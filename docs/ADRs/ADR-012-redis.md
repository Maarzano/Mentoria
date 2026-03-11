# ADR-012: Redis para Cache, Estado Compartilhado e Backplane

**Status:** Aceito  
**Data:** 2026-03-10

---

## Contexto

Em um sistema distribuído com múltiplas instâncias de cada serviço rodando no Kubernetes, surgem necessidades que não podem ser resolvidas com memória local do processo:

1. **Cache compartilhado entre instâncias**: um resultado cacheado por uma instância deve ser visível para todas as outras.
2. **Estado efêmero compartilhado**: ex: chaves de idempotência (ADR-013), sessões, locks distribuídos.
3. **Backplane para SignalR/WebSocket** (ADR-014): para que mensagens de WebSocket possam ser roteadas entre instâncias diferentes.
4. **Cache de alta velocidade**: acesso em microsegundos, estruturas de dados ricas (hashes, lists, sorted sets, sets).

## Decisão

Usaremos **Redis** como solução central para:

| Uso | Detalhes |
|-----|---------|
| **Cache distribuído** | Cache de resultados de queries, respostas de APIs externas, e dados calculados caros. TTL configurado por tipo de dado. |
| **Idempotência** | Armazenar chaves de idempotência com TTL para detectar requisições duplicadas (ADR-013). |
| **Backplane de SignalR** | Permitir que mensagens WebSocket sejam roteadas entre múltiplas instâncias do serviço que usa SignalR (ADR-014). |
| **Rate limiting** | Contadores de rate limit compartilhados entre instâncias (integrado ao Kong ou implementado no middleware .NET). |
| **Sessões e tokens temporários** | Armazenamento de tokens de refresh, códigos de verificação com expiração, etc. |
| **Locks distribuídos** | Via Redlock ou primitivas nativas do Redis para coordenação entre instâncias. |

O Redis será configurado em modo **cluster ou Sentinel** para alta disponibilidade em produção.

## Consequências

### Positivas

- Latência de acesso extremamente baixa (sub-milissegundo em operações simples).
- Resolve naturalmente o problema de estado compartilhado entre instâncias sem necessidade de sticky sessions.
- Estruturas de dados ricas (sorted sets para leaderboards/filas de prioridade, hashes para objetos, pub/sub para eventos internos).
- TTL nativo simplifica a gestão do ciclo de vida do cache e das chaves de idempotência.
- Amplamente suportado como serviço gerenciado (AWS ElastiCache, Azure Cache for Redis, etc.).
- Integração nativa com .NET via `StackExchange.Redis` e `IDistributedCache`.

### Negativas / Trade-offs

- Redis é **in-memory**: dados podem ser perdidos em caso de falha se a persistência não estiver configurada. Para dados críticos (não cache), usar RDB + AOF.
- Mais um componente de infraestrutura para operar e monitorar.
- Custo adicional de cloud para instâncias Redis gerenciadas com alta disponibilidade.
- Dados no Redis **não são transacionais** com o PostgreSQL — cuidado com inconsistências entre cache e banco.
- Tamanho da memória limita o volume de dados cacheados — não é adequado como banco de dados principal.

### Neutras / Observações

- **Não usar Redis como banco de dados primário** — apenas como cache, estado efêmero e coordenação.
- A estratégia completa de cache (incluindo invalidação e organização por camadas) está em ADR-015.
- Configurar **maxmemory-policy** adequadamente (ex: `allkeys-lru`) para evitar erros quando a memória encher.
- Separar namespaces por serviço nas chaves Redis para evitar colisões (ex: `orders:idempotency:`, `menu:cache:`, etc.).
- Monitoramento de Redis deve incluir: hit rate, uso de memória, latência e conexões (ADR-018).
