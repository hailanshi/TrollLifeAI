// 宠物模型：完整生命周期（幼年 → 成年 → 老年 → 离世）。
//
// 事件标记【宠物:猫】/【宠物:狗】创建宠物，
// 【宠物生病】【宠物走失】【宠物繁育】【宠物离世】推进生命周期。

/// 宠物当前状态
enum PetStatus {
  /// 正常陪伴
  normal,

  /// 走失（可能被找回，也不排除永久失去）
  lost,

  /// 生病中（每年消耗医疗费，健康恢复后回到 normal）
  sick,

  /// 已离世（保留记录，用于成就与日志回忆）
  dead,
}

/// 宠物状态字符串 ↔ 枚举工具
class PetStatusX {
  const PetStatusX._();

  static String toKey(PetStatus status) {
    switch (status) {
      case PetStatus.normal:
        return 'normal';
      case PetStatus.lost:
        return 'lost';
      case PetStatus.sick:
        return 'sick';
      case PetStatus.dead:
        return 'dead';
    }
  }

  static PetStatus fromKey(String key) {
    switch (key.trim().toLowerCase()) {
      case 'lost':
        return PetStatus.lost;
      case 'sick':
        return PetStatus.sick;
      case 'dead':
        return PetStatus.dead;
      default:
        return PetStatus.normal;
    }
  }

  static String label(PetStatus status) {
    switch (status) {
      case PetStatus.normal:
        return '健康';
      case PetStatus.lost:
        return '走失';
      case PetStatus.sick:
        return '生病';
      case PetStatus.dead:
        return '已离世';
    }
  }
}

/// 一只宠物
class Pet {
  /// 名字（品种 + 序号，例如「猫·团子」）
  String name;

  /// 物种：猫 / 狗 / 其他（标记里出现的任意词）
  String species;

  /// 当前年龄（岁）
  int age;

  /// 预计寿命（猫狗约 12-18 年，受技能 pet_care 影响）
  int lifespan;

  /// 状态
  PetStatus status;

  /// 亲密度 0-100
  int intimacy;

  /// 是否已绝育 / 是否繁育过后代（用于「毛孩子满堂」成就）
  bool hasOffspring;

  /// 健康度 0-100（主动行动「陪伴宠物」可以提升）
  int health;

  Pet({
    required this.name,
    this.species = '猫',
    this.age = 0,
    this.lifespan = 15,
    this.status = PetStatus.normal,
    this.intimacy = 60,
    this.hasOffspring = false,
    this.health = 100,
  });

  factory Pet.fromJson(Map<String, dynamic> json) {
    return Pet(
      name: (json['name'] ?? '小家伙').toString(),
      species: (json['species'] ?? '猫').toString(),
      age: _toInt(json['age'], 0),
      lifespan: _toInt(json['lifespan'], 15),
      status: PetStatusX.fromKey((json['status'] ?? 'normal').toString()),
      intimacy: _toInt(json['intimacy'], 60),
      hasOffspring: json['hasOffspring'] == true,
      health: _toInt(json['health'], 100),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'name': name,
      'species': species,
      'age': age,
      'lifespan': lifespan,
      'status': PetStatusX.toKey(status),
      'intimacy': intimacy,
      'hasOffspring': hasOffspring,
      'health': health,
    };
  }

  /// 是否还在世且陪伴中
  bool get isAlive => status != PetStatus.dead;

  /// 调整亲密度，夹在 0-100
  int adjustIntimacy(int delta) {
    intimacy = (intimacy + delta).clamp(0, 100);
    return intimacy;
  }

  /// 调整健康度，夹在 0-100
  int adjustHealth(int delta) {
    health = (health + delta).clamp(0, 100);
    return health;
  }

  /// 深拷贝
  Pet copy() {
    return Pet(
      name: name,
      species: species,
      age: age,
      lifespan: lifespan,
      status: status,
      intimacy: intimacy,
      hasOffspring: hasOffspring,
      health: health,
    );
  }

  @override
  String toString() => '$name(${PetStatusX.label(status)},${age}岁)';
}

/// 容错取整
int _toInt(Object? value, int fallback) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? fallback;
}
