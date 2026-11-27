import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hasr_alqawaed/main.dart';
import 'package:hasr_alqawaed/project/catalog.dart';
import 'package:hasr_alqawaed/project/models.dart';
import 'package:hasr_alqawaed/project/repository.dart';

import 'project_ui_test.dart' show MemoryStore, field;

void main() {
  testWidgets('a migrated length can be accepted or replaced once', (
    tester,
  ) async {
    final project = createExampleProject(id: 'review');
    final old = ProjectState(
      projects: [project],
      currentProjectId: project.id,
    ).toJson();
    old['version'] = 3;
    final works = ((old['projects'] as List).first as Map)['works'] as List;
    for (final work in works.where(
      (row) => row['kind'].toString().endsWith('Masonry'),
    )) {
      work['linkedToTieBeam'] = true;
      work['quantity'] = null;
    }
    final store = MemoryStore()
      ..values[ProjectRepository.v3StorageKey] = jsonEncode(old);
    Future<void> open() async {
      await tester.pumpWidget(
        HasrApp(repository: ProjectRepository(store: store)),
      );
      await tester.pumpAndSettle();
    }

    await open();
    final accept = find.byKey(const ValueKey('accept_length_belowMasonry'));
    await tester.ensureVisible(accept);
    await tester.tap(accept);
    await tester.pumpAndSettle();
    expect(accept, findsNothing);
    final upper = field('review:quantity:aboveMasonry');
    await tester.ensureVisible(upper);
    await tester.enterText(upper, '١٦٠');
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await open();
    expect(find.text('اعتماد الطول'), findsNothing);
    expect(tester.widget<TextField>(upper).controller!.text, '160');
    expect(
      tester
          .widget<TextField>(field('review:quantity:belowMasonry'))
          .controller!
          .text,
      '130',
    );
  });

  testWidgets(
    'an invalid first entry blocks empty quotes and is named in a partial quote',
    (tester) async {
      final store = MemoryStore(project: createProject(id: 'draft'));
      await tester.pumpWidget(
        HasrApp(repository: ProjectRepository(store: store)),
      );
      await tester.pumpAndSettle();
      final calculate = find.byKey(const ValueKey('calculate_project'));
      final count = field('draft:quantity:foundations');
      await tester.ensureVisible(count);
      await tester.enterText(count, '١٫٥');
      await tester.pumpAndSettle();
      expect(find.text('أدخل عددًا صحيحًا غير سالب.'), findsNothing);
      await tester.tap(calculate);
      await tester.pumpAndSettle();
      expect(find.text('أدخل عددًا صحيحًا غير سالب.'), findsOneWidget);
      expect(store.saved.currentProject.calculatedProject, isNull);
      final upper = field('draft:quantity:aboveMasonry');
      await tester.ensureVisible(upper);
      await tester.enterText(upper, '١٦٠');
      await tester.pumpAndSettle();
      await tester.tap(calculate);
      await tester.pumpAndSettle();
      expect(find.text('حصر جزئي — توجد بنود غير مكتملة'), findsOneWidget);
      expect(find.text('البنود غير المكتملة: القواعد'), findsOneWidget);
      expect(find.text('24,160.00'), findsOneWidget);
    },
  );

  testWidgets(
    'a legacy linear roof explains its real input at large text size',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final project = createFullExampleProject(id: 'old-roof');
      final roof = project.work(WorkKind.roof);
      final legacy = roof.model!.copyWith(
        id: 'custom-length',
        name: 'سقف طولي',
        inputUnit: QuantityUnit.linear,
        rows: [project.work(WorkKind.tieBeam).model!.rows.first],
      );
      final store = MemoryStore(
        project: project.updateWork(roof.copyWith(model: legacy, quantity: 77)),
      );
      await tester.pumpWidget(
        HasrApp(repository: ProjectRepository(store: store)),
      );
      await tester.pumpAndSettle();
      final before = Map.of(store.values);
      expect(find.byTooltip('مساعدة حول مساحة السقف'), findsNothing);
      expect(find.text('مستقل عن طول الميدة'), findsNothing);
      final help = find.byTooltip('مساعدة حول طول السقف');
      await tester.ensureVisible(help);
      await tester.tap(help);
      await tester.pumpAndSettle();
      expect(
        find.text('أدخل مقدار السقف بوحدة «متر طولي» حسب النموذج المختار.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('فهمت'));
      await tester.pumpAndSettle();
      expect(store.values, before);
      expect(
        tester
            .widget<TextField>(field('old-roof:quantity:roof'))
            .controller!
            .text,
        '77',
      );
    },
  );

  testWidgets(
    'count and missing beam guidance appear on blur, not initial load',
    (tester) async {
      final store = MemoryStore(project: createProject(id: 'empty'));
      await tester.pumpWidget(
        HasrApp(repository: ProjectRepository(store: store)),
      );
      await tester.pumpAndSettle();
      const countError = 'أدخل عددًا صحيحًا غير سالب.';
      const beamError = 'أدخل أطوال الكمرات لإكمال حساب السقف.';
      expect(find.text(countError), findsNothing);
      expect(find.text(beamError), findsNothing);
      final count = field('empty:quantity:foundations');
      await tester.ensureVisible(count);
      await tester.enterText(count, '١٫٥');
      await tester.pumpAndSettle();
      expect(find.text(countError), findsNothing);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(find.text(countError), findsOneWidget);
      final beams = field('empty:roof_beam_length');
      await tester.ensureVisible(beams);
      await tester.tap(beams);
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(find.text(beamError), findsOneWidget);
      expect(find.text('مستقل عن طول الميدة'), findsNothing);
      final exclude = find.byKey(const ValueKey('include_roof'));
      await tester.ensureVisible(exclude);
      await tester.tap(exclude);
      await tester.pumpAndSettle();
      expect(find.text(beamError), findsNothing);
      expect(find.text('غير مطلوب — خارج الحساب'), findsOneWidget);
    },
  );
}
