#!/usr/bin/env bash
# Wiring gate: the `vector_redeliver` job in .github/workflows/apply-web-platform-infra.yml
# must be wired the way the Guard Contract assumes — one plan artifact, graded by the sourced
# gate, consumed by one apply, behind the bridge that makes the plan authenticable.
#
# ── WHY THIS FILE EXISTS SEPARATELY FROM test-vector-redeliver-gate.sh ───────────────────────
# That suite proves the gate DECIDES correctly. It cannot prove the workflow CALLS it, calls it
# on the artifact the apply consumes, or that the apply is gated on its verdict at all — a
# `run:` body is not executable under test, so nothing else would ever exercise it. Every
# defect this file pins is one where the gate is perfect and the arm is still unsafe:
#
#   * the gate step present but `continue-on-error: true` — an ABORT that applies anyway;
#   * `terraform apply -target=…` instead of `apply tfplan` — a SECOND, ungraded plan, which
#     dissolves the Assembly's single-artifact chokepoint (the gate then grades a document the
#     apply never reads);
#   * the CF Tunnel bridge AFTER the plan — the plan bakes `ci_ssh_private_key = null` →
#     `agent = true` on an agent-less runner, and `apply <savedplan>` takes no variable input,
#     so the bridge's later export is inert (plan F10). This is an ORDERING fact; no unit test
#     can see it.
#
# ── WHY EVERY ASSERTION ANCHORS ON A CALL FORM ──────────────────────────────────────────────
# `cq-assert-anchor-not-bare-token`, and the measurement behind it is in this same repo:
# stock-preflight-coverage.test.ts:207-215 records that a bare `.includes("…-gate.sh")` was
# satisfied by the `# shellcheck source=` DIRECTIVE alone — "deleting all five real `source`
# lines left this suite green". So the rows below anchor on `^\s*source "…"$` and
# `^\s*if ! vector_redeliver_gate "…"; then$`, never on the filename or the function name as a
# token, and every read is comment-stripped first so prose cannot satisfy a row.
#
# Idiom follows tests/scripts/test-registry-d10-workflow-wiring.sh (the nearest neighbour —
# same axis, same file under test): `set -uo pipefail` + `export TMPDIR` + two-space ok/FAIL.
export TMPDIR="${TMPDIR:-/var/tmp}"

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WORKFLOW="${ROOT}/.github/workflows/apply-web-platform-infra.yml"
GATE_LIB="${ROOT}/tests/scripts/lib/vector-redeliver-gate.sh"

passes=0
fails=0
_report() {
  if [[ "$2" == "ok" ]]; then passes=$((passes + 1)); printf '  ok   %s\n' "$1"
  else fails=$((fails + 1)); printf '  FAIL %s%s\n' "$1" "${3:+ — $3}"; fi
}

[[ -f "$WORKFLOW" ]] || { printf 'harness: workflow not found at %s\n' "$WORKFLOW" >&2; exit 2; }

_strip() { grep -vE '^[[:space:]]*#'; }

# The job block: from `^  vector_redeliver:` to the next 2-space job header or top-level key.
_job_body() {
  awk -v want="$1" '
    index($0, "  " want ":") == 1 { inb = 1; print; next }
    inb && /^  [a-zA-Z_][a-zA-Z0-9_-]*:/ { inb = 0 }
    inb && /^[a-zA-Z]/ { inb = 0 }
    inb { print }
  ' "$WORKFLOW" | _strip
}

# A step body WITHIN the already-extracted job body — scoped to the job on purpose. The
# neighbouring suite's extractor scans the whole workflow, which is safe there only because its
# step names happen to be unique across 5500 lines; a name-collision with another arm would
# silently grade the WRONG job's step.
#
# The name match is WHOLE-LINE, not a prefix. Measured: with `index(...) == 1`, renaming the
# step to `CF Tunnel SSH bridge (late)` left every row green — the prefix still matched, so a
# renamed-and-repurposed step could satisfy the ordering rows it was supposed to break.
_step_body() {
  awk -v want="      - name: $1" '
    $0 == want { inb = 1; print; next }
    inb && /^      - name: / { inb = 0 }
    inb && /^  [a-zA-Z_][a-zA-Z0-9_-]*:/ { inb = 0 }
    inb { print }
  ' <<<"$JOB_BODY"
}

# 1-based line index of a step's `- name:` line within the job body. Used for ORDER rows.
# `grep -x` for the same reason as above.
_step_line() {
  grep -n -x -- "      - name: $1" <<<"$JOB_BODY" | head -1 | cut -d: -f1
}

JOB_BODY="$(_job_body 'vector_redeliver')"

PLAN_STEP_NAME='Terraform plan (vector redeliver — one target, one delivery)'
GATE_STEP_NAME='Vector-redeliver plan gate (reads the PLAN, not the flags)'
APPLY_STEP_NAME='Terraform apply (the graded tfplan)'
BRIDGE_STEP_NAME='CF Tunnel SSH bridge'
TEARDOWN_STEP_NAME='Tear down cloudflared SSH bridge'

PLAN_BODY="$(_step_body "$PLAN_STEP_NAME")"
GATE_BODY="$(_step_body "$GATE_STEP_NAME")"
APPLY_BODY="$(_step_body "$APPLY_STEP_NAME")"

# ── W1: HARD vacuity floor ──────────────────────────────────────────────────────────────────
# Every row below reads one of these strings. An extractor that returns empty makes `grep -q`
# fail, which a negative row reads as PASS and a positive row reports as one isolated FAIL
# among many — so the floor exits IMMEDIATELY rather than reporting a mixed verdict over a
# body nobody read. This is the same shape the D10 suite's W1 pins, and the same shape its own
# W8 row shipped with once (an undefined variable made the scan read "" and report ok).
w1_ok=1
_floor() {
  [[ -n "$2" ]] || { _report "W1 ${1} extracts non-empty" fail "extractor returned empty"; w1_ok=0; }
}
_floor "vector_redeliver job body"           "$JOB_BODY"
_floor "the plan step body"                  "$PLAN_BODY"
_floor "the gate step body"                  "$GATE_BODY"
_floor "the apply step body"                 "$APPLY_BODY"
if [[ "$w1_ok" -eq 1 ]]; then
  _report "W1 vacuity floor: job + plan/gate/apply step bodies all extract non-empty" ok
else
  printf '\n=== %d passed, %d failed (vacuity floor failed — no verdict) ===\n' "$passes" "$fails"
  exit 1
fi

# ── V: job-level posture ────────────────────────────────────────────────────────────────────
# The `if:` is pinned WHOLE, not by substring. A widened condition (dropping the event check,
# or matching a prefix) would let this arm run on push — i.e. on every merge, unattended.
if grep -qxE "    if: github\.event_name == 'workflow_dispatch' && inputs\.apply_target == 'vector-redeliver'" <<<"$JOB_BODY"; then
  _report "V1 job if: is exactly the dispatch + apply_target mutual exclusion" ok
else
  _report "V1 job if: is exactly the dispatch + apply_target mutual exclusion" fail "the if: line is absent or has drifted"
fi

# F7: this is a MAIN-BRANCH PIN, not merely a reviewer click. workflow_dispatch runs the
# SELECTED REF's workflow and its scripts; this job sources its gate from ${GITHUB_WORKSPACE}
# and runs root remote-exec on web-1, so without the environment's
# deployment_branch_policy anyone who can dispatch could point it at a branch carrying a
# neutered gate. Deleting this line is a silent, total loss of protection — hence a row.
if grep -qxE '    environment: web-platform-infra-apply' <<<"$JOB_BODY"; then
  _report "V2 job declares environment: web-platform-infra-apply (F7 main-branch pin)" ok
else
  _report "V2 job declares environment: web-platform-infra-apply (F7 main-branch pin)" fail "absent — the ref-pin is gone"
fi

if grep -qxE '      group: web-1-swap' <<<"$JOB_BODY"; then
  _report "V3 job-level concurrency group is web-1-swap (F4)" ok
else
  _report "V3 job-level concurrency group is web-1-swap (F4)" fail "absent"
fi
if grep -qxE '      cancel-in-progress: false' <<<"$JOB_BODY"; then
  _report "V4 cancel-in-progress: false (a cancelled half-apply is the worse split state)" ok
else
  _report "V4 cancel-in-progress: false" fail "absent"
fi
if grep -qxE '    timeout-minutes: 15' <<<"$JOB_BODY"; then
  _report "V5 timeout-minutes: 15 (F15 — omitted, GitHub grants 360 on a job holding two mutexes)" ok
else
  _report "V5 timeout-minutes: 15" fail "absent — the default 360 would hold web-1-swap for six hours"
fi
if grep -qxE '      contents: read' <<<"$JOB_BODY"; then
  _report "V6 job-level permissions: contents: read" ok
else
  _report "V6 job-level permissions: contents: read" fail "absent"
fi

# ── M6a: the gate is actually CALLED, and its verdict is actually BINDING ───────────────────
if grep -qxE '          source "\$\{GITHUB_WORKSPACE\}/tests/scripts/lib/vector-redeliver-gate\.sh"' <<<"$GATE_BODY"; then
  _report "M6a gate step sources the lib via the anchored source line (not a shellcheck directive)" ok
else
  _report "M6a gate step sources the lib via the anchored source line" fail "no '^ *source \"\${GITHUB_WORKSPACE}/tests/scripts/lib/vector-redeliver-gate.sh\"' line survives comment-stripping"
fi

if grep -qxE '          if ! vector_redeliver_gate "\$RUNNER_TEMP/vector-redeliver-plan\.json"; then' <<<"$GATE_BODY"; then
  _report "M6a gate step calls vector_redeliver_gate on the plan JSON via the anchored call form" ok
else
  _report "M6a gate step calls vector_redeliver_gate via the anchored call form" fail "no 'if ! vector_redeliver_gate \"\$RUNNER_TEMP/vector-redeliver-plan.json\"; then' line"
fi

if [[ -f "$GATE_LIB" ]]; then
  _report "M6a the sourced gate lib exists at tests/scripts/lib/vector-redeliver-gate.sh" ok
else
  _report "M6a the sourced gate lib exists" fail "the wired path does not resolve — the source would fail at dispatch time"
fi

# Negative, JOB-SCOPED. `continue-on-error` on the gate step converts every ABORT into a
# green step and lets the apply run on a plan the gate refused. On the apply step it hides a
# failed production apply. Neither is ever wanted here, so the row quantifies over the job.
if grep -qE '^[[:space:]]*continue-on-error:' <<<"$JOB_BODY"; then
  _report "M6a no step in the job is continue-on-error" fail "found a continue-on-error: — a refused plan could still apply"
else
  _report "M6a no step in the job is continue-on-error" ok
fi

if grep -qxE '          set -euo pipefail' <<<"$GATE_BODY"; then
  _report "M6a gate step body opens under set -euo pipefail" ok
else
  _report "M6a gate step body opens under set -euo pipefail" fail "without it a failed 'terraform show -json' leaves a stale/empty document for the gate to grade"
fi

# The no-op branch is a SUCCESS shape (F12), so the apply must be skipped by a positive
# verdict, not by a failure. That needs the outcome on $GITHUB_OUTPUT.
if grep -qE '^[[:space:]]*printf .outcome=%s\\n. "\$VECTOR_REDELIVER_OUTCOME" >> "\$GITHUB_OUTPUT"' <<<"$GATE_BODY"; then
  _report "M6a gate step publishes VECTOR_REDELIVER_OUTCOME to \$GITHUB_OUTPUT" ok
else
  _report "M6a gate step publishes VECTOR_REDELIVER_OUTCOME to \$GITHUB_OUTPUT" fail "the apply cannot be gated on a verdict that is never exported"
fi

if grep -qE 'nothing to redeliver' <<<"$GATE_BODY" && grep -qE 'GITHUB_STEP_SUMMARY' <<<"$GATE_BODY"; then
  _report "M6a the no-op outcome writes 'nothing to redeliver' to \$GITHUB_STEP_SUMMARY (F12)" ok
else
  _report "M6a the no-op outcome writes 'nothing to redeliver' to \$GITHUB_STEP_SUMMARY" fail "a silent green run is indistinguishable from a delivery"
fi

# ── M6c: ONE plan artifact, graded whole, feeding ONE apply ────────────────────────────────
n_plan=$(grep -cE '(^|[[:space:]])terraform plan([[:space:]]|$)' <<<"$JOB_BODY")
if [[ "$n_plan" -eq 1 ]]; then
  _report "M6c the job runs 'terraform plan' exactly once" ok
else
  _report "M6c the job runs 'terraform plan' exactly once" fail "found ${n_plan} — a second plan breaks the single-artifact chokepoint the Guard Contract rests on"
fi

if grep -qxE '            terraform plan -no-color -input=false -out=tfplan \\' <<<"$PLAN_BODY"; then
  _report "M6c the plan is SAVED to -out=tfplan (anchored)" ok
else
  _report "M6c the plan is SAVED to -out=tfplan (anchored)" fail "no anchored 'terraform plan -no-color -input=false -out=tfplan \\' line"
fi

n_target=$(grep -cE '^[[:space:]]*-target=' <<<"$PLAN_BODY")
if [[ "$n_target" -eq 1 ]] && grep -qxE '              -target=terraform_data\.journald_persistent( \\)?' <<<"$PLAN_BODY"; then
  _report "M6c the plan carries exactly one -target=, and it is terraform_data.journald_persistent" ok
else
  _report "M6c the plan carries exactly one -target=terraform_data.journald_persistent" fail "found ${n_target} -target= flag(s); a widened request enlarges the closure the gate must then refuse"
fi

n_apply=$(grep -cE '(^|[[:space:]])terraform apply([[:space:]]|$)' <<<"$JOB_BODY")
if [[ "$n_apply" -eq 1 ]]; then
  _report "M6c the job runs 'terraform apply' exactly once" ok
else
  _report "M6c the job runs 'terraform apply' exactly once" fail "found ${n_apply}"
fi

# THE row F10/AC13 turn on: the apply must consume the SAVED plan positionally. An
# `apply -target=…` here would re-plan — the gate would have graded a document the apply
# never reads, and the ci_ssh_private_key baked at plan time would be discarded.
if grep -qxE '            terraform apply -no-color -input=false -auto-approve tfplan' <<<"$APPLY_BODY"; then
  _report "M6c the apply consumes the SAVED tfplan positionally (AC13)" ok
else
  _report "M6c the apply consumes the SAVED tfplan positionally (AC13)" fail "no anchored 'terraform apply -no-color -input=false -auto-approve tfplan' line — a re-plan dissolves the chokepoint"
fi

# NOT line-anchored: measured, `apply -no-color -input=false -auto-approve -target=…` puts the
# flag mid-line, where a `^\s*-target=` row never sees it.
if grep -qE '(^|[[:space:]])-target=' <<<"$APPLY_BODY"; then
  _report "M6c the apply passes no -target= (a saved plan takes none)" fail "found a -target= on the apply step — it is re-planning"
else
  _report "M6c the apply passes no -target= (a saved plan takes none)" ok
fi

if grep -qxE "        if: steps\.vector_gate\.outputs\.outcome == 'pass'" <<<"$JOB_BODY"; then
  _report "M6c the apply step runs ONLY on the gate's 'pass' outcome" ok
else
  _report "M6c the apply step runs ONLY on the gate's 'pass' outcome" fail "the apply is not gated on steps.vector_gate.outputs.outcome"
fi

# ── M6d: step ORDER, which no unit test can see ────────────────────────────────────────────
ln_bridge=$(_step_line "$BRIDGE_STEP_NAME")
ln_plan=$(_step_line "$PLAN_STEP_NAME")
ln_gate=$(_step_line "$GATE_STEP_NAME")
ln_apply=$(_step_line "$APPLY_STEP_NAME")
ln_teardown=$(_step_line "$TEARDOWN_STEP_NAME")

_order() {
  local label="$1" a="$2" b="$3"
  if [[ -n "$a" && -n "$b" && "$a" -lt "$b" ]]; then _report "$label" ok
  else _report "$label" fail "line indices a=${a:-<missing>} b=${b:-<missing>}"; fi
}
# F10, and the single highest-consequence ordering in the job: the bridge writes
# TF_VAR_ci_ssh_private_key into $GITHUB_ENV, so a plan built BEFORE it bakes null →
# agent = true on an agent-less runner, and `apply <savedplan>` accepts no variable input.
_order "M6d the CF Tunnel SSH bridge precedes the plan (F10 — the plan bakes the SSH credential)" "$ln_bridge" "$ln_plan"

# The ordering rows above are satisfied by ANY step carrying that name. This row makes the
# named step actually be the bridge — otherwise a placeholder in the right position would
# leave TF_VAR_ci_ssh_private_key unset and the rows green.
bridge_body="$(_step_body "$BRIDGE_STEP_NAME")"
if grep -qxE '        uses: \./\.github/actions/cf-tunnel-ssh-bridge' <<<"$bridge_body"; then
  _report "M6d the bridge step invokes the cf-tunnel-ssh-bridge composite action" ok
else
  _report "M6d the bridge step invokes the cf-tunnel-ssh-bridge composite action" fail "the step is named for the bridge but does not use it"
fi
_order "M6d the plan precedes the gate (the gate grades a document that exists)" "$ln_plan" "$ln_gate"
_order "M6d the gate precedes the apply (AC12 as rewritten by F10)" "$ln_gate" "$ln_apply"
_order "M6d the teardown follows the apply" "$ln_apply" "$ln_teardown"

# The composite action declares this MANDATORY (action.yml:33-58) — it cannot register a
# post-job hook. It is also where /tmp/cloudflared.log surfaces, which is the evidence the
# runbook's L3 "tunnel unhealthy" hypothesis runs on.
teardown_body="$(_step_body "$TEARDOWN_STEP_NAME")"
if [[ -n "$teardown_body" ]] && grep -qxE '        if: always\(\)' <<<"$teardown_body"; then
  _report "M6d the bridge teardown is if: always() (caller obligation, action.yml:33-58)" ok
else
  _report "M6d the bridge teardown is if: always()" fail "absent or not always() — a failed apply would leak the NAT rule and lose the cloudflared log"
fi

# ── M6e: the dispatch surface ──────────────────────────────────────────────────────────────
if grep -qxE '          - vector-redeliver' < <(_strip < "$WORKFLOW"); then
  _report "M6e vector-redeliver is present in the apply_target options list" ok
else
  _report "M6e vector-redeliver is present in the apply_target options list" fail "the target cannot be selected"
fi

# AC9, read STRUCTURALLY. A grep over the file would hit the job header, the comparison, the
# error string and this suite's own name for it — F15 records that the row is not grep-able as
# written, so it is a parsed read of exactly one YAML scalar.
_desc_out=$(python3 - "$WORKFLOW" <<'PYX'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
# `on:` parses to the boolean True in YAML 1.1 — read both spellings rather than assume.
on = d.get("on", d.get(True)) or {}
inputs = ((on.get("workflow_dispatch") or {}).get("inputs") or {})
desc = (inputs.get("confirm") or {}).get("description")
if desc is None:
    print("MISSING")
else:
    print("HIT" if "REDELIVER-VECTOR" in desc else "CLEAN")
PYX
) || _desc_out="RC_FAIL"
case "$_desc_out" in
  CLEAN)   _report "M6e REDELIVER-VECTOR is absent from the confirm input's description (F5/AC9)" ok ;;
  HIT)     _report "M6e REDELIVER-VECTOR is absent from the confirm input's description" fail "the token leaked into the field label the operator reads" ;;
  *)       _report "M6e REDELIVER-VECTOR is absent from the confirm input's description" fail "could not read the description (${_desc_out}) — no verdict" ;;
esac

if grep -qE 'REDELIVER-VECTOR' <<<"$JOB_BODY"; then
  _report "M6e the job itself pins the confirm token REDELIVER-VECTOR" ok
else
  _report "M6e the job itself pins the confirm token REDELIVER-VECTOR" fail "the typo-guard compares against something else"
fi

# Operator-supplied strings must be routed through env: and compared as DATA — never
# interpolated into a shell body, per this workflow's own header. Rather than try to decide
# which lines are inside a `run:` block, this inverts the test: EVERY `${{ inputs.* }}` in the
# job must be an `env:` mapping line (`          NAME_RAW: ${{ inputs.x }}`). Anything else —
# a bare interpolation in a shell body, a `-var=` argument — is a violation by construction.
bad_interp="$(grep -nE '\$\{\{[[:space:]]*inputs\.' <<<"$JOB_BODY" \
  | grep -vE '^[0-9]+:[[:space:]]+[A-Z_]+:[[:space:]]*\$\{\{[[:space:]]*inputs\.[a-z_]+[[:space:]]*\}\}$' || true)"
if [[ -n "$bad_interp" ]]; then
  _report "M6e every \${{ inputs.* }} in the job is an env: mapping, never a shell body" fail "$bad_interp"
else
  _report "M6e every \${{ inputs.* }} in the job is an env: mapping, never a shell body" ok
fi

# No [ack-destroy] bypass on this path (hr-menu-option-ack-not-prod-write-auth). It is
# structurally unavailable on dispatch anyway — the push guard reads
# github.event.head_commit.message, empty on workflow_dispatch — so a reference here would be
# a misunderstanding at best and a real bypass at worst.
if grep -qE 'ack-destroy' <<<"$JOB_BODY"; then
  _report "M6e the job carries no [ack-destroy] bypass" fail "found an ack-destroy reference in the job body"
else
  _report "M6e the job carries no [ack-destroy] bypass" ok
fi

# ── Anti-vacuity assertion floor ────────────────────────────────────────────────────────────
# Pinned EXACTLY, per the neighbouring suite's measurement: neutering `_report` to `return 0`
# reports "0 passed, 0 failed" and exits 0, because `fails` is a single unguarded integer. A
# `>=` re-opens that hole the next time a row is added.
EXPECTED_ASSERTIONS=32
if [[ "$fails" -eq 0 && "$passes" -ne "$EXPECTED_ASSERTIONS" ]]; then
  printf '  FAIL anti-vacuity: %d assertions passed, expected exactly %d — rows were added, removed, or silenced\n' \
    "$passes" "$EXPECTED_ASSERTIONS"
  fails=$((fails + 1))
fi

printf '\n=== %d passed, %d failed ===\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]] || exit 1
