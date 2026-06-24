# CRM Kanban PR 13.1 — Contexto multimodal para a IA (áudio via Whisper, imagem via GPT-vision)

> **STATUS: IMPLEMENTADO E DEPLOYADO (2026-06-09)** — imagem `crm13.1` em web + Sidekiq. E2E verificado em produção com mídia real da conta 6:
> - Áudio (`audio/mpeg`) → `gpt-4o-mini-transcribe`: *"Boa noite, tudo bem? Pra qual destino será a viagem?"* (~2s).
> - Imagem (`image/jpeg`) → `gpt-5.4-mini` (visão confirmada): legenda correta lendo o texto do cartaz (~2s).
> - `attachment.meta` cacheado, `needs_enrich?` idempotente, `ContextBuilder` combinando texto + `[áudio transcrito]` + `[imagem]`.
> Decisões aplicadas: transcrição CRM-própria (chave do hook, cache compartilhado `transcribed_text`); marcador de presença para vídeo/documento. Kill-switch: `CRM_AI_MEDIA_ENABLED=false`. Rollback: `crm13-r3`.
>
> **Imagem final `crm13.1-r2`** — fix de janela de contexto: `Message` tem `default_scope(created_at: :asc)`, então `ContextBuilder`/`MediaEnricher` precisam de `.reorder(id: :desc)` (antes pegavam as 12 mensagens mais ANTIGAS — bug latente do PR13). Validado em teste live (conv display_id=87): mídia entra na janela e a IA lê `[áudio transcrito]`/`[imagem]`.


## 1. Objetivo

Hoje a IA que classifica/move cards lê **apenas texto**. Conversas com áudio e/ou imagem chegam "vazias" para o avaliador — uma conversa só de áudios não dá nenhum insumo. PR13.1 transforma áudio e imagem em **texto** (transcrição + legenda) e injeta esse texto no contexto montado para a IA. Vídeo e documento ficam **fora de escopo** (apenas marcador opcional de presença).

## 2. Pipeline atual (como a conversa é montada hoje)

Caminho de execução:

```
Crm::Conversations::CardSyncer#schedule_ai_evaluation        (app/services/crm/conversations/card_syncer.rb:53)
  → Crm::Ai::Observer#schedule_evaluation  (debounce 15s)    (app/services/crm/ai/observer.rb)
    → Crm::Ai::EvaluateCardJob                                (app/jobs/crm/ai/evaluate_card_job.rb)
      → Crm::Ai::Evaluator#perform                            (app/services/crm/ai/evaluator.rb)
          ├─ Crm::Ai::ContextBuilder#perform   ← MONTA A CONVERSA
          └─ Crm::Ai::StageClassifier#perform  → ResponsesClient (POST /v1/responses)
```

**Onde está o gargalo — `ContextBuilder#format_message` (context_builder.rb:40-47):**

```ruby
def format_message(message)
  role = message.incoming? ? 'customer' : 'agent'
  { role: role, content: message.content.to_s.truncate(2000), created_at: message.created_at.iso8601 }
end
```

- Usa **só `message.content`**. Mensagens de áudio/imagem têm `content` vazio (o conteúdo está no **attachment**, não em `content`). → contribuem com string vazia.
- `MAX_RECENT_MESSAGES = 12`, ordenadas por `created_at desc`, só `private:false` e não-`activity`. Isso é suficiente; o trigger **não** é gated por texto.
- `recent_messages` é serializado como **JSON-texto** em `StageClassifier#user_input` e enviado como `input` (string) ao Responses API. Pipeline 100% texto.

**Confirmação importante:** o `schedule_ai_evaluation` dispara em **qualquer** mensagem (incl. áudio/imagem only) — o `CardSyncer` roda no sync da conversa. Ou seja, o disparo já acontece; falta **só** extrair o conteúdo da mídia no `ContextBuilder`.

## 3. Infra existente reaproveitável (descobertas)

1. **`attachment.meta` é `jsonb`** (cache pronto, sem migration).
2. **`Attachment#file_type`** enum: `image:0, audio:1, video:2, file:3, ...` — classificação trivial.
3. **Chatwoot EE já transcreve áudio:** `enterprise/app/services/messages/audio_transcription_service.rb`
   - Modelo `gpt-4o-mini-transcribe`, limite 25 MB, temp file, `temperature: 0.0`.
   - **Cacheia em `attachment.meta['transcribed_text']`** ← chave canônica a reutilizar.
   - Porém é **gated por Captain** (`captain_integration` + `account.audio_transcriptions` + usage limits) e usa a **chave do Captain**, não a do hook `crm_kanban_ai`.
4. **`ruby-openai` 7.3.1** disponível (`OpenAI::Client#audio.transcribe`, e chat/responses).
5. **`Attachment#download_url`** (S3 presigned) e `file.blob.open` (bytes) — storage de produção é `s3_compatible` (bucket `chatwoot`).
6. **Credencial CRM**: `Crm::Ai::CredentialResolver#resolve` → `{api_key, api_base, source}` (hook da conta 6 tem `api_key` salva).

## 4. Arquitetura proposta — "mídia → texto, cacheada"

**Princípio:** NÃO mandar áudio/imagem crus ao classificador a cada avaliação. Em vez disso, **pré-converter mídia em texto uma vez por attachment, cachear no `attachment.meta`**, e o `ContextBuilder` apenas lê esse texto. Vantagens:

- Classificador permanece **texto+JSON** (modelo/prompt inalterados, barato, determinístico).
- **Sem reprocessar** a cada debounce de 15s nem a cada re-avaliação de card "stale".
- Funciona mesmo que o modelo de classificação (`gpt-5.4-mini`) não tenha visão.
- Custo de Whisper/vision isolado e pago **uma vez** por mídia.
- Alinha com o pedido: usar Whisper para áudio e GPT-vision para imagem como parte da conversa montada.

### Fluxo

```
nova mensagem com mídia
   → EnrichMessageMediaJob (assíncrono, SEM debounce, dispara já)   [novo]
        → Crm::Ai::MediaEnricher                                     [novo]
             áudio  → transcreve (gpt-4o-mini-transcribe) → attachment.meta['transcribed_text']
             imagem → legenda (Responses+vision)          → attachment.meta['ai_caption']
   ...em paralelo, Observer agenda Evaluator com debounce 15s
   → Evaluator → ContextBuilder (lê meta cacheada; lazy-enrich se faltar, com teto)
```

## 5. Componentes (novos / alterados)

| Arquivo | Ação |
|---|---|
| `app/services/crm/ai/media_enricher.rb` | **novo** — por mensagem, itera attachments: áudio→transcrição, imagem→legenda; idempotente (pula se `meta` já preenchida); grava em `attachment.meta`. |
| `app/services/crm/ai/transcription_client.rb` | **novo** — `OpenAI::Client.new(access_token: cred[:api_key], uri_base: "#{cred[:api_base]}/v1").audio.transcribe(model: 'gpt-4o-mini-transcribe', file:, temperature: 0.0)`. Usa credencial **do hook CRM** (independe do Captain). Limite 25 MB, idioma `pt`. |
| `app/services/crm/ai/vision_captioner.rb` | **novo** — legenda curta (≤ ~400 chars) de imagem via `ResponsesClient` com input multimodal (`input_image` em data-URL base64). Prompt: "descreva objetivamente a imagem desta conversa de atendimento". |
| `app/services/crm/ai/responses_client.rb` | **alterar** — aceitar `input` como **array** de itens (`{role, content:[{type:'input_text'...},{type:'input_image', image_url:'data:...'}]}`), além de string. Hoje só manda string. |
| `app/jobs/crm/ai/enrich_message_media_job.rb` | **novo** — wrapper assíncrono de `MediaEnricher` (fila default), com retry limitado. |
| `app/services/crm/ai/context_builder.rb` | **alterar** — `format_message` passa a compor `content` a partir de: texto + `[áudio]: <transcrição>` + `[imagem]: <legenda>` (lendo `attachment.meta`). Mídia sem enrich ainda → lazy-enrich síncrono com **teto de N itens** por avaliação (ex.: 3) para limitar latência/custo; ou marcador `[áudio recebido, não transcrito]`. |
| `app/services/crm/conversations/card_syncer.rb` | **alterar (mínimo)** — ao detectar mensagem nova com mídia, enfileirar `EnrichMessageMediaJob` (além do `schedule_ai_evaluation` atual). |
| `app/services/crm/ai/config.rb` | **alterar** — flags: `CRM_AI_MEDIA_ENABLED` (kill-switch), `TRANSCRIBE_MODEL`, `MAX_ENRICH_PER_EVAL`, limites de tamanho/duração. |

Cache (sem migration): `attachment.meta['transcribed_text']` (interopera com Chatwoot) e `attachment.meta['ai_caption']` + `attachment.meta['crm_ai_enriched_at']`.

## 6. Roteamento de modelo

- **Transcrição:** `gpt-4o-mini-transcribe` (mesmo do Chatwoot EE; barato, bom em pt-BR). Fallback `whisper-1`.
- **Legenda de imagem:** modelo com visão. **Confirmar** se `gpt-5.4-mini` aceita `input_image`; se não, usar `gpt-5.4` (já é o modelo de auto-move) ou `gpt-4o-mini` para a legenda. Como a legenda é cacheada, o custo é pago 1x por imagem.
- **Classificador:** **inalterado** (`gpt-5.4-mini` / `gpt-5.4`), continua recebendo só texto.

## 7. Custos, limites e guardrails

- Transcrição `gpt-4o-mini-transcribe`: ~US$0,003/min (cacheada → 1x). Limite **25 MB** (reusar `TRANSCRIPTION_BYTE_LIMIT = 25_000_000`); áudio maior → pula, marca `[áudio longo não transcrito]`.
- Legenda: 1 chamada vision por imagem (cacheada). Truncar legenda (~400) e transcrição (~1500) chars antes de entrar no contexto.
- Teto `MAX_ENRICH_PER_EVAL` no lazy-path para não estourar latência do job.
- Tudo com `store:false` na OpenAI (já é o caso no `ResponsesClient`).
- Idempotência: enrich pula se `meta` já tem o campo → re-deploys/re-avaliações não repagam.

## 8. Trigger e ordenação

- `EnrichMessageMediaJob` é enfileirado **imediatamente** (sem o wait de 15s) quando chega mídia; a avaliação continua com debounce de 15s → na prática a transcrição já está pronta quando o `Evaluator` roda.
- Se ainda não estiver, `ContextBuilder` faz lazy-enrich síncrono (teto N) ou usa marcador; a avaliação **nunca** é bloqueada por falha de mídia.

## 9. Privacidade / LGPD

- Áudio e imagem do cliente passam a ser enviados à OpenAI (hoje já enviamos o texto). Voz/imagem são dados pessoais → vale registrar no aviso de privacidade/consentimento e manter `store:false`. Kill-switch `CRM_AI_MEDIA_ENABLED` e por-pipeline `ai.media_enabled` para desligar.

## 10. Casos de borda

- **Conversa só de áudio:** passa a ter transcrições → sinal real. (Resolve o caso citado.)
- **Conversa só de imagem:** legendas dão contexto.
- **Vídeo / documento:** fora de escopo. Opcional: marcador `[vídeo recebido]` / `[documento recebido]` para a IA saber que houve mídia não-processada (evita assumir "silêncio"). Sem download/processamento.
- **Transcrição vazia / silêncio:** `temperature: 0.0` minimiza alucinação; texto vazio → trata como sem conteúdo.
- **Falha OpenAI (401/limite):** loga, segue avaliação com o que houver.

## 11. Testes e smoke E2E

- **Unit:** `MediaEnricher` com clients stubbados (áudio→texto fake, imagem→legenda fake); `ContextBuilder` montando content combinado; idempotência (não rechama quando `meta` preenchida).
- **E2E (conta 6):** enviar para uma conversa um **áudio** e uma **imagem** reais (WhatsApp) → confirmar `attachment.meta['transcribed_text']` / `['ai_caption']` populados → rodar `Crm::Ai::Evaluator` e inspecionar `ContextBuilder#perform` mostrando o texto da mídia → confirmar classificação coerente.

## 12. Rollout

- **Backend-only** (sem frontend) → **não precisa rebuild Vite**; reusar `public/vite` atual.
- Build imagem `chatwoot-campaign-import:v4.14.1-20260609-crm13.1` (`docker build -f docker/custom/Dockerfile.crm`), deploy **web + Sidekiq** (`--no-resolve-image`; Sidekiq roda o job de enrich e a avaliação).
- **Sem migration** (usa `attachment.meta`).
- Rollback: voltar para `...-crm13-r3`.

## 13. Fora de escopo (PR13.1)

- Processamento de vídeo e documento (PDF/office).
- UI mostrando transcrição no card (pode ser PR futura).
- Resumo de conversa (`MODEL_SUMMARY`) — campo `summary` existe mas hoje não é populado; avaliar em PR separada.

## 14. Riscos / questões em aberto

1. `gpt-5.4-mini` aceita `input_image`? (confirmar; senão rota de legenda usa `gpt-5.4`/`gpt-4o-mini`).
2. `uri_base` do hook é OpenAI padrão? Se for Azure/compatível, ajustar caminho de `audio.transcribe`.
3. Volume de mídia → custo: definir `MAX_ENRICH_PER_EVAL` e limites de tamanho como config.
4. Decidir: transcrição CRM-própria (hook key) **ou** reutilizar a do Captain quando habilitada (ler `attachment.meta['transcribed_text']` já existente). Proposta: **CRM-própria**, mas **lendo a mesma chave de cache** para interoperar.
