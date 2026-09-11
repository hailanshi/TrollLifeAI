// 成就页：已解锁 / 未解锁，显示 desc 与 trigger，顶部进度，可筛选。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/achievement.dart';
import '../providers/game_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

/// 筛选模式
enum AchievementFilter {
  /// 全部
  all,

  /// 只看已解锁
  unlocked,

  /// 只看未解锁
  locked,
}

/// 成就页
class AchievementPage extends StatefulWidget {
  const AchievementPage({super.key});

  /// 以路由方式打开
  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const AchievementPage(),
      ),
    );
  }

  @override
  State<AchievementPage> createState() => _AchievementPageState();
}

class _AchievementPageState extends State<AchievementPage> {
  /// 当前筛选
  AchievementFilter _filter = AchievementFilter.all;

  @override
  Widget build(BuildContext context) {
    final GameProvider game = context.watch<GameProvider>();
    final List<AchievementState> list = game.achievementStates(
      onlyUnlocked: _filter == AchievementFilter.unlocked,
      onlyLocked: _filter == AchievementFilter.locked,
    );
    final int total = game.achievementTotal;
    final int done = game.unlockedCount;
    final double ratio = total == 0 ? 0 : (done / total).clamp(0.0, 1.0).toDouble();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('成就'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: <Widget>[
          // 顶部进度
          SectionCard(
            title: '解锁进度',
            trailing: TagChip(
              text: '$done / $total',
              color: AppColors.primaryLight,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 8,
                    backgroundColor: AppColors.divider,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.primaryLight,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '已完成 ${(ratio * 100).toStringAsFixed(1)}% · '
                  '成就跨轮回永久保存，转世后依然保留',
                  style: const TextStyle(
                    color: AppColors.textDim,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          // 筛选
          SectionCard(
            dense: true,
            title: '筛选',
            child: Wrap(
              spacing: 8,
              children: <Widget>[
                _filterChip('全部', AchievementFilter.all, total),
                _filterChip('已解锁', AchievementFilter.unlocked, done),
                _filterChip(
                  '未解锁',
                  AchievementFilter.locked,
                  total - done,
                ),
              ],
            ),
          ),
          // 列表
          if (list.isEmpty)
            const SectionCard(
              child: EmptyHint(text: '没有符合条件的成就'),
            )
          else
            ...list.map((AchievementState s) => _AchievementCard(state: s)),
        ],
      ),
    );
  }

  /// 筛选按钮
  Widget _filterChip(String label, AchievementFilter filter, int count) {
    final bool selected = _filter == filter;
    return GestureDetector(
      onTap: () => setState(() => _filter = filter),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withAlpha(60)
              : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.primaryLight : AppColors.divider,
          ),
        ),
        child: Text(
          '$label $count',
          style: TextStyle(
            color: selected ? AppColors.primaryLight : AppColors.text,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// 单个成就卡片
class _AchievementCard extends StatelessWidget {
  final AchievementState state;

  const _AchievementCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final bool unlocked = state.unlocked;
    final Color accent = unlocked ? AppColors.primaryLight : AppColors.textDim;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: unlocked ? AppColors.surface : AppColors.surface.withAlpha(190),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: unlocked ? AppColors.primary.withAlpha(110) : AppColors.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                unlocked
                    ? Icons.emoji_events
                    : Icons.radio_button_unchecked,
                size: 17,
                color: accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  state.name,
                  style: TextStyle(
                    color: unlocked ? AppColors.text : AppColors.textDim,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (unlocked && state.unlockedAge >= 0)
                TagChip(
                  text: '第 ${state.unlockedLife} 世 · ${state.unlockedAge} 岁',
                  color: AppColors.primaryLight,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            state.achievement.desc,
            style: TextStyle(
              color: unlocked ? AppColors.text : AppColors.textDim,
              fontSize: 13,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(
                Icons.flag_outlined,
                size: 13,
                color: AppColors.textDim,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '触发条件：${state.achievement.trigger}',
                  style: const TextStyle(
                    color: AppColors.textDim,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
