// AI 剧情引擎：可配置的 OpenAI 兼容接口（默认 DeepSeek 官方端点）。
//
// 设计要点（与网页版 src/js/03_ai.js 对齐）：
//   1) 接口完全可配置：地址 / 模型 / Key / 触发频率 / 每世上限 / 超时 / JSON 模式 / 起始年龄；
//   2) Key 只写在本机独立小文件 ai_config.json 里，**绝不硬编码进代码**，也不随存档导出；
//   3) 网络用 dart:io 的 HttpClient 自己 POST，不引入任何第三方依赖；
//   4) AI 只负责「生成一条剧情」，能不能落地由本地严格校验：结构不对 / 属性越界 / 超时
//      → 一律回退本地事件池，绝不卡住游戏。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/character.dart';
import '../models/life_event.dart';
import '../models/relation.dart';
import '../models/skill.dart';
import 'data_loader.dart';
import 'storage_service.dart';

/// 默认接口地址（OpenAI 兼容的 chat/completions）
const String kAiDefaultUrl = 'https://api.deepseek.com/v1/chat/completions';

/// 默认模型
const String kAiDefaultModel = 'deepseek-chat';

/// AI 剧情引擎配置（可变对象，改完交给 AiOptionsStore 落盘）
class AiOptions {
  /// 是否启用 AI 续写
  bool enabled;

  /// 接口地址（OpenAI 兼容的 chat/completions）
  String url;

  /// 模型名
  String model;

  /// API Key（只存本机）
  String apiKey;

  /// 每年触发 AI 续写的概率 0-1
  double chance;

  /// 每世最多请求次数
  int maxPerLife;

  /// 单次请求超时（毫秒）
  int timeoutMs;

  /// 是否带 response_format: json_object
  bool jsonMode;

  /// 从这个年龄开始才用 AI（童年留白）
  int startAge;

  /// 默认接口地址
  static const String defaultUrl = kAiDefaultUrl;

  /// 默认模型
  static const String defaultModel = kAiDefaultModel;

  AiOptions({
    this.enabled = false,
    this.url = kAiDefaultUrl,
    this.model = kAiDefaultModel,
    this.apiKey = '',
    this.chance = 0.35,
    this.maxPerLife = 30,
    this.timeoutMs = 45000,
    this.jsonMode = true,
    this.startAge = 6,
  });

  /// 从 JSON 还原（容错：缺失字段用默认值）
  factory AiOptions.fromJson(Map<String, dynamic> json) {
    final AiOptions draft = AiOptions();
    draft.enabled = json['enabled'] == true;
    final String url = (json['url'] ?? '').toString().trim();
    if (url.isNotEmpty) draft.url = url;
    final String model = (json['model'] ?? '').toString().trim();
    if (model.isNotEmpty) draft.model = model;
    draft.apiKey = (json['apiKey'] ?? json['key'] ?? '').toString().trim();
    draft.chance = _toDouble(json['chance'], draft.chance);
    draft.maxPerLife = _toInt(json['maxPerLife'], draft.maxPerLife);
    draft.timeoutMs = _toInt(json['timeoutMs'], _toInt(json['timeout'], draft.timeoutMs));
    draft.jsonMode = json['jsonMode'] == null ? true : json['jsonMode'] == true;
    draft.startAge = _toInt(json['startAge'], draft.startAge);
    draft.normalize();
    return draft;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'enabled': enabled,
        'url': url,
        'model': model,
        'apiKey': apiKey,
        'chance': chance,
        'maxPerLife': maxPerLife,
        'timeoutMs': timeoutMs,
        'jsonMode': jsonMode,
        'startAge': startAge,
      };

  /// 拷贝一份（界面编辑时用，避免直接改到生效中的配置）
  AiOptions clone() => AiOptions.fromJson(toJson());

  /// 把全部数值夹到合理范围
  void normalize() {
    if (chance < 0) chance = 0;
    if (chance > 1) chance = 1;
    if (maxPerLife < 0) maxPerLife = 0;
    if (maxPerLife > 500) maxPerLife = 500;
    if (timeoutMs < 3000) timeoutMs = 3000;
    if (timeoutMs > 120000) timeoutMs = 120000;
    if (startAge < 0) startAge = 0;
    if (startAge > 60) startAge = 60;
    if (url.trim().isEmpty) url = defaultUrl;
    if (model.trim().isEmpty) model = defaultModel;
  }

  /// 是否已经具备请求条件
  bool get ready =>
      enabled && url.trim().isNotEmpty && model.trim().isNotEmpty && apiKey.trim().isNotEmpty;

  /// 状态文案（设置页顶部展示）
  String get statusText {
    if (!enabled) return '已关闭';
    if (apiKey.trim().isEmpty) return '缺少 API Key';
    if (url.trim().isEmpty) return '缺少接口地址';
    return '已启用（$model）';
  }
}

/// AI 配置的本地持久化（独立小文件，与存档同一目录）
class AiOptionsStore {
  /// 存档服务
  final StorageService storage;

  /// 配置文件名
  static const String fileName = 'ai_config.json';

  AiOptionsStore(this.storage);

  /// 读取配置；文件不存在或损坏时返回默认配置
  Future<AiOptions> load() async {
    final String? raw = await storage.readExtraFile(fileName);
    if (raw == null || raw.trim().isEmpty) return AiOptions();
    try {
      final Object? decoded = json.decode(raw);
      if (decoded is! Map) return AiOptions();
      return AiOptions.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return AiOptions();
    }
  }

  /// 写入配置
  Future<bool> save(AiOptions draft) {
    draft.normalize();
    return storage.writeExtraFile(fileName, json.encode(draft.toJson()));
  }

  /// 配置文件路径说明
  String get path => storage.extraFilePath(fileName);
}

/// 一次等待中的 AI 续写请求。
///
/// 界面据此弹出「AI 正在续写剧情…」；请求结束（成功 / 失败 / 玩家放弃）时
/// `done` 会被 complete，界面关闭弹窗后再让 GameProvider 落地结果。
class AiPendingRequest {
  /// 被挂起的本地事件（AI 失败时回退用它）
  final LifeEvent localEvent;

  /// 发起请求时的年龄（等待框展示用）
  final int age;

  /// 结束信号（幂等 complete）
  final Completer<void> done = Completer<void>();

  /// 玩家是否点了「不等了，用本地剧情」
  bool cancelled = false;

  /// 是否请求失败
  bool failed = false;

  /// 失败原因
  String error = '';

  /// AI 生成出来并通过校验的事件
  LifeEvent? aiEvent;

  AiPendingRequest({required this.localEvent, required this.age});

  /// 是否已经有结果
  bool get finished => done.isCompleted;

  /// 标记结束（幂等）
  void markFinished() {
    if (!done.isCompleted) done.complete();
  }
}

/// 连接测试结果
class AiTestResult {
  /// 是否成功
  final bool ok;

  /// 成功提示 / 失败原因
  final String message;

  const AiTestResult(this.ok, this.message);
}

/// 一次 AI 剧情生成的结果（event 为 null 表示失败，error 是原因）
class AiGenerateResult {
  /// 生成出来的事件（已通过本地校验）
  final LifeEvent? event;

  /// 失败原因
  final String error;

  const AiGenerateResult({this.event, this.error = ''});

  /// 是否成功
  bool get ok => event != null;
}

/// 生成提示词所需的当前人生状态
class AiStoryContext {
  /// 当前角色
  final Character character;

  /// 剧本数据（技能名映射）
  final GameDataBundle data;

  /// 年代显示名，例如「00年代」
  final String eraLabel;

  /// 月薪（0 表示无业）
  final int monthlySalary;

  /// 最近已经发生过的剧情标题（避免重复）
  final List<String> recentTitles;

  const AiStoryContext({
    required this.character,
    required this.data,
    required this.eraLabel,
    this.monthlySalary = 0,
    this.recentTitles = const <String>[],
  });
}

/// AI 剧情服务
class AiService {
  /// 配置持久化
  final AiOptionsStore store;

  AiService({required StorageService storage}) : store = AiOptionsStore(storage);

  /// SYSTEM 提示词（严格 JSON 要求，参考网页版 03_ai.js）
  static const String systemPrompt =
      '你是一款中文文字人生模拟器（人生重开模拟器）的剧情引擎。\n'
      '你要根据玩家当前的人生状态，原创一条贴合年龄、年代、城市、职业与属性的剧情事件。\n'
      '只输出一个 JSON 对象，不要任何解释、不要 markdown 代码块、不要多余文字。\n'
      'JSON 结构固定为：\n'
      '{"title":"事件标题","story":"第二人称剧情描述","choices":[{"option_text":"选项","desc":"结果说明","attr_change":{"智力":0,"体质":0,"魅力":0,"财富":0,"快乐":0,"运气":0,"健康值":0,"成瘾值":0,"名声值":0,"压力值":0,"罪恶值":0}}]}\n'
      '硬性规则：\n'
      '1. attr_change 必须完整包含 11 个键：智力、体质、魅力、财富、快乐、运气、健康值、成瘾值、名声值、压力值、罪恶值，值必须是整数。\n'
      '2. 除财富外每项取值范围 -15 到 15；财富取 -30000 到 30000。成瘾值、罪恶值只能取 0 到 20。\n'
      '3. title 不超过 18 个字，story 60-120 字，choices 2 到 3 个，option_text 不超过 14 个字，desc 不超过 40 字。\n'
      '4. 选项之间必须有取舍（有得有失），禁止出现只有好处没有代价的选项。\n'
      '5. 不要使用书名号双引号，需要引号时用「」。\n'
      '6. desc 末尾可选地追加剧情标记（不要新增 JSON 字段），可用：【习得:skillId】【关系:friend:名字】'
      '【关系结束:名字】【职业:岗位】【升职】【失业】【跳槽】【创业】【破产】【入狱:年数】【出狱】【案底】'
      '【减刑】【买房】【买车】【负债:金额】【还债:金额】【成瘾:烟瘾】【戒断:酒瘾】【宠物:猫】【宠物离世】，每个 desc 最多 2 个。';

  /// 拼装 USER 提示词：把玩家当前状态全部喂给模型
  String buildUserPrompt(AiStoryContext ctx) {
    final Character c = ctx.character;
    final List<String> lines = <String>[];
    lines.add('【当前人生状态】');
    lines.add('年龄：${c.age} 岁');
    lines.add('年代：${ctx.eraLabel}；出生城市：${c.cityName}');
    if (c.hasJob && c.career != '无') {
      lines.add('职业：${c.career}（月薪 ${ctx.monthlySalary}）');
    } else {
      lines.add('职业：无业');
    }
    if (c.inPrison) {
      lines.add('状态：正在服刑（剩余 ${c.jailYearsLeft} 年）');
    }

    final List<String> attrLine = <String>[];
    for (final AttributeKey key in AttributeKeyX.all) {
      attrLine.add('${AttributeKeyX.toKey(key)}${c.attr(key)}');
    }
    lines.add('属性：${attrLine.join('，')}');

    if (c.skills.isNotEmpty) {
      final Map<String, Skill> index = ctx.data.skillIndex;
      final List<String> names = <String>[];
      for (final String id in c.skills) {
        names.add(index[id]?.name ?? id);
      }
      lines.add('已习得技能：${names.join('、')}');
    }

    final List<Relation> alive = c.activeRelations;
    if (alive.isNotEmpty) {
      final List<String> rels = <String>[];
      for (int i = 0; i < alive.length && i < 6; i++) {
        final Relation r = alive[i];
        rels.add('${RelationTypeX.label(r.type)}${r.name}(好感${r.favor})');
      }
      lines.add('重要关系：${rels.join('、')}');
      lines.add('关系数量：朋友 ${c.countRelation(RelationType.friend)}，'
          '恋人 ${c.countRelation(RelationType.lover)}，'
          '配偶 ${c.countRelation(RelationType.spouse)}，'
          '子女 ${c.childCount}，仇人 ${c.enemyCount}');
    }

    if (c.activePets.isNotEmpty) {
      final List<String> pets = <String>[];
      for (int i = 0; i < c.activePets.length && i < 3; i++) {
        pets.add('${c.activePets[i].name}(${c.activePets[i].species})');
      }
      lines.add('宠物：${pets.join('、')}');
    }

    final List<String> addictionLine = <String>[];
    c.addictions.forEach((String name, int value) {
      if (value > 0) addictionLine.add('$name$value');
    });
    if (addictionLine.isNotEmpty) {
      lines.add('成瘾：${addictionLine.join('、')}');
    }

    if (ctx.recentTitles.isNotEmpty) {
      lines.add('');
      lines.add('【最近已经发生过的剧情（不要重复这些主题与标题）】');
      lines.add(ctx.recentTitles.join(' / '));
    }

    lines.add('');
    lines.add('【任务】');
    lines.add('请为这个 ${c.age} 岁的人，原创 1 条${ctx.eraLabel}背景下、'
        '发生在${c.cityName}的剧情事件，并给出 2-3 个有取舍的选项与完整的 11 项属性变化。只输出 JSON。');
    if (c.age <= 6) {
      lines.add('注意：这是幼儿阶段，剧情要贴近童年日常。');
    } else if (c.age <= 17) {
      lines.add('注意：这是学生阶段，剧情要贴近校园与家庭。');
    } else if (c.age >= 60) {
      lines.add('注意：这是老年阶段，剧情要贴近健康、养老与家庭。');
    }
    return lines.join('\n');
  }

  /// 连接自检：发一条极短请求验证 Key / 地址 / 模型
  Future<AiTestResult> test(AiOptions draft) async {
    if (draft.url.trim().isEmpty || draft.model.trim().isEmpty) {
      return const AiTestResult(false, '请先填写接口地址与模型');
    }
    if (draft.apiKey.trim().isEmpty) {
      return const AiTestResult(false, '请先填写 API Key');
    }
    final Map<String, dynamic> body = <String, dynamic>{
      'model': draft.model,
      'messages': <Map<String, String>>[
        <String, String>{'role': 'user', 'content': '只回复两个字：通过'},
      ],
      'temperature': 0,
      'max_tokens': 16,
      'stream': false,
    };
    final int timeout = draft.timeoutMs < 20000 ? draft.timeoutMs : 20000;
    final _HttpResult res = await _postJson(
      draft.url,
      _headers(draft.apiKey),
      json.encode(body),
      timeout,
    );
    if (res.error.isNotEmpty) {
      return AiTestResult(false, '连接失败：${res.error}');
    }
    if (res.status < 200 || res.status >= 300) {
      return AiTestResult(false, '接口返回 ${res.status}${_hint(res.body, 120)}');
    }
    final Object? decoded = _decode(res.body);
    if (decoded is! Map) return const AiTestResult(false, '返回解析失败：不是 JSON');
    final String content = _extractContent(Map<String, dynamic>.from(decoded));
    if (content.isEmpty) return const AiTestResult(false, '返回解析失败：没有内容');
    return AiTestResult(true, '连接成功，模型回复：${_clip(content, 30)}');
  }

  /// 生成一条 AI 剧情事件（失败时返回 error，调用方回退本地事件）
  Future<AiGenerateResult> generate(
    AiOptions draft,
    AiStoryContext ctx,
  ) async {
    if (draft.url.trim().isEmpty || draft.model.trim().isEmpty) {
      return const AiGenerateResult(error: '缺少接口地址或模型');
    }
    if (draft.apiKey.trim().isEmpty) {
      return const AiGenerateResult(error: '缺少 API Key');
    }

    final Map<String, dynamic> body = <String, dynamic>{
      'model': draft.model,
      'messages': <Map<String, String>>[
        <String, String>{'role': 'system', 'content': systemPrompt},
        <String, String>{'role': 'user', 'content': buildUserPrompt(ctx)},
      ],
      'temperature': 1.1,
      'max_tokens': 900,
      'stream': false,
    };
    if (draft.jsonMode) {
      body['response_format'] = <String, String>{'type': 'json_object'};
    }

    final _HttpResult res = await _postJson(
      draft.url,
      _headers(draft.apiKey),
      json.encode(body),
      draft.timeoutMs,
    );
    if (res.error.isNotEmpty) {
      return AiGenerateResult(error: '请求失败：${res.error}');
    }
    if (res.status < 200 || res.status >= 300) {
      return AiGenerateResult(error: '接口返回 ${res.status}${_hint(res.body, 160)}');
    }
    final Object? decoded = _decode(res.body);
    if (decoded is! Map) {
      return const AiGenerateResult(error: '返回内容不是 JSON');
    }
    final String content = _extractContent(Map<String, dynamic>.from(decoded));
    if (content.isEmpty) {
      return const AiGenerateResult(error: '返回里没有剧情内容');
    }
    final Map<String, dynamic>? obj = extractJson(content);
    if (obj == null) {
      return const AiGenerateResult(error: '剧情 JSON 解析失败');
    }
    final LifeEvent? event = normalizeEvent(obj, age: ctx.character.age);
    if (event == null) {
      return const AiGenerateResult(error: '剧情结构不合格（已丢弃）');
    }
    return AiGenerateResult(event: event);
  }

  /// 从模型返回的文本里抽取 JSON（兼容 ```json 代码块与前后废话）
  static Map<String, dynamic>? extractJson(String text) {
    String body = text.replaceAll('```json', '```').replaceAll('```', '').trim();
    final int start = body.indexOf('{');
    final int end = body.lastIndexOf('}');
    if (start < 0 || end < 0 || end <= start) return null;
    body = body.substring(start, end + 1);

    final Object? first = _decode(body);
    if (first is Map) return Map<String, dynamic>.from(first);
    // 常见问题兜底：去掉尾随逗号再试一次
    final Object? second = _decode(body.replaceAll(RegExp(r',\s*([}\]])'), r'$1'));
    if (second is Map) return Map<String, dynamic>.from(second);
    return null;
  }

  /// 规范化 AI 返回的事件：结构不合格返回 null，越界夹取、缺字段补 0
  static LifeEvent? normalizeEvent(Map<String, dynamic> raw, {required int age}) {
    final String title = _clip((raw['title'] ?? '').toString(), 24);
    final String story = _clip((raw['story'] ?? raw['desc'] ?? '').toString(), 260);
    if (title.isEmpty || story.isEmpty) return null;

    Object? rawChoices = raw['choices'];
    if (rawChoices is! List || rawChoices.isEmpty) {
      rawChoices = raw['options'];
    }
    if (rawChoices is! List || rawChoices.isEmpty) return null;

    final List<LifeEventChoice> choices = <LifeEventChoice>[];
    for (final Object? item in rawChoices) {
      if (choices.length >= 3) break;
      if (item is! Map) continue;
      final Map<String, dynamic> choiceJson = Map<String, dynamic>.from(item);
      final String optionText = _clip(
        (choiceJson['option_text'] ??
                choiceJson['text'] ??
                choiceJson['option'] ??
                '')
            .toString(),
        18,
      );
      if (optionText.isEmpty) continue;

      final Object? rawChange = choiceJson['attr_change'] ??
          choiceJson['attrChange'] ??
          choiceJson['attributes'];
      if (rawChange is! Map) continue;
      final Map<String, dynamic> changeMap = Map<String, dynamic>.from(rawChange);
      // 11 项属性整块缺失（一个已知键都没有）视为不合格选项
      if (!_hasAnyAttribute(changeMap)) continue;

      final String desc = _clip(
        (choiceJson['desc'] ?? choiceJson['description'] ?? '').toString(),
        70,
      );
      choices.add(
        LifeEventChoice(
          optionText: optionText,
          attrChange: _normalizeDelta(changeMap),
          rawDesc: desc,
          displayDesc: LifeEventMarker.stripAll(desc),
        ),
      );
    }
    // 选项必须 2-3 个，否则丢弃整条剧情
    if (choices.length < 2) return null;

    return LifeEvent(
      title: LifeEventMarker.stripAll(title),
      story: LifeEventMarker.stripAll(story),
      minAge: age,
      maxAge: 110,
      choices: choices,
      rawTitle: title,
      rawStory: story,
      eraLimit: LifeEventMarker.extractEraLimit(title),
      ai: true,
    );
  }

  /// 规范化 11 项属性变化
  static StatDelta _normalizeDelta(Map<String, dynamic> src) {
    final Map<AttributeKey, int> values = <AttributeKey, int>{};
    for (final AttributeKey key in AttributeKeyX.all) {
      final Object? rawValue = src[AttributeKeyX.toKey(key)];
      int value;
      if (rawValue == null || rawValue is bool) {
        value = 0;
      } else if (rawValue is num) {
        value = rawValue.round();
      } else {
        value = int.tryParse(rawValue.toString().trim()) ?? 0;
      }
      final int low = _lowBound(key);
      final int high = _highBound(key);
      if (value < low) value = low;
      if (value > high) value = high;
      values[key] = value;
    }
    return StatDelta(values);
  }

  /// 是否至少包含一项已知属性键
  static bool _hasAnyAttribute(Map<String, dynamic> src) {
    for (final AttributeKey key in AttributeKeyX.all) {
      if (src.containsKey(AttributeKeyX.toKey(key))) return true;
    }
    return false;
  }

  /// 属性下限：财富 -30000，成瘾值 / 罪恶值 0，其余 -15
  static int _lowBound(AttributeKey key) {
    if (key == AttributeKey.wealth) return -30000;
    if (key == AttributeKey.addiction || key == AttributeKey.sin) return 0;
    return -15;
  }

  /// 属性上限：财富 +30000，成瘾值 / 罪恶值 20，其余 +15
  static int _highBound(AttributeKey key) {
    if (key == AttributeKey.wealth) return 30000;
    if (key == AttributeKey.addiction || key == AttributeKey.sin) return 20;
    return 15;
  }

  /// 统一请求头
  static Map<String, String> _headers(String apiKey) {
    return <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${apiKey.trim()}',
    };
  }

  /// dart:io 自实现的 POST（不依赖任何第三方 HTTP 包）
  Future<_HttpResult> _postJson(
    String url,
    Map<String, String> headers,
    String body,
    int timeoutMs,
  ) async {
    final Uri? uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) {
      return const _HttpResult(error: '接口地址不合法');
    }
    final Duration timeout = Duration(milliseconds: timeoutMs);
    final HttpClient client = HttpClient();
    client.connectionTimeout = timeout;
    try {
      final HttpClientRequest request = await client.postUrl(uri).timeout(timeout);
      headers.forEach((String name, String value) {
        request.headers.set(name, value);
      });
      request.add(utf8.encode(body));
      final HttpClientResponse response = await request.close().timeout(timeout);
      final String text =
          await response.transform(utf8.decoder).join().timeout(timeout);
      return _HttpResult(status: response.statusCode, body: text);
    } on TimeoutException {
      return const _HttpResult(error: 'TIMEOUT（请求超时）');
    } catch (e) {
      return _HttpResult(error: e.toString());
    } finally {
      client.close(force: true);
    }
  }

  /// 从 OpenAI 兼容返回里取正文
  static String _extractContent(Map<String, dynamic> data) {
    final Object? choices = data['choices'];
    if (choices is List && choices.isNotEmpty) {
      final Object? first = choices[0];
      if (first is Map) {
        final Object? message = first['message'];
        if (message is Map) {
          final Object? content = message['content'];
          if (content != null) return content.toString();
        }
        final Object? text = first['text'];
        if (text != null) return text.toString();
      }
    }
    final Object? output = data['output_text'];
    if (output != null) return output.toString();
    final Object? content = data['content'];
    if (content != null) return content.toString();
    return '';
  }

  /// 接口错误提示片段
  static String _hint(String body, int max) {
    final String text = body.trim();
    if (text.isEmpty) return '';
    return '：${_clip(text, max)}';
  }

  /// 容错 JSON 解码
  static Object? _decode(String text) {
    if (text.trim().isEmpty) return null;
    try {
      return json.decode(text);
    } catch (_) {
      return null;
    }
  }

  /// 清理文本：换行压平、英文引号换成书名号、限制长度
  static String _clip(String text, int max) {
    String s = text;
    s = s.replaceAll('\u201C', '「');
    s = s.replaceAll('\u201D', '」');
    s = s.replaceAll('\r', ' ');
    s = s.replaceAll('\n', ' ');
    s = s.trim();
    if (s.length > max) s = s.substring(0, max);
    return s;
  }
}

/// 一次 HTTP POST 的结果（error 非空表示请求本身失败）
class _HttpResult {
  /// HTTP 状态码
  final int status;

  /// 响应正文
  final String body;

  /// 网络层错误
  final String error;

  const _HttpResult({this.status = 0, this.body = '', this.error = ''});
}

/// 容错取整
int _toInt(Object? value, int fallback) {
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
