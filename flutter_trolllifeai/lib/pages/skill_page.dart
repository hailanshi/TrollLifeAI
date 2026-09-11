// 技能页：已习得 / 未习得，显示 effect、desc 与关键词加成。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/character.dart';
import '../models/skill.dart';
import '../providers/game_provider.dart';
import '../services/event_engine.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

/// 技能筛选
enum SkillFilter {
  /// 全部
  all,

  /// 已习得
  learned,

  /// 未习得
  unlearned,
}

/// 技能页
class SkillPage extends StatefulWidget {
  const SkillPage({super.key});

  /// 以路由方式打开
  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const SkillPage(),
      ),
    );
  }

  @override
  State<SkillPage> createState() => _SkillPageState();
}

class _SkillPageState extends State<SkillPage> {
  SkillFilter _filter = SkillFilter.all;

  @override
  Widget build(BuildContext context) {
    final GameProvider game = context.watch<GameProvider>();
    final Character? c = game.character;
    final List<Skill> learned = game.learnedSkills;
    final List<Skill> unlearned = game.unlearnedSkills;

    List<Skill> list;
    switch (_filter) {
      case SkillFilter.learned:
        list = learned;
        break;
      case SkillFilter.unlearned:
        list = unlearned;
        break;
      case SkillFilter.all:
        list = <Skill>[...learned, ...unlearned];
        break;
    }

    final double bonusPercent = (learned.length * 7).clamp(0, 35).toDouble();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('技能'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: <Widget>[
          SectionCard(
            title: '技能加成',
            trailing: TagChip(
              text: '${learned.length} / ${game.allSkills.length}',
              color: AppColors.primaryLight,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: bonusPercent / 35,
                    minHeight: 8,
                    backgroundColor: AppColors.divider,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.primaryLight,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '每个命中事件关键词的技能提供 +7% 成功率，'
                  '当前合计 +${bonusPercent.round()}%（上限 +35%）',
                  style: const TextStyle(
                    color: AppColors.textDim,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
                if (c != null && c.skills.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: learned
                        .map(
                          (Skill s) => TagChip(
                            text: s.name,
                            color: AppColors.primaryLight,
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
          SectionCard(
            dense: true,
            title: '筛选',
            child: Wrap(
              spacing: 8,
              children: <Widget>[
                _filterChip('全部', SkillFilter.all, game.allSkills.length),
                _filterChip('已习得', SkillFilter.learned, learned.length),
                _filterChip('未习得', SkillFilter.unlearned, unlearned.length),
              ],
            ),
          ),
          if (list.isEmpty)
            const SectionCard(child: EmptyHint(text: '没有符合条件的技能'))
          else
            ...list.map(
              (Skill s) => _SkillCard(
                skill: s,
                learned: c?.skills.contains(s.skillId) ?? false,
              ),
            ),
        ],
      ),
    );
  }

  /// 筛选按钮
  Widget _filterChip(String label, SkillFilter filter, int count) {
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

/// 单个技能卡片
class _SkillCard extends StatelessWidget {
  final Skill skill;
  final bool learned;

  const _SkillCard({required this.skill, required this.learned});

  @override
  Widget build(BuildContext context) {
    final List<String> keywords = EventEngine.skillKeywords[skill.skillId] ?? <String>[];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: learned ? AppColors.primary.withAlpha(110) : AppColors.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                learned ? Icons.check_circle_outline : Icons.lock_outline,
                size: 16,
                color: learned ? AppColors.primaryLight : AppColors.textDim,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  skill.name,
                  style: TextStyle(
                    color: learned ? AppColors.text : AppColors.textDim,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TagChip(
                text: learned ? '已习得' : '未习得',
                color: learned ? AppColors.primaryLight : AppColors.textDim,
              ),
            ],
          ),
          if (skill.desc.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              skill.desc,
              style: TextStyle(
                color: learned ? AppColors.text : AppColors.textDim,
                fontSize: 13,
                height: 1.55,
              ),
            ),
          ],
          if (skill.effect.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(
                  Icons.auto_awesome,
                  size: 13,
                  color: AppColors.warning,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    skill.effect,
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
          if (keywords.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: keywords
                  .take(6)
                  .map(
                    (String k) => TagChip(text: k, color: AppColors.textDim),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            '技能 id：${skill.skillId}',
            style: const TextStyle(color: AppColors.textDim, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// 供页面显示技能数的小工具（避免每个页面重复算）
String skillSummary(Character c) => '已习得 ${c.skills.length} 项技能';
