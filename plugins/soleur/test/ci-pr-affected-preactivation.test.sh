#!/usr/bin/env bash
# shellcheck disable=SC2329,SC2015,SC2016,SC2034  # rows are dispatched indirectly; A && B || why is the assertion idiom; some programs are single-quoted on purpose
# Suite for scripts/ci-pr-affected-preactivation.sh (S4 PR C, #9729, ADR-276): Guard 4, the read-only gate that
# refuses activation until every prerequisite is POSITIVELY read as met.
#
# THE SEAM. `gh` is a PATH stub keyed on the request path; every response is the literal `gh api -i` output
# (a status line, a blank line, a body) so the SUT's status parsing is exercised for real. An unknown request
# exits 64 and logs STUB-MISS; the suite asserts the log holds none. The clock is PR_AFFECTED_PREACT_TODAY.
#
# THE WORLD. One synthesized root (the driver, the three artifacts, an ADR with its three recorded lines and a
# receipt) and one stubbed API in which every prerequisite is met. Each Guard 4 row (G4-1 .. G4-8) edits ONE
# thing in that world and requires `ready=false` with the right name in `missing=`. The must-PASS row is the
# unedited world. MUTATION ROWS copy the SUT, apply ONE edit (asserted to have landed), and require the named
# row to FAIL against the mutant. The floors report through printf + exit, never through pass()/fail().
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

build_world() {
  assert_fixture_dir "$WORLD"
  rm -rf "$WORLD" "$GHFIX"; mkdir -p "$GHFIX"
  mkdir -p "$WORLD/scripts" "$WORLD/plugins/soleur/scripts" "$WORLD/receipts" "$WORLD/adr"
  printf '#!/usr/bin/env bash\n# the driver, activation lock removed\nset -u\n' > "$WORLD/scripts/ci-pr-selection.sh"
  printf '# full-verified subcommand\n' > "$WORLD/plugins/soleur/scripts/ci-head-verdict.sh"
  printf '# calls full-verified\n' > "$WORLD/plugins/soleur/scripts/admin-merge-ready.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$WORLD/plugins/soleur/scripts/ci-full-battery-audit.sh"; chmod +x "$WORLD/plugins/soleur/scripts/ci-full-battery-audit.sh"
  printf 'notes\nSOLEUR_PR_AFFECTED_VERDICT verdict=GO ruled=confirmed date=2026-10-10\n' > "$WORLD/receipts/go-no-go.md"
  printf '# ADR\nGo/no-go receipt: receipts/go-no-go.md\nSkippable set: test-scripts shards\n' > "$WORLD/adr/ADR-276-x.md"
  resp "repos/$R/actions/variables/CI_PR_AFFECTED" 404 '{"message":"Not Found"}'
  resp "repos/$R/actions/variables" 200 '{"total_count":4,"variables":[]}'
  resp "repos/$R/actions/organization-variables" 200 '{"total_count":0,"variables":[]}'
  resp "repos/$R/actions/workflows/post-merge-monitor.yml/runs?branch=main&per_page=30" 200 '{"workflow_runs":[{"id":501}]}'
  resp "repos/$R/actions/runs/501/jobs?per_page=100" 200 '{"jobs":[{"name":"monitor","conclusion":"skipped"},{"name":"full-battery-audit","conclusion":"success"}]}'
  resp "repos/$R/issues/10415" 200 '{"state":"closed"}'
  resp "search/issues?q=repo:$R+is:pr+draft:false+created:%3E2026-10-15T17:50:38Z&sort=created&order=asc&per_page=30" 200 '{"items":[]}'
  : > "$GHLOG"
}

run_sut() {
  env PATH="$BIN:$PATH" PR_AFFECTED_PREACT_TODAY="$TODAY" bash "$SUT" --repo "$R" --root "$WORLD" --adr "$WORLD/adr/ADR-276-x.md"
}
OUT=""; RC=0
go() { OUT="$(run_sut 2>"$SANDBOX/stderr")"; RC=$?; }
final() { printf '%s\n' "$OUT" | tail -1; }
missing_of() { final | sed -n 's/.* missing=//p'; }

# ---------------------------------------------------------------------------------------------------------------------
echo "== must-PASS: every prerequisite met"
build_world; go
[[ "$RC" -eq 0 && "$(final)" = "SOLEUR_PR_AFFECTED_PREACTIVATION ready=true missing=none" ]] && pass "an all-met world reports ready=true and exits 0" || fail "all-met world: rc=$RC final='$(final)'"
printf '%s\n' "$OUT" | grep -qx 'variable=absent' && printf '%s\n' "$OUT" | grep -qx 'org_variables=0' && printf '%s\n' "$OUT" | grep -qx 'lock=absent' \
  && printf '%s\n' "$OUT" | grep -qx 'artifacts=ok' && printf '%s\n' "$OUT" | grep -qx 'verdict=GO-confirmed' && printf '%s\n' "$OUT" | grep -qx 'prereq5=ok' \
  && pass "each of the six prerequisites prints its own line" || fail "the six prerequisite lines: $OUT"
[[ "$(printf '%s\n' "$OUT" | wc -l)" -eq 8 ]] && pass "the output is exactly seven lines plus the final line (the closed line set)" || fail "closed line set (got $(printf '%s\n' "$OUT" | wc -l) lines)"
printf '%s\n' "$OUT" | grep -qx 'ac9c=not-yet' && pass "ac9c prints not-yet when no qualifying PR exists, and does not gate" || fail "ac9c not-yet"
! grep -q STUB-MISS "$GHLOG" && pass "the gate made no request the stub does not know" || fail "unknown request: $(grep STUB-MISS "$GHLOG" | head -2)"
[[ ! -s "$SANDBOX/stderr" ]] && pass "a ready run writes nothing to stderr" || fail "stderr on a ready run: $(head -2 "$SANDBOX/stderr")"

echo "== G4-1 organization variables: 403, then a count of 1"
build_world; resp "repos/$R/actions/organization-variables" 403 '{"message":"Resource not accessible"}'; go
[[ "$RC" -eq 1 && "$(missing_of)" = org_variables ]] && printf '%s\n' "$OUT" | grep -q 'org_variables=unknown' && pass "G4-1a a 403 is unknown, not met" || fail "G4-1a: rc=$RC '$(final)'"
build_world; resp "repos/$R/actions/organization-variables" 200 '{"total_count":1,"variables":[{"name":"CI_PR_AFFECTED"}]}'; go
[[ "$RC" -eq 1 && "$(missing_of)" = org_variables ]] && printf '%s\n' "$OUT" | grep -qx 'org_variables=1' && pass "G4-1b a count of 1 is unmet" || fail "G4-1b: rc=$RC '$(final)'"
build_world; resp "repos/$R/actions/organization-variables" 200 'not json'; go
[[ "$RC" -eq 1 && "$(missing_of)" = org_variables ]] && pass "G4-1c a 200 with an unparseable body is unknown" || fail "G4-1c: rc=$RC '$(final)'"

echo "== G4-2 and G4-8 prerequisite 5: no amendment, and the natural repair of an empty set"
build_world; printf '# ADR\nGo/no-go receipt: receipts/go-no-go.md\n' > "$WORLD/adr/ADR-276-x.md"; go
[[ "$RC" -eq 1 && "$(missing_of)" = prereq5 ]] && pass "G4-2 an ADR with no Skippable set line is not ready" || fail "G4-2: rc=$RC '$(final)'"
for v in none empty n/a - TBD '(none)'; do
  build_world; printf '# ADR\nGo/no-go receipt: receipts/go-no-go.md\nSkippable set: %s\n' "$v" > "$WORLD/adr/ADR-276-x.md"; go
  [[ "$RC" -eq 1 && "$(missing_of)" = prereq5 ]] && pass "G4-8 a Skippable set of '$v' is not ready" || fail "G4-8 '$v': rc=$RC '$(final)'"
done
build_world; resp "repos/$R/issues/10415" 200 '{"state":"open"}'; go
[[ "$RC" -eq 1 && "$(missing_of)" = prereq5 ]] && pass "an open heartbeat follow-up is not ready" || fail "open heartbeat: rc=$RC '$(final)'"
build_world; resp "repos/$R/issues/10415" 200 '{"state":"open"}'; printf 'Waiver: heartbeat accepted by the operator\n' >> "$WORLD/adr/ADR-276-x.md"; go
[[ "$RC" -eq 0 ]] && pass "an explicit waiver line stands in for the closed heartbeat issue" || fail "waiver: rc=$RC '$(final)'"

echo "== G4-3 the receipt: NO-GO, UNDECIDED, pending, absent, stale, malformed"
for line in "SOLEUR_PR_AFFECTED_VERDICT verdict=NO-GO ruled=confirmed date=2026-10-10" \
            "SOLEUR_PR_AFFECTED_VERDICT verdict=UNDECIDED ruled=pending date=2026-10-10" \
            "SOLEUR_PR_AFFECTED_VERDICT verdict=GO ruled=pending date=2026-10-10" \
            "SOLEUR_PR_AFFECTED_VERDICT verdict=GO ruled=confirmed date=2026-08-01" \
            "SOLEUR_PR_AFFECTED_VERDICT verdict=GO ruled=confirmed" \
            "verdict is GO"; do
  build_world; printf 'notes\n%s\n' "$line" > "$WORLD/receipts/go-no-go.md"; go
  [[ "$RC" -eq 1 && "$(missing_of)" = verdict ]] && pass "G4-3 '${line#SOLEUR_PR_AFFECTED_VERDICT }' is not ready" || fail "G4-3 '$line': rc=$RC '$(final)'"
done
build_world; rm -f "$WORLD/receipts/go-no-go.md"; go
[[ "$RC" -eq 1 && "$(missing_of)" = verdict ]] && printf '%s\n' "$OUT" | grep -qx 'verdict=receipt-absent' && pass "G4-3 an absent receipt file is not ready" || fail "G4-3 absent: rc=$RC '$(final)'"
build_world; printf '# ADR\nSkippable set: test-scripts shards\n' > "$WORLD/adr/ADR-276-x.md"; go
[[ "$RC" -eq 1 && "$(missing_of)" = verdict ]] && pass "G4-3 an ADR that records no receipt path is not ready" || fail "G4-3 no path: rc=$RC '$(final)'"
build_world; printf '# ADR\nGo/no-go receipt: ../escape.md\nSkippable set: test-scripts shards\n' > "$WORLD/adr/ADR-276-x.md"; go
[[ "$RC" -eq 1 && "$(missing_of)" = verdict ]] && pass "G4-3 a receipt path that climbs out of the root is refused" || fail "G4-3 escape path: rc=$RC '$(final)'"

echo "== G4-4 the lock and the audit run"
build_world; printf 'readonly PR_AFFECTED_LOCKED=1\n' >> "$WORLD/scripts/ci-pr-selection.sh"; go
[[ "$RC" -eq 1 && "$(missing_of)" = lock ]] && pass "G4-4a the activation lock still present is not ready" || fail "G4-4a: rc=$RC '$(final)'"
build_world; resp "repos/$R/actions/runs/501/jobs?per_page=100" 200 '{"jobs":[{"name":"full-battery-audit","conclusion":"failure"}]}'; go
[[ "$RC" -eq 1 && "$(missing_of)" = artifacts ]] && pass "G4-4b a failed newest audit run is not ready" || fail "G4-4b: rc=$RC '$(final)'"
build_world; resp "repos/$R/actions/runs/501/jobs?per_page=100" 200 '{"jobs":[{"name":"monitor","conclusion":"success"}]}'; go
[[ "$RC" -eq 1 && "$(missing_of)" = artifacts ]] && printf '%s\n' "$OUT" | grep -qx 'artifacts=no-audit-run' && pass "G4-4c no audit job anywhere in the listed runs is not ready" || fail "G4-4c: rc=$RC '$(final)'"
build_world; rm -f "$WORLD/plugins/soleur/scripts/ci-full-battery-audit.sh"; go
[[ "$RC" -eq 1 && "$(missing_of)" = artifacts ]] && pass "G4-4d a missing audit script is not ready" || fail "G4-4d: rc=$RC '$(final)'"
build_world; printf '# no call here\n' > "$WORLD/plugins/soleur/scripts/admin-merge-ready.sh"; go
[[ "$RC" -eq 1 && "$(missing_of)" = artifacts ]] && pass "G4-4e a merge authority that does not call the read is not ready" || fail "G4-4e: rc=$RC '$(final)'"

echo "== G4-5 two prerequisites unmet after a met one"
build_world; printf 'readonly PR_AFFECTED_LOCKED=1\n' >> "$WORLD/scripts/ci-pr-selection.sh"; printf '# ADR\nGo/no-go receipt: receipts/go-no-go.md\n' > "$WORLD/adr/ADR-276-x.md"; go
[[ "$RC" -eq 1 && "$(missing_of)" = lock,prereq5 ]] && pass "G4-5 both unmet prerequisites are listed, in order, after the met ones" || fail "G4-5: rc=$RC '$(final)'"

echo "== G4-7 the variable read"
build_world; resp "repos/$R/actions/variables/CI_PR_AFFECTED" 500 '{"message":"boom"}'; go
[[ "$RC" -eq 1 && "$(missing_of)" = variable ]] && printf '%s\n' "$OUT" | grep -q 'variable=unknown' && pass "G4-7 a non-404 error on the variable read is unknown" || fail "G4-7: rc=$RC '$(final)'"
build_world; resp "repos/$R/actions/variables/CI_PR_AFFECTED" 200 '{"name":"CI_PR_AFFECTED","value":"on"}'; go
[[ "$RC" -eq 1 && "$(missing_of)" = variable ]] && printf '%s\n' "$OUT" | grep -qx 'variable=present' && pass "a variable that already exists is unmet (activation already happened or was armed)" || fail "present variable: rc=$RC '$(final)'"
build_world; resp "repos/$R/actions/variables" 502 '{}'; go
[[ "$RC" -eq 1 && "$(missing_of)" = variable ]] && pass "a 404 beside a failing list read cannot establish absence" || fail "404 + failing list: rc=$RC '$(final)'"
build_world; silent_fail "repos/$R/actions/variables/CI_PR_AFFECTED"; go
[[ "$RC" -eq 1 && "$(missing_of)" = variable ]] && pass "a request that returns nothing at all is unknown" || fail "silent failure: rc=$RC '$(final)'"

echo "== ac9c is information only"
build_world
resp "search/issues?q=repo:$R+is:pr+draft:false+created:%3E2026-10-15T17:50:38Z&sort=created&order=asc&per_page=30" 200 '{"items":[{"number":77}]}'
resp "repos/$R/pulls/77/files?per_page=100" 200 "[{\"filename\":\"${KBDIR}/project/x.md\"},{\"filename\":\"README.md\"}]"
resp "repos/$R/pulls/77" 200 '{"head":{"sha":"abc123"}}'
resp "repos/$R/actions/workflows/ci.yml/runs?head_sha=abc123&per_page=100" 200 '{"workflow_runs":[{"id":900,"event":"pull_request"}]}'
resp "repos/$R/actions/runs/900/jobs?per_page=100" 200 '{"jobs":[{"name":"pr-selection","conclusion":"skipped"},{"name":"test-webplat (1/2)","conclusion":"success"},{"name":"test-webplat (2/2)","conclusion":"success"},{"name":"test-bun","conclusion":"success"},{"name":"test-scripts-heavy (1/3)","conclusion":"success"},{"name":"test-scripts (1/8)","conclusion":"success"},{"name":"test","conclusion":"success"}]}'
go
printf '%s\n' "$OUT" | grep -qx 'ac9c=observed' && [[ "$RC" -eq 0 ]] && pass "a doc-only PR with pr-selection skipped and every leg green is observed (matrix names included)" || fail "ac9c observed: rc=$RC $(printf '%s\n' "$OUT" | grep ac9c)"
resp "repos/$R/actions/runs/900/jobs?per_page=100" 200 '{"jobs":[{"name":"pr-selection","conclusion":"skipped"},{"name":"test-webplat (1/2)","conclusion":"failure"},{"name":"test-bun","conclusion":"success"},{"name":"test-scripts-heavy (1/3)","conclusion":"success"},{"name":"test-scripts (1/8)","conclusion":"success"},{"name":"test","conclusion":"success"}]}'
go
printf '%s\n' "$OUT" | grep -qx 'ac9c=not-yet' && pass "a skipped pr-selection beside a red leg is not an observation" || fail "ac9c red leg: $(printf '%s\n' "$OUT" | grep ac9c)"
resp "search/issues?q=repo:$R+is:pr+draft:false+created:%3E2026-10-15T17:50:38Z&sort=created&order=asc&per_page=30" 500 '{}'
go
printf '%s\n' "$OUT" | grep -qx 'ac9c=unknown' && [[ "$RC" -eq 0 ]] && pass "a failing ac9c read prints unknown and never blocks readiness" || fail "ac9c unknown: rc=$RC $(printf '%s\n' "$OUT" | grep ac9c)"

echo "== usage and refusals"
build_world
env PATH="$BIN:$PATH" bash "$SUT" --repo noslash --root "$WORLD" >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 2 ]] && pass "a malformed --repo is refused with rc 2" || fail "malformed --repo (rc=$rc)"
env PATH="$BIN:$PATH" bash "$SUT" --repo "$R" --root relative/path >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 2 ]] && pass "a relative --root is refused with rc 2" || fail "relative --root (rc=$rc)"
env PATH="$BIN:$PATH" bash "$SUT" --nope >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 2 ]] && pass "an unknown argument is refused with rc 2" || fail "unknown argument (rc=$rc)"
build_world; go
grep -rn 'gh api' "$SUT" | grep -vq -- 'gh api -i' && fail "every request goes through the one reader" || pass "every request goes through the one reader (gh api -i)"
grep -nE 'gh api[^|]*(-X|--method|--input|-f |-F )' "$SUT" >/dev/null && fail "the gate script issues only reads" || pass "the gate script issues only reads (no -X, --method, --input, -f, -F)"
grep -nE 'variables.*(-X|--method|PATCH|POST|PUT|DELETE)' "$SUT" >/dev/null && fail "the gate never mutates the variable" || pass "the gate never mutates the variable"

# ---------------------------------------------------------------------------------------------------------------------
echo "== mutation rows (each edit must land and the named row must fail)"
MUT_RUN=0; MUT_KILLED=0
mutate() {  # mutate <name> <old> <new> <row-function>
  local name="$1" old="$2" new="$3" row="$4" m="$SANDBOX/mut-$1.sh" got
  cp "$REAL_SUT" "$m" || { fail "mutant $name: copy"; return; }
  python3 - "$m" "$old" "$new" <<'PY' || { fail "mutant $name: the edit did not land exactly once"; return; }
import sys
p, old, new = sys.argv[1:4]
s = open(p).read()
assert s.count(old) == 1, "count=%d" % s.count(old)
open(p, "w").write(s.replace(old, new))
PY
  cmp -s "$m" "$REAL_SUT" && { fail "mutant $name: the mutation did not change the file"; return; }
  MUT_RUN=$((MUT_RUN + 1))
  SUT="$m"; "$row" >/dev/null 2>&1; got=$?; SUT="$REAL_SUT"
  if [[ "$got" -ne 0 ]]; then MUT_KILLED=$((MUT_KILLED + 1)); pass "mutant $name is killed by $row"; else fail "mutant $name SURVIVED $row"; fi
}
row_org_403() { build_world; resp "repos/$R/actions/organization-variables" 403 '{}'; go; [[ "$RC" -eq 1 && "$(missing_of)" = org_variables ]]; }
row_prereq5_empty() { build_world; printf '# ADR\nGo/no-go receipt: receipts/go-no-go.md\nSkippable set: none\n' > "$WORLD/adr/ADR-276-x.md"; go; [[ "$RC" -eq 1 && "$(missing_of)" = prereq5 ]]; }
row_prereq5_absent() { build_world; printf '# ADR\nGo/no-go receipt: receipts/go-no-go.md\n' > "$WORLD/adr/ADR-276-x.md"; go; [[ "$RC" -eq 1 && "$(missing_of)" = prereq5 ]]; }
row_ruled_pending() { build_world; printf 'x\nSOLEUR_PR_AFFECTED_VERDICT verdict=GO ruled=pending date=2026-10-10\n' > "$WORLD/receipts/go-no-go.md"; go; [[ "$RC" -eq 1 && "$(missing_of)" = verdict ]]; }
row_stale() { build_world; printf 'x\nSOLEUR_PR_AFFECTED_VERDICT verdict=GO ruled=confirmed date=2026-08-01\n' > "$WORLD/receipts/go-no-go.md"; go; [[ "$RC" -eq 1 && "$(missing_of)" = verdict ]]; }
row_two_unmet() { build_world; printf 'readonly PR_AFFECTED_LOCKED=1\n' >> "$WORLD/scripts/ci-pr-selection.sh"; printf '# ADR\nGo/no-go receipt: receipts/go-no-go.md\n' > "$WORLD/adr/ADR-276-x.md"; go; [[ "$(missing_of)" = lock,prereq5 ]]; }
row_var_500() { build_world; resp "repos/$R/actions/variables/CI_PR_AFFECTED" 500 '{}'; go; [[ "$RC" -eq 1 && "$(missing_of)" = variable ]]; }
row_audit_failed() { build_world; resp "repos/$R/actions/runs/501/jobs?per_page=100" 200 '{"jobs":[{"name":"full-battery-audit","conclusion":"failure"}]}'; go; [[ "$RC" -eq 1 && "$(missing_of)" = artifacts ]]; }
row_heartbeat_open() { build_world; resp "repos/$R/issues/10415" 200 '{"state":"open"}'; go; [[ "$RC" -eq 1 && "$(missing_of)" = prereq5 ]]; }
row_lock_present() { build_world; printf 'readonly PR_AFFECTED_LOCKED=1\n' >> "$WORLD/scripts/ci-pr-selection.sh"; go; [[ "$RC" -eq 1 && "$(missing_of)" = lock ]]; }
row_org_count1() { build_world; resp "repos/$R/actions/organization-variables" 200 '{"total_count":1}'; go; [[ "$RC" -eq 1 && "$(missing_of)" = org_variables ]]; }
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
  local out rc=0; out="$(env PATH="$BIN:$PATH" PR_AFFECTED_PREACT_TODAY="$TODAY" bash "$e" --repo "$R" --root "$WORLD" --adr "$WORLD/adr/ADR-276-x.md" 2>/dev/null)" || rc=$?
  [[ "$rc" -eq 2 ]] && ! printf '%s' "$out" | grep -q 'ready=true'
}
row_all_met() { build_world; go; [[ "$RC" -eq 0 && "$(final)" = "SOLEUR_PR_AFFECTED_PREACTIVATION ready=true missing=none" ]]; }
mutate unknown-counts-as-met 'if [ "$R_STATUS" = ok ]; then ok=$((ok + 1))' 'if [ "$R_STATUS" != unmet ]; then ok=$((ok + 1))' row_org_403
mutate org-count-ignored '    *) R_STATUS=unmet; R_LINE="org_variables=$n" ;;' '    *) R_STATUS=ok; R_LINE="org_variables=$n" ;;' row_org_count1
mutate none-is-a-set "''|none|n/a|-|tbd|empty|'(none)') R_STATUS=unmet" "''|n/a|-|tbd|empty|'(none)') R_STATUS=unmet" row_prereq5_empty
mutate prereq5-reader-dropped 'READERS=(variable org_variables lock artifacts verdict prereq5)' 'READERS=(variable org_variables lock artifacts verdict)' row_prereq5_absent
mutate ruled-ignored 'if [ "$v" != GO ] || [ "$r" != confirmed ]; then' 'if [ "$v" != GO ]; then' row_ruled_pending
mutate staleness-ignored 'if [ "$age" -lt 0 ] || [ "$age" -gt 60 ]; then' 'if [ "$age" -lt 0 ]; then' row_stale
mutate first-failure-only 'missing="${missing:+$missing,}$name"' 'missing="${missing:-$name}"' row_two_unmet
mutate variable-read-loose '  if [ "$s1" = 404 ] && [ "$s2" = 200 ]; then R_STATUS=ok; R_LINE="variable=absent"' '  if [ "$s1" != 200 ]; then R_STATUS=ok; R_LINE="variable=absent"' row_var_500
mutate audit-failure-ok '    *) R_STATUS=unmet; R_LINE="artifacts=audit-run-$found" ;;' '    *) R_STATUS=ok; R_LINE="artifacts=audit-run-$found" ;;' row_audit_failed
mutate open-heartbeat-ok '    open) R_STATUS=unmet; R_LINE="prereq5=heartbeat-open" ;;' '    open) R_STATUS=ok; R_LINE="prereq5=heartbeat-open" ;;' row_heartbeat_open
mutate lock-grep-anchor-lost "grep -c '^readonly PR_AFFECTED_LOCKED='" "grep -c '^readonly PR_AFFECTED_LOCKED_NOPE='" row_lock_present
mutate ok-requires-nothing 'if [ "$total" -gt 0 ] && [ "$ok" -eq "$total" ]; then' 'if [ "$total" -gt 0 ]; then' row_two_unmet
mutate list-empty-guard-dropped 'if [ "${#READERS[@]}" -eq 0 ]; then echo' 'if false; then echo' row_empty_list

echo "== G4-6 the prerequisite list is empty"
row_empty_list && pass "G4-6 an emptied prerequisite list exits 2 and never reports ready (anti-vacuity)" || fail "G4-6 an emptied prerequisite list exits 2"
echo "== control: the unmutated world still passes after the battery"
row_all_met && pass "the unmutated SUT still reports ready=true (the control)" || fail "the unmutated SUT still reports ready=true (the control)"
if [[ "$MUT_KILLED" -eq "$MUT_RUN" ]]; then pass "every mutant was killed ($MUT_KILLED of $MUT_RUN)"; else fail "mutants killed $MUT_KILLED of $MUT_RUN"; fi

FLOOR_ASSERTIONS=62
total=$((passes + fails))
if [[ "$total" -lt "$FLOOR_ASSERTIONS" ]]; then
  printf '[FATAL] anti-vacuity floor: only %s assertions ran, floor is %s\n' "$total" "$FLOOR_ASSERTIONS" >&2; exit 1
fi
FLOOR_MUTANTS=13
if [[ "$MUT_RUN" -lt "$FLOOR_MUTANTS" ]]; then
  printf '[FATAL] mutation floor: only %s mutants ran, floor is %s\n' "$MUT_RUN" "$FLOOR_MUTANTS" >&2; exit 1
fi
echo "ci-pr-affected-preactivation.test.sh: $passes passed, $fails failed, $total assertions, $MUT_RUN mutants"
[[ "$fails" -eq 0 ]] && exit 0
printf 'FAILED: %s\n' "${FAILED[@]}" >&2
exit 1
