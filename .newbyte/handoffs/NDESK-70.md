# Handoff — NDESK-70 — [NDesk] Distribuição de atendimentos

> Gerado em 2026-10-28 17:38. Consumido pelo fluxo Desenvolvimento → Handoff do
> plugin New Byte. Fonte da verdade sobre estado da task: o Plane.

## Task
- Identificador: NDESK-70
- Link: https://plane.byte.newbyte.net.br/engenharia/browse/NDESK-70/
- Projeto: NDesk
- Sub-itens:
  - Planning NDESK-71: **Done**;
  - Execution NDESK-72, QA NDESK-73 e Release NDESK-74: Backlog.
- Task principal em In Progress, com a etiqueta **Execution**. Conferido em 2026-10-28.

## Fase atual
Execution — ainda não iniciada. Ao retomar, entrar na `dev-execution` pelo início:
- NDESK-72 → In Progress, atribuída ao usuário;
- execução do plano pela Task 0.

O Planning terminou em 2026-10-28:
- spec v2.1 e plano aprovados pelo usuário;
- os dois publicados na descrição do NDESK-71 (`nb-pub v1`, hashes `75367a44ae4e` do spec e `ed13ff3bf608` do
  plano, com leitura de volta conferida);
- NDESK-71 em Done e etiqueta trocada de Planning para Execution.

## O que já foi feito
- **Spec v2 aprovado** pelo usuário em 2026-10-28. Na revisão, o usuário confirmou duas regras:
  - N2 offline continua no rodízio;
  - no repasse não realizado, o cliente recebe a mensagem da macro e o "em andamento", e o aviso é só interno.
- **Spec v2.1:** o atributo do Discord passou de `discord_id` para `discord_uid` (decisão do usuário sobre o
  achado crítico do grill do plano).
- **Plano** escrito com a skill writing-plans: 13 tarefas (0 a 12), autorrevisado e passado por um grill num
  agente separado em modelo Claude (o usuário escolheu Claude; o Clodex não está instalado). O grill deu 1
  crítico, 2 altos, 5 médios e 10 baixos, todos incorporados. Um deles foi ajustado depois de conferido no
  código: a origem no histórico só vale para trigger, não para macro (`has_history.rb:274`).
- **Commits locais** na `feat/ticket-distribution`, sem push:
  - `fbcb9b5d01`: spec, `docs/distribuicao/` (CONTEXT e ADRs 0001–0004) e `docs/pesquisas/`;
  - `695c56d196`: plano e spec v2.1.
- **Publicação no Plane** feita por REST (PATCH) com leitura de volta pela mesma API. O payload tem 141.657
  bytes.

## Decisões tomadas (e por quê)
- **`discord_uid` em vez de `discord_id`:** o Zammad trata toda coluna `*_id` como relação. O histórico grava
  o valor num inteiro de 4 bytes, e um ID do Discord tem 17 a 19 dígitos; o ObjectManager também recusa nomes
  `*_id`. O n8n passa a ler `ticket.owner.discord_uid`.
- **Triggers "Distribuição — Entrada/Reabertura" nos seeds também**, desligados, e não só na migração. O
  preview da PR é uma instalação nova e precisa deles para o QA.
- **QA é de outra pessoa:** o plano tem um "Roteiro de QA" completo, com a montagem do cenário no preview.
  Ele vira o "Como testar" da PR; o rascunho do corpo da PR é feito na Task 11, Step 3.
- **Critério 6 sai com ressalva no QA**, porque o n8n aponta para produção. O checklist do spec §8.2 roda
  depois da virada (Task 12, fase Release).
- **Ajustes do plano em relação ao spec**, registrados na seção "Ajustes em relação ao spec" do plano. Os
  principais:
  - o editor de macro e trigger é o `_application_action.coffee`;
  - a ação roda por último no `before_save`;
  - ordem das travas: linhas de ticket primeiro, advisory lock por último;
  - savepoint no caminho de trigger;
  - a escala fica fora do JSON de usuário.

## Próximos passos
1. Ligar a integração WSL do Docker Desktop (Settings › Resources › WSL Integration) e subir o devcontainer
   `.devcontainer/with-selenium`. Todos os testes do plano rodam dentro dele. Sem isso, a Task 0 para no Step 2.
2. `/newbyte:newbyte` → Desenvolvimento → NDESK-70 → Handoff → `dev-execution`: NDESK-72 → In Progress e
   execução por `superpowers:subagent-driven-development`, a partir da Task 0 do plano.
3. Ao fim da execução, seguir a `dev-execution`:
   - review de código num agente separado (perguntar de novo OpenAI × Claude);
   - teste visual;
   - PR só com autorização, com o corpo rascunhado na Task 11, Step 3.
4. Antes do push, conferir a permissão de escrita (`gh api repos/newbytesolucoesdigitais/ndesk --jq
   .permissions.push`). Se der `false`, pedir acesso ou abrir a PR de um fork.
5. Quando a PR abrir, passar a URL e o identificador NDESK-70 para a pessoa do QA (`/newbyte:newbyte` → Review
   + QA).

## Arquivos relevantes
- `docs/plans/2026-10-20-distribuicao-atendimentos-design.md` — spec v2.1 (fonte da verdade da regra).
- `docs/plans/2026-10-20-distribuicao-atendimentos.md` — plano aprovado (13 tarefas; Task 12 é manual).
- `docs/distribuicao/CONTEXT.md` e `docs/distribuicao/adr/0001…0004` — glossário e decisões de domínio.
- Pontos de integração citados no plano:
  - `app/models/ticket/perform_changes.rb`;
  - `app/controllers/tickets_mass_controller.rb`;
  - `app/assets/javascripts/app/controllers/_ui_element/_application_action.coffee`;
  - `app/assets/javascripts/app/models/ticket.coffee`;
  - `app/assets/javascripts/app/controllers/_plugin/notify.coffee`.

## Artefatos
- Spec: `docs/plans/2026-10-20-distribuicao-atendimentos-design.md` (v2.1, aprovado)
- Plano: `docs/plans/2026-10-20-distribuicao-atendimentos.md` (aprovado)
- Publicação no Plane: publicado (fim do Planning), na descrição do NDESK-71
- Branch: `feat/ticket-distribution` (base `origin/newbyte-stable` @ `31f0e2b171`, ainda igual em 2026-10-28)
- PR: não aberta
- Estado do git:
  - branch **só local, sem push** (sem upstream), com os commits `fbcb9b5d01` e `695c56d196`;
  - untracked: este handoff, `.newbyte/qa/` e `.superpowers/` (os dois últimos não devem ser commitados; o
    `.superpowers/` não está no `.gitignore`).

## Pegadinhas / contexto que se perde
- **Esta máquina (WSL) não tem Ruby, PostgreSQL, Redis nem Docker no WSL.** O Docker Desktop está instalado no
  Windows, mas a integração WSL está desligada. O CI do GitHub só roda em PR (`ci-test.yml`), então não serve
  de atalho antes da PR.
- **Clodex/`nb-review` não está instalado.** Os dois grills (spec e plano) rodaram em Claude por escolha do
  usuário. O review de código da Execution deve perguntar de novo.
- **MCP do Plane:**
  - pode dar timeout na abertura da sessão; resolve com `/mcp` → reconectar `plugin:newbyte:plane`;
  - PQL (`childOf`) não funciona nesta edição: filtrar sub-itens no cliente;
  - `retrieve_work_item` com `fields=labels` falha na validação: usar `expand=labels`;
  - `update_work_item` no NDESK-71 devolve a descrição publicada inteira (~140 KB) e estoura a saída. Não é
    erro: o resultado vai para um arquivo.
- **Republicação no fim da Execution:** se o spec ou o plano mudarem, a `dev-execution` republica. O conversor
  markdown→HTML desta sessão ficou só no scratchpad, que é temporário: será preciso um novo (sem biblioteca de
  markdown no Python da máquina), seguindo a tabela do `publicar-plane.md`. Tabelas dentro de itens de lista
  existem no plano (traduções da Task 10).
- **Exports do n8n** em `/mnt/c/Users/d4np/Downloads/` (`NDesk - Notificações.json`,
  `LB - Atribuição de Ticket.json`, `LB - Liberação de Pontos.json`) têm o token da API do NDesk em texto. Ler
  sempre com script que mascara (`python3 -I`) e nunca imprimir headers. Eles são necessários para o rollback
  (spec §8.3).
- **Quem faz a virada (Task 12) ainda não foi definido**: precisa de acesso ao n8n. O primeiro item da Task 12
  é conferir que o `complexidades` de produção é `select` com as chaves `facil`, `moderado` e `complexo`.
- **Rails 8.1:** rodar `rm -f db/schema.rb` antes dos testes. O banco de teste é montado por migrations.
- O spec tem a data 2026-10-20 no nome; o desenho começou em 2026-10-16 e a aprovação foi em 2026-10-28.
