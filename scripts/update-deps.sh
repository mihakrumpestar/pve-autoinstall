#!/usr/bin/env bash
# Bump flake.lock and devenv.lock.
#
#   scripts/update-deps.sh [<flake-input>...]
#
# Args are flake input names, passed to `nix flake update`.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

for arg in "$@"; do
  [[ $arg == -* ]] && { printf 'update-deps: %s: input names only\n' "$arg" >&2; exit 2; }
done

nix flake update "$@"
devenv update

printf '\nRun "task verify" before committing.\n'
