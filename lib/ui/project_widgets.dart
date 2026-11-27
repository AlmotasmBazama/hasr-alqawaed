import 'package:flutter/material.dart';

import '../domain/numbers.dart';
import '../project/engine.dart';
import '../project/models.dart';
import 'app_theme.dart';

export 'foundation_study.dart';

String money(num value) {
  final text = formatNumber(value);
  if (!value.isFinite) return text;
  return text.contains('.')
      ? text.padRight(text.length + 2 - text.split('.').last.length, '0')
      : '$text.00';
}

String statusLabel(WorkStatus status) => switch (status) {
  WorkStatus.calculated => 'محسوب',
  WorkStatus.needsData => 'يحتاج بيانات',
  WorkStatus.unentered => 'لم يُدرج',
  WorkStatus.excluded => 'غير مطلوب — خارج الحساب',
  WorkStatus.noModel => 'يحتاج نموذجًا',
  WorkStatus.zeroQuantity => 'لا توجد كمية',
};

String measure(num value) {
  if (!value.isFinite) return '—';
  final parts = value.toStringAsFixed(6).split('.');
  if (parts.length != 2) return inputNumber(value);
  final whole = parts.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  final fraction = parts.last.replaceFirst(RegExp(r'0+$'), '');
  return fraction.isEmpty ? whole : '$whole.$fraction';
}

String quantitySourceLabel(QuantitySource source) => switch (source) {
  QuantitySource.workQuantity => 'مقدار البند',
  QuantitySource.roofArea => 'مساحة السقف',
  QuantitySource.roofBeamLength => 'أطوال الكمرات',
};

/// Controllers belong to fields, not builds. The edit text comes from the
/// project controller when a tab or a project is revisited.
class NumberInput extends StatefulWidget {
  const NumberInput({
    super.key,
    required this.text,
    this.label,
    required this.onChanged,
    this.semanticLabel,
    this.error,
    this.helperText,
    this.displayErrors = false,
    this.suffixText,
    this.enabled = true,
    this.integer = false,
    this.focusNode,
    this.onNext,
  });
  final String text;
  final String? label;
  final ValueChanged<String> onChanged;
  final String? semanticLabel;
  final String? error;
  final String? helperText;
  final bool displayErrors;
  final String? suffixText;
  final bool enabled;
  final bool integer;
  final FocusNode? focusNode;
  final VoidCallback? onNext;
  @override
  State<NumberInput> createState() => _NumberInputState();
}

class _NumberInputState extends State<NumberInput> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.text,
  );
  late final FocusNode _focus = widget.focusNode ?? FocusNode();
  bool _visited = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted && !_focus.hasFocus && !_visited) {
      setState(() => _visited = true);
    }
  }

  @override
  void didUpdateWidget(NumberInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != _controller.text) {
      final selection = _controller.selection;
      _controller.value = TextEditingValue(
        text: widget.text,
        selection: _focus.hasFocus && selection.isValid
            ? TextSelection(
                baseOffset: selection.baseOffset.clamp(0, widget.text.length),
                extentOffset: selection.extentOffset.clamp(
                  0,
                  widget.text.length,
                ),
                affinity: selection.affinity,
                isDirectional: selection.isDirectional,
              )
            : TextSelection.collapsed(offset: widget.text.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.removeListener(_onFocusChange);
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.semanticLabel,
    child: TextField(
      controller: _controller,
      focusNode: _focus,
      enabled: widget.enabled,
      selectAllOnFocus: false,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      keyboardType: TextInputType.numberWithOptions(decimal: !widget.integer),
      textInputAction: widget.onNext == null
          ? TextInputAction.done
          : TextInputAction.next,
      onEditingComplete: widget.onNext,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        labelText: widget.label,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        errorText: widget.displayErrors || _visited ? widget.error : null,
        helperText: widget.helperText,
        helperMaxLines: 4,
        suffixIcon: widget.suffixText == null
            ? null
            : Padding(
                padding: const EdgeInsetsDirectional.only(end: 10),
                child: Text(
                  widget.suffixText!,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: secondaryText,
                  ),
                ),
              ),
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        errorMaxLines: 3,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 12,
        ),
      ),
      style: const TextStyle(
        fontSize: 18,
        color: forestInk,
        fontFeatures: [FontFeature.tabularFigures()],
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class Notice extends StatelessWidget {
  const Notice(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF6E4),
      border: Border.all(color: const Color(0xFFF0DCAE)),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.info_outline_rounded,
          size: 20,
          color: Color(0xFF86531A),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: Color(0xFF694414), fontSize: 13),
          ),
        ),
      ],
    ),
  );
}

class TotalCard extends StatelessWidget {
  const TotalCard({
    super.key,
    required this.value,
    this.title = 'إجمالي البنود المحسوبة',
    this.large = true,
  });
  final double value;
  final String title;
  final bool large;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.all(large ? 24 : 16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [Color(0xFF153E33), Color(0xFF246B57)],
      ),
      borderRadius: BorderRadius.circular(22),
    ),
    child: Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            money(value),
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFeatures: const [FontFeature.tabularFigures()],
              fontSize: large ? 42 : 27,
              height: 1.4,
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const Text('د.ل', style: TextStyle(color: Colors.white, fontSize: 16)),
      ],
    ),
  );
}

class DetailPair extends StatelessWidget {
  const DetailPair(this.label, this.value, {super.key, this.bold = false});
  final String label;
  final String value;
  final bool bold;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 290 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.35;
        final labelWidget = Text(
          label,
          style: TextStyle(
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          ),
        );
        final valueWidget = Text(
          value,
          textAlign: TextAlign.start,
          style: const TextStyle(fontWeight: FontWeight.w700),
        );
        return stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [labelWidget, const SizedBox(height: 4), valueWidget],
              )
            : Row(
                children: [
                  Expanded(child: labelWidget),
                  const SizedBox(width: 12),
                  Flexible(child: valueWidget),
                ],
              );
      },
    ),
  );
}

class ProjectBody extends StatelessWidget {
  const ProjectBody({super.key, required this.children, this.controller});
  final List<Widget> children;
  final ScrollController? controller;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    controller: controller,
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    padding: EdgeInsets.fromLTRB(
      16,
      MediaQuery.sizeOf(context).width >= 900 ? 24 : 12,
      16,
      32,
    ),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ),
  );
}
