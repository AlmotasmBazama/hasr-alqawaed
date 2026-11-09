import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hasr_alqawaed/domain/calculator.dart';
import 'package:hasr_alqawaed/domain/models.dart';
import 'package:hasr_alqawaed/services/report_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'report captures the exact unrounded screen result and embeds local fonts',
    () async {
      const model = FoundationModel.builtIn;
      const inputs = CalculatorInputs.defaults;
      final screenResult = calculate(model, inputs);
      final snapshot = ReportSnapshot(
        model: model,
        inputs: inputs,
        result: screenResult,
        createdAt: DateTime(2026, 11, 8, 12, 30),
      );
      expect(identical(snapshot.result, screenResult), isTrue);
      expect(snapshot.result.lines[1].quantity, closeTo(70 / 6.5, 1e-12));
      expect(snapshot.result.lines[1].cost, closeTo(5600, 1e-9));
      expect(snapshot.result.totalCost, closeTo(17800, 1e-9));
      expect(snapshot.filename, 'hasr_alqawaed_20261108_1230.pdf');

      final bytes = await ReportService.generate(snapshot);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      // Embedded fonts make this a self-contained document, even offline.
      final pdfStructure = String.fromCharCodes(bytes);
      expect(pdfStructure, contains('/FontFile2'));
      expect(pdfStructure, contains('/ToUnicode'));
      expect(bytes.length, greaterThan(10000));

      if (const bool.fromEnvironment('GENERATE_SAMPLE')) {
        final output = File('output/pdf/hasr_alqawaed_sample.pdf');
        await output.parent.create(recursive: true);
        await output.writeAsBytes(bytes);
      }
    },
  );

  test(
    'custom-model report retains caller inputs and exact computed result',
    () {
      final model = FoundationModel.builtIn.copyWith(
        id: 'report-custom',
        name: 'نموذج تجريبي',
        concretePerFoundation: 1,
        steel14BarsPerFoundation: 2,
        steel14BarsPerQuintal: 5,
        steel8BarsPerFoundation: .5,
        steel8BarsPerQuintal: 10,
      );
      const inputs = CalculatorInputs(count: 10, prices: Prices.defaults);
      final screenResult = calculate(model, inputs);
      final snapshot = ReportSnapshot(
        model: model,
        inputs: inputs,
        result: screenResult,
        createdAt: DateTime(2026, 11, 8),
      );
      expect(identical(snapshot.result, screenResult), isTrue);
      expect(snapshot.inputs.count, 10);
      expect(snapshot.result.totalCost, closeTo(9580, 1e-9));
      expect(snapshot.model.steel14BarsPerQuintal, 5);
    },
  );
}
