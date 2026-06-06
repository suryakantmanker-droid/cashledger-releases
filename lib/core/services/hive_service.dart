import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:hive_flutter/hive_flutter.dart';
import '../constants/app_constants.dart';
import '../constants/notification_mode.dart';

/// Centralised Hive service.
///
/// All Hive box access goes through this class — never open boxes directly
/// elsewhere. This prevents key collisions and makes it easy to wipe all
/// business-scoped cache on logout or business switch.
///
/// Initialise once in main.dart via [HiveService.initialize()].
class HiveService {
  HiveService._();
  static final HiveService instance = HiveService._();

  // ── Box accessors ─────────────────────────────────────────────────────────

  Box get _businessBox  => Hive.box(AppConstants.activeBusinessBox);
  Box get _settingsBox  => Hive.box(AppConstants.settingsBox);
  Box get _syncQueueBox => Hive.box(AppConstants.syncQueueBox);
  Box get _userBox      => Hive.box(AppConstants.userBox);

  // ── Initialization ────────────────────────────────────────────────────────

  /// Open all boxes. Call once from main.dart before runApp().
  static Future<void> initialize() async {
    await Future.wait([
      Hive.openBox(AppConstants.activeBusinessBox),
      Hive.openBox(AppConstants.settingsBox),
      Hive.openBox(AppConstants.syncQueueBox),
      Hive.openBox(AppConstants.userBox),
      Hive.openBox(AppConstants.draftExpenseBox),
    ]);
    debugPrint('[HiveService] All boxes opened');
  }

  // ── Active Business ───────────────────────────────────────────────────────

  static const _keyActiveBusinessId = 'active_business_id';

  String? getActiveBusinessId() =>
      _businessBox.get(_keyActiveBusinessId) as String?;

  Future<void> saveActiveBusinessId(String id) async {
    await _businessBox.put(_keyActiveBusinessId, id);
    debugPrint('[HiveService] Saved activeBusinessId: $id');
  }

  Future<void> clearActiveBusinessId() async {
    await _businessBox.delete(_keyActiveBusinessId);
    debugPrint('[HiveService] Cleared activeBusinessId');
  }

  // ── Cached Memberships ────────────────────────────────────────────────────

  static const _keyMemberships = 'cached_memberships';

  List<Map<String, dynamic>>? getCachedMemberships() {
    final raw = _businessBox.get(_keyMemberships);
    if (raw == null) return null;
    return (raw as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> cacheMemberships(List<Map<String, dynamic>> data) async {
    await _businessBox.put(_keyMemberships, data);
  }

  Future<void> clearMembershipsCache() async {
    await _businessBox.delete(_keyMemberships);
  }

  // ── Theme ─────────────────────────────────────────────────────────────────

  ThemeMode getThemeMode() {
    final index = _settingsBox.get('theme_mode', defaultValue: 0) as int;
    return ThemeMode.values[index.clamp(0, ThemeMode.values.length - 1)];
  }

  Future<void> saveThemeMode(ThemeMode mode) async {
    await _settingsBox.put('theme_mode', mode.index);
  }

  // ── Amount Threshold (super-admin, device-local) ──────────────────────────

  static const _keyAmountThreshold = 'sa_amount_threshold';

  double? getAmountThreshold() {
    final v = _settingsBox.get(_keyAmountThreshold);
    if (v == null) return null;
    return (v as num).toDouble();
  }

  Future<void> saveAmountThreshold(double? amount) async {
    if (amount == null) {
      await _settingsBox.delete(_keyAmountThreshold);
    } else {
      await _settingsBox.put(_keyAmountThreshold, amount);
    }
  }

  // ── Notification Mode ─────────────────────────────────────────────────────

  static const _keyNotificationMode = 'notification_mode';

  NotificationMode getNotificationMode() {
    final value = _settingsBox.get(_keyNotificationMode, defaultValue: 'sound') as String;
    return NotificationMode.values.firstWhere(
      (m) => m.name == value,
      orElse: () => NotificationMode.sound,
    );
  }

  Future<void> saveNotificationMode(NotificationMode mode) async {
    await _settingsBox.put(_keyNotificationMode, mode.name);
  }

  // ── Sync Queue (Phase 5 offline) ──────────────────────────────────────────

  List<Map<String, dynamic>> getSyncQueue() {
    final raw = _syncQueueBox.get('queue') as List<dynamic>? ?? [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> enqueueSyncOperation(Map<String, dynamic> op) async {
    final queue = getSyncQueue();
    queue.add(op);
    await _syncQueueBox.put('queue', queue);
  }

  Future<void> clearSyncQueue() async {
    await _syncQueueBox.put('queue', <Map<String, dynamic>>[]);
  }

  // ── Full wipe on logout ───────────────────────────────────────────────────

  Future<void> clearAll() async {
    await _businessBox.clear();
    await _userBox.clear();
    debugPrint('[HiveService] All local data cleared');
  }
}
