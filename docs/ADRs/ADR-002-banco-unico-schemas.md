# ADR-002: Banco de Dados Único com Separação por Schemas (Estratégia Inicial)

**Status:** Aceito  
**Data:** 2026-03-10

---

## Contexto

Em uma arquitetura de microserviços pura, cada serviço deveria ter seu próprio banco de dados isolado. No entanto, no estágio inicial do FoodeApp, manter múltiplas instâncias de banco de dados implica:

- Maior custo de infraestrutura (múltiplas instâncias PostgreSQL).
- Maior complexidade operacional (backups, monitoramento, provisionamento por instância).
- Overhead desnecessário para um time pequeno em fase de produto.

Ao mesmo tempo, não queremos usar um único conjunto de tabelas sem qualquer separação, pois isso criaria acoplamento na camada de dados e dificultaria a eventual migração para bancos separados.

## Decisão

Usaremos **um único banco de dados PostgreSQL**, com a separação lógica feita por **schemas** — um schema por serviço/bounded context.

Exemplos:
- `orders.*` — tabelas do serviço de pedidos
- `menu.*` — tabelas do serviço de cardápio
- `payments.*` — tabelas do serviço de pagamentos
- `users.*` — tabelas do serviço de usuários
- `notifications.*` — tabelas do serviço de notificações

Cada serviço **só acessa seu próprio schema** diretamente. Não haverá JOINs entre schemas. Toda troca de dados entre serviços ocorre via mensagens (fila) ou API.

## Consequências

### Positivas

- Custo inicial muito menor: uma única instância de banco.
- Operações de backup, restore e monitoramento centralizadas.
- Facilidade de setup local para desenvolvimento.
- A separação por schemas cria uma "fronteira lógica" que respeita os bounded contexts e facilita a migração futura para bancos separados.
- Migrations são versionadas e organizadas por schema/serviço.

### Negativas / Trade-offs

- Não há isolamento **físico** de falhas: um problema no banco afeta todos os serviços.
- Não é possível escalar o banco de forma independente por serviço.
- Um schema mal gerenciado pode "vazar" e acessar outro schema, quebrando o isolamento — isso exige disciplina de code review e testes.
- A migração para bancos separados no futuro exigirá trabalho (sincronização de dados, cutover).

### Neutras / Observações

- Esta é uma **decisão temporária e consciente**. O objetivo é evoluir para bancos separados por serviço conforme o produto e o time crescerem.
- A separação por schemas é o "passo 1" que torna essa migração futura menos traumática.
- Triggers, foreign keys e views cross-schema são **proibidos** — o isolamento existe por contrato do time, não apenas por restrição técnica.

### Regra de ouro: Transação vs Fila

| Escopo da alteração | Mecanismo obrigatório |
|---|---|
| Tabelas **dentro do mesmo schema** (mesmo microserviço) | **Transação ACID** normal do PostgreSQL |
| Tabelas em **schemas diferentes** (microserviços distintos) | **Fila de mensagens** (RabbitMQ via Outbox — ADR-017) |

O motivo não é limitação técnica — tecnicamente o PostgreSQL permite uma transação que toca dois schemas. A proibição é **arquitetural**: cada schema deve ser tratado como se já fosse um banco separado, porque será no futuro. Qualquer código que transacione entre schemas vai quebrar sem aviso quando a migração para bancos físicos individuais acontecer.

- Relacionado: ADR-005 (tabelas normalizadas e desnormalizadas), ADR-003 (PostgreSQL como banco escolhido), ADR-017 (Outbox), ADR-007 (SAGA para fluxos entre serviços).
