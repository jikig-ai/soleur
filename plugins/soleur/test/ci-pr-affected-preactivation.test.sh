#!/usr/bin/env bash
# shellcheck disable=SC2329,SC2015,SC2016,SC2034,SC1003,SC1091  # rows are dispatched indirectly; A && B || why is the assertion idiom; some programs are single-quoted on purpose
# Suite for scripts/ci-pr-affected-preactivation.sh (S4 PR C, #9729, ADR-276): Guard 4, the read-only gate that
# refuses activation until every prerequisite is POSITIVELY read as met.
#
# THE SEAM. `gh` is a PATH stub keyed on the request path; every response is the literal `gh api -i` output as the
# real tool prints it (CRLF line ends, a reason phrase, exit 1 on a 4xx/5xx) so the SUT's status parsing is exercised
# for real. An unknown request exits 64 and logs STUB-MISS; the suite asserts the log holds none. The clock is
# PR_AFFECTED_PREACT_TODAY. The gate reads the COMMITTED tree (HEAD) and compares HEAD to the API's tip of main, so the
# world is a real git repository whose HEAD sha the stub serves as `main`.
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
# shellcheck source=lib/git-fixture-env.sh
source "$SCRIPT_DIR/lib/git-fixture-env.sh"   # arms the git-location tripwire and gives git_fixture_env (one list, one builder)
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
# gh api -i <path>: prints the stored response; exits 0 on a 2xx and 1 otherwise, as the real tool does
[ "${1:-}" = api ] && [ "${2:-}" = -i ] || { echo "STUB-MISS argv=$*" >> "$GH_LOG"; exit 64; }
key="$(printf '%s' "$3" | tr -c 'A-Za-z0-9\n' '_')"
printf 'REQ %s\n' "$key" >> "$GH_LOG"
if [ -f "$GH_FIX/$key" ]; then
  cat "$GH_FIX/$key"
  code="$(awk 'NR == 1 { print $2; exit }' "$GH_FIX/$key")"
  case "$code" in 2*) exit 0 ;; *) exit 1 ;; esac
fi
echo "STUB-MISS $key" >> "$GH_LOG"; exit 64
GHSTUB
chmod +x "$BIN/gh"
export GH_LOG="$GHLOG" GH_FIX="$GHFIX"

keyof_path() { printf '%s' "$1" | tr -c 'A-Za-z0-9\n' '_'; }
resp() {  # resp <path> <status> <body>: the literal `gh api -i` output, CRLF line ends and a reason phrase included
  local k reason; k="$(keyof_path "$1")"
  case "$2" in 200) reason=OK ;; 404) reason="Not Found" ;; 403) reason=Forbidden ;; 502) reason="Bad Gateway" ;; *) reason="Error" ;; esac
  printf 'HTTP/2.0 %s %s\r\nContent-Type: application/json\r\n\r\n%s\n' "$2" "$reason" "$3" > "$GHFIX/$k"
}
silent_fail() {  # the request dies before any status line (a network failure)
  : > "$GHFIX/$(keyof_path "$1")"
}

GITW() {  # git against the synthesized world: the environment is git_fixture_env's, the rest is pinned on the command line
  assert_fixture_dir "$WORLD"
  git -c commit.gpgsign=false -c init.defaultBranch=main -c maintenance.auto=false -c gc.auto=0 -C "$WORLD" "$@"
}
commit_world() { GITW add -A >/dev/null 2>&1 && GITW commit -q --allow-empty -m world >/dev/null 2>&1; }
refresh_main() { resp "repos/$R/commits/main" 200 "{\"sha\":\"$(GITW rev-parse HEAD)\"}"; }   # the API's tip of main IS the world's HEAD

RL="Go/no-go receipt: $RCPT_DIR/go-no-go.md"
GOLINE="SOLEUR_PR_AFFECTED_VERDICT verdict=GO ruled=confirmed date=2026-10-10"
adr() { printf '# ADR\n' > "$ADRF"; printf '%s\n' "$@" >> "$ADRF"; }      # adr <line>...: rewrite the ADR
receipt() { printf 'notes\n%s\n' "$1" > "$WORLD/$RCPT_DIR/go-no-go.md"; }   # receipt <last line>
ARCH_DIR="$KBDIR/project/specs/archive/20261016-000000-feat-x/receipts"

ALLOW_MISS=""; ADR_OVERRIDE=""; TODAY_OVERRIDE=""; RUN_GIT_DIR=""; SHIM_PATH=""
REAL_SED="$(command -v sed)"
mkdir -p "$SANDBOX/shim"
printf '#!/usr/bin/env bash\ncase "$*" in *PR_AFFECTED_LOCKED*) exit 1 ;; esac\nexec "%s" "$@"\n' "$REAL_SED" > "$SANDBOX/shim/sed"; chmod +x "$SANDBOX/shim/sed"
build_world() {
  assert_fixture_dir "$WORLD"
  rm -rf "$WORLD" "$GHFIX"; mkdir -p "$GHFIX"
  mkdir -p "$WORLD/scripts" "$WORLD/plugins/soleur/scripts" "$WORLD/$RCPT_DIR" "$WORLD/adr"
  git_fixture_env "$WORLD" || { echo "[FATAL] git_fixture_env refused the world" >&2; exit 1; }
  GITW init -q >/dev/null 2>&1 || { echo "[FATAL] git init of the synthesized world failed" >&2; exit 1; }
  printf '#!/usr/bin/env bash\n# the driver, activation lock removed\nset -u\n[ "${PR_AFFECTED_LOCKED:-}" = 1 ] && locked=true\n' > "$WORLD/scripts/ci-pr-selection.sh"
  printf '# full-verified subcommand\nfull-verified() { :; }\n' > "$WORLD/plugins/soleur/scripts/ci-head-verdict.sh"
  printf '# calls full-verified\nci-head-verdict.sh full-verified\n' > "$WORLD/plugins/soleur/scripts/admin-merge-ready.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$WORLD/plugins/soleur/scripts/ci-full-battery-audit.sh"; chmod +x "$WORLD/plugins/soleur/scripts/ci-full-battery-audit.sh"
  printf '# suite durations\ntests/hooks/incidents\t1000\nscripts/lib/x.test\t2000\n' > "$WORLD/scripts/suite-durations.tsv"
  receipt "$GOLINE"
  ALLOW_MISS=""; ADR_OVERRIDE=""; TODAY_OVERRIDE=""; RUN_GIT_DIR=""; SHIM_PATH=""
  adr "$RL" "Skippable set: test-bun, tests/hooks/incidents"
  resp "repos/$R/actions/variables/CI_PR_AFFECTED" 404 '{"message":"Not Found"}'
  resp "repos/$R/actions/variables?per_page=100" 200 '{"total_count":4,"variables":[{"name":"A"},{"name":"B"},{"name":"C"},{"name":"D"}]}'
  resp "repos/$R/actions/organization-variables" 200 '{"total_count":0,"variables":[]}'
  resp "repos/$R/actions/workflows/post-merge-monitor.yml/runs?branch=main&per_page=30" 200 '{"workflow_runs":[{"id":501}]}'
  resp "repos/$R/actions/runs/501/jobs?per_page=100" 200 '{"jobs":[{"name":"monitor","conclusion":"skipped"},{"name":"full-battery-audit","conclusion":"success"}]}'
  resp "repos/$R/issues/10415" 200 '{"state":"closed","state_reason":"completed"}'
  resp "search/issues?q=repo:$R+is:pr+draft:false+created:%3E2026-10-15T17:50:38Z&sort=created&order=asc&per_page=30" 200 '{"items":[]}'
  commit_world
  refresh_main
  : > "$GHLOG"
}

run_sut() {
  env PATH="${SHIM_PATH:+$SHIM_PATH:}$BIN:$PATH" PR_AFFECTED_PREACT_TODAY="${TODAY_OVERRIDE:-$TODAY}" ${RUN_GIT_DIR:+GIT_DIR="$RUN_GIT_DIR"} \
    bash "$SUT" --repo "$R" --root "$WORLD" ${ADR_OVERRIDE:+--adr "$ADR_OVERRIDE"}
}
OUT=""; RC=0
go_raw() { OUT="$(run_sut 2>"$SANDBOX/stderr")"; RC=$?; }
go() { commit_world; refresh_main; go_raw; }      # commit whatever the row edited, point `main` at it, run: only a row about an UNCOMMITTED edit uses go_raw
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
has_line 'variable=absent' && has_line 'org_variables=0' && has_line 'lock=absent' && has_line 'artifacts=ok' && has_line 'verdict=GO-confirmed' && has_line 'prereq5=ok' && has_line 'tree=head-is-main' \
  && pass "each of the seven prerequisites prints its own line" || fail "the seven prerequisite lines: $OUT"
[[ "$(printf '%s\n' "$OUT" | wc -l)" -eq 9 ]] && pass "the output is exactly seven prerequisite lines, the ac9c line and the final line (the closed line set)" || fail "closed line set (got $(printf '%s\n' "$OUT" | wc -l) lines)"
has_line 'ac9c=not-yet' && pass "ac9c prints not-yet when no qualifying PR exists, and does not gate" || fail "ac9c not-yet"
stub_clean && pass "the gate made no request the stub does not know" || fail "unknown request: $(grep STUB-MISS "$GHLOG" | head -2)"
[[ ! -s "$SANDBOX/stderr" ]] && pass "a ready run writes nothing to stderr" || fail "stderr on a ready run: $(head -2 "$SANDBOX/stderr")"

# ---------------------------------------------------------------------------------------------------------------------
echo "== UNKNOWN TABLE: every reader's every unknown arm is not-met, names the reader, and exits 3 (nothing was unmet)"
# Each arm edits ONE thing so that the reader cannot tell. A reader that lets "could not tell" land in the met state
# makes the gate lie about readiness.
arm_var_500() { resp "repos/$R/actions/variables/CI_PR_AFFECTED" 500 '{"message":"boom"}'; }
arm_var_silent() { silent_fail "repos/$R/actions/variables/CI_PR_AFFECTED"; }
arm_var_list502() { resp "repos/$R/actions/variables?per_page=100" 502 '{}'; }
arm_var_list_empty_body() { resp "repos/$R/actions/variables?per_page=100" 200 '{}'; }
arm_var_list_short() { resp "repos/$R/actions/variables?per_page=100" 200 '{"total_count":12,"variables":[{"name":"A"}]}'; }
arm_var_contradict() { resp "repos/$R/actions/variables?per_page=100" 200 '{"total_count":1,"variables":[{"name":"CI_PR_AFFECTED"}]}'; }
arm_org_403() { resp "repos/$R/actions/organization-variables" 403 '{"message":"Resource not accessible"}'; }
arm_org_unparse() { resp "repos/$R/actions/organization-variables" 200 'not json'; }
arm_org_fraction() { resp "repos/$R/actions/organization-variables" 200 '{"total_count":1.5}'; }
arm_lock_missing() { rm -f "$WORLD/scripts/ci-pr-selection.sh"; }
arm_lock_comment_only() { printf '# only a comment\n#   and another\n' > "$WORLD/scripts/ci-pr-selection.sh"; }
arm_lock_empty() { : > "$WORLD/scripts/ci-pr-selection.sh"; }
arm_lock_transform_fails() { SHIM_PATH="$SANDBOX/shim"; }
arm_art_runs500() { resp "repos/$R/actions/workflows/post-merge-monitor.yml/runs?branch=main&per_page=30" 500 '{}'; }
arm_art_runs_unparse() { resp "repos/$R/actions/workflows/post-merge-monitor.yml/runs?branch=main&per_page=30" 200 '{"workflow_runs":"x"}'; }
arm_art_jobs500() { resp "repos/$R/actions/runs/501/jobs?per_page=100" 500 '{}'; }
arm_art_jobs_unparse() { resp "repos/$R/actions/runs/501/jobs?per_page=100" 200 'not json'; }
arm_art_jobs_truncated() { resp "repos/$R/actions/runs/501/jobs?per_page=100" 200 '{"total_count":5,"jobs":[{"name":"monitor","conclusion":"success"}]}'; }
arm_ver_date_bad() { receipt "SOLEUR_PR_AFFECTED_VERDICT verdict=GO ruled=confirmed date=2026-02-31"; }
arm_ver_today_bad() { TODAY_OVERRIDE=garbage; }
arm_ver_today_natural() { TODAY_OVERRIDE="2026-10-10 + 30 days"; }
arm_ver_path_escape() { printf 'x\n%s\n' "$GOLINE" > "$SANDBOX/escape.md"; [[ -f "$SANDBOX/escape.md" ]] && adr "Go/no-go receipt: ../escape.md" "Skippable set: test-bun"; }
arm_ver_archive_ambiguous() {
  local a1="$WORLD/$KBDIR/project/specs/archive/20261016-000000-feat-x/receipts" a2="$WORLD/$KBDIR/project/specs/archive/20261017-000000-feat-x/receipts"
  mkdir -p "$a1" "$a2"; cp "$WORLD/$RCPT_DIR/go-no-go.md" "$a1/"; cp "$WORLD/$RCPT_DIR/go-no-go.md" "$a2/"; rm -f "$WORLD/$RCPT_DIR/go-no-go.md"
}
arm_p5_hb500() { resp "repos/$R/issues/10415" 500 '{}'; }
arm_p5_hb_state() { resp "repos/$R/issues/10415" 200 '{"state":"weird"}'; }
arm_tree_500() { resp "repos/$R/commits/main" 500 '{}'; }
arm_tree_unparse() { resp "repos/$R/commits/main" 200 '{"sha":"not-a-sha"}'; }
row_unk() {  # row_unk <arm> <missing> <line fragment>
  build_world; "$1"; go_unk "$1"; expect 3 "$2" && has_pat "$3"
}
go_unk() {  # the tree arms must not be overwritten by go()'s refresh_main
  case "$1" in arm_tree_*) commit_world; go_raw ;; *) go ;; esac
}
unk() { local arm="$1" want="$2" frag="$3"; row_unk "$arm" "$want" "$frag" && pass "$arm: $frag" || fail "$arm: expected rc 3, missing=$want, line '$frag'; got rc=$RC final='$(final)' out=$(printf '%s' "$OUT" | head -4 | tr '\n' '|')"; }
unk arm_var_500 variable 'variable=unknown'
unk arm_var_silent variable 'variable=unknown'
unk arm_var_list502 variable 'variable=unknown'
unk arm_var_list_empty_body variable 'variable=unknown(list-unreadable-or-contradicts)'
unk arm_var_list_short variable 'variable=unknown(list-unreadable-or-contradicts)'
unk arm_var_contradict variable 'variable=unknown(list-unreadable-or-contradicts)'
unk arm_org_403 org_variables 'org_variables=unknown(http=403)'
unk arm_org_unparse org_variables 'org_variables=unknown(unparseable)'
unk arm_org_fraction org_variables 'org_variables=unknown(unparseable)'
unk arm_lock_missing lock 'lock=unknown(driver-missing)'
unk arm_lock_comment_only lock 'lock=unknown'
unk arm_lock_empty lock 'lock=unknown'
unk arm_lock_transform_fails lock 'lock=unknown(transform-failed)'
unk arm_art_runs500 artifacts 'artifacts=unknown(audit-runs-http=500)'
unk arm_art_runs_unparse artifacts 'artifacts=unknown(runs-unparseable)'
unk arm_art_jobs500 artifacts 'artifacts=unknown(jobs-http=500)'
unk arm_art_jobs_unparse artifacts 'artifacts=unknown(jobs-unparseable)'
unk arm_art_jobs_truncated artifacts 'artifacts=unknown(jobs-truncated)'
unk arm_ver_date_bad verdict 'verdict=unknown(date-unparseable)'
unk arm_ver_today_bad verdict 'verdict=unknown(date-unparseable)'
unk arm_ver_today_natural verdict 'verdict=unknown(date-unparseable)'
unk arm_ver_path_escape verdict 'verdict=unknown(receipt-path-rejected)'
unk arm_ver_archive_ambiguous verdict 'verdict=unknown(receipt-archive-ambiguous)'
unk arm_p5_hb500 prereq5 'prereq5=unknown(heartbeat-http=500)'
unk arm_p5_hb_state prereq5 'prereq5=unknown(heartbeat-state)'
unk arm_tree_500 tree 'tree=unknown(main-http=500)'
unk arm_tree_unparse tree 'tree=unknown(main-unparseable)'
if [[ "$(id -u)" -ne 0 ]]; then
  # a mode-000 file is unreadable on disk, but the gate reads the COMMITTED blob: the on-disk mode must not matter
  build_world; chmod 000 "$WORLD/scripts/ci-pr-selection.sh"; go
  ready && pass "the gate reads the committed blob: an unreadable working-tree copy changes nothing" || fail "unreadable working copy: rc=$RC $OUT"
  chmod 644 "$WORLD/scripts/ci-pr-selection.sh"
else
  pass "an unreadable working copy: skipped (running as root reads mode 000)"
fi
build_world; ADR_OVERRIDE="$SANDBOX/no-such-adr.md"; go
expect 3 verdict,prereq5 && has_pat 'verdict=unknown(adr-missing)' && has_pat 'prereq5=unknown(adr-missing)' && pass "a missing ADR makes both ADR-backed prerequisites unknown" || fail "adr missing: rc=$RC '$(final)'"
build_world; printf '# ADR twin\n' > "$WORLD/adr/ADR-276-y.md"; go
expect 3 verdict,prereq5 && pass "two committed ADR-276 files are ambiguous: the gate will not pick one" || fail "adr ambiguous: rc=$RC '$(final)'"
build_world; rm -f "$GHFIX"/*; rm -f "$WORLD/scripts/ci-pr-selection.sh"; ADR_OVERRIDE="$SANDBOX/no-such-adr.md"; ALLOW_MISS=1; commit_world; go_raw
expect 3 variable,org_variables,lock,artifacts,verdict,prereq5,tree && pass "exit 3: when every prerequisite is unknown the gate says it could not decide (not exit 1)" || fail "all-unknown: rc=$RC '$(final)'"
build_world; arm_org_403; printf 'readonly PR_AFFECTED_LOCKED=1\n' >> "$WORLD/scripts/ci-pr-selection.sh"; go
expect 1 org_variables,lock && pass "one unmet beside one unknown exits 1 and lists both, in order" || fail "mixed: rc=$RC '$(final)'"

# ---------------------------------------------------------------------------------------------------------------------
echo "== G4-9 the tree: HEAD must be the API's tip of main, and only HEAD counts"
build_world; resp "repos/$R/commits/main" 200 "{\"sha\":\"$(printf 'a%.0s' $(seq 1 40))\"}"; go_raw
ck "G4-9a a HEAD that is not the tip of main is unmet (a feature branch cannot read as main)" expect 1 tree; has_pat 'tree=head-is-not-main(head=' || fail "tree line"
build_world; printf 'readonly PR_AFFECTED_LOCKED=1\n' >> "$WORLD/scripts/ci-pr-selection.sh"; commit_world; refresh_main
printf '#!/usr/bin/env bash\nset -u\n' > "$WORLD/scripts/ci-pr-selection.sh"; go_raw
ck "G4-9b a lock removed only in the working tree still reads present (HEAD is what counts)" expect 1 lock
build_world; resp "repos/$R/issues/10415" 200 '{"state":"open"}'; printf 'Waiver: heartbeat added after the last commit\n' >> "$ADRF"; go_raw
ck "G4-9c a waiver added to the ADR but not committed does not waive" expect 1 prereq5
build_world; ADR_OVERRIDE="$SANDBOX/adr-file.md"; printf '# ADR\n%s\nSkippable set: test-webplat\n' "$RL" > "$ADR_OVERRIDE"; go
ck "G4-9d --adr FILE reads that file instead of the committed ADR (the drill seam)" ready
has_pat 'verdict=GO-confirmed(adr-from-file)' && has_pat 'prereq5=ok(adr-from-file)' && pass "the drill seam marks the lines it feeds, so a ready=true from a file ADR cannot pass for the committed one" || fail "adr seam marker: $OUT"

# ---------------------------------------------------------------------------------------------------------------------
echo "== G4-1 organization variables"
build_world; resp "repos/$R/actions/organization-variables" 200 '{"total_count":1,"variables":[{"name":"CI_PR_AFFECTED"}]}'; go
ck "G4-1b a count of 1 is unmet" expect 1 org_variables; has_line 'org_variables=1' || fail "G4-1b line"

echo "== G4-2 and G4-8 prerequisite 5: absent, empty, free text, unregistered, groups, last line wins, waiver shape"
build_world; adr "$RL"; go
ck "G4-2 an ADR with no Skippable set line is not ready" expect 1 prereq5
for v in none empty n/a - TBD '(none)' 'none yet' 'TBD.' 'test-bun shards' bogus-suite 'test-bun,bogus-suite' ',,' test-scripts tests; do
  build_world; adr "$RL" "Skippable set: $v"; go
  ck "G4-8 a Skippable set of '$v' is not ready" expect 1 prereq5
done
for v in test-webplat test-bun test-scripts-heavy tests/hooks/incidents 'test-bun, tests/hooks/incidents'; do
  build_world; adr "$RL" "Skippable set: $v"; go
  ck "a Skippable set of '$v' (a gated group or a registered suite) is accepted" ready
done
build_world; adr "$RL" "Skippable set: test-bun" "Skippable set: none"; go
ck "the LAST Skippable set line wins (a later 'none' is not hidden by an earlier valid line)" expect 1 prereq5
build_world; adr "$RL" "Skippable set: none" "Skippable set: test-bun"; go
ck "the LAST Skippable set line wins (a later valid line replaces an earlier 'none')" ready
build_world; resp "repos/$R/issues/10415" 200 '{"state":"open"}'; go
ck "an open heartbeat follow-up is not ready" expect 1 prereq5
build_world; resp "repos/$R/issues/10415" 200 '{"state":"open"}'; adr "$RL" "Skippable set: test-bun" "Waiver: heartbeat accepted by the operator"; go
ck "an explicit waiver line with a reason stands in for the closed heartbeat issue" ready
build_world; resp "repos/$R/issues/10415" 200 '{"state":"open"}'; adr "$RL" "Skippable set: test-bun" "Waiver: heartbeat"; go
ck "a waiver line with no reason is not a waiver" expect 1 prereq5
build_world; resp "repos/$R/issues/10415" 200 '{"state":"open"}'; adr "$RL" "Skippable set: test-bun" 'see the line "Waiver: heartbeat accepted" in the plan'; go
ck "a waiver quoted mid-line is not a waiver (the line must start with it)" expect 1 prereq5
build_world; resp "repos/$R/issues/10415" 200 '{"state":"open"}'; adr "$RL" "Skippable set: test-bun" "Waiver: heartbeat <non-empty reason>"; go
ck "the grammar's own placeholder ('<non-empty reason>') is not a waiver reason" expect 1 prereq5
build_world; resp "repos/$R/issues/10415" 200 '{"state":"closed","state_reason":"completed","pull_request":{"url":"x"}}'; go
ck "a --heartbeat-issue number that is really a pull request does not count as the follow-up" expect 1 prereq5; has_line 'prereq5=heartbeat-is-a-pull-request' || fail "heartbeat PR line: $OUT"
build_world; resp "repos/$R/issues/10415" 200 '{"state":"open"}'; adr "$RL" "Skippable set: test-bun" "Waiver: heartbeat accepted" "Waiver: none"; go
ck "the LAST Waiver line wins (a later retraction cancels an earlier waiver)" expect 1 prereq5
build_world; resp "repos/$R/issues/10415" 200 '{"state":"open"}'; adr "$RL" "Skippable set: test-bun" "Waiver: none" "Waiver: heartbeat accepted"; go
ck "the LAST Waiver line wins (a later waiver replaces an earlier retraction)" ready
for sr in not_planned duplicate null; do
  build_world; resp "repos/$R/issues/10415" 200 "{\"state\":\"closed\",\"state_reason\":$( [ "$sr" = null ] && echo null || echo "\"$sr\"" )}"; go
  ck "a heartbeat issue closed as '$sr' is not a completed follow-up" expect 1 prereq5
done

echo "== G4-3 the receipt: NO-GO, UNDECIDED, pending, absent, stale, future, malformed, forged, archived"
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
build_world; receipt "SOLEUR_PR_AFFECTED_VERDICT verdict=GO ruled=confirmed date=2026-08-17"; go
ck "G4-3 a receipt exactly 60 days old is still fresh" ready
build_world; receipt "SOLEUR_PR_AFFECTED_VERDICT verdict=GO ruled=confirmed date=2026-08-16"; go
ck "G4-3 a receipt 61 days old is stale" expect 1 verdict
build_world; printf 'notes\n%s\nSOLEUR_PR_AFFECTED_VERDICT verdict=NO-GO ruled=confirmed date=2026-10-12\n' "$GOLINE" > "$WORLD/$RCPT_DIR/go-no-go.md"; go
ck "G4-3 a later NO-GO line after an earlier GO line rules (the receipt ENDS in its verdict)" expect 1 verdict; has_line 'verdict=NO-GO-confirmed' || fail "two-line receipt: $OUT"
build_world; printf 'notes\nSOLEUR_PR_AFFECTED_VERDICT verdict=NO-GO ruled=confirmed date=2026-10-05\n%s\n' "$GOLINE" > "$WORLD/$RCPT_DIR/go-no-go.md"; go
ck "G4-3 a later GO line after an earlier NO-GO line rules (the last line, not the first, decides)" ready
build_world; rm -f "$WORLD/$RCPT_DIR/go-no-go.md"; go
ck "G4-3 an absent receipt file is not ready" expect 1 verdict; has_line 'verdict=receipt-absent' || fail "absent receipt line"
build_world; adr "Skippable set: test-bun"; go
ck "G4-3 an ADR that records no receipt path is not ready" expect 1 verdict
build_world; GITW rm -q --cached "$RCPT_DIR/go-no-go.md" >/dev/null 2>&1; GITW commit -q -m untrack >/dev/null 2>&1; refresh_main; go_raw
[[ -f "$WORLD/$RCPT_DIR/go-no-go.md" ]] && ck "G4-3 a receipt that exists only as an UNTRACKED file proves nothing" expect 1 verdict || fail "untracked setup"
build_world; receipt "SOLEUR_PR_AFFECTED_VERDICT verdict=NO-GO ruled=confirmed date=2026-10-10"; commit_world; refresh_main
printf 'x\n%s\n' "$GOLINE" > "$WORLD/$RCPT_DIR/go-no-go.md"; go_raw
ck "G4-3 an edit to the receipt that is not committed does not change the answer (the committed NO-GO still rules)" expect 1 verdict; has_line 'verdict=NO-GO-confirmed' || fail "dirty receipt line: $OUT"
build_world; printf 'x\n%s\n' "$GOLINE" > "$WORLD/real.md"; rm -f "$WORLD/$RCPT_DIR/go-no-go.md"; ln -s "$WORLD/real.md" "$WORLD/$RCPT_DIR/go-no-go.md"; go
ck "G4-3 a symlink at the receipt path is not a receipt" expect 1 verdict
build_world; rm -f "$WORLD/$RCPT_DIR/go-no-go.md"; ln -s "$GOLINE" "$WORLD/$RCPT_DIR/go-no-go.md"; go
ck "G4-3 a symlink whose TARGET TEXT is the machine line is not a receipt (the blob mode is checked, not only its bytes)" expect 1 verdict
build_world; mkdir -p "$WORLD/$ARCH_DIR"; cp "$WORLD/$RCPT_DIR/go-no-go.md" "$WORLD/$ARCH_DIR/"; rm -f "$WORLD/$RCPT_DIR/go-no-go.md"; ln -s elsewhere "$WORLD/$RCPT_DIR/go-no-go.md"; go
ck "G4-3 a symlink that is PRESENT at the receipt path does not hand over to an archived copy (the archive is for an ABSENT path)" expect 1 verdict
build_world; mkdir -p "$WORLD/$ARCH_DIR"; mv "$WORLD/$RCPT_DIR/go-no-go.md" "$WORLD/$ARCH_DIR/go-no-go.md"; go
ck "G4-3 after ship moves the spec directory the archived receipt is read" ready; has_line 'verdict=GO-confirmed(receipt-archived)' || fail "archived receipt line: $OUT"
build_world; WRONG="$WORLD/$KBDIR/project/specs/archive/20261016-000000-other-feat-x/receipts"; mkdir -p "$WRONG"; mv "$WORLD/$RCPT_DIR/go-no-go.md" "$WRONG/go-no-go.md"; go
ck "G4-3 an archive directory that merely ENDS in the feature name is another feature's receipt, not this one's" expect 1 verdict
build_world; adr "Go/no-go receipt: ../escape.md" "Skippable set: test-bun"; printf 'x\n%s\n' "$GOLINE" > "$SANDBOX/escape.md"; go
[[ -f "$SANDBOX/escape.md" ]] && ck "G4-3 a receipt path that climbs out of the root is refused although its target exists" expect 3 verdict || fail "escape target missing"
build_world; mkdir -p "$WORLD/other/specs/x"; printf 'x\n%s\n' "$GOLINE" > "$WORLD/other/specs/x/go-no-go.md"; adr "Go/no-go receipt: receipts/go-no-go.md" "Skippable set: test-bun"; go
ck "G4-3 a receipt path that is absent and not under a specs directory has no archive to fall back to" expect 1 verdict
build_world; adr "Go/no-go receipt: $RCPT_DIR/missing.md" "$RL" "Skippable set: test-bun"; go
ck "G4-3 the LAST receipt line wins (an earlier path to a missing file is replaced by the later valid one)" ready
build_world; adr "$RL" "Go/no-go receipt: $RCPT_DIR/missing.md" "Skippable set: test-bun"; go
ck "G4-3 the LAST receipt line wins (a later path to a missing file replaces the earlier valid one)" expect 1 verdict
build_world; decoy="$SANDBOX/decoy"; mkdir -p "$decoy"; env -u GIT_DIR -u GIT_INDEX_FILE git -c init.defaultBranch=main init -q "$decoy" >/dev/null 2>&1; RUN_GIT_DIR="$decoy/.git"; go_raw
ck "G4-3 an inherited GIT_DIR does not redirect the committed-tree read (the location variable is removed)" ready

echo "== G4-4 the lock and the audit run"
for spell in 'readonly PR_AFFECTED_LOCKED=1' '  readonly PR_AFFECTED_LOCKED=1' 'declare -r PR_AFFECTED_LOCKED=1' 'export PR_AFFECTED_LOCKED=1' 'PR_AFFECTED_LOCKED=1' 'readonly PR_AFFECTED_LOCKED=1  # ACTIVATION LOCK' \
             ': "${PR_AFFECTED_LOCKED:=1}"' 'printf -v PR_AFFECTED_LOCKED %s 1' 'read -r PR_AFFECTED_LOCKED <<<1' 'local PR_AFFECTED_LOCKED=1'; do
  build_world; printf '%s\n' "$spell" >> "$WORLD/scripts/ci-pr-selection.sh"; go
  ck "G4-4a the lock spelled '$spell' is still present" expect 1 lock
done
build_world; printf '# readonly PR_AFFECTED_LOCKED=1 was removed in the last commit\n' >> "$WORLD/scripts/ci-pr-selection.sh"; go
ck "G4-4a a comment that mentions the lock is not the lock" ready
build_world; printf '[ "$PR_AFFECTED_LOCKED" = 1 ] && echo "${PR_AFFECTED_LOCKED}" "${PR_AFFECTED_LOCKED:-no}"\n' >> "$WORLD/scripts/ci-pr-selection.sh"; go
ck "G4-4a plain reads of the name (\$X, \${X}, \${X:-d}) are not the lock" ready
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
build_world; chmod -x "$WORLD/plugins/soleur/scripts/ci-full-battery-audit.sh"; go
ck "G4-4d a committed audit script that is not executable is not ready" expect 1 artifacts
build_world; printf '# no call here\n' > "$WORLD/plugins/soleur/scripts/admin-merge-ready.sh"; go
ck "G4-4e a merge authority that does not call the read is not ready" expect 1 artifacts
build_world; printf '# full-verified appears only in this comment\n:\n' > "$WORLD/plugins/soleur/scripts/ci-head-verdict.sh"; go
ck "G4-4h a read named only in a comment is not the read (ci-head-verdict.sh)" expect 1 artifacts
build_world; printf '# full-verified appears only in this comment\n:\n' > "$WORLD/plugins/soleur/scripts/admin-merge-ready.sh"; go
ck "G4-4h a call named only in a comment is not the call (admin-merge-ready.sh)" expect 1 artifacts

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

echo "== usage, refusals and parity"
build_world
env PATH="$BIN:$PATH" bash "$SUT" --repo noslash --root "$WORLD" >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 2 ]] && pass "a malformed --repo is refused with rc 2" || fail "malformed --repo (rc=$rc)"
env PATH="$BIN:$PATH" bash "$SUT" --repo "$R" --root relative/path >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 2 ]] && pass "a relative --root is refused with rc 2" || fail "relative --root (rc=$rc)"
env PATH="$BIN:$PATH" bash "$SUT" --nope >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 2 ]] && pass "an unknown argument is refused with rc 2" || fail "unknown argument (rc=$rc)"
helptxt="$(env PATH="$BIN:$PATH" bash "$SUT" --help 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] && printf '%s\n' "$helptxt" | grep -q 'USAGE:' && printf '%s\n' "$helptxt" | grep -q 'Skippable set:' && printf '%s\n' "$helptxt" | grep -q 'EXIT: 0 ready=true' \
  && printf '%s\n' "$helptxt" | grep -q 'NEEDS: gh' && pass "--help prints the needs, the prerequisites, the three ADR line shapes and the exit codes" || fail "--help (rc=$rc): $(printf '%s' "$helptxt" | head -3)"
build_world; go
grep -n 'gh api' "$SUT" | grep -vq -- 'gh api -i' && fail "every request goes through the one reader" || pass "every request goes through the one reader (gh api -i)"
grep -nE 'gh api[^|]*(-X|--method|--input|-f |-F )' "$SUT" >/dev/null && fail "the gate script issues only reads" || pass "the gate script issues only reads (no -X, --method, --input, -f, -F)"
grep -nE 'variables.*(-X|--method|PATCH|POST|PUT|DELETE)' "$SUT" >/dev/null && fail "the gate never mutates the variable" || pass "the gate never mutates the variable"
grep -nE '(^|[^A-Za-z_])git (-C|[a-z])' "$SUT" | grep -v 'git_ro\|^[0-9]*:[[:space:]]*#' >/dev/null && fail "every git call goes through git_ro (location variables removed)" || pass "every git call goes through git_ro (location variables removed)"
REPO_ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
gate_git="$(awk '/^git_ro\(\)/,/^}/' "$REAL_SUT" | grep -o 'GIT_[A-Z_]*' | sort -u)"
lib_git="$(printf '%s\n' "${GIT_LOCATION_VARS[@]}" | sort -u)"
[[ -n "$gate_git" && "$gate_git" = "$lib_git" ]] && pass "the gate's git_ro unsets exactly the fixture lib's nine git-location names (the replay suite pins the replay tool to the same list)" || fail "git location list parity: gate='${gate_git//$'\n'/ }' lib='${lib_git//$'\n'/ }'"
ci_groups="$(sed -n "s/.*skip_re='^(\([^)]*\)).*/\1/p" "$REPO_ROOT_DIR/.github/workflows/ci.yml" | head -1 | tr '|' '\n' | sort -u)"
gate_groups="$(sed -n 's/^ *\(test-webplat[^)]*\)) : ;;$/\1/p' "$REAL_SUT" | head -1 | tr '|' '\n' | sort -u)"
[[ -n "$ci_groups" && "$ci_groups" = "$gate_groups" ]] && pass "the gate's gated groups are the groups ci.yml may skip (skip_re), no more and no fewer" || fail "gated group parity: ci='${ci_groups//$'\n'/ }' gate='${gate_groups//$'\n'/ }'"

# ---------------------------------------------------------------------------------------------------------------------
echo "== mutation rows (each edit lands once, leaves valid shell, leaves the row GREEN on the pristine SUT, and the named row must then FAIL)"
MUT_RUN=0; MUT_KILLED=0
declare -A PRISTINE_OK=()
MUT_RESULT=""
mutant_outcome() {  # mutant_outcome <name> <old> <new> <row>: sets MUT_RESULT = killed | survived | invalid | row-red-on-pristine | edit-failed
  local name="$1" old="$2" new="$3" row="$4" m="$SANDBOX/mut-$1.sh" got
  cp "$REAL_SUT" "$m" || { MUT_RESULT=edit-failed; return 0; }
  python3 - "$m" "$old" "$new" 2>/dev/null <<'PY' || { MUT_RESULT=edit-failed; return 0; }
import sys
p, old, new = sys.argv[1:4]
s = open(p).read()
assert s.count(old) == 1, "count=%d" % s.count(old)
open(p, "w").write(s.replace(old, new))
PY
  cmp -s "$m" "$REAL_SUT" && { MUT_RESULT=edit-failed; return 0; }
  bash -n "$m" 2>/dev/null || { MUT_RESULT=invalid; return 0; }   # a mutant that does not parse crashes every row: that is not a kill
  if [[ -z "${PRISTINE_OK[$row]:-}" ]]; then   # a row that is red on the real script would "kill" anything; checked once per row
    SUT="$REAL_SUT"; "$row" >/dev/null 2>&1 || { MUT_RESULT="row-red-on-pristine"; return 0; }
    PRISTINE_OK[$row]=1
  fi
  SUT="$m"; "$row" >/dev/null 2>&1; got=$?; SUT="$REAL_SUT"
  if [[ "$got" -ne 0 ]]; then MUT_RESULT=killed; else MUT_RESULT=survived; fi
}
mutate() {  # mutate <name> <old> <new> <row>
  mutant_outcome "$@"
  MUT_RUN=$((MUT_RUN + 1))
  if [[ "$MUT_RESULT" = killed ]]; then MUT_KILLED=$((MUT_KILLED + 1)); pass "mutant $1 is killed by $4"; else fail "mutant $1: $MUT_RESULT (row $4)"; fi
}
row_all_met() { build_world; go; ready; }
row_org_403() { row_unk arm_org_403 org_variables 'org_variables=unknown'; }
row_org_count1() { build_world; resp "repos/$R/actions/organization-variables" 200 '{"total_count":1}'; go; expect 1 org_variables; }
row_org_fraction() { row_unk arm_org_fraction org_variables 'org_variables=unknown'; }
row_bad_item() { build_world; adr "$RL" "Skippable set: test-bun, bogus-suite"; go; expect 1 prereq5; }
row_group_scripts() { build_world; adr "$RL" "Skippable set: test-scripts"; go; expect 1 prereq5; }
row_substring_label() { build_world; adr "$RL" "Skippable set: tests"; go; expect 1 prereq5; }
row_prereq5_absent() { build_world; adr "$RL"; go; expect 1 prereq5; }
row_ruled_pending() { build_world; receipt "SOLEUR_PR_AFFECTED_VERDICT verdict=GO ruled=pending date=2026-10-10"; go; expect 1 verdict; }
row_stale() { build_world; receipt "SOLEUR_PR_AFFECTED_VERDICT verdict=GO ruled=confirmed date=2026-08-16"; go; expect 1 verdict; }
row_fresh_60() { build_world; receipt "SOLEUR_PR_AFFECTED_VERDICT verdict=GO ruled=confirmed date=2026-08-17"; go; ready; }
row_future() { build_world; receipt "SOLEUR_PR_AFFECTED_VERDICT verdict=GO ruled=confirmed date=2026-12-01"; go; expect 1 verdict; }
row_two_lines() { build_world; printf 'notes\n%s\nSOLEUR_PR_AFFECTED_VERDICT verdict=NO-GO ruled=confirmed date=2026-10-12\n' "$GOLINE" > "$WORLD/$RCPT_DIR/go-no-go.md"; go; expect 1 verdict; }
row_two_unmet() { build_world; printf 'readonly PR_AFFECTED_LOCKED=1\n' >> "$WORLD/scripts/ci-pr-selection.sh"; adr "$RL"; go; expect 1 lock,prereq5; }
row_var_500() { row_unk arm_var_500 variable 'variable=unknown'; }
row_audit_failed() { build_world; resp "repos/$R/actions/runs/501/jobs?per_page=100" 200 '{"jobs":[{"name":"full-battery-audit","conclusion":"failure"}]}'; go; expect 1 artifacts; }
row_audit_not_exec() { build_world; chmod -x "$WORLD/plugins/soleur/scripts/ci-full-battery-audit.sh"; go; expect 1 artifacts; }
row_heartbeat_open() { build_world; resp "repos/$R/issues/10415" 200 '{"state":"open"}'; go; expect 1 prereq5; }
row_hb_duplicate() { build_world; resp "repos/$R/issues/10415" 200 '{"state":"closed","state_reason":"duplicate"}'; go; expect 1 prereq5; }
row_lock_spellings() { build_world; printf '  readonly PR_AFFECTED_LOCKED=1\n' >> "$WORLD/scripts/ci-pr-selection.sh"; go; expect 1 lock || return 1
  build_world; printf ': "${PR_AFFECTED_LOCKED:=1}"\n' >> "$WORLD/scripts/ci-pr-selection.sh"; go; expect 1 lock || return 1
  build_world; printf 'printf -v PR_AFFECTED_LOCKED %%s 1\n' >> "$WORLD/scripts/ci-pr-selection.sh"; go; expect 1 lock; }
row_lock_reads_ok() { build_world; printf '[ "$PR_AFFECTED_LOCKED" = 1 ] && echo "${PR_AFFECTED_LOCKED}" "${PR_AFFECTED_LOCKED:-no}"\n' >> "$WORLD/scripts/ci-pr-selection.sh"; go; ready; }
row_lock_comment_only() { row_unk arm_lock_comment_only lock 'lock=unknown'; }
row_comment_token() { build_world; printf '# full-verified appears only in this comment\n:\n' > "$WORLD/plugins/soleur/scripts/ci-head-verdict.sh"; go; expect 1 artifacts; }
row_comment_call() { build_world; printf '# full-verified appears only in this comment\n:\n' > "$WORLD/plugins/soleur/scripts/admin-merge-ready.sh"; go; expect 1 artifacts; }
row_pending_newest() { build_world; resp "repos/$R/actions/workflows/post-merge-monitor.yml/runs?branch=main&per_page=30" 200 '{"workflow_runs":[{"id":502},{"id":501}]}'
  resp "repos/$R/actions/runs/502/jobs?per_page=100" 200 '{"jobs":[{"name":"full-battery-audit","conclusion":null}]}'; go; expect 1 artifacts; }
row_jobs_truncated() { row_unk arm_art_jobs_truncated artifacts 'artifacts=unknown(jobs-truncated)'; }
row_runs_unparse() { row_unk arm_art_runs_unparse artifacts 'artifacts=unknown(runs-unparseable)'; }
row_date_bad() { row_unk arm_ver_date_bad verdict 'verdict=unknown(date-unparseable)'; }
row_today_natural() { row_unk arm_ver_today_natural verdict 'verdict=unknown(date-unparseable)'; }
row_dirty_receipt() { build_world; receipt "SOLEUR_PR_AFFECTED_VERDICT verdict=NO-GO ruled=confirmed date=2026-10-10"; commit_world; refresh_main
  printf 'x\n%s\n' "$GOLINE" > "$WORLD/$RCPT_DIR/go-no-go.md"; go_raw; expect 1 verdict; }
row_symlink_text() { build_world; rm -f "$WORLD/$RCPT_DIR/go-no-go.md"; ln -s "$GOLINE" "$WORLD/$RCPT_DIR/go-no-go.md"; go; expect 1 verdict; }
row_symlink_with_archive() { build_world; mkdir -p "$WORLD/$ARCH_DIR"; cp "$WORLD/$RCPT_DIR/go-no-go.md" "$WORLD/$ARCH_DIR/"; rm -f "$WORLD/$RCPT_DIR/go-no-go.md"; ln -s elsewhere "$WORLD/$RCPT_DIR/go-no-go.md"; go; expect 1 verdict; }
row_archive_wrong_feature() { build_world; local w="$WORLD/$KBDIR/project/specs/archive/20261016-000000-other-feat-x/receipts"; mkdir -p "$w"; mv "$WORLD/$RCPT_DIR/go-no-go.md" "$w/go-no-go.md"; go; expect 1 verdict; }
row_archive_ambiguous() { row_unk arm_ver_archive_ambiguous verdict 'verdict=unknown(receipt-archive-ambiguous)'; }
row_last_line_wins() { build_world; adr "$RL" "Skippable set: test-bun" "Skippable set: none"; go; expect 1 prereq5 || return 1
  build_world; adr "$RL" "Go/no-go receipt: $RCPT_DIR/missing.md" "Skippable set: test-bun"; go; expect 1 verdict; }
row_waiver() { build_world; resp "repos/$R/issues/10415" 200 '{"state":"open"}'; adr "$RL" "Skippable set: test-bun" "Waiver: heartbeat"; go; expect 1 prereq5 || return 1
  build_world; resp "repos/$R/issues/10415" 200 '{"state":"open"}'; adr "$RL" "Skippable set: test-bun" 'see the line "Waiver: heartbeat accepted" in the plan'; go; expect 1 prereq5; }
row_waiver_last() { build_world; resp "repos/$R/issues/10415" 200 '{"state":"open"}'; adr "$RL" "Skippable set: test-bun" "Waiver: heartbeat accepted" "Waiver: none"; go; expect 1 prereq5; }
row_waiver_placeholder() { build_world; resp "repos/$R/issues/10415" 200 '{"state":"open"}'; adr "$RL" "Skippable set: test-bun" "Waiver: heartbeat <non-empty reason>"; go; expect 1 prereq5; }
row_hb_pr() { build_world; resp "repos/$R/issues/10415" 200 '{"state":"closed","state_reason":"completed","pull_request":{"url":"x"}}'; go; expect 1 prereq5; }
row_lock_transform() { row_unk arm_lock_transform_fails lock 'lock=unknown(transform-failed)'; }
row_contradict() { row_unk arm_var_contradict variable 'variable=unknown'; }
row_list_short() { row_unk arm_var_list_short variable 'variable=unknown'; }
row_exit3() { build_world; rm -f "$GHFIX"/*; rm -f "$WORLD/scripts/ci-pr-selection.sh"; ADR_OVERRIDE="$SANDBOX/no-such-adr.md"; ALLOW_MISS=1; commit_world; go_raw
  expect 3 variable,org_variables,lock,artifacts,verdict,prereq5,tree; }
row_archived() { build_world; mkdir -p "$WORLD/$ARCH_DIR"; mv "$WORLD/$RCPT_DIR/go-no-go.md" "$WORLD/$ARCH_DIR/go-no-go.md"; go; ready; }
row_path_escape() { row_unk arm_ver_path_escape verdict 'verdict=unknown(receipt-path-rejected)'; }
row_git_dir() { build_world; local d="$SANDBOX/decoy-m"; mkdir -p "$d"; env -u GIT_DIR -u GIT_INDEX_FILE git -c init.defaultBranch=main init -q "$d" >/dev/null 2>&1; RUN_GIT_DIR="$d/.git"; go_raw; ready; }
row_tree_differs() { build_world; resp "repos/$R/commits/main" 200 "{\"sha\":\"$(printf 'a%.0s' $(seq 1 40))\"}"; go_raw; expect 1 tree; }
row_lock_head_only() { build_world; printf 'readonly PR_AFFECTED_LOCKED=1\n' >> "$WORLD/scripts/ci-pr-selection.sh"; commit_world; refresh_main
  printf '#!/usr/bin/env bash\nset -u\n' > "$WORLD/scripts/ci-pr-selection.sh"; go_raw; expect 1 lock; }
row_empty_list() {  # G4-6: the SUT under test, with its prerequisite list emptied, must refuse with rc 2 and never report ready
  local e="$SANDBOX/empty-list.sh"; cp "$SUT" "$e" || return 1
  python3 - "$e" <<'PY' || return 1
import sys
p = sys.argv[1]; s = open(p).read()
old = "READERS=(variable org_variables lock artifacts verdict prereq5 tree)"
assert s.count(old) == 1
open(p, "w").write(s.replace(old, "READERS=()"))
PY
  build_world
  local out rc=0; out="$(env PATH="$BIN:$PATH" PR_AFFECTED_PREACT_TODAY="$TODAY" bash "$e" --repo "$R" --root "$WORLD" 2>/dev/null)" || rc=$?
  [[ "$rc" -eq 2 ]] && ! printf '%s' "$out" | grep -q 'ready=true'
}
mutate unknown-counts-as-met '    ok) ok=$((ok + 1)) ;;' '    ok|unknown) ok=$((ok + 1)) ;;' row_org_403
mutate org-count-ignored '    *) R_STATUS=unmet; R_LINE="org_variables=$n" ;;' '    *) R_STATUS=ok; R_LINE="org_variables=$n" ;;' row_org_count1
mutate org-fraction-accepted '    *[!0-9]*) R_STATUS=unknown; R_LINE="org_variables=unknown(unparseable)" ;;' '    *[!0-9]*) R_STATUS=ok; R_LINE="org_variables=unknown(unparseable)" ;;' row_org_fraction
mutate unregistered-item-accepted '      *) registered_suite "$item" || { bad="$item"; break; } ;;' '      *) : ;;' row_bad_item
mutate group-list-widened '      test-webplat|test-bun|test-scripts-heavy) : ;;' '      test-webplat|test-bun|test-scripts-heavy|test-scripts) : ;;' row_group_scripts
mutate substring-label-accepted '$0 !~ /^#/ && $1 == want { found = 1 }' '$0 !~ /^#/ && index($1, want) > 0 { found = 1 }' row_substring_label
mutate prereq5-reader-dropped 'READERS=(variable org_variables lock artifacts verdict prereq5 tree)' 'READERS=(variable org_variables lock artifacts verdict tree)' row_prereq5_absent
mutate ruled-ignored 'if [ "$v" != GO ] || [ "$r" != confirmed ]; then' 'if [ "$v" != GO ]; then' row_ruled_pending
mutate staleness-ignored 'if [ "$age" -lt 0 ] || [ "$age" -gt 60 ]; then' 'if [ "$age" -lt 0 ]; then' row_stale
mutate staleness-window-widened 'if [ "$age" -lt 0 ] || [ "$age" -gt 60 ]; then' 'if [ "$age" -lt 0 ] || [ "$age" -gt 75 ]; then' row_stale
mutate staleness-window-narrowed 'if [ "$age" -lt 0 ] || [ "$age" -gt 60 ]; then' 'if [ "$age" -lt 0 ] || [ "$age" -ge 60 ]; then' row_fresh_60
mutate future-date-allowed 'if [ "$age" -lt 0 ] || [ "$age" -gt 60 ]; then' 'if [ "$age" -gt 60 ]; then' row_future
mutate receipt-first-machine-line "last=\"\$(printf '%s\\n' \"\$text\" | grep -v '^[[:space:]]*\$' | tail -1)\"" "last=\"\$(printf '%s\\n' \"\$text\" | grep '^SOLEUR_PR_AFFECTED_VERDICT ' | head -1)\"" row_two_lines
mutate first-failure-only '    unmet) unmet=$((unmet + 1)); missing="${missing:+$missing,}$name" ;;' '    unmet) unmet=$((unmet + 1)); missing="${missing:-$name}" ;;' row_two_unmet
mutate variable-read-loose 'if [ "$s1" = 404 ] && [ "$s2" = 200 ]; then' 'if [ "$s1" != 200 ]; then' row_var_500
mutate variable-list-crosscheck-dropped '(.variables | type == "array") and (.total_count == (.variables | length)) and ([.variables[].name] | index("CI_PR_AFFECTED") | not)' 'true' row_contradict
mutate variable-list-total-ignored '(.total_count == (.variables | length)) and ' '' row_list_short
mutate audit-failure-ok '    *) R_STATUS=unmet; R_LINE="artifacts=audit-run-$found" ;;' '    *) R_STATUS=ok; R_LINE="artifacts=audit-run-$found" ;;' row_audit_failed
mutate audit-script-mode-dropped '[ "$(committed_mode plugins/soleur/scripts/ci-full-battery-audit.sh)" = 100755 ]' '[ -n "$(committed_mode plugins/soleur/scripts/ci-full-battery-audit.sh)" ]' row_audit_not_exec
mutate pending-falls-through '(.conclusion // "pending")' '(.conclusion // "skipped")' row_pending_newest
mutate jobs-truncated-ignored '[ "$n" = 0 ] || { R_STATUS=unknown; R_LINE="artifacts=unknown(jobs-truncated)"; return; }' ':' row_jobs_truncated
mutate runs-unparseable-ignored '    || { R_STATUS=unknown; R_LINE="artifacts=unknown(runs-unparseable)"; return; }' '    || runs=""' row_runs_unparse
mutate open-heartbeat-ok '    open) R_STATUS=unmet; R_LINE="prereq5=heartbeat-open" ;;' '    open) R_STATUS=ok; R_LINE="prereq5=heartbeat-open" ;;' row_heartbeat_open
mutate closed-without-completed-ok 'closed) if [ "$reason" = completed ]; then' 'closed) if true; then' row_hb_duplicate
mutate lock-reads-not-stripped "stripped=\"\$(printf '%s\\n' \"\$code\" | sed -E 's/\\\$\\{PR_AFFECTED_LOCKED(:-[^}]*)?\\}//g; s/\\\$PR_AFFECTED_LOCKED//g')\"" 'stripped="$code"' row_lock_reads_ok
mutate lock-assignment-forms-stripped '(:-[^}]*)?' '(:[-=][^}]*)?' row_lock_spellings
mutate comment-strip-dropped "code=\"\$(printf '%s\\n' \"\$src\" | grep -v '^[[:space:]]*#')\" ||" 'code="$src" ||' row_lock_comment_only
mutate comment-token-accepted "body=\"\$(printf '%s\\n' \"\$1\" | grep -v '^[[:space:]]*#')\" || return 1" 'body="$1"' row_comment_token
mutate comment-call-accepted "body=\"\$(printf '%s\\n' \"\$1\" | grep -v '^[[:space:]]*#')\" || return 1" 'body="$1"' row_comment_call
mutate date-failure-reads-zero '    || { R_STATUS=unknown; R_LINE="verdict=unknown(date-unparseable)"; return; }' '    || { t_now=0; t_rec=0; }' row_date_bad
mutate clock-format-unchecked "printf '%s' \"\$today\" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}\$' || { R_STATUS=unknown; R_LINE=\"verdict=unknown(date-unparseable)\"; return; }" ':' row_today_natural
mutate receipt-from-worktree '  if text="$(committed "$rp")"; then :' '  if text="$(cat "$root/$rp" 2>/dev/null)"; then :' row_dirty_receipt
mutate blob-mode-unchecked '  case "$mode" in 100644|100755) : ;; *) return 1 ;; esac' '  :' row_symlink_text
mutate archive-for-present-path '  elif [ -z "$(git_ro -C "$root" ls-tree HEAD -- "$rp" 2>/dev/null)" ]; then' '  elif true; then' row_symlink_with_archive
mutate archive-fallback-dropped '        if [ "$n" -eq 1 ] && text="$(committed "$rel")"; then note="(receipt-archived)"; else text=""; fi' '        text=""' row_archived
mutate archive-feature-suffix-loose 'substr(rest, 17) == want' 'index(rest, want) > 0' row_archive_wrong_feature
mutate archive-ambiguity-ignored '        if [ "$n" -gt 1 ]; then R_STATUS=unknown; R_LINE="verdict=unknown(receipt-archive-ambiguous)"; return; fi' '        :' row_archive_ambiguous
mutate receipt-path-guard-dropped '  case "$rp" in /*|*..*) R_STATUS=unknown; R_LINE="verdict=unknown(receipt-path-rejected)"; return ;; esac' '  :' row_path_escape
mutate adr-first-line-wins 'adr_line() { printf '"'"'%s\n'"'"' "$ADR_TEXT" | sed -n "s/^$1:[[:space:]]*//p" | tail -1; }' 'adr_line() { printf '"'"'%s\n'"'"' "$ADR_TEXT" | sed -n "s/^$1:[[:space:]]*//p" | head -1; }' row_last_line_wins
mutate waiver-first-wins "w=\"\$(adr_line 'Waiver')\"" "w=\"\$(printf '%s\\n' \"\$ADR_TEXT\" | sed -n 's/^Waiver:[[:space:]]*//p' | head -1)\"" row_waiver_last
mutate waiver-placeholder-accepted "grep -Eq '^heartbeat[[:space:]]+[^[:space:]<]'" "grep -Eq '^heartbeat[[:space:]]+[^[:space:]]'" row_waiver_placeholder
mutate heartbeat-pull-request-accepted "  if printf '%s' \"\$G_BODY\" | jq -e 'has(\"pull_request\")' >/dev/null 2>&1; then R_STATUS=unmet; R_LINE=\"prereq5=heartbeat-is-a-pull-request\"; return; fi" ':' row_hb_pr
mutate lock-transform-unchecked "  [ -n \"\$(printf '%s' \"\$stripped\" | tr -d '[:space:]')\" ] || { R_STATUS=unknown; R_LINE=\"lock=unknown(transform-failed)\"; return; }" ':' row_lock_transform
mutate waiver-unanchored "grep -Eq '^heartbeat[[:space:]]+[^[:space:]<]'" "grep -q 'heartbeat'" row_waiver
mutate git-location-inherited '  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY \' '  env -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY \' row_git_dir
mutate tree-not-compared '  if [ "$h" = "$o" ]; then R_STATUS=ok; R_LINE="tree=head-is-main"' '  if true; then R_STATUS=ok; R_LINE="tree=head-is-main"' row_tree_differs
DRV_REL="scripts/ci-pr""-selection.sh"   # joined from two words so this suite does not name the real driver (the kb-consumer census would count it as a reader)
mutate working-tree-lock-read "  src=\"\$(committed $DRV_REL)\" ||" "  src=\"\$(cat \"\$root/$DRV_REL\" 2>/dev/null)\" ||" row_lock_head_only
mutate exit3-dropped '[ "$unmet" -eq 0 ] && exit 3' '[ "$unmet" -eq 0 ] && exit 1' row_exit3
mutate ok-requires-nothing 'if [ "$total" -gt 0 ] && [ "$ok" -eq "$total" ]; then' 'if [ "$total" -gt 0 ]; then' row_two_unmet
mutate list-empty-guard-dropped 'if [ "${#READERS[@]}" -eq 0 ]; then echo' 'if false; then echo' row_empty_list

echo "== harness controls: the harness reports a survivor, an unparseable mutant, a red row; the verdict helpers can fail"
row_always_red() { false; }
mutant_outcome ctl-survive '# SEAMS:' '# SEAMS (edited):' row_all_met
[[ "$MUT_RESULT" = survived ]] && pass "control: an edit outside the logic is reported as a SURVIVOR" || fail "control: survivor not reported ($MUT_RESULT)"
mutant_outcome ctl-invalid 'set -uo pipefail' 'set -uo pipefail )(' row_org_403
[[ "$MUT_RESULT" = invalid ]] && pass "control: a mutant that does not parse is INVALID, not killed" || fail "control: invalid mutant not reported ($MUT_RESULT)"
mutant_outcome ctl-nochange 'set -uo pipefail' 'set -uo pipefail' row_always_red
[[ "$MUT_RESULT" = edit-failed ]] && pass "control: an edit that changes nothing is reported, not counted" || fail "control: no-change edit not reported ($MUT_RESULT)"
mutant_outcome ctl-red2 '# SEAMS:' '# SEAMS (edited):' row_always_red
[[ "$MUT_RESULT" = row-red-on-pristine ]] && pass "control: a row that is red on the pristine SUT is reported, not counted as a kill" || fail "control: red row not reported ($MUT_RESULT)"
mutant_outcome ctl-nolanding 'THIS TEXT IS NOT IN THE SCRIPT' 'x' row_all_met
[[ "$MUT_RESULT" = edit-failed ]] && pass "control: an edit that does not land is reported" || fail "control: edit-failed not reported ($MUT_RESULT)"
ctl_verdict_helpers() {  # drive mutate() with a survivor and ck() with a false predicate: each must record a FAILURE, then unwind
  local p0=$passes f0=$fails n0=${#FAILED[@]} m0=$MUT_RUN k0=$MUT_KILLED f1
  mutate ctl-survive-through-mutate '# SEAMS:' '# SEAMS (edited):' row_all_met >/dev/null 2>&1
  ck "ctl" false >/dev/null 2>&1
  f1=$fails
  passes=$p0; fails=$f0; MUT_RUN=$m0; MUT_KILLED=$k0
  if (( n0 == 0 )); then FAILED=(); else FAILED=("${FAILED[@]:0:n0}"); fi
  [[ $((f1 - f0)) -eq 2 ]]
}
ctl_verdict_helpers && pass "control: mutate() records a survivor as a failure and ck() records a false predicate as a failure" || fail "control: the verdict helpers did not both record a failure"
if [[ "$MUT_KILLED" -eq "$MUT_RUN" ]]; then pass "every mutant was killed ($MUT_KILLED of $MUT_RUN)"; else fail "mutants killed $MUT_KILLED of $MUT_RUN"; fi

echo "== G4-6 the prerequisite list is empty"
row_empty_list && pass "G4-6 an emptied prerequisite list exits 2 and never reports ready (anti-vacuity)" || fail "G4-6 an emptied prerequisite list exits 2"
echo "== control: the unmutated world still passes after the battery"
row_all_met && pass "the unmutated SUT still reports ready=true (the control)" || fail "the unmutated SUT still reports ready=true (the control)"

FLOOR_ASSERTIONS=198
total=$((passes + fails))
if [[ "$total" -lt "$FLOOR_ASSERTIONS" ]]; then
  printf '[FATAL] anti-vacuity floor: only %s assertions ran, floor is %s\n' "$total" "$FLOOR_ASSERTIONS" >&2; exit 1
fi
FLOOR_MUTANTS=50
if [[ "$MUT_RUN" -lt "$FLOOR_MUTANTS" ]]; then
  printf '[FATAL] mutation floor: only %s mutants ran, floor is %s\n' "$MUT_RUN" "$FLOOR_MUTANTS" >&2; exit 1
fi
echo "ci-pr-affected-preactivation.test.sh: $passes passed, $fails failed, $total assertions, $MUT_RUN mutants"
[[ "$fails" -eq 0 ]] && exit 0
printf 'FAILED: %s\n' "${FAILED[@]}" >&2
exit 1
