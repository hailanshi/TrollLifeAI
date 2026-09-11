// 数据加载服务：从 assets/json 读取 5 份剧本数据。
//
// 全部读取都做了容错：某个文件缺失或 JSON 损坏时，
// 该部分返回空列表并记录错误信息，而不是抛异常让 App 崩溃。

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/achievement.dart';
import '../models/city_data.dart';
import '../models/life_event.dart';
import '../models/skill.dart';
import '../models/talent.dart';

/// 一次性打包的剧本数据
class GameDataBundle {
  /// 天赋表
  final List<Talent> talents;

  /// 成就表
  final List<Achievement> achievements;

  /// 技能表
  final List<Skill> skills;

  /// 城市表
  final List<CityData> cities;

  /// 事件表
  final List<LifeEvent> events;

  /// 加载过程中的错误信息（界面可展示，便于排查资源问题）
  final List<String> errors;

  const GameDataBundle({
    required this.talents,
    required this.achievements,
    required this.skills,
    required this.cities,
    required this.events,
    this.errors = const <String>[],
  });

  /// 空数据包（加载失败时的兜底）
  static const GameDataBundle empty = GameDataBundle(
    talents: <Talent>[],
    achievements: <Achievement>[],
    skills: <Skill>[],
    cities: <CityData>[],
    events: <LifeEvent>[],
  );

  /// 数据是否已经加载完整
  bool get isReady => events.isNotEmpty && skills.isNotEmpty;

  /// 按 skillId 建立索引，便于事件标记【习得:xxx】快速查表
  Map<String, Skill> get skillIndex {
    final Map<String, Skill> map = <String, Skill>{};
    for (final Skill s in skills) {
      map[s.skillId] = s;
    }
    return map;
  }

  /// 按城市名建立索引
  Map<String, CityData> get cityIndex {
    final Map<String, CityData> map = <String, CityData>{};
    for (final CityData c in cities) {
      map[c.cityName] = c;
    }
    return map;
  }

  /// 按成就名建立索引
  Map<String, Achievement> get achievementIndex {
    final Map<String, Achievement> map = <String, Achievement>{};
    for (final Achievement a in achievements) {
      map[a.name] = a;
    }
    return map;
  }

  /// 某年代可选的城市
  List<CityData> citiesOfEra(String era) {
    return cities.where((CityData c) => c.availableInEra(era)).toList();
  }
}

/// 剧本数据加载器
class DataLoader {
  const DataLoader._();

  /// 资源根目录
  static const String assetDir = 'assets/json';

  /// 一次性加载全部数据
  static Future<GameDataBundle> loadAll() async {
    final List<String> errors = <String>[];

    final List<Talent> talents = await _loadList<Talent>(
      '$assetDir/talents.json',
      (Map<String, dynamic> json) => Talent.fromJson(json),
      errors,
    );
    final List<Achievement> achievements = await _loadList<Achievement>(
      '$assetDir/achievements.json',
      (Map<String, dynamic> json) => Achievement.fromJson(json),
      errors,
    );
    final List<Skill> skills = await _loadList<Skill>(
      '$assetDir/skills.json',
      (Map<String, dynamic> json) => Skill.fromJson(json),
      errors,
    );
    final List<CityData> cities = await _loadList<CityData>(
      '$assetDir/city.json',
      (Map<String, dynamic> json) => CityData.fromJson(json),
      errors,
    );
    final List<LifeEvent> events = await _loadList<LifeEvent>(
      '$assetDir/event.json',
      (Map<String, dynamic> json) => LifeEvent.fromJson(json),
      errors,
    );

    return GameDataBundle(
      talents: talents,
      achievements: achievements,
      skills: skills,
      cities: cities,
      events: events,
      errors: errors,
    );
  }

  /// 通用列表加载：读取资源 → JSON 解码 → 逐项映射，
  /// 任何一步失败都只记录错误，返回已成功解析的部分。
  static Future<List<T>> _loadList<T>(
    String path,
    T Function(Map<String, dynamic> json) mapper,
    List<String> errors,
  ) async {
    final List<T> out = <T>[];
    try {
      final String raw = await rootBundle.loadString(path);
      final Object? decoded = json.decode(raw);
      if (decoded is! List) {
        errors.add('$path 顶层不是数组，已跳过');
        return out;
      }
      for (final Object? item in decoded) {
        if (item is! Map) continue;
        try {
          out.add(mapper(Map<String, dynamic>.from(item)));
        } catch (e) {
          errors.add('$path 中存在无法解析的条目：$e');
        }
      }
    } catch (e) {
      errors.add('$path 读取失败：$e');
    }
    return out;
  }
}
