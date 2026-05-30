import 'package:flutter/foundation.dart';

/// Callback de login exposto pela [GuestQuestionPage] quando o usuário NÃO
/// está autenticado. O [PresentationViewer] lê e exibe o botão de login.
final ValueNotifier<VoidCallback?> quizLoginNotifier =
    ValueNotifier<VoidCallback?>(null);

/// Callback de logout exposto pela [GuestQuestionPage] quando o usuário ESTÁ
/// autenticado. O [PresentationViewer] lê e exibe o botão de logout.
/// Mutuamente exclusivo com [quizLoginNotifier].
final ValueNotifier<VoidCallback?> quizLogoutNotifier =
    ValueNotifier<VoidCallback?>(null);
