import 'package:flutter/material.dart';

import '../services/pdf_file_actions.dart';

/// The ready dialog gives browsers a fresh user gesture after async generation.
class PdfExportDialog extends StatefulWidget {
  const PdfExportDialog({
    super.key,
    required this.file,
    required this.filename,
  });

  final PdfFileActions file;
  final String filename;

  @override
  State<PdfExportDialog> createState() => _PdfExportDialogState();
}

class _PdfExportDialogState extends State<PdfExportDialog> {
  bool _sharing = false;
  bool _shareFailed = false;
  String? _error;

  Future<void> _share() async {
    setState(() {
      _sharing = true;
      _error = null;
    });
    try {
      final started = await widget.file.share();
      if (!mounted) return;
      if (started) {
        Navigator.of(context).pop();
      } else {
        setState(() => _sharing = false);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _sharing = false;
          _shareFailed = true;
          _error = 'تعذر فتح المشاركة في هذا المتصفح. يمكنك تنزيل الملف.';
        });
      }
    }
  }

  void _download() {
    try {
      widget.file.download();
      Navigator.of(context).pop();
    } catch (_) {
      setState(() => _error = 'تعذر بدء التنزيل. حاول مرة أخرى.');
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_sharing,
    child: AlertDialog(
      title: const Text('التقرير جاهز'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.file.canShare
                  ? 'اختر تنزيل ملف PDF أو مشاركته.'
                  : 'يمكنك الآن تنزيل ملف PDF.',
            ),
            const SizedBox(height: 12),
            Text(
              widget.filename,
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontSize: 12),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sharing ? null : () => Navigator.of(context).pop(),
          child: const Text('إغلاق'),
        ),
        OutlinedButton.icon(
          key: const ValueKey('download_pdf'),
          onPressed: _sharing ? null : _download,
          icon: const Icon(Icons.download_rounded),
          label: const Text('تنزيل PDF'),
        ),
        if (widget.file.canShare && !_shareFailed)
          FilledButton.icon(
            key: const ValueKey('browser_share_pdf'),
            onPressed: _sharing ? null : _share,
            icon: _sharing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.ios_share_rounded),
            label: const Text('مشاركة PDF'),
          ),
      ],
    ),
  );
}
