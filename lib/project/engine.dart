import 'catalog.dart';
import 'models.dart';

enum WorkStatus {
  calculated('محسوب'),
  zeroQuantity('لا توجد كمية'),
  unentered('لم يُدرج'),
  needsData('يحتاج بيانات'),
  excluded('غير مطلوب'),
  noModel('بانتظار النموذج');

  const WorkStatus(this.label);
  final String label;
}

class CalculatedLine {
  const CalculatedLine({
    required this.projectId,
    required this.kind,
    required this.modelId,
    required this.row,
    required this.inputQuantity,
    required this.inputUnit,
    required this.rawQuantity,
    required this.quantity,
    required this.unitPrice,
    required this.cost,
    required this.overridden,
  });
  final String projectId;
  final WorkKind kind;
  final String modelId;
  final ModelRow row;

  /// The measured work input, before applying the consumption coefficient.
  final double inputQuantity;
  final QuantityUnit inputUnit;
  final double rawQuantity;
  final double quantity;
  final double unitPrice;
  final double cost;
  final bool overridden;
  String get label => row.label;
  QuantityUnit get unit => row.unit;
  String? get materialId => row.materialId;
  QuantitySource get quantitySource => row.quantitySource;
  bool get isMaterial => row.isMaterial;
  bool get reviewBasis => row.reviewBasis;
}

class WorkResult {
  WorkResult({
    required this.entry,
    required this.status,
    List<CalculatedLine> lines = const [],
    this.cost,
    this.materialCost = 0,
    this.serviceCost = 0,
  }) : lines = List.unmodifiable(lines);
  final WorkEntry entry;
  final WorkStatus status;
  final List<CalculatedLine> lines;
  final double? cost;
  final double materialCost;
  final double serviceCost;
  WorkKind get kind => entry.kind;
  String get label => kind.label;
}

class MaterialTotal {
  MaterialTotal({
    required this.material,
    required this.quantity,
    required this.cost,
    required List<CalculatedLine> lines,
  }) : lines = List.unmodifiable(lines);
  final MaterialDefinition material;
  final double quantity;
  final double cost;
  final List<CalculatedLine> lines;
  bool get hasDifferentPrices =>
      lines.map((line) => line.unitPrice).toSet().length > 1;
}

class ProjectResult {
  ProjectResult({
    required this.project,
    required List<WorkResult> works,
    required List<MaterialTotal> materials,
    required List<CalculatedLine> services,
    required this.materialCost,
    required this.serviceCost,
    required this.totalCost,
    required List<String> notes,
  }) : works = List.unmodifiable(works),
       materials = List.unmodifiable(materials),
       services = List.unmodifiable(services),
       notes = List.unmodifiable(notes);
  final Project project;
  final List<WorkResult> works;
  final List<MaterialTotal> materials;
  final List<CalculatedLine> services;
  final double materialCost;
  final double serviceCost;
  final double totalCost;
  double get baseCost => totalCost;
  double? get profitPercentage => project.profitPercentage;
  double? get profitAmount {
    final percentage = profitPercentage;
    if (percentage == null || !validProfitPercentage(percentage)) return null;
    final amount = baseCost * (percentage / 100);
    return validNonnegative(amount) ? amount : null;
  }

  double? get quotationTotal {
    final profit = profitAmount;
    if (profit == null) return null;
    final quotation = baseCost + profit;
    return validNonnegative(quotation) ? quotation : null;
  }

  final List<String> notes;
  int get calculatedCount =>
      works.where((work) => work.status == WorkStatus.calculated).length;
  bool get hasReviewableServices => services.any((line) => line.reviewBasis);
  Iterable<WorkResult> get unfinishedWorks => works.where(
    (work) =>
        work.status == WorkStatus.needsData ||
        work.status == WorkStatus.noModel,
  );
  bool get isPartial => unfinishedWorks.isNotEmpty;
  WorkResult work(WorkKind kind) =>
      works.firstWhere((work) => work.kind == kind);
}

/// Null means an unfinished input, while an absent override means shared price.
double? rowPrice(Project project, WorkEntry work, ModelRow row) {
  if (work.priceOverrides.containsKey(row.id)) {
    return work.priceOverrides[row.id];
  }
  if (row.isMaterial) {
    return project.materialPrices.containsKey(row.materialId)
        ? project.materialPrices[row.materialId]
        : row.defaultPrice;
  }
  final key = servicePriceKey(work.kind, row);
  return project.servicePrices.containsKey(key)
      ? project.servicePrices[key]
      : row.defaultPrice;
}

WorkResult _calculateWork(Project project, WorkEntry entry) {
  if (entry.explicitlyExcluded) {
    return WorkResult(entry: entry, status: WorkStatus.excluded);
  }
  final length = entry.roofBeamLength;
  final hasAllInputs =
      entry.quantityValid &&
      (!entry.requiresRoofBeamLength ||
          length != null && validNonnegative(length));
  if (hasAllInputs &&
      entry.quantity == 0 &&
      (!entry.requiresRoofBeamLength || length == 0)) {
    return WorkResult(entry: entry, status: WorkStatus.zeroQuantity);
  }
  if (!entry.included) {
    return WorkResult(
      entry: entry,
      status: project.legacyIncompleteScope
          ? WorkStatus.needsData
          : WorkStatus.unentered,
    );
  }
  final model = entry.model;
  if (model == null) {
    return WorkResult(entry: entry, status: WorkStatus.noModel);
  }
  if (!hasAllInputs || !model.isValid || model.kind != entry.kind) {
    return WorkResult(entry: entry, status: WorkStatus.needsData);
  }
  final lines = <CalculatedLine>[];
  var materialCost = 0.0;
  var serviceCost = 0.0;
  for (final row in model.rows) {
    final price = rowPrice(project, entry, row);
    if (price == null || !validNonnegative(price)) {
      return WorkResult(entry: entry, status: WorkStatus.needsData);
    }
    if (row.isMaterial) {
      final matches = materialCatalog.where(
        (material) =>
            material.id == row.materialId && material.unit == row.unit,
      );
      if (matches.isEmpty) {
        return WorkResult(entry: entry, status: WorkStatus.needsData);
      }
    }
    final inputQuantity = entry.quantityFor(row.quantitySource)!;
    final rawQuantity = inputQuantity * row.coefficient;
    final quantity = rawQuantity / row.divisor;
    final cost = quantity * price;
    if (![rawQuantity, quantity, cost].every(validNonnegative)) {
      return WorkResult(entry: entry, status: WorkStatus.needsData);
    }
    if (row.isMaterial) {
      materialCost += cost;
    } else {
      serviceCost += cost;
    }
    if (![
      materialCost,
      serviceCost,
      materialCost + serviceCost,
    ].every(validNonnegative)) {
      return WorkResult(entry: entry, status: WorkStatus.needsData);
    }
    lines.add(
      CalculatedLine(
        projectId: project.id,
        kind: entry.kind,
        modelId: model.id,
        row: row,
        inputQuantity: inputQuantity,
        inputUnit: entry.unitFor(row.quantitySource),
        rawQuantity: rawQuantity,
        quantity: quantity,
        unitPrice: price,
        cost: cost,
        overridden: entry.priceOverrides.containsKey(row.id),
      ),
    );
  }
  return WorkResult(
    entry: entry,
    status: WorkStatus.calculated,
    lines: lines,
    cost: materialCost + serviceCost,
    materialCost: materialCost,
    serviceCost: serviceCost,
  );
}

/// The only calculation pipeline used by work details, totals and PDF snapshots.
/// Unfinished work is omitted entirely, so it can never contribute stale costs.
ProjectResult calculateProject(Project project) {
  final works = <WorkResult>[];
  final grouped = <String, List<CalculatedLine>>{};
  final quantities = <String, double>{};
  final costs = <String, double>{};
  final services = <CalculatedLine>[];
  var materialCost = 0.0;
  var serviceCost = 0.0;
  for (final work in project.works) {
    final entry = project.inputDrafts.containsKey('quantity:${work.kind.name}')
        ? work.copyWith(quantity: null)
        : work;
    var result = _calculateWork(project, entry);
    if (result.status == WorkStatus.calculated) {
      // Check aggregate overflow before accepting the entire work atomically.
      final nextQuantities = {...quantities};
      final nextCosts = {...costs};
      for (final line in result.lines.where((line) => line.isMaterial)) {
        final key = materialById(line.materialId!).aggregateKey;
        nextQuantities[key] = (nextQuantities[key] ?? 0) + line.quantity;
        nextCosts[key] = (nextCosts[key] ?? 0) + line.cost;
      }
      final nextMaterial = materialCost + result.materialCost;
      final nextService = serviceCost + result.serviceCost;
      if (![
        nextMaterial,
        nextService,
        nextMaterial + nextService,
        ...nextQuantities.values,
        ...nextCosts.values,
      ].every(validNonnegative)) {
        result = WorkResult(entry: entry, status: WorkStatus.needsData);
      } else {
        materialCost = nextMaterial;
        serviceCost = nextService;
        quantities.addAll(nextQuantities);
        costs.addAll(nextCosts);
        for (final line in result.lines) {
          if (line.isMaterial) {
            final key = materialById(line.materialId!).aggregateKey;
            (grouped[key] ??= []).add(line);
          } else {
            // Keep work and pricing basis attached; unlike materials, services
            // with matching labels do not constitute an interchangeable stock.
            services.add(line);
          }
        }
      }
    }
    works.add(result);
  }
  final notes = <String>[];
  if (services.any((line) => line.reviewBasis)) {
    notes.add('تقدير مبدئي — توجد وحدات خدمات قابلة للمراجعة حسب الورقة:');
    notes.addAll(
      services
          .where((line) => line.reviewBasis)
          .map(
            (line) =>
                '${line.kind.label}: ${line.label} لكل ${line.unit.label}.',
          ),
    );
  }
  final roof = works.firstWhere((work) => work.kind == WorkKind.roof);
  if (roof.status == WorkStatus.calculated &&
      roof.entry.model?.id == roofModelId) {
    notes.addAll([roofLaborBasisNote, roofCorrectionNote, roofScopeNote]);
  }
  if (roof.status != WorkStatus.calculated &&
      roof.status != WorkStatus.zeroQuantity) {
    notes.add('السقف غير مشمول في الإجمالي');
  }
  final unfinished = works.where(
    (work) =>
        work.status == WorkStatus.needsData ||
        work.status == WorkStatus.noModel,
  );
  if (unfinished.isNotEmpty) {
    notes.add(
      'بنود غير محسوبة: ${unfinished.map((work) => work.label).join('، ')}',
    );
  }
  return ProjectResult(
    project: project,
    works: works,
    materials: [
      for (final material in materialCatalog)
        if (grouped.containsKey(material.aggregateKey))
          MaterialTotal(
            material: material,
            quantity: quantities[material.aggregateKey]!,
            cost: costs[material.aggregateKey]!,
            lines: grouped[material.aggregateKey]!,
          ),
    ],
    services: services,
    materialCost: materialCost,
    serviceCost: serviceCost,
    totalCost: materialCost + serviceCost,
    notes: notes,
  );
}
