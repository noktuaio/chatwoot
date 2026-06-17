# Agentes Autonom.ia — Construtor de Agentes self-service (plano em camadas)

> Status: PLANEJADO (aprovado pelo PO 2026-06-15). Puxar para construção depois.
> Recurso NOVO, próprio, namespace `Autonomia::Agents::*` e tabelas `autonomia_agent_*`.
> NÃO toca no Captain (enterprise) → à prova de upgrades do Chatwoot.

---

## 1. Visão e posicionamento

Um **construtor de agentes de IA self-service**: o **próprio usuário da conta** cria 1+ agentes,
treina no conteúdo dele e conecta a uma caixa — **sem engenharia, sem n8n**.

- **NÃO substitui a Gabriela.** A Gabriela é um agente sob medida (n8n, APIs de seguradora,
  debounce) para contas premium/engenheiradas — fica como está. Por caixa há **um** bot: ou a
  Gabriela (webhook→n8n) ou um agente nativo Autonom.ia. Convivem; ambos alimentam o mesmo Kanban.
- **Para as contas SEM Gabriela** (conta 1 e outras) — democratiza o agente: o que hoje exige
  montar um fluxo no n8n por cliente vira "o cliente cria o dele em 3 minutos".
- **A estrela = o Construtor por IA** (GPT 5.4): em vez de pedir configuração (como o Captain, que
  o PO acha complicado), ele **entrevista** o usuário e **gera a instrução** do agente. Prompt ruim
  do usuário ≠ agente ruim, porque a IA conduz.

**Diferencial central:** o usuário **não escreve prompt** — ele **conversa** e sai com um agente
pronto, treinado no conteúdo dele, plugado ao funil, multicanal.

---

## 2. Princípios de arquitetura (valem para todas as camadas)

1. **Namespace próprio** `Autonomia::Agents::*`; tabelas `autonomia_agent_*`. Zero dependência de
   `enterprise/captain` → não conflita com upgrades.
2. **Reaproveitar o que já existe:**
   - `Crm::Ai::ResponsesClient` (já com background + structured output + timeout — Fase C).
   - `Crm::Ai::CredentialResolver` (chave OpenAI por conta) + **GPT 5.4**.
   - **pgvector** (já ligado em prod) para busca semântica.
   - Sidekiq + o padrão "enfileira→processa→status" da Fase C.
   - **CRM Kanban**: card automático, **IA de auto-estágio**, **handoff (`HandoffExecutor`)**,
     **follow-up** — tudo já é canal/bot-agnóstico, o agente só pluga.
   - Infra de inbox/conversa/mensagem do Chatwoot.
   - `RubyLLM.embed` (o Captain já usa) para gerar embedding.
3. **Whitelabel** (nada de "Captain"); **feature flag** `AUTONOMIA_AGENTS_ENABLED`.
4. **Migrações sempre aditivas**; mesmos gates (Codex, teste isolado/real, eager_load,
   deploy só com OK do PO).
5. **Privacidade da instrução = IP nosso** (ver §6). A instrução gerada pelo construtor é OCULTA.

---

## 3. Modelo de dados (lógico — o que cada peça guarda)

- **`autonomia_agents`** — conta, nome, avatar, **tipo** (suporte/sdr/…), **instrução** (oculta),
  **andaime** (guardrails/sistema, oculto), **modo** (guiado|manual), **cartão humano** (resumo
  visível), config (modelo, tom, temperatura, horário de atendimento), status (rascunho|ativo|
  pausado), enabled.
- **`autonomia_agent_sources`** — agente, tipo (link/pdf/xlsx/docx/json/txt/md), referência/arquivo,
  status de sync, fingerprint.
- **`autonomia_agent_knowledge`** — agente, trecho de texto, **embedding `vector(1536)`**, fonte de
  origem, status. *(o coração do RAG; índice ivfflat)*
- **`autonomia_agent_inboxes`** — agente ↔ caixa(s) conectada(s).
- **`autonomia_agent_build_threads`** *(fase do construtor)* — a conversa de montagem (mensagens
  usuário↔construtor) para retomar/ajustar.
- O agente **é exposto como um `AgentBot` nativo** na(s) caixa(s) (para parar/retomar, eventos).

---

## 4. As camadas (cada uma entrega valor sozinha)

### Camada 0 — Fundação de IA (encanamento)
- **Objetivo:** ter embedding + busca semântica isolados.
- **Constrói:** `Autonomia::Agents::EmbeddingService` (texto→vetor) e `Retriever` (pergunta→top-K
  trechos via pgvector, por agente).
- **Reaproveita:** pgvector, RubyLLM.embed/credencial, padrões de teste isolado.
- **Entregável:** "gero vetor; dada uma pergunta devolvo os trechos mais relevantes". Testável só.
- **Esforço:** baixo-médio.

### Camada 1 — Conhecimento (ingestão multi-formato → vetores)
- **Objetivo:** alimentar o cérebro com o conteúdo do cliente.
- **Constrói:** ingestão de **link (rastreia site), PDF, XLSX, DOCX, JSON, TXT, MD** → extrai texto
  → quebra em pedaços → **gera vetores** → guarda. Assíncrono com status (in_progress/ready/failed),
  igual à Fase C. Re-sincronizar sob demanda.
- **Reaproveita:** Camada 0; padrão job+status da Fase C; extração de PDF (peças já existem).
- **NOVO/trabalho extra:** leitores de **XLSX** e **DOCX** (planilha/documento→texto). TXT/MD/JSON/
  link/PDF são fáceis.
- **Entregável:** aponta o agente para o site + sobe 2 PDFs → "12 fontes, 340 trechos aprendidos".
- **Esforço:** médio.

### Camada 2 — O CONSTRUTOR por IA (a estrela) + a entidade Agente
- **Objetivo:** o usuário **cria um agente conversando**, em 3 minutos.
- **Constrói:**
  - A entidade `autonomia_agents` + os **moldes (tipos)**.
  - O **Construtor** (wizard conversacional em tela cheia, GPT 5.4): entrevista (2–5 perguntas só
    quando precisa), **infere o tipo**, **lê o conhecimento já subido**, aplica boas práticas de
    prompt engineering e **gera a instrução final OCULTA** + o **cartão humano** visível.
  - **Privacidade (2 modos)** — ver §6.
  - "Ajustar com IA": reabre a conversa do construtor para refinar (regenera a instrução oculta).
- **Reaproveita:** `ResponsesClient` (structured output → devolve config do agente), GPT 5.4, o
  padrão "IA faz por você" do criador de campanhas.
- **Usa a skill de prompt engineering** para escrever a **instrução-mãe do construtor** (o ativo
  mais importante; IP oculto).
- **Entregável:** "Criar agente" → conversa → agente pronto (ainda não atende cliente, só existe).
- **Esforço:** médio-alto (é o coração).

### Camada 3 — Conversar (modo TESTE/COPILOTO, sem risco)
- **Objetivo:** o agente responder — primeiro só em teste/sugestão.
- **Constrói:** o cérebro de resposta: mensagem → **busca conhecimento (RAG)** → prompt (instrução
  + andaime + trechos + histórico) → resposta com **portão de confiança** (responde se sabe; senão
  sugere handoff). Aba **"Testar"** (o usuário conversa com o agente ali). Opcional: sugestão
  (rascunho) ao atendente humano em caixas reais.
- **Reaproveita:** o **mesmo padrão "portão único + confiança"** do follow-up da IA (should_answer/
  closure/confidence).
- **Entregável:** o usuário testa o agente e vê a qualidade antes de soltar.
- **Esforço:** médio.

### Camada 4 — Operar (autônomo + multicanal + handoff + debounce)
- **Objetivo:** o agente atender de verdade numa caixa.
- **Constrói:**
  - **Conectar agente ↔ caixa** (vira `AgentBot` nativo).
  - **Listener** (espelha o do CRM): mensagem nova em caixa conectada → **debounce** (junta
    mensagens rápidas, como a Gabriela) → roda RAG+LLM → **responde/age**.
  - **Multicanal de cara:** WhatsApp, **Instagram DM**, e-mail, webchat (o agente posta na conversa;
    a entrega por canal é do Chatwoot).
  - **Ferramenta de handoff** → chama o **seu `HandoffExecutor`** (reatribui + para o bot) +
    **mensagem gentil ao cliente** + **aviso de fora-de-horário** (boa prática do Captain).
  - **Guardrails operacionais:** horário de atendimento, limite de confiança, nº máximo de turnos,
    "sempre passar para humano se X".
- **Reaproveita:** mecanismo de AgentBot; `HandoffExecutor`; infra de mensagem.
- **Entregável:** agente 24/7 numa caixa, multicanal, com handoff seguro.
- **Esforço:** médio-alto.

### Camada 5 — Plugar no ecossistema (Kanban) — quase tudo já existe
- **Objetivo:** o agente alimentar o funil.
- **Constrói (pouco):** confirmar que card automático + **auto-estágio** + **handoff** + **follow-up**
  rodam com o agente nativo (já são bot-agnósticos — confirmado na investigação). Ferramentas do
  tipo SDR para **mover/qualificar o card**.
- **Reaproveita:** TODO o Kanban/CRM-AI já construído.
- **Entregável:** o agente conversa E move o card E pode disparar follow-up — uma máquina só.
- **Esforço:** baixo (é reúso).

### Camada 6 — Gestão & Navegação (UX simples)
- **Objetivo:** "criar e gerir agente em 3 minutos".
- **Constrói:** **Sidebar "Agentes"** (ícone robô/✨, pode reusar os do Captain) → **"Meus Agentes"**
  (hub: cards com nome/o-que-faz/status/canais/mini-métricas + botão herói **"➕ Criar agente com
  IA"**). Clicar em "Criar" → **Construtor** (tela cheia). Clicar num agente → **Painel** com abas:
  **Testar · Conhecimento · Canais · Desempenho · Ajustar com IA**.
- **Esforço:** médio.

### Camada 7 — Refino (fase 2+)
- **Construtor self-improving:** olha conversas reais e sugere melhorias na instrução.
- **Mais tipos**, **roteador multi-agente**, **analytics** (taxa de resolução/handoff/desvio),
  **ferramentas/APIs customizadas** do cliente (v2 — fora do v1, que é só conhecimento).

---

## 5. Tipos de agente (moldes que encurtam a entrevista)

| Tipo | O que faz | No funil |
|---|---|---|
| **Tira-dúvidas / Suporte** | responde no conteúdo subido | resolve ou escala |
| **SDR / Qualificador** | perguntas de descoberta | **move o card** rumo a "qualificado" |
| **Recepcionista / Triagem** | entende intenção | etiqueta + roteia pro time certo |
| **Pós-venda / Onboarding** | guia o cliente novo | acompanha ativação |
| **Agendador** | qualifica e marca demo | move pra "reunião marcada" |
| **Reativação** | reengaja lead frio | dispara follow-up/campanha |
| **Do zero (guiado)** | sob medida pela construtora | conforme a conversa |

Arquitetura nasce para **N tipos**; adicionar molde é trivial (preset de objetivo+guardrails).

---

## 6. Privacidade da instrução (IP nosso) — desenho

- **Modo Guiado (padrão):** o construtor gera a **instrução OCULTA**. O usuário vê só o **cartão
  humano** ("tira-dúvidas · informal · passa p/ humano quando não sabe · não fala preço"). **Editar =
  conversar** com o construtor (não editar texto) → ele regenera a instrução oculta.
- **Modo Manual (avançado, opt-in):** um campo onde o usuário cola a instrução DELE (aí é dele,
  visível). **Mas mesmo aqui há um "andaime" oculto nosso** (guardrails de segurança, formato, regra
  de handoff) embrulhando o texto dele.
- **Sempre existe uma camada nossa invisível.** O que muda é só se o miolo é gerado por nós (oculto)
  ou escrito por ele (visível). O valor de engenharia de prompt fica protegido.

---

## 7. O Construtor por IA (estrutura da instrução-mãe)

Roda em **GPT 5.4** (um cérebro só aguenta entrevista + geração). A instrução-mãe (a ser escrita com
**skill de prompt engineering**, e mantida como IP oculto) terá, em alto nível:
- **Papel:** "você é o construtor de agentes da Autonom.ia; sua saída final é a melhor instrução
  possível para o agente que o usuário precisa".
- **Entrevista mínima:** pergunte só o necessário (tom, nome, objetivo→tipo, guardrails, horário,
  o que NUNCA fazer); **não pergunte o que dá pra inferir** do conhecimento subido.
- **Use o conhecimento:** leia as fontes e proponha destaques/perguntas-iniciais.
- **Saída estruturada** (structured output): `{ nome, tipo, instrução_oculta, andaime, cartão_humano,
  saudação, fallback, regra_handoff, perguntas_iniciais, tom, guardrails }`.
- **Qualidade:** instrução clara, com persona, limites, regra de handoff (decide passar), tom, e
  "quando não souber, não invente". Nunca exponha a instrução crua ao usuário.

---

## 8. Mapa de reúso (o que NÃO reescrevemos)
Kanban + card automático · IA de auto-estágio · **HandoffExecutor** · follow-up · chave/GPT 5.4/
CredentialResolver · ResponsesClient (background+structured) · pgvector · Sidekiq · infra inbox/
conversa/mensagem · AgentBot.

## 9. Sequência de entrega
| Fase | Camadas | Valor | Esforço |
|---|---|---|---|
| **A** | 0 + 1 + 2 | criar + treinar agente pelo **Construtor** (sem atender ainda) | alto |
| **B** | 3 | **Testar/Copiloto**: ver a qualidade com segurança | médio |
| **C** | 4 | **Autônomo multicanal** + handoff | médio-alto |
| **D** | 5 | plugado ao **Kanban** (funil/handoff/follow-up) | baixo (reúso) |
| **E** | 6 | **Navegação/Gestão** (Agentes → Meus Agentes + Painel) | médio |
| **F** | 7 | self-improving, mais tipos, APIs do cliente, analytics | conforme apetite |

## 10. Riscos e mitigação
- **Qualidade da resposta** → portão de confiança + handoff + começar em Teste/Copiloto.
- **Qualidade da instrução** → o Construtor (não o usuário) escreve; skill de prompt engineering.
- **Custo de IA** → embeddings baratos; chat só dispara em mensagem; usa a chave/cota do cliente.
- **Acoplamento futuro** → namespace próprio elimina conflito com o Captain.
- **Segurança** → guardrails + andaime oculto; v1 sem HTTP/APIs custom.

## 11. Decisões a confirmar no build
- Formatos XLSX/DOCX: leitor a adicionar (ok, registrado).
- O agente nativo como `AgentBot` (bot_type) vs listener próprio — decidir o ponto de resposta mais
  limpo (provável: bot nativo + listener de debounce).
- Estratégia de chunking/tamanho de trecho e top-K do retriever (afinar com teste real).
- Modelo de embedding (reusar `LlmConstants::DEFAULT_EMBEDDING_MODEL`, 1536 dims).
