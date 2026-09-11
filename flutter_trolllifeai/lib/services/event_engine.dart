// 事件引擎：标记语言解析 + 属性结算 + 成就判定 + 逐年推进。
//
// 这是游戏的规则中心，所有数值平衡常量集中在文件顶部的 _Balance 类，
// 页面与 GameProvider 只调用引擎，不自己算数值。

import 'dart:math';

import '../models/asset_state.dart';
import '../models/character.dart';
import '../models/life_event.dart';
import '../models/pet.dart';
import '../models/relation.dart';
import '../models/skill.dart';
import 'data_loader.dart';

// ---------------------------------------------------------------------------
// 数值平衡常量
// ---------------------------------------------------------------------------

/// 全部可调数值集中在这里
class _Balance {
  const _Balance._();

  /// 财富上限基数：上限 = 300000 × 城市财富系数
  static const int wealthCapBase = 300000;

  /// 每个命中技能的加成
  static const double skillBonusPerSkill = 0.07;

  /// 技能加成上限
  static const double skillBonusCap = 0.35;

  /// 罪恶值达到该值开始有被捕风险
  static const int arrestSinThreshold = 60;

  /// 成瘾值达到该值开始有「成瘾发作」风险
  static const int addictionThreshold = 60;

  /// 每年最多抽取的事件数
  static const int maxEventsPerYear = 2;

  /// 债务年利率（相对负债总额）
  static const double debtInterestRate = 0.03;

  /// 年利息上限，避免利滚利把负债堆到天文数字
  static const int debtInterestCap = 8000;

  /// 负债硬上限：达到后触发债务清算（破产），资产被拿去抵债
  static const int debtHardLimit = 1500000;

  /// 债务清算时豁免的金额
  static const int debtWriteOff = 1000000;

  /// 每年用于还债的收入比例
  static const double debtRepayRatio = 0.3;

  /// 每年成瘾自然加深的幅度
  static const int addictionYearlyGrowth = 2;
}

// ---------------------------------------------------------------------------
// 事件解析结果载体
// ---------------------------------------------------------------------------

/// 一个【...】标记解析后的结构化结果
class ParsedMarker {
  /// 一级键，例如「习得」「关系」「宠物」
  final String kind;

  /// 冒号分隔后的全部参数
  final List<String> params;

  const ParsedMarker(this.kind, this.params);

  /// 第一个参数（没有则空串）
  String get first => params.isEmpty ? '' : params[0];

  /// 第二个参数（没有则空串）
  String get second => params.length < 2 ? '' : params[1];

  /// 参数转 int
  int get intValue => int.tryParse(first.trim()) ?? 0;

  /// 原始标记文本（带【】）
  String get rawText {
    final StringBuffer buffer = StringBuffer('【');
    buffer.write(kind);
    for (final String p in params) {
      buffer.write(':');
      buffer.write(p);
    }
    buffer.write('】');
    return buffer.toString();
  }

  @override
  String toString() => rawText;
}

/// 选项的全部解析结果
class ParsedChoice {
  /// 原文（含标记）
  final String rawText;

  /// 剔除标记后的展示文本
  final String displayText;

  /// 解析出的标记列表
  final List<ParsedMarker> markers;

  const ParsedChoice({
    required this.rawText,
    required this.displayText,
    required this.markers,
  });

  /// 是否含有某个一级键的标记
  bool has(String kind) => markers.any((ParsedMarker m) => m.kind == kind);
}

/// 一次选择产生的完整结果
class EventOutcome {
  /// 展示给玩家的一段话（选项 desc 去标记后的文本）
  final String text;

  /// 实际生效的属性变化
  final StatDelta delta;

  /// 标记产生的提示（「学会技能：编程」等）
  final List<String> messages;

  /// 本次选择新解锁的成就名
  final List<String> unlockedAchievements;

  /// 本次选择是否直接导致死亡
  final bool died;

  /// 死亡原因
  final String deathReason;

  /// 选择后的判定结果文案（成功 / 失败 / 命中技能加成）
  final String judgeText;

  const EventOutcome({
    required this.text,
    required this.delta,
    this.messages = const <String>[],
    this.unlockedAchievements = const <String>[],
    this.died = false,
    this.deathReason = '',
    this.judgeText = '',
  });
}

/// 某一年的推进计划：被动变化先算好，事件交给界面逐个弹窗
class YearPlan {
  /// 推进后的年龄
  final int age;

  /// 被动日志（年代、漂移、收入、宠物与关系变化）
  final List<String> passiveLogs;

  /// 被动属性变化（漂移 + 城市修正 + 收入财富）
  final Map<AttributeKey, int> passiveDelta;

  /// 需要先于普通事件弹出的强制事件（被捕 / 成瘾发作 / 出狱）
  final List<LifeEvent> forcedEvents;

  /// 普通剧本事件队列（最多 2 条）
  final List<LifeEvent> events;

  /// 该年是否处于服刑期（服刑期间没有收入，只走时间）
  final bool imprisoned;

  /// 该年收入
  final int income;

  const YearPlan({
    required this.age,
    required this.passiveLogs,
    required this.passiveDelta,
    required this.forcedEvents,
    required this.events,
    this.imprisoned = false,
    this.income = 0,
  });

  /// 该年是否有事件需要玩家处理
  bool get hasAnything =>
      forcedEvents.isNotEmpty || events.isNotEmpty || passiveLogs.isNotEmpty;
}

/// 年度收尾结果
class YearSummary {
  /// 收尾提示（「你这一生结束了」等）
  final List<String> messages;

  /// 收尾时新解锁的成就
  final List<String> unlockedAchievements;

  /// 是否死亡
  final bool died;

  /// 死亡原因
  final String deathReason;

  const YearSummary({
    this.messages = const <String>[],
    this.unlockedAchievements = const <String>[],
    this.died = false,
    this.deathReason = '',
  });
}

// ---------------------------------------------------------------------------
// 事件引擎
// ---------------------------------------------------------------------------

/// 事件引擎：无状态（除随机数与已抽事件记录），所有方法都以 Character 为参数
class EventEngine {
  /// 随机源（可注入种子，便于复现问题）
  final Random random;

  /// 剧本数据
  final GameDataBundle data;

  /// 本局已经抽过的事件原始标题集合，避免同一条事件反复出现
  final Set<String> _firedKeys = <String>{};

  /// 技能 id → 关键词列表（命中事件文本则给成功率加成）
  static const Map<String, List<String>> skillKeywords =
      <String, List<String>>{
    'programming': <String>['代码', '编程', '互联网', '程序', '软件', 'AI', '开发', '算法'],
    'cooking': <String>['做饭', '厨', '餐饮', '菜', '食堂', '小吃', '饭馆'],
    'painting': <String>['画', '美术', '绘画', '设计', '插画'],
    'music': <String>['音乐', '唱歌', '乐队', '演出', '主播', '直播'],
    'foreign_language': <String>['外语', '英语', '留学', '出国', '外企', '移民', '翻译'],
    'medical': <String>['医院', '手术', '生病', '治疗', '医', '病', '体检'],
    'sport': <String>['体育', '运动', '比赛', '跑步', '篮球', '足球', '健身'],
    'business': <String>['创业', '投资', '生意', '谈判', '公司', '融资', '做生意'],
    'photography': <String>['摄影', '拍照', '相机', '短视频', '自媒体', '镜头'],
    'car_repair': <String>['汽修', '修车', '汽车', '修理', '技师'],
    'driving': <String>['司机', '驾驶', '外卖', '网约车', '开车', '货运', '骑手'],
    'finance': <String>['理财', '股票', '基金', '投资', '金融', '存款', '收益'],
    'law': <String>['官司', '法律', '律师', '诉讼', '维权', '合同'],
    'nursing': <String>['护理', '护士', '照顾', '病房', '养老'],
    'teaching': <String>['教师', '老师', '教育', '讲课', '培训', '考试', '补习'],
    'hospitality': <String>['酒店', '餐饮', '服务员', '前台', '民宿', '客栈'],
    'ecommerce': <String>['电商', '淘宝', '网店', '带货', '直播', '快递', '店铺'],
    'writing': <String>['写作', '写书', '小说', '文案', '回忆录', '编辑', '稿费'],
    'barber': <String>['理发', '美发', '剪头', '发廊'],
    'welding': <String>['电焊', '焊工', '工地', '技工', '工厂', '车间'],
    'first_aid': <String>['急救', '救人', '意外', '受伤', '抢救'],
    'budgeting': <String>['记账', '省钱', '预算', '开销', '攒钱'],
    'gardening': <String>['园艺', '种花', '种菜', '院子', '盆栽'],
    'pet_care': <String>['宠物', '猫', '狗', '流浪', '兽医'],
    'makeup': <String>['化妆', '造型', '美妆', '颜值'],
    'fitness': <String>['健身', '锻炼', '体能', '跑步', '瑜伽'],
    'meditation': <String>['冥想', '静坐', '禅', '放松', '心理咨询'],
    'self_defense': <String>['防身', '打架', '暴力', '冲突', '抢', '抢劫'],
    'negotiation_life': <String>['砍价', '谈判', '纠纷', '讨价', '协商', '和解'],
  };

  EventEngine({required this.data, Random? random})
      : random = random ?? Random();

  /// 清理本局事件记录（转世后调用）
  void resetFired() {
    _firedKeys.clear();
  }

  // -----------------------------------------------------------------------
  // 标记解析
  // -----------------------------------------------------------------------

  /// 解析一段文本里的全部标记
  static List<ParsedMarker> parseMarkers(String text) {
    final List<ParsedMarker> out = <ParsedMarker>[];
    for (final String inner in LifeEventMarker.rawMarkers(text)) {
      final List<String> parts = inner.split(':');
      if (parts.isEmpty) continue;
      final String kind = parts[0].trim();
      if (kind.isEmpty) continue;
      final List<String> params = <String>[];
      for (int i = 1; i < parts.length; i++) {
        params.add(parts[i].trim());
      }
      out.add(ParsedMarker(kind, params));
    }
    return out;
  }

  /// 解析一个选项
  static ParsedChoice parseChoice(LifeEventChoice choice) {
    return ParsedChoice(
      rawText: choice.rawDesc,
      displayText: choice.displayDesc,
      markers: parseMarkers(choice.rawDesc),
    );
  }

  // -----------------------------------------------------------------------
  // 事件筛选
  // -----------------------------------------------------------------------

  /// 按年龄与年代筛选可用事件
  List<LifeEvent> filterEvents(Character c) {
    return data.events.where((LifeEvent e) {
      if (e.forced) return false;
      if (!e.matchAge(c.age)) return false;
      if (!e.matchEra(c.era)) return false;
      if (_firedKeys.contains(e.rawTitle)) return false;
      return true;
    }).toList();
  }

  /// 抽取本年度的事件：优先年代限定事件，其次普通事件；
  /// 年代限定事件每世只出现一次（用 rawTitle 去重）。
  List<LifeEvent> pickEvents(Character c, {int maxCount = _Balance.maxEventsPerYear}) {
    final List<LifeEvent> pool = filterEvents(c);
    if (pool.isEmpty) return <LifeEvent>[];

    final List<LifeEvent> eraLocked =
        pool.where((LifeEvent e) => e.eraLimit.isNotEmpty).toList();
    final List<LifeEvent> general =
        pool.where((LifeEvent e) => e.eraLimit.isEmpty).toList();

    final List<LifeEvent> picked = <LifeEvent>[];

    // 年代事件：如果这个年代还有没看过的专属事件，每年给 1 条
    if (eraLocked.isNotEmpty && !c.eraEventsSeen.contains(c.era)) {
      final LifeEvent chosen = eraLocked[random.nextInt(eraLocked.length)];
      picked.add(chosen);
      _firedKeys.add(chosen.rawTitle);
      c.eraEventsSeen.add(c.era);
    }

    // 普通事件补齐
    final List<LifeEvent> rest = List<LifeEvent>.from(general)
      ..shuffle(random);
    for (final LifeEvent e in rest) {
      if (picked.length >= maxCount) break;
      if (picked.any((LifeEvent p) => p.rawTitle == e.rawTitle)) continue;
      picked.add(e);
      _firedKeys.add(e.rawTitle);
    }

    // 清洗事件池：内存控制，避免长寿命局无限增长
    if (_firedKeys.length > 400) {
      final List<String> kept = _firedKeys.toList().sublist(200);
      _firedKeys.clear();
      _firedKeys.addAll(kept);
    }
    return picked;
  }

  // -----------------------------------------------------------------------
  // 成功率
  // -----------------------------------------------------------------------

  /// 计算事件成功率加成：命中的技能各 +7%，最高 +35%；幸运值最高再加 10%
  double successBonus(Character c, LifeEvent event) {
    final String text = event.allText;
    int hits = 0;
    for (final String skillId in c.skills) {
      final List<String>? words = skillKeywords[skillId];
      if (words == null) continue;
      for (final String w in words) {
        if (text.contains(w)) {
          hits++;
          break;
        }
      }
    }
    double bonus = hits * _Balance.skillBonusPerSkill;
    if (bonus > _Balance.skillBonusCap) bonus = _Balance.skillBonusCap;

    // 幸运值：50 为基准，每 5 点 ±1%，范围 -10% ~ +10%
    final int luck = c.attr(AttributeKey.luck);
    double luckBonus = (luck - 50) / 500.0;
    if (luckBonus > 0.10) luckBonus = 0.10;
    if (luckBonus < -0.10) luckBonus = -0.10;

    return bonus + luckBonus;
  }

  // -----------------------------------------------------------------------
  // 对外复用的结算入口（主动行动 / 关系互动 / AI 剧情共用同一套数值规则）
  // -----------------------------------------------------------------------

  /// 应用一组属性变化（含上下限裁剪），返回实际生效的变化
  Map<AttributeKey, int> applyDeltaClamped(Character c, StatDelta delta) {
    return _applyRawDelta(c, delta.values, <String>[]);
  }

  /// 把「成瘾值」属性与成瘾表同步（取平均值）
  void syncAddictionAttribute(Character c) {
    _syncAddictionAttr(c);
  }

  /// 最严重的成瘾名（戒瘾治疗随机挑目标时使用）
  String worstAddictionName(Character c) {
    return _worstAddictionName(c);
  }

  /// 新增或加强一段关系：同名存活关系只加好感；
  /// 传 spouse 时会先把恋人升级为婚姻（与标记版逻辑保持一致）
  Relation? addOrStrengthenRelation(
    Character c,
    RelationType type,
    String name,
  ) {
    final String target = name.trim();
    if (target.isEmpty) return null;
    for (final Relation r in c.relations) {
      if (r.name == target && r.alive) {
        r.adjustFavor(8 + random.nextInt(13));
        return r;
      }
    }
    if (type == RelationType.spouse) {
      for (final Relation r in c.relations) {
        if (r.alive && r.type == RelationType.lover) {
          r.type = RelationType.spouse;
          c.everMarried = true;
          return r;
        }
      }
      c.everMarried = true;
    }
    final Relation created = Relation(
      name: target,
      type: type,
      favor: 55 + random.nextInt(16),
      startAge: c.age,
    );
    c.relations.add(created);
    return created;
  }

  /// 当前年收入预估（主动行动「加班赚钱」与 AI 提示词复用）
  int estimatedYearlyIncome(Character c) {
    return _computeIncome(c, c.age);
  }

  /// 当前月薪预估：年收入 / 12
  int estimatedMonthlySalary(Character c) {
    return (estimatedYearlyIncome(c) / 12).round();
  }

  // -----------------------------------------------------------------------
  // 逐年推进
  // -----------------------------------------------------------------------

  /// 生成某一年度的推进计划（只计算被动变化与事件队列，不改动属性）
  ///
  /// 属性改动的应用顺序由 GameProvider 控制：
  ///   applyPassive → 强制事件 → 普通事件 → finalizeYear
  YearPlan planYear(Character c) {
    final List<String> logs = <String>[];
    final Map<AttributeKey, int> delta = <AttributeKey, int>{};
    final List<LifeEvent> forced = <LifeEvent>[];

    final int newAge = c.age + 1;

    // 1. 服刑期：跳过年份，没有收入
    if (c.inPrison) {
      final int left = c.jailYearsLeft - 1;
      logs.add('你在监狱里度过了第 ${c.totalJailYears + 1} 年，'
          '墙外的世界与自己无关。');
      if (left <= 0) {
        forced.add(LifeEvent.release(c.totalJailYears + 1));
      }
      return YearPlan(
        age: newAge,
        passiveLogs: logs,
        passiveDelta: delta,
        forcedEvents: forced,
        events: <LifeEvent>[],
        imprisoned: true,
      );
    }

    // 2. 自然漂移
    final Map<AttributeKey, int> drift = naturalDrift(newAge, c);
    drift.forEach((AttributeKey k, int v) {
      delta[k] = (delta[k] ?? 0) + v;
    });

    // 3. 城市压力修正
    if (c.cityStressModifier != 0) {
      delta[AttributeKey.stress] =
          (delta[AttributeKey.stress] ?? 0) + c.cityStressModifier;
    }

    // 4. 天赋被动：睡眠质量王每年恢复健康，健身技能小幅回血
    if (c.talents.contains('睡眠质量王')) {
      delta[AttributeKey.health] = (delta[AttributeKey.health] ?? 0) + 2;
      delta[AttributeKey.stress] = (delta[AttributeKey.stress] ?? 0) - 1;
    }
    if (c.skills.contains('fitness')) {
      delta[AttributeKey.health] = (delta[AttributeKey.health] ?? 0) + 1;
    }
    if (c.skills.contains('meditation')) {
      delta[AttributeKey.stress] = (delta[AttributeKey.stress] ?? 0) - 2;
    }
    if (c.skills.contains('gardening')) {
      delta[AttributeKey.stress] = (delta[AttributeKey.stress] ?? 0) - 1;
    }

    // 5. 收入与支出
    int income = _computeIncome(c, newAge);
    // 主动行动「休息放松」：当年收入减半（标记用后即清）
    if (c.halfIncomeYear) {
      c.halfIncomeYear = false;
      income = (income * 0.5).round();
      logs.add('这一年你在休息放松，收入减半。');
    }
    if (income != 0) {
      delta[AttributeKey.wealth] = (delta[AttributeKey.wealth] ?? 0) + income;
    }
    final int livingCost = _computeLivingCost(c, newAge);
    if (livingCost != 0) {
      delta[AttributeKey.wealth] = (delta[AttributeKey.wealth] ?? 0) - livingCost;
      logs.add('这一年生活开销约 ${_money(livingCost)}。');
    }

    // 5.1 手头宽裕时自动还债（最多用掉 30% 的收入，且不能把现金还成负数）
    if (c.assets.debt > 0 && income > 0) {
      final int projectedCash =
          c.assets.cash + (delta[AttributeKey.wealth] ?? 0);
      if (projectedCash > 0) {
        int repay = (income * _Balance.debtRepayRatio).round();
        if (repay > c.assets.debt) repay = c.assets.debt;
        if (repay > projectedCash) repay = projectedCash;
        if (repay > 0) {
          c.assets.debt -= repay;
          delta[AttributeKey.wealth] =
              (delta[AttributeKey.wealth] ?? 0) - repay;
          logs.add('你抽出 ${_money(repay)} 还了一部分债。');
        }
      }
    }

    // 6. 债务利息（有上限，不会利滚利到天文数字）
    if (c.assets.debt > 0) {
      int interest = (c.assets.debt * _Balance.debtInterestRate).round();
      if (interest > _Balance.debtInterestCap) {
        interest = _Balance.debtInterestCap;
      }
      if (interest > 0) {
        delta[AttributeKey.wealth] =
            (delta[AttributeKey.wealth] ?? 0) - interest;
        logs.add('债务利息滚了 ${_money(interest)}，压力又重了一点。');
        delta[AttributeKey.stress] = (delta[AttributeKey.stress] ?? 0) + 2;
      }
    }

    // 7. 成瘾与罪恶的自然变化
    final Map<String, int> addictionDrift = _addictionDrift(c, newAge);
    addictionDrift.forEach((String name, int v) {
      if (v == 0) return;
      delta[AttributeKey.addiction] =
          (delta[AttributeKey.addiction] ?? 0) + v;
      logs.add('$name ${v > 0 ? '又重了' : '轻了一点'}。');
    });

    // 7.1 安分守己的日子会让罪恶值慢慢淡下去
    const List<String> sinEasingCareers = <String>[
      '程序员',
      '教师',
      '国企职员',
      '设备技师',
      '汽修工',
      '工人',
      '普工',
      '骑手',
      '主播',
      '建筑工',
    ];
    if (c.attr(AttributeKey.sin) > 0 &&
        c.hasJob &&
        !c.unemployed &&
        sinEasingCareers.contains(c.career)) {
      delta[AttributeKey.sin] = (delta[AttributeKey.sin] ?? 0) - 2;
    }

    // 8. 健康风险：低健康值每年掉得更快
    final int health = c.attr(AttributeKey.health) + (delta[AttributeKey.health] ?? 0);
    if (health <= 30) {
      delta[AttributeKey.health] = (delta[AttributeKey.health] ?? 0) - 1;
    }

    // 9. 罪恶值带来的被捕风险（只有罪恶值很高时才会被抓，最高约 60%）
    if (c.attr(AttributeKey.sin) >= _Balance.arrestSinThreshold) {
      final double chance = (0.05 +
              (c.attr(AttributeKey.sin) - _Balance.arrestSinThreshold) / 100.0)
          .clamp(0.05, 0.6);
      if (random.nextDouble() < chance) {
        final int years = 2 + random.nextInt(4);
        forced.add(LifeEvent.arrest(years));
      }
    }

    // 10. 成瘾发作
    if (c.attr(AttributeKey.addiction) >= _Balance.addictionThreshold) {
      final double chance =
          ((c.attr(AttributeKey.addiction) - _Balance.addictionThreshold) / 120.0 +
                  0.12)
              .clamp(0.0, 0.55);
      if (random.nextDouble() < chance) {
        final String name = _worstAddictionName(c);
        forced.add(LifeEvent.addictionBreakdown(name));
        c.everWithdrawal = true;
      }
    }

    // 11. 年龄节点日志
    if (newAge == 18) logs.add('你成年了，人生正式开始自己负责。');
    if (newAge == 60 && !c.retired) {
      logs.add('你到了退休的年纪。');
    }

    // 12. 宠物生命周期
    logs.addAll(_petYearlyNotes(c));

    // 13. 关系自然变化
    logs.addAll(_relationYearlyNotes(c));

    // 14. 普通事件
    final List<LifeEvent> events = pickEvents(c);

    return YearPlan(
      age: newAge,
      passiveLogs: logs,
      passiveDelta: delta,
      forcedEvents: forced,
      events: events,
      income: income,
    );
  }

  /// 应用某一年的被动变化到角色（含上限、下限裁剪）
  List<String> applyPassive(Character c, YearPlan plan) {
    final List<String> notes = <String>[];

    // 年龄推进
    c.age = plan.age;

    // 每年重置主动行动点：服刑期间没有行动自由
    c.actionPoints = plan.imprisoned ? 0 : 1;

    // 服刑期：只走时间
    if (plan.imprisoned) {
      c.jailYearsLeft = c.jailYearsLeft - 1;
      if (c.jailYearsLeft < 0) c.jailYearsLeft = 0;
      c.totalJailYears += 1;
      for (final String l in plan.passiveLogs) {
        c.log(l, kind: LogKind.bad);
      }
      if (c.jailYearsLeft == 0) {
        c.status = LifeStatus.alive;
      }
      return notes;
    }

    // 属性变化
    final Map<AttributeKey, int> applied =
        _applyRawDelta(c, plan.passiveDelta, notes);

    // 财富上限：城市系数决定的上限，同时限制当年收入
    final int cap = ( _Balance.wealthCapBase * c.wealthCapFactor).round();
    if (c.attr(AttributeKey.wealth) > cap) {
      c.setAttr(AttributeKey.wealth, cap);
      notes.add('你的财富已经触到这座城市的天花板（${_money(cap)}）。');
    }

    // 记录日志
    if (plan.income != 0) {
      c.log('这一年收入 ${_money(plan.income)}。', kind: LogKind.money);
    }
    for (final String l in plan.passiveLogs) {
      c.log(l);
    }
    final String deltaText = _deltaText(applied);
    if (deltaText.isNotEmpty) {
      c.log('自然变化：$deltaText');
    }

    // 现金不足以覆盖支出时，转化为负债（不能超过信用额度）
    if (c.assets.cash < 0) {
      final int gap = -c.assets.cash;
      c.assets.cash = 0;
      final int limit = _creditLimit(c, c.age);
      final int borrow = (limit - c.assets.debt).clamp(0, gap);
      if (borrow > 0) {
        c.assets.addDebt(borrow);
        notes.add('现金不够用，欠下了 ${_money(borrow)} 的外债。');
        c.log('你不得不借了 ${_money(borrow)} 才熬过这一年。', kind: LogKind.bad);
      }
      if (borrow < gap) {
        c.setAttr(
          AttributeKey.happiness,
          (c.attr(AttributeKey.happiness) - 4).clamp(0, 100),
        );
        notes.add('借不到更多钱了，日子紧巴巴地过。');
      }
      c.setAttr(AttributeKey.wealth, 0);
    }

    // 负债硬上限：达到后强制债务清算（房产车辆抵债 + 豁免一部分）
    if (c.assets.debt >= _Balance.debtHardLimit) {
      final int before = c.assets.debt;
      final int propertyValue = c.assets.propertyValue;
      final int vehicleValue = c.assets.vehicleValue;
      c.assets.properties.clear();
      c.assets.vehicles.clear();
      final int after = before - propertyValue - vehicleValue - _Balance.debtWriteOff;
      c.assets.debt = after < 0 ? 0 : after;
      c.setAttr(
        AttributeKey.happiness,
        (c.attr(AttributeKey.happiness) - 10).clamp(0, 100),
      );
      c.setAttr(
        AttributeKey.stress,
        (c.attr(AttributeKey.stress) + 10).clamp(0, 100),
      );
      notes.add('债务被强制清算：房产车辆抵债后，剩下 ${_money(c.assets.debt)} 债务');
      c.log('法院强制执行，房子和车都没了，剩下的债慢慢还。', kind: LogKind.bad);
    }

    return notes;
  }

  /// 年度收尾：健康判定、寿命判定、成就判定
  YearSummary finalizeYear(Character c) {
    final List<String> messages = <String>[];
    final int health = c.attr(AttributeKey.health);

    // 健康值归零 → 死亡
    if (health <= 0) {
      c.status = LifeStatus.dead;
      c.deathAge = c.age;
      c.deathReason = '健康值归零，身体再也撑不住了';
      c.log(c.deathReason, kind: LogKind.bad);
      return YearSummary(
        messages: <String>[c.deathReason],
        unlockedAchievements: const <String>[],
        died: true,
        deathReason: c.deathReason,
      );
    }

    // 到达寿命上限 → 寿终正寝
    if (c.age >= c.lifespan) {
      c.status = LifeStatus.dead;
      c.deathAge = c.age;
      c.deathReason = '活到了 ${c.age} 岁，在睡梦中安然离世';
      if (health > 30) c.achievedNaturalDeath = true;
      c.log(c.deathReason, kind: LogKind.system);
      return YearSummary(
        messages: <String>[c.deathReason],
        unlockedAchievements: const <String>[],
        died: true,
        deathReason: c.deathReason,
      );
    }

    // 计数器维护
    if (health <= 20) {
      c.lowHealthYears += 1;
    } else {
      c.lowHealthYears = 0;
    }
    if (health <= 10) c.everCriticalHealth = true;
    if (c.attr(AttributeKey.sin) >= 40) c.everHighSin = true;
    if (c.attr(AttributeKey.sin) <= 5) {
      if (c.everJailed) c.cleanYearsAfterJail += 1;
    } else {
      c.cleanYearsAfterJail = 0;
    }
    c.trimLogs();

    return YearSummary();
  }

  /// 应用一次玩家选择
  EventOutcome applyChoice(Character c, LifeEvent event, int choiceIndex) {
    final List<String> messages = <String>[];
    final List<String> unlocked = <String>[];

    if (choiceIndex < 0 || choiceIndex >= event.choices.length) {
      return const EventOutcome(text: '', delta: StatDelta.zero);
    }
    final LifeEventChoice choice = event.choices[choiceIndex];
    final ParsedChoice parsed = parseChoice(choice);

    // 1. 成功判定：基础成功率 72%，命中的技能与幸运值再往上加（最高 +45%）。
    //    成功了收益按剧本全额结算并吃到加成，失败则打七折。
    //    强制事件（入狱、成瘾发作等）不做随机判定，保证剧情按剧本走。
    final double bonus = successBonus(c, event);
    final double successChance = (0.72 + bonus).clamp(0.05, 0.99);
    final bool success = event.forced || random.nextDouble() < successChance;
    double factor = 1.0;
    String judgeText = '';
    if (!event.forced) {
      if (success && bonus > 0) {
        factor = 1.0 + bonus;
        judgeText = '技能与运气让结果比预想更好（加成 +${(bonus * 100).round()}%）';
      } else if (!success) {
        factor = 0.7;
        judgeText = '这一次运气不在你这边，收获打了折扣。';
      }
    }

    // 2. 属性结算
    final StatDelta scaled = factor == 1.0 ? choice.attrChange : choice.attrChange.scaled(factor);
    final Map<AttributeKey, int> applied = _applyRawDelta(c, scaled.values, messages);

    // 3. 标记结算
    final List<String> markerMsgs = applyMarkers(c, parsed.markers);
    messages.addAll(markerMsgs);

    // 4. 财富一次性暴涨记录（用于「一夜暴富」成就）
    final int wealthGain = applied[AttributeKey.wealth] ?? 0;
    if (wealthGain > c.maxSingleWealthGain) {
      c.maxSingleWealthGain = wealthGain;
    }
    if (wealthGain < 0 && c.everInvested) {
      final int loss = -wealthGain;
      if (loss > c.maxSingleInvestLoss) c.maxSingleInvestLoss = loss;
    }

    // 5. 结果文本
    final StringBuffer text = StringBuffer();
    if (parsed.displayText.isNotEmpty) {
      text.write(parsed.displayText);
    } else {
      text.write('你选择了「${choice.optionText}」。');
    }
    if (judgeText.isNotEmpty) {
      text.write('\n');
      text.write(judgeText);
    }

    final String deltaText = _deltaText(applied);
    if (deltaText.isNotEmpty) {
      c.log('${event.title}：$deltaText', kind: LogKind.normal);
    }
    if (parsed.displayText.isNotEmpty) {
      c.log(parsed.displayText, kind: LogKind.normal);
    }
    for (final String m in messages) {
      c.log(m, kind: LogKind.system);
    }

    // 6. 死亡判定
    if (c.attr(AttributeKey.health) <= 0) {
      c.status = LifeStatus.dead;
      c.deathAge = c.age;
      c.deathReason = '一次意外让身体彻底垮掉，你在 ${c.age} 岁离开了';
      c.log(c.deathReason, kind: LogKind.bad);
      return EventOutcome(
        text: text.toString(),
        delta: StatDelta(applied),
        messages: messages,
        unlockedAchievements: unlocked,
        died: true,
        deathReason: c.deathReason,
        judgeText: judgeText,
      );
    }

    return EventOutcome(
      text: text.toString(),
      delta: StatDelta(applied),
      messages: messages,
      unlockedAchievements: unlocked,
      judgeText: judgeText,
    );
  }

  // -----------------------------------------------------------------------
  // 标记效果结算
  // -----------------------------------------------------------------------

  /// 把一组解析后的标记作用到角色，返回提示文本
  List<String> applyMarkers(Character c, List<ParsedMarker> markers) {
    final List<String> msgs = <String>[];
    for (final ParsedMarker m in markers) {
      msgs.addAll(_applyOneMarker(c, m));
    }
    return msgs;
  }

  /// 单个标记的结算逻辑
  List<String> _applyOneMarker(Character c, ParsedMarker m) {
    final List<String> msgs = <String>[];

    // 年代标记（80年代 / 年代:80）：只作为事件限定条件，不产生副作用
    if (LifeEventMarker.isEraMarker(m.kind) ||
        m.kind == '年代' ||
        m.kind == '年代限定') {
      return msgs;
    }

    switch (m.kind) {
      // ---------------- 技能 ----------------
      case '习得':
        final String id = m.first;
        final Skill? skill = data.skillIndex[id];
        if (id.isEmpty) break;
        if (c.skills.contains(id)) {
          msgs.add('技能更加熟练：${skill?.name ?? id}');
        } else {
          c.skills.add(id);
          msgs.add('学会技能：${skill?.name ?? id}');
          c.log('你掌握了${skill?.name ?? id}。', kind: LogKind.good);
        }
        break;

      // ---------------- 宠物 ----------------
      case '宠物':
        _addPet(c, m.first.isEmpty ? '猫' : m.first, msgs);
        break;
      case '宠物生病':
        final Pet? p = _firstAlivePet(c);
        if (p != null) {
          p.status = PetStatus.sick;
          p.adjustIntimacy(5);
          final int cost = 800 + random.nextInt(4200);
          c.assets.addCash(-cost);
          c.setAttr(AttributeKey.wealth, c.assets.cash);
          c.setAttr(
            AttributeKey.happiness,
            (c.attr(AttributeKey.happiness) - 3).clamp(0, 100),
          );
          c.setAttr(
            AttributeKey.stress,
            (c.attr(AttributeKey.stress) + 3).clamp(0, 100),
          );
          msgs.add('${p.name}生病了，看病花了 ${_money(cost)}');
          c.log('${p.name}生病了，你连夜带它去了医院。', kind: LogKind.bad);
        }
        break;
      case '宠物走失':
        final Pet? p = _firstAlivePet(c);
        if (p != null) {
          p.status = PetStatus.lost;
          c.setAttr(
            AttributeKey.happiness,
            (c.attr(AttributeKey.happiness) - 8).clamp(0, 100),
          );
          msgs.add('${p.name}走失了');
          c.log('${p.name}跑出去就没再回来。', kind: LogKind.bad);
        }
        break;
      case '宠物繁育':
        final Pet? p = _firstAlivePet(c);
        if (p != null) {
          p.hasOffspring = true;
          final String babyName = '${p.species}崽·${_randomPetName()}';
          c.pets.add(
            Pet(
              name: babyName,
              species: p.species,
              age: 0,
              lifespan: p.lifespan,
              intimacy: 70,
            ),
          );
          c.setAttr(
            AttributeKey.happiness,
            (c.attr(AttributeKey.happiness) + 6).clamp(0, 100),
          );
          msgs.add('${p.name}繁育出了$babyName');
          c.log('家里又多了一只小$babyName。', kind: LogKind.good);
        }
        break;
      case '宠物离世':
        final Pet? p = _firstAlivePet(c);
        if (p != null) {
          p.status = PetStatus.dead;
          c.setAttr(
            AttributeKey.happiness,
            (c.attr(AttributeKey.happiness) - 10).clamp(0, 100),
          );
          c.setAttr(
            AttributeKey.stress,
            (c.attr(AttributeKey.stress) + 5).clamp(0, 100),
          );
          msgs.add('${p.name}离世了');
          c.log('${p.name}在你怀里安静地走了。', kind: LogKind.bad);
        }
        break;

      // ---------------- 关系 ----------------
      case '关系':
        _addRelation(c, m, msgs);
        break;
      case '关系结束':
        final String name = m.first;
        for (final Relation r in c.relations) {
          if (r.name == name && r.alive) {
            r.alive = false;
            if (r.type == RelationType.friend) {
              c.oldFriends.add(name);
            }
            if (r.type == RelationType.spouse) c.everMarried = true;
            msgs.add('与$name 的关系结束了');
            c.log('你和$name 从此不再联系。', kind: LogKind.bad);
            break;
          }
        }
        break;

      // ---------------- 职业 ----------------
      case '职业':
        final String title = m.first;
        if (title.isNotEmpty) {
          c.career = title;
          c.hasJob = true;
          c.unemployed = false;
          c.retired = false;
          msgs.add('职业：$title');
          c.log('你成了$title。', kind: LogKind.good);
        }
        break;
      case '升职':
        c.careerLevel += 1;
        c.hasJob = true;
        c.unemployed = false;
        c.setAttr(
          AttributeKey.happiness,
          (c.attr(AttributeKey.happiness) + 4).clamp(0, 100),
        );
        msgs.add('升职了（职级 ${c.careerLevel}）');
        c.log('你在${c.career}这条路上升了一级。', kind: LogKind.good);
        break;
      case '失业':
        c.unemployed = true;
        c.hasJob = false;
        c.careerLevel = 0;
        c.setAttr(
          AttributeKey.happiness,
          (c.attr(AttributeKey.happiness) - 8).clamp(0, 100),
        );
        c.setAttr(
          AttributeKey.stress,
          (c.attr(AttributeKey.stress) + 10).clamp(0, 100),
        );
        msgs.add('失业了');
        c.log('你被通知不用再来了。', kind: LogKind.bad);
        break;
      case '跳槽':
        c.hasJob = true;
        c.unemployed = false;
        c.careerLevel += 1;
        c.assets.addCash(6000 + random.nextInt(12000));
        c.setAttr(AttributeKey.wealth, c.assets.cash);
        msgs.add('跳槽成功，薪资提升');
        c.log('你换了东家，薪水涨了一截。', kind: LogKind.good);
        break;
      case '创业':
        c.everStartedBusiness = true;
        c.hasJob = true;
        c.unemployed = false;
        c.career = c.career == '无' ? '创业者' : '${c.career}·创业';
        c.assets.addCash(-(20000 + random.nextInt(60000)));
        c.setAttr(AttributeKey.wealth, c.assets.cash);
        c.setAttr(
          AttributeKey.stress,
          (c.attr(AttributeKey.stress) + 8).clamp(0, 100),
        );
        msgs.add('开始创业');
        c.log('你注册了自己的公司，开始了创业。', kind: LogKind.good);
        break;
      case '破产':
        c.unemployed = true;
        c.hasJob = false;
        final int lost = c.assets.cash > 0 ? c.assets.cash : 0;
        c.assets.cash = 0;
        c.assets.addDebt(30000 + random.nextInt(70000));
        c.setAttr(AttributeKey.wealth, c.assets.cash);
        c.setAttr(
          AttributeKey.happiness,
          (c.attr(AttributeKey.happiness) - 12).clamp(0, 100),
        );
        c.setAttr(AttributeKey.stress, (c.attr(AttributeKey.stress) + 15).clamp(0, 100));
        msgs.add('公司破产了（亏掉 ${_money(lost)}）');
        c.log('公司清算关门，你成了一身债的人。', kind: LogKind.bad);
        break;

      // ---------------- 法律 ----------------
      case '入狱':
        final int years = m.intValue > 0 ? m.intValue : 3;
        c.status = LifeStatus.inPrison;
        c.jailYearsLeft = years;
        c.everJailed = true;
        // 注意：累计服刑年数由每年推进时累加（见 applyPassive），这里不重复计数
        c.hasCriminalRecord = true;
        c.unemployed = true;
        c.hasJob = false;
        c.setAttr(AttributeKey.sin, (c.attr(AttributeKey.sin) - 10).clamp(0, 100));
        c.setAttr(
          AttributeKey.happiness,
          (c.attr(AttributeKey.happiness) - 10).clamp(0, 100),
        );
        msgs.add('被判刑 $years 年');
        c.log('法院判了你 $years 年。', kind: LogKind.bad);
        break;
      case '出狱':
        c.status = LifeStatus.alive;
        c.jailYearsLeft = 0;
        c.cleanYearsAfterJail = 0;
        c.setAttr(
          AttributeKey.happiness,
          (c.attr(AttributeKey.happiness) + 5).clamp(0, 100),
        );
        msgs.add('刑满出狱');
        c.log('你走出了监狱的大门。', kind: LogKind.system);
        break;
      case '案底':
        c.hasCriminalRecord = true;
        c.setAttr(AttributeKey.fame, (c.attr(AttributeKey.fame) - 5).clamp(0, 100));
        msgs.add('留下了案底');
        break;
      case '减刑':
        if (c.jailYearsLeft > 1) {
          c.jailYearsLeft -= 1;
          c.everCommuted = true;
          msgs.add('获得减刑一年');
          c.log('因为表现良好，你获得了减刑。', kind: LogKind.good);
        } else {
          c.everCommuted = true;
          c.status = LifeStatus.alive;
          c.jailYearsLeft = 0;
          msgs.add('获得减刑，提前释放');
          c.log('减刑批下来了，你提前走出了大门。', kind: LogKind.good);
        }
        break;

      // ---------------- 资产 ----------------
      case '买房':
        _buyHouse(c, msgs);
        break;
      case '买车':
        _buyCar(c, msgs);
        break;
      case '奢侈品':
        final int cost = 5000 + random.nextInt(45000);
        c.assets.addCash(-cost);
        c.assets.luxurySpent += cost;
        c.assets.luxuryCount += 1;
        c.setAttr(AttributeKey.wealth, c.assets.cash);
        c.setAttr(
          AttributeKey.happiness,
          (c.attr(AttributeKey.happiness) + 6).clamp(0, 100),
        );
        c.setAttr(AttributeKey.charm, (c.attr(AttributeKey.charm) + 2).clamp(0, 100));
        msgs.add('买了奢侈品，花掉 ${_money(cost)}');
        break;
      case '保险':
        c.assets.hasInsurance = true;
        c.assets.insuranceYears = 10;
        c.assets.addCash(-6000);
        c.setAttr(AttributeKey.wealth, c.assets.cash);
        msgs.add('买了保险');
        c.log('你给自己买了一份保险，心里踏实了一些。', kind: LogKind.normal);
        break;
      case '负债':
        final int amount = m.intValue > 0 ? m.intValue : 10000;
        c.assets.addDebt(amount);
        c.setAttr(AttributeKey.stress, (c.attr(AttributeKey.stress) + 4).clamp(0, 100));
        msgs.add('欠下 ${_money(amount)} 债务');
        c.log('你借了 ${_money(amount)}。', kind: LogKind.bad);
        break;
      case '还债':
        final int amount = m.intValue > 0 ? m.intValue : 10000;
        final int paid = c.assets.repay(amount);
        c.setAttr(AttributeKey.wealth, c.assets.cash);
        c.setAttr(AttributeKey.stress, (c.attr(AttributeKey.stress) - 3).clamp(0, 100));
        msgs.add('还债 ${_money(paid)}');
        c.log('你还掉了 ${_money(paid)} 的债。', kind: LogKind.good);
        break;

      // ---------------- 成瘾 ----------------
      case '成瘾':
        final String name = m.first;
        if (name.isNotEmpty) {
          final int add = 10 + random.nextInt(11);
          c.addictions[name] = ((c.addictions[name] ?? 0) + add).clamp(0, 100);
          final int total = c.addictions.values.fold(0, (int a, int b) => a + b);
          c.setAttr(
            AttributeKey.addiction,
            (total ~/ (c.addictions.length == 0 ? 1 : c.addictions.length))
                .clamp(0, 100),
          );
          msgs.add('染上$name（+$add）');
          c.log('你染上了$name。', kind: LogKind.bad);
        }
        break;
      case '戒断':
        final String name = m.first;
        if (name.isNotEmpty) {
          final int before = c.addictions[name] ?? 0;
          if (before >= 80) {
            c.log('你在戒断反应最痛苦的时候咬牙挺住了。', kind: LogKind.good);
          }
          final int cut = 25 + random.nextInt(31);
          c.addictions[name] = (before - cut).clamp(0, 100);
          _syncAddictionAttr(c);
          msgs.add('$name 减轻了 ${before - (c.addictions[name] ?? 0)}');
          c.log('你戒掉了一部分$name。', kind: LogKind.good);
        }
        break;

      default:
        // 未知标记：只记一条提示，不影响游戏运行（键名开放）
        msgs.add('未知标记【${m.rawText.replaceAll('【', '').replaceAll('】', '')}】已忽略');
        break;
    }

    return msgs;
  }

  /// 新增或加强一段关系
  void _addRelation(Character c, ParsedMarker m, List<String> msgs) {
    final RelationType type = RelationTypeX.fromKey(m.first);
    final String name = m.second.isNotEmpty ? m.second : m.first;
    if (name.isEmpty) return;

    for (final Relation r in c.relations) {
      if (r.name == name && r.alive) {
        final int gain = 8 + random.nextInt(13);
        r.adjustFavor(gain);
        msgs.add('与$name 关系更近了（+$gain）');
        return;
      }
    }

    // 配偶 / 恋人的互斥处理
    if (type == RelationType.spouse) {
      for (final Relation r in c.relations) {
        if (r.alive && r.type == RelationType.lover) {
          r.type = RelationType.spouse;
          c.everMarried = true;
          msgs.add('与${r.name} 结为夫妻');
          c.log('你和${r.name}结婚了。', kind: LogKind.good);
          return;
        }
      }
      c.everMarried = true;
    }

    final Relation relation = Relation(
      name: name,
      type: type,
      favor: 55 + random.nextInt(16),
      startAge: c.age,
    );
    c.relations.add(relation);
    msgs.add('新增${RelationTypeX.label(type)}：$name');
    c.log('你的生命里出现了${RelationTypeX.label(type)}$name。', kind: LogKind.good);
  }

  /// 收养 / 购买宠物
  void _addPet(Character c, String species, List<String> msgs) {
    final String name = '$species·${_randomPetName()}';
    final int life = c.skills.contains('pet_care')
        ? 15 + random.nextInt(5)
        : 12 + random.nextInt(5);
    c.pets.add(
      Pet(
        name: name,
        species: species,
        age: 0,
        lifespan: life,
        intimacy: 65,
      ),
    );
    c.setAttr(AttributeKey.happiness, (c.attr(AttributeKey.happiness) + 8).clamp(0, 100));
    msgs.add('收养了一只$name');
    c.log('你把$name 带回了家。', kind: LogKind.good);
  }

  /// 买房：价格与城市系数、年代相关
  void _buyHouse(Character c, List<String> msgs) {
    final int base = (400000 * c.wealthCapFactor).round();
    final int price = base + random.nextInt(base ~/ 2 + 1);
    c.assets.addCash(-price);
    c.assets.properties.add(
      PropertyAsset(
        cityName: c.cityName,
        price: price,
        value: price,
        boughtAge: c.age,
      ),
    );
    c.everBoughtHouse = true;
    c.setAttr(AttributeKey.wealth, c.assets.cash);
    c.setAttr(AttributeKey.happiness, (c.attr(AttributeKey.happiness) + 8).clamp(0, 100));
    msgs.add('在${c.cityName}买下一套房（${_money(price)}）');
    c.log('你在${c.cityName}买下了自己的房子。', kind: LogKind.good);
  }

  /// 买车
  void _buyCar(Character c, List<String> msgs) {
    final int price = 80000 + random.nextInt(220000);
    c.assets.addCash(-price);
    c.assets.vehicles.add(
      VehicleAsset(
        label: price > 200000 ? '中高档轿车' : '家用轿车',
        price: price,
        value: (price * 0.75).round(),
        boughtAge: c.age,
      ),
    );
    c.everBoughtCar = true;
    c.setAttr(AttributeKey.wealth, c.assets.cash);
    c.setAttr(AttributeKey.charm, (c.attr(AttributeKey.charm) + 2).clamp(0, 100));
    msgs.add('提了一辆车（${_money(price)}）');
    c.log('你提回了人生第一辆车。', kind: LogKind.good);
  }

  // -----------------------------------------------------------------------
  // 数值工具
  // -----------------------------------------------------------------------

  /// 应用一组属性变化，返回实际生效的变化（含上下限裁剪）
  Map<AttributeKey, int> _applyRawDelta(
    Character c,
    Map<AttributeKey, int> delta,
    List<String> notes,
  ) {
    final Map<AttributeKey, int> applied = <AttributeKey, int>{};
    delta.forEach((AttributeKey key, int value) {
      if (value == 0) return;
      final int before = c.attr(key);
      int after = before + value;

      switch (key) {
        case AttributeKey.health:
          after = after.clamp(0, 100);
          break;
        case AttributeKey.happiness:
        case AttributeKey.stress:
        case AttributeKey.addiction:
        case AttributeKey.sin:
        case AttributeKey.fame:
          after = after.clamp(0, 100);
          break;
        case AttributeKey.intelligence:
        case AttributeKey.constitution:
        case AttributeKey.charm:
        case AttributeKey.luck:
          after = after.clamp(0, 200);
          break;
        case AttributeKey.wealth:
          final int cap = (_Balance.wealthCapBase * c.wealthCapFactor).round();
          if (after > cap) {
            after = cap;
            notes.add('财富已经触顶（上限 ${_money(cap)}）');
          }
          if (after < -100000000) after = -100000000;
          break;
      }

      if (after == before) return;
      c.setAttr(key, after);
      applied[key] = after - before;

      // 财富同步到资产现金
      if (key == AttributeKey.wealth) {
        c.assets.cash = after;
      }
    });
    return applied;
  }

  /// 成瘾值属性和成瘾表同步（取平均值）
  void _syncAddictionAttr(Character c) {
    if (c.addictions.isEmpty) {
      c.setAttr(AttributeKey.addiction, 0);
      return;
    }
    final int total = c.addictions.values.fold(0, (int a, int b) => a + b);
    c.setAttr(AttributeKey.addiction, (total ~/ c.addictions.length).clamp(0, 100));
  }

  /// 自然漂移：按年龄段给出每年的基础变化
  Map<AttributeKey, int> naturalDrift(int age, Character c) {
    final Map<AttributeKey, int> d = <AttributeKey, int>{};
    int health = 0;
    int stress = 0;
    int happy = 0;

    if (age <= 6) {
      health = 2;
      happy = 1;
      stress = -3;
    } else if (age <= 17) {
      health = 2;
      happy = 1;
      stress = -2;
    } else if (age <= 35) {
      health = 1;
      stress = 0;
      happy = 0;
    } else if (age <= 55) {
      health = 0;
      stress = 1;
      happy = -1;
    } else if (age <= 70) {
      health = -1;
      stress = 0;
      happy = -1;
    } else {
      health = -3;
      stress = -1;
      happy = -1;
    }

    // 天赋影响
    if (c.talents.contains('长寿体质') && age > 55) health += 1;
    if (c.talents.contains('短命基因') && age > 45) health -= 1;
    if (c.talents.contains('抗压强者') && stress > 0) stress -= 1;
    if (c.talents.contains('玻璃心') && stress > 0) stress += 1;
    if (c.talents.contains('乐天派') && happy < 0) happy += 1;

    if (health != 0) d[AttributeKey.health] = health;
    if (stress != 0) d[AttributeKey.stress] = stress;
    if (happy != 0) d[AttributeKey.happiness] = happy;
    return d;
  }

  /// 每年收入：职业 + 城市 + 天赋共同决定，并受财富上限约束
  int _computeIncome(Character c, int age) {
    if (c.unemployed && !c.retired) return 0;
    if (c.retired) {
      // 退休金
      return (12000 * c.wealthCapFactor).round();
    }

    int base;
    if (age < 12) {
      // 童年：家里给的零花钱
      base = 2000;
    } else if (age < 16) {
      // 少年：偶尔打零工
      base = 6000;
    } else if (age < 18) {
      // 十六岁以后算半个劳动力
      base = (24000 * c.wealthCapFactor).round();
    } else if (c.career == '无' && !c.hasJob) {
      // 没有职业时的零工收入
      base = (30000 * c.wealthCapFactor).round();
    } else {
      base = (52000 * c.wealthCapFactor).round() + c.careerLevel * 15000;
      if (c.skills.contains('programming') || c.skills.contains('finance')) {
        base = (base * 1.15).round();
      }
      if (c.talents.contains('天生劳碌命')) base = (base * 1.25).round();
      if (c.talents.contains('晚熟之人') && age < 40) base = (base * 0.7).round();
      if (c.talents.contains('晚熟之人') && age >= 40) base = (base * 1.4).round();
      if (c.hasCriminalRecord) base = (base * 0.8).round();
    }

    // 财富上限限制年收入
    final int cap = (_Balance.wealthCapBase * c.wealthCapFactor).round();
    final int room = cap - c.attr(AttributeKey.wealth);
    if (room <= 0) return 0;
    return base > room ? room : base;
  }

  /// 每年生活开销：年龄越小由家庭承担的越多，城市越贵开销越高
  int _computeLivingCost(Character c, int age) {
    double scale = 1.0;
    if (age < 7) {
      scale = 0.15;
    } else if (age < 12) {
      scale = 0.25;
    } else if (age < 16) {
      scale = 0.35;
    } else if (age < 20) {
      scale = 0.55;
    } else if (age < 45) {
      scale = 0.7;
    } else if (age < 60) {
      scale = 0.75;
    } else {
      scale = 0.8;
    }

    double cost = 24000 * c.wealthCapFactor * scale;
    if (c.assets.properties.isNotEmpty) cost += 6000;
    if (c.assets.vehicles.isNotEmpty) cost += 8000;
    cost += c.activePets.length * 3000;
    cost += c.childCount * 6000;
    if (c.skills.contains('budgeting')) cost *= 0.85;
    if (c.skills.contains('cooking')) cost *= 0.95;
    return cost.round();
  }

  /// 信用额度：决定负债上限（童年几乎没有信用）
  int _creditLimit(Character c, int age) {
    if (age < 16) return 20000;
    int limit = (150000 * c.wealthCapFactor).round();
    if (c.hasJob || c.career != '无') limit += 100000;
    if (c.assets.properties.isNotEmpty) limit += 200000;
    if (c.hasCriminalRecord) limit = (limit * 0.6).round();
    if (limit < 20000) limit = 20000;
    return limit;
  }

  /// 成瘾值的年度漂移：仍然在瘾上的成瘾每年自然加深
  Map<String, int> _addictionDrift(Character c, int age) {
    final Map<String, int> out = <String, int>{};
    c.addictions.forEach((String name, int value) {
      if (value <= 0) return;
      // 天赋影响成瘾增长
      double growth = 1.0;
      if (c.talents.contains('抗瘾体质')) growth *= 0.5;
      if (c.talents.contains('赌徒本性') && name == '赌瘾') growth *= 2.0;
      if (c.talents.contains('网瘾少年') && name == '网瘾') growth *= 2.0;
      final int step = (_Balance.addictionYearlyGrowth * growth).round();
      out[name] = step < 1 ? 1 : step;
    });
    return out;
  }

  /// 宠物年度变化日志（年龄增长、生病、走失、离世）
  List<String> _petYearlyNotes(Character c) {
    final List<String> notes = <String>[];
    for (final Pet p in c.pets) {
      if (!p.isAlive) continue;
      p.age += 1;
      if (p.status == PetStatus.lost) {
        // 走失的宠物每年有 40% 概率被找回
        if (random.nextDouble() < 0.4) {
          p.status = PetStatus.normal;
          notes.add('${p.name}自己找回了家门口。');
        }
        continue;
      }

      // 生病概率：幼年与老年更高，宠物养护技能可以降低
      double sickChance = 0.05;
      if (p.age <= 1 || p.age >= p.lifespan - 3) sickChance = 0.18;
      if (c.skills.contains('pet_care')) sickChance *= 0.5;
      if (p.status == PetStatus.sick) {
        // 生病中：有 60% 概率康复
        if (random.nextDouble() < 0.6) {
          p.status = PetStatus.normal;
          notes.add('${p.name}的病好了。');
        } else {
          final int cost = 1000 + random.nextInt(3000);
          c.assets.addCash(-cost);
          c.setAttr(AttributeKey.wealth, c.assets.cash);
          notes.add('${p.name}还在生病，又花了 ${_money(cost)} 医药费。');
        }
      } else if (random.nextDouble() < sickChance) {
        p.status = PetStatus.sick;
        notes.add('${p.name}看起来没什么精神，可能是病了。');
      }

      // 寿命判定
      if (p.age >= p.lifespan) {
        p.status = PetStatus.dead;
        c.setAttr(
          AttributeKey.happiness,
          (c.attr(AttributeKey.happiness) - 6).clamp(0, 100),
        );
        notes.add('${p.name}走完了它的一生。');
      } else {
        p.adjustIntimacy(1);
      }
    }
    return notes;
  }

  /// 关系年度变化日志（好感度自然衰减、子女长大）
  List<String> _relationYearlyNotes(Character c) {
    final List<String> notes = <String>[];
    for (final Relation r in c.relations) {
      if (!r.alive) continue;
      if (r.type == RelationType.enemy) continue;
      // 久不联系，好感度缓慢下滑；社交达人减缓
      final int decay = c.talents.contains('社交达人') ? 0 : 1;
      if (decay > 0) r.adjustFavor(-decay);
      if (r.favor <= 0) {
        r.alive = false;
        notes.add('你和${r.name} 慢慢断了联系。');
      }
    }
    return notes;
  }

  /// 取第一只在世的宠物
  Pet? _firstAlivePet(Character c) {
    for (final Pet p in c.pets) {
      if (p.isAlive) return p;
    }
    return null;
  }

  /// 最严重的成瘾名
  String _worstAddictionName(Character c) {
    String name = '烟瘾';
    int max = -1;
    c.addictions.forEach((String key, int value) {
      if (value > max) {
        max = value;
        name = key;
      }
    });
    return name;
  }

  // -----------------------------------------------------------------------
  // 成就判定
  // -----------------------------------------------------------------------

  /// 检查并解锁成就，返回本次新解锁的成就名
  ///
  /// [unlocked] 为已经解锁过的成就名集合，函数会就地写入新解锁的成就。
  List<String> checkAchievements(
    Character c,
    Set<String> unlocked,
    int generation,
  ) {
    final List<String> fresh = <String>[];
    final Map<String, AchievementProbe> probes = buildProbes(c, generation);

    probes.forEach((String name, AchievementProbe probe) {
      if (unlocked.contains(name)) return;
      if (!data.achievementIndex.containsKey(name)) return;
      if (!probe.condition()) return;
      unlocked.add(name);
      fresh.add(name);
    });

    // 副作用：入狱、出狱等标记位
    if (fresh.isNotEmpty) {
      for (final String name in fresh) {
        c.log('解锁成就：$name', kind: LogKind.system);
      }
    }
    return fresh;
  }

  /// 构造「成就名 → 判定条件」的探针表（覆盖 achievements.json 的全部 74 条）
  Map<String, AchievementProbe> buildProbes(Character c, int generation) {
    final Map<String, AchievementProbe> map = <String, AchievementProbe>{};

    void add(String name, bool Function() condition) {
      map[name] = AchievementProbe(name, condition);
    }

    // ---- 人生节点 ----
    add('呱呱坠地', () => true);
    add('成年礼', () => c.age >= 18);
    add('百岁人生', () => c.age >= 100);
    add('英年早逝', () => !c.isAlive && c.deathAge >= 0 && c.deathAge < 40);
    add('寿终正寝', () => !c.isAlive && c.achievedNaturalDeath && c.attr(AttributeKey.health) > 30);
    add('轮回新生', () => generation >= 2);
    add('退休生活', () => c.retired || c.age >= 60);
    add('初为父母', () => c.childCount >= 1);
    add('儿孙满堂', () => c.childCount >= 3);
    add('含饴弄孙', () => c.childCount >= 2 && c.age >= 50);
    add('携手一生', () => c.everMarried);
    add('情窦初开', () => c.relations.any((Relation r) => r.type == RelationType.lover));
    add('青梅竹马',
        () => c.relations.any((Relation r) => r.type == RelationType.lover && r.startAge < 18));
    add('孤家寡人',
        () => !c.isAlive && c.countRelation(RelationType.spouse) == 0 && c.childCount == 0);
    add('感情破碎',
        () => c.relations.any((Relation r) => !r.alive && r.type == RelationType.lover));
    add('老友重逢', () => c.oldFriends.isNotEmpty);
    // 父母相关的【关系结束】会写入 oldFriends，年纪大了自然也会经历
    add('丧亲之痛', () => c.age >= 45);
    add('人脉广交', () => c.activeRelations.length >= 10);
    add('铁哥们', () => c.closeFriendCount >= 1 &&
        c.relations.any((Relation r) => r.alive && r.type == RelationType.friend && r.favor >= 90));
    add('众叛亲离', () => c.enemyCount >= 3);

    // ---- 学业 / 职业 ----
    // 注意：这几条都加了年龄门槛，避免小孩阶段就误判解锁
    add('金榜题名', () => c.age >= 15 && c.attr(AttributeKey.intelligence) >= 70);
    add('学业中断', () => c.age >= 16 && c.age <= 25 && c.attr(AttributeKey.intelligence) < 35);
    add('打工人', () => c.age >= 16 && (c.hasJob || c.career != '无'));
    add('职场晋升', () => c.age >= 16 && c.careerLevel >= 1);
    add('被优化了', () => c.age >= 16 && c.unemployed);
    add('跳槽高手', () => c.age >= 16 && c.careerLevel >= 2 && c.hasJob);
    add('体质内上岸',
        () => c.age >= 16 &&
            (c.career.contains('国企') ||
                c.career.contains('编制') ||
                c.career.contains('教师')));
    add('创业先锋', () => c.everStartedBusiness && c.assets.netWorth > 0);
    add('融资成功', () => c.everStartedBusiness && c.assets.netWorth >= 500000);
    add('公司破产', () => c.everStartedBusiness && c.unemployed && c.assets.debt > 0);
    add('下海经商', () => c.everStartedBusiness && c.era == '80');

    // ---- 财富 ----
    add('一夜暴富', () => c.maxSingleWealthGain >= 50000);
    add('有房一族', () => c.everBoughtHouse && c.assets.properties.isNotEmpty);
    add('有车一族', () => c.everBoughtCar && c.assets.vehicles.isNotEmpty);
    add('楼市赢家', () => c.assets.propertyValue >= 800000);
    add('股神', () => c.assets.investProfit >= 200000);
    add('负债累累', () => c.assets.debt >= 100000);
    add('无债一身轻', () => c.assets.everDebtOver50k && c.assets.debt == 0);
    add('理财达人', () => c.assets.investProfit >= 100000);
    add('被割韭菜', () => c.maxSingleInvestLoss >= 30000);
    add('赌徒深渊', () => c.assets.debt >= 50000 && (c.addictions['赌瘾'] ?? 0) > 0);
    add('戒赌勇士', () => c.assets.everDebtOver50k && (c.addictions['赌瘾'] ?? 0) == 0 && c.assets.debt == 0);

    // ---- 法律 ----
    add('锒铛入狱', () => c.everJailed);
    add('牢底坐穿', () => c.totalJailYears >= 10);
    add('减刑出狱', () => c.everCommuted);
    add('案底在身', () => c.hasCriminalRecord && c.everJailed);
    add('洗心革面', () => c.cleanYearsAfterJail >= 10);
    add('越狱未遂', () => c.everJailed && c.attr(AttributeKey.stress) >= 90);
    add('浪子回头', () => c.everHighSin && c.attr(AttributeKey.sin) == 0);

    // ---- 健康 ----
    add('百病缠身', () => c.lowHealthYears >= 3);
    add('ICU奇迹', () => c.everCriticalHealth && c.attr(AttributeKey.health) >= 50);
    add('手术台归来', () => c.hospitalCount >= 1);
    add('久病成医', () => c.hospitalCount >= 3);
    add('与遗传病共存', () => c.talents.contains('遗传病史') && c.attr(AttributeKey.health) >= 60);
    add('心理重建', () => c.skills.contains('meditation'));

    // ---- 时代 ----
    add('互联网原住民',
        () => c.era == '20' || c.eraEventsSeen.length >= 3);
    add('时代见证者', () => c.eraEventsSeen.length >= 5);
    add('下岗再就业', () => c.era == '90' && c.unemployed && c.hasJob);
    add('流量红人', () => c.attr(AttributeKey.fame) >= 70);
    add('网暴受害者', () => c.attr(AttributeKey.fame) >= 50 && c.attr(AttributeKey.stress) >= 85);
    add('机缘遇仙', () => c.attr(AttributeKey.luck) >= 90);
    add('走遍山河', () => c.eraEventsSeen.length >= 4);
    add('回忆录作者', () => c.skills.contains('writing') && c.age >= 60);

    // ---- 成瘾 ----
    add('戒烟成功', () => c.addictions.containsKey('烟瘾') && (c.addictions['烟瘾'] ?? 1) == 0);
    add('戒酒成功', () => c.addictions.containsKey('酒瘾') && (c.addictions['酒瘾'] ?? 1) == 0);
    add('网瘾戒断', () => c.addictions.containsKey('网瘾') && (c.addictions['网瘾'] ?? 1) == 0);
    add('五毒俱全', () => c.severeAddictionCount >= 4);
    add('戒断地狱', () => c.everWithdrawal && c.maxAddiction <= 20);

    // ---- 宠物 ----
    add('宠物主人', () => c.pets.isNotEmpty);
    add('毛孩子爸妈', () => c.pets.isNotEmpty);
    add('毛孩子满堂', () => c.pets.any((Pet p) => p.hasOffspring));
    add('宠物医院常客',
        () => c.pets.any((Pet p) => p.status == PetStatus.sick) || c.pets.length >= 3);
    add('回喵星了', () => c.pets.any((Pet p) => p.status == PetStatus.dead));

    // ---- 金手指 ----
    add('开挂人生', () => c.godModeUnlocked);

    return map;
  }

  // -----------------------------------------------------------------------
  // 存档辅助
  // -----------------------------------------------------------------------

  /// 生成一个随机名字（按年代气质简单区分）
  String randomName(String era, {bool male = true}) {
    const List<String> surnames = <String>[
      '李', '王', '张', '刘', '陈', '杨', '赵', '黄', '周', '吴',
      '徐', '孙', '马', '朱', '胡', '林', '郭', '何', '高', '罗',
    ];
    const List<String> maleNames = <String>[
      '建国', '伟', '强', '磊', '涛', '鹏', '浩', '宇', '晨', '阳',
      '小军', '阿哲', '二狗', '大壮',
    ];
    const List<String> femaleNames = <String>[
      '小雨', '婷婷', '小雪', '芳', '静', '丽', '娜', '琳', '朵朵', '月',
      '小满', '秀英', '桂兰', '若曦',
    ];
    final List<String> pool = male ? maleNames : femaleNames;
    final String surname = surnames[random.nextInt(surnames.length)];
    final String given = pool[random.nextInt(pool.length)];
    return '$surname$given';
  }

  /// 寿命随机：基础 72-95，受天赋修正；
  /// 有约 2% 概率抽到「长寿命」，寿命直接突破 100 岁（对应「百岁人生」成就）
  int randomLifespan(Character c) {
    int base;
    if (random.nextDouble() < 0.02) {
      base = 100 + random.nextInt(11);
    } else {
      base = 72 + random.nextInt(24);
    }
    if (c.talents.contains('长寿体质')) base += 8;
    if (c.talents.contains('短命基因')) base -= 12;
    if (c.talents.contains('打不死的小强')) base += 4;
    if (base < 35) base = 35;
    if (base > 120) base = 120;
    return base;
  }

  /// 随机宠物名
  String _randomPetName() {
    const List<String> names = <String>[
      '团子', '豆豆', '旺财', '大橘', '煤球', '雪球', '小虎', '阿黄',
      '布丁', '年糕', '花卷', '小灰',
    ];
    return names[random.nextInt(names.length)];
  }
}

/// 成就判定探针
class AchievementProbe {
  /// 成就名
  final String name;

  /// 判定函数
  final bool Function() condition;

  const AchievementProbe(this.name, this.condition);
}

/// 金额格式化：12345 → 1.23万
String _money(int amount) {
  final int abs = amount.abs();
  final String sign = amount < 0 ? '-' : '';
  if (abs >= 100000000) {
    return '$sign${(abs / 100000000).toStringAsFixed(2)}亿';
  }
  if (abs >= 10000) {
    return '$sign${(abs / 10000).toStringAsFixed(2)}万';
  }
  return '$sign$abs';
}

/// 属性变化 → 可读文本
String _deltaText(Map<AttributeKey, int> applied) {
  final List<String> parts = <String>[];
  for (final AttributeKey key in AttributeKeyX.all) {
    final int v = applied[key] ?? 0;
    if (v == 0) continue;
    if (key == AttributeKey.wealth) {
      parts.add('财富${v > 0 ? '+' : '-'}${_money(v.abs())}');
    } else {
      parts.add('${AttributeKeyX.shortLabel(key)}${v > 0 ? '+' : ''}$v');
    }
  }
  return parts.join('  ');
}
