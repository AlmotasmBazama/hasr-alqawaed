import 'dart:async';
import 'dart:convert';

import '../data/app_repository.dart';
import '../domain/models.dart' as legacy;
import 'catalog.dart';
import 'models.dart';

class ProjectLoadResult {
  const ProjectLoadResult(this.data, {this.warning});
  final ProjectState data;
  final String? warning;
}

class ProjectRepository {
  ProjectRepository({KeyValueStore? store})
    : _store = store ?? PreferencesStore();
  static const storageKey = 'hasr_project_state_v4';
  static const v3StorageKey = 'hasr_project_state_v3';
  static const v3BackupKey = 'hasr_project_v3_original_backup';
  static const v3MigrationMarkerKey = 'hasr_project_v3_migration_complete';
  static const previousStorageKey = 'hasr_project_state_v2';
  static const previousBackupKey = 'hasr_project_v2_original_backup';
  static const previousMigrationMarkerKey =
      'hasr_project_v2_migration_complete';
  static const legacyBackupKey = 'hasr_project_v1_original_backup';
  static const migrationMarkerKey = 'hasr_project_v1_migration_complete';
  static const recoveryKey = 'hasr_project_v4_recovery_backup';
  final KeyValueStore _store;
  Future<ProjectLoadResult>? _loadFuture;
  Future<void> _pending = Future<void>.value();
  bool _canWrite = false;
  bool get canWrite => _canWrite;

  Future<ProjectLoadResult> load() => _loadFuture ??= _load();

  ProjectState _freshState() {
    final project = createProject();
    return ProjectState(projects: [project], currentProjectId: project.id);
  }

  Future<void> _backup(String key, String raw) async {
    final existing = await _store.read(key);
    if (existing == null) {
      await _store.write(key, raw);
    } else if (existing != raw) {
      // Never overwrite the first recovery copy, even following a later edit.
      await _store.write('$key-${DateTime.now().microsecondsSinceEpoch}', raw);
    }
  }

  Future<ProjectLoadResult> _load() async {
    String? currentRaw;
    String? v3Raw;
    String? previousRaw;
    String? legacyRaw;
    try {
      currentRaw = await _store.read(storageKey);
      if (currentRaw == null) {
        v3Raw = await _store.read(v3StorageKey);
        if (v3Raw == null) {
          previousRaw = await _store.read(previousStorageKey);
          if (previousRaw == null) {
            legacyRaw = await _store.read(AppRepository.storageKey);
          }
        }
      }
    } catch (_) {
      return ProjectLoadResult(
        _freshState(),
        warning:
            'تعذّرت قراءة البيانات المحفوظة. الحفظ متوقف لحماية بياناتك؛ أعد فتح التطبيق للمحاولة.',
      );
    }
    if (currentRaw != null) {
      try {
        final state = ProjectState.fromJson(jsonMap(jsonDecode(currentRaw)));
        _canWrite = true;
        return ProjectLoadResult(state);
      } catch (_) {
        try {
          await _backup(recoveryKey, currentRaw);
        } catch (_) {
          /* Original key remains untouched. */
        }
        return ProjectLoadResult(
          _freshState(),
          warning:
              'تعذّرت قراءة بيانات المشاريع. احتُفظ بالأصل، والحفظ متوقف لحمايته. أعد فتح التطبيق بعد استعادة البيانات.',
        );
      }
    }
    final sourceRaw = v3Raw ?? previousRaw ?? legacyRaw;
    if (sourceRaw != null) {
      ProjectState? migrated;
      try {
        // The byte-for-byte source survives both parse failures and save errors.
        final (backup, marker) = v3Raw != null
            ? (v3BackupKey, v3MigrationMarkerKey)
            : previousRaw != null
            ? (previousBackupKey, previousMigrationMarkerKey)
            : (legacyBackupKey, migrationMarkerKey);
        await _backup(backup, sourceRaw);
        final source = jsonMap(jsonDecode(sourceRaw));
        migrated = v3Raw != null
            ? migrateProjectStateV3(source)
            : previousRaw != null
            ? migrateProjectStateV2(
                ProjectState.fromJson(source, migrateV2: true),
              )
            : migrateLegacyState(legacy.AppData.fromJson(source));
        final json = jsonEncode(migrated.toJson());
        ProjectState.fromJson(jsonMap(jsonDecode(json)));
        await _store.write(storageKey, json);
        // Written only AFTER the complete new snapshot has been saved.
        await _store.write(marker, '${ProjectState.schemaVersion}');
        _canWrite = true;
        return ProjectLoadResult(migrated);
      } catch (_) {
        return ProjectLoadResult(
          migrated ?? _freshState(),
          warning:
              'لم يكتمل ترحيل البيانات. احتُفظ ببيانات النسخة السابقة دون تغيير. الحفظ متوقف؛ أعد فتح التطبيق لإعادة المحاولة.',
        );
      }
    }
    final initial = _freshState();
    _canWrite = true;
    try {
      await save(initial);
      return ProjectLoadResult(initial);
    } catch (_) {
      return ProjectLoadResult(
        initial,
        warning: 'تعذّر الحفظ الأولي. ستُعاد المحاولة عند تعديل البيانات.',
      );
    }
  }

  Future<void> save(ProjectState data) {
    if (!_canWrite) {
      return Future<void>.error(StateError('Storage not loaded safely'));
    }
    late final String snapshot;
    try {
      final json = data.toJson();
      ProjectState.fromJson(json);
      snapshot = jsonEncode(json);
    } catch (error, stack) {
      return Future<void>.error(error, stack);
    }
    final completion = Completer<void>();
    _pending = _pending.then((_) async {
      try {
        await _store.write(storageKey, snapshot);
        completion.complete();
      } catch (error, stack) {
        completion.completeError(error, stack);
      }
    });
    return completion.future;
  }

  Future<void> flush() => _pending;
}
