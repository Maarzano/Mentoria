# svc-establishments

Cadastro e estado das **lojas/estabelecimentos** do FoodeApp: dados cadastrais, horários, status (aberto/fechado), localização fixa, contato.

## Stack

| Item | Escolha |
|---|---|
| Linguagem | **C# / .NET 10 (LTS)** |
| Banco | PostgreSQL — schema `establishments` |
| Mensageria | RabbitMQ via MassTransit (Outbox) |
| Observabilidade | OpenTelemetry stack (ADR-018) |

> Segue o mesmo template de `svc-users`. CQRS nível de classe, Outbox, KongHeadersMiddleware.

## Responsabilidades

- CRUD de estabelecimento (somente lojista dono ou admin pode mutar).
- Horários de funcionamento, dias da semana, exceções (feriado).
- Toggle aberto/fechado em tempo real.
- Endereço fixo da loja (lat/lng — diferente de `svc-location` que cuida de GPS móvel).
- Publica eventos: `EstablishmentCreated`, `EstablishmentStatusChanged`, `EstablishmentUpdated`.

## Arquitetura proposta

Mesmas camadas de svc-users (Domain / Application / Adapters.API / Adapters.Data / Adapters.Messaging).

## 🗣️ Pontos para discussão

- [ ] Telefone de contato da loja: fica aqui ou em `svc-users` (perfil do dono)? — Hoje o memo diz "phone do estabelecimento ≠ phone do perfil". Confirmar.
- [ ] Validação de CNPJ e dados fiscais — onde mora? svc-users (tax_id) ou aqui?
- [ ] Geocoding do endereço — síncrono no create ou assíncrono via worker?
- [ ] Gestão de imagens da loja (logo, capa) — usar `svc-files`/CDN (ADR-028)?
