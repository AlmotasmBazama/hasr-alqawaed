import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../data/app_repository.dart';
import '../domain/calculator.dart';
import '../domain/models.dart';
import '../domain/numbers.dart';
import '../services/report_service.dart';
import '../services/browser_pdf.dart';
import 'app_theme.dart';
import 'model_editor.dart';
import 'pdf_export_dialog.dart';

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key, required this.repository});
  final AppRepository repository;
  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen>
    with WidgetsBindingObserver {
  AppData? _data;
  final _count = TextEditingController();
  final _prices = List.generate(6, (_) => TextEditingController());
  Timer? _debounce;
  bool _sharing = false;
  bool _savingModel = false;
  String? _storageMessage;
  int _saveVersion = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    final loaded = await widget.repository.load();
    if (!mounted) {
      return;
    }
    _data = loaded.data;
    _storageMessage = loaded.warning;
    _count.text = _data!.inputs.count.toString();
    for (var i = 0; i < 6; i++) {
      _prices[i].text = inputNumber(_data!.inputs.prices.values[i]);
    }
    _count.addListener(_changed);
    for (final c in _prices) {
      c.addListener(_changed);
    }
    setState(() {});
  }

  Prices _priceValues(List<double> p) => Prices(
    concrete: p[0],
    steel14: p[1],
    steel8: p[2],
    carpenter: p[3],
    steelWorker: p[4],
    casting: p[5],
  );

  CalculatorInputs? get _currentInputs {
    final n = parsePositiveCount(_count.text);
    final p = _prices.map((c) => parseDecimal(c.text)).toList();
    if (n == null || p.any((v) => v == null)) {
      return null;
    }
    return CalculatorInputs(count: n, prices: _priceValues(p.cast<double>()));
  }

  CalculationResult? get _result {
    final inputs = _currentInputs;
    if (inputs == null || _data == null) {
      return null;
    }
    try {
      return calculate(_data!.selectedModel, inputs);
    } on ArgumentError {
      return null;
    }
  }

  void _changed() {
    // Persist each valid field, while preserving the last valid value of drafts.
    final previous = _data!.inputs;
    final p = List.generate(
      6,
      (i) => parseDecimal(_prices[i].text) ?? previous.prices.values[i],
    );
    _data = _data!.copyWith(
      inputs: CalculatorInputs(
        count: parsePositiveCount(_count.text) ?? previous.count,
        prices: _priceValues(p),
      ),
    );
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _persist);
  }

  Future<void> _persist() async {
    if (_data == null || _savingModel || !widget.repository.canWrite) {
      return;
    }
    final version = ++_saveVersion;
    try {
      await widget.repository.save(_data!);
      if (mounted && version == _saveVersion && _storageMessage != null) {
        setState(() => _storageMessage = null);
      }
    } catch (_) {
      if (mounted && version == _saveVersion) {
        setState(
          () =>
              _storageMessage = 'تعذر حفظ التغييرات على الجهاز. أعد المحاولة.',
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _debounce?.cancel();
      unawaited(_persist());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    _count.dispose();
    for (final c in _prices) {
      c.dispose();
    }
    super.dispose();
  }

  String _dimensions(FoundationModel m) =>
      '${formatNumber(m.length)} × ${formatNumber(m.width)} × ${formatNumber(m.height)} م';

  Future<void> _edit({FoundationModel? model}) async {
    FocusScope.of(context).unfocus();
    _debounce?.cancel();
    await _persist();
    if (!mounted) {
      return;
    }
    var nextNumber = _data!.customModels.length + 2;
    while (_data!.models.any((m) => m.name == 'نموذج $nextNumber')) {
      nextNumber++;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ModelEditor(
          source: model ?? _data!.selectedModel,
          editing: model != null,
          suggestedName: model?.name ?? 'نموذج $nextNumber',
          onSave: (updated) async {
            final next = _data!.upsertModel(updated);
            _savingModel = true;
            try {
              await widget.repository.save(next);
              if (mounted) {
                setState(() {
                  _data = next;
                  _storageMessage = null;
                });
              }
            } finally {
              _savingModel = false;
            }
          },
        ),
      ),
    );
  }

  Future<void> _chooseModel() async {
    FocusScope.of(context).unfocus();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .75,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              const Text(
                'اختيار النموذج',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
              ),
              const SizedBox(height: 12),
              for (final m in _data!.models)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 6,
                    horizontal: 4,
                  ),
                  leading: Icon(
                    m.id == _data!.selectedModelId
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: primaryGreen,
                  ),
                  title: Text(m.name),
                  subtitle: Text(
                    _dimensions(m),
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.right,
                  ),
                  trailing: m.isBuiltIn
                      ? const Icon(
                          Icons.lock_outline,
                          size: 19,
                          color: secondaryText,
                        )
                      : IconButton(
                          key: ValueKey('edit_model_${m.id}'),
                          tooltip: 'تعديل ${m.name}',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            _edit(model: m);
                          },
                        ),
                  onTap: () {
                    _debounce?.cancel();
                    setState(() => _data = _data!.selectModel(m.id));
                    unawaited(_persist());
                    Navigator.pop(sheetContext);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _share() async {
    final inputs = _currentInputs;
    final result = _result;
    if (_sharing || inputs == null || result == null) {
      return;
    }
    final snapshot = ReportSnapshot(
      model: _data!.selectedModel,
      inputs: inputs,
      result: result,
      createdAt: DateTime.now(),
    );
    FocusScope.of(context).unfocus();
    setState(() => _sharing = true);
    try {
      if (kIsWeb) {
        final bytes = await ReportService.generate(snapshot);
        final file = prepareBrowserPdf(bytes, snapshot.filename);
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) =>
              PdfExportDialog(file: file, filename: snapshot.filename),
        );
      } else {
        final box = context.findRenderObject() as RenderBox?;
        final bounds = box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size;
        await ReportService.share(snapshot, bounds: bounds);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر إنشاء التقرير أو فتح المشاركة. حاول مرة أخرى.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sharing = false);
      }
    }
  }

  Widget _item(int i, CalculationResult? result) {
    const names = ['خرسانة مسلحة', 'حديد 14', 'حديد 8', 'نجار', 'حداد', 'صب'];
    const units = ['م³', 'قنطار', 'قنطار', 'قاعدة', 'قاعدة', 'قاعدة'];
    final line = result?.lines[i];
    final invalid = parseDecimal(_prices[i].text) == null;
    final description = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          names[i],
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        const SizedBox(height: 4),
        Text(
          line == null
              ? '— ${units[i]}'
              : '${formatNumber(line.quantity)} ${units[i]}',
          style: const TextStyle(color: secondaryText, fontSize: 12),
        ),
      ],
    );
    final cost = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          line == null ? '—' : formatNumber(line.cost),
          textDirection: TextDirection.ltr,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: primaryGreen,
            fontSize: 17,
          ),
        ),
        const Text('د.ل', style: TextStyle(fontSize: 11, color: secondaryText)),
      ],
    );
    final field = TextField(
      key: ValueKey('price_$i'),
      controller: _prices[i],
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: i == 5 ? TextInputAction.done : TextInputAction.next,
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      decoration: InputDecoration(
        labelText: 'سعر الوحدة',
        labelStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.normal,
        ),
        helperText: 'د.ل / ${units[i]}',
        helperStyle: const TextStyle(fontSize: 10, color: secondaryText),
        helperMaxLines: 2,
        errorText: invalid ? 'أدخل سعرًا صالحًا' : null,
        errorMaxLines: 2,
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      ),
    );
    return Padding(
      padding: const EdgeInsets.all(14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scaled = MediaQuery.textScalerOf(context).scale(14) > 18;
          if (constraints.maxWidth < 290 || scaled) {
            return Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: description),
                    const SizedBox(width: 12),
                    Flexible(child: cost),
                  ],
                ),
                const SizedBox(height: 16),
                field,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 10, child: description),
              const SizedBox(width: 10),
              Expanded(flex: 11, child: field),
              const SizedBox(width: 10),
              Expanded(flex: 9, child: cost),
            ],
          );
        },
      ),
    );
  }

  Widget _group(int start, CalculationResult? result) => SurfaceCard(
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        for (var i = start; i < start + 3; i++) ...[
          if (i > start)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Divider(),
            ),
          _item(i, result),
        ],
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final result = _result;
    final countValid = parsePositiveCount(_count.text) != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('حصر القواعد'),
        actions: [
          TextButton.icon(
            key: const ValueKey('add_model'),
            onPressed: _edit,
            icon: const Icon(Icons.add, size: 19),
            label: const Text('نموذج'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: ListView(
              key: const ValueKey('calculator_scroll'),
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                const Text(
                  'الكميات والتكلفة، في حسبة واحدة',
                  style: TextStyle(color: secondaryText, fontSize: 13),
                ),
                const SizedBox(height: 18),
                if (_storageMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: SurfaceCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _storageMessage!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                          if (widget.repository.canWrite)
                            TextButton(
                              onPressed: _persist,
                              child: const Text('إعادة محاولة الحفظ'),
                            ),
                        ],
                      ),
                    ),
                  ),
                Semantics(
                  button: true,
                  label: 'اختيار النموذج',
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      key: const ValueKey('choose_model'),
                      onTap: _chooseModel,
                      borderRadius: BorderRadius.circular(16),
                      child: SurfaceCard(
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: primaryGreen.withValues(alpha: .08),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.foundation_outlined,
                                color: primaryGreen,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    data.selectedModel.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 17,
                                    ),
                                  ),
                                  Text(
                                    _dimensions(data.selectedModel),
                                    textDirection: TextDirection.ltr,
                                    style: const TextStyle(
                                      color: secondaryText,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: secondaryText,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  key: const ValueKey('count'),
                  controller: _count,
                  textDirection: TextDirection.ltr,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: InputDecoration(
                    labelText: 'عدد القواعد',
                    prefixIcon: const Icon(
                      Icons.grid_view_rounded,
                      size: 22,
                      color: primaryGreen,
                    ),
                    errorText: countValid
                        ? null
                        : 'أدخل عددًا صحيحًا أكبر من صفر',
                    errorMaxLines: 2,
                  ),
                ),
                const SectionHeading('المواد', icon: Icons.layers_outlined),
                _group(0, result),
                const SectionHeading('التنفيذ', icon: Icons.handyman_outlined),
                _group(3, result),
                const SizedBox(height: 24),
                Container(
                  key: const ValueKey('total_card'),
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: primaryGreen,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'إجمالي التكلفة',
                        style: TextStyle(color: Colors.white, fontSize: 15),
                      ),
                      const SizedBox(height: 6),
                      if (result != null)
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 10,
                          children: [
                            Text(
                              formatNumber(result.totalCost),
                              key: const ValueKey('total_amount'),
                              textDirection: TextDirection.ltr,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 34,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Text(
                              'د.ل',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        )
                      else
                        const Text(
                          'الحسبة غير مكتملة',
                          key: ValueKey('incomplete'),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      if (result == null)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'أكمل الحقول بقيم صالحة لعرض الإجمالي والمشاركة.',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  key: const ValueKey('share_pdf'),
                  onPressed: result == null || _sharing ? null : _share,
                  icon: _sharing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.ios_share_rounded, size: 20),
                  label: Text(
                    _sharing
                        ? 'جارٍ تجهيز التقرير…'
                        : kIsWeb && !supportsBrowserFileSharing
                        ? 'تنزيل PDF'
                        : 'مشاركة PDF',
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'الحساب يعتمد كميات النموذج • الأسعار بالدينار الليبي',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: secondaryText, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
