import 'app_controller.dart';

class AppStrings {
  AppStrings(this.controller);
  final AppController controller;

  String text(String ar, String en) => controller.isArabic ? ar : en;

  String role(UserRole role) {
    return switch (role) {
      UserRole.owner => text('المالك', 'Owner'),
      UserRole.manager => text('المدير', 'Manager'),
      UserRole.accountant => text('المحاسب', 'Accountant'),
      UserRole.cashier => text('الكاشير', 'Cashier'),
      UserRole.inventory => text('موظف المخزن', 'Warehouse staff'),
      UserRole.general => text('موظف', 'Employee'),
    };
  }

  String roleKey(String value) {
    return switch (value.trim().toLowerCase()) {
      'owner' => text('المالك', 'Owner'),
      'manager' => text('المدير', 'Manager'),
      'accountant' => text('المحاسب', 'Accountant'),
      'cashier' => text('الكاشير', 'Cashier'),
      'inventory' => text('موظف المخزن', 'Warehouse staff'),
      'general' => text('موظف', 'Employee'),
      _ => value,
    };
  }

  String paymentMethod(String value) {
    return switch (value.trim().toLowerCase()) {
      'cash' => text('نقدي', 'Cash'),
      'card' => text('بطاقة', 'Card'),
      'wallet' => text('محفظة', 'Wallet'),
      'bank' => text('بنك', 'Bank'),
      'bank transfer' || 'transfer' => text('تحويل بنكي', 'Bank transfer'),
      'debt' || 'credit' => text('آجل', 'Credit'),
      _ => value,
    };
  }


  String expenseCategory(String value) {
    return switch (value.trim().toLowerCase()) {
      'operations' || 'operation' => text('تشغيل', 'Operations'),
      'utilities' => text('مرافق', 'Utilities'),
      'transport' || 'transportation' => text('نقل ومواصلات', 'Transport'),
      'maintenance' => text('صيانة', 'Maintenance'),
      'marketing' => text('تسويق', 'Marketing'),
      'salaries' || 'salary' => text('رواتب', 'Salaries'),
      'assets' || 'asset' => text('أصول', 'Assets'),
      'purchases' || 'purchase' => text('مشتريات', 'Purchases'),
      'rent' => text('إيجار', 'Rent'),
      'general' || 'other' => text('أخرى', 'Other'),
      _ => value,
    };
  }

  String assetCategory(String value) {
    return switch (value.trim().toLowerCase()) {
      'equipment' => text('معدات', 'Equipment'),
      'furniture' => text('أثاث', 'Furniture'),
      'vehicle' || 'vehicles' => text('مركبات', 'Vehicles'),
      'technology' || 'electronics' => text('تقنية وإلكترونيات', 'Technology & electronics'),
      'property' => text('عقار', 'Property'),
      _ => value,
    };
  }

  String sourceType(String value) {
    return switch (value.trim().toLowerCase()) {
      'salary' => text('راتب', 'Salary'),
      'purchase' => text('شراء', 'Purchase'),
      'asset' => text('أصل', 'Asset'),
      'employee_advance' => text('سلفة موظف', 'Employee advance'),
      'expense' => text('مصروف', 'Expense'),
      _ => value,
    };
  }

  String movementType(String value) {
    return switch (value.trim().toLowerCase()) {
      'sale' => text('بيع', 'Sale'),
      'return' => text('مرتجع', 'Return'),
      'receive' || 'receiving' => text('استلام', 'Receiving'),
      'purchase' => text('شراء', 'Purchase'),
      'damage' => text('تالف', 'Damage'),
      'transfer' => text('نقل', 'Transfer'),
      'void' => text('إلغاء فاتورة', 'Invoice void'),
      'count' || 'stock_count' || 'count_adjustment' => text('تسوية جرد', 'Stock-count adjustment'),
      'adjustment' => text('تسوية مخزون', 'Stock adjustment'),
      _ => value,
    };
  }

  String status(String value) {
    return switch (value.trim().toLowerCase()) {
      'pending' => text('قيد الانتظار', 'Pending'),
      'in_progress' || 'in progress' => text('قيد التنفيذ', 'In progress'),
      'completed' => text('مكتمل', 'Completed'),
      'open' => text('مفتوح', 'Open'),
      'closed' => text('مغلق', 'Closed'),
      'requested' => text('مطلوب', 'Requested'),
      'approved' => text('معتمد', 'Approved'),
      'ordered' => text('تم الطلب', 'Ordered'),
      'received' => text('تم الاستلام', 'Received'),
      'cancelled' || 'canceled' => text('ملغي', 'Cancelled'),
      'rejected' => text('مرفوض', 'Rejected'),
      _ => value,
    };
  }

  String priority(String value) {
    return switch (value.trim().toLowerCase()) {
      'low' => text('منخفضة', 'Low'),
      'medium' => text('متوسطة', 'Medium'),
      'high' => text('عالية', 'High'),
      'urgent' => text('عاجلة', 'Urgent'),
      _ => value,
    };
  }

  String unit(String value) {
    return switch (value.trim().toLowerCase()) {
      'piece' || 'pcs' || 'pc' => text('قطعة', 'Piece'),
      'carton' => text('كرتونة', 'Carton'),
      'box' => text('صندوق', 'Box'),
      'pack' => text('عبوة', 'Pack'),
      'kg' || 'kilogram' => text('كغم', 'kg'),
      'g' || 'gram' => text('غرام', 'g'),
      'liter' || 'litre' || 'l' => text('لتر', 'L'),
      'bottle' => text('زجاجة', 'Bottle'),
      _ => value,
    };
  }
}
