import 'package:flutter_test/flutter_test.dart';
import 'package:hasr_alqawaed/domain/calculator.dart';
import 'package:hasr_alqawaed/domain/models.dart';
import 'package:hasr_alqawaed/domain/numbers.dart';

void main() {
  test('required built-in calculation retains exact steel quantity', () {
    final result = calculate(
      FoundationModel.builtIn,
      CalculatorInputs.defaults,
    );
    expect(result.lines.map((line) => line.quantity), [
      15,
      70 / 6.5,
      1,
      20,
      20,
      20,
    ]);
    final costs = [8400, 5600, 600, 1400, 600, 1200];
    for (var i = 0; i < costs.length; i++) {
      expect(result.lines[i].cost, closeTo(costs[i], 0.000001));
    }
    expect(result.totalCost, closeTo(17800, 0.000001));
    expect(result.steel14Bars, 70);
    expect(formatNumber(result.lines[1].quantity), '10.77');
    expect(formatNumber(result.lines[1].cost), '5,600');
    expect(formatNumber(result.totalCost), '17,800');
    // 1.2 × 1.2 × 0.5 = 0.72; the stored 0.75 drives calculations.
    expect(result.lines.first.quantity, isNot(14.4));
  });

  test('custom constants and conversion factors produce 9580', () {
    final model = FoundationModel.builtIn.copyWith(
      id: 'custom',
      name: 'مخصص',
      concretePerFoundation: 1,
      steel14BarsPerFoundation: 2,
      steel14BarsPerQuintal: 5,
      steel8BarsPerFoundation: 0.5,
      steel8BarsPerQuintal: 10,
    );
    final result = calculate(
      model,
      const CalculatorInputs(count: 10, prices: Prices.defaults),
    );
    expect(result.lines.map((line) => line.cost), [
      5600,
      2080,
      300,
      700,
      300,
      600,
    ]);
    expect(result.totalCost, 9580);
  });

  test('zero quantities and prices allowed but zero conversion rejected', () {
    final model = FoundationModel.builtIn.copyWith(
      concretePerFoundation: 0,
      steel14BarsPerFoundation: 0,
      steel8BarsPerFoundation: 0,
    );
    final prices = Prices.defaults.copyWith(
      carpenter: 0,
      steelWorker: 0,
      casting: 0,
    );
    expect(
      calculate(model, CalculatorInputs(count: 1, prices: prices)).totalCost,
      0,
    );
    expect(
      () => calculate(
        model.copyWith(steel14BarsPerQuintal: 0),
        CalculatorInputs.defaults,
      ),
      throwsArgumentError,
    );
    expect(
      () => calculate(
        model.copyWith(steel8BarsPerQuintal: 0),
        CalculatorInputs.defaults,
      ),
      throwsArgumentError,
    );
  });

  test(
    'invalid dimensions, negative values, nonfinite and overflow rejected',
    () {
      for (final value in [-1.0, double.nan, double.infinity]) {
        expect(
          FoundationModel.builtIn
              .copyWith(concretePerFoundation: value)
              .isValid,
          isFalse,
        );
        expect(Prices.defaults.copyWith(concrete: value).isValid, isFalse);
      }
      expect(FoundationModel.builtIn.copyWith(length: 0).isValid, isFalse);
      expect(
        () => calculate(
          FoundationModel.builtIn,
          const CalculatorInputs(count: 0, prices: Prices.defaults),
        ),
        throwsArgumentError,
      );
      expect(
        () => calculate(
          FoundationModel.builtIn.copyWith(concretePerFoundation: 1e308),
          CalculatorInputs.defaults,
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'Arabic and Persian input, decimals and temporarily incomplete fields',
    () {
      expect(parseDecimal('3.5'), 3.5);
      expect(parseDecimal('٣٫٥'), 3.5);
      expect(parseDecimal('۳٫۵'), 3.5);
      expect(parsePositiveCount('٢٠'), 20);
      expect(parsePositiveCount('20.5'), isNull);
      expect(parsePositiveCount('20.0'), isNull);
      expect(parsePositiveCount('0'), isNull);
      expect(parsePositiveCount('9007199254740992'), isNull);
      expect(parseDecimal('0'), 0);
      expect(parseDecimal('3.'), 3);
      for (final value in [
        '',
        ' ',
        '.',
        '٫',
        '-1',
        'NaN',
        'Infinity',
        '1e9',
        '1,000',
      ]) {
        expect(parseDecimal(value), isNull, reason: value);
      }
    },
  );

  test('number format suppresses unnecessary zeros and groups results', () {
    expect(formatNumber(3.5), '3.5');
    expect(formatNumber(0), '0');
    expect(formatNumber(1234567.891), '1,234,567.89');
    expect(formatNumber(double.infinity), '—');
    expect(formatNumber(1e21), '1,000,000,000,000,000,000,000');
    expect(parseDecimal(inputNumber(1e30)), 1e30);
    expect(parseDecimal(inputNumber(1e-8)), 1e-8);
  });

  test(
    'selection retains calculator inputs and editing preserves identity',
    () {
      final initial = AppData(
        inputs: CalculatorInputs(
          count: 13,
          prices: Prices.defaults.copyWith(concrete: 42),
        ),
      );
      final custom = FoundationModel.builtIn.copyWith(
        id: 'custom',
        name: 'نموذج 2',
      );
      final added = initial.upsertModel(custom);
      expect(added.selectedModelId, 'custom');
      expect(added.inputs.count, 13);
      expect(added.inputs.prices.concrete, 42);
      final switched = added.selectModel(FoundationModel.builtIn.id);
      expect(identical(switched.inputs, added.inputs), isTrue);
      final edited = added.upsertModel(
        custom.copyWith(concretePerFoundation: 2),
      );
      expect(edited.customModels, hasLength(1));
      expect(edited.customModels.single.id, 'custom');
      expect(edited.customModels.single.concretePerFoundation, 2);
      expect(added.customModels.single.concretePerFoundation, 0.75);
      expect(
        () => added.upsertModel(FoundationModel.builtIn),
        throwsArgumentError,
      );
    },
  );
}
