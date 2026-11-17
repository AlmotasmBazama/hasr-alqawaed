import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hasr_alqawaed/data/app_repository.dart';
import 'package:hasr_alqawaed/project/catalog.dart';
import 'package:hasr_alqawaed/project/controller.dart';
import 'package:hasr_alqawaed/project/engine.dart';
import 'package:hasr_alqawaed/project/models.dart';
import 'package:hasr_alqawaed/project/repository.dart';

class _Store implements KeyValueStore {
  final data = <String, String>{};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;
}

void near(double? actual, double expected) =>
    expect(actual, closeTo(expected, 1e-8));

void main() {
  test('roof formulas use independently priced area and beam sources', () {
    final project = createFullExampleProject();
    final roof = project.work(WorkKind.roof);
    WorkResult estimate(double area, double length) => calculateProject(
      project.updateWork(roof.copyWith(quantity: area, roofBeamLength: length)),
    ).work(WorkKind.roof);
    final result = estimate(200, 130);
    const quantities = [
      50.0,
      20.0,
      8.45,
      10.0,
      9.375,
      1200.0,
      50.0,
      50.0,
      200.0,
    ];
    const costs = [
      28000.0,
      10400.0,
      5070.0,
      6000.0,
      2437.5,
      2160.0,
      3500.0,
      2000.0,
      2000.0,
    ];
    expect(result.lines.length, quantities.length);
    for (var i = 0; i < quantities.length; i++) {
      near(result.lines[i].quantity, quantities[i]);
      near(result.lines[i].cost, costs[i]);
    }
    near(result.materialCost, 54067.5);
    near(result.serviceCost, 7500);
    near(result.cost, 61567.5);
    for (final change in [
      (
        result: estimate(200, 260),
        expected: [50.0, 40.0, 16.9, 10.0, 9.375, 1200.0, 50.0, 50.0, 200.0],
      ),
      (
        result: estimate(400, 130),
        expected: [100.0, 20.0, 8.45, 20.0, 18.75, 2400.0, 100.0, 100.0, 400.0],
      ),
    ]) {
      for (var i = 0; i < quantities.length; i++) {
        near(change.result.lines[i].quantity, change.expected[i]);
      }
    }
    expect(
      calculateProject(
        project.updateWork(roof.copyWith(roofBeamLength: null)),
      ).work(WorkKind.roof).status,
      WorkStatus.needsData,
    );
    final noBeams = estimate(200, 0);
    expect(noBeams.status, WorkStatus.calculated);
    near(noBeams.lines[1].quantity, 0);
    near(noBeams.lines[2].quantity, 0);
  });

  test('full example aggregates actual costs, then adds profit once', () {
    final project = createFullExampleProject().copyWith(profitPercentage: 10);
    final result = calculateProject(project);
    near(result.materialCost, 120723.7);
    near(result.serviceCost, 27208);
    near(result.baseCost, 147931.7);
    near(result.profitAmount, 14793.17);
    near(result.quotationTotal, 162724.87);
    expect(result.isPartial, isFalse);
    const expected = {
      'concrete': 80.52,
      'concreteC15': 20.0,
      'steel14': 51.0,
      'steel8': 25.35,
      'steel6': 9.375,
      'block20': 6175.0,
      'hollowBlock': 1200.0,
      'cement': 169.0,
      'sand': 15.6,
    };
    expect(result.materials.length, expected.length);
    for (final row in result.materials) {
      near(row.quantity, expected[row.material.id]!);
      near(row.cost, row.lines.fold(0.0, (sum, line) => sum + line.cost));
    }
  });

  test(
    'v2 migration preserves exclusions and snapshots, then v3 remembers stale calculations',
    () async {
      final old = createExampleProject(id: 'v2');
      final beam = old.work(WorkKind.tieBeam);
      final custom = beam.model!.copyWith(id: 'old-custom', name: 'ميدة قديمة');
      final migratedInput = old.updateWork(
        beam.copyWith(
          included: false,
          model: custom,
          priceOverrides: {beam.model!.rows.first.id: 555},
        ),
      );
      final oldJson = jsonEncode({
        'version': 2,
        'currentProjectId': old.id,
        'projects': [migratedInput.toJson()],
        'customModels': [custom.toJson()],
      });
      final store = _Store()
        ..data[ProjectRepository.previousStorageKey] = oldJson;
      final controller = ProjectController(ProjectRepository(store: store));
      await controller.load();
      expect(controller.savedProject.id, 'v2');
      expect(controller.savedProject.work(WorkKind.tieBeam).included, isFalse);
      expect(controller.savedProject.work(WorkKind.tieBeam).quantity, 130);
      expect(
        controller.savedProject.work(WorkKind.tieBeam).model!.id,
        custom.id,
      );
      expect(
        controller.savedProject.work(WorkKind.tieBeam).priceOverrides.values,
        [555],
      );
      expect(
        controller.savedProject.work(WorkKind.roof).roofBeamLength,
        isNull,
      );
      expect(controller.savedProject.profitPercentage, 0);
      expect(store.data[ProjectRepository.previousStorageKey], oldJson);
      expect(store.data[ProjectRepository.previousBackupKey], oldJson);
      await controller.calculate();
      final savedQuote = controller.calculatedResult!.quotationTotal;
      controller.profitPercentage('١٠٫٥');
      await controller.saveNow();
      expect(controller.needsRecalculation, true);
      final reopened = ProjectController(ProjectRepository(store: store));
      await reopened.load();
      expect(reopened.calculatedResult!.quotationTotal, savedQuote);
      expect(reopened.needsRecalculation, true);
      expect(reopened.savedProject.profitPercentage, 10.5);
      await reopened.calculate();
      near(reopened.calculatedResult!.quotationTotal, savedQuote! * 1.105);
      expect(reopened.needsRecalculation, false);
      controller.dispose();
      reopened.dispose();
    },
  );
}
