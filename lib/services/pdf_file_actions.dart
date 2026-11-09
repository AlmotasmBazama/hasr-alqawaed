/// A PDF already generated from a frozen calculation, ready for a user action.
abstract interface class PdfFileActions {
  bool get canShare;

  /// Returns false for normal user cancellation.
  Future<bool> share();

  /// Starts a browser download synchronously within the button gesture.
  void download();
}
