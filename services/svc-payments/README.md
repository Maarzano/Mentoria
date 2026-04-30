# svc-payments

Integração com **Mercado Pago** (ADR-025): autorização, captura, estorno, webhooks. Participa da SAGA orquestrada por `svc-orders`.

## Stack

| Item | Escolha |
|---|---|
| Linguagem | **Rust** |
| Web framework | a definir — `axum` (Tokio, mais maduro) ou `actix-web` |
| Banco | PostgreSQL — schema `payments` (driver: `sqlx`) |
| Mensageria | RabbitMQ (`lapin`) — consumir comandos da SAGA, publicar eventos |
| Observabilidade | `tracing` + `opentelemetry-otlp` → OTel Collector |

### Por que Rust aqui

- **Segurança de tipos e memória** num serviço que mexe com dinheiro.
- **Latência baixíssima e previsível** (sem GC) — pagamento é caminho crítico do checkout.
- Footprint pequeno em containers, ótimo para escalar horizontalmente.
- Bibliotecas maduras: `sqlx` (compile-time SQL), `axum`, `tower` (middleware/retry/Polly-equivalente), `lapin` (AMQP).

### Custo

- Curva de aprendizado da equipe (vs C#).
- Ecossistema de SAGA não tão "out-of-the-box" quanto MassTransit — possivelmente implementar o handler manualmente seguindo o contrato do `svc-orders`.

## Responsabilidades

- Receber comandos da SAGA: `AuthorizePayment`, `CapturePayment`, `RefundPayment`.
- Chamar Mercado Pago (HTTP) com retry/circuit breaker (`tower-retry`).
- Persistir transações + status (idempotência por `payment_intent_id`).
- Receber **webhooks** do Mercado Pago e reconciliar.
- Publicar eventos: `PaymentAuthorized`, `PaymentCaptured`, `PaymentFailed`, `PaymentRefunded`.

## Arquitetura proposta

```
svc-payments/
├── Cargo.toml
├── src/
│   ├── main.rs
│   ├── api/         # axum routes (webhooks)
│   ├── application/ # casos de uso (authorize, capture, refund)
│   ├── domain/      # tipos, eventos, máquina de estados
│   ├── infra/
│   │   ├── db/      # sqlx repositories + migrations
│   │   ├── amqp/    # lapin consumers/publishers
│   │   └── mp/      # cliente Mercado Pago
│   └── observability.rs
└── migrations/
```

## 🗣️ Pontos para discussão

- [ ] **`axum` vs `actix-web`** — recomendação: axum (alinhado ao stack Tokio do `lapin` e `sqlx`).
- [ ] **Outbox em Rust** — não há equivalente direto ao MassTransit Outbox. Implementar manualmente: tabela `outbox_messages` + worker que lê e publica?
- [ ] Migrations: `sqlx-cli` ou `refinery`?
- [ ] Contratos dos eventos: usar **Protobuf** (`shared/contracts-proto` + `prost`/`tonic`) para alinhar com o resto do monorepo? Ou JSON Schema?
- [ ] Estratégia de **PCI**: confirmar que tokenização é 100% Mercado Pago e nunca tocamos cartão cru.
- [ ] Worker de webhooks idempotentes (ADR-013) — chave: `mp_event_id`.
