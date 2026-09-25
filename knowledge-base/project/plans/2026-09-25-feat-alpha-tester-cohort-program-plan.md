---
title: "feat: alpha-tester cohort program — onboarding flow v2 + value-prop validation loop"
date: 2026-09-25
slug: feat-alpha-tester-cohort-program
branch: feat-alpha-tester-value-loop
issue: 8880
lane: cross-domain
type: feat
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

Advance Soleur's Phase 4 alpha-validation protocol (#1439–#1443) for testers 2–10 on the hosted
platform: repair tester #1's incomplete loop, fix first-session orientation on real installs,
give the non-technical operator one pull-based cohort view, arm checkpoints instead of
remembering them, and ship a tester-owned local decision log that closes the self-hosted
measurability gap while producing the durable decision corpus the parked System-1 eval needs.

Brainstorm: `knowledge-base/project/brainstorms/2026-09-25-alpha-tester-value-loop-brainstorm.md`
Spec: `knowledge-base/project/specs/feat-alpha-tester-value-loop/spec.md` (issue #8880)

## Research Insights

### Verified premise (2026-09-25, origin/main)

- Alpha tester #1 (Skouer) is onboarded on self-hosted CLI; 2-week checkpoint was never filed
  (5+ weeks overdue); #7459 terms re-notify open; C9 re-run required per #7348 before tester #2.
- `welcome-hook.sh:16` guards on `[[ -d "${PROJECT_ROOT}/plugins/soleur" ]]` — true only for
  vendored/dev installs; marketplace installs never fire the welcome (root cause of the #5119
  orientation gap). Pinned by `plugins/soleur/test/welcome-hook.test.ts`.
- `hooks.json` has no Skill/Task matcher; nothing ships plugin-side decision capture.
  `.claude/hooks/skill-invocation-logger.sh` + `agent-token-tee.sh` are repo-side only (ADR-229).
- Activation already implemented: `computeFunnel`/`computeMetrics` in
  `apps/web-platform/lib/analytics.ts` (domainCount≥2 + span≥14d, constants at :41-45).
- `POST /api/internal/schedule-reminder` is idempotent on `reminder_id`+`fire_at`; allowlisted
  `issue-comment` + `named-check` actions; `CHECK_REGISTRY` at
  `server/inngest/functions/event-scheduled-reminder.ts:88`.
- Invite tokens are workspace-membership (`workspace_invitations` + WORM trigger) — keyless
  invitees route PAST `/setup-key` to `/dashboard/settings/team` (#4715 ordering), i.e. a
  keyless tester ends in a disabled product. Invite tokens are therefore NOT the cohort-capture
  vehicle; a `users.cohort_key` column + admin PATCH is.
- `beta_contacts` exists (stage enum, `last_contact`, `next_action`, `next_action_date`,
  `source`); `crm_get_contact_detail` is audited egress (writes an access-log row per call) —
  cohort-status prefers issue/git-derived data in v1; no CLI auth path to the platform exists.
- Skill-description budget: **2359/2389 model-visible words → 30 headroom** (measured via the
  components.test.ts counting method). `cohort-status` description must be ≤30 words (target
  ~25); no budget bump or sibling trims needed.
- Slack exists in-repo only as `SLACK_RELEASES_WEBHOOK_URL` (GHA incoming webhook, no bot/API
  client). Tester Slack channel = vendor-workspace action on the existing Slack workspace.
- `.claude/hooks/devin-matcher-parity.test.sh` T1 requires a `soleur-plugin` row in
  `.claude/hooks/devin-dispositions.tsv` for every new `hooks.json` registration.
- No plugin-side `log-rotation.sh` copy exists — `decisions.jsonl` rotation is inlined.

### Institutional learnings applied

- `hr-no-dashboard-eyeball-pull-data-yourself` — cohort-status is a pull, not a dashboard.
- operator-digest's "a failed read is NOT a quiet week" guardrail — reused verbatim in
  cohort-status output.
- `2026-09-22-worktree-git-paths-follow-cwd` + today's filing-gate learning — absolute paths.
- ADR-091 local-producer doctrine — the decision log is a local artifact, never CI-committed.

### Premise Validation note

All cited refs verified live this session: #1439–1443/#7348/#7459/#5119/#4647 open; runbook,
validation record, processing annex, LIA, and tech-debt file present on origin/main; platform
serving; welcome-hook bug reproduced by reading source; schedule-reminder contract verified in
`route.ts`. One premise CORRECTED: spec D8 proposed invite-token cohort capture — invite tokens
are workspace-membership with an ordering hazard (conversion-optimizer finding); replaced by
`users.cohort_key` + admin route.

### Property List (Phase 0.6b)

- P1 cohort state visible in one pull (runbook tally / issues / CRM today drift apart)
- P2 checkpoints fire without human memory (tester #1's was never filed)
- P3 activation/retention/agent-mix measurable (falsification tree needs data)
- P4 durable routing/skill/agent decisions on user machines (eval corpus + agent-mix)
- P5 near-zero-friction per-tester loop for a non-technical operator + tester
- P6 tester-#1 repair completes before tester #2
- P7 first-session orientation fires on real (marketplace) installs

### Cut List

- Opt-in telemetry beacon — property (P3/P4 partial) covered by aggregate pull; deferred per
  CLO (consent + Art. 13 + PA row + docs lockstep + TC bump).
- Admin-dashboard cohort-filter UI — P1 covered by cohort-status skill; deferred.
- Questionnaire-driven onboarding (#6008) — separate backlog item.
- In-product support surface — Slack chosen; no build.
- Server-side Slack posting — retention-adviser: keep tester Slack human; webhook is GHA-only.
- Plugin `hooks.json` Skill/Task matcher + `decision-emit-hook.sh` + dispositions rows —
  cut at plan review (DHH): coverage imbalance across harnesses + bash-JSON parsing; the
  prose emit owns both `route_decision` and opt-in `tool_invocation` events.
- `emitter_ready` capability-state machine — cut at plan review; the day-0 human verify
  (runbook 2.1g) plus alpha-metrics ABSENT/EMPTY markers cover the same property.
- Locking around the append — cut at plan review; O_APPEND printf under PIPE_BUF is
  atomic on POSIX.
- `arm-checkpoint.sh` runbook-table write — cut at plan review; reminder_ids are
  self-describing (`checkpoint-tester-N-<date>`); the script prints them and
  cohort-status derives expected ids by convention.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Codebase reality | Plan response |
|---|---|---|
| D8 "invite-token attribution, no signup UI" | Workspace-invites are membership grants; keyless invitees bypass `/setup-key` into a disabled product | `users.cohort_key` column (migration 141) + admin PATCH `/api/admin/cohort` set at tester signup |
| FR3 "owner RPC where platform allows" | `crm_get_contact_detail` writes an access-log row per call (audited egress); CLI has no Supabase session anyway | cohort-status v1 = git-runbook tally + `gh issue` + recorded reminder_ids only; CRM stage noted as an operator-side check |
| TR2 hook matcher `^(Skill|skill|Task|run_subagent)$` | Hook parity is ~1.5/4 harnesses; a hook matcher adds coverage imbalance + a bash-JSON parser on macOS | Hook path CUT at plan review — prose-directed emit only (uniform coverage; `route_decision` single-writer in go.md) |
| TR1 `.soleur/` outside git tree | `.soleur/` is gitignored only in THIS repo; tester repos have no guard | emit script also writes `.soleur/.gitignore` containing `*` — committable only via explicit `git add -f` |

## Implementation Phases

### Phase 1 — Plugin decision capture + welcome fix (Slice 1 core)

1.1. `plugins/soleur/scripts/emit-decision.sh` — append one field-allowlisted JSON line to
     `.soleur/decisions.jsonl` (slim schema, frozen at the allowlist:
     `{v,ts,event,label,skill,agent_domain,harness,session_id,plugin_sha,repo_hash}` —
     `event ∈ {route_decision, tool_invocation}`; `repo_hash` is a sha256 prefix of the
     git-root path — cohort-correlating without writing the path itself). Flags:
     `--event X --label Y [--skill S] [--agent_domain D]`; `harness`, `session_id`,
     `plugin_sha` auto-derived. Behaviors: resolve-git-root → `.soleur/` (default
     `GIT_ROOT`), create `.soleur/.gitignore` containing `*` on first write (self-guard),
     single `printf >>` append — O_APPEND writes under PIPE_BUF are atomic on POSIX; NO
     lock (two lock implementations for a handful of appends per session was a review-cut
     over-mechanization), inline size-rotate at ~5 MB (`decisions.jsonl.1`), fail-open
     exit 0, kill-switch `SOLEUR_DISABLE_DECISION_LOG`, `--selfcheck` prints
     `SOLEUR_EMIT_OK`. Never writes intent text/args/paths — the emit script is the single
     writer chokepoint, so the NO-ECHO contract is enforced at the boundary, not per call
     site.
     **Portability contract (sharp-edge #8231):** runs on TESTER machines — stock macOS has
     no `flock`, `timeout`, `date -d`, `sed -i`, `stat -c`, `readlink -f`, `jq`, and ships
     bash 3.2. Use: `#!/usr/bin/env bash` with bash-3.2-safe syntax (no associative
     arrays); `wc -c` for size; `date -u +%FT%TZ`; awk/grep/sed only; no `python3`/`jq`.
1.2. `plugins/soleur/scripts/emit-decision.test.sh` — covers write, ignore-guard, rotation,
     kill-switch, selfcheck, PIPE_BUF append correctness under two concurrent emitters;
     trap/EXIT placed BEFORE sourcing test-helpers; every negative row carries a positive
     control on the same input.
1.3. `plugins/soleur/commands/go.md` — after the routing-table decision, one prose line
     directing the agent to run `emit-decision.sh --event route_decision --label <route>`.
     `route_decision` is prose-owned (the agent knows the route; no hook sees it).
     **Capture model (review-cut):** prose-directed emit ONLY — uniform coverage across
     all four harnesses; a `hooks.json` Skill/Task matcher was designed then deleted at
     plan review: it added a bash-JSON parser on stock macOS (no jq), hook parity is
     ~1.5/4 harnesses anyway (capture imbalance = the capture-rate≠usage-rate trap), and
     hook-vs-prose double counting needed a disclaimer for a second instrument measuring
     the first. Skills MAY also prose-invoke `--event tool_invocation` at decision points
     where they own one. Capability detection is the day-0 human verify (2.1g) plus
     `alpha-metrics.sh` ABSENT/EMPTY markers — no capability-state event type.
1.4. `plugins/soleur/hooks/welcome-hook.sh` — remove the `plugins/soleur` dir guard (the hook's
     own registration already implies the plugin is active; the per-project sentinel at
     `.claude/soleur-welcomed.local` remains the dedupe). Keep the Codex/PLUGIN_ROOT bail.
1.5. `plugins/soleur/test/welcome-hook.test.ts` — re-pin semantics: sentinel now emits in any
     git repo when the plugin's SessionStart fires; add a second-repo sentinel test.

### Phase 2 — Onboarding flow v2 (Slice 2)

2.1. `knowledge-base/engineering/operations/runbooks/alpha-tester-onboarding.md` — v2 sections:
     (a) hosted path Step 3 rewrite (invite link → accept-terms → guided key setup live on the
     call → connect GitHub live → first real business question producing one artifact;
     self-serve-OK list: T&C, naming, tour, Slack); (b) Slack channel step (create private
     channel in the existing Jikigai workspace, invite tester, pin the setup/"what to try"
     message; reactive-only cadence — no scripted broadcasts); (c) checkpoint arming replaces
     Step 6 via a single wrapper `scripts/arm-checkpoint.sh tester-N` (below): POSTs
     `checkpoint-tester-N-<YYYY-MM-DD>` (date embedded — Inngest dedupes on event id, so a
     re-arm at a different fire_at under the same id is a lie-shaped 202) AND arms
     `cohort-quiet-tester-N` at day-3 in the same call, then appends both reminder_ids to
     the runbook row; issue-comment bodies @mention the operator (comments on closed
     issues notify nobody); (d) day-3/day-7 quiet protocol (threshold
     `daysSinceLastSession ≥ 3` during days 1–10, operator nudge via Slack only if quiet —
     no scripted touchpoints, they contaminate the unassisted-usage signal; when a nudge
     IS sent, record `nudged_at` in the tester's runbook row — the checkpoint template
     discloses assisted-vs-unassisted returns per tester (a nudged tester who returns is
     assisted, not unassisted — the protocol's load-bearing metric)); (e) tester-#1
     repair section (checkpoint now, #7459 re-notify, CRM contact, C9 re-run, retro
     problem-interview flagged post-exposure — never pooled with #1440); (f) recruitment
     update (screening-question sentence from copywriter; non-CC seats first: testers #2–4;
     channel:framing attribution recorded in `beta_contacts.source` + company-level in
     git; stall fallback: if no non-CC candidate signs within 2 weeks, onboard the next
     qualified CC tester while non-CC outreach continues — the ≥3/10 floor has slack until
     tester #8, an unbounded stall is the worse outcome); (g) guided-session day-0 verify step: run `/soleur:go` on the tester's machine
     and confirm one `decisions.jsonl` line lands (stale-install detection at day 0, not
     day 14); (h) at the admin PATCH, record `cohort_key` + `tester-N` in the runbook row
     (non-PII tag↔cohort map so cohort-status can reconcile tagging).
2.2. `scripts/arm-checkpoint.sh` — operator-side wrapper (repo scripts/, not shipped):
     args `tester-N`; reads `INNGEST_MANUAL_TRIGGER_SECRET` from env (fail loudly with the
     Doppler read instruction if unset — never hardcode); POSTs the two reminders via the
     internal route; prints the armed reminder_ids (self-describing
     `checkpoint-tester-N-<date>` / `cohort-quiet-tester-N` convention — cohort-status
     derives expected ids from the convention; no markdown-table write per review-cut).
     Portable-bash (operator machine may be macOS — same portability contract as 1.1).
2.3. `plugins/soleur/tester-docs/alpha-tester-setup.md` — tester-facing hosted setup doc (the welcome
     message's missing link target): screenshot-level Anthropic-key instructions, "check spam
     for the OTP", steer Google OAuth, GitHub "Skip this step — connect later with help",
     three starter prompts, Slack link. Linked via github.com blob URL.
2.4. Welcome-message update in the runbook (copywriter drop-in — preserves Art. 14 notice,
     terms paragraph, reply-ask, and adds the first-session-artifact promise; CLI→hosted).
2.5. `knowledge-base/marketing/recruitment-messaging-templates.md` — append the screening
     question to each DM variant.
2.6. Runbook exit-interview section (#1443 instrument, added while the file is open):
     the $49/mo willingness-to-pay ask, the testimonial opt-in question (CMO), and the
     nudge-disclosure question ("did any of my check-ins change whether you came back?").

### Phase 3 — Cohort instrumentation (Slice 3)

3.1. `apps/web-platform/supabase/migrations/141_users_cohort_key.sql` (+ `.down.sql`) —
     `ALTER TABLE public.users ADD COLUMN IF NOT EXISTS cohort_key text NULL` +
     `CHECK (cohort_key ~ '^[a-z0-9-]+$')` (free-text fragments like `alpha-3` vs `alpha-03`
     split the cohort) + `-- LAWFUL_BASIS: Art. 6(1)(f)` annotation + COMMENT (write via
     service role only — migration 006 already REVOKEs authenticated UPDATE).
3.2. `apps/web-platform/app/api/internal/cohort/route.ts` — `PATCH` gated on the
     `INNGEST_MANUAL_TRIGGER_SECRET` bearer (trigger-cron shape) + `createServiceClient()`:
     `{userId, cohort_key}` → update (lowercase-normalize before write). **Deviation from
     the drafted path (admin/):** `/api/admin/*` is session-cookie auth — the operator
     cannot curl it. Internal-ops writes belong under `/api/internal/` + a narrow
     PUBLIC_PATHS entry (`/api/internal/cohort` registered; do NOT broaden the prefix).
     Test file alongside. The runbook pairs the PATCH with the runbook-row record (2.1h)
     so the tag is never server-only.
3.3. `apps/web-platform/app/api/admin/analytics/route.ts` + `lib/analytics.ts` — `?cohort=`
     query param: select `cohort_key` into `UserRow`, filter users before
     `computeFunnel`/`computeMetrics`, and filter `conversations` server-side with
     `.in("user_id", cohortIds)` — applied BEFORE the 10_000-row cap so cohort rows are
     never truncated away. Extend `test/analytics-funnel.test.ts` /
     `analytics-metrics.test.ts`.
3.4. `server/inngest/functions/event-scheduled-reminder.ts` — `cohort-quiet` named check in
     `CHECK_REGISTRY`: select cohort members (`cohort_key = $1`); quiet predicate =
     `GREATEST(created_at, last_active) ≥ 3d` over NON-FAILED conversations (a `failed`
     conversation must not suppress quiet, and `last_active` catches resumed threads) OR
     `zero conversations AND signup_age ≥ 3d` (the never-activated tester — highest churn
     risk — otherwise reports quiet-forever); ALSO lists recent signups with
     `cohort_key IS NULL` (the un-tagged-signup visibility gap between signup and the
     operator's PATCH) → `report_to_issue` posts the quiet list (company-level only).
3.5. `plugins/soleur/scripts/alpha-metrics.sh` (+ `.test.sh`) — tester-run aggregate print:
     wc -l, per-skill/per-agent_domain/per-harness counts, first/last ts; logger-presence
     probe emitting `SOLEUR_EMIT_ABSENT` when the log is missing and `SOLEUR_EMIT_EMPTY` when
     it exists with zero lines (kill-switch/unwritable-dir void detector);
     git-log KB-growth instructions. **Portability contract: awk/grep/sed only — no `jq`,
     `flock`, `date -d`, `sed -i`, `stat`, `timeout`, `python3`** (tester machines = stock
     macOS). Merged-rotation reads (`decisions.jsonl` + `.1`). Capability reporting is
     ABSENT/EMPTY only (no capability-state event type — the day-0 human verify at 2.1g
     is the capability check); absence never reads as zero usage.
3.6. `plugins/soleur/skills/cohort-status/SKILL.md` — pull-based cohort table: parse the
     runbook recruitment-mix table (tally + non-CC floor + `checkpoint_armed` columns),
     `gh issue list` for `alpha-tester`/checkpoint issues (stage + overdue state);
     expected reminder_ids derived from the `checkpoint-tester-N-<date>` convention
     (armed-vs-fired ≈ checkpoint issue exists+closed-vs-open). Description ≤30 words starting "This skill". Failed-read
     guardrail: a failed source read renders `UNREADABLE`, never zeros — the
     operator-digest "a failed read is NOT a quiet week" rule; the quiet flag derives from
     a POSITIVE read (`daysSinceLastSession ≥ 3`), never from an absent source. Issue
     titles printed into the table are sanitized (strip newlines + `|` — titles are
     editable text, forgery class). Operator-invoked only — no cron surface runs it.
     Cloud-mode + grok header boilerplate per skill convention; README component counts
     updated; check `skill-body-budget.json` ceiling-entry convention for new skills at
     work time.
3.7. `knowledge-base/engineering/architecture/decisions/ADR-251-*.md` (provisional ordinal)
     — tester-owned local decision log: `.soleur/` sink on user machines, prose-directed
     emit (no hooks — uniform 4-harness coverage), field-allowlist NO-ECHO, no egress,
     tester-initiated aggregate export;
     prose-only capture model with LLM-compliance caveat; **surface→instrument table**
     (hosted cohort: `?cohort=` + cohort-quiet + conversations, pulled server-side;
     CLI/operator: emit-decision + alpha-metrics, pulled at checkpoint) and a residency
     pin: if a hosted runtime ever executes plugin emit inside Jikigai-run workspaces,
     `.soleur/` lands on Jikigai infrastructure — the ADR pins ownership + residency so
     the Posture-A story is evaluated, not assumed; the schema is FROZEN to the allowlist —
     a future corpus need renegotiates the boundary, it doesn't creep it.
3.8. `knowledge-base/engineering/architecture/diagrams/model.c4` — extend the plugin/hooks
     container description with the `.soleur/` local sink line (ADR-227 precedent for
     recording shipped-surface state extensions). No new elements: `betaContact` already
     covers the tester actor; Slack is a human comms channel, not a modeled system edge
     (no API integration built); `views.c4`/`spec.c4` unchanged — verified against the
     three files.

### Phase 4 — Tester-#1 repair verification sweep

(The repair runs NOW, off this PR's critical path — nothing below waits on merge.)

Every repair item is executable on runbook v1 TODAY — none depends on this PR's code, and
the 5+-weeks-overdue checkpoint is decaying evidence. The operator runs them in parallel
starting now: overdue checkpoint filing (aggregate + self-report disclosed as such),
#7459 re-notify (TC 2.5.0→2.5.1), beta-CRM contact upsert (owner-authenticated RPC —
never a scripted bypass), C9 re-run per #7348, retro problem interview flagged
post-exposure. This PR's Phase 4 verifies each item closed and updates the runbook's
repair checklist — it does not gate tester #2 on the merge.

## Files to Create

- `plugins/soleur/scripts/emit-decision.sh`
- `plugins/soleur/scripts/emit-decision.test.sh`
- `plugins/soleur/scripts/alpha-metrics.sh`
- `plugins/soleur/scripts/alpha-metrics.test.sh`
- `plugins/soleur/skills/cohort-status/SKILL.md`
- `plugins/soleur/tester-docs/alpha-tester-setup.md`
- `scripts/arm-checkpoint.sh`
- `apps/web-platform/app/api/admin/cohort/route.ts` (+ test)
- `apps/web-platform/supabase/migrations/141_users_cohort_key.sql`
- `apps/web-platform/supabase/migrations/141_users_cohort_key.down.sql`
- `knowledge-base/engineering/architecture/decisions/ADR-251-*.md` (provisional ordinal)

## Files to Edit

- `plugins/soleur/hooks/welcome-hook.sh`
- `plugins/soleur/test/welcome-hook.test.ts`
- `plugins/soleur/commands/go.md`
- `knowledge-base/engineering/operations/runbooks/alpha-tester-onboarding.md`
- `knowledge-base/marketing/recruitment-messaging-templates.md`
- `apps/web-platform/app/api/admin/analytics/route.ts`
- `apps/web-platform/lib/analytics.ts`
- `apps/web-platform/test/analytics-funnel.test.ts` / `analytics-metrics.test.ts`
- `apps/web-platform/server/inngest/functions/event-scheduled-reminder.ts`
- `knowledge-base/engineering/architecture/diagrams/model.c4`
- `plugins/soleur/README.md` (component counts)

## Open Code-Review Overlap

None — queried `gh issue list --label code-review --state open` against every planned path;
zero matches.

## Acceptance Criteria

- [ ] AC1: `emit-decision.sh --event route --label test` appends exactly one valid-JSON line
      to `.soleur/decisions.jsonl` containing all schema keys and no prompt/arg/path text;
      exits 0 with `SOLEUR_DISABLE_DECISION_LOG=1` and writes nothing.
- [ ] AC2: First write creates `.soleur/.gitignore` whose content is `*`;
      `git status` in the project shows no `.soleur` change.
- [ ] AC4: `welcome-hook.sh` emits the sentinel + welcome JSON in a git repo WITHOUT a
      `plugins/soleur` directory; test suite updated and green.
- [ ] AC5: `bun run` the emit/alpha-metrics test scripts — all green, including a
      `SOLEUR_EMIT_ABSENT` assertion for a missing log.
- [ ] AC6: `PATCH /api/admin/cohort` sets `users.cohort_key` (admin); non-admin → 403;
      `GET /api/admin/analytics?cohort=alpha` returns funnel/metrics scoped to the cohort.
- [ ] AC7: Migration 141 applies and its `.down.sql` reverts; column carries the
      `-- LAWFUL_BASIS:` annotation and COMMENT.
- [ ] AC8: `cohort-quiet` check exists in `CHECK_REGISTRY`, accepts `{cohort, min_days}`,
      and posts a company-level quiet list to `report_to_issue`.
- [ ] AC9: `soleur:cohort-status` prints a per-tester table (stage, checkpoint armed/fired,
      quiet flag, tally + mix floor); an unreadable source renders `UNREADABLE`, never 0.
- [ ] AC10: Runbook v2 names the hosted path end-to-end incl. guided-key step, Slack step,
      armed-checkpoint step (with `reminder_id` recording), quiet thresholds, tester-#1
      repair checklist, and the screening question.
- [ ] AC11: Tester setup doc exists at `plugins/soleur/tester-docs/alpha-tester-setup.md` and the
      runbook welcome message links to it; immutable legal paragraphs preserved verbatim
      (diff-verified against the prior block).
- [ ] AC12: `ADR-251-*` exists documenting the decision-log substrate (or ordinal renumbered
      per collision sweep); `model.c4` gains the `.soleur/` sink line; C4 tests pass.
- [ ] AC13: Observability discoverability test (`bash
      plugins/soleur/scripts/emit-decision.sh --selfcheck`) prints `SOLEUR_EMIT_OK`.

## Domain Review

**Domains relevant:** Product, Legal, Marketing, Operations, Support (carried forward from
brainstorm `## Domain Assessments` — all six leaders ran; Sales/Finance assessed
not-matched).

### Legal

**Status:** reviewed (carry-forward)
**Assessment:** Local-only logging = Posture A, zero new regulated surface; regulated event is
collection → tester-initiated aggregate export at the checkpoint, no beacon (consent stack +
TC bump + PA row required otherwise — deferred). #7348 (annex unexecuted; Art. 28(2)
authorisation outstanding per PA-34) and #7459 are preconditions to scaling, not to building.
`soleur:gdpr-gate` manually invoked at this plan (regex does not cover `plugins/soleur/`):
no Critical findings; `users.cohort_key` carries the `-- LAWFUL_BASIS:` annotation;
Slack tester comms flagged for a PA-register coverage check (repo register shows Slack only
as GHA webhook + deferred DM).

### Engineering

**Status:** reviewed (carry-forward + repo-research inventory)
**Assessment:** Nothing ships plugin-side capture; the initial dual-write design (hook + prose) was CUT
at plan review in favor of prose-only emit — hook parity is ~1.5/4 harnesses, so hook
capture adds imbalance rather than coverage, and it requires a bash-JSON parser on stock
macOS. Emit clones the `skill-invocation-logger.sh` posture (rotation, kill-switch,
fail-open) minus the lock. Schema is field-allowlisted
(NO-ECHO); harness-tagged so capture-rate never conflates with usage-rate. New constraints
surfaced by inventory: no plugin-side `log-rotation.sh` (inline rotation), `.soleur/` not
auto-gitignored in tester repos (`.gitignore` self-guard).

### Marketing

**Status:** reviewed (carry-forward + 4 specialists ran)
**Assessment:** CMO: non-CC mix constraint == surface constraint → hosted; fill non-CC seats
first (testers #2–4); screening question into recruitment DMs; `source` = `channel:framing`
attribution. Specialists: conversion-optimizer (drop-off ranking — setup-key is the killer,
guided-session covers it; invite-ordering hazard flagged → cohort-capture redesigned);
retention-strategist (14-day arc, day-3/7/14 touchpoints, `daysSinceLastSession ≥ 3` quiet
threshold, no scripted cadence); copywriter (welcome block + screening question + Slack
blurb, all immutable elements preserved); analytics-analyst (no new events needed;
`?cohort=` scope + `beta_contacts.source` taxonomy; weekly cohort numbers list).

### Operations

**Status:** reviewed (carry-forward)
**Assessment:** Skill-ify the mechanical 60% (cohort-status, armed checkpoints); keep the
human 40% human (CRM upsert, welcome message, guided sessions). Cohort-status is the
three-substrate reconciliation answer.

### Support

**Status:** reviewed (carry-forward)
**Assessment:** Blank-wall onboarding confirmed (welcome hook, no setup doc, no inbound
channel) — all three fixed in this plan. Capability gap recorded: no customer-success agent
seat (revisit at cohort ≥5).

### Product/UX Gate

**Tier:** none — no UI-surface files in `## Files to Create`/`## Files to Edit` (verified
against the ui-surface-terms glob: no `components/**`, `app/**/page.tsx`, `pages/**`,
`*.njk`). The onboarding journey changes operationally; in-product UI is unchanged.
If a later scope change adds a page/component, the mechanical override fires at plan/work.
**Agents invoked:** none (not required at NONE tier)
**Skipped specialists:** none — all 4 brainstorm-recommended specialists ran
**Pencil available:** N/A (no UI surface)

**Brainstorm-recommended specialists:** conversion-optimizer ✓ ran · retention-strategist ✓
ran · copywriter ✓ ran · analytics-analyst ✓ ran.

## User-Brand Impact

**If this lands broken, the user experiences:** a guided onboarding call that ends in a
disabled product (key skipped, invite-ordering dead end, silent welcome hook) — or a
checkpoint that never fires, leaving a first real user untracked in a small community
that doubles as the recruitment channel.

**If this leaks, the user's data is exposed via:** a decision log or metric pull that
captures prompt text/args/PII instead of field-allowlisted metadata — contradicting the
published "does not phone home" claims and creating an unconsented processing surface.

**Brand-survival threshold:** single-user incident

CPO sign-off: carried forward from brainstorm (CPO assessment on file); plan re-confirms the
same framing. `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Observability

```yaml
liveness_signal:
  what: cohort-quiet named-check firing per schedule + decisions.jsonl emit rows on user machines
  cadence: day-3 quiet probe per tester; decision rows per routing event
  alert_target: tracking issue comments (named-check report_to_issue)
  configured_in: server/inngest/functions/event-scheduled-reminder.ts CHECK_REGISTRY
error_reporting:
  destination: drop-sentinel rows inside decisions.jsonl (bounded-flock timeout, disabled-log probe)
    + named-check FAILURE posts to report_to_issue + SOLEUR_EMIT_ABSENT marker in alpha-metrics output
  fail_loud: hook/emitter always exit 0 by design; sentinel rows are the loud channel
failure_modes:
  - mode: stale plugin install (hook matchers absent)
    detection: SOLEUR_EMIT_ABSENT marker in alpha-metrics output
    alert_route: checkpoint aggregate pull surfaces it to the operator
  - mode: emit write fails (flock timeout, fs error)
    detection: drop-sentinel row {event:"drop",reason} appended where writable
    alert_route: aggregate pull counts drops vs records
  - mode: cohort-quiet check errors (supabase unreachable)
    detection: named-check posts FAILURE body to report_to_issue
    alert_route: issue comment
logs:
  where: .soleur/decisions.jsonl (user machine, rotated ~5MB) + issue comments
  retention: user-lifetime local; issue comments permanent
discoverability_test:
  command: bash plugins/soleur/scripts/emit-decision.sh --selfcheck
  expected_output: SOLEUR_EMIT_OK
```

## Infrastructure (IaC)

None — no Terraform-representable resource introduced. The private Slack channel is a
vendor-workspace action inside the existing Jikigai Slack (no Slack provider in repo; same
non-automatable carve-out the alpha-onboarding-motion spec used for the beta-CRM upsert).
The `INNGEST_MANUAL_TRIGGER_SECRET` env already exists for the arming route.

## Architecture Decision (ADR/C4)

### ADR

**ADR-251 (provisional ordinal)** — "Tester-owned local decision log (`.soleur/decisions.jsonl`):
prose-directed emit, field-allowlisted metadata, no egress, tester-initiated aggregate export."
Records: the `.soleur/` sink convention + `.gitignore` self-guard; hook-vs-prose parity table;
NO-ECHO contract; the capture-rate ≠ usage-rate disclosure; relationship to the parked
System-1 eval corpus (enabling action, no eval itself). Authored via `soleur:architecture`;
if the ordinal collides at merge, renumber + sweep `grep -rn 'ADR-251' knowledge-base/project/{plans,specs}/feat-alpha-tester-value-loop/`.

### C4 views

`model.c4`: extend the plugin/hooks container description with the `.soleur/` local sink
(stateful write on user machines — ADR-227 precedent). `views.c4`/`spec.c4`: unchanged.
Enumeration checked against all three files: (a) external human actor — `betaContact`
(Beta Tester / Prospect, model.c4:56) already models the tester; (b) external system —
Slack is a human comms channel with no API integration (deliberate: no automated posting),
so no new edge; email/resend webhook already modeled; (c) container/data-store —
`.soleur/decisions.jsonl` is a description-line extension of the existing plugin container,
not a new element; (d) access relationships — unchanged (tester never touches Jikigai
systems directly).

### Sequencing

ADR authored in this PR describing the target state ("status: adopting" for the decision-log
convention until the first alpha checkpoint pull exercises it).

## Encryption Posture

```yaml
at_rest:
  - store: public.users.cohort_key
    mechanism: Supabase-managed Postgres disk encryption (existing posture for all users-table
      columns; recorded in knowledge-base/legal/audits/encryption-posture-ledger.json)
    defends_against: provider-media disclosure of the database volume
    does_not_defend: account-level access; RLS bypass via service-role (same as all user rows —
      cohort label is low-sensitivity, user-readable via owner-select policy)
    disclosed_as: provider-managed (privacy policy §hosting)
    live_verification: migration COMMENT + LAWFUL_BASIS annotation
in_transit:
  - connection: PATCH /api/admin/cohort + GET /api/admin/analytics?cohort=
    tls: yes (Cloudflare edge → platform, existing)
    cert_verification: on
    does_not_defend: origin-side credential misuse (gated by ADMIN_USER_IDS + service role)
    disclosed_as: HTTPS-only surface
exception: none
```

## Test Scenarios

| # | Scenario | Expected |
|---|---|---|
| T1 | `emit-decision.sh` in a git repo | `.soleur/decisions.jsonl` + `.gitignore`(`*`) created; line validates as JSON with all schema keys |
| T2 | emit with `SOLEUR_DISABLE_DECISION_LOG=1` | exit 0, zero bytes written |
| T3 | two concurrent `emit-decision.sh` invocations | both lines present, each valid JSON (O_APPEND atomicity) |
| T4 | log exceeds 5 MB | rotated to `.1`; new line in fresh file |
| T5 | `--selfcheck` | prints `SOLEUR_EMIT_OK`, exit 0 |
| T6 | welcome-hook in non-vendored git repo | sentinel + welcome JSON emitted (previously silent) |
| T7 | welcome-hook second run same repo | silent (sentinel dedupe) |
| T8 | `alpha-metrics.sh` with no log | prints `SOLEUR_EMIT_ABSENT`, exit 0 |
| T9 | `alpha-metrics.sh` with populated log | per-skill/per-domain counts + first/last ts |
| T10 | `GET /api/admin/analytics?cohort=alpha` | funnel computed over cohort members only |
| T11 | `PATCH /api/admin/cohort` as non-admin | 403 |
| T12 | cohort-quiet check, tester 4d silent | quiet row in report_to_issue comment |
| T13 | cohort-status with runbook present | tally table + mix floor + armed checkpoint state |
| T14 | cohort-status with unreadable source | `UNREADABLE` cell, not zero |

## Open Questions / Risks

- **Slack PA-register coverage** — tester comms channel on existing vendor; verify a PA row
  covers Slack for tester comms or use email until recorded (CLO check at work Phase 2).
- **`guided-tour` flag** — verify on for tester accounts (conversion-optimizer flag).
- **Cohort key write path** — admin PATCH is service-role; the runbook step must run through
  the admin surface, not operator SQL.
- **n=10 statistics** — binaries not percentages; the falsification tree stays the verdict.
- **Cron cadence for cohort-quiet** — arm per-tester at day-3 (+ optional day-7) via the same
  schedule-reminder route; no standing cron needed.

## Deferred (tracked in spec Non-Goals; no issue filings — documented in place per triple test)

- Opt-in telemetry beacon (re-eval: checkpoint pull insufficient for ≥2 testers, or tester
  asks for live observability)
- BYOK delegation flag flip (Side Letter gate)
- Admin-dashboard cohort filter UI (cohort-status covers the operator pull)
- Customer-success agent seat (revisit at cohort ≥5)

## Plan Review record (2026-09-25)

Panel: DHH ✓ · Kieran ✗ (model-capacity error) · code-simplicity ✗ (capacity) ·
architecture-strategist ✗ (capacity) · spec-flow-analyzer ✓ (ran Phase 3 — 12 gaps,
all folded) · named panel: CPO ✓, CMO ✗ (capacity), CTO-devex ✗ (capacity).
Advisor consult ✓ (canonical event contract — partially superseded by DHH cut).

Applied (operator-approved):
- Prose-only emit; hook path + TSV + bash-JSON parsing deleted (DHH).
- Schema slimmed to 10 fields; `emitter_ready` capability machine deleted — day-0 human
  verify (2.1g) + ABSENT/EMPTY markers carry the property (DHH + advisor).
- No lock — O_APPEND printf append is atomic (DHH).
- `arm-checkpoint.sh` prints self-describing reminder_ids; no markdown-table write (DHH).
- cohort-status derives expected ids by convention (DHH).
- Repair pulled off the PR critical path — runs now; Phase 4 = verification sweep (CPO).
- `nudged_at` bookkeeping + assisted/unassisted disclosure in checkpoint template (CPO).
- Non-CC stall fallback (2-week valve) in runbook (CPO).
- Exit-interview section added to runbook v2: WTP $49 + testimonial opt-in + nudge
  disclosure (CPO, closing the only metric that answers the business question).
- ADR-251 gains surface→instrument table + residency pin (hosted emit on Jikigai infra
  would break the Posture-A assumption — evaluated, not assumed) (CPO).

Declined: cohort-quiet keeps the `cohort_key IS NULL` signup listing (only automated
un-tagged-signup detector — SpecFlow gap outweighs the two-jobs aesthetic); rotation kept
(~5 lines, years of headroom at ~200 B/line).

Implementation-time deviations recorded: cohort PATCH lives at `/api/internal/cohort`
(shared-secret bearer, PUBLIC_PATHS narrow entry) — the `/api/admin/` cookie auth cannot
be curled. Art. 30 Slack coverage gap filed as #8896 (register has only the release
webhook + deferred Slack-DM mention; tester-comms channel needs a PA row or recorded
coverage decision).
