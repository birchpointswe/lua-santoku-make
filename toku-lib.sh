#!/bin/sh
exec "$(dirname "$(readlink -f "$0")")/toku-container.sh" -i toku-lib "$@"
