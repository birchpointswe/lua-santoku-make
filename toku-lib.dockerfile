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

env XDG_DATA_HOME=/opt
env PATH=/opt/toku/rocks/bin:/opt/toku/luarocks/bin:/opt/toku/lua/bin:$PATH

run luarocks install santoku-cli 2.8.0-1 \
    && toku setup \
    && toku luarocks install luacheck \
    && rm -rf /opt/toku/src /root/.cache \
    && chmod -R a+rX /opt/toku

entrypoint [ "toku" ]
