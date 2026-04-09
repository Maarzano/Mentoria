# ADR-026: Estratégia de Autenticação e Autorização

**Status:** Aceito  
**Data:** 2026-03-10

---

## Contexto

O FoodeApp possui múltiplos tipos de usuário (Comprador, Estabelecimento, Entregador, Admin) acessando o sistema por canais distintos (app mobile, web, painel do estabelecimento). É necessário definir como esses usuários:

1. **Se autenticam**: provam quem são.
2. **São autorizados**: o sistema decide o que podem fazer.

Os diagramas arquiteturais indicam a presença de um "Sistema de login" externo e Ousers como abordagem. As opções avaliadas foram:

| Abordagem | Prós | Contras |
|-----------|------|---------|
| **users próprio (usuario + senha)** | Controle total | Alta responsabilidade de segurança, gestão de senhas, MFA, rotação de tokens |
| **Ousers 2.0 Social (Google, Apple)** | UX fluida, sem senha para gerenciar | Dependência de terceiros, Apple obrigatório para iOS App Store |
| **Keycloak (Identity Provider self-hosted)** | Controle total + Ousers2/OIDC padrão + social login integrado | Mais um componente a operar |
| **users0 / Cognito (SaaS)** | Zero operação, MFA, social login embutido | Custo recorrente, lock-in de vendor |

O Kong (ADR-009) já está na borda validando JWT — portanto a estratégia de autenticação precisa ser compatível com validação de token no gateway.

## Decisão

Adotaremos **Keycloak** como Identity Provider (IdP) central do FoodeApp, implementando **Ousers 2.0 + OIDC (OpenID Connect)** para autenticação e **JWT com claims de role/permissão** para autorização.

### Fluxos de autenticação

| Canal | Fluxo Ousers 2.0 |
|-------|----------------|
| Web (React) | usersorization Code + PKCE |
| Mobile (React Native) | usersorization Code + PKCE |
| Painel estabelecimento | usersorization Code + PKCE |
| Service-to-service (interno) | Client Credentials (sem usuário) |

### Login social suportado inicialmente

- **Google** (Comprador e Estabelecimento)
- **Apple** (obrigatório para iOS App Store — qualquer app com login social deve oferecer "Sign in with Apple")

### Estrutura do JWT

```json
{
  "sub": "uuid-do-usuario",
  "email": "usuario@exemplo.com",
  "realm_roles": ["comprador"],
  "resource_access": {
    "foodeapp": {
      "roles": ["fazer-pedido", "ver-historico"]
    }
  },
  "estabelecimento_id": "uuid-estabelecimento",  // apenas se role = estabelecimento
  "exp": 1740000000,
  "iat": 1739996400
}
```

### Topologia de autenticação

```
Cliente (Web/App)
    │  1. usersorization Code + PKCE → Keycloak
    │  2. Keycloak retorna access_token (JWT) + refresh_token
    ↓
Kong API Gateway (ADR-009)
    │  3. Valida assinatura do JWT (JWKS endpoint do Keycloak)
    │  4. Injeta headers: X-User-Id, X-User-Roles no request interno
    ↓
BFF / Microserviços
    │  5. Confiam nos headers injetados pelo Kong (sem revalidar o JWT)
    │  6. Autorização: verificam role/permissão para a operação específica
```

### Autorização nos serviços

- Os microserviços **não chamam o Keycloak**. Eles recebem os claims via headers injetados pelo Kong (já validados na borda).
- Autorização fine-grained (ex: "apenas dono do estabelecimento pode editar seu cardápio") é feita no próprio serviço comparando o `estabelecimento_id` do token com o recurso sendo acessado.
- Roles disponíveis: `comprador`, `estabelecimento`, `entregador`, `admin`.

### Gestão de tokens

| Token | TTL | Renovação |
|-------|-----|-----------|
| access_token (JWT) | 15 minutos | Via refresh_token |
| refresh_token | 7 dias | Rotação automática (Refresh Token Rotation) |
| refresh_token (remember me) | 30 dias | Rotação automática |

- Refresh Token Rotation: a cada uso do refresh_token, um novo é emitido e o anterior é invalidado — proteção contra roubo de token.
- Revogação de tokens: via Keycloak session management (logout global invalida todos os tokens do usuário).

## Consequências

### Positivas

- OIDC/Ousers 2.0 são padrões abertos — sem lock-in no protocolo.
- Keycloak concentra toda a complexidade de users: MFA, rate limiting de login, bloqueio de brute-force, RBAC, social login.
- Os microserviços ficam completamente desacoplados da lógica de autenticação — recebem apenas os claims no header.
- PKCE previne interceptação de usersorization code em apps mobile/SPA sem backend secret.
- Social login reduz atrito no cadastro (especialmente para compradores).
- Sign in with Apple atende requisito obrigatório da App Store.

### Negativas / Trade-offs

- Keycloak é mais um componente de infra para operar — requer HA, banco de dados próprio (PostgreSQL separado do FoodeApp), monitoramento.
- Curva de aprendizado na configuração de realms, clients, flows e mapeamento de claims.
- Access token de 15 minutos exige que o cliente (React/React Native) implemente renovação automática com o refresh token — complexidade no frontend.
- O Keycloak se torna crítico: se cair, nenhum usuário consegue fazer login. Requer réplicas e health checks.

### Neutras / Observações

- O Keycloak deve rodar em namespace Kubernetes separado (`foodeapp-infra`) com ao menos 2 réplicas.
- Banco do Keycloak é PostgreSQL independente — não compartilha instância com os dados de negócio.
- Para ambientes de desenvolvimento, um Keycloak local via `docker-compose` com realm pré-configurado importado via arquivo JSON.
- **Estabelecimentos** criados pelo admin recebem um `estabelecimento_id` como claim customizado no Keycloak via Protocol Mapper — isso permite que o serviço de Catálogo valide ownership sem query extra.
- O Kong usa o endpoint JWKS público do Keycloak para validar tokens sem precisar chamar o Keycloak a cada request (validação local da assinatura RS256).
