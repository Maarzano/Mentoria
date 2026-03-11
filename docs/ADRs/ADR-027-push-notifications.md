# ADR-027: Push Notifications e Canal de Notificações por Tipo

**Status:** Aceito  
**Data:** 2026-03-10

---

## Contexto

O FoodeApp precisa notificar usuários sobre eventos do sistema fora do contexto de uma sessão ativa no app ou no browser. Os canais identificados nos diagramas são:

- **Push Notification** (mobile): notificação na barra de status do celular, mesmo com o app fechado.
- **WhatsApp/SMS** (via Twilio): para usuários que não têm o app instalado ou para mensagens críticas de alta prioridade.
- **E-mail**: confirmações, recibos, notificações administrativas.
- **WebSocket/SignalR** (in-app): já coberto pela ADR-014 — para usuários com o app aberto.

O Serviço de Notificações precisa:
1. Receber eventos de outros microserviços via RabbitMQ (coreografia — ADR-008).
2. Decidir qual canal usar baseado no tipo de notificação, preferências do usuário e disponibilidade de canal.
3. Não criar acoplamento entre os produtores de eventos e os canais de entrega.

## Decisão

O Serviço de Notificações será responsável por **toda a entrega de notificações** do FoodeApp, integrando os seguintes providers por canal:

### Mapa de canais e providers

| Canal | Provider | Quando usar |
|-------|----------|-------------|
| **Push (Android)** | Firebase Cloud Messaging (FCM) | App instalado, usuário com notificações ativas |
| **Push (iOS)** | APNs (via FCM — Firebase abstrai APNs) | App instalado, usuário com notificações ativas no iOS |
| **WhatsApp** | Twilio (WhatsApp Business API) | Usuário sem app, notificações críticas, opt-in explícito |
| **E-mail** | Resend (ou SendGrid como fallback) | Confirmações, recibos, senhas, notificações admin |
| **In-app (real-time)** | SignalR/WebSocket — ADR-014 | App aberto pelo usuário (não responsabilidade deste serviço) |

### Hierarquia de canal (fallback chain)

```
Evento gerado (ex: PedidoConfirmado)
    │
    ▼
Serviço de Notificações
    │  1. Tenta Push (FCM) — se usuário tem token registrado e notificações ativas
    │  2. Se sem token FCM → tenta WhatsApp (se opt-in ativo)
    │  3. E-mail enviado SEMPRE para eventos críticos (independente de canal primário)
```

### Tipos de notificação e canais obrigatórios

| Evento | Push | WhatsApp | E-mail |
|--------|------|----------|--------|
| Pedido confirmado | ✅ | ✅ (opt-in) | ✅ |
| Saiu para entrega | ✅ | ✅ (opt-in) | ❌ |
| Pedido entregue | ✅ | ❌ | ✅ (recibo) |
| Pedido cancelado | ✅ | ✅ (opt-in) | ✅ |
| Pagamento recusado | ✅ | ❌ | ✅ |
| Promoção / marketing | ✅ (opt-in) | ❌ | ✅ (opt-in) |
| Novo pedido (estabelecimento) | ✅ | ✅ (obrigatório) | ❌ |

### Fluxo de integração

```
Produtor (ex: Serviço de Pedidos)
    │  Publica → PedidoConfirmado (RabbitMQ via Outbox)
    ↓
Serviço de Notificações (consumidor — coreografia)
    │  Consome o evento
    │  Lê preferências do usuário (canal preferido, token FCM, opt-ins)
    │  Monta payload da notificação (template por tipo de evento)
    │  Tenta entrega por ordem de prioridade
    ↓
FCM / Twilio / Resend (provider externo)
    │  Confirma recebimento ou retorna erro
    ↓
Dead Letter Queue (se falha após retries — ADR-006)
```

### Registro do token FCM

- O app (React Native) registra o token FCM no login e ao abrir o app.
- O token é enviado para o Serviço de Notificações via API autenticada e armazenado no schema de notifications.
- Token FCM é por dispositivo — um usuário pode ter múltiplos tokens (vários dispositivos).
- Tokens inválidos (retornados pelo FCM como `UNREGISTERED`) devem ser removidos automaticamente.

## Consequências

### Positivas

- FCM abstrai Android e iOS num único SDK — um único provider para Push nos dois sistemas operacionais.
- Resend tem excelente deliverability e API simples para e-mail transacional.
- Twilio WhatsApp tem alta taxa de abertura comparado a e-mail — ótimo para notificações críticas do estabelecimento.
- O Serviço de Notificações é completamente desacoplado dos produtores de eventos — nenhum serviço de negócio sabe qual canal foi usado.
- Templates centralizados de mensagem — mudança de texto não requer deploy dos serviços de negócio.

### Negativas / Trade-offs

- FCM tem limites de quota e pode ter latência variável — não é adequado para comunicação crítica de segurança (usar e-mail/SMS para isso).
- WhatsApp Business API via Twilio requer aprovação do template de mensagem pelo Meta — tempo de aprovação pode atrasar features.
- Custo por mensagem WhatsApp e SMS pode escalar com volume — monitorar com atenção (ADR-018).
- Tokens FCM expiram e ficam inválidos — lógica de invalidação e limpeza é obrigatória para não acumular tokens mortos.
- E-mail transacional tem risco de cair em spam — requer configuração de SPF, DKIM e DMARC no domínio.

### Neutras / Observações

- O schema de preferências de notificação (`notification_preferences`) fica no schema do Serviço de Notificações — nunca no schema de usuários.
- O serviço **não deve** fazer chamadas síncronas diretas para os providers durante o processamento de um pedido — tudo via consumo de filas para não bloquear o fluxo principal.
- Futuramente: OneSignal pode ser avaliado como abstração de push se a complexidade de gerenciar FCM diretamente aumentar.
- Métricas a monitorar (ADR-018): taxa de entrega por canal, taxa de clique em push, tokens inválidos por dia, latência de entrega pós-evento.
- **LGPD**: o usuário deve poder desativar cada canal individualmente. O opt-out deve ser respeitado imediatamente — nunca enviar após opt-out.
