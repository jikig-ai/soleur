# sentry-alert-projection.jq — the ONE comparable shape for a `sentry_alert`,
# reachable from three inputs (#8050).
#
#   jq --arg side tf        -f this.jq <terraform show -json plan-or-state>
#   jq --arg side live      -f this.jq <GET /api/0/organizations/{org}/workflows/>
#   jq --arg side reference -f this.jq <an already-projected document>
#
# Every side emits `{ <rule name>: { actionFilters, detectorIds, enabled,
# frequency, name, triggerConditions, triggerLogicType } }` with canonical key
# order and sorted arrays, so two documents are equal iff the rules they describe
# are equal. One definition of `canon` and `normalise` serves all three sides: a
# field can never be normalised differently on the two halves of a comparison.
#
# WHY THE REFERENCE IS PROJECTED FROM TERRAFORM AND NOT CAPTURED FROM LIVE. The
# post-apply probe used to compare live Sentry against a committed live capture.
# A rule cannot be live-captured before it is applied, so every rule added in a
# PR was UNMANAGED to that probe on the merge that applied it — `main` went red
# after a COMPLETE apply, twice (#7772 -> #7985, #7989 -> #8050). The plan the
# apply job is about to apply already carries every Terraform-owned field of
# every declared rule; projecting it gives the probe a reference that is true by
# construction the moment the `.tf` changes.
#
# MEASURED, NOT INFERRED. The `tf` side was measured against the real post-apply
# state of run 34491157462 (29 `sentry_alert`, serial 124) and the 2026-09-09
# live capture: 28 common rules, 0 mismatches, once the two normalisations below
# are applied. Each `trigger_conditions[]` / `action_filters[].conditions[]` /
# `actions[]` element in the provider's shape carries exactly ONE non-null key
# (the live `type`) and every other key as null.
#
# NORMALISATION 1 — lifecycle triggers. The provider renders `first_seen_event`,
# `reappeared_event`, `regression_event` and `issue_resolved_trigger` as `{}`;
# the live API renders their `comparison` as `true`. Both mean "no parameters".
#
# NORMALISATION 2 — trigger logicType. The provider HARD-CODES it: at tag
# v0.15.7, `internal/provider/resource_alert_impl.go` sets
# `OrganizationWorkflowTriggerLogicTypeAnyShort` in BOTH the create (line 803)
# and the update (line 835) request builders, and `sentry_alert` exposes no
# attribute for it (the `issue-alerts.tf` header says the same). The 15
# single-trigger rules read `all` in live Sentry only because they were imported
# and never PUT; the first `.tf` edit to one of them makes live `any-short`. With
# ONE condition any/all are indistinguishable, so both sides project the constant
# `single` for a single-trigger rule; a multi-trigger rule projects `any-short`
# on the Terraform side (what the provider will write) and the REAL value on the
# live side, so a flip to `all` made in the Sentry UI still reports.
#
# EVERY FLOOR IS AN `error`, NEVER A DEFAULT. jq exits 5 on `error(...)`, and
# every caller must refuse on a non-zero rc (the gate and the probe capture it on
# its own line; the apply workflow's plan step uses `|| { …; exit 1; }` because
# `set -e` is armed there) — a projection that quietly emits `{}` or `null` for
# an unexpected input would make a downstream "0 rules compared" read as a clean
# verdict. The one deliberate non-error is `trigger_logic_type`'s TF-side
# constant (documented at the definition); the LIVE side never defaults.
#
# ALLOWLISTS, NOT PASS-THROUGH, for every element kind. The provider renders each
# condition/action kind as its own snake_case sub-object, and the live API
# renders the same kind in camelCase or as a scalar — measured in the provider's
# wire structs for `assigned_to` (`target_id` -> `targetIdentifier`),
# `age_comparison` (`comparison_type` -> `comparisonType`), `latest_release`
# (`{}` -> `true`), `issue_priority_*` (`{comparison: 75}` -> `75`), and every
# optional sub-attribute (`null` here, `omitempty`-absent there). Passing an
# unmapped kind through would make the PR-time gate green (tf vs tf) and the
# post-apply probe red after a COMPLETE apply — the #8050 class again. So a kind
# outside the allowlist is an `error` at PR time, and adding one means mapping it
# on BOTH sides here plus a shape-parity row in the probe's suite.

def canon: walk(if type == "object" then (to_entries | sort_by(.key) | from_entries) else . end);

# Array order is not semantic on either side. Sort AFTER canon so `tostring`
# serialises identical data identically regardless of input key order — a
# hand-built fixture with `{value, interval}` order would otherwise sort into a
# different array position than the live side's `{interval, value}`.
def normalise: canon
  | with_entries(.value |= (
      .detectorIds |= sort
      | .triggerConditions |= sort_by(tostring)
      | .actionFilters |= map(.conditions |= sort_by(tostring) | .actions |= sort_by(tostring))
      | .actionFilters |= sort_by(tostring)));

# Trigger types the provider cannot express as `sentry_alert` (they stay
# `sentry_issue_alert` and are outside the probe's live scope by this predicate).
def excluded: ["event_unique_user_frequency_count", "new_high_priority_issue", "existing_high_priority_issue"];
# Lifecycle triggers: the provider renders them `{}`; the live API renders their
# `comparison` as `true`. Both mean "no parameters".
def lifecycle: ["first_seen_event", "reappeared_event", "regression_event", "issue_resolved_trigger"];
# Kinds the projection maps, per element position. Each has a MEASURED live shape
# (the 2026-09-09 capture, 28 rules): `event_frequency_count` -> `{interval,value}`
# on both sides; `tagged_event` -> `{key,match,value}` on both sides with every
# key set; `email` -> the field mapping in `tf_action`. Everything else is an
# `error` (see the header).
def trigger_kinds: lifecycle + ["event_frequency_count"];
def condition_kinds: ["tagged_event"];
def action_kinds: ["email"];

# Trigger logicType (NORMALISATION 2 in the header). One condition has no logic,
# so a single-trigger rule projects the constant `single` on both sides — and a
# live `none` on one trigger is NOT folded into it (it inverts the trigger, so it
# reports). A multi-trigger rule projects `any-short` on the TF side (the value
# the provider will write; `$live` is null there by construction) and the REAL
# value on the live side — a live workflow with more than one trigger and no
# `logicType` is an error, never a default that happens to equal the TF side.
def trigger_logic_type($n; $live):
  if $n <= 1 then (if $live == null or ($live | IN("all", "any", "any-short")) then "single" else $live end)
  elif $live == null then "any-short"
  else $live end;
def live_trigger_logic_type($n; $live):
  if $n > 1 and $live == null
  then error("live side: a workflow with \($n) trigger conditions carries no triggers.logicType; refusing to default it")
  else trigger_logic_type($n; $live) end;

# Shape, NOT cardinality: `{}` passes, so the callers' zero-rules floor stays
# reachable and testable.
#
# WHAT IS NOT IN THE SHAPE, deliberately. `environment` is the one attribute
# under `lifecycle.ignore_changes` on every `sentry_alert` block, by design
# (issue-alerts.tf documents the UI-binding case it tolerates); comparing it here
# would alarm on the one change Terraform has been told not to care about.
# `organization` is the provider's routing, not the rule. `id` is the join key.
def rule_keys: ["actionFilters", "detectorIds", "enabled", "frequency", "name", "triggerConditions", "triggerLogicType"];
def shape_ok:
  type == "object"
  and all(.[]; type == "object" and (keys == rule_keys));

# ── side == "tf" ─────────────────────────────────────────────────────────────
def one_key($ctx):
  (to_entries | map(select(.value != null))) as $set
  | if ($set | length) != 1
    then error("\($ctx): a condition/action element must carry exactly one non-null key, got \($set | length) (\($set | map(.key) | join(",")))")
    else $set[0] end;

# `.key as $k | (list | index($k))` — NOT `list | index(.key)`: inside that pipe
# `.key` would be evaluated against the LIST, not the element.
def tf_trigger($ctx):
  one_key($ctx)
  | .key as $k
  | if (trigger_kinds | index($k)) == null
    then error("\($ctx): trigger kind '\($k)' is not mapped by the projection (allowlist: \(trigger_kinds | join(","))); map it here and on the live side together, with a shape-parity row")
    else {type: $k, comparison: (if (lifecycle | index($k)) != null then true else .value end)} end;

def tf_condition($ctx):
  one_key($ctx)
  | .key as $k
  | if (condition_kinds | index($k)) == null
    then error("\($ctx): condition kind '\($k)' is not mapped by the projection (allowlist: \(condition_kinds | join(","))); map it here and on the live side together, with a shape-parity row")
    else {type: $k, comparison: .value} end;

def tf_action($ctx):
  one_key($ctx)
  | .key as $k
  | if (action_kinds | index($k)) == null
    then error("\($ctx): action kind '\($k)' is not mapped by the projection (allowlist: \(action_kinds | join(","))); map it here and on the live side together")
    else {type: $k, targetType: .value.target_type, targetIdentifier: .value.target_id, fallthroughType: .value.fallthrough_type} end;

def tf_rule:
  .address as $a
  | .values as $v
  | if (.sensitive_values | type) != "object"
    then error("\($a): sensitive_values is absent or not an object — not a terraform show -json resource; refusing to project without the sensitivity mask") else . end
  | if ([.sensitive_values | .. | select(. == true)] | length) > 0
    then error("\($a): a sensitive attribute is set on a sentry_alert; `terraform show -json` renders sensitive VALUES in plaintext, so the projection refuses rather than commit one") else . end
  | if ($v.enabled | type) != "boolean" then error("\($a): enabled is not a boolean (\($v.enabled | tojson)) — unknown at plan time; set it explicitly in the block") else . end
  | if ($v.trigger_conditions | type) != "array" then error("\($a): trigger_conditions is not an array (\($v.trigger_conditions | tojson))") else . end
  | if ($v.action_filters | type) != "array" then error("\($a): action_filters is not an array (\($v.action_filters | tojson))") else . end
  | if ($v.name | type) != "string" then error("\($a): name is not a string") else . end
  | if ($v.frequency_minutes | type) != "number" then error("\($a): frequency_minutes is not a number") else . end
  | if ($v.monitor_ids | type) != "array" then error("\($a): monitor_ids is not an array (\($v.monitor_ids | tojson))") else . end
  | {
      name: $v.name,
      enabled: $v.enabled,
      detectorIds: $v.monitor_ids,
      frequency: $v.frequency_minutes,
      triggerLogicType: trigger_logic_type($v.trigger_conditions | length; null),
      triggerConditions: [ $v.trigger_conditions[] | tf_trigger($a) ],
      actionFilters: [ $v.action_filters[]
        | if (.conditions | type) != "array" then error("\($a): an action_filters[].conditions is not an array") else . end
        | if (.actions | type) != "array" then error("\($a): an action_filters[].actions is not an array") else . end
        | {
            logicType: .logic_type,
            conditions: [ .conditions[] | tf_condition($a) ],
            actions: [ .actions[] | tf_action($a) ]
          } ]
    };

def project_tf:
  ((.planned_values // .values) // error("not a terraform show -json plan or state document (no .planned_values and no .values)"))
  | .root_module
  | if ((.child_modules // []) | length) > 0
    then error("the root carries child_modules; the projection reads root_module.resources only and refuses a second injection site") else . end
  | [ (.resources // [])[] | select(.type == "sentry_alert") ]
  | canon
  | map(tf_rule)
  | (group_by(.name) | map(select(length > 1) | .[0].name)) as $dups
  | if ($dups | length) > 0 then error("duplicate sentry_alert name(s): \($dups | join(","))") else . end
  | INDEX(.name)
  | normalise;

# ── side == "live" ───────────────────────────────────────────────────────────
# The probe's projection, moved here from scripts/sentry-alert-live-fidelity.sh.
# ALLOWLIST PROJECTION, not a blocklist: the live API returns server-assigned
# fields on every object (`id`, `conditionResult`, `organizationId` on
# triggers/conditions; `integrationId`, `status` on actions). Measured 2026-09-04,
# comparing raw live against a normalised reference reported 38 divergences on a
# healthy org. Projecting ONLY the asserted fields makes a future server-side
# addition inert by construction.
def in_scope:
  [ .triggers.conditions[]?.type ] as $t
  | (excluded | any(. as $e | $t | index($e))) | not;

def project_live:
  if type != "array" then error("live side: input is not a JSON array of workflows") else . end
  | canon
  | map(select(in_scope))
  # A live in-scope workflow with no usable name would be indexed under `""`
  # and skipped by every consumer's `[[ -n "$name" ]]`, i.e. exempt from the
  # UNMANAGED loop. Refuse rather than drop.
  | if any(.[]; (.name | type) != "string" or .name == "")
    then error("live side: an in-scope workflow has an empty or non-string name; refusing to index it") else . end
  # Sentry does not enforce unique workflow names, and `INDEX(.name)` is
  # last-writer-wins — a disabled managed rule shadowed by an enabled same-name
  # copy would read as healthy depending on API order. Refuse; the probe reports
  # this as unavailable and the daily filer names the class.
  | (group_by(.name) | map(select(length > 1) | .[0].name)) as $dups
  | if ($dups | length) > 0 then error("live side: duplicate in-scope workflow name(s): \($dups | join(",")) — the probe cannot tell the managed rule from a same-name copy") else . end
  | map({
      name: .name,
      enabled: .enabled,
      detectorIds: (.detectorIds // []),
      frequency: .config.frequency,
      triggerLogicType: live_trigger_logic_type((.triggers.conditions // []) | length; .triggers.logicType),
      triggerConditions: [ .triggers.conditions[]? | {type, comparison} ],
      actionFilters: [ .actionFilters[]? | {
          logicType: .logicType,
          conditions: [ .conditions[]? | {type, comparison} ],
          actions: [ .actions[]? | {
              type: .type,
              targetType: .config.targetType,
              targetIdentifier: .config.targetIdentifier,
              fallthroughType: .data.fallthroughType
            } ]
        } ]
    })
  | INDEX(.name)
  | normalise;

# ── side == "reference" ──────────────────────────────────────────────────────
def project_reference:
  if shape_ok then normalise
  else error("reference is not a name-indexed projection object (expected {<name>: {\(rule_keys | join(","))}})") end;

if $side == "tf" then project_tf
elif $side == "live" then project_live
elif $side == "reference" then project_reference
else error("--arg side must be one of tf|live|reference, got '\($side)'") end
