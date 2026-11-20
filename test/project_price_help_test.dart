import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hasr_alqawaed/main.dart';
import 'package:hasr_alqawaed/project/catalog.dart';
import 'package:hasr_alqawaed/project/models.dart';
import 'package:hasr_alqawaed/project/repository.dart';

import 'project_ui_test.dart' show MemoryStore, field;

void main() {
  testWidgets(
    'custom service keeps its quoted unit and override while explaining prices',
    (tester) async {
      final project = createExampleProject(id: 'custom');
      final foundation = project.work(WorkKind.foundations);
      final model = foundation.model!.copyWith(
        id: 'custom-foundation',
        rows: [
          for (final row in foundation.model!.rows)
            row.id == 'carpenter'
                ? row.copyWith(label: 'نجارة القالب', unit: QuantityUnit.area)
                : row,
        ],
      );
      final store = MemoryStore(
        project: project.updateWork(
          foundation.copyWith(
            model: model,
            priceOverrides: {'carpenter': 24.5},
          ),
        ),
      );
      await tester.pumpWidget(
        HasrApp(repository: ProjectRepository(store: store)),
      );
      await tester.pumpAndSettle();
      final saved = Map.of(store.values);
      Future<void> tap(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      await tap(find.byKey(const ValueKey('tab_prices')));
      await tap(find.byKey(const ValueKey('services_prices')));
      final serviceHelp = find.byTooltip('مساعدة حول سعر نجارة القالب القواعد');
      final priceRow = find
          .ancestor(of: serviceHelp, matching: find.byType(Row))
          .first;
      expect(
        find.descendant(of: priceRow, matching: find.text('د.ل / م²')),
        findsOneWidget,
      );
      await tap(serviceHelp);
      expect(
        find.text('أدخل سعر وحدة واحدة وفق الوحدة الموضحة بجوار الحقل.'),
        findsOneWidget,
      );
      await tap(find.text('فهمت'));
      await tap(find.byKey(const ValueKey('tab_project')));
      await tap(find.byKey(const ValueKey('work_foundations')));
      final override = field('custom:override:foundations:carpenter');
      expect(
        tester.widget<TextField>(override).decoration!.labelText,
        'السعر (د.ل / م²)',
      );
      expect(tester.widget<TextField>(override).controller!.text, '24.5');
      await tap(find.byTooltip('مساعدة حول سعر نجارة القالب'));
      expect(
        find.text(
          'هذا السعر يخص هذا السطر فقط. يمكنك إلغاء التخصيص لاستخدام السعر المشترك.',
        ),
        findsOneWidget,
      );
      await tap(find.text('فهمت'));
      expect(tester.widget<TextField>(override).controller!.text, '24.5');
      expect(store.values, saved);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
