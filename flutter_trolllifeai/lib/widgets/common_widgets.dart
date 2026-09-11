// 复用小组件集合：属性条、卡片、属性变化提示、标签、空状态。
//
// 所有页面都从这里取组件，保证视觉一致。

import 'package:flutter/material.dart';

import '../models/character.dart';
import '../theme/app_theme.dart';

/// 带标题的卡片面板
class SectionCard extends StatelessWidget {
  /// 标题（可为空）
  final String title;

  /// 标题右侧的小控件（例如计数、按钮）
  final Widget? trailing;

  /// 内容
  final Widget child;

  /// 是否使用更紧凑的内边距
  final bool dense;

  const SectionCard({
    super.key,
    this.title = '',
    this.trailing,
    required this.child,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final EdgeInsets padding =
        dense ? const EdgeInsets.all(12) : const EdgeInsets.all(14);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 3,
                    height: 14,
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
          child,
        ],
      ),
    );
  }
}

/// 属性条：名称 + 进度条 + 数值
class AttributeBar extends StatelessWidget {
  /// 属性名（短名）
  final String label;

  /// 当前值
  final int value;

  /// 进度条最大值（默认 100）
  final int maxValue;

  /// 数字后面追加的单位 / 说明
  final String suffix;

  /// 是否显示为金额（财富用）
  final bool isMoney;

  /// 变化提示（例如 +3），为空则不显示
  final int? delta;

  const AttributeBar({
    super.key,
    required this.label,
    required this.value,
    this.maxValue = 100,
    this.suffix = '',
    this.isMoney = false,
    this.delta,
  });

  @override
  Widget build(BuildContext context) {
    final double ratio = maxValue <= 0
        ? 0
        : (value / maxValue).clamp(0.0, 1.0).toDouble();
    final Color barColor = _barColor(label, value);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              SizedBox(
                width: 44,
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textDim,
                    fontSize: 13,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  isMoney ? formatMoney(value) : '$value$suffix',
                  style: TextStyle(
                    color: AppTheme.valueColor(value),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (delta != null && delta != 0)
                Text(
                  '${delta! > 0 ? '+' : ''}${isMoney ? formatMoney(delta!) : delta}',
                  style: TextStyle(
                    color: delta! > 0 ? AppColors.success : AppColors.danger,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 4,
              backgroundColor: AppColors.divider,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
        ],
      ),
    );
  }

  /// 不同属性用不同颜色，方便一眼分辨好坏
  Color _barColor(String label, int value) {
    switch (label) {
      case '健康':
        return value <= 30 ? AppColors.danger : AppColors.primaryLight;
      case '压力':
        return value >= 70 ? AppColors.danger : AppColors.warning;
      case '成瘾':
      case '罪恶':
        return value >= 60 ? AppColors.danger : AppColors.warning;
      case '财富':
        return AppColors.warning;
      default:
        return AppColors.primaryLight;
    }
  }
}

/// 属性变化提示条：把「智力+3 体质-2」渲染成彩色小标签
class DeltaChips extends StatelessWidget {
  /// 变化量
  final StatDelta delta;

  const DeltaChips({super.key, required this.delta});

  @override
  Widget build(BuildContext context) {
    final List<Widget> chips = <Widget>[];
    for (final AttributeKey key in AttributeKeyX.all) {
      final int v = delta.get(key);
      if (v == 0) continue;
      chips.add(
        DeltaChip(
          label: AttributeKeyX.shortLabel(key),
          value: v,
          isMoney: key == AttributeKey.wealth,
        ),
      );
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 6, runSpacing: 6, children: chips);
  }
}

/// 单个变化标签
class DeltaChip extends StatelessWidget {
  /// 名称
  final String label;

  /// 变化值
  final int value;

  /// 是否按金额格式化
  final bool isMoney;

  const DeltaChip({
    super.key,
    required this.label,
    required this.value,
    this.isMoney = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool up = value > 0;
    final Color color = up ? AppColors.success : AppColors.danger;
    final String text = isMoney
        ? '$label${up ? '+' : '-'}${formatMoney(value.abs())}'
        : '$label${up ? '+' : ''}$value';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// 小标签（年代、城市、类型等）
class TagChip extends StatelessWidget {
  /// 文本
  final String text;

  /// 颜色
  final Color color;

  /// 图标
  final IconData? icon;

  const TagChip({
    super.key,
    required this.text,
    this.color = AppColors.primaryLight,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(text, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}

/// 空状态提示
class EmptyHint extends StatelessWidget {
  /// 提示文本
  final String text;

  const EmptyHint({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(color: AppColors.textDim, fontSize: 13),
        ),
      ),
    );
  }
}

/// 标签行：左边说明，右边数值
class InfoRow extends StatelessWidget {
  /// 左侧说明
  final String label;

  /// 右侧内容
  final Widget value;

  const InfoRow({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.textDim, fontSize: 13),
            ),
          ),
          Expanded(child: value),
        ],
      ),
    );
  }
}

/// 金额格式化：12345 → 1.23万
String formatMoney(int amount) {
  final int abs = amount.abs();
  final String sign = amount < 0 ? '-' : '';
  if (abs >= 100000000) {
    return '$sign${(abs / 100000000).toStringAsFixed(2)}亿';
  }
  if (abs >= 10000) {
    return '$sign${(abs / 10000).toStringAsFixed(2)}万';
  }
  return '$sign$abs';
}
