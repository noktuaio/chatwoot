# Agente Operacional Autônomo — Estudo técnico de viabilidade

Síntese técnica das 5 sondagens codex feitas contra o código real deste fork (Chatwoot v4.15.1 EE white-label, "Autonom.ia"). Cada pilar tem um MD próprio com evidência (`probe-1..5`); este documento integra os achados, propõe a arquitetura aterrada no nosso stack e o plano de entrega de-riscado.

Data: 2026-06-20.

---

## 0. Veredito técnico

A **visão** é viável e tecnicamente coerente. O **plano "genérico/livre por padrão" do PRD não é seguro de começar** — as 5 sondagens, de forma independente, chegaram à mesma conclusão:

> Não construir a catedral genérica (Capability Gateway genérico + UI Bus universal + catálogo de toda a API + escrita autônoma) primeiro. Começar **read-only, curado e diagnóstico-primeiro**, e deixar o "genérico" **emergir das intenções reais**.

Três coisas que o PRD subestima e que decidem o resultado:
1. **Segurança das escritas** — undo genérico **não é viável** na arquitetura atual; muitos endpoints são destrutivos/irreversíveis.
2. **Custo de manutenção do catálogo + UI registry vs churn do upstream** — nossa pior fragilidade, amplificada.
3. **A autonomia "agir-por-padrão" conflita diretamente com as regras duras do dono** (não regressão, backup antes de destrutivo, confirmar exclusão/lote/externo).

O que é **forte e aproveitável já**: isolamento por conta (Pundit + `Current`), credencial de IA por conta, runtime Autonomia (RAG), o copiloto de conversa (cal39) que já trata transcrição como dado não confiável, e um precedente de "capability envelope" pronto pra copiar (`RestrictIntegrationTokenToCrm`).

---

## 1. Pilar API / Catalog / `call_operation` (probe-1)

**Números reais:**
- Superfície sob `api/v1/accounts`: ordem de **~600 endpoints** (119 `resources`, 202 verbos explícitos).
- **143 controllers** account-API (116 OSS + 27 EE).
- OpenAPI existe (`swagger/`) mas cobre só **99 operações** e **zero** dos namespaces custom (`crm`, `autonomia`, `campaign_imports`, `email_campaigns`). Servido só em dev/test.
- Contratos vivem em strong params espalhados (82 controllers com `permit`, 14 com `parameter_set` do CRM, 3 com `permit!`). Não há schema central.
- Pundit: **73 policies**, mas **0** `verify_authorized` global — autorização não é uniforme.

**Verdito:** catálogo **versionado e curado** (allow-list) + `search_operations` permission-aware = viável (M/L). `call_operation` genérico sobre toda a API = **não recomendado** (dano operacional, vazamento, drift). 

**Como fazer:** `call_operation(operation_id, params, confirmation_token)` que despacha por id pra um executor allow-listed (valida schema → resolve por `Current.account` → `authorize` → confirma se risco → executa via service existente → audita com redação). Catálogo como artefato de código dentro da imagem + **linter no build** que confirma que cada `operation_id` ainda existe (defesa contra drift do upstream).

**Segurança de escrita (evidência):** endpoints destrutivos reais — delete de contato/conversa/inbox (cascata async via `DeleteObjectJob`), `bulk_actions` (delete em massa), `reset_secret` (sem undo), `email_campaigns/send_now` (efeito externo), `crm/meetings/:id` (cancela evento externo de calendário), webhooks com `include_contact_pii`. Bloquear todos por default na 1ª fase.

---

## 2. Pilar UI Action Bus / UI Registry (probe-2)

**Números reais:**
- **17 `data-testid`** em **4.870 arquivos** de `app/javascript` (~0,23%). Praticamente nenhum nas telas operacionais (inbox, automação, contatos, autonomia).
- **142 rotas nomeadas** + `accountScopedRoute` + `meta.permissions`/`meta.featureFlag` → navegação por nome de rota é o padrão e é **altamente endereçável**.
- Bus `mitt` existente com **18 eventos** (incl. `INSERT_INTO_RICH_EDITOR`, que já usamos no copiloto) — bom transporte, **mau contrato** (global, sem resposta/erro/autorização).
- Formulários: 768 `v-model`, 138 `useVuelidate`, modais/componentes compostos → `fill`/`submit` genérico por DOM é **frágil**.

**Verdito:** `navigate`/`observe` por nome de rota = viável já. Controle fino (`fill`/`submit`) = só por **handlers estruturados por superfície**, não DOM scraping. UI Registry **pequeno e allow-listed**, não o app inteiro.

**Sequência recomendada:** (1) `navigate`+`observe` global por route registry; (2) piloto em **Campaign Import** (código nosso, baixo churn); (3) **criar automação** por payload estruturado; (4) **Instagram** só navegação + diagnóstico + iniciar OAuth (o passo determinante sai pro OAuth externo da Meta — não vender como E2E). Esforço: infra 2-4 dias; por superfície roteável 0,5-1 dia; modal/form 1-3 dias.

**Regra de sobrevivência ao update:** módulo próprio (`dashboard/operator/*`); tocar upstream só em 3-8 `data-testid` por superfície priorizada.

---

## 3. Pilar Diagnóstico (probe-3) — **a cunha de partida**

**O que já existe (sinais):** 149 jobs / 16 filas Sidekiq; webhooks (config + retry; eventos core+CRM); estados de canal com `Reauthorizable` (Instagram/Facebook/WhatsApp/Email/TikTok); **calendário S7 = o mais maduro** (`crm_calendar_sync_states`, free/busy, sync states por inbox); `Message.status` (sent/delivered/read/failed) + `external_error`; conversa/inbox/atribuição (round-robin, capacity EE); automation_rules; **63 feature flags**.

**8 diagnósticos propostos** (formato comum subject→checks→status→evidence→actions, read-only, gated):
`account_readiness`, `instagram_inbox`, `calendar_inbox`, `message_delivery` (MVP, ~1 semana) → `webhook_delivery`, `queue_health` (+1 semana) → `assignment_decision`, `automation_conflict` (+1-2 semanas, com linguagem de incerteza).

**Verdito:** **é por aqui que se começa.** Read-only, fortemente escopado por conta/inbox/conversa, baixo risco de regressão, deflete suporte direto. 

**Lacunas de infra a criar:** `correlation_id` (request→job→mensagem/webhook); tabela `webhook_deliveries` (hoje não há histórico de entrega); `diagnostic_runs` (auditoria do que o agente consultou); `account_id` padronizado nos jobs; mascaramento central de PII; API read-only namespaced (sem expor Sidekiq global ao tenant).

---

## 4. Pilar Project Intelligence / "commit implantado" (probe-4)

**Realidade:** prod roda **imagem Docker, sem checkout git**. Repo = ~2M linhas, 1.6 GB. `Dockerfile.crm` faz `COPY . /app`; `.git` **não** está no `.dockerignore` (risco de vazar histórico/IP). `.git_sha` existe mas é manual/frágil; `db/schema.rb` está **stale** (em `2026_06_26`, sem a migration `actuation`); Swagger não cobre custom; `ripgrep` não é instalado na imagem.

**Verdito: interno-primeiro.** Já temos esse pilar **hoje** via codex CLI (a LLM-de-dev lê o repo) — cobre o modo suporte/engenharia. Pra virar runtime confiável falta um **deploy manifest** (build-time: versão, commit, migrations aplicadas, flags, hashes) + um índice de código pré-construído. **Nunca expor código/paths ao usuário final** (IP) — só explicação sanitizada e orientada a ação; modo eng atrás de super admin.

**Esforço:** piloto interno útil 2-3 semanas; expor algo a usuário final com segurança 4-6 semanas.

---

## 5. Pilar Segurança / Escopo / Autonomia (probe-5) — **o pré-requisito**

**Números reais:** 73 policies; **81 `def destroy`**, **63 `.destroy!`**, **28 `.destroy_all`**, **14 `.delete_all`** (bypassa callbacks → péssimo pra undo), 91 linhas DELETE em rotas, 69 ocorrências `bulk`.

**Isolamento:** sólido — `Current.user/account/account_user` + Pundit hash + `policy_scope`; os controllers autonomia já são conta-scoped; CRM tem `AccessAuthorizer`/`VisibleScopeQuery`. **Toda ferramenta de escrita deve partir de `policy_scope`/`Current.account`, nunca de model direto.**

**Envelope de papel:** "é agente" **não basta** — por compatibilidade, agente sem custom role tem **CRM cheio** (`crm_permissions.rb`). O melhor padrão pra copiar é `RestrictIntegrationTokenToCrm` (mapa controller/action → escopo, **default-deny, calculado no backend**). O LLM propõe ferramenta+args; **nunca** declara papel/confirmação/reversibilidade.

**Undo genérico:** **NÃO é viável** — endpoints retornam estado final/`head :ok`, deletes em cascata/`delete_all`/jobs async, anexos purgados, efeitos externos (calendário/campanha) não se "desenviam". Undo tem que ser **por domínio** (ex.: `campaign_imports/undo_labels` e o archive de card são bons exemplos; o resto exige snapshot+confirmação).

**Modelo conservador-primeiro (níveis de risco):**
| Nível | Classe | Execução |
|---|---|---|
| R0 | Leitura/diagnóstico | Automática (Pundit/scope) |
| R1 | Escrita única reversível baixo impacto | Assistida: dry-run + auditoria |
| R2 | Lote/muitos registros | Confirmação + limite backend |
| R3 | Destrutivo/perda de dados/config/segurança/export | Confirmação + backup/snapshot |
| R4 | Efeito externo (envio/agenda/webhook) | Confirmação; undo não prometido |

Confirmação é **server-side referenciando o hash do plano** (não texto livre do modelo). Modo admin não remove confirmação de R3/R4.

---

## 6. Inventário de reuso (o que já temos)

| Eixo | Estado | Reuso real |
|---|---|---|
| Rollout/flags/kill-switch | Parcial | `DashboardController#app_config`, `Autonomia::Agents::Config` (ENV master + opt-in por conta) |
| Identidade/conta/Pundit | Parcial forte | `Current.*` + Pundit hash + `policy_scope` + autonomia conta-scoped |
| LLM runtime/credencial | Pronto p/ leitura | `Crm::Ai::CredentialResolver` (por conta) + `ResponsesClient` (store:false, anti-SSRF, log sem prompt) |
| Chat assistivo | Parcial | `Autonomia::Copilot::ConversationChat` + widget (cal39) — preso à conversa; falta assistente global |
| RAG/knowledge | Parcial | runtime Autonomia (34 services) — falta KB **da própria plataforma** (rotas/policies/manuais) |
| Diagnóstico read-only | Parcial | sinais existem; falta camada unificada de tools com redação |
| Action runner/registry | **Falta** | services de domínio reaproveitáveis, mas sem registry seguro |
| Capability envelope/risco | **Falta (padrão existe)** | copiar `RestrictIntegrationTokenToCrm` |
| Undo/backup/auditoria | Parcial | undo por domínio (campaign import, card archive); `Crm::ActivityLogger` |
| Project Intelligence | Parcial | codex CLI (interno) — falta manifest de deploy |

---

## 7. Arquitetura recomendada (aterrada no nosso stack)

Reusar o núcleo Autonomia e o padrão de gating. Novos componentes no namespace `operator`/`autonomia`, gated por `OPERATOR_AGENT_ENABLED` (default off) + opt-in por conta.

- **Operator Core** — orquestra (intenção → contexto → plano → tools → validação → resposta). Reusa `ResponsesClient` + credencial por conta.
- **CapabilityEnvelope** — calcula no backend o que o ATOR corrente pode (a partir de `Current.*` + policies + flags). Nunca confia no modelo.
- **ActionRegistry** — default-deny; cada ação declara policy, scope resolver, schema, risco (R0-R4), limite de lote, confirmação, backup, undo, efeito externo. Padrão = `RestrictIntegrationTokenToCrm`.
- **DiagnosticsService** (read-only) — os 8 diagnósticos, namespaced + Pundit + PII-mask.
- **UI Registry + Operator Bus** — pequeno, allow-listed; `navigate`/`observe` global + handlers por superfície priorizada; wrapper sobre `mitt`.
- **DeployManifest + ProjectIntel (interno)** — manifest no build; busca de código só em modo eng/super-admin.
- **AuditLog** — toda ação do agente, com ator humano, plano, registros afetados, redação.
- **Core MCP** — manter a fronteira desde o dia 1 (as tools expostas como capacidades reutilizáveis).

---

## 8. Plano de entrega de-riscado

| Fase | Entrega | Risco | Esforço |
|---|---|---|---|
| **F0 — Design + provas de segurança** | Envelope/registry/auditoria desenhados + provados; OPERATOR_AGENT_ENABLED; manifest de deploy + `.dockerignore`/`.git_sha`/schema.rb | baixo | 1-2 sem |
| **F1 — Agente READ-ONLY (o MVP de valor)** | Diagnóstico (4 MVP) + descoberta/navegação (route registry) + project-intel interno + chat global de plataforma. Reusa LLM/credencial/gates | baixo | 3-5 sem |
| **F2 — Escrita R1** | ActionRegistry + dry-run + auditoria + confirmação + primeiras escritas reversíveis (atribuir conversa, label, prioridade, card move/archive) | médio | 4-6 sem |
| **F3 — Lote R2 + UI guiada** | Lote limitado com confirmação; handlers de UI (campaign import, automação) | médio/alto | 3-5 sem |
| **F4 — Destrutivo R3/R4** | Por domínio, com snapshot/restore testado + confirmação | alto | 8-12+ sem/domínio |

**Caminho crítico:** F0 (segurança) **precede** qualquer escrita. F1 entrega valor real (deflexão de suporte) com risco baixo e reuso alto — é onde provar a tese.

---

## 9. Riscos técnicos principais

1. **Undo genérico inexistente** → escrita ampla sem snapshot por domínio = perda de dados.
2. **Drift de rota/contrato** (upstream + EE + custom) → catálogo quebra; mitigar com linter no build.
3. **Churn de UI** → registry quebra; mitigar com poucos `data-testid` próprios + payload estruturado.
4. **Cross-account/PII** → todo finder via `policy_scope`; redação central.
5. **Prompt injection operacional** (texto de conversa induzindo ação destrutiva) → envelope backend + confirmação por hash de plano.
6. **IP** (Project Intel vazando código ao usuário final) → modo eng atrás de super admin.
7. **`.git`/`public/vite` na imagem** → corrigir `.dockerignore`.
8. **Custo por resolução** sem meta → roteamento de modelo + métrica.

---

## 10. Decisões que travam o início

1. **Postura de autonomia**: confirmar **conservador-primeiro** (read-only → R1 → R2; R3/R4 sempre com confirmação+backup)? Isso reconcilia o PRD com as suas regras duras.
2. **Top ~15 intenções reais** (dos chamados de suporte) — é o que escopa a F1 (o próprio PRD aponta isso como próximo passo nº 1).
3. **Project Intelligence interno-primeiro** (IP)?
4. **Meta de custo por resolução.**
5. **Escopo do 1º release** = read-only (diagnóstico + descoberta + project-intel interno + chat global). Recomendado.

> Documentos de evidência por pilar: `probe-1-api-catalog.md`, `probe-2-ui-bus.md`, `probe-3-diagnostics.md`, `probe-4-project-intel.md`, `probe-5-security-autonomy-reuse.md`.
