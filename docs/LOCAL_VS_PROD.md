# 📦 Local vs Produção — Mentoria SvcAuth

Você tem um setup **idêntico** ao de produção em termos de código e comportamento. Mas diferenças na infra existem. Este documento mapeia a correspondência.

---

## 🔄 Mapeamento: Local Docker-Compose → Kubernetes Production

### 🔧 Core Application

| Local | Produção | Notas |
|-------|----------|-------|
| `mentoria-svc-auth:8080` (docker) | `svc-auth:8080` (K8s Pod) | Mesma imagem, mesmo código |
| `.NET 10 aspnet:latest` | `.NET 10 aspnet:latest` | Versão idêntica |
| `Program.cs + OTel SDK` | `Program.cs + OTel SDK` | Instrumentation idêntica |
| `ASPNETCORE_ENVIRONMENT=Development` | `ASPNETCORE_ENVIRONMENT=Production` | Só o env muda (logs mais esparsos em prod) |
| PostgreSQL `postgres:16-alpine` | PostgreSQL `postgres:16-alpine` (RDS/AKS DB) | Mesmo schema |
| `ConnectionStrings__Default` via env | `ConnectionStrings__Default` via K8s Secret | Credenciais via vault em prod |

### 🔍 Observabilidade — **IDÊNTICA**

| Componente | Local | Produção | Fluxo |
|------------|-------|----------|-------|
| **OTel Collector** | `otel/opentelemetry-collector-contrib:0.119.0` | Sidecar/DaemonSet | Recebe OTLP de svc-auth |
| **Prometheus** | `prom/prometheus:v3.1.0` | Prometheus Operator | Scrapa métricas (8889 OTel + 8080 svc-auth) |
| **Tempo** | `grafana/tempo:2.7.1` | Tempo cluster | Armazena traces (recebe OTLP) |
| **Loki** | `grafana/loki:2.9.7` | Loki cluster | Armazena logs (via Promtail) |
| **Promtail** | `grafana/promtail:3.0.0` | DaemonSet + Sidecar | Coleta logs de containers |
| **Grafana** | `grafana/grafana:11.4.0` | Grafana cluster | UI unificada (Datasources: Prometheus, Tempo, Loki) |

### 📡 Networking & Service Discovery

| Local | Produção |
|-------|----------|
| `localhost:8080` (direkto) | `http://svc-auth.default.svc.cluster.local:8080` (K8s DNS) |
| `postgres` (docker DNS) | `postgres-auth.default.svc.cluster.local` (K8s internal DNS) |
| `otel-collector:4318` | `otel-collector.default.svc.cluster.local:4318` |
| Port forwarding manual (`localhost:3000`) | Ingress ou NodePort para Grafana (`grafana.mentoria.io`) |

### 💾 Storage & Persistence

| Local | Produção | Implicações |
|-------|----------|------------|
| Docker volumes (`/tmp/tempo`, `/tmp/loki`) | PersistentVolumes (EBS/AzureDisk) | Local: perde tudo se reset; Prod: durável |
| Single instance | 3+ replicas (High Availability) | Local: 1 Prometheus = coleta centralizada; Prod: distribuído |
| No backup | Automated snapshots + retention | - |

### 🔐 Secrets & Configuration

| Local | Produção |
|-------|----------|
| `ConnectionStrings__Default` hardcoded em `docker-compose.yml` | `azure:///foodeapp_postgres_auth` via Azure KeyVault (ou Vault) |
| `ASPNETCORE_ENVIRONMENT=Development` em compose | ConfigMap + Sealed Secrets |
| Sem encryption | Encryption at rest + TLS in-transit |

### 🚀 Escalabilidade & Resiliência

| Local | Produção |
|-------|----------|
| 1 svc-auth replica | 3+ replicas (auto-scale via KEDA) |
| 1 PostgreSQL instance | RDS Multi-AZ ou Patroni HA |
| Restart policy: unless-stopped | K8s liveness/readiness probes + pod disruption budgets |
| Manual failover | Circuit breakers + retry policies + service mesh (Istio) |
| No load balancing | Load balancer (ALB/NGINX ingress controller) |

---

## ✅ O QUE É 100% IDÊNTICO entre Local e Prod

```
✅ Código da aplicação (.NET)
✅ OTel instrumentation (spans, metrics, logs)
✅ PostgreSQL schema e queries
✅ HTTP API contract (/v1/profiles)
✅ Observabilidade stack (Prom + Tempo + Loki + Grafana)
✅ Docker images e versions
✅ Dependências NuGet
```

---

## ⚠️ O QUE DIFERENCIA Local de Prod

```
❌ Número de replicas (1 local vs 3+ prod)
❌ Storage durabilidade (volumes efêmeros vs PV)
❌ Secrets management (env var vs Vault)
❌ Networking (localhost vs K8s DNS)
❌ Resiliência (restart policy vs probes + HPA)
❌ Latência (0ms localhost vs real network)
❌ Database (SQLite dev vs PostgreSQL prod)
```

---

## 📊 Conclusão: Vale a pena rodar local?

**SIM, 100%** — Por quê:

1. **Desenvolvimento** — Você valida o código e observabilidade sem deploy
2. **Debugging** — Logs em tempo real, traces locais, fácil reproduzir bugs
3. **Testing** — Testa integração svc-auth ↔ PostgreSQL ↔ OTel antes de mergear
4. **Documentação executável** — Qualquer dev novo consegue `./local-up.ps1` e estar rodando em 2 minutos

**Diferenças que você YA precisa lidar em Prod (não em local)**:

1. Kubernetes manifests (Deployment, Service, ConfigMap, Secret)
2. Helm charts ou Kustomize para parametrização
3. CI/CD pipelines (GitHub Actions ou Azure Pipelines)
4. Infrastructure-as-Code (Terraform)
5. Network policies, RBAC, Pod Security Policies
6. Monitoring de SLOs (P99 latency, error rate, availability)

---

## 🔗 Como Usar Local Efetivamente

### Iniciar a stack
```powershell
cd c:\Repo\Mentoria\Mentoria
.\infra\scripts\local-up.ps1
.\infra\scripts\local-status.ps1
```

### Ver logs em tempo real
```powershell
docker logs -f foodeapp-svc-auth
docker logs -f foodeapp-loki
docker logs -f foodeapp-prometheus
```

### Testar API
```powershell
# Criar usuário
$body = @{ keycloakId = "test-001"; displayName = "João"; role = "comprador" } | ConvertTo-Json
Invoke-RestMethod -Method POST -Uri 'http://localhost:8080/v1/profiles' `
  -ContentType 'application/json' -Body $body

# Buscar usuário
Invoke-RestMethod 'http://localhost:8080/v1/profiles/<GUID>'
```

### Validar observabilidade
- **Metrics**: http://localhost:9090 (Prometheus)
- **Traces**: http://localhost:3000 → Explore → Tempo
- **Logs**: http://localhost:3000 → Explore → Loki
- **API health**: http://localhost:8080/healthz

---

## 🎯 Resumo

| Aspecto | Local | Produção |
|---------|-------|----------|
| **Representatividade** | 70-80% (comportamento funcional) | Versão completa com HA |
| **Usabilidade para dev** | Excelente (rápido, fácil debugar) | Complexa (muitas variáveis) |
| **Custo** | Grátis (seu laptop) | ~$500-1000/mês (AKS + Grafana Cloud) |
| **Escalabilidade** | N/A | Automática (KEDA) |
| **Confiabilidade** | OK para testes | 99.9% SLA |

**Conclusão**: Local é seu **sandbox de desenvolvimento produção-like**. Daqui, você vai para Staging (idêntico a Prod menos dados) e depois Prod.
