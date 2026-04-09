FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

# Copia o projeto compartilhado Kernel (ProjectReference)
COPY shared/kernel-dotnet/src/FoodeApp.Kernel/FoodeApp.Kernel.csproj /shared/kernel-dotnet/src/FoodeApp.Kernel/

# Copia todos os csproj respeitando a estrutura multi-projeto
COPY services/svc-users/src/FoodeApp.Svcusers.Domain/FoodeApp.Svcusers.Domain.csproj                         src/FoodeApp.Svcusers.Domain/
COPY services/svc-users/src/FoodeApp.Svcusers.Application/FoodeApp.Svcusers.Application.csproj               src/FoodeApp.Svcusers.Application/
COPY services/svc-users/src/FoodeApp.Svcusers.Adapters.Data/FoodeApp.Svcusers.Adapters.Data.csproj           src/FoodeApp.Svcusers.Adapters.Data/
COPY services/svc-users/src/FoodeApp.Svcusers.Adapters.External/FoodeApp.Svcusers.Adapters.External.csproj   src/FoodeApp.Svcusers.Adapters.External/
COPY services/svc-users/src/FoodeApp.Svcusers.Adapters.Messaging/FoodeApp.Svcusers.Adapters.Messaging.csproj src/FoodeApp.Svcusers.Adapters.Messaging/
COPY services/svc-users/src/FoodeApp.Svcusers.Adapters.API/FoodeApp.Svcusers.Adapters.API.csproj             src/FoodeApp.Svcusers.Adapters.API/

# Restore usando o projeto de entrada (puxa transitivamente todos os demais)
RUN dotnet restore src/FoodeApp.Svcusers.Adapters.API/FoodeApp.Svcusers.Adapters.API.csproj

# Copia o restante dos fontes (svc-users + Kernel)
COPY services/svc-users/src/ src/
COPY shared/kernel-dotnet/src/FoodeApp.Kernel/ /shared/kernel-dotnet/src/FoodeApp.Kernel/
RUN dotnet publish src/FoodeApp.Svcusers.Adapters.API/FoodeApp.Svcusers.Adapters.API.csproj \
    -c Release -o /app/publish /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app

USER app

COPY --from=build /app/publish/ ./
# AssemblyName no csproj mantém o dll como FoodeApp.Svcusers.dll
ENTRYPOINT ["dotnet", "FoodeApp.Svcusers.dll"]
