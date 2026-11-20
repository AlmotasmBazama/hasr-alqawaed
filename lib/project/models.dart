/// Project estimates retain their model and prices as immutable snapshots.
enum QuantityUnit {
  foundation('قاعدة', 'قاعدة'),
  column('عمود', 'عمود'),
  linear('متر طولي', 'م طولي'),
  area('متر مربع', 'م²'),
  volume('متر مكعب', 'م³'),
  quintal('قنطار', 'قنطار'),
  block('بلوكة', 'بلوكة'),
  bag('كيس', 'كيس'),
  bar('سيخ', 'سيخ'),
  item('وحدة', 'وحدة');

  const QuantityUnit(this.label, this.shortLabel);
  final String label;
  final String shortLabel;
}

/// Identifies the measured input that feeds a row, separately from both units.
enum QuantitySource {
  workQuantity('مقدار العمل'),
  roofArea('مساحة السقف'),
  roofBeamLength('أطوال كمرات السقف');

  const QuantitySource(this.label);
  final String label;
}

enum WorkKind {
  foundations('القواعد', QuantityUnit.foundation),
  belowMasonry('مباني تحت الكتينة', QuantityUnit.linear),
  tieBeam('الميدة', QuantityUnit.linear),
  leanSlab('الكرسنة', QuantityUnit.area),
  columns('الأعمدة', QuantityUnit.column),
  aboveMasonry('مباني فوق الكتينة', QuantityUnit.linear),
  roof('السقف', QuantityUnit.area);

  const WorkKind(this.label, this.defaultUnit);
  final String label;
  final QuantityUnit defaultUnit;
  bool get integerQuantity => this == foundations || this == columns;
  bool get isMasonry => this == belowMasonry || this == aboveMasonry;
}

class MaterialDefinition {
  const MaterialDefinition({
    required this.id,
    required this.label,
    required this.specification,
    required this.unit,
    required this.defaultPrice,
  });
  final String id;
  final String label;
  final String specification;
  final QuantityUnit unit;
  final double defaultPrice;
  String get aggregateKey => '$id|$specification|${unit.name}';
}

const _unchanged = Object();
bool validNonnegative(double value) => value.isFinite && value >= 0;
const maxProfitPercentage = 1000000.0;
bool validProfitPercentage(double value) =>
    validNonnegative(value) && value <= maxProfitPercentage;

class ModelRow {
  const ModelRow({
    required this.id,
    required this.label,
    this.materialId,
    required this.unit,
    this.sourceUnit,
    this.quantitySource = QuantitySource.workQuantity,
    required this.coefficient,
    this.divisor = 1,
    required this.defaultPrice,
    this.reviewBasis = false,
  });
  final String id;
  final String label;
  final String? materialId;
  final QuantityUnit unit;
  final QuantityUnit? sourceUnit;
  final QuantitySource quantitySource;
  final double coefficient;
  final double divisor;
  final double defaultPrice;
  final bool reviewBasis;
  bool get isMaterial => materialId != null;
  bool get isValid =>
      id.trim().isNotEmpty &&
      label.trim().isNotEmpty &&
      (materialId == null || materialId!.isNotEmpty) &&
      validNonnegative(coefficient) &&
      divisor.isFinite &&
      divisor > 0 &&
      validNonnegative(defaultPrice);
  ModelRow copyWith({
    String? id,
    String? label,
    Object? materialId = _unchanged,
    QuantityUnit? unit,
    Object? sourceUnit = _unchanged,
    QuantitySource? quantitySource,
    double? coefficient,
    double? divisor,
    double? defaultPrice,
    bool? reviewBasis,
  }) => ModelRow(
    id: id ?? this.id,
    label: label ?? this.label,
    materialId: identical(materialId, _unchanged)
        ? this.materialId
        : materialId as String?,
    unit: unit ?? this.unit,
    sourceUnit: identical(sourceUnit, _unchanged)
        ? this.sourceUnit
        : sourceUnit as QuantityUnit?,
    quantitySource: quantitySource ?? this.quantitySource,
    coefficient: coefficient ?? this.coefficient,
    divisor: divisor ?? this.divisor,
    defaultPrice: defaultPrice ?? this.defaultPrice,
    reviewBasis: reviewBasis ?? this.reviewBasis,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'materialId': materialId,
    'unit': unit.name,
    'sourceUnit': sourceUnit?.name,
    'quantitySource': quantitySource.name,
    'coefficient': coefficient,
    'divisor': divisor,
    'defaultPrice': defaultPrice,
    'reviewBasis': reviewBasis,
  };
  factory ModelRow.fromJson(Map<String, dynamic> json) {
    final row = ModelRow(
      id: _string(json, 'id'),
      label: _string(json, 'label'),
      materialId: json['materialId'] as String?,
      unit: QuantityUnit.values.byName(_string(json, 'unit')),
      sourceUnit: json['sourceUnit'] == null
          ? null
          : QuantityUnit.values.byName(_string(json, 'sourceUnit')),
      quantitySource: json.containsKey('quantitySource')
          ? QuantitySource.values.byName(_string(json, 'quantitySource'))
          : QuantitySource.workQuantity,
      coefficient: _number(json, 'coefficient'),
      divisor: _number(json, 'divisor'),
      defaultPrice: _number(json, 'defaultPrice'),
      reviewBasis: _bool(json, 'reviewBasis'),
    );
    if (!row.isValid) throw const FormatException('Invalid model row');
    return row;
  }
}

class WorkModel {
  WorkModel({
    required this.id,
    required this.kind,
    required this.name,
    this.description = '',
    required this.inputUnit,
    required List<ModelRow> rows,
  }) : rows = List.unmodifiable(rows);
  final String id;
  final WorkKind kind;
  final String name;
  final String description;
  final QuantityUnit inputUnit;
  final List<ModelRow> rows;
  bool get isBuiltIn => id.startsWith('builtin-');
  bool get requiresRoofBeamLength =>
      rows.any((row) => row.quantitySource != QuantitySource.workQuantity);
  bool get isValid =>
      id.trim().isNotEmpty &&
      name.trim().isNotEmpty &&
      rows.isNotEmpty &&
      rows.every(
        (row) =>
            row.isValid &&
            (row.quantitySource == QuantitySource.workQuantity ||
                kind == WorkKind.roof && inputUnit == QuantityUnit.area),
      ) &&
      rows.map((row) => row.id).toSet().length == rows.length &&
      (kind == WorkKind.roof || inputUnit == kind.defaultUnit);
  WorkModel copyWith({
    String? id,
    WorkKind? kind,
    String? name,
    String? description,
    QuantityUnit? inputUnit,
    List<ModelRow>? rows,
  }) => WorkModel(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    name: name ?? this.name,
    description: description ?? this.description,
    inputUnit: inputUnit ?? this.inputUnit,
    rows: rows ?? this.rows,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'name': name,
    'description': description,
    'inputUnit': inputUnit.name,
    'rows': rows.map((row) => row.toJson()).toList(),
  };
  factory WorkModel.fromJson(Map<String, dynamic> json) {
    final model = WorkModel(
      id: _string(json, 'id'),
      kind: WorkKind.values.byName(_string(json, 'kind')),
      name: _string(json, 'name'),
      description: _string(json, 'description'),
      inputUnit: QuantityUnit.values.byName(_string(json, 'inputUnit')),
      rows: _list(
        json,
        'rows',
      ).map((row) => ModelRow.fromJson(jsonMap(row))).toList(),
    );
    if (!model.isValid) throw const FormatException('Invalid work model');
    return model;
  }
}

String servicePriceKey(WorkKind kind, ModelRow row) =>
    '${kind.name}|${row.id}|${row.unit.name}';

class WorkEntry {
  WorkEntry({
    required this.kind,
    required this.included,
    bool? explicitlyExcluded,
    this.quantity,
    this.linkedToTieBeam = false,
    this.roofBeamLength,
    this.model,
    Map<String, double?> priceOverrides = const {},
  }) : explicitlyExcluded = explicitlyExcluded ?? !included,
       priceOverrides = Map.unmodifiable(priceOverrides);
  final WorkKind kind;
  final bool included;
  final bool explicitlyExcluded;
  final double? quantity;
  final bool linkedToTieBeam;
  final double? roofBeamLength;
  final WorkModel? model;
  final Map<String, double?> priceOverrides;
  QuantityUnit get inputUnit => model?.inputUnit ?? kind.defaultUnit;
  bool get requiresRoofBeamLength => model?.requiresRoofBeamLength ?? false;
  double? quantityFor(QuantitySource source) => switch (source) {
    QuantitySource.workQuantity || QuantitySource.roofArea => quantity,
    QuantitySource.roofBeamLength => roofBeamLength,
  };
  QuantityUnit unitFor(QuantitySource source) => switch (source) {
    QuantitySource.workQuantity => inputUnit,
    QuantitySource.roofArea => QuantityUnit.area,
    QuantitySource.roofBeamLength => QuantityUnit.linear,
  };
  bool get quantityValid =>
      quantity != null &&
      validNonnegative(quantity!) &&
      (!kind.integerQuantity ||
          (quantity! <= 9007199254740991 &&
              quantity! == quantity!.truncateToDouble()));
  WorkEntry copyWith({
    bool? included,
    bool? explicitlyExcluded,
    Object? quantity = _unchanged,
    bool? linkedToTieBeam,
    Object? roofBeamLength = _unchanged,
    Object? model = _unchanged,
    Map<String, double?>? priceOverrides,
  }) => WorkEntry(
    kind: kind,
    included: included ?? this.included,
    explicitlyExcluded:
        explicitlyExcluded ??
        (included == null ? this.explicitlyExcluded : !included),
    quantity: identical(quantity, _unchanged)
        ? this.quantity
        : (quantity as num?)?.toDouble(),
    linkedToTieBeam: linkedToTieBeam ?? this.linkedToTieBeam,
    roofBeamLength: identical(roofBeamLength, _unchanged)
        ? this.roofBeamLength
        : (roofBeamLength as num?)?.toDouble(),
    model: identical(model, _unchanged) ? this.model : model as WorkModel?,
    priceOverrides: priceOverrides ?? this.priceOverrides,
  );
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'included': included,
    'explicitlyExcluded': explicitlyExcluded,
    'quantity': quantity,
    if (kind.isMasonry) 'linkedToTieBeam': linkedToTieBeam,
    'roofBeamLength': roofBeamLength,
    'model': model?.toJson(),
    'priceOverrides': priceOverrides,
  };
  factory WorkEntry.fromJson(Map<String, dynamic> json) {
    final entry = WorkEntry(
      kind: WorkKind.values.byName(_string(json, 'kind')),
      included: _bool(json, 'included'),
      explicitlyExcluded: json.containsKey('explicitlyExcluded')
          ? _bool(json, 'explicitlyExcluded')
          : null,
      quantity: _nullableNumber(json['quantity']),
      // Previous projects and their saved quotations used independent lengths.
      linkedToTieBeam: json.containsKey('linkedToTieBeam')
          ? _bool(json, 'linkedToTieBeam')
          : false,
      roofBeamLength: _nullableNumber(json['roofBeamLength']),
      model: json['model'] == null
          ? null
          : WorkModel.fromJson(jsonMap(json['model'])),
      priceOverrides: _prices(json['priceOverrides']),
    );
    if ((entry.quantity != null && !entry.quantityValid) ||
        (entry.included && entry.explicitlyExcluded) ||
        (entry.linkedToTieBeam && !entry.kind.isMasonry) ||
        (entry.kind != WorkKind.roof && entry.roofBeamLength != null) ||
        (entry.model != null && entry.model!.kind != entry.kind)) {
      throw const FormatException('Invalid work entry');
    }
    return entry;
  }
}

class Project {
  Project({
    required this.id,
    required this.name,
    required this.date,
    this.location = '',
    required List<WorkEntry> works,
    required Map<String, double?> materialPrices,
    Map<String, double?> servicePrices = const {},
    this.isExample = false,
    this.profitPercentage = 0,
    Map<String, String> inputDrafts = const {},
    this.calculatedProject,
    this.calculationStale = false,
  }) : works = List.unmodifiable(works),
       materialPrices = Map.unmodifiable(materialPrices),
       servicePrices = Map.unmodifiable(servicePrices),
       inputDrafts = Map.unmodifiable(inputDrafts);
  final String id;
  final String name;
  final String date;
  final String location;
  final List<WorkEntry> works;
  final Map<String, double?> materialPrices;
  final Map<String, double?> servicePrices;
  final bool isExample;
  final double? profitPercentage;

  /// Invalid or unfinished input can never silently revert to an earlier value
  /// when this project is reopened. Keep it apart from the last valid value.
  final Map<String, String> inputDrafts;

  /// Original, normalized inputs taken at the last explicit calculation.
  /// Nested calculation snapshots are disallowed when saved or restored.
  final Project? calculatedProject;
  final bool calculationStale;
  WorkEntry work(WorkKind kind) =>
      works.firstWhere((entry) => entry.kind == kind);

  double? effectiveQuantity(WorkKind kind) {
    final source = work(kind).linkedToTieBeam ? WorkKind.tieBeam : kind;
    if (inputDrafts.containsKey('quantity:${source.name}')) return null;
    return work(source).quantity;
  }

  Project updateWork(WorkEntry entry) => copyWith(
    works: [for (final item in works) item.kind == entry.kind ? entry : item],
  );
  Project copyWith({
    String? id,
    String? name,
    String? date,
    String? location,
    List<WorkEntry>? works,
    Map<String, double?>? materialPrices,
    Map<String, double?>? servicePrices,
    bool? isExample,
    Object? profitPercentage = _unchanged,
    Map<String, String>? inputDrafts,
    Object? calculatedProject = _unchanged,
    bool? calculationStale,
  }) => Project(
    id: id ?? this.id,
    name: name ?? this.name,
    date: date ?? this.date,
    location: location ?? this.location,
    works: works ?? this.works,
    materialPrices: materialPrices ?? this.materialPrices,
    servicePrices: servicePrices ?? this.servicePrices,
    isExample: isExample ?? this.isExample,
    profitPercentage: identical(profitPercentage, _unchanged)
        ? this.profitPercentage
        : (profitPercentage as num?)?.toDouble(),
    inputDrafts: inputDrafts ?? this.inputDrafts,
    calculatedProject: identical(calculatedProject, _unchanged)
        ? this.calculatedProject
        : calculatedProject as Project?,
    calculationStale: calculationStale ?? this.calculationStale,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'date': date,
    'location': location,
    'works': works.map((work) => work.toJson()).toList(),
    'materialPrices': materialPrices,
    'servicePrices': servicePrices,
    'isExample': isExample,
    'profitPercentage': profitPercentage,
    'inputDrafts': inputDrafts,
    'calculatedProject': calculatedProject?.toJson(),
    'calculationStale': calculationStale,
  };
  factory Project.fromJson(Map<String, dynamic> json) {
    final snapshot = json['calculatedProject'] == null
        ? null
        : jsonMap(json['calculatedProject']);
    if (snapshot?['calculatedProject'] != null) {
      throw const FormatException('Nested calculation snapshot');
    }
    final project = Project(
      id: _string(json, 'id'),
      name: _string(json, 'name'),
      date: _string(json, 'date'),
      location: _string(json, 'location'),
      works: _list(
        json,
        'works',
      ).map((work) => WorkEntry.fromJson(jsonMap(work))).toList(),
      materialPrices: _prices(json['materialPrices']),
      servicePrices: _prices(json['servicePrices']),
      isExample: _bool(json, 'isExample'),
      profitPercentage: json.containsKey('profitPercentage')
          ? _nullableNumber(json['profitPercentage'])
          : 0,
      inputDrafts: json.containsKey('inputDrafts')
          ? jsonMap(json['inputDrafts']).map((key, value) {
              if (value is! String) {
                throw const FormatException('Invalid draft');
              }
              return MapEntry(key, value);
            })
          : const {},
      calculatedProject: snapshot == null ? null : Project.fromJson(snapshot),
      calculationStale: json.containsKey('calculationStale')
          ? _bool(json, 'calculationStale')
          : false,
    );
    if (project.id.trim().isEmpty ||
        project.name.trim().isEmpty ||
        DateTime.tryParse(project.date) == null ||
        (project.profitPercentage != null &&
            !validProfitPercentage(project.profitPercentage!)) ||
        (project.calculationStale && project.calculatedProject == null) ||
        (project.calculatedProject != null &&
            (project.calculatedProject!.id != project.id ||
                project.calculatedProject!.inputDrafts.isNotEmpty)) ||
        project.works.length != WorkKind.values.length ||
        project.works.map((work) => work.kind).toSet().length !=
            WorkKind.values.length) {
      throw const FormatException('Invalid project');
    }
    return project;
  }
}

class ProjectState {
  ProjectState({
    required List<Project> projects,
    required this.currentProjectId,
    List<WorkModel> customModels = const [],
  }) : projects = List.unmodifiable(projects),
       customModels = List.unmodifiable(customModels);
  static const schemaVersion = 3;
  final List<Project> projects;
  final String currentProjectId;
  final List<WorkModel> customModels;
  Project get currentProject =>
      projects.firstWhere((project) => project.id == currentProjectId);
  ProjectState copyWith({
    List<Project>? projects,
    String? currentProjectId,
    List<WorkModel>? customModels,
  }) => ProjectState(
    projects: projects ?? this.projects,
    currentProjectId: currentProjectId ?? this.currentProjectId,
    customModels: customModels ?? this.customModels,
  );
  ProjectState updateProject(Project project) {
    final exists = projects.any((item) => item.id == project.id);
    return copyWith(
      projects: [
        for (final item in projects) item.id == project.id ? project : item,
        if (!exists) project,
      ],
    );
  }

  /// Only the catalog changes; stored project model snapshots never change here.
  ProjectState upsertModel(WorkModel model) {
    if (!model.isValid || model.isBuiltIn) {
      throw ArgumentError('Invalid custom model');
    }
    final exists = customModels.any((item) => item.id == model.id);
    return copyWith(
      customModels: [
        for (final item in customModels) item.id == model.id ? model : item,
        if (!exists) model,
      ],
    );
  }

  Map<String, Object?> toJson() => {
    'version': schemaVersion,
    'projects': projects.map((project) => project.toJson()).toList(),
    'currentProjectId': currentProjectId,
    'customModels': customModels.map((model) => model.toJson()).toList(),
  };
  factory ProjectState.fromJson(
    Map<String, dynamic> json, {
    bool migrateV2 = false,
  }) {
    if (json['version'] != (migrateV2 ? 2 : schemaVersion)) {
      throw const FormatException('Unsupported schema');
    }
    final state = ProjectState(
      projects: _list(
        json,
        'projects',
      ).map((project) => Project.fromJson(jsonMap(project))).toList(),
      currentProjectId: _string(json, 'currentProjectId'),
      customModels: _list(
        json,
        'customModels',
      ).map((model) => WorkModel.fromJson(jsonMap(model))).toList(),
    );
    if (state.projects.isEmpty ||
        !state.projects.any(
          (project) => project.id == state.currentProjectId,
        ) ||
        state.projects.map((project) => project.id).toSet().length !=
            state.projects.length ||
        state.customModels.any((model) => model.isBuiltIn) ||
        state.customModels.map((model) => model.id).toSet().length !=
            state.customModels.length) {
      throw const FormatException('Invalid state identities');
    }
    return state;
  }
}

Map<String, dynamic> jsonMap(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Expected object');
  }
  return value;
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) throw FormatException('Invalid $key');
  return value;
}

bool _bool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! bool) throw FormatException('Invalid $key');
  return value;
}

List<dynamic> _list(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! List) throw FormatException('Invalid $key');
  return value;
}

double _number(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! num || !value.isFinite) throw FormatException('Invalid $key');
  return value.toDouble();
}

double? _nullableNumber(Object? value) {
  if (value == null) return null;
  if (value is! num || !value.isFinite || value < 0) {
    throw const FormatException('Invalid number');
  }
  return value.toDouble();
}

Map<String, double?> _prices(Object? value) =>
    jsonMap(value).map((key, value) => MapEntry(key, _nullableNumber(value)));
