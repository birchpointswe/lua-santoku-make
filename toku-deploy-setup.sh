#!/bin/sh
set -eu

tree="${1:?usage: toku-deploy-setup <build-tree> [dist-dir]}"
dist="${2:-$tree/main/dist}"

find "$tree" -type f \( -name "*.o" -o -name "*.a" -o -name "*.link" \) -delete
chgrp -R 0 "$tree"
chmod -R g-w,o-w "$tree"
chmod +x "$dist/run.sh"
mkdir -p "$dist/logs" "$dist/temp"
chgrp 0 "$dist/logs" "$dist/temp"
chmod 0770 "$dist/temp"
ln -sf /dev/stdout "$dist/logs/access.log"
ln -sf /dev/stderr "$dist/logs/error.log"
ldconfig
