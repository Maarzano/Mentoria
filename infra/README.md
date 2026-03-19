# FoodeApp — Infrastructure

Infraestrutura completa do FoodeApp no Azure, gerenciada com Terraform e Kubernetes.

## Estrutura

```text
infra/
├── terraform/
│   ├── bootstrap/          ← Roda UMA vez: cria o backend do Terraform state
│   ├── modules/
│   │   ├── networking/     ← VNet, subnets, NSGs, private DNS zones
│   │   ├── acr/            ← Azure Container Registry
│   │   ├── keyvault/       ← Azure Key Vault + secrets
│   │   ├── database/       ← PostgreSQL Flexible Server + 8 databases + PostGIS
│   │   ├── redis/          ← Azure Cache for Redis
│   │   ├── storage/        ← Blob Storage (4 containers)
│   │   ├── aks/            ← AKS cluster (4 node pools: system, services, infra, monitor)
│   │   └── cdn/            ← Azure Front Door Standard + WAF
│   └── envs/
│       ├── staging/        ← Staging: menor custo, sem HA
│       └── production/     ← Produção: HA, SKUs maiores, WAF Prevention
└── k8s/
    ├── base/
    │   ├── namespaces/     ← Namespaces do cluster
    │   ├── istio/          ← IstioOperator, mTLS STRICT, AuthorizationPolicies
    │   ├── kong/           ← Kong Helm values + plugins (rate-limit, CORS, JWT)
    │   ├── keycloak/       ← Keycloak Helm values
    │   ├── rabbitmq/       ← RabbitMQ Helm values + definitions.json
    │   └── observability/  ← Prometheus, Loki, Tempo, OTel Collector
    └── overlays/
        ├── staging/        ← Kustomize patches para staging
        └── production/     ← Kustomize patches para produção
```

---

## Pré-requisitos

```bash
# Ferramentas necessárias
az --version          # Azure CLI 2.55+
terraform --version   # Terraform 1.7+
kubectl --version     # kubectl 1.28+
helm version          # Helm 3.12+
istioctl version      # Istio 1.20+
```

Login no Azure:

```bash
az login
az account set --subscription "<SEU_SUBSCRIPTION_ID>"
```

---

## PASSO 1 — Bootstrap (executa apenas uma vez)

Cria o Storage Account para guardar o Terraform state remotamente.

```bash
cd infra/terraform/bootstrap
terraform init
terraform apply
# Anote os outputs: storage_account_name, container_name
```

Atualize o bloco `backend "azurerm"` nos arquivos:

- `infra/terraform/envs/staging/main.tf`
- `infra/terraform/envs/production/main.tf`

com os valores retornados.

---

## PASSO 2 — Provisionar Staging

```bash
cd infra/terraform/envs/staging

# Configurar secrets como variáveis de ambiente (nunca commitar)
export TF_VAR_postgres_admin_password="SuaSenhaSuperSegura123!"

terraform init
terraform plan -out=plan.tfplan
terraform apply plan.tfplan
```

Após o apply, anote os outputs:

- `acr_login_server` — URL do registry para push de imagens
- `aks_kubelet_identity_object_id` — para o 2º apply abaixo
- `get_kubeconfig_command` — comando para baixar kubeconfig
- `postgres_fqdn` — FQDN do PostgreSQL para o Keycloak
- `frontdoor_hostname` — URL do Azure Front Door

### 2º Apply (após pegar o kubelet_identity_object_id)

```bash
# Adicione no terraform.tfvars o valor obtido do output acima:
# aks_kubelet_identity_object_id = "<valor>"
terraform apply
```

---

## Node Pools do AKS

| Pool | Taint | Workloads | Staging | Production |
| ---- | ----- | --------- | ------- | ---------- |
| `system` | `only_critical_addons` | coreDNS, kube-proxy | D2s\_v3 × 2 (fixo) | D4s\_v3 × 3 (fixo) |
| `services` | nenhum (destino padrão) | Microserviços + BFFs | D4s\_v3, 2→6 | D8s\_v3, 3→20 |
| `infra` | `workload=infra:NoSchedule` | Kong, Keycloak, RabbitMQ, Flagsmith | D2s\_v3, 2→3 | D4s\_v3, 2→4 |
| `monitor` | `workload=monitor:NoSchedule` | Prometheus, Loki, Tempo, Grafana, OTel | D4s\_v3, 1→2 | E4s\_v3, 2→4 |

Os pools `infra` e `monitor` têm taint `NoSchedule` — apenas Helm charts com a `toleration` correta são agendados neles (já configurado nos `values.yaml` de cada componente).

---

## PASSO 3 — Configurar kubectl

```bash
az aks get-credentials \
  --resource-group rg-foodeapp-staging \
  --name aks-foodeapp-staging \
  --overwrite-existing

kubectl get nodes
```

---

## PASSO 4 — Instalar Istio

```bash
# Instalar istioctl
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.20.0 sh -
export PATH=$PWD/istio-1.20.0/bin:$PATH

# Instalar no cluster
istioctl install -f infra/k8s/base/istio/istio-operator.yaml

# Verificar
kubectl get pods -n istio-system

# Aplicar políticas de segurança
kubectl apply -f infra/k8s/base/namespaces/namespaces.yaml
kubectl apply -f infra/k8s/base/istio/peer-authentication.yaml
kubectl apply -f infra/k8s/base/istio/authorization-policies.yaml
```

---

## PASSO 5 — Instalar Kong

```bash
helm repo add kong https://charts.konghq.com
helm repo update

helm install kong kong/kong \
  --namespace foodeapp-system \
  --create-namespace \
  --values infra/k8s/base/kong/values.yaml

# Aguardar Kong ficar pronto
kubectl wait --for=condition=ready pod -l app=kong -n foodeapp-system --timeout=120s

# Aplicar plugins
kubectl apply -f infra/k8s/base/kong/plugins.yaml

# Obter IP externo do Kong
kubectl get svc -n foodeapp-system kong-kong-proxy
# → Copiar o EXTERNAL-IP e atualizar var kong_ingress_ip no terraform.tfvars
# → Depois: terraform apply (para atualizar o Azure Front Door)
```

---

## PASSO 6 — Instalar Keycloak

```bash
# Criar Secret com senha do admin
kubectl create secret generic keycloak-admin-secret \
  --from-literal=admin-password="SuaSenhaKeycloak123!" \
  --namespace foodeapp-system

# Criar Secret com senha do banco
kubectl create secret generic keycloak-db-secret \
  --from-literal=db-password="$TF_VAR_postgres_admin_password" \
  --namespace foodeapp-system

# Instalar Keycloak
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Atualizar o externalDatabase.host no values.yaml com o FQDN do PostgreSQL:
# (valor do output postgres_fqdn)

helm install keycloak bitnami/keycloak \
  --namespace foodeapp-system \
  --values infra/k8s/base/keycloak/values.yaml

kubectl get pods -n foodeapp-system -l app.kubernetes.io/name=keycloak
```

---

## PASSO 7 — Instalar RabbitMQ

```bash
# Criar secrets
kubectl create secret generic rabbitmq-secret \
  --from-literal=rabbitmq-password="SuaSenhaRabbitMQ123!" \
  --namespace foodeapp-system

kubectl create secret generic rabbitmq-definitions \
  --from-file=load_definition.json=infra/k8s/base/rabbitmq/definitions.json \
  --namespace foodeapp-system

helm install rabbitmq bitnami/rabbitmq \
  --namespace foodeapp-system \
  --values infra/k8s/base/rabbitmq/values.yaml

kubectl get pods -n foodeapp-system -l app.kubernetes.io/name=rabbitmq
```

---

## PASSO 8 — Instalar Stack de Observabilidade

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

# kube-prometheus-stack (Prometheus + Alertmanager + Grafana)
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --values infra/k8s/base/observability/kube-prometheus-stack-values.yaml

# Loki
helm install loki grafana/loki \
  --namespace monitoring \
  --values infra/k8s/base/observability/loki-values.yaml

# Tempo
helm install tempo grafana/tempo \
  --namespace monitoring \
  --values infra/k8s/base/observability/tempo-values.yaml

# OpenTelemetry Collector
helm install opentelemetry-collector open-telemetry/opentelemetry-collector \
  --namespace monitoring \
  --values infra/k8s/base/observability/otel-collector-values.yaml

# Verificar
kubectl get pods -n monitoring
```

Acessar Grafana localmente:

```bash
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring
# Acessar: http://localhost:3000 (admin / CHANGE-ME-VIA-SECRET)
```

---

## PASSO 9 — Provisionar Produção

```bash
cd infra/terraform/envs/production

export TF_VAR_postgres_admin_password="SuaSenhaProdSuperSegura456!"

terraform init
terraform plan -out=plan.tfplan
# Revisar o plan cuidadosamente antes de aplicar
terraform apply plan.tfplan
```

> ⚠️ Produção tem `purge_protection_enabled = true` no Key Vault.  
> Destruir o Key Vault de produção requer 90 dias de espera.

---

## Variáveis de Ambiente Necessárias (nunca commitar)

| Variável | Descrição |
| -------- | --------- |
| `TF_VAR_postgres_admin_password` | Senha do admin do PostgreSQL |
| `TF_VAR_cicd_service_principal_object_id` | Object ID do SP do GitHub Actions |
| `AZURE_CLIENT_ID` | Client ID para autenticação Azure CLI/Terraform |
| `AZURE_SUBSCRIPTION_ID` | ID da subscription Azure |
| `AZURE_TENANT_ID` | Tenant ID do Azure AD |

---

## Recursos Azure Provisionados

### Staging

| Recurso | SKU / Configuração | Custo estimado/mês |
| ------- | ------------------ | ------------------ |
| AKS pool `system` | D2s\_v3 × 2 (fixo) | ~R$ 300 |
| AKS pool `services` | D4s\_v3 × 2 (min) | ~R$ 600 |
| AKS pool `infra` | D2s\_v3 × 2 (min) | ~R$ 300 |
| AKS pool `monitor` | D4s\_v3 × 1 (min) | ~R$ 300 |
| PostgreSQL Flexible | B\_Standard\_B2ms | ~R$ 200 |
| Redis Cache | Standard C1 | ~R$ 150 |
| Azure Front Door | Standard | ~R$ 100 |
| Blob Storage (LRS) | Standard | ~R$ 20 |
| Container Registry | Standard | ~R$ 50 |
| **Total estimado (mínimo)** | 7 nós no total | **~R$ 2.020/mês** |

### Production

| Recurso | SKU / Configuração | Custo estimado/mês |
| ------- | ------------------ | ------------------ |
| AKS pool `system` | D4s\_v3 × 3 (fixo) | ~R$ 900 |
| AKS pool `services` | D8s\_v3 × 3 (min) | ~R$ 2.700 |
| AKS pool `infra` | D4s\_v3 × 2 (min) | ~R$ 600 |
| AKS pool `monitor` | E4s\_v3 × 2 (min) | ~R$ 800 |
| PostgreSQL Flexible HA | GP\_Standard\_D4s\_v3 | ~R$ 1.200 |
| Redis Cache | Premium P1 | ~R$ 600 |
| Azure Front Door + WAF | Standard | ~R$ 300 |
| Blob Storage (ZRS) | Standard | ~R$ 60 |
| **Total estimado (mínimo)** | 10 nós no total | **~R$ 7.160/mês** |

> Valores em BRL aproximados. Custos reais variam com tráfego e uso.
> Autoscale pode elevar o custo: staging chega a 14 nós, production a 31 nós no pico.

---

## Próximos Passos

- [ ] Registrar domínio `foodeapp.com.br` e configurar DNS no Azure
- [ ] Configurar Custom Domain no Azure Front Door + certificado SSL gerenciado
- [ ] Criar Realm `foodeapp` no Keycloak via Terraform (provider Keycloak)
- [ ] Configurar GitHub Actions CI/CD com `kubeconfig` como secret
- [ ] Adicionar PostGIS ao database `foodeapp_locations`:

  ```sql
  CREATE EXTENSION postgis;
  CREATE EXTENSION postgis_topology;
  ```

- [ ] Criar Service Principal para GitHub Actions:

  ```bash
  az ad sp create-for-rbac --name "sp-foodeapp-cicd" \
    --role contributor \
    --scopes /subscriptions/<SUBSCRIPTION_ID>/resourceGroups/rg-foodeapp-staging
  ```
