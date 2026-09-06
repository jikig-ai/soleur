#!/usr/bin/env bash
# Guard B — every address leaving Terraform's management is re-adopted by
# exactly one import, and every import corresponds to exactly one forget
# (#7650 Phase 2). AC3.
#
# Usage: sentry-forget-import-bijection.sh <plan.json>
# Exit 0 = the two sets pair up, one-to-one, by resource name.
# Exit 1 = an unpaired member on either side, or nothing to pair at all.
#
# ── THE FAILURE THIS EXISTS FOR ────────────────────────────────────────────
# The adoption is 27 `removed { from = sentry_issue_alert.<n>  lifecycle
# { destroy = false } }` blocks paired with 27 `import { to = sentry_alert.<n> }`
# blocks. Delete ONE `import{}` and every per-address check still passes: the
# remaining 26 pairs are individually well-formed, the 27th `removed{}` is
# well-formed, and the orphaned `sentry_alert` block is well-formed. Nothing is
# malformed. What is violated is the PAIRING — and a live paging rule ends up
# managed by nobody, or planned as a create that collides with the live rule it
# was supposed to adopt.
#
# ── MEMBERSHIP, NOT CARDINALITY ────────────────────────────────────────────
# `27 == 27` is satisfied by forgetting X and importing Y. The assertion is set
# equality over the resource NAME (the part after the first `.`), which is what
# the `sentry_issue_alert.<n>` -> `sentry_alert.<n>` migration preserves. Both
# directions are reported, and reporting does not stop at the first unpaired
# member: stopping early is itself the failure class, because the second broken
# pair in a file of 27 near-identical blocks is exactly the one a scoped edit
# creates.
#
# ── THE VACUITY FLOOR ──────────────────────────────────────────────────────
# Zero forgets and zero imports satisfies set equality trivially. A guard that
# reports PASS over an empty plan is worse than no guard, so this exits 1. The
# CALLER is responsible for only invoking it on a plan where an adoption is
# expected — the workflow tests `forget_rows + import_rows > 0` first, so a
# post-adoption plan (all no-op, nothing to pair) is skipped explicitly rather
# than silently passing. Do not "fix" that skip by weakening this floor.
#
# Behaviour is unit-tested by tests/scripts/test-sentry-alert-adoption-guards.sh.
set -uo pipefail

PLAN="${1:?usage: sentry-forget-import-bijection.sh <plan.json>}"

if [[ ! -r "$PLAN" ]]; then
  echo "::error::forget/import bijection: plan JSON not readable at '$PLAN'." >&2
  exit 1
fi

# ONE chokepoint, one document. Both sets are derived from the same
# `terraform show -json` output in the same invocation, so neither can be
# assembled from a stale list or a different plan than the one being gated.
sets=$(jq -r '
  def rname: (. | sub("^[^.]*\\."; ""));
  {
    forgets: [ .resource_changes[]? | select((.change.actions // []) == ["forget"]) | .address ],
    imports: [ .resource_changes[]? | select(.change.importing.id != null)         | .address ]
  }
  | "FORGET_ADDRS\t\(.forgets | join(" "))",
    "IMPORT_ADDRS\t\(.imports | join(" "))",
    "FORGET_NAMES\t\(.forgets | map(rname) | sort | join(" "))",
    "IMPORT_NAMES\t\(.imports | map(rname) | sort | join(" "))"
' "$PLAN") || {
  echo "::error::forget/import bijection: could not parse '$PLAN'." >&2
  exit 1
}

# TYPE TRANSITION, asserted before the names are compared. The relation this
# guard exists for is `sentry_issue_alert.<n>` -> `sentry_alert.<n>`; pairing on
# the suffix after the first dot alone does not say that. A `removed{}` block
# naming the WRONG TYPE — the easy copy-paste error in a file of 27
# near-identical blocks — would then pair cleanly: a live `sentry_cron_monitor`
# leaves Terraform's management, this prints PASS, the cardinality check still
# sees 27/27, and `[ack-destroy]` greens the destroy gate over it.
_type_violations() {
  jq -r '
    [ (.resource_changes[]? | select((.change.actions // []) == ["forget"])
        | select((.address | startswith("sentry_issue_alert.")) | not)
        | "forget of a non-sentry_issue_alert address: \(.address)"),
      (.resource_changes[]? | select(.change.importing.id != null)
        | select((.address | startswith("sentry_alert.")) | not)
        | "import into a non-sentry_alert address: \(.address)") ]
    | .[]
  ' "$PLAN" 2>/dev/null
}
bad_types=$(_type_violations)
if [[ -n "$bad_types" ]]; then
  echo "::error::forget/import bijection: the plan forgets or imports the WRONG RESOURCE TYPE." >&2
  sed 's/^/::error::  /' <<<"$bad_types" >&2
  echo "::error::This adoption moves sentry_issue_alert.<n> -> sentry_alert.<n> and nothing else. A removed{} naming another type drops a live resource out of management while the name-pairing below still reports a clean bijection." >&2
  exit 1
fi

_field() { sed -n "s/^$1\t//p" <<<"$sets"; }
forget_addrs=$(_field FORGET_ADDRS)
import_addrs=$(_field IMPORT_ADDRS)
forget_names=$(_field FORGET_NAMES)
import_names=$(_field IMPORT_NAMES)

_count() { local s="$1"; [[ -z "$s" ]] && { echo 0; return; }; wc -w <<<"$s"; }
n_forget=$(_count "$forget_addrs")
n_import=$(_count "$import_addrs")

if [[ "$n_forget" -eq 0 && "$n_import" -eq 0 ]]; then
  echo "::error::forget/import bijection: the plan contains ZERO forgets and ZERO imports." >&2
  echo "::error::Set equality is trivially satisfied by two empty sets, so this is not a pass — it means the adoption blocks produced no plan rows at all (a dropped removed{}+import{} pair, a targeted plan, or a plan document that was never written). Refusing to report PASS." >&2
  exit 1
fi

# LC_ALL=C on EVERY sort that feeds `comm`, and on the uniq pipeline beside it.
# `sort` under a UTF-8 locale uses collation rules that ignore punctuation, while
# `comm` compares byte-wise — so on names carrying `_` (which is all 27 of the
# real ones) the two disagree, `comm` prints "file 1 is not in sorted order", and
# its output is undefined: it can report differences that do not exist or, worse,
# MISS real ones. Measured against the live 27-rule plan on 2026-09-04: the
# warning fired on every invocation and the verdict happened to be right anyway.
# A guard that is correct by luck on the one input that matters is the failure
# this whole file exists to prevent. The 3-name fixtures could never have caught
# it — `p1`/`p2`/`p3` collate identically under both rules.
_dupes() { tr ' ' '\n' <<<"$1" | sed '/^$/d' | LC_ALL=C sort | uniq -d | tr '\n' ' '; }
dup_f=$(_dupes "$forget_names"); dup_i=$(_dupes "$import_names")
if [[ -n "${dup_f// /}" || -n "${dup_i// /}" ]]; then
  echo "::error::forget/import bijection: duplicate resource name(s) — forgets: '${dup_f:-none}' imports: '${dup_i:-none}'." >&2
  echo "::error::A one-to-one relation cannot have a repeated member on either side; sorted-list equality would hide this." >&2
  exit 1
fi

# Report BOTH directions, in full. Not "the first mismatch".
_sorted() { tr ' ' '\n' <<<"$1" | sed '/^$/d' | LC_ALL=C sort; }
only_forget=$(LC_ALL=C comm -23 <(_sorted "$forget_names") <(_sorted "$import_names"))
only_import=$(LC_ALL=C comm -13 <(_sorted "$forget_names") <(_sorted "$import_names"))

if [[ -z "$only_forget" && -z "$only_import" ]]; then
  echo "forget/import bijection: PASS ($n_forget forget(s) paired one-to-one with $n_import import(s))"
  exit 0
fi

echo "::error::forget/import bijection BROKEN: $n_forget forget(s) vs $n_import import(s)." >&2
if [[ -n "$only_forget" ]]; then
  echo "::error::FORGOTTEN BUT NOT IMPORTED — these live Sentry rules would be left managed by nobody:" >&2
  sed 's/^/::error::  sentry_issue_alert./' <<<"$only_forget" >&2
fi
if [[ -n "$only_import" ]]; then
  echo "::error::IMPORTED BUT NOT FORGOTTEN — these addresses are adopted while the old address stays in state, so the same live rule is managed twice:" >&2
  sed 's/^/::error::  sentry_alert./' <<<"$only_import" >&2
fi
echo "::error::Restore the missing removed{}/import{} block. Each of the 27 rules needs BOTH: the removed{} drops the sentry_issue_alert address out of state without touching Sentry, and the import{} adopts the same live rule at its sentry_alert address. One without the other either orphans a live paging rule or plans a create that collides with it." >&2
exit 1
