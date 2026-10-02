import '../navigation/app_navigator.dart';
import 'print_document.dart';
import 'print_preview_dialog.dart';
import 'print_service_stub.dart'
    if (dart.library.html) 'print_service_web.dart'
    if (dart.library.io) 'print_service_native.dart' as platform;

class ThamanPrintService {
  const ThamanPrintService._();

  /// Every print action goes through a preview first.
  ///
  /// Web already provides an exact HTML print preview in a dedicated window,
  /// so it opens that preview directly. Native platforms show THAMAN's in-app
  /// preview first, then continue to the operating system print dialog.
  static Future<bool> printDocument(PrintDocument document) async {
    if (platform.providesDocumentPreview) {
      return platform.printDocument(document);
    }

    final context = thamanNavigatorKey.currentContext;
    if (context != null) {
      final action = await showThamanPrintPreview(context, document);
      if (action != PrintPreviewAction.print) {
        // Cancelling a preview is a valid user action, not a print error.
        return true;
      }
    }

    return platform.printDocument(document);
  }
}
