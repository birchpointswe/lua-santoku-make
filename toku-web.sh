#!/bin/sh
set -e

script_dir="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

cmd=""
while getopts "c:" opt; do
  case $opt in
    c) cmd="$OPTARG" ;;
    *) echo "Usage: $0 [-c docker|podman] [docker-opts...] -- [args...]" >&2; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

docker_opts=""
while [ $# -gt 0 ]; do
  if [ "$1" = "--" ]; then
    shift
    break
  fi
  docker_opts="$docker_opts $1"
  shift
done

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
$cmd build -f "$script_dir"/toku-web.dockerfile . --iidfile build/.toku-web.id
$cmd run $docker_opts -ti -v "$(pwd)":/app -w /app --rm $(cat build/.toku-web.id) "$@"
