import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../domain/numbers.dart';
import '../project/engine.dart';

/// Renders the immutable estimate already displayed by the project screen.
/// Prices, quantities and totals are never recalculated in the PDF layer.
class ProjectReportService {
  static const _green = PdfColor.fromInt(0xff246b57);
  static const _ink = PdfColor.fromInt(0xff202a28);
  static const _muted = PdfColor.fromInt(0xff75807b);
  static const _light = PdfColor.fromInt(0xfff6f7f5);
  static const _border = PdfColor.fromInt(0xffdce3df);
  static const _amber = PdfColor.fromInt(0xfffff0ca);

  static String filename([DateTime? createdAt]) {
    final date = createdAt ?? DateTime.now();
    String pad(int number) => number.toString().padLeft(2, '0');
    return 'hasr_project_${date.year}${pad(date.month)}${pad(date.day)}_'
        '${pad(date.hour)}${pad(date.minute)}${pad(date.second)}.pdf';
  }

  static Future<Uint8List> generate(ProjectResult snapshot) async {
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Cairo-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Cairo-Bold.ttf'),
    );
    final project = snapshot.project;
    final doc = pw.Document(
      title: 'تقرير حصر المشروع - ${project.name}',
      author: 'حصر المشروع',
      creator: 'حصر المشروع',
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );

    final content = <pw.Widget>[
      _ar('تقرير حصر المشروع', size: 25, strong: true, color: _green),
      pw.SizedBox(height: 6),
      _ar(project.name, size: 16, strong: true),
      pw.SizedBox(height: 4),
      _ar(
        'تاريخ المشروع: ${project.date}   |   الموقع: '
        '${project.location.trim().isEmpty ? 'غير محدد' : project.location}',
        size: 10,
        color: _muted,
      ),
      pw.SizedBox(height: 14),
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: pw.BoxDecoration(
          color: _green,
          borderRadius: pw.BorderRadius.circular(9),
        ),
        child: _physicalRow([
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _number(
                _money(snapshot.totalCost),
                size: 26,
                strong: true,
                color: PdfColors.white,
              ),
              _ar('د.ل', size: 11, color: PdfColors.white),
            ],
          ),
          pw.Expanded(
            child: _ar(
              'إجمالي البنود المحسوبة',
              size: 15,
              strong: true,
              color: PdfColors.white,
            ),
          ),
        ]),
      ),
      pw.SizedBox(height: 8),
      _ar(
        snapshot.isPartial
            ? 'حالة الحصر: مبدئي / جزئي'
            : 'حالة الحصر: مكتمل ضمن نطاقه',
        strong: true,
        color: _green,
      ),
      for (final note in snapshot.notes) ...[
        pw.SizedBox(height: 4),
        _note(note),
      ],
      pw.SizedBox(height: 10),
      _table(
        headers: ['التكلفة بالدينار الليبي', 'التصنيف'],
        widths: const [1, 1.6],
        rows: [
          [
            _number(_money(snapshot.materialCost), strong: true),
            _ar('إجمالي المواد'),
          ],
          [
            _number(_money(snapshot.serviceCost), strong: true),
            _ar('إجمالي المصنعية والخدمات'),
          ],
        ],
      ),
      _heading('إجمالي كميات المواد'),
      _ar(
        'التكلفة تجمع تكاليف السطور الفعلية، بما فيها الأسعار المخصصة.',
        size: 9,
        color: _muted,
      ),
      pw.SizedBox(height: 6),
      if (snapshot.materials.isEmpty)
        _ar('لا توجد مواد محسوبة ضمن البيانات الحالية.', color: _muted)
      else
        _table(
          headers: ['التكلفة', 'الكمية', 'الوحدة', 'المادة والمواصفة'],
          widths: const [1.05, .95, 1, 1.8],
          rows: [
            for (final material in snapshot.materials)
              [
                _number(_money(material.cost)),
                _number(formatNumber(material.quantity), strong: true),
                _ar(material.material.unit.label, size: 9),
                _ar(material.material.label, strong: true),
              ],
          ],
        ),
      pw.NewPage(),
      _heading('التكلفة حسب بند العمل'),
      _table(
        headers: ['التكلفة', 'الحالة', 'المدخل', 'بند العمل'],
        widths: const [1.1, 1.15, 1.25, 1.6],
        rows: [
          for (final work in snapshot.works)
            [
              _number(
                work.cost == null ? '—' : _money(work.cost!),
                strong: true,
              ),
              _ar(work.status.label, size: 9),
              _ar(_inputLabel(work), size: 9),
              _ar(work.label, strong: true),
            ],
        ],
      ),
      pw.SizedBox(height: 10),
      _ar(
        'الشرطة تعني أن البند لم يُحسب، ولا تعني أن تكلفته صفر. '
        'البنود المستبعدة والناقصة غير داخلة في الإجمالي.',
        size: 9,
        color: _muted,
      ),
      for (final work in snapshot.works.where(
        (work) => work.status != WorkStatus.calculated,
      ))
        ..._workWidgets(work),
      pw.SizedBox(height: 12),
      _note(
        'الحساب يعتمد القيم الدقيقة دون تقريب وسيط. '
        'الكميات والمبالغ المعروضة مقربة عند العرض فقط. '
        'معاملات النماذج مقدمة للحصر؛ الأوصاف والأبعاد لا تعيد اشتقاقها تلقائيًا.',
        caution: false,
      ),
      if (snapshot.calculatedCount > 0) ...[
        pw.NewPage(),
        _ar('تفاصيل بنود الأعمال', size: 21, strong: true, color: _green),
        pw.SizedBox(height: 4),
        _ar(
          'جميع الأسعار والتكاليف بالدينار الليبي. '
          'المعامل لكل وحدة من مدخل البند، ثم القسمة على معامل التحويل عند وجوده.',
          size: 9,
          color: _muted,
        ),
        for (final work in snapshot.works.where(
          (work) => work.status == WorkStatus.calculated,
        ))
          ..._workWidgets(work),
      ],
    ];

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(34, 30, 34, 32),
        textDirection: pw.TextDirection.rtl,
        maxPages: 300,
        header: (context) => context.pageNumber == 1
            ? pw.SizedBox()
            : pw.Container(
                padding: const pw.EdgeInsets.only(bottom: 9),
                child: _ar('تقرير حصر المشروع', size: 9, color: _muted),
              ),
        footer: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(top: 8),
          decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: _border)),
          ),
          child: _physicalRow([
            _number(
              '${context.pageNumber} / ${context.pagesCount}',
              size: 9,
              color: _muted,
            ),
            pw.Expanded(
              child: _ar('حصر المشروع • كميات وتكاليف', size: 9, color: _muted),
            ),
          ]),
        ),
        build: (_) => content,
      ),
    );
    return doc.save();
  }

  static Future<bool> share(ProjectResult snapshot, {Rect? bounds}) async {
    final bytes = await generate(snapshot);
    return Printing.sharePdf(
      bytes: bytes,
      filename: filename(),
      bounds: bounds,
      subject: 'تقرير حصر المشروع',
    );
  }

  static List<pw.Widget> _workWidgets(WorkResult work) {
    final model = work.entry.model;
    return [
      pw.NewPage(freeSpace: work.status == WorkStatus.calculated ? 580 : 130),
      _heading(work.label),
      _ar(
        '${work.status.label}  •  ${model?.name ?? 'بانتظار النموذج'}',
        strong: true,
      ),
      if (model != null && model.description.isNotEmpty)
        _ar(model.description, size: 9, color: _muted),
      pw.SizedBox(height: 4),
      _ar('مدخل البند: ${_inputLabel(work)}', size: 10),
      if (work.status != WorkStatus.calculated) ...[
        pw.SizedBox(height: 4),
        _ar('غير مشمول في الإجمالي المحسوب.', size: 9, color: _muted),
      ] else ...[
        pw.SizedBox(height: 7),
        _table(
          headers: [
            'التكلفة',
            'سعر الوحدة',
            'الكمية',
            'الوحدة',
            'المادة أو الخدمة',
          ],
          widths: const [1.05, .85, .95, .9, 1.65],
          rows: [
            for (final line in work.lines)
              [
                _number(_money(line.cost), strong: true),
                _number(formatNumber(line.unitPrice)),
                _number(formatNumber(line.quantity)),
                _ar(line.unit.label, size: 9),
                _ar(
                  '${line.label}${line.overridden ? ' (سعر مخصص)' : ''}',
                  strong: true,
                  size: 10,
                ),
              ],
          ],
        ),
        pw.SizedBox(height: 6),
        _physicalRow([
          _number(_money(work.cost!), strong: true, size: 13, color: _green),
          pw.Expanded(
            child: _ar('إجمالي البند (د.ل)', strong: true, color: _green),
          ),
        ]),
        pw.SizedBox(height: 7),
        _ar('المعاملات والتحويلات المستخدمة', size: 10, strong: true),
        pw.SizedBox(height: 4),
        _table(
          headers: [
            'الكمية الأولية',
            'قاسم التحويل',
            'المعامل',
            'المادة أو الخدمة',
          ],
          widths: const [1.3, .9, .85, 1.65],
          rows: [
            for (final line in work.lines)
              [
                _ar(
                  '${formatNumber(line.rawQuantity)} '
                  '${(line.row.sourceUnit ?? line.unit).label}',
                  size: 9,
                ),
                _number(inputNumber(line.row.divisor), size: 9),
                _number(inputNumber(line.row.coefficient), size: 9),
                _ar(line.label, size: 9),
              ],
          ],
        ),
        if (work.lines.any((line) => line.reviewBasis)) ...[
          pw.SizedBox(height: 6),
          _note('تقدير مبدئي — توجد وحدات خدمات قابلة للمراجعة'),
          for (final line in work.lines.where((line) => line.reviewBasis))
            _ar(
              '${line.label}: ${line.unit.label} كأساس تسعير للتنفيذ، '
              'ولا تمثل عدد المعدات أو حجم المياه.',
              size: 8,
              color: _muted,
            ),
        ],
      ],
      pw.SizedBox(height: 10),
    ];
  }

  static String _inputLabel(WorkResult work) {
    final quantity = work.entry.quantity;
    final unit = work.entry.model?.inputUnit;
    return quantity == null || unit == null
        ? 'غير مكتمل'
        : '${formatNumber(quantity)} ${unit.label}';
  }

  static String _money(num value) {
    final formatted = formatNumber(value);
    final parts = formatted.split('.');
    return '${parts.first}.${parts.length == 1 ? '00' : parts[1].padRight(2, '0')}';
  }

  static pw.Widget _heading(String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 13, bottom: 6),
    child: _ar(text, size: 14, strong: true, color: _green),
  );

  static pw.Widget _note(String text, {bool caution = true}) => pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: pw.BoxDecoration(
      color: caution ? _amber : _light,
      borderRadius: pw.BorderRadius.circular(5),
    ),
    child: _ar(text, size: 9),
  );

  static pw.Widget _ar(
    String text, {
    double size = 10,
    bool strong = false,
    PdfColor color = _ink,
  }) => pw.Text(
    text,
    textDirection: pw.TextDirection.rtl,
    textAlign: pw.TextAlign.right,
    style: pw.TextStyle(
      fontSize: size,
      fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: color,
    ),
  );

  static pw.Widget _number(
    String text, {
    double size = 10,
    bool strong = false,
    PdfColor color = _ink,
  }) => pw.Text(
    text,
    textDirection: pw.TextDirection.ltr,
    textAlign: pw.TextAlign.center,
    style: pw.TextStyle(
      fontSize: size,
      fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: color,
    ),
  );

  static pw.Widget _physicalRow(List<pw.Widget> children) => pw.Directionality(
    textDirection: pw.TextDirection.ltr,
    child: pw.Row(children: children),
  );

  static pw.Widget _table({
    required List<String> headers,
    required List<double> widths,
    required List<List<pw.Widget>> rows,
  }) {
    pw.Widget cell(pw.Widget child) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: child,
    );
    return pw.Directionality(
      textDirection: pw.TextDirection.ltr,
      child: pw.Table(
        columnWidths: {
          for (var index = 0; index < widths.length; index++)
            index: pw.FlexColumnWidth(widths[index]),
        },
        border: const pw.TableBorder(
          horizontalInside: pw.BorderSide(color: _border, width: .5),
        ),
        defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
        children: [
          pw.TableRow(
            repeat: true,
            decoration: const pw.BoxDecoration(color: _green),
            children: [
              for (final header in headers)
                cell(
                  _ar(header, size: 9, strong: true, color: PdfColors.white),
                ),
            ],
          ),
          for (var index = 0; index < rows.length; index++)
            pw.TableRow(
              decoration: pw.BoxDecoration(
                color: index.isEven ? _light : PdfColors.white,
              ),
              children: rows[index].map(cell).toList(),
            ),
        ],
      ),
    );
  }
}
