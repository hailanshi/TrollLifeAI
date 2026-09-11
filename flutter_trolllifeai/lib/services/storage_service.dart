// 本地存档服务：只用 dart:io，不依赖任何第三方包。
//
// 目录选择顺序（全部失败则降级为内存存档，绝不抛异常到界面）：
//   1. 环境变量 TROLLLIFE_HOME
//   2. 当前工作目录下的 .trolllife/（桌面端可用）
//   3. 系统临时目录下的 trolllife/
//
// 存档内容：
//   save.json         本局 + 全局进度（含成就解锁状态）
//   achievements.json 成就解锁状态（单独一份，便于跨轮回保留）

import 'dart:convert';
import 'dart:io';

/// 一条成就的持久化记录
class AchievementRecord {
  /// 成就名
  final String name;

  /// 解锁时的年龄
  final int age;

  /// 解锁时的第几世（从 1 开始）
  final int life;

  const AchievementRecord({
    required this.name,
    this.age = -1,
    this.life = 1,
  });

  factory AchievementRecord.fromJson(Map<String, dynamic> json) {
    return AchievementRecord(
      name: (json['name'] ?? '').toString(),
      age: _toInt(json['age'], -1),
      life: _toInt(json['life'], 1),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'age': age,
        'life': life,
      };
}

/// 全局存档快照（不直接依赖 models，避免循环引用）
class SaveSnapshot {
  /// 当前局（角色的 toJson 结果），没有进行中的局时为空
  final Map<String, dynamic> character;

  /// 成就解锁记录
  final List<AchievementRecord> achievements;

  /// 已经历的世数
  final int generation;

  /// 上一世的继承属性（11 项）
  final Map<String, dynamic> inherited;

  /// 存档版本，便于以后兼容处理
  final int version;

  const SaveSnapshot({
    this.character = const <String, dynamic>{},
    this.achievements = const <AchievementRecord>[],
    this.generation = 0,
    this.inherited = const <String, dynamic>{},
    this.version = 1,
  });

  factory SaveSnapshot.fromJson(Map<String, dynamic> json) {
    final List<AchievementRecord> achievements = <AchievementRecord>[];
    final Object? rawAch = json['achievements'];
    if (rawAch is List) {
      for (final Object? item in rawAch) {
        if (item is Map) {
          achievements.add(
            AchievementRecord.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    return SaveSnapshot(
      character: json['character'] is Map
          ? Map<String, dynamic>.from(json['character'] as Map)
          : const <String, dynamic>{},
      achievements: achievements,
      generation: _toInt(json['generation']),
      inherited: json['inherited'] is Map
          ? Map<String, dynamic>.from(json['inherited'] as Map)
          : const <String, dynamic>{},
      version: _toInt(json['version'], 1),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': version,
        'generation': generation,
        'character': character,
        'inherited': inherited,
        'achievements':
            achievements.map((AchievementRecord e) => e.toJson()).toList(),
      };

  /// 空快照
  static const SaveSnapshot empty = SaveSnapshot();
}

/// 存档服务
class StorageService {
  /// 实际使用的存档目录（null 表示已降级为内存存档）
  Directory? _dir;

  /// 内存兜底存档
  SaveSnapshot _memory = SaveSnapshot.empty;

  /// 额外小文件（AI 配置 / 3 个存档槽位）的内存兜底内容
  final Map<String, String> _extraMemory = <String, String>{};

  /// 是否处于「仅内存」降级状态
  bool get memoryOnly => _dir == null;

  /// 当前存档目录的可读路径（界面展示用）
  String get storagePath {
    final Directory? dir = _dir;
    if (dir == null) return '内存（未能写入磁盘）';
    return '${dir.path}${Platform.pathSeparator}save.json';
  }

  /// 初始化：依次尝试各个候选目录，并做一次写测试。
  Future<void> init() async {
    final List<Directory> candidates = _candidateDirs();
    for (final Directory dir in candidates) {
      try {
        if (!dir.existsSync()) {
          dir.createSync(recursive: true);
        }
        // 写测试，确认真的可写
        final File probe =
            File('${dir.path}${Platform.pathSeparator}.probe');
        probe.writeAsStringSync('ok');
        probe.deleteSync();
        _dir = dir;
        return;
      } catch (_) {
        // 换下一个候选目录
        continue;
      }
    }
    _dir = null;
  }

  /// 候选目录列表
  List<Directory> _candidateDirs() {
    final List<Directory> list = <Directory>[];
    final String sep = Platform.pathSeparator;

    // 1. 环境变量优先（便于测试与自定义）
    try {
      final String env = Platform.environment['TROLLLIFE_HOME'] ?? '';
      if (env.trim().isNotEmpty) {
        list.add(Directory(env.trim()));
      }
    } catch (_) {
      // 某些平台读取环境变量可能失败，忽略
    }

    // 2. 当前工作目录
    try {
      list.add(Directory('${Directory.current.path}${sep}.trolllife'));
    } catch (_) {
      // 忽略
    }

    // 3. 系统临时目录
    try {
      list.add(Directory('${Directory.systemTemp.path}${sep}trolllife'));
    } catch (_) {
      // 忽略
    }

    return list;
  }

  /// 读取存档；失败返回空快照（不会抛异常）
  Future<SaveSnapshot> load() async {
    final Directory? dir = _dir;
    if (dir == null) return _memory;
    try {
      final File file = File('${dir.path}${Platform.pathSeparator}save.json');
      if (!file.existsSync()) return SaveSnapshot.empty;
      final String raw = await file.readAsString();
      if (raw.trim().isEmpty) return SaveSnapshot.empty;
      final Object? decoded = json.decode(raw);
      if (decoded is! Map) return SaveSnapshot.empty;
      return SaveSnapshot.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return SaveSnapshot.empty;
    }
  }

  /// 写入存档；失败自动降级为内存存档
  Future<void> save(SaveSnapshot snapshot) async {
    _memory = snapshot;
    final Directory? dir = _dir;
    if (dir == null) return;
    try {
      final File file = File('${dir.path}${Platform.pathSeparator}save.json');
      await file.writeAsString(json.encode(snapshot.toJson()));
    } catch (_) {
      // 磁盘写入失败：清空 _dir，后续全部走内存
      _dir = null;
    }
  }

  /// 清除存档文件
  Future<void> clear() async {
    _memory = SaveSnapshot.empty;
    final Directory? dir = _dir;
    if (dir == null) return;
    try {
      final File file = File('${dir.path}${Platform.pathSeparator}save.json');
      if (file.existsSync()) file.deleteSync();
    } catch (_) {
      // 忽略删除失败
    }
  }

  /// 单独导出成就记录（跨轮回永久保存的第二份保险）
  Future<void> saveAchievements(List<AchievementRecord> records) async {
    final Directory? dir = _dir;
    if (dir == null) return;
    try {
      final File file =
          File('${dir.path}${Platform.pathSeparator}achievements.json');
      await file.writeAsString(
        json.encode(records.map((AchievementRecord e) => e.toJson()).toList()),
      );
    } catch (_) {
      // 忽略
    }
  }

  /// 读取成就记录
  Future<List<AchievementRecord>> loadAchievements() async {
    final Directory? dir = _dir;
    if (dir == null) return const <AchievementRecord>[];
    try {
      final File file =
          File('${dir.path}${Platform.pathSeparator}achievements.json');
      if (!file.existsSync()) return const <AchievementRecord>[];
      final String raw = await file.readAsString();
      final Object? decoded = json.decode(raw);
      if (decoded is! List) return const <AchievementRecord>[];
      final List<AchievementRecord> out = <AchievementRecord>[];
      for (final Object? item in decoded) {
        if (item is Map) {
          out.add(AchievementRecord.fromJson(Map<String, dynamic>.from(item)));
        }
      }
      return out;
    } catch (_) {
      return const <AchievementRecord>[];
    }
  }

  // ---------------------------------------------------------------------
  // 额外小文件（AI 配置 / 存档槽位）
  //
  // 与 save.json 共用同一个存档目录，同样是「磁盘优先、失败降级为内存」。
  // ---------------------------------------------------------------------

  /// 槽位文件名，例如 slot_1.json
  static String slotFileName(int index) {
    return 'slot_$index.json';
  }

  /// 额外文件的完整路径说明（界面展示用）
  String extraFilePath(String name) {
    final Directory? dir = _dir;
    if (dir == null) return '内存（未能写入磁盘）';
    return '${dir.path}${Platform.pathSeparator}$name';
  }

  /// 额外文件是否已经存在
  bool hasExtraFile(String name) {
    final Directory? dir = _dir;
    if (dir == null) return _extraMemory.containsKey(name);
    try {
      return File('${dir.path}${Platform.pathSeparator}$name').existsSync();
    } catch (_) {
      return false;
    }
  }

  /// 读取额外文件文本；不存在或失败返回 null
  Future<String?> readExtraFile(String name) async {
    final Directory? dir = _dir;
    if (dir == null) return _extraMemory[name];
    try {
      final File file = File('${dir.path}${Platform.pathSeparator}$name');
      if (!file.existsSync()) return _extraMemory[name];
      return await file.readAsString();
    } catch (_) {
      return _extraMemory[name];
    }
  }

  /// 写入额外文件文本；磁盘不可写时只写内存并返回 false
  Future<bool> writeExtraFile(String name, String content) async {
    _extraMemory[name] = content;
    final Directory? dir = _dir;
    if (dir == null) return false;
    try {
      final File file = File('${dir.path}${Platform.pathSeparator}$name');
      await file.writeAsString(content);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 删除额外文件（内存里的副本一并清掉）
  Future<void> deleteExtraFile(String name) async {
    _extraMemory.remove(name);
    final Directory? dir = _dir;
    if (dir == null) return;
    try {
      final File file = File('${dir.path}${Platform.pathSeparator}$name');
      if (file.existsSync()) file.deleteSync();
    } catch (_) {
      // 忽略删除失败
    }
  }

  /// 写入一个存档槽位（pack 建议为 {savedAt, version, snapshot}）
  Future<bool> writeSlot(int index, Map<String, dynamic> pack) {
    return writeExtraFile(slotFileName(index), json.encode(pack));
  }

  /// 读取一个槽位的原始 JSON；不存在或损坏返回 null
  Future<Map<String, dynamic>?> readSlot(int index) async {
    final String? raw = await readExtraFile(slotFileName(index));
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final Object? decoded = json.decode(raw);
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
  }

  /// 删除一个存档槽位
  Future<void> deleteSlotFile(int index) {
    return deleteExtraFile(slotFileName(index));
  }

  /// 槽位摘要（轮回页展示「槽位 1 · 存活 32 岁 · 00年代 · 小县城」）
  Future<SaveSlotInfo> slotInfo(int index) async {
    final Map<String, dynamic>? pack = await readSlot(index);
    if (pack == null) {
      return SaveSlotInfo(index: index, empty: true);
    }
    final Object? rawSnapshot = pack['snapshot'];
    Map<String, dynamic> snapshot = <String, dynamic>{};
    if (rawSnapshot is Map) {
      snapshot = Map<String, dynamic>.from(rawSnapshot);
    }
    final Object? rawCharacter = snapshot['character'];
    Map<String, dynamic> character = <String, dynamic>{};
    if (rawCharacter is Map) {
      character = Map<String, dynamic>.from(rawCharacter);
    }
    if (character.isEmpty) {
      return SaveSlotInfo(index: index, empty: true);
    }
    return SaveSlotInfo(
      index: index,
      empty: false,
      name: (character['name'] ?? '无名氏').toString(),
      age: _toInt(character['age']),
      era: (character['era'] ?? '').toString(),
      city: (character['cityName'] ?? '').toString(),
      alive: (character['status'] ?? 'alive').toString() != 'dead',
      savedAt: _toInt(pack['savedAt']),
    );
  }
}

/// 存档槽位摘要（只在轮回页展示用，不参与游戏逻辑）
class SaveSlotInfo {
  /// 槽位编号（从 1 开始）
  final int index;

  /// 是否为空槽位
  final bool empty;

  /// 角色姓名
  final String name;

  /// 存档时年龄
  final int age;

  /// 出生年代键
  final String era;

  /// 城市名
  final String city;

  /// 存档时角色是否存活
  final bool alive;

  /// 保存时间（毫秒时间戳，0 表示未知）
  final int savedAt;

  const SaveSlotInfo({
    required this.index,
    this.empty = true,
    this.name = '',
    this.age = 0,
    this.era = '',
    this.city = '',
    this.alive = true,
    this.savedAt = 0,
  });

  /// 保存时间文本，例如 2024-05-01 12:30；未知时返回空串
  String get savedAtText {
    if (savedAt <= 0) return '';
    final DateTime time = DateTime.fromMillisecondsSinceEpoch(savedAt);
    final String month = time.month < 10 ? '0${time.month}' : '${time.month}';
    final String day = time.day < 10 ? '0${time.day}' : '${time.day}';
    final String hour = time.hour < 10 ? '0${time.hour}' : '${time.hour}';
    final String minute =
        time.minute < 10 ? '0${time.minute}' : '${time.minute}';
    return '${time.year}-$month-$day $hour:$minute';
  }

  /// 槽位摘要文案
  String get label {
    if (empty) return '空槽位';
    final String state = alive ? '存活' : '已结束';
    return '$state $age 岁 · $name · $city';
  }
}

/// 容错取整
int _toInt(Object? value, [int fallback = 0]) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? fallback;
}
