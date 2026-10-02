import 'package:flutter/material.dart';
import '../../app/app_theme.dart';
import '../../core/app_controller.dart';
import '../../core/app_strings.dart';
import '../../core/widgets/app_logo.dart';
import '../../core/widgets/brand_pattern.dart';
import '../../core/widgets/language_switch.dart';
import 'admin_login_screen.dart';
import 'staff_login_screen.dart';

class AccessScreen extends StatelessWidget {
  const AccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final s = AppStrings(controller);

    return Scaffold(
      body: SafeArea(
        child: BrandPattern(
          borderRadius: BorderRadius.zero,
          child: LayoutBuilder(
          builder: (context, constraints) {
          final mobile = constraints.maxWidth < AppBreakpoints.mobile;
          final card = Container(
            constraints: const BoxConstraints(maxWidth: 1180),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(mobile ? 0 : 30),
              border: Border.all(color: AppColors.border),
              boxShadow: mobile
                  ? null
                  : const [
                      BoxShadow(
                        color: Color(0x120B3E37),
                        blurRadius: 60,
                        offset: Offset(0, 24),
                      ),
                    ],
            ),
            clipBehavior: Clip.antiAlias,
            child: mobile
                ? Column(
                    children: [
                      SizedBox(height: constraints.maxHeight < 720 ? 230 : 300, child: _HeroPanel(s: s)),
                      Expanded(child: _AccessPanel(s: s)),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(flex: 11, child: _HeroPanel(s: s)),
                      Expanded(flex: 10, child: _AccessPanel(s: s)),
                    ],
                  ),
          );

          return Container(
            color: AppColors.background.withValues(alpha: .94),
            padding: EdgeInsets.all(mobile ? 0 : 28),
            alignment: Alignment.center,
            child: card,
          );
          },
          ),
        ),
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({required this.s});
  final AppStrings s;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(34),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF083A34), Color(0xFF0F574C)],
        ),
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _AccessHeroDecorationPainter(),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: AlignmentDirectional.topStart,
                  end: AlignmentDirectional.bottomEnd,
                  colors: [
                    AppColors.primaryStrong.withValues(alpha: .28),
                    AppColors.primaryStrong.withValues(alpha: .06),
                    const Color(0xFF0F574C).withValues(alpha: .22),
                  ],
                ),
              ),
            ),
          ),
          PositionedDirectional(
            end: -90,
            top: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: .06), width: 42),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppLogo(onDark: true),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white.withValues(alpha: .1)),
                ),
                child: Text(
                  s.text('نظام بيع وإدارة متكامل', 'Retail operations, simplified'),
                  style: const TextStyle(
                    color: Color(0xFFCAE0DA),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                s.text('تجارتك\nمحسوبة.', 'Your business.\nAccounted for.'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 44,
                  height: 1.08,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.5,
                ),
              ),
              const SizedBox(height: 15),
              Text(
                s.text(
                  'واجهة هادئة وسريعة للكاشير، وإدارة واضحة لصاحب المتجر.',
                  'A focused cashier experience and a clear management workspace.',
                ),
                style: const TextStyle(
                  color: Color(0xFFB9D2CC),
                  fontSize: 12,
                  height: 1.7,
                ),
              ),
              const Spacer(),
              Text(
                'THAMAN POS • 2026',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .45),
                  fontSize: 9,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccessPanel extends StatelessWidget {
  const _AccessPanel({required this.s});
  final AppStrings s;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(34),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 500),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Align(alignment: AlignmentDirectional.centerEnd, child: LanguageSwitch()),
            const SizedBox(height: 34),
            Text(
              s.text('اختر مساحة الدخول', 'Choose your workspace'),
              style: const TextStyle(
                fontSize: 29,
                fontWeight: FontWeight.w900,
                color: AppColors.text,
                letterSpacing: -.7,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              s.text(
                'كل مستخدم يصل فقط إلى الأدوات والصلاحيات المرتبطة بعمله.',
                'Each account only sees the tools and permissions assigned to its role.',
              ),
              style: const TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.6),
            ),
            const SizedBox(height: 22),
            _AccessTile(
              icon: Icons.admin_panel_settings_outlined,
              title: s.text('دخول الإدارة', 'Management login'),
              subtitle: s.text(
                'للمالك والمدير والمحاسب والحسابات الإدارية المخولة.',
                'For owners, managers, accountants and authorized management accounts.',
              ),
              emphasized: true,
              onTap: () => _open(context, const AdminLoginScreen()),
            ),
            const SizedBox(height: 12),
            _AccessTile(
              icon: Icons.badge_outlined,
              title: s.text('دخول الموظفين', 'Employee login'),
              subtitle: s.text(
                'للكاشير وموظفي المخزون وباقي فريق التشغيل.',
                'For cashiers, inventory staff and the operational team.',
              ),
              onTap: () => _open(context, const StaffLoginScreen()),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                const Icon(Icons.lock_outline_rounded, size: 14, color: AppColors.muted),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    s.text(
                      'الصلاحيات تُتحقق من الحساب نفسه، وليس من شاشة الدخول المختارة.',
                      'Permissions are validated by the account itself, not by the selected login screen.',
                    ),
                    style: const TextStyle(color: AppColors.muted, fontSize: 9.5, height: 1.5),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(_pageRoute(page));
  }
}

class _AccessTile extends StatefulWidget {
  const _AccessTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.emphasized = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool emphasized;

  @override
  State<_AccessTile> createState() => _AccessTileState();
}

class _AccessTileState extends State<_AccessTile> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        transform: Matrix4.translationValues(hover ? 3 : 0, 0, 0),
        decoration: BoxDecoration(
          color: hover ? AppColors.surfaceAlt : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: hover ? const Color(0xFFCFDCD7) : AppColors.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.all(17),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: widget.emphasized ? AppColors.primarySoft : AppColors.accentSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    widget.icon,
                    color: widget.emphasized ? AppColors.primary : AppColors.accent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                      const SizedBox(height: 5),
                      Text(
                        widget.subtitle,
                        style: const TextStyle(color: AppColors.muted, fontSize: 9.7, height: 1.55),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded, size: 18, color: AppColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


class _AccessHeroDecorationPainter extends CustomPainter {
  const _AccessHeroDecorationPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true
      ..color = const Color(0xFFC47A44).withValues(alpha: .20);
    final faint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true
      ..color = Colors.white.withValues(alpha: .055);
    final node = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true
      ..color = const Color(0xFFC47A44).withValues(alpha: .78);

    void pathFrom(List<Offset> points, Paint paint) {
      if (points.length < 2) return;
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (var i = 1; i < points.length; i++) {
        final a = points[i - 1];
        final b = points[i];
        final midX = (a.dx + b.dx) / 2;
        path.cubicTo(midX, a.dy, midX, b.dy, b.dx, b.dy);
      }
      canvas.drawPath(path, paint);
    }

    final w = size.width;
    final h = size.height;

    pathFrom([
      Offset(w * .04, h * .72),
      Offset(w * .18, h * .62),
      Offset(w * .30, h * .67),
      Offset(w * .44, h * .49),
      Offset(w * .57, h * .56),
      Offset(w * .70, h * .35),
      Offset(w * .84, h * .42),
      Offset(w * .96, h * .22),
    ], line);

    pathFrom([
      Offset(w * -.04, h * .30),
      Offset(w * .14, h * .18),
      Offset(w * .32, h * .28),
      Offset(w * .48, h * .17),
      Offset(w * .66, h * .25),
      Offset(w * .86, h * .11),
      Offset(w * 1.04, h * .20),
    ], faint);

    pathFrom([
      Offset(w * .02, h * .91),
      Offset(w * .22, h * .82),
      Offset(w * .41, h * .90),
      Offset(w * .62, h * .73),
      Offset(w * .82, h * .80),
      Offset(w * 1.04, h * .68),
    ], faint);

    final nodes = <Offset>[
      Offset(w * .18, h * .62),
      Offset(w * .44, h * .49),
      Offset(w * .57, h * .56),
      Offset(w * .70, h * .35),
      Offset(w * .84, h * .42),
      Offset(w * .96, h * .22),
    ];
    for (final point in nodes) {
      canvas.drawCircle(point, 4.2, node);
      canvas.drawCircle(
        point,
        8.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .8
          ..isAntiAlias = true
          ..color = const Color(0xFFC47A44).withValues(alpha: .16),
      );
    }

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..isAntiAlias = true
      ..color = Colors.white.withValues(alpha: .045);
    for (var i = 0; i < 4; i++) {
      final rect = Rect.fromCircle(
        center: Offset(w * (.18 + i * .25), h * (.18 + (i % 2) * .56)),
        radius: 70 + i * 20,
      );
      canvas.drawArc(rect, .2, 1.45, false, arcPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}


Route<void> _pageRoute(Widget page) {
  return PageRouteBuilder<void>(
    pageBuilder: (_, animation, __) => page,
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    transitionsBuilder: (_, animation, __, child) {
      final offset = Tween<Offset>(begin: const Offset(.04, 0), end: Offset.zero)
          .chain(CurveTween(curve: Curves.easeOutCubic));
      return FadeTransition(
        opacity: animation,
        child: SlideTransition(position: animation.drive(offset), child: child),
      );
    },
  );
}
