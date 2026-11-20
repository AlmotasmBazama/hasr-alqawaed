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
import 'finance_widgets.dart';
import 'masonry_lengths.dart';
import 'pdf_export_dialog.dart';
import 'project_picker.dart';
import 'project_widgets.dart';
import 'quantity_workspace.dart';
import 'work_details.dart';
import 'workspace_header.dart';

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
      builder: (context) => ProjectPicker(
        projects: controller.state!.projects,
        selectedId: controller.savedProject.id,
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
      final wide =
          MediaQuery.sizeOf(context).width >= 900 &&
          MediaQuery.textScalerOf(context).scale(1) < 1.35;
      final navigation = NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _changeTab,
        destinations: const [
          NavigationDestination(
            key: ValueKey('tab_project'),
            icon: Icon(Icons.architecture_outlined),
            selectedIcon: Icon(Icons.architecture, color: forestInk),
            label: 'الكميات',
          ),
          NavigationDestination(
            key: ValueKey('tab_prices'),
            icon: Icon(Icons.sell_outlined),
            selectedIcon: Icon(Icons.sell, color: forestInk),
            label: 'الأسعار والربح',
          ),
          NavigationDestination(
            key: ValueKey('tab_results'),
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long, color: forestInk),
            label: 'النتائج',
          ),
        ],
      );
      return Scaffold(
        appBar: WorkspaceHeader(
          title: titles[_tab],
          wide: wide,
          navigation: navigation,
          onPickProject: controller.editable && !_exporting ? _projects : null,
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
                child: TweenAnimationBuilder<double>(
                  key: ValueKey((_tab, controller.savedProject.id)),
                  tween: Tween(begin: 0, end: 1),
                  curve: Curves.easeOutCubic,
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 210),
                  builder: (_, value, child) =>
                      Opacity(opacity: value, child: child),
                  child: switch (_tab) {
                    0 => _project(),
                    1 => _prices(),
                    _ => _results(),
                  },
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: keyboardOpen || wide
            ? null
            : DecoratedBox(
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: borderColor)),
                ),
                position: DecorationPosition.foreground,
                child: navigation,
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
        QuantityProjectCard(
          project: project,
          result: result,
          openProjects: controller.editable ? _projects : null,
          edit: controller.editable ? _metadata : null,
        ),
        const SectionHeading(
          'بنود الأعمال',
          icon: Icons.format_list_bulleted_rounded,
        ),
        LayoutBuilder(
          builder: (context, bounds) {
            final paired =
                bounds.maxWidth >= 720 &&
                MediaQuery.textScalerOf(context).scale(1) <= 1.3;
            final lengths = MasonryLengths(
              controller: controller,
              result: result,
              details: _details,
            );
            final foundations = _workRow(result.work(WorkKind.foundations));
            final leanSlab = _workRow(result.work(WorkKind.leanSlab));
            final columns = _workRow(result.work(WorkKind.columns));
            return Column(
              children: [
                if (paired)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: lengths),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          children: [
                            foundations,
                            const SizedBox(height: 10),
                            leanSlab,
                            const SizedBox(height: 10),
                            columns,
                          ],
                        ),
                      ),
                    ],
                  )
                else ...[
                  foundations,
                  const SizedBox(height: 10),
                  lengths,
                  const SizedBox(height: 10),
                  leanSlab,
                  const SizedBox(height: 10),
                  columns,
                ],
                const SizedBox(height: 12),
                _workRow(result.work(WorkKind.roof)),
              ],
            );
          },
        ),
        if (keyboardOpen) ...[const SizedBox(height: 12), calculateButton],
      ],
    );
    return Column(
      children: [
        Expanded(child: fields),
        if (!keyboardOpen)
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: borderColor)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: LayoutBuilder(
                  builder: (context, bounds) {
                    return Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: SizedBox(
                        width: bounds.maxWidth > 680 ? 250 : bounds.maxWidth,
                        child: calculateButton,
                      ),
                    );
                  },
                ),
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
    return QuantityWorkCard(
      result: result,
      title: title,
      status: status,
      quantity: quantity,
      showAreaLabel: roofArea,
      beams: showBeams ? beams : null,
      details: () => _details(kind),
      toggleInclusion: controller.editable
          ? () => controller.include(kind, entry.explicitlyExcluded)
          : null,
    );
  }

  Widget _prices() {
    final project = controller.project;
    return ProjectBody(
      key: ValueKey('prices:${project.id}:$_services'),
      children: [
        FinanceProjectHeading(
          project.name,
          caption: 'الأسعار ونسبة الربح تخص هذا المشروع',
        ),
        FinanceWorkspace(
          summary: ProfitPanel(
            input: NumberInput(
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
          ),
          ledger: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  ChoiceChip(
                    showCheckmark: false,
                    avatar: const Icon(Icons.layers_outlined, size: 17),
                    label: const Text('المواد'),
                    selected: !_services,
                    onSelected: (_) => setState(() => _services = false),
                  ),
                  ChoiceChip(
                    key: const ValueKey('services_prices'),
                    showCheckmark: false,
                    avatar: const Icon(Icons.handyman_outlined, size: 17),
                    label: const Text('المصنعية والخدمات'),
                    selected: _services,
                    onSelected: (_) => setState(() => _services = true),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ..._priceCards(project),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _priceCards(Project project) => [
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
                                .servicePrices[servicePriceKey(work.kind, row)]
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
  ];

  Widget _priceRow({
    required String label,
    required QuantityUnit unit,
    required Widget input,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            Text(
              'د.ل / ${unit.label}',
              style: const TextStyle(color: secondaryText, fontSize: 12),
            ),
          ],
        );
        return constraints.maxWidth < 230 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.3
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [title, const SizedBox(height: 12), input],
              )
            : Row(
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 14),
                  SizedBox(
                    width: constraints.maxWidth < 350 ? 96 : 120,
                    child: input,
                  ),
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
          FinanceProjectHeading(project.name),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: SurfaceCard(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FinanceIcon(
                        stale
                            ? Icons.update_rounded
                            : Icons.request_quote_outlined,
                        gold: stale,
                      ),
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
                      icon: Icon(
                        stale ? Icons.refresh : Icons.straighten_outlined,
                      ),
                      label: Text(stale ? 'تحديث الحسبة' : 'إدخال الكميات'),
                    ),
                  ],
                ),
              ),
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
        FinanceProjectHeading(result.project.name),
        FinanceWorkspace(
          summary: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                  padding: EdgeInsetsDirectional.only(start: 4, top: 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline_rounded,
                        size: 19,
                        color: primaryGreen,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'حصر كامل ضمن النطاق المحدد',
                          style: TextStyle(color: forestInk),
                        ),
                      ),
                    ],
                  ),
                ),
              if (result.unfinishedWorks.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                  child: Text(
                    'البنود غير المكتملة: ${result.unfinishedWorks.map((work) => work.kind.label).join('، ')}',
                    style: const TextStyle(color: secondaryText),
                  ),
                ),
            ],
          ),
          ledger: SurfaceCard(
            child: Column(
              children: [
                const LedgerHeading(
                  'الملخص المالي',
                  icon: Icons.receipt_long_outlined,
                ),
                const SizedBox(height: 12),
                const Divider(),
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
        ),
        const SizedBox(height: 16),
        _resultSection('كميات المواد المطلوبة', Icons.layers_outlined, [
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
        _resultSection('التكلفة حسب بند العمل', Icons.account_tree_outlined, [
          for (final work in result.works)
            DetailPair(
              work.kind.label,
              work.status == WorkStatus.calculated && work.cost != null
                  ? '${money(work.cost!)} د.ل'
                  : statusLabel(work.status),
            ),
        ]),
        const SizedBox(height: 10),
        _resultSection('تفاصيل المصنعية والخدمات', Icons.handyman_outlined, [
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
        _resultSection('تفاصيل الحسابات', Icons.functions_rounded, [
          for (final work in result.works)
            if (work.lines.isNotEmpty) ...[
              SectionHeading('${work.kind.label} • ${work.entry.model!.name}'),
              if (work.kind.isMasonry)
                Text(
                  masonryLengthSummary(work.entry),
                  style: const TextStyle(
                    color: primaryGreen,
                    fontWeight: FontWeight.w600,
                  ),
                ),
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
        FilledButton.icon(
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

  Widget _resultSection(String title, IconData icon, List<Widget> children) =>
      SurfaceCard(
        padding: EdgeInsets.zero,
        child: ExpansionTile(
          key: PageStorageKey('${controller.savedProject.id}:$title'),
          shape: const Border(),
          collapsedShape: const Border(),
          leading: FinanceIcon(icon),
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
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
