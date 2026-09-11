// AI 续写等待层：监听 GameProvider.pendingAiRequest，
// 自动弹出「AI 正在续写剧情…」对话框，并提供「不等了，用本地剧情」按钮。
//
// 与 event_dialog.dart 里的 EventGate 并列挂在属性主页的 Stack 中：
//   AI 命中 → 等待框 → 成功则用 AI 事件替换本地事件，失败 / 放弃则回退本地事件。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/character.dart';
import '../providers/game_provider.dart';
import '../services/ai_service.dart';
import '../theme/app_theme.dart';

/// AI 等待弹窗的宿主（本身不渲染任何东西）
class AiGate extends StatefulWidget {
  const AiGate({super.key});

  @override
  State<AiGate> createState() => _AiGateState();
}

class _AiGateState extends State<AiGate> {
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

  /// 状态变化：有等待中的 AI 请求就弹窗
  void _onChanged() {
    if (!mounted || _dialogOpen) return;
    final GameProvider? game = _game;
    if (game == null || game.pendingAiRequest == null) return;
    _open(game);
  }

  /// 打开等待弹窗（延迟一帧，避免在 build / notify 过程中 push）
  void _open(GameProvider game) {
    _dialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _dialogOpen = false;
        return;
      }
      final AiPendingRequest? request = game.pendingAiRequest;
      if (request == null) {
        _dialogOpen = false;
        return;
      }
      // 请求已经结束（例如瞬时失败）：不弹窗，直接结算并给出提示
      if (request.finished) {
        _dialogOpen = false;
        game.settleAiRequest();
        _showNotice(game);
        return;
      }
      showAiWaitingDialog(context, request).whenComplete(() {
        _dialogOpen = false;
        final GameProvider? current = _game;
        if (mounted && current != null && current.pendingAiRequest != null) {
          _open(current);
        }
      });
    });
  }

  /// 展示一次性的 AI 提示（失败回退等）
  void _showNotice(GameProvider game) {
    final String notice = game.takeAiNotice();
    if (notice.isEmpty || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(notice)));
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// 手动 / 自动打开「AI 正在续写剧情…」弹窗
Future<void> showAiWaitingDialog(
  BuildContext context,
  AiPendingRequest request,
) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    useSafeArea: true,
    builder: (BuildContext context) => _AiWaitingDialog(request: request),
  );
}

/// 等待弹窗本体：请求结束后自动关掉自己，并把结果交给 GameProvider 落地
class _AiWaitingDialog extends StatefulWidget {
  /// 等待中的请求
  final AiPendingRequest request;

  const _AiWaitingDialog({required this.request});

  @override
  State<_AiWaitingDialog> createState() => _AiWaitingDialogState();
}

class _AiWaitingDialogState extends State<_AiWaitingDialog> {
  /// 是否已经关过（防止重复 pop 把下面的弹窗顶掉）
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    // 等第一帧之后再取 Provider / Messenger，避免在 initState 里做依赖查找
    WidgetsBinding.instance.addPostFrameCallback((_) => _wait());
  }

  /// 等请求结束 → 关掉自己 → 让 Provider 落地结果并提示
  Future<void> _wait() async {
    if (!mounted) return;
    final GameProvider game = context.read<GameProvider>();
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    await widget.request.done.future;
    if (!mounted || _closed) return;
    _closed = true;
    // 注意：弹窗外面包了 PopScope(canPop: false)，必须用 pop() 直接关闭
    Navigator.of(context).pop();
    game.settleAiRequest();
    final String notice = game.takeAiNotice();
    if (notice.isNotEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(notice)));
    }
  }

  /// 「不等了」：立刻回退本地事件
  void _useLocal(GameProvider game) {
    game.cancelAiToLocal();
  }

  @override
  Widget build(BuildContext context) {
    final GameProvider game = context.watch<GameProvider>();
    final Character? c = game.character;
    String where = '';
    if (c != null) {
      where = '第 ${widget.request.age} 岁 · ${game.eraLabel(c.era)} · ${c.cityName}';
    }

    return PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'AI 正在续写剧情…',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                where,
                style: const TextStyle(
                  color: AppColors.textDim,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '正在请求模型生成这一年的原创事件，通常几秒内返回。\n'
                '拿不到结果（失败 / 超时 / 结构不合格）会自动改用本地剧情，不会卡住游戏。',
                style: TextStyle(
                  color: AppColors.textDim,
                  fontSize: 12.5,
                  height: 1.7,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '本世已用 ${c?.aiUsed ?? 0} 次 · 剩余 ${game.aiQuotaLeft} 次 · '
                '模型 ${game.aiOptions.model}',
                style: const TextStyle(
                  color: AppColors.textDim,
                  fontSize: 11.5,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '等待上限 ${game.aiOptions.timeoutMs ~/ 1000} 秒',
                      style: const TextStyle(
                        color: AppColors.textDim,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () => _useLocal(game),
                    child: const Text('不等了，用本地剧情'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
