import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

class AppUtils {
  AppUtils._();

  static final _currencyFormatter = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  static final _compactFormatter = NumberFormat.compact(locale: 'en_IN');

  static String formatCurrency(double amount) {
    return _currencyFormatter.format(amount);
  }

  static String formatCurrencyCompact(double amount) {
    if (amount >= 1000) {
      return '₹${_compactFormatter.format(amount)}';
    }
    return formatCurrency(amount);
  }

  static String formatDate(DateTime date) {
    return DateFormat('dd/MM/yyyy').format(date);
  }

  static String formatDateWithTime(DateTime date) {
    return DateFormat('dd/MM/yyyy hh:mm a').format(date);
  }

  static String formatTime(DateTime date) {
    return DateFormat('hh:mm a').format(date);
  }

  static String formatMonthYear(DateTime date) {
    return DateFormat('MMMM yyyy').format(date);
  }

  static String generateId() {
    return const Uuid().v4();
  }

  static String generateEmployeeId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString().substring(7);
    return 'EMP$timestamp';
  }

  static String generateTransferId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString().substring(7);
    return 'TXN$timestamp';
  }

  static String generateExpenseId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString().substring(7);
    return 'EXP$timestamp';
  }

  static String generateSaleId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString().substring(7);
    return 'SAL$timestamp';
  }

  static String timeAgo(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return formatDate(date);
  }

  static String getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  static String maskPhoneNumber(String phone) {
    if (phone.length < 4) return phone;
    return '${phone.substring(0, 2)}****${phone.substring(phone.length - 2)}';
  }
}
