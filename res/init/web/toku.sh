#!/bin/sh
set -e
mkdir -p build
podman build . --iidfile build/.toku.id
podman run -p 8080:8080 -e DB_FILE="$DB_FILE" -ti -v "$(dirname "$0")":/app -w /app --rm $(cat build/.toku.id) "$@"
