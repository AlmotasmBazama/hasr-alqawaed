import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Contextual help is presentation only. It has no access to project state.
class FieldHelp extends StatelessWidget {
  const FieldHelp({
    super.key,
    required this.title,
    required this.message,
    this.example,
    this.semanticLabel,
  });

  final String title;
  final String message;
  final String? example;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => TextFieldTapRegion(
    child: IconButton(
      tooltip: semanticLabel ?? 'مساعدة حول $title',
      icon: const Icon(Icons.info_outline_rounded, size: 18),
      color: primaryGreen,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          scrollable: true,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),
          constraints: const BoxConstraints(maxWidth: 440),
          backgroundColor: Colors.white,
          title: Text(
            title,
            style: const TextStyle(
              color: forestInk,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(message, style: const TextStyle(fontSize: 15, height: 1.7)),
              if (example case final text?) ...[
                const SizedBox(height: 14),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: paper,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      text,
                      style: const TextStyle(color: forestInk, height: 1.65),
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('فهمت'),
            ),
          ],
        ),
      ),
    ),
  );
}
