# svc-auth

Vertical slice minimo do servico de perfis pos-Keycloak.

## Responsabilidade

Este servico nao autentica usuarios.
Ele apenas persiste e consulta dados de perfil de aplicacao vinculados ao Keycloak.

## Endpoints

- `GET /healthz`
- `GET /ready`
- `GET /metrics`
- `POST /profiles`
- `GET /profiles/{id}`

## Subir local (um comando)

Da raiz do repositorio:

```powershell
.\infra\scripts\local-up.ps1
```

## Exemplos de requisicao

Criar perfil:

```powershell
$body = @{
  keycloakId  = "kc-user-123"
  displayName = "Maria Silva"
  role        = "comprador"
  avatarUrl   = "https://cdn.example.com/avatar/maria.png"
  phone       = "+55 11 99999-8888"
} | ConvertTo-Json

Invoke-RestMethod -Method Post -Uri "http://localhost:8080/profiles" -ContentType "application/json" -Body $body
```

Buscar perfil:

```powershell
Invoke-RestMethod -Method Get -Uri "http://localhost:8080/profiles/PUT-GUID-HERE"
```

## Regras de validacao

- `role` deve ser `comprador` ou `lojista`
- retorna `201` em criacao
- retorna `400` em payload invalido
- retorna `404` quando perfil nao existe
