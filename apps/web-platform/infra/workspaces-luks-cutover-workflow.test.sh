#!/usr/bin/env bash
#
# Structural + behavioral gate for .github/workflows/workspaces-luks-cutover.yml (#6588).
#
# WHY A DEDICATED SUITE: this workflow can delete user data and can perform an irreversible freeze
# on sole-copy data. Two properties are load-bearing and neither is expressible in the shell suites
# that cover workspaces-cutover.sh:
#
#   (1) The `environment:` gate expression. `dry_run` used to double as a proxy for "which mode",
#       and because `dry_run` DEFAULTS TO TRUE while the script's ROLLBACK block force-sets
#       DRY_RUN=0, `rollback=true` resolved to the UNGATED branch and performed a real
#       umount/close/restart behind nothing but a typo-guard token. The risk here is OPERAND
#       INVERSION, so the assertion is exact-string equality on the parsed value — that catches an
#       inversion without needing a GHA-semantics simulator.
#
#   (2) The pre-gate mode validation, asserted by EXECUTING the workflow's own extracted `run:`
#       body against input combinations — the real script, not a model of it.
#
# EVERY structural assertion parses the file as YAML. A grep would pass VACUOUSLY: the header
# comments discuss both the gate expression and the mode combinations at length, so a bare grep for
# the expression matches the prose that describes it (cq-assert-anchor-not-bare-token).
#
# `bash -n` is likewise run only on EXTRACTED `run:` bodies — `bash -n` on the .yml itself parses
# YAML as bash and proves nothing.
set -euo pipefail

WF=".github/workflows/workspaces-luks-cutover.yml"
[[ -f "$WF" ]] || { echo "FAIL - $WF not found (run from the repo root)"; exit 1; }

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
no() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }

python3 -c 'import yaml' 2>/dev/null || pip3 install --quiet pyyaml

SCRATCH="$(mktemp -d -t wl-wf.XXXXXXXX)"
trap 'rm -rf "$SCRATCH"' EXIT INT TERM HUP

# --- structural assertions, parsed as YAML -----------------------------------------------------
# The python leg writes one TSV verdict per line; bash reports them. Splitting it this way keeps
# the reporting convention identical to the sibling suites while still parsing real YAML.
python3 - "$WF" "$SCRATCH" > "$SCRATCH/verdicts.tsv" <<'PY'
import sys, yaml, json

wf = yaml.safe_load(open(sys.argv[1]))
scratch = sys.argv[2]
verdicts = []

def check(name, cond, detail=""):
    verdicts.append(("ok" if cond else "FAIL", name, str(detail)[:160]))

jobs = wf.get("jobs") or {}
check("jobs are exactly preflight + cutover", set(jobs) == {"preflight", "cutover"}, sorted(jobs))

# (1) the gate expression, EXACT — operand inversion is the real risk.
EXPECT = "${{ (!inputs.dry_run || inputs.clean_stray || inputs.rollback) && 'workspaces-luks-cutover' || '' }}"
got = (jobs.get("cutover") or {}).get("environment")
check("cutover environment expression is exactly the fail-closed form", got == EXPECT, repr(got))
for tok in ("!inputs.dry_run", "inputs.clean_stray", "inputs.rollback"):
    check(f"gate expression carries operand {tok}", tok in (got or ""))

# preflight is the ungated pre-gate job: an `environment:` key here would defeat its whole purpose,
# because a gate blocks a job BEFORE its first step runs.
check("preflight declares NO environment (must run before a reviewer is paged)",
      "environment" not in (jobs.get("preflight") or {}))
check("cutover needs preflight", (jobs.get("cutover") or {}).get("needs") == "preflight")

pf_text = json.dumps(jobs.get("preflight") or {})
check("preflight never references WORKSPACES_LUKS_BOOT_TOKEN (strictly less credential)",
      "WORKSPACES_LUKS_BOOT_TOKEN" not in pf_text)
check("preflight issues no rm (it is a read-only probe)", "rm -rf" not in pf_text)

steps = (jobs.get("cutover") or {}).get("steps") or []
lb = [s for s in steps if "Loopback" in str(s.get("name", ""))]
check("loopback validation gate step exists", len(lb) == 1)
if lb:
    cond = str(lb[0].get("if", ""))
    for tok in ("!inputs.dry_run", "!inputs.rollback", "!inputs.clean_stray"):
        check(f"loopback gate is scoped off {tok}", tok in cond, cond)

# `on` parses to the boolean True under YAML 1.1, hence the two-key lookup.
inp = ((wf.get(True) or wf.get("on") or {}).get("workflow_dispatch") or {}).get("inputs") or {}
cs = inp.get("clean_stray") or {}
check("clean_stray input exists", bool(cs))
check("clean_stray defaults to false (never the arm a dispatch falls into by omission)",
      cs.get("default") is False, repr(cs.get("default")))
desc = str(cs.get("description", ""))
check("clean_stray description names the AP-009 deviation at dispatch time", "AP-009" in desc)
check("clean_stray description states it deletes user data", "USER DATA" in desc.upper())

# CLEAN_STRAY must actually reach the host, or the mode is unreachable in production.
run_step = [s for s in steps if "Run workspaces-luks cutover" in str(s.get("name", ""))]
check("the Run step exists", len(run_step) == 1)
if run_step:
    body = str(run_step[0].get("run", ""))
    env = run_step[0].get("env") or {}
    check("CLEAN_STRAY is plumbed into the Run step env", "CLEAN_STRAY" in env)
    check("CLEAN_STRAY is written into the host .env printf", "CLEAN_STRAY=%s" in body)

# Extract every run: body so bash can syntax-check them, and the pre-gate step so bash can EXECUTE
# it against real input combinations.
n = 0
for jn, j in jobs.items():
    for s in (j.get("steps") or []):
        r = s.get("run")
        if not r:
            continue
        n += 1
        open(f"{scratch}/run-{n}.sh", "w").write(r)
        if "Validate dispatch" in str(s.get("name", "")):
            open(f"{scratch}/pregate.sh", "w").write(r)
check("extracted at least one run: body for syntax checking", n > 0, n)

with open(f"{scratch}/verdicts.tmp", "w") as f:
    pass
for v in verdicts:
    print("\t".join(v))
PY

while IFS=$'\t' read -r verdict name detail; do
  [[ -n "${verdict:-}" ]] || continue
  if [[ "$verdict" == "ok" ]]; then ok "$name"; else no "$name${detail:+ ($detail)}"; fi
done < "$SCRATCH/verdicts.tsv"

# --- bash -n on EXTRACTED run: bodies ----------------------------------------------------------
syntax_bad=0
for f in "$SCRATCH"/run-*.sh; do
  [[ -e "$f" ]] || continue
  bash -n "$f" 2>/dev/null || syntax_bad=$((syntax_bad + 1))
done
if [[ "$syntax_bad" -eq 0 ]]; then
  ok "every extracted run: body passes bash -n"
else
  no "$syntax_bad extracted run: body/bodies failed bash -n"
fi

# --- behavioral: the REAL pre-gate step against every input combination ------------------------
# This is the requirement-2 assertion that matters: a clean_stray dispatch must be UNABLE to ride
# the ungated dry_run=true arm. dry_run DEFAULTS TO TRUE, so the natural dispatch (tick clean_stray,
# change nothing else) is exactly the combination that must be refused.
if [[ ! -f "$SCRATCH/pregate.sh" ]]; then
  no "could not extract the pre-gate validation step — requirement-2 enforcement is unverified"
else
  gate_rc() {
    local rc=0
    CONFIRM="$1" DRY="$2" ROLLBACK_IN="$3" CLEAN_STRAY_IN="$4" \
      bash "$SCRATCH/pregate.sh" >/dev/null 2>&1 || rc=$?
    printf '%s' "$rc"
  }
  DEL="DELETE-STRAY-USER-DATA-AP-009"
  CUT="CUTOVER-WORKSPACES-LUKS"

  [[ "$(gate_rc "$DEL" true false true)" != "0" ]] \
    && ok "clean_stray + dry_run=true is REFUSED (requirement 2: not reachable from the ungated arm)" \
    || no "clean_stray rode the dry_run=true arm — requirement 2 is VIOLATED"

  [[ "$(gate_rc "$DEL" false true true)" != "0" ]] \
    && ok "clean_stray + rollback is REFUSED (rollback would silently win via its exit 0)" \
    || no "clean_stray + rollback was accepted — the rollback would run instead and report green"

  [[ "$(gate_rc "$CUT" false false true)" != "0" ]] \
    && ok "the cutover token cannot authorize a deletion (distinct token per destructive verb)" \
    || no "a muscle-memory cutover token reached the user-data deletion"

  [[ "$(gate_rc "$DEL" false false false)" != "0" ]] \
    && ok "the deletion token is rejected on a non-clean_stray dispatch (tokens are not interchangeable)" \
    || no "the deletion token authorized a non-deletion dispatch"

  [[ "$(gate_rc "$DEL" false false true)" == "0" ]] \
    && ok "POSITIVE CONTROL: the intended deletion dispatch is ACCEPTED (the gate is not refuse-everything)" \
    || no "the intended clean_stray dispatch was refused — the mode is unreachable and the cutover stays wedged"

  [[ "$(gate_rc "$CUT" true false false)" == "0" ]] \
    && ok "POSITIVE CONTROL: a normal rehearsal still passes" \
    || no "the pre-gate step broke the ordinary rehearsal dispatch"

  [[ "$(gate_rc "$CUT" false false false)" == "0" ]] \
    && ok "POSITIVE CONTROL: a normal real freeze still passes" \
    || no "the pre-gate step broke the ordinary freeze dispatch"

  [[ "$(gate_rc "$CUT" false true false)" == "0" ]] \
    && ok "POSITIVE CONTROL: an ordinary rollback still passes" \
    || no "the pre-gate step broke the rollback recovery dispatch"
fi

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]] || exit 1
