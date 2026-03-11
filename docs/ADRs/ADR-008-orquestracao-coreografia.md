# ADR-008: Orquestração vs Coreografia por Contexto e Complexidade

**Status:** Aceito  
**Data:** 2026-03-10

---

## Contexto

Em arquiteturas orientadas a eventos com microserviços, existem duas abordagens para coordenar a comunicação entre serviços:

**Coreografia (Choreography):**
- Cada serviço reage a eventos publicados por outros serviços.
- Não há um coordenador central — o fluxo emerge das reações em cadeia.
- Mais desacoplado, mas pode ser difícil de rastrear e entender o fluxo completo.

**Orquestração (Orchestration):**
- Um coordenador central (orquestrador / SAGA state machine) dirige o fluxo, chamando cada serviço na sequência correta.
- O fluxo é explícito e visível em um único lugar.
- Mais fácil de entender, monitorar e compensar em caso de falha.
- Cria um ponto central de controle (mas não um ponto único de falha se bem implementado).

Não há uma resposta única para qual abordagem usar — a escolha depende da complexidade do fluxo e do nível de acoplamento aceitável.

## Decisão

Usaremos **ambas as abordagens**, escolhendo a mais adequada por contexto:

| Critério | Usar Orquestração | Usar Coreografia |
|---------|------------------|-----------------|
| Complexidade | Fluxos com múltiplos passos, compensações e branching | Fluxos simples, reações diretas a eventos |
| Rastreabilidade | Quando é crítico saber o estado do fluxo | Quando o rastreamento pode ser feito com logs/tracing |
| Acoplamento | Aceitável ter um orquestrador que conhece os serviços | Serviços não devem conhecer uns aos outros |
| Domínio | Processos de negócio internos complexos | Integrações com sistemas externos ou notificações |

**Exemplos concretos:**
- **Orquestração** → Fluxo completo de um pedido: pagamento → confirmação → preparo → entrega. Usa SAGA com state machine (ADR-007).
- **Coreografia** → Envio de e-mail/notificação push quando um pedido é confirmado. O serviço de notificações reage ao evento `PedidoConfirmado` sem que ninguém precise "chamar" ele.

## Consequências

### Positivas

- Cada abordagem é usada onde tem mais vantagem, evitando a adoção dogmática de uma só.
- Fluxos complexos ficam explícitos e monitoráveis via orquestração.
- Integrações simples e reativas ficam desacopladas via coreografia.
- Facilita a adição de novos consumidores de eventos sem alterar o produtor (coreografia).

### Negativas / Trade-offs

- O time precisa ter clareza sobre **quando usar cada abordagem** — sem isso, pode haver inconsistência nas decisões.
- Fluxos coreografados são mais difíceis de entender end-to-end: o "fluxo completo" só existe nos logs e tracing distribuído (ADR-018).
- Orquestradores criam um componente adicional que precisa ser mantido e monitorado.

### Neutras / Observações

- A regra de bolso: **se você precisa compensar** em caso de erro → orquestração. **Se é uma reação simples** a um evento → coreografia.
- Documentar explicitamente os fluxos orquestrados em diagramas de sequence ajuda muito o onboarding de novos membros.
- O distributed tracing (ADR-018) é essencial para dar visibilidade aos fluxos coreografados, que de outra forma são "invisíveis".
