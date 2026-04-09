using FluentMigrator.Runner;
using FoodeApp.Kernel.Configuration;
using FoodeApp.Svcusers.Adapters.Data.Repositories;
using FoodeApp.Svcusers.Application.Ports;
using FoodeApp.Svcusers.Domain.Ports;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;

namespace FoodeApp.Svcusers.Adapters.Data.Extensions;

public static class DataServiceExtensions
{
    public static IServiceCollection AddSvcusersData(this IServiceCollection services, IConfiguration configuration)
    {
        services.AddDbContext<usersDbContext>((sp, options) =>
        {
            var dataSource = sp.GetRequiredService<NpgsqlDataSource>();
            options.UseNpgsql(dataSource);
        });

        services.AddScoped<IUserWriteRepository, UserWriteRepository>();
        services.AddScoped<IUnitOfWork, UnitOfWork>();
        services.AddScoped<IUserReadRepository, UserReadRepository>();

        var dbSettings = configuration.GetSection("Database").Get<DatabaseSettings>()
            ?? throw new InvalidOperationException("Secao 'Database' nao encontrada na configuracao.");

        services.AddFluentMigratorCore()
            .ConfigureRunner(runner => runner
                .AddPostgres()
                .WithGlobalConnectionString(dbSettings.ConnectionString)
                .ScanIn(typeof(DataServiceExtensions).Assembly).For.Migrations())
            .AddLogging(lb => lb.AddFluentMigratorConsole());

        return services;
    }
}
