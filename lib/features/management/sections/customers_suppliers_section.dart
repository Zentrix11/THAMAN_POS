import 'package:flutter/material.dart';
import '../../../app/app_theme.dart';
import '../../../core/app_strings.dart';
import '../../../core/app_controller.dart';
import '../../../core/widgets/surface_card.dart';
import '../../../core/printing/print_service.dart';
import '../../../core/printing/print_templates.dart';
import '../../../data/app_data_store.dart';
import '../../../data/models.dart';
import '../widgets/management_widgets.dart';

class CustomersSection extends StatefulWidget {
  const CustomersSection({super.key, required this.s});
  final AppStrings s;
  @override State<CustomersSection> createState() => _CustomersSectionState();
}

class _CustomersSectionState extends State<CustomersSection> {
  final search = TextEditingController();
  @override void dispose() { search.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final store = AppDataStore.instance;
    final s = widget.s;
    final controller = AppScope.of(context);
    final canManage = controller.role == UserRole.owner || controller.role == UserRole.manager;
    return AnimatedBuilder(animation: store, builder: (_, __) {
      final q = search.text.trim().toLowerCase();
      final data = store.customers.where((c) => q.isEmpty || c.name.toLowerCase().contains(q) || c.phone.contains(q) || c.accountNumber.toLowerCase().contains(q) || c.note.toLowerCase().contains(q)).toList();
      return Column(children: [
        ManagementMetricsGrid(items: [
          ManagementMetric(s.text('العملاء النشطون', 'Active customers'), '${store.customers.where((c) => c.active).length}', Icons.groups_outlined, AppColors.primary),
          ManagementMetric(s.text('مبالغ لنا عند العملاء', 'Receivables'), '${store.totalReceivables.toStringAsFixed(2)} ${store.settings.currency}', Icons.account_balance_wallet_outlined, AppColors.danger),
          ManagementMetric(s.text('دفعات العملاء', 'Customer payments'), '${store.totalCustomerPayments.toStringAsFixed(2)} ${store.settings.currency}', Icons.payments_outlined, AppColors.success),
          ManagementMetric(s.text('حسابات آجلة', 'Credit accounts'), '${store.customers.where((c) => c.active && c.creditAllowed).length}', Icons.credit_score_outlined, AppColors.accent),
        ]),
        const SizedBox(height: 12),
        SurfaceCard(padding: EdgeInsets.zero, child: Column(children: [
          SectionCardHeader(
            title: s.text('ملفات العملاء', 'Customer profiles'),
            subtitle: s.text('المالك والمدير فقط يضيفان العملاء. العميل النشط يظهر تلقائيًا للكاشير.', 'Only owner/manager can add customers. Active customers appear automatically in POS.'),
            trailing: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (canManage) FilledButton.icon(onPressed: () => _customerDialog(context), icon: const Icon(Icons.person_add_alt_1_rounded, size: 17), label: Text(s.text('إضافة عميل', 'Add customer'))),
              SearchField(controller: search, hint: s.text('اسم، هاتف، رقم حساب...', 'Name, phone, account...'), onChanged: (_) => setState(() {}), width: 270),
            ]),
          ),
          const Divider(height: 1),
          if (data.isEmpty) EmptyPanel(message: s.text('لا توجد نتائج.', 'No matching customers.')) else for (final c in data) ...[
            ListTile(
              onTap: () => _details(context, c, canManage),
              leading: Stack(clipBehavior: Clip.none, children: [
                CircleAvatar(backgroundColor: AppColors.primarySoft, child: Text(c.name.isEmpty ? 'C' : c.name.substring(0, 1), style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w900))),
                if (!c.active) const PositionedDirectional(end: -3, bottom: -2, child: Icon(Icons.block_rounded, size: 15, color: AppColors.danger)),
              ]),
              title: Text('${c.name} • ${c.accountNumber}', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900)),
              subtitle: Text('${c.phone} • ${c.address}${c.creditAllowed ? ' • ${s.text('آجل', 'Credit')}' : ''}', style: const TextStyle(fontSize: 8.8, color: AppColors.muted)),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${_customerPurchases(store, c).toStringAsFixed(2)} ${store.settings.currency}', style: const TextStyle(fontSize: 9.8, fontWeight: FontWeight.w900)),
                Text(c.balance > 0 ? '${s.text('مستحق', 'Due')}: ${c.balance.toStringAsFixed(2)}' : s.text('مسدد', 'Settled'), style: TextStyle(fontSize: 8, color: c.balance > 0 ? AppColors.danger : AppColors.success, fontWeight: FontWeight.w800)),
              ]),
            ),
            if (c != data.last) const Divider(height: 1),
          ],
        ])),
      ]);
    });
  }

  Future<void> _customerDialog(BuildContext context, {CustomerRecord? customer}) async {
    final store = AppDataStore.instance;
    final s = widget.s;
    final controller = AppScope.of(context);
    final role = controller.role?.name ?? '';
    if (role != 'owner' && role != 'manager') return;

    final name = TextEditingController(text: customer?.name ?? '');
    final phone = TextEditingController(text: customer?.phone ?? '');
    final address = TextEditingController(text: customer?.address ?? '');
    final limit = TextEditingController(text: customer == null || customer.creditLimit == 0 ? '' : customer.creditLimit.toStringAsFixed(2));
    final opening = TextEditingController();
    final note = TextEditingController(text: customer?.note ?? '');
    var creditAllowed = customer?.creditAllowed ?? false;
    var active = customer?.active ?? true;
    String? error;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (dialogContext, setDialogState) {
        return AlertDialog(
          scrollable: true,
          title: Text(customer == null ? s.text('إضافة عميل جديد', 'Add customer') : s.text('تعديل العميل', 'Edit customer')),
          content: SizedBox(width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 560.0).toDouble(), child: SingleChildScrollView(child: Column(children: [
            TextField(controller: name, autofocus: true, decoration: InputDecoration(labelText: s.text('اسم العميل *', 'Customer name *'), prefixIcon: const Icon(Icons.person_outline_rounded))),
            const SizedBox(height: 10),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: s.text('رقم الهاتف *', 'Phone number *'), prefixIcon: const Icon(Icons.phone_outlined))),
            const SizedBox(height: 10),
            TextField(controller: address, decoration: InputDecoration(labelText: s.text('العنوان', 'Address'), prefixIcon: const Icon(Icons.location_on_outlined))),
            const SizedBox(height: 10),
            SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, value: creditAllowed, onChanged: (v) => setDialogState(() => creditAllowed = v), title: Text(s.text('السماح بالشراء بالدين', 'Allow credit sales'), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800)), subtitle: Text(s.text('عند تعطيله لا يستطيع الكاشير تسجيل فاتورة آجلة لهذا العميل.', 'When disabled, POS cannot create a credit sale for this customer.'), style: const TextStyle(fontSize: 8.5, color: AppColors.muted))),
            if (creditAllowed) ...[
              TextField(controller: limit, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: s.text('حد الائتمان (0 = بدون حد)', 'Credit limit (0 = unlimited)'), prefixIcon: const Icon(Icons.credit_score_outlined))),
              if (customer == null) ...[
                const SizedBox(height: 10),
                TextField(controller: opening, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: s.text('رصيد افتتاحي مستحق', 'Opening receivable'), helperText: s.text('استخدمه فقط إذا كان على العميل دين سابق قبل إدخاله للنظام.', 'Use only for debt that existed before adding the customer.'))),
              ],
            ],
            const SizedBox(height: 10),
            TextField(controller: note, maxLines: 3, decoration: InputDecoration(labelText: s.text('ملاحظة', 'Note'), prefixIcon: const Icon(Icons.sticky_note_2_outlined))),
            if (customer != null) ...[
              const SizedBox(height: 8),
              SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, value: active, onChanged: (v) => setDialogState(() => active = v), title: Text(s.text('حساب العميل نشط', 'Customer account active'), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800))),
            ],
            if (error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(error!, style: const TextStyle(fontSize: 9, color: AppColors.danger, fontWeight: FontWeight.w800))),
          ]))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(s.text('إلغاء', 'Cancel'))),
            FilledButton.icon(
              onPressed: () {
                final creditLimit = double.tryParse(limit.text.trim()) ?? 0;
                final openingBalance = double.tryParse(opening.text.trim()) ?? 0;
                bool ok;
                if (customer == null) {
                  ok = store.addCustomer(name: name.text, phone: phone.text, address: address.text, creditAllowed: creditAllowed, creditLimit: creditLimit, openingBalance: openingBalance, note: note.text, actorName: controller.currentUserName, actorRole: role) != null;
                } else {
                  ok = store.updateCustomer(customerId: customer.id, name: name.text, phone: phone.text, address: address.text, creditAllowed: creditAllowed, creditLimit: creditLimit, note: note.text, active: active, actorName: controller.currentUserName, actorRole: role);
                }
                if (!ok) {
                  setDialogState(() => error = s.text('تعذر الحفظ. تأكد من الاسم والهاتف وعدم تكرار الهاتف وأن الدين لا يتجاوز حد الائتمان.', 'Could not save. Check required fields, duplicate phone, and credit limit.'));
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              icon: const Icon(Icons.save_outlined, size: 17),
              label: Text(s.text('حفظ العميل', 'Save customer')),
            ),
          ],
        );
      }),
    );
    name.dispose(); phone.dispose(); address.dispose(); limit.dispose(); opening.dispose(); note.dispose();
    if (saved == true && mounted) setState(() {});
  }

  void _details(BuildContext context, CustomerRecord c, bool canManage) {
    final store = AppDataStore.instance;
    final s = widget.s;
    final invoices = store.invoices.where((i) => i.customerId == c.id || i.customer == c.name).toList();
    final payments = store.customerPayments.where((p) => p.customerId == c.id).toList();
    showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
          scrollable: true,
      title: Row(children: [Expanded(child: Text(c.name)), if (!c.active) Chip(label: Text(s.text('غير نشط', 'Inactive')))]),
      content: SizedBox(width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 700.0).toDouble(), child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        DetailLine(label: s.text('رقم الحساب', 'Account'), value: c.accountNumber),
        DetailLine(label: s.text('الهاتف', 'Phone'), value: c.phone),
        DetailLine(label: s.text('العنوان', 'Address'), value: c.address),
        DetailLine(label: s.text('المبلغ المستحق لنا', 'Receivable'), value: '${c.balance.toStringAsFixed(2)} ${store.settings.currency}'),
        DetailLine(label: s.text('الشراء بالدين', 'Credit sales'), value: c.creditAllowed ? s.text('مسموح', 'Allowed') : s.text('غير مسموح', 'Not allowed')),
        if (c.creditAllowed) DetailLine(label: s.text('حد الائتمان', 'Credit limit'), value: c.creditLimit <= 0 ? s.text('بدون حد', 'Unlimited') : '${c.creditLimit.toStringAsFixed(2)} ${store.settings.currency}'),
        if (c.note.trim().isNotEmpty) DetailLine(label: s.text('الملاحظة', 'Note'), value: c.note),
        DetailLine(label: s.text('نقاط الولاء', 'Loyalty points'), value: '${c.loyaltyPoints}'),
        const Divider(height: 22),
        Text(s.text('الفواتير', 'Invoices'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        if (invoices.isEmpty) Text(s.text('لا توجد فواتير مرتبطة.', 'No linked invoices.'), style: const TextStyle(fontSize: 9, color: AppColors.muted)) else for (final i in invoices) Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(11)), child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${i.number} • ${formatDateTime(i.createdAt)}', style: const TextStyle(fontSize: 8.8, fontWeight: FontWeight.w800)), Text('${s.paymentMethod(i.paymentMethod)} • ${s.text('مدفوع', 'Paid')}: ${i.receivedAtSale.toStringAsFixed(2)} • ${s.text('آجل', 'Due')}: ${i.dueAmount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 7.7, color: AppColors.muted))])), Text('${i.total.toStringAsFixed(2)} ${store.settings.currency}', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900))])),
        const Divider(height: 22),
        Text(s.text('دفعات لاحقة', 'Later payments'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        if (payments.isEmpty) Text(s.text('لا توجد دفعات لاحقة مسجلة.', 'No later payments recorded.'), style: const TextStyle(fontSize: 9, color: AppColors.muted)) else for (final p in payments) ListTile(contentPadding: EdgeInsets.zero, dense: true, title: Text('${p.amount.toStringAsFixed(2)} ${store.settings.currency} • ${s.paymentMethod(p.method)}', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900)), subtitle: Text('${formatDateTime(p.createdAt)} • ${p.employeeName}', style: const TextStyle(fontSize: 8, color: AppColors.muted))),
      ]))),
      actions: [
        OutlinedButton.icon(onPressed: () => ThamanPrintService.printDocument(ThamanPrintTemplates.customerStatement(store, c, isArabic: s.controller.isArabic)), icon: const Icon(Icons.print_outlined, size: 16), label: Text(s.text('طباعة كشف', 'Print statement'))),
        if (canManage) OutlinedButton.icon(onPressed: () { Navigator.pop(dialogContext); _customerDialog(context, customer: c); }, icon: const Icon(Icons.edit_outlined, size: 16), label: Text(s.text('تعديل', 'Edit'))),
        FilledButton(onPressed: () => Navigator.pop(dialogContext), child: Text(s.text('إغلاق', 'Close'))),
      ],
    ));
  }
}

double _customerPurchases(AppDataStore store, CustomerRecord c) => store.invoices.where((i) => i.customerId == c.id || i.customer == c.name).fold<double>(0, (a, b) => a + b.total);

class SuppliersSection extends StatefulWidget {
  const SuppliersSection({super.key, required this.s});
  final AppStrings s;
  @override State<SuppliersSection> createState() => _SuppliersSectionState();
}

class _SuppliersSectionState extends State<SuppliersSection> {
  final search = TextEditingController();
  @override void dispose() { search.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final store = AppDataStore.instance;
    final s = widget.s;
    final controller = AppScope.of(context);
    final canManage = controller.role == UserRole.owner || controller.role == UserRole.manager;
    return AnimatedBuilder(animation: store, builder: (_, __) {
      final q = search.text.trim().toLowerCase();
      final data = store.suppliers.where((sup) => q.isEmpty || sup.name.toLowerCase().contains(q) || sup.accountNumber.toLowerCase().contains(q) || sup.phone.contains(q)).toList();
      return Column(children: [
        ManagementMetricsGrid(items: [
          ManagementMetric(s.text('الموردون', 'Suppliers'), '${store.suppliers.length}', Icons.local_shipping_outlined, AppColors.primary),
          ManagementMetric(s.text('إجمالي المشتريات', 'Purchases'), '${store.purchasesValue.toStringAsFixed(2)} ${store.settings.currency}', Icons.payments_outlined, AppColors.blue),
          ManagementMetric(s.text('مدفوع للموردين', 'Paid to suppliers'), '${store.totalSupplierPaid.toStringAsFixed(2)} ${store.settings.currency}', Icons.price_check_outlined, AppColors.success),
          ManagementMetric(s.text('علينا للموردين', 'Supplier payables'), '${store.totalPayables.toStringAsFixed(2)} ${store.settings.currency}', Icons.schedule_outlined, AppColors.danger),
        ]),
        const SizedBox(height: 12),
        SurfaceCard(padding: EdgeInsets.zero, child: Column(children: [
          SectionCardHeader(
            title: s.text('سجل الموردين', 'Supplier register'),
            subtitle: s.text('كشف مشتريات ودفعات ورصيد مستحق لكل مورد.', 'Purchase, payment and outstanding-balance ledger for each supplier.'),
            trailing: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (canManage)
                  FilledButton.icon(
                    onPressed: () => _supplierDialog(context),
                    icon: const Icon(Icons.add_business_rounded, size: 17),
                    label: Text(s.text('إضافة مورد', 'Add supplier')),
                  ),
                SearchField(
                  controller: search,
                  hint: s.text('اسم، رقم حساب، هاتف...', 'Name, account, phone...'),
                  onChanged: (_) => setState(() {}),
                  width: 250,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (data.isEmpty) EmptyPanel(message: s.text('لا توجد نتائج.', 'No results.')) else for (final sup in data) ...[
            Builder(builder: (_) {
              final receipts = store.purchases.where((p) => p.supplierId == sup.id || (p.supplierId.isEmpty && p.supplier == sup.name)).toList();
              final total = receipts.fold<double>(0, (a, b) => a + b.total);
              final balance = store.supplierBalance(sup.id);
              return ListTile(onTap: () => _details(context, sup, receipts), leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.local_shipping_outlined, color: AppColors.primary, size: 19)), title: Text('${sup.name} • ${sup.accountNumber}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900)), subtitle: Text('${receipts.length} ${s.text('فاتورة شراء', 'purchases')} • ${sup.phone}', style: const TextStyle(fontSize: 8.4, color: AppColors.muted)), trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [Text('${total.toStringAsFixed(2)} ${store.settings.currency}', style: const TextStyle(fontSize: 9.6, fontWeight: FontWeight.w900)), Text(balance > 0 ? '${s.text('علينا', 'Due')}: ${balance.toStringAsFixed(2)}' : s.text('مسدد', 'Settled'), style: TextStyle(fontSize: 7.8, color: balance > 0 ? AppColors.danger : AppColors.success, fontWeight: FontWeight.w800))]));
            }),
            if (sup != data.last) const Divider(height: 1),
          ],
        ])),
      ]);
    });
  }

  Future<void> _supplierDialog(BuildContext context) async {
    final store = AppDataStore.instance;
    final s = widget.s;
    final controller = AppScope.of(context);
    final role = controller.role?.name ?? '';
    if (role != 'owner' && role != 'manager') return;

    final name = TextEditingController();
    final phone = TextEditingController();
    final address = TextEditingController();
    final opening = TextEditingController();
    String? error;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          scrollable: true,
          title: Text(s.text('إضافة مورد جديد', 'Add supplier')),
          content: SizedBox(
            width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 560.0).toDouble(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: s.text('اسم المورد *', 'Supplier name *'),
                    prefixIcon: const Icon(Icons.local_shipping_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: s.text('رقم الهاتف', 'Phone number'),
                    prefixIcon: const Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: address,
                  decoration: InputDecoration(
                    labelText: s.text('العنوان', 'Address'),
                    prefixIcon: const Icon(Icons.location_on_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: opening,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: s.text('رصيد افتتاحي مستحق للمورد', 'Opening payable'),
                    helperText: s.text(
                      'استخدمه فقط إذا كان للمورد رصيد سابق قبل إدخاله للنظام.',
                      'Use only for a supplier balance that existed before adding the supplier.',
                    ),
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      error!,
                      style: const TextStyle(
                        fontSize: 9,
                        color: AppColors.danger,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(s.text('إلغاء', 'Cancel')),
            ),
            FilledButton.icon(
              onPressed: () {
                final openingBalance = double.tryParse(opening.text.trim()) ?? 0;
                final result = store.addSupplier(
                  name: name.text,
                  phone: phone.text,
                  address: address.text,
                  openingBalance: openingBalance,
                  actorName: controller.currentUserName,
                  actorRole: role,
                );
                if (result == null) {
                  setDialogState(() {
                    error = s.text(
                      'تحقق من اسم المورد، وعدم تكرار الاسم أو رقم الهاتف، وأن الرصيد الافتتاحي صحيح.',
                      'Check the supplier name, duplicate name/phone, and opening balance.',
                    );
                  });
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              icon: const Icon(Icons.save_outlined, size: 17),
              label: Text(s.text('حفظ المورد', 'Save supplier')),
            ),
          ],
        ),
      ),
    );

    name.dispose();
    phone.dispose();
    address.dispose();
    opening.dispose();

    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.text('تمت إضافة المورد.', 'Supplier added.'))),
      );
    }
  }

  Future<bool> _recordSupplierPayment(BuildContext context, SupplierRecord supplier) async {
    final s = widget.s;
    final store = AppDataStore.instance;
    final balance = store.supplierBalance(supplier.id);
    if (balance <= 0.005) return false;
    final amount = TextEditingController(text: balance.toStringAsFixed(2));
    final note = TextEditingController();
    String method = 'Cash';
    String? error;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setD) => AlertDialog(
          scrollable: true,
          title: Text(s.text('تسديد مستحقات المورد', 'Settle supplier balance')),
          content: SizedBox(
            width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 520.0).toDouble(),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  '${supplier.name} • ${s.text('المستحق', 'Due')}: ${balance.toStringAsFixed(2)} ${store.settings.currency}',
                  style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: s.text('المبلغ المراد تسديده', 'Amount to pay')),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: method,
                decoration: InputDecoration(labelText: s.text('طريقة الدفع', 'Payment method')),
                items: const ['Cash', 'Bank', 'Card', 'Wallet']
                    .map((v) => DropdownMenuItem(value: v, child: Text(s.paymentMethod(v))))
                    .toList(),
                onChanged: (v) => setD(() => method = v ?? method),
              ),
              const SizedBox(height: 10),
              TextField(controller: note, decoration: InputDecoration(labelText: s.text('ملاحظة', 'Note'))),
              if (error != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(error!, style: const TextStyle(color: AppColors.danger, fontSize: 9, fontWeight: FontWeight.w700)),
                ),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(s.text('إلغاء', 'Cancel'))),
            FilledButton.icon(
              onPressed: () {
                final value = double.tryParse(amount.text.trim()) ?? 0;
                final payment = store.recordSupplierPayment(
                  supplierId: supplier.id,
                  amount: value,
                  method: method,
                  employeeName: s.controller.currentUserName,
                  note: note.text.trim(),
                );
                if (payment == null) {
                  setD(() => error = s.text('تحقق من المبلغ؛ يجب ألا يتجاوز الرصيد المستحق.', 'Check the amount; it cannot exceed the outstanding balance.'));
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              icon: const Icon(Icons.payments_outlined, size: 17),
              label: Text(s.text('تسجيل التسديد', 'Record payment')),
            ),
          ],
        ),
      ),
    );
    amount.dispose();
    note.dispose();
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.text('تم تسجيل دفعة المورد وتحديث الرصيد.', 'Supplier payment recorded and balance updated.'))));
    }
    return saved == true;
  }

  void _details(BuildContext context, SupplierRecord supplier, List<PurchaseReceipt> receipts) {
    final s = widget.s;
    final store = AppDataStore.instance;
    final payments = store.supplierPayments.where((p) => p.supplierId == supplier.id).toList();
    showDialog<void>(context: context, builder: (_) => AlertDialog(
          scrollable: true,
      title: Text(supplier.name),
      content: SizedBox(width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 680.0).toDouble(), child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        DetailLine(label: s.text('رقم الحساب', 'Account'), value: supplier.accountNumber),
        DetailLine(label: s.text('الهاتف', 'Phone'), value: supplier.phone),
        DetailLine(label: s.text('العنوان', 'Address'), value: supplier.address),
        DetailLine(label: s.text('الرصيد المستحق علينا', 'Outstanding payable'), value: '${store.supplierBalance(supplier.id).toStringAsFixed(2)} ${store.settings.currency}'),
        const Divider(height: 22),
        Text(s.text('فواتير الشراء', 'Purchase invoices'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        if (receipts.isEmpty) Text(s.text('لا توجد مشتريات مرتبطة.', 'No linked purchases.'), style: const TextStyle(fontSize: 9, color: AppColors.muted)) else for (final r in receipts) Container(margin: const EdgeInsets.only(bottom: 7), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(11)), child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(r.number, style: const TextStyle(fontSize: 9.2, fontWeight: FontWeight.w900)), Text('${r.employeeName} • ${formatDateTime(r.createdAt)} • ${s.text('متبقي', 'Due')}: ${store.purchaseOutstanding(r).toStringAsFixed(2)}', style: const TextStyle(fontSize: 8, color: AppColors.muted))])), Text('${r.total.toStringAsFixed(2)} ${store.settings.currency}', style: const TextStyle(fontSize: 9.4, fontWeight: FontWeight.w900))])),
        const Divider(height: 22),
        Text(s.text('الدفعات', 'Payments'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        if (payments.isEmpty) Text(s.text('لا توجد دفعات إضافية مسجلة.', 'No additional payments recorded.'), style: const TextStyle(fontSize: 9, color: AppColors.muted)) else for (final p in payments) ListTile(contentPadding: EdgeInsets.zero, dense: true, title: Text('${p.amount.toStringAsFixed(2)} ${store.settings.currency} • ${s.paymentMethod(p.method)}', style: const TextStyle(fontSize: 9.2, fontWeight: FontWeight.w900)), subtitle: Text('${formatDateTime(p.createdAt)} • ${p.employeeName}${p.purchaseNumber.isNotEmpty ? ' • ${p.purchaseNumber}' : ''}', style: const TextStyle(fontSize: 8, color: AppColors.muted))),
      ]))),
      actions: [
        OutlinedButton.icon(onPressed: () => ThamanPrintService.printDocument(ThamanPrintTemplates.supplierStatement(store, supplier, isArabic: s.controller.isArabic)), icon: const Icon(Icons.print_outlined, size: 16), label: Text(s.text('طباعة كشف', 'Print statement'))),
        if (store.supplierBalance(supplier.id) > 0.005 && const [UserRole.owner, UserRole.manager, UserRole.accountant].contains(AppScope.of(context).role))
          FilledButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              await _recordSupplierPayment(context, supplier);
            },
            icon: const Icon(Icons.payments_outlined, size: 16),
            label: Text(s.text('تسديد', 'Pay')),
          ),
        FilledButton(onPressed: () => Navigator.pop(context), child: Text(s.text('إغلاق', 'Close'))),
      ],
    ));
  }
}
