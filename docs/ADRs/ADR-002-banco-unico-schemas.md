# ADR-002: Servidor PostgreSQL Único com Múltiplos Bancos por Serviço

**Status:** Revisado  
**Data original:** 2026-03-10  
**Data da revisão:** 2026-06-01

---

## Contexto

O desenho original desta ADR descrevia um único banco com separação por schemas. A implementação atual no Terraform evoluiu para um modelo com **um único servidor PostgreSQL** e **múltiplos bancos lógicos**, um por serviço.

Isso mantém custo e operação centralizados (uma instância gerenciada), mas aumenta isolamento entre domínios em comparação ao uso de schemas dentro do mesmo banco.

---

## Decisão

Usaremos **um único servidor PostgreSQL** com **um database por serviço**.

Exemplos atuais:

- `foodeapp_auth`
- `foodeapp_establishments`
- `foodeapp_catalog`
- `foodeapp_events`
- `foodeapp_locations`
- `foodeapp_orders`
- `foodeapp_notifications`
- `foodeapp_payments`
- `foodeapp_flags`

Cada microserviço acessa apenas seu próprio database. Não haverá JOINs entre databases. Toda troca de dados entre serviços ocorre via API ou fila (RabbitMQ + Outbox).

---

## Aderência com Terraform

Implementação correspondente:

- 1 servidor PostgreSQL (`azurerm_postgresql_flexible_server`)
- N databases (`azurerm_postgresql_flexible_server_database`)

Ou seja: o modelo oficial passa a ser "single server, multi-database".

---

## Consequências

### Positivas

- Melhor isolamento lógico entre serviços do que schema compartilhado.
- Permissões por database mais simples de segregar.
- Ainda mantém custo/operação de uma única instância gerenciada.
- Facilita futura migração para servidor dedicado por domínio crítico.

### Trade-offs

- Ainda existe ponto único de falha no nível de servidor (se o servidor cair, todos os bancos ficam indisponíveis).
- Escalabilidade ainda é compartilhada no nível da instância.
- Administração de migrations exige conexão por database de cada serviço.

### Observações

- Continua sendo uma estratégia intermediária entre monolito de dados e isolamento físico completo por serviço.
- Migração futura para "1 servidor por serviço" permanece possível e menos traumática do que partir de schema único.

---

## Regra de ouro: transação local vs integração distribuída

| Escopo da alteração | Mecanismo obrigatório |
|---|---|
| Dentro do mesmo database (mesmo serviço) | Transação ACID no PostgreSQL |
| Entre serviços (databases diferentes) | Fila/evento (RabbitMQ + Outbox) ou API síncrona |

Não usar transações distribuídas entre databases como mecanismo de acoplamento entre serviços.

---

## Relacionamentos

- ADR-003 (stack PostgreSQL)
- ADR-006 (RabbitMQ)
- ADR-007 (SAGA)
- ADR-017 (Outbox)
