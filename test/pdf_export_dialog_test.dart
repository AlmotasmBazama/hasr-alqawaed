import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hasr_alqawaed/services/pdf_file_actions.dart';
import 'package:hasr_alqawaed/ui/pdf_export_dialog.dart';

class _FileActions implements PdfFileActions {
  _FileActions({this.canShare = false});

  @override
  final bool canShare;
  bool failDownload = false;
  int downloads = 0;
  final shareResult = Completer<bool>();

  @override
  void download() {
    if (failDownload) throw StateError('Browser refused download');
    downloads++;
  }

  @override
  Future<bool> share() => shareResult.future;
}

Future<void> _openDialog(WidgetTester tester, _FileActions file) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => PdfExportDialog(
                file: file,
                filename: 'hasr_alqawaed_20261108_1230.pdf',
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'unsupported file sharing provides a real explicit download action',
    (tester) async {
      final file = _FileActions();
      await _openDialog(tester, file);
      expect(find.byKey(const ValueKey('browser_share_pdf')), findsNothing);
      expect(file.downloads, 0);
      await tester.tap(find.byKey(const ValueKey('download_pdf')));
      await tester.pumpAndSettle();
      expect(file.downloads, 1);
      expect(find.byType(PdfExportDialog), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets(
    'cancelled native browser sharing keeps download available without error',
    (tester) async {
      final file = _FileActions(canShare: true);
      await _openDialog(tester, file);
      await tester.tap(find.byKey(const ValueKey('browser_share_pdf')));
      await tester.pump();
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const ValueKey('download_pdf')))
            .onPressed,
        isNull,
      );
      file.shareResult.complete(false);
      await tester.pumpAndSettle();
      expect(find.byType(PdfExportDialog), findsOneWidget);
      expect(find.textContaining('تعذر'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('download_pdf')));
      await tester.pumpAndSettle();
      expect(file.downloads, 1);
    },
  );

  testWidgets('sharing rejection exposes download fallback', (tester) async {
    final file = _FileActions(canShare: true);
    await _openDialog(tester, file);
    await tester.tap(find.byKey(const ValueKey('browser_share_pdf')));
    await tester.pump();
    file.shareResult.completeError(StateError('Permission denied'));
    await tester.pumpAndSettle();
    expect(find.textContaining('يمكنك تنزيل الملف'), findsOneWidget);
    expect(find.byKey(const ValueKey('browser_share_pdf')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('download_pdf')));
    await tester.pumpAndSettle();
    expect(file.downloads, 1);
  });

  testWidgets('failed download stays open and does not claim success', (
    tester,
  ) async {
    final file = _FileActions()..failDownload = true;
    await _openDialog(tester, file);
    await tester.tap(find.byKey(const ValueKey('download_pdf')));
    await tester.pumpAndSettle();
    expect(file.downloads, 0);
    expect(find.byType(PdfExportDialog), findsOneWidget);
    expect(find.text('تعذر بدء التنزيل. حاول مرة أخرى.'), findsOneWidget);
  });
}
