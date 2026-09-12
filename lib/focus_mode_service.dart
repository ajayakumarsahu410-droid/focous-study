import 'package:flutter/services.dart';

/// Mirrors android.app.NotificationManager constants.
enum FocusLevel {
  off(1),          // INTERRUPTION_FILTER_ALL
  priorityOnly(2), // INTERRUPTION_FILTER_PRIORITY  (starred contacts can call)
  totalSilence(3), // INTERRUPTION_FILTER_NONE      (absolutely nothing)
  alarmsOnly(4);   // INTERRUPTION_FILTER_ALARMS    (our missed-slot alarm still rings)

  const FocusLevel(this.value);
  final int value;

  static FocusLevel fromValue(int v) =>
      FocusLevel.values.firstWhere((e) => e.value == v, orElse: () => FocusLevel.off);

  String get label => switch (this) {
        FocusLevel.off => 'Off',
        FocusLevel.priorityOnly => 'Priority only',
        FocusLevel.totalSilence => 'Total silence',
        FocusLevel.alarmsOnly => 'Alarms only',
      };

  String get description => switch (this) {
        FocusLevel.off => 'Normal ringer. Everything comes through.',
        FocusLevel.priorityOnly =>
          'Only starred contacts and repeat callers ring. Recommended if family must reach you.',
        FocusLevel.totalSilence =>
          'No calls, no notifications, no sound at all. Maximum focus.',
        FocusLevel.alarmsOnly =>
          'Calls and notifications muted, but alarms still ring. Best default for studying.',
      };
}

class FocusModeService {
  FocusModeService._();
  static final FocusModeService instance = FocusModeService._();

  static const _channel = MethodChannel('com.focusstudy.app/focus_mode');

  /// Filter that was active before we touched anything.
  int? _previousFilter;

  Future<bool> isPermissionGranted() async {
    try {
      return await _channel.invokeMethod<bool>('isDndAccessGranted') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Opens Settings > Notifications > Do Not Disturb access.
  Future<void> openPermissionSettings() =>
      _channel.invokeMethod('openDndSettings');

  Future<FocusLevel> currentLevel() async {
    final v = await _channel.invokeMethod<int>('getInterruptionFilter') ?? 1;
    return FocusLevel.fromValue(v);
  }

  /// Turn Focus Mode ON. Returns false if the user has not granted DND access.
  Future<bool> enable(FocusLevel level) async {
    if (!await isPermissionGranted()) return false;
    _previousFilter ??=
        await _channel.invokeMethod<int>('getInterruptionFilter') ?? 1;
    try {
      await _channel
          .invokeMethod('setInterruptionFilter', {'filter': level.value});
      return true;
    } on PlatformException {
      return false;
    }
  }

  /// Restore whatever sound profile the user had before the session.
  Future<void> disable() async {
    if (!await isPermissionGranted()) return;
    final restoreTo = _previousFilter ?? FocusLevel.off.value;
    try {
      await _channel
          .invokeMethod('setInterruptionFilter', {'filter': restoreTo});
    } on PlatformException {
      // ignore
    } finally {
      _previousFilter = null;
    }
  }
}
