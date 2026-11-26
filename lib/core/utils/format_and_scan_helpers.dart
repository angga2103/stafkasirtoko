import 'package:intl/intl.dart';

class CurrencyHelper {
  static String _symbol = 'Rp ';
  static void setCurrencySymbol(String symbol) {
    _symbol = symbol.trim().isEmpty ? 'Rp ' : '${symbol.trim()} ';
  }

  static String format(double amount, {bool withSymbol = true}) {
    final formatted = NumberFormat('#,##0', 'id_ID').format(amount.round());
    return withSymbol ? '$_symbol$formatted' : formatted;
  }

  static String formatNumber(double value) {
    if (value.truncateToDouble() == value) {
      return NumberFormat('#,##0', 'id_ID').format(value.toInt());
    }
    return NumberFormat('#,##0.##', 'id_ID').format(value);
  }
}

class QuickCashHelper {
  static List<double> suggestAmounts(double total) {
    if (total <= 0) return const [];
    final suggestions = <double>{total.ceilToDouble()};
    const denoms = [5000.0, 10000.0, 20000.0, 50000.0, 100000.0];
    for (final d in denoms) {
      final ceilD = ((total / d).ceil()) * d;
      suggestions.add(ceilD);
      if (d >= total) suggestions.add(d);
    }
    final list = suggestions.where((v) => v >= total).toList()..sort();
    return list.take(5).toList();
  }
}

class BarcodeScanGuard {
  final Duration cooldown;
  String? _lastCode;
  DateTime? _lastAcceptedAt;

  BarcodeScanGuard({this.cooldown = const Duration(milliseconds: 1200)});

  bool shouldAccept(String rawCode, {DateTime? now}) {
    final clean = rawCode.trim();
    if (clean.isEmpty) return false;
    final current = now ?? DateTime.now();
    if (_lastCode == clean && _lastAcceptedAt != null) {
      if (current.difference(_lastAcceptedAt!) < cooldown) {
        return false;
      }
    }
    _lastCode = clean;
    _lastAcceptedAt = current;
    return true;
  }

  void reset() {
    _lastCode = null;
    _lastAcceptedAt = null;
  }
}
