import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'pdf_file_actions.dart';

web.File _pdfFile(Uint8List bytes, String filename) => web.File(
  [bytes.toJS].toJS,
  filename,
  web.FilePropertyBag(type: 'application/pdf'),
);

bool _canShareFile(web.File file) {
  try {
    return web.window.isSecureContext &&
        web.window.navigator.hasProperty('share'.toJS).toDart &&
        web.window.navigator.canShare(web.ShareData(files: [file].toJS));
  } catch (_) {
    // canShare is absent in some browsers even when text sharing exists.
    return false;
  }
}

final bool _supportsFileSharing = _canShareFile(
  _pdfFile(Uint8List.fromList('%PDF-1.7\n'.codeUnits), 'report.pdf'),
);

bool get supportsBrowserFileSharing => _supportsFileSharing;

PdfFileActions prepareBrowserPdf(Uint8List bytes, String filename) {
  if (bytes.length < 5 || String.fromCharCodes(bytes.take(5)) != '%PDF-') {
    throw ArgumentError('The generated file is not a PDF');
  }
  return _BrowserPdfFile(_pdfFile(bytes, filename));
}

class _BrowserPdfFile implements PdfFileActions {
  _BrowserPdfFile(this._file);

  final web.File _file;

  @override
  bool get canShare => _canShareFile(_file);

  @override
  Future<bool> share() async {
    if (!canShare) {
      throw UnsupportedError('File sharing is not available');
    }
    try {
      // Deliberately call share before the first await, inside the fresh click.
      await web.window.navigator
          .share(web.ShareData(files: [_file].toJS, title: 'تقرير حصر القواعد'))
          .toDart;
      return true;
    } catch (error) {
      if (_isCancelled(error)) {
        return false;
      }
      rethrow;
    }
  }

  @override
  void download() {
    final body = web.document.body;
    if (body == null) {
      throw StateError('The browser document is not ready');
    }
    final url = web.URL.createObjectURL(_file);
    final link = web.HTMLAnchorElement()
      ..href = url
      ..download = _file.name
      ..style.display = 'none';
    try {
      body.append(link);
      // No window.open, tab creation or async work can consume activation here.
      link.click();
    } finally {
      link.remove();
      // Keep the blob alive long enough for Safari to start reading it.
      Timer(const Duration(minutes: 1), () => web.URL.revokeObjectURL(url));
    }
  }
}

bool _isCancelled(Object error) {
  try {
    return (error as JSObject).getProperty<JSString?>('name'.toJS)?.toDart ==
        'AbortError';
  } catch (_) {
    return false;
  }
}
