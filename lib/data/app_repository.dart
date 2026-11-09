import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';

abstract interface class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class PreferencesStore implements KeyValueStore {
  PreferencesStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();
  final SharedPreferencesAsync _preferences;

  @override
  Future<String?> read(String key) => _preferences.getString(key);

  @override
  Future<void> write(String key, String value) =>
      _preferences.setString(key, value);
}

class AppLoadResult {
  const AppLoadResult(this.data, {this.warning});
  final AppData data;
  final String? warning;
}

class AppRepository {
  AppRepository({KeyValueStore? store}) : _store = store ?? PreferencesStore();

  static const storageKey = 'hasr_alqawaed_state_v1';
  static const recoveryKey = 'hasr_alqawaed_recovery_backup';
  final KeyValueStore _store;
  Future<AppLoadResult>? _loadFuture;
  Future<void> _pending = Future<void>.value();
  bool _canWrite = false;

  /// False after an unreadable state or failed recovery backup. Preserve the
  /// load warning and ask for a fresh launch instead of retrying unsafe writes.
  bool get canWrite => _canWrite;

  Future<AppLoadResult> load() => _loadFuture ??= _load();

  Future<AppLoadResult> _load() async {
    String? raw;
    try {
      raw = await _store.read(storageKey);
    } catch (_) {
      // A failed read must never allow defaults to overwrite unread user data.
      return AppLoadResult(
        AppData(),
        warning:
            'تعذّرت قراءة البيانات المحفوظة. أعد فتح التطبيق للمحاولة؛ الحفظ متوقف لحماية بياناتك.',
      );
    }

    if (raw == null) {
      _canWrite = true;
      final initial = AppData();
      try {
        await save(initial);
        return AppLoadResult(initial);
      } catch (_) {
        return AppLoadResult(
          initial,
          warning: 'تعذّر حفظ الإعدادات الأولية. سيُعاد الحفظ عند تعديل القيم.',
        );
      }
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid saved state');
      }
      final data = AppData.fromJson(decoded);
      _canWrite = true;
      return AppLoadResult(data);
    } catch (_) {
      try {
        // Preserve the original bytes before permitting a replacement.
        await _store.write(recoveryKey, raw);
        _canWrite = true;
        return AppLoadResult(
          AppData(),
          warning:
              'تعذّرت قراءة بعض البيانات. استُخدمت القيم الأولية مع الاحتفاظ بنسخة من البيانات السابقة.',
        );
      } catch (_) {
        return AppLoadResult(
          AppData(),
          warning:
              'البيانات المحفوظة غير صالحة وتعذّر نسخها احتياطيًا. الحفظ متوقف لحماية البيانات السابقة.',
        );
      }
    }
  }

  Future<void> save(AppData data) {
    if (!_canWrite) {
      return Future<void>.error(StateError('Storage not loaded safely'));
    }
    // Capture an immutable JSON snapshot before joining the write queue.
    late final String json;
    try {
      final map = data.toJson();
      AppData.fromJson(map);
      json = jsonEncode(map);
    } catch (error, stack) {
      return Future<void>.error(error, stack);
    }
    final completion = Completer<void>();
    _pending = _pending.then((_) async {
      try {
        await _store.write(storageKey, json);
        completion.complete();
      } catch (error, stack) {
        completion.completeError(error, stack);
      }
    });
    return completion.future;
  }

  Future<void> flush() => _pending;
}
