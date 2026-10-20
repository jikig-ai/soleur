#!/usr/bin/env bash
# bare-root-cwd-guard-probe.sh — discoverability probe for the SOLEUR_BARE_ROOT_CWD
# session-start marker (#10383). Builds a throwaway bare-root-shaped fixture under a
# mktemp dir, runs .claude/hooks/bare-root-cwd-guard.sh against it, and prints whatever
# the guard prints (the marker on this host's layout). Runs in seconds, needs no
# credentials, cleans up after itself. Exit status is always 0 — the probe is a
# discoverability surface, not a gate.
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
GUARD="$REPO_ROOT/.claude/hooks/bare-root-cwd-guard.sh"
if [[ ! -x "$GUARD" ]]; then
  echo "probe: guard not executable at $GUARD" >&2
  exit 0
fi

TMP="$(mktemp -d 2>/dev/null)" || { echo "probe: mktemp failed" >&2; exit 0; }
trap 'rm -rf "$TMP"' EXIT

unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
  GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_CONFIG_NOSYSTEM GIT_CONFIG_GLOBAL
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME="Soleur Probe" GIT_AUTHOR_EMAIL="probe@example.com"
export GIT_COMMITTER_NAME="Soleur Probe" GIT_COMMITTER_EMAIL="probe@example.com"
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false

(
  cd "$TMP" 2>/dev/null || exit 0
  git init -q 2>/dev/null || { echo "probe: git init failed" >&2; exit 0; }
  t=$(git hash-object -t tree -w /dev/null 2>/dev/null) || exit 0
  c=$(git commit-tree "$t" -m seed 2>/dev/null) || exit 0
  git update-ref refs/heads/main "$c" 2>/dev/null || exit 0
  git symbolic-ref HEAD refs/heads/main 2>/dev/null || exit 0
  git config core.bare true 2>/dev/null || exit 0
)

bash "$GUARD" "$TMP" || true
exit 0
