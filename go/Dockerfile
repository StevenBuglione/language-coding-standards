# Runtime-only image: official base, no quality tools baked in.
# Every tool installs during the `deps` phase at versions pinned in verify.sh.
FROM golang:1.26-bookworm

ENV GOTOOLCHAIN=local \
    # Swift-style pinning: the image tag IS the toolchain. local forbids the
    # go command from silently downloading another toolchain mid-run.
    GOPATH=/workspace/.gopath \
    GOCACHE=/workspace/.gocache \
    GOMODCACHE=/workspace/.gomodcache \
    GOLANGCI_LINT_CACHE=/workspace/.golangci-cache \
    XDG_CACHE_HOME=/workspace/.cache \
    PATH=/workspace/.gopath/bin:${PATH}

WORKDIR /workspace
