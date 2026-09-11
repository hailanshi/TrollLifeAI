// 成就模型：自动监听解锁，跨轮回永久保存。
//
// 数据来源 assets/json/achievements.json
// trigger 为解锁条件的文案说明，实际判定逻辑在 services/event_engine.dart。

/// 一个成就
class Achievement {
  /// 成就名，例如「有房一族」
  final String name;

  /// 成就说明
  final String desc;

  /// 解锁条件文案
  final String trigger;

  const Achievement({
    required this.name,
    required this.desc,
    required this.trigger,
  });

  /// 从 JSON 解析（容错）
  factory Achievement.fromJson(Map<String, dynamic> json) {
    return Achievement(
      name: (json['name'] ?? '未命名成就').toString(),
      desc: (json['desc'] ?? '').toString(),
      trigger: (json['trigger'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'desc': desc,
        'trigger': trigger,
      };

  @override
  String toString() => 'Achievement($name)';
}

/// 成就 + 解锁状态（界面用）
class AchievementState {
  /// 成就定义
  final Achievement achievement;

  /// 是否已解锁
  final bool unlocked;

  /// 解锁时的年龄（未解锁为 -1）
  final int unlockedAge;

  /// 解锁时的第几世（未解锁为 -1）
  final int unlockedLife;

  const AchievementState({
    required this.achievement,
    required this.unlocked,
    this.unlockedAge = -1,
    this.unlockedLife = -1,
  });

  /// 成就名（快捷访问）
  String get name => achievement.name;

  @override
  String toString() => 'AchievementState($name,$unlocked)';
}
