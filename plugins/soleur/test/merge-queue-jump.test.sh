#!/usr/bin/env bash
# Suite for scripts/merge-queue-jump.sh (#11678): the deliberate queue-jump
# helper. The contract under test: --reason always required, --yes required on
# non-TTY stdin, never-armed refusal, armed/in-queue happy path, expectedHeadOid
# re-read before the mutation, merged exits 0 (first probe OR during confirm),
# attribution-post failure exits 3, every refusal exits 1.
#
# SEAM: a PATH `gh` stub serves synthesized GraphQL responses for the probe and
# mutation, applies --jq itself (real gh applies it client-side), records every
# argv line to GH_CALLS, and refuses unknown calls (exit 64). Flags:
#   GH_FIX_ARMED=false   -> autoMergeRequest null, isInMergeQueue false
#   GH_FIX_INQ=true      -> mergeQueueEntry present (already queued)
#   GH_FIX_STATE=CLOSED  -> pullRequest.state CLOSED
#   GH_FIX_MERGED=1      -> every probe reports merged=true
#   GH_FIX_MERGEBETWEEN  -> the SECOND probe onwards reports merged=true
#   GH_FIX_MUTFAIL       -> mutation call exits 1
#   GH_FIX_COMMENTFAIL   -> `gh pr comment` exits 1
# shellcheck disable=SC2016,SC2329
export TMPDIR="${TMPDIR:-/var/tmp}"
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SUT="$REPO_ROOT/scripts/merge-queue-jump.sh"

passes=0; fails=0; FAILED=()
pass() { passes=$((passes + 1)); echo "  PASS: $1"; }
fail() { fails=$((fails + 1)); FAILED+=("$1"); echo "  FAIL: $1" >&2; }
_iv_p="$passes"; _iv_f="$fails"; _iv_n="${#FAILED[@]}"
{ pass "self-test"; fail "self-test"; } >/dev/null 2>&1
if [[ "$passes" -ne $((_iv_p + 1)) || "$fails" -ne $((_iv_f + 1)) || "${#FAILED[@]}" -ne $((_iv_n + 1)) ]]; then
  printf '[FATAL] instrument self-test\n' >&2; exit 1
fi
passes=0; fails=0; FAILED=()

assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}
command -v jq >/dev/null 2>&1 || { echo "[FATAL] jq not found" >&2; exit 2; }

WORK="$(mktemp -d)"; assert_fixture_dir "$WORK"
trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bin"; assert_fixture_dir "$BIN"; mkdir -p "$BIN" || exit 2

cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
printf '%s\n' "$*" >> "${GH_CALLS:?}"
args="$*"
emit() { # emit <json-or-text> honoring a trailing --jq filter
  local data="$1" jqf=""
  case "$args" in *"--jq"*) jqf="${args##*--jq }"; jqf="${jqf%% *}";; esac
  if [[ -n "$jqf" ]]; then jq -r "$jqf" <<<"$data"; else printf '%s\n' "$data"; fi
}
pr_json() { # pr_json <merged> [<head>]
  printf '{"data":{"repository":{"mergeQueue":{"entries":{"totalCount":%s}},"pullRequest":{"id":"PR_x","state":"%s","merged":%s,"isInMergeQueue":%s,"headRefOid":"%s","baseRefName":"%s","autoMergeRequest":%s,"mergeQueueEntry":%s}}}}' \
    "${GH_FIX_DEPTH:-2}" "${GH_FIX_STATE:-OPEN}" "${1:-false}" "${GH_FIX_INQ:-false}" \
    "${2:-${GH_FIX_HEAD:-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa}}" "${GH_FIX_BASE:-main}" \
    "$( [[ "${GH_FIX_ARMED:-true}" == true ]] && printf '{"enabledAt":"2026-10-31T00:00:00Z"}' || printf 'null' )" \
    "$( [[ "${GH_FIX_INQ:-false}" == true ]] && printf '{"position":3,"state":"QUEUED"}' || printf 'null' )"
}
case "$args" in
  repo\ view*) emit "jikig-ai/soleur" ;;
  api\ user*)  emit '{"login":"operator-test"}' ;;
  pr\ comment*) [[ "${GH_FIX_COMMENTFAIL:-}" == 1 ]] && exit 1 || { echo posted; exit 0; } ;;
  api\ graphql*)
    if [[ "$args" == *enqueuePullRequest* ]]; then
      # the mutation must be a jump, bound with raw-field vars (-F, literal)
      [[ "$args" == *"jump:true"* ]] || { echo "stub gh: mutation lacks jump:true" >&2; exit 64; }
      [[ "$args" == *"-F pr="* && "$args" == *"-F oid="* ]] || { echo "stub gh: mutation vars not -F bound" >&2; exit 64; }
      [[ "${GH_FIX_MUTFAIL:-}" == 1 ]] && exit 1
      emit '{"data":{"enqueuePullRequest":{"mergeQueueEntry":{"position":1,"state":"QUEUED"},"clientMutationId":null}}}'
    else
      # the probe binds $o/$n/$pr by name — a renamed variable is a dead probe (P0 class)
      [[ "$args" == *"-F o="* && "$args" == *"-F n="* && "$args" == *"-F pr="* ]] \
        || { echo "stub gh: probe vars not bound as -F o=/n=/pr=" >&2; exit 64; }
      n=$(grep -c 'api graphql' "${GH_CALLS}" 2>/dev/null); n="${n//[[:space:]]/}"
      [[ "${GH_FIX_PROBEFAIL:-}" == 1 && "${n:-0}" -eq 1 ]] && { echo "gh: HTTP 500" >&2; exit 1; }
      [[ "${GH_FIX_PROBEFAIL:-}" == 2 && "${n:-0}" -eq 2 ]] && { echo "gh: HTTP 500" >&2; exit 1; }
      h="${GH_FIX_HEAD:-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa}"
      [[ "${n:-0}" -ge 2 && -n "${GH_FIX_HEAD2:-}" ]] && h="$GH_FIX_HEAD2"
      if [[ "${GH_FIX_MERGED:-}" == 1 ]]; then emit "$(pr_json true "$h")"
      elif [[ "${GH_FIX_MERGEBETWEEN:-}" == 1 && "${n:-0}" -ge 2 ]]; then emit "$(pr_json true "$h")"
      else emit "$(pr_json false "$h")"; fi
    fi ;;
  *) exit 64 ;;
esac
STUB
chmod +x "$BIN/gh"

export PATH="$BIN:$PATH"
export GH_CALLS="$WORK/calls"; : > "$GH_CALLS"

t() { # t <name> <want_rc> <substring-in-combined-output-or---> env... -- argv...
  local name="$1" want="$2" needle="$3"; shift 3
  local envargs=()
  while [[ $# -gt 0 && "$1" != -- ]]; do envargs+=("$1"); shift; done
  shift
  : > "$GH_CALLS"
  local out rc
  out="$(env "${envargs[@]}" bash "$SUT" "$@" </dev/null 2>&1)"; rc=$?
  if [[ "$rc" -ne "$want" ]]; then fail "$name (rc=$rc want=$want out=$out)"; return; fi
  if [[ "$needle" != "-" && "$out" != *"$needle"* ]]; then fail "$name (missing '$needle' in: $out)"; return; fi
  pass "$name"
}

t help-rc            0 "Usage"                          -- --help
t no-reason          1 "--reason is required"           -- 42 --yes
t non-tty-no-yes     1 "requires --yes"                 -- 42 --reason "hotfix"
t not-armed-refuse   1 "no auto-merge armed"            GH_FIX_ARMED=false -- 42 --reason r --yes
t armed-happy        0 "jumped PR #42"                  -- 42 --reason "prod down" --yes
t inqueue-happy      0 "jumped PR #42"                  GH_FIX_INQ=true -- 42 --reason "prod down" --yes
t already-merged     0 "already merged"                 GH_FIX_MERGED=1 -- 42 --reason r --yes
t merged-in-confirm  0 "merged during confirmation"     GH_FIX_MERGEBETWEEN=1 -- 42 --reason r --yes
t mutation-fail      1 "rejected"                       GH_FIX_MUTFAIL=1 -- 42 --reason r --yes
t unattributed       3 "attribution incomplete"         GH_FIX_COMMENTFAIL=1 -- 42 --reason r --yes
t closed-refuse      1 "is CLOSED"                      GH_FIX_STATE=CLOSED -- 42 --reason r --yes
t blank-reason       1 "--reason is required"           -- 42 --reason "   " --yes
t nonmain-refuse     1 "does not target main"           GH_FIX_BASE=develop -- 42 --reason r --yes
t probe1-fail        1 "probe failed"                   GH_FIX_PROBEFAIL=1 -- 42 --reason r --yes
t probe2-fail        1 "re-probe failed"                GH_FIX_PROBEFAIL=2 -- 42 --reason r --yes

# refusals must never reach the mutation — a refused jump that still mutates is a P1.
for row in "GH_FIX_ARMED=false" "GH_FIX_STATE=CLOSED" "GH_FIX_BASE=develop"; do
  : > "$GH_CALLS"
  env "$row" bash "$SUT" 42 --reason r --yes </dev/null >/dev/null 2>&1 || true
  if grep -q 'enqueuePullRequest' "$GH_CALLS"; then fail "refusal path $row still attempted the mutation"
  else pass "refusal path $row never mutates"; fi
done

# mutation must carry expectedHeadOid == the SECOND (post-confirm) probed head:
: > "$GH_CALLS"
env GH_FIX_HEAD=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb \
    GH_FIX_HEAD2=cccccccccccccccccccccccccccccccccccccccc \
    bash "$SUT" 42 --reason r --yes </dev/null >/dev/null 2>&1
if grep -q -- '-F oid=cccccccccccccccccccccccccccccccccccccccc' "$GH_CALLS" \
   && ! grep -q -- '-F oid=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' "$GH_CALLS"; then
  pass "mutation pins expectedHeadOid to the re-read head, not the first probe"
else fail "mutation expectedHeadOid pin (calls: $(tr '\n' '|' < "$GH_CALLS"))"; fi

# attribution must carry --reason verbatim on the PR:
: > "$GH_CALLS"
bash "$SUT" 42 --reason "prod down" --yes </dev/null >/dev/null 2>&1
if grep -q 'pr comment 42' "$GH_CALLS" && grep -q 'prod down' "$GH_CALLS"; then
  pass "attribution posts --reason on the PR"
else fail "attribution posts --reason (calls: $(tr '\n' '|' < "$GH_CALLS"))"; fi

# already-merged PR must NOT call the mutation:
: > "$GH_CALLS"
env GH_FIX_MERGED=1 bash "$SUT" 42 --reason r --yes </dev/null >/dev/null 2>&1
if grep -q 'enqueuePullRequest' "$GH_CALLS"; then
  fail "already-merged PR still attempted the mutation"
else pass "already-merged PR never mutates"; fi

printf 'merge-queue-jump.test.sh: %d passed, %d failed\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]] || { printf 'FAILED rows:\n' >&2; printf '  %s\n' "${FAILED[@]}" >&2; exit 1; }
[[ "$passes" -ge 10 ]] || { printf '[FATAL] pass floor: %d < 10\n' >&2; exit 1; }
