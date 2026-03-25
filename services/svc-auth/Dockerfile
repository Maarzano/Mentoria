FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

# Copia o projeto compartilhado Kernel (ProjectReference)
COPY shared/kernel-dotnet/src/FoodeApp.Kernel/FoodeApp.Kernel.csproj /shared/kernel-dotnet/src/FoodeApp.Kernel/

# Copia todos os csproj respeitando a estrutura multi-projeto
COPY services/svc-auth/src/FoodeApp.SvcAuth.Domain/FoodeApp.SvcAuth.Domain.csproj                         src/FoodeApp.SvcAuth.Domain/
COPY services/svc-auth/src/FoodeApp.SvcAuth.Application/FoodeApp.SvcAuth.Application.csproj               src/FoodeApp.SvcAuth.Application/
COPY services/svc-auth/src/FoodeApp.SvcAuth.Adapters.Data/FoodeApp.SvcAuth.Adapters.Data.csproj           src/FoodeApp.SvcAuth.Adapters.Data/
COPY services/svc-auth/src/FoodeApp.SvcAuth.Adapters.External/FoodeApp.SvcAuth.Adapters.External.csproj   src/FoodeApp.SvcAuth.Adapters.External/
COPY services/svc-auth/src/FoodeApp.SvcAuth.Adapters.Messaging/FoodeApp.SvcAuth.Adapters.Messaging.csproj src/FoodeApp.SvcAuth.Adapters.Messaging/
COPY services/svc-auth/src/FoodeApp.SvcAuth.Adapters.API/FoodeApp.SvcAuth.Adapters.API.csproj             src/FoodeApp.SvcAuth.Adapters.API/

# Restore usando o projeto de entrada (puxa transitivamente todos os demais)
RUN dotnet restore src/FoodeApp.SvcAuth.Adapters.API/FoodeApp.SvcAuth.Adapters.API.csproj

# Copia o restante dos fontes (svc-auth + Kernel)
COPY services/svc-auth/src/ src/
COPY shared/kernel-dotnet/src/FoodeApp.Kernel/ /shared/kernel-dotnet/src/FoodeApp.Kernel/
RUN dotnet publish src/FoodeApp.SvcAuth.Adapters.API/FoodeApp.SvcAuth.Adapters.API.csproj \
    -c Release -o /app/publish /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app

USER app

COPY --from=build /app/publish/ ./
# AssemblyName no csproj mantém o dll como FoodeApp.SvcAuth.dll
ENTRYPOINT ["dotnet", "FoodeApp.SvcAuth.dll"]
