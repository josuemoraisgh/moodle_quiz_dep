import 'package:equatable/equatable.dart';

/// Usuário local – professor ou aluno. Sem token ou URL de rede.
class LocalUserEntity extends Equatable {
  final int id;
  final String name;
  final bool isTeacher;

  const LocalUserEntity({
    required this.id,
    required this.name,
    required this.isTeacher,
  });

  String get fullname => name;

  @override
  List<Object?> get props => [id, name, isTeacher];
}
