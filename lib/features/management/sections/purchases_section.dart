import 'package:flutter/material.dart';

import '../../../core/app_controller.dart';
import '../../../app/app_theme.dart';
import '../../../core/app_strings.dart';
import '../../../core/widgets/surface_card.dart';
import '../../../core/printing/print_document.dart';
import '../../../core/printing/print_service.dart';
import '../../../core/printing/print_templates.dart';
import '../../../data/app_data_store.dart';
import '../../../data/models.dart';
import '../widgets/management_widgets.dart';

class PurchasesSection extends StatefulWidget {
  const PurchasesSection({super.key, required this.s});
  final AppStrings s;

  @override
  State<PurchasesSection> createState() => _PurchasesSectionState();
}

class _PurchasesSectionState extends State<PurchasesSection> {
  final search = TextEditingController();
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = AppDataStore.instance;
    final s = widget.s;
    return AnimatedBuilder(
      animation: store,
      builder: (_, __) {
        final q = search.text.trim().toLowerCase();
        final data = store.purchases.where((p) {
          if (q.isEmpty) return true;
          if (p.number.toLowerCase().contains(q) ||
              p.title.toLowerCase().contains(q) ||
              p.employeeName.toLowerCase().contains(q) ||
              p.employeeId.toLowerCase().contains(q) ||
              p.supplier.toLowerCase().contains(q) ||
              p.vendorInvoiceNumber.toLowerCase().contains(q) ||
              p.total.toString().contains(q)) return true;
          return p.lines.any((l) =>
              l.itemName.toLowerCase().contains(q) ||
              l.quantity.toString() == q ||
              l.purchaseUnit.toLowerCase().contains(q) ||
              l.total.toString().contains(q));
        }).toList();
        final notes = store.productNotes
            .where((n) =>
                n.active &&
                (n.audience == 'purchasing' || n.audience == 'both'))
            .toList();
        final outstanding = store.purchases
            .fold<double>(0, (sum, p) => sum + store.purchaseOutstanding(p));
        return Column(children: [
          ManagementMetricsGrid(items: [
            ManagementMetric(
                s.text('فواتير الشراء', 'Purchase invoices'),
                '${store.purchases.length}',
                Icons.shopping_cart_checkout_outlined,
                AppColors.primary),
            ManagementMetric(
                s.text('قيمة المشتريات', 'Purchase value'),
                '${store.purchasesValue.toStringAsFixed(2)} ${store.settings.currency}',
                Icons.payments_outlined,
                AppColors.blue),
            ManagementMetric(
                s.text('المدفوع عند الشراء', 'Paid at purchase'),
                '${store.purchases.fold<double>(0, (sum, p) => sum + p.amountPaid).toStringAsFixed(2)} ${store.settings.currency}',
                Icons.price_check_outlined,
                AppColors.success),
            ManagementMetric(
                s.text('متبقي على الفواتير', 'Invoice outstanding'),
                '${outstanding.toStringAsFixed(2)} ${store.settings.currency}',
                Icons.schedule_outlined,
                AppColors.danger),
            ManagementMetric(
                s.text('مرتجعات المشتريات', 'Purchase returns'),
                '${store.purchaseReturnsValue.toStringAsFixed(2)} ${store.settings.currency}',
                Icons.assignment_return_outlined,
                AppColors.accent),
          ]),
          const SizedBox(height: 12),
          if (notes.isNotEmpty) ...[
            SurfaceCard(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(
                      s.text('ملاحظات موجهة لمسؤول الشراء',
                          'Notes for purchasing'),
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  for (final n in notes.take(5))
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(children: [
                          const Icon(Icons.sticky_note_2_outlined,
                              size: 16, color: AppColors.accent),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(
                                  '${store.productOrNull(n.productId) == null ? n.productId : s.text(store.product(n.productId).nameAr, store.product(n.productId).nameEn)}: ${n.text}',
                                  style: const TextStyle(
                                      fontSize: 8.8,
                                      fontWeight: FontWeight.w700))),
                          Text(n.createdBy,
                              style: const TextStyle(
                                  fontSize: 8, color: AppColors.muted))
                        ])),
                ])),
            const SizedBox(height: 12),
          ],
          SurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              SectionCardHeader(
                title: s.text('سجل المشتريات والاستلام',
                    'Purchases & receiving register'),
                subtitle: s.text(
                    'المورد، الموظف المستلم، الوحدات، تكلفة الشراء، المدفوع والمتبقي.',
                    'Supplier, receiving employee, units, purchase cost, paid and outstanding amounts.'),
                trailing: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      SearchField(
                          controller: search,
                          hint: s.text('صنف، موظف، مورد، فاتورة...',
                              'Item, employee, supplier, invoice...'),
                          onChanged: (_) => setState(() {}),
                          width: 270),
                      OutlinedButton.icon(
                          onPressed: data.isEmpty
                              ? null
                              : () => _printPurchaseRegister(data),
                          icon: const Icon(Icons.print_outlined, size: 17),
                          label: Text(s.text('طباعة السجل', 'Print register'))),
                      FilledButton.icon(
                          onPressed: () => _newPurchase(context),
                          icon: const Icon(Icons.add_shopping_cart_rounded,
                              size: 17),
                          label: Text(s.text('فاتورة شراء', 'New purchase'))),
                    ]),
              ),
              const Divider(height: 1),
              if (data.isEmpty)
                EmptyPanel(
                    message: s.text('لا توجد نتائج مطابقة.',
                        'No matching purchase receipts.'))
              else
                for (final p in data) ...[
                  ListTile(
                    onTap: () => _details(context, p),
                    leading: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                            color: AppColors.primarySoft,
                            borderRadius: BorderRadius.circular(13)),
                        child: const Icon(Icons.receipt_long_outlined,
                            color: AppColors.primary)),
                    title: Text('${p.number}${p.title.trim().isEmpty ? '' : ' • ${p.title.trim()}'} • ${p.supplier}',
                        style: const TextStyle(
                            fontSize: 10, fontWeight: FontWeight.w900)),
                    subtitle: Text(
                        '${s.text('المشتري', 'Buyer')}: ${p.employeeName.isEmpty ? p.employeeId : p.employeeName} • ${formatPurchaseWhen(p.createdAt, arabic: s.controller.isArabic)}${p.restockRequestNumber.isEmpty ? '' : ' • ${s.text('طلب', 'Request')} ${p.restockRequestNumber}'} • ${p.lines.length} ${s.text('صنف', 'items')}',
                        style: const TextStyle(
                            fontSize: 8.5, color: AppColors.muted)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                                '${p.total.toStringAsFixed(2)} ${store.settings.currency}',
                                style: const TextStyle(
                                    fontSize: 9.8,
                                    fontWeight: FontWeight.w900)),
                            InkWell(
                              onTap: store.purchaseOutstanding(p) > 0.005 ? () => _supplierDebt(context, p) : null,
                              borderRadius: BorderRadius.circular(6),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                child: Text(
                                  store.purchaseOutstanding(p) > 0.005
                                      ? '${s.text('متبقي — اضغط للتسديد', 'Due — tap to pay')}: ${store.purchaseOutstanding(p).toStringAsFixed(2)}'
                                      : s.text('مسدد', 'Settled'),
                                  style: TextStyle(
                                      fontSize: 7.8,
                                      color: store.purchaseOutstanding(p) > 0.005
                                          ? AppColors.danger
                                          : AppColors.success,
                                      decoration: store.purchaseOutstanding(p) > 0.005 ? TextDecoration.underline : null,
                                      fontWeight: FontWeight.w800),
                                ),
                              ),
                            ),
                          ]),
                      const SizedBox(width: 6),
                      PopupMenuButton<String>(
                        tooltip: s.text('خيارات فاتورة الشراء', 'Purchase invoice actions'),
                        onSelected: (value) {
                          if (value == 'return') _returnPurchase(context, p);
                          if (value == 'details') _details(context, p);
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(value: 'details', child: Text(s.text('عرض التفاصيل', 'View details'))),
                          PopupMenuItem(value: 'return', child: Text(s.text('إرجاع بضاعة للمورد', 'Return goods to supplier'))),
                        ],
                      ),
                    ]),
                  ),
                  if (p != data.last) const Divider(height: 1),
                ],
            ]),
          ),
          if (store.purchaseReturns.isNotEmpty) ...[
            const SizedBox(height: 12),
            SurfaceCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                SectionCardHeader(
                  title: s.text('سجل مرتجعات المشتريات', 'Purchase return register'),
                  subtitle: s.text('كل عملية مرتبطة بفاتورة الشراء الأصلية وتحدّث المخزون وحساب المورد.', 'Every record is linked to its source purchase and updates stock and supplier balance.'),
                ),
                const Divider(height: 1),
                for (final r in store.purchaseReturns.take(20)) ...[
                  ListTile(
                    leading: const Icon(Icons.assignment_return_outlined, color: AppColors.accent),
                    title: Text('${r.purchaseNumber} • ${s.text('متفق عليه', 'Agreed')}: ${r.agreedAmount.toStringAsFixed(2)} ${store.settings.currency}', style: const TextStyle(fontSize: 9.8, fontWeight: FontWeight.w900)),
                    subtitle: Text('${r.supplierName} • ${r.processedBy} • ${formatDateTime(r.createdAt)}${r.reason.isEmpty ? '' : ' • ${r.reason}'}\n${r.lines.map((line) => '${line.returnUnitQuantity} ${_unitLabel(s, line.returnUnit)} ${line.itemName}').join(' • ')}', style: const TextStyle(fontSize: 8.2, color: AppColors.muted)),
                    trailing: Text('${s.text('خصم دين', 'Debt')}: ${r.payableReduction.toStringAsFixed(2)}\n${s.text('دفع الآن', 'Paid now')}: ${r.paidNow.toStringAsFixed(2)}\n${s.text('الباقي', 'Remaining')}: ${r.remainingRefund.toStringAsFixed(2)}', textAlign: TextAlign.end, style: const TextStyle(fontSize: 7.8, fontWeight: FontWeight.w800)),
                  ),
                  if (r != store.purchaseReturns.take(20).last) const Divider(height: 1),
                ],
              ]),
            ),
          ],
        ]);
      },
    );
  }


  Future<void> _returnPurchase(
      BuildContext context, PurchaseReceipt purchase) async {
    final store = AppDataStore.instance;
    final s = widget.s;
    final quantityControllers = <String, TextEditingController>{};
    final selectedUnits = <String, String>{};
    final agreedAmount = TextEditingController();
    final paidNow = TextEditingController(text: '0');
    for (final line in purchase.lines) {
      quantityControllers[line.productId] = TextEditingController(text: '0');
      selectedUnits[line.productId] = line.purchaseUnit;
    }
    final reason = TextEditingController();
    String? error;
    var submitting = false;

    int factorFor(PurchaseLine line, String unit) {
      if (unit == line.purchaseUnit) {
        return line.unitsPerPurchaseUnit <= 0 ? 1 : line.unitsPerPurchaseUnit;
      }
      return 1;
    }

    List<String> unitsFor(PurchaseLine line) {
      final values = <String>[line.purchaseUnit, line.saleUnit];
      final out = <String>[];
      for (final value in values) {
        if (value.trim().isNotEmpty && !out.contains(value)) out.add(value);
      }
      return out.isEmpty ? <String>['piece'] : out;
    }

    int enteredQuantity(PurchaseLine line) => int.tryParse(
            quantityControllers[line.productId]?.text.trim() ?? '0') ??
        0;

    int baseQuantity(PurchaseLine line) {
      final unit = selectedUnits[line.productId] ?? line.purchaseUnit;
      return enteredQuantity(line) * factorFor(line, unit);
    }

    double calculatedInventoryValue() {
      var total = 0.0;
      for (final line in purchase.lines) {
        final qty = baseQuantity(line);
        if (qty > 0) total += qty * purchase.landedBaseUnitCost(line);
      }
      return total;
    }

    double effectiveAgreedAmount() {
      final typed = double.tryParse(agreedAmount.text.trim());
      return typed == null || typed <= 0 ? calculatedInventoryValue() : typed;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, setD) {
          final inventoryValue = calculatedInventoryValue();
          final due = store.purchaseOutstanding(purchase);
          var agreed = effectiveAgreedAmount();
          final typedPaid = (double.tryParse(paidNow.text.trim()) ?? 0)
              .clamp(0, double.infinity)
              .toDouble();
          final availableBeforeRaise =
              (agreed - agreed.clamp(0, due)).clamp(0, double.infinity).toDouble();
          if (typedPaid > availableBeforeRaise + 0.005) {
            agreed = due + typedPaid;
          }
          final debtReduction = agreed.clamp(0, due).toDouble();
          final refundDue =
              (agreed - debtReduction).clamp(0, double.infinity).toDouble();
          final paid = typedPaid.clamp(0, refundDue).toDouble();
          final remaining =
              (refundDue - paid).clamp(0, double.infinity).toDouble();
          final paidOverflow = false;

          return AlertDialog(
            scrollable: true,
            title: Text(s.text(
                'إرجاع بضاعة مشتراة • ${purchase.number}',
                'Return purchased goods • ${purchase.number}')),
            content: SizedBox(
              width: (MediaQuery.sizeOf(dialogContext).width - 48)
                  .clamp(0.0, 760.0)
                  .toDouble(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: AppColors.accentSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      s.text(
                        'حدد وحدة الإرجاع والكمية لكل صنف، ثم أدخل المبلغ المتفق عليه مع المورد وكم دفع الآن. النظام يحسب خصم الدين والمبلغ المتبقي للمورد تلقائيًا.',
                        'Choose the return unit and quantity for each item, then enter the agreed supplier refund and how much was paid now. Debt reduction and the remaining supplier refund are calculated automatically.',
                      ),
                      style: const TextStyle(
                          fontSize: 8.7, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final line in purchase.lines) ...[
                    Builder(builder: (_) {
                      final available =
                          store.availablePurchaseReturnQuantity(purchase, line);
                      final product = store.productOrNull(line.productId);
                      final stock = product?.stock ?? 0;
                      final maxBaseReturn = available < stock ? available : stock;
                      final selected =
                          selectedUnits[line.productId] ?? line.purchaseUnit;
                      final factor = factorFor(line, selected);
                      final maxReturn = factor <= 0 ? 0 : maxBaseReturn ~/ factor;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceAlt,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(line.itemName,
                                style: const TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w900)),
                            const SizedBox(height: 4),
                            Text(
                              '${s.text('المتاح بالقطع', 'Returnable base units')}: $available • ${s.text('المتوفر بالمخزون', 'In stock')}: $stock • ${s.text('تكلفة القطعة', 'Base unit cost')}: ${purchase.landedBaseUnitCost(line).toStringAsFixed(2)} ${store.settings.currency}',
                              style: const TextStyle(
                                  fontSize: 8.0, color: AppColors.muted),
                            ),
                            const SizedBox(height: 8),
                            Row(children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: selected,
                                  decoration: InputDecoration(
                                    labelText:
                                        s.text('وحدة الإرجاع', 'Return unit'),
                                    isDense: true,
                                  ),
                                  items: unitsFor(line)
                                      .map((unit) => DropdownMenuItem(
                                            value: unit,
                                            child: Text(_unitLabel(s, unit)),
                                          ))
                                      .toList(),
                                  onChanged: (value) {
                                    if (value == null) return;
                                    setD(() {
                                      selectedUnits[line.productId] = value;
                                      quantityControllers[line.productId]?.text =
                                          '0';
                                      error = null;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller:
                                      quantityControllers[line.productId],
                                  keyboardType: TextInputType.number,
                                  enabled: maxReturn > 0,
                                  onChanged: (_) => setD(() {
                                    error = null;
                                    if (agreedAmount.text.trim().isEmpty) {
                                      final value = calculatedInventoryValue();
                                      if (value > 0) {
                                        agreedAmount.text = value.toStringAsFixed(2);
                                      }
                                    }
                                  }),
                                  decoration: InputDecoration(
                                    labelText: s.text('الكمية', 'Qty'),
                                    helperText:
                                        '${s.text('الحد', 'Max')}: $maxReturn ${_unitLabel(s, selected)}',
                                    isDense: true,
                                  ),
                                ),
                              ),
                            ]),
                            if (factor > 1) ...[
                              const SizedBox(height: 5),
                              Text(
                                '${s.text('كل', 'Each')} ${_unitLabel(s, selected)} = $factor ${_unitLabel(s, line.saleUnit)}',
                                style: const TextStyle(
                                    fontSize: 7.8, color: AppColors.muted),
                              ),
                            ],
                          ],
                        ),
                      );
                    }),
                  ],
                  const SizedBox(height: 4),
                  TextField(
                    controller: agreedAmount,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setD(() => error = null),
                    decoration: InputDecoration(
                      labelText: s.text('المبلغ المتفق أن يرجعه المورد',
                          'Agreed supplier refund'),
                      helperText:
                          '${s.text('قيمة البضاعة', 'Goods value')}: ${inventoryValue.toStringAsFixed(2)} • ${s.text('متبقي الفاتورة للمورد', 'Invoice still due to supplier')}: ${due.toStringAsFixed(2)} ${store.settings.currency}',
                      prefixIcon:
                          const Icon(Icons.handshake_outlined, size: 18),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: paidNow,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setD(() => error = null),
                    decoration: InputDecoration(
                      labelText: s.text('المبلغ الذي دفعه المورد الآن',
                          'Amount paid by supplier now'),
                      helperText:
                          '${s.text('الحد الأقصى للنقد الآن', 'Maximum cash now')} = ${s.text('المتفق', 'agreed')} ${agreed.toStringAsFixed(2)} − ${s.text('خصم الدين', 'debt')} ${debtReduction.toStringAsFixed(2)} = ${refundDue.toStringAsFixed(2)} ${store.settings.currency}',
                      prefixIcon: const Icon(Icons.payments_outlined, size: 18),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: reason,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: s.text('سبب الإرجاع / ملاحظة',
                          'Return reason / note'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${s.text('المعادلة', 'Formula')}: ${agreed.toStringAsFixed(2)} = ${debtReduction.toStringAsFixed(2)} + ${paid.toStringAsFixed(2)} + ${remaining.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 8.4, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        Text(
                            '${s.text('قيمة المخزون المرجع', 'Returned inventory value')}: ${inventoryValue.toStringAsFixed(2)} ${store.settings.currency}',
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text(
                            '${s.text('المبلغ المتفق عليه', 'Agreed amount')}: ${agreed.toStringAsFixed(2)} ${store.settings.currency}',
                            style: const TextStyle(fontWeight: FontWeight.w900)),
                        Text(
                            '${s.text('خصم من دين المورد', 'Supplier debt reduction')}: ${debtReduction.toStringAsFixed(2)} ${store.settings.currency}',
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text(
                            '${s.text('دفع الآن', 'Paid now')}: ${paid.toStringAsFixed(2)} ${store.settings.currency}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: AppColors.success)),
                        Text(
                            '${s.text('باقي لنا عند المورد', 'Remaining supplier refund')}: ${remaining.toStringAsFixed(2)} ${store.settings.currency}',
                            style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: remaining > 0.005
                                    ? AppColors.danger
                                    : AppColors.success)),
                      ],
                    ),
                      ],
                    ),
                  ),
                  if (paidOverflow) ...[
                    const SizedBox(height: 8),
                    Text(
                      s.text(
                        'المبلغ المدفوع الآن ${typedPaid.toStringAsFixed(2)} أكبر من المتاح ${refundDue.toStringAsFixed(2)}. الحد هو المتفق ناقص خصم دين المورد.',
                        'Cash paid now ${typedPaid.toStringAsFixed(2)} exceeds the available ${refundDue.toStringAsFixed(2)}. The limit is agreed amount minus supplier debt reduction.',
                      ),
                      style: const TextStyle(
                          color: AppColors.danger,
                          fontSize: 8.8,
                          fontWeight: FontWeight.w800),
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!,
                        style: const TextStyle(
                            color: AppColors.danger,
                            fontSize: 8.8,
                            fontWeight: FontWeight.w800)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(s.text('إلغاء', 'Cancel'))),
              FilledButton.icon(
                onPressed: submitting
                    ? null
                    : () {
                  if (submitting) return;
                  setD(() => submitting = true);
                  final quantities = <String, int>{};
                  final returnUnitQuantities = <String, int>{};
                  var any = false;
                  for (final line in purchase.lines) {
                    final entered = enteredQuantity(line);
                    final selected =
                        selectedUnits[line.productId] ?? line.purchaseUnit;
                    final factor = factorFor(line, selected);
                    final qty = entered * factor;
                    final available =
                        store.availablePurchaseReturnQuantity(purchase, line);
                    final stock = store.productOrNull(line.productId)?.stock ?? 0;
                    final maxReturn = available < stock ? available : stock;
                    if (entered < 0 || qty > maxReturn) {
                      setD(() {
                        submitting = false;
                        error = s.text(
                          'تحقق من الكميات ووحدات الإرجاع؛ لا يمكن إرجاع كمية أكبر من المتاح أو الموجود فعليًا في المخزون.',
                          'Check the quantities and return units; you cannot return more than the available purchased quantity or current stock.');
                      });
                      return;
                    }
                    quantities[line.productId] = qty;
                    returnUnitQuantities[line.productId] = entered;
                    if (qty > 0) any = true;
                  }
                  if (!any) {
                    setD(() {
                      submitting = false;
                      error = s.text(
                        'أدخل كمية إرجاع لصنف واحد على الأقل.',
                        'Enter a return quantity for at least one item.');
                    });
                    return;
                  }
                  final inventoryValue = calculatedInventoryValue();
                  final dueNow = store.purchaseOutstanding(purchase);
                  var agreed = effectiveAgreedAmount();
                  var paid = double.tryParse(paidNow.text.trim()) ?? 0;
                  if (paid < 0) paid = 0;
                  final availableBeforeRaise =
                      (agreed - agreed.clamp(0, dueNow)).clamp(0, double.infinity).toDouble();
                  if (paid > availableBeforeRaise + 0.005) {
                    agreed = dueNow + paid;
                  }
                  final debtReduction = agreed.clamp(0, dueNow).toDouble();
                  final refundDue = (agreed - debtReduction)
                      .clamp(0, double.infinity)
                      .toDouble();
                  if (agreed <= 0 || inventoryValue <= 0) {
                    setD(() {
                      submitting = false;
                      error = s.text(
                        'تحقق من قيمة الإرجاع والمبلغ المتفق عليه.',
                        'Check the return value and agreed amount.');
                    });
                    return;
                  }
                  if (paid > refundDue + 0.005) {
                    paid = refundDue;
                  }
                  final result = store.returnPurchase(
                    purchase: purchase,
                    quantities: quantities,
                    returnUnits: selectedUnits,
                    returnUnitQuantities: returnUnitQuantities,
                    agreedRefundAmount: agreed,
                    paidNow: paid,
                    reason: reason.text.trim(),
                    processedBy: s.controller.currentUserName,
                    processedById: s.controller.employeeId ?? '',
                  );
                  if (result == null) {
                    setD(() {
                      submitting = false;
                      error = s.text(
                        'تعذر تنفيذ الإرجاع. تأكد من الكميات والمخزون والمبالغ.',
                        'Could not process the return. Check quantities, stock, and amounts.');
                    });
                    return;
                  }
                  Navigator.pop(dialogContext);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(s.text(
                          'تم تسجيل المرتجع وتحديث المخزون وحساب المورد والملخص المالي.',
                          'Purchase return recorded; stock, supplier account, and financial summary were updated.'))));
                },
                icon: const Icon(Icons.assignment_return_outlined, size: 17),
                label: Text(s.text('تأكيد الإرجاع', 'Confirm return')),
              ),
            ],
          );
        },
      ),
    );

    for (final controller in quantityControllers.values) {
      controller.dispose();
    }
    agreedAmount.dispose();
    paidNow.dispose();
    reason.dispose();
  }

  SupplierRecord? _supplierForPurchase(PurchaseReceipt purchase) {
    final store = AppDataStore.instance;
    if (purchase.supplierId.isNotEmpty) {
      final direct = store.supplierOrNull(purchase.supplierId);
      if (direct != null) return direct;
    }
    for (final supplier in store.suppliers) {
      if (supplier.name.trim().toLowerCase() == purchase.supplier.trim().toLowerCase()) return supplier;
    }
    return null;
  }

  Future<void> _supplierDebt(BuildContext context, PurchaseReceipt purchase) async {
    final store = AppDataStore.instance;
    final s = widget.s;
    final supplier = _supplierForPurchase(purchase);
    if (supplier == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.text('تعذر العثور على ملف المورد المرتبط بهذه الفاتورة.', 'Could not find the supplier profile linked to this purchase.'))));
      return;
    }
    final purchaseDue = store.purchaseOutstanding(purchase);
    final supplierDue = store.supplierBalance(supplier.id);
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: Text('${s.text('حساب المورد', 'Supplier account')} • ${supplier.name}'),
        content: SizedBox(
          width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 560.0).toDouble(),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            DetailLine(label: s.text('رقم الحساب', 'Account'), value: supplier.accountNumber),
            DetailLine(label: s.text('فاتورة الشراء', 'Purchase invoice'), value: purchase.number),
            if (purchase.title.trim().isNotEmpty)
              DetailLine(label: s.text('اسم الفاتورة', 'Invoice name'), value: purchase.title.trim()),
            DetailLine(label: s.text('متبقي هذه الفاتورة', 'This invoice due'), value: '${purchaseDue.toStringAsFixed(2)} ${store.settings.currency}'),
            DetailLine(label: s.text('إجمالي المستحق للمورد', 'Supplier total due'), value: '${supplierDue.toStringAsFixed(2)} ${store.settings.currency}'),
            if (supplier.phone.trim().isNotEmpty) DetailLine(label: s.text('الهاتف', 'Phone'), value: supplier.phone),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(s.text('إغلاق', 'Close'))),
          if (purchaseDue > 0.005)
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, 'pay'),
              icon: const Icon(Icons.payments_outlined, size: 17),
              label: Text(s.text('تسديد', 'Pay')),
            ),
        ],
      ),
    );
    if (action != 'pay' || !context.mounted) return;
    await _payPurchaseDebt(context, supplier, purchase);
  }

  Future<void> _payPurchaseDebt(BuildContext context, SupplierRecord supplier, PurchaseReceipt purchase) async {
    final store = AppDataStore.instance;
    final s = widget.s;
    var due = store.purchaseOutstanding(purchase);
    if (due <= 0.005) return;
    final amount = TextEditingController(text: due.toStringAsFixed(2));
    final note = TextEditingController();
    String method = 'Cash';
    String? error;
    String? success;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setD) {
          due = store.purchaseOutstanding(purchase);
          final settled = due <= 0.005;
          return AlertDialog(
          scrollable: true,
          title: Text(s.text('تسديد فاتورة المورد', 'Pay supplier invoice')),
          content: SizedBox(
            width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 520.0).toDouble(),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Align(alignment: AlignmentDirectional.centerStart, child: Text('${supplier.name} • ${purchase.number}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900))),
              const SizedBox(height: 5),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  settled
                      ? s.text('تم تسديد هذه الفاتورة بالكامل.', 'This invoice is fully settled.')
                      : '${s.text('المتبقي على الفاتورة', 'Invoice remaining')}: ${due.toStringAsFixed(2)} ${store.settings.currency}',
                  style: TextStyle(fontSize: 9, color: settled ? AppColors.success : AppColors.danger, fontWeight: FontWeight.w800),
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  '${s.text('إجمالي المستحق للمورد', 'Supplier total due')}: ${store.supplierBalance(supplier.id).toStringAsFixed(2)} ${store.settings.currency}',
                  style: const TextStyle(fontSize: 8.5, color: AppColors.muted, fontWeight: FontWeight.w700),
                ),
              ),
              if (!settled) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: s.text('كم تريد تسديده الآن؟', 'How much do you want to pay now?'),
                    helperText: s.text('يمكنك تسديد جزء والبقاء في النافذة لتسديد المزيد.', 'You can pay part of the amount and stay in this window to pay more.'),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: method,
                  decoration: InputDecoration(labelText: s.text('طريقة الدفع', 'Payment method')),
                  items: const ['Cash', 'Bank', 'Card', 'Wallet'].map((v) => DropdownMenuItem(value: v, child: Text(s.paymentMethod(v)))).toList(),
                  onChanged: (v) => setD(() => method = v ?? method),
                ),
                const SizedBox(height: 10),
                TextField(controller: note, decoration: InputDecoration(labelText: s.text('ملاحظة', 'Note'))),
              ],
              if (success != null) ...[
                const SizedBox(height: 8),
                Align(alignment: AlignmentDirectional.centerStart, child: Text(success!, style: const TextStyle(fontSize: 9, color: AppColors.success, fontWeight: FontWeight.w800))),
              ],
              if (error != null) ...[
                const SizedBox(height: 8),
                Align(alignment: AlignmentDirectional.centerStart, child: Text(error!, style: const TextStyle(fontSize: 9, color: AppColors.danger, fontWeight: FontWeight.w700))),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(s.text(settled ? 'إغلاق' : 'إنهاء', settled ? 'Close' : 'Done'))),
            if (!settled)
              FilledButton.icon(
                onPressed: () {
                  final value = double.tryParse(amount.text.trim()) ?? 0;
                  final payment = store.recordSupplierPayment(
                    supplierId: supplier.id,
                    amount: value,
                    method: method,
                    employeeName: s.controller.currentUserName,
                    purchaseId: purchase.id,
                    note: note.text.trim(),
                  );
                  if (payment == null) {
                    setD(() {
                      error = s.text('تحقق من المبلغ؛ يجب ألا يتجاوز متبقي الفاتورة.', 'Check the amount; it cannot exceed this invoice outstanding balance.');
                      success = null;
                    });
                    return;
                  }
                  final remaining = store.purchaseOutstanding(purchase);
                  setD(() {
                    error = null;
                    success = remaining <= 0.005
                        ? s.text('تم التسديد بالكامل. المتبقي 0.', 'Fully settled. Remaining is 0.')
                        : '${s.text('تم تسجيل الدفعة. المتبقي', 'Payment recorded. Remaining')}: ${remaining.toStringAsFixed(2)} ${store.settings.currency}';
                    amount.text = remaining <= 0.005 ? '0' : remaining.toStringAsFixed(2);
                    note.clear();
                  });
                },
                icon: const Icon(Icons.check_circle_outline, size: 17),
                label: Text(s.text('تأكيد التسديد', 'Confirm payment')),
              ),
          ],
        );
        },
      ),
    );
    amount.dispose();
    note.dispose();
  }

  Future<void> _printPurchaseRegister(List<PurchaseReceipt> receipts) async {
    final store = AppDataStore.instance;
    final s = widget.s;
    await ThamanPrintService.printDocument(PrintDocument(
      title:
          s.text('سجل المشتريات والاستلام', 'Purchases & Receiving Register'),
      subtitle: '${store.settings.storeName} • ${store.settings.branchName}',
      metadata: {
        s.text('عدد الفواتير', 'Invoices'): '${receipts.length}',
        s.text('فلتر البحث', 'Search filter'):
            search.text.trim().isEmpty ? '-' : search.text.trim(),
      },
      headers: [
        s.text('الرقم', 'Number'),
        s.text('اسم الفاتورة', 'Invoice name'),
        s.text('التاريخ', 'Date'),
        s.text('المورد', 'Supplier'),
        s.text('المستلم', 'Receiver'),
        s.text('الأصناف', 'Items'),
        s.text('الإجمالي', 'Total'),
        s.text('المدفوع', 'Paid'),
        s.text('المتبقي', 'Due'),
        s.text('طريقة الدفع', 'Payment'),
      ],
      rows: receipts
          .map((r) => [
                r.number,
                r.title.trim().isEmpty ? '-' : r.title.trim(),
                formatDateTime(r.createdAt),
                r.supplier,
                '${r.employeeName} • ${r.employeeId}',
                r.lines
                    .map((l) =>
                        '${l.itemName} × ${l.quantity} ${_unitLabel(s, l.purchaseUnit)}')
                    .join(' | '),
                '${r.total.toStringAsFixed(2)} ${store.settings.currency}',
                '${r.amountPaid.toStringAsFixed(2)} ${store.settings.currency}',
                '${store.purchaseOutstanding(r).toStringAsFixed(2)} ${store.settings.currency}',
                r.paymentMethod,
              ])
          .toList(),
      summary: {
        s.text('قيمة المشتريات', 'Purchase value'):
            '${receipts.fold<double>(0, (sum, r) => sum + r.total).toStringAsFixed(2)} ${store.settings.currency}',
        s.text('إجمالي المدفوع', 'Total paid'):
            '${receipts.fold<double>(0, (sum, r) => sum + r.amountPaid).toStringAsFixed(2)} ${store.settings.currency}',
        s.text('إجمالي المتبقي', 'Total due'):
            '${receipts.fold<double>(0, (sum, r) => sum + store.purchaseOutstanding(r)).toStringAsFixed(2)} ${store.settings.currency}',
      },
      footer: store.settings.receiptFooter,
    
      isArabic: widget.s.controller.isArabic,));
  }

  Future<void> _newPurchase(BuildContext context) async {
    await showDialog<PurchaseReceipt>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _NewPurchaseDialog(s: widget.s));
  }

  void _details(BuildContext context, PurchaseReceipt p) {
    final s = widget.s;
    final store = AppDataStore.instance;
    final due = store.purchaseOutstanding(p);
    showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          scrollable: true,
              title: Text(
                  '${s.text('تفاصيل فاتورة الشراء', 'Purchase details')} • ${p.number}'),
              content: SizedBox(
                  width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 720.0).toDouble(),
                  child: SingleChildScrollView(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        DetailLine(
                            label: s.text('التاريخ', 'Date'),
                            value: formatPurchaseWhen(p.createdAt, arabic: s.controller.isArabic)),
                        DetailLine(
                            label:
                                s.text('المشتري / المستلم', 'Buyer / receiver'),
                            value: '${p.employeeName} • ${p.employeeId}'),
                        if (p.restockRequestNumber.isNotEmpty)
                          DetailLine(
                              label: s.text('طلب التوريد', 'Restock request'),
                              value: p.restockRequestNumber),
                        DetailLine(
                            label: s.text('المورد', 'Supplier'),
                            value: p.supplier),
                        if (p.vendorInvoiceNumber.isNotEmpty)
                          DetailLine(
                              label: s.text('فاتورة المورد', 'Vendor invoice'),
                              value: p.vendorInvoiceNumber),
                        DetailLine(
                            label: s.text('طريقة الدفع', 'Payment method'),
                            value: s.paymentMethod(p.paymentMethod)),
                        if (p.dueDate != null)
                          DetailLine(
                              label: s.text('تاريخ الاستحقاق', 'Due date'),
                              value: _date(p.dueDate!)),
                        DetailLine(
                            label: s.text('الفرع', 'Branch'), value: p.branch),
                        const Divider(height: 22),
                        Text(s.text('الأصناف والوحدات', 'Items & units'),
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 8),
                        for (final l in p.lines)
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: AppColors.surfaceAlt,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.border)),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Expanded(
                                        child: Text(l.itemName,
                                            style: const TextStyle(
                                                fontSize: 9.8,
                                                fontWeight: FontWeight.w900))),
                                    Text(
                                        '${l.total.toStringAsFixed(2)} ${store.settings.currency}',
                                        style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w900))
                                  ]),
                                  const SizedBox(height: 7),
                                  Wrap(spacing: 14, runSpacing: 5, children: [
                                    _Tiny(
                                        '${s.text('الشراء', 'Purchase')}: ${l.quantity} × ${_unitLabel(s, l.purchaseUnit)}'),
                                    _Tiny(
                                        '${s.text('سعر وحدة الشراء', 'Purchase-unit cost')}: ${l.unitCost.toStringAsFixed(2)} ${store.settings.currency}'),
                                    _Tiny(
                                        '${s.text('مصاريف كل وحدة شراء', 'Expense per purchase unit')}: ${l.unitExpense.toStringAsFixed(2)} ${store.settings.currency}'),
                                    _Tiny(
                                        '${s.text('محتوى الوحدة', 'Units/package')}: ${l.unitsPerPurchaseUnit}'),
                                    _Tiny(
                                        '${s.text('الكمية الداخلة للمخزون', 'Stock received')}: ${l.baseQuantity} ${_unitLabel(s, l.saleUnit)}'),
                                    _Tiny(
                                        '${s.text('تكلفة القطعة بعد مصاريف الوحدة', 'Piece cost after unit expenses')}: ${l.baseUnitCost.toStringAsFixed(3)} ${store.settings.currency}'),
                                    _Tiny(
                                        '${s.text('التكلفة الفعلية بعد الشحن والضريبة', 'Landed unit cost')}: ${p.landedBaseUnitCost(l).toStringAsFixed(3)} ${store.settings.currency}'),
                                    if (l.packageWeightKg > 0)
                                      _Tiny(
                                          '${s.text('وزن العبوة', 'Package weight')}: ${l.packageWeightKg.toStringAsFixed(2)} kg'),
                                    if (l.salePrice > 0)
                                      _Tiny(
                                          '${s.text('سعر البيع', 'Sale price')}: ${l.salePrice.toStringAsFixed(2)} ${store.settings.currency}'),
                                  ]),
                                  if (l.note.isNotEmpty) ...[
                                    const SizedBox(height: 7),
                                    Text(
                                        '${s.text('ملاحظة الصنف', 'Item note')}: ${l.note}',
                                        style: const TextStyle(
                                            fontSize: 8.2,
                                            color: AppColors.muted,
                                            fontWeight: FontWeight.w700))
                                  ],
                                ]),
                          ),
                        const Divider(height: 22),
                        DetailLine(
                            label: s.text('قيمة البضاعة', 'Merchandise'),
                            value:
                                '${p.merchandiseTotal.toStringAsFixed(2)} ${store.settings.currency}'),
                        DetailLine(
                            label: s.text('شحن/مصاريف', 'Shipping/fees'),
                            value:
                                '${p.shippingCost.toStringAsFixed(2)} ${store.settings.currency}'),
                        DetailLine(
                            label: s.text('ضريبة', 'Tax'),
                            value:
                                '${p.taxAmount.toStringAsFixed(2)} ${store.settings.currency}'),
                        DetailLine(
                            label: s.text('إجمالي الفاتورة', 'Invoice total'),
                            value:
                                '${p.total.toStringAsFixed(2)} ${store.settings.currency}'),
                        DetailLine(
                            label: s.text(
                                'المدفوع عند الشراء', 'Paid at purchase'),
                            value:
                                '${p.amountPaid.toStringAsFixed(2)} ${store.settings.currency}'),
                        DetailLine(
                            label: s.text('المتبقي', 'Outstanding'),
                            value:
                                '${due.toStringAsFixed(2)} ${store.settings.currency}'),
                        if (p.note.isNotEmpty)
                          DetailLine(
                              label: s.text('ملاحظة', 'Note'), value: p.note),
                      ]))),
              actions: [
                OutlinedButton.icon(
                    onPressed: () => ThamanPrintService.printDocument(
                        ThamanPrintTemplates.purchaseReceipt(store, p, isArabic: s.controller.isArabic)),
                    icon: const Icon(Icons.print_outlined, size: 17),
                    label: Text(s.text('طباعة', 'Print'))),
                FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(s.text('إغلاق', 'Close')))
              ],
            ));
  }
}

class _NewPurchaseDialog extends StatefulWidget {
  const _NewPurchaseDialog({required this.s});
  final AppStrings s;
  @override
  State<_NewPurchaseDialog> createState() => _NewPurchaseDialogState();
}

class _NewPurchaseDialogState extends State<_NewPurchaseDialog> {
  final invoiceTitle = TextEditingController();
  final vendorInvoice = TextEditingController();
  final newSupplier = TextEditingController();
  final shipping = TextEditingController(text: '0');
  final tax = TextEditingController(text: '0');
  final amountPaid = TextEditingController(text: '0');
  final note = TextEditingController();
  final lines = <_PurchaseDraft>[];
  String supplierId = '';
  String receivingEmployeeId = '';
  String paymentMethod = 'Cash';
  String selectedRestockId = '';
  DateTime? dueDate;
  String? error;
  String? supplierFieldError;
  String? employeeFieldError;
  String? paidFieldError;

  @override
  void initState() {
    super.initState();
    final store = AppDataStore.instance;
    if (store.suppliers.isNotEmpty) supplierId = store.suppliers.first.id;
    if (widget.s.controller.role == UserRole.owner) {
      receivingEmployeeId = '__owner__';
    } else {
      final inventory =
          store.activeEmployees.where((e) => e.roleKey == 'inventory').toList();
      if (inventory.isNotEmpty) {
        receivingEmployeeId = inventory.first.id;
      } else if (store.activeEmployees.isNotEmpty) {
        receivingEmployeeId = store.activeEmployees.first.id;
      }
    }
  }

  @override
  void dispose() {
    invoiceTitle.dispose();
    vendorInvoice.dispose();
    newSupplier.dispose();
    shipping.dispose();
    tax.dispose();
    amountPaid.dispose();
    note.dispose();
    super.dispose();
  }

  double get merchandiseTotal =>
      lines.fold<double>(0, (sum, l) => sum + l.total);
  double get invoiceTotal =>
      merchandiseTotal +
      (double.tryParse(shipping.text) ?? 0) +
      (double.tryParse(tax.text) ?? 0);

  @override
  Widget build(BuildContext context) {
    final store = AppDataStore.instance;
    final s = widget.s;
    final paid = double.tryParse(amountPaid.text) ?? 0;
    final due = (invoiceTotal - paid).clamp(0, double.infinity).toDouble();
    return AlertDialog(
          scrollable: true,
      title: Text(s.text('فاتورة شراء جديدة', 'New purchase invoice')),
      content: SizedBox(
        width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 900.0).toDouble(),
        height: MediaQuery.sizeOf(context).height * .76,
        child: SingleChildScrollView(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.text('بيانات المورد والاستلام', 'Supplier & receiving'),
              style:
                  const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth < 700 ? c.maxWidth : (c.maxWidth - 10) / 2;
            return Wrap(spacing: 10, runSpacing: 10, children: [
              SizedBox(
                  width: w,
                  child: DropdownButtonFormField<String>(
                      value: supplierId.isEmpty ? '__new__' : supplierId,
                      decoration: InputDecoration(
                          labelText: s.text('المورد', 'Supplier'),
                          errorText: supplierId.isNotEmpty ? supplierFieldError : null),
                      items: [
                        DropdownMenuItem(
                            value: '__new__',
                            child: Text(s.text('مورد جديد / كتابة الاسم',
                                'New supplier / type name'))),
                        ...store.suppliers.map((sup) => DropdownMenuItem(
                            value: sup.id,
                            child: Text('${sup.name} • ${sup.accountNumber}')))
                      ],
                      onChanged: (v) => setState(
                          () => supplierId = v == '__new__' ? '' : (v ?? '')))),
              SizedBox(
                  width: w,
                  child: DropdownButtonFormField<String>(
                      value: receivingEmployeeId.isEmpty
                          ? null
                          : receivingEmployeeId,
                      decoration: InputDecoration(
                          labelText: s.text('الموظف المستلم/المناوب',
                              'Receiving/on-duty employee'),
                          errorText: employeeFieldError),
                      items: [
                        if (s.controller.role == UserRole.owner)
                          DropdownMenuItem(value: '__owner__', child: Text(s.text('المالك (أنا)', 'Owner (me)'))),
                        ...store.activeEmployees.map((e) => DropdownMenuItem(
                              value: e.id,
                              child: Text('${s.text(e.nameAr, e.nameEn)} • ${e.loginId}'))),
                      ],
                      onChanged: (v) => setState(() =>
                          receivingEmployeeId = v ?? receivingEmployeeId))),
              if (supplierId.isEmpty)
                SizedBox(
                    width: w,
                    child: TextField(
                        controller: newSupplier,
                        decoration: InputDecoration(
                            labelText: s.text('اسم المورد', 'Supplier name'),
                            hintText: s.text('اكتب اسم المورد', 'Enter the supplier name'),
                            errorText: supplierFieldError))),
              SizedBox(
                  width: w,
                  child: TextField(
                      controller: invoiceTitle,
                      decoration: InputDecoration(
                          labelText: s.text('اسم الفاتورة (اختياري)', 'Invoice name (optional)'),
                          hintText: s.text('مثال: بضاعة رمضان', 'Example: Ramadan stock')))),
              SizedBox(
                  width: w,
                  child: TextField(
                      controller: vendorInvoice,
                      decoration: InputDecoration(
                          labelText: s.text(
                              'رقم فاتورة المورد', 'Vendor invoice number')))),
            ]);
          }),
          const Divider(height: 28),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(s.text('أصناف الفاتورة', 'Purchase items'),
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 3),
                  Text(
                      s.text(
                          'يمكن تحديد عدة أصناف بواسطة CHECKBOX، ولكل صنف كمية ووحدة وسعر مستقلان، أو كتابة صنف جديد يدويًا.',
                          'Select multiple items with checkboxes; every item has its own quantity, unit and price, or add a new item manually.'),
                      style: const TextStyle(
                          fontSize: 8.4, color: AppColors.muted))
                ])),
            const SizedBox(width: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.tonalIcon(
                  onPressed: () => _addMultipleLines(context),
                  icon: const Icon(Icons.checklist_rounded, size: 17),
                  label: Text(s.text('تحديد عدة أصناف', 'Select multiple'))),
              OutlinedButton.icon(
                  onPressed: () => _addLine(context),
                  icon: const Icon(Icons.edit_note_rounded, size: 17),
                  label: Text(s.text('إضافة/كتابة صنف', 'Add/manual item')))
            ])
          ]),
          const SizedBox(height: 10),
          if (lines.isEmpty)
            Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border)),
                child: Text(
                    s.text('أضف صنفًا واحدًا على الأقل إلى فاتورة الشراء.',
                        'Add at least one item to the purchase invoice.'),
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(fontSize: 9, color: AppColors.muted)))
          else
            for (final line in lines) ...[
              InkWell(
                onTap: () => _editLine(context, line),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border)),
                  child: Row(children: [
                    Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                            color: AppColors.primarySoft,
                            borderRadius: BorderRadius.circular(11)),
                        child: const Icon(Icons.inventory_2_outlined,
                            color: AppColors.primary, size: 18)),
                    const SizedBox(width: 9),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(line.itemName,
                              style: const TextStyle(
                                  fontSize: 9.8, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 3),
                          Text(
                              '${line.quantity} ${_unitLabel(s, line.purchaseUnit)} × ${line.purchaseUnitPrice.toStringAsFixed(2)}${line.unitExpense > 0.0005 ? ' • ${s.text('مصاريف الوحدة', 'unit expenses')}: ${line.unitExpense.toStringAsFixed(2)}' : ''} • ${line.unitsPerPurchaseUnit} ${_unitLabel(s, line.saleUnit)}/${_unitLabel(s, line.purchaseUnit)} • ${s.text('تكلفة القطعة الفعلية', 'landed piece cost')} ${line.baseUnitCost.toStringAsFixed(3)}',
                              style: const TextStyle(
                                  fontSize: 8, color: AppColors.muted))
                        ])),
                    Text(
                        '${line.total.toStringAsFixed(2)} ${store.settings.currency}',
                        style: const TextStyle(
                            fontSize: 9.6, fontWeight: FontWeight.w900)),
                    IconButton(
                        tooltip: s.text('تعديل الصنف', 'Edit item'),
                        onPressed: () => _editLine(context, line),
                        icon: const Icon(Icons.edit_outlined,
                            size: 17, color: AppColors.primary)),
                    IconButton(
                        tooltip: s.text('حذف الصنف', 'Remove item'),
                        onPressed: () => setState(() => lines.remove(line)),
                        icon: const Icon(Icons.close_rounded,
                            size: 17, color: AppColors.danger)),
                  ]))),
            ],
          const Divider(height: 28),
          Text(s.text('الدفع والتكاليف', 'Payment & costs'),
              style:
                  const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth < 700 ? c.maxWidth : (c.maxWidth - 10) / 2;
            return Wrap(spacing: 10, runSpacing: 10, children: [
              SizedBox(
                  width: w,
                  child: TextField(
                      controller: shipping,
                      onChanged: (_) => setState(() {}),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          labelText:
                              s.text('الشحن والمصاريف', 'Shipping & fees')))),
              SizedBox(
                  width: w,
                  child: TextField(
                      controller: tax,
                      onChanged: (_) => setState(() {}),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          labelText: s.text('الضريبة', 'Tax')))),
              SizedBox(
                  width: w,
                  child: DropdownButtonFormField<String>(
                      value: paymentMethod,
                      decoration: InputDecoration(
                          labelText: s.text('طريقة الدفع', 'Payment method')),
                      items: const ['Cash', 'Bank', 'Card', 'Wallet', 'Credit']
                          .map((v) => DropdownMenuItem(value: v, child: Text(s.paymentMethod(v))))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => paymentMethod = v ?? paymentMethod))),
              if (store.openRestockRequests.isNotEmpty)
                SizedBox(
                    width: w,
                    child: DropdownButtonFormField<String>(
                        value: selectedRestockId.isEmpty ? '__none__' : selectedRestockId,
                        decoration: InputDecoration(
                            labelText: s.text('طلب التوريد المرتبط', 'Linked restock request')),
                        items: [
                          DropdownMenuItem(value: '__none__', child: Text(s.text('بدون طلب', 'No request'))),
                          ...store.openRestockRequests.map((r) => DropdownMenuItem(
                                value: r.id,
                                child: Text('${r.number} • ${r.createdByName}'),
                              )),
                        ],
                        onChanged: (v) => setState(() => selectedRestockId = v == '__none__' ? '' : (v ?? '')))),
              SizedBox(
                  width: w,
                  child: TextField(
                      controller: amountPaid,
                      onChanged: (_) => setState(() {}),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          labelText: s.text(
                              'المبلغ المدفوع الآن', 'Amount paid now'),
                          errorText: paidFieldError))),
              SizedBox(
                  width: w,
                  child: OutlinedButton.icon(
                      onPressed: _pickDueDate,
                      icon: const Icon(Icons.event_outlined, size: 17),
                      label: Text(dueDate == null
                          ? s.text('تحديد تاريخ الاستحقاق', 'Set due date')
                          : '${s.text('الاستحقاق', 'Due')}: ${_date(dueDate!)}'))),
              SizedBox(
                  width: w,
                  child: TextField(
                      controller: note,
                      decoration: InputDecoration(
                          labelText:
                              s.text('ملاحظة الفاتورة', 'Purchase note')))),
            ]);
          }),
          const SizedBox(height: 14),
          Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(15)),
              child: Wrap(spacing: 22, runSpacing: 8, children: [
                _Summary(
                    label: s.text('البضاعة', 'Merchandise'),
                    value:
                        '${merchandiseTotal.toStringAsFixed(2)} ${store.settings.currency}'),
                _Summary(
                    label: s.text('الإجمالي', 'Total'),
                    value:
                        '${invoiceTotal.toStringAsFixed(2)} ${store.settings.currency}'),
                _Summary(
                    label: s.text('مدفوع', 'Paid'),
                    value:
                        '${paid.toStringAsFixed(2)} ${store.settings.currency}'),
                _Summary(
                    label: s.text('متبقي', 'Outstanding'),
                    value:
                        '${due.toStringAsFixed(2)} ${store.settings.currency}',
                    danger: due > 0),
              ])),
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(error!,
                style: const TextStyle(
                    fontSize: 9,
                    color: AppColors.danger,
                    fontWeight: FontWeight.w800))
          ],
        ])),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.text('إلغاء', 'Cancel'))),
        FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check_rounded, size: 17),
            label: Text(s.text('حفظ واستلام البضاعة', 'Save & receive stock'))),
      ],
    );
  }

  Future<void> _addMultipleLines(BuildContext context) async {
    final picked = await showDialog<List<_PurchaseDraft>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _MultiPurchasePickerDialog(s: widget.s));
    if (picked == null || picked.isEmpty) return;
    setState(() {
      for (final item in picked) {
        final index = lines.indexWhere((line) =>
            line.productId.isNotEmpty && line.productId == item.productId);
        if (index >= 0) {
          lines[index] = item;
        } else {
          lines.add(item);
        }
      }
    });
  }

  Future<void> _addLine(BuildContext context) async {
    final line = await showDialog<_PurchaseDraft>(
        context: context, builder: (_) => _PurchaseLineDialog(s: widget.s));
    if (line != null) setState(() => lines.add(line));
  }

  Future<void> _editLine(BuildContext context, _PurchaseDraft current) async {
    final updated = await showDialog<_PurchaseDraft>(
      context: context,
      builder: (_) => _PurchaseLineDialog(s: widget.s, initial: current),
    );
    if (updated == null) return;
    final index = lines.indexOf(current);
    if (index >= 0) setState(() => lines[index] = updated);
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
        context: context,
        initialDate: dueDate ?? now.add(const Duration(days: 14)),
        firstDate: DateTime(now.year, now.month, now.day),
        lastDate: now.add(const Duration(days: 3650)));
    if (picked != null) setState(() => dueDate = picked);
  }

  void _save() {
    final store = AppDataStore.instance;
    final s = widget.s;
    setState(() {
      error = null;
      supplierFieldError = null;
      employeeFieldError = null;
      paidFieldError = null;
    });
    if (lines.isEmpty) {
      setState(() => error =
          s.text('أضف صنفًا واحدًا على الأقل.', 'Add at least one item.'));
      return;
    }
    final supplierName = supplierId.isEmpty
        ? newSupplier.text.trim()
        : (store.supplierOrNull(supplierId)?.name ?? '');
    if (supplierName.isEmpty) {
      setState(() {
        supplierFieldError = s.text('اكتب اسم المورد، هذا الحقل مطلوب.', 'Enter the supplier name. This field is required.');
        error = s.text('حدد المورد أو اكتب اسمه.', 'Select or enter a supplier.');
      });
      return;
    }
    final ownerPurchase = receivingEmployeeId == '__owner__' && s.controller.role == UserRole.owner;
    final employee = ownerPurchase ? null : store.employeeOrNull(receivingEmployeeId);
    if (!ownerPurchase && employee == null) {
      setState(() {
        employeeFieldError = s.text('حدد الموظف المستلم.', 'Select the receiving employee.');
        error = s.text('حدد الموظف الذي استلم البضاعة أو اختر المالك.',
          'Select the receiving employee or choose the owner.');
      });
      return;
    }
    final paid = double.tryParse(amountPaid.text.trim()) ?? 0;
    final extraShipping = double.tryParse(shipping.text.trim()) ?? 0;
    final extraTax = double.tryParse(tax.text.trim()) ?? 0;
    if (paid < 0 || paid > invoiceTotal) {
      setState(() {
        paidFieldError = s.text('بين صفر وإجمالي الفاتورة.', 'Between zero and the invoice total.');
        error = s.text(
          'المبلغ المدفوع يجب أن يكون بين صفر وإجمالي الفاتورة.',
          'Paid amount must be between zero and the invoice total.');
      });
      return;
    }
    final finalLines = <PurchaseLine>[];
    for (final draft in lines) {
      ProductModel product;
      if (draft.productId.isEmpty) {
        product = store.createManualProduct(
            name: draft.itemName,
            sku: draft.sku,
            openingStock: 0,
            cost: draft.baseUnitCost,
            barcode: draft.barcode);
      } else {
        product = store.product(draft.productId);
      }
      finalLines.add(PurchaseLine(
          productId: product.id,
          itemName: product.nameAr,
          quantity: draft.quantity,
          unitCost: draft.purchaseUnitPrice,
          purchaseUnit: draft.purchaseUnit,
          unitsPerPurchaseUnit: draft.unitsPerPurchaseUnit,
          packageWeightKg: draft.packageWeightKg,
          saleUnit: draft.saleUnit,
          salePrice: draft.salePrice,
          unitExpense: draft.unitExpense,
          note: draft.note));
    }
    final receipt = store.createPurchase(
      lines: finalLines,
      supplierName: supplierName,
      employeeId: employee?.id ?? '',
      employeeName: employee == null ? s.controller.currentUserName : s.text(employee.nameAr, employee.nameEn),
      vendorInvoiceNumber: vendorInvoice.text.trim(),
      paymentMethod: paymentMethod,
      amountPaid: paid,
      shippingCost: extraShipping < 0 ? 0 : extraShipping,
      taxAmount: extraTax < 0 ? 0 : extraTax,
      dueDate: dueDate,
      note: note.text.trim(),
      invoiceTitle: invoiceTitle.text.trim(),
      restockRequestId: selectedRestockId,
    );
    Navigator.pop(context, receipt);
  }
}

class _MultiPurchasePickerDialog extends StatefulWidget {
  const _MultiPurchasePickerDialog({required this.s});
  final AppStrings s;
  @override
  State<_MultiPurchasePickerDialog> createState() =>
      _MultiPurchasePickerDialogState();
}

class _MultiPurchasePickerDialogState
    extends State<_MultiPurchasePickerDialog> {
  final search = TextEditingController();
  final barcode = TextEditingController();
  final Map<String, _MultiPurchaseLineState> selected = {};
  String? error;
  @override
  void dispose() {
    search.dispose();
    barcode.dispose();
    for (final l in selected.values) {
      l.dispose();
    }
    super.dispose();
  }

  void _scanBarcode(String raw) {
    final code = raw.trim();
    if (code.isEmpty) return;
    final found = AppDataStore.instance.productByBarcodeOrSku(code);
    if (found != null) {
      setState(() => selected.putIfAbsent(
          found!.id, () => _MultiPurchaseLineState(found!)));
      barcode.clear();
      search.clear();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.s.text(
              'الباركود غير مسجل على أي صنف.',
              'Barcode is not assigned to an item.',
            ),
          ),
        ),
      );

      barcode.selection = TextSelection(
        baseOffset: 0,
        extentOffset: barcode.text.length,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AppDataStore.instance;
    final s = widget.s;
    final q = search.text.trim().toLowerCase();
    final products = store.products
        .where((p) =>
            p.active &&
            (q.isEmpty ||
                p.nameAr.toLowerCase().contains(q) ||
                p.nameEn.toLowerCase().contains(q) ||
                p.sku.toLowerCase().contains(q) ||
                p.barcode.toLowerCase().contains(q)))
        .toList();
    final all = products.isNotEmpty &&
        products.every((p) => selected.containsKey(p.id));
    return AlertDialog(
          scrollable: true,
        title: Row(children: [
          Expanded(
              child: Text(s.text(
                  'تحديد عدة أصناف للشراء', 'Select multiple purchase items'))),
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(20)),
              child: Text('${selected.length} ${s.text('محدد', 'selected')}',
                  style: const TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary)))
        ]),
        content: SizedBox(
            width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 980.0).toDouble(),
            height: MediaQuery.sizeOf(context).height * .72,
            child: Column(children: [
              TextField(
                  controller: search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded),
                      hintText: s.text('اسم الصنف، SKU أو الباركود...',
                          'Item name, SKU or barcode...'))),
              const SizedBox(height: 8),
              TextField(
                  controller: barcode,
                  onSubmitted: _scanBarcode,
                  decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.qr_code_scanner_rounded),
                      labelText: s.text('قارئ الباركود', 'Barcode scanner'),
                      hintText: s.text(
                          'امسح الباركود ثم Enter', 'Scan barcode then Enter'),
                      suffixIcon: IconButton(
                          onPressed: () => _scanBarcode(barcode.text),
                          icon: const Icon(Icons.keyboard_return_rounded,
                              size: 18)))),
              const SizedBox(height: 8),
              Row(children: [
                OutlinedButton.icon(
                    onPressed: () => setState(() {
                          if (all) {
                            for (final p in products) {
                              selected.remove(p.id)?.dispose();
                            }
                          } else {
                            for (final p in products) {
                              selected.putIfAbsent(
                                  p.id, () => _MultiPurchaseLineState(p));
                            }
                          }
                        }),
                    icon: Icon(
                        all ? Icons.deselect_rounded : Icons.select_all_rounded,
                        size: 17),
                    label: Text(all
                        ? s.text('إلغاء تحديد الظاهر', 'Clear visible')
                        : s.text('تحديد الظاهر', 'Select visible'))),
                const Spacer(),
                Text(
                    s.text('كل صنف له بيانات مستقلة',
                        'Each item has independent values'),
                    style:
                        const TextStyle(fontSize: 8.5, color: AppColors.muted))
              ]),
              const SizedBox(height: 8),
              Expanded(child: LayoutBuilder(builder: (context, c) {
                final picker = Container(
                    decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border)),
                    child: ListView.separated(
                        itemCount: products.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final p = products[i];
                          return CheckboxListTile(
                              dense: true,
                              value: selected.containsKey(p.id),
                              controlAffinity: ListTileControlAffinity.leading,
                              onChanged: (v) => setState(() {
                                    if (v == true) {
                                      selected.putIfAbsent(p.id,
                                          () => _MultiPurchaseLineState(p));
                                    } else {
                                      selected.remove(p.id)?.dispose();
                                    }
                                  }),
                              title: Text(s.text(p.nameAr, p.nameEn),
                                  style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800)),
                              subtitle: Text(
                                  '${p.sku} • ${s.text('المخزون', 'Stock')}: ${p.stock}',
                                  style: const TextStyle(
                                      fontSize: 7.8, color: AppColors.muted)));
                        }));
                final editors = selected.isEmpty
                    ? Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.border)),
                        child: Text(
                            s.text('حدد الأصناف من القائمة.',
                                'Select items from the list.'),
                            style: const TextStyle(
                                fontSize: 9, color: AppColors.muted)))
                    : Container(
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.border)),
                        child: ListView.separated(
                            padding: const EdgeInsets.all(10),
                            itemCount: selected.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final line = selected.values.elementAt(i);
                              return _MultiPurchaseLineEditor(
                                  line: line,
                                  s: s,
                                  onChanged: () => setState(() {}),
                                  onRemove: () => setState(() {
                                        selected
                                            .remove(line.product.id)
                                            ?.dispose();
                                      }));
                            }));
                if (c.maxWidth < 800)
                  return Column(children: [
                    SizedBox(height: 190, child: picker),
                    const SizedBox(height: 8),
                    Expanded(child: editors)
                  ]);
                return Row(children: [
                  SizedBox(width: 300, child: picker),
                  const SizedBox(width: 8),
                  Expanded(child: editors)
                ]);
              })),
              if (error != null) ...[
                const SizedBox(height: 8),
                Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(error!,
                        style: const TextStyle(
                            fontSize: 9,
                            color: AppColors.danger,
                            fontWeight: FontWeight.w800)))
              ]
            ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s.text('إلغاء', 'Cancel'))),
          FilledButton.icon(
              onPressed: _done,
              icon: const Icon(Icons.check_rounded, size: 17),
              label: Text(s.text('إضافة المحدد', 'Add selected')))
        ]);
  }

  void _done() {
    final s = widget.s;
    if (selected.isEmpty) {
      setState(() => error =
          s.text('حدد صنفًا واحدًا على الأقل.', 'Select at least one item.'));
      return;
    }
    final out = <_PurchaseDraft>[];
    for (final line in selected.values) {
      final q = int.tryParse(line.quantity.text) ?? 0;
      final units = int.tryParse(line.units.text) ?? 0;
      final buy = double.tryParse(line.buy.text) ?? 0;
      final expense = double.tryParse(line.expense.text) ?? 0;
      final sell = double.tryParse(line.sell.text) ?? 0;
      final weight = double.tryParse(line.weight.text) ?? 0;
      if (q <= 0 || units <= 0 || buy <= 0 || expense < 0 || sell < 0 || weight < 0) {
        setState(() => error = s.text(
            'راجع الكمية والوحدة وسعر الشراء لكل صنف محدد.',
            'Check quantity, unit conversion and purchase price for every selected item.'));
        return;
      }
      out.add(_PurchaseDraft(
          productId: line.product.id,
          itemName: line.product.nameAr,
          barcode: line.product.barcode,
          quantity: q,
          purchaseUnit: line.purchaseUnit,
          unitsPerPurchaseUnit: units,
          packageWeightKg: weight,
          purchaseUnitPrice: buy,
          unitExpense: expense,
          saleUnit: line.saleUnit,
          salePrice: sell,
          note: line.itemNote.text.trim()));
    }
    Navigator.pop(context, out);
  }
}

class _MultiPurchaseLineState {
  _MultiPurchaseLineState(this.product)
      : quantity = TextEditingController(text: '1'),
        units = TextEditingController(
            text:
                '${product.unitsPerPurchaseUnit <= 0 ? 1 : product.unitsPerPurchaseUnit}'),
        buy = TextEditingController(
            text: (product.cost *
                    (product.unitsPerPurchaseUnit <= 0
                        ? 1
                        : product.unitsPerPurchaseUnit))
                .toStringAsFixed(3)),
        expense = TextEditingController(text: '0'),
        weight = TextEditingController(
            text: product.packageWeightKg.toStringAsFixed(3)),
        sell = TextEditingController(text: product.price.toStringAsFixed(2)),
        itemNote = TextEditingController(),
        purchaseUnit = product.purchaseUnit,
        saleUnit = product.baseUnit;
  final ProductModel product;
  final TextEditingController quantity;
  final TextEditingController units;
  final TextEditingController buy;
  final TextEditingController expense;
  final TextEditingController weight;
  final TextEditingController sell;
  final TextEditingController itemNote;
  String purchaseUnit;
  String saleUnit;
  void dispose() {
    quantity.dispose();
    units.dispose();
    buy.dispose();
    expense.dispose();
    weight.dispose();
    sell.dispose();
    itemNote.dispose();
  }
}

class _MultiPurchaseLineEditor extends StatelessWidget {
  const _MultiPurchaseLineEditor(
      {required this.line,
      required this.s,
      required this.onChanged,
      required this.onRemove});
  final _MultiPurchaseLineState line;
  final AppStrings s;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  @override
  Widget build(BuildContext context) {
    final store = AppDataStore.instance;
    final q = int.tryParse(line.quantity.text) ?? 0;
    final units = int.tryParse(line.units.text) ?? 0;
    final buy = double.tryParse(line.buy.text) ?? 0;
    final expense = double.tryParse(line.expense.text) ?? 0;
    return Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: AppColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(
                    '${s.text(line.product.nameAr, line.product.nameEn)} • ${line.product.sku}',
                    style: const TextStyle(
                        fontSize: 9.5, fontWeight: FontWeight.w900))),
            IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.close_rounded,
                    size: 17, color: AppColors.danger))
          ]),
          LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth < 570 ? c.maxWidth : (c.maxWidth - 20) / 3;
            return Wrap(spacing: 10, runSpacing: 8, children: [
              SizedBox(
                  width: w,
                  child: TextField(
                      controller: line.quantity,
                      onChanged: (_) => onChanged(),
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                          labelText: s.text('الكمية', 'Quantity'),
                          isDense: true))),
              SizedBox(
                  width: w,
                  child: DropdownButtonFormField<String>(
                      value: line.purchaseUnit,
                      decoration: InputDecoration(
                          labelText: s.text('وحدة الشراء', 'Purchase unit'),
                          isDense: true),
                      items: _units
                          .map((v) => DropdownMenuItem(
                              value: v, child: Text(_unitLabel(s, v))))
                          .toList(),
                      onChanged: (v) {
                        line.purchaseUnit = v ?? line.purchaseUnit;
                        onChanged();
                      })),
              SizedBox(
                  width: w,
                  child: TextField(
                      controller: line.units,
                      onChanged: (_) => onChanged(),
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                          labelText: s.text('محتوى الوحدة', 'Units/package'),
                          isDense: true))),
              SizedBox(
                  width: w,
                  child: TextField(
                      controller: line.buy,
                      onChanged: (_) => onChanged(),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          labelText:
                              s.text('سعر شراء الوحدة', 'Purchase-unit cost'),
                          isDense: true))),
              SizedBox(
                  width: w,
                  child: TextField(
                      controller: line.expense,
                      onChanged: (_) => onChanged(),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          labelText: s.text('مصاريف الوحدة', 'Unit expenses'),
                          isDense: true))),
              SizedBox(
                  width: w,
                  child: TextField(
                      controller: line.weight,
                      onChanged: (_) => onChanged(),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          labelText: s.text('الوزن كغ', 'Weight kg'),
                          isDense: true))),
              SizedBox(
                  width: w,
                  child: DropdownButtonFormField<String>(
                      value: line.saleUnit,
                      decoration: InputDecoration(
                          labelText: s.text('وحدة البيع', 'Sale unit'),
                          isDense: true),
                      items: _units
                          .map((v) => DropdownMenuItem(
                              value: v, child: Text(_unitLabel(s, v))))
                          .toList(),
                      onChanged: (v) {
                        line.saleUnit = v ?? line.saleUnit;
                        onChanged();
                      })),
              SizedBox(
                  width: w,
                  child: TextField(
                      controller: line.sell,
                      onChanged: (_) => onChanged(),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          labelText: s.text('سعر البيع', 'Selling price'),
                          isDense: true))),
              SizedBox(
                  width: c.maxWidth,
                  child: TextField(
                      controller: line.itemNote,
                      onChanged: (_) => onChanged(),
                      decoration: InputDecoration(
                          labelText: s.text(
                              'ملاحظة خاصة بهذا الصنف', 'Item-specific note'),
                          isDense: true)))
            ]);
          }),
          const SizedBox(height: 7),
          Text(
              '${s.text('الوحدات الداخلة للمخزون', 'Stock units')}: ${q * units} • ${s.text('تكلفة القطعة', 'Piece cost')}: ${units <= 0 ? '0.000' : ((buy + expense) / units).toStringAsFixed(3)} • ${s.text('إجمالي السطر', 'Line total')}: ${(q * (buy + expense)).toStringAsFixed(2)} ${store.settings.currency}',
              style: const TextStyle(
                  fontSize: 8,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800))
        ]));
  }
}

class _PurchaseLineDialog extends StatefulWidget {
  const _PurchaseLineDialog({required this.s, this.initial});
  final AppStrings s;
  final _PurchaseDraft? initial;
  @override
  State<_PurchaseLineDialog> createState() => _PurchaseLineDialogState();
}

class _PurchaseLineDialogState extends State<_PurchaseLineDialog> {
  String productId = '';
  final barcode = TextEditingController();
  final manualName = TextEditingController();
  final manualSku = TextEditingController();
  final manualBarcode = TextEditingController();
  final quantity = TextEditingController(text: '1');
  final unitsPerPackage = TextEditingController(text: '1');
  final packageWeight = TextEditingController(text: '0');
  final purchasePrice = TextEditingController();
  final unitExpense = TextEditingController(text: '0');
  final salePrice = TextEditingController();
  final itemNote = TextEditingController();
  String purchaseUnit = 'piece';
  String saleUnit = 'piece';
  String? error;
  String? nameFieldError;
  String? qtyFieldError;
  String? priceFieldError;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial == null) return;
    productId = initial.productId;
    manualName.text = initial.itemName;
    manualSku.text = initial.sku;
    manualBarcode.text = initial.barcode;
    quantity.text = '${initial.quantity}';
    unitsPerPackage.text = '${initial.unitsPerPurchaseUnit}';
    packageWeight.text = initial.packageWeightKg.toStringAsFixed(3);
    purchasePrice.text = initial.purchaseUnitPrice.toStringAsFixed(3);
    unitExpense.text = initial.unitExpense.toStringAsFixed(3);
    salePrice.text = initial.salePrice.toStringAsFixed(2);
    itemNote.text = initial.note;
    purchaseUnit = initial.purchaseUnit;
    saleUnit = initial.saleUnit;
  }

  @override
  void dispose() {
    barcode.dispose();
    manualName.dispose();
    manualSku.dispose();
    manualBarcode.dispose();
    quantity.dispose();
    unitsPerPackage.dispose();
    packageWeight.dispose();
    purchasePrice.dispose();
    unitExpense.dispose();
    salePrice.dispose();
    itemNote.dispose();
    super.dispose();
  }

  void _scanBarcode(String raw) {
    final code = raw.trim();
    if (code.isEmpty) return;
    final found = AppDataStore.instance.productByBarcodeOrSku(code);
    if (found == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(widget.s.text('الباركود غير مسجل على أي صنف.',
              'Barcode is not assigned to an item.'))));
      return;
    }
    final product = found;
    setState(() {
      productId = product.id;
      salePrice.text = found.price.toStringAsFixed(2);
      saleUnit = found.baseUnit;
      purchaseUnit = found.purchaseUnit;
      unitsPerPackage.text =
          '${found.unitsPerPurchaseUnit <= 0 ? 1 : found.unitsPerPurchaseUnit}';
      purchasePrice.text = (found.cost *
              (found.unitsPerPurchaseUnit <= 0
                  ? 1
                  : found.unitsPerPurchaseUnit))
          .toStringAsFixed(3);
      packageWeight.text = found.packageWeightKg.toStringAsFixed(3);
    });
    barcode.clear();
  }


  Widget _box(double width, Widget child) {
    return SizedBox(width: width, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final store = AppDataStore.instance;
    final q = int.tryParse(quantity.text) ?? 0;
    final units = int.tryParse(unitsPerPackage.text) ?? 0;
    final pp = double.tryParse(purchasePrice.text) ?? 0;
    final expense = double.tryParse(unitExpense.text) ?? 0;
    final unitCost = q > 0 && units > 0 ? (pp + expense) / units : 0.0;

    final productItems = <DropdownMenuItem<String>>[
      DropdownMenuItem(
        value: '__manual__',
        child: Text(s.text('كتابة صنف جديد يدويًا', 'Type a new item manually')),
      ),
      ...store.products.where((p) => p.active).map(
            (p) => DropdownMenuItem(
              value: p.id,
              child: Text('${s.text(p.nameAr, p.nameEn)} • ${p.sku}'),
            ),
          ),
    ];

    return AlertDialog(
      scrollable: true,
      title: Text(
        widget.initial == null
            ? s.text('إضافة صنف لفاتورة الشراء', 'Add purchase item')
            : s.text('تفاصيل وتعديل صنف الشراء', 'Purchase item details & edit'),
      ),
      content: SizedBox(
        width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 620.0).toDouble(),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: barcode,
                onSubmitted: _scanBarcode,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.qr_code_scanner_rounded),
                  labelText: s.text('قارئ الباركود', 'Barcode scanner'),
                  hintText: s.text('امسح الباركود ثم Enter', 'Scan barcode then Enter'),
                  suffixIcon: IconButton(
                    onPressed: () => _scanBarcode(barcode.text),
                    icon: const Icon(Icons.keyboard_return_rounded, size: 18),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: productId.isEmpty ? '__manual__' : productId,
                decoration: InputDecoration(labelText: s.text('الصنف', 'Item')),
                items: productItems,
                onChanged: (v) {
                  setState(() {
                    productId = v == '__manual__' ? '' : (v ?? '');
                    if (productId.isNotEmpty) {
                      final product = store.product(productId);
                      salePrice.text = product.price.toStringAsFixed(2);
                      saleUnit = product.baseUnit;
                      purchaseUnit = product.purchaseUnit;
                      final pack = product.unitsPerPurchaseUnit <= 0 ? 1 : product.unitsPerPurchaseUnit;
                      unitsPerPackage.text = '$pack';
                      purchasePrice.text = (product.cost * pack).toStringAsFixed(3);
                      unitExpense.text = '0';
                      packageWeight.text = product.packageWeightKg.toStringAsFixed(3);
                    }
                  });
                },
              ),
              if (productId.isEmpty) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: manualName,
                  decoration: InputDecoration(
                    labelText: s.text('اسم الصنف الجديد', 'New item name'),
                    errorText: nameFieldError,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: manualSku,
                  decoration: InputDecoration(
                    labelText: s.text('SKU (اختياري)', 'SKU (optional)'),
                    helperText: s.text(
                      'اختياري. إن تركته فارغًا سيُولَّد رمز تلقائيًا.',
                      'Optional. Leave empty and a SKU will be generated.',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: manualBarcode,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.qr_code_scanner_rounded),
                    labelText: s.text('باركود الصنف الجديد', 'New item barcode'),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth < 540
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 10) / 2;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _box(
                        w,
                        DropdownButtonFormField<String>(
                          value: purchaseUnit,
                          decoration: InputDecoration(
                            labelText: s.text('وحدة الشراء', 'Purchase unit'),
                          ),
                          items: _units
                              .map((v) => DropdownMenuItem(value: v, child: Text(_unitLabel(s, v))))
                              .toList(),
                          onChanged: (v) => setState(() => purchaseUnit = v ?? purchaseUnit),
                        ),
                      ),
                      _box(
                        w,
                        TextField(
                          controller: quantity,
                          onChanged: (_) => setState(() {}),
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: s.text('عدد وحدات الشراء', 'Purchase-unit quantity'),
                            errorText: qtyFieldError,
                          ),
                        ),
                      ),
                      _box(
                        w,
                        TextField(
                          controller: unitsPerPackage,
                          onChanged: (_) => setState(() {}),
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: s.text('كل وحدة شراء تحتوي', 'Units inside each purchase unit'),
                            helperText: s.text('مثال: الكرتونة تحتوي 12 عبوة.', 'Example: one carton contains 12 packs.'),
                          ),
                        ),
                      ),
                      _box(
                        w,
                        TextField(
                          controller: packageWeight,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: s.text('وزن وحدة الشراء بالكيلو (اختياري)', 'Purchase-unit weight kg (optional)'),
                          ),
                        ),
                      ),
                      _box(
                        w,
                        TextField(
                          controller: purchasePrice,
                          onChanged: (_) => setState(() {}),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: s.text('سعر شراء الوحدة', 'Purchase-unit price'),
                            errorText: priceFieldError,
                          ),
                        ),
                      ),
                      _box(
                        w,
                        TextField(
                          controller: unitExpense,
                          onChanged: (_) => setState(() {}),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: s.text('مصاريف لكل وحدة شراء', 'Expense per purchase unit'),
                            helperText: s.text('تدخل في تكلفة القطعة تلقائيًا.', 'Automatically included in the piece cost.'),
                          ),
                        ),
                      ),
                      _box(
                        w,
                        DropdownButtonFormField<String>(
                          value: saleUnit,
                          decoration: InputDecoration(
                            labelText: s.text('وحدة البيع/المخزون', 'Sale / stock unit'),
                          ),
                          items: _units
                              .map((v) => DropdownMenuItem(value: v, child: Text(_unitLabel(s, v))))
                              .toList(),
                          onChanged: (v) => setState(() => saleUnit = v ?? saleUnit),
                        ),
                      ),
                      _box(
                        w,
                        TextField(
                          controller: salePrice,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: s.text('سعر البيع', 'Selling price'),
                          ),
                        ),
                      ),
                      _box(
                        constraints.maxWidth,
                        TextField(
                          controller: itemNote,
                          decoration: InputDecoration(
                            labelText: s.text('ملاحظة خاصة بهذا الصنف', 'Item-specific note'),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${s.text('تكلفة القطعة بعد مصاريف الوحدة', 'Piece cost after unit expenses')}: ${unitCost.toStringAsFixed(3)} ${store.settings.currency} • ${s.text('إجمالي وحدات المخزون', 'Stock units received')}: ${q * units} • ${s.text('إجمالي السطر', 'Line total')}: ${(q * (pp + expense)).toStringAsFixed(2)} ${store.settings.currency}',
                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.primary),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(
                  error!,
                  style: const TextStyle(fontSize: 9, color: AppColors.danger, fontWeight: FontWeight.w800),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.text('إلغاء', 'Cancel')),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(
            widget.initial == null
                ? s.text('إضافة', 'Add')
                : s.text('حفظ التعديلات', 'Save changes'),
          ),
        ),
      ],
    );
  }

  void _submit() {
    final s = widget.s;
    final store = AppDataStore.instance;
    final itemName = productId.isEmpty ? manualName.text.trim() : store.product(productId).nameAr;
    final q = int.tryParse(quantity.text) ?? 0;
    final units = int.tryParse(unitsPerPackage.text) ?? 0;
    final buy = double.tryParse(purchasePrice.text) ?? 0;
    final expense = double.tryParse(unitExpense.text) ?? 0;
    final sell = double.tryParse(salePrice.text) ?? 0;
    final weight = double.tryParse(packageWeight.text) ?? 0;
    if (productId.isEmpty && manualSku.text.trim().isNotEmpty && store.skuExists(manualSku.text)) {
      setState(() {
        error = s.text('هذا الـ SKU مستخدم مسبقًا. اختر رمزًا مختلفًا.', 'This SKU is already in use. Choose a different one.');
      });
      return;
    }
    if (itemName.isEmpty || q <= 0 || units <= 0 || buy <= 0 || expense < 0 || sell < 0 || weight < 0) {
      setState(() {
        error = s.text('تحقق من الصنف والكمية ومحتوى الوحدة وسعر الشراء.', 'Check item, quantity, units per package and purchase price.');
        nameFieldError = itemName.isEmpty ? s.text('اكتب اسم الصنف', 'Enter the item name') : null;
        qtyFieldError = q <= 0 ? s.text('أدخل كمية أكبر من صفر', 'Enter a quantity greater than zero') : null;
        priceFieldError = buy <= 0 ? s.text('أدخل سعر الشراء', 'Enter the purchase price') : null;
      });
      return;
    }
    Navigator.pop(
      context,
      _PurchaseDraft(
        productId: productId,
        itemName: itemName,
        sku: productId.isEmpty ? manualSku.text.trim() : store.product(productId).sku,
        barcode: productId.isEmpty ? manualBarcode.text.trim() : store.product(productId).barcode,
        quantity: q,
        purchaseUnit: purchaseUnit,
        unitsPerPurchaseUnit: units,
        packageWeightKg: weight,
        purchaseUnitPrice: buy,
        unitExpense: expense,
        saleUnit: saleUnit,
        salePrice: sell,
        note: itemNote.text.trim(),
      ),
    );
  }
}


class _PurchaseDraft {
  const _PurchaseDraft(
      {required this.productId,
      required this.itemName,
      this.sku = '',
      this.barcode = '',
      required this.quantity,
      required this.purchaseUnit,
      required this.unitsPerPurchaseUnit,
      required this.packageWeightKg,
      required this.purchaseUnitPrice,
      this.unitExpense = 0,
      required this.saleUnit,
      required this.salePrice,
      this.note = ''});
  final String productId;
  final String itemName;
  final String sku;
  final String barcode;
  final int quantity;
  final String purchaseUnit;
  final int unitsPerPurchaseUnit;
  final double packageWeightKg;
  final double purchaseUnitPrice;
  final double unitExpense;
  final String saleUnit;
  final double salePrice;
  final String note;
  int get baseQuantity => quantity * unitsPerPurchaseUnit;
  double get total => quantity * (purchaseUnitPrice + unitExpense);
  double get baseUnitCost => unitsPerPurchaseUnit <= 0
      ? 0
      : (purchaseUnitPrice + unitExpense) / unitsPerPurchaseUnit;
}

class _Tiny extends StatelessWidget {
  const _Tiny(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border)),
      child: Text(text,
          style: const TextStyle(
              fontSize: 7.8,
              color: AppColors.muted,
              fontWeight: FontWeight.w700)));
}

class _Summary extends StatelessWidget {
  const _Summary(
      {required this.label, required this.value, this.danger = false});
  final String label;
  final String value;
  final bool danger;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(fontSize: 7.8, color: AppColors.muted)),
        const SizedBox(height: 3),
        Text(value,
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                color: danger ? AppColors.danger : AppColors.text))
      ]);
}

const _units = [
  'piece',
  'pack',
  'carton',
  'box',
  'bag',
  'kg',
  'gram',
  'liter',
  'bottle',
  'roll'
];
String _unitLabel(AppStrings s, String value) => switch (value) {
      'piece' => s.text('قطعة', 'Piece'),
      'pack' => s.text('عبوة', 'Pack'),
      'carton' => s.text('كرتونة', 'Carton'),
      'box' => s.text('صندوق', 'Box'),
      'bag' => s.text('كيس', 'Bag'),
      'kg' => s.text('كيلو', 'Kg'),
      'gram' => s.text('غرام', 'Gram'),
      'liter' => s.text('لتر', 'Liter'),
      'bottle' => s.text('زجاجة', 'Bottle'),
      'roll' => s.text('رول', 'Roll'),
      _ => value
    };
String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
