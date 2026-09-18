#!/usr/bin/env bash
# Mutation proof for #6721 — merge-commit-exclusive content must be scannable.
#
# `gitleaks git` drives `git log -p`. Without `-m`, a merge commit contributes
# ZERO patch content, so a secret introduced only by a hand-resolved merge
# conflict — present in the merge's tree but in NEITHER parent — is invisible to
# every scan job. `main` carries merge commits and `allow_merge_commit: true`,
# so this is reachable, not theoretical.
#
# Two non-obvious properties are pinned here:
#
#   1. `--cc` is a SILENT NO-OP. It emits ~195 patch bytes that visibly contain
#      the secret, and gitleaks detects nothing (its diff parser does not consume
#      combined-diff `@@@` format). Byte volume is NOT detection. Shipping `--cc`
#      as an "equivalent" to `-m` would create a fresh structurally-unfailable
#      gate — the exact defect class this file exists to prevent. Both halves are
#      asserted (bytes > 0 AND rc == 0) so the trap cannot be re-read as
#      "--cc simply sees nothing".
#
#   2. The GATE assertion reads `--log-opts` OUT OF .github/workflows/secret-scan.yml
#      rather than hand-mirroring it. A prior draft of this test hardcoded the
#      log-opts strings, so deleting `-m` from the workflow left the suite fully
#      green — a mutation proof that could not fail. The hardcoded rows below are
#      kept as PARSER CHARACTERIZATION only; the gate is the extracted value.
#
# When gitleaks is not RUNNABLE (absent, or an unpinned version-manager shim
# that resolves on PATH but exits non-zero — #8266), every arm that needs it
# prints a SKIP line and the arms that do not (T0, T2's byte half, T6, P2, the
# workflow `-m` check) still run. A skip is never silent and never a pass:
# under CI=true the suite exits 1 at the end naming every skipped arm, because
# ci.yml's `test-scripts` shard installs the pinned 8.24.2 binary to
# /usr/local/bin, so a skip there means a broken environment. Locally it exits
# 0 after listing them. (This replaced a hard `ABORT … exit 2`, which on a host
# with an unrunnable shim was indistinguishable from a real regression.)
#
# DETECTION oracles (T3, T4, P1, the `-m` coupling arm) read the JSON report's
# RuleIDs, never `rc == 1`: gitleaks exits 1 on a finding AND on a scan that
# failed to run, so an exit-code oracle certifies "detected" about a scan that
# never happened.
#
# The fixture repo is built on a branch named `trunk`, NOT `main`: the repo's
# own commit-on-main guardrail blocks fixture commits when the ambient CWD sits
# on main, which would make this suite pass or fail based on where it was invoked.
#
# Synthesized token only (cq-test-fixtures-synthesized-only), assembled at
# runtime — this path is not in the doppler-api-token allowlist, so a contiguous
# literal here would trip the repo's own scan.
#
# Run via:  bash plugins/soleur/test/gitleaks-merge-commit.test.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Guard 3 (#7833) tripwire adoption (#7849 exit condition). test-helpers.sh runs
# `set -euo pipefail`, so the `+e` below is REQUIRED to preserve this suite's
# deliberate no-errexit contract -- delete the source line and the `+e` becomes wrong.
# shellcheck source=plugins/soleur/test/test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh" || { echo "FATAL: could not source $SCRIPT_DIR/test-helpers.sh" >&2; exit 2; }

set +e -uo pipefail

REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CONFIG="$REPO_ROOT/.gitleaks.toml"
WORKFLOW="$REPO_ROOT/.github/workflows/secret-scan.yml"

# Runnability probe — runs the binary; `command -v` alone certifies a shim that
# cannot scan. `timeout` is optional (stock macOS lacks it and gtimeout).
SUITE="gitleaks-merge-commit"
HAVE_GITLEAKS=1
GITLEAKS_REASON=""
_probe_err=$(mktemp)
TO=(); if command -v timeout >/dev/null 2>&1; then TO=(timeout 10); elif command -v gtimeout >/dev/null 2>&1; then TO=(gtimeout 10); fi
_probe_rc=0
${TO[@]+"${TO[@]}"} gitleaks version >/dev/null 2>"$_probe_err" || _probe_rc=$?
if [[ "$_probe_rc" != "0" ]]; then
  HAVE_GITLEAKS=0
  GITLEAKS_REASON="gitleaks is not runnable here (rc=$(printf '%q' "$_probe_rc"), $(printf '%q' "$(head -n1 "$_probe_err")"))"
fi
rm -f "$_probe_err"

# Per-ARM skip. See the header: CI=true turns any skip into exit 1 at the end.
SKIPPED_ARMS=()
_skip_arm() {
  echo "SKIP — $1 — $2. CI pins gitleaks 8.24.2 — install that version or pin it in your version manager."
  SKIPPED_ARMS+=("$1")
}

PASS=0
FAIL=0
fail() {
  echo "  FAIL: $1"
  FAIL=$((FAIL + 1))
}
pass() {
  echo "  pass: $1"
  PASS=$((PASS + 1))
}

TMP=$(mktemp -d -t gitleaks-merge-commit.XXXXXXXX)
trap 'rm -rf "$TMP"' EXIT

# Synthesized Doppler-shape token, assembled at runtime. The doppler-api-token
# rule is used deliberately instead of database-url-with-password: it keeps this
# #6721 proof INDEPENDENT of the #6723 rule/allowlist changes shipping alongside
# it, so a regression in one cannot mask the other.
SEC="dp.pt."
SEC="${SEC}$(printf 'aB3x%.0s' {1..11})Zq9"

FIXTURE="$TMP/repo"
BASE_SHA=""

build_fixture() {
  mkdir -p "$FIXTURE"
  (
    cd "$FIXTURE" || exit 1
    git init -q -b trunk
    git config user.email "merge-fixture@example.com"
    git config user.name "merge fixture"
    echo base > conf.txt
    git add -A
    git commit -qm "base"
    git rev-parse HEAD > .base-sha
    git checkout -q -b feature
    echo feature-side > conf.txt
    git commit -qam "feature side"
    git checkout -q trunk
    echo trunk-side > conf.txt
    git commit -qam "trunk side"
    # Genuine 2-parent merge with a hand-resolved conflict. The resolution
    # introduces content present in NEITHER parent — the #6721 shape.
    git merge feature -q >/dev/null 2>&1 || true
    printf 'url = "%s"\n' "$SEC" > conf.txt
    git add conf.txt
    git commit -q --no-edit
  )
  BASE_SHA=$(cat "$FIXTURE/.base-sha" 2>/dev/null)
}

# scan_git <log-opts> -> echoes gitleaks exit code
scan_git() {
  (
    cd "$FIXTURE" || exit 1
    gitleaks git --config "$CONFIG" --no-banner --exit-code 1 --log-opts="$1" >/dev/null 2>&1
    echo $?
  )
}

# scan_git_count <log-opts> -> number of findings reported (NOT the exit code)
#
# Use this for any assertion of the form "the shipped config DETECTS X".
# `gitleaks git` exits 1 on a git-invocation failure as well as on a finding, so
# an exit-code oracle cannot distinguish "found the secret" from "the walk never
# ran". Reading the report separates them: a failed walk yields zero findings.
scan_git_count() {
  (
    cd "$FIXTURE" || exit 1
    rpt=$(mktemp -t glreport.XXXXXXXX.json)
    gitleaks git --config "$CONFIG" --no-banner --exit-code 1 --log-opts="$1" \
      --report-format json --report-path "$rpt" >/dev/null 2>&1
    n=$(jq 'length' "$rpt" 2>/dev/null || echo 0)
    rm -f "$rpt"
    echo "${n:-0}"
  )
}

# The rule the synthesized token is shaped for. Detection oracles assert THIS
# RuleID is in the parsed report — not just "some finding", and never rc == 1.
RULE="doppler-api-token"

# report_rules <report.json> -> newline-separated, de-duplicated RuleIDs.
# A missing, empty or unparseable report yields nothing, so an oracle built on
# this reads a scan that never ran as "not detected" — the fail-loud direction.
report_rules() {
  jq -r '.[].RuleID' "$1" 2>/dev/null | sort -u
}

# ...but that is only honest about gitleaks if jq can actually parse. Without this
# probe a missing or broken jq returns empty and T3/T4/T7 report "gitleaks dir
# missed on-tree content" — a verdict about the SUBJECT sourced from a broken
# INSTRUMENT, which is verbatim the #8266 class this suite exists to close, one
# layer down. jq is not optional here; it IS the oracle, so it fails loud.
if ! printf '%s' '[{"RuleID":"probe"}]' | jq -e -r '.[].RuleID' >/dev/null 2>&1; then
  echo "FATAL: gitleaks-merge-commit.test: jq cannot parse a findings report, so every RuleID oracle below would read as 'gitleaks found nothing'. This is a broken instrument, not a gitleaks verdict — install jq." >&2
  exit 2
fi

# scan_git_rules <repo-dir> <log-opts> -> RuleIDs `gitleaks git` reported.
scan_git_rules() {
  (
    cd "$1" || exit 1
    rpt=$(mktemp -t glreport.XXXXXXXX.json)
    gitleaks git --config "$CONFIG" --no-banner --exit-code 1 --log-opts="$2" \
      --report-format json --report-path "$rpt" >/dev/null 2>&1
    report_rules "$rpt"
    rm -f "$rpt"
  )
}

# scan_dir_rules <dir> -> RuleIDs `gitleaks dir .` reported for that tree.
scan_dir_rules() {
  (
    cd "$1" || exit 1
    rpt=$(mktemp -t glreport.XXXXXXXX.json)
    gitleaks dir . --config "$CONFIG" --no-banner --exit-code 1 \
      --report-format json --report-path "$rpt" >/dev/null 2>&1
    report_rules "$rpt"
    rm -f "$rpt"
  )
}

# patch_bytes <log-opts-for-git-log> -> bytes of patch body
# Anchored on 'diff --' so it catches BOTH `diff --git` (normal) and
# `diff --cc` (combined). Anchoring on 'diff --git' alone silently reports 0
# for --cc and fabricates the wrong conclusion.
patch_bytes() {
  (
    cd "$FIXTURE" || exit 1
    # shellcheck disable=SC2086
    git log -p $1 -1 HEAD | sed -n '/^diff --/,$p' | wc -c | tr -d ' '
  )
}

echo "=== #6721 merge-commit coverage mutation proof ==="
echo ""

build_fixture

echo "T0: fixture is a genuine 2-parent merge carrying content absent from both parents"
parents=$( (cd "$FIXTURE" && git rev-list --parents -1 HEAD | wc -w) )
in_merge=$( (cd "$FIXTURE" && git show HEAD:conf.txt) | grep -c 'dp\.pt\.' )
in_p1=$( (cd "$FIXTURE" && git show HEAD^1:conf.txt) | grep -c 'dp\.pt\.' )
in_p2=$( (cd "$FIXTURE" && git show HEAD^2:conf.txt) | grep -c 'dp\.pt\.' )
if [[ "$parents" == "3" && "$in_merge" == "1" && "$in_p1" == "0" && "$in_p2" == "0" ]]; then
  pass "2-parent merge; secret in merge tree only (parents clean)"
else
  fail "fixture did not reach the intended state (parents=$parents merge=$in_merge p1=$in_p1 p2=$in_p2)"
fi

echo "T1: parser characterization — which walks see merge-exclusive content"
# Hardcoded rows: characterization of gitleaks' walk behaviour, NOT the gate.
# The gate is T3, which reads the shipped workflow.
if [[ "$HAVE_GITLEAKS" != "1" ]]; then
  _skip_arm "$SUITE: T1" "$GITLEAKS_REASON"
else
for row in \
  "--no-merges HEAD|0|today's PR/merge_group/push:main shape — MISSES" \
  "HEAD|0|bare HEAD — MISSES" \
  "-m HEAD|1|-m — DETECTS" \
  "-m --first-parent HEAD|1|-m --first-parent — DETECTS" \
  ; do
  opts="${row%%|*}"
  rest="${row#*|}"
  want="${rest%%|*}"
  label="${rest#*|}"
  got=$(scan_git "$opts")
  if [[ "$got" == "$want" ]]; then
    pass "$label (rc=$got)"
  else
    fail "$label — expected rc=$want, got rc=$got"
  fi
done
fi  # T1 HAVE_GITLEAKS

echo "T2: --cc is a SILENT NO-OP (emits patch bytes, detects nothing)"
# Both halves matter. Asserting only rc=0 would leave the trap re-readable as
# "--cc simply produces no output"; asserting only bytes>0 would not show the
# miss. Together they pin: gitleaks ignores combined-diff format.
# The byte half needs only git, so it runs without gitleaks; the rc half skips.
cc_bytes=$(patch_bytes "--cc")
m_bytes=$(patch_bytes "-m")
plain_bytes=$(patch_bytes "")
if [[ "$cc_bytes" -gt 0 ]]; then
  pass "--cc emits patch content ($cc_bytes bytes)"
else
  fail "--cc emitted no patch bytes — fixture/extraction broken, trap unproven"
fi
if [[ "$HAVE_GITLEAKS" != "1" ]]; then
  _skip_arm "$SUITE: T2 (--cc detects nothing)" "$GITLEAKS_REASON"
else
  cc_rc=$(scan_git "--cc HEAD")
  if [[ "$cc_rc" == "0" ]]; then
    pass "--cc detects NOTHING despite emitting content (rc=0) — never substitute for -m"
  else
    fail "--cc unexpectedly detected (rc=$cc_rc) — gitleaks parser behaviour changed; re-evaluate #6721"
  fi
fi
if [[ "$plain_bytes" == "0" && "$m_bytes" -gt 0 ]]; then
  pass "plain walk emits 0 patch bytes; -m emits $m_bytes"
else
  fail "expected plain=0 and -m>0; got plain=$plain_bytes -m=$m_bytes"
fi

echo "T3: GATE — the log-opts SHIPPED in secret-scan.yml's weekly cron detects it"
# Reads the artifact. This is what goes RED if someone drops -m from the cron.
CRON_OPTS=$(awk '/name: Scan \(full history, weekly cron\)/{f=1} f && /log-opts=/{print; exit}' \
  "$WORKFLOW" | sed -E 's/.*--log-opts="([^"]*)".*/\1/')
if [[ -z "$CRON_OPTS" ]]; then
  fail "could not extract cron --log-opts from secret-scan.yml (YAML restructured?)"
elif [[ "$HAVE_GITLEAKS" != "1" ]]; then
  _skip_arm "$SUITE: T3" "$GITLEAKS_REASON"
else
  # The cron ships `-m --all`; --all is meaningless in the fixture repo (no other
  # refs) but harmless. Substitute the fixture's own ref so the walk is scoped.
  fixture_opts="${CRON_OPTS/--all/HEAD}"
  # Counts FINDINGS, not the exit code. gitleaks exits 1 both when it detects a
  # secret AND when the underlying `git log` invocation fails, so an exit-code
  # oracle passes when the walk never ran at all. Mutation-verified: rewriting
  # the cron to build its opts in a shell variable (`OPTS="--cc --all"` /
  # `--log-opts="$OPTS"`) makes git fail on the unexpanded literal, rc=1, and
  # the old form reported "DETECTS" while the shipped config — now the `--cc`
  # no-op T2 proves detects nothing — found zero. That is this file's own
  # defect class: a gate certifying the wrong property.
  got=$(scan_git_count "$fixture_opts")
  if [[ "$got" -ge 1 ]]; then
    pass "shipped cron log-opts ('$CRON_OPTS') DETECTS merge-exclusive secret ($got finding(s))"
  else
    fail "shipped cron log-opts ('$CRON_OPTS') found ZERO findings — either #6721 is not fixed, or the walk errored (an exit code alone cannot tell these apart)"
  fi
fi

echo "T4: GATE — full-tree scan detects content still on the tree"
# RuleID oracle, as T3: `gitleaks dir` exits 1 when the scan fails to run too,
# so `rc == 1` passed this gate about a scan that read nothing (#8266).
if [[ "$HAVE_GITLEAKS" != "1" ]]; then
  _skip_arm "$SUITE: T4" "$GITLEAKS_REASON"
else
  tree_rules=$(scan_dir_rules "$FIXTURE")
  if grep -qx "$RULE" <<<"$tree_rules"; then
    pass "gitleaks dir detects merge-introduced content on the tree ($RULE in report)"
  else
    fail "gitleaks dir missed on-tree content — $RULE not in the report (got: ${tree_rules:-<none>}); a scan that never ran reads the same"
  fi
fi

echo "T5: GATE — the PR-time window (BASE..HEAD spanning a conflict resolution)"
# The issue frames #6721 around main; the PR job is uncovered too and is the
# MORE common shape (developer merges main into a feature branch, resolves a
# conflict, introduces a secret in the resolution).
if [[ -z "$BASE_SHA" ]]; then
  fail "could not resolve fixture BASE_SHA"
elif [[ "$HAVE_GITLEAKS" != "1" ]]; then
  _skip_arm "$SUITE: T5" "$GITLEAKS_REASON"
else
  pr_rc=$(scan_git "--no-merges ${BASE_SHA}..HEAD")
  if [[ "$pr_rc" == "0" ]]; then
    pass "today's PR-range shape MISSES the resolution secret (the gap, rc=0)"
  else
    fail "expected PR-range shape to miss (rc=0), got rc=$pr_rc"
  fi
  # The shipped remedy for the PR job is a full-tree scan (T4 proves it fires).
fi

echo "T6: workflow text — the shipped configuration is what the gates above assume"
wf=$(cat "$WORKFLOW")
# AC4: -m must carry --all. Bare `-m` silently narrows breadth to HEAD, which
# would regress #6706's deliberate all-refs cron design.
all_form=$(grep -cF 'log-opts="-m --all"' "$WORKFLOW")
bare_form=$(grep -cF 'log-opts="-m"' "$WORKFLOW")
if [[ "$all_form" -ge 1 ]]; then
  pass "cron carries log-opts=\"-m --all\" ($all_form occurrence(s))"
else
  fail "expected log-opts=\"-m --all\" in secret-scan.yml; found none"
fi
if [[ "$bare_form" == "0" ]]; then
  pass "no bare log-opts=\"-m\" form (would narrow breadth to HEAD)"
else
  fail "found bare log-opts=\"-m\" ($bare_form) — --all is load-bearing"
fi
# AC5 + AC6a: full-tree coverage, asserted PER EVENT.
#
# This was `dir_steps -ge 2`, which is a count masquerading as a coverage claim.
# The workflow ships four full-tree steps, so deleting the PR-side one — the
# actual shipped remedy for the #6721 shape T5 proves is otherwise uncovered —
# left the count at 3, still `-ge 2`, and this suite fully GREEN. A `>=`
# threshold cannot fail for any deletion that keeps the floor, which is the
# vacuity class this whole file exists to prevent, inside the file itself.
#
# Now: every event that runs the scan job must have its own full-tree step, and
# each such step must reach an actual invocation. Anchored on the step-name and
# invocation shapes, so a comment cannot satisfy either half.
for ev in "PR" "merge_group candidate" "push:main" "weekly cron"; do
  if grep -qF -- "- name: Scan (full tree, ${ev})" "$WORKFLOW"; then
    pass "full-tree step present for '${ev}'"
  else
    fail "no full-tree step for '${ev}' — that event has no tree coverage"
  fi
done
dir_steps=$(grep -cE '^ +\./gitleaks dir \.' "$WORKFLOW")
if [[ "$dir_steps" == "4" ]]; then
  pass "exactly 4 './gitleaks dir .' invocations — one per event, none orphaned"
else
  fail "expected exactly 4 './gitleaks dir .' invocations (one per event); found $dir_steps"
fi
# Diagnosability: a bare full-tree failure prints only 'leaks found: N' with no
# File/RuleID/Line, and the search space for a tree scan is the whole repo.
# Measured: without -v the output is two INF/WRN lines and nothing else.
dir_verbose=$(grep -cE '^ +\./gitleaks dir \. .*--exit-code 1 -v$' "$WORKFLOW")
if [[ "$dir_verbose" == "4" ]]; then
  pass "all 4 full-tree scans carry -v (findings name File/RuleID/Line)"
else
  fail "only $dir_verbose/4 full-tree scans carry -v — a red gate would be undiagnosable"
fi
# AC6: the push:main comment must no longer describe #6721 as unfixed.
if grep -qF 'direction 1 would invert it' <<<"$wf"; then
  fail "push:main comment still describes #6721 as unfixed ('direction 1 would invert it')"
else
  pass "stale '#6721 unfixed' framing removed from push:main comment"
fi
# The behavioural invariant, not a prose check: no step may SHIP --cc as a
# log-opts value. T2 proves --cc detects nothing, so shipping it anywhere would
# install a gate that cannot fail. Goes RED if someone "simplifies" -m to --cc.
cc_shipped=$(grep -cE 'log-opts="[^"]*--cc' "$WORKFLOW")
if [[ "$cc_shipped" == "0" ]]; then
  pass "no step ships --cc as a log-opts value (it detects nothing — see T2)"
else
  fail "a step ships --cc in log-opts ($cc_shipped) — T2 proves that gate cannot fire"
fi
if grep -qF 'TRAP: `--cc` is NOT an equivalent' <<<"$wf"; then
  pass "workflow documents the --cc silent-no-op trap"
else
  fail "workflow should document the --cc silent-no-op trap for future editors"
fi

echo "T7: WHY the PR job uses 'gitleaks dir', not '-m' — main-sync coupling"
# T5 shows the PR job has a real gap. `-m` is the obvious remedy and is the
# WRONG one: because GitHub sets BASE_SHA to `pull_request.base.sha` (main's
# TIP at PR-event time, not the merge-base), a routine "merge main into my
# branch" puts main's own commits inside BASE..HEAD. Without `-m` the merge
# commit contributes no patch, so they stay invisible. With `-m`, the merge is
# diffed against each parent — and the M-vs-feature diff replays everything
# main brought in, making main-originated content count against THIS PR.
#
# The first attempt to measure this was INCONCLUSIVE: both arms returned rc=0
# because the fixture never reached the state under test, and a silent
# rc=0/rc=0 reads exactly like "no coupling". P1/P2 below exist so that
# failure mode is loud: a broken fixture fails the suite instead of
# fabricating a clean result.
COUPLING="$TMP/coupling"
CB=""; CM=""
build_coupling_fixture() {
  mkdir -p "$COUPLING"
  (
    cd "$COUPLING" || exit 1
    git init -q -b trunk
    git config user.email "coupling-fixture@example.com"
    git config user.name "coupling fixture"
    echo clean > readme.md
    git add -A && git commit -qm "A: base"
    git rev-parse HEAD > .a-sha
    # B: trunk gains a secret of its own. Clean merge, no conflict anywhere —
    # this is the ordinary main-sync shape, not the #6721 conflict shape.
    printf 'url = "%s"\n' "$SEC" > trunk-secret.conf
    git add -A && git commit -qm "B: trunk gains a secret"
    git rev-parse HEAD > .b-sha
    git checkout -q -b feature "$(cat .a-sha)"
    echo feature-work > feature.md
    git add -A && git commit -qm "C: unrelated feature work"
    git merge -q --no-ff trunk -m "M: sync trunk into feature" >/dev/null 2>&1
  )
  CB=$(cat "$COUPLING/.b-sha" 2>/dev/null)
  CM=$(git -C "$COUPLING" rev-parse HEAD 2>/dev/null)
}
scan_coupling() {
  (
    cd "$COUPLING" || exit 1
    gitleaks git --config "$CONFIG" --no-banner --exit-code 1 --log-opts="$1" >/dev/null 2>&1
    echo $?
  )
}
build_coupling_fixture

if [[ -z "$CB" || -z "$CM" ]]; then
  fail "coupling fixture did not build (BASE=$CB HEAD=$CM)"
else
  # P1 (non-vacuity): the planted secret must be detectable at all. Without
  # this, every arm below returns rc=0 and the suite reports "no coupling"
  # about a fixture that contains nothing to find. RuleID oracle, not rc: a scan
  # that fails to run also exits 1, and would certify a fixture it never read.
  if [[ "$HAVE_GITLEAKS" != "1" ]]; then
    _skip_arm "$SUITE: T7 P1" "$GITLEAKS_REASON"
  else
    p1_rules=$(scan_git_rules "$COUPLING" "${CB}~1..${CB}")
    if grep -qx "$RULE" <<<"$p1_rules"; then
      pass "P1: planted trunk secret fires standalone ($RULE in report — fixture is non-vacuous)"
    else
      fail "P1: planted trunk secret does NOT fire standalone ($RULE not in report, got: ${p1_rules:-<none>}) — fixture invalid, T7 result is meaningless"
    fi
  fi
  # P2: the merge must be a genuine 2-parent merge, else -m has nothing to expand.
  if [[ "$(git -C "$COUPLING" rev-list --parents -n1 "$CM" | wc -w)" == "3" ]]; then
    pass "P2: M is a genuine 2-parent merge"
  else
    fail "P2: M is not a 2-parent merge — -m has nothing to expand"
  fi

  if [[ "$HAVE_GITLEAKS" != "1" ]]; then
    _skip_arm "$SUITE: T7 arm_today" "$GITLEAKS_REASON"
    _skip_arm "$SUITE: T7 arm_dash_m" "$GITLEAKS_REASON"
  else
    arm_today=$(scan_coupling "--no-merges ${CB}..${CM}")
    # The coupling claim is "the -m walk REPORTS trunk's secret", so it reads the
    # report's RuleIDs. On rc it passed against a scan that never ran.
    arm_dash_m=$(scan_git_rules "$COUPLING" "-m ${CB}..${CM}")
    if [[ "$arm_today" == "0" ]]; then
      pass "shipped PR form (--no-merges BASE..HEAD) does NOT attribute trunk's secret to the PR (rc=0)"
    else
      fail "expected shipped PR form to stay clean (rc=0), got rc=$arm_today"
    fi
    if grep -qx "$RULE" <<<"$arm_dash_m"; then
      pass "COUPLING CONFIRMED: -m BASE..HEAD attributes trunk-originated content to the PR ($RULE in report)"
    else
      fail "expected -m to couple trunk content ($RULE in report), got: ${arm_dash_m:-<none>} — re-derive the PR-job decision before trusting it"
    fi
  fi
fi

# The consequence, asserted against the shipped artifact: the PR and
# merge_group steps must NOT carry -m in their log-opts. Anchored on the
# range-bearing form so the cron's own `-m --all` (a different, correct use)
# cannot satisfy or trip it.
# Order-independent: `git log` accepts options AFTER revisions, so the original
# `-m ${BASE_SHA}` anchor was evaded by `${BASE_SHA}..${HEAD_SHA} -m` (verified:
# the coupling T7 measures returns in full, suite stayed green). Match `-m` as a
# standalone token anywhere inside a range-bearing log-opts value.
pr_dash_m=$(grep -E 'log-opts="[^"]*\$\{BASE_SHA\}[^"]*"' "$WORKFLOW" \
  | grep -cE '(^|[ "])-m([ "]|$)' || true)
if [[ "$pr_dash_m" == "0" ]]; then
  pass "no PR/merge_group step uses '-m BASE..HEAD' (would couple main's content — see above)"
else
  fail "a PR/merge_group step uses '-m BASE..HEAD' ($pr_dash_m) — coupling is confirmed above"
fi

echo ""
echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed, ${#SKIPPED_ARMS[@]} arm(s) skipped ==="
if [[ "${#SKIPPED_ARMS[@]}" -gt 0 ]]; then
  echo "Skipped arms (gitleaks not runnable):"
  printf '  - %s\n' "${SKIPPED_ARMS[@]}"
  if [[ "${CI:-}" == "true" ]]; then
    echo "FAIL: ${#SKIPPED_ARMS[@]} arm(s) skipped under CI=true — CI installs the pinned gitleaks 8.24.2, so every arm above must run there."
    exit 1
  fi
fi
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
