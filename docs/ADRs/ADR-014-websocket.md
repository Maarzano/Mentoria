# ADR-014: WebSocket para Comunicação em Tempo Real

**Status:** Aceito  
**Data:** 2026-03-10

---

## Contexto

Algumas funcionalidades do FoodeApp requerem comunicação em tempo real — o servidor precisa **empurrar** atualizações para o cliente sem que o cliente precise fazer polling constante:

- **Status do pedido**: o consumidor precisa ver em tempo real quando o pedido muda de "Aguardando confirmação" → "Em preparo" → "Saiu para entrega" → "Entregue".
- **Chat/Conversas**: comunicação em tempo real entre consumidor e restaurante (ou suporte).
- Possíveis expansões: notificações de promoções, atualização de cardápio, etc.

As alternativas para comunicação em tempo real incluem:
- **Polling**: cliente consulta a cada N segundos. Simples, mas ineficiente e com latência.
- **Long Polling**: cliente mantém conexão aberta até o servidor responder. Melhor que polling, mas complexo.
- **Server-Sent Events (SSE)**: unidirecional (servidor → cliente). Simples, mas não suporta chat (bidirecional).
- **WebSocket**: bidirecional, eficiente, amplamente suportado.

## Decisão

Usaremos **WebSocket** via **SignalR** (.NET) para as funcionalidades de comunicação em tempo real do FoodeApp.

**Casos de uso iniciais:**
1. **Atualização de status do pedido** — o servidor envia atualizações ao cliente conforme o pedido avança.
2. **Chat em conversas** — comunicação bidirecional entre consumidor e restaurante/suporte.

**Implementação:**
- **SignalR** no backend .NET, que abstrai WebSocket (com fallback para SSE/Long Polling para clientes que não suportam WS).
- **Redis como backplane** (ADR-012): obrigatório para que mensagens sejam roteadas para o cliente correto independente de qual instância do serviço ele está conectado.
- O cliente web (React) e o app (React Native) usarão a biblioteca `@microsoft/signalr` para se conectar.
- Autenticação da conexão WebSocket via JWT no momento do handshake.

## Consequências

### Positivas

- Experiência do usuário muito superior ao polling: atualizações instantâneas, sem delay.
- Redução de carga no servidor comparado ao polling constante.
- SignalR gerencia automaticamente reconexões, heartbeats e fallbacks.
- Bidirecional: suporta tanto push do servidor quanto mensagens do cliente (necessário para chat).
- Redis backplane garante que múltiplas instâncias do serviço funcionem corretamente.

### Negativas / Trade-offs

- Conexões WebSocket são **persistentes** e consomem recursos do servidor (memória, file descriptors) — o dimensionamento de instâncias deve levar isso em conta.
- Requer que o load balancer suporte sticky sessions ou que o Redis backplane seja configurado corretamente (optamos pelo backplane para não depender de sticky sessions).
- Infraestrutura de proxies e firewalls precisam suportar WebSocket (nem todos os ambientes corporativos permitem).
- O Kong (ADR-009) precisa ser configurado para fazer proxy de conexões WebSocket corretamente.
- Maior complexidade de teste comparado a APIs REST tradicionais.

### Neutras / Observações

- Para casos onde apenas o servidor envia dados (ex: status de pedido), SSE seria suficiente e mais simples. Mas como também precisamos de chat (bidirecional), WebSocket/SignalR é a escolha correta.
- O serviço com WebSocket deve ser pensado para lidar com **reconexões** graciosamente: o cliente pode perder e reestabelecer a conexão, e precisa receber o estado atual ao reconectar.
- Atualizar o status do pedido via WebSocket **não elimina** a necessidade de o cliente poder consultar o status via REST ao abrir/reabrir o app — as duas formas devem coexistir.
- Monitorar número de conexões ativas como métrica de capacidade (ADR-018).
