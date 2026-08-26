# Runtime-only image: official base, no quality tools baked in.
# Every tool installs during the `deps` phase from pyproject.toml/uv.lock.
FROM python:3.13-slim

# Dependency manager only — every QUALITY tool installs from pyproject/uv.lock.
COPY --from=ghcr.io/astral-sh/uv:0.12.6 /uv /usr/local/bin/uv

ENV UV_LINK_MODE=copy \
    UV_COMPILE_BYTECODE=0 \
    # Hermetic: never fetch a managed interpreter; use the image's CPython.
    UV_PYTHON_DOWNLOADS=never \
    # Tool caches stay inside the mounted workspace, gitignored, so they
    # neither leak outside the workspace nor enter image layers.
    UV_CACHE_DIR=/workspace/.uv-cache \
    XDG_CACHE_HOME=/workspace/.cache

WORKDIR /workspace
