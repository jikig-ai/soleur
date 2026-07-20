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
# and intentionally accepted: the stable line has now shipped (pinned v0.15.4,
# #6636) but the migration blocker persists (see below), so the deferral stands.
# Do NOT migrate these to `sentry_alert` under the pinned v0.15.4:
#   - stable `sentry_alert` (re-confirmed at v0.15.4) is MONITOR-bound: `monitor_ids` (set) and
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
# Re-attempt when a future `sentry_alert` release lets a project-wide
# frequency alert bind + fire faithfully — i.e. when the `sentry_project_error_monitor`
# / `sentry_project_issue_stream_monitor` default-monitor data sources are
# confirmed to satisfy the `monitor_ids` requirement (stable v0.15.x, incl. the
# pinned v0.15.4, still requires it — #6636). Schema evidence + alternatives:
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
#   - the apply workflow plans the FULL ROOT (#6589), so declaring these rules
#     here applies them — there is no `-target=` list to also update. The 4
#     import-only auth rules are safe under that widening for a different reason
#     than before: they are not excluded by OMISSION from an allow-list any more,
#     they plan as no-op because their v2 attributes are under `ignore_changes`
#     (a live full-root plan on 2026-07-17 confirmed all 22 declared alerts
#     no-op). That assumption now carries 22 resources where it once carried 2,
#     which is why it is an explicit AC assertion rather than a comment.
# Tag vocabulary verified against apps/web-platform/server/cost-writer.ts +
# server/observability.ts: events carry `feature=byok-delegations`, `op=<...>`,
# and `art_33_breach=true` on the cross-tenant path (wired in this PR's #4364
# Goal 0a). Schema attribute names verified via `terraform providers schema
# -json` against jianyuan/sentry 0.15.4 (#6636 Phase 0 re-verified no drift; originally beta2).

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
  # 0.15.4 (`action_match` description: "…any or all of the specified
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

# server/repo-resolver-divergence.ts: emits `feature=repo-resolver-divergence`
# breadcrumbs via reportSilentFallback for the dual-resolver divergence class
# (ADR-044). The divergence file shipped the QUERYABLE signal but called the
# NOTIFICATION rule a fast-follow — this rule is that fast-follow. The
# dispatch-time op `connected-null-install-at-dispatch` (added this PR) is the
# member cold-dispatch into a genuinely-connected workspace whose credential
# read `resolve_workspace_installation_id` returned NULL — previously a SILENT
# repo-less agent spawn (the "no git repository" Concierge incident). Without
# this rule the events sit in Sentry un-notified
# (hr-no-dashboard-eyeball-pull-data-yourself).
#
# feature-ONLY filter (no `op` IS_IN): the `repo-resolver-divergence` feature tag
# is dedicated and EVERY op (non-member-claim-reset / self-heal-failed /
# connected-null-install-at-dispatch) is operator-actionable. Op-scoping would
# risk silently darking a future op (the failure mode test/sentry-repo-resolver
# -divergence-alert-op-contract.test.ts pins against). Feature-only future-proofs
# new ops.
#
# `action_match="any"` + first_seen/reappeared/regression lifecycle conditions:
# Sentry folds repeated fires of the same fingerprint into one issue and re-pages
# only on regression after the operator resolves it (anti-fatigue). Distinct
# `frequency=20` avoids Sentry POST-time exact-duplicate dedup (taken by
# siblings: 5,10,11,12,13,14,15,16,17,18,19,30,60,61,62); not evaluated by
# lifecycle-condition rules but must be unique.
resource "sentry_issue_alert" "repo_resolver_divergence" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "repo-resolver-divergence"
  action_match = "any"
  filter_match = "all"
  frequency    = 20

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
        value = "repo-resolver-divergence"
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

# ── GitHub-webhook founder-ambiguous alert (#5437) — APPLY-CREATED ────────────
# ADR-044 R8 asserts the founder-ambiguous standing-state MUST PAGE. The
# non-push webhook resolver (server/resolve-founder-for-installation.ts) now
# reads the NON-UNIQUE `workspaces.github_installation_id` (the mig-052 UNIQUE
# was dropped), so >1 solo workspaces sharing one installation is genuinely
# reachable. The route (app/api/webhooks/github/route.ts, `op=founder-ambiguous`
# branch) FAILS CLOSED: it drops the event with a 404 (GitHub does not retry
# 4xx) and never picks a founder — strictly safer than misattributing an
# action/installation-token to the WRONG founder (the brand-survival hazard).
# But the drop is a STANDING state: every subsequent webhook for that install
# also drops until the duplicate solo row is removed, and the HTTP monitor
# treats 404 as expected. This rule is the missing NOTIFICATION layer
# (hr-no-dashboard-eyeball-pull-data-yourself) — the `Sentry.captureException`
# already fires with `feature=github-webhook` + `op=founder-ambiguous` tags; no
# app change needed.
#
# 2-tag AND filter (`filter_match="all"`, feature + op tagged_event) — mirrors
# chat_message_save_failure's shape. Scoped to `op=founder-ambiguous` (NOT
# feature-only): the `github-webhook` feature tag also carries the routine
# no-founder 404 (`op` absent), the inngest-send-push failure
# (`op=inngest-send-push`), and the db-error mirror (`op=founder-resolve`,
# already paged by the workspace-resolver family). A feature-only filter would
# over-page on the expected no-founder 404. This rule fires ONLY on the
# standing-state ambiguity.
#
# `action_match="any"`: first_seen/reappeared/regression are mutually-exclusive
# event-lifecycle states (a captured event is exactly one) — "all" is never
# satisfiable. reappeared+regression re-page a recurrence after the founder
# resolves the Sentry issue (e.g. removes the duplicate solo row, then a later
# install drift re-introduces it). Distinct `frequency=19` avoids Sentry
# POST-time exact-duplicate dedup (taken: 5,10,11,12,13,14,15,16,17,18,30,60,61,
# 62; keyed on action-shape + frequency + match — must be unique).
resource "sentry_issue_alert" "github_webhook_founder_ambiguous" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "github-webhook-founder-ambiguous"
  action_match = "any"
  filter_match = "all"
  frequency    = 19

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
        value = "github-webhook"
      }
    },
    {
      tagged_event = {
        key   = "op"
        match = "EQUAL"
        value = "founder-ambiguous"
      }
    },
  ]
  # N=1 accepted risk (mirrors chat_message_save_failure): IssueOwners has no
  # ownership rule on this project → falls through to ActiveMembers, paging the
  # active founder. The event carries only installationId + deliveryId + count
  # tags/extra — NO cross-tenant content — so the fallthrough does not
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
# is correct (no event_frequency condition needed here). NB: beta2's conditions_v2
# DOES expose event_frequency — schema-verified in #6278 (first used by
# zot_mirror_fallback_rate at the bottom of this file); the earlier "no verified
# support" claim (and ADR-062:120) was stale ("no in-repo precedent" was the only
# true part, and it no longer holds).
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

# ── Disk-IO WAL-concentration alert (#5736) — APPLY-CREATED, NOT import-only ────
# server/inngest/functions/cron-supabase-disk-io.ts: the 6-hourly disk-IO monitor
# now reads the per-statement WAL signal (migration 114: top_wal_statements +
# max_wal_pct from extensions.pg_stat_statements) and emits ONE Sentry capture
# tagged feature=cron-supabase-disk-io / op=wal-concentration when a single
# statement's share of total WAL exceeds WAL_CONCENTRATION_PCT_CEIL (40). This is
# the continuous backstop for the #5736 class — a webhook dedup INSERT that was
# 63% of prod WAL yet shipped through review + green CI because no lens checked
# write frequency × per-write WAL. This rule is the NOTIFICATION layer
# (hr-no-dashboard-eyeball-pull-data-yourself): without it the capture sits in
# Sentry un-paged. The signal already exists (reportSilentFallback →
# captureException); no app change beyond the emit.
#
# 2-tag AND filter (`filter_match="all"`, feature + op tagged_event) — mirrors
# github_webhook_founder_ambiguous's EQUAL/EQUAL shape. Scoped to
# `op=wal-concentration` (NOT feature-only): `feature=cron-supabase-disk-io` also
# carries the read-signal failure op (`op=read-signal`) which is paged via the
# cron's own heartbeat monitor (scheduled-supabase-disk-io); a feature-only
# filter here would double-page that. This rule fires ONLY on WAL concentration.
#
# `action_match="any"`: first_seen/reappeared/regression are mutually-exclusive
# event-lifecycle states (a captured event is exactly one) — "all" is never
# satisfiable. reappeared+regression re-page a recurrence after the founder
# resolves the Sentry issue (e.g. fixes the dominating statement, then a later
# regression re-introduces it). Distinct `frequency=21` avoids Sentry POST-time
# exact-duplicate dedup (taken: 5,10,11,12,13,14,15,16,17,18,19,20,30,60,61,62;
# keyed on action_match+filter_match+frequency+actions-shape, NOT conditions —
# must be unique). Cross-artifact op/feature contract pinned by
# test/sentry-disk-io-wal-concentration-alert-op-contract.test.ts.
resource "sentry_issue_alert" "disk_io_wal_concentration" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "disk-io-wal-concentration"
  action_match = "any"
  filter_match = "all"
  frequency    = 21

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
        value = "cron-supabase-disk-io"
      }
    },
    {
      tagged_event = {
        key   = "op"
        match = "EQUAL"
        value = "wal-concentration"
      }
    },
  ]
  # N=1 accepted risk (mirrors kb_sync_silent_failure): IssueOwners has no
  # ownership rule on this project → falls through to ActiveMembers, paging the
  # solo founder. The event carries only the normalized (literal-stripped) query
  # text + WAL percentages — no row values / cross-tenant content — so the
  # fallthrough does not over-disclose. Revisit recipient pinning
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

# ── Sandbox-startup failure alert (#5875 / ADR-079) — APPLY-CREATED ──────────
# Pages when the agent-sandbox startup path fails for ≥K DISTINCT tenants in a
# rolling window. The 2026-07-01 P0 (#5873 — a seccomp EPERM on the SDK's split
# unshare() after bump #5849) produced ZERO server-side signal: the catch sites
# tagged only the SDK's missing-binary preflight substring, so the EPERM fell
# through to a bare untagged captureException. PR1 tags EVERY sandbox-startup
# failure (missing_binary + the #5873 seccomp/userns denial) with
# feature="agent-sandbox", op="sdk-startup" via reportSilentFallback
# (agent-runner.ts) / mirrorWithDebounce (cc-dispatcher.ts, per-user key). The
# emit is per-USER (no global-key debounce) so the affected-users condition below
# can distinguish a one-tenant blip from a fleet-wide outage (the #5873 class,
# where every tenant's Bash sandbox is down at once).
#
# Native affected-users threshold (event_unique_user_frequency): fire when ≥3
# distinct tenants hit a sandbox-startup failure within 1h. Verified against
# jianyuan/sentry 0.15.4 via `terraform providers schema -json` (condition
# type event_unique_user_frequency; comparison_type ∈ {count,percent}; interval
# valid values incl. 1h). Distinct frequency=22 avoids Sentry POST-time
# exact-duplicate dedup (keyed on action-shape + frequency + match — see the auth
# rules' comment above).
#
# ═══ WHY value = 2 AND NOT 3 (#6429) ═══
#
# `value` is compared with a STRICT `current_value > value` — `event_unique_user_frequency`
# extends the same BaseEventFrequencyCondition as `event_frequency`, whose strict-`>`
# semantics zot_mirror_fallback_rate documents below
# (sentry/rules/conditions/event_frequency.py). So `value = 2` means ">2 distinct users",
# i.e. it fires at **≥3** — the stated intent above. It shipped as `3`, which fires at ≥4:
# a silent off-by-one against its own comment, and #6429's real defect. Do NOT "restore"
# this to 3 to match the "≥3" prose — the prose is the intent, `2` is how you spell it.
#
# NOT the zot rule's defect (#6429's filed premise, falsified). That rule is
# `event_frequency` — a count of EVENTS in one issue-group, which a high-cardinality
# message breaks by minting a fresh group per event. This one counts DISTINCT USERS, and
# its group is stack-keyed (reportSilentFallback routes an Error to captureException), so
# the group is stable and the threshold is reachable. The discriminator is CAPTURE SHAPE,
# not the condition name: message-event → grouped on the message; exception-event →
# grouped on the stack. Guarded by sentry-zot-mirror-fallback-alert-op-contract.test.ts.
#
# Sentry also short-circuits the first event of a NEW group when value > 1 ("Assumes that
# the first event in a group will always be below the threshold"). Harmless here: a
# brand-new group has exactly one distinct user, already below 3.
#
# The corrected frequency-rule sweep (#6429's generalizable ask): this file has TWO
# `event_frequency` rules — zot_mirror_fallback_rate (value = 0, the #6285 fix) and
# web_terminal_boot_fatal (value = 1, reachable only because its shared `soleur-boot-emit`
# group is always already hot) — plus THIS ONE `event_unique_user_frequency`. The issue's
# "three event_frequency rules" was wrong on both the count and every line it cited.
resource "sentry_issue_alert" "sandbox_startup_failure" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "sandbox-startup-failure"
  action_match = "all"
  filter_match = "all"
  frequency    = 22

  conditions_v2 = [
    {
      event_unique_user_frequency = {
        comparison_type = "count"
        value           = 2 # STRICT `>`: fires at ≥3 distinct tenants (#6429)
        interval        = "1h"
      }
    },
  ]
  filters_v2 = [
    {
      tagged_event = {
        key   = "feature"
        match = "EQUAL"
        value = "agent-sandbox"
      }
    },
    {
      tagged_event = {
        key   = "op"
        match = "EQUAL"
        value = "sdk-startup"
      }
    },
  ]
  # N=1 accepted risk (mirrors the sibling rules in this file): IssueOwners has no
  # ownership rule on this project → falls through to ActiveMembers, paging the
  # active founder + ops@soleur.ai. The event carries only a userIdHash (Recital
  # 26 pseudonymized at the emit boundary) + bwrap/kernel stderr — no plaintext
  # tenant PII — so the fallthrough does not over-disclose. Revisit recipient
  # pinning (target_type="Member") before the first non-ops Sentry seat.
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

# ── Missed action_required inbox dispatch (feat-severity-ranked-inbox #6007) ──
# APPLY-CREATED (not import-only). A missed action_required inbox notification —
# the insert failing, or the push/email dispatch failing — is the exact "a
# decision that needs the founder, with no notice" failure this feature exists
# to prevent (ADR-085). notifyInboxItem + notifyOfflineUser→mirrorNotifyFailure
# emit feature=inbox / op=notify-inbox-action-required for the action_required
# class specifically (info/attention misses do not page). Op-pinned (EQUAL, not
# feature-only) because the `inbox` feature also carries non-paging list/read
# errors (op=list, op=set-state) that must NOT fire this rule.
resource "sentry_issue_alert" "inbox_action_required_notify_failure" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "inbox-action-required-notify-failure"
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
        value = "inbox"
      }
    },
    {
      tagged_event = {
        key   = "op"
        match = "EQUAL"
        value = "notify-inbox-action-required"
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

# ── zot mirror-staleness fallback-rate alarm (#6278 / ADR-096 "Loud, no-SSH signal") ──
# APPLY-CREATED. Pages on the FIRST runtime zot→GHCR fallback / gate-degrade event
# (event_frequency count > 0 in 1h). The LIVE-RUNTIME complement to the create-time CI
# degraded signal (mirror_status=degraded → Slack ⚠️ + ::warning::) that merged in
# #6274 / PR #6276.
#
# filter_match="any" over the FOUR runtime signal tag-VALUES (NOT feature+op "all"):
# the two ci-deploy.sh signals carry feature/op, but the inngest/app fresh-boot
# soleur-boot-emit events (cloud-init.yml) carry only `stage` — an all-match on
# feature+op would silently exclude the boot paths. Signals:
#   registry ∈ {ghcr-fallback, zot-gate-degraded}         (ci-deploy.sh rolling-deploy)
#   stage    ∈ {inngest_ghcr_fallback, app_ghcr_fallback} (cloud-init.yml fresh boot)
#
# ═══ WHY value = 0, AND WHY IT MUST STAY 0 (#6285) ═══
#
# MECHANISM. `event_frequency` counts the whole Sentry ISSUE-GROUP's events over the
# interval — `filters_v2` gate whether an event evaluates the rule, they do NOT scope
# the count. And `registry_pull_event` embeds the unique deploy tag in the MESSAGE
# (ci-deploy.sh: "image pulled from <reg> (<img>:<tag>)"), so Sentry mints a FRESH
# issue-group per deploy. The per-group count is therefore bounded by the pulling fleet
# size — it is NOT a rate.
#
# INVARIANT. Any value > 0 is fleet-shape-dependent and silently unreachable whenever
# the per-group event count cannot exceed it. Sentry compounds this: it short-circuits
# the FIRST EVENT of a new group when value > 1 ("Assumes that the first event in a
# group will always be below the threshold" — sentry/rules/conditions/event_frequency.py),
# then compares with a STRICT `current_value > value`. value = 0 is the ONLY fleet-
# independent setting: it fires on the first event of any group, at any fleet size.
# This is what the original >3/1h got wrong: on the rolling-deploy signal it needed 4+
# events in ONE group, and each deploy mints its own group sized by the puller count.
# (Not literally unfireable — re-deploying the SAME tag within the hour reuses the group
# — but a first-miss on a fresh tag, the case that matters, could never page.)
#
# DO NOT normalize to the `value = 1` used by web_terminal_boot_fatal below. That works
# there ONLY because its shared `soleur-boot-emit` group is never new (always already
# >1). On a fresh per-deploy group, value = 1 means ">1" and a single event does NOT
# page.
#
# CHANGE-TRIGGER. Do not raise above 0 without re-deriving against ci-deploy.sh's
# message construction. Parity: zot-soak-6122.sh FAILs the Phase-5 gate on >=1 fallback
# — a threshold above 0 is strictly less sensitive than the gate it exists to pre-warn.
#
# GROUPING is per-signal asymmetric (`ghcr-fallback` fresh per deploy; `zot-gate-degraded`
# per reason — 3 fixed literals; `app_ghcr_fallback` and `app_ghcr_served` each a dedicated
# static message; `inngest_ghcr_fallback` the shared always-hot `soleur-boot-emit` group).
# It no longer affects WHETHER a group pages at value = 0 — every group fires on its first
# event — but it is load-bearing for HOW to quiet noise safely (below). Relevant to the
# threshold again only if value is ever raised.
#
# IF THIS GETS NOISY, MUTE THE ISSUE — NEVER THE RULE. All five signals share one rule
# (filter_match = "any"), so muting the RULE to escape `zot-gate-degraded` noise also kills
# `ghcr-fallback` — the only no-SSH page gating the IRREVERSIBLE ADR-096 5.5 PAT
# rotate+revoke. Muting the noisy Sentry ISSUE is safe by construction for the ORIGINAL
# four: `zot-gate-degraded` groups on a stable reason literal, so a mute pins to that group
# only; `ghcr-fallback` mints a FRESH group per deploy, so no pre-existing mute can ever
# pre-suppress it. Pre-cutover the dominant noise is `probe_unreachable` — that is zot's
# probe genuinely failing (the real fix is the zot host, not the alarm).
#
# ⚠ `app_ghcr_served` (#6462) IS THE EXCEPTION — the mute-is-safe argument above does NOT
# extend to it, and this is the one signal where a reflexive mute is destructive. It is the
# first signal that is BOTH:
#   (a) stable-grouped — a static message ⇒ ONE Sentry issue group forever, so a mute is
#       permanent (unlike `ghcr-fallback`, whose per-deploy regrouping self-expires a mute);
#   (b) expected-noisy pre-cutover — ADR-096 tells the operator these pages are expected
#       until the flip and not to investigate them separately.
# Together those invite exactly one click that permanently blinds the page for the DOMINANT
# GHCR-served path (a /v2/ probe-miss, where the GHCR pull succeeds first try) — the hole
# #6462 exists to close. Muting does NOT create a false soak PASS (Discover counts muted
# issues), so the loss is paging only — but paging is the entire point of this signal
# pre-cutover.
#
# The honest levers, in order (an earlier draft of this comment offered "pin the soak's START
# past the cutover" — that is a CATEGORY ERROR and was removed: START is ZOT_SOAK_START, read
# only in zot-soak-6122.sh's sentry_count URL; THIS rule has no window and is completely
# unaffected by it. Do not reach for it):
#   1. Fix the probe (#6416 / #6288). This is the root cause and it also removes the noise
#      from `zot-gate-degraded`, which already pages on the SAME probe_unreachable condition
#      on ~34-of-38 rolling deploys — i.e. the operator is ALREADY being paged near-daily by
#      that signal, and app_ghcr_served is an increment on existing noise, not a new class.
#   2. If it must be quieted before then, mute `zot-gate-degraded`'s group (safe: it groups on
#      a stable reason literal) — NOT this one, and never the RULE.
#   3. If THIS group must be quieted, split it into its own sentry_issue_alert resource so it
#      can be tuned without touching ghcr-fallback. That is a real fix, not a mute. Since
#      #6589 the split costs only the resource block — the apply plans the full root, so
#      there is no `-target=` entry to add — plus the op-contract's alarm⇔soak parity (which
#      currently pins alarm.size == soakFailQueries().size == 5). Deferred, not dismissed:
#      see #6462's PR.
#
# Distinct `frequency = 23` avoids Sentry POST-time exact-duplicate dedup (taken:
# 5,10-22,30,60-62; keyed on action_match+filter_match+frequency+actions-shape, NOT
# conditions). Events carry only registry/stage/image/host_id/zot_gate_reason tags —
# no user content.
resource "sentry_issue_alert" "zot_mirror_fallback_rate" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "zot-mirror-fallback-rate"
  action_match = "all"
  filter_match = "any"
  frequency    = 23

  conditions_v2 = [
    {
      event_frequency = {
        comparison_type = "count"
        value           = 0
        interval        = "1h"
      }
    },
  ]
  filters_v2 = [
    {
      tagged_event = {
        key   = "registry"
        match = "EQUAL"
        value = "ghcr-fallback"
      }
    },
    {
      tagged_event = {
        key   = "registry"
        match = "EQUAL"
        value = "zot-gate-degraded"
      }
    },
    {
      tagged_event = {
        key   = "stage"
        match = "EQUAL"
        value = "inngest_ghcr_fallback"
      }
    },
    {
      tagged_event = {
        key   = "stage"
        match = "EQUAL"
        value = "app_ghcr_fallback"
      }
    },
    {
      tagged_event = {
        key   = "stage"
        match = "EQUAL"
        value = "app_ghcr_served"
      }
    },
  ]
  # N=1 accepted risk (mirrors every sibling apply-created rule): IssueOwners has no
  # ownership rule on this project → falls through to ActiveMembers, paging the solo
  # founder. Events carry only registry/stage/image/host_id — no cross-tenant content.
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

# web-host terminal serving-block boot FATAL (#6396). The cloud-init terminal `docker run` block
# emits `soleur-boot-emit <stage> fatal` (tags.stage ∈ {terminal_preamble, hostscripts_incomplete,
# doppler_download, docker_run}) on a no-SSH boot abort.
#
# HOST-GENERIC — DO NOT DELETE AS "web-2 surface" (#6575). This alert filters on `stage` and NEVER
# on host, so it was never web-2-specific; the original comment here said it was "the SOLE PAGE for
# a dead web-2 WARM STANDBY", which was already the wrong framing and became a live falsehood when
# web-2 was retired 2026-07-17 (#6538/#6463). Post-retire this is **web-1's sole no-SSH boot page**:
# a web-1 that aborts its cloud-init runcmd at stage=verify never binds :80/:3000, and `runcmd` is
# once-per-instance so no reboot repairs it. The #5933 per-host origin uptime probe was RETIRED
# (dns.tf), and `betteruptime_monitor.app` probes the app.soleur.ai A-record — which is web-1
# itself, so on a dead web-1 it goes red only after the host is already dark.
#
# SCOPE — READ BEFORE RELYING ON THIS (corrected at review, #6575). This alert does NOT detect
# the ADR-128 cross-commit skew mode (#6712). That failure aborts cloud-init at `stage=verify`,
# and `verify` is NOT among the four stages in `filters_v2` below (`terminal_preamble`,
# `hostscripts_incomplete`, `doppler_download`, `docker_run`). The whole `runcmd` stage set —
# verify/extract/pull/ghcr_login/runcmd_early/apt_install/doppler_dl/docker_apt/docker_restart —
# emits `fatal` to Sentry via the baked DSN and matches NO alert rule, so those events are
# write-only today. Detection for the skew mode is therefore ABSENT; the mitigation is
# PREVENTION (the coherence preflight, run per runbooks/web-host-birth.md step 2).
# Widening this rule to the runcmd stages is the obvious fix and is deliberately NOT bundled
# into a deletion PR — it changes live paging behaviour and wants its own change. Do not read
# the paragraph above as "boot failures page"; only these four stages do.
#
# Pages on the FIRST occurrence (a serving-host boot
# failure is high-severity), NOT a rate. The four stage tags are emitted ONLY at fatal level by the
# terminal-block EXIT trap + the explicit hostscripts_incomplete emit, so the stage filter alone
# selects fatal terminal-block failures (no separate level filter needed).
#
# GROUPING NOTE (mirrors the GROUPING paragraph of zot_mirror_fallback_rate above): these
# events use the SHARED
# `soleur-boot-emit` message ("soleur-cloud-init boot stage"; stage is a tag, not the message), so
# they share ONE issue-group with routine boot stages — that group is effectively always active, so
# event_frequency value=1 pages on the first event that MATCHES the fatal-stage filter. Over-loud in
# the SAFE direction (never a miss); a fatal terminal-block boot is always worth paging.
#
# Distinct `frequency = 24` avoids Sentry POST-time exact-duplicate dedup (taken: 5,10-23,30,60-62).
# Events carry only stage/host_id/region tags — no user content.
resource "sentry_issue_alert" "web_terminal_boot_fatal" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "web-host-terminal-boot-fatal"
  action_match = "all"
  filter_match = "any"
  frequency    = 24

  conditions_v2 = [
    {
      event_frequency = {
        comparison_type = "count"
        value           = 1
        interval        = "1h"
      }
    },
  ]
  filters_v2 = [
    {
      tagged_event = {
        key   = "stage"
        match = "EQUAL"
        value = "terminal_preamble"
      }
    },
    {
      tagged_event = {
        key   = "stage"
        match = "EQUAL"
        value = "hostscripts_incomplete"
      }
    },
    {
      tagged_event = {
        key   = "stage"
        match = "EQUAL"
        value = "doppler_download"
      }
    },
    {
      tagged_event = {
        key   = "stage"
        match = "EQUAL"
        value = "docker_run"
      }
    },
  ]
  # N=1 accepted risk (mirrors every sibling apply-created rule): IssueOwners has no ownership rule
  # on this project → falls through to ActiveMembers, paging the solo founder. Events carry only
  # stage/host_id/region — no cross-tenant content.
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

# #6441 — the first-boot private-NIC gate's non-ready outcomes (ADR-114 I1).
#
# WHY A SEPARATE RULE rather than two more stages on web_terminal_boot_fatal above: these are
# NOT terminal. soleur-wait-nic is fail-OPEN by contract — it defers and lets the boot continue,
# so folding them into a rule named "terminal-boot-fatal" would page a deferral as a boot
# failure and, worse, train the reader to discount that rule.
#
# WHY THE RULE IS LOAD-BEARING: the gate's entire value is converting a pathological case from
# SILENT to OBSERVED, and review established that without this the two stages matched no
# tagged_event filter anywhere in this file. They would also not raise a NEW-issue notification,
# because soleur-boot-emit sends one shared message ("soleur-cloud-init boot stage") for every
# stage, so all boot events land in a single perpetually-active issue group. Emitting into a
# bucket nobody reads is not observability — it is the silence the gate was built to end.
#
# Fires rarely by construction: runcmd is once-per-instance, so at most one event per fresh
# connector-host boot. Any occurrence means either the NIC never converged within 60 s
# (private_nic_timeout) or the probe could not measure at all (private_nic_probe_fault) — both
# worth a look, neither an emergency, since cloudflared dials its origin per connection and
# self-heals when the attach lands.
resource "sentry_issue_alert" "web_private_nic_boot_gate" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "web-host-private-nic-boot-gate"
  action_match = "all"
  filter_match = "any"
  frequency    = 24

  conditions_v2 = [
    {
      event_frequency = {
        comparison_type = "count"
        value           = 1
        interval        = "1h"
      }
    },
  ]
  filters_v2 = [
    {
      tagged_event = {
        key   = "stage"
        match = "EQUAL"
        value = "private_nic_timeout"
      }
    },
    {
      tagged_event = {
        key   = "stage"
        match = "EQUAL"
        value = "private_nic_probe_fault"
      }
    },
  ]
  # N=1 accepted risk, mirroring every sibling apply-created rule: IssueOwners has no ownership
  # rule on this project → falls through to ActiveMembers, paging the solo founder. Events carry
  # only stage/host_id/region — no cross-tenant content, and never the expected IP.
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

# #6604 — the /workspaces LUKS at-rest drift PAGE. Vector is Better-Stack-only and never reaches
# Sentry, so the drift page depends ENTIRELY on workspaces-luks-emit.sh's direct-curl envelope
# matching this filter (DP-8/DP-10): the emit sets BOTH feature=workspaces-luks AND
# op=workspaces-luks-drift, and filter_match="all" requires both. luks-monitor.sh (daily) and the
# cutover canary emit through that envelope on any failed at-rest assert.
resource "sentry_issue_alert" "workspaces_luks_drift" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "workspaces-luks-drift"
  action_match = "all"
  filter_match = "all"
  frequency    = 25 # unique — avoids Sentry's create-time "exact duplicate of <rule>" dedup

  conditions_v2 = [
    {
      event_frequency = {
        comparison_type = "count"
        # value=0, NOT 1: event_frequency compares with a STRICT `current_value > value`
        # (see zot_mirror_fallback_rate + web_terminal_boot_fatal above). This is a
        # DEDICATED, COLD issue-group (an event is emitted ONLY on a failed at-rest
        # assert), and luks-monitor.sh emits EXACTLY ONE event per daily failed run. With
        # value=1 a single daily drift is count=1, `1 > 1` is false → NO page. value=0
        # pages on the FIRST event (matches zot_mirror_fallback_rate). web_terminal_boot_fatal
        # can use value=1 only because its group is always-already-hot (shared boot events);
        # this group is not.
        value    = 0
        interval = "1h"
      }
    },
  ]
  filters_v2 = [
    {
      tagged_event = {
        key   = "feature"
        match = "EQUAL"
        value = "workspaces-luks"
      }
    },
    {
      tagged_event = {
        key   = "op"
        match = "EQUAL"
        value = "workspaces-luks-drift"
      }
    },
  ]
  # N=1 accepted risk (mirrors every sibling apply-created rule): IssueOwners falls through to
  # ActiveMembers, paging the solo founder. Drift events carry only the nine discriminating fields
  # (device_type/mount_source/… /host/reason) — no cross-tenant content.
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

# #6512 Fix 1 — seccomp reload local-cache reuse (registry == "local-cache"). ci-deploy.sh's
# pull_image_with_fallback grew a THIRD, last-resort tier: when BOTH the zot-primary and the
# GHCR-fallback legs fail to serve a same-version `web` reload (the item-4 seccomp redeploy of
# v<running_version>), it reuses the ALREADY-RUNNING container's cosign-verified image ID instead
# of dying image_pull_failed, and emits `registry_pull_event local-cache` at level=warning.
#
# This is a SEPARATE alert from zot_mirror_fallback_rate on purpose (do NOT fold local-cache into
# that rule): `ghcr-fallback` means "zot missed but GHCR served" and is the single no-SSH page
# gating the IRREVERSIBLE ADR-096 §5.5 GHCR-PAT retirement — a `local-cache` event means NEITHER
# registry served, a categorically different (and worse) condition. Overloading the retirement gate
# with it would corrupt that gate's meaning. A dedicated rule keeps the two signals decoupled.
#
# value=0 pages on ANY local-cache reuse (mirrors zot_mirror_fallback_rate's #6285 value=0 posture):
# the reload succeeded THIS time by reusing the local image, but both registries failing to serve an
# already-built image is a standing supply-chain-path degradation that must not hide behind the
# working local cache (the silent-fallback-14-days class). GROUPING: registry_pull_event embeds the
# unique deploy tag in the MESSAGE ("image pulled from local-cache (web:vX.Y.Z)"), so Sentry mints a
# FRESH issue-group per deploy — no pre-existing mute can permanently silence it.
#
# Distinct frequency = 26 avoids Sentry POST-time exact-duplicate dedup (taken: 5,10-25,30,60-62).
# Events carry only registry/image/tag — no user content.
resource "sentry_issue_alert" "local_cache_reload_rate" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "local-cache-reload-rate"
  action_match = "all"
  filter_match = "all"
  frequency    = 26

  conditions_v2 = [
    {
      event_frequency = {
        comparison_type = "count"
        value           = 0
        interval        = "1h"
      }
    },
  ]
  filters_v2 = [
    {
      tagged_event = {
        key   = "registry"
        match = "EQUAL"
        value = "local-cache"
      }
    },
  ]
  # N=1 accepted risk (mirrors every sibling apply-created rule): IssueOwners has no ownership rule
  # on this project → falls through to ActiveMembers, paging the solo founder. Events carry only
  # registry/image/tag — no cross-tenant content.
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

# #6512 Fix 2a — seccomp remediation redeploy terminally FAILED, leaving the running container's
# profile UNENFORCED (op == "seccomp-remediation-failed"). Emitted by scripts/seccomp-unenforced-alert.sh
# (sourced by apply-deploy-pipeline-fix.yml's item-4 step) at every terminal failure that gives up
# with the profile confirmed-or-presumed unenforced (redeploy image_pull_failed / diagnose_and_fail).
#
# This is a DEDICATED alert, distinct from the container/registry supply-chain rules: the operator's
# PRIMARY surface is the plain-language `ci/seccomp-unenforced` GitHub issue the same emitter files
# (operator-digest harvests action-required issues, never red CI jobs); this Sentry rule is the
# secondary alerting plane. It is EVENT-driven, deliberately NOT a cron-monitor check-in — an
# event-driven check-in to a cadence monitor's slug resets its missed-check-in clock and masks a
# genuinely-missed scheduled beat (code-simplicity MEDIUM).
#
# value=0 pages on the FIRST occurrence — an unenforced security control on prod is high-severity and
# invisible on the site's own health (the #6454/#6512 shape). GROUPING: the event message embeds the
# failure detail so Sentry groups per distinct cause.
#
# Distinct frequency = 27 avoids Sentry POST-time exact-duplicate dedup (taken: 5,10-26,30,60-62).
# Events carry only the failure detail (host_present/host_sha/loaded_matches or a redeploy reason) —
# no user content.
resource "sentry_issue_alert" "seccomp_remediation_failed" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "seccomp-remediation-failed"
  action_match = "all"
  filter_match = "all"
  frequency    = 27

  conditions_v2 = [
    {
      event_frequency = {
        comparison_type = "count"
        value           = 0
        interval        = "1h"
      }
    },
  ]
  filters_v2 = [
    {
      tagged_event = {
        key   = "op"
        match = "EQUAL"
        value = "seccomp-remediation-failed"
      }
    },
  ]
  # N=1 accepted risk (mirrors every sibling apply-created rule): IssueOwners has no ownership rule
  # on this project → falls through to ActiveMembers, paging the solo founder. Events carry only the
  # failure detail — no cross-tenant content.
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

# #6657 / ADR-125 — GitHub Pages cert-reissue failure pager.
# cron-gh-pages-cert-reissue is event-triggered (no Sentry cron monitor), so its
# only paging surface is the reportSilentFallback events it emits on a genuine
# remediation failure: poll_timeout / reissue_failed / proxy_restore_failed /
# precondition_blocked (CAA appeared, TXT missing, carve-out regressed) /
# reissue_incomplete_restore_ok (a retries-exhausted body throw whose restore
# still succeeded). Benign outcomes are deliberately NOT emitted to Sentry
# (logger only): issued, not_stuck, and config_missing (the DNS-edit token IaC
# not yet applied — see cron-gh-pages-cert-reissue.ts BENIGN_OUTCOMES). So every
# event carrying feature=cron-gh-pages-cert-reissue is by construction a failed
# remediation — page the founder. The highest-severity arm (proxy_restore_failed:
# origin IPs exposed AND/OR custom domain unset) is included by the feature filter.
resource "sentry_issue_alert" "gh_pages_cert_reissue_failed" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "gh-pages-cert-reissue-failed"
  action_match = "all"
  filter_match = "all"
  frequency    = 63

  conditions_v2 = [
    {
      event_frequency = {
        comparison_type = "count"
        value           = 0
        interval        = "1h"
      }
    },
  ]
  filters_v2 = [
    {
      tagged_event = {
        key   = "feature"
        match = "EQUAL"
        value = "cron-gh-pages-cert-reissue"
      }
    },
  ]
  # N=1 accepted risk (mirrors every sibling apply-created rule): IssueOwners has no ownership rule
  # on this project → falls through to ActiveMembers, paging the solo founder. Events carry only the
  # reissue outcome + infra fields — no user PII / cross-tenant content.
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
