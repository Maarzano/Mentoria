# Configuração — FoodeApp

> **Princípio**: Zero Hardcode, Fallback Claro.

## Fonte Única: `.env`

Tudo (portas, hosts, credenciais) vem do arquivo `.env` na raiz do projeto.

| Cenário | Quem lê `.env` | Como |
|---|---|---|
| `proj.ps1 run/infra` | PowerShell `Import-DotEnv` | Sempre sobrescreve `$env:*` |
| `dotnet run` (sem proj.ps1) | Kernel via `dotenv.net` | `builder.AddFoodeAppEnv()` sobe o diretório até achar `.env` |
| Container Docker | `proj.ps1 run -c` | `Build-ContainerEnvArgs` injeta `-e KEY=VAL` |
| K8s | ConfigMap + Secret | Overlay define host/port, Secret define password |

## Fallback

```
.env  →  $env:*  →  IOptions<T>
                         ↑
              appsettings.json (só valores intrínsecos: Database.Database, Observability.ServiceName)
```

- **Portas**: `.env` primeiro → `services.json` como fallback (via `Get-ServicePort`)  
- **Segredos** (`POSTGRES_PASSWORD`): obrigatórios — se ausentes, `Assert-RequiredEnvVars` falha com erro claro  
- **Settings classes** (Kernel): zero defaults operacionais (`string.Empty` / `0`)  
- **appsettings.json**: só valores que são intrínsecos ao serviço (nome do DB, ServiceName)

## Convenção de Nomes

| .env | Env var no pod (K8s) | IOptions<T> |
|---|---|---|
| `POSTGRES_HOST` | `Database__Host` | `DatabaseSettings.Host` |
| `POSTGRES_PORT` | `Database__Port` | `DatabaseSettings.Port` |
| `POSTGRES_USER` | `Database__Username` | `DatabaseSettings.Username` |
| `POSTGRES_PASSWORD` | `Database__Password` | `DatabaseSettings.Password` |
| `POSTGRES_DB_AUTH` | `Database__Database` | `DatabaseSettings.Database` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `OTEL_EXPORTER_OTLP_ENDPOINT` | `ObservabilitySettings.OtlpEndpoint` |

## Tradução Local → Container

`Build-ContainerEnvArgs` (proj.ps1) traduz automaticamente:
- `localhost` → nome do serviço Docker Compose (ex: `postgres`, `otel-collector`)
- Porta do host → porta interna do container

## Dockerfile

Sem `EXPOSE`, sem `ENV ASPNETCORE_URLS` hardcoded.  
Porta é injetada via `-e ASPNETCORE_URLS=http://0.0.0.0:<port>` em runtime.

## Checklist: novo serviço

1. Registrar em `infra/local/services.json` com porta e campo `database`
2. Adicionar variáveis de porta e DB no `.env` / `.env.example`
3. No `Program.cs`: `builder.AddFoodeAppEnv()` como primeira linha
4. `appsettings.json`: só `Database.Database` + `Observability.ServiceName`
5. K8s base: usar `Database__*` com `$(POSTGRES_*)` expansion
6. Overlays: garantir `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_USER` no ConfigMap
