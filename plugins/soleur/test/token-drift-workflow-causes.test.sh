#!/usr/bin/env bash
# Tests the CONSUMER half of the Cloudflare token-drift detector: the
# `scheduled-terraform-drift.yml` step that parses the detector's --json-file and
# publishes `verdict` / `causes` / `configs` / `coverage` / `coverage_ratio` /
# `configs_floor` / `configs_expected` / `configs_unread` / `inventory_age_days`,
# plus the email and issue bodies that render them.
#
# WHY THIS EXISTS. PR #7134 moved UNVERIFIABLE from one bucket with one static
# remedy to a closed CAUSE vocabulary the workflow branches on, and shipped with the
# emitting side pinned and the consuming side pinned by nothing — stated as a known
# gap in that PR's body rather than papered over. The gap matters because the
# failure it enables is silent: a cause the detector emits but the email never
# renders sends the operator a remedy for a different problem, which is the exact
# defect #7134 existed to remove.
#
# WHAT #7159 CHANGED HERE. The coverage vocabulary moved from `single-config` /
# `multi-config` (a count of configs ENUMERATED, with no denominator — it could not
# tell 2-of-13 from 13-of-13) to `unknown` / `degraded` / `at-floor`, graded by the
# DETECTOR against a floor this step DECLARES in its own `env:`. So the coverage
# cases below no longer test a derivation from `configs`; they test a passthrough
# with a closed-vocabulary clamp, plus the step's own EXTERNAL re-assertion of the
# floor against the pinned minimum of 13.
#
# THREE RULES THIS SUITE FOLLOWS, all learned the hard way:
#
#   1. The parser under test is EXTRACTED FROM THE WORKFLOW, never re-implemented.
#      A hand-copied `python3 -c` would pin the copy, and the workflow could drift
#      away from it while this suite stayed green.
#   2. The expected cause vocabulary is DERIVED FROM THE DETECTOR SOURCE, never
#      restated here. A restated list is a second unsynchronized pin: the detector
#      grows a cause, the list does not, and the parity assertion passes over a
#      cause no email can explain. Deriving it means adding a cause to the detector
#      REDS this suite until the email learns to render it.
#   3. NOTHING IS ASSERTED BY GREPPING THE WORKFLOW FILE (cq-assert-anchor-not-bare-token).
#      This workflow's comments quote the retired states (`multi-config`,
#      `single-config`), the falsified DEAD remedy, and the failure slugs by name —
#      so `! grep -q 'multi-config' "$WF"` FALSE-FAILS on prose, and
#      `grep -c "multi-config" "$WF"` counts prose as coverage. Every assertion here
#      reads a field parsed out of the YAML (comments cannot survive yaml.safe_load)
#      or the step's published outputs.
#
# Run: bash plugins/soleur/test/token-drift-workflow-causes.test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# Reachable: this file is `set -uo pipefail` with no `-e`, so a failed `cd` leaves REPO_ROOT
# empty and execution continues. `git -C ""` then reads the CALLER's repository and the
# comparison below silently reports a verdict about the wrong tree.
: "${REPO_ROOT:?repo root resolved empty; git -C with an empty operand would read the calling repository}"
WF="$REPO_ROOT/.github/workflows/scheduled-terraform-drift.yml"
DETECTOR="$REPO_ROOT/scripts/check-cloudflare-token-drift.sh"
INVENTORY="$REPO_ROOT/apps/web-platform/infra/doppler-config-inventory.txt"

# `/tmp` is a shared 4 GiB tmpfs and a direct invocation of this suite inherits it.
export TMPDIR="${TMPDIR:-/var/tmp}"
PASS=0
FAIL=0
pass() { echo "  pass: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

TMP=$(mktemp -d) || { echo "FATAL: sandbox"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

for f in "$WF" "$DETECTOR" "$INVENTORY"; do
  [[ -f "$f" ]] || { echo "FATAL: missing $f"; exit 2; }
done

echo "=== token-drift workflow consumer ==="

# ---------------------------------------------------------------------------
# HARNESS. Every setup command's status is checked and aborts with exit 2 — a
# harness that fails to set up must not go on to produce a confident wrong verdict.
# ---------------------------------------------------------------------------

# step_get <selector> <path>
#   selector: `id:token_drift` or `name:<step name prefix>`
#   path:     `run` | `if` | `with.body` | `env.DOPPLER_CONFIGS_FLOOR` | `.` (whole step)
#   exit 2 = no such step, exit 3 = no such field.
#
# WHY THIS EXISTS. T12/T13/T14 originally grepped the WHOLE workflow for a literal, which
# pins spelling, not behavior — and this PR simultaneously added a comment block quoting
# those same literals, so a comment satisfies the assertion. All were measured green under
# mutations that reproduced the exact defect each one names:
#   T13  `always()` -> `failure()` on the coverage arm   (step skipped on every clean run)
#   T13  `if:` replaced, literal preserved in a comment  (cq-assert-anchor-not-bare-token)
#   T14  `exit 0` deleted under the short-circuit        (~730 duplicate issues a year)
#   T12  gate-absent re-gated onto the verdict ladder    (security finding pre-empted)
# Selecting the step and asserting inside ITS OWN parsed field is the shape the sibling
# detector suite's W10 adopted for the same reason. A comment cannot survive yaml.safe_load,
# and a missing step is a hard failure rather than a silent zero-match.
step_get() {
  python3 - "$WF" "$1" "$2" <<'PYF'
import sys, yaml
wf, sel, path = sys.argv[1], sys.argv[2], sys.argv[3]
kind, want = sel.split(":", 1)
step = None
for job in yaml.safe_load(open(wf))["jobs"].values():
    for st in job.get("steps", []) or []:
        if kind == "id" and st.get("id") == want:
            step = st
            break
        if kind == "name" and str(st.get("name", "")).startswith(want):
            step = st
            break
    if step is not None:
        break
if step is None:
    sys.stderr.write("no step matching %s\n" % sel)
    raise SystemExit(2)
if path == ".":
    sys.stdout.write(yaml.safe_dump(step, default_flow_style=False, allow_unicode=True))
    raise SystemExit(0)
cur = step
for part in path.split("."):
    if not isinstance(cur, dict) or part not in cur:
        sys.stderr.write("step %s has no '%s'\n" % (sel, path))
        raise SystemExit(3)
    cur = cur[part]
sys.stdout.write(str(cur))
PYF
}

# ---------------------------------------------------------------------------
# COMMENT-STRIPPING, applied to EVERY `run:` body this suite asserts over.
#
# Rule 3 at the top of this file says nothing is asserted by grepping the workflow because
# "comments cannot survive yaml.safe_load". That is true of the workflow's YAML STRUCTURE
# and FALSE of a `run:` block scalar, which yaml.safe_load hands back as one opaque string
# with every `#` line inside it intact. So a shell comment in a step's own `run:` body can
# satisfy an assertion about that body — and the coverage filer's body is ~27% comment
# lines, several of which quote the exact slugs and control-flow fragments asserted below.
# Measured: no in-comment match today, which is precisely why it is worth fixing now rather
# than after one appears.
#
# TWO HELPERS, and the difference matters. `strip_comments` removes comment LINES and keeps
# the line structure, so line-anchored negative assertions (`! grep -qE 'gh issue create.*|
# tail'`) stay scoped to one line. `flatten_body` additionally joins everything into one
# line, which is required only where a sentence is SPLIT ACROSS `echo` calls and a
# line-based grep therefore cannot see it — and which would make a `.*` in a negative
# assertion span the whole body. Use the narrower one unless the sentence spans lines.
strip_comments() { grep -vE '^[[:space:]]*#' <<<"$1"; }
flatten_body() { tr '\n' ' ' <<<"$(strip_comments "$1")" | tr -s ' '; }

# Every `if:` expression in the whole workflow, one per line. Comment-free by
# construction, so a plain grep over THIS is anchored on live syntax.
all_step_ifs() {
  python3 - "$WF" <<'PYA'
import sys, yaml
for job in yaml.safe_load(open(sys.argv[1]))["jobs"].values():
    for st in job.get("steps", []) or []:
        v = st.get("if")
        if v is not None:
            print(" ".join(str(v).split()))
PYA
}

# ---------------------------------------------------------------------------
# Run the WHOLE `token_drift` step body, not a grepped line.
#
# v1 extracted one `read -r …` line and a three-line awk window, and its prose spoke
# about "the step". Review mutated the workflow and found 7 survivors living in the
# lines BETWEEN those two fragments — including deleting the ::warning:: and both
# email footers (the PR's entire user-visible deliverable) at a fully green suite,
# and `if [[ "$rc" == "2" || "$dead" == "-1" ]]` -> `if [[ "$rc" == "2" ]]`, which
# routes a corrupt verdict file to `clean` — the exact thing T4's pass-message claims
# to prevent.
#
# So: pull the step's `run:` body out of the YAML, stub ONLY the detector invocation
# (the external dependency), point $RUNNER_TEMP at a fixture dir and $GITHUB_OUTPUT at
# a temp file, and execute it under `bash -eo pipefail` — the shell Actions actually
# uses. Assertions then read the PUBLISHED outputs, which is what every downstream
# consumer sees.
#
# The invocation is now a FOUR-LINE backslash continuation (`--json-file`,
# `--inventory`, `--configs-floor`), so the stub is located and replaced in python
# rather than by a bash literal: a bash pattern substitution treats the embedded
# backslash-newlines as escapes, and reflowing the call must re-point the extractor
# loudly rather than silently stop stubbing and shell out for real.
# ---------------------------------------------------------------------------
python3 - "$WF" "$TMP/stub" <<'PYS'
import sys, yaml
wf, out = sys.argv[1], sys.argv[2]
body = None
for job in yaml.safe_load(open(wf))["jobs"].values():
    for st in job.get("steps", []) or []:
        if st.get("id") == "token_drift":
            body = st.get("run")
if body is None:
    sys.stderr.write("no step with id: token_drift, or it has no run:\n")
    raise SystemExit(2)
lines = body.split("\n")
# Tolerates a runner prefix (`timeout N `, `env X=Y `) before `bash`. The invocation is
# wrapped in `timeout 300` so a rate-limited run cannot outlive the JOB timeout, which
# would kill it before $GITHUB_OUTPUT is written; anchoring on a bare `bash ` prefix made
# that wrapper invisible to this extractor and the whole harness FATAL'd.
hits = [i for i, l in enumerate(lines)
        if "bash scripts/check-cloudflare-token-drift.sh" in l and not l.lstrip().startswith("#")]
if len(hits) != 1:
    sys.stderr.write("expected exactly 1 detector invocation, found %d\n" % len(hits))
    raise SystemExit(3)
s = hits[0]
e = s
while lines[e].rstrip().endswith("\\"):
    e += 1
call = "\n".join(lines[s:e + 1])
indent = lines[s][:len(lines[s]) - len(lines[s].lstrip())]
lines[s:e + 1] = [indent + 'bash -c "exit ${DET_RC}" || rc=$?']
open(out + ".call", "w").write(call)
open(out + ".body", "w").write("\n".join(lines))
open(out + ".raw", "w").write(body)
PYS
STUB_RC=$?
if (( STUB_RC != 0 )); then
  echo "FATAL: could not extract and stub the token_drift step (exit ${STUB_RC}). Re-point the extractor rather than deleting this case — every assertion below would otherwise test nothing." >&2
  exit 2
fi
STEP_BODY=$(cat "$TMP/stub.raw") || { echo "FATAL: stub.raw unreadable" >&2; exit 2; }
STEP_BODY_STUB=$(cat "$TMP/stub.body") || { echo "FATAL: stub.body unreadable" >&2; exit 2; }
DETECTOR_CALL=$(cat "$TMP/stub.call") || { echo "FATAL: stub.call unreadable" >&2; exit 2; }
[[ -n "$STEP_BODY" && -n "$STEP_BODY_STUB" && -n "$DETECTOR_CALL" ]] \
  || { echo "FATAL: empty extraction" >&2; exit 2; }
pass "the token_drift step body was extracted from the workflow YAML and its detector call stubbed"

echo "H1: the stubbed invocation still captures the detector's status with '|| rc=\$?'"
# `set -uo pipefail` does NOT clear `-e`, and Actions runs this under `bash -eo pipefail
# {0}` — a bare invocation aborts the step at the detector line and every output below it
# is never written, which is the silent-channel shape the whole step is arranged to avoid.
if grep -Fq '|| rc=$?' <<<"$DETECTOR_CALL"; then
  pass "the detector invocation captures rc instead of aborting the step"
else
  fail "the detector invocation no longer carries '|| rc=\$?' (it is: ${DETECTOR_CALL}) — under 'bash -eo pipefail' a non-zero detector aborts the step before a single output is written, leaving every positive-polarity consumer arm unmatched"
fi

echo "H2: the DECLARED floor and the committed inventory each reach the detector's argv EXACTLY ONCE"
# The floor is declared in this step's `env:` and read from nowhere else. If it does not
# reach the detector's argv, the detector falls back to its own default and the step's
# declaration becomes decorative while `configs_floor` still echoes back a number.
#
# THIS WAS TWO `grep -Fq` CALLS, AND THREE MUTATIONS WALKED PAST THEM, all measured green:
#   S4  APPEND `--configs-floor 1` to the invocation, leaving the pinned spelling intact.
#       Both greps still match, F1/F2/F3 read the unchanged `env:` block, and the detector's
#       own arg loop is LAST-WINS — effective floor 1. The gate is disabled at 48/48 green.
#   S5  APPEND `--inventory /nonexistent/inv.txt`. Same shape, and SILENT: the run stays green
#       and `at-floor` while `configs_expected` -> -1, the ratio -> `-`, and `configs_unread`
#       empties. Every denominator this change adds vanishes from both emails and the issue
#       body while the suite reports full coverage.
#   S6  MOVE the pinned literals into inline `# …` comments while the live flags read
#       `--configs-floor 1`. `DETECTOR_CALL` is a raw slice of a `run:` BLOCK SCALAR, and
#       yaml.safe_load hands block scalars back with their `#` lines intact — so this file's
#       own rule 3 ("comments cannot survive yaml.safe_load") is FALSE for exactly this blob.
#
# So: strip comments, TOKENIZE, and count. Counting is what kills append-a-second-copy;
# tokenizing is what kills a value hidden in a comment; and asserting the VALUE (not just the
# flag) is what keeps `--configs-floor 1` from satisfying a presence check.
_H2_CALL=$(strip_comments "$DETECTOR_CALL" | sed -e 's/[[:space:]]*\\$//' | tr '\n' ' ' | tr -s ' ')
_h2=1
for _flag in --configs-floor --inventory; do
  _n=$(grep -oE -- "(^| )${_flag}( |$)" <<<"$_H2_CALL" | grep -c .) || _n=0
  [[ "$_n" == "1" ]] || { _h2=0; echo "    ${_flag} appears ${_n} time(s) in the resolved call, not exactly 1 (last-wins would silently re-point it)"; }
done
grep -qE -- '--configs-floor +"\$DOPPLER_CONFIGS_FLOOR"' <<<"$_H2_CALL" \
  || { _h2=0; echo "    --configs-floor is not passed the step's own \$DOPPLER_CONFIGS_FLOOR"; }
grep -qF -- '--inventory apps/web-platform/infra/doppler-config-inventory.txt' <<<"$_H2_CALL" \
  || { _h2=0; echo "    --inventory does not name the committed inventory path"; }
if [[ "$_h2" == "1" ]]; then
  pass "--configs-floor \$DOPPLER_CONFIGS_FLOOR and --inventory <committed path> each appear exactly once outside comments"
else
  fail "the detector invocation must hand the declared floor and the committed inventory to the detector EXACTLY ONCE each, outside comments (resolved call: ${_H2_CALL}). The arg loop is last-wins, so a second --configs-floor or --inventory silently overrides the first while every spelling-based assertion stays green; and a `#` line inside a run: block scalar survives yaml.safe_load, so a commented-out literal can satisfy a naive grep"
fi

# The floor the workflow declares, read once and reused by the harness so run_step
# reproduces the runner's env rather than inventing one.
WF_FLOOR=$(step_get "id:token_drift" env.DOPPLER_CONFIGS_FLOOR) \
  || { echo "FATAL: the token_drift step declares no env.DOPPLER_CONFIGS_FLOOR" >&2; exit 2; }

# run_step <fixture-dir> <detector-rc> [floor-override] -> "rc|<published key=value lines, ;-joined>"
# The floor override uses `${3-…}` (not `:-`) so an explicitly EMPTY floor reaches the guard.
run_step() {
  local dir="$1" det_rc="${2:-0}" floor="${3-$WF_FLOOR}"
  local out; out=$(mktemp -p "$TMP") || return 2
  local step_rc=0
  # Under $TMP so the EXIT trap reclaims it. `mktemp` put one file per call in TMPDIR
  # (exported to /var/tmp above) and never removed it — ~20 leaked strays per run.
  STEP_STDOUT="$TMP/step-stdout.$$"
  DET_RC="$det_rc" \
  DOPPLER_TOKEN="stub-not-a-credential" \
  DOPPLER_PROJECT="soleur" \
  DOPPLER_CONFIGS_FLOOR="$floor" \
  RUNNER_TEMP="$dir" GITHUB_OUTPUT="$out" \
    bash -eo pipefail -c "$STEP_BODY_STUB" >"$STEP_STDOUT" 2>&1 || step_rc=$?
  printf '%s|%s' "$step_rc" "$(tr '\n' ';' < "$out")"
  rm -f "$out"
}

# Read one published output value from a run_step result.
out_val() { printf '%s' "$1" | sed 's/^[0-9]*|//' | tr ';' '\n' | sed -n "s/^$2=//p" | tail -1; }
# The step's exit status from a run_step result.
step_rc_of() { printf '%s' "$1" | sed 's/|.*//'; }

# mkfix <name> <json>. Aborts the whole suite on a setup failure.
mkfix() {
  mkdir -p "$TMP/$1" || { echo "FATAL: mkdir $TMP/$1" >&2; exit 2; }
  printf '%s' "$2" > "$TMP/$1/token-drift.json" || { echo "FATAL: write fixture $1" >&2; exit 2; }
}

COVERAGE_STEP="Open or update an action-required issue (token drift — coverage below the declared floor)"
CLOSE_STEP="Close the coverage issue once the declared floor is met"
DEAD_EMAIL_STEP="Email notification (token drift — DEAD credential)"
DEAD_ISSUE_STEP="Open or update an action-required issue (token drift — DEAD credential)"
UNVER_EMAIL_STEP="Email notification (token drift — UNVERIFIABLE only)"
CHANNEL_EMAIL_STEP="Email notification (token drift — the coverage issue channel is unreachable)"
SCRATCH_STEP="File an issue when the scratch-config half of the sweep was not performed"
SCRATCH_EMAIL_STEP="Email notification (rung-2 sweep — the scratch-config finding could not reach its issue channel)"

# ---------------------------------------------------------------------------
# T1-T5 — the parser's contract.
# ---------------------------------------------------------------------------
mkfix two '{"live":3,"dead":0,"unverifiable":3,"probes":4,"configs":13,
 "configs_floor":13,"configs_expected":13,"configs_unread":[],
 "coverage":"at-floor","coverage_ratio":"13/13","inventory_age_days":0,
 "stale":[],
 "unverifiable_keys":[
   {"key":"A_ID/_SECRET","cause":"probe-failed","reason":"x"},
   {"key":"B_ID/_SECRET","cause":"gate-absent","reason":"y"},
   {"key":"C_ID/_SECRET","cause":"detector-env","reason":"z"}]}'
# These three are chosen so SET iteration order differs from SORTED order
# (set -> "gate-absent,probe-failed,detector-env"; sorted -> "detector-env,...").
# A two-element fixture happened to hash into sorted order, so dropping sorted()
# from the workflow left the assertion green — the sort was asserted by luck.
echo "T1: multiple causes are comma-joined and SORTED (stable for a downstream match)"
r=$(run_step "$TMP/two" 1)
got="$(out_val "$r" causes)"
if [[ "$got" == "detector-env,gate-absent,probe-failed" ]]; then
  pass "three causes -> sorted 'detector-env,gate-absent,probe-failed' (published output)"
else
  fail "expected sorted 'detector-env,gate-absent,probe-failed', got '$got' — the workflow's email interpolates this string verbatim, and an unsorted set order makes it unstable run-to-run"
fi

mkfix clean '{"live":9,"dead":0,"unverifiable":0,"probes":9,"configs":13,
 "configs_floor":13,"configs_expected":13,"configs_unread":[],
 "coverage":"at-floor","coverage_ratio":"13/13","inventory_age_days":0,
 "stale":[],"unverifiable_keys":[]}'
echo "T2: zero unverifiable rows yield the '-' sentinel, never an empty field"
r=$(run_step "$TMP/clean" 0)
got="$(out_val "$r" causes) $(out_val "$r" configs) $(out_val "$r" verdict) $(out_val "$r" configs_unread)"
if [[ "$got" == "- 13 clean -" ]]; then
  pass "empty vocabulary publishes causes='-', configs=13, verdict=clean, configs_unread='-'"
else
  fail "expected '- 13 clean -', got '$got' — an empty comma-joined field is collapsed by IFS word-splitting, which shifts every later field LEFT and lets \`configs\` (the greedy tail) receive a wrong-but-numeric value"
fi

mkfix nocause '{"live":0,"dead":0,"unverifiable":1,"probes":1,"configs":2,
 "configs_floor":13,"configs_expected":13,"configs_unread":["prd","dev"],
 "coverage":"degraded","coverage_ratio":"2/13","inventory_age_days":0,
 "stale":[],"unverifiable_keys":[{"key":"K","reason":"no cause key at all"}]}'
echo "T3: a row with no 'cause' key degrades to 'unknown', not to a crash"
r=$(run_step "$TMP/nocause" 1)
got="$(out_val "$r" causes) $(out_val "$r" configs)"
if [[ "$got" == "unknown 2" ]]; then
  pass "a malformed row is absorbed as 'unknown'"
else
  fail "expected 'unknown 2', got '$got' — a KeyError here takes the whole step's fallback path and reports the fleet unavailable"
fi

mkfix corrupt '{ this is not json'
echo "T4: corrupt JSON takes the fallback and is NEVER read as clean"
r=$(run_step "$TMP/corrupt" 1)
got="$(out_val "$r" verdict) $(out_val "$r" coverage) $(out_val "$r" coverage_ratio)"
if [[ "$got" == "unavailable unknown -/-" ]]; then
  pass "corrupt verdict file publishes verdict=unavailable, coverage=unknown, ratio='-/-' — never 'clean'"
else
  fail "expected 'unavailable unknown -/-', got '$got' — anything else risks an unreadable scan being read as a healthy fleet, and the ten-token fallback's ARITY moving out of lockstep with the ten-name \`read -r\` leaves the trailing variables empty on exactly the path where nothing else is known"
fi

mkdir -p "$TMP/missing" || { echo "FATAL: mkdir missing" >&2; exit 2; }
echo "T5: a MISSING verdict file takes the same fallback"
r=$(run_step "$TMP/missing" 1)
got="$(out_val "$r" verdict) $(out_val "$r" coverage)"
if [[ "$got" == "unavailable unknown" ]]; then
  pass "missing verdict file publishes verdict=unavailable, coverage=unknown"
else
  fail "expected 'unavailable unknown' for a missing file, got '$got'"
fi

# ---------------------------------------------------------------------------
# T6-T8c — COVERAGE. This is the fan-out question, separate from the verdict
# question: the detector's own header cites "5 of 7 configs stale".
#
# #7159 moved the LADDER into the detector (the side that knows which reads
# succeeded). This step is now a PASSTHROUGH with a closed-vocabulary clamp plus
# an external floor re-assertion, so these cases test exactly that — not a
# re-derivation from `configs`, which no longer happens here.
# ---------------------------------------------------------------------------
mkfix degraded '{"live":4,"dead":0,"unverifiable":0,"probes":4,"configs":7,
 "configs_floor":13,"configs_expected":13,
 "configs_unread":["ci","cli","cli_ops","dev","dev_personal","dev_scheduled"],
 "coverage":"degraded","coverage_ratio":"7/13","inventory_age_days":1,
 "stale":[],"unverifiable_keys":[]}'
mkfix grown '{"live":9,"dead":0,"unverifiable":0,"probes":9,"configs":14,
 "configs_floor":13,"configs_expected":13,"configs_unread":[],
 "coverage":"at-floor","coverage_ratio":"14/13","inventory_age_days":2,
 "stale":[],"unverifiable_keys":[]}'

echo "T6: a detector-graded 'at-floor' scan publishes coverage=at-floor with its ratio and floor"
r=$(run_step "$TMP/clean" 0)
got="$(out_val "$r" coverage) $(out_val "$r" coverage_ratio) $(out_val "$r" configs_floor) $(out_val "$r" configs_expected)"
if [[ "$got" == "at-floor 13/13 13 13" ]]; then
  pass "coverage=at-floor, ratio 13/13, floor 13, expected 13 all reach \$GITHUB_OUTPUT"
else
  fail "expected 'at-floor 13/13 13 13', got '$got' — every downstream arm (the close arm, both email caveats, the issue body) reads these four outputs, and a dropped one publishes a bare 'key=' that no positive-polarity condition matches"
fi

echo "T7: a detector-graded 'degraded' scan publishes degraded WITH the unread config names"
r=$(run_step "$TMP/degraded" 0)
got="$(out_val "$r" coverage) $(out_val "$r" coverage_ratio) $(out_val "$r" configs) $(out_val "$r" configs_unread)"
if [[ "$got" == "degraded 7/13 7 ci,cli,cli_ops,dev,dev_personal,dev_scheduled" ]]; then
  pass "7-of-13 publishes degraded, ratio 7/13, and the six unread names comma-joined and sorted"
else
  fail "expected 'degraded 7/13 7 ci,cli,cli_ops,dev,dev_personal,dev_scheduled', got '$got' — the unread list is the operator's only evidence of WHICH narrowing occurred (N2 scoped to prd reads exactly 7 of 13), and without it the issue body says a number and names nothing"
fi

echo "T7b: legitimate GROWTH above the floor stays at-floor (the gate is '>=', not '==')"
r=$(run_step "$TMP/grown" 0)
got="$(out_val "$r" coverage) $(out_val "$r" coverage_ratio)"
if [[ "$got" == "at-floor 14/13" ]]; then
  pass "14 configs against a floor of 13 -> at-floor at 14/13, no state flip"
else
  fail "expected 'at-floor 14/13', got '$got' — an equality gate reds the cron twice daily the first time a prd_git_data or a rehearsal config appears, which is the noise that gets a real alarm filtered"
fi

echo "T8: every value outside the closed vocabulary clamps to 'unknown', never to a confident state"
# The vocabulary is `unknown | degraded | at-floor`. The clamp's DEFAULT must be the
# unmeasured state: the first version of the old in-YAML ladder defaulted to the
# optimistic state and moved off it on two guarded assignments, so `None` (a JSON null
# reaching d.get), a negative, a word, or any field-shift out of `read -r`'s greedy last
# variable ALL asserted fleet-wide coverage — and the email then reassured the operator
# with that word. Pinning only one bad input cannot see that.
_t8=1
for bad in None null -1 abc AT-FLOOR at_floor "at-floor-ish"; do
  mkfix badcov "{\"live\":0,\"dead\":0,\"unverifiable\":0,\"probes\":0,\"configs\":13,
 \"configs_floor\":13,\"configs_expected\":13,\"configs_unread\":[],
 \"coverage\":$([[ "$bad" == "null" ]] && printf 'null' || printf '"%s"' "$bad"),\"coverage_ratio\":\"13/13\",\"inventory_age_days\":0,
 \"stale\":[],\"unverifiable_keys\":[]}"
  c=$(out_val "$(run_step "$TMP/badcov" 0)" coverage)
  [[ "$c" == "unknown" ]] || { _t8=0; echo "    coverage='$bad' published '$c'"; }
done
if [[ "$_t8" == "1" ]]; then
  pass "None, null, -1, abc, a case variant and a near-miss all clamp to unknown"
else
  fail "a coverage value outside {unknown,degraded,at-floor} published something other than 'unknown' — the confident state must never be the default for a value we could not recognise, because the close arm fires on it and silences the channel"
fi

echo "T8b: the RETIRED states are unproducible — no live construct can publish or match them"
# Two halves, because either alone is defeatable.
#  (a) BEHAVIOR: a detector still emitting the old vocabulary clamps to unknown rather
#      than being passed through as a state with no denominator behind it.
#  (b) SYNTAX: no `if:` expression anywhere in the workflow keys on them. Asserted over
#      the PARSED `if:` fields, never a file grep — this workflow's comments name
#      `multi-config` and `single-config` five times while explaining why they are gone,
#      and a file-wide `! grep -q` would FALSE-FAIL on that prose.
_t8b=1
for retired in multi-config single-config full; do
  mkfix retired "{\"live\":0,\"dead\":0,\"unverifiable\":0,\"probes\":0,\"configs\":13,
 \"configs_floor\":13,\"configs_expected\":13,\"configs_unread\":[],
 \"coverage\":\"${retired}\",\"coverage_ratio\":\"13/13\",\"inventory_age_days\":0,
 \"stale\":[],\"unverifiable_keys\":[]}"
  c=$(out_val "$(run_step "$TMP/retired" 0)" coverage)
  [[ "$c" == "unknown" ]] || { _t8b=0; echo "    retired state '$retired' was passed through as '$c'"; }
done
ALL_IFS=$(all_step_ifs) || { echo "FATAL: could not enumerate the workflow's if: expressions" >&2; exit 2; }
_retired_arms=$(grep -Ec "outputs\.coverage[[:space:]]*[!=]=[[:space:]]*'(multi-config|single-config|full)'" <<<"$ALL_IFS")
if [[ "$_t8b" == "1" && "$_retired_arms" == "0" ]]; then
  pass "multi-config / single-config / full clamp to unknown and no step's if: keys on them"
else
  fail "a retired coverage state is still live (passthrough ok=${_t8b}, if: arms matching a retired state=${_retired_arms}) — 'multi-config' counted configs ENUMERATED with no denominator, so it could not tell 2-of-13 from 13-of-13, and an arm still keying on it fires from a state nothing produces (dead channel) or passes a denominatorless count off as coverage"
fi

echo "T8c: a FIELD SHIFT lands in the greedy tail and publishes configs=-1, not a wrong number"
# `configs` is LAST in the `read -r` and therefore greedy. The list-valued fields are
# comma-joins that can be empty, and IFS word-splitting collapses an empty field, shifting
# every later field LEFT. An empty `coverage_ratio` reproduces that: nine words arrive for
# ten names, so the shift must terminate in `configs` — which then fails `^[0-9]+$` and
# publishes the -1 sentinel rather than a plausible count.
#
# `coverage` MUST FOLLOW `configs` DOWN. `coverage` sits BEFORE the shift point and is a
# detector passthrough, so the greedy-tail guarantee protects `configs` and not it — left
# alone, this fixture publishes `configs=-1` beside a confident `at-floor`, and the close
# arm fires on `at-floor` alone. That pair silently CLOSES the coverage issue on a run that
# parsed no count at all. The vocabulary clamp cannot catch it (`at-floor` is IN the
# vocabulary), so the step ties the two explicitly: an unreadable count forces `unknown`.
mkfix shifted '{"live":0,"dead":0,"unverifiable":0,"probes":0,"configs":13,
 "configs_floor":13,"configs_expected":13,"configs_unread":[],
 "coverage":"at-floor","coverage_ratio":"","inventory_age_days":0,
 "stale":[],"unverifiable_keys":[]}'
r=$(run_step "$TMP/shifted" 0)
if [[ "$(out_val "$r" configs)" == "-1" ]]; then
  pass "an empty mid-list field shifts into the greedy tail and configs publishes -1"
else
  fail "a field shift left configs='$(out_val "$r" configs)' — a wrong-but-numeric count is fail-OPEN: it is the number the issue body, both email caveats and the close arm's comment all quote as fact"
fi
if [[ "$(out_val "$r" coverage)" == "unknown" ]]; then
  pass "an unreadable configs drags coverage to unknown, so the close arm cannot fire"
else
  fail "configs was unparseable but coverage published '$(out_val "$r" coverage)' — the close arm fires on at-floor, so this silently closes the coverage issue on a run that measured nothing"
fi
if [[ "$(out_val "$r" coverage_ratio)" == "-/-" ]]; then
  pass "the ratio is blanked alongside the forced-unknown coverage"
else
  fail "coverage_ratio='$(out_val "$r" coverage_ratio)' survived a forced-unknown coverage — both ops emails quote this ratio as measured fact"
fi

# ---------------------------------------------------------------------------
# T9-T11 — VOCABULARY PARITY. The cause set is derived from the detector source,
# so a new cause reds this suite until the workflow email learns to render it.
# ---------------------------------------------------------------------------
# DERIVE FROM THE EMITTED LITERAL, not from the internal state string. `UNVERIFIABLE:
# <cause>` is the PAIR_VERDICT map VALUE; what actually reaches the JSON the workflow
# parses is the second field of an `UNVERIFIABLE_ROWS+=(...)` push, produced by a `case`
# that translates the first into the second. Deriving from PAIR_VERDICT pinned the wrong
# side: renaming ONE row literal (`|probe-failed|` -> `|probe-timeout|`) while leaving
# its PAIR_VERDICT string intact left this suite fully green while the detector emitted
# a cause the email had no <li> for — the exact defect this file exists to catch.
# Verified by mutation.
mapfile -t CAUSES < <(grep -oE 'UNVERIFIABLE_ROWS\+=\("\$\{base\}_ID/_SECRET\|[a-z-]+\|' "$DETECTOR" \
                      | grep -oE '\|[a-z-]+\|' | tr -d '|' | sort -u)
# The two vocabularies must agree. They are separate literals in separate lines of the
# detector, so either can drift alone: a PAIR_VERDICT state with no `case` arm emits
# nothing (dead code), and an emitted cause with no PAIR_VERDICT state means the `case`
# invented one. Cardinality is the cheap cross-check — a member either extraction cannot
# see is otherwise silently exempt from every parity assertion below, and that exemption
# is invisible on a green run.
mapfile -t _PAIR_CAUSES < <(grep -oE 'UNVERIFIABLE:[a-z-]+' "$DETECTOR" | sed 's/^UNVERIFIABLE://' | sort -u)
# The unmapped-base row is pushed with a literal `|no-probe-configured|` field and has no
# PAIR_VERDICT state at all, so it is expected in CAUSES and not in _PAIR_CAUSES.
echo "T9a: the emitted cause vocabulary and the internal PAIR_VERDICT vocabulary agree"
_only_pair=()
for c in "${_PAIR_CAUSES[@]}"; do
  grep -qx "$c" <<<"$(printf '%s\n' "${CAUSES[@]}")" || _only_pair+=("$c")
done
if (( ${#_only_pair[@]} == 0 )); then
  pass "every PAIR_VERDICT state has a matching emitted row literal (${#_PAIR_CAUSES[@]} states, ${#CAUSES[@]} emitted)"
else
  fail "PAIR_VERDICT states with no matching emitted row literal: ${_only_pair[*]} — the case translating state to row has drifted, so the detector either emits a cause name nothing derived or drops one entirely"
fi
# `unknown` originates in the WORKFLOW's parser (r.get("cause","unknown")), not in the
# detector — so a detector-only derivation is blind to it, which is exactly where T3's
# fixture lives. T3 pins it as contract; the email must therefore explain it.
grep -qF 'r.get("cause","unknown")' <<<"$STEP_BODY" && CAUSES+=("unknown")
mapfile -t CAUSES < <(printf '%s\n' "${CAUSES[@]}" | sort -u)

# FLOOR AT THE CURRENT COUNT, not far below it. This was `>= 5` against 11 derived —
# six free slots, and a floor that slack cannot distinguish "the extraction broke" from
# "it worked". Measured: refactoring four detector cause literals behind a variable
# (invisible to the extraction) AND deleting their four email remedies left this suite
# 22/22 green, with T10 then checking 7 of 11 causes and the parity claim silently
# covering less. A DROP below this number means the extraction drifted; raise it when
# the detector legitimately grows a cause.
echo "T9: the cause vocabulary is complete (guards a silently-broken extraction)"
if (( ${#CAUSES[@]} >= 11 )); then
  pass "derived ${#CAUSES[@]} causes from the detector: ${CAUSES[*]}"
else
  fail "derived only ${#CAUSES[@]} causes — the extraction regex has drifted from the detector, and every parity assertion below would pass vacuously over an empty set"
fi

# The UNVERIFIABLE email body is the operator's per-cause remedy surface. Read from the
# step's PARSED `with.body`, not grepped out of the file: the previous `grep -F … -A 2 |
# head -4` window pinned a line offset, and this workflow's comments quote cause names.
UNVER_BODY=$(step_get "name:$UNVER_EMAIL_STEP" with.body) \
  || { echo "FATAL: could not read the UNVERIFIABLE email body" >&2; exit 2; }
echo "T10: every cause the detector can emit is explained in the UNVERIFIABLE email"
missing=()
# ANCHORED AT LIST-ITEM POSITION, via the SAME extraction its sibling T11 uses twenty lines
# down, and for the same reason T11 states: this body legitimately uses bare <code> for
# non-cause spans (access_hostname_for(), the script path, the coverage states `degraded` /
# `at-floor`, the output field names), so `grep -qF "<code>${c}</code>"` can be satisfied by
# a span that is not a per-cause remedy at all. No collision today — the collision arrives
# the first time a cause name is also a coverage state or an output field name, and T10 is
# then green over an email that explains nothing (cq-assert-anchor-not-bare-token).
#
# Deriving the SET once, rather than one grep per cause, is what keeps the two directions
# symmetric: T10 asks "is every derived cause in the rendered set", T11 asks "is every
# rendered entry a derived cause", and both now read the same rendered set.
mapfile -t _RENDERED_CAUSES < <(printf '%s' "$UNVER_BODY" \
         | grep -oE '<li><code>[a-z-]+</code>( / <code>[a-z-]+</code>)?' \
         | grep -oE '<code>[a-z-]+</code>' | sed 's/<\/\?code>//g' | sort -u)
for c in "${CAUSES[@]}"; do
  grep -qxF "$c" <<<"$(printf '%s\n' ${_RENDERED_CAUSES[@]+"${_RENDERED_CAUSES[@]}"})" || missing+=("$c")
done
if (( ${#missing[@]} == 0 )); then
  pass "all ${#CAUSES[@]} causes have a <li><code>cause</code> entry"
else
  fail "causes with no entry in the operator email: ${missing[*]} — the detector can emit these and the email cannot explain them, so the operator receives a remedy for a different problem (the exact defect #7134 removed one layer down)"
fi

echo "T11: the email does not explain a cause the detector cannot emit"
stale_entries=()
while IFS= read -r tok; do
  found=0
  for c in "${CAUSES[@]}"; do [[ "$tok" == "$c" ]] && { found=1; break; }; done
  (( found == 0 )) && stale_entries+=("$tok")
# NO membership filter on the input. The first version piped through
# `grep -E "^(${CAUSES[*]}|unknown)$"` — which keeps ONLY tokens already in CAUSES — and
# then asked whether each survivor was in CAUSES. `found` was always 1 and this assertion
# could not fail in either direction. Measured: injecting <code>bogus-orphan</code> into
# the email body left the suite 22/22 green.
#
# Anchored on `<li><code>` rather than a bare `<code>`, because the same body legitimately
# uses <code> for non-cause spans (access_hostname_for(), the script path, the coverage
# states) and those are not orphaned remedies. Cause entries are always at list-item
# position, optionally as a `<code>a</code> / <code>b</code>` pair sharing one remedy.
done < <(printf '%s' "$UNVER_BODY" \
         | grep -oE '<li><code>[a-z-]+</code>( / <code>[a-z-]+</code>)?' \
         | grep -oE '<code>[a-z-]+</code>' | sed 's/<\/\?code>//g' | sort -u)
if (( ${#stale_entries[@]} == 0 )); then
  pass "no orphaned cause entries in the email"
else
  fail "email explains causes the detector no longer emits: ${stale_entries[*]} — dead remedies train the operator to skim"
fi

# ---------------------------------------------------------------------------
# T12 — the gate-absent arm must fire on CAUSES, not on VERDICT. The ladder is
# first-match (dead > unverifiable > clean), so a security finding gated on the
# verdict is dropped whenever any dead row co-occurs.
# ---------------------------------------------------------------------------
echo "T12: the gate-absent email arm keys on outputs.causes, independent of the verdict ladder"
GATE_IF=$(step_get "name:Email notification (token drift — ACCESS GATE MISSING)" if) || GATE_IF=""
if grep -qF "contains(steps.token_drift.outputs.causes, 'gate-absent')" <<<"$GATE_IF" \
   && ! grep -qE "outputs\.verdict *==" <<<"$GATE_IF"; then
  pass "gate-absent fires on causes, so a co-occurring dead row cannot pre-empt it"
else
  fail "the gate-absent arm does not key on outputs.causes (its if: is '${GATE_IF}') — with a first-match ladder, a dead row anywhere in the same run silently drops the 'nothing is gating this host' finding"
fi

# ---------------------------------------------------------------------------
# T13-T14d — the COVERAGE ISSUE CHANNEL. A degraded scan can still report
# `verdict: clean` and exit 0, matching NO email arm, so this issue is the only
# artifact that channel produces.
# ---------------------------------------------------------------------------
COV_IF=$(step_get "name:$COVERAGE_STEP" if) || COV_IF=""
COV_RUN=$(strip_comments "$(step_get "name:$COVERAGE_STEP" run)") || COV_RUN=""

echo "T13: narrow coverage has a delivery channel that survives a GREEN clean run"
# Three properties, all load-bearing, asserted on the step's OWN parsed `if:`:
#   always()   — a degraded run can exit 0, so failure()/success()-implicit would skip the
#                step on exactly the runs it exists for
#   degraded   — the state this channel's title, body and remedy describe
#   NO `!=`    — `token_drift` is matrix-gated, so on the other leg every output is '' and
#                `'' != 'at-floor'` is TRUE; the step then fires from a leg that never
#                scanned, with a blank body. Positive polarity is what makes it skip-safe.
if grep -qF 'always()' <<<"$COV_IF" \
   && grep -qF "steps.token_drift.outputs.coverage == 'degraded'" <<<"$COV_IF" \
   && ! grep -qF 'coverage !=' <<<"$COV_IF"; then
  pass "an arm fires on coverage alone, positively, independent of verdict/outcome"
else
  fail "the coverage arm's if: is '${COV_IF}' — it must be always() AND test coverage POSITIVELY. A degraded scan can yield verdict=clean, rc=0, outcome=success, so no email arm matches; and a negative test also matches the empty output published by the matrix leg where the detector never ran"
fi

echo "T13b: the coverage arm also covers 'unknown', which no email arm reaches"
if grep -qF "steps.token_drift.outputs.coverage == 'unknown'" <<<"$COV_IF"; then
  pass "an unmeasurable coverage still reaches the issue channel"
else
  fail "coverage=unknown has no channel. It is reachable with a CLEAN verdict (well-formed JSON that simply lacks 'configs'), and no email arm fires on clean — the verdict=='unavailable' email only covers the crash path"
fi

echo "T13c: the filer ALSO fires at 'at-floor' when a named config went unread"
# The third leg, and the counterpart to the close arm's `configs_unread` conjunct. Without it
# the run that the close arm now correctly DECLINES to close reaches nothing at all: `at-floor`
# matches no email arm, no ::warning:: arm and — before this leg — no issue arm, so an
# ephemeral rehearsal config padding the count back to the floor after a real config's read
# failed produced a GREEN cron run with no artifact whatsoever. Withholding a close and filing
# nothing is a channel that goes quiet on exactly the state it was widened to detect.
#
# Asserted on the step's own parsed `if:`, on the FULL comparison, and requiring BOTH halves of
# the conjunction to be present in one leg — `at-floor` alone anywhere in this expression would
# make the filer fire on every healthy run.
if grep -qE "outputs\.coverage[[:space:]]*==[[:space:]]*'at-floor'" <<<"$COV_IF" \
   && grep -qE "outputs\.configs_unread[[:space:]]*!=[[:space:]]*'-'" <<<"$COV_IF"; then
  pass "at-floor with a non-empty configs_unread still reaches the issue channel"
else
  fail "the coverage filer's if: is '${COV_IF}' — it must carry an (at-floor AND configs_unread != '-') leg. That run is the one the close arm declines to close, and it matches no email arm and no warning arm, so without this leg it is a GREEN cron run with no artifact at all: the credential silently skipped a config the inventory names and nothing anywhere says so"
fi

echo "T14: the filer is CREATE-OR-UPDATE-BODY — an existing issue is REWRITTEN, never commented on"
# The create-only shape this replaces froze the issue at whichever state filed FIRST:
# dedup here is label-scoped rather than title-scoped, so a `single-config`-era issue
# pinned a stale title and a remedy already performed, and a `degraded` -> `unknown`
# transition (a different fault with a different remedy) was never visible.
# Assert the CONTROL FLOW, not the log sentence: `create-only, not commenting` was an echo
# string, and keeping it while deleting the `exit 0` beneath it left the old suite green.
if grep -qF 'gh issue list --label "$LABEL" --state open' <<<"$COV_RUN" \
   && grep -qE 'gh issue edit "\$EXISTING" --title "\$TITLE" --body-file' <<<"$COV_RUN" \
   && ! grep -qF 'gh issue comment' <<<"$COV_RUN"; then
  pass "an existing open coverage issue has its title and body rewritten in place, and is never commented on"
else
  fail "the coverage filer must dedup on the open-issue query, rewrite the existing issue with 'gh issue edit --title --body-file', and never comment: coverage is a STANDING condition holding on every run until the credential is repaired, so create-or-comment posts ~730 comments a year — while create-only freezes the body at a state this run did not measure"
fi

echo "T14b: a failed UPDATE and a failed CREATE are both reported, not swallowed"
# `… 2>&1 | tail -2 || true` lost gh's exit code behind the pipe (tail exits 0) and then
# discarded what was left. The `gh issue create` here is a THREE-LINE backslash
# continuation, so a line-based grep for 'gh issue create.*| tail' cannot see a pipe added
# on its last line — join the continuations first, or the negative half is unfalsifiable.
COV_RUN_JOINED=$(printf '%s' "$COV_RUN" | sed -z 's/\\\n[[:space:]]*/ /g')
if grep -qF 'token_drift_coverage_update_failed' <<<"$COV_RUN" \
   && grep -qF 'token_drift_coverage_escalation_failed' <<<"$COV_RUN" \
   && ! grep -qE 'gh issue (create|edit).*\| *tail' <<<"$COV_RUN_JOINED"; then
  pass "both the edit and the create branch on their exit status and annotate on failure"
else
  fail "a failed 'gh issue edit' or 'gh issue create' leaves a GREEN step on a GREEN cron run with no correct issue and no annotation. A frozen body asserts a coverage state — and prescribes a remedy — this run did not measure (hr-no-dashboard-eyeball-pull-data-yourself)"
fi

echo "T14c: a failed dedup QUERY fails closed, rather than filing a duplicate"
if grep -qF 'token_drift_coverage_list_failed' <<<"$COV_RUN"; then
  pass "an errored 'gh issue list' declines to create instead of reading empty as 'none open'"
else
  fail "the dedup query's failure is indistinguishable from 'no issue open', and the create path reads empty as 'file one' — so every transient API fault adds a permanent duplicate"
fi

echo "T14d: the label re-assert is a SEPARATE '|| true' call, so it cannot swallow the edit's status"
# Folding `--add-label` into the body edit would swallow the body edit's exit status into
# the `|| true` the label re-assert needs — and a failed body update freezes the issue at
# whichever state filed first, the exact defect the update path exists to remove.
if grep -qE 'gh issue edit "\$EXISTING" --add-label action-required.*\|\| true' <<<"$COV_RUN" \
   && ! grep -qE 'gh issue edit "\$EXISTING" --title "\$TITLE" --body-file.*\|\| true' <<<"$COV_RUN"; then
  pass "the body edit's status is branched on; only the label re-assert is '|| true'"
else
  fail "the label re-assert and the body edit share one call, so '|| true' swallows the body edit's status — a failed rewrite is then indistinguishable from a successful one, and the issue silently freezes at the state that filed first while the label re-assert reports success"
fi

echo "T14e: the DEGRADED issue body names the UNREAD configs and the ratio, not just a count"
if grep -qF '${CONFIGS_UNREAD}' <<<"$COV_RUN" \
   && grep -qF '${COVERAGE_RATIO}' <<<"$COV_RUN" \
   && grep -qF '${CONFIGS_FLOOR}' <<<"$COV_RUN"; then
  pass "the body renders configs_unread, coverage_ratio and configs_floor"
else
  fail "the coverage issue body does not render the unread config names alongside the ratio and the floor — 'read 7 configs' does not tell the operator WHICH narrowing occurred, and the three (N1 role downgrade, N2 environment scoping, N3 a config-scoped token) have three different remedies. The unread list is the only field that discriminates them"
fi

echo "T14f: the close arm fires ONLY on 'at-floor', and closes rather than comments"
CLOSE_IF=$(step_get "name:$CLOSE_STEP" if) || CLOSE_IF=""
CLOSE_RUN=$(strip_comments "$(step_get "name:$CLOSE_STEP" run)") || CLOSE_RUN=""
_close_states=$(grep -Ec "outputs\.coverage[[:space:]]*==[[:space:]]*'(degraded|unknown)'" <<<"$CLOSE_IF")
if grep -qF "steps.token_drift.outputs.coverage == 'at-floor'" <<<"$CLOSE_IF" \
   && [[ "$_close_states" == "0" ]] \
   && grep -qF 'gh issue close' <<<"$CLOSE_RUN"; then
  pass "coverage recovery to at-floor closes the standing issue without an operator step, and no unhealthy state can trigger it"
else
  fail "the close arm's if: is '${CLOSE_IF}' (unhealthy states matched: ${_close_states}) — it must fire on 'at-floor' ALONE. Closing on 'degraded' or 'unknown' silences the channel on exactly the runs it exists for; firing on nothing makes the issue's stated closing condition ('a scheduled run reports coverage: at-floor') an operator step observable only by opening a GREEN cron run's log"
fi

echo "T14f2: 'at-floor' is NOT sufficient — the close arm carries all THREE conjuncts"
# `at-floor` says the credential read at least the DECLARED FLOOR. It does not say it read
# the configs the inventory NAMES, and it does not say anything was measured:
#   configs_unread == '-'      an ephemeral rehearsal config counts toward `configs` and pads
#                              it back to the floor ONE-FOR-ONE after a real config's read
#                              fails, so `at-floor` alone closes the operator's standing issue
#                              on a run that silently skipped a named config — and closes it
#                              quoting a healthy-looking ratio.
#   verdict != 'unavailable'   a credential that lists NAMES but reads no VALUES counts every
#                              config, satisfies the floor, and draws zero conclusions. The
#                              detector catches it ("PROBED ZERO", exit 2) and this conjunct
#                              is what stops that run closing the issue.
# ANCHORED ON SYNTAX A COMMENT CANNOT PRODUCE: asserted over the step's own PARSED `if:`
# expression, and on the full comparison (`outputs.configs_unread == '-'`), never on the bare
# field names — the workflow's comment block beside this step names both fields repeatedly
# while explaining why they are there (cq-assert-anchor-not-bare-token).
_t14f2=1
grep -qE "outputs\.configs_unread[[:space:]]*==[[:space:]]*'-'" <<<"$CLOSE_IF" \
  || { _t14f2=0; echo "    the close arm does not require configs_unread == '-'"; }
grep -qE "outputs\.verdict[[:space:]]*!=[[:space:]]*'unavailable'" <<<"$CLOSE_IF" \
  || { _t14f2=0; echo "    the close arm does not require verdict != 'unavailable'"; }
if [[ "$_t14f2" == "1" ]]; then
  pass "the close arm requires at-floor AND configs_unread=='-' AND verdict!='unavailable'"
else
  fail "the close arm's if: is '${CLOSE_IF}' — gating on 'at-floor' alone auto-closes the operator's standing coverage issue on a run that skipped a config the inventory names (an ephemeral rehearsal config pads the count back to the floor one-for-one) or that drew no conclusion at all. That is 'a clean bill of health for a question never asked' reproduced at the close arm, and it is strictly WORSE than the pre-PR behaviour, where a failed per-config read exited 2 and fired the DETECTOR-UNAVAILABLE email every run"
fi

echo "T14g: the close comment INTERPOLATES the measured denominator, never a hardcoded 13"
# IT USED TO ASSERT THE LITERAL `13/13` WAS PRESENT. That is the guard restating the value it
# guards: it pinned the literal's PRESENCE and never that it EQUALS the floor or the inventory
# count. Measured — apply the growth edit the inventory's own header prescribes (append
# `prd_git_data`, raise DOPPLER_CONFIGS_FLOOR to 14 in the same PR) and this suite went fully
# GREEN while the auto-close comment on the operator's P1 issue rendered "at `14/14` — the
# credential read 14 of the 13 configs the committed inventory names ... That is 13/13 in the
# steady state". Two false statements, on the one artifact that tells the operator the incident
# is over. Assert the WIRING instead: the run body must interpolate the output, and the step's
# `env:` must actually supply it (an interpolation of a variable no `env:` sets renders empty).
_t14g=1
grep -qF '${CONFIGS_EXPECTED}' <<<"$CLOSE_RUN" \
  || { _t14g=0; echo "    the close comment does not interpolate \${CONFIGS_EXPECTED}"; }
grep -qF '${COVERAGE_RATIO}' <<<"$CLOSE_RUN" \
  || { _t14g=0; echo "    the close comment does not interpolate \${COVERAGE_RATIO}"; }
grep -qE '(^|[^0-9])13/13([^0-9]|$)' <<<"$CLOSE_RUN" \
  && { _t14g=0; echo "    the close comment hardcodes 13/13 — it goes stale the moment the floor legitimately rises"; }
_close_expected=$(step_get "name:$CLOSE_STEP" env.CONFIGS_EXPECTED) || _close_expected=""
[[ "$_close_expected" == '${{ steps.token_drift.outputs.configs_expected }}' ]] \
  || { _t14g=0; echo "    the close step's env: does not carry CONFIGS_EXPECTED (it is '${_close_expected}')"; }
if [[ "$_t14g" == "1" ]]; then
  pass "the close comment renders the run's own configs_expected and ratio, and hardcodes neither"
else
  fail "the close comment must state what coverage was restored TO by interpolating this run's measurements, not by restating a literal. A hardcoded 13 survives every growth edit and every floor change — and the operator reads that comment exactly once, to decide the incident is over"
fi

echo "T14h: a dead ISSUE channel has an email backstop gated on either filer's channel_failed"
CHAN_IF=$(step_get "name:$CHANNEL_EMAIL_STEP" if) || CHAN_IF=""
if grep -qF "always()" <<<"$CHAN_IF" \
   && grep -qF "steps.coverage_issue.outputs.channel_failed == 'true'" <<<"$CHAN_IF" \
   && grep -qF "steps.coverage_close.outputs.channel_failed == 'true'" <<<"$CHAN_IF" \
   && grep -qF 'channel_failed=true' <<<"$COV_RUN" \
   && grep -qF 'channel_failed=true' <<<"$CLOSE_RUN"; then
  pass "both filers publish channel_failed and one always() email arm gates on either"
else
  fail "the coverage finding's only channel is a GitHub issue, and when THAT is what failed the sole artifact is a named ::error:: on a still-GREEN cron run (every path runs under continue-on-error and several 'exit 0' deliberately). The backstop email's if: is '${CHAN_IF}' — it must be always() and gate positively on coverage_issue AND coverage_close channel_failed, and both steps must set it"
fi

echo "T14h2: the backstop ALSO gates on each filer's outcome, which the flag cannot see"
# THE FLAG IS BLIND TO A STALL. Both filers carry `timeout-minutes: 2` plus
# `continue-on-error: true`, so a `gh` call that HANGS is killed AFTER `channel_failed=false`
# has been written and BEFORE `fail_channel` can overwrite it. Result: job green, no issue
# filed or closed, no email sent, and no named slug emitted — the single failure mode this
# backstop exists for, and gating on the flag alone is blind to precisely it.
#
# `outcome` is populated under `continue-on-error` and is `skipped` (never `failure`) for a
# skipped step, so these legs preserve the positive polarity that keeps the `infra/github`
# matrix leg and every healthy run from firing the email.
_t14h2=1
for _st in coverage_issue coverage_close; do
  grep -qE "steps\.${_st}\.outcome[[:space:]]*==[[:space:]]*'failure'" <<<"$CHAN_IF" \
    || { _t14h2=0; echo "    the backstop does not gate on steps.${_st}.outcome == 'failure'"; }
done
grep -qE "steps\.(coverage_issue|coverage_close)\.outcome[[:space:]]*!=" <<<"$CHAN_IF" \
  && { _t14h2=0; echo "    the backstop tests an outcome NEGATIVELY, which also matches the skipped matrix leg"; }
if [[ "$_t14h2" == "1" ]]; then
  pass "both filers' outcome == 'failure' arm the backstop, positively"
else
  fail "the backstop's if: is '${CHAN_IF}' — it must carry an outcome == 'failure' leg for BOTH filers. A stalled gh call is killed by timeout-minutes after channel_failed=false is written and before it can be flipped, so the flag stays false, the job stays green, nothing is filed, no slug is emitted, and no email is sent"
fi

# ---------------------------------------------------------------------------
# T15-T16b — the IN-RUN annotations. Deriving coverage correctly and showing it
# to nobody is the defect this whole signal exists to fix.
# ---------------------------------------------------------------------------
echo "T15: a DEGRADED scan EMITS the ::warning:: annotation, naming the ratio and the unread list"
run_step "$TMP/degraded" 0 >/dev/null
if grep -q '::warning::.*Doppler config' "$STEP_STDOUT" \
   && grep -q '7/13' "$STEP_STDOUT" \
   && grep -q 'Unread: ci,cli' "$STEP_STDOUT"; then
  pass "the annotation is emitted with the ratio and the unread names, not merely derivable"
else
  fail "no ::warning:: carrying the ratio and the unread list on a degraded scan — the derivation was previously pinned while its only in-run surface was not, and a warning that omits WHICH configs went unread cannot distinguish the three narrowings"
fi

echo "T16: an AT-FLOOR scan does NOT emit the warning (no hedge when there is nothing to hedge)"
run_step "$TMP/clean" 0 >/dev/null
# POSITIVE CONTROL. A negative assertion over a log file is satisfied by an EMPTY log —
# a step that died before its first echo passes it vacuously. The verdict line is the last
# thing the step prints before its warning arms, so requiring it proves the step ran all
# the way there and then chose to stay quiet.
if grep -q 'token-drift verdict: clean' "$STEP_STDOUT" \
   && ! grep -q '::warning::' "$STEP_STDOUT"; then
  pass "a scan at the declared floor reaches its verdict line and emits no warning at all"
else
  fail "either the step did not reach its verdict line (so the 'no warning' half is vacuous) or it warned at full coverage — an unconditional hedge is the defect the enforce step's own comment records removing ('a hedge that fires when there is nothing to hedge makes a true alarm look uncertain')"
fi

echo "T16b: an UNMEASURABLE coverage emits its own, differently-worded annotation"
# The `unknown` branch of the ::warning:: was unpinned while its sibling was pinned —
# measured: deleting the branch entirely, and widening the degraded branch's test to
# `!= "at-floor"` (which makes an unreadable verdict file announce "read -/- Doppler
# config(s), below its declared floor of -1"), both left the suite green. That is T15's
# own defect one branch over, and the two states have DISJOINT remedies: `degraded` says
# the credential was narrowed, `unknown` says the detector could not run and the
# credential must not be touched.
run_step "$TMP/corrupt" 0 >/dev/null
if grep -q '::warning::.*could not measure its own coverage' "$STEP_STDOUT" \
   && ! grep -q '::warning::.*below its declared floor' "$STEP_STDOUT"; then
  pass "an unreadable verdict file says so, rather than reporting a narrowed credential"
else
  fail "coverage=unknown did not emit its own annotation — a detector that could not run is being described to the operator as a narrowed credential, whose remedy is unperformable on that path (there is nothing to widen: since #7234 the credential is thirteen config-scoped tokens keyed off the committed inventory, not one project-scoped identity that could be granted more), so the state never clears"
fi

# ---------------------------------------------------------------------------
# T17 — the EXTERNAL floor assertion. A declared number is exact about what the
# step demands, but a number cannot catch its own reduction: a floor edited DOWN
# in the same change that narrows the grant would hold the scan at `at-floor`
# while coverage regressed.
# ---------------------------------------------------------------------------
echo "T17: a floor BELOW the pinned minimum of 13 downgrades the run to degraded"
_t17=1
# 12 is one below; 0 is the degenerate floor every count satisfies. Both must downgrade.
for lowered in 12 0; do
  mkfix lowfloor "{\"live\":9,\"dead\":0,\"unverifiable\":0,\"probes\":9,\"configs\":13,
 \"configs_floor\":${lowered},\"configs_expected\":13,\"configs_unread\":[],
 \"coverage\":\"at-floor\",\"coverage_ratio\":\"13/${lowered}\",\"inventory_age_days\":0,
 \"stale\":[],\"unverifiable_keys\":[]}"
  c=$(out_val "$(run_step "$TMP/lowfloor" 0)" coverage)
  [[ "$c" == "degraded" ]] || { _t17=0; echo "    configs_floor=${lowered} published coverage='$c'"; }
done
# And a floor AT or ABOVE the minimum must NOT be downgraded — an assertion that fires on
# everything is not an assertion.
c_ok=$(out_val "$(run_step "$TMP/clean" 0)" coverage)
c_grown=$(out_val "$(run_step "$TMP/grown" 0)" coverage)
[[ "$c_ok" == "at-floor" && "$c_grown" == "at-floor" ]] || { _t17=0; echo "    floor 13 published '$c_ok', growth published '$c_grown'"; }
if [[ "$_t17" == "1" ]]; then
  pass "floors of 12 and 0 downgrade to degraded; a floor of 13 (and growth above it) does not"
else
  fail "the external floor assertion did not behave as '< 13 -> degraded, >= 13 -> unchanged' — three places must move together to defeat this pin (the run-time assertion, the consumer-suite integer, and the inventory-equality pin), and an assertion that fires on every run or on none is not one of them"
fi

echo "T17b: the floor assertion is GUARDED on 'unknown' — an unreadable run is not re-graded"
# The ladder's evaluation order is pinned `unknown` -> `degraded` -> `at-floor`. Re-grading
# `unknown` into `degraded` would claim a measurement was made, and route the operator to
# the credential remedy on a path where the credential is not the fault.
mkfix unk_lowfloor '{"live":0,"dead":0,"unverifiable":0,"probes":0,"configs":-1,
 "configs_floor":0,"configs_expected":13,"configs_unread":[],
 "coverage":"unknown","coverage_ratio":"-/-","inventory_age_days":0,
 "stale":[],"unverifiable_keys":[]}'
c=$(out_val "$(run_step "$TMP/unk_lowfloor" 0)" coverage)
if [[ "$c" == "unknown" ]]; then
  pass "coverage=unknown at a floor of 0 stays unknown, not degraded"
else
  fail "an unknown coverage at a sub-minimum floor was re-graded to '$c' — 'unknown' means the detector could not run, and its issue body says in as many words 'do not touch the Doppler identity'. Re-grading it to degraded swaps that for the credential remedy, which fixes nothing and never clears"
fi

# ---------------------------------------------------------------------------
# T18-T20 — the verdict ladder and the rendered caveats.
# ---------------------------------------------------------------------------
echo "T18: unverifiable rows publish verdict=unverifiable (the ladder branch actually fires)"
v=$(out_val "$(run_step "$TMP/two" 1)" verdict)
if [[ "$v" == "unverifiable" ]]; then
  pass "unver>0 with dead=0 publishes verdict=unverifiable"
else
  fail "expected verdict=unverifiable, got '$v' — widening the ladder's unver threshold silently disables the UNVERIFIABLE email arm entirely"
fi

echo "T19: both verdict-bearing email bodies carry ONE byte-identical coverage caveat"
# The caveat is the same sentence, in the same medium, for the same reader, in two email
# bodies — and nothing pinned the copies to each other. A presence-only check stays green
# while one is reworded and the other is not, leaving the DEAD and UNVERIFIABLE emails
# disagreeing about what coverage means, in the one sentence whose entire job is to stop
# `clean` being over-read. Same two-copies-one-pin shape as the #7134 defect this suite
# exists for, so: assert the copies are byte-identical.
#
# Read from the PARSED bodies, not from the file: a `grep -oP` over the workflow also
# matches the caveat quoted inside a comment, which would satisfy both the count and the
# uniqueness check without either email carrying it.
DEAD_BODY=$(step_get "name:$DEAD_EMAIL_STEP" with.body) \
  || { echo "FATAL: could not read the DEAD email body" >&2; exit 2; }
_t19=1
mapfile -t _CAVEATS < <(grep -oP '<em>Scan coverage:.*?</em>' <<<"${DEAD_BODY}"$'\n'"${UNVER_BODY}")
if (( ${#_CAVEATS[@]} != 2 )); then
  _t19=0
  echo "    expected exactly 2 coverage caveats (one per verdict-bearing body), found ${#_CAVEATS[@]}"
elif [[ "${_CAVEATS[0]}" != "${_CAVEATS[1]}" ]]; then
  _t19=0
  echo "    the two coverage caveats are not byte-identical"
fi
# And the caveat must carry the fields #7159 added. A caveat naming only the state is the
# denominatorless claim `multi-config` was retired for.
for field in 'outputs.coverage_ratio' 'outputs.configs_floor' 'outputs.configs_expected' 'outputs.configs_unread'; do
  grep -qF "$field" <<<"${_CAVEATS[0]:-}" || { _t19=0; echo "    the caveat omits ${field}"; }
done
if [[ "$_t19" == "1" ]]; then
  pass "the DEAD and UNVERIFIABLE bodies carry one identical caveat rendering ratio, floor, expected and unread"
else
  fail "a verdict-bearing email lost or reworded its coverage caveat — the reader is told a finding without being told how much of the fleet was actually looked at, and two bodies disagreeing about what coverage means is the exact defect this suite exists for"
fi

echo "T20: the verdict log line carries floor: and ratio:, not just the verdict"
run_step "$TMP/degraded" 0 >/dev/null
if grep -q 'token-drift verdict: clean .*floor: 13.*ratio: 7/13' "$STEP_STDOUT"; then
  pass "the echoed verdict line is a CONSUMER of the new fields"
else
  fail "the verdict log line does not carry both 'floor:' and 'ratio:' — the Observability discoverability_test greps this line's prefix, so the prefix keeps matching while the asserted fields are absent, and a `clean` verdict is printed with nothing qualifying its scope"
fi

# ---------------------------------------------------------------------------
# T21-T22 — THE STALE-DENOMINATOR CAVEAT. The >90-day rule exists TWICE in
# production: the detector emits `coverage_caveat`, and this step INDEPENDENTLY
# re-derives the same threshold from `inventory_age_days`. The producer suite
# pins the detector's copy; nothing pinned this one.
# ---------------------------------------------------------------------------
mkfix stale_inv '{"live":9,"dead":0,"unverifiable":0,"probes":9,"configs":13,
 "configs_floor":13,"configs_expected":13,"configs_unread":[],
 "coverage":"at-floor","coverage_ratio":"13/13","inventory_age_days":400,
 "coverage_caveat":"inventory is 400 days old (>90) — the denominator may no longer describe the project",
 "stale":[],"unverifiable_keys":[]}'

echo "T21: an inventory older than 90 days prints the staleness caveat and moves NO state"
# EVERY OTHER FIXTURE IN THIS FILE SETS inventory_age_days TO 0, 1 OR 2, so the workflow's own
# copy of the >90 threshold was exercised by nothing at all — deleting the whole branch, or
# inverting it to `< 90`, left the suite green. The threshold is duplicated across the
# producer and the consumer, which is the two-copies-one-pin shape this file exists for.
#
# BOTH HALVES. The caveat must PRINT (a derivation shown to nobody is the defect this whole
# signal exists to fix), and it must move nothing: the inventory REPORTS and gates nothing, so
# a 400-day-old file must still publish at-floor. If staleness could move a state, an
# un-regenerated file would be able to derive the unhealthy state — or, inverted, to close the
# channel — on the strength of its own mtime.
r=$(run_step "$TMP/stale_inv" 0)
_t21=1
[[ "$(out_val "$r" coverage)" == "at-floor" ]] || { _t21=0; echo "    a stale inventory moved coverage to '$(out_val "$r" coverage)'"; }
[[ "$(out_val "$r" inventory_age_days)" == "400" ]] || { _t21=0; echo "    inventory_age_days published '$(out_val "$r" inventory_age_days)', not 400"; }
grep -q 'token-drift coverage caveat: the committed config inventory is 400 days old' "$STEP_STDOUT" \
  || { _t21=0; echo "    the step did not print its own staleness caveat"; }
# POSITIVE CONTROL on the negative half: a FRESH inventory must NOT print it. A caveat that
# fires at every age is not a threshold, and this branch is the only in-run surface saying the
# denominator may be wrong.
run_step "$TMP/clean" 0 >/dev/null
grep -q 'token-drift coverage caveat' "$STEP_STDOUT" \
  && { _t21=0; echo "    a 0-day-old inventory also printed the staleness caveat"; }
if [[ "$_t21" == "1" ]]; then
  pass "a 400-day-old inventory prints the caveat, publishes age 400, and stays at-floor; a fresh one prints nothing"
else
  fail "the workflow re-derives the >90-day staleness rule independently of the detector, and nothing exercised it — every other fixture here sets the age to 0, 1 or 2. Deleting the branch, or flipping it to fire on a FRESH inventory, is invisible without this case; and if staleness ever moved a state, an un-regenerated file could derive the healthy state from its own mtime"
fi

echo "T22: coverage_caveat is PUBLISHED as an output and rendered in both verdict emails"
# IT HAD NO CONSUMER. The detector emitted it, the producer suite pinned it, and the workflow
# read it nowhere — so the one sentence saying "the denominator in this ratio may not describe
# the project any more" reached the operator in neither email. Emitted-and-unread is the same
# dead-channel shape as derived-and-unshown, which is the defect this whole signal exists for.
#
# IT MUST NOT RIDE THE `read -r`. The caveat is free text with SPACES; IFS word-splitting would
# scatter it across the remaining names and shift `configs`, which is exactly the greedy-tail
# failure T8c pins — manufactured on purpose. So it gets its own extraction, and this case
# proves the extraction works AND that `configs` beside it is undisturbed.
_t22=1
r=$(run_step "$TMP/stale_inv" 0)
[[ "$(out_val "$r" coverage_caveat)" == *"400 days old"* ]] \
  || { _t22=0; echo "    coverage_caveat published '$(out_val "$r" coverage_caveat)'"; }
[[ "$(out_val "$r" configs)" == "13" ]] \
  || { _t22=0; echo "    the multi-word caveat shifted the greedy tail: configs='$(out_val "$r" configs)'"; }
# The `-` sentinel on the path where the detector emitted none, for the same reason every
# other list-valued field carries one: a bare `key=` matches no positive-polarity consumer.
[[ "$(out_val "$(run_step "$TMP/clean" 0)" coverage_caveat)" == "-" ]] \
  || { _t22=0; echo "    an absent caveat did not publish the '-' sentinel"; }
for _body_var in DEAD_BODY UNVER_BODY; do
  grep -qF 'outputs.coverage_caveat' <<<"${!_body_var}" \
    || { _t22=0; echo "    ${_body_var} does not render outputs.coverage_caveat"; }
done
if [[ "$_t22" == "1" ]]; then
  pass "coverage_caveat is published, sentinel-guarded, harmless to the greedy tail, and rendered in both verdict-bearing emails"
else
  fail "coverage_caveat was emitted by the detector and read by nothing. The operator reads the ratio in both verdict emails; the caveat is the only thing that says the DENOMINATOR in that ratio may be stale, missing or unparseable. Either it is rendered beside the ratio or it should not be emitted at all"
fi

# hcl_uncommented <file> — strip `#` line comments, keeping code. Not a full HCL lexer: it
# does not know about `#` inside a quoted string, and it does not need to — no attribute in
# this file carries one, and F5's regex-literal assertion below would red if one appeared.
# Strips `#` AND `//` line comments AND `/* … */` blocks. All three are HCL comment forms,
# and stripping only `#` left C-a defeatable: a `/* … */` block containing a commented-out
# `config = each.key` satisfies C-a's anchored positive while the live attribute binds a
# `local.` (not a string literal, so the negative grep never fires). Measured — that .tf
# passes 60/60 with 13 tokens all bound to one config, which is the exact defect C-a is the
# pre-merge gate for. Not a full HCL lexer: it does not know about `#`/`//` inside a quoted
# string, and does not need to — no attribute in the guarded file carries one, and F5's
# regex-literal assertion would red if one appeared.
hcl_uncommented() {
  # `-z` on the FIRST pass is load-bearing: a `/* … */` block spans lines, and plain `sed`
  # is line-oriented, so a line-scoped pattern silently matches nothing and the block
  # survives whole. Measured — the first version of this fix left the bypass passing 60/60.
  # `-z` makes the file one record so the block pattern can span newlines.
  sed -Ez ':a; s@/\*([^*]|\*+[^*/])*\*+/@@g; ta' "$1" \
    | sed -E 's@(^|[[:space:]])(#|//).*$@@'
}

# ---------------------------------------------------------------------------
# F1-F3 — THE FLOOR PIN (AC29.3). Repo-internal: no credential, no network.
# This is the CI check that fails when the floor and the inventory drift apart.
#
# Three places must move together to lower the floor alongside a narrowed grant:
# the run-time `configs_floor >= 13` assertion (T17), this named integer, and the
# inventory-equality pin below. Defeating it requires editing a test whose only
# purpose is to stop that edit.
# ---------------------------------------------------------------------------
FLOOR_MINIMUM=13

echo "F1: DOPPLER_CONFIGS_FLOOR is declared in the step's own env: and parses as an integer"
if [[ "$WF_FLOOR" =~ ^[0-9]+$ ]]; then
  pass "env.DOPPLER_CONFIGS_FLOOR='${WF_FLOOR}' parses as a non-negative integer"
else
  fail "env.DOPPLER_CONFIGS_FLOOR is '${WF_FLOOR}', which is not an integer — the step's own guard then writes coverage=unknown and exits 2 on every scheduled run, which is a permanently dead detector rather than a silent one, but still a dead one"
fi

echo "F2: the declared floor is at or above the pinned minimum of ${FLOOR_MINIMUM}"
if [[ "$WF_FLOOR" =~ ^[0-9]+$ ]] && (( 10#$WF_FLOOR >= FLOOR_MINIMUM )); then
  pass "DOPPLER_CONFIGS_FLOOR=${WF_FLOOR} >= ${FLOOR_MINIMUM}"
else
  fail "DOPPLER_CONFIGS_FLOOR is '${WF_FLOOR}', below the pinned minimum of ${FLOOR_MINIMUM} — a floor lowered in the same change that narrows the grant holds the scan at 'at-floor' while coverage regresses, which is the one failure this whole coverage ladder exists to make impossible"
fi

# `grep -c` exits 1 on zero matches, so the status is captured rather than allowed to
# collapse a legitimate 0 into an empty string.
INV_RAW_COUNT=$(grep -cE '^[a-z0-9_]+$' "$INVENTORY") || INV_RAW_COUNT=0
# DEDUPED, because the SUT dedupes. See F3b for the divergence this closes.
INV_COUNT=$(grep -E '^[a-z0-9_]+$' "$INVENTORY" | sort -u | grep -c .) || INV_COUNT=0

echo "F2b: the floor is bounded ABOVE as well as below — it EQUALS the inventory count"
# F2 asserted only `>=`, with no ceiling anywhere and T17 exercising only downward (12, 0).
# Measured: a floor of 99 with the inventory padded to 99 names passes F2, F3 and the
# run-time re-assertion — and reds the twice-daily cron forever, because the live project
# can never reach 99. A one-sided ratchet stops the floor being lowered to hide a narrowing
# and does nothing about a floor raised past what the credential can possibly read; the
# second is quieter, because "the alarm has been red for months" reads as an alarm working.
# The equality is asserted against the DEDUPED inventory count for the reason F3b states.
# AND A CEILING THAT THE INVENTORY CANNOT MOVE. Equality alone is not a ceiling: the
# measured S3 mutation raises the floor to 99 AND pads the inventory to 99 names, which
# satisfies every equality in this file while reddening the twice-daily cron forever —
# quietly, because "that alarm has been red for months" reads as an alarm doing its job.
# FLOOR_HEADROOM is a small, deliberate band above the pinned minimum: the project's known
# growth is `prd_git_data` at git-data birth plus ephemeral rehearsal configs, and ephemeral
# ones need no floor edit at all (they only push the count ABOVE it, which the one-sided
# `>=` absorbs). Raising the floor past MINIMUM+HEADROOM is a real event and should cost a
# deliberate edit here, alongside the three `13`s named in the inventory's own header.
FLOOR_HEADROOM=3
_f2b=1
[[ "$WF_FLOOR" =~ ^[0-9]+$ ]] && (( 10#$WF_FLOOR == 10#$INV_COUNT )) \
  || { _f2b=0; echo "    floor ${WF_FLOOR} != inventory count ${INV_COUNT}"; }
[[ "$WF_FLOOR" =~ ^[0-9]+$ ]] && (( 10#$WF_FLOOR <= FLOOR_MINIMUM + FLOOR_HEADROOM )) \
  || { _f2b=0; echo "    floor ${WF_FLOOR} exceeds the ceiling of $((FLOOR_MINIMUM + FLOOR_HEADROOM)) (minimum ${FLOOR_MINIMUM} + headroom ${FLOOR_HEADROOM})"; }
if [[ "$_f2b" == "1" ]]; then
  pass "DOPPLER_CONFIGS_FLOOR=${WF_FLOOR} == ${INV_COUNT} and <= $((FLOOR_MINIMUM + FLOOR_HEADROOM)): bounded above and below"
else
  fail "DOPPLER_CONFIGS_FLOOR='${WF_FLOOR}' must EQUAL the inventory count (${INV_COUNT}) and stay within ${FLOOR_HEADROOM} of the pinned minimum (${FLOOR_MINIMUM}). A floor above what the project can contain is unreachable by any credential and reds the cron twice daily forever; padding the inventory to match it satisfies every equality here while doing exactly that"
fi

echo "F3: the declared floor EQUALS the committed inventory's DEDUPED name count"
if [[ "$WF_FLOOR" =~ ^[0-9]+$ ]] && [[ "$INV_COUNT" =~ ^[0-9]+$ ]] && (( 10#$WF_FLOOR == 10#$INV_COUNT )); then
  pass "DOPPLER_CONFIGS_FLOOR=${WF_FLOOR} == ${INV_COUNT} distinct bare name lines in $(basename "$INVENTORY")"
else
  fail "DOPPLER_CONFIGS_FLOOR='${WF_FLOOR}' but apps/web-platform/infra/doppler-config-inventory.txt lists ${INV_COUNT} distinct names. The change that alters the project's config set owns BOTH edits in the same PR — re-run the '# command:' line in the inventory's header and update the floor. This assertion reads no credential and makes no network call, so it cannot be defeated by narrowing the credential; that is the whole reason it lives here rather than in a live-Doppler verification step"
fi

echo "F3b: the raw and DEDUPED inventory counts agree — a duplicate line is loud, not silent"
# THE TWO SIDES COUNTED DIFFERENT THINGS, and F3 rested on the claim that they did not.
# F3 used `grep -cE '^[a-z0-9_]+$'` — RAW lines. The detector parses the same file with
# `grep -E '^[a-z0-9_]+$' | sort -u` — DEDUPED. Measured on the committed file: append one
# duplicate `prd` line and set the floor to 14 and F3 saw 14 == 14, F2 saw 14 >= 13, and the
# detector saw 13 — a permanent `degraded` that every gate in this suite waved through, with
# the run-time `>= 13` re-assertion agreeing.
#
# F3 dedupes now, which closes the divergence. This assertion is the SEPARATE half: making
# F3 dedupe alone would turn a duplicate line into a silent equality (13 == 13, nothing said)
# rather than a failure, and a duplicated name is a real defect in a file whose whole job is
# to name the configs the credential must reach.
if (( 10#$INV_RAW_COUNT == 10#$INV_COUNT )); then
  pass "${INV_RAW_COUNT} name lines, ${INV_COUNT} distinct — no duplicates"
else
  fail "apps/web-platform/infra/doppler-config-inventory.txt has ${INV_RAW_COUNT} name lines but only ${INV_COUNT} distinct ones. The detector dedupes and this pin dedupes, so the duplicate does not shift the gate — but the file is the operator's statement of which configs must be reachable, and a repeated name means it was hand-edited rather than regenerated. Re-run the '# command:' line in its header"
fi

echo "F4: every Doppler config the infra Terraform NAMES appears in the inventory"
# NOTHING TIED THE INVENTORY'S CONTENT TO ANYTHING. Measured: replace all 13 names with
# `zzz_nonexistent_01..13` and every assertion in this file stays green — the counts still
# match, the floor still equals them — while production prints ratio `13/13` and lists 13
# configs that do not exist in `configs_unread`, in both ops emails and the standing issue
# body. The counts were pinned; the NAMES were pinned by nothing.
#
# WHAT THIS CAN AND CANNOT DO. No offline check can confirm a name exists in live Doppler —
# that needs the credential, and a credential-derived denominator narrows in lockstep with
# the numerator, which is the whole reason the inventory is committed rather than fetched.
# What IS checkable offline: the infra Terraform NAMES several configs directly
# (`config = "prd_terraform"` and friends), and every one of those must be in the inventory,
# because a config the infrastructure depends on is by construction a config the scan must
# reach. That is a strict subset of the 13 and is stated as such — it kills the wholesale
# rename and any regeneration that drops a depended-on config, and it says nothing about the
# remainder.
INFRA_DIR="$REPO_ROOT/apps/web-platform/infra"
# COMMENT-STRIPPED, for the same reason F5 and C-a are (cq-assert-anchor-not-bare-token).
# This used to grep the RAW .tf files, so any `config = "<name>"` written in PROSE counted as
# a Terraform reference — and `token-drift-read-tokens.tf`'s header documents the mis-binding
# hazard by quoting `config = "prd"` verbatim, several times. Measured before and after this
# change: both extractions yield the same five names today, so nothing is being loosened. What
# it fixes is the NON-VACUITY GUARD below: with raw greps, deleting every real `config = "…"`
# attribute in the whole directory would still leave the guard satisfied by comment prose, so
# the one check that exists to catch a drifted extraction could be held up by a sentence.
mapfile -t _TF_CONFIGS < <(
  for _tf in "$INFRA_DIR"/*.tf; do
    [[ -f "$_tf" ]] || continue
    hcl_uncommented "$_tf"
  done 2>/dev/null | grep -ohE 'config[[:space:]]*=[[:space:]]*"[a-z0-9_]+"' \
                   | grep -oE '"[a-z0-9_]+"' | tr -d '"' | LC_ALL=C sort -u
)
unset _tf
_f4=1
if (( ${#_TF_CONFIGS[@]} == 0 )); then
  _f4=0
  echo "    the extraction found NO config names in ${INFRA_DIR}/*.tf (comments stripped) — it has drifted, and this assertion would pass vacuously"
fi
_inv_names=$(grep -E '^[a-z0-9_]+$' "$INVENTORY" | sort -u)
for _c in ${_TF_CONFIGS[@]+"${_TF_CONFIGS[@]}"}; do
  grep -qxF "$_c" <<<"$_inv_names" || { _f4=0; echo "    Terraform names config '${_c}' but the inventory does not list it"; }
done
if [[ "$_f4" == "1" ]]; then
  pass "all ${#_TF_CONFIGS[@]} Terraform-referenced configs are present in $(basename "$INVENTORY")"
else
  fail "the committed inventory must contain every Doppler config the infra Terraform names — those are configs production depends on, so a scan that cannot reach them is exactly the fan-out blindness this detector exists for. A regenerated-and-wrong or hand-edited inventory otherwise prints a healthy ratio over names that mean nothing, and lists nonexistent configs to the operator as 'not read'"
fi

echo "F4b: the inventory's name set never SHRINKS — it is a SUPERSET of the merge base's"
# THE ONE LAYER THAT IS NOT COUNT-FRAMED, and the gap that made it necessary.
#
# F2, F2b, F3 and the workflow's run-time re-assertion all bound a COUNT. Since #7234 the
# thing that matters is a SET: these name lines ARE the `for_each` key set, so the reach of
# the whole scan is the set, not its cardinality. A RENAME moves no count at all — swap
# `prd_cla` for `prd_cla_v2` and F2b's equality holds, F3 holds, F5's derived list still has
# 13 names, the run-time `>= 13` holds, and the scan reports a clean 13/13 while one config
# goes permanently unread and a token is minted for a config that does not exist. The
# 14->13 round trip the inventory's own header describes is the same blindness with the
# count moving DOWN and every pinned literal moving down with it.
#
# WHY NOT LEAVE THIS TO THE DESTROY GUARD. Removing a name DESTROYS that config's read
# token, and `destroy-guard-filter-web-platform.jq` does count planned deletes — but that
# count is inside the `[ack-destroy]`-bypassable `destroy_count` sum, and #7234's own merge
# commit carries `[ack-destroy]` (it retires the project-scoped service account). A PR
# shaped exactly like this one therefore sails through the only layer that fires above 13.
# That guard also has no `for_each` instance-delete fixture anywhere in its 40 tfplan
# cases. This assertion is pre-merge, reads no credential, makes no network call, and
# nothing in a commit message can wave it through.
#
# BASELINE IS THE MERGE BASE, NOT origin/main's TIP. Against the tip, every branch that has
# not rebased past a legitimate inventory GROWTH reds for a shrink it did not make. Against
# the merge base a stale branch compares to the tree it forked from, and CI — which builds
# the PR's MERGE commit — compares the merged result to main. Both are the semantics wanted.
# What this therefore does NOT catch: a stale branch that reverts a merged growth wholesale.
# F2/F3 pin the floor side of that, and a wholesale revert is not this ratchet's job.
#
# Names deliberately RETIRED from the Doppler project. Empty by default: adding a name here
# is what lets the ratchet down by exactly one config, and it is an edit to a test whose
# only purpose is to stop that edit — the same discipline as FLOOR_MINIMUM above. A stale
# entry (the name is gone from the baseline too) is inert rather than an error, because
# making it an error would red main for everyone the moment the removal merged.
INVENTORY_REMOVALS_ACK=()

_f4b=1
_INV_REL="apps/web-platform/infra/doppler-config-inventory.txt"
_base_names=""
_base_has_inventory=0
if ! _merge_base=$(git -C "$REPO_ROOT" merge-base HEAD origin/main 2>/dev/null) || [[ -z "$_merge_base" ]]; then
  _f4b=0
  echo "    could not resolve 'git merge-base HEAD origin/main' — run 'git fetch origin main' (CI: actions/checkout needs fetch-depth: 0, which the test-scripts shard already sets). This FAILS rather than skips: a ratchet that quietly disappears when its baseline is unreachable is the shape that lets the shrink through on exactly the runner where nobody is looking"
elif git -C "$REPO_ROOT" cat-file -e "${_merge_base}:${_INV_REL}" 2>/dev/null; then
  _base_has_inventory=1
  _base_names=$(git -C "$REPO_ROOT" show "${_merge_base}:${_INV_REL}" | LC_ALL=C grep -E '^[a-z0-9_]+$' | LC_ALL=C sort -u)
else
  echo "    the merge base has no ${_INV_REL} — the baseline set is empty, so any current set is a superset of it"
fi
# NON-VACUITY. A baseline blob that exists but parses to nothing means the extraction has
# drifted (a reformatted inventory, a changed name charset), and every comparison below
# would then pass over an empty set forever.
if (( _base_has_inventory )) && [[ -z "$_base_names" ]]; then
  _f4b=0
  echo "    the baseline inventory exists at ${_merge_base} but yielded ZERO parseable names — the extraction has drifted and this ratchet would pass vacuously"
fi
_base_n=$(grep -c . <<<"$_base_names") || _base_n=0
_checked=0
_acked_n=0
# Herestring, not `printf ... | while`: a pipe would put the loop in a SUBSHELL and every
# counter increment below would be discarded, which is the failure mode this loop's own
# accounting guard is written to detect.
while IFS= read -r _bn; do
  [[ -n "$_bn" ]] || continue
  _acked=0
  for _ack in ${INVENTORY_REMOVALS_ACK[@]+"${INVENTORY_REMOVALS_ACK[@]}"}; do
    [[ "$_ack" == "$_bn" ]] && { _acked=1; break; }
  done
  (( _acked )) && { _acked_n=$((_acked_n + 1)); continue; }
  _checked=$((_checked + 1))
  # Herestring, never a pipe: `producer | grep -q` takes SIGPIPE on an early match under
  # `pipefail`, which inverts a negative assertion into a silent pass.
  grep -qxF "$_bn" <<<"$_inv_names" \
    || { _f4b=0; echo "    config '${_bn}' is present in the merge base's inventory and absent from this branch's — a removal or a rename. That DESTROYS its read token and drops the config out of the scan's reach, and no count in this file moves when it is a rename"; }
done <<<"$_base_names"
# THE LOOP ACTUALLY RAN OVER THE BASELINE SET. Measured: deleting the comparison loop
# outright left this file reporting 61/61 and exit 0. The anti-vacuity floor at the bottom
# counts assertion CALLS, not assertion BODIES, so it sees a neutered control as a passing
# one — and the non-vacuity guard above only covers a baseline that fails to PARSE, not a
# comparison that never happens. This reconciles the two counts, so a body that stops
# iterating is as loud as a body that finds a missing name.
if (( _checked + _acked_n != _base_n )); then
  _f4b=0
  echo "    the comparison examined ${_checked} of ${_base_n} baseline names (${_acked_n} acked) — it did not run over the baseline set, so this assertion would report 'reach did not shrink' without having compared anything"
fi
if [[ "$_f4b" == "1" ]]; then
  # Says what was actually established. "all N survive" is FALSE the moment one is acked,
  # and a pass line that overstates its own scope is the defect this suite keeps finding
  # elsewhere.
  pass "reach did not shrink: ${_checked} of the merge base's ${_base_n} config names are still present in $(basename "$INVENTORY"), ${_acked_n} deliberately retired via INVENTORY_REMOVALS_ACK"
else
  fail "the committed inventory is the for_each key set, so its name set is the scan's REACH and must only ever grow. Every other layer here bounds a COUNT, and a rename moves no count: the ratio still reads 13/13 while one config is unread and one token is minted for a config that does not exist. Deliberately retiring a config means adding its name to INVENTORY_REMOVALS_ACK above — a visible edit to a test, which is the point"
fi

# ---------------------------------------------------------------------------
# F5 + C-a — THE PER-CONFIG READ-TOKEN SHAPE (#7234).
#
# The credential is now 13 config-scoped `doppler_service_token`s under one `for_each`,
# keyed off the committed inventory, published as ONE Actions secret holding a JSON map.
# Two things about that shape are worth pinning here, and neither is reachable from the
# workflow YAML the rest of this suite reads:
#
#   F5  the `for_each` list IS the inventory — not a hand-maintained copy of it. A fifth
#       place `13` lives would be a fifth place it can drift.
#   C-a `config = each.key`, never a string literal. This is the ONE mis-binding Terraform
#       can actually produce: `config = "prd"` mints 13 DISTINCT tokens with correct map
#       keys, all bound to one config. It passes every shape check, and Phase 0 measured
#       that it would then surface at runtime as 12 access-denied reads -> `1/13 degraded`.
#       That runtime signal is real but it costs a merge and up to 12 hours; this static
#       assertion costs nothing and fires on the PR.
#
# ASSERTED OVER COMMENT-STRIPPED HCL. The .tf deliberately DOCUMENTS the literal-vs-each.key
# hazard in prose beside the attribute, so a bare grep for `config = "` would match the
# warning against the defect and fail a correct file (cq-assert-anchor-not-bare-token; the
# "narrowing is not anchoring" class in #6456, four occurrences in one PR).
# ---------------------------------------------------------------------------
TF_READ_TOKENS="$INFRA_DIR/token-drift-read-tokens.tf"

# hcl_block <file> <type> <name> — the body of one `resource "<type>" "<name>" { … }`,
# comment-stripped. Brace-counted rather than awk-range'd so a nested block cannot end it
# early. Prints nothing and returns 1 when the block is absent, so callers fail loudly
# instead of asserting over an empty string.
hcl_block() {
  local _out
  _out=$(hcl_uncommented "$1" | awk -v t="$2" -v n="$3" '
    !inb && $0 ~ "resource[[:space:]]+\"" t "\"[[:space:]]+\"" n "\"" { inb=1; d=0 }
    inb {
      for (i=1; i<=length($0); i++) { c=substr($0,i,1); if (c=="{") d++; else if (c=="}") d-- }
      print
      # `seen` is set on the OPENING line unconditionally. Keying it on `d>0` meant a
      # single-line block (`resource "x" "y" { config = each.key }`) closed to d==0 on the
      # same line, never set `seen`, never hit the exit — so the extraction ran to EOF and
      # bled every following resource into the block, silently inverting both C-a greps.
      seen=1
      if (d<=0) { exit }
    }
  ')
  [[ -n "$_out" ]] || return 1
  printf '%s\n' "$_out"
}

echo "F5: the for_each config list is DERIVED from the committed inventory, not restated"
_f5=1
if [[ ! -f "$TF_READ_TOKENS" ]]; then
  _f5=0
  echo "    $(basename "$TF_READ_TOKENS") does not exist — the per-config read-token shape (#7234) is not in place"
else
  _tf_src=$(hcl_uncommented "$TF_READ_TOKENS")
  # (a) the list comes from the inventory FILE, by name.
  grep -qF 'file("${path.module}/doppler-config-inventory.txt")' <<<"$_tf_src" \
    || { _f5=0; echo "    the locals block does not read doppler-config-inventory.txt via file() — the config list has become a second, unpinned copy"; }
  # (b) no normaliser. R4 measured HCL's regex and the detector's grep agreeing on raw
  #     split("\n") lines; adding trimspace() BREAKS that agreement rather than helping.
  if grep -qE '(trimspace|chomp)\(|[^a-z_]trim\(' <<<"$_tf_src"; then
    _f5=0; echo "    the .tf normalises inventory lines (trimspace/trim/chomp) — that diverges it from the detector's grep, which does not"
  fi
  # (c) EXTRACT the accepted-name regex — do not assert it against a hardcoded copy. The
  #     literal is pulled out so (d) can APPLY it; asserting `== "^[a-z0-9_]+$"` here and
  #     then grepping with that same hardcoded string in (d) would compare the detector's
  #     regex to itself and pass for every possible .tf.
  _tf_re=$(sed -nE 's/.*can\(regex\("([^"]+)".*/\1/p' <<<"$_tf_src" | head -1)
  [[ -n "$_tf_re" ]] \
    || { _f5=0; echo "    the .tf's locals block contains no can(regex(\"…\")) name filter — nothing constrains which inventory lines become tokens"; }
  # (d) THE SET-EQUALITY. The regex APPLIED is the one extracted from the .tf; the expected
  #     set is the DETECTOR's own inventory parse. A .tf that filtered differently — a
  #     dropped anchor, an added character class, `[A-Za-z]` — selects a different set here
  #     and reds with the diff named.
  #
  #     ⚠️ THE REACH OF THIS ASSERTION IS BOUNDED BY THE CORPUS, and the comment here used
  #     to overstate it. Measured: `^[a-z]+$` fails, but `^[a-z0-9_-]+$`, `^[a-zA-Z0-9_]+$`
  #     and `^[a-z0-9_]*$` all select the SAME 13 names over the committed inventory and
  #     PASS. Both sides evaluate over one 13-line corpus, so only a corpus-witnessed
  #     divergence can ever fail. A widening that no current name exercises is invisible
  #     here — the reason (e) forbids a literal list and the reason the detector's own
  #     regex is extracted below rather than restated.
  if [[ -n "$_tf_re" ]]; then
    _tf_set=$(LC_ALL=C grep -E "$_tf_re" "$INVENTORY" | LC_ALL=C sort -u)
    # EXTRACTED, not restated. This line used to hardcode the detector's regex, so
    # changing the detector left BOTH suites green while the .tf and the detector diverged
    # — violating this file's own header Rule 2 ("derived from the detector source, never
    # restated here"). Now a change on either side reds.
    _det_re=$(sed -nE "s/.*LC_ALL=C grep -E '(\^[^']+)' \"\\\$INVENTORY_PATH\".*/\1/p" "$DETECTOR" | head -1)
    if [[ -z "$_det_re" ]]; then
      _f5=0; echo "    could not extract the detector's inventory-parse regex from $(basename "$DETECTOR") — the extraction has drifted and this comparison would be vacuous"
      _det_re='^[a-z0-9_]+$'
    fi
    # THE LITERALS THEMSELVES, because set-equality alone cannot pin this. Measured:
    # widening the DETECTOR's regex to `^[a-zA-Z0-9_-]+$` while the .tf keeps
    # `^[a-z0-9_]+$` leaves both sets identical over the committed 13 names and passes.
    # Extracting both sides was necessary and not sufficient — the comparison is bounded by
    # the corpus, so a widening no current name exercises is invisible to it. Comparing the
    # PREDICATES is corpus-independent and reds on any divergence.
    if [[ "$_tf_re" != "$_det_re" ]]; then
      _f5=0
      echo "    the .tf's filter and the detector's inventory parse are DIFFERENT predicates: .tf='${_tf_re}' detector='${_det_re}'. They must be the same string — a config name accepted by one and rejected by the other is either a token minted for a config the scan never counts, or a counted config with no token."
    fi
    _det_set=$(LC_ALL=C grep -E "$_det_re" "$INVENTORY" | LC_ALL=C sort -u)
    _n=$(grep -c . <<<"$_tf_set") || _n=0
    if [[ "$_tf_set" != "$_det_set" ]]; then
      _f5=0
      echo "    the .tf's filter '${_tf_re}' and the detector's inventory parse select DIFFERENT name sets:"
      diff <(printf '%s\n' "$_det_set") <(printf '%s\n' "$_tf_set") | sed 's/^/      /'
    elif (( _n < FLOOR_MINIMUM )); then
      _f5=0; echo "    the derived list has ${_n} names, below the pinned minimum of ${FLOOR_MINIMUM} — that would mint fewer tokens than the floor demands and hold the scan at 'degraded' forever"
    fi
  fi
  # (e) the list is not a hardcoded literal wearing a derivation's clothes.
  if grep -qE 'token_drift_configs[[:space:]]*=[[:space:]]*\[[[:space:]]*"' <<<"$_tf_src"; then
    _f5=0; echo "    local.token_drift_configs is assigned a literal list — a fifth place the number 13 lives, pinned to the inventory by nothing"
  fi
fi
if [[ "$_f5" == "1" ]]; then
  pass "local.token_drift_configs derives from the committed inventory with the detector's own name filter, and yields >= ${FLOOR_MINIMUM} names"
else
  fail "the per-config read tokens must be minted from the committed inventory using the detector's name filter. A restated list is a second unsynchronised pin: the inventory grows a config, the list does not, and the scan mints 13 tokens for a 14-config project while every count in the ladder still agrees with itself"
fi

echo "C-a: the token's config comes from each.key, never a string literal"
_ca=1
if [[ ! -f "$TF_READ_TOKENS" ]]; then
  _ca=0
  echo "    $(basename "$TF_READ_TOKENS") does not exist"
else
  _tok_block=$(hcl_block "$TF_READ_TOKENS" doppler_service_token token_drift) || _tok_block=""
  if [[ -z "$_tok_block" ]]; then
    _ca=0
    echo "    no 'resource \"doppler_service_token\" \"token_drift\"' block found — the extraction has drifted and every assertion below would pass vacuously"
  else
    grep -qE '^[[:space:]]*config[[:space:]]*=[[:space:]]*each\.key[[:space:]]*$' <<<"$_tok_block" \
      || { _ca=0; echo "    the token block does not set 'config = each.key'"; }
    # WHITELIST, not blacklist. The original form rejected only a string literal, so
    # `config = local.pinned` — 13 tokens on one config, identical blast radius — sailed
    # through. Anything that is not literally `each.key` is rejected, whatever its syntax.
    _cfg_binding=$(grep -oE '^[[:space:]]*config[[:space:]]*=[[:space:]]*[^[:space:]]+' <<<"$_tok_block" | head -1 | sed -E 's/.*=[[:space:]]*//')
    if [[ -n "$_cfg_binding" && "$_cfg_binding" != "each.key" ]]; then
      _ca=0
      echo "    the token block binds 'config' to '${_cfg_binding}', not each.key — every instance then reads the SAME config. A string literal, a local. or a var. are all the same defect: 13 distinct tokens, 13 correct map keys, one config actually read. Phase 0 measured the runtime consequence: 12 access-denied reads and a 1/13 degraded run, a merge and up to 12 hours after this line could have been caught here"
    fi
    grep -qE 'for_each[[:space:]]*=[[:space:]]*toset\(local\.token_drift_configs\)' <<<"$_tok_block" \
      || { _ca=0; echo "    for_each is not toset(local.token_drift_configs) — the instance keys and the config bindings are no longer the same set"; }
  fi
  # The map's key and value must come from the SAME iteration variable. A key/value skew
  # would be an HCL bug rather than a producible defect, but the assertion is one grep and
  # it is the line a future edit is most likely to get subtly wrong.
  _sec_block=$(hcl_block "$TF_READ_TOKENS" github_actions_secret doppler_token_drift_map) || _sec_block=""
  if [[ -z "$_sec_block" ]]; then
    _ca=0; echo "    no 'resource \"github_actions_secret\" \"doppler_token_drift_map\"' block found"
  else
    grep -qE 'for[[:space:]]+([A-Za-z_][A-Za-z0-9_]*),[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]+in[[:space:]]+doppler_service_token\.token_drift[[:space:]]*:[[:space:]]*\1[[:space:]]*=>[[:space:]]*\2\.key' <<<"$_sec_block" \
      || { _ca=0; echo "    the published map's key and value do not come from the same 'for' iteration variables over doppler_service_token.token_drift — a skew here hands every config someone else's credential"; }
    grep -qE '\.api_key' <<<"$_sec_block" \
      && { _ca=0; echo "    the map reads .api_key, which belonged to the retired doppler_service_account_token; doppler_service_token exposes .key"; }
  fi
fi
if [[ "$_ca" == "1" ]]; then
  pass "config = each.key, for_each = toset(local.token_drift_configs), and the map's key/value share one iteration variable"
else
  fail "the per-config tokens must bind 'config' to each.key — not a string literal, not a local., not a var. Any of them is the same mis-binding: 13 distinct tokens, 13 correct map keys, one config actually read. It passes shape validation and pairwise-distinctness, which is exactly why it needs a static gate. This assertion reads COMMENT-STRIPPED HCL (#, // and multi-line /* */), because the guarded file documents this hazard in prose beside the attribute"
fi

# ---------------------------------------------------------------------------
# C1-C3 — the CREDENTIAL the step is wired to, and the guard on its floor.
# ---------------------------------------------------------------------------
echo "C1: the step is wired to the per-config credential MAP, not a bare token"
# WHAT THIS PINS, AND WHY IT IS AN EXACT MATCH RATHER THAN "either value". The step reads
# DOPPLER_TOKEN_DRIFT_MAP: ONE Actions secret carrying a JSON object of per-config read
# tokens, minted by `doppler_service_token.token_drift` under a `for_each` over the
# committed inventory. Any THIRD value fails here, and so does a flip back to a bare
# project-scoped credential.
#
# THE HISTORY THIS ASSERTION EXISTS TO STOP REPEATING. #7159 wired this step to a
# `doppler_service_account` on the INFERRED premise that a project membership can
# enumerate and read every config. It was never probed. Measured (#7234): that credential
# saw NOTHING — `doppler configs -p soleur --json` returned null and reading `prd`
# returned "Could not find requested config 'prd'". If you are changing this line, the
# thing to carry forward is not the value but the discipline: measure the credential's
# reach against live Doppler BEFORE wiring it, not after the first scheduled run.
WF_TOKEN_MAP=$(step_get "id:token_drift" env.DOPPLER_TOKEN_MAP) || WF_TOKEN_MAP=""
_has_bare_token=0
step_get "id:token_drift" env.DOPPLER_TOKEN >/dev/null 2>&1 && _has_bare_token=1
if [[ "$WF_TOKEN_MAP" == '${{ secrets.DOPPLER_TOKEN_DRIFT_MAP }}' && "$_has_bare_token" == "0" ]]; then
  pass "DOPPLER_TOKEN_MAP: \${{ secrets.DOPPLER_TOKEN_DRIFT_MAP }}, and no bare DOPPLER_TOKEN alongside it"
else
  fail "the step's DOPPLER_TOKEN_MAP is '${WF_TOKEN_MAP}' (bare DOPPLER_TOKEN present=${_has_bare_token}) — expected \${{ secrets.DOPPLER_TOKEN_DRIFT_MAP }} and no bare token. Setting BOTH is a hard error in the detector: they select different scan modes and there is no defensible precedence, so it refuses rather than grading a config set nobody asked for. Before wiring any different credential here, measure its reach against live Doppler first — the last two premises about this credential that went unmeasured both shipped a scan that read fewer configs than it reported"
fi

echo "C2: DOPPLER_CONFIG is absent, no bare token reference survives, and the map is referenced exactly once"
# Asserted over the PARSED step (comments stripped), because the step's own comment block
# discusses both variable names at length.
STEP_YAML=$(step_get "id:token_drift" .) || { echo "FATAL: could not dump the token_drift step" >&2; exit 2; }
# OCCURRENCES, not matching LINES: `grep -Ec` counts lines and would read 1 for two
# references sharing one. The `_MAP` suffix is what makes the bare-token count reach a
# clean 0 — `secrets\.DOPPLER_TOKEN[[:space:]]*\}\}` cannot match
# `secrets.DOPPLER_TOKEN_DRIFT_MAP }}` because the `_DRIFT_MAP` defeats the `\}\}` tail.
# Reusing the old secret NAME for a map would have made this assertion unwritable.
_bare_token=$(grep -Eo 'secrets\.DOPPLER_TOKEN[[:space:]]*\}\}' <<<"$STEP_YAML" | grep -c .) || _bare_token=0
_map_refs=$(grep -Eo 'secrets\.DOPPLER_TOKEN_DRIFT_MAP[[:space:]]*\}\}' <<<"$STEP_YAML" | grep -c .) || _map_refs=0
_has_cfg=0
step_get "id:token_drift" env.DOPPLER_CONFIG >/dev/null 2>&1 && _has_cfg=1
# DOPPLER_CONFIG must STAY absent. The detector reads each config with that config's OWN
# credential and names it explicitly on every read; a single ambient config would read as
# "which config this scans", the wrong mental model for a fan-out — and the detector
# unsets it anyway, so declaring it here could only mislead a reader.
if [[ "$_has_cfg" == "0" && "$_bare_token" == "0" && "$_map_refs" == "1" ]]; then
  pass "no DOPPLER_CONFIG, zero bare secrets.DOPPLER_TOKEN references, and exactly 1 secrets.DOPPLER_TOKEN_DRIFT_MAP"
else
  fail "the step declares DOPPLER_CONFIG (present=${_has_cfg}), references the bare secrets.DOPPLER_TOKEN ${_bare_token} time(s) (expected 0) or the credential map ${_map_refs} time(s) (expected exactly 1) — this grep sees the WHOLE step YAML, so it catches a reference in a \`with:\` block or a second env key that C1's single-field lookup cannot"
fi

echo "C3: an unset, empty or unparseable floor WRITES the outputs and THEN exits 2"
# THE ORDERING IS THE WHOLE POINT. Failing before the write leaves every
# `steps.token_drift.outputs.*` as the empty string, and every consumer arm in this job
# tests POSITIVELY — so nothing matches: no email, no issue. The final Sentry check-in
# derives its status from steps.plan.outputs.exit_code, not from this step, so the monitor
# would still report `ok`. A misconfigured floor would be a silently dead channel.
_c3=1
for badfloor in "" " " "abc" "13.5" "-1" "1e1"; do
  r=$(run_step "$TMP/clean" 0 "$badfloor")
  rc=$(step_rc_of "$r")
  cov=$(out_val "$r" coverage)
  ver=$(out_val "$r" verdict)
  ratio=$(out_val "$r" coverage_ratio)
  orc=$(out_val "$r" rc)
  [[ "$rc" == "2" && "$cov" == "unknown" && "$ver" == "unavailable" && "$ratio" == "-/-" && "$orc" == "2" ]] \
    || { _c3=0; echo "    floor='${badfloor}' -> step rc=${rc}, published rc=${orc} verdict=${ver} coverage=${cov} ratio=${ratio}"; }
done
if [[ "$_c3" == "1" ]]; then
  pass "empty, blank, non-numeric, fractional, negative and exponent floors all publish rc=2/unavailable/unknown BEFORE exiting 2"
else
  fail "a misconfigured floor did not write its outputs before failing. Failing first leaves every output the empty string, no positive-polarity arm matches, and the Sentry monitor still reports 'ok' — a silently dead channel. Writing first routes it to the DETECTOR-UNAVAILABLE email and the unknown-coverage issue arm, both of which gate on the values written"
fi

# ---------------------------------------------------------------------------
# D1 — the DEAD remedy. The 2026-08-02 census falsified "branch configs inherit
# it": CF_API_TOKEN_DNS_EDIT is carried independently by 7 configs, and the
# prd_terraform / prd root key sets are not in a superset relation in either
# direction. This is the acute arm, on the path that produced the 63-hour
# ADR-154 outage, so the wrong remedy there is the one that costs most.
# ---------------------------------------------------------------------------
echo "D1: neither DEAD body still claims branch configs inherit the prd root value"
DEAD_ISSUE_RUN=$(step_get "name:$DEAD_ISSUE_STEP" run) \
  || { echo "FATAL: could not read the DEAD issue filer's run body" >&2; exit 2; }
# The issue body is built from ~40 `echo` lines, so the remedy sentence is SPLIT ACROSS
# LINES and a line-based grep cannot see it — flatten first (`flatten_body` also drops the
# run body's own shell comments: a `#` line explaining the retired remedy would otherwise
# satisfy the positive half and false-fail the negative one, cq-assert-anchor-not-bare-token).
#
# THREE BODIES, NOT TWO. The `Enforce token-drift result` step was the SIXTH site carrying
# the falsified remedy and the only one this pin could not see: its `dead)` arm printed
# "Set the live value on the 'prd' ROOT config." while the plan recorded the remedy
# "corrected at all five sites". It is also the site that matters most — it is the ::error::
# annotation on the RED run, i.e. the first thing the operator reads — so leaving it
# unpinned meant the loudest copy of the falsified instruction was the unguarded one.
ENFORCE_RUN=$(step_get "name:Enforce token-drift result" run) \
  || { echo "FATAL: could not read the Enforce token-drift result step's run body" >&2; exit 2; }
_d1=1
for body_name in DEAD_EMAIL DEAD_ISSUE DEAD_ENFORCE; do
  case "$body_name" in
    DEAD_EMAIL)   b=$(flatten_body "$DEAD_BODY") ;;
    DEAD_ISSUE)   b=$(flatten_body "$DEAD_ISSUE_RUN") ;;
    DEAD_ENFORCE) b=$(flatten_body "$ENFORCE_RUN") ;;
  esac
  # The falsified claim, in the exact shape both bodies carried it.
  grep -qE 'configs inherit it' <<<"$b" && { _d1=0; echo "    ${body_name} still says 'configs inherit it'"; }
  # And the correction must be present, not merely the falsehood absent — deleting the
  # whole paragraph would satisfy a negative-only assertion while leaving the operator
  # with no remedy at all. `[^.]{0,40}` is bounded so the match stays local to one
  # sentence rather than spanning the flattened body.
  grep -qiE 'does[^.]{0,40}not[^.]{0,40}inherit' <<<"$b" \
    || { _d1=0; echo "    ${body_name} does not state the non-inheritance premise"; }
done
# The DEAD issue's closing condition must name the surviving coverage state. Read from the
# COMMENT-STRIPPED body like its two siblings three lines up: this string is exactly the kind
# a `#` line explaining the coverage vocabulary would carry, and an assertion satisfiable by
# a comment measures the comment (cq-assert-anchor-not-bare-token).
grep -qF 'coverage: at-floor' <<<"$(strip_comments "$DEAD_ISSUE_RUN")" \
  || { _d1=0; echo "    the DEAD issue's closing condition does not name 'coverage: at-floor'"; }
if [[ "$_d1" == "1" ]]; then
  pass "all three DEAD bodies (email, issue, red-run annotation) state that a config does NOT inherit from its environment root, and the issue closes at at-floor"
else
  fail "a DEAD body still carries the falsified inheritance remedy, or lost the correction. Telling the operator to set prd root and stop is the wrong action on the acute arm: measured 2026-08-02, CF_API_TOKEN_DNS_EDIT is carried independently by 7 configs, so the stale copies keep being served while the operator believes the rotation propagated"
fi

# ---------------------------------------------------------------------------
# S1-S2 — the rung-2 scratch-config probe. Its predicate was UNSATISFIABLE as
# wired (a config-scoped service token lists 1 config, so
# startswith("prd_git_data_rehearsal_") can never match), and the sweep reported
# "no orphans" unconditionally rather than because it looked.
# ---------------------------------------------------------------------------
echo "S1: the scratch-config probe publishes a three-state verdict, defaulting to the unconfident one"
SWEEP_RUN=$(strip_comments "$(step_get "id:sweep" run)") || SWEEP_RUN=""
if grep -qF 'scratch_cfg_probe=' <<<"$SWEEP_RUN" \
   && grep -qF '_cfg_probe=failed' <<<"$SWEEP_RUN" \
   && grep -qF '_cfg_probe=unsatisfiable' <<<"$SWEEP_RUN" \
   && grep -qF '_cfg_probe=performed' <<<"$SWEEP_RUN" \
   && ! grep -qE 'doppler configs list.*2>/dev/null' <<<"$SWEEP_RUN"; then
  pass "failed / unsatisfiable / performed are all reachable and the CLI's stderr is no longer discarded"
else
  fail "the scratch-config probe does not publish all three states, or still suppresses the doppler CLI's stderr. '2>/dev/null | jq … || true' made THREE outcomes indistinguishable — a real listing with no matches, a CLI failure, and a jq parse failure all produced the empty string, which the job then reported as 'no orphans': a clean verdict from inspecting nothing"
fi

echo "S2: the two dishonest probe states reach an issue channel, positively gated"
SCRATCH_IF=$(step_get "name:$SCRATCH_STEP" if) || SCRATCH_IF=""
if grep -qF 'always()' <<<"$SCRATCH_IF" \
   && grep -qF "steps.sweep.outputs.scratch_cfg_probe == 'failed'" <<<"$SCRATCH_IF" \
   && grep -qF "steps.sweep.outputs.scratch_cfg_probe == 'unsatisfiable'" <<<"$SCRATCH_IF" \
   && ! grep -qF 'scratch_cfg_probe !=' <<<"$SCRATCH_IF"; then
  pass "'failed' and 'unsatisfiable' both file, and 'performed' files nothing"
else
  fail "the scratch-config filer's if: is '${SCRATCH_IF}' — it must be always() and test the probe POSITIVELY for both dishonest states. A plain-expression if: also carries an implicit success(), and the orphan filer beside it is gated 'orphans != 0', so in the steady state (no Hetzner orphans) a finding routed there reaches nothing; a negative test additionally matches the empty output of a skipped sweep"
fi

echo "S3: the scratch-config filer's named failures arm an ops-email backstop"
# IT HAD NO CHANNEL AT ALL. Both `rung2_scratch_cfg_list_failed` and
# `rung2_scratch_cfg_escalation_failed` were emitted to the run log and nowhere else: the step
# is `continue-on-error: true` and `exit 0`s, this job publishes no Sentry check-in, and there
# was no email arm — so a `gh` failure left a GREEN cron run whose only artifact was an
# annotation nobody opens (`hr-no-dashboard-eyeball-pull-data-yourself`). That is the identical
# shape the coverage filer's own backstop exists to eliminate, one job over.
SCRATCH_RUN=$(strip_comments "$(step_get "name:$SCRATCH_STEP" run)") || SCRATCH_RUN=""
SCRATCH_EMAIL_IF=$(step_get "name:$SCRATCH_EMAIL_STEP" if) || SCRATCH_EMAIL_IF=""
_s3=1
# Both named failures must FLIP THE FLAG, not merely annotate. Asserted on the assignment
# syntax, which a `#` line cannot produce — and the body is comment-stripped besides.
grep -qF 'channel_failed=false' <<<"$SCRATCH_RUN" \
  || { _s3=0; echo "    the filer never writes the channel_failed=false default"; }
[[ "$(grep -c 'channel_failed=true' <<<"$SCRATCH_RUN")" -ge 1 ]] \
  || { _s3=0; echo "    no path in the filer sets channel_failed=true"; }
for _slug in rung2_scratch_cfg_list_failed rung2_scratch_cfg_escalation_failed; do
  grep -qF "$_slug" <<<"$SCRATCH_RUN" || { _s3=0; echo "    the filer no longer emits ${_slug}"; }
done
# The list path must go through the same flag-setting helper as the create path. A bare
# `echo "::error::…"` there is exactly what the close arm carried, and it left one of the two
# failure paths unable to arm the email it is backed by.
grep -qE 'fail_channel "rung2_scratch_cfg_list_failed' <<<"$SCRATCH_RUN" \
  || { _s3=0; echo "    the list-failure path annotates without arming the backstop"; }
grep -qE 'fail_channel "rung2_scratch_cfg_escalation_failed' <<<"$SCRATCH_RUN" \
  || { _s3=0; echo "    the create-failure path annotates without arming the backstop"; }
# And the email arm: always(), positive polarity, plus the outcome leg that covers the stall
# the flag cannot see (see T14h2 for the full reasoning — same failure mode, same fix).
grep -qF 'always()' <<<"$SCRATCH_EMAIL_IF" \
  || { _s3=0; echo "    the backstop email is not always() — the sweep job can fail earlier"; }
grep -qE "steps\.scratch_cfg_issue\.outputs\.channel_failed[[:space:]]*==[[:space:]]*'true'" <<<"$SCRATCH_EMAIL_IF" \
  || { _s3=0; echo "    the backstop email does not gate on the filer's channel_failed"; }
grep -qE "steps\.scratch_cfg_issue\.outcome[[:space:]]*==[[:space:]]*'failure'" <<<"$SCRATCH_EMAIL_IF" \
  || { _s3=0; echo "    the backstop email has no outcome == 'failure' leg (blind to a stalled gh call)"; }
grep -qE "channel_failed[[:space:]]*!=" <<<"$SCRATCH_EMAIL_IF" \
  && { _s3=0; echo "    the backstop email tests the flag NEGATIVELY, so it fires from the skipped steady-state run"; }
if [[ "$_s3" == "1" ]]; then
  pass "both named scratch-config failures set channel_failed and an always() ops-email arm gates on it plus outcome"
else
  fail "the scratch-config filer's only channel is a GitHub issue, and when THAT is what failed the sole artifact is a named ::error:: on a still-GREEN cron run (the step is continue-on-error and exits 0, and this job has no Sentry check-in). Its backstop email's if: is '${SCRATCH_EMAIL_IF}'"
fi

echo "S4: the scratch-config probe demands a DECLARED floor, not a bare count of 2"
# `elif (( 10#$_cfg_total < 2 ))` published `performed` for a credential listing 2 of 13
# configs — the sweep then reported "no orphaned scratch Doppler config" while a
# `prd_git_data_rehearsal_*` could sit in any of the 11 it never listed. That is `multi-config`
# verbatim, the retired state this same change exists to remove ("could not tell 2-of-13 from
# 13-of-13"), re-committed in a second job. Unreachable today (this job's credential lists
# exactly 1) and nothing held it there — S1 asserts only that the three state literals appear.
_s4=1
_rung2_floor=$(step_get "id:sweep" env.RUNG2_CONFIGS_FLOOR) || _rung2_floor=""
[[ "$_rung2_floor" =~ ^[0-9]+$ ]] \
  || { _s4=0; echo "    the sweep step declares no integer env.RUNG2_CONFIGS_FLOOR (it is '${_rung2_floor}')"; }
[[ "$_rung2_floor" =~ ^[0-9]+$ ]] && (( 10#$_rung2_floor >= FLOOR_MINIMUM )) \
  || { _s4=0; echo "    RUNG2_CONFIGS_FLOOR='${_rung2_floor}' is below the pinned minimum of ${FLOOR_MINIMUM}"; }
# EQUALITY, not just `>=`. The workflow's own comment on this literal reads "KEEP IN LOCKSTEP
# WITH `DOPPLER_CONFIGS_FLOOR` … Three literals, one number", and a one-sided `>=` pins no
# such thing: RUNG2_CONFIGS_FLOOR could sit at 99 against a token_drift floor of 13 and every
# assertion here would agree, reddening the scratch-config half of the twice-daily sweep
# forever while the prose says the two numbers move together. Same one-sided-ratchet defect
# F2b closes for DOPPLER_CONFIGS_FLOOR, in the file that documents the lockstep.
[[ "$_rung2_floor" =~ ^[0-9]+$ ]] && [[ "$WF_FLOOR" =~ ^[0-9]+$ ]] && (( 10#$_rung2_floor == 10#$WF_FLOOR )) \
  || { _s4=0; echo "    RUNG2_CONFIGS_FLOOR='${_rung2_floor}' != DOPPLER_CONFIGS_FLOOR='${WF_FLOOR}' — the workflow's own comment calls these one number kept in lockstep"; }
# The comparison must READ the declared floor. A literal left in place beside a declared-and-
# unused env var is the decorative-declaration shape H2 exists to catch on the sibling step.
grep -qF 'RUNG2_CONFIGS_FLOOR' <<<"$SWEEP_RUN" \
  || { _s4=0; echo "    the probe's threshold does not read RUNG2_CONFIGS_FLOOR — the declaration is decorative"; }
grep -qE '_cfg_total[[:space:]]*<[[:space:]]*2[^0-9]' <<<"$SWEEP_RUN" \
  && { _s4=0; echo "    the probe still thresholds on a bare 2, which grades 2-of-13 as 'performed'"; }
if [[ "$_s4" == "1" ]]; then
  pass "the probe grades against a declared floor of ${_rung2_floor}, so a partial listing cannot publish 'performed'"
else
  fail "the scratch-config probe must grade its listing against a DECLARED floor, not against 2. At a threshold of 2 a credential seeing 2 of 13 configs publishes 'performed', files nothing, and the sweep reports 'no orphaned scratch Doppler config' — an answer by construction, from a listing that never covered 11 of the places the config could be"
fi

echo ""
echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
# ANTI-VACUITY FLOOR. Deleting every assertion call yields "0/0 passed" and exit 0,
# which test-all.sh (reading only the exit code) cannot distinguish from success.
# A FLOOR, not equality: adding a case must not require editing this line.
#
# SET AT THE CURRENT COUNT, not below it. At 20 against 22 running there were two free
# slots — measured: deleting the T15 AND T16 blocks, i.e. that PR's only in-run
# deliverable, reported "20/20 passed" and exit 0. A floor with slack licenses the
# deletion of exactly the assertions under review. Raise it when adding a case; that edit
# is the point, because it is what makes a REMOVAL visible in the diff.
#
# Raised 57 -> 60 with #7234's F5 (the for_each list IS the inventory) and C-a
# (`config = each.key`, never a literal), then 60 -> 61 with F4b (the inventory's name set
# never shrinks). 61 is the REALIZED `PASS + FAIL`, and the number
# in this comment and the number in the guard below MUST be the same number. They disagreed once
# (comment 46, guard 48, run 48/48), which is a ratchet whose own prose says the notch is
# lower than it is — a reader trusting the comment would have "raised" it downward.
if [[ "$((PASS + FAIL))" -lt 61 ]]; then
  echo "FATAL: only $((PASS + FAIL)) assertions ran; expected >= 61." >&2
  exit 1
fi
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
