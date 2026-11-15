import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../domain/numbers.dart';
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
                subtitle: const Text(
                  'مثال مستقل بأرقام الأوراق للاطلاع والتجربة',
                ),
                onTap: () => Navigator.pop(context, '__example'),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    await _action(() async {
      if (selected == '__new' || selected == '__example') {
        await controller.addProject(example: selected == '__example');
        if (selected == '__new' && mounted) await _metadata();
      } else {
        await controller.selectProject(selected);
      }
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

  Future<void> _export() async {
    if (_exporting) return;
    FocusScope.of(context).unfocus();
    final snapshot = controller.result;
    setState(() => _exporting = true);
    try {
      final bytes = await ProjectReportService.generate(snapshot);
      const filename = 'hasr-project-report.pdf';
      if (!mounted) return;
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
      final titles = ['حصر المشروع', 'أسعار المشروع', 'نتائج المشروع'];
      return Scaffold(
        appBar: AppBar(
          title: Text(titles[_tab]),
          actions: [
            IconButton(
              key: const ValueKey('project_picker'),
              tooltip: 'اختيار مشروع',
              onPressed: controller.editable ? _projects : null,
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
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (index) {
            FocusScope.of(context).unfocus();
            setState(() => _tab = index);
          },
          backgroundColor: Colors.white,
          indicatorColor: const Color(0xFFDCEFE6),
          destinations: const [
            NavigationDestination(
              key: ValueKey('tab_project'),
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home, color: primaryGreen),
              label: 'المشروع',
            ),
            NavigationDestination(
              key: ValueKey('tab_prices'),
              icon: Icon(Icons.sell_outlined),
              selectedIcon: Icon(Icons.sell, color: primaryGreen),
              label: 'الأسعار',
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
    return ProjectBody(
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
                        '${project.date}${project.location.isEmpty ? '' : ' • ${project.location}'}',
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
        for (final note in result.notes) Notice(note),
        if (result.works.any((work) => work.status == WorkStatus.needsData))
          const Notice(
            'بعض البنود تحتاج بيانات، ولا تدخل في الإجمالي حتى تكتمل.',
          ),
        const SizedBox(height: 20),
        TotalCard(value: result.totalCost, large: false),
      ],
    );
  }

  Widget _workRow(WorkResult result) {
    final entry = result.entry;
    final unit = entry.model?.inputUnit;
    final title = InkWell(
      onTap: () => _details(entry.kind),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.kind.label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    !entry.included
                        ? 'مستبعد من المشروع'
                        : entry.model == null
                        ? 'بانتظار النموذج'
                        : '${entry.model!.name}${entry.model!.description.isEmpty ? '' : ' • ${entry.model!.description}'}',
                    style: const TextStyle(color: secondaryText, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_left, color: secondaryText),
          ],
        ),
      ),
    );
    final quantity = entry.included && unit != null
        ? SizedBox(
            width: 118,
            child: NumberInput(
              semanticLabel: 'كمية ${entry.kind.label}',
              key: ValueKey(
                '${controller.savedProject.id}:quantity:${entry.kind.name}',
              ),
              text: controller.draft(
                'quantity:${entry.kind.name}',
                controller.savedProject.work(entry.kind).quantity,
              ),
              label: unit.shortLabel,
              integer: entry.kind.integerQuantity,
              enabled: controller.editable,
              error: entry.quantity == null ? 'أدخل كمية صالحة' : null,
              onChanged: (value) => controller.quantity(entry.kind, value),
            ),
          )
        : OutlinedButton(
            key: ValueKey('work_${entry.kind.name}'),
            onPressed: () => _details(entry.kind),
            child: Text(entry.included ? 'غير محسوب' : 'إضافة'),
          );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked =
              constraints.maxWidth < 280 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.3;
          return stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    title,
                    const SizedBox(height: 8),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: quantity,
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: 10),
                    quantity,
                  ],
                );
        },
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
            'تُطبّق هذه الأسعار على المشروع الحالي',
            textAlign: TextAlign.center,
            style: TextStyle(color: secondaryText),
          ),
        ),
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
            (entry) => entry.model != null,
          )) ...[
            SectionHeading(
              '${work.kind.label}${work.included ? '' : ' • مستبعد'}',
            ),
            SurfaceCard(
              child: Column(
                children: [
                  for (final row in work.model!.rows.where(
                    (row) => !row.isMaterial,
                  ))
                    _priceRow(
                      label: row.label,
                      unit: row.unit,
                      note: row.reviewBasis
                          ? 'أساس التسعير قابل للمراجعة من النموذج'
                          : null,
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
                  TextButton(
                    onPressed: () => _details(work.kind),
                    child: const Text('تفاصيل البند وأساس التسعير'),
                  ),
                ],
              ),
            ),
          ],
        ],
        const SizedBox(height: 20),
        const Text(
          'تتحدث النتائج تلقائيًا عند تعديل الأسعار',
          textAlign: TextAlign.center,
          style: TextStyle(color: secondaryText),
        ),
      ],
    );
  }

  Widget _priceRow({
    required String label,
    required QuantityUnit unit,
    required Widget input,
    String? note,
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
            if (note != null)
              Text(
                note,
                style: const TextStyle(color: Color(0xFF86531A), fontSize: 12),
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
    final result = controller.result;
    return ProjectBody(
      key: ValueKey('results:${result.project.id}'),
      children: [
        Text(
          result.project.name,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, color: secondaryText),
        ),
        const SizedBox(height: 18),
        TotalCard(
          key: const ValueKey('project_total'),
          value: result.totalCost,
        ),
        Notice(
          '${result.calculatedCount} بنود محسوبة • ${result.isPartial ? 'حصر مبدئي / جزئي' : 'مكتمل ضمن نطاقه'}',
        ),
        for (final note in result.notes) Notice(note),
        for (final work in result.works.where(
          (work) => work.status == WorkStatus.needsData,
        ))
          Notice('${work.kind.label}: يحتاج بيانات، غير مشمول في الإجمالي'),
        const SizedBox(height: 12),
        SurfaceCard(
          child: Column(
            children: [
              DetailPair(
                'المواد',
                '${money(result.materialCost)} د.ل',
                bold: true,
              ),
              const Divider(),
              DetailPair(
                'المصنعية والخدمات',
                '${money(result.serviceCost)} د.ل',
                bold: true,
              ),
            ],
          ),
        ),
        const SectionHeading('إجمالي كميات المواد'),
        SurfaceCard(
          child: Column(
            children: [
              if (result.materials.isEmpty)
                const Text('أكمل بيانات بند واحد لإظهار كمياته.'),
              for (final total in result.materials) ...[
                DetailPair(
                  total.material.label,
                  '${formatNumber(total.quantity)} ${total.material.unit.label}',
                  bold: true,
                ),
                if (total.hasDifferentPrices)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      'أسعار متعددة محفوظة — تكلفة السطور ${money(total.cost)} د.ل',
                      style: const TextStyle(
                        fontSize: 12,
                        color: secondaryText,
                      ),
                    ),
                  ),
                if (total != result.materials.last) const Divider(),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        SurfaceCard(
          padding: EdgeInsets.zero,
          child: ExpansionTile(
            title: const Text(
              'تفاصيل المصنعية والخدمات',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            childrenPadding: const EdgeInsets.all(14),
            children: [
              for (final line in result.services)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${line.kind.label} • ${line.label}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    DetailPair(
                      '${formatNumber(line.quantity)} ${line.unit.label} × ${money(line.unitPrice)} د.ل',
                      '${money(line.cost)} د.ل',
                    ),
                    if (line.reviewBasis)
                      const Text(
                        'أساس التسعير قابل للمراجعة',
                        style: TextStyle(
                          color: Color(0xFF86531A),
                          fontSize: 12,
                        ),
                      ),
                    const Divider(),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SurfaceCard(
          padding: EdgeInsets.zero,
          child: ExpansionTile(
            title: const Text(
              'التكلفة حسب بند العمل',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            childrenPadding: const EdgeInsets.all(14),
            children: [
              for (final work in result.works)
                InkWell(
                  onTap: () => _details(work.kind),
                  child: DetailPair(
                    work.kind.label,
                    work.cost == null
                        ? statusLabel(work.status)
                        : '${money(work.cost!)} د.ل',
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          key: const ValueKey('export_project_pdf'),
          onPressed: _exporting ? null : _export,
          icon: _exporting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(kIsWeb ? Icons.download_outlined : Icons.share_outlined),
          label: Text(
            _exporting
                ? 'جارٍ تجهيز التقرير…'
                : kIsWeb
                ? 'تنزيل PDF'
                : 'مشاركة PDF',
          ),
        ),
      ],
    );
  }
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
