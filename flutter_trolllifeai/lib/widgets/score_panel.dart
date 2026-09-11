// 人生评分面板：分数 + 称号 + 「评分明细」。
//
// 轮回页的人生总结卡片与「死亡结算」弹窗共用同一套展示。

import 'package:flutter/material.dart';

import '../services/score_service.dart';
import '../theme/app_theme.dart';
import 'common_widgets.dart';

/// 打开「人生评分明细」弹窗
Future<void> showScoreDetailDialog(BuildContext context, LifeScore score) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: Text('评分明细 · ${score.title.name}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ...score.detail.map(
                (ScoreItem item) => ScoreDetailRow(item: item),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      '总分',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${score.score}',
                    style: const TextStyle(
                      color: AppColors.primaryLight,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '评分 = 年龄 + 属性加权 + 财富资产 + 人际 + 技能 + 成就 + 宠物 '
                '− 压力 / 成瘾 / 罪恶 / 负债。',
                style: TextStyle(
                  color: AppColors.textDim,
                  fontSize: 11.5,
                  height: 1.7,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

/// 单行评分明细
class ScoreDetailRow extends StatelessWidget {
  /// 明细项
  final ScoreItem item;

  const ScoreDetailRow({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final Color color = item.value >= 0 ? AppColors.success : AppColors.danger;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Text(
              item.label,
              style: const TextStyle(color: AppColors.textDim, fontSize: 12.5),
            ),
          ),
          Text(
            '${item.value > 0 ? '+' : ''}${item.value}',
            style: TextStyle(
              color: color,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// 评分面板：大号分数 + 称号 + 明细按钮（可选直接展开明细）
class ScorePanel extends StatelessWidget {
  /// 评分结果
  final LifeScore score;

  /// 是否直接展开明细列表（弹窗里用）
  final bool expandDetail;

  const ScorePanel({
    super.key,
    required this.score,
    this.expandDetail = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Text(
              '${score.score}',
              style: const TextStyle(
                color: AppColors.primaryLight,
                fontSize: 34,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 6),
              child: Text(
                '分',
                style: TextStyle(color: AppColors.textDim, fontSize: 13),
              ),
            ),
            const Spacer(),
            TagChip(text: score.title.name, color: AppColors.epic),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          score.title.desc,
          style: const TextStyle(
            color: AppColors.textDim,
            fontSize: 12.5,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton(
                onPressed: () => showScoreDetailDialog(context, score),
                child: const Text('评分明细'),
              ),
            ),
          ],
        ),
        if (expandDetail) ...<Widget>[
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 8),
          ...score.detail.map((ScoreItem item) => ScoreDetailRow(item: item)),
        ],
      ],
    );
  }
}
