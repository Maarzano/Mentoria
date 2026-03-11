# ADR-005: Tabelas Normalizadas para Escrita e Desnormalizadas para Leitura (Sem Banco Separado)

**Status:** Aceito  
**Data:** 2026-03-10

---

## Contexto

Em sistemas com CQRS (ADR-004), a separação de modelos de leitura e escrita é um conceito importante. Entretanto, a implementação completa do CQRS com bancos físicos separados (write store + read store) implica:

- Sincronização de dados entre os bancos (replicação ou eventos).
- Lag de replicação e seus respectivos desafios (ver ADR-019 para mitigação via UI Otimista).
- Maior custo de infraestrutura e complexidade operacional.

O time quer obter os **benefícios dos modelos separados** sem o custo de infraestrutura duplicada no estágio inicial.

## Decisão

Dentro do **mesmo banco de dados** (e do mesmo schema por serviço — ADR-002), teremos **dois conjuntos de tabelas**:

**Tabelas de Escrita (Write Tables):**

- Normalizadas (3FN ou próximo).
- Representam o estado canônico do domínio.
- Manipuladas exclusivamente pelos Command Handlers.
- Integridade garantida por constraints, foreign keys e validações de domínio.

**Tabelas de Leitura (Read Tables / Projeções):**

- Desnormalizadas, otimizadas para as queries mais frequentes da UI.
- Populadas/atualizadas de forma derivada a partir dos eventos dos Commands.
- Acessadas exclusivamente pelos Query Handlers.
- Não possuem regras de negócio — são projeções de leitura.

A sincronização entre tabelas de escrita e leitura ocorre **dentro da mesma transação** (ou via Outbox Pattern — ADR-017) ao processar um Command.

## Consequências

### Positivas

- Queries de leitura são extremamente eficientes: lêem de tabelas já "montadas" para a UI, sem JOINs pesados.
- Separação clara de responsabilidades no banco de dados reflete a separação CQRS no código.
- Não há custo de infraestrutura adicional de um segundo banco.
- Sem lag de replicação entre escrita e leitura, pois tudo está no mesmo banco.
- Facilita evolução futura: caso necessário, as tabelas de leitura podem ser movidas para um store separado (Redis, Elasticsearch, segundo PostgreSQL) sem alterar os Query Handlers — apenas a fonte de dados muda.

### Negativas / Trade-offs

- O banco de dados terá um volume maior de tabelas (write + read).
- A lógica de atualização das tabelas de leitura precisa ser mantida sincronizada com o modelo de escrita — mudanças no domínio exigem atualizar ambos.
- Não há ganho de performance de I/O que um banco de leitura dedicado (com réplica de leitura) traria.
- Pode gerar redundância de dados dentro do mesmo banco.

### Neutras / Observações

- As tabelas de leitura são tratadas como **projeções descartáveis**: podem ser recriadas a partir das tabelas de escrita a qualquer momento (estratégia de replay).
- **Não usar o banco de leitura separado inicialmente** é uma decisão consciente para simplificar a operação. A arquitetura do código já está preparada para essa evolução.
- O padrão Outbox (ADR-017) pode ser usado para garantir que a atualização das tabelas de leitura e o envio de eventos para filas seja atômico com a escrita.
- **Transação interna**: tabelas write e read do mesmo serviço vão sempre na mesma transação — são parte do mesmo schema e do mesmo bounded context. O padrão de commit é:

```sql
BEGIN;
  -- 1. Escrita normalizada (estado canônico)
  UPDATE orders.orders SET status = 'confirmed' WHERE id = $1;

  -- 2. Projeção de leitura (atualizada junto, sem lag)
  UPDATE orders.read_orders SET status = 'confirmed', ... WHERE order_id = $1;

  -- 3. Outbox ("carta" para outros serviços, publicada de forma assíncrona)
  INSERT INTO orders.outbox_messages (type, payload) VALUES ('OrderConfirmed', $2);
COMMIT;
```

  O efeito em outros serviços (`payments.*`, `notifications.*`, etc.) chega **via fila**, processado em transações locais independentes de cada serviço receptor — nunca em transação compartilhada. Ver ADR-002 (regra de ouro), ADR-017 (Outbox).
