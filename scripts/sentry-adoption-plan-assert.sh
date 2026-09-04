#!/usr/bin/env bash
# AC2 / AC10 — assert an adoption plan is EXACTLY an adoption: N forgets, N
# matching imports, and every other managed row a no-op (#7650 Phase 2).
#
# Usage: sentry-adoption-plan-assert.sh <plan.json> [expected-pairs] [capture.json]
#   expected-pairs  default 27 — the landed scope
#   capture.json    optional; when given, every import id's numeric part must be
#                   a workflow id present in the committed live capture
# Exit 0 = not an adoption plan, or a well-formed one.
# Exit 1 = an adoption plan that is not exactly an adoption.
#
# ── WHY THE APPLY JOB NEEDS THIS AND NOT JUST THE DESTROY GATE ─────────────
# The `apply` job RE-PLANS. Whatever `plan_pr` saw on the PR is not what gets
# applied; the apply's own plan is, and its ONLY gate is `destroy_count` — which
# the merge's `[ack-destroy]` greens by design, because this adoption legitimately
# reports 27 forgets and 142 nested shrinks. So on the one run that actually
# mutates prod, a blanket ack currently waves through anything that is not a
# delete: a create, an update, a rebind. That is the largest hole the review round
# found, and this assertion is the plug. It runs BEFORE `terraform apply` and is
# NOT reachable from the ack.
#
# ── WHY IT IS CONDITIONAL ──────────────────────────────────────────────────
# "Every managed row is a no-op or a forget" is true of THIS apply and of no
# other. A later PR that adds a cron monitor legitimately plans a create, and a
# permanent version of this assertion would red it. So the discriminator is the
# presence of adoption rows: a plan with zero forgets and zero imports is not an
# adoption and this exits 0 with an explicit message. Once #7826 removes the
# import{}/removed{} blocks, every plan takes that branch and the assertion is
# inert by construction rather than by being deleted.
#
# ── WHY `expected` IS A NUMBER AND NOT DERIVED FROM CONFIG ─────────────────
# It cannot be derived from the plan: post-adoption the config still declares 27
# `import{}` blocks while the plan carries zero import rows (an import block on an
# already-managed address is a measured silent no-op). Deriving it from the .tf
# would therefore assert 27 forever, against plans that correctly have none. A
# literal, defaulted and passed explicitly by the caller, means a future adoption
# of a different size has to change this call deliberately.
#
# Behaviour is unit-tested by tests/scripts/test-sentry-alert-adoption-guards.sh.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAN="${1:?usage: sentry-adoption-plan-assert.sh <plan.json> [expected-pairs] [capture.json]}"
EXPECTED="${2:-27}"
CAPTURE="${3:-}"

if [[ ! -r "$PLAN" ]]; then
  echo "::error::adoption plan assert: plan JSON not readable at '$PLAN'." >&2
  exit 1
fi

# Parenthesised on purpose: `|` binds looser than `,`, so
# `[ A | length, B | length ]` parses as `[ A | (length, B) | length ]` and
# yields nonsense rather than a two-element array.
read -r n_forget n_import < <(jq -r '
  [ ([ .resource_changes[]? | select((.change.actions // []) == ["forget"]) ] | length),
    ([ .resource_changes[]? | select(.change.importing.id != null)          ] | length) ]
  | @tsv' "$PLAN" 2>/dev/null | tr '\t' ' ') || true

if [[ ! "${n_forget:-}" =~ ^[0-9]+$ || ! "${n_import:-}" =~ ^[0-9]+$ ]]; then
  echo "::error::adoption plan assert: could not read forget/import row counts from '$PLAN'." >&2
  exit 1
fi

if [[ "$n_forget" -eq 0 && "$n_import" -eq 0 ]]; then
  echo "adoption plan assert: SKIP — this plan carries no forget and no import rows, so it is not an adoption plan. (Expected on every run after the adoption has applied, and permanently after #7826 removes the blocks.)"
  exit 0
fi

rc=0

# ── 1. The bijection. Delegated, not re-derived: one implementation of "these
#       two sets pair up", exercised by its own matrix. ─────────────────────
if ! bash "$HERE/sentry-forget-import-bijection.sh" "$PLAN"; then
  rc=1
fi

# ── 2. Cardinality against the landed scope. The bijection holds for 26 pairs
#       too; this is what notices that a pair went missing from BOTH sides. ──
if [[ "$n_forget" -ne "$EXPECTED" || "$n_import" -ne "$EXPECTED" ]]; then
  echo "::error::adoption plan assert: expected ${EXPECTED} forget(s) and ${EXPECTED} import(s), got ${n_forget} and ${n_import}." >&2
  echo "::error::A removed{}+import{} pair dropped together keeps the bijection intact while a live paging rule is silently left on the old address. If the scope genuinely changed, update the expected count at the call site." >&2
  rc=1
fi

# ── 3. `0 to add, 0 to change, 0 to destroy` — asserted per ROW, not from the
#       summary line. Data-source reads are excluded: `.mode == "managed"`. ──
others=$(jq -r '
  [ .resource_changes[]?
    | select((.mode // "managed") == "managed")
    | select((.change.actions // []) != ["no-op"])
    | select((.change.actions // []) != ["forget"])
    | "\(.address) actions=\((.change.actions // []) | join(","))" ]
  | .[]
' "$PLAN") || others=""

if [[ -n "$others" ]]; then
  count=$(grep -c '' <<<"$others")
  echo "::error::adoption plan assert: ${count} managed row(s) are neither no-op nor forget — this plan does more than adopt:" >&2
  sed 's/^/::error::  /' <<<"$others" >&2
  echo "::error::An adoption must be inert on live Sentry: it moves addresses in state and changes nothing in the product. A create here is a dropped import{} colliding with the live rule it should have adopted; an update is drift between the authored block and live config; a delete is a paging rule about to disappear." >&2
  rc=1
fi

# ── 4. Every import id resolves to a workflow that was live at capture time. ─
if [[ -n "$CAPTURE" ]]; then
  if [[ ! -r "$CAPTURE" ]]; then
    echo "::error::adoption plan assert: capture JSON not readable at '$CAPTURE'." >&2
    rc=1
  else
    bad_ids=$(jq -r --slurpfile cap "$CAPTURE" '
      ($cap[0] | map(.id | tostring)) as $live
      | [ .resource_changes[]?
          | select(.change.importing.id != null)
          | { addr: .address, id: (.change.importing.id | tostring) }
          | select((.id | split("/") | last) as $wid | ($live | index($wid)) == null)
          | "\(.addr) id=\(.id)" ]
      | .[]
    ' "$PLAN") || bad_ids="JQFAIL"
    if [[ "$bad_ids" == "JQFAIL" ]]; then
      echo "::error::adoption plan assert: could not cross-check import ids against '$CAPTURE'." >&2
      rc=1
    elif [[ -n "$bad_ids" ]]; then
      echo "::error::adoption plan assert: import id(s) not present in the committed live capture:" >&2
      sed 's/^/::error::  /' <<<"$bad_ids" >&2
      echo "::error::Terraform would adopt a workflow id that did not exist when the capture was taken. Either the id is wrong (a typo adopts SOMEONE ELSE'S rule under this name) or the rule was created outside Terraform after the capture. Re-derive from the capture; do not hand-edit an id." >&2
      rc=1
    fi
  fi
fi

if [[ "$rc" -eq 0 ]]; then
  echo "adoption plan assert: PASS (${n_forget} forget(s), ${n_import} import(s), 0 add / 0 change / 0 destroy across every managed row)"
fi
exit "$rc"
