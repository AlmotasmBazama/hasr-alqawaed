import 'package:flutter/material.dart';

import '../project/controller.dart';
import '../project/engine.dart';
import '../project/models.dart';
import 'app_theme.dart';
import 'project_widgets.dart';
import 'work_model_editor.dart';

class WorkDetails extends StatelessWidget {
  const WorkDetails({super.key, required this.controller, required this.kind});
  final ProjectController controller;
  final WorkKind kind;

  Future<void> _editor(BuildContext context, WorkModel? model) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => WorkModelEditor(
            kind: kind,
            initial: model,
            onSave: (model) =>
                controller.selectModel(kind, model, register: true),
          ),
        ),
      );

  Future<void> _select(BuildContext context, WorkModel model) async {
    try {
      await controller.selectModel(kind, model);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذّر حفظ اختيار النموذج. حاول مرة أخرى.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final project = controller.project;
      final entry = project.work(kind);
      final result = controller.needsRecalculation
          ? null
          : controller.calculatedResult?.work(kind);
      final model = entry.model;
      final models = controller.modelsFor(kind);
      return Scaffold(
        appBar: AppBar(title: const Text('تفاصيل النموذج')),
        body: SafeArea(
          child: ProjectBody(
            children: [
              if (controller.saving) const LinearProgressIndicator(),
              SectionHeading(kind.label),
              if (entry.explicitlyExcluded)
                const Notice(
                  'هذا البند غير مطلوب. يمكن إضافته للحصر من الكميات.',
                ),
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (models.isNotEmpty)
                      DropdownButtonFormField<String>(
                        key: ValueKey(
                          '${project.id}:${model?.id}:${model?.name}',
                        ),
                        initialValue: model?.id,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'اختيار النموذج',
                        ),
                        items: [
                          for (final item in models)
                            DropdownMenuItem(
                              value: item.id,
                              child: Text(
                                item.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: controller.editable
                            ? (id) {
                                if (id != null) {
                                  _select(
                                    context,
                                    models.firstWhere((item) => item.id == id),
                                  );
                                }
                              }
                            : null,
                      ),
                    if (model == null)
                      const Notice(
                        'ثوابت النموذج غير متاحة. أضف نموذجًا وحدد وحدة المدخل ومواده وخدماته.',
                      ),
                    if (model?.description.isNotEmpty == true)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          model!.description,
                          style: const TextStyle(color: secondaryText),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          key: const ValueKey('add_work_model'),
                          onPressed: controller.editable
                              ? () => _editor(context, null)
                              : null,
                          icon: const Icon(Icons.add),
                          label: const Text('إضافة نموذج'),
                        ),
                        if (model != null)
                          TextButton.icon(
                            key: const ValueKey('edit_work_model'),
                            onPressed: controller.editable
                                ? () => _editor(context, model)
                                : null,
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('تعديل الثوابت'),
                          ),
                      ],
                    ),
                    const Text(
                      'النموذج يحدد الكميات لكل وحدة. تعديله هنا لا يغيّر تقديرات المشاريع الأخرى.',
                      style: TextStyle(fontSize: 12, color: secondaryText),
                    ),
                  ],
                ),
              ),
              if (model != null) ...[
                if (kind == WorkKind.roof)
                  const Notice(
                    'هذه معاملات حصر كمية. لا تُستخدم للتحقق من التصميم الإنشائي أو سلامة التسليح.',
                  ),
                if (kind == WorkKind.roof &&
                    model.requiresRoofBeamLength &&
                    (entry.quantity == null ||
                        (entry.quantity! > 0 && entry.roofBeamLength == null)))
                  const Notice(
                    'أدخل مساحة السقف وأطوال الكمرات في واجهة الكميات.',
                  ),
                if (model.rows.any((row) => row.reviewBasis))
                  const Notice('تقدير مبدئي — توجد وحدات خدمات قابلة للمراجعة'),
                const SectionHeading('المواد'),
                for (final row in model.rows.where((row) => row.isMaterial))
                  _line(context, entry, result, row),
                const SectionHeading('المصنعية والخدمات'),
                for (final row in model.rows.where((row) => !row.isMaterial))
                  _line(context, entry, result, row),
              ],
              const SizedBox(height: 20),
              if (result?.cost != null)
                TotalCard(
                  value: result!.cost!,
                  title: 'تكلفة ${kind.label} قبل الربح',
                  large: false,
                ),
            ],
          ),
        ),
      );
    },
  );

  Widget _line(
    BuildContext context,
    WorkEntry entry,
    WorkResult? result,
    ModelRow row,
  ) {
    final line = result?.lines
        .where((line) => line.row.id == row.id)
        .firstOrNull;
    final price = controller.price(entry, row);
    final hasOverride = controller.hasOverride(kind, row);
    final raw = controller.draft('override:${kind.name}:${row.id}', price);
    final sourceUnit = switch (row.quantitySource) {
      QuantitySource.workQuantity => entry.model!.inputUnit,
      QuantitySource.roofArea => QuantityUnit.area,
      QuantitySource.roofBeamLength => QuantityUnit.linear,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              row.label,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            Text(
              '${measure(row.coefficient)} ${row.sourceUnit?.label ?? row.unit.label} لكل ${sourceUnit.label}'
              '${row.divisor == 1 ? '' : ' ÷ ${measure(row.divisor)}'} ← ${row.unit.label}',
              style: const TextStyle(color: secondaryText, fontSize: 13),
            ),
            if (kind == WorkKind.roof)
              Text(
                'يُحسب حسب: ${quantitySourceLabel(row.quantitySource)}',
                style: const TextStyle(color: secondaryText, fontSize: 13),
              ),
            if (kind == WorkKind.roof && !row.isMaterial && row.divisor == 4)
              const Text(
                'قسمة المساحة على 4 معامل للتسعير في هذا النموذج.',
                style: TextStyle(color: secondaryText, fontSize: 12),
              ),
            if (row.reviewBasis)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'أساس تسعير خدمة قابل للمراجعة، وليس عدد معدات أو حجم مياه.',
                  style: TextStyle(color: Color(0xFF86531A), fontSize: 12),
                ),
              ),
            if (line != null)
              DetailPair(
                'الكمية المسعّرة',
                '${measure(line.quantity)} ${line.unit.label}',
              ),
            if (line != null && row.divisor != 1)
              Text(
                'قبل التحويل: ${measure(line.rawQuantity)} ${row.sourceUnit?.label ?? row.unit.label}',
                style: const TextStyle(fontSize: 12, color: secondaryText),
              ),
            const SizedBox(height: 12),
            NumberInput(
              key: ValueKey(
                '${controller.savedProject.id}:override:${kind.name}:${row.id}',
              ),
              text: raw,
              label:
                  '${hasOverride ? 'سعر مخصص للسطر' : 'السعر المشترك'} (د.ل / ${row.unit.label})',
              enabled: controller.editable,
              error: price == null ? 'سعر غير مكتمل' : null,
              onChanged: (value) => controller.overridePrice(kind, row, value),
            ),
            if (hasOverride)
              TextButton(
                onPressed: controller.editable
                    ? () => controller.clearOverride(kind, row)
                    : null,
                child: const Text('إلغاء التخصيص واستخدام السعر المشترك'),
              )
            else
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'تعديله هنا يخصص سعر هذا السطر فقط. الأسعار المشتركة من قسم الأسعار.',
                  style: TextStyle(color: secondaryText, fontSize: 12),
                ),
              ),
            if (line != null)
              DetailPair('تكلفة السطر', '${money(line.cost)} د.ل', bold: true),
          ],
        ),
      ),
    );
  }
}
