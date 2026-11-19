import 'package:flutter/material.dart';

import '../project/engine.dart';
import '../project/models.dart';
import 'app_theme.dart';
import 'project_widgets.dart';

class QuantityProjectCard extends StatelessWidget {
  const QuantityProjectCard({
    super.key,
    required this.project,
    required this.result,
    required this.openProjects,
    required this.edit,
  });

  final Project project;
  final ProjectResult result;
  final VoidCallback? openProjects;
  final VoidCallback? edit;

  @override
  Widget build(BuildContext context) {
    final scope = result.works.where((w) => w.status != WorkStatus.excluded);
    final ready = scope
        .where(
          (w) =>
              w.status == WorkStatus.calculated ||
              w.status == WorkStatus.zeroQuantity,
        )
        .length;
    final fraction = scope.isEmpty ? 0.0 : ready / scope.length;
    return LayoutBuilder(
      builder: (context, bounds) {
        final wide = bounds.maxWidth >= 650;
        final artWidth = wide ? 208.0 : 90.0;
        final padding = wide ? 24.0 : 14.0;
        final showArt = MediaQuery.textScalerOf(context).scale(1) < 1.5;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [Color(0xFF163E33), Color(0xFF215744), Color(0xFF246451)],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Stack(
            children: [
              if (showArt)
                Positioned(
                  left: wide ? 22 : 7,
                  top: 6,
                  bottom: 6,
                  width: artWidth,
                  child: const IgnorePointer(
                    child: ExcludeSemantics(child: FoundationStudy()),
                  ),
                ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  showArt ? artWidth + padding : padding,
                  padding,
                  padding,
                  padding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (project.isExample)
                      const Text(
                        'مثال توضيحي مستقل',
                        style: TextStyle(
                          color: Color(0xFFDBD39A),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          child: InkWell(
                            onTap: openProjects,
                            borderRadius: BorderRadius.circular(8),
                            child: Text(
                              project.name,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: wide ? 27 : 21,
                                fontWeight: FontWeight.w700,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('edit_project'),
                          tooltip: 'تعديل بيانات المشروع',
                          onPressed: edit,
                          color: const Color(0xFFC6DED1),
                          iconSize: 17,
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 14,
                      runSpacing: 3,
                      children: [
                        _Meta(
                          Icons.place_outlined,
                          project.location.isEmpty
                              ? 'لم يُحدَّد الموقع'
                              : project.location,
                        ),
                        _Meta(Icons.event_outlined, project.date),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      scope.isEmpty
                          ? 'كل البنود غير مطلوبة'
                          : 'اكتمال البنود  $ready من ${scope.length}',
                      style: const TextStyle(
                        color: Color(0xFFE2EEE6),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 5),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 255),
                      child: ExcludeSemantics(
                        child: LinearProgressIndicator(
                          value: fraction,
                          minHeight: 4,
                          borderRadius: BorderRadius.circular(9),
                          backgroundColor: const Color(0xFF47705F),
                          color: const Color(0xFFC4DFA1),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: const Color(0xFFB6D5C5)),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          text,
          style: const TextStyle(fontSize: 12, color: Color(0xFFE2EEE6)),
        ),
      ),
    ],
  );
}

IconData workIcon(WorkKind kind) => switch (kind) {
  WorkKind.foundations => Icons.foundation_outlined,
  WorkKind.belowMasonry || WorkKind.aboveMasonry => Icons.view_module_outlined,
  WorkKind.tieBeam => Icons.straighten_outlined,
  WorkKind.leanSlab => Icons.layers_outlined,
  WorkKind.columns => Icons.view_column_outlined,
  WorkKind.roof => Icons.roofing_outlined,
};

class QuantityWorkCard extends StatelessWidget {
  const QuantityWorkCard({
    super.key,
    required this.result,
    required this.title,
    required this.status,
    required this.quantity,
    required this.showAreaLabel,
    this.beams,
    required this.details,
    required this.toggleInclusion,
  });

  final WorkResult result;
  final String title;
  final String status;
  final Widget quantity;
  final bool showAreaLabel;
  final Widget? beams;
  final VoidCallback details;
  final VoidCallback? toggleInclusion;

  @override
  Widget build(BuildContext context) {
    final kind = result.kind;
    final excluded = result.entry.explicitlyExcluded;
    final ready = result.status == WorkStatus.calculated;
    final statusColor = switch (result.status) {
      WorkStatus.calculated => const Color(0xFF246450),
      WorkStatus.needsData || WorkStatus.noModel => const Color(0xFF855A25),
      _ => secondaryText,
    };
    Widget roofField(String name, Widget field) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          name,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        field,
      ],
    );
    final titleBlock = Tooltip(
      message: 'تفاصيل النموذج',
      child: InkWell(
        key: ValueKey('work_${kind.name}'),
        onTap: details,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: excluded ? paper : const Color(0xFFEAF2EB),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(7),
                  child: Icon(
                    workIcon(kind),
                    size: 19,
                    color: excluded ? secondaryText : primaryGreen,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            result.entry.model?.name ?? 'اختيار نموذج',
                            style: const TextStyle(
                              color: primaryGreen,
                              fontSize: 12,
                              height: 1.5,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.chevron_left_rounded,
                          size: 16,
                          color: primaryGreen,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
      child: LayoutBuilder(
        builder: (context, bounds) {
          final scaled = MediaQuery.textScalerOf(context).scale(1);
          final stacked = scaled > 1.3 || bounds.maxWidth < 230;
          final displayQuantity = !excluded && kind != WorkKind.roof;
          final separateRoofFields = scaled > 1.25 || bounds.maxWidth < 400;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!displayQuantity)
                titleBlock
              else if (stacked) ...[
                titleBlock,
                const SizedBox(height: 10),
                quantity,
              ] else
                Row(
                  children: [
                    Expanded(child: titleBlock),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: bounds.maxWidth > 370 ? 116 : 76,
                      child: quantity,
                    ),
                  ],
                ),
              if (!excluded && kind == WorkKind.roof) ...[
                const SizedBox(height: 12),
                if (beams == null)
                  showAreaLabel ? roofField('مساحة السقف', quantity) : quantity
                else if (separateRoofFields) ...[
                  roofField('مساحة السقف', quantity),
                  const SizedBox(height: 12),
                  roofField('إجمالي أطوال كمرات السقف', beams!),
                ] else
                  Row(
                    children: [
                      Expanded(child: roofField('مساحة السقف', quantity)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: roofField('إجمالي أطوال كمرات السقف', beams!),
                      ),
                    ],
                  ),
                if (beams != null &&
                    (result.entry.quantity == null ||
                        result.entry.quantity! > 0 &&
                            result.entry.roofBeamLength == null))
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'أدخل مساحة السقف وأطوال الكمرات.',
                      style: TextStyle(color: secondaryText, fontSize: 12),
                    ),
                  ),
              ],
              const SizedBox(height: 9),
              const Divider(),
              OverflowBar(
                alignment: MainAxisAlignment.spaceBetween,
                overflowAlignment: OverflowBarAlignment.start,
                children: [
                  Wrap(
                    spacing: 5,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Icon(
                        ready
                            ? Icons.check_circle_outline_rounded
                            : excluded
                            ? Icons.remove_circle_outline
                            : result.status == WorkStatus.zeroQuantity
                            ? Icons.check_rounded
                            : Icons.circle_outlined,
                        size: 14,
                        color: statusColor,
                      ),
                      Text(
                        status,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  TextButton(
                    key: ValueKey('include_${kind.name}'),
                    onPressed: toggleInclusion,
                    style: TextButton.styleFrom(
                      foregroundColor: excluded ? primaryGreen : secondaryText,
                      textStyle: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: Text(excluded ? 'إضافة للحصر' : 'غير مطلوب'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
