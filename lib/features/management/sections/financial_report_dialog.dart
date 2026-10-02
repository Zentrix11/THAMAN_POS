import 'package:flutter/material.dart';
import '../../../core/time_format.dart';

import '../../../app/app_theme.dart';
import '../../../core/app_strings.dart';
import '../../../core/printing/print_service.dart';
import '../../../core/printing/print_templates.dart';
import '../../../data/app_data_store.dart';
import '../../../data/models.dart';

enum FinancialReportKind { inflows, outflows, customers, suppliers }

Future<void> showFinancialReportDialog(
  BuildContext context, {
  required AppStrings s,
  required FinancialReportKind kind,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => FinancialReportDialog(s: s, kind: kind),
  );
}

class FinancialReportDialog extends StatefulWidget {
  const FinancialReportDialog({super.key, required this.s, required this.kind});
  final AppStrings s;
  final FinancialReportKind kind;

  @override
  State<FinancialReportDialog> createState() => _FinancialReportDialogState();
}

class _FinancialReportDialogState extends State<FinancialReportDialog> {
  final search = TextEditingController();
  final minAmount = TextEditingController();
  final maxAmount = TextEditingController();
  DateTime? start;
  DateTime? end;
  String partyId = 'all';

  @override
  void dispose() {
    search.dispose();
    minAmount.dispose();
    maxAmount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = AppDataStore.instance;
    final s = widget.s;
    final rows = _filteredRows(store);
    final total = rows.fold<double>(0, (sum, row) => sum + row.amount);
    final parties = widget.kind == FinancialReportKind.customers
        ? store.customers.map((e) => MapEntry(e.id, '${e.name} • ${e.accountNumber}')).toList()
        : widget.kind == FinancialReportKind.suppliers
            ? store.suppliers.map((e) => MapEntry(e.id, '${e.name} • ${e.accountNumber}')).toList()
            : const <MapEntry<String, String>>[];

    return AlertDialog(
          scrollable: true,
      title: Row(
        children: [
          Expanded(child: Text(_title(s))),
          IconButton(
            tooltip: s.text('طباعة التقرير', 'Print report'),
            onPressed: rows.isEmpty ? null : () => _print(rows, total),
            icon: const Icon(Icons.print_outlined),
          ),
        ],
      ),
      content: SizedBox(
        width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 1120.0).toDouble(),
        height: MediaQuery.sizeOf(context).height * .78,
        child: Column(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final filters = <Widget>[
                  SizedBox(
                    width: constraints.maxWidth < 680 ? double.infinity : 260,
                    child: TextField(
                      controller: search,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded),
                        labelText: s.text('بحث داخل التقرير', 'Search inside report'),
                        hintText: s.text('اسم، رقم، مرجع، موظف...', 'Name, number, reference, employee...'),
                      ),
                    ),
                  ),
                  if (parties.isNotEmpty)
                    SizedBox(
                      width: constraints.maxWidth < 680 ? double.infinity : 250,
                      child: DropdownButtonFormField<String>(
                        value: partyId,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: widget.kind == FinancialReportKind.customers ? s.text('العميل', 'Customer') : s.text('المورد', 'Supplier')),
                        items: [
                          DropdownMenuItem(value: 'all', child: Text(s.text('الكل', 'All'))),
                          ...parties.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))),
                        ],
                        onChanged: (value) => setState(() => partyId = value ?? 'all'),
                      ),
                    ),
                  SizedBox(width: 132, child: TextField(controller: minAmount, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: s.text('من مبلغ', 'Min amount')))),
                  SizedBox(width: 132, child: TextField(controller: maxAmount, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: s.text('إلى مبلغ', 'Max amount')))),
                  OutlinedButton.icon(onPressed: () => _pickDate(true), icon: const Icon(Icons.calendar_month_outlined, size: 17), label: Text(start == null ? s.text('من تاريخ', 'From date') : _date(start!))),
                  OutlinedButton.icon(onPressed: () => _pickDate(false), icon: const Icon(Icons.event_available_outlined, size: 17), label: Text(end == null ? s.text('إلى تاريخ', 'To date') : _date(end!))),
                  if (start != null || end != null || partyId != 'all' || minAmount.text.isNotEmpty || maxAmount.text.isNotEmpty || search.text.isNotEmpty)
                    TextButton.icon(onPressed: _clearFilters, icon: const Icon(Icons.filter_alt_off_outlined, size: 17), label: Text(s.text('مسح التصفية', 'Clear filters'))),
                ];
                return Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: filters);
              },
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(13)),
              child: Wrap(
                spacing: 18,
                runSpacing: 6,
                children: [
                  Text('${s.text('عدد الحركات', 'Transactions')}: ${rows.length}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 9.5)),
                  Text('${s.text('الإجمالي', 'Total')}: ${total.toStringAsFixed(2)} ${store.settings.currency}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 9.5, color: AppColors.primary)),
                  Text(s.text('يمكن البحث والتصفية قبل الطباعة، ومعاينة الطباعة نصية وقابلة للبحث في المتصفح.', 'Search and filter before printing; the browser print preview remains text-searchable.'), style: const TextStyle(fontSize: 8.3, color: AppColors.muted)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: rows.isEmpty
                  ? Center(child: Text(s.text('لا توجد نتائج مطابقة.', 'No matching records.'), style: const TextStyle(color: AppColors.muted)))
                  : ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 7),
                      itemBuilder: (_, index) => _ReportRowCard(row: rows[index], currency: store.settings.currency, s: s),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s.text('إغلاق', 'Close'))),
        FilledButton.icon(onPressed: rows.isEmpty ? null : () => _print(rows, total), icon: const Icon(Icons.print_rounded, size: 17), label: Text(s.text('طباعة', 'Print'))),
      ],
    );
  }

  List<_ReportRow> _filteredRows(AppDataStore store) {
    final all = _buildRows(store);
    final q = search.text.trim().toLowerCase();
    final min = double.tryParse(minAmount.text.trim());
    final max = double.tryParse(maxAmount.text.trim());
    final startDay = start == null ? null : DateTime(start!.year, start!.month, start!.day);
    final endExclusive = end == null ? null : DateTime(end!.year, end!.month, end!.day).add(const Duration(days: 1));
    return all.where((row) {
      if (partyId != 'all' && row.partyId != partyId) return false;
      if (startDay != null && row.date.isBefore(startDay)) return false;
      if (endExclusive != null && !row.date.isBefore(endExclusive)) return false;
      final magnitude = row.amount.abs();
      if (min != null && magnitude < min) return false;
      if (max != null && magnitude > max) return false;
      if (q.isNotEmpty && !'${row.party} ${row.type} ${row.reference} ${row.actor} ${row.note}'.toLowerCase().contains(q)) return false;
      return true;
    }).toList()..sort((a, b) => b.date.compareTo(a.date));
  }

  List<_ReportRow> _buildRows(AppDataStore store) {
    final s = widget.s;
    final rows = <_ReportRow>[];
    if (widget.kind == FinancialReportKind.inflows) {
      for (final invoice in store.invoices.where((i) => !i.voided && i.receivedAtSale > 0)) {
        rows.add(_ReportRow(date: invoice.createdAt, partyId: invoice.customerId, party: invoice.customer, type: s.text('بيع مقبوض', 'Sale receipt'), reference: invoice.number, amount: invoice.receivedAtSale, actor: invoice.cashier, note: s.paymentMethod(invoice.paymentMethod)));
      }
      for (final payment in store.customerPayments) {
        rows.add(_ReportRow(date: payment.createdAt, partyId: payment.customerId, party: payment.customerName, type: s.text('تحصيل عميل', 'Customer collection'), reference: payment.id, amount: payment.amount, actor: payment.employeeName, note: '${s.paymentMethod(payment.method)}${payment.note.isEmpty ? '' : ' • ${payment.note}'}'));
      }
      for (final record in store.purchaseReturns.where((r) => r.cashRefund > 0.005)) {
        rows.add(_ReportRow(date: record.createdAt, partyId: record.supplierId, party: record.supplierName, type: s.text('مبلغ مستلم من مرتجع مورد', 'Supplier return payment'), reference: record.purchaseNumber, amount: record.cashRefund, actor: record.processedBy, note: '${s.text('المتفق', 'Agreed')}: ${record.agreedAmount.toStringAsFixed(2)} • ${s.text('الباقي', 'Remaining')}: ${record.remainingRefund.toStringAsFixed(2)}'));
      }
    } else if (widget.kind == FinancialReportKind.outflows) {
      for (final expense in store.expenses) {
        rows.add(_ReportRow(date: expense.createdAt, partyId: '', party: s.expenseCategory(expense.category), type: s.text('مصروف تشغيلي', 'Operating expense'), reference: expense.id, amount: expense.amount, actor: expense.employeeName, note: '${s.paymentMethod(expense.paymentMethod)} • ${expense.description}'));
      }
      for (final purchase in store.purchases.where((p) => p.amountPaid > 0)) {
        rows.add(_ReportRow(date: purchase.createdAt, partyId: purchase.supplierId, party: purchase.supplier, type: s.text('دفعة شراء أولية', 'Initial purchase payment'), reference: purchase.number, amount: purchase.amountPaid, actor: purchase.employeeName, note: s.paymentMethod(purchase.paymentMethod)));
      }
      for (final payment in store.supplierPayments) {
        rows.add(_ReportRow(date: payment.createdAt, partyId: payment.supplierId, party: payment.supplierName, type: s.text('دفعة مورد', 'Supplier payment'), reference: payment.purchaseNumber.isEmpty ? payment.id : payment.purchaseNumber, amount: payment.amount, actor: payment.employeeName, note: '${s.paymentMethod(payment.method)}${payment.note.isEmpty ? '' : ' • ${payment.note}'}'));
      }
      for (final record in store.returns.where((r) => r.refundAmount > 0)) {
        rows.add(_ReportRow(date: record.createdAt, partyId: '', party: record.invoiceNumber, type: s.text('رد مبلغ مرتجع', 'Return refund'), reference: record.invoiceNumber, amount: record.refundAmount, actor: record.processedBy, note: s.paymentMethod(record.refundMethod)));
      }
      for (final asset in store.assets.where((a) => a.purchasePrice > 0)) {
        rows.add(_ReportRow(date: asset.purchaseDate, partyId: '', party: asset.name, type: s.text('شراء أصل', 'Asset purchase'), reference: asset.id, amount: asset.purchasePrice, actor: s.text('الإدارة', 'Management'), note: asset.category));
      }
    } else if (widget.kind == FinancialReportKind.customers) {
      for (final invoice in store.invoices.where((i) => !i.voided && i.customerId.isNotEmpty)) {
        rows.add(_ReportRow(date: invoice.createdAt, partyId: invoice.customerId, party: invoice.customer, type: s.text('فاتورة', 'Invoice'), reference: invoice.number, amount: invoice.total, actor: invoice.cashier, note: '${s.text('مدفوع', 'Paid')} ${invoice.receivedAtSale.toStringAsFixed(2)} • ${s.text('متبقي', 'Due')} ${store.invoiceOutstanding(invoice.id).toStringAsFixed(2)}'));
      }
      for (final payment in store.customerPayments) {
        rows.add(_ReportRow(date: payment.createdAt, partyId: payment.customerId, party: payment.customerName, type: s.text('دفعة', 'Payment'), reference: payment.id, amount: -payment.amount, actor: payment.employeeName, note: s.paymentMethod(payment.method)));
      }
      for (final record in store.returns) {
        SaleInvoice? invoice;
        for (final candidate in store.invoices) {
          if (candidate.id == record.invoiceId) {
            invoice = candidate;
            break;
          }
        }
        if (invoice != null && invoice.customerId.isNotEmpty) {
          rows.add(_ReportRow(date: record.createdAt, partyId: invoice.customerId, party: invoice.customer, type: s.text('مرتجع', 'Return'), reference: record.invoiceNumber, amount: -record.total, actor: record.processedBy, note: record.reason));
        }
      }
    } else {
      for (final purchase in store.purchases.where((p) => p.supplierId.isNotEmpty)) {
        rows.add(_ReportRow(date: purchase.createdAt, partyId: purchase.supplierId, party: purchase.supplier, type: s.text('شراء', 'Purchase'), reference: purchase.number, amount: purchase.total, actor: purchase.employeeName, note: '${s.text('مدفوع', 'Paid')} ${purchase.amountPaid.toStringAsFixed(2)} • ${s.text('متبقي', 'Due')} ${store.purchaseOutstanding(purchase).toStringAsFixed(2)}'));
      }
      for (final payment in store.supplierPayments) {
        rows.add(_ReportRow(date: payment.createdAt, partyId: payment.supplierId, party: payment.supplierName, type: s.text('دفعة', 'Payment'), reference: payment.purchaseNumber.isEmpty ? payment.id : payment.purchaseNumber, amount: -payment.amount, actor: payment.employeeName, note: s.paymentMethod(payment.method)));
      }
      for (final record in store.purchaseReturns.where((r) => r.supplierId.isNotEmpty)) {
        rows.add(_ReportRow(date: record.createdAt, partyId: record.supplierId, party: record.supplierName, type: s.text('مرتجع شراء', 'Purchase return'), reference: record.purchaseNumber, amount: -record.agreedAmount, actor: record.processedBy, note: '${s.text('خصم دين', 'Debt reduction')}: ${record.payableReduction.toStringAsFixed(2)} • ${s.text('دفع الآن', 'Paid now')}: ${record.cashRefund.toStringAsFixed(2)} • ${s.text('باقي لنا', 'Remaining to us')}: ${record.remainingRefund.toStringAsFixed(2)}'));
      }
    }
    return rows;
  }

  Future<void> _pickDate(bool from) async {
    final now = DateTime.now();
    final initial = from ? (start ?? now) : (end ?? now);
    final picked = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(now.year - 10), lastDate: DateTime(now.year + 2));
    if (picked == null || !mounted) return;
    setState(() {
      if (from) {
        start = picked;
        if (end != null && end!.isBefore(picked)) end = picked;
      } else {
        end = picked;
        if (start != null && start!.isAfter(picked)) start = picked;
      }
    });
  }

  void _clearFilters() {
    setState(() {
      search.clear();
      minAmount.clear();
      maxAmount.clear();
      start = null;
      end = null;
      partyId = 'all';
    });
  }

  Future<void> _print(List<_ReportRow> rows, double total) async {
    final store = AppDataStore.instance;
    final range = '${start == null ? '—' : _date(start!)} → ${end == null ? '—' : _date(end!)}';
    await ThamanPrintService.printDocument(
      ThamanPrintTemplates.financialLedgerReport(
        store,
        title: _title(widget.s),
        range: range,
        rows: rows.map((r) => [_dateTime(r.date), r.party, r.type, r.reference, r.amount.toStringAsFixed(2), r.actor, r.note]).toList(),
        total: total,
        filters: {
          widget.s.text('الفترة', 'Period'): range,
          widget.s.text('بحث', 'Search'): search.text.trim().isEmpty ? '-' : search.text.trim(),
          widget.s.text('من مبلغ', 'Min'): minAmount.text.trim().isEmpty ? '-' : minAmount.text.trim(),
          widget.s.text('إلى مبلغ', 'Max'): maxAmount.text.trim().isEmpty ? '-' : maxAmount.text.trim(),
          if (partyId != 'all') widget.s.text('الحساب', 'Account'): _selectedPartyName(store),
        },
        isArabic: widget.s.controller.isArabic,
      ),
    );
  }

  String _selectedPartyName(AppDataStore store) {
    if (widget.kind == FinancialReportKind.customers) return store.customerOrNull(partyId)?.name ?? partyId;
    if (widget.kind == FinancialReportKind.suppliers) return store.supplierOrNull(partyId)?.name ?? partyId;
    return partyId;
  }

  String _title(AppStrings s) => switch (widget.kind) {
        FinancialReportKind.inflows => s.text('كل الوارد والتحصيلات', 'All inflows & collections'),
        FinancialReportKind.outflows => s.text('كل المصاريف والمدفوعات', 'All expenses & outflows'),
        FinancialReportKind.customers => s.text('كشوف حساب العملاء', 'Customer statements'),
        FinancialReportKind.suppliers => s.text('كشوف حساب الموردين', 'Supplier statements'),
      };
}

class _ReportRowCard extends StatelessWidget {
  const _ReportRowCard({required this.row, required this.currency, required this.s});
  final _ReportRow row;
  final String currency;
  final AppStrings s;

  @override
  Widget build(BuildContext context) {
    final negative = row.amount < 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
      child: Row(
        children: [
          Container(width: 44, height: 44, alignment: Alignment.center, decoration: BoxDecoration(color: negative ? AppColors.accentSoft : AppColors.primarySoft, borderRadius: BorderRadius.circular(12)), child: Icon(negative ? Icons.call_made_rounded : Icons.call_received_rounded, color: negative ? AppColors.danger : AppColors.success, size: 19)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${row.party} • ${row.type}', style: const TextStyle(fontSize: 10.2, fontWeight: FontWeight.w900)),
            const SizedBox(height: 3),
            Text('${_dateTime(row.date)} • ${row.reference} • ${row.actor}', style: const TextStyle(fontSize: 8.3, color: AppColors.muted)),
            if (row.note.trim().isNotEmpty) ...[const SizedBox(height: 2), Text(row.note, style: const TextStyle(fontSize: 8.2, color: AppColors.muted))],
          ])),
          const SizedBox(width: 8),
          Text('${row.amount.toStringAsFixed(2)} $currency', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: negative ? AppColors.danger : AppColors.primary)),
          PopupMenuButton<String>(
            tooltip: s.text('تفاصيل', 'Details'),
            onSelected: (_) => showDialog<void>(
              context: context,
              builder: (_) => AlertDialog(
                scrollable: true,
                title: Text(row.type),
                content: SizedBox(
                  width: 430,
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _DetailText(label: s.text('الجهة', 'Party'), value: row.party),
                    _DetailText(label: s.text('التاريخ', 'Date'), value: _dateTime(row.date)),
                    _DetailText(label: s.text('المرجع', 'Reference'), value: row.reference),
                    _DetailText(label: s.text('المستخدم', 'Actor'), value: row.actor),
                    _DetailText(label: s.text('المبلغ', 'Amount'), value: '${row.amount.toStringAsFixed(2)} $currency'),
                    _DetailText(label: s.text('التفاصيل', 'Details'), value: row.note.trim().isEmpty ? '—' : row.note),
                  ]),
                ),
                actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(s.text('إغلاق', 'Close')))],
              ),
            ),
            itemBuilder: (_) => [PopupMenuItem(value: 'details', child: Row(children: [const Icon(Icons.info_outline_rounded, size: 17), const SizedBox(width: 8), Text(s.text('عرض التفاصيل', 'View details'))]))],
          ),
        ],
      ),
    );
  }
}

class _DetailText extends StatelessWidget {
  const _DetailText({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 105, child: Text(label, style: const TextStyle(fontSize: 9, color: AppColors.muted, fontWeight: FontWeight.w800))),
      Expanded(child: SelectableText(value, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700))),
    ]),
  );
}

class _ReportRow {
  const _ReportRow({required this.date, required this.partyId, required this.party, required this.type, required this.reference, required this.amount, required this.actor, required this.note});
  final DateTime date;
  final String partyId;
  final String party;
  final String type;
  final String reference;
  final double amount;
  final String actor;
  final String note;
}

String _date(DateTime value) => '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
String _dateTime(DateTime value) => '${_date(value)} ${formatHour12(value)}';
