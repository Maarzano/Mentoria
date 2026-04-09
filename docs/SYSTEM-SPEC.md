# FoodeApp — Especificação do Sistema

> **Versão:** 1.0 · **Data:** 2026-03-30  
> **Baseado em:** 29 ADRs, modules.md, CONFIGURATION.md, svc-users (código), infra (docker-compose, k8s, terraform), wireframes e diagramas C4.

---

## Sumário

1. [O Que É o FoodeApp](#1-o-que-é-o-foodeapp)
2. [Atores e Canais](#2-atores-e-canais)
3. [Jornadas do Lojista](#3-jornadas-do-lojista)
4. [Jornadas do Comprador](#4-jornadas-do-comprador)
5. [Regras de Negócio Centrais](#5-regras-de-negócio-centrais)
6. [Arquitetura Técnica](#6-arquitetura-técnica)
7. [Decomposição em Microserviços](#7-decomposição-em-microserviços)
8. [Modelo de Dados por Serviço](#8-modelo-de-dados-por-serviço)
9. [Fluxos Assíncronos e SAGA](#9-fluxos-assíncronos-e-saga)
10. [Infraestrutura e Ambientes](#10-infraestrutura-e-ambientes)
11. [Estado Atual da Implementação](#11-estado-atual-da-implementação)
12. [Estratégia de Slices e Próximos Passos](#12-estratégia-de-slices-e-próximos-passos)
13. [Referência de ADRs](#13-referência-de-adrs)

---

## 1. O Que É o FoodeApp

O FoodeApp é uma plataforma de **food delivery para food trucks** — um iFood focado em estabelecimentos móveis que mudam de localização diariamente. A proposta é conectar **lojistas** (donos de food trucks) a **compradores** (consumidores finais) com três diferenciais:

1. **Mobilidade do estabelecimento** — food trucks trocam de local, e o app mostra em **tempo real** onde estão.
2. **Eventos/feiras** — food trucks se agrupam em eventos; o comprador descobre vários de uma vez.
3. **Retirada presencial** — sem entrega por motoboy. O comprador vai até o food truck, usa um **código de retirada** e pega o pedido.

### Modelo de Negócio

```
Comprador paga via app (crédito, débito ou PIX)
    → Mercado Pago processa
    → Split automático: taxa FoodeApp + repasse ao lojista
    → Comprador vai ao local, informa código, retira pedido
```

---

## 2. Atores e Canais

| Ator | Descrição | Canal Primário | BFF | Funcionalidades-Chave |
|------|-----------|---------------|-----|----------------------|
| **Lojista** | Dono de food truck / estabelecimento fixo | **Web (React)** — navegador mobile, notebook ou desktop | `bff-web` | Configura loja, monta cardápios, gerencia pedidos, cria eventos |
| **Comprador** | Consumidor final que faz pedidos | **Mobile (React Native)** — smartphone | `bff-app` | Descobre food trucks, faz pedidos, acompanha em tempo real, avalia |

### Modelo de Usuários

- **1 único Identity Provider** — Keycloak com 1 Realm (`foodeapp`)
- **2 Realm Roles** — `comprador` e `lojista` (no mesmo realm, sem realms separados)
- **1 microserviço de perfil** — `svc-users` armazena perfil de aplicação de ambos os roles
- **Separação por BFF** — `bff-web` serve apenas funcionalidades do lojista; `bff-app` serve apenas funcionalidades do comprador
- **Autorização** — Kong valida JWT do Keycloak e injeta `X-User-Id` e `X-User-Roles` nos headers; cada endpoint/BFF verifica o role

---

## 3. Jornadas do Lojista

### 3.1 Cadastro e Login

```
Lojista acessa site → Keycloak (login com Google, Apple ou email/senha)
    → Callback com JWT contendo sub + role=lojista
    → Kong valida JWT, injeta X-User-Id
    → bff-web chama svc-users: POST /v1/profiles/me (upsert do perfil)
    → Perfil criado com displayName, avatar, phone, role=lojista
```

### 3.2 Configurar Estabelecimento

```
Lojista configura loja:
    → Nome do food truck
    → Foto/logo e banner
    → Descrição
    → Tipo (food truck ou loja fixa)
    → Horários de funcionamento (dia da semana + horário)
    → Configurar aceite de pedidos (manual ou automático)
```

- Inicialmente **1 loja por lojista** (expansão futura: múltiplas)
- O lojista pode **abrir/fechar a loja manualmente** (toggle no app)
- Ao abrir a loja: evento `establishment.opened` → notificação push para seguidores

### 3.3 Montar Cardápios

```
Lojista monta cardápios:
    → Cria cardápio (nome, descrição)
    → Cria categorias dentro do cardápio (ex: "Hambúrgueres", "Bebidas")
    → Cadastra itens com: nome, descrição, fotos, preço, quantidade disponível
    → Vincula itens a categorias
    → Ativa o cardápio (apenas 1 ativo por vez — ativar um desativa os demais)
```

**Regras de cardápio:**
- Pode ter **múltiplos cardápios**, mas **apenas 1 ativo por estabelecimento**
- Ao ativar um cardápio, o anterior é automaticamente desativado
- Cada item pode ter uma **quantidade disponível** (opcional)
- Quando a quantidade de um item chega a **zero**, ele é **automaticamente desabilitado**
- O lojista pode **desabilitar itens manualmente** (ex: "acabou" mesmo antes da quantidade zerar)

### 3.4 Gerenciar Pedidos

```
Ciclo de vida do pedido (visão do Lojista):

  Pedido chega (PENDENTE)
      ├── Aceitar (manual ou automático)
      │       → EM_PREPARO
      │           → FINALIZANDO
      │               → PRONTO (push pro comprador: "Seu pedido está pronto!")
      │                   → FINALIZADO (comprador informou código, lojista entregou)
      │
      ├── Rejeitar
      │       → REJEITADO (com motivo)
      │
      └── Cancelar (em qualquer status antes de PRONTO)
              → CANCELADO (SAGA: estorno de pagamento)
```

- **Aceite automático**: se configurado, o pedido é aceito automaticamente após N segundos
- **Aceite manual**: notificação push/WebSocket para o lojista; ele aceita ou rejeita
- **Status manual inicialmente**: o lojista altera o status conforme avança no preparo
- **Futuro**: estimativa automática de tempo baseada em histórico de pedidos anteriores

### 3.5 Validar Entrega

```
Comprador chega ao food truck
    → App do comprador gera código de retirada (ex: "A7K2")
    → Comprador fala o código em voz alta
    → Lojista digita o código no painel
    → Sistema valida: se correto → pedido FINALIZADO
```

### 3.6 Vincular a Eventos

```
Lojista está em um evento/feira:
    ├── O sistema sugere eventos próximos via geolocalização
    │       → Lojista confirma e vincula food truck ao evento
    │
    └── Evento não existe no sistema?
            → Lojista cria o evento (nome, área/localização, datas)
            → Sistema detecta duplicação (área + nome + datas similares)
            → Sugere "Você quis dizer este evento?" se houver match
            → Se realmente novo: evento criado, visível para outros lojistas
```

### 3.7 Dashboard

- **Itens mais pedidos** — ranking de itens por quantidade vendida
- **Histórico de pedidos** — com filtros por data, status
- **Receita** — total vendido no período

---

## 4. Jornadas do Comprador

### 4.1 Cadastro e Login

```
Comprador abre app → Keycloak (Google, Apple ou email/senha)
    → JWT com sub + role=comprador
    → bff-app chama svc-users: POST /v1/profiles/me
    → Perfil com displayName, foto (avatar)
```

O **displayName e foto** do comprador serão visíveis para o lojista quando chegar um pedido.

### 4.2 Descobrir Food Trucks

Duas formas de navegação:

```
1. POR EVENTO
   → App mostra lista de eventos ativos/próximos
   → Comprador entra em um evento
   → Vê os food trucks participantes
   → Entra em um food truck → vê cardápio

2. POR ESTABELECIMENTO
   → App mostra mapa com food trucks abertos por perto
   → Comprador filtra por raio/tipo/favoritos
   → Entra em um food truck → vê cardápio
```

- O comprador pode **seguir** um food truck → recebe **push notification** quando o food truck abrir
- Localização do food truck exibida em **tempo real via GPS** (WebSocket + Redis)
- Possibilidade de usar GPS do celular para traçar e **navegar até o food truck**

### 4.3 Fazer Pedido

```
Comprador monta carrinho:
    → Adiciona itens de 1 estabelecimento por vez (restrição)
    → Se trocar de estabelecimento, carrinho anterior é limpo (com confirmação)
    → Pode ajustar quantidade e adicionar observações por item (ex: "sem cebola")
    → Visualiza carrinho com subtotal

Checkout:
    → Escolhe método de pagamento: crédito, débito ou PIX
    → Frontend tokeniza dados do cartão (SDK Mercado Pago — PCI SAQ A)
    → Confirma pedido
    → SAGA: svc-orders → svc-payments → confirmação/cancelamento
```

### 4.4 Acompanhar Pedido

```
Tela de status do pedido (tempo real via WebSocket):

    PENDENTE → aguardando aceite do lojista
    ACEITO → pedido aceito, em breve será preparado
    EM_PREPARO → food truck está preparando
    FINALIZANDO → quase pronto
    PRONTO → "Vá buscar seu pedido!" (push notification)
        → Comprador vai ao local
        → App detecta proximidade (GPS) ou comprador marca "Estou no Local"
        → Lojista vê status "NO_LOCAL" no painel
        → Comprador diz código de retirada
        → Lojista valida código → FINALIZADO
```

### 4.5 Avaliação

```
Pedido FINALIZADO
    → App espera 30 minutos
    → Pop-up de avaliação do estabelecimento aparece na tela do comprador
    → Nota (estrelas) + comentário opcional
    → Avaliação vinculada ao estabelecimento (exibida na página da loja)
```

### 4.6 Histórico

- Lista de pedidos anteriores com status, data, valor, itens
- Filtros por período e estabelecimento

---

## 5. Regras de Negócio Centrais

### Cardápio

| Regra | Descrição |
|-------|-----------|
| **1 cardápio ativo** | Apenas 1 cardápio pode estar ativo por estabelecimento; ativar um desativa os demais automaticamente |
| **Auto-disable por quantidade** | Quando `AvailableQuantity` de um item chega a 0, `IsAvailable` → `false` automaticamente |
| **Disable manual** | Lojista pode desabilitar qualquer item a qualquer momento |
| **Snapshot no pedido** | Ao criar pedido, nome e preço do item são copiados (snapshot) para `order_items`; mudanças futuras no cardápio não afetam pedidos existentes |

### Pedidos

| Regra | Descrição |
|-------|-----------|
| **Carrinho mono-loja** | Carrinho aceita itens de apenas 1 estabelecimento por vez |
| **Aceite automático** | Se configurado no estabelecimento, pedido é aceito após N segundos sem ação |
| **Código de retirada** | App do comprador gera código alfanumérico; lojista valida para confirmar entrega |
| **Status "No Local"** | Detecção automática por GPS ou marcação manual pelo comprador ao chegar |
| **Pagamento antes do preparo** | Pagamento é processado antes do aceite; se falha, pedido é cancelado automaticamente (SAGA) |

### Eventos

| Regra | Descrição |
|-------|-----------|
| **Detecção de duplicação** | Ao criar evento, sistema verifica por nome similar + área geográfica similar + datas sobrepostas; sugere evento existente se encontrar match |
| **Vinculação por geolocalização** | Quando lojista está próximo de um evento ativo, sistema sugere vincular automaticamente |
| **Múltiplos food trucks por evento** | Vários estabelecimentos podem se vincular ao mesmo evento |

### Localização

| Regra | Descrição |
|-------|-----------|
| **GPS em tempo real** | Lojista envia posição periodicamente; Redis armazena com TTL de 24h |
| **PostGIS para queries** | Queries espaciais (raio, proximidade) usam PostgreSQL + PostGIS |
| **Notificação de abertura** | Seguidores recebem push quando food truck abre (evento `establishment.opened`) |

### Avaliações

| Regra | Descrição |
|-------|-----------|
| **Delay de 30 minutos** | Pop-up de avaliação aparece 30 minutos após pedido FINALIZADO |
| **Vinculada ao estabelecimento** | Avaliação é do estabelecimento, não do item |
| **1 avaliação por pedido** | Comprador avalia uma vez por pedido |

---

## 6. Arquitetura Técnica

### Stack (ADR-003)

| Camada | Tecnologia |
|--------|-----------|
| **Frontend Web** | React (TypeScript) |
| **Frontend Mobile** | React Native (TypeScript) |
| **Backend** | .NET 10 (C#) |
| **Database** | PostgreSQL 16 (1 database por microserviço) |
| **Cache/State** | Redis (carrinho, geolocalização, backplane WebSocket, idempotência) |
| **Mensageria** | RabbitMQ (via MassTransit) |
| **Identity Provider** | Keycloak (Ousers 2.0 + OIDC) |
| **API Gateway** | Kong (JWT validation, rate limiting, routing) |
| **Service Mesh** | Istio (mTLS, observabilidade interna, retry) |
| **Observabilidade** | OpenTelemetry + Prometheus + Loki + Tempo + Grafana |
| **Feature Flags** | Flagsmith (self-hosted) |
| **Pagamentos** | Mercado Pago (PIX + cartão, split marketplace) |
| **Push** | Firebase Cloud Messaging (Android/iOS) |
| **Email** | Resend |
| **WhatsApp** | Twilio |
| **File Storage** | Azure Blob Storage (imagens, assets) |
| **CDN** | Azure Front Door |
| **IaC** | Terraform |
| **CI/CD** | GitHub Actions |
| **Container** | Docker + Kubernetes |

### Padrões Arquiteturais

| Padrão | ADR | Onde |
|--------|-----|------|
| **CQRS** | ADR-004 | Cada microserviço: Commands (write) vs Queries (read) via MediatR |
| **Tabelas write + read** | ADR-005 | Write normalizado (EF Core), Read denormalizado (Dapper) no mesmo DB |
| **Outbox Pattern** | ADR-017 | Cada serviço que publica eventos: grava na tabela `outbox_messages` na mesma transação |
| **SAGA** | ADR-007 | Fluxo de pedido + pagamento via MassTransit state machine |
| **Hexagonal Architecture** | — | Domain → Application → Adapters (API, Data, Messaging, External) |
| **Result\<T\>** | — | Railway-oriented programming: sem exceptions para fluxo de negócio |
| **BFF per Channel** | ADR-010 | `bff-web` (lojista) e `bff-app` (comprador) |
| **Idempotência** | ADR-013 | `Idempotency-Key` no header → check Redis → audit PostgreSQL |
| **Multi-layer Cache** | ADR-015 | L1 (in-process) → L2 (Redis) → L3 (HTTP/CDN) |
| **Resiliência** | ADR-016 | Polly: retry (exponential backoff + jitter), circuit breaker, fallback |
| **Optimistic UI** | ADR-019 | Frontend assume sucesso; rollback se erro |

### Diagrama de Contexto

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                             INTERNET                                       │
│                                                                             │
│   ┌──────────────┐         ┌────────────────┐         ┌──────────────────┐ │
│   │  React Web   │         │  React Native  │         │  Mercado Pago    │ │
│   │  (Lojista)   │         │  (Comprador)   │         │  (Webhooks)      │ │
│   └──────┬───────┘         └───────┬────────┘         └────────┬─────────┘ │
│          │                         │                           │            │
└──────────┼─────────────────────────┼───────────────────────────┼────────────┘
           │                         │                           │
    ┌──────▼─────────────────────────▼───────────────────────────▼──────┐
    │                         KONG (API Gateway)                        │
    │         JWT validation · Rate limiting · Routing · SSL            │
    └──────┬─────────────────────────┬───────────────────────────┬──────┘
           │                         │                           │
    ┌──────▼──────┐           ┌──────▼──────┐            ┌──────▼──────┐
    │   bff-web   │           │  bff-app    │            │ svc-payments│
    │  (Lojista)  │           │ (Comprador) │            │  (webhook)  │
    └──────┬──────┘           └──────┬──────┘            └──────┬──────┘
           │                         │                          │
    ╔══════╧═════════════════════════╧══════════════════════════╧══════╗
    ║                    KUBERNETES + ISTIO (mTLS)                     ║
    ║                                                                  ║
    ║  ┌──────────┐  ┌────────────────┐  ┌───────────┐  ┌───────────┐ ║
    ║  │ svc-users │  │svc-establish.  │  │svc-catalog│  │svc-events │ ║
    ║  └─────┬────┘  └───────┬────────┘  └─────┬─────┘  └─────┬─────┘ ║
    ║        │               │                 │               │       ║
    ║  ┌─────┴────┐  ┌──────┴───────┐  ┌──────┴──────┐  ┌─────┴────┐ ║
    ║  │svc-orders│  │svc-location  │  │svc-notific. │  │svc-paymts│ ║
    ║  └─────┬────┘  └──────┬───────┘  └──────┬──────┘  └──────────┘ ║
    ║        │               │                 │                       ║
    ║   ┌────▼───────────────▼─────────────────▼────┐                 ║
    ║   │              RabbitMQ (MassTransit)        │                 ║
    ║   │      Outbox → Exchanges → DLQ             │                 ║
    ║   └───────────────────────────────────────────┘                 ║
    ║                                                                  ║
    ║   ┌────────────┐  ┌───────┐  ┌──────────┐  ┌──────────┐       ║
    ║   │ PostgreSQL │  │ Redis │  │ Keycloak │  │Flagsmith │       ║
    ║   │ (por svc)  │  │       │  │  (IdP)   │  │(feat.flg)│       ║
    ║   └────────────┘  └───────┘  └──────────┘  └──────────┘       ║
    ║                                                                  ║
    ║   ┌─────────────────────────────────────────────────────┐       ║
    ║   │ Observabilidade: OTel Collector → Prometheus/Loki/  │       ║
    ║   │                                   Tempo → Grafana   │       ║
    ║   └─────────────────────────────────────────────────────┘       ║
    ╚══════════════════════════════════════════════════════════════════╝
```

### Estrutura do Monorepo (ADR-021)

```
FoodeApp/
├── apps/
│   ├── bff-web/              # BFF para o painel do Lojista (React Web)
│   ├── bff-mobile/           # BFF para o app do Comprador (React Native)
│   ├── web/                  # Frontend React (Lojista)
│   └── mobile/               # Frontend React Native (Comprador)
├── services/
│   ├── svc-users/             # Perfis pós-Keycloak
│   ├── svc-establishments/   # Cadastro e gestão de lojas
│   ├── svc-catalog/          # Cardápios, categorias, itens
│   ├── svc-events/           # Eventos/feiras
│   ├── svc-location/         # Geolocalização GPS
│   ├── svc-orders/           # Pedidos + carrinho
│   ├── svc-notifications/    # Push/Email/WhatsApp + WebSocket (SignalR)
│   └── svc-payments/         # Mercado Pago
├── shared/
│   ├── contracts-proto/      # Contratos compartilhados
│   └── kernel-dotnet/        # Kernel compartilhado .NET (settings, extensions, observabilidade)
├── infra/
│   ├── local/                # Configs Docker Compose (Grafana, Prometheus, Loki, Tempo, OTel)
│   ├── k8s/                  # Kubernetes (base + overlays: homelab, staging, production)
│   ├── terraform/            # IaC (bootstrap + envs + modules)
│   └── scripts/              # Scripts auxiliares
├── docs/
│   ├── ADRs/                 # Architecture Decision Records (29 decisões)
│   ├── diagrams/             # Diagramas C4 + tabelas
│   ├── design/               # Wireframes (Excalidraw)
│   └── postman/              # Coleções Postman
├── docker-compose.yml        # Infraestrutura local
└── proj.ps1                  # CLI do projeto (~2500 linhas)
```

### Estrutura Padrão de Cada Microserviço (Hexagonal)

```
services/svc-{nome}/
├── Dockerfile                              # Multi-stage: SDK 10.0 → ASPNET 10.0
├── FoodeApp.Svc{Nome}.sln
└── src/
    ├── FoodeApp.Svc{Nome}.Domain/          # Entities, VOs, Events, Errors, Ports (interfaces)
    ├── FoodeApp.Svc{Nome}.Application/     # Commands, Queries, DTOs, Behaviors, Mappings
    ├── FoodeApp.Svc{Nome}.Adapters.API/    # Endpoints, Middleware, Contracts, Program.cs
    ├── FoodeApp.Svc{Nome}.Adapters.Data/   # DbContext, Repositories, Migrations
    ├── FoodeApp.Svc{Nome}.Adapters.External/ # Integrações externas (Keycloak, Mercado Pago, etc.)
    └── FoodeApp.Svc{Nome}.Adapters.Messaging/ # Publishers, Consumers, Outbox
```

---

## 7. Decomposição em Microserviços

### Tabela Resumo

| # | Serviço | Porta | Database | Schema | Depende de | Responsabilidade |
|---|---------|-------|----------|--------|-----------|-----------------|
| 1 | `svc-users` | 8080 | `foodeapp_users` | `users` | — | Perfis pós-Keycloak, favoritos |
| 2 | `svc-catalog` | 8081 | `foodeapp_catalog` | `catalog` | svc-users | Cardápios, categorias, itens |
| 3 | `svc-establishments` | 8082 | `foodeapp_establishments` | `establishments` | svc-users | Cadastro e gestão de lojas |
| 4 | `svc-events` | 8083 | `foodeapp_events` | `events` | svc-users | Eventos/feiras, vinculação |
| 5 | `svc-location` | 8084 | `foodeapp_locations` | `locations` | svc-users | GPS em tempo real |
| 6 | `svc-orders` | 8085 | `foodeapp_orders` | `orders` | svc-users | Carrinho (Redis), pedidos, SAGA |
| 7 | `svc-notifications` | 8086 | `foodeapp_notifications` | `notifications` | svc-users | Push/Email/WhatsApp + SignalR |
| 8 | `svc-payments` | 8087 | `foodeapp_payments` | `payments` | svc-users, svc-orders | Mercado Pago, estornos |
| — | `bff-web` | 8090 | — | — | users, catalog, establishments, orders | Agregador Lojista |
| — | `bff-app` | 8091 | — | — | users, catalog, establishments, orders, location, events | Agregador Comprador |
| — | `web` | 3001 | — | — | bff-web | Frontend React (Lojista) |
| — | `mobile` | 19000 | — | — | bff-mobile | Frontend React Native (Comprador) |

### Detalhamento

#### `svc-users` — Perfis & Favoritos

- Armazena perfil de aplicação pós-login no Keycloak (display name, avatar, phone, role)
- Gerencia favoritos do comprador (lojas favoritadas)
- Publica `UserRegisteredEvent` via Outbox
- **Não faz autenticação** — Keycloak cuida disso

#### `svc-establishments` — Estabelecimentos

- CRUD de food trucks (nome, slug, logo, banner, descrição, tipo)
- Horários de funcionamento por dia da semana
- Toggle abrir/fechar loja (manual)
- Configuração de aceite automático de pedidos
- Publica `EstablishmentOpened` / `EstablishmentClosed`

#### `svc-catalog` — Catálogo

- CRUD de cardápios (múltiplos, mas apenas 1 ativo)
- CRUD de categorias dentro de cardápio
- CRUD de itens (nome, descrição, foto, preço, quantidade)
- Auto-disable de item quando quantidade = 0
- Busca textual (PostgreSQL full-text)

#### `svc-events` — Eventos

- CRUD de eventos (nome, localização, datas, banner)
- Vinculação de estabelecimentos a eventos
- **Detecção de duplicação**: ao criar evento, busca por nome similar + área geográfica similar + datas sobrepostas e sugere existente
- Listagem de eventos ativos para descoberta

#### `svc-location` — Geolocalização

- Recebe posição GPS do food truck periodicamente
- **Redis** para posição atual (sub-second reads, TTL 24h)
- **PostgreSQL + PostGIS** para geo-queries (raio, proximidade)
- Publica `EstablishmentLocationUpdated` para WebSocket e push

#### `svc-orders` — Pedidos

- **Carrinho em Redis** (1 estabelecimento por vez, TTL 24h)
- Criação de pedido a partir do carrinho (snapshot de itens)
- Máquina de estados: PENDENTE → ACEITO → EM_PREPARO → FINALIZANDO → PRONTO → FINALIZADO
- Aceitação automática (timeout configurável)
- Código de retirada (gerado pelo app, validado pelo lojista)
- Detecção de "No Local" (GPS ou manual)
- Histórico de pedidos e dashboard de itens mais pedidos
- **Orquestração SAGA** via MassTransit (pedido ↔ pagamento)

#### `svc-payments` — Pagamentos

- Integração Mercado Pago (crédito, débito, PIX)
- Frontend tokeniza cartão (PCI SAQ A — sem dados de cartão no backend)
- Recebe webhooks do Mercado Pago (PIX assíncrono)
- Estorno como compensação SAGA
- Idempotência via `X-Idempotency-Key`
- Publica `PaymentConfirmed` / `PaymentFailed` / `PaymentRefunded`

#### `svc-notifications` — Notificações & Tempo Real

**Duas responsabilidades complementares:**

1. **Push/Email/WhatsApp** — Consome eventos do RabbitMQ, roteia para canal adequado:
   - Push: Firebase Cloud Messaging
   - WhatsApp: Twilio (critical, opt-in)
   - Email: Resend (transacional)
   - Hierarquia: Push → WhatsApp → Email

2. **WebSocket/SignalR** — Atualização em tempo real para app aberto:
   - Status do pedido (comprador)
   - Novos pedidos (lojista)
   - Localização do food truck (comprador)
   - Redis backplane para múltiplas instâncias

---

## 8. Modelo de Dados por Serviço

### Regras Absolutas (ADR-002)

- Cada serviço acessa **apenas seu próprio schema**
- **Zero JOINs** entre schemas
- **Zero foreign keys** entre schemas
- Troca de dados entre serviços = via RabbitMQ ou HTTP

### `users.*`

```sql
users.users (
    id             UUID PRIMARY KEY,
    keycloak_id    UUID NOT NULL UNIQUE,    -- claim 'sub' do JWT
    display_name   VARCHAR(100) NOT NULL,
    avatar_url     TEXT,
    phone          VARCHAR(20),
    role           VARCHAR(20) NOT NULL,    -- CHECK (role IN ('comprador','lojista'))
    created_at     TIMESTAMPTZ NOT NULL,
    updated_at     TIMESTAMPTZ NOT NULL
)

users.favorites (
    id                UUID PRIMARY KEY,
    user_id           UUID NOT NULL REFERENCES users.users(id),
    establishment_id  UUID NOT NULL,        -- ID externo (sem FK cross-schema)
    created_at        TIMESTAMPTZ NOT NULL,
    UNIQUE(user_id, establishment_id)
)

users.outbox_messages (...)   -- padrão Outbox (ADR-017)
```

### `establishments.*`

```sql
establishments.establishments (
    id                    UUID PRIMARY KEY,
    owner_user_id         UUID NOT NULL,
    name                  VARCHAR(150) NOT NULL,
    slug                  VARCHAR(150) NOT NULL UNIQUE,
    description           TEXT,
    logo_url              TEXT,
    banner_url            TEXT,
    is_open               BOOLEAN NOT NULL DEFAULT FALSE,
    auto_accept_orders    BOOLEAN NOT NULL DEFAULT FALSE,
    auto_accept_after_sec INT,
    created_at            TIMESTAMPTZ NOT NULL,
    updated_at            TIMESTAMPTZ NOT NULL
)

establishments.business_hours (
    id                UUID PRIMARY KEY,
    establishment_id  UUID NOT NULL REFERENCES establishments.establishments(id),
    day_of_week       SMALLINT NOT NULL,    -- 0=Dom .. 6=Sáb
    open_time         TIME NOT NULL,
    close_time        TIME NOT NULL
)

establishments.media (
    id                UUID PRIMARY KEY,
    establishment_id  UUID NOT NULL REFERENCES establishments.establishments(id),
    url               TEXT NOT NULL,
    media_type        VARCHAR(20) NOT NULL, -- 'logo' | 'banner' | 'gallery'
    display_order     SMALLINT NOT NULL DEFAULT 0
)

establishments.outbox_messages (...)
```

### `catalog.*`

```sql
catalog.menus (
    id                UUID PRIMARY KEY,
    establishment_id  UUID NOT NULL,
    name              VARCHAR(150) NOT NULL,
    is_active         BOOLEAN NOT NULL DEFAULT FALSE,
    created_at        TIMESTAMPTZ NOT NULL,
    updated_at        TIMESTAMPTZ NOT NULL
)

catalog.categories (
    id             UUID PRIMARY KEY,
    menu_id        UUID NOT NULL REFERENCES catalog.menus(id),
    name           VARCHAR(100) NOT NULL,
    description    TEXT,
    display_order  SMALLINT NOT NULL DEFAULT 0,
    is_active      BOOLEAN NOT NULL DEFAULT TRUE
)

catalog.products (
    id                  UUID PRIMARY KEY,
    category_id         UUID NOT NULL REFERENCES catalog.categories(id),
    name                VARCHAR(150) NOT NULL,
    description         TEXT,
    price               NUMERIC(10,2) NOT NULL,
    available_quantity  INT,                        -- NULL = ilimitado
    is_available        BOOLEAN NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ NOT NULL,
    updated_at          TIMESTAMPTZ NOT NULL
)

catalog.product_media (
    id          UUID PRIMARY KEY,
    product_id  UUID NOT NULL REFERENCES catalog.products(id),
    url         TEXT NOT NULL,
    media_type  VARCHAR(20) NOT NULL DEFAULT 'image',
    is_primary  BOOLEAN NOT NULL DEFAULT FALSE
)
```

### `events.*`

```sql
events.events (
    id                  UUID PRIMARY KEY,
    name                VARCHAR(200) NOT NULL,
    description         TEXT,
    address             TEXT,
    latitude            DECIMAL(10,7),
    longitude           DECIMAL(10,7),
    start_at            TIMESTAMPTZ NOT NULL,
    end_at              TIMESTAMPTZ NOT NULL,
    created_by_user_id  UUID NOT NULL,
    banner_url          TEXT,
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ NOT NULL
)

events.participations (
    id                UUID PRIMARY KEY,
    event_id          UUID NOT NULL REFERENCES events.events(id),
    establishment_id  UUID NOT NULL,
    joined_at         TIMESTAMPTZ NOT NULL,
    UNIQUE(event_id, establishment_id)
)
```

### `locations.*`

```sql
-- Requer: CREATE EXTENSION IF NOT EXISTS postgis;

locations.establishment_positions (
    id                UUID PRIMARY KEY,
    establishment_id  UUID NOT NULL UNIQUE,
    position          GEOGRAPHY(POINT, 4326) NOT NULL,
    updated_at        TIMESTAMPTZ NOT NULL
)

locations.position_history (
    id                UUID PRIMARY KEY,
    establishment_id  UUID NOT NULL,
    position          GEOGRAPHY(POINT, 4326) NOT NULL,
    recorded_at       TIMESTAMPTZ NOT NULL
)
```

**Redis:**
```
Chave:  location:estab:{establishment_id}
Valor:  { "lat": -23.5505, "lng": -46.6333, "updated_at": "..." }
TTL:    24h (sobrescrito a cada update)
```

### `orders.*`

```sql
orders.orders (
    id                UUID PRIMARY KEY,
    user_id           UUID NOT NULL,
    establishment_id  UUID NOT NULL,
    status            VARCHAR(30) NOT NULL,
    pickup_code       VARCHAR(10),             -- código de retirada
    total_amount      NUMERIC(10,2) NOT NULL,
    notes             TEXT,
    created_at        TIMESTAMPTZ NOT NULL,
    updated_at        TIMESTAMPTZ NOT NULL
)

orders.order_items (
    id                     UUID PRIMARY KEY,
    order_id               UUID NOT NULL REFERENCES orders.orders(id),
    product_id             UUID NOT NULL,
    product_name_snapshot  VARCHAR(150) NOT NULL,
    unit_price_snapshot    NUMERIC(10,2) NOT NULL,
    quantity               SMALLINT NOT NULL,
    notes                  TEXT
)

orders.order_status_history (
    id           UUID PRIMARY KEY,
    order_id     UUID NOT NULL REFERENCES orders.orders(id),
    from_status  VARCHAR(30),
    to_status    VARCHAR(30) NOT NULL,
    changed_by   UUID,
    changed_at   TIMESTAMPTZ NOT NULL,
    reason       TEXT
)

orders.saga_state (...)          -- MassTransit SAGA
orders.outbox_messages (...)     -- Outbox ADR-017
```

**Redis (carrinho):**
```
Chave:  cart:{user_id}
Valor:  { establishment_id, items: [...], subtotal }
TTL:    24h (renovado a cada alteração)
```

### `payments.*`

```sql
payments.payments (
    id                UUID PRIMARY KEY,
    order_id          UUID NOT NULL UNIQUE,
    amount            NUMERIC(10,2) NOT NULL,
    method            VARCHAR(20) NOT NULL,     -- 'cartao' | 'pix'
    status            VARCHAR(20) NOT NULL,     -- PENDENTE | CONFIRMADO | FALHOU | ESTORNADO
    mp_transaction_id TEXT,
    idempotency_key   UUID NOT NULL UNIQUE,
    created_at        TIMESTAMPTZ NOT NULL,
    updated_at        TIMESTAMPTZ NOT NULL
)

payments.payment_attempts (
    id            UUID PRIMARY KEY,
    payment_id    UUID NOT NULL REFERENCES payments.payments(id),
    attempt       SMALLINT NOT NULL,
    result        VARCHAR(20) NOT NULL,
    error_code    TEXT,
    attempted_at  TIMESTAMPTZ NOT NULL
)

payments.refunds (
    id              UUID PRIMARY KEY,
    payment_id      UUID NOT NULL REFERENCES payments.payments(id),
    amount          NUMERIC(10,2) NOT NULL,
    reason          TEXT NOT NULL,
    status          VARCHAR(20) NOT NULL,
    mp_refund_id    TEXT,
    created_at      TIMESTAMPTZ NOT NULL
)

payments.outbox_messages (...)
```

### `notifications.*`

```sql
notifications.device_tokens (
    id             UUID PRIMARY KEY,
    user_id        UUID NOT NULL,
    token          TEXT NOT NULL,
    platform       VARCHAR(10) NOT NULL,     -- 'android' | 'ios' | 'web'
    is_active      BOOLEAN NOT NULL DEFAULT TRUE,
    registered_at  TIMESTAMPTZ NOT NULL,
    UNIQUE(user_id, token)
)

notifications.preferences (
    id          UUID PRIMARY KEY,
    user_id     UUID NOT NULL,
    channel     VARCHAR(20) NOT NULL,        -- 'push' | 'whatsapp' | 'email'
    event_type  VARCHAR(50) NOT NULL,
    opted_in    BOOLEAN NOT NULL DEFAULT TRUE,
    UNIQUE(user_id, channel, event_type)
)

notifications.logs (
    id           UUID PRIMARY KEY,
    user_id      UUID NOT NULL,
    channel      VARCHAR(20) NOT NULL,
    event_type   VARCHAR(50) NOT NULL,
    status       VARCHAR(20) NOT NULL,
    error_msg    TEXT,
    sent_at      TIMESTAMPTZ NOT NULL
)
```

### Avaliações (proposta — novo schema no `svc-establishments` ou novo micro)

```sql
-- Opção A: dentro de svc-establishments (menos complexidade)
-- Opção B: svc-reviews separado (mais isolamento)

establishments.reviews (
    id                UUID PRIMARY KEY,
    order_id          UUID NOT NULL UNIQUE,       -- 1 avaliação por pedido
    establishment_id  UUID NOT NULL REFERENCES establishments.establishments(id),
    user_id           UUID NOT NULL,
    rating            SMALLINT NOT NULL,           -- 1 a 5
    comment           TEXT,
    created_at        TIMESTAMPTZ NOT NULL
)
```

---

## 9. Fluxos Assíncronos e SAGA

### Comunicação HTTP (Síncrona — via Istio mTLS)

| Origem | Destino | Quando |
|--------|---------|--------|
| `bff-web` | `svc-users`, `svc-establishments`, `svc-catalog`, `svc-orders`, `svc-events` | Agregar dados para o lojista |
| `bff-app` | `svc-users`, `svc-location`, `svc-establishments`, `svc-catalog`, `svc-orders`, `svc-events` | Agregar dados para o comprador |
| `svc-orders` | `svc-catalog` | Validar disponibilidade e obter snapshot de preço no checkout |

### Comunicação Assíncrona (RabbitMQ + Outbox)

| Evento | Produtor | Consumidor | Ação |
|--------|----------|------------|------|
| `users.user_registered` | svc-users | svc-notifications | Registrar preferências padrão |
| `establishment.opened` | svc-establishments | svc-notifications | Push para seguidores |
| `establishment.closed` | svc-establishments | svc-notifications | Atualizar hub |
| `establishment.location_updated` | svc-location | svc-notifications | WebSocket + push |
| `order.created` | svc-orders | svc-payments, svc-notifications | SAGA: processar pagamento |
| `order.status_changed` | svc-orders | svc-notifications | Push + WebSocket |
| `order.cancelled` | svc-orders | svc-payments | Compensação: estorno |
| `payment.confirmed` | svc-payments | svc-orders | SAGA: avançar estado do pedido |
| `payment.failed` | svc-payments | svc-orders, svc-notifications | SAGA: cancelar pedido |
| `payment.refunded` | svc-payments | svc-notifications | Notificar comprador |

### SAGA do Pedido (Orquestrada — ADR-007, ADR-008)

```
                          ┌─────────────────────┐
                          │   Checkout (BFF)     │
                          │   POST /checkout     │
                          └──────────┬──────────┘
                                     │
                          ┌──────────▼──────────┐
                          │   svc-orders         │
                          │   Cria pedido        │
                          │   Status: PENDENTE   │
                          │   Outbox: order.     │
                          │   created            │
                          └──────────┬──────────┘
                                     │
                          ┌──────────▼──────────┐
                          │   svc-payments       │
                          │   Cobra Mercado Pago │
                          └──────┬────────┬──────┘
                                 │        │
                     ┌───────────▼┐   ┌───▼──────────┐
                     │  SUCESSO    │   │  FALHA        │
                     │  Outbox:    │   │  Outbox:      │
                     │  payment.   │   │  payment.     │
                     │  confirmed  │   │  failed       │
                     └──────┬──────┘   └───┬──────────┘
                            │              │
                   ┌────────▼────────┐  ┌──▼────────────────┐
                   │  svc-orders     │  │  svc-orders        │
                   │  AGUARDANDO_    │  │  Status: CANCELADO │
                   │  ACEITE         │  │  (compensação)     │
                   └────────┬────────┘  └───────────────────┘
                            │
               ┌────────────▼────────────┐
               │  Lojista aceita/rejeita │
               └─────┬────────────┬──────┘
                     │            │
            ┌────────▼──────┐  ┌─▼──────────────┐
            │  ACEITO       │  │  REJEITADO      │
            │  → EM_PREPARO │  │  → Estorno SAGA │
            │  → FINALIZANDO│  └────────────────┘
            │  → PRONTO     │
            │  → FINALIZADO │
            └───────────────┘
```

---

## 10. Infraestrutura e Ambientes

### Ambiente Local (docker-compose)

| Componente | Container | Porta |
|------------|-----------|-------|
| PostgreSQL 16 | `foodeapp-postgres-users` | 5432 |
| OTel Collector | `foodeapp-otel-collector` | 4317 (gRPC), 4318 (HTTP) |
| Prometheus | `foodeapp-prometheus` | 9090 |
| Tempo | `foodeapp-tempo` | 3200 |
| Loki | `foodeapp-loki` | 3100 |
| Promtail | `foodeapp-promtail` | — |
| Grafana | `foodeapp-grafana` | 3000 |

Serviços .NET rodam **nativamente** (`dotnet run`) no dev local, não em container.

### Ambiente HomeLab (K8s overlay)

| Componente | Provisionado por | Notas |
|------------|-----------------|-------|
| PostgreSQL | Terraform (Helm: bitnami/postgresql) | 1 instância, databases separados |
| Redis | Terraform (Helm: bitnami/redis) | Cluster mode off, Sentinel |
| RabbitMQ | Terraform (Helm: bitnami/rabbitmq) | exchanges + DLQs pré-configurados |
| Kong | Kustomize (Helm values) | JWT plugin, rate limiting |
| Keycloak | Kustomize (Helm values) | Realm foodeapp |
| Istio | Manifests estáticos | mTLS, usersorizationPolicies |
| Flagsmith | Kustomize (Helm values) | Feature flags |
| Observabilidade | Terraform (Helm) | Full stack (Prometheus, Loki, Tempo, OTel, Grafana) |
| Microserviços | Kustomize | 8 services + 2 BFFs, ConfigMaps por serviço |

### Ambientes Planejados

| Ambiente | Infra | Deploy |
|----------|-------|--------|
| **Local** | docker-compose + dotnet run | Manual (proj.ps1) |
| **HomeLab** | K8s (homelab overlay) + Terraform | Manual ou CI/CD |
| **Staging** | K8s (staging overlay) + Terraform | CI/CD (GitHub Actions) |
| **Production** | K8s (production overlay) + Terraform | CI/CD com approval gate |

### Configuração (CONFIGURATION.md)

**Princípio**: Zero Hardcode, Fallback Claro.

```
.env (raiz) → $env:* → IOptions<T> → appsettings.json (só valores intrínsecos)
```

| Nível | Exemplo | Quem lê |
|-------|---------|---------|
| `.env` | `POSTGRES_HOST=localhost` | proj.ps1 (PowerShell), dotenv.net (.NET), docker-compose |
| K8s | `Database__Host=postgres.foodeapp.svc` | ConfigMap → env var do pod |
| appsettings.json | `Database.Database=foodeapp_users` | Valor intrínseco ao serviço |

---

## 11. Estado Atual da Implementação

### Pronto ✅

| Item | Detalhes |
|------|---------|
| **29 ADRs** | Todas as decisões arquiteturais documentadas e aceitas |
| **modules.md** | Decomposição completa em 8 micros + 2 BFFs com tabelas e comunicação |
| **CONFIGURATION.md** | Princípios de configuração e checklist de novo serviço |
| **docker-compose.yml** | PostgreSQL + stack de observabilidade completa |
| **proj.ps1** | CLI PowerShell (~2500 linhas): infra, build, run, migrations, status |
| **K8s manifests** | 10 services + namespaces + Kong + Keycloak + RabbitMQ + Istio + Flagsmith |
| **Terraform** | 3 ambientes (homelab, staging, production) + 8 módulos |
| **Shared Kernel** | DatabaseSettings, ObservabilitySettings, KeycloakSettings, RedisSettings, RabbitMqSettings + extensions |
| **Grafana Dashboard** | svc-users-overview.json com painel de métricas, logs e traces |
| **services.json** | Registro de todos os serviços com portas e dependências |
| **Wireframes** | Excalidraw com telas do sistema |
| **Diagramas C4** | Contexto e container level |

### Em Progresso 🔨

| Item | Status | Detalhes |
|------|--------|---------|
| **svc-users** | ~80% | Domain ✅, Application ✅, API ✅, Data ✅. Faltam: Keycloak real, MassTransit/Outbox, testes de integração |

### Não Iniciado ⬜

| Item |
|------|
| svc-establishments |
| svc-catalog |
| svc-events |
| svc-location |
| svc-orders |
| svc-notifications |
| svc-payments |
| bff-web |
| bff-app |
| web (frontend React) |
| mobile (frontend React Native) |
| Integração Keycloak |
| Integração RabbitMQ/MassTransit |
| Integração Redis |
| Integração Mercado Pago |

### `svc-users` — Detalhe do Estado Atual

```
Adapters.API/
├── Program.cs              ✅ Bootstrap completo: Serilog, OTel, Swagger, DB, MediatR, Health
├── Endpoints/
│   ├── ProfileEndpoints.cs ✅ POST /v1/profiles, GET /v1/profiles/{id}, GET /v1/profiles
│   └── HealthEndpoints.cs  ✅ GET /healthz, GET /ready
├── Contracts/
│   ├── RegisterUserRequest ✅ Body: KeycloakId, DisplayName, Role, AvatarUrl?, Phone?
│   └── ApiResponse<T>      ✅ Envelope padrão: { success, data, error }
├── Infrastructure/
│   ├── ResultExtensions     ✅ Result<T> → IResult (200/404/409/422/500)
│   └── GlobalExceptionHandler ✅ Exceção → 500 com ApiResponse
└── Middleware/
    └── KongHeadersMiddleware ✅ Extrai X-User-Id e X-User-Roles dos headers

Application/
├── Commands/RegisterUser/   ✅ Command + Validator + Handler (check duplicado, UoW, Outbox)
├── Queries/GetUserById/     ✅ Query + Handler
├── Queries/GetAllUsers/     ✅ Query + Handler
├── Behaviors/
│   ├── ValidationPipeline   ✅ FluentValidation antes do handler
│   ├── LoggingPipeline      ✅ Logs de request/response com duração
│   └── TracingPipeline      ✅ OpenTelemetry Activity spans
├── DTOs/UserProfileDto      ✅ Output DTO
└── Mappings/                ✅ User → UserProfileDto

Domain/
├── Entities/User            ✅ Aggregate com factory method Register(), domain events
├── ValueObjects/
│   ├── UserRole             ✅ Enum (Comprador/Lojista) com Parse/TryParse
│   └── PhoneNumber          ✅ Validação regex 10-15 dígitos
├── Events/UserRegisteredEvent ✅
├── Errors/UserErrors        ✅ AlreadyExists, InvalidRole, InvalidKeycloakId, etc.
├── Ports/IUnitOfWork        ✅ Begin/Commit/Rollback
├── Ports/IUserWriteRepository ✅ AddAsync
├── Ports/IUserEventPublisher ✅ PublishUserRegisteredAsync
└── Primitives/
    ├── Result<T>            ✅ Railway-oriented (Success/Failure, implicit operators)
    └── Error                ✅ Record com Code, Message, ErrorKind

Adapters.Data/
├── usersDbContext            ✅ EF Core com mappings (snake_case, PhoneNumber converter, UserRole converter)
├── UnitOfWork               ✅ Transaction wrapper sobre DbContext
├── Repositories/
│   ├── UserWriteRepository  ✅ EF Core (Add)
│   └── UserReadRepository   ✅ Dapper (SQL direto, DTO direto)
├── Migrations/M001          ✅ FluentMigrator: users schema + users + outbox_messages
└── Extensions/              ✅ DataServiceExtensions (DI registration)

Adapters.Messaging/
├── Publishers/UserEventPublisher ⬜ STUB: apenas loga, sem MassTransit
└── Extensions/              ⬜ STUB: registra publisher, sem RabbitMQ

Adapters.External/
└── (vazio)                  ⬜ STUB: Keycloak Admin Client planejado

Tests/
├── Domain.Tests/            ✅ 12 testes: User.Register(), PhoneNumber, UserRole
└── Application.Tests/       ✅ 5 testes: RegisterUserCommandHandler com NSubstitute
```

---

## 12. Estratégia de Slices e Próximos Passos

### Por que começar pelo Lojista?

O Lojista é o **lado da oferta**. Sem lojas e cardápios, o comprador não tem nada para usar:

```
Lojista cria conta → cria loja → monta cardápio → ativa
                                                     ↓
                             Comprador pode ver lojas e fazer pedidos
```

### Slice 1 — Lojista Configura Loja (Testar no HomeLab)

**Objetivo:** Pipeline completa testável: users → Establishment → Catalog

| Fase | Serviço | Escopo |
|------|---------|--------|
| 1 | svc-users | Completar: Keycloak integration (ou manter headers fake inicialmente) |
| 2 | svc-establishments | Novo: CRUD de loja + toggle abrir/fechar |
| 3 | svc-catalog | Novo: CRUD cardápio + categorias + itens + regra de 1 ativo |
| 4 | Deploy | Build imagens + kustomize homelab + verificar Grafana |

### Slices Seguintes

| Slice | Funcionalidade | Serviços |
|-------|---------------|----------|
| 2 | Comprador vê lojas e cardápio | svc-catalog (read) + bff-app |
| 3 | Comprador faz pedido | svc-orders + svc-payments + Redis + RabbitMQ |
| 4 | Status em tempo real | svc-notifications + SignalR + Redis backplane |
| 5 | Geolocalização | svc-location + PostGIS + Redis |
| 6 | Eventos e vinculação | svc-events + detecção de duplicação |
| 7 | Avaliações e dashboard | svc-establishments (reviews) |
| 8 | Produção | CI/CD + CDN + Terraform prod |

---

## 13. Referência de ADRs

| # | Decisão | Impacto |
|---|---------|---------|
| ADR-001 | Microserviços | Estrutura base de todo o sistema |
| ADR-002 | 1 PostgreSQL, 1 DB por micro | Isolamento de dados |
| ADR-003 | React + .NET 10 + PostgreSQL | Stack tecnológica |
| ADR-004 | CQRS via MediatR | Separação Command/Query em cada micro |
| ADR-005 | Write normalizado + Read denormalizado | EF Core (write) + Dapper (read) |
| ADR-006 | RabbitMQ via MassTransit | Mensageria assíncrona |
| ADR-007 | SAGA Pattern | Transações distribuídas (pedido + pagamento) |
| ADR-008 | Orquestração + Coreografia | SAGA orquestrada, notificações coreografadas |
| ADR-009 | Kong API Gateway | JWT validation, rate limiting, routing externo |
| ADR-010 | BFF por canal | bff-web (lojista), bff-app (comprador) |
| ADR-011 | Docker + Kubernetes | Containerização e orquestração |
| ADR-012 | Redis | Cache, carrinho, geo hot, backplane WebSocket, idempotência |
| ADR-013 | Idempotência | Idempotency-Key header + Redis + PostgreSQL audit |
| ADR-014 | WebSocket (SignalR) | Tempo real: status pedido, localização, notificações in-app |
| ADR-015 | Cache multicamadas | L1 (in-process) → L2 (Redis) → L3 (HTTP/CDN) |
| ADR-016 | Resiliência (Polly) | Retry, circuit breaker, fallback |
| ADR-017 | Outbox Pattern | Consistência DB ↔ RabbitMQ |
| ADR-018 | Observabilidade | OTel + Prometheus + Loki + Tempo + Grafana |
| ADR-019 | Optimistic UI | Frontend assume sucesso, rollback se erro |
| ADR-020 | Terraform | Infrastructure as Code |
| ADR-021 | Monorepo | Estrutura de pastas e CI/CD path filtering |
| ADR-022 | Istio (Service Mesh) | mTLS interno, observabilidade, retry |
| ADR-023 | CDN (Azure Front Door) | Assets estáticos |
| ADR-024 | GitHub Actions | CI/CD |
| ADR-025 | Mercado Pago | Pagamentos (PIX + cartão, marketplace split) |
| ADR-026 | Keycloak (Ousers 2.0/OIDC) | Autenticação e autorização |
| ADR-027 | FCM + Twilio + Resend | Push + WhatsApp + Email |
| ADR-028 | Azure Blob Storage | Imagens e arquivos |
| ADR-029 | Flagsmith | Feature flags |
