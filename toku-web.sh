#!/bin/sh
set -e

script_dir="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

if ! command -v nix >/dev/null 2>&1; then
  echo "Nix not found. Install from https://nixos.org/download.html" >&2
  exit 1
fi

nix_opts="--extra-experimental-features nix-command --extra-experimental-features flakes"

if [ $# -eq 0 ]; then
  exec nix develop $nix_opts "$script_dir/toku-web"
else
  exec nix shell $nix_opts "$script_dir/toku-web#default" --command "$@"
fi
