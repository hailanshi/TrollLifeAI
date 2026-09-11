// 天赋模型：开局三选一，attrModify 立即生效。
//
// 数据来源 assets/json/talents.json
// 注意：天赋只有 6 个属性键（智力/体质/魅力/财富/快乐/运气）。

import 'character.dart';

/// 一条天赋
class Talent {
  /// 天赋名，例如「天资聪颖」
  final String name;

  /// 描述文本
  final String desc;

  /// 属性修正（仅 6 项：智力/体质/魅力/财富/快乐/运气）
  final StatDelta attrModify;

  const Talent({
    required this.name,
    required this.desc,
    required this.attrModify,
  });

  /// 从 JSON 解析（容错：字段缺失时使用空值）
  factory Talent.fromJson(Map<String, dynamic> json) {
    return Talent(
      name: (json['name'] ?? '无名天赋').toString(),
      desc: (json['desc'] ?? '').toString(),
      attrModify: StatDelta.fromJson(json['attrModify']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'desc': desc,
        'attrModify': attrModify.toJson(),
      };

  /// 属性修正的可读文本，例如「智力+8 快乐+2」
  String get modifyText => attrModify.toReadable();

  /// 是否为「混合型」天赋（描述里带【混合型】标记，收益与风险并存）
  bool get isMixed => desc.contains('混合型');

  @override
  String toString() => 'Talent($name)';
}
