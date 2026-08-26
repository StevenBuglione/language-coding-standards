# Runtime image: official base only, NO quality tools baked in (CONTRACTS §6).
# Every tool installs during the deps phase at the versions pinned in
# verify.sh. The exact-patch bookworm tag matches rust-toolchain.toml's pin,
# so rustup resolves to the preinstalled toolchain and downloads nothing.
# Bump both files together.
FROM rust:1.98.0-bookworm

ENV CARGO_HOME=/workspace/.cargo-home \
    CARGO_TARGET_DIR=/workspace/target \
    # Reproducibility over speed: incremental caches change build outcomes
    # run-to-run and are worthless under deny-warnings CI anyway.
    CARGO_INCREMENTAL=0

WORKDIR /workspace
