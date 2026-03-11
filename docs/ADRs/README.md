# ADRs — FoodeApp

Architecture Decision Records documentam as decisões arquiteturais do FoodeApp.
Cada ADR é um documento vivo: pode ser revisado, atualizado ou depreciado conforme o produto evolui.

> **Status possíveis:** `Proposto` · `Aceito` · `Depreciado` · `Substituído por ADR-XXX`

---

## Índice

| # | Decisão | Status | Data |
|---|---------|--------|------|
| [ADR-000](ADR-000-template.md) | Template para novas ADRs | — | — |
| [ADR-001](ADR-001-microservicos.md) | Arquitetura de Microserviços | ✅ Aceito | 2026-03-10 |
| [ADR-002](ADR-002-banco-unico-schemas.md) | Banco de Dados Único com Separação por Schemas | ✅ Aceito | 2026-03-10 |
| [ADR-003](ADR-003-stack-tecnologias.md) | Stack de Tecnologias: React + .NET 10 + PostgreSQL | ✅ Aceito | 2026-03-10 |
| [ADR-004](ADR-004-cqrs-nivel-classe.md) | CQRS em Nível de Classe | ✅ Aceito | 2026-03-10 |
| [ADR-005](ADR-005-modelos-leitura-escrita.md) | Tabelas Normalizadas (Escrita) e Desnormalizadas (Leitura) sem DB Separado | ✅ Aceito | 2026-03-10 |
| [ADR-006](ADR-006-rabbitmq-fila.md) | RabbitMQ como Fila de Mensagens entre Microserviços | ✅ Aceito | 2026-03-10 |
| [ADR-007](ADR-007-saga-transacoes.md) | Padrão SAGA para Transações Distribuídas | ✅ Aceito | 2026-03-10 |
| [ADR-008](ADR-008-orquestracao-coreografia.md) | Orquestração vs Coreografia por Contexto e Complexidade | ✅ Aceito | 2026-03-10 |
| [ADR-009](ADR-009-api-gateway-kong.md) | API Gateway com Kong | ✅ Aceito | 2026-03-10 |
| [ADR-010](ADR-010-bff-por-frontend.md) | BFF Dedicado por Canal (Web + App) | ✅ Aceito | 2026-03-10 |
| [ADR-011](ADR-011-docker-kubernetes.md) | Docker + Kubernetes para Containerização e Orquestração | ✅ Aceito | 2026-03-10 |
| [ADR-012](ADR-012-redis.md) | Redis para Cache, Estado Compartilhado e Backplane | ✅ Aceito | 2026-03-10 |
| [ADR-013](ADR-013-idempotencia.md) | Idempotência via Chave do Cliente + Redis + TTL + PostgreSQL | ✅ Aceito | 2026-03-10 |
| [ADR-014](ADR-014-websocket.md) | WebSocket (SignalR) para Comunicação em Tempo Real | ✅ Aceito | 2026-03-10 |
| [ADR-015](ADR-015-cache-multicamadas.md) | Estratégia de Cache em Múltiplas Camadas com Invalidação | ✅ Aceito | 2026-03-10 |
| [ADR-016](ADR-016-resiliencia.md) | Retry + Circuit Breaker + Fallback com Exponential Backoff + Jitter | ✅ Aceito | 2026-03-10 |
| [ADR-017](ADR-017-outbox.md) | Padrão Outbox para Consistência entre Banco e Fila | ✅ Aceito | 2026-03-10 |
| [ADR-018](ADR-018-observabilidade.md) | Stack de Observabilidade: OTel + Prometheus + Loki + Tempo + Grafana | ✅ Aceito | 2026-03-10 |
| [ADR-019](ADR-019-ui-otimista.md) | UI Otimista (Optimistic UI) para Consistência Eventual | ✅ Aceito | 2026-03-10 |
| [ADR-020](ADR-020-terraform-iac.md) | Infrastructure as Code com Terraform | ✅ Aceito | 2026-03-10 |
| [ADR-021](ADR-021-monorepo.md) | Monorepo Único como Estratégia Inicial de Versionamento | ✅ Aceito | 2026-03-10 |
| [ADR-022](ADR-022-service-mesh.md) | Service Mesh (Istio) para Comunicação Interna entre Microserviços | ✅ Aceito | 2026-03-10 |
| [ADR-023](ADR-023-cdn-assets-estaticos.md) | CDN para Assets Estáticos (Imagens, JS, CSS) | ✅ Aceito | 2026-03-10 |
| [ADR-024](ADR-024-cicd-github-actions.md) | CI/CD com GitHub Actions (migração futura possível para Jenkins) | ✅ Aceito | 2026-03-10 |
| [ADR-025](ADR-025-gateway-pagamento.md) | Gateway de Pagamento — Mercado Pago | ✅ Aceito | 2026-03-10 |
| [ADR-026](ADR-026-autenticacao-oauth.md) | Autenticação e Autorização — Keycloak + OAuth 2.0 + OIDC | ✅ Aceito | 2026-03-10 |
| [ADR-027](ADR-027-push-notifications.md) | Push Notifications — FCM + Twilio WhatsApp + Resend | ✅ Aceito | 2026-03-10 |
| [ADR-028](ADR-028-file-storage.md) | File Storage — Cloudflare R2 para imagens e arquivos | ✅ Aceito | 2026-03-10 |
| [ADR-029](ADR-029-feature-flags.md) | Feature Flags — Flagsmith self-hosted | ✅ Aceito | 2026-03-10 |

---

## Mapa de Relacionamentos

```
ADR-001 (Microserviços)
  ├── ADR-002 (Banco único + schemas)
  │     └── ADR-005 (Tabelas leitura/escrita)
  ├── ADR-004 (CQRS em classe)
  │     └── ADR-005
  ├── ADR-006 (RabbitMQ)
  │     ├── ADR-007 (SAGA)
  │     │     └── ADR-008 (Orquestração/Coreografia)
  │     └── ADR-017 (Outbox)
  ├── ADR-009 (Kong API Gateway — apenas tráfego externo)
  │     └── ADR-010 (BFF por frontend)
  ├── ADR-022 (Service Mesh — Istio, comunicação interna síncrona)
  ├── ADR-011 (Docker + Kubernetes)
  │     └── ADR-020 (Terraform IaC)
  ├── ADR-012 (Redis)
  │     ├── ADR-013 (Idempotência)
  │     ├── ADR-014 (WebSocket + backplane)
  │     └── ADR-015 (Cache multicamadas)
  ├── ADR-016 (Resiliência)
  ├── ADR-018 (Observabilidade)
  └── ADR-019 (UI Otimista)

ADR-003 (Stack tecnológica) → base para todos os serviços .NET
  └── ADR-023 (CDN — serve bundles JS/CSS do React + assets)
ADR-021 (Monorepo) → organização de tudo acima no mesmo repositório
  └── ADR-024 (CI/CD — GitHub Actions, possível migração para Jenkins)
        ├── ADR-011 (build Docker + deploy no Kubernetes)
        ├── ADR-020 (terraform plan/apply no pipeline)
        └── ADR-023 (purge do CDN após deploy do frontend)

ADR-009 (Kong — APIs externas)
  └── ADR-026 (Keycloak — valida JWT na borda, não chama Keycloak a cada request)

ADR-023 (CDN Cloudflare — assets estáticos)
  ├── ADR-011 (Kubernetes Ingress = origin server do CDN)
  ├── ADR-015 (Cache multicamadas — CDN é a camada L0)
  └── ADR-020 (Terraform — provisionamento do Cloudflare)

ADR-025 (Gateway de Pagamento — Mercado Pago)
  ├── ADR-007 (SAGA — falha no pagamento dispara compensação)
  ├── ADR-013 (Idempotência — X-Idempotency-Key em toda chamada ao gateway)
  └── ADR-017 (Outbox — PagamentoConfirmado/Falhou via fila garantida)

ADR-026 (Autenticação — Keycloak + OAuth 2.0 + OIDC)
  ├── ADR-009 (Kong valida JWT via JWKS do Keycloak)
  ├── ADR-011 (Keycloak roda como pod no Kubernetes)
  └── ADR-020 (Terraform provisiona Keycloak)

ADR-027 (Push Notifications — FCM + Twilio + Resend)
  ├── ADR-006 (RabbitMQ — Serviço de Notificações consome eventos via fila)
  ├── ADR-008 (Coreografia — produtores publicam evento, Notificações reage)
  └── ADR-018 (Observabilidade — métricas de entrega por canal)

ADR-028 (File Storage — Cloudflare R2)
  ├── ADR-006 (RabbitMQ — worker de redimensionamento consome fila)
  ├── ADR-020 (Terraform — cloudflare_r2_bucket)
  └── ADR-023 (CDN — R2 serve arquivos via Cloudflare CDN)

ADR-029 (Feature Flags — Flagsmith)
  ├── ADR-009 (Kong traffic splitting = canary de versão; Flagsmith = canary de feature)
  ├── ADR-011 (Flagsmith roda como pod no Kubernetes)
  └── ADR-018 (Observabilidade — estado de flags como contexto nas métricas)
```

---

## Como criar uma nova ADR

1. Copie o [ADR-000-template.md](ADR-000-template.md).
2. Renomeie como `ADR-XXX-titulo-curto.md` (próximo número sequencial).
3. Preencha todas as seções.
4. Defina **Status** como `Proposto`.
5. Abra um PR para revisão.
6. Após aprovação, mude para `Aceito` e adicione ao índice acima.
