import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'field_help.dart';

const sharedPriceHelp =
    'تخص هذه الأسعار المشروع الحالي، وتُستخدم في السطور التي تعتمد السعر المشترك.';
const overridePriceHelp =
    'هذا السعر يخص هذا السطر فقط. يمكنك إلغاء التخصيص لاستخدام السعر المشترك.';
const invalidPriceMessage = 'أدخل قيمة رقمية غير سالبة.';

String unitPriceHelp(String? materialId) => switch (materialId) {
  'steel14' || 'steel8' || 'steel6' =>
    'يحوّل التطبيق كمية الحديد حسب معاملات النموذج المختار. أدخل السعر للوحدة الموضحة بجوار الحقل.',
  _ => 'أدخل سعر وحدة واحدة وفق الوحدة الموضحة بجوار الحقل.',
};

/// The summary precedes the ledger on a phone and sits alongside it on a desk.
class FinanceWorkspace extends StatelessWidget {
  const FinanceWorkspace({
    super.key,
    required this.summary,
    required this.ledger,
  });

  final Widget summary;
  final Widget ledger;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      if (bounds.maxWidth < 800 ||
          MediaQuery.textScalerOf(context).scale(1) > 1.4) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [summary, const SizedBox(height: 16), ledger],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(flex: 4, child: summary),
          const SizedBox(width: 24),
          Flexible(flex: 6, child: ledger),
        ],
      );
    },
  );
}

class FinanceProjectHeading extends StatelessWidget {
  const FinanceProjectHeading(this.name, {super.key, this.caption, this.help});

  final String name;
  final String? caption;
  final Widget? help;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(start: 2, bottom: 18),
    child: Row(
      children: [
        const FinanceIcon(Icons.folder_open_rounded),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 19,
                  color: forestInk,
                ),
              ),
              if (caption != null)
                Text(
                  caption!,
                  style: const TextStyle(color: secondaryText, fontSize: 13),
                ),
            ],
          ),
        ),
        ?help,
      ],
    ),
  );
}

class FinanceIcon extends StatelessWidget {
  const FinanceIcon(this.icon, {super.key, this.gold = false});

  final IconData icon;
  final bool gold;

  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      color: gold ? const Color(0xFFF7EEDC) : const Color(0xFFE8F1EC),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(
      icon,
      size: 21,
      color: gold ? const Color(0xFF835E22) : primaryGreen,
    ),
  );
}

class ProfitPanel extends StatelessWidget {
  const ProfitPanel({super.key, required this.input});
  final Widget input;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: const Color(0xFFEDF5EF),
      border: Border.all(color: const Color(0xFFCBDDD0)),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            FinanceIcon(Icons.percent_rounded),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'نسبة الربح على التكلفة',
                style: TextStyle(
                  color: forestInk,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
            FieldHelp(
              title: 'نسبة الربح على التكلفة',
              message:
                  'تُضاف هذه النسبة مرة واحدة إلى إجمالي تكلفة المواد والمصنعية والخدمات.',
              example:
                  'تكلفة 1,000 د.ل وربح 10% تعطي ربحًا 100 د.ل، وإجمالي عرض 1,100 د.ل.',
            ),
          ],
        ),
        const SizedBox(height: 13),
        input,
      ],
    ),
  );
}

class LedgerHeading extends StatelessWidget {
  const LedgerHeading(this.title, {super.key, required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: primaryGreen, size: 20),
      const SizedBox(width: 9),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: forestInk,
          ),
        ),
      ),
    ],
  );
}
