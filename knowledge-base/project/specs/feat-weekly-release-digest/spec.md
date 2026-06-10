---
feature: weekly-release-digest
lane: cross-domain
brand_survival_threshold: single-user incident
status: draft
brainstorm: knowledge-base/project/brainstorms/2026-06-10-weekly-release-digest-brainstorm.md
issue: 5080
created: 2026-06-10
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- IaC review note: no servers/cloud resources are provisioned. The only infra touchpoints
are Discord-side API objects (webhook, role) created via the existing DISCORD_BOT_TOKEN bot
API, a Doppler secret write done in-session, and the Sentry cron monitor which IS routed
through Terraform (TR7, infra/sentry/cron-monitors.tf). -->

# Spec: Weekly Community Release Digest (Discord)

## Problem Statement

PR #5078 moved per-release notifications to an internal Slack feed and removed the per-release
Discord post, leaving the community `#releases` channel with no content source. The community
needs a batched, curated release surface — a member had muted `#releases` over per-release
volume (multiple posts/day). Issue #5080's re-evaluation gate is met: #5078 merged 2026-06-10
and the Slack feed is verified live in prod (v3.154.0/v3.154.1).

## Goals

- G1: A weekly curated digest ("what shipped + why it matters") posts to Discord `#releases`
  every Friday ~15:00 UTC, fully unattended.
- G2: The digest never silently misses a week: LLM failure degrades to a deterministic
  template; a zero-release week posts a short quiet-week note.
- G3 (amended 2026-06-10): The community learns the cadence changed (one-time
  announcement). The majors opt-in ping path moved to tracking issue #5136 (NG6).
- G4: Brand and legal posture is preserved: no internal content, no contributor PII, no
  un-suppressed mentions, no premature security detail in public posts.
- G5: Failure is observable without SSH: Sentry monitor red iff the weekly Discord post did
  not land.

## Non-Goals

- NG1: Contributor attribution / name-checks (legal fork deferred — would trigger LIA +
  Article 30 + three-doc lockstep; revisit as its own issue).
- NG2: Cross-posting the digest to X/LinkedIn/blog.
- NG3: Re-enabling any per-release Discord posting.
- NG4: Discord thread auto-creation / engagement mechanics.
- NG5: Any app UI surface (Discord post content only — no wireframes, same boundary as #5079).
- NG6 (amended 2026-06-10, 5-agent plan review + operator decision): the brainstormed
  PR-2 extras — `@release-notify` opt-in role (former FR8), immediate majors post (former
  FR9), digest markdown persistence (former FR10) — are CUT and tracked in a
  deferred-scope-out issue with re-evaluation criteria (member requests pings / a major
  where digest latency mattered / a persistence consumer materializes). If revived:
  native Discord onboarding role-picker (not a reaction-poll) and Inngest-substrate
  majors detection (not a CI secret copy) are the reviewer-endorsed shapes.

## Functional Requirements

(Single PR — former PR-2 extras moved to NG6 / tracking issue #5136, 2026-06-10.)

- FR1: New pure-TS Inngest cron `cron-weekly-release-digest` (model: `cron-weekly-analytics.ts`
  shape; ADR-033 I1/I2/I5), schedule Friday ~15:00 UTC, plus auto-derived manual-trigger event.
- FR2 (amended 2026-06-10): Enumerate GitHub Releases published in the deterministic
  7-day window ending Friday via raw `fetch` against the REST API with a minted App
  installation token scoped `permissions: { contents: "read" }, repositories: ["soleur"]`
  (`hr-github-app-auth-not-pat` — ambient `GH_TOKEN` is empty in the prod container).
  Highlight-eligible iff tag matches `/^v\d/` or `/^web-v\d/` (anchored — `vinngest-v*`
  starts with `v` but not `v<digit>`); other streams count only toward the remainder
  aggregate.
- FR3: Curate via a direct Anthropic Messages API call (`cron-compound-promote.ts:423`
  precedent: operator key, timeout, input truncation, shape-invalid Sentry event): 3–5
  highlights with "why it matters" framing in brand voice (prompt loads brand guide `## Voice`
  + `### Discord` channel notes), plus an aggregated remainder line ("…plus N more releases,
  vA → vB").
- FR4: On LLM failure (timeout, non-2xx, shape-invalid), fall back to a deterministic template:
  rank by conventional-commit type (`feat` > `fix` > `chore`), verbatim release-note titles.
  The week is posted either way.
- FR5: Zero highlight-eligible releases in the window (including an infra-stream-only
  week): post a one-line quiet-week note; heartbeat green.
- FR6 (amended 2026-06-10, spec-flow P0-2): POST to `DISCORD_RELEASES_WEBHOOK_URL` ONLY —
  no `DISCORD_WEBHOOK_URL` fallback. A missing/empty/dead primary is a failure: Sentry
  captureException + `ok:false` heartbeat (red monitor). Rationale: a #general fallback
  keeps the monitor green while #releases stays dead, contradicting G5, and posts brand
  content to the wrong channel.
- FR7 (amended 2026-06-10): One-time cadence-change announcement post ("#releases is now
  a weekly digest") at launch — drafted per brand guide, operator-approved, POSTed
  directly via webhooks (#general + #releases); include a direct note to the affected
  member if reachable, outcome recorded in the ship summary.

## Technical Requirements

- TR1: **Closed input set:** LLM prompt sources are published GitHub Release bodies ONLY — no
  PR diffs, issue bodies, KB content, or unreleased material.
- TR2: **Security down-detail rule:** releases matching security-fix class (label/title
  heuristics) render title-only — never LLM-elaborated.
- TR3: **Verbatim-or-less invariant:** highlights may summarize but never add technical detail
  absent from the source release body. Names, links, and version numbers come from API data,
  never generated (2026-03-24 hallucinated-author learning).
- TR4: **PII-strip:** contributor handles/author metadata removed from LLM input and digest
  output (keeps the non-regulated posture; no gdpr-gate required).
- TR5: Every webhook payload includes `allowed_mentions: {parse: []}` (API-level). Entity-escape untrusted changelog text;
  2000-char-aware truncation.
- TR6 (amended 2026-06-10): Sentry monitor slug `cron-weekly-release-digest` (matches the
  newer cron-* slug family) via `postSentryHeartbeat`; the handler CATCHES any step
  failure and SENDS `ok:false` before returning (never throw-without-heartbeat —
  spec-flow P0-1); `ok:true` iff the Discord POST returned 2xx. Do not route through
  `resolveOutputAwareOk` (GitHub-issue-shaped helper).
- TR7: Five-registry lockstep in PR-1 (2026-06-05 learning, machine-enforced):
  `app/api/inngest/route.ts`, `cron-manifest.ts` `EXPECTED_CRON_FUNCTIONS`, registry-count
  test, `infra/sentry/cron-monitors.tf` (byte-identical slug), `apply-sentry-infra.yml`
  `-target`.
- TR8: Webhook POST isolated in its own `step.run` (memoization bounds double-post windows);
  deterministic week-key window makes manual-trigger duplicates acceptable (documented).
- TR9: Secret hygiene: webhook URL never interpolated into logs/Sentry events; rotation
  runbook line in the plan; gitleaks `discord-webhook-url` rule already covers repo-side.
- TR10: Webhook provisioned via the `DISCORD_BOT_TOKEN` bot API
  (`POST /channels/{id}/webhooks`, requires `MANAGE_WEBHOOKS` — verify the bot's permission at
  plan time and grant via API if absent); resulting URL written to Doppler prd in-session per
  `wg-block-pr-ready-on-undeferred-operator-steps`. Secret value never pasted via `!`-prefix.
- TR11: Tests follow the cron test gotchas (2026-06-02 learning): relative `./_cron-shared`
  import, registry count re-derived, no `*/N` cron syntax inside JSDoc, non-vacuous redaction
  assertions.

## Acceptance Criteria

- AC1: Manual-trigger dry run posts a correctly formatted digest to `#releases` with suppressed
  mentions and ≤2000 chars.
- AC2: With the Anthropic call forced to fail, the deterministic fallback digest posts and the
  heartbeat stays green.
- AC3: With zero releases in the window, the quiet-week note posts; heartbeat green.
- AC4: With the webhook URL broken, the Sentry monitor goes red (`ok:false`) — no silent miss.
- AC5: A security-class release appears title-only in the digest.
- AC6: No contributor handle appears in LLM input (assertable on the prompt builder) or in the
  posted content.
- AC7: Registry-count and cron-sweep tests pass with the new function registered in all five
  places.

## Brand-guide amendment

Add a "Release Digest" subsection under brand guide `### Discord` channel notes defining the
format and highlight rubric (target-user impact over commit volume) — PR-1, since the prompt
loads it.

## Stale-doc / hygiene sweep (ship time)

- Promote #5080 milestone/priority (currently Post-MVP / p3-low; the comms gap is live).
- Extend the Anthropic vendor row scope note in `knowledge-base/legal/compliance-posture.md`
  with the digest cron's direct API usage.
- Add a one-line dedupe rule to `cron-community-monitor`'s prompt re: weekly digest content
  (lands whenever that cron un-pauses; P3).
