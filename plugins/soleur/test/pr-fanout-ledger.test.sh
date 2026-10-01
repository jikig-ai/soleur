#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Guard 2 — the PR fan-out ledger (ADR-216 addendum 2026-09-14).
#
# PROPERTY. Every workflow that fires on a pull-request PUSH has a row in
# scripts/pr-fanout-ledger.txt that names its consequence, bounds its DECLARED
# job count, and records its `paths` and `cancel` shape — and no ledger row
# outlives its workflow. The set of firing workflows is a generator: a new file
# with `on: pull_request` costs runner slots on every push to every open PR,
# and nothing else in the tree notices. This suite is the thing that notices.
#
# ASSEMBLY. The chokepoint is the PyYAML enumerator below over
# `${PR_FANOUT_WORKFLOWS_DIR:-.github/workflows}/*.yml`. The column
# definitions live ONCE, in the ledger header (scripts/pr-fanout-ledger.txt);
# the enumerator implements them and this comment only names what it reaches:
#   - direct triggers: `on.pull_request` / `on.pull_request_target` (dict, list
#     or string form of `on:`; PyYAML parses a bare `on` key as True), unless
#     `types:` is present and omits `synchronize`;
#   - TRANSITIVE triggers: `on.workflow_run` naming a firing workflow's `name:`
#     with no `branches`/`branches-ignore` filter fires once per PR push too
#     (fix-constraints-stage-b.yml), so it is enumerated to a fixpoint;
#   - `jobs`: `len(jobs)`, where a `uses: ./.github/workflows/<callee>` job
#     counts the callee's declared jobs (it dispatches them), not 1;
#   - `cancel`: yes only when the enumerator can PROVE it — cancel form is
#     `true` or ci.yml's `${{ github.event_name == 'pull_request' }}` ternary
#     AND the group is keyed on a per-PR ref AND carries no per-run/per-SHA
#     token (`github.sha`, `run_id`, `head.sha`, ... — a group that mixes both
#     never collides across pushes, so it never cancels). Any other
#     cancel-in-progress spelling fails closed (A4c);
#   - A6: every block using the ternary form must carry ci.yml's group
#     expression byte-for-byte, so a copy regressed to a per-ref-only group
#     (the #7931 class on a `push: main` arm) cannot hide behind cancel=yes.
#
# BOTH SIDES ARE DERIVED INDEPENDENTLY. The real set never comes from the
# ledger's own row count — see Part B row 11 in the plan (a one-time harness
# verification: wiring A1 to the ledger's own set turns row 1 green).
#
# PART A runs against the tree. PART B (mutation battery) re-invokes Part A
# against a FRESH temp copy per mutant, with the assertion floor disabled, and
# requires each mutant to fail on the NAMED row. Every Part A row is driven RED
# at least once there. Mutants name live workflows (ci.yml, pr-quality-guards,
# secret-scan, infra-validation, cla) on purpose: a rename reds the HARNESS
# (assert_landed) rather than the guard, which is the loud direction.
#
# Env overrides: PR_FANOUT_WORKFLOWS_DIR, PR_FANOUT_LEDGER, PR_FANOUT_PARTS
# (default AB; children run A), PR_FANOUT_MIN_CASES (the A7 floor; children
# run 0).
#
# Auto-discovered by scripts/test-all.sh (`plugins/soleur/test/*.test.sh`),
# `test-scripts` shard. Requires python3 + PyYAML (as the drift suite and
# c4-count-parity already do).
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

SUITE_TMP="$(mktemp -d -t pr-fanout-suite.XXXXXXXX -p "$TMPDIR")" || {
  echo "FAIL: mktemp -d failed" >&2; exit 2; }
# Installed BEFORE test-helpers.sh is sourced so the helpers compose their own
# sandbox cleanup onto it rather than replacing it. Every per-mutant copy in
# Part B is minted under SUITE_TMP, so this one rm removes them all.
trap 'rm -rf "$SUITE_TMP"' EXIT

# shellcheck source=plugins/soleur/test/test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"   # PASS / FAIL / SKIPPED counters + print_results
# test-helpers.sh opens with `set -euo pipefail`; this suite is accumulate-then-
# exit (a failing lookup must print a FAIL line, not abort before A7), so errexit
# is switched back off right after the source. Neither sibling battery sources
# the helpers; this one does, for print_results only.
set +e

python3 -c 'import yaml' 2>/dev/null || { echo "FAIL: PyYAML is required" >&2; exit 2; }

WF_DIR="${PR_FANOUT_WORKFLOWS_DIR:-$REPO_ROOT/.github/workflows}"
LEDGER="${PR_FANOUT_LEDGER:-$REPO_ROOT/scripts/pr-fanout-ledger.txt}"
PARTS="${PR_FANOUT_PARTS:-AB}"
SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
A0_FLOOR=15

# CASES is incremented at every CALL SITE, never inside pass()/fail(), so the A7
# floor moves independently of the verdict machinery it backstops (ADR-193).
CASES=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() {
  echo "  FAIL: $1"
  [[ $# -ge 2 ]] && echo "    expected: $2"
  [[ $# -ge 3 ]] && echo "    actual:   $3"
  FAIL=$((FAIL + 1))
}
# Instrument self-test: drive both helpers once and require both counters to
# move, reported by a direct exit. A neutered fail() that takes the pass branch
# leaves CASES and the A7 floor intact, so nothing else here can see it.
_p0=$PASS; _f0=$FAIL
pass "instrument" >/dev/null; fail "instrument" >/dev/null
if [[ "$PASS" -ne $((_p0 + 1)) || "$FAIL" -ne $((_f0 + 1)) ]]; then
  echo "FAIL: instrument self-test — pass()/fail() did not move their counters" >&2
  exit 2
fi
PASS=$_p0; FAIL=$_f0

# The accepted spellings and group shapes are emitted by the enumerator itself
# (SPEC records) so the messages below cannot drift from the scorer.
ACCEPTED_SPELLINGS=""
GROUP_SHAPES=""

# ── The enumerator ───────────────────────────────────────────────────────────
# Emits one TSV record per *.yml / *.yaml in WF_DIR:
#   SPEC spellings <text>                                 the accepted cancel-in-progress spellings
#   SPEC shapes <text>                                    the accepted per-PR group shapes
#   FIRE <file> <jobs> <paths> <cancel> <bad-forms> <tgroup>  a firing workflow
#   SYM  <file>                                           a symlink (rejected via lstat)
#   ERR  <file> <message>                                 unparseable / not a mapping
# <bad-forms> is `-` or a `|`-joined list of `<scope>=<expr>` for every
# cancel-in-progress value that is none of the accepted spellings. <tgroup> is
# `-` or the US(0x1f)-joined group expressions of every block using the ternary
# form (A6 compares them to ci.yml's; `|` cannot be the joiner, the idiom
# itself contains `||`).
enumerate() { # <dir> -> TSV on stdout
  PR_FANOUT_ENUM_DIR="$1" python3 - <<'PY'
import os, re, sys, yaml
d = os.environ["PR_FANOUT_ENUM_DIR"]
TERNARY = "${{ github.event_name == 'pull_request' }}"
SPELLINGS = "true | false | " + TERNARY
SHAPES = ("github.ref | github.head_ref | github.ref_name | github.event.number"
          " | github.event.pull_request.number | github.event.pull_request.head.ref")
GROUP_RE = re.compile(r"github\.(ref|head_ref|ref_name|event\.number|event\.pull_request\.number|event\.pull_request\.head\.ref)\b")
# A per-run / per-SHA token anywhere in the group makes the key unique per
# push, so the group never collides and a superseded push is never cancelled,
# whatever else the expression mentions.
PERSHA_RE = re.compile(r"github\.(sha|run_id|run_number|run_attempt|event\.pull_request\.head\.sha|event\.workflow_run\.head_sha|event\.after)\b")
# ci.yml's idiom `event_name == 'pull_request' && <per-PR ref> || github.sha` keys
# per-ref ON pull_request and per-SHA elsewhere; the sha arm is not a per-run
# token on the PR path, so it is folded to its ref arm before the check.
TERNARY_GROUP_RE = re.compile(r"github\.event_name == 'pull_request' && (github\.[A-Za-z_.]+) \|\| github\.sha")

def norm_on(on):
    if on is None:
        return {}
    if isinstance(on, str):
        return {on: None}
    if isinstance(on, list):
        return {k: None for k in on}
    if isinstance(on, dict):
        return on
    return {}

def direct(on):
    for k in ("pull_request", "pull_request_target"):
        if k not in on:
            continue
        v = on[k] or {}
        if not isinstance(v, dict):
            v = {}
        t = v.get("types")
        if t is None:
            return True, v
        if isinstance(t, str):
            t = [t]
        if isinstance(t, list) and "synchronize" in t:
            return True, v
    return False, None

def chained(on, firing_names):
    # on.workflow_run naming a firing workflow with no branch filter fires
    # once per run of that workflow, i.e. once per PR push.
    v = on.get("workflow_run")
    if not isinstance(v, dict):
        return False
    if "branches" in v or "branches-ignore" in v:
        return False
    w = v.get("workflows") or []
    if isinstance(w, str):
        w = [w]
    return any(str(x) in firing_names for x in w)

def cancel_form(v):
    if v is None or v is False:
        return "false"
    if v is True:
        return "true"
    s = re.sub(r"\s+", " ", str(v).strip())
    if s.lower() in ("true", "false"):
        return s.lower()
    return s

docs = {}
out = ["SPEC\tspellings\t" + SPELLINGS, "SPEC\tshapes\t" + SHAPES]
for f in sorted(os.listdir(d)):
    if not (f.endswith(".yml") or f.endswith(".yaml")):
        continue
    p = os.path.join(d, f)
    if os.path.islink(p):
        out.append("SYM\t%s" % f)
        continue
    if not os.path.isfile(p):
        continue
    try:
        with open(p) as fh:
            doc = yaml.safe_load(fh)
    except Exception as e:  # noqa: BLE001 - fail closed on any parse error
        out.append("ERR\t%s\t%s" % (f, str(e).replace("\n", " ")[:160]))
        continue
    if doc is None:
        continue
    if not isinstance(doc, dict):
        out.append("ERR\t%s\tdocument is not a mapping" % f)
        continue
    docs[f] = doc

firing = {}   # file -> trigger dict (paths live there) or {} for chained
for f, doc in docs.items():
    ok, trig = direct(norm_on(doc.get("on", doc.get(True))))
    if ok:
        firing[f] = trig
changed = True
while changed:
    changed = False
    names = {str(docs[f].get("name", "")) for f in firing}
    for f, doc in docs.items():
        if f in firing:
            continue
        if chained(norm_on(doc.get("on", doc.get(True))), names):
            firing[f] = {}
            changed = True

def job_count(doc):
    jobs = doc.get("jobs") or {}
    if not isinstance(jobs, dict):
        return 0
    n = 0
    for j in jobs.values():
        uses = j.get("uses") if isinstance(j, dict) else None
        callee = None
        if isinstance(uses, str) and uses.startswith("./"):
            callee = docs.get(os.path.basename(uses.split("@", 1)[0]))
        if isinstance(callee, dict) and isinstance(callee.get("jobs"), dict):
            n += len(callee["jobs"])
        else:
            n += 1
    return n

for f in sorted(firing):
    doc, trig = docs[f], firing[f]
    jobs = doc.get("jobs") or {}
    if not isinstance(jobs, dict):
        jobs = {}
    paths = "yes" if ("paths" in trig or "paths-ignore" in trig) else "no"
    blocks = []
    if doc.get("concurrency") is not None:
        blocks.append(("workflow", doc["concurrency"]))
    for jn, j in jobs.items():
        if isinstance(j, dict) and j.get("concurrency") is not None:
            blocks.append((str(jn), j["concurrency"]))
    cancel = "no"
    bad, tgroups = [], []
    for scope, c in blocks:
        if isinstance(c, dict):
            grp = re.sub(r"\s+", " ", str(c.get("group", "")).strip())
            form = cancel_form(c.get("cancel-in-progress"))
        else:
            grp = str(c)          # string shorthand: group only, cancel defaults false
            form = "false"
        if form not in ("true", "false", TERNARY):
            bad.append("%s=%s" % (scope, form))
            continue
        if form == TERNARY:
            tgroups.append(grp)
        folded = TERNARY_GROUP_RE.sub(r"\1", grp)
        if form != "false" and GROUP_RE.search(folded) and not PERSHA_RE.search(folded):
            cancel = "yes"
    out.append("FIRE\t%s\t%d\t%s\t%s\t%s\t%s" % (
        f, job_count(doc), paths, cancel,
        "|".join(bad) if bad else "-", "\x1f".join(tgroups) if tgroups else "-"))
sys.stdout.write("\n".join(out) + "\n")
PY
}

# ── Part A ───────────────────────────────────────────────────────────────────
run_part_a() {
  echo "=== PART A: ledger vs tree ($WF_DIR) ==="
  local enum="$SUITE_TMP/enum.$$.tsv" rc=0
  enumerate "$WF_DIR" > "$enum" || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    echo "FAIL: enumerator exited $rc over $WF_DIR — fail closed" >&2
    exit 1
  fi
  ACCEPTED_SPELLINGS="$(awk -F'\t' '$1=="SPEC" && $2=="spellings"{print $3}' "$enum")"
  GROUP_SHAPES="$(awk -F'\t' '$1=="SPEC" && $2=="shapes"{print $3}' "$enum")"

  # A-sym / A-err: a symlinked or unparseable workflow is never silently skipped.
  local f msg
  while IFS=$'\t' read -r f; do
    CASES=$((CASES + 1))
    fail "A-sym $f is a symlink — workflows are read via lstat and a link is rejected; replace it with the real file"
  done < <(awk -F'\t' '$1=="SYM"{print $2}' "$enum")
  while IFS=$'\t' read -r f msg; do
    CASES=$((CASES + 1))
    fail "A-err $f could not be parsed ($msg) — fail closed: fix the YAML, the enumerator cannot score it"
  done < <(awk -F'\t' '$1=="ERR"{print $2"\t"$3}' "$enum")

  # A0 — vacuity floor on the ENUMERATOR, a direct exit. `found` is a computed
  # count (deliberately not a counter this file increments, so it sits outside
  # scripts/guard-vacuity-floor.test.sh's population); an unreadable tree must
  # never reach print_results at all.
  local found
  found="$(awk -F'\t' '$1=="FIRE"' "$enum" | wc -l | tr -d '[:space:]')"
  if ! [[ "$found" =~ ^[0-9]+$ ]]; then
    echo "FAIL: A0 enumerator count is not a number: '$found'" >&2
    exit 1
  fi
  if [[ "$found" -lt "$A0_FLOOR" ]]; then
    echo "FAIL: A0 vacuity floor: $found firing workflows found in $WF_DIR ($found < $A0_FLOOR) — the tree is unreadable or the enumerator broke; this is not a clean ledger" >&2
    exit 1
  fi
  CASES=$((CASES + 1))
  pass "A0 enumerator found $found firing workflows ($found >= $A0_FLOOR)"

  # A-parse — every non-comment ledger line has exactly 5 TAB-separated fields.
  if [[ ! -f "$LEDGER" ]]; then
    echo "FAIL: ledger $LEDGER not found" >&2
    exit 1
  fi
  local rows="$SUITE_TMP/rows.$$.tsv" ln nf
  # Comment lines are leading-# only; blank lines are ignored.
  awk -F'\t' '!/^#/ && NF>0 {print NR"\t"NF"\t"$0}' "$LEDGER" > "$rows"
  while IFS=$'\t' read -r ln nf _rest; do
    CASES=$((CASES + 1))
    if [[ "$nf" -eq 5 ]]; then
      pass "A-parse line $ln: 5 TAB-separated columns"
    else
      fail "A-parse line $ln: expected 5 TAB-separated columns, got $nf (spaces are not separators)" \
        "<workflow><TAB><jobs><TAB><paths><TAB><cancel><TAB><consequence>" \
        "$(sed -n "${ln}p" "$LEDGER")"
    fi
  done < "$rows"

  # Ledger lookups keyed by workflow name (only well-formed rows).
  local lrows="$SUITE_TMP/ledger-rows.$$.tsv"
  awk -F'\t' '!/^#/ && NF==5' "$LEDGER" > "$lrows"

  # A1 — every firing workflow has a row. One summary line prints both counts
  # (AC12); each missing file is its own FAIL that prints the ENUMERATOR'S OWN
  # reading of the file as the row to add (jobs/paths/cancel already derived),
  # so the reader supplies only the consequence.
  local firing ledgered missing=0 ej ep ec
  firing="$found"
  ledgered="$(wc -l < "$lrows" | tr -d '[:space:]')"
  while IFS=$'\t' read -r f ej ep ec; do
    if ! awk -F'\t' -v w="$f" '$1==w{found=1} END{exit !found}' "$lrows"; then
      missing=$((missing + 1))
      CASES=$((CASES + 1))
      fail "A1 $f fires on a PR push but has no ledger row in $(basename "$LEDGER") — three honest exits: (1) add the row ${f}<TAB>${ej}<TAB>${ep}<TAB>${ec}<TAB><consequence: what breaks if it does not run on every PR push>; (2) drop pull_request from its on: block (or add branches: to its workflow_run); (3) gate types: to opened/closed only"
    fi
  done < <(awk -F'\t' '$1=="FIRE"{print $2"\t"$3"\t"$4"\t"$5}' "$enum")
  CASES=$((CASES + 1))
  if [[ "$missing" -eq 0 ]]; then
    pass "A1 $firing firing / $ledgered ledgered — every firing workflow has a row"
  else
    fail "A1 $firing firing / $ledgered ledgered — $missing firing workflow(s) have no row"
  fi

  # ci.yml's ternary group is the reference every other ternary block must equal.
  local ci_tgroup
  ci_tgroup="$(awk -F'\t' '$1=="FIRE" && $2=="ci.yml"{print $7; exit}' "$enum")"

  # A2..A6 — per row, a fixed 8 cases each (A-parse above, A2, A3, A4, A4b, A4c,
  # A5, A6) so the A7 floor derives from the row count.
  local w jobs paths cancel cons declared fpaths fcancel bad tgroup nwords g
  while IFS=$'\t' read -r w jobs paths cancel cons; do
    # A2 — the row names a file that exists AND fires.
    CASES=$((CASES + 1))
    if ! awk -F'\t' -v w="$w" '$1=="FIRE" && $2==w{found=1} END{exit !found}' "$enum"; then
      if [[ -e "$WF_DIR/$w" ]]; then
        fail "A2 row for $w but $w does not fire on a PR push — delete the row, or restore the trigger"
      else
        fail "A2 row for $w but $WF_DIR/$w does not exist — delete the row, or restore the file"
      fi
      continue
    fi
    pass "A2 $w exists and fires"
    IFS=$'\t' read -r declared fpaths fcancel bad tgroup < <(awk -F'\t' -v w="$w" '$1=="FIRE" && $2==w{print $3"\t"$4"\t"$5"\t"$6"\t"$7; exit}' "$enum")

    # A3 — declared jobs <= the row (the row is a CEILING).
    CASES=$((CASES + 1))
    if [[ "$jobs" =~ ^[0-9]+$ ]] && [[ "$declared" -le "$jobs" ]]; then
      pass "A3 $w: $declared declared <= row $jobs"
    else
      fail "A3 $w: $declared declared, row allows $jobs — fold the new job into an existing job as a step (as #8149 did), or raise the row and name why; do not delete the job to satisfy the ledger"
    fi

    # A4 — paths flag equality.
    CASES=$((CASES + 1))
    if [[ "$paths" == "$fpaths" ]]; then
      pass "A4 $w: paths=$paths"
    else
      fail "A4 $w: row says paths=$paths, the trigger says paths=$fpaths — edit the row or the file, and name why"
    fi

    # A4b — cancel flag equality (form AND group shape AND no per-run token).
    CASES=$((CASES + 1))
    if [[ "$cancel" == "$fcancel" ]]; then
      pass "A4b $w: cancel=$cancel"
    else
      fail "A4b $w: row says cancel=$cancel, the file says cancel=$fcancel — cancel=yes needs ALL of: the form (cancel-in-progress in: $ACCEPTED_SPELLINGS, not false), a group keyed on one of: $GROUP_SHAPES, and no per-run token in the group (github.sha, run_id, head.sha, ...); edit the row or the file, and name why"
    fi

    # A4c — an unrecognised cancel-in-progress spelling fails closed.
    CASES=$((CASES + 1))
    if [[ "$bad" == "-" ]]; then
      pass "A4c $w: every cancel-in-progress value is an accepted spelling"
    else
      fail "A4c $w: cancel-in-progress '$bad' is not an accepted spelling — accepted verbatim: $ACCEPTED_SPELLINGS; the enumerator cannot score it either way"
    fi

    # A5 — consequence >= 4 words, and a cancel=no row says why (the header's
    # definition: "or why cancel is no").
    CASES=$((CASES + 1))
    nwords="$(printf '%s' "$cons" | wc -w | tr -d '[:space:]')"
    if [[ "$nwords" -lt 4 ]]; then
      fail "A5 $w: consequence has $nwords word(s), need >= 4 — a row with no consequence is a row that should not exist"
    elif [[ "$cancel" == "no" ]] && ! printf '%s' "$cons" | grep -qi 'no cancel'; then
      fail "A5 $w: cancel=no but the consequence never says why (expected the phrase 'no cancel: <reason>') — a superseded push leaves this run on the pool; name the state it holds or the rollout it awaits"
    else
      pass "A5 $w: consequence has $nwords words"
    fi

    # A6 — every block using ci.yml's ternary form carries ci.yml's GROUP too.
    # A4b scores the group semantically, so a copy regressed to a per-ref-only
    # group with the ternary (the #7931 class on a push: main arm) would still
    # read cancel=yes; this pins the replicated block to its source.
    CASES=$((CASES + 1))
    if [[ "$tgroup" == "-" ]]; then
      pass "A6 $w: no ternary-form concurrency block (n/a)"
    elif [[ -z "$ci_tgroup" || "$ci_tgroup" == "-" ]]; then
      fail "A6 $w: uses the ternary cancel form but ci.yml's reference group could not be read — fail closed"
    else
      local a6_ok=1
      # printf '%s\n': without the trailing newline `read` skips the final line
      # and the comparison never runs (caught by B6f on first run).
      local a6_n=0
      while IFS= read -r g; do a6_n=$((a6_n + 1)); [[ "$g" == "$ci_tgroup" ]] || a6_ok=0; done < <(printf '%s\n' "$tgroup" | tr '\037' '\n')
      [[ "$a6_n" -ge 1 ]] || a6_ok=0
      if [[ "$a6_ok" -eq 1 ]]; then
        pass "A6 $w: ternary-form block carries ci.yml's group verbatim"
      else
        fail "A6 $w: ternary-form concurrency block does not carry ci.yml's group" "$ci_tgroup" "$tgroup"
      fi
    fi
  done < "$lrows"
}

# ── Part B — mutation battery ────────────────────────────────────────────────
# Each mutant gets its OWN fresh copy of the workflows dir + ledger, so a file
# deleted in one row cannot leak into the next. Each mutation is asserted to
# have LANDED (diff against the pristine copy) before the child is read, so a
# no-op sed can never score as "caught".
PRISTINE=""
CONTROL_OUT=""
CONTROL_CASES=""

make_copy() { # -> prints the copy dir; workflows in <dir>/workflows, ledger at <dir>/ledger.txt
  local m
  m="$(mktemp -d -t pr-fanout.XXXXXXXX -p "$SUITE_TMP")" || return 1
  mkdir -p "$m/workflows" || return 1
  cp -r "$WF_DIR"/. "$m/workflows/" || return 1
  cp "$LEDGER" "$m/ledger.txt" || return 1
  printf '%s\n' "$m"
}

run_child() { # <copy-dir> <out-file> [MIN_CASES] -> rc
  local m="$1" out="$2" mc="${3:-0}" rc=0
  assert_fixture_dir "$m"; assert_fixture_dir "$out"   # P1b: both operands provably absolute before the redirect
  PR_FANOUT_PARTS=A PR_FANOUT_MIN_CASES="$mc" \
  PR_FANOUT_WORKFLOWS_DIR="$m/workflows" PR_FANOUT_LEDGER="$m/ledger.txt" \
    bash "$SELF" > "$out" 2>&1 || rc=$?
  return "$rc"
}

assert_landed() { # <row> <copy-dir>
  local row="$1" m="$2"
  CASES=$((CASES + 1))
  if diff -rq "$PRISTINE" "$m" > /dev/null 2>&1; then
    fail "$row mutation did NOT land (copy identical to pristine) — the harness, not the guard, is broken"
    return 1
  fi
  pass "$row mutation landed"
}

# assert_red <row> <rc> <out> <grep-ERE-1> [<grep-ERE-2> ...]
assert_red() {
  local row="$1" rc="$2" out="$3"; shift 3
  local pat
  CASES=$((CASES + 1))
  if [[ "$rc" -eq 0 ]]; then
    fail "$row child exited 0 — mutant SURVIVED" "non-zero exit" "$(tail -5 "$out")"
    return
  fi
  for pat in "$@"; do
    if ! grep -Eq -- "$pat" "$out"; then
      fail "$row child failed but not on the named row" "output matching /$pat/" "$(grep -E 'FAIL' "$out" | head -5)"
      return
    fi
  done
  pass "$row caught (rc=$rc): $(grep -E -m1 -- "$1" "$out")"
}

# assert_green <row> <rc> <out> <grep-ERE>
assert_green() {
  local row="$1" rc="$2" out="$3" pat="$4"
  CASES=$((CASES + 1))
  if [[ "$rc" -ne 0 ]]; then
    fail "$row child exited $rc — a must-PASS mutant went red" "exit 0" "$(grep -E 'FAIL' "$out" | head -5)"
    return
  fi
  if ! grep -Eq -- "$pat" "$out"; then
    fail "$row child green but the row's PASS line is missing" "output matching /$pat/" "$(grep -E 'PASS: A[13] ' "$out" | head -3)"
    return
  fi
  pass "$row green: $(grep -E -m1 -- "$pat" "$out")"
}

# red_mutant <row> <copy> <grep-ERE-1> [<grep-ERE-2> ...] — landed -> child -> red.
red_mutant() {
  local row="$1" m="$2"; shift 2
  local out="$m/child.out" rc=0
  assert_landed "$row" "$m" || return 0
  run_child "$m" "$out" || rc=$?
  assert_red "$row" "$rc" "$out" "$@"
}

# Rewrites <copy>/workflows/<file> through PyYAML with a one-line python edit
# applied to the parsed document `doc` (MUT is passed via env, never
# interpolated into the heredoc).
mutate_yaml() { # <copy> <file> <python-statement>
  MUT_FILE="$1/workflows/$2" MUT="$3" python3 - <<'PY'
import os, yaml
p = os.environ["MUT_FILE"]
with open(p) as fh:
    doc = yaml.safe_load(fh)
exec(os.environ["MUT"])
with open(p, "w") as fh:
    yaml.safe_dump(doc, fh, sort_keys=False, width=1000)
PY
}

ledger_row() { # <copy> <workflow> -> the row line
  awk -F'\t' -v w="$2" '!/^#/ && $1==w' "$1/ledger.txt"
}

run_part_b() {
  echo "=== PART B: mutation battery ==="
  local m out rc lno
  PRISTINE="$(make_copy)" || { echo "FAIL: could not build the pristine copy" >&2; exit 1; }
  assert_fixture_dir "$PRISTINE"

  # B0 — control: an unmutated copy is green and prints the A1 summary.
  m="$(make_copy)"; assert_fixture_dir "$m"; out="$m/child.out"; rc=0
  run_child "$m" "$out" || rc=$?
  CASES=$((CASES + 1))
  if [[ "$rc" -eq 0 ]] && grep -Eq '^  PASS: A1 [0-9]+ firing / [0-9]+ ledgered' "$out"; then
    CONTROL_OUT="$(grep -E '^  PASS: A1 [0-9]+ firing / [0-9]+ ledgered' "$out")"
    CONTROL_CASES="$(sed -nE 's/^A7 ([0-9]+) assertions ran.*/\1/p' "$out" | head -1)"
    pass "B0 control copy is green (${CONTROL_OUT#  PASS: }; $CONTROL_CASES cases)"
  else
    fail "B0 control copy is NOT green (rc=$rc) — every mutant below is uninterpretable" "rc 0 + A1 summary" "$(grep -E 'FAIL' "$out" | head -5)"
    return
  fi

  # Snapshot numbers the mutants are derived from (never copied from the plan).
  local ci_declared ci_allowed
  ci_declared="$(enumerate "$WF_DIR" | awk -F'\t' '$1=="FIRE" && $2=="ci.yml"{print $3}')"
  ci_allowed="$(ledger_row "$PRISTINE" ci.yml | cut -f2)"

  # B1 — unledgered firing workflow (string-form `on:`); A1 prints the
  # enumerator's own reading (1 job, paths=no, cancel=no) as the row to add.
  m="$(make_copy)"; assert_fixture_dir "$m"
  printf 'name: zz-new\non: pull_request\njobs:\n  one:\n    runs-on: ubuntu-latest\n    steps:\n      - run: true\n' > "$m/workflows/zz-new.yml"
  red_mutant B1 "$m" '^  FAIL: A1 zz-new\.yml fires' 'add the row zz-new\.yml<TAB>1<TAB>no<TAB>no<TAB>' 'drop pull_request' 'gate types:'

  # B2 — ci.yml grows past its row: add (allowed - declared + 1) jobs so the
  # file declares allowed+1 whatever the current declared count is.
  m="$(make_copy)"; assert_fixture_dir "$m"
  local k=$(( ci_allowed - ci_declared + 1 ))
  mutate_yaml "$m" ci.yml "for i in range($k): doc['jobs']['zz-mutant-%d' % i] = {'runs-on': 'ubuntu-latest', 'steps': [{'run': 'true'}]}"
  red_mutant B2 "$m" "^  FAIL: A3 ci\.yml: $((ci_allowed + 1)) declared, row allows $ci_allowed" 'fold the new job' 'do not delete the job'

  # B3 — delete the pr-quality-guards.yml row.
  m="$(make_copy)"; assert_fixture_dir "$m"
  sed -i '/^pr-quality-guards\.yml\t/d' "$m/ledger.txt"
  red_mutant B3 "$m" '^  FAIL: A1 pr-quality-guards\.yml fires' '^  FAIL: A1 [0-9]+ firing / [0-9]+ ledgered'

  # B4 — delete secret-scan.yml from the copy, keep its row (ghost row).
  m="$(make_copy)"; assert_fixture_dir "$m"
  rm -f "$m/workflows/secret-scan.yml"
  red_mutant B4 "$m" '^  FAIL: A2 row for secret-scan\.yml but .*does not exist' 'delete the row'

  # B5 — flip infra-validation.yml's paths flag to no in the ledger.
  m="$(make_copy)"; assert_fixture_dir "$m"
  awk -F'\t' -v OFS='\t' '!/^#/ && $1=="infra-validation.yml"{$3="no"} {print}' "$PRISTINE/ledger.txt" > "$m/ledger.txt"
  red_mutant B5 "$m" '^  FAIL: A4 infra-validation\.yml: row says paths=no, the trigger says paths=yes' 'name why'

  # B6 — no concurrency block in the file while the row says cancel=yes.
  m="$(make_copy)"; assert_fixture_dir "$m"
  mutate_yaml "$m" pr-quality-guards.yml "doc.pop('concurrency', None); [j.pop('concurrency', None) for j in doc['jobs'].values() if isinstance(j, dict)]"
  red_mutant B6 "$m" '^  FAIL: A4b pr-quality-guards\.yml: row says cancel=yes, the file says cancel=no' 'group keyed on'

  # B6b — per-SHA group with cancel-in-progress true, row cancel=yes (group shape).
  m="$(make_copy)"; assert_fixture_dir "$m"
  mutate_yaml "$m" pr-quality-guards.yml "doc['concurrency'] = {'group': 'pqg-\${{ github.event.pull_request.head.sha || github.sha }}', 'cancel-in-progress': True}"
  red_mutant B6b "$m" '^  FAIL: A4b pr-quality-guards\.yml: row says cancel=yes, the file says cancel=no' 'github\.event\.pull_request\.number'

  # B6e — a per-PR ref AND a per-run token in one group: the key never collides
  # across pushes, so nothing is ever cancelled; a presence check on the ref
  # alone would score it yes.
  m="$(make_copy)"; assert_fixture_dir "$m"
  mutate_yaml "$m" pr-quality-guards.yml "doc['concurrency'] = {'group': 'pqg-\${{ github.ref }}-\${{ github.sha }}', 'cancel-in-progress': True}"
  red_mutant B6e "$m" '^  FAIL: A4b pr-quality-guards\.yml: row says cancel=yes, the file says cancel=no' 'no per-run token'

  # B6c — an unrecognised cancel-in-progress expression fails closed (A4c).
  m="$(make_copy)"; assert_fixture_dir "$m"
  mutate_yaml "$m" pr-quality-guards.yml "doc['concurrency'] = {'group': 'pqg-\${{ github.ref }}', 'cancel-in-progress': \"\${{ github.event_name != 'push' }}\"}"
  red_mutant B6c "$m" "^  FAIL: A4c pr-quality-guards[.]yml: cancel-in-progress 'workflow=" "github[.]event_name != 'push' [}][}]' is not an accepted spelling" "accepted verbatim: true [|] false [|] [$][{][{] github[.]event_name == 'pull_request' [}][}];"

  # B6d — a row's TABs replaced with spaces: A-parse names the line.
  m="$(make_copy)"; assert_fixture_dir "$m"
  lno="$({ grep -n $'^cla\.yml\t' "$PRISTINE/ledger.txt" || true; } | cut -d: -f1 | head -1)"
  sed -i "${lno}s/\t/ /g" "$m/ledger.txt"
  red_mutant B6d "$m" "^  FAIL: A-parse line $lno: expected 5 TAB-separated columns, got 1 \\(spaces are not separators\\)"

  # B6f — a ternary-form copy whose group is per-ref only (the #7931 class on a
  # push: main arm): A4b still says yes, A6 pins it to ci.yml's group.
  m="$(make_copy)"; assert_fixture_dir "$m"
  mutate_yaml "$m" secret-scan.yml "doc['concurrency'] = {'group': 'secret-scan-\${{ github.ref }}', 'cancel-in-progress': \"\${{ github.event_name == 'pull_request' }}\"}"
  red_mutant B6f "$m" '^  FAIL: A6 secret-scan\.yml: ternary-form concurrency block does not carry ci\.yml' 'github\.workflow'

  # B7 — blank the consequence on cla.yml's row.
  m="$(make_copy)"; assert_fixture_dir "$m"
  awk -F'\t' -v OFS='\t' '!/^#/ && $1=="cla.yml"{$5=""} {print}' "$PRISTINE/ledger.txt" > "$m/ledger.txt"
  red_mutant B7 "$m" '^  FAIL: A5 cla\.yml: consequence has 0 word\(s\), need >= 4'

  # B7b — a cancel=no row whose consequence no longer says why.
  m="$(make_copy)"; assert_fixture_dir "$m"
  awk -F'\t' -v OFS='\t' '!/^#/ && $1=="cla.yml"{$5="CLA Required ruleset context cla-check via pull_request_target"} {print}' "$PRISTINE/ledger.txt" > "$m/ledger.txt"
  red_mutant B7b "$m" '^  FAIL: A5 cla\.yml: cancel=no but the consequence never says why'

  # B8 — an empty workflows dir: A0 exits 1 directly with `0 < 15`.
  m="$(make_copy)"; assert_fixture_dir "$m"; out="$m/child.out"; rc=0
  rm -rf "$m/workflows" && mkdir -p "$m/workflows"
  assert_landed B8 "$m" && { run_child "$m" "$out" || rc=$?; assert_red B8 "$rc" "$out" "^FAIL: A0 vacuity floor: 0 firing workflows found in .* \\(0 < $A0_FLOOR\\)"; }
  CASES=$((CASES + 1))
  if [[ "$rc" -eq 1 ]] && ! grep -Eq '^=== Results ===' "$out"; then
    pass "B8 A0 exited 1 directly — print_results never reached"
  else
    fail "B8 A0 did not exit directly" "rc 1 and no Results block" "rc=$rc"
  fi

  # B-sym — a symlinked *.yml is rejected via lstat, not followed.
  m="$(make_copy)"; assert_fixture_dir "$m"
  ln -s ci.yml "$m/workflows/zz-link.yml"
  red_mutant B-sym "$m" '^  FAIL: A-sym zz-link\.yml is a symlink'

  # B11 — a workflow_run chained off a firing workflow with no branch filter
  # fires once per PR push and has no row (the fix-constraints-stage-b shape).
  m="$(make_copy)"; assert_fixture_dir "$m"
  printf 'name: zz-chain\non:\n  workflow_run:\n    workflows: [CI]\n    types: [completed]\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps:\n      - run: true\n  b:\n    runs-on: ubuntu-latest\n    steps:\n      - run: true\n' > "$m/workflows/zz-chain.yml"
  red_mutant B11 "$m" '^  FAIL: A1 zz-chain\.yml fires' 'add the row zz-chain\.yml<TAB>2<TAB>no<TAB>no<TAB>' 'add branches: to its workflow_run'

  # B12 — a `uses:` job dispatches its local callee's jobs: one ci.yml job body
  # replaced by a 4-job reusable workflow declares allowed+3 slots, not allowed.
  m="$(make_copy)"; assert_fixture_dir "$m"
  printf 'name: zz-reusable\non:\n  workflow_call:\njobs:\n  r1:\n    runs-on: ubuntu-latest\n    steps: [{run: true}]\n  r2:\n    runs-on: ubuntu-latest\n    steps: [{run: true}]\n  r3:\n    runs-on: ubuntu-latest\n    steps: [{run: true}]\n  r4:\n    runs-on: ubuntu-latest\n    steps: [{run: true}]\n' > "$m/workflows/zz-reusable.yml"
  mutate_yaml "$m" ci.yml "k = sorted(doc['jobs'])[0]; doc['jobs'][k] = {'uses': './.github/workflows/zz-reusable.yml'}"
  red_mutant B12 "$m" "^  FAIL: A3 ci\.yml: $((ci_declared + 3)) declared, row allows $ci_allowed"

  # B9 — must PASS: a closed-only workflow with no row (mirrors
  # cleanup-unmerged-bot-branches.yml); the A1 summary is unchanged.
  m="$(make_copy)"; assert_fixture_dir "$m"; out="$m/child.out"; rc=0
  printf 'name: zz-closed\non:\n  pull_request:\n    types: [closed]\njobs:\n  one:\n    runs-on: ubuntu-latest\n    steps:\n      - run: true\n' > "$m/workflows/zz-closed.yml"
  assert_landed B9 "$m" && { run_child "$m" "$out" || rc=$?; assert_green B9 "$rc" "$out" "^${CONTROL_OUT}\$"; }

  # B9b — must PASS: a workflow_run chained off a firing workflow BUT filtered
  # to main (post-merge-monitor.yml's shape) is not a per-PR generator.
  m="$(make_copy)"; assert_fixture_dir "$m"; out="$m/child.out"; rc=0
  printf 'name: zz-main-chain\non:\n  workflow_run:\n    workflows: [CI]\n    types: [completed]\n    branches: [main]\njobs:\n  one:\n    runs-on: ubuntu-latest\n    steps:\n      - run: true\n' > "$m/workflows/zz-main-chain.yml"
  assert_landed B9b "$m" && { run_child "$m" "$out" || rc=$?; assert_green B9b "$rc" "$out" "^${CONTROL_OUT}\$"; }

  # B10 — must PASS: the ci.yml row is an upper bound (row = declared + 3).
  m="$(make_copy)"; assert_fixture_dir "$m"; out="$m/child.out"; rc=0
  awk -F'\t' -v OFS='\t' -v n="$((ci_declared + 3))" '!/^#/ && $1=="ci.yml"{$2=n} {print}' "$PRISTINE/ledger.txt" > "$m/ledger.txt"
  assert_landed B10 "$m" && { run_child "$m" "$out" || rc=$?; assert_green B10 "$rc" "$out" "^  PASS: A3 ci\\.yml: $ci_declared declared <= row $((ci_declared + 3))\$"; }

  # B-A7 — the assertion floor, off-diagonal: floor = actual+1 reds with the
  # direct message; floor = actual-1 stays green. Same unmutated copy.
  CASES=$((CASES + 1))
  if [[ "$CONTROL_CASES" =~ ^[0-9]+$ ]] && [[ "$CONTROL_CASES" -gt 1 ]]; then
    pass "B-A7 control reported $CONTROL_CASES cases"
    m="$(make_copy)"; assert_fixture_dir "$m"; out="$m/child.out"; rc=0
    run_child "$m" "$out" "$((CONTROL_CASES + 1))" || rc=$?
    assert_red "B-A7+1" "$rc" "$out" "^FAIL: only $CONTROL_CASES assertions ran \\(floor $((CONTROL_CASES + 1))\\)"
    m="$(make_copy)"; assert_fixture_dir "$m"; out="$m/child.out"; rc=0
    run_child "$m" "$out" "$((CONTROL_CASES - 1))" || rc=$?
    assert_green "B-A7-1" "$rc" "$out" "^A7 $CONTROL_CASES assertions ran \\(floor $((CONTROL_CASES - 1))\\)"
  else
    fail "B-A7 control did not report a usable case count" "an integer > 1" "'$CONTROL_CASES'"
  fi
}

# ── Dispatch ─────────────────────────────────────────────────────────────────
echo "=== pr-fanout-ledger.test.sh ==="
[[ "$PARTS" == *A* ]] && run_part_a
[[ "$PARTS" == *B* ]] && run_part_b

# A7 — assertion-count floor, checked over a counter incremented at every
# call site and reported by a DIRECT echo + exit, never through fail(), so a
# neutered verdict machinery cannot disarm it (scripts/guard-vacuity-floor.test.sh
# builds its mutant from exactly the MIN_CASES + if block below, so those lines
# stay adjacent and the default stays a literal).
#
# Derivation: A0 admits >= A0_FLOOR (15) firing workflows; each ledgered row
# contributes 8 Part A cases (A-parse, A2, A3, A4, A4b, A4c, A5, A6) and the
# singletons (A0, A1) add 2 -> 15 x 8 + 2 = 122 for Part A alone. Part B: 17
# RED mutants (B1-B8, B6b, B6c, B6d, B6e, B6f, B7b, B-sym, B11, B12) x (landed +
# verdict) = 34, 3 must-PASS rows (B9, B9b, B10) x 2 = 6, plus B0, the B8
# direct-exit check and B-A7 x 3 = 5 -> 45; 122 + 45 = 167 for a full run.
# Measured on the 2026-09-14 tree (22 firing): 178 Part A + 45 Part B = 223 (the
# figure is read from the run, never hand-summed). A Part-A-only run
# (PR_FANOUT_PARTS=A) gets the Part A floor; children pass 0.
if [[ -z "${PR_FANOUT_MIN_CASES:-}" ]]; then
  if [[ "$PARTS" == *B* ]]; then PR_FANOUT_MIN_CASES=167; else PR_FANOUT_MIN_CASES=122; fi
fi
# The `:-167` default duplicates the full-run literal above on purpose: the
# meta-guard constructs its mutant from a LITERAL bound adjacent to the `if`
# below, and an env-only bound is unconstructible (measured: it dropped this
# suite into the uncovered set).
MIN_CASES="${PR_FANOUT_MIN_CASES:-167}"
if [[ "$CASES" -lt "$MIN_CASES" ]]; then
  echo "FAIL: only $CASES assertions ran (floor $MIN_CASES)" >&2
  exit 1
fi
echo "A7 $CASES assertions ran (floor $MIN_CASES)"
print_results
