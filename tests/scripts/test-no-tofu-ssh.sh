#!/usr/bin/env bash
# Guard 1 (#7226 / #5914, ADR-237): no tracked file configures an SSH client to trust
# whatever host key the peer presents.
#
# PROPERTY. Outside the allow-list below, no file in the universe:
#   * sets StrictHostKeyChecking to accept-new, no, off or false (ssh parses `false` as
#     `off`);
#   * points UserKnownHostsFile at /dev/null (or `none`), which discards the pin;
#   * sends keyscan output into a file: a stdout redirect, an append, `&>`, a pipe into
#     tee, or any pipe on a line that also names the known-hosts file. A keyscan captured
#     into a variable with command substitution and then validated is not a known-hosts
#     write and is not flagged (stderr-only redirects such as 2>/dev/null are ignored).
# The match is case-insensitive and covers every spelling: `-o K=V`, `-oK=V`,
# `-o "K V"`, ssh_config `K V`, `K: V`, TS/JSON string literals and GIT_SSH_COMMAND
# strings. GlobalKnownHostsFile=/dev/null is ALLOWED: it removes a trust source, where
# the user-file form removes the pin.
#
# UNIVERSE. `git ls-files --cached --others --exclude-standard` (tracked files plus new
# files not yet added, so a local run sees the same thing CI will) minus
# knowledge-base/**, where docs quote the old literals on purpose. Binary files are
# skipped. A hit is one matching LINE.
#
# ALLOW-LIST. `path|expected-count|reason`. Each entry must hit EXACTLY its count: a
# zero-hit entry is RED (a stale exemption is an invisible hole), and so is a count
# that grew. There is no stored hash; the allow-list is anchored by review of this file
# (CODEOWNERS).
#
# Test files that need a literal build it by concatenation so it never counts here.
#
# Banned spellings, as documentation. Each of the next 5 lines is one hit of this
# script against itself, which is the `self` allow-list count:
#   ssh -o StrictHostKeyChecking=accept-new host
#   ssh -oStrictHostKeyChecking=no -o "StrictHostKeyChecking off" host
#   ssh_config:  UserKnownHostsFile /dev/null
#   GIT_SSH_COMMAND="ssh -o UserKnownHostsFile=/dev/null"
#   ssh-keyscan host >> known_hosts
#
# Env:
#   NO_TOFU_ROOT       tree to scan (default: the git toplevel containing this script).
#   NO_TOFU_MIN_FILES  scanned-file floor (default 1000; the real tree is ~5k files).
#                      An enumeration that silently returns nothing must not read green.
#
# Mutation harness: tests/scripts/test-no-tofu-ssh-mutation.sh.
set -euo pipefail

SELF="${BASH_SOURCE[0]}"
SELF_DIR="$(cd "$(dirname "$SELF")" && pwd)"
SELF_REL="tests/scripts/test-no-tofu-ssh.sh"
ROOT="${NO_TOFU_ROOT:-$(git -C "$SELF_DIR" rev-parse --show-toplevel)}"
MIN_FILES="${NO_TOFU_MIN_FILES:-1000}"

# --- The allow-list (path|expected-count|reason). Edit counts HERE. -----------------
ALLOWLIST="$(cat <<'EOF'
apps/web-platform/infra/git-data-ownership.test.sh|1|throwaway local container on 127.0.0.1:2222, never a real host
apps/web-platform/infra/infra-config-gate.test.sh|1|detector fixture string inside the infra-config-gate test, never executed
apps/web-platform/server/git-auth.ts|1|TOFU_FALLBACK_OPTS: the single transitional accept-new arm (#5914 removes it and this line)
tests/scripts/test-no-tofu-ssh.sh|5|this guard's own banned-spellings documentation block
EOF
)"

# --- Patterns (POSIX ERE, matched case-insensitively). ------------------------------
Q="[\"'\`]?"                                   # optional quote around key or value
SEP="${Q}[[:space:]]*[=:[:space:]][[:space:]]*${Q}"
P_STRICT="stricthostkeychecking${SEP}(accept-new|no|off|false)([^a-z0-9_-]|\$)"
P_USERKH="userknownhostsfile${SEP}(/dev/null|none)([^a-z0-9_/.-]|\$)"
KS="ssh-""keyscan"                            # split so these lines never self-match
P_KS_REDIR="${KS}.*[^0-9]>([^&]|\$)"
P_KS_TEE="${KS}.*\\|[[:space:]]*(sudo[[:space:]]+)?tee([[:space:]]|\$)"
P_KS_KH="${KS}.*\\|.*known""_hosts"

PATHSPEC=(-- . ':(exclude)knowledge-base/**')

fail=0
_red() { fail=1; printf 'FAIL: %s\n' "$*" >&2; }

if ! git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  printf 'FAIL: %s is not a git work tree; nothing to enumerate\n' "$ROOT" >&2
  exit 1
fi

scanned="$(git -C "$ROOT" ls-files --cached --others --exclude-standard "${PATHSPEC[@]}" | wc -l | tr -d ' ')"
echo "scanned files: $scanned (floor $MIN_FILES)"
if (( scanned < MIN_FILES )); then
  _red "scanned-file floor: $scanned < $MIN_FILES under $ROOT. An empty or truncated enumeration cannot prove absence."
fi

# path -> hit count. `git grep -c -z` prints `path\0count` per file with >=1 matching line.
declare -A HITS=()
while IFS= read -r -d '' path && IFS= read -r count; do
  HITS["$path"]="$count"
done < <(git -C "$ROOT" grep --untracked -I -i -E -c -z --no-color \
           -e "$P_STRICT" -e "$P_USERKH" -e "$P_KS_REDIR" -e "$P_KS_TEE" -e "$P_KS_KH" \
           "${PATHSPEC[@]}" || true)

declare -A ALLOWED=()
while IFS='|' read -r a_path a_count a_reason; do
  [[ -z "$a_path" ]] && continue
  ALLOWED["$a_path"]=1
  lineno="$(grep -nF -- "$a_path|$a_count|" "$SELF" | head -n1 | cut -d: -f1)"
  got="${HITS[$a_path]:-0}"
  if [[ "$got" != "$a_count" ]]; then
    if [[ "$got" == 0 ]]; then
      _red "allow-list entry '$a_path' ($a_reason) expects $a_count hit(s) and has 0. A zero-hit exemption is a stale hole: delete ${SELF_REL} line ${lineno}."
    else
      _red "allow-list entry '$a_path' ($a_reason) expects $a_count hit(s) and has $got. Remove the new unpinned SSH option(s) from $a_path, or (with review) change the count on ${SELF_REL} line ${lineno}."
    fi
    git -C "$ROOT" grep --untracked -I -i -n -E --no-color \
      -e "$P_STRICT" -e "$P_USERKH" -e "$P_KS_REDIR" -e "$P_KS_TEE" -e "$P_KS_KH" \
      -- "$a_path" 2>/dev/null | sed 's/^/    /' >&2 || true
  else
    echo "[ok] allow-list $a_path = $got"
  fi
done <<< "$ALLOWLIST"

allow_start="$(grep -n '^ALLOWLIST=' "$SELF" | head -n1 | cut -d: -f1)"
for path in "${!HITS[@]}"; do
  [[ -n "${ALLOWED[$path]:-}" ]] && continue
  _red "$path: ${HITS[$path]} unpinned SSH host-key line(s). Pin the host key (StrictHostKeyChecking=yes + a written known_hosts) instead. If this is a genuinely local/never-real-host use, add an entry to the ALLOWLIST in ${SELF_REL} (starts line ${allow_start}) with its exact count and reason."
  git -C "$ROOT" grep --untracked -I -i -n -E --no-color \
    -e "$P_STRICT" -e "$P_USERKH" -e "$P_KS_REDIR" -e "$P_KS_TEE" -e "$P_KS_KH" \
    -- "$path" 2>/dev/null | sed 's/^/    /' >&2 || true
done

if (( fail )); then
  echo "test-no-tofu-ssh: FAIL" >&2
  exit 1
fi
echo "test-no-tofu-ssh: PASS ($scanned files scanned, ${#HITS[@]} file(s) with hits, all allow-listed at exact counts)"
