import 'package:flutter/material.dart';
import '../../app/app_theme.dart';
import '../../core/app_controller.dart';
import '../../core/app_strings.dart';
import '../../core/auth_service.dart';
import '../../core/widgets/app_logo.dart';
import '../../core/widgets/brand_pattern.dart';
import '../../core/widgets/language_switch.dart';
import '../pos/pos_screen.dart';
import '../staff/staff_home.dart';

class StaffLoginScreen extends StatefulWidget {
  const StaffLoginScreen({super.key});

  @override
  State<StaffLoginScreen> createState() => _StaffLoginScreenState();
}

class _StaffLoginScreenState extends State<StaffLoginScreen> {
  final employeeId = TextEditingController();
  final pin = TextEditingController();
  bool obscure = true;
  String? error;

  @override
  void dispose() {
    employeeId.dispose();
    pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final s = AppStrings(controller);

    return Scaffold(
      body: SafeArea(
        child: Stack(
        children: [
          Positioned.fill(
            child: BrandPattern(
              borderRadius: BorderRadius.zero,
              child: Container(color: AppColors.background.withValues(alpha: .96)),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Container(
                width: (MediaQuery.sizeOf(context).width - 32).clamp(0.0, 470.0).toDouble(),
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: AppColors.border),
                  boxShadow: const [BoxShadow(color: Color(0x12083A34), blurRadius: 50, offset: Offset(0, 22))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton.outlined(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: Icon(controller.isArabic ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded),
                        ),
                        const Spacer(),
                        const LanguageSwitch(),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Center(child: AppLogo()),
                    const SizedBox(height: 26),
                    Text(s.text('دخول الموظفين', 'Employee sign in'), style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    Text(
                      s.text('استخدم الرقم الوظيفي والـPIN. النظام يفتح مساحة العمل المسموحة لهذا الحساب تلقائيًا.', 'Use the employee ID and PIN. THAMAN opens the workspace assigned to that account automatically.'),
                      style: const TextStyle(color: AppColors.muted, fontSize: 10.5, height: 1.6),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: employeeId,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(labelText: s.text('الرقم الوظيفي', 'Employee ID'), prefixIcon: const Icon(Icons.badge_outlined, size: 18)),
                    ),
                    const SizedBox(height: 11),
                    TextField(
                      controller: pin,
                      obscureText: obscure,
                      maxLength: 4,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        counterText: '',
                        labelText: 'PIN',
                        prefixIcon: const Icon(Icons.password_rounded, size: 18),
                        suffixIcon: IconButton(onPressed: () => setState(() => obscure = !obscure), icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18)),
                      ),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 11),
                      Text(error!, style: const TextStyle(fontSize: 9.5, color: AppColors.danger, fontWeight: FontWeight.w700)),
                    ],
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(onPressed: _submit, icon: const Icon(Icons.arrow_forward_rounded, size: 18), label: Text(s.text('فتح مساحة العمل', 'Open workspace'))),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }

  void _submit() {
    final controller = AppScope.of(context);
    final result = AuthService.staffLogin(employeeId: employeeId.text, pin: pin.text, arabic: controller.isArabic);
    if (!result.success || result.role == null) {
      setState(() => error = controller.isArabic ? result.messageAr : result.messageEn);
      return;
    }
    controller.signIn(result.role!, name: result.name, id: result.employeeId, management: false);
    final page = result.role == UserRole.cashier ? const PosScreen() : const StaffHome();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => page),
      (route) => route.isFirst,
    );
  }
}
