# ADR-016: Resiliência com Retry, Circuit Breaker e Fallback (Exponential Backoff + Jitter)

**Status:** Aceito  
**Data:** 2026-03-10

---

## Contexto

Em sistemas distribuídos, falhas transitórias são inevitáveis: timeouts de rede, instâncias sobrecarregadas, deploys em andamento, etc. Sem mecanismos de resiliência, uma falha transitória de um serviço pode se propagar em cascata e derrubar serviços que dependem dele.

Os principais padrões de resiliência para comunicação entre serviços são:
- **Retry**: tentar novamente após uma falha transitória.
- **Circuit Breaker**: parar de fazer requisições a um serviço com falha, dando tempo para ele se recuperar.
- **Fallback**: retornar um valor degradado/padrão quando o serviço dependente não está disponível.
- **Timeout**: não esperar indefinidamente por uma resposta.
- **Bulkhead**: isolar falhas para que não consumam todos os recursos do sistema.

## Decisão

Cada camada de comunicação entre serviços implementará resiliência com os seguintes padrões, usando a biblioteca **Polly** no .NET:

### Políticas por tipo de comunicação:

| Comunicação | Retry | Circuit Breaker | Fallback | Timeout |
|------------|-------|----------------|---------|---------|
| HTTP entre BFF → Microserviço | ✅ | ✅ | ✅ (quando possível) | ✅ |
| HTTP entre Microserviços | ✅ | ✅ | ✅ (quando possível) | ✅ |
| Consumo de fila (RabbitMQ) | ✅ | ❌ (gerenciado pelo broker) | ✅ | ✅ |
| Acesso ao Redis | ✅ (1-2 tentativas) | ✅ | ✅ (degradar para sem cache) | ✅ |
| Acesso ao PostgreSQL | ✅ (1-2 tentativas) | ❌ | ❌ | ✅ |

### Configuração de Retry — Exponential Backoff com Jitter:

```
Tentativa 1: espera base^1 + jitter_aleatório  (ex: ~1s)
Tentativa 2: espera base^2 + jitter_aleatório  (ex: ~2-4s)
Tentativa 3: espera base^3 + jitter_aleatório  (ex: ~4-8s)
Máximo: configurável por contexto (ex: 3 tentativas para APIs, 5 para filas)
```

O **jitter** (valor aleatório adicionado ao tempo de espera) é fundamental para evitar o **thundering herd problem**: sem jitter, todas as instâncias que falharam ao mesmo tempo fariam retry simultaneamente, sobrecarregando o serviço que estava se recuperando.

### Circuit Breaker:
- **Fechado (normal)**: requisições passam normalmente.
- **Aberto (falha)**: após N falhas consecutivas, o circuito abre. Requisições são rejeitadas imediatamente (rápido fail) por um período de cooldown.
- **Semi-aberto (teste)**: após o cooldown, permite uma requisição de teste. Se bem-sucedida, fecha o circuito. Se falhar, reabre.

## Consequências

### Positivas

- Falhas transitórias são absorvidas automaticamente pelo retry — o usuário não percebe.
- O Circuit Breaker impede que um serviço com falha sobrecarregue ainda mais o sistema com requisições que vão falhar de qualquer forma.
- O jitter distribui os retries no tempo, evitando picos de carga ao se recuperar de uma falha.
- O fallback permite degradação graciosa: o sistema continua funcionando (possivelmente com funcionalidade reduzida) em vez de falhar completamente.
- Polly é amplamente adotado no ecossistema .NET, com integração nativa ao `HttpClientFactory`.

### Negativas / Trade-offs

- Retry em operações **não idempotentes** pode causar duplicações — por isso o ADR-013 (idempotência) é complementar e necessário.
- Configuração inadequada (retries demais, janela do circuit breaker muito longa) pode piorar o problema ao invés de ajudar.
- Adiciona complexidade ao código e mais um ponto de configuração a gerenciar.
- O tempo total de uma requisição com retry pode ser longo — os timeouts dos clientes precisam ser dimensionados adequadamente.

### Neutras / Observações

- **Retry só deve ser aplicado a falhas transitórias** (timeouts, 503, 429). Erros de negócio (400, 404, 422) **não devem** ser retentados.
- A política de resiliência deve ser configurada centralmente (via `HttpClientFactory` + Polly extension methods) para garantir consistência e evitar que cada serviço implemente de forma diferente.
- Os eventos do Circuit Breaker (abriu, fechou, semi-aberto) devem ser logados e monitorados (ADR-018) para visibilidade operacional.
- Relacionado: ADR-013 (idempotência para segurança no retry), ADR-018 (observabilidade para monitorar falhas e circuit breakers).
