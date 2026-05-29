import 'dart:convert';

import '../../core/utils/debug_logger.dart';
import '../../core/utils/moodle_html_parser.dart'
    show MoodleHtmlParser, ParsedChoice, MatchData, MatchSubQuestion;
import '../../domain/entities/moodle_course.dart';
import '../../domain/entities/moodle_quiz.dart';
import '../../domain/entities/question_entity.dart';
import '../../domain/entities/quiz_state_entity.dart';
import '../../domain/entities/score_entity.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/i_quiz_repository.dart';
import '../datasources/moodle_datasource.dart';
import '../datasources/moodle_state_datasource.dart';
import '../models/quiz_state_model.dart';
import '../models/score_model.dart';

/// L: Substitui IQuizRepository; D: depende de interfaces, não concretos.
class QuizRepositoryImpl implements IQuizRepository {
  final IStateDatasource _state;
  final IMoodleDatasource _moodle;

  Map<String, int> _prevRanks = {};

  QuizRepositoryImpl(this._state, this._moodle);

  // ── Moodle ─────────────────────────────────────────────────────────────────

  @override
  Future<List<MoodleCourse>> getCourses(UserEntity user) async {
    final list = await _moodle.getCourses(user.baseUrl, user.token, user.id);
    return list.map(MoodleCourse.fromJson).toList();
  }

  @override
  Future<List<MoodleQuiz>> getQuizzesByCourse(
      UserEntity user, int courseId) async {
    final list =
        await _moodle.getQuizzesByCourse(user.baseUrl, user.token, courseId);
    return list.map(MoodleQuiz.fromJson).toList();
  }

  @override
  Future<int> startAttempt(UserEntity user, int quizId,
      {void Function(String)? onLog}) async {
    void log(String m) => onLog?.call(m);

    // 1. Busca tentativa em andamento antes de criar
    log('Verificando tentativas existentes (status=unfinished)…');
    final existingId =
        await _getUnfinishedAttemptId(user, quizId, onLog: onLog);
    if (existingId != null) {
      log('Tentativa existente reutilizada: ID $existingId');
      return existingId;
    }

    // 2. Tenta criar nova tentativa
    log('Nenhuma encontrada — criando nova tentativa…');
    try {
      final id = await _moodle.startAttempt(user.baseUrl, user.token, quizId);
      log('Nova tentativa criada: ID $id');
      return id;
    } on MoodleException catch (e) {
      log('Moodle recusou [${e.errorCode ?? '?'}]: ${e.message}');

      // "quizalreadystarted": já existe tentativa aberta não listada antes
      final retryId = await _getUnfinishedAttemptId(user, quizId, onLog: onLog);
      if (retryId != null) {
        log('Tentativa encontrada na segunda busca: ID $retryId');
        return retryId;
      }
      log('Tentando status=all como último recurso…');
      final anyId = await _getUnfinishedAttemptId(user, quizId,
          status: 'all', onLog: onLog);
      if (anyId != null) {
        log('Tentativa encontrada (all): ID $anyId');
        return anyId;
      }

      // Verifica se há tentativa de preview bloqueando
      log('Verificando tentativas de pré-visualização…');
      final previewAttempts = await _moodle.getUserAttempts(
          user.baseUrl, user.token, quizId,
          status: 'all', userId: user.id, includePreviews: true);
      final previews = previewAttempts
          .where((a) =>
              (a['preview'] == 1 || a['preview'] == true) &&
              (a['state']?.toString() == 'inprogress' ||
                  a['state']?.toString() == 'overdue'))
          .toList();
      log('Previews em andamento: ${previews.length}');

      if (previews.isNotEmpty) {
        // Estratégia 1: forcenew=1 — o Moodle deleta previews internamente
        log('Tentando startAttempt com forcenew=1 (deleta previews automaticamente)…');
        try {
          final freshId = await _moodle
              .startAttempt(user.baseUrl, user.token, quizId, forcenew: true);
          log('Nova tentativa criada com forcenew: ID $freshId');
          return freshId;
        } catch (forceErr) {
          log('forcenew falhou [${forceErr is MoodleException ? forceErr.errorCode ?? "?" : "?"}]: $forceErr');
        }

        // Estratégia 2: deletar preview via API
        for (final preview in previews) {
          final pid = (preview['id'] as num?)?.toInt() ?? 0;
          log('Tentando deletar preview ID $pid…');
          try {
            await _moodle.deleteAttempt(user.baseUrl, user.token, pid);
            log('Preview $pid deletado — criando nova tentativa…');
            final freshId =
                await _moodle.startAttempt(user.baseUrl, user.token, quizId);
            log('Nova tentativa criada: ID $freshId');
            return freshId;
          } catch (deleteErr) {
            log('deleteAttempt($pid) falhou [${deleteErr is MoodleException ? deleteErr.errorCode ?? "?" : "?"}]: $deleteErr');
          }
        }

        // Estratégia 3: finalizar preview com timeup
        for (final preview in previews) {
          final pid = (preview['id'] as num?)?.toInt() ?? 0;
          log('Tentando finalizar preview ID $pid com timeup…');
          try {
            await _moodle.finishAttempt(user.baseUrl, user.token, pid,
                timeup: true);
            log('Preview $pid finalizado — criando nova tentativa…');
            final freshId =
                await _moodle.startAttempt(user.baseUrl, user.token, quizId);
            log('Nova tentativa criada: ID $freshId');
            return freshId;
          } catch (finishErr) {
            log('finishAttempt($pid) falhou [${finishErr is MoodleException ? finishErr.errorCode ?? "?" : "?"}]: $finishErr');
          }
        }

        throw MoodleException(
          'Existe uma tentativa de pré-visualização bloqueando o quiz (ID: ${previews.map((p) => p["id"]).join(", ")}). '
          'Acesse Moodle → Quiz → Resultados → Tentativas e delete a tentativa de pré-visualização, depois clique em Reiniciar Quiz.',
          errorCode: 'previewblocking',
        );
      }
      rethrow;
    }
  }

  Future<int?> _getUnfinishedAttemptId(UserEntity user, int quizId,
      {String status = 'unfinished',
      bool includePreviews = false,
      void Function(String)? onLog}) async {
    void log(String m) => onLog?.call(m);
    try {
      final attempts = await _moodle.getUserAttempts(
          user.baseUrl, user.token, quizId,
          status: status, userId: user.id, includePreviews: includePreviews);
      log('  getUserAttempts($status): ${attempts.length} resultado(s)');
      for (final a in attempts) {
        log('    id=${a['id']} state=${a['state']}');
      }
      if (attempts.isNotEmpty) {
        final inprogress = attempts
            .where((a) =>
                a['state']?.toString() == 'inprogress' ||
                a['state']?.toString() == 'overdue')
            .toList();
        // Nunca retorna tentativa finalizada — apenas inprogress/overdue
        if (inprogress.isEmpty) return null;
        return (inprogress.first['id'] as num?)?.toInt();
      }
    } catch (e) {
      log('  getUserAttempts($status) ERRO: $e');
    }
    return null;
  }

  @override
  Future<QuestionEntity> getQuestion(
      UserEntity user, int attemptId, int slot) async {
    final dlog = DebugLogger.instance;
    dlog.separator('GET QUESTION');
    dlog.log('QUESTION', 'Buscando questão slot=$slot attemptId=$attemptId');

    // Tenta page=0 primeiro (cobre quizzes com todas as questões na mesma página)
    Map<String, dynamic>? qMap = await _findQuestionBySlot(
        user.baseUrl, user.token, attemptId, slot,
        moodlePage: 0);

    // Fallback: quiz com 1 questão por página (slot N está na página N-1)
    if (qMap == null && slot > 1) {
      dlog.log(
          'QUESTION', 'Não encontrada na page=0, tentando page=${slot - 1}');
      qMap = await _findQuestionBySlot(
          user.baseUrl, user.token, attemptId, slot,
          moodlePage: slot - 1);
    }

    if (qMap == null) {
      dlog.log('QUESTION', '✗ Questão slot=$slot NÃO encontrada');
      throw Exception(
          'Questão com slot $slot não encontrada na tentativa $attemptId');
    }

    final html = qMap['html'] as String? ?? '';
    final actualSlot = (qMap['slot'] as num? ?? slot).toInt();
    final moodleType = qMap['type']?.toString() ?? '';

    dlog.log('QUESTION', 'HTML recebido do Moodle', data: {
      'slot': actualSlot,
      'page': qMap['page'],
      'state': qMap['state'],
      'moodleType': moodleType,
      'htmlLength': html.length,
      'htmlPreview': html.length > 300 ? '${html.substring(0, 300)}…' : html,
    });

    final parsed = MoodleHtmlParser.parse(
      html: html,
      attemptId: attemptId,
      slot: actualSlot,
      token: user.token,
      baseUrl: user.baseUrl,
    );

    // Usa o tipo real da API do Moodle; cai para o inferido pelo HTML só se ausente.
    final resolvedType = moodleType.isNotEmpty ? moodleType : parsed.type;

    dlog.log('QUESTION', 'Questão parseada', data: {
      'inputBaseName': parsed.inputBaseName,
      'hardcoded_seria': 'q$attemptId:${actualSlot}_answer',
      'base_difere': parsed.inputBaseName != 'q$attemptId:${actualSlot}_answer'
          ? '⚠️ SIM — ID real ≠ attemptId!'
          : 'não (iguais)',
      'seqCheck': parsed.seqCheck,
      'moodleType': moodleType,
      'resolvedType': resolvedType,
      'choicesCount': parsed.choices.length,
      'choices': parsed.choices
          .map((c) => 'value="${c.value}" text="${c.text}"')
          .join(' | '),
    });

    return QuestionEntity(
      slot: parsed.slot,
      page: (qMap['page'] as num? ?? 0).toInt(),
      text: parsed.text,
      htmlText: parsed.htmlText,
      displayHtml: parsed.displayHtml,
      choices: parsed.choices,
      imageUrls: parsed.imageUrls,
      inputBaseName: parsed.inputBaseName,
      seqCheck: parsed.seqCheck,
      type: resolvedType,
      answerControls: parsed.answerControls,
      answerInputName: parsed.answerInputName,
      matchData: parsed.matchData,
      gapInputData: parsed.gapInputData,
      ddMarkerData: parsed.ddMarkerData,
    );
  }

  /// Busca a questão com determinado [slot] na [moodlePage] da tentativa.
  /// Retorna null se não encontrada.
  Future<Map<String, dynamic>?> _findQuestionBySlot(
      String baseUrl, String token, int attemptId, int slot,
      {required int moodlePage}) async {
    try {
      final data =
          await _moodle.getAttemptData(baseUrl, token, attemptId, moodlePage);
      final questions = data['questions'] as List? ?? [];
      for (final q in questions) {
        final qMap = Map<String, dynamic>.from(q as Map);
        final qSlot = (qMap['slot'] as num?)?.toInt();
        if (qSlot == slot) return qMap;
      }
    } catch (_) {}
    return null;
  }

  /// Carrega todas as questões do quiz usando UMA attempt, depois a finaliza
  /// e busca as respostas corretas via revisão. Usa nextpage do Moodle para
  /// navegar corretamente independente de quantas questões há por página.
  @override
  Future<List<QuestionEntity>> loadQuestionsWithAnswers(
      UserEntity user, int attemptId, int totalPages,
      {void Function(String)? onLog}) async {
    void log(String msg) => onLog?.call(msg);

    // 1. Carrega todas as páginas usando nextpage do Moodle
    final allQuestions = <QuestionEntity>[];
    final slotToPage = <int, int>{};
    int page = 0;
    int pageCount = 0;

    log('Carregando páginas da tentativa $attemptId…');
    while (page >= 0) {
      try {
        log('  → Buscando página $page…');
        final data = await _moodle.getAttemptData(
            user.baseUrl, user.token, attemptId, page);

        final questions = data['questions'] as List? ?? [];
        log('  → Página $page: ${questions.length} questão(ões) retornada(s)');

        for (final q in questions) {
          final qMap = Map<String, dynamic>.from(q as Map);
          final html = qMap['html'] as String? ?? '';
          final slot = (qMap['slot'] as num? ?? 1).toInt();
          final qPage = (qMap['page'] as num? ?? page).toInt();
          final type = qMap['type']?.toString() ?? '';

          log('     raw slot=$slot page=$qPage tipo=${type.isEmpty ? "?" : type} '
              'len=${html.length} flags=${_diagnosticFlags(html)} '
              'plain="${_diagnosticSnippet(_plainDiagnostic(html), 500)}"');

          final parsed = MoodleHtmlParser.parse(
            html: html,
            attemptId: attemptId,
            slot: slot,
            token: user.token,
            baseUrl: user.baseUrl,
          );

          // Usa o tipo real da API do Moodle; cai para o inferido pelo HTML só se ausente.
          final resolvedType = type.isNotEmpty ? type : parsed.type;
          log('     slot=$slot page=$qPage tipo=$resolvedType alternativas=${parsed.choices.length}');
          log('     parsed slot=$slot textLen=${parsed.text.length} '
              'htmlLen=${parsed.htmlText.length} displayLen=${parsed.displayHtml.length} '
              'gap=${parsed.gapInputData?.gapCount ?? 0} '
              'gapOptions=${parsed.gapInputData?.options.length ?? 0} '
              'gapGroups=${parsed.gapInputData?.optionsByGap.length ?? 0} '
              'flagsText=${_diagnosticFlags(parsed.text)} '
              'flagsHtml=${_diagnosticFlags(parsed.htmlText)} '
              'flagsDisplay=${_diagnosticFlags(parsed.displayHtml)}');
          if (resolvedType == 'gapselect' || resolvedType == 'ddwtos') {
            _logGapPromptDiagnostics(
              log,
              slot: slot,
              label: 'htmlText',
              html: parsed.htmlText,
            );
            _logGapPromptDiagnostics(
              log,
              slot: slot,
              label: 'displayHtml',
              html: parsed.displayHtml,
            );
          }

          allQuestions.add(QuestionEntity(
            slot: parsed.slot,
            page: qPage,
            text: parsed.text,
            htmlText: parsed.htmlText,
            displayHtml: parsed.displayHtml,
            choices: parsed.choices,
            imageUrls: parsed.imageUrls,
            inputBaseName: parsed.inputBaseName,
            seqCheck: parsed.seqCheck,
            type: resolvedType,
            answerControls: parsed.answerControls,
            answerInputName: parsed.answerInputName,
            matchData: parsed.matchData,
            gapInputData: parsed.gapInputData,
            ddMarkerData: parsed.ddMarkerData,
          ));
          slotToPage[slot] = qPage;
        }

        // nextpage == -1 significa última página
        final nextPage = (data['nextpage'] as num? ?? -1).toInt();
        log('  → nextpage=$nextPage');
        page = nextPage;
        pageCount++;
      } catch (e) {
        log('  → ERRO ao buscar página $page: $e');
        break;
      }
    }

    log('Total bruto: ${allQuestions.length} questões em $pageCount página(s)');
    if (allQuestions.isEmpty) return allQuestions;

    await _saveProbeAnswersForReview(user, attemptId, allQuestions, log);

    // 2. Finaliza a attempt para liberar revisão
    log('Finalizando attempt para obter revisão…');
    try {
      await _moodle.finishAttempt(user.baseUrl, user.token, attemptId);
      log('Attempt finalizado com sucesso');
    } catch (e) {
      log('AVISO: finishAttempt falhou ($e) — respostas corretas não disponíveis');
      return allQuestions;
    }

    // 3. Busca revisão e marca isCorrect — agrupa por página
    final reviewPages = slotToPage.values.toSet();
    final reviewHtmlBySlot = <int, String>{};

    log('Buscando revisão em ${reviewPages.length} página(s)…');
    for (final reviewPage in reviewPages) {
      try {
        log('  → Revisão página $reviewPage…');
        final review = await _moodle.getAttemptReview(
            user.baseUrl, user.token, attemptId, reviewPage);
        int found = 0;
        for (final rq in (review['questions'] as List? ?? [])) {
          final rqMap = rq as Map;
          final slot = (rqMap['slot'] as num?)?.toInt();
          final html = rqMap['html'] as String? ?? '';
          if (slot != null && html.isNotEmpty) {
            reviewHtmlBySlot[slot] = html;
            found++;
          }
        }
        log('  → $found slot(s) com HTML de revisão');
      } catch (e) {
        log('  → ERRO na revisão página $reviewPage: $e');
      }
    }

    final result = <QuestionEntity>[];
    int skipped = 0;
    for (final q in allQuestions) {
      final reviewHtml = reviewHtmlBySlot[q.slot] ?? '';
      final feedback = reviewHtml.isEmpty
          ? ''
          : MoodleHtmlParser.parseGeneralFeedback(reviewHtml);
      var rightAnswerHtml = reviewHtml.isEmpty
          ? ''
          : MoodleHtmlParser.parseRightAnswerHtml(
              reviewHtml, user.token, user.baseUrl);
      if (rightAnswerHtml.isEmpty && reviewHtml.isNotEmpty) {
        rightAnswerHtml = _fallbackSelectRightAnswerHtml(
          q,
          MoodleHtmlParser.parseSelectedSelectAnswers(reviewHtml),
        );
      }

      // Questões sem alternativas de rádio: incluídas para somente leitura
      // (Numérica, Calculada, ShortAnswer, Match, GapSelect, Cloze…)
      if (q.choices.isEmpty) {
        log('  ○ slot=${q.slot} (${q.type}) sem alternativas de rádio'
            '${rightAnswerHtml.isNotEmpty ? ' — gabarito HTML extraído' : ''}');

        // Para match: marca respostas corretas via seleção no HTML de revisão
        final matchData = q.matchData;
        if (matchData != null && reviewHtml.isNotEmpty) {
          final correctPairs =
              MoodleHtmlParser.parseCorrectMatchValues(reviewHtml);
          if (correctPairs.isNotEmpty) {
            log('  ✓ slot=${q.slot} (match) pares corretos: $correctPairs');
          }
          // Marcamos as opções corretas nas sub-questões (para reveal page)
          final updatedSubQuestions = matchData.subQuestions
              .map((sub) => MatchSubQuestion(
                    text: sub.text,
                    htmlText: sub.htmlText,
                    inputName: sub.inputName,
                    correctValue: correctPairs[sub.inputName],
                  ))
              .toList();
          final updatedOptions = matchData.options
              .map((o) => ParsedChoice(
                    value: o.value,
                    text: o.text,
                    htmlText: o.htmlText,
                    isCorrect: correctPairs.values.contains(o.value),
                  ))
              .toList();
          result.add(QuestionEntity(
            slot: q.slot,
            page: q.page,
            text: q.text,
            htmlText: q.htmlText,
            displayHtml: q.displayHtml,
            choices: q.choices,
            imageUrls: q.imageUrls,
            inputBaseName: q.inputBaseName,
            seqCheck: q.seqCheck,
            type: q.type,
            generalFeedback: feedback,
            rightAnswerHtml: rightAnswerHtml,
            answerControls: q.answerControls,
            answerInputName: q.answerInputName,
            matchData: MatchData(
              subQuestions: updatedSubQuestions,
              options: updatedOptions,
            ),
            gapInputData: q.gapInputData,
            ddMarkerData: q.ddMarkerData,
          ));
          continue;
        }

        result.add(QuestionEntity(
          slot: q.slot,
          page: q.page,
          text: q.text,
          htmlText: q.htmlText,
          displayHtml: q.displayHtml,
          choices: q.choices,
          imageUrls: q.imageUrls,
          inputBaseName: q.inputBaseName,
          seqCheck: q.seqCheck,
          type: q.type,
          generalFeedback: feedback,
          rightAnswerHtml: rightAnswerHtml,
          answerControls: q.answerControls,
          answerInputName: q.answerInputName,
          matchData: q.matchData,
          gapInputData: q.gapInputData,
          ddMarkerData: q.ddMarkerData,
        ));
        continue;
      }

      if (reviewHtml.isEmpty) {
        log('  ? slot=${q.slot} sem revisão — gabarito não disponível');
        result.add(q);
        continue;
      }
      final correctValues = MoodleHtmlParser.parseCorrectValues(reviewHtml);
      log('  ✓ slot=${q.slot} gabarito: $correctValues');

      DebugLogger.instance.log(
          'GABARITO', 'slot=${q.slot} correctValues=$correctValues',
          data: {
            'choices': q.choices
                .map((c) => 'value="${c.value}" text="${c.text}"')
                .join(' | '),
            'reviewHtmlLength': reviewHtml.length,
          });
      final newChoices = q.choices
          .map((c) => ParsedChoice(
                value: c.value,
                text: c.text,
                htmlText: c.htmlText,
                isCorrect: correctValues.contains(c.value),
              ))
          .toList();
      result.add(QuestionEntity(
        slot: q.slot,
        page: q.page,
        text: q.text,
        htmlText: q.htmlText,
        displayHtml: q.displayHtml,
        choices: newChoices,
        imageUrls: q.imageUrls,
        inputBaseName: q.inputBaseName,
        seqCheck: q.seqCheck,
        type: q.type,
        generalFeedback: feedback,
        rightAnswerHtml: rightAnswerHtml,
        answerControls: q.answerControls,
        answerInputName: q.answerInputName,
        matchData: q.matchData,
        gapInputData: q.gapInputData,
        ddMarkerData: q.ddMarkerData,
      ));
    }
    if (skipped > 0) log('Questões abertas ignoradas: $skipped');
    return result;
  }

  @override
  Future<bool> submitPage(UserEntity user, int attemptId,
      QuestionEntity question, Map<String, String> answers) async {
    final dlog = DebugLogger.instance;
    dlog.separator('SUBMIT PAGE');

    dlog.log('SUBMIT', 'Dados da questão', data: {
      'attemptId': attemptId,
      'slot': question.slot,
      'page': question.page,
      'type': question.type,
      'inputBaseName': question.inputBaseName,
      'seqCheck': question.seqCheck,
      'answers': answers.toString(),
    });

    // seqcheck e submit sempre derivados do inputBaseName (base comum a todos os tipos)
    final seqCheckKey =
        question.inputBaseName.replaceFirst('answer', ':sequencecheck');
    final submitKey = question.inputBaseName.replaceFirst('answer', '-submit');

    final answerData = {
      ...answers,
      seqCheckKey: question.seqCheck,
      submitKey: '1',
    };

    dlog.log('SUBMIT', 'Payload para Moodle', data: answerData);

    await _moodle.processAttempt(
        user.baseUrl, user.token, attemptId, answerData,
        page: question.page);

    // Lê o estado pós-avaliação
    try {
      dlog.log('SUBMIT',
          'Lendo estado pós-avaliação (getAttemptData page=${question.page})…');
      final data = await _moodle.getAttemptData(
          user.baseUrl, user.token, attemptId, question.page);

      final questions = data['questions'] as List? ?? [];
      dlog.log(
          'SUBMIT', 'getAttemptData retornou ${questions.length} questão(ões)');

      for (final q in questions) {
        final qMap = q as Map;
        final qSlot = (qMap['slot'] as num?)?.toInt();
        if (qSlot != question.slot) continue;

        final state = qMap['state']?.toString() ?? '';
        final stateclass = qMap['stateclass']?.toString() ?? '';
        final qHtml = qMap['html'] as String? ?? '';

        // Classe de estado do div raiz — genérica para qualquer tipo de questão
        // Moodle renderiza: class="que {type} {behaviour} {stateClass}"
        final divClassMatch =
            RegExp(r'class="que\s+\w[\w-]*\s+\w[\w-]*\s+(\w+)"')
                .firstMatch(qHtml);
        final queStateClass = divClassMatch?.group(1) ?? '';

        final htmlHasCorrect = qHtml.contains('class="correct"') ||
            qHtml.contains('class="gradedright"');
        final htmlHasIncorrect = qHtml.contains('class="incorrect"') ||
            qHtml.contains('class="gradedwrong"') ||
            qHtml.contains('class="notanswered"');

        dlog.log('SUBMIT', '★ Diagnóstico', data: {
          'state_api': state.isEmpty ? '(vazio)' : state,
          'stateclass_api': stateclass.isEmpty ? '(vazio)' : stateclass,
          'queStateClass_html':
              queStateClass.isEmpty ? '(não encontrado)' : queStateClass,
          'html_correct': htmlHasCorrect,
          'html_incorrect': htmlHasIncorrect,
          'htmlPreview': qHtml.length > 200 ? qHtml.substring(0, 200) : qHtml,
        });

        // 1) Campo state da API
        if (state == 'gradedright') return true;
        if (state == 'gradedwrong' || state == 'gradedpartial') return false;

        // 2) stateclass da API
        if (stateclass == 'correct') return true;
        if (stateclass == 'incorrect' || stateclass == 'notanswered') {
          return false;
        }

        // 3) Classe do div raiz no HTML
        if (queStateClass == 'correct') return true;
        if (queStateClass == 'incorrect' || queStateClass == 'notanswered') {
          return false;
        }

        // 4) Pistas genéricas no HTML
        if (htmlHasCorrect && !htmlHasIncorrect) return true;
        if (htmlHasIncorrect) return false;
        // Moodle exibe rightanswer apenas quando a resposta está errada
        if (qHtml.contains('rightanswer') &&
            !qHtml.contains('class="correct"')) {
          return false;
        }

        dlog.log('SUBMIT',
            '⚠ Nenhum indicador encontrado — quiz possivelmente usa deferred feedback');
        break;
      }
    } catch (e) {
      dlog.log('SUBMIT', '✗ ERRO ao ler estado pós-avaliação: $e');
    }

    dlog.log('SUBMIT', '→ Retornando FALSE (nenhum gradedright detectado)');
    return false;
  }

  @override
  Future<void> finishAttempt(UserEntity user, int attemptId) =>
      _moodle.finishAttempt(user.baseUrl, user.token, attemptId);

  // ── Moodle State ───────────────────────────────────────────────────────────

  @override
  Future<QuizStateEntity> getQuizState(UserEntity user, int courseId) async {
    final data = await _state.getState(user.baseUrl, user.token, courseId);
    return QuizStateModel.fromJson(data);
  }

  @override
  Future<void> setSelectedQuiz({
    required UserEntity user,
    required int courseId,
    required int quizId,
    required String quizName,
  }) =>
      _state.setSelectedQuiz(
        baseUrl: user.baseUrl,
        token: user.token,
        courseId: courseId,
        quizId: quizId,
        quizName: quizName,
      );

  @override
  Future<void> releaseQuestion({
    required UserEntity user,
    required int courseId,
    required int page,
    required int slot,
    required int duration,
    required bool startOnFirstResponse,
    required int totalPages,
    required String quizName,
    required int quizId,
  }) =>
      _state.releaseQuestion(
        baseUrl: user.baseUrl,
        token: user.token,
        courseId: courseId,
        page: page,
        slot: slot,
        duration: duration,
        startOnFirstResponse: startOnFirstResponse,
        totalPages: totalPages,
        quizName: quizName,
        quizId: quizId,
      );

  @override
  Future<QuizStateEntity> startQuestionTimerIfNeeded(
      UserEntity user, int courseId) async {
    final data = await _state.startQuestionTimerIfNeeded(
      user.baseUrl,
      user.token,
      courseId,
    );
    return QuizStateModel.fromJson(data);
  }

  @override
  Future<void> closeQuestion(UserEntity user, int courseId) =>
      _state.closeQuestion(user.baseUrl, user.token, courseId);

  @override
  Future<void> submitScore({
    required UserEntity user,
    required int courseId,
    required int score,
    required bool correct,
    required int page,
  }) async {
    final dl = DebugLogger.instance;
    dl.log('SCORE', 'submitScore chamado', data: {
      'studentId': user.id,
      'score': score,
      'correct': correct,
      'page': page,
    });
    await _state.submitScore(
      baseUrl: user.baseUrl,
      token: user.token,
      courseId: courseId,
      studentId: user.id.toString(),
      studentName: user.fullname,
      score: score,
      correct: correct,
      page: page,
    );
    dl.log('SCORE', 'submitScore concluído ✓');
  }

  @override
  Future<List<ScoreEntity>> getScores(UserEntity user, int courseId) async {
    final list = await _state.getScores(user.baseUrl, user.token, courseId);

    // Ordena por score desc para atribuir rank
    final sorted = [...list];
    sorted.sort((a, b) {
      final sa = (a['score'] as num? ?? 0).toInt();
      final sb = (b['score'] as num? ?? 0).toInt();
      return sb.compareTo(sa);
    });

    final result = sorted.indexed.map(((int, Map<String, dynamic>) entry) {
      final rank = entry.$1 + 1;
      final j = entry.$2;
      final id = j['student_id']?.toString() ?? '';
      // total_answered = número de páginas respondidas
      int totalAnswered = 0;
      final answeredPages = <int>[];
      final answeredPageRounds = <String, String>{};
      try {
        final pages = j['pages'];
        if (pages is String && pages.isNotEmpty) {
          final decoded = jsonDecode(pages);
          if (decoded is Map) {
            // Novo formato: {"0": {"s": 1230, "c": 1}, ...}
            totalAnswered = decoded.length;
            for (final key in decoded.keys) {
              final parsed = int.tryParse(key.toString());
              if (parsed != null) {
                answeredPages.add(parsed);
                final value = decoded[key];
                if (value is Map && value['r'] != null) {
                  answeredPageRounds[key.toString()] = value['r'].toString();
                }
              }
            }
          } else if (decoded is List) {
            // Formato legado: [0, 1, 2]
            totalAnswered = decoded.length;
            for (final page in decoded) {
              final parsed = int.tryParse(page.toString());
              if (parsed != null) {
                answeredPages.add(parsed);
              }
            }
          }
        } else if (pages is List) {
          totalAnswered = pages.length;
          for (final page in pages) {
            final parsed = int.tryParse(page.toString());
            if (parsed != null) {
              answeredPages.add(parsed);
            }
          }
        } else if (pages is Map) {
          totalAnswered = pages.length;
          for (final key in pages.keys) {
            final parsed = int.tryParse(key.toString());
            if (parsed != null) {
              answeredPages.add(parsed);
            }
          }
        }
      } catch (_) {}
      return ScoreModel.fromJson(
        {
          ...j,
          'rank': rank,
          'total_answered': totalAnswered,
          'answered_pages': answeredPages,
          'answered_page_rounds': answeredPageRounds,
        },
        previousRank: _prevRanks[id],
      );
    }).toList();

    _prevRanks = {for (final s in result) s.studentId: s.rank};
    return result;
  }

  @override
  Future<void> resetQuiz(UserEntity user, int courseId) async {
    await _state.resetQuiz(user.baseUrl, user.token, courseId);
    _prevRanks = {};
  }

  @override
  Future<void> setFinished(UserEntity user, int courseId) =>
      _state.setFinished(user.baseUrl, user.token, courseId);

  Future<void> _saveProbeAnswersForReview(
    UserEntity user,
    int attemptId,
    List<QuestionEntity> questions,
    void Function(String) log,
  ) async {
    log('Salvando respostas de diagnostico para forcar revisao do Moodle...');

    for (final question in questions) {
      final probe = _probeAnswersForQuestion(question);
      if (probe.isEmpty) continue;

      final seqCheckKey =
          question.inputBaseName.replaceFirst('answer', ':sequencecheck');
      final submitKey =
          question.inputBaseName.replaceFirst('answer', '-submit');
      final answerData = {
        ...probe,
        seqCheckKey: question.seqCheck,
        submitKey: '1',
      };

      try {
        await _moodle.processAttempt(
          user.baseUrl,
          user.token,
          attemptId,
          answerData,
          page: question.page,
        );
        log('  -> slot=${question.slot} resposta diagnostica salva');
      } catch (e) {
        log('  -> slot=${question.slot} nao aceitou resposta diagnostica: $e');
      }
    }
  }

  static Map<String, String> _probeAnswersForQuestion(QuestionEntity question) {
    final answers = <String, String>{};

    if (question.isMultiChoice && question.choices.isNotEmpty) {
      answers[question.inputBaseName] = question.choices.first.value;
      return answers;
    }

    if ((question.isNumerical || question.isShortAnswer) &&
        question.answerInputName != null) {
      answers[question.answerInputName!] =
          question.isNumerical ? '999999999' : '__mq_probe__';
      return answers;
    }

    if (question.isMatch && question.matchData != null) {
      final options = question.matchData!.options;
      if (options.isEmpty) return answers;
      for (final sub in question.matchData!.subQuestions) {
        answers[sub.inputName] = options.first.value;
      }
      return answers;
    }

    final gap = question.gapInputData;
    if ((question.isGapSelect || question.isDdwtos) && gap != null) {
      for (var i = 1; i <= gap.gapCount; i++) {
        final options = gap.optionsForGap(i);
        if (options.isNotEmpty) answers[gap.inputName(i)] = options.first.value;
      }
      return answers;
    }

    if (question.isOrdering) {
      final controls = question.answerControls
          .where((c) => c.isSelect && c.options.isNotEmpty)
          .toList(growable: false);
      for (var i = 0; i < controls.length; i++) {
        final control = controls[i];
        final rank = controls.length - i;
        final option = control.options.firstWhere(
          (o) => o.value.trim() == '$rank' || o.text.trim() == '$rank',
          orElse: () => control.options.first,
        );
        answers[control.name] = option.value;
      }
      return answers;
    }

    for (final control in question.answerControls) {
      if (!control.isAnswerable) continue;
      if (control.isSelect && control.options.isNotEmpty) {
        answers[control.name] = control.options.first.value;
      } else if (control.isMultipleChoice) {
        answers[control.name] = control.value.isEmpty ? '1' : control.value;
      } else if (control.isText || control.isLongText) {
        answers[control.name] = '999999999';
      }
    }

    return answers;
  }

  static String _fallbackSelectRightAnswerHtml(
    QuestionEntity question,
    Map<String, ParsedChoice> selectedSelects,
  ) {
    if (selectedSelects.isEmpty) return '';

    final items = <String>[];
    final gap = question.gapInputData;
    if ((question.isGapSelect || question.isDdwtos) && gap != null) {
      for (var i = 1; i <= gap.gapCount; i++) {
        final selected = selectedSelects[gap.inputName(i)];
        if (selected == null) continue;
        items.add(
            '<li><strong>[$i]</strong> ${_escapeAnswerHtml(selected.text)}</li>');
      }
    } else if (question.isOrdering) {
      final ranked = <int, String>{};
      for (final control in question.answerControls) {
        final selected = selectedSelects[control.name];
        if (selected == null) continue;
        final rank = int.tryParse(selected.text.trim()) ??
            int.tryParse(selected.value.trim());
        if (rank == null || rank <= 0) continue;
        final label = control.label.trim().isNotEmpty
            ? control.label
            : _plainDiagnostic(control.htmlLabel);
        if (label.trim().isNotEmpty) ranked[rank] = label.trim();
      }
      final ranks = ranked.keys.toList()..sort();
      for (final rank in ranks) {
        items.add(
            '<li><strong>$rank.</strong> ${_escapeAnswerHtml(ranked[rank]!)}</li>');
      }
    } else {
      for (final entry in selectedSelects.entries) {
        items.add('<li>${_escapeAnswerHtml(entry.value.text)}</li>');
      }
    }

    if (items.isEmpty) return '';
    return '<div class="rightanswer">Resposta correta:<ol>${items.join()}</ol></div>';
  }

  static String _escapeAnswerHtml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  static void _logGapPromptDiagnostics(
    void Function(String) log, {
    required int slot,
    required String label,
    required String html,
  }) {
    if (html.trim().isEmpty) {
      log('     prompt slot=$slot $label vazio');
      return;
    }

    try {
      final prompt = MoodleHtmlParser.extractTextWithGapMarkers(html, '', '');
      log('     prompt slot=$slot $label len=${prompt.length} '
          'flags=${_diagnosticFlags(prompt)} '
          'plain="${_diagnosticSnippet(_plainDiagnostic(prompt), 500)}"');
    } catch (e) {
      log('     prompt slot=$slot $label ERRO: $e');
    }
  }

  static String _diagnosticFlags(String value) {
    final checks = <String, bool>{
      'qno': value.contains('qno'),
      'Incompleto': value.contains('Incompleto'),
      'Vale': value.contains('Vale '),
      'Verificar': value.contains('Verificar'),
      'Em branco': value.contains('Em branco'),
      'spanClass': value.contains('<span class'),
      'alt': value.contains('alt='),
      'src': value.contains('src='),
      'texImg': value.contains('/filter/tex/') || value.contains('tex/pix.php'),
      'select': value.contains('<select'),
      'marker': RegExp(r'\[\d+\]').hasMatch(value),
    };

    final active = checks.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .join(',');
    return active.isEmpty ? 'ok' : active;
  }

  static String _plainDiagnostic(String html) {
    return html
        .replaceAll(
            RegExp(r'<script\b[^>]*>.*?</script>',
                caseSensitive: false, dotAll: true),
            ' ')
        .replaceAll(
            RegExp(r'<style\b[^>]*>.*?</style>',
                caseSensitive: false, dotAll: true),
            ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _diagnosticSnippet(String value, [int max = 600]) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= max) return normalized;
    return '${normalized.substring(0, max)}...';
  }
}
