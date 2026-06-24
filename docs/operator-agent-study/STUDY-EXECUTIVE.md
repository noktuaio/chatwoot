# Agente Operacional Autônomo — Estudo executivo

Resumo de decisão sobre o PRD do "Agente Operacional Autônomo": um sistema interno em que a pessoa **fala em linguagem natural** e a própria plataforma **descobre, entende, diagnostica, navega e opera** o que foi pedido — em vez de o usuário caçar menus ou abrir chamado.

Baseado em 5 sondagens feitas **dentro do nosso código real** (não em suposição). Data: 2026-06-20.

---

## A decisão em uma frase

> A **ideia é certeira e diferenciadora**. O **jeito de construir proposto no PRD ("fazer tudo, livre, agindo sozinho") é arriscado demais pra começar.** O caminho seguro e que entrega valor rápido é **começar pelo que ENTENDE e DIAGNOSTICA (sem mexer em nada), e ir liberando a operação aos poucos, com trava.**

As 5 análises, independentes, chegaram à mesma conclusão.

---

## Por que vale a pena (a oportunidade)

A plataforma é enorme (canais, caixas, automações, integrações, permissões, relatórios). A maior parte do suporte hoje **não é bug** — é "onde fica isso?", "por que parou?", "como configuro?". Hoje a gente ensina o cliente a clicar, pede print, pergunta horário.

O agente vira a **primeira linha de suporte e operação**: em vez de explicar onde clicar, ele **abre a tela**; em vez de causa genérica, ele **verifica a conta real**; em vez de pedir print, ele **lê o erro e o histórico**. O ganho: menos chamado, resolução mais rápida, e uma plataforma que **se explica e se opera sozinha** — algo que vende muito além de "white-label customizado".

---

## O que é verdade (e o PRD não enfatiza)

Três realidades que mudam o plano:

1. **"Desfazer" automático não existe de verdade aqui.** A maioria das ações que apagam ou mudam dados **não tem volta** no nosso sistema (apagar contato, conversa, caixa; enviar campanha; mexer em calendário externo). Então **não dá pra deixar o agente apagar/alterar em massa sozinho** — isso bate de frente com a sua regra de "não aceito regressão / backup antes de destrutivo".

2. **Controlar a tela inteira é caro e quebra a cada atualização do Chatwoot.** As telas quase não têm "marcadores" estáveis (17 em ~4.900 arquivos). Mapear tudo seria um custo de manutenção eterno. Dá pra **navegar e destacar** com facilidade; **preencher e enviar formulário** só vale a pena em **poucas telas escolhidas**.

3. **"Agir sozinho por padrão" conflita com as suas próprias regras.** O alvo é uma caixa de suporte com clientes reais. O agente errar uma ação tem impacto real. A recomendação é **conservador primeiro**: ele age sozinho no que é leitura/diagnóstico/navegação; pede confirmação pro que muda dado.

E o que joga a favor: **boa parte da fundação já existe** — isolamento por conta, IA por conta, o motor dos agentes Autonom.ia, o copiloto de conversa (que acabamos de lançar) e até um padrão de "trava de permissão" pronto pra reaproveitar.

---

## O caminho recomendado (inverter o plano)

Não construir a "máquina universal" antes de entregar valor. **Começar estreito e crescer pela demanda real:**

- **Fase 1 — o agente que ENTENDE e DIAGNOSTICA (sem mexer em nada).** Ele responde "por que essa caixa parou?", "por que essa conversa não foi atribuída?", "essa conta está pronta pro Instagram?", abre a tela certa e mostra a causa — **lendo o estado real**, sem risco. É a maior deflexão de suporte com o menor risco. **É por aqui que se começa.**
- **Fase 2 — operar o reversível.** Ele passa a **executar** ações seguras e reversíveis (atribuir conversa, pôr etiqueta, mover card), sempre com registro e com um "preview" antes.
- **Fase 3+ — o resto, com trava.** Lote e ações destrutivas só com **confirmação explícita e backup**, uma por uma, por área.

Tudo isso **reaproveita** o que já temos e fica **gateado** (liga/desliga por conta), no nosso padrão de "não quebrar quando o Chatwoot atualizar".

---

## Esforço e custo (ordem de grandeza)

| Fase | O que entrega | Prazo aprox. |
|---|---|---|
| Fundação + segurança | a "trava" que precede qualquer operação | 1-2 semanas |
| **Fase 1 — diagnóstico/entendimento (read-only)** | **o MVP que deflete suporte, baixo risco** | **3-5 semanas** |
| Fase 2 — operar o reversível | executar ações seguras com preview/registro | 4-6 semanas |
| Fase 3 — lote + telas guiadas | criar automação, importar base, etc. | 3-5 semanas |
| Fase 4 — destrutivo por área | só com backup/confirmação, área por área | longo, contínuo |

**Atenção a uma métrica que o PRD lista mas não fecha: custo por resolução.** Um agente que investiga + age + valida consome IA a cada tarefa. Precisamos de uma **meta de custo por resolução** pra garantir margem (decisão sua).

---

## Riscos principais (em linguagem simples)

- **Perda de dado** se liberarmos escrita ampla sem trava → mitigação: começar read-only; destrutivo só com backup+confirmação.
- **Quebrar no update do Chatwoot** se mapearmos a tela inteira → mitigação: poucas telas, do nosso jeito.
- **Vazar informação entre contas ou expor código/IP** → mitigação: tudo passa pela trava de permissão por conta; "ver o código" fica só no modo interno de engenharia.
- **O agente ser induzido a fazer besteira** por texto de uma conversa → mitigação: ele nunca decide sozinho que algo é seguro; confirmação é validada no servidor.

---

## O que eu preciso de você pra começar

1. **Confirmar a postura conservadora** (diagnostica/navega sozinho; pede confirmação pra mexer em dado). Isso reconcilia o PRD com as suas regras.
2. **As ~15 dúvidas/chamados mais comuns de verdade** (dos seus tickets) — é o que define o que a Fase 1 resolve primeiro.
3. **OK pra começar pela Fase 1 (read-only)**: diagnóstico + entender + navegar, sem operar ainda.
4. **Project Intelligence ("o agente conhece o código") só no modo interno** primeiro (proteção de IP).
5. **Uma meta de custo por resolução** (pode ser aproximada).

---

## Conclusão

O seu objetivo — **um sistema operacional interno assistido, operado por linguagem natural** — é viável e estrategicamente forte. A diferença entre "promessa de slide" e "produto que funciona" está em **não tentar fazer tudo de uma vez**: provar a tese com um agente que **entende e diagnostica** (valor real, risco baixo, muito reuso do que já temos), e só então abrir a mão pra operar — sempre com trava onde pode doer.

Recomendo aprovarmos a **Fase 1 (read-only)** e, em paralelo, você me passar a lista das intenções reais — com ela eu monto o backlog concreto e a primeira leva de diagnósticos.

> Detalhe técnico e evidência: `STUDY-TECHNICAL.md` + `probe-1..5`.
