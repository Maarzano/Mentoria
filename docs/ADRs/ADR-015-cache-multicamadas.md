# ADR-015: Estratégia de Cache em Múltiplas Camadas com Invalidação Criteriosa

**Status:** Aceito  
**Data:** 2026-03-10

---

## Contexto

Cache é uma das ferramentas mais poderosas para reduzir latência e carga no banco de dados. Entretanto, sem uma estratégia clara, o cache pode se tornar um problema: dados desatualizados chegando ao usuário, cache gigantesco e difícil de gerenciar, invalidação incorreta causando inconsistências, ou paradoxalmente, cache que nunca é utilizado.

O FoodeApp precisa de uma estratégia de cache que equilibre performance com consistência de dados, definindo claramente:
- **O que** deve ser cacheado.
- **Onde** o cache vive (em qual camada).
- **Por quanto tempo** (TTL).
- **Como** é invalidado quando os dados mudam.

## Decisão

Adotaremos **cache em múltiplas camadas**, com critérios claros para cada camada:

### Camadas de Cache

| Camada | Onde | O que cachear | TTL sugerido | Invalidação |
|--------|------|--------------|-------------|-------------|
| **L1 — In-Process** | Memória do processo (.NET `IMemoryCache`) | Dados de configuração, listas de referência estáticas (ex: tipos de culinária, faixas de preço) | Minutos a horas | Expiração por tempo ou restart do pod |
| **L2 — Redis Distribuído** | Redis (ADR-012) | Resultados de queries caros, listagens de cardápio, dados do perfil do usuário, resultados de aggregações do BFF | Segundos a minutos | Expiração por tempo + invalidação por evento |
| **L3 — HTTP Cache** | Kong / Headers HTTP | Respostas de APIs públicas estáticas (ex: cardápio público de um restaurante) | Segundos | Cache-Control headers, ETag |

### Critérios para decidir o que cachear

Cachear quando pelo menos 2 critérios forem atendidos:
- ✅ **Volume de leitura alto**: dado acessado frequentemente.
- ✅ **Custo de geração alto**: query cara, join pesado, cálculo demorado.
- ✅ **Taxa de mudança baixa**: dado não muda a cada segundo.
- ✅ **Tolerância a stale data**: pequeno atraso de atualização é aceitável para aquele contexto.

**Não cachear:**
- Dados de estado de pedido em andamento (precisam ser sempre frescos).
- Dados de pagamento e transações financeiras.
- Dados personalizados em alta frequência de mudança.

### Estratégias de Invalidação

- **TTL-based**: expiração automática por tempo. Simples e sempre válida como base.
- **Invalidação por evento**: ao processar um Command que altera um dado, publicar um evento que invalida as chaves Redis correspondentes. Ex: ao atualizar o cardápio, invalidar `menu:cache:restaurant:{id}`.
- **Cache-aside** (Lazy Loading): o app consulta o cache, se miss, busca no banco, armazena no cache e retorna. É o padrão dominante.

## Consequências

### Positivas

- Redução significativa de latência para dados frequentemente lidos.
- Redução de carga no PostgreSQL.
- Layers separadas permitem otimização independente por tipo de dado.
- TTL como mecanismo base garante que o cache eventualmente se torna consistente mesmo sem invalidação explícita.

### Negativas / Trade-offs

- Complexidade adicional: o time precisa entender a estratégia e aplicá-la corretamente.
- **Stale data**: janela de inconsistência entre o cache e o banco. Deve ser tolerada conscientemente.
- **Cache invalidation** é um dos problemas mais difíceis em computação — uma invalidação errada cause dados desatualizados; uma invalidação muito agressiva anularia os benefícios do cache.
- Cache L1 (in-process) é **por instância**: cada pod tem seu próprio cache L1, podendo ter dados diferentes entre pods. Para dados críticos, usar apenas L2 (Redis).
- **Cache stampede**: muitas requisições simultâneas num cache miss podem sobrecarregar o banco. Mitigar com locks de cache ou probabilistic early expiration.

### Neutras / Observações

- O cache **não é a solução para queries lentas** — queries lentas devem ser otimizadas com índices e modelo de dados corretos primeiro. Cache vem depois.
- Documentar explicitamente para cada endpoint/query se há cache, qual a TTL e a estratégia de invalidação. Deixar isso implícito cria bugs difíceis de debugar.
- Métricas de **cache hit rate** devem ser monitoradas (ADR-018) — hit rate abaixo de 70-80% indica problema na estratégia.
- Relacionado: ADR-012 (Redis), ADR-005 (tabelas de leitura desnormalizadas como "cache no banco").
