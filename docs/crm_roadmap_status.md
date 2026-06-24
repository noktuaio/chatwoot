# CRM Kanban Pro — Status do Roadmap & Próximos Passos

> Documento-âncora pós-compactação. Resume o que já foi entregue e o que falta, para iniciar a próxima PR sem contexto prévio. Fork Chatwoot v4.14.1 EE em `/root/docker-stacks/build/chatwoot-campaign-v4.14.1`, deploy Docker Swarm single-node, host `https://chat.autonomia.site`. Conta de teste: **6** (Seguro Viagem, pipeline 9, inbox 113, AgentBot "Agente Gabriela"). Conta 85 (Sena Negócios) também tem CRM.

## Imagem em produção
- **Atual:** `chatwoot-campaign-import:v4.14.1-20260611-ec3` (= conn24, web+Sidekiq, deploy 2026-06-12) — **Campanha de E-mail Onda 3** (rastreio próprio pixel+clique + ingestão SES via SNS + auto-suppression + relatório RD em CRM "Gestão campanhas" + retry de falhas). SNS fiado em prod (tópico + subscription CONFIRMED + event-destination) e **E2E real validado** (envio → entrega via SNS → relatório). Flag ON. 3 migrations aditivas. Smoke 21/21 + review SHIP. Rollback conn24→conn23. **Anterior:** ec2/conn23 = **Onda 2** (importação + motor): modelos EmailCampaign/Recipient/Suppression + importação transitória (sem poluir Contatos) + DeliveryEngine/jobs (Liquid + List-Unsubscribe + claim atômico/sem duplo-envio, via SES gem-free da Onda 1) + API + abas "Campanhas de e-mail"/"Domínios de e-mail". Flag `EMAIL_CAMPAIGN_ENABLED=true` (LIGADA em prod). 3 migrations aditivas. Smoke real de envio + review SHIP. Limitação conhecida: falha transitória de envio não tem retry automático (próximo follow-up). Rollback conn23→conn22. **Anterior:** ec1/conn22 = **Onda 1** (fundação de envio SES): modelo EmailSenderIdentity + camada SES gem-free (aws-sigv4) + onboarding de domínio (DKIM/SPF/DMARC + verificação) + API + aba "Email domains" em Campanhas. Gate `EMAIL_CAMPAIGN_ENABLED` **OFF** (dormente, zero regressão). Migration aditiva aplicada. Smoke real no SES + review independente SHIP. PRD: `docs/email_campaign_v1_prd.md`. Rollback ec1→conn21 (sem rollback de banco). Linha anterior:
- **Anterior:** `chatwoot-campaign-import:v4.14.1-20260611-conn21` (web + Sidekiq, 1/1, deploy 2026-06-11) — conn21 = **fix do follow-up automático**: o "radar" passou a ser derivado do 1º intervalo (nunca fixo, conserta cadências curtas 1h/2h/3h); campo confuso "Disparar após parar" removido; "1º toque" sempre visível (fim do 20h fantasma); badge do card com ícone de tipo (🤖 IA / 🔔 manual); texto explicando a janela de horário; caixas alinhadas. conn20 = **fix de alinhamento** do campo número/unidade no diálogo SLA (`!m-0`). conn18 = **fix UX do diálogo de política** (linhas compactas de tempo + **toggles por métrica**: 1ª resposta ON, próxima resposta ON, resolução OFF por default; ≥1 métrica obrigatória; off = null, motor ignora — só frontend). conn17 = **SLA Inteligente 5 ondas** (motor de horário justo multi-bloco + horário por agente, exclusão de grupos, IA pausa saudável, SLA na aba CRM + auto-aplicar, badge nos cards) com **E2E REAL em prod validado** (IA suprimiu encerramento conf 0,98 / contou espera conf 0,99; motor pausou relógio; auto-apply + skip de grupo); 3 migrations aditivas aplicadas. conn16 = Follow-up IA v2 + fix schema composer.
- **Rollback chain:** `conn21 → conn20 → conn18 → conn17 → conn16 → conn15 → conn14 → conn13 → conn12 → conn9 → conn7 → conn6 → conn5 → conn234 → conn1a → crm14f → crm13.3` (conn20/conn18→conn17 e conn17→conn16 sem rollback de banco).
- **Flags:** `CRM_KANBAN_ENABLED=true`, `CRM_AI_ENABLED=true`, `CRM_AI_MEDIA_ENABLED` default(true).
- **Como buildar/deployar + gates:** ver memória `chatwoot-crm-deploy-workflow` (vite → docker → **gate eager_load** se mexeu `.rb` → green-check → deploy start-first → **teste visual real em pt_BR**). Deploy SEMPRE com OK explícito do usuário.

## Roadmap original (PR10–PR15) — status
| PR | Escopo | Status |
|----|--------|--------|
| PR10 | Follow-ups / Lista / Calendário | ✅ |
| PR11 | Mensagens agendadas / envio WhatsApp | ✅ |
| PR12 | Automações de etapa / sequências | ✅ |
| PR13 | IA do CRM (+13.1 multimodal áudio/imagem) | ✅ |
| **PR14** | (multi-frente) permissões, hardening, **UI card/timeline/resumo IA/chip**, **filtros**, **Dashboard de relatórios**, **fechar negócio + valor por IA**, **handoff IA→humano**, **Meta de vendas + valor perdido + win-rate por valor** | ✅ |
| **PR Conexões** (= o "PR14 n8n/Webhooks/Tokens" original que foi ultrapassado) | webhooks de saída (eventos crm.*, PII default-deny, retry), tokens escopados por-conta + idempotência + rate-limit, card n8n (assistente), docs n8n | ✅ |
| **Pós-feedback** | 8 correções de UX/bug + master-save + label "Desconectar" | ✅ |
| **PR15** | Pro / Métricas / **Supervisor** / Relatórios / **Performance** / billing | ⬜ **PRÓXIMA** — Relatórios/Métricas JÁ entregues no Dashboard; resta **Supervisor (monitoramento ao vivo de time/agente), Performance e billing/licenciamento** |

## Próxima PR candidata: PR15 — Supervisor & Performance
Sugestão de escopo (a confirmar com o usuário ao iniciar):
- **Supervisor:** visão ao vivo de carga/atividade por agente e por funil (quem está atendendo o quê, SLAs, gargalos em tempo real). Reusar os builders `Crm::Reports::*` + realtime.
- **Performance:** rankings por responsável vs meta (a Meta hoje é por funil; falta **meta por agente/quota individual**).
- **Billing/licenciamento:** se aplicável ao produto.

## Lista & Calendário v2 ("versão final") — ✅ DEPLOYADO EM PRODUÇÃO (conn7)
- PRD: `docs/crm_list_calendar_v2_prd.md`. Implementado **FULL** (sem MVP-first) via orquestração (2 workflows, 26+5 agentes, reviews por fase + review final GO). Detalhe em progress.md **Phase 51**.
- **Lista** (`@tanstack/vue-table` v8): colunas config + sort server-side + group-by Σ valor + edição inline + bulk actions (`POST /crm/cards/bulk`) + Saved Views (tabela `crm_saved_views`) + Load more + a11y grid + responsivo.
- **Calendário** (hand-build Vue+Tailwind+date-fns, sem dep nova): Mês/Semana/Dia/Agenda, **pt-BR domingo-first**, overlays por tipo, drag-to-reschedule, quick-add, popover de detalhe.
- **Gates verdes:** vite build, eslint 0, i18n 641/641, **eager_load + migration** (Swarm temp), **teste visual Playwright** (List+Calendar renderizam, 0 erro JS). Backup: `backups/crm_list_calendar_v2_prebuild_20260610T123108Z/`.
- **Produção: `v4.14.1-20260610-conn7`** (deployado+verificado 2026-06-10). Rollback: conn7→conn6→conn5→conn234→conn1a→crm14f→crm13.3.

## Follow-up automático com IA "de onde parou" (por funil) — ✅ DEPLOYADO (conn13, dormente off-by-default; E2E real pendente)
- **PRD escrito:** `docs/crm_ai_followup_prd.md` (pesquisa cadência + composição IA + regras WhatsApp 2024–26, cruzada com mapa do código). IA lê onde a conversa parou e monta follow-up natural; on/off + nº de toques + espaçamento por funil; envio WhatsApp-aware (sessão <24h / template marketing fora). **Fundação já existe** (MessageSender/MessagingWindow/DueProcessor/auto_send_message + ResponsesClient/ContextBuilder + SettingsUpdater/CrmAiSettingsPanel). Falta: `Crm::Ai::FollowUpComposer`, maestro de cadência, config/UX, camada de conformidade WhatsApp (opt-in/cap/STOP). **7 decisões FECHADAS pelo PO** (template-fora-da-janela SIM; opt-in ASSUMIDO; off-por-padrão+auto-envio; 1º toque dentro de 24h; 3 toques 1d/3d/7d; só conversa primária; só WhatsApp oficial+não-oficial). MVP sem migration (reusa Crm::FollowUp + metadata).

## SLA Inteligente — ✅ DEPLOYADO EM PRODUÇÃO (conn17, 2026-06-11, E2E real verde)
- **5 ondas one-shot** via orquestração dinâmica (21 agentes: arquiteto + 9 impl paralelos + integrador + 7 reviewers + fix-pass + GO) + **review Codex = SHIP** (1 major N+1 corrigido). 53 arquivos, 3 migrations aditivas.
- **Gates verdes:** ruby -c, eslint 0 erros, paridade i18n (crm 774/774, settings 587/587), vite build, eager_load+db:migrate em Swarm temp, **smoke 24/24 PASS** (multi-bloco/fuso/precedência/grupo/auto-apply/fail-open), **visual Playwright** (página crm/sla + CRUD E2E + editor multi-bloco + toggle AddAgent + Settings sem SLA + relatório SLA intacto + badge 🔥 no card Kanban).
- **Pendente na janela de deploy:** `db:migrate` em prod (obrigatório), teste visual prod pt_BR, chamada REAL de IA (AiBreachGuard) — antes de confiar nos toggles de IA. Rollout/rollback: `docs/crm_sla_v2_rollout_rollback.md`. Imagem: `v4.14.1-20260611-conn17`.

## PR candidata (ESPECIFICADA): SLA Inteligente (SLA "justo" com IA + horário real + dentro do CRM)
- **PRD escrito:** `docs/crm_sla_v2_prd.md`. Reformula o SLA (EE) em 5 ondas: (1) motor de horário justo — multi-bloco/dia estilo cal.com + fuso + horário POR AGENTE que sobrescreve a caixa (precedência agente>caixa>24/7) + corrige o bug do `only_during_business_hours` (hoje conta 24/7); (2) excluir grupos (detecção `@g.us` comprovada WAHA/Evolution + denylist broadcast/newsletter); (3) IA "pausa saudável" não conta quebra (reusa ContextBuilder/ResponsesClient, só no momento da quebra + cache); (4) mover SLA de Configurações p/ aba CRM (abaixo do Dashboard) + auto-aplicar v1 (gatilho conversa-criada, sem ir em Automações); (5) badge de quebra de SLA nos cards Kanban/Lista (reusa SLACardLabel). Aditivo, EE overlay, sem regressão. **6 decisões FECHADAS** (agente atual no cálculo; sem agente→caixa; confiança IA 0,6; auto-aplicar v1 amarra caixa **E** funil; calendário 1 por usuário; remover SLA de Configurações de vez). **PRÓXIMO A CONSTRUIR = Onda 1 (motor de horário justo + horário por agente).**

## Backlog adiado (não-bloqueante, capturado dos planos)
- **E-mail · Fase B — Endurecer envio direto por webmail para produção** (follow-up, puxar depois; decidido com PO 2026-06-15): validar fluxo real agendado E2E multi-destinatário (B1), warm-up gradual por caixa (B2), detecção de bounce/NDR via IMAP (B3), processar descadastro one-click (B4), UX de produção — gate de ciência + progresso/ETA + pausar/retomar (B5), throttle adaptativo opcional (B6). **Escopo técnico completo em `docs/email_direct_webmail_status.md`.** Fase A (MVP) já em produção (email-13).
- **n8n:** teste E2E real com URL pública/privada do n8n do usuário (o webhook.site foi bloqueado por exfiltração); logo n8n real (hoje é placeholder de rede-de-nós, aceitável); **eventos fase-2** (`crm.card.value_changed`, `crm.ai.*`, `crm.follow_up.*`); UI de **replay de entregas** de webhook; nó community do n8n.
- **Chave própria de IA do CRM** (`CRM_AI_OPEN_AI_API_KEY`, desacoplar do Captain) — **decisão do usuário: NÃO agora**, manter fallback `CAPTAIN_OPEN_AI_API_KEY` (hoje vazio; cada conta usa hook próprio).
- **Saved Views** (filtros salvos por usuário) — adiado na PR14.7.
- **Origem/Canal:** popular `crm_cards.source` na criação + filtro de origem + bloco "por canal" no Dashboard.
- **Chip de estágio** na lista de conversas: updates em tempo real (hoje fetch-on-open).
- **Follow-up template nativo:** o picker manda `template_name/language` mas **não coleta variáveis de corpo** (`processed_params={}`) — templates com variáveis obrigatórias renderizam vazias; fechar isso se necessário.
- **"Perdidos por etapa"** (drop-off) — gráfico separado no Dashboard (não poluir o funil de abertos).
- Unificar o botão "Salvar IA" (hoje coexiste com o master "Salvar funil"); opcional remover.

## Decisões de produto travadas (não reverter sem nova decisão)
- **i18n:** a UI CRM-custom respeita o idioma da instância → **pt_BR + en com paridade 1:1 obrigatória** (override da regra "só en" do CLAUDE.md, porque é fork single-tenant pt_BR). Gate: `en↔pt_BR` parity em crm.json/integrations.json/integrationApps.json.
- **Permissões:** "se o admin deu, o cara tem" — admin + agente sem custom_role têm acesso CRM total; custom-role gateado pelas keys `crm_*`.
- **Token n8n:** por-conta, escopado, revogável (mantido).
- **Card n8n:** assistente guiado sobre os Webhooks nativos (mantido).
- **Win/Lost:** ação explícita no card, independente de etapa; valor por IA autopreenche `value_cents` (trava no takeover humano `value_source='human'`); funil só com abertos.
- **Meta:** mensal por funil (`pipeline.metadata.goals`); Dashboard mostra atingimento + pacing.
- **Handoff:** = atribuição + `bot_handoff!`; guard de loop; direto/round-robin; atribui mesmo offline.

## Gotchas recorrentes (memória curta)
- `display_id` ≠ id global (frontend usa display_id) — [[chatwoot-frontend-display-id]].
- Zeitwerk + eager_load: EE sob `enterprise/app/...` namespaceado; **rodar gate eager_load antes de todo deploy com `.rb`** (um deploy caiu por isso).
- `ApplicationRecord` capa strings em 255 sem validação explícita — [[chatwoot-applicationrecord-255-cap]].
- `Message` tem `default_scope order(:asc)`; usar `.reorder` — [[chatwoot-message-default-scope-reorder]].
- Transcrição: o CRM grava em `attachment.meta.transcribed_text` (mesmo campo do display nativo) → aparece na conversa de brinde, via chave do hook Kanban.

## Docs de referência
- `docs/crm_kanban_pr14_plan.md` (plano 8 frentes), `docs/crm_kanban_pr14_waveC_handoff.md`, `docs/crm_kanban_connections_plan.md` (n8n/webhooks/tokens, decisões travadas), `docs/crm_issues_action_plan.md` (8 correções), `docs/crm_kanban_pr13_1_plan.md`. Log completo: `/root/docker-stacks/progress.md` (Phases 26–49).
