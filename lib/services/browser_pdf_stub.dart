import 'dart:typed_data';

import 'pdf_file_actions.dart';

bool get supportsBrowserFileSharing => false;

PdfFileActions prepareBrowserPdf(Uint8List bytes, String filename) =>
    throw UnsupportedError('Browser PDF export is only available on the web');
