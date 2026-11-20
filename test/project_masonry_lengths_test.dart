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

void main() {
  test(
    'linked masonry uses the beam input in every row and freezes it in quotations',
    () async {
      final c = await _open(_Store());
      c.quantity(beam, '١٣٠');
      expect(c.result.calculatedCount, 3);
      for (final kind in [below, above]) {
        expect(c.savedProject.work(kind).included, isTrue);
        expect(c.savedProject.work(kind).quantity, isNull);
        expect(
          c.result.work(kind).lines.every((line) => line.inputQuantity == 130),
          isTrue,
        );
      }
      expect(c.result.work(below).cost, closeTo(6383, 1e-8));
      expect(c.result.work(above).cost, closeTo(19630, 1e-8));
      expect(c.result.work(WorkKind.roof).entry.quantity, isNull);
      expect(c.result.work(WorkKind.roof).entry.roofBeamLength, isNull);
      await c.calculate();
      c.quantity(beam, '150');
      expect(c.needsRecalculation, isTrue);
      expect(c.calculatedResult!.work(above).entry.quantity, 130);
      expect(c.result.work(below).entry.quantity, 150);
      expect(c.result.work(above).entry.quantity, 150);
      c.setLinkedToTieBeam(above, false);
      expect(c.project.work(above).quantity, 150);
      c.quantity(above, '١٧٠');
      c.quantity(beam, '160');
      expect(c.result.work(below).entry.quantity, 160);
      expect(c.result.work(above).entry.quantity, 170);
      expect(c.result.work(above).cost, closeTo(19630 * 170 / 130, 1e-8));
      c.setLinkedToTieBeam(above, true);
      expect(c.result.work(above).entry.quantity, 160);
      c.quantity(beam, '١٦٠٫٥');
      expect(c.result.work(above).entry.quantity, 160.5);
      expect(
        c.result.work(above).lines.every((line) => line.inputQuantity == 160.5),
        isTrue,
      );
    },
  );

  test(
    'exclusions, missing beam input, zero and an independent length survive reopening',
    () async {
      final store = _Store();
      final c = await _open(store);
      c.quantity(beam, '130');
      c.setLinkedToTieBeam(above, false);
      c.quantity(above, '170');
      c.include(below, false);
      c.quantity(beam, '150');
      expect(c.result.work(below).status, WorkStatus.excluded);
      expect(c.result.work(below).entry.quantity, 150);
      c.include(below, true);
      expect(c.result.work(below).entry.quantity, 150);
      c.include(beam, false);
      c.quantity(beam, '160');
      expect(c.result.work(beam).status, WorkStatus.excluded);
      expect(c.result.work(below).entry.quantity, 160);
      c.quantity(beam, '0');
      expect(c.result.work(below).status, WorkStatus.zeroQuantity);
      for (final raw in ['', 'خطأ', '-5']) {
        c.quantity(beam, raw);
        expect(c.result.work(below).status, WorkStatus.needsData);
        expect(c.result.work(below).entry.quantity, isNull);
        expect(c.result.work(above).entry.quantity, 170);
        expect(c.result.work(above).status, WorkStatus.calculated);
      }
      await c.calculate();
      c.include(below, false);
      await c.repository.flush();
      final reopened = await _open(store);
      expect(reopened.needsRecalculation, isTrue);
      expect(reopened.calculatedResult!.work(below).entry.quantity, isNull);
      expect(reopened.result.work(below).entry.quantity, isNull);
      expect(reopened.result.work(above).entry.quantity, 170);
      expect(reopened.result.work(above).entry.linkedToTieBeam, isFalse);
      reopened.quantity(beam, '200');
      expect(reopened.result.work(below).status, WorkStatus.excluded);
      reopened.include(below, true);
      expect(reopened.result.work(below).entry.quantity, 200);
      expect(reopened.result.work(below).status, WorkStatus.calculated);
    },
  );

  test(
    'old equal lengths, snapshots, prices, models and exclusions keep independent semantics',
    () async {
      final base = createExampleProject(id: 'old-v3');
      final model = base
          .work(above)
          .model!
          .copyWith(id: 'historic-model', name: 'نموذج محفوظ');
      final old = base.updateWork(
        base
            .work(above)
            .copyWith(
              model: model,
              priceOverrides: {'cement': 57},
              included: false,
            ),
      );
      final payload = ProjectState(
        projects: [old.copyWith(calculatedProject: old)],
        currentProjectId: old.id,
      ).toJson();
      final raw = jsonEncode(payload);
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final original = map['projects'].first;
      for (final project in [original, original['calculatedProject']]) {
        for (final work in project['works']) {
          work.remove('linkedToTieBeam');
        }
      }
      final legacy = jsonEncode(map);
      final store = _Store()..values[ProjectRepository.storageKey] = legacy;
      final c = await _open(store);
      expect(store.values[ProjectRepository.storageKey], legacy);
      expect(c.needsRecalculation, isFalse);
      expect(c.calculatedResult!.work(below).entry.linkedToTieBeam, isFalse);
      c.quantity(beam, '150');
      expect(c.result.work(below).entry.quantity, 130);
      expect(c.result.work(above).entry.quantity, 130);
      expect(c.result.work(above).status, WorkStatus.excluded);
      c.setLinkedToTieBeam(above, true);
      expect(c.result.work(above).entry.quantity, 150);
      expect(c.result.work(above).status, WorkStatus.excluded);
      await c.repository.flush();
      final reopened = await _open(store);
      expect(reopened.result.work(above).entry.linkedToTieBeam, isTrue);
      expect(reopened.result.work(above).entry.priceOverrides['cement'], 57);
      expect(reopened.result.work(above).entry.model!.id, model.id);
      expect(reopened.result.work(below).entry.linkedToTieBeam, isFalse);
    },
  );
}
