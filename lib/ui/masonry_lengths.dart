import 'package:flutter/material.dart';

import '../project/models.dart';
import 'project_widgets.dart';

class LengthReview extends StatelessWidget {
  const LengthReview({super.key, required this.entry, required this.onAccept});
  final WorkEntry entry;
  final VoidCallback? onAccept;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF6E4),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Wrap(
      spacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'الطول المحفوظ من الحصر السابق ${measure(entry.quantity!)} م. اعتمده أو أدخل طولًا جديدًا.',
          style: const TextStyle(fontSize: 12, color: Color(0xFF694414)),
        ),
        TextButton(
          key: ValueKey('accept_length_${entry.kind.name}'),
          onPressed: onAccept,
          child: const Text('اعتماد الطول'),
        ),
      ],
    ),
  );
}
