import 'dart:async';
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
  Completer<void>? block;
  bool failWrite = false;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    await block?.future;
    if (failWrite) throw StateError('Failed');
    values[key] = value;
  }
}

Future<(ProjectController, _Store)> _controller() async {
  final store = _Store();
  final state = ProjectState(
    projects: [
      createExampleProject(id: 'one'),
      createExampleProject(id: 'two'),
    ],
    currentProjectId: 'one',
  );
  store.values[ProjectRepository.storageKey] = jsonEncode(state.toJson());
  final controller = ProjectController(ProjectRepository(store: store));
  await controller.load();
  return (controller, store);
}

void main() {
  test(
    'service basis changes discard incompatible overrides and stale draft prices',
    () async {
      final (controller, _) = await _controller();
      addTearDown(controller.dispose);
      final old = controller.project.work(WorkKind.belowMasonry).model!;
      final water = old.rows.firstWhere((row) => row.id == 'water');
      controller.overridePrice(WorkKind.belowMasonry, water, '9');
      controller.servicePrice(WorkKind.belowMasonry, water, '7');
      final changed = old.copyWith(
        id: 'custom-water-area',
        rows: [
          for (final row in old.rows)
            row.id == 'water'
                ? row.copyWith(
                    unit: QuantityUnit.area,
                    defaultPrice: 2,
                    coefficient: 3,
                  )
                : row,
        ],
      );
      await controller.selectModel(
        WorkKind.belowMasonry,
        changed,
        register: true,
      );
      final areaRow = changed.rows.firstWhere((row) => row.id == 'water');
      expect(controller.hasOverride(WorkKind.belowMasonry, areaRow), isFalse);
      expect(controller.draft('override:belowMasonry:water', 2), '2');
      final line = controller.result
          .work(WorkKind.belowMasonry)
          .lines
          .firstWhere((line) => line.row.id == 'water');
      expect(line.unitPrice, 2);
      expect(line.unit, QuantityUnit.area);
      expect(line.quantity, 390);
      expect(line.cost, 780);
      expect(controller.project.work(WorkKind.belowMasonry).quantity, 130);
    },
  );

  test(
    'changing roof input unit clears saved amount and transient amount draft',
    () async {
      final (controller, _) = await _controller();
      addTearDown(controller.dispose);
      final material = defaultModel(WorkKind.tieBeam)!.rows.first;
      final area = WorkModel(
        id: 'roof-area',
        kind: WorkKind.roof,
        name: 'سقف مساحة',
        inputUnit: QuantityUnit.area,
        rows: [material],
      );
      await controller.selectModel(WorkKind.roof, area, register: true);
      controller.quantity(WorkKind.roof, '١٠٠');
      expect(
        controller.result.work(WorkKind.roof).status,
        WorkStatus.calculated,
      );
      await controller.selectModel(
        WorkKind.roof,
        area.copyWith(id: 'roof-length', inputUnit: QuantityUnit.linear),
        register: true,
      );
      expect(controller.project.work(WorkKind.roof).quantity, isNull);
      expect(controller.savedProject.work(WorkKind.roof).quantity, isNull);
      expect(controller.draft('quantity:roof', null), isEmpty);
      expect(
        controller.result.work(WorkKind.roof).status,
        WorkStatus.needsData,
      );
      expect(controller.result.work(WorkKind.roof).cost, isNull);
    },
  );

  test(
    'invalid draft remains incomplete across project switching without replacing saved valid input',
    () async {
      final (controller, store) = await _controller();
      addTearDown(controller.dispose);
      controller.quantity(WorkKind.tieBeam, '');
      expect(
        controller.result.work(WorkKind.tieBeam).status,
        WorkStatus.needsData,
      );
      expect(controller.savedProject.work(WorkKind.tieBeam).quantity, 130);
      await controller.selectProject('two');
      expect(controller.result.totalCost, closeTo(86364.2, 1e-8));
      await controller.selectProject('one');
      expect(controller.project.work(WorkKind.tieBeam).quantity, isNull);
      expect(controller.result.totalCost, closeTo(67280.2, 1e-8));
      await controller.saveNow();
      final reopened = (await ProjectRepository(store: store).load()).data;
      expect(reopened.currentProject.work(WorkKind.tieBeam).quantity, 130);
    },
  );

  test(
    'material and override drafts only affect their own project and revert explicitly',
    () async {
      final (controller, _) = await _controller();
      addTearDown(controller.dispose);
      controller.materialPrice('cement', '٤٠');
      expect(controller.result.totalCost, closeTo(86026.2, 1e-8));
      final row = controller.project
          .work(WorkKind.aboveMasonry)
          .model!
          .rows
          .firstWhere((row) => row.id == 'cement');
      controller.overridePrice(WorkKind.aboveMasonry, row, '');
      expect(
        controller.result.work(WorkKind.aboveMasonry).status,
        WorkStatus.needsData,
      );
      await controller.selectProject('two');
      expect(controller.result.totalCost, closeTo(86364.2, 1e-8));
      await controller.selectProject('one');
      expect(controller.hasOverride(WorkKind.aboveMasonry, row), isTrue);
      controller.clearOverride(WorkKind.aboveMasonry, row);
      expect(controller.hasOverride(WorkKind.aboveMasonry, row), isFalse);
      expect(controller.result.totalCost, closeTo(86026.2, 1e-8));
    },
  );

  test(
    'saved custom model preserves input amount and other project snapshots',
    () async {
      final (controller, store) = await _controller();
      addTearDown(controller.dispose);
      controller.quantity(WorkKind.tieBeam, '٣٫٥');
      final original = controller.project.work(WorkKind.tieBeam).model!;
      final model = original.copyWith(
        id: 'custom-test',
        rows: [
          for (final row in original.rows)
            row.id == 'concrete' ? row.copyWith(coefficient: .16) : row,
        ],
      );
      await controller.selectModel(WorkKind.tieBeam, model, register: true);
      expect(controller.project.work(WorkKind.tieBeam).quantity, 3.5);
      final changedCost = controller.result.work(WorkKind.tieBeam).cost;
      expect(changedCost, isNotNull);
      await controller.selectProject('two');
      expect(controller.project.work(WorkKind.tieBeam).model!.id, original.id);
      expect(controller.result.totalCost, closeTo(86364.2, 1e-8));
      final reopened = (await ProjectRepository(store: store).load()).data;
      expect(reopened.customModels.single.id, 'custom-test');
      expect(reopened.projects.first.work(WorkKind.tieBeam).quantity, 3.5);
    },
  );

  test(
    'pending model save resists lifecycle stale autosave and failure keeps prior model',
    () async {
      final (controller, store) = await _controller();
      addTearDown(controller.dispose);
      final old = controller.savedProject.work(WorkKind.tieBeam).model!;
      final custom = old.copyWith(id: 'custom-async');
      store.block = Completer<void>();
      final pending = controller.selectModel(
        WorkKind.tieBeam,
        custom,
        register: true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.saving, isTrue);
      await controller.saveNow();
      store.block!.complete();
      await pending;
      store.block = null;
      final saved = (await ProjectRepository(store: store).load()).data;
      expect(
        saved.currentProject.work(WorkKind.tieBeam).model!.id,
        'custom-async',
      );
      store.failWrite = true;
      await expectLater(
        controller.selectModel(WorkKind.tieBeam, old),
        throwsStateError,
      );
      expect(
        controller.savedProject.work(WorkKind.tieBeam).model!.id,
        'custom-async',
      );
      expect(controller.saving, isFalse);
      expect(controller.warning, isNotNull);
    },
  );
}
