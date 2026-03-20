# 🛠️ Modo Desenvolvimento Local — Setup Completo no VS Code

Você quer **máxima visibilidade** com cada componente em seu próprio terminal, logs em tempo real, e a aplicação rodando nativamente (não em container) com hot-reload.

Esta é a arquitetura de desenvolvimento recomendada para Mentoria SvcAuth:

---

## 📋 Arquitetura

```
┌─────────────────────────────────────────────────────┐
│  VS CODE - Terminal 1: Infraestrutura (Docker)      │
│  - PostgreSQL 16                                     │
│  - OTel Collector                                    │
│  - Prometheus                                        │
│  - Tempo                                             │
│  - Loki                                              │
│  - Promtail                                          │
│  - Grafana                                           │
└─────────────────────────────────────────────────────┘
                          ↓
                   localhost networking
                          ↓
┌─────────────────────────────────────────────────────┐
│  VS CODE - Terminal 2: Aplicação (dotnet run)       │
│  - svc-auth (watch mode, hot-reload)                │
│  - Logs em tempo real                               │
│  - Debugger pronto (F5 para step)                    │
│  - http://localhost:8080                            │
└─────────────────────────────────────────────────────┘
                          ↓
                      (logs/traces)
                          ↓
┌─────────────────────────────────────────────────────┐
│  Browser: Grafana (http://localhost:3000)           │
│  - Explore → Prometheus (métricas)                  │
│  - Explore → Tempo (traces)                         │
│  - Explore → Loki (logs)                            │
└─────────────────────────────────────────────────────┘
```

---

## 🚀 Setup Passo a Passo

### Passo 1: Abra 2 terminais no VS Code

**Terminal 1: Abra no diretório raiz (`Mentoria/`)**
```powershell
# Terminal 1 — Infra
cd c:\Repo\Mentoria\Mentoria
.\infra\scripts\local-dev-infra-start.ps1
```

**Terminal 2: Abra no diretório da app**
```powershell
# Terminal 2 — App
cd c:\Repo\Mentoria\Mentoria\services\svc-auth
.\..\..\infra\scripts\local-dev-app-run.ps1
```

Ou use **Tasks do VS Code** (mais simples):

### Alternativa: Rodar via VS Code Tasks

Pressione `Ctrl+Shift+B` (Run Build Task) e selecione:
1. **"📦 Infra: Start (Docker)"** (primeiro terminal)
2. **"🚀 App: svc-auth (watch mode)"** (segundo terminal)

---

## 📊 Validação — Como Confirmar que Está Funcionando

### 1. **Checklist de Infraestrutura (Terminal 1)**

Você verá algo assim:
```
╔════════════════════════════════════════════════════════════════╗
║  Infraestrutura Local (Docker)                                ║
║  Serviços: PostgreSQL, OTel, Prometheus, Tempo, Loki, Grafana ║
╚════════════════════════════════════════════════════════════════╝

🧹 Limpando containers antigos...
📦 Subindo infraestrutura...
⏳ Aguardando PostgreSQL ficar healthy...
   ✅ PostgreSQL healthy (8 segundos)

╔════════════════════════════════════════════════════════════════╗
║  ✅ Infraestrutura Online                                      ║
╚════════════════════════════════════════════════════════════════╝

📍 Endereços:
   🗄️  PostgreSQL:      localhost:5432
   📊 Prometheus:      http://localhost:9090
   📈 Grafana:         http://localhost:3000
   🔍 Tempo:           http://localhost:3200
   📝 Loki:            http://localhost:3100
   🔄 OTel Collector:  http://localhost:13133
```

### 2. **Checklist de Aplicação (Terminal 2)**

Você verá algo assim:
```
╔════════════════════════════════════════════════════════════════╗
║  🚀 svc-auth — Modo Desenvolvimento (dotnet run)               ║
║  Hot Reload Habilitado • Logs em tempo real                   ║
╚════════════════════════════════════════════════════════════════╝

⚙️  Ambiente: Development
📍 Endpoint: http://localhost:8080
📚 Swagger:  http://localhost:8080/swagger

▶️  Iniciando aplicação...

info: Microsoft.Hosting.Lifetime[14]
      Now listening on: http://localhost:8080
info: Microsoft.Hosting.Lifetime[0]
      Application started. Press Ctrl+C to stop, or press Ctrl+B then Enter to restart from the terminal...
```

### 3. **Teste a API (em um terceiro terminal)**

```powershell
# Criar usuário
$body = @{ keycloakId = "test-001"; displayName = "João"; role = "comprador" } | ConvertTo-Json
$resp = Invoke-RestMethod -Method POST -Uri 'http://localhost:8080/v1/profiles' `
  -ContentType 'application/json' -Body $body
Write-Host "✅ Usuário criado: $($resp.id)" -ForegroundColor Green

# Buscar usuário
Invoke-RestMethod "http://localhost:8080/v1/profiles/$($resp.id)"

# Ver Swagger
# No browser: http://localhost:8080/swagger
```

### 4. **Acompanhe Logs em Tempo Real**

**Terminal 1** mostra:
```
docker logs -f foodeapp-svc-auth  # se estivesse containerizado
```

**Terminal 2** mostra tudo direto (dotnet watch):
```
info: FoodeApp.SvcAuth.Adapters.API.Endpoints.ProfileEndpoints[0]
      Creating profile for keycloakId: test-001
info: FoodeApp.SvcAuth.Adapters.API.Endpoints.ProfileEndpoints[0]
      Profile created with ID: c52ee69f-487e-4a76-932f-69d9f43a7f51
```

### 5. **Visualize Observabilidade no Grafana**

Abra http://localhost:3000 (sem login):

**Métricas (Prometheus):**
- Explore → Datasource: Prometheus
- Query: `http_requests_received_total`
- Você verá os requests da app

**Traces (Tempo):**
- Explore → Datasource: Tempo
- Search → Service: svc-auth
- Clique em qualquer trace para ver o waterfall HTTP + SQL

**Logs (Loki):**
- Explore → Datasource: Loki
- Query: `{service="svc-auth"}`
- Você verá logs JSON da app

---

## 🔥 Hot-Reload & Debugging

### Modificar Código e Recarregar Automaticamente

1. Abra `services/svc-auth/src/FoodeApp.SvcAuth.Adapters.API/Program.cs`
2. Faça qualquer mudança (ex: adicione uma log)
3. **Salve com Ctrl+S**
4. Terminal 2 automaticamente recompila e reinicia
5. Próximo request já usa o código novo

### Adicionar Breakpoints

1. No VS Code, clique na gutter (esquerda do número de linha) para adicionar breakpoint
2. Pressione **F5** para entrar em debug mode
3. Rode uma requisição (POST /v1/profiles)
4. A execução pausará no breakpoint
5. Inspect variáveis, step through, etc.

**Nota**: `dotnet watch run` é melhor para hot-reload; `F5 debug` é melhor para breakpoints. Se você quer ambos:
- Use Terminal 2 para hot-reload (`dotnet watch run`)
- Quando precisar debugar, use um debug session separado (F5)

---

## 🛑 Parar Tudo (Cleanup)

### Opção 1: Via Terminal
```powershell
# Terminal 1: Ctrl+C para parar a infra
docker compose down

# Terminal 2: Ctrl+C para parar a app
```

### Opção 2: Via VS Code Task
`Ctrl+Shift+B` → `"🧹 Cleanup: Stop all (Docker)"`

---

## 📁 Estrutura de Terminais Recomendada

```
┌─ VS Code Main Window
│
├─ TERMINAL 1: "Infra"
│  ├─ Mostra logs do Docker Compose
│  ├─ PostgreSQL inicializando ✅
│  ├─ OTel Collector online ✅
│  ├─ Prometheus scraping ✅
│  ├─ Grafana pronto 🎯
│  └─ Não feche (infra fica rodando)
│
├─ TERMINAL 2: "svc-auth"
│  ├─ Mostra logs da aplicação
│  ├─ Hot-reload watch ativo
│  ├─ "Now listening on: http://localhost:8080"
│  └─ Modifique código e salve = auto-reload
│
└─ TERMINAL 3: "Tasks" (opcional)
   ├─ Para rodar testes pontuais
   ├─ Build sem rodar
   └─ Um-off operations
```

---

## ⚡ Comandos Úteis Rápidos

### Rodar Testes
```powershell
# Terminal 3
cd services/svc-auth
dotnet test FoodeApp.SvcAuth.sln
```

### Apenas Build (sem rodar)
```powershell
# Terminal 3
cd services/svc-auth
dotnet build src/FoodeApp.SvcAuth.Adapters.API/FoodeApp.SvcAuth.Adapters.API.csproj
```

### Ver Logs do PostgreSQL
```powershell
# Terminal 3
docker logs -f foodeapp-postgres-auth
```

### Ver Logs do Prometheus
```powershell
# Terminal 3
docker logs -f foodeapp-prometheus
```

### Acessar Terminal do PostgreSQL
```powershell
# Terminal 3
docker exec -it foodeapp-postgres-auth psql -U pgadmin -d foodeapp_auth

# Dentro do psql:
# \dt  — ver tabelas
# SELECT * FROM auth.users LIMIT 5;
```

---

## 🎯 Comparação: Docker Compose vs. Local Dev

| Aspecto | `docker compose up -d` | Local Dev (CLI) |
|---------|------------------------|-----------------|
| **Visibilidade** | ❌ Black box | ✅ Todos os logs em tempo real |
| **Terminais** | 1 container aggregado | 2+ terminais separados |
| **Hot-reload** | ❌ Rebuild necessário | ✅ Automático (Ctrl+S) |
| **Debugger** | ❌ Difícil (attach) | ✅ F5 nativo |
| **Editar código** | ❌ No container | ✅ IDE local |
| **Complexidade** | ✅ Simples | ⚠️ 2 terminals |
| **Representativo** | ✅ Produção-like | ⚠️ Dev-only (sem docker da app) |

---

## 🚨 Troubleshooting

### "App não consegue conectar no PostgreSQL"
```
Error: Host=localhost — Connection refused
```
**Solução**: Certifique-se de que Terminal 1 exibe "✅ PostgreSQL healthy"

### "OTel Collector não conecta"
```
Error: OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318 — refused
```
**Solução**: Terminal 1 deve exibir "foodeapp-otel-collector Created"

### "Porta 8080 já em uso"
```
Error EADDRINUSE: address already in use :::8080
```
**Solução**:
```powershell
# Encontrar processo usando porta 8080
netstat -ano | findstr :8080
# Kill o processo
taskkill /PID <PID> /F
```

### "Hot-reload não dispara"
**Solução**: Certifique-se de estar usando `dotnet watch run`, não `dotnet run`

---

## 🎬 Atalhos Rápidos

| Ação | Comando |
|------|---------|
| **Iniciar tudo** | Terminal 1: `.\infra\scripts\local-dev-infra-start.ps1` + Terminal 2: `.\infra\scripts\local-dev-app-run.ps1` |
| **Debug com F5** | Apenas quando quiser breakpoints |
| **Hot-reload** | Salve arquivo em Terminal 2 vê auto-reload |
| **Ver metrics** | http://localhost:8080/metrics (Prometheus format) |
| **Ver traces** | http://localhost:3000 → Explore → Tempo → Service: svc-auth |
| **Parar tudo** | Terminal 1: `Ctrl+C` → `docker compose down` |

---

## ✅ Próximos Passos

Depois de tudo online:

1. **Crie usuário de teste**: Veja a requisição HTTP em Swagger
2. **Monitore em Grafana**: Abra http://localhost:3000, navegue para traces
3. **Modifique código**: Edite `ProfileEndpoints.cs`, salve, veja hot-reload
4. **Debugue**: F5 em `Program.cs`, adicione breakpoint, ride requisição

---

## 📞 Suporte Rápido

Perdido? Rode:
```powershell
# Diagnóstico completo
.\infra\scripts\local-status.ps1
```

Isso valida todos os endpoints de saúde.
