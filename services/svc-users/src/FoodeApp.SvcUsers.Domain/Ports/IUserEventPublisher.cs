using FoodeApp.Svcusers.Domain.Events;

namespace FoodeApp.Svcusers.Domain.Ports;

/// <summary>
/// Porta de saída (outbound port): contrato de publicação de domain events.
/// Implementado por Adapters.Messaging (MassTransit + RabbitMQ) seguindo o
/// padrão Outbox (ADR-017): a implementação persiste o evento na tabela
/// outbox_messages dentro da mesma transação de banco — nunca publica direto.
/// </summary>
public interface IUserEventPublisher
{
    Task PublishUserRegisteredAsync(UserRegisteredEvent @event, CancellationToken ct = default);
}
