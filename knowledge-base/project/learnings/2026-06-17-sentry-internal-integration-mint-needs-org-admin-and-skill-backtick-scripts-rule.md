# Learning: Sentry internal-integration mint needs org:admin (Playwright-only), + skill bodies can't open a backtick with `scripts/`

**Date:** 2026-06-17
**Issue/PR:** #5495 / #5496
**Category:** integration-issues, workflow-patterns

## Problem

Implementing the inline Sentry read CLI (#5495) required minting a read-only Sentry token
(`inline-read-prd` Internal Integration, `[event:read, org:read]`) **by Soleur automation,
not an operator UI step**. Two concrete gotchas surfaced at /work.

## Solution / Key Insights

1. **Creating a Sentry Internal Integration via API needs `org:admin` (or org:integrations) —
   which Soleur's tokens do not have, and an existing internal-integration token cannot create
   another.** Verified live: `SENTRY_IAC_AUTH_TOKEN` is `[event:read, org:read, project:admin,
   alerts:*, project:*]` (no `org:admin`) AND its user is `…@proxy-user.sentry.io` (an internal-
   integration identity, which Sentry blocks from creating sentry-apps). `SENTRY_AUTH_TOKEN` is
   `[org:ci, org:read, project:read, project:releases, project:write]`. So `POST
   /api/0/organizations/<org>/sentry-apps/` is not reachable with any Doppler credential — the
   **Playwright dashboard path is the only mint path**. Probe the token's scopes with
   `GET https://<org>.sentry.io/api/0/` → `.auth.scopes` before assuming an API mint works.

2. **The Sentry dashboard mint IS Playwright-automatable (no human gate) — confirming #5480.**
   `https://jikigai-eu.sentry.io/settings/developer-settings/new-internal/` loaded the full
   authenticated New Internal Integration form (permission dropdowns + Save) with NO
   CAPTCHA/MFA/passkey. The only blocker was **browser-context instability** (closed twice mid-
   form). That is `attempted-blocked-on-tool`, NOT operator-only and NOT `deferred-automation` —
   filed as a `type/chore` tooling-retry (#5506) with a resume recipe, per the work-skill table.
   The a-priori "operator must mint it in the UI" assumption (plan `automation-status: UNVERIFIED`)
   was correctly treated as unverified and disproven by the attempt.

3. **A skill body (`plugins/soleur/skills/*/SKILL.md`) may not contain a backtick reference that
   OPENS with `scripts/`, `references/`, or `assets/`** — `plugins/soleur/test/components.test.ts`
   asserts `body.match(/`(?:references|assets|scripts)\/[^`]+`/g)` is null (the markdown-link
   convention). Two forms pass: a markdown link `[name](../../../../scripts/name.sh)`, OR a
   command invocation whose backtick opens with something else (`` `doppler run … -- scripts/x.sh` ``).
   A bare `` `scripts/x.sh` `` fails. `knowledge-base/…` backtick refs are NOT matched (only the
   three asset dirs). **Prevention:** when wiring a script into a skill body, write it as the full
   `doppler run … -- scripts/x.sh` invocation or a markdown link — never a bare `` `scripts/…` ``.
   This is `bun`-group-only (not the touched-file loop), so it surfaces at the full-suite exit gate.

## Session Errors

- **Bare `` `scripts/sentry-issue.sh` `` / `` `scripts/betterstack-query.sh` `` in incident +
  postmerge SKILL.md** — caught by `components.test.ts` at the bun-group exit gate (2 fail).
  Recovery: doppler-prefixed invocation (incident) + markdown link (postmerge). **Prevention:**
  insight #3 above.
- **`gh issue create --json`** (earlier session phase) — `gh issue create` has no `--json`; print
  the URL from stdout. One-off.

## Tags
category: integration-issues, workflow-patterns
module: sentry, work-skill, plugin-components
related: hr-exhaust-all-automated-options-before, #5480 (vendor-dashboard-mint-presumed-playwright-automatable)
