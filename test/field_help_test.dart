import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hasr_alqawaed/ui/app_theme.dart';
import 'package:hasr_alqawaed/ui/field_help.dart';
import 'package:hasr_alqawaed/ui/project_widgets.dart';

void main() {
  testWidgets(
    'help preserves an in-progress edit, selection, and change count',
    (tester) async {
      var raw = '';
      var changes = 0;
      const title = 'طول الميدة';
      const message = 'أدخل مجموع أطوال الميدات بالمتر حسب مخطط المشروع.';
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, refresh) => Column(
                children: [
                  NumberInput(
                    text: raw,
                    label: title,
                    onChanged: (text) => refresh(() {
                      raw = text;
                      changes++;
                    }),
                  ),
                  const FieldHelp(title: title, message: message),
                ],
              ),
            ),
          ),
        ),
      );
      final input = find.byType(TextField);
      await tester.enterText(input, '١٢٣٫');
      final editor = tester.widget<TextField>(input).controller!;
      editor.selection = const TextSelection.collapsed(offset: 2);
      final before = editor.value;
      final editsBeforeHelp = changes;
      expect(find.text(message), findsNothing);
      final help = find.byTooltip('مساعدة حول $title');
      expect(tester.getSize(help).shortestSide, greaterThanOrEqualTo(48));
      await tester.tap(help);
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      await tester.tap(find.text('فهمت'));
      await tester.pumpAndSettle();
      expect(find.text(message), findsNothing);
      expect(tester.widget<TextField>(input).controller, same(editor));
      expect(editor.value, before);
      expect(changes, editsBeforeHelp);
      expect(raw, '١٢٣٫');

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text(message), findsNothing);
      expect(editor.value, before);
    },
  );
}
