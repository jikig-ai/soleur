#!/usr/bin/env bash
# tests/scripts/test-main-duplicate-skip.sh — mutation-battery coverage for
# scripts/main-push-duplicate-skip.sh (the tree-identity proof that gates
# duplicate push-to-main workflow runs, #8919).
#
# Every fixture row below exists because a WRONG verdict in the true direction
# is silent (a skipped run leaves no trace) — so the false arm and the
# ambiguity arms are what the suite is for. The stub `gh` on PATH dispatchers
# on URL fragments to per-SHA fixture files; an unrouted call exits 64 so a
# SUT asking for the wrong thing fails LOUDLY, not by accident.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUT="$REPO_ROOT/scripts/main-push-duplicate-skip.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
passes=0; fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; }

mkdir -p "$TMP/bin" "$TMP/fixtures"
export GITHUB_REPOSITORY="jikig-ai/soleur"
export STUB_LOG="$TMP/gh.log"; : > "$STUB_LOG"
STUB_DIR="$TMP/fixtures"; export STUB_DIR

cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG"
# gh api honors --jq <prog>: the fixture is the RESPONSE, the program is the
# REQUEST's claim about how it reads the response — evaluate both, or a wrong
# jq on the SUT side would read unfiltered JSON and still pass.
# --jq <prog> and --arg <name> <value> — the arg VALUE follows the name, so
# pending_arg_name carries it across one iteration.
jq_prog=""; prev=""; pending_arg=""; jq_args=()
for a in "$@"; do
  if [ -n "$pending_arg" ]; then jq_args+=(--arg "$pending_arg" "$a"); pending_arg=""; prev="$a"; continue; fi
  case "$prev" in
    --jq) jq_prog="$a";;
    --arg) pending_arg="$a";;
  esac
  prev="$a"
done
respond() { [ -n "$jq_prog" ] && jq -r "${jq_args[@]}" "$jq_prog" || cat; }
for a in "$@"; do
  case "$a" in
    */commits/*/pulls)
      sha="${a%/pulls}"; sha="${sha##*/}"
      f="$STUB_DIR/pulls-$sha"; [ -f "$f" ] || exit 64
      respond < "$f"; exit 0 ;;
    */git/commits/*)
      sha="${a##*/}"
      f="$STUB_DIR/commit-$sha"; [ -f "$f" ] || exit 64
      respond < "$f"; exit 0 ;;
    */workflows/*/runs*)
      # name the fixture by the head_sha param of the REQUEST — a lookup at the
      # wrong head is a miss, not an answer.
      head=""
      for b in "$@"; do case "$b" in *head_sha=*) head="${b#*head_sha=}"; head="${head%%&*}";; esac; done
      f="$STUB_DIR/runs-$head"; [ -f "$f" ] || exit 64
      respond < "$f"; exit 0 ;;
    */runs/*/jobs*)
      id="${a%/jobs*}"; id="${id##*/}"
      f="$STUB_DIR/jobs-$id"; [ -f "$f" ] || exit 64
      respond < "$f"; exit 0 ;;
  esac
done
echo "stub: unrouted gh call: $*" >&2; exit 64
STUB
chmod +x "$TMP/bin/gh"

# also stub jq to the system one (real jq required — the SUT depends on it)
command -v jq >/dev/null || { echo "FAIL: jq required" >&2; exit 2; }

run_sut() {  # $1=out-file  $2..=sut args
  local _out="$1"; shift
  PATH="$TMP/bin:$PATH" bash "$SUT" "$@" > "$_out" 2>"$TMP/sut.err"
}

mksha() { local out=""; while (( ${#out} < 40 )); do out+="$1"; done; printf '%s' "${out:0:40}"; }
SHA_MERGE=$(mksha a); SHA_HEAD=$(mksha b); TREE_OK=$(mksha c); TREE_BAD=$(mksha d)
RUN_OK=111; SHA_OTHER_MERGE=$(mksha e)

WF="wf-under-test.yml"
# fixture builders ------------------------------------------------------------
pulls()  { printf '[{"head":{"sha":"%s"},"merged_at":"%s","merge_commit_sha":"%s"}]\n' "$1" "$2" "$3"; }
commit() { printf '{"tree":{"sha":"%s"}}\n' "$1"; }
runs()   { printf '{"workflow_runs":[%s]}\n' "$1"; }
jobs()   { printf '{"jobs":[%s]}\n' "$1"; }

check() {  # $1=label $2=want(true|false) $3..=sut args
  local _label="$1" _want="$2"; shift 2
  local out="$TMP/out"
  run_sut "$out" "$@"
  local got; got="$(grep -o 'duplicate=[a-z]*' "$out" | cut -d= -f2)"
  if [ "$got" = "$_want" ]; then pass; else fail "$_label: want $_want got ${got:-<none>} (stderr: $(tail -1 $TMP/sut.err))"; fi
}

# --- ROW 1: happy path — merged PR, merge_commit_sha match, trees equal, run+jobs green
pulls "$SHA_HEAD" 2026-09-25T00:00:00Z "$SHA_MERGE" > "$STUB_DIR/pulls-$SHA_MERGE"
commit "$TREE_OK" > "$STUB_DIR/commit-$SHA_HEAD"; commit "$TREE_OK" > "$STUB_DIR/commit-$SHA_MERGE"
runs '{"id":111,"status":"completed","conclusion":"success"}' > "$STUB_DIR/runs-$SHA_HEAD"
jobs '{"name":"validate","conclusion":"success"},{"name":"deploy-script-tests (1/4)","conclusion":"success"}' > "$STUB_DIR/jobs-$RUN_OK"
check "happy: tree-identical + green run + executed jobs" true "$WF" "$SHA_MERGE" validate deploy-script-tests
[ "${DEBUG:-0}" = 1 ] && { echo "--- gh.log ---" >&2; cat "$STUB_LOG" >&2; }

# --- ROW 2: no PR association at all (direct push)
rm -f "$STUB_DIR/pulls-$SHA_MERGE"; echo '[]' > "$STUB_DIR/pulls-$SHA_MERGE"
check "no-PR: direct/admin push" false "$WF" "$SHA_MERGE" validate

# --- ROW 3: association exists but merge_commit_sha is a different commit
echo '[]' > "$STUB_DIR/pulls-$SHA_MERGE"   # placeholder
pulls "$SHA_HEAD" 2026-09-25T00:00:00Z "$SHA_OTHER_MERGE" > "$STUB_DIR/pulls-$SHA_MERGE"
check "bind: PR contains the commit but merged as another sha" false "$WF" "$SHA_MERGE" validate

# --- ROW 4: PR not merged (merged_at null — REAL json null, not the string)
printf '[{"head":{"sha":"%s"},"merged_at":null,"merge_commit_sha":"%s"}]\n' "$SHA_HEAD" "$SHA_MERGE" > "$STUB_DIR/pulls-$SHA_MERGE"
check "unmerged association" false "$WF" "$SHA_MERGE" validate

# --- ROW 5: tree drift (main moved between check and merge)
pulls "$SHA_HEAD" 2026-09-25T00:00:00Z "$SHA_MERGE" > "$STUB_DIR/pulls-$SHA_MERGE"
commit "$TREE_BAD" > "$STUB_DIR/commit-$SHA_MERGE"
check "tree-differs: stale base / merge-order" false "$WF" "$SHA_MERGE" validate
commit "$TREE_OK" > "$STUB_DIR/commit-$SHA_MERGE"

# --- ROW 6: run not green — latest completed is cancelled
runs '{"id":112,"status":"completed","conclusion":"cancelled"},{"id":111,"status":"completed","conclusion":"success"}' > "$STUB_DIR/runs-$SHA_HEAD"
check "cancelled-latest" false "$WF" "$SHA_MERGE" validate
# --- ROW 7: latest completed is failure
runs '{"id":113,"status":"completed","conclusion":"failure"}' > "$STUB_DIR/runs-$SHA_HEAD"
check "failure-latest" false "$WF" "$SHA_MERGE" validate
# --- ROW 8: never ran at that head (no completed)
runs '{"workflow_runs":[]}' > "$STUB_DIR/runs-$SHA_HEAD"   # literal override below
printf '{"workflow_runs":[{"id":114,"status":"queued","conclusion":null}]}\n' > "$STUB_DIR/runs-$SHA_HEAD"
check "no completed run at head" false "$WF" "$SHA_MERGE" validate

runs '{"id":111,"status":"completed","conclusion":"success"}' > "$STUB_DIR/runs-$SHA_HEAD"

# --- ROW 9: required job missing entirely
check "required job absent from run" false "$WF" "$SHA_MERGE" validate nonexistent-job

# --- ROW 10: required job SKIPPED (skipped != coverage)
jobs '{"name":"validate","conclusion":"success"},{"name":"tenant-integration","conclusion":"skipped"}' > "$STUB_DIR/jobs-$RUN_OK"
check "required job skipped" false "$WF" "$SHA_MERGE" validate tenant-integration
jobs '{"name":"validate","conclusion":"success"},{"name":"deploy-script-tests (1/4)","conclusion":"success"}' > "$STUB_DIR/jobs-$RUN_OK"

# --- ROW 11: required job failed
jobs '{"name":"validate","conclusion":"failure"}' > "$STUB_DIR/jobs-$RUN_OK"
check "required job failed" false "$WF" "$SHA_MERGE" validate
jobs '{"name":"validate","conclusion":"success"},{"name":"deploy-script-tests (1/4)","conclusion":"success"}' > "$STUB_DIR/jobs-$RUN_OK"

# --- ROW 12: prefix collision — 'deploy-script-tests-done' must NOT satisfy 'deploy-script-tests'
jobs '{"name":"deploy-script-tests-done","conclusion":"success"}' > "$STUB_DIR/jobs-$RUN_OK"
check "prefix collision (done != tests)" false "$WF" "$SHA_MERGE" deploy-script-tests
jobs '{"name":"deploy-script-tests (1/4)","conclusion":"success"}' > "$STUB_DIR/jobs-$RUN_OK"

# --- ROW 13: API failure → fail-open
printf 'not-json' > "$STUB_DIR/pulls-$SHA_MERGE"; chmod 000 "$STUB_DIR/pulls-$SHA_MERGE"
check "API error on pulls" false "$WF" "$SHA_MERGE" validate
chmod 644 "$STUB_DIR/pulls-$SHA_MERGE"

# --- ROW 14: exit status is always 0
out="$TMP/out"; PATH="$TMP/bin:$PATH" bash "$SUT" "$WF" "$SHA_MERGE" validate >"$out" 2>/dev/null
rc=$?; [ "$rc" = 0 ] && [ "$(cat "$out")" = "duplicate=false" ] && pass || fail "exit nonzero or bad line on unhappy path"

# ═══ MUTATION BATTERY — each must drive a check RED on a true-fixture ════════
setup_happy() {
  pulls "$SHA_HEAD" 2026-09-25T00:00:00Z "$SHA_MERGE" > "$STUB_DIR/pulls-$SHA_MERGE"
  commit "$TREE_OK" > "$STUB_DIR/commit-$SHA_HEAD"; commit "$TREE_OK" > "$STUB_DIR/commit-$SHA_MERGE"
  runs '{"id":111,"status":"completed","conclusion":"success"}' > "$STUB_DIR/runs-$SHA_HEAD"
  jobs '{"name":"validate","conclusion":"success"}' > "$STUB_DIR/jobs-$RUN_OK"
}
mutant() {  # $1=label $2=sed-expression applied to a SUT copy
  local M="$TMP/mutant-$1.sh"; cp "$SUT" "$M"; sed -i "$2" "$M"; echo "$M"
}
setup_happy

# M1 drop the tree equality arm — a differs-fixture now emits true
M=$(mutant m1 's/\[ -n "\$head_tree" \] && \[ "\$head_tree" = "\$merge_tree" \]/true/')
commit "$TREE_BAD" > "$STUB_DIR/commit-$SHA_MERGE"
o=$(PATH="$TMP/bin:$PATH" bash "$M" "$WF" "$SHA_MERGE" validate); [ "$o" = "duplicate=true" ] && pass || fail "M1 tree-check-drop should still emit true (mutation detects)"
commit "$TREE_OK" > "$STUB_DIR/commit-$SHA_MERGE"

# M3 accept cancelled as coverage (conclusion!=failure)
M=$(mutant m3 's/conclusion=="success"/conclusion!="failure"/g')
runs '{"id":112,"status":"completed","conclusion":"cancelled"}' > "$STUB_DIR/runs-$SHA_HEAD"
jobs '{"name":"validate","conclusion":"success"}' > "$STUB_DIR/jobs-112"
o=$(PATH="$TMP/bin:$PATH" bash "$M" "$WF" "$SHA_MERGE" validate); [ "$o" = "duplicate=true" ] && pass || fail "M3 cancelled-counted should emit true"
runs '{"id":111,"status":"completed","conclusion":"success"}' > "$STUB_DIR/runs-$SHA_HEAD"

# M4 skipped counts as coverage
M=$(mutant m4 's/\.conclusion=="success")/(.conclusion=="success" or .conclusion=="skipped"))/')
jobs '{"name":"validate","conclusion":"skipped"}' > "$STUB_DIR/jobs-$RUN_OK"
o=$(PATH="$TMP/bin:$PATH" bash "$M" "$WF" "$SHA_MERGE" validate); [ "$o" = "duplicate=true" ] && pass || fail "M4 skipped-counted should emit true"
jobs '{"name":"validate","conclusion":"success"}' > "$STUB_DIR/jobs-$RUN_OK"

echo "test-main-duplicate-skip: $passes passed, $fails failed"
[ "$fails" -eq 0 ]
