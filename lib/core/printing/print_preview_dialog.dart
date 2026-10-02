import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'print_document.dart';

enum PrintPreviewAction { cancel, print }

Future<PrintPreviewAction> showThamanPrintPreview(
  BuildContext context,
  PrintDocument document,
) async {
  final result = await showDialog<PrintPreviewAction>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _PrintPreviewDialog(document: document),
  );
  return result ?? PrintPreviewAction.cancel;
}

class _PrintPreviewDialog extends StatelessWidget {
  const _PrintPreviewDialog({required this.document});

  final PrintDocument document;

  static const _primary = Color(0xFF0F4B43);
  static const _accent = Color(0xFFD86B32);
  static const _ink = Color(0xFF17231D);
  static const _muted = Color(0xFF68736F);
  static const _border = Color(0xFFDCE3DF);
  static const _soft = Color(0xFFF5F8F6);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = math.min(size.width - 24, 1120.0);
    final height = math.min(size.height - 24, 900.0);
    final isLandscape = document.headers.length >= 7;

    return Directionality(
      textDirection: document.isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Dialog(
        insetPadding: const EdgeInsets.all(12),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: SizedBox(
          width: width,
          height: height,
          child: Column(
            children: [
              _toolbar(context, isLandscape),
              Expanded(
                child: ColoredBox(
                  color: const Color(0xFFEFF3F1),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: size.width < 700 ? 10 : 24,
                      vertical: 20,
                    ),
                    child: Center(
                      child: Container(
                        width: isLandscape ? 1040 : 820,
                        constraints: const BoxConstraints(minHeight: 560),
                        padding: EdgeInsets.all(size.width < 700 ? 18 : 30),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _border),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x14000000),
                              blurRadius: 24,
                              offset: Offset(0, 10),
                            ),
                          ],
                        ),
                        child: _paper(),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolbar(BuildContext context, bool isLandscape) {
    final ar = document.isArabic;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _soft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.preview_outlined, color: _primary, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ar ? 'معاينة قبل الطباعة' : 'Print preview',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: _ink),
                ),
                const SizedBox(height: 2),
                Text(
                  '${isLandscape ? (ar ? 'A4 أفقي' : 'A4 landscape') : (ar ? 'A4 عمودي' : 'A4 portrait')} • ${document.rows.length} ${ar ? 'سطر' : 'rows'}',
                  style: const TextStyle(fontSize: 10, color: _muted),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(PrintPreviewAction.cancel),
            child: Text(ar ? 'إلغاء' : 'Cancel'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _primary),
            onPressed: () => Navigator.of(context).pop(PrintPreviewAction.print),
            icon: const Icon(Icons.print_outlined, size: 18),
            label: Text(ar ? 'متابعة للطباعة' : 'Continue to print'),
          ),
        ],
      ),
    );
  }

  Widget _paper() {
    final previewRows = document.rows.take(100).toList();
    final truncated = document.rows.length > previewRows.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(),
        if (document.metadata.isNotEmpty) ...[
          const SizedBox(height: 18),
          _metadata(),
        ],
        const SizedBox(height: 20),
        _table(previewRows),
        if (truncated) ...[
          const SizedBox(height: 8),
          Text(
            document.text(
              'المعاينة تعرض أول 100 سطر فقط، بينما الطباعة ستتضمن جميع البيانات.',
              'Preview shows the first 100 rows only; printing includes all rows.',
            ),
            style: const TextStyle(fontSize: 10, color: _muted, fontWeight: FontWeight.w700),
          ),
        ],
        if (document.summary.isNotEmpty) ...[
          const SizedBox(height: 18),
          _summary(),
        ],
        if (document.notes.isNotEmpty) ...[
          const SizedBox(height: 18),
          _notes(),
        ],
        const SizedBox(height: 26),
        _footer(),
      ],
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.only(bottom: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _primary, width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 105,
            height: 58,
            child: Image.asset(
              'assets/thaman-logo.png',
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'THAMAN POS',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: _accent, letterSpacing: .5),
                ),
                const SizedBox(height: 4),
                Text(
                  document.title,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: _primary, height: 1.15),
                ),
                if (document.subtitle.trim().isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(document.subtitle, style: const TextStyle(fontSize: 11, color: _muted)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metadata() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth < 620
            ? constraints.maxWidth
            : (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 10,
          children: document.metadata.entries.map((entry) {
            return Container(
              width: cardWidth,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _soft,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: _border),
              ),
              child: Row(
                children: [
                  Expanded(child: Text(entry.key, style: const TextStyle(fontSize: 10, color: _muted))),
                  const SizedBox(width: 10),
                  Flexible(child: Text(entry.value, textAlign: TextAlign.end, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: _ink))),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _table(List<List<String>> rows) {
    if (document.headers.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(color: _soft, borderRadius: BorderRadius.circular(10)),
        child: Text(
          document.text('لا توجد بيانات للطباعة.', 'No printable data.'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted, fontWeight: FontWeight.w700),
        ),
      );
    }

    final columns = document.headers.length;
    final tableWidth = math.max(720.0, 220.0 + (columns - 1) * (columns >= 8 ? 104.0 : 126.0));

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: tableWidth,
        child: Table(
          border: TableBorder.all(color: _border, width: .8),
          columnWidths: <int, TableColumnWidth>{
            0: const FlexColumnWidth(2.2),
            for (var i = 1; i < columns; i++) i: const FlexColumnWidth(1),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              decoration: const BoxDecoration(color: _primary),
              children: document.headers.map((value) => _cell(value, header: true)).toList(),
            ),
            if (rows.isEmpty)
              TableRow(
                children: [
                  _cell(document.text('لا توجد بيانات', 'No data')),
                  for (var i = 1; i < columns; i++) _cell(''),
                ],
              ),
            for (var index = 0; index < rows.length; index++)
              TableRow(
                decoration: BoxDecoration(color: index.isOdd ? const Color(0xFFF8FAF9) : Colors.white),
                children: _normalizedRow(rows[index], columns).map(_cell).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _cell(String value, {bool header = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      child: Text(
        value,
        textAlign: TextAlign.center,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: header ? 10 : 9.5,
          height: 1.25,
          fontWeight: header ? FontWeight.w900 : FontWeight.w600,
          color: header ? Colors.white : _ink,
        ),
      ),
    );
  }

  Widget _summary() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth < 620
            ? constraints.maxWidth
            : (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 10,
          children: document.summary.entries.map((entry) {
            final total = _isGrandTotal(entry.key);
            return Container(
              width: cardWidth,
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
              decoration: BoxDecoration(
                color: total ? _primary : Colors.white,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: total ? _primary : _border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.key,
                      style: TextStyle(fontSize: 10, color: total ? Colors.white70 : _muted, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      entry.value,
                      textAlign: TextAlign.end,
                      style: TextStyle(fontSize: total ? 12 : 11, color: total ? Colors.white : _primary, fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _notes() {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBF7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF0D8C8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(document.text('ملاحظات', 'Notes'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: _accent)),
          const SizedBox(height: 6),
          for (final note in document.notes)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text('• $note', style: const TextStyle(fontSize: 10, color: _ink, height: 1.4)),
            ),
        ],
      ),
    );
  }

  Widget _footer() {
    return Container(
      padding: const EdgeInsets.only(top: 10),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: _border))),
      child: Row(
        children: [
          Text(document.text('THAMAN POS • تجارتك محسوبة.', 'THAMAN POS • Business, calculated.'), style: const TextStyle(fontSize: 8.5, color: _muted, fontWeight: FontWeight.w700)),
          const Spacer(),
          Flexible(
            child: Text(document.footer, textAlign: TextAlign.end, style: const TextStyle(fontSize: 8.5, color: _muted)),
          ),
        ],
      ),
    );
  }

  List<String> _normalizedRow(List<String> values, int columns) {
    if (values.length == columns) return values;
    if (values.length > columns) return values.take(columns).toList();
    return <String>[...values, ...List<String>.filled(columns - values.length, '')];
  }

  bool _isGrandTotal(String label) {
    final normalized = label.trim().toLowerCase();
    return normalized == 'الإجمالي' ||
        normalized == 'المجموع' ||
        normalized == 'total' ||
        normalized == 'grand total';
  }
}
