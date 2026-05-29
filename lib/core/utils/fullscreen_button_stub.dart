import 'package:flutter/material.dart';

/// Implementação no-op para plataformas não web.
class FullscreenButton extends StatelessWidget {
  const FullscreenButton({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
