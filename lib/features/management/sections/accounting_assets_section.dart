import 'package:flutter/material.dart';
import '../../../app/app_theme.dart';
import '../../../core/app_strings.dart';
import '../../../core/widgets/surface_card.dart';
import '../../../core/printing/print_service.dart';
import '../../../core/printing/print_templates.dart';
import '../../../data/app_data_store.dart';
import '../../../data/models.dart';
import '../widgets/management_widgets.dart';

class AccountingSection extends StatelessWidget {
  const AccountingSection({super.key, required this.s});
  final AppStrings s;

  @override
  Widget build(BuildContext context) {
    final store = AppDataStore.instance;
    return AnimatedBuilder(
      animation: store,
      builder: (_, __) {
        final snapshot = store.accountingSnapshot();
        final period = store.financialSummary();
        final codes = {...store.trialBalanceDebits.keys, ...store.trialBalanceCredits.keys}.toList()..sort();
        return Column(children: [
          ManagementMetricsGrid(items: [
            ManagementMetric(s.text('صافي المبيعات', 'Net sales'), '${period.netSales.toStringAsFixed(2)} ${store.settings.currency}', Icons.payments_outlined, AppColors.primary),
            ManagementMetric(s.text('صافي الربح', 'Net profit'), '${period.netProfit.toStringAsFixed(2)} ${store.settings.currency}', Icons.trending_up_rounded, period.netProfit >= 0 ? AppColors.success : AppColors.danger),
            ManagementMetric(s.text('الذمم لنا', 'Receivables'), '${snapshot.receivables.toStringAsFixed(2)} ${store.settings.currency}', Icons.person_outline_rounded, AppColors.blue),
            ManagementMetric(s.text('مرتجعات المشتريات', 'Purchase returns'), '${period.purchaseReturns.toStringAsFixed(2)} ${store.settings.currency}', Icons.assignment_return_outlined, AppColors.accent),
            ManagementMetric(s.text('ذمم الموردين', 'Payables'), '${snapshot.payables.toStringAsFixed(2)} ${store.settings.currency}', Icons.local_shipping_outlined, AppColors.accent),
          ]),
          const SizedBox(height: 12),
          SurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              SectionCardHeader(
                title: s.text('الميزانية العمومية', 'Balance sheet'),
                subtitle: s.text('مبنية على الأرصدة الفعلية والذمم والمخزون والأصول، بدون نسب تقديرية.', 'Built from actual balances, receivables, inventory and assets with no estimated liability ratio.'),
                trailing: OutlinedButton.icon(onPressed: () => ThamanPrintService.printDocument(ThamanPrintTemplates.accountingStatement(store, isArabic: s.controller.isArabic)), icon: const Icon(Icons.print_outlined, size: 17), label: Text(s.text('طباعة', 'Print'))),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(18),
                child: LayoutBuilder(builder: (context, c) {
                  final wide = c.maxWidth >= 720;
                  final assets = Column(children: [
                    DetailLine(label: s.text('النقد', 'Cash'), value: '${snapshot.cash.toStringAsFixed(2)} ${store.settings.currency}'),
                    DetailLine(label: s.text('البنك والبطاقات', 'Bank / card'), value: '${snapshot.bank.toStringAsFixed(2)} ${store.settings.currency}'),
                    DetailLine(label: s.text('ذمم العملاء', 'Accounts receivable'), value: '${store.totalReceivables.toStringAsFixed(2)} ${store.settings.currency}'),
                    DetailLine(label: s.text('باقي لنا من مرتجعات الموردين', 'Supplier return receivables'), value: '${store.supplierReturnReceivables.toStringAsFixed(2)} ${store.settings.currency}'),
                    DetailLine(label: s.text('المخزون', 'Inventory'), value: '${snapshot.inventory.toStringAsFixed(2)} ${store.settings.currency}'),
                    DetailLine(label: s.text('الأصول الثابتة الصافية', 'Net fixed assets'), value: '${snapshot.fixedAssetsNet.toStringAsFixed(2)} ${store.settings.currency}'),
                    const Divider(),
                    DetailLine(label: s.text('إجمالي الأصول', 'Total assets'), value: '${snapshot.totalAssets.toStringAsFixed(2)} ${store.settings.currency}'),
                  ]);
                  final liabilities = Column(children: [
                    DetailLine(label: s.text('ذمم الموردين', 'Accounts payable'), value: '${snapshot.payables.toStringAsFixed(2)} ${store.settings.currency}'),
                    DetailLine(label: s.text('ضريبة المبيعات المستحقة', 'Sales tax payable'), value: '${snapshot.salesTaxPayable.toStringAsFixed(2)} ${store.settings.currency}'),
                    const Divider(),
                    DetailLine(label: s.text('إجمالي الالتزامات', 'Total liabilities'), value: '${snapshot.totalLiabilities.toStringAsFixed(2)} ${store.settings.currency}'),
                    DetailLine(label: s.text('حقوق الملكية', 'Equity'), value: '${snapshot.equity.toStringAsFixed(2)} ${store.settings.currency}'),
                    const Divider(),
                    DetailLine(label: s.text('الالتزامات + حقوق الملكية', 'Liabilities + equity'), value: '${(snapshot.totalLiabilities + snapshot.equity).toStringAsFixed(2)} ${store.settings.currency}'),
                  ]);
                  return wide ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: assets), const SizedBox(width: 28), Expanded(child: liabilities)]) : Column(children: [assets, const SizedBox(height: 12), liabilities]);
                }),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          SurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              SectionCardHeader(
                title: s.text('ميزان المراجعة', 'Trial balance'),
                subtitle: store.journalIsBalanced ? s.text('القيود متزنة: إجمالي المدين يساوي إجمالي الدائن.', 'Journal is balanced: total debits equal total credits.') : s.text('تحذير: يوجد عدم اتزان في القيود.', 'Warning: journal entries are not balanced.'),
                trailing: StatusPill(label: store.journalIsBalanced ? s.text('متزن', 'Balanced') : s.text('غير متزن', 'Unbalanced'), color: store.journalIsBalanced ? AppColors.success : AppColors.danger),
              ),
              const Divider(height: 1),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: [DataColumn(label: Text(s.text('الحساب', 'Account'))), DataColumn(label: Text(s.text('الاسم', 'Name'))), DataColumn(label: Text(s.text('مدين', 'Debit'))), DataColumn(label: Text(s.text('دائن', 'Credit'))), DataColumn(label: Text(s.text('الرصيد', 'Balance')))],
                  rows: [for (final code in codes) DataRow(cells: [DataCell(Text(code)), DataCell(Text(store.accountName(code))), DataCell(Text((store.trialBalanceDebits[code] ?? 0).toStringAsFixed(2))), DataCell(Text((store.trialBalanceCredits[code] ?? 0).toStringAsFixed(2))), DataCell(Text(store.accountBalance(code).toStringAsFixed(2)))])],
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          SurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              SectionCardHeader(title: s.text('آخر القيود اليومية', 'Recent journal entries'), subtitle: s.text('كل عملية مالية رئيسية تنشئ قيدًا مدينًا ودائنًا متوازنًا.', 'Each major financial operation creates a balanced debit/credit entry.')),
              const Divider(height: 1),
              if (store.currentFinancialJournalEntries.isEmpty) EmptyPanel(message: s.text('لا توجد قيود بعد.', 'No journal entries yet.')) else for (final entry in store.currentFinancialJournalEntries.take(20)) ...[
                ListTile(
                  leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.menu_book_outlined, color: AppColors.primary, size: 18)),
                  title: Text('${entry.number} • ${entry.reference}', style: const TextStyle(fontSize: 9.8, fontWeight: FontWeight.w900)),
                  subtitle: Text('${entry.description} • ${formatDateTime(entry.createdAt)}', style: const TextStyle(fontSize: 8.2, color: AppColors.muted)),
                  trailing: Text('${entry.totalDebit.toStringAsFixed(2)} = ${entry.totalCredit.toStringAsFixed(2)}', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, color: entry.balanced ? AppColors.success : AppColors.danger)),
                ),
                if (entry != store.currentFinancialJournalEntries.take(20).last) const Divider(height: 1),
              ],
            ]),
          ),
        ]);
      },
    );
  }
}

class AssetsSection extends StatefulWidget {
  const AssetsSection({super.key, required this.s});
  final AppStrings s;
  @override State<AssetsSection> createState() => _AssetsSectionState();
}

class _AssetsSectionState extends State<AssetsSection> {
  final search = TextEditingController();
  @override void dispose() { search.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final store = AppDataStore.instance;
    final s = widget.s;
    return AnimatedBuilder(
      animation: store,
      builder: (_, __) {
        final q = search.text.toLowerCase();
        final data = store.assets.where((a) => q.isEmpty || a.name.toLowerCase().contains(q) || a.category.toLowerCase().contains(q)).toList();
        return Column(children: [
          ManagementMetricsGrid(items: [
            ManagementMetric(s.text('عدد الأصول', 'Assets'), '${store.assets.where((a) => a.active).length}', Icons.apartment_outlined, AppColors.primary),
            ManagementMetric(s.text('تكلفة الشراء', 'Purchase cost'), '${store.assetPurchaseValue.toStringAsFixed(2)} ${store.settings.currency}', Icons.receipt_long_outlined, AppColors.accent),
            ManagementMetric(s.text('القيمة الدفترية', 'Book value'), '${store.assetBookValue.toStringAsFixed(2)} ${store.settings.currency}', Icons.account_balance_outlined, AppColors.success),
          ]),
          const SizedBox(height: 12),
          SurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              SectionCardHeader(
                title: s.text('سجل الأصول', 'Asset register'),
                subtitle: s.text('قيمة دفترية محسوبة حسب سعر الشراء ونسبة الإهلاك السنوية.', 'Book value calculated from purchase price and annual depreciation rate.'),
                trailing: Wrap(spacing: 8, runSpacing: 8, children: [
                  SearchField(controller: search, hint: s.text('بحث أصل...', 'Search asset...'), onChanged: (_) => setState(() {}), width: 210),
                  OutlinedButton.icon(
                    onPressed: data.isEmpty ? null : () => ThamanPrintService.printDocument(ThamanPrintTemplates.assetsReport(store, assets: data, isArabic: s.controller.isArabic)),
                    icon: const Icon(Icons.print_outlined, size: 17),
                    label: Text(s.text('طباعة الأصول', 'Print assets')),
                  ),
                  FilledButton.icon(onPressed: () => _add(context), icon: const Icon(Icons.add_rounded, size: 17), label: Text(s.text('إضافة أصل', 'Add asset'))),
                ]),
              ),
              const Divider(height: 1),
              if (data.isEmpty)
                EmptyPanel(message: s.text('لا توجد أصول.', 'No assets.'))
              else
                for (final a in data) ...[
                  ListTile(
                    onTap: () => _details(context, a),
                    leading: Container(width: 38, height: 38, decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(11)), child: const Icon(Icons.precision_manufacturing_outlined, color: AppColors.primary, size: 18)),
                    title: Text(a.name, style: const TextStyle(fontSize: 9.7, fontWeight: FontWeight.w900)),
                    subtitle: Text('${s.assetCategory(a.category)} • ${formatDate(a.purchaseDate)} • ${a.annualDepreciationRate.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 8.2, color: AppColors.muted)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('${a.bookValueAt(DateTime.now()).toStringAsFixed(2)} ${store.settings.currency}', style: const TextStyle(fontSize: 9.2, fontWeight: FontWeight.w900)),
                      const SizedBox(width: 8),
                      StatusPill(label: a.active ? s.text('نشط', 'Active') : s.text('مؤرشف', 'Archived'), color: a.active ? AppColors.success : AppColors.muted),
                    ]),
                  ),
                  if (a != data.last) const Divider(height: 1),
                ],
            ]),
          ),
        ]);
      },
    );
  }

  Future<void> _add(BuildContext context) async {
    final s = widget.s;
    final name = TextEditingController();
    final category = TextEditingController(text: s.text('معدات', 'Equipment'));
    final price = TextEditingController();
    final rate = TextEditingController(text: '20');
    final note = TextEditingController();
    DateTime date = DateTime.now();
    await showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          scrollable: true,
          title: Text(s.text('إضافة أصل', 'Add asset')),
          content: SizedBox(
            width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 480.0).toDouble(),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: name, decoration: InputDecoration(labelText: s.text('اسم الأصل', 'Asset name'))),
                const SizedBox(height: 8),
                TextField(controller: category, decoration: InputDecoration(labelText: s.text('التصنيف', 'Category'))),
                const SizedBox(height: 8),
                TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: s.text('سعر الشراء', 'Purchase price'))),
                const SizedBox(height: 8),
                TextField(controller: rate, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: s.text('نسبة الإهلاك السنوية %', 'Annual depreciation %'))),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.text('تاريخ الشراء', 'Purchase date'), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800)),
                  subtitle: Text(formatDate(date)),
                  trailing: OutlinedButton(
                    onPressed: () async {
                      final d = await showDatePicker(context: context, firstDate: DateTime(2000), lastDate: DateTime.now(), initialDate: date);
                      if (d != null) setD(() => date = d);
                    },
                    child: Text(s.text('تغيير', 'Change')),
                  ),
                ),
                TextField(controller: note, maxLines: 2, decoration: InputDecoration(labelText: s.text('ملاحظة', 'Note'))),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(s.text('إلغاء', 'Cancel'))),
            FilledButton(
              onPressed: () {
                final p = double.tryParse(price.text) ?? 0;
                final r = double.tryParse(rate.text) ?? 0;
                if (name.text.trim().isEmpty || p <= 0) return;
                AppDataStore.instance.addAsset(name: name.text.trim(), category: category.text.trim(), purchaseDate: date, purchasePrice: p, annualDepreciationRate: r, note: note.text.trim());
                Navigator.pop(context);
              },
              child: Text(s.text('حفظ', 'Save')),
            ),
          ],
        ),
      ),
    );
    for (final c in [name, category, price, rate, note]) { c.dispose(); }
  }

  void _details(BuildContext context, AssetRecord asset) {
    final s = widget.s;
    final store = AppDataStore.instance;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
          scrollable: true,
        title: Text(asset.name),
        content: SizedBox(
          width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 480.0).toDouble(),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DetailLine(label: s.text('التصنيف', 'Category'), value: s.assetCategory(asset.category)),
            DetailLine(label: s.text('تاريخ الشراء', 'Purchase date'), value: formatDate(asset.purchaseDate)),
            DetailLine(label: s.text('سعر الشراء', 'Purchase price'), value: '${asset.purchasePrice.toStringAsFixed(2)} ${store.settings.currency}'),
            DetailLine(label: s.text('الإهلاك المتراكم', 'Accumulated depreciation'), value: '${asset.accumulatedDepreciationAt(DateTime.now()).toStringAsFixed(2)} ${store.settings.currency}'),
            DetailLine(label: s.text('القيمة الدفترية', 'Book value'), value: '${asset.bookValueAt(DateTime.now()).toStringAsFixed(2)} ${store.settings.currency}'),
            DetailLine(label: s.text('الملاحظة', 'Note'), value: asset.note.isEmpty ? '—' : asset.note),
          ]),
        ),
        actions: [
          TextButton(onPressed: () { store.setAssetActive(asset.id, !asset.active); Navigator.pop(context); }, child: Text(asset.active ? s.text('أرشفة', 'Archive') : s.text('إعادة تفعيل', 'Reactivate'))),
          OutlinedButton.icon(
            onPressed: () => ThamanPrintService.printDocument(ThamanPrintTemplates.assetsReport(store, assets: [asset], isArabic: s.controller.isArabic)),
            icon: const Icon(Icons.print_outlined, size: 16),
            label: Text(s.text('طباعة الأصل', 'Print asset')),
          ),
          FilledButton(onPressed: () => Navigator.pop(context), child: Text(s.text('إغلاق', 'Close'))),
        ],
      ),
    );
  }
}
