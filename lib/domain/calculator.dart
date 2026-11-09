import 'models.dart';

class CalculationLine {
  const CalculationLine({
    required this.id,
    required this.label,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
    required this.cost,
  });
  final String id;
  final String label;
  final String unit;
  final double quantity;
  final double unitPrice;
  final double cost;
}

class CalculationResult {
  CalculationResult({
    required List<CalculationLine> lines,
    required this.totalCost,
    required this.steel14Bars,
    required this.steel8Bars,
  }) : lines = List.unmodifiable(lines);
  final List<CalculationLine> lines;
  final double totalCost;
  final double steel14Bars;
  final double steel8Bars;
}

/// The only quantity/cost calculation path, shared by the display and PDF.
/// No rounding is performed here. Model dimensions are descriptive only.
CalculationResult calculate(FoundationModel model, CalculatorInputs inputs) {
  if (!model.isValid || !inputs.isValid) {
    throw ArgumentError('Invalid calculation inputs');
  }
  final count = inputs.count.toDouble();
  final prices = inputs.prices;
  final steel14Bars = count * model.steel14BarsPerFoundation;
  final steel8Bars = count * model.steel8BarsPerFoundation;
  CalculationLine line(
    String id,
    String label,
    String unit,
    double quantity,
    double price,
  ) => CalculationLine(
    id: id,
    label: label,
    unit: unit,
    quantity: quantity,
    unitPrice: price,
    cost: quantity * price,
  );
  final lines = [
    line(
      'concrete',
      'خرسانة مسلحة',
      'م³',
      count * model.concretePerFoundation,
      prices.concrete,
    ),
    line(
      'steel14',
      'حديد 14',
      'قنطار',
      steel14Bars / model.steel14BarsPerQuintal,
      prices.steel14,
    ),
    line(
      'steel8',
      'حديد 8',
      'قنطار',
      steel8Bars / model.steel8BarsPerQuintal,
      prices.steel8,
    ),
    line('carpenter', 'نجار', 'قاعدة', count, prices.carpenter),
    line('steelWorker', 'حداد', 'قاعدة', count, prices.steelWorker),
    line('casting', 'صب', 'قاعدة', count, prices.casting),
  ];
  final total = lines.fold<double>(0, (sum, line) => sum + line.cost);
  if (!steel14Bars.isFinite ||
      !steel8Bars.isFinite ||
      !total.isFinite ||
      lines.any((line) => !line.quantity.isFinite || !line.cost.isFinite)) {
    throw ArgumentError('Calculation exceeds supported numeric range');
  }
  return CalculationResult(
    lines: lines,
    totalCost: total,
    steel14Bars: steel14Bars,
    steel8Bars: steel8Bars,
  );
}
