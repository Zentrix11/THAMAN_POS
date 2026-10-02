import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

import 'print_document.dart';

const bool providesDocumentPreview = true;

Future<bool> printDocument(PrintDocument document) async {
  // Open synchronously while still inside the user's click gesture. Waiting for
  // an asset before window.open can make browsers classify the popup as blocked.
  final popup = web.window.open('', '_blank');
  if (popup == null) return false;

  try {
    String logoData = '';
    try {
      final logo = await rootBundle.load('assets/thaman-logo.png');
      final data = base64Encode(logo.buffer.asUint8List());
      logoData = 'data:image/png;base64,$data';
    } catch (_) {
      // The report must still print if the optional logo asset is unavailable.
    }
    final html = _html(document, logoData);

    popup.document.open();
    popup.document.write(html.toJS);
    popup.document.close();
    popup.focus();
    return true;
  } catch (_) {
    try {
      popup.close();
    } catch (_) {}
    return false;
  }
}

String _clean(String value) => value
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

String _e(String value) => const HtmlEscape().convert(_clean(value));

List<String> _normalizedRow(List<String> row, int columns) {
  if (columns <= 0) return const <String>[];
  if (row.length == columns) return row.map(_clean).toList();
  if (row.length > columns) return row.take(columns).map(_clean).toList();
  return <String>[
    ...row.map(_clean),
    ...List<String>.filled(columns - row.length, ''),
  ];
}

String _html(PrintDocument d, String logo) {
  final lang = d.isArabic ? 'ar' : 'en';
  final dir = d.isArabic ? 'rtl' : 'ltr';
  final align = d.isArabic ? 'right' : 'left';
  final oppositeAlign = d.isArabic ? 'left' : 'right';
  final columnCount = d.headers.isEmpty ? 1 : d.headers.length;
  final landscape = columnCount >= 7;
  final pageSize = landscape ? 'A4 landscape' : 'A4 portrait';
  final tableFont = columnCount >= 11
      ? '8px'
      : columnCount >= 8
          ? '9px'
          : '10.5px';
  final logoTag = logo.isEmpty ? '' : '<img src="$logo" alt="THAMAN POS">';

  final metadata = d.metadata.entries
      .map(
        (entry) =>
            '<div class="meta"><span>${_e(entry.key)}</span><strong>${_e(entry.value)}</strong></div>',
      )
      .join();

  final headers = d.headers.map((h) => '<th>${_e(h)}</th>').join();
  final rows = d.rows
      .map((row) => _normalizedRow(row, columnCount))
      .map(
        (row) => '<tr>${row.map((cell) => '<td>${_e(cell)}</td>').join()}</tr>',
      )
      .join();

  final summary = d.summary.entries
      .map((entry) {
        final totalClass = _isGrandTotalLabel(entry.key) ? ' total' : '';
        return '<div class="summary$totalClass"><span>${_e(entry.key)}</span><strong>${_e(entry.value)}</strong></div>';
      })
      .join();

  final notes = d.notes.isEmpty
      ? ''
      : '<section class="notes"><h3>${_e(d.text('ملاحظات', 'Notes'))}</h3>${d.notes.map((n) => '<p>${_e(n)}</p>').join()}</section>';

  final noRows = d.rows.isEmpty
      ? '<tr><td colspan="$columnCount" class="empty">${_e(d.text('لا توجد بيانات للطباعة.', 'No printable data.'))}</td></tr>'
      : '';

  return '''
<!doctype html>
<html lang="$lang" dir="$dir">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${_e(d.title)}</title>
<style>
@page { size: $pageSize; margin: 12mm; }
* { box-sizing: border-box; }
html, body { min-height: 100%; }
body, table, th, td { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
body {
  font-family: Tahoma, Arial, "Segoe UI", sans-serif;
  color: #17231d;
  margin: 0;
  background: #f5f7f6;
  font-size: 12px;
  direction: $dir;
  text-align: $align;
}
.toolbar {
  position: sticky;
  top: 0;
  z-index: 10;
  background: #fff;
  border-bottom: 1px solid #d8dedb;
  padding: 10px 16px;
  display: flex;
  gap: 8px;
  align-items: center;
  box-shadow: 0 4px 14px rgba(18, 55, 42, .06);
}
.preview-label { color: #0f4b43; white-space: nowrap; font-size: 12px; }
.toolbar input {
  flex: 1;
  min-width: 160px;
  border: 1px solid #cfd8d3;
  border-radius: 9px;
  padding: 9px 11px;
  font-size: 12px;
  text-align: $align;
  direction: $dir;
}
.toolbar button {
  border: 0;
  border-radius: 9px;
  padding: 9px 14px;
  font-weight: 700;
  cursor: pointer;
}
.toolbar .print { background: #0f4b43; color: #fff; }
.toolbar .clear { background: #eef3f0; color: #0f4b43; }
.counter { font-size: 10px; color: #69736f; white-space: nowrap; }
.sheet {
  max-width: ${landscape ? '1320px' : '1000px'};
  margin: 18px auto;
  background: #fff;
  padding: 22px;
  border: 1px solid #e0e5e2;
  border-radius: 12px;
}
.head {
  display: flex;
  align-items: center;
  gap: 18px;
  border-bottom: 3px solid #0f4b43;
  padding-bottom: 14px;
}
.head img { width: 118px; max-height: 70px; object-fit: contain; }
.title { flex: 1; min-width: 0; }
.title h1 { margin: 0 0 5px; font-size: 22px; color: #0f4b43; overflow-wrap: anywhere; }
.title p { margin: 0; color: #66736d; font-size: 11px; overflow-wrap: anywhere; }
.brand { color: #d86b32; font-weight: 700; letter-spacing: .5px; }
.meta-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 7px 16px;
  margin: 16px 0;
}
.meta {
  display: flex;
  justify-content: space-between;
  gap: 12px;
  border: 1px solid #dce3df;
  border-radius: 8px;
  background: #f5f8f6;
  padding: 9px 11px;
  min-width: 0;
}
.meta span { color: #69736f; }
.meta strong { text-align: $oppositeAlign; overflow-wrap: anywhere; }
.table-wrap { width: 100%; overflow-x: auto; }
table {
  width: 100%;
  border-collapse: separate;
  border-spacing: 0;
  margin-top: 14px;
  font-size: $tableFont;
  table-layout: ${columnCount >= 8 ? 'fixed' : 'auto'};
}
th {
  background: #0f4b43;
  color: #fff;
  padding: 8px 6px;
  border: 1px solid #0f4b43;
  overflow-wrap: anywhere;
}
td {
  padding: 7px 6px;
  border: 1px solid #dce2df;
  text-align: center;
  vertical-align: top;
  overflow-wrap: anywhere;
}
th:first-child, td:first-child { width: ${columnCount <= 6 ? '34%' : '18%'}; }
thead th:first-child { border-start-start-radius: 8px; }
thead th:last-child { border-start-end-radius: 8px; }
tbody tr:nth-child(even) { background: #f7f9f8; }
tbody tr.hidden { display: none; }
td.empty { padding: 24px; color: #69736f; }
.summary-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 7px 14px;
  margin-top: 14px;
}
.summary {
  border: 1px solid #dce2df;
  border-radius: 7px;
  padding: 9px 11px;
  display: flex;
  justify-content: space-between;
  gap: 12px;
}
.summary strong { color: #0f4b43; text-align: $oppositeAlign; }
.summary.total { background: #0f4b43; border-color: #0f4b43; color: #fff; }
.summary.total span { color: rgba(255,255,255,.78); font-weight: 700; }
.summary.total strong { color: #fff; font-size: 13px; }
.notes {
  margin-top: 18px;
  border: 1px solid #efd9c9;
  background: #fffaf6;
  border-radius: 8px;
  padding: 12px;
}
.notes h3 { margin: 0 0 7px; color: #0f4b43; }
.notes p { margin: 5px 0; overflow-wrap: anywhere; }
.foot {
  margin-top: 22px;
  border-top: 1px solid #d8dedb;
  padding-top: 9px;
  display: flex;
  justify-content: space-between;
  gap: 14px;
  color: #727d78;
  font-size: 9px;
}
.signature {
  margin-top: 32px;
  display: flex;
  justify-content: space-between;
  gap: 50px;
}
.signature div {
  width: 42%;
  border-top: 1px solid #53615a;
  padding-top: 7px;
  text-align: center;
  color: #6b7771;
}
@media (max-width: 640px) {
  .sheet { margin: 0; border: 0; border-radius: 0; padding: 13px; }
  .toolbar { flex-wrap: wrap; }
  .toolbar input { width: 100%; flex-basis: 100%; }
  .meta-grid, .summary-grid { grid-template-columns: 1fr; }
  .head { align-items: flex-start; }
  .head img { width: 78px; }
  .title h1 { font-size: 18px; }
  .foot { flex-direction: column; }
}
@media print {
  .toolbar { display: none !important; }
  body { background: #fff; }
  .sheet { max-width: none; margin: 0; padding: 0; border: 0; border-radius: 0; }
  .table-wrap { overflow: visible; }
  tbody tr.hidden { display: table-row !important; }
  thead { display: table-header-group; }
  tr, .summary, .meta, .notes { break-inside: avoid; page-break-inside: avoid; }
}
</style>
</head>
<body>
<div class="toolbar">
  <strong class="preview-label">${_e(d.text('معاينة الطباعة', 'Print preview'))}</strong>
  <input id="search" type="search" placeholder="${_e(d.text('بحث داخل الكشف', 'Search this report'))}">
  <span class="counter" id="counter"></span>
  <button class="clear" id="clear" type="button">${_e(d.text('مسح', 'Clear'))}</button>
  <button class="print" id="print" type="button">${_e(d.text('طباعة', 'Print'))}</button>
</div>
<div class="sheet">
<header class="head">
  $logoTag
  <div class="title">
    <div class="brand">THAMAN POS</div>
    <h1>${_e(d.title)}</h1>
    <p>${_e(d.subtitle)}</p>
  </div>
</header>
<div class="meta-grid">$metadata</div>
<div class="table-wrap">
<table>
  <thead><tr>$headers</tr></thead>
  <tbody id="rows">$rows$noRows</tbody>
</table>
</div>
${summary.isEmpty ? '' : '<div class="summary-grid">$summary</div>'}
$notes
<div class="signature">
  <div>${_e(d.text('توقيع المسؤول', 'Authorized signature'))}</div>
  <div>${_e(d.text('الختم', 'Stamp'))}</div>
</div>
<footer class="foot">
  <span>${_e(d.text('THAMAN POS • تجارتك محسوبة.', 'THAMAN POS • Business, calculated.'))}</span>
  <span>${_e(d.footer)}</span>
</footer>
</div>
<script>
(function () {
  const input = document.getElementById('search');
  const rows = [...document.querySelectorAll('#rows tr')].filter(function (row) {
    return !row.querySelector('.empty');
  });
  const counter = document.getElementById('counter');
  function filter() {
    const q = (input.value || '').trim().toLocaleLowerCase('$lang');
    let visible = 0;
    rows.forEach(function (row) {
      const ok = !q || row.textContent.toLocaleLowerCase('$lang').includes(q);
      row.classList.toggle('hidden', !ok);
      if (ok) visible++;
    });
    counter.textContent = visible + ' / ' + rows.length;
  }
  input.addEventListener('input', filter);
  document.getElementById('clear').addEventListener('click', function () {
    input.value = '';
    filter();
    input.focus();
  });
  document.getElementById('print').addEventListener('click', function () {
    window.print();
  });
  filter();
})();
</script>
</body>
</html>
''';
}
