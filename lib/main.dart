import 'package:flutter/material.dart';

import 'core/bootstrap/default_app_factory.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(await buildDefaultApp());
}
