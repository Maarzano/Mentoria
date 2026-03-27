using FluentMigrator.Runner;
using FoodeApp.SvcAuth.Adapters.Data.Repositories;
using FoodeApp.SvcAuth.Application.Ports;
using FoodeApp.SvcAuth.Domain.Ports;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;

namespace FoodeApp.SvcAuth.Adapters.Data.Extensions;

public static class DataServiceExtensions
{
    public static IServiceCollection AddSvcAuthData(this IServiceCollection services)
    {
        services.AddDbContext<AuthDbContext>((sp, options) =>
        {
            var dataSource = sp.GetRequiredService<NpgsqlDataSource>();
            options.UseNpgsql(dataSource);
        });

        services.AddScoped<IUserWriteRepository, UserWriteRepository>();
        services.AddScoped<IUnitOfWork, UnitOfWork>();
        services.AddScoped<IUserReadRepository, UserReadRepository>();

        services.AddFluentMigratorCore()
            .ConfigureRunner(runner => runner
                .AddPostgres()
                .ScanIn(typeof(DataServiceExtensions).Assembly).For.Migrations())
            .AddLogging(lb => lb.AddFluentMigratorConsole());

        return services;
    }
}
