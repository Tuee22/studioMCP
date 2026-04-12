FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
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
    tar \
    tini \
    unzip \
    wget \
    xz-utils \
    zlib1g-dev \
  && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y --no-install-recommends blender || true

ARG GHC_VERSION=9.12.2
ARG CABAL_VERSION=3.16.0.0
ARG BUILDX_VERSION=v0.32.1
ARG HELM_VERSION=v3.18.6
ARG KIND_VERSION=v0.29.0
ARG KUBECTL_VERSION=v1.33.4
ARG TARGETARCH

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    docker.io \
    skopeo \
  && rm -rf /var/lib/apt/lists/*

RUN if [ -z "${TARGETARCH}" ]; then TARGETARCH="$(dpkg --print-architecture)"; fi && \
    case "${TARGETARCH}" in \
      arm64) export STUDIO_ARCH=arm64 ;; \
      amd64) export STUDIO_ARCH=amd64 ;; \
      *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac && \
    curl --proto '=https' --tlsv1.2 -fsSL https://get-ghcup.haskell.org | \
      BOOTSTRAP_HASKELL_NONINTERACTIVE=1 BOOTSTRAP_HASKELL_MINIMAL=1 sh && \
    export PATH="/root/.ghcup/bin:/root/.cabal/bin:${PATH}" && \
    ghcup install ghc "${GHC_VERSION}" && \
    ghcup set ghc "${GHC_VERSION}" && \
    ghcup install cabal "${CABAL_VERSION}" && \
    ghcup set cabal "${CABAL_VERSION}" && \
    curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${STUDIO_ARCH}/kubectl" && \
    chmod +x /usr/local/bin/kubectl && \
    curl -fsSL -o /usr/local/bin/kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-${STUDIO_ARCH}" && \
    chmod +x /usr/local/bin/kind && \
    curl -fsSL -o /tmp/helm.tgz "https://get.helm.sh/helm-${HELM_VERSION}-linux-${STUDIO_ARCH}.tar.gz" && \
    tar -xzf /tmp/helm.tgz -C /tmp && \
    mv "/tmp/linux-${STUDIO_ARCH}/helm" /usr/local/bin/helm && \
    chmod +x /usr/local/bin/helm && \
    curl -fsSL -o /usr/local/bin/mc "https://dl.min.io/client/mc/release/linux-${STUDIO_ARCH}/mc" && \
    chmod +x /usr/local/bin/mc && \
    mkdir -p /usr/libexec/docker/cli-plugins && \
    curl -fsSL -o /usr/libexec/docker/cli-plugins/docker-buildx "https://github.com/docker/buildx/releases/download/${BUILDX_VERSION}/buildx-${BUILDX_VERSION}.linux-${STUDIO_ARCH}" && \
    chmod +x /usr/libexec/docker/cli-plugins/docker-buildx && \
    rm -rf /tmp/helm.tgz "/tmp/linux-${STUDIO_ARCH}"

ENV LANG="C.UTF-8" \
    LC_ALL="C.UTF-8" \
    PATH="/root/.ghcup/bin:/root/.cabal/bin:/usr/local/bin:${PATH}"

WORKDIR /workspace

COPY . /workspace

RUN mkdir -p /opt/build/studiomcp && \
    cabal update && \
    cabal --builddir=/opt/build/studiomcp build all && \
    cabal --builddir=/opt/build/studiomcp install exe:studiomcp --installdir /usr/local/bin --overwrite-policy=always
ENTRYPOINT ["tini", "--"]
