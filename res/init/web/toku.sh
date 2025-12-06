#!/bin/sh
set -e
podman build . --iidfile .toku.id
podman run --entrypoint /bin/bash -p 8080:8080 -e DB_FILE="$DB_FILE" -ti -v "$(dirname "$0")":/app -w /app --rm $(cat .toku.id) "$@"
