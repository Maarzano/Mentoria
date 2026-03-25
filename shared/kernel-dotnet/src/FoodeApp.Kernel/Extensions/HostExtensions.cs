using dotenv.net;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Configuration;
using System.Text.Json;

namespace FoodeApp.Kernel.Extensions;

public static class HostExtensions
{
    /// <summary>
    /// Procura arquivo .env subindo a árvore de diretórios a partir do ContentRoot
    /// e carrega as variáveis no processo (sobrescrevendo existentes).
    /// Permite que `dotnet run` funcione sem precisar do proj.ps1.
    /// </summary>
    public static WebApplicationBuilder AddFoodeAppEnv(this WebApplicationBuilder builder)
    {
        var effectiveEnvironment = Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT")
                                   ?? builder.Environment.EnvironmentName;

        var repoRoot = FindRepoRoot(builder.Environment.ContentRootPath);
        if (repoRoot is null)
            return builder;

        var envFile = Path.Combine(repoRoot, ".env");
        if (File.Exists(envFile))
        {
            DotEnv.Load(new DotEnvOptions(
                envFilePaths: [envFile],
                overwriteExistingVars: true
            ));
        }

        ApplyNormalizedConfiguration(builder, repoRoot, effectiveEnvironment);

        builder.Configuration.AddEnvironmentVariables();

        return builder;
    }

    private static void ApplyNormalizedConfiguration(
        WebApplicationBuilder builder,
        string repoRoot,
        string effectiveEnvironment)
    {
        var serviceName = builder.Configuration["Observability:ServiceName"];
        if (string.IsNullOrWhiteSpace(serviceName))
            return;

        var isDevelopment = string.Equals(effectiveEnvironment, "Development", StringComparison.OrdinalIgnoreCase);

        ServiceConfig? service = null;
        if (isDevelopment)
        {
            var registry = LoadRegistry(repoRoot);
            if (registry?.Services is not null)
                registry.Services.TryGetValue(serviceName, out service);
        }

        var servicePort = FirstOrDefault(
            Environment.GetEnvironmentVariable(ToEnvServicePortKey(serviceName)),
            service is not null && service.Port > 0 ? service.Port.ToString() : null);
        var databaseName = FirstOrDefault(
            service?.Database is not null ? Environment.GetEnvironmentVariable(service.Database) : null,
            builder.Configuration["Database:Database"]);

        var normalized = new Dictionary<string, string?>
        {
            ["Database:Host"] = Environment.GetEnvironmentVariable("POSTGRES_HOST"),
            ["Database:Port"] = Environment.GetEnvironmentVariable("POSTGRES_PORT"),
            ["Database:Database"] = databaseName,
            ["Database:Username"] = Environment.GetEnvironmentVariable("POSTGRES_USER"),
            ["Database:Password"] = Environment.GetEnvironmentVariable("POSTGRES_PASSWORD"),
            ["Observability:OtlpEndpoint"] = Environment.GetEnvironmentVariable("OTEL_EXPORTER_OTLP_ENDPOINT"),
            ["Observability:OtlpProtocol"] = Environment.GetEnvironmentVariable("OTEL_EXPORTER_OTLP_PROTOCOL"),
            ["Observability:Environment"] = Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT") ?? builder.Environment.EnvironmentName,
            ["Observability:ServiceName"] = serviceName
        };

        builder.Configuration.AddInMemoryCollection(normalized!);

        if (isDevelopment && !string.IsNullOrWhiteSpace(servicePort))
        {
            var urls = $"http://localhost:{servicePort}";
            builder.Configuration["ASPNETCORE_URLS"] = urls;
            builder.WebHost.UseSetting(WebHostDefaults.ServerUrlsKey, urls);
        }

        builder.WebHost.UseSetting(WebHostDefaults.EnvironmentKey, effectiveEnvironment);
    }

    private static string? FirstOrDefault(params string?[] values)
    {
        foreach (var value in values)
        {
            if (!string.IsNullOrWhiteSpace(value))
                return value;
        }

        return null;
    }

    private static string ToEnvServicePortKey(string serviceName) =>
        serviceName.Replace('-', '_').ToUpperInvariant() + "_PORT";

    private static RegistryRoot? LoadRegistry(string repoRoot)
    {
        var registryPath = Path.Combine(repoRoot, "infra", "local", "services.json");
        if (!File.Exists(registryPath))
            return null;

        return JsonSerializer.Deserialize<RegistryRoot>(
            File.ReadAllText(registryPath),
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
    }

    private static string? FindRepoRoot(string startDir)
    {
        var dir = new DirectoryInfo(startDir);
        while (dir is not null)
        {
            var registry = Path.Combine(dir.FullName, "infra", "local", "services.json");
            if (File.Exists(registry))
                return dir.FullName;
            dir = dir.Parent;
        }

        return null;
    }

    private sealed class RegistryRoot
    {
        public Dictionary<string, ServiceConfig> Services { get; set; } = [];
    }

    private sealed class ServiceConfig
    {
        public int Port { get; set; }
        public string? Database { get; set; }
    }
}
