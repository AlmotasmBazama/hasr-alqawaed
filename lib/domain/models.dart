class FoundationModel {
  const FoundationModel({
    required this.id,
    required this.name,
    required this.length,
    required this.width,
    required this.height,
    required this.concretePerFoundation,
    required this.steel14BarsPerFoundation,
    required this.steel14BarsPerQuintal,
    required this.steel8BarsPerFoundation,
    required this.steel8BarsPerQuintal,
  });

  static const builtIn = FoundationModel(
    id: 'builtin-foundation-1',
    name: 'نموذج 1',
    length: 1.2,
    width: 1.2,
    height: 0.5,
    concretePerFoundation: 0.75,
    steel14BarsPerFoundation: 3.5,
    steel14BarsPerQuintal: 6.5,
    steel8BarsPerFoundation: 1,
    steel8BarsPerQuintal: 20,
  );

  final String id;
  final String name;
  final double length;
  final double width;
  final double height;
  final double concretePerFoundation;
  final double steel14BarsPerFoundation;
  final double steel14BarsPerQuintal;
  final double steel8BarsPerFoundation;
  final double steel8BarsPerQuintal;

  bool get isBuiltIn => id == builtIn.id;

  bool get isValid =>
      id.trim().isNotEmpty &&
      name.trim().isNotEmpty &&
      [
        length,
        width,
        height,
        steel14BarsPerQuintal,
        steel8BarsPerQuintal,
      ].every((value) => value.isFinite && value > 0) &&
      [
        concretePerFoundation,
        steel14BarsPerFoundation,
        steel8BarsPerFoundation,
      ].every((value) => value.isFinite && value >= 0);

  FoundationModel copyWith({
    String? id,
    String? name,
    double? length,
    double? width,
    double? height,
    double? concretePerFoundation,
    double? steel14BarsPerFoundation,
    double? steel14BarsPerQuintal,
    double? steel8BarsPerFoundation,
    double? steel8BarsPerQuintal,
  }) => FoundationModel(
    id: id ?? this.id,
    name: name ?? this.name,
    length: length ?? this.length,
    width: width ?? this.width,
    height: height ?? this.height,
    concretePerFoundation: concretePerFoundation ?? this.concretePerFoundation,
    steel14BarsPerFoundation:
        steel14BarsPerFoundation ?? this.steel14BarsPerFoundation,
    steel14BarsPerQuintal: steel14BarsPerQuintal ?? this.steel14BarsPerQuintal,
    steel8BarsPerFoundation:
        steel8BarsPerFoundation ?? this.steel8BarsPerFoundation,
    steel8BarsPerQuintal: steel8BarsPerQuintal ?? this.steel8BarsPerQuintal,
  );

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'length': length,
    'width': width,
    'height': height,
    'concretePerFoundation': concretePerFoundation,
    'steel14BarsPerFoundation': steel14BarsPerFoundation,
    'steel14BarsPerQuintal': steel14BarsPerQuintal,
    'steel8BarsPerFoundation': steel8BarsPerFoundation,
    'steel8BarsPerQuintal': steel8BarsPerQuintal,
  };

  factory FoundationModel.fromJson(Map<String, dynamic> json) {
    final model = FoundationModel(
      id: _string(json, 'id'),
      name: _string(json, 'name').trim(),
      length: _number(json, 'length'),
      width: _number(json, 'width'),
      height: _number(json, 'height'),
      concretePerFoundation: _number(json, 'concretePerFoundation'),
      steel14BarsPerFoundation: _number(json, 'steel14BarsPerFoundation'),
      steel14BarsPerQuintal: _number(json, 'steel14BarsPerQuintal'),
      steel8BarsPerFoundation: _number(json, 'steel8BarsPerFoundation'),
      steel8BarsPerQuintal: _number(json, 'steel8BarsPerQuintal'),
    );
    if (!model.isValid) throw const FormatException('Invalid foundation model');
    return model;
  }
}

class Prices {
  const Prices({
    required this.concrete,
    required this.steel14,
    required this.steel8,
    required this.carpenter,
    required this.steelWorker,
    required this.casting,
  });

  static const defaults = Prices(
    concrete: 560,
    steel14: 520,
    steel8: 600,
    carpenter: 70,
    steelWorker: 30,
    casting: 60,
  );

  final double concrete;
  final double steel14;
  final double steel8;
  final double carpenter;
  final double steelWorker;
  final double casting;

  List<double> get values => [
    concrete,
    steel14,
    steel8,
    carpenter,
    steelWorker,
    casting,
  ];
  bool get isValid => values.every((value) => value.isFinite && value >= 0);

  Prices copyWith({
    double? concrete,
    double? steel14,
    double? steel8,
    double? carpenter,
    double? steelWorker,
    double? casting,
  }) => Prices(
    concrete: concrete ?? this.concrete,
    steel14: steel14 ?? this.steel14,
    steel8: steel8 ?? this.steel8,
    carpenter: carpenter ?? this.carpenter,
    steelWorker: steelWorker ?? this.steelWorker,
    casting: casting ?? this.casting,
  );

  Map<String, Object> toJson() => {
    'concrete': concrete,
    'steel14': steel14,
    'steel8': steel8,
    'carpenter': carpenter,
    'steelWorker': steelWorker,
    'casting': casting,
  };

  factory Prices.fromJson(Map<String, dynamic> json) {
    final prices = Prices(
      concrete: _number(json, 'concrete'),
      steel14: _number(json, 'steel14'),
      steel8: _number(json, 'steel8'),
      carpenter: _number(json, 'carpenter'),
      steelWorker: _number(json, 'steelWorker'),
      casting: _number(json, 'casting'),
    );
    if (!prices.isValid) throw const FormatException('Invalid prices');
    return prices;
  }
}

class CalculatorInputs {
  const CalculatorInputs({required this.count, required this.prices});
  static const defaults = CalculatorInputs(count: 20, prices: Prices.defaults);

  final int count;
  final Prices prices;
  bool get isValid => count > 0 && count <= 9007199254740991 && prices.isValid;
  CalculatorInputs copyWith({int? count, Prices? prices}) => CalculatorInputs(
    count: count ?? this.count,
    prices: prices ?? this.prices,
  );

  Map<String, Object> toJson() => {'count': count, 'prices': prices.toJson()};
  factory CalculatorInputs.fromJson(Map<String, dynamic> json) {
    if (json['count'] is! int) throw const FormatException('Invalid count');
    final inputs = CalculatorInputs(
      count: json['count'] as int,
      prices: Prices.fromJson(_map(json['prices'])),
    );
    if (!inputs.isValid) throw const FormatException('Invalid inputs');
    return inputs;
  }
}

class AppData {
  AppData({
    List<FoundationModel> customModels = const [],
    this.selectedModelId = 'builtin-foundation-1',
    this.inputs = CalculatorInputs.defaults,
  }) : customModels = List.unmodifiable(customModels);

  static const schemaVersion = 1;
  final List<FoundationModel> customModels;
  final String selectedModelId;
  final CalculatorInputs inputs;
  List<FoundationModel> get models => [
    FoundationModel.builtIn,
    ...customModels,
  ];
  FoundationModel get selectedModel => models.firstWhere(
    (model) => model.id == selectedModelId,
    orElse: () => FoundationModel.builtIn,
  );

  AppData copyWith({
    List<FoundationModel>? customModels,
    String? selectedModelId,
    CalculatorInputs? inputs,
  }) => AppData(
    customModels: customModels ?? this.customModels,
    selectedModelId: selectedModelId ?? this.selectedModelId,
    inputs: inputs ?? this.inputs,
  );

  AppData selectModel(String id) {
    if (!models.any((model) => model.id == id)) {
      throw ArgumentError.value(id, 'id', 'Unknown model');
    }
    return copyWith(selectedModelId: id);
  }

  /// Replaces by identity; the bundled model cannot be replaced.
  AppData upsertModel(FoundationModel model, {bool select = true}) {
    if (!model.isValid || model.isBuiltIn) {
      throw ArgumentError('Cannot save an invalid or built-in model');
    }
    final models = [...customModels];
    final index = models.indexWhere((item) => item.id == model.id);
    if (index < 0) {
      models.add(model);
    } else {
      models[index] = model;
    }
    return copyWith(
      customModels: models,
      selectedModelId: select ? model.id : selectedModelId,
    );
  }

  Map<String, Object> toJson() => {
    'version': schemaVersion,
    'customModels': customModels.map((model) => model.toJson()).toList(),
    'selectedModelId': selectedModelId,
    'inputs': inputs.toJson(),
  };

  factory AppData.fromJson(Map<String, dynamic> json) {
    if (json['version'] != schemaVersion) {
      throw const FormatException('Unsupported data version');
    }
    if (json['customModels'] is! List) {
      throw const FormatException('Invalid custom models');
    }
    final models = (json['customModels'] as List)
        .map((item) => FoundationModel.fromJson(_map(item)))
        .toList();
    final ids = <String>{};
    for (final model in models) {
      if (model.isBuiltIn || !ids.add(model.id)) {
        throw const FormatException('Duplicate or built-in custom model');
      }
    }
    final selected = _string(json, 'selectedModelId');
    return AppData(
      customModels: models,
      selectedModelId:
          selected == FoundationModel.builtIn.id || ids.contains(selected)
          ? selected
          : FoundationModel.builtIn.id,
      inputs: CalculatorInputs.fromJson(_map(json['inputs'])),
    );
  }
}

double _number(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! num || !value.isFinite) throw FormatException('Invalid $key');
  return value.toDouble();
}

String _string(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! String) throw FormatException('Invalid $key');
  return value;
}

Map<String, dynamic> _map(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Invalid object');
  }
  return value;
}
