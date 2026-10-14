---
date: 2026-06-10
topic: weekly-release-digest
lane: cross-domain
brand_survival_threshold: single-user incident
status: brainstormed
issue: 5080
---

# Brainstorm: Weekly Community Release Digest (Discord)

## What We're Building

A weekly, LLM-curated release digest posted to the community Discord `#releases` channel by a
**pure-TS Inngest cron** (`cron-weekly-release-digest`). Every Friday ~15:00 UTC it enumerates
the week's GitHub Releases (plugin `v*` + web-platform `web-v*` streams), asks the Anthropic
Messages API to pick 3–5 highlights and write "what shipped + why it matters" in brand voice,
and POSTs the result to a newly provisioned `DISCORD_RELEASES_WEBHOOK_URL`. If the LLM call
fails, a deterministic `feat > fix > chore` template renders an uncurated-but-correct digest —
the week is never silently missed.

This restores the community release surface removed in #5078 (per-release posts moved to
internal Slack) at the batched cadence the community actually wanted: a member had muted
`#releases` over multiple-posts-per-day volume. The re-evaluation gate on #5080 is verified
met: PR #5078 merged 2026-06-10 and the "Post to Slack (release)" step succeeded in prod on
releases v3.154.0 and v3.154.1.

V1 scope also includes (operator pulled all extras in): a one-time cadence-change announcement
(so the muted member learns the fix exists — Discord mutes persist until manually reversed), an
opt-in `@release-notify` role pinged only for majors, an immediate out-of-band post for major
releases (capped at one/week, replacing that week's slot if within ~48h), and persisting each
digest as a markdown artifact for calendar visibility / future cross-posting / AEO.

## Why This Approach

- **Pure-TS cron is the only shape that runs today.** Claude-*spawn* crons with non-GitHub
  egress sit in the Tier-2 defer set (`TIER2_DEFERRED_CRONS`, `_cron-shared.ts:244`) post-#5046;
  a spawn-based digest would be born paused. Direct Messages API calls from a TS handler are
  outside the tier system entirely — live precedent: `cron-compound-promote.ts:423`
  (`fetch("https://api.anthropic.com/v1/messages")` with operator key, timeout, truncation,
  shape-invalid Sentry events). Posting precedent: `cron-weekly-analytics.ts:221–250` already
  POSTs to a Discord webhook from a TS step.
- **LLM + deterministic fallback** balances the quality bar ("why it matters" narrative, the
  Vercel Ship / Linear model) against the automate-everything principle for non-technical
  operators — no recurring weekly approval touchpoint. Brand risk is bounded by a closed input
  set and deterministic safety rails (below), not by prompt instructions alone.
- **New `#releases` webhook, not `#general` reuse.** The old `DISCORD_RELEASES_WEBHOOK_URL` was
  fully deleted with #5078 (GH secret removed per `feat-slack-release-notify/tasks.md` 5.6;
  never in Doppler). Re-provisioning keeps the channel taxonomy honest and revives the channel
  the muted member actually watches. Creation is expected automatable via the existing
  `DISCORD_BOT_TOKEN` (bot API webhook creation) — verify at plan time.
- **Quiet-week note over silent skip.** `#releases` is digest-only after #5078; a skipped week
  is indistinguishable from a broken job for both community and operator. A one-line post keeps
  the cadence promise and makes the failure mode observable.

## User-Brand Impact

- **Artifacts:** the new Discord `#releases` webhook URL (public-channel write credential) and
  the digest content itself (first fully unattended LLM-generated public brand-voice surface —
  every existing public-posting path has an approval gate or posts pre-approved content).
- **Vectors (operator endorsed all):**
  1. **Webhook credential leak** — leak enables brand-voice spoofing into the *public community
     channel* (higher blast radius than #5079's internal Slack case). Mitigations: Doppler-held
     secret, existing gitleaks `discord-webhook-url` rule (`.gitleaks.toml:235`), no-log/Sentry-
     scrub assertion, rotation runbook line (channel webhooks regenerate in seconds).
  2. **Silent failure** — a missed run = a full week dark. Mitigations: Sentry monitor with
     heartbeat `ok` gated on the Discord POST returning 2xx (the post IS the output contract —
     stricter than weekly-analytics' warn-only), deterministic fallback on LLM failure,
     quiet-week note policy.
  3. **Private/internal content in a public post** — Mitigations: closed input set (published
     GitHub Release bodies ONLY — no PR diffs, issues, KB, or unreleased content), security
     down-detail rule (`type/security`-class releases render title-only, no LLM elaboration —
     don't widen the exploit window before users patch), verbatim-or-less invariant (summarize,
     never add technical detail absent from the source), contributor handles stripped from
     LLM input and output.
- **Threshold:** `single-user incident`.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Substrate | **Pure-TS Inngest cron** (model: `cron-weekly-analytics.ts`) | Claude-spawn = Tier-2 defer trap; pure TS runs today |
| Curation | **LLM via direct Anthropic Messages API + deterministic `feat>fix>chore` fallback** | compound-promote precedent; quality without a weekly operator touchpoint; degrades to correct-but-plain, never to silence |
| Channel/webhook | **`#releases` via new `DISCORD_RELEASES_WEBHOOK_URL`** in Doppler prd; fallback `\|\| DISCORD_WEBHOOK_URL` with `reportSilentFallback` | Old secret fully deleted with #5078; channel taxonomy + muted-member fix |
| Webhook provisioning | **Automate via `DISCORD_BOT_TOKEN` bot API** (verify permission at plan time); operator click-path only as documented fallback | `hr-exhaust-all-automated-options-before` |
| Cadence | **Friday ~15:00 UTC**, window = 7 days ending Friday (deterministic week-key) | Week-wrap voice; EU-centric community; idempotent across retries/manual triggers |
| Release streams | **Plugin `v*` + web-platform `web-v*`**; infra streams (e.g. `inngest-v*`) excluded from highlights, counted in remainder | Both are user-facing product surfaces; infra is off-brand noise |
| Content shape | 3–5 highlights + aggregated remainder ("…plus N more releases, v3.148.0 → v3.154.1"); 2000-char truncation-aware | Heavy weeks are the norm (~50–100 releases/wk); raw lists are noise |
| Zero-release week | **Short quiet-week note** + green heartbeat | Digest-only channel must not look abandoned; failure stays distinguishable |
| Contributor attribution | **Strip handles in v1** (LLM input AND output) | Keeps non-regulated surface: no gdpr-gate, no LIA, no Article 30 row, no 3-doc lockstep. Revisit as own issue if recognition wanted |
| Mention safety | `allowed_mentions: {parse: []}` on every payload | API-level; sed-stripping is bypassable (2026-03-05 learning) |
| Brand voice | Prompt loads brand guide `## Voice` + `### Discord` channel notes; add a "Release Digest" subsection to brand guide | CMO; matches discord-content pattern |
| V1 extras | **All four in scope:** one-time cadence announcement, `@release-notify` opt-in role (majors-only ping), immediate majors post (≤1/wk, replaces slot if within ~48h), persist digest as markdown artifact | Operator decision |
| Delivery | **Two sequenced PRs:** PR-1 core cron + webhook + announcement; PR-2 role + majors trigger + persistence | Reviewable slices; live gap closes first; cron lockstep lands once |
| Observability | Sentry monitor `scheduled-release-digest` via `postSentryHeartbeat`; `ok` gated on Discord 2xx; five-registry lockstep | hr-observability-as-plan-quality-gate; 2026-06-05 lockstep learning |
| GitHub auth | Minted App installation token, narrowed scope (`contents:read`-class) | `hr-github-app-auth-not-pat`; `GH_TOKEN` is empty in prod container |
| Visual design (Phase 3.55) | **N/A** | Discord post content, no app UI surface (same boundary as #5079) |

## Open Questions

1. **Bot-API webhook creation permission.** Does the existing `DISCORD_BOT_TOKEN` carry
   `MANAGE_WEBHOOKS` on `#releases`? Verify at plan time; if not, exact operator click-path +
   in-session `doppler secrets set` (never via `!`-prefix — `hr-never-paste-secrets-via-bang-prefix`).
2. **Markdown persistence mechanics (PR-2).** `distribution-content/` file via bot PR (inherits
   lint + calendar) vs. plain KB artifact. The content-publisher `status:` semantics assume
   pre-approval — an auto-generated auto-approved file subverts that gate's meaning; decide at
   plan time whether to post-record (file documents what was already posted) instead.
3. **Role self-assign flow (PR-2).** Reaction role vs. Discord native role-subscription; what
   the bot can configure via API vs. one-time admin setup.
4. **Major detection (PR-2).** Semver major on which stream(s); plugin is v3.x (rare majors) —
   confirm trigger definition.
5. **Anthropic vendor-row scope note.** `compliance-posture.md` Anthropic row enumerates CI +
   #2720 clustering; extend with the digest cron's API usage at ship time (CLO, cheap one-liner).
6. **cron-community-monitor dedupe.** Once it un-pauses, its daily digest will re-summarize the
   weekly digest content in #releases; add a one-line dedupe rule to its prompt (P3).

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support
(Operations, Sales, Finance not relevant; triad CPO+CLO+CTO mandatory via user-brand-critical tag)

### Engineering (CTO)

**Summary:** Pure-TS handler + direct Anthropic API is the only non-dead-on-arrival shape
(Tier-2 defer set governs claude-spawn crons; community-monitor remains deferred for exactly
this non-GitHub-egress reason). Releases API via minted App token; ~50–100 releases/week makes
curation load-bearing; five-registry lockstep machine-enforced; heartbeat must be output-aware
(Discord 2xx), not exit-code-green. Estimate: 1–2 days for core.

### Product (CPO)

**Summary:** The comms gap is live (not hypothetical) since #5078 — promote #5080 out of
p3/Post-MVP into Phase 4. Dominant vector shifted vs #5079: accidental internal-content
publication is the net-new risk. Curation model + source allowlist were the two decisions to
lock (now locked). Define a success metric (member un-mutes, reactions, opt-ins) and capture a
#releases baseline before launch.

### Legal (CLO)

**Summary:** With PII-strip + published-release-bodies-only sourcing, this stays a non-regulated
surface (no gdpr-gate, no Article 30/policy changes — same posture as #5079). Security releases
need a down-detail rule (amplification ≠ first disclosure, but LLM elaboration can widen the
exploit window). Webhook repo-side leak surface already covered by gitleaks `discord-webhook-url`
(`.gitleaks.toml:235`); runtime no-log/scrub + rotation runbook are plan ACs. EU AI Act Art. 50:
out of scope for a release digest.

### Support (CCO)

**Summary:** `#releases` is currently dead and the digest is its sole future content source —
never skip silently. A weekly post does NOT un-mute the affected member; the one-time
announcement (+ direct note) is what lands the fix. Webhook posts can't create threads (needs
bot token) — engagement mechanics are a bot-path concern. Friday ~15:00 UTC fits the small
EU-centric community. Define success metrics; add community-monitor dedupe rule later.

### Marketing (CMO)

**Summary:** Brand guide exists with Discord channel notes and announcement examples — the
digest prompt must load `## Voice` + `### Discord`, and a "Release Digest" subsection should be
added defining the highlight rubric (target-user impact, not commit volume). This is the first
fully unattended public brand-voice surface — bounded by deterministic rails. Persisted digest
doubles as `feature-tweet` feeder and AEO changelog surface (PR-2). Ownership split: Support
owns channel/cadence; Marketing owns voice template + selection rubric.

## Research Reconciliation

- Repo-research's claim "no cron calls the Anthropic SDK/API directly" was a **false negative**
  — verified by direct grep: `cron-compound-promote.ts:423` fetches `api.anthropic.com`. CTO's
  precedent claim stands; the LLM-curation path is viable without Tier-2 entanglement.
- CTO's "DISCORD_RELEASES_WEBHOOK_URL is a GH Actions secret (orphaned)" was stale by hours —
  repo-research verified the secret was already **deleted** (tasks.md 5.6 executed) and never
  existed in Doppler. Net: new webhook provisioning is required, not a copy.

## Productize Candidate

None beyond the feature itself — the digest cron IS the productized recurring artifact
(recorded as such in the #5079 brainstorm).

## Session Errors

None.
