---
status: accepted
---

# O n8n continua reconhecendo o repasse pelo texto do artigo

Depois que o NDesk passa a escolher o N2, o n8n continua sabendo que houve um repasse pelo texto do artigo da
macro ("Realizamos uma análise prévia da sua ocorrência"). É assim que ele decide mencionar o dono no Discord e
mandar o e-mail "em andamento" ao cliente. Só a atribuição deixou de depender do texto.

## Contexto

O n8n classifica todas as macros pelo texto do artigo (Roadmap, Engenharia, encerramento, análise prévia). Com
o NDesk escolhendo o dono no mesmo salvamento do artigo, o payload de "Ticket Atualizado" já chega com o N2
certo, e a menção pode usar o ID do Discord do dono.

## Alternativas consideradas (e por que rejeitadas)

**O NDesk manda um aviso próprio "Ticket Repassado"**, só quando o repasse de fato acontece: um trigger e um
webhook novos no NDesk e um ramo novo no n8n. Rejeitada pelo usuário: mais trabalho nas duas pontas para ganhar
pouco, e diferente de como o n8n trata as outras macros.

## Consequências

- Num repasse não realizado, o Discord anuncia o ticket mencionando o N1, que continua dono, e o cliente recebe
  o "em andamento". Na prática, isso avisa o time.
- Se alguém mudar o texto da macro, o Discord e o e-mail param, como hoje.
- Qualquer nota criada pela distribuição na mesma requisição precisa vir antes do artigo da macro, porque o
  webhook leva só o último artigo.
