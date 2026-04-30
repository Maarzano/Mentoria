# svc-catalog

Cardápios das lojas: **categorias, itens, preços, disponibilidade, fotos**.

## Stack

| Item | Escolha |
|---|---|
| Linguagem | **C# / .NET 10 (LTS)** |
| Banco | PostgreSQL — schema `catalog` |
| Cache | Redis (catálogo é read-heavy — ADR-015) |
| Mensageria | RabbitMQ via MassTransit (Outbox) |

## Responsabilidades

- Hierarquia: estabelecimento → categorias → itens (+ variações/adicionais quando vier).
- Disponibilidade do item (em estoque / esgotado / pausado pelo lojista).
- Preço base + variações.
- Snapshot de item para o `svc-orders` (preço congelado no momento do pedido).
- Read model otimizado para listagem por loja (ADR-005).

## 🗣️ Pontos para discussão

- [ ] Modelagem de **variações/adicionais** (combos, tamanhos, sabores) — JSONB ou tabelas normalizadas?
- [ ] Estratégia de **cache invalidation** quando lojista altera preço — TTL curto vs evento `ItemPriceChanged`?
- [ ] Indexação para busca textual (item por nome) — pg `tsvector` é suficiente ou eventualmente Elasticsearch?
- [ ] Versionamento de cardápio — manter histórico de preços para reconciliação financeira?
- [ ] Imagens de itens — referenciar URL do CDN (ADR-028) ou armazenar metadata local?
