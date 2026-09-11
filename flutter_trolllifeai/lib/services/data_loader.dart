// 数据加载服务：从 assets/json 读取剧本数据（5 份剧本 + 1 份剧情规则表）。
//
// 全部读取都做了容错：某个文件缺失或 JSON 损坏时，
// 该部分返回空列表 / 空规则并记录错误信息，而不是抛异常让 App 崩溃。

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/achievement.dart';
import '../models/age_rule.dart';
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

  /// 剧情逻辑规则表（年龄纠偏 + 前提校验），来自 assets/json/age_rules.json。
  /// 资源缺失时为 AgeRuleSet.empty：不纠偏、不校验，游戏仍可正常进行。
  final AgeRuleSet ageRules;

  /// 加载过程中的错误信息（界面可展示，便于排查资源问题）
  final List<String> errors;

  const GameDataBundle({
    required this.talents,
    required this.achievements,
    required this.skills,
    required this.cities,
    required this.events,
    this.ageRules = AgeRuleSet.empty,
    this.errors = const <String>[],
  });

  /// 空数据包（加载失败时的兜底）
  static const GameDataBundle empty = GameDataBundle(
    talents: <Talent>[],
    achievements: <Achievement>[],
    skills: <Skill>[],
    cities: <CityData>[],
    events: <LifeEvent>[],
    ageRules: AgeRuleSet.empty,
  );

  /// 数据是否已经加载完整
  bool get isReady => events.isNotEmpty && skills.isNotEmpty;

  /// 规则表是否可用
  bool get hasAgeRules => !ageRules.isEmpty;

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

    // 剧情逻辑规则表：缺失 / 损坏时退回空规则（不纠偏、不校验），不影响其他数据
    final AgeRuleSet ageRules = await _loadAgeRules(
      '$assetDir/age_rules.json',
      errors,
    );

    return GameDataBundle(
      talents: talents,
      achievements: achievements,
      skills: skills,
      cities: cities,
      events: events,
      ageRules: ageRules,
      errors: errors,
    );
  }

  /// 加载剧情逻辑规则表（age_rules.json）。
  /// 文件不存在或格式异常时返回 [AgeRuleSet.empty] 并记录错误，绝不抛异常。
  ///
  /// 注意：源文件带 UTF-8 BOM（与网页版共用同一份），
  /// 这里先剥掉 BOM 再交给 json.decode，避免部分 Dart 版本解析失败。
  static Future<AgeRuleSet> _loadAgeRules(
    String path,
    List<String> errors,
  ) async {
    try {
      final String raw = await rootBundle.loadString(path);
      final String cleaned = _stripBom(raw);
      final Object? decoded = json.decode(cleaned);
      if (decoded is! Map) {
        errors.add('$path 顶层不是对象，已忽略年龄/前提规则');
        return AgeRuleSet.empty;
      }
      final AgeRuleSet rules =
          AgeRuleSet.fromJson(Map<String, dynamic>.from(decoded));
      if (rules.isEmpty) {
        errors.add('$path 中没有可用的 ageRules / preconditions');
      }
      return rules;
    } catch (e) {
      errors.add('$path 读取失败（已退回空规则）：$e');
      return AgeRuleSet.empty;
    }
  }

  /// 去掉 UTF-8 BOM 头（\uFEFF），保证 json.decode 在任意版本都能解析
  static String _stripBom(String text) {
    if (text.isEmpty) return text;
    if (text.codeUnitAt(0) == 0xFEFF) {
      return text.substring(1);
    }
    return text;
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
