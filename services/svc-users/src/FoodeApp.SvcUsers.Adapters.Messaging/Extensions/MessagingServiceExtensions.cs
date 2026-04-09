using FoodeApp.Svcusers.Adapters.Messaging.Publishers;
using FoodeApp.Svcusers.Domain.Ports;
using Microsoft.Extensions.DependencyInjection;

namespace FoodeApp.Svcusers.Adapters.Messaging.Extensions;

public static class MessagingServiceExtensions
{
    /// <summary>
    /// Registra os adaptadores de mensageria no container de DI.
    /// Quando o MassTransit Outbox for ativado (ADR-017), os registros adicionais
    /// (ConfigureMassTransit, AddRabbitMq, etc.) entrarão aqui.
    /// </summary>
    public static IServiceCollection AddSvcusersMessaging(this IServiceCollection services)
    {
        services.AddScoped<IUserEventPublisher, UserEventPublisher>();
        return services;
    }
}
