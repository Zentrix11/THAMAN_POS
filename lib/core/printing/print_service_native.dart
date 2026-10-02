import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'print_document.dart';

const bool providesDocumentPreview = false;

String _cleanPrintText(String value) => value
    .replaceAll('\u0000', '')
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n');

bool _isGrandTotalLabel(String label) {
  final value = label.trim().toLowerCase();
  return value == 'الإجمالي' ||
      value == 'المجموع' ||
      value == 'total' ||
      value == 'grand total';
}

Future<bool> printDocument(PrintDocument document) async {
  try {
    // Arabic printing is rendered with Flutter's own text engine so it remains
    // fully offline-safe and does not depend on downloading a Google font at
    // print time. English reports remain vector/searchable PDFs.
    final Uint8List bytes = document.isArabic
        ? await _buildArabicRasterPdf(document)
        : await _buildPdf(document);
    return await Printing.layoutPdf(onLayout: (_) async => bytes);
  } catch (_) {
    return false;
  }
}

Future<Uint8List> _buildPdf(PrintDocument d) async {
  final pdf = pw.Document(
    title: d.title,
    author: 'THAMAN POS',
  );

  final pw.Font regular = pw.Font.helvetica();
  final pw.Font bold = pw.Font.helveticaBold();

  pw.MemoryImage? logo;
  try {
    final asset = await rootBundle.load('assets/thaman-logo.png');
    logo = pw.MemoryImage(asset.buffer.asUint8List());
  } catch (_) {
    // Printing remains usable even if the optional brand image cannot load.
  }

  final theme = pw.ThemeData.withFont(base: regular, bold: bold);
  final direction =
      d.isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr;
  final startAlign =
      d.isArabic ? pw.TextAlign.right : pw.TextAlign.left;
  final endAlign = d.isArabic ? pw.TextAlign.left : pw.TextAlign.right;
  final startCross = d.isArabic
      ? pw.CrossAxisAlignment.end
      : pw.CrossAxisAlignment.start;

  final bodyColor = PdfColor(0.090, 0.137, 0.114);
  final primary = PdfColor(0.059, 0.294, 0.263);
  final accent = PdfColor(0.847, 0.420, 0.196);
  final border = PdfColor(0.863, 0.886, 0.875);
  final muted = PdfColor(0.412, 0.451, 0.435);
  final alt = PdfColor(0.969, 0.976, 0.973);

  final columnCount = d.headers.isEmpty ? 1 : d.headers.length;
  final landscape = columnCount >= 7;
  final pageFormat = landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;
  final headerSize = columnCount >= 11
      ? 5.4
      : columnCount >= 8
          ? 6.0
          : columnCount >= 6
              ? 6.8
              : 8.2;
  final cellSize = columnCount >= 11
      ? 4.9
      : columnCount >= 8
          ? 5.5
          : columnCount >= 6
              ? 6.2
              : 7.6;

  pw.Widget text(
    String value, {
    double? size,
    bool boldText = false,
    PdfColor? color,
    pw.TextAlign? align,
  }) {
    return pw.Text(
      _cleanPrintText(value),
      textDirection: direction,
      textAlign: align ?? startAlign,
      style: pw.TextStyle(
        fontSize: size ?? 8,
        font: boldText ? bold : regular,
        fontWeight: boldText ? pw.FontWeight.bold : pw.FontWeight.normal,
        color: color ?? bodyColor,
      ),
    );
  }

  List<String> normalizedRow(List<String> values) {
    if (values.length == columnCount) return values;
    if (values.length > columnCount) return values.take(columnCount).toList();
    return <String>[...values, ...List<String>.filled(columnCount - values.length, '')];
  }

  pw.TableRow tableRow(
    List<String> rawValues, {
    bool header = false,
    int index = 0,
  }) {
    final values = normalizedRow(rawValues);
    return pw.TableRow(
      decoration: pw.BoxDecoration(
        color: header
            ? primary
            : (index.isEven ? PdfColors.white : alt),
      ),
      children: values
          .map(
            (value) => pw.Container(
              padding: pw.EdgeInsets.symmetric(
                horizontal: columnCount >= 8 ? 2.5 : 4,
                vertical: columnCount >= 8 ? 4 : 5,
              ),
              alignment: pw.Alignment.center,
              child: text(
                value,
                size: header ? headerSize : cellSize,
                boldText: header,
                color: header ? PdfColors.white : bodyColor,
                align: pw.TextAlign.center,
              ),
            ),
          )
          .toList(),
    );
  }

  final metaWidth = landscape ? 350.0 : 245.0;
  final summaryWidth = landscape ? 350.0 : 245.0;
  final columnWidths = <int, pw.TableColumnWidth>{
    if (columnCount > 0) 0: pw.FlexColumnWidth(columnCount <= 6 ? 2.2 : 1.35),
    for (var i = 1; i < columnCount; i++) i: const pw.FlexColumnWidth(1),
  };

  pdf.addPage(
    pw.MultiPage(
      pageFormat: pageFormat,
      margin: const pw.EdgeInsets.all(28),
      theme: theme,
      textDirection: direction,
      maxPages: 200,
      footer: (context) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 8),
        decoration: pw.BoxDecoration(
          border: pw.Border(
            top: pw.BorderSide(color: border, width: .6),
          ),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            text(
              d.footer.isEmpty ? 'THAMAN POS' : d.footer,
              size: 6.5,
              color: muted,
            ),
            text(
              '${context.pageNumber} / ${context.pagesCount}',
              size: 6.5,
              color: muted,
              align: endAlign,
            ),
          ],
        ),
      ),
      build: (context) => <pw.Widget>[
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: <pw.Widget>[
            if (logo != null)
              pw.Container(
                width: 72,
                height: 48,
                child: pw.Image(logo!, fit: pw.BoxFit.contain),
              ),
            if (logo != null) pw.SizedBox(width: 12),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: startCross,
                children: <pw.Widget>[
                  text(d.title, size: 16, boldText: true, color: primary),
                  if (d.subtitle.isNotEmpty) pw.SizedBox(height: 3),
                  if (d.subtitle.isNotEmpty)
                    text(d.subtitle, size: 8, color: muted),
                  pw.SizedBox(height: 3),
                  text('THAMAN POS', size: 7, boldText: true, color: accent),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Container(height: 2, color: primary),
        if (d.metadata.isNotEmpty) ...<pw.Widget>[
          pw.SizedBox(height: 10),
          pw.Wrap(
            spacing: 10,
            runSpacing: 6,
            children: d.metadata.entries
                .map(
                  (entry) => pw.Container(
                    width: metaWidth,
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                    decoration: pw.BoxDecoration(
                      color: alt,
                      border: pw.Border.all(color: border, width: .5),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                    ),
                    child: pw.Row(
                      children: <pw.Widget>[
                        pw.Expanded(
                          child: text(entry.key, size: 7, color: muted),
                        ),
                        pw.SizedBox(width: 8),
                        pw.Expanded(
                          child: text(
                            entry.value,
                            size: 7,
                            boldText: true,
                            align: endAlign,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ],
        pw.SizedBox(height: 12),
        if (d.headers.isEmpty)
          text(d.text('لا توجد بيانات للطباعة.', 'No printable data.'), size: 9)
        else
          pw.Table(
            border: pw.TableBorder.all(color: border, width: .5),
            columnWidths: columnWidths,
            defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
            children: <pw.TableRow>[
              tableRow(d.headers, header: true),
              for (var i = 0; i < d.rows.length; i++)
                tableRow(d.rows[i], index: i),
            ],
          ),
        if (d.summary.isNotEmpty) ...<pw.Widget>[
          pw.SizedBox(height: 12),
          pw.Wrap(
            spacing: 10,
            runSpacing: 6,
            children: d.summary.entries
                .map((entry) {
                  final total = _isGrandTotalLabel(entry.key);
                  return pw.Container(
                    width: summaryWidth,
                    padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 8),
                    decoration: pw.BoxDecoration(
                      color: total ? primary : PdfColors.white,
                      border: pw.Border.all(color: total ? primary : border, width: .6),
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(4),
                      ),
                    ),
                    child: pw.Row(
                      children: <pw.Widget>[
                        pw.Expanded(
                          child: text(
                            entry.key,
                            size: 7,
                            boldText: total,
                            color: total ? PdfColors.white : muted,
                          ),
                        ),
                        pw.SizedBox(width: 8),
                        pw.Expanded(
                          child: text(
                            entry.value,
                            size: total ? 8.5 : 7.5,
                            boldText: true,
                            color: total ? PdfColors.white : primary,
                            align: endAlign,
                          ),
                        ),
                      ],
                    ),
                  );
                })
                .toList(),
          ),
        ],
        if (d.notes.isNotEmpty) ...<pw.Widget>[
          pw.SizedBox(height: 12),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: PdfColor(1.0, 0.985, 0.965),
              border: pw.Border.all(color: PdfColor(0.94, 0.85, 0.78), width: .6),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Column(
              crossAxisAlignment: startCross,
              children: <pw.Widget>[
                text(
                  d.text('ملاحظات', 'Notes'),
                  size: 8,
                  boldText: true,
                  color: primary,
                ),
                pw.SizedBox(height: 4),
                for (final note in d.notes) text(note, size: 7),
              ],
            ),
          ),
        ],
      ],
    ),
  );

  return pdf.save();
}

Future<Uint8List> _buildArabicRasterPdf(PrintDocument d) async {
  final landscape = d.headers.length >= 7;
  final pageFormat = landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;
  final pixelWidth = landscape ? 1754 : 1240;
  final pixelHeight = landscape ? 1240 : 1754;
  final pages = <Uint8List>[];

  ui.Image? logo;
  try {
    final data = await rootBundle.load('assets/thaman-logo.png');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    logo = (await codec.getNextFrame()).image;
  } catch (_) {
    logo = null;
  }

  const margin = 64.0;
  const footerHeight = 54.0;
  final rowHeight = d.headers.length >= 11
      ? 42.0
      : d.headers.length >= 8
          ? 46.0
          : 52.0;
  const tableHeaderHeight = 50.0;
  final summaryHeight = d.summary.isEmpty
      ? 0.0
      : 40.0 + ((d.summary.length + 1) ~/ 2) * 56.0;
  final notesHeight = d.notes.isEmpty ? 0.0 : 50.0 + d.notes.length * 42.0;
  final endY = pixelHeight - margin - footerHeight;

  var rowIndex = 0;
  var pageNumber = 1;
  var firstPage = true;
  var finishContent = false;

  while (!finishContent) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, pixelWidth.toDouble(), pixelHeight.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );

    var y = _drawRasterHeader(
      canvas,
      d,
      logo,
      pixelWidth.toDouble(),
      margin,
    );

    if (firstPage && d.metadata.isNotEmpty) {
      y = _drawRasterKeyValueGrid(
        canvas,
        d.metadata,
        startY: y + 18,
        width: pixelWidth.toDouble(),
        margin: margin,
        labelColor: const ui.Color(0xFF68736F),
        valueColor: const ui.Color(0xFF17231F),
      );
    }

    y += firstPage ? 18 : 8;
    final columnCount = d.headers.isEmpty ? 1 : d.headers.length;
    final columnWidths = _rasterColumnWidths(
      pixelWidth.toDouble(),
      margin,
      columnCount,
    );

    if (d.headers.isNotEmpty) {
      _drawRasterTableRow(
        canvas,
        d.headers,
        y: y,
        rowHeight: tableHeaderHeight,
        columnWidths: columnWidths,
        margin: margin,
        header: true,
      );
      y += tableHeaderHeight;
    }

    if (d.rows.isEmpty && firstPage) {
      _drawRasterText(
        canvas,
        d.text('لا توجد بيانات للطباعة.', 'No printable data.'),
        x: margin,
        y: y + 24,
        width: pixelWidth - margin * 2,
        fontSize: 24,
        color: const ui.Color(0xFF68736F),
        align: ui.TextAlign.right,
      );
      y += 80;
    } else {
      while (rowIndex < d.rows.length) {
        final remainingRows = d.rows.length - rowIndex;
        final reserveForLast = remainingRows == 1
            ? summaryHeight + notesHeight + 30
            : 0.0;
        if (y + rowHeight + reserveForLast > endY) break;
        _drawRasterTableRow(
          canvas,
          d.rows[rowIndex],
          y: y,
          rowHeight: rowHeight,
          columnWidths: columnWidths,
          margin: margin,
          header: false,
          alternate: rowIndex.isOdd,
          expectedColumns: columnCount,
        );
        y += rowHeight;
        rowIndex++;
      }
    }

    final rowsDone = rowIndex >= d.rows.length;
    if (rowsDone) {
      final extrasNeed = summaryHeight + notesHeight + 24;
      if (extrasNeed == 24 || y + extrasNeed <= endY) {
        if (d.summary.isNotEmpty) {
          y = _drawRasterSectionTitle(canvas, d.text('الملخص', 'Summary'), y + 22, margin);
          y = _drawRasterKeyValueGrid(
            canvas,
            d.summary,
            startY: y + 8,
            width: pixelWidth.toDouble(),
            margin: margin,
            labelColor: const ui.Color(0xFF68736F),
            valueColor: const ui.Color(0xFF0F4B43),
            highlightGrandTotal: true,
          );
        }
        if (d.notes.isNotEmpty) {
          y = _drawRasterSectionTitle(canvas, d.text('ملاحظات', 'Notes'), y + 20, margin);
          for (final note in d.notes) {
            _drawRasterText(
              canvas,
              '• $note',
              x: margin,
              y: y + 8,
              width: pixelWidth - margin * 2,
              fontSize: 19,
              color: const ui.Color(0xFF17231F),
              align: ui.TextAlign.right,
              maxLines: 2,
            );
            y += 42;
          }
        }
        finishContent = true;
      } else if (y <= margin + 230) {
        // The extra section itself is taller than a clean page. Draw as much as
        // possible rather than looping forever.
        if (d.summary.isNotEmpty) {
          y = _drawRasterSectionTitle(canvas, d.text('الملخص', 'Summary'), y + 20, margin);
          _drawRasterKeyValueGrid(
            canvas,
            d.summary,
            startY: y + 8,
            width: pixelWidth.toDouble(),
            margin: margin,
            labelColor: const ui.Color(0xFF68736F),
            valueColor: const ui.Color(0xFF0F4B43),
            highlightGrandTotal: true,
          );
        }
        finishContent = true;
      }
    }

    _drawRasterFooter(
      canvas,
      d.footer.isEmpty ? 'THAMAN POS' : d.footer,
      pageNumber,
      pixelWidth.toDouble(),
      pixelHeight.toDouble(),
      margin,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(pixelWidth, pixelHeight);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) throw StateError('Unable to render print page');
    pages.add(byteData.buffer.asUint8List());
    pageNumber++;
    firstPage = false;

    if (pageNumber > 200) {
      throw StateError('Print document exceeded the 200-page safety limit');
    }
  }

  final pdf = pw.Document(title: d.title, author: 'THAMAN POS');
  for (final page in pages) {
    final pageImage = pw.MemoryImage(page);
    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(0),
        build: (_) => pw.Image(pageImage, fit: pw.BoxFit.fill),
      ),
    );
  }
  return pdf.save();
}

double _drawRasterHeader(
  ui.Canvas canvas,
  PrintDocument d,
  ui.Image? logo,
  double width,
  double margin,
) {
  const primary = ui.Color(0xFF0F4B43);
  const accent = ui.Color(0xFFD86B32);
  var textX = margin;
  var textWidth = width - margin * 2;
  if (logo != null) {
    const logoW = 190.0;
    const logoH = 105.0;
    final source = ui.Rect.fromLTWH(
      0,
      0,
      logo.width.toDouble(),
      logo.height.toDouble(),
    );
    final destination = ui.Rect.fromLTWH(width - margin - logoW, margin, logoW, logoH);
    canvas.drawImageRect(logo, source, destination, ui.Paint());
    textWidth -= logoW + 24;
  }
  _drawRasterText(
    canvas,
    d.title,
    x: textX,
    y: margin + 4,
    width: textWidth,
    fontSize: 34,
    color: primary,
    bold: true,
    align: ui.TextAlign.right,
  );
  if (d.subtitle.isNotEmpty) {
    _drawRasterText(
      canvas,
      d.subtitle,
      x: textX,
      y: margin + 56,
      width: textWidth,
      fontSize: 18,
      color: const ui.Color(0xFF68736F),
      align: ui.TextAlign.right,
      maxLines: 2,
    );
  }
  _drawRasterText(
    canvas,
    'THAMAN POS',
    x: textX,
    y: margin + 104,
    width: textWidth,
    fontSize: 16,
    color: accent,
    bold: true,
    align: ui.TextAlign.right,
  );
  canvas.drawRect(
    ui.Rect.fromLTWH(margin, margin + 142, width - margin * 2, 3),
    ui.Paint()..color = primary,
  );
  return margin + 150;
}

double _drawRasterSectionTitle(
  ui.Canvas canvas,
  String title,
  double y,
  double margin,
) {
  _drawRasterText(
    canvas,
    title,
    x: margin,
    y: y,
    width: 500,
    fontSize: 22,
    color: const ui.Color(0xFF0F4B43),
    bold: true,
    align: ui.TextAlign.right,
  );
  return y + 34;
}

double _drawRasterKeyValueGrid(
  ui.Canvas canvas,
  Map<String, String> values, {
  required double startY,
  required double width,
  required double margin,
  required ui.Color labelColor,
  required ui.Color valueColor,
  bool highlightGrandTotal = false,
}) {
  const gap = 20.0;
  final itemWidth = (width - margin * 2 - gap) / 2;
  var y = startY;
  var index = 0;
  for (final entry in values.entries) {
    final col = index % 2;
    final x = margin + (1 - col) * (itemWidth + gap);
    final grandTotal = highlightGrandTotal && _isGrandTotalLabel(entry.key);
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        ui.Rect.fromLTWH(x, y, itemWidth, 42),
        const ui.Radius.circular(7),
      ),
      ui.Paint()..color = grandTotal ? const ui.Color(0xFF0F4B43) : const ui.Color(0xFFF5F8F6),
    );
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        ui.Rect.fromLTWH(x, y, itemWidth, 42),
        const ui.Radius.circular(7),
      ),
      ui.Paint()
        ..color = grandTotal ? const ui.Color(0xFF0F4B43) : const ui.Color(0xFFDCE3DF)
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    _drawRasterText(
      canvas,
      entry.key,
      x: x + 10,
      y: y + 8,
      width: itemWidth * .46,
      fontSize: 15,
      color: grandTotal ? const ui.Color(0xFFFFFFFF) : labelColor,
      bold: grandTotal,
      align: ui.TextAlign.right,
      maxLines: 1,
    );
    _drawRasterText(
      canvas,
      entry.value,
      x: x + itemWidth * .48,
      y: y + 8,
      width: itemWidth * .49 - 10,
      fontSize: grandTotal ? 18 : 16,
      color: grandTotal ? const ui.Color(0xFFFFFFFF) : valueColor,
      bold: true,
      align: ui.TextAlign.left,
      maxLines: 1,
    );
    index++;
    if (index.isEven) y += 50;
  }
  if (index.isOdd) y += 50;
  return y;
}

List<double> _rasterColumnWidths(double pageWidth, double margin, int columns) {
  final available = pageWidth - margin * 2;
  if (columns <= 0) return const <double>[];
  final firstWeight = columns <= 6 ? 2.2 : 1.35;
  final totalWeight = firstWeight + (columns - 1);
  final unit = available / totalWeight;
  return <double>[
    unit * firstWeight,
    for (var i = 1; i < columns; i++) unit,
  ];
}

void _drawRasterTableRow(
  ui.Canvas canvas,
  List<String> rawValues, {
  required double y,
  required double rowHeight,
  required List<double> columnWidths,
  required double margin,
  required bool header,
  bool alternate = false,
  int? expectedColumns,
}) {
  final columns = expectedColumns ?? rawValues.length;
  final values = rawValues.length >= columns
      ? rawValues.take(columns).toList()
      : <String>[...rawValues, ...List<String>.filled(columns - rawValues.length, '')];
  final background = header
      ? const ui.Color(0xFF0F4B43)
      : alternate
          ? const ui.Color(0xFFF7F9F8)
          : const ui.Color(0xFFFFFFFF);
  final border = ui.Paint()
    ..color = const ui.Color(0xFFDCE3DF)
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = 1;
  final fill = ui.Paint()..color = background;
  final fontSize = columns >= 11
      ? 12.0
      : columns >= 8
          ? 14.0
          : columns >= 6
              ? 16.0
              : 18.0;
  for (var i = 0; i < columns; i++) {
    final cellWidth = columnWidths[i];
    final x = margin + columnWidths.skip(i + 1).fold<double>(0, (sum, value) => sum + value);
    final rect = ui.Rect.fromLTWH(x, y, cellWidth, rowHeight);
    canvas.drawRect(rect, fill);
    canvas.drawRect(rect, border);
    _drawRasterText(
      canvas,
      values[i],
      x: x + 6,
      y: y + 8,
      width: cellWidth - 12,
      fontSize: fontSize,
      color: header ? const ui.Color(0xFFFFFFFF) : const ui.Color(0xFF17231F),
      bold: header,
      align: ui.TextAlign.center,
      maxLines: 2,
    );
  }
}

void _drawRasterFooter(
  ui.Canvas canvas,
  String footer,
  int page,
  double width,
  double height,
  double margin,
) {
  final y = height - margin - 34;
  canvas.drawRect(
    ui.Rect.fromLTWH(margin, y - 12, width - margin * 2, 1),
    ui.Paint()..color = const ui.Color(0xFFDCE3DF),
  );
  _drawRasterText(
    canvas,
    footer,
    x: margin,
    y: y,
    width: width - margin * 2 - 160,
    fontSize: 13,
    color: const ui.Color(0xFF7A8581),
    align: ui.TextAlign.right,
    maxLines: 1,
  );
  _drawRasterText(
    canvas,
    '$page',
    x: width - margin - 100,
    y: y,
    width: 100,
    fontSize: 13,
    color: const ui.Color(0xFF7A8581),
    align: ui.TextAlign.left,
    maxLines: 1,
  );
}

double _drawRasterText(
  ui.Canvas canvas,
  String text, {
  required double x,
  required double y,
  required double width,
  required double fontSize,
  required ui.Color color,
  required ui.TextAlign align,
  bool bold = false,
  int maxLines = 1,
}) {
  final builder = ui.ParagraphBuilder(
    ui.ParagraphStyle(
      textDirection: ui.TextDirection.rtl,
      textAlign: align,
      maxLines: maxLines,
      ellipsis: '…',
    ),
  )..pushStyle(
      ui.TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: bold ? ui.FontWeight.w700 : ui.FontWeight.w400,
      ),
    );
  builder.addText(_cleanPrintText(text));
  final paragraph = builder.build();
  paragraph.layout(ui.ParagraphConstraints(width: width));
  canvas.drawParagraph(paragraph, ui.Offset(x, y));
  return paragraph.height;
}

