# Manual — Atribuição e Handoff (IA → Humano)

Guia prático do painel **Atribuição e handoff** do funil de CRM. Explica cada campo,
o que acontece por trás, e traz receitas prontas para os cenários mais comuns.

> Onde fica: dentro do funil (Kanban), botão **"Atribuição e handoff"** no topo.

---

## 1. O conceito em uma frase

A IA atende o cliente sozinha até bater um **gatilho** que você descreve em linguagem
natural. Nesse momento ela **passa a conversa para um humano** — do jeito que você
configurar aqui: direto ou por convite, para a caixa inteira ou uma pessoa específica,
e com um plano B caso ninguém pegue.

---

## 2. Dois níveis de configuração

| Nível | Para que serve |
|---|---|
| **Padrão do funil** | Regra que vale para **todas as etapas** que não têm regra própria. |
| **Personalizações por etapa** | Cada etapa pode **herdar o padrão** ou ter a **sua própria** regra (botão `Padrão` / `Personalizar`). |

Exemplo: o funil inteiro fica **desligado**, mas só a etapa "Em atendimento" liga o
handoff. Ou o contrário: o funil passa por convite, mas a etapa "Fechamento" passa
direto para o vendedor responsável.

---

## 3. Os campos, um a um

### Passar para um humano neste estágio
Liga/desliga o handoff. Desligado = a IA nunca passa a conversa nesse funil/etapa.

### Quando transferir (gatilho)
Texto livre que diz à IA **quando** passar. A IA lê **toda mensagem** do cliente e
decide. Escreva como se explicasse para um atendente novo.

- Ex.: `Cliente pede para falar com atendente humano, reclamação grave, ou pergunta que a IA não sabe responder.`
- Ex.: `Quando o cliente confirmar que quer fechar a compra.`

### Fluxo do handoff — **Direto** ou **Convite**
A diferença mais importante do painel.

| | **Direto — atribui e cala a IA** | **Convite — a IA segue atendendo até um humano pegar** |
|---|---|---|
| O que faz | Atribui a conversa a um agente **e silencia a IA na hora**. | Adiciona o agente como **participante + manda notificação** (sino/push/e-mail), mas **a IA continua respondendo** o cliente. |
| Quando a IA cala | Imediatamente. | Só quando um humano **se auto-atribui** a conversa. |
| Bom para | Times que assumem rápido; quando o humano tem de assumir já. | Não deixar o cliente no vácuo: a IA segura a conversa até alguém pegar. |
| Plano B "se ninguém pegar" | Não se aplica. | **Aparece** (re-notificar ou escalar). |

### Atribuir para — **Caixa inteira** ou **Pessoa específica**
- **Caixa inteira**: o pool é toda a equipe da caixa (inbox). Aparece o campo **Atribuição** abaixo.
- **Pessoa específica**: sempre a mesma pessoa que você escolher.

### Atribuição (só com "Caixa inteira")
Como escolher dentro da caixa:
- **Rodízio**: balanceia pela carga — quem tem menos conversas abertas pega.
- **Direto (por nome)**: tenta casar o nome que a **IA sugeriu** na conversa; se não achar, cai no rodízio.

### Preferir quem está online
Prioriza agentes online. **Se ninguém estiver online, segura** e tenta de novo quando
alguém entrar — em vez de largar o cliente com a IA já calada.

### Se ninguém pegar em N min (só no fluxo **Convite**)
Prazo de "pega". Passado esse tempo com o convite em aberto, escolha o plano B:

- **Re-notificar**: manda a notificação de novo para **o mesmo agente convidado**, e
  repete a cada N min (**até 8 vezes**). Bom para equipes pequenas.
- **Escalar para**: passa para um **supervisor** que você escolhe. Bom quando há um
  responsável de plantão. (O supervisor precisa ser membro da caixa.)

---

## 4. Receitas prontas

### Receita A — Suporte simples (assumir rápido)
> Cliente pede humano → cai para quem está livre e a IA cala.

- Passar para humano: **ligado**
- Fluxo: **Direto**
- Atribuir para: **Caixa inteira** → **Rodízio**
- Preferir quem está online: **ligado**
- Quando transferir: `Cliente pede atendente humano ou está irritado/reclamando.`

### Receita B — Vendas com dona da conta + escalonamento
> A IA segura a conversa e convida a Maria; se ela não pegar em 15 min, chama o gerente.

- Fluxo: **Convite**
- Atribuir para: **Pessoa específica** → *Maria*
- Se ninguém pegar em: **15 min** → **Escalar para** *Gerente*
- Quando transferir: `Cliente quer proposta, preço ou fechar. Passe para a vendedora.`

### Receita C — Equipe pequena, insistir sem escalar
> Convida a caixa; se ninguém pega em 10 min, re-cutuca a cada 10 min (até 8x).

- Fluxo: **Convite**
- Atribuir para: **Caixa inteira** → **Rodízio**
- Se ninguém pegar em: **10 min** → **Re-notificar**

### Receita D — Só uma etapa passa para humano
> O funil roda 100% com IA; só "Em atendimento" chama gente.

- **Padrão do funil**: Passar para humano **desligado**
- Etapa "Em atendimento" → **Personalizar** → **ligado**, Fluxo **Convite**
- Demais etapas → **Padrão** (seguem só com a IA)

### Receita E — Fora do horário sem largar o cliente
> À noite ninguém online: a IA segura e só passa quando um humano entra.

- Fluxo: **Direto** (ou Convite)
- Preferir quem está online: **ligado**
- Resultado: sem online, o handoff **fica segurando** e o sistema tenta de novo
  automaticamente quando alguém fica online.

---

## 5. Regras e limites (o que o sistema faz sozinho)

- **A IA decide o "quando"** pelo texto de *Quando transferir* — ela lê cada mensagem.
- **Anti-repique (6h):** a mesma conversa não é re-passada dentro de 6 horas.
- **Convite esquecido expira em 24h:** fecha sozinho, sem re-notificar nem escalar.
- **Re-notificar:** no máximo **8 vezes**; depois para (o convite ainda expira em 24h).
- **Escalar:** só existe no fluxo **Convite** e exige um supervisor **membro da caixa**.
- **Pessoa específica que saiu da caixa:** o handoff **cai para a caixa inteira** (não
  trava nem perde o cliente).
- **Direto x Convite (lembrete):** Direto cala a IA na hora; Convite mantém a IA
  atendendo até um humano assumir de fato.

---

## 6. Dúvidas rápidas

- **"Liguei e nada passou."** Revise o texto de *Quando transferir* (muito restrito?) e
  se a etapa atual está herdando o Padrão ou tem regra própria desligada.
- **"Convidei mas o bot continua falando."** É o esperado no fluxo **Convite** — a IA só
  cala quando alguém se **auto-atribui** a conversa.
- **"Escalar não aparece."** Troque o fluxo para **Convite** (Direto não tem plano B).
- **"Escolhi Pessoa específica mas caiu para outro."** A pessoa provavelmente saiu da
  caixa — o sistema usa a caixa inteira como rede de segurança.
