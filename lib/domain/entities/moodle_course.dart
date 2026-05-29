import 'package:equatable/equatable.dart';

class MoodleCourse extends Equatable {
  final int id;
  final String shortname;
  final String fullname;

  const MoodleCourse({
    required this.id,
    required this.shortname,
    required this.fullname,
  });

  factory MoodleCourse.fromJson(Map<String, dynamic> json) => MoodleCourse(
        id: (json['id'] as num).toInt(),
        shortname: json['shortname']?.toString() ?? '',
        fullname: json['fullname']?.toString() ?? '',
      );

  @override
  List<Object?> get props => [id];
}
