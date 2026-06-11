---
date: 2026-06-10
type: feat
feature: weekly-release-digest
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issue: 5080
spec: knowledge-base/project/specs/feat-weekly-release-digest/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-06-10-weekly-release-digest-brainstorm.md
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- IaC review note: the only Terraform-managed surface is the Sentry cron monitor
(routed through infra/sentry/cron-monitors.tf + apply-sentry-infra.yml auto-apply).
Discord-side objects (webhook) are vendor-API writes executed in-session via the
existing DISCORD_BOT_TOKEN; the Doppler prd secret write is executed in-session with
explicit operator ack. No servers, no manual dashboard steps. -->

# Plan: Weekly Community Release Digest (Discord) — #5080

## Overview

Build `cron-weekly-release-digest`, a pure-TS Inngest cron that posts a curated weekly
release digest to the community Discord `#releases` channel every Friday 15:00 UTC.
Curation via a direct Anthropic Messages API call (3–5 highlights, brand voice) with a
deterministic `feat > fix > chore` fallback. **Single PR** (`Closes #5080`).

Post-5-agent-review scope: the brainstorm's PR-2 extras (`@release-notify` opt-in role,
immediate majors post, markdown persistence) are CUT per unanimous reviewer convergence +
operator decision (2026-06-10) — tracked in a deferred-scope-out issue created at plan
time (Phase 7), re-evaluated if a community member requests pings or a persistence
consumer materializes. Spec FR8/FR9/FR10 amended to Non-Goals.

## Premise Validation

All cited premises verified live on 2026-06-10: #5079 CLOSED via PR #5078 (merged
2026-06-10T16:37Z); "Post to Slack (release)" step `success` in release runs for
v3.154.0/v3.154.1 (re-evaluation gate met); `DISCORD_RELEASES_WEBHOOK_URL` deleted from
GH secrets and absent from Doppler (new provisioning required); `cron-weekly-analytics.ts`
Discord POST precedent at lines 221–250; `cron-compound-promote.ts` direct Anthropic call
(`ANTHROPIC_MODEL = "claude-sonnet-4-6"` at :66, `fetch("https://api.anthropic.com/v1/messages")`
at :423, `withTimeout` at :211, `stop_reason` check at :437–440).

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| Sentry slug `scheduled-release-digest` (TR6) | Newer crons use the `cron-*` slug family | Slug `cron-weekly-release-digest`, TF resource `sentry_cron_monitor.cron_weekly_release_digest`; spec TR6 amended |
| Five-registry lockstep (TR7) | Confirmed: route.ts asserts 52 entries (`function-registry-count.test.ts:135`); manifest has **40** crons (awk-counted; earlier "41" grep-counted a comment); apply-sentry-infra.yml auto-applies `-target=sentry_cron_monitor.*` on merge | Route 52→53; manifest set-equality test forces the entry (no count literal); add `-target` line |
| Tag streams "plugin `v*` + web `web-v*`; e.g. `inngest-v*` excluded" | Actual tag families: `v*` (968), `web-v*` (810), `telegram-v*` (29), **`vinngest-v*`** (17). `inngest-v*` does NOT exist, and `vinngest-v*` STARTS WITH `v` — a naive `v*` prefix match would headline infra bootstrap releases (Kieran P0) | Partition anchors `/^v\d/` and `/^web-v\d/`; load-bearing fixtures: `vinngest-v1.1.12` (v-prefix collision) + `telegram-v0.1.1` (real excluded release stream) |
| FR2 "via Octokit" | Plan prescribes raw `fetch` with minted App token (sibling convention) | Spec FR2 amended |
| Brand-guide rules "loaded by the cron at runtime" (early draft) | `docker_context: "apps/web-platform"` (web-platform-release.yml:36) — `knowledge-base/` is NEVER in the container image; a runtime read is dead code that falls to its fallback on every prod run (simplicity P0-1 + architecture P1-1, independently verified) | Inline constant is AUTHORITATIVE; unit test asserts byte-for-byte sync with the brand-guide subsection (lockstep pattern) |
| `.env.example` should carry the new secret | Zero DISCORD entries (Doppler-only convention) | No .env.example edit |

## User-Brand Impact

(Carried forward from brainstorm `## User-Brand Impact` — operator endorsed all vectors.)

- **If this lands broken, the user experiences:** a dead `#releases` channel (digest never
  posts — silent failure) or an embarrassing/wrong public post (LLM elaboration, mention
  ping, internal content) attributed to the Soleur brand.
- **If this leaks, the user's [data / workflow / money] is exposed via:** the webhook URL
  is a public-channel write credential — a leak enables brand-voice spoofing into the
  community channel. No end-user data is processed (PII-strip + closed input set).
- **Brand-survival threshold:** single-user incident.

CPO sign-off: covered by brainstorm-phase CPO assessment (carry-forward;
`requires_cpo_signoff: true` in frontmatter). `user-impact-reviewer` runs at review time.

**Named residuals (architecture + post-implementation review — the canonical
accepted-residual ledger):**

1. Prompt injection: the "closed input set" (published release bodies) derives from PR
   bodies external contributors can influence. Rails: JSON-schema validation,
   verbatim-or-less tag allowlist + dedupe, `allowed_mentions: {parse: []}`, backslash-
   first markup escaping, URL stripping in free-text fields, 2000-char cap, deterministic
   fallback. Blast radius: plain non-clickable text in #releases.
2. Fallback-verbatim titles: the deterministic fallback renders release titles verbatim
   by contract — brand-banned vocabulary in a PR title would post as-is. Mitigant outside
   the diff: brand-guide GitHub rule keeps PR titles technical. Accepted.
3. Plain contributor names: PII-strip removes @handles/emails/Co-Authored-By; a free-text
   name in already-published release notes passes through. Already-public data; accepted.
4. Infra-only weeks post the quiet-week line (excluded-stream releases are not
   enumerated) — by design per AC8; brand-guide quiet-week rule amended to match.

## Implementation Phases

### Phase 0 — Preconditions (probes, no code)

0.1 Discord probes (read-only): read `DISCORD_BOT_TOKEN` + `DISCORD_GUILD_ID` via
    `doppler secrets get ... --plain` (read-only), then
    `curl -sS --max-time 10 -H "Authorization: Bot $TOKEN" https://discord.com/api/v10/guilds/$GUILD/channels`
    → record the `#releases` channel id. Probe BOTH permissions the plan needs:
    (a) `MANAGE_WEBHOOKS` (`GET /channels/<id>/webhooks` — 403 means missing, fall to
    5.2's grant path); (b) message-read (`GET /channels/<id>/messages?limit=1` — needed
    by AC13(a)'s post-merge assertion; spec-flow NEW-3).
0.2 Confirm `ANTHROPIC_API_KEY` present in Doppler prd (compound-promote already consumes
    it in prod — confirmation, not setup).
0.3 Confirm release-notes shape: `gh api 'repos/jikig-ai/soleur/releases?per_page=5' --jq '.[0] | {tag_name, published_at, body: (.body | length)}'`.

### Phase 1 — Failing tests first (`cq-write-failing-tests-before`)

Create `apps/web-platform/test/server/inngest/cron-weekly-release-digest.test.ts`
(matches vitest node-project glob `test/**/*.test.ts`; runner:
`cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-weekly-release-digest.test.ts`).
Follow the cron test gotchas (2026-06-02 learning): relative `./_cron-shared` import guard,
no `*/N` inside JSDoc, non-vacuous redaction assertions. Heartbeat assertions (Kieran P1):
`postSentryHeartbeat` silently skips when Sentry env vars are unset/malformed
(`_cron-shared.ts:185–199`) — the suite MUST either set shape-valid Sentry env and assert
the mocked fetch URL contains `?status=error`, or `vi.mock("./_cron-shared")` and assert
call args `{ ok: false, sentryMonitorSlug: "cron-weekly-release-digest" }`. Test scenarios
listed below.

### Phase 2 — Handler `apps/web-platform/server/inngest/functions/cron-weekly-release-digest.ts`

Shape: pure-TS, modeled on `cron-weekly-analytics.ts` (registration verified: `retries: 1`,
`concurrency [{scope:"fn",limit:1},{scope:"account",key:'"cron-platform"',limit:1}]`,
triggers `[{ cron: "0 15 * * 5" }, { event: "cron/weekly-release-digest.manual-trigger" }]`).
ADR-033 invariants I1 (step.run), I2 (operator key, no BYOK), I5 (deterministic return).
**Three `step.run`s** (simplicity P1-1 — only I/O earns memoization; pure computation runs
inline; sibling precedent `cron-kb-template-health.ts` has 3):

1. `fetch-releases` — mint App installation token with
   `permissions: { contents: "read" }, repositories: ["soleur"]` (Kieran P2-4 — the
   default omitted-permissions form grants the FULL installation; do not reuse the wider
   `ISSUE_CREATOR_CRON_TOKEN_PERMISSIONS`; `hr-github-app-auth-not-pat` — ambient
   `GH_TOKEN` is empty in prod). `fetch` GitHub REST
   `/repos/jikig-ai/soleur/releases?per_page=100`; filter `published_at` in the window;
   exclude drafts/prereleases. **Window math is a pure function, computed inline before
   the step:** end = most recent Friday 15:00 UTC ≤ now; window = `(end − 7d, end]`
   (half-open, end-inclusive — a release published exactly Friday 15:00:00 belongs to the
   closing week). Week key = ISO date of window end. `/releases` orders by `created_at`;
   `per_page=100` covers any realistic week (~50–100), residual documented.
   **Partition (Kieran P0):** highlight-eligible iff tag matches `/^v\d/` or `/^web-v\d/`
   (anchored with the digit — `vinngest-v1.1.9` starts with `v` but NOT `v<digit>`);
   everything else (`telegram-v*`, `vinngest-v*`, future families) counts toward the
   remainder aggregate only. **Sanitize runs inside this step (pure):** drop `author`
   fields; strip `@handle` tokens, email addresses, and `Co-Authored-By:` lines (ASCII
   regexes — release bodies derive from PR-body Changelogs; gdpr-gate finding); security
   down-detail: release whose name/body matches
   `/security|vulnerab|CVE-\d|xss|rce|injection|privilege escalation/i` → title-only
   entry, body withheld from LLM input (title/body heuristic — GitHub releases carry no
   labels; documented residual); per-release body truncation (compound-promote guard).
2. `curate` — direct Anthropic Messages API call (compound-promote shape: `withTimeout`,
   `max_tokens`, `stop_reason` check, JSON-shape validation with Sentry event on
   invalid). Model: pin the concrete ID `claude-sonnet-4-6` (matches
   `cron-compound-promote.ts:66`). Call-site comment (ADR-053; direction per
   architecture review): "Never-downgrade-shaped: unattended public brand-voice surface
   at single-user-incident threshold — judgment-adjacent, NOT a mechanical step; do not
   sweep to haiku. Concrete ID per ADR-053 cron-constants lifecycle; registry
   consolidation deferred to #5106." Prompt embeds the `#### Release Digest` rules as an
   **authoritative module constant** (NO runtime file read — `knowledge-base/` is not in
   the container image; the constant↔brand-guide sync is asserted by a unit test, see
   Phase 4). LLM output schema: `{ highlights: [{tag, title, why}] }` — **highlights
   only** (simplicity P1-3): the remainder line is computed by code from data the handler
   already holds, never echoed through the model. **Anthropic failure handling is
   caught INSIDE this step** (returns a fallback marker) so a transient LLM error does
   not consume the function retry; the deterministic fallback (rank `feat:` > `fix:` >
   `chore:` from release names, verbatim titles) renders downstream.
3. `post-discord` — **one renderer over one intermediate shape** (simplicity P1-2): LLM
   path, deterministic fallback, and quiet week all produce `{highlights, remainder}`
   (quiet week = empty highlights → one-line note); a single render function enforces
   entity-escaping FIRST, then 2000-char truncation (escape-before-truncate — escaping
   must not re-expand a truncated payload; Kieran P2-6), `allowed_mentions: {parse: []}`
   always, webhook identity `username: "Soleur Releases"` (2026-02-19 learning).
   POST via a **shared `postDiscordWebhook` helper added to `_cron-shared.ts`**
   (architecture P2-4 + `hr-write-boundary-sentinel-sweep-all-write-sites`:
   mentions-suppressed default, never-log-URL discipline, returns status; existing
   bare-`{content}` sites are NOT migrated in this PR — helper is for new sites, noted
   for #3739-class follow-up). Target: `process.env.DISCORD_RELEASES_WEBHOOK_URL` ONLY —
   **no #general fallback** (spec FR6 as amended; a fallback keeps the monitor green
   while #releases is dead, and posts brand content to the wrong channel). Missing or
   empty secret → `Sentry.captureException` + **throw**. Non-2xx → **throw**. The step
   THROWS so Inngest's `retries: 1` grants one step retry on transient failure
   (spec-flow NEW-1 — the in-step-catch shape would suppress retries).
4. Failure→heartbeat shape (Kieran P1 — the REAL precedent is the
   **`cron-weekly-analytics.ts` tail**, NOT cron-oauth-probe's in-step catch): a
   handler-level `try/catch` wraps all steps; on caught failure (post-retry-exhaustion
   `StepError` included) it sends the heartbeat as a **direct best-effort call**
   (object signature: `await postSentryHeartbeat({ ok: false, sentryMonitorSlug:
   SENTRY_MONITOR_SLUG, cronName: FUNCTION_NAME, logger })` wrapped in its own
   try/catch), then RETURNS `{ ok: false, ... }` (never rethrow — a check-in must
   always be attempted). Success path sends `ok: true` iff the Discord POST returned
   2xx (the post IS the output contract, including the quiet-week note). Corollary
   (named per spec-flow): catch-and-return marks the Inngest run COMPLETED — Inngest-
   native failure events never fire; the Sentry monitor is the sole liveness layer by
   design (the watchdog checks registration only). Do NOT use `resolveOutputAwareOk`.

### Phase 3 — Five-registry lockstep (machine-enforced)

1. `apps/web-platform/app/api/inngest/route.ts` — import + functions-array entry (52→53;
   update the count assertion in `function-registry-count.test.ts:135`).
2. `apps/web-platform/server/inngest/cron-manifest.ts` — add `"cron-weekly-release-digest"`
   to `EXPECTED_CRON_FUNCTIONS` (40 entries today; test (e) is set-equality against the
   file list, no count literal). Manual-trigger event derives automatically →
   `/soleur:trigger-cron` picks it up for free.
3. `apps/web-platform/test/server/inngest/function-registry-count.test.ts` — route count bump.
4. `apps/web-platform/infra/sentry/cron-monitors.tf` — `resource "sentry_cron_monitor"
   "cron_weekly_release_digest"`: `name = "cron-weekly-release-digest"` (byte-identical
   to the handler constant; asserted by registry test (c)),
   `schedule = { crontab = "0 15 * * 5" }`, `checkin_margin_minutes = 30`
   (Inngest-fired precedent — `scheduled_strategy_review` cohort at cron-monitors.tf:293–303,
   NOT the 55-min claude-eval cohort), `max_runtime_minutes = 10`,
   `failure_issue_threshold = 1`, `recovery_threshold = 1`, `timezone = "UTC"`; header
   comment naming the firing function file + closest sibling per file convention.
5. `.github/workflows/apply-sentry-infra.yml` — add
   `-target=sentry_cron_monitor.cron_weekly_release_digest \` to the target list (mind
   the line-continuation backslash — a missing `\` executes the next `-target=` as a bare
   command, exit 127, per the PR #5108 comment at :193–195; copy a sibling line verbatim;
   do not disturb the deliberately-absent `kb_tenant_mint_silent_fallback` orphan).
6. `apps/web-platform/infra/cron-egress-allowlist.txt` — update the per-host evidence
   comments for `api.anthropic.com` and `discord.com` to cite the new cron's call sites
   (architecture P2-3: the header declares "grep-enumerated, NOT intuited"; the anthropic
   line currently cites only token-validators.ts. Doc-only; this path triggers
   `apply-web-platform-infra.yml`'s harmless provisioner re-resolve).

### Phase 4 — Brand-guide amendment + constant sync test

Add the following copywriter-authored subsection VERBATIM under `### Discord`
(knowledge-base/marketing/brand-guide.md:275, after line 283). The brand guide is the
human-readable source; the handler's module constant is the operational copy; a unit
test asserts they match byte-for-byte (same lockstep pattern as the five registries —
without it, brand-guide edits silently never reach prod):

```markdown
#### Release Digest

Automated weekly post to #releases (Fridays). These are operational rules for unattended generation — follow exactly:

- **Format:** 3-5 highlight bullets, each one sentence in the shape "what shipped + why it matters to a founder." Close with exactly one remainder line: "…plus N more releases, vA → vB." Total post ≤2000 characters. No @-mentions, no contributor names, no commit hashes, no links unless they appear in the release notes.
- **Selection rubric:** rank candidate releases by (1) founder impact — something a user can now do, stop doing, or stop worrying about; (2) breadth — affects most users, not one niche config; (3) novelty — new capability beats fix beats chore. Never rank by commit count, diff size, or release frequency.
- **Tone:** declarative, concrete, builder-to-builder. Lead each bullet with the outcome, not the component name. State only what shipped — no roadmap promises, no hype adjectives ("game-changing," "massive"), no "just/simply," no "AI-powered." Use a number only if it appears verbatim in the source release notes. Structural emoji (arrows, checkmarks) sparingly; decorative emoji never.
- **Example highlight:** "Release notifications now land in Slack instead of Discord DMs — your team sees ships where they already work."
- **Quiet week (zero releases):** post one line only, e.g. "Quiet week at the forge — heads-down on the next release. See you next Friday." Never pad with filler highlights or restate old releases as new.
```

Test: assert the LLM prompt builder includes the banned-word prohibition (prompt-side
string check). Do NOT test that the deterministic fallback omits banned words — it
renders verbatim release titles by contract, so that assertion is vacuous-or-false
(simplicity P1-6 + DHH).

### Phase 5 — Provisioning (pre-merge, in-session; `wg-block-pr-ready-on-undeferred-operator-steps`)

5.1 Create the webhook via bot API (automated):
    `curl -sS --max-time 10 -X POST -H "Authorization: Bot $TOKEN" -H "Content-Type: application/json" -d '{"name":"Soleur Releases"}' https://discord.com/api/v10/channels/<releases-channel-id>/webhooks`
    → capture `url` from the response into a shell variable (parsed in-shell, never echoed).
5.2 If 403 (no `MANAGE_WEBHOOKS`): grant via guild role update if the session bot/admin
    token allows; otherwise present the exact Discord click-path (Server Settings →
    Integrations → Webhooks → New Webhook → channel `#releases`) and have the operator
    paste the URL **into Doppler directly** (dashboard or `doppler secrets set` typed by
    operator) — never via `!`-prefixed chat (`hr-never-paste-secrets-via-bang-prefix`).
5.3 Write Doppler prd (explicit operator ack required before this prod write,
    `hr-menu-option-ack-not-prod-write-auth`):
    `printf '%s' "$WEBHOOK_URL" | doppler secrets set DISCORD_RELEASES_WEBHOOK_URL -p soleur -c prd --silent`
5.4 Rotation runbook line (TR9): webhook compromised → `DELETE /webhooks/<id>` via bot
    token + re-run 5.1/5.3, THEN refresh the container env without SSH
    (`hr-no-ssh-fallback-in-runbooks`): trigger a redeploy via
    `gh workflow run web-platform-release.yml` (workflow_dispatch confirmed at :7; the
    container env re-downloads the full Doppler prd config at deploy, ci-deploy.sh:175).
    Without this step the container serves the dead URL until the next unrelated merge.
    PR-1's own merge supplies the initial deploy.

### Phase 6 — Post-merge: gate, announce, verify

6.0 Gate on BOTH workflows for the merge commit concluding SUCCESS before any trigger
    (architecture P1-2): `web-platform-release.yml` (deploy — the manual-trigger
    allowlist is served by the deployed container; early fire = 400) AND
    `apply-sentry-infra.yml` (a heartbeat BEFORE the TF apply auto-creates the monitor
    outside state; the subsequent single-plan auto-apply then fails on create-conflict
    and blocks every monitor's auto-apply until a manual `terraform import`). Poll via
    `gh run watch`/Monitor pattern. Backstop: if the apply failed, fix/import BEFORE the
    first natural Friday fire — heartbeats fire on failure paths too.
6.1 One-time cadence announcement (FR7): draft copy per brand guide, show the operator
    for approval (outward-facing publish), then POST to the **community**
    `DISCORD_WEBHOOK_URL` (#general — the muted member won't see a #releases-only post)
    and to `#releases` via the new webhook. Note in the copy that a catch-up digest will
    follow shortly. Direct note to the affected member: operator knows the identity
    (Discord does not expose mute state); offer the drafted DM text and record the
    outcome (sent / declined) in the ship summary.
6.2 Verification trigger: fire `/soleur:trigger-cron` →
    `cron/weekly-release-digest.manual-trigger` and assert programmatically
    (`hr-no-dashboard-eyeball-pull-data-yourself`):
    (a) the `apply-sentry-infra.yml` success already gated in 6.0 (ordering per
    architecture P1-2 — apply BEFORE first check-in);
    (b) the digest message exists in `#releases` via bot API
    `GET /channels/<id>/messages?limit=1` (permission probed in Phase 0.1(b));
    (c) the monitor config read via Sentry API shows schedule `0 15 * * 5` +
    `checkin_margin_minutes 30` and latest check-in ok
    (`apps/web-platform/scripts/sentry-monitors-audit.sh` — full path; repo-root
    `scripts/` has no such file).
6.3 `gh issue edit 5080` — promote milestone/priority per spec hygiene sweep (Phase 4
    milestone, drop `priority/p3-low` → `priority/p2-medium`; labels verified via
    `gh label list`).

### Phase 7 — Deferred-scope-out tracking issue (plan-time, before /work)

Create ONE tracking issue for the cut extras (a deferral without a tracking issue is
invisible): title `feat: release-digest community extras (opt-in ping role, majors post,
digest persistence)`, labels `deferred-scope-out` + `domain/support` +
`priority/p3-low`, milestone `Post-MVP / Later`. Body: what was deferred (FR8/FR9/FR10
as brainstormed), why (5-agent review convergence: native Discord onboarding obviates
the reaction-poll; majors fire ~annually on v3.x and CI cannot read the Doppler-only
secret; persistence has no consumer; 11-member community), re-evaluation criteria (a
community member requests release pings, OR a major ships where 6-day digest latency
demonstrably mattered, OR a feature-tweet/AEO consumer for digest markdown materializes).
Reference the reviewer guidance: native onboarding role-picker + Inngest-substrate majors
detection are the right shapes if revived.

## Files to Create

- `apps/web-platform/server/inngest/functions/cron-weekly-release-digest.ts`
- `apps/web-platform/test/server/inngest/cron-weekly-release-digest.test.ts`

## Files to Edit

- `apps/web-platform/app/api/inngest/route.ts` (import + array entry)
- `apps/web-platform/server/inngest/cron-manifest.ts` (manifest entry)
- `apps/web-platform/server/inngest/functions/_cron-shared.ts` (`postDiscordWebhook` helper)
- `apps/web-platform/test/server/inngest/function-registry-count.test.ts` (route count)
- `apps/web-platform/infra/sentry/cron-monitors.tf` (monitor resource)
- `apps/web-platform/infra/cron-egress-allowlist.txt` (evidence comments — doc-only)
- `.github/workflows/apply-sentry-infra.yml` (-target line)
- `knowledge-base/marketing/brand-guide.md` (Release Digest subsection)
- `knowledge-base/legal/compliance-posture.md` (Anthropic vendor-row scope note)
- `knowledge-base/engineering/architecture/decisions/ADR-053-per-call-model-tiering-for-workflow-subagent-spawns.md`
  (hygiene fold-in: header self-titles "ADR-051" — one-line fix, architecture review)
- `knowledge-base/project/specs/feat-weekly-release-digest/spec.md` (FR2 fetch wording;
  FR8/FR9/FR10 → Non-Goals with tracking-issue reference; AC16–AC18 removed)

## Open Code-Review Overlap

Checked 63 open `code-review` issues against the file lists (2026-06-10). No issue bodies
reference the planned files. Three generic-token matches on "route.ts" (#3739
reportSilentFallback helper extraction, #3351 kb-upload streaming, #2246 kb polish) —
**Acknowledge:** different files/concerns; the new `postDiscordWebhook` helper is adjacent
to #3739's helper-extraction theme but does not modify its 11 sites; noted for that
refactor to adopt.

## Observability

```yaml
liveness_signal:
  what: Sentry cron monitor check-in `cron-weekly-release-digest` (postSentryHeartbeat object call)
  cadence: weekly (Fri 15:00 UTC) + manual triggers
  alert_target: Sentry cron-monitor missed/error alerting (failure_issue_threshold = 1)
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf (auto-applied on merge via apply-sentry-infra.yml)
error_reporting:
  destination: Sentry (captureException in steps; handler-level catch -> best-effort ok:false check-in)
  fail_loud: post-discord step THROWS on non-2xx/missing secret (one Inngest step retry), handler catch sends ok:false check-in (status=error, immediate red) then returns error result
failure_modes:
  - mode: Discord POST fails (bad/deleted webhook, 4xx/5xx, missing/empty secret)
    detection: step retry once -> handler catch -> ok:false check-in -> monitor error (immediate)
    alert_route: Sentry monitor alert
  - mode: Anthropic call fails/times out/shape-invalid
    detection: caught INSIDE curate step (no function retry consumed) -> Sentry event + deterministic fallback still posts
    alert_route: Sentry issue alert (event-level); digest lands (degraded)
  - mode: GitHub releases fetch fails
    detection: step retry once -> handler catch -> ok:false check-in
    alert_route: Sentry monitor alert
  - mode: Sentry heartbeat env unset (shared _cron-shared skip at :185-199)
    detection: missed-check-in margin (checkin_margin_minutes = 30) as backstop
    alert_route: Sentry monitor missed alert
logs:
  where: pino structured logs (fn: cron-weekly-release-digest) -> container stdout -> Better Stack
  retention: Better Stack default
discoverability_test:
  command: curl -sS -o /dev/null -w "%{http_code}" --max-time 10 https://app.soleur.ai/api/inngest
  expected_output: 401 or 200
# (401 = signed Inngest serve endpoint alive, the registration surface for this
# cron; richer reads: /soleur:trigger-cron list + bash
# apps/web-platform/scripts/sentry-monitors-audit.sh — no ssh anywhere.)
```

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/sentry/cron-monitors.tf`: one `sentry_cron_monitor` resource
  as specified in Phase 3.4 (values pinned to the `scheduled_strategy_review` Inngest-fired
  cohort; terraform-architect reviewed). Provider/versions unchanged (existing root). No
  new sensitive variables.

### Apply path

Auto-apply on merge: `apply-sentry-infra.yml` fires when the PR touching
`cron-monitors.tf` merges to main, scoped by the `-target` allowlist. No operator
terraform step; kill switch `[skip-sentry-apply]`. Blast radius: one new monitor, pure
`+ create` under `-target`; zero changes to existing resources. Phase 6.0 gates the first
check-in on apply success (create-conflict poisoning hazard — architecture P1-2).

### Distinctness / drift safeguards

Sentry monitors are prd-only (consistent with all 40+ siblings). Slug↔resource-name
byte-identity asserted by `function-registry-count.test.ts` (tf parse). Drift detection:
existing `scheduled-terraform-drift` cron covers this root. The new monitor will appear
as a Class A orphan (no alert-rule reference) in `sentry-monitors-audit.sh` reports —
report-only, consistent with siblings relying on `failure_issue_threshold`.

### Vendor-tier reality check

Sentry cron monitors are on the existing paid plan (40+ siblings) — no tier gate. Discord
webhook is a free vendor object (bot-API provisioned in-session — ack note in frontmatter).

### Non-Terraform provisioning (in-session, automated)

- Discord webhook for `#releases`: created via bot API (Phase 5.1), fallback click-path
  documented (Phase 5.2).
- Doppler prd secret `DISCORD_RELEASES_WEBHOOK_URL`: written in-session with explicit
  operator ack (Phase 5.3). Value lands in the container env on the merge deploy.
- Rationale (terraform-architect reviewed): the infra root at `apps/web-platform/infra/`
  HAS a wired Doppler provider, but its `doppler_secret` convention covers
  Terraform-derived values only; this webhook URL is minted by the vendor API outside
  Terraform, and Terraform-managing it would require an operator-pasted variable
  (violates `hr-tf-variable-no-operator-mint-default`) while adding tfstate exposure
  with no reconciliation benefit. No Discord provider is wired; not adding one for a
  single webhook. The sentry root has only the sentry provider — cross-root coupling for
  one secret is worse than the in-session write.

## Acceptance Criteria

### Pre-merge (PR)

- AC1: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-weekly-release-digest.test.ts` passes; suite covers the Test Scenarios below.
- AC2: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/function-registry-count.test.ts` passes with the new function in all five registries (route 53; manifest via set-equality; tf monitor present; -target line via tests (f)/(f2)).
- AC3: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- AC4: Unit test: ALL payloads flow through the single renderer; fixtures for all three input shapes (LLM highlights, deterministic fallback, quiet week) assert `allowed_mentions: { parse: [] }` and ≤2000 chars; escaping applied BEFORE the truncation measurement (oversized fixture whose escaped form exceeds 2000 proves the order).
- AC5: Unit test: a release named `fix(security): patch CVE-2026-1234 ...` renders title-only — the withheld body string is absent from the LLM-input fixture output (non-vacuous: present in the raw fixture). An `xss`-titled fixture gets the same treatment.
- AC6: Unit test: prompt-builder output contains no `@`-handle token, no `author` field, no email address, and no `Co-Authored-By:` line from a fixture release authored by `@octocat` whose body embeds `Co-Authored-By: Test <test@example.test>` (non-vacuous: raw fixture contains all four).
- AC7: Unit test: Anthropic fetch mocked to fail → deterministic fallback payload still produced AND Discord POST still attempted (no function retry consumed — failure caught inside curate). Mocked Discord POST non-2xx → step throws; handler catch sends the `ok:false` check-in, asserted via the Phase 1 heartbeat mechanism (mocked fetch URL `?status=error` or mocked `postSentryHeartbeat` call args) — NOT merely "a step threw".
- AC8: Unit test: zero highlight-eligible releases (including a `vinngest-v1.1.12` + `telegram-v0.1.1`-only window — the v-prefix-collision and real-excluded-stream fixtures) → quiet-week payload posted, heartbeat ok:true; the partition test separately proves `vinngest-v1.1.12` is NOT highlight-eligible while `v3.154.0` and `web-v0.120.0` are.
- AC8b: Unit test: `DISCORD_RELEASES_WEBHOOK_URL` missing AND empty-string → no POST to any URL, captureException called, step throws, `ok:false` check-in sent.
- AC9: `grep -c 'target=sentry_cron_monitor.cron_weekly_release_digest' .github/workflows/apply-sentry-infra.yml` returns 1, and the preceding line ends with `\` (belt-and-suspenders with AC2's tests (f)/(f2) and the 6.0 apply gate).
- AC10: Unit test asserts the prompt-rules module constant matches the `#### Release Digest` subsection of `knowledge-base/marketing/brand-guide.md` byte-for-byte (drift lockstep); `grep -c '#### Release Digest' knowledge-base/marketing/brand-guide.md` returns 1; prompt builder includes the banned-word prohibition string.
- AC11: Doppler prd holds a LIVE `DISCORD_RELEASES_WEBHOOK_URL` bound to `#releases` (assert the invariant, not name presence): read the value (parsed in-shell, never echoed), call Discord's unauthenticated `GET /webhooks/{id}/{token}`, assert HTTP 200 + `channel_id` equals the `#releases` id recorded in Phase 0.1 + value non-empty — provisioned Phase 5, before `gh pr ready`.
- AC12: `grep -ci 'release digest' knowledge-base/legal/compliance-posture.md` ≥ 1 (case-insensitive — Kieran P2-2) on the Anthropic vendor row scope note.
- AC13 (plan-time): the Phase 7 deferred-scope-out issue exists (`gh issue list --label deferred-scope-out --search "release-digest extras"` returns 1).

### Post-merge (automated in-session)

- AC14: Phase 6.0 gate held: BOTH `web-platform-release.yml` and `apply-sentry-infra.yml` runs for the merge commit concluded success BEFORE the manual trigger fired. `Automation: gh run watch.`
- AC15: Manual trigger → digest message asserted in `#releases` via bot API message read; Sentry monitor config (schedule `0 15 * * 5`, margin 30) + latest check-in ok via API/audit script. `Automation: trigger-cron skill + Discord bot API + Sentry API; no dashboard eyeballing.`
- AC16: Cadence announcement posted to #general + #releases after operator approves the copy; DM outcome recorded in ship summary. `Automation: webhook POST; operator approval is a genuine outward-facing-content judgment.`
- AC17: Issue #5080 milestone/priority updated (Phase 6.3).

## Test Scenarios

1. Window math: manual trigger on a Tuesday resolves to the previous Friday-ended window; boundary fixture at exactly Friday 15:00:00 lands in the closing week only (`(start, end]`).
2. Partition (load-bearing fixtures): `v3.154.0` + `web-v0.120.0` highlight-eligible; `vinngest-v1.1.12` (v-prefix collision) + `telegram-v0.1.1` (real excluded release stream) remainder-only.
3. Sanitize: author strip, @handle strip, email + Co-Authored-By strip, security down-detail incl. xss/rce/injection titles (AC5/AC6 fixtures).
4. Curate: valid LLM JSON → 3–5 highlights with code-computed remainder; `stop_reason: max_tokens` → fallback; shape-invalid → fallback + Sentry event; failure caught in-step (no function retry).
5. Render: single renderer; escape-then-truncate order; `allowed_mentions` on all three input shapes; webhook username set.
6. Post: 2xx → ok:true; 500 → step throws → handler catch → ok:false check-in asserted via mocked mechanism; missing AND empty secret → no POST, captureException, ok:false.
7. Quiet week: zero highlight-eligible releases (infra/telegram-only window) → one-line note posted, ok:true.
8. Constant sync: prompt-rules constant === brand-guide `#### Release Digest` subsection bytes.
9. Registry: five-registry lockstep (existing machine-enforced suite).

## Domain Review

**Domains relevant:** Engineering, Product, Legal, Support, Marketing (carried forward
from brainstorm `## Domain Assessments`, same-day; Operations/Sales/Finance not relevant)

### Engineering (CTO) — carry-forward

**Status:** reviewed
**Assessment:** Pure-TS + direct Anthropic API is the only non-dead-on-arrival shape (Tier-2 defer set governs claude-spawn crons). Five-registry lockstep machine-enforced; heartbeat must be output-aware (Discord 2xx). Estimate 1–2 days core.

### Product (CPO) — carry-forward

**Status:** reviewed
**Assessment:** Comms gap is live; promote #5080 out of p3/Post-MVP. Dominant net-new vector: internal content in a public post — closed input set + down-detail rule are the controls. Success metric + #releases baseline to capture at launch.

### Legal (CLO) — carry-forward

**Status:** reviewed
**Assessment:** PII-strip + published-release-bodies-only keeps this non-regulated (no LIA/Article 30/policy changes). Security down-detail rule required. Anthropic vendor-row scope note folded into this PR (AC12).

### Support (CCO) — carry-forward

**Status:** reviewed
**Assessment:** `#releases` is digest-only — never skip silently (quiet-week note adopted). One-time announcement + direct note is what lands the muted-member fix. Friday ~15:00 UTC fits the community. Engagement mechanics deferred (NG4 + Phase 7 tracking issue).

### Marketing (CMO) — carry-forward

**Status:** reviewed
**Assessment:** Brand-guide Voice + Discord rules drive the prompt (as an authoritative tested constant); Release Digest subsection added (Phase 4). First fully-unattended public brand-voice surface — bounded by deterministic rails. Ownership: Support owns channel/cadence; Marketing owns voice template + rubric.

**Brainstorm-recommended specialists:** copywriter — invoked at plan time (below).
ux-design-lead N/A (no UI surface — Product/UX Gate tier NONE; Discord post content is
not an app UI surface, consistent with brainstorm Phase 3.55 N/A and #5079 precedent).

### Product/UX Gate

**Tier:** none (no UI-surface file in Files lists; mechanical override did not fire)

### Copywriter (plan-time specialist)

**Status:** reviewed
**Assessment:** Authored the `#### Release Digest` brand-guide subsection (embedded in
Phase 4). Four unattended-generation failure modes each bounded by an operational rule:
claim inflation → "state only what shipped" + verbatim-number rule; hype-register drift →
string-checkable banned-word list; volume bias → three-criterion rubric with explicit
negative; privacy/ping hazards → hard prohibition on @-mentions/names/non-source links +
2000-char cap.

### Terraform-architect (Phase 2.8 gate)

**Status:** reviewed (OK, amendments applied)
**Assessment:** Monitor resource values pinned to the Inngest-fired cohort. Webhook +
Doppler secret correctly stay outside Terraform (convention + `hr-tf-variable-no-operator-mint-default`,
not capability — Doppler provider IS wired). Drift safety: pure `+ create` under `-target`.

### Spec-flow-analyzer (Phase 3 + re-validation)

**Status:** reviewed twice — first pass 2 P0 / 6 P1 / 9 P2 all folded; re-validation:
all 17 ENCODED, no paper resolutions; NEW-1 (retry-preserving throw shape) folded,
NEW-2 (stale Sharp Edge) fixed, NEW-3 (message-read probe) added, NEW-4 dissolved by
the inline-constant decision.

### GDPR gate (Phase 2.7, trigger (b): single-user-incident threshold)

**Status:** reviewed (advisory; no Critical findings)
**Findings:** (1) Chapter V — Anthropic vendor-row scope-note extension in PR scope
(AC12); Discord needs no DPA/register row while the PII-strip holds. (2) Suggestion
folded: sanitize strips emails + `Co-Authored-By:` lines; AC6 fixture extended.

### Plan-review panel (5-agent, single-user-incident threshold)

**Status:** reviewed — DHH, Kieran, code-simplicity, architecture-strategist, spec-flow
**Outcome:** PR-1 approved with amendments (all applied: Kieran P0 tag-partition fix +
vinngest fixture, heartbeat signature/mechanism, weekly-analytics catch precedent,
retry-preserving throw, 3 step.runs, single renderer, highlights-only LLM schema,
inline-constant prompt rules + sync test, dual-workflow post-merge gate, never-downgrade
ADR-053 comment, shared postDiscordWebhook helper, egress evidence comments, prompt-
injection residual named). PR-2 CUT entirely per unanimous simplification-panel
convergence + operator decision → Phase 7 tracking issue; `Closes #5080` moves to this PR.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| LLM elaborates beyond source (brand/security) | Closed input set (release bodies only), down-detail rule, verbatim-or-less invariant, JSON-schema validation (highlights only — remainder computed), deterministic fallback |
| Prompt-injection-shaped text in release bodies (external-contributor PR Changelogs) | Named residual: rails bound blast radius to plain text in #releases (schema validation, allowed_mentions parse:[], 2000-char cap, fallback); accepted at threshold |
| Webhook URL leak | Doppler-only storage, never-log discipline in the shared helper, gitleaks `discord-webhook-url` rule (repo-side), rotation runbook with redeploy step (Phase 5.4) |
| Silent week-miss | Step throws (one retry) → handler catch → ok:false check-in (immediate red); quiet-week note keeps "no post" ≡ "broken" distinguishable; margin backstop for env-unset |
| Wrong-channel posting | Eliminated by design — no #general fallback; missing/empty/dead primary → red monitor |
| Double-post on retry/manual trigger | POST isolated in its own memoized step (render inside it is deterministic from curate output); deterministic window key; same-week manual duplicate accepted + documented (low-stakes channel) |
| Brand-voice drift | Tested authoritative constant ↔ brand-guide lockstep; copywriter-authored rubric; review-time `user-impact-reviewer` |
| `MANAGE_WEBHOOKS` missing on bot | Phase 5.2 grant path + operator click-path fallback (secret lands via Doppler directly, never chat) |
| TF apply vs first check-in race | Phase 6.0 dual-workflow gate (apply BEFORE any heartbeat; create-conflict would block ALL monitor auto-applies) |
| Anthropic cost | One sonnet call/week over truncated input; trivial spend |

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| Claude-spawn cron (content-generator pattern) | Tier-2 defer trap for non-GitHub egress — would never run (#5046) |
| Deterministic template only | Quality ceiling — no "why it matters" narrative; kept as the fallback path. Honest note (DHH P1): the LLM is the majority of the complexity budget — sanitize/curate rails exist solely to chaperone it; operator endorsed LLM curation at brainstorm with the deterministic path as the always-available floor |
| LLM draft + weekly operator approval | Recurring operator touchpoint conflicts with automate-everything for non-technical operators |
| Route through distribution-content/ + content-publisher | Pre-approval `status:` semantics would be subverted by an auto-generated auto-approved file |
| `#general` via existing webhook | `#releases` stays dead; muted member never sees the fix; channel taxonomy erodes |
| GHA cron instead of Inngest | ADR-030/ADR-033: Inngest is the mandated cron substrate |
| PR-2 extras (role/majors/persistence) | CUT — Phase 7 tracking issue records what/why/re-evaluation criteria (deferral tracking) |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails deepen-plan
  Phase 4.6 — section is filled (carry-forward) above.
- The `-target=` line in apply-sentry-infra.yml: preceding line MUST end with `\` (PR #5108
  regression class).
- Test runner is vitest (NOT `bun test` — `bunfig.toml` blocks bun discovery); typecheck is
  in-package `tsc --noEmit` (NOT `npm run -w`, no root workspaces field).
- Cron syntax `0 15 * * 5` must NOT appear inside a `/** */` JSDoc header in the handler
  (closes the comment; suite fails at collection).
- `gh pr ready` is blocked until Phase 5 provisioning completed (AC11) — merging without
  the secret means the first fire goes red-monitor (missing secret = failure; there is NO
  #general fallback). Recoverable but noisy; provision first.
- `postSentryHeartbeat` takes an object (`{ ok, sentryMonitorSlug, cronName, logger }`) —
  not positional args. It silently skips when Sentry env is unset (`_cron-shared.ts:185–199`);
  tests must use the Phase 1 mechanism.
- The catch-shape precedent is the `cron-weekly-analytics.ts` TAIL (handler-level
  try/catch + best-effort direct heartbeat call) — NOT `cron-oauth-probe.ts:593` (in-step
  catch, which would suppress the function retry and not cover other steps' throws).
- `vinngest-v*` tags start with `v` — any tag-family logic must anchor `/^v\d/`, never
  bare `v` prefix.
