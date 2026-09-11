// 事件页（事件弹窗的独立入口）。
//
// 游戏中的事件默认由 EventGate 自动弹出（见 event_dialog.dart）；
// 本页把「手动触发 / 预览事件」的能力单独做成一个页面，
// 便于调试、金手指测试，也满足“每个页面一个 dart 文件”的结构要求。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/life_event.dart';
import '../providers/game_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'event_dialog.dart';

/// 事件页
class EventPage extends StatefulWidget {
  const EventPage({super.key});

  /// 以路由方式打开事件页
  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (BuildContext context) => const EventPage()),
    );
  }

  @override
  State<EventPage> createState() => _EventPageState();
}

class _EventPageState extends State<EventPage> {
  /// 预览列表条数
  int _previewLimit = 20;

  @override
  Widget build(BuildContext context) {
    final GameProvider game = context.watch<GameProvider>();
    final List<LifeEvent> preview = _buildPreview(game);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('事件'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: <Widget>[
          SectionCard(
            title: '事件机制',
            child: const Text(
              '· 每年按年龄段与年代抽取事件，同一条剧本只会出现一次\n'
              '· 年代专属事件（【80年代】/【年代:80】标记）只在对应年代出现\n'
              '· 选项结算后自动应用属性变化，并触发【习得】【关系】【宠物】等标记效果\n'
              '· 命中的技能每个 +7% 成功率（最高 +35%），幸运值额外 ±10%\n'
              '· 罪恶值 ≥45 可能被捕入狱；成瘾值 ≥60 可能触发强制事件「成瘾发作」',
              style: TextStyle(
                color: AppColors.textDim,
                fontSize: 12.5,
                height: 1.7,
              ),
            ),
          ),
          SectionCard(
            title: '当前事件状态',
            trailing: TagChip(
              text: game.hasPendingEvent ? '有待处理事件' : '空闲',
              color: game.hasPendingEvent
                  ? AppColors.warning
                  : AppColors.primaryLight,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                InfoRow(
                  label: '当前事件',
                  value: Text(
                    game.currentEvent?.title ?? '无',
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 13.5,
                    ),
                  ),
                ),
                InfoRow(
                  label: '强制事件',
                  value: Text(
                    '${game.forcedQueue.length} 条排队',
                    style: const TextStyle(
                      color: AppColors.textDim,
                      fontSize: 13,
                    ),
                  ),
                ),
                InfoRow(
                  label: '普通事件',
                  value: Text(
                    '${game.eventQueue.length} 条排队',
                    style: const TextStyle(
                      color: AppColors.textDim,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: ElevatedButton(
                        onPressed: game.currentEvent == null
                            ? null
                            : () => showEventDialog(context),
                        child: const Text('打开事件弹窗'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: game.character == null
                            ? null
                            : () => game.godTriggerEvent(),
                        child: const Text('随机触发一条'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SectionCard(
            title: '可抽取事件预览',
            trailing: TagChip(
              text: '展示 $_previewLimit 条',
              color: AppColors.textDim,
            ),
            child: preview.isEmpty
                ? const EmptyHint(text: '当前年龄与年代没有可用事件')
                : Column(
                    children: preview.map((LifeEvent e) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                TagChip(
                                  text: '${e.minAge}-${e.maxAge} 岁',
                                  color: AppColors.textDim,
                                ),
                                if (e.eraLimit.isNotEmpty) ...<Widget>[
                                  const SizedBox(width: 6),
                                  TagChip(
                                    text: '${e.eraLimit.first} 年代',
                                    color: AppColors.epic,
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              e.title,
                              style: const TextStyle(
                                color: AppColors.text,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${e.choices.length} 个选项',
                              style: const TextStyle(
                                color: AppColors.textDim,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  /// 构造预览列表（只读，不消耗事件池）
  List<LifeEvent> _buildPreview(GameProvider game) {
    if (game.character == null) return const <LifeEvent>[];
    final int age = game.character!.age;
    final String era = game.character!.era;
    final List<LifeEvent> out = <LifeEvent>[];
    for (final LifeEvent e in game.data.events) {
      if (e.forced) continue;
      if (!e.matchAge(age)) continue;
      if (!e.matchEra(era)) continue;
      out.add(e);
      if (out.length >= _previewLimit) break;
    }
    return out;
  }
}
