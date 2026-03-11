# ADR-020: Infrastructure as Code com Terraform

**Status:** Aceito  
**Data:** 2026-03-10

---

## Contexto

A infraestrutura do FoodeApp envolve múltiplos componentes: cluster Kubernetes, instâncias de banco de dados PostgreSQL, Redis, RabbitMQ, Kong, serviços de observabilidade, redes, DNS, etc. Gerenciar essa infraestrutura manualmente via console da cloud traz problemas sérios:

- **Não-reprodutibilidade**: ambientes de staging e produção divergem ao longo do tempo.
- **Falta de rastreabilidade**: não há histórico de quem mudou o quê na infraestrutura.
- **Dificuldade de recuperação**: em caso de desastre, recriar o ambiente do zero é lento e propenso a erro.
- **Escalabilidade humana**: processos manuais não escalam com o time.

Infrastructure as Code (IaC) resolve esses problemas ao tratar a infraestrutura como código: versionada, revisada, testada e aplicada de forma automática.

## Decisão

Usaremos **Terraform** como ferramenta de IaC para provisionar e gerenciar toda a infraestrutura do FoodeApp.

### Escopo do Terraform:
- Provisionamento do cluster **Kubernetes** (via serviço gerenciado da cloud — ex: EKS, GKE, AKS).
- Instâncias de **PostgreSQL** gerenciadas (ex: RDS, Cloud SQL).
- Instâncias de **Redis** gerenciadas (ex: ElastiCache, Memorystore).
- Configuração de **networking**: VPCs, subnets, security groups, peerings.
- **DNS** e certificados SSL.
- **Registry de containers** (ex: ECR, GCR, GHCR).
- Configurações de **RabbitMQ** (se gerenciado externamente, ex: CloudAMQP) ou o chart Helm dentro do K8s.

### Organização do código Terraform:
```
infra/
  terraform/
    modules/
      kubernetes/
      database/
      redis/
      networking/
    envs/
      staging/
        main.tf
        variables.tf
        terraform.tfvars
      production/
        main.tf
        variables.tf
        terraform.tfvars
```

### Estado remoto:
- O estado do Terraform (`terraform.tfstate`) será armazenado remotamente (ex: S3 + DynamoDB para lock, ou Terraform Cloud).
- **Nunca** commitar o arquivo de estado no repositório.

## Consequências

### Positivas

- **Reprodutibilidade**: criar um ambiente idêntico ao de produção é uma questão de rodar `terraform apply`.
- **Versionamento**: mudanças na infraestrutura são revisadas via Pull Request como qualquer código.
- **Rastreabilidade**: histórico de git mostra quem mudou o quê e quando.
- **Multi-cloud e multi-ambiente**: módulos reutilizáveis entre staging e produção com variáveis diferentes.
- **Destruição controlada**: `terraform destroy` para limpar ambientes de teste.
- Terraform é agnóstico de cloud provider — reduz lock-in.

### Negativas / Trade-offs

- Curva de aprendizado: o time precisa aprender HCL (linguagem do Terraform) e os conceitos de state.
- O estado remoto é um ponto crítico — corrupção ou perda do estado pode ser catastrófico. Backups e lock são obrigatórios.
- `terraform apply` em produção é uma operação de risco e deve ter processo de validação (ex: `terraform plan` revisado antes do apply).
- Recursos criados manualmente fora do Terraform criam drift de estado — disciplina é necessária para não gerenciar infra fora do Terraform.
- Alguns recursos demoram para ser provisionados (ex: cluster Kubernetes), tornando o ciclo de feedback lento.

### Neutras / Observações

- Usar **terraform plan** em CI/CD para visibilidade de mudanças antes do apply.
- **Separar o state** por ambiente (staging e production têm states separados) para evitar que um erro em staging afete produção.
- Configuração do Kubernetes (Deployments, Services, ConfigMaps) pode ser gerenciada via **Helm** ou **Kustomize** — o Terraform provisiona o cluster, e Helm/Kustomize gerenciam o que roda dentro dele.
- Dashboards do Grafana (ADR-018) configurados via Terraform Grafana Provider para manter tudo como código.
- Relacionado: ADR-011 (Docker + Kubernetes como plataforma alvo).
