import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/app_theme.dart';
import '../../../core/app_strings.dart';

class DeveloperSection extends StatelessWidget {
  const DeveloperSection({super.key, required this.s});
  final AppStrings s;

  static const developer = 'عمر نضال البحطيطي';
  static const website = 'https://zentrix.zentrixtech.workers.dev/';
  static const whatsapp = '+970 569 477 784';
  static const email = 'albhtytymr6@gmail.com';

  Future<void> _open(BuildContext context, Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.text('تعذر فتح الرابط.', 'Could not open the link.'))),
      );
    }
  }

  Future<void> _copy(BuildContext context, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.text('تم نسخ البريد.', 'Email copied.'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final compact = constraints.maxWidth < 900;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HeroSlide(
              compact: compact,
              s: s,
              onWebsite: () => _open(context, Uri.parse(website)),
              onWhatsapp: () => _open(context, Uri.parse('https://wa.me/970569477784')),
            ),
            const SizedBox(height: 18),
            _StatementStrip(s: s),
            const SizedBox(height: 18),
            _ContactPanel(
              s: s,
              onWebsite: () => _open(context, Uri.parse(website)),
              onWhatsapp: () => _open(context, Uri.parse('https://wa.me/970569477784')),
              onEmail: () => _open(context, Uri(scheme: 'mailto', path: email)),
              onCopyEmail: () => _copy(context, email),
            ),
          ],
        );
      },
    );
  }
}

class _HeroSlide extends StatelessWidget {
  const _HeroSlide({
    required this.compact,
    required this.s,
    required this.onWebsite,
    required this.onWhatsapp,
  });

  final bool compact;
  final AppStrings s;
  final VoidCallback onWebsite;
  final VoidCallback onWhatsapp;

  @override
  Widget build(BuildContext context) {
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Image.asset('assets/zentrix_logo.png', height: 38, fit: BoxFit.contain),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .13),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withValues(alpha: .20)),
              ),
              child: const Text(
                'ZENTRIX • THAMAN',
                style: TextStyle(fontSize: 8.6, fontWeight: FontWeight.w900, color: Colors.white),
              ),
            ),
          ],
        ),
        const SizedBox(height: 34),
        Text(
          s.text('نصنع نظامًا يعمل\nمعك كل يوم.', 'Built to work\nwith you every day.'),
          style: TextStyle(
            fontSize: compact ? 28 : 38,
            height: 1.08,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: -.6,
          ),
        ),
        const SizedBox(height: 14),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Text(
            s.text(
              'ثمن يجمع المبيعات والمخزون والمشتريات والموظفين والمالية في تجربة واحدة واضحة وسريعة، صُممت لتبقى بسيطة مهما كبر العمل.',
              'THAMAN brings sales, inventory, purchasing, staff and finance into one clear, fast experience designed to stay simple as the business grows.',
            ),
            style: TextStyle(fontSize: compact ? 10 : 11, height: 1.75, color: Colors.white.withValues(alpha: .82)),
          ),
        ),
        const SizedBox(height: 26),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.primary),
              onPressed: onWebsite,
              icon: const Icon(Icons.north_east_rounded, size: 17),
              label: Text(s.text('زيارة الموقع', 'Visit website')),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: BorderSide(color: Colors.white.withValues(alpha: .45))),
              onPressed: onWhatsapp,
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
              label: Text(s.text('تواصل عبر واتساب', 'WhatsApp')),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _GlassTag(Icons.point_of_sale_rounded, s.text('مبيعات', 'Sales')),
            _GlassTag(Icons.inventory_2_outlined, s.text('مخزون', 'Inventory')),
            _GlassTag(Icons.groups_2_outlined, s.text('فريق', 'Team')),
            _GlassTag(Icons.account_balance_wallet_outlined, s.text('مالية', 'Finance')),
          ],
        ),
      ],
    );

    final profile = Container(
      constraints: const BoxConstraints(maxWidth: 380),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: .18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(23),
            child: AspectRatio(
              aspectRatio: 1.06,
              child: Image.asset('assets/omar_nidal_albahtiti.png', fit: BoxFit.cover, alignment: Alignment.topCenter),
            ),
          ),
          const SizedBox(height: 16),
          const Text(DeveloperSection.developer, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white)),
          const SizedBox(height: 5),
          Text(
            s.text('تصميم وتطوير النظام', 'System design & development'),
            style: TextStyle(fontSize: 9.5, color: Colors.white.withValues(alpha: .72), fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(Icons.location_on_outlined, size: 15, color: Colors.white.withValues(alpha: .72)),
              const SizedBox(width: 5),
              Expanded(child: Text(s.text('فلسطين - غزة', 'Palestine - Gaza'), style: TextStyle(fontSize: 8.8, color: Colors.white.withValues(alpha: .72)))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: .12), borderRadius: BorderRadius.circular(999)),
                child: const Text('V9.13', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, color: Colors.white)),
              ),
            ],
          ),
        ],
      ),
    );

    return Container(
      padding: EdgeInsets.all(compact ? 22 : 34),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF0B352F), Color(0xFF155B4E), Color(0xFF0F766E)],
        ),
        borderRadius: BorderRadius.circular(34),
        boxShadow: const [BoxShadow(color: Color(0x24000000), blurRadius: 34, offset: Offset(0, 18))],
      ),
      child: compact
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [copy, const SizedBox(height: 28), profile])
          : Row(crossAxisAlignment: CrossAxisAlignment.center, children: [Expanded(flex: 6, child: copy), const SizedBox(width: 38), Expanded(flex: 4, child: profile)]),
    );
  }
}

class _GlassTag extends StatelessWidget {
  const _GlassTag(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: .14)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 8.3, color: Colors.white, fontWeight: FontWeight.w800)),
        ]),
      );
}

class _StatementStrip extends StatelessWidget {
  const _StatementStrip({required this.s});
  final AppStrings s;

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.bolt_rounded, s.text('أسرع في التشغيل', 'Faster to operate'), s.text('خطوات أقل في المهام اليومية.', 'Fewer steps in daily work.')),
      (Icons.sync_alt_rounded, s.text('بيانات مترابطة', 'Connected data'), s.text('كل حركة تنعكس في مكانها الصحيح.', 'Every movement reaches the right place.')),
      (Icons.auto_graph_rounded, s.text('رؤية أوضح', 'Clearer insight'), s.text('أرقام وتقارير تساعد على القرار.', 'Numbers and reports that support decisions.')),
    ];
    return LayoutBuilder(builder: (_, c) {
      final width = c.maxWidth >= 820 ? (c.maxWidth - 24) / 3 : c.maxWidth;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [for (final item in items) _StatementCard(width: width, icon: item.$1, title: item.$2, text: item.$3)],
      );
    });
  }
}

class _StatementCard extends StatelessWidget {
  const _StatementCard({required this.width, required this.icon, required this.title, required this.text});
  final double width;
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), border: Border.all(color: AppColors.border)),
          child: Row(children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: AppColors.primary)),
            const SizedBox(width: 13),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(text, style: const TextStyle(fontSize: 8.4, color: AppColors.muted, height: 1.5)),
            ])),
          ]),
        ),
      );
}

class _ContactPanel extends StatelessWidget {
  const _ContactPanel({required this.s, required this.onWebsite, required this.onWhatsapp, required this.onEmail, required this.onCopyEmail});
  final AppStrings s;
  final VoidCallback onWebsite;
  final VoidCallback onWhatsapp;
  final VoidCallback onEmail;
  final VoidCallback onCopyEmail;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _ContactData(Icons.language_rounded, s.text('الموقع الرسمي', 'Official website'), 'zentrix.zentrixtech.workers.dev', s.text('فتح الموقع', 'Open website'), onWebsite, null),
      _ContactData(Icons.chat_outlined, s.text('واتساب', 'WhatsApp'), DeveloperSection.whatsapp, s.text('بدء محادثة', 'Start chat'), onWhatsapp, null),
      _ContactData(Icons.alternate_email_rounded, s.text('البريد', 'Email'), DeveloperSection.email, s.text('إرسال بريد', 'Send email'), onEmail, onCopyEmail),
    ];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: const Color(0xFFF7F9F8), borderRadius: BorderRadius.circular(26), border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.text('ابقَ على تواصل', 'Stay connected'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
        const SizedBox(height: 5),
        Text(s.text('كل الروابط أدناه فعالة وتفتح مباشرة خارج التطبيق.', 'Every link below is active and opens directly outside the app.'), style: const TextStyle(fontSize: 8.8, color: AppColors.muted)),
        const SizedBox(height: 16),
        LayoutBuilder(builder: (_, c) {
          final width = c.maxWidth >= 900 ? (c.maxWidth - 24) / 3 : c.maxWidth >= 580 ? (c.maxWidth - 12) / 2 : c.maxWidth;
          return Wrap(spacing: 12, runSpacing: 12, children: [for (final card in cards) _ContactCard(width: width, data: card)]);
        }),
      ]),
    );
  }
}

class _ContactData {
  const _ContactData(this.icon, this.title, this.value, this.action, this.onTap, this.onSecondary);
  final IconData icon;
  final String title;
  final String value;
  final String action;
  final VoidCallback onTap;
  final VoidCallback? onSecondary;
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.width, required this.data});
  final double width;
  final _ContactData data;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(19),
          child: InkWell(
            borderRadius: BorderRadius.circular(19),
            onTap: data.onTap,
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(19)),
              child: Row(children: [
                Container(width: 41, height: 41, decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(13)), child: Icon(data.icon, color: AppColors.primary, size: 20)),
                const SizedBox(width: 11),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(data.title, style: const TextStyle(fontSize: 8.3, color: AppColors.muted)),
                  const SizedBox(height: 3),
                  Text(data.value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9.2, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 5),
                  Text(data.action, style: const TextStyle(fontSize: 8.2, color: AppColors.primary, fontWeight: FontWeight.w800)),
                ])),
                if (data.onSecondary != null) IconButton(onPressed: data.onSecondary, tooltip: 'Copy', icon: const Icon(Icons.copy_rounded, size: 16)),
                const Icon(Icons.arrow_outward_rounded, size: 16, color: AppColors.primary),
              ]),
            ),
          ),
        ),
      );
}
