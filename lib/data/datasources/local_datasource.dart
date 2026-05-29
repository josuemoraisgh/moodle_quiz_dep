import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../core/database/app_database.dart';
import '../../core/utils/moodle_html_parser.dart'
    show
        GapInputData,
        MatchData,
        MatchSubQuestion,
        MoodleAnswerControl,
        ParsedChoice;
import '../../domain/entities/answer_record_entity.dart';
import '../../domain/entities/app_settings_entity.dart';
import '../../domain/entities/local_quiz_entity.dart';
import '../../domain/entities/local_user_entity.dart';
import '../../domain/entities/question_entity.dart';
import '../../domain/entities/quiz_state_entity.dart';
import '../../domain/entities/score_entity.dart';
import '../../domain/entities/student_entity.dart';

/// Acesso a todos os dados persistidos no SQLite.
/// Único ponto que conhece o esquema do banco.
class LocalDatasource {
  final AppDatabase _db;
  LocalDatasource(this._db);

  // ── Settings ──────────────────────────────────────────────────────────────

  Future<AppSettingsEntity> loadSettings() async {
    final db = await _db.database;
    final rows = await db.query('settings');
    final map = {
      for (final r in rows) r['key'] as String: r['value'] as String
    };
    final rawOptions = map['duration_options'] ?? '';
    final options = rawOptions.isEmpty
        ? <int>[15, 20, 30, 45, 60, 90, 120]
        : rawOptions
            .split(',')
            .map((s) => int.tryParse(s.trim()))
            .whereType<int>()
            .toList();
    return AppSettingsEntity(
      teacherPassword: map['teacher_password'] ?? '',
      studentPassword: map['student_password'] ?? '',
      quizTitle: map['quiz_title'] ?? 'Quiz Presencial',
      defaultDurationSeconds: int.tryParse(map['default_duration'] ?? '') ?? 30,
      durationOptions:
          options.isEmpty ? [15, 20, 30, 45, 60, 90, 120] : options,
    );
  }

  Future<void> saveSettings(AppSettingsEntity s) async {
    final db = await _db.database;
    final batch = db.batch();
    void upsert(String k, String v) => batch.insert(
          'settings',
          {'key': k, 'value': v},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
    upsert('teacher_password', s.teacherPassword);
    upsert('student_password', s.studentPassword);
    upsert('quiz_title', s.quizTitle);
    upsert('default_duration', s.defaultDurationSeconds.toString());
    upsert('duration_options', s.durationOptions.join(','));
    await batch.commit(noResult: true);
  }

  // ── Session (usuário logado) ───────────────────────────────────────────────

  Future<void> saveSession(LocalUserEntity user) async {
    final db = await _db.database;
    final batch = db.batch();
    void upsert(String k, String v) => batch.insert(
          'settings',
          {'key': k, 'value': v},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
    upsert('session_id', user.id.toString());
    upsert('session_name', user.name);
    upsert('session_is_teacher', user.isTeacher ? '1' : '0');
    await batch.commit(noResult: true);
  }

  Future<LocalUserEntity?> loadSession() async {
    final db = await _db.database;
    final rows = await db.query(
      'settings',
      where: "key IN ('session_id','session_name','session_is_teacher')",
    );
    final map = {
      for (final r in rows) r['key'] as String: r['value'] as String
    };
    final id = int.tryParse(map['session_id'] ?? '');
    final name = map['session_name'];
    if (id == null || name == null) return null;
    return LocalUserEntity(
      id: id,
      name: name,
      isTeacher: map['session_is_teacher'] == '1',
    );
  }

  Future<void> clearSession() async {
    final db = await _db.database;
    await db.delete(
      'settings',
      where: "key IN ('session_id','session_name','session_is_teacher')",
    );
  }

  // ── Students ──────────────────────────────────────────────────────────────

  Future<List<StudentEntity>> loadStudents() async {
    final db = await _db.database;
    final rows = await db.query('students', orderBy: 'name ASC');
    return rows
        .map(
            (r) => StudentEntity(id: r['id'] as int, name: r['name'] as String))
        .toList();
  }

  Future<StudentEntity?> getStudentByName(String name) async {
    final db = await _db.database;
    final rows =
        await db.query('students', where: 'name = ?', whereArgs: [name.trim()]);
    if (rows.isEmpty) return null;
    return StudentEntity(
        id: rows.first['id'] as int, name: rows.first['name'] as String);
  }

  Future<void> replaceStudentList(List<String> names) async {
    final db = await _db.database;
    final batch = db.batch();
    batch.delete('students');
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final name in names) {
      if (name.trim().isEmpty) continue;
      batch.insert(
        'students',
        {'name': name.trim(), 'created_at': now},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  // ── Quizzes ───────────────────────────────────────────────────────────────

  Future<List<LocalQuizEntity>> loadQuizzes() async {
    final db = await _db.database;
    final rows = await db.query('quizzes', orderBy: 'created_at DESC');
    return rows
        .map((r) =>
            LocalQuizEntity(id: r['id'] as int, name: r['name'] as String))
        .toList();
  }

  Future<LocalQuizEntity> saveQuiz(
      String name, List<QuestionEntity> questions) async {
    final db = await _db.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final quizId =
        await db.insert('quizzes', {'name': name, 'created_at': now});
    final batch = db.batch();
    for (final q in questions) {
      batch.insert('questions', {
        'quiz_id': quizId,
        'slot': q.slot,
        'type': q.type,
        'data': _encodeQuestion(q),
      });
    }
    await batch.commit(noResult: true);
    return LocalQuizEntity(id: quizId, name: name, questions: questions);
  }

  Future<LocalQuizEntity?> loadQuizWithQuestions(int quizId) async {
    final db = await _db.database;
    final quizRows =
        await db.query('quizzes', where: 'id = ?', whereArgs: [quizId]);
    if (quizRows.isEmpty) return null;
    final name = quizRows.first['name'] as String;
    final qRows = await db.query(
      'questions',
      where: 'quiz_id = ?',
      whereArgs: [quizId],
      orderBy: 'slot ASC',
    );
    final questions = qRows.map(_decodeQuestion).toList();
    return LocalQuizEntity(id: quizId, name: name, questions: questions);
  }

  Future<void> deleteQuiz(int quizId) async {
    final db = await _db.database;
    await db.delete('questions', where: 'quiz_id = ?', whereArgs: [quizId]);
    await db.delete('quizzes', where: 'id = ?', whereArgs: [quizId]);
  }

  // ── Quiz Session ──────────────────────────────────────────────────────────

  Future<int> createSession(int quizId, String quizTitle) async {
    final db = await _db.database;
    return db.insert('quiz_sessions', {
      'quiz_id': quizId,
      'status': 'waiting',
      'current_slot': 0,
      'current_page': -1,
      'total_pages': 0,
      'duration_seconds': 30,
      'start_on_first_response': 1,
      'timer_started': 0,
      'started_at': null,
      'ends_at': null,
      'round_id': '',
      'quiz_title': quizTitle,
    });
  }

  Future<void> updateSession(int sessionId, QuizStateEntity state) async {
    final db = await _db.database;
    await db.update(
      'quiz_sessions',
      {
        'status': state.status.name,
        'current_slot': state.currentSlot,
        'current_page': state.currentPage,
        'total_pages': state.totalPages,
        'duration_seconds': state.durationSeconds,
        'start_on_first_response': state.startOnFirstResponse ? 1 : 0,
        'timer_started': state.timerStarted ? 1 : 0,
        'started_at': state.startedAt?.millisecondsSinceEpoch,
        'ends_at': state.endsAt?.millisecondsSinceEpoch,
        'round_id': state.roundId,
        'quiz_title': state.quizTitle,
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<QuizStateEntity?> getSessionState(int sessionId) async {
    final db = await _db.database;
    final rows = await db.query(
      'quiz_sessions',
      where: 'id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _rowToState(rows.first);
  }

  Future<int?> getLatestSessionId(int quizId) async {
    final db = await _db.database;
    final rows = await db.query(
      'quiz_sessions',
      where: 'quiz_id = ?',
      whereArgs: [quizId],
      orderBy: 'id DESC',
      limit: 1,
      columns: ['id'],
    );
    return rows.isEmpty ? null : rows.first['id'] as int;
  }

  Future<QuizStateEntity?> loadLatestSession(int quizId) async {
    final db = await _db.database;
    final rows = await db.query(
      'quiz_sessions',
      where: 'quiz_id = ?',
      whereArgs: [quizId],
      orderBy: 'id DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _rowToState(rows.first);
  }

  QuizStateEntity _rowToState(Map<String, dynamic> r) {
    final startedMs = r['started_at'] as int?;
    final endsMs = r['ends_at'] as int?;
    return QuizStateEntity(
      status: _parseStatus(r['status'] as String? ?? 'waiting'),
      currentSlot: r['current_slot'] as int? ?? 0,
      currentPage: r['current_page'] as int? ?? -1,
      totalPages: r['total_pages'] as int? ?? 0,
      quizId: r['quiz_id'] as int? ?? 0,
      courseId: 0,
      quizTitle: r['quiz_title'] as String? ?? '',
      roundId: r['round_id'] as String? ?? '',
      durationSeconds: r['duration_seconds'] as int? ?? 30,
      startOnFirstResponse: (r['start_on_first_response'] as int? ?? 1) == 1,
      timerStarted: (r['timer_started'] as int? ?? 0) == 1,
      startedAt: startedMs != null
          ? DateTime.fromMillisecondsSinceEpoch(startedMs)
          : null,
      endsAt:
          endsMs != null ? DateTime.fromMillisecondsSinceEpoch(endsMs) : null,
    );
  }

  static QuizStatus _parseStatus(String s) => switch (s) {
        'active' => QuizStatus.active,
        'closed' => QuizStatus.closed,
        'finished' => QuizStatus.finished,
        _ => QuizStatus.waiting,
      };

  // ── Answers ───────────────────────────────────────────────────────────────

  Future<void> saveAnswer(AnswerRecordEntity answer) async {
    final db = await _db.database;
    await db.insert(
      'answers',
      {
        'session_id': answer.sessionId,
        'student_id': answer.studentId,
        'question_slot': answer.questionSlot,
        'round_id': answer.roundId,
        'answer_data': jsonEncode(answer.answerData),
        'is_correct': answer.isCorrect ? 1 : 0,
        'score': answer.score,
        'answered_at': answer.answeredAt.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> hasStudentAnswered(
      int sessionId, int studentId, int questionSlot, String roundId) async {
    final db = await _db.database;
    final rows = await db.query(
      'answers',
      where: 'session_id=? AND student_id=? AND question_slot=? AND round_id=?',
      whereArgs: [sessionId, studentId, questionSlot, roundId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<List<ScoreEntity>> loadScores(int sessionId) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT
        s.id                                                      AS student_id,
        s.name                                                    AS student_name,
        SUM(a.score)                                              AS total_score,
        SUM(a.is_correct)                                         AS correct_count,
        COUNT(a.id)                                               AS total_answered,
        GROUP_CONCAT(a.question_slot || ':' || a.round_id, '|')  AS pages_info
      FROM answers a
      JOIN students s ON s.id = a.student_id
      WHERE a.session_id = ?
      GROUP BY s.id
      ORDER BY total_score DESC
    ''', [sessionId]);

    final result = <ScoreEntity>[];
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final pagesInfo = r['pages_info'] as String? ?? '';
      final answeredPages = <int>[];
      final answeredPageRounds = <int, String>{};
      for (final part in pagesInfo.split('|')) {
        final idx = part.indexOf(':');
        if (idx > 0) {
          final slot = int.tryParse(part.substring(0, idx));
          if (slot != null) {
            answeredPages.add(slot);
            answeredPageRounds[slot] = part.substring(idx + 1);
          }
        }
      }
      result.add(ScoreEntity(
        studentId: (r['student_id'] as int).toString(),
        studentName: r['student_name'] as String,
        score: (r['total_score'] as num?)?.toInt() ?? 0,
        correctCount: (r['correct_count'] as num?)?.toInt() ?? 0,
        totalAnswered: (r['total_answered'] as num?)?.toInt() ?? 0,
        rank: i + 1,
        answeredPages: answeredPages,
        answeredPageRounds: answeredPageRounds,
      ));
    }
    return result;
  }

  Future<void> deleteSessionAnswers(int sessionId) async {
    final db = await _db.database;
    await db.delete('answers', where: 'session_id=?', whereArgs: [sessionId]);
  }

  // ── Question serialization ────────────────────────────────────────────────

  String _encodeQuestion(QuestionEntity q) => jsonEncode({
        'slot': q.slot,
        'page': q.page,
        'text': q.text,
        'htmlText': q.htmlText,
        'displayHtml': q.displayHtml,
        'type': q.type,
        'generalFeedback': q.generalFeedback,
        'rightAnswerHtml': q.rightAnswerHtml,
        'inputBaseName': q.inputBaseName,
        'seqCheck': q.seqCheck,
        'answerInputName': q.answerInputName,
        'imageUrls': q.imageUrls,
        'choices': q.choices.map(_encodeChoice).toList(),
        'answerControls': q.answerControls.map(_encodeControl).toList(),
        'matchData': q.matchData == null ? null : _encodeMatch(q.matchData!),
        'gapInputData':
            q.gapInputData == null ? null : _encodeGap(q.gapInputData!),
      });

  QuestionEntity _decodeQuestion(Map<String, dynamic> row) {
    final data = jsonDecode(row['data'] as String) as Map<String, dynamic>;
    return QuestionEntity(
      slot: data['slot'] as int? ?? 1,
      page: data['page'] as int? ?? 0,
      text: data['text'] as String? ?? '',
      htmlText: data['htmlText'] as String? ?? '',
      displayHtml: data['displayHtml'] as String? ?? '',
      type: data['type'] as String? ?? 'multichoice',
      generalFeedback: data['generalFeedback'] as String? ?? '',
      rightAnswerHtml: data['rightAnswerHtml'] as String? ?? '',
      inputBaseName: data['inputBaseName'] as String? ?? '',
      seqCheck: data['seqCheck'] as String? ?? '',
      answerInputName: data['answerInputName'] as String?,
      imageUrls: (data['imageUrls'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      choices:
          (data['choices'] as List<dynamic>? ?? []).map(_decodeChoice).toList(),
      answerControls: (data['answerControls'] as List<dynamic>? ?? [])
          .map(_decodeControl)
          .toList(),
      matchData:
          data['matchData'] == null ? null : _decodeMatch(data['matchData']),
      gapInputData: data['gapInputData'] == null
          ? null
          : _decodeGap(data['gapInputData']),
    );
  }

  Map<String, dynamic> _encodeChoice(ParsedChoice c) => {
        'value': c.value,
        'text': c.text,
        'htmlText': c.htmlText,
        'isCorrect': c.isCorrect,
      };

  ParsedChoice _decodeChoice(dynamic d) {
    final m = d as Map<String, dynamic>;
    return ParsedChoice(
      value: m['value'] as String? ?? '',
      text: m['text'] as String? ?? '',
      htmlText: m['htmlText'] as String? ?? '',
      isCorrect: m['isCorrect'] as bool? ?? false,
    );
  }

  Map<String, dynamic> _encodeControl(MoodleAnswerControl c) => {
        'type': c.type,
        'name': c.name,
        'value': c.value,
        'label': c.label,
        'htmlLabel': c.htmlLabel,
        'options': c.options.map(_encodeChoice).toList(),
      };

  MoodleAnswerControl _decodeControl(dynamic d) {
    final m = d as Map<String, dynamic>;
    return MoodleAnswerControl(
      type: m['type'] as String? ?? 'text',
      name: m['name'] as String? ?? '',
      value: m['value'] as String? ?? '',
      label: m['label'] as String? ?? '',
      htmlLabel: m['htmlLabel'] as String? ?? '',
      options:
          (m['options'] as List<dynamic>? ?? []).map(_decodeChoice).toList(),
    );
  }

  Map<String, dynamic> _encodeMatch(MatchData m) => {
        'subQuestions': m.subQuestions
            .map((s) => {
                  'text': s.text,
                  'htmlText': s.htmlText,
                  'inputName': s.inputName,
                  'correctValue': s.correctValue,
                })
            .toList(),
        'options': m.options.map(_encodeChoice).toList(),
      };

  MatchData _decodeMatch(dynamic d) {
    final m = d as Map<String, dynamic>;
    return MatchData(
      subQuestions: (m['subQuestions'] as List<dynamic>? ?? []).map((s) {
        final sm = s as Map<String, dynamic>;
        return MatchSubQuestion(
          text: sm['text'] as String? ?? '',
          htmlText: sm['htmlText'] as String? ?? '',
          inputName: sm['inputName'] as String? ?? '',
          correctValue: sm['correctValue'] as String?,
        );
      }).toList(),
      options:
          (m['options'] as List<dynamic>? ?? []).map(_decodeChoice).toList(),
    );
  }

  Map<String, dynamic> _encodeGap(GapInputData g) => {
        'inputNamePrefix': g.inputNamePrefix,
        'gapCount': g.gapCount,
        'options': g.options.map(_encodeChoice).toList(),
        'optionsByGap': g.optionsByGap
            .map((list) => list.map(_encodeChoice).toList())
            .toList(),
      };

  GapInputData _decodeGap(dynamic d) {
    final m = d as Map<String, dynamic>;
    final rawByGap = m['optionsByGap'] as List<dynamic>? ?? [];
    return GapInputData(
      inputNamePrefix: m['inputNamePrefix'] as String? ?? '',
      gapCount: m['gapCount'] as int? ?? 0,
      options:
          (m['options'] as List<dynamic>? ?? []).map(_decodeChoice).toList(),
      optionsByGap: rawByGap
          .map((list) => (list as List<dynamic>).map(_decodeChoice).toList())
          .toList(),
    );
  }
}
