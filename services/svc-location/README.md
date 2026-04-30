# svc-location

Rastreamento de **GPS em tempo real** (entregadores, lojas móveis, eventos itinerantes) e **geo-queries** (estabelecimentos próximos, cobertura de entrega).

## Stack

| Item | Escolha |
|---|---|
| Linguagem | **Go** |
| Web framework | a definir — `chi` (minimalista, padrão Go) ou `gin` |
| Estado quente (GPS atual) | **Redis** com `GEOADD` / `GEOSEARCH` (ADR-012) |
| Banco frio | PostgreSQL com **PostGIS** — schema `locations` |
| Mensageria | RabbitMQ — consumir/publicar updates de posição |
| Observabilidade | `otelhttp` + `otel-go` → OTel Collector |

### Por que Go aqui

- **Concorrência massiva** (goroutines) — milhares de conexões abertas recebendo pings GPS simultaneamente.
- **Footprint mínimo** (binário estático, ~10-20 MB) — ótimo para escalar pods.
- Stdlib forte para HTTP/WebSocket sem framework pesado.
- `go-redis` e `pgx` são clientes maduros e rápidos.

## Responsabilidades

- Receber pings GPS (HTTP ou WebSocket) e atualizar Redis (`GEOADD locations:active`).
- Expor **geo-queries**: "lojas dentro de raio X", "entregadores próximos do pedido Y".
- Persistir trilhas históricas (sample) no PostGIS para auditoria/analytics.
- Publicar eventos: `LocationUpdated`, `EnteredArea`, `LeftArea`.

## Arquitetura proposta

```
svc-location/
├── go.mod
├── cmd/server/main.go
├── internal/
│   ├── api/           # handlers HTTP/WS
│   ├── domain/        # tipos (Coord, Track, Area)
│   ├── application/   # casos de uso
│   ├── infra/
│   │   ├── redis/     # GEOADD/GEOSEARCH
│   │   ├── postgis/   # repos
│   │   └── amqp/      # publishers
│   └── observability/
└── migrations/
```

## 🗣️ Pontos para discussão

- [ ] **Pings via HTTP polling vs WebSocket vs MQTT** — qual frequência (5s? 15s?) e qual protocolo? WS recomendado para mobile.
- [ ] Política de **retenção** das trilhas históricas (30 dias? 90?).
- [ ] **PostGIS** vale o ônus operacional ou Redis Geo + cálculos in-memory cobrem tudo?
- [ ] Privacy: pings antigos devem ser anonimizados após X tempo? LGPD.
- [ ] Como o `bff-mobile` consome: stream WS direto ou via `svc-notifications` (que já tem hub)?
- [ ] Contratos: Protobuf via `shared/contracts-proto`?
