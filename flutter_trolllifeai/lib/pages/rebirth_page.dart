// 轮回页：人生总结 + 继承信息 + 转世按钮。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/character.dart';
import '../models/pet.dart';
import '../models/relation.dart';
import '../providers/game_provider.dart';
import '../services/score_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/save_slot_panel.dart';
import '../widgets/score_panel.dart';
import 'achievement_page.dart';

/// 轮回页
class RebirthPage extends StatelessWidget {
  const RebirthPage({super.key});

  @override
  Widget build(BuildContext context) {
    final GameProvider game = context.watch<GameProvider>();
    final Character? c = game.character;
    if (c == null) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Text(
            '没有可以总结的人生',
            style: TextStyle(color: AppColors.textDim),
          ),
        ),
      );
    }

    final Map<AttributeKey, int> inherit = game.inheritancePreview;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                children: <Widget>[
                  _buildHeader(c),
                  _buildScore(game),
                  _buildSummary(game, c),
                  _buildInheritance(inherit),
                  _buildFinalAttributes(c),
                  _buildRelationsAndPets(c),
                  _buildSaveSlots(),
                  _buildLogs(game),
                ],
              ),
            ),
            _buildBottomBar(context, game, c),
          ],
        ),
      ),
    );
  }

  /// 顶部：享年
  Widget _buildHeader(Character c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '人生总结',
            style: TextStyle(
              color: AppColors.primaryLight,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${c.name}（${c.gender}）享年 ${c.deathAge >= 0 ? c.deathAge : c.age} 岁',
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            c.deathReason.isEmpty ? '这一世结束了。' : c.deathReason,
            style: const TextStyle(
              color: AppColors.textDim,
              fontSize: 13,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  /// 人生评分与称号（分数 + 称号 + 评分明细入口）
  Widget _buildScore(GameProvider game) {
    final LifeScore score = game.lifeScore;
    return SectionCard(
      title: '人生评分',
      trailing: TagChip(
        text: score.title.name,
        color: AppColors.epic,
      ),
      child: ScorePanel(score: score),
    );
  }

  /// 存档管理（3 个槽位 + 文本导出 / 导入）
  Widget _buildSaveSlots() {
    return SectionCard(
      title: '存档管理',
      trailing: const TagChip(
        text: '3 个槽位',
        color: AppColors.textDim,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '存档保存在本机，可以随时回滚到某个节点；也可以导出文本做备份。',
            style: TextStyle(
              color: AppColors.textDim,
              fontSize: 12,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 12),
          const SaveSlotPanel(),
        ],
      ),
    );
  }

  /// 一生数据
  Widget _buildSummary(GameProvider game, Character c) {
    return SectionCard(
      title: '这一生',
      trailing: TagChip(
        text: '第 ${game.generation} 世',
        color: AppColors.epic,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InfoRow(
            label: '出身',
            value: Text('${game.eraLabel(c.era)} · ${c.cityName}'),
          ),
          InfoRow(
            label: '天赋',
            value: Text(c.talents.isEmpty ? '无' : c.talents.join(' / ')),
          ),
          InfoRow(
            label: '终职',
            value: Text(c.career == '无' ? '无业' : c.career),
          ),
          InfoRow(
            label: '净身家',
            value: Text(
              formatMoney(c.assets.netWorth),
              style: TextStyle(
                color: AppTheme.valueColor(c.assets.netWorth),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          InfoRow(
            label: '资产',
            value: Text(
              '现金 ${formatMoney(c.assets.cash)} · '
              '房产 ${formatMoney(c.assets.propertyValue)} · '
              '车 ${formatMoney(c.assets.vehicleValue)} · '
              '负债 ${formatMoney(c.assets.debt)}',
            ),
          ),
          InfoRow(
            label: '技能',
            value: Text('${c.skills.length} 项 · 成就 ${game.unlockedCount}/${game.achievementTotal}'),
          ),
          InfoRow(
            label: '经历',
            value: Text(
              '${c.logs.length} 条记录 · 见证 ${c.eraEventsSeen.length} 个年代事件',
            ),
          ),
          if (c.everJailed)
            InfoRow(
              label: '牢狱',
              value: Text(
                '实际服刑 ${c.totalJailYears} 年'
                '${c.jailYearsLeft > 0 ? '（还有 ${c.jailYearsLeft} 年未服完）' : ''}'
                '${c.everCommuted ? '（获得过减刑）' : ''}',
                style: const TextStyle(color: AppColors.warning),
              ),
            ),
        ],
      ),
    );
  }

  /// 继承信息
  Widget _buildInheritance(Map<AttributeKey, int> inherit) {
    final List<Widget> chips = <Widget>[];
    inherit.forEach((AttributeKey key, int value) {
      chips.add(
        DeltaChip(
          label: AttributeKeyX.shortLabel(key),
          value: value,
        ),
      );
    });
    return SectionCard(
      title: '转世继承（各取本世 8%）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (chips.isEmpty)
            const EmptyHint(text: '没有可继承的属性')
          else
            Wrap(spacing: 6, runSpacing: 6, children: chips),
          const SizedBox(height: 8),
          const Text(
            '智力 / 体质 / 魅力 / 运气 的 8% 会带到下一世，'
            '成就全部保留，天赋需要重新抽取。',
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

  /// 最终属性
  Widget _buildFinalAttributes(Character c) {
    return SectionCard(
      title: '最终属性',
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double tileWidth = (constraints.maxWidth - 12) / 2;
          return Wrap(
            spacing: 12,
            runSpacing: 4,
            children: AttributeKeyX.all.map((AttributeKey key) {
              return SizedBox(
                width: tileWidth,
                child: AttributeBar(
                  label: AttributeKeyX.shortLabel(key),
                  value: c.attr(key),
                  maxValue: key == AttributeKey.wealth ? c.wealthCap : 150,
                  isMoney: key == AttributeKey.wealth,
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  /// 关系与宠物
  Widget _buildRelationsAndPets(Character c) {
    final List<Relation> relations = c.relations;
    final List<Pet> pets = c.pets;
    return SectionCard(
      title: '留下的人与动物',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (relations.isEmpty)
            const Text(
              '一生没有留下什么关系。',
              style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: relations.map((Relation r) {
                final String suffix = r.alive ? '' : '（已结束）';
                return TagChip(
                  text: '${RelationTypeX.label(r.type)}·${r.name}$suffix',
                  color: r.alive ? AppColors.primaryLight : AppColors.textDim,
                );
              }).toList(),
            ),
          const SizedBox(height: 10),
          if (pets.isEmpty)
            const Text(
              '没有养过宠物。',
              style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: pets.map((Pet pet) {
                return TagChip(
                  text: '${pet.name}（${PetStatusX.label(pet.status)}）',
                  color: pet.isAlive ? AppColors.primaryLight : AppColors.textDim,
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  /// 完整日志（折叠）
  Widget _buildLogs(GameProvider game) {
    final List<LifeLogEntry> logs = game.recentLogs(limit: 40);
    return SectionCard(
      title: '最后一页回忆',
      trailing: TagChip(
        text: '共 ${game.character?.logs.length ?? 0} 条，展示最近 ${logs.length} 条',
        color: AppColors.textDim,
      ),
      child: logs.isEmpty
          ? const EmptyHint(text: '没有留下记录')
          : Column(
              children: logs
                  .map(
                    (LifeLogEntry e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          SizedBox(
                            width: 40,
                            child: Text(
                              '${e.age}岁',
                              style: const TextStyle(
                                color: AppColors.textDim,
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              e.text,
                              style: const TextStyle(
                                color: AppColors.text,
                                fontSize: 12.5,
                                height: 1.5,
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

  /// 底部操作
  Widget _buildBottomBar(BuildContext context, GameProvider game, Character c) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: () => AchievementPage.open(context),
                  child: Text('成就 ${game.unlockedCount}/${game.achievementTotal}'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: () => game.rebirth(),
                  child: const Text('转世重开'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '转世后会回到开局页，重新选择年代、城市与天赋',
            style: TextStyle(color: AppColors.textDim, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}
