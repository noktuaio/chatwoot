# Envio Direto por Webmail — Status & Roadmap

Trilha de e-mail (imagens `…-email-N`). Pequenos negócios usam Gmail/Hotmail/Outlook/Yahoo
gratuitos para falar com clientes. Quando o sistema detecta uma caixa de webmail conectada,
ela vira opção no "Domínio de envio" da campanha e o disparo sai **direto pela conexão própria
do cliente** (NÃO pela Amazon SES — SES não autentica webmail), com throttle humano e avisos.

## Imagem em produção
- **Atual:** `chatwoot-campaign-import:v4.14.1-20260615-email-13` (web + Sidekiq, 1/1).
  email-13 = fix do gráfico (timeline `since` em `created_at`, não `sent_at`) + alinhamento do
  botão Exportar CSV (reestrutura flex). email-12 = registro de entrega no envio direto
  (aceite do provedor = `delivered`) + sync de status no claim. email-11/10 = Fase A backend/FE
  + 6 fixes do Codex. email-5..9 = OAuth Microsoft/Google (Fase 1/2) + AADSTS70011.

## Fase A — Envio direto por webmail (MVP) — ✅ ENTREGUE E DEPLOYADO (email-13), E2E real validado
Disparo real validado: rovictor@hotmail.com (inbox 154, Microsoft/Graph) → comercial@autonomia.site,
e-mail de divulgação gerado por IA com logo/cores da Autonomia, abertura+clique+entrega no dashboard.

**O que foi entregue:**
- **Modelo** (`EmailCampaign`): `enum delivery_mode {ses, direct_inbox}`, `belongs_to :sender_inbox`,
  `sender_identity` opcional, `set_direct_from_email` (força `from_email` = e-mail da caixa),
  validações (`sender_inbox_must_belong_to_account`, `sender_present_for_mode`), `sender_ready?`.
  Migration aditiva `20260615120000_add_direct_inbox_to_email_campaigns` (delivery_mode + sender_inbox_id).
- **`EmailCampaigns::DirectInbox::Limits`** — 21 domínios webmail; cap diário 100 (gmail/icloud),
  60 (outlook/hotmail/yahoo), 40 (uol/bol/terra); intervalo 60–120s; horário 9–18h; autopause
  (3 falhas seguidas OU 5% de falha).
- **`DirectInbox::Sender`** — mesma interface do `Ses::Sender`; Microsoft via Graph `/sendMail`
  (202), demais via SMTP (gmail XOAUTH2 / SMTP da caixa). Monta MIME com `Mail`.
- **`DirectInbox::RecipientSender`** — render (Liquid) + `Tracking::Injector` (pixel+clique) +
  List-Unsubscribe + envio. **At-most-once**: `claim` atômico pending→sent; falha de envio marca
  FAILED (nunca re-enfileira — duplicado dana reputação). **Entrega**: no aceite do provedor cria
  evento `delivered` + `mark_delivered!` (webmail não tem webhook; aceite = sinal de entrega).
- **`DirectInbox::DeliveryEngine` + `TickJob`** — 1 e-mail por tick; reagenda com intervalo
  aleatório; só em horário comercial (fuso BR); respeita teto diário rolling-24h por caixa;
  autopause por guardrail/falhas; `finalize!` ao fim.
- **FE** (`EmailCampaignDialog.vue`) — detecta caixas webmail conectadas, mostra no dropdown de
  remetente, **aviso vermelho** ("ciente que este provedor não é para disparo em massa e pode
  bloquear sua conta"), trava `from_email` na caixa.
- **Reports** — `delivered_count`/taxas funcionam no direto; timeline corrigido (email-13).

**Arquivos:** `app/services/email_campaigns/direct_inbox/{limits,sender,recipient_sender,delivery_engine}.rb`,
`app/jobs/email_campaigns/direct_inbox/tick_job.rb`, `app/models/email_campaign.rb`,
`app/controllers/.../email_campaigns/campaigns_controller.rb`,
`app/javascript/.../EmailCampaign/EmailCampaignDialog.vue`, `app/services/email_campaigns/reports/builder.rb`.

---

## Fase B — Endurecer envio direto para produção — 🔜 FOLLOW-UP (planejado, NÃO iniciado)
> Decidido com o PO em 2026-06-15: registrar como atualização e **puxar depois**. Escopo abaixo
> já é o plano técnico para quando retomarmos.

A Fase A é o MVP (envio + throttle + tracking). A Fase B fecha o que falta para uso real diário
por PMEs. Módulos independentes — dá para priorizar/cortar na hora de puxar:

### B1 — Validar o FLUXO REAL agendado E2E (hoje só o envio manual foi testado)
- **Problema:** o E2E da Fase A chamou `RecipientSender` direto (fora de horário). O caminho de
  produção (`send_now`/`scheduler` → `DeliveryJob` → `DirectInbox::TickJob` → `DeliveryEngine#tick`)
  com **multi-destinatário**, horário comercial, throttle 60–120s, teto diário e autopause **não
  foi exercitado ponta a ponta** em prod.
- **Entregar:** teste E2E real com ~5–10 destinatários reais (lista de teste própria), em horário
  comercial, observando: 1 envio por tick, reagendamento, respeito ao teto, `finalize!` ao fim,
  e disparo do autopause num cenário de falha forçada. Métricas/abertura/clique no dashboard.
- **Risco/atenção:** o `TickJob` reagenda via Sidekiq `set(wait:)`. Validar que o backlog de
  reagendamentos sobrevive a restart do Sidekiq (idempotência do tick + `claim`).

### B2 — Warm-up gradual por caixa (contas novas têm limite muito menor)
- **Problema:** cap diário é fixo por domínio. Conta nova de Gmail/Hotmail é bloqueada bem antes
  de 100/dia. Disparar 100 no 1º dia = risco alto de suspensão.
- **Entregar:** estado de warm-up por `sender_inbox` (ex.: `first_direct_send_at`, contador
  acumulado) + rampa (ex.: dia 1 = 10, dia 2 = 20, … até o teto do domínio). `Limits.daily_cap`
  passa a considerar a idade/uso da caixa. Migration aditiva (tabela `direct_inbox_warmups` ou
  colunas na inbox/channel). UI mostra "limite de hoje: X (em aquecimento)".
- **Decisão p/ PO:** curva de rampa (conservadora vs. agressiva) e se o cliente pode pular o
  warm-up assumindo o risco.

### B3 — Detecção de bounce/NDR via IMAP (hoje só falha SÍNCRONA de envio é detectada)
- **Problema:** Graph/SMTP retornam 202/OK mesmo para endereço que depois "bounce". Sem webhook
  (≠ SES), e-mails que voltam (NDR/Mailer-Daemon) não viram `bounced` → autopause não enxerga,
  taxa de bounce fica 0, e a lista suja continua sendo disparada.
- **Entregar:** job que lê a caixa via IMAP (já temos credencial/refresh OAuth), identifica NDRs
  (remetente mailer-daemon/postmaster, status 5.x.x), casa com o destinatário/campanha (via
  `message_id` ou cabeçalhos), cria evento `bounce` + `mark_bounced!` + suppression. Alimenta
  autopause e a taxa de bounce real.
- **Risco/atenção:** parsing de NDR é heurístico (formatos variam por provedor). Começar com
  Microsoft/Gmail (maioria), padrão RFC 3464 (`message/delivery-status`).

### B4 — Processar descadastro one-click (List-Unsubscribe já é INJETADO, falta processar)
- **Problema:** a Fase A injeta `List-Unsubscribe`/`List-Unsubscribe-Post`, mas é preciso garantir
  que o endpoint de descadastro (RFC 8058 one-click POST) processa o token e suprime o contato
  **também para envio direto** (não só SES), refletindo no dashboard e bloqueando reenvios.
- **Entregar:** validar/estender `Unsubscribe::Token` + endpoint para cobrir campanhas
  `direct_inbox`; suppression por conta aplicada no `RecipientSender` (já consulta
  `EmailSuppression.suppressed_set_for`). Teste E2E do clique de descadastro.

### B5 — UX de produção (gate de ciência, progresso/ETA, pausar/retomar)
- **Gate de ciência:** checkbox obrigatório "Estou ciente dos riscos" antes de habilitar o envio
  direto (hoje só há o aviso vermelho informativo). Persistir o aceite.
- **Progresso + ETA:** dado o throttle (60–120s) e o horário comercial, mostrar barra de progresso
  e estimativa de término ("~3h, terminando amanhã 11h"). Usar contadores + janela.
- **Pausar/Retomar:** botões na UI ligados a `campaign.pause!/resume!` (modelo já suporta), com
  feedback do motivo quando autopause disparar.

### B6 — (Opcional) Throttle adaptativo
- Ajustar o intervalo dinamicamente conforme falhas observadas (recuar quando começar a falhar,
  acelerar levemente quando estável). Só depois do B3 (precisa do sinal de bounce real).

**Ordem sugerida ao puxar:** B1 (provar o motor real) → B5 (gate+progresso, baixo risco, alto
valor de UX) → B3 (bounce, o maior risco de reputação) → B2 (warm-up) → B4 (descadastro) → B6.

**Gates de deploy (iguais à Fase A):** backup BD antes de migration; `eager_load!` em serviço
Swarm temporário; teste isolado efêmero (pg+redis descartáveis); deploy `--update-order start-first`;
deploy só com OK explícito do PO.
