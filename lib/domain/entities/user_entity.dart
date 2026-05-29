import 'package:equatable/equatable.dart';

/// Entidade de usuário – sem dependência de frameworks externos.
class UserEntity extends Equatable {
  final int id;
  final String username;
  final String fullname;
  final String token;
  final String baseUrl;
  final bool isTeacher;
  final Set<String> availableFunctions;

  const UserEntity({
    required this.id,
    required this.username,
    required this.fullname,
    required this.token,
    required this.baseUrl,
    required this.isTeacher,
    this.availableFunctions = const {},
  });

  bool hasFunction(String fn) => availableFunctions.contains(fn);

  @override
  List<Object?> get props =>
      [id, username, token, baseUrl, isTeacher];
}
