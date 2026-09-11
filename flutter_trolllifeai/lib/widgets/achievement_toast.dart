// 成就解锁提示：浮在页面顶部的轻量提示条。
//
// 由 AppRoot 常驻挂载，直接监听 GameProvider 的解锁列表变化。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/game_provider.dart';
import '../theme/app_theme.dart';

/// 成就提示层
class AchievementToast extends StatefulWidget {
  const AchievementToast({super.key});

  @override
  State<AchievementToast> createState() => _AchievementToastState();
}

class _AchievementToastState extends State<AchievementToast> {
  /// 正在展示的成就名
  final List<String> _showing = <String>[];

  /// 自动消失定时器
  Timer? _timer;

  /// 已经处理过的解锁条数
  int _handledCount = 0;

  /// 订阅者（手动订阅，避免 build 里做副作用）
  GameProvider? _game;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final GameProvider game = context.read<GameProvider>();
    if (identical(_game, game)) return;
    _game?.removeListener(_onGameChanged);
    _game = game..addListener(_onGameChanged);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _game?.removeListener(_onGameChanged);
    super.dispose();
  }

  /// 游戏状态变化：检查是否有新解锁的成就
  void _onGameChanged() {
    final GameProvider? game = _game;
    if (game == null || !mounted) return;

    if (game.lastUnlocked.isEmpty) {
      _handledCount = 0;
      return;
    }
    if (game.lastUnlocked.length == _handledCount) return;
    _handledCount = game.lastUnlocked.length;

    bool changed = false;
    for (final String name in game.lastUnlocked) {
      if (_showing.contains(name)) continue;
      _showing.add(name);
      changed = true;
    }
    while (_showing.length > 2) {
      _showing.removeAt(0);
      changed = true;
    }
    if (!changed) return;

    setState(() {});
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 2400), () {
      if (!mounted) return;
      setState(_showing.clear);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showing.isEmpty) return const SizedBox.shrink();
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 16,
      right: 16,
      child: Column(
        children: _showing
            .map(
              (String name) => Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.primary.withAlpha(120)),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withAlpha(90),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(
                      Icons.emoji_events_outlined,
                      size: 16,
                      color: AppColors.epic,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '成就解锁 · $name',
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}
