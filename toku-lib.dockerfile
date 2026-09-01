from debian:bookworm-slim

env MAKEFLAGS="-j4"

run apt-get update && apt-get -y install --no-install-recommends \
    git ca-certificates wget unzip inotify-tools \
    gcc g++ make pkg-config \
    luarocks build-essential \
    libreadline-dev libopenblas-dev liblapacke-dev \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /usr/share/doc /usr/share/man /usr/share/info \
    && rm -rf /usr/share/locale/*

run ARCH_DIR=$(if [ "$(dpkg --print-architecture)" = "arm64" ]; then echo "aarch64-linux-gnu"; else echo "x86_64-linux-gnu"; fi) \
    && ln -sv /usr/include/$ARCH_DIR/openblas-pthread /usr/include/$ARCH_DIR/openblas \
    && ln -sv /usr/include/lapacke.h /usr/include/$ARCH_DIR/openblas

env XDG_DATA_HOME=/opt
env PATH=/opt/toku/rocks/bin:/opt/toku/luarocks/bin:/opt/toku/lua/bin:$PATH

run luarocks install santoku-make 5.0.12-1 \
    && luarocks install santoku-cli 2.9.0-1 \
    && toku setup \
    && toku luarocks install luacheck \
    && rm -rf /opt/toku/src /root/.cache \
    && chmod -R a+rX /opt/toku

entrypoint [ "toku" ]
