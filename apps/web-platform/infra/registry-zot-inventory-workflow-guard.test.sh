#!/usr/bin/env bash
# Guard tests for the read-only zot disk-inventory lever (#7278).
#
# THREE SUBJECTS, one suite, because they share one failure mode — a gate that LOOKS present
# and does nothing:
#   1. .github/workflows/registry-zot-inventory.yml          — the #6425 self-trigger guard
#   2. .github/workflows/registry-zot-inventory-dispatch.yml — the label + Bot authority boundary
#   3. .github/actions/cf-tunnel-registry-bridge/action.yml  — the fail-closed skip-docker-login gate
# plus the CI wiring in .github/workflows/infra-validation.yml that makes this file run at all.
#
# EVERYTHING IS ASSERTED AGAINST THE PARSED YAML, never a grep. A grep passes on a commented-out
# step, on a guard moved onto a different job, and on a comment that merely mentions the idiom.
# The CI-wiring assertions in particular are the reason this rule is not negotiable here: a grep
# for the registration of THIS FILE would pass on a `# - run: bash ...registry-zot-inventory-
# workflow-guard.test.sh` line, i.e. the suite would certify its own de-registration.
#
# WHY THE COMPARISONS HAPPEN INSIDE PYTHON. The job `if:` string contains both spaces and single
# quotes. Round-tripping it through a shell variable into `eval` mangles the quoting and silently
# false-FAILS a correct workflow. Python emits bare `yes`/`no` tokens instead.
#
# WHY BOTH `on:` SPELLINGS ARE PROBED. `on` is YAML 1.1 truthy: pyyaml keys it as the BOOLEAN
# True, not the string "on". Probing only `"on"` reads as "this workflow has no triggers" and
# every trigger assertion PASSES VACUOUSLY. Arm 5.1b below exercises both spellings against
# synthetic fixtures so neither branch of `wf.get("on", wf.get(True))` can rot into dead code.
#
# NON-VACUITY. Arm 5.1c copies the workflow to a scratch dir, DELETES the job-level `if:`, and
# requires the guard probe to flip to `no`. Without it, "the guard is present" is a human claim
# about a test nobody has seen fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

WF="$REPO_ROOT/.github/workflows/registry-zot-inventory.yml"
DISPATCH_WF="$REPO_ROOT/.github/workflows/registry-zot-inventory-dispatch.yml"
BRIDGE="$REPO_ROOT/.github/actions/cf-tunnel-registry-bridge/action.yml"
INFRA_WF="$REPO_ROOT/.github/workflows/infra-validation.yml"

# A skip is not a pass. TMPDIR is pinned so a runner with a tiny /tmp cannot turn the mutation
# arm into a silent no-op.
export TMPDIR="${TMPDIR:-/var/tmp}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
assert() {
  local desc="$1" cond="$2"
  if eval "$cond"; then echo "  PASS: $desc"; PASS=$((PASS + 1));
  else echo "  FAIL: $desc"; echo "    cond: $cond"; FAIL=$((FAIL + 1)); fi
}

echo "=== registry-zot-inventory guard tests (#7278) ==="

assert "inventory workflow exists" "[[ -f '$WF' ]]"
assert "dispatch workflow exists" "[[ -f '$DISPATCH_WF' ]]"
assert "cf-tunnel-registry-bridge composite exists" "[[ -f '$BRIDGE' ]]"
assert "infra-validation workflow exists" "[[ -f '$INFRA_WF' ]]"

for f in "$WF" "$DISPATCH_WF" "$BRIDGE" "$INFRA_WF"; do
  assert "YAML parses (pyyaml): ${f#"$REPO_ROOT/"}" \
    "python3 -c 'import yaml; yaml.safe_load(open(\"$f\"))'"
done

# ---------------------------------------------------------------------------
# The trigger/guard probe. Takes a workflow path + a check name, prints yes/no.
# Parameterised by PATH on purpose: the mutation arm re-runs it against a mutated copy.
# ---------------------------------------------------------------------------
probe_wf() {
  python3 - "$1" "$2" <<'PY'
import sys, yaml

wf = yaml.safe_load(open(sys.argv[1])) or {}
# `on` is YAML 1.1 truthy — pyyaml keys it as boolean True. Probe BOTH spellings or a bare
# `on:` workflow reads as "no triggers" and every trigger check passes vacuously.
on = wf.get("on", wf.get(True)) or {}
jobs = wf.get("jobs") or {}
GUARD = "github.event_name == 'workflow_dispatch'"

def every_job_guarded():
    # ITERATE ALL JOBS, never pin one. Pinning a single key lets a future second job ship
    # unguarded and fire on every registration push — the #6425 class re-entering through the
    # one door the guard does not watch. An empty jobs map is NOT a pass.
    if not jobs:
        return False
    return all(GUARD in str(j.get("if", "")) for j in jobs.values())

def dispatch_input_is_single_choice():
    inp = ((on.get("workflow_dispatch") or {}).get("inputs") or {}).get("action")
    if not isinstance(inp, dict):
        return False
    return inp.get("type") == "choice" and list(inp.get("options") or []) == ["inventory"]

def push_paths_self_scoped():
    paths = list((on.get("push") or {}).get("paths") or [])
    return len(paths) == 1 and paths[0].endswith(sys.argv[1].rsplit("/", 1)[-1])

def checkout_sha_pinned():
    for j in jobs.values():
        for s in (j.get("steps") or []):
            u = str(s.get("uses", ""))
            if u.startswith("actions/checkout@"):
                ref = u.split("@", 1)[1]
                # 40-hex = a SHA pin. A tag or branch ref is not a pin.
                if len(ref) == 40 and all(c in "0123456789abcdef" for c in ref.lower()):
                    return True
                return False
    return False

def _bridge_with(field):
    """The value the bridge step passes for `field`, normalised to a string. None if absent."""
    for j in jobs.values():
        for s in (j.get("steps") or []):
            if "cf-tunnel-registry-bridge" in str(s.get("uses", "")):
                with_ = s.get("with") or {}
                if field not in with_:
                    return None
                v = with_[field]
                # A YAML-bare `true` parses as a Python bool; Actions renders it as the string
                # 'true'. Normalise so the gate's literal-string contract can be asserted
                # without a bare-vs-quoted false RED.
                return "true" if v is True else ("false" if v is False else str(v))
    return None

def bridge_passes_literal(field, want):
    return _bridge_with(field) == want

def bridge_passes_secret(field, secret_name):
    # Asserted by CONTAINMENT, not equality: the value is a `${{ secrets.X }}` expression, and
    # pinning its exact whitespace would red on a harmless reformat. What must hold is which
    # secret is named — DOPPLER_TOKEN_PRD, never the prd_terraform-scoped DOPPLER_TOKEN, which
    # cannot read the prd root at all.
    v = _bridge_with(field)
    return v is not None and secret_name in v and "secrets." in v

def bridge_forwards(field):
    for j in jobs.values():
        for s in (j.get("steps") or []):
            if "cf-tunnel-registry-bridge" in str(s.get("uses", "")):
                return field in (s.get("with") or {})
    return False

def has_teardown_always():
    for j in jobs.values():
        for s in (j.get("steps") or []):
            if "docker logout 127.0.0.1:5000" in str(s.get("run", "")):
                return str(s.get("if", "")).strip() == "always()"
    return False

def concurrency_serialised():
    for j in jobs.values():
        c = j.get("concurrency")
        if isinstance(c, dict) and c.get("group") == "registry-zot-inventory":
            return c.get("cancel-in-progress") is False
    return False

def perms():
    p = wf.get("permissions") or {}
    return p.get("contents") == "read" and p.get("issues") == "write"

def comments_on_7247():
    # #7278 is CLOSED by the PR that adds this lever, so it is not a valid recording target.
    # #7247 is the OPEN action-required incident the number is evidence for.
    blob = "\n".join(str(s.get("run", "")) for j in jobs.values() for s in (j.get("steps") or []))
    return "gh issue comment 7247" in blob

def dispatch_guard_two_clause():
    # A label alone is NOT an authority boundary — applying one needs only Triage.
    if not jobs:
        return False
    for j in jobs.values():
        cond = str(j.get("if", ""))
        if "github.event.label.name ==" not in cond:
            return False
        if "github.event.issue.user.type == 'Bot'" not in cond:
            return False
    return True

checks = {
    "push": "push" in on,
    "dispatch": "workflow_dispatch" in on,
    "guard_every_job": every_job_guarded(),
    "jobs_exact_inventory": set(jobs) == {"inventory"},
    "single_choice_input": dispatch_input_is_single_choice(),
    "push_paths_self": push_paths_self_scoped(),
    "checkout_pinned": checkout_sha_pinned(),
    "timeout_set": all(isinstance(j.get("timeout-minutes"), int) for j in jobs.values()) and bool(jobs),
    "concurrency": concurrency_serialised(),
    "permissions": perms(),
    "skip_docker_login_true": bridge_passes_literal("skip-docker-login", "true"),
    "bridge_token_prd": bridge_passes_secret("doppler-token", "DOPPLER_TOKEN_PRD"),
    # NEGATIVE CONTROL for the check above. `DOPPLER_TOKEN_PRD` CONTAINS `DOPPLER_TOKEN` as a
    # substring, so a containment test alone would pass on the wrong secret. Requiring the
    # rendered value NOT to name the bare token discriminates the two.
    "bridge_not_bare_token": (_bridge_with("doppler-token") or "").replace(
        "DOPPLER_TOKEN_PRD", "") .find("DOPPLER_TOKEN") == -1,
    "forwards_verdict": bridge_forwards("token-verdict"),
    "forwards_checked_at": bridge_forwards("token-checked-at"),
    "forwards_cause": bridge_forwards("token-cause"),
    "teardown_always": has_teardown_always(),
    "comments_7247": comments_on_7247(),
    "dispatch_guard_two_clause": dispatch_guard_two_clause(),
}
print("yes" if checks[sys.argv[2]] else "no")
PY
}

echo ""
echo "--- 5.1 / 5.1a: the #6425 self-trigger guard, asserted over ALL jobs ---"

# Premise: the guard is only meaningful while BOTH triggers exist. Stated rather than
# silently passed — if the registration push is ever dropped, the guard is moot.
assert "inventory workflow carries the registration push trigger (guard premise)" \
  "[[ \$(probe_wf '$WF' push) == 'yes' ]]"
assert "inventory workflow carries workflow_dispatch (the real entry point)" \
  "[[ \$(probe_wf '$WF' dispatch) == 'yes' ]]"
assert "push trigger is scoped to this workflow file only (registration, not a content trigger)" \
  "[[ \$(probe_wf '$WF' push_paths_self) == 'yes' ]]"
assert "EVERY job is gated on workflow_dispatch (not just one pinned job key)" \
  "[[ \$(probe_wf '$WF' guard_every_job) == 'yes' ]]"
assert "the job set is exactly {inventory} (a new job must be added to the guard deliberately)" \
  "[[ \$(probe_wf '$WF' jobs_exact_inventory) == 'yes' ]]"

echo ""
echo "--- 3.1 / 3.1a: dispatch surface, permissions, serialisation, pinning ---"

assert "the only dispatch input is a single-value choice {inventory}" \
  "[[ \$(probe_wf '$WF' single_choice_input) == 'yes' ]]"
assert "actions/checkout is SHA-pinned (40-hex), not tag-pinned" \
  "[[ \$(probe_wf '$WF' checkout_pinned) == 'yes' ]]"
assert "every job carries a timeout-minutes cap" \
  "[[ \$(probe_wf '$WF' timeout_set) == 'yes' ]]"
assert "concurrency group registry-zot-inventory with cancel-in-progress: false" \
  "[[ \$(probe_wf '$WF' concurrency) == 'yes' ]]"
assert "permissions are contents:read AND issues:write (read-only cannot record on #7247)" \
  "[[ \$(probe_wf '$WF' permissions) == 'yes' ]]"
assert "the recording target is #7247 (open), never #7278 (closed by this PR)" \
  "[[ \$(probe_wf '$WF' comments_7247) == 'yes' ]]"

echo ""
echo "--- 3.2: the bridge call forwards what the job MEASURED (ADR-166) ---"

assert "the bridge is called with skip-docker-login: 'true'" \
  "[[ \$(probe_wf '$WF' skip_docker_login_true) == 'yes' ]]"
assert "the bridge gets DOPPLER_TOKEN_PRD (branch configs do NOT inherit from the prd root)" \
  "[[ \$(probe_wf '$WF' bridge_token_prd) == 'yes' ]]"
assert "and it is NOT the bare prd_terraform-scoped DOPPLER_TOKEN (substring discriminator)" \
  "[[ \$(probe_wf '$WF' bridge_not_bare_token) == 'yes' ]]"
for f in token-verdict token-checked-at token-cause; do
  key="forwards_${f//-/_}"
  key="${key/token_verdict/verdict}"; key="${key/token_checked_at/checked_at}"; key="${key/token_cause/cause}"
  assert "the bridge call forwards $f (omitting it commits the ADR-166 defect the preflight exists to avoid)" \
    "[[ \$(probe_wf '$WF' $key) == 'yes' ]]"
done
assert "an if: always() teardown copied from the composite's documented contract is present" \
  "[[ \$(probe_wf '$WF' teardown_always) == 'yes' ]]"

echo ""
echo "--- 3.4: the dispatch route's authority boundary needs BOTH clauses ---"

assert "dispatch workflow guards on the controlled label AND issue.user.type == 'Bot'" \
  "[[ \$(probe_wf '$DISPATCH_WF' dispatch_guard_two_clause) == 'yes' ]]"
assert "dispatch workflow carries its own registration push trigger" \
  "[[ \$(probe_wf '$DISPATCH_WF' push) == 'yes' ]]"

echo ""
echo "--- 5.1b: BOTH \`on:\` key spellings are exercised, so neither .get arm is dead code ---"

# Without this pair, `wf.get("on", wf.get(True))` has one live branch and one that has never
# executed. pyyaml keys a BARE `on:` as boolean True and a QUOTED `"on":` as the string "on".
cat > "$TMP/bare-on.yml" <<'YML'
name: fixture bare on
on:
  workflow_dispatch: {}
  push:
    branches: [main]
    paths:
      - '.github/workflows/bare-on.yml'
jobs:
  inventory:
    if: github.event_name == 'workflow_dispatch'
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - run: 'true'
YML
cat > "$TMP/quoted-on.yml" <<'YML'
name: fixture quoted on
"on":
  workflow_dispatch: {}
  push:
    branches: [main]
    paths:
      - '.github/workflows/quoted-on.yml'
jobs:
  inventory:
    if: github.event_name == 'workflow_dispatch'
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - run: 'true'
YML

assert "pyyaml really does key a BARE \`on:\` as boolean True (the premise this probe defends against)" \
  "python3 -c 'import yaml,sys; d=yaml.safe_load(open(\"$TMP/bare-on.yml\")); sys.exit(0 if (True in d and \"on\" not in d) else 1)'"
assert "the trigger probe reads a BARE \`on:\` fixture (wf.get(True) arm is live)" \
  "[[ \$(probe_wf '$TMP/bare-on.yml' dispatch) == 'yes' ]]"
assert "the trigger probe reads a QUOTED \`\"on\":\` fixture (wf.get(\"on\") arm is live)" \
  "[[ \$(probe_wf '$TMP/quoted-on.yml' dispatch) == 'yes' ]]"
assert "the guard probe passes on the bare-on fixture (positive control for the mutation below)" \
  "[[ \$(probe_wf '$TMP/bare-on.yml' guard_every_job) == 'yes' ]]"

echo ""
echo "--- 5.1c: MUTATION ARM — the guard probe must be able to go RED ---"

# Copy the REAL workflow, delete the job-level `if:` from every job, re-probe. A guard test
# that has never been observed failing is indistinguishable from one that cannot fail.
python3 - "$WF" "$TMP/mutant-no-guard.yml" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
for j in (wf.get("jobs") or {}).values():
    j.pop("if", None)
yaml.safe_dump(wf, open(sys.argv[2], "w"), sort_keys=False)
PY

# LANDING ASSERTION FIRST. A mutation that did not land is a null result wearing a pass's
# clothes — if the copy still carries an `if:`, the RED below would prove nothing.
assert "mutation landed: the scratch copy carries no job-level if:" \
  "python3 -c 'import yaml,sys; d=yaml.safe_load(open(\"$TMP/mutant-no-guard.yml\")); sys.exit(0 if all(\"if\" not in j for j in d[\"jobs\"].values()) else 1)'"
assert "guard-deleted mutant is REJECTED by the guard probe (probe returns no)" \
  "[[ \$(probe_wf '$TMP/mutant-no-guard.yml' guard_every_job) == 'no' ]]"

# Second mutant: a SECOND job added without the guard. This is the exact hole a single-pinned
# job key leaves open, and it is why the probe iterates instead of indexing.
python3 - "$WF" "$TMP/mutant-second-job.yml" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
wf["jobs"]["sneaky"] = {"runs-on": "ubuntu-latest", "steps": [{"run": "echo hi"}]}
yaml.safe_dump(wf, open(sys.argv[2], "w"), sort_keys=False)
PY
assert "mutation landed: the scratch copy carries a second, unguarded job" \
  "python3 -c 'import yaml,sys; d=yaml.safe_load(open(\"$TMP/mutant-second-job.yml\")); sys.exit(0 if \"sneaky\" in d[\"jobs\"] else 1)'"
assert "an unguarded SECOND job is REJECTED (a pinned job key would have passed this)" \
  "[[ \$(probe_wf '$TMP/mutant-second-job.yml' guard_every_job) == 'no' ]]"
assert "an unexpected second job is also caught by the job-set assertion" \
  "[[ \$(probe_wf '$TMP/mutant-second-job.yml' jobs_exact_inventory) == 'no' ]]"

echo ""
echo "--- 2.3: the composite's skip-docker-login gate, DURABLE invariants only ---"

# Deliberately NOT asserted: "none of the four pre-existing callers passes skip-docker-login".
# This PR's own workflow is a FIFTH caller that does, so that assertion would be RED on the
# same commit that introduces it. The one-shot migration check (a `git diff` showing no
# `with:` change on the four pre-existing callers) belongs in AC5 evidence, not in a permanent
# test. What IS permanent is invariant (i) below: a login condition of exactly `!= 'true'`
# guarantees "unchanged for any caller that does not pass the input" for ALL future callers.
probe_bridge() {
  python3 - "$BRIDGE" "$1" <<'PY'
import sys, yaml

a = yaml.safe_load(open(sys.argv[1])) or {}
inputs = a.get("inputs") or {}
steps = ((a.get("runs") or {}).get("steps")) or []
skip = inputs.get("skip-docker-login") or {}

def login_step():
    for s in steps:
        if "docker login" in str(s.get("name", "")).lower():
            return s
    return None

def login_gate_exact():
    s = login_step()
    if s is None:
        return False
    # EXACTLY `!= 'true'`. `== 'false'` inverts the failure direction: a typo'd or empty value
    # would then evaluate false and SILENTLY STRIP the push credential from every push caller.
    return str(s.get("if", "")).strip() == "inputs.skip-docker-login != 'true'"

def rejects_malformed():
    # The `case ... in true|false) ;; *) exit 1` normalizer, on an UNGATED step. Gating a
    # validator on the value it validates makes it unreachable for the values it rejects.
    for s in steps:
        body = str(s.get("run", ""))
        if "true|false)" in body and "exit 1" in body:
            return s.get("if") is None
    return False

def default_is_false():
    d = skip.get("default")
    return d == "false" or d is False

checks = {
    "input_exists": bool(skip),
    "default_false": default_is_false(),
    "not_required": skip.get("required") in (False, None),
    "login_gate_exact": login_gate_exact(),
    "rejects_malformed": rejects_malformed(),
}
print("yes" if checks[sys.argv[2]] else "no")
PY
}

assert "composite declares the skip-docker-login input" \
  "[[ \$(probe_bridge input_exists) == 'yes' ]]"
assert "its default is the literal 'false' (zero behaviour change for every existing caller)" \
  "[[ \$(probe_bridge default_false) == 'yes' ]]"
assert "it is optional, so no existing caller is forced to change" \
  "[[ \$(probe_bridge not_required) == 'yes' ]]"
assert "the login gate is EXACTLY \`inputs.skip-docker-login != 'true'\` (fail CLOSED, never == 'false')" \
  "[[ \$(probe_bridge login_gate_exact) == 'yes' ]]"
assert "a malformed value is rejected by an UNGATED normalizer step (case true|false / exit 1)" \
  "[[ \$(probe_bridge rejects_malformed) == 'yes' ]]"

# (ii) Discovered-set scan. The caller set must be NON-EMPTY first — an empty set trivially
# satisfies "every caller is well-formed", and an empty set is exactly what a renamed action
# directory would produce.
callers_scan() {
  python3 - "$REPO_ROOT" "$1" <<'PY'
import sys, os, yaml

root, mode = sys.argv[1], sys.argv[2]
wfdir = os.path.join(root, ".github", "workflows")
callers, bad = [], []
for fn in sorted(os.listdir(wfdir)):
    if not fn.endswith((".yml", ".yaml")):
        continue
    try:
        wf = yaml.safe_load(open(os.path.join(wfdir, fn))) or {}
    except Exception:
        continue
    for j in (wf.get("jobs") or {}).values():
        for s in (j.get("steps") or []):
            if "cf-tunnel-registry-bridge" not in str(s.get("uses", "")):
                continue
            callers.append(fn)
            v = (s.get("with") or {}).get("skip-docker-login", None)
            if v is None:
                continue  # omitting the key is the correct, zero-change form
            sv = "true" if v is True else ("false" if v is False else str(v))
            # An expression here would make the gate's value a runtime unknown, which is
            # precisely what a fail-closed literal exists to prevent.
            if "${{" in sv or sv not in ("true", "false"):
                bad.append(f"{fn}:{sv}")

if mode == "nonempty":
    print("yes" if len(callers) >= 4 else "no")
elif mode == "all_literal":
    print("yes" if not bad else "no")
elif mode == "list":
    print(" ".join(sorted(set(callers))))
PY
}

assert "the discovered caller set is non-empty (>=4 known callers; an empty set proves nothing)" \
  "[[ \$(callers_scan nonempty) == 'yes' ]]"
assert "every caller either omits skip-docker-login or sets a LITERAL true/false (never a \${{ }} expression)" \
  "[[ \$(callers_scan all_literal) == 'yes' ]]"
echo "  (discovered callers: $(callers_scan list))"

echo ""
echo "--- 5.2 / 5.2a: the CI wiring, asserted from PARSED YAML (a grep passes on a comment) ---"

probe_infra() {
  python3 - "$INFRA_WF" "$1" <<'PY'
import sys, yaml

wf = yaml.safe_load(open(sys.argv[1])) or {}
on = wf.get("on", wf.get(True)) or {}
jobs = wf.get("jobs") or {}
job = jobs.get("deploy-script-tests") or {}
runs = [str(s.get("run", "")) for s in (job.get("steps") or [])]
pr_paths = list((on.get("pull_request") or {}).get("paths") or [])

GUARD_SUITE = "apps/web-platform/infra/registry-zot-inventory-workflow-guard.test.sh"

checks = {
    "job_exists": bool(job),
    # The literal single-line `run: bash <path>` form is load-bearing beyond registration here:
    # apps/web-platform/infra/run-registered-suites.sh DERIVES its execute set from this job's
    # steps with a literal single-line match, so an inline env prefix or a `run: |` block
    # silently de-registers the suite from the local runner while it still LOOKS registered.
    "suite_registered": any(r.strip() == f"bash {GUARD_SUITE}" for r in runs),
    "inventory_wf_path": ".github/workflows/registry-zot-inventory.yml" in pr_paths,
    "dispatch_wf_path": ".github/workflows/registry-zot-inventory-dispatch.yml" in pr_paths,
    "bridge_action_path": ".github/actions/cf-tunnel-registry-bridge/action.yml" in pr_paths,
}
print("yes" if checks[sys.argv[2]] else "no")
PY
}

assert "infra-validation.yml still has a deploy-script-tests job" \
  "[[ \$(probe_infra job_exists) == 'yes' ]]"
assert "this suite is registered as a literal single-line \`run: bash <path>\` step" \
  "[[ \$(probe_infra suite_registered) == 'yes' ]]"
assert "registry-zot-inventory.yml is in that workflow's pull_request.paths" \
  "[[ \$(probe_infra inventory_wf_path) == 'yes' ]]"
assert "registry-zot-inventory-dispatch.yml is in that workflow's pull_request.paths" \
  "[[ \$(probe_infra dispatch_wf_path) == 'yes' ]]"
assert "cf-tunnel-registry-bridge/action.yml is in that workflow's pull_request.paths" \
  "[[ \$(probe_infra bridge_action_path) == 'yes' ]]"

echo ""
echo "--- AC6: the two touched files under apps/*/infra/ are Terraform-INERT ---"

# AC6 is "this change edits no Terraform", enforced by a pathspec that includes
# `apps/web-platform/infra/**` wholesale. Two files in this change live under it:
#   - this suite, which sits here because that is where deploy-script-tests' registered
#     suites live and nowhere else;
#   - restart-inngest-workflow-guard.test.sh, which received the iterate-all-jobs back-port
#     (the same hole, fleet-wide — a two-line fix that would otherwise need its own PR).
# Both are carve-outs, and a carve-out is only defensible while no Terraform reads the file.
# So the suite PROVES that rather than asserting it, and it proves it for both.
#
# `find | xargs grep` rather than `grep --include`: the -r/--include form silently depends on
# flag placement and on whatever `grep` resolves to in the caller's shell, and a filter that
# quietly stops filtering turns this into a vacuous check.
tf_consumers() {
  find "$REPO_ROOT/apps" "$REPO_ROOT/infra" -name '*.tf' -type f -print0 2>/dev/null \
    | xargs -0 grep -lF -- "$1" 2>/dev/null || true
}

# POSITIVE CONTROL FIRST. If the discovery finds no .tf files at all, every "not consumed"
# assertion below is satisfied trivially — and zero .tf files is what a moved infra root or a
# broken $REPO_ROOT produces.
assert "the .tf discovery set is non-empty (an empty set would satisfy the negatives vacuously)" \
  "[[ \$(find '$REPO_ROOT/apps' '$REPO_ROOT/infra' -name '*.tf' -type f 2>/dev/null | wc -l) -gt 0 ]]"
assert "no .tf consumes THIS suite (templatefile()/file() or otherwise)" \
  "[[ -z \"\$(tf_consumers registry-zot-inventory-workflow-guard.test.sh)\" ]]"
assert "no .tf consumes restart-inngest-workflow-guard.test.sh (the second AC6 carve-out)" \
  "[[ -z \"\$(tf_consumers restart-inngest-workflow-guard.test.sh)\" ]]"

echo ""
echo "=== Results: $PASS/$((PASS + FAIL)) passed ==="
if (( FAIL > 0 )); then
  echo "FAIL: $FAIL test(s) failed"
  exit 1
fi
