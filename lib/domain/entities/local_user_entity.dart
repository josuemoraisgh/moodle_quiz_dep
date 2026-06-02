import 'package:equatable/equatable.dart';

/// Usuário local – professor ou aluno. Sem token ou URL de rede.
class LocalUserEntity extends Equatable {
  final int id;
  final String name;
  final bool isTeacher;
  final String username;
  final String token;
  final String baseUrl;
  final int courseId;
  final Set<String> availableFunctions;

  const LocalUserEntity({
    required this.id,
    required this.name,
    required this.isTeacher,
    this.username = '',
    this.token = '',
    this.baseUrl = '',
    this.courseId = 0,
    this.availableFunctions = const {},
  });

  String get fullname => name;
  bool get isOnlineUser => token.isNotEmpty && baseUrl.isNotEmpty;

  /// Convidado: acesso somente-leitura sem cadastro.
  bool get isGuest => id == -1 && !isTeacher;

  /// Aluno: usuário autenticado que aguarda questões liberadas pelo professor.
  bool get isStudent => !isTeacher && !isGuest;

  @override
  List<Object?> get props => [
        id,
        name,
        isTeacher,
        username,
        token,
        baseUrl,
        courseId,
        availableFunctions,
      ];
}
