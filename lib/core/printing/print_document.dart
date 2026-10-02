class PrintDocument {
  const PrintDocument({
    required this.title,
    required this.subtitle,
    required this.headers,
    required this.rows,
    this.metadata = const <String, String>{},
    this.summary = const <String, String>{},
    this.notes = const <String>[],
    this.footer = '',
    this.isArabic = true,
  });

  final String title;
  final String subtitle;
  final Map<String, String> metadata;
  final List<String> headers;
  final List<List<String>> rows;
  final Map<String, String> summary;
  final List<String> notes;
  final String footer;
  final bool isArabic;

  String text(String ar, String en) => isArabic ? ar : en;
}
