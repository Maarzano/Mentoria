# svc-notifications

Envio de **push, email, WhatsApp** e **hub de tempo real** (WebSocket/Phoenix Channels) para notificar lojista e comprador sobre eventos do sistema (pedido aceito, pronto, a caminho, entregue, etc.).

## Stack

| Item | Escolha |
|---|---|
| Linguagem | **Elixir** |
| Web framework | **Phoenix** + **Phoenix Channels** (substitui SignalR do plano original) |
| Banco | PostgreSQL — schema `notifications` (driver: `Ecto`) |
| Mensageria | RabbitMQ (`broadway_rabbitmq`) — consumir eventos do sistema |
| Push | FCM / APNs (lib `pigeon` ou HTTP direto) |
| Email | provedor a definir (SES, SendGrid, Resend) |
| WhatsApp | API Cloud do Meta |
| Observabilidade | `opentelemetry_phoenix` + `opentelemetry_exporter` → OTel Collector |

### Por que Elixir aqui

- **BEAM (Erlang VM)**: milhões de processos leves, ideal para milhares de conexões WebSocket abertas (lojista e comprador acompanhando pedido em tempo real).
- **Phoenix Channels**: mais simples e robusto que SignalR para o caso de fan-out massivo.
- **Tolerância a falhas** (supervisores, "let it crash") — perfeito para serviço de notificação que precisa ser resiliente a falhas de provedor externo.
- **Broadway**: pipeline declarativo de consumo de fila com backpressure nativo.

> ⚠️ Esta escolha **substitui** a menção a SignalR no ADR-014 / `modules.md` para o componente de tempo real do FoodeApp.

## Responsabilidades

- Consumir eventos da fila (`OrderAccepted`, `OrderReady`, `LocationUpdated` relevantes ao pedido, etc.).
- Decidir canal por evento + preferências do usuário (push? email? WhatsApp? in-app?).
- **Hub real-time**: cliente conecta via Phoenix Channel autenticado (JWT do ZITADEL), recebe push do estado do pedido em tempo real.
- Idempotência (ADR-013): chave `event_id`.
- Histórico de notificações enviadas (auditoria).

## Arquitetura proposta

```
svc_notifications/
├── mix.exs
├── lib/
│   ├── svc_notifications/
│   │   ├── application.ex
│   │   ├── domain/         # contextos
│   │   ├── inbox/          # consumers Broadway (RabbitMQ)
│   │   ├── channels/       # provedores: Push, Email, WhatsApp
│   │   └── repo.ex
│   └── svc_notifications_web/
│       ├── endpoint.ex
│       └── channels/       # UserChannel (real-time)
└── priv/repo/migrations/
```

## 🗣️ Pontos para discussão

- [ ] Confirmar substituição **SignalR → Phoenix Channels** no ADR-014.
- [ ] Como o **Kong** roteia WebSocket para Phoenix? (Kong suporta WS upstream — validar config.)
- [ ] **Preferências de notificação** por usuário moram aqui ou em `svc-users`?
- [ ] Templates de mensagem: hardcoded em código vs tabela editável vs CMS externo?
- [ ] Provedor de email/WhatsApp — qual escolher? (SES x SendGrid x Resend; Meta Cloud API direta?)
- [ ] Estratégia de **retry** em falha de push (FCM offline) — Broadway dead-letter ou tabela de outbox local?
- [ ] Contratos com outros serviços: Protobuf (`shared/contracts-proto`) — usar `protobuf-elixir`?
