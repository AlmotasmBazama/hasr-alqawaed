import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hasr_alqawaed/data/app_repository.dart';
import 'package:hasr_alqawaed/main.dart';
import 'package:hasr_alqawaed/project/catalog.dart';
import 'package:hasr_alqawaed/project/controller.dart';
import 'package:hasr_alqawaed/project/engine.dart';
import 'package:hasr_alqawaed/project/models.dart';
import 'package:hasr_alqawaed/project/repository.dart';
import 'package:hasr_alqawaed/ui/app_theme.dart';
import 'package:hasr_alqawaed/ui/work_model_editor.dart';

class MemoryStore implements KeyValueStore {
  MemoryStore({Project? project}) {
    if (project != null) {
      values[ProjectRepository.storageKey] = jsonEncode(
        ProjectState(
          projects: [project],
          currentProjectId: project.id,
        ).toJson(),
      );
    }
  }
  final values = <String, String>{};
  Completer<void>? gate;
  bool fail = false;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    await gate?.future;
    if (fail) throw StateError('disk unavailable');
    values[key] = value;
  }

  ProjectState get saved =>
      ProjectState.fromJson(jsonDecode(values[ProjectRepository.storageKey]!));
}

Finder field(String key) => find.descendant(
  of: find.byKey(ValueKey(key)),
  matching: find.byType(TextField),
);
Future<void> reveal(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  test(
    'blank live drafts invalidate estimates and preserve last valid save',
    () async {
      final store = MemoryStore(project: createExampleProject(id: 'example'));
      final controller = ProjectController(ProjectRepository(store: store));
      await controller.load();
      final snapshot = controller.result;
      controller.quantity(WorkKind.tieBeam, '');
      expect(
        controller.result.work(WorkKind.tieBeam).status,
        WorkStatus.needsData,
      );
      expect(controller.result.totalCost, closeTo(41267.2, .000001));
      expect(snapshot.totalCost, closeTo(86364.2, .000001));
      await controller.saveNow();
      expect(store.saved.currentProject.work(WorkKind.tieBeam).quantity, 130);
      controller.quantity(WorkKind.tieBeam, '٣٫٥');
      expect(controller.result.work(WorkKind.tieBeam).entry.quantity, 3.5);
      controller.quantity(WorkKind.foundations, '٣٫٥');
      expect(controller.result.work(WorkKind.foundations).cost, isNull);
      controller.materialPrice('cement', '');
      expect(controller.result.work(WorkKind.belowMasonry).cost, isNull);
      expect(controller.result.work(WorkKind.aboveMasonry).cost, isNull);
      controller.dispose();
    },
  );

  test(
    'project prices, drafts, model snapshots and overrides remain independent',
    () async {
      final store = MemoryStore(project: createExampleProject(id: 'example'));
      final controller = ProjectController(ProjectRepository(store: store));
      await controller.load();
      controller.materialPrice('cement', '40');
      expect(controller.result.totalCost, closeTo(86026.2, .000001));
      final beam = controller.project.work(WorkKind.tieBeam);
      final row = beam.model!.rows.first;
      controller.overridePrice(WorkKind.tieBeam, row, '600');
      expect(
        controller.result.work(WorkKind.tieBeam).lines.first.overridden,
        isTrue,
      );
      controller.clearOverride(WorkKind.tieBeam, row);
      expect(controller.result.totalCost, closeTo(86026.2, .000001));
      await controller.addProject(example: true);
      final second = controller.savedProject.id;
      expect(controller.result.totalCost, closeTo(86364.2, .000001));
      await controller.selectModel(
        WorkKind.tieBeam,
        beam.model!.copyWith(
          id: 'custom-beam',
          rows: [row.copyWith(coefficient: .16), ...beam.model!.rows.skip(1)],
        ),
        register: true,
      );
      expect(
        controller.result.work(WorkKind.tieBeam).cost,
        closeTo(24908, .000001),
      );
      await controller.selectProject('example');
      expect(
        controller.result.work(WorkKind.tieBeam).entry.model!.id,
        beam.model!.id,
      );
      expect(controller.result.totalCost, closeTo(86026.2, .000001));
      await controller.selectProject(second);
      await controller.saveNow();
      final restored = await ProjectRepository(store: store).load();
      expect(restored.data.currentProject.id, second);
      expect(
        restored.data.currentProject.work(WorkKind.tieBeam).model!.id,
        'custom-beam',
      );
      controller.dispose();
    },
  );

  test(
    'slow atomic model save cannot be overwritten by lifecycle save',
    () async {
      final store = MemoryStore(project: createExampleProject(id: 'example'));
      final controller = ProjectController(ProjectRepository(store: store));
      await controller.load();
      final old = controller.savedProject.work(WorkKind.tieBeam).model!;
      final changed = old.copyWith(id: 'custom-beam', name: 'نموذج محفوظ');
      store.gate = Completer<void>();
      final saving = controller.selectModel(
        WorkKind.tieBeam,
        changed,
        register: true,
      );
      expect(controller.saving, isTrue);
      await controller.saveNow();
      expect(controller.savedProject.work(WorkKind.tieBeam).model!.id, old.id);
      store.gate!.complete();
      await saving;
      await controller.repository.flush();
      expect(
        store.saved.currentProject.work(WorkKind.tieBeam).model!.id,
        'custom-beam',
      );
      expect(store.saved.customModels.single.name, 'نموذج محفوظ');
      store.gate = null;
      store.fail = true;
      await expectLater(
        controller.selectModel(
          WorkKind.tieBeam,
          changed.copyWith(name: 'فشل'),
          register: true,
        ),
        throwsStateError,
      );
      expect(
        controller.savedProject.work(WorkKind.tieBeam).model!.name,
        'نموذج محفوظ',
      );
      controller.dispose();
    },
  );

  testWidgets(
    'explicit calculations use the current draft and prevent stale PDF export',
    (tester) async {
      final store = MemoryStore(project: createExampleProject(id: 'example'));
      await tester.pumpWidget(
        HasrApp(repository: ProjectRepository(store: store)),
      );
      await tester.pumpAndSettle();
      final results = find.byKey(const ValueKey('tab_results'));
      final calculate = find.byKey(const ValueKey('calculate_project'));
      final update = find.byKey(const ValueKey('recalculate_project'));
      final export = find.byKey(const ValueKey('export_project_pdf'));
      await tester.tap(results);
      await tester.pumpAndSettle();
      expect(find.text('لم يُحسب المشروع بعد'), findsOneWidget);
      expect(export, findsNothing);
      await tester.tap(update);
      await tester.pumpAndSettle();
      await tester.tap(calculate);
      await tester.pumpAndSettle();
      expect(find.text('86,364.20'), findsOneWidget);
      expect(tester.widget<ButtonStyleButton>(export).onPressed, isNotNull);

      await tester.tap(find.byKey(const ValueKey('tab_project')));
      await tester.pumpAndSettle();
      final quantity = field('example:quantity:foundations');
      await reveal(tester, quantity);
      await tester.enterText(quantity, '');
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(quantity).controller!.text, '');
      await tester.tap(results);
      await tester.pumpAndSettle();
      expect(find.text('الحسبة تحتاج تحديثًا'), findsOneWidget);
      expect(find.text('86,364.20'), findsNothing);
      expect(export, findsNothing);
      await tester.tap(update);
      await tester.pumpAndSettle();
      expect(find.text('68,564.20'), findsOneWidget);
      expect(find.text('حصر جزئي — توجد بنود غير مكتملة'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('tab_prices')));
      await tester.pumpAndSettle();
      final cement = field('example:price:cement');
      await reveal(tester, cement);
      await tester.enterText(cement, '٤٠');
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(cement).controller!.text, '٤٠');
      expect(tester.widget<TextField>(cement).focusNode!.hasFocus, isTrue);
      await tester.tap(results);
      await tester.pumpAndSettle();
      expect(find.text('الحسبة تحتاج تحديثًا'), findsOneWidget);
      expect(export, findsNothing);
      await tester.tap(find.byKey(const ValueKey('tab_project')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(quantity).controller!.text, '');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(store.saved.currentProject.materialPrices['cement'], 40);
      expect(
        store.saved.currentProject.work(WorkKind.foundations).quantity,
        20,
      );
      await tester.pumpWidget(
        HasrApp(repository: ProjectRepository(store: store)),
      );
      await tester.pumpAndSettle();
      await tester.tap(results);
      await tester.pumpAndSettle();
      expect(find.text('الحسبة تحتاج تحديثًا'), findsOneWidget);
      expect(export, findsNothing);
    },
  );

  testWidgets(
    'positive edits enter the scope, exclusion retains values, and zero is explicit',
    (tester) async {
      final store = MemoryStore(project: createProject(id: 'blank'));
      await tester.pumpWidget(
        HasrApp(repository: ProjectRepository(store: store)),
      );
      await tester.pumpAndSettle();
      final quantity = field('blank:quantity:foundations');
      final include = find.byKey(const ValueKey('include_foundations'));
      final calculate = find.byKey(const ValueKey('calculate_project'));
      expect(tester.widget<TextField>(quantity).controller!.text, '');
      await reveal(tester, quantity);
      await tester.enterText(quantity, '٢');
      await tester.pumpAndSettle();
      expect(find.text('جاهز للحساب'), findsOneWidget);
      await reveal(tester, include);
      await tester.tap(include);
      await tester.pumpAndSettle();
      expect(quantity, findsNothing);
      expect(find.text('إضافة للحصر'), findsOneWidget);
      await tester.tap(calculate);
      await tester.pumpAndSettle();
      expect(store.saved.currentProject.work(WorkKind.foundations).quantity, 2);
      expect(
        store.saved.currentProject
            .work(WorkKind.foundations)
            .explicitlyExcluded,
        isTrue,
      );

      await tester.tap(find.byKey(const ValueKey('tab_project')));
      await tester.pumpAndSettle();
      await reveal(tester, include);
      await tester.tap(include);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(quantity).controller!.text, '٢');
      await tester.tap(calculate);
      await tester.pumpAndSettle();
      expect(find.text('1,780.00'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('tab_project')));
      await tester.pumpAndSettle();
      await reveal(tester, quantity);
      await tester.enterText(quantity, '٠');
      await tester.pumpAndSettle();
      expect(find.text('لا توجد كمية'), findsOneWidget);
    },
  );

  testWidgets(
    'masonry lengths follow a single field and support a per-row custom length',
    (tester) async {
      final store = MemoryStore(project: createProject(id: 'group'));
      await tester.pumpWidget(
        HasrApp(repository: ProjectRepository(store: store)),
      );
      await tester.pumpAndSettle();
      final beam = field('group:quantity:tieBeam');
      final upper = field('group:quantity:aboveMasonry');
      Future<void> tapKey(String key) async {
        final target = find.byKey(ValueKey(key));
        await reveal(tester, target);
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      Future<void> enter(Finder input, String value) async {
        await reveal(tester, input);
        await tester.enterText(input, value);
        await tester.pumpAndSettle();
      }

      expect(upper, findsNothing);
      await enter(beam, '١٣٠');
      expect(
        find.text('مباني تحت الكتينة: 130 م — نفس طول الميدة'),
        findsOneWidget,
      );
      expect(
        find.text('مباني فوق الكتينة: 130 م — نفس طول الميدة'),
        findsOneWidget,
      );
      await tapKey('edit_length_aboveMasonry');
      await enter(upper, '١٧٠');
      await enter(beam, '١٦٠');
      expect(
        find.text('مباني تحت الكتينة: 160 م — نفس طول الميدة'),
        findsOneWidget,
      );
      expect(find.text('مباني فوق الكتينة: 170 م — طول مخصص'), findsOneWidget);
      await tapKey('include_belowMasonry');
      await enter(beam, '');
      expect(find.text('مباني فوق الكتينة: 170 م — طول مخصص'), findsOneWidget);
      expect(
        find.text('مباني تحت الكتينة: يحتاج طول الميدة — نفس طول الميدة'),
        findsOneWidget,
      );
      await enter(beam, '٠');
      expect(
        find.text('مباني تحت الكتينة: 0 م — نفس طول الميدة'),
        findsOneWidget,
      );
      await tapKey('relink_aboveMasonry');
      expect(upper, findsNothing);
      expect(
        find.text('مباني فوق الكتينة: 0 م — نفس طول الميدة'),
        findsOneWidget,
      );
      await enter(beam, '١٥٠');
      expect(
        find.text('مباني فوق الكتينة: 150 م — نفس طول الميدة'),
        findsOneWidget,
      );
      expect(
        store.saved.currentProject
            .work(WorkKind.belowMasonry)
            .explicitlyExcluded,
        isTrue,
      );
    },
  );

  testWidgets(
    'roof keeps area separate from beam length including an entered zero',
    (tester) async {
      final store = MemoryStore(project: createProject(id: 'blank'));
      await tester.pumpWidget(
        HasrApp(repository: ProjectRepository(store: store)),
      );
      await tester.pumpAndSettle();
      final area = field('blank:quantity:roof');
      final beams = field('blank:roof_beam_length');
      final calculate = find.byKey(const ValueKey('calculate_project'));
      await reveal(tester, area);
      await tester.enterText(area, '٢٠٠');
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(beams).controller!.text, '');
      await tester.tap(calculate);
      await tester.pumpAndSettle();
      final missing = find.textContaining('البنود غير المكتملة:');
      expect(tester.widget<Text>(missing).data, contains('السقف'));

      await tester.tap(find.byKey(const ValueKey('tab_project')));
      await tester.pumpAndSettle();
      await reveal(tester, beams);
      await tester.enterText(beams, '٠');
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(area).controller!.text, '٢٠٠');
      await tester.tap(calculate);
      await tester.pumpAndSettle();
      expect(find.text('46,097.50'), findsOneWidget);
      expect(tester.widget<Text>(missing).data, isNot(contains('السقف')));
    },
  );

  testWidgets(
    'first price override keeps focus and clears back to shared price',
    (tester) async {
      final store = MemoryStore(project: createExampleProject(id: 'example'));
      await tester.pumpWidget(
        HasrApp(repository: ProjectRepository(store: store)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('work_foundations')));
      await tester.pumpAndSettle();
      final override = field('example:override:foundations:concrete');
      await reveal(tester, override);
      await tester.enterText(override, '600');
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(override).focusNode!.hasFocus, isTrue);
      final reset = find.text('إلغاء التخصيص واستخدام السعر المشترك').first;
      await reveal(tester, reset);
      await tester.tap(reset);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(override).controller!.text, '560');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('small phone, keyboard and large text have no layout errors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.view.resetViewInsets);
    final store = MemoryStore(project: createExampleProject(id: 'example'));
    await tester.pumpWidget(
      HasrApp(repository: ProjectRepository(store: store)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final tab in ['tab_prices', 'tab_results', 'tab_project']) {
      await tester.tap(find.byKey(ValueKey(tab)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pumpAndSettle();
    final quantity = field('example:quantity:foundations');
    await reveal(tester, quantity);
    await tester.enterText(quantity, '٢١');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('model editor validates divisors and saves custom identity', (
    tester,
  ) async {
    WorkModel? saved;
    final initial = defaultModel(
      WorkKind.leanSlab,
    )!.copyWith(id: 'custom-slab');
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => WorkModelEditor(
                      kind: WorkKind.leanSlab,
                      initial: initial,
                      onSave: (model) async => saved = model,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final divisor = find.byKey(const ValueKey('divisor_0'));
    await reveal(tester, divisor);
    await tester.enterText(divisor, '0');
    final save = find.byKey(const ValueKey('save_work_model'));
    await reveal(tester, save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(saved, isNull);
    await reveal(tester, divisor);
    expect(find.text('أدخل عددًا أكبر من صفر'), findsOneWidget);
    await tester.enterText(divisor, '٢');
    await reveal(tester, save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(saved!.id, 'custom-slab');
    expect(saved!.rows.first.divisor, 2);
    expect(saved!.rows.length, 4);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('a custom roof line accepts a chosen beam length source', (
    tester,
  ) async {
    WorkModel? saved;
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => WorkModelEditor(
                      kind: WorkKind.roof,
                      onSave: (model) async => saved = model,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('coefficient_0')), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('model_name')),
      'سقف مخصص',
    );
    final add = find.byKey(const ValueKey('add_model_row'));
    await reveal(tester, add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    await tester.tap(find.text('خرسانة مسلحة'));
    await tester.pumpAndSettle();
    final source = find.byKey(const ValueKey('roof_source_0'));
    await reveal(tester, source);
    await tester.tap(source);
    await tester.pumpAndSettle();
    await tester.tap(find.text('أطوال الكمرات').last);
    await tester.pumpAndSettle();
    final coefficient = find.byKey(const ValueKey('coefficient_0'));
    await reveal(tester, coefficient);
    await tester.enterText(coefficient, '٠٫٢');
    final save = find.byKey(const ValueKey('save_work_model'));
    await reveal(tester, save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(saved!.kind, WorkKind.roof);
    expect(saved!.inputUnit, QuantityUnit.area);
    expect(saved!.rows.single.coefficient, .2);
    expect(saved!.rows.single.materialId, 'concrete');
    expect(saved!.rows.single.quantitySource, QuantitySource.roofBeamLength);
    expect(saved!.isBuiltIn, isFalse);
  });
}
