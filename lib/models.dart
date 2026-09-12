import 'package:flutter/material.dart';

/// A study subject, e.g. "Economics".
class Subject {
  final int? id;
  final String name;
  final int colorValue;

  const Subject({this.id, required this.name, required this.colorValue});

  Color get color => Color(colorValue);

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'color_value': colorValue,
      };

  factory Subject.fromMap(Map<String, Object?> m) => Subject(
        id: m['id'] as int?,
        name: m['name'] as String,
        colorValue: m['color_value'] as int,
      );
}

/// One completed (or in-progress) stopwatch run.
class StudySession {
  final int? id;
  final String subjectName;
  final DateTime startTime;
  final DateTime? endTime;
  final int durationSeconds;
  final String? note;

  const StudySession({
    this.id,
    required this.subjectName,
    required this.startTime,
    required this.endTime,
    required this.durationSeconds,
    this.note,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'subject_name': subjectName,
        'start_time': startTime.toUtc().millisecondsSinceEpoch,
        'end_time': endTime?.toUtc().millisecondsSinceEpoch,
        'duration_seconds': durationSeconds,
        'note': note,
      };

  factory StudySession.fromMap(Map<String, Object?> m) => StudySession(
        id: m['id'] as int?,
        subjectName: m['subject_name'] as String,
        startTime:
            DateTime.fromMillisecondsSinceEpoch(m['start_time'] as int, isUtc: true)
                .toLocal(),
        endTime: m['end_time'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['end_time'] as int, isUtc: true)
                .toLocal(),
        durationSeconds: m['duration_seconds'] as int,
        note: m['note'] as String?,
      );
}

/// A recurring daily timetable slot, e.g. Economics 08:00 -> 11:00 Mon-Sat.
class TimetableSlot {
  final int? id;
  final String subjectName;

  /// Minutes from midnight (08:00 => 480).
  final int startMinute;
  final int endMinute;

  /// 7 booleans, index 0 = Monday ... 6 = Sunday.
  final List<bool> days;
  final bool enabled;

  /// Grace period before the "you missed it" alarm fires.
  final int graceMinutes;

  const TimetableSlot({
    this.id,
    required this.subjectName,
    required this.startMinute,
    required this.endMinute,
    required this.days,
    this.enabled = true,
    this.graceMinutes = 5,
  });

  TimeOfDay get startTod =>
      TimeOfDay(hour: startMinute ~/ 60, minute: startMinute % 60);
  TimeOfDay get endTod => TimeOfDay(hour: endMinute ~/ 60, minute: endMinute % 60);

  int get durationMinutes =>
      endMinute >= startMinute ? endMinute - startMinute : (1440 - startMinute) + endMinute;

  /// Stable alarm id derived from the row id (android_alarm_manager needs an int).
  int get alarmId => 100000 + (id ?? 0);

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'subject_name': subjectName,
        'start_minute': startMinute,
        'end_minute': endMinute,
        'days_mask': _maskFromDays(days),
        'enabled': enabled ? 1 : 0,
        'grace_minutes': graceMinutes,
      };

  factory TimetableSlot.fromMap(Map<String, Object?> m) => TimetableSlot(
        id: m['id'] as int?,
        subjectName: m['subject_name'] as String,
        startMinute: m['start_minute'] as int,
        endMinute: m['end_minute'] as int,
        days: _daysFromMask(m['days_mask'] as int),
        enabled: (m['enabled'] as int) == 1,
        graceMinutes: (m['grace_minutes'] as int?) ?? 5,
      );

  TimetableSlot copyWith({
    String? subjectName,
    int? startMinute,
    int? endMinute,
    List<bool>? days,
    bool? enabled,
    int? graceMinutes,
  }) =>
      TimetableSlot(
        id: id,
        subjectName: subjectName ?? this.subjectName,
        startMinute: startMinute ?? this.startMinute,
        endMinute: endMinute ?? this.endMinute,
        days: days ?? this.days,
        enabled: enabled ?? this.enabled,
        graceMinutes: graceMinutes ?? this.graceMinutes,
      );

  /// Public helper used by the alarm scheduler.
  static int maskOf(List<bool> d) => _maskFromDays(d);

  static int _maskFromDays(List<bool> d) {
    var mask = 0;
    for (var i = 0; i < 7; i++) {
      if (d[i]) mask |= (1 << i);
    }
    return mask;
  }

  static List<bool> _daysFromMask(int mask) =>
      List<bool>.generate(7, (i) => (mask & (1 << i)) != 0);
}
