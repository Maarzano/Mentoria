# ADR-024 — CI/CD com GitHub Actions (com possível migração para Jenkins)

**Status:** Aceito  
**Data:** 2026-03-10  
**Decisores:** Time de Arquitetura  
**Tags:** `ci/cd` `infraestrutura` `devops` `automação`

---

## Contexto

O FoodeApp é um monorepo (ADR-021) com múltiplos microserviços .NET 10, dois frontends (React Web + React Native) e infraestrutura como código via Terraform (ADR-020). É necessário um pipeline de CI/CD para:

- Executar testes automatizados a cada push/PR
- Fazer build e publicação das imagens Docker (ADR-011)
- Aplicar mudanças de infraestrutura via Terraform
- Fazer purge do CDN após deploy (ADR-023)
- Garantir qualidade antes de chegar em produção

A escolha da ferramenta impacta custo, portabilidade, tempo de onboarding e complexidade de manutenção.

---

## Decisão

**Usar GitHub Actions como ferramenta de CI/CD na fase inicial do projeto.**

A migração para Jenkins será avaliada quando houver necessidade de maior controle sobre infraestrutura de build, runners proprietários ou restrições de compliance que o GitHub Actions não suporte.

---

## Estrutura dos Pipelines

### Fluxo principal

```
Push / PR
    │
    ▼
┌─────────────────────────────────────┐
│  CI (pull_request → main)           │
│  1. Checkout + cache de dependências│
│  2. Build .NET (dotnet build)       │
│  3. Testes unitários + integração   │
│  4. Build imagem Docker (sem push)  │
│  5. Lint / análise estática         │
└─────────────────────────────────────┘
    │ merge em main
    ▼
┌─────────────────────────────────────┐
│  CD (push → main)                   │
│  1. Build + push da imagem Docker   │
│     Para: GitHub Container Registry │
│  2. Atualiza manifests Kubernetes   │
│  3. terraform plan + apply          │
│  4. Purge do index.html no CDN      │
│     (ADR-023)                       │
└─────────────────────────────────────┘
```

### Estratégia de gatilhos

| Evento | Pipeline | Ambiente alvo |
|---|---|---|
| Pull Request aberto/atualizado | CI (lint, build, testes) | — |
| Merge em `main` | CD automático | Staging |
| Tag `v*.*.*` | CD manual com aprovação | Produção |
| Cron diário | Scan de vulnerabilidades | — |

### Segredos e variáveis

Todos os segredos (tokens Cloudflare, credenciais Docker registry, kubeconfig, Terraform Cloud token) são armazenados em **GitHub Actions Secrets**, nunca em arquivos no repositório.

```yaml
# Exemplo de referência segura
- name: Login no Container Registry
  uses: docker/login-action@v3
  with:
    registry: ghcr.io
    username: ${{ github.actor }}
    password: ${{ secrets.GITHUB_TOKEN }}
```

---

## Por que GitHub Actions agora

| Critério | GitHub Actions | Jenkins |
|---|---|---|
| Onboarding | Imediato — integrado ao repositório | Alto — requer servidor, configuração, plugins |
| Custo inicial | Gratuito para repositórios públicos; minutos generosos em privados | Servidor próprio (custo de infra) |
| Manutenção | Zero infraestrutura de CI para gerenciar | Time precisa manter o servidor Jenkins |
| Integração com GitHub | Nativa (PRs, checks, dependabot) | Via webhook + plugins |
| Runners para monorepo | Matrix strategy nativa | Requer configuração de agents |
| Portabilidade | Workflows em YAML no repositório | Jenkinsfile no repositório — mais portável que Actions |

---

## Critérios para migrar para Jenkins

A migração será considerada quando **dois ou mais** dos seguintes critérios forem atendidos:

1. **Runners self-hosted com hardware especializado** — ex: builds de React Native que precisam de macOS dedicado ou GPU
2. **Compliance / auditoria interna** — cliente ou regulação exige que CI/CD rode em infraestrutura própria da organização
3. **Custo** — minutos do GitHub Actions superam o custo de manter runners Jenkins próprios
4. **Integração com ferramentas legadas** — sistemas internos que só se integram via plugins Jenkins
5. **Pipelines muito complexos** — lógica de orquestração que o modelo YAML do GitHub Actions não expressa bem

---

## Preparação para migração futura

Para manter a portabilidade e facilitar uma eventual migração:

- **Lógica de build em scripts shell** (`scripts/build.sh`, `scripts/test.sh`) — nunca inline no YAML do Actions. O Jenkinsfile chamaria os mesmos scripts.
- **Imagens Docker determinísticas** — o artefato final é uma imagem; a ferramenta de CI é apenas quem a constrói e empurra
- **Variáveis de ambiente padronizadas** — usar nomes genéricos (`CI_REGISTRY`, `CI_TOKEN`) mapeados nos dois sistemas
- **Não usar features exclusivas de Actions** — evitar `github.event.*` inline na lógica de negócio de build; encapsular em scripts

---

## Consequências

### ✅ Positivas

- Pipelines operacionais em horas, não dias — sem infra de CI para provisionar
- Checks de PR integrados nativamente (status, comentários automáticos, bloqueio de merge)
- Matriz de testes (múltiplas versões do .NET, OS) express com `strategy.matrix`
- GitHub Actions Marketplace fornece actions prontas para Docker, Kubernetes, Terraform e Cloudflare
- Sem custo operacional de manter servidor de CI

### ❌ Negativas

- Lock-in parcial no GitHub — fluxos dependentes de `github.event.*` precisam ser reescritos na migração
- Minutos de Actions têm limite no plano gratuito; monorepo com muitos serviços pode consumir rápido
- Runners `ubuntu-latest` são efêmeros — dependências precisam de cache agressivo (`actions/cache`)

### ➖ Neutras

- Jenkins é uma opção madura e viável no futuro — a decisão não é irreversível
- A estratégia de separar lógica de build em scripts minimiza o esforço de migração

---

## Alternativas Consideradas

| Alternativa | Por que não agora |
|---|---|
| Jenkins | Overhead de operação alto no início do projeto |
| GitLab CI | Não usamos GitLab; migrar plataforma de repositório não justifica |
| CircleCI / Buildkite | Custo adicional; sem vantagem sobre Actions integrado ao GitHub |
| Tekton (Kubernetes-native) | Complexidade alta para o estágio atual do projeto |

---

## Relacionamentos

- **[ADR-011](ADR-011-docker-kubernetes.md)** — CI/CD constrói as imagens Docker e aplica manifests no cluster
- **[ADR-020](ADR-020-terraform-iac.md)** — pipeline executa `terraform plan` / `terraform apply`
- **[ADR-021](ADR-021-monorepo.md)** — estratégia de monorepo influencia a estrutura de matrix jobs no Actions
- **[ADR-023](ADR-023-cdn-assets-estaticos.md)** — pipeline executa purge do CDN após deploy do frontend
