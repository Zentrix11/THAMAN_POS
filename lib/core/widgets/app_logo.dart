import 'package:flutter/material.dart';
import '../../app/app_theme.dart';

class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.compact = false,
    this.onDark = false,
  });

  final bool compact;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 38 : 44,
          height: compact ? 38 : 44,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: onDark ? Colors.white.withValues(alpha: .12) : AppColors.border,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset('assets/thaman-mark.png', fit: BoxFit.cover),
          ),
        ),
        if (!compact) ...[
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'THAMAN',
                style: TextStyle(
                  color: onDark ? Colors.white : AppColors.text,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  letterSpacing: 1.5,
                ),
              ),
              Text(
                'POS',
                style: TextStyle(
                  color: onDark ? const Color(0xFF9EC0B8) : AppColors.muted,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
