# bff-web (BFF do Lojista)

> Também referenciado como **bff-lojista** — pasta mantida como `bff-web` por simetria com `apps/web`.

**BFF (Backend for Frontend)** dedicado ao painel do **lojista** (`apps/web`, React + Vite). Não tem regra de negócio — é **agregador de I/O**: junta chamadas a microsserviços, filtra, transforma payloads para o painel e cuida de políticas transversais (cache curto, idempotência, rate limit por use case, observabilidade).

> A arquitetura é **idêntica** à do `bff-mobile` (ver [README do bff-mobile](../bff-mobile/README.md)). O que muda são as **personas, use cases e padrões de paginação**. Eventualmente, `platform/` deve virar `packages/bff-platform` compartilhado entre os dois.

---

## 1. Stack

| Item | Escolha |
|---|---|
| Linguagem | **TypeScript** |
| Runtime | **Bun** |
| Framework HTTP | **Hono** |
| Tipos cliente↔BFF | **tRPC** |
| Validação | **Zod** |
| Cache | **Redis** |
| Idempotência | **Redis** (chave `Idempotency-Key`) |
| Observabilidade | **OpenTelemetry** (traces + métricas + logs estruturados) |
| Testes | **`bun test`** |
| Auth | Confia no Kong — lê `X-User-Id` / `X-User-Roles` (ZITADEL via Kong, ADR-026) |

---

## 2. Princípios

1. **Sem regra de negócio** — agregador de I/O.
2. **Endpoints por use case, NÃO por tela.**
   | ✅ Bom (use case) | ❌ Ruim (tela disfarçada) |
   |---|---|
   | `updateMenuItem` | `editItemModalData` |
   | `listEstablishmentOrders` | `ordersDashboardScreen` |
   | `changeOrderStatus` | `orderDetailsScreen` |
   | `getEstablishmentDailySummary` | `dashboardHomeScreen` |
3. **Fan-out paralelo com graceful degradation** (`Promise.allSettled`).
4. **Stateless** — estado em Redis ou nos microsserviços.
5. **Composição** sobre herança — context object, sem container DI.

---

## 3. Arquitetura — Vertical Slice + Downstream Adapters

> Mesma estrutura do `bff-mobile`. **Não usamos Clean Architecture** — sem regra de negócio para isolar.

```
bff-web/
├── src/
│   ├── index.ts                          # bootstrap Hono + tRPC
│   │
│   ├── usecases/                         # 1 pasta = 1 use case
│   │   ├── update-menu-item/
│   │   │   ├── input.ts / output.ts
│   │   │   ├── handler.ts
│   │   │   ├── procedure.ts
│   │   │   └── handler.test.ts
│   │   ├── list-establishment-orders/
│   │   ├── change-order-status/
│   │   ├── get-establishment-daily-summary/
│   │   ├── issue-realtime-token/         # token p/ tópico establishment:{id}
│   │   └── ...
│   │
│   ├── platform/                         # idem bff-mobile
│   │   ├── clients/                      # orders, catalog, establishments, payments, users
│   │   ├── http/                         # fetch-with-policies (timeout/retry/circuit breaker)
│   │   ├── cache/redis.ts
│   │   ├── idempotency/store.ts
│   │   ├── observability/                # otel.ts, logger.ts, middleware.ts
│   │   ├── auth/                         # kong-headers.ts, realtime-token.ts
│   │   └── errors/domain-errors.ts
│   │
│   ├── trpc/
│   │   ├── context.ts                    # AppContext
│   │   ├── router.ts                     # appRouter
│   │   └── middleware.ts                 # auth guard (exige role `lojista`), rate limit
│   │
│   └── routes/
│       ├── healthz.ts
│       ├── readyz.ts
│       └── webhooks.ts
│
├── package.json
├── bunfig.toml
└── tsconfig.json
```

---

## 4. Decisões transversais

> Iguais ao `bff-mobile`. Diferenças marcadas com 🔷.

### 4.1 WebSocket — sempre direto, com token curto

🔷 Token escopa o tópico `establishment:{loja_id}` (em vez de `user:{id}`).
- Painel chama `issueRealtimeToken` → BFF emite token curto → painel conecta direto no `svc-notifications` (Phoenix Channels).

### 4.2 Idempotência — obrigatória em mutations

- Header `Idempotency-Key` em mutations críticas (`changeOrderStatus`, `updateMenuItem`, `publishMenu`).
- Cache de resposta no Redis por **24h**.

### 4.3 Rate limiting

| Camada | Onde | Quando |
|---|---|---|
| Global | **Kong** | Sempre |
| Por use case | **BFF (tRPC middleware)** | `publishMenu` (1/min/loja), `bulkUpdatePrices` (5/min/loja) |

### 4.4 Cache

- **Redis compartilhado**.
- 🔷 TTLs do painel: dashboards diários (60s), lista de pedidos do dia (10s — leitura frequente), config da loja (300s).
- Key namespace: `bff-web:{usecase}:{establishmentId|userId}`.

### 4.5 Backpressure / circuit breaker

- Timeout 3s, retry 2x em GETs idempotentes, circuit breaker (5 falhas/10s).

### 4.6 Versionamento

🔷 Painel web atualiza junto com deploy (cache buster) → versionamento menos crítico que mobile, mas mantemos compat reversa de 1 versão para reduzir blast radius de deploy.

### 4.7 Auth refresh

- Painel faz refresh direto no ZITADEL (PKCE).
- BFF não intermedia.

### 4.8 🔷 Paginação

- **Offset-based** (tabelas do painel — usuário pula páginas).
- Mobile usa cursor (lista infinita); web usa offset (paginador clássico).

### 4.9 🔷 Authorization adicional

- BFF valida em `tRPC middleware` que `X-User-Roles` contém `lojista`.
- BFF valida em cada use case que o `establishmentId` solicitado pertence ao usuário (chamada a `svc-establishments`). Defense in depth — o microsserviço também valida.

---

## 5. Observabilidade — checklist

- [ ] **Tracing**: trace ID propagado pro downstream via `traceparent`.
- [ ] **Métricas**: latência por procedure (p50/p95/p99), taxa de erro, circuit breaker, cache hit ratio.
- [ ] **Logs estruturados (JSON)** com `traceId`, `spanId`, `userId`, `establishmentId`, `procedure`, `durationMs`.
- [ ] **Logs sem PII**: telefone, email, CPF, dados financeiros — redaction automática.
- [ ] **Health checks**: `/healthz` e `/readyz` (testa Redis + 1 downstream crítico).
- [ ] **OTel resource attributes**: `service.name=bff-web`, `service.version`, `deployment.environment`.
- [ ] **Exporter**: OTLP → OTel Collector → Tempo + Prometheus + Loki.

---

## 6. Use cases iniciais sugeridos

| Use case | Tipo | Downstream |
|---|---|---|
| `listEstablishmentOrders` | query | orders, users (nome do comprador) |
| `getOrderDetails` | query | orders, catalog, users |
| `changeOrderStatus` (idempotente) | mutation | orders |
| `listMenuCategories` / `listMenuItems` | query | catalog |
| `createMenuItem` / `updateMenuItem` / `deleteMenuItem` (idempotentes) | mutation | catalog |
| `publishMenu` (idempotente) | mutation | catalog |
| `getEstablishmentConfig` / `updateEstablishmentConfig` | query/mutation | establishments |
| `toggleEstablishmentOpen` | mutation | establishments |
| `getEstablishmentDailySummary` | query | orders, payments |
| `listEstablishmentPayouts` | query | payments |
| `issueRealtimeToken` | mutation | (interno) |

---

## 7. Pontos abertos para discussão

- [ ] **Multi-loja**: lojista com várias lojas — como o painel troca contexto? Header `X-Establishment-Id` ou no input de cada use case?
- [ ] **Promoção comprador → lojista** (ADR-026): quando o usuário ganha role `lojista`, o painel é o mesmo ou onboarding específico?
- [ ] **Exportação** (CSV/PDF de relatórios): pesado — fazer no BFF (síncrono) ou delegar a worker assíncrono?
- [ ] Quando promover `platform/` para `packages/bff-platform` (regra dos 3 — quando duplicação com `bff-mobile` doer).
