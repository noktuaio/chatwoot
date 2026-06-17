# Campanha de E-mail — Discovery & Decisões (fase exploratória)

> Documento-âncora da fase de pesquisa (não é PRD ainda). Fork Chatwoot v4.14.1 EE. Objetivo: campanha de e-mail dentro da aba **Campanhas** — importar lista (nome+e-mail), disparar, e acompanhar (estilo RD Station). Pesquisa cruzada: código real do fork + docs externas (ESP, tracking, deliverability, LGPD).

## 1. Achados de código (o que existe hoje no fork)

### E-mail (canal de atendimento)
- `Channel::Email` (um modelo, 3 formas: Microsoft OAuth, Google OAuth, IMAP/SMTP manual). Recebe por IMAP (cron 1 min, `Inboxes::FetchImapEmailInboxesJob`), envia por SMTP via `ConversationReplyMailer` (`Email::SendOnEmailService`).
- **Microsoft quebra** porque o Chatwoot usa **IMAP/SMTP legados + XOAUTH2** (sem Microsoft Graph) — protocolos que a Microsoft desliga (rejeição total **abr/2026**, issue chatwoot#13021). Token inicial "chutado" em 1h; auto-desabilita após 10 erros.
- **Envio atual NÃO serve para disparo em massa:** é amarrado a uma conversa (`ConversationReplyMailer` precisa de conversa+contato+inbox) e usa a caixa do próprio usuário (O365/Gmail), com limite diário baixo. → campanha precisa de **ESP dedicado**, não da caixa conectada.

### Campanhas (motor atual)
- `Campaign` só aceita **Website live-chat, SMS, WhatsApp** — **rejeita e-mail** (`campaign.rb:84`, `case inbox.inbox_type` sem `Email`). Audiência = contatos com etiqueta. Cron `*/5` (`TriggerScheduledItemsJob`).
- **`WhatsappApiCampaign` + `WhatsappApiCampaignRecipient`** = motor de disparo moderno do fork (tabela de destinatários por campanha, status enviado/falhou, contadores, scheduler, pause/resume). **É o PADRÃO a copiar para `EmailCampaign`** (não estender o `Campaign` nativo).

### Importação
- `DataImport` (nativo) importa CSV → cria Contatos (dedup por identifier/email/phone; índice único de e-mail por conta).
- **`campaign_imports/*`** (do fork, gate `CAMPAIGN_IMPORT_ENABLED`): pipeline CSV/XLSX completo (Parser/Validator/Importer/HeaderMapper/PhoneNormalizer + telas) — **hoje só telefone**, cria Contatos com etiqueta de lote. **É o mecanismo a estender para e-mail** (adicionar alias de coluna `email` + ramo que grava em lista de destinatários em vez de Contatos).

## 2. Pesquisa externa (resumo)

- **KPIs estilo RD:** Enviados · Entregues · Taxa de abertura · Taxa de cliques · Descadastros · Bounces (soft/hard) · Spam — taxas calculadas sobre **entregues** + lista "quem abriu/clicou".
- **Tracking:** abertura = pixel 1x1 (**não confiável**: Apple MPP infla ~49% das aberturas); clique = reescrita de link (**confiável**); entregue/bounce/spam = **webhook do ESP**.
- **ESP é quem entrega o tracking + escala.** SendGrid **encerrou plano grátis (mai/2025)**. **Brevo** = grátis 300/dia permanente + self-upgrade (melhor p/ "grátis e cresce sozinho"). **SES** = ~US$0,10/1.000 (mais barato em volume, exige conta AWS + sair do sandbox). **Resend** = grátis ~3k/mês.
- **Onboarding 100% automático é impossível** (3 portas humanas): criar conta no ESP (anti-fraude), verificar remetente (clique no e-mail), **DNS SPF/DKIM/DMARC** (só o dono do domínio). Script NOSSO automatiza: identidade, **gerar DNS pra colar**, validar, webhook, envio.
- **Deliverability obrigatória:** Gmail (fev/2024) e Outlook (mai/2025) **rejeitam** volume sem SPF+DKIM+DMARC + descadastro 1 clique + spam <0,3%. Single-sender sem DNS = vai pro lixo.
- **LGPD:** marketing exige consentimento próprio comprovável; lista fria/comprada é inviável; descadastro ≤2 dias úteis + log de consentimento.

## 3. Decisões travadas (PO)

1. **Tipo de lista:** clientes **com opt-in** (LGPD ok). Precisa de consentimento/descadastro/suppression.
2. **Envio = MODELO "NÓS HOSPEDAMOS" (SES):** UMA conta **Amazon SES nossa (Autonomia)**, multi-tenant — **o cliente NÃO se cadastra em ESP nenhum**. Custo = **centavos pagos por nós** (~US$0,10/1.000, sem mensalidade), embutido no preço do produto. **Reputação é nossa** → precisa de guardrails anti-spam (suppression + monitorar bounce/complaint por tenant; senão um cliente ruim derruba a conta SES de todos). Sair do **sandbox do SES** é tarefa nossa (aprovação única AWS). *(Rastreio NÃO depende do ESP — é nosso, ver decisão 3.)*
   - **Domínio de envio = do CLIENTE** (marca dele, ex.: `contato@empresadocliente.com.br`). Cada cliente vira uma **identidade verificada no nosso SES** via **DNS (DKIM/SPF/DMARC)** que ele adiciona **uma vez** — nós **geramos os registros prontos + fazemos o polling do check verde**. É o único passo do cliente.
   - **Carteiro grátis p/ pré-lançamento/baixo volume:** Brevo free 300/dia pode servir de relay inicial, mas o modelo de produto é SES.
3. **Relatório:** **completo estilo RD** (enviados/entregues/abertos/clicados/descadastro/bounce + quem abriu). Abertura marcada como **aproximada** (MPP).
4. **Respostas:** replies **viram conversa** — Reply-To aponta para uma **caixa já conectada** no Chatwoot; o IMAP existente transforma em conversa.
5. **Importação:** **lista transitória** (estratégia b) — reusa o mecanismo `campaign_imports`, **sem poluir Contatos**; opcional futuro "salvar como contatos".
6. **Motor:** **novo `EmailCampaign`** no padrão `WhatsappApiCampaign` (não estender `Campaign` nativo); nova **sub-aba "E-mail"** em Campanhas.
7. **Microsoft (Graph):** **PR SEPARADA, depois da campanha** (prazo abr/2026; não bloqueia a campanha, que usa ESP).

## 4. Em aberto para a PRD (inputs do PO)
- **Volumetria** esperada (e-mails/mês) → fecha ESP padrão (Brevo vs SES) e se vale um **adaptador multi-ESP** ou começar com 1.
- **Domínio de envio** (ex.: `marketing@empresa.com`) → onde vão SPF/DKIM/DMARC.
- **Caixa de retorno** (qual inbox conectada recebe as respostas → conversa).
- Profundidade de tracking self-host vs ESP-hosted (recomendado ESP-hosted no MVP).

## 5. Esboço de arquitetura (alto nível, sem código) — MODELO B (SES multi-tenant, domínio do cliente)
- **Envio:** uma conta **SES nossa**; cada cliente = **identidade de domínio verificada** (DKIM) + **configuration set** p/ publicar eventos. Construir o motor **no fork** (não rodar Postal/listmonk separado). Carteiro plugável (adaptador), começando por SES.
- **Onboarding do cliente:** informar domínio de envio → app **gera SPF/DKIM/DMARC prontos** (do SES) → cliente cola no registrador → app faz **polling até verificar (✓ verde)** → pode disparar. Único passo do cliente.
- **Rastreio NOSSO (grátis):** pixel de abertura (endpoint próprio) + reescrita de link (redirect próprio) + ingestão de eventos do SES via **SNS→webhook** (delivered/bounce/complaint). Abertura marcada como aproximada (Apple MPP).
- **Modelos:** `EmailCampaign`, `EmailCampaignRecipient` (nome/e-mail/status/message_id SES), `EmailEvent` (entregue/abriu/clicou/bounce/complaint/descadastro), `Suppression` (descadastro/hard-bounce, por conta), config SES/identidade por conta.
- **Guardrails anti-spam (obrigatório no modelo "nós hospedamos"):** suppression automática em hard-bounce/complaint; monitorar taxa de bounce/complaint por tenant; cortar tenant que estoura limites antes de a AWS punir a conta toda.
- **Jobs:** importação (estende `campaign_imports` p/ e-mail), `EmailCampaigns::DeliveryJob` (lotes/throttle respeitando o rate do SES), `ScheduleDueCampaignsJob` (cron, espelha WhatsApp API), ingestão SNS/webhook, polling de verificação de domínio.
- **Endpoints:** webhook SNS do SES (assina/valida, grava `EmailEvent` por message_id), pixel de abertura, redirect de clique, descadastro público (token + header List-Unsubscribe 1 clique).
- **UI:** sub-aba E-mail em `campaigns.routes.js` (modelo da página WhatsApp API) + upload de lista + setup de domínio (DNS pronto + check) + página de relatório RD.
- **Respostas → conversa:** Reply-To = caixa conectada; IMAP existente cria a conversa.
- **Reuso:** pipeline `campaign_imports`, padrão `WhatsappApiCampaign`, Liquid de template, `Channel::Email` (Reply-To/identidade).
