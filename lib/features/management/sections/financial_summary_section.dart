import 'package:flutter/material.dart';
import '../../../core/time_format.dart';
import '../../../app/app_theme.dart';
import '../../../core/app_strings.dart';
import '../../../core/widgets/surface_card.dart';
import '../../../core/printing/print_service.dart';
import '../../../core/printing/print_templates.dart';
import '../../../data/app_data_store.dart';
import '../../../data/models.dart';
import '../widgets/management_widgets.dart';
import 'financial_report_dialog.dart';

class FinancialSummarySection extends StatefulWidget {
  const FinancialSummarySection({super.key, required this.s});
  final AppStrings s;

  @override
  State<FinancialSummarySection> createState() => _FinancialSummarySectionState();
}

class _FinancialSummarySectionState extends State<FinancialSummarySection> {
  String period = 'month';
  DateTime? customStart;
  DateTime? customEnd;

  @override
  Widget build(BuildContext context) {
    final store = AppDataStore.instance;
    final s = widget.s;
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final snapshot = period == 'custom'
            ? _FinancialSnapshot.fromSummary(store.financialSummary(start: _customStartValue, end: _customEndExclusive))
            : _FinancialSnapshot.fromStore(store, period);
        final currency = store.settings.currency;
        final comprehensiveResult = _comprehensiveResult(store, period, _customStartValue, _customEndExclusive);
        final positive = comprehensiveResult >= 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SurfaceCard(
              child: LayoutBuilder(builder: (context, c) {
                final compact = c.maxWidth < 760;
                final intro = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(width: 44, height: 44, decoration: BoxDecoration(color: positive ? AppColors.primarySoft : const Color(0xFFFFEEEE), borderRadius: BorderRadius.circular(14)), child: Icon(positive ? Icons.trending_up_rounded : Icons.trending_down_rounded, color: positive ? AppColors.success : AppColors.danger)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s.text('النتيجة المالية', 'Financial result'), style: const TextStyle(fontSize: 10, color: AppColors.muted, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(positive ? s.text('المتجر رابح', 'Business is profitable') : s.text('المتجر خاسر', 'Business is at a loss'), style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: positive ? AppColors.success : AppColors.danger)),
                      ])),
                    ]),
                    const SizedBox(height: 12),
                    Text('${comprehensiveResult.abs().toStringAsFixed(2)} $currency', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: -1, color: positive ? AppColors.text : AppColors.danger)),
                    const SizedBox(height: 5),
                    Text(s.text('النتيجة الشاملة = كل المقبوضات − كل المدفوعات الفعلية: مشتريات، دفعات موردين، مصروفات، رواتب، سلف، أصول ومرتجعات ضمن الفترة المختارة.', 'Comprehensive result = all receipts minus all actual outflows: purchases, supplier payments, expenses, payroll, advances, assets and refunds in the selected period.'), style: const TextStyle(fontSize: 9, color: AppColors.muted, height: 1.5)),
                  ],
                );
                final filter = DropdownButtonFormField<String>(
                  value: period,
                  decoration: InputDecoration(labelText: s.text('الفترة', 'Period'), prefixIcon: const Icon(Icons.date_range_outlined, size: 18)),
                  items: [
                    DropdownMenuItem(value: 'today', child: Text(s.text('اليوم', 'Today'))),
                    DropdownMenuItem(value: 'week', child: Text(s.text('آخر 7 أيام', 'Last 7 days'))),
                    DropdownMenuItem(value: 'month', child: Text(s.text('هذا الشهر', 'This month'))),
                    DropdownMenuItem(value: 'all', child: Text(s.text('كل الفترة', 'All time'))),
                    DropdownMenuItem(value: 'custom', child: Text(s.text('فترة مخصصة', 'Custom range'))),
                  ],
                  onChanged: (value) => setState(() {
                    period = value ?? period;
                    if (period == 'custom' && customStart == null) {
                      final now = DateTime.now();
                      customEnd = DateTime(now.year, now.month, now.day);
                      customStart = customEnd!.subtract(const Duration(days: 29));
                    }
                  }),
                );
                final printButton = OutlinedButton.icon(
                  onPressed: () => _printSummary(context),
                  icon: const Icon(Icons.print_outlined, size: 17),
                  label: Text(s.text('طباعة الملخص', 'Print summary')),
                );
                return compact
                    ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [intro, const SizedBox(height: 16), filter, const SizedBox(height: 8), printButton])
                    : Row(children: [Expanded(child: intro), const SizedBox(width: 22), SizedBox(width: 210, child: Column(children: [filter, const SizedBox(height: 8), SizedBox(width: double.infinity, child: printButton)]))]);
              }),
            ),
            if (period == 'custom') ...[
              const SizedBox(height: 10),
              _CustomPeriodFilter(
                s: s,
                start: customStart,
                end: customEnd,
                onStart: () => _pickCustomDate(true),
                onEnd: () => _pickCustomDate(false),
              ),
            ],
            const SizedBox(height: 12),
            _SummaryGrid(s: s, snapshot: snapshot),
            const SizedBox(height: 12),
            _FinancialFlowCards(
              s: s,
              onInflows: () => showFinancialReportDialog(context, s: s, kind: FinancialReportKind.inflows),
              onOutflows: () => showFinancialReportDialog(context, s: s, kind: FinancialReportKind.outflows),
            ),
            const SizedBox(height: 12),
            _PeriodReconciliation(s: s),
            const SizedBox(height: 12),
            SurfaceCard(
              child: LayoutBuilder(builder: (context, c) {
                final actions = [
                  _FinanceAction(icon: Icons.person_add_alt_1_outlined, title: s.text('قبض من عميل', 'Collect customer payment'), subtitle: s.text('تخفيض المبلغ المستحق على العميل.', 'Reduce a customer receivable.'), onTap: () => _collectCustomer(context)),
                  _FinanceAction(icon: Icons.local_shipping_outlined, title: s.text('دفع للمورد', 'Pay supplier'), subtitle: s.text('تسجيل دفعة وربطها بالمورد أو فاتورة شراء.', 'Record a supplier payment and optionally link a purchase.'), onTap: () => _paySupplier(context)),
                  _FinanceAction(icon: Icons.receipt_long_outlined, title: s.text('تسجيل مصروف', 'Record expense'), subtitle: s.text('مصروف تشغيلي ينعكس على صافي الربح.', 'Operating expense reflected in net profit.'), onTap: () => _addExpense(context)),
                  _FinanceAction(icon: Icons.manage_accounts_outlined, title: s.text('كشف حساب عميل', 'Customer statement'), subtitle: s.text('بحث وتصفية حسب العميل والتاريخ والمبلغ ثم الطباعة.', 'Filter by customer, date and amount, then print.'), onTap: () => showFinancialReportDialog(context, s: s, kind: FinancialReportKind.customers)),
                  _FinanceAction(icon: Icons.local_shipping_outlined, title: s.text('كشف حساب مورد', 'Supplier statement'), subtitle: s.text('كشف مشتريات ودفعات المورد مع التصفية والطباعة.', 'Supplier purchases and payments with filters and printing.'), onTap: () => showFinancialReportDialog(context, s: s, kind: FinancialReportKind.suppliers)),
                ];
                final cols = c.maxWidth >= 900 ? 3 : c.maxWidth >= 560 ? 2 : 1;
                return GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: cols, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: cols == 1 ? 3.6 : 2.25, children: actions.map((a) => _FinanceActionCard(data: a)).toList());
              }),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(builder: (context, c) {
              final wide = c.maxWidth >= 960;
              final receivables = _ReceivablesPanel(s: s);
              final payables = _PayablesPanel(s: s);
              return wide ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: receivables), const SizedBox(width: 12), Expanded(child: payables)]) : Column(children: [receivables, const SizedBox(height: 12), payables]);
            }),
            const SizedBox(height: 12),
            _RecentFinancialActivity(s: s),
          ],
        );
      },
    );
  }

  DateTime? get _customStartValue => customStart == null ? null : DateTime(customStart!.year, customStart!.month, customStart!.day);
  DateTime? get _customEndExclusive => customEnd == null ? null : DateTime(customEnd!.year, customEnd!.month, customEnd!.day).add(const Duration(days: 1));

  Future<void> _pickCustomDate(bool startField) async {
    final now = DateTime.now();
    final initial = startField ? (customStart ?? now) : (customEnd ?? now);
    final picked = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(now.year - 10), lastDate: DateTime(now.year + 2));
    if (picked == null || !mounted) return;
    setState(() {
      if (startField) {
        customStart = picked;
        if (customEnd != null && customEnd!.isBefore(picked)) customEnd = picked;
      } else {
        customEnd = picked;
        if (customStart != null && customStart!.isAfter(picked)) customStart = picked;
      }
    });
  }

  Future<void> _printSummary(BuildContext context) async {
    final store = AppDataStore.instance;
    final now = DateTime.now();
    DateTime? start; DateTime? end;
    if (period == 'today') { start = DateTime(now.year, now.month, now.day); end = start.add(const Duration(days: 1)); }
    else if (period == 'week') { start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6)); end = DateTime(now.year, now.month, now.day).add(const Duration(days: 1)); }
    else if (period == 'month') { start = DateTime(now.year, now.month, 1); end = now.month == 12 ? DateTime(now.year + 1, 1, 1) : DateTime(now.year, now.month + 1, 1); }
    else if (period == 'custom') { start = _customStartValue; end = _customEndExclusive; }
    final value = store.financialSummary(start: start, end: end);
    final s = widget.s;
    final label = switch(period){'today'=>s.text('اليوم','Today'),'week'=>s.text('آخر 7 أيام','Last 7 days'),'month'=>s.text('هذا الشهر','This month'),'custom'=>'${_shortDate(start)} → ${_shortDate(end == null ? null : end.subtract(const Duration(days: 1)))}',_=>s.text('كل الفترة','All time')};
    await ThamanPrintService.printDocument(ThamanPrintTemplates.financialSummary(store, value, label, isArabic: s.controller.isArabic));
  }

  Future<void> _collectCustomer(BuildContext context) async {
    final store = AppDataStore.instance;
    final s = widget.s;
    final available = store.customers.where((c) => c.balance > 0).toList();
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.text('لا توجد ذمم مستحقة على العملاء حاليًا.', 'There are no customer receivables right now.'))));
      return;
    }
    String customerId = available.first.id;
    String method = 'Cash';
    final amount = TextEditingController();
    final note = TextEditingController();
    String? error;
    await showDialog<void>(context: context, builder: (_) => StatefulBuilder(builder: (context, setD) {
      final customer = store.customerOrNull(customerId)!;
      return AlertDialog(
          scrollable: true,
        title: Text(s.text('قبض دفعة من عميل', 'Collect customer payment')),
        content: SizedBox(width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 520.0).toDouble(), child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(value: customerId, decoration: InputDecoration(labelText: s.text('العميل', 'Customer')), items: available.map((c) => DropdownMenuItem(value: c.id, child: Text('${c.name} • ${c.accountNumber} • ${c.balance.toStringAsFixed(2)} ${store.settings.currency}'))).toList(), onChanged: (v) => setD(() => customerId = v ?? customerId)),
          const SizedBox(height: 10),
          TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: s.text('المبلغ المقبوض', 'Amount received'), helperText: '${s.text('المستحق الحالي', 'Current due')}: ${customer.balance.toStringAsFixed(2)} ${store.settings.currency}')),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(value: method, decoration: InputDecoration(labelText: s.text('طريقة القبض', 'Payment method')), items: const ['Cash', 'Card', 'Bank', 'Wallet'].map((v) => DropdownMenuItem(value: v, child: Text(s.paymentMethod(v)))).toList(), onChanged: (v) => setD(() => method = v ?? method)),
          const SizedBox(height: 10),
          TextField(controller: note, decoration: InputDecoration(labelText: s.text('ملاحظة', 'Note'))),
          if (error != null) ...[const SizedBox(height: 8), Align(alignment: AlignmentDirectional.centerStart, child: Text(error!, style: const TextStyle(color: AppColors.danger, fontSize: 9, fontWeight: FontWeight.w700)))],
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(s.text('إلغاء', 'Cancel'))), FilledButton(onPressed: () {
          final value = double.tryParse(amount.text.trim()) ?? 0;
          final result = store.recordCustomerPayment(customerId: customerId, amount: value, method: method, employeeName: s.controller.currentUserName, note: note.text.trim());
          if (result == null) { setD(() => error = s.text('تحقق من المبلغ. لا يمكن قبض مبلغ أكبر من الرصيد المستحق.', 'Check the amount. It cannot exceed the current receivable.')); return; }
          Navigator.pop(context);
        }, child: Text(s.text('تسجيل القبض', 'Record payment')))],
      );
    }));
    amount.dispose(); note.dispose();
  }

  Future<void> _paySupplier(BuildContext context) async {
    final store = AppDataStore.instance;
    final s = widget.s;
    final available = store.suppliers.where((sup) => store.supplierBalance(sup.id) > 0).toList();
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.text('لا توجد مبالغ مستحقة للموردين حاليًا.', 'There are no supplier payables right now.'))));
      return;
    }
    String supplierId = available.first.id;
    String purchaseId = '';
    String method = 'Cash';
    final amount = TextEditingController();
    final note = TextEditingController();
    String? error;
    await showDialog<void>(context: context, builder: (_) => StatefulBuilder(builder: (context, setD) {
      final supplier = store.supplierOrNull(supplierId)!;
      final purchases = store.purchases.where((p) => p.supplierId == supplierId && store.purchaseOutstanding(p) > 0).toList();
      return AlertDialog(
          scrollable: true,
        title: Text(s.text('دفع دفعة لمورد', 'Supplier payment')),
        content: SizedBox(width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 540.0).toDouble(), child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(value: supplierId, decoration: InputDecoration(labelText: s.text('المورد', 'Supplier')), items: available.map((sup) => DropdownMenuItem(value: sup.id, child: Text('${sup.name} • ${store.supplierBalance(sup.id).toStringAsFixed(2)} ${store.settings.currency}'))).toList(), onChanged: (v) => setD(() { supplierId = v ?? supplierId; purchaseId = ''; })),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(value: purchaseId, decoration: InputDecoration(labelText: s.text('ربط بفاتورة شراء (اختياري)', 'Link to purchase (optional)')), items: [DropdownMenuItem(value: '', child: Text(s.text('دفعة عامة على حساب المورد', 'General supplier payment'))), ...purchases.map((p) => DropdownMenuItem(value: p.id, child: Text('${p.number} • ${store.purchaseOutstanding(p).toStringAsFixed(2)} ${store.settings.currency}')))], onChanged: (v) => setD(() => purchaseId = v ?? '')),
          const SizedBox(height: 10),
          TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: s.text('المبلغ المدفوع', 'Amount paid'), helperText: '${s.text('رصيد المورد', 'Supplier balance')}: ${store.supplierBalance(supplier.id).toStringAsFixed(2)} ${store.settings.currency}')),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(value: method, decoration: InputDecoration(labelText: s.text('طريقة الدفع', 'Payment method')), items: const ['Cash', 'Bank', 'Card', 'Wallet'].map((v) => DropdownMenuItem(value: v, child: Text(s.paymentMethod(v)))).toList(), onChanged: (v) => setD(() => method = v ?? method)),
          const SizedBox(height: 10),
          TextField(controller: note, decoration: InputDecoration(labelText: s.text('ملاحظة', 'Note'))),
          if (error != null) ...[const SizedBox(height: 8), Align(alignment: AlignmentDirectional.centerStart, child: Text(error!, style: const TextStyle(color: AppColors.danger, fontSize: 9, fontWeight: FontWeight.w700)))],
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(s.text('إنهاء', 'Done'))), FilledButton(onPressed: () {
          final value = double.tryParse(amount.text.trim()) ?? 0;
          final result = store.recordSupplierPayment(supplierId: supplierId, amount: value, method: method, employeeName: s.controller.currentUserName, purchaseId: purchaseId, note: note.text.trim());
          if (result == null) { setD(() => error = s.text('تحقق من المبلغ والرصيد المستحق.', 'Check the amount and outstanding balance.')); return; }
          setD(() {
            error = null;
            amount.text = '';
            note.clear();
            if (store.supplierBalance(supplierId) <= 0.005) purchaseId = '';
          });
        }, child: Text(s.text('تسجيل الدفعة', 'Record payment')))],
      );
    }));
    amount.dispose(); note.dispose();
  }

  Future<void> _addExpense(BuildContext context) async {
    final store = AppDataStore.instance;
    final s = widget.s;
    final description = TextEditingController();
    final note = TextEditingController();
    final amount = TextEditingController();
    var expenseDate = DateTime.now();
    String category = 'Operations';
    String method = 'Cash';
    String? error;
    await showDialog<void>(context: context, builder: (_) => StatefulBuilder(builder: (context, setD) => AlertDialog(
          scrollable: true,
      title: Text(s.text('تسجيل مصروف', 'Record expense')),
      content: SizedBox(width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 500.0).toDouble(), child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(value: category, decoration: InputDecoration(labelText: s.text('التصنيف', 'Category')), items: const ['Operations', 'Utilities', 'Transport', 'Maintenance', 'Marketing', 'Other', 'Custom'].map((v) => DropdownMenuItem(value: v, child: Text(v == 'Custom' ? s.text('+ مصروف خاص', '+ Custom expense') : s.expenseCategory(v)))).toList(), onChanged: (v) => setD(() => category = v ?? category)),
        const SizedBox(height: 10),
        TextField(controller: description, decoration: InputDecoration(labelText: s.text('البيان', 'Description'))),
        const SizedBox(height: 10),
        TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: s.text('المبلغ', 'Amount'))),
        const SizedBox(height: 10),
        TextField(controller: note, maxLines: 2, decoration: InputDecoration(labelText: s.text('ملاحظة / سبب المصروف', 'Expense note / reason'))),
        const SizedBox(height: 10),
        OutlinedButton.icon(onPressed: () async { final d = await showDatePicker(context: context, initialDate: expenseDate, firstDate: DateTime(DateTime.now().year-10), lastDate: DateTime(DateTime.now().year+2)); if (d != null) setD(() => expenseDate = d); }, icon: const Icon(Icons.calendar_month_rounded), label: Text('${expenseDate.day.toString().padLeft(2,'0')}/${expenseDate.month.toString().padLeft(2,'0')}/${expenseDate.year}')),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(value: method, decoration: InputDecoration(labelText: s.text('طريقة الدفع', 'Payment method')), items: const ['Cash', 'Bank', 'Card'].map((v) => DropdownMenuItem(value: v, child: Text(s.paymentMethod(v)))).toList(), onChanged: (v) => setD(() => method = v ?? method)),
        if (error != null) ...[const SizedBox(height: 8), Text(error!, style: const TextStyle(color: AppColors.danger, fontSize: 9))],
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(s.text('إلغاء', 'Cancel'))), FilledButton(onPressed: () {
        final baseDescription = description.text.trim();
        final fullDescription = note.text.trim().isEmpty ? baseDescription : '$baseDescription • ${note.text.trim()}';
        final result = store.addExpense(category: category == 'Custom' ? 'Other' : category, description: fullDescription, amount: double.tryParse(amount.text) ?? 0, employeeName: s.controller.currentUserName, paymentMethod: method, createdAt: expenseDate);
        if (result == null) { setD(() => error = s.text('أدخل بيانًا ومبلغًا صحيحًا.', 'Enter a description and valid amount.')); return; }
        Navigator.pop(context);
      }, child: Text(s.text('حفظ المصروف', 'Save expense')))],
    )));
    description.dispose(); note.dispose(); amount.dispose();
  }
}


double _comprehensiveResult(AppDataStore store, String period, DateTime? customStart, DateTime? customEnd) {
  final now = DateTime.now();
  DateTime? start;
  DateTime? end;
  if (period == 'today') { start = DateTime(now.year, now.month, now.day); end = start.add(const Duration(days: 1)); }
  else if (period == 'week') { start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6)); end = DateTime(now.year, now.month, now.day).add(const Duration(days: 1)); }
  else if (period == 'month') { start = DateTime(now.year, now.month, 1); end = now.month == 12 ? DateTime(now.year + 1, 1, 1) : DateTime(now.year, now.month + 1, 1); }
  else if (period == 'custom') { start = customStart; end = customEnd; }
  return store.cashResultForPeriod(start: start, end: end);
}


class _CustomPeriodFilter extends StatelessWidget {
  const _CustomPeriodFilter({required this.s, required this.start, required this.end, required this.onStart, required this.onEnd});
  final AppStrings s;
  final DateTime? start;
  final DateTime? end;
  final VoidCallback onStart;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        child: LayoutBuilder(builder: (context, c) {
          final title = Row(children: [const Icon(Icons.date_range_rounded, color: AppColors.primary, size: 20), const SizedBox(width: 10), Expanded(child: Text(s.text('الفترة المخصصة للملخص المالي', 'Custom financial-summary range'), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900)))]);
          final buttons = Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(onPressed: onStart, icon: const Icon(Icons.calendar_today_outlined, size: 15), label: Text(_shortDate(start))),
            OutlinedButton.icon(onPressed: onEnd, icon: const Icon(Icons.event_available_outlined, size: 15), label: Text(_shortDate(end))),
          ]);
          if (c.maxWidth < 620) return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [title, const SizedBox(height: 10), buttons]);
          return Row(children: [Expanded(child: title), buttons]);
        }),
      );
}

class _FinancialFlowCards extends StatelessWidget {
  const _FinancialFlowCards({required this.s, required this.onInflows, required this.onOutflows});
  final AppStrings s;
  final VoidCallback onInflows;
  final VoidCallback onOutflows;

  @override
  Widget build(BuildContext context) {
    final store = AppDataStore.instance;
    final purchaseRefundIn = store.purchaseReturns.where((r) => store.isInCurrentFinancialPeriod(r.createdAt)).fold<double>(0, (sum, r) => sum + r.cashRefund);
    final inflow = store.invoices.where((i) => !i.voided && store.isInCurrentFinancialPeriod(i.createdAt)).fold<double>(0, (sum, i) => sum + i.receivedAtSale) + store.customerPayments.where((p) => store.isInCurrentFinancialPeriod(p.createdAt)).fold<double>(0, (sum, p) => sum + p.amount) + purchaseRefundIn;
    final outflow = (store.expenses.where((e) => store.isInCurrentFinancialPeriod(e.createdAt)).fold<double>(0, (sum, e) => sum + e.amount) + store.purchases.where((p) => store.isInCurrentFinancialPeriod(p.createdAt)).fold<double>(0, (sum, p) => sum + p.amountPaid) + store.supplierPayments.where((p) => store.isInCurrentFinancialPeriod(p.createdAt)).fold<double>(0, (sum, p) => sum + p.amount) + store.returns.where((r) => store.isInCurrentFinancialPeriod(r.createdAt)).fold<double>(0, (sum, r) => sum + r.refundAmount) + store.assets.where((a) => store.isInCurrentFinancialPeriod(a.purchaseDate)).fold<double>(0, (sum, a) => sum + a.purchasePrice)).clamp(0, double.infinity).toDouble();
    Widget card({required String title, required String subtitle, required double amount, required IconData icon, required Color color, required VoidCallback onTap}) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.border)),
          child: Row(children: [
            Container(width: 48, height: 48, decoration: BoxDecoration(color: color.withValues(alpha: .09), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: color)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900)), const SizedBox(height: 3), Text(subtitle, style: const TextStyle(fontSize: 8.2, color: AppColors.muted, height: 1.45)), const SizedBox(height: 8), Text('${amount.toStringAsFixed(2)} ${store.settings.currency}', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: color))])),
            const Icon(Icons.arrow_outward_rounded, color: AppColors.muted, size: 18),
          ]),
        ),
      );
    return LayoutBuilder(builder: (context, c) {
      final a = card(title: s.text('كل الوارد', 'All inflows'), subtitle: s.text('المبيعات المقبوضة + تحصيلات العملاء + ما دفعه الموردون عن المرتجعات. اضغط للبحث والتفاصيل والطباعة.', 'Collected sales + customer collections + supplier return payments. Open for search, details and printing.'), amount: inflow, icon: Icons.south_west_rounded, color: AppColors.success, onTap: onInflows);
      final b = card(title: s.text('كل المصاريف والمدفوعات', 'All expenses & outflows'), subtitle: s.text('المصاريف + دفعات الموردين + المدفوع من المشتريات + رد المبالغ + الأصول.', 'Expenses + supplier payments + purchase payments + refunds + assets.'), amount: outflow, icon: Icons.north_east_rounded, color: AppColors.danger, onTap: onOutflows);
      if (c.maxWidth < 720) return Column(children: [a, const SizedBox(height: 10), b]);
      return Row(children: [Expanded(child: a), const SizedBox(width: 10), Expanded(child: b)]);
    });
  }
}

String _shortDate(DateTime? d) => d == null ? '—' : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.s, required this.snapshot});
  final AppStrings s;
  final _FinancialSnapshot snapshot;
  @override
  Widget build(BuildContext context) {
    final store = AppDataStore.instance;
    final c = store.settings.currency;
    final cards = [
      ManagementMetric(s.text('صافي المبيعات', 'Net sales'), '${snapshot.netSales.toStringAsFixed(2)} $c', Icons.point_of_sale_outlined, AppColors.primary),
      ManagementMetric(s.text('المقبوض من العملاء', 'Collected from customers'), '${snapshot.collected.toStringAsFixed(2)} $c', Icons.payments_outlined, AppColors.success),
      ManagementMetric(s.text('لنا عند العملاء', 'Receivables'), '${store.totalReceivables.toStringAsFixed(2)} $c', Icons.person_search_outlined, AppColors.blue),
      ManagementMetric(s.text('علينا للموردين', 'Supplier payables'), '${store.totalPayables.toStringAsFixed(2)} $c', Icons.local_shipping_outlined, AppColors.accent),
      ManagementMetric(s.text('المشتريات', 'Purchases'), '${snapshot.purchases.toStringAsFixed(2)} $c', Icons.shopping_cart_outlined, AppColors.blue),
      ManagementMetric(s.text('مرتجعات المشتريات', 'Purchase returns'), '${snapshot.purchaseReturns.toStringAsFixed(2)} $c', Icons.assignment_return_outlined, AppColors.accent),
      ManagementMetric(s.text('باقي لنا عند الموردين من المرتجعات', 'Supplier return receivables'), '${snapshot.supplierReturnReceivables.toStringAsFixed(2)} $c', Icons.request_quote_outlined, snapshot.supplierReturnReceivables > 0.005 ? AppColors.danger : AppColors.success),
      ManagementMetric(s.text('المدفوع للموردين', 'Paid to suppliers'), '${snapshot.supplierPaid.toStringAsFixed(2)} $c', Icons.account_balance_outlined, AppColors.primary),
      ManagementMetric(s.text('تكلفة البضاعة المباعة', 'COGS'), '${snapshot.costOfSales.toStringAsFixed(2)} $c', Icons.inventory_2_outlined, AppColors.accent),
      ManagementMetric(s.text('المصروفات', 'Expenses'), '${snapshot.expenses.toStringAsFixed(2)} $c', Icons.receipt_outlined, AppColors.danger),
      ManagementMetric(s.text('إجمالي الربح', 'Gross profit'), '${snapshot.grossProfit.toStringAsFixed(2)} $c', Icons.insights_outlined, AppColors.success),
      ManagementMetric(s.text('التدفق النقدي التشغيلي', 'Operating cash flow'), '${snapshot.cashFlow.toStringAsFixed(2)} $c', Icons.currency_exchange_rounded, snapshot.cashFlow >= 0 ? AppColors.success : AppColors.danger),
      ManagementMetric(s.text('قيمة المخزون', 'Inventory value'), '${store.inventoryValue.toStringAsFixed(2)} $c', Icons.warehouse_outlined, AppColors.primary),
      ManagementMetric(s.text('صافي الربح/الخسارة', 'Net profit / loss'), '${snapshot.netProfit.toStringAsFixed(2)} $c', snapshot.netProfit >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded, snapshot.netProfit >= 0 ? AppColors.success : AppColors.danger),
    ];
    return ManagementMetricsGrid(items: cards);
  }
}



class _PeriodReconciliation extends StatelessWidget {
  const _PeriodReconciliation({required this.s});
  final AppStrings s;

  @override
  Widget build(BuildContext context) {
    final store = AppDataStore.instance;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final monthStart = DateTime(now.year, now.month, 1);
    final nextMonth = now.month == 12 ? DateTime(now.year + 1, 1, 1) : DateTime(now.year, now.month + 1, 1);
    final today = store.financialSummary(start: todayStart, end: tomorrow);
    final earlier = store.financialSummary(start: monthStart, end: todayStart);
    final month = store.financialSummary(start: monthStart, end: nextMonth);
    final c = store.settings.currency;

    Widget amount(String label, double value, {bool total = false}) {
      final color = value >= 0 ? AppColors.success : AppColors.danger;
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: total ? AppColors.primarySoft : AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: total ? AppColors.primary.withValues(alpha: .15) : AppColors.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 8.5, color: AppColors.muted, fontWeight: FontWeight.w700)),
            const SizedBox(height: 5),
            Text('${value.toStringAsFixed(2)} $c', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: color)),
          ]),
        ),
      );
    }

    return SurfaceCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.calculate_outlined, color: AppColors.primary, size: 19),
          const SizedBox(width: 8),
          Expanded(child: Text(s.text('مطابقة ربح الشهر', 'Monthly profit reconciliation'), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900))),
        ]),
        const SizedBox(height: 6),
        Text(
          s.text(
            'ربح هذا الشهر يساوي نتيجة الأيام السابقة + نتيجة اليوم. لذلك قد يكون أقل من ربح اليوم إذا كانت الأيام السابقة فيها خسائر أو مصروفات.',
            'This month equals earlier days + today. The month can be lower than today when earlier days include losses or expenses.',
          ),
          style: const TextStyle(fontSize: 8.7, color: AppColors.muted, height: 1.55),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 560) {
              return Column(children: [
                Row(children: [
                  amount(s.text('قبل اليوم', 'Earlier this month'), earlier.netProfit),
                  const SizedBox(width: 8),
                  amount(s.text('اليوم', 'Today'), today.netProfit),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  amount(s.text('إجمالي الشهر • يشمل اليوم', 'Month total • includes today'), month.netProfit, total: true),
                ]),
              ]);
            }
            return Row(children: [
              amount(s.text('قبل اليوم', 'Earlier this month'), earlier.netProfit),
              const SizedBox(width: 8),
              amount(s.text('اليوم', 'Today'), today.netProfit),
              const SizedBox(width: 8),
              amount(s.text('إجمالي الشهر • يشمل اليوم', 'Month total • includes today'), month.netProfit, total: true),
            ]);
          },
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
          child: Text(
            '${s.text('المعادلة', 'Equation')}: ${earlier.netProfit.toStringAsFixed(2)} + ${today.netProfit.toStringAsFixed(2)} = ${month.netProfit.toStringAsFixed(2)} $c',
            style: const TextStyle(fontSize: 9.2, fontWeight: FontWeight.w900, color: AppColors.primary),
          ),
        ),
      ]),
    );
  }
}

class _ReceivablesPanel extends StatelessWidget {
  const _ReceivablesPanel({required this.s});
  final AppStrings s;
  @override
  Widget build(BuildContext context) {
    final store = AppDataStore.instance;
    final data = store.customers.where((c) => c.balance > 0).toList()..sort((a, b) => b.balance.compareTo(a.balance));
    return SurfaceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Expanded(child: Text(s.text('الذمم لنا', 'Receivables'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900))), Text('${(store.totalReceivables + store.supplierReturnReceivables).toStringAsFixed(2)} ${store.settings.currency}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppColors.blue))]),
      const SizedBox(height: 10),
      if (data.isEmpty && store.supplierReturnReceivables <= 0.005) Text(s.text('لا توجد مبالغ مستحقة.', 'No outstanding receivables.'), style: const TextStyle(fontSize: 9, color: AppColors.muted)) else ...[
        if (store.supplierReturnReceivables > 0.005) ...[
          Row(children: [Container(width: 34, height: 34, decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.assignment_return_outlined, color: AppColors.accent, size: 17)), const SizedBox(width: 9), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(s.text('باقي لنا من مرتجعات الموردين', 'Supplier return receivables'), style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800)), Text(s.text('مبالغ متفق إرجاعها ولم تُقبض بعد', 'Agreed supplier refunds not yet collected'), style: const TextStyle(fontSize: 8, color: AppColors.muted))])), Text('${store.supplierReturnReceivables.toStringAsFixed(2)} ${store.settings.currency}', style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: AppColors.danger))]),
          if (data.isNotEmpty) const Divider(height: 17),
        ],
        for (final item in data.take(8)) ...[
        Row(children: [Container(width: 34, height: 34, decoration: BoxDecoration(color: AppColors.blue.withValues(alpha: .08), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.person_outline_rounded, color: AppColors.blue, size: 17)), const SizedBox(width: 9), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(item.name, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800)), Text('${item.accountNumber} • ${item.phone}', style: const TextStyle(fontSize: 8, color: AppColors.muted))])), Text('${item.balance.toStringAsFixed(2)} ${store.settings.currency}', style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900))]),
        if (item != data.take(8).last) const Divider(height: 17),
      ],
      ],
    ]));
  }
}

class _PayablesPanel extends StatelessWidget {
  const _PayablesPanel({required this.s});
  final AppStrings s;
  @override
  Widget build(BuildContext context) {
    final store = AppDataStore.instance;
    final data = store.suppliers.where((x) => store.supplierBalance(x.id) > 0).toList()..sort((a, b) => store.supplierBalance(b.id).compareTo(store.supplierBalance(a.id)));
    return SurfaceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Expanded(child: Text(s.text('ذمم الموردين', 'Supplier payables'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900))), Text('${store.totalPayables.toStringAsFixed(2)} ${store.settings.currency}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppColors.accent))]),
      const SizedBox(height: 10),
      if (data.isEmpty) Text(s.text('لا توجد مبالغ مستحقة.', 'No outstanding payables.'), style: const TextStyle(fontSize: 9, color: AppColors.muted)) else for (final item in data.take(8)) ...[
        Row(children: [Container(width: 34, height: 34, decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.local_shipping_outlined, color: AppColors.accent, size: 17)), const SizedBox(width: 9), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(item.name, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800)), Text('${item.accountNumber} • ${item.phone}', style: const TextStyle(fontSize: 8, color: AppColors.muted))])), Text('${store.supplierBalance(item.id).toStringAsFixed(2)} ${store.settings.currency}', style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900))]),
        if (item != data.take(8).last) const Divider(height: 17),
      ],
    ]));
  }
}

class _RecentFinancialActivity extends StatelessWidget {
  const _RecentFinancialActivity({required this.s});
  final AppStrings s;
  @override
  Widget build(BuildContext context) {
    final store = AppDataStore.instance;
    final rows = <_Activity>[];
    for (final e in store.expenses) { rows.add(_Activity(e.createdAt, Icons.receipt_outlined, AppColors.danger, e.description, '-${e.amount.toStringAsFixed(2)} ${store.settings.currency}', e.employeeName)); }
    for (final p in store.customerPayments) { rows.add(_Activity(p.createdAt, Icons.call_received_rounded, AppColors.success, '${s.text('قبض من', 'Collected from')} ${p.customerName}', '+${p.amount.toStringAsFixed(2)} ${store.settings.currency}', p.employeeName)); }
    for (final p in store.supplierPayments) { rows.add(_Activity(p.createdAt, Icons.call_made_rounded, AppColors.accent, '${s.text('دفعة إلى', 'Paid to')} ${p.supplierName}', '-${p.amount.toStringAsFixed(2)} ${store.settings.currency}', p.employeeName)); }
    for (final r in store.purchaseReturns) {
      rows.add(_Activity(
        r.createdAt,
        Icons.assignment_return_outlined,
        AppColors.accent,
        '${s.text('مرتجع شراء', 'Purchase return')} • ${r.purchaseNumber} • ${r.supplierName}',
        '${r.agreedAmount.toStringAsFixed(2)} ${store.settings.currency}',
        r.processedBy,
      ));
    }
    rows.sort((a, b) => b.date.compareTo(a.date));
    return SurfaceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(s.text('آخر الحركات المالية', 'Recent financial activity'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
      const SizedBox(height: 10),
      if (rows.isEmpty) Text(s.text('لا توجد حركات إضافية بعد.', 'No additional financial activity yet.'), style: const TextStyle(fontSize: 9, color: AppColors.muted)) else for (final row in rows.take(12)) ...[
        Row(children: [Container(width: 36, height: 36, decoration: BoxDecoration(color: row.color.withValues(alpha: .08), borderRadius: BorderRadius.circular(11)), child: Icon(row.icon, size: 17, color: row.color)), const SizedBox(width: 9), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(row.title, style: const TextStyle(fontSize: 9.4, fontWeight: FontWeight.w800)), Text('${_dateTime(row.date)} • ${row.actor}', style: const TextStyle(fontSize: 8, color: AppColors.muted))])), Text(row.amount, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: row.color))]),
        if (row != rows.take(12).last) const Divider(height: 17),
      ],
    ]));
  }
}

class _FinanceAction {
  const _FinanceAction({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon; final String title; final String subtitle; final VoidCallback onTap;
}
class _FinanceActionCard extends StatelessWidget {
  const _FinanceActionCard({required this.data}); final _FinanceAction data;
  @override Widget build(BuildContext context) => InkWell(onTap: data.onTap, borderRadius: BorderRadius.circular(15), child: Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(15), border: Border.all(color: AppColors.border)), child: Row(children: [Container(width: 39, height: 39, decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(12)), child: Icon(data.icon, color: AppColors.primary, size: 19)), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Text(data.title, style: const TextStyle(fontSize: 9.8, fontWeight: FontWeight.w900)), const SizedBox(height: 3), Text(data.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 8, color: AppColors.muted))])), const Icon(Icons.arrow_outward_rounded, size: 16, color: AppColors.muted)])));
}

class _FinancialSnapshot {
  const _FinancialSnapshot({required this.netSales, required this.collected, required this.purchases, required this.purchaseReturns, required this.supplierReturnReceivables, required this.supplierPaid, required this.costOfSales, required this.expenses, required this.grossProfit, required this.netProfit, required this.cashFlow});
  final double netSales; final double collected; final double purchases; final double purchaseReturns; final double supplierReturnReceivables; final double supplierPaid; final double costOfSales; final double expenses; final double grossProfit; final double netProfit; final double cashFlow;

  factory _FinancialSnapshot.fromSummary(FinancialPeriodSummary value) => _FinancialSnapshot(
    netSales: value.netSales,
    collected: value.collected,
    purchases: value.purchases,
    purchaseReturns: value.purchaseReturns,
    supplierReturnReceivables: value.supplierReturnReceivables,
    supplierPaid: value.supplierPaid,
    costOfSales: value.costOfSales,
    expenses: value.expenses,
    grossProfit: value.grossProfit,
    netProfit: value.netProfit,
    cashFlow: value.cashFlow,
  );

  factory _FinancialSnapshot.fromStore(AppDataStore store, String period) {
    final now = DateTime.now();
    DateTime? start;
    DateTime? end;
    if (period == 'today') {
      start = DateTime(now.year, now.month, now.day);
      end = start.add(const Duration(days: 1));
    } else if (period == 'week') {
      start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
      end = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    } else if (period == 'month') {
      start = DateTime(now.year, now.month, 1);
      end = now.month == 12 ? DateTime(now.year + 1, 1, 1) : DateTime(now.year, now.month + 1, 1);
    }
    final value = store.financialSummary(start: start, end: end);
    return _FinancialSnapshot(
      netSales: value.netSales,
      collected: value.collected,
      purchases: value.purchases,
      purchaseReturns: value.purchaseReturns,
      supplierReturnReceivables: value.supplierReturnReceivables,
      supplierPaid: value.supplierPaid,
      costOfSales: value.costOfSales,
      expenses: value.expenses,
      grossProfit: value.grossProfit,
      netProfit: value.netProfit,
      cashFlow: value.cashFlow,
    );
  }
}

class _Activity {
  const _Activity(this.date, this.icon, this.color, this.title, this.amount, this.actor);
  final DateTime date; final IconData icon; final Color color; final String title; final String amount; final String actor;
}
String _dateTime(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} • ${formatHour12(d)}';
