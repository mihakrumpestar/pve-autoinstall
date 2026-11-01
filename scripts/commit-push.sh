#!/usr/bin/env bash
# Commit the given paths and push, for the scheduled bump workflows. No-op when
# they did not change.
#
#   scripts/commit-push.sh <message> <path>...
#
# Called by CI only; the identity is the Actions bot.
set -euo pipefail

[[ $# -ge 2 ]] || { echo "usage: commit-push.sh <message> <path>..." >&2; exit 2; }
message=$1
shift

git add -- "$@"
if git diff --cached --quiet; then
  echo "nothing to commit"
  exit 0
fi

git -c user.name='github-actions[bot]' \
  -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
  commit --message "$message"
# A push may land while the gate runs; replay the commit on top of it.
git pull --rebase --quiet origin "$(git rev-parse --abbrev-ref HEAD)"
git push --quiet origin HEAD
