import '../domain/models.dart' as legacy;
import '../domain/numbers.dart';
import 'models.dart';

const materialCatalog = <MaterialDefinition>[
  MaterialDefinition(
    id: 'concrete',
    label: 'خرسانة مسلحة',
    specification: 'مسلحة',
    unit: QuantityUnit.volume,
    defaultPrice: 560,
  ),
  MaterialDefinition(
    id: 'concreteC15',
    label: 'خرسانة C15',
    specification: 'C15',
    unit: QuantityUnit.volume,
    defaultPrice: 500,
  ),
  MaterialDefinition(
    id: 'steel14',
    label: 'حديد قطر 14',
    specification: 'قطر 14',
    unit: QuantityUnit.quintal,
    defaultPrice: 520,
  ),
  MaterialDefinition(
    id: 'steel8',
    label: 'حديد قطر 8',
    specification: 'قطر 8',
    unit: QuantityUnit.quintal,
    defaultPrice: 600,
  ),
  MaterialDefinition(
    id: 'steel6',
    label: 'حديد قطر 6',
    specification: 'قطر 6',
    unit: QuantityUnit.quintal,
    defaultPrice: 260,
  ),
  MaterialDefinition(
    id: 'block20',
    label: 'بلوك 20 سم',
    specification: '20 سم',
    unit: QuantityUnit.block,
    defaultPrice: 1.8,
  ),
  MaterialDefinition(
    id: 'hollowBlock',
    label: 'بلوك هوردي',
    specification: 'هوردي',
    unit: QuantityUnit.block,
    defaultPrice: 1.8,
  ),
  MaterialDefinition(
    id: 'cement',
    label: 'أسمنت بالنقل',
    specification: 'بالنقل',
    unit: QuantityUnit.bag,
    defaultPrice: 42,
  ),
  MaterialDefinition(
    id: 'sand',
    label: 'رمل',
    specification: 'رمل',
    unit: QuantityUnit.volume,
    defaultPrice: 70,
  ),
];

MaterialDefinition materialById(String id) =>
    materialCatalog.firstWhere((material) => material.id == id);

ModelRow _material(
  String id,
  double coefficient, {
  String? rowId,
  String? label,
  double divisor = 1,
  QuantityUnit? sourceUnit,
  QuantitySource quantitySource = QuantitySource.workQuantity,
}) {
  final material = materialById(id);
  return ModelRow(
    id: rowId ?? id,
    label: label ?? material.label,
    materialId: id,
    unit: material.unit,
    sourceUnit: sourceUnit,
    quantitySource: quantitySource,
    coefficient: coefficient,
    divisor: divisor,
    defaultPrice: material.defaultPrice,
  );
}

ModelRow _service(
  String id,
  String label,
  QuantityUnit unit,
  double price, {
  double coefficient = 1,
  double divisor = 1,
  QuantityUnit? sourceUnit,
  QuantitySource quantitySource = QuantitySource.workQuantity,
  bool review = false,
}) => ModelRow(
  id: id,
  label: label,
  unit: unit,
  coefficient: coefficient,
  divisor: divisor,
  sourceUnit: sourceUnit,
  quantitySource: quantitySource,
  defaultPrice: price,
  reviewBasis: review,
);

WorkModel convertFoundationModel(legacy.FoundationModel model) => WorkModel(
  id: model.id,
  kind: WorkKind.foundations,
  name: model.name,
  description:
      '${inputNumber(model.length)} × ${inputNumber(model.width)} × ${inputNumber(model.height)} م — أبعاد وصفية',
  inputUnit: QuantityUnit.foundation,
  rows: [
    _material('concrete', model.concretePerFoundation),
    _material(
      'steel14',
      model.steel14BarsPerFoundation,
      divisor: model.steel14BarsPerQuintal,
      sourceUnit: QuantityUnit.bar,
    ),
    _material(
      'steel8',
      model.steel8BarsPerFoundation,
      divisor: model.steel8BarsPerQuintal,
      sourceUnit: QuantityUnit.bar,
    ),
    _service('carpenter', 'نجار', QuantityUnit.foundation, 70),
    _service('steelWorker', 'حداد', QuantityUnit.foundation, 30),
    _service('casting', 'صب', QuantityUnit.foundation, 60),
  ],
);

const roofModelId = 'builtin-roof-25cm-1';
const roofStirrupsRowId = 'steel8-stirrups';
const roofArea = QuantitySource.roofArea;
const roofBeamLength = QuantitySource.roofBeamLength;
const roofLaborBasisNote =
    'القسمة على 4 في نجارة السقف وحدادته معامل تسعير خاص بالنموذج من الورقة، ولا يتغيّر بتغيير وصف السمك.';
const roofCorrectionNote =
    'تم تصحيح حاصل ضرب سطر الكانات من 5,040 إلى 5,070، مع الإبقاء على الكمية والسعر الواردين في الورقة.';
const roofScopeNote =
    'معاملات السقف لأغراض حصر الكميات والتكلفة؛ لا تُعد تصميمًا إنشائيًا أو تحققًا من سلامة التسليح.';

final List<WorkModel> builtInModels = List.unmodifiable([
  convertFoundationModel(legacy.FoundationModel.builtIn),
  WorkModel(
    id: 'builtin-below-masonry-1',
    kind: WorkKind.belowMasonry,
    name: 'نموذج 1',
    description: 'ارتفاع 4 بلوكات',
    inputUnit: QuantityUnit.linear,
    rows: [
      _material('block20', 10),
      _material('cement', .30),
      _material('sand', .05),
      _service('water', 'خدمة مياه', QuantityUnit.linear, 1, review: true),
      _service('mason', 'بنّاي', QuantityUnit.linear, 8),
      _service('stocking', 'عامل تشوين', QuantityUnit.linear, 6),
    ],
  ),
  WorkModel(
    id: 'builtin-tie-beam-1',
    kind: WorkKind.tieBeam,
    name: 'نموذج 1',
    inputUnit: QuantityUnit.linear,
    rows: [
      _material('concrete', .08),
      _material('steel14', .55, divisor: 6.5, sourceUnit: QuantityUnit.bar),
      _material('steel8', .60, divisor: 20, sourceUnit: QuantityUnit.bar),
      _service('carpenter', 'نجار', QuantityUnit.linear, 20),
      _service('steelWorker', 'حداد', QuantityUnit.linear, 5),
      _service('casting', 'صب', QuantityUnit.linear, 15),
    ],
  ),
  WorkModel(
    id: 'builtin-lean-slab-1',
    kind: WorkKind.leanSlab,
    name: 'نموذج 1',
    description: 'سمك 10 سم',
    inputUnit: QuantityUnit.area,
    rows: [
      _material('concreteC15', .10),
      _service(
        'waterTruck',
        'خدمة سيارة مياه',
        QuantityUnit.area,
        1.5,
        review: true,
      ),
      _service('carpenter', 'نجار', QuantityUnit.area, 1),
      _service('mixer', 'خدمة عجانة', QuantityUnit.area, 7, review: true),
    ],
  ),
  WorkModel(
    id: 'builtin-columns-1',
    kind: WorkKind.columns,
    name: 'نموذج 1',
    inputUnit: QuantityUnit.column,
    rows: [
      _material('concrete', .256),
      _material('steel14', 3, divisor: 6.5, sourceUnit: QuantityUnit.bar),
      _material('steel8', 2, divisor: 20, sourceUnit: QuantityUnit.bar),
      _service('carpenter', 'نجار', QuantityUnit.column, 70),
      _service('steelWorker', 'حداد', QuantityUnit.column, 30),
      _service('casting', 'صب', QuantityUnit.column, 35),
    ],
  ),
  WorkModel(
    id: 'builtin-above-masonry-1',
    kind: WorkKind.aboveMasonry,
    name: 'نموذج 1',
    description: 'ارتفاع 15 بلوكة',
    inputUnit: QuantityUnit.linear,
    rows: [
      _material('block20', 37.5),
      _material('cement', 1),
      _material('sand', .07),
      _service('water', 'خدمة مياه', QuantityUnit.linear, 1, review: true),
      _service('mason', 'بنّاي', QuantityUnit.area, 8, coefficient: 3.2),
      _service('stocking', 'عامل تشوين', QuantityUnit.linear, 10),
    ],
  ),
  WorkModel(
    id: roofModelId,
    kind: WorkKind.roof,
    name: 'سقف سمك 25 سم — نموذج 1',
    description: 'سمك 25 سم. $roofLaborBasisNote $roofScopeNote',
    inputUnit: QuantityUnit.area,
    rows: [
      _material('concrete', .25, quantitySource: roofArea),
      _material(
        'steel14',
        1,
        label: 'حديد قطر 14 للكمرات',
        divisor: 6.5,
        sourceUnit: QuantityUnit.bar,
        quantitySource: roofBeamLength,
      ),
      _material(
        'steel8',
        1.3,
        rowId: roofStirrupsRowId,
        label: 'حديد قطر 8 للكانات',
        divisor: 20,
        sourceUnit: QuantityUnit.bar,
        quantitySource: roofBeamLength,
      ),
      _material(
        'steel8',
        1,
        rowId: 'steel8-mesh',
        label: 'حديد قطر 8 فرش وغطاء',
        divisor: 20,
        sourceUnit: QuantityUnit.bar,
        quantitySource: roofArea,
      ),
      _material(
        'steel6',
        1.5,
        label: 'حديد قطر 6 للأعصاب',
        divisor: 32,
        sourceUnit: QuantityUnit.bar,
        quantitySource: roofArea,
      ),
      _material('hollowBlock', 6, quantitySource: roofArea),
      _service(
        'roof25-carpenter',
        'نجار السقف',
        QuantityUnit.volume,
        70,
        divisor: 4,
        sourceUnit: QuantityUnit.area,
        quantitySource: roofArea,
      ),
      _service(
        'roof25-steel-worker',
        'حداد السقف',
        QuantityUnit.volume,
        40,
        divisor: 4,
        sourceUnit: QuantityUnit.area,
        quantitySource: roofArea,
      ),
      _service(
        'roof25-casting',
        'صب السقف',
        QuantityUnit.area,
        10,
        quantitySource: roofArea,
      ),
    ],
  ),
]);

WorkModel? defaultModel(WorkKind kind) {
  for (final model in builtInModels) {
    if (model.kind == kind) return model;
  }
  return null;
}

int _idSequence = 0;
String newProjectId() =>
    'project-${DateTime.now().microsecondsSinceEpoch}-${_idSequence++}';

Project createProject({
  String? id,
  String name = 'مشروع جديد',
  String? date,
  String location = '',
}) => Project(
  id: id ?? newProjectId(),
  name: name,
  date: date ?? DateTime.now().toIso8601String().split('T').first,
  location: location,
  works: [
    for (final kind in WorkKind.values)
      WorkEntry(
        kind: kind,
        included: false,
        explicitlyExcluded: false,
        model: defaultModel(kind),
      ),
  ],
  materialPrices: {
    for (final material in materialCatalog) material.id: material.defaultPrice,
  },
  servicePrices: {
    for (final model in builtInModels)
      for (final row in model.rows)
        if (!row.isMaterial) servicePriceKey(model.kind, row): row.defaultPrice,
  },
);

/// An explicit independent example, never injected into migrated user projects.
Project createExampleProject({String? id}) {
  final project = createProject(id: id, name: 'مثال الأوراق');
  const quantities = <WorkKind, double>{
    WorkKind.foundations: 20,
    WorkKind.belowMasonry: 130,
    WorkKind.tieBeam: 130,
    WorkKind.leanSlab: 200,
    WorkKind.columns: 20,
    WorkKind.aboveMasonry: 130,
  };
  return project.copyWith(
    isExample: true,
    works: [
      for (final work in project.works)
        work.copyWith(
          included: quantities.containsKey(work.kind),
          quantity: quantities[work.kind],
        ),
    ],
  );
}

Project createFullExampleProject({String? id}) {
  final project = createExampleProject(id: id);
  return project
      .updateWork(
        project
            .work(WorkKind.roof)
            .copyWith(included: true, quantity: 200, roofBeamLength: 130),
      )
      .copyWith(name: 'مثال الأوراق مع السقف');
}

/// Adds only absent keys and a roof option for entries without a selection.
/// No prior input becomes active merely because it has a stored quantity.
ProjectState migrateProjectStateV2(ProjectState previous) {
  final roof = defaultModel(WorkKind.roof)!;
  // A legacy roof model with a missing shared price still uses its row's
  // default. Seeding a colliding key would silently change that model's cost.
  final legacyServiceKeys = {
    for (final model in [
      ...previous.customModels,
      for (final project in previous.projects)
        ?project.work(WorkKind.roof).model,
    ])
      if (model.kind == WorkKind.roof)
        for (final row in model.rows)
          if (!row.isMaterial) servicePriceKey(WorkKind.roof, row),
  };
  return previous.copyWith(
    projects: [
      for (final project in previous.projects)
        project
            .updateWork(
              project.work(WorkKind.roof).model == null
                  ? project.work(WorkKind.roof).copyWith(model: roof)
                  : project.work(WorkKind.roof),
            )
            .copyWith(
              materialPrices: {
                'steel6': materialById('steel6').defaultPrice,
                'hollowBlock': materialById('hollowBlock').defaultPrice,
                ...project.materialPrices,
              },
              servicePrices: {
                for (final row in roof.rows)
                  if (!row.isMaterial &&
                      !legacyServiceKeys.contains(
                        servicePriceKey(WorkKind.roof, row),
                      ))
                    servicePriceKey(WorkKind.roof, row): row.defaultPrice,
                ...project.servicePrices,
              },
            ),
    ],
  );
}

ProjectState migrateLegacyState(legacy.AppData data) {
  final project = createProject(
    id: 'migrated-project-v1',
    name: 'مشروعي السابق',
  );
  final prices = data.inputs.prices;
  final selected = convertFoundationModel(data.selectedModel);
  final migrated = project
      .updateWork(
        project
            .work(WorkKind.foundations)
            .copyWith(
              included: true,
              quantity: data.inputs.count.toDouble(),
              model: selected,
            ),
      )
      .copyWith(
        materialPrices: {
          ...project.materialPrices,
          'concrete': prices.concrete,
          'steel14': prices.steel14,
          'steel8': prices.steel8,
        },
        servicePrices: {
          ...project.servicePrices,
          servicePriceKey(
            WorkKind.foundations,
            selected.rows.firstWhere((row) => row.id == 'carpenter'),
          ): prices.carpenter,
          servicePriceKey(
            WorkKind.foundations,
            selected.rows.firstWhere((row) => row.id == 'steelWorker'),
          ): prices.steelWorker,
          servicePriceKey(
            WorkKind.foundations,
            selected.rows.firstWhere((row) => row.id == 'casting'),
          ): prices.casting,
        },
      );
  return ProjectState(
    projects: [migrated],
    currentProjectId: migrated.id,
    customModels: data.customModels.map(convertFoundationModel).toList(),
  );
}
