import 'package:equatable/equatable.dart';

class MoodleQuiz extends Equatable {
  final int id;
  final int courseId;
  final String name;
  final int? timeLimit;    // segundos; null = sem limite
  final int attempts;      // máximo de tentativas permitidas
  final String intro;      // descrição HTML
  final String preferredBehaviour; // ex: 'immediatefeedback', 'deferredfeedback'
  final int reviewCorrectness;    // bitmask de opções de revisão

  const MoodleQuiz({
    required this.id,
    required this.courseId,
    required this.name,
    this.timeLimit,
    this.attempts = 0,
    this.intro = '',
    this.preferredBehaviour = '',
    this.reviewCorrectness = 0,
  });

  factory MoodleQuiz.fromJson(Map<String, dynamic> json) => MoodleQuiz(
        id: (json['id'] as num).toInt(),
        courseId: (json['course'] as num? ?? 0).toInt(),
        name: json['name']?.toString() ?? '',
        timeLimit: json['timelimit'] == null || json['timelimit'] == 0
            ? null
            : (json['timelimit'] as num).toInt(),
        attempts: (json['attempts'] as num? ?? 0).toInt(),
        intro: json['intro']?.toString() ?? '',
        preferredBehaviour: json['preferredbehaviour']?.toString() ?? '',
        reviewCorrectness: (json['reviewcorrectness'] as num? ?? 0).toInt(),
      );

  /// Verifica se o quiz usa feedback imediato (immediatefeedback ou interactive).
  bool get isImmediateFeedback =>
      preferredBehaviour == 'immediatefeedback' ||
      preferredBehaviour == 'interactive';

  /// Verifica se "Se está correto" está habilitado durante a tentativa.
  /// Moodle usa bitmask: bit 0x10000 (65536) = DURING_ATTEMPT.
  /// reviewcorrectness & 0x10000 != 0 significa que está habilitado.
  bool get showsCorrectnessOnAttempt => (reviewCorrectness & 0x10000) != 0;

  /// Quiz está totalmente compatível com o MoodleQuiz Live.
  bool get isCompatible => isImmediateFeedback && showsCorrectnessOnAttempt;

  /// Retorna mensagens de incompatibilidade (vazio se compatível).
  List<String> get incompatibilityReasons {
    final reasons = <String>[];
    if (!isImmediateFeedback) {
      reasons.add('Comportamento deve ser "Feedback imediato" (atual: $preferredBehaviour)');
    }
    if (!showsCorrectnessOnAttempt) {
      reasons.add('Opções de revisão → "Se está correto" deve estar marcado durante tentativa');
    }
    return reasons;
  }

  @override
  List<Object?> get props => [id];
}
