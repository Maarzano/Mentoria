# ADR-013: Idempotência via Chave do Cliente, Redis e TTL com Auditoria no PostgreSQL

**Status:** Aceito  
**Data:** 2026-03-10

---

## Contexto

Em sistemas distribuídos, requisições podem ser **retransmitidas** pelo cliente ou por mecanismos de retry (rede instável, timeout, retry automático). Sem uma estratégia de idempotência, isso pode causar:

- Pedidos duplicados criados duas vezes.
- Pagamentos processados múltiplas vezes.
- Operações com efeitos colaterais irreversíveis executadas repetidamente.

O problema é especialmente crítico em operações monetárias e de estado do pedido. A idempotência garante que executar a mesma operação múltiplas vezes produza o mesmo resultado que executá-la uma única vez.

## Decisão

Implementaremos idempotência no FoodeApp usando a seguinte estratégia:

### Fluxo:

1. **O cliente gera e envia uma chave de idempotência** (`Idempotency-Key`) no header de toda requisição que modifica estado (POST, PUT, PATCH).
2. **A API verifica no Redis** se aquela chave já foi processada nos últimos N minutos (TTL configurável, ex: 24h).
   - Se **já processada**: retorna o resultado original armazenado (sem reprocessar).
   - Se **não processada**: processa normalmente, armazena o resultado no Redis com TTL e persiste a chave no PostgreSQL para auditoria.
3. **O Redis** armazena `{idempotency_key → response_payload}` com TTL para resposta rápida.
4. **O PostgreSQL** armazena os registros de idempotência para auditoria, rastreamento e queries históricas além do TTL do Redis.

### Estrutura da chave Redis:
```
{service}:idempotency:{idempotency_key}  →  {status, response_body, processed_at}
TTL: 24h (configurável por operação)
```

### Geração da chave pelo cliente:
- Recomendado: UUID v4 gerado pelo cliente antes de enviar a requisição.
- O cliente deve reutilizar a mesma chave em caso de retry da mesma operação.
- Chaves diferentes = operações diferentes.

## Consequências

### Positivas

- Proteção total contra operações duplicadas em caso de retry (rede, timeout, falha do cliente).
- O Redis garante latência mínima na verificação de idempotência (sub-milissegundo).
- O PostgreSQL mantém auditoria durável além do TTL do Redis.
- A solução é stateless do ponto de vista das instâncias da API — qualquer instância pode verificar a chave no Redis (compartilhado via ADR-012).
- Sem necessidade de locks ou coordenação complexa entre instâncias.

### Negativas / Trade-offs

- A responsabilidade de gerar e reutilizar a `Idempotency-Key` está no **cliente** — clientes mal implementados que geram nova chave a cada retry derrotam o mecanismo.
- Adiciona uma consulta ao Redis em toda requisição de escrita (overhead mínimo mas existente).
- O TTL deve ser calibrado corretamente: muito curto → duplicatas passam após expirar; muito longo → Redis CreatorID acumula muita memória.
- Respostas padrão de erros também devem ser armazenadas como resultado idempotente (para não reprocessar e retornar erro diferente).

### Neutras / Observações

- O middleware de idempotência pode ser implementado como um **ASP.NET middleware** reutilizável, aplicado via atributo ou configuração de rota.
- A verificação de idempotência deve acontecer **antes** de qualquer lógica de negócio ou acesso ao banco.
- Relacionado: ADR-012 (Redis), ADR-016 (retry e circuit breaker no cliente), ADR-019 (UI Otimista).
- Reference: [Stripe Idempotency Keys](https://stripe.com/docs/api/idempotent_requests) como referência de implementação madura.
