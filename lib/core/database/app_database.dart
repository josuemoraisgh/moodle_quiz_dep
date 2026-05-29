import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Banco de dados SQLite local – único ponto de acesso a persistência.
class AppDatabase {
  static const _dbName = 'quiz_offline.db';
  static const _dbVersion = 1;

  static final AppDatabase instance = AppDatabase._();
  AppDatabase._();

  Database? _db;

  Future<Database> get database async {
    return _db ??= await _open();
  }

  Future<Database> _open() async {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final dir = await getApplicationDocumentsDirectory();
    final path = join(dir.path, _dbName);
    return openDatabase(path, version: _dbVersion, onCreate: _onCreate);
  }

  Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();

    batch.execute('''
      CREATE TABLE settings (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE students (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        name       TEXT NOT NULL UNIQUE,
        created_at INTEGER NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE quizzes (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        name       TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE questions (
        id      INTEGER PRIMARY KEY AUTOINCREMENT,
        quiz_id INTEGER NOT NULL,
        slot    INTEGER NOT NULL,
        type    TEXT    NOT NULL,
        data    TEXT    NOT NULL,
        FOREIGN KEY (quiz_id) REFERENCES quizzes(id) ON DELETE CASCADE
      )
    ''');

    // Uma sessão ativa por quiz (professor controla o estado).
    batch.execute('''
      CREATE TABLE quiz_sessions (
        id                      INTEGER PRIMARY KEY AUTOINCREMENT,
        quiz_id                 INTEGER NOT NULL,
        status                  TEXT    NOT NULL DEFAULT 'waiting',
        current_slot            INTEGER NOT NULL DEFAULT 0,
        current_page            INTEGER NOT NULL DEFAULT -1,
        total_pages             INTEGER NOT NULL DEFAULT 0,
        duration_seconds        INTEGER NOT NULL DEFAULT 30,
        start_on_first_response INTEGER NOT NULL DEFAULT 1,
        timer_started           INTEGER NOT NULL DEFAULT 0,
        started_at              INTEGER,
        ends_at                 INTEGER,
        round_id                TEXT    NOT NULL DEFAULT '',
        quiz_title              TEXT    NOT NULL DEFAULT '',
        FOREIGN KEY (quiz_id) REFERENCES quizzes(id)
      )
    ''');

    // Uma linha por (sessão, aluno, questão).
    batch.execute('''
      CREATE TABLE answers (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id    INTEGER NOT NULL,
        student_id    INTEGER NOT NULL,
        question_slot INTEGER NOT NULL,
        round_id      TEXT    NOT NULL,
        answer_data   TEXT    NOT NULL,
        is_correct    INTEGER NOT NULL DEFAULT 0,
        score         INTEGER NOT NULL DEFAULT 0,
        answered_at   INTEGER NOT NULL,
        FOREIGN KEY (session_id) REFERENCES quiz_sessions(id),
        FOREIGN KEY (student_id) REFERENCES students(id)
      )
    ''');

    await batch.commit(noResult: true);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
