// 事件模型 + 标记语言的数据载体。
//
// 数据来源 assets/json/event.json（155 条）
// 元素结构：{age_range:[min,max], title, story, choices:[{option_text, attr_change, desc}]}
//
// title / story / desc 里可能带【...】标记，标记只做调用方解析，
// 模型本身只负责原样承载原文与「剔除标记后的展示文本」。

import 'character.dart';

/// 事件选项
class LifeEventChoice {
  /// 选项文字（按钮上展示）
  final String optionText;

  /// 属性变化（11 项，全部为 int）
  final StatDelta attrChange;

  /// 选项结果描述（原文，可能含【...】标记）
  final String rawDesc;

  /// 剔除标记后用于展示的结果描述
  final String displayDesc;

  const LifeEventChoice({
    required this.optionText,
    required this.attrChange,
    required this.rawDesc,
    required this.displayDesc,
  });

  /// 从 JSON 解析
  factory LifeEventChoice.fromJson(Map<String, dynamic> json) {
    final String desc = (json['desc'] ?? '').toString();
    return LifeEventChoice(
      optionText: (json['option_text'] ?? '继续').toString(),
      attrChange: StatDelta.fromJson(json['attr_change']),
      rawDesc: desc,
      displayDesc: LifeEventMarker.stripAll(desc),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'option_text': optionText,
        'attr_change': attrChange.toJson(),
        'desc': rawDesc,
      };

  /// 是否有属性变化（全 0 时界面不展示变化条）
  bool get hasAttrChange => !attrChange.isEmpty;
}

/// 一条人生事件
class LifeEvent {
  /// 事件标题（已剔除【...】标记，例如「【80年代】粮票布票换鸡蛋」→「粮票布票换鸡蛋」）
  final String title;

  /// 剧情正文（已剔除标记）
  final String story;

  /// 适用年龄区间 [min, max]
  final int minAge;
  final int maxAge;

  /// 选项列表
  final List<LifeEventChoice> choices;

  /// 原始标题（含标记，用于解析年代限定等信息）
  final String rawTitle;

  /// 原始剧情（含标记）
  final String rawStory;

  /// 该事件限定的年代列表（空表示不限年代）
  final List<String> eraLimit;

  /// 是否为「强制事件」（成瘾发作 / 入狱等系统内置事件）
  final bool forced;

  /// 是否为 AI 原创剧情（界面会展示「AI 原创」标记）
  final bool ai;

  /// 规则表纠偏后的有效年龄区间 [min, max]。
  /// 由 EventEngine 依据 assets/json/age_rules.json 计算并缓存；
  /// 未被纠偏时等于 [minAge, maxAge]（原始声明区间）。
  int effectiveMinAge = 0;

  /// 纠偏后的最大年龄
  int effectiveMaxAge = 110;

  /// 是否已经算过纠偏区间
  bool ageRuleApplied = false;

  /// 记录本次抽事件时该事件是否被前提校验拦下（仅用于调试展示）
  String blockedReason = '';

  const LifeEvent({
    required this.title,
    required this.story,
    required this.minAge,
    required this.maxAge,
    required this.choices,
    required this.rawTitle,
    required this.rawStory,
    this.eraLimit = const <String>[],
    this.forced = false,
    this.ai = false,
  });

  /// 从 JSON 解析（容错：age_range 缺失按 [0,100]，choices 为空时补一个空选项）
  factory LifeEvent.fromJson(Map<String, dynamic> json) {
    int minAge = 0;
    int maxAge = 100;
    final Object? rawRange = json['age_range'];
    if (rawRange is List && rawRange.length >= 2) {
      minAge = _toInt(rawRange[0]);
      maxAge = _toInt(rawRange[1]);
    }
    if (maxAge < minAge) maxAge = minAge;

    final List<LifeEventChoice> choices = <LifeEventChoice>[];
    final Object? rawChoices = json['choices'];
    if (rawChoices is List) {
      for (final Object? item in rawChoices) {
        if (item is Map) {
          choices.add(
            LifeEventChoice.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    if (choices.isEmpty) {
      // 剧本异常时的兜底，保证界面永远有可选按钮
      choices.add(
        const LifeEventChoice(
          optionText: '继续生活',
          attrChange: StatDelta.zero,
          rawDesc: '',
          displayDesc: '',
        ),
      );
    }

    final String rawTitle = (json['title'] ?? '平淡的一天').toString();
    final String rawStory = (json['story'] ?? '').toString();

    return LifeEvent(
      title: LifeEventMarker.stripAll(rawTitle),
      story: LifeEventMarker.stripAll(rawStory),
      minAge: minAge,
      maxAge: maxAge,
      choices: choices,
      rawTitle: rawTitle,
      rawStory: rawStory,
      eraLimit: LifeEventMarker.extractEraLimit(rawTitle),
      ai: json['ai'] == true,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'age_range': <int>[minAge, maxAge],
        'title': rawTitle,
        'story': rawStory,
        'choices':
            choices.map((LifeEventChoice e) => e.toJson()).toList(),
        'ai': ai,
      };

  /// 年龄是否落在「纠偏后」的有效区间内。
  ///
  /// 纠偏区间由 EventEngine 通过 applyAgeRange 写入；未纠偏时退化为原始区间，
  /// 因此本方法在没有规则数据时行为与旧版本一致。
  bool matchAge(int age) {
    if (!ageRuleApplied) return age >= minAge && age <= maxAge;
    return age >= effectiveMinAge && age <= effectiveMaxAge;
  }

  /// 原始声明区间是否命中（三级兜底的最末一级使用）
  bool matchDeclaredAge(int age) => age >= minAge && age <= maxAge;

  /// 写入纠偏后的年龄区间（由 EventEngine 调用）
  void applyAgeRange(int min, int max) {
    effectiveMinAge = min;
    effectiveMaxAge = max;
    ageRuleApplied = true;
  }

  /// 有效区间是否被收窄过（用于调试 / 展示）
  bool get ageRangeNarrowed =>
      ageRuleApplied && (effectiveMinAge != minAge || effectiveMaxAge != maxAge);

  /// 是否限定某个年代（eraLimit 为空则任何年代都可以）
  bool matchEra(String era) {
    if (eraLimit.isEmpty) return true;
    return eraLimit.contains(era);
  }

  /// 事件全部文本（标题 + 剧情 + 选项），用于技能关键词匹配
  String get allText {
    final StringBuffer buffer = StringBuffer(rawTitle);
    buffer.write(' ');
    buffer.write(rawStory);
    for (final LifeEventChoice c in choices) {
      buffer.write(' ');
      buffer.write(c.optionText);
      buffer.write(' ');
      buffer.write(c.rawDesc);
    }
    return buffer.toString();
  }

  /// 内置强制事件：成瘾发作（11 项属性齐全）
  factory LifeEvent.addictionBreakdown(String addictionName) {
    return LifeEvent(
      title: '成瘾发作：$addictionName',
      story: '半夜里你再一次控制不住自己。理智告诉你该停下，'
          '可身体已经先一步行动起来，你又一次熬到天亮，'
          '疲惫、愧疚和快感混在一起，压在胸口。',
      minAge: 0,
      maxAge: 120,
      rawTitle: '成瘾发作：$addictionName',
      rawStory: '',
      forced: true,
      choices: <LifeEventChoice>[
        LifeEventChoice(
          optionText: '硬扛过去，找人帮忙',
          attrChange: const StatDelta(<AttributeKey, int>{
            AttributeKey.intelligence: 0,
            AttributeKey.constitution: -3,
            AttributeKey.charm: 0,
            AttributeKey.wealth: -800,
            AttributeKey.happiness: -4,
            AttributeKey.luck: 0,
            AttributeKey.health: -4,
            AttributeKey.addiction: -18,
            AttributeKey.fame: 0,
            AttributeKey.stress: 6,
            AttributeKey.sin: 0,
          }),
          rawDesc: '你把手边的东西全扔了，硬生生熬过这一夜。【戒断:$addictionName】',
          displayDesc: '你把手边的东西全扔了，硬生生熬过这一夜。',
        ),
        LifeEventChoice(
          optionText: '向家人朋友求助',
          attrChange: const StatDelta(<AttributeKey, int>{
            AttributeKey.intelligence: 0,
            AttributeKey.constitution: -2,
            AttributeKey.charm: 1,
            AttributeKey.wealth: -2000,
            AttributeKey.happiness: 3,
            AttributeKey.luck: 0,
            AttributeKey.health: -2,
            AttributeKey.addiction: -12,
            AttributeKey.fame: 0,
            AttributeKey.stress: -4,
            AttributeKey.sin: 0,
          }),
          rawDesc: '有人陪着你，这一次你没有一个人扛。【关系:friend:戒友】',
          displayDesc: '有人陪着你，这一次你没有一个人扛。',
        ),
        LifeEventChoice(
          optionText: '彻底放纵，明天再说',
          attrChange: const StatDelta(<AttributeKey, int>{
            AttributeKey.intelligence: -2,
            AttributeKey.constitution: -5,
            AttributeKey.charm: -1,
            AttributeKey.wealth: -1500,
            AttributeKey.happiness: 2,
            AttributeKey.luck: -2,
            AttributeKey.health: -7,
            AttributeKey.addiction: 12,
            AttributeKey.fame: 0,
            AttributeKey.stress: 3,
            AttributeKey.sin: 1,
          }),
          rawDesc: '你把自己交给本能，第二天醒来只剩空荡的房间。',
          displayDesc: '你把自己交给本能，第二天醒来只剩空荡的房间。',
        ),
      ],
    );
  }

  /// 内置强制事件：被捕入狱（服刑年数由引擎写入）
  factory LifeEvent.arrest(int years) {
    return LifeEvent(
      title: '被捕入狱',
      story: '敲门声在凌晨响起。你被带走的那一刻，'
          '楼道里的邻居都推开了一条门缝。判决下来：有期徒刑 $years 年。',
      minAge: 0,
      maxAge: 120,
      rawTitle: '被捕入狱',
      rawStory: '',
      forced: true,
      choices: <LifeEventChoice>[
        LifeEventChoice(
          optionText: '接受判决，好好服刑',
          attrChange: const StatDelta(<AttributeKey, int>{
            AttributeKey.intelligence: 0,
            AttributeKey.constitution: -2,
            AttributeKey.charm: -3,
            AttributeKey.wealth: -3000,
            AttributeKey.happiness: -10,
            AttributeKey.luck: -2,
            AttributeKey.health: -3,
            AttributeKey.addiction: 0,
            AttributeKey.fame: -10,
            AttributeKey.stress: 8,
            AttributeKey.sin: -5,
          }),
          rawDesc: '你低着头听完判决，被带上了车。【入狱:$years】【案底】',
          displayDesc: '你低着头听完判决，被带上了车。',
        ),
      ],
    );
  }

  /// 内置强制事件：出狱
  factory LifeEvent.release(int servedYears) {
    return LifeEvent(
      title: '刑满释放',
      story: '铁门在身后关上。你在里面待了 $servedYears 年，'
          '外面的世界换了模样，手机、扫码、外卖，你都要重新学一遍。',
      minAge: 0,
      maxAge: 120,
      rawTitle: '刑满释放',
      rawStory: '',
      forced: true,
      choices: <LifeEventChoice>[
        LifeEventChoice(
          optionText: '重新做人',
          attrChange: const StatDelta(<AttributeKey, int>{
            AttributeKey.intelligence: 0,
            AttributeKey.constitution: -2,
            AttributeKey.charm: -2,
            AttributeKey.wealth: 2000,
            AttributeKey.happiness: 4,
            AttributeKey.luck: 0,
            AttributeKey.health: -2,
            AttributeKey.addiction: 0,
            AttributeKey.fame: -5,
            AttributeKey.stress: -6,
            AttributeKey.sin: -10,
          }),
          rawDesc: '你决定把过去留在门里。【出狱】',
          displayDesc: '你决定把过去留在门里。',
        ),
      ],
    );
  }
}

/// 标记语言工具：统一负责【...】标记的识别、提取与剔除。
class LifeEventMarker {
  const LifeEventMarker._();

  /// 所有标记的通用正则
  static final RegExp _markerPattern = RegExp('【([^】]*)】');

  /// 关键词 → 年代键 的映射（用于「80年代」这种无冒号写法）
  static const Map<String, String> eraKeywordMap = <String, String>{
    '80年代': '80',
    '90年代': '90',
    '00年代': '00',
    '10年代': '10',
    '20年代': '20',
    '80': '80',
    '90': '90',
    '00': '00',
    '10': '10',
    '20': '20',
  };

  /// 提取文本中出现的全部原始标记（不含方括号）
  static List<String> rawMarkers(String text) {
    final List<String> out = <String>[];
    if (text.isEmpty) return out;
    for (final RegExpMatch match in _markerPattern.allMatches(text)) {
      final String? inner = match.group(1);
      if (inner != null && inner.isNotEmpty) out.add(inner);
    }
    return out;
  }

  /// 剔除全部标记，并清理多余的空白，
  /// 保证玩家永远不会看到【...】。
  static String stripAll(String text) {
    if (text.isEmpty) return text;
    String cleaned = text.replaceAll(_markerPattern, '');
    cleaned = cleaned.replaceAll(RegExp(r'[ \t]{2,}'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\s+([，。！？、；：])'), r'$1');
    return cleaned.trim();
  }

  /// 从标题里提取年代限定，例如
  /// 「【80年代】粮票布票换鸡蛋」→ ['80']
  /// 「【年代:90】xxx」→ ['90']
  static List<String> extractEraLimit(String text) {
    final List<String> out = <String>[];
    for (final String marker in rawMarkers(text)) {
      final String era = eraFromMarker(marker);
      if (era.isNotEmpty && !out.contains(era)) out.add(era);
    }
    return out;
  }

  /// 单个标记 → 年代键，无法识别时返回空串
  static String eraFromMarker(String marker) {
    final String m = marker.trim();
    if (m.isEmpty) return '';
    if (m.startsWith('年代')) {
      // 【年代:80】
      final List<String> parts = m.split(':');
      if (parts.length >= 2) {
        final String value = parts[1].trim();
        if (eraKeywordMap.containsKey(value)) return eraKeywordMap[value]!;
      }
      return '';
    }
    // 整段就是年代关键词的标记才算年代标记
    // （避免把【关系:friend:小林】里的内容误判为年代）
    if (eraKeywordMap.containsKey(m)) return eraKeywordMap[m]!;
    return '';
  }

  /// 判断一个标记是不是年代标记
  static bool isEraMarker(String marker) => eraFromMarker(marker).isNotEmpty;
}
