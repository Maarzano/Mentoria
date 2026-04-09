# Decomposição em Módulos — FoodeApp

**Versão:** 1.1  
**Data:** 2026-03-11  
**Baseado em:** ADR-001, ADR-002, ADR-004, ADR-006, ADR-007, ADR-009, ADR-010, ADR-012, ADR-014, ADR-017, ADR-022, ADR-025, ADR-026, ADR-027

---

## Visão Geral

O FoodeApp é decomposto em **8 microserviços** de domínio + **2 BFFs** de apresentação, organizados por bounded context (DDD). A maioria dos serviços possui seu próprio schema PostgreSQL (ADR-002). Dois serviços usam apenas Redis (ADR-012) para estado efêmero: o carrinho vive dentro do `svc-orders` e o hub em tempo real vive dentro do `svc-notifications`.

```
                          ┌─────────┐
                          │  Kong   │  ← Tráfego externo (ADR-009)
                          └────┬────┘
               ┌───────────────┴───────────────┐
          ┌────▼─────┐                   ┌─────▼────┐
          │ bff-web  │                   │ bff-app  │
          │(Lojista) │                   │(Usuário) │
          └────┬─────┘                   └─────┬────┘
               │          Istio mTLS           │
         ──────┴───────────────────────────────┴──────
        │                  Microserviços               │
        │   users    establishments  events   catalog   │
        │   orders  payments       location  notif.    │
         ──────────────────────────────────────────────
               │
        ┌──────┴────────────────┐
        │  RabbitMQ + Outbox    │  ← Comunicação assíncrona (ADR-006, ADR-017)
        └───────────────────────┘
```

---

## Tabela de Módulos

| # | Serviço | Schema DB | Atores | Responsabilidade Principal |
|---|---------|-----------|--------|---------------------------|
| 1 | `svc-users` | `users` | Lojista, Usuário | users pós-Keycloak: perfis, favoritos |
| 2 | `svc-establishments` | `establishments` | Lojista | Cadastro, config e estado das lojas |
| 3 | `svc-catalog` | `catalog` | Lojista, Usuário | Cardápios, categorias e itens |
| 4 | `svc-events` | `events` | Lojista, Usuário | Eventos/feiras e vínculo com estabelecimentos |
| 5 | `svc-location` | `locations` | Lojista, Usuário | GPS em tempo real (Redis hot) e geo-queries |
| 6 | `svc-orders` | `orders` | Lojista, Usuário | Carrinho (Redis), ciclo de pedidos e SAGA |
| 7 | `svc-notifications` | `notifications` | Sistema (eventos) | Push/Email/WhatsApp + hub SignalR/WebSocket |
| 8 | `svc-payments` | `payments` | Sistema (SAGA) | Pagamentos via Mercado Pago e estornos |
| `bff-web` | — | Lojista | Agregador para o painel do lojista (React Web) |
| `bff-app` | — | Usuário | Agregador para o app do consumidor (React Native) |

---

## Detalhamento por Módulo

---

### 1. `svc-users` — users & Perfis

**Schema:** `users`

**Contexto:** O Keycloak (ADR-026) é o responsável pela autenticação — emissão de JWT, login social (Google/Apple), gerenciamento de senhas e sessões. O `svc-users` é responsável pelos dados de *aplicação* gerados após o cadastro no Keycloak: perfil, preferências e favoritos. Não executa nenhuma operação de autenticação diretamente.

**Quem usa:**
- Lojista: cria perfil após conta no Keycloak
- Usuário consumidor: cria perfil, gerencia favoritos

**Responsabilidades:**
- Criar e atualizar perfil de aplicação (nome de exibição, avatar, telefone)
- Registrar a role do usuário no sistema (`comprador` | `lojista`)
- Gerenciar lista de lojas favoritadas pelo consumidor

**Tabelas:**

```sql
-- Perfil de aplicação vinculado ao usuário do Keycloak
users.users (
  id             UUID PRIMARY KEY,
  keycloak_id    UUID NOT NULL UNIQUE,   -- claim 'sub' do JWT
  display_name   VARCHAR(100) NOT NULL,
  avatar_url     TEXT,
  phone          VARCHAR(20),
  role           VARCHAR(20) NOT NULL,   -- 'comprador' | 'lojista'
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
)

-- Lojas favoritadas pelo consumidor
users.favorites (
  id                UUID PRIMARY KEY,
  user_id           UUID NOT NULL REFERENCES users.users(id),
  establishment_id  UUID NOT NULL,       -- ID em svc-establishments (sem FK cross-schema)
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, establishment_id)
)
```

---

### 2. `svc-establishments` — Estabelecimentos

**Schema:** `establishments`

**Contexto:** Gerencia tudo que define um estabelecimento (foodtruck). É o domínio central do lojista.

**Quem usa:**
- Lojista: configurar sua loja

**Responsabilidades:**
- CRUD do estabelecimento (nome, slug, logo, banner, descrição)
- Gerenciar horários de funcionamento
- Abrir/fechar loja manualmente
- Configurar aceite automático ou manual de pedidos
- Linkar o estabelecimento a um evento (publica evento via RabbitMQ para o `svc-events`)

**Tabelas:**

```sql
establishments.establishments (
  id                    UUID PRIMARY KEY,
  owner_user_id         UUID NOT NULL,       -- ID em users.users
  name                  VARCHAR(150) NOT NULL,
  slug                  VARCHAR(150) NOT NULL UNIQUE,
  description           TEXT,
  logo_url              TEXT,
  banner_url            TEXT,
  is_open               BOOLEAN NOT NULL DEFAULT FALSE,
  auto_accept_orders    BOOLEAN NOT NULL DEFAULT FALSE,
  auto_accept_after_sec INT,                 -- aceite automático após N segundos (NULL = sem timeout)
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
)

establishments.business_hours (
  id                UUID PRIMARY KEY,
  establishment_id  UUID NOT NULL REFERENCES establishments.establishments(id),
  day_of_week       SMALLINT NOT NULL,  -- 0=Dom .. 6=Sáb
  open_time         TIME NOT NULL,
  close_time        TIME NOT NULL
)

establishments.media (
  id                UUID PRIMARY KEY,
  establishment_id  UUID NOT NULL REFERENCES establishments.establishments(id),
  url               TEXT NOT NULL,
  media_type        VARCHAR(20) NOT NULL,  -- 'logo' | 'banner' | 'gallery'
  display_order     SMALLINT NOT NULL DEFAULT 0
)

-- Outbox para eventos publicados via RabbitMQ (ADR-017)
establishments.outbox_messages (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type          VARCHAR(255) NOT NULL,
  payload       JSONB NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  published_at  TIMESTAMPTZ NULL,
  retry_count   INT NOT NULL DEFAULT 0
)
```

---

### 3. `svc-catalog` — Catálogo

**Schema:** `catalog`

**Contexto:** Gerencia o cardápio do estabelecimento. O lojista pode ter múltiplos cardápios, mas apenas um pode estar ativo por vez — este é o que o usuário visualiza. Dentro do cardápio, itens são organizados em categorias.

**Quem usa:**
- Lojista: criar/gerir cardápios, categorias e itens; ativar um cardápio
- Usuário: visualizar itens do cardápio ativo da loja; busca global por item

**Responsabilidades:**
- CRUD de cardápios (flag `is_active`: apenas 1 ativo por estabelecimento)
- CRUD de categorias dentro de um cardápio
- CRUD de itens (produto: nome, descrição, preço, disponibilidade, foto)
- Expõe o cardápio ativo com categorias e itens para o app do consumidor
- Suporta busca textual por nome de produto/categoria (PostgreSQL full-text)

**Regra de negócio importante:** Ativar um cardápio desativa automaticamente o anterior (unicidade do cardápio ativo por estabelecimento).

**Tabelas:**

```sql
catalog.menus (
  id                UUID PRIMARY KEY,
  establishment_id  UUID NOT NULL,
  name              VARCHAR(150) NOT NULL,
  is_active         BOOLEAN NOT NULL DEFAULT FALSE,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
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
  id            UUID PRIMARY KEY,
  category_id   UUID NOT NULL REFERENCES catalog.categories(id),
  name          VARCHAR(150) NOT NULL,
  description   TEXT,
  price         NUMERIC(10, 2) NOT NULL,
  is_available  BOOLEAN NOT NULL DEFAULT TRUE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
)

catalog.product_media (
  id          UUID PRIMARY KEY,
  product_id  UUID NOT NULL REFERENCES catalog.products(id),
  url         TEXT NOT NULL,
  media_type  VARCHAR(20) NOT NULL DEFAULT 'image',
  is_primary  BOOLEAN NOT NULL DEFAULT FALSE
)
```

---

### 4. `svc-events` — Eventos

**Schema:** `events`

**Contexto:** Foodtrucks frequentemente se reúnem em feiras, festivais e eventos. Este serviço gerencia esses eventos e o vínculo entre estabelecimentos e eventos. O usuário descobre estabelecimentos filtrando por evento.

**Quem usa:**
- Lojista: criar evento ou vincular-se a um evento existente
- Usuário: descobrir eventos, filtrar lojas por evento

**Responsabilidades:**
- CRUD de eventos (nome, localização, datas)
- Lojista cria evento ou se vincula a evento já existente
- Expõe lista de eventos ativos para descoberta de estabelecimentos

**Tabelas:**

```sql
events.events (
  id                  UUID PRIMARY KEY,
  name                VARCHAR(200) NOT NULL,
  description         TEXT,
  address             TEXT,
  latitude            DECIMAL(10, 7),
  longitude           DECIMAL(10, 7),
  start_at            TIMESTAMPTZ NOT NULL,
  end_at              TIMESTAMPTZ NOT NULL,
  created_by_user_id  UUID NOT NULL,   -- ID em users.users (lojista criador)
  banner_url          TEXT,
  is_active           BOOLEAN NOT NULL DEFAULT TRUE,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
)

events.participations (
  id                UUID PRIMARY KEY,
  event_id          UUID NOT NULL REFERENCES events.events(id),
  establishment_id  UUID NOT NULL,    -- ID em svc-establishments (sem FK cross-schema)
  joined_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(event_id, establishment_id)
)
```

---

### 5. `svc-location` — Geolocalização

**Schema:** `locations`

**Contexto:** Foodtrucks se movem. O usuário precisa ver a posição atual das lojas no mapa em tempo real e, ao ir buscar o pedido, acompanhar a localização atual do estabelecimento. Este serviço gerencia posições GPS e expõe geo-queries para descoberta.

**Quem usa:**
- Lojista: envia sua posição GPS periodicamente (via app do lojista)
- Usuário: visualiza mapa com lojas próximas, acompanha localização de uma loja específica

**Responsabilidades:**
- Receber e armazenar a última posição conhecida de cada estabelecimento
- Redis para acesso de baixa latência à posição atual (TTL longo, sobrescrito a cada update)
- PostgreSQL + PostGIS para geo-queries: "estabelecimentos abertos num raio de X km"
- Flush periódico do Redis para o PostgreSQL (persistência de histórico)
- Publica `EstabelecimentoLocalizacaoAtualizada` via RabbitMQ para o `svc-notifications` (que repassa ao hub WebSocket)

**Tabelas:**

```sql
-- Requer extensão: CREATE EXTENSION IF NOT EXISTS postgis;

locations.establishment_positions (
  id                UUID PRIMARY KEY,
  establishment_id  UUID NOT NULL UNIQUE,   -- ID em svc-establishments
  position          GEOGRAPHY(POINT, 4326) NOT NULL,  -- PostGIS
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
)

-- Histórico para analytics (particionar por mês em produção)
locations.position_history (
  id                UUID PRIMARY KEY,
  establishment_id  UUID NOT NULL,
  position          GEOGRAPHY(POINT, 4326) NOT NULL,
  recorded_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
)
```

**Redis:**
```
Chave: location:estab:{establishment_id}
Valor: { "lat": -23.5505, "lng": -46.6333, "updated_at": "..." }
TTL: 24h (sobrescrito a cada update do lojista)
```

---

### 6. `svc-orders` — Pedidos

> Inclui o **carrinho** (estado pré-pedido gerido em Redis)

**Schema:** `orders`

**Contexto:** Coração transacional do FoodeApp. Gerencia todo o ciclo de vida de um pedido e orquestra a SAGA de pedido via MassTransit (ADR-007). Publica todos os eventos de pedido via Outbox (ADR-017).

**Quem usa:**
- Usuário: criar pedido, acompanhar status, ver histórico
- Lojista: receber, aceitar, rejeitar, atualizar status, ver histórico

**Responsabilidades:**
- Criar pedido em estado `PENDENTE`
- Gerenciar transições de status:
  ```
  PENDENTE → ACEITO | REJEITADO
  ACEITO → EM_PREPARO → PRONTO → FINALIZADO
  Qualquer estado → CANCELADO (dentro das regras)
  ```
- Aceite automático por tempo (configurado em `svc-establishments`) ou manual pelo lojista
- Ver histórico de pedidos (usuário vê os seus; lojista vê os da sua loja)
- Orquestrar a SAGA: Criar Pedido → Processar Pagamento → Confirmar Pedido

**Tabelas:**

```sql
orders.orders (
  id                UUID PRIMARY KEY,
  user_id           UUID NOT NULL,            -- ID em users.users
  establishment_id  UUID NOT NULL,            -- ID em svc-establishments
  status            VARCHAR(30) NOT NULL,     -- PENDENTE | ACEITO | REJEITADO | EM_PREPARO | PRONTO | FINALIZADO | CANCELADO
  total_amount      NUMERIC(10, 2) NOT NULL,
  notes             TEXT,                     -- observação geral do pedido
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
)

orders.order_items (
  id                     UUID PRIMARY KEY,
  order_id               UUID NOT NULL REFERENCES orders.orders(id),
  product_id             UUID NOT NULL,           -- ID original em catalog.products
  product_name_snapshot  VARCHAR(150) NOT NULL,   -- snapshot no momento do pedido
  unit_price_snapshot    NUMERIC(10, 2) NOT NULL, -- snapshot no momento do pedido
  quantity               SMALLINT NOT NULL,
  notes                  TEXT                     -- ex: "sem cebola"
)

orders.order_status_history (
  id           UUID PRIMARY KEY,
  order_id     UUID NOT NULL REFERENCES orders.orders(id),
  from_status  VARCHAR(30),
  to_status    VARCHAR(30) NOT NULL,
  changed_by   UUID,      -- user_id que fez a transição (NULL = sistema)
  changed_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  reason       TEXT
)

-- Estado da SAGA persistido pelo MassTransit
orders.saga_state (
  id              UUID PRIMARY KEY,
  correlation_id  UUID NOT NULL UNIQUE,
  current_state   VARCHAR(50) NOT NULL,
  order_id        UUID,
  data            JSONB,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
)

-- Outbox para eventos de pedido (ADR-017)
orders.outbox_messages (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type          VARCHAR(255) NOT NULL,
  payload       JSONB NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  published_at  TIMESTAMPTZ NULL,
  retry_count   INT NOT NULL DEFAULT 0
)
```

**Redis (carrinho):**
```
Chave: cart:{user_id}
Valor (Hash):
  establishment_id: "uuid"
  items: [{ product_id, name_snapshot, price_snapshot, quantity, notes }]
  subtotal: 49.90
TTL: 86400 (24h, renovado a cada alteração)
```

---

### 7. `svc-notifications` — Notificações & Realtime

> Unifica entrega de notificações (push/email/WhatsApp) e o hub WebSocket/SignalR

**Schema:** `notifications`

**Contexto:** Este serviço tem duas responsabilidades complementares: (1) entregar notificações *fora* do app (Push via FCM/APNs, WhatsApp via Twilio, e-mail via Resend) e (2) empurrar atualizações em tempo real *para* usuários com o app aberto via SignalR/WebSocket. Ambas as responsabilidades são desencadeadas pelos mesmos eventos do RabbitMQ, tornando natural sua coexistência no mesmo serviço.

**Quem usa:**
- Sistema (consumidor de eventos do RabbitMQ — coreografia)

**Responsabilidades:**

*Notificações fora do app:*
- Registrar e gerenciar tokens de dispositivo (FCM/APNs)
- Gerenciar preferências de notificação por usuário (opt-in/opt-out por canal e tipo)
- Entregar Push, WhatsApp e e-mail com hierarquia de fallback (ADR-027)
- Logar tentativas de entrega para rastreabilidade

*Realtime (in-app):*
- Manter conexões WebSocket/SignalR autenticadas (JWT no handshake)
- Consumir eventos do RabbitMQ: `PedidoStatusAlterado`, `EstabelecimentoLocalizacaoAtualizada`
- Emitir eventos para grupos SignalR corretos (`user:{id}`, `establishment:{id}`)
- Redis backplane para múltiplas instâncias (ADR-012, ADR-014)

**Grupos SignalR:**
```
user:{user_id}            → status do pedido (comprador)
establishment:{loja_id}   → novos pedidos e atualizações (lojista)
```

**Tabelas:**

```sql
notifications.device_tokens (
  id             UUID PRIMARY KEY,
  user_id        UUID NOT NULL,          -- ID em users.users
  token          TEXT NOT NULL,
  platform       VARCHAR(10) NOT NULL,   -- 'android' | 'ios' | 'web'
  is_active      BOOLEAN NOT NULL DEFAULT TRUE,
  registered_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, token)
)

notifications.preferences (
  id          UUID PRIMARY KEY,
  user_id     UUID NOT NULL,
  channel     VARCHAR(20) NOT NULL,   -- 'push' | 'whatsapp' | 'email'
  event_type  VARCHAR(50) NOT NULL,   -- 'pedido_confirmado' | 'pedido_cancelado' | etc.
  opted_in    BOOLEAN NOT NULL DEFAULT TRUE,
  UNIQUE(user_id, channel, event_type)
)

notifications.logs (
  id           UUID PRIMARY KEY,
  user_id      UUID NOT NULL,
  channel      VARCHAR(20) NOT NULL,
  event_type   VARCHAR(50) NOT NULL,
  status       VARCHAR(20) NOT NULL,   -- ENVIADO | FALHOU | IGNORADO
  error_msg    TEXT,
  sent_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
)
```

---

### 8. `svc-payments` — Pagamentos

**Schema:** `payments`

**Contexto:** Integração com Mercado Pago para processar cobranças. Nunca armazena dados de cartão — apenas tokens gerados pelo SDK frontend (PCI SAQ A — ADR-025). É acionado como etapa da SAGA do `svc-orders`.

**Quem usa:**
- Sistema (SAGA orquestrada pelo `svc-orders`)

**Responsabilidades:**
- Processar cobrança via cartão (tokenizado) ou PIX
- Receber webhooks do Mercado Pago para confirmar/rejeitar pagamentos assíncronos
- Emitir estorno em compensação de SAGA quando pedido é cancelado
- Publicar `PagamentoConfirmado` / `PagamentoFalhou` / `PagamentoEstornado` via Outbox
- Garantir idempotência via `X-Idempotency-Key` (ADR-013)

**Tabelas:**

```sql
payments.payments (
  id                    UUID PRIMARY KEY,
  order_id              UUID NOT NULL UNIQUE,
  amount                NUMERIC(10, 2) NOT NULL,
  method                VARCHAR(20) NOT NULL,   -- 'cartao' | 'pix'
  status                VARCHAR(20) NOT NULL,   -- PENDENTE | CONFIRMADO | FALHOU | ESTORNADO
  mp_transaction_id     TEXT,                  -- ID externo do Mercado Pago
  idempotency_key       UUID NOT NULL UNIQUE,  -- ADR-013
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
)

payments.payment_attempts (
  id            UUID PRIMARY KEY,
  payment_id    UUID NOT NULL REFERENCES payments.payments(id),
  attempt       SMALLINT NOT NULL,
  result        VARCHAR(20) NOT NULL,   -- SUCCESS | FAILURE
  error_code    TEXT,
  attempted_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
)

payments.refunds (
  id              UUID PRIMARY KEY,
  payment_id      UUID NOT NULL REFERENCES payments.payments(id),
  amount          NUMERIC(10, 2) NOT NULL,
  reason          TEXT NOT NULL,
  status          VARCHAR(20) NOT NULL,  -- PENDENTE | CONFIRMADO | FALHOU
  mp_refund_id    TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
)

payments.outbox_messages (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type          VARCHAR(255) NOT NULL,
  payload       JSONB NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  published_at  TIMESTAMPTZ NULL,
  retry_count   INT NOT NULL DEFAULT 0
)
```

---

## BFFs (Apresentação — ADR-010)

Os BFFs não são módulos de domínio. São serviços de agregação e composição dedicados por canal de frontend, vivem atrás do Kong e não possuem schema de banco.

### `bff-web` — Backend for Frontend (Painel do Lojista)

**Schema:** nenhum

**Atende:** Frontend React Web — painel de gerenciamento do lojista

**Serviços que agrega:**
- `svc-establishments` — configurações da loja
- `svc-catalog` — gestão de cardápio
- `svc-orders` — pedidos ao vivo e histórico
- `svc-events` — criar/gerenciar eventos

**Endpoints típicos:**
```
GET  /dashboard                  → resumo do dia (pedidos, receita)
GET  /orders/live                → pedidos pendentes/em preparo
GET  /orders/history             → histórico com filtros e paginação
GET  /menu                       → cardápio ativo com categorias e itens
GET  /analytics                  → dados históricos para gráficos
POST /orders/:id/accept          → aceitar pedido
POST /orders/:id/reject          → rejeitar pedido
PUT  /orders/:id/status          → avança status do pedido
```

---

### `bff-app` — Backend for Frontend (App do Consumidor)

**Schema:** nenhum

**Atende:** App React Native — consumidor final

**Serviços que agrega:**
- `svc-users` — perfil e favoritos do usuário
- `svc-location` + `svc-establishments` — mapa de lojas próximas
- `svc-events` — descoberta de eventos
- `svc-catalog` — cardápio e itens da loja selecionada
- `svc-orders` — carrinho, fazer pedido, acompanhar status, histórico

**Endpoints típicos:**
```
GET  /discover?lat=&lng=&radius= → lojas próximas (mapa) com filtros
GET  /discover?event_id=         → lojas de um evento específico
GET  /search?q=                  → busca global por loja ou item
GET  /stores/:id                 → detalhe da loja + cardápio ativo
GET  /cart                       → carrinho atual do usuário (via svc-orders/Redis)
POST /cart/items                 → adicionar item ao carrinho
POST /checkout                   → cria pedido a partir do carrinho
GET  /orders/:id                 → status do pedido
GET  /orders/history             → pedidos anteriores
GET  /favorites                  → lojas favoritadas (via svc-users)
POST /favorites/:establishment_id → favoritar/desfavoritar loja
```

---

## Mapa de Comunicação

### Síncrona (HTTP via Istio — ADR-022)

| Origem | Destino | Motivo |
|--------|---------|--------|
| `bff-web` | `svc-users`, `svc-establishments`, `svc-catalog`, `svc-orders`, `svc-events` | Agrega dados para o painel |
| `bff-app` | `svc-users`, `svc-location`, `svc-establishments`, `svc-catalog`, `svc-orders`, `svc-events` | Agrega dados para o app |
| `svc-orders` | `svc-catalog` | Valida disponibilidade e obtém snapshot de preço (carrinho + checkout) |

### Assíncrona (RabbitMQ + Outbox — ADR-006, ADR-017)

| Exchange / Evento | Produz | Consome |
|-------------------|--------|---------|
| `users.user_registered` | `svc-users` | `svc-notifications` (registrar preferências padrão) |
| `establishment.opened` / `establishment.closed` | `svc-establishments` | `svc-notifications` (hub WebSocket) |
| `establishment.location_updated` | `svc-location` | `svc-notifications` (hub WebSocket + push se app fechado) |
| `order.created` | `svc-orders` | `svc-payments` (SAGA), `svc-notifications` |
| `order.status_changed` | `svc-orders` | `svc-notifications` (push + WebSocket) |
| `order.cancelled` | `svc-orders` | `svc-payments` (compensação/estorno) |
| `payment.confirmed` | `svc-payments` | `svc-orders` (SAGA: avançar estado) |
| `payment.failed` | `svc-payments` | `svc-orders` (SAGA: compensar), `svc-notifications` |
| `payment.refunded` | `svc-payments` | `svc-notifications` |

---

## SAGA: Fluxo Principal de Pedido

```
Usuário faz checkout (bff-app → svc-orders, que lê o carrinho do Redis)
│
├─ svc-orders: limpa carrinho Redis + cria pedido PENDENTE + salva SAGA state + Outbox { order.created }
│
├─ svc-payments: recebe order.created → processa cobrança
│     ├─ Sucesso → Outbox { payment.confirmed }
│     │     └─ svc-orders: pedido → AGUARDANDO_ACEITE + Outbox { order.status_changed }
│     │           ├─ svc-realtime: notifica usuário e lojista
│     │           └─ svc-notifications: envia push "Pedido recebido"
│     │
│     └─ Falha → Outbox { payment.failed }
│           └─ svc-orders: pedido → CANCELADO (compensação)
│                 └─ svc-notifications: envia push "Pagamento recusado"
│
├─ Lojista aceita/rejeita o pedido
│     └─ svc-orders: pedido → ACEITO | REJEITADO + Outbox { order.status_changed }
│           └─ svc-notifications: WebSocket (usuário) + push ao usuário
│
└─ Lojista atualiza status até PRONTO
      └─ svc-orders: pedido → EM_PREPARO → PRONTO + Outbox { order.status_changed }
            └─ svc-notifications: WebSocket live (usuário) + push "Seu pedido está pronto!"
```

---

## Decisões de Fronteira Importantes

| Cenário | Onde fica |
|---------|-----------|
| Autenticação (login/logout/tokens) | **Keycloak** (externo) — ADR-026 |
| Perfil de usuário pós-cadastro e favoritos | `svc-users` |
| Configuração da loja | `svc-establishments` |
| Cardápio e itens | `svc-catalog` |
| Carrinho pré-pedido | `svc-orders` (Redis, gerido pelo mesmo serviço) |
| Pedido confirmado e histórico | `svc-orders` |
| Snapshot de preço/nome do item no pedido | `orders.order_items` (cópia no momento do pedido; nunca consulta `catalog` para pedidos já feitos) |
| Posição GPS atual (baixa latência) | `svc-location` → Redis |
| Posição GPS histórica | `svc-location` → PostgreSQL |
| Notificação push/email/whatsapp | `svc-notifications` |
| Atualização live (WebSocket) | `svc-notifications` (SignalR embutido) |
| Busca global (item/restaurante) | Endpoints de query do `svc-catalog` + `svc-establishments`, agregados pelo BFF (PostgreSQL full-text — sem serviço dedicado no estágio atual) |

---

## Schemas PostgreSQL — Resumo

```
postgres/
├── users.*              → svc-users
├── establishments.*    → svc-establishments
├── catalog.*           → svc-catalog
├── events.*            → svc-events
├── locations.*         → svc-location (+ extensão PostGIS)
├── orders.*            → svc-orders
├── notifications.*     → svc-notifications
└── payments.*          → svc-payments
```

> `svc-orders` e `svc-notifications` também usam **Redis** para estado efêmero (carrinho e backplane SignalR, respectivamente), mas não possuem schemas adicionais.

**Regras absolutas** (ADR-002):
- Cada serviço acessa **apenas o seu próprio schema**
- Zero JOINs entre schemas
- Zero foreign keys entre schemas
- Toda troca de dados entre schemas = via fila (RabbitMQ) ou chamada HTTP entre serviços
