import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../core/app_strings.dart';
import '../../core/widgets/app_logo.dart';
import '../../data/app_data_store.dart';
import '../../data/models.dart';
import 'inventory_batch_dialog.dart';

class BarcodeStationScreen extends StatefulWidget {
  const BarcodeStationScreen({
    super.key,
    required this.s,
    required this.actorId,
    required this.actorName,
    required this.actorRole,
  });

  final AppStrings s;
  final String actorId;
  final String actorName;
  final String actorRole;

  @override
  State<BarcodeStationScreen> createState() => _BarcodeStationScreenState();
}

class _BarcodeStationScreenState extends State<BarcodeStationScreen> {
  final controller = TextEditingController();
  final focusNode = FocusNode();
  ProductModel? product;
  String? message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => focusNode.requestFocus());
  }

  @override
  void dispose() {
    controller.dispose();
    focusNode.dispose();
    super.dispose();
  }

  void _scan(String raw) {
    final code = raw.trim();
    if (code.isEmpty) return;
    final found = AppDataStore.instance.productByBarcodeOrSku(code);
    setState(() {
      product = found;
      message = found == null
          ? widget.s.text('الباركود غير مسجل على أي صنف.', 'Barcode is not assigned to an item.')
          : null;
    });
    controller.clear();
    focusNode.requestFocus();
  }

  Future<void> _operation(String type) async {
    final p = product;
    if (p == null) return;
    await showInventoryBatchOperation(
      context,
      s: widget.s,
      type: type,
      actorId: widget.actorId,
      actorName: widget.actorName,
      actorRole: widget.actorRole,
      initialProductId: p.id,
    );
    if (mounted) focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Row(children: [const AppLogo(compact: true), const SizedBox(width: 10), Text(s.text('محطة قارئ الباركود', 'Barcode station'))]),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(
            padding: const EdgeInsets.all(22),
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), border: Border.all(color: AppColors.border)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(width: 48, height: 48, decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.qr_code_scanner_rounded, color: AppColors.primary)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.text('امسح الباركود مباشرة', 'Scan a barcode'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                      Text(s.text('أغلب أجهزة USB ترسل الباركود كلوحة مفاتيح وتضغط Enter تلقائيًا.', 'Most USB scanners type the barcode like a keyboard and submit Enter automatically.'), style: const TextStyle(fontSize: 9.5, color: AppColors.muted, height: 1.5)),
                    ])),
                  ]),
                  const SizedBox(height: 18),
                  TextField(
                    controller: controller,
                    focusNode: focusNode,
                    autofocus: true,
                    onSubmitted: _scan,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.qr_code_scanner_rounded),
                      labelText: s.text('الباركود / SKU', 'Barcode / SKU'),
                      hintText: s.text('امسح أو اكتب الكود ثم Enter', 'Scan or type code then Enter'),
                      suffixIcon: IconButton(onPressed: () => _scan(controller.text), icon: const Icon(Icons.keyboard_return_rounded)),
                    ),
                  ),
                  if (message != null) ...[const SizedBox(height: 10), Text(message!, style: const TextStyle(color: AppColors.danger, fontSize: 10, fontWeight: FontWeight.w800))],
                ]),
              ),
              const SizedBox(height: 14),
              if (product != null) _ProductResult(product: product!, s: s, onReceive: () => _operation('purchase'), onDamage: () => _operation('damage'), onTransfer: () => _operation('transfer')),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductResult extends StatelessWidget {
  const _ProductResult({required this.product, required this.s, required this.onReceive, required this.onDamage, required this.onTransfer});
  final ProductModel product;
  final AppStrings s;
  final VoidCallback onReceive;
  final VoidCallback onDamage;
  final VoidCallback onTransfer;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.text(product.nameAr, product.nameEn), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Text('${product.sku} • ${product.barcode.isEmpty ? s.text('بدون باركود', 'No barcode') : product.barcode}', style: const TextStyle(fontSize: 10, color: AppColors.muted)),
        const SizedBox(height: 16),
        Wrap(spacing: 9, runSpacing: 9, children: [
          _Metric(label: s.text('المخزون', 'Stock'), value: '${product.stock} ${product.baseUnit}'),
          _Metric(label: s.text('سعر البيع', 'Sale price'), value: product.price.toStringAsFixed(2)),
          _Metric(label: s.text('متوسط التكلفة', 'Average cost'), value: product.cost.toStringAsFixed(3)),
          _Metric(label: s.text('حد الطلب', 'Reorder'), value: '${product.minStock}'),
        ]),
        const SizedBox(height: 18),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(onPressed: onReceive, icon: const Icon(Icons.move_to_inbox_outlined, size: 17), label: Text(s.text('إدخال هذا الصنف', 'Enter stock'))),
          OutlinedButton.icon(onPressed: onDamage, icon: const Icon(Icons.warning_amber_rounded, size: 17), label: Text(s.text('تسجيل تالف', 'Record damage'))),
          OutlinedButton.icon(onPressed: onTransfer, icon: const Icon(Icons.swap_horiz_rounded, size: 17), label: Text(s.text('نقل', 'Transfer'))),
        ]),
      ]),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Container(
        width: 160,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(13)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontSize: 8.5, color: AppColors.muted)), const SizedBox(height: 4), Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900))]),
      );
}
