// 属性主页：11 项属性 + 资产负债 + 成瘾 + 人际关系 + 宠物 + 人生日志。
//
// 底部固定「过一年 / 快进十年」按钮；事件由 EventGate 自动弹窗。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/asset_state.dart';
import '../models/character.dart';
import '../models/pet.dart';
import '../models/relation.dart';
import '../providers/game_provider.dart';
import '../services/action_engine.dart';
import '../theme/app_theme.dart';
import '../widgets/ai_gate.dart';
import '../widgets/common_widgets.dart';
import '../widgets/save_slot_panel.dart';
import 'achievement_page.dart';
import 'ai_page.dart';
import 'event_dialog.dart';
import 'event_page.dart';
import 'god_console_page.dart';
import 'skill_page.dart';

/// 属性主页
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final GameProvider game = context.watch<GameProvider>();
    final Character? c = game.character;
    if (c == null) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Text(
            '还没有进行中的角色',
            style: TextStyle(color: AppColors.textDim),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('${c.name} · ${c.age} 岁'),
        actions: <Widget>[
          IconButton(
            tooltip: '人生总结',
            icon: const Icon(Icons.history_edu_outlined, size: 20),
            onPressed: () => _openSummary(context, game),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz),
            color: AppColors.surfaceAlt,
            onSelected: (String value) => _onMenu(context, game, value),
            itemBuilder: (BuildContext context) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(value: 'achievement', child: Text('成就')),
              PopupMenuItem<String>(value: 'skill', child: Text('技能')),
              PopupMenuItem<String>(value: 'event', child: Text('事件')),
              PopupMenuItem<String>(value: 'ai', child: Text('AI 剧情设置')),
              PopupMenuItem<String>(value: 'slots', child: Text('存档管理（3 槽位）')),
              PopupMenuItem<String>(value: 'god', child: Text('调试控制台')),
              PopupMenuItem<String>(value: 'save', child: Text('保存进度')),
              PopupMenuItem<String>(value: 'abandon', child: Text('放弃这一世（回开局页）')),
              PopupMenuItem<String>(value: 'kill', child: Text('结束这一世')),
            ],
          ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: <Widget>[
              _InfoSection(character: c, game: game),
              _ActionGridSection(game: game),
              _AttributesSection(character: c),
              _AssetSection(character: c),
              _AddictionSection(character: c),
              _RelationSection(character: c, game: game),
              _PetSection(character: c),
              _ShortcutSection(game: game),
              _ActionSection(game: game),
            ],
          ),
          const EventGate(),
          // AI 续写等待层（命中条件时自动弹「AI 正在续写剧情…」）
          const AiGate(),
        ],
      ),
    );
  }

  /// 菜单动作分发
  void _onMenu(BuildContext context, GameProvider game, String value) {
    switch (value) {
      case 'achievement':
        AchievementPage.open(context);
        break;
      case 'skill':
        SkillPage.open(context);
        break;
      case 'event':
        EventPage.open(context);
        break;
      case 'ai':
        AiPage.open(context);
        break;
      case 'slots':
        _openSlotSheet(context);
        break;
      case 'god':
        GodConsolePage.open(context);
        break;
      case 'save':
        game.saveNow();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              game.isMemoryOnly ? '已保存到内存（不可写磁盘）' : '已保存：${game.storagePath}',
            ),
          ),
        );
        break;
      case 'abandon':
        showDialog<void>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: const Text('放弃这一世'),
            content: const Text(
              '当前这一世的进度会被删除（成就保留），回到开局页重新选择年代与天赋。确定吗？',
              style: TextStyle(fontSize: 13.5, height: 1.6),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  context.read<GameProvider>().abandonLife();
                },
                child: const Text('确定放弃'),
              ),
            ],
          ),
        );
        break;
      case 'kill':
        showDialog<void>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: const Text('结束这一世'),
            content: const Text(
              '会直接进入人生总结，之后可以转世重开。确定吗？',
              style: TextStyle(fontSize: 13.5, height: 1.6),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  context.read<GameProvider>().killCharacter('你选择了结束这一世');
                },
                child: const Text('确定'),
              ),
            ],
          ),
        );
        break;
    }
  }

  /// 存档管理底部弹层（3 个槽位 + 文本导出 / 导入）
  void _openSlotSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                '存档管理',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '3 个槽位可以随时保存 / 读取 / 删除，也可以导出存档文本做备份。',
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
        ),
      ),
    );
  }

  /// 打开人生总结（简化版：弹窗展示关键数据）
  void _openSummary(BuildContext context, GameProvider game) {
    final Character? c = game.character;
    if (c == null) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              '本世速览',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            InfoRow(label: '姓名', value: Text(c.name)),
            InfoRow(label: '年龄', value: Text('${c.age} 岁')),
            InfoRow(
              label: '年代',
              value: Text('${game.eraLabel(c.era)} · ${c.cityName}'),
            ),
            InfoRow(label: '职业', value: Text(c.career)),
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
            InfoRow(label: '技能', value: Text('${c.skills.length} 项')),
            InfoRow(
              label: '成就',
              value: Text('${game.unlockedCount} / ${game.achievementTotal}'),
            ),
            InfoRow(label: '日志', value: Text('${c.logs.length} 条')),
            InfoRow(
              label: '人生评分',
              value: Text(
                game.lifeScore.summary,
                style: const TextStyle(
                  color: AppColors.primaryLight,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 区块①：基本信息
// ---------------------------------------------------------------------------

class _InfoSection extends StatelessWidget {
  final Character character;
  final GameProvider game;

  const _InfoSection({required this.character, required this.game});

  @override
  Widget build(BuildContext context) {
    final Character c = character;
    return SectionCard(
      title: '人生状态',
      trailing: TagChip(
        text: c.inPrison
            ? '服刑中 ${c.jailYearsLeft} 年'
            : (c.unemployed ? '待业' : (c.hasJob ? '在业' : '无业')),
        color: c.inPrison
            ? AppColors.danger
            : (c.unemployed ? AppColors.warning : AppColors.primaryLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              TagChip(text: game.eraLabel(c.era), color: AppColors.primaryLight),
              TagChip(text: c.cityName, color: AppColors.primaryLight),
              TagChip(
                text: '${c.calendarYear} 年',
                color: AppColors.textDim,
              ),
              TagChip(
                text: '寿命 ${c.lifespan} 岁',
                color: AppColors.textDim,
              ),
              if (c.talents.isNotEmpty)
                TagChip(
                  text: '天赋 · ${c.talents.join(' / ')}',
                  color: AppColors.epic,
                ),
              if (c.hasCriminalRecord)
                const TagChip(text: '有案底', color: AppColors.danger),
            ],
          ),
          const SizedBox(height: 10),
          InfoRow(label: '职业', value: Text(c.career)),
          InfoRow(
            label: '财富上限',
            value: Text(
              '${formatMoney(c.wealthCap)}（系数 ${c.wealthCapFactor}）',
            ),
          ),
          InfoRow(
            label: '技能加成',
            value: Text(
              '已习得 ${c.skills.length} 项技能，'
              '最高成功率 +${(c.skills.isEmpty ? 0 : _maxBonus(c))}%',
            ),
          ),
          if (c.deathReason.isNotEmpty)
            InfoRow(
              label: '死因',
              value: Text(
                c.deathReason,
                style: const TextStyle(color: AppColors.danger),
              ),
            ),
        ],
      ),
    );
  }

  /// 当前技能能提供的最大加成（百分比整数）
  int _maxBonus(Character c) {
    final int hits = c.skills.length;
    final int percent = (hits * 7).clamp(0, 35);
    return percent;
  }
}

// ---------------------------------------------------------------------------
// 区块①.5：主动行动（每岁 1 点行动力，两列网格）
// ---------------------------------------------------------------------------

class _ActionGridSection extends StatelessWidget {
  final GameProvider game;

  const _ActionGridSection({required this.game});

  @override
  Widget build(BuildContext context) {
    final Character? c = game.character;
    if (c == null) return const SizedBox.shrink();
    final List<ActionCard> cards = game.actionCards;

    return SectionCard(
      title: '主动行动',
      trailing: TagChip(
        text: '行动点 ${c.actionPoints} / 1',
        color: c.actionPoints > 0 ? AppColors.primaryLight : AppColors.textDim,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            c.inPrison
                ? '服刑期间失去行动自由，只能继续服刑。'
                : '每年 1 点行动力，可以主动做一件事；也可以什么都不做直接过一年。',
            style: TextStyle(
              color: c.inPrison ? AppColors.danger : AppColors.textDim,
              fontSize: 12,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              // 两列排布，窄屏也能保持可读
              final double tileWidth = (constraints.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: cards.map((ActionCard card) {
                  return SizedBox(
                    width: tileWidth,
                    child: _ActionTile(
                      card: card,
                      onTap: () => _run(context, card),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  /// 执行行动并用 SnackBar 反馈
  void _run(BuildContext context, ActionCard card) {
    if (!card.usable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(card.reason.isEmpty ? '暂时不能做' : card.reason)),
      );
      return;
    }
    final String message = game.performAction(card.spec.id);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// 单个行动卡片：名称 + 分类标签 + 说明（不可用时置灰并显示原因）
class _ActionTile extends StatelessWidget {
  final ActionCard card;
  final VoidCallback onTap;

  const _ActionTile({required this.card, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bool usable = card.usable;
    final Color nameColor = usable ? AppColors.text : AppColors.textDim;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: usable ? AppColors.surfaceAlt : AppColors.surfaceAlt.withAlpha(120),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: usable ? AppColors.divider : AppColors.divider.withAlpha(120),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    card.name,
                    style: TextStyle(
                      color: nameColor,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TagChip(
                  text: card.tag,
                  color: usable ? AppColors.primaryLight : AppColors.textDim,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              card.displayDesc,
              style: TextStyle(
                color: usable ? AppColors.textDim : AppColors.warning,
                fontSize: 11.5,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 区块②：11 项属性
// ---------------------------------------------------------------------------

class _AttributesSection extends StatelessWidget {
  final Character character;

  const _AttributesSection({required this.character});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: '属性',
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // 两列排布，窄屏也能保持可读
          final double tileWidth = (constraints.maxWidth - 12) / 2;
          return Wrap(
            spacing: 12,
            runSpacing: 4,
            children: AttributeKeyX.all.map((AttributeKey key) {
              final int value = character.attr(key);
              final bool isMoney = key == AttributeKey.wealth;
              final int maxValue = isMoney
                  ? character.wealthCap
                  : (key == AttributeKey.health ||
                          key == AttributeKey.happiness ||
                          key == AttributeKey.stress ||
                          key == AttributeKey.addiction ||
                          key == AttributeKey.sin ||
                          key == AttributeKey.fame)
                      ? 100
                      : 150;
              return SizedBox(
                width: tileWidth,
                child: AttributeBar(
                  label: AttributeKeyX.shortLabel(key),
                  value: value,
                  maxValue: maxValue,
                  isMoney: isMoney,
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 区块③：资产与负债
// ---------------------------------------------------------------------------

class _AssetSection extends StatelessWidget {
  final Character character;

  const _AssetSection({required this.character});

  @override
  Widget build(BuildContext context) {
    final Character c = character;
    return SectionCard(
      title: '资产与负债',
      trailing: TagChip(
        text: '净值 ${formatMoney(c.assets.netWorth)}',
        color: AppTheme.valueColor(c.assets.netWorth),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AttributeBar(
            label: '现金',
            value: c.assets.cash,
            maxValue: c.wealthCap,
            isMoney: true,
          ),
          AttributeBar(
            label: '负债',
            value: c.assets.debt,
            maxValue: 1000000,
            isMoney: true,
          ),
          const SizedBox(height: 8),
          InfoRow(
            label: '总资产',
            value: Text(
              '${formatMoney(c.assets.totalAsset)}'
              '（房产 ${formatMoney(c.assets.propertyValue)} · '
              '车 ${formatMoney(c.assets.vehicleValue)}）',
            ),
          ),
          if (c.assets.properties.isNotEmpty)
            InfoRow(
              label: '房产',
              value: Text(
                c.assets.properties
                    .map((PropertyAsset asset) =>
                        '${asset.cityName} ${formatMoney(asset.value)}')
                    .join('、'),
              ),
            ),
          if (c.assets.vehicles.isNotEmpty)
            InfoRow(
              label: '车辆',
              value: Text(
                c.assets.vehicles
                    .map((VehicleAsset v) => '${v.label} ${formatMoney(v.value)}')
                    .join('、'),
              ),
            ),
          InfoRow(
            label: '保险',
            value: Text(
              c.assets.hasInsurance
                  ? '已投保（剩余 ${c.assets.insuranceYears} 年）'
                  : '未投保',
            ),
          ),
          if (c.assets.luxurySpent > 0)
            InfoRow(
              label: '奢侈品',
              value: Text('累计花掉 ${formatMoney(c.assets.luxurySpent)}'),
            ),
          if (c.assets.investProfit != 0)
            InfoRow(
              label: '理财收益',
              value: Text(
                formatMoney(c.assets.investProfit),
                style: TextStyle(
                  color: AppTheme.valueColor(c.assets.investProfit),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 区块④：成瘾状态
// ---------------------------------------------------------------------------

class _AddictionSection extends StatelessWidget {
  final Character character;

  const _AddictionSection({required this.character});

  @override
  Widget build(BuildContext context) {
    final Character c = character;
    final int max = c.maxAddiction;
    return SectionCard(
      title: '成瘾状态',
      trailing: TagChip(
        text: max >= 60 ? '高危' : (max >= 30 ? '注意' : '正常'),
        color: max >= 60
            ? AppColors.danger
            : (max >= 30 ? AppColors.warning : AppColors.primaryLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ...c.addictions.entries.map(
            (MapEntry<String, int> e) => AttributeBar(
              label: e.key.length > 2 ? e.key.substring(0, 2) : e.key,
              value: e.value,
              maxValue: 100,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            max >= 60
                ? '成瘾值过高，每年都可能触发「成瘾发作」强制事件。'
                : '成瘾值 ≥60 时会每年按概率触发成瘾发作。',
            style: TextStyle(
              color: max >= 60 ? AppColors.danger : AppColors.textDim,
              fontSize: 12,
            ),
          ),
          if (c.attr(AttributeKey.sin) >= 45) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              '罪恶值 ${c.attr(AttributeKey.sin)}：每年都有被捕入狱的风险。',
              style: const TextStyle(color: AppColors.danger, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 区块⑤：人际关系
// ---------------------------------------------------------------------------

class _RelationSection extends StatelessWidget {
  final Character character;
  final GameProvider game;

  const _RelationSection({required this.character, required this.game});

  @override
  Widget build(BuildContext context) {
    final List<Relation> list = character.activeRelations;
    list.sort((Relation a, Relation b) {
      final int w =
          RelationTypeX.sortWeight(a.type) - RelationTypeX.sortWeight(b.type);
      if (w != 0) return w;
      return b.favor - a.favor;
    });

    return SectionCard(
      title: '人际关系',
      trailing: TagChip(
        text:
            '朋友 ${character.countRelation(RelationType.friend)} · 子女 ${character.childCount}',
        color: AppColors.textDim,
      ),
      child: list.isEmpty
          ? const EmptyHint(text: '还没有认识什么人')
          : Column(
              children: list.map((Relation r) {
                return _RelationRow(relation: r, game: game);
              }).toList(),
            ),
    );
  }
}

/// 单条关系（含送礼 / 深聊 / 和解 / 求婚互动）
class _RelationRow extends StatelessWidget {
  final Relation relation;
  final GameProvider game;

  const _RelationRow({required this.relation, required this.game});

  @override
  Widget build(BuildContext context) {
    final bool enemy = relation.type == RelationType.enemy;
    final Color color = enemy
        ? AppColors.danger
        : (relation.favor >= 80 ? AppColors.success : AppColors.primaryLight);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              TagChip(
                text: RelationTypeX.label(relation.type),
                color: enemy ? AppColors.danger : AppColors.primaryLight,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  relation.name,
                  style: const TextStyle(color: AppColors.text, fontSize: 14),
                ),
              ),
              SizedBox(
                width: 92,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: (relation.favor / 100).clamp(0.0, 1.0).toDouble(),
                    minHeight: 5,
                    backgroundColor: AppColors.divider,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${relation.favor}',
                style: TextStyle(color: color, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _buildInteractRow(context),
        ],
      ),
    );
  }

  /// 互动按钮行：送礼 / 深聊（仇人加「和解」，恋人加「求婚」）
  Widget _buildInteractRow(BuildContext context) {
    final List<RelationInteract> kinds = game.interactsFor(relation);
    final int age = game.character?.age ?? -1;
    final bool acted = relation.lastAct >= 0 && relation.lastAct == age;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: kinds.map((RelationInteract info) {
            final String reason = game.relationInteractReason(relation, info.kind);
            final bool usable = reason.isEmpty;
            String label = info.name;
            if (info.cost > 0) {
              label = '${info.name} ¥${formatMoney(info.cost)}';
            }
            return GestureDetector(
              onTap: () => _interact(context, info, usable, reason),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: usable
                        ? AppColors.primary.withAlpha(110)
                        : AppColors.divider,
                  ),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: usable ? AppColors.primaryLight : AppColors.textDim,
                    fontSize: 11.5,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        if (acted)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              '今年已经互动过了',
              style: TextStyle(color: AppColors.textDim, fontSize: 11),
            ),
          ),
      ],
    );
  }

  /// 执行互动并用 SnackBar 反馈
  void _interact(
    BuildContext context,
    RelationInteract info,
    bool usable,
    String reason,
  ) {
    if (!usable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(reason.isEmpty ? '暂时不能互动' : reason)),
      );
      return;
    }
    final String message = game.interactRelation(relation, info.kind);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

// ---------------------------------------------------------------------------
// 区块⑥：宠物
// ---------------------------------------------------------------------------

class _PetSection extends StatelessWidget {
  final Character character;

  const _PetSection({required this.character});

  @override
  Widget build(BuildContext context) {
    final List<Pet> pets = character.pets;
    return SectionCard(
      title: '宠物',
      trailing: TagChip(
        text: '在世 ${character.activePets.length} / 共 ${pets.length}',
        color: AppColors.textDim,
      ),
      child: pets.isEmpty
          ? const EmptyHint(text: '还没有养过小动物')
          : Column(
              children: pets.map((Pet pet) {
                final bool dead = pet.status == PetStatus.dead;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: <Widget>[
                      TagChip(
                        text: PetStatusX.label(pet.status),
                        color: dead
                            ? AppColors.textDim
                            : (pet.status == PetStatus.normal
                                ? AppColors.primaryLight
                                : AppColors.warning),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          pet.name,
                          style: TextStyle(
                            color: dead ? AppColors.textDim : AppColors.text,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Text(
                        '${pet.age}/${pet.lifespan} 岁',
                        style: const TextStyle(
                          color: AppColors.textDim,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '健康 ${pet.health} · 亲密 ${pet.intimacy}',
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
    );
  }
}

// ---------------------------------------------------------------------------
// 区块⑦：快捷入口
// ---------------------------------------------------------------------------

class _ShortcutSection extends StatelessWidget {
  final GameProvider game;

  const _ShortcutSection({required this.game});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: '收藏与技能',
      dense: true,
      child: Row(
        children: <Widget>[
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => AchievementPage.open(context),
              icon: const Icon(Icons.emoji_events_outlined, size: 16),
              label: Text('成就 ${game.unlockedCount}/${game.achievementTotal}'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => SkillPage.open(context),
              icon: const Icon(Icons.menu_book_outlined, size: 16),
              label: Text('技能 ${game.learnedSkills.length}/${game.allSkills.length}'),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 区块⑧：操作按钮
// ---------------------------------------------------------------------------

class _ActionSection extends StatelessWidget {
  final GameProvider game;

  const _ActionSection({required this.game});

  @override
  Widget build(BuildContext context) {
    final bool busy = game.hasPendingEvent;
    return SectionCard(
      title: '时间',
      dense: true,
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: busy ? null : () => game.advanceYear(),
                  child: Text(busy ? '请先处理事件' : '过一年'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : () => game.fastForward(10),
                  child: const Text('快进 10 年'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: () => EventPage.open(context),
                  child: const Text('事件一览'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _showLogSheet(context),
                  child: const Text('人生日志'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 人生日志底部弹层
  void _showLogSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => const _LogSheet(),
    );
  }
}

/// 日志弹层内容
class _LogSheet extends StatelessWidget {
  const _LogSheet();

  @override
  Widget build(BuildContext context) {
    final GameProvider game = context.watch<GameProvider>();
    final List<LifeLogEntry> logs = game.recentLogs(limit: 200);
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    '人生日志',
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '共 ${game.character?.logs.length ?? 0} 条',
                  style: const TextStyle(
                    color: AppColors.textDim,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: logs.isEmpty
                ? const Center(
                    child: Text(
                      '还没有记录，过一年试试',
                      style: TextStyle(color: AppColors.textDim, fontSize: 13),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                    itemCount: logs.length,
                    itemBuilder: (BuildContext context, int index) {
                      final LifeLogEntry entry = logs[index];
                      return LogLine(entry: entry);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 单条日志（可复用的公开组件）
// ---------------------------------------------------------------------------

/// 单条日志
class LogLine extends StatelessWidget {
  final LifeLogEntry entry;

  const LogLine({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 40,
            child: Text(
              '${entry.age}岁',
              style: const TextStyle(
                color: AppColors.textDim,
                fontSize: 11.5,
              ),
            ),
          ),
          Expanded(
            child: Text(
              entry.text,
              style: TextStyle(
                color: _color(entry.kind),
                fontSize: 13,
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 日志类型 → 颜色
  Color _color(LogKind kind) {
    switch (kind) {
      case LogKind.good:
        return AppColors.success;
      case LogKind.bad:
        return AppColors.danger;
      case LogKind.system:
        return AppColors.primaryLight;
      case LogKind.money:
        return AppColors.warning;
      case LogKind.normal:
        return AppColors.text;
    }
  }
}
