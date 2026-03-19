FROM ubuntu:24.04 AS base

ARG DEBIAN_FRONTEND=noninteractive
ARG GHC_VERSION=9.12.2
ARG CABAL_VERSION=3.16.0.0

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    build-essential \
    ca-certificates \
    curl \
    ffmpeg \
    git \
    gstreamer1.0-libav \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-tools \
    imagemagick \
    jq \
    libffi-dev \
    libgmp-dev \
    libopencv-dev \
    libyaml-dev \
    openjdk-21-jre-headless \
    pkg-config \
    python3 \
    python3-pip \
    sox \
    unzip \
    wget \
    xz-utils \
    zlib1g-dev \
  && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y --no-install-recommends blender || true

RUN curl --proto '=https' --tlsv1.2 -fsSL https://get-ghcup.haskell.org | \
    BOOTSTRAP_HASKELL_NONINTERACTIVE=1 BOOTSTRAP_HASKELL_MINIMAL=1 sh

ENV PATH="/root/.ghcup/bin:/root/.cabal/bin:${PATH}"

RUN ghcup install ghc "${GHC_VERSION}" && \
    ghcup set ghc "${GHC_VERSION}" && \
    ghcup install cabal "${CABAL_VERSION}" && \
    ghcup set cabal "${CABAL_VERSION}"

WORKDIR /workspace

FROM base AS production

COPY . /workspace

RUN cabal update && cabal build exe:studiomcp

# The image is used for both server and inference mode.
# Helm and Skaffold consume the `production` target as the canonical build output.
ENTRYPOINT ["/workspace/docker/entrypoints/start-server.sh"]
