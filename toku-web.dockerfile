from debian:bookworm-slim

env MAKE="make -j$(nproc)"
env MAKEFLAGS="-j$(nproc)"
env PATH=$PATH:/emsdk/upstream/emscripten:/emsdk/node/22.16.0_64bit/bin/
env OPENRESTY_DIR=/usr/local/openresty

run apt-get update && apt-get -y install --no-install-recommends \
    git gnupg ca-certificates wget curl xz-utils python3 \
    && ln -s /usr/bin/python3 /usr/bin/python \
    && rm -rf /var/lib/apt/lists/*

run git clone --depth 1 https://github.com/emscripten-core/emsdk.git \
    && cd emsdk && ./emsdk install latest && ./emsdk activate latest \
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
       libgcc-dev \
       luarocks npm \
       python3 python3-dev python3-pip python3-venv libpython3-dev \
       libmariadb-dev-compat libxml2-dev libopenblas-dev liblapacke-dev \
       librsvg2-bin imagemagick inotify-tools procps vim xxd \
       openresty \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /usr/share/doc /usr/share/man /usr/share/info \
    && rm -rf /usr/share/locale/* \
    && find /usr -name "*.a" ! -name "libc_nonshared.a" ! -name "libpthread_nonshared.a" -delete 2>/dev/null || true

run wget https://www.sqlite.org/2024/sqlite-autoconf-3470200.tar.gz \
    && tar xf sqlite-autoconf-3470200.tar.gz \
    && cd sqlite-autoconf-3470200 && ./configure && make && make install \
    && cd / && rm -rf sqlite-autoconf-3470200* \
    && strip /usr/local/lib/libsqlite3.so* 2>/dev/null || true

run luarocks install santoku-cli 0.0.331-1 \
    && luarocks install lua-cjson \
    && luarocks install luacheck \
    && rm -rf /root/.cache

run npm -g install tailwindcss @tailwindcss/cli \
    && npm cache clean --force \
    && rm -rf /root/.npm

run ARCH_DIR=$(if [ "$(dpkg --print-architecture)" = "arm64" ]; then echo "aarch64-linux-gnu"; else echo "x86_64-linux-gnu"; fi) \
    && ln -sv /usr/include/$ARCH_DIR/openblas-pthread /usr/include/$ARCH_DIR/openblas \
    && ln -sv /usr/include/lapacke.h /usr/include/$ARCH_DIR/openblas

entrypoint [ "toku" ]
