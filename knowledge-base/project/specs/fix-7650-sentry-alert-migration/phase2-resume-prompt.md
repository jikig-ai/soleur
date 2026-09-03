# Resume prompt — #7650 Phase 2 state surgery

Paste the block below into a fresh session. It is written to be verified, not trusted:
every number in it was measured, and the ones most likely to have gone stale are marked.

---

/soleur:go Resume #7650 Phase 2 — migrate the Sentry issue alerts off the deprecated
alert-rule API by importing them as `sentry_alert`. Do NOT re-plan from scratch; Phases 0
and 1 are done and merged. Do NOT re-derive the ESTABLISHED section.

STATE (verify, don't trust). Base is main at `2a6903a97` or later. Confirm before starting:
  git show origin/main:apps/web-platform/infra/sentry/versions.tf | grep 'version = "0.15'
    -> must be 0.15.7 (merged as 2a6903a97). If it is higher, RE-READ the provider source
       at that tag before trusting anything below about what the provider supports.
  git show origin/main:tests/scripts/lib/destroy-guard-filter-sentry.jq | grep -c sentry_alert_blocks_count
    -> must be 2. This is Phase 1 and it MUST already be on main before any sentry_alert
       enters a plan.

THE SET IS 24, NOT 29 AND NOT 27. This is the number most likely to be got wrong, and
three different figures are defensible-looking, so derive it rather than quoting it:

  30 live workflows in the org
  -1  "Send a notification for high priority issues" (id 566201) — Sentry's OWN default.
      NEVER import it. It carries new_high_priority_issue / existing_high_priority_issue,
      which the provider cannot represent, and it is not ours to manage.
  -2  auth-per-user-loop (566671) and sandbox-startup-failure (669246) — carry
      event_unique_user_frequency_count, which the provider still cannot express as a
      TRIGGER at 0.15.7. Filed upstream as jianyuan/terraform-provider-sentry#950.
      Check whether #950 has been fixed before assuming these are still blocked.
  -3  auth-signout-burst (566672), auth-exchange-code-burst (566682),
      auth-callback-no-code-burst (566683) — the provider CAN express these, but their
      Terraform blocks are empty shells (`conditions_v2 = []` under a wide
      `ignore_changes`) and configure-sentry-alerts.sh is their only executable
      definition. See THE AUTH FOUR below — this is a scope decision, not a blocker.
  = 24 to migrate in this pass.

Regenerate the set rather than trusting the list:
  doppler run -p soleur -c prd -- bash -c '
    curl -sS -H "Authorization: Bearer $SENTRY_IAC_AUTH_TOKEN" \
      "https://$SENTRY_API_HOST/api/0/organizations/$SENTRY_ORG/workflows/?per_page=100"' \
  | jq -r '.[] | . as $w
      | ([$w.triggers.conditions[] | select(
           .type=="first_seen_event" or .type=="reappeared_event"
           or .type=="regression_event" or .type=="issue_resolved_trigger"
           or (.type=="event_frequency_count" and (.comparison|type)=="object"))] | length) as $ok
      | select($ok == ([$w.triggers.conditions[]]|length))
      | select(($w.name|startswith("auth-")|not)
               and $w.name != "Send a notification for high priority issues")
      | "\($w.name) \($w.id)"'

ESTABLISHED — do not re-derive:

- Import ID format is `organization/id` (e.g. `jikigai-eu/728266`), or the full
  `https://{org}.sentry.io/monitors/alerts/{id}/` URL. From the provider's own import.sh.
- `terraform state rm` is refresh-free: it does NOT call the provider read, so it works
  DURING a brownout. `removed {}` blocks are likely DOA — a plan/apply refresh of the
  removed resource hits the 410. Use `state rm`, not `removed {}`.
- Sentry already migrated all 29 of our rules server-side: `rules/` and `workflows/` are
  two views of the SAME objects. So this is an IMPORT, not a re-creation — the target
  objects exist with correct semantics and Terraform only needs to start managing them.
- All 30 workflows bind to detector `1213799` (issue_stream). Uniform. Do not branch
  `monitor_ids` per rule class.
- Credentials: `SENTRY_IAC_AUTH_TOKEN` from `doppler -p soleur -c prd`. The R2 state
  backend needs AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY from `-c prd_terraform`
  (a DIFFERENT config) or terraform init fails with an EC2 IMDS error.

THE MAPPING, measured at 0.15.7 — and note the plan is STALE here:
  lifecycle (first_seen_event / reappeared_event / regression_event) -> trigger_conditions,
      logic_type any-short
  event_frequency_count                  -> trigger_conditions  (NEW at 0.15.7 via #943;
      the plan still says "NOT MIGRATABLE at v0.15.5", which was true then and is now
      stale. It is version-scoped, so it is not wrong — but do not follow it.)
  event_unique_user_frequency_count      -> NOT EXPRESSIBLE as a trigger. #950.
  tagged_event / level                   -> action_filters[].conditions
  filter_match                           -> action_filters[].logic_type
  actions_v2 + frequency                 -> action_filters[].actions + frequency_minutes
  monitor_ids                            -> ["1213799"]

CONSTRAINTS — these look like defects and are not:

- SEQUENCING IS LOAD-BEARING. Run `state rm` + `import` BEFORE the merge that lands the
  `sentry_alert` blocks. Get it backwards and the post-merge full-root apply CREATES 24
  duplicate live paging rules. The create-gate would catch it, but do not rely on that.
- Execution vehicle is a one-time `workflow_dispatch`, never SSH. apply-sentry-infra.yml
  already has a `workflow_dispatch` with a reason input; apply-web-platform-infra.yml has
  the import/state-surgery pattern to mirror.
- PRESERVE EVERY `name` BYTE-FOR-BYTE. `assert-byok-rules-exist.sh`'s EXPECTED_RULES and
  operator dashboard queries both key on names.
- The brownout retry STAYS. Even at 24/29 migrated, the full-root plan still refreshes the
  remaining `sentry_issue_alert` resources through the deprecated endpoint, so the gate can
  still wedge. Phase 3.4 — remove the retry only when ZERO remain — is unchanged and now
  depends on #950 and on the auth-four decision.
- Do NOT delete configure-sentry-alerts.sh. It is the only executable definition of the
  four auth-* rules' filters.

THE AUTH FOUR — a decision, not a blocker, and worth surfacing to the operator:
Their Terraform blocks are empty shells; the live definitions were previously readable only
from configure-sentry-alerts.sh. Phase 0 established they are now readable from the API:
  auth-signout-burst / auth-exchange-code-burst / auth-callback-no-code-burst
      event_frequency_count            -> expressible at 0.15.7
  auth-per-user-loop
      event_unique_user_frequency_count -> blocked by #950
So three of the four COULD be authored properly as `sentry_alert` with their real
definitions, which would retire the script's ownership and address #4781's drift-to-empty
recurrence. That is a scope expansion beyond "move 24 rules" and changes what owns live
paging config — put it to the operator rather than folding it in silently.

TRAPS THIS ISSUE HAS ALREADY SPRUNG (all three cost real time):

1. READ THE PROVIDER SOURCE AT THE TAG, NOT THE CHANGELOG. A changelog-sourced claim closed
   #6636 on a false premise and cost four months; the same shape recurred twice more inside
   #7650. If you assert what the provider does, cite the file and line at the pinned tag.
2. 0.15.7 STILL ROUTES A BOOLEAN COMPARISON TO LEGACY. An `event_frequency_count` whose
   comparison is a bare boolean (not an object) still falls into `legacy_trigger_conditions`
   and loses its threshold. All 11 of ours were measured as objects — RE-MEASURE, do not
   assume. The regenerate command above already encodes the object check.
3. `ignore_changes` MARKS TWO DISJOINT SETS IN ONE FILE. A file-level grep cannot tell the
   BYOK/chat rules (Terraform owns their filters) from the auth-* four (it does not).
   Resolve the attribute PER RESOURCE BLOCK.

VERIFY, in this order:

  1. `terraform plan` full-root -> no-op 0/0/0, no 410s, across sentry_alert +
     sentry_issue_alert + sentry_cron_monitor + sentry_uptime_monitor.
  2. Destroy guard on the REAL plan json -> {"resource_deletes":0,"resource_creates":0,
     "nested_deletes":0}, and the type-scope guard covers every type in `.tf UNION state`.
  3. `assert-byok-rules-exist.sh` still lists all four EXPECTED_RULES by name, ENABLED.
  4. A clean plan is NOT evidence the deprecation lifted — it may just mean you planned
     outside a brownout window. Say so explicitly rather than implying otherwise.

REVIEW: this touches live paging state, including the GDPR Art. 33 breach alert. Ask the
operator to authorise a review panel before shipping. Every panel run on this issue so far
found criticals that self-review missed, including a guard that was a tautology and a test
that passed while the code laundered failures.

Prior art, all merged: #7598 (retry + meter), #7715 (Phase 1 destroy guard), #7750 (Phase 2
blocker + re-scope), #7809 (0.15.7 bump). Plan:
knowledge-base/project/plans/2026-08-25-fix-7650-sentry-issue-alert-to-alert-migration-plan.md
Evidence: knowledge-base/project/specs/fix-7650-sentry-alert-migration/
