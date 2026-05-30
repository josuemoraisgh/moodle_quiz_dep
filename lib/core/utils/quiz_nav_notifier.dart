import 'package:flutter/foundation.dart';

/// Callback de login exposto pela [GuestQuestionPage] para componentes externos.
///
/// O [GuestQuestionPage] define o valor quando o usuário não está logado;
/// o [PresentationViewer] (ou qualquer viewer externo) lê e exibe o botão.
/// Zerado automaticamente quando a página é desmontada.
final ValueNotifier<VoidCallback?> quizLoginNotifier =
    ValueNotifier<VoidCallback?>(null);
