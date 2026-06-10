---
date: 2026-06-09
topic: slack-release-notify
lane: cross-domain
brand_survival_threshold: single-user incident
status: brainstormed
---

# Brainstorm: Move Release Notifications from Discord to Slack

## What We're Building

Replace the per-release **Discord** announcement in `.github/workflows/reusable-release.yml` with a per-release **Slack** post via an Incoming Webhook, delivered through a new `notify-slack` composite action. The Slack channel is an **internal/team** release feed (high-frequency is fine for the team). The email-to-ops notification is untouched.

A second insight surfaced during brainstorming: a community member muted the Discord `#releases` channel because per-release posts (multiple/day) are too noisy. The current Discord post already suppresses @-mentions (`allowed_mentions:{parse:[]}`), so the fatigue is pure **message volume**, not pings. The fix is a **lower-frequency batched digest**, not a quiet channel. That work is scoped as a **fast-follow** (separate issue), not part of this PR.

## Why This Approach

- **Slot-for-slot swap, contained blast radius.** The Discord release step (`reusable-release.yml:653–707`) is the *only* consumer of `DISCORD_RELEASES_WEBHOOK_URL` in the workflows. No tests assert it; only historical learnings docs reference it. Removing it is clean.
- **Composite action matches precedent.** `notify-ops-email` (`.github/actions/notify-ops-email/action.yml`) is the established pattern for HTTP-POST notifications. `notify-slack` mirrors it: encapsulates the webhook secret as an input, keeps workflow YAML readable, reusable later.
- **Incoming Webhook = YAGNI.** Mirrors the existing Discord webhook model exactly (single URL secret, one `curl` POST). No Slack App / OAuth / bot-token rotation overhead.
- **Digest is the real community fix, deferred deliberately.** A weekly digest is a new scheduled Inngest job + brand-voice content template — its own plan/PR. Industry best practice (Vercel "Ship", GitHub Changelog, Supabase Launch Week, Linear) is batched, curated, predictable-cadence digests over per-event firehoses. Building it now would ~3x this PR's scope.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Discord vs Slack | **Replace** — remove Discord release step | True "move" per operator directive |
| Audience | **Internal/team Slack channel** | Per-release feed is ops-flavored; team tolerates high frequency |
| Delivery mechanism | **Slack Incoming Webhook** | Mirrors Discord webhook pattern; simplest |
| Implementation shape | **`notify-slack` composite action** | Matches `notify-ops-email` precedent; reusable |
| Secret | **`SLACK_RELEASES_WEBHOOK_URL`** (new GH Actions secret) | No fallback chain needed (greenfield) |
| Community release comms | **Weekly digest in Discord — FAST-FOLLOW issue** | Discord stays the community hub; digest IS community content |
| Community gap on removal | **Acceptable** | Member was muting it; GitHub Releases page persists; digest restores better signal |
| Visual design (Phase 3.55) | **N/A** | Pure CI/infra; no UI surface |

## User-Brand Impact

- **Artifact:** the Slack Incoming Webhook URL (`SLACK_RELEASES_WEBHOOK_URL`) and the release-notification path itself.
- **Vectors (operator endorsed all three):**
  1. **Silent failure** — a release ships but no announcement posts (team loses release visibility). Mitigated by `continue-on-error: true` keeping the release green, plus an HTTP-code check that emits `::warning::` on non-2xx (mirrors the Discord step).
  2. **Webhook credential leak** — if the URL leaks in logs/repo, anyone can post arbitrary messages into the channel (spoofing/spam; no data exfil). Mitigated by `::add-mask::` in CI logs + a new gitleaks `slack-webhook-url` rule.
  3. **No direct end-user data impact** — payload is public release notes; no PII.
- **Threshold:** `single-user incident`.

## Open Questions

1. **Slack webhook provisioning (operator dependency).** Creating the Incoming Webhook requires a Slack workspace admin to add it via Slack's app UI and choose the target channel — this is genuinely external (operator's Slack creds). Setting the resulting `SLACK_RELEASES_WEBHOOK_URL` GH secret IS automatable via `gh secret set` (do NOT paste the URL via a `!`-prefixed shell line — `hr-never-paste-secrets-via-bang-prefix`). Plan must produce an exact click-path + automate the `gh secret set` step.
2. **Digest content depth (fast-follow).** Raw "merged PRs this week" list vs. curated narrative (3–5 highlights + collapsed remainder). Strategist recommends curated, matching Vercel/Linear voice. Decide at digest-plan time.
3. **Should the Slack post use plain `text` or Block Kit?** Block Kit gives a richer card (header + release-notes section + link button). Plain `text` is the minimal port of the Discord `content` string. Lean plain `text` for v1 (YAGNI); Block Kit is a trivial later enhancement.

## Domain Assessments

**Assessed:** Engineering, Product, Marketing, Operations, Legal (Sales, Finance, Support not relevant)

### Engineering (CTO lens)

**Summary:** Contained single-step swap at `reusable-release.yml:653–707`; only release consumer of the Discord secret; no test breakage. Add `notify-slack` composite action (mirrors `notify-ops-email`), new `SLACK_RELEASES_WEBHOOK_URL` secret, and a gitleaks `slack-webhook-url` rule. Payload must be transformed to Slack schema (`text`/`blocks`, `icon_url`, no `allowed_mentions`).

### Marketing / Community (retention-strategist lens)

**Summary:** Per-release community pings are the proven fatigue source. Right fix is a weekly (or per-minor) **batched digest in Discord** (community content), curated not raw, fitting the existing `cron-weekly-*` Inngest pattern. Ship the Slack internal move now; do the digest as a fast-follow. Reserve any future @-mention to an opt-in role for majors only.

### Product (CPO lens)

**Summary:** The notification-fatigue complaint is a real UX signal; the move cleanly separates the firehose (internal Slack, push) from the signal (community digest, batched). Removing the per-release community post temporarily is acceptable given the member was already muting and the Releases page persists.

### Operations

**Summary:** Secret provisioning is manual (no Doppler→GH or Terraform sync for release webhooks). New secret is a single `gh secret set`; the Slack-side webhook creation is an operator step requiring workspace admin — must be given an exact click-path, not deferred vaguely.

### Legal (CLO lens)

**Summary:** No regulated-data surface. Payload is public release notes posted to a webhook; no PII, no contract/ToS surface beyond standard Slack incoming-webhook usage. Not a blocking domain.

## Productize Candidate

`release-digest` — a recurring weekly community release-digest job (scheduled Inngest function). Filed as the fast-follow issue below.

## Session Errors

None.
