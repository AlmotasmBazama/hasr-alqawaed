import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hasr_alqawaed/data/app_repository.dart';
import 'package:hasr_alqawaed/main.dart';

/// Real native preferences, isolated from the installed application's data.
class _IntegrationStore implements KeyValueStore {
  final preferences = SharedPreferencesAsync();
  static const prefix = 'hasr_integration_';

  @override
  Future<String?> read(String key) => preferences.getString('$prefix$key');

  @override
  Future<void> write(String key, String value) =>
      preferences.setString('$prefix$key', value);

  Future<void> clear() async {
    await preferences.remove('$prefix${AppRepository.storageKey}');
    await preferences.remove('$prefix${AppRepository.recoveryKey}');
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native model lifecycle, Arabic input and persistent calculator', (
    tester,
  ) async {
    final store = _IntegrationStore();
    await store.clear();
    final repository = AppRepository(store: store);

    Future<void> settle() async {
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
    }

    Future<void> reveal(Finder finder, {double delta = 260}) async {
      if (finder.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          finder,
          delta,
          scrollable: find
              .descendant(
                of: find.byType(ListView).last,
                matching: find.byType(Scrollable),
              )
              .first,
          maxScrolls: 35,
        );
      } else {
        await tester.ensureVisible(finder);
      }
      await settle();
    }

    Future<void> tap(Finder finder, {double delta = 260}) async {
      await reveal(finder, delta: delta);
      await tester.tap(finder);
      await settle();
    }

    Future<void> enter(String key, String value) async {
      final field = find.byKey(ValueKey(key));
      await reveal(field);
      await tester.enterText(field, value);
      await settle();
    }

    Future<void> hideKeyboard() async {
      FocusManager.instance.primaryFocus?.unfocus();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await settle();
    }

    try {
      await tester.pumpWidget(HasrApp(repository: repository));
      await settle();
      expect(find.text('حصر القواعد'), findsOneWidget);
      await reveal(find.textContaining('17,800'));
      expect(find.textContaining('17,800'), findsOneWidget);

      await reveal(find.byKey(const ValueKey('count')), delta: -260);
      await enter('count', '١٠');
      await hideKeyboard();
      await tap(find.byKey(const ValueKey('add_model')), delta: -260);
      await enter('model_name', 'نموذج الاختبار');
      const values = <int, String>{4: '١', 5: '٢', 6: '٥', 7: '٠٫٥', 8: '١٠'};
      for (final entry in values.entries) {
        await enter('model_field_${entry.key}', entry.value);
      }
      await hideKeyboard();
      await tap(find.text('حفظ واستخدام النموذج'));
      await reveal(find.textContaining('9,580'));
      expect(find.textContaining('9,580'), findsOneWidget);

      await repository.flush();
      var saved = (await AppRepository(store: store).load()).data;
      expect(saved.customModels, hasLength(1));
      final modelId = saved.customModels.single.id;
      expect(saved.selectedModelId, modelId);
      expect(saved.inputs.count, 10);
      expect(saved.selectedModel.steel8BarsPerFoundation, 0.5);

      await reveal(find.byKey(const ValueKey('price_0')), delta: -260);
      await enter('price_0', '600');
      await hideKeyboard();
      await tester.pump(const Duration(milliseconds: 700));
      await repository.flush();

      await tap(find.byKey(const ValueKey('choose_model')), delta: -260);
      await tap(find.byKey(ValueKey('edit_model_$modelId')));
      await enter('model_name', 'نموذج معدل');
      await hideKeyboard();
      await tap(find.text('حفظ التعديلات'));
      await repository.flush();
      saved = (await AppRepository(store: store).load()).data;
      expect(saved.customModels, hasLength(1));
      expect(saved.customModels.single.id, modelId);
      expect(saved.customModels.single.name, 'نموذج معدل');

      await tap(find.byKey(const ValueKey('choose_model')), delta: -260);
      await tap(find.byKey(ValueKey('edit_model_$modelId')));
      await enter('model_name', 'تعديل ملغى');
      await hideKeyboard();
      await tester.tap(find.byType(BackButton));
      await settle();
      expect(
        (await AppRepository(
          store: store,
        ).load()).data.customModels.single.name,
        'نموذج معدل',
      );

      await tap(find.byKey(const ValueKey('choose_model')), delta: -260);
      await tap(find.text('نموذج 1').last);
      await repository.flush();
      saved = (await AppRepository(store: store).load()).data;
      expect(saved.selectedModel.isBuiltIn, isTrue);
      expect(saved.inputs.count, 10);
      expect(saved.inputs.prices.concrete, 600);

      // Dispose the entire UI and create another repository to read native data.
      await tester.pumpWidget(const SizedBox.shrink());
      await settle();
      await tester.pumpWidget(HasrApp(repository: AppRepository(store: store)));
      await settle();
      final count = tester.widget<TextField>(
        find.byKey(const ValueKey('count')),
      );
      expect(count.controller!.text, '10');
      await reveal(find.byKey(const ValueKey('price_0')));
      final price = tester.widget<TextField>(
        find.byKey(const ValueKey('price_0')),
      );
      expect(double.parse(price.controller!.text), 600);
      await reveal(find.textContaining('9,200'));
      expect(find.textContaining('9,200'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await settle();
      await repository.flush();
      await store.clear();
    }
  });
}
