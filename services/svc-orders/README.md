# svc-orders

Núcleo transacional do FoodeApp: **carrinho** (Redis), **ciclo de pedido** (PostgreSQL), e **orquestração da SAGA** que coordena `svc-payments`, `svc-catalog`, `svc-establishments`, `svc-notifications`.

## Stack

| Item | Escolha |
|---|---|
| Linguagem | **C# / .NET 10 (LTS)** |
| Estado efêmero (carrinho) | **Redis** (ADR-012) |
| Banco | PostgreSQL — schema `orders` |
| Mensageria | RabbitMQ via MassTransit + **Outbox** (ADR-006, ADR-017) |
| Padrão distribuído | **SAGA orquestrada** (ADR-007, ADR-008) |

> Por que C# e não Elixir/Go? O domínio é rico (regras, estados, compensações) — produtividade DDD/CQRS em .NET ganha. Concorrência aqui não é o gargalo (é I/O em fila).

## Responsabilidades

- **Carrinho** (Redis): adicionar/remover item, snapshot de preço, TTL.
- **Pedido** (Postgres): checkout → confirmar → pago → preparando → pronto → entregue/cancelado.
- **SAGA**: reservar item, autorizar pagamento (`svc-payments`), confirmar/compensar, notificar (`svc-notifications`).
- **Idempotência** em consumers (ADR-013).

## 🗣️ Pontos para discussão

- [ ] **Orquestração explícita** (state machine no svc-orders) **vs coreografia** com eventos? — ADR-008 deixou em aberto. Recomendação: orquestrada por causa das compensações.
- [ ] State machine: **MassTransit Saga** (StateMachineSaga + persistência) ou rolar mão (entidade `Order` como agregado)?
- [ ] Carrinho expira em quanto tempo? (sugestão 24h)
- [ ] Snapshot de preço: chamar `svc-catalog` no checkout ou já guardar preço no item do carrinho?
- [ ] Política de cancelamento: em quais estados o usuário/lojista pode cancelar? Reembolso parcial?
