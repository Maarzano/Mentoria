# mobile (App do Comprador)

App **mobile** do FoodeApp — experiência do **consumidor** (iOS + Android). Consome o `bff-mobile` via tRPC e o hub real-time do `svc-notifications` (Phoenix Channels) via token curto.

---

## 1. Stack

| Item | Escolha |
|---|---|
| Framework | **Expo** (managed workflow) |
| Linguagem | **TypeScript** |
| Build / OTA | **EAS Build** + **EAS Update** |
| Plataformas | iOS + Android (uma única base) |
| Routing | **Expo Router** (file-based) |
| State server | **TanStack Query** + `@trpc/react-query` |
| State client | **Zustand** (mínimo, apenas UI state) |
| UI / styling | **Tamagui** |
| Forms | `react-hook-form` + `zod` |
| Auth | OIDC + PKCE (ZITADEL) — `expo-auth-session` + `expo-secure-store` |
| Push | **Expo Notifications** (MVP) — token registrado via BFF |
| Realtime | cliente `phoenix` JS — token curto emitido pelo `bff-mobile` |
| Localização | `expo-location` |
| Mapas | `react-native-maps` (MVP) |
| Crash | **Sentry** (`sentry-expo`) |
| Analytics produto | **PostHog** (opcional MVP) |
| Testes | `bun test` (unit) + `@testing-library/react-native` (componente) + Maestro (E2E, opcional) |

### Por que Expo (managed)

- Uma base, dois targets (iOS + Android) sem mexer em projeto nativo na maior parte do tempo.
- **EAS Build** elimina dor de Xcode/Gradle local.
- **EAS Update** = bugfix sem passar pela App Store.
- SDK oficial cobre push, location, secure-store, deep links — 90% do que precisamos.
- Migrar para `dev-client` é caminho aberto se um dia precisar de módulo nativo custom.

### Por que TanStack Query (mandatório, não opção)

- Cache, refetch on focus/reconnect, optimistic updates (ADR-019), retry com backoff — tudo pronto.
- Persistor com AsyncStorage = **offline mínimo** sem custo extra.
- Integração tRPC nativa → tipos end-to-end com o `bff-mobile`.

### Por que Zustand mínimo

- 1 KB, API direta, sem provider obrigatório, sem boilerplate.
- Suficiente para tema, modais abertos, flags de UI.
- **Regra dura**: server state **NUNCA** entra no Zustand. Se vem do backend, vive no TanStack Query.

### Por que Tamagui

- Componentes prontos (Button, Card, Sheet, Input, Stack…) — produtividade alta no MVP.
- Compilador AOT extrai estilos estáticos no build → árvore mais leve em runtime.
- Theme system robusto (tokens, dark mode, breakpoints).
- Trade-offs assumidos: setup inicial mais pesado (Babel + Metro plugin), curva de tokens/variants, bus-factor concentrado em poucos mantenedores. Mitigação: Tamagui só "vaza" para `shared/ui/` (regra 3.2 abaixo) — features nunca o importam direto.

---

## 2. Princípios

1. **Feature-based** — uma pasta por contexto, autocontida.
2. **Rotas thin** (`app/`) — só compõem páginas de `features/`. Sem lógica.
3. **Server state em TanStack Query**, client state em Zustand mínimo.
4. **`shared/ui/` esconde o framework de estilo** — features não importam Tamagui direto.
5. **`shared/trpc/` é a ÚNICA porta para o BFF** — `fetch` proibido em features.
6. **Cross-feature share?** Vira `shared/`. Regra dos 3 (duplicou 3 vezes? extrai).
7. **Composição** sobre herança — sem classes, sem `BaseScreen`.

---

## 3. Arquitetura — Feature-based + Expo Router

### 3.1 Estrutura de pastas

```
mobile/
├── app/                              # rotas Expo Router (file-based) — THIN
│   ├── _layout.tsx                   # providers globais (Query, Theme, Auth)
│   ├── (auth)/                       # rotas para não-autenticados
│   │   ├── _layout.tsx
│   │   └── login.tsx                 # importa features/auth/LoginPage
│   ├── (tabs)/                       # rotas autenticadas (guard no _layout)
│   │   ├── _layout.tsx               # AuthGuard + bottom tabs
│   │   ├── home.tsx                  # importa features/home/HomePage
│   │   ├── orders.tsx
│   │   ├── favorites.tsx
│   │   └── profile.tsx
│   ├── establishment/
│   │   └── [id].tsx                  # importa features/establishment/EstablishmentPage
│   └── order/
│       └── [id].tsx                  # importa features/order-tracking/OrderTrackingPage
│
├── src/
│   ├── features/                     # uma pasta por contexto (autocontida)
│   │   ├── home/
│   │   │   ├── components/           # EstablishmentCard, HomeHeader
│   │   │   ├── hooks/                # useNearbyEstablishments
│   │   │   └── HomePage.tsx          # composição renderizada por app/(tabs)/home.tsx
│   │   ├── establishment/
│   │   │   ├── components/
│   │   │   ├── hooks/
│   │   │   └── EstablishmentPage.tsx
│   │   ├── cart/
│   │   ├── checkout/
│   │   ├── order-tracking/
│   │   ├── favorites/
│   │   ├── profile/
│   │   └── auth/
│   │       └── LoginPage.tsx
│   │
│   ├── shared/                       # genuinamente compartilhado
│   │   ├── ui/                       # design system — esconde Tamagui
│   │   │   ├── Button.tsx
│   │   │   ├── Card.tsx
│   │   │   ├── Input.tsx
│   │   │   ├── skeletons/            # Skeleton padronizados
│   │   │   └── ErrorBoundary.tsx
│   │   ├── trpc/
│   │   │   └── client.ts             # cliente tRPC (httpBatchLink + auth header)
│   │   ├── auth/                     # OIDC PKCE, expo-secure-store wrapper
│   │   ├── realtime/                 # cliente phoenix.js + reconnect/auth
│   │   ├── analytics/                # PostHog + Sentry wrappers
│   │   ├── i18n/                     # i18next (opcional MVP)
│   │   └── utils/                    # helpers genéricos
│   │
│   └── providers/                    # integração com a árvore React
│       ├── QueryProvider.tsx
│       ├── TamaguiProvider.tsx
│       ├── AuthProvider.tsx
│       └── index.tsx                 # composição dos providers
│
├── assets/
├── app.config.ts
├── eas.json
├── tamagui.config.ts
├── tsconfig.json
└── package.json
```

### 3.2 Regras do jogo

1. **Rotas (`app/`) são thin** — importam `<XPage />` da feature e passam params. Sem hooks de query, sem lógica.
2. **`features/<nome>/` é autocontida** — pode importar `shared/`, **não importa de outras features**.
3. **1 página = 1 componente raiz na feature** (`HomePage.tsx`, `CheckoutPage.tsx`). Se a feature crescer pra 2+ páginas, criar subpasta `pages/`.
4. **`shared/ui/` é o design system** — Button, Card, Input. **Tamagui só é importado aqui dentro.** Features usam `<Button />` da `shared/ui/`, não `<Button />` do Tamagui.
5. **`shared/trpc/` é a única forma de falar com o BFF.** Ninguém usa `fetch`. Ninguém chama `trpc.X.useQuery` direto na tela — sempre via hook na feature.
6. **Hooks de query dentro da feature**, com convenção `use<Verbo>`:
   ```ts
   // features/home/hooks/useNearbyEstablishments.ts
   export function useNearbyEstablishments(coords: Coords) {
     return trpc.listNearbyEstablishments.useQuery(coords, {
       staleTime: 30_000,
       enabled: !!coords,
     })
   }
   ```
   A "regra de cache" (staleTime, enabled, retry) mora num lugar só. Mudar a estratégia = trocar 1 arquivo.
7. **Mutations** seguem mesma convenção (`useToggleFavorite`, `usePlaceOrder`) e disparam optimistic updates (ADR-019) via `onMutate` + rollback.
8. **Cross-feature share** → vira `shared/`. **Regra dos 3** (duplicou 3 vezes, extrai).

### 3.3 O que evitar

- ❌ Pasta `screens/` global → vira lixão.
- ❌ `api/` global com todas as queries → acopla features.
- ❌ `store/` Redux global → você provavelmente não precisa.
- ❌ Atomic Design rígido (atoms/molecules/organisms) → dogma sem ROI.
- ❌ `<TamaguiButton />` direto na feature → quebra a regra 4.
- ❌ `fetch` em qualquer lugar fora de `shared/trpc/` ou `shared/realtime/`.

---

## 4. Decisões transversais

### 4.1 Auth (PKCE com ZITADEL)

- `expo-auth-session` para o flow OIDC + PKCE.
- **Refresh token** em `expo-secure-store` (encriptado pelo SO). **Nunca em AsyncStorage.**
- **Access token em memória** + interceptor do tRPC client lê do `AuthProvider`.
- Deep link de retorno: `foodeapp://auth/callback` (registrado em `app.config.ts`).
- **Refresh é responsabilidade do app**, BFF não intermedia.

### 4.2 Guard de rotas

```
app/(auth)/_layout.tsx       # rotas públicas (login)
app/(tabs)/_layout.tsx       # AuthGuard — redireciona pra /login se não autenticado
app/establishment/[id].tsx   # também atrás do AuthGuard via parent layout
```

`AuthGuard` lê estado de `AuthProvider` e usa `<Redirect />` do Expo Router.

### 4.3 Realtime (Phoenix Channels)

- App chama `bff-mobile.issueRealtimeToken()` → recebe token curto (5–15 min) escopado em `user:{id}`.
- Conecta direto no `svc-notifications` via cliente `phoenix.js`.
- Reconnect automático com refresh do token quando expirar.
- **App não fala WS pelo BFF** — aproveita o BEAM.

### 4.4 Push notifications

- **MVP**: Expo Notifications. App registra device → envia push token via BFF (`registerPushToken`) → BFF salva em `svc-notifications`.
- **Pós-MVP**: migrar para FCM/APNs direto (`@react-native-firebase/messaging`) quando volume justificar — exige `dev-client`.

### 4.5 Mapas

- **MVP**: `react-native-maps` (Google Maps Android, MapKit iOS). Free tier cobre.
- Pós-MVP: avaliar Mapbox se precisar branding/clusters/animações.

### 4.6 Localização

- `expo-location` com permissão runtime.
- Pings GPS para `svc-location` (via BFF ou direto, a definir — preferência **via BFF** para autenticação centralizada).

### 4.7 Offline

- **Mínimo**: TanStack Query persistor → AsyncStorage. Última lista vista fica "stale" disponível.
- **Sem mutations offline** no MVP. App de delivery offline é caso raro.
- WatermelonDB / Realm fica para o futuro se aparecer dor real.

### 4.8 UI otimista (ADR-019)

- Toggle favorito, adicionar ao carrinho → `onMutate` + rollback no `onError`.
- Padrão: encapsulado nos hooks de mutation da feature.

### 4.9 Loading states

- **Skeleton screens** (não spinners). Padronizados em `shared/ui/skeletons/`.
- Spinner só para ações pontuais (botão de submit).

### 4.10 Tratamento de erros

3 níveis:

1. **Hook nível**: `onError` → toast (`shared/ui/Toast`).
2. **ErrorBoundary** por feature ou rota (`shared/ui/ErrorBoundary`).
3. **Sentry** captura tudo que escapou.

### 4.11 Forms

- `react-hook-form` (controle total, performance) + `zod` (mesmo schema do tRPC).
- Componentes em `shared/ui/forms/` (FormField, FormErrorText) wrappam Tamagui.

---

## 5. Observabilidade

- **Sentry** para crashes e performance (RN integration + source maps via EAS).
- **PostHog** (opcional MVP) para eventos de produto: `app.opened`, `order.placed`, `cart.item_added`.
- **Logs PII redacted** — telefone, email, CPF, endereço nunca em logs/analytics.
- **OTel mobile** fica fora do MVP — RN OTel é imaturo, ROI baixo.

---

## 6. Telas principais

| Tela | Feature | Use case principal (BFF) |
|---|---|---|
| Login | `auth` | OIDC PKCE direto no ZITADEL |
| Home | `home` | `listNearbyEstablishments` |
| Estabelecimento + cardápio | `establishment` | `getEstablishmentMenu` |
| Carrinho | `cart` | `addToCart`, `getCart`, `removeFromCart` |
| Checkout | `checkout` | `placeOrder` (idempotente) |
| Acompanhar pedido | `order-tracking` | `trackActiveOrder` + WS Phoenix |
| Histórico | `orders` | `listMyOrders` |
| Favoritos | `favorites` | `listFavorites`, `toggleFavorite` |
| Perfil | `profile` | `getMyProfile`, `updateMyProfile` |

---

## 7. Pontos abertos para discussão

- [ ] **GPS**: app envia direto ao `svc-location` ou via BFF? — recomendação: via BFF.
- [ ] **i18n**: PT-BR only no MVP ou já preparar `i18next`?
- [ ] **Stores**: política de privacidade, screenshots, política de cancelamento exigida pelas lojas — definir antes do submit.
- [ ] **Crash reporting**: Sentry confirmado; manter Firebase Crashlytics como backup ou só Sentry?
- [ ] **Tamagui vs NativeWind**: decisão consciente por Tamagui (componentes prontos). Reavaliar caso a configuração/bundle/bus-factor incomode no caminho.
- [ ] **Maestro vs Detox** para E2E quando entrar no escopo.
