# ADR-006: RabbitMQ como Fila de Mensagens entre Microserviços

**Status:** Aceito  
**Data:** 2026-03-10

---

## Contexto

Em uma arquitetura de microserviços, os serviços precisam se comunicar. A comunicação pode ser:

- **Síncrona** (REST/gRPC): o chamador aguarda a resposta. Cria acoplamento temporal.
- **Assíncrona** (filas/eventos): o produtor publica uma mensagem e não espera resposta. Maior desacoplamento.

Para operações onde um serviço não precisa da resposta imediata do outro (ex: envio de notificação após pedido confirmado, atualização de estoque, emissão de cobrança), a comunicação assíncrona via fila é a abordagem correta.

É necessário escolher uma tecnologia de mensageria que seja simples de operar, com boa maturidade, suporte a padrões como Dead Letter Queue, ACK/NACK, e que seja adequada ao volume do FoodeApp.

## Decisão

Usaremos **RabbitMQ** como broker de mensagens para a comunicação assíncrona entre microserviços.

- O padrão de publicação será via **exchanges** com routing keys bem definidas por domínio.
- Cada serviço consumidor terá sua própria **fila dedicada** com binding ao exchange relevante.
- Usaremos **Dead Letter Queues (DLQ)** para mensagens que falharam após as tentativas de retry configuradas.
- O Outbox Pattern (ADR-017) garante que mensagens só sejam publicadas após a transação de banco ser confirmada.
- Mensagens devem ser **idempotentes** pelos consumidores — o broker pode entregar a mesma mensagem mais de uma vez (at least once delivery).

## Consequências

### Positivas

- RabbitMQ é simples de instalar, configurar e entender, com excelente documentação.
- Suporte nativo a DLQ, TTL de mensagem, prioridade de filas, ACK manual — tudo que precisamos.
- Baixa latência para casos de uso do FoodeApp.
- Protocolo AMQP com clientes maduros em .NET (`MassTransit`, `RabbitMQ.Client`).
- MassTransit abstrai o RabbitMQ e facilita implementar SAGA (ADR-007), retry e circuit breaker na camada de mensageria.
- Boa integração com o padrão Outbox (ADR-017).

### Negativas / Trade-offs

- Não é a melhor escolha para casos de uso de **streaming de eventos** em alta escala (Kafka seria mais adequado nesses cenários).
- RabbitMQ não é um log de eventos persistente por padrão — mensagens consumidas são removidas da fila. Para event sourcing ou replay de eventos históricos, seria necessário persistir os eventos externamente.
- Requer atenção no gerenciamento de filas, exchanges e bindings — pode se tornar complexo com muitos serviços.
- Alta disponibilidade requer configuração de cluster (replicação de filas).

### Neutras / Observações

- Recomendamos o uso de **MassTransit** como abstração sobre o RabbitMQ no .NET, facilitando padrões como Publish/Subscribe, Request/Response, e SAGA.
- Se no futuro o volume de eventos exigir streaming em larga escala, a avaliação de Kafka deve ser feita — o MassTransit facilita essa migração ao abstrair o broker.
- Cada equipe de serviço é responsável pelo schema das mensagens que publica — versionamento de contratos de mensagem deve ser tratado com cuidado (ex: campos opcionais para retrocompatibilidade).
