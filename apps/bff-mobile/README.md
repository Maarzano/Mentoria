# bff-mobile (BFF do Comprador)

> Também referenciado como **bff-comprador** — pasta mantida como `bff-mobile` por simetria com `apps/mobile`.

**BFF (Backend for Frontend)** dedicado ao app do **comprador** (`apps/mobile`, Expo). Não tem regra de negócio — é **agregador de I/O**: junta chamadas a microsserviços, filtra, transforma payloads para mobile e cuida de políticas transversais (cache curto, idempotência, rate limit por use case, observabilidade).

---

## 1. Stack

| Item | Escolha |
|---|---|
| Linguagem | **TypeScript** |
| Runtime | **Bun** |
| Framework HTTP | **Hono** |
| Tipos cliente↔BFF | **tRPC** (com `httpBatchLink` no app) |
| Validação | **Zod** |
| Cache | **Redis** (compartilhado em K8s — múltiplas réplicas) |
| Idempotência | **Redis** (chave `Idempotency-Key`) |
| Observabilidade | **OpenTelemetry** (traces + métricas + logs estruturados) |
| Testes | **`bun test`** |
| Auth | Confia no Kong — lê `X-User-Id` / `X-User-Roles` (ZITADEL via Kong, ADR-026) |

### Por que TS + Bun

- BFF é I/O-bound (agrega downstream HTTP) — event loop é suficiente.
- TS no BFF + TS no Expo = **tipos end-to-end via tRPC, sem codegen**.
- Bun acelera DX (install, build, `bun test`) e tem `fetch` nativo.

### Por que tRPC

- BFF é privado por definição (ADR-010) — não precisa de contrato REST público.
- Mudou um campo no use case → o app reclama em compile time.
- Trade-off aceito: acopla cliente e servidor (correto para BFF, errado para API pública).

---

## 2. Princípios

1. **Sem regra de negócio.** Se aparecer regra, é sintoma de microsserviço incompleto — refator no serviço, não no BFF.
2. **Endpoints por use case, NÃO por tela.** Use case = ação/intenção do usuário.
   | ✅ Bom (use case) | ❌ Ruim (tela disfarçada) |
   |---|---|
   | `placeOrder` | `checkoutScreenData` |
   | `listNearbyEstablishments` | `homeScreen` |
   | `trackActiveOrder` | `orderTrackingScreen` |
   | `addFavoriteEstablishment` | `favoritesScreen` |
3. **Fan-out paralelo com graceful degradation** (`Promise.allSettled`). Se cupons cair, a tela ainda renderiza sem cupons.
4. **Stateless.** Sem DB local. Estado vive em Redis (cache, idempotência) ou nos microsserviços.
5. **Composição em vez de herança.** Sem `BaseHandler`, sem container DI — context object passado adiante.

---

## 3. Arquitetura — Vertical Slice + Downstream Adapters

> **Por que não Clean Architecture?** Clean isola regra de negócio de infra. BFF não tem regra. Aplicar Clean aqui gera 4 camadas pra fazer `fetch + transform + return` — sem proteger nada.
>
> **Por que não plana ingênua?** Cliente HTTP duplicado, sem ponto único pra OTel/retry, difícil testar.
>
> **Vertical Slice**: cada use case é uma fatia autocontida. Coisas genuinamente compartilhadas viram `platform/`.

```
bff-mobile/
├── src/
│   ├── index.ts                          # bootstrap Hono + tRPC
│   │
│   ├── usecases/                         # 1 pasta = 1 use case (vertical slice)
│   │   ├── place-order/
│   │   │   ├── input.ts                  # zod schema do input
│   │   │   ├── output.ts                 # zod schema do output
│   │   │   ├── handler.ts                # orquestração (função pura, testável)
│   │   │   ├── procedure.ts              # binding tRPC (3 linhas)
│   │   │   └── handler.test.ts
│   │   ├── list-nearby-establishments/
│   │   ├── track-active-order/
│   │   ├── issue-realtime-token/         # emite token curto p/ svc-notifications
│   │   └── ...
│   │
│   ├── platform/                         # compartilhado de verdade
│   │   ├── clients/                      # 1 arquivo por microsserviço downstream
│   │   │   ├── orders.client.ts
│   │   │   ├── catalog.client.ts
│   │   │   ├── establishments.client.ts
│   │   │   ├── location.client.ts
│   │   │   └── notifications.client.ts
│   │   │
│   │   ├── http/
│   │   │   ├── fetch-with-policies.ts    # timeout + retry + circuit breaker
│   │   │   └── propagate-context.ts      # traceparent, X-User-Id, X-App-Version
│   │   │
│   │   ├── cache/redis.ts
│   │   ├── idempotency/store.ts          # Idempotency-Key → resposta cacheada
│   │   │
│   │   ├── observability/
│   │   │   ├── otel.ts                   # SDK + resource attributes
│   │   │   ├── logger.ts                 # JSON estruturado + redaction PII
│   │   │   └── middleware.ts             # Hono middleware (trace por request)
│   │   │
│   │   ├── auth/
│   │   │   ├── kong-headers.ts
│   │   │   └── realtime-token.ts         # JWT curto p/ Phoenix Channels
│   │   │
│   │   └── errors/domain-errors.ts
│   │
│   ├── trpc/
│   │   ├── context.ts                    # AppContext (clients, cache, logger, user)
│   │   ├── router.ts                     # appRouter (importa todos os procedure.ts)
│   │   └── middleware.ts                 # auth guard, rate limit por user/use case
│   │
│   └── routes/                           # REST público quando inevitável
│       ├── healthz.ts                    # liveness
│       ├── readyz.ts                     # readiness (Redis + 1 downstream crítico)
│       └── webhooks.ts
│
├── package.json
├── bunfig.toml
└── tsconfig.json
```

### Fluxo de uma fatia

```ts
// usecases/place-order/handler.ts
export async function placeOrderHandler(
  input: PlaceOrderInput,
  ctx: AppContext,
): Promise<PlaceOrderOutput> {
  const cached = await ctx.idempotency.tryGet(input.idempotencyKey)
  if (cached) return cached

  const order = await ctx.clients.orders.createOrder({
    userId: ctx.userId,
    items: input.items,
    addressId: input.addressId,
  })

  const out = mapToOutput(order)
  await ctx.idempotency.save(input.idempotencyKey, out)
  return out
}
```

```ts
// usecases/place-order/procedure.ts
export const placeOrder = authedProcedure
  .input(placeOrderInputSchema)
  .output(placeOrderOutputSchema)
  .mutation(({ input, ctx }) => placeOrderHandler(input, ctx))
```

**Características:**
- `handler` é função pura — recebe contexto, devolve resposta. Testável sem Hono/tRPC.
- `procedure` é só binding — 3 linhas.
- Adicionar use case = criar uma pasta. Não toca em mais nada.

---

## 4. Decisões transversais

### 4.1 WebSocket — sempre direto, com token curto

App **não conecta WS pelo BFF**. Fluxo:

1. App chama `issueRealtimeToken` (use case do BFF).
2. BFF emite **token curto** (5–15 min, derivado do JWT do ZITADEL) já com escopo do tópico (`user:{id}`).
3. App conecta direto no `svc-notifications` (Phoenix Channels) com esse token.

> Aproveita o BEAM (milhões de WS leves) e mantém o BFF stateless. Caminho híbrido (proxiar 1ª vez) foi descartado: dobra complexidade sem ganho real.

### 4.2 Idempotência — obrigatória em mutations

- App envia header `Idempotency-Key` (UUID v4) em toda mutation crítica (`placeOrder`, `cancelOrder`, etc).
- BFF cacheia a resposta no Redis por **24h** sob essa chave.
- Reenvio com mesma key → mesma resposta, sem reexecutar.
- Conecta com ADR-013 (idempotência fim a fim).

### 4.3 Rate limiting

| Camada | Onde | Quando |
|---|---|---|
| Global por IP/usuário | **Kong** (ADR-009) | Sempre — primeira linha |
| Por use case + user | **BFF (tRPC middleware)** | Casos específicos: `placeOrder` (3/min/user), `issueRealtimeToken` (10/min/user) |

> Defense in depth: Kong para o ataque genérico; BFF para abusos específicos onde o Kong não consegue diferenciar.

### 4.4 Cache

- **Redis compartilhado** entre réplicas (não in-memory — múltiplos pods).
- TTLs curtos: catálogo (60s), estabelecimentos próximos (30s), feed home (15s).
- Key namespace: `bff-mobile:{usecase}:{userId|hash(input)}`.
- Invalidação por TTL apenas — sem invalidação proativa no MVP.

### 4.5 Backpressure / circuit breaker

Em `platform/http/fetch-with-policies.ts`:
- **Timeout**: 3s por chamada downstream (default).
- **Retry**: só GETs idempotentes, máx 2 tentativas, exponential backoff.
- **Circuit breaker**: abre após 5 falhas em 10s, half-open após 30s.
- Em circuito aberto: handler decide → erro 503 ou degrade silencioso.

### 4.6 Versionamento

- App envia header `X-App-Version`.
- BFF mantém compat reversa de **2 versões anteriores** mínimo.
- Mudança quebra-tudo → nova procedure (`placeOrderV2`) coexiste com a antiga.

### 4.7 Auth refresh

- Refresh do JWT é responsabilidade do **app** (PKCE direto no ZITADEL).
- BFF **não** intermedia refresh — mantém o BFF stateless e simples.

---

## 5. Observabilidade — checklist

- [ ] **Tracing**: trace ID propagado pro downstream via `traceparent` header.
- [ ] **Métricas**: latência por procedure (p50/p95/p99), taxa de erro, circuit breaker (estado/transições), cache hit ratio.
- [ ] **Logs estruturados (JSON)** com `traceId`, `spanId`, `userId`, `procedure`, `durationMs`, `appVersion`.
- [ ] **Logs sem PII**: telefone, email, CPF, endereço — redaction automática no logger.
- [ ] **Health checks**: `/healthz` (liveness, sem dependências) e `/readyz` (readiness — testa Redis + 1 downstream crítico).
- [ ] **OTel resource attributes**: `service.name=bff-mobile`, `service.version`, `deployment.environment`.
- [ ] **Exporter**: OTLP → OTel Collector → Tempo (traces) + Prometheus (métricas) + Loki (logs).

---

## 6. Use cases iniciais sugeridos

| Use case | Tipo | Downstream |
|---|---|---|
| `listNearbyEstablishments` | query | location, establishments, catalog (preview) |
| `getEstablishmentMenu` | query | establishments, catalog |
| `addToCart` / `removeFromCart` / `getCart` | mutation/query | orders (Redis carrinho) |
| `placeOrder` | mutation (idempotente) | orders, payments |
| `trackActiveOrder` | query | orders, location |
| `issueRealtimeToken` | mutation | (interno) |
| `listFavorites` / `toggleFavorite` | query/mutation | users |
| `getMyProfile` / `updateMyProfile` | query/mutation | users |
| `listMyOrders` (histórico) | query | orders |

---

## 7. Pontos abertos para discussão

- [ ] Estratégia de **paginação** (cursor para listas infinitas mobile — confirmar formato).
- [ ] Push tokens (FCM/APNs): app registra direto em `svc-notifications` ou via BFF? — recomendação: via BFF (centraliza auth).
- [ ] Quando promover `platform/` para pacote compartilhado em `packages/bff-platform` (regra: depois que `bff-web` existir e duplicação ficar dolorosa).
- [ ] Teste de contrato com microsserviços downstream (Pact?) — ou OpenAPI codegen é suficiente?
