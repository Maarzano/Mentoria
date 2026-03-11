# ADR-019: UI Otimista (Optimistic UI) para Consistência Eventual

**Status:** Aceito  
**Data:** 2026-03-10

---

## Contexto

Em sistemas distribuídos com consistência eventual (ex: dados que transitam por filas, tabelas de leitura atualizadas de forma assíncrona — ADR-005), há uma janela de tempo entre a operação ser executada com sucesso no backend e os dados novos estarem disponíveis para leitura.

Se o frontend confirmar uma ação (ex: adicionar item ao carrinho, confirmar pedido) e em seguida consultar o estado atualizado, pode receber dados desatualizados por alguns milissegundos ou segundos — o que confunde o usuário e parece um bug mesmo não sendo.

Soluções comuns para o problema:
1. **Esperar pela consistência**: bloquear o frontend até ter certeza que os dados estão consistentes. Péssima UX, alto acoplamento.
2. **Ignorar**: não fazer nada. O usuário vê estado antigo e fica confuso.
3. **UI Otimista**: assumir que a operação vai dar certo e refletir a mudança na interface imediatamente, corrigindo apenas se der errado.

## Decisão

Adotaremos **UI Otimista (Optimistic UI)** como padrão para operações que modificam estado no FoodeApp.

### Como funciona:

1. **O usuário executa uma ação** (ex: confirma um pedido).
2. **O frontend atualiza imediatamente** o estado local como se a operação já tivesse sido bem-sucedida (sem esperar a resposta do servidor).
3. **A API é chamada em background**.
4. Se a API retornar **sucesso**: nada muda na interface — o usuário já viu o estado correto.
5. Se a API retornar **erro**: o frontend **desfaz a mudança** e exibe uma mensagem de erro clara ao usuário.

### Aplicações no FoodeApp:
- Adicionar/remover item do carrinho.
- Curtir ou favoritar restaurante/item.
- Atualizar quantidade de um item no pedido.
- Confirmar ações simples onde o erro é raro.

### Quando **não** usar UI Otimista:
- Operações financeiras (pagamento, reembolso) — o usuário deve ver confirmação real.
- Operações de alto impacto onde o rollback seria confuso (ex: cancelar pedido já em preparo).
- Operações onde a validação do servidor é complexa e a taxa de erro é alta.

## Consequências

### Positivas

- **UX significativamente melhor**: a interface responde instantaneamente, sem loading spinners para operações simples.
- Reduz a percepção de latência do sistema — o usuário não precisa esperar a round-trip de rede para ver o resultado.
- Desacopla a UX da latência de rede e dos atrasos de consistência eventual.
- Padrão amplamente utilizado por apps de alto padrão (WhatsApp, Instagram, Uber, etc.).

### Negativas / Trade-offs

- Aumenta a complexidade do estado no frontend: é necessário gerenciar o estado otimista, o estado real e o rollback.
- Em caso de erro, o usuário pode ficar confuso se o rollback não for bem comunicado — uma boa mensagem de erro é obrigatória.
- Pode criar inconsistência visual momentânea se a taxa de erros for alta (o usuário vê sucesso e logo depois vê rollback).
- Não elimina a necessidade de feedback de erro — só muda o timing.

### Neutras / Observações

- No React, o hook `useOptimistic` (nativo no React 19+) ou bibliotecas como **React Query** / **TanStack Query** facilitam a implementação com rollback automático.
- O backend **não sabe** que o frontend já assumiu sucesso — continua funcionando normalmente, retornando sucesso ou erro.
- A combinação de UI Otimista + Idempotência (ADR-013) é poderosa: em caso de retry após falha de rede, o mesmo resultado é retornado sem processar duas vezes.
- Relacionado: ADR-005 (consistência eventual entre tabelas de escrita e leitura), ADR-013 (idempotência).
