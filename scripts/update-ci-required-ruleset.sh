#!/usr/bin/env bash
# Add `skill-security-scan PR gate` to the "CI Required" ruleset
# (R15 mitigation, #3542; closes the trust-boundary gap from #2719).
#
# Idempotent: if the check is already in required_status_checks, exit 0
# with a no-op message.
#
# Dry-run: `--dry-run` prints the payload without PUT.
# JSON output: `--json` emits a structured envelope to stdout (status,
#   before, after, snapshot_path); human prose goes to stderr.
#
# IMPORTANT: Run AFTER bot workflow updates (Phase 2 in
# plans/2026-05-11-feat-skill-security-scan-branch-protection-plan.md)
# have merged to main. If run before, bot PRs from the 3 inline workflows
# + 5 composite-action workflows will deadlock on the new required check
# until their next run reflects the merge.
#
# Exit codes:
#   0 = success or no-op (already present)
#   1 = preflight / fetch / fatal error
#   2 = post-PUT integrity drift (rollback required)
#
# Refs: #3542 (this work), #2719 (R15 origin), #3524 (parent skill PR),
#   learning 2026-04-03-github-ruleset-put-replaces-entire-payload.md

set -euo pipefail

REPO="jikig-ai/soleur"
RULESET_ID=14145388
NEW_CHECK="skill-security-scan PR gate"
GITHUB_ACTIONS_INTEGRATION_ID=15368  # github-actions[bot]
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CANONICAL_BYPASS_FILE="${SCRIPT_DIR}/ci-required-ruleset-canonical-bypass-actors.json"
DRY_RUN=0
JSON_OUT=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --json)    JSON_OUT=1 ;;
    *)         echo "::error::Unknown flag: $arg" >&2; exit 1 ;;
  esac
done

# Human prose to stderr when JSON envelope is requested so stdout stays parseable.
say() {
  if (( JSON_OUT )); then
    printf '%s\n' "$*" >&2
  else
    printf '%s\n' "$*"
  fi
}

before=$(mktemp)
payload=$(mktemp)
after=$(mktemp)
trap 'rm -f "$payload" "$after"' EXIT  # $before is moved to an audit path before exit

# 1. Preflight: confirm the composite action AND the 3 inline workflows on
#    main already have the new check token. If any are missing, the
#    ruleset PUT would deadlock the corresponding bot fleet.
say "Preflight: checking bot workflows on main contain '$NEW_CHECK'..."
preflight_paths=(
  ".github/actions/bot-pr-with-synthetic-checks/action.yml"
  ".github/workflows/scheduled-content-publisher.yml"
  ".github/workflows/scheduled-disk-io-24h-recheck.yml"
  ".github/workflows/scheduled-disk-io-7d-recheck.yml"
)
for path in "${preflight_paths[@]}"; do
  contents_b64=$(gh api "repos/${REPO}/contents/${path}?ref=main" --jq '.content' 2>/dev/null || true)
  if [[ -z "$contents_b64" ]]; then
    echo "::error::Could not fetch ${path} from main" >&2
    exit 1
  fi
  if ! echo "$contents_b64" | base64 -d | grep -qF "$NEW_CHECK"; then
    echo "::error::${path} on main does NOT include '$NEW_CHECK'." >&2
    echo "         Merge Phase 2 first, then re-run this script." >&2
    exit 1
  fi
done
say "Preflight OK: all bot workflows on main include the new check token."

# 2. Snapshot current ruleset (live; never trust cached values)
gh api "repos/${REPO}/rulesets/${RULESET_ID}" > "$before"

# Helper: select the required_status_checks rule by type, not by array index.
# A future operator may add a sibling rule (pull_request, deletion, etc.) and
# rule ordering is not contractual. The `.rules[0]`-positional pattern would
# either drop the wrong rule's parameters or silently strip sibling rules.
rsc_rule_jq='(.rules | map(select(.type == "required_status_checks")) | .[0])'

# 3. Sanity: at least one existing required check must use integration_id
#    15368 (github-actions[bot]). If GitHub renumbers the integration id,
#    the new row's hardcoded value will drift from siblings and bot PRs
#    will silently fail to satisfy the gate.
if ! jq -e --argjson iid "$GITHUB_ACTIONS_INTEGRATION_ID" \
    "${rsc_rule_jq}.parameters.required_status_checks | map(.integration_id) | index(\$iid) != null" \
    "$before" >/dev/null; then
  echo "::error::No existing required_status_check has integration_id=${GITHUB_ACTIONS_INTEGRATION_ID}." >&2
  echo "         The github-actions[bot] integration may have been renumbered; verify before adding." >&2
  exit 1
fi

# 4. Idempotency check (type-filtered)
if jq -e --arg c "$NEW_CHECK" \
    "${rsc_rule_jq}.parameters.required_status_checks | map(.context) | index(\$c) != null" \
    "$before" >/dev/null; then
  say "Already present in required_status_checks. No-op."
  if (( JSON_OUT )); then
    jq -n --arg status "noop" --slurpfile before "$before" \
      '{status: $status, before: $before[0].rules}'
  fi
  exit 0
fi

# 5. Build updated payload — preserve bypass_actors, conditions, name,
#    target, enforcement verbatim from the GET. The PUT API replaces the
#    entire payload, so any omission silently strips the field. Sibling
#    rules (if any) are preserved by reconstructing the rules array.
jq --arg c "$NEW_CHECK" --argjson iid "$GITHUB_ACTIONS_INTEGRATION_ID" '
  . as $orig
  | ($orig.rules | map(select(.type == "required_status_checks")) | .[0]) as $rsc
  | ($orig.rules | map(select(.type != "required_status_checks"))) as $siblings
  | {
      name: $orig.name,
      target: $orig.target,
      enforcement: $orig.enforcement,
      bypass_actors: $orig.bypass_actors,
      conditions: $orig.conditions,
      rules: ($siblings + [{
        type: "required_status_checks",
        parameters: {
          strict_required_status_checks_policy: $rsc.parameters.strict_required_status_checks_policy,
          do_not_enforce_on_create: $rsc.parameters.do_not_enforce_on_create,
          required_status_checks: ($rsc.parameters.required_status_checks + [{context: $c, integration_id: $iid}])
        }
      }])
    }
' "$before" > "$payload"

say "Proposed required_status_checks contexts:"
say "$(jq -r "${rsc_rule_jq}.parameters.required_status_checks[].context" "$payload" | sort)"
say "---"
say "bypass_actors (verbatim from before-snapshot):"
say "$(jq '.bypass_actors' "$payload")"
say "---"
say "conditions (verbatim from before-snapshot):"
say "$(jq '.conditions' "$payload")"

# Persist the pre-mutation snapshot to a durable audit path BEFORE any
# mutation. Runbook (knowledge-base/engineering/ops/runbooks/skill-security
# -scan-required-check.md) requires retaining $before for 24h as the
# canonical rollback artifact; an EXIT-trap rm contradicts that.
audit_dir="${XDG_STATE_HOME:-$HOME/.local/state}/soleur"
mkdir -p "$audit_dir"
ts=$(date -u +%Y%m%dT%H%M%SZ)
snapshot_path="${audit_dir}/ruleset-${RULESET_ID}-${ts}.json"
cp "$before" "$snapshot_path"
say "Pre-mutation snapshot retained at: $snapshot_path"
say "(Retain for at least 24h; canonical rollback artifact.)"

if (( DRY_RUN )); then
  say "---"
  say "Dry-run mode -- no mutation."
  if (( JSON_OUT )); then
    jq -n --arg status "dry-run" --arg snap "$snapshot_path" \
      --slurpfile payload "$payload" \
      '{status: $status, snapshot_path: $snap, proposed: $payload[0]}'
  fi
  exit 0
fi

# 6. Apply (per hr-menu-option-ack-not-prod-write-auth, the caller has
#    already shown the exact command to the operator and received explicit
#    per-command go-ahead).
say "---"
say "Applying PUT..."
gh api --method PUT "repos/${REPO}/rulesets/${RULESET_ID}" --input "$payload" > "$after"
say "PUT succeeded. Verifying preserved fields..."

# 7. Verify every preserved field (not just bypass_actors/conditions). The
#    PUT API silently strips any field omitted from the payload, and a
#    future GitHub schema change could introduce a top-level field whose
#    drop we'd otherwise miss.
preserved_fields=(name target enforcement bypass_actors conditions)
drift=0
for field in "${preserved_fields[@]}"; do
  if ! diff <(jq -S ".${field}" "$before") <(jq -S ".${field}" "$after") >/dev/null; then
    echo "::error::${field} drifted after PUT -- INVESTIGATE" >&2
    diff <(jq -S ".${field}" "$before") <(jq -S ".${field}" "$after") >&2 || true
    drift=1
  fi
done
# Also verify strict_required_status_checks_policy survived
if ! diff \
    <(jq -S "${rsc_rule_jq}.parameters.strict_required_status_checks_policy" "$before") \
    <(jq -S "${rsc_rule_jq}.parameters.strict_required_status_checks_policy" "$after") >/dev/null; then
  echo "::error::strict_required_status_checks_policy drifted after PUT -- INVESTIGATE" >&2
  drift=1
fi
# Verify the newly-added check has the correct integration_id (no spoof)
new_iid=$(jq --arg c "$NEW_CHECK" \
  "${rsc_rule_jq}.parameters.required_status_checks | map(select(.context == \$c))[0].integration_id" \
  "$after")
if [[ "$new_iid" != "$GITHUB_ACTIONS_INTEGRATION_ID" ]]; then
  echo "::error::New check integration_id is ${new_iid}, expected ${GITHUB_ACTIONS_INTEGRATION_ID}" >&2
  echo "         Without integration_id constraint, any GitHub App with checks:write could spoof the gate." >&2
  drift=1
fi

# Audit fast-path (#3544): diff round-tripped bypass_actors against the
# canonical in-repo JSON, not just the pre-mutation snapshot. The PUT API
# copies bypass_actors verbatim from $before, so a same-PUT-cycle drift
# would not surface in the before/after diff — only the canonical
# comparison catches an admin-broadened bypass that happened to land in
# the pre-mutation snapshot.
if [[ -f "$CANONICAL_BYPASS_FILE" ]]; then
  bypass_canonical_norm=$(jq -S 'map({actor_type, actor_id, bypass_mode}) | sort_by(.actor_type, (.actor_id // "null" | tostring), .bypass_mode)' "$CANONICAL_BYPASS_FILE")
  bypass_after_norm=$(jq -S '.bypass_actors | map({actor_type, actor_id, bypass_mode}) | sort_by(.actor_type, (.actor_id // "null" | tostring), .bypass_mode)' "$after")
  if [[ "$bypass_canonical_norm" != "$bypass_after_norm" ]]; then
    echo "::error::bypass_actors after PUT does not match canonical at ${CANONICAL_BYPASS_FILE}" >&2
    echo "         canonical: ${bypass_canonical_norm}" >&2
    echo "         after PUT: ${bypass_after_norm}" >&2
    echo "         If the bypass change is intentional, update the canonical JSON FIRST," >&2
    echo "         then re-run; the daily audit reads the same file." >&2
    drift=1
  fi
else
  echo "::warning::canonical bypass file missing at ${CANONICAL_BYPASS_FILE} — skipping audit fast-path check" >&2
fi

(( drift )) && exit 2

say "Verification OK. Final required_status_checks contexts:"
final_contexts=$(gh api "repos/${REPO}/rulesets/${RULESET_ID}" \
  --jq "${rsc_rule_jq}.parameters.required_status_checks[].context" | sort)
say "$final_contexts"

if (( JSON_OUT )); then
  jq -n \
    --arg status "applied" \
    --arg snap "$snapshot_path" \
    --slurpfile before "$before" \
    --slurpfile after "$after" \
    '{status: $status, snapshot_path: $snap, before: $before[0].rules, after: $after[0].rules}'
fi
