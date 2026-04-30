FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

# Copia o projeto compartilhado Kernel (ProjectReference)
COPY shared/kernel-dotnet/src/FoodeApp.Kernel/FoodeApp.Kernel.csproj /shared/kernel-dotnet/src/FoodeApp.Kernel/

# Copia todos os csproj respeitando a estrutura multi-projeto
COPY services/svc-users/src/FoodeApp.SvcUsers.Domain/FoodeApp.SvcUsers.Domain.csproj                         src/FoodeApp.SvcUsers.Domain/
COPY services/svc-users/src/FoodeApp.SvcUsers.Application/FoodeApp.SvcUsers.Application.csproj               src/FoodeApp.SvcUsers.Application/
COPY services/svc-users/src/FoodeApp.SvcUsers.Adapters.Data/FoodeApp.SvcUsers.Adapters.Data.csproj           src/FoodeApp.SvcUsers.Adapters.Data/
COPY services/svc-users/src/FoodeApp.SvcUsers.Adapters.External/FoodeApp.SvcUsers.Adapters.External.csproj   src/FoodeApp.SvcUsers.Adapters.External/
COPY services/svc-users/src/FoodeApp.SvcUsers.Adapters.Messaging/FoodeApp.SvcUsers.Adapters.Messaging.csproj src/FoodeApp.SvcUsers.Adapters.Messaging/
COPY services/svc-users/src/FoodeApp.SvcUsers.Adapters.API/FoodeApp.SvcUsers.Adapters.API.csproj             src/FoodeApp.SvcUsers.Adapters.API/

# Restore usando o projeto de entrada (puxa transitivamente todos os demais)
RUN dotnet restore src/FoodeApp.SvcUsers.Adapters.API/FoodeApp.SvcUsers.Adapters.API.csproj

# Copia o restante dos fontes (svc-users + Kernel)
COPY services/svc-users/src/ src/
COPY shared/kernel-dotnet/src/FoodeApp.Kernel/ /shared/kernel-dotnet/src/FoodeApp.Kernel/
RUN dotnet publish src/FoodeApp.SvcUsers.Adapters.API/FoodeApp.SvcUsers.Adapters.API.csproj \
    -c Release -o /app/publish /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app

USER app

COPY --from=build /app/publish/ ./
# AssemblyName no csproj mantém o dll como FoodeApp.Svcusers.dll
ENTRYPOINT ["dotnet", "FoodeApp.Svcusers.dll"]
