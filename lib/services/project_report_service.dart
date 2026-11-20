import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../domain/numbers.dart';
import '../project/engine.dart';
import '../project/models.dart';

/// Renders the immutable estimate already displayed by the project screen.
/// Prices, quantities and totals are never recalculated in the PDF layer.
class ProjectReportService {
  static const _green = PdfColor.fromInt(0xff246b57);
  static const _ink = PdfColor.fromInt(0xff202a28);
  static const _muted = PdfColor.fromInt(0xff596760);
  static const _light = PdfColor.fromInt(0xfff6f7f5);
  static const _border = PdfColor.fromInt(0xffdce3df);
  static const _amber = PdfColor.fromInt(0xfffff0ca);

  static String filename([DateTime? createdAt]) {
    final date = createdAt ?? DateTime.now();
    return 'hasr_project_${date.year}${_pad(date.month)}${_pad(date.day)}_'
        '${_pad(date.hour)}${_pad(date.minute)}${_pad(date.second)}.pdf';
  }

  static Future<Uint8List> generate(
    ProjectResult snapshot, {
    DateTime? createdAt,
  }) async {
    final reportDate = createdAt ?? DateTime.now();
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Cairo-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Cairo-Bold.ttf'),
    );
    final doc = pw.Document(
      title: 'تقرير حصر المشروع - ${snapshot.project.name}',
      author: 'حصر المشروع',
      creator: 'حصر المشروع',
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(32, 30, 32, 30),
        textDirection: pw.TextDirection.rtl,
        maxPages: 300,
        header: (context) => context.pageNumber == 1
            ? pw.SizedBox()
            : pw.Container(
                padding: const pw.EdgeInsets.only(bottom: 10),
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
        build: (_) => [
          ..._summary(snapshot, reportDate),
          pw.NewPage(freeSpace: 150),
          _heading('ملخص المدخلات والنماذج'),
          _inputs(snapshot),
          if (snapshot.calculatedCount > 0) ...[
            pw.NewPage(freeSpace: 155),
            _heading('تفاصيل بنود الأعمال المحسوبة'),
            _ar(
              'سعر الوحدة وتكلفة السطر بالدينار الليبي. تكاليف البنود قبل الربح.',
              size: 9,
              color: _muted,
            ),
            for (final work in snapshot.works.where(
              (work) => work.status == WorkStatus.calculated,
            ))
              ..._workDetails(work),
          ],
          pw.NewPage(freeSpace: 130),
          _heading('الحصر المجمع للمواد'),
          _ar(
            'التجميع حسب هوية المادة ومواصفاتها ووحدتها. التكلفة هي مجموع تكاليف السطور، بما فيها الأسعار المخصصة.',
            size: 9,
            color: _muted,
          ),
          pw.SizedBox(height: 6),
          if (snapshot.materials.isEmpty)
            _ar('لا توجد مواد محسوبة ضمن البيانات الحالية.', color: _muted)
          else
            _table(
              headers: [
                'التكلفة (د.ل)',
                'الكمية',
                'الوحدة',
                'المادة والمواصفة',
              ],
              widths: const [1.05, .95, 1, 2],
              rows: [
                for (final material in snapshot.materials)
                  [
                    _number(_money(material.cost)),
                    _number(_quantity(material.quantity), strong: true),
                    _ar(material.material.unit.label, size: 9),
                    _ar(material.material.label, strong: true),
                  ],
              ],
            ),
          pw.NewPage(freeSpace: 130),
          _heading('تفاصيل المصنعية والخدمات'),
          _ar(
            'تظل كل خدمة مرتبطة ببند عملها ووحدة تسعيرها. تُجمع التكاليف فقط.',
            size: 9,
            color: _muted,
          ),
          pw.SizedBox(height: 6),
          if (snapshot.services.isEmpty)
            _ar('لا توجد خدمات محسوبة ضمن البيانات الحالية.', color: _muted)
          else
            _table(
              headers: [
                'التكلفة (د.ل)',
                'سعر الوحدة',
                'الكمية',
                'الوحدة',
                'الخدمة وبندها',
              ],
              widths: const [1.05, .95, .75, 1.15, 1.9],
              rows: [
                for (final line in snapshot.services)
                  [
                    _number(_money(line.cost), strong: true),
                    _number(_money(line.unitPrice)),
                    _number(_quantity(line.quantity)),
                    _ar(line.unit.label, size: 9),
                    _ar('${line.label} • ${line.kind.label}', size: 9),
                  ],
              ],
            ),
          pw.NewPage(freeSpace: 235),
          _heading('نطاق الحصر والملاحظات'),
          if (snapshot.works.any((work) => work.status == WorkStatus.excluded))
            _note(
              'بنود غير مطلوبة: ${snapshot.works.where((work) => work.status == WorkStatus.excluded).map((work) => work.label).join('، ')}',
              caution: false,
            ),
          if (snapshot.unfinishedWorks.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            _note(
              'بنود غير مكتملة: ${snapshot.unfinishedWorks.map((work) => work.label).join('، ')}',
            ),
          ],
          for (final note in snapshot.notes) ...[
            pw.SizedBox(height: 4),
            _ar('• $note', size: 9, color: _muted),
          ],
          pw.SizedBox(height: 4),
          _note(
            'تُحسب السطور بالقيم الدقيقة ثم تُقرّب عند العرض فقط. معاملات النماذج مخصصة لتقدير الكميات والتكاليف؛ لا تمثل تحققًا من سلامة التصميم الإنشائي.',
            caution: false,
          ),
        ],
      ),
    );
    return doc.save();
  }

  static Future<bool> share(ProjectResult snapshot, {Rect? bounds}) async {
    final createdAt = DateTime.now();
    final bytes = await generate(snapshot, createdAt: createdAt);
    return Printing.sharePdf(
      bytes: bytes,
      filename: filename(createdAt),
      bounds: bounds,
      subject: 'تقرير حصر المشروع',
    );
  }

  static List<pw.Widget> _summary(ProjectResult snapshot, DateTime reportDate) {
    final project = snapshot.project;
    final total = snapshot.quotationTotal;
    return [
      _ar('تقرير حصر المشروع', size: 24, strong: true, color: _green),
      _ar(project.name, size: 16, strong: true),
      if (project.isExample)
        _ar('مشروع تجريبي', size: 9, strong: true, color: _green),
      pw.SizedBox(height: 8),
      _physicalRow([
        pw.Expanded(
          child: _ar('تاريخ التقرير: ${_date(reportDate)}', color: _muted),
        ),
        pw.Expanded(
          child: _ar(
            'تاريخ المشروع: ${project.date.isEmpty ? 'غير محدد' : project.date}',
            color: _muted,
          ),
        ),
      ]),
      _ar(
        'الموقع: ${project.location.trim().isEmpty ? 'غير محدد' : project.location}',
        color: _muted,
      ),
      pw.SizedBox(height: 10),
      _note(
        snapshot.isPartial
            ? 'حالة الحصر: حصر جزئي. البنود غير المكتملة غير مشمولة في الإجمالي.'
            : 'حالة الحصر: كامل ضمن النطاق المحدد.',
        caution: snapshot.isPartial,
      ),
      pw.SizedBox(height: 8),
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        decoration: pw.BoxDecoration(
          color: _green,
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: _physicalRow([
          if (total == null)
            _ar('غير متاح', size: 13, strong: true, color: PdfColors.white)
          else ...[
            pw.ConstrainedBox(
              constraints: const pw.BoxConstraints(maxWidth: 185),
              child: _number(
                _money(total),
                size: 23,
                strong: true,
                color: PdfColors.white,
                align: pw.TextAlign.left,
              ),
            ),
            pw.SizedBox(width: 8),
            _ar('د.ل', size: 10, color: PdfColors.white),
          ],
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: _ar(
              'إجمالي العرض شامل الربح',
              size: 14,
              strong: true,
              color: PdfColors.white,
            ),
          ),
        ]),
      ),
      pw.SizedBox(height: 8),
      _table(
        headers: ['القيمة', 'الملخص المالي'],
        widths: const [1, 2.3],
        rows: [
          [_number(_money(snapshot.materialCost)), _ar('تكلفة المواد (د.ل)')],
          [
            _number(_money(snapshot.serviceCost)),
            _ar('تكلفة المصنعية والخدمات (د.ل)'),
          ],
          [
            _number(_money(snapshot.baseCost), strong: true),
            _ar('إجمالي التكلفة قبل الربح (د.ل)', strong: true),
          ],
          [
            _number(
              snapshot.profitPercentage == null
                  ? '-'
                  : '${_quantity(snapshot.profitPercentage!)}%',
            ),
            _ar('نسبة الربح المضافة إلى التكلفة'),
          ],
          [_number(_money(snapshot.profitAmount)), _ar('قيمة الربح (د.ل)')],
          [
            _number(_money(total), strong: true, color: _green),
            _ar('إجمالي العرض شامل الربح (د.ل)', strong: true, color: _green),
          ],
        ],
      ),
    ];
  }

  static pw.Widget _inputs(ProjectResult snapshot) => _table(
    headers: ['التكلفة قبل الربح', 'الحالة', 'المدخلات', 'بند العمل والنموذج'],
    widths: const [1.08, .9, 1.7, 1.8],
    rows: [
      for (final work in snapshot.works)
        [
          _number(_money(work.cost), strong: true),
          _ar(work.status.label, size: 9),
          _inputDetails(work),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _ar(work.label, strong: true),
              _ar(
                work.entry.model?.name ?? 'بلا نموذج',
                size: 9,
                color: _muted,
              ),
            ],
          ),
        ],
    ],
  );

  static pw.Widget _inputDetails(WorkResult work) {
    final entry = work.entry;
    if (work.kind.isMasonry) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _valueAndUnit(entry.quantity, entry.inputUnit, size: 9),
          _ar(_lengthSource(entry), size: 8, color: _muted),
        ],
      );
    }
    if (work.kind != WorkKind.roof || entry.inputUnit != QuantityUnit.area) {
      return _valueAndUnit(entry.quantity, entry.inputUnit, size: 9);
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _ar('مساحة السقف', size: 8, color: _muted),
        _valueAndUnit(entry.quantity, entry.inputUnit, size: 9),
        _ar('أطوال كمرات السقف', size: 8, color: _muted),
        if (entry.model != null && !entry.model!.requiresRoofBeamLength)
          _ar('غير مستخدمة في النموذج', size: 9)
        else
          _valueAndUnit(entry.roofBeamLength, QuantityUnit.linear, size: 9),
      ],
    );
  }

  static String _lengthSource(WorkEntry entry) =>
      entry.linkedToTieBeam ? 'الطول مرتبط بالميدة' : 'طول مخصص';

  static List<pw.Widget> _workDetails(WorkResult work) {
    final description = work.entry.model?.description ?? '';
    return [
      pw.NewPage(freeSpace: 145),
      _heading(work.label, size: 12),
      _ar(work.entry.model!.name, strong: true),
      if (work.kind.isMasonry)
        _ar(
          '${_lengthSource(work.entry)} • ${_quantity(work.entry.quantity!)} ${work.entry.inputUnit.label}',
          size: 9,
          color: _green,
        ),
      if (description.isNotEmpty) _ar(description, size: 9, color: _muted),
      pw.SizedBox(height: 6),
      _table(
        headers: [
          'تكلفة السطر',
          'سعر الوحدة',
          'الكمية المسعّرة',
          'المادة أو الخدمة: ${work.label}',
        ],
        widths: const [1.02, .87, 1.18, 2.5],
        rows: [
          for (final line in work.lines)
            [
              _number(_money(line.cost), strong: true),
              _number(_money(line.unitPrice)),
              _valueAndUnit(line.quantity, line.unit, size: 9),
              _lineDetails(line),
            ],
        ],
      ),
      pw.SizedBox(height: 6),
      _physicalRow([
        _number(_money(work.cost), strong: true, size: 12, color: _green),
        pw.Expanded(
          child: _ar(
            'تكلفة ${work.label} قبل الربح (د.ل)',
            strong: true,
            color: _green,
          ),
        ),
      ]),
      if (work.lines.any((line) => line.reviewBasis)) ...[
        pw.SizedBox(height: 4),
        for (final line in work.lines.where((line) => line.reviewBasis))
          _ar(
            '${line.label}: ${line.unit.label} كأساس تسعير للتنفيذ؛ الكمية لا تمثل عدد المعدات أو حجم المياه.',
            size: 8,
            color: _muted,
          ),
      ],
    ];
  }

  static pw.Widget _lineDetails(CalculatedLine line) {
    final input = _quantity(line.inputQuantity);
    final coefficient = _quantity(line.row.coefficient);
    final raw = _quantity(line.rawQuantity);
    final quantity = _quantity(line.quantity);
    final divisor = _quantity(line.row.divisor);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _ar(line.label, strong: true),
        if (line.overridden) _ar('سعر مخصص', size: 8, color: _green),
        _ar(
          '${line.quantitySource.label} (${line.inputUnit.label})',
          size: 8.5,
          color: _muted,
        ),
        _formula(
          '$input × $coefficient = $raw',
          (line.row.sourceUnit ?? line.unit).label,
        ),
        if (line.row.divisor != 1) ...[
          _formula('$raw ÷ $divisor = $quantity', line.unit.label),
          _formula(
            '$quantity × ${_money(line.unitPrice)} = ${_money(line.cost)}',
            'د.ل',
          ),
        ],
      ],
    );
  }

  static pw.Widget _formula(String expression, String unit) => _physicalRow([
    pw.Flexible(
      child: _number(expression, size: 8.5, align: pw.TextAlign.right),
    ),
    pw.SizedBox(width: 4),
    _ar(unit, size: 8.5, color: _muted),
  ], mainAxisAlignment: pw.MainAxisAlignment.end);

  static pw.Widget _valueAndUnit(
    double? value,
    QuantityUnit unit, {
    required double size,
  }) => value == null
      ? _ar('غير مدخل', size: size, color: _muted)
      : _physicalRow([
          pw.Expanded(child: _number(_quantity(value), size: size)),
          pw.SizedBox(width: 4),
          _ar(unit.label, size: size),
        ]);

  static String _pad(int value) => value.toString().padLeft(2, '0');
  static String _date(DateTime time) =>
      '${time.year}-${_pad(time.month)}-${_pad(time.day)}';

  static String _quantity(num value) {
    if (value.abs() >= 1e21) return formatNumber(value);
    final [whole, fraction] = value.toStringAsFixed(6).split('.');
    final grouped = whole.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    final decimals = fraction.replaceFirst(RegExp(r'0+$'), '');
    return decimals.isEmpty ? grouped : '$grouped.$decimals';
  }

  static String _money(num? value) {
    if (value == null) return '-';
    final parts = formatNumber(value).split('.');
    return '${parts.first}.${parts.length == 1 ? '00' : parts[1].padRight(2, '0')}';
  }

  static pw.Widget _heading(String text, {double size = 14}) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 12, bottom: 5),
    child: _ar(text, size: size, strong: true, color: _green),
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
    pw.TextAlign align = pw.TextAlign.center,
  }) => pw.Text(
    text,
    textDirection: pw.TextDirection.ltr,
    textAlign: align,
    style: pw.TextStyle(
      fontSize: size,
      fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: color,
    ),
  );

  static pw.Widget _physicalRow(
    List<pw.Widget> children, {
    pw.MainAxisAlignment mainAxisAlignment = pw.MainAxisAlignment.start,
  }) => pw.Directionality(
    textDirection: pw.TextDirection.ltr,
    child: pw.Row(mainAxisAlignment: mainAxisAlignment, children: children),
  );

  static pw.Widget _table({
    required List<String> headers,
    required List<double> widths,
    required List<List<pw.Widget>> rows,
  }) {
    pw.Widget cell(pw.Widget child) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      child: child,
    );
    // Table itself is a spanning widget and repeats its header when paginated.
    // Physical column order is left-to-right; Arabic labels are explicitly RTL.
    return pw.Table(
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
              cell(_ar(header, size: 9, strong: true, color: PdfColors.white)),
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
    );
  }
}
