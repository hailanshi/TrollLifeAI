// 金手指控制台：输入密码 208526 解锁后，可以篡改全部属性与进度。
//
// 解锁时会自动解锁成就「开挂人生」。
// 所有改动都会写入日志与存档，方便回看。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/character.dart';
import '../providers/game_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

/// 金手指控制台页面
class GodConsolePage extends StatefulWidget {
  const GodConsolePage({super.key});

  /// 以路由方式打开
  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const GodConsolePage(),
      ),
    );
  }

  @override
  State<GodConsolePage> createState() => _GodConsolePageState();
}

class _GodConsolePageState extends State<GodConsolePage> {
  /// 密码输入控制器
  final TextEditingController _passwordCtrl = TextEditingController();

  /// 最近一次密码校验结果
  String _passwordError = '';

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GameProvider game = context.watch<GameProvider>();
    final Character? c = game.character;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('金手指控制台'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: c == null
          ? const Center(
              child: Text(
                '还没有进行中的角色',
                style: TextStyle(color: AppColors.textDim),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: <Widget>[
                if (!c.godModeUnlocked)
                  _buildPasswordGate(game)
                else ...<Widget>[
                  _buildConsoleHeader(game, c),
                  _buildAttributeEditor(game, c),
                  _buildQuickActions(game, c),
                  _buildDangerZone(game),
                ],
              ],
            ),
    );
  }

  /// 密码关卡
  Widget _buildPasswordGate(GameProvider game) {
    return SectionCard(
      title: '需要密码',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '这里是调试用的金手指控制台。输入密码后可以修改全部 11 项属性、'
            '一键增加财富、回满健康、清空成瘾与罪恶、习得全部技能、解锁全部成就。',
            style: TextStyle(
              color: AppColors.textDim,
              fontSize: 12.5,
              height: 1.65,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordCtrl,
            keyboardType: TextInputType.number,
            obscureText: true,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(12),
            ],
            decoration: InputDecoration(
              labelText: '密码',
              hintText: '请输入 6 位数字密码',
              errorText: _passwordError.isEmpty ? null : _passwordError,
            ),
            onSubmitted: (String value) => _tryUnlock(game, value),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _tryUnlock(game, _passwordCtrl.text),
                  child: const Text('解锁控制台'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 校验密码
  void _tryUnlock(GameProvider game, String value) {
    final bool ok = game.unlockGodMode(value);
    if (!ok) {
      setState(() => _passwordError = '密码错误');
      return;
    }
    setState(() => _passwordError = '');
    _passwordCtrl.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('金手指已解锁：成就「开挂人生」已解锁')),
    );
  }

  /// 控制台头部
  Widget _buildConsoleHeader(GameProvider game, Character c) {
    return SectionCard(
      title: '控制台',
      trailing: const TagChip(text: '已解锁', color: AppColors.epic),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InfoRow(label: '角色', value: Text('${c.name} · ${c.age} 岁')),
          InfoRow(
            label: '年代',
            value: Text('${game.eraLabel(c.era)} · ${c.cityName}'),
          ),
          InfoRow(label: '寿命上限', value: Text('${c.lifespan} 岁')),
          InfoRow(
            label: '状态',
            value: Text(c.isAlive ? '存活' : '已死亡'),
          ),
          const SizedBox(height: 8),
          const Text(
            '所有修改立即生效并写入存档，请在确认后使用。',
            style: TextStyle(color: AppColors.textDim, fontSize: 12),
          ),
        ],
      ),
    );
  }

  /// 11 项属性编辑器
  Widget _buildAttributeEditor(GameProvider game, Character c) {
    return SectionCard(
      title: '属性编辑（全部 11 项）',
      child: Column(
        children: AttributeKeyX.all.map((AttributeKey key) {
          final int value = c.attr(key);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    SizedBox(
                      width: 62,
                      child: Text(
                        AttributeKeyX.toKey(key),
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        value: value.clamp(0, 500).toDouble(),
                        max: key == AttributeKey.wealth ? 5000000 : 500,
                        divisions: key == AttributeKey.wealth ? 50 : 100,
                        label: key == AttributeKey.wealth
                            ? formatMoney(value)
                            : '$value',
                        onChanged: (double v) {
                          game.godSetAttr(key, v.round());
                        },
                      ),
                    ),
                    SizedBox(
                      width: 74,
                      child: Text(
                        key == AttributeKey.wealth
                            ? formatMoney(value)
                            : '$value',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: AppTheme.valueColor(value),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: <Widget>[
                    const SizedBox(width: 62),
                    _stepButton(
                      label: '-10',
                      onTap: () => game.godSetAttr(key, value - 10),
                    ),
                    const SizedBox(width: 6),
                    _stepButton(
                      label: '-1',
                      onTap: () => game.godSetAttr(key, value - 1),
                    ),
                    const SizedBox(width: 6),
                    _stepButton(
                      label: '+1',
                      onTap: () => game.godSetAttr(key, value + 1),
                    ),
                    const SizedBox(width: 6),
                    _stepButton(
                      label: '+10',
                      onTap: () => game.godSetAttr(key, value + 10),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => _showInputDialog(game, key, value),
                      child: const Text('精确输入'),
                    ),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  /// 步进按钮
  Widget _stepButton({required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.divider),
        ),
        child: Text(
          label,
          style: const TextStyle(color: AppColors.text, fontSize: 12),
        ),
      ),
    );
  }

  /// 精确输入弹窗
  void _showInputDialog(GameProvider game, AttributeKey key, int current) {
    final TextEditingController controller =
        TextEditingController(text: '$current');
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('修改 ${AttributeKeyX.toKey(key)}'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(signed: true),
          decoration: const InputDecoration(
            labelText: '新数值',
            hintText: '请输入整数',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final int? v = int.tryParse(controller.text.trim());
              Navigator.of(dialogContext).pop();
              if (v != null) game.godSetAttr(key, v);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 一键功能
  Widget _buildQuickActions(GameProvider game, Character c) {
    return SectionCard(
      title: '一键功能',
      child: Column(
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _actionButton('财富 +100000', () => game.godAddWealth(100000)),
              _actionButton('财富 +1000000', () => game.godAddWealth(1000000)),
              _actionButton('财富归零', () => game.godSetAttr(AttributeKey.wealth, 0)),
              _actionButton('回满健康', () => game.godFullHealth()),
              _actionButton('快乐满 / 压力清零', () => game.godFullHappiness()),
              _actionButton('清空成瘾与罪恶', () => game.godClearAddictionAndSin()),
              _actionButton('负债清零', () => game.godClearDebt()),
              _actionButton('习得全部技能', () => game.godLearnAllSkills()),
              _actionButton('解锁全部成就', () => game.godUnlockAllAchievements()),
              _actionButton('随机触发事件', () => game.godTriggerEvent()),
              _actionButton('年龄 +10', () => game.godSetAge(c.age + 10)),
              _actionButton('寿命 +20', () => game.godSetLifespan(c.lifespan + 20)),
              _actionButton('原地复活', () => game.godRevive()),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            '提示：「习得全部技能」会直接把 29 个技能全部加入，'
            '之后所有事件都能吃到上限 +35% 的成功率加成。',
            style: TextStyle(
              color: AppColors.textDim,
              fontSize: 12,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  /// 单个一键功能按钮
  Widget _actionButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.primary.withAlpha(110)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: AppColors.primaryLight,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  /// 危险操作区
  Widget _buildDangerZone(GameProvider game) {
    return SectionCard(
      title: '危险操作',
      dense: true,
      child: Row(
        children: <Widget>[
          Expanded(
            child: OutlinedButton(
              onPressed: () => game.killCharacter('金手指改写了这一世的结局'),
              child: const Text('结束这一世'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton(
              onPressed: () => game.godFullHealth(),
              child: const Text('保命一次'),
            ),
          ),
        ],
      ),
    );
  }
}
