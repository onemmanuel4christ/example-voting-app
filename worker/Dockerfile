# Multi-stage build with pinned images
FROM mcr.microsoft.com/dotnet/sdk:7.0.406 AS build
WORKDIR /source

COPY *.csproj .
RUN dotnet restore

COPY . .
RUN dotnet publish -c release -o /app --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:7.0.16 AS runtime
WORKDIR /app
COPY --from=build /app .

# Run as non-root user
RUN groupadd -r appgroup && useradd -r -g appgroup appuser
RUN chown -R appuser:appgroup /app
USER appuser

ENTRYPOINT ["dotnet", "Worker.dll"]
