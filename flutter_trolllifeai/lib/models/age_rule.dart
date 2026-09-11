// 剧情逻辑规则表：年龄纠偏（ageRules）+ 前提校验（preconditions）。
//
// 规则来源 assets/json/age_rules.json，与网页版共用同一份文件（内容一字不改）。
//   · ageRules   只收窄事件年龄区间，绝不放大；规则互相冲突时放弃纠偏
//   · preconditions 校验剧情前提（没配偶不该离婚、没宠物不该宠物离世……）

/// 一条年龄纠偏规则
class AgeRule {
  /// 规则 id，例如 exam / romance
  final String id;

  /// 正则字符串，命中事件全文时生效
  final String keyword;

  /// 收窄后的最小年龄（null 表示不限制）
  final int? min;

  /// 收窄后的最大年龄（null 表示不限制）
  final int? max;

  /// 规则说明
  final String note;

  const AgeRule({
    required this.id,
    required this.keyword,
    this.min,
    this.max,
    this.note = '',
  });

  /// 从 JSON 解析（容错：kw 为空视为无效规则）
  factory AgeRule.fromJson(Map<String, dynamic> json) {
    return AgeRule(
      id: (json['id'] ?? '').toString(),
      keyword: (json['kw'] ?? '').toString(),
      min: _toIntOrNull(json['min']),
      max: _toIntOrNull(json['max']),
      note: (json['note'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'kw': keyword,
        if (min != null) 'min': min,
        if (max != null) 'max': max,
        if (note.isNotEmpty) 'note': note,
      };

  /// 规则是否可用（必须有 id 与关键词）
  bool get isValid => id.isNotEmpty && keyword.isNotEmpty;
}

/// 一条前提校验规则
class PreconditionRule {
  /// 规则 id，例如 partner / child
  final String id;

  /// 正则字符串：命中则进入校验
  final String keyword;

  /// 正则字符串：命中则跳过校验（例如「结婚」不该要求已有配偶）
  final String exclude;

  /// 需要满足的前提：partner / child / pet / convict / job
  final String need;

  /// 不满足时的原因文案
  final String reason;

  const PreconditionRule({
    required this.id,
    required this.keyword,
    this.exclude = '',
    required this.need,
    this.reason = '',
  });

  /// 从 JSON 解析
  factory PreconditionRule.fromJson(Map<String, dynamic> json) {
    return PreconditionRule(
      id: (json['id'] ?? '').toString(),
      keyword: (json['kw'] ?? '').toString(),
      exclude: (json['exclude'] ?? '').toString(),
      need: (json['need'] ?? '').toString(),
      reason: (json['reason'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'kw': keyword,
        if (exclude.isNotEmpty) 'exclude': exclude,
        'need': need,
        if (reason.isNotEmpty) 'reason': reason,
      };

  /// 规则是否可用（必须有 id、关键词与前提名）
  bool get isValid => id.isNotEmpty && keyword.isNotEmpty && need.isNotEmpty;
}

/// 规则集合：负责年龄纠偏与前提校验的判定入口
class AgeRuleSet {
  /// 年龄纠偏规则
  final List<AgeRule> ageRules;

  /// 前提校验规则
  final List<PreconditionRule> preconditions;

  /// 加载过程中的错误（界面可提示，不影响运行）
  final List<String> errors;

  const AgeRuleSet({
    this.ageRules = const <AgeRule>[],
    this.preconditions = const <PreconditionRule>[],
    this.errors = const <String>[],
  });

  /// 空规则集（资源缺失时的兜底：不纠偏、不校验，保证还能正常玩）
  static const AgeRuleSet empty = AgeRuleSet();

  /// 是否有任何可用规则
  bool get isEmpty => ageRules.isEmpty && preconditions.isEmpty;

  /// 从 JSON 解析（顶层为对象，缺字段按空处理）
  factory AgeRuleSet.fromJson(Map<String, dynamic> json) {
    final List<AgeRule> ages = <AgeRule>[];
    final Object? rawAges = json['ageRules'];
    if (rawAges is List) {
      for (final Object? item in rawAges) {
        if (item is! Map) continue;
        final AgeRule rule = AgeRule.fromJson(Map<String, dynamic>.from(item));
        if (rule.isValid) ages.add(rule);
      }
    }

    final List<PreconditionRule> pre = <PreconditionRule>[];
    final Object? rawPre = json['preconditions'];
    if (rawPre is List) {
      for (final Object? item in rawPre) {
        if (item is! Map) continue;
        final PreconditionRule rule =
            PreconditionRule.fromJson(Map<String, dynamic>.from(item));
        if (rule.isValid) pre.add(rule);
      }
    }

    return AgeRuleSet(ageRules: ages, preconditions: pre);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'ageRules': ageRules.map((AgeRule e) => e.toJson()).toList(),
        'preconditions':
            preconditions.map((PreconditionRule e) => e.toJson()).toList(),
      };

  /// 事件全文（标题 + 剧情 + 全部选项文本 + 选项结果描述），
  /// 与网页版 TL.eventText 保持一致，用于关键词匹配。
  static String eventText({
    required String title,
    required String story,
    required List<String> optionTexts,
    required List<String> descriptions,
  }) {
    final StringBuffer buffer = StringBuffer();
    buffer.write(title);
    buffer.write(' ');
    buffer.write(story);
    for (int i = 0; i < optionTexts.length; i++) {
      buffer.write(' ');
      buffer.write(optionTexts[i]);
    }
    for (int i = 0; i < descriptions.length; i++) {
      buffer.write(' ');
      buffer.write(descriptions[i]);
    }
    return buffer.toString();
  }

  /// 年龄纠偏：按规则收窄 [declaredMin, declaredMax]，只收窄不放大。
  ///
  /// - 任何命中规则的 min 抬高下界，max 压低上界；
  /// - 规则互相冲突（min > max）时放弃纠偏，返回原区间，避免事件永远不出现；
  /// - 上界 100 视为「终身」，放宽到 110，否则 101 岁以上抽不到任何事件。
  static List<int> effectiveAgeRange({
    required int declaredMin,
    required int declaredMax,
    required String text,
  }) {
    int lo = declaredMin;
    int hi = declaredMax;
    for (final AgeRule rule in _activeAgeRules) {
      if (rule.min == null && rule.max == null) continue;
      if (!_matches(rule.keyword, text)) continue;
      final int? rmin = rule.min;
      final int? rmax = rule.max;
      if (rmin != null && rmin > lo) lo = rmin;
      if (rmax != null && rmax < hi) hi = rmax;
    }
    if (lo > hi) return <int>[declaredMin, declaredMax];
    if (hi == 100) hi = 110;
    return <int>[lo, hi];
  }

  /// 当前生效的年龄规则（由 EventEngine 注入的全局表）
  static List<AgeRule> _activeAgeRules = const <AgeRule>[];

  /// 注入规则表（EventEngine 初始化时调用一次）
  static void install(AgeRuleSet rules) {
    _activeAgeRules = rules.ageRules;
  }

  /// 关键词匹配（正则失败时退化为普通包含判断，保证不抛异常）
  static bool _matches(String pattern, String text) {
    if (pattern.isEmpty || text.isEmpty) return false;
    try {
      return RegExp(pattern).hasMatch(text);
    } catch (_) {
      return text.contains(pattern);
    }
  }
}

/// 容错取整：非数值返回 null
int? _toIntOrNull(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  final int? parsed = int.tryParse(value.toString());
  return parsed;
}
