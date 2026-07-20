FROM debian:bookworm-slim

WORKDIR /
ARG DEBIAN_FRONTEND=noninteractive
ENV VCPKG_FORCE_SYSTEM_BINARIES=1
RUN apt update -y && \
    apt install --yes --no-install-recommends \
        g++ \
        gcc \
        git \
        curl \
        nasm \
        yasm \
        libgtk-3-dev \
        clang \
        libxcb-randr0-dev \
        libxdo-dev \
        libxfixes-dev \
        libxcb-shape0-dev \
        libxcb-xfixes0-dev \
        libasound2-dev \
        libpam0g-dev \
        libpulse-dev \
        make \
        wget \
        libssl-dev \
        unzip \
        zip \
        sudo \
        libgstreamer1.0-dev \
        libgstreamer-plugins-base1.0-dev \
        ca-certificates \
        ninja-build \
        cmake \
        && rm -rf /var/lib/apt/lists/*

# CMake via apt (Debian 12 tem CMake 3.25+)
# Se precisar de versão específica, use o source tarball com checksum SHA256 fixo:
# RUN wget https://github.com/Kitware/CMake/releases/download/v3.30.6/cmake-3.30.6.tar.gz \
#         -O /tmp/cmake.tar.gz && \
#     sha256sum /tmp/cmake.tar.gz && \  # verificar checksum aqui
#     tar xzf /tmp/cmake.tar.gz -C /tmp && \
#     cd /tmp/cmake-3.30.6 && \
#     ./configure --prefix=/usr/local && make -j$(nproc) && make install

RUN git clone --branch 2023.04.15 --depth=1 https://github.com/microsoft/vcpkg && \
    /vcpkg/bootstrap-vcpkg.sh -disableMetrics && \
    /vcpkg/vcpkg --disable-metrics install libvpx libyuv opus aom

RUN groupadd -r user && \
    useradd -r -g user user --home /home/user && \
    mkdir -p /home/user/onlidesk && \
    chown -R user: /home/user && \
    echo "user ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/user

WORKDIR /home/user
# OnliDesk fork: substitua pelo URL do seu release ou build interno
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs > rustup.sh && \
    chmod +x rustup.sh && \
    ./rustup.sh -y

USER root
ENV HOME=/home/user
COPY ./entrypoint.sh /
ENTRYPOINT ["/entrypoint.sh"]