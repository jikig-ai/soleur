# Issue alerts for the auth observability stack — operator-keyed names that
# match apps/web-platform/scripts/configure-sentry-alerts.sh byte-for-byte
# per knowledge-base/project/learnings/2026-05-13-helper-migration-must-
# preserve-operator-dashboard-message-strings.md.
#
# IMPORT-ONLY: these resources mirror existing Sentry rules created by the
# legacy script. Operator runs `terraform import sentry_issue_alert.<name>
# <org>/<project>/<rule-id>` BEFORE the first apply (see README.md). Match
# by id, never by name (Sentry API allows duplicate names — see
# 2026-04-29-supabase-auth-probe-and-sentry-rule-api-quirks.md).
#
# Lifecycle ignore_changes covers the v2 attribute set + environment +
# frequency, all of which can recompute on import for the legacy rules per
# the v0.15 release notes (Kieran P1, plan §5).
#
# ── DEPRECATION WARNING IS ACCEPTED UNTIL PROVIDER GA (#4610) ──────────────
# `terraform validate`/`plan` emits "This resource is deprecated. Please
# migrate to `sentry_alert`" for each block below. That warning is EXPECTED
# and intentionally accepted until `jianyuan/sentry` ships a stable v0.15.0.
# Do NOT migrate these to `sentry_alert` under the pinned v0.15.0-beta2:
#   - beta2's `sentry_alert` is MONITOR-bound: `monitor_ids` (set) and
#     `trigger_conditions` (first_seen|regression|reappeared|issue_resolved)
#     are BOTH required, and it has no `project` attribute.
#   - these 4 rules are PROJECT-WIDE frequency alerts (EventFrequencyCondition
#     + TaggedEventFilter) bound to no monitor — they cannot populate the
#     required fields without changing which event class fires.
#   - `terraform state mv sentry_issue_alert.X sentry_alert.X` is impossible:
#     the two schemas share only name/organization/id, so any migration would
#     DROP + READD the live paging rules (the exact failure the "match by id,
#     never recreate" rule above guards against).
# The provider's deprecation pointer is forward-looking to the GA schema, not
# a claim that beta2 supports the migration. The warning is NOT suppressible
# while the resource type is `sentry_issue_alert` (Terraform core cannot
# allow-list validate/plan warnings; the provider exposes no opt-out attr).
# Re-attempt at stable v0.15.0 when `sentry_alert` supports project-wide
# frequency alerts. Schema evidence + alternatives:
#   - ADR-031-sentry-as-iac.md (## Decision → "Defer migration" bullet)
#   - knowledge-base/project/plans/2026-05-29-refactor-sentry-issue-alert-to-sentry-alert-migration-plan.md
# ──────────────────────────────────────────────────────────────────────────

resource "sentry_issue_alert" "auth_exchange_code_burst" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "auth-exchange-code-burst"
  action_match = "all"
  filter_match = "all"
  # Frequency varies per resource (60/61/30/62) so Sentry's "exact duplicate
  # of <other-rule>" dedup at POST time doesn't conflate them. After create,
  # `lifecycle.ignore_changes` reasserts the operator-managed real value via
  # the Sentry UI. Discovered 2026-05-17 during PR-β §11 — see learning
  # 2026-05-17-sentry-issue-alert-create-dedup-on-action-match-not-conditions.md.
  frequency = 61

  # Provider schema requires actions_v2 ≥ 1 at config-time even for
  # imported resources. The placeholder is overwritten by import; lifecycle
  # ignore_changes (below) keeps the real state authoritative thereafter.
  conditions_v2 = []
  filters_v2    = []
  actions_v2 = [
    {
      notify_email = {
        target_type      = "IssueOwners"
        fallthrough_type = "ActiveMembers"
      }
    },
  ]

  lifecycle {
    ignore_changes = [
      conditions_v2,
      filters_v2,
      actions_v2,
      environment,
      frequency,
    ]
  }
}

resource "sentry_issue_alert" "auth_callback_no_code_burst" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "auth-callback-no-code-burst"
  action_match = "all"
  filter_match = "all"
  frequency    = 62 # see auth_exchange_code_burst comment for dedup rationale

  # Provider schema requires actions_v2 ≥ 1 at config-time even for
  # imported resources. The placeholder is overwritten by import; lifecycle
  # ignore_changes (below) keeps the real state authoritative thereafter.
  conditions_v2 = []
  filters_v2    = []
  actions_v2 = [
    {
      notify_email = {
        target_type      = "IssueOwners"
        fallthrough_type = "ActiveMembers"
      }
    },
  ]

  lifecycle {
    ignore_changes = [
      conditions_v2,
      filters_v2,
      actions_v2,
      environment,
      frequency,
    ]
  }
}

resource "sentry_issue_alert" "auth_per_user_loop" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "auth-per-user-loop"
  action_match = "all"
  filter_match = "all"
  frequency    = 30

  # Provider schema requires actions_v2 ≥ 1 at config-time even for
  # imported resources. The placeholder is overwritten by import; lifecycle
  # ignore_changes (below) keeps the real state authoritative thereafter.
  conditions_v2 = []
  filters_v2    = []
  actions_v2 = [
    {
      notify_email = {
        target_type      = "IssueOwners"
        fallthrough_type = "ActiveMembers"
      }
    },
  ]

  lifecycle {
    ignore_changes = [
      conditions_v2,
      filters_v2,
      actions_v2,
      environment,
      frequency,
    ]
  }
}

resource "sentry_issue_alert" "auth_signout_burst" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "auth-signout-burst"
  action_match = "all"
  filter_match = "all"
  frequency    = 60

  # Provider schema requires actions_v2 ≥ 1 at config-time even for
  # imported resources. The placeholder is overwritten by import; lifecycle
  # ignore_changes (below) keeps the real state authoritative thereafter.
  conditions_v2 = []
  filters_v2    = []
  actions_v2 = [
    {
      notify_email = {
        target_type      = "IssueOwners"
        fallthrough_type = "ActiveMembers"
      }
    },
  ]

  lifecycle {
    ignore_changes = [
      conditions_v2,
      filters_v2,
      actions_v2,
      environment,
      frequency,
    ]
  }
}

# ── BYOK delegations alert rules (#4364) — APPLY-CREATED, NOT import-only ───
# Unlike the 4 auth rules above (which mirror legacy script-created rules and
# are imported with `conditions_v2/filters_v2 = []` placeholders), these two
# have NO pre-existing Sentry rule. Terraform CREATES them from real
# conditions_v2 + filters_v2 + actions_v2, so:
#   - conditions/filters/actions are NOT under `ignore_changes` — this file is
#     the source of truth for them (the whole point of the rule).
#   - `environment` IS ignored: the provider recomputes it on read for these
#     project-wide rules just as it does for the auth rules.
#   - distinct `frequency` (5, 15) avoids Sentry's POST-time "exact duplicate"
#     dedup (keyed on action-shape + frequency + match, NOT conditions — see
#     2026-05-17-sentry-issue-alert-create-dedup-on-action-match-not-conditions.md).
#     Taken set is 60/61/62/30 (auth rules) — 5 and 15 are free.
#   - the apply workflow MUST `-target` both (see apply-sentry-infra.yml); the
#     untargeted apply is scoped to monitors so it never trips the import-only
#     auth rules.
# Tag vocabulary verified against apps/web-platform/server/cost-writer.ts +
# server/observability.ts: events carry `feature=byok-delegations`, `op=<...>`,
# and `art_33_breach=true` on the cross-tenant path (wired in this PR's #4364
# Goal 0a). Schema attribute names verified via `terraform providers schema
# -json` against jianyuan/sentry 0.15.0-beta2 (Phase 0).

# Rule 1 — GDPR Art. 33 breach (cross-tenant BYOK key leak). Highest urgency:
# tight frequency + notify ActiveMembers fallthrough. Filters require BOTH
# feature=byok-delegations AND art_33_breach=true (filter_match = "all").
resource "sentry_issue_alert" "byok_art_33_breach" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "byok-art-33-breach"
  # action_match MUST be "any" (#4656 item 1): the 3 conditions below are
  # mutually-exclusive event-lifecycle states (a captured event is exactly one
  # of new / reappeared / regressed). "all" would require all three on one
  # event — never satisfiable. Schema-grounded against jianyuan/sentry
  # 0.15.0-beta2 (`action_match` description: "…any or all of the specified
  # conditions happen"). NOTE: this is the only rule in this file using "any" —
  # the 4 auth rules + byok_cap_exceeded use "all" with a single condition.
  action_match = "any"
  filter_match = "all"
  frequency    = 5

  # #4656 item 1 — recurrence firing. `first_seen_event` alone pages ONCE per
  # Sentry issue fingerprint: a repeat cross-tenant breach (same fingerprint)
  # folds into the open issue and never re-pages, and a breach recurring after
  # the founder resolves the issue also never re-pages — so the Art. 33 72h
  # clock for the recurrence never starts. Adding `reappeared_event`
  # (issue reopened after resolve) + `regression_event` (issue regressed)
  # re-pages on recurrence. Attribute names verified via
  # `terraform providers schema -json` (beta2): condition types include
  # first_seen_event, reappeared_event, regression_event.
  #
  # Interaction with the app-side dedup: the emit path (`mirrorP0Deduped`,
  # observability.ts) suppresses re-fires for the same
  # `grantorUserId:op:conversationId` for 1h (P0_DEDUP_TTL_MS). So
  # reappeared/regression here re-page a recurrence on the SAME conversation
  # only after that 1h window lapses; a recurrence in a DIFFERENT conversation
  # is a fresh dedup key and re-pages immediately. The first occurrence always
  # pages and stamps `first_seen_at`, so the Art. 33(1) 72h clock starts on
  # first detection regardless — the 1h floor only bounds *re-paging* of an
  # already-detected same-conversation incident, which is immaterial to the
  # 72h window.
  conditions_v2 = [
    { first_seen_event = {} },
    { reappeared_event = {} },
    { regression_event = {} },
  ]
  filters_v2 = [
    {
      tagged_event = {
        key   = "feature"
        match = "EQUAL"
        value = "byok-delegations"
      }
    },
    {
      tagged_event = {
        key   = "art_33_breach"
        match = "EQUAL"
        value = "true"
      }
    },
  ]
  # ACCEPTED RISK (N=1) — recipient pinning deferred, tracked in #4656.
  # `IssueOwners` has no ownership rule on this project, so it falls through
  # to `ActiveMembers`. With a solo founder (the only active Sentry member
  # today) that correctly pages the one person who must start the Art. 33
  # 72h clock. BUT this event class carries cross-tenant-leak metadata, so
  # at N>1 active members the fallthrough would over-disclose to every seat.
  # MUST be revisited — pin `target_type = "Member"` + the founder's member
  # id (or a single-member ops Team) — BEFORE the first non-founder Sentry
  # seat is added. user-impact-reviewer P1 (single-user-incident threshold).
  # The 4 auth rules above use the same IssueOwners/ActiveMembers pattern;
  # this is the repo convention, not a new risk introduced here.
  actions_v2 = [
    {
      notify_email = {
        target_type      = "IssueOwners"
        fallthrough_type = "ActiveMembers"
      }
    },
  ]

  lifecycle {
    ignore_changes = [environment]
  }
}

# Rule 2 — BYOK delegation cap exceeded (hourly | daily). Lower urgency:
# wider frequency + quieter `NoOne` fallthrough. Filters require
# feature=byok-delegations AND op ∈ {hourly-cap-exceeded, daily-cap-exceeded}
# via a single `in` match (comma-separated; `in` confirmed in beta2 schema).
resource "sentry_issue_alert" "byok_cap_exceeded" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "byok-cap-exceeded"
  action_match = "all"
  filter_match = "all"
  frequency    = 15

  conditions_v2 = [
    { first_seen_event = {} },
  ]
  filters_v2 = [
    {
      tagged_event = {
        key   = "feature"
        match = "EQUAL"
        value = "byok-delegations"
      }
    },
    {
      tagged_event = {
        key   = "op"
        match = "IS_IN"
        value = "hourly-cap-exceeded,daily-cap-exceeded"
      }
    },
  ]
  actions_v2 = [
    {
      notify_email = {
        target_type      = "IssueOwners"
        fallthrough_type = "NoOne"
      }
    },
  ]

  lifecycle {
    ignore_changes = [environment]
  }
}
