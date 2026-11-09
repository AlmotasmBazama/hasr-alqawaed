import 'dart:math';
import 'package:flutter/material.dart';
import '../domain/models.dart';
import '../domain/numbers.dart';
import 'app_theme.dart';

class ModelEditor extends StatefulWidget {
  const ModelEditor({
    super.key,
    required this.source,
    required this.suggestedName,
    required this.onSave,
    this.editing = false,
  });
  final FoundationModel source;
  final String suggestedName;
  final bool editing;
  final Future<void> Function(FoundationModel) onSave;
  @override
  State<ModelEditor> createState() => _ModelEditorState();
}

class _ModelEditorState extends State<ModelEditor> {
  final _formKey = GlobalKey<FormState>();
  late final List<TextEditingController> _fields;
  late final String _id;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final m = widget.source;
    _id = widget.editing
        ? m.id
        : 'custom_${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(0x7fffffff)}';
    _fields = [
      widget.suggestedName,
      inputNumber(m.length),
      inputNumber(m.width),
      inputNumber(m.height),
      inputNumber(m.concretePerFoundation),
      inputNumber(m.steel14BarsPerFoundation),
      inputNumber(m.steel14BarsPerQuintal),
      inputNumber(m.steel8BarsPerFoundation),
      inputNumber(m.steel8BarsPerQuintal),
    ].map((value) => TextEditingController(text: value)).toList();
  }

  @override
  void dispose() {
    for (final c in _fields) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    double n(int i) => parseDecimal(_fields[i].text)!;
    try {
      final model = FoundationModel(
        id: _id,
        name: _fields[0].text.trim().replaceAll(RegExp(r'\s+'), ' '),
        length: n(1),
        width: n(2),
        height: n(3),
        concretePerFoundation: n(4),
        steel14BarsPerFoundation: n(5),
        steel14BarsPerQuintal: n(6),
        steel8BarsPerFoundation: n(7),
        steel8BarsPerQuintal: n(8),
      );
      await widget.onSave(model);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'تعذر حفظ النموذج. حاول مرة أخرى.';
        });
      }
    }
  }

  Widget _number(
    int i,
    String label, {
    bool positive = false,
    String? helper,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      key: ValueKey('model_field_$i'),
      controller: _fields[i],
      enabled: !_saving,
      textDirection: TextDirection.ltr,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        errorMaxLines: 2,
      ),
      validator: (value) {
        final n = parseDecimal(value ?? '');
        if (n == null) {
          return 'أدخل رقمًا صالحًا';
        }
        if (positive ? n <= 0 : n < 0) {
          return positive
              ? 'يجب أن تكون القيمة أكبر من صفر'
              : 'أدخل صفرًا أو قيمة موجبة';
        }
        return null;
      },
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.editing ? 'تعديل النموذج' : 'إضافة نموذج'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  TextFormField(
                    key: const ValueKey('model_name'),
                    controller: _fields[0],
                    enabled: !_saving,
                    maxLength: 80,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'اسم النموذج',
                      counterText: '',
                    ),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? 'أدخل اسم النموذج' : null,
                  ),
                  const SectionHeading(
                    'الأبعاد بالمتر',
                    icon: Icons.straighten_rounded,
                  ),
                  _number(1, 'الطول (م)', positive: true),
                  _number(2, 'العرض (م)', positive: true),
                  _number(3, 'الارتفاع (م)', positive: true),
                  const SectionHeading(
                    'كميات القاعدة الواحدة',
                    icon: Icons.layers_outlined,
                  ),
                  _number(4, 'الخرسانة (م³)', helper: 'الكمية المعتمدة للحساب'),
                  const SectionHeading('حديد 14'),
                  _number(5, 'أسياخ لكل قاعدة'),
                  _number(6, 'أسياخ لكل قنطار', positive: true),
                  const SectionHeading('حديد 8'),
                  _number(7, 'أسياخ لكل قاعدة'),
                  _number(8, 'أسياخ لكل قنطار', positive: true),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            widget.editing
                                ? 'حفظ التعديلات'
                                : 'حفظ واستخدام النموذج',
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
