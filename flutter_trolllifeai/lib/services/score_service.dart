// 人生评分与称号（玩法增强层第三节）。
//
// 评分 = 年龄 + 属性加权 + 财富资产 + 人际 + 技能 + 成就 + 宠物
//        − 压力 / 成瘾 / 罪恶 / 负债，下限 0 分。
// 对应网页版 src/js/04_actions.js 的 TL.scoreLife / TL.TITLES。

import '../models/character.dart';
import '../models/relation.dart';

/// 评分明细里的一项（label 说明 + 该项得分）
class ScoreItem {
  /// 明细说明，例如「活到 62 岁」「智力」
  final String label;

  /// 该项得分（已取整，可为负）
  final int value;

  const ScoreItem(this.label, this.value);
}

/// 人生称号
class LifeTitle {
  /// 达到该分数即可获得此称号
  final int min;

  /// 称号名，例如「传奇人生」
  final String name;

  /// 称号说明
  final String desc;

  const LifeTitle(this.min, this.name, this.desc);
}

/// 一次人生评分的结果
class LifeScore {
  /// 总分（≥0）
  final int score;

  /// 称号
  final LifeTitle title;

  /// 明细列表（顺序与公式一致）
  final List<ScoreItem> detail;

  const LifeScore({
    required this.score,
    required this.title,
    required this.detail,
  });

  /// 一句话总结，例如「438 分 · 小有成就」
  String get summary => '$score 分 · ${title.name}';
}

/// 评分服务：纯函数，无状态
class ScoreService {
  const ScoreService._();

  /// 称号区间（从高到低，最后一条兜底）
  static const List<LifeTitle> titles = <LifeTitle>[
    LifeTitle(620, '传奇人生', '后世会把你写进故事里'),
    LifeTitle(520, '人生赢家', '事业、财富、家庭、健康全都拿到了'),
    LifeTitle(420, '小有成就', '这一生过得比大多数人都好'),
    LifeTitle(320, '平凡一生', '普通人的一生，安稳而真实'),
    LifeTitle(220, '碌碌无为', '日子过得有些潦草'),
    LifeTitle(-9999, '悲惨人生', '命运对你并不温柔'),
  ];

  /// 按分数取称号
  static LifeTitle titleOf(int score) {
    for (final LifeTitle item in titles) {
      if (score >= item.min) return item;
    }
    return titles[titles.length - 1];
  }

  /// 计算一世的人生评分
  ///
  /// [achievementCount] 为已解锁成就数（成就跨轮回保留，由 GameProvider 提供）。
  static LifeScore evaluate(Character c, {required int achievementCount}) {
    final List<ScoreItem> detail = <ScoreItem>[];
    double total = 0;

    void add(String label, double value) {
      total += value;
      detail.add(ScoreItem(label, value.round()));
    }

    // ---- 年龄与属性 ----
    add('活到 ${c.age} 岁', c.age * 1.2);
    add('智力', c.attr(AttributeKey.intelligence) * 0.9);
    add('体质', c.attr(AttributeKey.constitution) * 0.7);
    add('魅力', c.attr(AttributeKey.charm) * 0.7);
    add('快乐', c.attr(AttributeKey.happiness) * 0.9);
    add('运气', c.attr(AttributeKey.luck) * 0.6);
    add('健康值', c.attr(AttributeKey.health) * 0.6);
    add('名声值', c.attr(AttributeKey.fame) * 0.8);
    add('压力值', -c.attr(AttributeKey.stress) * 0.5);
    add('成瘾值', -c.attr(AttributeKey.addiction) * 0.7);
    add('罪恶值', -c.attr(AttributeKey.sin) * 1.2);

    // ---- 财富与资产 ----
    final int wealth = c.attr(AttributeKey.wealth);
    final int cappedWealth = wealth < 0 ? 0 : (wealth > 2000000 ? 2000000 : wealth);
    add('财富积累', cappedWealth / 20000);
    add(
      '房产车辆',
      c.assets.properties.length * 10.0 +
          c.assets.vehicles.length * 5.0 +
          c.assets.luxuryCount * 2.0,
    );
    add('负债', -(c.assets.debt / 50000) * 5);

    // ---- 人际 / 技能 / 成就 / 宠物 ----
    int goodRelations = c.countRelation(RelationType.friend);
    goodRelations += c.countRelation(RelationType.lover);
    goodRelations += c.countRelation(RelationType.spouse);
    goodRelations += c.countRelation(RelationType.child);
    add('人际关系', goodRelations * 3.0 - c.enemyCount * 4.0);
    add('技能', c.skills.length * 3.0);
    add('成就', achievementCount * 4.0);
    add('宠物', c.pets.length * 2.0);

    int score = total.round();
    if (score < 0) score = 0;

    return LifeScore(score: score, title: titleOf(score), detail: detail);
  }
}
