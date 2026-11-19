import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hasr_alqawaed/project/catalog.dart';
import 'package:hasr_alqawaed/ui/project_picker.dart';

void main() {
  testWidgets('search saved projects by name or location and open a match', (
    tester,
  ) async {
    final projects = [
      createProject(id: 'house', name: 'منزل العائلة', location: 'طرابلس'),
      createProject(id: 'shop', name: 'المتجر', location: 'بنغازي'),
      createProject(id: 'office', name: 'المكتب', location: 'مصراتة'),
      createProject(id: 'clinic', name: 'العيادة', location: 'درنة'),
      createProject(id: 'school', name: 'المدرسة', location: 'سبها'),
    ];
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              child: const Text('اختيار مشروع'),
              onPressed: () async {
                selected = await showModalBottomSheet<String>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) =>
                      ProjectPicker(projects: projects, selectedId: 'house'),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('اختيار مشروع'));
    await tester.pumpAndSettle();

    final search = find.byType(TextField);
    await tester.enterText(search, 'عائلة');
    await tester.pump();
    expect(find.text('منزل العائلة'), findsOneWidget);
    expect(find.text('المتجر'), findsNothing);

    await tester.enterText(search, 'لا نتيجة');
    await tester.pump();
    expect(find.text('لا توجد مشاريع تطابق البحث'), findsOneWidget);
    expect(find.text('منزل العائلة'), findsNothing);

    await tester.enterText(search, 'بنغازي');
    await tester.pump();
    expect(find.text('لا توجد مشاريع تطابق البحث'), findsNothing);
    expect(find.text('منزل العائلة'), findsNothing);
    await tester.tap(find.text('المتجر'));
    await tester.pumpAndSettle();
    expect(selected, 'shop');
    expect(find.byType(ProjectPicker), findsNothing);
  });
}
