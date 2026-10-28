# Spec — Distribuição de atendimentos N1/N2 (NDESK-70)

- **Task:** [NDESK-70](https://plane.byte.newbyte.net.br/engenharia/browse/NDESK-70/) · `[NDesk] Distribuição de atendimentos`
- **Data:** 2026-10-20 (desenho iniciado em 2026-10-16) · **Fase:** Planning · **Revisão:** v2.1 (v1 passou pela
  leitura de um builder independente e pelo grill-with-docs com modelo Claude — o Clodex não está instalado
  nesta máquina e o usuário escolheu seguir com Claude; v2 incorpora os achados e as decisões do usuário;
  v2.1, de 2026-10-28, troca o nome técnico `discord_id` por `discord_uid`, por decisão do usuário sobre um
  achado do grill do plano)
- **Branch:** `feat/ticket-distribution` (base `origin/newbyte-stable` @ `31f0e2b171`, tag `nb.v1.6.1`)
- **Glossário:** [`docs/distribuicao/CONTEXT.md`](../distribuicao/CONTEXT.md) · **ADRs:** [`docs/distribuicao/adr/`](../distribuicao/adr/)
- **Pesquisa de mercado:** `docs/pesquisas/pesquisa-load-balancer-atendimento.md`

Convenção deste documento: o que o usuário decidiu aparece como regra. O que foi decisão de quem escreveu o
spec aparece marcado **(decisão do spec)** e pode ser contestado na revisão.

## 1. Problema

Um atendente novo vai assumir o N1 e o time de N2 vai crescer. Hoje a distribuição vive no n8n
(`auto.newbyte.net.br`), espalhada em três fluxos, com agentes fixos no código dos nós:

| Fluxo n8n | O que faz hoje | Agente fixo |
|---|---|---|
| "NDesk - Notificações" (`d7LWYGViZwO7MUwj`) | Recebe os webhooks do NDesk (header `x-zammad-trigger`: Ticket Criado/Atualizado/Fechado/Reaberto). Na criação, o nó "adiciona Marcus" grava `owner_id 585`. No "Ticket Atualizado", o `Switch1` classifica o artigo pelo texto: "Realizamos uma análise prévia da sua ocorrência" chama o LB. O que não casa com nenhum texto cai no nó "É o suporte?", que decide se a resposta é do suporte pelo autor do artigo. No "Ticket Fechado", chama a Liberação de Pontos e depois manda o e-mail de fechamento ("Send email2"). Menciona o dono no Discord por um switch de nomes com `<@id>` fixo. | N1 = 585; suporte = 11, 5 e 6; Discord por nome |
| "LB - Atribuição de Ticket" (`yNJPRYAPJcfZzjFV`) | Pontua por `complexidades` (facil 1, moderado 3, complexo 6) e guarda a carga na data table `load_balancer` (agent_id, agent_name, carga_atual, ultimo_atribuido). Nó "É disparo?": grupo "Disparos e campanhas – Disparo de mensagens em massa" vai para o agente 6 (e zera o 5). | N2 = 5 e 6; Disparos = 6 |
| "LB - Liberação de Pontos" (`oBok5knogJLEF6G3`) | Sub-fluxo chamado no fechamento. Subtrai os pontos da complexidade *atual* do ticket da `carga_atual` do dono, só se ele for 5 ou 6. | `agentesLB = [5, 6]` |

Consequências: trocar o N1 ou incluir alguém no N2 exige editar o n8n; com três ou mais agentes o LB
escolhe errado (o empate pega o primeiro com `ultimo_atribuido=false` da lista toda; com todos `true`,
`agentes[-1]`); um N2 novo não é reconhecido como suporte; ninguém vê a carga de ninguém; a carga deriva —
ticket reaberto não volta a somar, e se a complexidade muda durante o atendimento a liberação subtrai outro
valor.

## 2. Objetivos, não-objetivos e anti-objetivos

**Objetivos** (critérios de aceite da task, numerados como no Plane):

1. Trocar o N1 na tela vale para o próximo ticket criado, sem editar o n8n.
2. Agente incluído no N2 pela tela passa a receber repasses, com 3 ou mais agentes no rodízio.
3. Agente desligado do rodízio para de receber novos tickets; os que já estão com ele ficam com ele.
4. Empate na menor carga vai para quem está há mais tempo sem receber.
5. A tela mostra a carga atual de cada N2, igual à soma dos pontos dos tickets abertos dele.
6. Nenhuma regressão nos e-mails de notificação nem no aviso do Discord, que menciona o dono atribuído,
   inclusive agentes novos.

**Não-objetivos:** skills/especialidades, agente preferencial por cliente, transbordo entre filas; mudanças
nos e-mails ao cliente e na regra de horário de atendimento do n8n; distribuição de conversas do NChat.

**Anti-objetivos** (falharia mesmo "funcionando"):

- NDesk e n8n atribuindo ao mesmo tempo: o n8n chama a API depois e sobrescreve o dono.
- O cliente receber "Realizamos uma análise prévia" enquanto o ticket fica parado porque faltou a
  complexidade.
- Ticket ficar sem dono em silêncio.
- O cliente parar de receber o e-mail de abertura, de atualização ou de fechamento depois da virada (§8.1).
- A distribuição desfazer uma escolha de dono feita por uma pessoa.

## 3. Abordagem

**O NDesk é dono da escala e executa a atribuição.** O n8n deixa de atribuir e fica com o que já fazia além
disso: e-mails, mensagens de horário, Discord e as automações de estado (por exemplo, encerrar depois de 48 h).
Motivos: uma fonte da verdade; regra testada (o bug dos dois agentes nasceu num JS de n8n sem teste); a
atribuição deixa de depender do texto do artigo. Ver ADR 0001.

Rejeitadas:

- O n8n continuar atribuindo e só ler a escala do NDesk por API. Mantém a regra sem teste e duas pontas para
  manter.
- O NDesk mandar um aviso próprio "Ticket Repassado" ao n8n, no lugar do reconhecimento pelo texto. Rejeitada
  pelo usuário: o n8n continua reconhecendo o repasse pelo texto para o Discord e o e-mail, como já faz com as
  outras macros (§6.4, ADR 0004).

A configuração e a tela ficam **só no admin clássico** (CoffeeScript/Spine). O NDesk não usa os apps Vue
para isso (`.claude/NEWBYTE_WORKFLOW.md`; mesmo motivo de `docs/csat/adr/0001-csat-na-ui-classica.md`).

## 4. Modelo de dados e configuração

- **Tabela `ticket_distribution_members`:** `user_id`, `level` (`n1` | `n2`), `active` (o interruptor
  "No rodízio"; só tem efeito no N2), `last_assigned_at` (nulo = nunca recebeu), timestamps. Uma linha por
  pessoa por nível, então a mesma pessoa pode estar nos dois. Único em (`user_id`, `level`).
  - Com o Rails 8.1 e `load_defaults 8.1`, finders sem ordem em model sem chave primária levantam erro: a
    tabela tem `id`.
  - **Exclusão de usuário:** os registros saem junto com o usuário, antes de
    `User#destroy_move_dependency_ownership` (`app/models/user.rb:1065`), que levanta "Failed deleting
    references!" para qualquer coluna `user_id` que ainda aponte para ele. Isso também vale para a
    DataPrivacyTask. As specs que enumeram modelos e referências são atualizadas, como no commit do CSAT
    `0c96a70da0`.
- **Setting(s)** (o formato — um hash ou várias chaves — fica com o builder):
  - o atributo de complexidade, escolhido na tela entre os atributos de ticket do tipo seleção do
    ObjectManager (padrão `complexidades`), para um erro de digitação não recusar toda macro;
  - pesos por valor (padrão `facil` 1, `moderado` 3, `complexo` 6 — as chaves são os valores gravados no
    ticket, como no LB);
  - IDs de estados que não pesam e IDs de prioridades que não pesam (escolhidos na tela; em produção serão
    "Melhoria" e "4 sem previsão");
  - grupo de Disparos e o usuário responsável. Se o responsável for excluído, o campo é limpo e os Disparos
    seguem o rodízio do N2 até alguém escolher outro.
- **Atributo de usuário "ID do Discord"** (`discord_uid`, via ObjectManager, só dígitos, editável no cadastro
  de agentes no admin; não aparece nas telas de cliente). Precisa ser atributo real e não `preferences`: o
  payload do webhook leva `ticket.owner` com os atributos, mas filtra `preferences`
  (`app/jobs/trigger_webhook_job/record_payload/base.rb`, `USER_ATTRIBUTE_FILTER`).
  O nome técnico não termina em `_id`: o Zammad trata toda coluna `*_id` como relação (o histórico grava o
  valor num inteiro de 4 bytes, e um ID do Discord tem de 17 a 19 dígitos; o ObjectManager recusa o nome).
  **(decisão do usuário em 2026-10-28, revisão v2.1)**
- **Permissão `admin.ticket_distribution`:** vem com o perfil Admin e pode ser dada a outros perfis. Quem a
  tem vê a tela e a carga.

Nada específico de produção vai escrito no código: o atributo `complexidades`, os estados ("Aguardando
cliente", "Melhoria", "Em andamento"…) e as prioridades ("4 sem previsão") só existem no banco de produção.

## 5. Regras de atribuição

### 5.1 Quem pode ser dono

O Zammad zera o dono (vira `owner_id 1`, "sem dono") num update se ele não estiver ativo, não tiver
`ticket.agent` ou não tiver acesso `full` ao grupo do ticket (`Ticket#check_owner_active`,
`app/models/ticket.rb:755`). Por isso **todo candidato passa por esse mesmo filtro** antes de qualquer outra
regra; quem não passa é pulado, nunca escolhido. **(decisão do spec)**

### 5.2 Entrada (ticket novo → N1)

- **Todo** ticket novo entra pelo N1: inclusive os abertos por um agente (mesmo com dono escolhido), os
  divididos (split) e os do grupo de Disparos. **(decisão do usuário)**
- O N1 recebe **em qualquer estado**: online, offline, deslogado, com "Fora do escritório" ativo. Não há
  substituto e não há interruptor no N1. **(decisão do usuário em 2026-10-20; substitui o "N1 ausente → vai
  para o substituto" registrado no handoff de 2026-10-16)**
- Com mais de uma pessoa no N1, vale a **vez do N1**: recebe quem está há mais tempo sem receber
  (`last_assigned_at` mais antigo; nulo primeiro; empate final pelo `id` do membro **(decisão do spec)**).
  Atualiza o `last_assigned_at` do N1.
- Se nenhum N1 passar no filtro de §5.1, o ticket fica sem dono, recebe uma nota interna "Sem N1 que possa
  ser dono deste grupo" e o fato vai para o log. A prevenção fica na tela (alerta por membro, §7).
  **(decisão do spec)**

### 5.3 Repasse (macro de análise prévia → N2)

1. **Sem complexidade, não há repasse:** a macro é recusada (§6.3). O N1 preenche e clica de novo. O valor
   lido é o do ticket em memória, já com o que veio no mesmo envio (`tickets_controller.rb#update` faz
   `assign_attributes` antes da macro), para o N1 poder preencher e aplicar a macro de uma vez.
2. **Reaplicação:** se o dono atual já é membro do N2, está no rodízio, passa em §5.1 e não é quem está
   repassando, ele continua dono e o `last_assigned_at` não muda. Evita que um segundo clique mova o ticket
   de um N2 para outro. **(decisão do spec)**
3. **Disparos:** se o grupo do ticket é o grupo de Disparos configurado, o ticket vai para o responsável de
   Disparos. Soma na carga dele, mas **não** atualiza o `last_assigned_at` do N2. O interruptor do N2 não
   vale para essa função: para parar os Disparos, troca-se o responsável **(decisão do spec)**. Se o
   responsável estiver com "Fora do escritório", não passar em §5.1 ou não estiver definido, segue a regra
   normal do N2 abaixo.
4. **Candidatos do N2:** membros `n2` com o interruptor ligado, **sem** "Fora do escritório" valendo
   (`User#out_of_office?`), que passam em §5.1, **menos quem está repassando** (o usuário que aplicou a
   macro). Offline ou deslogado **continua** candidato.
5. Recebe o candidato de **menor carga** (§5.5), sem contar o próprio ticket. Empate: `last_assigned_at`
   mais antigo, nulo primeiro; empate final pelo `id` do membro **(decisão do spec)**. Atualiza o
   `last_assigned_at` do N2.
6. **Repasse não realizado** (nenhum candidato: todos desligados ou com "Fora do escritório"):
   - a macro **passa** — o cliente recebe a mensagem e os campos mudam —, e o dono não muda;
   - entra uma nota **interna**, de autoria do Sistema (usuário 1): "Não repassado: nenhum N2 no rodízio";
   - quem aplicou a macro recebe uma notificação no sino do NDesk (`OnlineNotification`) **(o canal é
     decisão do spec)**. O `OnlineNotification` não guarda texto: a mensagem é montada no cliente pelo tipo
     (`activityMessage` em `app/assets/javascripts/app/models/ticket.coffee`), então isso exige um tipo novo
     e o render correspondente;
   - quando alguém do N2 voltar, o ticket é passado **à mão**, trocando o proprietário; não há macro nem
     botão de "repassar de novo" **(decisão do usuário)**. A atribuição manual não mexe no
     `last_assigned_at`.
   - **A nota não pode esconder o artigo da macro.** Numa requisição, o `TransactionDispatcher` funde os
     eventos e guarda só o último `article_id` (`lib/transaction_dispatcher.rb`, `get_uniq_changes`), e o n8n
     reconhece o repasse pelo texto desse artigo (§6.4). Uma nota criada no `after_commit` ainda cai no mesmo
     buffer da requisição (`handles_transitions.rb` só despacha depois da action). Por isso a nota é criada
     na fase `before_save`, antes do artigo da macro, ou num job assíncrono. Teste: o webhook "Ticket
     Atualizado" sai com o artigo da macro.

### 5.4 Reabertura

- **O que é reabertura:** o estado sai de uma categoria `closed` para uma categoria aberta — nem `closed`, nem
  `merged`, nem `removed` (a mesma definição de "aberto" de §5.5). Mesclar ou remover um ticket fechado não é
  reabertura (`Ticket#merge_to` aceita ticket fechado como origem). Sair de "pendente fechar" também não.
  **(decisão do spec)**
- **Só quando quem reabre é o cliente** — resposta ou follow-up; tecnicamente, o autor da mudança não tem
  `ticket.agent`. Quando um agente reabre, inclusive escolhendo o dono no mesmo salvamento, vale o que ele fez.
  **(decisão do usuário)**
- O Zammad não tem evento de reabertura, e as condições do trigger "Ticket Reaberto" de produção não são
  visíveis daqui. Por isso **a própria ação confere a transição e o autor** pelas mudanças do contexto
  (`changes['state_id']`) e não faz nada fora disso. O trigger criado pela migração usa só condições
  genéricas (ticket atualizado, estado mudou), sem ID de estado de produção.
- **Quem atendeu** é o dono de antes da reabertura: o valor anterior em `changes['owner_id']`, se houver,
  senão o dono atual. Em grupo com "Atribuir follow-ups" desligado, o `Channel::Filter::FollowUpAssignment`
  zera o dono no follow-up por e-mail antes dos triggers; a regra "volta para quem atendeu" vale também nesses
  grupos. **(decisão do spec)**
- **Quem atendeu continua dono** se passa em §5.1 e:
  - é membro do N1 (que recebe em qualquer estado); ou
  - é membro do N2 com o interruptor ligado e sem "Fora do escritório"; ou
  - não está em nenhuma lista (por exemplo, Engenharia ou um gestor): alguém o escolheu de propósito.
    **(decisão do usuário)**
- Senão (saiu do rodízio do N2 ou não pode mais ser dono), passa pela regra do Repasse (§5.3, itens 3 a 5),
  sem excluir ninguém por "quem repassa". Atualiza o `last_assigned_at` do N2, porque é um recebimento pelo
  rodízio. **(decisão do spec)**
- Fallbacks, já que trigger não recusa **(decisão do spec)**:
  - sem complexidade → regra de Entrada (§5.2);
  - nenhum N2 no rodízio → regra de Entrada (§5.2), nota interna "Não repassado: nenhum N2 no rodízio" e
    notificação no sino para o N1 que recebeu.

### 5.5 Carga

- Calculada **na hora**, sem contador gravado: soma dos pesos da complexidade dos tickets de que o agente é
  dono, em estado **aberto**, de qualquer grupo (os Disparos entram na carga do responsável). Ver ADR 0002.
- "Aberto" = estado cuja categoria (`state_type`) não é `closed`, `merged` nem `removed`. Inclui as
  categorias de pendência, onde deve ficar "Aguardando cliente" (confirmar em produção, §12).
  **(decisão do spec)**
- Não pesam: tickets em estados ou prioridades marcados na tela.
- Ticket sem complexidade pesa 0. Valor de complexidade sem peso cadastrado pesa 0 e vai para o log uma vez
  por decisão, não por ticket.
- Ao decidir para um ticket, ele mesmo fica fora da soma.
- Resolve o drift de hoje: reaberto volta a pesar sozinho; fechado sai sozinho; mudança de complexidade vale
  na hora.

### 5.6 Concorrência

Dois repasses simultâneos veriam a mesma menor carga. A escolha do N2 (e da vez do N1) acontece sob uma trava
que serializa as decisões de distribuição e dura até o commit do dono escolhido; senão, o segundo repasse lê a
carga antiga. O mecanismo (lock de linhas da tabela ou advisory lock do Postgres) e a **ordem de aquisição**
ficam com o builder, com um requisito: a macro em lote (§6.1), que trava vários tickets na mesma transação, não
pode entrar em deadlock com uma macro individual. Teste dos dois caminhos em paralelo.

## 6. Integração

### 6.1 Ação "Distribuição de atendimentos"

Uma ação nova de `perform_changes`, configurável em macros e triggers, com um modo: **Entrada**,
**Repasse ao N2** ou **Reabertura**.

- Se pluga como a ação de IA: roteamento por prefixo em `app/models/concerns/can_perform_changes.rb`
  (`prepare_actions`, lista `action_checks`), classe em `app/models/ticket/perform_changes/action/`, fase
  `before_save` (molde: `ai_agent.rb`), para o dono escolhido ser gravado no mesmo save.
- O editor de ações do admin clássico ganha a entrada correspondente
  (`app/assets/javascripts/app/controllers/_ui_element/object_perform_action.coffee`, onde a IA aparece).
- **Macro individual no app clássico:** `App.Ticket.macro` aplica quase tudo no navegador e só manda ao
  servidor os prefixos `ai` e `notification` (`app/assets/javascripts/app/models/ticket.coffee`, fim de
  `@macro`). O prefixo novo entra nessa lista. O servidor só executa as chaves que recebeu em
  `macro.perform_changes` e roda a macro dentro de `ticket.with_lock`, junto do save e do artigo
  (`app/controllers/tickets_controller.rb`, `update`). Consequência para a virada: uma aba aberta com o JS
  antigo não manda o prefixo novo, e a ação some em silêncio (§8.3).
- **Macro em lote:** aplicar a macro a vários tickets na visão geral usa `POST /api/v1/tickets/mass_macro`
  (`app/controllers/tickets_mass_controller.rb#macro`), que roda a macro inteira no servidor, todos os tickets
  numa transação. A recusa (§6.3) recusa o lote inteiro, e a mensagem precisa aparecer: hoje o app clássico
  mostra só o texto do status HTTP (`app/assets/javascripts/app/lib/mixins/ticket_mass_updatable.coffee`).
  **(decisão do spec)**
- A ação roda no servidor, então funciona de qualquer cliente que aplique a macro pelo `perform_changes`.
  O compromisso é com o app clássico; o builder confere que o caminho de macro dos apps Vue não quebra.

### 6.2 Triggers

- Uma migração cria **desligados** dois triggers: "Distribuição — Entrada" (ticket criado, modo Entrada) e
  "Distribuição — Reabertura" (ticket atualizado com o estado mudado, modo Reabertura; a ação filtra a
  transição e o autor, §5.4). Eles são ligados na virada (§8.3).
- **Ordem:** os triggers rodam em ordem alfabética de nome (`app/models/transaction/trigger.rb`,
  `reorder LOWER(name)`), todos na mesma transação, e a condição de cada um é avaliada por SQL sobre o estado
  já alterado pelos anteriores (`Ticket.perform_triggers`, `app/models/ticket.rb`). Os nomes "Distribuição —
  …" ordenam antes de "Ticket Criado/Atualizado/Reaberto", então **os triggers de produção que vêm depois
  já enxergam o dono escolhido**. Isso é intencional, mas um trigger de produção com condição sobre o dono
  (por exemplo, "dono não definido") deixaria de disparar, e um que mude grupo ou estado depois da Entrada
  pode fazer o `check_owner_active` zerar o dono. Por isso a virada revisa os triggers ativos (§8.3), e há um
  teste com um trigger de webhook condicionado ao dono.
- **Para o payload do n8n, a ordem não importa:** a ação de webhook só enfileira o job no `after_commit`
  (`app/models/ticket/perform_changes/action/notification_webhook.rb`), e o job carrega o ticket do banco
  quando roda. O payload de "Ticket Criado" já sai com o dono escolhido.

### 6.3 Recusa da macro

- Só no modo Repasse e só quando falta complexidade.
- A ação levanta `Exceptions::UnprocessableEntity` com uma mensagem traduzível ("Preencha a complexidade
  antes de repassar"). O `with_lock` do controller desfaz tudo: campos, artigo e dono. O cliente não recebe
  nada.
- A recusa acontece **antes de qualquer escrita da requisição**. O `EventBuffer` é por thread e não é limpo
  quando a action levanta erro (`app/controllers/application_controller/handles_transitions.rb`); eventos de
  escritas desfeitas seriam despachados na próxima requisição da mesma thread.
- No app clássico, o erro de save aparece num aviso de 2 s (`ticket_zoom.coffee`, callback `error` do
  `submitPost`). **Para este erro**, o aviso fica até a pessoa fechar; os outros erros de save não mudam.
  Como identificar o erro (código, chave no JSON) fica com o builder. Vale também para a macro em lote.
- Efeito colateral aceito: as tags da macro são gravadas via API antes do envio e **não** são desfeitas. Se o
  N1 reaplica a macro, a repetição é inofensiva; se não reaplica, as tags ficam erradas até alguém corrigir.
- Em trigger, a ação **nunca** levanta erro: usa os fallbacks de §5.4.

### 6.4 Payload do webhook e Discord

O `ticket.owner` do payload passa a levar o `discord_uid` sem mudança no webhook: o de produção usa o payload
padrão, e atributos de usuário criados pelo ObjectManager entram nele. O n8n monta a menção
`<@{{ discord_uid }}>`; se o campo estiver vazio, menciona pelo nome (§8.1).

**O n8n continua reconhecendo o repasse pelo texto do artigo** ("Realizamos uma análise prévia da sua
ocorrência") para mencionar o dono no Discord e mandar o e-mail "em andamento" ao cliente, como já faz com
as outras macros (Roadmap, Engenharia, encerramento). Só a atribuição deixa de depender do texto. Um aviso
próprio "Ticket Repassado" foi considerado e rejeitado pelo usuário (ADR 0004). Consequências aceitas:

- quando o repasse não é realizado, o Discord anuncia o ticket mencionando o N1, que continua dono, e o
  cliente recebe o "em andamento";
- o "Email de em andamento" passa a mostrar o N2 como responsável (hoje mostra o N1, porque o payload é de
  antes do LB atribuir).

## 7. Tela "Distribuição de atendimentos" (admin clássico)

Em **Admin › Gerenciar › Distribuição de atendimentos**, com `admin.ticket_distribution`. O esboço aprovado
está em `.superpowers/brainstorm/` (não versionado); a descrição abaixo é a referência.

- **N1 · Entrada:** lista de agentes (nome, último ticket recebido, remover) e campo para adicionar. Sem
  interruptor. Não deixa remover o último N1. Se a lista ficar vazia por exclusão do usuário, a tela mostra um
  alerta vermelho "Nenhum N1 cadastrado".
- **N2 · Repasse:** lista com interruptor "No rodízio", situação ("No rodízio", "Offline · continua no
  rodízio", "Fora do escritório até dd/mm", "Desligado"), carga em pontos com barra, quantidade de tickets
  que pesam, último repasse recebido, indicador do ID do Discord (ok / "sem ID") e remover; campo para
  adicionar. Abaixo, a linha "Se um repasse acontecesse agora, iria para *fulano*" — a regra de §5.3, itens
  4 e 5, sem excluir ninguém por "quem repassa", sem considerar Disparos e sem considerar o grupo do ticket
  (a tela diz isso).
- **Alerta por membro** (o cadastro não é bloqueado) **(decisão do spec)**: inativo, sem `ticket.agent` ou sem
  acesso `full` aos grupos que o papel exige, com o motivo (por exemplo, "sem acesso a: Suporte"):
  - N1: todos os grupos ativos (todo ticket entra pelo N1);
  - N2: todos os grupos ativos, menos o de Disparos;
  - responsável de Disparos: o grupo de Disparos.
- **Disparos e campanhas:** seleção do grupo e do responsável, com o texto "Como todo ticket, entra pelo N1.
  No repasse, vai para o responsável em vez do rodízio do N2."
- **Como a carga é contada:** atributo de complexidade (seleção entre os atributos de ticket do tipo
  seleção), pesos por valor, estados que não pesam, prioridades que não pesam.
- **Cadastro do agente:** campo "ID do Discord".

O interruptor e a lista salvam na hora; os blocos de Disparos e de carga têm botão Salvar (padrão das telas
de configuração do admin clássico, como `_manage/ticket_auto_assignment.coffee`). A API REST da tela
(controller, policy, rotas) segue o molde do CSAT (commit `0c96a70da0`).

## 8. n8n e virada

### 8.1 Roteiro do n8n

Roteiro nó a nó no "NDesk - Notificações". Remover um nó do meio de uma cadeia corta o que vem depois, então
cada remoção vem com a religação. Religar é seguro: os nós de destino leem de `$('Notificações')`, e não do
nó removido. O plano traz este roteiro como tarefa manual da virada, executada por quem tem acesso ao n8n.

| Ramo | Cadeia hoje | Depois |
|---|---|---|
| Ticket Criado | `Webhook canal de tickets no discord1 → adiciona Marcus → É melhoria? → Email de criação1 / Roadmap de melhorias1` | Remover "adiciona Marcus" (`owner_id 585`) e ligar `Webhook canal de tickets no discord1 → É melhoria?`. Sem isso, o cliente deixa de receber o e-mail de abertura. |
| Ticket Atualizado, saída "Passa para o N2 e entra em andamento" do `Switch1` | `Switch1 → Call 'LB - Atribuição de Ticket' → Switch (nomes) → Mensagem marcando X → Email de em andamento` | Remover a chamada ao LB, o switch de nomes e as mensagens por pessoa. Ligar `Switch1 → (novo) Mensagem marcando o dono → Email de em andamento`, com `<@discord_uid>` e o nome como reserva. |
| Ticket Atualizado, saída de fallback do `Switch1` | `É o suporte?` testa `article.updated_by_id` igual a 11, 5 ou 6 | Trocar pelo teste "artigo de agente e não interno" (`article.sender == "Agent"` e `article.internal == false`) **(decisão do usuário)**. Consequência aceita: as respostas do N1 (585), que hoje não estão na lista, passam a gerar o e-mail "Acabou de receber uma atualização" ao cliente. |
| Ticket Reaberto | `não é reaberto → Mensagem marcando a reabertura` | A mensagem passa a mencionar o dono pelo `discord_uid`, que depois da ação já é o dono certo. |
| Ticket Fechado | `Define notificação → Call 'LB - Liberação de Pontos' → Send email2` | Remover a chamada e ligar `Define notificação` (saída "Ticket Fechado") direto no `Send email2`. A chamada tem "Always Output Data"; sem religar, o cliente deixa de receber o e-mail de fechamento. |

Depois: desativar **"LB - Atribuição de Ticket"** e **"LB - Liberação de Pontos"**. A data table
`load_balancer` deixa de ser usada.

### 8.2 Checklist de não-regressão (critério 6)

Depois da virada, em produção:

- ticket criado gera o e-mail de abertura e cai no N1;
- repasse menciona o N2 certo no Discord, inclusive um agente novo, e o "Email de em andamento" mostra o N2;
- um N2 novo responde ao cliente e o cliente recebe "Acabou de receber uma atualização";
- nota interna não gera e-mail ao cliente;
- reabertura pelo cliente avisa no Discord mencionando o dono;
- fechamento gera o e-mail "Seu ticket … foi finalizado".

### 8.3 Virada

1. **Deploy** com os dois triggers desligados e a macro sem a ação nova: nada muda no comportamento.
2. **Configuração:** o admin preenche os IDs do Discord, as listas de N1 e N2, o responsável de Disparos e as
   regras de carga, e resolve os alertas da tela.
3. **Revisão dos triggers ativos de produção:** procurar condições sobre o dono e ações que mudem grupo ou
   estado na criação e na atualização (§6.2).
4. **Recarga:** garantir que todos os agentes recarreguem o NDesk depois do deploy, porque abas com o JS antigo
   não mandam a ação nova na macro (§6.1).
5. **Ligar o NDesk e logo depois o n8n**, fora do horário de pico: ligar os dois triggers e incluir a ação
   (modo Repasse) na macro de análise prévia; em seguida, publicar o n8n do roteiro de §8.1 e desativar os
   dois fluxos do LB. Nessa ordem, a janela entre os dois passos só tem o n8n sobrescrevendo com o
   comportamento antigo; na ordem inversa, os tickets ficariam sem dono.
6. **Checklist** de §8.2 e revisão dos tickets criados ou repassados durante a janela.
7. **Rollback:** desligar os triggers, tirar a ação da macro, atualizar a `carga_atual` da data table
   `load_balancer` com a carga mostrada na tela (ela ficou parada desde a virada) e reimportar o export atual
   dos três fluxos do n8n.

Os exports do n8n carregam o token da API do NDesk em texto nos headers. Eles são necessários para o
rollback: guardar num cofre (nunca no git), apagar do Downloads e trocar o token depois da virada.

## 9. Erros e casos-limite

| Situação | Comportamento |
|---|---|
| Repasse sem complexidade | Macro recusada, aviso fixo, nada gravado (tags da macro ficam). |
| Macro em lote com algum ticket sem complexidade | Lote inteiro recusado, com a mensagem visível. |
| Macro reaplicada num ticket que já está com um N2 do rodízio | Dono mantido. |
| Nenhum N2 no rodízio no repasse | Macro passa, dono não muda, nota interna, notificação no sino para quem repassou; depois, atribuição manual. |
| Nenhum N2 no rodízio na reabertura | Vai para o N1 pela Entrada, nota interna, notificação no sino. |
| Reabertura feita por um agente | A distribuição não mexe no dono. |
| Reaberto com dono fora das listas, ativo e com acesso | Fica com ele. |
| Mesclar ou remover ticket fechado | Não é reabertura; nada acontece. |
| Responsável de Disparos ausente, sem acesso ou excluído | Regra normal do N2. |
| Agente desativado, sem `ticket.agent` ou sem acesso `full` ao grupo | Pulado na escolha (§5.1); a tela mostra o alerta. |
| Nenhum N1 consegue ser dono do ticket | Fica sem dono, nota interna e log. |
| Usuário excluído | Sai das listas; se for o responsável de Disparos, o campo é limpo. |
| Valor de complexidade sem peso | Pesa 0, log uma vez por decisão. |
| Dois repasses no mesmo instante, inclusive em lote | Serializados pela trava, sem deadlock (§5.6). |

## 10. Testes

Antes de rodar: `rm -f db/schema.rb` (o banco de teste é construído por migrations desde a NDESK-45).

- **Regra de escolha (service):** menor carga sem o próprio ticket; empate por `last_assigned_at` com nulo
  primeiro; 3 ou mais agentes (critérios 2 e 4); interruptor desligado e "Fora do escritório" fora, offline
  dentro (critério 3); quem repassa fora; reaplicação mantém o dono; Disparos vão ao responsável sem mexer no
  `last_assigned_at`, inclusive com o interruptor dele desligado; responsável ausente cai no N2; filtro de
  §5.1; N1 recebe ausente; vez do N1 com vários membros.
- **Critério 1:** trocar o N1 na configuração e o próximo ticket criado cai no novo.
- **Carga:** inclui estado de pendência, ignora estados e prioridades marcados, sem complexidade = 0, Disparos
  na carga do responsável, e bate com a soma dos tickets (critério 5).
- **Ação, nos três modos, em macro e em trigger:**
  - preencher a complexidade e aplicar a macro no mesmo envio funciona;
  - a recusa desfaz artigo, campos e dono, e acontece antes de qualquer escrita;
  - trigger nunca levanta erro;
  - repasse não realizado: nota interna do Sistema e notificação, com o webhook "Ticket Atualizado" saindo com
    o artigo da macro.
- **Reabertura:** só age na transição `closed` → aberto e só quando quem reabre é o cliente; mesclar ticket
  fechado não dispara; usa o dono anterior de `changes['owner_id']` quando o follow-up zerou o dono; dono fora
  das listas fica; fallbacks.
- **Ordem dos triggers:** um trigger de webhook condicionado ao dono, com nome depois de "Distribuição", vê o
  dono escolhido.
- **Request specs:** `PUT /api/v1/tickets/:id` com a macro sem complexidade devolve 422 com a mensagem e não
  grava nada; `POST /api/v1/tickets/mass_macro` com um ticket sem complexidade recusa o lote.
- **Concorrência:** repasses em paralelo, individual e em lote, não caem no mesmo agente nem travam.
- **Payload do webhook** com o `discord_uid` do dono (critério 6, lado NDesk).
- **Exclusão de usuário** membro das listas e responsável de Disparos (inclusive pela DataPrivacyTask).
- **Permissão, policy e controller** da tela; **migração** (permissão, settings, atributo `discord_uid`,
  triggers desligados); specs que enumeram modelos e referências atualizadas.
- **Atributos de produção nos specs:** criar o atributo `complexidades` pelo ObjectManager e os estados e
  prioridades customizados nas factories.
- **App clássico:** QUnit para o adiamento do prefixo novo em `App.Ticket.macro`; system spec do caminho
  feliz (cadastrar N2, aplicar a macro, ver o dono mudar e a carga na tela) e do aviso fixo da recusa.
- **n8n:** sem teste automático; coberto pelo checklist de §8.2 no QA (NDESK-73).

## 11. Fica com o builder

- Formato do(s) Setting(s), nomes de classes, rotas e endpoints da tela.
- Mecanismo e ordem de aquisição da trava de §5.6.
- Como o app clássico reconhece o erro da recusa para deixar o aviso fixo (individual e em lote).
- Texto exato das notas e da notificação (em pt-BR, traduzíveis).
- Ordenação e paginação das listas da tela.

## 12. A conferir em produção (QA, NDESK-73)

- A categoria (`state_type`) de "Aguardando cliente" (deve ser pendência, para pesar) e dos estados de
  "Melhoria" (se forem `closed`, sair deles conta como reabertura).
- Se algum grupo tem o follow-up configurado para criar ticket novo: aí a resposta a um ticket fechado vira
  ticket novo, vai para a Entrada, e a "volta para quem atendeu" não acontece.
- As condições do trigger "Ticket Atualizado" de produção: se ele dispara para notas internas, e quem é o
  usuário 11 da lista antiga do "É o suporte?".
