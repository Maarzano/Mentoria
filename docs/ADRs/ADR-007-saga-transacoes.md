# ADR-007: Padrão SAGA para Transações Distribuídas

**Status:** Aceito  
**Data:** 2026-03-10

---

## Contexto

Em uma arquitetura de microserviços, transações que envolvem múltiplos serviços não podem ser gerenciadas com uma transação de banco de dados ACID tradicional. Por exemplo, ao criar um pedido no FoodeApp, o fluxo pode envolver:

1. Criar o pedido (serviço de pedidos)
2. Debitar o saldo ou processar pagamento (serviço de pagamentos)
3. Reduzir estoque do item (serviço de cardápio/estoque)
4. Notificar o restaurante (serviço de notificações)

Se qualquer etapa falhar após etapas anteriores já terem sucesso, é necessário **desfazer** o que foi feito — o que em sistemas distribuídos exige **transações compensatórias**.

O padrão **SAGA** resolve isso definindo uma sequência de transações locais, onde cada etapa publica um evento e, em caso de falha, transações compensatórias são disparadas para reverter o estado.

## Decisão

Usaremos o **padrão SAGA** para gerenciar transações distribuídas no FoodeApp.

A implementação será feita com **MassTransit** (sobre RabbitMQ — ADR-006), que oferece suporte nativo a SAGAs com state machine.

A escolha entre **orquestração** e **coreografia** dentro do SAGA depende da complexidade do fluxo (ver ADR-008). De forma geral:
- **Orquestração** para SAGAs complexas (ex: fluxo completo de um pedido).
- **Coreografia** para SAGAs mais simples envolvendo reações a eventos externos.

Cada transação compensatória deve ser **idempotente**.

### Exemplo: SAGA de Pedido (Orquestrada)

```
[CreateOrder] → [ProcessPayment]
                    ↓ (falha)
              [RefundPayment.Compensate]  ← [CancelOrder.Compensate]
```

## Consequências

### Positivas

- Permite manter consistência eventual entre serviços sem locks distribuídos.
- Falhas em etapas intermediárias são tratadas de forma explícita e rastreável.
- O estado da SAGA é persistido, permitindo auditoria e replay em caso de erro.
- MassTransit oferece uma DSL clara para definir a state machine da SAGA.
- Cada etapa continua sendo uma transação local simples e atômica.

### Negativas / Trade-offs

- SAGAs são **mais difíceis de entender e debugar** do que transações ACID tradicionais.
- O sistema fica em **estado inconsistente temporariamente** entre os passos — isso é inerente à consistência eventual.
- Cada etapa precisa ter uma **transação compensatória** bem definida e testada.
- A lógica de compensação pode ser complexa (ex: se o pagamento foi parcialmente processado).
- Dados lidos durante a SAGA podem estar desatualizados (leituras "sujas" entre os passos).

### Neutras / Observações

- SAGAs **não substituem** transações ACID — dentro de um único serviço, continuamos usando transações de banco normais.
- O estado da SAGA deve ser armazenado de forma durável (banco de dados ou Redis com persistência) para sobreviver a reinicializações dos serviços.
- Monitorar o estado de SAGAs em andamento é essencial — dashboards de observabilidade (ADR-018) devem incluir visibilidade sobre SAGAs pendentes e com falha.
- Relacionado: ADR-008 (orquestração vs coreografia), ADR-006 (RabbitMQ), ADR-013 (idempotência).
