# ADR-021: Monorepo Único como Estratégia Inicial de Versionamento

**Status:** Aceito  
**Data:** 2026-03-10

---

## Contexto

Com múltiplos microserviços, BFFs e frontends, é necessário decidir como organizar o código-fonte nos repositórios:

**Polyrepo**: cada serviço/componente tem seu próprio repositório.
- ✅ Isolamento completo: cada time faz deploy do seu repositório independentemente.
- ❌ Compartilhamento de código difícil (contratos, tipos compartilhados, libs internas).
- ❌ Overhead de gerenciar dezenas de repositórios (CI/CD, permissões, issues, PRs).
- ❌ Mudanças que afetam múltiplos serviços exigem coordenação entre múltiplos PRs.

**Monorepo**: todo o código fica num único repositório.
- ✅ Compartilhamento de código sem overhead de packages externos.
- ✅ Mudanças cross-service em um único PR — facilita refactorings e atualizações de contrato.
- ✅ Um único pipeline de CI/CD com build incremental (só rebuilda o que mudou).
- ❌ Repositório cresce em tamanho com o tempo.
- ❌ Requer ferramentas de build inteligentes para não buildar tudo sempre.

Para um time pequeno em fase inicial de produto, a escolha impacta diretamente a produtividade diária de desenvolvimento.

## Decisão

Adotaremos **monorepo único** para conter todo o código-fonte do FoodeApp inicialmente.

### Estrutura proposta do monorepo:
```
FoodeApp/
  src/
    services/
      orders/           ← Microserviço de pedidos (.NET)
      payments/         ← Microserviço de pagamentos (.NET)
      menu/             ← Microserviço de cardápio (.NET)
      users/            ← Microserviço de usuários (.NET)
      notifications/    ← Microserviço de notificações (.NET)
    bffs/
      bff-web/          ← BFF para o frontend Web (.NET)
      bff-app/          ← BFF para o app mobile (.NET)
    frontends/
      web/              ← Frontend React Web
      app/              ← App React Native
    shared/
      contracts/        ← Contratos de mensagens e DTOs compartilhados
      libs/             ← Bibliotecas internas (ex: middlewares, extensões)
  infra/
    terraform/          ← IaC (ADR-020)
    k8s/                ← Manifests Kubernetes / Charts Helm
  docs/
    ADRs/               ← Este diretório
    diagrams/
```

### CI/CD com monorepo:
- Builds e deployments são **incrementais**: só os serviços que tiveram arquivos alterados são rebuiltados e re-deployados.
- Ferramentas como **Nx** (para Node/React) ou **scripts de path filtering** no GitHub Actions detectam quais serviços foram afetados por um commit.
- Cada serviço tem seu próprio `Dockerfile` e pipeline de deploy independente dentro do mesmo repositório.

## Consequências

### Positivas

- **Produtividade inicial alta**: um único `git clone`, uma única configuração de ambiente, fácil navegação entre serviços.
- Mudanças de contrato (ex: renomear um campo de mensagem) são feitas em um único PR com impacto visível em todos os consumidores.
- Compartilhamento de código (libs compartilhadas, contratos) sem overhead de package registry.
- Configuração de CI/CD centralizada e mais simples de manter inicialmente.
- Histórico de git unificado: fácil de entender a evolução do sistema como um todo.

### Negativas / Trade-offs

- À medida que o time cresce, o monorepo pode se tornar lento para clone e operações de git sem ferramentas adequadas (ex: git sparse-checkout, shallow clone).
- Times diferentes trabalhando no mesmo repositório exigem mais disciplina de branching e code review.
- Sem cuidado, o CI/CD pode buildar tudo sempre ao invés de só o que mudou — requer configuração de path filtering.
- Não há isolamento de permissões de acesso por serviço no repositório (qualquer contribuidor vê todo o código).

### Neutras / Observações

- Esta é uma **decisão estratégica para a fase inicial**. À medida que o produto e o time escalam, a migração para polyrepo (ou uma abordagem híbrida) pode ser avaliada — serviços com times separados e autonomia total são os primeiros candidatos.
- A separação física por diretórios já prepara o terreno para uma eventual extração para repositórios separados.
- Projetos como Google, Meta e Microsoft usam monorepos em escala com ferramentas específicas (Bazel, Buck, Nx). Para o porte do FoodeApp, não é necessário esse nível de complexidade inicialmente.
- Relacionado: ADR-001 (microserviços), ADR-011 (Docker — cada serviço tem seu Dockerfile), ADR-020 (Terraform no mesmo repo).
