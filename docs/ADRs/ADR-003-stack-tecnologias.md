# ADR-003: Stack de Tecnologias Principal (React, .NET 10, PostgreSQL)

**Status:** Aceito
**Data:** 2026-03-10

---

## Contexto

Para iniciar o desenvolvimento do FoodeApp, é necessário definir a stack tecnológica base: linguagem do backend, framework frontend e banco de dados relacional. Essas escolhas impactam contratação, produtividade do time, ecossistema de ferramentas e longevidade do produto.

## Decisão

Adotaremos a seguinte stack como padrão tecnológico do FoodeApp:

| Camada | Tecnologia | Versão |
|--------|-----------|--------|
| Frontend Web | React | Última estável |
| Frontend Mobile | React Native | Última estável |
| Backend | .NET (C#) | 10 (LTS) |
| Banco de Dados | PostgreSQL | Última estável |

### Justificativas

**React (Web + React Native Mobile):**
- Compartilhamento de lógica e conhecimento entre as equipes web e mobile.
- Ecossistema enorme, vasta comunidade, facilidade de contratar.
- React Native permite código mobile próximo do web, reduzindo duplicação.
- A existência de 2 frontais (Web e App) é tratada via BFF dedicado por canal (ADR-010).

**.NET 10 (C#):**
- Alta performance, tipagem forte, excelente suporte a concorrência e async/await.
- Primeira versão LTS após .NET 9, garantindo suporte de longo prazo.
- Excelente ecossistema para CQRS (MediatR), filas, observabilidade e DDD.
- Forte integração com ferramentas como OpenTelemetry, Entity Framework e afins.

**PostgreSQL:**
- Banco relacional de código aberto com excelente performance e confiabilidade.
- Suporte nativo a JSON/JSONB para dados semi-estruturados quando necessário.
- Extensível (ex: pgcrypto, pg_partman, PostGIS se necessário).
- Suporte a schemas para separação lógica de dados entre serviços (ADR-002).
- Amplamente suportado por provedores de cloud (RDS, Cloud SQL, etc.).
- Disponível como managed service, reduzindo overhead operacional.

## Consequências

### Positivas

- Stack moderna e amplamente adotada na indústria.
- Facilidade de encontrar desenvolvedores e recursos de aprendizado.
- .NET 10 garante suporte por vários anos (LTS).
- Alinhamento entre Web e Mobile reduz divergência tecnológica.
- PostgreSQL é versátil o suficiente para cobrir casos de uso simples e avançados.

### Negativas / Trade-offs

- .NET 10 é novo: pode haver menor disponibilidade de bibliotecas de terceiros atualizadas no lançamento.
- React Native, apesar de compartilhar paradigma com React Web, tem peculiaridades que exigem conhecimento específico de mobile.
- PostgreSQL pode não ser a melhor escolha para casos de uso muito específicos (ex: full-text search em escala — Elasticsearch seria melhor; grafos — Neo4j seria melhor), mas cobre bem o escopo atual do FoodeApp.

### Neutras / Observações

- Não há impedimento para usar serviços auxiliares com tecnologias diferentes (Redis, RabbitMQ, etc.) quando a necessidade justificar.
- A versão do .NET deve ser atualizada conforme novos LTS forem lançados, com planejamento de migração.
