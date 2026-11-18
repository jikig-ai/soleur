#!/usr/bin/env bash
# Phase 0.4 (synthesized fixture): the "before" behaviour of today's bare `git push` from a feature branch in a
# single-branch `--depth 1` clone (what a user on a non-default branch got from syncPush before #12600).
# Usage: probe11.sh [scratch-root]
set -uo pipefail
if [ -n "${1:-}" ]; then BASE=$1; else BASE=$(mktemp -d); trap 'rm -rf "$BASE"' EXIT; fi
R="$BASE/p11-$$"; mkdir -p "$R"; cd "$R" || exit 1
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
g() { git -c user.name=t -c user.email=t@t "$@"; }
git init -q -b main --bare remote.git
g init -q -b main seed; cd seed; mkdir -p knowledge-base; echo a > knowledge-base/a.md; g add -A; g commit -qm init
g remote add origin ../remote.git; g push -q origin main; cd ..
git clone -q --depth 1 "file://$R/remote.git" ws; cd ws
echo "clone: single-branch=$(git config --get remote.origin.fetch)"
g checkout -q -b feature; echo b >> knowledge-base/a.md; g commit -qam "Auto-commit after session"
echo "--- bare git push (default push.default=simple), new local branch, no upstream"
g push 2>&1 | sed -E 's#file://[^ ]*#<url>#g' | head -6; echo "rc=${PIPESTATUS[0]}"
echo "remote feature ref: $(git -C ../remote.git rev-parse --verify --quiet refs/heads/feature || echo absent)"
echo "--- same, when the remote already has a 'feature' branch the clone does not track"
cd ../seed; g checkout -q -b feature; g push -q origin feature; cd ../ws
g push 2>&1 | sed -E 's#file://[^ ]*#<url>#g' | head -6; echo "rc=${PIPESTATUS[0]}"
git --version
