import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hasr_alqawaed/data/app_repository.dart';
import 'package:hasr_alqawaed/domain/models.dart';

class MemoryStore implements KeyValueStore {
  final values = <String, String>{};
  final writes = <String>[];
  bool failRead = false;
  bool failWrite = false;
  Completer<void>? gate;

  @override
  Future<String?> read(String key) async {
    if (failRead) throw StateError('Read unavailable');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (gate != null) await gate!.future;
    if (failWrite) throw StateError('Disk full');
    writes.add(value);
    values[key] = value;
  }
}

void main() {
  test('initial data seeded once and saved custom state restored', () async {
    final store = MemoryStore();
    final repository = AppRepository(store: store);
    final first = await repository.load();
    expect(first.warning, isNull);
    expect(first.data.inputs.count, 20);
    expect(store.writes, hasLength(1));
    final custom = FoundationModel.builtIn.copyWith(
      id: 'stable-custom',
      name: 'نموذج 2',
      steel14BarsPerQuintal: 5,
    );
    final data = first.data
        .upsertModel(custom)
        .copyWith(
          inputs: CalculatorInputs(
            count: 10,
            prices: Prices.defaults.copyWith(steel14: 0),
          ),
        );
    await repository.save(data);
    final restored = await AppRepository(store: store).load();
    expect(restored.data.customModels.single.id, 'stable-custom');
    expect(restored.data.selectedModelId, 'stable-custom');
    expect(restored.data.inputs.count, 10);
    expect(restored.data.inputs.prices.steel14, 0);
    expect(store.writes, hasLength(2));
    final edited = restored.data.upsertModel(custom.copyWith(name: 'معدّل'));
    await repository.save(edited);
    final editedAgain = await AppRepository(store: store).load();
    expect(editedAgain.data.customModels, hasLength(1));
    expect(editedAgain.data.customModels.single.name, 'معدّل');
  });

  test('concurrent saves serialize so latest state wins', () async {
    final store = MemoryStore();
    final repository = AppRepository(store: store);
    final initial = (await repository.load()).data;
    store.gate = Completer<void>();
    final old = repository.save(
      initial.copyWith(inputs: CalculatorInputs.defaults.copyWith(count: 2)),
    );
    final latest = repository.save(
      initial.copyWith(inputs: CalculatorInputs.defaults.copyWith(count: 99)),
    );
    await Future<void>.delayed(Duration.zero);
    expect(store.writes, hasLength(1));
    store.gate!.complete();
    await Future.wait([old, latest]);
    final restored = await AppRepository(store: store).load();
    expect(restored.data.inputs.count, 99);
    expect(jsonDecode(store.writes[1])['inputs']['count'], 2);
    expect(jsonDecode(store.writes[2])['inputs']['count'], 99);
  });

  test(
    'failed write is reported and does not poison subsequent writes',
    () async {
      final store = MemoryStore();
      final repository = AppRepository(store: store);
      final initial = (await repository.load()).data;
      store.failWrite = true;
      await expectLater(repository.save(initial), throwsStateError);
      store.failWrite = false;
      await repository.save(
        initial.copyWith(inputs: CalculatorInputs.defaults.copyWith(count: 88)),
      );
      expect((await AppRepository(store: store).load()).data.inputs.count, 88);
    },
  );

  test(
    'read failure cannot overwrite unread user data with defaults',
    () async {
      final store = MemoryStore()..failRead = true;
      final repository = AppRepository(store: store);
      expect((await repository.load()).warning, isNotNull);
      await expectLater(repository.save(AppData()), throwsStateError);
      expect(store.writes, isEmpty);
    },
  );

  test(
    'malformed JSON recovers without crash and preserves original bytes',
    () async {
      final store = MemoryStore();
      store.values[AppRepository.storageKey] = '{broken json';
      final repository = AppRepository(store: store);
      final loaded = await repository.load();
      expect(loaded.warning, isNotNull);
      expect(loaded.data.inputs.count, 20);
      expect(store.values[AppRepository.recoveryKey], '{broken json');
      await repository.save(loaded.data);
      expect((await AppRepository(store: store).load()).warning, isNull);
    },
  );

  test('saving before a successful load is blocked', () async {
    final store = MemoryStore();
    await expectLater(
      AppRepository(store: store).save(AppData()),
      throwsStateError,
    );
    expect(store.writes, isEmpty);
  });

  test(
    'missing selection falls back safely and bundled model cannot be replaced',
    () {
      final map = AppData().toJson();
      map['selectedModelId'] = 'deleted';
      expect(
        AppData.fromJson(map).selectedModel.id,
        FoundationModel.builtIn.id,
      );
      map['customModels'] = [FoundationModel.builtIn.toJson()];
      expect(() => AppData.fromJson(map), throwsFormatException);
    },
  );
}
