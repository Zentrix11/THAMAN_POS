import 'package:flutter/material.dart';
import '../../app/app_theme.dart';
import '../../core/app_controller.dart';
import '../../core/app_strings.dart';
import 'management_shell.dart';
import 'sections/accounting_assets_section.dart';
import 'sections/attendance_section.dart';
import 'sections/customers_suppliers_section.dart';
import 'sections/employees_section.dart';
import 'sections/payroll_section.dart';
import 'sections/financial_summary_section.dart';
import 'sections/inventory_section.dart';
import 'sections/kpi_details_section.dart';
import 'sections/products_section.dart';
import 'sections/purchases_section.dart';
import 'sections/reports_section.dart';
import 'sections/sales_section.dart';
import 'sections/subscription_section.dart';
import 'sections/offers_plans_section.dart';
import 'sections/settings_section.dart';
import 'sections/tasks_section.dart';
import 'sections/communications_section.dart';
import 'sections/restock_requests_section.dart';
import 'sections/developer_section.dart';

class SectionPage extends StatelessWidget {
  const SectionPage({super.key, required this.section, required this.onBack});
  final ManagementSection section;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings(AppScope.of(context));
    final meta = _meta(s, section);
    return SingleChildScrollView(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 700 ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(meta.$1, style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w900, letterSpacing: -.7)), const SizedBox(height: 5), Text(meta.$2, style: const TextStyle(fontSize: 10.3, color: AppColors.muted, height: 1.5))])),
            if (MediaQuery.sizeOf(context).width > 560) OutlinedButton.icon(onPressed: onBack, icon: const Icon(Icons.space_dashboard_outlined, size: 17), label: Text(s.text('النظرة العامة', 'Overview'))),
          ]),
          const SizedBox(height: 16),
          _body(section, s),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  Widget _body(ManagementSection section, AppStrings s) {
    switch (section) {
      case ManagementSection.sales:
        return SalesSection(s: s);
      case ManagementSection.products:
        return ProductsSection(s: s);
      case ManagementSection.inventory:
        return InventorySection(s: s);
      case ManagementSection.purchases:
        return PurchasesSection(s: s);
      case ManagementSection.customers:
        return CustomersSection(s: s);
      case ManagementSection.suppliers:
        return SuppliersSection(s: s);
      case ManagementSection.employees:
        return EmployeesSection(s: s);
      case ManagementSection.payroll:
        return PayrollSection(s: s);
      case ManagementSection.attendance:
        return AttendanceSection(s: s);
      case ManagementSection.tasks:
        return TasksSection(s: s);
      case ManagementSection.messages:
        return CommunicationsSection(s: s);
      case ManagementSection.restockRequests:
        return RestockRequestsSection(s: s);
      case ManagementSection.financialSummary:
        return FinancialSummarySection(s: s);
      case ManagementSection.accounting:
        return AccountingSection(s: s);
      case ManagementSection.assets:
        return AssetsSection(s: s);
      case ManagementSection.reports:
        return ReportsSection(s: s);
      case ManagementSection.offersPlans:
        return OffersPlansSection(s: s);
      case ManagementSection.subscription:
        return SubscriptionSection(s: s);
      case ManagementSection.settings:
        return SettingsSection(s: s);
      case ManagementSection.developer:
        return DeveloperSection(s: s);
      case ManagementSection.heldSales:
        return HeldSalesSection(s: s);
      case ManagementSection.returns:
        return ReturnsSection(s: s);
      case ManagementSection.stockAlerts:
        return StockAlertsSection(s: s);
      case ManagementSection.netSalesDetails:
        return KpiDetailSection(s: s, type: KpiDetailType.netSales);
      case ManagementSection.profitDetails:
        return KpiDetailSection(s: s, type: KpiDetailType.profit);
      case ManagementSection.averageTicketDetails:
        return KpiDetailSection(s: s, type: KpiDetailType.averageTicket);
      case ManagementSection.invoiceDetails:
        return KpiDetailSection(s: s, type: KpiDetailType.invoices);
      case ManagementSection.overview:
        return const SizedBox.shrink();
    }
  }
}

(String, String) _meta(AppStrings s, ManagementSection section) => switch (section) {
      ManagementSection.sales => (s.text('المبيعات والفواتير', 'Sales & invoices'), s.text('بحث وتفاصيل الفواتير والكاشير والعميل وطرق الدفع.', 'Search and inspect invoices, cashier, customer and payment details.')),
      ManagementSection.products => (s.text('المنتجات', 'Products'), s.text('بحث الأصناف وملاحظات موجهة للمخزون أو الشراء.', 'Search products and send notes to inventory or purchasing staff.')),
      ManagementSection.inventory => (s.text('المخزون', 'Inventory'), s.text('سجل حركة كامل مع التاريخ والمنفذ والمرجع والجرد.', 'Full movement ledger with date, actor, reference and stock counts.')),
      ManagementSection.purchases => (s.text('المشتريات والاستلام', 'Purchases & receiving'), s.text('سجل المشتريات يحفظ المورد والأصناف والكميات والقيمة وبيانات المستلم عند الحاجة.', 'Purchases keep supplier, items, quantities, value and receiver details when applicable.')),
      ManagementSection.customers => (s.text('العملاء', 'Customers'), s.text('بحث بالاسم أو الهاتف أو رقم الحساب مع سجل الفواتير.', 'Search by name, phone or account number with invoice history.')),
      ManagementSection.suppliers => (s.text('الموردون', 'Suppliers'), s.text('ملخص الموردين والمشتريات المستلمة منهم.', 'Supplier summary and received purchases.')),
      ManagementSection.employees => (s.text('الموظفون', 'Employees'), s.text('بحث، تعديل الاسم والدوام والإجازات والمهام وتفعيل أو إنهاء الخدمة.', 'Search, rename, schedule, leave, assign tasks and activate/terminate staff.')),
      ManagementSection.payroll => (s.text('الرواتب', 'Payroll'), s.text('رواتب الموظفين، موعد القبض، حالة الصرف وربط الرواتب بالمصاريف والقيود المحاسبية.', 'Employee salaries, pay dates, payment status and automatic expense/accounting integration.')),
      ManagementSection.attendance => (s.text('الحضور والانصراف', 'Attendance'), s.text('بيانات حقيقية من ضغط الموظفين على تسجيل الحضور والانصراف.', 'Live records created by employees clocking in and out.')),
      ManagementSection.tasks => (s.text('إدارة المهام', 'Task management'), s.text('إنشاء مهام للموظفين ومتابعة لم تبدأ / قيد التنفيذ / مكتملة ومتأخرة.', 'Assign tasks and track pending, in-progress, completed and overdue work.')),
      ManagementSection.messages => (s.text('الرسائل الداخلية', 'Internal messages'), s.text('إرسال رسائل لكل الموظفين أو المخزون أو موظف محدد ومتابعة الردود.', 'Broadcast to staff, inventory or a specific employee and track replies.')),
      ManagementSection.restockRequests => (s.text('طلبات إعادة التوريد', 'Restock requests'), s.text('إنشاء طلبات بضاعة بسبب النقص ومتابعتها من الطلب حتى الاستلام.', 'Create shortage-driven restock requests and track them through receiving.')),
      ManagementSection.financialSummary => (s.text('الملخص المالي', 'Financial summary'), s.text('ما بعته، ما قبضته، ما لك عند العملاء، ما عليك للموردين، المصروفات والربح أو الخسارة.', 'Sales, collections, receivables, supplier payables, expenses and profit or loss.')),
      ManagementSection.accounting => (s.text('المحاسبة', 'Accounting'), s.text('ملخص تشغيلي مبني على المبيعات والمرتجعات والمشتريات.', 'Operational summary calculated from sales, returns and purchases.')),
      ManagementSection.assets => (s.text('الأصول', 'Assets'), s.text('سجل الأصول مع الإهلاك والقيمة الدفترية.', 'Asset register with depreciation and book value.')),
      ManagementSection.reports => (s.text('التقارير', 'Reports'), s.text('تقارير محسوبة فعليًا من بيانات النظام مع فلاتر زمنية.', 'Reports calculated from system data with date filters.')),
      ManagementSection.offersPlans => (s.text('العروض والباقات', 'Offers & plans'), s.text('شاهد باقات وعروض THAMAN واطلب التجديد أو تغيير الباقة مباشرة من إدارة THAMAN.', 'Browse THAMAN plans and offers and request renewal or a plan change directly from THAMAN administration.')),
      ManagementSection.subscription => (s.text('الاشتراك والباقة', 'Subscription & plan'), s.text('تفاصيل باقة THAMAN الحالية، المدة المتبقية، حالة الاشتراك والأجهزة المرتبطة.', 'Current THAMAN plan, time remaining, subscription status and linked devices.')),
      ManagementSection.settings => (s.text('الإعدادات', 'Settings'), s.text('إعدادات متجر وتشغيل قابلة للتعديل والحفظ.', 'Editable and persisted store and operational settings.')),
      ManagementSection.developer => (s.text('مطور النظام', 'System developer'), s.text('Zentrix وفريق تطوير THAMAN وبيانات التواصل والدعم.', 'Zentrix, the THAMAN development team, contact and support information.')),
      ManagementSection.heldSales => (s.text('الفواتير المعلقة', 'Held sales'), s.text('تفاصيل السلة والكاشير والعميل ووقت التعليق.', 'Cart, cashier, customer and hold-time details.')),
      ManagementSection.returns => (s.text('المرتجعات', 'Returns'), s.text('كل مرتجع مربوط بفاتورته الأصلية ومنفذ العملية.', 'Every return is linked to its original invoice and operator.')),
      ManagementSection.stockAlerts => (s.text('تنبيهات المخزون', 'Stock alerts'), s.text('الأصناف التي وصلت إلى حد إعادة الطلب وملاحظاتها.', 'Items at reorder threshold with related notes.')),
      ManagementSection.netSalesDetails => (s.text('تفاصيل صافي المبيعات', 'Net sales details'), s.text('تفكيك الرقم إلى مبيعات ومرتجعات وفواتير ومساهمات الموظفين.', 'Break down net sales into invoices, returns and employee contribution.')),
      ManagementSection.profitDetails => (s.text('تحليل الربح التقديري', 'Estimated profit analysis'), s.text('صافي المبيعات ناقص تكلفة البضاعة التقديرية مع تفاصيل الأصناف.', 'Net sales minus estimated product cost with item contribution.')),
      ManagementSection.averageTicketDetails => (s.text('تحليل متوسط السلة', 'Average ticket analysis'), s.text('توزيع أحجام الفواتير وأعلى وأدنى ومتوسط قيمة الفاتورة.', 'Distribution of invoice size with high, low and average ticket values.')),
      ManagementSection.invoiceDetails => (s.text('سجل الفواتير', 'Invoice register'), s.text('كل الفواتير التسلسلية مع الموظف والعميل والوقت والقيمة.', 'All sequential invoices with employee, customer, time and value.')),
      ManagementSection.overview => (s.text('نظرة عامة', 'Overview'), ''),
    };
