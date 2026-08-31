from debian:bookworm-slim

env OPENRESTY_DIR=/usr/local/openresty

run apt-get update \
    && apt-get -y install --no-install-recommends gnupg wget ca-certificates \
    && wget -O - https://openresty.org/package/pubkey.gpg | apt-key add - \
    && if [ "$(dpkg --print-architecture)" = "arm64" ]; then \
         echo "deb http://openresty.org/package/arm64/debian bookworm openresty" > /etc/apt/sources.list.d/openresty.list; \
       else \
         echo "deb http://openresty.org/package/debian bookworm openresty" > /etc/apt/sources.list.d/openresty.list; \
       fi \
    && apt-get update && apt-get -y install --no-install-recommends openresty \
    && apt-get purge -y gnupg wget \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /usr/share/doc /usr/share/man /usr/share/info \
    && rm -rf /usr/share/locale/*

run useradd -r -u 10001 -g 0 -M -d /nonexistent -s /usr/sbin/nologin worker

copy toku-deploy-setup.sh /usr/local/bin/toku-deploy-setup
run chmod 0755 /usr/local/bin/toku-deploy-setup

workdir /app

cmd ["sh", "-c", "umask 002; exec ./run.sh --fg"]
