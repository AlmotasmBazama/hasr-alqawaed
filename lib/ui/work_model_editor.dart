import 'package:flutter/material.dart';

import '../domain/numbers.dart';
import '../project/catalog.dart';
import '../project/models.dart';
import 'app_theme.dart';
import 'project_widgets.dart';

class WorkModelEditor extends StatefulWidget {
  const WorkModelEditor({
    super.key,
    required this.kind,
    this.initial,
    this.onSave,
  });
  final WorkKind kind;
  final WorkModel? initial;
  final Future<void> Function(WorkModel)? onSave;
  @override
  State<WorkModelEditor> createState() => _WorkModelEditorState();
}

class _WorkModelEditorState extends State<WorkModelEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: widget.initial?.isBuiltIn == true
        ? '${widget.initial!.name} — مخصص'
        : widget.initial?.name ?? '',
  );
  late final _description = TextEditingController(
    text: widget.initial?.description ?? '',
  );
  late QuantityUnit _unit =
      widget.initial?.inputUnit ?? widget.kind.defaultUnit;
  late final String _id = widget.initial != null && !widget.initial!.isBuiltIn
      ? widget.initial!.id
      : 'custom-${widget.kind.name}-${DateTime.now().microsecondsSinceEpoch}';
  late final List<_RowDraft> _rows = [
    for (final row in widget.initial?.rows ?? <ModelRow>[]) _RowDraft(row),
  ];
  bool _saving = false;
  String? _error;
  int _rowSerial = 0;
  bool get _roof => widget.kind == WorkKind.roof;
  bool get _hasExplicitRoofSource =>
      _rows.any((row) => row.quantitySource != QuantitySource.workQuantity);
  bool get _hasLegacyRoofSource =>
      widget.initial?.rows.any(
        (row) => row.quantitySource == QuantitySource.workQuantity,
      ) ??
      false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> _add() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .75,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'إضافة سطر للنموذج',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              for (final material in materialCatalog)
                ListTile(
                  title: Text(material.label),
                  subtitle: Text(material.unit.label),
                  leading: const Icon(Icons.inventory_2_outlined),
                  onTap: () => Navigator.pop(context, material.id),
                ),
              const Divider(),
              ListTile(
                title: const Text('مصنعية أو خدمة مخصصة'),
                leading: const Icon(Icons.handyman_outlined),
                onTap: () => Navigator.pop(context, '__service'),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final id = 'row-${DateTime.now().microsecondsSinceEpoch}-${_rowSerial++}';
    final material = selected == '__service' ? null : materialById(selected);
    setState(() {
      _rows.add(
        _RowDraft(
          ModelRow(
            id: id,
            label: material?.label ?? '',
            materialId: material?.id,
            unit: material?.unit ?? _unit,
            quantitySource:
                !_roof || _hasLegacyRoofSource && !_hasExplicitRoofSource
                ? QuantitySource.workQuantity
                : QuantitySource.roofArea,
            coefficient: 0,
            defaultPrice: material?.defaultPrice ?? 0,
          ),
        ),
      );
      _error = null;
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_rows.isEmpty) {
      setState(() => _error = 'أضف مادة أو خدمة واحدة على الأقل.');
      return;
    }
    if (_roof &&
        _hasExplicitRoofSource &&
        _unit != QuantityUnit.area &&
        _rows.any((row) => row.quantitySource == QuantitySource.workQuantity)) {
      setState(
        () => _error =
            'حدّد مصدرًا واضحًا لكل سطر قبل تغيير وحدة مدخل السقف القديم.',
      );
      return;
    }
    final model = WorkModel(
      id: _id,
      kind: widget.kind,
      name: _name.text.trim(),
      description: _description.text.trim(),
      inputUnit: _hasExplicitRoofSource ? QuantityUnit.area : _unit,
      rows: _rows.map((row) => row.value()).toList(),
    );
    if (!model.isValid) {
      setState(() => _error = 'راجع معاملات النموذج ووحداته.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave?.call(model);
      if (mounted) Navigator.pop(context, model);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'تعذّر حفظ النموذج. بقيت تعديلاتك هنا؛ حاول مرة أخرى.';
        });
      }
    }
  }

  String? _numberValidator(String? raw, {bool positive = false}) {
    final value = parseDecimal(raw ?? '');
    return value == null || (positive && value <= 0)
        ? (positive ? 'أدخل عددًا أكبر من صفر' : 'أدخل رقمًا غير سالب')
        : null;
  }

  Widget _numeric(
    TextEditingController controller,
    String label, {
    bool positive = false,
    Key? key,
  }) => TextFormField(
    key: key,
    controller: controller,
    enabled: !_saving,
    textDirection: TextDirection.ltr,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(labelText: label, errorMaxLines: 3),
    validator: (raw) => _numberValidator(raw, positive: positive),
  );

  Widget _rowEditor(_RowDraft row, int index) => Padding(
    key: ValueKey(row.row.id),
    padding: const EdgeInsets.only(bottom: 16),
    child: SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  'السطر ${index + 1} • ${row.isMaterial ? 'مادة' : 'مصنعية / خدمة'}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: primaryGreen,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'حذف السطر',
                onPressed: _saving
                    ? null
                    : () => setState(() {
                        _rows.remove(row);
                        row.dispose();
                      }),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          DropdownButtonFormField<String>(
            initialValue: row.materialId ?? '__service',
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'المادة أو الخدمة'),
            items: [
              for (final material in materialCatalog)
                DropdownMenuItem(
                  value: material.id,
                  child: Text(material.label),
                ),
              const DropdownMenuItem(
                value: '__service',
                child: Text('مصنعية أو خدمة'),
              ),
            ],
            onChanged: _saving
                ? null
                : (value) => setState(() {
                    final material = value == '__service' || value == null
                        ? null
                        : materialById(value);
                    row.selectMaterial(material);
                  }),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: row.label,
            enabled: !_saving,
            decoration: const InputDecoration(labelText: 'اسم السطر'),
            validator: (value) =>
                value!.trim().isEmpty ? 'أدخل اسم السطر' : null,
          ),
          if (_roof) ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<QuantitySource>(
              key: ValueKey('roof_source_$index'),
              initialValue: row.quantitySource,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'يُحسب حسب'),
              items: [
                for (final source in QuantitySource.values)
                  if (source != QuantitySource.workQuantity ||
                      _hasLegacyRoofSource)
                    DropdownMenuItem(
                      value: source,
                      child: Text(
                        source == QuantitySource.workQuantity
                            ? 'مدخل النموذج السابق (${_unit.label})'
                            : quantitySourceLabel(source),
                      ),
                    ),
              ],
              onChanged: _saving
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => row.quantitySource = value);
                      }
                    },
            ),
          ],
          const SizedBox(height: 18),
          _numeric(
            row.coefficient,
            'الكمية لكل ${_sourceInputUnit(row.quantitySource).label}',
            key: ValueKey('coefficient_$index'),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<QuantityUnit>(
            key: ValueKey('source_unit_${row.row.id}:${row.materialId}'),
            initialValue: row.sourceUnit ?? row.row.unit,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'وحدة الكمية الأولية'),
            items: [
              for (final unit in QuantityUnit.values)
                DropdownMenuItem(value: unit, child: Text(unit.label)),
            ],
            onChanged: _saving
                ? null
                : (value) => setState(() => row.sourceUnit = value),
          ),
          const SizedBox(height: 16),
          _numeric(
            row.divisor,
            'معامل القسمة للتحويل',
            positive: true,
            key: ValueKey('divisor_$index'),
          ),
          const SizedBox(height: 8),
          Text(
            'الكمية المسعّرة = مقدار البند × المعامل ÷ معامل القسمة. الناتج: ${row.unit.label}',
            style: const TextStyle(fontSize: 12, color: secondaryText),
          ),
          if (row.isMaterial)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text('وحدة الناتج حسب المادة: ${row.unit.label}'),
            )
          else ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<QuantityUnit>(
              initialValue: row.unit,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'وحدة التسعير / الناتج',
              ),
              items: [
                for (final unit in QuantityUnit.values)
                  DropdownMenuItem(value: unit, child: Text(unit.label)),
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(() => row.unit = value!),
            ),
            const SizedBox(height: 16),
            _numeric(row.price, 'السعر الابتدائي (د.ل / ${row.unit.label})'),
            const SizedBox(height: 8),
            const Text(
              'يُستخدم إذا لم يكن للمشروع سعر محفوظ. عدّل السعر الحالي من قسم الأسعار.',
              style: TextStyle(fontSize: 12, color: secondaryText),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('أساس التسعير قابل للمراجعة'),
              subtitle: const Text(
                'تظهر ملاحظة في النتائج والتقرير عند استخدامه',
              ),
              value: row.review,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => row.review = value),
            ),
          ],
        ],
      ),
    ),
  );

  QuantityUnit _sourceInputUnit(QuantitySource source) => switch (source) {
    QuantitySource.workQuantity => _unit,
    QuantitySource.roofArea => QuantityUnit.area,
    QuantitySource.roofBeamLength => QuantityUnit.linear,
  };

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.initial == null
              ? 'إضافة نموذج ${widget.kind.label}'
              : 'تعديل نموذج ${widget.kind.label}',
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ProjectBody(
            children: [
              if (widget.initial?.isBuiltIn == true)
                const Notice(
                  'سيُحفظ التعديل كنموذج مخصص؛ النموذج الأساسي يبقى متاحًا.',
                ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('model_name'),
                controller: _name,
                enabled: !_saving,
                decoration: const InputDecoration(labelText: 'اسم النموذج'),
                validator: (value) =>
                    value!.trim().isEmpty ? 'أدخل اسم النموذج' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _description,
                enabled: !_saving,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'الوصف والأبعاد (اختياري)',
                  helperText: 'الوصف لا يغيّر معاملات الحصر تلقائيًا',
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: 16),
              if (_roof && _hasLegacyRoofSource && !_hasExplicitRoofSource)
                DropdownButtonFormField<QuantityUnit>(
                  initialValue: _unit,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'وحدة مدخل السقف',
                  ),
                  items: [
                    for (final unit in QuantityUnit.values)
                      DropdownMenuItem(value: unit, child: Text(unit.label)),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _unit = value!),
                )
              else if (!_roof)
                Text(
                  'جميع معاملات هذا النموذج لكل ${_unit.label}.',
                  style: const TextStyle(color: secondaryText),
                ),
              const SectionHeading('المواد والمصنعية والخدمات'),
              for (var i = 0; i < _rows.length; i++) _rowEditor(_rows[i], i),
              OutlinedButton.icon(
                key: const ValueKey('add_model_row'),
                onPressed: _saving ? null : _add,
                icon: const Icon(Icons.add),
                label: const Text('إضافة مادة أو خدمة'),
              ),
              if (_error != null) Notice(_error!),
              const SizedBox(height: 20),
              FilledButton.icon(
                key: const ValueKey('save_work_model'),
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check),
                label: Text(_saving ? 'جارٍ الحفظ…' : 'حفظ النموذج'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _RowDraft {
  _RowDraft(this.row)
    : label = TextEditingController(text: row.label),
      coefficient = TextEditingController(text: inputNumber(row.coefficient)),
      divisor = TextEditingController(text: inputNumber(row.divisor)),
      price = TextEditingController(text: inputNumber(row.defaultPrice)),
      unit = row.unit,
      sourceUnit = row.sourceUnit,
      materialId = row.materialId,
      quantitySource = row.quantitySource,
      review = row.reviewBasis;
  final ModelRow row;
  final TextEditingController label;
  final TextEditingController coefficient;
  final TextEditingController divisor;
  final TextEditingController price;
  QuantityUnit unit;
  QuantityUnit? sourceUnit;
  String? materialId;
  QuantitySource quantitySource;
  bool review;
  bool get isMaterial => materialId != null;

  void selectMaterial(MaterialDefinition? material) {
    if (materialId == material?.id) return;
    materialId = material?.id;
    if (material != null) {
      label.text = material.label;
      unit = material.unit;
      sourceUnit = null;
      price.text = inputNumber(material.defaultPrice);
      review = false;
    } else {
      label.clear();
      price.text = '0';
    }
  }

  ModelRow value() => row.copyWith(
    label: label.text.trim(),
    materialId: materialId,
    coefficient: parseDecimal(coefficient.text)!,
    divisor: parseDecimal(divisor.text)!,
    defaultPrice: parseDecimal(price.text)!,
    unit: unit,
    sourceUnit: sourceUnit,
    quantitySource: quantitySource,
    reviewBasis: review,
  );
  void dispose() {
    label.dispose();
    coefficient.dispose();
    divisor.dispose();
    price.dispose();
  }
}
