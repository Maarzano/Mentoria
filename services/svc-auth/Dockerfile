FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

# Copia todos os csproj respeitando a estrutura multi-projeto
COPY src/FoodeApp.SvcAuth.Domain/FoodeApp.SvcAuth.Domain.csproj                         src/FoodeApp.SvcAuth.Domain/
COPY src/FoodeApp.SvcAuth.Application/FoodeApp.SvcAuth.Application.csproj               src/FoodeApp.SvcAuth.Application/
COPY src/FoodeApp.SvcAuth.Adapters.Data/FoodeApp.SvcAuth.Adapters.Data.csproj           src/FoodeApp.SvcAuth.Adapters.Data/
COPY src/FoodeApp.SvcAuth.Adapters.External/FoodeApp.SvcAuth.Adapters.External.csproj   src/FoodeApp.SvcAuth.Adapters.External/
COPY src/FoodeApp.SvcAuth.Adapters.Messaging/FoodeApp.SvcAuth.Adapters.Messaging.csproj src/FoodeApp.SvcAuth.Adapters.Messaging/
COPY src/FoodeApp.SvcAuth.Adapters.API/FoodeApp.SvcAuth.Adapters.API.csproj             src/FoodeApp.SvcAuth.Adapters.API/

# Restore usando o projeto de entrada (puxa transitivamente todos os demais)
RUN dotnet restore src/FoodeApp.SvcAuth.Adapters.API/FoodeApp.SvcAuth.Adapters.API.csproj

# Copia o restante dos fontes e publica
COPY src/ src/
RUN dotnet publish src/FoodeApp.SvcAuth.Adapters.API/FoodeApp.SvcAuth.Adapters.API.csproj \
    -c Release -o /app/publish /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app

ENV ASPNETCORE_URLS=http://0.0.0.0:8080
EXPOSE 8080

COPY --from=build /app/publish/ ./
# AssemblyName no csproj mantém o dll como FoodeApp.SvcAuth.dll
ENTRYPOINT ["dotnet", "FoodeApp.SvcAuth.dll"]
