// 事件弹窗：剧情 + 多选项，选完自动结算并关闭。
//
// 由 EventGate 监听 GameProvider.currentEvent 自动弹出；
// 页面也可以直接调用 showEventDialog 手动打开（例如金手指触发事件）。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/character.dart';
import '../models/life_event.dart';
import '../providers/game_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/score_panel.dart';

/// 事件弹窗的宿主：常驻在主页面上，负责「有事件就弹窗」
class EventGate extends StatefulWidget {
  const EventGate({super.key});

  @override
  State<EventGate> createState() => _EventGateState();
}

class _EventGateState extends State<EventGate> {
  GameProvider? _game;

  /// 弹窗是否已经在屏幕上
  bool _dialogOpen = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final GameProvider game = context.read<GameProvider>();
    if (identical(_game, game)) return;
    _game?.removeListener(_onChanged);
    _game = game..addListener(_onChanged);
  }

  @override
  void dispose() {
    _game?.removeListener(_onChanged);
    super.dispose();
  }

  /// 状态变化：有待处理事件就弹窗
  void _onChanged() {
    if (!mounted || _dialogOpen) return;
    final GameProvider? game = _game;
    if (game == null) return;
    if (game.currentEvent == null) return;
    _open();
  }

  /// 打开事件弹窗（延迟一帧，避免在 build / notify 过程中 push）
  void _open() {
    _dialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _dialogOpen = false;
        return;
      }
      showEventDialog(context).whenComplete(() {
        _dialogOpen = false;
        // 关闭后如果又产生了新事件（例如同一年还有下一条），继续弹
        final GameProvider? game = _game;
        if (mounted && game != null && game.currentEvent != null) {
          _open();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// 手动 / 自动打开事件弹窗
Future<void> showEventDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    useSafeArea: true,
    builder: (BuildContext context) => const EventDialog(),
  );
}

/// 事件弹窗本体
class EventDialog extends StatefulWidget {
  const EventDialog({super.key});

  @override
  State<EventDialog> createState() => _EventDialogState();
}

class _EventDialogState extends State<EventDialog> {
  /// 已经选择的选项下标（-1 表示还没选）
  int _picked = -1;

  /// 结算结果
  EventOutcome? _outcome;

  /// 本次结算新解锁的成就
  List<String> _unlocked = const <String>[];

  /// 是否已经关闭（防止重复 pop）
  bool _closing = false;

  @override
  Widget build(BuildContext context) {
    final GameProvider game = context.watch<GameProvider>();
    final LifeEvent? event = game.currentEvent;

    // 事件已经处理完（例如玩家死亡后跳过剩余事件）
    if (event == null && _outcome == null) {
      _scheduleClose();
      return const _EmptyDialog();
    }

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 620),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: SingleChildScrollView(
          child: _outcome == null
              ? _buildQuestion(game, event!)
              : _buildOutcome(game),
        ),
      ),
    );
  }

  /// 延迟一帧关闭弹窗（避免在 build 中 pop）
  void _scheduleClose() {
    if (_closing) return;
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).maybePop();
    });
  }

  /// 选项界面
  Widget _buildQuestion(GameProvider game, LifeEvent event) {
    final int hits = game.hitSkillCount(event);
    final double bonus = game.eventBonus(event);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            TagChip(
              text: game.currentEventIsForced ? '强制事件' : '人生事件',
              color: game.currentEventIsForced
                  ? AppColors.danger
                  : AppColors.primaryLight,
            ),
            if (game.currentEventIsAi) ...<Widget>[
              const SizedBox(width: 6),
              const TagChip(text: 'AI 原创', color: AppColors.epic),
            ],
            const SizedBox(width: 6),
            TagChip(
              text: '${event.minAge}-${event.maxAge} 岁',
              color: AppColors.textDim,
            ),
            if (event.eraLimit.isNotEmpty) ...<Widget>[
              const SizedBox(width: 6),
              TagChip(
                text: '${event.eraLimit.first} 年代',
                color: AppColors.epic,
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Text(
          event.title,
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 10),
        if (event.story.isNotEmpty)
          Text(
            event.story,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 14.5,
              height: 1.75,
            ),
          ),
        if (hits > 0) ...<Widget>[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withAlpha(30),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.auto_awesome,
                  size: 14,
                  color: AppColors.primaryLight,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '技能加成：命中 $hits 项技能，成功率 +${(bonus * 100).round()}%',
                    style: const TextStyle(
                      color: AppColors.primaryLight,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        ...List<Widget>.generate(event.choices.length, (int index) {
          final LifeEventChoice choice = event.choices[index];
          final bool picked = _picked == index;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: () => setState(() => _picked = index),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: picked
                      ? AppColors.primary.withAlpha(45)
                      : AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: picked ? AppColors.primaryLight : AppColors.divider,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(
                          picked
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          size: 15,
                          color:
                              picked ? AppColors.primaryLight : AppColors.textDim,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            choice.optionText,
                            style: const TextStyle(
                              color: AppColors.text,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (choice.hasAttrChange) ...<Widget>[
                      const SizedBox(height: 8),
                      DeltaChips(delta: choice.attrChange),
                    ],
                  ],
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 6),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '提示：选项的收益会受技能与运气影响',
                style: TextStyle(color: AppColors.textDim, fontSize: 11.5),
              ),
            ),
            ElevatedButton(
              onPressed: _picked < 0
                  ? null
                  : () {
                      final EventOutcome? before = game.lastOutcome;
                      game.chooseEventOption(_picked);
                      final EventOutcome? after = game.lastOutcome;
                      if (after != null && !identical(before, after)) {
                        setState(() {
                          _outcome = after;
                          _unlocked = List<String>.from(game.lastUnlocked);
                        });
                      }
                    },
              child: const Text('确定'),
            ),
          ],
        ),
      ],
    );
  }

  /// 结算界面
  Widget _buildOutcome(GameProvider game) {
    final EventOutcome outcome = _outcome!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            TagChip(
              text: outcome.died ? '人生结束' : '结果',
              color: outcome.died ? AppColors.danger : AppColors.primaryLight,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          outcome.text,
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 14.5,
            height: 1.75,
          ),
        ),
        if (!outcome.delta.isEmpty) ...<Widget>[
          const SizedBox(height: 12),
          const Text(
            '属性变化',
            style: TextStyle(
              color: AppColors.textDim,
              fontSize: 12,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          DeltaChips(delta: outcome.delta),
        ],
        if (outcome.messages.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          ...outcome.messages.map(
            (String m) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(
                    Icons.circle,
                    size: 5,
                    color: AppColors.primaryLight,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      m,
                      style: const TextStyle(
                        color: AppColors.textDim,
                        fontSize: 12.5,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (_unlocked.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          ..._unlocked.map(
            (String name) => Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.epic.withAlpha(28),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.epic.withAlpha(90)),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.emoji_events_outlined,
                    size: 14,
                    color: AppColors.epic,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '解锁成就：$name',
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (outcome.died) ...<Widget>[
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),
          const Text(
            '死亡结算 · 人生评分',
            style: TextStyle(
              color: AppColors.textDim,
              fontSize: 12,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          ScorePanel(score: game.lifeScore, expandDetail: true),
        ],
        const SizedBox(height: 14),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                outcome.died ? '这一世结束了，去人生总结看看' : '继续人生',
                style: const TextStyle(color: AppColors.textDim, fontSize: 12),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                game.dismissOutcome();
                Navigator.of(context).maybePop();
              },
              child: const Text('继续'),
            ),
          ],
        ),
      ],
    );
  }
}

/// 空弹窗（极端情况下的兜底，会立即自动关闭）
class _EmptyDialog extends StatelessWidget {
  const _EmptyDialog();

  @override
  Widget build(BuildContext context) {
    return const Dialog(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Text(
          '这一年的故事已经讲完了。',
          style: TextStyle(color: AppColors.text, fontSize: 14),
        ),
      ),
    );
  }
}
