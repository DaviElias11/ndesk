# NewByte NDesk - Workflow e Instrucoes para Sessoes Claude

## Branch e PR

- **Branch de producao**: `newbyte-stable` (NÃO é `main` nem `master`)
- Commit livre é permitido (liberado pelo CTO) — não é obrigatório passar por PR **por commit**
- **Mas SEMPRE na branch da feature — commit/push direto na `newbyte-stable` é PROIBIDO**
- **Push também é livre na branch da feature** — push NÃO abre PR; PR é sempre uma ação
  explícita e separada (confirmado pelo CTO em 2026-07-16)
- **A PR só deve ser aberta no final, quando o usuário pedir explicitamente**
- Criar branch com prefixo descritivo: `feat/`, `fix/`, `chore/`
- A PR (quando pedida) é aberta contra `newbyte-stable`
- Se o `gh pr create` falhar via GraphQL, usar a API REST:
  ```
  gh api repos/newbytesolucoesdigitais/ndesk/pulls \
    -f title="..." \
    -f head="newbytesolucoesdigitais:<branch>" \
    -f base="newbyte-stable" \
    -f body="..."
  ```

## Merge e Tags

- Toda merge em `newbyte-stable` DEVE ser acompanhada de uma tag
- Formato da tag: `nb.v{major}.{minor}` (ex: `nb.v1.3`)
- A tag mais recente ate esta sessao: `nb.v1.6`
- Fluxo de merge:
  ```bash
  # 1. Merge via API
  gh api repos/newbytesolucoesdigitais/ndesk/pulls/<PR_NUMBER>/merge \
    -X PUT -f merge_method=merge

  # 2. Fetch, criar tag no commit de merge e push
  git fetch origin newbyte-stable
  git tag nb.v<NEXT_VERSION> origin/newbyte-stable
  git push origin nb.v<NEXT_VERSION>
  ```
- Perguntar ao usuario qual sera a proxima versao da tag antes de criar

## Deploy (Coolify)

- O deploy e trigado automaticamente por push na branch configurada no Coolify
- Se o webhook nao disparar, fazer um commit vazio para re-triggar:
  ```bash
  git commit --allow-empty -m "chore: trigger deploy" && git push
  ```
- O build roda `assets:precompile` (Sprockets) - erros de CSS/CoffeeScript quebram o deploy

## Arquivos que NAO devem entrar na PR

Estes arquivos existem no workspace mas nao devem ser commitados:

- `.devcontainer/default/devcontainer-lock.json` - arquivo gerado pelo devcontainer
- `design-system-web.md` - documento de referencia de design, nao e codigo
- `logoblue.svg` - SVG fonte usado como referencia, ja incorporado no `icons.svg`
- Qualquer arquivo `.env`, credenciais ou secrets
- Arquivos temporarios ou de debug

## Restricoes de Git

- **NUNCA** fazer operacoes destrutivas (pull, reset --hard, push --force, checkout --) sem aprovacao explicita do usuario
- **NUNCA** commitar ou fazer push direto na `newbyte-stable` — trabalho sempre na branch da feature
- Preferir commits novos a amend

## Frontend — SOMENTE o app legacy

- **Todo trabalho de UI é no app legacy** (`app/assets/javascripts` e `app/assets/stylesheets`) — CoffeeScript/Spine.js, servido na raiz `/`.
- **NUNCA trabalhar nos apps Vue** (`app/frontend/apps/desktop` e `app/frontend/apps/mobile`). Eles são código oficial do upstream Zammad (a migração do desktop pra Vue, servida em `/desktop` e `/mobile`) e o NDesk **não** os usa nem customiza.
- Ignorar as mencoes aos apps Vue no `AGENTS.md` / CLAUDE.md — sao boilerplate herdado do upstream.

## Compatibilidade de Browser

- Testar considerando Chrome, Firefox e Safari
- Safari nao suporta `audio/webm` - usar `audio/mp4` como fallback
- Safari nao resolve `url(#id)` dentro de `<symbol>/<use>` no SVG (shadow DOM) - usar `fill` inline direto, sem `clipPath`, `<style>`, ou `linearGradient` dentro de symbols
- Firefox retorna `duration = Infinity` para blobs WebM - usar `isFinite()` guard

## Servidor de Desenvolvimento

- Para rodar local: verificar se o `Procfile.dev` esta configurado
- O CSS usa variaveis customizadas com `:root` (light) e `[data-theme='dark']` (dark)
- O mixin `@include dark { }` aplica estilos so no dark mode

---

## Changelog

> **Instrucao para sessoes futuras**: Ao finalizar uma sessao com alteracoes de codigo,
> adicionar uma entrada abaixo com a data, resumo das mudancas e branch/PR/tag.
> Isso mantem um historico legivel do que foi feito no projeto.

### 2026-05-27 - PR #16 (tag nb.v1.3)

**Branch**: `feat/audio-firefox-fix`

Alteracoes:
- **Fix Firefox audio**: Player de preview mostrava `0:00 / Infinity:NaN` porque blobs WebM retornam `duration = Infinity`. Adicionado guard `isFinite()` com fallback para duracao gravada.
- **Fix Safari audio**: Safari nao suporta `audio/webm`. Adicionado `audio/mp4` na cadeia de deteccao do `MediaRecorder`, com extensao `.m4a` no upload.
- **Fix Safari SVG**: Logos usavam `clipPath`, `<style>` e `linearGradient` dentro de `<symbol>` que nao funcionam no Safari via `<use>`. Substituidas por paths simples com `fill` inline.
- **Compose sticky**: Barra de composicao flutua no fundo da tela ao scrollar pra cima, com efeito frosted glass (`backdrop-filter: blur`).
- **Toggle minimize**: Botao para ocultar/mostrar compose. Bloqueado quando perto do fundo (200px). Auto-reopen ao scrollar de volta ao fundo. Fallback de reopen apos colapsar se ficou no fundo.
- **Sidebar clara (light mode)**: Menu lateral com tons claros no tema branco, dark mode inalterado com override explicito das variaveis `--menu-*`.
- **Logo azul (light mode)**: Logo New Byte azul (`#0077FF`) no light mode, branca no dark mode. Toggle via CSS `display` + `@include dark`.

Arquivos modificados:
- `app/assets/javascripts/app/controllers/article_view/item.coffee`
- `app/assets/javascripts/app/controllers/ticket_zoom/article_new.coffee`
- `app/assets/javascripts/app/views/navigation.jst.eco`
- `app/assets/javascripts/app/views/ticket_zoom/article_new.jst.eco`
- `app/assets/stylesheets/zammad.scss`
- `public/assets/images/icons.svg`

### 2026-07-06 - PR #<n> (tag nb.v<x>)

**Branch**: `feat/csat-two-scores`

Alteracoes:
- **CSAT em duas dimensões**: nota única vira Nota de Atendimento (`score` renomeado
  para `score_service`, ADR 0003) + nova Nota de Resolução (`score_resolution`, NULL
  nas avaliações antigas). Popup com duas fileiras de estrelas (resolução primeiro),
  ambas obrigatórias. POST/surveys/stats/embed do ticket expõem o par; stats com
  bloco por dimensão (médias ignoram NULL; `count_resolution` por atendente).
  Sem alias para o param antigo `score`.

### 2026-07-17 - branch feat/ticket-grouping

**Branch**: `feat/ticket-grouping`

Alteracoes:
- **Coleções de abas na taskbar**: o atendente organiza as Abas da taskbar (sidebar
  esquerda da UI clássica) em Coleções nomeadas via drag & drop, persistidas em
  `user.preferences` (`taskbar_collections`). Zero backend novo — save por
  `PUT /api/v1/users/preferences` (merge por chave), ordem via `prio` da taskbar.
  - **Módulo `App.TaskbarCollections`** (`lib/app_post/taskbar_collections.coffee`):
    dono único do documento (id/nome/collapsed/keys), filiação única de cada Aba,
    persistência debounced (nível `task`, cancelada no logout), reconciliação de keys
    órfãs (guard contra `reconcile(undefined)`), nome padrão traduzido ("Coleção N").
  - **Auto-limpeza**: `TaskManager.tasksAutoCleanup` pula Abas que estão em Coleção.
  - **Widget em dois níveis** (`controllers/taskbar_widget.coffee`): Abas soltas na
    raiz + container por Coleção (cabeçalho, contador, membros); recolher/expandir;
    auto-expand ao ativar membro (só em transição real de ativação).
  - **Menu ⋯**: renomear inline (Enter/Esc/blur), desfazer Coleção, fechar todas
    (modal única quando há rascunho não salvo).
  - **Drag & drop** (jQuery UI sortable em dois níveis): miolo (~60%) cria/adiciona à
    Coleção, bordas reordenam; cabeçalho recolhido expande no drop; guard contra
    aninhamento ilegal de Coleção; ordem achatada em `TaskManager.reorder`.
    `tolerance: 'intersect'` (não `'pointer'`): sem isso o rearrange do sortable
    disparava na borda e o alvo "fugia" do ponteiro antes do miolo — o gesto de criar
    grupo virava reordenação (corrigido no QA da PR).
  - **F5/relogin (item 7 do QA)**: Coleções, nomes, ordem e recolhimento sobrevivem;
    a Aba restaurada como ativa não reabre Coleção recolhida (bootActiveKeys) e o
    render em dois níveis não sai achatado no boot.
  - **Estilos** (`zammad.scss`, variáveis `--menu-*`, light/dark) e **i18n pt-BR**.
  - Docs de domínio: `docs/taskbar/CONTEXT.md`, ADR `docs/taskbar/adr/0001-*`,
    spec e plano em `docs/superpowers/`.

Arquivos modificados:
- `app/assets/javascripts/app/lib/app_post/taskbar_collections.coffee` (novo)
- `app/assets/javascripts/app/views/widget/task_collection.jst.eco` (novo)
- `app/assets/javascripts/app/controllers/taskbar_widget.coffee`
- `app/assets/javascripts/app/lib/app_post/task_manager/singleton.coffee`
- `app/assets/stylesheets/zammad.scss`
- `i18n/zammad.pt-br.po`
- `public/assets/tests/qunit/taskbar_collections.js` (novo)

### 2026-09-08 - branch chore/rails-8.1-upgrade (NDESK-45)

**Branch**: `chore/rails-8.1-upgrade`

Alteracoes:

- **Rails 8.0.4 → 8.1.3.1 e Brakeman 8.0.6**: o check Security Scan falhava por EOLRails
  (Brakeman 8.0.2 marcava a serie 8.0 como EOL em 2026-10-07). Lock: Rails e 12 componentes,
  `action_text-trix` entra, `benchmark` sai, rack fica em 2.2.22.
- **`config.load_defaults 8.1`**: sete ajustes com um teste cada (`spec/config/framework_defaults_spec.rb`):
  yjit so em producao, JSON sem escape de HTML/U+2028/U+2029, redirect relativo levanta erro, finders
  sem ordem em model sem chave levantam erro, render_tracker `:ruby`, hidden fields sem autocomplete.
- **Guard de somente-leitura em `lock!`** replicado no patch `active_record_lock_issue_3664.rb`.
- **`allow_other_host`** passado de fato no callback de credenciais externas.
- **`dump_schema_after_migration = false`** em `config/environments/test.rb` e `development.rb`: o
  dumper de schema do Rails 8.1 passou a ordenar as colunas em ordem alfabetica; como o `db:migrate`
  do `zammad:db:reset` carrega o `db/schema.rb` quando ele existe, em vez de rodar as migrations, o
  banco de teste ficava com `column_names` fora da ordem de criacao. Com o dump desligado nesses dois
  ambientes, o banco de teste passa a ser construido por migrations e o `db/schema.rb` continua ausente
  e gitignored. Depois de fazer checkout desta branch, rode `rm -f db/schema.rb`: um dump residual
  (de um checkout anterior que rodou `db:migrate` com o dump ligado) continua sendo carregado pelo
  `zammad:db:reset`/`zammad:db:init` via `DatabaseTasks.initialize_database` e reproduz em silencio a
  ordem alfabetica. O `zammad:bootstrap:reset` (`lib/tasks/zammad/bootstrap/reset.rake:14`) ainda grava
  um `db/schema.rb` vazio logo apos o truncate, o que e inofensivo.
- **Specs de migration instanciam a classe viva** (`spec/support/db_migration.rb`): sem `db/schema.rb`
  o `zammad:db:reset` do `before(:suite)` roda as migrations dentro do processo do RSpec e o
  `MigrationProxy` troca cada classe, deixando o `described_class` do arquivo de spec obsoleto.
- **`benchmark` declarada de volta no `Gemfile`**: a `activesupport` 8.1 deixou de depender de
  `benchmark` (por isso a gem saiu do lock, bullet acima), mas `delayed_job` (`lib/delayed/worker.rb:10`)
  faz `require 'benchmark'` e `lib/background_services/service/base_delayed_jobs.rb:36` chama
  `Benchmark.realtime` sem dar require, o que em todo boot (RSpec, Minitest e o worker do `delayed_job`
  em producao) imprimia o aviso de que `benchmark` deixara de ser gem padrao a partir do Ruby 4.0.0.
  Este commit declara `gem 'benchmark'` no `Gemfile` (lock resolve para `0.5.0`) e o warning de boot
  desaparece.
- **Throttle do rack-attack lia os parametros do Rack, nao os do Rails** (achado D20 do QA da PR #26): o
  discriminador do rate limit usava `req.params` do Rack 2.2, que ainda separa a query string em `;`,
  enquanto o controller le `params` do ActionDispatch 8.1, que nao separa mais (`SEMICOLON_COMPAT` removido).
  Um `&x=1;username=lixoN` trocava a chave do throttle a cada requisicao e derrubava o limite por usuario em
  `password_reset`, `email_verify_send` e `admin_password_auth`. O campo passa a ser lido via
  `ActionDispatch::Request` sobre o `env` (query string e corpo, JSON incluido), o que tambem corrige a chave
  vazia `""` que todo POST JSON compartilhava. Specs nos tres endpoints.
- Spec e plano: `docs/plans/2026-09-08-atualizar-rails-design.md`, `docs/plans/2026-09-08-atualizar-rails.md`.

Arquivos modificados:

- Config: `Gemfile`, `Gemfile.lock`, `config/application.rb`, `config/brakeman.ignore`,
  `config/environments/development.rb`, `config/environments/test.rb`,
  `config/initializers/active_record_lock_issue_3664.rb`, `config/initializers/rack_attack.rb`
- App: `app/controllers/external_credentials_controller.rb`
- Specs novos: `spec/config/framework_defaults_spec.rb`,
  `spec/controllers/framework_defaults_redirect_spec.rb`, `spec/lib/sessions/store_roundtrip_spec.rb`,
  `spec/requests/framework_defaults_json_spec.rb`, `spec/requests/framework_query_string_spec.rb`
- Specs modificados: `spec/lib/active_record/locking/pessimistic_spec.rb`,
  `spec/models/ticket/satisfaction_rating_spec.rb`, `spec/requests/external_credentials_spec.rb`,
  `spec/requests/knowledge_base_public/custom_path_spec.rb`, `spec/support/db_migration.rb`,
  `spec/requests/user/password_reset_spec.rb`, `spec/requests/user/email_verify_send_spec.rb`,
  `spec/requests/user/admin_password_auth_spec.rb`

### 2026-09-16 - branch feat/nchat-embed-frame-ancestors (NDESK-60)

**Branch**: `feat/nchat-embed-frame-ancestors`

Alteracoes:

- **Embed do NDesk nos Aplicativos do NChat**: a CSP global declara
  `frame-ancestors 'self' https://chat.newbyte.net.br https://nchat.newbyte.net.br`; o
  `X-Frame-Options: SAMEORIGIN` do Rails sai dos headers padrão (logo após `load_defaults 8.1`, que
  substitui o hash inteiro); a política de download de anexos passa a
  `default-src 'none'; frame-ancestors 'self'`. Nenhuma outra diretiva muda. Contrato e limitações do
  lado do NChat (`allow=` no iframe, credenciais na URL do `chat` antigo, auth só por senha/TOTP no
  embed) na ADR `docs/adr/0001-nchat-embed-frame-ancestors.md`; follow-up no NChat: NCHATV4-271.
- **Hook de assets das specs**: `spec/support/compile_assets.rb` recarrega o manifesto do Sprockets depois de
  `assets:precompile`. Num processo de CI (checkout sem manifesto no boot) toda página Sprockets devolvia 500
  (`Sprockets::Rails::Helper::AssetNotFound`) e nenhuma spec verificava o status da raiz até a spec de
  `frame-ancestors`.

Arquivos modificados:

- `config/initializers/content_security_policy.rb`
- `config/application.rb`
- `app/controllers/application_controller/has_download.rb`
- `spec/requests/frame_ancestors_spec.rb` (novo)
- `spec/requests/ticket/article_attachments_spec.rb`
- `spec/support/compile_assets.rb`
- `docs/adr/0001-nchat-embed-frame-ancestors.md` (novo)
- `docs/plans/2026-09-16-nchat-embed-frame-ancestors-design.md` e
  `docs/plans/2026-09-16-nchat-embed-frame-ancestors.md` (novos)

### 2026-10-31 - branch feat/ticket-distribution (NDESK-70)

**Branch**: `feat/ticket-distribution`

Alteracoes:

- **Distribuição de atendimentos N1/N2 no NDesk**: o NDesk passa a decidir o dono do ticket. Ticket novo vai
  para o N1; a macro de análise prévia repassa ao N2 de menor carga (empate vai para quem está há mais tempo
  sem receber); a reabertura pelo cliente volta para quem atendeu (ou outro N2 se ele estiver desligado). A
  carga é calculada na hora (soma dos pontos dos tickets abertos), com pesos por complexidade, estados e
  prioridades que não pesam, e grupo/responsável de Disparos. Ver `docs/distribuicao/CONTEXT.md` e as ADRs
  em `docs/distribuicao/adr/`.
- **Escala**: tabela `ticket_distribution_members` (modelo `Ticket::DistributionMember`, níveis `n1` e `n2`),
  Setting `ticket_distribution`, permissão `admin.ticket_distribution` e atributo de usuário `discord_uid`
  (ID do Discord, só dígitos), incluído no payload do webhook em `owner.discord_uid`. A escala acompanha a
  exclusão do usuário.
- **Ação de `perform_changes`** `distribution.ticket_distribution` (modos `entry`, `handover`, `reopening`),
  na fase `before_save`, com trava (linhas do ticket por `id` crescente, depois advisory lock) e avisos.
  Disponível no editor de macros e triggers, com o validador de `perform` ajustado.
- **Recusa sem complexidade**: macro com a ação, aplicada a ticket sem complexidade, é recusada antes de
  gravar (individual e em lote), com aviso fixo até ser fechado. Repasse não realizado grava nota interna do
  Sistema e envia sino (`distribution_not_handed_over`) a quem aplicou, sem mudar o dono.
- **Tela** `#manage/ticket_distribution` (admin clássico, CoffeeScript/Spine) e API REST
  `/api/v1/ticket_distribution`: escala, carga de cada N2 e alertas.
- **Triggers criados desligados**: `Distribuição — Entrada` e `Distribuição — Reabertura` nascem desligados
  (migration e seeds). **A virada é manual (Task 12)**: depois do merge e do deploy, alguém com acesso ao n8n
  liga os dois triggers e tira a atribuição do n8n. O código implantado não muda nada até lá.
- Migrations: `20261028000001_create_ticket_distribution_members` e `20261028000002_add_ticket_distribution_setup`.
- Catálogo de i18n regenerado; tradução pt-br em `i18n/zammad.pt-br.po`.

Arquivos novos:

- Modelos: `app/models/ticket/distribution_member.rb`, `app/models/user/ticket_distribution_membership.rb`,
  `app/models/ticket/distribution/{complexity_missing_error,config,decision,eligibility,load,lock,macro_guard,notice,overview,picker,rotation}.rb`,
  `app/models/ticket/perform_changes/action/ticket_distribution.rb`
- Controller, policy e rota: `app/controllers/ticket_distribution_controller.rb`,
  `app/policies/controllers/ticket_distribution_controller_policy.rb`, `config/routes/ticket_distribution.rb`
- Migrations: `db/migrate/20261028000001_create_ticket_distribution_members.rb`,
  `db/migrate/20261028000002_add_ticket_distribution_setup.rb`
- Frontend clássico: `app/assets/javascripts/app/controllers/ticket_distribution.coffee`,
  `app/assets/javascripts/app/views/ticket_distribution/{add_member,index,problems,weights}.jst.eco`
- Docs: `docs/distribuicao/CONTEXT.md`, `docs/distribuicao/adr/0001` a `0004`,
  `docs/pesquisas/pesquisa-load-balancer-atendimento.md`,
  `docs/plans/2026-10-20-distribuicao-atendimentos.md` e `...-design.md`, `.newbyte/handoffs/NDESK-70.md`
- Specs novos: `spec/models/ticket/distribution/*_spec.rb`, `spec/models/ticket/distribution_member_spec.rb`,
  `spec/models/ticket/perform_changes/action/ticket_distribution_spec.rb`,
  `spec/models/user/ticket_distribution_membership_spec.rb`, `spec/requests/ticket_distribution_spec.rb`,
  `spec/requests/ticket_distribution_macro_spec.rb`, `spec/system/manage/ticket_distribution_spec.rb`,
  `spec/system/ticket/zoom/distribution_refusal_spec.rb`, `spec/db/seeds/ticket_distribution_spec.rb`,
  `spec/db/migrate/add_ticket_distribution_setup_spec.rb`, `spec/factories/ticket/distribution_member.rb`,
  `spec/support/ticket_distribution.rb`

Arquivos modificados:

- App: `app/controllers/tickets_mass_controller.rb`, `app/models/ticket/perform_changes.rb`,
  `app/models/user.rb`, `lib/validations/verify_perform_rules_validator.rb`
- Seeds: `db/seeds/object_manager_attributes.rb`, `db/seeds/permissions.rb`, `db/seeds/settings.rb`,
  `db/seeds/triggers.rb`
- Frontend clássico: `app/assets/javascripts/app/controllers/_plugin/notify.coffee`,
  `app/assets/javascripts/app/controllers/_ui_element/_application_action.coffee`,
  `app/assets/javascripts/app/controllers/ticket_zoom.coffee`,
  `app/assets/javascripts/app/lib/mixins/ticket_mass_updatable.coffee`,
  `app/assets/javascripts/app/models/{macro,ticket,trigger}.coffee`, `app/assets/stylesheets/zammad.scss`
- i18n: `i18n/zammad.pot`, `i18n/zammad.pt-br.po`
- QUnit: `public/assets/tests/qunit/form_ticket_perform_action.js`, `public/assets/tests/qunit/ticket_macro.js`
- Specs modificados: `spec/graphql/gql/mutations/ticket/update_spec.rb`,
  `spec/jobs/trigger_webhook_job/record_payload/ticket_spec.rb`,
  `spec/lib/validations/verify_perform_rules_validator_spec.rb`, `spec/models/system_report_spec.rb`,
  `spec/models/user_spec.rb`
