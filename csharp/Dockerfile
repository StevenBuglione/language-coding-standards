# Runtime-only image: official base, no quality tools baked in.
# Packages restore during bootstrap from packages.lock.json at pinned versions.
FROM mcr.microsoft.com/dotnet/sdk:9.0

ENV DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1 \
    DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1 \
    DOTNET_GENERATE_ASPNET_CERTIFICATE=false \
    NUGET_PACKAGES=/workspace/.nuget/packages \
    NUGET_HTTP_CACHE_PATH=/workspace/.nuget/http-cache \
    DOTNET_CLI_HOME=/workspace/.dotnet \
    XDG_CACHE_HOME=/workspace/.cache

WORKDIR /workspace
