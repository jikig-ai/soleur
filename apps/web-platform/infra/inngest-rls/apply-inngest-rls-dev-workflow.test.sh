#!/usr/bin/env bash
# Shape guard for the PAIR of Inngest RLS apply workflows:
#   .github/workflows/apply-inngest-rls.yml      -> soleur-inngest-prd (pigsfuxruiopinouvjwy)
#   .github/workflows/apply-inngest-rls-dev.yml  -> soleur-dev         (mlwiodleouzwniehynfz)
#
# WHY A CHECKED-IN GUARD AND NOT A ONE-SHOT PR REVIEW: a PR-time grep does not stop a
# later de-pin, a re-widened `paths:` glob, or a copy-paste that re-collides the two
# workflows' issue titles. actionlint is local-only (it runs in ZERO workflows), so a
# checked-in test invoked by infra-validation.yml is the enforceable gate.
#
# THE TWO FAILURES THIS EXISTS TO PREVENT:
#  1. TRIGGER BLEED (finding 0). apply-inngest-rls.yml used to trigger on
#     'apps/web-platform/infra/inngest-rls/**' — matching EVERY file in that directory.
#     Editing a dev-only artifact therefore auto-applied 0001 (a schema-wide REVOKE-all)
#     to the brand-survival-critical Inngest PRD project. The path-routing assertions
#     below simulate real edited paths against the parsed `paths:` filters.
#  2. IDENTITY COLLISION. The prd workflow auto-closes any open issue matching its own
#     title on success. A verbatim-copied ISSUE_TITLE would mean a green prd run silently
#     closes dev's open failure issue; a shared `concurrency.group` would queue them.
#
# Asserted against the PARSED YAML rather than greps, so a reformat or a comment
# mentioning an idiom cannot false-PASS the gate.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
PRD_WF="$REPO_ROOT/.github/workflows/apply-inngest-rls.yml"
DEV_WF="$REPO_ROOT/.github/workflows/apply-inngest-rls-dev.yml"

PASS=0
FAIL=0
assert() {
  local desc="$1" cond="$2"
  if eval "$cond"; then echo "  PASS: $desc"; PASS=$((PASS + 1));
  else echo "  FAIL: $desc"; echo "    cond: $cond"; FAIL=$((FAIL + 1)); fi
}

echo "=== apply-inngest-rls{,-dev}.yml shape guards ==="

assert "prd workflow exists" "[[ -f '$PRD_WF' ]]"
assert "dev workflow exists" "[[ -f '$DEV_WF' ]]"
assert "prd YAML parses (pyyaml)" "python3 -c 'import yaml; yaml.safe_load(open(\"$PRD_WF\"))'"
assert "dev YAML parses (pyyaml)" "python3 -c 'import yaml; yaml.safe_load(open(\"$DEV_WF\"))'"

# All shape probes run in python and emit a bare yes/no token. Rationale (inherited from
# restart-inngest-workflow-guard.test.sh): round-tripping YAML strings that contain spaces
# and quotes through a shell variable into `eval` mangles the quoting and silently
# false-FAILS a correct workflow.
probe() {
  python3 - "$PRD_WF" "$DEV_WF" "$1" <<'PY'
import sys, yaml, fnmatch

prd = yaml.safe_load(open(sys.argv[1])) or {}
dev = yaml.safe_load(open(sys.argv[2])) or {}

def triggers(wf):
    # `on` is YAML 1.1 truthy: pyyaml keys it as boolean True, NOT the string "on".
    # Probe both spellings or this reads as "no triggers" and every path assertion
    # below passes VACUOUSLY.
    return wf.get("on", wf.get(True)) or {}

def paths(wf):
    return (triggers(wf).get("push") or {}).get("paths") or []

def step_env(wf, key):
    for job in (wf.get("jobs") or {}).values():
        for step in (job.get("steps") or []):
            env = step.get("env") or {}
            if key in env:
                return str(env[key])
    return ""

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

def group(wf):
    c = wf.get("concurrency")
    return (c or {}).get("group", "") if isinstance(c, dict) else str(c or "")

def routes(wf, path):
    return any(fnmatch.fnmatch(path, p) for p in paths(wf))

D = "apps/web-platform/infra/inngest-rls/"
prd_run, dev_run = all_run_text(prd), all_run_text(dev)

checks = {
    # --- Path routing: simulate a real edited file against each `paths:` filter ---
    # The prd workflow applies 0001 and ONLY 0001, so ONLY 0001 may trigger it.
    "prd_routes_0001":        routes(prd, D + "0001_enable_rls_lockdown.sql"),
    "prd_ignores_0002":       not routes(prd, D + "0002_dev_inngest_tables_lockdown.sql"),
    "prd_ignores_probe":      not routes(prd, D + "anon-probe.sh"),
    "prd_ignores_tests":      not routes(prd, D + "inngest-rls.test.sh"),
    "prd_ignores_devwf":      not routes(prd, ".github/workflows/apply-inngest-rls-dev.yml"),
    "prd_no_wildcard_glob":   not any(p.rstrip("/").endswith("**") for p in paths(prd)),
    # The dev workflow applies 0002 and ONLY 0002.
    "dev_routes_0002":        routes(dev, D + "0002_dev_inngest_tables_lockdown.sql"),
    "dev_routes_pin_bump":    routes(dev, "apps/web-platform/infra/cloud-init-inngest.yml"),
    "dev_ignores_0001":       not routes(dev, D + "0001_enable_rls_lockdown.sql"),
    "dev_no_wildcard_glob":   not any(p.rstrip("/").endswith("**") for p in paths(dev)),

    # --- Project pinning: literal refs, never interpolated ---
    "dev_ref_pinned":         step_env(dev, "PROJECT_REF") == "mlwiodleouzwniehynfz",
    "prd_ref_pinned":         step_env(prd, "PROJECT_REF") == "pigsfuxruiopinouvjwy",
    "dev_ref_not_interp":     "${{" not in step_env(dev, "PROJECT_REF"),
    "dev_no_prd_ref":         "pigsfuxruiopinouvjwy" not in open(sys.argv[2]).read(),
    "dev_no_0001":            "0001_enable_rls_lockdown" not in open(sys.argv[2]).read(),
    "dev_applies_0002":       "0002_dev_inngest_tables_lockdown.sql" in step_env(dev, "SQL_FILE"),

    # --- Identity preflight (the PRIMARY project guard) ---
    "dev_identity_name":      step_env(dev, "PROJECT_NAME") == "soleur-dev",
    "prd_identity_name":      step_env(prd, "PROJECT_NAME") == "soleur-inngest-prd",
    "dev_identity_call":      "/v1/projects/" in dev_run and "identity_mismatch" in dev_run,
    "prd_identity_call":      "/v1/projects/" in prd_run and "identity_mismatch" in prd_run,

    # --- The dev gate must assert GRANTS incl. TRUNCATE, not just relrowsecurity ---
    # RLS does not gate TRUNCATE and PostgREST has no TRUNCATE verb, so this catalog
    # gate is the only place the anon wipe vector can be proven closed.
    "dev_gate_grants":        "has_table_privilege" in dev_run,
    "dev_gate_truncate":      "TRUNCATE" in dev_run.upper(),
    "dev_gate_rls":           "relrowsecurity" in dev_run,
    "dev_gate_owner":         "pg_get_userbyid" in dev_run,
    # Scoped to the allowlist: a schema-wide gate can NEVER reach 0 on co-tenanted dev
    # (52 app tables hold anon grants by design) and would fail forever.
    "dev_gate_scoped":        "relname = ANY(" in dev_run or "relname = any(" in dev_run,
    "dev_gate_coverage":      "gate_coverage" in dev_run,

    # --- No collision with the prd workflow's issue/label/concurrency identity ---
    "titles_differ":          ("[ci/inngest-rls-dev]" in dev_run) and ("[ci/inngest-rls-dev]" not in prd_run),
    "labels_differ":          ("ci/inngest-rls-dev" in dev_run) and ("ci/inngest-rls-dev" not in prd_run),
    "groups_differ":          group(dev) != group(prd) and group(dev) != "",
    "killswitch_differs":     "[skip-inngest-rls-dev-apply]" in str(dev),

    # --- Probe wiring + supply chain ---
    "dev_runs_probe":         "anon-probe.sh" in dev_run,
    "dev_uses_sha_pinned":    all(("@" in u and len(u.split("@")[1].split()[0]) == 40) for u in uses_list(dev)),
    "prd_uses_sha_pinned":    all(("@" in u and len(u.split("@")[1].split()[0]) == 40) for u in uses_list(prd)),
}
print("yes" if checks[sys.argv[3]] else "no")
PY
}

# --- Path routing (finding 0: trigger bleed onto Inngest prd) -----------------
assert "prd workflow IS triggered by a 0001 edit" "[[ $(probe prd_routes_0001) == yes ]]"
assert "prd workflow is NOT triggered by a 0002 edit (finding 0)" "[[ $(probe prd_ignores_0002) == yes ]]"
assert "prd workflow is NOT triggered by an anon-probe.sh edit" "[[ $(probe prd_ignores_probe) == yes ]]"
assert "prd workflow is NOT triggered by a shape-guard edit" "[[ $(probe prd_ignores_tests) == yes ]]"
assert "prd workflow is NOT triggered by the dev workflow's own edit" "[[ $(probe prd_ignores_devwf) == yes ]]"
assert "prd paths carry no '**' wildcard (re-widening re-opens the blast radius)" "[[ $(probe prd_no_wildcard_glob) == yes ]]"
assert "dev workflow IS triggered by a 0002 edit" "[[ $(probe dev_routes_0002) == yes ]]"
assert "dev workflow IS triggered by a goose image-pin bump" "[[ $(probe dev_routes_pin_bump) == yes ]]"
assert "dev workflow is NOT triggered by a 0001 edit" "[[ $(probe dev_ignores_0001) == yes ]]"
assert "dev paths carry no '**' wildcard" "[[ $(probe dev_no_wildcard_glob) == yes ]]"

# --- Project pinning ----------------------------------------------------------
assert "dev PROJECT_REF is the pinned soleur-dev literal" "[[ $(probe dev_ref_pinned) == yes ]]"
assert "prd PROJECT_REF is the pinned soleur-inngest-prd literal" "[[ $(probe prd_ref_pinned) == yes ]]"
assert "dev PROJECT_REF is not interpolated from event/input" "[[ $(probe dev_ref_not_interp) == yes ]]"
assert "dev workflow never names the prd project ref" "[[ $(probe dev_no_prd_ref) == yes ]]"
assert "dev workflow never applies 0001" "[[ $(probe dev_no_0001) == yes ]]"
assert "dev workflow applies 0002" "[[ $(probe dev_applies_0002) == yes ]]"

# --- Identity preflight -------------------------------------------------------
assert "dev asserts project name soleur-dev" "[[ $(probe dev_identity_name) == yes ]]"
assert "prd asserts project name soleur-inngest-prd" "[[ $(probe prd_identity_name) == yes ]]"
assert "dev performs the identity GET and fails closed on mismatch" "[[ $(probe dev_identity_call) == yes ]]"
assert "prd performs the identity GET and fails closed on mismatch" "[[ $(probe prd_identity_call) == yes ]]"

# --- Gate semantics -----------------------------------------------------------
assert "dev gate asserts grants (has_table_privilege), not just RLS" "[[ $(probe dev_gate_grants) == yes ]]"
assert "dev gate asserts TRUNCATE (RLS never gates it; PostgREST has no TRUNCATE verb)" "[[ $(probe dev_gate_truncate) == yes ]]"
assert "dev gate asserts relrowsecurity" "[[ $(probe dev_gate_rls) == yes ]]"
assert "dev gate asserts postgres ownership" "[[ $(probe dev_gate_owner) == yes ]]"
assert "dev gate is allowlist-scoped (a schema-wide gate never reaches 0 on dev)" "[[ $(probe dev_gate_scoped) == yes ]]"
assert "dev gate has a coverage guard (violations=0 over 0 rows is vacuous)" "[[ $(probe dev_gate_coverage) == yes ]]"

# --- Identity collision -------------------------------------------------------
assert "issue titles differ (a green prd run must not close dev's failure issue)" "[[ $(probe titles_differ) == yes ]]"
assert "issue labels differ" "[[ $(probe labels_differ) == yes ]]"
assert "concurrency groups differ" "[[ $(probe groups_differ) == yes ]]"
assert "kill-switch token is distinct from the prd workflow's" "[[ $(probe killswitch_differs) == yes ]]"

# --- Probe wiring + supply chain ---------------------------------------------
assert "dev workflow invokes anon-probe.sh (Phase 3 has an executor)" "[[ $(probe dev_runs_probe) == yes ]]"
assert "dev workflow SHA-pins every uses:" "[[ $(probe dev_uses_sha_pinned) == yes ]]"
assert "prd workflow SHA-pins every uses:" "[[ $(probe prd_uses_sha_pinned) == yes ]]"

echo ""
echo "passed=$PASS failed=$FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
