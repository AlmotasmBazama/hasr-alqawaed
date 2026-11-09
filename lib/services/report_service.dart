import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../domain/calculator.dart';
import '../domain/models.dart';
import '../domain/numbers.dart';

/// A stable copy of the same immutable result displayed by the calculator.
class ReportSnapshot {
  const ReportSnapshot({
    required this.model,
    required this.inputs,
    required this.result,
    required this.createdAt,
  });

  final FoundationModel model;
  final CalculatorInputs inputs;
  final CalculationResult result;
  final DateTime createdAt;

  String get filename {
    final date = createdAt;
    String pad(int value) => value.toString().padLeft(2, '0');
    return 'hasr_alqawaed_${date.year}${pad(date.month)}${pad(date.day)}_'
        '${pad(date.hour)}${pad(date.minute)}.pdf';
  }
}

class ReportService {
  static const _green = PdfColor.fromInt(0xff246b57);
  static const _ink = PdfColor.fromInt(0xff202a28);
  static const _muted = PdfColor.fromInt(0xff75807b);
  static const _light = PdfColor.fromInt(0xfff6f7f5);
  static const _border = PdfColor.fromInt(0xffdce3df);

  static Future<Uint8List> generate(ReportSnapshot snapshot) async {
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Cairo-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Cairo-Bold.ttf'),
    );
    final doc = pw.Document(
      title: 'تقرير حصر القواعد',
      author: 'حصر القواعد',
      creator: 'حصر القواعد',
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );
    final model = snapshot.model;
    final date = snapshot.createdAt;
    String pad(int value) => value.toString().padLeft(2, '0');
    final dateLabel =
        '${date.year}/${pad(date.month)}/${pad(date.day)}'
        '  ${pad(date.hour)}:${pad(date.minute)}';
    final dimensions =
        '${formatNumber(model.length)} × '
        '${formatNumber(model.width)} × ${formatNumber(model.height)}';

    pw.Widget ar(
      String text, {
      double size = 11,
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
    pw.Widget numText(
      String text, {
      double size = 11,
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
    pw.Widget cell(pw.Widget child) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 7),
      child: child,
    );
    pw.Widget physicalRow({
      pw.MainAxisAlignment mainAxisAlignment = pw.MainAxisAlignment.start,
      required List<pw.Widget> children,
    }) => pw.Directionality(
      textDirection: pw.TextDirection.ltr,
      child: pw.Row(mainAxisAlignment: mainAxisAlignment, children: children),
    );
    // Physical column order is left-to-right. Arabic item names are rightmost.
    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _green),
        children:
            ['التكلفة', 'سعر الوحدة', 'الكمية الإجمالية', 'الوحدة', 'البند']
                .map(
                  (text) => cell(
                    ar(text, size: 10, strong: true, color: PdfColors.white),
                  ),
                )
                .toList(),
      ),
      for (var index = 0; index < snapshot.result.lines.length; index++)
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: index.isEven ? _light : PdfColors.white,
          ),
          children: [
            cell(
              numText(
                formatNumber(snapshot.result.lines[index].cost),
                strong: true,
              ),
            ),
            cell(numText(formatNumber(snapshot.result.lines[index].unitPrice))),
            cell(numText(formatNumber(snapshot.result.lines[index].quantity))),
            cell(
              ar(
                snapshot.result.lines[index].unit == 'م³'
                    ? 'متر مكعب'
                    : snapshot.result.lines[index].unit,
                size: 9,
              ),
            ),
            cell(ar(snapshot.result.lines[index].label, strong: true)),
          ],
        ),
    ];

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        textDirection: pw.TextDirection.rtl,
        footer: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(top: 12),
          decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: _border)),
          ),
          child: physicalRow(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              numText(
                '${context.pageNumber} / ${context.pagesCount}',
                size: 9,
                color: _muted,
              ),
              ar('حصر القواعد • تقرير كميات وتكلفة', size: 9, color: _muted),
            ],
          ),
        ),
        build: (context) => [
          ar('تقرير حصر القواعد', size: 25, strong: true, color: _green),
          pw.SizedBox(height: 6),
          ar('حساب الكميات والتكلفة', size: 11, color: _muted),
          pw.SizedBox(height: 14),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: _light,
              borderRadius: pw.BorderRadius.circular(10),
              border: pw.Border.all(color: _border),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                ar(model.name, size: 15, strong: true),
                pw.SizedBox(height: 8),
                physicalRow(
                  mainAxisAlignment: pw.MainAxisAlignment.end,
                  children: [
                    ar('متر', size: 10),
                    pw.SizedBox(width: 5),
                    numText(dimensions),
                    pw.SizedBox(width: 8),
                    ar('الأبعاد: الطول × العرض × الارتفاع', size: 10),
                  ],
                ),
                pw.SizedBox(height: 6),
                physicalRow(
                  mainAxisAlignment: pw.MainAxisAlignment.end,
                  children: [
                    numText(formatNumber(snapshot.inputs.count), strong: true),
                    pw.SizedBox(width: 8),
                    ar('عدد القواعد', size: 11),
                  ],
                ),
                pw.SizedBox(height: 6),
                physicalRow(
                  mainAxisAlignment: pw.MainAxisAlignment.end,
                  children: [
                    numText(dateLabel, size: 10, color: _muted),
                    pw.SizedBox(width: 8),
                    ar('تاريخ ووقت التقرير', size: 10, color: _muted),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          ar('تفاصيل الحسبة', size: 14, strong: true),
          pw.SizedBox(height: 6),
          ar(
            'جميع الأسعار والتكاليف بالدينار الليبي (د.ل)',
            size: 9,
            color: _muted,
          ),
          pw.SizedBox(height: 8),
          pw.Directionality(
            textDirection: pw.TextDirection.ltr,
            child: pw.Table(
              columnWidths: const {
                0: pw.FlexColumnWidth(1.05),
                1: pw.FlexColumnWidth(1.05),
                2: pw.FlexColumnWidth(1.15),
                3: pw.FlexColumnWidth(1),
                4: pw.FlexColumnWidth(1.5),
              },
              border: const pw.TableBorder(
                horizontalInside: pw.BorderSide(color: _border, width: .5),
              ),
              defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
              children: rows,
            ),
          ),
          pw.SizedBox(height: 14),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 10,
            ),
            decoration: pw.BoxDecoration(
              color: _green,
              borderRadius: pw.BorderRadius.circular(10),
            ),
            child: physicalRow(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                physicalRow(
                  children: [
                    ar('د.ل', size: 14, color: PdfColors.white),
                    pw.SizedBox(width: 10),
                    numText(
                      formatNumber(snapshot.result.totalCost),
                      size: 24,
                      strong: true,
                      color: PdfColors.white,
                    ),
                  ],
                ),
                ar(
                  'إجمالي التكلفة',
                  size: 14,
                  strong: true,
                  color: PdfColors.white,
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 14),
          ar('الثوابت المعتمدة', size: 11, strong: true),
          pw.SizedBox(height: 5),
          ar(
            'حديد 14: ${formatNumber(model.steel14BarsPerQuintal)} سيخ لكل قنطار.'
            '   حديد 8: ${formatNumber(model.steel8BarsPerQuintal)} سيخ لكل قنطار.',
            size: 9,
            color: _muted,
          ),
          ar(
            'الخرسانة لكل قاعدة: ${formatNumber(model.concretePerFoundation)} متر مكعب.'
            ' الأبعاد وصفية، والحساب يعتمد كمية الخرسانة المحددة.',
            size: 9,
            color: _muted,
          ),
          pw.SizedBox(height: 8),
          ar(
            'الكميات والمبالغ المعروضة مقربة إلى منزلتين عند الحاجة؛ '
            'الحساب يعتمد القيم الدقيقة قبل التقريب.',
            size: 9,
            color: _muted,
          ),
        ],
      ),
    );
    return doc.save();
  }

  /// A false return (e.g. cancellation) is a normal user action.
  static Future<bool> share(ReportSnapshot snapshot, {Rect? bounds}) async {
    final bytes = await generate(snapshot);
    return Printing.sharePdf(
      bytes: bytes,
      filename: snapshot.filename,
      bounds: bounds,
      subject: 'تقرير حصر القواعد',
    );
  }
}
