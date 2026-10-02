import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../core/app_controller.dart';
import '../../../core/app_strings.dart';
import '../../../core/printing/print_document.dart';
import '../../../core/printing/print_service.dart';
import '../../../core/widgets/surface_card.dart';
import '../../../data/app_data_store.dart';
import '../../../data/models.dart';
import '../widgets/management_widgets.dart';

class PayrollSection extends StatefulWidget {
  const PayrollSection({super.key, required this.s});
  final AppStrings s;

  @override
  State<PayrollSection> createState() => _PayrollSectionState();
}

class _PayrollSectionState extends State<PayrollSection> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
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
    final role = s.controller.role;
    final allowed = role == UserRole.owner || role == UserRole.manager || role == UserRole.accountant;
    if (!allowed) {
      return EmptyPanel(
        message: s.text('لا تملك صلاحية عرض الرواتب.', 'You do not have payroll access.'),
        icon: Icons.lock_outline_rounded,
      );
    }

    return AnimatedBuilder(
      animation: store,
      builder: (_, __) {
        final q = search.text.trim().toLowerCase();
        final employees = store.employees.where((e) {
          return q.isEmpty ||
              e.loginId.toLowerCase().contains(q) ||
              e.nameAr.toLowerCase().contains(q) ||
              e.nameEn.toLowerCase().contains(q) ||
              e.roleKey.toLowerCase().contains(q);
        }).toList();

        final canEditPayroll = role == UserRole.owner || role == UserRole.manager;
        final canAdvance = role == UserRole.owner || role == UserRole.accountant;
        final nowMonth = DateTime(DateTime.now().year, DateTime.now().month);
        final selectedMonth = DateTime(month.year, month.month);
        final isFuturePeriod = selectedMonth.isAfter(nowMonth);
        final isPastPeriodWithoutHistory = selectedMonth.isBefore(nowMonth) && !store.hasPayrollActivityForMonth(selectedMonth);
        final periodAvailable = !isFuturePeriod && !isPastPeriodWithoutHistory;
        final payrollEmployees = periodAvailable ? employees.where((e) => e.salary > 0).toList() : <EmployeeRecord>[];
        final total = payrollEmployees.fold<double>(0, (sum, e) => sum + store.payrollGrossFor(e.id, month));
        final paid = payrollEmployees.fold<double>(0, (sum, e) => sum + store.salaryPaidAmountFor(e.id, month));
        final outstanding = payrollEmployees.fold<double>(0, (sum, e) => sum + store.salaryOutstandingFor(e.id, month));
        final today = DateTime.now();
        final overdue = payrollEmployees.where((e) {
          if (store.salaryPaidFor(e.id, month)) return false;
          final due = store.salaryDueDate(e, month);
          return !_sameMonth(month, today)
              ? month.isBefore(DateTime(today.year, today.month))
              : due.isBefore(DateTime(today.year, today.month, today.day));
        }).length;

        return Column(
          children: [
            ManagementMetricsGrid(items: [
              ManagementMetric(s.text('إجمالي رواتب الشهر', 'Monthly payroll'), '${total.toStringAsFixed(2)} ${store.settings.currency}', Icons.payments_outlined, AppColors.primary),
              ManagementMetric(s.text('تم صرفه', 'Paid'), '${paid.toStringAsFixed(2)} ${store.settings.currency}', Icons.check_circle_outline_rounded, AppColors.success),
              ManagementMetric(s.text('متبقي', 'Outstanding'), '${outstanding.toStringAsFixed(2)} ${store.settings.currency}', Icons.hourglass_bottom_rounded, AppColors.accent),
              ManagementMetric(s.text('رواتب متأخرة', 'Overdue salaries'), '$overdue', Icons.warning_amber_rounded, AppColors.danger),
            ]),
            const SizedBox(height: 12),
            SurfaceCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                SectionCardHeader(
                  title: s.text('الرواتب والسلف ومواعيد القبض', 'Payroll, advances & pay dates'),
                  subtitle: s.text(
                    'يمكن صرف الراتب كاملًا أو على دفعات، ومراجعة السلف وخصمها من الدفعة. كل عملية تبقى محفوظة في المصروفات والقيود المحاسبية.',
                    'Salary can be paid in full or in installments. Advances can be reviewed and deducted from a payment. Every transaction remains in expenses and accounting entries.',
                  ),
                  trailing: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${s.text('رواتب الشهر الحالي', 'Current month payroll')} • ${_monthLabel(s, month)}',
                          style: const TextStyle(fontSize: 8.8, fontWeight: FontWeight.w900, color: AppColors.primary),
                        ),
                      ),
                      SearchField(controller: search, hint: s.text('اسم أو رقم الموظف...', 'Employee name or ID...'), onChanged: (_) => setState(() {}), width: 220),
                      OutlinedButton.icon(onPressed: () => _printPayroll(payrollEmployees), icon: const Icon(Icons.print_outlined, size: 16), label: Text(s.text('طباعة', 'Print'))),
                    ],
                  ),
                ),
                const Divider(height: 1),
                if (!periodAvailable)
                  EmptyPanel(
                    message: isFuturePeriod
                        ? s.text('هذه الفترة لم تبدأ بعد، لذلك لا يتم إنشاء رواتب مستقبلية تلقائيًا.', 'This period has not started yet, so future payroll is not generated automatically.')
                        : s.text('لا توجد سجلات رواتب أو سلف محفوظة لهذه الفترة. النظام لا يفترض رواتب تاريخية قبل بدء استخدامه.', 'There are no saved payroll or advance records for this period. The system does not invent historical payroll before it was used.'),
                    icon: isFuturePeriod ? Icons.event_busy_rounded : Icons.history_rounded,
                  )
                else if (employees.isEmpty)
                  EmptyPanel(message: s.text('لا توجد نتائج.', 'No matching employees.'))
                else
                  for (final e in employees) ...[
                    _PayrollTile(
                      employee: e,
                      month: month,
                      s: s,
                      onEdit: canEditPayroll ? () => _editPayroll(context, e) : null,
                      onAdvance: canAdvance ? () => _giveAdvance(context, e) : null,
                      onPay: e.salary <= 0 || store.salaryOutstandingFor(e.id, month) <= 0.005
                          ? null
                          : () => _paySalary(context, e),
                    ),
                    if (e != employees.last) const Divider(height: 1),
                  ],
              ]),
            ),
          ],
        );
      },
    );
  }

  Future<void> _editPayroll(BuildContext context, EmployeeRecord e) async {
    final s = widget.s;
    final salary = TextEditingController(text: e.salary <= 0 ? '' : e.salary.toStringAsFixed(2));
    final day = TextEditingController(text: '${e.salaryPayDay}');
    String? error;
    await showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          scrollable: true,
          title: Text('${s.text('إعداد الراتب', 'Payroll settings')} • ${s.text(e.nameAr, e.nameEn)}'),
          content: SizedBox(
            width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 460.0).toDouble(),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (error != null)
                Container(width: double.infinity, margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: .08), borderRadius: BorderRadius.circular(10)), child: Text(error!, style: const TextStyle(fontSize: 8.7, color: AppColors.danger, fontWeight: FontWeight.w800))),
              TextField(controller: salary, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: s.text('الراتب الشهري', 'Monthly salary'), suffixText: AppDataStore.instance.settings.currency)),
              const SizedBox(height: 10),
              TextField(controller: day, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: s.text('يوم القبض من الشهر (1-31)', 'Pay day of month (1-31)'))),
              const SizedBox(height: 8),
              Text(s.text('إذا كان الشهر أقصر من يوم القبض المختار، يتم اعتماد آخر يوم في الشهر.', 'If a month is shorter than the selected pay day, the last day of that month is used.'), style: const TextStyle(fontSize: 8.2, color: AppColors.muted)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(s.text('إلغاء', 'Cancel'))),
            FilledButton(
              onPressed: () {
                final amount = double.tryParse(salary.text.trim()) ?? -1;
                final payDay = int.tryParse(day.text.trim()) ?? 0;
                if (amount < 0 || payDay < 1 || payDay > 31) {
                  setD(() => error = s.text('أدخل راتبًا صحيحًا ويوم قبض بين 1 و31.', 'Enter a valid salary and a pay day between 1 and 31.'));
                  return;
                }
                final role = s.controller.role?.name ?? '';
                final ok = AppDataStore.instance.updateEmployeePayroll(
                  employeeId: e.id,
                  salary: amount,
                  payDay: payDay,
                  actorName: s.controller.currentUserName,
                  actorRole: role,
                );
                if (!ok) {
                  setD(() => error = s.text('تعذر حفظ بيانات الراتب.', 'Could not save payroll settings.'));
                  return;
                }
                Navigator.pop(context);
              },
              child: Text(s.text('حفظ', 'Save')),
            ),
          ],
        ),
      ),
    );
    salary.dispose();
    day.dispose();
  }

  Future<void> _giveAdvance(BuildContext context, EmployeeRecord e) async {
    final s = widget.s;
    final store = AppDataStore.instance;
    final amount = TextEditingController();
    final note = TextEditingController();
    String method = 'Cash';
    String? error;
    await showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          scrollable: true,
          title: Text('${s.text('إعطاء سلفة', 'Give advance')} • ${s.text(e.nameAr, e.nameEn)}'),
          content: SizedBox(
            width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 480.0).toDouble(),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DetailLine(label: s.text('السلف المتبقية حاليًا', 'Current outstanding advances'), value: '${store.employeeOutstandingAdvance(e.id).toStringAsFixed(2)} ${store.settings.currency}'),
              const SizedBox(height: 10),
              TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: s.text('قيمة السلفة', 'Advance amount'), suffixText: store.settings.currency)),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: method,
                decoration: InputDecoration(labelText: s.text('طريقة الصرف', 'Payment method')),
                items: ['Cash', 'Bank'].map((v) => DropdownMenuItem(value: v, child: Text(s.paymentMethod(v)))).toList(),
                onChanged: (v) => setD(() => method = v ?? method),
              ),
              const SizedBox(height: 10),
              TextField(controller: note, maxLines: 2, decoration: InputDecoration(labelText: s.text('ملاحظة السلفة', 'Advance note'))),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(color: AppColors.danger, fontSize: 8.7, fontWeight: FontWeight.w800)),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(s.text('إلغاء', 'Cancel'))),
            FilledButton(
              onPressed: () {
                final value = double.tryParse(amount.text.trim()) ?? 0;
                if (value <= 0) {
                  setD(() => error = s.text('أدخل قيمة سلفة أكبر من صفر.', 'Enter an advance amount greater than zero.'));
                  return;
                }
                final role = s.controller.role?.name ?? '';
                final record = store.recordEmployeeAdvance(
                  employeeId: e.id,
                  amount: value,
                  givenBy: s.controller.currentUserName,
                  actorRole: role,
                  paymentMethod: method,
                  note: note.text.trim(),
                );
                if (record == null) {
                  setD(() => error = s.text('تعذر تسجيل السلفة. الصلاحية للمالك أو المحاسب.', 'Could not record the advance. Owner or accountant permission is required.'));
                  return;
                }
                Navigator.pop(context);
              },
              child: Text(s.text('صرف السلفة', 'Give advance')),
            ),
          ],
        ),
      ),
    );
    amount.dispose();
    note.dispose();
  }

  Future<void> _paySalary(BuildContext context, EmployeeRecord e) async {
    final s = widget.s;
    final store = AppDataStore.instance;
    final due = store.salaryDueDate(e, month);
    final overtimeAmount = store.overtimePayFor(e.id, month);
    final grossPayroll = store.payrollGrossFor(e.id, month);
    final remaining = store.salaryOutstandingFor(e.id, month);
    final advanceOutstanding = store.employeeOutstandingAdvance(e.id);
    final amount = TextEditingController(text: remaining.toStringAsFixed(2));
    final deduction = TextEditingController(text: advanceOutstanding.clamp(0, remaining).toStringAsFixed(2));
    String method = 'Cash';
    String? error;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setD) {
          final gross = double.tryParse(amount.text.trim()) ?? 0;
          final deductionValue = double.tryParse(deduction.text.trim()) ?? 0;
          final net = (gross - deductionValue).clamp(0, double.infinity).toDouble();
          return AlertDialog(
            scrollable: true,
            title: Text('${s.text('صرف راتب', 'Pay salary')} • ${s.text(e.nameAr, e.nameEn)}'),
            content: SizedBox(
              width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 500.0).toDouble(),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DetailLine(label: s.text('الشهر', 'Month'), value: _monthLabel(s, month)),
                DetailLine(label: s.text('موعد القبض', 'Pay date'), value: _date(due)),
                DetailLine(label: s.text('الراتب الأساسي', 'Base salary'), value: '${e.salary.toStringAsFixed(2)} ${store.settings.currency}'),
                DetailLine(label: s.text('الدوام الإضافي', 'Overtime pay'), value: '${overtimeAmount.toStringAsFixed(2)} ${store.settings.currency}'),
                DetailLine(label: s.text('إجمالي المستحق قبل السلف', 'Gross due before advances'), value: '${grossPayroll.toStringAsFixed(2)} ${store.settings.currency}'),
                DetailLine(label: s.text('مصروف سابقًا هذا الشهر', 'Already paid this month'), value: '${store.salaryPaidAmountFor(e.id, month).toStringAsFixed(2)} ${store.settings.currency}'),
                DetailLine(label: s.text('المتبقي من الراتب', 'Salary remaining'), value: '${remaining.toStringAsFixed(2)} ${store.settings.currency}'),
                DetailLine(label: s.text('السلف غير المسددة', 'Outstanding advances'), value: '${advanceOutstanding.toStringAsFixed(2)} ${store.settings.currency}'),
                const SizedBox(height: 10),
                TextField(
                  controller: amount,
                  onChanged: (_) => setD(() {}),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: s.text('كم تريد أن تصرف من الراتب؟', 'How much salary do you want to pay?'), suffixText: store.settings.currency),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: deduction,
                  onChanged: (_) => setD(() {}),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: s.text('خصم من السلف في هذه الدفعة', 'Advance deduction in this payment'), suffixText: store.settings.currency, helperText: s.text('اختياري، ولا يمكن أن يتجاوز السلف المتبقية أو قيمة الدفعة.', 'Optional; cannot exceed the outstanding advances or the payment amount.')),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: method,
                  decoration: InputDecoration(labelText: s.text('طريقة الصرف', 'Payment method')),
                  items: ['Cash', 'Bank'].map((v) => DropdownMenuItem(value: v, child: Text(s.paymentMethod(v)))).toList(),
                  onChanged: (v) => setD(() => method = v ?? method),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(12)),
                  child: Wrap(spacing: 18, runSpacing: 8, children: [
                    _MiniValue(label: s.text('قيمة الراتب المسجلة', 'Salary amount'), value: '${gross.toStringAsFixed(2)} ${store.settings.currency}'),
                    _MiniValue(label: s.text('خصم السلفة', 'Advance deduction'), value: '${deductionValue.toStringAsFixed(2)} ${store.settings.currency}'),
                    _MiniValue(label: s.text('الصافي الذي سيُصرف', 'Net cash paid'), value: '${net.toStringAsFixed(2)} ${store.settings.currency}'),
                  ]),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: const TextStyle(color: AppColors.danger, fontSize: 8.7, fontWeight: FontWeight.w800)),
                ],
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.text('إلغاء', 'Cancel'))),
              FilledButton(
                onPressed: () {
                  final grossValue = double.tryParse(amount.text.trim()) ?? 0;
                  final deductionValue = double.tryParse(deduction.text.trim()) ?? 0;
                  if (grossValue <= 0 || grossValue > remaining + 0.005) {
                    setD(() => error = s.text('قيمة الصرف يجب أن تكون أكبر من صفر ولا تتجاوز المتبقي من الراتب.', 'Payment must be greater than zero and cannot exceed the remaining salary.'));
                    return;
                  }
                  if (deductionValue < 0 || deductionValue > grossValue + 0.005 || deductionValue > advanceOutstanding + 0.005) {
                    setD(() => error = s.text('قيمة خصم السلفة غير صحيحة.', 'The advance deduction is invalid.'));
                    return;
                  }
                  Navigator.pop(context, true);
                },
                child: Text(s.text('تأكيد الصرف', 'Confirm payment')),
              ),
            ],
          );
        },
      ),
    );

    if (ok == true && mounted) {
      final role = s.controller.role?.name ?? '';
      final record = store.recordSalaryPayment(
        employeeId: e.id,
        month: month,
        paidBy: s.controller.currentUserName,
        actorRole: role,
        paymentMethod: method,
        grossAmount: double.tryParse(amount.text.trim()) ?? 0,
        advanceDeduction: double.tryParse(deduction.text.trim()) ?? 0,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(record == null ? s.text('تعذر تسجيل دفعة الراتب.', 'Could not record the salary payment.') : s.text('تم تسجيل دفعة الراتب وتحديث المصروفات والسلف.', 'Salary payment recorded; expenses and advances were updated.'))));
      }
    }
    amount.dispose();
    deduction.dispose();
  }

  Future<void> _printPayroll(List<EmployeeRecord> employees) async {
    final store = AppDataStore.instance;
    final s = widget.s;
    final rows = employees.map((e) {
      final due = store.salaryDueDate(e, month);
      final paidAmount = store.salaryPaidAmountFor(e.id, month);
      final remaining = store.salaryOutstandingFor(e.id, month);
      final lastPayment = store.salaryPaymentFor(e.id, month);
      return [
        e.loginId,
        s.text(e.nameAr, e.nameEn),
        s.roleKey(e.roleKey),
        '${e.salary.toStringAsFixed(2)} + ${store.overtimePayFor(e.id, month).toStringAsFixed(2)} = ${store.payrollGrossFor(e.id, month).toStringAsFixed(2)} ${store.settings.currency}',
        '${paidAmount.toStringAsFixed(2)} ${store.settings.currency}',
        '${remaining.toStringAsFixed(2)} ${store.settings.currency}',
        '${store.employeeOutstandingAdvance(e.id).toStringAsFixed(2)} ${store.settings.currency}',
        _date(due),
        store.salaryPaidFor(e.id, month) ? s.text('مدفوع', 'Paid') : paidAmount > 0 ? s.text('مدفوع جزئيًا', 'Partially paid') : s.text('غير مدفوع', 'Unpaid'),
        lastPayment == null ? '-' : _date(lastPayment.createdAt),
      ];
    }).toList();
    await ThamanPrintService.printDocument(PrintDocument(
      title: s.text('كشف الرواتب والسلف', 'Payroll & Advances Statement'),
      subtitle: '${store.settings.storeName} • ${_monthLabel(s, month)}',
      metadata: {
        s.text('عدد الموظفين', 'Employees'): '${employees.length}',
        s.text('إجمالي الرواتب', 'Total payroll'): '${employees.fold<double>(0, (sum, e) => sum + store.payrollGrossFor(e.id, month)).toStringAsFixed(2)} ${store.settings.currency}',
        s.text('صافي بعد السلف', 'Net after advances'): '${employees.fold<double>(0, (sum, e) => sum + store.employeeNetSalaryAfterAdvances(e.id, month)).toStringAsFixed(2)} ${store.settings.currency}',
      },
      headers: [s.text('الرقم', 'ID'), s.text('الموظف', 'Employee'), s.text('الدور', 'Role'), s.text('الراتب + الإضافي', 'Salary + overtime'), s.text('مصروف', 'Paid'), s.text('متبقي', 'Remaining'), s.text('سلف', 'Advances'), s.text('موعد القبض', 'Pay date'), s.text('الحالة', 'Status'), s.text('آخر صرف', 'Last payment')],
      rows: rows,
      footer: store.settings.receiptFooter,
      isArabic: s.controller.isArabic,
    ));
  }
}

class _PayrollTile extends StatelessWidget {
  const _PayrollTile({
    required this.employee,
    required this.month,
    required this.s,
    required this.onEdit,
    required this.onPay,
    required this.onAdvance,
  });

  final EmployeeRecord employee;
  final DateTime month;
  final AppStrings s;
  final VoidCallback? onEdit;
  final VoidCallback? onPay;
  final VoidCallback? onAdvance;

  @override
  Widget build(BuildContext context) {
    final store = AppDataStore.instance;
    final due = store.salaryDueDate(employee, month);
    final configured = employee.salary > 0;
    final paidAmount = store.salaryPaidAmountFor(employee.id, month);
    final overtimeAmount = store.overtimePayFor(employee.id, month);
    final grossPayroll = store.payrollGrossFor(employee.id, month);
    final remaining = store.salaryOutstandingFor(employee.id, month);
    final paid = configured && remaining <= 0.005;
    final now = DateTime.now();
    final overdue = configured && !paid &&
        (_sameMonth(month, now)
            ? due.isBefore(DateTime(now.year, now.month, now.day))
            : month.isBefore(DateTime(now.year, now.month)));
    final status = !configured
        ? s.text('غير محدد', 'Not set')
        : paid
            ? s.text('مدفوع', 'Paid')
            : paidAmount > 0
                ? s.text('مدفوع جزئيًا', 'Partially paid')
                : overdue
                    ? s.text('متأخر', 'Overdue')
                    : s.text('مستحق', 'Due');
    final statusColor = !configured
        ? AppColors.muted
        : paid
            ? AppColors.success
            : overdue
                ? AppColors.danger
                : AppColors.accent;
    final advances = store.advancesForEmployee(employee.id)..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final payments = store.salaryPaymentsFor(employee.id, month);
    final totalAdvances = store.employeeAdvanceTotal(employee.id);
    final settledAdvances = store.employeeAdvanceSettled(employee.id);
    final outstandingAdvances = store.employeeOutstandingAdvance(employee.id);
    final netAfterAdvances = store.employeeNetSalaryAfterAdvances(employee.id, month);

    return ExpansionTile(
      leading: CircleAvatar(backgroundColor: AppColors.primarySoft, child: Text(employee.nameAr.isEmpty ? 'E' : employee.nameAr.substring(0, 1), style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w900))),
      title: Wrap(spacing: 7, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('${s.text(employee.nameAr, employee.nameEn)} • ${employee.loginId}', style: const TextStyle(fontSize: 10.2, fontWeight: FontWeight.w900)),
        if (employee.managementOnly) StatusPill(label: s.roleKey(employee.roleKey), color: AppColors.blue),
        StatusPill(label: status, color: statusColor),
      ]),
      subtitle: Text(
        configured
            ? '${s.text('الراتب', 'Salary')} = ${employee.salary.toStringAsFixed(2)} + ${s.text('الدوام الإضافي', 'Overtime')} = ${overtimeAmount.toStringAsFixed(2)} - ${s.text('السلف المتبقية', 'Outstanding advances')} = ${outstandingAdvances.toStringAsFixed(2)} • ${s.text('الباقي له', 'Net due')} = ${netAfterAdvances.toStringAsFixed(2)} ${store.settings.currency}'
            : s.text('لم يتم تحديد راتب لهذا الموظف.', 'No salary is configured for this employee.'),
        style: const TextStyle(fontSize: 8.4, color: AppColors.muted),
      ),
      trailing: Wrap(
        spacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (onAdvance != null) OutlinedButton.icon(onPressed: onAdvance, icon: const Icon(Icons.request_quote_outlined, size: 15), label: Text(s.text('سلفة', 'Advance'))),
          if (onEdit != null) OutlinedButton.icon(onPressed: onEdit, icon: const Icon(Icons.edit_outlined, size: 15), label: Text(s.text('الراتب', 'Payroll'))),
          if (onPay != null) FilledButton.tonalIcon(onPressed: onPay, icon: const Icon(Icons.payments_outlined, size: 15), label: Text(s.text('صرف', 'Pay'))),
          const Icon(Icons.keyboard_arrow_down_rounded),
        ],
      ),
      childrenPadding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 14),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.text('تفاصيل الراتب والسلف', 'Payroll & advance details'), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Wrap(spacing: 18, runSpacing: 8, children: [
              _MiniValue(label: s.text('موعد القبض', 'Pay date'), value: _date(due)),
              _MiniValue(label: s.text('الراتب الأساسي', 'Base salary'), value: '${employee.salary.toStringAsFixed(2)} ${store.settings.currency}'),
              _MiniValue(label: s.text('قيمة الدوام الإضافي', 'Overtime pay'), value: '${overtimeAmount.toStringAsFixed(2)} ${store.settings.currency}'),
              _MiniValue(label: s.text('الإجمالي قبل السلف', 'Gross before advances'), value: '${grossPayroll.toStringAsFixed(2)} ${store.settings.currency}'),
              _MiniValue(label: s.text('مصروف هذا الشهر', 'Paid this month'), value: '${paidAmount.toStringAsFixed(2)} ${store.settings.currency}'),
              _MiniValue(label: s.text('متبقي قبل خصم السلف', 'Remaining before advances'), value: '${remaining.toStringAsFixed(2)} ${store.settings.currency}'),
              _MiniValue(label: s.text('إجمالي السلف المأخوذة', 'Total advances taken'), value: '${totalAdvances.toStringAsFixed(2)} ${store.settings.currency}'),
              _MiniValue(label: s.text('تم تسديده من السلف', 'Advances settled'), value: '${settledAdvances.toStringAsFixed(2)} ${store.settings.currency}'),
              _MiniValue(label: s.text('المتبقي من السلف', 'Advances outstanding'), value: '${outstandingAdvances.toStringAsFixed(2)} ${store.settings.currency}'),
              _MiniValue(label: s.text('صافي المستحق بعد السلف', 'Net due after advances'), value: '${netAfterAdvances.toStringAsFixed(2)} ${store.settings.currency}'),
            ]),
            if (advances.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(s.text('آخر السلف', 'Latest advances'), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900)),
              const SizedBox(height: 5),
              for (final a in advances.take(4))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('${s.text('التاريخ','Date')}: ${_date(a.createdAt)}  |  ${s.text('السلفة','Advance')}: ${a.amount.toStringAsFixed(2)} ${store.settings.currency}  |  ${s.text('المسدّد','Settled')}: ${a.settledAmount.toStringAsFixed(2)}  |  ${s.text('المتبقي','Remaining')}: ${a.outstanding.toStringAsFixed(2)} ${store.settings.currency}  |  ${s.text('الطريقة','Method')}: ${s.paymentMethod(a.paymentMethod)}${a.note.isEmpty ? '' : '  |  ${s.text('ملاحظة','Note')}: ${a.note}'}', style: const TextStyle(fontSize: 8.1, color: AppColors.muted)),
                ),
            ],
            if (payments.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(s.text('دفعات راتب هذا الشهر', 'Salary payments this month'), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900)),
              const SizedBox(height: 5),
              for (final p in payments.take(5))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('${_date(p.createdAt)} • ${p.amount.toStringAsFixed(2)} ${store.settings.currency} • ${s.paymentMethod(p.paymentMethod)}', style: const TextStyle(fontSize: 8.1, color: AppColors.muted)),
                ),
            ],
          ]),
        ),
      ],
    );
  }
}

class _MiniValue extends StatelessWidget {
  const _MiniValue({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 7.7, color: AppColors.muted)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900)),
        ],
      );
}

bool _sameMonth(DateTime a, DateTime b) => a.year == b.year && a.month == b.month;
String _date(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
String _monthLabel(AppStrings s, DateTime d) {
  const ar = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
  const en = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  return '${s.controller.isArabic ? ar[d.month - 1] : en[d.month - 1]} ${d.year}';
}
