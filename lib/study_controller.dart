import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/database_helper.dart';
import '../models/models.dart';
import '../services/alarm_service.dart';
import '../services/focus_mode_service.dart';
import '../services/notification_service.dart';

class StudyController extends ChangeNotifier {
  final _db = DatabaseHelper.instance;

  // ---- persisted keys (shared with the background alarm isolate) ----
  static const _kRunning = 'is_running';
  static const _kSubject = 'running_subject';
  static const _kStartedAt = 'started_at_millis';
  static const _kAccumulated = 'accumulated_seconds';
  static const _kFocusLevel = 'focus_level';
  static const _kFocusEnabled = 'focus_enabled';

  List<Subject> subjects = [];
  List<TimetableSlot> slots = [];
  List<StudySession> recent = [];
  Map<String, int> todayTotals = {};
  Map<String, int> weekTotals = {};

  String? selectedSubject;

  /// Wall-clock instant the current (un-paused) run began. Null when paused.
  DateTime? _segmentStart;

  /// Seconds banked from previous segments of the same session.
  int _accumulated = 0;

  /// Instant the whole session began (used for the DB row).
  DateTime? _sessionStart;

  bool get isRunning => _segmentStart != null;
  bool get hasActiveSession => _sessionStart != null;

  bool focusEnabled = true;
  FocusLevel focusLevel = FocusLevel.alarmsOnly;
  bool dndGranted = false;
  bool focusActive = false;

  Timer? _uiTicker;

  // ------------------------------------------------------------- lifecycle

  Future<void> bootstrap() async {
    await refreshAll();

    final prefs = await SharedPreferences.getInstance();
    focusEnabled = prefs.getBool(_kFocusEnabled) ?? true;
    focusLevel = FocusLevel.fromValue(prefs.getInt(_kFocusLevel) ?? 4);
    dndGranted = await FocusModeService.instance.isPermissionGranted();

    // Restore a session that was running when the process died.
    if (prefs.getBool(_kRunning) ?? false) {
      selectedSubject = prefs.getString(_kSubject);
      _accumulated = prefs.getInt(_kAccumulated) ?? 0;
      final startedAt = prefs.getInt(_kStartedAt);
      if (startedAt != null) {
        _segmentStart = DateTime.fromMillisecondsSinceEpoch(startedAt);
        _sessionStart = _segmentStart;
        _startTicker();
      }
    }

    selectedSubject ??= subjects.isNotEmpty ? subjects.first.name : null;
    await NotificationService.instance.requestPermissions();
    await AlarmService.instance.syncAllSlots();
    notifyListeners();
  }

  Future<void> refreshAll() async {
    subjects = await _db.getSubjects();
    slots = await _db.getSlots();
    recent = await _db.getRecentSessions(limit: 40);

    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final startOfWeek = startOfToday.subtract(Duration(days: now.weekday - 1));

    todayTotals =
        await _db.totalsBySubject(startOfToday, startOfToday.add(const Duration(days: 1)));
    weekTotals =
        await _db.totalsBySubject(startOfWeek, startOfWeek.add(const Duration(days: 7)));

    notifyListeners();
  }

  // -------------------------------------------------------- the stopwatch

  /// Drift-free: derived purely from system timestamps.
  Duration get elapsed {
    final live = _segmentStart == null
        ? Duration.zero
        : DateTime.now().difference(_segmentStart!);
    return Duration(seconds: _accumulated) + live;
  }

  Future<void> start() async {
    if (isRunning || selectedSubject == null) return;

    final now = DateTime.now();
    _segmentStart = now;
    _sessionStart ??= now;

    await _persistRunState();
    await _applyFocusMode(true);
    _startTicker();
    notifyListeners();
  }

  Future<void> pause() async {
    if (!isRunning) return;

    _accumulated += DateTime.now().difference(_segmentStart!).inSeconds;
    _segmentStart = null;
    _uiTicker?.cancel();

    await _persistRunState();
    await _applyFocusMode(false); // restore the ringer while on a break
    notifyListeners();
  }

  /// Stop, write the session row, reset everything.
  Future<StudySession?> stopAndSave({String? note}) async {
    if (!hasActiveSession) return null;

    if (isRunning) {
      _accumulated += DateTime.now().difference(_segmentStart!).inSeconds;
    }
    final session = StudySession(
      subjectName: selectedSubject ?? 'Study',
      startTime: _sessionStart!,
      endTime: DateTime.now(),
      durationSeconds: _accumulated,
      note: note,
    );

    // Discard accidental taps under 10 seconds.
    if (_accumulated >= 10) {
      await _db.insertSession(session);
    }

    _segmentStart = null;
    _sessionStart = null;
    _accumulated = 0;
    _uiTicker?.cancel();

    await _persistRunState();
    await _applyFocusMode(false);
    await NotificationService.instance.cancel(1);
    await refreshAll();
    return session;
  }

  void _startTicker() {
    _uiTicker?.cancel();
    // Repaints the UI only. The value always comes from timestamps.
    _uiTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      notifyListeners();
      final e = elapsed;
      if (e.inSeconds % 15 == 0) {
        NotificationService.instance.showOngoing(
          subject: selectedSubject ?? 'Study',
          elapsed: formatDuration(e),
          focusOn: focusActive,
        );
      }
    });
  }

  Future<void> _persistRunState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kRunning, isRunning);
    await prefs.setString(_kSubject, selectedSubject ?? '');
    await prefs.setInt(_kAccumulated, _accumulated);
    if (_segmentStart != null) {
      await prefs.setInt(_kStartedAt, _segmentStart!.millisecondsSinceEpoch);
    } else {
      await prefs.remove(_kStartedAt);
    }
  }

  // -------------------------------------------------------- focus mode

  Future<void> refreshDndPermission() async {
    dndGranted = await FocusModeService.instance.isPermissionGranted();
    notifyListeners();
  }

  Future<void> setFocusEnabled(bool v) async {
    focusEnabled = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kFocusEnabled, v);
    if (isRunning) await _applyFocusMode(v);
    notifyListeners();
  }

  Future<void> setFocusLevel(FocusLevel level) async {
    focusLevel = level;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kFocusLevel, level.value);
    if (isRunning && focusEnabled) await _applyFocusMode(true);
    notifyListeners();
  }

  Future<void> _applyFocusMode(bool on) async {
    if (!focusEnabled) {
      if (focusActive) {
        await FocusModeService.instance.disable();
        focusActive = false;
      }
      return;
    }
    if (on) {
      focusActive = await FocusModeService.instance.enable(focusLevel);
      dndGranted = focusActive || await FocusModeService.instance.isPermissionGranted();
    } else {
      await FocusModeService.instance.disable();
      focusActive = false;
    }
  }

  // -------------------------------------------------------- subjects / slots

  Future<void> addSubject(String name, Color color) async {
    final clean = name.trim();
    if (clean.isEmpty) return;
    await _db.insertSubject(Subject(name: clean, colorValue: color.value));
    await refreshAll();
    selectedSubject ??= clean;
  }

  Future<void> removeSubject(Subject s) async {
    if (s.id == null) return;
    await _db.deleteSubject(s.id!);
    if (selectedSubject == s.name) selectedSubject = null;
    await refreshAll();
  }

  void selectSubject(String name) {
    if (hasActiveSession) return; // don't switch mid-session
    selectedSubject = name;
    notifyListeners();
  }

  Future<void> saveSlot(TimetableSlot slot) async {
    final id = await _db.upsertSlot(slot);
    await refreshAll();
    final saved = slots.firstWhere((s) => s.id == id, orElse: () => slot);
    await AlarmService.instance.cancelSlot(saved);
    if (saved.enabled) await AlarmService.instance.scheduleSlot(saved);
  }

  Future<void> deleteSlot(TimetableSlot slot) async {
    await AlarmService.instance.cancelSlot(slot);
    if (slot.id != null) await _db.deleteSlot(slot.id!);
    await refreshAll();
  }

  /// The slot that should be running right now, if any.
  TimetableSlot? get currentSlot {
    final now = DateTime.now();
    final minutes = now.hour * 60 + now.minute;
    final today = now.weekday - 1;
    for (final s in slots) {
      if (!s.enabled || !s.days[today]) continue;
      if (minutes >= s.startMinute && minutes < s.endMinute) return s;
    }
    return null;
  }

  @override
  void dispose() {
    _uiTicker?.cancel();
    super.dispose();
  }
}

String formatDuration(Duration d) {
  final h = d.inHours.toString().padLeft(2, '0');
  final m = (d.inMinutes % 60).toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$h:$m:$s';
}

String formatHours(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (h == 0) return '${m}m';
  return '${h}h ${m}m';
}
