import 'package:flutter/material.dart';
import '../../core/time_format.dart';
import '../../app/app_theme.dart';
import '../../core/app_controller.dart';
import '../../core/app_strings.dart';
import '../../core/permissions.dart';
import '../../core/widgets/brand_pattern.dart';
import '../../core/widgets/surface_card.dart';
import '../../data/app_data_store.dart';

class OwnerDashboard extends StatelessWidget {
  const OwnerDashboard({super.key, required this.role, required this.onNavigate});
  final UserRole role;
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final s = AppStrings(controller);
    final store = AppDataStore.instance;
    final canSeeProfit = controller.can(Permission.viewProfit);

    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final now = DateTime.now();
        final monthStart = DateTime(now.year, now.month, 1);
        final nextMonth = now.month == 12 ? DateTime(now.year + 1, 1, 1) : DateTime(now.year, now.month + 1, 1);
        final monthFinance = store.financialSummary(start: monthStart, end: nextMonth);
        final sales = monthFinance.netSales;
        final invoiceCount = store.invoices.where((i) => !i.voided && !i.createdAt.isBefore(monthStart) && i.createdAt.isBefore(nextMonth)).length;
        final avgTicket = invoiceCount == 0 ? 0 : sales / invoiceCount;
        final returns = store.returns.where((r) => !r.createdAt.isBefore(monthStart) && r.createdAt.isBefore(nextMonth)).fold<double>(0, (sum, r) => sum + r.total);
        final profit = monthFinance.netProfit;

        return SingleChildScrollView(
          padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 700 ? 16 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Hero(s: s, sales: sales, invoiceCount: invoiceCount),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, c) {
                  final columns = c.maxWidth >= 1200 ? 5 : c.maxWidth >= 760 ? 3 : 2;
                  final cards = <_KpiData>[
                    _KpiData(s.text('صافي المبيعات • هذا الشهر', 'Net sales • this month'), '${sales.toStringAsFixed(2)} ${store.settings.currency}', s.text('اضغط للتفاصيل', 'Open details'), Icons.trending_up_rounded, AppColors.primary, 'netSalesDetails'),
                    _KpiData(s.text('الفواتير • هذا الشهر', 'Invoices • this month'), '$invoiceCount', s.text('السجل الكامل', 'Full register'), Icons.receipt_long_outlined, AppColors.blue, 'invoiceDetails'),
                    _KpiData(s.text('متوسط السلة', 'Average ticket'), '${avgTicket.toStringAsFixed(2)} ${store.settings.currency}', s.text('تحليل المبيعات', 'Sales analysis'), Icons.shopping_bag_outlined, AppColors.accent, 'averageTicketDetails'),
                    _KpiData(s.text('المرتجعات • هذا الشهر', 'Returns • this month'), '${returns.toStringAsFixed(2)} ${store.settings.currency}', '${store.returns.length} ${s.text('عملية', 'records')}', Icons.assignment_return_outlined, AppColors.danger, 'returns'),
                    if (canSeeProfit) _KpiData(s.text('صافي الربح • هذا الشهر', 'Net profit • this month'), '${profit.toStringAsFixed(2)} ${store.settings.currency}', s.text('حسب تكلفة الأصناف', 'Based on product cost'), Icons.insights_outlined, AppColors.success, 'profitDetails'),
                  ];
                  return GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: columns,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: columns == 2 ? 1.65 : 1.45,
                    children: cards.map((data) => _KpiCard(data: data, onTap: () => onNavigate(data.target))).toList(),
                  );
                },
              ),
              const SizedBox(height: 14),
              _FinancialSnapshotCard(s: s, canSeeProfit: canSeeProfit, onTap: () => onNavigate('financial')),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, c) {
                  final wide = c.maxWidth >= 980;
                  final chart = _SalesPulse(s: s, onTap: () => onNavigate('reports'));
                  final stock = _StockHealth(s: s, onTap: () => onNavigate('stockAlerts'));
                  return wide ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 7, child: chart), const SizedBox(width: 12), Expanded(flex: 4, child: stock)]) : Column(children: [chart, const SizedBox(height: 12), stock]);
                },
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, c) {
                  final wide = c.maxWidth >= 980;
                  final activity = _ActivityPanel(s: s, onTap: () => onNavigate('sales'));
                  final operations = _OperationsPanel(s: s, onNavigate: onNavigate);
                  return wide ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 7, child: activity), const SizedBox(width: 12), Expanded(flex: 4, child: operations)]) : Column(children: [activity, const SizedBox(height: 12), operations]);
                },
              ),
              const SizedBox(height: 14),
              _TeamSnapshot(s: s, onNavigate: onNavigate),
              const SizedBox(height: 18),
            ],
          ),
        );
      },
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.s, required this.sales, required this.invoiceCount});
  final AppStrings s;
  final double sales;
  final int invoiceCount;

  @override
  Widget build(BuildContext context) {
    final user = s.controller.currentUserName.trim().isEmpty ? s.role(s.controller.role ?? UserRole.owner) : s.controller.currentUserName.trim();
    final store = AppDataStore.instance;
    return BrandPattern(
      dark: true,
      borderRadius: BorderRadius.circular(26),
      child: Container(
        padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 650 ? 20 : 26),
        decoration: BoxDecoration(gradient: const LinearGradient(begin: AlignmentDirectional.topStart, end: AlignmentDirectional.bottomEnd, colors: [AppColors.primaryStrong, Color(0xFF0E5A4F)]), borderRadius: BorderRadius.circular(26), boxShadow: const [BoxShadow(color: Color(0x1A083A34), blurRadius: 34, offset: Offset(0, 14))]),
        child: LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 720;
            final intro = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('THAMAN • MANAGEMENT', style: TextStyle(color: Colors.white.withValues(alpha: .5), fontSize: 8.5, letterSpacing: 1.1, fontWeight: FontWeight.w800)),
              const SizedBox(height: 9),
              Text('${s.text('مرحبًا', 'Welcome')}، $user', style: const TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w900, letterSpacing: -.8)),
              const SizedBox(height: 6),
              Text(s.text('المؤشرات هنا تُحسب من عمليات البيع والمخزون والموظفين المسجلة في النظام.', 'These indicators are calculated from recorded sales, inventory and staff activity.'), style: const TextStyle(color: Color(0xFFC2DAD4), fontSize: 10.2, height: 1.6)),
            ]);
            final summary = Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: .08), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white.withValues(alpha: .1))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _HeroValue(label: s.text('المبيعات', 'Sales'), value: '${sales.toStringAsFixed(0)} ${store.settings.currency}'),
                _divider(),
                _HeroValue(label: s.text('الفواتير', 'Invoices'), value: '$invoiceCount'),
                _divider(),
                _HeroValue(label: s.text('داخل الدوام', 'On shift'), value: '${store.openAttendance.length}', success: true),
              ]),
            );
            return wide ? Row(children: [Expanded(child: intro), const SizedBox(width: 20), summary]) : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [intro, const SizedBox(height: 18), SingleChildScrollView(scrollDirection: Axis.horizontal, child: summary)]);
          },
        ),
      ),
    );
  }

  Widget _divider() => Container(width: 1, height: 36, margin: const EdgeInsets.symmetric(horizontal: 16), color: Colors.white.withValues(alpha: .12));
}

class _HeroValue extends StatelessWidget {
  const _HeroValue({required this.label, required this.value, this.success = false});
  final String label;
  final String value;
  final bool success;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: Color(0xFFB8D2CC), fontSize: 8.5)), const SizedBox(height: 4), Row(children: [if (success) ...[const Icon(Icons.check_circle_rounded, size: 13, color: Color(0xFF8DE0C2)), const SizedBox(width: 4)], Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900))])]);
}

class _KpiData {
  const _KpiData(this.label, this.value, this.meta, this.icon, this.color, this.target);
  final String label;
  final String value;
  final String meta;
  final IconData icon;
  final Color color;
  final String target;
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.data, required this.onTap});
  final _KpiData data;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SurfaceCard(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(15),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Container(width: 38, height: 38, decoration: BoxDecoration(color: data.color.withValues(alpha: .09), borderRadius: BorderRadius.circular(12)), child: Icon(data.icon, color: data.color, size: 18)), const Spacer(), const Icon(Icons.arrow_outward_rounded, size: 16, color: AppColors.muted)]),
            const Spacer(),
            Text(data.value, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: -.5)),
            const SizedBox(height: 2),
            Text(data.label, style: const TextStyle(fontSize: 9.3, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(data.meta, style: const TextStyle(fontSize: 8.1, color: AppColors.muted)),
          ]),
        ),
      );
}

class _FinancialSnapshotCard extends StatelessWidget {
  const _FinancialSnapshotCard({required this.s, required this.canSeeProfit, required this.onTap});
  final AppStrings s;
  final bool canSeeProfit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final store = AppDataStore.instance;
    final currency = store.settings.currency;
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final nextMonth = now.month == 12 ? DateTime(now.year + 1, 1, 1) : DateTime(now.year, now.month + 1, 1);
    final month = store.financialSummary(start: monthStart, end: nextMonth);
    return SurfaceCard(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: LayoutBuilder(builder: (context, c) {
          final compact = c.maxWidth < 760;
          final title = Row(children: [
            Container(width: 42, height: 42, decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.account_balance_wallet_outlined, color: AppColors.primary, size: 20)),
            const SizedBox(width: 11),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(s.text('الملخص المالي', 'Financial summary'), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900)), const SizedBox(height: 3), Text(s.text('صورة مباشرة لما لك وما عليك ونتيجة الربح والخسارة.', 'A live view of what is owed to you, what you owe, and profit or loss.'), style: const TextStyle(fontSize: 8.7, color: AppColors.muted))])),
            const Icon(Icons.arrow_outward_rounded, size: 18, color: AppColors.muted),
          ]);
          final stats = Wrap(spacing: 9, runSpacing: 9, children: [
            _FinanceMini(label: s.text('لنا عند العملاء', 'Receivables'), value: '${store.totalReceivables.toStringAsFixed(0)} $currency', color: AppColors.blue),
            _FinanceMini(label: s.text('علينا للموردين', 'Payables'), value: '${store.totalPayables.toStringAsFixed(0)} $currency', color: AppColors.accent),
            _FinanceMini(label: s.text('مصروفات الشهر', 'Month expenses'), value: '${month.expenses.toStringAsFixed(0)} $currency', color: AppColors.danger),
            if (canSeeProfit) _FinanceMini(label: month.netProfit >= 0 ? s.text('صافي ربح الشهر', 'Month net profit') : s.text('صافي خسارة الشهر', 'Month net loss'), value: '${month.netProfit.abs().toStringAsFixed(0)} $currency', color: month.netProfit >= 0 ? AppColors.success : AppColors.danger),
          ]);
          return compact ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [title, const SizedBox(height: 14), stats]) : Row(children: [Expanded(flex: 5, child: title), const SizedBox(width: 14), Expanded(flex: 6, child: Align(alignment: AlignmentDirectional.centerEnd, child: stats))]);
        }),
      ),
    );
  }
}

class _FinanceMini extends StatelessWidget {
  const _FinanceMini({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(width: 132, padding: const EdgeInsets.all(11), decoration: BoxDecoration(color: color.withValues(alpha: .07), borderRadius: BorderRadius.circular(12)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: color)), const SizedBox(height: 3), Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 7.8, color: AppColors.muted))]));
}

class _SalesPulse extends StatelessWidget {
  const _SalesPulse({required this.s, required this.onTap});
  final AppStrings s;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final store = AppDataStore.instance;
    final today = DateTime.now();
    final values = List<double>.generate(7, (index) {
      final day = DateTime(today.year, today.month, today.day).subtract(Duration(days: 6 - index));
      return store.invoices.where((i) => i.createdAt.year == day.year && i.createdAt.month == day.month && i.createdAt.day == day.day && !i.voided).fold<double>(0, (sum, i) => sum + i.total);
    });
    final max = values.fold<double>(1, (a, b) => b > a ? b : a);
    return SurfaceCard(
      child: InkWell(
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(s.text('نبض المبيعات', 'Sales pulse'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)), const SizedBox(height: 3), Text(s.text('آخر 7 أيام من الفواتير المسجلة', 'Last 7 days from recorded invoices'), style: const TextStyle(fontSize: 8.8, color: AppColors.muted))])), const Icon(Icons.arrow_outward_rounded, size: 17, color: AppColors.muted)]),
          const SizedBox(height: 20),
          SizedBox(
            height: 175,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (int i = 0; i < values.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                      Expanded(child: Align(alignment: Alignment.bottomCenter, child: FractionallySizedBox(heightFactor: values[i] == 0 ? .04 : (values[i] / max).clamp(.08, 1), child: Container(decoration: BoxDecoration(color: i == values.length - 1 ? AppColors.accent : AppColors.primary.withValues(alpha: .78), borderRadius: const BorderRadius.vertical(top: Radius.circular(7))))))),
                      const SizedBox(height: 7),
                      Text('${today.subtract(Duration(days: 6 - i)).day}', style: const TextStyle(fontSize: 7.7, color: AppColors.muted)),
                    ]),
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _StockHealth extends StatelessWidget {
  const _StockHealth({required this.s, required this.onTap});
  final AppStrings s;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final store = AppDataStore.instance;
    final low = store.lowStock;
    return SurfaceCard(
      child: InkWell(
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(s.text('صحة المخزون', 'Inventory health'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)), const SizedBox(height: 3), Text('${store.products.length} ${s.text('منتج نشط', 'active products')}', style: const TextStyle(fontSize: 8.8, color: AppColors.muted))])), Container(width: 42, height: 42, decoration: BoxDecoration(color: low.isEmpty ? AppColors.primarySoft : AppColors.accentSoft, borderRadius: BorderRadius.circular(13)), child: Icon(low.isEmpty ? Icons.check_circle_outline_rounded : Icons.warning_amber_rounded, color: low.isEmpty ? AppColors.success : AppColors.accent, size: 20))]),
          const SizedBox(height: 18),
          Row(children: [Expanded(child: _HealthNumber(label: s.text('قيمة المخزون', 'Inventory value'), value: '${store.inventoryValue.toStringAsFixed(0)} ${store.settings.currency}')), const SizedBox(width: 10), Expanded(child: _HealthNumber(label: s.text('منخفض', 'Low stock'), value: '${low.length}', danger: low.isNotEmpty))]),
          const SizedBox(height: 17),
          for (final product in low.take(4)) ...[
            Row(children: [Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle)), const SizedBox(width: 8), Expanded(child: Text(s.text(product.nameAr, product.nameEn), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700))), Text('${product.stock}', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: AppColors.danger))]),
            if (product != low.take(4).last) const Divider(height: 17),
          ],
        ]),
      ),
    );
  }
}

class _HealthNumber extends StatelessWidget {
  const _HealthNumber({required this.label, required this.value, this.danger = false});
  final String label;
  final String value;
  final bool danger;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(13)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontSize: 8.2, color: AppColors.muted)), const SizedBox(height: 4), Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: danger ? AppColors.danger : AppColors.text))]));
}

class _ActivityPanel extends StatelessWidget {
  const _ActivityPanel({required this.s, required this.onTap});
  final AppStrings s;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final store = AppDataStore.instance;
    final invoices = store.invoices.take(5).toList();
    return SurfaceCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text(s.text('آخر حركة بيع', 'Latest sales activity'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900))), TextButton(onPressed: onTap, child: Text(s.text('عرض الكل', 'View all'), style: const TextStyle(fontSize: 8.5)))]),
        const SizedBox(height: 8),
        for (final invoice in invoices) ...[
          InkWell(onTap: onTap, child: Row(children: [Container(width: 38, height: 38, decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.receipt_long_outlined, size: 18, color: AppColors.primary)), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(invoice.number, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900)), const SizedBox(height: 3), Text('${invoice.customer} • ${invoice.cashier}', style: const TextStyle(fontSize: 8.3, color: AppColors.muted))])), Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text('${invoice.total.toStringAsFixed(2)} ${store.settings.currency}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900)), Text(_time(invoice.createdAt), style: const TextStyle(fontSize: 8, color: AppColors.muted))]), const SizedBox(width: 4), const Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.muted)])),
          if (invoice != invoices.last) const Divider(height: 20),
        ],
      ]),
    );
  }
}

class _OperationsPanel extends StatelessWidget {
  const _OperationsPanel({required this.s, required this.onNavigate});
  final AppStrings s;
  final ValueChanged<String> onNavigate;
  @override
  Widget build(BuildContext context) {
    final store = AppDataStore.instance;
    return SurfaceCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.text('تشغيل اليوم', 'Today operations'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        _OperationRow(icon: Icons.pause_circle_outline_rounded, label: s.text('فواتير معلقة', 'Held sales'), value: '${store.heldSales.length}', tone: AppColors.accent, onTap: () => onNavigate('held')),
        const Divider(height: 18),
        _OperationRow(icon: Icons.task_alt_rounded, label: s.text('مهام قيد التنفيذ', 'Open tasks'), value: '${store.openTasks.length}', tone: AppColors.blue, onTap: () => onNavigate('tasks')),
        const Divider(height: 18),
        _OperationRow(icon: Icons.warning_amber_rounded, label: s.text('تنبيهات مخزون', 'Stock alerts'), value: '${store.lowStock.length}', tone: AppColors.danger, onTap: () => onNavigate('stockAlerts')),
        const Divider(height: 18),
        _OperationRow(icon: Icons.shopping_cart_checkout_outlined, label: s.text('طلبات توريد مفتوحة', 'Open restock requests'), value: '${store.openRestockRequests.length}', tone: AppColors.accent, onTap: () => onNavigate('restockRequests')),
        const Divider(height: 18),
        _OperationRow(icon: Icons.forum_outlined, label: s.text('الرسائل الداخلية', 'Internal messages'), value: '${store.messages.length}', tone: AppColors.blue, onTap: () => onNavigate('messages')),
        const Divider(height: 18),
        _OperationRow(icon: Icons.assignment_return_outlined, label: s.text('مرتجعات', 'Returns'), value: '${store.returns.length}', tone: AppColors.primary, onTap: () => onNavigate('returns')),
      ]),
    );
  }
}

class _OperationRow extends StatelessWidget {
  const _OperationRow({required this.icon, required this.label, required this.value, required this.tone, required this.onTap});
  final IconData icon;
  final String label;
  final String value;
  final Color tone;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(10), child: Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [Container(width: 34, height: 34, decoration: BoxDecoration(color: tone.withValues(alpha: .09), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: tone, size: 17)), const SizedBox(width: 9), Expanded(child: Text(label, style: const TextStyle(fontSize: 9.3, fontWeight: FontWeight.w700))), Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)), const SizedBox(width: 4), const Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.muted)])));
}

class _TeamSnapshot extends StatelessWidget {
  const _TeamSnapshot({required this.s, required this.onNavigate});
  final AppStrings s;
  final ValueChanged<String> onNavigate;
  @override
  Widget build(BuildContext context) {
    final store = AppDataStore.instance;
    final completed = store.tasks.where((t) => t.done).length;
    final overdue = store.overdueTasks.length;
    return SurfaceCard(
      child: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 780;
        final intro = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(s.text('الفريق والمهام', 'Team & tasks'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)), const SizedBox(height: 5), Text(s.text('ملخص مباشر من الحضور وحالات المهام.', 'Live summary from attendance and task status.'), style: const TextStyle(fontSize: 8.8, color: AppColors.muted))]);
        final stats = Wrap(spacing: 9, runSpacing: 9, children: [
          _MiniStat(label: s.text('داخل الدوام', 'On shift'), value: '${store.openAttendance.length}', color: AppColors.success, onTap: () => onNavigate('attendance')),
          _MiniStat(label: s.text('مكتملة', 'Completed'), value: '$completed', color: AppColors.primary, onTap: () => onNavigate('tasks')),
          _MiniStat(label: s.text('متأخرة', 'Overdue'), value: '$overdue', color: AppColors.danger, onTap: () => onNavigate('tasks')),
          _MiniStat(label: s.text('الموظفون', 'Employees'), value: '${store.activeEmployees.length}', color: AppColors.blue, onTap: () => onNavigate('employees')),
        ]);
        return wide ? Row(children: [Expanded(child: intro), stats]) : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [intro, const SizedBox(height: 14), stats]);
      }),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, required this.color, required this.onTap});
  final String label;
  final String value;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(13), child: Container(width: 115, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: color.withValues(alpha: .07), borderRadius: BorderRadius.circular(13)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color)), const SizedBox(height: 3), Text(label, style: const TextStyle(fontSize: 8.3, color: AppColors.muted))])));
}

String _time(DateTime date) => formatHour12(date);
