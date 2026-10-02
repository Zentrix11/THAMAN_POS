import 'print_document.dart';

const bool providesDocumentPreview = false;

Future<bool> printDocument(PrintDocument document) async {
  // Native printer adapters are intentionally isolated here. The current
  // commercial web build prints through the browser's native print dialog.
  return false;
}
