import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hasr_alqawaed/data/app_repository.dart';
import 'package:hasr_alqawaed/domain/models.dart';
import 'package:hasr_alqawaed/main.dart';

class _MemoryStore implements KeyValueStore {
  String? value;
  @override
  Future<String?> read(String key) async => value;
  @override
  Future<void> write(String key, String data) async => value = data;
}

Future<void> reveal(
  WidgetTester tester,
  Finder finder, {
  double delta = 280,
}) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      delta,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 60,
    );
  } else {
    await tester.ensureVisible(finder);
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('keyboard next advances to the immediately following field', (
    tester,
  ) async {
    await tester.pumpWidget(
      HasrApp(repository: AppRepository(store: _MemoryStore())),
    );
    await tester.pumpAndSettle();
    final count = find.byKey(const ValueKey('count'));
    await tester.tap(count);
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    final firstPrice = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey('price_0')),
        matching: find.byType(EditableText),
      ),
    );
    expect(firstPrice.focusNode.hasFocus, isTrue);
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    final secondPrice = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey('price_1')),
        matching: find.byType(EditableText),
      ),
    );
    expect(secondPrice.focusNode.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  testWidgets(
    'incomplete drafts do not share or overwrite valid saved inputs',
    (tester) async {
      final store = _MemoryStore();
      final repository = AppRepository(store: store);
      await tester.pumpWidget(HasrApp(repository: repository));
      await tester.pumpAndSettle();
      final count = find.byKey(const ValueKey('count'));
      await tester.enterText(count, '');
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.widget<TextField>(count).controller!.text, '');
      expect(jsonDecode(store.value!)['inputs']['count'], 20);
      await reveal(tester, find.byKey(const ValueKey('share_pdf')));
      expect(find.byKey(const ValueKey('incomplete')), findsOneWidget);
      expect(find.byKey(const ValueKey('total_amount')), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const ValueKey('share_pdf')))
            .onPressed,
        isNull,
      );
      await reveal(tester, count, delta: -280);
      await tester.enterText(count, '٢٠');
      await tester.pumpAndSettle();
      final price = find.byKey(const ValueKey('price_0'));
      await reveal(tester, price);
      await tester.tap(price);
      await tester.enterText(price, '٣٫٥');
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(price);
      expect(field.controller!.text, '٣٫٥');
      expect(field.controller!.selection.baseOffset, 3);
      expect(jsonDecode(store.value!)['inputs']['prices']['concrete'], 3.5);
      await tester.enterText(price, '');
      await tester.pumpAndSettle();
      expect(jsonDecode(store.value!)['inputs']['prices']['concrete'], 3.5);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'small screen, keyboard and enlarged Arabic text do not overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final repository = AppRepository(store: _MemoryStore());
      await tester.pumpWidget(HasrApp(repository: repository));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (var i = 0; i < 6; i++) {
        await reveal(tester, find.byKey(ValueKey('price_$i')));
        expect(tester.takeException(), isNull);
      }
      await reveal(tester, find.byKey(const ValueKey('share_pdf')));
      expect(find.text('17,800'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await reveal(tester, find.byKey(const ValueKey('count')), delta: -280);
      await tester.tap(find.byKey(const ValueKey('count')));
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      await tester.tap(find.byKey(const ValueKey('add_model')));
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const ValueKey('model_field_6')));
      await tester.enterText(find.byKey(const ValueKey('model_field_6')), '0');
      await reveal(tester, find.text('حفظ واستخدام النموذج'));
      await tester.tap(find.text('حفظ واستخدام النموذج'));
      await tester.pumpAndSettle();
      await reveal(
        tester,
        find.byKey(const ValueKey('model_field_6')),
        delta: -280,
      );
      expect(find.text('يجب أن تكون القيمة أكبر من صفر'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('model switching retains controller text and current prices', (
    tester,
  ) async {
    final store = _MemoryStore();
    final custom = FoundationModel.builtIn.copyWith(
      id: 'test-model',
      name: 'نموذج خاص',
      concretePerFoundation: 1,
    );
    store.value = jsonEncode(AppData(customModels: [custom]).toJson());
    await tester.pumpWidget(HasrApp(repository: AppRepository(store: store)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('count')), '١٠');
    final price = find.byKey(const ValueKey('price_0'));
    await reveal(tester, price);
    await tester.enterText(price, '٠');
    await reveal(
      tester,
      find.byKey(const ValueKey('choose_model')),
      delta: -280,
    );
    await tester.tap(find.byKey(const ValueKey('choose_model')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('نموذج خاص'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('count')))
          .controller!
          .text,
      '١٠',
    );
    await reveal(tester, price);
    expect(tester.widget<TextField>(price).controller!.text, '٠');
    expect(jsonDecode(store.value!)['selectedModelId'], 'test-model');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
