#!/bin/sh
set -e

cmd=""
port=8080

while getopts "c:p:" opt; do
  case $opt in
    c) cmd="$OPTARG" ;;
    p) port="$OPTARG" ;;
    *) echo "Usage: $0 [-c docker|podman] [-p port] -- [args...]" >&2; exit 1 ;;
  esac
done
shift $((OPTIND - 1))
if [ "$1" = "--" ]; then shift; fi

if [ -z "$cmd" ]; then
  if command -v docker >/dev/null 2>&1; then
    cmd=docker
  elif command -v podman >/dev/null 2>&1; then
    cmd=podman
  else
    echo "Neither docker nor podman found" >&2
    exit 1
  fi
fi

mkdir -p build
$cmd build . --iidfile build/.toku.id
$cmd run -p "$port:8080" -e DB_FILE="$DB_FILE" -ti -v "$(dirname "$0")":/app -w /app --rm $(cat build/.toku.id) "$@"
