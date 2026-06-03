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

# ── Chat write-absence liveness alert (#4849) — APPLY-CREATED, NOT import-only ─
# Pages on any interactive-message INSERT failure in `dispatchSoleurGo`. All
# three insert-blocking ops throw AND carry `feature=cc-dispatcher`
# (cc-dispatcher.ts:1457 tenant-mint, :1477 workspaceRead, :1502 the INSERT) —
# scoping to only the INSERT slug would leave the two sibling failure paths
# (identical user-visible outage: "message didn't save") unpaged, the
# single-user-incident window this alert exists to close. The signal already
# exists (reportSilentFallback → captureException); no app change needed. The
# 3-week chat-RLS outage (#4831/#4848) hit the :1502 INSERT — this catches that
# class and its two siblings. Cross-artifact op/feature contract pinned by
# test/sentry-chat-alert-op-contract.test.ts.
#
# `action_match="any"`: first_seen/reappeared/regression are mutually-exclusive
# event-lifecycle states (a captured event is exactly one) — "all" is never
# satisfiable. reappeared+regression re-page a recurrence after the founder
# resolves the Sentry issue. This path uses plain `reportSilentFallback` (no
# `mirrorP0Deduped` TTL), so every failed save emits — re-paging relies on
# Sentry's own issue-fingerprint folding, which the 3 lifecycle conditions
# handle. Distinct `frequency=10` avoids Sentry POST-time exact-duplicate dedup
# (taken: 5,15,30,60,61,62). `IS_IN` proven in beta2 at byok_cap_exceeded above.
resource "sentry_issue_alert" "chat_message_save_failure" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "chat-message-save-failure"
  action_match = "any"
  filter_match = "all"
  frequency    = 10

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
        value = "cc-dispatcher"
      }
    },
    {
      tagged_event = {
        key   = "op"
        match = "IS_IN"
        value = "tenant-mint.persistUserMessage,persistUserMessage.workspaceRead,persist-user-message"
      }
    },
  ]
  # N=1 accepted risk (mirrors byok_art_33_breach:259-269): IssueOwners has no
  # ownership rule on this project → falls through to ActiveMembers, correctly
  # paging the solo founder. Unlike byok_art_33, this event carries NO
  # cross-tenant content (only op + pg_code tags) so the fallthrough does not
  # over-disclose. Revisit recipient pinning (target_type="Member") before the
  # first non-founder Sentry seat.
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

# server/inngest/functions/cron-workspace-sync-health.ts: a daily probe that
# emits `feature=workspace-sync-health` events via reportSilentFallback for both
# user-actionable findings (op ∈ {ready-null-installation, stale-sync-failed,
# went-quiet}) AND probe-self-failures (op ∈ {scan, scan-stale, scan-went-quiet,
# went-quiet-probe}). Detection (#4712/#4717) shipped the probe; this rule
# (#4882) is the missing NOTIFICATION layer — without it the events sit in
# Sentry un-notified (hr-no-dashboard-eyeball-pull-data-yourself), so the
# KB-sync-stale PIR (#4878) failure mode (user reports a missing KB file before
# the operator knows) recurs.
#
# feature-ONLY filter (no `op` IS_IN): unlike chat_message_save_failure (whose
# `cc-dispatcher` feature spans many unrelated ops, forcing op-scoping), this
# feature tag is dedicated to one cron and EVERY event is operator-actionable.
# Op-scoping here would silently drop the probe-self-failure ops — and arms 2/3
# swallow their own scan errors (return {reported:0}/{wentQuiet:0}) while the
# heartbeat keys only on arm 1, so the probe-failure op is the ONLY signal that
# the detector itself broke. Feature-only also future-proofs against new arms.
#
# `action_match="any"` + first_seen/reappeared/regression lifecycle conditions
# (NOT a per-event condition): Sentry folds repeated daily fires of the same
# workspace into one issue by fingerprint and re-pages only on regression after
# the operator resolves it — this is the anti-fatigue mechanism, so a transient
# `ok:false` does not train the operator to mute the channel. Distinct
# `frequency=11` avoids Sentry POST-time exact-duplicate dedup (taken by
# siblings: 5,10,15,30,60,61,62); not evaluated by lifecycle-condition rules but
# must be unique. Cross-artifact feature contract pinned by
# test/sentry-workspace-sync-health-alert-op-contract.test.ts.
resource "sentry_issue_alert" "workspace_sync_health" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "workspace-sync-health"
  action_match = "any"
  filter_match = "all"
  frequency    = 11

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
        value = "workspace-sync-health"
      }
    },
  ]
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

# ── KB tenant-mint silent-fallback alert (#4918) — APPLY-CREATED, NOT import ──
# Pages on the first occurrence of any KB tenant-JWT mint failure. PIR #4913
# (generate-link-tenant-mint-regression-postmortem.md) found the durability gap
# the #4913 service-role fallback did NOT close: the mint failure emitted a
# `reportSilentFallback` Sentry signal on EVERY tenant-mint dead-end, yet no
# alert routed it to attention, so it sat latent ~19 days until the founder hit
# the dead Generate-link button while dogfooding. This rule is the missing
# NOTIFICATION layer (hr-no-dashboard-eyeball-pull-data-yourself) — the signal
# already exists (RuntimeAuthError → captureException with feature/op tags); no
# app change needed.
#
# op-SCOPED filter (op IS_IN, NOT feature-only): unlike workspace_sync_health
# (whose feature tag is dedicated to one cron), `feature=kb-route-helpers` spans
# 6 ops — the 3 tenant-mint slugs PLUS workspace-sync-*, self-heal-*, and
# kb-sync.unexpected. A feature-only filter would over-page on those unrelated
# self-heal/workspace-sync events. So this mirrors chat_message_save_failure's
# op-scoped shape. The THIRD slug `kb-sync.tenant-mint` (sync/route.ts:62) is
# the identical RuntimeAuthError→503 mint-failure class the issue body omitted;
# at brand-survival threshold `single-user incident`, scoping out the next-most-
# likely sibling is anti-pattern, so it is folded into the IS_IN value.
#
# `action_match="any"`: first_seen/reappeared/regression are mutually-exclusive
# event-lifecycle states (a captured event is exactly one) — "all" is never
# satisfiable. reappeared+regression re-page a recurrence after the founder
# resolves the Sentry issue — the issue-alert equivalent of the issue text's
# `failure_issue_threshold = 1` (which is a cron/uptime-monitor attribute, NOT
# valid on sentry_issue_alert). Distinct `frequency=12` avoids Sentry POST-time
# exact-duplicate dedup (taken: 5,10,11,15,30,60,61,62; keyed on action-shape +
# frequency + match, NOT conditions — not evaluated by lifecycle-condition rules
# but must be unique). `IS_IN` proven in beta2 at byok_cap_exceeded above.
# Cross-artifact op/feature contract pinned by
# test/sentry-kb-tenant-mint-alert-op-contract.test.ts.
resource "sentry_issue_alert" "kb_tenant_mint_silent_fallback" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "kb-tenant-mint-silent-fallback"
  action_match = "any"
  filter_match = "all"
  frequency    = 12

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
        value = "kb-route-helpers"
      }
    },
    {
      tagged_event = {
        key   = "op"
        match = "IS_IN"
        value = "resolveUserKbRoot.tenant-mint,authenticateAndResolveKbPath.tenant-mint,kb-sync.tenant-mint"
      }
    },
  ]
  # N=1 accepted risk (mirrors chat_message_save_failure:378-383): IssueOwners
  # has no ownership rule on this project → falls through to ActiveMembers,
  # correctly paging the solo founder. These events carry NO cross-tenant
  # content (only hashed userId + op + pg_code tags) so the fallthrough does not
  # over-disclose. Revisit recipient pinning (target_type="Member") before the
  # first non-founder Sentry seat.
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
