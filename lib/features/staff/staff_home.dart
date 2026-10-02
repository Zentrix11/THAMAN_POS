import 'package:flutter/material.dart';
import '../../core/time_format.dart';
import '../../app/app_theme.dart';
import '../../core/app_controller.dart';
import '../../core/app_strings.dart';
import '../../core/printing/print_service.dart';
import '../../core/printing/print_templates.dart';
import '../../core/widgets/app_logo.dart';
import '../../core/widgets/brand_pattern.dart';
import '../../core/widgets/language_switch.dart';
import '../../core/widgets/logout_confirmation.dart';
import '../../core/widgets/surface_card.dart';
import '../../data/app_data_store.dart';
import '../../data/models.dart';
import '../inventory/inventory_batch_dialog.dart';
import '../inventory/barcode_station_screen.dart';
import '../inventory/stock_count_start_dialog.dart';
import 'stock_count_screen.dart';

class StaffHome extends StatelessWidget {
  const StaffHome({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final s = AppStrings(controller);
    final inventory = controller.role == UserRole.inventory;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          tooltip: s.text('تسجيل الخروج', 'Sign out'),
          onPressed: () => _logout(context),
          icon: Icon(controller.isArabic ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded),
        ),
        title: const AppLogo(compact: true),
        actions: const [LanguageSwitch(compact: true), SizedBox(width: 14)],
      ),
      body: BrandPattern(
        borderRadius: BorderRadius.zero,
        child: AnimatedBuilder(
          animation: AppDataStore.instance,
          builder: (context, _) => SingleChildScrollView(
            padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 700 ? 16 : 26),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: inventory ? _InventoryWorkspace(s: s) : _EmployeeWorkspace(s: s),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    final controller = AppScope.of(context);
    final s = AppStrings(controller);
    if (!await confirmSignOut(context, s) || !context.mounted) return;
    controller.signOut();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}

class _InventoryWorkspace extends StatelessWidget {
  const _InventoryWorkspace({required this.s});
  final AppStrings s;

  @override
  Widget build(BuildContext context) {
    final store = AppDataStore.instance;
    final controller = s.controller;
    final id = controller.employeeId;
    if (id == null || id.trim().isEmpty) {
      return Center(
        child: Text(
          s.text('انتهت جلسة الموظف. سجّل الدخول من جديد.', 'Employee session expired. Please sign in again.'),
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.danger),
        ),
      );
    }
    final myTasks = store.tasks.where((task) => task.assignedEmployeeId == id).toList();
    final notes = store.productNotes.where((note) => note.active && (note.audience == 'inventory' || note.audience == 'both')).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _WorkspaceHero(
          eyebrow: 'THAMAN • INVENTORY',
          title: s.text('مساحة موظف المخزن', 'Inventory workspace'),
          subtitle: s.text('الاستلام، الجرد، التالف، التحويلات والمهام في مساحة تشغيلية واحدة.', 'Receiving, stock counts, damage, transfers and tasks in one operational workspace.'),
          icon: Icons.warehouse_outlined,
          userName: controller.currentUserName,
        ),
        const SizedBox(height: 14),
        _AssignedStockCountsPanel(s: s, employeeId: id),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 840;
            final attendance = _AttendancePanel(s: s, employeeId: id, employeeName: controller.currentUserName);
            final notePanel = _InventoryNotesPanel(s: s, notes: notes);
            return wide ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: attendance), const SizedBox(width: 12), Expanded(child: notePanel)]) : Column(children: [attendance, const SizedBox(height: 12), notePanel]);
          },
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 850;
            final messages = _StaffMessagesPanel(s: s, employeeId: id, canSend: true);
            final requests = _InventoryRestockPanel(s: s);
            return wide
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: messages), const SizedBox(width: 12), Expanded(child: requests)])
                : Column(children: [messages, const SizedBox(height: 12), requests]);
          },
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth >= 900 ? 4 : c.maxWidth >= 560 ? 2 : 1;
            final cards = [
              _ActionData(
                s.text('إدخال بضاعة للمخزون', 'Stock entry'),
                s.text('سجّل شراء واستلام البضاعة في عملية واحدة، لصنف موجود أو منتج جديد.', 'Record purchasing and receiving in one operation for an existing or new product.'),
                Icons.add_business_rounded,
                () => _showInventoryAction(context, s, 'purchase'),
              ),
              _ActionData(s.text('بدء جرد', 'Stock count'), s.text('افتح صفحة جرد مستقلة وابحث داخل الأصناف.', 'Open a dedicated stock-count page with search.'), Icons.qr_code_scanner_rounded, () => _startCount(context, s)),
              _ActionData(s.text('تسجيل تالف', 'Damaged stock'), s.text('بحث/اختيار صنف أو تسجيل وصف يدوي.', 'Search/select an item or record a manual description.'), Icons.warning_amber_rounded, () => _showInventoryAction(context, s, 'damage')),
              _ActionData(s.text('تحويل مخزون', 'Stock transfer'), s.text('اختيار الصنف والفرع أو كتابة الحركة يدويًا.', 'Select item and branch or type the movement manually.'), Icons.swap_horiz_rounded, () => _showInventoryAction(context, s, 'transfer')),
              _ActionData(s.text('محطة الباركود', 'Barcode station'), s.text('امسح الباركود لتحديد الصنف بسرعة ثم نفذ الاستلام أو التالف أو النقل.', 'Scan a barcode to identify an item, then receive, damage or transfer it.'), Icons.qr_code_scanner_rounded, () => _barcodeStation(context, s)),
            ];
            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: cols,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: cols == 1 ? 3.2 : 1.48,
              children: cards.map((item) => _ActionCard(data: item)).toList(),
            );
          },
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 850;
            final stock = _LowStockPanel(s: s);
            final tasks = _TasksPanel(s: s, tasks: myTasks);
            return wide ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 6, child: stock), const SizedBox(width: 12), Expanded(flex: 5, child: tasks)]) : Column(children: [stock, const SizedBox(height: 12), tasks]);
          },
        ),
        const SizedBox(height: 14),
        _RecentMovements(s: s, employeeId: id),
      ],
    );
  }

  Future<void> _barcodeStation(BuildContext context, AppStrings s) async {
    final c = s.controller;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BarcodeStationScreen(s: s, actorId: c.employeeId ?? '', actorName: c.currentUserName, actorRole: 'inventory')));
  }

  Future<void> _startCount(BuildContext context, AppStrings s) async {
    final selectedIds = await showStockCountStartDialog(context, s);
    if (selectedIds == null || selectedIds.isEmpty || !context.mounted) return;
    final c = s.controller;
    final session = AppDataStore.instance.startStockCount(
      employeeId: c.employeeId ?? '',
      employeeName: c.currentUserName,
      productIds: selectedIds,
    );
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StockCountScreen(sessionId: session.id)));
  }

  Future<void> _showInventoryAction(BuildContext context, AppStrings s, String type) async {
    final c = s.controller;
    await showInventoryBatchOperation(
      context,
      s: s,
      type: type,
      actorId: c.employeeId ?? '',
      actorName: c.currentUserName,
      actorRole: 'inventory',
    );
  }
}

class _EmployeeWorkspace extends StatelessWidget {
  const _EmployeeWorkspace({required this.s});
  final AppStrings s;

  @override
  Widget build(BuildContext context) {
    final controller = s.controller;
    final store = AppDataStore.instance;
    final id = controller.employeeId;
    if (id == null || id.trim().isEmpty) {
      return Center(
        child: Text(
          s.text('انتهت جلسة الموظف. سجّل الدخول من جديد.', 'Employee session expired. Please sign in again.'),
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.danger),
        ),
      );
    }
    final employee = store.employeeOrNull(id);
    final tasks = store.tasks.where((task) => task.assignedEmployeeId == id).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _WorkspaceHero(
          eyebrow: 'THAMAN • STAFF',
          title: s.text('مساحة الموظف', 'Employee workspace'),
          subtitle: s.text('دوامك، مهامك وجدولك فقط. حالة المهام تنعكس فورًا عند الإدارة.', 'Your attendance, tasks and schedule only. Task status updates instantly for management.'),
          icon: Icons.badge_outlined,
          userName: controller.currentUserName,
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 850;
            final attendance = _AttendancePanel(s: s, employeeId: id, employeeName: controller.currentUserName);
            final taskPanel = _TasksPanel(s: s, tasks: tasks);
            return wide ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 4, child: attendance), const SizedBox(width: 12), Expanded(flex: 6, child: taskPanel)]) : Column(children: [attendance, const SizedBox(height: 12), taskPanel]);
          },
        ),
        const SizedBox(height: 14),
        _StaffMessagesPanel(s: s, employeeId: id, canSend: false),
        const SizedBox(height: 14),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.text('جدول الدوام', 'Work schedule'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              if (employee == null)
                Text(s.text('لا يوجد جدول محفوظ.', 'No saved schedule.'), style: const TextStyle(fontSize: 9, color: AppColors.muted))
              else ...[
                _ScheduleRow(day: s.text('الوردية الأساسية', 'Default shift'), time: employee.shiftLabel, status: employee.onLeave ? s.text('إجازة', 'On leave') : s.text('نشط', 'Active')),
                const Divider(height: 20),
                _ScheduleRow(day: s.text('اليوم الأسبوعي للإجازة', 'Weekly off day'), time: _weekday(employee.weeklyOffDay, s), status: s.text('إعداد الإدارة', 'Managed')),
                if (employee.leaveUntil != null) ...[
                  const Divider(height: 20),
                  _ScheduleRow(day: s.text('إجازة حالية', 'Current leave'), time: _date(employee.leaveUntil!), status: s.text('حتى التاريخ', 'Until')),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _AttendancePanel extends StatelessWidget {
  const _AttendancePanel({required this.s, required this.employeeId, required this.employeeName});
  final AppStrings s;
  final String employeeId;
  final String employeeName;

  @override
  Widget build(BuildContext context) {
    final store = AppDataStore.instance;
    final current = store.currentAttendance(employeeId);
    final clockedIn = current != null;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(13)), child: Icon(clockedIn ? Icons.how_to_reg_rounded : Icons.schedule_outlined, color: AppColors.primary, size: 20)),
            const SizedBox(width: 11),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.text('الحضور والانصراف', 'Clock in / out'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
              Text(clockedIn ? '${s.text('تم تسجيل الحضور', 'Clocked in')} • ${_time(current.clockIn)}' : s.text('اضغط تسجيل الحضور لبدء دوامك.', 'Clock in to start your shift.'), style: const TextStyle(fontSize: 9, color: AppColors.muted)),
            ])),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: clockedIn
                ? OutlinedButton.icon(onPressed: () => _confirmClockOut(context), icon: const Icon(Icons.logout_rounded, size: 17), label: Text(s.text('تسجيل الانصراف', 'Clock out')))
                : FilledButton.icon(onPressed: () => store.clockIn(employeeId, employeeName), icon: const Icon(Icons.login_rounded, size: 17), label: Text(s.text('تسجيل الحضور', 'Clock in'))),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClockOut(BuildContext context) async {
    final store = AppDataStore.instance;
    if (!store.settings.requireClockOutConfirmation) {
      store.clockOut(employeeId);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
          scrollable: true,
        title: Text(s.text('تأكيد تسجيل الانصراف', 'Confirm clock out')),
        content: Text(s.text('هل أنت متأكد؟ سيتم إغلاق سجل دوامك الحالي الآن.', 'Are you sure? Your current attendance record will be closed now.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.text('إلغاء', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(s.text('تسجيل الانصراف', 'Clock out'))),
        ],
      ),
    );
    if (ok == true) store.clockOut(employeeId);
  }
}

class _InventoryNotesPanel extends StatelessWidget {
  const _InventoryNotesPanel({required this.s, required this.notes});
  final AppStrings s;
  final List<ProductNote> notes;

  @override
  Widget build(BuildContext context) {
    final store = AppDataStore.instance;
    return SurfaceCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Icon(Icons.sticky_note_2_outlined, color: AppColors.accent, size: 20), const SizedBox(width: 8), Text(s.text('ملاحظات الإدارة للمخزون', 'Management notes'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900))]),
        const SizedBox(height: 12),
        if (notes.isEmpty)
          Text(s.text('لا توجد ملاحظات جديدة.', 'No new notes.'), style: const TextStyle(fontSize: 9, color: AppColors.muted))
        else
          for (final note in notes.take(4)) ...[
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(store.productOrNull(note.productId) == null ? note.productId : s.text(store.product(note.productId).nameAr, store.product(note.productId).nameEn), style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(note.text, style: const TextStyle(fontSize: 8.7, color: AppColors.muted, height: 1.45)),
              ])),
              IconButton(tooltip: s.text('تمت المراجعة', 'Dismiss'), onPressed: () => store.dismissProductNote(note.id), icon: const Icon(Icons.check_rounded, size: 17)),
            ]),
            if (note != notes.take(4).last) const Divider(height: 16),
          ],
      ]),
    );
  }
}

class _TasksPanel extends StatelessWidget {
  const _TasksPanel({required this.s, required this.tasks});
  final AppStrings s;
  final List<TaskRecord> tasks;

  @override
  Widget build(BuildContext context) {
    final sorted = [...tasks]..sort((a, b) => a.done == b.done ? a.dueAt.compareTo(b.dueAt) : a.done ? 1 : -1);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Expanded(child: Text(s.text('مهامي', 'My tasks'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900))), Text('${sorted.where((t) => !t.done).length}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.primary))]),
          const SizedBox(height: 12),
          if (sorted.isEmpty)
            Text(s.text('لا توجد مهام حالية.', 'No current tasks.'), style: const TextStyle(fontSize: 9, color: AppColors.muted))
          else
            for (final task in sorted) ...[
              _TaskRow(task: task, s: s),
              if (task != sorted.last) const Divider(height: 18),
            ],
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task, required this.s});
  final TaskRecord task;
  final AppStrings s;

  @override
  Widget build(BuildContext context) {
    final tone = task.status == 'completed' ? AppColors.success : task.status == 'in_progress' ? AppColors.blue : task.isOverdue ? AppColors.danger : AppColors.accent;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 9, height: 9, margin: const EdgeInsets.only(top: 4), decoration: BoxDecoration(color: tone, shape: BoxShape.circle)),
        const SizedBox(width: 9),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.text(task.titleAr, task.titleEn), style: TextStyle(fontSize: 9.7, fontWeight: FontWeight.w900, decoration: task.done ? TextDecoration.lineThrough : null)),
          const SizedBox(height: 3),
          Text('${_dateTime(task.dueAt)} • ${s.text('من', 'By')}: ${task.assignedBy}', style: const TextStyle(fontSize: 8.2, color: AppColors.muted)),
        ])),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: [
        _TaskStatusButton(label: s.text('لم تبدأ', 'Pending'), selected: task.status == 'pending', onTap: () => AppDataStore.instance.updateTaskStatus(task.id, 'pending')),
        _TaskStatusButton(label: s.text('قيد التنفيذ', 'In progress'), selected: task.status == 'in_progress', onTap: () => AppDataStore.instance.updateTaskStatus(task.id, 'in_progress')),
        _TaskStatusButton(label: s.text('تم الإنجاز', 'Completed'), selected: task.status == 'completed', onTap: () => AppDataStore.instance.updateTaskStatus(task.id, 'completed')),
      ]),
    ]);
  }
}

class _TaskStatusButton extends StatelessWidget {
  const _TaskStatusButton({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(color: selected ? AppColors.primary : AppColors.surfaceAlt, borderRadius: BorderRadius.circular(20), border: Border.all(color: selected ? AppColors.primary : AppColors.border)),
          child: Text(label, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: selected ? Colors.white : AppColors.muted)),
        ),
      );
}

class _AssignedStockCountsPanel extends StatelessWidget {
  const _AssignedStockCountsPanel({required this.s, required this.employeeId});
  final AppStrings s;
  final String employeeId;

  @override
  Widget build(BuildContext context) {
    final store = AppDataStore.instance;
    final sessions = store.stockCounts
        .where((session) =>
            session.employeeId == employeeId &&
            (session.status == 'open' || session.status == 'submitted'))
        .toList();
    return SurfaceCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.fact_check_outlined, color: AppColors.primary, size: 19),
          const SizedBox(width: 8),
          Expanded(child: Text(s.text('طلبات الجرد المسندة إليك', 'Assigned stock counts'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900))),
          Text('${sessions.length}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.primary)),
        ]),
        const SizedBox(height: 5),
        Text(s.text('أدخل الكمية الفعلية فقط. أرقام النظام والفروقات مخفية عن موظف المخزن لضمان جرد محايد.', 'Enter physical quantities only. System quantities and variances are hidden from inventory staff for an unbiased count.'), style: const TextStyle(fontSize: 8.5, color: AppColors.muted, height: 1.5)),
        const SizedBox(height: 10),
        if (sessions.isEmpty)
          Text(s.text('لا يوجد جرد مطلوب منك حاليًا.', 'No stock count is assigned to you right now.'), style: const TextStyle(fontSize: 9, color: AppColors.muted))
        else
          for (final session in sessions) ...[
            InkWell(
              onTap: session.status == 'open'
                  ? () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StockCountScreen(sessionId: session.id)))
                  : null,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Container(width: 36, height: 36, decoration: BoxDecoration(color: session.status == 'submitted' ? AppColors.blue.withValues(alpha: .08) : AppColors.primarySoft, borderRadius: BorderRadius.circular(10)), child: Icon(session.status == 'submitted' ? Icons.hourglass_top_rounded : Icons.inventory_2_outlined, size: 17, color: session.status == 'submitted' ? AppColors.blue : AppColors.primary)),
                  const SizedBox(width: 9),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${session.number} • ${session.lines.length} ${s.text('صنف', 'items')}', style: const TextStyle(fontSize: 9.6, fontWeight: FontWeight.w900)),
                    Text(session.requestedByName.isEmpty ? s.text('جرد مباشر', 'Direct count') : '${s.text('طلبه', 'Requested by')}: ${session.requestedByName}', style: const TextStyle(fontSize: 8.1, color: AppColors.muted)),
                  ])),
                  Text(session.status == 'submitted' ? s.text('بانتظار الإدارة', 'Waiting for management') : s.text('ابدأ الجرد', 'Open count'), style: TextStyle(fontSize: 8.3, fontWeight: FontWeight.w900, color: session.status == 'submitted' ? AppColors.blue : AppColors.primary)),
                  if (session.status == 'open') const SizedBox(width: 5),
                  if (session.status == 'open') const Icon(Icons.chevron_right_rounded, size: 17, color: AppColors.muted),
                ]),
              ),
            ),
            if (session != sessions.last) const Divider(height: 10),
          ],
      ]),
    );
  }
}

class _LowStockPanel extends StatelessWidget {
  const _LowStockPanel({required this.s});
  final AppStrings s;
  @override
  Widget build(BuildContext context) {
    final items = AppDataStore.instance.lowStock;
    return SurfaceCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text(s.text('تنبيهات المخزون', 'Stock alerts'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900))), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5), decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(20)), child: Text('${items.length}', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: AppColors.accent)))]),
        const SizedBox(height: 12),
        for (final product in items.take(5)) ...[
          Row(children: [Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle)), const SizedBox(width: 9), Expanded(child: Text(s.text(product.nameAr, product.nameEn), style: const TextStyle(fontSize: 9.8, fontWeight: FontWeight.w700))), Text(s.text('تنبيه نقص', 'Low stock'), style: const TextStyle(fontSize: 8.7, color: AppColors.muted, fontWeight: FontWeight.w800))]),
          if (product != items.take(5).last) const Divider(height: 18),
        ],
      ]),
    );
  }
}

class _RecentMovements extends StatelessWidget {
  const _RecentMovements({required this.s, required this.employeeId});
  final AppStrings s;
  final String employeeId;
  @override
  Widget build(BuildContext context) {
    final store = AppDataStore.instance;
    final movements = store.stockMovements.where((m) => m.employeeId == employeeId || m.employeeId.isEmpty).take(10).toList();
    return SurfaceCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.text('آخر حركات المخزون', 'Recent stock movements'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        if (movements.isEmpty)
          Text(s.text('ستظهر هنا عمليات الاستلام والجرد والتالف والتحويل.', 'Receiving, counts, damage and transfers will appear here.'), style: const TextStyle(fontSize: 9, color: AppColors.muted))
        else
          for (final movement in movements) ...[
            InkWell(
              onTap: () => _movementDetails(context, movement),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Icon(_movementIcon(movement.type), size: 17, color: AppColors.primary),
                  const SizedBox(width: 9),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_movementName(store, movement, s), style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700)), Text(_dateTime(movement.createdAt), style: const TextStyle(fontSize: 7.9, color: AppColors.muted))])),
                  Text('${movement.quantity > 0 ? '+' : ''}${movement.quantity}', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: movement.quantity >= 0 ? AppColors.success : AppColors.danger)),
                  const SizedBox(width: 7),
                  Icon(s.controller.isArabic ? Icons.chevron_left_rounded : Icons.chevron_right_rounded, size: 18, color: AppColors.muted),
                ]),
              ),
            ),
            if (movement != movements.last) const Divider(height: 15),
          ],
      ]),
    );
  }

  void _movementDetails(BuildContext context, StockMovement movement) {
    final store = AppDataStore.instance;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
          scrollable: true,
        title: Text(s.text('تفاصيل حركة المخزون', 'Stock movement details')),
        content: SizedBox(width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 440.0).toDouble(), child: Column(mainAxisSize: MainAxisSize.min, children: [
          _DetailLine(label: s.text('الصنف', 'Item'), value: _movementName(store, movement, s)),
          _DetailLine(label: s.text('النوع', 'Type'), value: s.movementType(movement.type)),
          _DetailLine(label: s.text('الكمية المؤثرة على المخزون', 'Base stock quantity'), value: '${movement.quantity > 0 ? '+' : ''}${movement.quantity}'),
          if (movement.operationQuantity > 0)
            _DetailLine(label: s.text('الكمية والوحدة المدخلة', 'Entered quantity & unit'), value: '${movement.operationQuantity.toStringAsFixed(movement.operationQuantity % 1 == 0 ? 0 : 2)} ${_inventoryUnitLabel(s, movement.operationUnit)}${movement.unitsPerOperationUnit > 1 ? ' × ${movement.unitsPerOperationUnit}' : ''}'),
          _DetailLine(label: s.text('التاريخ والوقت', 'Date & time'), value: _dateTime(movement.createdAt)),
          _DetailLine(label: s.text('نفذها', 'Performed by'), value: movement.employeeName.isEmpty ? s.text('النظام', 'System') : movement.employeeName),
          if (movement.reference.isNotEmpty) _DetailLine(label: s.text('المرجع', 'Reference'), value: movement.reference),
          if (movement.note.isNotEmpty) _DetailLine(label: s.text('الملاحظة', 'Note'), value: movement.note),
        ])),
        actions: [
          OutlinedButton.icon(
            onPressed: () => ThamanPrintService.printDocument(ThamanPrintTemplates.stockMovementNotice(store, movement, isArabic: s.controller.isArabic)),
            icon: const Icon(Icons.print_outlined, size: 17),
            label: Text(s.text('طباعة', 'Print')),
          ),
          FilledButton(onPressed: () => Navigator.pop(context), child: Text(s.text('إغلاق', 'Close'))),
        ],
      ),
    );
  }
}


class _StaffMessagesPanel extends StatelessWidget {
  const _StaffMessagesPanel({required this.s, required this.employeeId, required this.canSend});
  final AppStrings s;
  final String employeeId;
  final bool canSend;

  @override
  Widget build(BuildContext context) {
    final store = AppDataStore.instance;
    final employee = store.employeeOrNull(employeeId);
    if (employee == null) return const SizedBox.shrink();
    final rows = store.messagesForEmployee(employee).take(8).toList();
    final unread = store.unreadEmployeeMessages(employee);
    return SurfaceCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.forum_outlined, color: AppColors.primary, size: 19),
          const SizedBox(width: 8),
          Expanded(child: Text(s.text('الرسائل الداخلية', 'Internal messages'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900))),
          if (unread > 0)
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(20)), child: Text('$unread', style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, color: AppColors.accent))),
          if (canSend) ...[
            const SizedBox(width: 6),
            IconButton(tooltip: s.text('رسالة جديدة', 'New message'), onPressed: () => _composeStaffMessage(context, employee), icon: const Icon(Icons.edit_outlined, size: 18)),
          ],
        ]),
        const SizedBox(height: 10),
        if (rows.isEmpty)
          Text(s.text('لا توجد رسائل بعد.', 'No messages yet.'), style: const TextStyle(fontSize: 9, color: AppColors.muted))
        else
          for (final message in rows) ...[
            InkWell(
              onTap: () {
                store.markMessageRead(message.id, employee.id);
                showDialog<void>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
          scrollable: true,
                    title: Text(message.senderName),
                    content: SizedBox(width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 470.0).toDouble(), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(message.body, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, height: 1.65)),
                      const SizedBox(height: 12),
                      _DetailLine(label: s.text('التاريخ', 'Date'), value: _dateTime(message.createdAt)),
                    ])),
                    actions: [
                      TextButton.icon(
                        onPressed: () {
                          store.hideMessageForReader(message.id, employee.id);
                          Navigator.pop(dialogContext);
                        },
                        icon: const Icon(Icons.delete_outline_rounded, size: 16),
                        label: Text(s.text('حذف', 'Delete')),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          store.markMessageUnread(message.id, employee.id);
                          Navigator.pop(dialogContext);
                        },
                        icon: const Icon(Icons.mark_email_unread_outlined, size: 16),
                        label: Text(s.text('غير مقروء', 'Mark unread')),
                      ),
                      TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(s.text('إغلاق', 'Close'))),
                      if (canSend)
                        FilledButton.icon(
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            _composeStaffMessage(context, employee, replyTo: message);
                          },
                          icon: const Icon(Icons.reply_rounded, size: 16),
                          label: Text(s.text('رد', 'Reply')),
                        ),
                    ],
                  ),
                );
              },
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  Icon(message.readBy.contains(employee.id) ? Icons.mail_outline_rounded : Icons.mark_email_unread_outlined, size: 17, color: message.readBy.contains(employee.id) ? AppColors.muted : AppColors.accent),
                  const SizedBox(width: 8),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(message.senderName, style: const TextStyle(fontSize: 9.4, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(message.body, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 8.2, color: AppColors.muted)),
                  ])),
                  Text(_time(message.createdAt), style: const TextStyle(fontSize: 7.6, color: AppColors.muted)),
                ]),
              ),
            ),
            if (message != rows.last) const Divider(height: 14),
          ],
      ]),
    );
  }

  Future<void> _composeStaffMessage(BuildContext context, EmployeeRecord employee, {MessageRecord? replyTo}) async {
    final store = AppDataStore.instance;
    final body = TextEditingController();
    String target = replyTo != null ? 'management' : 'management';
    String employeeTarget = store.activeEmployees.where((e) => e.id != employee.id).isEmpty ? '' : store.activeEmployees.where((e) => e.id != employee.id).first.id;
    await showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, setD) => AlertDialog(
          scrollable: true,
          title: Text(replyTo == null ? s.text('إرسال رسالة', 'Send message') : s.text('رد على الإدارة', 'Reply to management')),
          content: SizedBox(width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 520.0).toDouble(), child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: target,
              decoration: InputDecoration(labelText: s.text('المستلم', 'Recipient')),
              items: [
                DropdownMenuItem(value: 'management', child: Text(s.text('المالك والمدير', 'Owner & manager'))),
                DropdownMenuItem(value: 'all_staff', child: Text(s.text('كل الموظفين', 'All employees'))),
                DropdownMenuItem(value: 'employee', child: Text(s.text('موظف محدد', 'Specific employee'))),
              ],
              onChanged: (v) => setD(() => target = v ?? target),
            ),
            if (target == 'employee') ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: employeeTarget.isEmpty ? null : employeeTarget,
                decoration: InputDecoration(labelText: s.text('الموظف', 'Employee')),
                items: store.activeEmployees.where((e) => e.id != employee.id).map((e) => DropdownMenuItem(value: e.id, child: Text('${s.text(e.nameAr, e.nameEn)} • ${e.id}'))).toList(),
                onChanged: (v) => setD(() => employeeTarget = v ?? employeeTarget),
              ),
            ],
            const SizedBox(height: 10),
            TextField(controller: body, minLines: 3, maxLines: 6, decoration: InputDecoration(labelText: s.text('نص الرسالة', 'Message'))),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(s.text('إلغاء', 'Cancel'))),
            FilledButton.icon(
              onPressed: () {
                if (body.text.trim().isEmpty) return;
                store.sendMessage(
                  senderId: employee.id,
                  senderName: s.text(employee.nameAr, employee.nameEn),
                  senderRole: employee.roleKey,
                  recipientType: target,
                  recipientId: target == 'employee' ? employeeTarget : '',
                  body: body.text.trim(),
                  replyToId: replyTo?.id ?? '',
                );
                Navigator.pop(dialogContext);
              },
              icon: const Icon(Icons.send_rounded, size: 16),
              label: Text(s.text('إرسال', 'Send')),
            ),
          ],
        ),
      ),
    );
    body.dispose();
  }
}

class _InventoryRestockPanel extends StatelessWidget {
  const _InventoryRestockPanel({required this.s});
  final AppStrings s;

  @override
  Widget build(BuildContext context) {
    final store = AppDataStore.instance;
    final rows = store.openRestockRequests.take(6).toList();
    return SurfaceCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.shopping_cart_checkout_outlined, color: AppColors.accent, size: 19),
          const SizedBox(width: 8),
          Expanded(child: Text(s.text('طلبات التوريد من الإدارة', 'Management restock requests'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900))),
          Text('${rows.length}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.accent)),
        ]),
        const SizedBox(height: 10),
        if (rows.isEmpty)
          Text(s.text('لا توجد طلبات مفتوحة.', 'No open requests.'), style: const TextStyle(fontSize: 9, color: AppColors.muted))
        else
          for (final request in rows) ...[
            InkWell(
              onTap: () => _restockDetails(context, request),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(request.number, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900)),
                    Text(request.lines.map((e) => '${e.itemName} × ${e.quantity.toStringAsFixed(e.quantity % 1 == 0 ? 0 : 2)}').take(2).join(s.text('، ', ', ')), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 8.2, color: AppColors.muted)),
                  ])),
                  Text(s.status(request.status), style: const TextStyle(fontSize: 8.2, fontWeight: FontWeight.w800, color: AppColors.primary)),
                  const SizedBox(width: 5),
                  const Icon(Icons.chevron_right_rounded, size: 17, color: AppColors.muted),
                ]),
              ),
            ),
            if (request != rows.last) const Divider(height: 14),
          ],
      ]),
    );
  }

  void _restockDetails(BuildContext context, RestockRequest request) {
    final store = AppDataStore.instance;
    showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, setD) => AlertDialog(
          scrollable: true,
          title: Text(request.number),
          content: SizedBox(width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 560.0).toDouble(), child: Column(mainAxisSize: MainAxisSize.min, children: [
            _DetailLine(label: s.text('من الإدارة', 'From management'), value: request.createdByName),
            _DetailLine(label: s.text('التاريخ', 'Date'), value: _dateTime(request.createdAt)),
            _DetailLine(label: s.text('الحالة', 'Status'), value: s.status(request.status)),
            if (request.note.isNotEmpty) _DetailLine(label: s.text('ملاحظة', 'Note'), value: request.note),
            const Divider(height: 20),
            for (final line in request.lines)
              Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: [Expanded(child: Text(line.itemName, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900))), Text('${line.quantity.toStringAsFixed(line.quantity % 1 == 0 ? 0 : 2)} ${_inventoryUnitLabel(s, line.unit)}', style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: AppColors.primary))])),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(s.text('إغلاق', 'Close'))),
            PopupMenuButton<String>(
              onSelected: (status) {
                store.updateRestockStatus(requestId: request.id, status: status, actorName: s.controller.currentUserName, actorRole: 'inventory');
                setD(() {});
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'reviewing', child: Text(s.text('قيد المراجعة', 'Reviewing'))),
                PopupMenuItem(value: 'ordered', child: Text(s.text('تم الطلب', 'Ordered'))),
                PopupMenuItem(value: 'received', child: Text(s.text('تم الاستلام', 'Received'))),
              ],
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: Text(s.text('تحديث الحالة', 'Update status'), style: const TextStyle(fontWeight: FontWeight.w800))),
            ),
          ],
        ),
      ),
    );
  }
}


class _WorkspaceHero extends StatelessWidget {
  const _WorkspaceHero({required this.eyebrow, required this.title, required this.subtitle, required this.icon, required this.userName});
  final String eyebrow;
  final String title;
  final String subtitle;
  final IconData icon;
  final String userName;
  @override
  Widget build(BuildContext context) => BrandPattern(
        dark: true,
        borderRadius: BorderRadius.circular(26),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.primaryStrong, Color(0xFF0F5B50)]), borderRadius: BorderRadius.circular(26)),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(eyebrow, style: TextStyle(color: Colors.white.withValues(alpha: .55), fontSize: 8.5, letterSpacing: 1.1, fontWeight: FontWeight.w800)), const SizedBox(height: 9), Text(title, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -.7)), const SizedBox(height: 7), Text(subtitle, style: const TextStyle(color: Color(0xFFC1D9D3), fontSize: 10, height: 1.6)), const SizedBox(height: 13), Text(userName, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800))])),
            if (MediaQuery.sizeOf(context).width > 600) Container(width: 70, height: 70, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .09), borderRadius: BorderRadius.circular(21), border: Border.all(color: Colors.white.withValues(alpha: .1))), child: Icon(icon, color: Colors.white, size: 30)),
          ]),
        ),
      );
}

class _ActionData {
  const _ActionData(this.title, this.subtitle, this.icon, this.onTap);
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.data});
  final _ActionData data;
  @override
  Widget build(BuildContext context) => SurfaceCard(
        child: InkWell(
          onTap: data.onTap,
          borderRadius: BorderRadius.circular(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(13)), child: Icon(data.icon, color: AppColors.primary, size: 20)), const Spacer(), const Icon(Icons.arrow_outward_rounded, size: 17, color: AppColors.muted)]), const Spacer(), Text(data.title, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text(data.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 8.7, color: AppColors.muted, height: 1.45))]),
        ),
      );
}

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({required this.day, required this.time, required this.status});
  final String day;
  final String time;
  final String status;
  @override
  Widget build(BuildContext context) => Row(children: [SizedBox(width: 145, child: Text(day, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800))), Expanded(child: Text(time, style: const TextStyle(fontSize: 9.5, color: AppColors.muted))), Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(20)), child: Text(status, style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: AppColors.primary)))]);
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 7), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 120, child: Text(label, style: const TextStyle(fontSize: 9, color: AppColors.muted))), Expanded(child: Text(value, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800)))]));
}

IconData _movementIcon(String type) => switch (type) {
      'receive' => Icons.move_to_inbox_outlined,
      'damage' || 'damage_manual' => Icons.warning_amber_rounded,
      'transfer' || 'transfer_manual' => Icons.swap_horiz_rounded,
      'count' => Icons.fact_check_outlined,
      'return' => Icons.assignment_return_outlined,
      'sale' => Icons.point_of_sale_outlined,
      _ => Icons.inventory_2_outlined,
    };

String _movementName(AppDataStore store, StockMovement movement, AppStrings s) {
  final p = movement.productId.isEmpty ? null : store.productOrNull(movement.productId);
  return p == null
      ? (movement.itemName.isEmpty ? movement.productId : movement.itemName)
      : s.text(p.nameAr, p.nameEn);
}

String _inventoryUnitLabel(AppStrings s, String value) => switch (value) {
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

String _time(DateTime date) => formatHour12(date);
String _date(DateTime date) => '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
String _dateTime(DateTime date) => '${_date(date)} • ${_time(date)}';
String _weekday(int day, AppStrings s) => switch (day) {
      DateTime.monday => s.text('الاثنين', 'Monday'),
      DateTime.tuesday => s.text('الثلاثاء', 'Tuesday'),
      DateTime.wednesday => s.text('الأربعاء', 'Wednesday'),
      DateTime.thursday => s.text('الخميس', 'Thursday'),
      DateTime.friday => s.text('الجمعة', 'Friday'),
      DateTime.saturday => s.text('السبت', 'Saturday'),
      _ => s.text('الأحد', 'Sunday'),
    };
