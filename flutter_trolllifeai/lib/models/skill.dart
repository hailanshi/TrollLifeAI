// 技能模型：学会后永久生效，每个命中的技能给事件成功率 +7%，最高 +35%。
//
// 数据来源 assets/json/skills.json

/// 一个技能
class Skill {
  /// 技能 id（事件标记【习得:programming】用的就是它）
  final String skillId;

  /// 技能中文名，例如「编程」
  final String name;

  /// 技能说明
  final String desc;

  /// 效果描述
  final String effect;

  const Skill({
    required this.skillId,
    required this.name,
    required this.desc,
    required this.effect,
  });

  /// 从 JSON 解析（容错）
  factory Skill.fromJson(Map<String, dynamic> json) {
    return Skill(
      skillId: (json['skillId'] ?? '').toString(),
      name: (json['name'] ?? '未知技能').toString(),
      desc: (json['desc'] ?? '').toString(),
      effect: (json['effect'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'skillId': skillId,
        'name': name,
        'desc': desc,
        'effect': effect,
      };

  @override
  String toString() => 'Skill($skillId/$name)';
}
