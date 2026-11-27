import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hasr_alqawaed/data/app_repository.dart';
import 'package:hasr_alqawaed/project/catalog.dart';
import 'package:hasr_alqawaed/project/controller.dart';
import 'package:hasr_alqawaed/project/engine.dart';
import 'package:hasr_alqawaed/project/models.dart';
import 'package:hasr_alqawaed/project/repository.dart';

class _Store implements KeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

Future<ProjectController> _open(_Store store) async {
  final controller = ProjectController(ProjectRepository(store: store));
  await controller.load();
  addTearDown(controller.dispose);
  return controller;
}

const beam = WorkKind.tieBeam;
const below = WorkKind.belowMasonry;
const above = WorkKind.aboveMasonry;

List<(String, double, double)> _outputs(WorkResult work) => [
  for (final line in work.lines) (line.row.id, line.quantity, line.cost),
];

double _blocks(WorkResult work) =>
    work.lines.singleWhere((line) => line.materialId == 'block20').quantity;

void main() {
  test(
    'manual lengths survive save/reopen and only change their own rows',
    () async {
      final store = _Store();
      final c = await _open(store);
      for (final kind in [beam, below, above]) {
        expect(c.savedProject.work(kind).quantity, isNull);
        expect(c.savedProject.work(kind).included, isFalse);
      }

      c.quantity(above, '١٦٠');
      expect(c.result.calculatedCount, 1);
      expect(c.project.work(beam).included, isFalse);
      expect(c.project.work(below).included, isFalse);
      c.quantity(below, '95');
      c.quantity(beam, '١٣٠');
      await c.calculate();
      final first = c.calculatedResult!;
      expect(first.isPartial, isFalse);
      expect(first.work(WorkKind.columns).status, WorkStatus.unentered);
      expect(_blocks(first.work(below)), 950);
      expect(_blocks(first.work(above)), 6000);

      c.quantity(beam, '150');
      expect(c.needsRecalculation, isTrue);
      await c.repository.flush();
      final reopened = await _open(store);
      expect(reopened.calculatedResult!.work(beam).entry.quantity, 130);
      expect(reopened.needsRecalculation, isTrue);
      await reopened.calculate();
      final updated = reopened.calculatedResult!;
      expect(reopened.needsRecalculation, isFalse);
      for (final (kind, length) in [(beam, 150), (below, 95), (above, 160)]) {
        final work = updated.work(kind);
        expect(work.entry.quantity, length);
        expect(work.lines.map((line) => line.inputQuantity).toSet(), {length});
      }
      expect(_blocks(updated.work(below)), 950);
      expect(_blocks(updated.work(above)), 6000);
      for (final kind in [below, above]) {
        expect(_outputs(updated.work(kind)), _outputs(first.work(kind)));
      }
      reopened.quantity(above, '١٢٥٫٧٥');
      final changed = reopened.result;
      expect(_blocks(changed.work(above)), 125.75 * 37.5);
      for (final kind in [beam, below]) {
        expect(_outputs(changed.work(kind)), _outputs(updated.work(kind)));
      }
      expect(updated.work(above).entry.quantity, 160);
    },
  );

  test(
    'cleared required length, explicit zero and exclusion remain distinct',
    () async {
      final store = _Store();
      final c = await _open(store);
      c.quantity(beam, '150');
      c.quantity(below, '95');
      c.quantity(above, '160');
      c.include(above, false);
      c.quantity(beam, '');
      c.quantity(below, '٠');
      await c.calculate();
      final reopened = await _open(store);
      final result = reopened.calculatedResult!;
      expect(result.isPartial, isTrue);
      expect(result.unfinishedWorks.map((work) => work.kind), [beam]);
      expect(result.work(beam).status, WorkStatus.needsData);
      expect(result.work(beam).entry.quantity, isNull);
      expect(result.work(above).status, WorkStatus.excluded);
      expect(result.work(above).entry.quantity, 160);
      expect(result.work(below).status, WorkStatus.zeroQuantity);
      expect(result.work(below).entry.quantity, 0);
      reopened.quantity(beam, '125');
      expect(reopened.result.work(above).status, WorkStatus.excluded);
      expect(reopened.result.work(below).status, WorkStatus.zeroQuantity);
      reopened.quantity(above, '161');
      expect(reopened.result.work(above).status, WorkStatus.calculated);
      expect(reopened.result.work(beam).entry.quantity, 125);
    },
  );

  test(
    'nonempty invalid first input is identified in a saved partial quotation',
    () async {
      final store = _Store();
      final c = await _open(store);
      c.quantity(above, '160');
      c.quantity(WorkKind.foundations, '١٫٥');
      c.roofBeamLength('خطأ');
      await c.calculate();
      final reopened = await _open(store);
      expect(
        reopened.savedProject.work(WorkKind.foundations).included,
        isFalse,
      );
      expect(
        reopened.calculatedResult!.unfinishedWorks.map((work) => work.kind),
        [WorkKind.foundations, WorkKind.roof],
      );
      expect(
        reopened.calculatedResult!.work(below).status,
        WorkStatus.unentered,
      );
      reopened.quantity(WorkKind.foundations, '');
      reopened.roofBeamLength('');
      await reopened.calculate();
      expect(reopened.calculatedResult!.isPartial, isFalse);
    },
  );

  test('paper example accepts 130 typed separately, roof and profit', () async {
    final c = await _open(_Store());
    for (final (kind, value) in [
      (below, '130'),
      (above, '١٣٠'),
      (beam, '130'),
      (WorkKind.foundations, '20'),
      (WorkKind.columns, '20'),
      (WorkKind.leanSlab, '200'),
    ]) {
      c.quantity(kind, value);
    }
    await c.calculate();
    expect(c.calculatedResult!.baseCost, closeTo(86364.20, 1e-8));
    c.roofBeamLength('130');
    c.quantity(WorkKind.roof, '200');
    await c.calculate();
    expect(c.calculatedResult!.quotationTotal, closeTo(147931.70, 1e-8));
    c.profitPercentage('١٠');
    await c.calculate();
    expect(c.calculatedResult!.profitAmount, closeTo(14793.17, 1e-8));
    expect(c.calculatedResult!.quotationTotal, closeTo(162724.87, 1e-8));
  });

  test(
    'v3 uses last issued length for linked rows and leaves manual zero intact',
    () async {
      final base = createExampleProject(id: 'from-v3');
      final custom = base
          .work(below)
          .model!
          .copyWith(id: 'saved-below', name: 'نموذج محفوظ');
      final issued = base.updateWork(
        base
            .work(below)
            .copyWith(model: custom, priceOverrides: {'cement': 53}),
      );
      final editing = issued
          .updateWork(base.work(beam).copyWith(quantity: 150))
          .updateWork(base.work(above).copyWith(quantity: 0, included: false))
          .copyWith(
            calculatedProject: issued,
            calculationStale: true,
            profitPercentage: 12.5,
          );
      final raw = ProjectState(
        projects: [editing],
        currentProjectId: base.id,
        customModels: [custom],
      ).toJson();
      raw['version'] = 3;
      final current = (raw['projects'] as List).single as Map;
      final historical = current['calculatedProject'] as Map;
      for (final project in [current, historical]) {
        final works = project['works'] as List;
        final lower = works.singleWhere((work) => work['kind'] == below.name);
        lower['linkedToTieBeam'] = true;
        lower['quantity'] = 7; // Old, out-of-use manual value.
        final upper = works.singleWhere((work) => work['kind'] == above.name);
        upper['linkedToTieBeam'] = identical(project, historical);
        if (identical(project, historical)) upper['quantity'] = null;
      }
      final original = jsonEncode(raw);
      final store = _Store()..values[ProjectRepository.v3StorageKey] = original;
      final c = await _open(store);
      expect(c.warning, isNull);
      expect(store.values[ProjectRepository.v3StorageKey], original);
      expect(store.values[ProjectRepository.v3BackupKey], original);
      expect(
        store.values[ProjectRepository.storageKey],
        isNot(contains('linkedToTieBeam')),
      );
      expect(c.needsRecalculation, isTrue);
      expect(c.savedProject.profitPercentage, 12.5);
      expect(c.state!.customModels.single.id, custom.id);
      expect(c.project.work(below).priceOverrides, {'cement': 53.0});
      expect(c.project.work(beam).quantity, 150);
      expect(c.project.work(below).quantity, 130);
      expect(c.project.work(below).needsLengthReview, isTrue);
      expect(c.project.work(above).quantity, 0);
      expect(c.project.work(above).needsLengthReview, isFalse);
      expect(c.project.work(above).explicitlyExcluded, isTrue);
      final historicalResult = c.calculatedResult!;
      expect(historicalResult.work(above).entry.quantity, 130);
      expect(historicalResult.work(below).entry.needsLengthReview, isFalse);
      expect(
        historicalResult.baseCost,
        closeTo(calculateProject(issued).baseCost, 1e-8),
      );
      c.acceptLength(below);
      c.quantity(beam, '165');
      await c.repository.flush();
      final reopened = await _open(store);
      expect(reopened.project.work(below).needsLengthReview, isFalse);
      expect(reopened.project.work(below).quantity, 130);
      expect(reopened.calculatedResult!.work(beam).entry.quantity, 130);
      expect(reopened.calculatedResult!.work(above).entry.quantity, 130);
    },
  );

  test(
    'the historical scope remains partial until a new calculation',
    () async {
      final blank = createProject(id: 'partial-v3');
      final project = blank.updateWork(
        blank.work(beam).copyWith(quantity: 130, included: true),
      );
      final raw = ProjectState(
        projects: [project.copyWith(calculatedProject: project)],
        currentProjectId: project.id,
      ).toJson();
      raw['version'] = 3;
      final store = _Store()
        ..values[ProjectRepository.v3StorageKey] = jsonEncode(raw);
      final c = await _open(store);
      final historical = c.calculatedResult!;
      expect(historical.isPartial, isTrue);
      expect(historical.work(below).status, WorkStatus.needsData);
      expect(c.needsRecalculation, isFalse);
      await c.calculate();
      expect(c.calculatedResult!.isPartial, isFalse);
      expect(c.calculatedResult!.work(below).status, WorkStatus.unentered);
      expect(c.calculatedResult!.baseCost, historical.baseCost);
    },
  );

  test(
    'v3 without a quotation recovers only an available source, including zero',
    () async {
      for (final measurement in [null, 0.0, 127.5]) {
        final base = createProject(id: 'no-quote');
        final project = base.updateWork(
          base.work(beam).copyWith(quantity: measurement),
        );
        final raw = ProjectState(
          projects: [project],
          currentProjectId: base.id,
        ).toJson();
        raw['version'] = 3;
        final old = (raw['projects'] as List).single;
        for (final row in old['works'] as List) {
          if ([below.name, above.name].contains(row['kind'])) {
            row['linkedToTieBeam'] = true;
            row['quantity'] = 45; // Inactive manual value.
          }
        }
        final store = _Store()
          ..values[ProjectRepository.v3StorageKey] = jsonEncode(raw);
        final c = await _open(store);
        for (final kind in [below, above]) {
          expect(c.savedProject.work(kind).quantity, measurement);
          expect(
            c.savedProject.work(kind).needsLengthReview,
            measurement != null,
          );
          expect(c.savedProject.work(kind).included, isFalse);
        }
        c.quantity(below, '95');
        await c.repository.flush();
        final reopened = await _open(store);
        expect(reopened.savedProject.work(below).quantity, 95);
        expect(reopened.savedProject.work(below).needsLengthReview, isFalse);
        expect(reopened.savedProject.work(above).quantity, measurement);
        expect(
          reopened.savedProject.work(above).needsLengthReview,
          measurement != null,
        );
      }
    },
  );
}
