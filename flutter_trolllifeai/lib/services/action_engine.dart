// 主动行动与关系互动引擎（玩法增强层）。
//
//   1) 主动行动：每岁 1 点行动力，玩家可以主动「做事」，不再只是被动等事件；
//   2) 关系互动：送礼 / 深聊 / 和解 / 求婚，每人每年 1 次（用 lastAct 年份去重）。
//
// 这里只负责「行动规则 + 数值」，属性上下限裁剪、关系与成瘾的写回
// 全部复用 EventEngine 已有的公开入口，保证和事件结算走同一套规则。
// 对应网页版 src/js/04_actions.js 的前两节。

import 'dart:math';

import '../models/character.dart';
import '../models/pet.dart';
import '../models/relation.dart';
import '../models/skill.dart';
import 'data_loader.dart';
import 'event_engine.dart';

/// 一个主动行动的静态定义（名称 / 分类标签 / 说明）
class ActionSpec {
  /// 行动 id，例如 work
  final String id;

  /// 行动名，例如「加班赚钱」
  final String name;

  /// 分类标签，例如「赚钱」
  final String tag;

  /// 说明文案
  final String desc;

  const ActionSpec(this.id, this.name, this.tag, this.desc);
}

/// 一个主动行动的运行时状态（是否可用 + 不可用原因）
class ActionCard {
  /// 静态定义
  final ActionSpec spec;

  /// 当前是否可点
  final bool usable;

  /// 不可用原因（可用时为空串）
  final String reason;

  const ActionCard({
    required this.spec,
    required this.usable,
    this.reason = '',
  });

  /// 行动名
  String get name => spec.name;

  /// 分类标签
  String get tag => spec.tag;

  /// 说明：可用时显示玩法说明，不可用时显示原因
  String get displayDesc => usable ? spec.desc : (reason.isEmpty ? spec.desc : reason);
}

/// 一种关系互动方式
class RelationInteract {
  /// 互动 id：gift / chat / reconcile / propose
  final String kind;

  /// 中文名
  final String name;

  /// 花费（0 表示免费）
  final int cost;

  /// 说明
  final String desc;

  const RelationInteract(this.kind, this.name, this.cost, this.desc);
}

/// 一次行动 / 互动的结算结果
class ActionOutcome {
  /// 是否真的执行了（false 时 message 是失败原因）
  final bool success;

  /// 给玩家的反馈文本（界面用 SnackBar 展示）
  final String message;

  /// 额外提示（会写入人生日志）
  final List<String> messages;

  /// 实际生效的属性变化
  final StatDelta delta;

  /// 是否因这次行动死亡
  final bool died;

  const ActionOutcome({
    this.success = true,
    this.message = '',
    this.messages = const <String>[],
    this.delta = StatDelta.zero,
    this.died = false,
  });
}

/// 主动行动与关系互动引擎
class ActionEngine {
  /// 剧本数据（技能表用于「进修学习」）
  final GameDataBundle data;

  /// 事件引擎：复用随机源、属性裁剪、关系写入等能力
  final EventEngine engine;

  /// 随机源（默认与事件引擎共用，保证随机可复现）
  final Random random;

  ActionEngine({required this.data, required this.engine, Random? random})
      : random = random ?? engine.random;

  /// 14 种主动行动（顺序即界面展示顺序）
  static const List<ActionSpec> specs = <ActionSpec>[
    ActionSpec('work', '加班赚钱', '赚钱', '接私活、加通宵班，钱到账但身体和情绪被透支'),
    ActionSpec('hospital', '看病就医', '健康', '花钱做检查与调养，把身体拉回来'),
    ActionSpec('fitness', '健身锻炼', '健康', '跑步撸铁，体质与健康稳步回升'),
    ActionSpec('study', '进修学习', '成长', '报班、看书、考证，有机会习得新技能'),
    ActionSpec('social', '社交应酬', '人际', '请客吃饭拓展人脉，有机会结识新朋友'),
    ActionSpec('invest', '投资理财', '赚钱', '把闲钱拿去投资，收益与亏损都有可能'),
    ActionSpec('family', '陪伴家人', '人际', '陪爱人孩子吃饭散步，关系与心情都会变好'),
    ActionSpec('rest', '休息放松', '健康', '彻底放空一年，压力大降，但当年收入减半'),
    ActionSpec('rehab', '戒瘾治疗', '健康', '去戒瘾机构接受治疗，成功率不算高'),
    ActionSpec('date', '相亲交友', '人际', '主动出击寻找伴侣，魅力越高成功率越大'),
    ActionSpec('child', '生育子女', '家庭', '迎接新生命，幸福与压力同时暴涨'),
    ActionSpec('startup', '创业尝试', '赚钱', '投钱试一个新项目，成败只在一线之间'),
    ActionSpec('pet', '陪伴宠物', '生活', '带宠物散步、洗澡、玩耍，彼此都被治愈'),
    ActionSpec('checkup', '全面体检', '健康', '早发现早治疗，把隐患掐在萌芽里'),
  ];

  /// 4 种关系互动方式
  static const List<RelationInteract> interacts = <RelationInteract>[
    RelationInteract('gift', '送礼', 2000, '花 2000 元送份礼物，好感 +8'),
    RelationInteract('chat', '深聊', 0, '认真聊一次，好感 +3、快乐 +2、压力 -2'),
    RelationInteract('reconcile', '和解', 0, '主动低头，有机会化敌为友'),
    RelationInteract('propose', '求婚', 5000, '向恋人求婚，成功即可结婚'),
  ];

  /// 按 id 取行动定义
  static ActionSpec? specById(String id) {
    for (final ActionSpec s in specs) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// 按 kind 取互动定义
  static RelationInteract? interactByKind(String kind) {
    for (final RelationInteract it in interacts) {
      if (it.kind == kind) return it;
    }
    return null;
  }

  /// 某段关系当前可用的互动方式（仇人才能和解，恋人才能求婚）
  static List<RelationInteract> interactsFor(Relation relation) {
    final List<RelationInteract> out = <RelationInteract>[];
    for (final RelationInteract it in interacts) {
      if (it.kind == 'reconcile' && relation.type != RelationType.enemy) continue;
      if (it.kind == 'propose' && relation.type != RelationType.lover) continue;
      out.add(it);
    }
    return out;
  }

  // -----------------------------------------------------------------------
  // 主动行动
  // -----------------------------------------------------------------------

  /// 当前可用性一览（界面用的两列网格数据）
  List<ActionCard> cards(Character c, {bool busy = false}) {
    final List<ActionCard> out = <ActionCard>[];
    for (final ActionSpec spec in specs) {
      String reason = '';
      if (!c.isAlive) {
        reason = '这一世已经结束了';
      } else if (c.inPrison) {
        reason = '服刑期间失去行动自由';
      } else if (c.actionPoints <= 0) {
        reason = '今年的行动点已经用完了';
      } else if (busy) {
        reason = '请先处理完当前事件';
      } else {
        reason = unavailableReason(spec.id, c);
      }
      out.add(
        ActionCard(spec: spec, usable: reason.isEmpty, reason: reason),
      );
    }
    return out;
  }

  /// 行动不可用的原因（空串表示可用）
  String unavailableReason(String id, Character c) {
    final int cash = c.attr(AttributeKey.wealth);
    switch (id) {
      case 'work':
        return '';
      case 'hospital':
        return cash >= 8000 ? '' : '现金不足 8000 元';
      case 'fitness':
        return c.attr(AttributeKey.health) >= 20 ? '' : '身体太虚弱，需要先就医';
      case 'study':
        return cash >= 5000 ? '' : '现金不足 5000 元';
      case 'social':
        return cash >= 2000 ? '' : '现金不足 2000 元';
      case 'invest':
        return cash >= 20000 ? '' : '现金不足 20000 元';
      case 'family':
        return _familyCount(c) > 0 ? '' : '暂时没有可以陪伴的家人或朋友';
      case 'rest':
        return '';
      case 'rehab':
        return c.attr(AttributeKey.addiction) >= 20 ? '' : '成瘾值低于 20，暂时不需要';
      case 'date':
        if (c.countRelation(RelationType.spouse) > 0) return '已经有配偶了';
        if (c.countRelation(RelationType.lover) > 0) return '已经有恋人了';
        return cash >= 1000 ? '' : '现金不足 1000 元';
      case 'child':
        if (c.countRelation(RelationType.spouse) == 0) return '需要先结婚';
        if (c.childCount >= 3) return '子女已经够多了';
        return cash >= 20000 ? '' : '现金不足 20000 元';
      case 'startup':
        return cash >= 50000 ? '' : '现金不足 50000 元';
      case 'pet':
        return c.activePets.isNotEmpty ? '' : '还没有宠物';
      case 'checkup':
        return cash >= 3000 ? '' : '现金不足 3000 元';
      default:
        return '行动不存在';
    }
  }

  /// 执行一个主动行动（会扣 1 点行动点，并写日志）
  ActionOutcome perform(Character c, String id) {
    final ActionSpec? spec = specById(id);
    if (spec == null) return _fail('行动不存在');
    if (!c.isAlive) return _fail('这一世已经结束了');
    if (c.inPrison) return _fail('服刑期间失去行动自由');
    if (c.actionPoints <= 0) return _fail('今年的行动点已经用完了，先过一年吧');
    final String reason = unavailableReason(id, c);
    if (reason.isNotEmpty) return _fail('暂时不能做：$reason');

    final Map<AttributeKey, int> delta = <AttributeKey, int>{};
    final List<String> messages = <String>[];
    String message = '';

    switch (id) {
      case 'work':
        message = _work(c, delta, messages);
        break;
      case 'hospital':
        message = _hospital(c, delta, messages);
        break;
      case 'fitness':
        message = _fitness(c, delta, messages);
        break;
      case 'study':
        message = _study(c, delta, messages);
        break;
      case 'social':
        message = _social(c, delta, messages);
        break;
      case 'invest':
        message = _invest(c, delta, messages);
        break;
      case 'family':
        message = _family(c, delta, messages);
        break;
      case 'rest':
        message = _rest(c, delta, messages);
        break;
      case 'rehab':
        message = _rehab(c, delta, messages);
        break;
      case 'date':
        message = _date(c, delta, messages);
        break;
      case 'child':
        message = _child(c, delta, messages);
        break;
      case 'startup':
        message = _startup(c, delta, messages);
        break;
      case 'pet':
        message = _pet(c, delta, messages);
        break;
      case 'checkup':
        message = _checkup(c, delta, messages);
        break;
      default:
        message = '${spec.name} 完成';
        break;
    }

    final Map<AttributeKey, int> applied =
        engine.applyDeltaClamped(c, StatDelta(delta));
    c.actionPoints -= 1;
    c.log('第 ${c.age} 年（主动行动）：${spec.name}');
    final String deltaText = StatDelta(applied).toReadable();
    if (deltaText.isNotEmpty) {
      c.log(deltaText, kind: LogKind.normal);
    }
    for (final String m in messages) {
      c.log(m, kind: LogKind.system);
    }

    return ActionOutcome(
      success: true,
      message: message,
      messages: messages,
      delta: StatDelta(applied),
      died: c.attr(AttributeKey.health) <= 0,
    );
  }

  /// 1. 加班赚钱：有职业按「月薪 × 0.6」额外收入，否则打零工
  String _work(
    Character c,
    Map<AttributeKey, int> delta,
    List<String> messages,
  ) {
    final int monthly = engine.estimatedMonthlySalary(c);
    if (c.hasJob && !c.unemployed && monthly > 0) {
      final int gain = (monthly * 0.6).round();
      _add(delta, AttributeKey.wealth, gain);
      _add(delta, AttributeKey.stress, 6);
      _add(delta, AttributeKey.health, -3);
      _add(delta, AttributeKey.happiness, -2);
      return '加班到手 ${_money(gain)}，但压力 +6';
    }
    final int gain = 2500 + random.nextInt(2501);
    _add(delta, AttributeKey.wealth, gain);
    _add(delta, AttributeKey.constitution, -2);
    _add(delta, AttributeKey.stress, 4);
    return '打零工赚 ${_money(gain)}';
  }

  /// 2. 看病就医：学过医疗 / 护理技能可以省钱
  String _hospital(
    Character c,
    Map<AttributeKey, int> delta,
    List<String> messages,
  ) {
    final int cost = (_has(c, 'medical') || _has(c, 'nursing')) ? 5000 : 8000;
    _add(delta, AttributeKey.wealth, -cost);
    _add(delta, AttributeKey.health, 12);
    _add(delta, AttributeKey.constitution, 1);
    _add(delta, AttributeKey.stress, -2);
    return '就医调养：健康 +12，花费 ${_money(cost)}';
  }

  /// 3. 健身锻炼：健身技能额外回血
  String _fitness(
    Character c,
    Map<AttributeKey, int> delta,
    List<String> messages,
  ) {
    final int bonus = _has(c, 'fitness') ? 2 : 0;
    _add(delta, AttributeKey.constitution, 2);
    _add(delta, AttributeKey.health, 3 + bonus);
    _add(delta, AttributeKey.happiness, 1);
    _add(delta, AttributeKey.stress, -3);
    if (bonus > 0) {
      return '体质 +2，健康 +${3 + bonus}（健身技能加成）';
    }
    return '体质 +2，健康 +3';
  }

  /// 4. 进修学习：35% 概率习得一个未习得技能
  String _study(
    Character c,
    Map<AttributeKey, int> delta,
    List<String> messages,
  ) {
    _add(delta, AttributeKey.wealth, -5000);
    _add(delta, AttributeKey.intelligence, 3);
    _add(delta, AttributeKey.stress, 3);
    if (random.nextDouble() < 0.35) {
      final List<Skill> pool = <Skill>[];
      for (final Skill skill in data.skills) {
        if (c.skills.contains(skill.skillId)) continue;
        pool.add(skill);
      }
      if (pool.isNotEmpty) {
        final Skill learned = pool[random.nextInt(pool.length)];
        c.skills.add(learned.skillId);
        messages.add('学会技能：${learned.name}');
        c.log('进修期间你掌握了${learned.name}。', kind: LogKind.good);
        return '智力 +3，习得技能：${learned.name}';
      }
    }
    return '智力 +3（这次没学到新技能）';
  }

  /// 5. 社交应酬：60% 概率结识新朋友
  String _social(
    Character c,
    Map<AttributeKey, int> delta,
    List<String> messages,
  ) {
    _add(delta, AttributeKey.wealth, -2000);
    _add(delta, AttributeKey.charm, 1);
    _add(delta, AttributeKey.happiness, 2);
    _add(delta, AttributeKey.stress, 2);
    if (random.nextDouble() < 0.6) {
      final Relation? friend = engine.addOrStrengthenRelation(
        c,
        RelationType.friend,
        _randomNickname(),
      );
      if (friend != null) {
        messages.add('新增朋友：${friend.name}');
        c.log('饭局上你认识了${friend.name}。', kind: LogKind.good);
        return '社交成功，结识新朋友 ${friend.name}';
      }
    }
    return '应酬一场，人脉没有变化';
  }

  /// 6. 投资理财：基数 min(现金, 12 万)，输赢都按比例
  String _invest(
    Character c,
    Map<AttributeKey, int> delta,
    List<String> messages,
  ) {
    double winRate = 0.55;
    if (_has(c, 'finance')) winRate += 0.08;
    if (_has(c, 'business')) winRate += 0.04;
    if (_talent(c, '投资直觉') || _talent(c, '商业嗅觉')) winRate += 0.08;
    if (_talent(c, '手气极差')) winRate -= 0.15;

    final int base = min(c.attr(AttributeKey.wealth), 120000);
    c.everInvested = true;

    if (random.nextDouble() < winRate) {
      final int win = (base * (0.06 + random.nextDouble() * 0.14)).round();
      _add(delta, AttributeKey.wealth, win);
      _add(delta, AttributeKey.happiness, 2);
      _add(delta, AttributeKey.stress, 1);
      c.assets.investProfit += win;
      if (win > c.maxSingleWealthGain) c.maxSingleWealthGain = win;
      return '投资盈利 +${_money(win)}';
    }

    final int lose = (base * (0.05 + random.nextDouble() * 0.12)).round();
    _add(delta, AttributeKey.wealth, -lose);
    _add(delta, AttributeKey.happiness, -3);
    _add(delta, AttributeKey.stress, 6);
    c.assets.investProfit -= lose;
    if (lose > c.maxSingleInvestLoss) c.maxSingleInvestLoss = lose;
    return '投资亏损 -${_money(lose)}';
  }

  /// 7. 陪伴家人：所有存活关系好感 +8
  String _family(
    Character c,
    Map<AttributeKey, int> delta,
    List<String> messages,
  ) {
    _add(delta, AttributeKey.wealth, -1000);
    _add(delta, AttributeKey.happiness, 5);
    _add(delta, AttributeKey.stress, -5);
    _add(delta, AttributeKey.health, 1);
    int count = 0;
    for (final Relation r in c.relations) {
      if (!r.alive) continue;
      r.adjustFavor(8);
      count += 1;
    }
    if (count > 0) {
      messages.add('$count 段关系好感 +8');
    }
    return '家人好感 +8，压力 -5';
  }

  /// 8. 休息放松：置位「当年收入减半」标记
  String _rest(
    Character c,
    Map<AttributeKey, int> delta,
    List<String> messages,
  ) {
    _add(delta, AttributeKey.stress, -10);
    _add(delta, AttributeKey.happiness, 4);
    _add(delta, AttributeKey.health, 2);
    c.halfIncomeYear = true;
    return '压力 -10，今年收入减半';
  }

  /// 9. 戒瘾治疗：成功时总成瘾值 -25，并随机挑一种成瘾再 -30
  String _rehab(
    Character c,
    Map<AttributeKey, int> delta,
    List<String> messages,
  ) {
    final int cost = (_has(c, 'medical') || _has(c, 'meditation')) ? 6000 : 10000;
    double rate = 0.7;
    if (_talent(c, '钢铁意志') || _talent(c, '抗瘾体质')) rate += 0.12;
    if (_has(c, 'meditation')) rate += 0.05;

    _add(delta, AttributeKey.wealth, -cost);

    final List<String> types = <String>[];
    c.addictions.forEach((String name, int value) {
      if (value > 0) types.add(name);
    });
    final String target = types.isEmpty ? '' : types[random.nextInt(types.length)];

    if (random.nextDouble() < rate) {
      _add(delta, AttributeKey.addiction, -25);
      _add(delta, AttributeKey.happiness, -4);
      _add(delta, AttributeKey.stress, 6);
      if (target.isNotEmpty) {
        final int before = c.addictions[target] ?? 0;
        c.addictions[target] = (before - 30).clamp(0, 100).toInt();
        messages.add('$target 减轻了 ${before - (c.addictions[target] ?? 0)}');
      }
      if (target.isEmpty) {
        return '戒瘾有效：成瘾值 -25';
      }
      return '戒瘾有效：成瘾值 -25（$target -30）';
    }

    _add(delta, AttributeKey.addiction, -5);
    _add(delta, AttributeKey.stress, 12);
    _add(delta, AttributeKey.happiness, -6);
    return '治疗失败，只降了 5 点成瘾值';
  }

  /// 10. 相亲交友：成功率 = 55% + 魅力/300（上限 +25%）
  String _date(
    Character c,
    Map<AttributeKey, int> delta,
    List<String> messages,
  ) {
    double rate = 0.55 + min(c.attr(AttributeKey.charm) / 300, 0.25);
    if (_talent(c, '天生丽质') || _talent(c, '社交达人')) rate += 0.1;
    if (_talent(c, '社交恐惧')) rate -= 0.2;

    _add(delta, AttributeKey.wealth, -1000);
    if (random.nextDouble() < rate) {
      _add(delta, AttributeKey.happiness, 8);
      _add(delta, AttributeKey.charm, 2);
      _add(delta, AttributeKey.stress, 2);
      final Relation? lover = engine.addOrStrengthenRelation(
        c,
        RelationType.lover,
        _randomNickname(),
      );
      if (lover != null) {
        messages.add('新增恋人：${lover.name}');
        c.log('你和${lover.name}开始了交往。', kind: LogKind.good);
      }
      return '脱单成功！';
    }
    _add(delta, AttributeKey.happiness, -3);
    _add(delta, AttributeKey.stress, 3);
    return '相亲失败，下次再试';
  }

  /// 11. 生育子女：新增一个 child 关系
  String _child(
    Character c,
    Map<AttributeKey, int> delta,
    List<String> messages,
  ) {
    _add(delta, AttributeKey.wealth, -20000);
    _add(delta, AttributeKey.happiness, 8);
    _add(delta, AttributeKey.stress, 12);
    _add(delta, AttributeKey.health, -3);
    final String babyName = engine.randomName(c.era, male: random.nextBool());
    final Relation? baby = engine.addOrStrengthenRelation(
      c,
      RelationType.child,
      babyName,
    );
    if (baby != null) {
      messages.add('新增子女：${baby.name}');
      c.log('家里多了一个孩子：${baby.name}。', kind: LogKind.good);
    }
    return '子女 +1，压力 +12';
  }

  /// 12. 创业尝试：成功净增 1~8 万，失败亏 5 万
  String _startup(
    Character c,
    Map<AttributeKey, int> delta,
    List<String> messages,
  ) {
    double rate = 0.45;
    if (_has(c, 'business')) rate += 0.08;
    if (_has(c, 'ecommerce')) rate += 0.05;
    if (_talent(c, '商业嗅觉')) rate += 0.08;
    if (_talent(c, '赌命之徒')) rate += 0.06;

    c.everStartedBusiness = true;
    if (random.nextDouble() < rate) {
      final int gain = 60000 + random.nextInt(70001);
      _add(delta, AttributeKey.wealth, -50000 + gain);
      _add(delta, AttributeKey.fame, 4);
      _add(delta, AttributeKey.stress, 10);
      _add(delta, AttributeKey.intelligence, 2);
      return '创业成功 +${_money(gain)}';
    }
    _add(delta, AttributeKey.wealth, -50000);
    _add(delta, AttributeKey.happiness, -6);
    _add(delta, AttributeKey.stress, 15);
    _add(delta, AttributeKey.intelligence, 1);
    return '创业失败，亏损 50000';
  }

  /// 13. 陪伴宠物：所有在世宠物健康 +10（宠物养护技能 +6）
  String _pet(
    Character c,
    Map<AttributeKey, int> delta,
    List<String> messages,
  ) {
    final int bonus = _has(c, 'pet_care') ? 6 : 0;
    _add(delta, AttributeKey.wealth, -500);
    _add(delta, AttributeKey.happiness, 4);
    _add(delta, AttributeKey.stress, -3);
    for (final Pet p in c.pets) {
      if (!p.isAlive) continue;
      p.adjustHealth(10 + bonus);
    }
    if (bonus > 0) {
      return '宠物健康 +${10 + bonus}（宠物养护加成），快乐 +4';
    }
    return '宠物健康 +10，快乐 +4';
  }

  /// 14. 全面体检：25% 概率查出隐患，提前处理收益更高
  String _checkup(
    Character c,
    Map<AttributeKey, int> delta,
    List<String> messages,
  ) {
    final bool found = random.nextDouble() < 0.25;
    final int heal = _has(c, 'medical') ? 8 : 5;
    _add(delta, AttributeKey.wealth, -3000);
    _add(delta, AttributeKey.health, heal + (found ? 4 : 0));
    _add(delta, AttributeKey.stress, found ? 4 : 1);
    if (found) {
      messages.add('体检查出早期隐患，已及时处理');
      c.log('体检查出早期隐患，你及时做了治疗。', kind: LogKind.good);
      return '查出隐患并已处理：健康 +${heal + 4}';
    }
    return '体检正常：健康 +$heal';
  }

  // -----------------------------------------------------------------------
  // 关系互动
  // -----------------------------------------------------------------------

  /// 互动是否可用：空串表示可以互动，否则返回原因
  String interactReason(Character c, Relation relation, String kind) {
    if (!c.isAlive) return '这一世已经结束了';
    if (!relation.alive) return '这段关系已经结束了';
    if (relation.lastAct == c.age) return '今年已经互动过了';
    final RelationInteract? info = interactByKind(kind);
    if (info == null) return '互动方式不存在';
    if (info.cost > 0 && c.attr(AttributeKey.wealth) < info.cost) {
      return '现金不足 ${_money(info.cost)} 元';
    }
    if (kind == 'reconcile' && relation.type != RelationType.enemy) {
      return '只有仇人才需要和解';
    }
    if (kind == 'propose') {
      if (relation.type != RelationType.lover) return '只有恋人才能求婚';
      if (c.countRelation(RelationType.spouse) > 0) return '你已经有配偶了';
    }
    return '';
  }

  /// 执行一次关系互动（每人每年一次）
  ActionOutcome interact(Character c, Relation relation, String kind) {
    final String reason = interactReason(c, relation, kind);
    if (reason.isNotEmpty) return _fail(reason);
    final RelationInteract? info = interactByKind(kind);
    if (info == null) return _fail('互动方式不存在');

    final Map<AttributeKey, int> delta = <AttributeKey, int>{};
    final List<String> messages = <String>[];
    if (info.cost > 0) {
      _add(delta, AttributeKey.wealth, -info.cost);
    }

    String message = '';
    switch (kind) {
      case 'gift':
        relation.adjustFavor(8);
        message = '给${relation.name}送了礼物，好感 +8';
        break;
      case 'chat':
        relation.adjustFavor(3);
        _add(delta, AttributeKey.happiness, 2);
        _add(delta, AttributeKey.stress, -2);
        message = '和${relation.name}深聊了一次，好感 +3';
        break;
      case 'reconcile':
        if (random.nextDouble() < 0.5) {
          relation.type = RelationType.friend;
          relation.favor = 55;
          messages.add('仇人${relation.name}变成了朋友');
          message = '与${relation.name}冰释前嫌，化敌为友';
        } else {
          relation.adjustFavor(5);
          message = '${relation.name}还没完全原谅你，但关系缓和了一些';
        }
        break;
      case 'propose':
        final double rate = 0.6 + min(relation.favor / 400, 0.2);
        if (random.nextDouble() < rate) {
          relation.type = RelationType.spouse;
          relation.adjustFavor(10);
          c.everMarried = true;
          _add(delta, AttributeKey.happiness, 12);
          _add(delta, AttributeKey.fame, 3);
          _add(delta, AttributeKey.luck, 1);
          _add(delta, AttributeKey.health, 2);
          _add(delta, AttributeKey.stress, 4);
          _add(delta, AttributeKey.wealth, -10000);
          messages.add('解锁成就：携手一生');
          message = '求婚成功！${relation.name}成为了你的配偶';
        } else {
          _add(delta, AttributeKey.happiness, -8);
          _add(delta, AttributeKey.stress, 8);
          message = '${relation.name}拒绝了你的求婚，需要更多相处';
        }
        break;
      default:
        message = '互动完成';
        break;
    }

    final Map<AttributeKey, int> applied =
        engine.applyDeltaClamped(c, StatDelta(delta));
    relation.lastAct = c.age;
    c.log('第 ${c.age} 年（关系互动）：$message');
    for (final String m in messages) {
      c.log(m, kind: LogKind.system);
    }

    return ActionOutcome(
      success: true,
      message: message,
      messages: messages,
      delta: StatDelta(applied),
      died: c.attr(AttributeKey.health) <= 0,
    );
  }

  // -----------------------------------------------------------------------
  // 工具
  // -----------------------------------------------------------------------

  /// 往变化表里累加一项
  static void _add(Map<AttributeKey, int> delta, AttributeKey key, int value) {
    delta[key] = (delta[key] ?? 0) + value;
  }

  /// 是否习得某技能
  static bool _has(Character c, String skillId) {
    return c.skills.contains(skillId);
  }

  /// 是否拥有某天赋
  static bool _talent(Character c, String name) {
    return c.talents.contains(name);
  }

  /// 可陪伴的对象数量（配偶 / 子女 / 朋友 / 恋人）
  static int _familyCount(Character c) {
    return c.countRelation(RelationType.spouse) +
        c.countRelation(RelationType.child) +
        c.countRelation(RelationType.friend) +
        c.countRelation(RelationType.lover);
  }

  /// 随机一个新关系的名字（沿用网页版的人名池）
  String _randomNickname() {
    const List<String> pool = <String>[
      '小林', '阿哲', '小雨', '老周', '小美', '阿豪', '小柔', '老陈',
      '小夏', '阿泽', '小满', '老李', '小舟', '阿敏', '子墨', '佩琪',
    ];
    final String base = pool[random.nextInt(pool.length)];
    if (random.nextInt(3) == 0) {
      return '$base${10 + random.nextInt(90)}';
    }
    return base;
  }

  /// 失败结果
  static ActionOutcome _fail(String reason) {
    return ActionOutcome(success: false, message: reason);
  }

  /// 金额格式化：12345 → 1.23万
  static String _money(int amount) {
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
}
