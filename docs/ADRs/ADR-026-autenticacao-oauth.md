# ADR-026: Estratégia de Autenticação e Autorização

**Status:** Revisado (implementação diverge da decisão original — ver seção abaixo)
**Data original:** 2026-03-10
**Data da revisão:** 2026-04-22

---

## ⚠️ Revisão da Decisão (2026-04-22)

### Decisão Original vs Implementação Atual

| Item | ADR original | **Implementação real** |
|------|-------------|------------------------|
| Identity Provider | Keycloak | **ZITADEL v2** |
| Protocolos | OAuth 2.0 + OIDC | OAuth 2.0 + OIDC (mantidos) |
| Validação de JWT na borda | Kong + JWKS do Keycloak | **Kong + JWKS do ZITADEL** |
| Banco do IdP | PostgreSQL dedicado ao Keycloak | PostgreSQL compartilhado com database `zitadel` (dev local) |
| Atores no sistema | Comprador, Estabelecimento, Entregador, Admin | **Comprador, Lojista** (sem entregador — retirada presencial; admin não modelado nesta fase) |

### Motivos da mudança

A decisão de usar **ZITADEL** em vez de Keycloak foi tomada após avaliação prática:

1. **Cloud-native first**: ZITADEL nasceu cloud-native (Go, single binary, stateless). Keycloak (Java/WildFly) tem footprint maior e startup mais lento, impactando ambientes locais e ciclos de teste.
2. **Multi-tenant nativo**: ZITADEL trabalha com Organizations/Projects/Apps de forma nativa — o modelo casa diretamente com a estrutura `Org=FoodeApp / Project=FoodeApp` sem hacks de realm.
3. **API administrativa moderna**: Management API (gRPC/REST) bem documentada, usada pelo `svc-users` para promoção de role e operações administrativas.
4. **Operação simplificada em dev**: container único via `docker-compose` (`ghcr.io/zitadel/zitadel`), sem necessidade de import de realm JSON.
5. **Roles do projeto**: ZITADEL Project Roles substituem `realm_roles` do Keycloak — mesmo conceito, formato diferente nos claims.

### Impacto da mudança

- **ADR-009 (Kong)**: sem impacto conceitual — Kong continua validando JWT via JWKS, apenas a URL muda para o endpoint do ZITADEL (`/oauth/v2/keys`).
- **Claims do JWT**: estrutura levemente diferente (ver seção "Estrutura do JWT" abaixo).
- **`svc-users`**: integra com a Management API do ZITADEL para promoção de role e leitura de metadados; não armazena credenciais.
- **docker-compose local**: já contém o serviço `zitadel` com init container que cria a database `zitadel` no Postgres compartilhado.

---

## Contexto

O FoodeApp possui dois tipos de usuário (Comprador e Lojista) acessando o sistema por canais distintos (app mobile React Native, web React do painel do lojista). É necessário definir como esses usuários:

1. **Se autenticam**: provam quem são.
2. **São autorizados**: o sistema decide o que podem fazer.

As opções avaliadas foram:

| Abordagem | Prós | Contras |
|-----------|------|---------|
| **Auth próprio (usuário + senha)** | Controle total | Alta responsabilidade de segurança, gestão de senhas, MFA, rotação de tokens |
| **OAuth 2.0 Social (Google, Apple)** | UX fluida, sem senha para gerenciar | Dependência de terceiros, Apple obrigatório para iOS App Store |
| **Keycloak (Identity Provider self-hosted)** | Controle total + OAuth2/OIDC padrão + social login integrado | Stack Java pesada, footprint alto |
| **ZITADEL (Identity Provider self-hosted, cloud-native)** | OAuth2/OIDC + multi-tenant nativo + footprint baixo + Management API moderna | Comunidade menor que Keycloak, ecossistema mais novo |
| **Auth0 / Cognito (SaaS)** | Zero operação, MFA, social login embutido | Custo recorrente, lock-in de vendor |

O Kong (ADR-009) já está na borda validando JWT — portanto a estratégia de autenticação precisa ser compatível com validação de token no gateway via JWKS.

## Decisão

Adotaremos **ZITADEL** como Identity Provider (IdP) central do FoodeApp, implementando **OAuth 2.0 + OIDC (OpenID Connect)** para autenticação e **JWT com claims de role/permissão** para autorização.

### Fluxos de autenticação

| Canal | Fluxo OAuth 2.0 |
|-------|----------------|
| Web (React — painel do lojista) | Authorization Code + PKCE |
| Mobile (React Native — comprador) | Authorization Code + PKCE |
| Service-to-service (interno) | Client Credentials (sem usuário) |

### Login social (planejado)

- **Email + senha** (suportado nativamente pelo ZITADEL — fluxo principal no MVP)
- **Google** (Comprador e Lojista — planejado)
- **Apple** (obrigatório para iOS App Store quando login social estiver ativo — planejado)

### Estrutura do JWT (ZITADEL)

```json
{
  "iss": "https://zitadel.foodeapp.local",
  "sub": "281474976710656",
  "aud": ["foodeapp"],
  "email": "usuario@exemplo.com",
  "email_verified": true,
  "urn:zitadel:iam:org:project:roles": {
    "comprador": { "<orgId>": "FoodeApp" }
  },
  "exp": 1740000000,
  "iat": 1739996400
}
```

> O claim `sub` é o snowflake do ZITADEL e é armazenado em `users.zitadel_user_id` (string) no `svc-users`.

### Topologia de autenticação

```
Cliente (Web/App)
    │  1. Authorization Code + PKCE → ZITADEL
    │  2. ZITADEL retorna access_token (JWT) + refresh_token
    ↓
Kong API Gateway (ADR-009)
    │  3. Valida assinatura do JWT (JWKS endpoint do ZITADEL)
    │  4. Injeta headers: X-User-Id (claim 'sub') e X-User-Roles (project roles) no request interno
    ↓
BFF / Microserviços
    │  5. Confiam nos headers injetados pelo Kong (sem revalidar o JWT)
    │  6. Autorização: verificam role/permissão para a operação específica
```

### Autorização nos serviços

- Os microserviços **não chamam o ZITADEL** no caminho quente. Recebem os claims via headers injetados pelo Kong (já validados na borda).
- Autorização fine-grained (ex: "apenas dono do estabelecimento pode editar seu cardápio") é feita no próprio serviço comparando `X-User-Id` com o `owner_user_id` do recurso.
- Roles disponíveis: `comprador`, `lojista`.
- Promoção `comprador → lojista`: o `svc-users` chama a Management API do ZITADEL para adicionar a role `lojista` ao usuário (mantém a role `comprador`).

### Gestão de tokens

| Token | TTL | Renovação |
|-------|-----|-----------|
| access_token (JWT) | 15 minutos | Via refresh_token |
| refresh_token | 7 dias | Rotação automática (Refresh Token Rotation) |
| refresh_token (remember me) | 30 dias | Rotação automática |

- Refresh Token Rotation: a cada uso do refresh_token, um novo é emitido e o anterior é invalidado — proteção contra roubo de token.
- Revogação de tokens: via session management do ZITADEL (logout invalida tokens da sessão).

## Consequências

### Positivas

- OIDC/OAuth 2.0 são padrões abertos — sem lock-in no protocolo.
- ZITADEL concentra toda a complexidade de auth: MFA, rate limiting de login, bloqueio de brute-force, RBAC, social login, verificação de email, reset de senha.
- Os microserviços ficam completamente desacoplados da lógica de autenticação — recebem apenas os claims no header.
- PKCE previne interceptação de authorization code em apps mobile/SPA sem backend secret.
- Footprint operacional menor que Keycloak (single binary Go, sem JVM).
- Management API moderna facilita integração programática (promoção de role, listagem de usuários, etc.).

### Negativas / Trade-offs

- ZITADEL é mais um componente de infra para operar — requer HA e monitoramento em produção.
- Comunidade menor que Keycloak — menos material/exemplos públicos.
- Access token de 15 minutos exige que o cliente (React/React Native) implemente renovação automática com o refresh token — complexidade no frontend.
- O ZITADEL se torna crítico: se cair, nenhum usuário consegue fazer login. Requer réplicas e health checks em produção.

### Neutras / Observações

- Em produção, ZITADEL deve rodar em namespace Kubernetes separado (`foodeapp-infra`) com ao menos 2 réplicas e banco PostgreSQL dedicado.
- Em **dev local**, ZITADEL roda como container no `docker-compose.yml` com a database `zitadel` criada via init container no Postgres compartilhado (apenas para reduzir overhead local).
- O `svc-users` armazena o **Application Profile** vinculado ao usuário do ZITADEL via `users.zitadel_user_id` (= claim `sub` do JWT). Nunca armazena credenciais.
- O Kong usa o endpoint JWKS público do ZITADEL para validar tokens sem precisar chamar o ZITADEL a cada request (validação local da assinatura RS256).
- A claim de project roles do ZITADEL (`urn:zitadel:iam:org:project:roles`) é mapeada pelo Kong para o header `X-User-Roles` em formato simplificado (lista de roles).
