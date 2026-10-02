import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../app/app_theme.dart';

class BrandPattern extends StatelessWidget {
  const BrandPattern({
    super.key,
    required this.child,
    this.dark = false,
    this.padding = EdgeInsets.zero,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
  });

  final Widget child;
  final bool dark;
  final EdgeInsets padding;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _ThamanPatternPainter(dark: dark))),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

class _ThamanPatternPainter extends CustomPainter {
  const _ThamanPatternPainter({required this.dark});
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final green = Paint()
      ..color = (dark ? Colors.white : AppColors.primary).withValues(alpha: dark ? .055 : .045)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final copper = Paint()
      ..color = AppColors.accent.withValues(alpha: dark ? .12 : .08)
      ..style = PaintingStyle.fill;

    const step = 150.0;
    for (double x = -40; x < size.width + step; x += step) {
      for (double y = -30; y < size.height + step; y += step) {
        final center = Offset(x, y);
        final rect = Rect.fromCenter(center: center, width: 82, height: 82);
        canvas.drawArc(rect, math.pi * .2, math.pi * .72, false, green);
        canvas.drawCircle(center.translate(22, -24), 3.1, copper);
        canvas.drawCircle(center.translate(34, -19), 3.1, copper);
        canvas.drawCircle(center.translate(46, -13), 3.1, copper);
        final bar1 = RRect.fromRectAndRadius(Rect.fromLTWH(x - 22, y + 12, 9, 20), const Radius.circular(2));
        final bar2 = RRect.fromRectAndRadius(Rect.fromLTWH(x - 8, y + 2, 9, 30), const Radius.circular(2));
        final bar3 = RRect.fromRectAndRadius(Rect.fromLTWH(x + 6, y - 10, 9, 42), const Radius.circular(2));
        canvas.drawRRect(bar1, green);
        canvas.drawRRect(bar2, green);
        canvas.drawRRect(bar3, green);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ThamanPatternPainter oldDelegate) => oldDelegate.dark != dark;
}
