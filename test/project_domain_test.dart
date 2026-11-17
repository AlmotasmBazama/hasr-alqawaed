import 'package:flutter_test/flutter_test.dart';
import 'package:hasr_alqawaed/domain/numbers.dart';
import 'package:hasr_alqawaed/project/catalog.dart';
import 'package:hasr_alqawaed/project/engine.dart';
import 'package:hasr_alqawaed/project/models.dart';

void main() {
  test(
    'paper example calculates six work costs and all material aggregates',
    () {
      final result = calculateProject(createExampleProject());
      const expectedCosts = [
        17800.0,
        6383.0,
        19084.0,
        11900.0,
        11567.2,
        19630.0,
      ];
      for (var i = 0; i < expectedCosts.length; i++) {
        expect(result.works[i].cost, closeTo(expectedCosts[i], 1e-8));
      }
      expect(result.totalCost, closeTo(86364.2, 1e-8));
      expect(result.materialCost, closeTo(66656.2, 1e-8));
      expect(result.serviceCost, closeTo(19708, 1e-8));
      const quantities = {
        'concrete': 30.52,
        'concreteC15': 20.0,
        'steel14': 31.0,
        'steel8': 6.9,
        'block20': 6175.0,
        'cement': 169.0,
        'sand': 15.6,
      };
      for (final material in result.materials) {
        expect(
          material.quantity,
          closeTo(quantities[material.material.id]!, 1e-8),
        );
      }
      expect(result.materials.length, 7);
      expect(result.calculatedCount, 6);
      expect(result.work(WorkKind.roof).cost, isNull);
      expect(result.work(WorkKind.roof).status, WorkStatus.excluded);
      expect(result.notes, contains('السقف غير مشمول في الإجمالي'));
      expect(result.hasReviewableServices, isTrue);
      expect(result.isPartial, isFalse);
    },
  );

  test('shared cement price updates both masonry works exactly', () {
    final project = createExampleProject();
    final before = calculateProject(project);
    final after = calculateProject(
      project.copyWith(
        materialPrices: {...project.materialPrices, 'cement': 40},
      ),
    );
    expect(after.totalCost, closeTo(86026.2, 1e-8));
    expect(before.totalCost - after.totalCost, closeTo(338, 1e-8));
    expect(
      before.work(WorkKind.belowMasonry).cost! -
          after.work(WorkKind.belowMasonry).cost!,
      closeTo(78, 1e-8),
    );
    expect(
      before.work(WorkKind.aboveMasonry).cost! -
          after.work(WorkKind.aboveMasonry).cost!,
      closeTo(260, 1e-8),
    );
  });

  test(
    'shared steel price changes every relevant work without touching another project',
    () {
      final first = createExampleProject(id: 'first');
      final second = createExampleProject(id: 'second');
      final updated = first.copyWith(
        materialPrices: {...first.materialPrices, 'steel14': 530},
      );
      expect(
        calculateProject(updated).totalCost - calculateProject(first).totalCost,
        closeTo(310, 1e-8),
      );
      expect(calculateProject(second).totalCost, closeTo(86364.2, 1e-8));
      expect(
        () => first.materialPrices['steel14'] = 10,
        throwsUnsupportedError,
      );
    },
  );

  test(
    'beam model coefficient is isolated from other work and existing model snapshot',
    () {
      final project = createExampleProject();
      final beam = project.work(WorkKind.tieBeam);
      final changedModel = beam.model!.copyWith(
        id: 'custom-beam',
        rows: [
          for (final row in beam.model!.rows)
            row.id == 'concrete' ? row.copyWith(coefficient: .16) : row,
        ],
      );
      final after = calculateProject(
        project.updateWork(beam.copyWith(model: changedModel)),
      );
      final before = calculateProject(project);
      expect(
        after.totalCost - before.totalCost,
        closeTo(130 * .08 * 560, 1e-8),
      );
      for (final kind in WorkKind.values.where(
        (kind) => kind != WorkKind.tieBeam,
      )) {
        expect(after.work(kind).cost, before.work(kind).cost);
      }
      expect(beam.model!.rows.first.coefficient, .08);
    },
  );

  test('quantity affects only its own work and columns remain independent', () {
    final project = createExampleProject();
    final updated = project.updateWork(
      project.work(WorkKind.columns).copyWith(quantity: 10),
    );
    final result = calculateProject(updated);
    expect(result.work(WorkKind.columns).cost, closeTo(11567.2 / 2, 1e-8));
    expect(result.work(WorkKind.foundations).cost, closeTo(17800, 1e-8));
  });

  test(
    'price overrides retain actual line cost when aggregating one material',
    () {
      final project = createExampleProject();
      final work = project.work(WorkKind.aboveMasonry);
      final result = calculateProject(
        project.updateWork(work.copyWith(priceOverrides: {'cement': 40})),
      );
      final cement = result.materials.firstWhere(
        (material) => material.material.id == 'cement',
      );
      expect(cement.quantity, 169);
      expect(cement.cost, closeTo(39 * 42 + 130 * 40, 1e-8));
      expect(cement.hasDifferentPrices, isTrue);
      expect(result.totalCost, closeTo(86364.2 - 260, 1e-8));
      expect(
        result
            .work(WorkKind.aboveMasonry)
            .lines
            .firstWhere((line) => line.materialId == 'cement')
            .overridden,
        isTrue,
      );
    },
  );

  test(
    'services retain work and pricing basis without cross-unit aggregation',
    () {
      final result = calculateProject(createExampleProject());
      expect(
        result.services.where((line) => line.row.id == 'carpenter').length,
        4,
      );
      final below = result.services.firstWhere(
        (line) => line.kind == WorkKind.belowMasonry && line.row.id == 'mason',
      );
      final above = result.services.firstWhere(
        (line) => line.kind == WorkKind.aboveMasonry && line.row.id == 'mason',
      );
      expect(below.unit, QuantityUnit.linear);
      expect(below.quantity, 130);
      expect(above.unit, QuantityUnit.area);
      expect(above.quantity, 416);
      expect(above.cost, 3328);
      expect(
        servicePriceKey(below.kind, below.row),
        isNot(servicePriceKey(above.kind, above.row)),
      );
      final slabServices = result
          .work(WorkKind.leanSlab)
          .lines
          .where((line) => !line.isMaterial);
      expect(
        slabServices.every(
          (line) => line.unit == QuantityUnit.area && line.quantity == 200,
        ),
        isTrue,
      );
      expect(result.work(WorkKind.leanSlab).lines.length, 4);
    },
  );

  test(
    'excluded and incomplete work have null totals and contribute no stale rows',
    () {
      final project = createExampleProject();
      final without = project.updateWork(
        project.work(WorkKind.tieBeam).copyWith(quantity: null),
      );
      final result = calculateProject(without);
      expect(result.work(WorkKind.tieBeam).cost, isNull);
      expect(result.work(WorkKind.tieBeam).status, WorkStatus.needsData);
      expect(result.totalCost, closeTo(86364.2 - 19084, 1e-8));
      expect(
        result.services.any((line) => line.kind == WorkKind.tieBeam),
        isFalse,
      );
      final excluded = calculateProject(
        project.updateWork(
          project.work(WorkKind.roof).copyWith(included: false),
        ),
      );
      expect(excluded.work(WorkKind.roof).status, WorkStatus.excluded);
      expect(excluded.work(WorkKind.roof).cost, isNull);
      expect(excluded.notes, contains('السقف غير مشمول في الإجمالي'));
    },
  );

  test(
    'blank shared price affects relevant works and never uses default or stale price',
    () {
      final project = createExampleProject();
      final result = calculateProject(
        project.copyWith(
          materialPrices: {...project.materialPrices, 'cement': null},
        ),
      );
      expect(result.work(WorkKind.belowMasonry).status, WorkStatus.needsData);
      expect(result.work(WorkKind.aboveMasonry).status, WorkStatus.needsData);
      expect(result.totalCost, closeTo(86364.2 - 6383 - 19630, 1e-8));
      expect(
        result.materials.any((material) => material.material.id == 'cement'),
        isFalse,
      );
    },
  );

  test('zero prices and coefficients are valid; zero divisors are not', () {
    final blank = createProject();
    final project = blank.updateWork(
      blank.work(WorkKind.foundations).copyWith(included: true, quantity: 20),
    );
    final foundation = project.work(WorkKind.foundations);
    final zeroPrice = calculateProject(
      project.copyWith(
        materialPrices: {...project.materialPrices, 'steel14': 0},
      ),
    );
    expect(zeroPrice.work(WorkKind.foundations).status, WorkStatus.calculated);
    final invalid = foundation.model!.copyWith(
      rows: [foundation.model!.rows.first.copyWith(divisor: 0)],
    );
    expect(invalid.isValid, isFalse);
    expect(
      calculateProject(
        project.updateWork(foundation.copyWith(model: invalid)),
      ).work(WorkKind.foundations).cost,
      isNull,
    );
    final zero = foundation.model!.copyWith(
      rows: [foundation.model!.rows.first.copyWith(coefficient: 0)],
    );
    expect(zero.isValid, isTrue);
    expect(
      calculateProject(
        project.updateWork(foundation.copyWith(model: zero)),
      ).totalCost,
      0,
    );
  });

  test('Arabic decimal works for length while counts must stay integer', () {
    expect(parseDecimal('٣٫٥'), 3.5);
    final project = createExampleProject();
    final length = calculateProject(
      project.updateWork(
        project.work(WorkKind.tieBeam).copyWith(quantity: parseDecimal('٣٫٥')),
      ),
    );
    expect(length.work(WorkKind.tieBeam).status, WorkStatus.calculated);
    final fractionalCount = calculateProject(
      project.updateWork(
        project.work(WorkKind.columns).copyWith(quantity: 3.5),
      ),
    );
    expect(fractionalCount.work(WorkKind.columns).status, WorkStatus.needsData);
  });

  test('infinite quantities, costs, and aggregate overflow are rejected', () {
    final project = createExampleProject();
    final invalid = calculateProject(
      project.updateWork(
        project.work(WorkKind.tieBeam).copyWith(quantity: double.infinity),
      ),
    );
    expect(invalid.totalCost.isFinite, isTrue);
    expect(invalid.work(WorkKind.tieBeam).status, WorkStatus.needsData);
    final overflow = calculateProject(
      project.copyWith(
        materialPrices: {...project.materialPrices, 'concrete': 1e308},
      ),
    );
    expect(overflow.totalCost.isFinite, isTrue);
    expect(overflow.work(WorkKind.foundations).status, WorkStatus.needsData);
  });

  test(
    'roof can be defined explicitly with any chosen input unit and dynamic rows',
    () {
      final project = createProject();
      final roof = WorkModel(
        id: 'custom-roof',
        kind: WorkKind.roof,
        name: 'سقف مخصص',
        inputUnit: QuantityUnit.area,
        rows: [
          ModelRow(
            id: 'concrete',
            label: 'خرسانة مسلحة',
            materialId: 'concrete',
            unit: QuantityUnit.volume,
            coefficient: .2,
            defaultPrice: 560,
          ),
        ],
      );
      final result = calculateProject(
        project.updateWork(
          project
              .work(WorkKind.roof)
              .copyWith(included: true, model: roof, quantity: 100),
        ),
      );
      expect(result.work(WorkKind.roof).cost, 11200);
      expect(result.work(WorkKind.roof).lines.length, 1);
      expect(result.notes, isNot(contains('السقف غير مشمول في الإجمالي')));
    },
  );

  test(
    'custom model update by ID does not alter project snapshots or duplicate catalog',
    () {
      final model = defaultModel(WorkKind.tieBeam)!.copyWith(id: 'custom-beam');
      final project = createExampleProject().updateWork(
        WorkEntry(
          kind: WorkKind.tieBeam,
          included: true,
          quantity: 130,
          model: model,
        ),
      );
      final state = ProjectState(
        projects: [project],
        currentProjectId: project.id,
      ).upsertModel(model);
      final changed = model.copyWith(
        name: 'معدل',
        rows: [model.rows.first.copyWith(coefficient: .2)],
      );
      final updated = state.upsertModel(changed);
      expect(updated.customModels.length, 1);
      expect(updated.customModels.single.name, 'معدل');
      expect(
        updated.currentProject.work(WorkKind.tieBeam).model!.rows.length,
        6,
      );
      expect(
        calculateProject(updated.currentProject).totalCost,
        closeTo(86364.2, 1e-8),
      );
    },
  );
}
