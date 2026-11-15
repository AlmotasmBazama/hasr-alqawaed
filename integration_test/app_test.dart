import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hasr_alqawaed/data/app_repository.dart';
import 'package:hasr_alqawaed/domain/calculator.dart' as old_engine;
import 'package:hasr_alqawaed/domain/models.dart' as legacy;
import 'package:hasr_alqawaed/main.dart';
import 'package:hasr_alqawaed/project/engine.dart';
import 'package:hasr_alqawaed/project/models.dart';
import 'package:hasr_alqawaed/project/repository.dart';
import 'package:hasr_alqawaed/services/project_report_service.dart';

/// Native storage remains isolated from the application's own saved projects.
class NativeTestStore implements KeyValueStore {
  final preferences = SharedPreferencesAsync();
  static const prefix = 'hasr_v2_integration_';
  static const keys = [
    AppRepository.storageKey,
    ProjectRepository.storageKey,
    ProjectRepository.legacyBackupKey,
    ProjectRepository.migrationMarkerKey,
    ProjectRepository.recoveryKey,
  ];
  @override
  Future<String?> read(String key) => preferences.getString('$prefix$key');
  @override
  Future<void> write(String key, String value) =>
      preferences.setString('$prefix$key', value);
  Future<void> clear() async {
    for (final key in keys) {
      await preferences.remove('$prefix$key');
    }
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native migration, example prices, independent projects and PDF',
    (tester) async {
      final store = NativeTestStore();
      await store.clear();
      final custom = legacy.FoundationModel.builtIn.copyWith(
        id: 'native-custom',
        name: 'نموذج محفوظ',
        concretePerFoundation: .9,
        steel14BarsPerFoundation: 2.5,
        steel14BarsPerQuintal: 5.5,
        steel8BarsPerFoundation: .75,
        steel8BarsPerQuintal: 18.5,
      );
      final old = legacy.AppData(
        customModels: [custom],
        selectedModelId: custom.id,
        inputs: legacy.CalculatorInputs(
          count: 12,
          prices: legacy.Prices.defaults.copyWith(
            concrete: 615,
            steel14: 533,
            carpenter: 77,
          ),
        ),
      );
      final raw = jsonEncode(old.toJson());
      await store.write(AppRepository.storageKey, raw);
      var repository = ProjectRepository(store: store);
      Future<void> settle() =>
          tester.pumpAndSettle(const Duration(milliseconds: 100));
      Future<void> hideKeyboard() async {
        FocusManager.instance.primaryFocus?.unfocus();
        await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
        await settle();
      }

      Future<void> tapKey(String key) async {
        final finder = find.byKey(ValueKey(key));
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await settle();
      }

      Future<void> enter(String key, String value) async {
        final container = find.byKey(ValueKey(key));
        await tester.ensureVisible(container);
        final field = find.descendant(
          of: container,
          matching: find.byType(TextField),
        );
        await tester.enterText(field, value);
        await tester.pump(const Duration(milliseconds: 600));
        await hideKeyboard();
      }

      try {
        await tester.pumpWidget(HasrApp(repository: repository));
        await settle();
        expect(find.text('مشروعي السابق'), findsOneWidget);
        var saved = (await ProjectRepository(store: store).load()).data;
        expect(saved.projects, hasLength(1));
        expect(saved.customModels.single.id, custom.id);
        expect(saved.currentProject.work(WorkKind.foundations).quantity, 12);
        expect(
          saved.currentProject.works.where((work) => work.included),
          hasLength(1),
        );
        expect(
          calculateProject(saved.currentProject).totalCost,
          closeTo(old_engine.calculate(custom, old.inputs).totalCost, 1e-8),
        );
        expect(await store.read(AppRepository.storageKey), raw);
        expect(await store.read(ProjectRepository.legacyBackupKey), raw);
        expect(await store.read(ProjectRepository.migrationMarkerKey), '2');

        await tapKey('project_picker');
        await tapKey('example_project');
        saved = (await ProjectRepository(store: store).load()).data;
        final exampleId = saved.currentProjectId;
        expect(
          calculateProject(saved.currentProject).totalCost,
          closeTo(86364.20, 1e-8),
        );
        await tapKey('tab_prices');
        await enter('$exampleId:price:cement', '٤٠');
        await repository.flush();
        await tapKey('tab_results');
        expect(find.text('86,026.20'), findsOneWidget);
        saved = (await ProjectRepository(store: store).load()).data;
        expect(saved.currentProject.materialPrices['cement'], 40);
        expect(saved.projects.first.materialPrices['cement'], 42);
        final snapshot = calculateProject(saved.currentProject);
        final bytes = await ProjectReportService.generate(snapshot);
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
        expect(snapshot.totalCost, closeTo(86026.20, 1e-8));
        expect(snapshot.work(WorkKind.roof).cost, isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await settle();
        await repository.flush();
        repository = ProjectRepository(store: store);
        await tester.pumpWidget(HasrApp(repository: repository));
        await settle();
        expect(find.text('مثال الأوراق'), findsOneWidget);
        await tapKey('tab_results');
        expect(find.text('86,026.20'), findsOneWidget);
        await tapKey('project_picker');
        await tester.tap(find.text('مشروعي السابق'));
        await settle();
        await tapKey('tab_project');
        await enter('migrated-project-v1:quantity:foundations', '٢١');
        await repository.flush();
        saved = (await ProjectRepository(store: store).load()).data;
        expect(saved.projects, hasLength(2));
        expect(saved.currentProject.work(WorkKind.foundations).quantity, 21);
        expect(saved.projects.last.work(WorkKind.foundations).quantity, 20);
        expect(saved.projects.last.materialPrices['cement'], 40);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await settle();
        await repository.flush();
        await store.clear();
      }
    },
  );
}
