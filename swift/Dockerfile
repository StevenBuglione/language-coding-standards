# Runtime-only image: official base, no quality tools baked in.
# Evidence is Linux (this image). Apple platforms are unproven.
# Tools that are not part of the toolchain install during bootstrap,
# never into the image layer.
FROM swift:6.0

ENV XDG_CACHE_HOME=/workspace/.cache

WORKDIR /workspace
