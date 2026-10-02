String formatHour12(DateTime value, {bool arabic = true}) {
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final minute = value.minute.toString().padLeft(2, '0');
  final period = value.hour < 12 ? (arabic ? 'صباحًا' : 'AM') : (arabic ? 'مساءً' : 'PM');
  return '$hour:$minute $period';
}

String formatMinutes12(int minutes, {bool arabic = true}) {
  final normalized = ((minutes % (24 * 60)) + (24 * 60)) % (24 * 60);
  final date = DateTime(2000, 1, 1, normalized ~/ 60, normalized % 60);
  return formatHour12(date, arabic: arabic);
}
