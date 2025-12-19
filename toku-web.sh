#!/bin/sh
set -e

script_dir="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

cmd=""
if [ "$1" = "-c" ]; then
  cmd="$2"
  shift 2
fi

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

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/toku-web"
mkdir -p "$cache_dir"
$cmd build -t toku-web -f "$script_dir"/toku-web.dockerfile . --iidfile "$cache_dir"/image.id
userns=""
if [ "$cmd" = "podman" ]; then
  userns="--userns=keep-id"
fi
$cmd run $userns $docker_opts -ti -v "$(pwd)":/app -w /app --rm $(cat "$cache_dir"/image.id) "$@"
