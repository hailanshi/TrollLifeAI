// 城市模型：按年代可用性筛选，提供压力修正与财富上限系数。
//
// 数据来源 assets/json/city.json

/// 一座城市
class CityData {
  /// 城市名，例如「北上广深」
  final String cityName;

  /// 年代可用性：键为 '80' / '90' / '00' / '10' / '20'
  final Map<String, bool> eraFactor;

  /// 城市描述
  final String desc;

  /// 每年压力修正
  final int stressEffect;

  /// 财富上限系数（财富上限 = 300000 × 系数）
  final double wealthCapFactor;

  const CityData({
    required this.cityName,
    required this.eraFactor,
    required this.desc,
    required this.stressEffect,
    required this.wealthCapFactor,
  });

  /// 从 JSON 解析（容错：eraFactor / attrEffect 缺失时给默认值）
  factory CityData.fromJson(Map<String, dynamic> json) {
    final Map<String, bool> era = <String, bool>{
      '80': false,
      '90': false,
      '00': false,
      '10': false,
      '20': false,
    };
    final Object? rawEra = json['eraFactor'];
    if (rawEra is Map) {
      rawEra.forEach((Object? key, Object? value) {
        if (key == null) return;
        era[key.toString()] = value == true;
      });
    }

    int stress = 0;
    double cap = 1.0;
    final Object? rawEffect = json['attrEffect'];
    if (rawEffect is Map) {
      stress = _toInt(rawEffect['压力值']);
      cap = _toDouble(rawEffect['财富上限'], 1.0);
    }

    return CityData(
      cityName: (json['cityName'] ?? '未知城市').toString(),
      eraFactor: era,
      desc: (json['desc'] ?? '').toString(),
      stressEffect: stress,
      wealthCapFactor: cap,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'cityName': cityName,
        'eraFactor': eraFactor,
        'desc': desc,
        'attrEffect': <String, dynamic>{
          '压力值': stressEffect,
          '财富上限': wealthCapFactor,
        },
      };

  /// 某个年代是否可选这座城
  bool availableInEra(String era) => eraFactor[era] == true;

  /// 财富上限（元）
  int get wealthCap => (300000 * wealthCapFactor).round();

  @override
  String toString() => 'CityData($cityName)';
}

/// 容错取整
int _toInt(Object? value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}

/// 容错取小数
double _toDouble(Object? value, double fallback) {
  if (value == null) return fallback;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? fallback;
}
