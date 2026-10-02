import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../core/app_strings.dart';
import '../../../core/printing/print_document.dart';
import '../../../core/printing/print_service.dart';
import '../../../data/app_data_store.dart';

class FinancialReportsScreen extends StatefulWidget {
  const FinancialReportsScreen({super.key, required this.s, this.initialMode = 'incoming'});
  final AppStrings s;
  final String initialMode;

  @override
  State<FinancialReportsScreen> createState() => _FinancialReportsScreenState();
}

class _FinancialReportsScreenState extends State<FinancialReportsScreen> {
  late String mode;
  DateTime? start;
  DateTime? end;
  final search = TextEditingController();
  final minAmount = TextEditingController();
  final maxAmount = TextEditingController();
  String personId = '';

  @override
  void initState() {
    super.initState();
    mode = widget.initialMode;
    final now = DateTime.now();
    start = DateTime(now.year, now.month, 1);
    end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
  }

  @override
  void dispose() {
    search.dispose();
    minAmount.dispose();
    maxAmount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final store = AppDataStore.instance;
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final rows = _filteredRows(store);
        final total = rows.fold<double>(0, (sum, e) => sum + e.amount);
        final people = mode == 'customers'
            ? store.customers.map((e) => MapEntry(e.id, '${e.name} • ${e.accountNumber}')).toList()
            : mode == 'suppliers'
                ? store.suppliers.map((e) => MapEntry(e.id, '${e.name} • ${e.accountNumber}')).toList()
                : const <MapEntry<String, String>>[];
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: Text(s.text('التقارير والكشوف المالية', 'Financial reports & statements')),
            actions: [IconButton(onPressed: rows.isEmpty ? null : () => _print(rows), tooltip: s.text('طباعة التقرير', 'Print report'), icon: const Icon(Icons.print_outlined)), const SizedBox(width: 8)],
          ),
          body: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                _modeChip('incoming', s.text('كل الوارد', 'All incoming')),
                _modeChip('outgoing', s.text('كل المصاريف والصادر', 'All expenses & outgoing')),
                _modeChip('customers', s.text('كشف حساب العملاء', 'Customer statements')),
                _modeChip('suppliers', s.text('كشف حساب الموردين', 'Supplier statements')),
              ]),
              const SizedBox(height: 14),
              Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: LayoutBuilder(builder: (context, c) {
                    final narrow = c.maxWidth < 760;
                    final controls = <Widget>[
                      _dateButton(true),
                      _dateButton(false),
                      if (people.isNotEmpty)
                        DropdownButtonFormField<String>(
                          value: personId,
                          decoration: InputDecoration(labelText: s.text('الشخص / الحساب', 'Person / account')),
                          items: [DropdownMenuItem(value: '', child: Text(s.text('الكل', 'All'))), ...people.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))],
                          onChanged: (v) => setState(() => personId = v ?? ''),
                        ),
                      TextField(controller: minAmount, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: s.text('من مبلغ', 'Min amount'))),
                      TextField(controller: maxAmount, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: s.text('إلى مبلغ', 'Max amount'))),
                    ];
                    return Column(children: [
                      TextField(controller: search, onChanged: (_) => setState(() {}), decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), labelText: s.text('بحث بالاسم، الرقم، المرجع، الملاحظة أو طريقة الدفع', 'Search name, number, reference, note or payment method'))),
                      const SizedBox(height: 10),
                      if (narrow) ...controls.expand((w) => [w, const SizedBox(height: 8)]) else Row(children: controls.map((w) => Expanded(child: Padding(padding: const EdgeInsetsDirectional.only(end: 8), child: w))).toList()),
                    ]);
                  }),
                ),
              ),
              const SizedBox(height: 12),
              _summaryCard(rows, total),
              const SizedBox(height: 12),
              Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(_title(), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900))),
                      Text('${rows.length} ${s.text('حركة', 'entries')}', style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 10),
                      FilledButton.icon(onPressed: rows.isEmpty ? null : () => _print(rows), icon: const Icon(Icons.print_outlined, size: 18), label: Text(s.text('طباعة', 'Print'))),
                    ]),
                    const SizedBox(height: 10),
                    if (rows.isEmpty)
                      Padding(padding: const EdgeInsets.symmetric(vertical: 26), child: Center(child: Text(s.text('لا توجد حركات مطابقة للفلاتر.', 'No matching entries.'), style: const TextStyle(color: AppColors.muted))))
                    else
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: [
                            DataColumn(label: Text(s.text('التاريخ', 'Date'))), DataColumn(label: Text(s.text('الشخص / الجهة', 'Person'))), DataColumn(label: Text(s.text('النوع', 'Type'))), DataColumn(label: Text(s.text('المرجع', 'Reference'))), DataColumn(label: Text(s.text('الطريقة', 'Method'))), DataColumn(label: Text(s.text('المبلغ', 'Amount'))), DataColumn(label: Text(s.text('الملاحظة', 'Note'))),
                          ],
                          rows: rows.map((e) => DataRow(cells: [
                            DataCell(Text(_date(e.date))), DataCell(Text(e.person)), DataCell(Text(e.type)), DataCell(Text(e.reference)), DataCell(Text(e.method)), DataCell(Text('${e.amount.toStringAsFixed(2)} ${store.settings.currency}', style: TextStyle(fontWeight: FontWeight.w900, color: mode == 'incoming' ? AppColors.success : mode == 'outgoing' ? AppColors.danger : AppColors.text))), DataCell(SizedBox(width: 240, child: Text(e.note, maxLines: 2, overflow: TextOverflow.ellipsis))),
                          ])).toList(),
                        ),
                      ),
                  ]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _modeChip(String value, String label) => ChoiceChip(label: Text(label), selected: mode == value, onSelected: (_) => setState(() { mode = value; personId = ''; }));

  Widget _dateButton(bool isStart) {
    final value = isStart ? start : end;
    return OutlinedButton.icon(
      onPressed: () async {
        final picked = await showDatePicker(context: context, initialDate: value ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 3650)));
        if (picked == null) return;
        setState(() {
          if (isStart) start = DateTime(picked.year, picked.month, picked.day);
          else end = DateTime(picked.year, picked.month, picked.day, 23, 59, 59, 999);
        });
      },
      icon: const Icon(Icons.calendar_today_outlined, size: 17),
      label: Text('${isStart ? widget.s.text('من', 'From') : widget.s.text('إلى', 'To')}: ${value == null ? '-' : _date(value)}'),
    );
  }

  List<_LedgerRow> _filteredRows(AppDataStore store) {
    final s = widget.s;
    final rows = <_LedgerRow>[];
    bool inRange(DateTime d) =>
        (start == null || !d.isBefore(start!)) &&
        (end == null || !d.isAfter(end!));

    if (mode == 'incoming') {
      for (final i in store.invoices.where(
        (x) => !x.voided && inRange(x.createdAt) && x.receivedAtSale > 0,
      )) {
        rows.add(_LedgerRow(
          i.createdAt,
          i.customer,
          s.text('بيع مقبوض', 'Sale receipt'),
          i.number,
          s.paymentMethod(i.paymentMethod),
          i.receivedAtSale,
          s.text('بيع نقطة البيع', 'POS sale'),
        ));
      }
      for (final p in store.customerPayments.where((x) => inRange(x.createdAt))) {
        rows.add(_LedgerRow(
          p.createdAt,
          p.customerName,
          s.text('تحصيل عميل', 'Customer payment'),
          p.id,
          s.paymentMethod(p.method),
          p.amount,
          p.note,
        ));
      }
    } else if (mode == 'outgoing') {
      for (final p in store.purchases.where(
        (x) => inRange(x.createdAt) && x.amountPaid > 0,
      )) {
        rows.add(_LedgerRow(
          p.createdAt,
          p.supplier,
          s.text('دفعة شراء', 'Purchase payment'),
          p.number,
          s.paymentMethod(p.paymentMethod),
          p.amountPaid,
          p.note,
        ));
      }
      for (final p in store.supplierPayments.where((x) => inRange(x.createdAt))) {
        rows.add(_LedgerRow(
          p.createdAt,
          p.supplierName,
          s.text('دفعة مورد', 'Supplier payment'),
          p.purchaseNumber.isEmpty ? p.id : p.purchaseNumber,
          s.paymentMethod(p.method),
          p.amount,
          p.note,
        ));
      }
      for (final e in store.expenses.where((x) => inRange(x.createdAt))) {
        rows.add(_LedgerRow(
          e.createdAt,
          e.employeeName,
          s.text('مصروف تشغيلي', 'Operating expense'),
          e.id,
          s.paymentMethod(e.paymentMethod),
          e.amount,
          '${s.expenseCategory(e.category)} • ${e.description}',
        ));
      }
      for (final r in store.returns.where(
        (x) => inRange(x.createdAt) && x.refundAmount > 0,
      )) {
        rows.add(_LedgerRow(
          r.createdAt,
          r.processedBy,
          s.text('رد مبلغ للعميل', 'Customer refund'),
          r.invoiceNumber,
          s.paymentMethod(r.refundMethod),
          r.refundAmount,
          r.reason,
        ));
      }
    } else if (mode == 'customers') {
      for (final i in store.invoices.where(
        (x) =>
            !x.voided &&
            x.customerId.isNotEmpty &&
            inRange(x.createdAt) &&
            (personId.isEmpty || x.customerId == personId),
      )) {
        rows.add(_LedgerRow(
          i.createdAt,
          i.customer,
          s.text('فاتورة', 'Invoice'),
          i.number,
          s.paymentMethod(i.paymentMethod),
          i.total,
          '${s.text('متبقي', 'Due')} ${store.invoiceOutstanding(i.id).toStringAsFixed(2)}',
        ));
      }
      for (final p in store.customerPayments.where(
        (x) =>
            inRange(x.createdAt) &&
            (personId.isEmpty || x.customerId == personId),
      )) {
        rows.add(_LedgerRow(
          p.createdAt,
          p.customerName,
          s.text('دفعة', 'Payment'),
          p.id,
          s.paymentMethod(p.method),
          p.amount,
          p.note,
        ));
      }
      for (final r in store.returns.where((x) => inRange(x.createdAt))) {
        final matches = store.invoices.where((i) => i.id == r.invoiceId).toList();
        if (matches.isEmpty) continue;
        final inv = matches.first;
        if (inv.customerId.isEmpty ||
            (personId.isNotEmpty && inv.customerId != personId)) {
          continue;
        }
        rows.add(_LedgerRow(
          r.createdAt,
          inv.customer,
          s.text('مرتجع', 'Return'),
          r.invoiceNumber,
          s.paymentMethod(r.refundMethod),
          r.total,
          r.reason,
        ));
      }
    } else {
      for (final p in store.purchases.where(
        (x) =>
            inRange(x.createdAt) &&
            (personId.isEmpty || x.supplierId == personId),
      )) {
        rows.add(_LedgerRow(
          p.createdAt,
          p.supplier,
          s.text('شراء', 'Purchase'),
          p.number,
          s.paymentMethod(p.paymentMethod),
          p.total,
          '${s.text('متبقي', 'Due')} ${store.purchaseOutstanding(p).toStringAsFixed(2)} • ${p.note}',
        ));
      }
      for (final p in store.supplierPayments.where(
        (x) =>
            inRange(x.createdAt) &&
            (personId.isEmpty || x.supplierId == personId),
      )) {
        rows.add(_LedgerRow(
          p.createdAt,
          p.supplierName,
          s.text('دفعة', 'Payment'),
          p.purchaseNumber.isEmpty ? p.id : p.purchaseNumber,
          s.paymentMethod(p.method),
          p.amount,
          p.note,
        ));
      }
    }

    final q = search.text.trim().toLowerCase();
    final min = double.tryParse(minAmount.text.trim());
    final max = double.tryParse(maxAmount.text.trim());
    rows.retainWhere((e) {
      final hay =
          '${e.person} ${e.type} ${e.reference} ${e.method} ${e.note}'.toLowerCase();
      if (q.isNotEmpty && !hay.contains(q)) return false;
      if (min != null && e.amount < min) return false;
      if (max != null && e.amount > max) return false;
      return true;
    });
    rows.sort((a, b) => b.date.compareTo(a.date));
    return rows;
  }

  Widget _summaryCard(List<_LedgerRow> rows, double total) {
    final store = AppDataStore.instance;
    final s = widget.s;
    final color = mode == 'incoming' ? AppColors.success : mode == 'outgoing' ? AppColors.danger : AppColors.primary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: mode == 'incoming' ? AppColors.primarySoft : mode == 'outgoing' ? const Color(0xFFFFF1F1) : AppColors.surfaceAlt, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
      child: Row(children: [Icon(mode == 'incoming' ? Icons.south_west_rounded : mode == 'outgoing' ? Icons.north_east_rounded : Icons.account_balance_wallet_outlined, color: color), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_title(), style: const TextStyle(fontWeight: FontWeight.w900)), Text('${rows.length} ${s.text('حركة مطابقة', 'matching entries')}', style: const TextStyle(fontSize: 9, color: AppColors.muted))])), Text('${total.toStringAsFixed(2)} ${store.settings.currency}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color))]),
    );
  }

  String _title() => switch (mode) {
        'incoming' => widget.s.text('تقرير كل الوارد الفعلي', 'All actual incoming funds'),
        'outgoing' => widget.s.text('تقرير كل المصاريف والصادر الفعلي', 'All actual expenses & outgoing funds'),
        'customers' => widget.s.text('كشف حساب العملاء', 'Customer statement report'),
        _ => widget.s.text('كشف حساب الموردين', 'Supplier statement report'),
      };

  Future<void> _print(List<_LedgerRow> rows) async {
    final store = AppDataStore.instance;
    final total = rows.fold<double>(0, (sum, e) => sum + e.amount);
    await ThamanPrintService.printDocument(PrintDocument(
      title: _title(),
      subtitle: '${store.settings.storeName} • ${store.settings.branchName}',
      metadata: {widget.s.text('من تاريخ', 'From'): start == null ? '-' : _date(start!), widget.s.text('إلى تاريخ', 'To'): end == null ? '-' : _date(end!), widget.s.text('عدد الحركات', 'Entries'): '${rows.length}', widget.s.text('فلتر البحث', 'Search filter'): search.text.trim().isEmpty ? '-' : search.text.trim()},
      headers: [widget.s.text('التاريخ', 'Date'), widget.s.text('الشخص / الجهة', 'Person'), widget.s.text('النوع', 'Type'), widget.s.text('المرجع', 'Reference'), widget.s.text('الطريقة', 'Method'), widget.s.text('المبلغ', 'Amount'), widget.s.text('الملاحظة', 'Note')],
      rows: rows.map((e) => [_date(e.date), e.person, e.type, e.reference, e.method, '${e.amount.toStringAsFixed(2)} ${store.settings.currency}', e.note]).toList(),
      summary: {widget.s.text('الإجمالي', 'Total'): '${total.toStringAsFixed(2)} ${store.settings.currency}'},
      notes: [widget.s.text('يمكن البحث داخل معاينة الطباعة قبل الطباعة أو الحفظ PDF.', 'The print preview is searchable before printing or saving as PDF.')],
      footer: store.settings.receiptFooter,
    
      isArabic: widget.s.controller.isArabic,));
  }
}

class _LedgerRow {
  const _LedgerRow(this.date, this.person, this.type, this.reference, this.method, this.amount, this.note);
  final DateTime date; final String person; final String type; final String reference; final String method; final double amount; final String note;
}

String _date(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
