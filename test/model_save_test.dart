import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hasr_alqawaed/data/app_repository.dart';
import 'package:hasr_alqawaed/domain/models.dart';
import 'package:hasr_alqawaed/main.dart';
import 'package:hasr_alqawaed/ui/model_editor.dart';

class _ControlledStore implements KeyValueStore {
  String? value;
  Completer<void>? gate;
  bool failRead = false;
  bool failNextWrite = false;
  int writeStarts = 0;

  @override
  Future<String?> read(String key) async {
    if (failRead) throw StateError('Storage unavailable');
    return value;
  }

  @override
  Future<void> write(String key, String data) async {
    writeStarts++;
    if (gate != null) await gate!.future;
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('Disk full');
    }
    value = data;
  }

  AppData get saved =>
      AppData.fromJson(jsonDecode(value!) as Map<String, dynamic>);
}

Future<void> _openEditor(WidgetTester tester, AppRepository repository) async {
  await tester.pumpWidget(HasrApp(repository: repository));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('add_model')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('model_name')),
    'نموذج الحفظ',
  );
  FocusManager.instance.primaryFocus?.unfocus();
  final save = find.text('حفظ واستخدام النموذج');
  await tester.scrollUntilVisible(
    save,
    300,
    scrollable: find
        .descendant(
          of: find.byType(ModelEditor),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'inactive lifecycle during slow model save cannot overwrite new model',
    (tester) async {
      final store = _ControlledStore();
      final repository = AppRepository(store: store);
      await _openEditor(tester, repository);
      final previousWrites = store.writeStarts;
      store.gate = Completer<void>();
      await tester.tap(find.text('حفظ واستخدام النموذج'));
      await tester.pump();
      expect(find.byType(ModelEditor), findsOneWidget);
      expect(store.saved.customModels, isEmpty);
      expect(store.writeStarts, previousWrites + 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      store.gate!.complete();
      await tester.pumpAndSettle();
      await repository.flush();
      expect(
        store.writeStarts,
        previousWrites + 1,
        reason:
            'The lifecycle event must not enqueue the old calculator state.',
      );
      expect(find.byType(ModelEditor), findsNothing);
      expect(store.saved.customModels, hasLength(1));
      expect(store.saved.selectedModel.name, 'نموذج الحفظ');
      expect(store.saved.selectedModelId, store.saved.customModels.single.id);
      expect(find.text('نموذج الحفظ'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'failed model save keeps editor and allows retry without duplicate model',
    (tester) async {
      final store = _ControlledStore();
      final repository = AppRepository(store: store);
      await _openEditor(tester, repository);
      store.failNextWrite = true;
      await tester.tap(find.text('حفظ واستخدام النموذج'));
      await tester.pumpAndSettle();
      expect(find.byType(ModelEditor), findsOneWidget);
      expect(find.text('تعذر حفظ النموذج. حاول مرة أخرى.'), findsOneWidget);
      expect(store.saved.customModels, isEmpty);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      await tester.ensureVisible(find.text('حفظ واستخدام النموذج'));
      await tester.tap(find.text('حفظ واستخدام النموذج'));
      await tester.pumpAndSettle();
      expect(find.byType(ModelEditor), findsNothing);
      expect(store.saved.customModels, hasLength(1));
      expect(store.saved.selectedModel.name, 'نموذج الحفظ');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'editing after failed load preserves protected-data recovery message',
    (tester) async {
      final store = _ControlledStore()..failRead = true;
      final repository = AppRepository(store: store);
      await tester.pumpWidget(HasrApp(repository: repository));
      await tester.pumpAndSettle();
      const warning =
          'تعذّرت قراءة البيانات المحفوظة. أعد فتح التطبيق للمحاولة؛ الحفظ متوقف لحماية بياناتك.';
      expect(repository.canWrite, isFalse);
      expect(find.text(warning), findsOneWidget);
      final count = find.byKey(const ValueKey('count'));
      await tester.ensureVisible(count);
      await tester.enterText(count, '33');
      await tester.pump(const Duration(milliseconds: 500));
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.drag(
        find.byKey(const ValueKey('calculator_scroll')),
        const Offset(0, 700),
      );
      await tester.pumpAndSettle();
      expect(find.text(warning), findsOneWidget);
      expect(store.writeStarts, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
