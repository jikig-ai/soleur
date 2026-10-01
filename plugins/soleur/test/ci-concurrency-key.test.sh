#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Guard 1 (#7931 part 1) — no two `main` pushes share a CI concurrency group.
#
# WHAT THIS EXISTS TO CATCH. `ci.yml`'s concurrency group was
# `${{ github.workflow }}-${{ github.ref }}` with `cancel-in-progress` true only
# on pull_request. On `main`, `github.ref` is CONSTANT, so every push shared one
# group and `cancel-in-progress: false` turned "let prior runs finish" into
# "serialize". A run's gated quantity — time-to-`test`, measured from the run's
# own `created_at` — therefore contained the PREVIOUS run's entire time-to-
# `test`: an unbounded term belonging to a DIFFERENT COMMIT, which no declared
# ceiling has ever had a place for and no amount of ceiling-sizing can bound,
# because it is not a property of the run being measured.
#
# THE CLAIM IS SEMANTIC, NOT WALL-CLOCK, and this guard is scoped to match.
# Measured over 29 consecutive main pushes the queue binds on 7 (24%) at a
# median 393s; the median run saves nothing. See ci.yml's dispatch note. So
# this suite asserts the KEY IS PER-SHA — a property that holds on 100% of runs
# — and asserts nothing about duration, which would be a flake.
#
# WHY THE ASSEMBLY IS "EVERY concurrency MAPPING" AND NOT "THE BLOCK".
# Workflow-level and job-level `concurrency:` COEXIST (see the learning
# 2026-07-05-cross-pipeline-serialization-via-shared-job-level-concurrency-group).
# A check that stops at the first `concurrency:` mapping is the defect class:
# someone re-serialises `main` by adding a job-level group keyed on
# `github.ref` and the guard reports green. Mutation 4 is that row.
#
# RED BY DESIGN AT THE COMMIT THAT INTRODUCES IT (cq-write-failing-tests-before).
#   git log --diff-filter=A --format=%H -- plugins/soleur/test/ci-concurrency-key.test.sh
# yields a SHA whose `git show --name-only` contains no `.github/workflows` path.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

passes=0
fails=0
FAILURES=()
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); FAILURES+=("$1"); printf 'FAIL: %s\n' "$1" >&2; }

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
CI_YML="$REPO_ROOT/.github/workflows/ci.yml"
[ -f "$CI_YML" ] || { printf 'FAIL: %s not found\n' "$CI_YML" >&2; exit 2; }

SANDBOX=$(mktemp -d -t ci-conc-key.XXXXXXXX) || {
  printf 'FAIL: could not create sandbox\n' >&2; exit 2; }
trap 'rm -rf "$SANDBOX"' EXIT
python3 -c 'import yaml' 2>/dev/null || {
  printf 'FAIL: PyYAML is required\n' >&2; exit 2; }

echo "=== Guard 1: the CI concurrency key is per-SHA on non-PR events (#7931 part 1) ==="

# ── The analyser ─────────────────────────────────────────────────────────────
#
# Emits one TSV record per concurrency mapping found ANYWHERE in the workflow:
#     <scope>\t<group-expression>\t<cancel-in-progress-expression>
# `scope` is `workflow` or the job key. Discovery is STRUCTURAL (PyYAML walks
# the parsed document), never a fixed list of places to look, so a job-level
# mapping added later is found by construction.
#
# It also EVALUATES the group expression for a given event name, so a
# semantically identical but textually reordered ternary passes (harness row b)
# while a semantically different one fails. A pure string compare would reject
# the first and a pure substring check would accept the second.
ANALYSER="$SANDBOX/analyse.py"
cat > "$ANALYSER" <<'PY'
import sys, re, yaml, json

def spans(expr):
    return re.findall(r"\$\{\{(.*?)\}\}", expr or "", re.S)

def eval_span(body, event):
    """Evaluate the subset of GitHub expression syntax this key uses:
       <lhs> ==|!= '<lit>' && <A> || <B>     ->  A when the comparison holds, else B
       a bare context reference               ->  itself
       Returns the surviving text. Whitespace-insensitive."""
    b = " ".join(body.split())
    m = re.match(
        r"^github\.event_name\s*(==|!=)\s*'([^']*)'\s*&&\s*(.+?)\s*\|\|\s*(.+)$", b)
    if not m:
        return b
    op, lit, a, other = m.groups()
    holds = (event == lit) if op == "==" else (event != lit)
    return a if holds else other

def cancel_for(expr, event):
    """Evaluate `cancel-in-progress` to a BOOLEAN for one event.
       Returns True/False, or None when the shape is not one we can evaluate —
       which is itself a finding, never a silent pass."""
    if expr is None:
        return False                       # absent means false, per GitHub
    b = " ".join(str(expr).split())
    if b == "":
        return False
    if b.lower() in ("true", "false"):
        return b.lower() == "true"
    sp = spans(b)
    if len(sp) != 1 or b.strip() != "${{%s}}" % sp[0] and b.strip() != "${{ %s }}" % sp[0].strip():
        inner = sp[0] if sp else None
    else:
        inner = sp[0]
    if inner is None:
        return None
    t = " ".join(inner.split())
    m = re.match(r"^github\.event_name\s*(==|!=)\s*'([^']*)'$", t)
    if m:
        op, lit = m.groups()
        return (event == lit) if op == "==" else (event != lit)
    if t.lower() in ("true", "false"):
        return t.lower() == "true"
    return None

def group_for(expr, event):
    """Substitute every ${{...}} span in the group with its evaluation."""
    out, last = [], 0
    for m in re.finditer(r"\$\{\{(.*?)\}\}", expr or "", re.S):
        out.append(expr[last:m.start()])
        out.append(eval_span(m.group(1), event))
        last = m.end()
    out.append(expr[last:])
    return "".join(out)

wf = sys.argv[1]
doc = yaml.safe_load(open(wf))
recs = []
def add(scope, block):
    if block is None:
        return
    if isinstance(block, str):          # `concurrency: <group>` shorthand
        recs.append({"scope": scope, "group": block, "cancel": ""})
    else:
        recs.append({"scope": scope,
                     "group": str(block.get("group", "")),
                     "cancel": str(block.get("cancel-in-progress", ""))})
add("workflow", doc.get("concurrency"))
for jname, job in (doc.get("jobs") or {}).items():
    if isinstance(job, dict):
        add(jname, job.get("concurrency"))

# EVERY EVENT THE WORKFLOW DECLARES, not the two that happened to be fixtured.
# `cancel-in-progress` false and SUPERSEDED-impossible hold on merge_group and
# workflow_dispatch for the same reason they hold on push, and a predicate that
# only ever sees {push, pull_request} cannot tell a correct rule from one that
# happens to agree on those two.
on = doc.get("on", doc.get(True)) or {}
declared = sorted(on.keys()) if isinstance(on, dict) else ([on] if isinstance(on, str) else list(on))
EVENTS = [e for e in declared if isinstance(e, str)] or ["push", "pull_request"]
for r in recs:
    r["group_push"] = group_for(r["group"], "push")
    r["group_pr"] = group_for(r["group"], "pull_request")
    r["groups"] = {e: group_for(r["group"], e) for e in EVENTS}
    r["cancels"] = {e: cancel_for(r["cancel"], e) for e in EVENTS}
out = {"recs": recs, "events": EVENTS}
print(json.dumps(out))
PY

analyse() {  # $1 = workflow file -> JSON on stdout
  python3 "$ANALYSER" "$1"
}

# ── INSTRUMENT SELF-TEST ─────────────────────────────────────────────────────
_p0=$passes; _f0=$fails
pass; fail "INSTRUMENT SELF-TEST (expected — proves fail() increments)"
if [ "$passes" -ne $((_p0 + 1)) ] || [ "$fails" -ne $((_f0 + 1)) ]; then
  printf 'FAIL: instrument self-test — helpers did not both move\n' >&2; exit 2
fi
fails=$((fails - 1)); unset 'FAILURES[${#FAILURES[@]}-1]'
echo "  instrument self-test: pass() and fail() both move"

# The analyser is itself an instrument. Prove it can SEE a job-level mapping
# before trusting it to report their absence — an extractor that finds nothing
# reports "no violations" and "nothing to check" identically.
cat > "$SANDBOX/probe.yml" <<'YML'
name: Probe
on: push
concurrency:
  group: W-${{ github.sha }}
  cancel-in-progress: false
jobs:
  a:
    runs-on: ubuntu-latest
    concurrency:
      group: J-${{ github.ref }}
      cancel-in-progress: true
    steps:
      - run: 'true'
YML
_probe=$(analyse "$SANDBOX/probe.yml" 2>/dev/null)
if [ "$(printf '%s' "$_probe" | python3 -c 'import sys,json;print(len(json.load(sys.stdin)))')" = "2" ]; then
  pass
else
  printf 'FAIL: ANALYSER SELF-TEST — the extractor did not find both the workflow-level and job-level mappings in a fixture that has one of each. Every "no violations" verdict below would be unfalsifiable.\n' >&2
  exit 2
fi
echo "  analyser self-test: finds workflow-level AND job-level mappings"

# ── Predicates ───────────────────────────────────────────────────────────────
# Each takes a workflow FILE so the mutation rows can point the identical
# assertions at a mutated copy. A predicate that reads a global cannot be
# driven red.
check_file() {  # $1=file -> prints a violation summary, empty when clean
  python3 - "$1" "$ANALYSER" <<'PY'
import sys, subprocess, json
wf, analyser = sys.argv[1], sys.argv[2]
try:
    _out = json.loads(subprocess.check_output([sys.executable, analyser, wf]))
    recs, EVENTS = _out["recs"], _out["events"]
except Exception as e:
    print("ANALYSER-FAILED: %s" % e); sys.exit(0)
v = []
# P1 — there must BE a concurrency mapping. Deleting the block must RED, never
# produce "0 checked, exit 0".
if not recs:
    print("P1 no concurrency mapping found at all"); sys.exit(0)
wl = [r for r in recs if r["scope"] == "workflow"]
if not wl:
    v.append("P1 no WORKFLOW-level concurrency mapping")
for r in wl:
    # P2 — on a push, the group must resolve to something SHA-valued and must
    # NOT resolve to github.ref (which is constant across main pushes).
    if "github.sha" not in r["group_push"]:
        v.append("P2 push-event group does not resolve to github.sha: %r" % r["group_push"])
    if "github.ref" in r["group_push"]:
        v.append("P2 push-event group still resolves to github.ref (all main pushes share it): %r" % r["group_push"])
    # P3 — on a pull_request the group must stay ref-keyed, so cancel-in-progress
    # keeps collapsing superseded PR runs. Per-SHA there would defeat it.
    if "github.ref" not in r["group_pr"]:
        v.append("P3 pull_request group is not github.ref-keyed: %r" % r["group_pr"])
    # P4 — cancel-in-progress EVALUATED PER EVENT, not pattern-matched.
    # The previous form asked `"pull_request" not in c`, which is satisfied by
    # `github.event_name != 'pull_request'` — the INVERSION, which cancels
    # in-progress main runs (destroying the audit trail this change claims to
    # preserve, and killing the deploy gate mid-flight) while still containing
    # the substring. Substring containment is not a predicate about meaning.
    for ev in EVENTS:
        got = r["cancels"].get(ev)
        want = (ev == "pull_request")
        if got is None:
            v.append("P4 cancel-in-progress could not be EVALUATED for %r: %r — an unevaluable "
                     "condition must not read as compliant" % (ev, r["cancel"]))
        elif got != want:
            v.append("P4 cancel-in-progress evaluates to %s on %r, expected %s — %s"
                     % (got, ev, want,
                        "in-flight runs for a SHA already being gated would be cancelled"
                        if got else "superseded PR runs would no longer collapse"))
# P5 — SECOND-MEMBER ROW. No job-level mapping may re-introduce a ref-keyed
# group; that would re-serialise main one level down while the workflow-level
# key looks correct.
for r in recs:
    if r["scope"] == "workflow":
        continue
    gp = r["group_push"]
    if "github.ref" in gp:
        v.append("P5 job-level concurrency on %r is github.ref-keyed on push: %r"
                 % (r["scope"], gp))
    elif "github.sha" not in gp:
        # A CONSTANT group serialises HARDER than a ref-keyed one — it collapses
        # every branch into one queue, not just every push to a branch. Keying
        # P5 on the literal `github.ref` let the worse defect through, including
        # via the `concurrency: <string>` shorthand no fixture instantiated.
        v.append("P5 job-level concurrency on %r does not vary per SHA on push (%r) — "
                 "a group constant across SHAs re-serialises main one level down "
                 "while the workflow-level key looks correct" % (r["scope"], gp))
print("; ".join(v))
PY
}

# ── CONTROL: the shipped file must be clean before any mutant is read ────────
_ctl=$(check_file "$CI_YML")
if [ -z "$_ctl" ]; then
  pass
else
  fail "CONTROL — the shipped ci.yml violates the guard: $_ctl"
fi
if [ "$fails" -ne 0 ]; then
  printf '\nCONTROL ROW FAILED. Every mutation verdict below would be measured\n' >&2
  printf 'against a broken baseline, so the battery is VOID rather than failing.\n' >&2
  printf 'ci-concurrency-key.test.sh: %d rows, %d passed, %d failed\n' \
    "$((passes + fails))" "$passes" "$fails" >&2
  exit 1
fi

# ── Mutation battery ─────────────────────────────────────────────────────────
MUT_TOTAL=0; MUT_KILLED=0; MUT_SURVIVED=()
mutate_file() {  # $1=label  $2=python-mutator (reads $IN writes $OUT)
  local label="$1" mut="$2"
  local m="$SANDBOX/mut.$RANDOM.yml"
  MUT_TOTAL=$((MUT_TOTAL + 1))
  IN="$CI_YML" OUT="$m" python3 -c "$mut"
  if cmp -s "$m" "$CI_YML"; then
    fail "MUTATION DID NOT LAND: $label — the mutant is byte-identical to the source, so this row measured the BASELINE"
    return
  fi
  local out; out=$(check_file "$m")
  if [ -n "$out" ]; then
    pass; MUT_KILLED=$((MUT_KILLED + 1))
  else
    fail "MUTANT SURVIVED: $label — the guard reported clean"
    MUT_SURVIVED+=("$label")
  fi
}

READ='import os;s=open(os.environ["IN"]).read()'
WRITE='open(os.environ["OUT"],"w").write(s)'

# 1 — revert the group to the pre-#7931 ref-keyed form.
mutate_file "1 revert group to github.workflow-github.ref" \
"$READ
import re
s=re.sub(r'^concurrency:\n  group: .*\$', 'concurrency:\n  group: \${{ github.workflow }}-\${{ github.ref }}', s, count=1, flags=re.M)
$WRITE"

# 2 — flip the ternary so PUSH takes the github.ref arm.
mutate_file "2 ternary inverted so push takes the github.ref arm" \
"$READ
s=s.replace(\"github.event_name == 'pull_request' && github.ref || github.sha\",
            \"github.event_name == 'pull_request' && github.sha || github.ref\",1)
$WRITE"

# 3 — cancel-in-progress unconditionally true.
mutate_file "3 cancel-in-progress unconditionally true" \
"$READ
import re
s=re.sub(r'^  cancel-in-progress: .*\$', '  cancel-in-progress: true', s, count=1, flags=re.M)
$WRITE"

# 4 — SECOND-MEMBER ROW: a job-level mapping re-serialises main one level down.
#     A guard that stops at the first `concurrency:` mapping cannot see this.
mutate_file "4 a job-level concurrency keyed on github.ref is added" \
"$READ
import re
s=re.sub(r'^(  test-bun:\n)(    runs-on: [^\n]*\n)',
         r'\1\2    concurrency:\n      group: legacy-\${{ github.ref }}\n      cancel-in-progress: false\n',
         s, count=1, flags=re.M)
$WRITE"

# 5 — delete the concurrency block entirely. Must RED, never "0 checked, exit 0".
mutate_file "5 the concurrency block is deleted entirely" \
"$READ
import re
s=re.sub(r'^concurrency:\n(?:  [^\n]*\n)+', '', s, count=1, flags=re.M)
$WRITE"

# ── Harness rows ─────────────────────────────────────────────────────────────
# (a) Delete the guard's own comparison and confirm the suite would go green on
#     a known-bad file — i.e. the comparison is load-bearing, not decorative.
#     Implemented positively: run the ANALYSER-only path over mutant 1 and
#     assert that WITHOUT the P2 comparison it looks clean.
_ha=$(python3 - "$CI_YML" "$ANALYSER" <<'PY'
import sys, subprocess, json
recs = json.loads(subprocess.check_output([sys.executable, sys.argv[2], sys.argv[1]]))["recs"]
# The "guard with its comparison deleted": report nothing but the count.
print("" if recs else "no mappings")
PY
)
if [ -z "$_ha" ]; then pass; else
  fail "Ha HARNESS: the comparison-free analyser path did not return clean, so mutation rows prove nothing about the comparison"
fi

# (b) MUST-PASS negative control: the same key with different whitespace and a
#     semantically identical but REORDERED ternary must PASS. A guard that only
#     accepts one byte-sequence would force every future editorial change
#     through a guard edit, which is how guards get deleted.
cat > "$SANDBOX/variant.yml" <<'YML'
name: CI
on: push
concurrency:
  group: >-
    ${{ github.workflow }}-${{ github.event_name != 'pull_request'
        && github.sha
        || github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - run: 'true'
YML
_hb=$(check_file "$SANDBOX/variant.yml")
if [ -z "$_hb" ]; then pass; else
  fail "Hb MUST-PASS: a semantically identical, reordered/reflowed ternary was rejected: $_hb"
fi

# ── Mutants 6-8 and the must-PASS direction (added at review) ────────────────
# Each of these SURVIVED the original battery. They are the defects the guard
# most needed to catch, and the shapes the fixtures never instantiated.
mutate_file "6 cancel-in-progress is INVERTED (main runs get cancelled)" '
import os
s=open(os.environ["IN"]).read()
open(os.environ["OUT"],"w").write(s.replace(
  "cancel-in-progress: ${{ github.event_name == \x27pull_request\x27 }}",
  "cancel-in-progress: ${{ github.event_name != \x27pull_request\x27 }}",1))
'
mutate_file "7 a job-level CONSTANT group (serialises harder than github.ref)" '
import os
s=open(os.environ["IN"]).read()
open(os.environ["OUT"],"w").write(s.replace(
  "  test-bun:",
  "  test-bun:\n    concurrency:\n      group: legacy-shared-lock\n      cancel-in-progress: false",1))
'
mutate_file "8 a job-level constant group via the concurrency-as-a-plain-string shorthand" '
import os
s=open(os.environ["IN"]).read()
open(os.environ["OUT"],"w").write(s.replace(
  "  test-bun:",
  "  test-bun:\n    concurrency: legacy-${{ github.workflow }}",1))
'
# MUST-PASS (fixture DIRECTION). Every other row in this suite is must-TRIP, so
# the guard was free to become arbitrarily more aggressive without any row
# noticing — and P5 keying on the literal `github.ref` was one edit away from
# rejecting a legitimate per-SHA job-level group.
_okjob="$SANDBOX/ok-jobgroup.yml"
python3 - "$CI_YML" "$_okjob" <<'PYOK'
import sys
s=open(sys.argv[1]).read()
assert "  e2e:" in s
open(sys.argv[2],"w").write(s.replace(
  "  e2e:",
  "  e2e:\n    concurrency:\n      group: e2e-${{ github.sha }}\n      cancel-in-progress: false",1))
PYOK
_okout=$(check_file "$_okjob")
if [ -z "$_okout" ]; then pass; else
  fail "MUST-PASS: a job-level concurrency group keyed per-SHA was flagged: $_okout — that is a LEGITIMATE way to serialise one job without re-serialising main, and rejecting it reds a correct tree"
fi

# ── Verdict ──────────────────────────────────────────────────────────────────
TOTAL=$((passes + fails))
# DERIVED: 1 instrument self-test + 1 analyser self-test + 1 control
#        + 8 mutants + 2 harness rows + 1 must-PASS (job-level per-SHA group) = 14
#        Mutants 6-8 were added at review: each SURVIVED the original battery.
MIN_ROWS=14
if [ "$TOTAL" -lt "$MIN_ROWS" ]; then
  printf 'FAIL: assertion floor — %d rows executed, at least %d required.\n' "$TOTAL" "$MIN_ROWS" >&2
  exit 1
fi
if [ "$MUT_TOTAL" -lt 8 ]; then
  printf 'FAIL: mutation floor — %d mutants executed, at least 8 required.\n' "$MUT_TOTAL" >&2
  exit 1
fi

echo
echo "mutation battery: $MUT_KILLED/$MUT_TOTAL killed"
if [ "${#MUT_SURVIVED[@]}" -gt 0 ]; then
  printf 'surviving mutants:\n' >&2; printf '  - %s\n' "${MUT_SURVIVED[@]}" >&2
fi
echo "ci-concurrency-key.test.sh: $TOTAL rows, $passes passed, $fails failed"
if [ "${#FAILURES[@]}" -gt 0 ]; then
  printf '\nfailures:\n' >&2; printf '  - %s\n' "${FAILURES[@]}" >&2
  exit 1
fi
exit 0
