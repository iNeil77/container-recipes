# Run as: docker run --rm -it --gpus '"device=5"' --ipc=host --ulimit memlock=-1 --ulimit stack=67108864 ineil77/gpt-neox:tagname

FROM nvcr.io/nvidia/cuda:12.4.1-cudnn-devel-ubuntu22.04

SHELL ["/bin/bash", "-c"]

ENV TORCH_CUDA_ARCH_LIST="7.0 7.5 8.0 8.6 8.9 9.0+PTX" \
    PYTHONUNBUFFERED=1 \
    CARGO_HOME="/container/cargo" \
    RUSTUP_HOME="/container/rustup" \
    HF_HUB_ENABLE_HF_TRANSFER=1

# Setup System Utilities
RUN apt update -y \
    && apt upgrade -y \
    && DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends \
        apt-transport-https \
        apt-utils \
        apache2 \
        apache2-bin \
        apache2-data \
        apache2-utils \
        autoconf \
        automake \
        bc \
        bison \
        build-essential \
        ca-certificates \
        check \
        cmake \
        curl \
        dmidecode \
        emacs \
        g++ \
        gcc \
        git \
        gnupg \
        htop \
        iproute2 \
        iputils-ping \
        iputils-tracepath \
        jq \
        kmod \
        libaio-dev \
        libapr1-dev \
        libboost-all-dev \
        libcurl4-openssl-dev \
        libffi-dev \
        libgdbm-dev \
        libglib2.0-0 \
        libgomp1 \
        libibverbs-dev \
        libncurses5-dev \
        libnuma-dev \
        libnuma1 \
        libomp-dev \
        libreadline-dev \
        libsm6 \
        libssl-dev \
        libsubunit-dev \
        libsubunit0 \
        libtest-deep-perl \
        libtool \
        libxext6 \
        libxrender-dev \
        libyaml-dev \
        lsb-release \
        lsof \
        make \
        moreutils \
        net-tools \
        ninja-build \
        openjdk-21-jdk-headless \
        openjdk-21-jre-headless \
        openssh-client \
        openssh-server \
        openssl \
        pkg-config \
        ruby \
        screen \
        software-properties-common \
        sudo \
        tmux \
        traceroute \
        unzip \
        util-linux \
        vim \
        wget \
        zlib1g-dev \
    && apt autoremove -y \
    && apt clean \
    && rm -rf /var/lib/apt/lists/*

# Setup Mamba environment and Rust
RUN wget -O /tmp/Miniforge.sh https://github.com/conda-forge/miniforge/releases/download/24.3.0-0/Miniforge3-24.3.0-0-Linux-x86_64.sh \
    && bash /tmp/Miniforge.sh -b -p /Miniforge \
    && source /Miniforge/etc/profile.d/conda.sh \
    && source /Miniforge/etc/profile.d/mamba.sh \
    && mamba update -y -n base -c defaults mamba \
    && mamba create -y -n GPTNeoX python=3.12 setuptools=69.5.1 cxx-compiler=1.7.0 \
    && mamba activate GPTNeoX \
    && mamba install -y -c conda-forge \
        charset-normalizer \
        gputil \
        ipython \
        mkl \
        mkl-include \
        mpi4py \
        nb_conda_kernels \
        nccl \
        'numpy<2.0.0' \
        pandas \
        rust=1.80.1 \
        scikit-learn \
        wandb \
    && mamba install -y -c pytorch magma-cuda124 \
    && mamba clean -a -f -y

# Install PyTorch
RUN source /Miniforge/etc/profile.d/conda.sh \
    && source /Miniforge/etc/profile.d/mamba.sh \
    && mamba activate GPTNeoX \
    && mamba install -y \
        nvidia/label/cuda-12.4.1::cuda-toolkit \
        nvidia/label/cuda-12.4.1::cuda-runtime \
    && mamba install -y -c pytorch -c nvidia \
        pytorch \
        pytorch-cuda=12.4

# Install optimized NVIDIA Apex
RUN source /Miniforge/etc/profile.d/conda.sh \
    && source /Miniforge/etc/profile.d/mamba.sh \
    && mamba activate GPTNeoX \
    && export MAX_JOBS=$(($(nproc) - 2)) \
    && tmp_apex_path="/tmp/apex" \
    && rm -rf $tmp_apex_path \
    && git clone https://github.com/NVIDIA/apex $tmp_apex_path \
    && cd $tmp_apex_path \
    && git checkout 24.04.01 \
    && pip install -v \
        --disable-pip-version-check \
        --no-cache-dir \
        --no-build-isolation \
        --config-settings "--build-option=--cpp_ext" \
        --config-settings "--build-option=--cuda_ext" \
        --config-settings "--build-option=--permutation_search" \
        --config-settings "--build-option=--xentropy" \
        --config-settings "--build-option=--focal_loss" \
        --config-settings "--build-option=--index_mul_2d" \
        --config-settings "--build-option=--deprecated_fused_adam" \
        --config-settings "--build-option=--deprecated_fused_lamb" \
        --config-settings "--build-option=--fast_layer_norm" \
        --config-settings "--build-option=--fmha" \
        --config-settings "--build-option=--fast_multihead_attn" \
        --config-settings "--build-option=--transducer" \
        --config-settings "--build-option=--nccl_p2p" ./

# Install GPTNeoX dependencies
RUN source /Miniforge/etc/profile.d/conda.sh \
    && source /Miniforge/etc/profile.d/mamba.sh \
    && mamba activate GPTNeoX \
    && pip install 'accelerate>=0.13.2' \
        boto3 \
        camel_converter \
        cdifflib \
        'datasets>=2.6.1' \
        diff_match_patch \
        'evaluate>=0.3.0' \
        'fsspec<2023.10.0' \
        'ftfy>=6.0.1' \
        'git+https://github.com/iNeil77/DeeperSpeed.git@98a03a761d9f94d1c29ed6588493abe727a13f06#egg=deepspeed' \
        'git+https://github.com/EleutherAI/lm_dataformat.git@4eec05349977071bf67fc072290b95e31c8dd836' \
        'huggingface_hub>=0.11.1' \
        hf_transfer \
        jinja2 \
        jsonlines \
        maturin \
        'mosestokenizer==1.0.0' \
        mup \
        ninja \
        nltk \
        openai \
        packaging \
        patchelf \
        peft \
        protobuf \
        py7zr \
        pybind11 \
        regex \
        requests \
        'rouge-score!=0.0.7,!=0.0.8,!=0.1,!=0.1.1' \
        rtpt \
        sacrebleu \
        'sentencepiece!=0.1.92' \
        seqeval \
        six \
        termcolor \
        tiktoken \
        'transformers==4.44.2' \
        wheel

# Install Flash Attention
RUN source /Miniforge/etc/profile.d/conda.sh \
    && source /Miniforge/etc/profile.d/mamba.sh \
    && mamba activate GPTNeoX \
    && export MAX_JOBS=$(($(nproc) - 2)) \
    && pip install --no-cache-dir ninja packaging \
    && pip install flash-attn==2.6.3 --no-build-isolation

# Prepare GPTNeoX and Megatron-LM kernels
RUN source /Miniforge/etc/profile.d/conda.sh \
    && source /Miniforge/etc/profile.d/mamba.sh \
    && mamba activate GPTNeoX \
    && git clone https://github.com/iNeil77/gpt-neox.git /gpt-neox \
    && cd /gpt-neox \
    && python ./megatron/fused_kernels/setup.py install

