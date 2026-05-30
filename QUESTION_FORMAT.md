# Formato de Questão — Schema v3

Toda serialização de `QuestionEntity` usa `QuestionSerializer` (schema v3).  
Não crie dicionários JSON de questão à mão fora deste serializador.

## Campos obrigatórios (todos os tipos)

| Chave | Tipo | Descrição |
|---|---|---|
| `v` | int | Versão do schema. Sempre `3`. |
| `slot` | int | Número da questão na ordem (começa em 1). |
| `page` | int | Página do questionário (começa em 0). |
| `type` | string | Tipo Moodle (veja tabela abaixo). |
| `html` | string | Enunciado em HTML. |
| `input` | string | Nome base do campo de formulário (ex.: `q_local:1_answer`). |
| `seq` | string | Valor do sequencecheck Moodle (ex.: `seq-1`). |

## Campos opcionais comuns

| Chave | Tipo | Quando incluir |
|---|---|---|
| `feedback` | string | Feedback geral pós-resposta (omitir se vazio). |
| `answer_html` | string | HTML da resposta correta (omitir se vazio). |
| `images` | string[] | URLs de imagens usadas no enunciado (omitir se vazio). |

---

## Campos por tipo de questão

### multichoice · truefalse · calculatedmulti

Campo extra: **`choices`** — array de opções.

```json
{
  "v": 3, "slot": 1, "page": 0,
  "type": "multichoice",
  "html": "<p>Qual a capital do Brasil?</p>",
  "input": "q_local:1_answer",
  "seq": "seq-1",
  "feedback": "Brasília é a capital federal.",
  "answer_html": "<p>Brasília</p>",
  "choices": [
    { "v": "0", "h": "<p>São Paulo</p>",      "ok": false },
    { "v": "1", "h": "<p>Brasília</p>",       "ok": true  },
    { "v": "2", "h": "<p>Rio de Janeiro</p>", "ok": false }
  ]
}
```

> **`truefalse`**: apenas 2 choices — `v:"0"` = Falso, `v:"1"` = Verdadeiro.

Estrutura de cada choice:

| Chave | Tipo | Descrição |
|---|---|---|
| `v` | string | Valor enviado ao servidor (identificador da opção). |
| `h` | string | HTML exibido ao aluno. |
| `ok` | bool | `true` se esta é a resposta correta. |

---

### numerical · calculated · calculatedsimple · shortanswer · essay

Campo extra: **`answer_field`** — nome do campo de texto da resposta.

```json
{
  "v": 3, "slot": 2, "page": 0,
  "type": "numerical",
  "html": "<p>Quanto é 2 + 2?</p>",
  "input": "q_local:2_answer",
  "seq": "seq-2",
  "answer_html": "<p>4</p>",
  "answer_field": "q_local:2_answer"
}
```

> Para `essay`, `answer_html` pode ficar vazio (avaliação manual).

---

### match

Campo extra: **`match`** — premissas e opções de associação.

```json
{
  "v": 3, "slot": 3, "page": 0,
  "type": "match",
  "html": "<p>Associe cada país à sua capital:</p>",
  "input": "q_local:3_answer",
  "seq": "seq-3",
  "match": {
    "subs": [
      { "h": "<p>Brasil</p>",    "name": "q_local:3_sub0", "correct": "1" },
      { "h": "<p>Argentina</p>", "name": "q_local:3_sub1", "correct": "2" }
    ],
    "opts": [
      { "v": "1", "h": "<p>Brasília</p>",    "ok": false },
      { "v": "2", "h": "<p>Buenos Aires</p>","ok": false }
    ]
  }
}
```

Estrutura de `match`:

| Chave | Tipo | Descrição |
|---|---|---|
| `subs` | array | Premissas a associar. |
| `subs[].h` | string | HTML da premissa. |
| `subs[].name` | string | Nome do `<select>` desta premissa. |
| `subs[].correct` | string? | Valor correto (mesmo `v` de `opts`). |
| `opts` | array | Opções compartilhadas por todas as premissas (mesmo formato de choice). |

> `ok` nas `opts` do match é sempre `false` — a resposta correta vem de `correct` em cada sub.

---

### gapselect · ddwtos

Campo extra: **`gap`** — lacunas no texto e suas opções.

```json
{
  "v": 3, "slot": 4, "page": 0,
  "type": "gapselect",
  "html": "<p>O [[1]] é o astro-rei. A [[2]] é o satélite natural.</p>",
  "input": "q_local:4_answer",
  "seq": "seq-4",
  "gap": {
    "count": 2,
    "prefix": "q_local:4_p",
    "opts": [
      { "v": "1", "h": "<p>Sol</p>",  "ok": true  },
      { "v": "2", "h": "<p>Lua</p>",  "ok": true  },
      { "v": "3", "h": "<p>Marte</p>","ok": false }
    ]
  }
}
```

Quando cada lacuna tem opções diferentes, adicionar **`by_gap`**:

```json
"gap": {
  "count": 2,
  "prefix": "q_local:4_p",
  "opts": [],
  "by_gap": [
    [ { "v": "1", "h": "<p>Sol</p>",  "ok": true  }, { "v": "2", "h": "<p>Lua</p>",  "ok": false } ],
    [ { "v": "1", "h": "<p>Lua</p>",  "ok": true  }, { "v": "2", "h": "<p>Sol</p>",  "ok": false } ]
  ]
}
```

Estrutura de `gap`:

| Chave | Tipo | Descrição |
|---|---|---|
| `count` | int | Número de lacunas (`[[1]]`, `[[2]]`, …). |
| `prefix` | string | Prefixo do nome dos campos. Nome da lacuna N = `prefix + N`. |
| `opts` | array | Opções globais (mesmo formato de choice). |
| `by_gap` | array? | Opções por lacuna (só quando diferem). Omitir se todos usam `opts`. |

---

### ordering · multianswer (cloze)

Campo extra: **`controls`** — controles de formulário individuais.

```json
{
  "v": 3, "slot": 5, "page": 0,
  "type": "ordering",
  "html": "<p>Ordene os passos:</p>",
  "input": "q_local:5_answer",
  "seq": "seq-5",
  "controls": [
    { "name": "q_local:5_i0", "type": "select", "hl": "<p>Observação</p>",
      "opts": [{"v":"1","h":"1°","ok":false},{"v":"2","h":"2°","ok":false}] },
    { "name": "q_local:5_i1", "type": "select", "hl": "<p>Hipótese</p>",
      "opts": [{"v":"1","h":"1°","ok":false},{"v":"2","h":"2°","ok":false}] }
  ]
}
```

Estrutura de cada controle em `controls`:

| Chave | Tipo | Descrição |
|---|---|---|
| `name` | string | Nome do campo HTML. |
| `type` | string | `text`, `number`, `textarea`, `select`, `radio`, `checkbox`, `hidden`. |
| `hl` | string | HTML do rótulo exibido. |
| `value` | string? | Valor pré-preenchido (omitir se vazio). |
| `opts` | array? | Opções do controle (mesmo formato de choice; omitir se vazio). |

---

### ddmarker · ddimageortext

Campo extra: **`dd`** — imagem de fundo e marcadores arrastáveis.

```json
{
  "v": 3, "slot": 6, "page": 0,
  "type": "ddmarker",
  "html": "<p>Marque as capitais no mapa:</p>",
  "input": "q_local:6_answer",
  "seq": "seq-6",
  "images": ["https://exemplo.com/mapa.png"],
  "dd": {
    "bg": "https://exemplo.com/mapa.png",
    "choices": [
      { "no": 1, "name": "q_local:6_c1", "h": "Brasília", "inf": false, "n": 1 },
      { "no": 2, "name": "q_local:6_c2", "h": "Lima",     "inf": false, "n": 1 }
    ]
  }
}
```

Estrutura de `dd`:

| Chave | Tipo | Descrição |
|---|---|---|
| `bg` | string | URL da imagem de fundo. |
| `choices[].no` | int | Número do marcador. |
| `choices[].name` | string | Nome do campo de formulário. |
| `choices[].h` | string | Texto/rótulo do marcador. |
| `choices[].inf` | bool | `true` se o marcador pode ser usado múltiplas vezes. |
| `choices[].n` | int | Número máximo de arrastes. |

---

## Tipos Moodle suportados

| `type` | Campos extras |
|---|---|
| `multichoice` | `choices` |
| `truefalse` | `choices` (2 itens) |
| `calculatedmulti` | `choices` |
| `numerical` | `answer_field` |
| `calculated` | `answer_field` |
| `calculatedsimple` | `answer_field` |
| `shortanswer` | `answer_field` |
| `essay` | `answer_field` |
| `match` | `match` |
| `gapselect` | `gap` |
| `ddwtos` | `gap` |
| `ordering` | `controls` |
| `multianswer` | `controls` |
| `ddmarker` | `dd` |
| `ddimageortext` | `dd` |

---

## Como serializar/deserializar no Dart

```dart
import 'package:moodle_quiz_dep/core/utils/question_serializer.dart';

// QuestionEntity → Map (para passar via API ou JSON embutido em slide)
final map = QuestionSerializer.toJson(question);

// QuestionEntity → String JSON (para salvar em SQLite)
final jsonStr = QuestionSerializer.encode(question);

// Map → QuestionEntity (receber de API ou slide)
final question = QuestionSerializer.fromJson(map);

// String JSON → QuestionEntity (ler do SQLite)
final question = QuestionSerializer.decode(jsonStr);
```

> `fromJson` aceita tanto schema v3 quanto o v2 legado (retrocompatibilidade).

---

## Retrocompatibilidade

Registros em SQLite gravados antes do schema v3 (formato legado `htmlText`, `generalFeedback`, etc.)
**não são compatíveis** com `QuestionSerializer.decode`.  
Se necessário migrar dados antigos, use o branch de leitura v2 interno do serializador
chamando diretamente `QuestionSerializer.fromJson({'schema_version': 2, ...})`.
