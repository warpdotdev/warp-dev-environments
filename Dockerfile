FROM debian:trixie-slim

# =============================================================================
# VERSION CONFIGURATION
# =============================================================================
ARG NODE_VERSION=24.0.0
ARG BUN_VERSION=1.3.9
ARG GO_VERSION=1.23.4
ARG RUST_VERSION=1.83.0
ARG JAVA_VERSION=21
ARG DOTNET_VERSION=8.0
ARG RUBY_VERSION=3.3

# =============================================================================
# INSTALL FLAGS
# =============================================================================
ARG INSTALL_BUN=false
ARG INSTALL_RUST=false
ARG INSTALL_GO=false
ARG INSTALL_JAVA=false
ARG INSTALL_DOTNET=false
ARG INSTALL_RUBY=false
ARG INSTALL_BROWSERS=false
ARG INSTALL_CODING_AGENTS=false
# Docker client tooling is installed by default so `docker` and `docker compose`
# are ready to use in every image. Set to "false" to build a slimmer image.
ARG INSTALL_DOCKER=true
ARG LANGUAGES=""

# =============================================================================
# DOCKER TOOLING VERSIONS
# =============================================================================
ARG DOCKER_VERSION=27.5.1
ARG DOCKER_COMPOSE_VERSION=v2.32.4
ARG DOCKER_BUILDX_VERSION=v0.19.3

# Base dependencies
RUN apt-get update && apt-get install -y \
    curl ca-certificates build-essential git \
 && rm -rf /var/lib/apt/lists/*

# Node.js (always installed)
RUN set -eux; \
    dpkgArch="$(dpkg --print-architecture)"; \
    case "${dpkgArch##*-}" in \
      amd64) ARCH='x64';; \
      arm64) ARCH='arm64';; \
    esac; \
    curl --proto '=https' --tlsv1.2 -fsSLO --compressed "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-$ARCH.tar.xz" && \
    tar -xJf node-v${NODE_VERSION}-linux-$ARCH.tar.xz -C /usr/local --strip-components=1 --no-same-owner && \
    rm node-v${NODE_VERSION}-linux-$ARCH.tar.xz && \
    ln -s /usr/local/bin/node /usr/local/bin/nodejs && \
    npm install -g corepack && \
    corepack enable && \
    node --version && \
    npm --version

# Python (always installed)
RUN apt-get update && apt-get install -y \
      python3 python3-pip python3-venv && \
    ln -sf /usr/bin/python3 /usr/bin/python && \
    rm -rf /var/lib/apt/lists/* && \
    python --version

# uv + uvx (Python package/project manager)
RUN curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR=/usr/local/bin sh && \
    uv --version

# Docker CLI + Compose plugin + Buildx plugin (client tools only).
# Only the client binaries are installed; a Docker daemon is provided by the
# sandbox host at runtime (e.g. Docker-routed Warp hosted sandboxes). This makes
# `docker`, `docker compose`, and the standalone `docker-compose` command
# available out of the box so customers don't have to install them via setup
# commands.
RUN if [ "$INSTALL_DOCKER" = "true" ]; then \
      set -eux; \
      dpkgArch="$(dpkg --print-architecture)"; \
      case "${dpkgArch}" in \
        amd64) DOCKER_ARCH='x86_64'; PLUGIN_ARCH='x86_64'; BUILDX_ARCH='linux-amd64';; \
        arm64) DOCKER_ARCH='aarch64'; PLUGIN_ARCH='aarch64'; BUILDX_ARCH='linux-arm64';; \
        *) echo "Unsupported architecture for Docker: ${dpkgArch}" >&2; exit 1;; \
      esac; \
      # Docker CLI: extract only the `docker` client binary from the static bundle. \
      curl --proto '=https' --tlsv1.2 -fsSLO "https://download.docker.com/linux/static/stable/${DOCKER_ARCH}/docker-${DOCKER_VERSION}.tgz"; \
      tar -xzf "docker-${DOCKER_VERSION}.tgz" --strip-components=1 -C /usr/local/bin docker/docker; \
      rm "docker-${DOCKER_VERSION}.tgz"; \
      mkdir -p /usr/local/lib/docker/cli-plugins; \
      # Compose v2, available both as `docker compose` and standalone `docker-compose`. \
      curl --proto '=https' --tlsv1.2 -fsSL -o /usr/local/lib/docker/cli-plugins/docker-compose \
        "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-linux-${PLUGIN_ARCH}"; \
      chmod +x /usr/local/lib/docker/cli-plugins/docker-compose; \
      ln -s /usr/local/lib/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose; \
      # Buildx (used by `docker buildx` and `docker compose build`). \
      curl --proto '=https' --tlsv1.2 -fsSL -o /usr/local/lib/docker/cli-plugins/docker-buildx \
        "https://github.com/docker/buildx/releases/download/${DOCKER_BUILDX_VERSION}/buildx-${DOCKER_BUILDX_VERSION}.${BUILDX_ARCH}"; \
      chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx; \
      docker --version && \
      docker compose version && \
      docker-compose version && \
      docker buildx version ; \
    fi

# Bun
RUN if [ "$INSTALL_BUN" = "true" ]; then \
      apt-get update && apt-get install -y unzip && \
      rm -rf /var/lib/apt/lists/* && \
      dpkgArch="$(dpkg --print-architecture)"; \
      case "${dpkgArch##*-}" in \
        amd64) ARCH='x64';; \
        arm64) ARCH='aarch64';; \
      esac; \
      curl --proto '=https' --tlsv1.2 -fsSLO "https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/bun-linux-$ARCH.zip" && \
      unzip bun-linux-$ARCH.zip -d /tmp/bun && \
      mv /tmp/bun/bun-linux-$ARCH/bun /usr/local/bin/bun && \
      chmod +x /usr/local/bin/bun && \
      rm -rf bun-linux-$ARCH.zip /tmp/bun && \
      bun --version ; \
    fi

# Rust
RUN if [ "$INSTALL_RUST" = "true" ]; then \
      echo 'export RUSTUP_HOME=/usr/local/rustup' >> /etc/profile.d/rust.sh && \
      echo 'export CARGO_HOME=/usr/local/cargo' >> /etc/profile.d/rust.sh && \
      echo 'export PATH=/usr/local/cargo/bin:$PATH' >> /etc/profile.d/rust.sh && \
      . /etc/profile.d/rust.sh && \
      curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path --profile minimal --default-toolchain $RUST_VERSION && \
      chmod -R a+w $RUSTUP_HOME $CARGO_HOME && \
      rustc --version && \
      cargo --version ; \
    fi

# Go
RUN if [ "$INSTALL_GO" = "true" ]; then \
      set -eux; \
      dpkgArch="$(dpkg --print-architecture)"; ARCH="${dpkgArch##*-}"; \
      curl --proto '=https' --tlsv1.2 -fsSLO https://go.dev/dl/go${GO_VERSION}.linux-$ARCH.tar.gz && \
      tar -C /usr/local -xzf go${GO_VERSION}.linux-$ARCH.tar.gz && \
      rm go${GO_VERSION}.linux-$ARCH.tar.gz && \
      echo 'export PATH=/usr/local/go/bin:$PATH' >> /etc/profile.d/go.sh && \
      . /etc/profile.d/go.sh && \
      go version ; \
    fi

# Java (Eclipse Temurin) + Maven + Gradle
RUN if [ "$INSTALL_JAVA" = "true" ]; then \
      apt-get update && apt-get install -y wget apt-transport-https gnupg && \
      wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor -o /usr/share/keyrings/adoptium.gpg && \
      echo "deb [signed-by=/usr/share/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb $(. /etc/os-release && echo $VERSION_CODENAME) main" > /etc/apt/sources.list.d/adoptium.list && \
      apt-get update && apt-get install -y temurin-${JAVA_VERSION}-jdk maven gradle && \
      rm -rf /var/lib/apt/lists/* && \
      java --version && \
      mvn --version && \
      gradle --version ; \
    fi

# .NET SDK
RUN if [ "$INSTALL_DOTNET" = "true" ]; then \
      apt-get update && apt-get install -y wget libicu-dev && \
      dpkgArch="$(dpkg --print-architecture)"; \
      case "${dpkgArch}" in \
        amd64) DOTNET_ARCH='x64';; \
        arm64) DOTNET_ARCH='arm64';; \
      esac; \
      wget https://dot.net/v1/dotnet-install.sh -O /tmp/dotnet-install.sh && \
      chmod +x /tmp/dotnet-install.sh && \
      /tmp/dotnet-install.sh --channel ${DOTNET_VERSION} --install-dir /usr/share/dotnet --architecture $DOTNET_ARCH && \
      ln -s /usr/share/dotnet/dotnet /usr/bin/dotnet && \
      rm /tmp/dotnet-install.sh && \
      rm -rf /var/lib/apt/lists/* && \
      dotnet --version ; \
    fi

# Ruby + Bundler
RUN if [ "$INSTALL_RUBY" = "true" ]; then \
      apt-get update && apt-get install -y ruby-full && \
      gem install bundler && \
      rm -rf /var/lib/apt/lists/* && \
      ruby --version && \
      bundler --version ; \
    fi

# Browsers (Chromium + Firefox)
RUN if [ "$INSTALL_BROWSERS" = "true" ]; then \
      apt-get update && apt-get install -y \
        wget \
        libdbus-glib-1-2 \
        --no-install-recommends chromium && \
      ln -sf /usr/bin/chromium /usr/local/bin/google-chrome && \
      dpkgArch="$(dpkg --print-architecture)"; \
      case "$dpkgArch" in \
        amd64) FF_OS='linux64';; \
        arm64) FF_OS='linux64-aarch64';; \
      esac && \
      wget -q -O firefox.tar.xz "https://download.mozilla.org/?product=firefox-latest&os=$FF_OS&lang=en-US" && \
      tar -xf firefox.tar.xz -C /opt && \
      ln -s /opt/firefox/firefox /usr/local/bin/firefox && \
      rm firefox.tar.xz && \
      rm -rf /var/lib/apt/lists/* && \
      echo "Chromium version:" && chromium --version && \
      echo "Firefox version:" && firefox --version ; \
    fi

# Coding Agent CLIs
RUN if [ "$INSTALL_CODING_AGENTS" = "true" ]; then \
      npm install -g \
        @anthropic-ai/claude-code \
        @openai/codex \
        @google/gemini-cli && \
      curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null && \
      chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg && \
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list && \
      apt-get update && apt-get install -y --no-install-recommends gh && \
      rm -rf /var/lib/apt/lists/* && \
      echo "Installed coding agent CLIs:" && \
      claude --version && \
      codex --version && \
      gemini --version && \
      gh --version ; \
    fi

LABEL languages="${LANGUAGES}"
