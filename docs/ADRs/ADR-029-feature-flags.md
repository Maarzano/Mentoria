# ADR-029: Feature Flags — Estratégia e Implementação

**Status:** Aceito  
**Data:** 2026-03-10

---

## Contexto

O diagrama arquitetural identifica Feature Flags como um mecanismo desejado para o FoodeApp, com as seguintes motivações explícitas:

> *"Quero utilizar feature flags, pelo menos em algumas coisas para testar como se faz, pode ser em features novas... podemos usar Redis para guardar ela, mas aí precisaríamos criar o front para mudar, ou usar SaaS disso. Precisamos excluir elas depois de validar."*

Feature Flags permitem:
- **Releases sem deploy**: habilitar/desabilitar features em produção sem novo código.
- **Canary releases e rollout gradual**: liberar para X% dos usuários antes do rollout completo.
- **Kill switch**: desabilitar imediatamente uma feature defeituosa sem rollback de código.
- **A/B testing**: comparar variantes de features com subsets de usuários.

As opções avaliadas foram:

| Abordagem | Controle | Operação | Targeting por usuário | UI de gestão |
|-----------|----------|----------|----------------------|-------------|
| **Redis manual** | Total | Baixa (já temos Redis) | Requer código extra | Precisaria construir |
| **SaaS (LaunchDarkly / Flagsmith Cloud)** | Alta | Zero | ✅ nativo | ✅ nativo | 
| **Flagsmith self-hosted** | Total | Médio (mais um pod) | ✅ nativo | ✅ nativo |
| **GrowthBook** | Total | Médio | ✅ nativo | ✅ nativo |

O Kong (ADR-009) foi mencionado no diagrama como possível mecanismo de canary release via traffic splitting — isso é complementar, não substituto de feature flags.

## Decisão

Adotaremos **Flagsmith self-hosted** como plataforma de feature flags do FoodeApp.

### Motivos da escolha

- **Open source com UI web**: painel pronto para ligar/desligar flags sem deploy — atende ao requisito do diagrama sem construir do zero.
- **Self-hosted no Kubernetes**: sem custo recorrente de SaaS — Flagsmith roda como pod no cluster (ADR-011).
- **Targeting por identidade**: suporta habilitar flags por `userId`, `estabelecimentoId`, porcentagem de usuários, ou combinações — necessário para canary e A/B.
- **SDK oficial .NET**: integração simples nos microserviços via `Flagsmith` NuGet package.
- **Infraestrutura Terraform** disponível (ADR-020).

### Categorias de feature flags

| Categoria | Exemplo | Vida útil |
|-----------|---------|-----------|
| **Release flag** | `novo-fluxo-checkout` | Temporária — remover após rollout completo |
| **Kill switch** | `pagamento-pix-habilitado` | Permanente em produção |
| **Experiment (A/B)** | `layout-cardapio-v2` | Temporária — remover após decisão |
| **Ops flag** | `manutencao-pagamentos` | Permanente — ativada em manutenções |

### Regra obrigatória: ciclo de vida das flags

> **Flags temporárias têm prazo de expiração definido na criação.**
> Uma flag de release deve ser removida do código no sprint seguinte ao rollout completo.
> Flags não utilizadas acumulam dívida técnica e confusão operacional.

O nome da flag no código e na plataforma deve seguir o padrão:
- `{dominio}_{descricao}_{tipo}` → ex: `pedidos_novo_checkout_release`, `pagamentos_pix_ops`

### Integração nos microserviços .NET

```csharp
// Injetado via DI — avalia a flag para o usuário correto
var flagEnabled = await _flagsmith.IsFeatureEnabled("pedidos_novo_checkout_release", userId);

if (flagEnabled)
{
    // novo comportamento
}
else
{
    // comportamento atual (fallback)
}
```

- A avaliação da flag ocorre **no início** do request — nunca no meio de uma transação.
- Flags são **cacheadas localmente** pelo SDK do Flagsmith (TTL configurável, padrão 60s) — sem latência de rede a cada request.
- O SDK faz fallback para o valor padrão da flag se o Flagsmith estiver indisponível — flags nunca bloqueiam o fluxo principal.

### Canary release via Flagsmith vs Kong

| Mecanismo | Quando usar |
|-----------|------------|
| **Flagsmith (flag por usuário/%)** | Rollout gradual de feature específica — usuário A vê nova feature, usuário B vê a antiga |
| **Kong traffic splitting** | Canary de versão inteira do serviço — X% do tráfego vai para a nova versão do pod |

Os dois mecanismos são complementares e independentes.

## Consequências

### Positivas

- Kill switch imediato para qualquer feature sem deploy — reduz drasticamente o risco de releases.
- Rollout gradual controlado — problemas afetam menos usuários antes de serem detectados.
- Separação entre deploy e release: code pode ser deployado mas feature fica invisível até ser ligada.
- Flagsmith self-hosted garante que dados de targeting de usuários não saem da infraestrutura do FoodeApp (LGPD relevante).
- UI web permite que não-engenheiros (ex: PO/PM) liguem ou desliguem features de forma segura.

### Negativas / Trade-offs

- Mais um componente para operar no Kubernetes (Flagsmith + seu PostgreSQL).
- Se o time não mantiver disciplina de remover flags temporárias, o código se enche de branches mortos — requer processo (revisão de flags no planning de sprint).
- Feature flags aumentam a complexidade do rastreamento em logs/traces (ADR-018): o estado das flags ativas deve ser incluído como contexto nas métricas de A/B.
- Testar comportamento com flags different estados pode ser trabalhoso — requer testes parametrizados.

### Neutras / Observações

- O Flagsmith usa PostgreSQL próprio — não compartilha instância com os serviços de negócio.
- O painel do Flagsmith deve ser acessível apenas internamente (sem Kong público) — acesso via VPN ou IP whitelist.
- **Graveyard de flags**: manter documento ou issues de rastreamento listando flags temporárias com data-alvo de remoção.
- Auditar via logs do Flagsmith quem ligou/desligou cada flag e quando — importante para rastreabilidade em incidentes.
- No ambiente local (`docker-compose`), o Flagsmith pode rodar com flags mockadas via arquivo de configuração — sem necessidade da instância real para desenvolvimento.
