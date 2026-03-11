# ADR-010: BFF (Backend for Frontend) Dedicado por Canal

**Status:** Aceito  
**Data:** 2026-03-10

---

## Contexto

O FoodeApp possui dois frontends com características distintas:
- **Web** (React): tela maior, mais dados por página, navegação por mouse/teclado, contexto de gerenciamento/operação.
- **App Mobile** (React Native): tela menor, menos dados, navegação touch, conexão potencialmente instável, foco no consumidor final.

Se ambos os frontends consumissem diretamente os microserviços, teriam que lidar com:
- Aggregação de múltiplas chamadas para montar uma única tela (chatty API).
- Respostas com dados desnecessários para o contexto do frontend (over-fetching).
- Lógica de composição de dados repetida em cada frontend.
- Dificuldade de evoluir a API sem impactar múltiplos clientes simultaneamente.

O padrão **BFF (Backend for Frontend)** propõe criar uma camada de backend dedicada por tipo de cliente, que agrega, filtra e formata os dados especificamente para as necessidades de cada frontend.

## Decisão

Criaremos **dois BFFs dedicados**, um por canal de frontend:

| BFF | Serve | Responsabilidades |
|-----|-------|------------------|
| `bff-web` | Frontend React Web | Agrega dados para dashboards, relatórios, gestão de cardápio, painel do restaurante |
| `bff-app` | App React Native | Agrega dados para fluxo do consumidor: busca, pedido, status, histórico |

Cada BFF:
- É um serviço .NET separado e deployável independentemente.
- Conhece as necessidades específicas do seu frontend.
- Agrega chamadas a múltiplos microserviços para reduzir round-trips do cliente.
- Formata e filtra dados antes de enviá-los ao frontend.
- Fica atrás do Kong (ADR-009) — o Kong roteia para o BFF correto.
- Pode implementar cache de curta duração específico do cliente (ADR-015).
- É o lugar correto para lógica de composição de UI, não nos microserviços de domínio.

## Consequências

### Positivas

- Cada frontend recebe exatamente os dados que precisa — sem over-fetching nem under-fetching.
- Redução do número de requests do cliente (BFF agrega chamadas internas).
- Frontends ficam mais simples: a complexidade de composição fica no BFF.
- Cada BFF pode evoluir independentemente conforme as necessidades do seu frontend mudam.
- Facilita otimizações específicas por canal (ex: payloads menores para mobile, paginação mais agressiva).
- Separação clara entre "o que o domínio conhece" (microserviços) e "o que a UI precisa" (BFF).

### Negativas / Trade-offs

- Mais um componente para manter e operar por canal de frontend.
- Lógica de composição semelhante pode ser duplicada entre BFFs se não houver atenção.
- O BFF não deve conter regras de negócio — se isso acontecer, evolui para um "GOD BFF" e o padrão perde o sentido.
- Mudanças nos microserviços de domínio podem exigir atualização coordenada dos BFFs.

### Neutras / Observações

- **Regra fundamental:** BFF contém lógica de **apresentação e composição**, nunca lógica de **negócio**. Regras de negócio vivem nos microserviços.
- Se surgir um terceiro canal (ex: API pública para parceiros), um terceiro BFF deve ser criado — não reutilizar os existentes com condicionais.
- Os BFFs se comunicam com os microserviços internamente via HTTP (dentro do cluster Kubernetes) ou via fila quando necessário.
- Autenticação/autorização é validada pelo Kong antes de chegar ao BFF — o BFF confia que o usuário já foi autenticado.
