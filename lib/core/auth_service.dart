import 'app_controller.dart';
import 'credential_hash.dart';
import '../data/app_data_store.dart';

class AuthResult {
  const AuthResult({
    required this.success,
    this.role,
    this.name = '',
    this.employeeId,
    this.messageAr = '',
    this.messageEn = '',
  });

  final bool success;
  final UserRole? role;
  final String name;
  final String? employeeId;
  final String messageAr;
  final String messageEn;
}

class AuthService {
  static AuthResult managementLogin({
    required String email,
    required String password,
    required String pin,
    required bool arabic,
  }) {
    final account = AppDataStore.instance.adminAccountByEmail(email);
    const requiresPin = true;
    if (account == null ||
        !account.active ||
        !CredentialHash.verify(password.trim(), account.password) ||
        (requiresPin && !CredentialHash.verify(pin.trim(), account.pin))) {
      return const AuthResult(
        success: false,
        messageAr: 'بيانات الدخول غير صحيحة. تحقق من البريد وكلمة المرور، وتحقق من رمز الإدارة PIN.',
        messageEn: 'Invalid credentials. Check the email and password; verify the management PIN as well.',
      );
    }
    final role = switch (account.roleKey) {
      'owner' => UserRole.owner,
      'manager' => UserRole.manager,
      'accountant' => UserRole.accountant,
      _ => null,
    };
    if (role == null) {
      return const AuthResult(
        success: false,
        messageAr: 'هذا الحساب لا يملك صلاحية دخول الإدارة.',
        messageEn: 'This account is not allowed to access management.',
      );
    }
    var upgraded = false;
    if (CredentialHash.needsUpgrade(account.password)) {
      account.password = CredentialHash.encode(password.trim());
      upgraded = true;
    }
    if (requiresPin && CredentialHash.needsUpgrade(account.pin)) {
      account.pin = CredentialHash.encode(pin.trim());
      upgraded = true;
    }
    if (upgraded) AppDataStore.instance.persistCredentialUpgrade();
    return AuthResult(success: true, role: role, name: arabic ? account.nameAr : account.nameEn);
  }

  static AuthResult staffLogin({
    required String employeeId,
    required String pin,
    required bool arabic,
  }) {
    final normalized = employeeId.trim().toUpperCase();
    final account = AppDataStore.instance.employeeByLoginId(normalized);
    if (account == null || !account.active || account.managementOnly || !CredentialHash.verify(pin.trim(), account.pin)) {
      return const AuthResult(
        success: false,
        messageAr: 'رقم الدخول أو PIN غير صحيح، أو أن الحساب غير نشط.',
        messageEn: 'Login ID or PIN is incorrect, or the account is inactive.',
      );
    }
    final role = switch (account.roleKey) {
      'cashier' => UserRole.cashier,
      'inventory' => UserRole.inventory,
      _ => UserRole.general,
    };
    if (CredentialHash.needsUpgrade(account.pin)) {
      account.pin = CredentialHash.encode(pin.trim());
      AppDataStore.instance.persistCredentialUpgrade();
    }
    return AuthResult(
      success: true,
      role: role,
      name: arabic ? account.nameAr : account.nameEn,
      employeeId: account.id,
    );
  }
}
