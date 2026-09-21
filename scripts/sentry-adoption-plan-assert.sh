#!/usr/bin/env bash
# AC2 / AC10 — assert an adoption plan is EXACTLY an adoption: N forgets, N
# matching imports, every adopted row inert, and no delete or replace anywhere
# (#7650 Phase 2; scoped to the adopted rows in #8451 — see section 3).
#
# Usage: sentry-adoption-plan-assert.sh <plan.json> [expected-pairs] [capture.json]
#   expected-pairs  REQUIRED — the landed scope, passed explicitly by the caller
#   capture.json    optional; when given, every import id's numeric part must be
#                   a workflow id present in the committed live capture, and the
#                   imported object's name must be that capture entry's name
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
# ── WHY IT IS CONDITIONAL, AND WHY IT IS SCOPED ─────────────────────────────
# (#8451) An adoption that lands on a WEDGED root carries the unapplied backlog:
# #8451's adoption could only plan once it existed, so every create/update that
# merged while plans failed rides in the same plan. Global inertness therefore
# cannot hold, and section 3 asserts it at the adopted rows (plus no delete or
# replace anywhere), delegating backlog rows to the create gate, the reference
# gate and the tripwire. The paragraph below is the Phase 2 reasoning, kept.
#
# "Every managed row is a no-op or a forget" is true of THIS apply and of no
# other. A later PR that adds a cron monitor legitimately plans a create, and a
# permanent version of this assertion would red it. So the discriminator is the
# presence of adoption rows: a plan with zero forgets and zero imports is not an
# adoption and this exits 0 with an explicit message. #7826 removed the Phase 2
# import{}/removed{} blocks on 2026-09-06; #8451 re-added two pairs, so this
# assertion is live on the plans that carry them and SKIPs on every plan after
# they apply. The blocks themselves leave with #7985's conversion.
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
# REQUIRED, not defaulted. The header six lines up says the literal is "passed
# explicitly by the caller" so a future adoption of a different size has to change
# the call deliberately — and a `${2:-27}` default contradicted exactly that by
# silently re-arming the assertion at 27 for a caller that forgot.
EXPECTED="${2:?usage: sentry-adoption-plan-assert.sh <plan.json> <expected-pairs> [capture.json]}"
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

# ROW-COUNT FLOOR before the skip branch. "Zero forgets and zero imports" is the
# legitimate post-adoption state AND what a truncated or unwritten plan document
# looks like, and the skip branch cannot tell them apart. Without this, the
# AC2/AC10 assertion that gates the run which mutates prod relied on the create
# tripwire happening to run first at both call sites.
rows=$(jq -r '(.resource_changes // []) | length' "$PLAN" 2>/dev/null) || rows=""
if [[ ! "$rows" =~ ^[0-9]+$ ]] || [[ "$rows" -eq 0 ]]; then
  echo "::error::adoption plan assert: '$PLAN' has ZERO resource_changes rows. A full-root Sentry plan always carries one row per managed resource, no-ops included — zero means the document is truncated, targeted, or was never written, not that there is nothing to assert." >&2
  exit 1
fi

if [[ "$n_forget" -eq 0 && "$n_import" -eq 0 ]]; then
  echo "adoption plan assert: SKIP — this plan carries no forget and no import rows, so it is not an adoption plan. (Expected on every run after an adoption has applied.)"
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
  # TWO DIFFERENT SITUATIONS, and conflating them made the PR's own documented
  # recovery unusable. A RESUMED PARTIAL APPLY looks like `k == k < EXPECTED`:
  # the pairs that already committed leave no rows behind (a removed{} naming an
  # address no longer in state produces no forget; an import{} naming an address
  # already in state is a measured silent no-op), so a run that got 15 of 27
  # through re-plans as exactly 12 + 12. A DROPPED PAIR looks the same
  # arithmetically but means something else entirely.
  #
  # Both must still refuse to apply — the caller declared a scope and this is not
  # it — but they need different sentences, because the operator's next action
  # differs and the apply-failure issue tells them to "re-run the failed job,
  # it is the only gesture that works". Under a partial apply the re-run reds
  # HERE, and the previous wording sent them hunting for a dropped block.
  if [[ "$n_forget" -eq "$n_import" && "$n_forget" -lt "$EXPECTED" ]]; then
    echo "::error::adoption plan assert: ${n_forget} matched pair(s), expected ${EXPECTED} — this is the shape of a RESUMED PARTIAL APPLY, not a dropped block." >&2
    echo "::error::A pair that already applied leaves NO rows in a re-plan: its removed{} names an address no longer in state, and its import{} names an address already in state. So $(( EXPECTED - n_forget )) of the ${EXPECTED} pairs appear to have committed and ${n_forget} remain." >&2
    echo "::error::VERIFY THAT before acting, because a dropped removed{}+import{} pair is arithmetically identical here. Run AC17 ('terraform state list' for this root) and check each adopted LABEL: an applied pair shows sentry_alert.<label> present and sentry_issue_alert.<label> absent; ${n_forget} label(s) should still show sentry_issue_alert.<label>. If it does, the adoption is genuinely mid-flight and the remaining ${n_forget} are what is left to apply — resuming needs the expected count at the call site lowered to ${n_forget} in a reviewed commit, NOT an edit made under time pressure. If state does not agree, a pair really was dropped: restore the block." >&2
  else
    echo "::error::adoption plan assert: expected ${EXPECTED} forget(s) and ${EXPECTED} import(s), got ${n_forget} and ${n_import}." >&2
    echo "::error::The two counts differ. Two shapes produce that: a pair whose FORGET committed while its IMPORT did not (state shows neither sentry_issue_alert.<label> nor sentry_alert.<label>; recovery is a reviewed PR deleting that label's removed{} block and setting the expected count to the remaining pairs), or a removed{}/import{} block dropped from config. Check AC17's 'terraform state list' per adopted label before choosing. If the scope genuinely changed, update the expected count at the call site." >&2
  fi
  rc=1
fi

# ── 3. Inertness AT THE ADOPTED ROWS, plus no delete/replace anywhere ──────
#       (#8451 CTO ruling). Per ROW, never from the summary line; data-source
#       reads are excluded (`.mode == "managed"`). Four predicates:
#   3a  every IMPORT row is `["no-op"]` — an update at an imported address is
#       drift between the authored block and live config;
#   3b  every FORGET moves `sentry_issue_alert` — the only legacy type;
#   3c  no managed row anywhere carries `delete` (delete or either replace
#       order) — overlaps the destroy gate, but `[ack-destroy]` greens that
#       gate and does not reach this one;
#   3d  every OTHER create/update is BACKLOG: allowed, and printed as a notice.
# Why 3d exists: an adoption landing on a wedged root carries every change that
# merged while no plan could complete. What covers those rows, precisely:
# CREATES are diff-matched by the create gate (window: the last applied commit,
# both jobs); any write to a legacy-trigger sentry_alert is refused by the
# tripwire (both jobs); sentry_alert CONTENT is held to alert-reference.json by
# the reference gate (plan_pr only) and to live by the post-apply fidelity
# probe. Everything else (cron/uptime monitor updates) is covered by the
# review of the PR that merged it — the same coverage every ordinary apply has.
# 3a cannot see content drift on a frozen (ignore_changes = all) import: it
# always plans no-op. Section 4's name check and the op-contract test pin which
# object each import adopts; the live-fidelity frozen pin checks its content.
violations=$(jq -r '
  [ .resource_changes[]?
    | select((.mode // "managed") == "managed")
    | (.change.actions // []) as $a
    | if (.change.importing.id != null) and ($a != ["no-op"]) then
        "\(.address) actions=\($a | join(",")) (3a: an imported address must plan no-op)"
      elif ($a == ["forget"]) and (.type != "sentry_issue_alert") then
        "\(.address) actions=forget (3b: only sentry_issue_alert may be forgotten)"
      elif ($a | index("delete")) != null then
        "\(.address) actions=\($a | join(",")) (3c: no delete or replace in an adoption plan)"
      else empty end ]
  | .[]
' "$PLAN") || violations="JQFAIL"
backlog=$(jq -r '
  [ .resource_changes[]?
    | select((.mode // "managed") == "managed")
    | select(.change.importing.id == null)
    | (.change.actions // []) as $a
    | select($a != ["no-op"] and $a != ["forget"] and ($a | index("delete")) == null)
    | "\(.address) actions=\($a | join(","))" ]
  | .[]
' "$PLAN") || backlog="JQFAIL"

# A jq failure must not read as the SUCCESS signal: an empty `$violations` is
# the strongest claim this section makes.
if [[ "$violations" == "JQFAIL" || "$backlog" == "JQFAIL" ]]; then
  echo "::error::adoption plan assert: could not scan managed rows in '$PLAN'; refusing to report the adopted-rows-inert assertion as passed." >&2
  rc=1
  violations=""; backlog=""
fi

if [[ -n "$violations" ]]; then
  count=$(grep -c '' <<<"$violations")
  echo "::error::adoption plan assert: ${count} managed row(s) break the adoption's inertness:" >&2
  while IFS= read -r line; do echo "::error::  $line" >&2; done <<<"$violations"
  echo "::error::An adoption must move addresses in state and change nothing at the adopted rules. A non-no-op import row is drift between the authored block and live config; a forget of anything but sentry_issue_alert drops a live resource from management; a delete or replace is a live object about to disappear, and no acknowledgement reaches this check." >&2
  rc=1
fi

n_backlog=0
if [[ -n "$backlog" ]]; then
  n_backlog=$(grep -c '' <<<"$backlog")
  echo "::notice::adoption plan assert: ${n_backlog} non-adoption backlog row(s), not asserted inert here (creates: create gate; legacy-trigger writes: tripwire; sentry_alert content: reference gate + post-apply probe; the rest: the reviewed PR that merged it):"
  while IFS= read -r line; do echo "::notice::  $line"; done <<<"$backlog"
fi

# ── 3e. Import ids are UNIQUE. ──────────────────────────────────────────────
# The membership check below only catches ids that were NEVER live. The capture
# holds every live workflow at capture time, so an id copy-pasted from ANOTHER —
# the realistic generator or hand-edit error — passes it. Two addresses importing
# the same workflow id means one live rule adopted twice and one adopted by
# nobody.
dup_ids=$(jq -r '
  [ .resource_changes[]? | select(.change.importing.id != null) | .change.importing.id ]
  | group_by(.) | map(select(length > 1) | .[0]) | .[]
' "$PLAN" 2>/dev/null) || dup_ids="JQFAIL"
if [[ "$dup_ids" == "JQFAIL" ]]; then
  echo "::error::adoption plan assert: could not check import ids for duplicates." >&2
  rc=1
elif [[ -n "$dup_ids" ]]; then
  echo "::error::adoption plan assert: the same workflow id is imported at more than one address:" >&2
  sed 's/^/::error::  /' <<<"$dup_ids" >&2
  echo "::error::One live Sentry rule would be adopted twice and another adopted by nobody. This is what a copy-pasted id looks like, and the capture-membership check below cannot see it — every duplicated id IS live." >&2
  rc=1
fi

# ── 4. Every import id resolves to a workflow that was live at capture time,
#       and the object imported under it carries THAT workflow's name (#8451
#       review: under ignore_changes = all an import always plans no-op, so a
#       swapped pair of ids passes 3a, uniqueness and membership alike). ─────
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
    bad_names=$(jq -r --slurpfile cap "$CAPTURE" '
      ($cap[0] | map({key: (.id | tostring), value: .name}) | from_entries) as $name_of
      | [ .resource_changes[]?
          | select(.change.importing.id != null)
          | (.change.importing.id | tostring | split("/") | last) as $wid
          | select($name_of[$wid] != null)
          | ((.change.after // {}).name) as $got
          | select($got != $name_of[$wid])
          | "\(.address) id=\($wid) imported name=\($got // "<absent>") capture name=\($name_of[$wid])" ]
      | .[]
    ' "$PLAN") || bad_names="JQFAIL"
    if [[ "$bad_names" == "JQFAIL" ]]; then
      echo "::error::adoption plan assert: could not cross-check imported names against '$CAPTURE'." >&2
      rc=1
    elif [[ -n "$bad_names" ]]; then
      echo "::error::adoption plan assert: import row(s) whose imported object is not the captured workflow of that id:" >&2
      while IFS= read -r line; do echo "::error::  $line" >&2; done <<<"$bad_names"
      echo "::error::The id in import{} adopts whatever object Sentry holds under it; the name read back from that object does not match the committed capture. Swapped or stale ids adopt a different live rule at this address. Re-derive the id from the capture." >&2
      rc=1
    fi
  fi
fi

if [[ "$rc" -eq 0 ]]; then
  echo "adoption plan assert: PASS (${n_forget} forget(s), ${n_import} import(s); adopted rows no-op, 0 deletes/replaces, ${n_backlog} backlog row(s) delegated)"
fi
exit "$rc"
