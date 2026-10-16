#!/usr/bin/env bash
# shellcheck disable=SC2329,SC2015,SC2016,SC2034  # rows are dispatched indirectly; A && B || why is the assertion idiom; some programs are single-quoted on purpose
# Suite for scripts/ci-pr-affected-preactivation.sh (S4 PR C, #9729, ADR-276): Guard 4, the read-only gate that
# refuses activation until every prerequisite is POSITIVELY read as met.
#
# THE SEAM. `gh` is a PATH stub keyed on the request path; every response is the literal `gh api -i` output
# (a status line, a blank line, a body) so the SUT's status parsing is exercised for real. An unknown request
# exits 64 and logs STUB-MISS; the suite asserts the log holds none. The clock is PR_AFFECTED_PREACT_TODAY.
#
# THE WORLD. One synthesized git repository (the driver, the three artifacts, an ADR with its recorded lines and a
# committed receipt) and one stubbed API in which every prerequisite is met. Each Guard 4 row edits ONE thing in
# that world and requires the right `missing=` AND the right exit code: 1 when a prerequisite is UNMET, 3 when the
# only thing missing is UNKNOWN (the gate could not decide). The UNKNOWN TABLE pins every reader's every unknown
# arm, because an unknown that lands as "met" is the defect class this gate exists to refuse. The must-PASS row is
# the unedited world. MUTATION ROWS copy the SUT, apply ONE edit (asserted to have landed once, to leave valid
# shell, and to leave the row GREEN on the pristine SUT) and require the named row to FAIL against the mutant;
# a survivor control and an invalid-mutant control prove the harness reports both honestly. The floors report
# through printf + exit, never through pass()/fail().
export TMPDIR="${TMPDIR:-/var/tmp}"
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_SUT="$SCRIPT_DIR/../../../scripts/ci-pr-affected-preactivation.sh"
SUT="$REAL_SUT"

passes=0; fails=0; FAILED=()
pass() { passes=$((passes + 1)); echo "  PASS: $1"; }
fail() { fails=$((fails + 1)); FAILED+=("$1"); echo "  FAIL: $1" >&2; }

_iv_p="$passes"; _iv_f="$fails"; _iv_n="${#FAILED[@]}"
{ pass "self-test"; fail "self-test"; } >/dev/null 2>&1
if [[ "$passes" -ne $((_iv_p + 1)) || "$fails" -ne $((_iv_f + 1)) || "${#FAILED[@]}" -ne $((_iv_n + 1)) ]]; then
  printf '[FATAL] instrument self-test: the verdict helpers did not both record\n' >&2; exit 1
fi
passes=0; fails=0; FAILED=()

[[ -f "$REAL_SUT" ]] || { echo "[FATAL] SUT not found at $REAL_SUT" >&2; exit 1; }
for tool in jq python3 git; do
  command -v "$tool" >/dev/null || { echo "[FATAL] $tool required" >&2; exit 1; }
done

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

SANDBOX="$(mktemp -d "$TMPDIR/ci-pr-affected-preact.XXXXXXXX")" || { echo "[FATAL] mktemp failed" >&2; exit 1; }
case "$SANDBOX" in /*) : ;; *) echo "[FATAL] sandbox is not absolute" >&2; exit 1 ;; esac
trap 'rm -rf "$SANDBOX"' EXIT
export TMPDIR="$SANDBOX"

WORLD="$SANDBOX/world"      # the synthesized repository root
GHFIX="$SANDBOX/ghfix"
BIN="$SANDBOX/bin"
GHLOG="$SANDBOX/gh.log"
R=jikig-ai/soleur
TODAY=2026-10-16
KBDIR="knowledge""-base"   # two words, so this suite carries no literal path of the documentation tree (the kb-consumer census)
RCPT_DIR="$KBDIR/project/specs/feat-x/receipts"
ADRF="$WORLD/adr/ADR-276-x.md"

mkdir -p "$BIN" "$GHFIX"
cat > "$BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
# gh api -i <path>
[ "${1:-}" = api ] && [ "${2:-}" = -i ] || { echo "STUB-MISS argv=$*" >> "$GH_LOG"; exit 64; }
key="$(printf '%s' "$3" | tr -c 'A-Za-z0-9\n' '_')"
printf 'REQ %s\n' "$key" >> "$GH_LOG"
if [ -f "$GH_FIX/$key" ]; then cat "$GH_FIX/$key"; exit 0; fi
echo "STUB-MISS $key" >> "$GH_LOG"; exit 64
GHSTUB
chmod +x "$BIN/gh"
export GH_LOG="$GHLOG" GH_FIX="$GHFIX"

resp() {  # resp <path> <status> <body>: the literal `gh api -i` output
  local k; k="$(printf '%s' "$1" | tr -c 'A-Za-z0-9\n' '_')"
  printf 'HTTP/2.0 %s X\nContent-Type: application/json\n\n%s\n' "$2" "$3" > "$GHFIX/$k"
}
silent_fail() {  # the request dies before any status line (a network failure)
  local k; k="$(printf '%s' "$1" | tr -c 'A-Za-z0-9\n' '_')"
  : > "$GHFIX/$k"
}


GITW() {  # git against the synthesized world: every location variable removed, identity pinned, no background work
  assert_fixture_dir "$WORLD"
  env -u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY \
    git -c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false -c init.defaultBranch=main \
        -c maintenance.auto=false -c gc.auto=0 -C "$WORLD" "$@"
}
commit_world() { GITW add -A >/dev/null 2>&1 && GITW commit -q --allow-empty -m world >/dev/null 2>&1; }

RL="Go/no-go receipt: $RCPT_DIR/go-no-go.md"
GOLINE="SOLEUR_PR_AFFECTED_VERDICT verdict=GO ruled=confirmed date=2026-10-10"
adr() { printf '# ADR\n' > "$ADRF"; printf '%s\n' "$@" >> "$ADRF"; }      # adr <line>...: rewrite the ADR
receipt() { printf 'notes\n%s\n' "$1" > "$WORLD/$RCPT_DIR/go-no-go.md"; }   # receipt <last line>

ALLOW_MISS=""; ADR_OVERRIDE=""; TODAY_OVERRIDE=""; RUN_GIT_DIR=""
build_world() {
  assert_fixture_dir "$WORLD"
  rm -rf "$WORLD" "$GHFIX"; mkdir -p "$GHFIX"
  mkdir -p "$WORLD/scripts" "$WORLD/plugins/soleur/scripts" "$WORLD/$RCPT_DIR" "$WORLD/adr"
  GITW init -q >/dev/null 2>&1 || { echo "[FATAL] git init of the synthesized world failed" >&2; exit 1; }
  printf '#!/usr/bin/env bash\n# the driver, activation lock removed\nset -u\n[ "${PR_AFFECTED_LOCKED:-}" = 1 ] && locked=true\n' > "$WORLD/scripts/ci-pr-selection.sh"
  printf '# full-verified subcommand\nfull-verified() { :; }\n' > "$WORLD/plugins/soleur/scripts/ci-head-verdict.sh"
  printf '# calls full-verified\nci-head-verdict.sh full-verified\n' > "$WORLD/plugins/soleur/scripts/admin-merge-ready.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$WORLD/plugins/soleur/scripts/ci-full-battery-audit.sh"; chmod +x "$WORLD/plugins/soleur/scripts/ci-full-battery-audit.sh"
  printf '# suite durations\ntests/hooks/incidents\t1000\nscripts/lib/x.test\t2000\n' > "$WORLD/scripts/suite-durations.tsv"
  receipt "$GOLINE"
  ALLOW_MISS=""; ADR_OVERRIDE=""; TODAY_OVERRIDE=""; RUN_GIT_DIR=""
  adr "$RL" "Skippable set: test-scripts, tests/hooks/incidents"
  resp "repos/$R/actions/variables/CI_PR_AFFECTED" 404 '{"message":"Not Found"}'
  resp "repos/$R/actions/variables" 200 '{"total_count":4,"variables":[]}'
  resp "repos/$R/actions/organization-variables" 200 '{"total_count":0,"variables":[]}'
  resp "repos/$R/actions/workflows/post-merge-monitor.yml/runs?branch=main&per_page=30" 200 '{"workflow_runs":[{"id":501}]}'
  resp "repos/$R/actions/runs/501/jobs?per_page=100" 200 '{"jobs":[{"name":"monitor","conclusion":"skipped"},{"name":"full-battery-audit","conclusion":"success"}]}'
  resp "repos/$R/issues/10415" 200 '{"state":"closed","state_reason":"completed"}'
  resp "search/issues?q=repo:$R+is:pr+draft:false+created:%3E2026-10-15T17:50:38Z&sort=created&order=asc&per_page=30" 200 '{"items":[]}'
  commit_world
  : > "$GHLOG"
}

run_sut() {
  env PATH="$BIN:$PATH" PR_AFFECTED_PREACT_TODAY="${TODAY_OVERRIDE:-$TODAY}" ${RUN_GIT_DIR:+GIT_DIR="$RUN_GIT_DIR"} \
    bash "$SUT" --repo "$R" --root "$WORLD" --adr "${ADR_OVERRIDE:-$ADRF}"
}
OUT=""; RC=0
go_raw() { OUT="$(run_sut 2>"$SANDBOX/stderr")"; RC=$?; }
go() { commit_world; go_raw; }      # commit whatever the row edited, then run: only a row about an UNCOMMITTED file uses go_raw
final() { printf '%s\n' "$OUT" | tail -1; }
missing_of() { final | sed -n 's/.* missing=//p'; }
stub_clean() { [[ -n "$ALLOW_MISS" ]] || ! grep -q STUB-MISS "$GHLOG"; }   # a row whose request the stub did not know proves nothing
expect() { [[ "$RC" -eq "$1" && "$(missing_of)" = "$2" ]] && stub_clean; }   # expect <rc> <missing>; rc 1 = unmet, rc 3 = only unknown
ready() { [[ "$RC" -eq 0 && "$(final)" = "SOLEUR_PR_AFFECTED_PREACTIVATION ready=true missing=none" ]] && stub_clean; }
has_line() { printf '%s\n' "$OUT" | grep -qxF -- "$1"; }
has_pat() { printf '%s\n' "$OUT" | grep -qF -- "$1"; }
ck() { local d="$1"; shift; if "$@"; then pass "$d"; else fail "$d: rc=$RC final='$(final)' out=$(printf '%s' "$OUT" | head -4 | tr '\n' '|') stubmiss=$(grep -m1 STUB-MISS "$GHLOG" 2>/dev/null)"; fi; }

# ---------------------------------------------------------------------------------------------------------------------
echo "== must-PASS: every prerequisite met"
build_world; go
ck "an all-met world reports ready=true and exits 0" ready
has_line 'variable=absent' && has_line 'org_variables=0' && has_line 'lock=absent' && has_line 'artifacts=ok' && has_line 'verdict=GO-confirmed' && has_line 'prereq5=ok' \
  && pass "each of the six prerequisites prints its own line" || fail "the six prerequisite lines: $OUT"
[[ "$(printf '%s\n' "$OUT" | wc -l)" -eq 8 ]] && pass "the output is exactly six prerequisite lines, the ac9c line and the final line (the closed line set)" || fail "closed line set (got $(printf '%s\n' "$OUT" | wc -l) lines)"
has_line 'ac9c=not-yet' && pass "ac9c prints not-yet when no qualifying PR exists, and does not gate" || fail "ac9c not-yet"
stub_clean && pass "the gate made no request the stub does not know" || fail "unknown request: $(grep STUB-MISS "$GHLOG" | head -2)"
[[ ! -s "$SANDBOX/stderr" ]] && pass "a ready run writes nothing to stderr" || fail "stderr on a ready run: $(head -2 "$SANDBOX/stderr")"

# ---------------------------------------------------------------------------------------------------------------------
echo "== UNKNOWN TABLE: every reader's every unknown arm is not-met, names the reader, and exits 3 (nothing was unmet)"
# Each arm edits ONE thing so that the reader cannot tell. A reader that lets "could not tell" land in the met state
# makes the gate lie about readiness; the original battery pinned two of these arms and a composite of the rest read ready=true.
arm_var_500() { resp "repos/$R/actions/variables/CI_PR_AFFECTED" 500 '{"message":"boom"}'; }
arm_var_silent() { silent_fail "repos/$R/actions/variables/CI_PR_AFFECTED"; }
arm_var_list502() { resp "repos/$R/actions/variables" 502 '{}'; }
arm_var_list_empty_body() { resp "repos/$R/actions/variables" 200 '{}'; }
arm_var_contradict() { resp "repos/$R/actions/variables" 200 '{"total_count":1,"variables":[{"name":"CI_PR_AFFECTED"}]}'; }
arm_org_403() { resp "repos/$R/actions/organization-variables" 403 '{"message":"Resource not accessible"}'; }
arm_org_unparse() { resp "repos/$R/actions/organization-variables" 200 'not json'; }
arm_lock_missing() { rm -f "$WORLD/scripts/ci-pr-selection.sh"; }
arm_lock_comment_only() { printf '# only a comment\n#   and another\n' > "$WORLD/scripts/ci-pr-selection.sh"; }
arm_lock_empty() { : > "$WORLD/scripts/ci-pr-selection.sh"; }
arm_art_runs500() { resp "repos/$R/actions/workflows/post-merge-monitor.yml/runs?branch=main&per_page=30" 500 '{}'; }
arm_art_jobs500() { resp "repos/$R/actions/runs/501/jobs?per_page=100" 500 '{}'; }
arm_art_jobs_unparse() { resp "repos/$R/actions/runs/501/jobs?per_page=100" 200 'not json'; }
arm_ver_date_bad() { receipt "SOLEUR_PR_AFFECTED_VERDICT verdict=GO ruled=confirmed date=2026-02-31"; }
arm_ver_today_bad() { TODAY_OVERRIDE=garbage; }
arm_ver_path_escape() { printf 'x\n%s\n' "$GOLINE" > "$SANDBOX/escape.md"; [[ -f "$SANDBOX/escape.md" ]] && adr "Go/no-go receipt: ../escape.md" "Skippable set: test-scripts"; }
arm_p5_hb500() { resp "repos/$R/issues/10415" 500 '{}'; }
arm_p5_hb_state() { resp "repos/$R/issues/10415" 200 '{"state":"weird"}'; }
row_unk() {  # row_unk <arm> <missing> <line fragment>
  build_world; "$1"; go; expect 3 "$2" && has_pat "$3"
}
unk() { local arm="$1" want="$2" frag="$3"; row_unk "$arm" "$want" "$frag" && pass "$arm: $frag" || fail "$arm: expected rc 3, missing=$want, line '$frag'; got rc=$RC final='$(final)' out=$(printf '%s' "$OUT" | head -4 | tr '\n' '|')"; }
unk arm_var_500 variable 'variable=unknown'
unk arm_var_silent variable 'variable=unknown'
unk arm_var_list502 variable 'variable=unknown'
unk arm_var_list_empty_body variable 'variable=unknown(list-unreadable-or-contradicts)'
unk arm_var_contradict variable 'variable=unknown(list-unreadable-or-contradicts)'
unk arm_org_403 org_variables 'org_variables=unknown(http=403)'
unk arm_org_unparse org_variables 'org_variables=unknown(unparseable)'
unk arm_lock_missing lock 'lock=unknown(driver-missing)'
unk arm_lock_comment_only lock 'lock=unknown'
unk arm_lock_empty lock 'lock=unknown'
unk arm_art_runs500 artifacts 'artifacts=unknown(audit-runs-http=500)'
unk arm_art_jobs500 artifacts 'artifacts=unknown(jobs-http=500)'
unk arm_art_jobs_unparse artifacts 'artifacts=unknown(jobs-unparseable)'
unk arm_ver_date_bad verdict 'verdict=unknown(date-unparseable)'
unk arm_ver_today_bad verdict 'verdict=unknown(date-unparseable)'
unk arm_ver_path_escape verdict 'verdict=unknown(receipt-path-rejected)'
unk arm_p5_hb500 prereq5 'prereq5=unknown(heartbeat-http=500)'
unk arm_p5_hb_state prereq5 'prereq5=unknown(heartbeat-state)'
if [[ "$(id -u)" -ne 0 ]]; then
  build_world; chmod 000 "$WORLD/scripts/ci-pr-selection.sh"; go_raw
  expect 3 lock && has_pat 'lock=unknown' && pass "an unreadable driver (mode 000) is unknown, never absent" || fail "unreadable driver: rc=$RC $OUT"
  chmod 644 "$WORLD/scripts/ci-pr-selection.sh"
else
  pass "an unreadable driver: skipped (running as root reads mode 000)"
fi
build_world; ADR_OVERRIDE="$SANDBOX/no-such-adr.md"; go
expect 3 verdict,prereq5 && has_pat 'verdict=unknown(adr-missing)' && has_pat 'prereq5=unknown(adr-missing)' && pass "a missing ADR makes both ADR-backed prerequisites unknown" || fail "adr missing: rc=$RC '$(final)'"
build_world; rm -f "$GHFIX"/*; rm -f "$WORLD/scripts/ci-pr-selection.sh"; ADR_OVERRIDE="$SANDBOX/no-such-adr.md"; ALLOW_MISS=1; go
expect 3 variable,org_variables,lock,artifacts,verdict,prereq5 && pass "exit 3: when every prerequisite is unknown the gate says it could not decide (not exit 1)" || fail "all-unknown: rc=$RC '$(final)'"
build_world; arm_org_403; printf 'readonly PR_AFFECTED_LOCKED=1\n' >> "$WORLD/scripts/ci-pr-selection.sh"; go
expect 1 org_variables,lock && pass "one unmet beside one unknown exits 1 and lists both, in order" || fail "mixed: rc=$RC '$(final)'"

# ---------------------------------------------------------------------------------------------------------------------
echo "== G4-1 organization variables"
build_world; resp "repos/$R/actions/organization-variables" 200 '{"total_count":1,"variables":[{"name":"CI_PR_AFFECTED"}]}'; go
ck "G4-1b a count of 1 is unmet" expect 1 org_variables; has_line 'org_variables=1' || fail "G4-1b line"

echo "== G4-2 and G4-8 prerequisite 5: absent, empty, free text, unregistered, last line wins, waiver shape"
build_world; adr "$RL"; go
ck "G4-2 an ADR with no Skippable set line is not ready" expect 1 prereq5
for v in none empty n/a - TBD '(none)' 'none yet' 'TBD.' 'test-scripts shards' bogus-suite 'test-scripts,bogus-suite' ',,' ; do
  build_world; adr "$RL" "Skippable set: $v"; go
  ck "G4-8 a Skippable set of '$v' is not ready" expect 1 prereq5
done
for v in test-webplat test-bun test-scripts-heavy tests/hooks/incidents 'test-bun, tests/hooks/incidents'; do
  build_world; adr "$RL" "Skippable set: $v"; go
  ck "a Skippable set of '$v' (a gated group or a registered suite) is accepted" ready
done
build_world; adr "$RL" "Skippable set: test-scripts" "Skippable set: none"; go
ck "the LAST Skippable set line wins (a later 'none' is not hidden by an earlier valid line)" expect 1 prereq5
build_world; adr "$RL" "Skippable set: none" "Skippable set: test-scripts"; go
ck "the LAST Skippable set line wins (a later valid line replaces an earlier 'none')" ready
build_world; resp "repos/$R/issues/10415" 200 '{"state":"open"}'; go
ck "an open heartbeat follow-up is not ready" expect 1 prereq5
build_world; resp "repos/$R/issues/10415" 200 '{"state":"open"}'; adr "$RL" "Skippable set: test-scripts" "Waiver: heartbeat accepted by the operator"; go
ck "an explicit waiver line with a reason stands in for the closed heartbeat issue" ready
build_world; resp "repos/$R/issues/10415" 200 '{"state":"open"}'; adr "$RL" "Skippable set: test-scripts" "Waiver: heartbeat"; go
ck "a waiver line with no reason is not a waiver" expect 1 prereq5
build_world; resp "repos/$R/issues/10415" 200 '{"state":"open"}'; adr "$RL" "Skippable set: test-scripts" 'see the line "Waiver: heartbeat accepted" in the plan'; go
ck "a waiver quoted mid-line is not a waiver (the line must start with it)" expect 1 prereq5
build_world; resp "repos/$R/issues/10415" 200 '{"state":"closed","state_reason":"not_planned"}'; go
ck "a heartbeat issue closed as not planned is not a completed follow-up" expect 1 prereq5

echo "== G4-3 the receipt: NO-GO, UNDECIDED, pending, absent, stale, future, malformed, forged"
for line in "SOLEUR_PR_AFFECTED_VERDICT verdict=NO-GO ruled=confirmed date=2026-10-10" \
            "SOLEUR_PR_AFFECTED_VERDICT verdict=UNDECIDED ruled=pending date=2026-10-10" \
            "SOLEUR_PR_AFFECTED_VERDICT verdict=GO ruled=pending date=2026-10-10" \
            "SOLEUR_PR_AFFECTED_VERDICT verdict=GO ruled=confirmed date=2026-08-01" \
            "SOLEUR_PR_AFFECTED_VERDICT verdict=GO ruled=confirmed date=2026-12-01" \
            "SOLEUR_PR_AFFECTED_VERDICT verdict=GO ruled=confirmed" \
            "verdict is GO"; do
  build_world; receipt "$line"; go
  ck "G4-3 '${line#SOLEUR_PR_AFFECTED_VERDICT }' is not ready" expect 1 verdict
done
build_world; receipt "SOLEUR_PR_AFFECTED_VERDICT verdict=GO ruled=confirmed date=2026-12-01"; go
has_pat 'verdict=stale(age_days=-' && pass "a receipt dated after today reads as stale with a negative age" || fail "future date line: $OUT"
build_world; rm -f "$WORLD/$RCPT_DIR/go-no-go.md"; go
ck "G4-3 an absent receipt file is not ready" expect 1 verdict; has_line 'verdict=receipt-absent' || fail "absent receipt line"
build_world; adr "Skippable set: test-scripts"; go
ck "G4-3 an ADR that records no receipt path is not ready" expect 1 verdict
build_world; GITW rm -q --cached "$RCPT_DIR/go-no-go.md" >/dev/null 2>&1; GITW commit -q -m untrack >/dev/null 2>&1; go_raw
[[ -f "$WORLD/$RCPT_DIR/go-no-go.md" ]] && ck "G4-3 a receipt that exists only as an UNTRACKED file proves nothing" expect 1 verdict || fail "untracked setup"
build_world; receipt "SOLEUR_PR_AFFECTED_VERDICT verdict=NO-GO ruled=confirmed date=2026-10-10"; commit_world
printf 'x\n%s\n' "$GOLINE" > "$WORLD/$RCPT_DIR/go-no-go.md"; go_raw
ck "G4-3 an edit to the receipt that is not committed does not change the answer (the committed NO-GO still rules)" expect 1 verdict; has_line 'verdict=NO-GO-confirmed' || fail "dirty receipt line: $OUT"
build_world; printf 'x\n%s\n' "$GOLINE" > "$WORLD/real.md"; rm -f "$WORLD/$RCPT_DIR/go-no-go.md"; ln -s "$WORLD/real.md" "$WORLD/$RCPT_DIR/go-no-go.md"; go
ck "G4-3 a symlink at the receipt path is not a receipt" expect 1 verdict
build_world; ARCH="$KBDIR/project/specs/archive/20261016-000000-feat-x/receipts"; mkdir -p "$WORLD/$ARCH"; mv "$WORLD/$RCPT_DIR/go-no-go.md" "$WORLD/$ARCH/go-no-go.md"; go
ck "G4-3 after ship moves the spec directory the archived receipt is read" ready; has_line 'verdict=GO-confirmed(receipt-archived)' || fail "archived receipt line: $OUT"
build_world; adr "Go/no-go receipt: ../escape.md" "Skippable set: test-scripts"; printf 'x\n%s\n' "$GOLINE" > "$SANDBOX/escape.md"; go
[[ -f "$SANDBOX/escape.md" ]] && ck "G4-3 a receipt path that climbs out of the root is refused although its target exists" expect 3 verdict || fail "escape target missing"
build_world; adr "Go/no-go receipt: $RCPT_DIR/missing.md" "$RL" "Skippable set: test-scripts"; go
ck "G4-3 the LAST receipt line wins (an earlier path to a missing file is replaced by the later valid one)" ready
build_world; adr "$RL" "Go/no-go receipt: $RCPT_DIR/missing.md" "Skippable set: test-scripts"; go
ck "G4-3 the LAST receipt line wins (a later path to a missing file replaces the earlier valid one)" expect 1 verdict
build_world; decoy="$SANDBOX/decoy"; mkdir -p "$decoy"; env -u GIT_DIR -u GIT_INDEX_FILE git -c init.defaultBranch=main init -q "$decoy" >/dev/null 2>&1; RUN_GIT_DIR="$decoy/.git"; go_raw
ck "G4-3 an inherited GIT_DIR does not redirect the committed-tree read (the location variable is removed)" ready

echo "== G4-4 the lock and the audit run"
for spell in 'readonly PR_AFFECTED_LOCKED=1' '  readonly PR_AFFECTED_LOCKED=1' 'declare -r PR_AFFECTED_LOCKED=1' 'export PR_AFFECTED_LOCKED=1' 'PR_AFFECTED_LOCKED=1' 'readonly PR_AFFECTED_LOCKED=1  # ACTIVATION LOCK'; do
  build_world; printf '%s\n' "$spell" >> "$WORLD/scripts/ci-pr-selection.sh"; go
  ck "G4-4a the lock spelled '$spell' is still present" expect 1 lock
done
build_world; printf '# readonly PR_AFFECTED_LOCKED=1 was removed in the last commit\n' >> "$WORLD/scripts/ci-pr-selection.sh"; go
ck "G4-4a a comment that mentions the lock is not the lock" ready
build_world; resp "repos/$R/actions/runs/501/jobs?per_page=100" 200 '{"jobs":[{"name":"full-battery-audit","conclusion":"failure"}]}'; go
ck "G4-4b a failed newest audit run is not ready" expect 1 artifacts
build_world; resp "repos/$R/actions/runs/501/jobs?per_page=100" 200 '{"jobs":[{"name":"monitor","conclusion":"success"}]}'; go
ck "G4-4c no audit job anywhere in the listed runs is not ready" expect 1 artifacts; has_line 'artifacts=no-audit-run' || fail "G4-4c line"
build_world; resp "repos/$R/actions/workflows/post-merge-monitor.yml/runs?branch=main&per_page=30" 200 '{"workflow_runs":[{"id":502},{"id":501}]}'
resp "repos/$R/actions/runs/502/jobs?per_page=100" 200 '{"jobs":[{"name":"full-battery-audit","conclusion":null}]}'; go
ck "G4-4f a NEWEST audit run that is still pending does not fall through to an older success" expect 1 artifacts; has_line 'artifacts=audit-run-pending' || fail "G4-4f line: $OUT"
build_world; resp "repos/$R/actions/workflows/post-merge-monitor.yml/runs?branch=main&per_page=30" 200 '{"workflow_runs":[{"id":502},{"id":501}]}'
resp "repos/$R/actions/runs/502/jobs?per_page=100" 200 '{"jobs":[{"name":"monitor","conclusion":"success"}]}'; go
ck "G4-4g a newer run that has no audit job is skipped over to the newest run that does" ready
build_world; rm -f "$WORLD/plugins/soleur/scripts/ci-full-battery-audit.sh"; go
ck "G4-4d a missing audit script is not ready" expect 1 artifacts
build_world; printf '# no call here\n' > "$WORLD/plugins/soleur/scripts/admin-merge-ready.sh"; go
ck "G4-4e a merge authority that does not call the read is not ready" expect 1 artifacts
build_world; printf '# full-verified appears only in this comment\n:\n' > "$WORLD/plugins/soleur/scripts/ci-head-verdict.sh"; go
ck "G4-4h a read named only in a comment is not the read" expect 1 artifacts

echo "== G4-5 two prerequisites unmet after a met one"
build_world; printf 'readonly PR_AFFECTED_LOCKED=1\n' >> "$WORLD/scripts/ci-pr-selection.sh"; adr "$RL"; go
ck "G4-5 both unmet prerequisites are listed, in order, after the met ones" expect 1 lock,prereq5

echo "== G4-7 the variable read"
build_world; resp "repos/$R/actions/variables/CI_PR_AFFECTED" 200 '{"name":"CI_PR_AFFECTED","value":"on"}'; go
ck "a variable that already exists is unmet (activation already happened or was armed)" expect 1 variable; has_line 'variable=present' || fail "present line"

echo "== ac9c is information only"
build_world
resp "search/issues?q=repo:$R+is:pr+draft:false+created:%3E2026-10-15T17:50:38Z&sort=created&order=asc&per_page=30" 200 '{"items":[{"number":77}]}'
resp "repos/$R/pulls/77/files?per_page=100" 200 "[{\"filename\":\"${KBDIR}/project/x.md\"},{\"filename\":\"README.md\"}]"
resp "repos/$R/pulls/77" 200 '{"head":{"sha":"abc123"}}'
resp "repos/$R/actions/workflows/ci.yml/runs?head_sha=abc123&per_page=100" 200 '{"workflow_runs":[{"id":900,"event":"pull_request"}]}'
resp "repos/$R/actions/runs/900/jobs?per_page=100" 200 '{"jobs":[{"name":"pr-selection","conclusion":"skipped"},{"name":"test-webplat (1/2)","conclusion":"success"},{"name":"test-webplat (2/2)","conclusion":"success"},{"name":"test-bun","conclusion":"success"},{"name":"test-scripts-heavy (1/3)","conclusion":"success"},{"name":"test-scripts (1/8)","conclusion":"success"},{"name":"test","conclusion":"success"}]}'
go
has_line 'ac9c=observed' && [[ "$RC" -eq 0 ]] && pass "a doc-only PR with pr-selection skipped and every leg green is observed (matrix names included)" || fail "ac9c observed: rc=$RC $(printf '%s\n' "$OUT" | grep ac9c)"
resp "repos/$R/actions/runs/900/jobs?per_page=100" 200 '{"jobs":[{"name":"pr-selection","conclusion":"skipped"},{"name":"test-webplat (1/2)","conclusion":"failure"},{"name":"test-bun","conclusion":"success"},{"name":"test-scripts-heavy (1/3)","conclusion":"success"},{"name":"test-scripts (1/8)","conclusion":"success"},{"name":"test","conclusion":"success"}]}'
go
has_line 'ac9c=not-yet' && pass "a skipped pr-selection beside a red leg is not an observation" || fail "ac9c red leg: $(printf '%s\n' "$OUT" | grep ac9c)"
resp "search/issues?q=repo:$R+is:pr+draft:false+created:%3E2026-10-15T17:50:38Z&sort=created&order=asc&per_page=30" 500 '{}'
go
has_line 'ac9c=unknown' && [[ "$RC" -eq 0 ]] && pass "a failing ac9c read prints unknown and never blocks readiness" || fail "ac9c unknown: rc=$RC $(printf '%s\n' "$OUT" | grep ac9c)"

echo "== usage and refusals"
build_world
env PATH="$BIN:$PATH" bash "$SUT" --repo noslash --root "$WORLD" >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 2 ]] && pass "a malformed --repo is refused with rc 2" || fail "malformed --repo (rc=$rc)"
env PATH="$BIN:$PATH" bash "$SUT" --repo "$R" --root relative/path >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 2 ]] && pass "a relative --root is refused with rc 2" || fail "relative --root (rc=$rc)"
env PATH="$BIN:$PATH" bash "$SUT" --nope >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 2 ]] && pass "an unknown argument is refused with rc 2" || fail "unknown argument (rc=$rc)"
helptxt="$(env PATH="$BIN:$PATH" bash "$SUT" --help 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] && printf '%s\n' "$helptxt" | grep -q 'USAGE:' && printf '%s\n' "$helptxt" | grep -q 'Skippable set:' && printf '%s\n' "$helptxt" | grep -q 'EXIT: 0 ready=true' \
  && pass "--help prints the usage, the three ADR line shapes and the exit codes" || fail "--help (rc=$rc): $(printf '%s' "$helptxt" | head -3)"
build_world; go
grep -n 'gh api' "$SUT" | grep -vq -- 'gh api -i' && fail "every request goes through the one reader" || pass "every request goes through the one reader (gh api -i)"
grep -nE 'gh api[^|]*(-X|--method|--input|-f |-F )' "$SUT" >/dev/null && fail "the gate script issues only reads" || pass "the gate script issues only reads (no -X, --method, --input, -f, -F)"
grep -nE 'variables.*(-X|--method|PATCH|POST|PUT|DELETE)' "$SUT" >/dev/null && fail "the gate never mutates the variable" || pass "the gate never mutates the variable"
grep -nE '(^|[^A-Za-z_])git (-C|[a-z])' "$SUT" | grep -v 'git_ro\|^[0-9]*:[[:space:]]*#' >/dev/null && fail "every git call goes through git_ro (location variables removed)" || pass "every git call goes through git_ro (location variables removed)"

# ---------------------------------------------------------------------------------------------------------------------
echo "== mutation rows (each edit lands once, leaves valid shell, leaves the row GREEN on the pristine SUT, and the named row must then FAIL)"
MUT_RUN=0; MUT_KILLED=0
mutant_outcome() {  # mutant_outcome <name> <old> <new> <row>: prints killed | survived | invalid | row-red-on-pristine | edit-failed
  local name="$1" old="$2" new="$3" row="$4" m="$SANDBOX/mut-$1.sh" got
  cp "$REAL_SUT" "$m" || { echo edit-failed; return; }
  python3 - "$m" "$old" "$new" 2>/dev/null <<'PY' || { echo edit-failed; return; }
import sys
p, old, new = sys.argv[1:4]
s = open(p).read()
assert s.count(old) == 1, "count=%d" % s.count(old)
open(p, "w").write(s.replace(old, new))
PY
  cmp -s "$m" "$REAL_SUT" && { echo edit-failed; return; }
  bash -n "$m" 2>/dev/null || { echo invalid; return; }   # a mutant that does not parse crashes every row: that is not a kill
  SUT="$REAL_SUT"; "$row" >/dev/null 2>&1 || { echo row-red-on-pristine; return; }   # a row that is red on the real script kills anything
  SUT="$m"; "$row" >/dev/null 2>&1; got=$?; SUT="$REAL_SUT"
  if [[ "$got" -ne 0 ]]; then echo killed; else echo survived; fi
}
mutate() {  # mutate <name> <old> <new> <row>
  local r; r="$(mutant_outcome "$@")"
  MUT_RUN=$((MUT_RUN + 1))
  if [[ "$r" = killed ]]; then MUT_KILLED=$((MUT_KILLED + 1)); pass "mutant $1 is killed by $4"; else fail "mutant $1: $r (row $4)"; fi
}
row_all_met() { build_world; go; ready; }
row_org_403() { row_unk arm_org_403 org_variables 'org_variables=unknown'; }
row_org_count1() { build_world; resp "repos/$R/actions/organization-variables" 200 '{"total_count":1}'; go; expect 1 org_variables; }
row_bad_item() { build_world; adr "$RL" "Skippable set: test-scripts, bogus-suite"; go; expect 1 prereq5; }
row_prereq5_absent() { build_world; adr "$RL"; go; expect 1 prereq5; }
row_ruled_pending() { build_world; receipt "SOLEUR_PR_AFFECTED_VERDICT verdict=GO ruled=pending date=2026-10-10"; go; expect 1 verdict; }
row_stale() { build_world; receipt "SOLEUR_PR_AFFECTED_VERDICT verdict=GO ruled=confirmed date=2026-08-01"; go; expect 1 verdict; }
row_future() { build_world; receipt "SOLEUR_PR_AFFECTED_VERDICT verdict=GO ruled=confirmed date=2026-12-01"; go; expect 1 verdict; }
row_two_unmet() { build_world; printf 'readonly PR_AFFECTED_LOCKED=1\n' >> "$WORLD/scripts/ci-pr-selection.sh"; adr "$RL"; go; expect 1 lock,prereq5; }
row_var_500() { row_unk arm_var_500 variable 'variable=unknown'; }
row_audit_failed() { build_world; resp "repos/$R/actions/runs/501/jobs?per_page=100" 200 '{"jobs":[{"name":"full-battery-audit","conclusion":"failure"}]}'; go; expect 1 artifacts; }
row_heartbeat_open() { build_world; resp "repos/$R/issues/10415" 200 '{"state":"open"}'; go; expect 1 prereq5; }
row_lock_spellings() { build_world; printf '  readonly PR_AFFECTED_LOCKED=1\n' >> "$WORLD/scripts/ci-pr-selection.sh"; go; expect 1 lock || return 1
  build_world; printf 'declare -r PR_AFFECTED_LOCKED=1\n' >> "$WORLD/scripts/ci-pr-selection.sh"; go; expect 1 lock; }
row_lock_comment_only() { row_unk arm_lock_comment_only lock 'lock=unknown'; }
row_comment_token() { build_world; printf '# full-verified appears only in this comment\n:\n' > "$WORLD/plugins/soleur/scripts/ci-head-verdict.sh"; go; expect 1 artifacts; }
row_pending_newest() { build_world; resp "repos/$R/actions/workflows/post-merge-monitor.yml/runs?branch=main&per_page=30" 200 '{"workflow_runs":[{"id":502},{"id":501}]}'
  resp "repos/$R/actions/runs/502/jobs?per_page=100" 200 '{"jobs":[{"name":"full-battery-audit","conclusion":null}]}'; go; expect 1 artifacts; }
row_date_bad() { row_unk arm_ver_date_bad verdict 'verdict=unknown(date-unparseable)'; }
row_dirty_receipt() { build_world; receipt "SOLEUR_PR_AFFECTED_VERDICT verdict=NO-GO ruled=confirmed date=2026-10-10"; commit_world
  printf 'x\n%s\n' "$GOLINE" > "$WORLD/$RCPT_DIR/go-no-go.md"; go_raw; expect 1 verdict; }
row_last_line_wins() { build_world; adr "$RL" "Skippable set: test-scripts" "Skippable set: none"; go; expect 1 prereq5 || return 1
  build_world; adr "$RL" "Go/no-go receipt: $RCPT_DIR/missing.md" "Skippable set: test-scripts"; go; expect 1 verdict; }
row_waiver() { build_world; resp "repos/$R/issues/10415" 200 '{"state":"open"}'; adr "$RL" "Skippable set: test-scripts" "Waiver: heartbeat"; go; expect 1 prereq5 || return 1
  build_world; resp "repos/$R/issues/10415" 200 '{"state":"open"}'; adr "$RL" "Skippable set: test-scripts" 'see the line "Waiver: heartbeat accepted" in the plan'; go; expect 1 prereq5; }
row_not_planned() { build_world; resp "repos/$R/issues/10415" 200 '{"state":"closed","state_reason":"not_planned"}'; go; expect 1 prereq5; }
row_contradict() { row_unk arm_var_contradict variable 'variable=unknown'; }
row_exit3() { build_world; rm -f "$GHFIX"/*; rm -f "$WORLD/scripts/ci-pr-selection.sh"; ADR_OVERRIDE="$SANDBOX/no-such-adr.md"; ALLOW_MISS=1; go
  expect 3 variable,org_variables,lock,artifacts,verdict,prereq5; }
row_archived() { build_world; ARCH="$KBDIR/project/specs/archive/20261016-000000-feat-x/receipts"; mkdir -p "$WORLD/$ARCH"; mv "$WORLD/$RCPT_DIR/go-no-go.md" "$WORLD/$ARCH/go-no-go.md"; go; ready; }
row_path_escape() { row_unk arm_ver_path_escape verdict 'verdict=unknown(receipt-path-rejected)'; }
row_git_dir() { build_world; local d="$SANDBOX/decoy-m"; mkdir -p "$d"; env -u GIT_DIR -u GIT_INDEX_FILE git -c init.defaultBranch=main init -q "$d" >/dev/null 2>&1; RUN_GIT_DIR="$d/.git"; go_raw; ready; }
row_empty_list() {  # G4-6: the SUT under test, with its prerequisite list emptied, must refuse with rc 2 and never report ready
  local e="$SANDBOX/empty-list.sh"; cp "$SUT" "$e" || return 1
  python3 - "$e" <<'PY' || return 1
import sys
p = sys.argv[1]; s = open(p).read()
old = "READERS=(variable org_variables lock artifacts verdict prereq5)"
assert s.count(old) == 1
open(p, "w").write(s.replace(old, "READERS=()"))
PY
  build_world
  local out rc=0; out="$(env PATH="$BIN:$PATH" PR_AFFECTED_PREACT_TODAY="$TODAY" bash "$e" --repo "$R" --root "$WORLD" --adr "$ADRF" 2>/dev/null)" || rc=$?
  [[ "$rc" -eq 2 ]] && ! printf '%s' "$out" | grep -q 'ready=true'
}
mutate unknown-counts-as-met '    ok) ok=$((ok + 1)) ;;' '    ok|unknown) ok=$((ok + 1)) ;;' row_org_403
mutate org-count-ignored '    *) R_STATUS=unmet; R_LINE="org_variables=$n" ;;' '    *) R_STATUS=ok; R_LINE="org_variables=$n" ;;' row_org_count1
mutate unregistered-item-accepted '      *) registered_suite "$item" || { bad="$item"; break; } ;;' '      *) : ;;' row_bad_item
mutate prereq5-reader-dropped 'READERS=(variable org_variables lock artifacts verdict prereq5)' 'READERS=(variable org_variables lock artifacts verdict)' row_prereq5_absent
mutate ruled-ignored 'if [ "$v" != GO ] || [ "$r" != confirmed ]; then' 'if [ "$v" != GO ]; then' row_ruled_pending
mutate staleness-ignored 'if [ "$age" -lt 0 ] || [ "$age" -gt 60 ]; then' 'if [ "$age" -lt 0 ]; then' row_stale
mutate future-date-allowed 'if [ "$age" -lt 0 ] || [ "$age" -gt 60 ]; then' 'if [ "$age" -gt 60 ]; then' row_future
mutate first-failure-only '    unmet) unmet=$((unmet + 1)); missing="${missing:+$missing,}$name" ;;' '    unmet) unmet=$((unmet + 1)); missing="${missing:-$name}" ;;' row_two_unmet
mutate variable-read-loose 'if [ "$s1" = 404 ] && [ "$s2" = 200 ]; then' 'if [ "$s1" != 200 ]; then' row_var_500
mutate variable-list-crosscheck-dropped '(.variables | type == "array") and ([.variables[].name] | index("CI_PR_AFFECTED") | not)' 'true' row_contradict
mutate audit-failure-ok '    *) R_STATUS=unmet; R_LINE="artifacts=audit-run-$found" ;;' '    *) R_STATUS=ok; R_LINE="artifacts=audit-run-$found" ;;' row_audit_failed
mutate pending-falls-through '(.conclusion // "pending")' '(.conclusion // "skipped")' row_pending_newest
mutate open-heartbeat-ok '    open) R_STATUS=unmet; R_LINE="prereq5=heartbeat-open" ;;' '    open) R_STATUS=ok; R_LINE="prereq5=heartbeat-open" ;;' row_heartbeat_open
mutate not-planned-ok 'if [ "$reason" = not_planned ]; then' 'if false; then' row_not_planned
mutate lock-regex-narrow "'PR_AFFECTED_LOCKED[[:space:]]*\\+?=|(readonly|declare|typeset|export)[[:space:]].*PR_AFFECTED_LOCKED'" "'^readonly PR_AFFECTED_LOCKED='" row_lock_spellings
mutate comment-strip-dropped "grep -v '^[[:space:]]*#' \"\$1\" 2>/dev/null" 'cat "$1" 2>/dev/null' row_lock_comment_only
mutate comment-token-accepted "code_of \"\$root/plugins/soleur/scripts/ci-head-verdict.sh\" | grep -q 'full-verified'" "grep -q 'full-verified' \"\$root/plugins/soleur/scripts/ci-head-verdict.sh\"" row_comment_token
mutate date-failure-reads-zero '    || { R_STATUS=unknown; R_LINE="verdict=unknown(date-unparseable)"; return; }' '    || { t_now=0; t_rec=0; }' row_date_bad
mutate receipt-from-worktree 'text="$(git_ro -C "$root" show "HEAD:$rp" 2>/dev/null)" || text=""' 'text="$(cat "$root/$rp" 2>/dev/null)" || text=""' row_dirty_receipt
mutate archive-fallback-dropped '    rel="$(git_ro -C "$root" ls-tree -r --name-only HEAD 2>/dev/null | grep -E "$cand" | sort | tail -1)"' '    rel=""' row_archived
mutate receipt-path-guard-dropped '  case "$rp" in /*|*..*) R_STATUS=unknown; R_LINE="verdict=unknown(receipt-path-rejected)"; return ;; esac' '  :' row_path_escape
mutate adr-first-line-wins 'adr_line() { sed -n "s/^$1:[[:space:]]*//p" "$adr" | tail -1; }' 'adr_line() { sed -n "s/^$1:[[:space:]]*//p" "$adr" | head -1; }' row_last_line_wins
mutate waiver-unanchored "grep -Eq '^Waiver: heartbeat[[:space:]]+[^[:space:]]' \"\$adr\"" "grep -q 'Waiver: heartbeat' \"\$adr\"" row_waiver
mutate git-location-inherited 'git_ro() { env -u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE -u GIT_COMMON_DIR git "$@"; }' 'git_ro() { git "$@"; }' row_git_dir
mutate exit3-dropped '[ "$unmet" -eq 0 ] && exit 3' '[ "$unmet" -eq 0 ] && exit 1' row_exit3
mutate ok-requires-nothing 'if [ "$total" -gt 0 ] && [ "$ok" -eq "$total" ]; then' 'if [ "$total" -gt 0 ]; then' row_two_unmet
mutate list-empty-guard-dropped 'if [ "${#READERS[@]}" -eq 0 ]; then echo' 'if false; then echo' row_empty_list

echo "== harness controls: the mutation harness reports a survivor, an unparseable mutant and a red row honestly"
row_always_red() { false; }
[[ "$(mutant_outcome ctl-survive '# SEAMS:' '# SEAMS (edited):' row_all_met)" = survived ]] && pass "control: an edit outside the logic is reported as a SURVIVOR" || fail "control: survivor not reported"
[[ "$(mutant_outcome ctl-invalid 'set -uo pipefail' 'set -uo pipefail )(' row_org_403)" = invalid ]] && pass "control: a mutant that does not parse is INVALID, not killed" || fail "control: invalid mutant not reported"
[[ "$(mutant_outcome ctl-red 'set -uo pipefail' 'set -uo pipefail ' row_always_red)" = row-red-on-pristine ]] && pass "control: a row that is red on the pristine SUT is reported, not counted as a kill" || fail "control: red row not reported"
[[ "$(mutant_outcome ctl-nolanding 'THIS TEXT IS NOT IN THE SCRIPT' 'x' row_all_met)" = edit-failed ]] && pass "control: an edit that does not land is reported" || fail "control: edit-failed not reported"

echo "== G4-6 the prerequisite list is empty"
row_empty_list && pass "G4-6 an emptied prerequisite list exits 2 and never reports ready (anti-vacuity)" || fail "G4-6 an emptied prerequisite list exits 2"
echo "== control: the unmutated world still passes after the battery"
row_all_met && pass "the unmutated SUT still reports ready=true (the control)" || fail "the unmutated SUT still reports ready=true (the control)"
if [[ "$MUT_KILLED" -eq "$MUT_RUN" ]]; then pass "every mutant was killed ($MUT_KILLED of $MUT_RUN)"; else fail "mutants killed $MUT_KILLED of $MUT_RUN"; fi

FLOOR_ASSERTIONS=133
total=$((passes + fails))
if [[ "$total" -lt "$FLOOR_ASSERTIONS" ]]; then
  printf '[FATAL] anti-vacuity floor: only %s assertions ran, floor is %s\n' "$total" "$FLOOR_ASSERTIONS" >&2; exit 1
fi
FLOOR_MUTANTS=27
if [[ "$MUT_RUN" -lt "$FLOOR_MUTANTS" ]]; then
  printf '[FATAL] mutation floor: only %s mutants ran, floor is %s\n' "$MUT_RUN" "$FLOOR_MUTANTS" >&2; exit 1
fi
echo "ci-pr-affected-preactivation.test.sh: $passes passed, $fails failed, $total assertions, $MUT_RUN mutants"
[[ "$fails" -eq 0 ]] && exit 0
printf 'FAILED: %s\n' "${FAILED[@]}" >&2
exit 1
