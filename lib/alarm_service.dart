import 'dart:isolate';
import 'dart:ui';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/database_helper.dart';
import '../models/models.dart';
import 'notification_service.dart';

/// Runs in a BACKGROUND ISOLATE. Must be a top-level (or static) function
/// and must be annotated with @pragma('vm:entry-point') for release builds.
@pragma('vm:entry-point')
Future<void> missedSlotAlarmCallback(int alarmId, Map<String, dynamic> data) async {
  WidgetsFlutterBinding.ensureInitialized();

  final subject = (data['subject'] as String?) ?? 'Study';
  final label = (data['label'] as String?) ?? '';
  final slotStartMillis = (data['slotStartMillis'] as int?) ?? 0;
  final slotStart = DateTime.fromMillisecondsSinceEpoch(slotStartMillis);

  final db = DatabaseHelper.instance;

  // 1. Is a session for this subject running right now?
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final runningSubject = prefs.getString('running_subject');
  final isRunning = prefs.getBool('is_running') ?? false;

  // 2. Or did the user already log a session around the slot start?
  final alreadyStudied =
      await db.hasSessionNear(subject, slotStart, window: const Duration(minutes: 30));

  final honoured = (isRunning && runningSubject == subject) || alreadyStudied;

  if (!honoured) {
    await NotificationService.instance.showMissedSlotAlarm(
      id: alarmId,
      subject: subject,
      slotLabel: label,
    );
  }

  // 3. Re-arm for tomorrow (one-shot alarms are the only reliable exact alarms).
  await AlarmService.instance.rescheduleOne(alarmId, data);

  // Let the UI isolate refresh if it happens to be alive.
  IsolateNameServer.lookupPortByName(AlarmService.portName)?.send(alarmId);
}

class AlarmService {
  AlarmService._();
  static final AlarmService instance = AlarmService._();

  static const portName = 'focus_study_alarm_port';

  Future<void> init() async {
    await AndroidAlarmManager.initialize();
    await NotificationService.instance.init();
  }

  /// Rebuild every alarm from the DB. Call on app start, after editing the
  /// timetable, and from the boot receiver.
  Future<void> syncAllSlots() async {
    final slots = await DatabaseHelper.instance.getSlots();
    for (final slot in slots) {
      await cancelSlot(slot);
      if (slot.enabled) await scheduleSlot(slot);
    }
  }

  Future<void> scheduleSlot(TimetableSlot slot) async {
    final fireAt = _nextFireTime(slot);
    if (fireAt == null) return;

    final payload = <String, dynamic>{
      'subject': slot.subjectName,
      'label': _label(slot),
      'slotStartMillis':
          fireAt.subtract(Duration(minutes: slot.graceMinutes)).millisecondsSinceEpoch,
      'startMinute': slot.startMinute,
      'graceMinutes': slot.graceMinutes,
      'daysMask': TimetableSlot.maskOf(slot.days),
    };

    await AndroidAlarmManager.oneShotAt(
      fireAt,
      slot.alarmId,
      missedSlotAlarmCallback,
      exact: true,                 // exact wall-clock alarm
      wakeup: true,                // wake the CPU
      allowWhileIdle: true,        // punch through Doze
      rescheduleOnReboot: true,    // survives a restart
      params: payload,
    );

    debugPrint('Alarm ${slot.alarmId} armed for $fireAt (${slot.subjectName})');
  }

  /// Called from inside the background isolate to arm the next occurrence.
  Future<void> rescheduleOne(int alarmId, Map<String, dynamic> data) async {
    final startMinute = (data['startMinute'] as int?) ?? 0;
    final grace = (data['graceMinutes'] as int?) ?? 5;
    final daysMask = (data['daysMask'] as int?) ?? 127;

    final next = _nextFireFromParts(startMinute, grace, daysMask);
    if (next == null) return;

    final payload = Map<String, dynamic>.from(data)
      ..['slotStartMillis'] =
          next.subtract(Duration(minutes: grace)).millisecondsSinceEpoch;

    await AndroidAlarmManager.oneShotAt(
      next,
      alarmId,
      missedSlotAlarmCallback,
      exact: true,
      wakeup: true,
      allowWhileIdle: true,
      rescheduleOnReboot: true,
      params: payload,
    );
  }

  Future<void> cancelSlot(TimetableSlot slot) async {
    await AndroidAlarmManager.cancel(slot.alarmId);
    await NotificationService.instance.cancel(slot.alarmId);
  }

  /// Snooze the missed-slot alarm by [minutes].
  Future<void> snooze(int alarmId, Map<String, dynamic> data, int minutes) async {
    await NotificationService.instance.cancel(alarmId);
    await AndroidAlarmManager.oneShotAt(
      DateTime.now().add(Duration(minutes: minutes)),
      alarmId + 500000,
      missedSlotAlarmCallback,
      exact: true,
      wakeup: true,
      allowWhileIdle: true,
      params: data,
    );
  }

  // ------------------------------------------------------------- scheduling

  String _label(TimetableSlot s) =>
      '${_fmt(s.startMinute)} - ${_fmt(s.endMinute)}';

  String _fmt(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    final suffix = h < 12 ? 'AM' : 'PM';
    final hh = h % 12 == 0 ? 12 : h % 12;
    return '$hh:${m.toString().padLeft(2, '0')} $suffix';
  }

  DateTime? _nextFireTime(TimetableSlot slot) => _nextFireFromParts(
      slot.startMinute, slot.graceMinutes, TimetableSlot.maskOf(slot.days));

  DateTime? _nextFireFromParts(int startMinute, int grace, int daysMask) {
    if (daysMask == 0) return null;
    final now = DateTime.now();

    for (var offset = 0; offset < 8; offset++) {
      final day = now.add(Duration(days: offset));
      final weekdayIndex = day.weekday - 1; // Mon = 0
      if ((daysMask & (1 << weekdayIndex)) == 0) continue;

      final fire = DateTime(day.year, day.month, day.day)
          .add(Duration(minutes: startMinute + grace));
      if (fire.isAfter(now.add(const Duration(seconds: 5)))) return fire;
    }
    return null;
  }
}
