# ADR-001: Arquitetura de Microserviços

**Status:** Aceito  
**Data:** 2026-03-10

---

## Contexto

O FoodeApp é um sistema de delivery/alimentação com múltiplos domínios distintos (pedidos, cardápio, pagamento, usuários, notificações, etc.). Esses domínios possuem necessidades de escalabilidade, ciclos de deploy e equipes potencialmente diferentes. Uma arquitetura monolítica atenderia bem no início, mas criaria acoplamento forte e dificuldade de evolução independente de cada domínio a médio e longo prazo.

A decisão do time é pela separação desde o início, com consciência de que a complexidade operacional aumenta, mas os ganhos estratégicos de longo prazo justificam a escolha.

## Decisão

Adotaremos **arquitetura de microserviços** como estilo arquitetural principal do FoodeApp.

Cada serviço:

- Representa um **bounded context** claro e bem definido dentro do domínio do sistema.
- É deployável de forma **independente**.
- É responsável pelos seus próprios dados (isolamento lógico via schemas num primeiro momento — ver ADR-002).
- Se comunica com outros serviços de forma **assíncrona** via fila de mensagens (RabbitMQ — ADR-006) quando não precisa de resposta imediata.
- Se comunica de forma **síncrona** via HTTP direto (dentro do cluster, gerenciado pelo service mesh — ADR-022) quando o resultado é necessário para continuar o fluxo.

A decomposição inicial dos serviços será guiada pelo domínio do negócio (DDD), não por camadas técnicas.

## Consequências

### Positivas

- Cada serviço pode escalar de forma **independente**, otimizando custo e performance.
- Times podem evoluir e fazer deploy de serviços **sem coordenar releases** com outros times.
- Falhas são isoladas: um serviço com problema não derruba o sistema inteiro.
- Permite escolher tecnologias diferentes por serviço se necessário no futuro.
- Facilita a adoção de SLAs individuais por domínio.

### Negativas / Trade-offs

- **Complexidade operacional** significativamente maior: service discovery, distributed tracing, health checks, etc.
- Testes de integração entre serviços são mais custosos.
- Transações distribuídas requerem padrões específicos como SAGA (ver ADR-007).
- Overhead de rede e serialização em chamadas entre serviços.
- Debugging em produção é mais difícil sem uma boa stack de observabilidade (ver ADR-018).
- Maior curva de aprendizado para novos membros do time.

### Neutras / Observações

- **Inicialmente**, dado o tamanho do time, os serviços devem ter fronteiras bem definidas mas não serem micro demais. Evitar o anti-padrão de "nanoserviços".
- A estratégia de migração de banco de dados único para bancos separados por serviço fica registrada como evolução futura (ADR-002).
- **Comunicação síncrona interna** (serviço → serviço) ocorre diretamente via DNS interno do Kubernetes, gerenciada e observada pelo service mesh (ADR-022). O Kong (ADR-009) é exclusivo para tráfego **externo** (clientes → sistema) e **nunca** é usado como intermediário de comunicação interna.
- A escolha entre síncrono e assíncrono depende da necessidade de resposta imediata: se o passo B depende do resultado do passo A para continuar, use HTTP síncrono. Se não, prefira a fila.
