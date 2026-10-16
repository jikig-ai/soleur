#!/usr/bin/env bash
# Wiring test for the standing registry fill-rate leg (#7521, part b).
#
# This suite is the ONLY owner of the fill-leg contract. The leg lives in
# .github/workflows/scheduled-zot-restart-loop.yml as four steps appended AFTER the
# `Sentry check-in (final)` step: a probe (runs scripts/followthroughs/zot-fill-rate-7341.sh in
# place), a FAIL filing step, a probe-defect filing step and a PASS close step. Every pass
# condition lives inside workflow YAML, which no unit test reaches by itself, so this suite parses
# the workflow with python3 + yaml (never grep over YAML), finds the steps by what they DO (the
# probe is the step that invokes the script, the filing steps are told apart by their `if:`
# literal), and EXECUTES the probe and filing bodies against a fake script and a PATH-shimmed `gh`.
# The harness runs each body under `bash --noprofile --norc -e`, which is the runner default for a
# step with no `shell:` key, PLUS the body's own `set` line (pinned below as its first statement).
# It adds no pipefail of its own: a harness stricter than the runner would hide a deleted `set`.
#
# THE PROPERTY. The fill leg can neither change the restart-loop alarm's Sentry status nor the
# reachability of its filing steps, nor file or close an issue on a verdict it did not measure,
# nor report a probe defect as a store state.
#
# WHAT IS PINNED, AND WHAT IS NOT. Each fill step has its exact `if:`, its exact env and a closed
# key set (name, id on the probe only, if, timeout-minutes on the probe only, env, run); the job
# and the workflow have closed key sets, and the reviewed permissions and outputs. The generic
# condition-shape rules (a status function, non-empty non-numeric literals, no `!=`) are the
# independent witness of scripts/alarm-issue-filing-guard.test.sh, which discovers the new steps on
# its own, and apps/web-platform/test/server/watchdog-workflow-idempotence.test.ts executes the
# lookup lines.
#
# TEST SEAM. ZOT_FILL_WIRING_ROOT points the suite at a tree holding
# .github/workflows/scheduled-zot-restart-loop.yml (default: the repo root). The mutation rows
# below use it to run this same suite, as a child process, against edited copies of the workflow.
# AC3 (the suite is RED against the pre-change workflow) is checked in the PR by pointing this seam
# at a tree holding `git show origin/main:.github/workflows/scheduled-zot-restart-loop.yml`; the
# in-suite equivalents are the zero-fill-steps floor and mutation row 1. ZOT_FILL_WIRING_CHILD
# marks such a child: it skips the mutation section (no recursion) and the vacuity floor, which
# the parent enforces by comparing the child's executed-case count with its own.
#
# Shape (six ratchets bind this file): `set -uo pipefail` (never -e), a call-site `cases`
# counter, a literal-bound MIN_CASES floor adjacent above its `if`, an instrument self-test, one
# trap owning every mktemp, the canonical assert_fixture_dir, every $( ) capture guarded, and no
# `grep -q` after a pipe.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="${SCRIPT_DIR}/$(basename "${BASH_SOURCE[0]}")"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ROOT="${ZOT_FILL_WIRING_ROOT:-$REPO_ROOT}"
CHILD="${ZOT_FILL_WIRING_CHILD:-}"
WF_REL=".github/workflows/scheduled-zot-restart-loop.yml"
WF="${ROOT}/${WF_REL}"
BASE_PATH="/usr/local/bin:/usr/bin:/bin"

# One trap, one scratch root: every file this suite creates lives under $S.
S="$(mktemp -d -t zot-fill-wiring.XXXXXXXX)" || { echo "FATAL: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$S"' EXIT INT TERM HUP

# Canonical copy of the fixture-dir guard from plugins/soleur/test/test-helpers.sh (byte-identical
# per fixture-dir-operand-assert.test.sh). Sourcing the helper file is not an option here: it sets
# -e, and this suite deliberately runs `set -uo pipefail` so a failing case lands in FAIL.
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
assert_fixture_dir "$S"

passes=0; fails=0; cases=0
LEDGER="$S/ledger.txt"
: > "$LEDGER"
# Verdict helpers. One line each: the instrument self-test below neuters them by line.
pass() { printf '  PASS: %s\n' "$1"; echo PASS >> "$LEDGER"; passes=$((passes + 1)); }
fail() { printf '  FAIL: %s\n' "$1"; echo FAIL >> "$LEDGER"; fails=$((fails + 1)); }
# Incremented at the CALL SITE, never inside pass()/fail(): a counter living inside the helper it
# polices cannot notice that helper being neutered (ADR-193).
ck() { cases=$((cases + 1)); }
eq() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1 (want: [$2] got: [$3])"; fi; }

command -v python3 >/dev/null 2>&1 || { echo "FATAL: python3 missing" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq missing" >&2; exit 2; }
command -v timeout >/dev/null 2>&1 || { echo "FATAL: timeout missing" >&2; exit 2; }
[[ -f "$WF" ]] || { echo "FATAL: workflow not found at $WF" >&2; exit 2; }

# ── helper programs (heredocs: their bodies are data, not suite code) ───────────────────────────
HELPERS="$S/helpers"
SHIM="$S/shim"
mkdir -p "$HELPERS" "$SHIM"

cat > "$HELPERS/wf.py" <<'PY'
import json, os, re, sys, yaml

PROBE_CALL = re.compile(r"\$\(bash scripts/followthroughs/zot-fill-rate-7341\.sh")
ALARM_CALL = re.compile(r"\$\(bash scripts/zot-restart-loop-alarm\.sh")
WRITE_VERB = re.compile(r"gh issue (create|comment|close)\b")
TITLE = re.compile(r'^\s*ISSUE_TITLE="([^"]*)"\s*$', re.M)
ECHO_KEY = re.compile(r'echo "([A-Za-z_][A-Za-z0-9_]*)=')
# Fill-output references are detected by the output KEY NAMES and by any steps[...] / toJSON(steps)
# spelling, never by the dot form alone, so bracket syntax cannot evade the count.
FILL_KEYS = re.compile(r"fill_verdict|fill_defect|fill_line")
STEPS_INDEX = re.compile(r"steps\s*\[|toJSON\(\s*steps")
BRACKET_ID = re.compile(r"steps\s*\[\s*['\"]([A-Za-z0-9_-]+)['\"]\s*\]")
SET_LINE = re.compile(r"^\s*(?:#.*)?$")

def text(o):
    """Every string in a parsed YAML node (keys included), newline-joined."""
    if isinstance(o, dict):
        return "\n".join(text(k) + "\n" + text(v) for k, v in o.items())
    if isinstance(o, list):
        return "\n".join(text(v) for v in o)
    return str(o)

def first_stmt(run):
    for line in run.splitlines():
        if not SET_LINE.match(line):
            return line.strip()
    return "<none>"

def load(path):
    return yaml.safe_load(open(path, encoding="utf-8"))

def steps_of(doc):
    return doc["jobs"]["alarm"]["steps"]

def run_of(s):
    return s.get("run") or ""

def find(steps):
    probe = [i for i, s in enumerate(steps) if PROBE_CALL.search(run_of(s))]
    alarm = [i for i, s in enumerate(steps) if ALARM_CALL.search(run_of(s))]
    sentry = [i for i, s in enumerate(steps) if "sentry-heartbeat" in str(s.get("uses", ""))]
    return probe, alarm, sentry

def facts(wf, out):
    doc = load(wf)
    steps = steps_of(doc)
    probe, alarm, sentry = find(steps)
    f = {}
    f["N_PROBE"] = len(probe)
    f["N_ALARM"] = len(alarm)
    f["N_SENTRY"] = len(sentry)
    if not (probe and alarm and sentry):
        f["FILL_STEPS"] = len(probe)
        for k, v in f.items():
            print(f"{k}={v}")
        return
    p, a, sn = probe[0], alarm[0], sentry[0]
    pid = steps[p].get("id", "")
    f["PROBE_IDX"], f["ALARM_IDX"], f["SENTRY_IDX"] = p, a, sn
    f["PROBE_ID"], f["ALARM_ID"] = pid, steps[a].get("id", "")
    ref = re.compile(r"steps\.%s\." % re.escape(pid)) if pid else None
    fill = set([p])
    for i, s in enumerate(steps):
        blob = text(s)
        if ((ref and ref.search(blob)) or "ci/zot-fill-rate" in blob
                or FILL_KEYS.search(blob) or STEPS_INDEX.search(blob)):
            fill.add(i)
    f["FILL_STEPS"] = len(fill)
    status = str((steps[sn].get("with") or {}).get("status", ""))
    f["SENTRY_STATUS_IDS"] = ",".join(sorted(set(re.findall(r"steps\.([A-Za-z0-9_-]+)\.", status))))
    f["SENTRY_IF"] = str(steps[sn].get("if", ""))
    f["JOB_TIMEOUT"] = doc["jobs"]["alarm"].get("timeout-minutes", "")
    f["PROBE_TIMEOUT"] = steps[p].get("timeout-minutes", "")
    existing = [i for i, s in enumerate(steps) if i not in fill and WRITE_VERB.search(run_of(s))]
    f["EXISTING_FILING_MIN"] = min(existing) if existing else -1
    f["EXISTING_FILING_MAX"] = max(existing) if existing else -1
    kinds = {"fail": [], "defect": [], "pass": []}
    filing = []
    for i in sorted(fill - {p}):
        s = steps[i]
        if WRITE_VERB.search(run_of(s)):
            filing.append(i)
        cond = str(s.get("if", ""))
        if "fill_verdict == 'FAIL'" in cond:
            kinds["fail"].append(i)
        elif "fill_defect == 'true'" in cond:
            kinds["defect"].append(i)
        elif "fill_verdict == 'PASS'" in cond:
            kinds["pass"].append(i)
    f["N_FILING"] = len(filing)
    f["FILING_MIN"] = min(filing) if filing else -1
    for k, v in kinds.items():
        f["N_" + k.upper()] = len(v)
        body = run_of(steps[v[0]]) if v else ""
        open(os.path.join(out, k + ".sh"), "w").write(body)
    open(os.path.join(out, "probe.sh"), "w").write(run_of(steps[p]))
    f["BETTERSTACK_IN_FILING"] = sum(
        1 for i in filing for k in (steps[i].get("env") or {}) if str(k).startswith("BETTERSTACK_"))
    m = TITLE.search(open(os.path.join(out, "fail.sh")).read())
    f["FAIL_TITLE"] = m.group(1) if m else ""
    m = TITLE.search(open(os.path.join(out, "defect.sh")).read())
    f["DEFECT_TITLE"] = m.group(1) if m else ""
    pass_body = open(os.path.join(out, "pass.sh")).read()
    f["PASS_TITLES_OK"] = int(bool(f["FAIL_TITLE"]) and bool(f["DEFECT_TITLE"])
                              and f["FAIL_TITLE"] in pass_body and f["DEFECT_TITLE"] in pass_body)
    # Exact `if:` and env of every fill step, and the closed world of step outputs. Each value is
    # compared against a reviewed literal by the shell side.
    roles = {"probe": [p], "fail": kinds["fail"], "defect": kinds["defect"], "pass": kinds["pass"]}
    for role, idx in roles.items():
        s0 = steps[idx[0]] if idx else {}
        env = s0.get("env") or {}
        f["IF_" + role] = str(s0.get("if", "<absent>")) if idx else "<no step>"
        f["ENV_" + role] = " ; ".join("%s=%s" % (k, env[k]) for k in sorted(env)) if idx else "<no step>"
    ids = set(s.get("id") for s in steps if s.get("id"))
    blobs = [text(s) for s in steps]
    # Everything in the document that is NOT the alarm job's step list (job outputs, job and
    # workflow level keys, the other jobs).
    outside_doc = json.loads(json.dumps(doc, default=str))
    outside_doc["jobs"]["alarm"]["steps"] = []
    outside = text(outside_doc)
    refs_any = set()
    for b in blobs + [outside]:
        refs_any |= set(re.findall(r"steps\.([A-Za-z0-9_-]+)\.", b))
        refs_any |= set(BRACKET_ID.findall(b))
    f["DANGLING_STEP_IDS"] = ",".join(sorted(refs_any - ids))
    out_ref = re.compile(
        r"steps(?:\.%s|\s*\[\s*['\"]%s['\"]\s*\])\.outputs(?:\.([A-Za-z0-9_]+)|\s*\[\s*['\"]([A-Za-z0-9_]+)['\"]\s*\])"
        % (re.escape(pid), re.escape(pid)))
    fill_refs = set()
    for b in blobs:
        for a1, a2 in out_ref.findall(b):
            fill_refs.add(a1 or a2)
    f["FILL_OUTSIDE"] = len(ref.findall(outside)) + len(FILL_KEYS.findall(outside)) + len(STEPS_INDEX.findall(outside))
    written = set(ECHO_KEY.findall(run_of(steps[p])))
    f["FILL_UNWRITTEN_REFS"] = ",".join(sorted(fill_refs - written))
    f["FILL_REFS_N"] = len(fill_refs)
    aid = steps[a].get("id", "")
    alarm_refs = set(re.findall(r"steps\.%s\.outputs\.([A-Za-z0-9_]+)" % re.escape(aid), blobs[p]))
    # Closed key sets: the contract is the literal list below, so any other behaviour-bearing key
    # (shell, continue-on-error, working-directory, uses, with, an id on a non-probe step) fails.
    for role, idx in roles.items():
        s0 = steps[idx[0]] if idx else {}
        f["KEYS_" + role] = ",".join(sorted(str(k) for k in s0)) if idx else "<no step>"
        f["FIRST_" + role] = first_stmt(run_of(s0)) if idx else "<no step>"
    f["FILL_SHELL_STEPS"] = sum(1 for i in fill if "shell" in steps[i])
    # A later `set +e` / `set +o errexit` would undo the first-statement set line (verifier P3-1).
    f["FILL_SET_PLUS"] = sum(1 for i in fill if re.search(r"(^|[\n;&|(])\s*set\s+\+", run_of(steps[i])))
    f["TOP_KEYS"] = ",".join(sorted("on" if k is True else str(k) for k in doc))
    f["JOB_KEYS"] = ",".join(sorted(str(k) for k in doc["jobs"]["alarm"]))
    perms = doc.get("permissions") or {}
    f["WF_PERMS"] = " ; ".join("%s=%s" % (k, perms[k]) for k in sorted(perms))
    jo = doc["jobs"]["alarm"].get("outputs") or {}
    f["JOB_OUTPUTS"] = " ; ".join("%s=%s" % (k, jo[k]) for k in sorted(jo))
    f["PROBE_ALARM_REFS_N"] = len(alarm_refs)
    f["PROBE_ALARM_REFS_MISSING"] = ",".join(sorted(alarm_refs - set(ECHO_KEY.findall(run_of(steps[a])))))
    for k, v in f.items():
        print(f"{k}={v}")

def mutate(src, dst, op, args):
    raw = open(src, encoding="utf-8").read()
    if op == "rename-literal":
        new = raw.replace(args[0], args[1])
        if new == raw:
            sys.exit("mutation did not apply: " + op)
        open(dst, "w").write(new)
        return
    if op == "rename-ids":
        new = raw.replace("steps.fill.", "steps.probex.").replace("id: fill\n", "id: probex\n")
        if new == raw:
            sys.exit("mutation did not apply: " + op)
        open(dst, "w").write(new + "\n# an extra comment line that changes nothing\n")
        return
    doc = yaml.safe_load(raw)
    steps = steps_of(doc)
    probe, alarm, sentry = find(steps)
    kind_cond = {"probe": None, "fail": "fill_verdict == 'FAIL'", "defect": "fill_defect == 'true'",
                 "pass": "fill_verdict == 'PASS'"}
    if op == "noop":
        # A pure yaml.safe_load / safe_dump roundtrip: the control for every row that uses one.
        open(dst, "w").write(yaml.safe_dump(doc, sort_keys=False, width=10**9, allow_unicode=True))
        return
    if op in ("step-set", "job-set", "wf-set"):
        key, val = args[-2], args[-1]
        node = json.loads(val) if val != "__DEL__" else None
        if op == "step-set":
            kind = args[0]
            tgt = steps[probe[0]] if kind == "probe" else next(
                s for s in steps if kind_cond[kind] in str(s.get("if", "")))
        elif op == "job-set":
            tgt = doc["jobs"]["alarm"]
        else:
            tgt = doc
        if node is None:
            if key not in tgt:
                sys.exit("mutation did not apply: " + op + " " + key)
            del tgt[key]
        else:
            if tgt.get(key) == node:
                sys.exit("mutation did not apply: " + op + " " + key)
            tgt[key] = node
        open(dst, "w").write(yaml.safe_dump(doc, sort_keys=False, width=10**9, allow_unicode=True))
        return
    if op == "add-step-run":
        steps.append({"name": "Extra step", "run": args[0]})
        open(dst, "w").write(yaml.safe_dump(doc, sort_keys=False, width=10**9, allow_unicode=True))
        return
    if op == "run-replace":
        kind, old, new = args
        if kind == "probe":
            tgt = steps[probe[0]]
        else:
            tgt = next(s for s in steps if kind_cond[kind] in str(s.get("if", "")))
        if old not in tgt["run"]:
            sys.exit("mutation did not apply: " + op + " " + old)
        tgt["run"] = tgt["run"].replace(old, new)
    elif op in ("if-replace", "if-delete", "env-set", "add-step"):
        kind = args[0]
        if kind == "probe":
            tgt = steps[probe[0]]
        else:
            tgt = next(s for s in steps if kind_cond[kind] in str(s.get("if", "")))
        if op == "if-replace":
            if args[1] not in str(tgt.get("if", "")):
                sys.exit("mutation did not apply: " + op + " " + args[1])
            tgt["if"] = str(tgt["if"]).replace(args[1], args[2])
        elif op == "if-delete":
            if "if" not in tgt:
                sys.exit("mutation did not apply: " + op)
            del tgt["if"]
        elif op == "env-set":
            before = dict(tgt.get("env") or {})
            env = dict(before)
            if args[2] == "__DEL__":
                env.pop(args[1], None)
            else:
                env[args[1]] = args[2]
            if env == before:
                sys.exit("mutation did not apply: " + op)
            tgt["env"] = env
        else:
            steps.append({
                "name": "Third-party writer",
                "uses": "actions/github-script@v7",
                "with": {"script": "core.setOutput('x', '${{ steps.%s.outputs.fill_verdict }}')" % steps[probe[0]]["id"]},
            })
    elif op == "status-add":
        s = steps[sentry[0]]
        old = " && 'ok' || 'error'"
        if old not in s["with"]["status"]:
            sys.exit("mutation did not apply: " + op)
        s["with"]["status"] = s["with"]["status"].replace(
            old, " || steps.%s.outputs.fill_verdict == 'PASS' && 'ok' || 'error'" % steps[probe[0]]["id"])
    elif op == "move-probe-first":
        st = steps.pop(probe[0])
        steps.insert(alarm[0], st)
    elif op == "move-sentry-last":
        steps.append(steps.pop(sentry[0]))
    elif op == "add-filing":
        steps.append({
            "name": "Second fill filing step",
            "if": "steps.%s.outputs.fill_verdict == 'FAIL'" % steps[probe[0]]["id"],
            "run": "gh issue create --title x --body y\n",
        })
    else:
        sys.exit("unknown op " + op)
    open(dst, "w").write(yaml.safe_dump(doc, sort_keys=False, width=10**9, allow_unicode=True))

if __name__ == "__main__":
    if sys.argv[1] == "facts":
        facts(sys.argv[2], sys.argv[3])
    elif sys.argv[1] == "mutate":
        mutate(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5:])
PY

# PATH-shimmed `gh`: logs argv, answers `issue list` from $GH_ISSUES PROJECTED to the fields named
# by --json (a field the workflow did not request reaches jq as absent, exactly as with the real
# gh), logs the body file of a create, REFUSES an issue search (a lookup must list by label, never
# search) and an issue list with no --json, and fails `issue close N` for every N in $GH_CLOSE_FAIL.
cat > "$SHIM/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_LOG"
case "$1 $2" in
  "issue list")
    [[ "${GH_LIST_FAIL:-0}" == "1" ]] && exit 1
    fields=""; prev=""
    for a in "$@"; do
      [[ "$a" == "--search" ]] && { echo "stub: --search refused" >&2; exit 64; }
      [[ "$prev" == "--json" ]] && fields="$a"
      prev="$a"
    done
    [[ -n "$fields" ]] || { echo "stub: issue list needs --json" >&2; exit 64; }
    printf '%s' "${GH_ISSUES:-[]}" | "$PY3" -I -c '
import json, sys
want = [k for k in sys.argv[1].split(",") if k]
print(json.dumps([{k: o[k] for k in want if k in o} for o in json.load(sys.stdin)]))
' "$fields" ;;
  "issue create")
    [[ "${GH_CREATE_FAIL:-0}" == "1" ]] && exit 1
    prev=""
    for a in "$@"; do
      if [[ "$prev" == "--body-file" ]]; then
        { printf 'BODY<<<\n'; cat "$a"; printf '\n>>>BODY\n'; } >> "$GH_LOG"
      fi
      prev="$a"
    done
    echo "https://github.com/o/r/issues/4242" ;;
  "issue close")
    [[ " ${GH_CLOSE_FAIL:-} " == *" $3 "* ]] && exit 1
    : ;;
  "issue comment"|"label create") : ;;
  *) echo "stub: unexpected gh $*" >&2; exit 64 ;;
esac
SH
chmod +x "$SHIM/gh"

fact() { local v; v="$(printf '%s\n' "$1" | sed -n "s/^$2=//p")" || v=""; printf '%s' "$v"; }

# extract <root-workflow> <outdir> -> facts on stdout
extract() {
  assert_fixture_dir "$2"
  mkdir -p "$2"
  python3 "$HELPERS/wf.py" facts "$1" "$2" 2>"$2/facts.err"
}

LIVE="$S/live"
FACTS="$(extract "$WF" "$LIVE")" || FACTS=""
if [[ "$(fact "$FACTS" FILL_STEPS)" == "" ]] || (( $(fact "$FACTS" FILL_STEPS) < 3 )); then
  # Own-dispatch floor, reported DIRECTLY: a parse that yields no fill steps would otherwise let
  # every assertion below run over nothing and exit 0.
  printf '[FATAL] %s fill-referencing step(s) found in %s, expected at least 3.\n' \
    "$(fact "$FACTS" FILL_STEPS)" "$WF" >&2
  exit 1
fi

# ── step runner ─────────────────────────────────────────────────────────────────────────────────
GH_LOG="$S/gh.log"
STEP_RC=0
PY3="$(command -v python3)" || PY3=""
# Test seam: ZOT_FILL_WIRING_RUN_WRAP (word-split on purpose) prefixes the whole step command, e.g.
# `timeout 1`. Always initialised here, never read from the ambient environment.
ZOT_FILL_WIRING_RUN_WRAP=""
# run_step <script> <workdir> <outfile> [VAR=val ...]: the runner default shell (`bash -e`, no
# pipefail of its own), a scrubbed env, the gh shim first on PATH. Sets STEP_RC. Never called in a
# $( ) capture, so the rc is real.
run_step() {
  local script="$1" work="$2" outf="$3"
  shift 3
  assert_fixture_dir "$work"
  assert_fixture_dir "$outf"
  : > "$GH_LOG"
  STEP_RC=0
  # shellcheck disable=SC2086
  ${ZOT_FILL_WIRING_RUN_WRAP} env -C "$work" -i "PATH=${SHIM}:${BASE_PATH}" "HOME=$S" "GH_LOG=$GH_LOG" "PY3=$PY3" "$@" \
    bash --noprofile --norc -e "$script" > "$outf" 2>&1 || STEP_RC=$?
}

# gho_last <file> <key>: the LAST value written for a key, which is what the runner keeps.
gho_last() { local v; v="$(sed -n "s/^$2=//p" "$1" | tail -n 1)" || v=""; printf '%s' "$v"; }

CASE_N=0
# probe_case <label> <rc|absent> <body (printf %b)> <alarm_exit> <want "VERDICT|DEFECT|STEPRC">
probe_case() {
  local label="$1" frc="$2" body="$3" aexit="$4" want="$5"
  CASE_N=$((CASE_N + 1))
  local w="$S/p$CASE_N"
  assert_fixture_dir "$w"
  mkdir -p "$w/scripts/followthroughs"
  : > "$w/gho.txt"
  : > "$w/summary.txt"
  if [[ "$frc" != "absent" ]]; then
    printf '%b' "$body" > "$w/body.txt"
    printf '#!/usr/bin/env bash\ncat "%s"\nexit %s\n' "$w/body.txt" "$frc" > "$w/scripts/followthroughs/zot-fill-rate-7341.sh"
  fi
  run_step "$LIVE/probe.sh" "$w" "$w/log.txt" \
    "GITHUB_OUTPUT=$w/gho.txt" "GITHUB_STEP_SUMMARY=$w/summary.txt" \
    "BETTERSTACK_QUERY_HOST=Qhost.Example.test" "BETTERSTACK_QUERY_USERNAME=u" \
    "BETTERSTACK_QUERY_PASSWORD=p" "ALARM_EXIT=$aexit"
  local v d
  v="$(gho_last "$w/gho.txt" fill_verdict)" || v=""
  d="$(gho_last "$w/gho.txt" fill_defect)" || d=""
  ck
  eq "$label" "$want" "${v}|${d}|${STEP_RC}"
}

H_PASS='zot-fill-rate[#7341]: PASS pcent=16 slope=-1.25pp/day proj14d=-1 first=18 last=16 median12=16 max12=16 span=29h samples=349 boot=46f08985 window=72h'
H_FAIL='zot-fill-rate[#7341]: FAIL pcent=40 slope=+8.00pp/day projects_85_in_5.6d_first=20_last=40_median12=40_max12=41_span=60h samples=700 boot=46f08985 window=72h'
H_SPAN='zot-fill-rate[#7341]: TRANSIENT span=3.0h_of_history_under_24h_pcent=16 samples=40 boot=46f08985 window=72h'
H_RECL='zot-fill-rate[#7341]: TRANSIENT reclaim_at_sample_30_left_5_samples_under_12 samples=40 boot=46f08985 window=72h'
H_STALE='zot-fill-rate[#7341]: TRANSIENT newest_sample_95min_old_over_30min_pcent=16 samples=349 boot=46f08985 window=72h'
H_FEW_LOW='zot-fill-rate[#7341]: TRANSIENT too_few_samples n=3 rows_env=3 rows_scoped=3 boot=46f08985 window=72h'
# H_FEW_HIGH and H_FEW_12 are headers the script CANNOT emit: it prints too_few_samples only when
# rows_scoped == n and n < 12 (scripts/followthroughs/zot-fill-rate-7341.sh, the emit site), so a
# rows_scoped of 12 or more never appears. They are tripwires against a future script change, kept
# so the 12 boundary of the benign test stays pinned if that invariant ever breaks.
H_FEW_HIGH='zot-fill-rate[#7341]: TRANSIENT too_few_samples n=3 rows_env=40 rows_scoped=40 boot=46f08985 window=72h'
H_FEW_12='zot-fill-rate[#7341]: TRANSIENT too_few_samples n=3 rows_env=12 rows_scoped=12 boot=46f08985 window=72h'
H_FEW_11='zot-fill-rate[#7341]: TRANSIENT too_few_samples n=3 rows_env=11 rows_scoped=11 boot=46f08985 window=72h'
H_FEW_08='zot-fill-rate[#7341]: TRANSIENT too_few_samples n=3 rows_env=8 rows_scoped=08 boot=46f08985 window=72h'
H_FEW_NONE='zot-fill-rate[#7341]: TRANSIENT too_few_samples n=3 rows_env=3 boot=46f08985 window=72h'
H_QRC='zot-fill-rate[#7341]: TRANSIENT query_rc=3'
H_NOEMIT='zot-fill-rate[#7341]: TRANSIENT no_emission_rows rows_returned=0 window=72h'
H_NOBOOT='zot-fill-rate[#7341]: TRANSIENT no_real_boot_id rows_env=40 window=72h'

echo "zot-fill-rate-standing-wiring.test.sh (root: ${ROOT})"

# ── T1 Sentry isolation ─────────────────────────────────────────────────────────────────────────
echo "--- T1 Sentry isolation"
ck; eq "T1 the Sentry status expression references exactly the alarm step (property, not text)" \
  "$(fact "$FACTS" ALARM_ID)" "$(fact "$FACTS" SENTRY_STATUS_IDS)"
ck; eq "T1 the Sentry check-in is still if: always()" "always()" "$(fact "$FACTS" SENTRY_IF)"
ck; eq "T1 the job timeout is unchanged at 8 minutes" "8" "$(fact "$FACTS" JOB_TIMEOUT)"
PT="$(fact "$FACTS" PROBE_TIMEOUT)"
ck; if [[ "$PT" =~ ^[0-9]+$ ]] && (( PT >= 1 && PT <= 3 )); then pass "T1 the probe step timeout is at most 3 minutes"; else fail "T1 the probe step timeout is at most 3 minutes (got [$PT])"; fi
ck; eq "T1 exactly one probe step, one alarm step and one Sentry check-in" "1|1|1" \
  "$(fact "$FACTS" N_PROBE)|$(fact "$FACTS" N_ALARM)|$(fact "$FACTS" N_SENTRY)"
ck; eq "T1 exactly three fill filing steps (FAIL, probe defect, PASS close), each of one kind" "3|1|1|1" \
  "$(fact "$FACTS" N_FILING)|$(fact "$FACTS" N_FAIL)|$(fact "$FACTS" N_DEFECT)|$(fact "$FACTS" N_PASS)"

PID="$(fact "$FACTS" PROBE_ID)"; AID="$(fact "$FACTS" ALARM_ID)"
ck; eq "T1 exactly four steps reference the fill outputs or ci/zot-fill-rate by any key (run, uses, with, env, if)" "4" "$(fact "$FACTS" FILL_STEPS)"
ck; eq "T1 the probe step if: is exactly the reviewed literal" '${{ !cancelled() }}' "$(fact "$FACTS" IF_probe)"
ck; eq "T1 the FAIL step if: is exactly the reviewed literal" "\${{ !cancelled() && steps.${PID}.outputs.fill_verdict == 'FAIL' }}" "$(fact "$FACTS" IF_fail)"
ck; eq "T1 the probe-defect step if: is exactly the reviewed literal" "\${{ !cancelled() && steps.${PID}.outputs.fill_defect == 'true' }}" "$(fact "$FACTS" IF_defect)"
ck; eq "T1 the PASS close step if: is exactly the reviewed literal" "\${{ !cancelled() && steps.${PID}.outputs.fill_verdict == 'PASS' }}" "$(fact "$FACTS" IF_pass)"
ENV_REPO='GH_REPO=${{ github.repository }} ; GH_TOKEN=${{ github.token }} ; RUN_URL=${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}'
ck; eq "T1 the probe step env is exactly the reviewed key set and sources" "ALARM_EXIT=\${{ steps.${AID}.outputs.exit_code }} ; BETTERSTACK_QUERY_HOST=\${{ secrets.BETTERSTACK_QUERY_HOST }} ; BETTERSTACK_QUERY_PASSWORD=\${{ secrets.BETTERSTACK_QUERY_PASSWORD }} ; BETTERSTACK_QUERY_USERNAME=\${{ secrets.BETTERSTACK_QUERY_USERNAME }}" "$(fact "$FACTS" ENV_probe)"
ck; eq "T1 the FAIL step env is exactly the reviewed key set and sources" "FILL_LINE=\${{ steps.${PID}.outputs.fill_line }} ; ${ENV_REPO}" "$(fact "$FACTS" ENV_fail)"
ck; eq "T1 the probe-defect step env is exactly the reviewed key set and sources" "FILL_LINE=\${{ steps.${PID}.outputs.fill_line }} ; ${ENV_REPO}" "$(fact "$FACTS" ENV_defect)"
ck; eq "T1 the PASS close step env is exactly the reviewed key set and sources" "${ENV_REPO}" "$(fact "$FACTS" ENV_pass)"
ck; eq "T1 the probe step has exactly the reviewed key set (no shell, continue-on-error, working-directory, uses, with)" "env,id,if,name,run,timeout-minutes" "$(fact "$FACTS" KEYS_probe)"
ck; eq "T1 the FAIL step has exactly the reviewed key set (no id, shell, continue-on-error, working-directory)" "env,if,name,run" "$(fact "$FACTS" KEYS_fail)"
ck; eq "T1 the probe-defect step has exactly the reviewed key set (no id, shell, continue-on-error, working-directory)" "env,if,name,run" "$(fact "$FACTS" KEYS_defect)"
ck; eq "T1 the PASS close step has exactly the reviewed key set (no id, shell, continue-on-error, working-directory)" "env,if,name,run" "$(fact "$FACTS" KEYS_pass)"
ck; eq "T1 no fill step declares shell: (the runner default bash -e applies)" "0" "$(fact "$FACTS" FILL_SHELL_STEPS)"
ck; eq "T1 no fill step body switches an option off again with set +" "0" "$(fact "$FACTS" FILL_SET_PLUS)"
ck; eq "T1 the probe step's first statement is set -uo pipefail" "set -uo pipefail" "$(fact "$FACTS" FIRST_probe)"
ck; eq "T1 the FAIL step's first statement is set -euo pipefail" "set -euo pipefail" "$(fact "$FACTS" FIRST_fail)"
ck; eq "T1 the probe-defect step's first statement is set -euo pipefail" "set -euo pipefail" "$(fact "$FACTS" FIRST_defect)"
ck; eq "T1 the PASS close step's first statement is set -euo pipefail" "set -euo pipefail" "$(fact "$FACTS" FIRST_pass)"
ck; eq "T1 the alarm job declares exactly the reviewed keys (no env, defaults, continue-on-error, permissions)" "outputs,runs-on,steps,timeout-minutes" "$(fact "$FACTS" JOB_KEYS)"
ck; eq "T1 the workflow declares exactly the reviewed top-level keys (no env, defaults)" "concurrency,jobs,name,on,permissions" "$(fact "$FACTS" TOP_KEYS)"
ck; eq "T1 the workflow permissions are exactly the reviewed block" "contents=read ; issues=write" "$(fact "$FACTS" WF_PERMS)"
ck; eq "T1 the alarm job outputs are exactly the reviewed block" 'inventory_tracker=${{ steps.fire.outputs.inventory_tracker }}' "$(fact "$FACTS" JOB_OUTPUTS)"
ck; eq "T1 nothing outside the alarm job steps references the fill step or its outputs" "0" "$(fact "$FACTS" FILL_OUTSIDE)"
ck; eq "T1 no step references a step id that does not exist" "" "$(fact "$FACTS" DANGLING_STEP_IDS)"
ck; eq "T1 every steps.<probe>.outputs key referenced anywhere is written by the probe, and three are" "|3" "$(fact "$FACTS" FILL_UNWRITTEN_REFS)|$(fact "$FACTS" FILL_REFS_N)"
ck; eq "T1 every steps.<alarm>.outputs key the probe reads exists, and it reads one" "|1" "$(fact "$FACTS" PROBE_ALARM_REFS_MISSING)|$(fact "$FACTS" PROBE_ALARM_REFS_N)"

# ── T2 ordering ─────────────────────────────────────────────────────────────────────────────────
echo "--- T2 ordering"
A_IDX="$(fact "$FACTS" ALARM_IDX)"; EF_MIN="$(fact "$FACTS" EXISTING_FILING_MIN)"
EF_MAX="$(fact "$FACTS" EXISTING_FILING_MAX)"; S_IDX="$(fact "$FACTS" SENTRY_IDX)"
P_IDX="$(fact "$FACTS" PROBE_IDX)"; F_MIN="$(fact "$FACTS" FILING_MIN)"
ck; if (( A_IDX < EF_MIN )); then pass "T2 the alarm step precedes every existing filing step"; else fail "T2 the alarm step precedes every existing filing step ($A_IDX vs $EF_MIN)"; fi
ck; if (( EF_MAX < S_IDX )); then pass "T2 every existing filing step precedes the Sentry check-in"; else fail "T2 every existing filing step precedes the Sentry check-in ($EF_MAX vs $S_IDX)"; fi
ck; if (( A_IDX < P_IDX )); then pass "T2 the fill probe follows the alarm step"; else fail "T2 the fill probe follows the alarm step ($A_IDX vs $P_IDX)"; fi
ck; if (( S_IDX < P_IDX )); then pass "T2 the Sentry check-in precedes the fill probe"; else fail "T2 the Sentry check-in precedes the fill probe ($S_IDX vs $P_IDX)"; fi
ck; if (( P_IDX < F_MIN )); then pass "T2 the fill probe precedes every fill filing step"; else fail "T2 the fill probe precedes every fill filing step ($P_IDX vs $F_MIN)"; fi

# ── T3 probe classification and defect flag (EXECUTED) ──────────────────────────────────────────
echo "--- T3 probe classification"
probe_case "T3 rc 0 with a PASS header -> PASS, no defect, step ok" 0 "${H_PASS}\n" 0 "PASS|false|0"
probe_case "T3 rc 1 with a FAIL header -> FAIL, no defect, step ok" 1 "${H_FAIL}\nThe store is refilling.\n  ATTRIB_SENTINEL_1 lead line\n" 0 "FAIL|false|0"
probe_case "T3 rc 2 with a TRANSIENT header -> TRANSIENT (benign span), no defect" 2 "${H_SPAN}\nTRANSIENT: the store's state could not be established. NOT a pass.\n" 0 "TRANSIENT|false|0"
probe_case "T3 rc 0 with no header -> UNEVALUATED, defect, step fails" 0 "all good\n" 0 "UNEVALUATED|true|1"
FL="$(gho_last "$S/p${CASE_N}/gho.txt" fill_line)" || FL=""
ck; eq "T3 the UNEVALUATED fill_line names the exit code and header count" "UNEVALUATED rc=0 headers=0" "$FL"
probe_case "T3 rc 2 with only TRANSIENT text and no header (precondition exit) -> UNEVALUATED" 2 "TRANSIENT: python3 is not on PATH\n" 0 "UNEVALUATED|true|1"
probe_case "T3 rc 0 with a FAIL header (disagreement) -> UNEVALUATED" 0 "${H_FAIL}\n" 0 "UNEVALUATED|true|1"
probe_case "T3 rc 1 with a PASS header (disagreement) -> UNEVALUATED" 1 "${H_PASS}\n" 0 "UNEVALUATED|true|1"
probe_case "T3 rc 3 with a PASS header -> UNEVALUATED (exit outside the contract)" 3 "${H_PASS}\n" 0 "UNEVALUATED|true|1"
probe_case "T3 rc 3 with a TRANSIENT header -> UNEVALUATED (the default arm is not TRANSIENT)" 3 "${H_SPAN}\n" 0 "UNEVALUATED|true|1"
probe_case "T3 rc 127 (script absent) -> UNEVALUATED" absent "" 0 "UNEVALUATED|true|1"
probe_case "T3 two column-0 headers -> UNEVALUATED (no late spoof picks the verdict)" 0 "${H_PASS}\n${H_FAIL}\n" 0 "UNEVALUATED|true|1"
probe_case "T3 a header-looking line after a bare carriage return is not a header (PASS stands)" 0 "${H_PASS}\n\r${H_FAIL}\n" 0 "PASS|false|0"
probe_case "T3 TRANSIENT reclaim_at_sample_ is benign" 2 "${H_RECL}\n" 0 "TRANSIENT|false|0"
probe_case "T3 TRANSIENT newest_sample_ is benign" 2 "${H_STALE}\n" 0 "TRANSIENT|false|0"
probe_case "T3 TRANSIENT too_few_samples with rows_scoped below 12 is benign" 2 "${H_FEW_LOW}\n" 0 "TRANSIENT|false|0"
probe_case "T3 TRANSIENT too_few_samples with rows_scoped of 12 or more is a defect" 2 "${H_FEW_HIGH}\n" 0 "TRANSIENT|true|0"
probe_case "T3 TRANSIENT query_rc= is a defect while the zot leg is not failing" 2 "${H_QRC}\n" 0 "TRANSIENT|true|0"
probe_case "T3 TRANSIENT no_emission_rows is a defect" 2 "${H_NOEMIT}\n" 0 "TRANSIENT|true|0"
probe_case "T3 TRANSIENT no_real_boot_id is a defect" 2 "${H_NOBOOT}\n" 0 "TRANSIENT|true|0"
probe_case "T3 alarm exit 2 suppresses the TRANSIENT defect (Sentry already pages for it)" 2 "${H_QRC}\n" 2 "TRANSIENT|false|0"
probe_case "T3 alarm exit 3 (PRODUCER_SILENT) suppresses the TRANSIENT defect" 2 "${H_QRC}\n" 3 "TRANSIENT|false|0"
probe_case "T3 alarm exit 4 (INGEST_DARK) suppresses the TRANSIENT defect" 2 "${H_QRC}\n" 4 "TRANSIENT|false|0"
probe_case "T3 alarm exit 1 (FIRE) does not suppress a non-benign TRANSIENT defect" 2 "${H_QRC}\n" 1 "TRANSIENT|true|0"
probe_case "T3 alarm exit 3 does NOT suppress UNEVALUATED" 3 "${H_PASS}\n" 3 "UNEVALUATED|true|1"
probe_case "T3 alarm exit 4 does NOT suppress UNEVALUATED" 3 "${H_PASS}\n" 4 "UNEVALUATED|true|1"
probe_case "T3 TRANSIENT too_few_samples with rows_scoped of exactly 11 is benign" 2 "${H_FEW_11}\n" 0 "TRANSIENT|false|0"
probe_case "T3 TRANSIENT too_few_samples with rows_scoped of exactly 12 is a defect" 2 "${H_FEW_12}\n" 0 "TRANSIENT|true|0"
probe_case "T3 TRANSIENT too_few_samples with a zero-padded rows_scoped=08 is benign (decimal, not octal)" 2 "${H_FEW_08}\n" 0 "TRANSIENT|false|0"
probe_case "T3 TRANSIENT too_few_samples with no rows_scoped is a defect" 2 "${H_FEW_NONE}\n" 0 "TRANSIENT|true|0"
probe_case "T3 a PASSED header is not a header (UNEVALUATED)" 0 "zot-fill-rate[#7341]: PASSED pcent=16\n" 0 "UNEVALUATED|true|1"
probe_case "T3 an indented header is not a header (UNEVALUATED)" 0 " ${H_PASS}\n" 0 "UNEVALUATED|true|1"
probe_case "T3 a header carrying U+2028, a control byte, NEL and a BOM is still a PASS" 0 'zot-fill-rate[#7341]: PASS x\xe2\x80\xa8y\x01z\xc2\x85w\xef\xbb\xbfv\n' 0 "PASS|false|0"
FL="$(gho_last "$S/p${CASE_N}/gho.txt" fill_line)" || FL=""
ck; eq "T3 fill_line carries none of the U+2028, control, NEL or BOM bytes" "PASS xyzwv" "$FL"
probe_case "T3 alarm exit 2 does NOT suppress UNEVALUATED" 3 "${H_PASS}\n" 2 "UNEVALUATED|true|1"
probe_case "T3 an unset alarm exit is not 2, 3 or 4: a non-benign TRANSIENT is still a defect" 2 "${H_QRC}\n" "" "TRANSIENT|true|0"

# Log hygiene: workflow commands in script output must reach the log neutralized.
HOSTILE="${H_FAIL}\n::error::HOSTILE_INJECT\n\r::error::HOSTILE_CR\n::stop-commands::x\nleak.betterstackdata.com\n"
probe_case "T3 a FAIL with hostile body lines is still classified FAIL" 1 "$HOSTILE" 0 "FAIL|false|0"
HW="$S/p${CASE_N}"
n_inj="$(tr '\r' '\n' < "$HW/log.txt" | grep -c '^::error::HOSTILE_' )" || n_inj=0
ck; eq "T3 no log line (CR treated as a line break) starts a workflow command from script output" "0" "$n_inj"
n_stop="$(tr '\r' '\n' < "$HW/log.txt" | grep -c '^::stop-commands::')" || n_stop=0
ck; eq "T3 a stop-commands line from script output is neutralized" "0" "$n_stop"
n_cr="$(tr -cd '\r' < "$HW/log.txt" | wc -c | tr -d ' ')" || n_cr=""
ck; eq "T3 carriage returns are stripped from the log" "0" "$n_cr"
n_vis="$(grep -c '^| ::error::HOSTILE_INJECT' "$HW/log.txt")" || n_vis=0
ck; eq "T3 script output lines are echoed behind a visible pipe prefix" "1" "$n_vis"
n_host="$(grep -c 'leak.betterstackdata.com' "$HW/log.txt")" || n_host=0
ck; eq "T3 a *.betterstackdata.com hostname in script output is scrubbed from the log" "0" "$n_host"
n_mask="$(grep -c '^::add-mask::qhost.example.test$' "$HW/log.txt")" || n_mask=0
ck; eq "T3 the lowercased query host is masked" "1" "$n_mask"

# Published line hygiene: prefix removed, # @ backtick deleted, capped at 400.
BIGTAIL="$(head -c 10000 /dev/zero | tr '\0' 'A')" || BIGTAIL=""
BIGB="$(head -c 10000 /dev/zero | tr '\0' 'B')" || BIGB=""
probe_case "T3 a hostile header is classified PASS" 0 "zot-fill-rate[#7341]: PASS pcent=16 \`tick\` @octocat #1 [x](http://e.test) \$(id) ${BIGTAIL}\n" 0 "PASS|false|0"
FL="$(gho_last "$S/p${CASE_N}/gho.txt" fill_line)" || FL=""
ck; eq "T3 fill_line drops the script-name prefix and the hash, at-sign and backtick characters" "PASS pcent=16 tick octocat 1 [x](http://e.test) \$(id) AAAA" "${FL:0:58}"
ck; if (( ${#FL} <= 400 )); then pass "T3 fill_line is capped at 400 characters"; else fail "T3 fill_line is capped at 400 characters (got ${#FL})"; fi

# A 3-minute step timeout must still leave a probe-defect verdict behind: the pessimistic outputs
# are written before anything that can hang. (A JOB-level timeout or a cancellation files nothing.)
CASE_N=$((CASE_N + 1))
TW="$S/p$CASE_N"
assert_fixture_dir "$TW"
mkdir -p "$TW/scripts/followthroughs"
: > "$TW/gho.txt"
: > "$TW/summary.txt"
printf '#!/usr/bin/env bash\nsleep 3\n' > "$TW/scripts/followthroughs/zot-fill-rate-7341.sh"
ZOT_FILL_WIRING_RUN_WRAP="timeout -k 2 1"
run_step "$LIVE/probe.sh" "$TW" "$TW/log.txt" \
  "GITHUB_OUTPUT=$TW/gho.txt" "GITHUB_STEP_SUMMARY=$TW/summary.txt" \
  "BETTERSTACK_QUERY_HOST=Qhost.Example.test" "BETTERSTACK_QUERY_USERNAME=u" \
  "BETTERSTACK_QUERY_PASSWORD=p" "ALARM_EXIT=0"
ZOT_FILL_WIRING_RUN_WRAP=""
ck; eq "T3 a probe that outlives its step timeout leaves UNEVALUATED, defect=true and a line behind (rc 124)" \
  "UNEVALUATED|true|probe step did not complete|124" \
  "$(gho_last "$TW/gho.txt" fill_verdict)|$(gho_last "$TW/gho.txt" fill_defect)|$(gho_last "$TW/gho.txt" fill_line)|$STEP_RC"

# ── T4 filing (EXECUTED against the gh shim) ────────────────────────────────────────────────────
echo "--- T4 filing"
FAIL_TITLE="$(fact "$FACTS" FAIL_TITLE)"
DEFECT_TITLE="$(fact "$FACTS" DEFECT_TITLE)"
ck; eq "T4 the FAIL step title" "[ci/zot-fill-rate] Registry store fill rate projects a breach" "$FAIL_TITLE"
ck; eq "T4 the probe-defect step title" "[ci/zot-fill-rate] Registry fill-rate probe defect" "$DEFECT_TITLE"
ck; eq "T4 the PASS close step names both titles (parity with the filing steps)" "1" "$(fact "$FACTS" PASS_TITLES_OK)"
ck; eq "T4 no filing step passes BETTERSTACK_* into its env" "0" "$(fact "$FACTS" BETTERSTACK_IN_FILING)"

FILL_LINE_OK="FAIL pcent=40 slope=+8.00pp/day projects_85_in_5.6d samples=700 boot=46f08985"
filing_case() { # filing_case <name> <script> <issues-json> [VAR=val ...] -> sets $FW (workdir)
  local name="$1" script="$2" issues="$3"
  shift 3
  FW="$S/f-$name"
  assert_fixture_dir "$FW"
  mkdir -p "$FW"
  : > "$FW/gho.txt"
  run_step "$script" "$FW" "$FW/log.txt" \
    "GITHUB_OUTPUT=$FW/gho.txt" "GH_TOKEN=t" "GH_REPO=o/r" \
    "RUN_URL=https://github.com/o/r/actions/runs/1" "GH_ISSUES=$issues" "$@"
}
count_in_log() { local n; n="$(grep -c -- "$1" "$GH_LOG")" || n=0; printf '%s' "$n"; }
count_fixed() { local n; n="$(grep -c -F -- "$1" "$GH_LOG")" || n=0; printf '%s' "$n"; }

# lookup_json: the --json value of every `gh issue list` the last step ran, joined by ";".
lookup_json() { grep '^issue list ' "$GH_LOG" | sed -n 's/.* --json \([^ ]*\).*/\1/p' | paste -sd';' -; }

# lookup_flags: "<lookups>|<missing label>|<missing --state open>|<missing --limit 100>|<--search>"
# over every `gh issue list` the last step ran, so a dropped flag in ANY lookup is visible.
lookup_flags() {
  local n nl ns nm sr
  n="$(grep -c '^issue list ' "$GH_LOG")" || n=0
  nl="$(grep '^issue list ' "$GH_LOG" | grep -vcE -- '--label ci/zot-fill-rate( |$)')" || nl=0
  ns="$(grep '^issue list ' "$GH_LOG" | grep -vcE -- '--state open( |$)')" || ns=0
  nm="$(grep '^issue list ' "$GH_LOG" | grep -vcE -- '--limit 100( |$)')" || nm=0
  sr="$(grep -c -F -- '--search' "$GH_LOG")" || sr=0
  printf '%s|%s|%s|%s|%s' "$n" "$nl" "$ns" "$nm" "$sr"
}

filing_case failnew "$LIVE/fail.sh" "[]" "FILL_LINE=$FILL_LINE_OK"
ck; eq "T4 FAIL, no tracker: the step exits 0" "0" "$STEP_RC"
ck; eq "T4 FAIL, no tracker: one label create then one issue create" "1|1" "$(count_in_log '^label create ci/zot-fill-rate')|$(count_in_log '^issue create ')"
LBL_LINE="$(grep -n '^label create' "$GH_LOG" | head -1 | cut -d: -f1)" || LBL_LINE=0
CRE_LINE="$(grep -n '^issue create' "$GH_LOG" | head -1 | cut -d: -f1)" || CRE_LINE=0
ck; if [[ -n "$LBL_LINE" && -n "$CRE_LINE" ]] && (( LBL_LINE < CRE_LINE )); then pass "T4 the label is created before the issue"; else fail "T4 the label is created before the issue ($LBL_LINE vs $CRE_LINE)"; fi
CREATE_LINE="$(grep '^issue create' "$GH_LOG")" || CREATE_LINE=""
ck; eq "T4 the issue carries all four labels" "4" "$(printf '%s' "$CREATE_LINE" | grep -o -- '--label \(ci/zot-fill-rate\|action-required\|observability\|domain/engineering\)' | wc -l | tr -d ' ')"
ck; eq "T4 the issue is created under the FAIL title" "1" "$(count_fixed "--title $FAIL_TITLE")"
ck; eq "T4 every lookup lists by the label and none uses --search" "0" "$(count_fixed '--search')"
n_list_nolabel="$(grep '^issue list' "$GH_LOG" | grep -vc -- '--label ci/zot-fill-rate')" || n_list_nolabel=0
ck; eq "T4 every issue lookup carries --label ci/zot-fill-rate" "0" "$n_list_nolabel"
ck; eq "T4 FAIL: both lookups (tracker, stale defect) list open issues by label with --limit 100 and no --search" "2|0|0|0|0" "$(lookup_flags)"
ck; eq "T4 FAIL: both lookups request exactly --json number,title" "number,title;number,title" "$(lookup_json)"
BODY="$(sed -n '/^BODY<<</,/^>>>BODY/p' "$GH_LOG")" || BODY=""
ck; eq "T4 the body holds the verdict line" "1" "$(printf '%s\n' "$BODY" | grep -c -F -- "$FILL_LINE_OK")"
ck; eq "T4 the body holds the reproduce command" "1" "$(printf '%s\n' "$BODY" | grep -c -F -- 'doppler run -p soleur -c prd_terraform -- bash scripts/followthroughs/zot-fill-rate-7341.sh')"
ck; eq "T4 the body holds the run link" "1" "$(printf '%s\n' "$BODY" | grep -c -F -- 'https://github.com/o/r/actions/runs/1')"
ck; eq "T4 the body names #7521 and not a closing keyword for it" "0" "$(printf '%s\n' "$BODY" | grep -ci -E '(close[sd]?|fix(es|ed)?|resolve[sd]?) #7521')"

filing_case failold "$LIVE/fail.sh" "[{\"number\":77,\"title\":\"${FAIL_TITLE}\"}]" "FILL_LINE=$FILL_LINE_OK"
ck; eq "T4 FAIL, tracker exists: comment on it, create nothing and close nothing (the tracker is not a stale defect)" "1|0|0" "$(count_in_log '^issue comment 77 ')|$(count_in_log '^issue create ')|$(count_in_log '^issue close ')"

filing_case faildedupe "$LIVE/fail.sh" "[]" "FILL_LINE=$FILL_LINE_OK" "GH_LIST_FAIL=1"
ck; eq "T4 FAIL, dedupe query fails: proceeds to create (the documented trade) and the step exits 0" "1|0" "$(count_in_log '^issue create ')|$STEP_RC"
ck; eq "T4 FAIL, dedupe query fails: the failure is annotated (needs the body's own pipefail, the harness adds none)" "1" "$(grep -c -F '::error::zot-fill-rate: dedupe query failed' "$FW/log.txt")"

# A sibling issue under the same label must not be mistaken for this class.
filing_case failsibling "$LIVE/fail.sh" "[{\"number\":78,\"title\":\"${DEFECT_TITLE}\"}]" "FILL_LINE=$FILL_LINE_OK"
ck; eq "T4 FAIL: an open probe-defect issue is not the FAIL tracker (creates), and is then closed" "1|1" "$(count_in_log '^issue create ')|$(count_in_log '^issue close 78 ')"
filing_case failnodefect "$LIVE/fail.sh" "[]" "FILL_LINE=$FILL_LINE_OK"
ck; eq "T4 FAIL with no open probe-defect issue closes nothing" "0" "$(count_in_log '^issue close ')"

HOSTILE_LINE="FAIL \$(id) \`id\` @octocat #1 [x](http://e.test) ::error::x ${BIGB}"
filing_case failhostile "$LIVE/fail.sh" "[]" "FILL_LINE=$HOSTILE_LINE"
BODY="$(sed -n '/^BODY<<</,/^>>>BODY/p' "$GH_LOG")" || BODY=""
ck; eq "T4 a hostile FILL_LINE reaches the body with no at-sign mention and no issue reference" "0" "$(printf '%s\n' "$BODY" | grep -c -E '@octocat|#1([^0-9]|$)')"
ck; eq "T4 a hostile FILL_LINE is not executed (the substitution stays literal text)" "0" "$(grep -c 'uid=' "$GH_LOG")"
ck; if (( $(printf '%s' "$BODY" | wc -c) < 4000 )); then pass "T4 a 10 KB FILL_LINE tail is capped in the body"; else fail "T4 a 10 KB FILL_LINE tail is capped in the body"; fi
filing_case failhostile2 "$LIVE/fail.sh" "[{\"number\":77,\"title\":\"${FAIL_TITLE}\"}]" "FILL_LINE=$HOSTILE_LINE"
CMT="$(grep '^issue comment' "$GH_LOG")" || CMT=""
ck; eq "T4 a hostile FILL_LINE reaches the comment with no at-sign mention and no issue reference" "0" "$(printf '%s\n' "$CMT" | grep -c -E '@octocat|#1([^0-9]|$)')"
ck; if (( $(printf '%s' "$CMT" | wc -c) < 1000 )); then pass "T4 a 10 KB FILL_LINE tail is capped in the comment"; else fail "T4 a 10 KB FILL_LINE tail is capped in the comment"; fi

# The probe-defect step carries its own re-strip and 400 cap, so it gets the same hostile line.
filing_case defhostile "$LIVE/defect.sh" "[]" "FILL_LINE=$HOSTILE_LINE"
BODY="$(sed -n '/^BODY<<</,/^>>>BODY/p' "$GH_LOG")" || BODY=""
ck; eq "T4 defect: a hostile FILL_LINE reaches the body with no at-sign mention and no issue reference" "0" "$(printf '%s\n' "$BODY" | grep -c -E '@octocat|#1([^0-9]|$)')"
ck; eq "T4 defect: a hostile FILL_LINE is not executed (the substitution stays literal text)" "0" "$(grep -c 'uid=' "$GH_LOG")"
ck; if (( $(printf '%s' "$BODY" | wc -c) < 4000 )); then pass "T4 defect: a 10 KB FILL_LINE tail is capped in the body"; else fail "T4 defect: a 10 KB FILL_LINE tail is capped in the body"; fi
filing_case defhostile2 "$LIVE/defect.sh" "[{\"number\":91,\"title\":\"${DEFECT_TITLE}\"}]" "FILL_LINE=$HOSTILE_LINE"
CMT="$(grep '^issue comment' "$GH_LOG")" || CMT=""
ck; eq "T4 defect: a hostile FILL_LINE reaches the comment with no at-sign mention and no issue reference" "0" "$(printf '%s\n' "$CMT" | grep -c -E '@octocat|#1([^0-9]|$)')"
ck; if (( $(printf '%s' "$CMT" | wc -c) < 1000 )); then pass "T4 defect: a 10 KB FILL_LINE tail is capped in the comment"; else fail "T4 defect: a 10 KB FILL_LINE tail is capped in the comment"; fi

# End to end: the probe's published line feeds the FAIL step; nothing else of the script output
# travels with it.
probe_case "T4 chain: a FAIL probe run" 1 "${H_FAIL}\nThe store is refilling.\n  ATTRIB_SENTINEL_2 lead line\n" 0 "FAIL|false|0"
CHAIN_LINE="$(gho_last "$S/p${CASE_N}/gho.txt" fill_line)" || CHAIN_LINE=""
filing_case chain "$LIVE/fail.sh" "[]" "FILL_LINE=$CHAIN_LINE"
BODY="$(sed -n '/^BODY<<</,/^>>>BODY/p' "$GH_LOG")" || BODY=""
ck; eq "T4 chain: the body carries the measured line and none of the script's other output" "1|0" \
  "$(printf '%s\n' "$BODY" | grep -c -F 'projects_85_in_5.6d')|$(printf '%s\n' "$BODY" | grep -c 'ATTRIB_SENTINEL_2')"

filing_case defnew "$LIVE/defect.sh" "[]" "FILL_LINE=UNEVALUATED rc=0 headers=0"
ck; eq "T4 defect, no tracker: label then one create under the defect title with four labels" "1|1|4" \
  "$(count_in_log '^label create ci/zot-fill-rate')|$(count_fixed "--title $DEFECT_TITLE")|$(grep '^issue create' "$GH_LOG" | grep -o -- '--label \(ci/zot-fill-rate\|action-required\|observability\|domain/engineering\)' | wc -l | tr -d ' ')"
BODY="$(sed -n '/^BODY<<</,/^>>>BODY/p' "$GH_LOG")" || BODY=""
ck; eq "T4 the defect body holds the cause line, the reproduce command and the run link" "1|1|1" \
  "$(printf '%s\n' "$BODY" | grep -c -F 'UNEVALUATED rc=0')|$(printf '%s\n' "$BODY" | grep -c -F 'bash scripts/followthroughs/zot-fill-rate-7341.sh')|$(printf '%s\n' "$BODY" | grep -c -F 'actions/runs/1')"
ck; eq "T4 defect, no tracker: its one lookup lists open issues by label with --limit 100 and no --search" "1|0|0|0|0" "$(lookup_flags)"
ck; eq "T4 defect: its one lookup requests exactly --json number,title" "number,title" "$(lookup_json)"
filing_case defold "$LIVE/defect.sh" "[{\"number\":90,\"title\":\"${FAIL_TITLE}\"},{\"number\":91,\"title\":\"${DEFECT_TITLE}\"}]" "FILL_LINE=UNEVALUATED rc=0 headers=0"
ck; eq "T4 defect, tracker exists (the FAIL issue listed FIRST): comment on the defect issue only and create nothing" "1|0|0" "$(count_in_log '^issue comment 91 ')|$(count_in_log '^issue comment 90 ')|$(count_in_log '^issue create ')"
filing_case defdedupe "$LIVE/defect.sh" "[]" "FILL_LINE=x" "GH_LIST_FAIL=1"
ck; eq "T4 defect, dedupe query fails: proceeds to create" "1" "$(count_in_log '^issue create ')"
ck; eq "T4 defect, dedupe query fails: the failure is annotated (needs the body's own pipefail, the harness adds none)" "1" "$(grep -c -F '::error::zot-fill-rate-defect: dedupe query failed' "$FW/log.txt")"

# ── T5 PASS close hysteresis (EXECUTED) ─────────────────────────────────────────────────────────
echo "--- T5 PASS close"
ago() { date -u -d "$1 hours ago" '+%Y-%m-%dT%H:%M:%SZ'; }
ago_min() { date -u -d "$1 minutes ago" '+%Y-%m-%dT%H:%M:%SZ'; }
T5_5H="$(ago 5)"; T5_7H="$(ago 7)"; T5_30H="$(ago 30)"; T5_1M="$(ago_min 1)"
filing_case pass5h "$LIVE/pass.sh" "[{\"number\":50,\"title\":\"${FAIL_TITLE}\",\"updatedAt\":\"${T5_5H}\"}]"
ck; eq "T5 a tracker updated 5 h ago is not closed (hysteresis)" "0|0" "$(count_in_log '^issue close ')|$STEP_RC"
filing_case pass7h "$LIVE/pass.sh" "[{\"number\":51,\"title\":\"${FAIL_TITLE}\",\"updatedAt\":\"${T5_7H}\"}]"
ck; eq "T5 a tracker updated 7 h ago is closed with a comment" "1|1" "$(count_in_log '^issue close 51 .*--comment')|$(count_in_log '^issue close ')"
ck; eq "T5 the PASS step does ONE lookup (open, by label, --limit 100, no --search) for both titles" "1|0|0|0|0" "$(lookup_flags)"
ck; eq "T5 the PASS lookup requests exactly --json number,title,updatedAt" "number,title,updatedAt" "$(lookup_json)"
filing_case passnone "$LIVE/pass.sh" "[]"
ck; eq "T5 no open tracker is a no-op that exits 0" "0|0" "$(count_in_log '^issue close ')|$STEP_RC"
filing_case passtwo "$LIVE/pass.sh" "[{\"number\":52,\"title\":\"${FAIL_TITLE}\",\"updatedAt\":\"${T5_7H}\"},{\"number\":53,\"title\":\"${FAIL_TITLE}\",\"updatedAt\":\"${T5_30H}\"}]"
ck; eq "T5 two old duplicates of the same title are both closed" "1|1" "$(count_in_log '^issue close 52 ')|$(count_in_log '^issue close 53 ')"
filing_case passdefect "$LIVE/pass.sh" "[{\"number\":54,\"title\":\"${DEFECT_TITLE}\",\"updatedAt\":\"${T5_7H}\"},{\"number\":55,\"title\":\"${DEFECT_TITLE}\",\"updatedAt\":\"${T5_5H}\"}]"
ck; eq "T5 the probe-defect issue closes at once on a PASS whatever its age (7 h and 5 h old)" "1|1" "$(count_in_log '^issue close 54 ')|$(count_in_log '^issue close 55 ')"
filing_case passclosefail "$LIVE/pass.sh" "[{\"number\":60,\"title\":\"${FAIL_TITLE}\",\"updatedAt\":\"${T5_30H}\"},{\"number\":61,\"title\":\"${DEFECT_TITLE}\",\"updatedAt\":\"${T5_1M}\"}]" "GH_CLOSE_FAIL=61"
ck; eq "T5 a failing probe-defect close still closes the old breach issue (breach first), and the step goes red" "1|1|1" "$(count_in_log '^issue close 60 ')|$(count_in_log '^issue close 61 ')|$STEP_RC"
filing_case passdefect1m "$LIVE/pass.sh" "[{\"number\":58,\"title\":\"${DEFECT_TITLE}\",\"updatedAt\":\"${T5_1M}\"}]"
ck; eq "T5 a probe-defect issue updated one minute ago is closed by the PASS" "1" "$(count_in_log '^issue close 58 ')"
filing_case passbreach1m "$LIVE/pass.sh" "[{\"number\":59,\"title\":\"${FAIL_TITLE}\",\"updatedAt\":\"${T5_1M}\"}]"
ck; eq "T5 a breach issue updated one minute ago is NOT closed by the PASS (hysteresis stays for the breach title)" "0|0" "$(count_in_log '^issue close ')|$STEP_RC"
filing_case passother "$LIVE/pass.sh" "[{\"number\":56,\"title\":\"[ci/zot-fill-rate] some other class\",\"updatedAt\":\"${T5_30H}\"}]"
ck; eq "T5 an unrelated issue under the same label is never closed" "0" "$(count_in_log '^issue close ')"
filing_case passbadts "$LIVE/pass.sh" "[{\"number\":57,\"title\":\"${FAIL_TITLE}\",\"updatedAt\":\"not-a-date\"}]"
ck; eq "T5 an unparseable timestamp does not close, and the step still exits 0" "0|0" "$(count_in_log '^issue close ')|$STEP_RC"
filing_case passlistfail "$LIVE/pass.sh" "[]" "GH_LIST_FAIL=1"
ck; eq "T5 a failed lookup closes nothing and does not fail the step" "0|0" "$(count_in_log '^issue close ')|$STEP_RC"

# ── instrument self-test ────────────────────────────────────────────────────────────────────────
echo "--- instrument self-test"
# Driven, not read: a fail() that credits `passes` keeps every literal a grep could look for while
# making the suite unable to report a defect. Undone so it pollutes neither counters nor ledger.
ck
_p=$passes; _f=$fails
fail "self-test: this FAIL is expected and immediately reconciled" >/dev/null
if [[ $fails -eq $((_f + 1)) && $passes -eq $_p ]]; then
  fails=$_f; sed -i '$d' "$LEDGER"
  pass "fail() moves fails and ONLY fails (driven, not grepped)"
else
  fails=$_f; sed -i '$d' "$LEDGER"
  fail "fail() does not move fails, or moves passes too: every verdict above is unreportable"
fi

# ── mutation rows (parent only) ─────────────────────────────────────────────────────────────────
base_cases=$cases
if [[ -z "$CHILD" ]]; then
  echo "--- mutation rows"
  # mut_row <name> <expected substring in the child's output> <wf.py mutate args...>
  # The child must exit NON-ZERO and name the expected check ON A VERDICT LINE (`  FAIL: ...`, or
  # a whole-suite `[FATAL] ...` line), so a row cannot go red for an unrelated reason or because
  # its label merely appears in a PASS line or a want/got dump. A mutation that does not apply is
  # a suite defect, not a pass.
  # Rows run as background children, MUT_JOBS at a time (each child re-executes the whole suite),
  # and are judged afterwards by mut_collect in launch order.
  MUT_JOBS=4
  MUT_NAMES=(); MUT_EXPECT=(); MUT_ROOTS=()
  MUT_RUNNING=()
  mut_row() {
    local name="$1" expect="$2" mrc
    shift 2
    local mroot="$S/m-$name"
    assert_fixture_dir "$mroot"
    mkdir -p "$mroot/.github/workflows"
    mrc=0
    python3 "$HELPERS/wf.py" mutate "$WF" "$mroot/$WF_REL" "$@" > "$mroot/mutate.txt" 2>&1 || mrc=$?
    if (( mrc != 0 )); then
      ck; fail "MUT $name: the mutation did not apply ($(cat "$mroot/mutate.txt"))"
      return 0
    fi
    if (( ${#MUT_RUNNING[@]} >= MUT_JOBS )); then
      wait "${MUT_RUNNING[0]}" 2>/dev/null || true
      MUT_RUNNING=("${MUT_RUNNING[@]:1}")
    fi
    ( env "ZOT_FILL_WIRING_ROOT=$mroot" "ZOT_FILL_WIRING_CHILD=1" bash "$SELF" > "$mroot/out.txt" 2>&1; echo $? > "$mroot/rc.txt" ) &
    MUT_RUNNING+=("$!")
    MUT_NAMES+=("$name"); MUT_EXPECT+=("$expect"); MUT_ROOTS+=("$mroot")
  }
  mut_collect() {
    local i name expect mroot crc n
    wait
    for i in "${!MUT_NAMES[@]}"; do
      name="${MUT_NAMES[$i]}"; expect="${MUT_EXPECT[$i]}"; mroot="${MUT_ROOTS[$i]}"
      crc="$(cat "$mroot/rc.txt")" || crc=""
      n="$(grep -E '^(  FAIL:|\[FATAL\])' "$mroot/out.txt" | grep -c -F -- "$expect")" || n=0
      ck
      if [[ -n "$crc" && "$crc" != "0" && "$n" -ge 1 ]]; then pass "MUT $name goes RED on [$expect]"; else fail "MUT $name did not go RED on [$expect] (rc=[$crc], matches=$n)"; fi
    done
  }
  mut_row 1-zero-fill-steps "fill-referencing step(s) found" rename-literal "zot-fill-rate" "zot-renamed-rate"
  mut_row 2-status-references-fill "T1 the Sentry status expression references exactly the alarm step" status-add
  mut_row 3-probe-before-alarm "T2 the fill probe follows the alarm step" move-probe-first
  mut_row 4-sentry-after-fill "T2 the Sentry check-in precedes the fill probe" move-sentry-last
  mut_row 5-extra-filing-step "T1 exactly three fill filing steps" add-filing
  mut_row 5b-query-rc-benign "T3 TRANSIENT query_rc= is a defect" run-replace probe 'span=*|reclaim_at_sample_*|newest_sample_*)' 'span=*|reclaim_at_sample_*|newest_sample_*|query_rc=*)'
  mut_row 5b-drop-alarm-exit-guard "T3 alarm exit 2 suppresses the TRANSIENT defect" run-replace probe '2|3|4) owned=true' '3|4) owned=true'
  mut_row 5b-guard-only-exit-2 "T3 alarm exit 3 (PRODUCER_SILENT) suppresses" run-replace probe '2|3|4) owned=true' '2) owned=true'
  mut_row 5b-guard-no-exit-4 "T3 alarm exit 4 (INGEST_DARK) suppresses" run-replace probe '2|3|4) owned=true' '2|3) owned=true'
  mut_row 5b-guard-includes-exit-1 "T3 alarm exit 1 (FIRE) does not suppress" run-replace probe '2|3|4) owned=true' '1|2|3|4) owned=true'
  mut_row 5b-owned-hides-unevaluated "T3 alarm exit 3 does NOT suppress UNEVALUATED" run-replace probe 'raw_line="$hdr_line"' 'case "${ALARM_EXIT:-}" in 3|4) defect=false ;; esac
raw_line="$hdr_line"'
  mut_row 5b-unevaluated-never-defect "T3 alarm exit 3 does NOT suppress UNEVALUATED" run-replace probe 'UNEVALUATED) defect=true ;;' 'UNEVALUATED) defect=false ;;'
  mut_row 5c-rows-boundary-13 "T3 TRANSIENT too_few_samples with rows_scoped of exactly 12 is a defect" run-replace probe '10#$rows_scoped < 12' '10#$rows_scoped < 13'
  mut_row 5c-rows-boundary-11 "T3 TRANSIENT too_few_samples with rows_scoped of exactly 11 is benign" run-replace probe '10#$rows_scoped < 12' '10#$rows_scoped < 11'
  mut_row 5c-rows-missing-benign "T3 TRANSIENT too_few_samples with no rows_scoped is a defect" run-replace probe '[[ "$rows_scoped" =~ ^[0-9]+$ ]] && (( 10#$rows_scoped < 12 ))' '(( 10#${rows_scoped:-0} < 12 ))'
  mut_row 5c-rows-octal "T3 TRANSIENT too_few_samples with a zero-padded rows_scoped=08 is benign" run-replace probe '10#$rows_scoped' '$rows_scoped'
  mut_row 6-drop-header-agreement "T3 rc 0 with a FAIL header (disagreement)" run-replace probe ' && "$hdr_verdict" == "$mapped"' ''
  mut_row 6-take-last-header "T3 two column-0 headers" run-replace probe '"$hdr_count" == "1"' '"$hdr_count" != "0"'
  mut_row 7-default-transient "T3 rc 3 with a TRANSIENT header" run-replace probe '*) mapped=UNEVALUATED ;;' '*) mapped=TRANSIENT ;;'
  mut_row 8-drop-exit-1 "T3 rc 0 with no header -> UNEVALUATED" run-replace probe 'then exit 1; fi' 'then :; fi'
  mut_row 8-headerless-rc2-transient "T3 rc 2 with only TRANSIENT text" run-replace probe 'if [[ "$hdr_count" == "1" && "$mapped" != "UNEVALUATED" && "$hdr_verdict" == "$mapped" ]]; then' 'if [[ "$rc" == "2" ]] || [[ "$hdr_count" == "1" && "$mapped" != "UNEVALUATED" && "$hdr_verdict" == "$mapped" ]]; then'
  mut_row 9-close-threshold-3600 "T5 a tracker updated 5 h ago is not closed" run-replace pass '21600' '3600'
  mut_row 9-drop-cr-strip "T3 carriage returns are stripped from the log" run-replace probe '\013-\037' '\013-\014\016-\037'
  mut_row 9-drop-pipe-prefix "T3 script output lines are echoed behind a visible pipe prefix" run-replace probe "sed 's/^/| /'" "cat"

  # Step-shape rows: the exact `if:`, the env wiring and the closed world of step outputs.
  mut_row 12-probe-if-deleted "T1 the probe step if: is exactly" if-delete probe
  mut_row 12-probe-if-failure "T1 the probe step if: is exactly" if-replace probe '!cancelled()' 'failure()'
  mut_row 12-fail-if-failure "T1 the FAIL step if: is exactly" if-replace fail '!cancelled()' 'failure()'
  mut_row 12-fail-if-or-arm "T1 the FAIL step if: is exactly" if-replace fail "== 'FAIL'" "== 'FAIL' || steps.fill.outputs.fill_verdict == 'PASS'"
  mut_row 12-defect-if-success "T1 the probe-defect step if: is exactly" if-replace defect '!cancelled()' 'success()'
  mut_row 12-defect-if-neq-arm "T1 the probe-defect step if: is exactly" if-replace defect "== 'true'" "== 'true' || steps.fill.outputs.fill_verdict != 'PASS'"
  mut_row 12-pass-if-or-true "T1 the PASS close step if: is exactly" if-replace pass "== 'PASS'" "== 'PASS' || true"
  mut_row 12-pass-if-never-arm "T1 the PASS close step if: is exactly" if-replace pass "== 'PASS'" "== 'NEVER'"
  mut_row 12-dangling-id "T1 no step references a step id that does not exist" if-replace fail 'steps.fill.' 'steps.fil.'
  mut_row 13-alarm-exit-deleted "T1 the probe step env is exactly" env-set probe ALARM_EXIT __DEL__
  mut_row 13-alarm-exit-miswired "T1 every steps.<alarm>.outputs key the probe reads exists" env-set probe ALARM_EXIT '${{ steps.alarm.outputs.exit_cod }}'
  mut_row 13-alarm-exit-wrong-source "T1 the probe step env is exactly" env-set probe ALARM_EXIT '${{ steps.alarm.outputs.verdict }}'
  mut_row 13-window-injected "T1 the probe step env is exactly" env-set probe ZOT_FILL_WINDOW 1h
  mut_row 13-query-injected "T1 the probe step env is exactly" env-set probe ZOT_FILL_QUERY x
  mut_row 13-secret-misnamed "T1 the probe step env is exactly" env-set probe BETTERSTACK_QUERY_USERNAME '${{ secrets.BETTERSTACK_QUERY_USER }}'
  mut_row 13-fail-line-miswired "T1 the FAIL step env is exactly" env-set fail FILL_LINE '${{ steps.fill.outputs.fill_verdict }}'
  mut_row 13-defect-line-deleted "T1 the probe-defect step env is exactly" env-set defect FILL_LINE __DEL__
  mut_row 13-pass-gets-line "T1 the PASS close step env is exactly" env-set pass FILL_LINE '${{ steps.fill.outputs.fill_line }}'
  mut_row 13-pass-gets-secret "T1 the PASS close step env is exactly" env-set pass BETTERSTACK_QUERY_PASSWORD '${{ secrets.BETTERSTACK_QUERY_PASSWORD }}'
  mut_row 13-unwritten-ref "T1 every steps.<probe>.outputs key referenced anywhere is written" env-set fail FILL_CAUSE '${{ steps.fill.outputs.fill_cause }}'
  mut_row 14-script-writer-step "T1 exactly four steps reference the fill outputs" add-step probe

  # Lookup rows: every lookup in every filing step keeps its flags.
  mut_row 15-pass-lookup-no-state "T5 the PASS step does ONE lookup" run-replace pass ' --state open' ''
  mut_row 15-pass-lookup-search "T5 the PASS step does ONE lookup" run-replace pass ' --state open' ' --state open --search x'
  mut_row 15-pass-second-lookup "T5 the PASS step does ONE lookup" run-replace pass 'CUTOFF=$(( $(date' 'gh issue list --repo "$GH_REPO" --state open --label ci/zot-fill-rate --limit 100 --json number >/dev/null; CUTOFF=$(( $(date'
  mut_row 15-pass-limit "T5 the PASS step does ONE lookup" run-replace pass '--limit 100' '--limit 30'
  mut_row 15-fail-lookup-no-state "T4 FAIL: both lookups" run-replace fail ' --state open' ''
  mut_row 15-fail-lookup-limit "T4 FAIL: both lookups" run-replace fail '--limit 100' '--limit 30'
  mut_row 15-defect-lookup-no-state "T4 defect, no tracker: its one lookup" run-replace defect ' --state open' ''
  mut_row 15-defect-lookup-label "T4 defect, no tracker: its one lookup" run-replace defect '--label "$(sed -E' '--label "x$(sed -E'

  # Fixture rows.
  mut_row 16-fail-closes-its-own-tracker "T4 FAIL, tracker exists" run-replace fail "'.[] | select(.title | contains(\$t)) | .number'" "'.[] | .number'"
  mut_row 16-defect-takes-first-issue "T4 defect, tracker exists (the FAIL issue listed FIRST)" run-replace defect '[.[] | select(.title | contains($t))][0].number' '[.[]][0].number'
  mut_row 16-pass-defect-age-gated "T5 a probe-defect issue updated one minute ago is closed" run-replace pass "contains(\$t)) | .number' <<<\"\$LIST\") || DEFECTS" "contains(\$t)) | select((.updatedAt | fromdateiso8601) < (now - 21600)) | .number' <<<\"\$LIST\") || DEFECTS"
  mut_row 16-pass-defect-never-closes "T5 a probe-defect issue updated one minute ago is closed" run-replace pass 'for N in $DEFECTS; do' 'for N in; do'
  mut_row 16-pass-breach-closes-at-once "T5 a breach issue updated one minute ago is NOT closed" run-replace pass '< $c' '< ($c + 100000)'

  # Probe rows beyond classification.
  mut_row 17-no-pre-write "T3 a probe that outlives its step timeout" run-replace probe 'echo "fill_verdict=UNEVALUATED"' ':'
  mut_row 17-pre-write-benign "T3 a probe that outlives its step timeout" run-replace probe 'echo "fill_defect=true"' 'echo "fill_defect=false"'
  mut_row 18-headerless-fill-line-empty "T3 the UNEVALUATED fill_line names the exit code" run-replace probe 'raw_line="UNEVALUATED rc=${rc} headers=${hdr_count}"' 'raw_line=""'
  mut_row 18-header-accepts-suffix "T3 a PASSED header is not a header" run-replace probe '\( .*\)\{0,1\}' '.*'
  mut_row 18-header-accepts-indent "T3 an indented header is not a header" run-replace probe "sed -n 's/^zot-fill-rate\\[#7341\\]: \\(PASS" "sed -n 's/^ *zot-fill-rate\\[#7341\\]: \\(PASS"
  mut_row 18-keep-u2028 "T3 fill_line carries none of the U+2028" run-replace probe 's/\xe2\x80\xa8//g; ' ''
  mut_row 18-keep-control-bytes "T3 fill_line carries none of the U+2028" run-replace probe "tr -d '\\000-\\037\\177'" "tr -d '\\000'"
  mut_row 18-keep-hash-at-tick "T3 fill_line drops the script-name prefix and the hash" run-replace probe "| tr -d '#@\`')" '| cat)'
  mut_row 18-cap-4000 "T3 fill_line is capped at 400 characters" run-replace probe '${fill_line:0:400}' '${fill_line:0:4000}'
  mut_row 18-host-scrub-off "T3 a *.betterstackdata.com hostname in script output is scrubbed" run-replace probe 's/[A-Za-z0-9.-]+\.betterstackdata\.com/[host]/g' 's/NOPE/[host]/g'
  mut_row 18-mask-off "T3 the lowercased query host is masked" run-replace probe 'echo "::add-mask::${BETTERSTACK_QUERY_HOST,,}"' ':'

  # Key-class rows (every behaviour-bearing step, job and workflow key outside if/env/run).
  mut_row 19-probe-shell "T1 the probe step has exactly the reviewed key set" step-set probe shell '"sh"'
  mut_row 19-probe-shell-no-shell-pin "T1 no fill step declares shell:" step-set probe shell '"sh"'
  mut_row 19-probe-continue-on-error "T1 the probe step has exactly the reviewed key set" step-set probe continue-on-error 'true'
  mut_row 19-fail-continue-on-error "T1 the FAIL step has exactly the reviewed key set" step-set fail continue-on-error 'true'
  mut_row 19-probe-working-directory "T1 the probe step has exactly the reviewed key set" step-set probe working-directory '"/tmp"'
  mut_row 19-pass-gains-id "T1 the PASS close step has exactly the reviewed key set" step-set pass id '"passx"'
  mut_row 19-defect-shell "T1 the probe-defect step has exactly the reviewed key set" step-set defect shell '"sh"'
  mut_row 19-job-env-window "T1 the alarm job declares exactly the reviewed keys" job-set env '{"ZOT_FILL_WINDOW": "1h"}'
  mut_row 19-job-continue-on-error "T1 the alarm job declares exactly the reviewed keys" job-set continue-on-error 'true'
  mut_row 19-job-defaults-shell "T1 the alarm job declares exactly the reviewed keys" job-set defaults '{"run": {"shell": "sh"}}'
  mut_row 19-wf-env-query "T1 the workflow declares exactly the reviewed top-level keys" wf-set env '{"ZOT_FILL_QUERY": "x"}'
  mut_row 19-wf-defaults-shell "T1 the workflow declares exactly the reviewed top-level keys" wf-set defaults '{"run": {"shell": "sh"}}'
  mut_row 19-job-outputs-literal "T1 the alarm job outputs are exactly the reviewed block" job-set outputs '{"inventory_tracker": "${{ steps.fire.outputs.inventory_tracker }}", "fv": "${{ steps.fill.outputs.fill_verdict }}"}'
  mut_row 19-job-outputs-outside-scan "T1 nothing outside the alarm job steps references the fill step" job-set outputs '{"inventory_tracker": "${{ steps.fire.outputs.inventory_tracker }}", "fv": "${{ steps.fill.outputs.fill_verdict }}"}'
  mut_row 19-permissions-widened "T1 the workflow permissions are exactly the reviewed block" wf-set permissions '{"contents": "write", "issues": "write"}'
  mut_row 19-permissions-actions "T1 the workflow permissions are exactly the reviewed block" wf-set permissions '{"contents": "read", "issues": "write", "actions": "write"}'

  # Bracket syntax must not evade the exactly-four count or the dangling-id check.
  mut_row 20-bracket-outputs-step "T1 exactly four steps reference the fill outputs" add-step-run 'echo "${{ steps['"'"'fill'"'"'].outputs['"'"'fill_verdict'"'"'] }}"'
  mut_row 20-tojson-steps-step "T1 exactly four steps reference the fill outputs" add-step-run 'echo "${{ toJSON(steps) }}"'
  mut_row 20-bracket-dangling-id "T1 no step references a step id that does not exist" add-step-run 'echo "${{ steps['"'"'ghost'"'"'].outputs.x }}"'

  # --json field pinning: the gh shim projects the canned list to the requested fields.
  mut_row 21-pass-drops-updatedat-behaviour "T5 a tracker updated 7 h ago is closed with a comment" run-replace pass '--json number,title,updatedAt' '--json number,title'
  mut_row 21-pass-drops-updatedat-pin "T5 the PASS lookup requests exactly --json number,title,updatedAt" run-replace pass '--json number,title,updatedAt' '--json number,title'
  mut_row 21-pass-extra-field-pin "T5 the PASS lookup requests exactly --json number,title,updatedAt" run-replace pass '--json number,title,updatedAt' '--json number,title,updatedAt,body'
  mut_row 21-fail-drops-title-behaviour "T4 FAIL, tracker exists" run-replace fail '--limit 100 --json number,title | jq -r --arg t "$ISSUE_TITLE"' '--limit 100 --json number | jq -r --arg t "$ISSUE_TITLE"'
  mut_row 21-fail-drops-title-pin "T4 FAIL: both lookups request exactly --json number,title" run-replace fail '--limit 100 --json number,title | jq -r --arg t "$ISSUE_TITLE"' '--limit 100 --json number | jq -r --arg t "$ISSUE_TITLE"'
  mut_row 21-fail-defect-lookup-extra-field-pin "T4 FAIL: both lookups request exactly --json number,title" run-replace fail '--limit 100 --json number,title | jq -r --arg t "$DEFECT_TITLE"' '--limit 100 --json number,title,body | jq -r --arg t "$DEFECT_TITLE"'
  mut_row 21-defect-drops-title-behaviour "T4 defect, tracker exists (the FAIL issue listed FIRST)" run-replace defect '--limit 100 --json number,title' '--limit 100 --json number'
  mut_row 21-defect-extra-field-pin "T4 defect: its one lookup requests exactly --json number,title" run-replace defect '--limit 100 --json number,title' '--limit 100 --json number,title,body'

  # The body's own set line (the harness adds no pipefail): first statement pinned, and the dedupe
  # annotation observable.
  mut_row 22-pass-set-plus-e "T1 no fill step body switches an option off again with set +" run-replace pass 'set -euo pipefail' 'set -euo pipefail
set +e'
  mut_row 22-probe-set-deleted "T1 the probe step's first statement is set -uo pipefail" run-replace probe 'set -uo pipefail
' ''
  mut_row 22-probe-set-no-pipefail "T1 the probe step's first statement is set -uo pipefail" run-replace probe 'set -uo pipefail' 'set -u'
  mut_row 22-fail-set-deleted "T1 the FAIL step's first statement is set -euo pipefail" run-replace fail 'set -euo pipefail
' ''
  mut_row 22-defect-set-deleted "T1 the probe-defect step's first statement is set -euo pipefail" run-replace defect 'set -euo pipefail
' ''
  mut_row 22-pass-set-deleted "T1 the PASS close step's first statement is set -euo pipefail" run-replace pass 'set -euo pipefail
' ''
  mut_row 22-fail-no-pipefail-annotation "T4 FAIL, dedupe query fails: the failure is annotated" run-replace fail 'set -euo pipefail' 'set -eu'
  mut_row 22-defect-no-pipefail-annotation "T4 defect, dedupe query fails: the failure is annotated" run-replace defect 'set -euo pipefail' 'set -eu'

  # The defect step's own defence in depth (the FAIL step's twin is exercised by fail.sh above).
  mut_row 23-defect-restrip-removed "T4 defect: a hostile FILL_LINE reaches the body with no at-sign mention" run-replace defect "tr -d '\\000-\\037\\177#@\`'" 'cat'
  mut_row 23-defect-cap-removed "T4 defect: a 10 KB FILL_LINE tail is capped in the body" run-replace defect 'FILL_LINE="${FILL_LINE:0:400}"' 'FILL_LINE="$FILL_LINE"'
  mut_row 23-defect-restrip-removed-comment "T4 defect: a hostile FILL_LINE reaches the comment with no at-sign mention" run-replace defect "tr -d '\\000-\\037\\177#@\`'" 'cat'
  mut_row 23-defect-cap-removed-comment "T4 defect: a 10 KB FILL_LINE tail is capped in the comment" run-replace defect 'FILL_LINE="${FILL_LINE:0:400}"' 'FILL_LINE="$FILL_LINE"'

  # Ordering: the breach close must run before the defect close, so a failing defect close cannot
  # starve it. The mutant runs a defect-close loop first.
  mut_row 24-pass-defect-close-first "T5 a failing probe-defect close still closes the old breach issue" run-replace pass 'CUTOFF=$(( $(date' 'for N in $(jq -r --arg t "$DEFECT_TITLE" '"'"'.[] | select(.title | contains($t)) | .number'"'"' <<<"$LIST"); do gh issue close "$N" --repo "$GH_REPO" --comment x; done; CUTOFF=$(( $(date'

  mut_collect

  # Row 10, the harness itself: neuter pass()/fail() in a copy of THIS file and run it against the
  # live workflow. The call-site `cases` counter keeps moving, so accounting must go RED.
  neut="$S/neutered"
  assert_fixture_dir "$neut"
  mkdir -p "$neut"
  sed -e 's/^pass() {.*$/pass() { :; }/' -e 's/^fail() {.*$/fail() { :; }/' "$SELF" > "$neut/neutered.test.sh"
  nrc=0
  env "ZOT_FILL_WIRING_ROOT=$ROOT" "ZOT_FILL_WIRING_CHILD=1" bash "$neut/neutered.test.sh" > "$neut/out.txt" 2>&1 || nrc=$?
  n_acc="$(grep -c 'accounting' "$neut/out.txt")" || n_acc=0
  ck
  if (( nrc != 0 && n_acc >= 1 )); then pass "MUT 10 neutered pass()/fail() goes RED on the accounting check"; else fail "MUT 10 neutered pass()/fail() did not go RED on accounting (rc=$nrc, matches=$n_acc)"; fi

  # Rows 11 and 11b, must-PASS: the same workflow with every fill step id renamed consistently and
  # an extra comment line (11), and a bare yaml roundtrip with no change (11b). Each must execute the
  # same number of cases as the parent's base population.
  # must_pass_row <tag> <what> <wf.py op...>: the edited workflow must run the FULL base population
  # green. A guard that rejects everything cannot satisfy it, and a roundtrip that altered the
  # workflow would be caught here instead of turning every red row green for the wrong reason.
  must_pass_row() {
    local tag="$1" what="$2" mpr mc=0 got
    shift 2
    local mp="$S/m-$tag"
    assert_fixture_dir "$mp"
    mkdir -p "$mp/.github/workflows"
    mpr=0
    python3 "$HELPERS/wf.py" mutate "$WF" "$mp/$WF_REL" "$@" > "$mp/mutate.txt" 2>&1 || mpr=$?
    ck
    if (( mpr != 0 )); then
      fail "MUT $tag must-PASS: the edit did not apply ($(cat "$mp/mutate.txt"))"
      return 0
    fi
    env "ZOT_FILL_WIRING_ROOT=$mp" "ZOT_FILL_WIRING_CHILD=1" bash "$SELF" > "$mp/out.txt" 2>&1 || mc=$?
    got="$(sed -n 's/^CHILD CASES=\([0-9]*\) FAILS=0$/\1/p' "$mp/out.txt")" || got=""
    if (( mc == 0 )) && [[ "$got" == "$base_cases" ]]; then
      pass "MUT $tag must-PASS: $what stays green over the full ${base_cases}-case population"
    else
      fail "MUT $tag must-PASS: $what went red or ran a different population (rc=$mc, cases=[$got], want $base_cases)"
    fi
  }
  must_pass_row 11 "consistently renamed step ids" rename-ids
  must_pass_row 11b "a no-op yaml.safe_load/safe_dump roundtrip" noop
fi

# ── accounting. Emitted DIRECTLY, never through pass()/fail(). ──────────────────────────────────
# Direction-aware: the printed ledger is the independent observable. Silencing it means deleting
# evidence rather than decrementing a number.
ledger_fail="$(grep -c '^FAIL$' "$LEDGER")" || ledger_fail=0
ledger_pass="$(grep -c '^PASS$' "$LEDGER")" || ledger_pass=0
if [[ "$ledger_fail" -ne "$fails" || "$ledger_pass" -ne "$passes" ]]; then
  printf '\n[FATAL] accounting: ledger (%s pass / %s fail) disagrees with counters (%d pass / %d fail).\n' \
    "$ledger_pass" "$ledger_fail" "$passes" "$fails" >&2
  exit 1
fi
if [[ $((passes + fails)) -ne $cases ]]; then
  printf '\n[FATAL] accounting: passes+fails (%d) != cases (%d): a verdict was lost or a call site is missing its increment.\n' \
    "$((passes + fails))" "$cases" >&2
  exit 1
fi

if [[ -n "$CHILD" ]]; then
  printf 'CHILD CASES=%d FAILS=%d\n' "$cases" "$fails"
  [[ "$fails" -eq 0 ]]
  exit $?
fi

# Floor: derived from a green run, with no headroom for silently dropped rows. Raise in lockstep.
MIN_CASES=252
if [[ "$cases" -lt "$MIN_CASES" ]]; then
  printf '[FATAL] vacuity floor: %d cases executed, expected at least %d\n' "$cases" "$MIN_CASES" >&2
  exit 1
fi

echo
echo "zot-fill-rate-standing-wiring.test.sh: ${passes} passed, ${fails} failed, ${cases} case(s) executed (floor ${MIN_CASES})"
[[ "$fails" -eq 0 ]] || exit 1
