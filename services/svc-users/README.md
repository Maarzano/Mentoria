# svc-users

**Application Profile** dos usuários do FoodeApp. Vive **depois** do ZITADEL: o IdP cuida de credenciais/sessão; aqui ficam dados de produto (perfil, role, favoritos, promoção comprador→lojista).

> **Serviço de referência / template** para os demais serviços .NET do monorepo (`svc-establishments`, `svc-catalog`, `svc-events`, `svc-orders`).

---

## 1. Stack

| Item | Escolha |
|---|---|
| Linguagem | **C# / .NET 10 (LTS)** |
| Banco | PostgreSQL — schema `users` |
| Migrations | **FluentMigrator** |
| Mensageria | RabbitMQ via **MassTransit** (Outbox — em integração) |
| Validação | **FluentValidation** (Application) + invariantes no Domain (Value Objects) |
| Mapping | **Manual** — extension methods `ToDto()` / `ToEntity()` (sem AutoMapper/Mapster) |
| Erros | **`Result<T, Error>`** no Application/Domain. Exceptions só para falhas de infra |
| Observabilidade | OpenTelemetry → OTel Collector → Tempo / Loki / Prometheus |
| Health checks | **`/healthz` + `/readyz`** — `AddHealthChecks().AddNpgSql().AddRabbitMQ()` |
| IdP | ZITADEL (ADR-026) |

---

## 2. Arquitetura

DDD + CQRS nível de classe (ADR-004), repositórios W/R separados (ADR-005):

```
src/
├── FoodeApp.SvcUsers.Domain/             # Entidades, VOs, eventos, invariantes
├── FoodeApp.SvcUsers.Application/        # Commands/Queries, Behaviors, Validators
├── FoodeApp.SvcUsers.Adapters.API/       # Controllers, KongHeadersMiddleware, health
├── FoodeApp.SvcUsers.Adapters.Data/      # Repos W/R, FluentMigrator, EF Core read
├── FoodeApp.SvcUsers.Adapters.Messaging/ # Outbox publisher (MassTransit)
└── FoodeApp.SvcUsers.Adapters.External/  # Cliente ZITADEL Management API
```

### 2.1 Pipeline behaviors (MediatR)

Ordem de execução em cada Command/Query:

1. `TracingPipelineBehavior` — abre span OTel.
2. `LoggingPipelineBehavior` — log estruturado entrada/saída (PII redacted).
3. `ValidationBehavior` — FluentValidation, retorna `Result.Failure` em erro.
4. `IdempotencyBehavior` (mutations) — checa `Idempotency-Key` (ADR-013).
5. Handler (Domain + repos).

### 2.2 Auth

Confia no Kong. `KongHeadersMiddleware` lê `X-User-Id` (sub do ZITADEL) e `X-User-Roles` (project roles). **Serviço nunca revalida JWT.**

---

## 3. Decisões de design

### 3.1 Erros — `Result<T, Error>`

- Domain e Application retornam `Result<T, Error>` (impl manual ou `OneOf`).
- Exceptions reservadas para infra (DB down, RabbitMQ down, timeout) → handler global converte em 5xx.
- Erros de domínio são **dados**, não controle de fluxo: `User.NotFound`, `User.InvalidZitadelUserId`, `User.AlreadyPromoted`.

### 3.2 Validação em duas camadas

| Camada | Responsabilidade | Exemplo |
|---|---|---|
| **Domain (VO no construtor)** | Invariantes de negócio | `Cpf` valida dígitos verificadores; `Email` valida formato; `Phone` valida E.164 |
| **Application (FluentValidation)** | Shape do input | Campo obrigatório, tamanho máximo, regex de display name |

`ValidationBehavior` roda os validators do FluentValidation antes do handler. Se falhar, retorna `Result.Failure(ValidationError)` — sem throw.

### 3.3 Mapping manual

```csharp
public static class UserMappings
{
    public static UserDto ToDto(this User user) => new(
        user.Id,
        user.ZitadelUserId,
        user.DisplayName,
        user.Avatar?.Url,
        user.Role.ToString());

    public static User ToEntity(this RegisterUserCommand cmd) =>
        User.Create(cmd.ZitadelUserId, cmd.DisplayName, cmd.TaxId);
}
```

Sem AutoMapper/Mapster. Boilerplate explícito > magia que esconde bug.

### 3.4 Soft-delete + anonimização (LGPD)

Quando ZITADEL emite `user.removed` (webhook):

1. Webhook handler em `Adapters.API` recebe e dispara `AnonymizeUserCommand`.
2. Handler:
   - Marca `users.deleted_at = NOW()`.
   - Anonimiza colunas PII: `display_name = 'Usuário removido'`, `phone = NULL`, `tax_id = NULL`, `avatar_url = NULL`.
   - **Mantém** `id`, `zitadel_user_id`, `created_at`, `role` (integridade histórica de pedidos/avaliações).
   - Publica `UserDeletionRequested` (Outbox) → consumidores reagem (favoritos limpos, etc.).
3. Queries normais filtram `WHERE deleted_at IS NULL` via global filter no read repo.
4. Pedidos antigos referenciam `user_id` ainda válido — exibem como "Usuário removido".

> **Sem hard-delete.** LGPD pede minimização de PII, não destruição de toda a linha — pedidos têm finalidade fiscal/contábil que prevalece.

### 3.5 Health checks

```csharp
builder.Services.AddHealthChecks()
    .AddNpgSql(cs, name: "postgres", tags: ["ready"])
    .AddRabbitMQ(rabbitConn, name: "rabbitmq", tags: ["ready"]);

app.MapHealthChecks("/healthz", new() { Predicate = _ => false });          // liveness — só ping
app.MapHealthChecks("/readyz", new() { Predicate = r => r.Tags.Contains("ready") });
```

- **`/healthz`**: 200 sempre que o processo está vivo. Kong/K8s liveness probe → reinicia se 5xx.
- **`/readyz`**: 200 só se Postgres + RabbitMQ acessíveis. K8s readiness probe → tira do load balancing se 5xx.
- Kong gateway aponta para `/readyz` para não rotear request a pod que perdeu DB.

### 3.6 Observabilidade

- **Tracing**: `TracingPipelineBehavior` envolve cada Command/Query. `traceparent` propagado em chamadas externas (ZITADEL, RabbitMQ via headers).
- **Logs**: JSON estruturado, **PII redacted** (cpf, email, phone, display_name nunca em log).
- **Métricas técnicas**: HTTP (`http_server_duration_seconds`), DB (`db_client_operation_duration_seconds`), RabbitMQ.
- **Métricas de negócio** (custom):
  - `users_registered_total{source}`
  - `users_promoted_to_lojista_total`
  - `users_anonymized_total`
  - `users_outbox_lag_seconds`

---

## 4. Modelagem do domínio

### 4.1 `User` (aggregate root)

| Campo | Tipo | Notas |
|---|---|---|
| `Id` | Guid | PK interno |
| `ZitadelUserId` | string (varchar 32) | snowflake do ZITADEL, UNIQUE |
| `DisplayName` | string | nome de exibição |
| `Phone` | `Phone` (VO) | E.164, validado no VO; `phone_verified` lido do ZITADEL |
| `TaxId` | `TaxId` (VO) | CPF ou CNPJ, dígitos verificadores no VO |
| `Role` | enum | `Comprador`, `Lojista` (histórico em `user_role_grants`) |
| `Avatar` | `AvatarUrl` (VO) | aponta para CDN/blob (ADR-023/028) |
| `CreatedAt` / `UpdatedAt` / `DeletedAt` | timestamptz | |

### 4.2 Roles — fonte da verdade no ZITADEL

- Runtime: roles vêm do JWT (`X-User-Roles`).
- svc-users **não duplica** estado de role — armazena apenas **histórico** em `users.user_role_grants` (`granted_at`, `granted_by`, `role`) para auditoria e telemetria de promoção.

### 4.3 Favoritos

`users.user_favorites (user_id, establishment_id, created_at)` — vive aqui porque o lookup natural é "**meus** favoritos", não "quem favoritou esta loja".

### 4.4 Avatar / upload

- Upload via **SAS URL direto** para Azure Blob (ADR-028). Fluxo:
  1. App chama `bff-{web,mobile}.requestAvatarUpload()` → BFF chama svc-users → gera SAS write 5 min.
  2. App faz `PUT` direto no Blob.
  3. App chama `bff.confirmAvatarUpload(blobPath)` → svc-users valida e atualiza `avatar_url`.
- Banda não passa pelo backend.

### 4.5 Phone & verificação

- ZITADEL faz OTP/SMS (já tem feature). svc-users **lê** `phone_verified` via Management API ou claim.
- `Phone` em svc-users é unique? **Sim** — para suportar recovery e evitar duplicação. Conflito retorna `User.PhoneAlreadyInUse`.

---

## 5. Outbox (ADR-017) — em integração

- Tabela `users.outbox_messages` já criada (`M001_CreateUsersAndOutbox`).
- Handler escreve evento + estado do agregado **na mesma transação**.
- **Worker** (`OutboxWorker : BackgroundService`):
  - Polling 1s (`SELECT ... WHERE processed_at IS NULL ORDER BY created_at LIMIT 100 FOR UPDATE SKIP LOCKED`).
  - Publica via MassTransit, marca `processed_at = NOW()` em sucesso.
  - Falha → incrementa `attempts`, agenda retry com backoff (ADR-016). Após N tentativas → DLQ.
- **Idempotência consumidor** (ADR-013): `inbox_messages` no destino, dedup por `message_id`.
- Métrica: `users_outbox_lag_seconds` (gauge = `NOW() - MIN(created_at) WHERE processed_at IS NULL`).

> Decisão pendente: migrar para LISTEN/NOTIFY se latência de ~1s incomodar. MVP fica polling.

---

## 6. Contratos de eventos

Decisão **pendente** mas direção:

- **Protobuf** em `shared/contracts-proto/events/users/v1/`.
- Eventos: `UserRegistered`, `UserPromotedToLojista`, `UserDeletionRequested`, `UserProfileUpdated`.
- Versionamento: `events.users.v1.UserRegistered` — adição-only no v1, breaking change vira v2.
- Justificativa: stack poliglota (Rust/Go/Elixir consomem) precisa de schema multilinguagem.

---

## 7. Adapters.External — ZITADEL Management API

Cliente HTTP autenticado via **Client Credentials**. Casos de uso:

- **Promoção comprador→lojista**: atribuir Project Grant + role `Lojista` no ZITADEL.
- **Buscar `phone_verified` / `email_verified`** quando claim não vem.
- **Listar usuários** (uso interno backoffice — futuro).

Patrão: **Polly** com retry exponencial + circuit breaker (ADR-016). Métricas de chamadas externas (`zitadel_api_duration_seconds`, `zitadel_api_errors_total`).

---

## 8. Testes

- **Unit (atual)**: 10 Domain + 4 Application = 14 passando.
- **Integration (a fazer)**: pasta `tests/SvcUsers.IntegrationTests/` com **Testcontainers** (Postgres + RabbitMQ reais) cobrindo:
  - Migrations.
  - Repositórios W/R.
  - Outbox round-trip.
  - Webhook de soft-delete.
- **Contract tests**: validar Protobuf gerado contra consumidores (futuro).

---

## 9. Build & test

```powershell
dotnet build services/svc-users/FoodeApp.SvcUsers.sln
dotnet test  services/svc-users/FoodeApp.SvcUsers.sln
```

Estado atual: 0 warnings, 0 errors, 14/14 testes passando.

---

## 10. Como svc-users vira **template**

Os outros serviços .NET (`svc-establishments`, `svc-catalog`, `svc-events`, `svc-orders`) seguem este molde:

- Estrutura `Domain` / `Application` / `Adapters.{API,Data,Messaging,External}`.
- Behaviors (Tracing, Logging, Validation, Idempotency).
- `Result<T, Error>` em todo handler.
- FluentValidation no Application + invariantes em VOs.
- Mapping manual.
- Outbox + Inbox boilerplate.
- Health checks `/healthz` + `/readyz`.
- Logs JSON com PII redacted.
- Convenções: `{Verb}{Entity}Command/Query`, `{Entity}WriteRepository` / `{Entity}ReadRepository`.

> Documentar como `docs/templates/dotnet-service.md` quando o segundo serviço (provavelmente `svc-establishments`) replicar o padrão.

---

## 11. Pontos abertos

- [ ] **Outbox real**: ativar MassTransit + OutboxWorker, encerrar TODO ADR-017.
- [ ] **Contratos Protobuf**: confirmar `shared/contracts-proto/events/users/v1/` e gerar bindings (.NET, Rust, Go, Elixir).
- [ ] **Webhook ZITADEL** para `user.removed`: definir endpoint, autenticação (HMAC?), retry policy.
- [ ] **Adapters.External**: implementar cliente ZITADEL Management para promoção de role.
- [ ] **Testcontainers**: subir suite de integração no CI.
- [ ] **`docs/templates/dotnet-service.md`**: extrair convenções quando 2º serviço .NET nascer.
- [ ] **LISTEN/NOTIFY** vs polling no Outbox — decidir se latência incomodar.
- [ ] **`user_role_grants`** — modelar tabela e migration M002.
