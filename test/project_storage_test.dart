import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hasr_alqawaed/data/app_repository.dart';
import 'package:hasr_alqawaed/domain/models.dart' as legacy;
import 'package:hasr_alqawaed/project/catalog.dart';
import 'package:hasr_alqawaed/project/engine.dart';
import 'package:hasr_alqawaed/project/models.dart';
import 'package:hasr_alqawaed/project/repository.dart';

class MemoryProjectStore implements KeyValueStore {
  final values = <String, String>{};
  final writes = <String>[];
  String? failKey;
  bool failRead = false;
  @override
  Future<String?> read(String key) async {
    if (failRead) throw StateError('read failed');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    writes.add(key);
    if (failKey == key) throw StateError('write failed');
    values[key] = value;
  }
}

legacy.AppData oldData() {
  final custom = legacy.FoundationModel.builtIn.copyWith(
    id: 'custom-original',
    name: 'أساس خاص',
    length: 1.37,
    width: 1.28,
    height: .62,
    concretePerFoundation: .8137,
    steel14BarsPerFoundation: 3.75,
    steel14BarsPerQuintal: 6.3,
    steel8BarsPerFoundation: 1.8,
    steel8BarsPerQuintal: 19.5,
  );
  return legacy.AppData(
    customModels: [custom],
    selectedModelId: custom.id,
    inputs: legacy.CalculatorInputs(
      count: 37,
      prices: legacy.Prices.defaults.copyWith(
        concrete: 599.5,
        steel14: 530.25,
        steel8: 610.75,
        carpenter: 74.5,
        steelWorker: 33.5,
        casting: 66.5,
      ),
    ),
  );
}

const _v2Key = 'hasr_project_state_v2';

// The wire format from the previous build: no v3 fields or v3 model instances.
String _v2Fixture() {
  Map<String, Object?> roofModel(double coefficient) => {
    'id': 'my-custom-roof',
    'kind': 'roof',
    'name': 'سقف بحسب الطول',
    'description': 'نموذج بمدخل واحد',
    'inputUnit': 'linear',
    'rows': [
      {
        'id': 'legacy-concrete',
        'label': 'خرسانة مسلحة',
        'materialId': 'concrete',
        'unit': 'volume',
        'sourceUnit': null,
        'coefficient': .1,
        'divisor': 1,
        'defaultPrice': 520,
        'reviewBasis': false,
      },
      {
        'id': 'roof25-carpenter',
        'label': 'نجار خاص',
        'materialId': null,
        'unit': 'volume',
        'sourceUnit': null,
        'coefficient': coefficient,
        'divisor': 1,
        'defaultPrice': 95,
        'reviewBasis': false,
      },
    ],
  };
  Map<String, Object?> project(String id, {required bool legacyRoof}) => {
    'id': id,
    'name': 'مشروع $id',
    'date': '2026-11-08',
    'location': 'بنغازي',
    'works': [
      for (final kind in [
        'foundations',
        'belowMasonry',
        'tieBeam',
        'leanSlab',
        'columns',
        'aboveMasonry',
        'roof',
      ])
        {
          'kind': kind,
          'included': kind == 'roof' && legacyRoof,
          'quantity': switch (kind) {
            'roof' => legacyRoof ? 12.5 : 199.5,
            'tieBeam' => 105,
            _ => null,
          },
          'model': kind == 'roof' && legacyRoof ? roofModel(2) : null,
          'priceOverrides': {
            if (kind == 'roof' && legacyRoof) 'legacy-concrete': 555,
          },
        },
    ],
    'materialPrices': {'cement': legacyRoof ? 40 : 48, 'steel8': null},
    'servicePrices': {'columns|casting|column': 39},
    'isExample': false,
  };
  return jsonEncode({
    'version': 2,
    'projects': [
      project('first', legacyRoof: false),
      project('selected', legacyRoof: true),
    ],
    'currentProjectId': 'selected',
    'customModels': [roofModel(3)],
  });
}

void main() {
  test(
    'v2 migration keeps project selection, custom roof basis and prices',
    () async {
      final store = MemoryProjectStore();
      final raw = _v2Fixture();
      final v1 = jsonEncode(oldData().toJson());
      store.values.addAll({_v2Key: raw, AppRepository.storageKey: v1});
      final repository = ProjectRepository(store: store);
      final result = await repository.load();

      expect(result.warning, isNull);
      expect(repository.canWrite, isTrue);
      expect(result.data.currentProjectId, 'selected');
      expect(result.data.projects.map((project) => project.id), [
        'first',
        'selected',
      ]);
      final current = result.data.currentProject;
      final roof = current.work(WorkKind.roof);
      expect(roof.model!.id, 'my-custom-roof');
      expect(roof.quantity, 12.5);
      expect(roof.inputUnit, QuantityUnit.linear);
      expect(roof.requiresRoofBeamLength, isFalse);
      expect(roof.roofBeamLength, isNull);
      expect(roof.model!.rows.last.coefficient, 2);
      expect(result.data.customModels.single.rows.last.coefficient, 3);
      expect(roof.priceOverrides, {'legacy-concrete': 555.0});
      expect(current.materialPrices['cement'], 40);
      expect(current.materialPrices['steel6'], 260);
      expect(current.materialPrices['hollowBlock'], 1.8);
      expect(current.materialPrices.containsKey('steel8'), isTrue);
      expect(current.materialPrices['steel8'], isNull);
      expect(current.servicePrices['columns|casting|column'], 39);
      expect(current.profitPercentage, 0);
      expect(current.calculatedProject, isNull);
      final calculated = calculateProject(current).work(WorkKind.roof);
      expect(calculated.status, WorkStatus.calculated);
      expect(calculated.cost, closeTo(3068.75, 1e-8));
      expect(calculated.lines.last.unitPrice, 95);
      final first = result.data.projects.first;
      expect(first.materialPrices['cement'], 48);
      expect(first.work(WorkKind.tieBeam).quantity, 105);
      expect(first.work(WorkKind.tieBeam).explicitlyExcluded, isTrue);
      expect(first.work(WorkKind.roof).model!.id, roofModelId);
      expect(first.work(WorkKind.roof).quantity, 199.5);
      expect(first.work(WorkKind.roof).roofBeamLength, isNull);
      expect(first.work(WorkKind.roof).included, isFalse);
      expect(store.values[_v2Key], raw);
      expect(store.values[AppRepository.storageKey], v1);
      expect(store.values[ProjectRepository.previousBackupKey], raw);
      expect(store.writes, [
        ProjectRepository.previousBackupKey,
        ProjectRepository.storageKey,
        ProjectRepository.previousMigrationMarkerKey,
      ]);
      final reopened = await ProjectRepository(store: store).load();
      expect(reopened.data.toJson(), result.data.toJson());
      expect(store.writes, hasLength(3));
    },
  );

  for (final failKey in [
    ProjectRepository.previousBackupKey,
    ProjectRepository.storageKey,
  ]) {
    test(
      'v2 migration retries safely after write failure at $failKey',
      () async {
        final raw = _v2Fixture();
        final store = MemoryProjectStore()..failKey = failKey;
        store.values[_v2Key] = raw;
        final repository = ProjectRepository(store: store);
        final failed = await repository.load();
        expect(failed.warning, isNotNull);
        expect(repository.canWrite, isFalse);
        expect(store.values[ProjectRepository.storageKey], isNull);
        expect(
          store.values[ProjectRepository.previousMigrationMarkerKey],
          isNull,
        );
        expect(store.values[_v2Key], raw);
        if (failKey == ProjectRepository.storageKey) {
          expect(store.values[ProjectRepository.previousBackupKey], raw);
        }
        await expectLater(repository.save(failed.data), throwsStateError);

        store.failKey = null;
        final retry = ProjectRepository(store: store);
        final recovered = await retry.load();
        expect(recovered.warning, isNull);
        expect(retry.canWrite, isTrue);
        expect(recovered.data.projects, hasLength(2));
        expect(recovered.data.customModels, hasLength(1));
        expect(store.values[ProjectRepository.previousBackupKey], raw);
        expect(store.values[ProjectRepository.previousMigrationMarkerKey], '3');
      },
    );
  }

  test(
    'corrupt v2 source is backed up and never replaced with older v1 data',
    () async {
      final store = MemoryProjectStore();
      store.values.addAll({
        _v2Key: '{broken',
        AppRepository.storageKey: jsonEncode(oldData().toJson()),
      });
      final repository = ProjectRepository(store: store);
      final result = await repository.load();
      expect(result.warning, isNotNull);
      expect(repository.canWrite, isFalse);
      expect(store.values[_v2Key], '{broken');
      expect(store.values[ProjectRepository.previousBackupKey], '{broken');
      expect(store.values[ProjectRepository.storageKey], isNull);
      expect(
        store.values[ProjectRepository.previousMigrationMarkerKey],
        isNull,
      );
    },
  );

  test(
    'v1 migration preserves fractional custom model identity inputs and all six prices',
    () async {
      final store = MemoryProjectStore();
      final old = oldData();
      final raw = jsonEncode(old.toJson());
      store.values[AppRepository.storageKey] = raw;
      final repo = ProjectRepository(store: store);
      final result = await repo.load();
      expect(result.warning, isNull);
      final project = result.data.currentProject;
      expect(project.name, 'مشروعي السابق');
      expect(project.work(WorkKind.foundations).quantity, 37);
      final model = project.work(WorkKind.foundations).model!;
      expect(model.id, old.selectedModelId);
      expect(model.rows.first.coefficient, .8137);
      expect(model.rows[1].coefficient, 3.75);
      expect(model.rows[1].divisor, 6.3);
      expect(model.rows[2].coefficient, 1.8);
      expect(model.rows[2].divisor, 19.5);
      expect(result.data.customModels.single.id, old.selectedModelId);
      expect(project.materialPrices['concrete'], 599.5);
      expect(project.materialPrices['steel14'], 530.25);
      expect(project.materialPrices['steel8'], 610.75);
      final lines = calculateProject(project).work(WorkKind.foundations).lines;
      expect(
        lines.firstWhere((line) => line.row.id == 'carpenter').unitPrice,
        74.5,
      );
      expect(
        lines.firstWhere((line) => line.row.id == 'steelWorker').unitPrice,
        33.5,
      );
      expect(
        lines.firstWhere((line) => line.row.id == 'casting').unitPrice,
        66.5,
      );
      for (final work in project.works.where(
        (work) => work.kind != WorkKind.foundations,
      )) {
        expect(work.included, isFalse);
        expect(work.quantity, isNull);
      }
      expect(store.values[AppRepository.storageKey], raw);
      expect(store.values[ProjectRepository.legacyBackupKey], raw);
      expect(
        store.writes.indexOf(ProjectRepository.legacyBackupKey),
        lessThan(store.writes.indexOf(ProjectRepository.storageKey)),
      );
      expect(
        store.writes.indexOf(ProjectRepository.storageKey),
        lessThan(store.writes.indexOf(ProjectRepository.migrationMarkerKey)),
      );
    },
  );

  test(
    'migration repeats safely and never duplicates models or projects',
    () async {
      final store = MemoryProjectStore();
      store.values[AppRepository.storageKey] = jsonEncode(oldData().toJson());
      final first = await ProjectRepository(store: store).load();
      final writes = store.writes.length;
      final second = await ProjectRepository(store: store).load();
      expect(second.data.projects.length, 1);
      expect(second.data.customModels.length, 1);
      expect(second.data.toJson(), first.data.toJson());
      expect(store.writes.length, writes);
    },
  );

  test(
    'failed new-state save keeps original bytes and no success marker, retries on reopening',
    () async {
      final store = MemoryProjectStore()
        ..failKey = ProjectRepository.storageKey;
      final raw = jsonEncode(oldData().toJson());
      store.values[AppRepository.storageKey] = raw;
      final repo = ProjectRepository(store: store);
      final failed = await repo.load();
      expect(failed.warning, isNotNull);
      expect(repo.canWrite, isFalse);
      expect(store.values[AppRepository.storageKey], raw);
      expect(store.values[ProjectRepository.legacyBackupKey], raw);
      expect(store.values[ProjectRepository.migrationMarkerKey], isNull);
      expect(store.values[ProjectRepository.storageKey], isNull);
      await expectLater(repo.save(failed.data), throwsStateError);
      store.failKey = null;
      final retried = await ProjectRepository(store: store).load();
      expect(retried.warning, isNull);
      expect(retried.data.projects.length, 1);
      expect(retried.data.customModels.length, 1);
    },
  );

  test('failed backup does not save new state or marker', () async {
    final store = MemoryProjectStore()
      ..failKey = ProjectRepository.legacyBackupKey;
    final raw = jsonEncode(oldData().toJson());
    store.values[AppRepository.storageKey] = raw;
    final repo = ProjectRepository(store: store);
    await repo.load();
    expect(repo.canWrite, isFalse);
    expect(store.values[AppRepository.storageKey], raw);
    expect(store.values[ProjectRepository.storageKey], isNull);
    expect(store.values[ProjectRepository.migrationMarkerKey], isNull);
  });

  test(
    'marker failure after saved snapshot does not repeat migration on next load',
    () async {
      final store = MemoryProjectStore()
        ..failKey = ProjectRepository.migrationMarkerKey;
      store.values[AppRepository.storageKey] = jsonEncode(oldData().toJson());
      final first = await ProjectRepository(store: store).load();
      expect(first.warning, isNotNull);
      expect(store.values[ProjectRepository.storageKey], isNotNull);
      store.failKey = null;
      final secondRepo = ProjectRepository(store: store);
      final second = await secondRepo.load();
      expect(second.warning, isNull);
      expect(secondRepo.canWrite, isTrue);
      expect(second.data.projects.length, 1);
      expect(second.data.customModels.length, 1);
    },
  );

  test(
    'corrupt legacy and current state remain untouched with writes blocked',
    () async {
      for (final key in [
        AppRepository.storageKey,
        ProjectRepository.storageKey,
      ]) {
        final store = MemoryProjectStore();
        store.values[key] = '{broken';
        final repo = ProjectRepository(store: store);
        final result = await repo.load();
        expect(result.warning, isNotNull);
        expect(repo.canWrite, isFalse);
        expect(store.values[key], '{broken');
        await expectLater(repo.save(result.data), throwsStateError);
      }
    },
  );

  test(
    'unreadable storage and save-before-load cannot overwrite data',
    () async {
      final store = MemoryProjectStore()..failRead = true;
      final repo = ProjectRepository(store: store);
      final project = createProject();
      final state = ProjectState(
        projects: [project],
        currentProjectId: project.id,
      );
      await expectLater(repo.save(state), throwsStateError);
      final result = await repo.load();
      expect(result.warning, isNotNull);
      expect(store.writes, isEmpty);
      expect(repo.canWrite, isFalse);
    },
  );

  test(
    'save/reopen preserves second project, independent price and model snapshots',
    () async {
      final store = MemoryProjectStore();
      final repo = ProjectRepository(store: store);
      final initial = (await repo.load()).data;
      final second = createExampleProject(id: 'second');
      final altered = second.copyWith(
        materialPrices: {...second.materialPrices, 'cement': 40},
      );
      final state = initial
          .updateProject(altered)
          .copyWith(currentProjectId: second.id);
      await repo.save(state);
      final reopened = (await ProjectRepository(store: store).load()).data;
      expect(reopened.currentProjectId, 'second');
      expect(reopened.projects.length, 2);
      expect(reopened.projects.first.materialPrices['cement'], 42);
      expect(reopened.currentProject.materialPrices['cement'], 40);
      expect(
        calculateProject(reopened.currentProject).totalCost,
        closeTo(86026.2, 1e-8),
      );
      expect(reopened.toJson(), state.toJson());
    },
  );

  test(
    'queued saves keep snapshot order and recover after a failed write',
    () async {
      final store = MemoryProjectStore();
      final repo = ProjectRepository(store: store);
      final state = (await repo.load()).data;
      store.failKey = ProjectRepository.storageKey;
      await expectLater(repo.save(state), throwsStateError);
      store.failKey = null;
      final second = state.updateProject(
        state.currentProject.copyWith(name: 'ثانٍ'),
      );
      final third = state.updateProject(
        state.currentProject.copyWith(name: 'ثالث'),
      );
      await Future.wait([repo.save(second), repo.save(third)]);
      await repo.flush();
      final reopened = (await ProjectRepository(store: store).load()).data;
      expect(reopened.currentProject.name, 'ثالث');
    },
  );

  test(
    'nullable drafts round-trip without becoming a prior valid value',
    () async {
      final store = MemoryProjectStore();
      final repo = ProjectRepository(store: store);
      final state = (await repo.load()).data;
      final project = state.currentProject.updateWork(
        state.currentProject
            .work(WorkKind.foundations)
            .copyWith(quantity: null),
      );
      await repo.save(state.updateProject(project));
      final reopened = (await ProjectRepository(store: store).load()).data;
      expect(
        reopened.currentProject.work(WorkKind.foundations).quantity,
        isNull,
      );
      expect(
        calculateProject(
          reopened.currentProject,
        ).work(WorkKind.foundations).status,
        WorkStatus.needsData,
      );
    },
  );
}
