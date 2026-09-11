// AI 剧情设置页：开关 / 接口地址 / 模型 / Key / 频率 / 每世上限 / 超时 / JSON 模式 / 起始年龄。
//
// 配置会写入本机独立小文件（ai_config.json），Key 绝不硬编码进代码，也不随存档导出。
// 页面里提供「测试连接」按钮，以及本世的用量与 AI 原创剧情列表。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/game_provider.dart';
import '../services/ai_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

/// AI 剧情设置页
class AiPage extends StatefulWidget {
  const AiPage({super.key});

  /// 以路由方式打开
  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (BuildContext context) => const AiPage()),
    );
  }

  @override
  State<AiPage> createState() => _AiPageState();
}

class _AiPageState extends State<AiPage> {
  /// 接口地址
  final TextEditingController _urlCtrl = TextEditingController();

  /// 模型名
  final TextEditingController _modelCtrl = TextEditingController();

  /// API Key
  final TextEditingController _keyCtrl = TextEditingController();

  /// 每世请求上限
  final TextEditingController _maxCtrl = TextEditingController();

  /// 超时毫秒
  final TextEditingController _timeoutCtrl = TextEditingController();

  /// 起始年龄
  final TextEditingController _startAgeCtrl = TextEditingController();

  /// 可选触发频率
  static const List<double> _chanceOptions = <double>[0.0, 0.15, 0.35, 0.6, 1.0];

  /// 界面编辑中的配置副本
  AiOptions _draft = AiOptions();

  /// 是否已经从 Provider 取过初始值
  bool _initialized = false;

  /// 是否正在测试连接
  bool _testing = false;

  /// 测试结果文本
  String _testMessage = '';

  /// 测试是否成功
  bool _testOk = false;

  /// 是否隐藏 Key
  bool _obscureKey = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    final GameProvider game = context.read<GameProvider>();
    _draft = game.aiOptions.clone();
    _urlCtrl.text = _draft.url;
    _modelCtrl.text = _draft.model;
    _keyCtrl.text = _draft.apiKey;
    _maxCtrl.text = '${_draft.maxPerLife}';
    _timeoutCtrl.text = '${_draft.timeoutMs}';
    _startAgeCtrl.text = '${_draft.startAge}';
    _initialized = true;
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _modelCtrl.dispose();
    _keyCtrl.dispose();
    _maxCtrl.dispose();
    _timeoutCtrl.dispose();
    _startAgeCtrl.dispose();
    super.dispose();
  }

  /// 把输入框内容同步回配置对象
  AiOptions _collect() {
    final AiOptions draft = _draft.clone();
    draft.url = _urlCtrl.text.trim();
    draft.model = _modelCtrl.text.trim();
    draft.apiKey = _keyCtrl.text.trim();
    draft.maxPerLife = int.tryParse(_maxCtrl.text.trim()) ?? draft.maxPerLife;
    draft.timeoutMs = int.tryParse(_timeoutCtrl.text.trim()) ?? draft.timeoutMs;
    draft.startAge = int.tryParse(_startAgeCtrl.text.trim()) ?? draft.startAge;
    draft.normalize();
    return draft;
  }

  /// 保存配置到本机
  Future<void> _save() async {
    final GameProvider game = context.read<GameProvider>();
    final AiOptions draft = _collect();
    await game.saveAiOptions(draft);
    if (!mounted) return;
    setState(() {
      _draft = draft;
      _urlCtrl.text = draft.url;
      _modelCtrl.text = draft.model;
      _maxCtrl.text = '${draft.maxPerLife}';
      _timeoutCtrl.text = '${draft.timeoutMs}';
      _startAgeCtrl.text = '${draft.startAge}';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('AI 配置已保存到本机：${game.ai.store.path}')),
    );
  }

  /// 测试连接
  Future<void> _test() async {
    final GameProvider game = context.read<GameProvider>();
    setState(() {
      _testing = true;
      _testMessage = '';
    });
    final AiOptions draft = _collect();
    final AiTestResult result = await game.testAiConnection(draft);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testOk = result.ok;
      _testMessage = result.message;
    });
  }

  /// 清空 Key
  Future<void> _clearKey() async {
    final GameProvider game = context.read<GameProvider>();
    final AiOptions draft = _collect();
    draft.apiKey = '';
    draft.enabled = false;
    _keyCtrl.clear();
    await game.saveAiOptions(draft);
    if (!mounted) return;
    setState(() => _draft = draft);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已清空 API Key 并关闭 AI 剧情')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final GameProvider game = context.watch<GameProvider>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('AI 剧情设置'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: <Widget>[
          _buildIntro(game),
          _buildSwitchSection(),
          _buildApiSection(game),
          _buildLimitSection(),
          _buildUsageSection(game),
          _buildHistorySection(game),
          const SizedBox(height: 6),
          ElevatedButton(
            onPressed: _save,
            child: const Text('保存配置'),
          ),
        ],
      ),
    );
  }

  /// 顶部说明
  Widget _buildIntro(GameProvider game) {
    return SectionCard(
      title: 'AI 剧情引擎',
      trailing: TagChip(
        text: game.aiStatusText,
        color: game.aiReady ? AppColors.primaryLight : AppColors.textDim,
      ),
      child: const Text(
        '开启后，每年按概率让大模型为你原创一条贴合当前年龄 / 年代 / 城市 / 职业 / 属性 / 技能的剧情事件。\n'
        '生成结果会经过本地严格校验（结构、11 项属性齐全、数值范围、标题与剧情长度），'
        '不合格、超时或请求失败都会自动回退内置剧情池，不会卡住游戏。\n'
        '接口采用 OpenAI 兼容格式（/chat/completions），可填 DeepSeek、OpenAI 或任意兼容网关。\n'
        'API Key 只保存在本机配置文件里，不会写进代码，也不会随存档导出。',
        style: TextStyle(
          color: AppColors.textDim,
          fontSize: 12.5,
          height: 1.8,
        ),
      ),
    );
  }

  /// 开关与触发频率
  Widget _buildSwitchSection() {
    return SectionCard(
      title: '开关与频率',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _draft.enabled,
            onChanged: (bool value) => setState(() => _draft.enabled = value),
            title: const Text(
              '开启 AI 剧情续写',
              style: TextStyle(color: AppColors.text, fontSize: 14),
            ),
            subtitle: const Text(
              '关闭时完全使用内置剧本',
              style: TextStyle(color: AppColors.textDim, fontSize: 11.5),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _draft.jsonMode,
            onChanged: (bool value) => setState(() => _draft.jsonMode = value),
            title: const Text(
              'JSON 模式（推荐）',
              style: TextStyle(color: AppColors.text, fontSize: 14),
            ),
            subtitle: const Text(
              '请求里带上 response_format: json_object',
              style: TextStyle(color: AppColors.textDim, fontSize: 11.5),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '触发频率：每年有 ${(_draft.chance * 100).round()}% 的概率请求 AI',
            style: const TextStyle(color: AppColors.textDim, fontSize: 12.5),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _chanceOptions.map((double value) {
              final bool on = (_draft.chance - value).abs() < 0.001;
              return ChoiceChip(
                label: Text('${(value * 100).round()}%'),
                selected: on,
                onSelected: (bool selected) {
                  setState(() => _draft.chance = value);
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// 接口配置
  Widget _buildApiSection(GameProvider game) {
    return SectionCard(
      title: '接口配置',
      trailing: TagChip(
        text: _draft.apiKey.trim().isEmpty ? '未填 Key' : '已填 Key',
        color: _draft.apiKey.trim().isEmpty
            ? AppColors.warning
            : AppColors.primaryLight,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: _urlCtrl,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: '接口地址',
              hintText: 'https://api.deepseek.com/v1/chat/completions',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _modelCtrl,
            decoration: const InputDecoration(
              labelText: '模型',
              hintText: 'deepseek-chat',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _keyCtrl,
            obscureText: _obscureKey,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'API Key',
              hintText: 'sk-...',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureKey ? Icons.visibility_off : Icons.visibility,
                  size: 18,
                ),
                onPressed: () => setState(() => _obscureKey = !_obscureKey),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: _testing ? null : _test,
                  child: Text(_testing ? '正在测试…' : '测试连接'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: _clearKey,
                  child: const Text('清空 Key'),
                ),
              ),
            ],
          ),
          if (_testing) ...<Widget>[
            const SizedBox(height: 10),
            const LinearProgressIndicator(minHeight: 2),
          ],
          if (_testMessage.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (_testOk ? AppColors.primary : AppColors.danger)
                    .withAlpha(26),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: (_testOk ? AppColors.primary : AppColors.danger)
                      .withAlpha(90),
                ),
              ),
              child: Text(
                _testMessage,
                style: TextStyle(
                  color: _testOk ? AppColors.primaryLight : AppColors.danger,
                  fontSize: 12.5,
                  height: 1.6,
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            '配置文件：${game.ai.store.path}',
            style: const TextStyle(
              color: AppColors.textDim,
              fontSize: 11.5,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  /// 触发参数
  Widget _buildLimitSection() {
    return SectionCard(
      title: '触发参数',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: _maxCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(3),
            ],
            decoration: const InputDecoration(
              labelText: '每世最多请求次数',
              hintText: '30',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _timeoutCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            decoration: const InputDecoration(
              labelText: '单次超时（毫秒，3000-120000）',
              hintText: '45000',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _startAgeCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(2),
            ],
            decoration: const InputDecoration(
              labelText: '从这个年龄开始用 AI（童年留白）',
              hintText: '6',
            ),
          ),
        ],
      ),
    );
  }

  /// 本世用量
  Widget _buildUsageSection(GameProvider game) {
    final int used = game.character?.aiUsed ?? 0;
    final int fails = game.character?.aiFails ?? 0;
    return SectionCard(
      title: '本世用量',
      trailing: TagChip(
        text: '剩余 ${game.aiQuotaLeft} 次',
        color: game.aiQuotaLeft > 0 ? AppColors.primaryLight : AppColors.warning,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InfoRow(label: '成功', value: Text('$used 次')),
          InfoRow(label: '失败', value: Text('$fails 次')),
          InfoRow(
            label: '上限',
            value: Text('${_draft.maxPerLife} 次 / 每世'),
          ),
          const SizedBox(height: 6),
          const Text(
            '失败、超时、结构不合格都不会计入成功次数，界面会提示并自动改用本地剧情。',
            style: TextStyle(
              color: AppColors.textDim,
              fontSize: 11.5,
              height: 1.7,
            ),
          ),
        ],
      ),
    );
  }

  /// AI 原创剧情列表
  Widget _buildHistorySection(GameProvider game) {
    final List<String> titles = game.aiGeneratedTitles;
    return SectionCard(
      title: '本世 AI 原创剧情',
      trailing: TagChip(
        text: '共 ${titles.length} 条',
        color: AppColors.textDim,
      ),
      child: titles.isEmpty
          ? const EmptyHint(text: '还没有 AI 原创剧情')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: titles.map((String title) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Icon(
                        Icons.auto_awesome,
                        size: 13,
                        color: AppColors.epic,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: AppColors.text,
                            fontSize: 12.5,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}
