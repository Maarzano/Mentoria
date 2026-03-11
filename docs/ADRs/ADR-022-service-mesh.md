# ADR-022: Service Mesh para Comunicação Interna entre Microserviços

**Status:** Aceito  
**Data:** 2026-03-10

---

## Contexto

Com vários microserviços se comunicando entre si dentro do cluster Kubernetes, surgem necessidades transversais que, sem uma solução centralizada, cada serviço precisaria implementar individualmente:

- **mTLS (mutual TLS)**: criptografia e autenticação mútua em toda comunicação interna — garantir que serviço A só fala com serviço B se ambos forem quem dizem ser.
- **Observabilidade de rede interna**: métricas de latência, error rate e throughput de cada chamada serviço → serviço, sem instrumentar o código de cada serviço.
- **Gerenciamento de tráfego**: retry na camada de rede, circuit breaking, timeouts e traffic shifting (ex: canary deployments) de forma centralizada.
- **Service discovery**: localizar instâncias saudáveis de um serviço dinamicamente.

Sem um service mesh, cada serviço implementaria resiliência (Polly — ADR-016), TLS e observabilidade de forma individual e inconsistente. O service mesh resolve isso na **camada de infraestrutura** (sidecar proxy), sem alterar o código de negócio.

Ao mesmo tempo, ficou claro que a comunicação interna entre microserviços **não deve passar pelo API Gateway (Kong — ADR-009)**, que existe exclusivamente para tráfego externo. Comunicação interna síncrona ocorre diretamente entre serviços pela rede interna do cluster.

## Decisão

Adotaremos um **service mesh** para gerenciar toda a comunicação síncrona interna entre microserviços no cluster Kubernetes.

A ferramenta escolhida é o **Istio**, pelo conjunto de funcionalidades e pela maturidade no ecossistema Kubernetes.

### O que o Istio gerencia:

| Funcionalidade | Como o Istio resolve |
|---------------|---------------------|
| **mTLS automático** | Sidecar Envoy injeta e valida certificados automaticamente em toda comunicação interna. Zero mudança de código. |
| **Observabilidade** | Métricas de latência, taxa de erro e throughput entre cada par de serviços automaticamente exportadas para Prometheus (ADR-018). |
| **Retry e timeout** | Configurados declarativamente via `VirtualService` — sem precisar de Polly para falhas de rede entre serviços. |
| **Circuit breaking** | Via `DestinationRule` — o Istio abre o circuito na camada de proxy se o serviço destino estiver degradado. |
| **Traffic shifting** | Canary deployments e blue/green via split de tráfego no `VirtualService`, sem alterar os serviços. |
| **Service discovery** | Integrado nativamente ao Kubernetes — o sidecar sabe quais pods de cada serviço estão saudáveis. |

### Topologia de comunicação:

```
                ┌─────────────────────────────────┐
   Externo      │         Cluster Kubernetes        │
                │                                  │
 Cliente ──→ Kong ──→ BFF Web                      │
                │       │  (mTLS via Istio mesh)   │
                │       ├──→ Service A              │
                │       │       └──→ Service B      │
                │       └──→ Service C              │
                │                                  │
                └─────────────────────────────────┘

Kong: tráfego externo → interno
Istio: tráfego interno → interno (síncrono direto entre serviços)
RabbitMQ: tráfego assíncrono entre serviços (fila — ADR-006)
```

### Quando usar síncrono (Istio/HTTP) vs assíncrono (RabbitMQ):

| Usar HTTP síncrono (via Istio) | Usar fila (RabbitMQ) |
|-------------------------------|---------------------|
| O resultado é necessário para continuar o fluxo | O produtor não precisa da resposta imediata |
| Validação em tempo real (ex: verificar se restaurante existe antes de criar pedido) | Notificações, emails, atualizações de estado derivadas |
| Consultas entre serviços (ex: enriquecer dados de leitura) | Fluxos de SAGA entre serviços |
| Latência baixa é crítica para a operação | Desacoplamento e resiliência são prioridade |

## Consequências

### Positivas

- **Zero mudança de código** para ganhar mTLS, observabilidade e resiliência de rede — tudo acontece no sidecar Envoy.
- Segurança por padrão: toda comunicação interna é criptografada e autenticada automaticamente.
- Observabilidade granular da rede interna sem instrumentação manual — complementa o OTel (ADR-018).
- Retry e circuit breaking na camada de rede são complementares (não substitutos) ao Polly (ADR-016): o Istio cobre falhas de rede; o Polly cobre falhas de negócio e lógica de aplicação.
- Canary deployments são triviais via configuração declarativa, sem alterar Deployments do Kubernetes.
- Policies de segurança (`AuthorizationPolicy`) permitem controlar quais serviços podem falar com quais — princípio do menor privilégio na rede interna.

### Negativas / Trade-offs

- **Complexidade operacional alta**: o Istio é um dos componentes mais complexos do ecossistema Kubernetes. A curva de aprendizado é significativa.
- **Overhead de recursos**: cada pod ganha um sidecar Envoy. Em clusters grandes, isso representa consumo extra de CPU e memória por pod.
- **Latência adicional**: o hop pelo sidecar adiciona microssegundos em cada chamada — geralmente imperceptível, mas mensurável.
- Debugging de problemas de rede pode ser mais difícil com o Istio no meio (é necessário entender os logs do Envoy, não só os da aplicação).
- Atualizações do Istio são operações de risco que exigem planejamento.

### Neutras / Observações

- **Alternativas avaliadas:**
  - **Linkerd**: mais simples e leve, mas com menos funcionalidades (sem traffic shifting avançado, menor ecossistema).
  - **Consul Connect**: boa opção se o time já usa Consul para service discovery, mas adiciona outra ferramenta ao stack.
  - Istio foi escolhido pela maturidade, ampla adoção e integração com a stack de observabilidade já definida (ADR-018).
- O Istio **não substitui** o Polly (ADR-016) — os dois coexistem. O Istio atua na camada de rede (infraestrutura); o Polly atua na camada de aplicação (lógica de retry de negócio, fallbacks específicos).
- O sidecar do Istio é injetado automaticamente em pods de namespaces marcados com `istio-injection: enabled` — sem necessidade de alterar os Dockerfiles ou Deployments dos serviços.
- Relate ao IaC (ADR-020): a configuração do Istio (`VirtualService`, `DestinationRule`, `AuthorizationPolicy`) deve ser versionada e aplicada via Terraform ou Helm.
- Relacionado: ADR-001 (microserviços), ADR-009 (Kong — apenas externo), ADR-011 (Kubernetes), ADR-016 (resiliência na camada de aplicação), ADR-018 (observabilidade).
