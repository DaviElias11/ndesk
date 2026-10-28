---
status: accepted
---

# Repasse sem complexidade recusa a macro; sem N2 no rodízio, a macro passa com nota

Quando alguém aplica a macro de análise prévia num ticket **sem complexidade**, a ação de distribuição levanta
um erro e a macro inteira é desfeita: nem a mensagem ao cliente, nem os campos, nem o dono. Quando **nenhum N2
está no rodízio**, a macro passa normalmente, o ticket fica com quem repassou, entra uma nota interna e quem
repassou é notificado; depois, alguém passa o ticket à mão.

## Contexto

A macro faz tudo de uma vez: avisa o cliente ("Realizamos uma análise prévia"), muda os campos e pede o
repasse. Nos dois casos o repasse não pode acontecer, mas só no primeiro o próprio N1 resolve na hora.

## Alternativas consideradas (e por que rejeitadas)

**Nota interna nos dois casos.** Sem complexidade, o cliente seria avisado da análise enquanto o ticket fica
parado, e se a macro fechar a aba o N1 nem vê a nota.

**Recusa nos dois casos.** Com o N2 todo fora do rodízio, o N1 ficaria impedido de avisar o cliente até alguém
voltar, sem nada que ele possa fazer.

**Uma segunda macro "Repassar ao N2", sem mensagem ao cliente, para depois do repasse não realizado.** O
usuário preferiu a atribuição manual: o caso só acontece com o N2 inteiro fora ao mesmo tempo.

## Consequências

- O aviso de erro do app clássico dura 2 s; para esta recusa ele fica até a pessoa fechar, também na macro em
  lote, que é recusada inteira.
- A recusa precisa acontecer antes de qualquer escrita da requisição.
- As tags da macro são gravadas via API antes do envio e não são desfeitas pela recusa.
- Em trigger não existe recusa: a reabertura usa fallbacks.
