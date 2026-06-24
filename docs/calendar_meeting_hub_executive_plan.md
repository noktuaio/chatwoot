# Hub de Agendamento no CRM — Plano Executivo (para aprovação)

> Versão de negócio do plano técnico completo em `docs/calendar_meeting_hub_technical_plan.md` (v2, revisado por codex — READY).

## O que vamos construir
Transformar o CRM num **hub de agendamento dentro do atendimento**: o agente agenda uma reunião direto do card do cliente (ou pela aba Calendário), gera link de **Google Meet / Microsoft Teams**, envia o **convite de calendário nativo** para o cliente (e mais convidados), recebe **lembrete por push + e-mail** (reusando o que subimos hoje), e tudo aparece no **inbox + calendário do CRM**. Diferencial real frente ao Chatwoot puro.

## Como funciona para o usuário
1. Admin liga a **"agenda"** na caixa de e-mail do agente (toggle, 1 vez).
2. No card do cliente → botão **"Reunião"**: escolhe a caixa (pessoal/departamento), data/hora, convidados (o contato do negócio já vem preenchido; pode adicionar mais), gera Meet/Teams, define "lembrar X min antes".
3. O convite real (.ics) sai para todos os convidados; uma nota aparece no inbox/timeline do card; a reunião entra no calendário do CRM; e o lembrete dispara push+e-mail+popup na hora certa.

## Fases (do valor-com-baixo-risco ao pesado)

| Fase | Entrega | Valor | Esforço | Risco |
|---|---|---|---|---|
| **P1 — Agendar (MVP)** | Botão Reunião → cria evento (Graph/Google) + Meet/Teams + convite nativo p/ vários convidados + nota no inbox + aparece no calendário CRM + lembrete (push/e-mail) | **Alto** — é o coração do hub | Médio-grande | Médio |
| **P2 — Disponibilidade & gestão** | Free/busy (evita conflito) + reagendar/cancelar (propaga p/ Google/MS) + ver os eventos externos do agente no calendário do CRM | Médio-alto | Médio | Baixo |
| **P3 — Diferenciadores** | Página de **booking pública** por agente (estilo Calendly) + sincronização 2-vias + resultado da reunião no card + **no-show** + **IA** (sugere horário, redige convite, resume depois) | Alto (wow) | Grande | Alto |

Recomendo **aprovar e começar pela P1** (entrega o hub funcional), depois P2, depois P3.

## 3 pontos de atenção que afetam você (decididos no plano)
1. **Google = app próprio por cliente.** O escopo de calendário do Google é "sensível" → exige app/projeto Google do próprio cliente (mesmo modelo que já usamos no e-mail, que dribla a verificação CASA). O plano **bloqueia** o uso do app global para calendário e orienta o agente. *Gmail pessoal (não-Workspace) tem limitação — documentado.*
2. **Teams precisa de licença.** O link Teams via Microsoft (mesma API Graph do e-mail de vocês) exige a caixa ter licença Teams. Caixa **pessoal** do agente normalmente tem; **compartilhada** muitas vezes não → tratamos com aviso.
3. **Re-consentimento.** Caixas de e-mail já conectadas precisam reautorizar uma vez para ganhar a permissão de agenda (o plano preserva o token de e-mail existente — corrigimos um bug crítico onde o re-consent zeraria o e-mail).

## Por que é "barato" (reaproveita o que já existe)
- **OAuth de e-mail Google/MS** (por-conta, já feito) → só adiciona o escopo de calendário.
- **Microsoft** = a **mesma API Graph** do e-mail de vocês (zero cliente novo).
- **Calendário do CRM** já concatena eventos → reuniões entram nele.
- **Tipo "Reunião"** já é um placeholder pronto na UI.
- **Notificações cal13** (push+e-mail) que subimos hoje → lembrete da reunião sai de graça.

## Como entregamos (seus padrões)
Orquestração dinâmica + **harness isolado com teste real** (sem spammar calendários reais — APIs stubadas + e-mail de teste), eager_load, eslint 0, i18n pt/en, **review duplo (codex)**, **feature-flag** por conta (rollout controlado) e **deploy só com seu OK** a cada fase. Migrações **aditivas e reversíveis** (cuidado com o BD de prod).

## Decisão que preciso de você
- **Aprovar P1** para eu montar o pacote de implementação (com gates) e começar? 
- Confirmar a ordem **P1 → P2 → P3** (ou quer priorizar algo de P3 antes, ex.: booking público)?
