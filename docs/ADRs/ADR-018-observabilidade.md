# ADR-018: Stack de Observabilidade (OpenTelemetry + Prometheus + Loki + Tempo + Grafana)

**Status:** Aceito  
**Data:** 2026-03-10

---

## Contexto

Em uma arquitetura de microserviços, entender o que está acontecendo no sistema em produção é muito mais difícil do que em um monolito. Uma requisição do usuário pode passar por Kong → BFF → 3 ou 4 microserviços → banco de dados → fila → outro serviço. Sem observabilidade adequada:

- É impossível saber onde um erro aconteceu.
- Não se sabe qual serviço está lento.
- Alertas são reativos demais (o usuário reporta antes do time perceber).
- Debugging em produção é um processo de tentativa e erro cego.

Os três pilares da observabilidade são:
- **Métricas**: valores numéricos ao longo do tempo (CPU, req/s, latência, erros).
- **Logs**: registros estruturados de eventos discretos.
- **Traces**: rastreamento de uma requisição através de múltiplos serviços.

## Decisão

Adotaremos a seguinte stack de observabilidade, com **OpenTelemetry** como camada unificada de instrumentação:

| Ferramenta | Pilar | Função |
|-----------|-------|--------|
| **OpenTelemetry (OTel)** | Todos | SDK único para instrumentação de métricas, logs e traces no .NET. Agnóstico de backend — envia para qualquer destino. |
| **Prometheus** | Métricas | Coleta e armazena métricas por scraping dos endpoints `/metrics` expostos pelo OTel Collector. Suporta alertas via Alertmanager. |
| **Loki** | Logs | Armazena logs estruturados. Indexação por labels (não por conteúdo), o que o torna eficiente e barato. |
| **Tempo** | Traces | Armazena distributed traces. Integrado ao Grafana para visualização de spans. |
| **Grafana** | Visualização | Painel unificado que consolida métricas (Prometheus), logs (Loki) e traces (Tempo) em dashboards e alertas. |

### Instrumentação:
- Todos os serviços .NET usarão o SDK do **OpenTelemetry .NET** para:
  - Auto-instrumentação de HTTP, banco de dados, MassTransit/RabbitMQ.
  - Instrumentação manual para spans de negócio relevantes.
  - Propagação de `TraceId` e `SpanId` em todos os logs (correlação de logs com traces).
- O `TraceId` deve estar presente em **todos** os logs e em respostas de erro ao cliente (para facilitar suporte).

### O que monitorar (exemplos):

**Métricas:**
- Request rate, error rate, latência (p50, p95, p99) — RED Method por serviço.
- CPU, memória, uso de disco por pod.
- Fila de mensagens: tamanho da fila, taxa de consumo, DLQ.
- Redis: hit rate, uso de memória, latência.
- PostgreSQL: conexões ativas, query time, slow queries.

**Alertas (SLA):**
- Error rate > 1% nos últimos 5 minutos → alerta crítico.
- Latência p99 > 2s → alerta de degradação.
- Tamanho da DLQ > 0 mensagens → investigar mensagens com falha.

## Consequências

### Positivas

- **Stack 100% open source** — sem custo de licença, apenas infraestrutura.
- OpenTelemetry é o padrão da indústria: ao migrar de backend (ex: trocar Tempo por Jaeger), só muda a configuração do Collector, não o código dos serviços.
- Grafana consolida tudo em um único painel — o time não precisa navegar entre múltiplas ferramentas.
- Correlação entre logs e traces (via TraceId) permite navegar de um log de erro diretamente para o trace completo da requisição.
- Facilita SLA real: dashboards mostram métricas objetivas de disponibilidade e latência.

### Negativas / Trade-offs

- Mais componentes de infraestrutura para operar (Prometheus, Loki, Tempo, Grafana, OTel Collector).
- Volume de dados de observabilidade pode crescer rapidamente — política de retenção deve ser configurada.
- Configuração inicial da stack é trabalhosa, especialmente o OTel Collector e o roteamento de dados.
- Loki não indexa conteúdo dos logs (apenas labels) — queries de busca por texto livre são mais lentas que ferramentas como Elasticsearch.

### Neutras / Observações

- Usar o **OTel Collector** como intermediário entre os serviços e os backends (Prometheus, Loki, Tempo): isso desacopla os serviços dos backends e permite trocar backends sem alterar os serviços.
- Definir **Runbooks** para os alertas mais comuns: quando um alerta dispara, o time deve saber o que fazer.
- Dashboards devem ser versionados como código (Grafana suporta provisioning via YAML/JSON — incluir no IaC do ADR-020).
- Dados de observabilidade **não são logs de auditoria de negócio** — logs de auditoria (quem fez o quê) devem ser armazenados no PostgreSQL.
