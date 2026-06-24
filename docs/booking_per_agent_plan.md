# Plano — Booking por agente + disponibilidade "agente-aware"

> Extensão do S6 (página pública de agendamento, cal28). Status: PLANO (aguardando aprovação do PO). Build dir: `/root/docker-stacks/build/chatwoot-campaign-v4.15.1`.

## 1. Objetivo / cenário

Corretora com N vendedores. Uma página de agendamento por funil. Cada vendedor manda **o próprio link** (já atribuído a ele). A disponibilidade tem que ser **por vendedor**, mesmo quando vários compartilham a mesma caixa de e-mail (comercial@), para que "João às 14h" **não** bloqueie outro vendedor às 14h. A mesma regra precisa valer na **página pública**, no **scheduler interno** ("Agendar Reunião") e na **IA que sugere horário** — uma lógica só, sem contradição entre superfícies.

## 2. Modelo de dados (tudo aditivo)

1. **`channel_email.calendar_shared`** (boolean, default `false`).
   Marca uma caixa-agenda como **compartilhada entre vendedores**. Default `false` = comportamento atual (free/busy real). Propriedade da CAIXA (vale para qualquer superfície que peça disponibilidade).
2. **`crm_agent_booking_profiles.assignment_mode`** (int enum, default `fixed`).
   `fixed` (1 dono, hoje) | `per_agent` (link individual por vendedor).
3. **`crm_agent_booking_links`** (tabela nova):
   `id, account_id (fk), booking_profile_id (fk), agent_id (fk users), inbox_id (fk — a caixa-agenda do vendedor), slug (uuid, unique), enabled (bool, default true), timestamps`.
   Unique `(booking_profile_id, agent_id)`. Validações: agent é membro de `inbox`; inbox é calendar-enabled; tudo pertence à mesma conta.

Migrações: 1 para `calendar_shared`, 1 para `assignment_mode`, 1 para `crm_agent_booking_links`. Todas additivas → backup pré-migração + aplicar no container antigo antes do swap (padrão zero-risco já usado no S6).

## 3. Núcleo — `Crm::Meetings::AvailabilityService` vira "agente-aware"

Assinatura ganha `agent:` (opcional, retrocompatível):

```
AvailabilityService.new(inbox:, date:, timezone:, agent: nil)
```

Regra de fonte de disponibilidade:

| Condição | Busy vem de |
|---|---|
| `inbox.channel.calendar_shared? == false` (default) | free/busy **real** do provedor (Google/MS) — **comportamento atual, sem regressão** |
| `calendar_shared? == true` e `agent` presente | reuniões do CRM **onde `created_by = agent`** (status scheduled), dentro da janela |

- Mantém `strict:` (fail-closed no booking) e a subtração de meetings locais já existentes.
- No modo compartilhado a gente **ignora** o free/busy do provedor (ele super-bloqueia). Trade-off honesto: compromissos que não sejam reunião do CRM não bloqueiam. **Fase 2 (opcional):** "explain-away" = ler o free/busy real mas descontar os intervalos que são reuniões de OUTROS agentes no CRM, bloqueando só o que sobra (compromissos coletivos). Fora do v1.

Chamadores (todos passam o agente certo):
- **Página pública** (`PublicAvailableSlots`) → `agent = link.agent` (modo per_agent) ou `default_assignee` (fixed).
- **Scheduler interno** (`calendar_controller#available_slots`) → `agent = Current.user`.
- **IA sugerir horário** (`Crm::Ai::SuggestMeetingTimeService`) → `agent` do contexto.

## 4. Resolução de anfitrião/dono no booking

- **`per_agent`**: o slug do link resolve `{agent, inbox}` no servidor → `meeting.created_by = link.agent`, `card.owner = link.agent`, `meeting.inbox = link.inbox` (caixa-agenda do vendedor; pode ser a própria joao@ → free/busy real, ou a compartilhada comercial@ → CRM-por-agente). Organizador = essa caixa.
- **`fixed`**: comportamento de hoje (default_assignee).

## 5. UI (drawer "Página de agendamento pública")

- Campo **"Atribuir agendamentos a"** vira um seletor de **modo**:
  - **Agente fixo** → escolhe 1 agente (caso simples; esconde a lista).
  - **Por agente (link individual)** → mostra a lista de **agentes elegíveis** (membros da caixa-agenda da página). Cada linha: nome do agente + seletor de **caixa-agenda** dele (o mesmo "Enviar de", default = caixa da página) + **"Copiar link"** (UUID dedicado).
- **Toggle "Agenda compartilhada entre vendedores"** na caixa-agenda (`calendar_shared`), com texto explicando o efeito na disponibilidade. Default off.
- **Self-service:** agente comum vê **só o próprio link** (gera a partir da caixa dele); **admin vê/gerencia todos** no mesmo drawer.
- Esconde "Atribuir a" quando a caixa tem 1 agente (atribuição automática).

## 6. Admin / superadmin

- **Admin da conta** enxerga TODAS as caixas (Pundit já garante) → monta o template + gera/gerencia os links por agente do time.
- **Cada página é por conta (cliente)** → admin gerencia só a sua; nada vaza entre contas.
- **Superadmin de plataforma**: fora de escopo (outra camada; não toca nisso).
- Admin pode ter o próprio link se também atender (opcional).

## 7. Segurança (reusa S6 + acréscimos)

- Slug do link por agente = **UUID**, **lookup no servidor** → à prova de adulteração (booker não troca de vendedor).
- Toda a defesa do S6 mantida: verificação por e-mail (token assinado 30min, 0 criação no passo 1), advisory lock + checagem local anti-duplo-booking, rate-limit **por IP**, fail-closed no strict, sanitização XSS, validação cross-account.
- Elegibilidade: só agentes **membros** da caixa podem ter link nela (validação no modelo + controller).

## 8. Não-regressão (crítico — encosta em código vivo)

- `calendar_shared` default `false` + `agent` opcional ⇒ **todo comportamento atual fica idêntico** (S3 scheduler, S5 IA, S6 fixed).
- Caminho não-shared do AvailabilityService = byte-equivalente ao de hoje.
- Gate eager_load + testes de regressão dos 3 chamadores antes de qualquer deploy.

## 9. Rollout (slices verdes, cada um: implementar → review codex+meu → teste real/harness+prod → deploy só com OK)

- **Slice A — disponibilidade agente-aware + toggle compartilhada** (backend, +migração `calendar_shared`).
  Torna `AvailabilityService` agente-aware; liga os 3 chamadores; toggle na caixa.
  *Teste real:* caixa compartilhada → agente A marca 14h; agente B ainda vê 14h livre (harness + prod). Caixa não-compartilhada → free/busy real intacto (não-regressão).
- **Slice B — links por agente** (+migração `assignment_mode` + `crm_agent_booking_links`, UI do drawer, self-service).
  Resolução de host/owner por link; UI; copiar link.
  *Teste real:* link do João → disponibilidade dele, lead+reunião atribuídos a ele, evento na caixa dele; screenshots.
- **Fase 2 (opcional, depois):** "explain-away" para bloquear compromissos coletivos numa caixa compartilhada.

## 10. Decisões assumidas (corrigir se necessário)

1. `calendar_shared` **default off** (opt-in).
2. Disponibilidade compartilhada = reuniões onde o agente é **anfitrião** (`created_by`). (Refinamento: incluir onde ele é convidado.)
3. Elegibilidade = **membros da caixa-agenda**.
4. **Self-service** (agente gera o próprio) + admin gerencia todos.
5. "Explain-away" coletivo = **fase 2**.

## 11. Riscos

- Mexe no S3 (scheduler em produção) e S5 (IA) → mitigado por retrocompatibilidade (default off / agent opcional) + testes de regressão dos 3 chamadores.
- Caixa compartilhada perde compromissos não-CRM até a fase 2 (trade-off documentado e aceito).
