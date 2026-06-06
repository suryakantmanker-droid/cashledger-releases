import 'package:flutter/material.dart';

DateTime? _tryParseDate(dynamic v) {
  if (v is! String) return null;
  try { return DateTime.parse(v); } catch (_) { return null; }
}

class NotificationModel {
  final String id;
  final String userId;
  final String businessId;
  final String title;
  final String body;
  final String type;
  final Map<String, dynamic> data;
  final bool isRead;
  final DateTime createdAt;

  const NotificationModel({
    required this.id,
    required this.userId,
    this.businessId = '',
    required this.title,
    required this.body,
    required this.type,
    required this.data,
    required this.isRead,
    required this.createdAt,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id:         json['id'] as String? ?? '',
      userId:     json['user_id'] as String? ?? '',
      businessId: json['business_id'] as String? ?? '',
      title:      json['title'] as String? ?? '',
      body:       json['body'] as String? ?? '',
      type:       json['type'] as String? ?? '',
      data:       Map<String, dynamic>.from(json['data'] as Map? ?? {}),
      isRead:     json['is_read'] as bool? ?? false,
      createdAt:  _tryParseDate(json['created_at']) ?? DateTime.now(),
    );
  }

  bool get isSaleCollection => type == 'sale_collection';
  String? get saleId => data['saleId'] as String?;

  IconData get icon {
    switch (type) {
      case 'expense_approved':  return Icons.check_circle_rounded;
      case 'expense_rejected':  return Icons.cancel_rounded;
      case 'fund_transferred':  return Icons.account_balance_wallet_rounded;
      case 'expense_pending':   return Icons.pending_actions_rounded;
      case 'sale_collection':   return Icons.sell_rounded;
      default:                  return Icons.notifications_rounded;
    }
  }

  Color get iconColor {
    switch (type) {
      case 'expense_approved': return const Color(0xFF22C55E);
      case 'expense_rejected': return const Color(0xFFEF4444);
      case 'fund_transferred': return const Color(0xFF3B82F6);
      case 'expense_pending':  return const Color(0xFFF59E0B);
      case 'sale_collection':  return const Color(0xFF10B981);
      default:                 return const Color(0xFF6B7280);
    }
  }
}
