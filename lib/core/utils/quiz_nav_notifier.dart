import 'package:flutter/material.dart';

import '../../domain/entities/local_user_entity.dart';

/// Sessão global do quiz — atualizada por [InMemoryAuthRepository] a cada
/// login/logout. O [PresentationViewer] usa isto para exibir o overlay de
/// autenticação antes de qualquer slide.
final ValueNotifier<LocalUserEntity?> quizGlobalUserNotifier =
    ValueNotifier<LocalUserEntity?>(null);

/// Callback de login exposto quando o usuário NÃO está autenticado.
/// O [PresentationViewer] lê e exibe o botão de login.
final ValueNotifier<VoidCallback?> quizLoginNotifier =
    ValueNotifier<VoidCallback?>(null);

/// Callback de logout exposto quando o usuário ESTÁ autenticado.
/// Mutuamente exclusivo com [quizLoginNotifier].
final ValueNotifier<VoidCallback?> quizLogoutNotifier =
    ValueNotifier<VoidCallback?>(null);

/// Verdadeiro enquanto um ALUNO (não convidado, não professor) está logado
/// no quiz. O [PresentationViewer] usa isso para ativar o modo takeover
/// (quiz ocupa toda a tela, sem chrome da apresentação).
final ValueNotifier<bool> quizStudentModeNotifier =
    ValueNotifier<bool>(false);

/// Conta quantas instâncias de QuizSlideHost estão montadas simultaneamente.
/// Pode ser > 1 durante a transição do AnimatedSwitcher (saindo + entrando).
/// Gerenciado exclusivamente por [QuizSlideHost].initState / dispose.
int _quizWidgetMountCount = 0;

/// True enquanto pelo menos um QuizSlideHost estiver montado.
bool get quizWidgetMounted => _quizWidgetMountCount > 0;

/// Incrementa o contador ao montar um QuizSlideHost.
void mountQuizWidget() {
  _quizWidgetMountCount++;
}

/// Decrementa o contador ao desmontar um QuizSlideHost.
/// Retorna true se não restam mais instâncias montadas.
bool unmountQuizWidget() {
  if (_quizWidgetMountCount > 0) _quizWidgetMountCount--;
  return _quizWidgetMountCount == 0;
}

/// Verdadeiro quando o widget de quiz precisa ocupar a tela toda (sem chrome
/// da apresentação). Controlado por [QuizSlideHost] + [AuthController]:
///   • [QuizSlideHost].initState → true  (inclusive durante o carregamento)
///   • [QuizSlideHost].dispose   → false
///   • [AuthController]: false apenas quando convidado está logado
final ValueNotifier<bool> quizNeedsFullscreenNotifier =
    ValueNotifier<bool>(false);

/// Modo de tema global — compartilhado entre o [PresentationViewer] (que expõe
/// o botão de alternância) e o [MoodleQuizApp] (que aplica o tema ao MaterialApp).
/// Alterado pelo viewer; lido pelo shell do quiz.
final ValueNotifier<ThemeMode> quizThemeModeNotifier =
    ValueNotifier<ThemeMode>(ThemeMode.dark);
