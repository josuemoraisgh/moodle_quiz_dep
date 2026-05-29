# Especificação Funcional — moodle_quiz_dep

> Documento gerado para validação por IA externa.  
> Descreve todas as funcionalidades, fluxos, regras de navegação e arquitetura do pacote Flutter `moodle_quiz_dep`.

---

## 1. Visão Geral

`moodle_quiz_dep` é um pacote Flutter que implementa um sistema de quiz presencial com suporte a integração Moodle. Ele é projetado para ser **embarcado em outros aplicativos Flutter ou apresentações HTML**, expondo uma API pública (`QuizCore` / `buildQuizAppWithDependencies`) que permite instanciar telas de quiz com dependências externas.

O pacote opera em dois contextos de deployment completamente independentes, chamados **"duas portas"**:

---

## 2. Dois Contextos de Deployment ("Duas Portas")

### Porta A — Apresentação / Modo Dependência

- **Flag**: `QuizRuntimeConfig.singleQuestionByDependency = true`
- **Rota inicial**: `/guest/question`
- **Caso de uso**: Uma apresentação HTML com slides (ex.: Reveal.js, GitHub Pages) onde alguns slides são questões de quiz embarcadas como widget Flutter. O professor navega pelos slides apresentando conteúdo teórico; quando aparece um slide de questão, o widget Flutter é exibido.
- **Quem acessa**: Professor (logado) e convidados (não logados). **Alunos NÃO acessam esta porta.**
- **Persistência**: Todas as respostas das questões da apresentação são salvas no banco de dados para gerar ranking da apresentação completa.
- **Comportamento por papel**:
  - **Não autenticado**: Vê a questão em modo somente leitura (preview) + botão "Fazer login" (visível apenas quando há backend disponível).
  - **Professor autenticado**: Redirecionado automaticamente pelo router para as telas de gestão (`/professor/quiz`).
  - **Usuário não-professor autenticado** (caso raro, acesso pela porta errada): Vê a questão em modo somente leitura sem botão de login.
  - **Hospedagem estática / sem banco funcional** (ex.: GitHub Pages sem backend): Apenas a questão em leitura; sem botão de login (porque `auth.students.isEmpty && !auth.isOnlineMode`).

### Porta B — App do Aluno (via QR Code)

- **Flag**: `QuizRuntimeConfig.singleQuestionByDependency = false`
- **Rota inicial**: `/login`
- **Caso de uso**: O professor exibe um QR Code na tela do `ProfessorHomePage`. O aluno escaneia e entra no app de quiz, vê a tela de espera, responde quando o professor libera, recebe feedback, e aguarda a próxima questão — tudo sem reconectar.
- **Quem acessa**: Apenas alunos. O mesmo QR code serve para todas as questões da sessão.
- **Comportamento**: `StudentLobbyPage` com ciclo completo (espera → questão ativa → timer → feedback → nova espera).

---

## 3. Modos de Operação

```dart
enum QuizOperationMode { online, offline }
enum QuestionNavigationMode { list, single }
```

### Modo Online (`QuizOperationMode.online`)
- Autentica via Moodle (usuário + senha + URL base do Moodle).
- Busca questões e estado do quiz via API Moodle.
- `StudentController` faz polling da API Moodle para obter estado da questão.
- Senhas padrão: `'_moodle_'`.

### Modo Offline (`QuizOperationMode.offline`)
- Autentica localmente: dropdown com lista de alunos configurados + senha única.
- Professor executa `OfflineLocalServer` (shelf HTTP) no próprio dispositivo.
- Alunos conectam ao servidor do professor via Wi-Fi local.
- Banco de dados SQLite local para persistência.

### Modo de Navegação
- **`list`**: Professor vê painel lateral com lista de questões e seleciona qualquer uma.
- **`single`**: Professor navega sequencialmente com setas (← →) ou teclado (ArrowLeft/ArrowRight); sem painel lateral.

---

## 4. Arquitetura de Servidor Local (Modo Offline)

O `OfflineLocalServer` (pacote `shelf`) é iniciado automaticamente no dispositivo do professor quando `startLocalServer = true`.

**Porta padrão**: 8080 (configurável via `localServerPort`).

**Endpoints da API**:

| Método | Rota | Descrição |
|--------|------|-----------|
| GET | `/api/state` | Estado atual do quiz (status, slot, timer, roundId…) |
| GET | `/api/question/:slot` | Dados da questão pelo número de slot |
| GET | `/api/students` | Lista de nomes de alunos para o dropdown de login |
| POST | `/api/score` | Registrar resposta de aluno (studentId, answers, isCorrect, score) |
| GET | `/api/scores` | Ranking atual |
| POST | `/api/reset` | Reiniciar sessão (apaga respostas e pontuações) |
| GET | `/` | Página HTML simples para acesso via browser (informa IP:porta) |

**QR Code**: Exibido no `ProfessorHomePage` com o URL `http://<IP-local>:8080`. O aluno escaneia uma única vez e o mesmo URL serve para todas as questões da sessão.

---

## 5. Rotas e Navegação

### Tabela de Rotas

| Rota | Tela | Acesso |
|------|------|--------|
| `/guest/question` | `GuestQuestionPage` | Porta A: convidado ou não autenticado |
| `/login` | `LoginPage` | Todos os não autenticados (Porta B) |
| `/professor/setup` | `ProfessorSetupPage` | Professor — primeira configuração |
| `/professor/quiz` | `ProfessorQuizSelectionPage` | Professor — selecionar/importar quiz |
| `/professor` | `ProfessorHomePage` | Professor — painel de controle principal |
| `/professor/rank` | `RankingPage` | Professor — ver ranking completo |
| `/professor/reveal` | `ProfessorRevealPage` | Professor — revelar gabarito |
| `/student/lobby` | `StudentLobbyPage` | Aluno autenticado (Porta B) |

### Lógica de Redirect do Router (`AppRouter`)

```
Ao acessar /guest/question:
  SE singleQuestionByDependency = false:
    SE autenticado → professor? /professor/quiz : /student/lobby
    SE não autenticado → /login
  SE singleQuestionByDependency = true:
    SE não autenticado → permanece em /guest/question (null)
    SE professor → /professor/quiz
    SE não-professor → permanece em /guest/question (null)

Ao acessar /professor/setup:
  SE requiresSetup = true → permanece
  SE não autenticado → /login
  SE autenticado → professor? /professor/quiz : /student/lobby

Regras gerais:
  SE não autenticado E rota ≠ /login → /login
  SE autenticado E rota = /login → professor? /professor/quiz : /student/lobby
  SE aluno E rota começa com /professor → /student/lobby
  SE professor E rota começa com /student → /professor/quiz
```

### Lógica pós-login (`LoginPage._login()`)

```
SE professor → /professor/quiz
SE não-professor E singleQuestionByDependency = true → /guest/question
SE não-professor E singleQuestionByDependency = false → /student/lobby
```

---

## 6. Telas em Detalhe

### 6.1 GuestQuestionPage (`/guest/question`) — Porta A

**Comportamentos**:

1. **Não autenticado + backend disponível** (`auth.isOnlineMode || auth.students.isNotEmpty`):
   - Exibe a questão em `QuestionEngineMode.preview` (somente leitura).
   - Botões de resposta e feedback desabilitados.
   - Botão "Fazer login" visível e habilitado.

2. **Não autenticado + sem backend** (hospedagem estática / GitHub Pages / sem BD):
   - Exibe a questão em `QuestionEngineMode.preview`.
   - **Sem** botão de login (condição: `auth.students.isEmpty && !auth.isOnlineMode`).

3. **Usuário não-professor autenticado** (acesso acidental pela Porta A):
   - Exibe a questão em `QuestionEngineMode.preview`.
   - Exibe o nome do usuário logado no card de cabeçalho.
   - Sem botão de login.

4. **Professor autenticado**: Nunca vê esta tela — o router redireciona para `/professor/quiz`.

5. **Sem questão configurada**: Exibe card "Nenhuma questão foi fornecida para visualização."

---

### 6.2 LoginPage (`/login`)

**Modo Offline**:
- Dropdown de seleção de nome (lista de alunos + "Professor").
- Campo de senha.
- Botão "Entrar" desabilitado enquanto nome ou senha estiverem vazios.
- Se `requiresSetup = true`, redireciona automaticamente para `/professor/setup`.

**Modo Online (Moodle)**:
- Campo URL do Moodle (pré-preenchido com `moodleBaseUrl`).
- Campo usuário Moodle.
- Campo senha.
- Não há dropdown de seleção de nome.

**Erros**: Exibidos em caixa vermelha abaixo dos campos.

**Após login bem-sucedido**:
- Professor → `/professor/quiz`
- Aluno em Porta B (`singleQuestionByDependency = false`) → `/student/lobby`
- Usuário em Porta A (`singleQuestionByDependency = true`) → `/guest/question`

---

### 6.3 ProfessorSetupPage (`/professor/setup`)

- Exibida na primeira execução quando `requiresSetup = true`:
  - `needsTeacherPassword`: senha de professor vazia.
  - `needsStudentPassword`: senha de aluno vazia.
  - `needsQuizTitle`: título do quiz vazio.
  - `needsStudents`: lista de alunos vazia.
- Permite configurar: título do quiz, senha do professor, senha dos alunos, lista de alunos.
- Após salvar → redireciona para `/professor/quiz`.

---

### 6.4 ProfessorQuizSelectionPage (`/professor/quiz`)

**Funcionalidades**:
- Lista quizzes já importados/salvos no banco.
- Botão "Importar Quiz (XML Moodle)": abre seletor de arquivo ou dialog de colar XML.
  - Disponível apenas quando `prof.supportsImport && !singleQuestionByDependency`.
- Card de cada quiz: nome, total de questões, botão "Usar", botão "Excluir" (se suportado).
- Ao selecionar um quiz → navega para `/professor`.
- Botões: Configurações (`/professor/setup`) e Sair (logout → `/login`).

**Comportamento em modo dependência** (`singleQuestionByDependency = true`):
- Se há quiz disponível, seleciona automaticamente o primeiro e vai direto para `/professor`.
- Botão de importação XML desabilitado.

---

### 6.5 ProfessorHomePage (`/professor`) — Painel Principal

**Layout responsivo**:
- **Desktop**: Painel lateral (lista de questões) + painel de controle à direita.
- **Mobile**: Abas "Questões" e "Controle". Em modo `single`, sem abas — só o painel de controle.

**Componentes do painel de controle**:

1. **AppBar**: Nome do quiz, botões Voltar, Fullscreen, Gabarito, Ranking, Sair.

2. **QR Code**: Exibido com URL `http://<IP>:<porta>` para os alunos escanearem. Visível no layout.

3. **Status Card**: Indica o estado atual do quiz:
   - `waiting` → "Aguardando Início" (ícone cinza).
   - `active` → "Questão Ativa" (ícone verde, ponto pulsante).
   - `closed` → "Questão Encerrada" (ícone amarelo).
   - `finished` → "Quiz Finalizado" (ícone azul/ciano).

4. **Timer**: Exibido quando `state.isActive && state.endsAt != null`. Botão "+15s" para estender o tempo.

5. **Aviso "Aguardando primeira resposta"**: Exibido quando `state.isActive && state.isTimerPending` (timer só inicia na primeira resposta).

6. **Seletor de duração**: Chips de tempo (ex.: 15s, 20s, 30s, 45s, 60s, 90s, 120s). Desabilitado quando questão ativa.

7. **Opção "Começar tempo na 1ª resposta"**: Checkbox. Quando marcado, o cronômetro só inicia quando o primeiro aluno responder.

8. **Card de questão selecionada**: Expansível. Mostra enunciado (até 3 linhas recolhido, completo expandido). Checkboxes "Mostrar resposta correta" e botão "Feedback".

9. **Botões de ação**:
   - `Liberar Questão N`: Ativa a questão selecionada (disponível quando não ativa).
   - `Encerrar Questão`: Encerra a questão ativa.
   - `Reiniciar Quiz`: Dialog de confirmação → apaga todas respostas e pontuações.

10. **Mini ranking Top 5**: Exibido quando há scores. Cores: ouro/prata/bronze para top 3.

11. **Log colapsável**: Linhas de diagnóstico/carregamento. Botão de copiar.

**Navegação por teclado** (modo `single`): ArrowLeft/ArrowRight muda a questão selecionada.

**Navegação por setas visuais** (modo `single`): Botões `<` `>` sobrepostos ao card da questão.

---

### 6.6 ProfessorRevealPage (`/professor/reveal`)

- Exibe o gabarito completo da questão (respostas corretas destacadas).
- Recebe a `QuestionEntity` via `state.extra`.
- Acessado pelo botão "Mostrar Gabarito" (ícone fact_check) na AppBar do professor.

---

### 6.7 RankingPage (`/professor/rank`)

- Exibe ranking completo de todos os alunos com pontuações.
- Acessado pelo botão "Ranking" (ícone bar_chart) na AppBar do professor.

---

### 6.8 StudentLobbyPage (`/student/lobby`) — Porta B

**Estados da tela** (baseados em `QuizStateEntity.status`):

1. **`waiting`** — Tela de espera:
   - Ícone animado (ampulheta pulsante).
   - Texto: "Aguarde o professor liberar a próxima questão…"
   - Exibe o título do quiz.

2. **`active` ou `closed`** — Questão visível:
   - **Timer**: Exibido quando `state.isActive && state.endsAt != null && !student.hasAnswered`.
   - **QuestionEngineWidget**: Modo `answer` quando `isActive && !hasAnswered`; modo `preview` quando `hasAnswered || isClosed`.
   - **Botão "Enviar Resposta"**: Habilitado quando `hasAnyAnswer && !isSubmitting && isActive`. Exibe spinner durante envio.
   - **FeedbackCard** (após responder): Correto (verde ✓) / Incorreto (vermelho ✗) / Discursivo (azul, "Será avaliada posteriormente").
   - **Aviso de tempo esgotado** (`isClosed && !hasAnswered`): Card amarelo "Tempo esgotado. Aguarde a próxima questão."

3. **`finished`** — Quiz finalizado:
   - Ícone de troféu dourado.
   - Texto: "Quiz Finalizado! Obrigado por participar!"

**AppBar do aluno**: Nome do aluno + botão Sair (logout → `/login`).

**Inicialização**: `StudentController.initLocal(user)` chamado no `initState` via `addPostFrameCallback`.

**Comunicação com o servidor**:
- **Modo local** (mesmo dispositivo): `_stateService.addListener` — estado compartilhado em memória.
- **Modo Wi-Fi** (`initClient`): Polling a cada 1 segundo via `OfflineLocalClient` → `GET /api/state` e `GET /api/question/:slot`.
- **Modo online** (Moodle): Polling via `_quizRepo.getLiveState()` e `getLiveQuestion()`.

**Auto-submit**: Se `isClosed && !hasAnswered && selectedAnswers.isNotEmpty` → resposta enviada automaticamente.

---

## 7. Máquina de Estados do Quiz

```
waiting → active → closed
                ↘
              finished

waiting:  professor ainda não liberou nenhuma questão
active:   questão ativa, alunos podem responder, timer correndo
closed:   questão encerrada (professor clicou "Encerrar" ou timer esgotou)
finished: professor encerrou o quiz completo
```

**Transição waiting → active**: `ProfessorController.releaseQuestion(question)`.  
**Transição active → closed**: `ProfessorController.stopQuestion()` ou timer expirado (`onTimeUp`).  
**Reset**: `ProfessorController.resetQuiz()` → volta a `waiting`, apaga scores.

---

## 8. Pontuação

**Fórmula**:
```
score = 1000 + (secondsRemaining × 10)
```
- Se `isTimerPending` (timer não iniciou ainda): `score = 1000 + (durationSeconds × 10)`.
- Resposta incorreta: `score = 0`.
- Questões discursivas (`isEssay`): não graduadas automaticamente (`lastAnswerGraded = false`).

---

## 9. Autenticação

### Papéis
- **Professor** (`LocalUserEntity.isTeacher = true`): Acesso a todas as telas de gestão.
- **Aluno** (`isTeacher = false`): Acesso apenas ao `StudentLobbyPage` (Porta B).

### AuthController
- `isLoggedIn`: `user != null`.
- `isOnlineMode`: `!_repo.supportsLocalSetup` (não tem setup local → é Moodle).
- `requiresSetup`: `supportsLocalSetup && (needsTeacherPassword || needsStudentPassword || needsQuizTitle || needsStudents)`.
- `needsTeacherPassword / needsStudentPassword / needsQuizTitle / needsStudents`: verificações de configuração pendente.

### Sessão
- Sessão salva localmente via `_repo.saveSession(user)` após login.
- Sessão carregada no `init()` via `_repo.loadSession()`.
- Logout via `_repo.clearSession()`.

---

## 10. QuizCore — API de Embedding

`QuizCore` é a classe central para quem consome o pacote externamente. Ela é separada das telas de UI para permitir embedding em diferentes contextos (apps Flutter, apresentações HTML, etc.).

### Funções públicas

```dart
// Cria com factories (recomendado para múltiplas telas independentes)
QuizCore buildQuizCoreWithFactories({
  required QuizRuntimeConfig baseConfig,
  required IQuizAuthRepository Function() authRepositoryFactory,
  required IQuizRuntimeRepository Function(QuizStateService) quizRepositoryFactory,
  required QuizSyncServer Function() syncServerFactory,
})

// Cria com instâncias prontas
QuizCore buildQuizCoreWithDependencies({...})

// Cria o widget completo (entrada simplificada)
Future<Widget> buildQuizAppWithDependencies({
  required QuizOperationMode mode,
  required IQuizAuthRepository authRepository,
  required IQuizRuntimeRepository quizRepository,
  required List<StudentEntity> users,
  required AppSettingsEntity settings,
  required String defaultPassword,
  QuestionEntity? question,       // ← define singleQuestionByDependency = true
  Map<String, dynamic>? questionMap,
  String? questionXml,
  int questionXmlIndex = 0,
  int? questionId,
  QuestionNavigationMode navigationMode,
  List<LocalQuizEntity> quizzes,
  List<QuestionEntity> questions,
  String initialQuizName,
  String moodleBaseUrl,
  String studentUrl,
  int courseId,
  int localServerPort,
  bool startLocalServer,
  QuizStateService? stateService,
  QuizSyncServer? syncServer,
})
```

### `singleQuestionByDependency`

Definido como `true` automaticamente quando qualquer um destes é fornecido: `question != null`, `questionMap?.isNotEmpty`, `questionXml?.isNotEmpty`.

---

## 11. QuizRuntimeConfig — Configuração em Runtime

| Campo | Tipo | Descrição |
|-------|------|-----------|
| `operationMode` | `QuizOperationMode` | `online` ou `offline` |
| `navigationMode` | `QuestionNavigationMode` | `list` ou `single` |
| `settings` | `AppSettingsEntity` | Senhas, título, duração padrão, opções de duração |
| `students` | `List<StudentEntity>` | Lista de alunos para login offline |
| `quizzes` | `List<LocalQuizEntity>` | Quizzes pré-carregados |
| `questions` | `List<QuestionEntity>` | Questões pré-carregadas |
| `initialQuizName` | `String` | Nome exibido no cabeçalho do guest |
| `moodleBaseUrl` | `String` | URL base do Moodle |
| `studentUrl` | `String` | URL que o aluno usa para conectar |
| `courseId` | `int` | ID do curso no Moodle |
| `localServerPort` | `int` | Porta do servidor local (padrão: 8080) |
| `startLocalServer` | `bool` | Se deve iniciar o `OfflineLocalServer` |
| `singleQuestionByDependency` | `bool` | Se está no modo Porta A (apresentação) |

---

## 12. Detecção de Backend Disponível

Na `GuestQuestionPage`, o botão "Fazer login" é exibido **somente** quando:

```dart
final canLogin = !auth.isLoggedIn && (auth.isOnlineMode || auth.students.isNotEmpty);
```

Ou seja:
- **Moodle online** (`isOnlineMode = true`): sempre exibe o botão.
- **Offline com alunos cadastrados** (`students.isNotEmpty`): exibe o botão.
- **Offline sem alunos** (hospedagem estática, GitHub Pages, sem BD): **NÃO** exibe o botão.

---

## 13. Regras Importantes de Negócio

1. O **mesmo QR code** é válido para toda a sessão do quiz (Porta B). O aluno não precisa reconectar entre questões.
2. Na **Porta A**, alunos **nunca** aparecem — é exclusiva para professor e convidados anônimos.
3. Na **Porta B**, a questão fica em modo `waiting` até o professor clicar "Liberar". Quando liberada, todos os alunos conectados recebem a questão simultaneamente (por polling).
4. O **timer pode ser estendido** em +15s durante uma questão ativa (botão na tela do professor).
5. O **auto-submit** ocorre quando o timer encerra e o aluno tinha selecionado respostas mas não enviou.
6. **Reiniciar o quiz** apaga todas as respostas e pontuações (ação irreversível, requer confirmação).
7. Na **Porta A**, o `QuizCore` é instanciado a cada slide de questão na apresentação, e todas as respostas são persistidas para ranking final da apresentação completa.
8. Em **modo dependência** com `singleQuestionByDependency = true`, a importação de XML pelo professor é **desabilitada** (o quiz vem da dependência externa, não de importação).
9. A **senha do professor** é configurada em `AppSettingsEntity.teacherPassword`. Em modo Moodle, usa `'_moodle_'` como sentinel que delega a autenticação ao Moodle.
10. O **`QuizStateService`** é o barramento central de estado em memória. Cada tela de quiz instancia seu próprio `QuizStateService`, garantindo isolamento entre múltiplas telas simultâneas.

---

## 14. Fluxo Completo — Porta A (Apresentação)

```
1. Apresentação HTML abre slide de questão
2. Widget Flutter inicializa com singleQuestionByDependency = true, question = <questão do slide>
3. Rota inicial: /guest/question
4. [Se não autenticado]
   - Questão exibida em preview (somente leitura)
   - Botão "Fazer login" visível (se há backend)
   - Usuário clica "Fazer login" → navega para /login
   - Login bem-sucedido:
     - Professor → /professor/quiz → seleciona quiz automaticamente → /professor
     - Não-professor → retorna para /guest/question (somente leitura)
5. [Professor autenticado em /professor]
   - Vê a questão do slide no painel de controle
   - Configura duração, opção de timer
   - Clica "Liberar Questão" → estado muda para active
   - Alunos (Porta B) recebem a questão
   - Timer corre
   - Clica "Encerrar Questão" (ou timer esgota)
   - Pode revelar gabarito (/professor/reveal)
   - Pode ver ranking (/professor/rank)
6. Apresentação avança para próximo slide (próxima questão)
7. Nova instância do widget Flutter com a nova questão
```

---

## 15. Fluxo Completo — Porta B (Aluno via QR)

```
1. Professor exibe QR Code em /professor (URL: http://<IP>:8080)
2. Aluno escaneia QR → abre app → /login
3. Aluno seleciona nome no dropdown + digita senha → "Entrar"
4. Login → /student/lobby
5. [Estado: waiting] Tela de espera com ampulheta animada
6. Professor libera questão em /professor
7. [Estado: active] Questão aparece no app do aluno
8. Timer inicia (imediatamente ou na primeira resposta, conforme configuração)
9. Aluno seleciona resposta → botão "Enviar Resposta" habilita
10. Aluno clica "Enviar" → resposta salva → feedback exibido (correto/incorreto)
11. [Estado: closed] Professor encerra → alunos sem resposta veem "Tempo esgotado"
12. [Estado: waiting] Professor libera próxima questão → aluno aguarda novamente
13. [Sem reconexão necessária — mesmo QR, mesma sessão]
14. [Estado: finished] Quiz finalizado → tela de conclusão
```

---

## 16. Dependências Externas Principais

| Pacote | Uso |
|--------|-----|
| `go_router` | Navegação declarativa com redirect |
| `provider` | Injeção de dependência e gerenciamento de estado |
| `shelf` / `shelf_router` | Servidor HTTP local (OfflineLocalServer) |
| `http` | Cliente HTTP (OfflineLocalClient → servidor do professor) |
| `flutter_animate` | Animações (feedback, ranking, espera) |
| `qr_flutter` | Geração do QR Code na tela do professor |
| `google_fonts` | Tipografia |
| `sqflite` | Banco de dados SQLite (modo offline) |

---

*Fim da especificação. Versão gerada em 2026-05-29.*
