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
Discord-side objects (webhook, role) are vendor-API writes executed in-session via the
existing DISCORD_BOT_TOKEN; the Doppler prd secret write is executed in-session with
explicit operator ack. No servers, no manual dashboard steps. -->

# Plan: Weekly Community Release Digest (Discord) — #5080

## Overview

Build `cron-weekly-release-digest`, a pure-TS Inngest cron that posts a curated weekly
release digest to the community Discord `#releases` channel every Friday 15:00 UTC.
Curation via a direct Anthropic Messages API call (3–5 highlights, brand voice) with a
deterministic `feat > fix > chore` fallback. Delivered as **two sequenced PRs**:

- **PR-1 (this branch):** core cron + five-registry lockstep + webhook provisioning +
  brand-guide amendment + one-time cadence announcement.
- **PR-2 (follow-up branch off main after PR-1 merges):** `@release-notify` opt-in role +
  immediate-majors post + digest markdown persistence.

PR-1 body uses `Ref #5080`; PR-2 body uses `Closes #5080`.

## Premise Validation

All cited premises verified live on 2026-06-10: #5079 CLOSED via PR #5078 (merged
2026-06-10T16:37Z); "Post to Slack (release)" step `success` in release runs for
v3.154.0/v3.154.1 (re-evaluation gate met); `DISCORD_RELEASES_WEBHOOK_URL` deleted from
GH secrets and absent from Doppler (new provisioning required); `cron-weekly-analytics.ts`
Discord POST precedent at lines 221–250; `cron-compound-promote.ts` direct Anthropic call
at lines 398–483 (verified by grep — `ANTHROPIC_MODEL = "claude-sonnet-4-6"` at line 66,
`fetch("https://api.anthropic.com/v1/messages")` at line 423).

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| Sentry slug `scheduled-release-digest` (TR6) | Newer crons use the `cron-*` slug family (`cron_kb_template_health`, `cron_egress_resolve` in cron-monitors.tf) | Use slug `cron-weekly-release-digest`, TF resource `sentry_cron_monitor.cron_weekly_release_digest` (byte-identical slugify); spec TR6 amended at work time |
| Five-registry lockstep (TR7) | Confirmed: route.ts asserts 52 entries (function-registry-count.test.ts:135); manifest has 41 crons; apply-sentry-infra.yml auto-applies `-target=sentry_cron_monitor.*` on merge | Counts go 52→53 and 41→42; add `-target` line; auto-apply means no operator terraform step |
| `EXPECTED_CRON_FUNCTIONS` in cron-manifest.ts | Lives in `cron-manifest.ts`; re-exported via `cron-inngest-cron-watchdog.ts:61` (test imports from the watchdog) | Edit cron-manifest.ts only; re-export carries through |
| "repo-research: no cron calls Anthropic API directly" (brainstorm reconciliation) | False negative — compound-promote does | LLM-curation path confirmed viable (already reconciled in brainstorm) |
| `.env.example` should carry the new secret | apps/web-platform/.env.example has zero DISCORD entries (convention: these are Doppler-only) | No .env.example edit |

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

## PR-1 Implementation Phases

### Phase 0 — Preconditions (probes, no code)

0.1 Probe bot webhook capability (read-only): read `DISCORD_BOT_TOKEN` + `DISCORD_GUILD_ID`
    via `doppler secrets get ... --plain` (read-only), then
    `curl -sS --max-time 10 -H "Authorization: Bot $TOKEN" https://discord.com/api/v10/guilds/$GUILD/channels`
    → record the `#releases` channel id. Then probe permission:
    `GET /channels/<id>` succeeds and bot role carries `MANAGE_WEBHOOKS` (decode
    permissions bits or attempt webhook list `GET /channels/<id>/webhooks` — a 403 means
    the grant is missing; fall to 5.2's grant path).
0.2 Confirm Anthropic key availability in the prod cron env: `ANTHROPIC_API_KEY` present in
    Doppler prd (`doppler secrets get ANTHROPIC_API_KEY -p soleur -c prd --plain | head -c 8`)
    — compound-promote already consumes it in prod, so this is a confirmation, not a setup.
0.3 Confirm release-notes shape: `gh api 'repos/jikig-ai/soleur/releases?per_page=5' --jq '.[0] | {tag_name, published_at, body: (.body | length)}'`.

### Phase 1 — Failing tests first (`cq-write-failing-tests-before`)

Create `apps/web-platform/test/server/inngest/cron-weekly-release-digest.test.ts`
(matches vitest node-project glob `test/**/*.test.ts`; runner:
`cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-weekly-release-digest.test.ts`).
Follow the cron test gotchas (2026-06-02 learning): relative `./_cron-shared` import guard,
no `*/N` inside JSDoc, non-vacuous redaction assertions. Test scenarios listed below.

### Phase 2 — Handler `apps/web-platform/server/inngest/functions/cron-weekly-release-digest.ts`

Shape: pure-TS, modeled on `cron-weekly-analytics.ts` (registration block: `retries: 1`,
`concurrency [{scope:"fn",limit:1},{scope:"account",key:'"cron-platform"',limit:1}]`,
schedule `[{ cron: "0 15 * * 5" }, { event: "cron/weekly-release-digest.manual-trigger" }]`).
ADR-033 invariants I1 (step.run), I2 (operator key, no BYOK), I5 (deterministic return).

Steps (each its own `step.run`):

1. `compute-window` — deterministic week key: window end = most recent Friday 15:00 UTC
   ≤ now (manual triggers on other days resolve to the same window as the natural fire);
   window = `(end − 7d, end]` (half-open, end-inclusive — a release published exactly at
   Friday 15:00:00 belongs to the closing week, never double-counted). Week key = ISO
   date of window end. Note: `/releases` orders by `created_at`; `per_page=100` covers
   any realistic week (~50–100), residual accepted and documented.
2. `fetch-releases` — mint App installation token (`mintInstallationToken`, narrowed
   read-only permissions per `hr-github-app-auth-not-pat`; ambient `GH_TOKEN` is empty in
   the prod container), `fetch` GitHub REST `/repos/jikig-ai/soleur/releases?per_page=100`,
   filter `published_at` in window, exclude drafts/prereleases. Partition by tag prefix:
   `v*` + `web-v*` = highlight-eligible; everything else = remainder-count only.
3. `sanitize` — PII-strip (drop `author` fields; strip `@handle` tokens, email-address
   patterns, AND `Co-Authored-By:` lines from bodies with ASCII regexes — release bodies
   derive from PR-body Changelog sections which can embed both; gdpr-gate finding),
   security down-detail (release whose name/body matches
   `/security|vulnerab|CVE-\d|xss|rce|injection|privilege escalation/i` → title-only
   entry, body withheld from LLM input — widened per spec-flow P2-8; GitHub releases
   carry no labels so this is a title/body heuristic with documented residual),
   per-release body truncation (compound-promote's truncation-guard pattern).
4. `curate` — direct Anthropic Messages API call (copy `cron-compound-promote.ts:398–483`
   shape: `withTimeout`, `ANTHROPIC_MODEL` sonnet-class constant with ADR-053 call-site
   justification comment — mechanical summarization over a closed public input set,
   precedent compound-promote — `max_tokens`, `stop_reason` check, JSON-shape validation
   with Sentry event on invalid). Prompt embeds brand-guide `## Voice` + `### Discord`
   excerpts — REQUIREMENT (spec-flow P1-4): lazy/guarded load inside the step with an
   inline-constant fallback; NEVER a bare module-scope `readFileSync` (a throwing
   module-scope read fails the `route.ts` import and takes down all 53 registered
   functions, not one cron). Output schema:
   `{ highlights: [{tag, title, why}], remainder: {count, fromTag, toTag} }` (3–5 highlights).
5. `render` — build the Discord payload. Verbatim-or-less invariant: titles/tags/links from
   API data only. Entity-escape untrusted text; ≤2000 chars with truncation-aware remainder
   line; `allowed_mentions: { parse: [] }` always; webhook identity per 2026-02-19 learning
   (`username: "Soleur Releases"`). On LLM failure → deterministic fallback render
   (rank `feat:` > `fix:` > `chore:` from release names, verbatim titles). Zero-release
   window → one-line quiet-week note.
6. `post-discord` — isolated step: POST to `process.env.DISCORD_RELEASES_WEBHOOK_URL`
   ONLY. **No #general fallback** (spec-flow P0-2: the alternatives table already rejects
   #general posting; a fallback keeps the monitor green while #releases is dead —
   contradicting G5 — and pollutes the general channel with a wrong-channel brand post).
   Missing or empty-string secret is a failure, same as non-2xx: `Sentry.captureException`
   + treated as post-failure. Never log/interpolate the URL.
7. Failure→heartbeat shape (spec-flow P0-1 — sibling precedent `cron-oauth-probe.ts:593`):
   the handler CATCHES any step failure, sends
   `postSentryHeartbeat("cron-weekly-release-digest", ok:false)`, THEN returns the error
   result — never throw-without-heartbeat (a terminal throw skips the heartbeat step
   entirely and redness would depend only on the missed-check-in margin). Success path
   sends `ok:true` iff the Discord POST returned 2xx (the post IS the output contract —
   including the quiet-week note). Do NOT use `resolveOutputAwareOk`
   (GitHub-issue-shaped helper).

### Phase 3 — Five-registry lockstep (machine-enforced)

1. `apps/web-platform/app/api/inngest/route.ts` — import + functions-array entry (52→53;
   update the count assertion in `function-registry-count.test.ts:135`).
2. `apps/web-platform/server/inngest/cron-manifest.ts` — add `"cron-weekly-release-digest"`
   to `EXPECTED_CRON_FUNCTIONS` (41→42; manual-trigger event derives automatically →
   `/soleur:trigger-cron` picks it up for free).
3. `apps/web-platform/test/server/inngest/function-registry-count.test.ts` — count bump.
4. `apps/web-platform/infra/sentry/cron-monitors.tf` — `resource "sentry_cron_monitor"
   "cron_weekly_release_digest"` (slug byte-identical to the handler constant; schedule
   `0 15 * * 5`; copy a sibling resource's shape).
5. `.github/workflows/apply-sentry-infra.yml` — add
   `-target=sentry_cron_monitor.cron_weekly_release_digest \` to the target list (mind the
   line-continuation backslash — a missing `\` executes the next `-target=` as a bare
   command, exit 127, per the PR #5108 comment at line 195).

### Phase 4 — Brand-guide amendment

Add the following copywriter-authored subsection VERBATIM under `### Discord`
(knowledge-base/marketing/brand-guide.md:275, after line 283). The cron's LLM prompt
embeds this subsection, so its rules are operational:

```markdown
#### Release Digest

Automated weekly post to #releases (Fridays). These are operational rules for unattended generation — follow exactly:

- **Format:** 3-5 highlight bullets, each one sentence in the shape "what shipped + why it matters to a founder." Close with exactly one remainder line: "…plus N more releases, vA → vB." Total post ≤2000 characters. No @-mentions, no contributor names, no commit hashes, no links unless they appear in the release notes.
- **Selection rubric:** rank candidate releases by (1) founder impact — something a user can now do, stop doing, or stop worrying about; (2) breadth — affects most users, not one niche config; (3) novelty — new capability beats fix beats chore. Never rank by commit count, diff size, or release frequency.
- **Tone:** declarative, concrete, builder-to-builder. Lead each bullet with the outcome, not the component name. State only what shipped — no roadmap promises, no hype adjectives ("game-changing," "massive"), no "just/simply," no "AI-powered." Use a number only if it appears verbatim in the source release notes. Structural emoji (arrows, checkmarks) sparingly; decorative emoji never.
- **Example highlight:** "Release notifications now land in Slack instead of Discord DMs — your team sees ships where they already work."
- **Quiet week (zero releases):** post one line only, e.g. "Quiet week at the forge — heads-down on the next release. See you next Friday." Never pad with filler highlights or restate old releases as new.
```

The banned-word list ("game-changing", "just/simply", "AI-powered") is string-checkable —
add a unit assertion that the deterministic fallback renderer never emits them and that
the LLM prompt includes the prohibition.

### Phase 5 — Provisioning (pre-merge, in-session; `wg-block-pr-ready-on-undeferred-operator-steps`)

5.1 Create the webhook via bot API (automated):
    `curl -sS --max-time 10 -X POST -H "Authorization: Bot $TOKEN" -H "Content-Type: application/json" -d '{"name":"Soleur Releases"}' https://discord.com/api/v10/channels/<releases-channel-id>/webhooks`
    → capture `url` from the response into a shell variable (never echoed).
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
    `gh workflow run web-platform-release.yml` (the container env re-downloads the full
    Doppler prd config at deploy, ci-deploy.sh:175). Without this step the container
    serves the dead URL until the next unrelated merge — red monitor every Friday in
    between (spec-flow P1-3). PR-1's own merge supplies the initial deploy.

### Phase 6 — Post-merge: announcement first, then verification (spec-flow P2-1 ordering)

6.0 Wait for the merge deploy to complete before any trigger (spec-flow P2-2: the
    manual-trigger allowlist is served by the DEPLOYED container; firing early returns
    400 "Event not allowlisted"). Poll the `web-platform-release.yml` run for the merge
    commit to conclude success (`gh run list/watch` — Monitor pattern, no sleep-loops).
6.1 One-time cadence announcement (FR7): draft copy per brand guide, show the operator
    for approval (outward-facing publish), then POST to the **community**
    `DISCORD_WEBHOOK_URL` (#general) and to `#releases` via the new webhook. Note in the
    copy that a catch-up digest will follow shortly. Mention `@release-notify` (PR-2) is
    coming for major-release pings. Direct note to the affected member: operator knows
    the identity (Discord does not expose mute state); offer the drafted DM text and
    RECORD the outcome (sent / declined) in the ship summary (spec-flow P2-6 — the
    originating user must not be silently dropped).
6.2 Verification trigger: fire `/soleur:trigger-cron` →
    `cron/weekly-release-digest.manual-trigger` and assert programmatically
    (`hr-no-dashboard-eyeball-pull-data-yourself`, spec-flow P1-2/P2-7):
    (a) the digest message exists in `#releases` via bot API
    `GET /channels/<id>/messages?limit=1` (not operator eyeball);
    (b) the `apply-sentry-infra.yml` run for the merge concluded SUCCESS (a green
    check-in alone can mask a failed TF apply — Sentry auto-creates monitors from first
    check-in with no alerting);
    (c) the monitor config read via Sentry API shows schedule `0 15 * * 5` +
    `checkin_margin_minutes 30` and latest check-in ok (`scripts/sentry-monitors-audit.sh`).
6.3 `gh issue edit 5080` — promote milestone/priority per spec hygiene sweep (Phase 4
    milestone, drop `priority/p3-low` → `priority/p2-medium`; labels verified to exist via
    `gh label list`).

## PR-2 Implementation Phases (planned at lower resolution; re-validate at PR-2 work time)

### Phase 7 — `@release-notify` opt-in role (FR8)

7.1 Create role via bot API: `POST /guilds/$GUILD/roles {"name":"release-notify","mentionable":false}`.
7.2 Self-assign flow: bot posts a pinned reaction-role message in `#releases`
    ("react 🔔 to opt in"); a `sync-role-optins` step added to the weekly digest cron
    reads reactions (`GET /channels/<id>/messages/<msg-id>/reactions/🔔`) and PUTs/DELETEs
    member roles to match. Weekly sync latency is acceptable for a majors-only ping and
    avoids a persistent gateway listener (no bot process exists; pure-TS constraint).
    Document the latency in the message copy.
7.3 Majors post pings via explicit `allowed_mentions: {roles: ["<role-id>"]}` — role id
    stored as a module constant or Doppler value, decided at PR-2 time.

### Phase 8 — Immediate majors post (FR9)

8.1 Detection in the digest codebase, not CI: a lightweight Inngest function listening on
    a new `release/published` event is over-engineering; instead add a step to the
    existing per-release CI path (`reusable-release.yml`, adjacent to the Slack step):
    if the new tag's major > previous tag's major (same prefix family), POST a one-off
    digest-style announcement to the `#releases` webhook with the role mention.
8.2 Weekly cap + replaces-slot rule (FR9): enforced by the weekly cron checking "did a
    majors post fire in this window" via the Phase 9 kb-persisted marker. If the marker
    path is dropped at PR-2 time, spec FR9 MUST be amended (an unenforced FR is not a
    "documented residual" — spec-flow P1-6).
8.3 OPEN (decide at PR-2 plan time, spec-flow P1-6): the CI majors post cannot read a
    Doppler-only secret — `DISCORD_RELEASES_WEBHOOK_URL` was deliberately NOT re-created
    as a GH Actions secret. Either (re)provision a GH secret copy (two copies to rotate —
    extend the Phase 5.4 runbook) or move majors detection into the Inngest substrate
    (event on release publish). The `@release-notify` role id has the same CI-readability
    question. Also: reaction-role sync latency is up to 7 DAYS at majors time (sync lives
    in the weekly cron) — the opt-in message copy must say "up to a week"; reactions
    pagination (100/page) and bot perms for pin (MANAGE_MESSAGES) + seed reaction
    (ADD_REACTIONS) need a Phase-0-style probe at PR-2 time.

### Phase 9 — Digest persistence (FR10)

Post-record semantics: after a successful Discord POST, write
`knowledge-base/marketing/release-digests/YYYY-MM-DD.md` (frontmatter: week window,
highlight tags, posted-at) via the existing `_cron-safe-commit.ts` bot-PR pattern (same
substrate as cron-weekly-analytics snapshots). The file documents what was posted — it is
NOT a pre-approval gate (avoids subverting content-publisher `status:` semantics; the
brainstorm Open Question 2 resolution).

## Files to Create

- `apps/web-platform/server/inngest/functions/cron-weekly-release-digest.ts` (PR-1)
- `apps/web-platform/test/server/inngest/cron-weekly-release-digest.test.ts` (PR-1)
- `knowledge-base/marketing/release-digests/` artifacts (PR-2, cron-written)

## Files to Edit

- `apps/web-platform/app/api/inngest/route.ts` (PR-1, import + array entry)
- `apps/web-platform/server/inngest/cron-manifest.ts` (PR-1, manifest entry)
- `apps/web-platform/test/server/inngest/function-registry-count.test.ts` (PR-1, counts)
- `apps/web-platform/infra/sentry/cron-monitors.tf` (PR-1, monitor resource)
- `.github/workflows/apply-sentry-infra.yml` (PR-1, -target line)
- `knowledge-base/marketing/brand-guide.md` (PR-1, Release Digest subsection)
- `knowledge-base/legal/compliance-posture.md` (PR-1, Anthropic vendor-row scope note —
  digest cron added to the enumerated Anthropic API usage)
- `.github/workflows/reusable-release.yml` (PR-2, majors-post step)

## Open Code-Review Overlap

Checked 63 open `code-review` issues against the file lists (2026-06-10). No issue bodies
reference the planned files. Three generic-token matches on "route.ts" (#3739
reportSilentFallback helper extraction, #3351 kb-upload streaming, #2246 kb polish) —
**Acknowledge:** different files/concerns; the new cron's `reportSilentFallback` call site
follows current convention and will be swept by #3739's refactor when it lands.

## Observability

```yaml
liveness_signal:
  what: Sentry cron monitor check-in `cron-weekly-release-digest` (postSentryHeartbeat)
  cadence: weekly (Fri 15:00 UTC) + manual triggers
  alert_target: Sentry cron-monitor missed/error alerting (existing monitor-level rules)
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf (auto-applied on merge via apply-sentry-infra.yml)
error_reporting:
  destination: Sentry (captureException in steps; catch-path heartbeat ok:false)
  fail_loud: any step failure is CAUGHT -> heartbeat ok:false SENT (error check-in, immediate monitor red) -> error result returned; never throw-without-heartbeat
failure_modes:
  - mode: Discord POST fails (bad/deleted webhook, 4xx/5xx)
    detection: catch-path heartbeat ok:false -> Sentry monitor error (immediate, not margin-dependent)
    alert_route: Sentry monitor alert
  - mode: Anthropic call fails/times out/shape-invalid
    detection: Sentry event (op anthropic-curate-*) + deterministic fallback still posts
    alert_route: Sentry issue alert (event-level); digest still lands (degraded)
  - mode: DISCORD_RELEASES_WEBHOOK_URL missing or empty
    detection: captureException + catch-path heartbeat ok:false (NO #general fallback by design)
    alert_route: Sentry monitor alert
  - mode: GitHub releases fetch fails
    detection: catch-path heartbeat ok:false
    alert_route: Sentry monitor alert
  - mode: SENTRY heartbeat env unset (shared _cron-shared skip behavior)
    detection: missed-check-in margin (checkin_margin_minutes = 30) as backstop
    alert_route: Sentry monitor missed alert
logs:
  where: pino structured logs (fn: cron-weekly-release-digest) -> container stdout -> Better Stack
  retention: Better Stack default
discoverability_test:
  command: "curl -sS https://api.github.com/repos/jikig-ai/soleur is NOT needed — use: /soleur:trigger-cron list (shows the manual trigger) and the Sentry API monitor read via scripts/sentry-monitors-audit.sh"
  expected_output: monitor `cron-weekly-release-digest` present with latest check-in status ok
```

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/sentry/cron-monitors.tf`: one `sentry_cron_monitor`
  resource `cron_weekly_release_digest` — `name = "cron-weekly-release-digest"` (byte-
  identical to the handler's `SENTRY_MONITOR_SLUG`; asserted by registry test (c)),
  `schedule = { crontab = "0 15 * * 5" }`, `checkin_margin_minutes = 30` (Inngest-fired
  precedent — scheduled_strategy_review cohort, NOT the 55-min claude-eval cohort),
  `max_runtime_minutes = 10` (pure-TS handler, single Anthropic fetch),
  `failure_issue_threshold = 1` (one missed Friday is noteworthy at weekly cadence),
  `recovery_threshold = 1`, `timezone = "UTC"`; header comment naming the firing
  function file + closest sibling per file convention. Provider/versions unchanged
  (existing root). No new sensitive variables.

### Apply path

Auto-apply on merge: `apply-sentry-infra.yml` fires when the PR touching
`cron-monitors.tf` merges to main, scoped by the `-target` allowlist (the new line added
in Phase 3.5). No operator terraform step; kill switch `[skip-sentry-apply]` available.
Blast radius: one new monitor; zero changes to existing resources.

### Distinctness / drift safeguards

Sentry monitors are prd-only (no dev twin — consistent with all 40+ sibling monitors).
Slug↔resource-name byte-identity is asserted by `function-registry-count.test.ts` (tf
parse step). Drift detection: existing `scheduled-terraform-drift` cron covers this root.

### Vendor-tier reality check

Sentry cron monitors are on the existing paid plan used by 40+ sibling monitors — no
tier gate needed. Discord webhooks/roles are free-tier vendor objects (not Terraform-
managed; provisioned via bot API in-session — see ack note in frontmatter).

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
  single webhook. The sentry root (where this PR lands) has only the sentry provider —
  cross-root coupling for one secret is worse than the in-session write.

## Acceptance Criteria

### Pre-merge (PR-1)

- AC1: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-weekly-release-digest.test.ts` passes; suite covers the Test Scenarios below.
- AC2: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/function-registry-count.test.ts` passes with the new function in all five registries (route 53, manifest 42, tf monitor present).
- AC3: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- AC4: Unit test asserts every rendered payload — across ALL THREE render paths (LLM-curated, deterministic fallback, quiet-week note) — includes `allowed_mentions: { parse: [] }` and total content ≤2000 chars on an oversized fixture (spec-flow P2-4: the quiet-week note is the payload most likely to be hand-built).
- AC5: Unit test: a release named `fix(security): patch CVE-2026-1234 ...` renders title-only — `grep -c` of the LLM-input fixture for the withheld body string returns 0 (non-vacuous: the same string IS present in the raw fixture).
- AC6: Unit test: prompt-builder output contains no `@`-handle token, no `author` field, no email address, and no `Co-Authored-By:` line from a fixture release authored by `@octocat` whose body embeds `Co-Authored-By: Test <test@example.test>` (non-vacuous: raw fixture contains all four).
- AC7: Unit test: Anthropic fetch mocked to fail → deterministic fallback payload still produced AND Discord POST still attempted; mocked POST non-2xx → an `ok:false` check-in is SENT to the heartbeat endpoint (assert the heartbeat call happened with ok:false — NOT merely that a step threw; spec-flow P0-1).
- AC8: Unit test: zero highlight-eligible releases in window → quiet-week payload posted; heartbeat ok:true. Same behavior when the window contains ONLY excluded-stream releases (e.g. `inngest-v*`) — quiet-week note, not a remainder-only digest (spec-flow P2-3 resolution: infra-only weeks are quiet weeks for the community).
- AC8b: Unit test: `DISCORD_RELEASES_WEBHOOK_URL` missing AND empty-string cases → no POST to any other URL (no #general fallback), captureException called, `ok:false` check-in sent (spec-flow P0-2/P1-5).
- AC9: `grep -c 'target=sentry_cron_monitor.cron_weekly_release_digest' .github/workflows/apply-sentry-infra.yml` returns 1, and the preceding line ends with `\`.
- AC10: `grep -c '#### Release Digest' knowledge-base/marketing/brand-guide.md` returns 1.
- AC11: Doppler prd holds a LIVE `DISCORD_RELEASES_WEBHOOK_URL` bound to `#releases`
  (spec-flow P1-1 — assert the invariant, not name presence): read the value
  (never echoed), call Discord's unauthenticated `GET /webhooks/{id}/{token}` and assert
  HTTP 200 + `channel_id` equals the `#releases` id recorded in Phase 0.1 + value
  non-empty — provisioned Phase 5, before `gh pr ready`.
- AC12: `compliance-posture.md` Anthropic vendor row mentions the digest cron (`grep -c 'release digest' knowledge-base/legal/compliance-posture.md` ≥ 1).

### Post-merge (PR-1, automated in-session)

- AC13: After the deploy completes (Phase 6.0 poll): manual trigger via `/soleur:trigger-cron` → (a) digest message asserted in `#releases` via bot API message read, (b) `apply-sentry-infra.yml` merge run concluded success, (c) Sentry monitor config (schedule + margin) + latest check-in ok read via API. `Automation: trigger-cron skill + Discord bot API + gh run + Sentry API; no dashboard eyeballing, no operator eyeball on the Discord half.`
- AC14: Cadence announcement posted to #general + #releases after operator approves the copy. `Automation: webhook POST; operator approval is a genuine outward-facing-content judgment.`
- AC15: Issue #5080 milestone/priority updated (Phase 6.3).

### PR-2

- AC16: Majors post pings only `@release-notify` (explicit `allowed_mentions.roles`); weekly digest never pings.
- AC17: Reaction-role sync test: fixture reactions → role PUT/DELETE calls match opt-in set.
- AC18: After a successful post, `knowledge-base/marketing/release-digests/<date>.md` exists on a bot PR (safe-commit pattern).

## Test Scenarios (PR-1 suite)

1. Window math: manual trigger on a Tuesday resolves to the previous Friday-ended window (deterministic week key); boundary fixture at exactly Friday 15:00:00 lands in the closing week only (`(start, end]`).
2. Partition: `v3.154.0` + `web-v0.120.0` highlight-eligible; `inngest-v1.1.12` remainder-only.
3. Sanitize: author strip, @handle strip, email + Co-Authored-By strip, security down-detail incl. xss/rce/injection titles (AC5/AC6 fixtures).
4. Curate: valid LLM JSON → 3–5 highlights; `stop_reason: max_tokens` → fallback; shape-invalid → fallback + Sentry event; banned-word list absent from fallback output.
5. Render: 2000-char truncation, allowed_mentions present on ALL THREE render paths, webhook username set.
6. Post: 2xx → heartbeat ok:true; 500 → ok:false check-in SENT (catch shape); missing secret AND empty-string secret → no POST anywhere, captureException, ok:false sent.
7. Quiet week: zero highlight-eligible releases (including infra-only week) → one-line note posted, ok:true.
8. Registry: five-registry lockstep (existing machine-enforced suite).

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
**Assessment:** PII-strip + published-release-bodies-only keeps this non-regulated (no LIA/Article 30/policy changes). Security down-detail rule required. Extend Anthropic vendor-row scope note at ship time (folded into PR-1, AC12).

### Support (CCO) — carry-forward

**Status:** reviewed
**Assessment:** `#releases` is digest-only — never skip silently (quiet-week note adopted). One-time announcement + direct note is what lands the muted-member fix. Friday ~15:00 UTC fits the community. Webhooks can't create threads — engagement mechanics deferred (NG4).

### Marketing (CMO) — carry-forward

**Status:** reviewed
**Assessment:** Prompt must load brand-guide Voice + Discord notes; add Release Digest subsection (Phase 4). First fully-unattended public brand-voice surface — bounded by deterministic rails. Persistence artifact (PR-2) feeds feature-tweet/AEO later. Ownership: Support owns channel/cadence; Marketing owns voice template + rubric.

**Brainstorm-recommended specialists:** copywriter (CMO: digest copy/template review) —
invoked at plan time, findings below. ux-design-lead N/A (no UI surface — Product/UX Gate
tier NONE, no `components/**` or `app/**/page.tsx` files in the lists; Discord post
content is not an app UI surface, consistent with brainstorm Phase 3.55 N/A and #5079
precedent).

### Product/UX Gate

**Tier:** none (no UI-surface file in Files lists; mechanical override did not fire)

### Copywriter (plan-time specialist)

**Status:** reviewed
**Assessment:** Authored the `#### Release Digest` brand-guide subsection (embedded in
Phase 4 above). Four unattended-generation failure modes each bounded by an operational
rule: claim inflation → "state only what shipped" + verbatim-number rule; hype-register
drift → string-checkable banned-word list; volume bias → three-criterion rubric with
explicit negative ("never rank by commit count"); privacy/ping hazards → hard prohibition
on @-mentions/contributor names/non-source links + 2000-char cap.

### Terraform-architect (Phase 2.8 gate)

**Status:** reviewed (OK, two amendments applied)
**Assessment:** Monitor resource shape OK vs siblings; margin/runtime values pinned to
the Inngest-fired cohort (amendment applied to Terraform-changes bullet). Keeping the
webhook + Doppler secret outside Terraform is the right call — rationale corrected:
Doppler provider IS wired in the main root, but the `doppler_secret` convention is
Terraform-derived values only, and an operator-pasted TF_VAR would violate
`hr-tf-variable-no-operator-mint-default` while landing the secret in tfstate. Drift
safety: pure `+ create` under `-target`; the pre-existing `kb_tenant_mint_silent_fallback`
state orphan must not be disturbed (copy a sibling target line verbatim).

### Spec-flow-analyzer (Phase 3)

**Status:** reviewed — 2 P0, 6 P1, 9 P2; ALL folded into this plan revision
**Assessment:** P0-1 heartbeat dead-end (throw skips the heartbeat step → no check-in;
fixed via sibling catch-shape, AC7 now asserts the ok:false check-in is SENT). P0-2
fallback-to-#general green-monitor contradiction with G5 (resolved by DROPPING the
fallback; spec FR6 amended). P1s: AC11 proxy→invariant (live webhook GET + channel_id),
AC13 sharpened (apply-run success + monitor config read + bot message read), rotation
runbook redeploy step, lazy brand-guide load requirement, both-missing/empty tests,
PR-2 CI writer-path flagged OPEN (8.3). P2s: Phase 6 reordered (announcement before
catch-up digest) + deploy poll, infra-only week = quiet week, AC4 three render paths,
window boundary `(start, end]`, DM outcome recorded, security regex widened, spec drift
amended (FR5/FR6/FR7/TR6).

### GDPR gate (Phase 2.7, trigger (b): single-user-incident threshold)

**Status:** reviewed (advisory; no Critical findings)
**Findings:** (1) Chapter V — Anthropic vendor-row scope-note extension confirmed in PR-1
scope (AC12); Discord needs no DPA/register row while TR4 PII-strip holds. (2) Suggestion
folded in: TR4 sanitize extended to strip email addresses + `Co-Authored-By:` lines
(release bodies derive from PR-body Changelogs); AC6 fixture extended accordingly.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| LLM elaborates beyond source (brand/security) | Closed input set (release bodies only), down-detail rule, verbatim-or-less invariant, JSON-schema validation, deterministic fallback |
| Webhook URL leak | Doppler-only storage, no-log assertion, gitleaks `discord-webhook-url` rule (repo-side), rotation runbook (Phase 5.4) |
| Silent week-miss | Heartbeat gated on POST 2xx; quiet-week note keeps "no post" ≡ "broken" distinguishable; Sentry monitor red on miss |
| Wrong-channel posting | Eliminated by design — no #general fallback; missing/empty/dead primary → ok:false heartbeat (red monitor) |
| Double-post on retry/manual trigger | POST isolated in own memoized `step.run`; deterministic window key; same-week manual duplicate accepted + documented (low-stakes channel) |
| Brand-voice drift | Brand-guide-sourced prompt + copywriter-authored rubric (Phase 4); review-time `user-impact-reviewer` |
| `MANAGE_WEBHOOKS` missing on bot | Phase 5.2 grant path + operator click-path fallback (secret still lands via Doppler directly, never chat) |
| Anthropic cost | One sonnet-class call/week over truncated input (compound-promote truncation guard); trivial spend |

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| Claude-spawn cron (content-generator pattern) | Tier-2 defer trap for non-GitHub egress — would never run (#5046) |
| Deterministic template only | Quality ceiling — no "why it matters" narrative; kept as the fallback path instead |
| LLM draft + weekly operator approval | Recurring operator touchpoint conflicts with automate-everything for non-technical operators; rails bound the risk instead |
| Route through distribution-content/ + content-publisher | Pre-approval `status:` semantics would be subverted by an auto-generated auto-approved file; post-record artifact (PR-2 Phase 9) captures the cross-posting value without the gate subversion |
| `#general` via existing webhook | `#releases` stays dead; muted member never sees the fix; channel taxonomy erodes |
| GHA cron instead of Inngest | ADR-033/ADR-030: Inngest is the mandated cron substrate |

No deferred items requiring new tracking issues — all brainstorm extras are in PR-1/PR-2
scope under #5080; NG1 (contributor attribution) and NG4 (thread mechanics) are recorded
as Non-Goals in the spec with re-evaluation context, not silent drops.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails deepen-plan
  Phase 4.6 — section is filled (carry-forward) above.
- The `-target=` line in apply-sentry-infra.yml: preceding line MUST end with `\` (PR #5108
  regression class).
- Test runner is vitest (NOT `bun test` — `bunfig.toml` blocks bun discovery); typecheck is
  in-package `tsc --noEmit` (NOT `npm run -w`, no root workspaces field).
- Cron syntax `0 15 * * 5` must NOT appear inside a `/** */` JSDoc header in the handler
  (closes the comment; suite fails at collection).
- `gh pr ready` for PR-1 is blocked until Phase 5 provisioning completed (AC11) — the cron
  must not merge pointing at a secret that doesn't exist (silent #general fallback on
  first fire would be the result; mitigated but unwanted).
