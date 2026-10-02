import 'package:flutter/material.dart';
import '../../../app/app_theme.dart';
import '../../../core/app_strings.dart';
import '../../../core/widgets/surface_card.dart';
import '../../../core/time_format.dart';

class ManagementMetric {
  const ManagementMetric(this.label, this.value, this.icon, this.color, {this.onTap});
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
}

class ManagementMetricsGrid extends StatelessWidget {
  const ManagementMetricsGrid({super.key, required this.items});
  final List<ManagementMetric> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxCols = items.length > 4 ? 4 : items.length;
        final cols = constraints.maxWidth >= 1050 ? maxCols : constraints.maxWidth >= 650 ? 2 : 1;
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: cols,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: cols == 1 ? 3.6 : 2.25,
          children: items.map((metric) {
            return SurfaceCard(
              child: InkWell(
                onTap: metric.onTap,
                borderRadius: BorderRadius.circular(14),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(color: metric.color.withValues(alpha: .09), borderRadius: BorderRadius.circular(13)),
                      child: Icon(metric.icon, color: metric.color, size: 20),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(metric.value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 2),
                          Text(metric.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 8.8, color: AppColors.muted, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                    if (metric.onTap != null) const Icon(Icons.arrow_outward_rounded, size: 15, color: AppColors.muted),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class SectionCardHeader extends StatelessWidget {
  const SectionCardHeader({super.key, required this.title, this.subtitle = '', this.trailing});
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(17),
      child: LayoutBuilder(
        builder: (context, c) {
          final text = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(subtitle, style: const TextStyle(fontSize: 8.7, color: AppColors.muted)),
              ],
            ],
          );
          if (trailing == null) return text;
          if (c.maxWidth < 640) {
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [text, const SizedBox(height: 10), trailing!]);
          }
          return Row(children: [Expanded(child: text), const SizedBox(width: 12), trailing!]);
        },
      ),
    );
  }
}

class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.controller, required this.hint, required this.onChanged, this.width});
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded, size: 18), hintText: hint, isDense: true),
    );
    if (MediaQuery.sizeOf(context).width < 640) return field;
    return SizedBox(width: width, child: field);
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(color: color.withValues(alpha: .09), borderRadius: BorderRadius.circular(30)),
        child: Text(label, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: color)),
      );
}

class EmptyPanel extends StatelessWidget {
  const EmptyPanel({super.key, required this.message, this.icon = Icons.inbox_outlined});
  final String message;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(34),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: AppColors.muted, size: 28),
            const SizedBox(height: 8),
            Text(message, style: const TextStyle(fontSize: 9.5, color: AppColors.muted)),
          ]),
        ),
      );
}

class DetailLine extends StatelessWidget {
  const DetailLine({super.key, required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 130, child: Text(label, style: const TextStyle(fontSize: 8.8, color: AppColors.muted))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 9.4, fontWeight: FontWeight.w800))),
        ]),
      );
}

String formatTime(DateTime date) => formatHour12(date);
String formatDate(DateTime date) => '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
String formatDateTime(DateTime date) => '${formatDate(date)} • ${formatTime(date)}';
String weekdayName(DateTime date, {bool arabic = true}) {
  const ar = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
  const en = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  final index = date.weekday - 1;
  return arabic ? ar[index] : en[index];
}
String formatPurchaseWhen(DateTime date, {bool arabic = true}) =>
    '${weekdayName(date, arabic: arabic)} • ${formatDateTime(date)}';
String formatDuration(Duration d) => '${d.inHours}h ${d.inMinutes.remainder(60)}m';

String formatReadableMinutes(AppStrings s, int totalMinutes) {
  final safeMinutes = totalMinutes < 0 ? 0 : totalMinutes;
  final hours = safeMinutes ~/ 60;
  final minutes = safeMinutes.remainder(60);

  if (!s.controller.isArabic) {
    final parts = <String>[];
    if (hours > 0) parts.add('$hours ${hours == 1 ? 'hour' : 'hours'}');
    if (minutes > 0 || parts.isEmpty) {
      parts.add('$minutes ${minutes == 1 ? 'minute' : 'minutes'}');
    }
    return parts.join(' and ');
  }

  String hourLabel(int value) {
    if (value == 1) return 'ساعة';
    if (value == 2) return 'ساعتين';
    if (value >= 3 && value <= 10) return '$value ساعات';
    return '$value ساعة';
  }

  String minuteLabel(int value) {
    if (value == 1) return 'دقيقة';
    if (value == 2) return 'دقيقتين';
    if (value >= 3 && value <= 10) return '$value دقائق';
    return '$value دقيقة';
  }

  final parts = <String>[];
  if (hours > 0) parts.add(hourLabel(hours));
  if (minutes > 0 || parts.isEmpty) parts.add(minuteLabel(minutes));
  return parts.join(' و');
}

String taskStatusLabel(AppStrings s, String status) => switch (status) {
      'completed' => s.text('مكتملة', 'Completed'),
      'in_progress' => s.text('قيد التنفيذ', 'In progress'),
      _ => s.text('لم تبدأ', 'Pending'),
    };

Color taskStatusColor(String status, {bool overdue = false}) {
  if (status == 'completed') return AppColors.success;
  if (overdue) return AppColors.danger;
  if (status == 'in_progress') return AppColors.blue;
  return AppColors.accent;
}
