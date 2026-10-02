import 'package:flutter/material.dart';
import 'permissions.dart';

enum AppLanguage { ar, en }
enum UserRole { owner, manager, accountant, cashier, inventory, general }

class AppController extends ChangeNotifier {
  AppLanguage language = AppLanguage.ar;
  UserRole? role;
  String currentUserName = '';
  String? employeeId;
  bool managementAuthenticated = false;

  bool get isArabic => language == AppLanguage.ar;
  bool get canAccessManagement => managementAuthenticated &&
      (role == UserRole.owner || role == UserRole.manager || role == UserRole.accountant);

  void setLanguage(AppLanguage value) {
    if (language == value) return;
    language = value;
    notifyListeners();
  }

  void toggleLanguage() {
    language = isArabic ? AppLanguage.en : AppLanguage.ar;
    notifyListeners();
  }

  void signIn(
    UserRole value, {
    String name = '',
    String? id,
    bool management = false,
  }) {
    role = value;
    currentUserName = name;
    employeeId = id;
    managementAuthenticated = management;
    notifyListeners();
  }

  void signOut() {
    role = null;
    currentUserName = '';
    employeeId = null;
    managementAuthenticated = false;
    notifyListeners();
  }

  bool can(Permission permission) => permissionsFor(role).contains(permission);

  Set<Permission> permissionsFor(UserRole? userRole) {
    switch (userRole) {
      case UserRole.owner:
        return Permission.values.toSet();
      case UserRole.manager:
        return {
          Permission.accessManagement,
          Permission.viewDashboard,
          Permission.openPos,
          Permission.viewSales,
          Permission.returnSales,
          Permission.voidSales,
          Permission.discountSale,
          Permission.viewProfit,
          Permission.manageProducts,
          Permission.manageInventory,
          Permission.receivePurchases,
          Permission.recordDamage,
          Permission.stockCount,
          Permission.stockTransfer,
          Permission.manageCustomers,
          Permission.manageSuppliers,
          Permission.manageEmployees,
          Permission.viewPayroll,
          Permission.managePayroll,
          Permission.manageAttendance,
          Permission.viewReports,
          Permission.viewSubscription,
          Permission.manageSettings,
        };
      case UserRole.accountant:
        return {
          Permission.accessManagement,
          Permission.viewDashboard,
          Permission.viewSales,
          Permission.viewCost,
          Permission.viewProfit,
          Permission.manageSuppliers,
          Permission.viewAccounting,
          Permission.manageAccounting,
          Permission.manageAssets,
          Permission.viewPayroll,
          Permission.managePayroll,
          Permission.manageAttendance,
          Permission.viewReports,
          Permission.viewSubscription,
        };
      case UserRole.cashier:
        return {
          Permission.openPos,
          Permission.viewSales,
          Permission.returnSales,
          Permission.discountSale,
        };
      case UserRole.inventory:
        return {
          Permission.manageInventory,
          Permission.receivePurchases,
          Permission.recordDamage,
          Permission.stockCount,
          Permission.stockTransfer,
        };
      case UserRole.general:
      case null:
        return {};
    }
  }
}

class AppScope extends InheritedNotifier<AppController> {
  const AppScope({
    super.key,
    required AppController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found in context');
    return scope!.notifier!;
  }
}
