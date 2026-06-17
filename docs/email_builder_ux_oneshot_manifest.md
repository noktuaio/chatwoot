# ONE-SHOT — Redesign UX do Email Builder (Ondas 1-5) — manifesto autoritativo

Data 2026-06-12. Repo `/root/docker-stacks/build/chatwoot-campaign-v4.14.1` (NAO git). Baseline/rollback: image `v4.14.1-20260612-builder` + backup `backups/chatwoot-src-pre-builder-ux-20260612.tar.gz` + DB dump `backups/chatwoot-db-pre-builder-20260612.dump`. App Chatwoot v4.14.1 EE, Vue3 `<script setup>`, Tailwind tokens `n-*` only, i18n en+pt_BR (paridade), components-next, i-lucide ESTATICO. Libs ja instaladas: grapesjs 0.23.2 + grapesjs-mjml 1.0.8 + mjml-browser 5.3.0.

## DECISOES TRAVADAS (PO) — nao reabrir
1. **GrapesJS HEADLESS + UI NOSSA.** `panels:{defaults:[]}` (mata toolbar cru), `blockManager:{custom:true}` -> evento `block:custom` -> NOSSO painel de blocos Vue (cards), `styleManager:{custom:true}` -> evento `style:custom` -> NOSSO painel de propriedades curado (Tamanho/Cor/Alinhamento/Espacamento, expandir depois). Canvas continua GrapesJS. Top bar nossa, "Criar com IA" = HEROI (primario destacado).
2. **FLUXO REORDENADO:** Etapa1 dialog = nome+dominio+remetente+reply_to+**upload da base** (REMOVER campo Corpo HTML). Etapa2 = tela "como criar" (Criar com IA HEROI / Escolher modelo / Do zero). Etapa3 = editor com placeholders REAIS da base ja carregados. Etapa4 = revisar+enviar. Placeholders dinamicos JA EXISTEM (`TemplateValidator.available`); so subir base antes.
3. **IA gpt-5.4 multimodal + ciente da base:** modelo gpt-5.4 (add `Crm::Ai::Config::MODEL_EMAIL='gpt-5.4'` ou usar MODEL_AUTO_MOVE). IA recebe briefing + placeholders da base + assets. Responses API: `input` vira ARRAY de content parts (input_text + input_image + input_file). PDF/imagem = contexto lido; imagem tb embutida.
4. **VIDEO = EMBUTIR, NAO LER.** Usuario descreve ("depoimento do cliente X") + da LINK (YouTube/Vimeo -> thumbnail via oEmbed) OU sobe arquivo (hospeda via ActiveStorage + gera 1 frame poster). IA POSICIONA um bloco de video (mj-image poster + overlay play + link) no lugar certo com a copy a partir da DESCRICAO (NAO assiste o video). Email-safe (sem <video>).
5. **GALERIA = PAGINA dedicada** (nao modal) com categorias/preview/import; MAXIMO de templates com alto nivel. Fontes MIT: Mailteorite/mjml-email-templates, mjmlio/email-templates, mjml.io/templates -> converter p/ nossos blocos + rodape travado (.footer-locked).

## Regras gerais (TODOS agentes)
- MVP happy-path, sem defensive demais, remover codigo morto que substituir.
- vue-i18n v9: `{ } @ |` especiais -> escapar (`{'{{ x }}'}`, `{'@'}`). NAO editar en/pt campaign.json|crm.json direto -> fragmentos `/tmp/uxshot/i18n/<pkg>.en.json`/`.pt.json` com `__target__`.
- Rotas: NAO editar config/routes.rb direto -> contract em `/tmp/uxshot/contracts/<pkg>.md`. Migracoes (se houver): timestamps reservados abaixo.
- Pundit policy top-level. Ruby rubocop 150col compacto. JS eslint Airbnb+Vue3; rodar eslint --fix nos seus arquivos.
- Reaproveitar o que existe (NAO recriar): assets_controller, ai_controller, template_tools_controller (placeholders/validate), EmailCampaignTemplate model, Sanitizer, PromptBuilder, GrapesEditor.vue (sera REESCRITO p/ headless), EmailBuilderPage.vue, EmailCampaignDialog/DetailsDialog.
- NAO rodar vite/migracao (fases proprias). NAO deploy.

## Fatos do codigo (verificados — nao redescobrir; scouts confirmam detalhes)
- IA: `Crm::Ai::CredentialResolver.new(account:).resolve` -> {api_key,api_base,source}|nil. `Crm::Ai::ResponsesClient#create(model:,instructions:,input:,schema:,reasoning_effort:)` POST `#{api_base}/v1/responses`; `input` hoje eh STRING -> mudar p/ aceitar array de parts. `Crm::Ai::Config` tem MODEL_AUTO_MOVE='gpt-5.4', MODEL_FOLLOWUP/SUMMARY/CLASSIFY='gpt-5.4-mini', VISION_MODEL.
- ai_controller: actions generate {brief, placeholders[]} e rewrite {text, instruction}; usa PromptBuilder + Sanitizer. assets_controller: upload image<=2MB -> builder_assets attach -> {url}. template_tools_controller: placeholders/validate. EmailCampaign tem body_mjml/body_html/preheader/from_email + has_many_attached :builder_assets. EmailCampaignRecipient.custom_data jsonb. EmailCampaignTemplate (account,name,body_mjml,body_html).
- FE: EmailBuilderPage.vue (rota campaigns_email_builder lazy em campaigns.routes.js) usa GrapesEditor.vue (components-next/.../EmailCampaign/builder/) que faz dynamic import grapesjs+grapesjs-mjml; blocks.js (registerAutonomiaBlocks) 10 blocos + footer-locked; starterTemplates.js/starterMjml.js; AiComposerDialog.vue + AiBlockActions.vue + PlaceholderChips.vue; api emailCampaignAi.js. Store emailCampaigns (sendTest/placeholders/validate). EmailCampaignDialog.vue (from_email+preheader+"Salvar e abrir editor"); EmailCampaignDetailsDialog.vue (upload base + placeholders chips + validate). Chart: shared/components/charts/{BarChart,LineChart}.vue (vue-chartjs).
- grapesjs-mjml: comandos `mjml-code`(string) e `mjml-code-to-html`({html,errors}); blocos via editor.Blocks.add; lock via attr css-class no model tree (NAO find('.classe')); devices set-device-desktop/mobile; css `import 'grapesjs/dist/css/grapes.min.css'`.
- Responses API multimodal: content parts input_text/input_image(image_url base64|url)/input_file(PDF base64|file_id|url); limite 100pag/32MB.

## Migracoes reservadas (so se necessario; provavelmente NENHUMA — reusar builder_assets)
- 20260612130001 (RESERVADO) — usar so se algum pkg precisar de coluna (ex.: email_campaign_templates +category/+thumbnail_url p/ galeria). Decidir na arquitetura.

## Pacotes & ownership (arquiteto refina as costuras, sobretudo FE editor)
### BE-A — IA multimodal + modelo + video-embed (backend)
ResponsesClient: aceitar `input` array de parts (back-compat: string vira [{type:input_text,text:}]). ai_controller#generate: aceitar `assets` (array {kind:image|pdf|video, url|signed, description, role}) + `placeholders`; montar input multimodal (image->input_image, pdf->input_file; video NAO vai pro LLM, vai como instrucao textual "EMBUTIR video: <desc> url:<url> poster:<poster>"); modelo gpt-5.4. PromptBuilder.generate: incluir catalogo de blocos + placeholders + manifest de assets + REGRA de video-embed (gerar bloco mj-image poster+link posicionado). Sanitizer: manter (garantir bloco video nao injeta script). Contract: rotas/permits.
### BE-B — Assets de video + galeria backend
NOVO `EmailCampaigns::VideoAsset` service: dado URL YouTube/Vimeo -> extrair id + thumbnail (oEmbed/img.youtube) ; dado arquivo de video (upload) -> hospedar (ActiveStorage) + gerar 1 frame poster (usar ffmpeg se disponivel no container; senao placeholder + TODO). Endpoint p/ resolver video {url|file} -> {video_url, poster_url, provider}. Galeria: templates_controller#index ja existe -> garantir payload leve (metadados) + endpoint de detalhe/body; seed task `lib/tasks/email_campaign_templates.rake` que importa N templates MJML curados (converter dos repos MIT — colocar os MJML em db/seeds ou um diretorio app) com category. EmailCampaignTemplate +category +thumbnail (migracao 20260612130001 SE preciso). Contract.
### BE-C — Fluxo/etapas backend (minimo)
Garantir placeholders endpoint robusto p/ campanha recem-criada (0 recipients -> defaults). Campos da campanha p/ etapas (reusar status draft). Sem migracao se possivel. Contract permits se faltar algo.
### FE-EDITOR (nucleo — arquiteto define contrato; pode virar 1 dono + sub-agentes)
GrapesEditor.vue REESCRITO headless: panels:[], blockManager.custom, styleManager.custom, expoe composable/bus (editorRef.getEditor + eventos block:custom/style:custom repassados). Top bar nova (IA heroi). Dono de campaigns.routes.js + store emailCampaigns.
### FE-BLOCKS — painel de blocos Vue (consome block:custom; cards arrastaveis; drag via dragStart/dragStop).
### FE-PROPS — painel de propriedades Vue curado (consome style:custom; controles Tamanho/Cor/Alinhamento/Espacamento via Style Manager API sm.getSectors).
### FE-FLOW — Etapa1 dialog (remover Corpo HTML; mover upload base p/ ca) + Etapa2 "como criar" (welcome) + roteamento. EmailCampaignDialog/Details/EmailCampaignsPage.
### FE-AI — AiComposerDialog redesenhado: briefing + UPLOAD de assets (imagem/pdf via assets_controller; video por LINK ou upload via BE-B) com rotulo de uso + lista dos placeholders da base; manda assets[] pro generate. AiBlockActions (manter, garantir montado).
### FE-GALLERY — pagina de modelos (rota nova lazy) grid+categorias+preview+"usar modelo" (import setMjml na campanha). api templates.

## Fase Integracao / TestBed / Visual / Reviews / Fix / Final
- Integracao: aplicar contracts (rotas/permits/i18n merge/seed), reconciliar costuras FE-EDITOR<->FE-BLOCKS/FE-PROPS/FE-AI/FE-GALLERY, gates mecanicos (ruby -c, eslint, paridade i18n campaign+crm).
- TestBed REAL: vite build -> image uxshot-test -> pgvector pg15 isolado (prod intocado) -> migracoes (se houver) -> seed (account+admin+identity verified hub2you.ai+campanha+base REAL com colunas nome/empresa/veiculo/cidade/valor) -> app 3344 -> smokes: a) placeholders da base aparecem; b) ai generate multimodal (mock/real se credencial) retorna mjml com bloco; c) video-embed: VideoAsset resolve URL youtube -> poster; d) gallery seed importa templates + import setMjml; e) sanitizer; f) ENVIO SES REAL p/ atendimento@hub2you.ai com placeholder; g) eager_load. DEIXAR de pe p/ visual.
- Visual Playwright (172.17.0.1:3344): fluxo etapa1(base)->etapa2(IA heroi)->editor (UI nossa: blocos Vue, propriedades curadas, SEM style manager cru, top bar IA destaque), arrastar bloco, placeholders reais, Criar-com-IA dialog com upload de assets+video, galeria de modelos, salvar. zero-regressao campanhas antigas. screenshots /tmp/uxshot/shots.
- 6-7 reviews adversariais (seguranca assets/video URL SSRF, IA injection, FE qualidade headless/leaks, zero-regressao, deliverability MJML video block, migracao). Fix-loop. GO/NO-GO -> /tmp/uxshot/final_report.md. NAO DEPLOY.

Dirs de trabalho: /tmp/uxshot/{facts,contracts,i18n,shots}.
