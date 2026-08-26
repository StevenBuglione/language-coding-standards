# Runtime-only image: official base, no quality tools baked in.
# Every tool installs during the `deps` phase from package.json/pnpm-lock.yaml.
# `-bookworm` (not -slim) because bookworm-slim ships without git, which the
# container preamble and the deps-hygiene lockfile guard both need; keeping git
# in the image buys parity between local runs and CI containers.
FROM node:24-bookworm

ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0 \
    # Hermetic pnpm store: caches stay inside the mounted workspace, gitignored,
    # so they neither leak outside the workspace nor enter image layers.
    npm_config_store_dir=/workspace/.pnpm-store \
    XDG_CACHE_HOME=/workspace/.cache

WORKDIR /workspace
