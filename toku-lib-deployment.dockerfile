from debian:bookworm-slim

run apt-get update && apt-get -y install --no-install-recommends \
    liblua5.1-0 ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /usr/share/doc /usr/share/man /usr/share/info \
    && rm -rf /usr/share/locale/*

run useradd -r -u 10001 -g 0 -M -d /nonexistent -s /usr/sbin/nologin worker

workdir /app
