class Formatters {
  Formatters._();

  /// Formats a number with a space as thousands separator (French/Guinean convention),
  /// without depending on intl locale data initialization.
  static String number(num value) {
    final isNegative = value < 0;
    final intPart = value.abs().round();
    final str = intPart.toString();
    final buffer = StringBuffer();
    final len = str.length;
    for (int i = 0; i < len; i++) {
      if (i > 0 && (len - i) % 3 == 0) buffer.write(' ');
      buffer.write(str[i]);
    }
    return (isNegative ? '-' : '') + buffer.toString();
  }

  static String gnf(num value) => '${number(value)} GNF';

  static String date(DateTime? d) {
    if (d == null) return '';
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }

  static String dateCode(DateTime d) {
    final yy = (d.year % 100).toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '$yy$mm$dd';
  }

  static String? dateToIso(DateTime? d) => d?.toIso8601String();

  static DateTime? isoToDate(String? s) => s == null || s.isEmpty ? null : DateTime.tryParse(s);
}
