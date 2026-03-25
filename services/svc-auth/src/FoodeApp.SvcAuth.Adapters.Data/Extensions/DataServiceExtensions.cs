using FoodeApp.SvcAuth.Adapters.Data.Repositories;
using FoodeApp.SvcAuth.Adapters.Data.Schema;
using FoodeApp.SvcAuth.Domain.Ports;
using Microsoft.Extensions.DependencyInjection;

namespace FoodeApp.SvcAuth.Adapters.Data.Extensions;

public static class DataServiceExtensions
{
    /// <summary>
    /// Registra todos os adaptadores de dados no container de DI.
    /// O NpgsqlDataSource já está registrado pelo AddFoodeAppDatabase() do Kernel.
    /// </summary>
    public static IServiceCollection AddSvcAuthData(this IServiceCollection services)
    {
        services.AddScoped<IUserRepository, UserRepository>();
        services.AddSingleton<SchemaInitializer>();
        return services;
    }
}
