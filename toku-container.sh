#!/bin/sh
set -e

image="${TOKU_IMAGE:-toku-web}"
cmd=""
dry=""

while [ $# -gt 0 ]; do
  case "$1" in
    -c) cmd="$2"; shift 2 ;;
    -i) image="$2"; shift 2 ;;
    -n) dry=1; shift ;;
    *) break ;;
  esac
done

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
  elif [ -n "$dry" ]; then
    cmd=docker
  else
    echo "Neither docker nor podman found" >&2
    exit 1
  fi
fi

userns=""
if [ "$cmd" = "podman" ]; then
  userns="--userns=keep-id"
fi

tty_opt="-i"
if [ -t 0 ] && [ -t 1 ]; then
  tty_opt="-ti"
fi

if [ -n "$dry" ]; then
  echo "$cmd run $userns$docker_opts $tty_opt -v $(pwd):/app -w /app --rm $image $*"
  exit 0
fi

script_dir="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
if ! $cmd image exists "$image" 2>/dev/null && ! $cmd images -q "$image" | grep -q .; then
  echo "Image '$image' not found. Build it first:" >&2
  echo "  $cmd build -t $image -f $script_dir/$image.dockerfile ." >&2
  exit 1
fi

$cmd run $userns $docker_opts $tty_opt -v "$(pwd)":/app -w /app --rm "$image" "$@"
