# Pilar 4 - Project Intelligence + "commit implantado"

Sondagem de viabilidade contra o codigo real do fork Chatwoot v4.15.1 white-label. Escopo: projeto como fonte de verdade para um Agente Operacional Autonomo, com enfase em deploy, manifest por implantacao, busca de codigo em producao e fronteira de IP.

## Veredito

Recomendacao: **interno-primeiro**.

O pilar ja e util hoje para suporte/engenharia via Codex CLI lendo este checkout: da para responder perguntas de comportamento com `rg`, inspecao de controllers/services/models e cruzamento com rotas/flags. Isso cobre bem o modo "engenharia assistida".

Para virar recurso em producao, ainda falta uma camada de **deployment intelligence**: um manifest gerado no build e enriquecido no runtime. Sem isso, o agente consegue explicar o codigo da imagem, mas nao consegue provar com seguranca qual commit esta rodando, quais migrations foram aplicadas no banco, quais flags estao efetivas por conta, nem quais contratos/API/UI pertencem exatamente aquela implantacao.

Nao recomendo expor busca de codigo ou explicacoes com paths/linhas para usuario final. Para cliente final, o seguro e explicar comportamento em linguagem de produto e diagnostico operacional. Paths, snippets, diffs, SQL, nomes internos e razoes de implementacao devem ficar em modo interno/engenharia.

## Evidencias principais

### Build/deploy da imagem custom

O Dockerfile customizado e pequeno e copia a arvore inteira para `/app`:

- `docker/custom/Dockerfile.crm:1` usa `FROM chatwoot/chatwoot:v4.15.1`.
- `docker/custom/Dockerfile.crm:9-11` copia `Gemfile`/`Gemfile.lock` e roda `bundle install`.
- `docker/custom/Dockerfile.crm:13` remove `/app/public/vite` herdado da imagem base.
- `docker/custom/Dockerfile.crm:15` faz `COPY . /app`.

A `.dockerignore` nao exclui `.git`, `.git_sha`, `docs`, `spec`, `swagger` ou `public/vite`:

- `.dockerignore:1-18` ignora `.bundle`, `.env*`, `node_modules`, `vendor/bundle`, `tmp`, `log`, `storage`, `public/system`, `public/packs`, etc.
- Ausencias importantes: `.git`, `.git_sha`, `public/vite`, `docs`, `spec`, `swagger`.

Implicacao: se o build context vier de um checkout Git real, `.git` pode entrar na imagem, porque nao esta ignorado. No working dir atual, `.git` existe como diretorio vazio e `git rev-parse` falha (`fatal: not a git repository`), mas `.git_sha` existe e contem `97bb8ecd326299c46eacea74863976427c96fe94`.

Isso e suficiente para exibir um build id, mas nao e uma cadeia robusta de "commit implantado": o Dockerfile nao gera `.git_sha`, nao valida se ele bate com a origem, nao grava label OCI na imagem e nao falha quando o SHA esta ausente.

### Versionamento e commit hoje

Ja existe rastreio basico:

- `config/app.yml:2` define `version: '4.15.1'`.
- `package.json:3` define `"version": "4.15.1"`.
- `VERSION_CW:1` contem `4.15.1`.
- `VERSION_CWCTL:1` contem `3.5.0`.
- `config/initializers/git_sha.rb:2-16` define `GIT_HASH`: tenta `git rev-parse HEAD` se `.git` existir, depois cai para `.git_sha`, depois `HEROKU_SLUG_COMMIT`, depois `unknown`.
- `app/controllers/dashboard_controller.rb:69-91` injeta `APP_VERSION` e `GIT_SHA` em `window.globalConfig`.
- `app/javascript/shared/store/globalConfig.js:7-21` consome `APP_VERSION`, `GIT_SHA` e flags.
- `app/javascript/dashboard/routes/dashboard/settings/account/components/BuildInfo.vue:27-33` mostra/copia o SHA e `:46-53` renderiza `v<version>` e `Build <sha curto>`.
- `app/controllers/super_admin/instance_statuses_controller.rb:22-31` mostra status de migrations como `pending/completed` e `Git SHA`.
- `app/controllers/api_controller.rb:4-8` expoe apenas `version`, timestamp, Redis e Postgres no endpoint raiz; nao expoe SHA.

Ponto fraco: `git_sha.rb` executa `git rev-parse` se houver diretorio `.git`. Com `.git` vazio, como neste working dir, o comando falha e so depois usa `.git_sha`. Em producao isso pode gerar ruido no boot/log caso a imagem tenha `.git` incompleto.

### Migrations e estado de banco

O repo tem 200 arquivos em `db/migrate`:

- 2023: 28
- 2024: 17
- 2025: 58
- 2026: 97

Primeira migration: `20230426130150_init_schema.rb`. Ultima migration por nome: `20260627000001_add_actuation_to_autonomia_agents.rb`.

O `db/schema.rb:13` esta em `ActiveRecord::Schema[7.1].define(version: 2026_06_26_000001)`, ou seja, nao reflete a migration local mais recente `20260627000001_add_actuation_to_autonomia_agents.rb`. Essa migration adiciona `actuation` e indice em `autonomia_agents` (`db/migrate/20260627000001_add_actuation_to_autonomia_agents.rb:6-15`), e o codigo ja usa esse campo em `app/models/autonomia/agents/agent.rb:30` e no copiloto em `app/controllers/api/v1/accounts/autonomia/conversation_copilot_controller.rb:24-35`.

Hoje ja da para extrair em runtime:

- status agregado de pending migrations via `ActiveRecord::Base.connection.migration_context.needs_migration?`, usado em `app/controllers/super_admin/instance_statuses_controller.rb:22-24`;
- lista real via DB/console consultando `schema_migrations`;
- versao de schema local via `db/schema.rb`.

Falta para manifest: lista/hash das migrations aplicadas, lista/hash das migrations presentes na imagem e comparacao entre ambas.

### Feature flags e configuracao

Ha um padrao forte de gating por ENV:

- `app/controllers/dashboard_controller.rb:80-87` expoe `CAMPAIGN_IMPORT_ENABLED`, `WHATSAPP_API_CAMPAIGNS_ENABLED`, `CRM_KANBAN_ENABLED`, `CRM_COPILOT_ENABLED`, `CRM_CALENDAR_MEETINGS_ENABLED`, `CRM_AI_ENABLED`, `AUTONOMIA_AGENTS_ENABLED`, `EMAIL_CAMPAIGN_ENABLED`.
- `app/services/autonomia/agents/config.rb:148-155` exige `AUTONOMIA_AGENTS_ENABLED` e, quando recebe conta, exige tambem habilitacao por conta.
- `app/services/autonomia/agents/config.rb:165-184` usa `accounts.internal_attributes['autonomia_agents_enabled']` ou `AUTONOMIA_AGENTS_GLOBAL` com credencial de IA disponivel.
- `app/views/api/v1/models/_account.json.jbuilder:33` expoe `autonomia_agents_enabled` por conta.
- `app/services/crm/ai/config.rb:97-103` gateia IA de CRM por `CRM_AI_ENABLED` e `CRM_AI_MEDIA_ENABLED`.

Isso ja da uma base para snapshot de flags. O que falta e normalizar em um manifest runtime:

- flags globais efetivas no processo;
- flags por conta relevantes ao agente;
- origem da decisao: ENV, `InstallationConfig`, `account.internal_attributes`, feature flag nativa do Chatwoot;
- mascaramento de valores sensiveis.

### Autonomia existente

O sistema "Autonomia agents" ja esta bem isolado:

- 74 arquivos encontrados sob `app/services/autonomia`, `app/models/autonomia`, `app/controllers/api/v1/accounts/autonomia`, `app/javascript/dashboard/components/autonomia` e `app/javascript/dashboard/routes/dashboard/autonomia`.
- 9 controllers em `app/controllers/api/v1/accounts/autonomia`.
- 7 wrappers/API modules JS de Autonomia em `app/javascript/dashboard/api`.

Padroes relevantes:

- `app/controllers/api/v1/accounts/autonomia/base_controller.rb:1-17` gateia por feature e exige administrador de conta.
- `app/controllers/api/v1/accounts/autonomia/base_controller.rb:19-26` prende escopos a `Current.account`.
- `app/controllers/api/v1/accounts/autonomia/conversation_copilot_controller.rb:59-65` gateia o copiloto por CRM + `CRM_COPILOT_ENABLED`.
- `app/controllers/api/v1/accounts/autonomia/conversation_copilot_controller.rb:68-73` busca conversa dentro de `Current.account` e chama `authorize @conversation, :show?`.
- `app/javascript/dashboard/routes/dashboard/autonomia/autonomia.routes.js:17-35` esconde rotas quando ENV master ou flag por conta estao off.
- `app/javascript/dashboard/routes/dashboard/dashboard.routes.js:25-37` registra as rotas Autonomia junto das rotas do dashboard.

Para Pilar 4, isso significa que o caminho natural e adicionar inteligencia de projeto como capability interna do agente, respeitando o mesmo padrao: flag global, conta/role, Pundit e resposta minimizada.

### Contratos de API e UI registry

O repo tem Swagger/OpenAPI, mas ele nao cobre as customizacoes investigadas:

- `swagger/paths` tem 141 arquivos.
- `swagger/swagger.json` tem 477.501 bytes.
- `lib/tasks/swagger.rake:141-155` gera `swagger.json` e arquivos por tag group.
- `config/routes.rb:925-927` serve `/swagger`.
- `rg` encontrou 0 referencias a `autonomia`, `campaign_import`, `email_campaign` e `crm` dentro de `swagger`.

As rotas custom existem no Rails:

- `config/routes.rb:245-269` declara namespace `autonomia`, CRUD de agents, sources, channels, build threads, builder images e endpoints do copiloto.

Mas os contratos estao espalhados entre:

- rotas Rails (`config/routes.rb`);
- controllers;
- wrappers JS (`app/javascript/dashboard/api/autonomia/*.js`, `app/javascript/dashboard/api/autonomiaCopilot.js`);
- serializers Jbuilder;
- store modules Vuex.

Para um manifest de implantacao, isso e "extraivel", mas nao pronto. Precisaria gerar um contrato consolidado no build ou no CI e incluir as custom APIs.

UI registry:

- Existe registry implicito nas rotas Vue (`app/javascript/dashboard/routes/dashboard/dashboard.routes.js:25-37`, `app/javascript/dashboard/routes/dashboard/autonomia/autonomia.routes.js:38-66`).
- Existe manifest de assets do Vite em `public/vite/.vite/manifest.json` com 243 entradas e 85.662 bytes; `public/vite/.vite/manifest-assets.json` esta vazio (`{}`).
- Esse manifest de Vite ajuda a identificar assets/hashes, mas nao descreve "features UI", "rotas disponiveis", "permissoes" ou "componentes por modulo".

### Tamanho e busca de codigo

Contagens aproximadas no working dir, excluindo diretorios pesados/ignorados (`node_modules`, `vendor/bundle`, `tmp`, `log`, `storage`, `public/system`, `public/packs`, `.git`, `.pnpm-store`):

| Escopo | Arquivos | Linhas aprox. |
| --- | ---: | ---: |
| Total com `public/vite` | 9.745 | 2.382.247 |
| Total sem `public/vite` | 8.030 | 2.013.124 |
| `app` | 6.481 | 293.305 |
| `enterprise` | 433 | 17.718 |
| `config` | 192 | 101.522 |
| `db` | 232 | 22.395 |
| `lib` | 135 | 10.442 |
| `public` | 1.811 | 378.089 |
| `swagger` | 294 | 63.774 |
| `docs` | 36 | 12.915 |
| `spec` | 49 | 4.226 |

Tamanho local:

- working tree completo: 1,6 GB;
- arvore aproximada de build sem diretorios ignorados pesados: 984 MB;
- `public/vite`: 1.717 arquivos e 792 MB.

Risco de imagem: como `docker/custom/Dockerfile.crm:13` apaga `/app/public/vite` herdado e `docker/custom/Dockerfile.crm:15` faz `COPY . /app`, um `public/vite` local entra na imagem se existir no contexto. Isso e separado do pilar, mas afeta tamanho, tempo de busca e superficie de IP.

Sobre `ripgrep` em producao:

- O Dockerfile custom nao instala `ripgrep`.
- Nao consegui validar a imagem base porque o Docker daemon local negou acesso (`permission denied while trying to connect to the Docker daemon socket`).
- Portanto, `rg` dentro da imagem nao e garantido pelo fork.

Opcao recomendada: nao depender de `rg` runtime em producao. Criar no build um indice interno e read-only com paths allowlist, hashes e metadados. Para MVP interno, um indice textual simples por arquivo/rota/constante ja resolve mais que busca live no container. Para modo avancado, adicionar embeddings ou BM25 por simbolo/arquivo.

## O que um manifest por implantacao precisaria

| Item | Ja da para extrair hoje? | Falta para producao confiavel |
| --- | --- | --- |
| Versao Chatwoot/app | Sim: `config/app.yml`, `package.json`, `VERSION_CW`, `APP_VERSION` no globalConfig | Consolidar em JSON unico e Docker label |
| Commit implantado | Parcial: `.git_sha` + `GIT_HASH` + UI BuildInfo | Gerar `.git_sha` no build, excluir `.git`, validar SHA, gravar label OCI `org.opencontainers.image.revision` |
| Data/build id/imagem | Nao no codigo custom | Injetar build time, image digest/tag, pipeline id |
| Migrations presentes | Sim: arquivos `db/migrate` | Hash/lista no manifest de build |
| Migrations aplicadas | Sim via DB/console; UI so mostra pending/completed | Endpoint interno que retorna lista/hash de `schema_migrations` e diff contra imagem |
| Feature flags globais | Parcial: expostas em `DashboardController#app_config` | Snapshot interno com origem, valor efetivo e mascaramento |
| Feature flags por conta | Parcial: `autonomia_agents_enabled` em account payload | Manifest account-scoped para operador interno, com Pundit |
| Contratos de API | Parcial: Swagger upstream + rotas/wrappers custom | Atualizar OpenAPI para CRM/Autonomia/Campaigns ou gerar contrato custom no CI |
| UI registry | Parcial: Vue routes e Vite manifest | Registry declarativo de modulos, rotas, flags, permissoes e chunks |
| Hashes de assets/codigo | Parcial: Vite asset names e manifests | Hash de arquivos allowlist, manifest assinado/opcional |
| Busca de codigo | Sim no checkout de dev; incerto na imagem | Indice pre-construido no build; endpoint interno com redacao |
| Explicacao segura | Nao como produto | Politica de redacao: final-user vs interno/eng |

## Project Intelligence interno via Codex CLI

Hoje o modo interno ja cobre uma parte grande do pilar:

- Codex roda no checkout, usa `rg`, le arquivos reais e cruza backend/frontend/EE.
- Nao depende de producao ter Git checkout.
- Consegue responder perguntas como "por que o copiloto aparece?", "qual flag gateia isso?", "qual controller autoriza?", "qual model/servico cria tal comportamento?" com evidencia de paths e linhas.
- E adequado para suporte/engenharia quando a pergunta e sobre codigo esperado, regressao, PRD, diagnostico tecnico ou preparacao de deploy.

Limite importante: Codex no checkout nao prova estado live. Para provar producao, precisa do manifest da imagem implantada + estado runtime do banco/ENV. Sem isso, ha risco de analisar um checkout diferente do container rodando.

## Fronteira de IP e seguranca

Seguro para usuario final:

- explicar comportamento em termos de produto: "este recurso esta desativado para sua conta", "a conversa nao aparece porque voce nao tem permissao", "a importacao falhou por arquivo invalido";
- citar nomes de flags somente se forem parte do contrato operacional exposto;
- mostrar status, versao curta, horario de deploy, checks de saude;
- sugerir proximas acoes sem paths internos.

Somente interno/engenharia:

- paths de arquivo, linhas, nomes de classes, snippets de codigo, queries, diffs, stack traces completos;
- lista de routes/controllers/services;
- indice textual do repo;
- hashes de arquivos e comparacao de manifests;
- explicacoes que revelem logica proprietaria, prompts, heuristicas de IA ou regras internas.

Bloqueios recomendados:

- nunca expor `.git`, arquivos fonte ou indice de codigo em endpoints publicos/account-level normais;
- modo engenharia atras de super admin ou canal operacional separado;
- redacao de secrets e credenciais (`InstallationConfig`, ENV, hooks);
- logs do agente sem prompt completo quando houver codigo/credenciais.

## Riscos

1. **`.git` pode entrar na imagem**: `.dockerignore` nao exclui `.git`. Isso aumenta tamanho e vaza historico/IP se o contexto for um checkout real.
2. **`.git_sha` e manual/fragil**: existe no working dir, mas o Dockerfile nao gera nem valida.
3. **Schema dump desalinhado**: `db/schema.rb` esta em `2026_06_26_000001`, mas ha migration `20260627000001_add_actuation_to_autonomia_agents.rb` e o codigo usa `actuation`.
4. **Swagger nao cobre customizacoes**: 0 refs a Autonomia/CRM/Campaign custom no `swagger`.
5. **`public/vite` grande no contexto**: 792 MB e nao ignorado; pode inflar imagem e indice.
6. **Busca runtime nao garantida**: `ripgrep` nao e instalado pelo Dockerfile custom e Docker daemon local nao permitiu validar a base.
7. **Explicabilidade pode vazar IP**: um agente que "explica comportamento" com base em codigo precisa de separacao forte entre modo interno e final-user.

## Infra nova recomendada

MVP interno:

1. Gerar `/app/config/deploy_manifest.json` no build com `app_version`, `commit_sha`, `build_time`, `image_tag/digest`, `migration_files`, hashes allowlist e Vite manifest summary.
2. Adicionar labels OCI no Docker build: revision, version, source, created.
3. Atualizar `.dockerignore` para excluir `.git` e artefatos que nao devem entrar na imagem.
4. Endpoint interno/super-admin para manifest runtime: build manifest + `schema_migrations` hash/lista + flags globais mascaradas + health.
5. Indice de codigo build-time read-only, allowlist (`app`, `enterprise/app`, `config/routes.rb`, `db/migrate`, `lib`, `swagger`, `docs` selecionados), sem secrets, sem `.git`.
6. Politica de resposta: final-user nunca recebe codigo; eng-mode pode receber paths/linhas.

Depois:

1. Gerar OpenAPI custom para CRM/Autonomia/Campaigns.
2. Criar UI registry declarativo de modulos/rotas/flags/permissoes.
3. Hash comparativo entre manifest de build, assets Vite, migrations e rotas.
4. Opcional: embedding/BM25 do indice para perguntas em linguagem natural.

## Esforco estimado

- Commit/version confiavel no build (`.git_sha`, labels OCI, `.dockerignore`): **0,5-1,5 dia**.
- Manifest build + endpoint interno runtime com migrations/flags mascaradas: **3-5 dias**.
- Indice textual interno allowlist + busca segura: **4-7 dias**.
- Contratos custom API + UI registry minimo: **4-7 dias**.
- Politica de redacao, permissoes, auditoria e testes de vazamento: **3-5 dias**.

Total para piloto interno util: **2-3 semanas**.

Para expor parte disso a usuarios finais com seguranca, estimativa sobe para **4-6 semanas**, principalmente por redacao, UX, matriz de permissoes, testes de vazamento e governanca de prompts.

## Conclusao

O pilar e viavel, mas nao deve comecar como "agente de usuario final que le o projeto". O caminho correto e:

1. tornar o deploy comprovavel por manifest;
2. limitar Project Intelligence a modo interno/engenharia;
3. usar o agente para diagnostico operacional com evidencias internas;
4. expor ao usuario final apenas explicacoes sanitizadas e orientadas a acao.

Sem manifest, o agente pode ser inteligente sobre o repo, mas nao confiavel sobre a implantacao. Com manifest, "commit implantado" vira uma fonte de verdade objetiva e auditavel.
