# ADR-003: Stack de Tecnologias (Poliglota — núcleo .NET 10)

**Status:** Aceito (revisado)
**Data:** 2026-03-10 · **Revisado:** 2026-04-29

---

## Contexto

A stack original deste projeto era homogênea: **.NET 10 + React + React Native + PostgreSQL**. Após análise do perfil técnico de cada microserviço, decidimos adotar uma **stack poliglota controlada**: o núcleo de domínio segue em .NET, mas serviços com perfil técnico específico ganham linguagens mais adequadas. Os frontends e BFFs são padronizados em TypeScript com Bun.

## Decisão

### Backend (microserviços)

| Serviço | Linguagem / Runtime | Motivo |
|---------|---------------------|--------|
| `svc-users` | **C# / .NET 10** | Domínio rico, CQRS/MediatR, já implementado como referência |
| `svc-establishments` | **C# / .NET 10** | CRUD com regras de negócio — produtividade DDD em .NET |
| `svc-catalog` | **C# / .NET 10** | Domínio relacional, read-heavy (resolvido com cache) |
| `svc-events` | **C# / .NET 10** | Domínio simples, alinhado ao núcleo |
| `svc-orders` | **C# / .NET 10** | Orquestrador de SAGA, MassTransit Saga state machine, regras complexas |
| `svc-payments` | **Rust** | Caminho crítico financeiro: latência previsível, segurança de tipos/memória, footprint pequeno |
| `svc-location` | **Go** | Concorrência massiva (milhares de pings/WS), binário pequeno, stdlib HTTP forte |
| `svc-notifications` | **Elixir / Phoenix** | Milhões de processos leves no BEAM para WebSocket; tolerância a falhas; Phoenix Channels para hub real-time (substitui SignalR no ADR-014) |

### Frontends e BFFs

| App | Stack |
|-----|-------|
| `bff-web` | **TypeScript + Bun** (framework: Hono recomendado) |
| `bff-mobile` | **TypeScript + Bun** (framework: Hono recomendado) |
| `web` (lojista) | **React + TypeScript + Bun** (Vite recomendado) |
| `mobile` (consumidor) | **Expo (React Native + TypeScript)** + EAS Build/Update — iOS + Android |

### Banco de dados e infra

| Camada | Tecnologia |
|--------|-----------|
| Banco relacional | **PostgreSQL** (1 instância, múltiplos databases — ADR-002 revisado) |
| Geo (frio) | PostGIS (em `svc-location`, opcional) |
| Estado quente | **Redis** (carrinho em `svc-orders`, GPS em `svc-location`, cache de catálogo) |
| Mensageria | **RabbitMQ** + **Outbox** (ADR-006, ADR-017) |

### Justificativas

**.NET 10 como núcleo (5 serviços):**
- Domínio principal (users, establishments, catalog, events, orders) é rico em regras → DDD/CQRS/MediatR é altamente produtivo.
- Time já tem expertise; serviço de referência (`svc-users`) já implementado.
- Excelente integração com OpenTelemetry, MassTransit (RabbitMQ + Outbox + SAGA), FluentMigrator.
- LTS de longo prazo.

**Rust em `svc-payments`:**
- Pagamento é caminho crítico do checkout: latência previsível, ausência de GC.
- Segurança de tipos e memória num serviço que mexe com dinheiro reduz classes inteiras de bugs.
- Stack: `axum` + `tokio` + `sqlx` + `lapin`.
- Custo aceito: equipe precisa estudar Rust; SAGA implementada manualmente sem MassTransit-equivalente.

**Go em `svc-location`:**
- Goroutines + canais para milhares de conexões WS/HTTP recebendo pings GPS.
- Binários estáticos pequenos escalam bem horizontalmente.
- Clientes maduros: `pgx`, `go-redis`, `otel-go`.
- Custo aceito: outra linguagem na operação; mitigado pelo escopo bem delimitado.

**Elixir/Phoenix em `svc-notifications`:**
- BEAM foi feito para concorrência massiva de processos leves — ideal para hub WebSocket fan-out.
- Phoenix Channels é mais simples e robusto que SignalR para o caso, e **substitui** a menção a SignalR no ADR-014.
- Supervisores e "let it crash" trazem resiliência a falhas de provedores externos (FCM, APNs, WhatsApp, SMTP).
- Broadway oferece pipeline declarativo de consumo de fila com backpressure.

**TypeScript + Bun nos BFFs:**
- Time de front domina TS — aproveita expertise.
- Bun acelera DX (install, build, test) e tem `fetch` nativo.
- BFF é I/O-bound — event loop é suficiente.
- Hono é otimizado para Bun e tem tipagem excelente.

**React + Vite (web) e Expo (mobile):**
- Web do lojista é autenticado → sem SSR/SEO; Vite vence em DX.
- Expo unifica iOS + Android com EAS Build/Update e ecossistema de módulos (push, location, secure-store).

## Consequências

### Positivas

- Cada serviço usa a ferramenta certa para o seu problema.
- Núcleo .NET coeso (mesmo template de DDD/CQRS/Outbox em 5 serviços).
- Frontends padronizados em TS reduzem fricção entre web e mobile.
- Phoenix Channels resolve elegantemente o real-time.
- Rust/Go/Elixir agregam valor de mercado e atraem talentos.

### Negativas / Trade-offs

- **Custo cognitivo**: 4 backends diferentes (C#, Rust, Go, Elixir). Mitigação: limitar cada um ao serviço certo; padronizar contratos via Protobuf (`shared/contracts-proto`); padronizar observabilidade via OpenTelemetry em todas as linguagens.
- **CI/CD mais complexo** (ADR-024): pipelines distintos por linguagem (toolchain, cache, lint, test).
- **Ecossistema desigual** para padrões transversais:
  - MassTransit/Outbox em .NET → Rust/Go/Elixir precisam de implementações próprias.
  - JWT/JWKS, retries, circuit breakers → garantir bibliotecas equivalentes.
- **Imagens Docker** distintas — base images padronizadas por linguagem.
- Operação Kubernetes uniforme via Istio (ADR-022) e OTel reduz parte do overhead.

### Neutras / Observações

- **Contratos entre serviços**: padronizar em Protobuf no monorepo (`shared/contracts-proto`) com geração para C#, Rust (`prost`), Go (`protoc-gen-go`), TS (`ts-proto`), Elixir (`protobuf-elixir`).
- **Auth poliglota é barato**: validação de JWT do ZITADEL é feita pelo Kong (ADR-009/ADR-026); serviços só leem `X-User-Id` e `X-User-Roles`.
- **Regra de bolso** para futuras decisões de linguagem: se o serviço é domínio rico/CRUD-ish → .NET. Se é gargalo técnico (latência, concorrência, real-time, segurança) → justificar e adotar a linguagem ideal.
- Versões fixadas em cada README de serviço/app (`*.csproj`, `Cargo.toml`, `go.mod`, `mix.exs`, `package.json`).

## Referências

- [ADR-001 — Microserviços](ADR-001-microservicos.md)
- [ADR-002 — Banco único com schemas](ADR-002-banco-unico-schemas.md)
- [ADR-006 — RabbitMQ](ADR-006-rabbitmq-fila.md)
- [ADR-009 — Kong](ADR-009-api-gateway-kong.md)
- [ADR-010 — BFF por frontend](ADR-010-bff-por-frontend.md)
- [ADR-014 — WebSocket (Phoenix Channels substituem SignalR)](ADR-014-websocket.md)
- [ADR-018 — Observabilidade](ADR-018-observabilidade.md)
- [ADR-026 — ZITADEL](ADR-026-autenticacao-oauth.md)
- READMEs por serviço/app em [services/](../../services/) e [apps/](../../apps/)
