import 'package:flutter/material.dart';
import '../../core/time_format.dart';
import '../../app/app_theme.dart';
import '../../core/app_controller.dart';
import '../../core/app_strings.dart';
import '../../core/widgets/app_logo.dart';
import '../../core/printing/print_service.dart';
import '../../core/printing/print_templates.dart';
import '../../data/app_data_store.dart';
import '../../data/models.dart';
import '../inventory/stock_count_start_dialog.dart';

class StockCountScreen extends StatefulWidget {
  const StockCountScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  State<StockCountScreen> createState() => _StockCountScreenState();
}

class _StockCountScreenState extends State<StockCountScreen> {
  final search = TextEditingController();

  StockCountSession get session => AppDataStore.instance.stockCounts.firstWhere(
        (s) => s.id == widget.sessionId,
      );

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final s = AppStrings(controller);
    final blindCount = controller.role == UserRole.inventory;
    final managementReviewer =
        controller.role == UserRole.owner || controller.role == UserRole.manager;
    final managementOwnedSession = session.employeeId.startsWith('ADMIN-');
    final canEditSession = session.status == 'open' &&
        (blindCount
            ? session.employeeId == controller.employeeId
            : managementOwnedSession);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Row(
          children: [
            const AppLogo(compact: true),
            const SizedBox(width: 12),
            Text(
              s.text(
                'جلسة جرد ${session.number}',
                'Stock count ${session.number}',
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: s.text(
              blindCount ? 'طباعة الجرد' : 'طباعة إشعار الجرد',
              blindCount ? 'Print count' : 'Print stock-count notice',
            ),
            onPressed: () => _printCount(context, s),
            icon: const Icon(Icons.print_outlined),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: AnimatedBuilder(
        animation: AppDataStore.instance,
        builder: (context, _) {
          final q = search.text.trim().toLowerCase();

          final lines = session.lines.where((line) {
            final product = AppDataStore.instance.productOrNull(line.productId);

            return q.isEmpty ||
                line.itemName.toLowerCase().contains(q) ||
                (product?.sku.toLowerCase().contains(q) ?? false) ||
                (product?.barcode.contains(q) ?? false);
          }).toList();

          final store = AppDataStore.instance;

          final changed = session.lines
              .where(
                (l) =>
                    l.counted &&
                    l.actual != store.stockCountExpectedQuantity(session, l),
              )
              .length;

          final remaining = session.lines.where((l) => !l.counted).length;

          return Column(
            children: [
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
                child: LayoutBuilder(
                  builder: (context, c) {
                    final searchBox = TextField(
                      controller: search,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (value) => _scanBarcode(value, s),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(
                          Icons.qr_code_scanner_rounded,
                        ),
                        hintText: s.text(
                          'بحث أو امسح الباركود ثم Enter...',
                          'Search or scan barcode then press Enter...',
                        ),
                      ),
                    );

                    final addExisting = OutlinedButton.icon(
                      onPressed: canEditSession ? () => _addExisting(context, s) : null,
                      icon: const Icon(
                        Icons.playlist_add_check_rounded,
                        size: 17,
                      ),
                      label: Text(
                        s.text('إضافة أصناف', 'Add items'),
                      ),
                    );

                    final add = OutlinedButton.icon(
                      onPressed: canEditSession ? () => _addManual(context, s) : null,
                      icon: const Icon(
                        Icons.edit_note_rounded,
                        size: 17,
                      ),
                      label: Text(
                        s.text('صنف يدوي', 'Manual item'),
                      ),
                    );

                    final countStatus = Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: blindCount
                            ? AppColors.primarySoft
                            : changed == 0
                                ? AppColors.primarySoft
                                : AppColors.accentSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            blindCount
                                ? s.text('جرد محايد', 'Blind count')
                                : '${s.text('فروقات', 'Differences')}: $changed',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: blindCount || changed == 0
                                  ? AppColors.primary
                                  : AppColors.accent,
                            ),
                          ),
                          Text(
                            '${s.text('متبقي للجرد', 'Not counted')}: $remaining',
                            style: const TextStyle(
                              fontSize: 7.8,
                              color: AppColors.muted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    );

                    if (c.maxWidth < 720) {
                      return Column(
                        children: [
                          searchBox,
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              addExisting,
                              add,
                              countStatus,
                            ],
                          ),
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(child: searchBox),
                        const SizedBox(width: 8),
                        addExisting,
                        const SizedBox(width: 8),
                        add,
                        const SizedBox(width: 8),
                        countStatus,
                      ],
                    );
                  },
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(18),
                  itemCount: lines.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 9),
                  itemBuilder: (context, index) {
                    final line = lines[index];

                    final product = AppDataStore.instance.productOrNull(
                      line.productId,
                    );

                    final expected =
                        AppDataStore.instance.stockCountExpectedQuantity(
                      session,
                      line,
                    );

                    return _CountLineCard(
                      key: ValueKey('count-${line.productId}'),
                      line: line,
                      expected: expected,
                      editable: canEditSession,
                      showVariance: !blindCount,
                      product: product,
                      sku: product?.sku ?? '',
                      s: s,
                      onDetails: blindCount
                          ? null
                          : () => _showMovementDetails(context, s, line),
                      onChanged: (
                        enteredQuantity,
                        unit,
                        unitsPerUnit,
                      ) =>
                          AppDataStore.instance.updateStockCountEntry(
                        session.id,
                        line.productId,
                        enteredQuantity: enteredQuantity,
                        unit: unit,
                        unitsPerUnit: unitsPerUnit,
                      ),
                    );
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(
                      color: AppColors.border,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        blindCount
                            ? s.text(
                                'أدخل الكميات الفعلية فقط. الكمية المتوقعة والفروقات مخفية وتظهر للإدارة بعد الإرسال.',
                                'Enter physical quantities only. Expected stock and variances stay hidden and are shown to management after submission.',
                              )
                            : s.text(
                                session.status == 'submitted'
                                    ? 'الجرد مرسل للمراجعة. راجع الفروقات ثم اعتمدها لتحديث المخزون.'
                                    : !managementOwnedSession
                                        ? 'الجرد قيد التنفيذ لدى موظف المخزن. يمكنك متابعة التقدم، والاعتماد يتاح بعد الإرسال.'
                                        : 'الجرد لا يعدّل المخزون إلا بعد اعتماد الإدارة.',
                                session.status == 'submitted'
                                    ? 'The count is submitted for review. Review variances, then approve to update inventory.'
                                    : !managementOwnedSession
                                        ? 'The inventory employee is counting. You can monitor progress; approval unlocks after submission.'
                                        : 'Inventory is updated only after management approval.',
                              ),
                        style: const TextStyle(
                          fontSize: 9,
                          color: AppColors.muted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: () => _printCount(context, s),
                      icon: const Icon(Icons.print_outlined, size: 18),
                      label: Text(
                        s.text(
                          blindCount ? 'طباعة الجرد' : 'طباعة إشعار الجرد',
                          blindCount ? 'Print count' : 'Print count notice',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: session.status == 'completed' ||
                              (session.status == 'submitted' && blindCount) ||
                              (!blindCount && !managementReviewer) ||
                              (!blindCount && session.status == 'open' && !managementOwnedSession)
                          ? null
                          : () => _complete(context, s),
                      icon: const Icon(
                        Icons.verified_rounded,
                        size: 18,
                      ),
                      label: Text(
                        s.text(
                          blindCount
                              ? 'إرسال للإدارة'
                              : session.status == 'submitted'
                                  ? 'اعتماد الفروقات'
                                  : 'اعتماد الجرد',
                          blindCount
                              ? 'Submit to management'
                              : session.status == 'submitted'
                                  ? 'Approve variances'
                                  : 'Complete count',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _printCount(
    BuildContext context,
    AppStrings s,
  ) async {
    final blindCount = s.controller.role == UserRole.inventory;
    final document = blindCount
        ? ThamanPrintTemplates.stockCountCounterCopy(
            AppDataStore.instance,
            session,
            isArabic: s.controller.isArabic,
          )
        : ThamanPrintTemplates.stockCount(
            AppDataStore.instance,
            session,
            isArabic: s.controller.isArabic,
          );
    final ok = await ThamanPrintService.printDocument(document);

    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            s.text(
              'تعذر فتح نافذة الطباعة على هذا الجهاز.',
              'Could not open the print dialog on this device.',
            ),
          ),
        ),
      );
    }
  }

  void _scanBarcode(
    String raw,
    AppStrings s,
  ) {
    final code = raw.trim();

    if (code.isEmpty) return;

    final store = AppDataStore.instance;
    final found = store.productByBarcodeOrSku(code);

    if (found == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            s.text(
              'لم يتم العثور على صنف بهذا الباركود.',
              'No item found for this barcode.',
            ),
          ),
        ),
      );
      return;
    }

    if (!session.lines.any(
      (l) => l.productId == found.id,
    )) {
      store.addExistingStockCountLines(
        session.id,
        [found.id],
      );
    }

    search.text = found.barcode.isNotEmpty ? found.barcode : found.sku;

    setState(() {});
  }

  Future<void> _addExisting(
    BuildContext context,
    AppStrings s,
  ) async {
    final ids = await showStockCountStartDialog(
      context,
      s,
    );

    if (ids == null || ids.isEmpty) return;

    AppDataStore.instance.addExistingStockCountLines(
      session.id,
      ids,
    );

    search.clear();

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _addManual(
    BuildContext context,
    AppStrings s,
  ) async {
    final name = TextEditingController();
    final sku = TextEditingController();

    final value = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => AlertDialog(
        scrollable: true,
        title: Text(
          s.text(
            'إضافة صنف يدوي للجرد',
            'Add manual stock-count item',
          ),
        ),
        content: SizedBox(
          width: (MediaQuery.sizeOf(context).width - 48)
              .clamp(0.0, 420.0)
              .toDouble(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: s.text('اسم الصنف', 'Item name'),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: sku,
                decoration: InputDecoration(
                  labelText: 'SKU',
                  helperText: s.text(
                    'اكتب أي رمز تريده؛ لا توجد صيغة مفروضة. يجب فقط ألا يتكرر.',
                    'Choose any SKU text you want; no format is enforced. It only needs to be unique.',
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.text('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              {
                'name': name.text.trim(),
                'sku': sku.text.trim(),
              },
            ),
            child: Text(s.text('إضافة', 'Add')),
          ),
        ],
      ),
    );

    name.dispose();
    sku.dispose();

    final itemName = value?['name']?.trim() ?? '';
    final skuValue = value?['sku']?.trim() ?? '';
    if (itemName.isEmpty || skuValue.isEmpty) return;

    if (AppDataStore.instance.skuExists(skuValue)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              s.text(
                'هذا الـ SKU مستخدم مسبقًا. اختر رمزًا مختلفًا.',
                'This SKU is already in use. Choose a different one.',
              ),
            ),
          ),
        );
      }
      return;
    }

    AppDataStore.instance.addManualStockCountLine(
      session.id,
      itemName,
      skuValue,
    );

    search.clear();

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _showMovementDetails(
    BuildContext context,
    AppStrings s,
    StockCountLine line,
  ) async {
    if (s.controller.role == UserRole.inventory) return;
    final store = AppDataStore.instance;

    final b = store.stockCountBreakdown(
      session.id,
      line.productId,
    );

    String typeLabel(String type) => switch (type) {
          'sale' => s.text('بيع', 'Sale'),
          'damage' => s.text('تالف', 'Damage'),
          'receive' => s.text('استلام', 'Receiving'),
          'return' => s.text('مرتجع', 'Return'),
          'transfer' => s.text('نقل', 'Transfer'),
          'count' => s.text(
              'تعديل جرد سابق',
              'Previous count adjustment',
            ),
          _ => type,
        };

    Widget metric(
      String label,
      String value, {
      Color? color,
    }) {
      return Container(
        width: 132,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: AppColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 7.8,
                color: AppColors.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: color ?? AppColors.text,
              ),
            ),
          ],
        ),
      );
    }

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
          scrollable: true,
        title: Text(
          s.text(
            'تفاصيل حركة ${line.itemName}',
            '${line.itemName} movement details',
          ),
        ),
        content: SizedBox(
          width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 760.0).toDouble(),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${s.text('الفترة', 'Period')}: '
                  '${_countDate(b.periodStart)} → '
                  '${_countDate(b.periodEnd)}',
                  style: const TextStyle(
                    fontSize: 8.8,
                    color: AppColors.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    metric(
                      s.text(
                        'رصيد البداية',
                        'Opening stock',
                      ),
                      '${b.openingStock}',
                    ),
                    metric(
                      s.text('استلام', 'Received'),
                      '+${b.received}',
                      color: AppColors.success,
                    ),
                    metric(
                      s.text(
                        'مرتجعات داخلة',
                        'Returns in',
                      ),
                      '+${b.returned}',
                      color: AppColors.success,
                    ),
                    metric(
                      s.text('مباع', 'Sold'),
                      '-${b.sold}',
                      color: AppColors.danger,
                    ),
                    metric(
                      s.text('تالف', 'Damaged'),
                      '-${b.damaged}',
                      color: AppColors.danger,
                    ),
                    metric(
                      s.text(
                        'نقل للخارج',
                        'Transferred out',
                      ),
                      '-${b.transferredOut}',
                      color: AppColors.danger,
                    ),
                    metric(
                      s.text(
                        'تعديلات أخرى',
                        'Other adjustments',
                      ),
                      '${b.adjustments >= 0 ? '+' : ''}'
                      '${b.adjustments}',
                      color: AppColors.blue,
                    ),
                    metric(
                      s.text(
                        'المتوقع بالنظام',
                        'System expected',
                      ),
                      '${b.expected}',
                      color: AppColors.primary,
                    ),
                    metric(
                      s.text(
                        'الفعلي المعدود',
                        'Physical count',
                      ),
                      line.counted
                          ? '${b.actual}'
                          : s.text(
                              'لم يُعد بعد',
                              'Not counted yet',
                            ),
                      color: line.counted ? AppColors.accent : AppColors.muted,
                    ),
                    metric(
                      s.text(
                        'الفرق',
                        'Difference',
                      ),
                      line.counted
                          ? '${b.difference >= 0 ? '+' : ''}'
                              '${b.difference}'
                          : '—',
                      color: line.counted && b.difference != 0
                          ? AppColors.danger
                          : AppColors.primary,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(
                    '${b.openingStock} + '
                    '${b.received} + '
                    '${b.returned} - '
                    '${b.sold} - '
                    '${b.damaged} - '
                    '${b.transferredOut} '
                    '${b.adjustments >= 0 ? '+' : '-'} '
                    '${b.adjustments.abs()} = '
                    '${b.reconciledExpected}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  s.text(
                    'الحركات المسجلة',
                    'Recorded movements',
                  ),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                if (b.movements.isEmpty)
                  Text(
                    s.text(
                      'لا توجد حركات مسجلة خلال فترة المراجعة.',
                      'No movements recorded in this review period.',
                    ),
                    style: const TextStyle(
                      fontSize: 9,
                      color: AppColors.muted,
                    ),
                  )
                else
                  for (final movement in b.movements)
                    Container(
                      margin: const EdgeInsets.only(
                        bottom: 6,
                      ),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: movement.quantity >= 0
                                  ? AppColors.primarySoft
                                  : AppColors.accentSoft,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Text(
                              '${movement.quantity >= 0 ? '+' : ''}'
                              '${movement.quantity}',
                              style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w900,
                                color: movement.quantity >= 0
                                    ? AppColors.primary
                                    : AppColors.danger,
                              ),
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${typeLabel(movement.type)} • '
                                  '${movement.reference.isEmpty ? s.text('بدون مرجع', 'No reference') : movement.reference}',
                                  style: const TextStyle(
                                    fontSize: 9.2,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  '${_countDate(movement.createdAt)} • '
                                  '${movement.employeeName.isEmpty ? s.text('النظام', 'System') : movement.employeeName}'
                                  '${movement.note.isEmpty ? '' : ' • ${movement.note}'}',
                                  style: const TextStyle(
                                    fontSize: 8,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              s.text('إغلاق', 'Close'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _complete(
    BuildContext context,
    AppStrings s,
  ) async {
    final controller = s.controller;
    final blindCount = controller.role == UserRole.inventory;
    final managerRole = controller.role == UserRole.owner
        ? 'owner'
        : controller.role == UserRole.manager
            ? 'manager'
            : '';
    final remaining = session.lines.where((line) => !line.counted).length;

    if (remaining > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            s.text(
              'لا يمكن إنهاء الجرد قبل إدخال الكمية الفعلية لكل الأصناف. متبقي: $remaining',
              'Enter the physical quantity for every item before finishing the count. Remaining: $remaining',
            ),
          ),
        ),
      );
      return;
    }

    if (blindCount) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(s.text('إرسال الجرد للإدارة؟', 'Submit count to management?')),
          content: Text(s.text(
            'سيتم قفل إدخالات الجرد وإرسال الكميات الفعلية للمدير والمالك لمراجعة الفروقات. لن يتم تعديل المخزون الآن.',
            'The count will be locked and physical quantities sent to the manager/owner for variance review. Inventory will not change yet.',
          )),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.text('إلغاء', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(s.text('إرسال', 'Submit'))),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      final submitted = AppDataStore.instance.submitStockCount(session.id);
      if (!submitted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.text('تعذر إرسال الجرد.', 'Could not submit the count.'))));
        return;
      }
      Navigator.of(context).pop();
      return;
    }

    if (managerRole.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(s.text('اعتماد فروقات الجرد؟', 'Approve stock-count variances?')),
        content: Text(s.text(
          'سيتم تطبيق الكميات الفعلية على المخزون وتسجيل كل فرق في سجل الحركات والقيود المحاسبية.',
          'Physical quantities will be applied to inventory and every variance recorded in stock movements and accounting entries.',
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.text('إلغاء', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(s.text('اعتماد', 'Approve'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final completed = AppDataStore.instance.approveStockCount(
      session.id,
      actorName: controller.currentUserName,
      actorRole: managerRole,
    );
    if (!completed) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.text('تعذر اعتماد الجرد.', 'Could not approve the count.'))));
      return;
    }
    Navigator.of(context).pop();
  }

}

class _CountLineCard extends StatefulWidget {
  const _CountLineCard({
    super.key, // ✅ تم إصلاح مشكلة key
    required this.line,
    required this.expected,
    required this.editable,
    required this.showVariance,
    required this.product,
    required this.sku,
    required this.s,
    required this.onDetails,
    required this.onChanged,
  });

  final StockCountLine line;
  final int expected;
  final bool editable;
  final bool showVariance;
  final ProductModel? product;
  final String sku;
  final AppStrings s;
  final VoidCallback? onDetails;
  final void Function(
    int enteredQuantity,
    String unit,
    int unitsPerUnit,
  ) onChanged;

  @override
  State<_CountLineCard> createState() => _CountLineCardState();
}

class _CountLineCardState extends State<_CountLineCard> {
  late final TextEditingController quantityController;
  late final TextEditingController unitsController;

  late String selectedUnit;

  final quantityFocus = FocusNode();
  final unitsFocus = FocusNode();

  @override
  void initState() {
    super.initState();

    quantityController = TextEditingController(
      text: widget.line.counted ? '${widget.line.enteredQuantity}' : '',
    );

    unitsController = TextEditingController(
      text: '${widget.line.unitsPerCountUnit}',
    );

    selectedUnit = _countUnits.contains(widget.line.countUnit)
        ? widget.line.countUnit
        : 'piece';

    // Commit values whenever the operator leaves either field. This is
    // especially important with barcode/keyboard-heavy desktop workflows
    // where focus can jump without onEditingComplete firing consistently.
    quantityFocus.addListener(_commitOnFocusLoss);
    unitsFocus.addListener(_commitOnFocusLoss);
  }

  void _commitOnFocusLoss() {
    if (!quantityFocus.hasFocus && !unitsFocus.hasFocus) {
      _commit();
    }
  }

  @override
  void didUpdateWidget(
    covariant _CountLineCard oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);

    if (!quantityFocus.hasFocus &&
        oldWidget.line.enteredQuantity != widget.line.enteredQuantity &&
        int.tryParse(quantityController.text) != widget.line.enteredQuantity) {
      quantityController.text =
          widget.line.counted ? '${widget.line.enteredQuantity}' : '';
    }

    if (!unitsFocus.hasFocus &&
        oldWidget.line.unitsPerCountUnit != widget.line.unitsPerCountUnit &&
        int.tryParse(unitsController.text) != widget.line.unitsPerCountUnit) {
      unitsController.text = '${widget.line.unitsPerCountUnit}';
    }

    if (oldWidget.line.countUnit != widget.line.countUnit &&
        _countUnits.contains(widget.line.countUnit)) {
      selectedUnit = widget.line.countUnit;
    }
  }

  @override
  void dispose() {
    quantityFocus.removeListener(_commitOnFocusLoss);
    unitsFocus.removeListener(_commitOnFocusLoss);
    quantityController.dispose();
    unitsController.dispose();
    quantityFocus.dispose();
    unitsFocus.dispose();
    super.dispose();
  }

  void _commit() {
    final rawQuantity = quantityController.text.trim();

    final rawUnits = unitsController.text.trim();

    if (rawQuantity.isEmpty || rawUnits.isEmpty) {
      return;
    }

    final entered = int.tryParse(rawQuantity);
    final units = int.tryParse(rawUnits);

    if (entered == null || units == null || entered < 0 || units <= 0) {
      return;
    }

    widget.onChanged(
      entered,
      selectedUnit,
      units,
    );
  }

  void _commitLive() {
    final entered = int.tryParse(quantityController.text);

    final units = int.tryParse(unitsController.text);

    if (entered == null || entered < 0 || units == null || units <= 0) {
      return;
    }

    widget.onChanged(
      entered,
      selectedUnit,
      units,
    );

    if (mounted) {
      setState(() {});
    }
  }

  void _selectUnit(String value) {
    selectedUnit = value;

    final product = widget.product;

    if (product != null) {
      if (value == product.baseUnit) {
        unitsController.text = '1';
      } else if (value == product.purchaseUnit) {
        unitsController.text =
            '${product.unitsPerPurchaseUnit <= 0 ? 1 : product.unitsPerPurchaseUnit}';
      }
    }

    setState(() {});
    _commit();
  }

  @override
  Widget build(BuildContext context) {
    final diff = widget.line.counted ? widget.line.actual - widget.expected : 0;

    final product = widget.product;

    final baseUnit = product?.baseUnit ?? 'piece';

    final expectedLabel = '${widget.expected} '
        '${_countUnitLabel(widget.s, baseUnit)}';

    final actualLabel = widget.line.counted
        ? '${widget.line.actual} '
            '${_countUnitLabel(widget.s, baseUnit)}'
        : widget.s.text(
            'لم يُعد بعد',
            'Not counted yet',
          );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: !widget.showVariance || diff == 0
              ? AppColors.border
              : AppColors.accent.withValues(alpha: .4),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;

          final identity = Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.inventory_2_outlined,
                  color: AppColors.primary,
                  size: 19,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.line.itemName,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.showVariance
                          ? '${widget.sku} • ${widget.s.text('المتوقع', 'Expected')}: $expectedLabel'
                          : widget.sku,
                      style: const TextStyle(
                        fontSize: 9.4,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${widget.s.text('الفعلي بعد التحويل', 'Converted actual')}: '
                      '$actualLabel',
                      style: const TextStyle(
                        fontSize: 9.1,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          final controls = Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 105,
                child: TextField(
                  controller: quantityController,
                  focusNode: quantityFocus,
                  enabled: widget.editable,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    labelText: widget.s.text(
                      'الكمية',
                      'Quantity',
                    ),
                    isDense: true,
                  ),
                  onChanged: (_) => _commitLive(),
                  onSubmitted: (_) => _commit(),
                  onEditingComplete: () {
                    _commit();
                    FocusScope.of(context).unfocus();
                  },
                  onTapOutside: (_) {
                    _commit();
                    FocusScope.of(context).unfocus();
                  },
                ),
              ),
              SizedBox(
                width: 130,
                child: DropdownButtonFormField<String>(
                  value: selectedUnit,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: widget.s.text(
                      'الوحدة',
                      'Unit',
                    ),
                    isDense: true,
                  ),
                  items: _countUnits
                      .map(
                        (unit) => DropdownMenuItem(
                          value: unit,
                          child: Text(
                            _countUnitLabel(
                              widget.s,
                              unit,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: widget.editable
                      ? (value) {
                          if (value != null) {
                            _selectUnit(value);
                          }
                        }
                      : null,
                ),
              ),
              SizedBox(
                width: 125,
                child: TextField(
                  controller: unitsController,
                  focusNode: unitsFocus,
                  enabled: widget.editable,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    labelText: widget.s.text(
                      'محتوى الوحدة',
                      'Units / unit',
                    ),
                    isDense: true,
                  ),
                  onChanged: (_) => _commitLive(),
                  onSubmitted: (_) => _commit(),
                  onEditingComplete: () {
                    _commit();
                    FocusScope.of(context).unfocus();
                  },
                  onTapOutside: (_) {
                    _commit();
                    FocusScope.of(context).unfocus();
                  },
                ),
              ),
              if (widget.showVariance)
                OutlinedButton.icon(
                onPressed: widget.onDetails,
                icon: const Icon(
                  Icons.receipt_long_outlined,
                  size: 15,
                ),
                label: Text(
                  widget.s.text(
                    'تفاصيل الحركة',
                    'Movement details',
                  ),
                  style: const TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (widget.showVariance)
                Container(
                width: 100,
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: diff == 0
                      ? AppColors.surfaceAlt
                      : diff > 0
                          ? AppColors.primarySoft
                          : AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Column(
                  children: [
                    Text(
                      !widget.line.counted
                          ? widget.s.text(
                              'الفرق',
                              'Difference',
                            )
                          : diff < 0
                              ? widget.s.text(
                                  'النقص',
                                  'Shortage',
                                )
                              : diff > 0
                                  ? widget.s.text(
                                      'الزيادة',
                                      'Surplus',
                                    )
                                  : widget.s.text(
                                      'مطابق',
                                      'Matched',
                                    ),
                      style: const TextStyle(
                        fontSize: 7.5,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      !widget.line.counted
                          ? '—'
                          : diff == 0
                              ? '0'
                              : '${diff.abs()}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: !widget.line.counted || diff == 0
                            ? AppColors.muted
                            : diff > 0
                                ? AppColors.success
                                : AppColors.danger,
                      ),
                    ),
                    if (widget.line.counted && diff != 0)
                      Text(
                        '${widget.s.text('المتوقع', 'Expected')} '
                        '${widget.expected} • '
                        '${widget.s.text('الموجود', 'Actual')} '
                        '${widget.line.actual}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 6.6,
                          color: AppColors.muted,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                identity,
                const SizedBox(height: 12),
                controls,
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: identity),
              const SizedBox(width: 14),
              controls,
            ],
          );
        },
      ),
    );
  }
}

String _countDate(DateTime value) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(value.day)}/${two(value.month)}/${value.year} ${formatHour12(value)}';
}

const _countUnits = [
  'piece',
  'pack',
  'carton',
  'box',
  'bag',
  'kg',
  'gram',
  'liter',
  'bottle',
  'roll',
];

String _countUnitLabel(
  AppStrings s,
  String value,
) =>
    switch (value) {
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
