import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/app_theme.dart';
import '../../core/app_controller.dart';
import '../../core/app_strings.dart';
import '../../core/subscription/subscription_repository.dart';
import '../../core/widgets/app_logo.dart';
import '../../core/widgets/language_switch.dart';
import '../../core/widgets/logout_confirmation.dart';
import '../../data/app_data_store.dart';
import '../../data/models.dart';
import '../auth/access_screen.dart';
import '../pos/pos_screen.dart';
import 'owner_dashboard.dart';
import 'section_page.dart';

enum ManagementSection {
  overview,
  sales,
  products,
  inventory,
  purchases,
  customers,
  suppliers,
  employees,
  payroll,
  attendance,
  tasks,
  messages,
  restockRequests,
  financialSummary,
  accounting,
  assets,
  reports,
  offersPlans,
  subscription,
  settings,
  developer,
  heldSales,
  returns,
  stockAlerts,
  netSalesDetails,
  profitDetails,
  averageTicketDetails,
  invoiceDetails,
}

class ManagementShell extends StatefulWidget {
  const ManagementShell({super.key});

  @override
  State<ManagementShell> createState() => _ManagementShellState();
}

class _ManagementShellState extends State<ManagementShell> {
  ManagementSection selected = ManagementSection.overview;
  final SubscriptionRepository _subscriptionRepository = SubscriptionRepository();
  SubscriptionSnapshot? _remoteSubscription;
  Timer? _subscriptionStatusTimer;
  bool _expiryNoticeShown = false;

  @override
  void initState() {
    super.initState();
    _loadRemoteSubscription();
    _subscriptionStatusTimer = Timer.periodic(const Duration(minutes: 10), (_) => _loadRemoteSubscription());
  }

  @override
  void dispose() {
    _subscriptionStatusTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadRemoteSubscription() async {
    try {
      final code = await _subscriptionRepository.loadActivationCode();
      if (code.isEmpty) return;
      final snapshot = await _subscriptionRepository.fetch(code);
      if (!mounted) return;
      setState(() => _remoteSubscription = snapshot);
      _showExpiryNoticeIfNeeded(snapshot);
    } catch (_) {
      // StartupGate remains authoritative for blocking access; this fetch only
      // feeds the in-app expiry notification.
    }
  }

  void _showExpiryNoticeIfNeeded(SubscriptionSnapshot snapshot) {
    if (_expiryNoticeShown || (!snapshot.isNearExpiry && snapshot.status != 'grace')) return;
    _expiryNoticeShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final s = AppStrings(AppScope.of(context));
      final remaining = snapshot.remainingDuration;
      final days = remaining.inDays;
      final hours = remaining.inHours % 24;
      final minutes = remaining.inMinutes % 60;
      final text = snapshot.status == 'grace'
          ? s.text(
              'انتهت مدة الاشتراك الأساسية ودخلت فترة السماح. متبقي ${snapshot.graceDaysRemaining} يوم قبل الإيقاف الكامل.',
              'The base subscription period has ended and the grace period is active. ${snapshot.graceDaysRemaining} days remain before full suspension.',
            )
          : s.text(
              'تنبيه الاشتراك: متبقي فعليًا $days يوم و$hours ساعة و$minutes دقيقة. يبدأ التنبيه قبل ${snapshot.expiryWarningDays} يوم حسب إعداد الإدارة.',
              'Subscription notice: $days days, $hours hours and $minutes minutes actually remain. The warning starts ${snapshot.expiryWarningDays} days before expiry as configured by administration.',
            );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 10),
          content: Text(text),
          action: SnackBarAction(
            label: s.text('الاشتراك', 'Subscription'),
            onPressed: () {
              if (mounted) setState(() => selected = ManagementSection.subscription);
            },
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    if (!controller.canAccessManagement || controller.role == null) return const AccessScreen();
    final role = controller.role!;
    final allowed = _allowedSections(role);
    if (!allowed.contains(selected)) selected = ManagementSection.overview;
    final visibleNavigation = allowed.where((e) => !const {ManagementSection.heldSales, ManagementSection.returns, ManagementSection.stockAlerts, ManagementSection.netSalesDetails, ManagementSection.profitDetails, ManagementSection.averageTicketDetails, ManagementSection.invoiceDetails}.contains(e)).toList();

    return Scaffold(
      drawer: MediaQuery.sizeOf(context).width < AppBreakpoints.tablet
          ? Drawer(
              width: 286,
              child: SafeArea(
                child: _SideNavigation(
                  selected: selected,
                  sections: visibleNavigation,
                  onSelect: (value) {
                    setState(() => selected = value);
                    Navigator.of(context).pop();
                  },
                  onLogout: () => _logout(context),
                ),
              ),
            )
          : null,
      body: SafeArea(
        child: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= AppBreakpoints.tablet;
          return Row(
            children: [
              if (desktop)
                SizedBox(
                  width: constraints.maxWidth >= 1380 ? 268 : 236,
                  child: _SideNavigation(
                    selected: selected,
                    sections: visibleNavigation,
                    onSelect: (value) => setState(() => selected = value),
                    onLogout: () => _logout(context),
                  ),
                ),
              Expanded(
                child: Column(
                  children: [
                    _ManagementTopBar(
                      selected: selected,
                      desktop: desktop,
                      onBack: selected == ManagementSection.overview ? null : () => setState(() => selected = ManagementSection.overview),
                      onOpenPos: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PosScreen(managementMode: true))),
                      onSearch: (query) => _showGlobalSearch(context, query),
                      onNotifications: () => _showNotifications(context),
                      onToggleAttendance: () => _toggleManagementAttendance(context),
                      subscriptionSnapshot: _remoteSubscription,
                    ),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: SlideTransition(position: Tween<Offset>(begin: const Offset(.015, 0), end: Offset.zero).animate(animation), child: child)),
                        child: selected == ManagementSection.overview
                            ? OwnerDashboard(key: const ValueKey('overview'), role: role, onNavigate: (target) => setState(() => selected = _sectionForTarget(target)))
                            : SectionPage(key: ValueKey(selected.name), section: selected, onBack: () => setState(() => selected = ManagementSection.overview)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
        ),
      ),
    );
  }

  List<ManagementSection> _allowedSections(UserRole role) {
    switch (role) {
      case UserRole.owner:
        return ManagementSection.values;
      case UserRole.manager:
        return const [
          ManagementSection.overview,
          ManagementSection.sales,
          ManagementSection.products,
          ManagementSection.inventory,
          ManagementSection.purchases,
          ManagementSection.customers,
          ManagementSection.suppliers,
          ManagementSection.employees,
          ManagementSection.payroll,
          ManagementSection.attendance,
          ManagementSection.tasks,
          ManagementSection.messages,
          ManagementSection.restockRequests,
          ManagementSection.financialSummary,
          ManagementSection.reports,
          ManagementSection.offersPlans,
          ManagementSection.subscription,
          ManagementSection.settings,
          ManagementSection.developer,
          ManagementSection.heldSales,
          ManagementSection.returns,
          ManagementSection.stockAlerts,
          ManagementSection.netSalesDetails,
          ManagementSection.profitDetails,
          ManagementSection.averageTicketDetails,
          ManagementSection.invoiceDetails,
        ];
      case UserRole.accountant:
        return const [
          ManagementSection.overview,
          ManagementSection.sales,
          ManagementSection.purchases,
          ManagementSection.suppliers,
          ManagementSection.financialSummary,
          ManagementSection.accounting,
          ManagementSection.assets,
          ManagementSection.payroll,
          ManagementSection.attendance,
          ManagementSection.reports,
          ManagementSection.offersPlans,
          ManagementSection.subscription,
          ManagementSection.developer,
          ManagementSection.returns,
          ManagementSection.netSalesDetails,
          ManagementSection.profitDetails,
          ManagementSection.averageTicketDetails,
          ManagementSection.invoiceDetails,
        ];
      default:
        return const [ManagementSection.overview];
    }
  }


  ManagementSection _sectionForTarget(String target) => switch (target) {
        'sales' => ManagementSection.sales,
        'netSalesDetails' => ManagementSection.netSalesDetails,
        'invoiceDetails' => ManagementSection.invoiceDetails,
        'averageTicketDetails' => ManagementSection.averageTicketDetails,
        'profitDetails' => ManagementSection.profitDetails,
        'products' => ManagementSection.products,
        'inventory' => ManagementSection.inventory,
        'purchases' => ManagementSection.purchases,
        'customers' => ManagementSection.customers,
        'employees' => ManagementSection.employees,
        'payroll' => ManagementSection.payroll,
        'attendance' => ManagementSection.attendance,
        'tasks' => ManagementSection.tasks,
        'messages' => ManagementSection.messages,
        'restockRequests' => ManagementSection.restockRequests,
        'financial' => ManagementSection.financialSummary,
        'reports' => ManagementSection.reports,
        'held' => ManagementSection.heldSales,
        'returns' => ManagementSection.returns,
        'stockAlerts' => ManagementSection.stockAlerts,
        _ => ManagementSection.overview,
      };

  Future<void> _logout(BuildContext context) async {
    final controller = AppScope.of(context);
    final s = AppStrings(controller);
    if (!await confirmSignOut(context, s) || !context.mounted) return;
    controller.signOut();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }


  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _toggleManagementAttendance(BuildContext context) {
    final controller = AppScope.of(context);
    if (controller.role != UserRole.manager && controller.role != UserRole.accountant) return;
    final s = AppStrings(controller);
    final store = AppDataStore.instance;
    final id = 'ADMIN-${controller.role!.name}';
    final open = store.currentAttendance(id);
    if (open == null) {
      store.clockIn(id, controller.currentUserName.isEmpty ? controller.role!.name : controller.currentUserName);
      _toast(s.text('تم تسجيل الحضور الإداري.', 'Management clock-in recorded.'));
    } else {
      store.clockOut(id);
      _toast(s.text('تم تسجيل الانصراف الإداري.', 'Management clock-out recorded.'));
    }
  }

  Future<void> _showGlobalSearch(BuildContext context, String initial) async {
    final controller = AppScope.of(context);
    final allowed = controller.role == null ? <ManagementSection>{ManagementSection.overview} : _allowedSections(controller.role!).toSet();
    await showDialog<void>(
      context: context,
      builder: (_) => _GlobalSearchDialog(
        initialQuery: initial,
        allowedSections: allowed,
        onNavigate: (section) {
          Navigator.pop(context);
          setState(() => selected = section);
        },
      ),
    );
  }

  Future<void> _showNotifications(BuildContext context) async {
    final s = AppStrings(AppScope.of(context));
    final store = AppDataStore.instance;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Directionality(
        textDirection: s.controller.isArabic ? TextDirection.rtl : TextDirection.ltr,
        child: Container(
          height: MediaQuery.sizeOf(context).height * .72,
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(18),
                child: Row(children: [Text(s.text('مركز الإشعارات', 'Notification center'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)), const Spacer(), IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded))]),
              ),
              const Divider(height: 1),
              Expanded(
                child: AnimatedBuilder(
                  animation: store,
                  builder: (context, _) {
                    final role = s.controller.role;
                    final roleKey = role?.name ?? 'manager';
                    final readerId = 'ADMIN-$roleKey';
                    final items = <_NotificationData>[
                      ..._buildNotificationItems(s, store, roleKey, readerId),
                      if (_subscriptionNotification(s, _remoteSubscription) case final item?) item,
                    ]
                        .where((item) => role == null || _notificationSectionAllowed(role, item.section))
                        .where((item) => store.isNotificationUnread(readerId, item.key))
                        .toList();
                    if (items.isEmpty) return Center(child: Text(s.text('لا توجد إشعارات تحتاج انتباهك.', 'No notifications need your attention.'), style: const TextStyle(fontSize: 10, color: AppColors.muted)));
                    return ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 9),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return ListTile(
                          tileColor: AppColors.surfaceAlt,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppColors.border)),
                          leading: Container(width: 42, height: 42, decoration: BoxDecoration(color: item.color.withValues(alpha: .09), borderRadius: BorderRadius.circular(13)), child: Icon(item.icon, color: item.color)),
                          title: Text(item.title, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900)),
                          subtitle: Text(item.subtitle, style: const TextStyle(fontSize: 8.7, color: AppColors.muted)),
                          trailing: PopupMenuButton<String>(
                            tooltip: s.text('خيارات', 'Options'),
                            onSelected: (value) {
                              if (value == 'delete') store.hideNotification(readerId, item.key);
                            },
                            itemBuilder: (_) => [PopupMenuItem(value: 'delete', child: Row(children: [const Icon(Icons.delete_outline_rounded, size: 17), const SizedBox(width: 8), Text(s.text('حذف الإشعار', 'Delete notification'))]))],
                          ),
                          onTap: () {
                            store.markNotificationRead(readerId, item.key);
                            Navigator.pop(context);
                            setState(() => selected = item.section);
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

class _ManagementTopBar extends StatelessWidget {
  const _ManagementTopBar({required this.selected, required this.desktop, required this.onBack, required this.onOpenPos, required this.onSearch, required this.onNotifications, required this.onToggleAttendance, required this.subscriptionSnapshot});
  final ManagementSection selected;
  final bool desktop;
  final VoidCallback? onBack;
  final VoidCallback onOpenPos;
  final ValueChanged<String> onSearch;
  final VoidCallback onNotifications;
  final VoidCallback onToggleAttendance;
  final SubscriptionSnapshot? subscriptionSnapshot;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final s = AppStrings(controller);
    final search = TextEditingController();
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Row(children: [
        if (!desktop) Builder(builder: (context) => IconButton(tooltip: s.text('القائمة', 'Menu'), onPressed: () => Scaffold.of(context).openDrawer(), icon: const Icon(Icons.menu_rounded))),
        if (onBack != null) ...[IconButton(tooltip: s.text('رجوع', 'Back'), onPressed: onBack, icon: Icon(controller.isArabic ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded)), const SizedBox(width: 4)],
        if (!desktop && onBack == null) const AppLogo(compact: true),
        if (!desktop) const SizedBox(width: 10),
        Text(_sectionLabel(s, selected), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
        const Spacer(),
        if (MediaQuery.sizeOf(context).width > 760) ...[
          SizedBox(
            width: 240,
            child: TextField(
              controller: search,
              onSubmitted: onSearch,
              decoration: InputDecoration(hintText: s.text('فاتورة، عميل، موظف، مهمة...', 'Invoice, customer, employee, task...'), prefixIcon: const Icon(Icons.search_rounded, size: 18), suffixIcon: IconButton(onPressed: () => onSearch(search.text), icon: const Icon(Icons.arrow_forward_rounded, size: 17)), isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 11)),
            ),
          ),
          const SizedBox(width: 9),
        ] else ...[
          IconButton.outlined(
            tooltip: s.text('البحث الشامل', 'Global search'),
            onPressed: () => onSearch(''),
            icon: const Icon(Icons.search_rounded, size: 19),
          ),
          const SizedBox(width: 8),
        ],
        if (controller.role == UserRole.manager || controller.role == UserRole.accountant) ...[
          AnimatedBuilder(
            animation: AppDataStore.instance,
            builder: (_, __) {
              final id = 'ADMIN-${controller.role!.name}';
              final inside = AppDataStore.instance.currentAttendance(id) != null;
              return IconButton.outlined(
                tooltip: inside ? s.text('تسجيل انصراف', 'Clock out') : s.text('تسجيل حضور', 'Clock in'),
                onPressed: onToggleAttendance,
                icon: Icon(inside ? Icons.logout_rounded : Icons.how_to_reg_rounded, size: 19, color: inside ? AppColors.danger : AppColors.success),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
        AnimatedBuilder(
          animation: AppDataStore.instance,
          builder: (_, __) {
            final store = AppDataStore.instance;
            final roleKey = controller.role?.name ?? 'manager';
            final readerId = 'ADMIN-$roleKey';
            final count = <_NotificationData>[
              ..._buildNotificationItems(s, store, roleKey, readerId),
              if (_subscriptionNotification(s, subscriptionSnapshot) case final item?) item,
            ]
                .where((item) => controller.role == null || _notificationSectionAllowed(controller.role!, item.section))
                .where((item) => store.isNotificationUnread(readerId, item.key))
                .length;
            return IconButton.outlined(tooltip: s.text('الإشعارات', 'Notifications'), onPressed: onNotifications, icon: Badge(isLabelVisible: count > 0, label: Text('$count'), child: const Icon(Icons.notifications_none_rounded, size: 19)));
          },
        ),
        const SizedBox(width: 8),
        if (MediaQuery.sizeOf(context).width > 580) ...[OutlinedButton.icon(onPressed: onOpenPos, icon: const Icon(Icons.point_of_sale_rounded, size: 17), label: Text(s.text('فتح الكاشير', 'Open POS'), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700))), const SizedBox(width: 8)],
        const LanguageSwitch(compact: true),
      ]),
    );
  }
}

class _GlobalSearchDialog extends StatefulWidget {
  const _GlobalSearchDialog({required this.initialQuery, required this.allowedSections, required this.onNavigate});
  final String initialQuery;
  final Set<ManagementSection> allowedSections;
  final ValueChanged<ManagementSection> onNavigate;
  @override
  State<_GlobalSearchDialog> createState() => _GlobalSearchDialogState();
}

class _GlobalSearchDialogState extends State<_GlobalSearchDialog> {
  late final TextEditingController query;
  @override
  void initState() {
    super.initState();
    query = TextEditingController(text: widget.initialQuery);
  }
  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  ManagementSection _sectionForKind(String kind) => switch (kind) {
        'invoice' => ManagementSection.sales,
        'customer' => ManagementSection.customers,
        'employee' => ManagementSection.employees,
        'task' => ManagementSection.tasks,
        'attendance' => ManagementSection.attendance,
        'product' => ManagementSection.products,
        'supplier' => ManagementSection.suppliers,
        'purchase' => ManagementSection.purchases,
        'return' => ManagementSection.returns,
        'stock_movement' => ManagementSection.inventory,
        'message' => ManagementSection.messages,
        'restock' => ManagementSection.restockRequests,
        'held_sale' => ManagementSection.heldSales,
        'customer_payment' => ManagementSection.customers,
        'supplier_payment' => ManagementSection.suppliers,
        'expense' => ManagementSection.financialSummary,
        'product_note' => ManagementSection.products,
        _ => ManagementSection.overview,
      };

  IconData _iconForKind(String kind) => switch (kind) {
        'invoice' => Icons.receipt_long_outlined,
        'customer' => Icons.person_outline_rounded,
        'employee' => Icons.badge_outlined,
        'task' => Icons.task_alt_rounded,
        'attendance' => Icons.how_to_reg_rounded,
        'product' => Icons.inventory_2_outlined,
        'supplier' => Icons.local_shipping_outlined,
        'purchase' => Icons.shopping_cart_outlined,
        'return' => Icons.assignment_return_outlined,
        'stock_movement' => Icons.swap_vert_rounded,
        'message' => Icons.forum_outlined,
        'restock' => Icons.shopping_cart_checkout_outlined,
        'held_sale' => Icons.pause_circle_outline_rounded,
        'customer_payment' => Icons.payments_outlined,
        'supplier_payment' => Icons.price_check_outlined,
        'expense' => Icons.receipt_outlined,
        'product_note' => Icons.sticky_note_2_outlined,
        _ => Icons.search_rounded,
      };

  String _kindLabel(AppStrings s, String kind) => switch (kind) {
        'invoice' => s.text('فاتورة', 'Invoice'),
        'customer' => s.text('عميل', 'Customer'),
        'employee' => s.text('موظف', 'Employee'),
        'task' => s.text('مهمة', 'Task'),
        'attendance' => s.text('حضور / انصراف', 'Attendance'),
        'product' => s.text('منتج', 'Product'),
        'supplier' => s.text('مورد', 'Supplier'),
        'purchase' => s.text('شراء / استلام', 'Purchase / receiving'),
        'return' => s.text('مرتجع', 'Return'),
        'stock_movement' => s.text('حركة مخزون', 'Stock movement'),
        'message' => s.text('رسالة', 'Message'),
        'restock' => s.text('طلب توريد', 'Restock request'),
        'held_sale' => s.text('فاتورة معلقة', 'Held sale'),
        'customer_payment' => s.text('دفعة عميل', 'Customer payment'),
        'supplier_payment' => s.text('دفعة مورد', 'Supplier payment'),
        'expense' => s.text('مصروف', 'Expense'),
        'product_note' => s.text('ملاحظة منتج', 'Product note'),
        _ => s.text('نتيجة', 'Result'),
      };

  @override
  Widget build(BuildContext context) {
    final s = AppStrings(AppScope.of(context));
    final store = AppDataStore.instance;
    final q = query.text.trim();
    final results = q.isEmpty
        ? const <GlobalSearchHit>[]
        : store.searchAll(q).where((hit) => widget.allowedSections.contains(_sectionForKind(hit.kind))).take(60).toList();
    return AlertDialog(
          scrollable: true,
      title: Text(s.text('البحث الشامل', 'Global search')),
      content: SizedBox(
        width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 700.0).toDouble(),
        height: 540,
        child: Column(children: [
          TextField(
            controller: query,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: s.text('فاتورة، عميل، صنف، باركود، موظف، مورد، شراء، حركة مخزون، مهمة...', 'Invoice, customer, product, barcode, employee, supplier, purchase, stock movement, task...'),
              suffixIcon: query.text.isEmpty ? null : IconButton(onPressed: () { query.clear(); setState(() {}); }, icon: const Icon(Icons.close_rounded, size: 18)),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              q.isEmpty ? s.text('ابحث في كل البيانات التي تسمح بها صلاحيات حسابك.', 'Search across all data allowed by your role.') : '${s.text('النتائج', 'Results')}: ${results.length}',
              style: const TextStyle(fontSize: 8.8, color: AppColors.muted, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: q.isEmpty
                ? Center(child: Text(s.text('ابدأ بالكتابة لعرض النتائج.', 'Start typing to see results.'), style: const TextStyle(fontSize: 10, color: AppColors.muted)))
                : results.isEmpty
                    ? Center(child: Text(s.text('لا توجد نتائج مطابقة ضمن صلاحياتك.', 'No matching results within your permissions.'), style: const TextStyle(fontSize: 10, color: AppColors.muted)))
                    : ListView.separated(
                        itemCount: results.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, index) {
                          final hit = results[index];
                          final section = _sectionForKind(hit.kind);
                          return ListTile(
                            onTap: () => widget.onNavigate(section),
                            leading: Container(width: 38, height: 38, decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(11)), child: Icon(_iconForKind(hit.kind), color: AppColors.primary, size: 18)),
                            title: Text(hit.title, style: const TextStyle(fontSize: 10.2, fontWeight: FontWeight.w900)),
                            subtitle: Text('${_kindLabel(s, hit.kind)} • ${hit.subtitle}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 8.5, color: AppColors.muted)),
                            trailing: const Icon(Icons.arrow_outward_rounded, size: 16),
                          );
                        },
                      ),
          ),
        ]),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: Text(s.text('إغلاق', 'Close')))],
    );
  }
}

class _SideNavigation extends StatelessWidget {
  const _SideNavigation({required this.selected, required this.sections, required this.onSelect, required this.onLogout});
  final ManagementSection selected;
  final List<ManagementSection> sections;
  final ValueChanged<ManagementSection> onSelect;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final s = AppStrings(controller);
    final role = controller.role ?? UserRole.owner;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
      child: Column(children: [
        const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Align(alignment: AlignmentDirectional.centerStart, child: AppLogo())),
        const SizedBox(height: 26),
        Expanded(
          child: ListView(children: [
            Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), child: Text(s.text('مساحة الإدارة', 'MANAGEMENT'), style: const TextStyle(color: AppColors.muted, fontSize: 8.5, fontWeight: FontWeight.w800, letterSpacing: 1.2))),
            ...sections.map((section) => _NavItem(icon: _sectionIcon(section), label: _sectionLabel(s, section), selected: selected == section, onTap: () => onSelect(section))),
          ]),
        ),
        const Divider(height: 20),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(15)),
          child: Row(children: [
            Container(width: 38, height: 38, decoration: const BoxDecoration(color: AppColors.primarySoft, shape: BoxShape.circle), alignment: Alignment.center, child: const Text('T', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w900))),
            const SizedBox(width: 9),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(controller.currentUserName.isEmpty ? s.role(role) : controller.currentUserName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9.8, fontWeight: FontWeight.w800)), Text('${s.role(role)} • ${AppDataStore.instance.settings.branchName}', style: const TextStyle(fontSize: 8.2, color: AppColors.muted))])),
            IconButton(tooltip: s.text('تسجيل الخروج', 'Sign out'), onPressed: onLogout, icon: const Icon(Icons.logout_rounded, size: 17, color: AppColors.muted)),
          ]),
        ),
      ]),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.selected, required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
            decoration: BoxDecoration(color: selected ? AppColors.primarySoft : Colors.transparent, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [Icon(icon, size: 18, color: selected ? AppColors.primary : AppColors.muted), const SizedBox(width: 11), Expanded(child: Text(label, style: TextStyle(color: selected ? AppColors.primary : const Color(0xFF52605C), fontSize: 10.8, fontWeight: selected ? FontWeight.w800 : FontWeight.w600))), if (selected) Container(width: 5, height: 5, decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle))]),
          ),
        ),
      );
}

String _sectionLabel(AppStrings s, ManagementSection section) => switch (section) {
      ManagementSection.overview => s.text('نظرة عامة', 'Overview'),
      ManagementSection.sales => s.text('المبيعات', 'Sales'),
      ManagementSection.products => s.text('المنتجات', 'Products'),
      ManagementSection.inventory => s.text('المخزون', 'Inventory'),
      ManagementSection.purchases => s.text('المشتريات', 'Purchases'),
      ManagementSection.customers => s.text('العملاء', 'Customers'),
      ManagementSection.suppliers => s.text('الموردون', 'Suppliers'),
      ManagementSection.employees => s.text('الموظفون', 'Employees'),
      ManagementSection.payroll => s.text('الرواتب', 'Payroll'),
      ManagementSection.attendance => s.text('الحضور والدوام', 'Attendance'),
      ManagementSection.tasks => s.text('المهام', 'Tasks'),
      ManagementSection.messages => s.text('الرسائل', 'Messages'),
      ManagementSection.restockRequests => s.text('طلبات التوريد', 'Restock requests'),
      ManagementSection.financialSummary => s.text('الملخص المالي', 'Financial summary'),
      ManagementSection.accounting => s.text('المحاسبة', 'Accounting'),
      ManagementSection.assets => s.text('الأصول', 'Assets'),
      ManagementSection.reports => s.text('التقارير', 'Reports'),
      ManagementSection.offersPlans => s.text('العروض والباقات', 'Offers & plans'),
      ManagementSection.subscription => s.text('الاشتراك والباقة', 'Subscription & plan'),
      ManagementSection.settings => s.text('الإعدادات', 'Settings'),
      ManagementSection.developer => s.text('مطور النظام', 'System developer'),
      ManagementSection.heldSales => s.text('الفواتير المعلقة', 'Held sales'),
      ManagementSection.returns => s.text('المرتجعات', 'Returns'),
      ManagementSection.stockAlerts => s.text('تنبيهات المخزون', 'Stock alerts'),
      ManagementSection.netSalesDetails => s.text('تفاصيل صافي المبيعات', 'Net sales details'),
      ManagementSection.profitDetails => s.text('تحليل الربح', 'Profit analysis'),
      ManagementSection.averageTicketDetails => s.text('تحليل متوسط السلة', 'Average ticket analysis'),
      ManagementSection.invoiceDetails => s.text('سجل الفواتير', 'Invoice register'),
    };

IconData _sectionIcon(ManagementSection section) => switch (section) {
      ManagementSection.overview => Icons.space_dashboard_outlined,
      ManagementSection.sales => Icons.receipt_long_outlined,
      ManagementSection.products => Icons.inventory_2_outlined,
      ManagementSection.inventory => Icons.warehouse_outlined,
      ManagementSection.purchases => Icons.shopping_cart_outlined,
      ManagementSection.customers => Icons.people_alt_outlined,
      ManagementSection.suppliers => Icons.local_shipping_outlined,
      ManagementSection.employees => Icons.badge_outlined,
      ManagementSection.payroll => Icons.payments_outlined,
      ManagementSection.attendance => Icons.schedule_outlined,
      ManagementSection.tasks => Icons.task_alt_outlined,
      ManagementSection.messages => Icons.forum_outlined,
      ManagementSection.restockRequests => Icons.shopping_cart_checkout_outlined,
      ManagementSection.financialSummary => Icons.account_balance_wallet_outlined,
      ManagementSection.accounting => Icons.account_balance_wallet_outlined,
      ManagementSection.assets => Icons.domain_outlined,
      ManagementSection.reports => Icons.analytics_outlined,
      ManagementSection.offersPlans => Icons.local_offer_outlined,
      ManagementSection.subscription => Icons.workspace_premium_outlined,
      ManagementSection.settings => Icons.settings_outlined,
      ManagementSection.developer => Icons.code_rounded,
      ManagementSection.heldSales => Icons.pause_circle_outline_rounded,
      ManagementSection.returns => Icons.assignment_return_outlined,
      ManagementSection.stockAlerts => Icons.warning_amber_rounded,
      ManagementSection.netSalesDetails => Icons.trending_up_rounded,
      ManagementSection.profitDetails => Icons.insights_outlined,
      ManagementSection.averageTicketDetails => Icons.shopping_bag_outlined,
      ManagementSection.invoiceDetails => Icons.receipt_long_outlined,
    };

class _NotificationData {
  const _NotificationData(this.key, this.icon, this.color, this.title, this.subtitle, this.section);
  final String key;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final ManagementSection section;
}


bool _notificationSectionAllowed(UserRole role, ManagementSection section) {
  switch (role) {
    case UserRole.owner:
      return true;
    case UserRole.manager:
      return !const <ManagementSection>{
        ManagementSection.accounting,
        ManagementSection.assets,
      }.contains(section);
    case UserRole.accountant:
      return const <ManagementSection>{
        ManagementSection.overview,
        ManagementSection.sales,
        ManagementSection.purchases,
        ManagementSection.suppliers,
        ManagementSection.financialSummary,
        ManagementSection.accounting,
        ManagementSection.assets,
        ManagementSection.reports,
        ManagementSection.subscription,
        ManagementSection.returns,
        ManagementSection.netSalesDetails,
        ManagementSection.profitDetails,
        ManagementSection.averageTicketDetails,
        ManagementSection.invoiceDetails,
      }.contains(section);
    default:
      return section == ManagementSection.overview;
  }
}

_NotificationData? _subscriptionNotification(AppStrings s, SubscriptionSnapshot? snapshot) {
  if (snapshot == null) return null;
  final remaining = snapshot.remainingDuration;
  if (snapshot.status == 'grace') {
    return _NotificationData(
      'subscription-grace:${snapshot.subscriptionId}:${snapshot.endsAt.toIso8601String()}',
      Icons.warning_amber_rounded,
      AppColors.warning,
      s.text('انتهت مدة الاشتراك الأساسية', 'Base subscription period ended'),
      s.text('فترة السماح فعالة. متبقي ${snapshot.graceDaysRemaining} يوم قبل الإيقاف الكامل.', 'Grace period is active. ${snapshot.graceDaysRemaining} days remain before full suspension.'),
      ManagementSection.subscription,
    );
  }
  if (snapshot.status == 'expired') {
    return _NotificationData(
      'subscription-expired:${snapshot.subscriptionId}:${snapshot.endsAt.toIso8601String()}',
      Icons.event_busy_rounded,
      AppColors.danger,
      s.text('انتهى اشتراك THAMAN', 'THAMAN subscription expired'),
      s.text('افتح صفحة الاشتراك لطلب التجديد.', 'Open the subscription page to request renewal.'),
      ManagementSection.subscription,
    );
  }
  if (!snapshot.isNearExpiry) return null;
  final days = remaining.inDays;
  final hours = remaining.inHours % 24;
  final minutes = remaining.inMinutes % 60;
  final remainingText = days > 0
      ? s.text('$days يوم و$hours ساعة', '$days days and $hours hours')
      : hours > 0
          ? s.text('$hours ساعة و$minutes دقيقة', '$hours hours and $minutes minutes')
          : s.text('$minutes دقيقة', '$minutes minutes');
  return _NotificationData(
    'subscription-expiry:${snapshot.subscriptionId}:${snapshot.endsAt.toIso8601String()}:${snapshot.expiryWarningDays}',
    Icons.notifications_active_outlined,
    AppColors.warning,
    s.text('اشتراكك يقترب من الانتهاء', 'Your subscription is nearing expiry'),
    s.text('المدة الفعلية المتبقية: $remainingText', 'Actual time remaining: $remainingText'),
    ManagementSection.subscription,
  );
}

List<_NotificationData> _buildNotificationItems(AppStrings s, AppDataStore store, String roleKey, String readerId) {
  final since = DateTime.now().subtract(const Duration(hours: 24));
  final completedTasks = store.tasks.where((task) => task.completedAt != null && task.completedAt!.isAfter(since)).toList();
  final attendanceUpdates = store.attendance.where((record) => record.clockIn.isAfter(since) || (record.clockOut?.isAfter(since) ?? false)).toList();
  final overdue = store.overdueTasks;
  final low = store.lowStock;
  final restock = store.openRestockRequests;
  final held = store.heldSales;
  final returns = store.returns;
  final unreadMessages = store.messagesForManagement(roleKey, readerId: readerId)
      .where((m) => !m.readBy.contains(readerId) && m.senderId != readerId)
      .toList();

  String joined(Iterable<String> values) {
    final rows = values.toList()..sort();
    return rows.join('|');
  }

  return <_NotificationData>[
    if (completedTasks.isNotEmpty)
      _NotificationData(
        'completed:${joined(completedTasks.map((e) => '${e.id}:${e.completedAt?.millisecondsSinceEpoch ?? 0}'))}',
        Icons.task_alt_rounded,
        AppColors.success,
        s.text('${completedTasks.length} مهام أُنجزت خلال 24 ساعة', '${completedTasks.length} tasks completed in 24h'),
        s.text('حالة المهمة واسم الموظف ووقت الإنجاز متاحة مباشرة في صفحة المهام.', 'Task status, employee and completion time are available in the tasks page.'),
        ManagementSection.tasks,
      ),
    if (attendanceUpdates.isNotEmpty)
      _NotificationData(
        'attendance:${joined(attendanceUpdates.map((e) => '${e.id}:${e.clockIn.millisecondsSinceEpoch}:${e.clockOut?.millisecondsSinceEpoch ?? 0}'))}',
        Icons.how_to_reg_rounded,
        AppColors.blue,
        s.text('${attendanceUpdates.length} تحديثات حضور وانصراف', '${attendanceUpdates.length} attendance updates'),
        s.text('تسجيلات الموظفين تنعكس مباشرة في سجل الحضور لدى الإدارة.', 'Employee clock-in/out records are reflected directly in management attendance.'),
        ManagementSection.attendance,
      ),
    if (overdue.isNotEmpty)
      _NotificationData(
        'overdue:${joined(overdue.map((e) => '${e.id}:${e.status}:${e.dueAt.millisecondsSinceEpoch}'))}',
        Icons.task_alt_rounded,
        AppColors.danger,
        s.text('${overdue.length} مهام متأخرة', '${overdue.length} overdue tasks'),
        s.text('افتح المهام لمراجعة الموظفين ومواعيد الاستحقاق وإرسال تنبيه مباشر للمكلّف.', 'Open tasks to review assignees, due dates and send a direct reminder.'),
        ManagementSection.tasks,
      ),
    if (low.isNotEmpty)
      _NotificationData(
        'low:${joined(low.map((e) => '${e.id}:${e.stock}:${e.minStock}'))}',
        Icons.warning_amber_rounded,
        AppColors.accent,
        s.text('${low.length} تنبيهات مخزون', '${low.length} stock alerts'),
        s.text('هناك أصناف وصلت إلى حد إعادة الطلب.', 'Items have reached their reorder threshold.'),
        ManagementSection.stockAlerts,
      ),
    if (restock.isNotEmpty)
      _NotificationData(
        'restock:${joined(restock.map((e) => '${e.id}:${e.status}'))}',
        Icons.shopping_cart_checkout_outlined,
        AppColors.primary,
        s.text('${restock.length} طلبات توريد مفتوحة', '${restock.length} open restock requests'),
        s.text('طلبات النقص مرتبطة بالأصناف ويمكن متابعتها حتى الاستلام.', 'Low-stock requests can be tracked through receiving.'),
        ManagementSection.restockRequests,
      ),
    if (unreadMessages.isNotEmpty)
      _NotificationData(
        'messages:${joined(unreadMessages.map((e) => e.id))}',
        Icons.forum_outlined,
        AppColors.blue,
        s.text('${unreadMessages.length} رسائل داخلية غير مقروءة', '${unreadMessages.length} unread internal messages'),
        s.text('راجع رسائل الموظفين وردود مسؤول المخزون.', 'Review staff messages and inventory replies.'),
        ManagementSection.messages,
      ),
    if (held.isNotEmpty)
      _NotificationData(
        'held:${joined(held.map((e) => e.id))}',
        Icons.pause_circle_outline_rounded,
        AppColors.blue,
        s.text('${held.length} فواتير معلقة', '${held.length} held sales'),
        s.text('راجع الفواتير المعلقة والكاشير ووقت التعليق.', 'Review held sales, cashier and hold time.'),
        ManagementSection.heldSales,
      ),
    if (returns.isNotEmpty)
      _NotificationData(
        'returns:${joined(returns.map((e) => e.id))}',
        Icons.assignment_return_outlined,
        AppColors.primary,
        s.text('${returns.length} مرتجعات مسجلة', '${returns.length} returns recorded'),
        s.text('سجل المرتجعات مرتبط بالفواتير الأصلية.', 'Returns are linked to original invoices.'),
        ManagementSection.returns,
      ),
  ];
}

