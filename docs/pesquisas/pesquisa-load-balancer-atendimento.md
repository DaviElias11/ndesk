# Pesquisa de mercado: load balancing e roteamento de atendimentos para atendentes humanos

- **Data:** 2026-10-16
- **Método:** Firecrawl (`firecrawl_search`, `firecrawl_scrape`, `firecrawl_map`), priorizando help centers e developer docs oficiais. Material de marketing e de terceiros vem marcado como tal.
- **Escopo:** como tickets, chats, conversas de WhatsApp e ligações são atribuídos a atendentes humanos. Não cobre roteamento para bots/IA.
- **Convenção:** "**não encontrado**" significa que a informação não apareceu nas páginas lidas. Não quer dizer que a plataforma não tenha o recurso.

---

## 1. Resumo executivo

1. **Padrão dominante nos helpdesks:** distribuição *push* com teto de capacidade por atendente. O critério principal é "menos carga" (menos itens abertos ou mais capacidade livre) e o desempate é "há mais tempo sem receber" (Zendesk, Salesforce, Intercom, Freshdesk/Freshchat, HubSpot, Blip).
2. **Round robin quase nunca é puro:** quase sempre vem filtrado por status online e capacidade livre. Exceção: o round robin do Intercom ignora o limite.
3. **Capacidade** é um limite de itens simultâneos **por canal**, às vezes com teto total ou pesos/percentuais (Salesforce, Twilio). Voz é quase sempre 1. Status unificado (online/away/offline + pausas personalizadas) define quem está elegível.
4. **Contact centers** (Genesys, NICE, Twilio, Five9) usam "agente ocioso há mais tempo", skills com proficiência e prioridade, com *fallback* por expansão progressiva do pool (bullseye/anéis, timeouts por etapa).
5. **Sem ninguém disponível:** o item espera numa fila ordenada por prioridade → SLA → idade (FIFO). Timeouts de oferta reoferecem a outro atendente, timeouts de skill relaxam requisitos e grupos secundários fazem transbordo.
6. **Agente preferencial (sticky)** é nativo e configurável nos contact centers (Genesys PAR/LAR, Twilio Known Agent, NICE Target Agent). Nos helpdesks aparece só parcialmente (Freshchat devolve conversa reaberta ao mesmo agente, HubSpot roteia para o dono do contato). **Nas plataformas brasileiras: não encontrado.**
7. **Brasileiras** (Blip, Octadesk, Huggy, Movidesk): rodízio ou "menos ativos" + limite simultâneo + filas por regra. Não encontrei skills com proficiência, sticky nem transbordo automático entre filas.
8. **Métricas expostas:** carga/capacidade por agente, tempo do item mais antigo na fila, tempo até aceite, tempo por status e, no Intercom, o **motivo** de um item estar sem atribuição.

---

## 2. Glossário dos modelos de distribuição

| Termo | Definição |
|---|---|
| **Push** | O sistema escolhe o atendente e entrega (oferta ou atribuição automática). Padrão de todas as plataformas pesquisadas. |
| **Pull** | O atendente pede o próximo item. Ex.: botão "Pull conversation" (Intercom), "+1 Contact" / Request Interaction (NICE), botão "Atender" (Blip). Costuma respeitar a ordem da fila, mas às vezes **ignora** limites. |
| **Round robin / rodízio** | Entrega ao atendente que está **há mais tempo sem receber** (ou na ordem fixa de uma lista). Na maioria das plataformas ainda exige status online e capacidade livre. |
| **Menor carga (least active / load-based / balanced)** | Entrega a quem tem **menos itens ativos** (contagem absoluta ou capacidade consumida). |
| **Maior capacidade livre (most available / spare capacity)** | Entrega a quem tem **mais folga** (`capacidade máxima − carga atual`, em número ou %). Difere de "menor carga" quando os atendentes têm limites diferentes. |
| **Agente ocioso há mais tempo (LIA, longest idle)** | Critério clássico de ACD: tempo desde a última interação atribuída. Base de Genesys, NICE (tempo em Available) e da ordenação padrão do Twilio. |
| **Capacidade** | Quantos itens o atendente pode ter ao mesmo tempo, por canal e/ou no total, em unidades, peso ou percentual. |
| **Capacidade interrompível** | Trabalho assíncrono (e-mail) ocupa uma "faixa" separada e pode ser interrompido por trabalho prioritário (Salesforce, Genesys). |
| **Skills-based routing (SBR)** | O item exige skills (idioma, produto, tier) e só vai para quem as tem. Pode ter **proficiência** (nível) e skills **obrigatórias vs. opcionais**. |
| **Best available skills / all skills matching** | Variações de SBR no Genesys: maior proficiência média entre os ociosos vs. qualquer um que tenha todas as skills. |
| **Bullseye / anéis** | Começa com um pool restrito (melhores agentes) e amplia anel a anel após timeouts, relaxando skills ou adicionando grupos. |
| **Prioridade / ordenação da fila** | Ordem em que itens em espera são entregues: prioridade, proximidade de quebra de SLA, idade (FIFO), prioridade da fila. |
| **FIFO** | Primeiro a entrar, primeiro a ser atendido. Padrão quando não há prioridade nem SLA. |
| **Sticky / agente preferencial / last agent / known agent** | Tenta primeiro o atendente que já atendeu o cliente (ou um definido), com timeout e fallback para o pool geral. |
| **Overflow / transbordo entre filas** | Se ninguém do grupo primário está livre, abre para grupos secundários (fallback). Atenção: no jargão BR, "transbordo" costuma significar **bot → humano** (Blip, Zenvia). |
| **Timeout de oferta (push timeout / refusal timeout / reassignment timing)** | Tempo para o atendente aceitar antes de a oferta ir para outro. |
| **Focus mode / channel lock** | O atendente recebe trabalho de um canal em tempo real por vez (Zendesk) ou fica "travado" no canal atual (NICE). |
| **Auto-accept vs. offer** | Atribuição direta vs. oferta com botão de aceitar. |
| **Wrap-up time** | Pausa pós-atendimento antes de receber o próximo item. |
| **Conversa inativa / capacity release** | Conversa sem resposta do cliente por X minutos deixa (ou não) de contar na capacidade. |
| **Predictive / AI routing** | Escolhe o agente com maior probabilidade de bater uma meta (KPI). Genesys e NICE. |

---

## 3. Tabela comparativa

Legenda: ✅ documentado · ⚠️ parcial ou com ressalva · ❌/— não encontrado nas fontes lidas.

| Plataforma | Modelos suportados | Capacidade | Fila / sem disponível / overflow | Sticky agent | Skills | Observações |
|---|---|---|---|---|---|---|
| **Zendesk** (omnichannel routing) | Maior capacidade livre (numérica ou %), round robin. Desempate: há mais tempo sem receber. Push com oferta ou auto-accept | Capacity rules por canal: e-mail ≤500 abertos, messaging ≤20, voz 0/1. Uma regra por agente. Pending/on-hold não contam. Inativos (10 min) contam se configurado | Fila padrão ou custom queues com grupos primários e **secundários (fallback)**. Ordem: mais antigo / SLA / prioridade (conforme plano). Reoferta de messaging após 30 s. Voz reofertada em round robin até o tempo máximo de fila → correio de voz | ⚠️ Reaberto fica com o mesmo agente, a menos que o status dele dispare reatribuição. "Voltar ao último agente" para nova conversa: não encontrado | ✅ (Professional+). Obrigatórias/opcionais, prioridade de skill por agente, timeout de skill | Focus mode, status unificado + personalizados, reatribuição automática quando o agente muda de status. Agente pode exceder o limite manualmente |
| **Salesforce Service Cloud** (Omni-Channel) | Least Active, Most Available, External routing. Desempate: agente sem trabalho que logou primeiro, depois há mais tempo sem atribuição | Capacidade total na presence configuration (unidades ou %). Tamanho do item por routing configuration. Capacidade interrompível. Item pausado consome 0 por padrão | Prioridade de roteamento entre filas → tempo na fila. Push timeout → próximo rep. Recusado volta à fila com a idade original. *Overflow assignee* quando a org atinge limites do Omni. Timeout que descarta skills adicionais | ⚠️ Roteamento direto para um rep específico existe (Omni-Channel flow); fallback não detalhado nas páginas lidas | ✅ Skills-based routing (regras ou flow). Fila **ou** skills, nunca os dois | Trabalho conta como atribuído mesmo se recusado. Classificação não roda de novo se o campo mudar depois |
| **Freshdesk** (Omniroute) | Round-robin, load-based, skill-based, configurados por grupo | Carga padrão por novo agente. Por fila de canal (Email/Messaging/Fallback) no Freshdesk Omni, ou "Tickets" global no standalone. Escolha de quais status contam na carga | Só agentes disponíveis. Ordem: criação do ticket, *response due* ou *resolution due* (SLA). Idle timeout (Omni) | — não encontrado | ✅ | Doc avisa: load-based favorece quem resolve mais rápido |
| **Freshchat** (IntelliAssign) | Load-based (maior folga %, depois há mais tempo sem receber), round robin, skill-based (Enterprise) | Limite de conversas ativas por agente + **níveis de carga** (Beginner/Intermediate/Expert) | Conversa de agente inativo vai para o membro do grupo com menos conversas ativas (opcional). Se todos estão inativos, a conversa fica aberta. Assignment rules têm precedência | ✅ Reaberta volta ao mesmo agente se reabrir dentro do período configurado | ✅ (Enterprise) | Define tempo de ociosidade e timeout de conversa inativa |
| **Intercom** | Balanced (menos abertas; desempate há mais tempo sem receber), round robin (sequencial, **ignora limite**), manual. Botão "Pull conversation" | Limite do workspace + override por pessoa. Limites separados conversas/tickets e e-mail/Messenger (0 bloqueia). Limite por inbox (precisa satisfazer os dois). Telefone = 1 | Espera na team inbox. Ordenação: prioridade, SLA, waiting since, started at, prioridade da inbox. Inboxes primárias/secundárias. Posição na fila visível ao cliente. Motivo de "não atribuída" | — não encontrado | ✅ (Expert, só com balanced). Sem skilled disponível, cai para o menos carregado (não espera) | Wrap-up até 2 h por canal. Reatribui conversas des-sonecadas quando o dono está no limite ou ausente |
| **HubSpot** (help desk) | Load balanced (menos tickets abertos do mesmo tipo), round robin, random. Também por workflow ou "contact owner" | Limite de tickets por usuário. Exclui status como *waiting on contact*. Conta só tickets abertos atribuídos nos últimos 30 dias. Tipos: calling / messaging / email | Só usuários disponíveis (horário, ausência, manual). Se nenhum está disponível ou todos no limite → **fica sem atribuição** até alguém atribuir manualmente | ⚠️ Rotear para o **dono do contato** (contato com owner e rastreado por cookie) | ✅ Idiomas como skills (principal/secundário) | "Assignment details" explica regra, disponibilidade e capacidade de cada atribuição |
| **Twilio Flex** (TaskRouter) | Workflows com filtros e targets. Padrão: worker ocioso há mais tempo. `order_by` em atributos. Multi-reservation | Multitasking por TaskChannel (voice, chat, sms, video, custom). `configured_capacity`, `assigned_tasks`, `available_capacity_percentage` | Task espera em cada target até o timeout e avança. `default_filter` até o TTL. `skip_if`. Reserva rejeitada ou expirada → reavaliação | ✅ **Known Agent Routing** (`known_worker_sid`) com timeout e fallback | ✅ Via expressões em atributos do worker | Permite reservar parte da capacidade para pull manual |
| **Genesys Cloud** | Standard ACD, Predictive (IA), Preferred agent, Bullseye, Conditional group routing. Avaliação: best available skills / all skills matching / disregard skills | *Utilization* por mídia (padrão: 1 call, 1 callback, 4 chats, 1 e-mail, 4 mensagens, 4 workitems). Tipos interrompíveis. Org + agente | Espera até haver agente. Anéis bullseye com timeout. **Conditional Group Activation** liga grupo de overflow por EWT. Score de prioridade (1 ponto = 60 s) | ✅ **PAR** (até 20 agentes, score 0–100, 6 regras com timeout) + **last agent routing** | ✅ Com proficiência | Ociosidade considera só os últimos 7 dias. PAR não é compatível com WFM |
| **NICE CXone** | Dynamic delivery: tempo em Available + proficiência. AI routing opcional. Bullseye, routing attributes, integrated matching (prioridade entre voz e digital) | Por time/agente: voz 1, chat/SMS ≤12, e-mail/work item ≤25, digital ≤50 + **Total Contact Count**. Channel Lock | Prioridade + aceleração + max priority por skill. Refusal timeout padrão 45 s (15–300) e transfere | ⚠️ **Target Agent** (rotear a um agente específico). "Last agent" não verificado | ✅ Com proficiência | Entrega automática "sem load balancing". Modo agent-request (+1 contato) |
| **Five9** | Só marketing: skills-based, prioridade, por horário, distribuição por fila, data-directed | não encontrado | não encontrado | ⚠️ Marketing cita "cliente recorrente para o mesmo agente" | ⚠️ Marketing: "skill groups e proficiência ilimitados" | Docs técnicas (portal Zoomin) não indexáveis pela busca |
| **Blip** (Blip Desk) | Padrão: **menos tickets ativos** (desempate há mais tempo sem receber). Alternativo: **há mais tempo sem receber** (desempate menos ativos) | "Atendimentos por atendente" global + override individual. Limite de tickets **sem primeira resposta** | Filas + **regras de atendimento** (mensagem, nome, e-mail, extras → fila; senão fila Default) + **regras de priorização** (baixa/média/alta). Bot pode checar se há atendente online por fila | — não encontrado | ❌ Sem SBR; segmentação por fila e regra | Pode bloquear o pull manual (botão "Atender") |
| **Zenvia** (Customer Cloud) | não encontrado (páginas públicas citam transbordo bot→humano, transferência e tickets/chat) | não encontrado | não encontrado | não encontrado | não encontrado | Movidesk aparece como "Zenvia Movidesk" (ver linha Movidesk) |
| **Octadesk** | **Roleta** (round robin), global ou por grupo | "Limitar o número de conversas por usuário". Acima do limite → fila "não atribuídas" | Espera em "não atribuídas". Quem fica online primeiro recebe todo o backlog. Transferência por inatividade do agente (tempo configurável) | — não encontrado | ❌ Grupos de atendimento | Opção de incluir os responsáveis do grupo na roleta |
| **Huggy** | Autodistribuição: lista de disponíveis ordenada por quem está **há mais tempo sem receber chat automático** | Limite de chats simultâneos por usuário | Chats seguem a ordem da fila. Filtros por departamento, por usuário e **por horário** da autodistribuição | — não encontrado | ❌ Departamentos | Status Disponível/Indisponível/Em pausa + status personalizados com mensagem automática |
| **Movidesk** (Zenvia) | Distribuição automática por **grupo de chat** seguindo uma **ordem configurável de agentes** | Máximo de atendimentos simultâneos **por grupo** (vazio = ilimitado). Chats de ticket e internos não contam | Todos no teto → fila de espera. O 1º da fila vai para quem libera | — não encontrado | ❌ | Agente em 2 grupos com limite 2 pode chegar a 4 (o limite é por grupo) |

---

## 4. Detalhes por plataforma

### 4.1 Zendesk: omnichannel routing
- **Fluxo:** triggers definem grupo, prioridade, tags e skills → o ticket entra na primeira custom queue cujas condições casar, senão vai para a fila padrão (e-mail só entra na fila padrão com a tag `auto-routing`) → é atribuído quando chega à frente da fila.
- **Elegibilidade:** grupo/fila, status (e-mail exige online ou away; messaging e voz exigem online), capacidade livre no canal, skills. Respeita a associação do agente à marca.
- **Métodos:**
  - **Highest numeric spare capacity** (padrão): `máx − atribuídos`.
  - **Highest percentage spare capacity**: `atribuídos / máx × 100`, menor vence.
  - **Round robin**: há mais tempo sem receber no canal, mas ainda exige capacidade. Oferta de call/messaging e reabertura contam como evento de atribuição.
  - **Desempate** no spare capacity: há mais tempo sem receber no canal.
- **Ordem da fila:** Team = mais antigo. Growth = mais antigo ou SLA mais próximo. Professional+ = prioridade + mais antigo, ou SLA. Custom queues **sempre** passam à frente da fila padrão.
- **Sem disponível:**
  - Fica na fila.
  - Messaging: com *reassignment timing*, sai do agente que não aceitou após 30 s (customizável no Enterprise); sem isso, insiste no mesmo agente.
  - Voz: oferta em round robin até o tempo máximo de fila → voicemail.
  - **Skills timeout** (padrões: e-mail 1 h, messaging 30 s, voz 30 s) descarta as skills opcionais. Sem timeout, o ticket fica na fila indefinidamente.
  - Custom queues com grupos secundários fazem o overflow.
- **Reatribuição:** reabertos (Professional+) podem ser reatribuídos conforme o status do agente. *Auto-reassign open tickets* devolve até 50 tickets abertos quando o agente muda para um status configurado (com 1 min de atraso). Voz nunca é reatribuída depois de atribuída.
- **Capacidade:** e-mail ≤500, messaging ≤20 (vale separadamente para messaging e live chat), voz 0/1. Um agente tem uma só capacity rule. Pending/on-hold não contam. Conversas inativas (sem resposta do cliente há 10 min) só contam se a opção estiver ligada.
- **Status:** status unificado (online/away/offline/transfers only) + personalizados (até 5 no Professional, 100 no Enterprise). Idle threshold e desconexão mudam o status automaticamente.
- **Métricas:** dashboard Explore "Omnichannel: Agent productivity and queues" com capacidade usada por canal, ofertas/aceites e tempo em cada status.

### 4.2 Salesforce Service Cloud: Omni-Channel
- **Routing models:**
  - **Least Active:** menor capacidade consumida.
  - **Most Available:** maior capacidade disponível.
  - **External routing:** um sistema terceiro decide.
- **Desempate:** primeiro reps sem trabalho, pelo login mais antigo; depois quem está há mais tempo sem atribuição.
- **Capacidade:** a *presence configuration* define a capacidade total (unidades ou %). A *routing configuration* define quanto cada item consome (unidades ou %; voz = 100%). No modelo status-based, itens pausados consomem 0 por padrão. **Capacidade interrompível** separa trabalho assíncrono.
- **Configuração por fila:**
  - Routing priority (ordem entre filas, depois idade do item).
  - **Push time-out** (tempo para responder antes de ir a outro rep).
  - **Drop additional skills time-out**.
  - **Overflow assignee** (usuário ou fila que recebe quando a org atinge os limites do Omni-Channel).
- **Comportamento:** o trabalho conta como atribuído ao ser roteado, mesmo se o rep recusar. Item recusado volta à fila com a idade original. Ao voltar de offline, abre uma nova sessão e a capacidade é recalculada.
- **Skills:** por regras (campo do objeto → skill), na routing configuration ou via Omni-Channel flow. Um item usa **fila ou skills**, nunca os dois. O Trailhead recomenda não exigir skills demais por item.
- **Sticky:** trabalho pode "ir direto a um rep específico" (Trailhead). O fallback dessa opção **não foi detalhado** nas páginas lidas.

### 4.3 Freshdesk: Omniroute
- **Métodos por grupo** (Pro/Enterprise):
  - **Round-robin:** circular, por última atribuição, respeitando capacidade.
  - **Load-based:** menos ocupado primeiro, depois última atribuição.
  - **Skill-based**.
- **Capacidade:** carga padrão para novos agentes. No Freshdesk Omni, capacidade por fila de canal (ex.: Email 5, Messaging 10, Fallback 5); no standalone, um campo "Tickets" global. *Agent load behavior by status* define quais status de ticket contam na carga.
- **Ordem:** criação do ticket, *first/next response due* ou *resolution due* (SLA).
- **Disponibilidade:** só agentes Available. Admin escolhe se o agente, o supervisor ou só o admin controla o status. Idle timeout no Omni.
- **Alerta da doc:** "agentes que resolvem mais rápido recebem mais".

### 4.4 Freshchat: IntelliAssign
- **Lógicas:**
  - **Load-based:** maior *bandwidth* livre, depois há mais tempo sem receber. Exemplo da doc: limites 10 e 5 com 4 conversas entrando → A recebe 3, B recebe 1.
  - **Round robin:** há mais tempo sem receber + limite.
  - **Skill-based** (Enterprise).
- **Agent settings:** tempo de ociosidade (vira idle), timeout de conversa inativa, limite de conversas ativas, **load levels** por senioridade que sobrescrevem o limite geral.
- **Sticky:** conversa reaberta pode voltar ao mesmo agente, se o toggle estiver ligado, o agente estiver ativo e a reabertura ocorrer dentro do período configurado.
- **Agente inativo:** opção de redistribuir para quem tem menos conversas ativas no grupo. Se todos estão inativos, as conversas ficam abertas.
- **Precedência:** *Assignment Rules* (condições) valem antes do IntelliAssign.

### 4.5 Intercom: Workload management
- **Métodos:**
  - **Balanced** (plano Expert): menos conversas abertas; desempate há mais tempo sem receber.
  - **Round robin:** sequencial, não respeita limite e só atribui uma vez.
  - **Manual**.
- **Capacidade:** limite do workspace (sem o recurso, fixo em 3) e override por pessoa. Separação conversas/tickets e **e-mail/Messenger**: o limite de canal soma ao total, vale o mais restritivo, e 0 bloqueia o canal. Telefone = 1. **Inbox assignment limits:** precisa satisfazer o limite pessoal **e** o da inbox.
- **Ordenação:** prioridade, SLA, *waiting since*, *started at*, prioridade da inbox. Inboxes **primárias e secundárias** por pessoa (secundária só recebe quando as primárias estão vazias).
- **Sem disponível:** fica na team inbox, com **motivo visível** (ex.: "All teammates are at their conversation capacity", "All teammates are away") e posição na fila exibida ao cliente no Messenger.
- **Outros:** *wrap-up time* até 2 h por canal (chat/e-mail). Reatribuição de conversas des-sonecadas quando o dono está no limite ou ausente. O botão *Pull conversation* ignora limite e status. Atribuição manual ignora limite e status.
- **Skills (Expert, só com balanced):** sem skilled disponível, **nunca espera**: vai ao menos carregado. Na voz, a skill muda a **ordem** de toque (tenta até 5 pessoas, e a 5ª vaga fica reservada a alguém sem a skill).
- **Métricas:** dashboard em tempo real (abertas, idle, snoozed, carga por pessoa, SLA miss, FRT, CSAT). No popover, "capacidade da inbox / capacidade da pessoa" fica em vermelho quando estoura.

### 4.6 HubSpot: Help desk
- **Distribuição por canal** (e-mail, formulário, WhatsApp): Load Balanced (menos tickets abertos), Round Robin ou Random. Destino: usuários/times específicos, só time, workflow, **dono do contato** ou ninguém.
- **Carga:** conta só tickets **abertos atribuídos nos últimos 30 dias**, separados em calling / messaging / email-other ("menos tickets abertos do mesmo tipo").
- **Disponibilidade:** horário de trabalho, ausência ou manual. Com "assign to available users only" (padrão), se ninguém está disponível o ticket fica **sem atribuição**.
- **Capacity limits** (Service Hub Pro/Ent): no limite, o usuário sai da distribuição. Se todos estão no limite, o ticket fica sem atribuição até alguém atribuir manualmente. Dá para excluir status (ex.: *Waiting on contact*). Atribuição manual continua permitida.
- **Explicabilidade:** "Assignment details" mostra regra, disponibilidade, checagem de capacidade e atribuição.
- **Skills:** idiomas como skills (principal/secundário).

### 4.7 Twilio Flex: TaskRouter
- **Workflow:** filtros avaliados de cima para baixo. Em cada *target* (fila + expressão + prioridade + timeout), a task espera e, ao expirar, avança para o próximo. `default_filter` vale até o TTL. `skip_if` pula etapas sem disponíveis. Reserva rejeitada ou expirada → reavaliação.
- **Escolha do worker:** sem `order_by`, o worker **ocioso há mais tempo** é reservado primeiro (a doc de ciclo de vida descreve a criação de reservas como round robin sequencial). `order_by` ordena por atributos inteiros (ex.: nível). Multi-reservation oferece a vários ao mesmo tempo e o primeiro que aceitar leva.
- **Capacidade (multitasking):** capacidade por TaskChannel (ex.: 1 voz + 3 chats). Atributos `configured_capacity`, `assigned_tasks` e `available_capacity_percentage` permitem regras como "não receber chat enquanto estiver em voz" ou reservar uma fração da capacidade para pull manual.
- **Sticky:** **Known Agent Routing** com `known_worker_sid` / `known_worker_friendly_name`, recomendado para "last agent" e "preferred agent", com timeout e targets de fallback. O agente precisa estar na fila (senão dá erro 40152).
- **Métricas (TaskQueue Statistics, até 30 dias):** `longest_task_waiting_age`, `tasks_by_status`, `total_available_workers`, `total_eligible_workers`, tempo médio entre criação e aceite, `wait_duration_until_accepted`, `split_by_wait_time`.

### 4.8 Genesys Cloud
- **Routing methods:** Standard ACD, Predictive (IA), Preferred agent, Bullseye, Conditional group routing.
- **Evaluation methods:**
  - *Best Available Skills:* entre os 100 mais ociosos, maior proficiência média.
  - *All Skills Matching:* mais ocioso com todas as skills.
  - *Disregard Skills:* mais ocioso.
  - A ociosidade é calculada entre todas as filas do agente, olhando só os últimos 7 dias.
- **Prioridade:** *conversation score* (1 ponto = 60 s de antecipação na chegada) ou *priority score*.
- **Utilization** (padrões): 1 call, 1 callback, até 4 chats, 1 e-mail, até 4 mensagens, até 4 workitems. Configurável na org e por agente, incluindo quais tipos podem interromper quais.
- **Overflow:** anéis bullseye (ampliam o pool ou relaxam skills após um timeout por anel). **Conditional Group Activation** ativa um grupo de overflow quando o EWT passa de um limite e o remove quando o EWT normaliza.
- **Sticky:** **Preferred Agent Routing** com até 20 agentes, score 0–100 e 6 regras com timeout (o pool só cresce). Ignora skills, mas respeita utilization e presença; prioridade mais alta passa à frente. **Last agent routing** para e-mail só funciona se o envio for direto para a fila. Não é compatível com forecasting de WFM.

### 4.9 NICE CXone
- **Static** (legado) vs. **Dynamic delivery** (recomendado). Dynamic roteia por **tempo em Available + proficiência**, com AI Routing opcional. Bullseye e routing attributes estreitam o pool. **Integrated matching** compara a prioridade entre voz e digital (com aceleração e max priority por skill) e oferece **Target Agent**.
- **Modos de entrega:**
  - Automática: ritmo de ~15 s; a doc diz "sem load balancing"; continua entregando até o teto, mesmo com recusa.
  - Agent request: 1 voz + 1 digital e botão "+1".
- **Capacidade** (time, sobrescrita por agente): voz 1; chat e SMS ≤12; e-mail e work items ≤25; digital ≤50; **Total Contact Count** global. **Channel Lock** troca a lógica de "voz E chats" para "voz OU chats".
- **Recusa:** *refusal timeout* por canal (padrão 45 s, entre 15 e 300) transfere para outro agente.
- **Métricas:** Concurrent Time, Agent Time, Productivity Rate, elevações. *Focus time* por interação.

### 4.10 Five9
- O portal de documentação (`documentation.five9.com`, Zoomin) não devolveu páginas de roteamento via busca, map ou scrape. **Capacidade, fila e overflow: não encontrado.**
- O FAQ de marketing cita: skills-based routing com grupos e proficiência "ilimitados", prioridade (VIP, callbacks), roteamento por horário, distribuição "uniforme" por fila e *data-directed routing* ("cliente recorrente pode ir ao mesmo agente"). **Não verificado em doc técnica.**

### 4.11 Blip (Blip Desk)
- **Elegibilidade:** estar na fila do ticket, status Online e pelo menos 1 slot livre (`limite − tickets ativos > 0`).
- **Modos:**
  - Padrão: **menos tickets ativos**, desempate por há mais tempo sem receber.
  - Alternativo: **há mais tempo sem receber**, desempate por menos ativos.
- **Capacidade:** "Atendimentos por atendente" global + limite personalizado por atendente (alterar o global não afeta quem tem personalizado). Limite opcional de tickets **sem primeira resposta**. Opção de impedir que o atendente puxe tickets pelo botão "Atender".
- **Filas:**
  - **Regras de atendimento:** mensagem, nome, e-mail ou extras do contato com operadores contém/igual → fila. Sem match, vai para a fila **Default**.
  - **Regras de priorização:** baixa/média/alta; baixa ainda passa à frente de "sem prioridade".
  - Template de bot para verificar se há atendente online na fila antes de transbordar.
- **Sticky, skills, overflow entre filas:** não encontrado.

### 4.12 Zenvia
- As páginas públicas da Zenvia Customer Cloud (home, "atender melhor", preços) citam transbordo bot→humano, transferência manual de atendimento, tickets com SLA e chat. **Regras de distribuição: não encontrado.** Da página "atender melhor" li só os trechos sobre distribuição, filas e roteamento.
- O Movidesk aparece em fontes de terceiros como "Zenvia Movidesk", e a central do Movidesk usa o favicon "rebranding-zenvia". Não verifiquei se o módulo de tickets e chat da Customer Cloud usa o mesmo motor do Movidesk.

### 4.13 Octadesk
- **Roleta** (round robin) ligada nas configurações gerais ou por grupo de atendimento. A doc diz que quem fica online primeiro recebe todas as conversas que estão esperando em "Não atribuídas". Se todos ficam online juntos, a distribuição é igual e depois segue "conforme quem for encerrando mais conversas".
- **Por grupo:** incluir os responsáveis na roleta, **limitar conversas por usuário** (acima do limite, a conversa fica em "não atribuídas"), transferir após inatividade do usuário, encerrar após inatividade do contato, restringir visibilidade.
- **Automações:** transferência por inatividade do agente (tempo configurável). A config do grupo prevalece sobre a geral.
- **Sticky, skills, prioridade:** não encontrado.

### 4.14 Huggy
- **Autodistribuição:** lista de usuários disponíveis ordenada por quem está há mais tempo sem receber chat automático. Quem recebe vai para o fim da lista. Os chats seguem a ordem da fila.
- **Requisitos:** status Disponível, acesso ao departamento do chat, limite de chats simultâneos não excedido.
- **Modos combináveis:** geral, por departamento, ativação individual por usuário, **janela de horário da autodistribuição**.
- **Status:** Disponível, Indisponível, Em pausa + personalizados com mensagem automática enviada durante a ausência.
- **Sticky, skills, prioridade:** não encontrado.

### 4.15 Movidesk
- **Distribuição automática por grupo de chat:** o sistema segue uma **sequência ordenada de agentes** (reordenável por arrastar) e entrega ao próximo online que estiver abaixo do limite. A nova aba do chat já abre para o agente.
- **Capacidade:** "máximo de atendimentos simultâneos por agente" **por grupo**; vazio = sem limite. Não contam chats abertos a partir de tickets, chats internos e chats de outros grupos. Por isso o teto efetivo soma entre grupos.
- **Sem disponível:** todos no teto → fila de espera. O primeiro da fila vai para quem encerrar um chat (FIFO).
- **Sticky, skills:** não encontrado.

---

## 5. Boas práticas e armadilhas comuns

### Boas práticas recorrentes
1. **Capacidade por canal + teto total.** Ex.: 1 voz + N chats + M e-mails, com limite global (Intercom: limites somam e vale o mais restritivo; NICE: Total Contact Count; Zendesk: regra por canal).
2. **Separar tempo real de assíncrono.** Capacidade interrompível (Salesforce, Genesys), focus mode (Zendesk), channel lock (NICE), expressões "não recebe chat em voz" (Twilio).
3. **Contar só o trabalho ativo.** Excluir pendentes ou aguardando cliente (HubSpot, Freshdesk *load by status*, Zendesk inativos e pending/on-hold, Salesforce pausado = 0).
4. **Ordenar a fila por prioridade → SLA → idade**, não só FIFO (Intercom, Zendesk, Freshdesk, Genesys).
5. **Timeout de oferta + reoferta** para canais em tempo real (Zendesk 30 s, Salesforce push timeout, NICE refusal timeout).
6. **Reatribuir quando o agente sai.** Mudança de status, ociosidade ou desconexão (Zendesk auto-reassign, Freshchat, Octadesk, Intercom unsnooze).
7. **Skills com válvula de escape.** Timeout de skill opcional (Zendesk), drop skills (Salesforce), anéis bullseye (Genesys). Não exigir combinações raras de skills (Trailhead).
8. **Overflow explícito.** Grupos primários e secundários (Zendesk, Intercom). Grupo de overflow ativado por métrica, como EWT (Genesys CGA).
9. **Sticky com timeout e fallback.** O preferido tenta primeiro por X segundos e depois o pool abre (Genesys PAR, Twilio Known Agent).
10. **Limites menores para novatos** e níveis de carga por senioridade (Zendesk, Intercom, Freshchat load levels).
11. **Explicabilidade.** Mostrar por que um item não foi atribuído ou por que foi para fulano (Intercom unassigned reasons, HubSpot assignment details).
12. **Wrap-up** antes do próximo item (Intercom até 2 h, Zendesk wrap-up de voz).

### Armadilhas
1. **Round robin que ignora capacidade** sobrecarrega (Intercom round robin) e **atribui uma vez só**: se desatribuir, não roda de novo.
2. **Load-based premia quem resolve rápido** (alerta da doc do Freshdesk). Pode parecer injusto se a métrica de justiça for volume.
3. **Atribuição manual e pull furam o limite** (Zendesk, Intercom pull, HubSpot, NICE). É preciso monitorar quem passa do teto.
4. **Reabertos e inativos que voltam a ficar ativos** estouram a capacidade (Zendesk).
5. **Skills sem timeout travam a fila para sempre** (Zendesk). O oposto, sem espera nenhuma, entrega a quem não tem a skill (Intercom).
6. **Limite por grupo soma** quando o agente está em vários grupos (Movidesk).
7. **"Quem loga primeiro leva todo o backlog"** (Octadesk roleta). Sem um ritmo de entrega, o agente recebe tudo de uma vez.
8. **Entrega automática sem balanceamento** continua mesmo com recusas (NICE automatic delivery).
9. **Mudar o critério de ordenação com a fila cheia** gera ordem inesperada (Genesys).
10. **Preferred/known agent precisa ser membro da fila**, senão o timeout é pulado ou dá erro (Genesys, Twilio). O PAR do Genesys também é incompatível com forecasting de WFM.
11. **Custom queues furam a prioridade da fila padrão** (Zendesk). Voz atribuída não é reatribuída (Zendesk).
12. **A classificação roda só uma vez.** Se o campo mudar depois, o item não é reclassificado (Salesforce).
13. **Ambiguidade de "transbordo"** no mercado BR: bot→humano vs. overflow entre filas. Vale definir o termo no produto.

---

## 6. Fontes

### Zendesk
- About omnichannel routing: https://support.zendesk.com/hc/en-us/articles/4409149119514-About-omnichannel-routing
- Managing your omnichannel routing configuration: https://support.zendesk.com/hc/en-us/articles/4828787357210-Managing-your-omnichannel-routing-configuration
- Creating capacity rules to balance agent workloads: https://support.zendesk.com/hc/en-us/articles/4776409839770-Creating-capacity-rules-to-balance-agent-workloads
- Métricas (só títulos e snippets de busca, sem leitura completa): https://support.zendesk.com/hc/en-us/articles/5600291364378-Overview-of-the-omnichannel-agent-productivity-and-queues-dashboard · https://support.zendesk.com/hc/en-us/articles/5600298255770-Analyzing-omnichannel-agent-state-and-activity

### Salesforce
- Routing Model Options for Omni-Channel: https://help.salesforce.com/s/articleView?id=service.service_presence_routing_options.htm&language=en_US&type=5
- Routing Configuration Settings: https://help.salesforce.com/s/articleView?id=service.service_presence_routing_configuration_settings.htm&language=en_US&type=5
- Trailhead, Improve Work Distribution with Enhanced Omni-Channel: https://trailhead.salesforce.com/content/learn/modules/enhanced-omni-channel/improve-work-distribution-with-enhanced-omni-channel

### Freshworks
- About Omniroute (Advanced Automatic Routing): https://support.freshdesk.com/support/solutions/articles/196581-about-omniroute-advanced-automatic-routing-
- Configure Omniroute Settings: https://support.freshdesk.com/support/solutions/articles/238979-configure-omniroute-settings
- Freshchat IntelliAssign: https://crmsupport.freshworks.com/support/solutions/articles/50000004357-what-is-conversation-routing-or-intelliassign-in-freshchat-

### Intercom
- Balanced assignment deep dive: https://www.intercom.com/help/en/articles/6553774-balanced-assignment-deep-dive
- Workload management explained: https://www.intercom.com/help/en/articles/6560715-workload-management-explained
- Skill-based routing: https://www.intercom.com/help/en/articles/15858833-skill-based-routing
- Monitoring your team's workload and capacity: https://www.intercom.com/help/en/articles/6560699-monitoring-your-team-s-workload-and-capacity

### HubSpot
- Route tickets in help desk: https://knowledge.hubspot.com/help-desk/route-tickets-in-help-desk
- Set ticket capacity limits for users in help desk: https://knowledge.hubspot.com/help-desk/set-ticket-capacity-limits-for-users-in-help-desk

### Twilio
- Lifecycle of a Task, Workflows and Assignment: https://www.twilio.com/docs/taskrouter/lifecycle-task-workflows-and-assignment
- Multitasking: https://www.twilio.com/docs/taskrouter/multitasking
- Known Agent Routing: https://www.twilio.com/docs/taskrouter/workflow-configuration/known-agent-routing
- Ordering Workers: https://www.twilio.com/docs/taskrouter/order-workers
- TaskQueue Statistics: https://www.twilio.com/docs/taskrouter/api/taskqueue-statistics

### Genesys Cloud
- Routing and evaluation methods: https://help.genesys.cloud/articles/acd-evaluation-routing-methods/
- Bullseye routing overview: https://help.genesys.cloud/articles/bullseye-routing-overview/
- Preferred agent routing behavior: https://help.genesys.cloud/articles/preferred-agent-routing-behavior/
- Agent utilization: https://help.genesys.cloud/articles/utilization/

### NICE CXone
- Dynamic Delivery: https://help.nice-incontact.com/Content/acd/routing/dynamicdelivery/dynamicdelivery.htm
- Manage Contact Delivery Settings for Dynamic Delivery: https://help.nice-incontact.com/Content/acd/routing/dynamicdelivery/managecontactdeliverysettings.htm

### Five9 (marketing, não é doc técnica)
- What Is an Automatic Call Distributor (FAQ): https://www.five9.com/faq/what-is-an-acd
- Portal de documentação (sem conteúdo de roteamento recuperável): https://documentation.five9.com/

### Blip
- Como funciona a distribuição automática de tickets no Blip Desk: https://help.blip.ai/hc/pt-br/articles/18694892640791
- Como gerenciar filas e regras de atendimento no Blip: https://help.blip.ai/hc/pt-br/articles/4474425334423
- Como verificar atendentes disponíveis por fila de atendimento: https://help.blip.ai/hc/pt-br/articles/4474382512919
- Preferências no Blip Desk e Desk App: https://help.blip.ai/hc/pt-br/articles/4474382630551

### Zenvia
- Customer Cloud, preços e recursos: https://zenvia.com/precos/
- Customer Cloud, atender melhor (lido parcialmente, trechos sobre distribuição): https://zenvia.com/customer-cloud/atender-melhor/
- Relação Zenvia ↔ Movidesk (terceiros): https://www.sentinelone.com/vulnerability-database/cve-2025-0970/ · https://www.sunsethq.com/layoff-tracker/movidesk

### Octadesk
- Como funciona a roleta de chat no Octadesk: https://help.octadesk.com/a/como-funciona-a-roleta-de-chat-no-octadesk/
- Como crio Grupos de Atendimento: https://help.octadesk.com/a/como-crio-grupos-de-atendimento-para-chat/
- Encerramento automático e transferência de conversas inativas: https://help.octadesk.com/a/como-ativar-o-encerramento-automatico-e-a-transferencia-de-conversas-inativas-em-breve-disponivel/

### Huggy
- Autodistribuição de atendimentos: https://help.huggy.io/recursos/autodistribuicao-de-atendimentos
- Como gerenciar seu status: https://help.huggy.io/recursos/como-gerenciar-meu-status

### Movidesk
- 05 - Chat Distribution: https://atendimento.movidesk.com/kb/en/article/10498/05-chat-distribution
