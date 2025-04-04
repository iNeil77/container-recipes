FROM nvcr.io/nvidia/nemo:25.02.rc6
# Ubuntu 24.04

SHELL ["/bin/bash", "-c"]

ENV GO111MODULE="off" \
    GOPATH="/container/go" \
    JUPYTER_CONFIG_DIR=/run/determined/jupyter/config \
    JUPYTER_DATA_DIR=/run/determined/jupyter/data \
    JUPYTER_RUNTIME_DIR=/run/determined/jupyter/runtime \
    PYTHONFAULTHANDLER=1 \
    PYTHONHASHSEED=0 \
    PYTHONUNBUFFERED=1

# Copy various shell scripts that group dependencies for install
COPY Dockerfile_Scripts /tmp/Dockerfile_Scripts

# Setup System Utilities and Languages: C, C++, Fortran, Haskell, Java, Lisp, Lua, OCaml, Pascal, Perl, R, Ruby and Scala
RUN apt update -yqq \
    && apt upgrade -yqq \
    && DEBIAN_FRONTEND=noninteractive apt install -yqq \
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
    ca-certificates \
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
    gnupg \
    htop \
    hyperfine \
    ibutils \
    ibverbs-providers \
    ibverbs-utils \
    infiniband-diags \
    iotop \
    iproute2 \
    jq \
    krb5-user \
    libaio-dev \
    libapr1-dev \
    libboost-dev \
    libffi-dev \
    libgdbm-dev \
    libgl1 \
    libglib2.0-0 \
    libibverbs-dev \
    libncurses5-dev \
    libnuma-dev \
    libnuma1 \
    libomp-dev \
    libreadline-dev \
    libsm6 \
    libsubunit-dev \
    libsubunit0 \
    libtest-deep-perl \
    libtool \
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
    ruby \
    sbcl \
    scala \
    screen \
    software-properties-common \
    sudo \
    tmux \
    tre-command \
    tree \
    unattended-upgrades \
    unzip \
    util-linux \
    zlib1g-dev \
    && apt autoremove \
    && apt clean \
    && rm -rf /var/lib/apt/lists/*

# Add multiverse, universe and restricted repositories and install additional packages
RUN add-apt-repository -y multiverse \
    && add-apt-repository -y universe \
    && add-apt-repository -y restricted \
    && unattended-upgrade \
    && apt update -yqq \
    && DEBIAN_FRONTEND=noninteractive apt install -yqq nvtop \
    && apt autoremove \
    && apt clean

# Install Google Cloud CLI
RUN curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list \
    && apt-get update -yqq \
    && apt-get install -yqq \
        google-cloud-cli \
        google-cloud-cli-app-engine-go \
        google-cloud-cli-app-engine-java \
        google-cloud-cli-app-engine-python \
        google-cloud-cli-bigtable-emulator \
        google-cloud-cli-cbt \
        google-cloud-cli-cloud-build-local

# Insrall AWS CLI
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip" \
    && unzip /tmp/awscliv2.zip \
    && ./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update \
    && rm -rf /tmp/awscliv2.zip ./aws

# Setup Perl testing dependencies
RUN perl -MCPAN -e 'install Test::Deep' \
    && perl -MCPAN -e 'install Test::Differences' \
    && perl -MCPAN -e 'install Data::Compare'

# Setup R testing dependencies
RUN R -e "install.packages('testthat', repos='http://cran.rstudio.com/')" \
    && R -e "install.packages('devtools', repos='http://cran.rstudio.com/')"

# Setup Php and its testing dependencies
RUN add-apt-repository ppa:ondrej/php \
    && apt update -yqq \
    && DEBIAN_FRONTEND=noninteractive apt install -yqq php8.4 \
    && DEBIAN_FRONTEND=noninteractive apt install -yqq \
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
        php8.4-zip

# Clojure
RUN curl -L -O https://github.com/clojure/brew-install/releases/latest/download/linux-install.sh
RUN chmod +x linux-install.sh
RUN ./linux-install.sh --prefix /container/clojure
ENV PATH="/container/clojure/bin:${PATH}"
RUN clojure -P

# Dart
RUN wget -qO- https://dl-ssl.google.com/linux/linux_signing_key.pub | gpg  --dearmor -o /usr/share/keyrings/dart.gpg
RUN echo 'deb [signed-by=/usr/share/keyrings/dart.gpg arch=amd64] https://storage.googleapis.com/download.dartlang.org/linux/debian stable main' | tee /etc/apt/sources.list.d/dart_stable.list
RUN apt-get update -yqq && apt-get install -yqq dart

# Setup Go, its testing dependencies and go-enry
RUN add-apt-repository -y ppa:longsleep/golang-backports \
    && apt update -yqq \
    && DEBIAN_FRONTEND=noninteractive apt install -yqq golang-1.21 \
    && ln -s /usr/lib/go-1.21/bin/go /usr/bin/go \
    && go get github.com/stretchr/testify/assert \
    && go get github.com/stretchr/testify/mock \
    && go get github.com/stretchr/testify/require

# Setup JS/TS and auxiliary tools
RUN curl -fsSL https://deb.nodesource.com/setup_current.x | bash - \
    && DEBIAN_FRONTEND=noninteractive apt install -y nodejs \
    && npm install -g lodash \
    && npm install -g typescript

# Setup Dlang
RUN wget https://netcologne.dl.sourceforge.net/project/d-apt/files/d-apt.list -O /etc/apt/sources.list.d/d-apt.list \
    && apt update --allow-insecure-repositories \
    && apt -y --allow-unauthenticated install --reinstall d-apt-keyring \
    && apt update \
    && DEBIAN_FRONTEND=noninteractive apt install -yqq dmd-compiler dub

# Setup C# and dotnet runtime
RUN apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 3FA7E0328081BFF6A14DA29AA6A19B38D3D831EF \
    && echo "deb https://download.mono-project.com/repo/ubuntu stable-focal main" | tee /etc/apt/sources.list.d/mono-official-stable.list \
    && apt update -yqq \
    && DEBIAN_FRONTEND=noninteractive apt install -yqq mono-devel \
    && wget https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb \
    && dpkg -i packages-microsoft-prod.deb \
    && rm packages-microsoft-prod.deb \
    && apt update -yqq \
    && DEBIAN_FRONTEND=noninteractive apt install -yqq dotnet-sdk-8.0 dotnet-runtime-8.0

# Setup Swift
RUN curl https://download.swift.org/swift-6.0.3-release/ubuntu2404/swift-6.0.3-RELEASE/swift-6.0.3-RELEASE-ubuntu24.04.tar.gz | tar xz -C /container/
ENV PATH="/container/swift-6.0.3-RELEASE-ubuntu24.04/usr/bin:${PATH}"

# Setup Julia
RUN curl https://julialang-s3.julialang.org/bin/linux/x64/1.11/julia-1.11.3-linux-x86_64.tar.gz | tar xz -C /container/
ENV PATH="/container/julia-1.11.3/bin:${PATH}"

# Install Java testing dependencies
RUN mkdir /container/multipl-e \
    && wget https://repo.mavenlibs.com/maven/org/javatuples/javatuples/1.2/javatuples-1.2.jar -O /container/multipl-e/javatuples-1.2.jar

# Install LLVM
RUN wget https://apt.llvm.org/llvm.sh -O /tmp/llvm.sh \
    && chmod +x /tmp/llvm.sh \
    && /tmp/llvm.sh 20 all \
    && rm -rf /tmp/llvm.sh

# Install Ruby/Rails testing dependencies and GitHub linguist
RUN gem install rails \ 
    && gem install minitest \
    && gem install minitest-reporters \
    && gem install minitest-rails \
    && gem install minitest-spec-rails \
    && gem install minitest-spec-context \
    && gem install minitest-hooks \
    && gem install minitest-retry \
    && gem install rake \
    && gem install activesupport \
    && gem install github-linguist \
    && gem install github-markup \
    && gem install github-pages

# Install GitHub CLI
RUN (type -p wget >/dev/null || (sudo apt update && sudo apt-get install wget -y)) \
    && sudo mkdir -p -m 755 /etc/apt/keyrings \
    && out=$(mktemp) && wget -nv -O$out https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    && cat $out | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
    && sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && sudo apt update \
    && sudo apt install gh -y

# Install Joern CLI
RUN wget https://github.com/joernio/joern/releases/download/v4.0.318/joern-cli.zip -O /tmp/joern-cli.zip \
    && unzip /tmp/joern-cli.zip -d /container/ \
    && rm -rf /tmp/joern-cli.zip

# Install Enry CLI
RUN wget https://github.com/go-enry/enry/releases/download/v1.2.0/enry-v1.2.0-linux-amd64.tar.gz -O /tmp/enry.tar.gz \
    && tar -xzf /tmp/enry.tar.gz -C /usr/local/bin/ \
    && rm -rf /tmp/enry.tar.gz

# NGC images contain user owned files in /usr/lib
RUN chown root:root /usr/lib

# Copy various shell scripts that group dependencies for install
COPY Dockerfile_Scripts /tmp/Dockerfile_Scripts

RUN /tmp/Dockerfile_Scripts/add_det_nobody_user.sh \
    && /tmp/Dockerfile_Scripts/install_libnss_determined.sh

RUN python -m pip install -r /tmp/Dockerfile_Scripts/additional-requirements-torch.txt \
    && python -m pip install -r /tmp/Dockerfile_Scripts/notebook-requirements.txt \
    && jupyter labextension disable "@jupyterlab/apputils-extension:announcements"

RUN rm -r /tmp/*