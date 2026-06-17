# PRD — Campanha de E-mail (v1) · aba Campanhas

> **Status:** proposta para aprovação (não iniciada). Fork Chatwoot v4.14.1 EE em `/root/docker-stacks/build/chatwoot-campaign-v4.14.1`. Produção atual: `conn21`. Discovery que embasa: [[email_campaign_discovery]] (`docs/email_campaign_discovery.md`).
> **Conta de teste:** 6 (Seguro Viagem). Volumetria-alvo v1: **~2.000 e-mails/dia** (somando clientes).

---

## 0. Objetivo e princípios

**Objetivo.** Permitir, dentro da aba **Campanhas**, **importar uma lista (nome + e-mail)**, **disparar uma campanha de e-mail em massa** e **acompanhar os resultados** (estilo RD Station: enviados, entregues, aberturas, cliques, descadastros, bounces) — com o mínimo de fricção para o cliente final.

**Regras SEMPRE (não negociáveis):**
- **Zero regressão.** Tudo aditivo; não tocar no motor `Campaign` nativo (que rejeita e-mail) nem no canal de e-mail de atendimento. Nova feature isolada.
- **Reviews por fase + fix-pass** (backend, segurança/Pundit, regressão zero, deliverability/anti-spam, FE+i18n) + **review final GO/NO-GO** + **review Codex** quando disponível.
- **Testes reais:** `ruby -c`, eslint, **paridade i18n en↔pt_BR**, `vite build`, **`eager_load` em serviço Swarm temporário**, teste visual real (SSO+Playwright) e **smoke do disparo** (envio real de teste pelo SES sandbox/identidade de teste + ingestão de evento).
- **Backup antes do build**, **deploy só com OK explícito**, **rollback pronto** (próxima tag `connN`).
- **Identidade Chatwoot:** Vue 3 `<script setup>`, Tailwind `n-*`, components-next, i-lucide, i18n pt_BR+en 1:1.
- **LGPD é lei (postura prática, SEM double-opt-in):** **não** pedimos confirmação a cada destinatário (nada de e-mail de "confirme sua inscrição"). O "opt-in" é uma **DECLARAÇÃO do cliente** (quem sobe a lista) num **checkbox no upload** — "confirmo que tenho consentimento desta lista" — que vira **log de responsabilidade**. O destinatário só recebe a campanha + o **link de descadastro (1 clique)**; nenhuma ação é pedida a ele. Suppression honrada.

---

## 1. Decisões travadas (PO) — base do desenho

1. **Modelo de envio = "NÓS HOSPEDAMOS" (Amazon SES).** UMA conta SES da Autonomia, multi-tenant. **O cliente NÃO se cadastra em ESP.** Custo = centavos nossos (~US$0,10/1.000), embutido no preço. **Reputação é nossa** → guardrails anti-spam obrigatórios (§6). Sair do sandbox do SES é tarefa nossa (1x).
2. **Domínio de envio = do CLIENTE** (marca dele). Cada cliente = **identidade de domínio verificada no nosso SES** via **DNS (DKIM + SPF + DMARC)** que ele adiciona **uma vez** — nós geramos os registros prontos e fazemos o polling do ✓ verde. É o **único passo** do cliente.
3. **Rastreio = PRÓPRIO ("top do top", padrão dos melhores OSS — listmonk/Postal):** abertura por **pixel próprio** + clique por **reescrita de link** passando pelo **nosso domínio de rastreio** (ex.: `track.autonomia.site`) — dado 100% nosso, controlável, com marca própria (melhor que o domínio default do SES). O **SES (via SNS→webhook)** entra só para **entregue/bounce/complaint** (eventos que só o provedor de envio sabe). Relatório completo estilo RD. **Abertura marcada como aproximada** (Apple MPP infla).
4. **Lista = transitória.** Reaproveita o pipeline `campaign_imports/*` (estendido p/ e-mail); grava numa tabela de destinatários por campanha — **NÃO** cria Contatos (base do CRM limpa). Opcional futuro "salvar como contatos".
5. **Motor construído no fork:** novo `EmailCampaign` no padrão `WhatsappApiCampaign` (NÃO estender `Campaign` nativo). Não rodar Postal/listmonk como serviço externo — **adotamos a ABORDAGEM** deles (pixel + reescrita de link), implementada no fork.
   - **Disparo/execução = aba CAMPANHAS** (sub-aba E-mail): configurar remetente/domínio (1x), criar, importar lista e disparar.
   - **Gestão + relatório = aba CRM**, novo item **"Gestão campanhas"** (i18n EN: **"Campaign Management"**), ao lado de Kanban · Dashboard · SLA: lista campanhas, relatórios estilo RD e **filtro por campanha**.
   - **IMPORTANTE — não confundir com a caixa de entrada:** o **remetente de campanha (SES + DNS) é coisa SEPARADA** da "criar caixa de entrada" (IMAP/SMTP de atendimento). A criação de caixa de entrada **não muda** e **não ganha campo de DNS**. O setup de domínio/DNS é uma **tela própria na aba Campanhas**, feita 1x por domínio. A caixa de entrada existente é reaproveitada apenas como **Reply-To** (resposta vira conversa), sem DNS novo.
6. **Respostas → conversa:** Reply-To aponta para uma **caixa de e-mail já conectada** no Chatwoot; o IMAP existente transforma a resposta em conversa.
7. **Microsoft (Graph):** PR SEPARADA, depois (não bloqueia; envio é via SES).
8. **Volumetria v1:** ~2k/dia → pool SES compartilhado, **sem IP dedicado**, aquecimento leve.

---

## 2. Escopo

**Dentro do v1:**
- Setup de domínio de envio do cliente (gerar DNS, verificar via SES).
- Importar lista CSV/XLSX (nome+e-mail) → lista transitória por campanha.
- Compor campanha (assunto, corpo HTML com variáveis Liquid `{{ nome }}`, remetente, reply-to).
- Agendar/disparar em massa via SES (lotes + throttle).
- Rastreio + relatório estilo RD (enviados/entregues/abertos/clicados/descadastro/bounce/spam + lista de quem abriu/clicou).
- Descadastro de 1 clique + suppression list.
- Guardrails anti-spam.

**Fora do v1 (futuro):** automação/sequências de e-mail, A/B test, editor drag-and-drop de template, IP dedicado, domínio de rastreio customizado (usa o default do SES no v1), "salvar lista como contatos", segmentação avançada, multi-ESP (adaptador deixado plugável, mas só SES implementado).

---

## 3. Arquitetura (Modelo B — SES multi-tenant)

```
Importar lista ─► Lista transitória ─► EmailCampaign ─► DeliveryJob ─► SES (domínio do cliente)
(CSV nome+email)   (não vira contato)   (compor/agendar)  (lotes/throttle)        │
                                                                                  ▼
Relatório RD ◄── EmailEvent ◄── nosso webhook ◄── SNS ◄── configuration set (entregue/abriu/clicou/bounce/spam)

Cliente responde ─► Reply-To (caixa conectada) ─► IMAP existente ─► Conversa no Chatwoot
```

- **Identidade por cliente:** verificar o **domínio** do cliente no nosso SES (Easy DKIM = 3 CNAMEs) + orientar SPF + DMARC. `From = marketing@dominiodocliente`; `Reply-To = caixa conectada`.
- **Eventos:** SES configuration set → SNS → nosso webhook **apenas para entregue/bounce/complaint**. **Abertura e clique são NOSSOS:** pixel 1x1 num endpoint próprio + reescrita de cada link para passar pelo **nosso domínio de rastreio** (redirect 302 que loga e segue). Domínio de rastreio com a nossa marca (não o `awstrack.me` do SES) — melhor entrega e dado direto no nosso banco.
- **Throttle:** `DeliveryJob` respeita o `max send rate` do SES; a 2k/dia sobra folga.

---

## 4. Modelo de dados (aditivo; migrations additivas)
- **`EmailSenderIdentity`** (por conta): `account_id`, `domain`, `from_email`, `reply_to_inbox_id`, `dkim_tokens`/registros, `status` (pending/verified/failed), `verified_at`. (Representa a identidade no nosso SES.)
- **`EmailCampaign`**: `account_id`, `sender_identity_id`, `name`, `subject`, `from_name`, `body_html`, `status` (draft/scheduled/sending/sent/paused/canceled), `scheduled_at`, counters (sent/delivered/opened/clicked/bounced/complained/unsubscribed), `ses_configuration_set`.
- **`EmailCampaignRecipient`**: `email_campaign_id`, `name`, `email`, `status` (pending/sent/delivered/opened/clicked/bounced/failed/suppressed), `ses_message_id`, `sent_at`, `last_error`. Índice único `(email_campaign_id, lower(email))`.
- **`EmailEvent`**: `recipient_id`, `type` (delivered/open/click/bounce/complaint/unsubscribe), `url` (clique), `occurred_at`, `payload` jsonb. Join por `ses_message_id`.
- **`EmailSuppression`** (por conta): `account_id`, `email`, `reason` (hard_bounce/complaint/unsubscribe), `created_at`. Índice único `(account_id, lower(email))`. Consultada no disparo.
- Sem mudança no `Campaign` nativo nem em `Contact`.

---

## 5. Fluxos

1. **Onboarding de domínio:** admin informa o domínio → app cria a identidade no SES, **mostra DKIM/SPF/DMARC prontos** → cliente adiciona no registrador → `DomainVerificationPollJob` confirma → ✓ verde, pronto p/ enviar. (Pode começar com **single-sender** verificado por e-mail p/ teste rápido, mas marketing exige domínio.)
2. **Importação:** estende `campaign_imports` (alias `email`/`e-mail` + validação de e-mail) → grava em `email_campaign_recipients` (modo "lista transitória", sem Contatos) → dedup por e-mail na campanha → pula suppressed.
3. **Compor/agendar:** assunto + corpo HTML (Liquid `{{ nome }}`), remetente (identidade verificada) + reply-to (caixa conectada) + agendamento.
4. **Disparo:** `ScheduleDueCampaignsJob` (cron) → `EmailCampaigns::DeliveryJob` em lotes: para cada destinatário não suprimido, envia via SES (configuration set), grava `ses_message_id` + status `sent`. Insere **header List-Unsubscribe (1 clique)** e link de descadastro no rodapé.
5. **Rastreio:** SES publica eventos → SNS → nosso webhook (valida assinatura) → grava `EmailEvent` + atualiza status do destinatário + counters da campanha (padrão `refresh_counters!` do WhatsApp API).
6. **Relatório RD:** em **CRM → "Gestão campanhas"** — KPIs (enviados/entregues/abertos/clicados/descadastro/bounce/spam, taxas sobre **entregues**) + lista de quem abriu/clicou, com **filtro por campanha**. Abertura rotulada "aproximada".
7. **Descadastro:** endpoint público (token) → grava em `EmailSuppression` (≤ imediato, bem dentro do limite LGPD) + honra List-Unsubscribe.
8. **Resposta → conversa:** Reply-To = caixa conectada; IMAP existente cria a conversa (sem mudança).

---

## 6. Guardrails anti-spam (OBRIGATÓRIO no modelo "nós hospedamos")
A reputação do SES é compartilhada por todos os clientes → um cliente ruim pode fazer a AWS punir/suspender a conta inteira. Logo:
- **Suppression automática** em hard-bounce e complaint (nunca reenviar).
- **Monitorar taxa de bounce/complaint por tenant**; alertar/pausar o cliente que se aproxima dos limites da AWS (bounce <5%, complaint <0,1%) **antes** de a AWS agir.
- **Só listas opt-in** (declaração no upload) + descadastro 1 clique sempre presente.
- **Rate/cap por conta** (ex.: teto diário por cliente) para um tenant não consumir a cota de todos.
- Painel interno de saúde de envio (bounce/complaint por conta).

---

## 7. LGPD / conformidade (SEM double-opt-in)
- **Sem confirmação ao destinatário.** O cliente que sobe a lista **declara** o consentimento num checkbox no upload (gravamos data/usuário/origem = log de responsabilidade). O destinatário não recebe pedido de opt-in — só a campanha.
- **Descadastro de 1 clique:** header **List-Unsubscribe (RFC 8058)** + link visível no rodapé; suppression respeitada (não reenvia). SPF+DKIM+DMARC no domínio do cliente (obrigatório Gmail/Outlook). Texto explicativo na UI.

---

## 8. Mapa de arquivos (reuso vs novo)
**Reuso:** `campaign_imports/*` (Parser/Validator/HeaderMapper — estender p/ e-mail), padrão `WhatsappApiCampaign`/`WhatsappApiCampaignRecipient` (motor/counters/scheduler), `Liquid::CampaignTemplateService`, `Channel::Email` (Reply-To/caixa conectada), `campaigns.routes.js` (nova sub-aba), cron `TriggerScheduledItemsJob`.
**Novo:** modelos do §4 + migrations; `EmailCampaigns::{DeliveryJob,ScheduleDueCampaignsJob,DomainVerificationPollJob}`; serviço SES (envio + criar identidade + configuration set); controller de webhook SNS; endpoints de descadastro + pixel/clique (se self-host) ; Pundit `EmailCampaignPolicy`; UI (sub-aba E-mail: lista de campanhas, criar, upload, setup de domínio, relatório); i18n.
**Config/ENV:** credenciais AWS SES (`AWS_SES_*`/IAM), SNS topic, `EMAIL_CAMPAIGN_ENABLED` (gate, off por padrão).

---

## 9. Faseamento (ondas)
- **Onda 1 — Fundação de envio:** conta SES + IAM + sandbox-exit (operacional) · `EmailSenderIdentity` + onboarding de domínio (gerar DNS + poll verify) · serviço de envio SES + configuration set.
- **Onda 2 — Importação + motor:** estender `campaign_imports` p/ e-mail → `EmailCampaignRecipient` (lista transitória) · `EmailCampaign` + `DeliveryJob` + `ScheduleDueCampaignsJob` + Liquid + List-Unsubscribe.
- **Onda 3 — Rastreio próprio + relatório:** pixel de abertura + redirect de clique no **domínio de rastreio próprio** + reescrita de links no envio (padrão listmonk/Postal) · webhook SNS (entregue/bounce/complaint) → `EmailEvent` + counters · página **"Gestão campanhas" em CRM** com filtro por campanha.
- **Onda 4 — Descadastro + guardrails:** suppression + endpoint público + monitor bounce/complaint por tenant + caps.
- **Onda 5 — UI/UX final + i18n + polish.**
Cada onda: orquestração (impl disjunto + review paralelo + fix-pass) → gates → teste real → **OK do PO** antes de deploy.

## 10. Processo (recap)
Backup → orquestração dinâmica → gates (`ruby -c`, eslint, i18n parity, vite, eager_load Swarm temp, **smoke de envio real + ingestão de evento**, teste visual) → review final + Codex → deploy `start-first` com OK + rollback. **Lição:** testar envio/tracking com **chamada real ao SES** (não só review).

## 11. Riscos
- **Reputação compartilhada** (mitigado: guardrails §6). **Sandbox/limites SES** (resolver antes do go-live). **Aquecimento** leve a 2k/dia. **Abertura inflada** (Apple MPP — rotular aproximada; liderar por entregues/cliques). **Custo** cresce com volume (centavos; revisar IP dedicado acima de dezenas de milhares/dia). **DNS do cliente** depende de ele colar os registros (UI guia + ✓ verde).

## 12. Em aberto (a confirmar na Onda 1)
- *(Resolvido: disparo/execução na aba **Campanhas**; gestão+relatório em **CRM → "Gestão campanhas"**.)*
- Qual **caixa conectada** será o Reply-To padrão (por conta).
- Conta AWS/SES + região (us-east-1 ou sa-east-1) + sandbox-exit.
- **Domínio de rastreio** próprio (ex.: `track.autonomia.site`): um só nosso (simples) vs subdomínio por cliente (mais marca, mais setup) — recomendo um nosso no v1.
- *(Resolvido: rastreio é PRÓPRIO — pixel + reescrita de link, não o do SES.)*

## 13. Referências (âncoras de código)
`app/models/whatsapp_api_campaign*.rb` (padrão a copiar), `app/services/campaign_imports/*` (importação a estender), `app/services/liquid/campaign_template_service.rb`, `app/models/channel/email.rb` (Reply-To), `app/javascript/dashboard/routes/dashboard/campaigns/campaigns.routes.js` (sub-aba), `config/schedule.yml` (cron). Discovery + decisões: `docs/email_campaign_discovery.md`.
