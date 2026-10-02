import 'package:flutter/material.dart';
import '../../app/app_theme.dart';
import '../app_controller.dart';

class LanguageSwitch extends StatelessWidget {
  const LanguageSwitch({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LanguageOption(
            label: 'ع',
            selected: controller.isArabic,
            onTap: () => controller.setLanguage(AppLanguage.ar),
            compact: compact,
          ),
          _LanguageOption(
            label: 'EN',
            selected: !controller.isArabic,
            onTap: () => controller.setLanguage(AppLanguage.en),
            compact: compact,
          ),
        ],
      ),
    );
  }
}

class _LanguageOption extends StatelessWidget {
  const _LanguageOption({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.compact,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 6 : 7,
        ),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x120F4B43),
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.primary : AppColors.muted,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
