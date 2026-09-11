// 人际关系模型：friend / lover / spouse / child / enemy 五类。
//
// 关系由事件标记【关系:friend:小林】创建或加强，
// 由【关系结束:小林】移除；好感度范围 0-100。

/// 关系类型：对应标记里的英文键
enum RelationType {
  friend,
  lover,
  spouse,
  child,
  enemy,
}

/// 关系类型的字符串 ↔ 枚举互转工具
class RelationTypeX {
  const RelationTypeX._();

  /// 枚举 → 标记英文键
  static String toKey(RelationType type) {
    switch (type) {
      case RelationType.friend:
        return 'friend';
      case RelationType.lover:
        return 'lover';
      case RelationType.spouse:
        return 'spouse';
      case RelationType.child:
        return 'child';
      case RelationType.enemy:
        return 'enemy';
    }
  }

  /// 标记英文键 → 枚举，未知键兜底为 friend
  static RelationType fromKey(String key) {
    switch (key.trim().toLowerCase()) {
      case 'friend':
        return RelationType.friend;
      case 'lover':
        return RelationType.lover;
      case 'spouse':
        return RelationType.spouse;
      case 'child':
        return RelationType.child;
      case 'enemy':
        return RelationType.enemy;
      default:
        return RelationType.friend;
    }
  }

  /// 中文显示名
  static String label(RelationType type) {
    switch (type) {
      case RelationType.friend:
        return '朋友';
      case RelationType.lover:
        return '恋人';
      case RelationType.spouse:
        return '配偶';
      case RelationType.child:
        return '子女';
      case RelationType.enemy:
        return '仇人';
    }
  }

  /// 图标（Material 内置图标，避免引入图片资源）
  static int sortWeight(RelationType type) {
    switch (type) {
      case RelationType.spouse:
        return 0;
      case RelationType.child:
        return 1;
      case RelationType.lover:
        return 2;
      case RelationType.friend:
        return 3;
      case RelationType.enemy:
        return 4;
    }
  }
}

/// 一段人际关系
class Relation {
  /// 关系对象的名字，例如「小林」
  String name;

  /// 关系类型
  RelationType type;

  /// 好感度 0-100（仇人同样用这个字段表示敌意强度）
  int favor;

  /// 建立时的年龄（用于「青梅竹马」等成就判定）
  int startAge;

  /// 关系是否仍然存在（关系结束后保留记录但标记失效）
  bool alive;

  /// 最近一次互动时的年龄（每人每年只能互动一次，-1 表示从未互动）
  int lastAct;

  Relation({
    required this.name,
    required this.type,
    this.favor = 50,
    this.startAge = 0,
    this.alive = true,
    this.lastAct = -1,
  });

  /// 从存档 JSON 还原
  factory Relation.fromJson(Map<String, dynamic> json) {
    return Relation(
      name: (json['name'] ?? '某人').toString(),
      type: RelationTypeX.fromKey((json['type'] ?? 'friend').toString()),
      favor: _asInt(json['favor'], 50),
      startAge: _asInt(json['startAge'], 0),
      alive: json['alive'] == null ? true : json['alive'] == true,
      lastAct: _asInt(json['lastAct'], -1),
    );
  }

  /// 序列化为存档 JSON
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'name': name,
      'type': RelationTypeX.toKey(type),
      'favor': favor,
      'startAge': startAge,
      'alive': alive,
      'lastAct': lastAct,
    };
  }

  /// 调整好感度，自动夹在 0-100 之间
  int adjustFavor(int delta) {
    favor = (favor + delta).clamp(0, 100);
    return favor;
  }

  /// 深拷贝（用于快照 / 轮回继承）
  Relation copy() {
    return Relation(
      name: name,
      type: type,
      favor: favor,
      startAge: startAge,
      alive: alive,
    );
  }

  @override
  String toString() => '${RelationTypeX.label(type)}·$name($favor)';
}

/// 容错取整：JSON 里可能是 int / double / String
int _asInt(Object? value, int fallback) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? fallback;
}
