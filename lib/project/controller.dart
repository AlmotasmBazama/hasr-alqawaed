import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/numbers.dart';
import 'catalog.dart';
import 'engine.dart';
import 'models.dart';
import 'repository.dart';

/// Persistent data and transient edit buffers have separate lifetimes. Empty
/// drafts invalidate the live estimate without replacing the last valid save.
class ProjectController extends ChangeNotifier {
  ProjectController(this.repository);

  final ProjectRepository repository;
  ProjectState? state;
  String? warning;
  bool saving = false;
  bool _disposed = false;
  Timer? _debounce;
  final Map<String, String> _drafts = {};

  bool get loaded => state != null;
  bool get editable => loaded && repository.canWrite && !saving;
  Project get savedProject => state!.currentProject;
  String _key(String field) => '${savedProject.id}:$field';
  String draft(String field, double? value) =>
      _drafts[_key(field)] ?? (value == null ? '' : inputNumber(value));

  Future<void> load() async {
    final result = await repository.load();
    if (_disposed) return;
    state = result.data;
    warning = result.warning;
    notifyListeners();
  }

  double? parseQuantity(WorkKind kind, String raw) {
    final number = parseDecimal(raw);
    if (number == null) return null;
    if (kind.integerQuantity &&
        (number != number.truncateToDouble() || number > 9007199254740991)) {
      return null;
    }
    return number;
  }

  Project get project {
    var current = savedProject;
    final materials = Map<String, double?>.of(current.materialPrices);
    final services = Map<String, double?>.of(current.servicePrices);
    for (final material in materialCatalog) {
      final raw = _drafts[_key('material:${material.id}')];
      if (raw != null) materials[material.id] = parseDecimal(raw);
    }
    for (final entry in current.works) {
      var work = entry;
      final raw = _drafts[_key('quantity:${entry.kind.name}')];
      if (raw != null) {
        work = work.copyWith(quantity: parseQuantity(entry.kind, raw));
      }
      final overrides = Map<String, double?>.of(work.priceOverrides);
      for (final row in work.model?.rows ?? <ModelRow>[]) {
        final serviceKey = servicePriceKey(work.kind, row);
        final price = _drafts[_key('service:$serviceKey')];
        if (price != null) services[serviceKey] = parseDecimal(price);
        final override = _drafts[_key('override:${work.kind.name}:${row.id}')];
        if (override != null) overrides[row.id] = parseDecimal(override);
      }
      current = current.updateWork(work.copyWith(priceOverrides: overrides));
    }
    return current.copyWith(materialPrices: materials, servicePrices: services);
  }

  ProjectResult get result => calculateProject(project);

  void _changed(Project project) {
    state = state!.updateProject(project);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), saveNow);
    notifyListeners();
  }

  void quantity(WorkKind kind, String raw) {
    if (!editable) return;
    _drafts[_key('quantity:${kind.name}')] = raw;
    final number = parseQuantity(kind, raw);
    if (number != null) {
      _changed(
        savedProject.updateWork(
          savedProject.work(kind).copyWith(quantity: number),
        ),
      );
    } else {
      notifyListeners();
    }
  }

  void materialPrice(String id, String raw) {
    if (!editable) return;
    _drafts[_key('material:$id')] = raw;
    final value = parseDecimal(raw);
    if (value != null) {
      _changed(
        savedProject.copyWith(
          materialPrices: {...savedProject.materialPrices, id: value},
        ),
      );
    } else {
      notifyListeners();
    }
  }

  void servicePrice(WorkKind kind, ModelRow row, String raw) {
    if (!editable) return;
    final key = servicePriceKey(kind, row);
    _drafts[_key('service:$key')] = raw;
    final value = parseDecimal(raw);
    if (value != null) {
      _changed(
        savedProject.copyWith(
          servicePrices: {...savedProject.servicePrices, key: value},
        ),
      );
    } else {
      notifyListeners();
    }
  }

  void overridePrice(WorkKind kind, ModelRow row, String raw) {
    if (!editable) return;
    _drafts[_key('override:${kind.name}:${row.id}')] = raw;
    final value = parseDecimal(raw);
    if (value != null) {
      final work = savedProject.work(kind);
      _changed(
        savedProject.updateWork(
          work.copyWith(
            priceOverrides: {...work.priceOverrides, row.id: value},
          ),
        ),
      );
    } else {
      notifyListeners();
    }
  }

  void clearOverride(WorkKind kind, ModelRow row) {
    if (!editable) return;
    _drafts.remove(_key('override:${kind.name}:${row.id}'));
    final work = savedProject.work(kind);
    final overrides = Map<String, double?>.of(work.priceOverrides)
      ..remove(row.id);
    _changed(savedProject.updateWork(work.copyWith(priceOverrides: overrides)));
  }

  bool hasOverride(WorkKind kind, ModelRow row) =>
      savedProject.work(kind).priceOverrides.containsKey(row.id) ||
      _drafts.containsKey(_key('override:${kind.name}:${row.id}'));

  void include(WorkKind kind, bool value) {
    if (!editable) return;
    _changed(
      savedProject.updateWork(
        savedProject.work(kind).copyWith(included: value),
      ),
    );
  }

  double? price(WorkEntry work, ModelRow row) {
    return rowPrice(project, work, row);
  }

  List<WorkModel> modelsFor(WorkKind kind) {
    final models = <String, WorkModel>{
      for (final model in builtInModels.where((m) => m.kind == kind))
        model.id: model,
      for (final model in state!.customModels.where((m) => m.kind == kind))
        model.id: model,
    };
    final snapshot = savedProject.work(kind).model;
    if (snapshot != null) models[snapshot.id] = snapshot;
    return models.values.toList();
  }

  Future<void> selectModel(
    WorkKind kind,
    WorkModel model, {
    bool register = false,
  }) async {
    final old = savedProject.work(kind);
    final unitChanged = old.model?.inputUnit != model.inputUnit;
    final compatibleRows = <String>{};
    for (final row in model.rows) {
      final oldRow = old.model?.rows
          .where((value) => value.id == row.id)
          .firstOrNull;
      if (oldRow != null &&
          oldRow.materialId == row.materialId &&
          oldRow.unit == row.unit) {
        compatibleRows.add(row.id);
      }
    }
    final entry = old.copyWith(
      model: model,
      quantity: unitChanged ? null : old.quantity,
      priceOverrides: {
        for (final override in old.priceOverrides.entries)
          if (compatibleRows.contains(override.key))
            override.key: override.value,
      },
    );
    var next = state!.updateProject(savedProject.updateWork(entry));
    if (register) {
      next = next.copyWith(
        customModels: [
          for (final existing in next.customModels)
            if (existing.id != model.id) existing,
          model,
        ],
      );
    }
    await _commit(next);
    if (unitChanged) _drafts.remove(_key('quantity:${kind.name}'));
    final overridePrefix = _key('override:${kind.name}:');
    _drafts.removeWhere(
      (key, _) =>
          key.startsWith(overridePrefix) &&
          !compatibleRows.contains(key.substring(overridePrefix.length)),
    );
    if (!_disposed) notifyListeners();
  }

  Future<void> selectProject(String id) =>
      _commit(state!.copyWith(currentProjectId: id));

  Future<void> addProject({bool example = false}) async {
    final created = example ? createExampleProject() : createProject();
    await _commit(
      state!.copyWith(
        projects: [...state!.projects, created],
        currentProjectId: created.id,
      ),
    );
  }

  Future<void> metadata(String name, String date, String location) => _commit(
    state!.updateProject(
      savedProject.copyWith(
        name: name.trim(),
        date: date,
        location: location.trim(),
      ),
    ),
  );

  Future<void> _commit(ProjectState next) async {
    if (!editable) throw StateError('الحفظ غير متاح الآن');
    _debounce?.cancel();
    saving = true;
    notifyListeners();
    try {
      await repository.save(next);
      state = next;
      warning = null;
    } catch (_) {
      warning =
          'تعذّر حفظ التعديل. بقيت البيانات السابقة محفوظة؛ حاول مرة أخرى.';
      rethrow;
    } finally {
      saving = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> saveNow() async {
    _debounce?.cancel();
    if (!loaded || !repository.canWrite || saving) return;
    try {
      await repository.save(state!);
      warning = null;
    } catch (_) {
      warning =
          'تعذّر الحفظ التلقائي. التعديلات الحالية ظاهرة، حاول الحفظ مجددًا.';
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    super.dispose();
  }
}
