# web (Painel do Lojista)

App **web** do FoodeApp — dashboard do **lojista** (estabelecimento). Roda em browser desktop, consome o `bff-web` via tRPC e o hub real-time do `svc-notifications` (Phoenix Channels) via token curto.

> Público-alvo: dono/operador de loja gerenciando pedidos em tempo real, cardápio, configurações e métricas. **Não é** site público de marketing nem app do consumidor.

---

## 1. Stack

| Item | Escolha |
|---|---|
| Framework | **React 19** |
| Build | **Vite** |
| Runtime / package manager | **Bun** |
| Linguagem | **TypeScript** |
| Routing | **TanStack Router** (file-based, type-safe) |
| State server | **TanStack Query** + `@trpc/react-query` |
| State client | **Zustand** (mínimo, UI state) |
| UI / styling | **shadcn/ui** (copy-paste) + **Tailwind CSS** |
| Tabelas | **TanStack Table** |
| Charts | **Recharts** ou **Tremor** (a definir) |
| Forms | **react-hook-form** + **zod** (resolver compartilhado com tRPC) |
| Auth | OIDC + PKCE (ZITADEL) — `react-oidc-context` (wrapper de `oidc-client-ts`) |
| Realtime | cliente `phoenix` JS — token curto emitido pelo `bff-web` |
| Crash + perf | **Sentry** (`@sentry/react`) |
| Analytics produto | **PostHog** (opcional MVP) |
| PWA | manifest + service worker mínimo (notificação desktop + install) |
| Testes | `bun test` (unit) + `@testing-library/react` (componente) + Playwright (E2E, opcional) |

### Por que essa stack

- **Vite** = HMR instantâneo, build moderno, sem ejetar nada. Padrão de fato para SPA.
- **Bun** unifica package manager + runtime de scripts/testes (mesmo do BFF) — uma toolchain, dois mundos.
- **TanStack Router** dá file-based routing **type-safe** (params/search-params tipados), loaders, code-splitting automático. Combina com TanStack Query nativamente.
- **TanStack Query mandatório** — cache, invalidação, refetch on focus/reconnect, optimistic updates (ADR-019). Mesma escolha do mobile, conhecimento se transfere.
- **Zustand mínimo** — UI state apenas (sidebar aberta, tema, modais). Server state **NUNCA** entra aqui.
- **shadcn/ui copy-paste** — você é dono dos componentes, sem upgrade-hell, customização ilimitada. Padrão atual da indústria pra dashboards internos.
- **TanStack Table** — headless, controla render. Essencial pra tabelas de pedidos com filtros/paginação/ordenação.
- **react-hook-form + zod** — performance + mesmo schema usado no tRPC (input validation single-source).

### Por que **não** isso

- ❌ Next.js — overkill pra app interno autenticado, SSR não agrega aqui.
- ❌ Redux/Zustand global de tudo — TanStack Query resolve.
- ❌ Material UI / Chakra — caixa-preta, theme limitado pro nosso DS.
- ❌ styled-components — Tailwind + CSS vars cobrem (mantemos como fallback se shadcn precisar de variant complexa).
- ❌ React Router 7 — TanStack Router é mais type-safe e moderno; mesmo ecossistema do Query.

---

## 2. Princípios

1. **Feature-based** — uma pasta por contexto, autocontida.
2. **Rotas thin** (`routes/`) — só compõem páginas de `features/`. Sem lógica.
3. **Server state em TanStack Query**, client state em Zustand mínimo.
4. **`shared/ui/` é o design system (shadcn)** — features importam daqui, não direto do `radix-ui` ou de classes Tailwind soltas para padrões compostos.
5. **`shared/trpc/` é a ÚNICA porta para o BFF** — `fetch` proibido em features.
6. **Cross-feature share?** Vira `shared/`. Regra dos 3.
7. **Composição** sobre herança.

---

## 3. Arquitetura — Feature-based + TanStack Router

### 3.1 Estrutura de pastas

```
web/
├── src/
│   ├── routes/                       # TanStack Router (file-based) — THIN
│   │   ├── __root.tsx                # app shell (sidebar, header, providers)
│   │   ├── login.tsx                 # importa features/auth/LoginPage
│   │   ├── _auth.tsx                 # layout protegido (AuthGuard)
│   │   └── _auth/                    # rotas autenticadas
│   │       ├── dashboard.tsx
│   │       ├── orders/
│   │       │   ├── index.tsx         # importa features/orders/OrdersPage
│   │       │   └── $orderId.tsx      # importa features/orders/OrderDetailPage
│   │       ├── menu/
│   │       │   ├── index.tsx
│   │       │   └── $itemId.tsx
│   │       └── settings/
│   │           ├── index.tsx
│   │           ├── billing.tsx
│   │           └── team.tsx
│   │
│   ├── features/                     # uma pasta por contexto
│   │   ├── orders/
│   │   │   ├── components/           # OrderTable, OrderCard, StatusBadge, OrderTimeline
│   │   │   ├── hooks/                # useOrders, useOrderDetails, useUpdateOrderStatus
│   │   │   ├── pages/                # OrdersPage.tsx, OrderDetailPage.tsx
│   │   │   └── realtime/             # subscribers do canal establishment:{id}
│   │   ├── menu/                     # CRUD de cardápio
│   │   ├── dashboard/                # KPIs + charts
│   │   ├── settings/
│   │   └── auth/
│   │       └── LoginPage.tsx
│   │
│   ├── shared/                       # genuinamente compartilhado
│   │   ├── ui/                       # shadcn copiado aqui — DS do app
│   │   │   ├── button.tsx
│   │   │   ├── dialog.tsx
│   │   │   ├── form.tsx
│   │   │   ├── data-table.tsx        # wrapper TanStack Table + shadcn
│   │   │   ├── skeletons/
│   │   │   └── error-boundary.tsx
│   │   ├── trpc/
│   │   │   └── client.ts             # cliente tRPC (httpBatchLink + auth header)
│   │   ├── auth/                     # OIDC PKCE wrapper, helpers de token
│   │   ├── realtime/                 # cliente phoenix.js + reconnect/auth
│   │   ├── charts/                   # wrappers Recharts/Tremor
│   │   ├── tables/                   # primitives TanStack Table (column helpers)
│   │   ├── forms/                    # FormField, FormError, useZodForm helper
│   │   ├── analytics/                # PostHog + Sentry wrappers
│   │   └── utils/
│   │
│   ├── providers/                    # composição de providers
│   │   ├── QueryProvider.tsx
│   │   ├── AuthProvider.tsx
│   │   ├── RouterProvider.tsx
│   │   ├── ThemeProvider.tsx
│   │   └── index.tsx
│   │
│   ├── styles/
│   │   └── globals.css               # Tailwind base + CSS vars do tema
│   ├── main.tsx
│   └── routeTree.gen.ts              # gerado pelo TanStack Router
│
├── public/
│   ├── manifest.webmanifest
│   └── icons/
├── index.html
├── vite.config.ts                    # com plugin TanStack Router + PWA
├── tailwind.config.ts
├── tsconfig.json
├── components.json                   # config shadcn
└── package.json
```

### 3.2 Regras do jogo

1. **Rotas (`routes/`) são thin** — importam `<XPage />` da feature. Sem hooks de query, sem lógica de fetch.
2. **`features/<nome>/` é autocontida** — pode importar `shared/`, **não importa de outras features**.
3. **`shared/ui/` é o design system (shadcn)** — features usam `<Button />`, `<Dialog />` daqui. Padrões compostos (DataTable, FormField) também moram aqui.
4. **`shared/trpc/` é a única porta para o BFF.** Ninguém usa `fetch`. Ninguém chama `trpc.X.useQuery` direto na página — sempre via hook na feature.
5. **Hooks de query/mutation dentro da feature**, convenção `use<Verbo>`:
   ```ts
   // features/orders/hooks/useOrders.ts
   export function useOrders(filters: OrderFilters) {
     return trpc.listOrders.useQuery(filters, {
       staleTime: 10_000,
       refetchOnWindowFocus: true,
     })
   }
   ```
6. **Mutations** com optimistic updates (ADR-019) e `Idempotency-Key` quando aplicável (já tratado pelo BFF, mas documentar no hook).
7. **Realtime por feature** — `features/orders/realtime/` assina canal e invalida queries do TanStack Query (`queryClient.invalidateQueries(['orders'])`).
8. **Cross-feature share** → `shared/`. **Regra dos 3.**

### 3.3 O que evitar

- ❌ `pages/` global ou `views/` global → vira lixão.
- ❌ `api/` global com todas queries → acopla features.
- ❌ Redux ou Zustand global de tudo.
- ❌ shadcn importado de `node_modules` esperando upgrade — **componentes ficam no repo**.
- ❌ `fetch` fora de `shared/trpc/` ou `shared/realtime/`.
- ❌ Lógica de negócio em rotas/páginas — mora em hooks da feature.

---

## 4. Decisões transversais

### 4.1 Auth (PKCE com ZITADEL)

- `react-oidc-context` (wrapper React do `oidc-client-ts`).
- **Access token em memória** (state do `AuthProvider`). **Refresh via redirect/iframe silencioso PKCE** — sem refresh token persistido no browser.
- **Não usar localStorage** para tokens (XSS).
- **Não proxy via cookie HttpOnly no BFF** — manteria BFF stateless é prioridade. Trade-off aceito: F5 obriga reautenticação silenciosa (iframe). TanStack Query rebusca automaticamente depois.
- Interceptor do tRPC client lê token do `AuthProvider`.

> Se o time decidir migrar pra cookie HttpOnly proxy futuramente, o ponto único de mudança é `shared/auth/` + adapter no `bff-web` — features não enxergam.

### 4.2 Guard de rotas

- TanStack Router `beforeLoad` no `_auth.tsx` checa `isAuthenticated` do `AuthProvider`.
- Não autenticado → `redirect({ to: '/login' })`.
- Login bem-sucedido → volta para `search.redirectTo` ou `/dashboard`.

### 4.3 Realtime (Phoenix Channels)

- Lojista entra na rota `_auth/orders` → `features/orders/realtime/` faz:
  1. Chama `bff-web.issueRealtimeToken()` → token curto (5–15 min) escopado em `establishment:{loja_id}`.
  2. Conecta direto no `svc-notifications` via `phoenix.js`.
  3. Eventos `order.created`, `order.updated` invalidam queries do TanStack Query e mostram toast `<NewOrderToast />`.
- Reconnect automático com refresh do token quando expirar.
- **Painel não fala WS pelo BFF.**

### 4.4 Notificações desktop (PWA)

- **MVP**: manifest + service worker mínimo (`vite-plugin-pwa`).
- Permissão `Notification.requestPermission()` ao entrar na primeira vez na tela de pedidos.
- Pedido novo → `new Notification('Novo pedido #123', { ... })` disparado pelo handler de realtime, mesmo com aba em background.
- **Sem offline complexo** — lojista usa online o dia todo.
- App instalável (ícone no dock/start menu).

### 4.5 Charts (decisão pendente)

| Opção | Quando faz sentido |
|---|---|
| **Recharts** | API simples, declarativa, React-friendly. **Default recomendado** pro MVP. |
| **Tremor** | Charts + dashboard primitives já estilizados Tailwind. Mais opinativo, ganha tempo. |
| **D3 puro** | Só se precisar customização extrema (não é o caso agora). |

> Decisão sugerida: começar com Tremor (acelera dashboard + KPI cards), cair para Recharts puro se algum chart específico não couber.

### 4.6 Tabelas

- **TanStack Table** (headless) + render com `<DataTable />` em `shared/ui/`.
- Filtros, paginação, ordenação, column resize — tudo no client para datasets pequenos; server-side via `pageIndex`/`sort` nos hooks da feature quando datasets crescerem.

### 4.7 Forms

- `react-hook-form` + `zodResolver` com **mesmo schema** que o BFF expõe via tRPC (zod compartilhado por tipo).
- Componentes `<FormField />`, `<FormError />` em `shared/forms/` wrappam shadcn `<Form />`.

### 4.8 Loading / erro

- **Skeleton screens** em `shared/ui/skeletons/` (não spinners).
- **ErrorBoundary** por feature/rota (`shared/ui/error-boundary.tsx`).
- Sentry captura o que escapa.
- Toasts via `shared/ui/toaster.tsx` (shadcn `sonner`).

### 4.9 Tema

- Light/dark via CSS vars + Tailwind `dark:` (padrão shadcn).
- Persistência: localStorage (UI state, não sensível).

### 4.10 i18n

- PT-BR only no MVP. `i18next` fica documentado como expansão futura (lojista internacional? raro).

---

## 5. Observabilidade

- **Sentry** (`@sentry/react`) — errors + performance + replay (sob política de privacidade).
- **PostHog** (opcional MVP) — `dashboard.viewed`, `order.accepted`, `menu.item_created`.
- **Web Vitals** → exporta para Sentry; mover para OTel-web quando o stack OTel JS estabilizar.
- **PII redacted** em logs/replay — nome cliente, telefone, endereço nunca capturados em texto.
- **Source maps** subidos pro Sentry no build CI.

---

## 6. Telas principais

| Tela | Feature | Use case principal (BFF) |
|---|---|---|
| Login | `auth` | OIDC PKCE direto no ZITADEL |
| Dashboard | `dashboard` | `getEstablishmentKpis`, `getRevenueSeries` |
| Lista de pedidos | `orders` | `listOrders` + WS Phoenix |
| Detalhe do pedido | `orders` | `getOrder`, `updateOrderStatus` (idempotente) |
| Cardápio | `menu` | `listMenuItems`, `createMenuItem`, `updateMenuItem` |
| Configurações da loja | `settings` | `getEstablishmentSettings`, `updateEstablishmentSettings` |
| Time / usuários | `settings/team` | `listTeamMembers`, `inviteTeamMember` |
| Faturamento | `settings/billing` | `getBillingSummary` |

---

## 7. Pontos abertos para discussão

- [ ] **Charts**: Tremor (default sugerido) vs Recharts puro — confirmar.
- [ ] **Auth storage**: token em memória + PKCE silent (recomendado) vs cookie HttpOnly proxy (BFF stateful). Decisão registrada como **memória + PKCE**, mas vale ADR formal.
- [ ] **PWA**: profundidade — só notificação + install no MVP, ou já preparar background sync para "fila offline" de aceite de pedidos?
- [ ] **E2E**: Playwright vs Cypress quando entrar no escopo.
- [ ] **Replay Sentry**: ligar com PII masking agressivo, ou desligar até definir política?
- [ ] **Multi-loja**: lojista com várias lojas — switcher no header? `establishment_id` na URL ou no contexto?
- [ ] **Permissões finas**: dono vs gerente vs operador — RBAC no BFF + flags no frontend (a partir das claims do ZITADEL).
