class AppValidators {
  AppValidators._();

  static String? required(String? value, {String? fieldName}) {
    if (value == null || value.trim().isEmpty) {
      return '${fieldName ?? 'This field'} is required';
    }
    return null;
  }

  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) return 'Email is required';
    final regex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    if (!regex.hasMatch(value.trim())) return 'Enter a valid email address';
    return null;
  }

  static String? password(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  static String? phone(String? value) {
    if (value == null || value.trim().isEmpty) return 'Phone number is required';
    final regex = RegExp(r'^[6-9]\d{9}$');
    if (!regex.hasMatch(value.trim())) return 'Enter a valid 10-digit mobile number';
    return null;
  }

  static String? amount(String? value, {double? min, double? max}) {
    if (value == null || value.trim().isEmpty) return 'Amount is required';
    final amount = double.tryParse(value.trim());
    if (amount == null) return 'Enter a valid amount';
    if (amount <= 0) return 'Amount must be greater than 0';
    if (min != null && amount < min) return 'Minimum amount is ₹${min.toStringAsFixed(2)}';
    if (max != null && amount > max) return 'Maximum amount is ₹${max.toStringAsFixed(2)}';
    return null;
  }

  static String? name(String? value, {String? fieldName}) {
    if (value == null || value.trim().isEmpty) {
      return '${fieldName ?? 'Name'} is required';
    }
    if (value.trim().length < 2) return '${fieldName ?? 'Name'} is too short';
    if (value.trim().length > 60) return '${fieldName ?? 'Name'} is too long';
    return null;
  }

  static String? minLength(String? value, int min, {String? fieldName}) {
    if (value == null || value.trim().isEmpty) {
      return '${fieldName ?? 'This field'} is required';
    }
    if (value.trim().length < min) {
      return '${fieldName ?? 'This field'} must be at least $min characters';
    }
    return null;
  }

  static String? maxLength(String? value, int max, {String? fieldName}) {
    if (value != null && value.trim().length > max) {
      return '${fieldName ?? 'This field'} cannot exceed $max characters';
    }
    return null;
  }

  static String? Function(String?) combine(List<String? Function(String?)> validators) {
    return (value) {
      for (final v in validators) {
        final result = v(value);
        if (result != null) return result;
      }
      return null;
    };
  }
}
