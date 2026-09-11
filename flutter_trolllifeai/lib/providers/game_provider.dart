// 全局游戏状态：ChangeNotifier。
//
// 页面只与 GameProvider 交互，不直接改 Character，
// 保证「属性变化 → 成就判定 → 日志 → 存档」这条链路只有一处实现。

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/achievement.dart';
import '../models/character.dart';
import '../models/city_data.dart';
import '../models/life_event.dart';
import '../models/pet.dart';
import '../models/relation.dart';
import '../models/skill.dart';
import '../models/talent.dart';
import '../services/action_engine.dart';
import '../services/ai_service.dart';
import '../services/data_loader.dart';
import '../services/event_engine.dart';
import '../services/score_service.dart';
import '../services/storage_service.dart';

/// 金手指解锁密码
const String kGodPassword = '208526';

/// 天赋抽取时每次展示的候选数量
const int kTalentPickCount = 3;

/// 游戏流程阶段
enum GamePhase {
  /// 数据加载中
  loading,

  /// 开局：选年代 / 城市 / 天赋
  setup,

  /// 推进中（有存活角色）
  running,

  /// 本局已结束，等待转世
  finished,
}

/// 天赋抽取结果（3 选 1）
///
/// 作为开局页的数据载体：页面展示 candidates，重抽时替换整个对象。
class TalentDraw {
  /// 本次抽到的 3 个天赋
  final List<Talent> candidates;

  /// 已经重抽过的次数
  final int rerollUsed;

  const TalentDraw({required this.candidates, required this.rerollUsed});

  /// 还能重抽几次
  int get rerollLeft => max(0, kMaxReroll - rerollUsed);

  /// 是否还能重抽
  bool get canReroll => rerollLeft > 0;
}

/// 最多可重抽次数
const int kMaxReroll = 3;

/// 全局游戏状态
class GameProvider extends ChangeNotifier {
  /// 剧本数据（init 后可用）
  GameDataBundle data = GameDataBundle.empty;

  /// 数据加载中
  bool isLoading = true;

  /// 数据加载错误（非空时界面会提示）
  String loadError = '';

  /// 存档服务
  final StorageService storage = StorageService();

  /// 事件引擎
  EventEngine? _engine;

  /// 主动行动与关系互动引擎（init 后可用）
  ActionEngine? _actionEngine;

  /// AI 剧情服务（配置写在本机独立小文件里）
  late final AiService ai = AiService(storage: storage);

  /// AI 配置（init 时从本机读取，默认关闭）
  AiOptions aiOptions = AiOptions();

  /// 正在等待 AI 结果的请求（界面据此弹「AI 正在续写剧情…」）
  AiPendingRequest? pendingAiRequest;

  /// 当前展示的事件是否来自 AI 原创
  bool currentEventIsAi = false;

  /// 本世 AI 原创过的剧情标题（倒序，设置页展示用）
  final List<String> aiGeneratedTitles = <String>[];

  /// 一次性的 AI 提示文本（界面取走后清空）
  String _aiNotice = '';

  /// 存档槽位数量（与网页版一致：3 个）
  static const int saveSlotCount = 3;

  /// 当前角色（未开局时为 null）
  Character? character;

  /// 已解锁成就：成就名 → 解锁记录
  final Map<String, AchievementRecord> unlocked = <String, AchievementRecord>{};

  /// 已经历的世数（第一世为 1）
  int generation = 1;

  /// 上一世继承的属性
  Map<AttributeKey, int> inheritedAttributes = <AttributeKey, int>{};

  /// 最近一次解锁的成就（界面用来弹出提示）
  final List<String> lastUnlocked = <String>[];

  // -------------------------- 开局流程状态 --------------------------

  /// 已选年代（80/90/00/10/20）
  String selectedEra = '00';

  /// 已选城市
  CityData? selectedCity;

  /// 当前天赋候选
  List<Talent> talentCandidates = <Talent>[];

  /// 已重抽次数
  int rerollUsed = 0;

  // -------------------------- 推进状态 --------------------------

  /// 待处理的强制事件（被捕 / 成瘾发作 / 出狱）
  final List<LifeEvent> forcedQueue = <LifeEvent>[];

  /// 待处理的普通事件
  final List<LifeEvent> eventQueue = <LifeEvent>[];

  /// 当前正在展示的事件
  LifeEvent? currentEvent;

  /// 当前事件是否是强制事件
  bool currentEventIsForced = false;

  /// 本年度被动变化是否已经结算
  bool passiveApplied = false;

  /// 等待玩家看完上一次选择的结果（看完才推进下一个事件）
  bool _awaitingOutcomeDismiss = false;

  /// 正在推进中（防止连点）
  bool isAdvancing = false;

  /// 最后一次推进的结果提示
  final List<String> lastYearNotes = <String>[];

  /// 上一次推进结束时是否死亡
  bool justDied = false;

  /// 最近一次选择的结算结果（事件弹窗关闭前展示）
  EventOutcome? lastOutcome;

  /// 存档是否降级为内存
  bool get isMemoryOnly => storage.memoryOnly;

  /// 存档路径说明
  String get storagePath => storage.storagePath;

  /// 是否有进行中的角色
  bool get hasCharacter => character != null;

  /// 当前阶段
  GamePhase get phase {
    if (isLoading) return GamePhase.loading;
    final Character? c = character;
    if (c == null) return GamePhase.setup;
    if (!c.isAlive) return GamePhase.finished;
    return GamePhase.running;
  }

  /// 事件引擎（未初始化时返回 null）
  EventEngine? get engine => _engine;

  /// 是否还有待处理的事件
  bool get hasPendingEvent =>
      currentEvent != null || eventQueue.isNotEmpty || pendingAiRequest != null;

  // ---------------------------------------------------------------------
  // 初始化
  // ---------------------------------------------------------------------

  /// 初始化：加载剧本数据 + 读取存档
  Future<void> init() async {
    isLoading = true;
    loadError = '';
    notifyListeners();

    await storage.init();
    final GameDataBundle bundle = await DataLoader.loadAll();
    data = bundle;
    if (bundle.errors.isNotEmpty) {
      loadError = bundle.errors.first;
    }
    final EventEngine engine = EventEngine(data: bundle);
    _engine = engine;
    _actionEngine = ActionEngine(data: bundle, engine: engine);

    // AI 配置：独立小文件，Key 只存在本机，绝不硬编码进代码
    aiOptions = await ai.store.load();

    // 恢复存档
    final SaveSnapshot snapshot = await storage.load();
    generation = snapshot.generation <= 0 ? 1 : snapshot.generation;
    for (final AchievementRecord r in snapshot.achievements) {
      if (r.name.isEmpty) continue;
      unlocked[r.name] = r;
    }
    inheritedAttributes = <AttributeKey, int>{};
    snapshot.inherited.forEach((String key, Object? value) {
      final AttributeKey? attr = AttributeKeyX.fromKey(key);
      if (attr != null && value is num) {
        inheritedAttributes[attr] = value.toInt();
      }
    });

    if (snapshot.character.isNotEmpty) {
      character = Character.fromJson(snapshot.character);
      final Character? c = character;
      if (c != null) {
        selectedEra = c.era;
        selectedCity = data.cityIndex[c.cityName];
        if (!c.isAlive) justDied = true;
      }
    } else {
      character = null;
    }

    isLoading = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // 开局：年代 / 城市 / 天赋
  // ---------------------------------------------------------------------

  /// 可选年代列表（按时间顺序）
  List<String> get eras => const <String>['80', '90', '00', '10', '20'];

  /// 年代的显示名
  String eraLabel(String era) {
    switch (era) {
      case '80':
        return '80年代';
      case '90':
        return '90年代';
      case '00':
        return '00年代';
      case '10':
        return '10年代';
      case '20':
        return '20年代';
      default:
        return '$era年代';
    }
  }

  /// 年代的描述文案
  String eraDesc(String era) {
    switch (era) {
      case '80':
        return '改革开放刚开始，票证还没退出生活，机会藏在体制的缝隙里。';
      case '90':
        return '下海潮、下岗潮同时到来，录像厅和股票认购证是这一代的记忆。';
      case '00':
        return '互联网萌芽，网吧、淘宝、非典，世界正在换一副面孔。';
      case '10':
        return '移动互联网爆发，房价、外卖、网约车，人人都在往前跑。';
      case '20':
        return '短视频与 AI 浪潮并行，机遇与裁员通知一起送到手里。';
      default:
        return '';
    }
  }

  /// 选择年代（切换后需要重新选择城市）
  void selectEra(String era) {
    if (!eras.contains(era)) return;
    selectedEra = era;
    selectedCity = null;
    notifyListeners();
  }

  /// 当前年代可选的城市
  List<CityData> get availableCities => data.citiesOfEra(selectedEra);

  /// 选择城市
  void selectCity(CityData city) {
    selectedCity = city;
    notifyListeners();
  }

  /// 抽取天赋候选（3 选 1）
  void drawTalents() {
    final EventEngine? e = _engine;
    if (e == null) return;
    final List<Talent> pool = List<Talent>.from(data.talents);
    if (pool.isEmpty) return;
    pool.shuffle(e.random);
    final int count = pool.length < kTalentPickCount ? pool.length : kTalentPickCount;
    talentCandidates = pool.sublist(0, count);
    notifyListeners();
  }

  /// 重抽天赋（次数有限）
  bool rerollTalents() {
    if (rerollUsed >= kMaxReroll) return false;
    rerollUsed += 1;
    drawTalents();
    return true;
  }

  /// 剩余重抽次数
  int get rerollLeft => (kMaxReroll - rerollUsed).clamp(0, kMaxReroll);

  /// 正式开局：应用天赋、初始化属性、写入继承
  void startNewGame(Talent talent) {
    final CityData? city = selectedCity ?? (availableCities.isNotEmpty ? availableCities.first : null);
    final EventEngine? e = _engine;
    if (e == null || city == null) return;

    final bool male = e.random.nextBool();
    final Character c = Character(
      name: e.randomName(selectedEra, male: male),
      gender: male ? '男' : '女',
      age: 0,
      era: selectedEra,
      cityName: city.cityName,
      wealthCapFactor: city.wealthCapFactor,
      cityStressModifier: city.stressEffect,
      talents: <String>[talent.name],
    );

    // 天赋属性立即生效
    c.applyDelta(talent.attrModify);

    // 前世继承（智力/体质/魅力/运气 的 8%）
    if (inheritedAttributes.isNotEmpty) {
      inheritedAttributes.forEach((AttributeKey key, int value) {
        c.inherited[key] = value;
        c.setAttr(key, c.attr(key) + value);
      });
    }

    // 财富初值：天赋可能给出负财富（贫困出身等），需要转为负债
    final int wealth = c.attr(AttributeKey.wealth);
    if (wealth < 0) {
      c.assets.debt += -wealth;
      c.setAttr(AttributeKey.wealth, 0);
      c.assets.cash = 0;
    } else {
      c.assets.cash = wealth;
    }

    // 寿命
    c.lifespan = e.randomLifespan(c);
    c.log('你出生在${eraLabel(selectedEra)}的${city.cityName}，'
        '这是一个${talent.name}的孩子。', kind: LogKind.system);
    if (inheritedAttributes.isNotEmpty) {
      final StringBuffer buffer = StringBuffer();
      inheritedAttributes.forEach((AttributeKey key, int value) {
        if (value == 0) return;
        buffer.write('${AttributeKeyX.shortLabel(key)}+$value ');
      });
      c.log('前世的记忆还留着一点：${buffer.toString().trim()}', kind: LogKind.system);
    }

    character = c;
    forcedQueue.clear();
    eventQueue.clear();
    currentEvent = null;
    lastYearNotes.clear();
    justDied = false;
    lastOutcome = null;
    passiveApplied = true;
    e.resetFired();

    // 开局即检查一次成就（呱呱坠地）
    _runAchievementCheck();
    _persist();
    notifyListeners();
  }

  /// 放弃当前存档，回到开局页
  Future<void> abandonLife() async {
    character = null;
    eventQueue.clear();
    forcedQueue.clear();
    currentEvent = null;
    pendingAiRequest = null;
    currentEventIsAi = false;
    aiGeneratedTitles.clear();
    justDied = false;
    await _persist();
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // 逐年推进
  // ---------------------------------------------------------------------

  /// 过一年：结算被动变化，之后由界面依次处理强制事件与普通事件
  void advanceYear() {
    final Character? c = character;
    final EventEngine? e = _engine;
    if (c == null || e == null || !c.isAlive) return;
    if (hasPendingEvent) return;
    if (isAdvancing) return;

    isAdvancing = true;
    lastYearNotes.clear();
    lastOutcome = null;
    _awaitingOutcomeDismiss = false;

    // 1. 生成年度计划
    final YearPlan plan = e.planYear(c);

    // 2. 应用被动变化
    final List<String> notes = e.applyPassive(c, plan);
    passiveApplied = true;
    lastYearNotes.addAll(notes);
    lastYearNotes.addAll(plan.passiveLogs);

    // 3. 队列：强制事件优先
    forcedQueue
      ..clear()
      ..addAll(plan.forcedEvents);
    eventQueue
      ..clear()
      ..addAll(plan.events);

    _runAchievementCheck();
    _persist();
    isAdvancing = false;

    // 4. 推进下一个事件（没有事件时就做年度收尾）
    _pumpNextEvent();
    notifyListeners();
  }

  /// 快进 N 年：连续推进，遇到需要玩家处理的事件就停下
  void fastForward(int years) {
    for (int i = 0; i < years; i++) {
      final Character? c = character;
      if (c == null || !c.isAlive) break;
      if (hasPendingEvent || _awaitingOutcomeDismiss) break;
      advanceYear();
      if (hasPendingEvent || _awaitingOutcomeDismiss || !c.isAlive) break;
    }
  }

  /// 取出下一个事件放入 currentEvent；没有事件时执行年度收尾
  void _pumpNextEvent() {
    final Character? c = character;
    if (c == null || !c.isAlive) {
      currentEvent = null;
      return;
    }
    // 玩家还没看完上一次选择的结果，先不推进
    if (_awaitingOutcomeDismiss) {
      currentEvent = null;
      return;
    }
    if (forcedQueue.isNotEmpty) {
      currentEvent = forcedQueue.removeAt(0);
      currentEventIsForced = true;
      return;
    }
    if (eventQueue.isNotEmpty) {
      final LifeEvent next = eventQueue.removeAt(0);
      currentEventIsAi = false;
      // AI 续写：命中条件时先挂起本地事件，弹「AI 正在续写剧情…」
      if (shouldUseAi(c)) {
        startAiRewrite(next);
        return;
      }
      currentEvent = next;
      currentEventIsForced = false;
      return;
    }
    currentEvent = null;
    _finalizeYear();
  }

  /// 年度收尾：健康 / 寿命 / 成就判定
  void _finalizeYear() {
    final Character? c = character;
    final EventEngine? e = _engine;
    if (c == null || e == null) return;
    if (!passiveApplied) return;
    passiveApplied = false;

    final YearSummary summary = e.finalizeYear(c);
    lastYearNotes.addAll(summary.messages);
    _runAchievementCheck();
    if (summary.died || !c.isAlive) {
      justDied = true;
      lastYearNotes.add('这一世结束了。');
    }
    _persist();
  }

  /// 结算当前事件的选择
  void chooseEventOption(int index) {
    final Character? c = character;
    final EventEngine? e = _engine;
    final LifeEvent? event = currentEvent;
    if (c == null || e == null || event == null) return;

    final EventOutcome outcome = e.applyChoice(c, event, index);
    lastOutcome = outcome;
    // 记录已发生的剧情标题（AI 提示词用它避免重复）
    _rememberStoryTitle(c, event.title);
    if (outcome.messages.isNotEmpty) {
      lastYearNotes.addAll(outcome.messages);
    }
    if (outcome.died) {
      justDied = true;
    }

    currentEvent = null;
    currentEventIsForced = false;

    _runAchievementCheck();
    _persist();

    // 如果这次选择直接死亡，跳过剩余事件
    if (outcome.died || !c.isAlive) {
      eventQueue.clear();
      forcedQueue.clear();
      lastYearNotes.add('你在这一年的经历中离开了人世。');
      notifyListeners();
      return;
    }

    // 等玩家看完结果弹窗再继续推进
    _awaitingOutcomeDismiss = true;
    notifyListeners();
  }

  /// 关闭事件结果弹窗：取出下一个事件或做年度收尾
  void dismissOutcome() {
    final Character? c = character;
    if (c == null) return;
    lastOutcome = null;
    _awaitingOutcomeDismiss = false;
    if (!c.isAlive) {
      justDied = true;
      notifyListeners();
      return;
    }
    _pumpNextEvent();
    notifyListeners();
  }

  /// 强制结束本局（调试 / 玩家主动）
  void killCharacter(String reason) {
    final Character? c = character;
    if (c == null) return;
    c.setAttr(AttributeKey.health, 0);
    c.status = LifeStatus.dead;
    c.deathAge = c.age;
    c.deathReason = reason;
    c.log(reason, kind: LogKind.bad);
    justDied = true;
    currentEvent = null;
    currentEventIsAi = false;
    pendingAiRequest = null;
    eventQueue.clear();
    forcedQueue.clear();
    _runAchievementCheck();
    _persist();
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // 主动行动（每岁 1 点行动力）
  // ---------------------------------------------------------------------

  /// 行动引擎（未初始化时为 null）
  ActionEngine? get actionEngine => _actionEngine;

  /// 当前剩余行动点
  int get actionPoints => character?.actionPoints ?? 0;

  /// 主动行动一览（界面两列网格用：可用状态 + 不可用原因）
  List<ActionCard> get actionCards {
    final Character? c = character;
    final ActionEngine? ae = _actionEngine;
    if (c == null || ae == null) return const <ActionCard>[];
    return ae.cards(c, busy: hasPendingEvent);
  }

  /// 执行一个主动行动，返回给界面展示的反馈文本
  String performAction(String id) {
    final Character? c = character;
    final ActionEngine? ae = _actionEngine;
    if (c == null || ae == null) return '当前没有进行中的人生';
    final ActionOutcome outcome = ae.perform(c, id);
    if (!outcome.success) {
      notifyListeners();
      return outcome.message;
    }
    _handleActionDeath(c);
    _runAchievementCheck();
    unawaited(_persist());
    notifyListeners();
    return outcome.message;
  }

  // ---------------------------------------------------------------------
  // 关系互动（每人每年 1 次）
  // ---------------------------------------------------------------------

  /// 某段关系当前可用的互动方式（仇人才能和解，恋人才能求婚）
  List<RelationInteract> interactsFor(Relation relation) {
    return ActionEngine.interactsFor(relation);
  }

  /// 互动的可用性：空串表示可以互动，否则返回原因
  String relationInteractReason(Relation relation, String kind) {
    final Character? c = character;
    final ActionEngine? ae = _actionEngine;
    if (c == null || ae == null) return '当前没有进行中的人生';
    return ae.interactReason(c, relation, kind);
  }

  /// 执行一次关系互动，返回给界面展示的反馈文本
  String interactRelation(Relation relation, String kind) {
    final Character? c = character;
    final ActionEngine? ae = _actionEngine;
    if (c == null || ae == null) return '当前没有进行中的人生';
    final ActionOutcome outcome = ae.interact(c, relation, kind);
    if (!outcome.success) {
      notifyListeners();
      return outcome.message;
    }
    // 求婚成功会顺带解锁「携手一生」
    _runAchievementCheck();
    _handleActionDeath(c);
    unawaited(_persist());
    notifyListeners();
    return outcome.message;
  }

  /// 行动 / 互动导致健康归零时收尾
  void _handleActionDeath(Character c) {
    if (c.attr(AttributeKey.health) > 0) return;
    c.status = LifeStatus.dead;
    c.deathAge = c.age;
    c.deathReason = '主动行动的消耗让身体彻底垮掉';
    c.log(c.deathReason, kind: LogKind.bad);
    justDied = true;
    currentEvent = null;
    eventQueue.clear();
    forcedQueue.clear();
  }

  // ---------------------------------------------------------------------
  // 人生评分
  // ---------------------------------------------------------------------

  /// 当前一世的人生评分（未开局时返回 0 分与最低称号）
  LifeScore get lifeScore {
    final Character? c = character;
    if (c == null) {
      return LifeScore(
        score: 0,
        title: ScoreService.titleOf(0),
        detail: const <ScoreItem>[],
      );
    }
    return ScoreService.evaluate(c, achievementCount: unlocked.length);
  }

  // ---------------------------------------------------------------------
  // AI 剧情
  // ---------------------------------------------------------------------

  /// AI 是否已经具备请求条件（已启用 + 地址 + 模型 + Key）
  bool get aiReady => aiOptions.ready;

  /// AI 状态文案
  String get aiStatusText => aiOptions.statusText;

  /// 本世 AI 剩余可用次数
  int get aiQuotaLeft {
    final Character? c = character;
    if (c == null) return 0;
    final int left = aiOptions.maxPerLife - c.aiUsed;
    return left < 0 ? 0 : left;
  }

  /// 取走一次性 AI 提示（提示只展示一次）
  String takeAiNotice() {
    final String notice = _aiNotice;
    _aiNotice = '';
    return notice;
  }

  /// 保存 AI 配置到本机独立小文件
  Future<void> saveAiOptions(AiOptions draft) async {
    draft.normalize();
    aiOptions = draft;
    await ai.store.save(draft);
    notifyListeners();
  }

  /// 测试连接（发一条极短请求验证 Key / 地址 / 模型）
  Future<AiTestResult> testAiConnection(AiOptions config) {
    return ai.test(config);
  }

  /// 是否该用 AI 续写这一年
  bool shouldUseAi(Character c) {
    if (!aiOptions.ready) return false;
    if (c.age < aiOptions.startAge) return false;
    if (c.inPrison) return false;
    if (c.aiUsed >= aiOptions.maxPerLife) return false;
    final EventEngine? e = _engine;
    final Random source = e?.random ?? uiRandom;
    return source.nextDouble() < aiOptions.chance;
  }

  /// 发起一次 AI 续写：本地事件先挂起，界面弹「AI 正在续写剧情…」
  void startAiRewrite(LifeEvent local) {
    final AiPendingRequest request = AiPendingRequest(
      localEvent: local,
      age: character?.age ?? 0,
    );
    pendingAiRequest = request;
    currentEvent = null;
    currentEventIsAi = false;
    notifyListeners();
    unawaited(_runAiRewrite(request));
  }

  /// 真正的请求过程（异步，不阻塞界面）
  Future<void> _runAiRewrite(AiPendingRequest request) async {
    final Character? c = character;
    if (c == null) {
      _finishAiRequest(request, null, '没有进行中的人生');
      return;
    }
    final AiStoryContext ctx = AiStoryContext(
      character: c,
      data: data,
      eraLabel: eraLabel(c.era),
      monthlySalary: _engine?.estimatedMonthlySalary(c) ?? 0,
      recentTitles: _recentStoryTitles(c),
    );
    AiGenerateResult result;
    try {
      result = await ai.generate(aiOptions, ctx);
    } catch (e) {
      result = AiGenerateResult(error: e.toString());
    }
    _finishAiRequest(request, result.event, result.error);
  }

  /// 请求结束：写入结果并唤醒界面（界面负责 settle）
  void _finishAiRequest(AiPendingRequest request, LifeEvent? event, String error) {
    if (!identical(request, pendingAiRequest)) return;
    if (request.cancelled) {
      request.markFinished();
      notifyListeners();
      return;
    }
    if (event == null) {
      request.failed = true;
      request.error = error.isEmpty ? '未知原因' : error;
      final Character? c = character;
      if (c != null) c.aiFails += 1;
      _aiNotice = 'AI 未成功（${request.error}），已改用本地剧情';
    } else {
      request.aiEvent = event;
    }
    request.markFinished();
    notifyListeners();
  }

  /// 「不等了，用本地剧情」：立刻放弃 AI，回退本地事件
  void cancelAiToLocal() {
    final AiPendingRequest? request = pendingAiRequest;
    if (request == null || request.finished) return;
    request.cancelled = true;
    _aiNotice = '已改用本地剧情';
    request.markFinished();
    notifyListeners();
  }

  /// 界面收尾：AI 事件替换本地事件；失败 / 放弃时回退本地事件
  void settleAiRequest() {
    final AiPendingRequest? request = pendingAiRequest;
    if (request == null) return;
    pendingAiRequest = null;
    final Character? c = character;
    final LifeEvent? aiEvent = request.cancelled ? null : request.aiEvent;
    if (aiEvent != null) {
      currentEvent = aiEvent;
      currentEventIsAi = true;
      if (c != null) {
        c.aiUsed += 1;
        _rememberStoryTitle(c, aiEvent.title);
        c.log('第 ${c.age} 年：AI 续写剧情「${aiEvent.title}」', kind: LogKind.system);
        aiGeneratedTitles.insert(0, aiEvent.title);
        if (aiGeneratedTitles.length > 30) {
          aiGeneratedTitles.removeRange(30, aiGeneratedTitles.length);
        }
      }
    } else {
      currentEvent = request.localEvent;
      currentEventIsAi = false;
    }
    currentEventIsForced = false;
    _runAchievementCheck();
    unawaited(_persist());
    notifyListeners();
  }

  /// 最近 14 条已发生过的剧情标题（AI 提示词用来避免重复）
  List<String> _recentStoryTitles(Character c) {
    final List<String> all = c.storyTitles;
    if (all.length <= 14) return List<String>.from(all);
    return all.sublist(all.length - 14);
  }

  /// 记录一条已发生的剧情标题（相邻去重 + 上限 80 条）
  void _rememberStoryTitle(Character c, String title) {
    final String text = title.trim();
    if (text.isEmpty) return;
    if (c.storyTitles.isNotEmpty && c.storyTitles.last == text) return;
    c.storyTitles.add(text);
    if (c.storyTitles.length > 80) {
      c.storyTitles.removeRange(0, c.storyTitles.length - 80);
    }
  }

  // ---------------------------------------------------------------------
  // 成就
  // ---------------------------------------------------------------------

  /// 已解锁成就数量
  int get unlockedCount => unlocked.length;

  /// 成就总数
  int get achievementTotal => data.achievements.length;

  /// 成就列表（含解锁状态），可按「只看已解锁 / 只看未解锁」筛选
  List<AchievementState> achievementStates({bool onlyUnlocked = false, bool onlyLocked = false}) {
    final List<AchievementState> out = <AchievementState>[];
    for (final Achievement a in data.achievements) {
      final AchievementRecord? r = unlocked[a.name];
      final bool isUnlocked = r != null;
      if (onlyUnlocked && !isUnlocked) continue;
      if (onlyLocked && isUnlocked) continue;
      out.add(
        AchievementState(
          achievement: a,
          unlocked: isUnlocked,
          unlockedAge: r?.age ?? -1,
          unlockedLife: r?.life ?? -1,
        ),
      );
    }
    return out;
  }

  /// 执行一次成就判定，返回新解锁列表
  List<String> _runAchievementCheck() {
    final Character? c = character;
    final EventEngine? e = _engine;
    if (c == null || e == null) return const <String>[];
    final Set<String> names = unlocked.keys.toSet();
    final List<String> fresh = e.checkAchievements(c, names, generation);
    if (fresh.isEmpty) return fresh;
    for (final String name in fresh) {
      unlocked[name] = AchievementRecord(name: name, age: c.age, life: generation);
    }
    lastUnlocked
      ..clear()
      ..addAll(fresh);
    storage.saveAchievements(unlocked.values.toList());
    // 「轮回新生」在新一世开始时解锁，这里避免提前触发
    return fresh;
  }

  /// 清空「最近解锁」提示
  void clearLastUnlocked() {
    if (lastUnlocked.isEmpty) return;
    lastUnlocked.clear();
    notifyListeners();
  }

  /// 全部技能的定义列表
  List<Skill> get allSkills => data.skills;

  /// 已习得技能（有序）
  List<Skill> get learnedSkills {
    final Character? c = character;
    if (c == null) return const <Skill>[];
    final Map<String, Skill> index = data.skillIndex;
    final List<Skill> out = <Skill>[];
    for (final String id in c.skills) {
      final Skill? s = index[id];
      if (s != null) out.add(s);
    }
    return out;
  }

  /// 未习得技能
  List<Skill> get unlearnedSkills {
    final Character? c = character;
    if (c == null) return data.skills;
    return data.skills.where((Skill s) => !c.skills.contains(s.skillId)).toList();
  }

  /// 按 skillId 查技能定义
  Skill? skillById(String id) => data.skillIndex[id];

  /// 当前事件命中的技能数（事件弹窗展示加成用）
  int hitSkillCount(LifeEvent event) {
    final Character? c = character;
    final EventEngine? e = _engine;
    if (c == null || e == null) return 0;
    final String text = event.allText;
    int hits = 0;
    for (final String id in c.skills) {
      final List<String>? words = EventEngine.skillKeywords[id];
      if (words == null) continue;
      for (final String w in words) {
        if (text.contains(w)) {
          hits++;
          break;
        }
      }
    }
    return hits;
  }

  /// 当前事件的成功率加成（0-0.45）
  double eventBonus(LifeEvent event) {
    final Character? c = character;
    final EventEngine? e = _engine;
    if (c == null || e == null) return 0;
    return e.successBonus(c, event);
  }

  // ---------------------------------------------------------------------
  // 轮回
  // ---------------------------------------------------------------------

  /// 是否可以进行转世
  bool get canRebirth {
    final Character? c = character;
    return c != null && !c.isAlive;
  }

  /// 本世的继承属性预览：智力/体质/魅力/运气 的 8%
  Map<AttributeKey, int> get inheritancePreview {
    final Character? c = character;
    if (c == null) return <AttributeKey, int>{};
    return <AttributeKey, int>{
      AttributeKey.intelligence: (c.attr(AttributeKey.intelligence) * 0.08).floor(),
      AttributeKey.constitution: (c.attr(AttributeKey.constitution) * 0.08).floor(),
      AttributeKey.charm: (c.attr(AttributeKey.charm) * 0.08).floor(),
      AttributeKey.luck: (c.attr(AttributeKey.luck) * 0.08).floor(),
    };
  }

  /// 转世：继承 8% 属性，保留成就，重新抽天赋
  Future<void> rebirth() async {
    final Character? c = character;
    if (c == null || c.isAlive) return;

    inheritedAttributes = inheritancePreview;
    // 叠加：上一世继承的属性会随着轮回累积
    generation += 1;

    final EventEngine? e = _engine;
    if (e != null) e.resetFired();

    // 解锁「轮回新生」
    unlocked['轮回新生'] = AchievementRecord(
      name: '轮回新生',
      age: c.age,
      life: generation,
    );

    character = null;
    eventQueue.clear();
    forcedQueue.clear();
    currentEvent = null;
    lastOutcome = null;
    lastYearNotes.clear();
    justDied = false;
    talentCandidates = <Talent>[];
    rerollUsed = 0;
    passiveApplied = false;
    _awaitingOutcomeDismiss = false;
    pendingAiRequest = null;
    currentEventIsAi = false;
    aiGeneratedTitles.clear();

    await _persist();
    notifyListeners();
  }

  /// 彻底删除存档（回到全新状态）
  Future<void> resetAll() async {
    character = null;
    unlocked.clear();
    inheritedAttributes = <AttributeKey, int>{};
    generation = 1;
    eventQueue.clear();
    forcedQueue.clear();
    currentEvent = null;
    justDied = false;
    lastOutcome = null;
    pendingAiRequest = null;
    currentEventIsAi = false;
    aiGeneratedTitles.clear();
    await storage.clear();
    await _persist();
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // 金手指控制台
  // ---------------------------------------------------------------------

  /// 金手指是否已解锁
  bool get godModeUnlocked => character?.godModeUnlocked ?? false;

  /// 校验密码并解锁金手指
  bool unlockGodMode(String password) {
    final Character? c = character;
    if (c == null) return false;
    if (password.trim() != kGodPassword) return false;
    if (c.godModeUnlocked) return true;
    c.godModeUnlocked = true;
    c.log('金手指已解锁，命运从此可以修改。', kind: LogKind.system);
    lastUnlocked
      ..clear()
      ..add('开挂人生');
    _runAchievementCheck();
    _persist();
    notifyListeners();
    return true;
  }

  /// 直接修改某一项属性（金手指）
  void godSetAttr(AttributeKey key, int value) {
    final Character? c = character;
    if (c == null) return;
    final int clamped = value.clamp(0, 9999);
    c.setAttr(key, clamped);
    if (key == AttributeKey.wealth) {
      c.assets.cash = clamped;
    }
    c.godModeUsed = true;
    _runAchievementCheck();
    _persist();
    notifyListeners();
  }

  /// 一键 +100000 财富
  void godAddWealth(int amount) {
    final Character? c = character;
    if (c == null) return;
    final int next = c.attr(AttributeKey.wealth) + amount;
    c.setAttr(AttributeKey.wealth, next);
    c.assets.cash = next;
    c.godModeUsed = true;
    c.log('金手指：财富 ${amount > 0 ? '+' : ''}$amount', kind: LogKind.system);
    _runAchievementCheck();
    _persist();
    notifyListeners();
  }

  /// 一键回满健康
  void godFullHealth() {
    final Character? c = character;
    if (c == null) return;
    c.setAttr(AttributeKey.health, 100);
    c.godModeUsed = true;
    c.log('金手指：健康值回满', kind: LogKind.system);
    _persist();
    notifyListeners();
  }

  /// 一键清空成瘾与罪恶
  void godClearAddictionAndSin() {
    final Character? c = character;
    if (c == null) return;
    c.addictions.updateAll((String key, int value) => 0);
    c.setAttr(AttributeKey.addiction, 0);
    c.setAttr(AttributeKey.sin, 0);
    c.godModeUsed = true;
    c.log('金手指：成瘾与罪恶值全部清零', kind: LogKind.system);
    _runAchievementCheck();
    _persist();
    notifyListeners();
  }

  /// 一键习得全部技能
  void godLearnAllSkills() {
    final Character? c = character;
    if (c == null) return;
    for (final Skill s in data.skills) {
      if (!c.skills.contains(s.skillId)) c.skills.add(s.skillId);
    }
    c.godModeUsed = true;
    c.log('金手指：习得全部技能', kind: LogKind.system);
    _runAchievementCheck();
    _persist();
    notifyListeners();
  }

  /// 一键解锁全部成就
  void godUnlockAllAchievements() {
    final Character? c = character;
    for (final Achievement a in data.achievements) {
      unlocked[a.name] = AchievementRecord(
        name: a.name,
        age: c?.age ?? -1,
        life: generation,
      );
    }
    if (c != null) {
      c.godModeUsed = true;
      c.log('金手指：解锁全部成就', kind: LogKind.system);
    }
    storage.saveAchievements(unlocked.values.toList());
    _persist();
    notifyListeners();
  }

  /// 一键清除全部负债
  void godClearDebt() {
    final Character? c = character;
    if (c == null) return;
    c.assets.debt = 0;
    c.godModeUsed = true;
    c.log('金手指：负债清零', kind: LogKind.system);
    _runAchievementCheck();
    _persist();
    notifyListeners();
  }

  /// 一键回满快乐
  void godFullHappiness() {
    final Character? c = character;
    if (c == null) return;
    c.setAttr(AttributeKey.happiness, 100);
    c.setAttr(AttributeKey.stress, 0);
    c.godModeUsed = true;
    c.log('金手指：快乐回满、压力清零', kind: LogKind.system);
    _persist();
    notifyListeners();
  }

  /// 直接修改年龄（金手指）
  void godSetAge(int age) {
    final Character? c = character;
    if (c == null) return;
    c.age = age.clamp(0, 200);
    c.godModeUsed = true;
    c.log('金手指：年龄设为 ${c.age} 岁', kind: LogKind.system);
    _persist();
    notifyListeners();
  }

  /// 直接修改寿命上限（金手指）
  void godSetLifespan(int lifespan) {
    final Character? c = character;
    if (c == null) return;
    c.lifespan = lifespan.clamp(1, 200);
    c.godModeUsed = true;
    c.log('金手指：寿命上限设为 ${c.lifespan} 岁', kind: LogKind.system);
    _persist();
    notifyListeners();
  }

  /// 一键复活（死亡后回到 100 健康继续玩）
  void godRevive() {
    final Character? c = character;
    if (c == null) return;
    c.setAttr(AttributeKey.health, 100);
    c.status = LifeStatus.alive;
    c.jailYearsLeft = 0;
    c.deathReason = '';
    c.deathAge = -1;
    c.godModeUsed = true;
    justDied = false;
    c.log('金手指：你被强行拉回了人间。', kind: LogKind.system);
    _persist();
    notifyListeners();
  }

  /// 立即触发一条随机事件（金手指 / 调试）
  void godTriggerEvent() {
    final Character? c = character;
    final EventEngine? e = _engine;
    if (c == null || e == null) return;
    final List<LifeEvent> picked = e.pickEvents(c, maxCount: 1);
    if (picked.isEmpty) {
      lastYearNotes.add('当前年龄段没有可用事件了。');
      notifyListeners();
      return;
    }
    eventQueue.insert(0, picked.first);
    _pumpNextEvent();
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // 存档
  // ---------------------------------------------------------------------

  /// 当前存档快照
  SaveSnapshot _currentSnapshot() {
    final Character? c = character;
    final Map<String, dynamic> inheritJson = <String, dynamic>{};
    inheritedAttributes.forEach((AttributeKey key, int value) {
      inheritJson[AttributeKeyX.toKey(key)] = value;
    });
    return SaveSnapshot(
      character: c?.toJson() ?? const <String, dynamic>{},
      achievements: unlocked.values.toList(),
      generation: generation,
      inherited: inheritJson,
    );
  }

  /// 写入存档
  Future<void> _persist() async {
    await storage.save(_currentSnapshot());
  }

  /// 手动保存（界面「保存」按钮）
  Future<void> saveNow() async {
    await _persist();
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // 存档槽位（3 个）与文本导出 / 导入
  // ---------------------------------------------------------------------

  /// 读取全部槽位摘要（轮回页展示用）
  Future<List<SaveSlotInfo>> slotInfos() async {
    final List<SaveSlotInfo> out = <SaveSlotInfo>[];
    for (int i = 1; i <= saveSlotCount; i++) {
      out.add(await storage.slotInfo(i));
    }
    return out;
  }

  /// 槽位文件路径说明（界面展示用）
  String slotPathOf(int index) {
    return storage.extraFilePath(StorageService.slotFileName(index));
  }

  /// 保存到指定槽位：成功返回空串，失败返回原因
  Future<String> saveToSlot(int index) async {
    if (index < 1 || index > saveSlotCount) return '槽位不存在';
    if (character == null) return '当前没有人生可以保存';
    final Map<String, dynamic> pack = <String, dynamic>{
      'version': 1,
      'savedAt': DateTime.now().millisecondsSinceEpoch,
      'snapshot': _currentSnapshot().toJson(),
    };
    final bool ok = await storage.writeSlot(index, pack);
    notifyListeners();
    if (!ok) return '槽位 $index 已存到内存（磁盘不可写）';
    return '';
  }

  /// 从槽位读取并覆盖当前进度：成功返回空串，失败返回原因
  Future<String> loadFromSlot(int index) async {
    if (index < 1 || index > saveSlotCount) return '槽位不存在';
    final Map<String, dynamic>? pack = await storage.readSlot(index);
    if (pack == null) return '槽位 $index 是空的';
    final Object? rawSnapshot = pack['snapshot'];
    if (rawSnapshot is! Map) return '槽位数据损坏';
    final String error = _applySnapshot(Map<String, dynamic>.from(rawSnapshot));
    if (error.isNotEmpty) return error;
    await _persist();
    notifyListeners();
    return '';
  }

  /// 删除槽位：成功返回空串
  Future<String> deleteSlot(int index) async {
    if (index < 1 || index > saveSlotCount) return '槽位不存在';
    await storage.deleteSlotFile(index);
    notifyListeners();
    return '';
  }

  /// 导出存档文本（只有进度与成就，不含 API Key）
  String exportSaveText() {
    final Map<String, dynamic> pack = <String, dynamic>{
      'version': 1,
      'exportedAt': DateTime.now().millisecondsSinceEpoch,
      'snapshot': _currentSnapshot().toJson(),
    };
    return const JsonEncoder.withIndent('  ').convert(pack);
  }

  /// 导入存档文本（覆盖当前进度）：成功返回空串，失败返回原因，绝不抛异常
  Future<String> importSaveText(String text) async {
    final String raw = text.trim();
    if (raw.length < 20) return '请先粘贴完整的存档内容';
    Object? decoded;
    try {
      decoded = json.decode(raw);
    } catch (_) {
      return '解析失败：不是合法的 JSON 文本';
    }
    if (decoded is! Map) return '解析失败：存档顶层不是对象';
    final Map<String, dynamic> pack = Map<String, dynamic>.from(decoded);
    final Object? rawSnapshot = pack['snapshot'] ?? pack['state'];
    Map<String, dynamic> snapshotJson = pack;
    if (rawSnapshot is Map) {
      snapshotJson = Map<String, dynamic>.from(rawSnapshot);
    }
    final String error = _applySnapshot(snapshotJson);
    if (error.isNotEmpty) return error;
    await _persist();
    notifyListeners();
    return '';
  }

  /// 把一份快照应用到当前状态（槽位读取与文本导入共用）
  String _applySnapshot(Map<String, dynamic> json) {
    final SaveSnapshot snapshot = SaveSnapshot.fromJson(json);
    if (snapshot.character.isEmpty) return '不是有效的存档内容';

    final Character loaded = Character.fromJson(snapshot.character);
    character = loaded;
    generation = snapshot.generation <= 0 ? 1 : snapshot.generation;
    inheritedAttributes = <AttributeKey, int>{};
    snapshot.inherited.forEach((String key, Object? value) {
      final AttributeKey? attr = AttributeKeyX.fromKey(key);
      if (attr != null && value is num) {
        inheritedAttributes[attr] = value.toInt();
      }
    });

    // 清掉与旧人生绑定的临时状态
    eventQueue.clear();
    forcedQueue.clear();
    currentEvent = null;
    currentEventIsAi = false;
    pendingAiRequest = null;
    lastOutcome = null;
    lastYearNotes.clear();
    passiveApplied = false;
    isAdvancing = false;
    _awaitingOutcomeDismiss = false;
    justDied = !loaded.isAlive;

    selectedEra = loaded.era;
    selectedCity = data.cityIndex[loaded.cityName];
    return '';
  }

  /// 日志（倒序：最新在最上面），limit 为最多返回条数
  List<LifeLogEntry> recentLogs({int limit = 120}) {
    final Character? c = character;
    if (c == null) return const <LifeLogEntry>[];
    final List<LifeLogEntry> all = c.logs;
    if (all.length <= limit) return all.reversed.toList();
    return all.sublist(all.length - limit).reversed.toList();
  }

  /// 存活中的宠物
  List<Pet> get pets => character?.activePets ?? const <Pet>[];

  /// 全部宠物（含离世）
  List<Pet> get allPets => character?.pets ?? const <Pet>[];

  /// 存活中的关系（按类型排序）
  List<Relation> get relations {
    final Character? c = character;
    if (c == null) return const <Relation>[];
    final List<Relation> list = c.activeRelations;
    list.sort((Relation a, Relation b) {
      final int w = RelationTypeX.sortWeight(a.type) - RelationTypeX.sortWeight(b.type);
      if (w != 0) return w;
      return b.favor - a.favor;
    });
    return list;
  }

  /// 随机源（界面需要随机时使用，避免各页面自己 new Random）
  final Random uiRandom = Random();
}
