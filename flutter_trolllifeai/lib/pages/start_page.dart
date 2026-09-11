// 开局页：选年代 → 选城市 → 抽天赋（3 选 1，可重抽）。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/character.dart';
import '../models/city_data.dart';
import '../models/life_event.dart';
import '../models/talent.dart';
import '../providers/game_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

/// 开局页
class StartPage extends StatefulWidget {
  const StartPage({super.key});

  @override
  State<StartPage> createState() => _StartPageState();
}

class _StartPageState extends State<StartPage> {
  /// 当前选中的天赋（点「开始新的一生」时才真正生效）
  Talent? _pickedTalent;

  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    // 首次进入自动抽一次天赋，省一次点击
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final GameProvider game = context.read<GameProvider>();
      if (game.talentCandidates.isEmpty) {
        game.drawTalents();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final GameProvider game = context.watch<GameProvider>();
    final List<CityData> cities = game.availableCities;

    // 年代切换后清掉已选天赋与已选城市，强制玩家重新确认
    if (_pickedTalent != null &&
        !(game.talentCandidates.contains(_pickedTalent))) {
      _pickedTalent = null;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                children: <Widget>[
                  _buildHeader(game),
                  _buildEraSection(game),
                  _buildCitySection(game, cities),
                  _buildTalentSection(game),
                  _buildTipSection(game),
                ],
              ),
            ),
            _buildBottomBar(game, cities),
          ],
        ),
      ),
    );
  }

  /// 顶部标题
  Widget _buildHeader(GameProvider game) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              const Text(
                'TrollLifeAI',
                style: TextStyle(
                  color: AppColors.primaryLight,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '第 ${game.generation} 世',
                  style: const TextStyle(
                    color: AppColors.textDim,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '人生重开模拟器 · 选一个时代，重新活一次',
            style: TextStyle(color: AppColors.textDim, fontSize: 13),
          ),
          if (game.inheritedAttributes.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            _buildInheritanceHint(game),
          ],
        ],
      ),
    );
  }

  /// 前世继承提示
  Widget _buildInheritanceHint(GameProvider game) {
    final List<Widget> chips = <Widget>[];
    game.inheritedAttributes.forEach((AttributeKey key, int value) {
      if (value == 0) return;
      chips.add(
        DeltaChip(label: AttributeKeyX.shortLabel(key), value: value),
      );
    });
    if (chips.isEmpty) return const SizedBox.shrink();
    return SectionCard(
      title: '前世继承（按上一世的 8% 折算）',
      dense: true,
      child: Wrap(spacing: 6, runSpacing: 6, children: chips),
    );
  }

  /// 年代选择
  Widget _buildEraSection(GameProvider game) {
    return SectionCard(
      title: '第一步 · 选择年代',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: game.eras.map((String era) {
              final bool selected = game.selectedEra == era;
              return GestureDetector(
                onTap: () {
                  setState(() => _pickedTalent = null);
                  game.selectEra(era);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
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
                    game.eraLabel(era),
                    style: TextStyle(
                      color: selected ? AppColors.primaryLight : AppColors.text,
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          Text(
            game.eraDesc(game.selectedEra),
            style: const TextStyle(
              color: AppColors.textDim,
              fontSize: 13,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '该年代专属事件：共 ${_eraEventCount(game)} 条',
            style: const TextStyle(color: AppColors.textDim, fontSize: 12),
          ),
        ],
      ),
    );
  }

  /// 统计当前年代的专属事件数量
  int _eraEventCount(GameProvider game) {
    final List<LifeEvent> events = game.data.events;
    return events
        .where((LifeEvent e) => e.eraLimit.contains(game.selectedEra))
        .length;
  }

  /// 城市选择
  Widget _buildCitySection(GameProvider game, List<CityData> cities) {
    return SectionCard(
      title: '第二步 · 选择城市',
      trailing: TagChip(
        text: '${cities.length} 座可选',
        color: AppColors.textDim,
      ),
      child: cities.isEmpty
          ? const EmptyHint(text: '这个年代没有可选城市，请重新选择年代')
          : Column(
              children: cities.map((CityData city) {
                final bool selected = game.selectedCity?.cityName == city.cityName;
                return GestureDetector(
                  onTap: () => game.selectCity(city),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.primary.withAlpha(40)
                          : AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color:
                            selected ? AppColors.primaryLight : AppColors.divider,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                city.cityName,
                                style: TextStyle(
                                  color: selected
                                      ? AppColors.primaryLight
                                      : AppColors.text,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            TagChip(
                              text: '压力 ${city.stressEffect >= 0 ? '+' : ''}${city.stressEffect}',
                              color: city.stressEffect > 0
                                  ? AppColors.danger
                                  : AppColors.success,
                            ),
                            const SizedBox(width: 6),
                            TagChip(
                              text: '上限 ${formatMoney(city.wealthCap)}',
                              color: AppColors.warning,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          city.desc,
                          style: const TextStyle(
                            color: AppColors.textDim,
                            fontSize: 12.5,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
    );
  }

  /// 天赋抽取
  Widget _buildTalentSection(GameProvider game) {
    final List<Talent> candidates = game.talentCandidates;
    return SectionCard(
      title: '第三步 · 抽天赋（3 选 1）',
      trailing: TextButton(
        onPressed: game.rerollLeft > 0
            ? () {
                setState(() => _pickedTalent = null);
                game.rerollTalents();
              }
            : null,
        child: Text(
          '重抽（剩 ${game.rerollLeft} 次）',
          style: TextStyle(
            fontSize: 12.5,
            color: game.rerollLeft > 0
                ? AppColors.primaryLight
                : AppColors.textDim,
          ),
        ),
      ),
      child: candidates.isEmpty
          ? const EmptyHint(text: '暂无天赋数据，请检查 assets/json/talents.json')
          : Column(
              children: candidates.map((Talent talent) {
                final bool selected = _pickedTalent?.name == talent.name;
                return GestureDetector(
                  onTap: () => setState(() => _pickedTalent = talent),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.epic.withAlpha(36)
                          : AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected ? AppColors.epic : AppColors.divider,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Icon(
                              selected
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                              size: 16,
                              color: selected
                                  ? AppColors.epic
                                  : AppColors.textDim,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                talent.name,
                                style: TextStyle(
                                  color: selected
                                      ? AppColors.text
                                      : AppColors.text,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (talent.isMixed)
                              const TagChip(
                                text: '混合型',
                                color: AppColors.warning,
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          talent.desc,
                          style: const TextStyle(
                            color: AppColors.textDim,
                            fontSize: 12.5,
                            height: 1.5,
                          ),
                        ),
                        if (talent.modifyText.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: _talentChips(talent),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
    );
  }

  /// 天赋的属性标签
  List<Widget> _talentChips(Talent talent) {
    final List<Widget> chips = <Widget>[];
    talent.attrModify.values.forEach((AttributeKey key, int value) {
      if (value == 0) return;
      chips.add(
        DeltaChip(
          label: AttributeKeyX.shortLabel(key),
          value: value,
          isMoney: key == AttributeKey.wealth,
        ),
      );
    });
    return chips;
  }

  /// 底部提示
  Widget _buildTipSection(GameProvider game) {
    return SectionCard(
      title: '说明',
      dense: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '· 初始属性：11 项从 50 起（财富 0、健康 70、压力 20、快乐 60）\n'
            '· 城市压力会每年修正压力值，财富上限 = 30 万 × 城市系数\n'
            '· 技能永久生效，命中事件关键词每个 +7% 成功率，最高 +35%\n'
            '· 罪恶值 ≥45 可能被捕入狱，成瘾值 ≥60 可能成瘾发作\n'
            '· 死亡后可转世，继承智力/体质/魅力/运气的 8%，成就永久保留',
            style: TextStyle(
              color: AppColors.textDim,
              fontSize: 12.5,
              height: 1.7,
            ),
          ),
          if (game.loadError.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              '数据加载提醒：${game.loadError}',
              style: const TextStyle(color: AppColors.danger, fontSize: 12),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Icon(
                game.isMemoryOnly ? Icons.warning_amber : Icons.save_outlined,
                size: 14,
                color: game.isMemoryOnly
                    ? AppColors.warning
                    : AppColors.textDim,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  game.isMemoryOnly
                      ? '存档降级为内存：本次进度在退出后会丢失'
                      : '存档位置：${game.storagePath}',
                  style: TextStyle(
                    color: game.isMemoryOnly
                        ? AppColors.warning
                        : AppColors.textDim,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 底部启动栏
  Widget _buildBottomBar(GameProvider game, List<CityData> cities) {
    final bool ready = _pickedTalent != null && game.selectedCity != null;
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
                  onPressed: game.unlockedCount > 0
                      ? () {
                          showDialog<void>(
                            context: context,
                            builder: (BuildContext context) =>
                                _buildResetDialog(context, game),
                          );
                        }
                      : null,
                  child: Text(
                    game.unlockedCount > 0
                        ? '清空存档（成就 ${game.unlockedCount}）'
                        : '暂无存档',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: ready
                      ? () {
                          final Talent? talent = _pickedTalent;
                          if (talent == null) return;
                          game.startNewGame(talent);
                        }
                      : null,
                  child: Text(
                    ready
                        ? '开始新的一生'
                        : (cities.isEmpty ? '请先选择年代' : '请选择城市与天赋'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 清空存档确认框
  Widget _buildResetDialog(BuildContext context, GameProvider game) {
    return AlertDialog(
      title: const Text('清空存档'),
      content: Text(
        '会删除当前进度与全部成就记录（当前已解锁 ${game.unlockedCount} 项），此操作不可撤销。',
        style: const TextStyle(fontSize: 13.5, height: 1.6),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            game.resetAll();
          },
          child: const Text('确认清空'),
        ),
      ],
    );
  }
}
