// 角色模型：11 项属性 + 资产 + 成瘾 + 关系 + 宠物 + 技能 + 天赋 + 日志。
//
// 这是整个游戏的核心数据容器，所有页面都读取它，
// 所有修改都通过 GameProvider（持有 Character 实例）完成。

import 'asset_state.dart';
import 'pet.dart';
import 'relation.dart';

/// 11 项属性的固定键（顺序即界面展示顺序）
enum AttributeKey {
  intelligence,
  constitution,
  charm,
  wealth,
  happiness,
  luck,
  health,
  addiction,
  fame,
  stress,
  sin,
}

/// 属性枚举的中文名 / JSON 键互转工具
class AttributeKeyX {
  const AttributeKeyX._();

  /// 全部属性的固定顺序列表
  static const List<AttributeKey> all = <AttributeKey>[
    AttributeKey.intelligence,
    AttributeKey.constitution,
    AttributeKey.charm,
    AttributeKey.wealth,
    AttributeKey.happiness,
    AttributeKey.luck,
    AttributeKey.health,
    AttributeKey.addiction,
    AttributeKey.fame,
    AttributeKey.stress,
    AttributeKey.sin,
  ];

  /// 枚举 → 事件 JSON 里的中文键
  static String toKey(AttributeKey key) {
    switch (key) {
      case AttributeKey.intelligence:
        return '智力';
      case AttributeKey.constitution:
        return '体质';
      case AttributeKey.charm:
        return '魅力';
      case AttributeKey.wealth:
        return '财富';
      case AttributeKey.happiness:
        return '快乐';
      case AttributeKey.luck:
        return '运气';
      case AttributeKey.health:
        return '健康值';
      case AttributeKey.addiction:
        return '成瘾值';
      case AttributeKey.fame:
        return '名声值';
      case AttributeKey.stress:
        return '压力值';
      case AttributeKey.sin:
        return '罪恶值';
    }
  }

  /// 中文键 → 枚举，未知键返回 null（用于容错解析）
  static AttributeKey? fromKey(String key) {
    final String k = key.trim();
    for (final AttributeKey item in all) {
      if (toKey(item) == k) return item;
    }
    return null;
  }

  /// 界面短名
  static String shortLabel(AttributeKey key) {
    switch (key) {
      case AttributeKey.intelligence:
        return '智力';
      case AttributeKey.constitution:
        return '体质';
      case AttributeKey.charm:
        return '魅力';
      case AttributeKey.wealth:
        return '财富';
      case AttributeKey.happiness:
        return '快乐';
      case AttributeKey.luck:
        return '运气';
      case AttributeKey.health:
        return '健康';
      case AttributeKey.addiction:
        return '成瘾';
      case AttributeKey.fame:
        return '名声';
      case AttributeKey.stress:
        return '压力';
      case AttributeKey.sin:
        return '罪恶';
    }
  }
}

/// 一次属性变化量（11 项，缺省为 0）
class StatDelta {
  /// 每一项的变化值，键为属性枚举
  final Map<AttributeKey, int> values;

  const StatDelta(this.values);

  /// 全 0 的变化量
  static const StatDelta zero = StatDelta(<AttributeKey, int>{});

  /// 从事件 JSON 的 attr_change / attrModify 解析（容错：缺键按 0 处理）
  factory StatDelta.fromJson(Object? json) {
    final Map<AttributeKey, int> map = <AttributeKey, int>{};
    if (json is Map) {
      json.forEach((Object? key, Object? value) {
        final AttributeKey? attr = AttributeKeyX.fromKey(key.toString());
        if (attr == null) return;
        map[attr] = _toInt(value);
      });
    }
    return StatDelta(map);
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> out = <String, dynamic>{};
    values.forEach((AttributeKey key, int value) {
      out[AttributeKeyX.toKey(key)] = value;
    });
    return out;
  }

  /// 取某项变化值
  int get(AttributeKey key) => values[key] ?? 0;

  /// 是否全部为 0
  bool get isEmpty => values.isEmpty || values.values.every((int e) => e == 0);

  /// 合并两个变化量，返回新的变化量
  StatDelta merge(StatDelta other) {
    final Map<AttributeKey, int> merged = <AttributeKey, int>{};
    merged.addAll(values);
    other.values.forEach((AttributeKey key, int value) {
      merged[key] = (merged[key] ?? 0) + value;
    });
    return StatDelta(merged);
  }

  /// 按倍数放大（用于天赋、难度的增益 / 惩罚）
  StatDelta scaled(double factor) {
    final Map<AttributeKey, int> out = <AttributeKey, int>{};
    values.forEach((AttributeKey key, int value) {
      final int scaled = (value * factor).round();
      if (scaled != 0) out[key] = scaled;
    });
    return StatDelta(out);
  }

  /// 生成一段「智力+3 体质-2」形式的可读文本，全 0 时返回空串
  String toReadable() {
    final List<String> parts = <String>[];
    for (final AttributeKey key in AttributeKeyX.all) {
      final int v = get(key);
      if (v == 0) continue;
      if (key == AttributeKey.wealth) {
        final String sign = v > 0 ? '+' : '-';
        parts.add('财富$sign${_money(v.abs())}');
      } else {
        parts.add('${AttributeKeyX.shortLabel(key)}${v > 0 ? '+' : ''}$v');
      }
    }
    return parts.join('  ');
  }

  /// 构造一个单项变化量，便于代码里快速生成
  factory StatDelta.single(AttributeKey key, int value) {
    return StatDelta(<AttributeKey, int>{key: value});
  }

  /// 金额格式化：12345 → 1.23万
  static String _money(int amount) {
    if (amount >= 100000000) {
      return '${(amount / 100000000).toStringAsFixed(2)}亿';
    }
    if (amount >= 10000) {
      return '${(amount / 10000).toStringAsFixed(2)}万';
    }
    return amount.toString();
  }
}

/// 人生日志条目：每一年都会写入若干条
class LifeLogEntry {
  /// 发生时的年龄
  final int age;

  /// 日志文本（已剔除标记语言）
  final String text;

  /// 日志类型，用于着色
  final LogKind kind;

  LifeLogEntry({
    required this.age,
    required this.text,
    this.kind = LogKind.normal,
  });

  factory LifeLogEntry.fromJson(Map<String, dynamic> json) {
    return LifeLogEntry(
      age: _toInt(json['age']),
      text: (json['text'] ?? '').toString(),
      kind: LogKindX.fromKey((json['kind'] ?? 'normal').toString()),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'age': age,
        'text': text,
        'kind': LogKindX.toKey(kind),
      };
}

/// 日志类型
enum LogKind {
  /// 普通叙述
  normal,

  /// 好事（绿色）
  good,

  /// 坏事（红色）
  bad,

  /// 系统提示（天赋、成就、金手指）
  system,

  /// 收入 / 资产变动（黄色）
  money,
}

/// 日志类型字符串 ↔ 枚举
class LogKindX {
  const LogKindX._();

  static String toKey(LogKind kind) {
    switch (kind) {
      case LogKind.normal:
        return 'normal';
      case LogKind.good:
        return 'good';
      case LogKind.bad:
        return 'bad';
      case LogKind.system:
        return 'system';
      case LogKind.money:
        return 'money';
    }
  }

  static LogKind fromKey(String key) {
    switch (key.trim().toLowerCase()) {
      case 'good':
        return LogKind.good;
      case 'bad':
        return LogKind.bad;
      case 'system':
        return LogKind.system;
      case 'money':
        return LogKind.money;
      default:
        return LogKind.normal;
    }
  }
}

/// 人生状态
enum LifeStatus {
  /// 正常存活
  alive,

  /// 服刑中
  inPrison,

  /// 已死亡
  dead,
}

/// 角色：一世的全部数据
class Character {
  /// 姓名（开局按年代随机生成）
  String name;

  /// 性别描述，仅用于文案
  String gender;

  /// 当前年龄
  int age;

  /// 出生年代键：80 / 90 / 00 / 10 / 20
  String era;

  /// 所在城市名
  String cityName;

  /// 城市财富上限系数（决定财富上限 = 300000 × 系数）
  double wealthCapFactor;

  /// 城市每年压力修正
  int cityStressModifier;

  /// 11 项属性
  Map<AttributeKey, int> attributes;

  /// 资产与负债
  AssetState assets;

  /// 成瘾表：键为「烟瘾 / 酒瘾 / 网瘾 / 赌瘾」等开放键名，值为 0-100
  Map<String, int> addictions;

  /// 人际关系
  List<Relation> relations;

  /// 宠物
  List<Pet> pets;

  /// 已习得技能 id 列表
  List<String> skills;

  /// 天赋名（通常 1 个，轮回后重新抽取）
  List<String> talents;

  /// 人生日志（按时间正序）
  List<LifeLogEntry> logs;

  /// 是否已经历过某些关键节点（供成就与文案使用）
  bool hasJob;

  /// 当前职业称谓，例如「程序员」
  String career;

  /// 职业等级（升职累加）
  int careerLevel;

  /// 是否失业中
  bool unemployed;

  /// 是否已退休
  bool retired;

  /// 是否入过狱
  bool everJailed;

  /// 是否当前有案底
  bool hasCriminalRecord;

  /// 剩余服刑年数
  int jailYearsLeft;

  /// 累计服刑年数（用于「牢底坐穿」成就）
  int totalJailYears;

  /// 是否获得过减刑
  bool everCommuted;

  /// 是否买过房 / 买过车
  bool everBoughtHouse;

  /// 是否买过车
  bool everBoughtCar;

  /// 是否创过业
  bool everStartedBusiness;

  /// 是否结婚过
  bool everMarried;

  /// 是否触发过成瘾发作
  bool everWithdrawal;

  /// 是否解锁过金手指
  bool godModeUnlocked;

  /// 是否已开启过金手指篡改（用于成就与标记作弊）
  bool godModeUsed;

  /// 预计寿命（开局随机，受天赋影响）
  int lifespan;

  /// 人生状态
  LifeStatus status;

  /// 死亡原因
  String deathReason;

  /// 健康值连续 ≤20 的年数（「百病缠身」成就）
  int lowHealthYears;

  /// 健康值曾经 ≤10 过（「ICU奇迹」成就）
  bool everCriticalHealth;

  /// 罪恶值曾经 ≥40 过（「浪子回头」成就）
  bool everHighSin;

  /// 出狱后连续低罪恶年数（「洗心革面」成就）
  int cleanYearsAfterJail;

  /// 是否经历过住院（累计次数）
  int hospitalCount;

  /// 经历过的年代事件集合（「时代见证者」成就）
  List<String> eraEventsSeen;

  /// 单次财富增加最大值（用于「一夜暴富」判定）
  int maxSingleWealthGain;

  /// 单次投资亏损最大值（用于「被割韭菜」判定）
  int maxSingleInvestLoss;

  /// 是否已投过资
  bool everInvested;

  /// 「老友重逢」用的老友名单（曾经存在但已结束的关系）
  List<String> oldFriends;

  /// 上一世继承下来的属性（轮回展示用）
  Map<AttributeKey, int> inherited;

  /// 本局是否已经触发过「寿终正寝」成就
  bool achievedNaturalDeath;

  /// 死亡时的年龄，未死亡为 -1
  int deathAge;

  /// 主动行动点：每年推进时重置为 1，服刑期间为 0
  int actionPoints;

  /// 「休息放松」标记：置位后当年收入减半（结算后自动清除）
  bool halfIncomeYear;

  /// 本世 AI 续写成功的次数
  int aiUsed;

  /// 本世 AI 续写失败的次数
  int aiFails;

  /// 本世已经发生过的剧情标题（保留最近若干条，供 AI 提示词避免重复）
  List<String> storyTitles;

  Character({
    required this.name,
    this.gender = '男',
    this.age = 0,
    required this.era,
    required this.cityName,
    this.wealthCapFactor = 1.0,
    this.cityStressModifier = 0,
    Map<AttributeKey, int>? attributes,
    AssetState? assets,
    Map<String, int>? addictions,
    List<Relation>? relations,
    List<Pet>? pets,
    List<String>? skills,
    List<String>? talents,
    List<LifeLogEntry>? logs,
    this.hasJob = false,
    this.career = '无',
    this.careerLevel = 0,
    this.unemployed = false,
    this.retired = false,
    this.everJailed = false,
    this.hasCriminalRecord = false,
    this.jailYearsLeft = 0,
    this.totalJailYears = 0,
    this.everCommuted = false,
    this.everBoughtHouse = false,
    this.everBoughtCar = false,
    this.everStartedBusiness = false,
    this.everMarried = false,
    this.everWithdrawal = false,
    this.godModeUnlocked = false,
    this.godModeUsed = false,
    this.lifespan = 78,
    this.status = LifeStatus.alive,
    this.deathReason = '',
    this.lowHealthYears = 0,
    this.everCriticalHealth = false,
    this.everHighSin = false,
    this.cleanYearsAfterJail = 0,
    this.hospitalCount = 0,
    List<String>? eraEventsSeen,
    this.maxSingleWealthGain = 0,
    this.maxSingleInvestLoss = 0,
    this.everInvested = false,
    List<String>? oldFriends,
    Map<AttributeKey, int>? inherited,
    this.achievedNaturalDeath = false,
    this.deathAge = -1,
    this.actionPoints = 1,
    this.halfIncomeYear = false,
    this.aiUsed = 0,
    this.aiFails = 0,
    List<String>? storyTitles,
  })  : attributes = attributes ?? _defaultAttributes(),
        assets = assets ?? AssetState(),
        addictions = addictions ?? _defaultAddictions(),
        relations = relations ?? <Relation>[],
        pets = pets ?? <Pet>[],
        skills = skills ?? <String>[],
        talents = talents ?? <String>[],
        logs = logs ?? <LifeLogEntry>[],
        eraEventsSeen = eraEventsSeen ?? <String>[],
        oldFriends = oldFriends ?? <String>[],
        inherited = inherited ?? <AttributeKey, int>{},
        storyTitles = storyTitles ?? <String>[];

  /// 初始 11 项属性：智力/体质/魅力/快乐/运气 从 50 起，
  /// 财富 0、健康值 70、压力值 20、快乐 60、成瘾值 0、罪恶值 0、名声值 0
  static Map<AttributeKey, int> _defaultAttributes() {
    return <AttributeKey, int>{
      AttributeKey.intelligence: 50,
      AttributeKey.constitution: 50,
      AttributeKey.charm: 50,
      AttributeKey.wealth: 0,
      AttributeKey.happiness: 60,
      AttributeKey.luck: 50,
      AttributeKey.health: 70,
      AttributeKey.addiction: 0,
      AttributeKey.fame: 0,
      AttributeKey.stress: 20,
      AttributeKey.sin: 0,
    };
  }

  /// 默认成瘾表（四种常见成瘾，值为 0）
  static Map<String, int> _defaultAddictions() {
    return <String, int>{
      '烟瘾': 0,
      '酒瘾': 0,
      '网瘾': 0,
      '赌瘾': 0,
    };
  }

  // ---------------------------------------------------------------------
  // 属性读写
  // ---------------------------------------------------------------------

  /// 读取单项属性
  int attr(AttributeKey key) => attributes[key] ?? 0;

  /// 写入单项属性（不做上下限裁剪，裁剪由引擎负责）
  void setAttr(AttributeKey key, int value) {
    attributes[key] = value;
  }

  /// 叠加属性变化（不做裁剪）
  void applyDelta(StatDelta delta) {
    delta.values.forEach((AttributeKey key, int value) {
      attributes[key] = attr(key) + value;
    });
  }

  /// 是否存活
  bool get isAlive => status != LifeStatus.dead;

  /// 是否在服刑
  bool get inPrison => status == LifeStatus.inPrison && jailYearsLeft > 0;

  /// 财富上限 = 300000 × 城市系数
  int get wealthCap => (300000 * wealthCapFactor).round();

  /// 当前财富是否已经触顶
  bool get wealthAtCap => attr(AttributeKey.wealth) >= wealthCap;

  /// 年龄 + 出生年代 → 现实年份，例如 1980 + 年龄
  int get calendarYear {
    final int base = int.tryParse(era) ?? 80;
    final int startYear = base >= 100 ? base : 1900 + base;
    return startYear + age;
  }

  /// 存活中的关系列表
  List<Relation> get activeRelations =>
      relations.where((Relation e) => e.alive).toList();

  /// 存活中的宠物列表
  List<Pet> get activePets => pets.where((Pet e) => e.isAlive).toList();

  /// 按类型统计关系数量
  int countRelation(RelationType type) {
    return relations
        .where((Relation e) => e.alive && e.type == type)
        .length;
  }

  /// 子女数量
  int get childCount => countRelation(RelationType.child);

  /// 仇人数量
  int get enemyCount => countRelation(RelationType.enemy);

  /// 好朋友数量（好感度 ≥ 60 的 friend）
  int get closeFriendCount => relations
      .where((Relation e) =>
          e.alive &&
          e.type == RelationType.friend &&
          e.favor >= 60)
      .length;

  /// 最高的成瘾值
  int get maxAddiction {
    if (addictions.isEmpty) return 0;
    return addictions.values.reduce((int a, int b) => a > b ? a : b);
  }

  /// ≥50 的成瘾种类数量（「五毒俱全」成就）
  int get severeAddictionCount =>
      addictions.values.where((int e) => e >= 50).length;

  /// 是否有某种成瘾
  bool hasAddiction(String name) => (addictions[name] ?? 0) > 0;

  // ---------------------------------------------------------------------
  // 日志
  // ---------------------------------------------------------------------

  /// 写入一条日志（最新的排在日志列表末尾，界面倒序展示）
  void log(String text, {LogKind kind = LogKind.normal}) {
    logs.add(LifeLogEntry(age: age, text: text, kind: kind));
  }

  /// 只保留最近 [limit] 条日志，避免存档无限膨胀
  void trimLogs({int limit = 600}) {
    if (logs.length <= limit) return;
    logs.removeRange(0, logs.length - limit);
  }

  // ---------------------------------------------------------------------
  // 序列化
  // ---------------------------------------------------------------------

  factory Character.fromJson(Map<String, dynamic> json) {
    final Map<AttributeKey, int> attrs = _defaultAttributes();
    final Object? rawAttrs = json['attributes'];
    if (rawAttrs is Map) {
      rawAttrs.forEach((Object? key, Object? value) {
        final AttributeKey? attr = AttributeKeyX.fromKey(key.toString());
        if (attr != null) attrs[attr] = _toInt(value);
      });
    }

    final Map<String, int> addictions = _defaultAddictions();
    final Object? rawAdd = json['addictions'];
    if (rawAdd is Map) {
      rawAdd.forEach((Object? key, Object? value) {
        if (key == null) return;
        addictions[key.toString()] = _toInt(value);
      });
    }

    final List<Relation> relations = <Relation>[];
    final Object? rawRel = json['relations'];
    if (rawRel is List) {
      for (final Object? item in rawRel) {
        if (item is Map) {
          relations.add(Relation.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    final List<Pet> pets = <Pet>[];
    final Object? rawPets = json['pets'];
    if (rawPets is List) {
      for (final Object? item in rawPets) {
        if (item is Map) {
          pets.add(Pet.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    final List<LifeLogEntry> logs = <LifeLogEntry>[];
    final Object? rawLogs = json['logs'];
    if (rawLogs is List) {
      for (final Object? item in rawLogs) {
        if (item is Map) {
          logs.add(LifeLogEntry.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    final Map<AttributeKey, int> inherited = <AttributeKey, int>{};
    final Object? rawInherit = json['inherited'];
    if (rawInherit is Map) {
      rawInherit.forEach((Object? key, Object? value) {
        final AttributeKey? attr = AttributeKeyX.fromKey(key.toString());
        if (attr != null) inherited[attr] = _toInt(value);
      });
    }

    return Character(
      name: (json['name'] ?? '无名氏').toString(),
      gender: (json['gender'] ?? '男').toString(),
      age: _toInt(json['age']),
      era: (json['era'] ?? '00').toString(),
      cityName: (json['cityName'] ?? '小县城').toString(),
      wealthCapFactor: _toDouble(json['wealthCapFactor'], 1.0),
      cityStressModifier: _toInt(json['cityStressModifier']),
      attributes: attrs,
      assets: json['assets'] is Map
          ? AssetState.fromJson(Map<String, dynamic>.from(json['assets'] as Map))
          : AssetState(),
      addictions: addictions,
      relations: relations,
      pets: pets,
      skills: _toStringList(json['skills']),
      talents: _toStringList(json['talents']),
      logs: logs,
      hasJob: json['hasJob'] == true,
      career: (json['career'] ?? '无').toString(),
      careerLevel: _toInt(json['careerLevel']),
      unemployed: json['unemployed'] == true,
      retired: json['retired'] == true,
      everJailed: json['everJailed'] == true,
      hasCriminalRecord: json['hasCriminalRecord'] == true,
      jailYearsLeft: _toInt(json['jailYearsLeft']),
      totalJailYears: _toInt(json['totalJailYears']),
      everCommuted: json['everCommuted'] == true,
      everBoughtHouse: json['everBoughtHouse'] == true,
      everBoughtCar: json['everBoughtCar'] == true,
      everStartedBusiness: json['everStartedBusiness'] == true,
      everMarried: json['everMarried'] == true,
      everWithdrawal: json['everWithdrawal'] == true,
      godModeUnlocked: json['godModeUnlocked'] == true,
      godModeUsed: json['godModeUsed'] == true,
      lifespan: _toInt(json['lifespan'], 78),
      status: _statusFromKey((json['status'] ?? 'alive').toString()),
      deathReason: (json['deathReason'] ?? '').toString(),
      lowHealthYears: _toInt(json['lowHealthYears']),
      everCriticalHealth: json['everCriticalHealth'] == true,
      everHighSin: json['everHighSin'] == true,
      cleanYearsAfterJail: _toInt(json['cleanYearsAfterJail']),
      hospitalCount: _toInt(json['hospitalCount']),
      eraEventsSeen: _toStringList(json['eraEventsSeen']),
      maxSingleWealthGain: _toInt(json['maxSingleWealthGain']),
      maxSingleInvestLoss: _toInt(json['maxSingleInvestLoss']),
      everInvested: json['everInvested'] == true,
      oldFriends: _toStringList(json['oldFriends']),
      inherited: inherited,
      achievedNaturalDeath: json['achievedNaturalDeath'] == true,
      deathAge: _toInt(json['deathAge'], -1),
      actionPoints: _toInt(json['actionPoints'], 1),
      halfIncomeYear: json['halfIncomeYear'] == true,
      aiUsed: _toInt(json['aiUsed']),
      aiFails: _toInt(json['aiFails']),
      storyTitles: _toStringList(json['storyTitles']),
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> attrJson = <String, dynamic>{};
    attributes.forEach((AttributeKey key, int value) {
      attrJson[AttributeKeyX.toKey(key)] = value;
    });
    final Map<String, dynamic> inheritJson = <String, dynamic>{};
    inherited.forEach((AttributeKey key, int value) {
      inheritJson[AttributeKeyX.toKey(key)] = value;
    });

    return <String, dynamic>{
      'name': name,
      'gender': gender,
      'age': age,
      'era': era,
      'cityName': cityName,
      'wealthCapFactor': wealthCapFactor,
      'cityStressModifier': cityStressModifier,
      'attributes': attrJson,
      'assets': assets.toJson(),
      'addictions': addictions,
      'relations': relations.map((Relation e) => e.toJson()).toList(),
      'pets': pets.map((Pet e) => e.toJson()).toList(),
      'skills': skills,
      'talents': talents,
      'logs': logs.map((LifeLogEntry e) => e.toJson()).toList(),
      'hasJob': hasJob,
      'career': career,
      'careerLevel': careerLevel,
      'unemployed': unemployed,
      'retired': retired,
      'everJailed': everJailed,
      'hasCriminalRecord': hasCriminalRecord,
      'jailYearsLeft': jailYearsLeft,
      'totalJailYears': totalJailYears,
      'everCommuted': everCommuted,
      'everBoughtHouse': everBoughtHouse,
      'everBoughtCar': everBoughtCar,
      'everStartedBusiness': everStartedBusiness,
      'everMarried': everMarried,
      'everWithdrawal': everWithdrawal,
      'godModeUnlocked': godModeUnlocked,
      'godModeUsed': godModeUsed,
      'lifespan': lifespan,
      'status': _statusToKey(status),
      'deathReason': deathReason,
      'lowHealthYears': lowHealthYears,
      'everCriticalHealth': everCriticalHealth,
      'everHighSin': everHighSin,
      'cleanYearsAfterJail': cleanYearsAfterJail,
      'hospitalCount': hospitalCount,
      'eraEventsSeen': eraEventsSeen,
      'maxSingleWealthGain': maxSingleWealthGain,
      'maxSingleInvestLoss': maxSingleInvestLoss,
      'everInvested': everInvested,
      'oldFriends': oldFriends,
      'inherited': inheritJson,
      'achievedNaturalDeath': achievedNaturalDeath,
      'deathAge': deathAge,
      'actionPoints': actionPoints,
      'halfIncomeYear': halfIncomeYear,
      'aiUsed': aiUsed,
      'aiFails': aiFails,
      'storyTitles': storyTitles,
    };
  }

  /// 深拷贝（用于金手指预览、轮回快照）
  Character copy() => Character.fromJson(toJson());

  /// 状态字符串互转
  static String _statusToKey(LifeStatus status) {
    switch (status) {
      case LifeStatus.alive:
        return 'alive';
      case LifeStatus.inPrison:
        return 'inPrison';
      case LifeStatus.dead:
        return 'dead';
    }
  }

  static LifeStatus _statusFromKey(String key) {
    switch (key) {
      case 'inPrison':
        return LifeStatus.inPrison;
      case 'dead':
        return LifeStatus.dead;
      default:
        return LifeStatus.alive;
    }
  }
}

/// 容错取整
int _toInt(Object? value, [int fallback = 0]) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? fallback;
}

/// 容错取小数
double _toDouble(Object? value, double fallback) {
  if (value == null) return fallback;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? fallback;
}

/// 容错取字符串数组
List<String> _toStringList(Object? value) {
  final List<String> out = <String>[];
  if (value is List) {
    for (final Object? item in value) {
      if (item == null) continue;
      out.add(item.toString());
    }
  }
  return out;
}
