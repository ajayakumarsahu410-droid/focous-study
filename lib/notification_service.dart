import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const alarmChannelId = 'missed_slot_alarm';
  static const ongoingChannelId = 'study_running';

  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;

    // Timezone database is bundled with the app -> works with no network.
    tzdata.initializeTimeZones();
    final localName = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(localName));

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: android),
      onDidReceiveNotificationResponse: (resp) {
        // payload = "missed:<slotId>" or "running"
        debugPrint('notification tapped: ${resp.payload}');
      },
    );

    final impl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    await impl?.createNotificationChannel(const AndroidNotificationChannel(
      alarmChannelId,
      'Missed study slot alarms',
      description: 'Loud alarm when you skip a timetable slot.',
      importance: Importance.max,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('study_alarm'),
      enableVibration: true,
      audioAttributesUsage: AudioAttributesUsage.alarm, // pierces DND
    ));

    await impl?.createNotificationChannel(const AndroidNotificationChannel(
      ongoingChannelId,
      'Study session running',
      description: 'Shows the live stopwatch while you study.',
      importance: Importance.low,
      playSound: false,
    ));

    _ready = true;
  }

  Future<void> requestPermissions() async {
    final impl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await impl?.requestNotificationsPermission();   // Android 13+
    await impl?.requestExactAlarmsPermission();     // Android 12+
  }

  // ------------------------------------------------------------- the alarm

  Future<void> showMissedSlotAlarm({
    required int id,
    required String subject,
    required String slotLabel,
  }) async {
    await init();
    await _plugin.show(
      id,
      'Missed: $subject',
      'Your $slotLabel slot started and no timer is running. Open the app and start studying.',
      NotificationDetails(
        android: AndroidNotificationDetails(
          alarmChannelId,
          'Missed study slot alarms',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.alarm,
          fullScreenIntent: true,
          ongoing: true,
          autoCancel: false,
          playSound: true,
          sound: const RawResourceAndroidNotificationSound('study_alarm'),
          audioAttributesUsage: AudioAttributesUsage.alarm,
          enableVibration: true,
          vibrationPattern: Int64List.fromList([0, 700, 400, 700, 400, 700]),
          actions: const [
            AndroidNotificationAction('start_now', 'Start now',
                showsUserInterface: true),
            AndroidNotificationAction('snooze_10', 'Snooze 10 min'),
          ],
        ),
      ),
      payload: 'missed:$id',
    );
  }

  /// Optional belt-and-braces: also schedule via the notification plugin,
  /// so the reminder fires even if AlarmManager work is dropped by the OEM.
  Future<void> scheduleExactAt({
    required int id,
    required DateTime when,
    required String title,
    required String body,
  }) async {
    await init();
    if (when.isBefore(DateTime.now())) return;

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(when, tz.local),
      NotificationDetails(
        android: AndroidNotificationDetails(
          alarmChannelId,
          'Missed study slot alarms',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.alarm,
          fullScreenIntent: true,
          audioAttributesUsage: AudioAttributesUsage.alarm,
          sound: const RawResourceAndroidNotificationSound('study_alarm'),
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time, // repeat daily
      payload: 'missed:$id',
    );
  }

  Future<void> showOngoing({
    required String subject,
    required String elapsed,
    required bool focusOn,
  }) async {
    await init();
    await _plugin.show(
      1,
      'Studying $subject',
      '$elapsed elapsed${focusOn ? "  •  Focus Mode on" : ""}',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          ongoingChannelId,
          'Study session running',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          onlyAlertOnce: true,
          showWhen: false,
          usesChronometer: true,
        ),
      ),
      payload: 'running',
    );
  }

  Future<void> cancel(int id) async => _plugin.cancel(id);
  Future<void> cancelAll() async => _plugin.cancelAll();
}
