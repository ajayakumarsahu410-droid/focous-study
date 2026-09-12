import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/models.dart';

class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  static const _dbName = 'focus_study.db';
  static const _dbVersion = 1;

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE subjects (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            name         TEXT    NOT NULL UNIQUE,
            color_value  INTEGER NOT NULL
          );
        ''');

        await db.execute('''
          CREATE TABLE sessions (
            id                INTEGER PRIMARY KEY AUTOINCREMENT,
            subject_name      TEXT    NOT NULL,
            start_time        INTEGER NOT NULL,   -- UTC millis
            end_time          INTEGER,            -- UTC millis, null while running
            duration_seconds  INTEGER NOT NULL DEFAULT 0,
            note              TEXT
          );
        ''');

        await db.execute(
            'CREATE INDEX idx_sessions_start ON sessions(start_time);');
        await db.execute(
            'CREATE INDEX idx_sessions_subject ON sessions(subject_name);');

        await db.execute('''
          CREATE TABLE timetable (
            id             INTEGER PRIMARY KEY AUTOINCREMENT,
            subject_name   TEXT    NOT NULL,
            start_minute   INTEGER NOT NULL,
            end_minute     INTEGER NOT NULL,
            days_mask      INTEGER NOT NULL DEFAULT 127,
            enabled        INTEGER NOT NULL DEFAULT 1,
            grace_minutes  INTEGER NOT NULL DEFAULT 5
          );
        ''');

        // Sensible starter subjects so the app is usable on first launch.
        const seed = <String, int>{
          'Economics': 0xFF6366F1,
          'History': 0xFFF59E0B,
          'Mathematics': 0xFF10B981,
        };
        for (final e in seed.entries) {
          await db.insert('subjects', {'name': e.key, 'color_value': e.value});
        }
      },
    );
  }

  // ---------------------------------------------------------------- subjects

  Future<List<Subject>> getSubjects() async {
    final db = await database;
    final rows = await db.query('subjects', orderBy: 'name COLLATE NOCASE ASC');
    return rows.map(Subject.fromMap).toList();
  }

  Future<int> insertSubject(Subject s) async {
    final db = await database;
    return db.insert('subjects', s.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> deleteSubject(int id) async {
    final db = await database;
    await db.delete('subjects', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------- sessions

  Future<int> insertSession(StudySession s) async {
    final db = await database;
    return db.insert('sessions', s.toMap());
  }

  Future<List<StudySession>> getSessionsBetween(DateTime from, DateTime to) async {
    final db = await database;
    final rows = await db.query(
      'sessions',
      where: 'start_time >= ? AND start_time < ?',
      whereArgs: [
        from.toUtc().millisecondsSinceEpoch,
        to.toUtc().millisecondsSinceEpoch,
      ],
      orderBy: 'start_time DESC',
    );
    return rows.map(StudySession.fromMap).toList();
  }

  Future<List<StudySession>> getRecentSessions({int limit = 50}) async {
    final db = await database;
    final rows =
        await db.query('sessions', orderBy: 'start_time DESC', limit: limit);
    return rows.map(StudySession.fromMap).toList();
  }

  Future<void> deleteSession(int id) async {
    final db = await database;
    await db.delete('sessions', where: 'id = ?', whereArgs: [id]);
  }

  /// { "Economics": 7200, "History": 1800 } seconds studied in the range.
  Future<Map<String, int>> totalsBySubject(DateTime from, DateTime to) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT subject_name, SUM(duration_seconds) AS total
      FROM sessions
      WHERE start_time >= ? AND start_time < ?
      GROUP BY subject_name
      ORDER BY total DESC
    ''', [
      from.toUtc().millisecondsSinceEpoch,
      to.toUtc().millisecondsSinceEpoch,
    ]);
    return {
      for (final r in rows) r['subject_name'] as String: (r['total'] as int?) ?? 0
    };
  }

  /// Seconds studied per day for the last [days] days (index 0 = oldest).
  Future<List<int>> dailyTotals({int days = 7}) async {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final out = <int>[];
    for (var i = days - 1; i >= 0; i--) {
      final from = startOfToday.subtract(Duration(days: i));
      final to = from.add(const Duration(days: 1));
      final totals = await totalsBySubject(from, to);
      out.add(totals.values.fold<int>(0, (a, b) => a + b));
    }
    return out;
  }

  /// Did the user actually study [subject] around [slotStart] today?
  /// Used by the alarm callback to decide whether the slot was missed.
  Future<bool> hasSessionNear(String subject, DateTime slotStart,
      {Duration window = const Duration(minutes: 30)}) async {
    final db = await database;
    final rows = await db.query(
      'sessions',
      where: 'subject_name = ? AND start_time >= ? AND start_time <= ?',
      whereArgs: [
        subject,
        slotStart.subtract(window).toUtc().millisecondsSinceEpoch,
        slotStart.add(window).toUtc().millisecondsSinceEpoch,
      ],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  // --------------------------------------------------------------- timetable

  Future<List<TimetableSlot>> getSlots() async {
    final db = await database;
    final rows = await db.query('timetable', orderBy: 'start_minute ASC');
    return rows.map(TimetableSlot.fromMap).toList();
  }

  Future<int> upsertSlot(TimetableSlot slot) async {
    final db = await database;
    if (slot.id == null) return db.insert('timetable', slot.toMap());
    await db.update('timetable', slot.toMap(),
        where: 'id = ?', whereArgs: [slot.id]);
    return slot.id!;
  }

  Future<void> deleteSlot(int id) async {
    final db = await database;
    await db.delete('timetable', where: 'id = ?', whereArgs: [id]);
  }
}
