using FoodeApp.Kernel.Configuration;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using Npgsql;

namespace FoodeApp.Kernel.Extensions;

public static class DatabaseExtensions
{
    /// <summary>
    /// Registra DatabaseSettings (IOptions&lt;T&gt;) e NpgsqlDataSource no DI.
    /// O NpgsqlDataSource é singleton — Npgsql 10+ gerencia o pool internamente.
    /// </summary>
    public static IServiceCollection AddFoodeAppDatabase(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        services.Configure<DatabaseSettings>(configuration.GetSection("Database"));

        services.AddSingleton(sp =>
        {
            var settings = sp.GetRequiredService<IOptions<DatabaseSettings>>().Value;
            var missing = new List<string>();

            if (string.IsNullOrWhiteSpace(settings.Host)) missing.Add("Database__Host");
            if (settings.Port <= 0) missing.Add("Database__Port");
            if (string.IsNullOrWhiteSpace(settings.Database)) missing.Add("Database__Database");
            if (string.IsNullOrWhiteSpace(settings.Username)) missing.Add("Database__Username");
            if (string.IsNullOrWhiteSpace(settings.Password)) missing.Add("Database__Password");

            if (missing.Count > 0)
            {
                throw new InvalidOperationException(
                    $"Configuracao de banco incompleta. Defina: {string.Join(", ", missing)}. " +
                    "Para dev local, carregue .env com POSTGRES_*; a porta HTTP do servico pode vir de services.json, mas credenciais nao fazem fallback.");
            }

            return new NpgsqlDataSourceBuilder(settings.ConnectionString).Build();
        });

        return services;
    }
}
