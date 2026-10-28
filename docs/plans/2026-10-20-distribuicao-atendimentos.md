# Plano — Distribuição de atendimentos N1/N2 (NDESK-70)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended)
> or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`)
> syntax for tracking.

**Goal:** O NDesk passa a decidir o dono de cada ticket: todo ticket novo vai para o N1, a macro de análise
prévia repassa ao N2 de menor carga, a reabertura pelo cliente volta para quem atendeu, e uma tela do admin
clássico mantém a escala e mostra a carga.

**Architecture:** Uma ação nova de `perform_changes` (`distribution.ticket_distribution`, modos `entry`,
`handover` e `reopening`) roda na fase `before_save`, depois das outras ações do mesmo `perform`, e grava o
dono no mesmo save. A regra fica em POROs de `app/models/ticket/distribution/` (configuração, elegibilidade,
carga, rodízio, escolha, trava e avisos), sem estado além da tabela `ticket_distribution_members` e de um
Setting. A tela é um `App.ControllerSubContent` que fala com uma API REST própria. O n8n deixa de atribuir
num passo manual da virada.

**Tech Stack:** Ruby 3.4.8, Rails 8.1.3.1, PostgreSQL (advisory lock), RSpec, CoffeeScript/Spine/Eco
(admin clássico), QUnit, Capybara (system specs).

**Spec:** `docs/plans/2026-10-20-distribuicao-atendimentos-design.md` (v2, aprovado em 2026-10-28). O plano
argumenta a partir dele; quem executa lê os dois. Glossário: `docs/distribuicao/CONTEXT.md`.

## Restrições globais

- **Só o admin clássico** (`app/assets/`). Nunca tocar `app/frontend/` (`.claude/NEWBYTE_WORKFLOW.md`).
- **Nomes fixos** (usados por várias tarefas):
  - chave do `perform`: `distribution.ticket_distribution`, valor `{ 'value' => 'entry' | 'handover' | 'reopening' }`;
  - classe da ação: `Ticket::PerformChanges::Action::TicketDistribution` (lookup `:ticket_distribution`);
  - tabela `ticket_distribution_members`, modelo `Ticket::DistributionMember`, níveis `n1` e `n2`;
  - Setting `ticket_distribution` (um hash), área `Ticket::Distribution`, `frontend: false`;
  - permissão `admin.ticket_distribution`;
  - atributo de usuário `discord_uid` (string, até 30 caracteres, só dígitos);
  - tipo de `OnlineNotification`: `distribution_not_handed_over`;
  - entidade do erro de recusa: `ticket_distribution.complexity_missing`;
  - triggers: `Distribuição — Entrada` e `Distribuição — Reabertura` (travessão U+2014), criados desligados;
  - rota da tela: `#manage/ticket_distribution`; API em `/api/v1/ticket_distribution`.
- **Padrão do Setting** (spec §4): `complexity_attribute: 'complexidades'`,
  `weights: { 'facil' => 1, 'moderado' => 3, 'complexo' => 6 }`, `ignored_state_ids: []`,
  `ignored_priority_ids: []`, `dispatch_group_id: nil`, `dispatch_user_id: nil`. Nenhum outro dado de
  produção no código.
- **"Aberto"** = estado cuja categoria não é `closed`, `merged` nem `removed` (spec §5.5).
- **Filtro de dono** (spec §5.1) = o mesmo de `Ticket#check_owner_active` (`app/models/ticket.rb:755`):
  ativo, `ticket.agent` e acesso `full` ao grupo.
- **Ordem das travas** (spec §5.6): primeiro as linhas de ticket (em lote, por `id` crescente), por último o
  advisory lock `pg_advisory_xact_lock`. Nunca o inverso.
- **Strings:** fonte em inglês com `__()`, tradução em `i18n/zammad.pt-br.po`; o catálogo é regenerado com
  `rails generate zammad:translation_catalog` (Task 10). Textos gravados no banco (notas) passam por
  `Translation.translate(Setting.get('locale_default') || 'en-us', ...)`.
- Arquivos Ruby novos começam com `# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/`.
  Migrations em `ActiveRecord::Migration[8.1]`.
- **Testes:** antes de qualquer RSpec, `rm -f db/schema.rb`. Todo RSpec roda com as tags do CI:
  `bundle exec rspec --tag '~searchindex' --tag '~integration' --tag '~required_envs' <arquivos>` (abaixo,
  "RSpec CI"). Specs que criam o atributo `complexidades` levam `db_strategy: :reset`.
- **Lint:** `bundle exec rubocop <arquivos .rb tocados>` sem offenses; CoffeeScript com
  `coffeelint --rules ./.dev/coffeelint/rules/* <arquivos>` quando o binário existir no ambiente.
- **Git:** commits na `feat/ticket-distribution`, mensagem `tipo(escopo): resumo (NDESK-70)` em português,
  trailer de atribuição conforme a instrução vigente da sessão que executa. Nunca reescrever histórico. Não
  commitar `.superpowers/` nem `.newbyte/qa/`. A PR só é aberta quando o usuário pedir (`dev-execution`).
  Antes do push, confirme que a conta tem escrita em `newbytesolucoesdigitais/ndesk` (`gh api
  repos/newbytesolucoesdigitais/ndesk --jq .permissions.push`); se for `false`, a PR sai de um fork ou espera a
  permissão.
- **QA é de outra pessoa:** ela chega só com a PR. O "Como testar" do corpo da PR é a seção "Roteiro de QA"
  deste plano, completa (Task 11, Step 3).

## Ajustes em relação ao spec

O spec deixa estes pontos com o builder ou cita o arquivo errado. O plano decide assim:

1. **Editor de ações:** macros e triggers usam `tag: 'ticket_perform_action'`, que herda
   `App.UiElement.ApplicationAction` (`_ui_element/_application_action.coffee`). O
   `object_perform_action.coffee` citado no spec §6.1 é o editor dos Jobs e não muda.
2. **Roteamento do prefixo:** pelo gancho que o `Ticket` já tem para isso,
   `Ticket::PerformChanges#additional_object_action` (hoje só `article.note`), e não pela lista genérica
   `action_checks` de `CanPerformChanges`.
3. **A ação roda por último no `before_save`:** `Ticket::PerformChanges` sobrescreve `execute_before_save`
   para executar a distribuição depois das outras ações (por exemplo, `ticket.group_id` da mesma macro em lote).
   Sem isso, a ordem dependeria da ordem das chaves no hash.
4. **Trava:** linha do ticket (`SELECT … FOR UPDATE`, sem recarregar o registro) e depois
   `pg_advisory_xact_lock` com chave fixa. A macro em lote trava todas as linhas por `id` antes de começar e
   decide com os tickets recarregados por essa trava.
5. **Reabertura pelo usuário Sistema (id 1) não conta como do cliente.**
6. **"Tickets que pesam"** na tela = tickets abertos de peso maior que zero.
7. **Os dois triggers nascem desligados pela migração** (instalações existentes, guarda `system_init_done`)
   **e pelos seeds** (instalação nova, banco de teste e preview da PR, que é uma instalação nova). As specs que
   precisam deles ligam os triggers semeados (`Trigger.find_by(name: …).update!(active: true)`), e não criam
   outros com o mesmo nome.
8. **O modo da ação é validado** em `Validations::VerifyPerformRulesValidator`, além da presença do valor.
9. **Trigger nunca derruba a importação:** no caminho de trigger, trava e decisão rodam num savepoint
   (`transaction(requires_new: true)`). Deadlock ou timeout de trava viram log de erro sem distribuição.
10. **Duas notas ao mesmo tempo:** na reabertura sem N2 e sem N1, entram a nota de "não repassado" e a de
    "sem N1". O dono fica 1 e ninguém recebe sino.
11. **A escala não aparece no JSON de usuário:** `association_attributes_ignored :ticket_distribution_members`.
    Só a API da tela mexe na escala.
12. **Atributo `discord_uid`** (spec v2.1): o nome técnico não termina em `_id`.

## Review Focus

Entradas e falhas que o spec implica e que nenhum teste "óbvio" pegaria. Cada linha tem teste na tarefa dona.

1. **Valor de complexidade sem peso** (opção nova no atributo): pesa 0 e gera um único log por decisão, não um
   por ticket (Task 4).
2. **Agente no N1 e no N2 ao mesmo tempo** aplica a macro num ticket dele: é "quem repassa" e fica de fora;
   se for o único N2, o repasse não é realizado (Task 5).
3. **Grupo em que nenhum N2 tem acesso `full`:** "Repasse não realizado" com nota e sino, nunca erro nem dono
   zerado pelo `check_owner_active` (Task 5).
4. **Macro em lote com a ação antes de `ticket.group_id` no hash:** a decisão usa o grupo novo (Task 6).
5. **Atributo de complexidade configurado deixa de existir:** a macro é recusada com a mensagem normal (sem
   500) e a tela mostra um alerta de configuração (Tasks 2, 4 e 8).

## Arquivos

| Ação | Arquivo | Responsabilidade |
|------|---------|------------------|
| Criar | `db/migrate/20261028000001_create_ticket_distribution_members.rb` | tabela e coluna `users.discord_uid` |
| Criar | `db/migrate/20261028000002_add_ticket_distribution_setup.rb` | permissão, Setting, metadado do `discord_uid`, triggers (instalações existentes) |
| Modificar | `db/seeds/permissions.rb`, `db/seeds/settings.rb`, `db/seeds/object_manager_attributes.rb`, `db/seeds/triggers.rb` | o mesmo para instalações novas, testes e preview |
| Criar | `app/models/ticket/distribution_member.rb` | escala (N1/N2, Interruptor, Último repasse) |
| Criar | `app/models/ticket/distribution/{config,eligibility,load,rotation,decision,picker,lock,notice,macro_guard,overview,complexity_missing_error}.rb` | a regra |
| Criar | `app/models/ticket/perform_changes/action/ticket_distribution.rb` | ação de macro e trigger |
| Modificar | `app/models/ticket/perform_changes.rb` | registro da ação, prefixo, ordem no `before_save` |
| Modificar | `lib/validations/verify_perform_rules_validator.rb` | presença e modo válido |
| Criar | `app/models/user/ticket_distribution_membership.rb`; modificar `app/models/user.rb` | exclusão de usuário e `discord_uid` |
| Modificar | `app/controllers/tickets_mass_controller.rb` | recusa do lote antes de escrever e ordem das travas |
| Criar | `app/controllers/ticket_distribution_controller.rb`, `app/policies/controllers/ticket_distribution_controller_policy.rb`, `config/routes/ticket_distribution.rb` | API da tela |
| Modificar | `app/assets/javascripts/app/controllers/_ui_element/_application_action.coffee`, `app/assets/javascripts/app/models/{macro,trigger,ticket}.coffee` | editor, prefixo adiado, mensagem do sino |
| Modificar | `app/assets/javascripts/app/controllers/_plugin/notify.coffee`, `app/assets/javascripts/app/controllers/ticket_zoom.coffee`, `app/assets/javascripts/app/lib/mixins/ticket_mass_updatable.coffee` | aviso fixo da recusa |
| Criar | `app/assets/javascripts/app/controllers/ticket_distribution.coffee`, `app/assets/javascripts/app/views/ticket_distribution/*.jst.eco`; modificar `app/assets/stylesheets/zammad.scss` | tela |
| Modificar | `i18n/zammad.pot`, `i18n/zammad.pt-br.po` | traduções |
| Specs | ver cada tarefa | |
| Modificar | `.claude/NEWBYTE_WORKFLOW.md` | entrada de changelog |

---

### Task 0: Preflight e commit do plano

**Files:**

- Commit: `docs/plans/2026-10-20-distribuicao-atendimentos.md`

**Interfaces:**

- Produces: ambiente de teste respondendo; baseline verde; plano versionado.

- [ ] **Step 1: Confirmar branch e base**

```bash
git fetch -q origin
test "$(git branch --show-current)" = feat/ticket-distribution
git merge-base --is-ancestor origin/newbyte-stable HEAD && echo BASE_OK
```

Expected: `BASE_OK`. Se `origin/newbyte-stable` andou além de `31f0e2b171`, pare e relate antes de seguir.

- [ ] **Step 2: Confirmar o ambiente de teste**

Run: `ruby -v && pg_isready && redis-cli ping`
Expected: `ruby 3.4.8…`, `accepting connections`, `PONG`. Sem Ruby, PostgreSQL e Redis na máquina, use o
devcontainer `.devcontainer/with-selenium` (no WSL, exige a integração WSL do Docker Desktop ligada) e rode
todos os comandos deste plano dentro dele. Ele é o `default` mais o Selenium, que as system specs e o QUnit
(Tasks 9 e 10) exigem. Não siga sem ambiente: o plano não tem gate que dispense o RSpec.

- [ ] **Step 3: Baseline das specs que o plano altera**

Run (RSpec CI, depois de `rm -f db/schema.rb`): `spec/models/user_spec.rb spec/models/system_report_spec.rb
spec/models/ticket/perform_changes_spec.rb spec/lib/validations/verify_perform_rules_validator_spec.rb
spec/jobs/trigger_webhook_job/record_payload/ticket_spec.rb spec/requests/ticket_spec.rb`
Expected: `0 failures`. Falha aqui é pré-existente: relate e não siga.

- [ ] **Step 4: Commit do plano**

```bash
git add docs/plans/2026-10-20-distribuicao-atendimentos.md
git commit -m "docs(plans): plano da distribuição de atendimentos N1/N2 (NDESK-70)"
```

---

### Task 1: Tabela da escala e modelo `Ticket::DistributionMember`

**Files:**

- Create: `db/migrate/20261028000001_create_ticket_distribution_members.rb`
- Create: `app/models/ticket/distribution_member.rb`
- Create: `spec/factories/ticket/distribution_member.rb`
- Test: `spec/models/ticket/distribution_member_spec.rb`

**Interfaces:**

- Produces:
  - tabela `ticket_distribution_members` (`id` integer, `user_id` FK `users` not null, `level` string(2)
    not null, `active` boolean not null default `true`, `last_assigned_at` datetime(3) null, `created_by_id`,
    `updated_by_id`, timestamps(3); índice único `[user_id, level]`);
  - coluna `users.discord_uid` string(30) null;
  - `Ticket::DistributionMember` com `LEVELS = %w[n1 n2]`, `belongs_to :user`, escopos `n1`, `n2`,
    `switched_on` (`active: true`) e `by_turn` (`last_assigned_at` crescente com nulos primeiro, depois `id`);
  - factory `:ticket_distribution_member` (padrão `level 'n2'`, `user { association :agent }`,
    `created_by_id { 1 }`, `updated_by_id { 1 }`: sem `UserInfo`, as colunas NOT NULL não se preenchem),
    trait `:n1`.

- [ ] **Step 1: Escrever a spec do modelo**

```ruby
RSpec.describe Ticket::DistributionMember, type: :model do
  let(:agent) { create(:agent) }

  it 'allows the same user once per level' do
    create(:ticket_distribution_member, :n1, user: agent)
    expect(build(:ticket_distribution_member, :n1, user: agent)).not_to be_valid
    expect(build(:ticket_distribution_member, user: agent)).to be_valid
  end

  it 'rejects unknown levels' do
    expect(build(:ticket_distribution_member, level: 'n3')).not_to be_valid
  end

  it 'orders by turn: never assigned first, then oldest, then id' do
    newer = create(:ticket_distribution_member, last_assigned_at: 1.hour.ago)
    older = create(:ticket_distribution_member, last_assigned_at: 2.hours.ago)
    never = create(:ticket_distribution_member, last_assigned_at: nil)
    expect(described_class.by_turn).to eq([never, older, newer])
  end

  it 'adds the discord_uid column to users' do
    expect(User.column_names).to include('discord_uid')
  end
end
```

- [ ] **Step 2: Rodar e ver falhar**

Run: RSpec CI `spec/models/ticket/distribution_member_spec.rb`
Expected: FAIL com `uninitialized constant Ticket::DistributionMember`.

- [ ] **Step 3: Migration, modelo e factory**

Migration sem guarda (roda em instalação nova e no banco de teste): `create_table … id: :integer` no molde de
`db/migrate/20260609000001_create_ticket_satisfaction_ratings.rb`, e
`add_column :users, :discord_uid, :string, limit: 30, null: true` se a coluna não existir, seguido de
`User.reset_column_information`. Modelo `< ApplicationModel` com `include HasDefaultModelUserRelations`,
`validates :level, inclusion: { in: LEVELS }` e `validates :user_id, uniqueness: { scope: :level }`.
`by_turn` = `order(Arel.sql('last_assigned_at ASC NULLS FIRST'), :id)`.

- [ ] **Step 4: Rodar e ver passar**

Run: `rm -f db/schema.rb` e RSpec CI `spec/models/ticket/distribution_member_spec.rb`
Expected: `4 examples, 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add db/migrate/20261028000001_create_ticket_distribution_members.rb app/models/ticket/distribution_member.rb \
  spec/factories/ticket/distribution_member.rb spec/models/ticket/distribution_member_spec.rb
git commit -m "feat(distribuicao): tabela da escala e modelo de membro N1/N2 (NDESK-70)"
```

---

### Task 2: Setting, permissão, `discord_uid`, triggers desligados e `Config`

**Files:**

- Create: `db/migrate/20261028000002_add_ticket_distribution_setup.rb`
- Modify: `db/seeds/permissions.rb`, `db/seeds/settings.rb`, `db/seeds/object_manager_attributes.rb`,
  `db/seeds/triggers.rb`
- Create: `app/models/ticket/distribution/config.rb`
- Create: `spec/support/ticket_distribution.rb`
- Modify: `spec/models/system_report_spec.rb` (lista `non_confidential_settings`)
- Test: `spec/db/migrate/add_ticket_distribution_setup_spec.rb`, `spec/db/seeds/ticket_distribution_spec.rb`,
  `spec/models/ticket/distribution/config_spec.rb`

**Interfaces:**

- Consumes: coluna `users.discord_uid` (Task 1).
- Produces:
  - `Ticket::Distribution::Config.current → Config` e os leitores `complexity_attribute → String`,
    `weights → Hash{String => Integer}`, `weight_for(value) → Integer | nil` (nil = valor sem peso),
    `ignored_state_ids → Array<Integer>`, `ignored_priority_ids → Array<Integer>`,
    `dispatch_group_id → Integer | nil`, `dispatch_user_id → Integer | nil`;
  - `Config#complexity_attribute_present? → Boolean` (coluna existe em `Ticket` e o atributo do ObjectManager
    está ativo);
  - `Config#complexity_of(ticket) → String | nil` (lê o valor em memória; nil se vazio ou se o atributo não
    existe);
  - `Config.update!(params) → Config`: aceita as chaves do Setting (parcial, faz merge), levanta
    `Exceptions::UnprocessableEntity` com mensagem traduzível se o atributo não for de ticket do tipo `select`
    e ativo, se algum peso não for inteiro ≥ 0, ou se algum id (estado, prioridade, grupo, usuário) não existir;
  - `Config.complexity_attribute_options → Array<{ name:, display:, options: Hash{String => String} }>`:
    atributos de ticket ativos, do tipo `select`, `editable: true` e sem `relation`. Isso tira os atributos de
    sistema, como `state_id`, `priority_id`, `type` e `detected_language`;
  - shared context `'with ticket distribution complexity'`: cria o atributo de ticket `complexidades` (select,
    opções `facil`, `moderado`, `complexo`, visível na edição para `ticket.agent`) e roda
    `ObjectManager::Attribute.migration_execute`. Quem inclui usa `db_strategy: :reset`. O cop
    `Zammad/ExistsDbStrategy` acusa `migration_execute` fora de um bloco com essa metadata: no shared context,
    use `# rubocop:disable Zammad/ExistsDbStrategy` com a justificativa "quem inclui declara db_strategy: :reset".

- [ ] **Step 1: Specs de migração, seeds e Config**

```ruby
# spec/db/migrate/add_ticket_distribution_setup_spec.rb
RSpec.describe AddTicketDistributionSetup, :aggregate_failures, type: :db_migration do
  before do
    Setting.where(name: 'ticket_distribution').destroy_all
    Permission.where(name: 'admin.ticket_distribution').destroy_all
    ObjectManager::Attribute.where(name: 'discord_uid').destroy_all
    Trigger.where(name: ['Distribuição — Entrada', 'Distribuição — Reabertura']).destroy_all
  end

  it 'creates permission, setting, the Discord attribute and both triggers switched off' do
    migrate
    expect(Permission.exists?(name: 'admin.ticket_distribution')).to be(true)
    expect(Setting.get('ticket_distribution')).to include('complexity_attribute' => 'complexidades',
                                                         'weights' => { 'facil' => 1, 'moderado' => 3, 'complexo' => 6 })
    expect(ObjectManager::Attribute.get(object: 'User', name: 'discord_uid')).to be_present
    entry  = Trigger.find_by(name: 'Distribuição — Entrada')
    reopen = Trigger.find_by(name: 'Distribuição — Reabertura')
    expect([entry.active, reopen.active]).to eq([false, false])
    expect(entry.perform).to eq('distribution.ticket_distribution' => { 'value' => 'entry' })
    expect(reopen.condition['ticket.state_id']).to eq('operator' => 'has changed')
  end
end
```

`spec/db/seeds/ticket_distribution_spec.rb`: a permissão, o Setting com o padrão, o atributo `discord_uid` e
os dois triggers "Distribuição — …" existem num banco recém-semeado, com os triggers desligados (ajuste 7).

`spec/models/ticket/distribution/config_spec.rb` (com o shared context e `db_strategy: :reset` onde precisar
da coluna):

- `weight_for('moderado') == 3`, `weight_for('raro')` é `nil`;
- `complexity_of(ticket)` lê o valor atribuído e ainda não salvo (`ticket.complexidades = 'complexo'`);
- **Review Focus 5:** sem o atributo `complexidades`, `complexity_attribute_present?` é `false` e
  `complexity_of(ticket)` é `nil`, sem exceção;
- `update!(complexity_attribute: 'title')` levanta `Exceptions::UnprocessableEntity`; `update!(weights:
  { 'facil' => -1 })` também; `update!(dispatch_group_id: group.id)` mantém as outras chaves;
- `complexity_attribute_options` inclui `complexidades` com as três opções e não inclui `state_id`,
  `priority_id` nem atributos que não são `select`.

- [ ] **Step 2: Rodar e ver falhar**

Run: RSpec CI nos três arquivos novos.
Expected: FAIL (`uninitialized constant AddTicketDistributionSetup` / `Ticket::Distribution::Config`).

- [ ] **Step 3: Migração guardada, seeds e Config**

- Migração no molde de `db/migrate/20260609000002_add_csat_permissions_and_settings.rb`
  (`return if !Setting.exists?(name: 'system_init_done')`): `Permission.create_if_not_exists(name:
  'admin.ticket_distribution', label: 'Ticket Distribution', description: 'Manage the N1/N2 ticket
  distribution.', preferences: { prio: 1336 })`; `Setting.create_if_not_exists` com o padrão das restrições
  globais, `preferences: { permission: ['admin.ticket_distribution'] }`; `ObjectManager::Attribute.add` do
  `discord_uid` (`force: true`, obrigatório porque a coluna já existe: sem `force`, o `add` força
  `to_create`/`to_migrate`; `data_type: 'input'`, `data_option: { type: 'text', maxlength: 30, null: true,
  item_class: 'formGroup--halfSize', permission: ['admin.user'] }`, `editable: false`, `active: true`, telas
  `edit`/`create` com `'-all-' => { null: true }` e `view` com `'-all-' => { shown: false }`, `to_create:
  false`, `to_migrate: false`, `to_delete: false`, `position: 1495`, `created_by_id: 1`, `updated_by_id: 1`,
  molde do `vip` de usuário em `db/seeds/object_manager_attributes.rb`); os dois
  `Trigger.create_if_not_exists` com `active: false`, `activator: 'action'`, `execution_condition_mode:
  'selective'`, `created_by_id: 1`, `updated_by_id: 1` (NOT NULL e sem `UserInfo` na migração), condições
  `{ 'ticket.action' => { 'operator' => 'is', 'value' => 'create' } }` (Entrada) e
  `{ 'ticket.action' => { 'operator' => 'is', 'value' => 'update' }, 'ticket.state_id' => { 'operator' =>
  'has changed' } }` (Reabertura), `perform` com o modo correspondente.
- Seeds: a mesma permissão com `__()`, o Setting, o atributo e os dois triggers desligados (em
  `db/seeds/triggers.rb`, com as mesmas condições e `perform` da migração). O papel Admin já cobre `admin.*`
  pela permissão `admin`: não há `permission_grant` e o `spec/models/role_spec.rb` não muda.
- `Config` lê `Setting.get('ticket_distribution')` com `with_indifferent_access` e cai no padrão para chave
  ausente; `update!` grava com `Setting.set`.
- `spec/models/system_report_spec.rb`: incluir `'ticket_distribution'` em `non_confidential_settings`.

- [ ] **Step 4: Rodar e ver passar**

Run: `rm -f db/schema.rb` e RSpec CI nos três arquivos novos + `spec/models/system_report_spec.rb
spec/models/trigger_spec.rb spec/lib/import/otrs/state_factory_spec.rb` (a última usa `Trigger.reseed`, que
recarrega `db/seeds/triggers.rb`)
Expected: `0 failures`.

- [ ] **Step 5: Commit**

```bash
git add db/migrate/20261028000002_add_ticket_distribution_setup.rb db/seeds/ app/models/ticket/distribution/config.rb \
  spec/support/ticket_distribution.rb spec/db/ spec/models/ticket/distribution/config_spec.rb spec/models/system_report_spec.rb
git commit -m "feat(distribuicao): setting, permissão, ID do Discord e triggers desligados (NDESK-70)"
```

---

### Task 3: Usuário — exclusão, responsável de Disparos e `discord_uid`

**Files:**

- Create: `app/models/user/ticket_distribution_membership.rb`
- Modify: `app/models/user.rb` (incluir o concern junto dos outros `User::*`, antes da linha do
  `before_destroy`, `app/models/user.rb:56`)
- Modify: `app/models/ticket/distribution/config.rb` (`release_dispatch_user!`)
- Modify: `spec/models/user_spec.rb` (`refs_known` de "does remove references before destroy")
- Modify: `spec/jobs/trigger_webhook_job/record_payload/ticket_spec.rb`
- Test: `spec/models/user/ticket_distribution_membership_spec.rb`

**Interfaces:**

- Consumes: `Ticket::DistributionMember` (Task 1), `Config` (Task 2).
- Produces:
  - `User#ticket_distribution_members` (`has_many …, class_name: 'Ticket::DistributionMember', inverse_of:
    :user, dependent: :destroy`). O concern é incluído antes da linha 56, então o `has_many` apaga as linhas
    antes de `destroy_move_dependency_ownership`;
  - `association_attributes_ignored :ticket_distribution_members` no concern (o método soma à lista,
    `app/models/application_model/can_associations.rb:325`). Sem isso, `ticket_distribution_member_ids` sai em
    todo JSON e asset de usuário e no `ticket.owner` do webhook, e um `PUT /api/v1/users/:id` de quem tem só
    `admin.user` mexeria na escala;
  - validação de `discord_uid`: `%r{\A\d+\z}`, `allow_blank`, só se `has_attribute?(:discord_uid)` (migrations
    antigas instanciam `User` antes da coluna existir);
  - `Ticket::Distribution::Config.release_dispatch_user!(user_id) → void`: limpa só `dispatch_user_id` quando
    ele é o usuário, e o grupo de Disparos continua.

- [ ] **Step 1: Specs**

```ruby
RSpec.describe User::TicketDistributionMembership, type: :model do
  let(:agent) { create(:agent) }

  it 'removes the memberships with the user' do
    create(:ticket_distribution_member, :n1, user: agent)
    create(:ticket_distribution_member, user: agent)
    expect { agent.destroy! }.to change(Ticket::DistributionMember, :count).by(-2)
  end

  it 'lets a data privacy task delete a member', performs_jobs: true do
    create(:ticket_distribution_member, user: agent)
    create(:data_privacy_task, deletable: agent)
    DataPrivacyTaskJob.perform_now
    expect(User.exists?(agent.id)).to be(false)
    expect(Ticket::DistributionMember.where(user_id: agent.id)).to be_empty
  end

  it 'clears the dispatch responsible and keeps the dispatch group' do
    group = create(:group)
    Ticket::Distribution::Config.update!(dispatch_group_id: group.id, dispatch_user_id: agent.id)
    agent.destroy!
    config = Ticket::Distribution::Config.current
    expect([config.dispatch_group_id, config.dispatch_user_id]).to eq([group.id, nil])
  end

  it 'accepts only digits as Discord ID' do
    expect(build(:agent, discord_uid: '123456789012345678')).to be_valid
    expect(build(:agent, discord_uid: 'abc')).not_to be_valid
    expect(build(:agent, discord_uid: '')).to be_valid
  end
end
```

`spec/models/user_spec.rb`: incluir `'Ticket::DistributionMember' => { 'user_id' => 1, 'created_by_id' => 0,
'updated_by_id' => 0 }` em `refs_known` e criar `create(:ticket_distribution_member, user: user)` junto dos
outros objetos da lista "delete objects", conferindo que ele some.

Mais três exemplos na spec do concern, porque um ID do Discord real tem 17 a 19 dígitos, e só um valor desse
tamanho salvo num usuário existente pega o defeito que tirou o sufixo `_id` do nome:

- `agent.update!(discord_uid: '123456789012345678')` salva e grava histórico;
- `PUT /api/v1/users/:id` de um admin com esse valor responde 200;
- o JSON do usuário (`agent.attributes_with_association_ids`) não tem `ticket_distribution_member_ids`.

`spec/jobs/trigger_webhook_job/record_payload/ticket_spec.rb`: com
`owner.update!(discord_uid: '123456789012345678')`, o payload gerado tem esse valor em
`payload['owner']['discord_uid']` e não tem chave `ticket_distribution_member_ids` (critério 6, lado NDesk).

- [ ] **Step 2: Rodar e ver falhar**

Run: RSpec CI nos quatro arquivos.
Expected: FAIL (`uninitialized constant User::TicketDistributionMembership` e "Failed deleting references!").

- [ ] **Step 3: Concern, inclusão e `release_dispatch_user!`**

`before_destroy :ticket_distribution_release_dispatch` no concern chama `Config.release_dispatch_user!(id)`.

- [ ] **Step 4: Rodar e ver passar**

Run: RSpec CI nos quatro arquivos.
Expected: `0 failures`.

- [ ] **Step 5: Commit**

```bash
git add app/models/user/ticket_distribution_membership.rb app/models/user.rb app/models/ticket/distribution/config.rb \
  spec/models/user/ticket_distribution_membership_spec.rb spec/models/user_spec.rb spec/jobs/trigger_webhook_job/record_payload/ticket_spec.rb
git commit -m "feat(distribuicao): escala acompanha a exclusão do usuário e ID do Discord no payload (NDESK-70)"
```

---

### Task 4: Elegibilidade e Carga

**Files:**

- Create: `app/models/ticket/distribution/eligibility.rb`, `app/models/ticket/distribution/load.rb`
- Test: `spec/models/ticket/distribution/eligibility_spec.rb`, `spec/models/ticket/distribution/load_spec.rb`

**Interfaces:**

- Consumes: `Config` (Task 2).
- Produces:
  - `Ticket::Distribution::Eligibility.can_own?(user, group_id) → Boolean`: ativo, `ticket.agent` e
    `group_access?(group_id, 'full')`. Com `group_id` nil, o grupo não é testado (prévia da tela);
  - `Ticket::Distribution::Eligibility.problems(user, group_ids) → Array<Hash>`, cada item
    `{ type: 'inactive' }`, `{ type: 'not_agent' }` ou `{ type: 'no_group_access', groups: [nomes] }`;
  - `Ticket::Distribution::Load.new(config).by_user(user_ids, exclude_ticket_id: nil)
    → Hash{Integer => { points: Integer, tickets: Integer }}`, com uma entrada para cada id pedido (zeros por
    padrão). `tickets` conta só tickets de peso > 0 (ajuste 6).

- [ ] **Step 1: Specs**

Eligibility (tabela de casos):

- inativo → `false`; sem `ticket.agent` → `false`; acesso `read` ao grupo → `false`; `full` → `true`;
  `group_id: nil` com agente ativo → `true`;
- **paridade com `check_owner_active`:** para cada um dos quatro casos acima, `ticket.update!(owner: user)`
  num ticket aberto do grupo mantém o dono se, e só se, `can_own?` é `true`;
- `problems(agent_sem_acesso, [suporte.id, vendas.id])` devolve
  `[{ type: 'no_group_access', groups: ['Suporte'] }]` quando falta só o Suporte.

Load (`db_strategy: :reset`, shared context `'with ticket distribution complexity'`):

```ruby
it 'sums the weights of the open tickets of each agent' do
  create(:ticket, owner: agent, group:, complexidades: 'complexo')                       # 6
  create(:ticket, owner: agent, group:, complexidades: 'facil',
                  state: Ticket::State.find_by(name: 'pending reminder'))               # 1
  create(:ticket, owner: agent, group:, complexidades: 'moderado',
                  state: Ticket::State.find_by(name: 'closed'))                         # não conta
  create(:ticket, owner: agent, group: create(:group), complexidades: 'moderado')       # 3, outro grupo
  create(:ticket, owner: agent, group:)                                                 # sem complexidade
  expect(described_class.new(config).by_user([agent.id, other.id]))
    .to eq(agent.id => { points: 10, tickets: 3 }, other.id => { points: 0, tickets: 0 })
end
```

- estados `merged` e `removed` não contam;
- estados e prioridades customizados, como os de produção (spec §10): um estado "Melhoria" de categoria
  `open` (`create(:ticket_state, …)`) e uma prioridade "4 sem previsão" (`create(:ticket_priority, …)`) pesam
  normalmente e, marcados em `ignored_state_ids` / `ignored_priority_ids`, saem da soma e da contagem;
- `exclude_ticket_id:` tira o próprio ticket;
- **Review Focus 1:** dois tickets com `complexidades: 'raro'` (opção nova, sem peso) pesam 0 e
  `Rails.logger` recebe **um** `warn` com `raro` na chamada;
- **Review Focus 5:** sem a coluna do atributo, `by_user` devolve zeros e loga um `error`, sem exceção.

- [ ] **Step 2: Rodar e ver falhar**

Run: RSpec CI nos dois arquivos.
Expected: FAIL (constantes indefinidas).

- [ ] **Step 3: Implementar**

`Load`: `Ticket.where(owner_id: user_ids)` com estado aberto (subquery de `Ticket::State` cujo
`state_type.name` não está em `closed merged removed`), sem os ids ignorados e sem o ticket excluído,
`.group(:owner_id, attr).count`, e a soma dos pesos em Ruby. Só usar `attr` se
`Ticket.column_names.include?(attr)` (é o nome de coluna no `group`; nunca interpolar outro valor).

- [ ] **Step 4: Rodar e ver passar**

Run: RSpec CI nos dois arquivos.
Expected: `0 failures`.

- [ ] **Step 5: Commit**

```bash
git add app/models/ticket/distribution/eligibility.rb app/models/ticket/distribution/load.rb \
  spec/models/ticket/distribution/eligibility_spec.rb spec/models/ticket/distribution/load_spec.rb
git commit -m "feat(distribuicao): quem pode ser dono e carga calculada na hora (NDESK-70)"
```

---

### Task 5: Rodízio e regras de escolha

**Files:**

- Create: `app/models/ticket/distribution/decision.rb`, `rotation.rb`, `picker.rb` (em
  `app/models/ticket/distribution/`)
- Test: `spec/models/ticket/distribution/rotation_spec.rb`, `spec/models/ticket/distribution/picker_spec.rb`

**Interfaces:**

- Consumes: `Config`, `Eligibility`, `Load`, `Ticket::DistributionMember`.
- Produces:
  - `Ticket::Distribution::Decision = Data.define(:outcome, :owner_id, :member, :notices, :notify_user_id)`:
    - `outcome` ∈ `:assigned`, `:dispatch`, `:kept`, `:no_n1`, `:not_handed_over`, `:complexity_missing`,
      `:skipped`;
    - `owner_id`: dono a gravar (nil = não mexer);
    - `member`: membro cujo `last_assigned_at` deve ser atualizado (nil = nenhum);
    - `notices`: lista com `:not_handed_over` e/ou `:no_n1` (vazia = nenhuma nota);
    - `notify_user_id`: quem recebe o sino do `:not_handed_over` (nil = ninguém);
  - `Ticket::Distribution::Rotation.new(config, load: Load.new(config)).pick(group_id:, exclude_user_id: nil,
    exclude_ticket_id: nil) → Ticket::DistributionMember | nil`. Candidatos: `n2.switched_on`, sem
    `out_of_office?`, `can_own?(user, group_id)` e diferentes de `exclude_user_id`. Ordem: menor `points`,
    depois `last_assigned_at` crescente com nulos primeiro, depois `id` do membro;
  - `Ticket::Distribution::Picker.new(ticket, config: Config.current)`:
    - `#entry → Decision`;
    - `#handover(acting_user_id:) → Decision`;
    - `#reopening(changes:, author_id:) → Decision`.

  Regras (spec §5.2–§5.4; os números dos itens são os do spec):
  - **entry:** o primeiro de `n1.by_turn` que passa em `can_own?(user, ticket.group_id)` →
    `:assigned` com `member` = esse N1. Nenhum → `:no_n1`, `owner_id: 1`, `notices: [:no_n1]`;
  - **handover:**
    1. `complexity_of(ticket)` nil → `:complexity_missing`;
    2. o dono atual é N2 ligado, sem OOO, passa no filtro e não é `acting_user_id` → `:kept`;
    3. grupo do ticket = `dispatch_group_id` e o responsável está definido, sem OOO e passa no filtro →
       `:dispatch` (o Interruptor dele não importa e `member` é nil);
    4. `Rotation#pick(group_id: ticket.group_id, exclude_user_id: acting_user_id, exclude_ticket_id: ticket.id)`
       → `:assigned`;
    5. ninguém → `:not_handed_over`, `owner_id: nil`, `notices: [:not_handed_over]`,
       `notify_user_id: acting_user_id`;
  - **reopening:**
    - `:skipped` quando o estado antigo de `changes['state_id']` não é de categoria `closed`, quando o novo é
      `closed`/`merged`/`removed`, quando falta `changes['state_id']`, ou quando o autor tem `ticket.agent` ou
      é o usuário 1 (ajuste 5);
    - quem atendeu = `changes['owner_id']&.first`, senão `ticket.owner_id`;
    - `:kept` com `owner_id` = quem atendeu se ele passa no filtro e (é N1, ou é N2 ligado sem OOO, ou não está
      em nenhuma lista);
    - senão, regras 3 e 4 do handover sem `exclude_user_id`;
    - sem complexidade → `entry`;
    - sem candidato → `entry` com `:not_handed_over` somado a `notices` e `notify_user_id` = o N1 escolhido
      pela Entrada. Se a Entrada também não acha N1, ficam as duas notas (`[:not_handed_over, :no_n1]`), o dono
      fica 1 e ninguém recebe sino (`notify_user_id: nil`).

- [ ] **Step 1: Specs do Picker e do Rodízio**

Contexto comum (`db_strategy: :reset`, shared context da complexidade): `group`, três N2 com acesso `full`
(`n2_a`, `n2_b`, `n2_c`), um N1 e um ticket aberto `complexidades: 'moderado'`. Agente fora do escritório =
`create(:agent, :ooo, ooo_agent: substituto, groups: [group])`: o `OutOfOfficeValidator` exige o substituto.
Exemplos, com os valores literais:

- **entry:**
  - o único N1 recebe mesmo com `:ooo`;
  - com dois N1, recebe o de `last_assigned_at` nulo, depois o mais antigo; no empate, o de menor `id`;
  - N1 sem acesso ao grupo é pulado;
  - nenhum N1 elegível → `outcome :no_n1`, `owner_id 1`, `notices [:no_n1]`;
- **handover:**
  - sem complexidade → `:complexity_missing`;
  - cargas 6, 3 e 1 → `n2_c` (critério 2, três agentes);
  - a carga não conta o próprio ticket: um ticket `complexo` já de `n2_c` não pesa contra `n2_c` quando é ele
    que está sendo decidido;
  - empate em 0 com `last_assigned_at` nulo, 1 h e 2 h atrás → o nulo; sem nulo → o de 2 h (critério 4);
  - `n2_a` desligado e `n2_b` com `:ooo` ficam de fora; `n2_c` sem sessão (offline) recebe (critério 3);
  - `acting_user_id: n2_c.id` tira `n2_c` dos candidatos;
  - reaplicação: dono `n2_a` ligado → `:kept`, e o `last_assigned_at` de `n2_a` não muda;
  - reaplicação pelo próprio dono → não mantém, vai para outro N2;
  - grupo de Disparos → responsável, inclusive com o Interruptor dele desligado, `member nil`;
  - responsável com `:ooo`, sem acesso ou não definido → regra normal do N2;
  - todos desligados → `:not_handed_over`, `owner_id nil`, `notify_user_id` = quem repassa;
  - **Review Focus 3:** ticket de um grupo onde nenhum N2 tem acesso `full` → `:not_handed_over`;
  - **Review Focus 2:** o N1 também é `n2_a` e aplica a macro num ticket dele → vai para `n2_b`/`n2_c`; se
    `n2_a` for o único N2 → `:not_handed_over`;
- **reopening:**
  - `pending action` → `open` e `closed` → `merged`/`removed` → `:skipped`;
  - autor com `ticket.agent` → `:skipped`; autor usuário 1 → `:skipped`;
  - follow-up zerou o dono (`changes['owner_id'] = [n1.user_id, 1]`) e o N1 continua elegível → `:kept` com
    `owner_id` = o N1;
  - dono fora das listas (agente "engenharia" com acesso) → `:kept`;
  - dono `n2_a` ligado → `:kept`;
  - dono `n2_a` desligado → `:assigned` para o de menor carga, `member` = esse N2;
  - sem complexidade → `entry`;
  - nenhum N2 → `entry` com `notices [:not_handed_over]` e `notify_user_id` = o N1 escolhido;
  - nenhum N2 e nenhum N1 → `owner_id 1`, `notices [:not_handed_over, :no_n1]`, `notify_user_id nil`.

Rodízio: com `group_id: nil`, um N2 sem acesso a nenhum grupo continua candidato (prévia da tela, spec §7).

- [ ] **Step 2: Rodar e ver falhar**

Run: RSpec CI nos dois arquivos.
Expected: FAIL (constantes indefinidas).

- [ ] **Step 3: Implementar `Decision`, `Rotation` e `Picker` com as interfaces acima**

`Picker` não escreve nada: só lê e devolve a `Decision`.

- [ ] **Step 4: Rodar e ver passar**

Run: RSpec CI nos dois arquivos.
Expected: `0 failures`.

- [ ] **Step 5: Commit**

```bash
git add app/models/ticket/distribution/{decision,rotation,picker}.rb spec/models/ticket/distribution/{rotation,picker}_spec.rb
git commit -m "feat(distribuicao): regras de entrada, repasse e reabertura (NDESK-70)"
```

---

### Task 6: Ação `TicketDistribution`, trava, avisos e validação do `perform`

**Files:**

- Create: `app/models/ticket/perform_changes/action/ticket_distribution.rb`
- Create: `app/models/ticket/distribution/lock.rb`, `notice.rb`, `complexity_missing_error.rb`
- Modify: `app/models/ticket/perform_changes.rb`
- Modify: `lib/validations/verify_perform_rules_validator.rb`
- Test: `spec/models/ticket/perform_changes/action/ticket_distribution_spec.rb`,
  `spec/models/ticket/distribution/lock_spec.rb`, `spec/lib/validations/verify_perform_rules_validator_spec.rb`

**Interfaces:**

- Consumes: `Picker`, `Decision`, `Config` e `Ticket::DistributionMember`.
- Produces:
  - `Ticket::Distribution::ComplexityMissingError < Exceptions::UnprocessableEntity`, com `ENTITY =
    'ticket_distribution.complexity_missing'` e mensagem `__('Fill in the complexity before handing over.')`.
    O JSON de erro sai com `error_human` e `unprocessable_entity: ENTITY`
    (`application_controller/handles_errors.rb`);
  - `Ticket::Distribution::Lock`:
    - `KEY = Zlib.crc32('ndesk.ticket_distribution')`;
    - `.acquire!(ticket_id) → void`: `Ticket.where(id:).lock.pluck(:id)` e depois
      `SELECT pg_advisory_xact_lock(KEY)`;
    - `.lock_tickets!(ids) → Array<Ticket>`: `Ticket.where(id: ids).order(:id).lock.to_a` (recarrega e trava
      em ordem de `id`);
  - `Ticket::Distribution::Notice`:
    - `.not_handed_over!(ticket:, notify_user_id:)`: nota interna `__('Not handed over: no N2 agent in the
      rotation.')`, mais o `OnlineNotification.add(type: 'distribution_not_handed_over', object: 'Ticket',
      o_id: ticket.id, seen: false, user_id: notify_user_id, created_by_id: 1)` quando `notify_user_id` não é
      nil;
    - `.no_n1!(ticket:)`: nota interna `__('No N1 agent can own tickets of this group.')` e
      `Rails.logger.warn`;
    - as notas têm sender `System`, type `note`, `internal: true`, `created_by_id`/`updated_by_id` 1, e corpo
      traduzido para o `locale_default`;
  - `Ticket::PerformChanges`:
    - `:ticket_distribution` em `available_perform_change_actions`;
    - `additional_object_action` devolve `{ name: :ticket_distribution, value: }` para
      `distribution.ticket_distribution`;
    - `execute_before_save` sobrescrito para rodar as instâncias de `TicketDistribution` depois das outras;
  - `Validations::VerifyPerformRulesValidator`: `'distribution.ticket_distribution' => %w[value]` em
    `CHECK_PRESENT`, e erro se `value` não estiver em `%w[entry handover reopening]`.

  Fluxo do `execute` (fase `before_save`):
  1. `mode = execution_data['value']`; modo desconhecido → log e retorna `false`.
  2. Para `handover` com `origin == 'macro'` e sem complexidade → `raise ComplexityMissingError`, **antes** de
     qualquer trava ou escrita.
  3. `Lock.acquire!(record.id)`. Fora de macro (trigger), os passos 3 a 5 rodam dentro de
     `ActiveRecord::Base.transaction(requires_new: true)`, com `rescue ActiveRecord::Deadlocked,
     ActiveRecord::LockWaitTimeout`, que loga em `error` e não distribui. No e-mail, os triggers rodam dentro da
     transação da importação (`app/models/transaction.rb`). Um erro de PostgreSQL sem savepoint abortaria essa
     transação, e o `execute_single_backend` só engole a exceção Ruby (`lib/transaction_dispatcher.rb:64`): a
     importação do e-mail falharia. Em macro, o erro sobe normalmente.
  4. A decisão vem do `Picker`:
     - `entry` → `#entry`;
     - `handover` → `#handover(acting_user_id: user_id)`, com `:complexity_missing` fora de macro caindo em
       `#entry`;
     - `reopening` → `#reopening(changes: context_data.try(:dig, :changes) || {}, author_id: user_id)`.
  5. Se `owner_id` difere do atual: `record.history_change_source_attribute(performable, 'owner_id')` (como faz
     `AttributeUpdates`; só tem efeito para trigger) e grava `record.owner_id`. Depois,
     `member&.update!(last_assigned_at: Time.zone.now)` e uma nota para cada item de `notices`, ainda no
     `before_save`. Assim as notas nascem antes do artigo da macro (spec §5.3, item 6).
  6. Retorna `true` se mudou o dono (`save_needed`).

- [ ] **Step 1: Specs**

`spec/models/ticket/distribution/lock_spec.rb`: dentro de `ActiveRecord::Base.transaction`, depois de
`acquire!(ticket.id)`, `SELECT count(*) FROM pg_locks WHERE locktype = 'advisory' AND objid = KEY AND
pid = pg_backend_pid()` é ≥ 1. Não afirme que o lock some no fim: com transactional fixtures, o `transaction`
aninhado vira savepoint e o lock só sai no rollback da fixture.

`spec/lib/validations/verify_perform_rules_validator_spec.rb`: uma macro com
`'distribution.ticket_distribution' => {}` fica inválida; com `{ 'value' => 'foo' }` também; com
`{ 'value' => 'handover' }` fica válida.

Ação (`db_strategy: :reset`, shared context da complexidade, N1 e três N2 como na Task 5, `ticket` aberto
de `group` com dono = o N1 e `complexidades: 'moderado'`,
`macro = create(:macro, perform: { 'distribution.ticket_distribution' => { 'value' => 'handover' } })`):

```ruby
def apply_macro(ticket, macro, agent, body: 'Realizamos uma análise prévia da sua ocorrência')
  ticket.perform_changes(macro, 'macro', nil, agent.id) do |object, _save_needed|
    object.save!
    create(:ticket_article, :outbound_email, ticket: object, body:)
  end
end

it 'refuses before any write when complexity is missing' do
  ticket.update!(complexidades: nil)
  EventBuffer.reset('transaction')
  expect { apply_macro(ticket, macro, n1.user) }
    .to raise_error(Ticket::Distribution::ComplexityMissingError) { |e| expect(e.entity).to eq('ticket_distribution.complexity_missing') }
  expect(EventBuffer.list('transaction')).to be_empty
  expect(ticket.reload.owner_id).to eq(n1.user_id)
end

it 'keeps the macro article as the last article when the handover does not happen' do
  Ticket::DistributionMember.n2.update_all(active: false)
  EventBuffer.reset('transaction')
  apply_macro(ticket, macro, n1.user)
  last_article_id = TransactionDispatcher.get_uniq_changes(EventBuffer.list('transaction'))['Ticket'][ticket.id][:article_id]
  expect(Ticket::Article.find(last_article_id).body).to include('análise prévia')
  note = ticket.articles.find_by(internal: true)
  expect(note).to have_attributes(created_by_id: 1, sender: Ticket::Article::Sender.lookup(name: 'System'))
  expect(OnlineNotification.find_by(user_id: n1.user_id, o_id: ticket.id).type_lookup_id)
    .to eq(TypeLookup.by_name('distribution_not_handed_over'))
end
```

Os exemplos de trigger chamam `TransactionDispatcher.commit` depois de criar ou atualizar o ticket (como em
`spec/models/trigger_spec.rb:67`). Num model spec, `create(:ticket)` não despacha triggers. Chamar
`perform_changes` direto tiraria do teste a ordem alfabética dos triggers, que o spec §6.2 pede.

Outros exemplos, todos com asserção explícita de `owner_id` e `last_assigned_at`:

- **webhook "Ticket Atualizado" com o artigo da macro** (spec §5.3, item 6; `performs_jobs: true`): com um
  trigger `notification.webhook` de `ticket.action is update` ligado, o repasse não realizado seguido de
  `TransactionDispatcher.commit` enfileira `TriggerWebhookJob` com o artigo da macro como terceiro argumento,
  e não com a nota (`have_enqueued_job(TriggerWebhookJob).with(trigger, ticket, artigo_da_macro, any_args)`);
- **critério 3:** desligar `n2_a` (`update!(active: false)`) não muda o dono dos tickets que já são dele (um
  ticket aberto de `n2_a` continua com `owner_id = n2_a.user_id` depois de um repasse de outro ticket), e o
  repasse seguinte vai para outro N2;
- na Entrada por trigger, o histórico da troca de dono registra o trigger como origem (`History` com
  `sourceable` = o trigger). Para macro não há origem: `history_change_source_attribute` só aceita Job,
  Trigger, PostmasterFilter e AI::Agent (`app/models/concerns/has_history.rb:274`), e o histórico mostra o
  agente que aplicou;

- a macro com complexidade preenchida no mesmo envio (`ticket.assign_attributes(complexidades: 'facil')`
  antes de `apply_macro`) repassa ao N2 de menor carga e atualiza o `last_assigned_at` dele;
- macro de origem `macro` com `:no_n1` não acontece (só a Entrada gera); trigger de Entrada sem N1 elegível
  → dono 1 e nota "No N1 agent…";
- **Entrada por trigger** (liga o trigger semeado: `Trigger.find_by(name: 'Distribuição — Entrada')
  .update!(active: true)`): `create(:ticket, owner: outro_agente)` termina com `owner_id` = o N1 (inclusive
  ticket aberto por agente com dono escolhido); critério 1: trocar o N1 na escala e criar outro ticket → cai
  no novo N1;
- **ordem dos triggers** (spec §6.2, `performs_jobs: true`): um trigger de webhook "Ticket Criado", com
  condição `ticket.owner_id is <n1.user_id>` e ação `notification.webhook` com `create(:webhook)`, dispara
  depois da Entrada (`have_enqueued_job(TriggerWebhookJob)`). O mesmo trigger com o nome "Aaa — webhook"
  (ordena antes da Entrada) não dispara;
- **Reabertura por trigger:** ticket fechado de `n2_a` (desligado), resposta do cliente
  (`ticket.update!(state: open, updated_by_id: customer.id)` com artigo do cliente) → o dono vira o N2 de
  menor carga; o mesmo com autor agente → dono não muda;
- `handover` vindo de trigger sem complexidade → cai na Entrada e não levanta erro;
- **Review Focus 4:** macro com `perform` `{ 'distribution.ticket_distribution' => …, 'ticket.group_id' =>
  { 'value' => vendas.id } }`, nessa ordem, aplicada por `perform_changes` sem bloco (caminho do lote): o dono
  escolhido tem acesso `full` a Vendas, e um N2 com acesso só ao grupo antigo não é escolhido.

- [ ] **Step 2: Rodar e ver falhar**

Run: RSpec CI nos três arquivos.
Expected: FAIL (`uninitialized constant Ticket::PerformChanges::Action::TicketDistribution`, validator
aceitando chave vazia).

- [ ] **Step 3: Implementar com as interfaces acima**

- [ ] **Step 4: Rodar e ver passar, junto com a spec de `perform_changes` existente**

Run: RSpec CI nos três arquivos + `spec/models/ticket/perform_changes_spec.rb spec/models/trigger_spec.rb
spec/models/macro_spec.rb`
Expected: `0 failures`.

- [ ] **Step 5: Commit**

```bash
git add app/models/ticket/perform_changes/action/ticket_distribution.rb app/models/ticket/perform_changes.rb \
  app/models/ticket/distribution/{lock,notice,complexity_missing_error}.rb lib/validations/verify_perform_rules_validator.rb \
  spec/models/ticket/perform_changes/action/ticket_distribution_spec.rb spec/models/ticket/distribution/lock_spec.rb \
  spec/lib/validations/verify_perform_rules_validator_spec.rb
git commit -m "feat(distribuicao): ação de macro e trigger com trava, recusa e avisos (NDESK-70)"
```

---

### Task 7: Caminhos de macro (individual e em lote) e concorrência

**Files:**

- Create: `app/models/ticket/distribution/macro_guard.rb`
- Modify: `app/controllers/tickets_mass_controller.rb`
- Test: `spec/requests/ticket_distribution_macro_spec.rb`, `spec/models/ticket/distribution/concurrency_spec.rb`

**Interfaces:**

- Consumes: a ação (Task 6), `Lock.lock_tickets!`, `Config#complexity_of`.
- Produces:
  - `Ticket::Distribution::MacroGuard.distributes?(macro) → Boolean`: o `perform` tem a chave da distribuição;
  - `Ticket::Distribution::MacroGuard.tickets_missing_complexity(macro, tickets) → Array<Ticket>`: só para o
    modo `handover`. Conta como preenchida a complexidade que a própria macro grava em `ticket.<atributo>`;
  - `Ticket::Distribution::MacroGuard.lock_for(macro, tickets) → Array<Ticket>`: quando `distributes?(macro)`,
    devolve `Lock.lock_tickets!(tickets.map(&:id))`, ou seja, os tickets **recarregados** e travados em ordem de
    `id`; senão, devolve `tickets` como veio. Tem de ser chamado dentro de uma transação;
  - `TicketsMassController#macro`:
    - antes de `execute_transaction`, se `tickets_missing_complexity` não for vazio, responde 422 com
      `{ error:, error_human:, unprocessable_entity: ENTITY, ticket_ids: [...] }` sem escrever nada;
    - `execute_transaction(tickets, macro: nil, &)` ganha o parâmetro e, como primeira instrução da transação,
      troca `tickets` por `MacroGuard.lock_for(macro, tickets)`. A decisão usa então dono, grupo e complexidade
      lidos depois da trava, e não os do `fetch_tickets`;
    - a ação de `update` chama sem `macro:` e não muda de comportamento;
  - `TicketsController#update` não muda: a recusa sai do `with_lock` como 422 pelo handler padrão.

  O que a recusa antecipada evita: hoje uma exceção no meio do lote desfaz a transação
  (`tickets_mass_controller.rb:75`). Mas os eventos do primeiro ticket ficam no `EventBuffer`, que é por thread
  e não é limpo quando a action levanta erro (`handles_transitions.rb`). Esses eventos seriam despachados na
  requisição seguinte da mesma thread, com triggers e notificações de um repasse que não aconteceu.

- [ ] **Step 1: Request specs**

```ruby
RSpec.describe 'Ticket distribution macros', :aggregate_failures, db_strategy: :reset, type: :request do
  include_context 'with ticket distribution complexity'
  # n1, n2_a e n2_b com acesso full a group; macro handover com artigo "Realizamos uma análise prévia…"

  it 'refuses PUT /api/v1/tickets/:id without complexity and writes nothing' do
    authenticated_as(n1.user)
    EventBuffer.reset('transaction')
    expect do
      put "/api/v1/tickets/#{ticket.id}", params: { id: ticket.id, 'macro.id' => macro.id,
                                                    'macro.perform_changes' => ['distribution.ticket_distribution'],
                                                    article: { body: 'Realizamos uma análise prévia', type: 'note', internal: false } }, as: :json
    end.not_to change(Ticket::Article, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(json_response).to include('error_human' => 'Fill in the complexity before handing over.',
                                     'unprocessable_entity' => 'ticket_distribution.complexity_missing')
    expect(ticket.reload.owner_id).to eq(n1.user_id)
    expect(EventBuffer.list('transaction')).to be_empty
  end
end
```

Outros exemplos:

- o mesmo `PUT` com `complexidades: 'moderado'` no payload → 200 e dono = N2 de menor carga;
- `POST /api/v1/tickets/mass_macro` com dois tickets e um sem complexidade → 422 com
  `ticket_ids: [id_sem]`, `unprocessable_entity` igual, nenhum dos dois tickets muda (dono, artigos) e
  `EventBuffer.list('transaction')` vazio;
- `mass_macro` com os dois preenchidos e cargas iguais → os dois tickets vão para N2 diferentes (o segundo vê
  a carga do primeiro);
- `mass_macro` com uma macro que grava `ticket.complexidades` → não recusa;
- caminho dos apps Vue (`spec/graphql/gql/mutations/ticket/update_spec.rb`, contexto novo
  `'with a ticket distribution macro'`, `db_strategy: :reset`): `ticketUpdate` com `meta: { macroId: }` de
  uma macro handover, num ticket sem complexidade, devolve erro com a mensagem (não 500) e o dono não muda.

- [ ] **Step 2: Spec de concorrência**

`spec/models/ticket/distribution/concurrency_spec.rb`, com `self.use_transactional_tests = false`. Os dados
são criados e confirmados no `before`. A limpeza fica num `ensure` (dentro de um `around`):

- apaga tickets, artigos, históricos, `OnlineNotification`s, membros e usuários criados;
- restaura o Setting `ticket_distribution`;
- remove o atributo com `ObjectManager::Attribute.remove` + `migration_execute`.

Assim a coluna `complexidades` nunca vaza para as specs seguintes. Cada thread usa
`ActiveRecord::Base.connection_pool.with_connection` dentro do `ensure_threads_exited` de
`spec/support/threads.rb`. As threads são **sincronizadas** com `Queue`, para o teste falhar sem a trava:

- **dois repasses individuais em paralelo:** `allow_any_instance_of(Ticket::Distribution::Load)` segura a
  thread T1 dentro de `by_user` (sinaliza numa `Queue` e espera outra). T2 começa o repasse do outro ticket e
  precisa ficar **bloqueada** até T1 terminar (afirmar que T2 não concluiu enquanto T1 está segura). No fim,
  os dois tickets têm donos diferentes, com cargas iniciais iguais;
- **lote × individual no mesmo ticket:**
  - B faz `t2.with_lock` e sinaliza;
  - só então A roda o caminho real do lote, `ActiveRecord::Base.transaction { MacroGuard.lock_for(macro,
    [t1, t2]).each { |t| t.perform_changes(macro, 'macro', nil, n1.user_id) } }`;
  - B termina o seu `perform_changes`;
  - as duas threads terminam em até 10 s, sem `ActiveRecord::Deadlocked`, e A vê o dono que B gravou em
    `t2` (recarregado pela trava).

- [ ] **Step 3: Rodar e ver falhar**

Run: RSpec CI nos dois arquivos.
Expected:

- o lote sem complexidade falha: hoje a recusa sai da ação no meio da transação, sem `ticket_ids` e com
  eventos do primeiro ticket no `EventBuffer`;
- o lote × individual falha: `MacroGuard` não existe;
- o exemplo do GraphQL passa já (a recusa vem da Task 6) e serve de regressão.

- [ ] **Step 4: Implementar `MacroGuard` e o controller**

- [ ] **Step 5: Rodar e ver passar, com as specs vizinhas**

Run: RSpec CI nos dois arquivos + `spec/requests/ticket_spec.rb spec/requests/tickets_mass_spec.rb
spec/graphql/gql/mutations/ticket/update_spec.rb`
Expected: `0 failures` (a última confere que o caminho de macro dos apps Vue não quebrou).

- [ ] **Step 6: Commit**

```bash
git add app/models/ticket/distribution/macro_guard.rb app/controllers/tickets_mass_controller.rb \
  spec/requests/ticket_distribution_macro_spec.rb spec/models/ticket/distribution/concurrency_spec.rb
git commit -m "feat(distribuicao): recusa do lote antes de escrever e travas sem deadlock (NDESK-70)"
```

---

### Task 8: API da tela

**Files:**

- Create: `app/models/ticket/distribution/overview.rb`
- Create: `app/controllers/ticket_distribution_controller.rb`
- Create: `app/policies/controllers/ticket_distribution_controller_policy.rb`
- Create: `config/routes/ticket_distribution.rb`
- Test: `spec/models/ticket/distribution/overview_spec.rb`, `spec/requests/ticket_distribution_spec.rb`

**Interfaces:**

- Consumes: `Config`, `Eligibility`, `Load`, `Rotation`, `Ticket::DistributionMember`.
- Produces:
  - `Ticket::Distribution::Overview.new(config: Config.current, online_user_ids: nil).as_json → Hash`.
    `online_user_ids` padrão = ids de usuário em `Sessions.list` (`data.dig(:user, 'id')`). O hash:

    ```text
    config:        o Setting atual
    config_alerts: ['complexity_attribute_missing'] quando não complexity_attribute_present?
    n1_empty:      true quando não há N1
    n1:            [{ id, user_id, name, last_assigned_at, problems }]
                   problems para todos os grupos ativos
    n2:            [{ id, user_id, name, active, situation, out_of_office_end_at, points, tickets,
                      last_assigned_at, discord_uid_present, problems }]
                   situation ∈ off | out_of_office | offline | in_rotation, nessa precedência
                   problems para os grupos ativos menos o de Disparos
    dispatch:      { group_id, user_id, problems }   problems só para o grupo de Disparos
    preview_user_id: Rotation#pick(group_id: nil)&.user_id
    options:       { agents: [{ id, name }] (ativos com ticket.agent), groups, states, priorities,
                     complexity_attributes: Config.complexity_attribute_options }
    ```

  - rotas (`config/routes/ticket_distribution.rb`, molde de `config/routes/csat.rb`):
    - `GET /api/v1/ticket_distribution` → `#show`;
    - `PUT /api/v1/ticket_distribution` → `#update` (`Config.update!` com as chaves permitidas do Setting);
    - `POST /api/v1/ticket_distribution/members` → `#member_create` (`user_id`, `level`);
    - `PUT /api/v1/ticket_distribution/members/:id` → `#member_update` (`active`; num membro N1 responde 422,
      porque o N1 não tem Interruptor);
    - `DELETE /api/v1/ticket_distribution/members/:id` → `#member_destroy` (422 com
      `__('The last N1 agent cannot be removed.')` se for o último N1).

    Toda resposta de sucesso devolve o `Overview#as_json` atualizado;
  - policy `default_permit!('admin.ticket_distribution')`; o controller usa
    `prepend_before_action :authenticate_and_authorize!`.

- [ ] **Step 1: Specs**

Overview (`db_strategy: :reset`, shared context; `allow(Sessions).to receive(:list)` para o online):

- **critério 5:** `points` e `tickets` de cada N2 batem com a soma dos tickets abertos criados no exemplo;
- `situation`: desligado → `off`; `:ooo` → `out_of_office` com `out_of_office_end_at`; sem sessão →
  `offline`; com sessão → `in_rotation`;
- `discord_uid_present` falso para quem não tem ID;
- `problems` do N2 ignora o grupo de Disparos; o do responsável testa só ele;
- `preview_user_id` = o N2 de menor carga, e um N2 sem acesso a grupo nenhum continua elegível;
- escala sem N1 → `n1_empty: true`; sem o atributo → `config_alerts: ['complexity_attribute_missing']`.

Request:

- agente sem a permissão → 403; admin → 200; agente cujo papel tem `admin.ticket_distribution` → 200;
- `POST members` cria e devolve o membro; duplicado → 422;
- `PUT members/:id` com `active: false` desliga um N2; num N1 → 422;
- `DELETE` do último N1 → 422 com a mensagem; de um N2 → 200;
- `PUT` com `complexity_attribute: 'title'` → 422; com pesos e o grupo/responsável de Disparos → 200 e o
  `Setting` atualizado.

- [ ] **Step 2: Rodar e ver falhar**

Run: RSpec CI nos dois arquivos.
Expected: FAIL (rota inexistente, constante indefinida).

- [ ] **Step 3: Implementar**

- [ ] **Step 4: Rodar e ver passar**

Run: RSpec CI nos dois arquivos.
Expected: `0 failures`.

- [ ] **Step 5: Commit**

```bash
git add app/models/ticket/distribution/overview.rb app/controllers/ticket_distribution_controller.rb \
  app/policies/controllers/ticket_distribution_controller_policy.rb config/routes/ticket_distribution.rb \
  spec/models/ticket/distribution/overview_spec.rb spec/requests/ticket_distribution_spec.rb
git commit -m "feat(distribuicao): API da tela com escala, carga e alertas (NDESK-70)"
```

---

### Task 9: App clássico — editor de ações, macro, aviso fixo e sino

**Files:**

- Modify: `app/assets/javascripts/app/controllers/_ui_element/_application_action.coffee`
- Modify: `app/assets/javascripts/app/models/macro.coffee`, `app/assets/javascripts/app/models/trigger.coffee`
- Modify: `app/assets/javascripts/app/models/ticket.coffee` (`@macro` e `activityMessage`)
- Modify: `app/assets/javascripts/app/controllers/_plugin/notify.coffee`
- Modify: `app/assets/javascripts/app/controllers/ticket_zoom.coffee` (callback `error` do `submitPost`)
- Modify: `app/assets/javascripts/app/lib/mixins/ticket_mass_updatable.coffee`
- Test: `public/assets/tests/qunit/ticket_macro.js`, `public/assets/tests/qunit/form_ticket_perform_action.js`,
  `spec/system/ticket/zoom/distribution_refusal_spec.rb`

**Interfaces:**

- Consumes: a chave, os modos e a entidade de erro (restrições globais); o tipo do sino (Task 6).
- Produces:
  - **editor de ações:**
    - `ApplicationAction.@defaults` cria o grupo `distribution` (`name: __('Ticket Distribution')`, sem model)
      quando `attribute.ticket_distribution`;
    - o grupo tem um elemento `distribution.ticket_distribution`, com `tag: 'select'`, `null: false`,
      `translate: true` e as opções `entry` → `__('Entry (N1)')`, `handover` → `__('Hand over to N2')` e
      `reopening` → `__('Reopening')`, no molde de `elements['ticket.action']`;
    - `macro.coffee` e `trigger.coffee` ganham `ticket_distribution: true` no atributo `perform`;
  - **`App.Ticket.macro`:** `distribution` entra na lista de prefixos adiados, junto de `ai` e `notification`;
  - **`activityMessage`:** `when 'distribution_not_handed_over'` →
    `App.i18n.translateContent('Ticket |%s| was not handed over: no N2 agent in the rotation', item.title)`;
  - **`App.Notify`:** aceita `sticky: true`, que vira `timeout: false` no noty; o padrão de 3800 ms continua
    para o resto;
  - **`ticket_zoom` e mixin do lote:** quando `responseJSON.unprocessable_entity` é
    `'ticket_distribution.complexity_missing'`:
    - o aviso do `ticket_zoom` sai com `sticky: true` e a mensagem `error_human`; os outros erros continuam com
      2000 ms;
    - o `ErrorModal` do lote mostra `App.i18n.translateContent(error_human)` e os títulos dos tickets de
      `ticket_ids`.

- [ ] **Step 1: QUnit**

`ticket_macro.js`:

```js
QUnit.test("distribution action is deferred to the server", assert => {
  var ticket = new App.Ticket()
  App.Ticket.macro({
    ticket: ticket,
    article: {},
    macro: {
      'distribution.ticket_distribution': { value: 'handover' },
      'ticket.state_id': { value: 2 },
    }
  })
  assert.deepEqual(ticket['macro.perform_changes'], ['distribution.ticket_distribution'])
  assert.equal(ticket.state_id, 2)
})
```

`form_ticket_perform_action.js`: um `ticket_perform_action` com `ticket_distribution: true` e
`params: { perform: { 'distribution.ticket_distribution': { value: 'handover' } } }` devolve o mesmo valor em
`App.ControllerForm.params(el)`, e o seletor de atributo tem a opção `distribution.ticket_distribution`. Sem a
flag, a opção não aparece.

- [ ] **Step 2: System spec do aviso fixo**

`spec/system/ticket/zoom/distribution_refusal_spec.rb` (`db_strategy: :reset`, shared context, macro com a
ação e um artigo): N1 abre o ticket sem complexidade, aplica a macro, vê o aviso
"Fill in the complexity before handing over." e o aviso **continua visível depois de 5 s**. O dono não muda.
Clicar no aviso fecha.

- [ ] **Step 3: Rodar e ver falhar**

Run: `QUNIT_TEST=ticket_macro bundle exec rspec spec/system/js/q_unit_spec.rb`,
`QUNIT_TEST=form_ticket_perform_action bundle exec rspec spec/system/js/q_unit_spec.rb` e RSpec CI na system
spec.
Expected: FAIL nos três (prefixo não adiado, opção ausente, aviso some em 2 s).

- [ ] **Step 4: Implementar**

- [ ] **Step 5: Rodar e ver passar**

Run: os mesmos três comandos, mais `QUNIT_TEST=model_ticket` no QUnit.
Expected: `0 failures` em todos.

- [ ] **Step 6: Commit**

```bash
git add app/assets/javascripts/app/ public/assets/tests/qunit/ticket_macro.js \
  public/assets/tests/qunit/form_ticket_perform_action.js spec/system/ticket/zoom/distribution_refusal_spec.rb
git commit -m "feat(distribuicao): ação no editor, macro adiada, aviso fixo da recusa e sino (NDESK-70)"
```

---

### Task 10: Tela "Distribuição de atendimentos" e traduções

**Files:**

- Create: `app/assets/javascripts/app/controllers/ticket_distribution.coffee`
- Create: `app/assets/javascripts/app/views/ticket_distribution/index.jst.eco` (e parciais que o builder achar
  úteis, no mesmo diretório)
- Modify: `app/assets/stylesheets/zammad.scss` (bloco `.ticket-distribution`, com `@include dark` onde precisar)
- Modify: `i18n/zammad.pot` (regenerado), `i18n/zammad.pt-br.po`
- Test: `spec/system/manage/ticket_distribution_spec.rb`

**Interfaces:**

- Consumes: API da Task 8 (forma do `Overview#as_json`) e o editor da Task 9.
- Produces:
  - `App.TicketDistribution extends App.ControllerSubContent`, com `@requiredPermission:
    'admin.ticket_distribution'`;
  - entrada em `NavBarAdmin`: `{ prio: 2315, name: __('Ticket Distribution'), parent: '#manage', target:
    '#manage/ticket_distribution', controller: App.TicketDistribution, permission:
    ['admin.ticket_distribution'] }`;
  - blocos da tela, conforme o spec §7:
    - **N1 · Entrada:** lista, adicionar, remover; sem remover o último; alerta vermelho com `n1_empty`;
    - **N2 · Repasse:** Interruptor, situação, carga com barra, tickets, último repasse, ID do Discord ok ou
      "sem ID", remover, adicionar; a linha "Se um repasse acontecesse agora, iria para *fulano*" com a ressalva
      de grupo e Disparos;
    - **Disparos e campanhas:** grupo, responsável, o texto do spec e o botão Salvar;
    - **Como a carga é contada:** atributo, pesos por valor (as opções do atributo escolhido; valor sem peso
      mostra 0), estados e prioridades que não pesam, e o botão Salvar;
    - alertas por membro com os motivos de `problems`, e o `config_alerts`;
  - o Interruptor e as listas salvam na hora (`PUT`/`POST`/`DELETE`); os dois blocos com Salvar fazem
    `PUT /api/v1/ticket_distribution`. Toda resposta re-renderiza a tela com o `Overview` devolvido.
  - **Traduções:** o catálogo é regenerado com `rails generate zammad:translation_catalog` e todas as strings
    novas do plano ganham pt-BR. As fixadas pelo spec:

    | Fonte | pt-BR |
    |---|---|
    | `Ticket Distribution` | `Distribuição de atendimentos` |
    | `Fill in the complexity before handing over.` | `Preencha a complexidade antes de repassar.` |
    | `Not handed over: no N2 agent in the rotation.` | `Não repassado: nenhum N2 no rodízio.` |
    | `No N1 agent can own tickets of this group.` | `Sem N1 que possa ser dono deste grupo.` |
    | `Ticket \|%s\| was not handed over: no N2 agent in the rotation` | `O ticket \|%s\| não foi repassado: nenhum N2 no rodízio` |
    | `Discord ID` | `ID do Discord` |
    | `In rotation` / `Offline · still in rotation` / `Out of office until %s` / `Switched off` | `No rodízio` / `Offline · continua no rodízio` / `Fora do escritório até %s` / `Desligado` |
    | `No N1 agent registered` | `Nenhum N1 cadastrado` |
    | `If a handover happened now, it would go to %s` | `Se um repasse acontecesse agora, iria para %s` |

- [ ] **Step 1: System spec do caminho feliz**

`spec/system/manage/ticket_distribution_spec.rb` (`db_strategy: :reset`, shared context, admin logado):

- cadastrar um N1 e dois N2 pela tela; desligar um N2 e ver a situação "Switched off";
- a prévia mostra o N2 ligado;
- com a macro handover e um ticket com `complexidades: 'complexo'`, o N1 aplica a macro no zoom; o dono vira
  o N2 ligado; de volta à tela, a carga dele mostra `6` e `1` ticket;
- remover o único N1 não é permitido (mensagem de erro e a lista continua com ele);
- salvar os pesos com `moderado` = 4 e ver o valor persistido depois de recarregar.

- [ ] **Step 2: Rodar e ver falhar**

Run: RSpec CI em `spec/system/manage/ticket_distribution_spec.rb`
Expected: FAIL (rota `#manage/ticket_distribution` inexistente).

- [ ] **Step 3: Implementar a tela e as traduções**

- [ ] **Step 4: Rodar e ver passar**

Run: RSpec CI em `spec/system/manage/ticket_distribution_spec.rb`; `coffeelint` nos arquivos `.coffee`
tocados nas Tasks 9 e 10; `git diff --stat i18n/` mostra `zammad.pot` e `zammad.pt-br.po` alterados.
Expected: `0 failures`; coffeelint sem erros.

- [ ] **Step 5: Commit**

```bash
git add app/assets/ i18n/zammad.pot i18n/zammad.pt-br.po spec/system/manage/ticket_distribution_spec.rb
git commit -m "feat(distribuicao): tela de distribuição de atendimentos no admin clássico (NDESK-70)"
```

---

### Task 11: Changelog e regressão

**Files:**

- Modify: `.claude/NEWBYTE_WORKFLOW.md` (entrada de changelog no fim, no padrão das anteriores)

**Interfaces:**

- Consumes: tudo acima.
- Produces: branch pronta para a PR.

- [ ] **Step 1: Entrada de changelog**

Data, branch `feat/ticket-distribution`, resumo das mudanças (escala, ação, tela, ID do Discord, triggers
desligados, recusa) e a lista de arquivos, como nas entradas anteriores. Registre que a virada é manual
(Task 12) e que os triggers nascem desligados.

- [ ] **Step 2: Regressão ampla**

Run (RSpec CI, depois de `rm -f db/schema.rb`): `spec/models/ticket/ spec/models/ticket_spec.rb
spec/models/user_spec.rb spec/models/user/ spec/models/trigger_spec.rb spec/models/macro_spec.rb
spec/models/system_report_spec.rb spec/requests/ticket_spec.rb spec/requests/tickets_mass_spec.rb
spec/requests/ticket_distribution_spec.rb spec/requests/ticket_distribution_macro_spec.rb spec/db/
spec/lib/validations/ spec/jobs/trigger_webhook_job/ spec/graphql/gql/mutations/ticket/
spec/system/manage/ticket_distribution_spec.rb spec/system/ticket/zoom/distribution_refusal_spec.rb`; QUnit
completo (`bundle exec rspec spec/system/js/q_unit_spec.rb`); `bundle exec rubocop` nos `.rb` do
`git diff --name-only origin/newbyte-stable`.
Expected: `0 failures` e `no offenses detected`. Falha fora dos arquivos do plano: confira se é
pré-existente (rodando na `origin/newbyte-stable`) e relate.

- [ ] **Step 3: Rascunho do "Como testar" da PR**

Escrever o rascunho do corpo da PR (template `references/pr-template.md` da skill `dev-execution`) em
`$SCRATCHPAD/pr-body.md`. Ele fica fora do repositório até a PR ser autorizada. O "Como testar" copia, completas e
com os nomes exatos, as subseções "Montagem do cenário no preview" e "O que testar" do Roteiro de QA abaixo.
Os critérios de aceite vão um por linha, como no Plane. O critério 6 vai marcado como dependente da virada.

- [ ] **Step 4: Commit**

```bash
git add .claude/NEWBYTE_WORKFLOW.md
git commit -m "docs(workflow): changelog da distribuição de atendimentos (NDESK-70)"
```

---

### Task 12 (manual, na virada): n8n e ligar a distribuição

Não é tarefa de código. Ela roda depois do merge e do deploy (fase Release), por alguém com acesso ao n8n e
ao admin de produção. **Quem é ainda está em aberto: o time define antes da Release.** O fechamento do
critério 6 depende desta tarefa. A fonte é o spec §8.1 e §8.3; a lista abaixo é a ordem de execução.

- [ ] Conferir que o atributo `complexidades` de produção é do tipo `select` (seleção simples), com as
  chaves `facil`, `moderado` e `complexo`. A tela só aceita `select`; se for outro tipo, pare e reabra a task
  antes da virada.
- [ ] Guardar os três exports atuais do n8n num cofre (nunca no git) e apagar do Downloads. Eles carregam o
  token da API do NDesk em texto; ler só com script que mascara (`python3 -I`).
- [ ] Deploy feito com os dois triggers desligados e a macro de análise prévia sem a ação: nada muda.
- [ ] Configurar a escala: IDs do Discord dos agentes, N1, N2, grupo e responsável de Disparos, atributo e
  pesos, e os estados e prioridades que não pesam ("Melhoria", "4 sem previsão"). Resolver todos os alertas da
  tela.
- [ ] Revisar os triggers ativos de produção: condições sobre o dono e ações que mudam grupo ou estado na
  criação e na atualização (spec §6.2).
- [ ] Garantir que todos os agentes recarreguem o NDesk (aba com JS antigo não manda a ação).
- [ ] Fora do pico, nesta ordem:
  1. ligar "Distribuição — Entrada" e "Distribuição — Reabertura";
  2. incluir a ação "Ticket Distribution → Hand over to N2" na macro de análise prévia;
  3. publicar o "NDesk - Notificações" com o roteiro nó a nó do spec §8.1 (as cinco linhas da tabela, cada
     remoção com a religação);
  4. desativar "LB - Atribuição de Ticket" e "LB - Liberação de Pontos".
- [ ] Rodar o checklist do spec §8.2 e revisar os tickets criados ou repassados na janela.
- [ ] Trocar o token da API do NDesk usado pelo n8n.
- [ ] Rollback (se preciso), conforme o spec §8.3, item 7:
  - desligar os triggers e tirar a ação da macro;
  - atualizar a `carga_atual` da data table `load_balancer` com a carga da tela;
  - reimportar os três exports.

## Roteiro de QA (NDESK-73)

Quem faz o QA não é quem desenvolveu e chega só com a PR. Esta seção vira o "Como testar" do corpo da PR
(Task 11, Step 3).

### Montagem do cenário no preview

O preview da PR (`ndesk-pr-N.staging-preview.newbyte.net.br`) é uma instalação nova. Ele não tem nada do que
existe só em produção.

1. Rodar o assistente de configuração do preview (ele fica em `setup_done: false` até alguém rodar).
2. **Admin › Sistema › Objetos › Ticket:** criar o atributo `complexidades`, do tipo seleção, com os valores-chave
   `facil`, `moderado` e `complexo` (as chaves precisam ser exatamente essas, porque são as dos pesos
   padrão), visível na edição do ticket para agentes. Aplicar as mudanças do ObjectManager.
3. Criar um estado "Melhoria" (categoria aberta) e uma prioridade "4 sem previsão", para testar o que não pesa.
4. Criar dois grupos ("Suporte" e "Disparos e campanhas") e cinco agentes:
   - um N1 com acesso total aos dois grupos;
   - três N2 com acesso total ao Suporte;
   - um agente "Engenharia", fora das listas.
   Um N2 recebe um ID do Discord no cadastro e os outros ficam sem.
5. **Admin › Gerenciar › Distribuição de atendimentos:** cadastrar o N1 e os três N2, escolher o grupo e o
   responsável de Disparos e marcar "Melhoria" e "4 sem previsão" como estados/prioridades que não pesam.
6. **Admin › Macros:** criar a macro "Análise prévia" com um artigo público cujo texto começa com
   "Realizamos uma análise prévia da sua ocorrência" e a ação **Ticket Distribution → Hand over to N2**.
7. **Admin › Trigger:** ligar "Distribuição — Entrada" e "Distribuição — Reabertura", que já vêm criados e
   desligados.

### O que testar

- Critérios 1 a 5 da task, pela tela e por tickets criados no preview:
  - criar tickets: todos caem no N1;
  - trocar o N1;
  - repassar com cargas diferentes e com empate;
  - desligar um N2 e pôr outro em "Fora do escritório";
  - comparar a carga da tela com a soma dos tickets.
- A recusa sem complexidade, individual e em lote: o aviso fica até ser fechado e nada é gravado. Testar em
  Chrome, Firefox e Safari.
- Repasse não realizado (todos os N2 desligados): nota interna do Sistema, sino para quem aplicou e dono
  inalterado.
- Reabertura pelo cliente (responder um ticket fechado): volta para quem atendeu. Com quem atendeu
  desligado, vai para outro N2. Reabertura por agente não mexe no dono.
- Disparos: ticket do grupo de Disparos repassado vai para o responsável.
- Exclusão de um agente que está na escala: ele some das listas e a tela mostra os alertas.

### Critério 6 (e-mails e Discord) — depende da virada

O n8n aponta para produção, então o critério 6 não é testável no preview. No QA ele sai **com ressalva**: o
lado do NDesk é conferido no preview (o payload do webhook leva `owner.discord_uid`). O checklist do spec §8.2
roda em produção depois da virada (Task 12, fase Release), por quem tiver acesso ao n8n.

### O que conferir em produção (spec §12)

- a categoria de "Aguardando cliente" e dos estados de "Melhoria";
- os grupos com follow-up que cria ticket novo;
- as condições do trigger "Ticket Atualizado";
- quem é o usuário 11.
