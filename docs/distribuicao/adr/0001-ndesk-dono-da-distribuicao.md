---
status: accepted
---

# O NDesk é dono da escala e executa a distribuição; o n8n deixa de atribuir

A distribuição de tickets (N1 na criação, N2 no repasse por menor carga) passa a ser configurada e executada
dentro do NDesk, por uma ação de macro/trigger e uma tela no admin clássico. O n8n deixa de atribuir e fica
com o resto do que já fazia: e-mails, mensagens de horário, Discord e automações de estado. Ele lê o dono já
escolhido no payload do webhook.

## Contexto

Até a NDESK-70, o N1 era o `owner_id 585` fixo no fluxo "NDesk - Notificações", e o N2 era escolhido pelo
fluxo "LB - Atribuição de Ticket", que guardava a carga numa data table do n8n e só funcionava com dois
agentes. Os IDs dos agentes também estavam fixos na menção do Discord, na liberação de pontos e no nó que
decide se uma resposta é do suporte. Trocar o N1 ou incluir alguém no N2 exigia editar o n8n.

## Alternativas consideradas (e por que rejeitadas)

**O n8n continua atribuindo e lê a escala do NDesk por API.** Mantém a regra num JS sem teste (onde nasceu o
bug dos dois agentes) e duas pontas para manter em sincronia.

## Consequências

- A regra ganha testes automatizados no NDesk; o comportamento do n8n vira um roteiro e um checklist de virada.
- A virada liga o NDesk antes de publicar o n8n: com as duas pontas ativas ao mesmo tempo, o n8n sobrescreve o
  dono com o comportamento antigo, o que é preferível a tickets sem dono.
- O aviso do Discord passa a depender do atributo "ID do Discord" do agente, e não de nomes fixos no n8n.
- O n8n continua reconhecendo o repasse pelo texto do artigo para o Discord e o e-mail (ADR 0004).
