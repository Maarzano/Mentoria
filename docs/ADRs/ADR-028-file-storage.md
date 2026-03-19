# ADR-028: File Storage para Imagens e Arquivos de Usuário

**Status:** Revisado  
**Data original:** 2026-03-10  
**Data da revisão:** 2026-06-01

---

## Contexto

O FoodeApp precisa armazenar arquivos binários enviados por usuários e estabelecimentos:

- Imagens de produtos/pratos
- Logotipo e capa do estabelecimento
- Foto de perfil do comprador
- Documentos de onboarding (futuro)

Arquivos binários não devem ser armazenados no PostgreSQL. É necessário object storage dedicado, integração com CDN e política de segurança para arquivos privados.

Na decisão original desta ADR, havia referência a Cloudflare R2. A implementação final da infraestrutura, no entanto, foi consolidada em Azure.

---

## Decisão

Usaremos **Azure Blob Storage** como serviço de object storage do FoodeApp.

### Decisão original vs implementação final

| Item | Decisão original | Implementação final |
|---|---|---|
| Object storage | Cloudflare R2 | Azure Blob Storage |
| Integração CDN | Cloudflare CDN | Azure Front Door Standard |
| SDK .NET | S3-compatible | Azure.Storage.Blobs |
| Provisionamento IaC | Cloudflare provider | azurerm_storage_account + containers |

### Motivos da escolha final

1. **Coerência Azure-first**: o restante da infraestrutura já está em Azure (AKS, PostgreSQL, Redis, Key Vault, ACR, Front Door).
2. **Segurança de rede**: Storage com Private Endpoint dentro da VNet, sem tráfego público direto para backend.
3. **Operação simplificada**: um único fornecedor, menor complexidade de suporte e billing.
4. **Integração com observabilidade**: uso do Blob também para retenção de logs do Loki em produção (`loki-logs`).

---

## Implementação atual

### Provisionamento

- Terraform cria `azurerm_storage_account`
- Terraform cria containers de aplicação
- Terraform cria Private Endpoint para acesso interno

### Uso por tipo de dado

| Container | Conteúdo | Acesso | Cache sugerido |
|---|---|---|---|
| `assets` | JS/CSS/estáticos do frontend | Público via Front Door | alto (immutables) |
| `uploads` | Imagens de produto, logo, capa | Público via Front Door | médio |
| `loki-logs` | Logs agregados (produção) | Privado interno | n/a |

### Fluxo de upload recomendado

1. Frontend solicita URL temporária de upload ao backend.
2. Backend gera SAS/Presigned URL para Blob.
3. Frontend envia arquivo diretamente ao Blob.
4. Backend registra metadados/URL no banco.

Essa abordagem reduz carga no backend e evita upload binário atravessando APIs de negócio.

---

## Segurança e governança

- Arquivos privados devem usar URL temporária com expiração curta.
- Nome de arquivo deve ser gerado no backend (`{uuid}.{ext}`), nunca confiar no nome original do cliente.
- Validar tipo e tamanho antes de emitir URL de upload.
- Política de remoção para dados pessoais (LGPD) deve ser implementada por job de limpeza.

---

## Consequências

### Positivas

- Melhor alinhamento com a stack atual da plataforma.
- Menor complexidade operacional e de rede.
- Integração direta com Front Door e observabilidade.
- Facilidade de operação via Terraform já existente.

### Trade-offs

- Custo de egress do Blob existe (diferente do argumento original de R2).
- Dependência maior de um único cloud vendor.

---

## Relacionamentos

- ADR-020 (Terraform / IaC)
- ADR-023 (CDN com Azure Front Door)
- ADR-018 (Observabilidade e Loki)
