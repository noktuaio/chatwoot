# Agentes Autonom.ia — Plano de Remediação (auditoria codex 2026-06-22)

## Sumário executivo

A página **Agentes Autonom.ia** (builder por IA, base de conhecimento/RAG, operação ao vivo com handoff, copiloto, hub/painel) foi auditada de ponta a ponta — codex + revisor por área, 6 áreas em paralelo, ~6,7k linhas BE + FE.

**Veredito: frágil, não quebrado.** A espinha de segurança é genuinamente sólida — toda rota é *account-scoped*, agentes de sistema (Guia) ocultos, anti-loop/debounce/token bem desenhados, material ingerido tratado como **dado não-confiável** com defesas de prompt-injection em camadas, e falhas de IA caem em **handoff seguro** em vez de 500. **Nenhum IDOR cross-tenant confirmado.** Os pontos fracos são de **robustez de caminho triste** e **paridade de hardening**, não de arquitetura.

**Contagem:** 1 P0 · 22 P1 · ~24 P2 · ~9 P3 (55 achados; concordância codex alta, exceto a área Knowledge cujo codex não terminou na janela → re-rodar antes de mexer nela).

**Risco dominante:**
1. **1 P0 de segurança** — `EmbeddingService` alcança a rede com `api_base` controlável pela conta **sem validação SSRF** (gap de paridade vs `ResponsesClient`). Atinge ingestão, Testar e auto-resposta.
2. **Operate (auto-resposta ao vivo)** — handoff age após um humano assumir; sem recheck autoritativo de elegibilidade no meio do voo; falha de envio do provedor é invisível; conversa pode ficar presa em `pending`; corrida na conexão de inbox pode pôr 2 bots numa caixa; desabilitar/destruir agente não libera conversas pending.
3. **Answer/RAG** — gate de grounding parcialmente auto-certificado pelo modelo; `raw_reply` pré-gate pode vazar ao usuário; `Retriever` fail-open em erro de banco; `web_search` ligado por padrão sem trilha de citação.
4. **Concorrência** — *lost-updates* em jsonb (build_thread, recompute, config), conexão de inbox check-then-act.
5. **Frontend** — Painel quebra sem estado de erro; stores singleton com dado stale cross-agente; poll de ingestão infinito; turnos otimistas não revertidos; PanelTest envia turno em dobro.

**Abordagem (igual ao resto do projeto):** ondas incrementais, cada uma = implementar → teste real (feliz **e** triste) no harness → review codex (GO) → **deploy só com OK**; backup antes de qualquer migração; zero regressão; gate `eager_load`. Nada destrutivo sem backup.

**Ordem recomendada:** Onda 1 (segurança P0+SSRF/kill-switch) → Onda 2 (Operate, maior risco operacional) → Onda 3 (Answer/RAG) → Onda 4 (Builder/lifecycle) → Onda 5 (Frontend) → Onda 6 (P2/P3 em lote). As Ondas 1–5 são as P1; a 6 é hardening.

**Esforço estimado:** Onda 1 ~M · Onda 2 ~L · Onda 3 ~M · Onda 4 ~M · Onda 5 ~M · Onda 6 ~L (lote). Cada onda é deployável isoladamente.

---

## Onda 1 — Segurança (P0 + SSRF/kill-switch)

| # | Sev | Achado | Fix | Arquivos | Migr. |
|---|-----|--------|-----|----------|-------|
| 1 | **P0** | `EmbeddingService` sem validação SSRF do `api_base` da conta | Extrair `validate_api_base!` do `ResponsesClient` para um guard compartilhado (HTTPS-only, sem userinfo/query, resolve DNS + bloqueia loopback/privado/link-local/metadata) e aplicar **antes** de montar o contexto RubyLLM | `services/autonomia/agents/embedding_service.rb`, `services/crm/ai/responses_client.rb` (extrair) | não |
| 2 | P1 | Link ingestion SSRF por **DNS rebinding** (valida hostname, não o socket) | Resolver uma vez, validar o IP resolvido, **fixar a conexão a esse IP** (connect-by-IP + Host header). ⚠️ codex não confirmou (área Knowledge) → **re-rodar codex em Knowledge primeiro** | `services/autonomia/agents/knowledge/url_guard.rb`, `processors/link.rb` | não |
| 3 | P1 | Copiloto **ignora o kill-switch** `Autonomia::Agents::Config.enabled?` | Exigir `Config.enabled?(Current.account)` em `ensure_copilot_enabled` | `controllers/.../conversation_copilot_controller.rb` | não |
| 4 | P1 | Agente **desabilitado** ainda usável como copiloto | `where(enabled: true)` na listagem e no `resolve_agent` | `services/autonomia/copilot/conversation_chat.rb`, `conversation_copilot_controller.rb` | não |
| 5 | P1 | Imagens do builder = blobs ActiveStorage **globais, sem dono, sem expiração** | Vincular upload a um registro por-thread/conta com token expirável + verificar posse no `image_part` + purgar pós-uso/TTL | `controllers/.../builder_images_controller.rb`, `build_threads_controller.rb`, `services/.../builder.rb` | possível (tabela/coluna) |

**Teste:** stub de `api_base` interno → guard **levanta** (embedding + link); copiloto 403 quando Autonomia off; agente disabled some da listagem; signed_id de outro escopo rejeitado. **Sem migração** exceto #5 (avaliar: associação por-thread vs tabela).

---

## Onda 2 — Operate (auto-resposta ao vivo + handoff) — maior risco operacional

| # | Sev | Achado | Fix | Arquivos | Migr. |
|---|-----|--------|-----|----------|-------|
| 6 | P1 | Handoff age após humano assumir (só checa `pending?`) | Exigir `pending? && assignee_id.blank?` (+ agente ainda elegível) dentro do lock do handoff | `operate/handoff_handler.rb` | não |
| 7 | P1 | Sem recheck autoritativo de elegibilidade no meio do voo | Predicado único `Operate.eligible_for_delivery?(conversation, agent_inbox)` recarregado **dentro de cada lock** (reply/handoff/cada chunk) — inclui enabled/active/não-interno/não-system | `operate/responder.rb`, `operate.rb`, `jobs/.../chunked_delivery_job.rb`, `handoff_handler.rb` | não |
| 8 | P1 | Falha de envio do provedor **invisível** ("replied" logado) | Observar Message outgoing AgentBot com `status==failed` → retry/handoff/alerta | novo observer/listener + `operate/*` | não |
| 9 | P1 | `HandoffHandler :error` engolido → conversa presa em pending | `Responder#handoff` inspeciona o `Result`; em `:error` re-levanta/retry (Sidekiq) | `operate/responder.rb` | não |
| 10 | P1 | Conexão de inbox check-then-act sem lock → **2 bots numa inbox** + 500 | Lock da row do inbox + re-check na txn; rescue `RecordNotUnique`→422; avaliar índice único "bot ativo por inbox" | `operate/inbox_connector.rb` | **avaliar** (índice em tabela core — cuidado) |
| 11 | P1 | Desabilitar/destruir/pausar agente conectado **não libera** conversas pending | Liberar pending (`bot_handoff!`) no `after_destroy` do AgentInbox e na transição p/ status não-operável; desativar AgentBotInbox | `models/.../agent_inbox.rb`, `models/.../agent.rb`, `operate/inbox_connector.rb` | não |

**Teste (harness, conta real):** humano assume durante a IA → bot **não** posta/reassina; agente desabilitado no meio do voo → não entrega; envio falho → handoff/alerta; handoff com erro → não fica preso; 2 conexões concorrentes → 1 bot só; destruir agente conectado → conversas pending liberadas. **Cuidado #10:** índice único em `agent_bot_inboxes` (tabela core) pode colidir com bots não-Autonomia → preferir lock+check app-level; índice parcial só se seguro.

---

## Onda 3 — Answer / RAG (qualidade e segurança da resposta)

| # | Sev | Achado | Fix | Arquivos |
|---|-----|--------|-----|----------|
| 12 | P1 | Gate de grounding **auto-certificado** (bypassável com zero snippets) | Exigir `used.any?`/citação para "grounded"; **capar confiança** abaixo do threshold quando a recuperação falhou/vazia | `services/autonomia/agents/answerer.rb` |
| 13 | P1 | `raw_reply` pré-gate servido ao usuário quando `reply` vazio | Confinar `raw_reply` a fluxos de revisão humana (renomear `unsafe_*`); **nunca** como fallback ao usuário | `answer_result.rb`, `guide/chat.rb`, `copilot/conversation_chat.rb`, `conversation_copilot.rb` |
| 14 | P1 | `Retriever` engole erro de DB em `[]`; scoping out-of-business fail-**open** | `[]` só para erro de embedding/provedor; erro de DB = falha distinta → handoff seguro; **fail-closed** no isolamento cross-business | `services/autonomia/agents/retriever.rb` |
| 15 | P1 | `web_search` ligado por padrão sem trilha de citação | Default **off** p/ agentes de produção **ou** carregar `tools_used`/citações no `AnswerResult` e gatear resposta web | `answerer.rb`, `answer_result.rb` |
| 16 | P2 | Snippets recuperados injetados sem moldura "dado não-confiável" | Envolver `context_message` como dado não-confiável (igual ao Guia/Construtor) | `prompt_builder.rb` |

**Teste:** retrieval vazio + modelo "confiante" → confiança capada / handoff (não resposta ungrounded); sem fallback_message → **não** vaza raw_reply; erro de pgvector → handoff (não "sem KB"); snippet com instrução maliciosa → ignorado.

---

## Onda 4 — Builder + lifecycle (correção)

| # | Sev | Achado | Fix | Arquivos |
|---|-----|--------|-----|----------|
| 17 | P1 | `append_message!` *lost-update* (read-modify-write de jsonb sem lock) | Lock da row para append + flag + `begin_build!`; chave de idempotência do cliente | `models/.../build_thread.rb`, `build_threads_controller.rb` |
| 18 | P1 | Adjust-mode: 2 threads do mesmo agente não se superseden | Token/versão de builder **a nível de agente** (marca threads antigas como superseded) | `build_threads_controller.rb`, `models/.../agent.rb` |
| 19 | P1 | Saída do builder não revalidada + drift de `with_knowledge` | Final exige `instruction`/`human_card` não-vazios; `needs_more_info` ausente → tratar como `true`; em adjust-mode **preservar** `with_knowledge` salvo se a thread setou explicitamente | `services/.../builder.rb` |

**Teste:** double-click/2 abas → turno não some/duplica; 2 ajustes concorrentes → o mais novo vence; schema com instruction vazia → não persiste agente vazio; re-tunar agente sem-KB → não vira com-KB.

---

## Onda 5 — Frontend

| # | Sev | Achado | Fix | Arquivos |
|---|-----|--------|-----|----------|
| 20 | P1 | Painel renderiza agente quebrado/em branco quando `show` falha | `loadError`/`notFound` + retry; corpo só com `agent?.id`; `watch(agentId, immediate)` | `pages/AgentPanelPage.vue` |
| 21 | P1 | Stores singleton sources/channels sem dono → stale cross-agente | Guardar `currentAgentId`; descartar respostas/polls que não batem com o agente ativo | `store/modules/autonomiaSources.js`, `autonomiaChannels.js` |
| 22 | P1 | Poll de ingestão **infinito** sem teto/erro | Teto de tentativas + retry com catch + falha visível | `store/modules/autonomiaSources.js` |
| 23 | P1 | Turnos otimistas do builder nunca revertidos; finalize sem guard | Estado pending/failed por mensagem + idempotência; capturar/comparar thread ativa no dispatch; finalize silencioso que não muta após unmount | `store/modules/autonomiaBuildThreads.js`, `pages/AgentBuilderPage.vue` |
| 24 | P1 | PanelTest envia o turno **em dobro** (history + message) | Snapshot do history antes de anexar o turno do usuário | `components/panel/PanelTest.vue` |

**Teste (browser real):** show 404 → estado de erro+retry (não tela em branco); trocar de agente → sem dado stale; ingestão travada → para de pollar com aviso; falha de turno → marcador + sem duplicar no retry; PanelTest → backend vê o turno 1×.

---

## Onda 6 — Hardening P2/P3 (em lote)

Itens P2/P3 agrupados (sem risco de produção isolado, mas valem):
- **Data-loss:** extração vazia/corrompida marca source `ready` com 0 chunks e **apaga KB** no resync → não apagar se a nova extração for vazia (P2).
- **Embedding:** modelo configurável pode não bater com `vector(1536)` → validar dimensão (P2); 1 erro transitório falha o source inteiro → retry/backoff por chunk (P2); timeout 120s na resposta síncrona + log verbatim do provedor (P2).
- **Concorrência:** `recompute_overall!` lost-update no `agent.config` (P2); transação separada agent-write vs thread-ready (P2).
- **API/controllers:** `config` mass-assign sobrescreve chaves runtime + jbuilder vaza `knowledge_refresh_token` (P2); enum inválido → 500 em vez de 422 (P2); input ilimitado no boundary (P2); `SubmitJob` não re-checa flag (P2); falha do builder nunca exibida no FE (P2).
- **Operate:** `active_for?` mais fraco que o gate do ReplyJob (P2); ChunkedDeliveryJob duplicado reagenda o resto mesmo sem postar (P2); "digitando" pode vazar (P2); idempotência por regex em `content_attributes` frágil (P3).
- **Knowledge:** link buffeia o body inteiro antes do `MAX_BYTES` (DoS de memória) (P2); `source_type` não validado contra o arquivo real (P3); DELETE /channels não idempotente (P2).
- **Reaper:** sem timeout/reaper p/ `processing` travado (build/knowledge) + sem retry de job (P2).
- **FE:** falhas de fetch inicial não exibidas (P2); SourceAddDialog validação fraca (P2); PanelTune salva `manual` com instruction vazia (P2); range toggle dispara load duplicado (P2); ChatComposer vaza object URLs (P3); ARIA das tabs (P3).
- **Schema/modelo:** `db/schema.rb` sem a coluna `actuation`/suite (drift — regerar) (P3); validações de consistência de conta em AgentInbox/AgentEvent (P3); flags `no_materials`/`force_close` "sticky" mas `false` explícito desfaz (P3); refine do copiloto interpolado no system prompt (P3).
- **Prompt-injection (output-side):** sem filtro determinístico de vazamento na resposta ao cliente / campos visíveis do builder (P2).

---

## Notas de execução
- **Metodologia por onda:** backup pré-mudança (e pré-migração); implementar; teste real feliz+triste no harness (`up_web`); review codex crítico → GO; deploy `start-first` web+sidekiq + re-seed/verificação; **deploy só com OK explícito do PO**.
- **Migrações:** apenas #5 (talvez) e #10 (avaliar — tabela core, cuidado) podem precisar; ambas aditivas, backup antes.
- **Knowledge:** re-rodar codex na área antes de tocar (#2 e os P2 de Knowledge são revisor-only).
- **Discordância registrada:** #5 (builder images) — codex=P0, revisor=P1 (exige já possuir signed_id de outro tenant). Tratado como P1.
- **Zero regressão:** o caminho feliz atual (anti-loop, debounce, lock+re-eval, idempotência) é bom e deve ficar byte-equivalente onde não for o alvo do fix.
