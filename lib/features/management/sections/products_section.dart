import 'package:flutter/material.dart';
import '../../../app/app_theme.dart';
import '../../../core/app_controller.dart';
import '../../../core/app_strings.dart';
import '../../../core/permissions.dart';
import '../../../core/widgets/surface_card.dart';
import '../../../core/printing/print_document.dart';
import '../../../core/printing/print_service.dart';
import '../../../data/app_data_store.dart';
import '../../../data/models.dart';
import '../widgets/management_widgets.dart';

class ProductsSection extends StatefulWidget {
  const ProductsSection({super.key, required this.s});
  final AppStrings s;

  @override
  State<ProductsSection> createState() => _ProductsSectionState();
}

class _ProductsSectionState extends State<ProductsSection> {
  final search = TextEditingController();
  final selectedIds = <String>{};

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = AppDataStore.instance;
    final s = widget.s;
    final canManage = s.controller.can(Permission.manageProducts);
    final canCost = s.controller.can(Permission.viewCost) ||
        s.controller.can(Permission.viewProfit) ||
        canManage;

    return AnimatedBuilder(
      animation: store,
      builder: (_, __) {
        final q = search.text.trim().toLowerCase();
        final data = store.products.where((p) {
          return q.isEmpty ||
              p.nameAr.toLowerCase().contains(q) ||
              p.nameEn.toLowerCase().contains(q) ||
              p.sku.toLowerCase().contains(q) ||
              p.barcode.toLowerCase().contains(q) ||
              p.categoryAr.toLowerCase().contains(q) ||
              p.categoryEn.toLowerCase().contains(q);
        }).toList();

        return Column(
          children: [
            ManagementMetricsGrid(
              items: [
                ManagementMetric(
                  s.text('المنتجات النشطة', 'Active products'),
                  '${store.products.where((p) => p.active).length}',
                  Icons.inventory_2_outlined,
                  AppColors.primary,
                ),
                ManagementMetric(
                  s.text('قيمة المخزون', 'Inventory value'),
                  '${store.inventoryValue.toStringAsFixed(0)} ${store.settings.currency}',
                  Icons.account_balance_wallet_outlined,
                  AppColors.blue,
                ),
                ManagementMetric(
                  s.text('منخفض المخزون', 'Low stock'),
                  '${store.lowStock.length}',
                  Icons.warning_amber_rounded,
                  AppColors.danger,
                ),
                ManagementMetric(
                  s.text('ملاحظات نشطة', 'Active notes'),
                  '${store.productNotes.where((n) => n.active).length}',
                  Icons.sticky_note_2_outlined,
                  AppColors.accent,
                ),
              ],
            ),
            const SizedBox(height: 12),
            SurfaceCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  SectionCardHeader(
                    title: s.text('قائمة المنتجات', 'Product list'),
                    subtitle: s.text(
                      'ابحث في الأصناف، راجع أسعار البيع والتكلفة، وأدر ملاحظات المخزون والشراء.',
                      'Search products, review selling/cost prices and manage inventory or purchasing notes.',
                    ),
                    trailing: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SearchField(
                          controller: search,
                          hint: s.text('اسم، SKU، باركود...', 'Name, SKU, barcode...'),
                          onChanged: (_) => setState(() {}),
                          width: 250,
                        ),
                        OutlinedButton.icon(
                          onPressed: data.isEmpty ? null : () => _printProducts(data, canCost),
                          icon: const Icon(Icons.print_outlined, size: 17),
                          label: Text(s.text('طباعة القائمة', 'Print list')),
                        ),
                        if (canManage) ...[
                          OutlinedButton.icon(
                            onPressed: () => setState(() {
                              final ids = data.map((p) => p.id).toSet();
                              if (ids.isNotEmpty && ids.every(selectedIds.contains)) {
                                selectedIds.removeAll(ids);
                              } else {
                                selectedIds.addAll(ids);
                              }
                            }),
                            icon: const Icon(Icons.select_all_rounded, size: 17),
                            label: Text(s.text('تحديد الظاهر', 'Select visible')),
                          ),
                          if (selectedIds.isNotEmpty)
                            FilledButton.tonalIcon(
                              onPressed: () => _addBulkNote(context),
                              icon: const Icon(Icons.sticky_note_2_outlined, size: 17),
                              label: Text('${s.text('ملاحظة للمحدد', 'Note selected')} (${selectedIds.length})'),
                            ),
                          FilledButton.icon(
                            onPressed: () => _showProductEditor(context),
                            icon: const Icon(Icons.add_rounded, size: 17),
                            label: Text(s.text('إضافة صنف', 'Add product')),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  if (data.isEmpty)
                    EmptyPanel(message: s.text('لا توجد منتجات مطابقة.', 'No matching products.'))
                  else
                    for (final p in data) ...[
                      ListTile(
                        onTap: () => _details(context, p, canCost, canManage),
                        leading: SizedBox(
                          width: canManage ? 78 : 42,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (canManage)
                                Checkbox(
                                  value: selectedIds.contains(p.id),
                                  onChanged: (value) => setState(() {
                                    if (value == true) { selectedIds.add(p.id); } else { selectedIds.remove(p.id); }
                                  }),
                                ),
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: !p.active ? AppColors.surfaceAlt : p.stock <= p.minStock ? AppColors.accentSoft : AppColors.primarySoft,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  p.active ? Icons.inventory_2_outlined : Icons.inventory_2_rounded,
                                  color: !p.active ? AppColors.muted : p.stock <= p.minStock ? AppColors.accent : AppColors.primary,
                                  size: 19,
                                ),
                              ),
                            ],
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${s.text(p.nameAr, p.nameEn)} • ${p.sku}',
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
                              ),
                            ),
                            if (!p.active)
                              StatusPill(label: s.text('موقوف', 'Inactive'), color: AppColors.muted),
                          ],
                        ),
                        subtitle: Text(
                          '${s.text(p.categoryAr, p.categoryEn)} • ${s.text('المخزون', 'Stock')}: ${p.stock} ${_unitLabel(s, p.baseUnit)} • ${s.text('حد الطلب', 'Reorder')}: ${p.minStock}',
                          style: const TextStyle(fontSize: 8.5, color: AppColors.muted),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${p.price.toStringAsFixed(2)} ${store.settings.currency}',
                                  style: const TextStyle(fontSize: 9.6, fontWeight: FontWeight.w900),
                                ),
                                Text(
                                  s.text('سعر البيع', 'Selling price'),
                                  style: const TextStyle(fontSize: 7.5, color: AppColors.muted),
                                ),
                              ],
                            ),
                            const SizedBox(width: 8),
                            if (canManage)
                              Badge(
                                isLabelVisible: store.notesForProduct(p.id).isNotEmpty,
                                label: Text('${store.notesForProduct(p.id).length}'),
                                child: IconButton(
                                  tooltip: s.text('إضافة ملاحظة', 'Add note'),
                                  onPressed: () => _addNote(context, p),
                                  icon: const Icon(Icons.sticky_note_2_outlined, size: 18, color: AppColors.primary),
                                ),
                              )
                            else
                              Badge(
                                isLabelVisible: store.notesForProduct(p.id).isNotEmpty,
                                label: Text('${store.notesForProduct(p.id).length}'),
                                child: const Icon(Icons.sticky_note_2_outlined, size: 18, color: AppColors.muted),
                              ),
                            if (canManage) ...[
                              const SizedBox(width: 2),
                              IconButton(
                                tooltip: s.text('تعديل الصنف والأسعار', 'Edit product & prices'),
                                onPressed: () => _showProductEditor(context, product: p),
                                icon: const Icon(Icons.edit_outlined, size: 18),
                              ),
                            ] else ...[
                              const SizedBox(width: 5),
                              const Icon(Icons.arrow_outward_rounded, size: 16),
                            ],
                          ],
                        ),
                      ),
                      if (p != data.last) const Divider(height: 1),
                    ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _printProducts(List<ProductModel> products, bool canCost) async {
    final store = AppDataStore.instance;
    final s = widget.s;
    final headers = <String>[
      s.text('الصنف', 'Item'),
      'SKU',
      s.text('الباركود', 'Barcode'),
      s.text('الفئة', 'Category'),
      s.text('المخزون', 'Stock'),
      s.text('حد الطلب', 'Reorder'),
      s.text('سعر البيع', 'Selling price'),
      if (canCost) s.text('متوسط التكلفة', 'Average cost'),
      if (canCost) s.text('قيمة المخزون', 'Stock value'),
      s.text('الحالة', 'Status'),
    ];
    final rows = products.map((p) => <String>[
      s.text(p.nameAr, p.nameEn),
      p.sku,
      p.barcode.isEmpty ? '-' : p.barcode,
      s.text(p.categoryAr, p.categoryEn),
      '${p.stock} ${_unitLabel(s, p.baseUnit)}',
      '${p.minStock}',
      '${p.price.toStringAsFixed(2)} ${store.settings.currency}',
      if (canCost) '${p.cost.toStringAsFixed(3)} ${store.settings.currency}',
      if (canCost) '${(p.cost * p.stock).toStringAsFixed(2)} ${store.settings.currency}',
      p.active ? s.text('نشط', 'Active') : s.text('موقوف', 'Inactive'),
    ]).toList();
    await ThamanPrintService.printDocument(PrintDocument(
      title: s.text('سجل المنتجات والمخزون', 'Products & Inventory Register'),
      subtitle: '${store.settings.storeName} • ${store.settings.branchName}',
      metadata: {
        s.text('عدد الأصناف', 'Items'): '${products.length}',
        s.text('فلتر البحث', 'Search filter'): search.text.trim().isEmpty ? '-' : search.text.trim(),
      },
      headers: headers,
      rows: rows,
      summary: {
        s.text('إجمالي الوحدات', 'Total units'): '${products.fold<int>(0, (sum, p) => sum + p.stock)}',
        if (canCost) s.text('قيمة المخزون', 'Inventory value'): '${products.fold<double>(0, (sum, p) => sum + p.cost * p.stock).toStringAsFixed(2)} ${store.settings.currency}',
      },
      footer: store.settings.receiptFooter,
    
      isArabic: s.controller.isArabic,));
  }

  Future<void> _addBulkNote(BuildContext context) async {
    if (selectedIds.isEmpty) return;
    final s = widget.s;
    final text = TextEditingController();
    String audience = 'inventory';
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, setD) => AlertDialog(
          scrollable: true,
          title: Text(s.text('ملاحظة لعدة أصناف', 'Note for multiple products')),
          content: SizedBox(width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 500.0).toDouble(), child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${selectedIds.length} ${s.text('صنف محدد', 'products selected')}', style: const TextStyle(fontSize: 9, color: AppColors.muted)),
            const SizedBox(height: 10),
            TextField(controller: text, maxLines: 3, decoration: InputDecoration(labelText: s.text('الملاحظة', 'Note'))),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(value: audience, decoration: InputDecoration(labelText: s.text('تظهر لمن؟', 'Visible to')), items: [DropdownMenuItem(value: 'inventory', child: Text(s.text('موظف المخزن', 'Inventory staff'))), DropdownMenuItem(value: 'purchasing', child: Text(s.text('مسؤول الشراء', 'Purchasing staff'))), DropdownMenuItem(value: 'both', child: Text(s.text('المخزون والشراء', 'Inventory & purchasing')))], onChanged: (v) => setD(() => audience = v ?? audience)),
          ])),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(s.text('إلغاء', 'Cancel'))), FilledButton(onPressed: () => Navigator.pop(dialogContext, text.text.trim().isNotEmpty), child: Text(s.text('حفظ للمحدد', 'Save to selected')))],
        ),
      ),
    );
    if (saved == true) {
      final store = AppDataStore.instance;
      for (final id in selectedIds) {
        store.addProductNote(productId: id, text: text.text.trim(), audience: audience, createdBy: s.controller.currentUserName);
      }
      if (mounted) setState(() => selectedIds.clear());
    }
    text.dispose();
  }

  void _details(BuildContext context, ProductModel p, bool canCost, bool canManage) {
    final s = widget.s;
    final store = AppDataStore.instance;
    showDialog<void>(
      context: context,
      builder: (_) => AnimatedBuilder(
        animation: store,
        builder: (dialogContext, __) {
          final notes = store.notesForProduct(p.id);
          return AlertDialog(
          scrollable: true,
            title: Text(s.text(p.nameAr, p.nameEn)),
            content: SizedBox(
              width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 640.0).toDouble(),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DetailLine(label: 'SKU', value: p.sku),
                    DetailLine(label: s.text('الباركود', 'Barcode'), value: p.barcode.isEmpty ? '-' : p.barcode),
                    DetailLine(label: s.text('الفئة', 'Category'), value: s.text(p.categoryAr, p.categoryEn)),
                    DetailLine(label: s.text('سعر البيع للكاشير', 'POS selling price'), value: '${p.price.toStringAsFixed(2)} ${store.settings.currency}'),
                    if (canCost)
                      DetailLine(label: s.text('تكلفة الوحدة الفعلية', 'Actual unit cost'), value: '${p.cost.toStringAsFixed(3)} ${store.settings.currency}'),
                    if (canCost)
                      DetailLine(label: s.text('هامش الربح', 'Margin'), value: '${p.margin.toStringAsFixed(1)}%'),
                    DetailLine(label: s.text('وحدة البيع/المخزون', 'Sale / stock unit'), value: _unitLabel(s, p.baseUnit)),
                    DetailLine(label: s.text('وحدة الشراء', 'Purchase unit'), value: _unitLabel(s, p.purchaseUnit)),
                    DetailLine(label: s.text('محتوى وحدة الشراء', 'Units per purchase unit'), value: '${p.unitsPerPurchaseUnit} ${_unitLabel(s, p.baseUnit)}'),
                    if (p.packageWeightKg > 0)
                      DetailLine(label: s.text('وزن وحدة الشراء', 'Purchase-unit weight'), value: '${p.packageWeightKg.toStringAsFixed(3)} kg'),
                    DetailLine(label: s.text('المخزون', 'Stock'), value: '${p.stock} ${_unitLabel(s, p.baseUnit)}'),
                    DetailLine(label: s.text('حد إعادة الطلب', 'Reorder level'), value: '${p.minStock}'),
                    DetailLine(label: s.text('الحالة', 'Status'), value: p.active ? s.text('نشط', 'Active') : s.text('موقوف', 'Inactive')),
                    if (canManage) ...[
                      const SizedBox(height: 4),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonalIcon(
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            _showProductEditor(context, product: p);
                          },
                          icon: const Icon(Icons.edit_outlined, size: 17),
                          label: Text(s.text('تعديل بيانات الصنف والأسعار', 'Edit product data & prices')),
                        ),
                      ),
                    ],
                    const Divider(height: 26),
                    Row(
                      children: [
                        Expanded(child: Text(s.text('ملاحظات الموظفين', 'Staff notes'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900))),
                        FilledButton.tonalIcon(
                          onPressed: () => _addNote(dialogContext, p),
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: Text(s.text('إضافة ملاحظة', 'Add note')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (notes.isEmpty)
                      Text(s.text('لا توجد ملاحظات نشطة.', 'No active notes.'), style: const TextStyle(fontSize: 9, color: AppColors.muted))
                    else
                      for (final n in notes)
                        Container(
                          margin: const EdgeInsets.only(bottom: 7),
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(12)),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(n.text, style: const TextStyle(fontSize: 9.2, fontWeight: FontWeight.w800)),
                                    const SizedBox(height: 3),
                                    Text('${_audience(s, n.audience)} • ${n.createdBy} • ${formatDateTime(n.createdAt)}', style: const TextStyle(fontSize: 8, color: AppColors.muted)),
                                  ],
                                ),
                              ),
                              IconButton(onPressed: () => store.dismissProductNote(n.id), icon: const Icon(Icons.close_rounded, size: 16)),
                            ],
                          ),
                        ),
                  ],
                ),
              ),
            ),
            actions: [FilledButton(onPressed: () => Navigator.pop(dialogContext), child: Text(s.text('إغلاق', 'Close')))],
          );
        },
      ),
    );
  }

  Future<void> _showProductEditor(BuildContext context, {ProductModel? product}) async {
    final s = widget.s;
    final canManage = s.controller.can(Permission.manageProducts);
    if (!canManage) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _ProductEditorDialog(s: s, product: product),
    );
  }

  Future<void> _addNote(BuildContext context, ProductModel p) async {
    final s = widget.s;
    final text = TextEditingController();
    String audience = 'inventory';
    await showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, setD) => AlertDialog(
          scrollable: true,
          title: Text(s.text('إضافة ملاحظة للمنتج', 'Add product note')),
          content: SizedBox(
            width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 480.0).toDouble(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: text, maxLines: 3, decoration: InputDecoration(labelText: s.text('الملاحظة', 'Note'))),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: audience,
                  decoration: InputDecoration(labelText: s.text('تظهر لمن؟', 'Visible to')),
                  items: [
                    DropdownMenuItem(value: 'inventory', child: Text(s.text('موظف المخزن', 'Inventory staff'))),
                    DropdownMenuItem(value: 'purchasing', child: Text(s.text('مسؤول الشراء', 'Purchasing staff'))),
                    DropdownMenuItem(value: 'both', child: Text(s.text('المخزون والشراء', 'Inventory & purchasing'))),
                  ],
                  onChanged: (v) => setD(() => audience = v ?? 'inventory'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(s.text('إلغاء', 'Cancel'))),
            FilledButton(
              onPressed: () {
                if (text.text.trim().isEmpty) return;
                AppDataStore.instance.addProductNote(
                  productId: p.id,
                  text: text.text.trim(),
                  audience: audience,
                  createdBy: s.controller.currentUserName,
                );
                Navigator.pop(dialogContext);
              },
              child: Text(s.text('حفظ', 'Save')),
            ),
          ],
        ),
      ),
    );
    text.dispose();
  }
}

class _ProductEditorDialog extends StatefulWidget {
  const _ProductEditorDialog({required this.s, this.product});
  final AppStrings s;
  final ProductModel? product;

  @override
  State<_ProductEditorDialog> createState() => _ProductEditorDialogState();
}

class _ProductEditorDialogState extends State<_ProductEditorDialog> {
  late final TextEditingController nameAr;
  late final TextEditingController nameEn;
  late final TextEditingController sku;
  late final TextEditingController barcode;
  late final TextEditingController categoryAr;
  late final TextEditingController categoryEn;
  late final TextEditingController salePrice;
  late final TextEditingController cost;
  late final TextEditingController stock;
  late final TextEditingController minStock;
  late final TextEditingController unitsPerPurchase;
  late final TextEditingController packageWeight;
  late String baseUnit;
  late String purchaseUnit;
  late bool active;
  String? error;

  bool get editing => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    nameAr = TextEditingController(text: p?.nameAr ?? '');
    nameEn = TextEditingController(text: p?.nameEn ?? '');
    sku = TextEditingController(text: p?.sku ?? '');
    barcode = TextEditingController(text: p?.barcode ?? '');
    categoryAr = TextEditingController(text: p?.categoryAr ?? 'عام');
    categoryEn = TextEditingController(text: p?.categoryEn ?? 'General');
    salePrice = TextEditingController(text: p == null ? '' : p.price.toStringAsFixed(2));
    cost = TextEditingController(text: p == null ? '' : p.cost.toStringAsFixed(3));
    stock = TextEditingController(text: p == null ? '0' : p.stock.toString());
    minStock = TextEditingController(text: p == null ? '0' : p.minStock.toString());
    unitsPerPurchase = TextEditingController(text: p?.unitsPerPurchaseUnit.toString() ?? '1');
    packageWeight = TextEditingController(text: (p?.packageWeightKg ?? 0) == 0 ? '' : p!.packageWeightKg.toStringAsFixed(3));
    baseUnit = p?.baseUnit ?? 'piece';
    purchaseUnit = p?.purchaseUnit ?? 'piece';
    active = p?.active ?? true;
  }

  @override
  void dispose() {
    nameAr.dispose();
    nameEn.dispose();
    sku.dispose();
    barcode.dispose();
    categoryAr.dispose();
    categoryEn.dispose();
    salePrice.dispose();
    cost.dispose();
    stock.dispose();
    minStock.dispose();
    unitsPerPurchase.dispose();
    packageWeight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final store = AppDataStore.instance;
    return AlertDialog(
          scrollable: true,
      title: Text(editing ? s.text('تعديل الصنف والأسعار', 'Edit product & prices') : s.text('إضافة صنف جديد', 'Add new product')),
      content: SizedBox(
        width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 720.0).toDouble(),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    const Icon(Icons.price_change_outlined, color: AppColors.primary, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        s.text(
                          'سعر البيع المحفوظ هنا هو السعر الذي سيظهر للكاشير مباشرة. سعر الشراء يستخدم لحساب التكلفة والربح.',
                          'The selling price saved here is the price shown to the cashier. Purchase cost is used for cost and profit calculations.',
                        ),
                        style: const TextStyle(fontSize: 8.7, color: AppColors.primary, fontWeight: FontWeight.w700, height: 1.45),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, c) {
                  final two = c.maxWidth >= 560;
                  final w = two ? (c.maxWidth - 10) / 2 : c.maxWidth;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      SizedBox(width: w, child: TextField(controller: nameAr, decoration: InputDecoration(labelText: s.text('اسم الصنف بالعربية', 'Arabic product name')))),
                      SizedBox(width: w, child: TextField(controller: nameEn, decoration: InputDecoration(labelText: s.text('اسم الصنف بالإنجليزية', 'English product name')))),
                      SizedBox(width: w, child: TextField(controller: sku, decoration: InputDecoration(labelText: s.text('SKU (اختياري)', 'SKU (optional)'), helperText: s.text('اختياري. إن تركته فارغًا سيُولَّد رمز تلقائيًا، وإذا كتبته يجب ألا يتكرر.', 'Optional. Leave empty to auto-generate; if entered it must be unique.')))),
                      SizedBox(width: w, child: TextField(controller: barcode, decoration: InputDecoration(labelText: s.text('الباركود', 'Barcode')))),
                      SizedBox(width: w, child: TextField(controller: categoryAr, decoration: InputDecoration(labelText: s.text('الفئة بالعربية', 'Arabic category')))),
                      SizedBox(width: w, child: TextField(controller: categoryEn, decoration: InputDecoration(labelText: s.text('الفئة بالإنجليزية', 'English category')))),
                      SizedBox(width: w, child: TextField(controller: salePrice, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: s.text('سعر البيع للكاشير', 'POS selling price'), suffixText: store.settings.currency))),
                      SizedBox(width: w, child: TextField(controller: cost, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: s.text('تكلفة وحدة البيع', 'Cost per sale unit'), suffixText: store.settings.currency))),
                      if (!editing)
                        SizedBox(width: w, child: TextField(controller: stock, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: s.text('رصيد افتتاحي', 'Opening stock')))),
                      SizedBox(width: w, child: TextField(controller: minStock, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: s.text('حد إعادة الطلب', 'Reorder level')))),
                      SizedBox(
                        width: w,
                        child: DropdownButtonFormField<String>(
                          value: baseUnit,
                          decoration: InputDecoration(labelText: s.text('وحدة البيع/المخزون', 'Sale / stock unit')),
                          items: _units.map((v) => DropdownMenuItem(value: v, child: Text(_unitLabel(s, v)))).toList(),
                          onChanged: (v) => setState(() => baseUnit = v ?? baseUnit),
                        ),
                      ),
                      SizedBox(
                        width: w,
                        child: DropdownButtonFormField<String>(
                          value: purchaseUnit,
                          decoration: InputDecoration(labelText: s.text('وحدة الشراء', 'Purchase unit')),
                          items: _units.map((v) => DropdownMenuItem(value: v, child: Text(_unitLabel(s, v)))).toList(),
                          onChanged: (v) => setState(() => purchaseUnit = v ?? purchaseUnit),
                        ),
                      ),
                      SizedBox(width: w, child: TextField(controller: unitsPerPurchase, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: s.text('محتوى وحدة الشراء', 'Units per purchase unit'), helperText: s.text('مثال: الكرتونة = 12 عبوة', 'Example: carton = 12 packs')))),
                      SizedBox(width: w, child: TextField(controller: packageWeight, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: s.text('وزن وحدة الشراء بالكيلو (اختياري)', 'Purchase-unit weight kg (optional)')))),
                    ],
                  );
                },
              ),
              if (editing) ...[
                const SizedBox(height: 10),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: active,
                  onChanged: (v) => setState(() => active = v),
                  title: Text(s.text('الصنف نشط ومتاح للبيع', 'Product is active and available for sale'), style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800)),
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(fontSize: 9, color: AppColors.danger, fontWeight: FontWeight.w700)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s.text('إلغاء', 'Cancel'))),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined, size: 17),
          label: Text(s.text('حفظ', 'Save')),
        ),
      ],
    );
  }

  void _save() {
    final s = widget.s;
    final store = AppDataStore.instance;
    final sale = double.tryParse(salePrice.text.trim());
    final purchaseCost = double.tryParse(cost.text.trim());
    final opening = int.tryParse(stock.text.trim()) ?? 0;
    final reorder = int.tryParse(minStock.text.trim());
    final units = int.tryParse(unitsPerPurchase.text.trim());
    final weight = packageWeight.text.trim().isEmpty ? 0.0 : double.tryParse(packageWeight.text.trim());

    if (nameAr.text.trim().isEmpty || sale == null || purchaseCost == null || reorder == null || units == null || weight == null || sale < 0 || purchaseCost < 0 || opening < 0 || reorder < 0 || units <= 0 || weight < 0) {
      setState(() => error = s.text('تحقق من الاسم والأسعار والكميات والوحدات.', 'Check the name, prices, quantities and units.'));
      return;
    }

    final controller = s.controller;
    final role = switch (controller.role) {
      UserRole.owner => 'owner',
      UserRole.manager => 'manager',
      _ => '',
    };
    if (role.isEmpty) {
      setState(() => error = s.text('لا تملك صلاحية تعديل الأصناف.', 'You do not have permission to manage products.'));
      return;
    }

    bool ok;
    if (editing) {
      ok = store.updateManagedProduct(
        productId: widget.product!.id,
        nameAr: nameAr.text,
        nameEn: nameEn.text,
        sku: sku.text,
        barcode: barcode.text,
        categoryAr: categoryAr.text,
        categoryEn: categoryEn.text,
        salePrice: sale,
        cost: purchaseCost,
        minStock: reorder,
        baseUnit: baseUnit,
        purchaseUnit: purchaseUnit,
        unitsPerPurchaseUnit: units,
        packageWeightKg: weight,
        active: active,
        actorName: controller.currentUserName,
        actorRole: role,
      );
    } else {
      ok = store.addManagedProduct(
            nameAr: nameAr.text,
            nameEn: nameEn.text,
            sku: sku.text,
            barcode: barcode.text,
            categoryAr: categoryAr.text,
            categoryEn: categoryEn.text,
            salePrice: sale,
            cost: purchaseCost,
            openingStock: opening,
            minStock: reorder,
            baseUnit: baseUnit,
            purchaseUnit: purchaseUnit,
            unitsPerPurchaseUnit: units,
            packageWeightKg: weight,
            actorName: controller.currentUserName,
            actorRole: role,
          ) !=
          null;
    }

    if (!ok) {
      setState(() => error = s.text('تعذر الحفظ. SKU يقبل أي صيغة تختارها، لكن يجب ألا يتكرر. تحقق أيضًا من الباركود وباقي البيانات.', 'Could not save. SKU can use any format you choose, but it must be unique. Also check the barcode and other data.'));
      return;
    }
    Navigator.pop(context);
  }
}

String _audience(AppStrings s, String a) => a == 'inventory'
    ? s.text('للمخزون', 'Inventory')
    : a == 'purchasing'
        ? s.text('للشراء', 'Purchasing')
        : s.text('للمخزون والشراء', 'Inventory & purchasing');

const _units = ['piece', 'pack', 'carton', 'box', 'bag', 'kg', 'gram', 'liter', 'bottle', 'roll'];

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
