# Distribuição de atendimentos

Contexto da feature que decide quem fica com cada ticket do NDesk: todo ticket novo entra pelo N1, e o N1
repassa ao N2 pela macro de análise prévia, que escolhe o agente de menor carga. A escala e as regras são
configuradas numa tela do admin clássico. Glossário — sem detalhes de implementação (ver
`docs/plans/2026-10-20-distribuicao-atendimentos-design.md`).

## Linguagem

**Escala**:
A configuração de quem atende: as listas do N1 e do N2, o Interruptor de cada N2 e o Responsável de Disparos.
O NDesk é a fonte da verdade da Escala (ADR 0001).
_Evitar_: plantão, turno (a Escala não tem horário)

**N1 (Entrada)**:
A lista de agentes que recebe todo ticket novo, inclusive os de Disparos, os divididos e os abertos por um
agente. O N1 recebe em qualquer situação — offline, deslogado ou com "Fora do escritório" — e não tem
substituto nem Interruptor.
_Evitar_: triagem, primeiro nível, fila

**Vez do N1**:
Com mais de uma pessoa no N1, recebe o ticket novo quem está há mais tempo sem receber; quem nunca recebeu vem
primeiro. Não é Rodízio: no N1 não há Interruptor nem Carga na decisão. No código: `last_assigned_at` do
membro `n1`.

**N2 (Repasse)**:
A lista de agentes que recebe os tickets repassados pelo N1. Cada um tem um Interruptor.
_Evitar_: segundo nível, suporte avançado, LB

**Repasse**:
O momento em que alguém aplica a macro de análise prévia e o ticket muda de dono para o N2 (ou para o
Responsável de Disparos). Exige Complexidade preenchida; sem ela, a macro é recusada.
_Evitar_: transferência, escalonamento, encaminhamento

**Repasse não realizado**:
A macro de análise prévia passou, mas não havia Candidato no Rodízio: o dono não muda, entra uma nota interna
e quem aplicou a macro é notificado. Depois, alguém passa o ticket à mão.

**Rodízio**:
O conjunto de agentes do N2 que podem receber um Repasse agora: Interruptor ligado e sem "Fora do escritório"
valendo. Estar offline ou deslogado **não** tira ninguém do Rodízio. Só existe no N2.
_Evitar_: disponível/online (são estados de presença, que não contam); rodízio do N1 (é a Vez do N1)

**Candidato**:
Quem pode receber um ticket específico: está no Rodízio, pode ser dono do ticket (ativo, agente, com acesso
total ao grupo dele) e não é quem está repassando. Difere do Rodízio porque depende do ticket.

**Interruptor**:
A chave "No rodízio" de cada agente do N2, ligada ou desligada na tela. Desligar não mexe nos tickets que já
estão com o agente nem na função de Responsável de Disparos. O N1 não tem Interruptor.
_Evitar_: pausa, status

**Complexidade**:
O atributo do ticket (em produção, `complexidades`) com os valores fácil, moderado e complexo, preenchido pelo
N1 antes do Repasse. Cada valor tem um Peso.
_Evitar_: dificuldade, prioridade (prioridade é outro campo)

**Peso**:
Os pontos de cada valor de Complexidade: fácil 1, moderado 3, complexo 6 (configuráveis).
_Evitar_: pontuação, score

**Carga**:
A soma dos Pesos dos tickets abertos de que o agente é dono, calculada na hora, sem contador. Conta todo
estado aberto, inclusive "Aguardando cliente"; não contam os estados e prioridades marcados na tela (em
produção, "Melhoria" e "4 sem previsão", que marca Engenharia). Ticket sem Complexidade pesa 0. Ao decidir
para um ticket, ele mesmo fica fora da soma.
_Evitar_: fila, volume, pontos acumulados

**Último repasse**:
Quando o agente do N2 recebeu um ticket pelo Rodízio pela última vez — num Repasse ou numa Reabertura
redistribuída. Desempata a menor Carga: recebe quem está há mais tempo sem receber; quem nunca recebeu vem
primeiro. Receber um Disparo, ser mantido numa reaplicação da macro ou receber à mão não conta. No código:
`last_assigned_at` do membro `n2`.
_Evitar_: última atribuição (o dono também muda por outros caminhos)

**Disparos**:
Os tickets do grupo configurado como de Disparos e campanhas. Entram pelo N1 como qualquer ticket; no Repasse
vão para o Responsável de Disparos em vez do Rodízio e somam na Carga dele.
_Evitar_: campanha (sozinho), massa

**Responsável de Disparos**:
O agente escolhido na tela para receber os Disparos no Repasse. Pode ser do N2, e o Interruptor não vale para
essa função. Com "Fora do escritório", ou se não puder ser dono do ticket, o Disparo segue o Rodízio do N2.

**Reabertura**:
O cliente responde a um ticket fechado e ele volta a um estado aberto. Mesclar ou remover não é Reabertura, e
quando um agente reabre, a distribuição não mexe no dono. O ticket fica com Quem atendeu se ele está no N1,
no Rodízio ou fora das listas (Engenharia, gestor); senão, passa pela regra do Repasse.

**Quem atendeu**:
O dono do ticket antes da Reabertura, mesmo que o follow-up por e-mail tenha apagado o dono no caminho.
_Evitar_: dono atual (pode já ter sido apagado na Reabertura)

**ID do Discord**:
O atributo do agente que o n8n usa para mencionar o dono do ticket no Discord.
