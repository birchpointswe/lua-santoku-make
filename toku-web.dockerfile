from debian:bookworm-slim

env MAKEFLAGS="-j4"
env PATH=$PATH:/emsdk/upstream/emscripten
env OPENRESTY_DIR=/usr/local/openresty

run apt-get update && apt-get -y install --no-install-recommends \
    git gnupg ca-certificates wget curl xz-utils python3 \
    && ln -s /usr/bin/python3 /usr/bin/python \
    && rm -rf /var/lib/apt/lists/*

run git clone --depth 1 https://github.com/emscripten-core/emsdk.git \
    && cd emsdk && ./emsdk install latest && ./emsdk activate latest \
    && ln -sf /emsdk/node/*/bin/node /usr/local/bin/node \
    && ln -sf /emsdk/node/*/bin/npm /usr/local/bin/npm \
    && rm -rf /emsdk/downloads /emsdk/.git \
    && find /emsdk -name "*.a" -delete \
    && find /emsdk -name "*.pyc" -delete \
    && rm -rf /emsdk/upstream/emscripten/test \
    && rm -rf /emsdk/upstream/emscripten/site \
    && rm -rf /emsdk/upstream/lib/clang/*/lib/wasi

run wget -O - https://openresty.org/package/pubkey.gpg | apt-key add - \
    && if [ "$(dpkg --print-architecture)" = "arm64" ]; then \
         echo "deb http://openresty.org/package/arm64/debian bookworm openresty" > /etc/apt/sources.list.d/openresty.list; \
       else \
         echo "deb http://openresty.org/package/debian bookworm openresty" > /etc/apt/sources.list.d/openresty.list; \
       fi \
    && apt-get update && apt-get -y install --no-install-recommends \
       gcc g++ make perl pkg-config swig \
       luarocks npm build-essential \
       python3 python3-dev python3-pip python3-venv libpython3-dev \
       libmariadb-dev-compat libxml2-dev libopenblas-dev liblapacke-dev \
       librsvg2-bin imagemagick inotify-tools procps vim xxd \
       openresty \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /usr/share/doc /usr/share/man /usr/share/info \
    && rm -rf /usr/share/locale/*

run wget https://www.sqlite.org/2024/sqlite-autoconf-3470200.tar.gz \
    && tar xf sqlite-autoconf-3470200.tar.gz \
    && cd sqlite-autoconf-3470200 && ./configure && make && make install \
    && cd / && rm -rf sqlite-autoconf-3470200* \
    && strip /usr/local/lib/libsqlite3.so* 2>/dev/null

env XDG_DATA_HOME=/opt
env PATH=/opt/toku/rocks/bin:/opt/toku/luarocks/bin:/opt/toku/lua/bin:$PATH
env TOKU_FG=1

run luarocks install santoku-cli 2.8.0-1 \
    && toku setup \
    && toku luarocks install lua-cjson \
    && toku luarocks install luacheck \
    && rm -rf /opt/toku/src /root/.cache \
    && chmod -R a+rX /opt/toku

run npm -g install tailwindcss @tailwindcss/cli esbuild \
    && npm cache clean --force \
    && rm -rf /root/.npm

run ARCH_DIR=$(if [ "$(dpkg --print-architecture)" = "arm64" ]; then echo "aarch64-linux-gnu"; else echo "x86_64-linux-gnu"; fi) \
    && ln -sv /usr/include/$ARCH_DIR/openblas-pthread /usr/include/$ARCH_DIR/openblas \
    && ln -sv /usr/include/lapacke.h /usr/include/$ARCH_DIR/openblas

entrypoint [ "toku" ]
