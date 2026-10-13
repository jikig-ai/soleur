#!/usr/bin/env bash
# flip.sh FLAG_ENV_VARS must list exactly the RUNTIME_FLAGS in apps/web-platform/lib/feature-flags/server.ts,
# with the same FLAG_* env names. The two were hand-synced and drifted three times (#4923, #6182, #6526)
# and again on #4671: a flag missing from flip.sh cannot be flipped by the operator tooling ("unknown flag").
set -uo pipefail
REPO_ROOT="$(git rev-parse --show-toplevel)"
# Repo-relative argv literals (not $REPO_ROOT-built paths): the affected-set derive reads the
# literals as edges, so a change to either file selects this suite without a runner-index edit.
cd "$REPO_ROOT" || exit 1
FLIP="plugins/soleur/skills/flag-set-role/scripts/flip.sh"
SERVER="apps/web-platform/lib/feature-flags/server.ts"
test -r plugins/soleur/skills/flag-set-role/scripts/flip.sh -a -r apps/web-platform/lib/feature-flags/server.ts || { echo "flip-flag-map-parity: FAIL — flip.sh or server.ts missing"; exit 1; }
MIN_FLAGS=12

flip_pairs="$(sed -n '/^declare -A FLAG_ENV_VARS=(/,/^)/p' "$FLIP" | sed -n 's/^[[:space:]]*\["\([^"]*\)"\]="\(FLAG_[A-Z0-9_]*\)".*$/\1=\2/p' | LC_ALL=C sort)"
# RUNTIME_FLAGS block: `"name": "FLAG_X",` or `name: "FLAG_X",` (bare key), comments stripped by the anchored pattern.
server_pairs="$(sed -n '/^const RUNTIME_FLAGS = {/,/^} as const;/p' "$SERVER" | sed -n 's/^[[:space:]]*"\{0,1\}\([a-z][a-z0-9-]*\)"\{0,1\}:[[:space:]]*"\(FLAG_[A-Z0-9_]*\)",.*$/\1=\2/p' | LC_ALL=C sort)"

n_flip="$(printf '%s\n' "$flip_pairs" | grep -c . || true)"
n_server="$(printf '%s\n' "$server_pairs" | grep -c . || true)"

if [[ "$n_flip" -lt "$MIN_FLAGS" || "$n_server" -lt "$MIN_FLAGS" ]]; then
  printf 'flip-flag-map-parity: FAIL — extraction found flip=%s server=%s (floor %s); the extractor is broken, not the maps\n' "$n_flip" "$n_server" "$MIN_FLAGS"
  exit 1
fi

only_flip="$(comm -23 <(printf '%s\n' "$flip_pairs") <(printf '%s\n' "$server_pairs"))"
only_server="$(comm -13 <(printf '%s\n' "$flip_pairs") <(printf '%s\n' "$server_pairs"))"
if [[ -n "$only_flip$only_server" ]]; then
  printf 'flip-flag-map-parity: FAIL — flip.sh FLAG_ENV_VARS and server.ts RUNTIME_FLAGS disagree\n'
  [[ -n "$only_flip" ]] && printf '  only in flip.sh:\n%s\n' "$only_flip"
  [[ -n "$only_server" ]] && printf '  only in server.ts (add to flip.sh FLAG_ENV_VARS):\n%s\n' "$only_server"
  exit 1
fi
printf 'flip-flag-map-parity: PASS (%s flags)\n' "$n_flip"
