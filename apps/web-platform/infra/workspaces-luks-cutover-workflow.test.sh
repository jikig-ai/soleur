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
    # Strip tab/newline: the bash reader below splits on tabs, so an embedded one in a YAML value
    # would desync the loop and manufacture a phantom verdict.
    d = str(detail)[:160].replace("\t", " ").replace("\n", " ").replace("\r", " ")
    verdicts.append(("ok" if cond else "FAIL", name.replace("\t", " "), d))

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
pregate_job = None
pregate_step = None
for jn, j in jobs.items():
    for s in (j.get("steps") or []):
        r = s.get("run")
        if not r:
            continue
        n += 1
        open(f"{scratch}/run-{n}.sh", "w").write(r)
        if "Validate dispatch" in str(s.get("name", "")):
            open(f"{scratch}/pregate.sh", "w").write(r)
            pregate_job, pregate_step = jn, s
check("extracted at least one run: body for syntax checking", n > 0, n)

# THE STEP WRAPPER, not just its body. The behavioral leg below executes the extracted `run:`
# script, which observes the shell and NOTHING around it — so moving the step into the gated
# `cutover` job, disabling it with `if: false`, or marking it continue-on-error all leave every
# behavioral assertion passing while the guard is inert or runs after a reviewer was paged.
check("the pre-gate step exists", pregate_step is not None)
if pregate_step is not None:
    check("the pre-gate runs in the UNGATED preflight job (a gated job would page the reviewer first)",
          pregate_job == "preflight", pregate_job)
    check("the pre-gate step is unconditional (no if:)", "if" not in pregate_step,
          pregate_step.get("if"))
    check("the pre-gate step is not continue-on-error (that would make every refusal advisory)",
          not pregate_step.get("continue-on-error"))

# `needs: preflight` alone does not prove a preflight FAILURE blocks the cutover: an
# `if: always()` on the job would run it anyway, after a refused dispatch.
check("cutover declares no job-level if: (a preflight failure must block it)",
      "if" not in (jobs.get("cutover") or {}), (jobs.get("cutover") or {}).get("if"))

# Key-presence on the env is not enough: a hardcoded CLEAN_STRAY: '1' satisfies "in env" while
# sending the deletion flag to the host on EVERY dispatch.
if run_step:
    cs_env = str((run_step[0].get("env") or {}).get("CLEAN_STRAY", ""))
    check("CLEAN_STRAY env derives from inputs.clean_stray, not a hardcoded value",
          "inputs.clean_stray" in cs_env, cs_env)

# PATH PARITY. The workflow hardcodes /mnt/data-luks and /mnt/data (in the clean_stray input
# description and in the probe's env); the script derives them from ${WORKSPACES_STAGING:-...} /
# ${WORKSPACES_MOUNT:-...}. The workflow does NOT pass those vars in the .env, so the two agree
# only by coincidence. Change a script default and the approval banner would describe — and the
# probe would measure — a path different from the one the script deletes, with nothing failing.
import re
script = open("apps/web-platform/infra/workspaces-cutover.sh").read()
def _default(var):
    # e.g. STAGING="${WORKSPACES_STAGING:-/mnt/data-luks}" — the env var name differs from the
    # local, so match any override name rather than assuming they are the same.
    m = re.search(r'^%s="\$\{[A-Za-z_][A-Za-z0-9_]*:-([^}]+)\}"' % re.escape(var), script, re.M)
    return m.group(1) if m else None
script_staging = _default("STAGING")
script_mount = _default("MOUNT")
check("could read the script's STAGING/MOUNT defaults", bool(script_staging and script_mount),
      f"{script_staging} {script_mount}")
probe = [s for s in (jobs.get("preflight") or {}).get("steps") or []
         if "AP-009 deletion probe" in str(s.get("name", ""))]
check("the AP-009 probe step exists", len(probe) == 1)
if probe and script_staging and script_mount:
    penv = probe[0].get("env") or {}
    check("probe STAGING_PATH matches the script's $STAGING default",
          str(penv.get("STAGING_PATH")) == script_staging,
          f"workflow={penv.get('STAGING_PATH')} script={script_staging}")
    check("probe MOUNT_PATH matches the script's $MOUNT default",
          str(penv.get("MOUNT_PATH")) == script_mount,
          f"workflow={penv.get('MOUNT_PATH')} script={script_mount}")
    # Safe-by-literal, not by construction: the probe interpolates these into a single-quoted
    # remote shell string. They are constants today; a quote or metacharacter would escape it.
    for k in ("STAGING_PATH", "MOUNT_PATH"):
        v = str(penv.get(k, ""))
        check(f"probe {k} is a metacharacter-free literal (it is interpolated into a remote shell string)",
              bool(re.fullmatch(r"[A-Za-z0-9/_.-]+", v)), v)

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

# NON-DEGENERACY FLOOR — see the sibling rationale in workspaces-luks-staging.test.sh. A python
# leg that dies before emitting verdicts, or a `check()` block deleted wholesale, would otherwise
# leave this suite reporting "0 passed, 0 failed" and exiting 0.
WF_MIN_ASSERTIONS=40
if [[ "$pass" -lt "$WF_MIN_ASSERTIONS" ]]; then
  echo "FAIL - only $pass assertions ran (floor $WF_MIN_ASSERTIONS) — the structural leg produced fewer verdicts than expected; a green run here would be vacuous"
  exit 1
fi
[[ "$fail" -eq 0 ]] || exit 1
