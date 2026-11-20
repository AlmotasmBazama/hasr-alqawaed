import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hasr_alqawaed/project/catalog.dart';
import 'package:hasr_alqawaed/project/engine.dart';
import 'package:hasr_alqawaed/project/models.dart';
import 'package:hasr_alqawaed/services/project_report_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'original estimate report keeps embedded Cairo and a frozen price snapshot',
    () async {
      final project = createExampleProject(
        id: 'report-example',
      ).copyWith(date: '2026-11-15', location: 'بنغازي');
      final screenResult = calculateProject(project);
      expect(screenResult.totalCost, closeTo(86364.20, 1e-8));
      expect(screenResult.materialCost, closeTo(66656.20, 1e-8));
      expect(screenResult.serviceCost, closeTo(19708, 1e-8));
      expect(screenResult.work(WorkKind.roof).cost, isNull);
      expect(screenResult.notes, contains('السقف غير مشمول في الإجمالي'));

      final bytes = await ProjectReportService.generate(screenResult);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      final structure = String.fromCharCodes(bytes);
      expect(structure, contains('/FontFile2'));
      expect(structure, contains('/ToUnicode'));
      expect(
        RegExp(r'/Type\s*/Page\b').allMatches(structure).length,
        greaterThan(1),
      );
      expect(bytes.length, greaterThan(15000));
      expect(
        ProjectReportService.filename(DateTime(2026, 11, 15, 18, 30, 12)),
        'hasr_project_20261115_183012.pdf',
      );

      // The estimate itself owns immutable model and price snapshots. A later
      // editor change must not alter the result being exported asynchronously.
      final changed = project.copyWith(
        materialPrices: {...project.materialPrices, 'cement': 40},
      );
      expect(calculateProject(changed).totalCost, closeTo(86026.20, 1e-8));
      expect(screenResult.totalCost, closeTo(86364.20, 1e-8));
    },
  );

  test(
    'full quotation exports the roof and profit from the screen snapshot',
    () async {
      final project = createFullExampleProject(
        id: 'roof-report',
      ).copyWith(profitPercentage: 10, location: 'بنغازي', date: '2026-11-15');
      final snapshot = calculateProject(project);
      final roof = snapshot.work(WorkKind.roof);
      expect(roof.lines, hasLength(9));
      expect(roof.cost, closeTo(61567.50, 1e-8));
      expect(snapshot.quotationTotal, closeTo(162724.87, 1e-8));
      expect(snapshot.isPartial, isFalse);

      final bytes = await ProjectReportService.generate(
        snapshot,
        createdAt: DateTime(2026, 11, 17),
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(String.fromCharCodes(bytes), contains('/FontFile2'));
      if (const bool.fromEnvironment('GENERATE_SAMPLE')) {
        final file = File('output/pdf/hasr_project_sample.pdf');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes);
      }
    },
  );

  test(
    'mixed masonry lengths use the frozen effective inputs in the report',
    () async {
      final project = createExampleProject(id: 'masonry-report');
      final mixed = project
          .updateWork(project.work(WorkKind.tieBeam).copyWith(quantity: 160))
          .updateWork(
            project
                .work(WorkKind.belowMasonry)
                .copyWith(linkedToTieBeam: true, quantity: 23),
          )
          .updateWork(
            project
                .work(WorkKind.aboveMasonry)
                .copyWith(linkedToTieBeam: false, quantity: 170),
          );
      final snapshot = calculateProject(mixed);
      final below = snapshot.work(WorkKind.belowMasonry);
      final above = snapshot.work(WorkKind.aboveMasonry);
      expect(below.entry.quantity, 160);
      expect(above.entry.quantity, 170);
      expect(below.lines.first.quantity, 1600);
      expect(above.lines.first.quantity, 6375);
      final bytes = await ProjectReportService.generate(snapshot);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      if (const bool.fromEnvironment('GENERATE_SAMPLE')) {
        final file = File('output/pdf/linked-masonry-mixed.pdf');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes);
      }
    },
  );

  test(
    'long dynamic tables span pages and incomplete inputs export no stale cost',
    () async {
      final project = createExampleProject(id: 'long-report');
      final foundation = project.work(WorkKind.foundations);
      final beam = project.work(WorkKind.tieBeam);
      final model = beam.model!;
      final expanded = model.copyWith(
        id: 'custom-many-lines',
        name: 'نموذج مخصص ذو سطور متعددة',
        rows: [
          for (var index = 0; index < 50; index++)
            ModelRow(
              id: 'service-$index',
              label: 'خدمة تنفيذ مخصصة رقم ${index + 1}',
              unit: index.isEven ? QuantityUnit.linear : QuantityUnit.area,
              coefficient: 1.25,
              divisor: 2,
              defaultPrice: 3.5,
            ),
        ],
      );
      final current = project
          .updateWork(foundation.copyWith(quantity: null))
          .updateWork(beam.copyWith(model: expanded));
      final result = calculateProject(current);
      expect(result.work(WorkKind.foundations).status, WorkStatus.needsData);
      expect(result.work(WorkKind.foundations).cost, isNull);
      expect(result.work(WorkKind.foundations).lines, isEmpty);
      expect(result.work(WorkKind.tieBeam).lines, hasLength(50));
      final bytes = await ProjectReportService.generate(result);
      expect(
        RegExp(
          r'/Type\s*/Page\b',
        ).allMatches(String.fromCharCodes(bytes)).length,
        greaterThan(3),
      );
    },
  );

  test(
    'empty scope produces an honest zero report with excluded work statuses',
    () async {
      final source = createProject(id: 'empty-report');
      final project = source.copyWith(
        works: source.works
            .map((entry) => entry.copyWith(included: false))
            .toList(),
      );
      final result = calculateProject(project);
      expect(result.totalCost, 0);
      expect(result.materials, isEmpty);
      expect(
        result.works.every((work) => work.status == WorkStatus.excluded),
        isTrue,
      );
      final bytes = await ProjectReportService.generate(result);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    },
  );
}
