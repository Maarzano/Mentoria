using FoodeApp.SvcAuth.Adapters.Data.Repositories;
using FoodeApp.SvcAuth.Adapters.Data.Schema;
using FoodeApp.SvcAuth.Domain.Ports;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;

namespace FoodeApp.SvcAuth.Adapters.Data.Extensions;

public static class DataServiceExtensions
{
    /// <summary>
    /// Registra todos os adaptadores de dados no container de DI.
    /// Chamado pelo host (Adapters.API/Program.cs).
    /// </summary>
    public static IServiceCollection AddSvcAuthData(
        this IServiceCollection services,
        NpgsqlDataSource dataSource)
    {
        services.AddSingleton(dataSource);
        services.AddScoped<IUserRepository, UserRepository>();
        services.AddSingleton<SchemaInitializer>();
        return services;
    }
}
