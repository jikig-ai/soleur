#!/usr/bin/env bash
# §2.9 — all 27 adopted `sentry_alert` rules, diffed field-by-field against the
# committed live capture (#7650 Phase 2). AC19/AC20/AC22.
#
# ── WHAT THIS CATCHES THAT NOTHING ELSE DOES ───────────────────────────────
# A migrated rule can go dark WEEKS after the adoption applies: it still exists,
# the plan is still clean, and it matches nothing. Every existing control misses
# that, each for a different reason:
#
#   * `assert-byok-rules-exist.sh` covers 4 of the 27 by name and enablement.
#     Twenty-three rules are outside it entirely, and for the four inside it a
#     `tagged_event` whose key was renamed in the UI still reads as live.
#   * The destroy gate reads a PLAN. A rule edited in the Sentry UI produces a
#     plan diff only when Terraform next refreshes it, and `ignore_changes`
#     hides `environment` regardless.
#   * A green `terraform plan` says config and state agree. It says nothing
#     about whether the live rule still fires on the events it was written for.
#
# So this reads LIVE Sentry and compares it to the capture the 27 blocks were
# generated from — the same file, so a divergence here is a real difference
# between what was authored and what is running.
#
# Covers, for all 27: deletion, `enabled:false`, name drift, changed
# `comparison.{value,interval}`, changed `tagged_event` key/match/value,
# `logicType` flip, and `detectorIds` (monitor_ids) unbind.
#
# ── WHY `environment` IS EXCLUDED ──────────────────────────────────────────
# It is the one attribute under `lifecycle.ignore_changes` on all 27, by design.
# Including it would make this probe alarm on the one change Terraform has been
# told not to care about — a false positive on every run, which is how a drift
# probe becomes something the operator mutes.
#
# ── SCOPE COMES FROM THE SAME PREDICATE AS THE GENERATOR ───────────────────
# Not a name list. The 27 are "every live workflow whose trigger conditions the
# provider can express", and the two that stay behind plus the vendor default
# are excluded by that predicate rather than by being enumerated here. A name
# list would need editing in two places the day a rule is added, and the
# failure mode of forgetting is a rule nobody watches.
#
# Required env: SENTRY_AUTH_TOKEN, SENTRY_ORG, SENTRY_API_HOST.
# Test injection (its own suite ONLY): SENTRY_FIXTURE_RULES — file path served
# instead of the live GET. SENTRY_CAPTURE_FILE overrides the capture path.
#
# Exit 0 = every in-scope rule matches the capture.
# Exit 1 = a divergence, or the probe could not establish that it checked anything.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CAPTURE="${SENTRY_CAPTURE_FILE:-$REPO_ROOT/knowledge-base/project/specs/fix-7650-sentry-alert-migration/phase2-live-workflows-capture-2026-09-04.json}"

: "${SENTRY_AUTH_TOKEN:?SENTRY_AUTH_TOKEN must be set}"
: "${SENTRY_ORG:?SENTRY_ORG must be set}"

[[ -r "$CAPTURE" ]] || { echo "ERROR: capture not readable at $CAPTURE" >&2; exit 1; }

fetch_rules() {
  if [[ -n "${SENTRY_FIXTURE_RULES:-}" ]]; then
    cat "$SENTRY_FIXTURE_RULES"
    return
  fi
  : "${SENTRY_API_HOST:?SENTRY_API_HOST must be set (org-subdomain, e.g. jikigai-eu.sentry.io)}"
  # The NON-deprecated org workflows endpoint — the same one
  # assert-byok-rules-exist.sh migrated to in #7590. Deliberately not
  # `projects/{org}/{proj}/rules/`: that family is under brownout and would make
  # this probe red on Sentry's calendar rather than on drift.
  curl -fsS --max-time 15 \
    -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
    "https://${SENTRY_API_HOST}/api/0/organizations/${SENTRY_ORG}/workflows/?per_page=100"
}

live_json="$(fetch_rules)"

if ! jq -e 'type == "array"' >/dev/null 2>&1 <<<"$live_json"; then
  echo "ERROR: Sentry workflows response is not a JSON array. \`curl -fsS\` already aborted on any >=400, so what reaches here is a 200 carrying a non-array body: schema drift, an HTML interstitial, or a proxy injection. Cannot assert fidelity." >&2
  printf '%s\n' "$live_json" | head -c 500 >&2
  exit 1
fi

# PAGINATION CEILING, same reasoning as assert-byok-rules-exist.sh: this fetch
# asks for one page of 100 and follows no cursor. A rule on page 2 is
# indistinguishable from a deleted one, and this probe's whole output would be a
# false "27 rules are gone" alarm.
if (( $(jq 'length' <<<"$live_json") >= 100 )); then
  echo "ERROR: the workflows payload returned >= 100 rows, this fetch's unpaginated ceiling. Rules beyond page 1 would read as DELETED and produce a false alarm. Do not trust this verdict. Fix: follow the Link rel=\"next\" cursor, mirroring sentry_fetch_collection in apps/web-platform/scripts/sentry-monitors-audit.sh." >&2
  exit 1
fi

# ── The comparable projection ──────────────────────────────────────────────
# One jq program, applied to BOTH sides, so a field can never be normalised
# differently on the two halves of the comparison. `environment` is dropped for
# the reason in the header; `id` is dropped because it is the join key, not a
# property under test (a changed id is reported as deleted+new, which is what it
# is).
PROJECT='
  def excluded: ["event_unique_user_frequency_count",
                 "new_high_priority_issue",
                 "existing_high_priority_issue"];
  def in_scope: [ .triggers.conditions[]?.type ] as $t
                | (excluded | any(. as $e | $t | index($e))) | not;
  map(select(in_scope))
  | map({
      name: .name,
      enabled: .enabled,
      detectorIds: (.detectorIds // [] | sort),
      frequency: .config.frequency,
      triggerLogicType: .triggers.logicType,
      triggerConditions: ([ .triggers.conditions[]? | {type, comparison} ]
                          | sort_by(.type | tostring)),
      actionFilters: [ .actionFilters[]? | {
          logicType,
          conditions: ([ .conditions[]? | {type, comparison} ] | sort_by(tostring)),
          actions:    ([ .actions[]?    | {type, config, data} ] | sort_by(tostring))
        } ]
    })
  | INDEX(.name)
'

live_proj=$(jq "$PROJECT" <<<"$live_json")
cap_proj=$(jq  "$PROJECT" < "$CAPTURE")

cap_count=$(jq 'length' <<<"$cap_proj")
live_count=$(jq 'length' <<<"$live_proj")

# Anti-vacuity floor, stated as a POSITIVE requirement on work done. A probe
# that compared nothing must never print a clean verdict — and "the capture
# parsed to zero in-scope rules" is exactly how this would silently become a
# no-op after an unrelated edit to the capture or the predicate.
if [[ "$cap_count" -eq 0 ]]; then
  echo "ERROR: the capture yielded ZERO in-scope rules. The scope predicate and the capture disagree, so this probe would report 'no drift' having compared nothing. Refusing." >&2
  exit 1
fi

findings=0
_finding() { findings=$((findings + 1)); printf '  %s\n' "$*"; }

echo "sentry_alert live fidelity: comparing ${cap_count} captured in-scope rule(s) against ${live_count} live in-scope rule(s)"

# ── Per-rule, field-by-field ────────────────────────────────────────────────
while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  if ! jq -e --arg n "$name" 'has($n)' >/dev/null <<<"$live_proj"; then
    _finding "DELETED or RENAMED: '$name' is in the capture and absent from live Sentry. An apply can recreate a deleted rule; a rule renamed in the UI needs the name restored (Terraform owns \`name\`, so the next apply would otherwise create a SECOND rule)."
    continue
  fi
  if ! jq -e --arg n "$name" '.[$n].enabled == true' >/dev/null <<<"$live_proj"; then
    _finding "DISABLED: '$name' exists but is not enabled — it pages nobody. Enablement is live state; an apply will NOT fix it."
  fi
  # Field-by-field so the report names WHICH attribute moved, not just "differs".
  while IFS= read -r field; do
    [[ -n "$field" ]] || continue
    local_cap=$(jq -c --arg n "$name" --arg f "$field" '.[$n][$f]' <<<"$cap_proj")
    local_live=$(jq -c --arg n "$name" --arg f "$field" '.[$n][$f]' <<<"$live_proj")
    if [[ "$local_cap" != "$local_live" ]]; then
      case "$field" in
        detectorIds)
          _finding "MONITOR UNBIND: '$name'.detectorIds captured=$local_cap live=$local_live — the rule is bound to a different detector (or none), so it watches nothing while still appearing healthy." ;;
        triggerLogicType)
          _finding "LOGICTYPE FLIP: '$name'.triggers.logicType captured=$local_cap live=$local_live — the rule now requires all/any of its triggers where it required the other." ;;
        triggerConditions|actionFilters)
          # Narrow to the LEAF PATHS that moved. Printing both whole arrays is
          # technically complete and practically unreadable: a one-key rename
          # inside one condition renders as two ~600-character blobs the reader
          # has to diff by eye, at the moment they are least able to. An
          # element-level `$a - $b` does not help either — the differing element
          # IS the whole object — so this descends to scalars and reports
          # `path: captured -> live`, which is the sentence the operator needs.
          _finding "DRIFT: '$name'.$field"
          while IFS= read -r leaf; do
            [[ -n "$leaf" ]] && _finding "         $leaf"
          # `paths` reads the INPUT, and this runs under `-n`, so `$v |` is
          # required — without it every call returns nothing and the loop prints
          # an empty drift report while claiming a divergence.
          #
          # Presence is tested with `has`, never `// "<absent>"`: a leaf whose
          # value is `false` or `null` is falsy, and the `//` form would render
          # a real `false` as absent and hide the exact flip
          # (`enabled`-shaped booleans live in these structures).
          done < <(jq -r --argjson a "$local_cap" --argjson b "$local_live" -n '
            def leaves($v): [ ($v | paths(scalars)) as $p
                              | {k: ($p | map(tostring) | join(".")), v: ($v | getpath($p))} ]
                            | INDEX(.k);
            leaves($a) as $A | leaves($b) as $B
            | (($A | keys) + ($B | keys) | unique)[] as $k
            | (if ($A | has($k)) then ($A[$k].v | tojson) else "<absent>" end) as $ca
            | (if ($B | has($k)) then ($B[$k].v | tojson) else "<absent>" end) as $li
            | select($ca != $li)
            | "\($k): captured=\($ca) live=\($li)"
          ') ;;
        *)
          _finding "DRIFT: '$name'.$field captured=$local_cap live=$local_live" ;;
      esac
    fi
  done < <(printf '%s\n' enabled detectorIds frequency triggerLogicType triggerConditions actionFilters)
done < <(jq -r 'keys[]' <<<"$cap_proj")

# ── The other direction: an in-scope live rule the capture never saw ────────
# Not cosmetic. A rule created outside Terraform that is in scope is one the
# adoption does not manage, and the next author to regenerate from the capture
# will not see it.
while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  jq -e --arg n "$name" 'has($n)' >/dev/null <<<"$cap_proj" && continue
  _finding "UNMANAGED: '$name' is live and in scope but absent from the capture — created outside Terraform, or the capture is stale. Nothing in this repo manages it."
done < <(jq -r 'keys[]' <<<"$live_proj")

if [[ "$findings" -eq 0 ]]; then
  echo "sentry_alert live fidelity: PASS (all ${cap_count} in-scope rules match the committed capture field-for-field)"
  exit 0
fi

echo "ERROR: sentry_alert live fidelity FAILED — ${findings} divergence(s) between live Sentry and the committed capture at ${CAPTURE}." >&2
echo "A rule that exists, plans clean, and matches nothing is the failure this probe is for. Re-read the findings above: DELETED and DRIFT are repaired by an apply; DISABLED and MONITOR UNBIND are live state an apply will not touch." >&2
exit 1
