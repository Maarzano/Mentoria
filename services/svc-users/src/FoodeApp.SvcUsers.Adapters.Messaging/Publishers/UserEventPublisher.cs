using FoodeApp.Svcusers.Domain.Events;
using FoodeApp.Svcusers.Domain.Ports;
using Microsoft.Extensions.Logging;

namespace FoodeApp.Svcusers.Adapters.Messaging.Publishers;

/// <summary>
/// Implementação stub da porta IUserEventPublisher.
///
/// TODO (ADR-017 + ADR-006): Substituir pelo MassTransit Outbox quando o
/// OutboxWorker for implementado. A lógica correta seria:
///   1. Serializar o evento para JSONB
///   2. Inserir em users.outbox_messages dentro da MESMA transação do Command Handler
///   3. O OutboxWorker (hosted service) faz polling e publica no RabbitMQ via MassTransit
///
/// Por enquanto loga o evento para não bloquear o desenvolvimento do fluxo principal.
/// </summary>
internal sealed class UserEventPublisher(ILogger<UserEventPublisher> logger) : IUserEventPublisher
{
    public Task PublishUserRegisteredAsync(UserRegisteredEvent @event, CancellationToken ct = default)
    {
        logger.LogInformation(
            "UserRegistered enfileirado para Outbox. UserId={UserId} Role={Role} OccurredAt={OccurredAt}",
            @event.UserId, @event.Role, @event.OccurredAt);

        return Task.CompletedTask;
    }
}
