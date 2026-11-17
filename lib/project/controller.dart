import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/numbers.dart';
import 'catalog.dart';
import 'engine.dart';
import 'models.dart';
import 'repository.dart';

/// Numeric edits retain their exact text during the session. Invalid edits also
/// survive reopening, without overwriting the user's last valid number.
class ProjectController extends ChangeNotifier {
  ProjectController(this.repository);

  final ProjectRepository repository;
  ProjectState? state;
  String? warning;
  bool saving = false;
  bool _disposed = false;
  final Map<String, String> _drafts = {};
  Project? _lastSnapshot;
  ProjectResult? _lastResult;

  bool get loaded => state != null;
  bool get editable => loaded && repository.canWrite && !saving;
  Project get savedProject => state!.currentProject;
  String _key(String field) => '${savedProject.id}:$field';
  String draft(String field, double? value) =>
      _drafts[_key(field)] ??
      savedProject.inputDrafts[field] ??
      (value == null ? '' : inputNumber(value));

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
    final drafts = current.inputDrafts;
    if (drafts.isEmpty) return current;
    final materials = Map<String, double?>.of(current.materialPrices);
    final services = Map<String, double?>.of(current.servicePrices);
    var profit = current.profitPercentage;
    if (drafts.containsKey('profitPercentage')) profit = null;
    for (final material in materialCatalog) {
      if (drafts.containsKey('material:${material.id}')) {
        materials[material.id] = null;
      }
    }
    for (final entry in current.works) {
      var work = entry;
      if (drafts.containsKey('quantity:${entry.kind.name}')) {
        work = work.copyWith(quantity: null);
      }
      if (entry.kind == WorkKind.roof && drafts.containsKey('roofBeamLength')) {
        work = work.copyWith(roofBeamLength: null);
      }
      final overrides = Map<String, double?>.of(work.priceOverrides);
      for (final row in work.model?.rows ?? <ModelRow>[]) {
        final serviceKey = servicePriceKey(work.kind, row);
        if (drafts.containsKey('service:$serviceKey')) {
          services[serviceKey] = null;
        }
        if (drafts.containsKey('override:${work.kind.name}:${row.id}')) {
          overrides[row.id] = null;
        }
      }
      current = current.updateWork(work.copyWith(priceOverrides: overrides));
    }
    return current.copyWith(
      materialPrices: materials,
      servicePrices: services,
      profitPercentage: profit,
    );
  }

  /// Live, uncommitted preview for editing model details only.
  ProjectResult get result => calculateProject(project);

  ProjectResult? get calculatedResult {
    final snapshot = state?.currentProject.calculatedProject;
    if (snapshot == null) return null;
    if (!identical(snapshot, _lastSnapshot)) {
      _lastSnapshot = snapshot;
      _lastResult = calculateProject(snapshot);
    }
    return _lastResult;
  }

  bool get needsRecalculation =>
      state?.currentProject.calculationStale ?? false;

  Future<void> calculate() async {
    final snapshot = project.copyWith(
      inputDrafts: const {},
      calculatedProject: null,
      calculationStale: false,
    );
    final calculated = calculateProject(snapshot);
    await _commit(
      state!.updateProject(
        savedProject.copyWith(
          calculatedProject: snapshot,
          calculationStale: false,
        ),
      ),
      onSaved: () {
        _lastSnapshot = snapshot;
        _lastResult = calculated;
      },
    );
  }

  Project _stale(Project project) => project.calculatedProject == null
      ? project
      : project.copyWith(calculationStale: true);

  void _changed(Project project) {
    state = state!.updateProject(_stale(project));
    // Queue the write before notifying the UI, so an immediate browser reload
    // cannot leave an intentional edit waiting on an autosave timer.
    unawaited(saveNow());
    notifyListeners();
  }

  Project _withDraft(Project project, String field, String raw, double? value) {
    _drafts[_key(field)] = raw;
    final invalidDrafts = {...project.inputDrafts};
    if (value == null) {
      invalidDrafts[field] = raw;
    } else {
      invalidDrafts.remove(field);
    }
    return project.copyWith(inputDrafts: invalidDrafts);
  }

  void quantity(WorkKind kind, String raw) {
    if (!editable) return;
    final number = parseQuantity(kind, raw);
    var next = _withDraft(savedProject, 'quantity:${kind.name}', raw, number);
    if (number != null) {
      next = next.updateWork(
        next
            .work(kind)
            .copyWith(quantity: number, included: number > 0 ? true : null),
      );
    }
    _changed(next);
  }

  void roofBeamLength(String raw) {
    if (!editable) return;
    final number = parseDecimal(raw);
    var next = _withDraft(savedProject, 'roofBeamLength', raw, number);
    if (number != null) {
      next = next.updateWork(
        next
            .work(WorkKind.roof)
            .copyWith(
              roofBeamLength: number,
              included: number > 0 ? true : null,
            ),
      );
    }
    _changed(next);
  }

  void profitPercentage(String raw) {
    if (!editable) return;
    final parsed = parseDecimal(raw);
    final value = parsed != null && validProfitPercentage(parsed)
        ? parsed
        : null;
    final next = _withDraft(savedProject, 'profitPercentage', raw, value);
    _changed(value == null ? next : next.copyWith(profitPercentage: value));
  }

  void materialPrice(String id, String raw) {
    if (!editable) return;
    final value = parseDecimal(raw);
    final next = _withDraft(savedProject, 'material:$id', raw, value);
    _changed(
      value == null
          ? next
          : next.copyWith(materialPrices: {...next.materialPrices, id: value}),
    );
  }

  void servicePrice(WorkKind kind, ModelRow row, String raw) {
    if (!editable) return;
    final key = servicePriceKey(kind, row);
    final value = parseDecimal(raw);
    final next = _withDraft(savedProject, 'service:$key', raw, value);
    _changed(
      value == null
          ? next
          : next.copyWith(servicePrices: {...next.servicePrices, key: value}),
    );
  }

  void overridePrice(WorkKind kind, ModelRow row, String raw) {
    if (!editable) return;
    final value = parseDecimal(raw);
    var next = _withDraft(
      savedProject,
      'override:${kind.name}:${row.id}',
      raw,
      value,
    );
    if (value != null) {
      final work = next.work(kind);
      next = next.updateWork(
        work.copyWith(priceOverrides: {...work.priceOverrides, row.id: value}),
      );
    }
    _changed(next);
  }

  void clearOverride(WorkKind kind, ModelRow row) {
    if (!editable) return;
    final field = 'override:${kind.name}:${row.id}';
    _drafts.remove(_key(field));
    final work = savedProject.work(kind);
    final overrides = Map<String, double?>.of(work.priceOverrides)
      ..remove(row.id);
    final drafts = {...savedProject.inputDrafts}..remove(field);
    _changed(
      savedProject
          .updateWork(work.copyWith(priceOverrides: overrides))
          .copyWith(inputDrafts: drafts),
    );
  }

  bool hasOverride(WorkKind kind, ModelRow row) =>
      savedProject.work(kind).priceOverrides.containsKey(row.id) ||
      savedProject.inputDrafts.containsKey('override:${kind.name}:${row.id}');

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
    final unitChanged = old.inputUnit != model.inputUnit;
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
    final quantityField = 'quantity:${kind.name}';
    final overrideFieldPrefix = 'override:${kind.name}:';
    bool discardDraft(String field) =>
        (unitChanged && field == quantityField) ||
        (field.startsWith(overrideFieldPrefix) &&
            !compatibleRows.contains(
              field.substring(overrideFieldPrefix.length),
            ));
    final drafts = {...savedProject.inputDrafts}
      ..removeWhere((field, _) => discardDraft(field));
    var next = state!.updateProject(
      _stale(savedProject.updateWork(entry).copyWith(inputDrafts: drafts)),
    );
    if (register) {
      next = next.upsertModel(model);
    }
    await _commit(next);
    final draftPrefix = '${savedProject.id}:';
    _drafts.removeWhere(
      (key, _) =>
          key.startsWith(draftPrefix) &&
          discardDraft(key.substring(draftPrefix.length)),
    );
    if (!_disposed) notifyListeners();
  }

  Future<void> selectProject(String id) =>
      _commit(state!.copyWith(currentProjectId: id));

  Future<void> addProject({
    bool example = false,
    bool fullExample = false,
  }) async {
    final created = fullExample
        ? createFullExampleProject()
        : example
        ? createExampleProject()
        : createProject();
    await _commit(
      state!.copyWith(
        projects: [...state!.projects, created],
        currentProjectId: created.id,
      ),
    );
  }

  Future<void> metadata(String name, String date, String location) => _commit(
    state!.updateProject(
      _stale(
        savedProject.copyWith(
          name: name.trim(),
          date: date,
          location: location.trim(),
        ),
      ),
    ),
  );

  Future<void> _commit(ProjectState next, {VoidCallback? onSaved}) async {
    if (!editable) throw StateError('الحفظ غير متاح الآن');
    saving = true;
    notifyListeners();
    try {
      await repository.save(next);
      state = next;
      onSaved?.call();
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
    super.dispose();
  }
}
