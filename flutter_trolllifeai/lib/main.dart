// TrollLifeAI 入口
//
// 单机文字人生重开模拟器：
//   选年代 → 选城市 → 抽天赋 → 逐年推进 → 人生总结 → 转世
//
// 全局状态由 provider 注入，页面通过 context.read / context.watch 取用。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'pages/home_page.dart';
import 'pages/rebirth_page.dart';
import 'pages/start_page.dart';
import 'providers/game_provider.dart';
import 'theme/app_theme.dart';
import 'widgets/achievement_toast.dart';

void main() {
  runApp(const TrollLifeApp());
}

/// 应用根组件
class TrollLifeApp extends StatelessWidget {
  const TrollLifeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<GameProvider>(
      create: (BuildContext context) => GameProvider()..init(),
      child: MaterialApp(
        title: 'TrollLifeAI',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.dark,
        home: const AppRoot(),
        builder: (BuildContext context, Widget? child) {
          // 保证任何情况下文字缩放都不会撑破布局
          final MediaQueryData mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(
              textScaler: mq.textScaler.clamp(
                minScaleFactor: 0.9,
                maxScaleFactor: 1.2,
              ),
            ),
            child: child ?? const SizedBox.shrink(),
          );
        },
      ),
    );
  }
}

/// 根据游戏阶段分发到不同页面，并挂载全局提示层
class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    final GameProvider game = context.watch<GameProvider>();

    Widget page;
    switch (game.phase) {
      case GamePhase.loading:
        page = const LoadingPage();
        break;
      case GamePhase.setup:
        page = const StartPage();
        break;
      case GamePhase.running:
        page = const HomePage();
        break;
      case GamePhase.finished:
        page = const RebirthPage();
        break;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: <Widget>[
          Positioned.fill(child: page),
          // 成就解锁提示（全局，浮在所有页面之上）
          const AchievementToast(),
        ],
      ),
    );
  }
}

/// 数据加载页
class LoadingPage extends StatelessWidget {
  const LoadingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final GameProvider game = context.watch<GameProvider>();
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(height: 18),
          const Text(
            '正在读取人生剧本…',
            style: TextStyle(color: AppColors.textDim, fontSize: 13),
          ),
          if (game.loadError.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                game.loadError,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.danger, fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
