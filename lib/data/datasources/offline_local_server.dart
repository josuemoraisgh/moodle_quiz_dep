import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../../core/utils/local_ip.dart';
import '../../core/utils/question_serializer.dart';
import '../../domain/entities/question_entity.dart';
import '../../domain/entities/quiz_state_entity.dart';
import '../../domain/entities/score_entity.dart';
import '../../domain/entities/student_entity.dart';
import '../../domain/services/quiz_sync_server.dart';

/// Servidor HTTP local que substitui o Moodle no modo presencial offline.
///
/// O professor executa este servidor no próprio dispositivo.
/// Alunos conectam via Wi-Fi usando o IP exibido no QR code.
///
/// Fluxo correto: QR Code → Tela de Login → Espera → Questão
///
/// Endpoints:
///   GET  /api/state          → estado atual do quiz
///   GET  /api/question/:slot → dados da questão (JSON)
///   GET  /api/students       → lista de nomes para o dropdown de login
///   POST /api/login          → autentica aluno ou professor
///   POST /api/score          → registrar resposta de aluno
///   GET  /api/scores         → ranking atual
///   POST /api/reset          → reiniciar sessão
class OfflineLocalServer implements QuizSyncServer {
  final int port;
  HttpServer? _server;
  String _localIp = '0.0.0.0';

  // Callbacks que o ProfessorController injeta
  QuizStateEntity Function()? _onGetState;
  QuestionEntity? Function(int slot)? _onGetQuestion;
  List<StudentEntity> Function()? _onGetStudents;
  List<ScoreEntity> Function()? _onGetScores;
  Future<void> Function(Map<String, dynamic> body)? _onScore;
  Future<void> Function()? _onReset;
  Future<Map<String, dynamic>?> Function(String name, String password)?
      _onLogin;

  OfflineLocalServer({this.port = 8080});

  String get localIp => _localIp;
  @override
  String get serverUrl => 'http://$_localIp:$port';

  @override
  set onGetState(QuizStateEntity Function()? callback) =>
      _onGetState = callback;

  @override
  set onGetQuestion(QuestionEntity? Function(int slot)? callback) =>
      _onGetQuestion = callback;

  @override
  set onGetStudents(List<StudentEntity> Function()? callback) =>
      _onGetStudents = callback;

  @override
  set onGetScores(List<ScoreEntity> Function()? callback) =>
      _onGetScores = callback;

  @override
  set onScore(Future<void> Function(Map<String, dynamic> body)? callback) =>
      _onScore = callback;

  @override
  set onReset(Future<void> Function()? callback) => _onReset = callback;

  @override
  set onLogin(
          Future<Map<String, dynamic>?> Function(String name, String password)?
              callback) =>
      _onLogin = callback;

  @override
  Future<void> start() async {
    _localIp = (await getLocalIp()) ?? '0.0.0.0';

    final router = Router();

    router.get('/api/state', _handleState);
    router.get('/api/question/<slot>', _handleQuestion);
    router.get('/api/students', _handleStudents);
    router.get('/api/scores', _handleScores);
    router.post('/api/score', _handleScore);
    router.post('/api/reset', _handleReset);
    router.post('/api/login', _handleLogin);

    // Arquivos estáticos (página web simples para alunos via browser)
    router.get('/', _handleWebRoot);
    router.get('/<path|.*>', _handle404);

    final pipeline =
        const Pipeline().addMiddleware(_cors()).addHandler(router.call);

    _server = await shelf_io.serve(pipeline, InternetAddress.anyIPv4, port);
  }

  @override
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  @override
  bool get isRunning => _server != null;

  // ── Handlers ─────────────────────────────────────────────────────────────

  Response _handleState(Request req) {
    final state = _onGetState?.call() ?? QuizStateEntity.empty();
    return _json(_stateToMap(state));
  }

  Response _handleQuestion(Request req, String slot) {
    final slotNum = int.tryParse(slot);
    if (slotNum == null) return Response.badRequest();
    final q = _onGetQuestion?.call(slotNum);
    if (q == null) {
      return Response.notFound('{"error":"Questão não encontrada"}');
    }
    return _json(_questionToMap(q));
  }

  Response _handleStudents(Request req) {
    final students = _onGetStudents?.call() ?? [];
    return _json({'students': students.map((s) => s.name).toList()});
  }

  Response _handleScores(Request req) {
    final scores = _onGetScores?.call() ?? [];
    return _json({'scores': scores.map(_scoreToMap).toList()});
  }

  Future<Response> _handleScore(Request req) async {
    try {
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      await _onScore?.call(body);
      return _json({'ok': true});
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': '$e'}));
    }
  }

  Future<Response> _handleReset(Request req) async {
    await _onReset?.call();
    return _json({'ok': true});
  }

  Future<Response> _handleLogin(Request req) async {
    try {
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final name = body['name'] as String? ?? '';
      final password = body['password'] as String? ?? '';

      if (name.isEmpty) {
        return _json({'ok': false, 'error': 'Nome obrigatório.'});
      }

      final result = await _onLogin?.call(name, password);
      if (result == null) {
        return _json({'ok': false, 'error': 'Usuário ou senha incorretos.'});
      }
      return _json({'ok': true, ...result});
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'ok': false, 'error': '$e'}));
    }
  }

  Response _handleWebRoot(Request req) {
    return Response.ok(
      _studentWebPage(),
      headers: {'content-type': 'text/html; charset=utf-8'},
    );
  }

  Response _handle404(Request req, String path) =>
      Response.notFound('Not found: $path');

  // ── Serialização ──────────────────────────────────────────────────────────

  Map<String, dynamic> _stateToMap(QuizStateEntity s) => {
        'status': s.status.name,
        'currentSlot': s.currentSlot,
        'currentPage': s.currentPage,
        'totalPages': s.totalPages,
        'quizId': s.quizId,
        'quizTitle': s.quizTitle,
        'roundId': s.roundId,
        'durationSeconds': s.durationSeconds,
        'startOnFirstResponse': s.startOnFirstResponse,
        'timerStarted': s.timerStarted,
        'startedAt': s.startedAt?.millisecondsSinceEpoch,
        'endsAt': s.endsAt?.millisecondsSinceEpoch,
      };

  Map<String, dynamic> _questionToMap(QuestionEntity q) =>
      QuestionSerializer.toJson(q);

  Map<String, dynamic> _scoreToMap(ScoreEntity s) => {
        'studentId': s.studentId,
        'studentName': s.studentName,
        'score': s.score,
        'correctCount': s.correctCount,
        'totalAnswered': s.totalAnswered,
        'rank': s.rank,
      };

  // ── Helpers ───────────────────────────────────────────────────────────────

  Response _json(Map<String, dynamic> body) => Response.ok(
        jsonEncode(body),
        headers: {
          'content-type': 'application/json; charset=utf-8',
          'access-control-allow-origin': '*',
        },
      );

  Middleware _cors() => (Handler inner) {
        return (Request req) async {
          if (req.method == 'OPTIONS') {
            return Response.ok('', headers: {
              'access-control-allow-origin': '*',
              'access-control-allow-methods': 'GET, POST, OPTIONS',
              'access-control-allow-headers': 'content-type',
            });
          }
          final res = await inner(req);
          return res.change(headers: {'access-control-allow-origin': '*'});
        };
      };

  /// Página web para alunos via browser — fluxo: Login → Espera → Questão.
  String _studentWebPage() => '''<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Quiz Presencial</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#0D0D2B;color:#fff;min-height:100vh;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:16px}
.card{background:#1A1A3E;border-radius:16px;padding:28px;width:100%;max-width:420px;box-shadow:0 8px 32px rgba(0,0,0,.4)}
h1{color:#6C63FF;font-size:1.5rem;margin-bottom:6px;text-align:center}
.sub{color:#aaa;font-size:.9rem;text-align:center;margin-bottom:24px}
label{display:block;color:#ccc;font-size:.85rem;margin:16px 0 6px}
select,input{width:100%;background:#0D0D2B;color:#fff;border:1px solid #333;border-radius:8px;padding:12px;font-size:1rem;outline:none}
select:focus,input:focus{border-color:#6C63FF}
.btn{width:100%;padding:14px;border:none;border-radius:8px;font-size:1rem;font-weight:600;cursor:pointer;margin-top:16px}
.btn-p{background:linear-gradient(135deg,#6C63FF,#9B59B6);color:#fff}
.btn-g{background:transparent;color:#aaa;border:1px solid #444;margin-top:10px}
.btn:disabled{opacity:.5;cursor:not-allowed}
.err{background:rgba(231,76,60,.15);border:1px solid rgba(231,76,60,.4);border-radius:8px;padding:12px;color:#e74c3c;font-size:.9rem;margin-top:16px;display:none}
.hidden{display:none!important}
.badge{text-align:right;color:#6C63FF;font-size:.85rem;margin-bottom:16px}
.logout{color:#888;font-size:.8rem;cursor:pointer;text-decoration:underline;margin-left:8px}
.chip{display:inline-block;background:#6C63FF;color:#fff;border-radius:20px;padding:2px 10px;font-size:.75rem;margin-left:6px}
/* Espera */
.wait-ico{font-size:3rem;text-align:center;margin-bottom:16px}
.wait-txt{color:#aaa;text-align:center;font-size:.95rem}
/* Questão */
.qtext{color:#fff;font-size:1.05rem;line-height:1.6;margin-bottom:20px}
.choices{display:flex;flex-direction:column;gap:10px}
.choice{background:#0D0D2B;border:1px solid #333;border-radius:8px;padding:14px;cursor:pointer;color:#fff;text-align:left;font-size:.95rem;transition:border .15s,background .15s;width:100%}
.choice:hover{border-color:#6C63FF}
.sel{border-color:#6C63FF!important;background:rgba(108,99,255,.2)!important}
.ok{border-color:#2ecc71!important;background:rgba(46,204,113,.15)!important}
.wrong{border-color:#e74c3c!important;background:rgba(231,76,60,.15)!important}
.ok-msg{color:#2ecc71;text-align:center;font-size:1rem;margin-top:16px;display:none}
.divider{display:flex;align-items:center;gap:10px;margin:14px 0}
.divider hr{flex:1;border:none;border-top:1px solid #333}
.divider span{color:#555;font-size:.8rem}
</style>
</head>
<body>

<!-- LOGIN -->
<div id="vLogin" class="card">
<h1>🎓 Quiz Presencial</h1>
<p class="sub">Selecione seu nome e entre com a senha</p>
<label>Nome</label>
<select id="selName"><option value="">Carregando…</option></select>
<label>Senha</label>
<input type="password" id="inPass" placeholder="Digite sua senha" />
<div class="err" id="errLogin"></div>
<button class="btn btn-p" id="btnLogin" onclick="doLogin()">Entrar</button>
<div class="divider"><hr><span>ou</span><hr></div>
<button class="btn btn-g" onclick="doGuest()">👁 Entrar como Convidado</button>
</div>

<!-- ESPERA -->
<div id="vWait" class="card hidden">
<div class="badge" id="bdgWait"></div>
<div class="wait-ico">⏳</div>
<p style="text-align:center;font-size:1.1rem;margin-bottom:8px">Aguardando…</p>
<p class="wait-txt">O professor ainda não liberou a atividade.</p>
</div>

<!-- QUESTÃO -->
<div id="vQ" class="card hidden">
<div class="badge" id="bdgQ"></div>
<div class="qtext" id="qText"></div>
<div class="choices" id="qChoices"></div>
<button class="btn btn-p hidden" id="btnSubmit" onclick="doSubmit()">Confirmar Resposta</button>
<p class="ok-msg" id="okMsg">✓ Resposta enviada!</p>
</div>

<!-- FIM -->
<div id="vEnd" class="card hidden">
<div style="text-align:center">
<div style="font-size:3rem">🏆</div>
<h1 style="margin-top:12px">Quiz Finalizado!</h1>
<p class="wait-txt" style="margin-top:8px">Obrigado por participar.</p>
</div>
</div>

<script>
var S=JSON.parse(localStorage.getItem('qs')||'null');
var timer=null,curSlot=null,curRound=null,curQ=null,selAns=null,submitted=false;

window.onload=function(){loadStudents();if(S){badge();show('Wait');poll();}};

async function loadStudents(){
  try{
    var r=await fetch('/api/students'),d=await r.json();
    var el=document.getElementById('selName');
    el.innerHTML='<option value="">Selecione…</option>';
    ['Professor',...d.students].forEach(function(n){
      var o=document.createElement('option');o.value=n;o.text=n;el.appendChild(o);
    });
  }catch(e){}
}

async function doLogin(){
  var name=document.getElementById('selName').value;
  var pass=document.getElementById('inPass').value;
  if(!name||!pass){showErr('Selecione o nome e a senha.');return;}
  document.getElementById('btnLogin').disabled=true;
  hideErr();
  try{
    var r=await fetch('/api/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({name:name,password:pass})});
    var d=await r.json();
    if(d.ok){
      if(d.role==='professor'){showErr('Professor deve usar o app principal.');document.getElementById('btnLogin').disabled=false;return;}
      S={name:d.name,role:d.role,studentId:d.studentId||0};
      localStorage.setItem('qs',JSON.stringify(S));
      badge();show('Wait');startPoll();
    }else{showErr(d.error||'Usuário ou senha incorretos.');}
  }catch(e){showErr('Erro de conexão.');}
  document.getElementById('btnLogin').disabled=false;
}

function doGuest(){
  S={name:'Convidado',role:'guest',studentId:0};
  localStorage.setItem('qs',JSON.stringify(S));
  badge();show('Wait');startPoll();
}

function logout(){
  S=null;localStorage.removeItem('qs');
  curSlot=null;curQ=null;selAns=null;submitted=false;
  stopPoll();show('Login');loadStudents();
}

function startPoll(){stopPoll();timer=setInterval(poll,2000);poll();}
function stopPoll(){if(timer){clearInterval(timer);timer=null;}}

async function poll(){
  try{var r=await fetch('/api/state');var st=await r.json();await handleState(st);}catch(e){}
}

async function handleState(st){
  if(st.status==='finished'){show('End');stopPoll();return;}
  if(st.status==='waiting'||st.currentSlot===0){show('Wait');return;}
  var slot=st.currentSlot,round=st.roundId;
  if(slot!==curSlot||round!==curRound){
    curSlot=slot;curRound=round;selAns=null;submitted=false;
    try{var r=await fetch('/api/question/'+slot);curQ=await r.json();}catch(e){curQ=null;}
  }
  show('Q');renderQ(st);
}

function renderQ(st){
  if(!curQ)return;
  document.getElementById('qText').innerHTML=curQ.html||curQ.htmlText||'';
  var div=document.getElementById('qChoices');div.innerHTML='';
  var choices=curQ.choices||[];
  var isGuest=S&&S.role==='guest';
  var closed=st.status!=='active'||submitted;
  choices.forEach(function(c,i){
    var val=c.v||c.value||String(i);
    var btn=document.createElement('button');
    btn.className='choice';
    btn.innerHTML=c.h||c.htmlText||'';
    if(selAns===val)btn.classList.add('sel');
    if(submitted){
      if(c.ok||c.isCorrect)btn.classList.add('ok');
      else if(selAns===val)btn.classList.add('wrong');
    }
    if(!isGuest&&!closed){btn.onclick=function(){selAns=val;renderQ(st);};}
    else{btn.style.cursor='default';}
    div.appendChild(btn);
  });
  var sb=document.getElementById('btnSubmit');
  var om=document.getElementById('okMsg');
  if(isGuest){sb.classList.add('hidden');om.style.display='none';}
  else if(submitted){sb.classList.add('hidden');om.style.display='block';}
  else if(st.status==='active'&&selAns!==null){sb.classList.remove('hidden');om.style.display='none';}
  else{sb.classList.add('hidden');om.style.display='none';}
}

async function doSubmit(){
  if(!S||S.role==='guest'||!selAns||!curQ)return;
  var ans={};
  var inp=curQ.input||curQ.inputBaseName||'';
  if(inp)ans[inp]=selAns;
  var choices=curQ.choices||[];
  var correctChoice=choices.find(function(c){return (c.v||c.value)===selAns;});
  var isOk=correctChoice?(correctChoice.ok||correctChoice.isCorrect||false):false;
  try{
    await fetch('/api/score',{method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({studentId:S.studentId,studentName:S.name,questionSlot:curSlot,roundId:curRound,isCorrect:isOk,score:isOk?1:0,answers:ans})});
    submitted=true;
    var st=await(await fetch('/api/state')).json();
    renderQ(st);
  }catch(e){}
}

function show(v){['Login','Wait','Q','End'].forEach(function(x){document.getElementById('v'+x).classList[x===v?'remove':'add']('hidden');});}

function badge(){
  if(!S)return;
  var lbl=S.role==='professor'?'Professor':S.role==='guest'?'Convidado':'Aluno';
  var html=S.name+'<span class="chip">'+lbl+'</span><span class="logout" onclick="logout()">Sair</span>';
  document.getElementById('bdgWait').innerHTML=html;
  document.getElementById('bdgQ').innerHTML=html;
}

function showErr(m){var e=document.getElementById('errLogin');e.textContent=m;e.style.display='block';}
function hideErr(){var e=document.getElementById('errLogin');e.style.display='none';}

document.addEventListener('DOMContentLoaded',function(){
  var p=document.getElementById('inPass');
  if(p)p.addEventListener('keypress',function(e){if(e.key==='Enter')doLogin();});
});
</script>
</body>
</html>''';
}
