# ADR-028: File Storage para Imagens e Arquivos de Usuário

**Status:** Aceito  
**Data:** 2026-03-10

---

## Contexto

O FoodeApp precisa armazenar arquivos binários enviados por usuários e estabelecimentos:

- **Imagens de produtos/pratos**: foto de cada item do cardápio.
- **Logotipo e foto de capa do estabelecimento**: exibidas na listagem e na página do restaurante.
- **Foto de perfil do comprador**: opcional.
- **Comprovantes/documentos**: CNPJ, alvará — necessários no onboarding do estabelecimento (futuro).

Arquivos binários não devem ser armazenados no PostgreSQL (performance, custo, complexidade de backup). É necessário um serviço de object storage separado.

Os diagramas arquiteturais mencionam **Azure Blob Storage** como opção, mas o restante da infra não está comprometido com Azure especificamente. A CDN já está definida como Cloudflare (ADR-023) — pontos de serviço de storage devem considerar a integração com essa camada.

Opções avaliadas:

| Opção | Custo | Integração CDN | SDK .NET | Observações |
|-------|-------|---------------|---------|-------------|
| **Cloudflare R2** | Muito baixo (sem egress fee) | Nativa com Cloudflare CDN | S3-compatible | Sem custo de saída de dados |
| **AWS S3** | Baixo | Via CloudFront ou Cloudflare | ✅ | Egress fee pode escalar |
| **Azure Blob Storage** | Baixo | Via CDN Azure ou Cloudflare | ✅ | Mencionado nos diagramas C4 iniciais |
| **MinIO (self-hosted)** | Hosting próprio | Via Cloudflare | S3-compatible | Mais operação, menos custo |

## Decisão

Usaremos **Cloudflare R2** como serviço de object storage para todos os arquivos de usuário do FoodeApp.

### Motivos da escolha

- **Zero egress fees**: Cloudflare R2 não cobra pela saída de dados — custo relevante quando imagens são servidas frequentemente.
- **Integração nativa com Cloudflare CDN** (ADR-023): arquivos no R2 podem ser servidos diretamente pelo CDN do Cloudflare sem configuração adicional de origin. Evita um hop desnecessário.
- **API S3-compatible**: o SDK .NET da AWS (`AWSSDK.S3`) funciona com R2 apenas alterando o endpoint — sem lock-in de SDK.
- **Terraform provider** disponível (ADR-020): `cloudflare_r2_bucket` — infra como código consistente com o restante.
- Já usamos Cloudflare para CDN e WAF (ADR-023) — consolida vendors e simplifica faturamento.

### Organização dos buckets

| Bucket | Conteúdo | Acesso | Cache |
|--------|---------|--------|-------|
| `foodeapp-products` | Fotos de pratos e cardápio | Público (via CDN) | `max-age=86400` |
| `foodeapp-merchants` | Logo e capa de estabelecimentos | Público (via CDN) | `max-age=86400` |
| `foodeapp-users` | Fotos de perfil | Público (via CDN) | `max-age=3600` |
| `foodeapp-documents` | CNPJ, alvará, documentos de onboarding | **Privado** (signed URL, TTL 15min) | Sem cache |

### Fluxo de upload (imagens públicas)

```
Frontend (React/React Native)
    │  1. POST /api/uploads/presigned-url
    │     → Serviço de Mídia solicita Presigned URL ao R2
    │     → Retorna URL temporária de upload (validade: 5 min)
    ↓
Frontend
    │  2. PUT diretamente no R2 via Presigned URL (bypass do backend)
    │     → Arquivo vai diretamente do browser/app para o R2
    ↓
Frontend
    │  3. POST /api/produtos/{id}/imagem com a URL final do arquivo
    │     → Backend registra a URL no PostgreSQL
```

**Por que Presigned URL?** O arquivo nunca passa pelo backend do FoodeApp — reduz latência, elimina carga no servidor e simplifica a infraestrutura (sem streaming de multipart no .NET).

### Processamento de imagens

- Após o upload, um worker assíncrono (consumidor de fila — ADR-006) redimensiona a imagem para os tamanhos padrão:
  - `thumbnail`: 150×150 (listagens)
  - `card`: 400×300 (card do produto)
  - `full`: 800×600 (detalhe do produto)
- Resultado: 3 URLs armazenadas no banco por imagem. O frontend escolhe o tamanho adequado.
- Worker usa **SixLabors.ImageSharp** (.NET) para redimensionamento.

### Nomes de arquivo e segurança

- Nome do arquivo sempre gerado pelo backend: `{uuid}.{ext}` — nunca o nome original do usuário.
- Validação de Content-Type no backend antes de emitir a Presigned URL: apenas `image/jpeg`, `image/png`, `image/webp` aceitos.
- Tamanho máximo: 10 MB por arquivo (validado na Presigned URL com content-length-range).
- Documentos privados usam Presigned URL de download com TTL de 15 minutos — nunca URLs permanentes.

## Consequências

### Positivas

- Cloudflare R2 + CDN: imagens servidas globalmente sem custo de egress — modelo de custo previsível.
- Presigned URL descarrega completamente os uploads do backend FoodeApp.
- API S3-compatible permite migrar para S3/MinIO com mudança mínima de configuração.
- Redimensionamento assíncrono não bloqueia a resposta ao usuário — UI Otimista (ADR-019) pode exibir preview antes do processamento terminar.
- Buckets separados por categoria facilitam políticas de retenção e backup diferenciadas.

### Negativas / Trade-offs

- Cloudflare R2 é relativamente recente comparado ao S3 — menos SLAs históricos publicados, mas tem crescido em estabilidade.
- O worker de processamento de imagens é mais um componente para manter e escalar.
- Presigned URL expira — o frontend deve solicitar nova URL se o upload demorar mais que 5 minutos (raro, mas precisa de tratamento de erro).
- Documentos privados com signed URL precisam de lógica de expiração bem testada — URL expirada deve retornar 403, não 404.

### Neutras / Observações

- O schema de mídia (`media_item`) fica no schema do Serviço de Mídia — armazena `{ id, bucket, key, sizes: { thumbnail, card, full }, uploaded_at, uploaded_by }`.
- **LGPD**: foto de perfil do usuário deve ser deletável mediante solicitação — implementar soft-delete + job de limpeza no R2.
- Futuramente: **Cloudflare Images** pode substituir a lógica manual de redimensionamento — o Cloudflare faz on-the-fly resize via URL parameter (`?w=400&h=300`). Não implementar agora para evitar lock-in prematuro, mas a URL pattern dos arquivos deve ser compatível.
- Custo atual estimado R2: $0.015/GB/mês de storage + $0.36/1M operações de classe A. Para um catálogo inicial de alguns milhares de pratos, custo é desprezível.
