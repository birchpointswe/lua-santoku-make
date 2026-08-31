from debian:bookworm-slim

env MAKEFLAGS="-j4"

run apt-get update && apt-get -y install --no-install-recommends \
    git ca-certificates wget unzip inotify-tools \
    gcc g++ make pkg-config \
    luarocks build-essential \
    libreadline-dev \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /usr/share/doc /usr/share/man /usr/share/info \
    && rm -rf /usr/share/locale/*

run luarocks install santoku-make 5.0.5-1 \
    && luarocks install santoku-cli 2.4.4-1 \
    && luarocks install luacheck \
    && rm -rf /root/.cache

entrypoint [ "toku" ]
