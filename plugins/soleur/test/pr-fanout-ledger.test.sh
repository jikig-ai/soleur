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
# `${PR_FANOUT_WORKFLOWS_DIR:-.github/workflows}/*.yml`. A file FIRES when
# `on.pull_request` or `on.pull_request_target` is present (dict, list or string
# form of `on:`; PyYAML parses a bare `on` key as boolean True) and `types` is
# absent or contains `synchronize`. `jobs` is `len(jobs)`. `paths` is the
# presence of `paths`/`paths-ignore` under that trigger. `cancel` is yes only
# when BOTH halves hold on SOME concurrency mapping (workflow-level or
# job-level): the cancel FORM is `true` or ci.yml's
# `${{ github.event_name == 'pull_request' }}` ternary, AND the GROUP SHAPE
# references `github.ref`, `github.head_ref`, `github.ref_name`,
# `github.event.number` or `github.event.pull_request.number` (a per-SHA group
# never cancels a superseded push). Any other cancel-in-progress spelling fails
# closed (A4c) so a new expression cannot be silently scored either way.
#
# BOTH SIDES ARE DERIVED INDEPENDENTLY. The real set never comes from the
# ledger's own row count — see Part B row 11 in the plan (a one-time harness
# verification: wiring A1 to the ledger's own set turns row 1 green).
#
# PART A runs against the tree. PART B (mutation battery) re-invokes Part A
# against a FRESH temp copy per mutant, with the assertion floor disabled, and
# requires each mutant to fail on the NAMED row. Every Part A row is driven RED
# at least once there.
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

python3 -c 'import yaml' 2>/dev/null || { echo "FAIL: PyYAML is required" >&2; exit 2; }

WF_DIR="${PR_FANOUT_WORKFLOWS_DIR:-$REPO_ROOT/.github/workflows}"
LEDGER="${PR_FANOUT_LEDGER:-$REPO_ROOT/scripts/pr-fanout-ledger.txt}"
PARTS="${PR_FANOUT_PARTS:-AB}"
SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"

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

ACCEPTED_SPELLINGS="true | false | \${{ github.event_name == 'pull_request' }}"
GROUP_SHAPES="github.ref | github.head_ref | github.ref_name | github.event.number | github.event.pull_request.number"

# ── The enumerator ───────────────────────────────────────────────────────────
# Emits one TSV record per *.yml / *.yaml in WF_DIR:
#   FIRE <file> <jobs> <paths> <cancel> <bad-forms>     a firing workflow
#   SYM  <file>                                          a symlink (rejected via lstat)
#   ERR  <file> <message>                                unparseable / not a mapping
# <bad-forms> is `-` or a `|`-joined list of `<scope>=<expr>` for every
# cancel-in-progress value that is none of the accepted spellings.
enumerate() { # <dir> -> TSV on stdout
  WF_DIR="$1" python3 - <<'PY'
import os, re, sys, yaml
d = os.environ["WF_DIR"]
TERNARY = "${{ github.event_name == 'pull_request' }}"
GROUP_RE = re.compile(r"github\.(ref|head_ref|ref_name|event\.number|event\.pull_request\.number)\b")

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

def fires(on):
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

def cancel_form(v):
    if v is None or v is False:
        return "false"
    if v is True:
        return "true"
    s = re.sub(r"\s+", " ", str(v).strip())
    if s.lower() in ("true", "false"):
        return s.lower()
    return s

out = []
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
    on = norm_on(doc.get("on", doc.get(True)))
    ok, trig = fires(on)
    if not ok:
        continue
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
    bad = []
    for scope, c in blocks:
        if isinstance(c, dict):
            grp = str(c.get("group", ""))
            form = cancel_form(c.get("cancel-in-progress"))
        else:
            grp = str(c)          # string shorthand: group only, cancel defaults false
            form = "false"
        if form not in ("true", "false", TERNARY):
            bad.append("%s=%s" % (scope, form))
            continue
        if form != "false" and GROUP_RE.search(grp):
            cancel = "yes"
    out.append("FIRE\t%s\t%d\t%s\t%s\t%s" % (f, len(jobs), paths, cancel, "|".join(bad) if bad else "-"))
sys.stdout.write("\n".join(out) + ("\n" if out else ""))
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
  if [[ "$found" -lt 15 ]]; then
    echo "FAIL: A0 vacuity floor: $found firing workflows found in $WF_DIR ($found < 15) — the tree is unreadable or the enumerator broke; this is not a clean ledger" >&2
    exit 1
  fi
  CASES=$((CASES + 1))
  pass "A0 enumerator found $found firing workflows ($found >= 15)"

  # A-parse — every non-comment ledger line has exactly 5 TAB-separated fields.
  if [[ ! -f "$LEDGER" ]]; then
    echo "FAIL: ledger $LEDGER not found" >&2
    exit 1
  fi
  local rows="$SUITE_TMP/rows.$$.tsv" ln nf
  # Comment lines are leading-# only; blank lines are ignored.
  awk -F'\t' '!/^#/ && NF>0 {print NR"\t"NF"\t"$0}' "$LEDGER" > "$rows"
  local example
  example="$(awk -F'\t' '!/^#/ && NF==5 {print; exit}' "$LEDGER")"
  while IFS=$'\t' read -r ln nf _rest; do
    CASES=$((CASES + 1))
    if [[ "$nf" -eq 5 ]]; then
      pass "A-parse line $ln: 5 TAB-separated columns"
    else
      fail "A-parse line $ln: expected 5 TAB-separated columns, got $nf (spaces are not separators)" \
        "<workflow><TAB><jobs><TAB><paths><TAB><cancel><TAB><consequence>, e.g. ${example//$'\t'/<TAB>}" \
        "$(sed -n "${ln}p" "$LEDGER")"
    fi
  done < "$rows"

  # Ledger lookups keyed by workflow name (only well-formed rows).
  local lrows="$SUITE_TMP/ledger-rows.$$.tsv"
  awk -F'\t' '!/^#/ && NF==5' "$LEDGER" > "$lrows"

  # A1 — every firing workflow has a row. One summary line prints both counts
  # (AC12); each missing file is its own FAIL naming the three honest exits.
  local firing ledgered missing=0
  firing="$found"
  ledgered="$(wc -l < "$lrows" | tr -d '[:space:]')"
  while IFS=$'\t' read -r f; do
    if ! awk -F'\t' -v w="$f" '$1==w{found=1} END{exit !found}' "$lrows"; then
      missing=$((missing + 1))
      CASES=$((CASES + 1))
      fail "A1 $f fires on a PR push but has no ledger row in $(basename "$LEDGER") — three honest exits: (1) add a row naming the consequence, e.g. ${example//$'\t'/<TAB>}; (2) drop pull_request from its on: block; (3) gate types: to opened/closed only"
    fi
  done < <(awk -F'\t' '$1=="FIRE"{print $2}' "$enum")
  CASES=$((CASES + 1))
  if [[ "$missing" -eq 0 ]]; then
    pass "A1 $firing firing / $ledgered ledgered — every firing workflow has a row"
  else
    fail "A1 $firing firing / $ledgered ledgered — $missing firing workflow(s) have no row"
  fi

  # A2..A5 — per row.
  local w jobs paths cancel cons declared fpaths fcancel bad nwords
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
    IFS=$'\t' read -r declared fpaths fcancel bad < <(awk -F'\t' -v w="$w" '$1=="FIRE" && $2==w{print $3"\t"$4"\t"$5"\t"$6; exit}' "$enum")

    # A3 — declared jobs <= the row (the row is a CEILING).
    CASES=$((CASES + 1))
    if [[ "$jobs" =~ ^[0-9]+$ ]] && [[ "$declared" -le "$jobs" ]]; then
      pass "A3 $w: $declared declared <= row $jobs"
    else
      fail "A3 $w: $declared declared, row allows $jobs — raise the row and name why; do not delete the job to satisfy the ledger"
    fi

    # A4 — paths flag equality.
    CASES=$((CASES + 1))
    if [[ "$paths" == "$fpaths" ]]; then
      pass "A4 $w: paths=$paths"
    else
      fail "A4 $w: row says paths=$paths, the trigger says paths=$fpaths — edit the row or the file, and name why"
    fi

    # A4c — an unrecognised cancel-in-progress spelling fails closed.
    CASES=$((CASES + 1))
    if [[ "$bad" == "-" ]]; then
      pass "A4c $w: every cancel-in-progress value is an accepted spelling"
    else
      fail "A4c $w: cancel-in-progress '$bad' is not an accepted spelling — accepted verbatim: $ACCEPTED_SPELLINGS; the enumerator cannot score it either way"
    fi

    # A4b — cancel flag equality (form AND group shape).
    CASES=$((CASES + 1))
    if [[ "$cancel" == "$fcancel" ]]; then
      pass "A4b $w: cancel=$cancel"
    else
      fail "A4b $w: row says cancel=$cancel, the file says cancel=$fcancel — cancel=yes needs BOTH the form (cancel-in-progress in: $ACCEPTED_SPELLINGS, not false) AND a group shape keyed on one of: $GROUP_SHAPES; edit the row or the file, and name why"
    fi

    # A5 — consequence >= 4 words.
    CASES=$((CASES + 1))
    nwords="$(printf '%s' "$cons" | wc -w | tr -d '[:space:]')"
    if [[ "$nwords" -ge 4 ]]; then
      pass "A5 $w: consequence has $nwords words"
    else
      fail "A5 $w: consequence has $nwords word(s), need >= 4 — a row with no consequence is a row that should not exist"
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

# assert_red <row> <copy> <rc> <out> <grep-ERE-1> [<grep-ERE-2> ...]
assert_red() {
  local row="$1" m="$2" rc="$3" out="$4"; shift 4
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

  # B0 — control: an unmutated copy is green and prints the A1 summary.
  m="$(make_copy)"; out="$m/child.out"; rc=0
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

  # B1 — unledgered firing workflow (string-form `on:`).
  m="$(make_copy)"; out="$m/child.out"; rc=0
  printf 'name: zz-new\non: pull_request\njobs:\n  one:\n    runs-on: ubuntu-latest\n    steps:\n      - run: true\n' > "$m/workflows/zz-new.yml"
  assert_landed B1 "$m" && { run_child "$m" "$out" || rc=$?; assert_red B1 "$m" "$rc" "$out" '^  FAIL: A1 zz-new\.yml fires' 'add a row naming the consequence' 'drop pull_request' 'gate types:'; }

  # B2 — ci.yml grows past its row: add (allowed - declared + 1) jobs so the
  # file declares allowed+1 whatever the current declared count is.
  m="$(make_copy)"; out="$m/child.out"; rc=0
  local k=$(( ci_allowed - ci_declared + 1 ))
  mutate_yaml "$m" ci.yml "for i in range($k): doc['jobs']['zz-mutant-%d' % i] = {'runs-on': 'ubuntu-latest', 'steps': [{'run': 'true'}]}"
  assert_landed B2 "$m" && { run_child "$m" "$out" || rc=$?; assert_red B2 "$m" "$rc" "$out" "^  FAIL: A3 ci\.yml: $((ci_allowed + 1)) declared, row allows $ci_allowed" 'do not delete the job'; }

  # B3 — delete the pr-quality-guards.yml row.
  m="$(make_copy)"; out="$m/child.out"; rc=0
  sed -i '/^pr-quality-guards\.yml\t/d' "$m/ledger.txt"
  assert_landed B3 "$m" && { run_child "$m" "$out" || rc=$?; assert_red B3 "$m" "$rc" "$out" '^  FAIL: A1 pr-quality-guards\.yml fires' '^  FAIL: A1 [0-9]+ firing / [0-9]+ ledgered'; }

  # B4 — delete secret-scan.yml from the copy, keep its row (ghost row).
  m="$(make_copy)"; out="$m/child.out"; rc=0
  rm -f "$m/workflows/secret-scan.yml"
  assert_landed B4 "$m" && { run_child "$m" "$out" || rc=$?; assert_red B4 "$m" "$rc" "$out" '^  FAIL: A2 row for secret-scan\.yml but .*does not exist' 'delete the row'; }

  # B5 — flip infra-validation.yml's paths flag to no in the ledger.
  m="$(make_copy)"; out="$m/child.out"; rc=0
  awk -F'\t' -v OFS='\t' '!/^#/ && $1=="infra-validation.yml"{$3="no"} {print}' "$PRISTINE/ledger.txt" > "$m/ledger.txt"
  assert_landed B5 "$m" && { run_child "$m" "$out" || rc=$?; assert_red B5 "$m" "$rc" "$out" '^  FAIL: A4 infra-validation\.yml: row says paths=no, the trigger says paths=yes' 'name why'; }

  # B6 — no concurrency block in the file, cancel=yes in the row. The block is
  # stripped from the copy (a no-op while the file has none) AND the row is set
  # to yes (a no-op once the tree has flipped it), so the mutant lands on either
  # side of the 2026-09-14 concurrency rollout.
  m="$(make_copy)"; out="$m/child.out"; rc=0
  mutate_yaml "$m" pr-quality-guards.yml "doc.pop('concurrency', None); [j.pop('concurrency', None) for j in doc['jobs'].values() if isinstance(j, dict)]"
  awk -F'\t' -v OFS='\t' '!/^#/ && $1=="pr-quality-guards.yml"{$4="yes"} {print}' "$PRISTINE/ledger.txt" > "$m/ledger.txt"
  assert_landed B6 "$m" && { run_child "$m" "$out" || rc=$?; assert_red B6 "$m" "$rc" "$out" '^  FAIL: A4b pr-quality-guards\.yml: row says cancel=yes, the file says cancel=no' 'group shape'; }

  # B6b — per-SHA group with cancel-in-progress true, row cancel=yes (group shape).
  m="$(make_copy)"; out="$m/child.out"; rc=0
  mutate_yaml "$m" pr-quality-guards.yml "doc['concurrency'] = {'group': 'pqg-\${{ github.event.pull_request.head.sha || github.sha }}', 'cancel-in-progress': True}"
  awk -F'\t' -v OFS='\t' '!/^#/ && $1=="pr-quality-guards.yml"{$4="yes"} {print}' "$PRISTINE/ledger.txt" > "$m/ledger.txt"
  assert_landed B6b "$m" && { run_child "$m" "$out" || rc=$?; assert_red B6b "$m" "$rc" "$out" '^  FAIL: A4b pr-quality-guards\.yml: row says cancel=yes, the file says cancel=no' 'github\.event\.pull_request\.number'; }

  # B6c — an unrecognised cancel-in-progress expression fails closed (A4c).
  m="$(make_copy)"; out="$m/child.out"; rc=0
  mutate_yaml "$m" pr-quality-guards.yml "doc['concurrency'] = {'group': 'pqg-\${{ github.ref }}', 'cancel-in-progress': \"\${{ github.event_name != 'push' }}\"}"
  assert_landed B6c "$m" && { run_child "$m" "$out" || rc=$?; assert_red B6c "$m" "$rc" "$out" "^  FAIL: A4c pr-quality-guards[.]yml: cancel-in-progress 'workflow=" "github[.]event_name != 'push' [}][}]' is not an accepted spelling" "accepted verbatim: true [|] false [|] [$][{][{] github[.]event_name == 'pull_request' [}][}];"; }

  # B6d — a row's TABs replaced with spaces: A-parse names the line.
  m="$(make_copy)"; out="$m/child.out"; rc=0
  lno="$(grep -n $'^cla\.yml\t' "$PRISTINE/ledger.txt" | cut -d: -f1 | head -1)"
  sed -i "${lno}s/\t/ /g" "$m/ledger.txt"
  assert_landed B6d "$m" && { run_child "$m" "$out" || rc=$?; assert_red B6d "$m" "$rc" "$out" "^  FAIL: A-parse line $lno: expected 5 TAB-separated columns, got 1 \\(spaces are not separators\\)"; }

  # B7 — blank the consequence on cla.yml's row.
  m="$(make_copy)"; out="$m/child.out"; rc=0
  awk -F'\t' -v OFS='\t' '!/^#/ && $1=="cla.yml"{$5=""} {print}' "$PRISTINE/ledger.txt" > "$m/ledger.txt"
  assert_landed B7 "$m" && { run_child "$m" "$out" || rc=$?; assert_red B7 "$m" "$rc" "$out" '^  FAIL: A5 cla\.yml: consequence has 0 word\(s\), need >= 4'; }

  # B8 — an empty workflows dir: A0 exits 1 directly with `0 < 15`.
  m="$(make_copy)"; out="$m/child.out"; rc=0
  rm -rf "$m/workflows" && mkdir -p "$m/workflows"
  assert_landed B8 "$m" && { run_child "$m" "$out" || rc=$?; assert_red B8 "$m" "$rc" "$out" '^FAIL: A0 vacuity floor: 0 firing workflows found in .* \(0 < 15\)'; }
  CASES=$((CASES + 1))
  if [[ "$rc" -eq 1 ]] && ! grep -Eq '^=== Results ===' "$out"; then
    pass "B8 A0 exited 1 directly — print_results never reached"
  else
    fail "B8 A0 did not exit directly" "rc 1 and no Results block" "rc=$rc"
  fi

  # B-sym — a symlinked *.yml is rejected via lstat, not followed.
  m="$(make_copy)"; out="$m/child.out"; rc=0
  ln -s ci.yml "$m/workflows/zz-link.yml"
  assert_landed B-sym "$m" && { run_child "$m" "$out" || rc=$?; assert_red B-sym "$m" "$rc" "$out" '^  FAIL: A-sym zz-link\.yml is a symlink'; }

  # B9 — must PASS: a closed-only workflow with no row (mirrors
  # cleanup-unmerged-bot-branches.yml); the A1 summary is unchanged.
  m="$(make_copy)"; out="$m/child.out"; rc=0
  printf 'name: zz-closed\non:\n  pull_request:\n    types: [closed]\njobs:\n  one:\n    runs-on: ubuntu-latest\n    steps:\n      - run: true\n' > "$m/workflows/zz-closed.yml"
  assert_landed B9 "$m" && { run_child "$m" "$out" || rc=$?; assert_green B9 "$rc" "$out" "^${CONTROL_OUT}\$"; }

  # B10 — must PASS: the ci.yml row is an upper bound (row = declared + 3).
  m="$(make_copy)"; out="$m/child.out"; rc=0
  awk -F'\t' -v OFS='\t' -v n="$((ci_declared + 3))" '!/^#/ && $1=="ci.yml"{$2=n} {print}' "$PRISTINE/ledger.txt" > "$m/ledger.txt"
  assert_landed B10 "$m" && { run_child "$m" "$out" || rc=$?; assert_green B10 "$rc" "$out" "^  PASS: A3 ci\\.yml: $ci_declared declared <= row $((ci_declared + 3))\$"; }

  # B-A7 — the assertion floor, off-diagonal: floor = actual+1 reds with the
  # direct message; floor = actual-1 stays green. Same unmutated copy.
  CASES=$((CASES + 1))
  if [[ "$CONTROL_CASES" =~ ^[0-9]+$ ]] && [[ "$CONTROL_CASES" -gt 1 ]]; then
    pass "B-A7 control reported $CONTROL_CASES cases"
    m="$(make_copy)"; out="$m/child.out"; rc=0
    run_child "$m" "$out" "$((CONTROL_CASES + 1))" || rc=$?
    assert_red "B-A7+1" "$m" "$rc" "$out" "^FAIL: only $CONTROL_CASES assertions ran \\(floor $((CONTROL_CASES + 1))\\)"
    m="$(make_copy)"; out="$m/child.out"; rc=0
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
# Derivation: A0 admits >= 15 firing workflows; each ledgered row contributes 7
# Part A cases (A-parse, A2, A3, A4, A4c, A4b, A5) and the singletons (A0, A1)
# add 2 -> 15 x 7 + 2 = 107 for Part A alone; Part B contributes >= 32 (control,
# 12 landed + 12 verdict rows, B8 direct-exit, B-A7 x 3) -> 139 for a full run.
# Measured on the 2026-09-14 tree (21 firing): 149 Part A + 35 Part B. A Part-A-only
# run (PR_FANOUT_PARTS=A) gets the Part A floor; children pass 0.
if [[ -z "${PR_FANOUT_MIN_CASES:-}" ]]; then
  if [[ "$PARTS" == *B* ]]; then PR_FANOUT_MIN_CASES=139; else PR_FANOUT_MIN_CASES=107; fi
fi
MIN_CASES="${PR_FANOUT_MIN_CASES:-139}"
if [[ "$CASES" -lt "$MIN_CASES" ]]; then
  echo "FAIL: only $CASES assertions ran (floor $MIN_CASES)" >&2
  exit 1
fi
echo "A7 $CASES assertions ran (floor $MIN_CASES)"
print_results
