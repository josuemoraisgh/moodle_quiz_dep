import 'package:equatable/equatable.dart';

/// Aluno cadastrado pelo professor.
class StudentEntity extends Equatable {
  final int id;
  final String name;

  const StudentEntity({required this.id, required this.name});

  @override
  List<Object?> get props => [id, name];
}
