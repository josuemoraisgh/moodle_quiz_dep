/// Public API for using moodle_quiz_live as a Flutter package dependency.
///
/// Add to your pubspec.yaml:
/// ```yaml
/// dependencies:
///   moodle_quiz_live:
///     path: ../moodle_quiz_live   # or git: / hosted:
/// ```
///
/// Usage:
/// ```dart
/// import 'package:moodle_quiz_live/moodle_quiz_live.dart';
///
/// MoodleQuizEmbed(
///   config: MoodleQuizConfig(
///     moodleUrl: 'https://moodle.ufu.br',
///     token: 'abc123',
///     userId: 42,
///     courseId: 10,
///     quizId: 3,
///     questionSlot: 1,
///   ),
///   onAnswered: (correct, score) { ... },
/// )
/// ```
library;

export 'quiz_embed/quiz_embed_config.dart';
export 'quiz_embed/moodle_quiz_embed.dart' show MoodleQuizEmbed;
