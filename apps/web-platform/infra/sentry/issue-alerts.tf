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

# ── KB db-error alert (#4929) — APPLY-CREATED, NOT import ──────────────────
# Pages on the first occurrence of any KB share db-error event — the "breaks
# every insert" class: the 23502 NOT-NULL constraint that caused PIR #4913 (the
# missing `workspace_id` on NOT-NULL inserts dead-ended every "Generate link"
# create), and the 42501 RLS class that caused the 3-week chat-save outage
# (#4831). The signal already exists: `createShare`'s db-error path
# (kb-share.ts:340) calls `reportSilentFallback(feature:"kb-share", op:"create")`
# — `create` is the 23502 insert path — and the sibling list/revoke/preview ops
# emit the same `feature:"kb-share"` family. This rule is the missing
# NOTIFICATION layer (hr-no-dashboard-eyeball-pull-data-yourself): without it a
# constraint that breaks every insert sits latent for weeks (PIR #4913 sat ~19
# days) instead of paging on first occurrence. No app change needed.
#
# op-SCOPED filter (op IS_IN, NOT feature-only): mirrors
# kb_sync_silent_failure / chat_message_save_failure. The `kb-share`
# feature tag spans MORE than these 5 ops — sibling files emit feature="kb-share"
# for non-db ops too (cf-cache-purge.ts `revoke-purge`; kb-preview-metadata.ts
# `preview-pdf-*`/`preview-image-*`; agent-runner.ts `baseUrl`). This rule is
# DELIBERATELY scoped to the db-error subset that originates in kb-share.ts
# (create/list/revoke/preview/preview-invariant — query/insert/update failures;
# `create` is the 23502 path) so a CDN-purge or PDF-parse failure does not page
# the founder. A new db-error op added to kb-share.ts MUST be added to BOTH this
# IS_IN value AND the op-contract test (the test's reverse-guard fails closed on
# any unlisted kb-share.ts op).
#
# `action_match="any"`: first_seen/reappeared/regression are mutually-exclusive
# event-lifecycle states (a captured event is exactly one) — "all" is never
# satisfiable. reappeared+regression re-page a recurrence after the founder
# resolves the Sentry issue. Distinct `frequency=13` avoids Sentry POST-time
# exact-duplicate dedup (taken: 5,10,11,12,15,30,60,61,62; keyed on action-shape
# + frequency + match, NOT conditions — not evaluated by lifecycle-condition
# rules but must be unique). `IS_IN` proven in beta2 at byok_cap_exceeded above.
# Cross-artifact op/feature contract pinned by
# test/sentry-kb-db-error-alert-op-contract.test.ts.
resource "sentry_issue_alert" "kb_db_error" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "kb-db-error"
  action_match = "any"
  filter_match = "all"
  frequency    = 13

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
        value = "kb-share"
      }
    },
    {
      tagged_event = {
        key   = "op"
        match = "IS_IN"
        value = "create,list,revoke,preview,preview-invariant"
      }
    },
  ]
  # N=1 accepted risk (mirrors the kb_sync_silent_failure block):
  # IssueOwners has no ownership rule on this project → falls through to
  # ActiveMembers, correctly paging the solo founder. These events carry only
  # hashed userId + op + documentPath + pg_code tags — no cross-tenant content —
  # so the fallthrough does not over-disclose. Revisit recipient pinning
  # (target_type="Member") before the first non-founder Sentry seat.
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

# ── KB sync silent-failure alert (#4918, re-pointed #5005) — APPLY-CREATED ─────
# Pages on the first occurrence of an unexpected (uncaught) failure on the
# manual KB-sync path. PIR #4913 (generate-link-tenant-mint-regression-
# postmortem.md) found the durability gap that motivated this rule: a silent
# failure on a KB route emitted a `reportSilentFallback` Sentry signal on every
# dead-end, yet no alert routed it to attention, so it sat latent ~19 days until
# the founder hit the dead button while dogfooding. This rule is the missing
# NOTIFICATION layer (hr-no-dashboard-eyeball-pull-data-yourself) — the signal
# already exists (captureException with feature/op tags); no app change needed.
#
# #5005 re-point: kb/sync converged off the per-user tenant client onto the
# ADR-044 service-role resolvers (resolveActiveWorkspaceKbRoot +
# resolveActiveWorkspaceRepoMeta), removing the LAST `kb-sync.tenant-mint` emit
# site (the prior surviving slug after #4953/#4956 migrated the other KB
# routes). The tenant-mint failure CLASS no longer exists on any KB route, so
# pinning the alert to that slug would dark it. The route's surviving
# silent-failure surface is its top-level catch, which mirrors under
# `feature=kb-route-helpers`, `op=kb-sync.unexpected` (sync/route.ts) — the same
# "a kb/sync request 500'd and the user saw a dead Sync button" class the alert
# exists to catch. The IS_IN filter is re-pointed there. (The resolver's own
# query errors mirror separately under `feature=workspace-resolver`.)
#
# op-SCOPED filter (op IS_IN, NOT feature-only): `feature=kb-route-helpers`
# spans several ops beyond the unexpected-failure catch — workspace-sync-*,
# 3x self-heal-*, etc. A feature-only filter would over-page on those routine
# self-heal/workspace-sync events. So this mirrors chat_message_save_failure's
# op-scoped shape.
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
# test/sentry-kb-sync-silent-failure-alert-op-contract.test.ts.
resource "sentry_issue_alert" "kb_sync_silent_failure" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "kb-sync-silent-failure"
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
        value = "kb-sync.unexpected"
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

# #5046 PR-2 (AC-P2.10) — container egress firewall fail-loud alert. The
# nftables default-drop logs to the kernel journal; cron-egress-resolve.sh
# counts fresh `egress-blocked:` hits each 5-min tick and posts ONE error
# event tagged feature=cron-egress-firewall / op=egress_blocked. A block of
# a NEEDED host (allowlist gap / frozen set) must page — silent egress loss
# is the exact silent-green failure the umbrella issue exists to prevent.
# Modeled on kb_sync_silent_failure; unique frequency (30) so this alert's
# re-notification cadence is distinguishable in Sentry's alert list.
resource "sentry_issue_alert" "egress_blocked" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "cron-egress-blocked"
  action_match = "any"
  filter_match = "all"
  frequency    = 30

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
        value = "cron-egress-firewall"
      }
    },
    {
      tagged_event = {
        key   = "op"
        match = "IS_IN"
        value = "egress_blocked"
      }
    },
  ]
  # N=1 accepted risk (mirrors kb_sync_silent_failure): IssueOwners falls
  # through to ActiveMembers, paging the solo founder. Events carry only
  # kernel packet metadata (IPs/ports) — no cross-tenant content.
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

# container-restart-monitor.sh (#5417): the host systemd-timer detector posts a
# Sentry error EVENT tagged feature=container-restart-monitor when the
# soleur-web-platform container's restart rate breaches RESTART_THRESHOLD
# (op=restart_storm) or a freshly-deployed container is already crash-looping
# (op=fresh_crash_loop). This rule is the no-SSH NOTIFICATION layer
# (hr-no-dashboard-eyeball-pull-data-yourself) for the restart-churn root cause:
# the monitor reads docker inspect RestartCount + the cgroup memory.events
# oom_kill counter directly on the host (authoritative — catches the cgroup-v2
# child-cgroup OOM that .State.OOMKilled and the "Server startup" event-frequency
# both miss), so paging on its event is the host-authoritative restart-rate
# signal. The monitor does the rate thresholding host-side, so a first-seen page
# is correct (no event_frequency condition needed — and beta2's conditions_v2
# has no verified event_frequency support; see ADR-062).
#
# op-SCOPED filter (op IS_IN, NOT feature-only): the monitor also emits
# op=recovered (a "storm cleared" event) under the SAME feature tag; scoping to
# {restart_storm, fresh_crash_loop} keeps the recovery note from paging as an
# incident. Mirrors chat_message_save_failure / kb_db_error op-scoping. A new
# alertable monitor op MUST be added to BOTH this IS_IN value AND the op-contract
# test (test/sentry-container-restart-alert-op-contract.test.ts).
#
# `action_match="any"` + first_seen/reappeared/regression: lifecycle states are
# mutually exclusive (a captured event is exactly one) so "all" is never
# satisfiable; reappeared+regression re-page a recurrence after the founder
# resolves the Sentry issue. Distinct `frequency=17` avoids Sentry POST-time
# exact-duplicate dedup (taken: 5,10,11,12,13,14,15,16,30,60,61,62; keyed on
# action_match+filter_match+frequency+actions-shape, NOT conditions). Events
# carry only container id / counts / exit code — no user content.
resource "sentry_issue_alert" "container_restart_burst" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "container-restart-burst"
  action_match = "any"
  filter_match = "all"
  frequency    = 17

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
        value = "container-restart-monitor"
      }
    },
    {
      tagged_event = {
        key   = "op"
        match = "IS_IN"
        value = "restart_storm,fresh_crash_loop"
      }
    },
  ]
  # N=1 accepted risk (mirrors kb_sync_silent_failure / egress_blocked):
  # IssueOwners has no ownership rule on this project → falls through to
  # ActiveMembers, paging the solo founder. Events carry only container id +
  # restart counts + exit code — no cross-tenant content.
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

# ── KB-sync protected-branch fallback failure (#5426) — APPLY-CREATED ───────
# server/session-sync.ts `syncPush`: when the user's default branch is
# protected, the post-session KB commit can't be pushed onto it, so the fallback
# accretes the latest KB tree onto a durable `soleur/kb-sync` side branch and
# opens/updates a PR. The fallback is ORDERED so the local default is reset only
# AFTER the side-branch push + PR succeed — on any failure the un-pushed commit
# stays on default for next-session retry, and `op=kb-sync.protected-fallback-
# failed` is emitted (covers side-branch push reject / Octokit error /
# persistent_other like `shallow update not allowed`). This rule is the
# NOTIFICATION layer (hr-no-dashboard-eyeball-pull-data-yourself): without it a
# user whose KB writes silently fail to deliver (the divergence-treadmill class
# #5426 fixes) goes unnoticed. The signal already exists (reportSilentFallback →
# captureException with feature/op tags); no app change beyond the emit.
#
# op-SCOPED filter (op IS_IN, NOT feature-only): `feature=session-sync` spans
# many routine ops (syncPull, syncPush, recordKbSyncHistory, appendKbSyncRow,
# auth-probe.*, AND the warn-level success entry op kb-sync.push-protected-
# fallback). A feature-only filter would over-page on every transient sync blip.
# Scoped to the single FAILURE op so only an undelivered-writes incident pages;
# the success entry op (kb-sync.push-protected-fallback) is warn-level and
# deliberately excluded. Mirrors kb_sync_silent_failure / chat_message_save_failure.
#
# `action_match="any"` + first_seen/reappeared/regression: lifecycle states are
# mutually exclusive (a captured event is exactly one) so "all" is never
# satisfiable; reappeared+regression re-page a recurrence after the founder
# resolves the Sentry issue. Distinct `frequency=18` avoids Sentry POST-time
# exact-duplicate dedup (taken: 5,10,11,12,13,14,15,16,17,30,60,61,62; 18 free
# 2026-06-16 — 17 taken by container_restart_burst #5417) — dedup keys on
# action_match+filter_match+frequency+actions-shape, NOT conditions. `IS_IN`
# proven in beta2 at byok_cap_exceeded above. Cross-artifact op/feature contract
# pinned by test/sentry-kb-sync-protected-fallback-alert-op-contract.test.ts.
resource "sentry_issue_alert" "kb_sync_protected_fallback_failed" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "kb-sync-protected-fallback-failed"
  action_match = "any"
  filter_match = "all"
  frequency    = 18

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
        value = "session-sync"
      }
    },
    {
      tagged_event = {
        key   = "op"
        match = "IS_IN"
        value = "kb-sync.protected-fallback-failed"
      }
    },
  ]
  # N=1 accepted risk (mirrors kb_sync_silent_failure): IssueOwners has no
  # ownership rule on this project → falls through to ActiveMembers, correctly
  # paging the solo founder. These events carry only hashed userId + op tags —
  # no cross-tenant content — so the fallthrough does not over-disclose. Revisit
  # recipient pinning (target_type="Member") before the first non-founder seat.
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

# server/inngest/functions/cron-cloud-task-heartbeat.ts: the stale-bot-PR
# watchdog (#5138) emits `feature=cron-cloud-task-heartbeat` events for three
# ops — `stale-bot-pr` (warnSilentFallback, a ci/* PR open >48h: auto-merge
# silently disarmed on conflict, or a `direct` pipeline that fell back and
# stalled — ADR-054) plus two detector SELF-failure ops (`stale-bot-pr-scan-
# failed`, `stale-bot-pr-comment-failed`, reportSilentFallback). This rule is
# the NOTIFICATION layer (hr-no-dashboard-eyeball-pull-data-yourself): the warn
# is search-only without it, AND the scan deliberately does NOT flip the
# heartbeat monitor (found-work ≠ liveness), so a daily-failing scan would
# silently stop the watchdog — exactly the silent-stale gap #5138 closes.
#
# op IS_IN (NOT feature-only): `feature=cron-cloud-task-heartbeat` is SHARED —
# the same function also emits `task-pending-first-run`, `check-task`,
# `issue-handling` for the unrelated cloud-task-silence check, which must NOT
# page here. Scoping to the three watchdog ops routes only this concern.
# Routing the self-failure ops (not just `stale-bot-pr`) is load-bearing: the
# watchdog is the only detector for these stuck PRs, so its OWN blindness must
# page. `action_match="any"` + first_seen/reappeared/regression: lifecycle
# states are mutually exclusive ("all" never satisfiable) and re-page a
# recurrence after the operator resolves the issue. Distinct frequency (14)
# avoids Sentry POST-time exact-duplicate dedup (taken: 5,10,11,12,13,15,30,60,
# 61,62; verified free 2026-06-12) — dedup keys on action_match+filter_match+
# frequency+actions-shape, NOT conditions. A new watchdog op MUST be added to
# this IS_IN value. Events carry only PR number/head/age — no user content.
resource "sentry_issue_alert" "stale_bot_pr" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "stale-bot-pr"
  action_match = "any"
  filter_match = "all"
  frequency    = 14

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
        value = "cron-cloud-task-heartbeat"
      }
    },
    {
      tagged_event = {
        key   = "op"
        match = "IS_IN"
        value = "stale-bot-pr,stale-bot-pr-scan-failed,stale-bot-pr-comment-failed"
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

# server/email-triage/outbound.ts: agent-native cold-outbound email (#5325).
# Pages on ANY failure in `sendCompliantOutbound`. The four emit sites all call
# reportSilentFallback with `feature=outbound-email`:
#   - outbound.suppression_check — suppression-lookup DB error (fail-closed: the
#     send is BLOCKED, so a recurring failure silently halts all outbound).
#   - outbound.dedup_check       — dedup-lookup DB error (also fail-closed).
#   - outbound.send_error        — Resend API send failure (the email never went).
#   - outbound.record_error      — record_outbound_send failed AFTER a successful
#     send: the email WENT OUT but the WORM `outbound_sends` audit row is missing.
#     This is a GDPR Art. 30 accountability gap (an un-logged send), so it must
#     page even though the user-visible send "succeeded".
# Detection already exists (reportSilentFallback → captureException); this is the
# missing NOTIFICATION layer (hr-no-dashboard-eyeball-pull-data-yourself).
#
# feature-ONLY filter (no `op` IS_IN): `feature=outbound-email` is dedicated to
# outbound.ts and EVERY emit site is an operator-actionable failure (all four are
# reportSilentFallback — there is NO routine info/warn emit under this feature;
# pinned by test/sentry-outbound-email-alert-op-contract.test.ts, which fails
# closed if a non-error emit is ever added). Mirrors workspace_sync_health's
# feature-only rationale and future-proofs new failure ops. A NEW non-error emit
# under feature=outbound-email would over-page — the contract test guards that.
#
# `action_match="any"` + first_seen/reappeared/regression: lifecycle states are
# mutually exclusive (a captured event is exactly one) so "all" is never
# satisfiable; reappeared+regression re-page a recurrence after the founder
# resolves the Sentry issue. Distinct `frequency=16` avoids Sentry POST-time
# exact-duplicate dedup (taken: 5,10,11,12,13,14,15,30,60,61,62; 16 free
# 2026-06-15) — dedup keys on action_match+filter_match+frequency+actions-shape,
# NOT conditions.
resource "sentry_issue_alert" "outbound_email_send_failure" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "outbound-email-send-failure"
  action_match = "any"
  filter_match = "all"
  frequency    = 16

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
        value = "outbound-email"
      }
    },
  ]
  # N=1 accepted risk (mirrors kb_sync_silent_failure / chat_message_save_failure):
  # IssueOwners has no ownership rule on this project → falls through to
  # ActiveMembers, paging the active founder + the ops@soleur.ai seat (added for
  # this feature). The events carry only a recipient HASH (keyed HMAC), op, and
  # pg_code/Resend-error tags — NO plaintext recipient or body — so the
  # fallthrough does not over-disclose. Revisit recipient pinning
  # (target_type="Member") before the first non-ops Sentry seat.
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
