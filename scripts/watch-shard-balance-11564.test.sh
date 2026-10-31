#!/usr/bin/env bash
# Suite for scripts/watch-shard-balance-11564.sh — the weekly advisory drift
# probe (#11564). Mock-`gh` + fixture timings dirs: the mock serves run-list/
# download/issue verbs and records every argv; the WATCH_* env seams feed a
# synthetic committed durations/manifest base so flagged rows are fixture-made.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/watch-shard-balance-11564.sh"
WF="$SCRIPT_DIR/../.github/workflows/shard-balance-watch.yml"

PASS=0; FAIL=0; TOTAL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); }
fatal() { printf 'FATAL: %s\n' "$*" >&2; exit 2; }
finish() { [[ "$FAIL" -eq 0 ]]; }

pass "self-test" >/dev/null; fail "self-test" >/dev/null
if [[ "$PASS" -ne 1 || "$FAIL" -ne 1 || "$TOTAL" -ne 2 ]]; then
  printf 'FATAL: verdict helpers are not dispatching\n' >&2; exit 2
fi
PASS=0; FAIL=0; TOTAL=0
if ( FAIL=1; finish ) || ! ( FAIL=0; finish ); then
  printf 'FATAL: finish() does not map FAIL to an exit status\n' >&2; exit 2
fi
if [[ "$(tail -n 1 "${BASH_SOURCE[0]}")" != 'finish || exit 1' ]]; then
  printf 'FATAL: last line is not `finish || exit 1`\n' >&2; exit 2
fi

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

TMPDIR="${TMPDIR:-/var/tmp}"; export TMPDIR
ROOT="$(mktemp -d "${TMPDIR%/}/watch-shard-balance.XXXXXXXX")" || fatal "mktemp failed"
assert_fixture_dir "$ROOT"
trap 'rm -rf "$ROOT"' EXIT
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Committed-base fixture shared by all scenarios (legs 1-2; predicted legs are
# perfectly balanced at 7444ms so the predicted-ratio never fires here).
BASE="$ROOT/base"; mkdir -p "$BASE"; assert_fixture_dir "$BASE"
printf 'f-floor-big\t1222\tfloor\nf-floor-big2\t1222\tfloor\nf-floor-never\t1222\tfloor\nf-floor-sub\t1222\tfloor\nf-meas-x\t5000\tmeasured\nf-meas-y\t5000\tmeasured\n' \
  > "$BASE/durations.tsv"
{ printf '# fixture incumbent\n# n=2\n'
  printf 'f-floor-big\t1\nf-floor-big2\t1\nf-floor-never\t2\nf-floor-sub\t2\nf-meas-x\t1\nf-meas-y\t2\n'; } > "$BASE/manifest.tsv"

N=0; MOCKD=""; OUT=""; ERR=""; RC=0
mkscene() {
  N=$((N + 1)); MOCKD="$ROOT/mock$N"; assert_fixture_dir "$MOCKD"
  mkdir -p "$MOCKD/artifacts" || fatal "mkdir failed"
  : > "$MOCKD/calls"; : > "$MOCKD/bodies"; : > "$MOCKD/created"; : > "$MOCKD/closed"
  printf '101\n' > "$MOCKD/run_ids"
  printf '[]' > "$MOCKD/issues.json"
  printf '{"number":505,"state":"OPEN","comments":[]}' > "$MOCKD/issue.json"
  cat > "$MOCKD/gh" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCKD/calls"
case "$1 $2" in
  "run list")
    [[ -f "$MOCKD/runlist_fail" ]] && { echo "gh: boom" >&2; exit 1; }
    cat "$MOCKD/run_ids"; exit 0 ;;
  "run download")
    rid="$3"; dest=""
    prev=""; for a in "$@"; do [[ "$prev" == "-D" ]] && dest="$a"; prev="$a"; done
    [[ -n "$dest" && -d "$MOCKD/artifacts/$rid" ]] || exit 1
    mkdir -p "$dest"; cp -r "$MOCKD/artifacts/$rid/." "$dest"; exit 0 ;;
  "issue list") cat "$MOCKD/issues.json"; exit 0 ;;
  "issue view") cat "$MOCKD/issue.json"; exit 0 ;;
  "issue comment") cat >> "$MOCKD/bodies"; exit 0 ;;
  "issue create")
    cat >> "$MOCKD/created"; printf 'https://example.invalid/i/505\n'; exit 0 ;;
  "issue close") printf '%s\n' "$*" >> "$MOCKD/closed"; exit 0 ;;
esac
echo "mock gh: unexpected call: $*" >&2; exit 64
MOCK
  chmod +x "$MOCKD/gh"
}

# seed_run <rid> <artifact-dir> : writes suite-timings.tsv with stdin content.
seed() {
  local rid="$1" adir="$2"; assert_fixture_dir "$MOCKD/artifacts/$rid"
  mkdir -p "$MOCKD/artifacts/$rid/$adir" || fatal "seed mkdir failed"
  cat > "$MOCKD/artifacts/$rid/$adir/suite-timings.tsv"
}

run() {
  OUT=""; ERR=""; RC=0
  local o="$MOCKD/stdout" e="$MOCKD/stderr"
  ( cd "$REPO_ROOT" && env "PATH=$MOCKD:$PATH" "MOCKD=$MOCKD" GH_REPO=jikig-ai/soleur \
      WATCH_DRIFT_GROUP=light WATCH_DURATIONS="$BASE/durations.tsv" WATCH_MANIFEST="$BASE/manifest.tsv" \
      bash "$SUT" "$@" ) > "$o" 2> "$e"
  RC=$?; OUT="$(cat "$o")"; ERR="$(cat "$e")"
}
ncalls() { grep -c "^$1" "$MOCKD/calls" || true; }
sentinel_of() { grep -oE 'drift=[0-9a-f]{40}' "$1" | tail -1; }

# ---- S1: over-bound floor row -> find-or-file creates the tracker -----------
mkscene; seed 101 suite-timings-scripts-0 <<'EOF'
f-floor-big	1500000
f-meas-x	5000
f-meas-y	5000
EOF
run
body="$(cat "$MOCKD/created")"
[[ "$RC" -eq 0 && "$(ncalls 'issue create')" -eq 1 && "$body" == *"f-floor-big"* \
   && "$body" == *"1500000"* && "$body" == *'<!-- shard-balance-watch:v1 drift='* ]] \
  && pass "S1 over-bound floor row files ONE tracker with sentinel" || fail "S1 (rc=$RC created=$(ncalls 'issue create'))"
[[ "$body" == *"leg"* && "$body" == *"1505000"* ]] \
  && pass "S1b the imbalanced observed leg is also flagged (max 1505000 > 1.30x bound)" || fail "S1b leg flag missing"
[[ "$body" != *"f-floor-sub"* && "$body" != *"f-meas-x"* ]] \
  && pass "S1c sub-bound and measured rows are not flagged" || fail "S1c wrong rows flagged"

# ---- S2: two over-bound floor rows -> BOTH appear ---------------------------
mkscene; seed 101 suite-timings-scripts-0 <<'EOF'
f-floor-big	1500000
f-floor-big2	1600000
f-meas-x	5000
f-meas-y	5000
EOF
run
body="$(cat "$MOCKD/created")"
[[ "$RC" -eq 0 && "$body" == *"f-floor-big"* && "$body" == *"f-floor-big2"* ]] \
  && pass "S2 two over-bound rows both land in the findings set" || fail "S2"

# ---- S3: identical flagged set on second run -> sentinel dedupe, no repost --
mkscene; seed 101 suite-timings-scripts-0 <<'EOF'
f-floor-big	1500000
f-meas-x	5000
f-meas-y	5000
EOF
run; sha="$(sentinel_of "$MOCKD/created")"; [[ -n "$sha" ]] || fatal "no sentinel captured"
: > "$MOCKD/calls"
printf '[{"number":505,"title":"ci-shard-balance-watch: manifest drift findings"}]' > "$MOCKD/issues.json"
printf '{"number":505,"state":"OPEN","comments":[{"author":{"login":"github-actions"},"body":"prior\\n<!-- shard-balance-watch:v1 %s -->"}]}' "$sha" > "$MOCKD/issue.json"
run
[[ "$RC" -eq 0 && "$(ncalls 'issue comment')" -eq 0 && "$(ncalls 'issue create')" -eq 0 ]] \
  && pass "S3 identical flagged set: no second comment (sentinel dedupe)" || fail "S3 (comments=$(ncalls 'issue comment'))"

# ---- S4: flagged set empties while tracker open -> resolution + close -------
mkscene; seed 101 suite-timings-scripts-0 <<'EOF'
f-meas-x	5000
f-meas-y	5000
EOF
printf '[{"number":505,"title":"ci-shard-balance-watch: manifest drift findings"}]' > "$MOCKD/issues.json"
run
[[ "$RC" -eq 0 && "$(ncalls 'issue comment')" -eq 1 && "$(ncalls 'issue close')" -eq 1 \
   && "$(cat "$MOCKD/bodies")" == *"All-clear"* ]] \
  && pass "S4 all-clear posts a resolution comment and closes the tracker" || fail "S4 (comments=$(ncalls 'issue comment') closes=$(ncalls 'issue close'))"

# ---- S5: zero timing artifacts in every sampled run -> exit 3 ---------------
mkscene; run
[[ "$RC" -eq 3 && "$ERR" == *"::error::"* && "$(ncalls 'issue create')" -eq 0 ]] \
  && pass "S5 no artifact-bearing run: exit 3, never a green all-clear" || fail "S5 (rc=$RC)"

# ---- S6: floor row just under the bound -> must-PASS unflagged --------------
mkscene; seed 101 suite-timings-scripts-0 <<'EOF'
f-floor-sub	299000
f-meas-x	304000
f-meas-y	5000
EOF
run
[[ "$RC" -eq 0 && "$(ncalls 'issue create')" -eq 0 && "$(ncalls 'issue comment')" -eq 0 ]] \
  && pass "S6 sub-bound floor row (299s < 300s) unflagged; balanced legs unflagged" || fail "S6 (rc=$RC)"

# ---- S7: shrunk non-empty set -> exactly one comment, new sentinel ----------
mkscene; seed 101 suite-timings-scripts-0 <<'EOF'
f-floor-big	1500000
f-meas-x	5000
f-meas-y	5000
EOF
printf '[{"number":505,"title":"ci-shard-balance-watch: manifest drift findings"}]' > "$MOCKD/issues.json"
printf '{"number":505,"state":"OPEN","comments":[{"author":{"login":"github-actions"},"body":"old\\n<!-- shard-balance-watch:v1 drift=0000000000000000000000000000000000000001 -->"}]}' > "$MOCKD/issue.json"
run
[[ "$RC" -eq 0 && "$(ncalls 'issue comment')" -eq 1 && "$(cat "$MOCKD/bodies")" == *"drift="* \
   && "$(sentinel_of "$MOCKD/bodies")" != "drift=0000000000000000000000000000000000000001" ]] \
  && pass "S7 changed flagged set posts exactly one comment with a new sentinel" || fail "S7"

# ---- S8: --dry-run prints findings, posts nothing ---------------------------
mkscene; seed 101 suite-timings-scripts-0 <<'EOF'
f-floor-big	1500000
f-meas-x	5000
f-meas-y	5000
EOF
run --dry-run
[[ "$RC" -eq 0 && "$OUT" == *"f-floor-big"* && "$OUT" == *"drift="* \
   && "$(ncalls 'issue create')" -eq 0 && "$(ncalls 'issue comment')" -eq 0 ]] \
  && pass "S8 --dry-run prints the would-be comment and posts nothing" || fail "S8 (rc=$RC)"

# ---- S9: exit vocabulary ----------------------------------------------------
mkscene; run --bogus
[[ "$RC" -eq 2 && "$ERR" == *"usage:"* && ! -s "$MOCKD/calls" ]] \
  && pass "S9a unknown arg: exit 2 usage, no gh call" || fail "S9a (rc=$RC)"
mkscene; : > "$MOCKD/runlist_fail"; run
[[ "$RC" -eq 3 && "$(ncalls 'issue')" -eq 0 ]] \
  && pass "S9b run-list failure: exit 3" || fail "S9b (rc=$RC)"
mkscene; seed 101 suite-timings-scripts-0 <<'EOF'
f-floor-big	1500000
f-meas-x	5000
f-meas-y	5000
EOF
( cd "$REPO_ROOT" && env "PATH=$MOCKD:$PATH" "MOCKD=$MOCKD" GH_REPO=jikig-ai/soleur bash -x "$SUT" ) >/dev/null 2>"$MOCKD/stderr"; RC=$?
ERR="$(cat "$MOCKD/stderr")"
[[ "$RC" -eq 78 && "$ERR" == *"xtrace"* ]] && pass "S9c bash -x refused with exit 78" || fail "S9c (rc=$RC)"

# ---- S10: workflow contract --------------------------------------------------
[[ -s "$WF" ]] || fatal "workflow missing: $WF"
wf="$(grep -vE '^[[:space:]]*#' "$WF")"
wf_missing=""
grep -qF "cron: '41 9 * * 2'" <<<"$wf" || wf_missing="$wf_missing cron"
grep -qE '^permissions: \{\}' <<<"$wf" || wf_missing="$wf_missing permissions-top"
grep -qE '^      contents: read$' <<<"$wf" || wf_missing="$wf_missing contents-read"
grep -qE '^      issues: write$' <<<"$wf" || wf_missing="$wf_missing issues-write"
grep -qF 'group: shard-balance-watch' <<<"$wf" || wf_missing="$wf_missing concurrency"
grep -qF 'cancel-in-progress: false' <<<"$wf" || wf_missing="$wf_missing cancel"
grep -qE '^        run: bash scripts/watch-shard-balance-11564\.sh' <<<"$wf" || wf_missing="$wf_missing run"
grep -qE 'dry_run' <<<"$wf" || wf_missing="$wf_missing dry_run-input"
grep -qF "github.repository == 'jikig-ai/soleur'" <<<"$wf" || wf_missing="$wf_missing repo-scope"
[[ -z "$wf_missing" ]] && pass "S10 workflow contract: cron/permissions/concurrency/repo-scope/dry_run/run line" || fail "S10 missing:$wf_missing"

# ---- S11: observed gh call allowlist -----------------------------------------
bad=0
for d in "$ROOT"/mock*; do
  [[ -s "$d/calls" ]] || continue
  while IFS= read -r line; do
    case "$line" in
      "run list "*|"run download "*|"issue list "*|"issue view "*|"issue comment "*|"issue create "*|"issue close "*) ;;
      *) bad=$((bad + 1)); echo "unexpected call: $line" ;;
    esac
  done < "$d/calls"
done
[[ "$bad" -eq 0 ]] && pass "S11 gh call set is a subset of the allowlist" || fail "S11 ($bad unexpected)"

# Exit-gate check
if [[ -z "${WSB_INJECT_FAIL:-}" ]]; then
  WSB_INJECT_FAIL=1 bash "${BASH_SOURCE[0]}" >/dev/null 2>&1; nested_rc=$?
  [[ "$nested_rc" -eq 1 ]] || { printf 'FATAL: exit gate returned %s with one injected failure\n' "$nested_rc" >&2; exit 2; }
else
  fail "injected failure (exit-gate check)"
fi

echo; echo "PASS=$PASS FAIL=$FAIL TOTAL=$TOTAL"
MIN_ASSERTIONS=14
if [[ "$TOTAL" -lt "$MIN_ASSERTIONS" ]]; then
  printf 'FATAL: assertion floor breached (TOTAL=%s < %s)\n' "$TOTAL" "$MIN_ASSERTIONS" >&2; exit 2
fi
finish || exit 1
