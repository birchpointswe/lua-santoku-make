from debian:bookworm-slim

env MAKE="make -j$(nproc)"
env MAKEFLAGS="-j$(nproc)"

run apt-get update && apt-get -y install --no-install-recommends \
    git gnupg ca-certificates wget curl xz-utils python3

run ln -s /usr/bin/python3 /usr/bin/python

run git clone https://github.com/emscripten-core/emsdk.git && \
    cd emsdk && ./emsdk install latest && ./emsdk activate latest
env PATH=$PATH:/emsdk/upstream/emscripten:/emsdk/node/16.20.0_64bit/bin/

run wget -O - https://openresty.org/package/pubkey.gpg | apt-key add - && \
    if [ "$(dpkg --print-architecture)" = "arm64" ]; then \
      echo "deb http://openresty.org/package/arm64/debian bookworm openresty" > /etc/apt/sources.list.d/openresty.list; \
    else \
      echo "deb http://openresty.org/package/debian bookworm openresty" > /etc/apt/sources.list.d/openresty.list; \
    fi

run apt-get update && apt-get -y install --no-install-recommends \
    gcc g++ make perl pkg-config swig \
    luarocks npm \
    python3 python3-dev python3-pip python3-venv libpython3-dev \
    libmariadb-dev-compat libxml2-dev libopenblas-dev liblapacke-dev \
    librsvg2-bin imagemagick inotify-tools procps vim xxd \
    openresty

run wget https://www.sqlite.org/2024/sqlite-autoconf-3470200.tar.gz && \
    tar xf sqlite-autoconf-3470200.tar.gz && \
    cd sqlite-autoconf-3470200 && ./configure && make && make install && \
    cd / && rm -rf sqlite-autoconf-3470200*

run luarocks install santoku-cli 0.0.327-1 && \
    luarocks install lua-cjson && \
    luarocks install luacheck

run npm -g install tailwindcss @tailwindcss/cli

run ARCH_DIR=$(if [ "$(dpkg --print-architecture)" = "arm64" ]; then echo "aarch64-linux-gnu"; else echo "x86_64-linux-gnu"; fi) && \
    ln -sv /usr/include/$ARCH_DIR/openblas-pthread /usr/include/$ARCH_DIR/openblas && \
    ln -sv /usr/include/lapacke.h /usr/include/$ARCH_DIR/openblas

env OPENRESTY_DIR=/usr/local/openresty
entrypoint [ "toku" ]
