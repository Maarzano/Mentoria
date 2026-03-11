# ADR-004: CQRS em Nível de Classe (Separação de Comandos e Queries)

**Status:** Aceito  
**Data:** 2026-03-10

---

## Contexto

À medida que o sistema cresce, misturar lógica de leitura e escrita no mesmo serviço/classe leva a problemas como:

- Modelos de domínio poluídos com preocupações de leitura.
- Dificuldade em otimizar queries sem afetar a lógica de escrita.
- Código difícil de testar isoladamente.

O padrão **CQRS (Command Query Responsibility Segregation)** propõe separar explicitamente as operações que **modificam estado** (Commands) das que **leem estado** (Queries).

Existem diferentes níveis de adoção do CQRS:

1. **Nível de classe** — separação lógica no mesmo processo, sem infra separada.
2. **Nível de pipeline** — handlers distintos com middlewares diferenciados.
3. **Nível de banco** — bancos físicos separados para leitura e escrita.

## Decisão

Adotaremos **CQRS em nível de classe**, utilizando a biblioteca **MediatR** no .NET para separar explicitamente Commands e Queries em handlers distintos.

Estrutura padrão:
```
Application/
  Commands/
    CreateOrder/
      CreateOrderCommand.cs
      CreateOrderCommandHandler.cs
  Queries/
    GetOrderById/
      GetOrderByIdQuery.cs
      GetOrderByIdQueryHandler.cs
```

- **Commands** → modificam estado, passam por validação, domínio e persistência.
- **Queries** → leem dados, podem acessar diretamente o modelo desnormalizado (ADR-005), sem passar pela lógica de domínio.

**Não separamos bancos de leitura e escrita neste momento** — isso é conscientemente adiado (ver ADR-005).

## Consequências

### Positivas

- Código com responsabilidade única e coesa: handlers pequenos e focados.
- Queries podem ser otimizadas independentemente (ex: Dapper para queries diretas).
- Facilidade de testar cada caso de uso isoladamente.
- Abre caminho natural para evolução futura em direção a bancos separados de leitura/escrita.
- Pipeline de comportamentos (validação, logging, autorização) pode ser aplicado seletivamente a Commands ou Queries via MediatR behaviors.

### Negativas / Trade-offs

- Mais arquivos e estrutura de diretórios mais extensa (pode parecer over-engineering para casos simples).
- Desenvolvedores precisam entender o paradigma para não "misturar" acidentalmente responsabilidades.
- Sem separação física de banco, a principal vantagem de performance do CQRS completo não é obtida inicialmente.

### Neutras / Observações

- O uso de **MediatR** como dispatcher desacopla o ponto de entrada (controller) do handler, facilitando testes e substituição futura.
- Queries **podem** acessar as tabelas desnormalizadas de leitura diretamente (ADR-005), sem passar pela camada de domínio.
- Commands **devem** passar pelo modelo de domínio e usar as tabelas normalizadas de escrita.
- Evolução prevista: caso performance exija, é possível evoluir para banco de leitura separado sem alterar a estrutura de Commands e Queries (apenas os QueryHandlers mudam de fonte de dados).
