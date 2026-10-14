#!/usr/bin/env bash
# Shape guard for the Inngest RLS apply workflow:
#   .github/workflows/apply-inngest-rls.yml -> soleur-inngest-prd (pigsfuxruiopinouvjwy)
#
# WAS a PAIR guard. The dev half (apply-inngest-rls-dev.yml -> soleur-dev) is gone:
# the cutover ended soleur-dev's co-tenancy with the dark Inngest host, the 14 dark
# tables were dropped (#6488) and the lockdown that defended them was retired with
# them. The dev workflow file is TRANSIENT for the life of that PR and is deleted in
# its second commit; asserting a lockdown shape against a one-commit drop workflow
# would pin an artifact that has no future to regress into.
#
# WHY A CHECKED-IN GUARD AND NOT A ONE-SHOT PR REVIEW: a PR-time grep does not stop a
# later de-pin or a re-widened `paths:` glob. actionlint cannot see either — it checks
# workflow SYNTAX and shell, not this repo's routing semantics — so a checked-in test
# invoked by infra-validation.yml is the enforceable gate.
#
# (#7002 note: actionlint now DOES run in CI, as a hang guard in ci.yml. That step asserts
# only that the linter TERMINATES — it is not a semantic gate and does not subsume this
# file. The earlier wording here, "actionlint is local-only (it runs in ZERO workflows)",
# is no longer true; the reason for this guard is unchanged.)
#
# THE FAILURE THIS EXISTS TO PREVENT: TRIGGER BLEED (finding 0). apply-inngest-rls.yml
# used to trigger on 'apps/web-platform/infra/inngest-rls/**' — matching EVERY file in
# that directory. Editing a dev-only artifact therefore auto-applied 0001 (a schema-wide
# REVOKE-all) to the brand-survival-critical Inngest PRD project. The path-routing
# assertions below simulate real edited paths against the parsed `paths:` filter, and
# three of them deliberately name now-deleted files: the property under test is that
# the filter stays NARROW, and a re-widening to `**` would start matching them again.
#
# Asserted against the PARSED YAML rather than greps, so a reformat or a comment
# mentioning an idiom cannot false-PASS the gate.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
PRD_WF="$REPO_ROOT/.github/workflows/apply-inngest-rls.yml"

# ANTI-VACUITY FLOOR (Guard 1). PASS + FAIL must equal this at the end of the run.
# The failure it catches is NOT an emptied `checks` dict — measured 2026-09-19, that
# raises KeyError and reports `passed=0 failed=48`, i.e. loudly RED. It is the other
# shape: deleting `assert` LINES silently lowers the executed count with everything
# still green. This file just lost 25 of its 40 checks in one hand-edited cleanup
# (the dev half), which is exactly the edit under which a miscount hides.
#
# Derived 2026-09-19 at the commit that removed the dev half: 15 `probe` assertions
# (6 path-routing + 1 project pinning + 2 identity + 5 gate semantics + 1 supply
# chain) plus 2 file-level assertions (prd workflow exists, prd YAML parses) = 17.
# A mismatch means an assert line was added or removed — investigate it, do not
# bump this number to match.

PASS=0
FAIL=0
assert() {
  local desc="$1" cond="$2"
  if eval "$cond"; then echo "  PASS: $desc"; PASS=$((PASS + 1));
  else echo "  FAIL: $desc"; echo "    cond: $cond"; FAIL=$((FAIL + 1)); fi
}

echo "=== apply-inngest-rls.yml shape guards ==="

assert "prd workflow exists" "[[ -f '$PRD_WF' ]]"
assert "prd YAML parses (pyyaml)" "python3 -c 'import yaml; yaml.safe_load(open(\"$PRD_WF\"))'"

# All shape probes run in python and emit a bare yes/no token. Rationale (inherited from
# restart-inngest-workflow-guard.test.sh): round-tripping YAML strings that contain spaces
# and quotes through a shell variable into `eval` mangles the quoting and silently
# false-FAILS a correct workflow.
probe() {
  python3 - "$PRD_WF" "$1" <<'PY'
import sys, yaml, fnmatch

prd = yaml.safe_load(open(sys.argv[1])) or {}

def triggers(wf):
    # `on` is YAML 1.1 truthy: pyyaml keys it as boolean True, NOT the string "on".
    # Probe both spellings or this reads as "no triggers" and every path assertion
    # below passes VACUOUSLY.
    return wf.get("on", wf.get(True)) or {}

def paths(wf):
    return (triggers(wf).get("push") or {}).get("paths") or []

def env_values(wf, key):
    """EVERY declaration of `key` — workflow-, job-, and step-level.

    Deliberately NOT "the first match". PROJECT_REF used to be declared TWICE (the
    apply step and the probe step) and the old first-match step_env() only ever
    inspected the apply step's copy: the probe step's ref — which aims a
    deliberately destructive anon DELETE/INSERT and has NO identity preflight of
    its own — was asserted by nothing. dev_no_prd_ref caught drift to the Inngest
    prd ref only; drift to ifsccnjhymdmidffkzhl (the APP prd project) or any other
    ref passed silently.
    """
    out = []
    if key in (wf.get("env") or {}):
        out.append(str(wf["env"][key]))
    for job in (wf.get("jobs") or {}).values():
        if key in (job.get("env") or {}):
            out.append(str(job["env"][key]))
        for step in (job.get("steps") or []):
            env = step.get("env") or {}
            if key in env:
                out.append(str(env[key]))
    return out

def env_all_eq(wf, key, literal):
    # `vals and ...` is load-bearing: all([]) is True, so a key that vanished
    # entirely would PASS vacuously.
    vals = env_values(wf, key)
    return bool(vals) and all(v == literal for v in vals)

def all_run_text(wf):
    out = []
    for job in (wf.get("jobs") or {}).values():
        for step in (job.get("steps") or []):
            if step.get("run"):
                out.append(str(step["run"]))
    return "\n".join(out)

def uses_list(wf):
    out = []
    for job in (wf.get("jobs") or {}).values():
        for step in (job.get("steps") or []):
            if step.get("uses"):
                out.append(str(step["uses"]))
    return out

def step_if(wf, name_substr):
    """The `if:` of the first step whose name contains name_substr ('' if none)."""
    for job in (wf.get("jobs") or {}).values():
        for step in (job.get("steps") or []):
            if name_substr in str(step.get("name") or ""):
                return str(step.get("if") or "")
    return ""

def group(wf):
    c = wf.get("concurrency")
    return (c or {}).get("group", "") if isinstance(c, dict) else str(c or "")

def routes(wf, path):
    return any(fnmatch.fnmatch(path, p) for p in paths(wf))

D = "apps/web-platform/infra/inngest-rls/"
prd_run = all_run_text(prd)

checks = {
    # --- Path routing: simulate a real edited file against each `paths:` filter ---
    # The prd workflow applies 0001 and ONLY 0001, so ONLY 0001 may trigger it.
    "prd_routes_0001":        routes(prd, D + "0001_enable_rls_lockdown.sql"),
    "prd_ignores_0002":       not routes(prd, D + "0002_dev_inngest_tables_lockdown.sql"),
    "prd_ignores_probe":      not routes(prd, D + "anon-probe.sh"),
    "prd_ignores_tests":      not routes(prd, D + "inngest-rls.test.sh"),
    "prd_ignores_devwf":      not routes(prd, ".github/workflows/apply-inngest-rls-dev.yml"),
    "prd_no_wildcard_glob":   not any(p.rstrip("/").endswith("**") for p in paths(prd)),

    # --- Project pinning: literal refs, never interpolated ---
    # EVERY declaration must equal the literal, not merely the first one.
    "prd_ref_pinned":         env_all_eq(prd, "PROJECT_REF", "pigsfuxruiopinouvjwy"),

    # --- Identity preflight (the PRIMARY project guard) ---
    "prd_identity_name":      env_all_eq(prd, "PROJECT_NAME", "soleur-inngest-prd"),
    "prd_identity_call":      "/v1/projects/" in prd_run and "identity_mismatch" in prd_run,

    # --- Gate semantics: the prd gate must stay SCHEMA-WIDE -----------------------
    # On a DEDICATED Inngest project an allowlist-scoped gate would silently stop
    # covering every table a future Inngest version ships, so prd_gate_schemawide
    # asserts the absence of the scoping predicate. (The now-retired dev gate was
    # the deliberate inversion — allowlist-scoped, because a schema-wide gate can
    # never reach 0 on a co-tenanted project where 52 app tables hold anon grants
    # by design. That inversion is why they were two workflows and not a matrix.)
    "prd_gate_grants":        "has_table_privilege" in prd_run,
    "prd_gate_truncate":      "TRUNCATE" in prd_run.upper(),
    "prd_gate_rls":           "relrowsecurity" in prd_run,
    "prd_gate_owner":         "pg_get_userbyid" in prd_run,
    "prd_gate_schemawide":    "relname = ANY(" not in prd_run and "relname = any(" not in prd_run,



    # --- Probe wiring + supply chain ---
    # `uses_list(wf) and ...` is load-bearing: all([]) is True, so stripping every
    # `uses:` from a workflow made this PASS vacuously (GREEN 37/0, mutation-proven
    # 2026-07-15). The workflow checks out the repo, so an empty list is itself a defect.
    "prd_uses_sha_pinned":    bool(uses_list(prd)) and
                              all(("@" in u and len(u.split("@")[1].split()[0]) == 40) for u in uses_list(prd)),
}
print("yes" if checks[sys.argv[2]] else "no")
PY
}

# --- Path routing (finding 0: trigger bleed onto Inngest prd) -----------------
assert "prd workflow IS triggered by a 0001 edit" "[[ $(probe prd_routes_0001) == yes ]]"
assert "prd workflow is NOT triggered by a 0002 edit (finding 0)" "[[ $(probe prd_ignores_0002) == yes ]]"
assert "prd workflow is NOT triggered by an anon-probe.sh edit" "[[ $(probe prd_ignores_probe) == yes ]]"
assert "prd workflow is NOT triggered by a shape-guard edit" "[[ $(probe prd_ignores_tests) == yes ]]"
assert "prd workflow is NOT triggered by the dev workflow's own edit" "[[ $(probe prd_ignores_devwf) == yes ]]"
assert "prd paths carry no '**' wildcard (re-widening re-opens the blast radius)" "[[ $(probe prd_no_wildcard_glob) == yes ]]"

# --- Project pinning ----------------------------------------------------------
assert "prd PROJECT_REF is the pinned soleur-inngest-prd literal" "[[ $(probe prd_ref_pinned) == yes ]]"

# --- Identity preflight -------------------------------------------------------
assert "prd asserts project name soleur-inngest-prd" "[[ $(probe prd_identity_name) == yes ]]"
assert "prd performs the identity GET and fails closed on mismatch" "[[ $(probe prd_identity_call) == yes ]]"

# --- Gate semantics -----------------------------------------------------------
assert "prd gate asserts grants (has_table_privilege), not just RLS" "[[ $(probe prd_gate_grants) == yes ]]"
assert "prd gate asserts TRUNCATE" "[[ $(probe prd_gate_truncate) == yes ]]"
assert "prd gate asserts relrowsecurity" "[[ $(probe prd_gate_rls) == yes ]]"
assert "prd gate asserts postgres ownership" "[[ $(probe prd_gate_owner) == yes ]]"
assert "prd gate is SCHEMA-WIDE (scoping it would stop covering future Inngest tables)" "[[ $(probe prd_gate_schemawide) == yes ]]"

# --- Probe wiring + supply chain ---------------------------------------------
assert "prd workflow SHA-pins every uses:" "[[ $(probe prd_uses_sha_pinned) == yes ]]"

echo ""
echo "passed=$PASS failed=$FAIL"

# ANTI-VACUITY FLOOR (Guard 1). Reported with printf + exit rather than through
# assert(), because assert() is the thing this backstops: a mutation that stops
# assert() incrementing must not be able to route this verdict through it.
# `-lt`, NOT `-ne`, and that is two decisions rather than a style choice.
#
# (a) A FLOOR is the correct semantics: the count is developer-incremented, so `-ne` turns
#     every legitimately-added assertion into a spurious failure, which trains the next author
#     to edit the number reflexively -- the exact habit the message below asks them not to form.
#     Removal is the direction that loses coverage silently, and a floor catches it.
# (b) `-ne` is INVISIBLE to scripts/guard-vacuity-floor.test.sh, the repo's meta-guard for
#     "can this floor actually fire". Its population regex admits `-lt|-le|-ge` (its header
#     records that `-eq`/`-gt` were tried and reverted), so a `-ne` floor is bounded by nothing
#     and deleting this block outright would go unnoticed. Measured during review: this file
#     returned ZERO candidate lines while the three other floors this PR adds all matched. That
#     is the one failure mode the meta-guard's own header says it cannot report on itself.
# Bound HERE as a literal, adjacent to the `if`, with NOTHING between them.
# scripts/guard-vacuity-floor.test.sh builds its mutant by slicing the `if` plus the CONTIGUOUS
# simple assignments above it, so a threshold bound far away is UNBOUND in that slice: the
# mutant dies at `set -u` and the floor scores CONSTRUCTION (status unknown) rather than FIRING.
#
# "Contiguous" is literal. An intervening `if`/`fi` breaks the walk even when the binding is one
# line further up -- measured during review: a drift-pin comparing this against a second
# declaration sat between the two and put the file straight back into the uncovered set. Two
# variables pinned to each other was the wrong shape; one literal in one place is the right one.
#
# Derived 2026-09-19 at the commit that retired the dev half: 15 `probe` assertions
# (6 path-routing + 1 project pinning + 2 identity + 5 gate semantics + 1 supply chain) plus
# 2 file-level assertions (prd workflow exists, prd YAML parses) = 17.
EXPECTED_TOTAL=17
if [[ $((PASS + FAIL)) -lt "$EXPECTED_TOTAL" ]]; then
  # The wording carries a term from guard-vacuity-floor.test.sh's FIRES sentinel vocabulary
  # (`anti-vacuity`, `assertion floor`, `only <n>`, `[FATAL]`, ...). That is not decoration: the
  # meta-guard classifies a mutant by exit code AND recognised output, so a floor that exits
  # non-zero with an unrecognised message is scored CONSTRUCTION -- status unknown -- rather
  # than FIRING, and silently leaves the covered set. Measured twice in this PR, on two
  # different files, which is why it is written down at the message rather than remembered.
  printf '\n[FATAL] anti-vacuity assertion floor: only %d assertion(s) ran, expected >= %d (EXPECTED_TOTAL).\n' \
    "$((PASS + FAIL))" "$EXPECTED_TOTAL" >&2
  printf 'An assert line was removed. Investigate it; do not lower the number to match.\n' >&2
  exit 1
fi

[[ "$FAIL" -eq 0 ]] || exit 1
