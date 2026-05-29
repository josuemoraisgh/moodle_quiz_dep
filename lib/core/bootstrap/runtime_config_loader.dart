import 'dart:convert';

import 'package:flutter/services.dart';

import '../config/app_config.dart';
import '../config/quiz_runtime_config.dart';

Future<QuizRuntimeConfig> loadRuntimeConfig() async {
  try {
    final raw = await rootBundle.loadString('assets/config.json');
    final map = jsonDecode(raw) as Map<String, dynamic>;
    AppConfig.loadFromMap(map);
    return QuizRuntimeConfig.fromMap(map);
  } catch (_) {
    return QuizRuntimeConfig.offline(
      localServerPort: AppConfig.localServerPort,
    );
  }
}
