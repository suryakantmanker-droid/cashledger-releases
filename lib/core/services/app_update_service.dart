import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Result of a version check.
class UpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String minVersion;
  final String apkUrl;
  final String releaseNotes;
  final bool isForceUpdate;    // must update — cannot skip
  final bool hasUpdate;        // any update available

  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.minVersion,
    required this.apkUrl,
    required this.releaseNotes,
    required this.isForceUpdate,
    required this.hasUpdate,
  });

  bool get canSkip => !isForceUpdate;
}

class AppUpdateService {
  static final _supabase = Supabase.instance.client;

  /// Fetches version config from Supabase and compares with the installed version.
  /// Returns null if the check fails (network error, etc.) — app should proceed normally.
  static Future<UpdateInfo?> check() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final current = packageInfo.version; // e.g. "1.0.0"

      final row = await _supabase
          .from('app_versions')
          .select()
          .eq('platform', 'android')
          .eq('is_active', true)
          .maybeSingle();

      if (row == null) return null;

      final latest      = (row['latest_version'] as String?) ?? current;
      final min         = (row['min_version']    as String?) ?? current;
      final apkUrl      = (row['apk_url']        as String?) ?? '';
      final notes       = (row['release_notes']  as String?) ?? '';
      final forceFlag   = (row['force_update']   as bool?)   ?? false;

      final hasUpdate   = _isLower(current, latest);
      final belowMin    = _isLower(current, min);
      final isForce     = forceFlag || belowMin;

      debugPrint('[UpdateService] current=$current latest=$latest min=$min '
          'hasUpdate=$hasUpdate isForce=$isForce');

      // No update needed
      if (!hasUpdate) return null;

      return UpdateInfo(
        currentVersion: current,
        latestVersion:  latest,
        minVersion:     min,
        apkUrl:         apkUrl,
        releaseNotes:   notes,
        isForceUpdate:  isForce,
        hasUpdate:      hasUpdate,
      );
    } catch (e) {
      debugPrint('[UpdateService] check failed (non-fatal): $e');
      return null; // don't block app on network error
    }
  }

  /// Returns true if [a] is strictly lower than [b] (semver comparison).
  /// e.g. _isLower('1.0.0', '1.2.0') == true
  static bool _isLower(String a, String b) {
    final pa = _parse(a);
    final pb = _parse(b);
    for (var i = 0; i < 3; i++) {
      if (pa[i] < pb[i]) return true;
      if (pa[i] > pb[i]) return false;
    }
    return false; // equal
  }

  static List<int> _parse(String v) {
    final parts = v.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    while (parts.length < 3) { parts.add(0); }
    return parts;
  }
}
