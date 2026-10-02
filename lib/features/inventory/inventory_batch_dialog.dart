import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../core/app_strings.dart';
import '../../data/app_data_store.dart';
import '../../data/models.dart';

Future<void> showInventoryBatchOperation(
  BuildContext context, {
  required AppStrings s,
  required String type,
  required String actorId,
  required String actorName,
  required String actorRole,
  String initialProductId = '',
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => InventoryBatchOperationDialog(
      s: s,
      type: type,
      actorId: actorId,
      actorName: actorName,
      actorRole: actorRole,
      initialProductId: initialProductId,
    ),
  );
}

class InventoryBatchOperationDialog extends StatefulWidget {
  const InventoryBatchOperationDialog({
    super.key,
    required this.s,
    required this.type,
    required this.actorId,
    required this.actorName,
    required this.actorRole,
    this.initialProductId = '',
  });

  final AppStrings s;
  final String type;
  final String actorId;
  final String actorName;
  final String actorRole;
  final String initialProductId;

  @override
  State<InventoryBatchOperationDialog> createState() =>
      _InventoryBatchOperationDialogState();
}

class _InventoryBatchOperationDialogState
    extends State<InventoryBatchOperationDialog> {
  final search = TextEditingController();
  final barcode = TextEditingController();
  final supplier = TextEditingController(text: 'Direct supplier');
  final invoiceTitle = TextEditingController();
  final vendorInvoice = TextEditingController();
  final amountPaid = TextEditingController(text: '0');
  final shipping = TextEditingController(text: '0');
  final tax = TextEditingController(text: '0');
  final note = TextEditingController();
  final destination = TextEditingController(text: 'Branch 2');
  String paymentMethod = 'Cash';
  String? error;

  final Map<String, _BatchLineState> selected = {};
  final List<_BatchLineState> manualLines = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialProductId.isNotEmpty) {
      final product =
          AppDataStore.instance.productOrNull(widget.initialProductId);
      if (product != null && product.active) {
        selected[product.id] =
            _BatchLineState.fromProduct(product, type: widget.type);
      }
    }
  }

  bool get isPurchase => widget.type == 'purchase';
  bool get isReceive => widget.type == 'receive' || isPurchase;
  bool get isDamage => widget.type == 'damage';
  bool get isTransfer => widget.type == 'transfer';

  @override
  void dispose() {
    search.dispose();
    barcode.dispose();
    supplier.dispose();
    invoiceTitle.dispose();
    vendorInvoice.dispose();
    amountPaid.dispose();
    shipping.dispose();
    tax.dispose();
    note.dispose();
    destination.dispose();
    for (final line in selected.values) {
      line.dispose();
    }
    for (final line in manualLines) {
      line.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = AppDataStore.instance;
    final s = widget.s;
    final q = search.text.trim().toLowerCase();
    final products = store.products.where((p) {
      if (!p.active) return false;
      if (q.isEmpty) return true;
      return p.nameAr.toLowerCase().contains(q) ||
          p.nameEn.toLowerCase().contains(q) ||
          p.sku.toLowerCase().contains(q) ||
          p.barcode.toLowerCase().contains(q);
    }).toList();
    final title = switch (widget.type) {
      'purchase' =>
        s.text('إدخال بضاعة للمخزون', 'Stock entry'),
      'receive' =>
        s.text('استلام بضاعة', 'Receive stock'),
      'damage' =>
        s.text('تسجيل تالف لعدة أصناف', 'Record damage for multiple items'),
      _ => s.text('نقل عدة أصناف', 'Transfer multiple items'),
    };

    return AlertDialog(
          scrollable: true,
      title: Row(
        children: [
          Expanded(child: Text(title)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(20)),
            child: Text(
              '${selected.length + manualLines.length} ${s.text('محدد', 'selected')}',
              style: const TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primary),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 1040.0).toDouble(),
        height: MediaQuery.sizeOf(context).height * .78,
        child: Column(
          children: [
            _TopControls(
              s: s,
              search: search,
              barcode: barcode,
              onSearch: () => setState(() {}),
              onBarcode: _scanBarcode,
              allVisibleSelected: products.isNotEmpty &&
                  products.every((p) => selected.containsKey(p.id)),
              onToggleAll: () => _toggleAll(products),
              onAddManual: _addManual,
            ),
            const SizedBox(height: 10),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final picker = _ProductPicker(
                    s: s,
                    products: products,
                    selectedIds: selected.keys.toSet(),
                    onToggle: _toggleProduct,
                  );
                  final editors = _EditorsPanel(
                    s: s,
                    isReceive: isReceive,
                    isTransfer: isTransfer,
                    lines: [...selected.values, ...manualLines],
                    onRemove: _removeLine,
                    onChanged: () => setState(() {}),
                  );
                  if (constraints.maxWidth < 820) {
                    return Column(
                      children: [
                        SizedBox(height: 210, child: picker),
                        const SizedBox(height: 10),
                        Expanded(child: editors),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 310, child: picker),
                      const SizedBox(width: 10),
                      Expanded(child: editors),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            _OperationFooter(
              s: s,
              isReceive: isReceive,
              isTransfer: isTransfer,
              supplier: supplier,
              invoiceTitle: invoiceTitle,
              vendorInvoice: vendorInvoice,
              amountPaid: amountPaid,
              shipping: shipping,
              tax: tax,
              note: note,
              destination: destination,
              paymentMethod: paymentMethod,
              onPaymentMethodChanged: (value) =>
                  setState(() => paymentMethod = value),
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(error!,
                    style: const TextStyle(
                        fontSize: 9,
                        color: AppColors.danger,
                        fontWeight: FontWeight.w800)),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.text('إلغاء', 'Cancel'))),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.check_rounded, size: 17),
          label: Text(s.text('تنفيذ العملية', 'Apply operation')),
        ),
      ],
    );
  }

  void _scanBarcode(String raw) {
    final code = raw.trim();
    if (code.isEmpty) return;
    final store = AppDataStore.instance;
    final product = store.productByBarcodeOrSku(code);
    if (product == null) {
      setState(() => error = widget.s.text(
          'الباركود غير مرتبط بأي صنف. يمكنك إضافة الصنف يدويًا ثم حفظ الباركود من صفحة المنتجات.',
          'Barcode is not linked to an item. Add the item manually, then save its barcode from Products.'));
      barcode.selection = TextSelection(
        baseOffset: 0,
        extentOffset: barcode.text.length,
      );
      return;
    }
    setState(() {
      selected.putIfAbsent(product!.id,
          () => _BatchLineState.fromProduct(product!, type: widget.type));
      search.clear();
      error = null;
    });
    barcode.clear();
  }

  void _toggleProduct(ProductModel product, bool value) {
    setState(() {
      if (value) {
        selected.putIfAbsent(product.id,
            () => _BatchLineState.fromProduct(product, type: widget.type));
      } else {
        selected.remove(product.id)?.dispose();
      }
    });
  }

  void _toggleAll(List<ProductModel> products) {
    final allSelected = products.isNotEmpty &&
        products.every((p) => selected.containsKey(p.id));
    setState(() {
      if (allSelected) {
        for (final p in products) {
          selected.remove(p.id)?.dispose();
        }
      } else {
        for (final p in products) {
          selected.putIfAbsent(
              p.id, () => _BatchLineState.fromProduct(p, type: widget.type));
        }
      }
    });
  }

  void _addManual() {
    setState(() => manualLines.add(_BatchLineState.manual(type: widget.type)));
  }

  void _removeLine(_BatchLineState line) {
    setState(() {
      if (line.productId.isNotEmpty) {
        selected.remove(line.productId)?.dispose();
      } else {
        manualLines.remove(line);
        line.dispose();
      }
    });
  }

  void _submit() {
    final s = widget.s;
    final store = AppDataStore.instance;
    final lines = [...selected.values, ...manualLines];
    if (lines.isEmpty) {
      setState(() => error = s.text(
          'حدد صنفًا واحدًا على الأقل أو أضف صنفًا يدويًا.',
          'Select at least one item or add a manual item.'));
      return;
    }

    for (final line in lines) {
      final validation =
          line.validate(s, receive: isReceive, outgoing: !isReceive);
      if (validation != null) {
        setState(() => error = validation);
        return;
      }
    }

    if (!isReceive) {
      final seenSkus = <String>{};
      for (final line in lines.where((line) => line.productId.isEmpty)) {
        final skuKey = line.newSku.text.trim().toLowerCase();
        if (!seenSkus.add(skuKey) || store.skuExists(line.newSku.text)) {
          setState(() => error = s.text(
              'يوجد SKU مكرر. اختر رمزًا مختلفًا للصنف اليدوي.',
              'A duplicate SKU was found. Choose a different SKU for the manual item.'));
          return;
        }
      }
    }

    if (isReceive) {
      final merchandise = lines.fold<double>(0, (sum, line) => sum + line.total);
      final total = merchandise + _money(shipping.text) + _money(tax.text);
      final paid = _money(amountPaid.text);
      if (paid < 0 || paid > total) {
        setState(() => error = s.text(
            'المبلغ المدفوع يجب أن يكون بين صفر وإجمالي العملية.',
            'Paid amount must be between zero and the operation total.'));
        return;
      }

      final manual = lines.where((line) => line.productId.isEmpty).toList();
      final seenSkus = <String>{};
      final seenBarcodes = <String>{};
      for (final line in manual) {
        final sku = line.newSku.text.trim().toLowerCase();
        final barcodeValue = line.barcode.text.trim();
        if (!seenSkus.add(sku) ||
            store.products.any((p) => p.sku.trim().toLowerCase() == sku)) {
          setState(() => error = s.text(
              'يوجد SKU مكرر. استخدم رمز SKU مختلفًا لكل منتج جديد.',
              'A duplicate SKU was found. Use a unique SKU for every new product.'));
          return;
        }
        if (barcodeValue.isNotEmpty &&
            (!seenBarcodes.add(barcodeValue) ||
                store.products.any((p) => p.barcode == barcodeValue))) {
          setState(() => error = s.text(
              'يوجد باركود مكرر. استخدم باركود مختلفًا أو اتركه فارغًا.',
              'A duplicate barcode was found. Use a different barcode or leave it blank.'));
          return;
        }
      }

      final receiptLines = <PurchaseLine>[];
      for (final line in lines) {
        ProductModel product;
        if (line.productId.isEmpty) {
          final created = store.addInventoryPurchaseProduct(
            nameAr: line.name.text.trim(),
            nameEn: line.nameEn.text.trim(),
            sku: line.newSku.text.trim(),
            barcode: line.barcode.text.trim(),
            categoryAr: line.categoryAr.text.trim(),
            categoryEn: line.categoryEn.text.trim(),
            salePrice: line.salePriceValue,
            cost: line.baseUnitCost,
            minStock: line.minStockValue,
            baseUnit: line.saleUnit,
            purchaseUnit: line.operationUnit,
            unitsPerPurchaseUnit: line.unitsPerUnitValue,
            packageWeightKg: line.packageWeightValue,
            actorName: widget.actorName,
            actorRole: widget.actorRole,
          );
          if (created == null) {
            setState(() => error = s.text(
                'تعذر إنشاء المنتج الجديد. راجع الاسم وSKU والأسعار والوحدات.',
                'Could not create the new product. Check its name, SKU, prices and units.'));
            return;
          }
          product = created;
        } else {
          product = store.product(line.productId);
        }
        receiptLines.add(
          PurchaseLine(
            productId: product.id,
            itemName: product.nameAr,
            quantity: line.quantityValue,
            unitCost: line.purchasePriceValue,
            purchaseUnit: line.operationUnit,
            unitsPerPurchaseUnit: line.unitsPerUnitValue,
            packageWeightKg: line.packageWeightValue,
            saleUnit: line.saleUnit,
            salePrice: line.salePriceValue,
            note: line.itemNote.text.trim(),
          ),
        );
      }
      store.createPurchase(
        lines: receiptLines,
        supplierName: supplier.text.trim().isEmpty
            ? 'Direct supplier'
            : supplier.text.trim(),
        employeeId: widget.actorId,
        employeeName: widget.actorName,
        vendorInvoiceNumber: vendorInvoice.text.trim(),
        paymentMethod: paymentMethod,
        amountPaid: paid,
        shippingCost: _money(shipping.text),
        taxAmount: _money(tax.text),
        note: note.text.trim(),
        invoiceTitle: invoiceTitle.text.trim(),
      );
    } else {
      if (isTransfer && destination.text.trim().isEmpty) {
        setState(() => error =
            s.text('حدد الفرع المستلم.', 'Enter the destination branch.'));
        return;
      }
      for (final line in lines) {
        ProductModel product;
        if (line.productId.isEmpty) {
          final opening = line.manualCurrentStockValue;
          if (opening < line.baseQuantity) {
            setState(() => error = s.text(
                'رصيد الصنف اليدوي يجب أن يغطي كمية الحركة.',
                'Manual item stock must cover the operation quantity.'));
            return;
          }
          product = store.createManualProduct(
              name: line.name.text.trim(),
              sku: line.newSku.text.trim(),
              openingStock: opening);
        } else {
          product = store.product(line.productId);
        }
        final details =
            '${line.quantityValue} ${_unitLabel(s, line.operationUnit)} × ${line.unitsPerUnitValue} ${_unitLabel(s, product.baseUnit)}';
        final movementNote = [
          line.itemNote.text.trim(),
          note.text.trim(),
          details
        ].where((e) => e.isNotEmpty).join(' • ');
        final ok = isDamage
            ? store.recordDamage(
                productId: product.id,
                quantity: line.baseQuantity,
                reason: movementNote.isEmpty ? 'Damaged goods' : movementNote,
                employeeId: widget.actorId,
                employeeName: widget.actorName,
                operationUnit: line.operationUnit,
                operationQuantity: line.quantityValue.toDouble(),
                unitsPerOperationUnit: line.unitsPerUnitValue,
              )
            : store.transferStock(
                productId: product.id,
                quantity: line.baseQuantity,
                destination: destination.text.trim(),
                employeeId: widget.actorId,
                employeeName: widget.actorName,
                operationUnit: line.operationUnit,
                operationQuantity: line.quantityValue.toDouble(),
                unitsPerOperationUnit: line.unitsPerUnitValue,
                note: movementNote,
              );
        if (!ok) {
          setState(() => error = s.text(
              'إحدى الكميات أكبر من المخزون المتاح. راجع الأصناف المحددة.',
              'One quantity exceeds available stock. Review the selected items.'));
          return;
        }
      }
    }

    Navigator.pop(context);
  }
}

class _TopControls extends StatelessWidget {
  const _TopControls({
    required this.s,
    required this.search,
    required this.barcode,
    required this.onSearch,
    required this.onBarcode,
    required this.allVisibleSelected,
    required this.onToggleAll,
    required this.onAddManual,
  });

  final AppStrings s;
  final TextEditingController search;
  final TextEditingController barcode;
  final VoidCallback onSearch;
  final ValueChanged<String> onBarcode;
  final bool allVisibleSelected;
  final VoidCallback onToggleAll;
  final VoidCallback onAddManual;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final searchBox = TextField(
          controller: search,
          onChanged: (_) => onSearch(),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: s.text('ابحث بالاسم، SKU أو الباركود...',
                'Search name, SKU or barcode...'),
          ),
        );
        final barcodeBox = TextField(
          controller: barcode,
          autofocus: true,
          onSubmitted: onBarcode,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.qr_code_scanner_rounded),
            labelText: s.text('قارئ الباركود', 'Barcode scanner'),
            hintText:
                s.text('امسح الباركود ثم Enter', 'Scan barcode then Enter'),
            suffixIcon: IconButton(
                tooltip: s.text('تحديد', 'Select'),
                onPressed: () => onBarcode(barcode.text),
                icon: const Icon(Icons.keyboard_return_rounded, size: 18)),
          ),
        );
        final actions = Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: onToggleAll,
              icon: Icon(
                  allVisibleSelected
                      ? Icons.deselect_rounded
                      : Icons.select_all_rounded,
                  size: 17),
              label: Text(allVisibleSelected
                  ? s.text('إلغاء تحديد الظاهر', 'Clear visible')
                  : s.text('تحديد الظاهر', 'Select visible')),
            ),
            OutlinedButton.icon(
              onPressed: onAddManual,
              icon: const Icon(Icons.edit_note_rounded, size: 17),
              label: Text(s.text('إضافة صنف يدوي', 'Manual item')),
            ),
          ],
        );
        if (c.maxWidth < 700) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                barcodeBox,
                const SizedBox(height: 8),
                searchBox,
                const SizedBox(height: 8),
                actions
              ]);
        }
        return Column(children: [
          Row(children: [
            Expanded(child: barcodeBox),
            const SizedBox(width: 10),
            Expanded(child: searchBox)
          ]),
          const SizedBox(height: 8),
          Align(alignment: AlignmentDirectional.centerEnd, child: actions)
        ]);
      },
    );
  }
}

class _ProductPicker extends StatelessWidget {
  const _ProductPicker(
      {required this.s,
      required this.products,
      required this.selectedIds,
      required this.onToggle});
  final AppStrings s;
  final List<ProductModel> products;
  final Set<String> selectedIds;
  final void Function(ProductModel, bool) onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border)),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(11),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(s.text('الأصناف المتاحة', 'Available items'),
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w900)),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: products.isEmpty
                ? Center(
                    child: Text(s.text('لا توجد نتائج.', 'No results.'),
                        style: const TextStyle(
                            fontSize: 9, color: AppColors.muted)))
                : ListView.separated(
                    itemCount: products.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final p = products[index];
                      return CheckboxListTile(
                        dense: true,
                        value: selectedIds.contains(p.id),
                        onChanged: (value) => onToggle(p, value ?? false),
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(s.text(p.nameAr, p.nameEn),
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w900)),
                        subtitle: Text(
                            '${p.sku} • ${s.text('المخزون', 'Stock')}: ${p.stock}',
                            style: const TextStyle(
                                fontSize: 9, color: AppColors.muted)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _EditorsPanel extends StatelessWidget {
  const _EditorsPanel({
    required this.s,
    required this.isReceive,
    required this.isTransfer,
    required this.lines,
    required this.onRemove,
    required this.onChanged,
  });

  final AppStrings s;
  final bool isReceive;
  final bool isTransfer;
  final List<_BatchLineState> lines;
  final ValueChanged<_BatchLineState> onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) {
      return Container(
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border)),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Text(
          s.text(
              'حدد عدة أصناف بواسطة CHECKBOX، ثم عدّل الكمية والوحدة لكل صنف بشكل مستقل.',
              'Select multiple items with checkboxes, then set quantity and unit for each item independently.'),
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 9.5, height: 1.6, color: AppColors.muted),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border)),
      child: ListView.separated(
        padding: const EdgeInsets.all(10),
        itemCount: lines.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, index) => _BatchLineEditor(
          key: ObjectKey(lines[index]),
          line: lines[index],
          s: s,
          isReceive: isReceive,
          isTransfer: isTransfer,
          onRemove: () => onRemove(lines[index]),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _BatchLineEditor extends StatelessWidget {
  const _BatchLineEditor({
    super.key,
    required this.line,
    required this.s,
    required this.isReceive,
    required this.isTransfer,
    required this.onRemove,
    required this.onChanged,
  });

  final _BatchLineState line;
  final AppStrings s;
  final bool isReceive;
  final bool isTransfer;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final store = AppDataStore.instance;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.inventory_2_outlined,
                      color: AppColors.primary, size: 17)),
              const SizedBox(width: 8),
              Expanded(
                child: line.productId.isEmpty
                    ? Column(children: [
                        TextField(
                            controller: line.name,
                            decoration: InputDecoration(
                                labelText: s.text(
                                    'اسم الصنف بالعربية', 'Product name (Arabic)'),
                                isDense: true)),
                        const SizedBox(height: 6),
                        TextField(
                            controller: line.barcode,
                            decoration: InputDecoration(
                                prefixIcon: const Icon(
                                    Icons.qr_code_scanner_rounded,
                                    size: 17),
                                labelText: s.text(
                                    'باركود الصنف الجديد', 'New item barcode'),
                                isDense: true))
                      ])
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            Text(line.name.text,
                                style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w900)),
                            Text(
                                '${line.sku} • ${s.text('المخزون', 'Stock')}: ${line.stock}',
                                style: const TextStyle(
                                    fontSize: 9, color: AppColors.muted)),
                          ]),
              ),
              IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.close_rounded,
                      size: 17, color: AppColors.danger)),
            ],
          ),
          const SizedBox(height: 9),
          LayoutBuilder(
            builder: (context, c) {
              final width =
                  c.maxWidth < 620 ? c.maxWidth : (c.maxWidth - 20) / 3;
              final fields = <Widget>[
                if (line.productId.isEmpty) ...[
                  SizedBox(
                      width: width,
                      child: TextField(
                          controller: line.nameEn,
                          decoration: InputDecoration(
                              labelText: s.text('اسم الصنف بالإنجليزية', 'Product name (English)'),
                              isDense: true))),
                  SizedBox(
                      width: width,
                      child: TextField(
                          controller: line.newSku,
                          decoration: InputDecoration(
                              labelText: 'SKU',
                              helperText: s.text('أي رمز تختاره؛ بلا صيغة مفروضة، فقط غير مكرر', 'Any text you choose; no enforced format, only unique'),
                              isDense: true))),
                  SizedBox(
                      width: width,
                      child: TextField(
                          controller: line.categoryAr,
                          decoration: InputDecoration(
                              labelText: s.text('التصنيف بالعربية', 'Category (Arabic)'),
                              isDense: true))),
                  SizedBox(
                      width: width,
                      child: TextField(
                          controller: line.categoryEn,
                          decoration: InputDecoration(
                              labelText: s.text('التصنيف بالإنجليزية', 'Category (English)'),
                              isDense: true))),
                  SizedBox(
                      width: width,
                      child: TextField(
                          controller: line.minStock,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                              labelText: s.text('حد تنبيه المخزون', 'Low-stock threshold'),
                              isDense: true))),
                ],
                SizedBox(
                    width: width,
                    child: TextField(
                        controller: line.quantity,
                        onChanged: (_) => onChanged(),
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                            labelText: s.text('الكمية', 'Quantity'),
                            isDense: true))),
                SizedBox(
                    width: width,
                    child: DropdownButtonFormField<String>(
                        value: line.operationUnit,
                        decoration: InputDecoration(
                            labelText: isReceive
                                ? s.text('وحدة الشراء', 'Purchase unit')
                                : s.text('وحدة الحركة', 'Operation unit'),
                            isDense: true),
                        items: inventoryUnits
                            .map((v) => DropdownMenuItem(
                                value: v, child: Text(_unitLabel(s, v))))
                            .toList(),
                        onChanged: (v) {
                          line.operationUnit = v ?? line.operationUnit;
                          onChanged();
                        })),
                SizedBox(
                    width: width,
                    child: TextField(
                        controller: line.unitsPerUnit,
                        onChanged: (_) => onChanged(),
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                            labelText: s.text(
                                'محتوى الوحدة', 'Units per selected unit'),
                            helperText: s.text('مثال: كرتونة = 12 قطعة',
                                'Example: carton = 12 pieces'),
                            isDense: true))),
              ];
              if (isReceive) {
                fields.addAll([
                  SizedBox(
                      width: width,
                      child: TextField(
                          controller: line.purchasePrice,
                          onChanged: (_) => onChanged(),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                              labelText: s.text(
                                  'سعر شراء الوحدة', 'Purchase-unit cost'),
                              isDense: true))),
                  SizedBox(
                      width: width,
                      child: TextField(
                          controller: line.packageWeight,
                          onChanged: (_) => onChanged(),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                              labelText: s.text(
                                  'وزن العبوة/الوحدة كغ', 'Package weight kg'),
                              isDense: true))),
                  SizedBox(
                      width: width,
                      child: DropdownButtonFormField<String>(
                          value: line.saleUnit,
                          decoration: InputDecoration(
                              labelText: s.text('وحدة البيع', 'Sale unit'),
                              isDense: true),
                          items: inventoryUnits
                              .map((v) => DropdownMenuItem(
                                  value: v, child: Text(_unitLabel(s, v))))
                              .toList(),
                          onChanged: (v) {
                            line.saleUnit = v ?? line.saleUnit;
                            onChanged();
                          })),
                  SizedBox(
                      width: width,
                      child: TextField(
                          controller: line.salePrice,
                          onChanged: (_) => onChanged(),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                              labelText: s.text(
                                  'سعر البيع للكاشير', 'POS selling price'),
                              isDense: true))),
                ]);
              } else if (line.productId.isEmpty) {
                fields.add(SizedBox(
                    width: width,
                    child: TextField(
                        controller: line.manualCurrentStock,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                            labelText: s.text('الرصيد الحالي للصنف اليدوي',
                                'Manual item current stock'),
                            isDense: true))));
              }
              fields.add(SizedBox(
                  width: c.maxWidth,
                  child: TextField(
                      controller: line.itemNote,
                      onChanged: (_) => onChanged(),
                      decoration: InputDecoration(
                          labelText: s.text(
                              'ملاحظة خاصة بهذا الصنف', 'Item-specific note'),
                          isDense: true))));
              return Wrap(spacing: 10, runSpacing: 9, children: fields);
            },
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _MiniChip(
                  text:
                      '${s.text('كمية المخزون المتأثرة', 'Base stock quantity')}: ${line.baseQuantity}'),
              if (isReceive)
                _MiniChip(
                    text:
                        '${s.text('تكلفة وحدة البيع', 'Base unit cost')}: ${line.baseUnitCost.toStringAsFixed(3)} ${store.settings.currency}'),
              if (isReceive)
                _MiniChip(
                    text:
                        '${s.text('الإجمالي', 'Line total')}: ${line.total.toStringAsFixed(2)} ${store.settings.currency}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _OperationFooter extends StatelessWidget {
  const _OperationFooter({
    required this.s,
    required this.isReceive,
    required this.isTransfer,
    required this.supplier,
    required this.invoiceTitle,
    required this.vendorInvoice,
    required this.amountPaid,
    required this.shipping,
    required this.tax,
    required this.note,
    required this.destination,
    required this.paymentMethod,
    required this.onPaymentMethodChanged,
  });

  final AppStrings s;
  final bool isReceive;
  final bool isTransfer;
  final TextEditingController supplier;
  final TextEditingController invoiceTitle;
  final TextEditingController vendorInvoice;
  final TextEditingController amountPaid;
  final TextEditingController shipping;
  final TextEditingController tax;
  final TextEditingController note;
  final TextEditingController destination;
  final String paymentMethod;
  final ValueChanged<String> onPaymentMethodChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border)),
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth < 650 ? c.maxWidth : (c.maxWidth - 20) / 3;
          final fields = <Widget>[];
          if (isReceive) {
            fields.addAll([
              SizedBox(
                  width: w,
                  child: TextField(
                      controller: supplier,
                      decoration: InputDecoration(
                          labelText: s.text('المورد', 'Supplier'),
                          isDense: true))),
              SizedBox(
                  width: w,
                  child: TextField(
                      controller: invoiceTitle,
                      decoration: InputDecoration(
                          labelText: s.text('اسم الفاتورة (اختياري)', 'Invoice name (optional)'),
                          isDense: true))),
              SizedBox(
                  width: w,
                  child: TextField(
                      controller: vendorInvoice,
                      decoration: InputDecoration(
                          labelText:
                              s.text('رقم فاتورة المورد', 'Vendor invoice'),
                          isDense: true))),
              SizedBox(
                  width: w,
                  child: DropdownButtonFormField<String>(
                      value: paymentMethod,
                      decoration: InputDecoration(
                          labelText: s.text('طريقة الدفع', 'Payment method'),
                          isDense: true),
                      items: const ['Cash', 'Card', 'Transfer', 'Debt']
                          .map(
                              (v) => DropdownMenuItem(value: v, child: Text(s.paymentMethod(v))))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) onPaymentMethodChanged(v);
                      })),
              SizedBox(
                  width: w,
                  child: TextField(
                      controller: amountPaid,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          labelText: s.text('المبلغ المدفوع', 'Amount paid'),
                          isDense: true))),
              SizedBox(
                  width: w,
                  child: TextField(
                      controller: shipping,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          labelText:
                              s.text('الشحن والمصاريف', 'Shipping & fees'),
                          isDense: true))),
              SizedBox(
                  width: w,
                  child: TextField(
                      controller: tax,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          labelText: s.text('الضريبة', 'Tax'), isDense: true))),
            ]);
          }
          if (isTransfer) {
            fields.add(SizedBox(
                width: w,
                child: TextField(
                    controller: destination,
                    decoration: InputDecoration(
                        labelText:
                            s.text('الفرع المستلم', 'Destination branch'),
                        isDense: true))));
          }
          fields.add(SizedBox(
              width: c.maxWidth < 650 ? c.maxWidth : c.maxWidth,
              child: TextField(
                  controller: note,
                  maxLines: 2,
                  decoration: InputDecoration(
                      labelText:
                          s.text('ملاحظة عامة للعملية', 'Operation note'),
                      isDense: true))));
          return Wrap(spacing: 10, runSpacing: 9, children: fields);
        },
      ),
    );
  }
}

class _BatchLineState {
  _BatchLineState({
    required this.productId,
    required this.sku,
    required this.stock,
    required String name,
    required String nameEnValue,
    required String skuValue,
    required String barcodeValue,
    required String categoryArValue,
    required String categoryEnValue,
    required int minStockValue,
    required int quantity,
    required this.operationUnit,
    required int unitsPerUnit,
    required double purchasePrice,
    required double packageWeight,
    required this.saleUnit,
    required double salePrice,
    required int manualCurrentStock,
  })  : name = TextEditingController(text: name),
        nameEn = TextEditingController(text: nameEnValue),
        newSku = TextEditingController(text: skuValue),
        barcode = TextEditingController(text: barcodeValue),
        categoryAr = TextEditingController(text: categoryArValue),
        categoryEn = TextEditingController(text: categoryEnValue),
        minStock = TextEditingController(text: '$minStockValue'),
        quantity = TextEditingController(text: '$quantity'),
        unitsPerUnit = TextEditingController(text: '$unitsPerUnit'),
        purchasePrice = TextEditingController(
            text: purchasePrice == 0 ? '' : purchasePrice.toStringAsFixed(3)),
        packageWeight =
            TextEditingController(text: packageWeight.toStringAsFixed(3)),
        salePrice = TextEditingController(
            text: salePrice == 0 ? '' : salePrice.toStringAsFixed(2)),
        manualCurrentStock = TextEditingController(text: '$manualCurrentStock'),
        itemNote = TextEditingController();

  factory _BatchLineState.fromProduct(ProductModel product,
      {required String type}) {
    final receive = type == 'receive' || type == 'purchase';
    final unit = receive ? product.purchaseUnit : product.baseUnit;
    final conversion = receive ? product.unitsPerPurchaseUnit : 1;
    return _BatchLineState(
      productId: product.id,
      sku: product.sku,
      stock: product.stock,
      name: product.nameAr,
      nameEnValue: product.nameEn,
      skuValue: product.sku,
      barcodeValue: product.barcode,
      categoryArValue: product.categoryAr,
      categoryEnValue: product.categoryEn,
      minStockValue: product.minStock,
      quantity: 1,
      operationUnit: unit,
      unitsPerUnit: conversion <= 0 ? 1 : conversion,
      purchasePrice: product.cost * (conversion <= 0 ? 1 : conversion),
      packageWeight: product.packageWeightKg,
      saleUnit: product.baseUnit,
      salePrice: product.price,
      manualCurrentStock: product.stock,
    );
  }

  factory _BatchLineState.manual({required String type}) => _BatchLineState(
        productId: '',
        sku: '',
        stock: 0,
        name: '',
        nameEnValue: '',
        skuValue: '',
        barcodeValue: '',
        categoryArValue: 'غير مصنف',
        categoryEnValue: 'Uncategorized',
        minStockValue: 0,
        quantity: 1,
        operationUnit: 'piece',
        unitsPerUnit: 1,
        purchasePrice: 0,
        packageWeight: 0,
        saleUnit: 'piece',
        salePrice: 0,
        manualCurrentStock: 0,
      );

  final String productId;
  final String sku;
  final int stock;
  final TextEditingController name;
  final TextEditingController nameEn;
  final TextEditingController newSku;
  final TextEditingController barcode;
  final TextEditingController categoryAr;
  final TextEditingController categoryEn;
  final TextEditingController minStock;
  final TextEditingController quantity;
  String operationUnit;
  final TextEditingController unitsPerUnit;
  final TextEditingController purchasePrice;
  final TextEditingController packageWeight;
  String saleUnit;
  final TextEditingController salePrice;
  final TextEditingController manualCurrentStock;
  final TextEditingController itemNote;

  int get minStockValue => int.tryParse(minStock.text) ?? 0;
  int get quantityValue => int.tryParse(quantity.text) ?? 0;
  int get unitsPerUnitValue => int.tryParse(unitsPerUnit.text) ?? 0;
  double get purchasePriceValue => _money(purchasePrice.text);
  double get packageWeightValue => _money(packageWeight.text);
  double get salePriceValue => _money(salePrice.text);
  int get manualCurrentStockValue => int.tryParse(manualCurrentStock.text) ?? 0;
  int get baseQuantity =>
      quantityValue * (unitsPerUnitValue <= 0 ? 1 : unitsPerUnitValue);
  double get baseUnitCost => baseQuantity <= 0 ? 0 : total / baseQuantity;
  double get total => quantityValue * purchasePriceValue;

  String? validate(AppStrings s,
      {required bool receive, required bool outgoing}) {
    if (name.text.trim().isEmpty ||
        quantityValue <= 0 ||
        unitsPerUnitValue <= 0) {
      return s.text('راجع اسم الصنف والكمية ومحتوى الوحدة لكل سطر.',
          'Check item name, quantity and unit conversion for every line.');
    }
    if (receive &&
        (purchasePriceValue <= 0 ||
            salePriceValue < 0 ||
            packageWeightValue < 0)) {
      return s.text(
          'كل صنف مستلم يحتاج سعر شراء صحيح، مع التحقق من سعر البيع والوزن.',
          'Each received item needs a valid purchase cost; also check selling price and weight.');
    }
    if (productId.isEmpty) {
      if (newSku.text.trim().isEmpty) {
        return s.text('الصنف الجديد يحتاج SKU فريدًا.',
            'A new item requires a unique SKU.');
      }
      if (receive && minStockValue < 0) {
        return s.text('حد تنبيه المخزون لا يمكن أن يكون سالبًا.',
            'Low-stock threshold cannot be negative.');
      }
      if (receive && salePriceValue <= 0) {
        return s.text('الصنف الجديد يحتاج سعر بيع حتى يظهر بشكل صحيح للكاشير.',
            'A new item needs a selling price so it appears correctly in POS.');
      }
    }
    if (outgoing && productId.isNotEmpty && baseQuantity > stock) {
      return s.text('إحدى الكميات أكبر من الرصيد المتاح.',
          'One selected quantity exceeds available stock.');
    }
    return null;
  }

  void dispose() {
    name.dispose();
    nameEn.dispose();
    newSku.dispose();
    barcode.dispose();
    categoryAr.dispose();
    categoryEn.dispose();
    minStock.dispose();
    quantity.dispose();
    unitsPerUnit.dispose();
    purchasePrice.dispose();
    packageWeight.dispose();
    salePrice.dispose();
    manualCurrentStock.dispose();
    itemNote.dispose();
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.text});
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
                fontSize: 9,
                color: AppColors.muted,
                fontWeight: FontWeight.w700)),
      );
}

const inventoryUnits = [
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
      _ => value,
    };

double _money(String value) => double.tryParse(value.trim()) ?? 0;
