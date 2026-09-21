#!/usr/bin/env bash
# Guard 1 (#7226 / #5914, ADR-237): no tracked file configures an SSH client to trust
# whatever host key the peer presents.
#
# PROPERTY. Outside the allow-list below, no file in the universe:
#   * sets StrictHostKeyChecking to accept-new, no, off or false (ssh parses `false` as
#     `off`);
#   * points UserKnownHostsFile at /dev/null (or `none`), which discards the pin;
#   * sets the known-hosts command option (KnownHostsCommand) to anything but `none` (a
#     command that prints host keys is a second trust source no committed pin constrains);
#   * sends keyscan output into a file: a stdout redirect (`>`, `>>`, `1>`, `&>`), a pipe
#     (`|` or `|&`) into tee, dd, or sponge (optionally through sudo/doas with flags), or any
#     pipe on a line that also names the known-hosts file. A keyscan captured into a variable
#     with command substitution and then validated is not a known-hosts write and is not
#     flagged (stderr-only redirects such as 2>/dev/null are ignored).
# The match is case-insensitive and covers every spelling: `-o K=V`, `-oK=V`,
# `-o "K V"`, ssh_config `K V`, YAML `K: V`, TS/JSON string literals and GIT_SSH_COMMAND
# strings. GlobalKnownHostsFile=/dev/null is ALLOWED: it removes a trust source, where
# the user-file form removes the pin.
#
# OUT OF REACH. This is a TEXT guard. A literal assembled at runtime (string concatenation,
# a variable holding the value, an ssh_config written by a heredoc with an interpolated
# value) never appears as one string and cannot be seen here. The RESOLVED-value tests cover
# those paths instead: the app transport's `ssh -G` assertions (apps/web-platform/test/
# git-data-host-key-pin.test.ts) and the bridge/writer rows (tests/scripts/
# test-write-known-hosts.sh, git-data-cutover-access.test.sh).
#
# UNIVERSE. `git ls-files --cached --others --exclude-standard` (tracked files plus new
# files not yet added, so a local run sees the same thing CI will) minus
# knowledge-base/**, where docs quote the old literals on purpose. Binary files are
# skipped. A hit is one MATCH (`git grep -o`), so a second literal appended to an
# allow-listed line raises that file's count. The keyscan arms are counted per LINE (their
# patterns span the line, so one line is one keyscan write).
#
# ALLOW-LIST. `path|expected-count|reason`. Each entry must hit EXACTLY its count: a
# zero-hit entry is RED (a stale exemption is an invisible hole), and so is a count
# that grew. There is no stored hash; the allow-list is anchored by review of this file
# (CODEOWNERS).
#
# Test files that need a literal build it by concatenation so it never counts here.
#
# Banned spellings, as documentation. Each of the next 5 lines holds exactly one hit of
# this script against itself; together they are the `self` allow-list count:
#   ssh -o StrictHostKeyChecking=accept-new host
#   ssh -o "StrictHostKeyChecking off" host
#   ssh_config:  UserKnownHostsFile /dev/null
#   GIT_SSH_COMMAND="ssh -o UserKnownHostsFile=/dev/null"
#   ssh-keyscan host >> known_hosts
#
# Env:
#   NO_TOFU_ROOT       tree to scan (default: the git toplevel containing this script).
#   NO_TOFU_MIN_FILES  scanned-file floor (default 4750, ~90% of the ~5.3k-file tree).
#                      An enumeration that silently returns nothing, or loses a top-level
#                      directory, must not read green.
#
# Mutation harness: tests/scripts/test-no-tofu-ssh-mutation.sh.
set -euo pipefail

SELF="${BASH_SOURCE[0]}"
SELF_DIR="$(cd "$(dirname "$SELF")" && pwd)"
SELF_REL="tests/scripts/test-no-tofu-ssh.sh"
ROOT="${NO_TOFU_ROOT:-$(git -C "$SELF_DIR" rev-parse --show-toplevel)}"
MIN_FILES="${NO_TOFU_MIN_FILES:-4750}"

# --- The allow-list (path|expected-count|reason). Edit counts HERE. -----------------
ALLOWLIST="$(cat <<'ALLOW'
apps/web-platform/infra/git-data-ownership.test.sh|2|throwaway local container on 127.0.0.1:2222, never a real host (SHKC=no + UKHF=/dev/null on one line)
apps/web-platform/infra/infra-config-gate.test.sh|1|detector fixture string inside the infra-config-gate test, never executed
apps/web-platform/server/git-auth.ts|1|TOFU_FALLBACK_OPTS: the single transitional accept-new arm (#5914 removes it and this line)
tests/scripts/test-no-tofu-ssh.sh|5|this guard's own banned-spellings documentation block
ALLOW
)"

# --- Patterns (POSIX ERE, matched case-insensitively). ------------------------------
Q="[\"'\`]?"                                   # optional quote around key or value
SEP="${Q}[[:space:]]*[=:[:space:]][[:space:]]*${Q}"
P_STRICT="stricthostkeychecking${SEP}(accept-new|no|off|false)([^a-z0-9_-]|\$)"
P_USERKH="userknownhostsfile${SEP}(/dev/null|none)([^a-z0-9_/.-]|\$)"
# Any value; the `none` value is dropped by the filter below (ERE has no negative lookahead).
P_KHC="knownhostscommand${SEP}[^[:space:]\"'\`,;)]*"
KS="ssh-""keyscan"                            # split so these lines never self-match
P_KS_REDIR="${KS}.*([^0-9]|[^0-9]1)>([^&]|\$)"
P_KS_SINK="${KS}.*\\|&?[[:space:]]*((sudo|doas)([[:space:]]+[^[:space:]|]+)*[[:space:]]+)?(tee|dd|sponge)([[:space:]]|\$)"
P_KS_KH="${KS}.*\\|.*known""_hosts"
ALL_PATTERNS=(-e "$P_STRICT" -e "$P_USERKH" -e "$P_KHC" -e "$P_KS_REDIR" -e "$P_KS_SINK" -e "$P_KS_KH")

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

_grep() { git -C "$ROOT" grep --untracked -I -i -E --no-color "$@" "${PATHSPEC[@]}" || true; }

# path -> hit count, summed over the arms.
declare -A HITS=()
_add() { HITS["$1"]=$(( ${HITS[$1]:-0} + $2 )); }
# Per-MATCH arms: `git grep -o -z` prints `path\0match` once per match.
while IFS= read -r -d '' path && IFS= read -r _m; do
  _add "$path" 1
done < <(_grep -o -z -e "$P_STRICT" -e "$P_USERKH")
while IFS= read -r -d '' path && IFS= read -r m; do
  v="${m,,}"
  v="${v#knownhostscommand}"
  v="${v#[\"\'\`]}"
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v#[=:]}"
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v#[\"\'\`]}"
  [[ "$v" == none ]] && continue
  _add "$path" 1
done < <(_grep -o -z -e "$P_KHC")
# Per-LINE arm (keyscan writes): `git grep -c -z` prints `path\0count`.
while IFS= read -r -d '' path && IFS= read -r count; do
  _add "$path" "$count"
done < <(_grep -c -z -e "$P_KS_REDIR" -e "$P_KS_SINK" -e "$P_KS_KH")

_show() { git -C "$ROOT" grep --untracked -I -i -n -E --no-color "${ALL_PATTERNS[@]}" -- "$1" 2>/dev/null | sed 's/^/    /' >&2 || true; }

# `grep -n` exits 1 on no match; that is an answer here (the line is shown as `?`), not an error.
_line_of() { local l; l="$( { grep -nF -- "$1" "$SELF" || true; } | head -n1 | cut -d: -f1)"; printf '%s' "${l:-?}"; }

declare -A ALLOWED=()
while IFS='|' read -r a_path a_count a_reason; do
  [[ -z "$a_path" ]] && continue
  ALLOWED["$a_path"]=1
  lineno="$(_line_of "$a_path|$a_count|")"
  got="${HITS[$a_path]:-0}"
  if [[ "$got" != "$a_count" ]]; then
    if [[ "$got" == 0 ]]; then
      _red "allow-list entry '$a_path' ($a_reason) expects $a_count hit(s) and has 0. A zero-hit exemption is a stale hole: delete ${SELF_REL} line ${lineno}."
    else
      _red "allow-list entry '$a_path' ($a_reason) expects $a_count hit(s) and has $got. Remove the new unpinned SSH option(s) from $a_path, or (with review) change the count on ${SELF_REL} line ${lineno}."
    fi
    _show "$a_path"
  else
    echo "[ok] allow-list $a_path = $got"
  fi
done <<< "$ALLOWLIST"

# shellcheck disable=SC2016  # the single-quoted text is the literal line to find
allow_start="$(_line_of 'ALLOWLIST="$(cat')"
for path in "${!HITS[@]}"; do
  [[ -n "${ALLOWED[$path]:-}" ]] && continue
  _red "$path: ${HITS[$path]} unpinned SSH host-key hit(s). Pin the host key (StrictHostKeyChecking=yes + a written known_hosts) instead. If this is a genuinely local/never-real-host use, add an entry to the ALLOWLIST in ${SELF_REL} (starts line ${allow_start}) with its exact count and reason."
  _show "$path"
done

if (( fail )); then
  echo "test-no-tofu-ssh: FAIL" >&2
  exit 1
fi
echo "test-no-tofu-ssh: PASS ($scanned files scanned, ${#HITS[@]} file(s) with hits, all allow-listed at exact counts)"
