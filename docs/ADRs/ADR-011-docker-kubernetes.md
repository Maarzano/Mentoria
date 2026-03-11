# ADR-011: Docker para Containerização e Kubernetes para Orquestração

**Status:** Aceito  
**Data:** 2026-03-10

---

## Contexto

Com múltiplos microserviços, BFFs e serviços de infraestrutura (Redis, RabbitMQ, Kong, etc.), é essencial ter uma forma padronizada de:
- **Empacotar** cada serviço de forma isolada e reproduzível (independente do ambiente).
- **Executar** múltiplas instâncias dos serviços com alocação eficiente de recursos.
- **Escalar** serviços individualmente conforme a demanda.
- **Gerenciar** saúde dos serviços, restart automático em falhas, rolling deployments sem downtime.
- **Isolar** dependências: cada serviço carrega exatamente o que precisa, sem conflito com outros.

## Decisão

Adotaremos **Docker** para containerização de todos os serviços e **Kubernetes (K8s)** para orquestração dos containers em produção.

### Docker:
- Todo serviço terá um `Dockerfile` otimizado (multi-stage build para imagens menores).
- As imagens serão armazenadas em um registry de containers (ex: GitHub Container Registry ou DockerHub).
- `docker-compose` será usado para o ambiente de desenvolvimento local, subindo todos os serviços com um único comando.

### Kubernetes:
- Cada microserviço será um **Deployment** no K8s com réplicas configuráveis.
- **Horizontal Pod Autoscaler (HPA)** será configurado para escalar automaticamente baseado em CPU/memória ou métricas customizadas.
- **Liveness e Readiness Probes** garantem que pods não saudáveis sejam reiniciados e removidos do balanceamento automaticamente.
- **Kong Ingress Controller** (ADR-009) gerencia o roteamento de entrada no cluster.
- Secrets e configurações são gerenciados via **Kubernetes Secrets** e **ConfigMaps**, nunca embutidos na imagem.
- O provisionamento do cluster é gerenciado via IaC (ADR-020 — Terraform).

## Consequências

### Positivas

- **Elasticidade real**: o HPA escala os pods conforme necessidade, reduzindo custo em períodos de baixo tráfego e garantindo capacidade em picos.
- **Ambientes idênticos**: a imagem Docker garante que o que roda em dev/staging é o mesmo que vai para prod.
- **Rolling deployments** sem downtime: Kubernetes faz a troca gradual de pods na nova versão.
- **Self-healing**: pods que morrem são reiniciados automaticamente.
- **Isolamento de recursos** por serviço: cada pod tem seus limites de CPU e memória definidos.
- Facilita a estratégia de monorepo (ADR-021): múltiplos Dockerfiles, um por serviço, dentro do mesmo repositório.

### Negativas / Trade-offs

- Kubernetes tem **alta complexidade operacional**: curva de aprendizado significativa para o time.
- Overhead de infraestrutura: o próprio K8s consome recursos (control plane, etc.).
- Debugging dentro de containers pode ser mais difícil — exige familiaridade com `kubectl`, logs, exec, etc.
- Gestão de storage persistente (ex: para PostgreSQL) no Kubernetes tem seus próprios desafios (Persistent Volumes).
- Custo maior de cloud comparado a deployments simples em VMs.

### Neutras / Observações

- Para ambientes não-produtivos (dev local), `docker-compose` é suficiente e muito mais simples.
- Serviços stateful (PostgreSQL, Redis, RabbitMQ) podem rodar fora do Kubernetes (como serviços gerenciados na cloud) para simplificar a operação — essa decisão deve ser reavaliada com base no provedor de cloud escolhido.
- **Namespace por ambiente** (ex: `foodeapp-staging`, `foodeapp-production`) para isolamento dentro do mesmo cluster.
- Network Policies devem ser configuradas para restringir comunicação entre pods apenas ao necessário (princípio do menor privilégio).
