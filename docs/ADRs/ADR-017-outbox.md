# ADR-017: Padrão Outbox para Consistência entre Banco de Dados e Fila de Mensagens

**Status:** Aceito  
**Data:** 2026-03-10

---

## Contexto

Em um Command Handler típico, é comum precisar realizar duas operações atômicas:
1. **Persistir o estado** no banco de dados (PostgreSQL).
2. **Publicar uma mensagem** na fila (RabbitMQ) para notificar outros serviços.

O problema: **não existe transação distribuída** entre o PostgreSQL e o RabbitMQ. Se o processo for interrompido entre as duas operações, podemos cair em um de dois cenários inconsistentes:
- Dado salvo no banco, mas mensagem **não publicada** → outros serviços não sabem o que aconteceu.
- Mensagem publicada, mas dado **não salvo** → outros serviços agem sobre dados que não existem.

Nenhum dos dois é aceitável em um sistema financeiro/transacional como o FoodeApp.

## Decisão

Usaremos o **Padrão Outbox** (Transactional Outbox) para garantir atomicidade entre a escrita no banco e a publicação de mensagens na fila.

### Como funciona:

1. No mesmo Command Handler, dentro de **uma única transação de banco de dados**:
   - Persiste-se o estado do domínio na tabela principal.
   - Persiste-se a mensagem a ser publicada em uma tabela **`outbox_messages`** (dentro do mesmo schema do serviço).

2. Um **process worker dedicado** (background job) consulta periodicamente a tabela `outbox_messages`:
   - Lê mensagens não publicadas.
   - Publica no RabbitMQ.
   - Marca como publicada (ou deleta) após confirmação do broker.

3. Se o processo morrer entre o passo 1 e o passo 2, a mensagem ainda está na tabela `outbox_messages` e será publicada na próxima execução do worker.

### Estrutura da tabela `outbox_messages`:
```sql
CREATE TABLE {schema}.outbox_messages (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type         VARCHAR(255) NOT NULL,       -- tipo/nome do evento
  payload      JSONB        NOT NULL,       -- corpo da mensagem
  created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  published_at TIMESTAMPTZ  NULL,           -- NULL = pendente
  retry_count  INT          NOT NULL DEFAULT 0
);
```

## Consequências

### Positivas

- **Consistência garantida**: ou ambas as operações acontecem (banco + outbox na mesma transação), ou nenhuma acontece.
- Sem mensagens "perdidas" mesmo em caso de falha do processo entre a escrita e a publicação.
- O Outbox funciona como um buffer durável, desacoplando a escrita da publicação.
- Permite reprocessar mensagens com falha sem risco de duplicação no banco.
- Compatível com a estratégia de SAGA (ADR-007): eventos da SAGA também passam pelo Outbox.

### Negativas / Trade-offs

- **Latência adicional**: a mensagem não é publicada instantaneamente — há um delay entre a transação e a publicação (geralmente milissegundos a poucos segundos, dependendo do polling interval do worker).
- Tabela `outbox_messages` cresce continuamente e precisa de uma estratégia de limpeza (purge de registros publicados após N dias).
- O worker de publicação é um componente adicional a operar e monitorar.
- Em cenários de alto volume, a tabela Outbox pode se tornar um gargalo — particionamento por tempo pode ser necessário.
- Mensagens podem ser publicadas **mais de uma vez** em caso de falha do worker após publicar mas antes de marcar como publicada → consumidores devem ser idempotentes (ADR-013).

### Neutras / Observações

- Bibliotecas como **MassTransit Outbox** (nativo) ou **Wolverine** implementam esse padrão de forma transparente no .NET, sem precisar gerenciar manualmente.
- A periodicidade do worker de polling deve ser calibrada: muito curta → carga no banco; muito longa → latência de entrega alta. Um intervalo de 500ms a 2s costuma ser bom ponto de partida.
- O Outbox por si só não garante **ordem de mensagens** — se a ordem importa, use números de sequência ou timestamps e trate nos consumidores.
- Relacionado: ADR-006 (RabbitMQ), ADR-007 (SAGA), ADR-013 (idempotência nos consumidores).
