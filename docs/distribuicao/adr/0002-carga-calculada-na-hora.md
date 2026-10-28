---
status: accepted
---

# A carga é calculada na hora, a partir dos tickets abertos, sem contador

A carga de um agente é a soma dos pesos da complexidade dos tickets abertos de que ele é dono, calculada a
cada decisão e a cada exibição da tela. Não há coluna nem tabela de carga.

## Contexto

O n8n guardava a carga num contador (`carga_atual`): somava no repasse e subtraía no fechamento, pelo fluxo
"LB - Liberação de Pontos". O contador derivava: ticket reaberto não voltava a somar, e se a complexidade
mudava durante o atendimento a liberação subtraía outro valor.

## Alternativas consideradas (e por que rejeitadas)

**Contador atualizado por eventos** (repasse, fechamento, reabertura, mudança de complexidade, troca de dono).
Cada evento esquecido vira drift silencioso, e a tela mostraria um número que pode não bater com os tickets
(critério de aceite 5).

## Consequências

- A carga sempre bate com os tickets, por construção.
- Cada decisão faz uma consulta agregada sobre os tickets abertos dos candidatos; com o volume do NDesk, é
  barata.
- Reabertura, fechamento e troca manual de dono entram na conta sem código extra.
