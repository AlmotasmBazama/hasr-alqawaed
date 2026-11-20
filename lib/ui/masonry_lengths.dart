import 'package:flutter/material.dart';

import '../project/controller.dart';
import '../project/engine.dart';
import '../project/models.dart';
import 'app_theme.dart';
import 'field_help.dart';
import 'project_widgets.dart';

String masonryLengthSummary(WorkEntry entry) {
  final value = entry.quantity;
  final basis = entry.linkedToTieBeam ? 'نفس طول الميدة' : 'طول مخصص';
  final length = value != null ? '${measure(value)} م' : 'لم يُحدَّد الطول';
  return '${entry.kind.label}: $length — $basis';
}

class MasonryLengths extends StatelessWidget {
  const MasonryLengths({
    super.key,
    required this.controller,
    required this.result,
    required this.details,
    required this.displayErrors,
  });

  final ProjectController controller;
  final ProjectResult result;
  final ValueChanged<WorkKind> details;
  final bool displayErrors;

  @override
  Widget build(BuildContext context) {
    const kind = WorkKind.tieBeam;
    final entry = result.work(kind).entry;
    final linkedActive = result.works.any(
      (w) => w.entry.linkedToTieBeam && !w.entry.explicitlyExcluded,
    );
    final raw = controller.draft(
      'quantity:tieBeam',
      controller.savedProject.work(kind).quantity,
    );
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'الميدة والمباني',
            style: TextStyle(
              color: forestInk,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: NumberInput(
                  key: ValueKey(
                    '${controller.savedProject.id}:quantity:tieBeam',
                  ),
                  semanticLabel: 'طول الميدة',
                  label: 'طول الميدة — ${entry.inputUnit.label}',
                  text: raw,
                  enabled: controller.editable,
                  displayErrors: displayErrors,
                  error:
                      entry.quantity == null &&
                          (!entry.explicitlyExcluded || linkedActive)
                      ? (raw.trim().isEmpty && linkedActive
                            ? 'أدخل طول الميدة لتعبئة أطوال المباني المرتبطة به.'
                            : 'أدخل قيمة رقمية غير سالبة.')
                      : null,
                  onChanged: (value) => controller.quantity(kind, value),
                ),
              ),
              const FieldHelp(
                title: 'طول الميدة',
                message: 'أدخل مجموع أطوال الميدات بالمتر حسب مخطط المشروع.',
              ),
            ],
          ),
          if (entry.explicitlyExcluded)
            Text(
              statusLabel(WorkStatus.excluded),
              style: const TextStyle(fontSize: 12, color: secondaryText),
            ),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            children: [
              _ModelAction(entry, () => details(kind)),
              _ScopeAction(entry, controller),
            ],
          ),
          for (final masonry in [
            WorkKind.belowMasonry,
            WorkKind.aboveMasonry,
          ]) ...[
            const Divider(),
            _MasonryRow(
              key: ValueKey('${controller.savedProject.id}:${masonry.name}'),
              work: result.work(masonry),
              controller: controller,
              details: () => details(masonry),
              displayErrors: displayErrors,
            ),
          ],
        ],
      ),
    );
  }
}

class _MasonryRow extends StatefulWidget {
  const _MasonryRow({
    super.key,
    required this.work,
    required this.controller,
    required this.details,
    required this.displayErrors,
  });
  final WorkResult work;
  final ProjectController controller;
  final VoidCallback details;
  final bool displayErrors;

  @override
  State<_MasonryRow> createState() => _MasonryRowState();
}

class _MasonryRowState extends State<_MasonryRow> {
  bool editing = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.work.entry;
    final kind = entry.kind;
    final controller = widget.controller;
    final excluded = entry.explicitlyExcluded;
    final linked = entry.linkedToTieBeam;
    final fieldOpen = editing && !linked && !excluded;
    final raw = controller.draft(
      'quantity:${kind.name}',
      controller.savedProject.work(kind).quantity,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                linked ? Icons.link : Icons.straighten_outlined,
                size: 18,
                color: excluded ? secondaryText : primaryGreen,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  masonryLengthSummary(entry),
                  style: TextStyle(
                    color: excluded ? secondaryText : forestInk,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              FieldHelp(
                title: kind.label,
                message: excluded
                    ? (linked
                          ? 'يتبع الطول طول الميدة. اختر «إضافة للحصر» لاستخدام هذا البند.'
                          : 'يحتفظ البند بطوله المخصص. اختر «إضافة للحصر» لاستخدامه.')
                    : (linked
                          ? 'يستخدم هذا البند طول الميدة ويتحدث معه تلقائيًا. اختر تعديل الطول إذا كان طول المباني مختلفًا.'
                          : 'هذا طول مخصص لا يتغير عند تعديل الميدة. اختر استخدام طول الميدة لإعادة الربط.'),
              ),
            ],
          ),
          if (excluded ||
              (entry.quantity != null &&
                  widget.work.status == WorkStatus.needsData) ||
              widget.work.status == WorkStatus.noModel)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                statusLabel(widget.work.status),
                style: const TextStyle(color: secondaryText, fontSize: 12),
              ),
            ),
          if (fieldOpen)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: NumberInput(
                key: ValueKey(
                  '${controller.savedProject.id}:quantity:${kind.name}',
                ),
                text: raw,
                label: 'الطول المخصص — ${entry.inputUnit.label}',
                semanticLabel: 'طول مخصص ${kind.label}',
                enabled: controller.editable,
                displayErrors: widget.displayErrors,
                error: entry.quantity == null
                    ? 'أدخل قيمة رقمية غير سالبة.'
                    : null,
                onChanged: (value) => controller.quantity(kind, value),
              ),
            ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (!excluded)
                _LengthAction(
                  key: ValueKey('edit_length_${kind.name}'),
                  text: fieldOpen ? 'تم' : 'تعديل الطول',
                  kind: kind,
                  onTap: controller.editable
                      ? () {
                          if (linked) {
                            controller.setLinkedToTieBeam(kind, false);
                          }
                          setState(() => editing = !fieldOpen);
                        }
                      : null,
                ),
              if (!linked && !excluded)
                _LengthAction(
                  key: ValueKey('relink_${kind.name}'),
                  text: 'استخدام طول الميدة',
                  kind: kind,
                  onTap: controller.editable
                      ? () {
                          controller.setLinkedToTieBeam(kind, true);
                          setState(() => editing = false);
                        }
                      : null,
                ),
              _ModelAction(entry, widget.details),
              _ScopeAction(entry, controller),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModelAction extends StatelessWidget {
  const _ModelAction(this.entry, this.open);
  final WorkEntry entry;
  final VoidCallback open;

  @override
  Widget build(BuildContext context) => _LengthAction(
    key: ValueKey('work_${entry.kind.name}'),
    kind: entry.kind,
    text: entry.model?.name ?? 'اختيار نموذج',
    semanticLabel: 'تفاصيل نموذج ${entry.kind.label}',
    icon: Icons.tune_rounded,
    muted: true,
    onTap: open,
  );
}

class _ScopeAction extends StatelessWidget {
  const _ScopeAction(this.entry, this.controller);
  final WorkEntry entry;
  final ProjectController controller;

  @override
  Widget build(BuildContext context) => _LengthAction(
    key: ValueKey('include_${entry.kind.name}'),
    kind: entry.kind,
    text: entry.explicitlyExcluded ? 'إضافة للحصر' : 'غير مطلوب',
    muted: !entry.explicitlyExcluded,
    onTap: controller.editable
        ? () => controller.include(entry.kind, entry.explicitlyExcluded)
        : null,
  );
}

class _LengthAction extends StatelessWidget {
  const _LengthAction({
    super.key,
    required this.kind,
    required this.text,
    required this.onTap,
    this.semanticLabel,
    this.icon,
    this.muted = false,
  });
  final WorkKind kind;
  final String text;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final IconData? icon;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      text,
      semanticsLabel: semanticLabel ?? '$text ${kind.label}',
    );
    final style = TextButton.styleFrom(
      foregroundColor: muted ? secondaryText : primaryGreen,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      minimumSize: const Size(44, 44),
      textStyle: const TextStyle(
        fontFamily: 'Cairo',
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
    );
    return icon == null
        ? TextButton(onPressed: onTap, style: style, child: label)
        : TextButton.icon(
            onPressed: onTap,
            style: style,
            icon: Icon(icon, size: 14),
            label: label,
          );
  }
}
