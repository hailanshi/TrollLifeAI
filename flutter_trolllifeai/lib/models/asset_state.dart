// 资产与负债状态：财富、负债、房产、车辆、奢侈品、保险。
//
// 城市 attrEffect.财富上限 决定「财富上限 = 300000 × 系数」，
// 资产状态本身只负责记录与计算净值，不做上限裁剪（裁剪在事件引擎里做）。

/// 一份房产
class PropertyAsset {
  /// 城市名 / 房产描述
  String cityName;

  /// 购入价格
  int price;

  /// 当前估值
  int value;

  /// 购入时的年龄
  int boughtAge;

  PropertyAsset({
    required this.cityName,
    required this.price,
    required this.value,
    required this.boughtAge,
  });

  factory PropertyAsset.fromJson(Map<String, dynamic> json) {
    return PropertyAsset(
      cityName: (json['cityName'] ?? '某处').toString(),
      price: _toInt(json['price']),
      value: _toInt(json['value']),
      boughtAge: _toInt(json['boughtAge']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'cityName': cityName,
        'price': price,
        'value': value,
        'boughtAge': boughtAge,
      };
}

/// 一辆车
class VehicleAsset {
  /// 车辆描述，例如「家用轿车」
  String label;

  /// 购入价格
  int price;

  /// 当前估值
  int value;

  /// 购入时的年龄
  int boughtAge;

  VehicleAsset({
    required this.label,
    required this.price,
    required this.value,
    required this.boughtAge,
  });

  factory VehicleAsset.fromJson(Map<String, dynamic> json) {
    return VehicleAsset(
      label: (json['label'] ?? '一辆车').toString(),
      price: _toInt(json['price']),
      value: _toInt(json['value']),
      boughtAge: _toInt(json['boughtAge']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'label': label,
        'price': price,
        'value': value,
        'boughtAge': boughtAge,
      };
}

/// 资产状态汇总
class AssetState {
  /// 现金 / 存款（可以为负，负值会被计入负债一并展示）
  int cash;

  /// 负债总额（恒 ≥ 0）
  int debt;

  /// 房产列表
  List<PropertyAsset> properties;

  /// 车辆列表
  List<VehicleAsset> vehicles;

  /// 奢侈品总花费（只做记录）
  int luxurySpent;

  /// 奢侈品件数（人生评分里按件数加分）
  int luxuryCount;

  /// 是否买过保险
  bool hasInsurance;

  /// 保险剩余有效年数
  int insuranceYears;

  /// 理财累计收益（用于「理财达人」成就）
  int investProfit;

  /// 是否曾经负债 ≥ 50000（用于「无债一身轻」成就）
  bool everDebtOver50k;

  AssetState({
    this.cash = 0,
    this.debt = 0,
    List<PropertyAsset>? properties,
    List<VehicleAsset>? vehicles,
    this.luxurySpent = 0,
    this.luxuryCount = 0,
    this.hasInsurance = false,
    this.insuranceYears = 0,
    this.investProfit = 0,
    this.everDebtOver50k = false,
  })  : properties = properties ?? <PropertyAsset>[],
        vehicles = vehicles ?? <VehicleAsset>[];

  factory AssetState.fromJson(Map<String, dynamic> json) {
    final List<PropertyAsset> props = <PropertyAsset>[];
    final Object? rawProps = json['properties'];
    if (rawProps is List) {
      for (final Object? item in rawProps) {
        if (item is Map) {
          props.add(PropertyAsset.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    final List<VehicleAsset> cars = <VehicleAsset>[];
    final Object? rawCars = json['vehicles'];
    if (rawCars is List) {
      for (final Object? item in rawCars) {
        if (item is Map) {
          cars.add(VehicleAsset.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return AssetState(
      cash: _toInt(json['cash']),
      debt: _toInt(json['debt']),
      properties: props,
      vehicles: cars,
      luxurySpent: _toInt(json['luxurySpent']),
      luxuryCount: _toInt(json['luxuryCount']),
      hasInsurance: json['hasInsurance'] == true,
      insuranceYears: _toInt(json['insuranceYears']),
      investProfit: _toInt(json['investProfit']),
      everDebtOver50k: json['everDebtOver50k'] == true,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'cash': cash,
        'debt': debt,
        'properties': properties.map((PropertyAsset e) => e.toJson()).toList(),
        'vehicles': vehicles.map((VehicleAsset e) => e.toJson()).toList(),
        'luxurySpent': luxurySpent,
        'luxuryCount': luxuryCount,
        'hasInsurance': hasInsurance,
        'insuranceYears': insuranceYears,
        'investProfit': investProfit,
        'everDebtOver50k': everDebtOver50k,
      };

  /// 存款是否为正
  bool get hasPositiveCash => cash > 0;

  /// 房产总值
  int get propertyValue =>
      properties.fold(0, (int sum, PropertyAsset e) => sum + e.value);

  /// 车辆总值
  int get vehicleValue =>
      vehicles.fold(0, (int sum, VehicleAsset e) => sum + e.value);

  /// 总资产（现金 + 房产 + 车辆）
  int get totalAsset => cash + propertyValue + vehicleValue;

  /// 净值（总资产 - 负债）
  int get netWorth => totalAsset - debt;

  /// 增加现金，同时记录「曾经负债超 5 万」标记
  void addCash(int delta) {
    cash += delta;
  }

  /// 增加负债（恒 ≥ 0）
  void addDebt(int delta) {
    debt += delta;
    if (debt < 0) debt = 0;
    if (debt >= 50000) everDebtOver50k = true;
  }

  /// 还债：优先扣现金，不足部分仍然减少负债（外部保证不超支）
  int repay(int amount) {
    final int pay = amount < 0 ? 0 : amount;
    cash -= pay;
    debt -= pay;
    if (debt < 0) {
      // 多还的部分退回现金
      cash += -debt;
      debt = 0;
    }
    return pay;
  }

  /// 深拷贝
  AssetState copy() {
    return AssetState(
      cash: cash,
      debt: debt,
      properties: properties
          .map((PropertyAsset e) => PropertyAsset.fromJson(e.toJson()))
          .toList(),
      vehicles: vehicles
          .map((VehicleAsset e) => VehicleAsset.fromJson(e.toJson()))
          .toList(),
      luxurySpent: luxurySpent,
      luxuryCount: luxuryCount,
      hasInsurance: hasInsurance,
      insuranceYears: insuranceYears,
      investProfit: investProfit,
      everDebtOver50k: everDebtOver50k,
    );
  }
}

/// 容错取整
int _toInt(Object? value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}
