import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../project/catalog.dart';
import '../project/controller.dart';
import '../project/engine.dart';
import '../project/models.dart';
import '../project/repository.dart';
import '../services/browser_pdf.dart';
import '../services/project_report_service.dart';
import 'app_theme.dart';
import 'pdf_export_dialog.dart';
import 'project_widgets.dart';
import 'work_details.dart';

class ProjectShell extends StatefulWidget {
  const ProjectShell({super.key, required this.repository});
  final ProjectRepository repository;
  @override
  State<ProjectShell> createState() => _ProjectShellState();
}

class _ProjectShellState extends State<ProjectShell>
    with WidgetsBindingObserver {
  late final ProjectController controller = ProjectController(
    widget.repository,
  );
  int _tab = 0;
  bool _services = false;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller.load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) controller.saveNow();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.saveNow();
    controller.dispose();
    super.dispose();
  }

  Future<void> _action(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              controller.warning ?? 'تعذّر حفظ التعديل. حاول مرة أخرى.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _projects() async {
    FocusScope.of(context).unfocus();
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .8,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
            children: [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'المشاريع المحفوظة',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
                ),
              ),
              for (final project in controller.state!.projects)
                ListTile(
                  title: Text(project.name),
                  subtitle: Text(
                    '${project.date}${project.isExample ? ' • مشروع توضيحي' : ''}',
                  ),
                  leading: Icon(
                    project.id == controller.savedProject.id
                        ? Icons.check_circle
                        : Icons.folder_outlined,
                    color: primaryGreen,
                  ),
                  onTap: () => Navigator.pop(context, project.id),
                ),
              const Divider(),
              ListTile(
                key: const ValueKey('new_project'),
                leading: const Icon(Icons.add_circle_outline),
                title: const Text('إنشاء مشروع جديد'),
                onTap: () => Navigator.pop(context, '__new'),
              ),
              ListTile(
                key: const ValueKey('example_project'),
                leading: const Icon(Icons.description_outlined),
                title: const Text('إضافة «مثال الأوراق»'),
                subtitle: const Text('المثال السابق دون السقف'),
                onTap: () => Navigator.pop(context, '__example'),
              ),
              ListTile(
                key: const ValueKey('full_example_project'),
                leading: const Icon(Icons.description_outlined),
                title: const Text('إضافة «مثال الأوراق بالسقف»'),
                subtitle: const Text(
                  'مثال مستقل يشمل مساحة السقف وأطوال الكمرات',
                ),
                onTap: () => Navigator.pop(context, '__full_example'),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    await _action(() async {
      if (selected == '__new' ||
          selected == '__example' ||
          selected == '__full_example') {
        await controller.addProject(
          example: selected == '__example',
          fullExample: selected == '__full_example',
        );
        if (selected == '__new' && mounted) await _metadata();
      } else {
        await controller.selectProject(selected);
      }
      if (mounted) setState(() => _tab = 0);
    });
  }

  Future<void> _metadata() async {
    final project = controller.savedProject;
    final result = await showDialog<List<String>>(
      context: context,
      builder: (_) => _MetadataDialog(project: project),
    );
    if (result != null) {
      await _action(() => controller.metadata(result[0], result[1], result[2]));
    }
  }

  void _details(WorkKind kind) {
    FocusScope.of(context).unfocus();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WorkDetails(controller: controller, kind: kind),
      ),
    );
  }

  void _changeTab(int index) {
    FocusScope.of(context).unfocus();
    setState(() => _tab = index);
  }

  Future<void> _calculate() async {
    FocusScope.of(context).unfocus();
    await _action(() async {
      await controller.calculate();
      if (mounted) _changeTab(2);
    });
  }

  Future<void> _export() async {
    if (_exporting || controller.needsRecalculation) return;
    final snapshot = controller.calculatedResult;
    if (snapshot == null || snapshot.quotationTotal == null) return;
    FocusScope.of(context).unfocus();
    setState(() => _exporting = true);
    try {
      final createdAt = DateTime.now();
      final bytes = await ProjectReportService.generate(
        snapshot,
        createdAt: createdAt,
      );
      final filename = ProjectReportService.filename(createdAt);
      if (!mounted ||
          controller.needsRecalculation ||
          controller.calculatedResult?.project.id != snapshot.project.id ||
          controller.calculatedResult?.project != snapshot.project) {
        return;
      }
      if (kIsWeb) {
        final file = prepareBrowserPdf(bytes, filename);
        await showDialog<void>(
          context: context,
          builder: (_) => PdfExportDialog(file: file, filename: filename),
        );
      } else {
        await Printing.sharePdf(bytes: bytes, filename: filename);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر تجهيز PDF. حاول مرة أخرى.')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      if (!controller.loaded) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final titles = ['كميات المشروع', 'الأسعار والربح', 'نتائج المشروع'];
      final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
      return Scaffold(
        appBar: AppBar(
          title: Text(titles[_tab]),
          actions: [
            IconButton(
              key: const ValueKey('project_picker'),
              tooltip: 'اختيار مشروع',
              onPressed: controller.editable && !_exporting ? _projects : null,
              icon: const Icon(Icons.folder_open_rounded),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (controller.saving)
                const LinearProgressIndicator(minHeight: 2),
              if (controller.warning != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Notice(controller.warning!),
                ),
              Expanded(
                child: switch (_tab) {
                  0 => _project(),
                  1 => _prices(),
                  _ => _results(),
                },
              ),
            ],
          ),
        ),
        bottomNavigationBar: keyboardOpen
            ? null
            : NavigationBar(
                selectedIndex: _tab,
                onDestinationSelected: _changeTab,
                backgroundColor: Colors.white,
                indicatorColor: const Color(0xFFDCEFE6),
                destinations: const [
                  NavigationDestination(
                    key: ValueKey('tab_project'),
                    icon: Icon(Icons.straighten_outlined),
                    selectedIcon: Icon(Icons.straighten, color: primaryGreen),
                    label: 'الكميات',
                  ),
                  NavigationDestination(
                    key: ValueKey('tab_prices'),
                    icon: Icon(Icons.sell_outlined),
                    selectedIcon: Icon(Icons.sell, color: primaryGreen),
                    label: 'الأسعار والربح',
                  ),
                  NavigationDestination(
                    key: ValueKey('tab_results'),
                    icon: Icon(Icons.bar_chart_outlined),
                    selectedIcon: Icon(Icons.bar_chart, color: primaryGreen),
                    label: 'النتائج',
                  ),
                ],
              ),
      );
    },
  );

  Widget _project() {
    final project = controller.project;
    final result = controller.result;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final calculateButton = FilledButton.icon(
      key: const ValueKey('calculate_project'),
      onPressed: controller.editable ? _calculate : null,
      icon: const Icon(Icons.calculate_outlined),
      label: const Text('احسب المشروع'),
    );
    final fields = ProjectBody(
      key: ValueKey('project:${project.id}'),
      children: [
        SurfaceCard(
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: controller.editable ? _projects : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        project.name,
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${project.date} • ${project.location.isEmpty ? 'لم يُحدَّد الموقع' : project.location}',
                        style: const TextStyle(color: secondaryText),
                      ),
                      if (project.isExample)
                        const Text(
                          'مثال توضيحي مستقل',
                          style: TextStyle(color: primaryGreen, fontSize: 12),
                        ),
                    ],
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('edit_project'),
                tooltip: 'تعديل بيانات المشروع',
                onPressed: controller.editable ? _metadata : null,
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
        ),
        const SectionHeading('بنود الأعمال'),
        SurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Column(
            children: [
              for (var i = 0; i < WorkKind.values.length; i++) ...[
                _workRow(result.work(WorkKind.values[i])),
                if (i != WorkKind.values.length - 1) const Divider(),
              ],
            ],
          ),
        ),
        if (keyboardOpen) ...[const SizedBox(height: 16), calculateButton],
      ],
    );
    return Column(
      children: [
        Expanded(child: fields),
        if (!keyboardOpen)
          Container(
            width: double.infinity,
            color: Theme.of(context).scaffoldBackgroundColor,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 650),
                child: SizedBox(width: double.infinity, child: calculateButton),
              ),
            ),
          ),
      ],
    );
  }

  Widget _workRow(WorkResult result) {
    final entry = result.entry;
    final kind = entry.kind;
    final model = entry.model;
    final unit = model?.inputUnit ?? kind.defaultUnit;
    final saved = controller.savedProject;
    final raw = controller.draft(
      'quantity:${kind.name}',
      saved.work(kind).quantity,
    );
    final beamRaw = controller.draft(
      'roofBeamLength',
      saved.work(kind).roofBeamLength,
    );
    final roofArea = kind == WorkKind.roof && unit == QuantityUnit.area;
    final showBeams =
        kind == WorkKind.roof &&
        (model == null || model.requiresRoofBeamLength);
    final status =
        result.status == WorkStatus.calculated &&
            (controller.calculatedResult == null ||
                controller.needsRecalculation)
        ? 'جاهز للحساب'
        : statusLabel(result.status);
    final title = switch (kind) {
      WorkKind.foundations => 'عدد القواعد',
      WorkKind.belowMasonry => 'طول مباني تحت الكتينة',
      WorkKind.tieBeam => 'طول الميدة',
      WorkKind.leanSlab => 'مساحة الكرسنة',
      WorkKind.columns => 'عدد الأعمدة',
      WorkKind.aboveMasonry => 'طول مباني فوق الكتينة',
      WorkKind.roof => 'السقف',
    };
    final quantity = NumberInput(
      semanticLabel: roofArea ? 'مساحة السقف' : 'كمية ${kind.label}',
      key: ValueKey('${saved.id}:quantity:${kind.name}'),
      text: raw,
      label: unit.label,
      integer: kind.integerQuantity,
      enabled: controller.editable,
      error: raw.isNotEmpty && entry.quantity == null
          ? 'أدخل كمية صالحة'
          : null,
      onChanged: (value) => controller.quantity(kind, value),
    );
    final beams = NumberInput(
      semanticLabel: 'إجمالي أطوال كمرات السقف',
      key: ValueKey('${saved.id}:roof_beam_length'),
      text: beamRaw,
      label: QuantityUnit.linear.label,
      enabled: controller.editable,
      error: beamRaw.isNotEmpty && entry.roofBeamLength == null
          ? 'أدخل طولًا صالحًا'
          : null,
      onChanged: controller.roofBeamLength,
    );
    Widget roofField(String label, Widget field) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        field,
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  entry.explicitlyExcluded ? 'غير مطلوب' : status,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color:
                        !entry.explicitlyExcluded &&
                            (result.status == WorkStatus.needsData ||
                                result.status == WorkStatus.noModel)
                        ? const Color(0xFF86531A)
                        : primaryGreen,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          if (entry.explicitlyExcluded || kind == WorkKind.roof)
            Text(
              model?.name ?? 'لم يُختَر نموذج',
              style: const TextStyle(color: secondaryText, fontSize: 13),
            ),
          if (!entry.explicitlyExcluded) ...[
            const SizedBox(height: 12),
            if (showBeams)
              LayoutBuilder(
                builder: (context, constraints) {
                  final areaField = roofField('مساحة السقف', quantity);
                  final beamField = roofField(
                    'إجمالي أطوال كمرات السقف',
                    beams,
                  );
                  if (constraints.maxWidth < 480 ||
                      MediaQuery.textScalerOf(context).scale(1) > 1.2) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        areaField,
                        const SizedBox(height: 12),
                        beamField,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: areaField),
                      const SizedBox(width: 12),
                      Expanded(child: beamField),
                    ],
                  );
                },
              )
            else if (kind == WorkKind.roof)
              roofArea ? roofField('مساحة السقف', quantity) : quantity
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final name = Text(
                    model?.name ?? 'لم يُختَر نموذج',
                    style: const TextStyle(color: secondaryText, fontSize: 13),
                  );
                  if (constraints.maxWidth < 310 ||
                      MediaQuery.textScalerOf(context).scale(1) > 1.3) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [name, const SizedBox(height: 12), quantity],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: name),
                      const SizedBox(width: 12),
                      SizedBox(width: 148, child: quantity),
                    ],
                  );
                },
              ),
            if (showBeams &&
                (entry.quantity == null ||
                    (entry.quantity! > 0 && entry.roofBeamLength == null)))
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'أدخل مساحة السقف وأطوال الكمرات.',
                  style: TextStyle(color: secondaryText, fontSize: 12),
                ),
              ),
          ],
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                key: ValueKey('work_${kind.name}'),
                onPressed: () => _details(kind),
                child: const Text('تفاصيل النموذج'),
              ),
              TextButton(
                key: ValueKey('include_${kind.name}'),
                onPressed: controller.editable
                    ? () => controller.include(kind, entry.explicitlyExcluded)
                    : null,
                child: Text(
                  entry.explicitlyExcluded ? 'إضافة للحصر' : 'غير مطلوب',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _prices() {
    final project = controller.project;
    return ProjectBody(
      key: ValueKey('prices:${project.id}:$_services'),
      children: [
        Text(
          project.name,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, color: secondaryText),
        ),
        const SizedBox(height: 20),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('المواد'),
              selected: !_services,
              onSelected: (_) => setState(() => _services = false),
            ),
            ChoiceChip(
              key: const ValueKey('services_prices'),
              label: const Text('المصنعية والخدمات'),
              selected: _services,
              onSelected: (_) => setState(() => _services = true),
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Text(
            'الأسعار ونسبة الربح تخص هذا المشروع',
            textAlign: TextAlign.center,
            style: TextStyle(color: secondaryText),
          ),
        ),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'نسبة الربح المضافة إلى التكلفة',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                'تُضاف إلى إجمالي تكلفة المواد والمصنعية والخدمات',
                style: TextStyle(color: secondaryText),
              ),
              const SizedBox(height: 14),
              NumberInput(
                semanticLabel: 'نسبة الربح المضافة إلى التكلفة',
                key: ValueKey('${project.id}:profit_percentage'),
                text: controller.draft(
                  'profitPercentage',
                  controller.savedProject.profitPercentage,
                ),
                label: 'نسبة الربح',
                suffixText: '%',
                enabled: controller.editable,
                error: project.profitPercentage == null
                    ? 'أدخل نسبة من 0 إلى ${measure(maxProfitPercentage)}'
                    : null,
                onChanged: controller.profitPercentage,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (!_services)
          SurfaceCard(
            child: Column(
              children: [
                for (final material in materialCatalog) ...[
                  _priceRow(
                    label: material.label,
                    unit: material.unit,
                    input: NumberInput(
                      semanticLabel: 'سعر ${material.label}',
                      key: ValueKey('${project.id}:price:${material.id}'),
                      text: controller.draft(
                        'material:${material.id}',
                        controller.savedProject.materialPrices[material.id],
                      ),
                      label: 'السعر',
                      enabled: controller.editable,
                      error: project.materialPrices[material.id] == null
                          ? 'سعر غير مكتمل'
                          : null,
                      onChanged: (value) =>
                          controller.materialPrice(material.id, value),
                    ),
                  ),
                  if (material != materialCatalog.last) const Divider(),
                ],
              ],
            ),
          )
        else ...[
          for (final work in project.works.where(
            (entry) => entry.model?.rows.any((row) => !row.isMaterial) ?? false,
          )) ...[
            SectionHeading(work.kind.label),
            SurfaceCard(
              child: Column(
                children: [
                  for (final row in work.model!.rows.where(
                    (row) => !row.isMaterial,
                  ))
                    _priceRow(
                      label: row.label,
                      unit: row.unit,
                      input: NumberInput(
                        semanticLabel: 'سعر ${row.label} ${work.kind.label}',
                        key: ValueKey(
                          '${project.id}:service:${servicePriceKey(work.kind, row)}',
                        ),
                        text: controller.draft(
                          'service:${servicePriceKey(work.kind, row)}',
                          controller.savedProject.servicePrices.containsKey(
                                servicePriceKey(work.kind, row),
                              )
                              ? controller
                                    .savedProject
                                    .servicePrices[servicePriceKey(
                                  work.kind,
                                  row,
                                )]
                              : row.defaultPrice,
                        ),
                        label: 'السعر',
                        enabled: controller.editable,
                        error:
                            project.servicePrices.containsKey(
                                  servicePriceKey(work.kind, row),
                                ) &&
                                project.servicePrices[servicePriceKey(
                                      work.kind,
                                      row,
                                    )] ==
                                    null
                            ? 'سعر غير مكتمل'
                            : null,
                        onChanged: (value) =>
                            controller.servicePrice(work.kind, row, value),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _priceRow({
    required String label,
    required QuantityUnit unit,
    required Widget input,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            Text(
              'د.ل / ${unit.label}',
              style: const TextStyle(color: secondaryText),
            ),
          ],
        );
        return constraints.maxWidth < 280 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.3
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [title, const SizedBox(height: 12), input],
              )
            : Row(
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 14),
                  SizedBox(width: 128, child: input),
                ],
              );
      },
    ),
  );

  Widget _results() {
    final project = controller.project;
    final result = controller.calculatedResult;
    if (controller.needsRecalculation || result == null) {
      final stale = controller.needsRecalculation;
      return ProjectBody(
        key: ValueKey('results:${project.id}:$stale'),
        children: [
          const SizedBox(height: 18),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  stale ? Icons.refresh_rounded : Icons.calculate_outlined,
                  color: primaryGreen,
                  size: 38,
                ),
                SectionHeading(
                  stale ? 'الحسبة تحتاج تحديثًا' : 'لم يُحسب المشروع بعد',
                ),
                Text(
                  stale
                      ? 'تغيّرت بيانات المشروع بعد آخر حساب. حدّث الحسبة لعرض النتائج وتنزيل التقرير.'
                      : 'أدخل كميات الأعمال والأسعار، ثم اضغط «احسب المشروع» لعرض النتائج.',
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  key: const ValueKey('recalculate_project'),
                  onPressed: stale
                      ? (controller.editable ? _calculate : null)
                      : () => _changeTab(0),
                  icon: Icon(stale ? Icons.refresh : Icons.straighten_outlined),
                  label: Text(stale ? 'تحديث الحسبة' : 'إدخال الكميات'),
                ),
              ],
            ),
          ),
        ],
      );
    }
    final profit = result.profitPercentage;
    final profitAmount = result.profitAmount;
    final quotation = result.quotationTotal;
    final shareAvailable = !kIsWeb || supportsBrowserFileSharing;
    return ProjectBody(
      key: ValueKey('results:${project.id}'),
      children: [
        Text(
          result.project.name,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, color: secondaryText),
        ),
        const SizedBox(height: 18),
        if (quotation != null)
          TotalCard(
            key: const ValueKey('project_total'),
            title: 'إجمالي العرض شامل الربح',
            value: quotation,
          )
        else ...[
          const Notice(
            'أدخل نسبة ربح صالحة لإظهار إجمالي العرض وإتاحة التقرير.',
          ),
          TextButton(
            onPressed: () => _changeTab(1),
            child: const Text('تعديل نسبة الربح'),
          ),
        ],
        if (result.isPartial)
          const Notice('حصر جزئي — توجد بنود غير مكتملة')
        else
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text('حصر كامل ضمن النطاق المحدد'),
          ),
        if (result.unfinishedWorks.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(
              'البنود غير المكتملة: ${result.unfinishedWorks.map((work) => work.kind.label).join('، ')}',
              style: const TextStyle(color: secondaryText),
            ),
          ),
        const SizedBox(height: 12),
        SurfaceCard(
          child: Column(
            children: [
              DetailPair(
                'تكلفة المواد',
                '${money(result.materialCost)} د.ل',
                bold: true,
              ),
              const Divider(),
              DetailPair(
                'تكلفة المصنعية والخدمات',
                '${money(result.serviceCost)} د.ل',
                bold: true,
              ),
              const Divider(),
              DetailPair(
                'إجمالي التكلفة قبل الربح',
                '${money(result.baseCost)} د.ل',
                bold: true,
              ),
              const Divider(),
              DetailPair(
                'نسبة الربح',
                profit == null ? '—' : '${measure(profit)}%',
              ),
              const Divider(),
              DetailPair(
                'قيمة الربح',
                profitAmount == null ? '—' : '${money(profitAmount)} د.ل',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _resultSection('كميات المواد المطلوبة', [
          if (result.materials.isEmpty)
            const Text('لا توجد مواد في الحصر الحالي.'),
          for (final total in result.materials) ...[
            DetailPair(
              total.material.label,
              '${measure(total.quantity)} ${total.material.unit.label}',
              bold: true,
            ),
            DetailPair(
              total.hasDifferentPrices
                  ? 'تكلفة السطور بأسعارها المحفوظة'
                  : 'التكلفة',
              '${money(total.cost)} د.ل',
            ),
            if (total != result.materials.last) const Divider(),
          ],
        ]),
        const SizedBox(height: 10),
        _resultSection('التكلفة حسب بند العمل', [
          for (final work in result.works)
            DetailPair(
              work.kind.label,
              work.status == WorkStatus.calculated && work.cost != null
                  ? '${money(work.cost!)} د.ل'
                  : statusLabel(work.status),
            ),
        ]),
        const SizedBox(height: 10),
        _resultSection('تفاصيل المصنعية والخدمات', [
          if (result.services.isEmpty)
            const Text('لا توجد مصنعية أو خدمات في الحصر الحالي.'),
          for (final line in result.services) ...[
            DetailPair(
              '${line.kind.label} • ${line.label}',
              '${money(line.cost)} د.ل',
            ),
            Text(
              '${measure(line.quantity)} ${line.unit.label} × ${money(line.unitPrice)} د.ل',
              style: const TextStyle(color: secondaryText),
            ),
            if (line.reviewBasis)
              const Text(
                'أساس التسعير قابل للمراجعة',
                style: TextStyle(color: Color(0xFF86531A), fontSize: 12),
              ),
            const Divider(),
          ],
        ]),
        const SizedBox(height: 10),
        _resultSection('تفاصيل الحسابات', [
          for (final work in result.works)
            if (work.lines.isNotEmpty) ...[
              SectionHeading('${work.kind.label} • ${work.entry.model!.name}'),
              for (final line in work.lines) _calculatedLine(line),
            ],
          if (result.works.every((work) => work.lines.isEmpty))
            const Text('لا توجد سطور محسوبة للعرض.'),
          if (result.notes.isNotEmpty) ...[
            const SectionHeading('ملاحظات الحساب'),
            for (final note in result.notes) Notice(note),
          ],
        ]),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          key: const ValueKey('export_project_pdf'),
          onPressed: _exporting || quotation == null ? null : _export,
          icon: _exporting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  shareAvailable
                      ? Icons.share_outlined
                      : Icons.download_outlined,
                ),
          label: Text(
            _exporting
                ? 'جارٍ تجهيز التقرير…'
                : shareAvailable
                ? 'مشاركة التقرير PDF'
                : 'تنزيل التقرير PDF',
          ),
        ),
      ],
    );
  }

  Widget _resultSection(String title, List<Widget> children) => SurfaceCard(
    padding: EdgeInsets.zero,
    child: ExpansionTile(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );

  Widget _calculatedLine(CalculatedLine line) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DetailPair(line.label, '${money(line.cost)} د.ل', bold: true),
        Text(
          '${quantitySourceLabel(line.row.quantitySource)}: '
          '${measure(line.inputQuantity)} ${line.inputUnit.label}',
        ),
        Text(
          '${measure(line.inputQuantity)} × ${measure(line.row.coefficient)}'
          '${line.row.divisor == 1 ? '' : ' ÷ ${measure(line.row.divisor)}'}'
          ' = ${measure(line.quantity)} ${line.unit.label}',
          style: const TextStyle(color: secondaryText),
        ),
        Text('سعر الوحدة: ${money(line.unitPrice)} د.ل'),
        if (line.overridden)
          const Text(
            'سعر مخصص لهذا السطر',
            style: TextStyle(color: secondaryText, fontSize: 12),
          ),
        const SizedBox(height: 12),
        const Divider(),
      ],
    ),
  );
}

class _MetadataDialog extends StatefulWidget {
  const _MetadataDialog({required this.project});
  final Project project;
  @override
  State<_MetadataDialog> createState() => _MetadataDialogState();
}

class _MetadataDialogState extends State<_MetadataDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.project.name);
  late final _date = TextEditingController(text: widget.project.date);
  late final _location = TextEditingController(text: widget.project.location);
  @override
  void dispose() {
    _name.dispose();
    _date.dispose();
    _location.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('بيانات المشروع'),
    content: SizedBox(
      width: 400,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const ValueKey('project_name'),
                controller: _name,
                decoration: const InputDecoration(labelText: 'اسم المشروع'),
                validator: (value) =>
                    value!.trim().isEmpty ? 'أدخل اسم المشروع' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _date,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'التاريخ',
                  suffixIcon: Icon(Icons.calendar_today_outlined),
                ),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate:
                        DateTime.tryParse(_date.text) ?? DateTime.now(),
                    firstDate: DateTime(1900),
                    lastDate: DateTime(2200),
                  );
                  if (date != null) {
                    _date.text = date.toIso8601String().split('T').first;
                  }
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _location,
                decoration: const InputDecoration(
                  labelText: 'الموقع (اختياري)',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('إلغاء'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, [_name.text, _date.text, _location.text]);
          }
        },
        child: const Text('حفظ'),
      ),
    ],
  );
}
