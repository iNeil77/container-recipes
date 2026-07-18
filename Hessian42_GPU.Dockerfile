# syntax=docker/dockerfile:1.7
# Run as: sudo DOCKER_BUILDKIT=1 docker build -t ineil77/hessian42-gpu-exec:18072026 -f Hessian42_GPU.Dockerfile .

############################
# Stage 1: fetcher
############################
FROM nvcr.io/nvidia/cuda-dl-base:25.06-cuda12.9-devel-ubuntu24.04 AS fetcher

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
 && apt-get update -yqq \
 && DEBIAN_FRONTEND=noninteractive apt-get install -yqq --no-install-recommends \
      ca-certificates curl unzip wget xz-utils

# Swift toolchain (pruned: drop macOS/cross artifacts, docs, static SDK)
RUN mkdir -p /out \
 && curl -fsSL https://download.swift.org/swift-6.0.3-release/ubuntu2404/swift-6.0.3-RELEASE/swift-6.0.3-RELEASE-ubuntu24.04.tar.gz \
    | tar xz -C /out/ \
 && rm -rf \
      /out/swift-6.0.3-RELEASE-ubuntu24.04/usr/lib/swift/pm \
      /out/swift-6.0.3-RELEASE-ubuntu24.04/usr/lib/swift_static \
      /out/swift-6.0.3-RELEASE-ubuntu24.04/usr/share/doc \
      /out/swift-6.0.3-RELEASE-ubuntu24.04/usr/share/man

# Julia
RUN curl -fsSL https://julialang-s3.julialang.org/bin/linux/x64/1.10/julia-1.10.11-linux-x86_64.tar.gz \
    | tar xz -C /out/

# Joern CLI
RUN curl -fsSL -o /tmp/joern-cli.zip \
      https://github.com/joernio/joern/releases/download/v4.0.318/joern-cli.zip \
 && unzip -q /tmp/joern-cli.zip -d /out/ \
 && rm -f /tmp/joern-cli.zip

# Enry CLI
RUN mkdir -p /out/bin \
 && curl -fsSL -o /tmp/enry.tar.gz \
      https://github.com/go-enry/enry/releases/download/v1.2.0/enry-v1.2.0-linux-amd64.tar.gz \
 && tar -xzf /tmp/enry.tar.gz -C /out/bin/ \
 && rm -f /tmp/enry.tar.gz

# AWS CLI v2
RUN curl -fsSL -o /tmp/awscliv2.zip "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
 && unzip -q /tmp/awscliv2.zip -d /tmp \
 && /tmp/aws/install --bin-dir /out/aws-bin --install-dir /out/aws-cli \
 && rm -rf /tmp/awscliv2.zip /tmp/aws

# Clojure (installer writes a self-contained prefix)
RUN curl -fsSL -O https://github.com/clojure/brew-install/releases/latest/download/linux-install.sh \
 && chmod +x linux-install.sh \
 && ./linux-install.sh --prefix /out/clojure \
 && rm -f linux-install.sh

# Java testing dependency
RUN mkdir -p /out/multipl-e \
 && curl -fsSL -o /out/multipl-e/javatuples-1.2.jar \
      https://repo.mavenlibs.com/maven/org/javatuples/javatuples/1.2/javatuples-1.2.jar


############################
# Stage 2: final
############################
FROM nvcr.io/nvidia/cuda-dl-base:25.06-cuda12.9-devel-ubuntu24.04
# Ubuntu 24.04

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV GO111MODULE="off" \
    GOPATH="/container/go" \
    JUPYTER_CONFIG_DIR=/run/determined/jupyter/config \
    JUPYTER_DATA_DIR=/run/determined/jupyter/data \
    JUPYTER_RUNTIME_DIR=/run/determined/jupyter/runtime \
    MAX_JOBS=64 \
    PYTHONFAULTHANDLER=1 \
    PYTHONHASHSEED=0 \
    PYTHONUNBUFFERED=1

# Single copy of the helper scripts, placed just before first use
COPY Dockerfile_Scripts /tmp/Dockerfile_Scripts

# ---------------------------------------------------------------------------
# All third-party repos + one apt update + one install.
# BuildKit cache mounts keep archives and lists out of the layers entirely.
# ---------------------------------------------------------------------------
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
 && apt-get update -yqq \
 && DEBIAN_FRONTEND=noninteractive apt-get install -yqq --no-install-recommends \
      ca-certificates curl gnupg software-properties-common wget \
 && mkdir -p -m 755 /etc/apt/keyrings \
 \
 # --- Ubuntu component repos ---
 && add-apt-repository -y --no-update multiverse \
 && add-apt-repository -y --no-update universe \
 && add-apt-repository -y --no-update restricted \
 \
 # --- PPAs ---
 && add-apt-repository -y --no-update ppa:deki/firejail \
 && add-apt-repository -y --no-update ppa:ondrej/php \
 && add-apt-repository -y --no-update ppa:longsleep/golang-backports \
 \
 # --- Google Cloud SDK ---
 && curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
      | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
      > /etc/apt/sources.list.d/google-cloud-sdk.list \
 \
 # --- Dart ---
 && curl -fsSL https://dl-ssl.google.com/linux/linux_signing_key.pub \
      | gpg --dearmor -o /usr/share/keyrings/dart.gpg \
 && echo 'deb [signed-by=/usr/share/keyrings/dart.gpg arch=amd64] https://storage.googleapis.com/download.dartlang.org/linux/debian stable main' \
      > /etc/apt/sources.list.d/dart_stable.list \
 \
 # --- NodeSource (Node 24.x; node_current.x is not a valid apt path) ---
 && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
      | gpg --dearmor -o /usr/share/keyrings/nodesource.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_24.x nodistro main" \
      > /etc/apt/sources.list.d/nodesource.list \
 \
 # --- D (dlang) ---
 && curl -fsSL https://master.dl.sourceforge.net/project/d-apt/files/d-apt.sources \
      -o /etc/apt/sources.list.d/d-apt.sources \
 && curl -fsSL https://master.dl.sourceforge.net/project/d-apt/files/d-apt.asc \
      -o /etc/apt/keyrings/d-apt.asc \
 \
 # --- Mono (signed-by keyring; apt-key adv is deprecated and fails on 24.04) ---
 && curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x3FA7E0328081BFF6A14DA29AA6A19B38D3D831EF" \
      | gpg --dearmor -o /usr/share/keyrings/mono-official.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/mono-official.gpg] https://download.mono-project.com/repo/ubuntu stable-focal main" \
      > /etc/apt/sources.list.d/mono-official-stable.list \
 \
 # --- Microsoft (dotnet) ---
 && curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
      | gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg \
 && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft-prod.gpg] https://packages.microsoft.com/ubuntu/24.04/prod noble main" \
      > /etc/apt/sources.list.d/microsoft-prod.list \
 \
 # --- GitHub CLI ---
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 \
 # --- d-apt needs its keyring package before the main update ---
 && apt-get update -yqq --allow-insecure-repositories \
 && DEBIAN_FRONTEND=noninteractive apt-get install -yqq --allow-unauthenticated \
      --no-install-recommends --reinstall d-apt-keyring \
 \
 # --- one update, one install ---
 && apt-get update -yqq \
 && apt-get upgrade -yqq \
 && DEBIAN_FRONTEND=noninteractive apt-get install -yqq --no-install-recommends \
      apache2 \
      apache2-bin \
      apache2-data \
      apache2-utils \
      apt-listchanges \
      apt-transport-https \
      apt-utils \
      bat \
      bc \
      bison \
      check \
      daemontools \
      debhelper \
      devscripts \
      dmidecode \
      duf \
      emacs \
      erlang \
      erlang-base \
      fp-compiler \
      ghc \
      htop \
      hyperfine \
      ibutils \
      ibverbs-providers \
      ibverbs-utils \
      infiniband-diags \
      iotop \
      iproute2 \
      jq \
      kmod \
      krb5-user \
      libaio-dev \
      libapr1-dev \
      libboost-dev \
      libffi-dev \
      libfreetype6-dev \
      libgdal-dev \
      libgdbm-dev \
      libgl1 \
      libglib2.0-0 \
      libibverbs-dev \
      libncurses5-dev \
      libnuma-dev \
      libnuma1 \
      libomp-dev \
      libpng-dev \
      libreadline-dev \
      libsm6 \
      libsubunit-dev \
      libsubunit0 \
      libtest-deep-perl \
      libtool \
      libxext6 \
      libxrender-dev \
      libyaml-dev \
      lsof \
      lua-unit \
      lua5.3 \
      moreutils \
      net-tools \
      nfs-common \
      ninja-build \
      nvtop \
      ocaml \
      ocaml-interp \
      openjdk-21-jdk-headless \
      openjdk-21-jre-headless \
      parallel \
      perl \
      pkg-config \
      pybind11-dev \
      r-base \
      racket \
      ripgrep \
      rlwrap \
      rsync \
      ruby-dev \
      sbcl \
      scala \
      screen \
      sudo \
      tmux \
      tre-command \
      tree \
      unattended-upgrades \
      unzip \
      util-linux \
      zlib1g-dev \
      \
      firejail \
      firejail-profiles \
      \
      google-cloud-cli \
      google-cloud-cli-app-engine-go \
      google-cloud-cli-app-engine-java \
      google-cloud-cli-app-engine-python \
      google-cloud-cli-bigtable-emulator \
      google-cloud-cli-cbt \
      google-cloud-cli-cloud-build-local \
      \
      php8.4 \
      php8.4-bcmath \
      php8.4-cgi \
      php8.4-cli \
      php8.4-common \
      php8.4-curl \
      php8.4-fpm \
      php8.4-gd \
      php8.4-gettext \
      php8.4-intl \
      php8.4-mbstring \
      php8.4-mysql \
      php8.4-mysqlnd \
      php8.4-opcache \
      php8.4-pdo \
      php8.4-pgsql \
      php8.4-readline \
      php8.4-sqlite3 \
      php8.4-xml \
      php8.4-zip \
      \
      dart \
      golang-1.21 \
      nodejs \
      dmd-compiler \
      dub \
      mono-devel \
      dotnet-sdk-8.0 \
      dotnet-runtime-8.0 \
      gh \
 && ln -s /usr/lib/go-1.21/bin/go /usr/bin/go \
 && unattended-upgrade \
 && /tmp/Dockerfile_Scripts/apt_cleanup.sh

# ---------------------------------------------------------------------------
# LLVM 20 — named subprojects only, not `all`
# ---------------------------------------------------------------------------
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    curl -fsSL https://apt.llvm.org/llvm.sh -o /tmp/llvm.sh \
 && chmod +x /tmp/llvm.sh \
 && /tmp/llvm.sh 20 clang lldb lld \
 && rm -f /tmp/llvm.sh \
 && /tmp/Dockerfile_Scripts/apt_cleanup.sh

# ---------------------------------------------------------------------------
# Language-level test dependencies (each cleans its own cache in-layer)
# ---------------------------------------------------------------------------

# Perl
RUN perl -MCPAN -e 'install Test::Deep' \
 && perl -MCPAN -e 'install Test::Differences' \
 && perl -MCPAN -e 'install Data::Compare' \
 && rm -rf /root/.cpan /root/.cpanm /tmp/*

# R
RUN R -e "install.packages('testthat', repos='http://cran.rstudio.com/')" \
 && R -e "install.packages('devtools', repos='http://cran.rstudio.com/')" \
 && rm -rf /tmp/Rtmp* /tmp/downloaded_packages

# Go (GOPATH mode: sources must stay, build cache must not)
RUN --mount=type=cache,target=/root/.cache/go-build \
    go get github.com/stretchr/testify/assert \
 && go get github.com/stretchr/testify/mock \
 && go get github.com/stretchr/testify/require

# JS/TS
RUN npm install -g lodash typescript \
 && npm cache clean --force \
 && rm -rf /root/.npm /tmp/*

# Ruby/Rails + GitHub linguist (--no-document skips rdoc/ri)
RUN gem install --no-document \
      rails \
      minitest \
      minitest-reporters \
      minitest-rails \
      minitest-spec-rails \
      minitest-spec-context \
      minitest-hooks \
      minitest-retry \
      rake \
      activesupport \
      github-linguist \
      github-markup \
      github-pages \
 && rm -rf /root/.gem /usr/local/bundle/cache /var/lib/gems/*/cache

# ---------------------------------------------------------------------------
# Artifacts from the fetcher stage
# ---------------------------------------------------------------------------
COPY --from=fetcher /out/clojure                                /container/clojure
COPY --from=fetcher /out/swift-6.0.3-RELEASE-ubuntu24.04        /container/swift-6.0.3-RELEASE-ubuntu24.04
COPY --from=fetcher /out/julia-1.10.11                          /container/julia-1.10.11
COPY --from=fetcher /out/joern-cli                              /container/joern-cli
COPY --from=fetcher /out/multipl-e                              /container/multipl-e
COPY --from=fetcher /out/aws-cli                                /usr/local/aws-cli
COPY --from=fetcher /out/aws-bin/                               /usr/local/bin/
COPY --from=fetcher /out/bin/enry                               /usr/local/bin/enry

# Single consolidated PATH
ENV PATH="/container/clojure/bin:/container/swift-6.0.3-RELEASE-ubuntu24.04/usr/bin:/container/julia-1.10.11/bin:/container/joern-cli:${PATH}"

# Warm the Clojure dependency cache (~/.m2) — intentionally kept
RUN clojure -P

# NGC images contain user-owned files in /usr/lib.
# Scoped find avoids duplicating the entire directory into a new layer.
RUN find /usr/lib \( -not -user root -o -not -group root \) -exec chown root:root {} +

RUN /tmp/Dockerfile_Scripts/add_det_nobody_user.sh \
 && /tmp/Dockerfile_Scripts/install_libnss_determined.sh

RUN --mount=type=cache,target=/root/.cache/pip \
    python -m pip install --no-cache-dir -r /tmp/Dockerfile_Scripts/additional-requirements-torch.txt \
 && python -m pip install --no-cache-dir -r /tmp/Dockerfile_Scripts/notebook-requirements.txt \
 && jupyter labextension disable "@jupyterlab/apputils-extension:announcements" \
 && rm -rf /tmp/Dockerfile_Scripts
