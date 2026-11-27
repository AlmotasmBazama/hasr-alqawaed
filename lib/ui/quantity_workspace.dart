import 'package:flutter/material.dart';

import '../project/models.dart';
import 'app_theme.dart';
import 'field_help.dart';

class QuantityProjectHeading extends StatelessWidget {
  const QuantityProjectHeading({
    super.key,
    required this.project,
    required this.edit,
  });

  final Project project;
  final VoidCallback? edit;

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (project.location.isNotEmpty) (Icons.place_outlined, project.location),
      if (project.date.isNotEmpty) (Icons.event_outlined, project.date),
    ];
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(2, 0, 2, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  project.name,
                  style: const TextStyle(
                    fontSize: 23,
                    height: 1.5,
                    fontWeight: FontWeight.w700,
                    color: forestInk,
                  ),
                ),
                if (meta.isNotEmpty)
                  Wrap(
                    spacing: 16,
                    runSpacing: 4,
                    children: [
                      for (final (icon, value) in meta)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon, size: 15, color: secondaryText),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                value,
                                style: const TextStyle(
                                  color: secondaryText,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
              ],
            ),
          ),
          IconButton.outlined(
            key: const ValueKey('edit_project'),
            tooltip: 'تعديل بيانات المشروع',
            onPressed: edit,
            style: IconButton.styleFrom(
              side: const BorderSide(color: borderColor),
              foregroundColor: primaryGreen,
            ),
            icon: const Icon(Icons.edit_outlined, size: 18),
          ),
        ],
      ),
    );
  }
}

class QuantityGroup extends StatelessWidget {
  const QuantityGroup(this.title, this.icon, this.rows, {super.key});
  final String title;
  final IconData icon;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: const BoxDecoration(
            color: Color(0xFFEAF1EC),
            borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(icon, color: primaryGreen, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: forestInk,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const Divider(indent: 14, endIndent: 14),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 3, 14, 10),
            child: rows[i],
          ),
        ],
      ],
    ),
  );
}

class QuantityFieldRow extends StatelessWidget {
  const QuantityFieldRow({
    super.key,
    required this.title,
    required this.help,
    required this.input,
    this.details,
    this.toggleInclusion,
    this.excluded = false,
    this.kind,
    this.status,
    this.review,
  });

  final String title;
  final String help;
  final Widget input;
  final WorkKind? kind;
  final bool excluded;
  final String? status;
  final VoidCallback? details;
  final VoidCallback? toggleInclusion;
  final Widget? review;

  @override
  Widget build(BuildContext context) {
    final action = kind == null
        ? null
        : TextButton(
            key: ValueKey('include_${kind!.name}'),
            onPressed: toggleInclusion,
            style: TextButton.styleFrom(
              foregroundColor: excluded ? primaryGreen : secondaryText,
              textStyle: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(44, 44),
            ),
            child: Text(
              excluded ? 'إضافة للحصر' : 'غير مطلوب',
              semanticsLabel:
                  '${excluded ? 'إضافة للحصر' : 'غير مطلوب'} ${kind!.label}',
            ),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.45,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            FieldHelp(title: title, message: help),
            if (kind != null)
              IconButton(
                key: ValueKey('work_${kind!.name}'),
                onPressed: details,
                tooltip: 'تفاصيل نموذج ${kind!.label}',
                icon: const Icon(
                  Icons.tune_rounded,
                  size: 19,
                  color: secondaryText,
                ),
              ),
          ],
        ),
        LayoutBuilder(
          builder: (context, bounds) {
            final stacked =
                bounds.maxWidth < 230 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.35;
            final entryActions = Wrap(
              spacing: 4,
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (status != null)
                  Text(
                    status!,
                    style: TextStyle(
                      fontSize: 12,
                      color: status == 'يحتاج بيانات'
                          ? const Color(0xFF875719)
                          : secondaryText,
                    ),
                  ),
                ?action,
              ],
            );
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [input, entryActions],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: bounds.maxWidth < 350 ? 124 : 152,
                  child: input,
                ),
                const SizedBox(width: 8),
                Expanded(child: entryActions),
              ],
            );
          },
        ),
        ?review,
      ],
    );
  }
}
