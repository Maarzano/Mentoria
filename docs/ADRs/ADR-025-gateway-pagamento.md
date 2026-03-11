# ADR-025: Gateway de Pagamento — Integração e Estratégia de Cobrança

**Status:** Aceito  
**Data:** 2026-03-10

---

## Contexto

O FoodeApp precisa processar pagamentos de compradoes para os estabelecimentos. As responsabilidades envolvidas incluem:

- Processar cobranças via cartão de crédito/débito, PIX e carteiras digitais.
- Lidar com falhas de cobrança (rede, saldo insuficiente, timeout) sem criar pedidos "fantasmas".
- Garantir que o dinheiro não seja cobrado sem que o pedido exista, e vice-versa.
- Suportar estornos/reembolsos em caso de cancelamento (integração com SAGA — ADR-007).
- Cumprir requisitos de PCI-DSS: **nenhum dado de cartão pode trafegar ou ser armazenado nos servidores do FoodeApp**.

Opções avaliadas:

| Provider | PIX nativo | SDK .NET | PCI | Retenção de fundos | Observações |
|----------|------------|----------|-----|--------------------|-------------|
| **Mercado Pago** | ✅ | ✅ | SAQ A | ✅ (marketplace) | Amplamente adotado no Brasil |
| **Stripe** | ⚠️ (via API) | ✅ | SAQ A | ✅ (Connect) | Melhor DX, mas PIX ainda limitado |
| **PagSeguro** | ✅ | ⚠️ | SAQ A | ❌ | SDK mais antigo |
| **Adyen** | ✅ | ✅ | SAQ A | ✅ | Mais voltado a enterprise |

O sistema de pagamento está intimamente acoplado ao fluxo de pedidos e ao SAGA de transações distribuídas (ADR-007). Uma falha no pagamento deve disparar compensações nos demais serviços.

## Decisão

Usaremos o **Mercado Pago** como gateway de pagamento primário do FoodeApp.

### Motivos da escolha

- Melhor suporte a PIX nativo no Brasil (geração de QR Code via API simples).
- Modelo **marketplace** nativo: permite dividir o pagamento entre FoodeApp (taxa) e estabelecimento na mesma transação.
- SDK oficial para .NET bem documentado.
- Amplamente conhecido pelos estabelecimentos parceiros — facilita o onboarding.

### Formas de pagamento suportadas inicialmente

- Cartão de crédito/débito (tokenizado via SDK frontend — PCI SAQ A)
- PIX (QR Code gerado server-side, webhook de confirmação)
- Carteiras digitais (Mercado Crédito) — avaliação futura

### Modelo de integração

```
Comprador (frontend)
    │  1. Tokeniza cartão via MP SDK (browser/app)
    │     Dados sensíveis NUNCA passam pelo backend FoodeApp
    ↓
BFF → Serviço de Pedidos
    │  2. Cria pedido em estado PENDENTE
    ↓
Serviço de Pagamento
    │  3. Chama API Mercado Pago com o token + valor
    │  4. Aguarda confirmação (síncrona para cartão, webhook para PIX)
    ↓
RabbitMQ (Outbox — ADR-017)
    │  5. Publica PagamentoConfirmado / PagamentoFalhou
    ↓
SAGA Orquestrador (ADR-007)
    │  6a. Confirmado → avança fluxo do pedido
    │  6b. Falhou → cancela pedido e libera estoque
```

### Regras críticas

- O serviço de pagamento **nunca armazena dados de cartão** — apenas o token gerado pelo SDK frontend.
- Todo evento de pagamento (confirmado, falhou, estornado) é publicado via Outbox (ADR-017) para garantir consistência.
- **Timeout de cobrança**: se a resposta do gateway não chegar em 10s, o pedido vai para estado `AGUARDANDO_CONFIRMACAO` e o webhook resolverá assincronamente.
- **Idempotência com Mercado Pago**: toda requisição inclui um `X-Idempotency-Key` (mesmo padrão da ADR-013) para evitar cobrança dupla em caso de retry.
- **Reembolso automático**: acionado pelo SAGA quando o pedido é cancelado após a cobrança — a compensação chama a API de estorno do Mercado Pago.

### Estrutura dos eventos

```
PagamentoProcessado (base)
  ├── PagamentoConfirmado { pedidoId, valor, metodo, transacaoExternaId }
  ├── PagamentoFalhou    { pedidoId, motivo, tentativa }
  └── PagamentoEstornado { pedidoId, valor, motivoEstorno }
```

## Consequências

### Positivas

- PCI SAQ A: o FoodeApp nunca toca dados de cartão — escopo de compliance mínimo.
- PIX nativo simplifica muito a integração (webhook de confirmação confiável).
- Marketplace nativo: repasse automático para o estabelecimento, sem lógica financeira manual.
- Webhook oficial do Mercado Pago garante eventual consistency mesmo em falhas de rede.
- Integração via SDK oficial .NET reduz código de plumbing.

### Negativas / Trade-offs

- Dependência de provedor único — se o Mercado Pago tiver outage, pagamentos param. Mitigação: SLA do MP é alto, e o modelo de pedido `AGUARDANDO_CONFIRMACAO` absorve instabilidades curtas.
- Taxas de transação do Mercado Pago precisam ser computadas no modelo de negócio.
- Webhooks chegam assincronamente para PIX — o frontend precisa de WebSocket (ADR-014) ou polling para exibir confirmação em tempo real.
- Estornos pelo Mercado Pago têm janelas de tempo e regras específicas que o SAGA precisa respeitar.

### Neutras / Observações

- O serviço de Pagamento deve ser isolado em seu próprio schema do PostgreSQL (ADR-002) — nunca acessar dados de pedidos diretamente.
- O `transacaoExternaId` do Mercado Pago deve ser armazenado no banco para rastreamento e suporte.
- Futuramente, uma camada de abstração de gateway permite adicionar Stripe ou outros providers sem alterar o domínio de Pagamento — não implementar essa abstração agora (YAGNI), mas o contrato de eventos deve permanecer estável.
- Logs de todas as chamadas ao gateway devem ser auditáveis (ADR-018), mas **sem logar dados sensíveis** (nunca logar token de cartão, CVV ou dados pessoais de pagamento).
