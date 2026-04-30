# svc-events

**Eventos / feiras / festivais** que agregam múltiplos estabelecimentos. Ex.: "Feira Gastronômica do Centro" — N lojas vinculadas, com período (início/fim), local físico e regras próprias.

> Não confundir com **eventos de domínio (mensagens)** — esses ficam no Outbox + RabbitMQ. Aqui é entidade de negócio.

## Stack

| Item | Escolha |
|---|---|
| Linguagem | **C# / .NET 10 (LTS)** |
| Banco | PostgreSQL — schema `events` |
| Mensageria | RabbitMQ via MassTransit (Outbox) |

## Responsabilidades

- CRUD de evento (admin/organizador).
- Vínculo N:N evento ↔ estabelecimento.
- Período de vigência, local, descrição, capa.
- Listagem de eventos ativos / próximos (read model).

## 🗣️ Pontos para discussão

- [ ] Permissões: quem pode criar evento? Admin global, organizador externo, lojista?
- [ ] Linguagem alternativa? **Elixir** seria interessante se tivesse tempo real pesado (chat do evento, contagem ao vivo) — hoje não justifica trocar de C#.
- [ ] Geolocalização: usar `svc-location` ou guardar lat/lng fixo aqui?
- [ ] Eventos privados (acesso por convite) — fora de escopo MVP?
