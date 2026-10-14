---
title: "feat: Generalize handler-level fallback audit-issue to all 8 always-create cron producers"
date: 2026-06-06
type: feat
issue: 4978
branch: feat-one-shot-4978-cron-fallback-all-producers
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

# ♻️ feat: Generalize the handler-level fallback audit-issue to all 8 always-create cron producers (#4978)

## Overview

PR #4975 (merged 2026-06-05 19:57 UTC, closes #4960) added a **handler-level
`ensure-audit-issue` fallback** to `cron-content-generator.ts`: when the
output-aware heartbeat check (`resolveOutputAwareOk`) finds NO
`scheduled-content-generator` issue in the run window, the handler itself files
a self-reporting `FAILED [Scheduled] Content Generator - <date>` issue so the
run is never silent. It lives ABOVE the prompt, so it survives any termination
that bypasses the prompt's in-prompt "create issue and stop" steps (mid-eval
crash, upstream Anthropic API 500, max-turns kill).

The fallback was observed firing correctly in prod: issue #4982
(`[Scheduled] Content Generator - 2026-06-05`) self-reported end-to-end at
2026-06-05 20:58 UTC, and the daily `cloud-task-silence` alerts ceased.

The fallback currently lives **only** in content-generator. The source learning
(`knowledge-base/project/learnings/integration-issues/2026-06-05-cloud-task-silence-per-producer-triage-and-handler-fallback.md`)
states explicitly: *"All 8 always-create cron producers share this hole … generalizing
the fallback to the other 7 producers (extract into `_cron-shared.ts`) is a
tracked follow-up."* This is that follow-up (#4978).

**The work:**
1. Extract the proven fallback primitive (`AUDIT_TAIL_CHARS`, `formatTailForIssue`,
   `ensureContentGeneratorAuditIssue`) out of `cron-content-generator.ts` into a
   shared helper in `_cron-shared.ts`, parameterized by `{ label, titlePrefix }`
   (plus `cronName` for observability `feature`/`extra`).
2. Re-wire `cron-content-generator.ts` to call the shared helper (no behavior change).
3. Wire the other 7 always-create producers (roadmap-review,
   competitive-analysis, growth-audit, growth-execution, seo-aeo-audit,
   community-monitor, campaign-calendar) to call the shared helper after their
   `verify-output` step, gated on `!heartbeatOk`.
4. Extend the un-wiring guard (`cron-producer-output-wiring.test.ts`) to assert
   the `ensure-audit-issue` step is present in all 8.
5. Add behavioral unit tests for the shared helper in `cron-shared.test.ts`.

This is a **pure backend refactor + wiring change** — no schema, no migration, no
infra, no UI, no new dependency, no prompt edit, no turn-budget bump.

## Research Reconciliation — Spec vs. Codebase

| Claim (from issue #4978) | Codebase reality | Plan response |
| --- | --- | --- |
| "proven on content-generator in PR #4975" | ✅ PR #4975 MERGED; `ensureContentGeneratorAuditIssue` present at `cron-content-generator.ts:176-253`; fired in prod (#4982) | Extract verbatim, preserve all invariants |
| "shared `_cron-shared.ts` helper parameterized by `{ label, titlePrefix }`" | content-generator's helper hardcodes `SENTRY_MONITOR_SLUG` (label) and `[Scheduled] Content Generator` (titlePrefix). Both vary per producer. | Parameterize by `{ label, titlePrefix, cronName }` — `cronName` is also hardcoded and needed for Sentry `feature`/`extra` |
| "all 8 always-create cron producers" | All 8 confirmed present + structurally uniform (verify-output → sentry-heartbeat → `return { ok: heartbeatOk }`). They are exactly the `WIRED_PRODUCERS` list in `cron-producer-output-wiring.test.ts:22-40`. | Wire all 8; content-generator is re-wire (no behavior change), other 7 are new |
| "call it after their verify-output step, gated on `!heartbeatOk`" | content-generator's pattern: `if (!heartbeatOk) { await step.run("ensure-audit-issue", …) }` between `sentry-heartbeat` and the `finally` teardown (`cron-content-generator.ts:375-393`) | Mirror that exact placement in all 7 |
| Title prefix derivable from slug | ❌ FALSE. 8 distinct prefixes that do NOT match `scheduled-<slug>` — see "Per-producer title prefixes" table below | `titlePrefix` is a required explicit param, NOT slug-derived |

## User-Brand Impact

**If this lands broken, the user experiences:** a scheduled cron producer (e.g.
SEO/AEO audit, growth audit) silently goes dark on a mid-eval crash — no audit
issue, no Sentry red, no `cloud-task-silence` alert for up to `maxGapDays` (3-40
days depending on producer) — exactly the #4960 failure class this PR closes for
the other 7. A *broken* fallback (e.g. an unredacted spawn tail) could leak a
secret into a public GitHub issue body.

**If this leaks, the user's data is exposed via:** the FAILED audit-issue body
interpolates the redacted spawn `stdoutTail`/`stderrTail`. If the multi-secret
scrubber (`redactGithubSourcedText`) or the markdown-breakout neutralization
regresses during extraction, a crash stack could spill an allowlisted-env secret
(`ANTHROPIC_API_KEY` / `sk-ant-…`) into a public issue, or inject a
markdown-table breakout (image-autofetch / banner injection).

**Brand-survival threshold:** aggregate pattern. The content-generator fallback
already shipped at this same risk profile (PR #4975) and was reviewed by
security-sentinel; this PR generalizes the *same already-vetted* redaction path
to 7 more producers — it does not introduce a new exposure surface, it
replicates a vetted one. No new per-PR CPO sign-off; the section is present per
the gate.

## Per-producer title prefixes (load-bearing — dedup is `title.startsWith`)

The fallback files `${titlePrefix} ${date}` and dedups against a label-scoped GET
via `title.startsWith(${titlePrefix} ${date})`. The prefix MUST match each
producer's prompt-emitted success title or the dedup breaks (double-file under
`retries:1`). Verified against each handler's prompt block:

| Producer | label (SENTRY_MONITOR_SLUG) | titlePrefix |
| --- | --- | --- |
| content-generator | `scheduled-content-generator` | `[Scheduled] Content Generator -` |
| roadmap-review | `scheduled-roadmap-review` | `[Scheduled] Weekly Roadmap Review -` |
| competitive-analysis | `scheduled-competitive-analysis` | `[Scheduled] Competitive Analysis -` |
| growth-audit | `scheduled-growth-audit` | `[Scheduled] Growth Audit -` |
| growth-execution | `scheduled-growth-execution` | `[Scheduled] Growth Execution -` |
| seo-aeo-audit | `scheduled-seo-aeo-audit` | `[Scheduled] SEO/AEO Audit -` |
| community-monitor | `scheduled-community-monitor` | `[Scheduled] Community Monitor -` |
| campaign-calendar | `scheduled-campaign-calendar` | `[Scheduled] Campaign Calendar -` |

**Note on the exact dedup string.** content-generator builds
`title = \`[Scheduled] Content Generator - ${date}\`` (with ` - ` separator) and
dedups via `startsWith(title)`. To preserve byte-identical behavior the shared
helper must compose `${titlePrefix} ${date}` where `titlePrefix` ENDS in ` -`
(no trailing space) — i.e. `titlePrefix = "[Scheduled] Content Generator -"` and
the helper joins with a single space → `"[Scheduled] Content Generator - <date>"`.
The /work author MUST verify the composed string is byte-identical to the
pre-extraction content-generator title (an AC covers this).

## Sharp Edges (carry-forward + new)

- **content-generator dedup edge generalizes.** The dedup GET is label-scoped +
  title-prefix. For producers whose label is ALSO used by non-`[Scheduled]`
  issues, the prefix is what disambiguates:
  - **campaign-calendar** uses `scheduled-campaign-calendar` for THREE title
    shapes: `[Content] Overdue: …`, `[Scheduled] Campaign Calendar - <date> (heartbeat)`,
    and the fallback `[Scheduled] Campaign Calendar - <date>`. The dedup prefix
    `[Scheduled] Campaign Calendar - <date>` will NOT match `[Content] Overdue:`
    (correct — those are not the heartbeat artifact) but WILL match the
    `(heartbeat)`-suffixed title via `startsWith` (correct — that IS a same-day
    artifact, suppressing the fallback). Confirm the prompt's heartbeat title is
    `[Scheduled] Campaign Calendar - <today> (heartbeat)` so the prefix-match
    holds. **This is the right behavior**: if the prompt's heartbeat issue
    landed, the run was NOT silent, so the fallback should not fire.
  - **community-monitor** emits `[Scheduled] Community Monitor - FAILED` (a
    prompt-driven failure path) AND `[Scheduled] Community Monitor - YYYY-MM-DD`.
    The fallback title is `[Scheduled] Community Monitor - <date>`; its
    prefix-match will NOT match `- FAILED` (different — and that's fine; a prompt
    FAILED issue is itself a non-silent artifact, but `verifyScheduledIssueCreated`
    already counts ANY same-label issue in the window via `updated_at`, so
    `heartbeatOk` would be true and the fallback never fires). No double-file risk.
- **Two coupling residuals carry over verbatim** (already documented at
  `cron-content-generator.ts:366-374`): (a) `resolveOutputAwareOk` returns
  `spawnOk` when its verify-list THREW (transient GitHub 5xx) → a verify-throw +
  spawn-ok run skips the fallback even if the issue is genuinely absent (covered
  by the watchdog `maxGapDays`, not this step); (b) on a verify-throw +
  spawn-nonzero run the gate fires even though the prompt's issue may exist —
  the helper's same-title dedup is what prevents a spurious second issue, so the
  dedup is **load-bearing, not belt-and-suspenders**. Keep it robust in all 8.
- **Empty `## User-Brand Impact` would fail deepen-plan Phase 4.6** — section is
  filled above; threshold is `aggregate pattern`.
- **`redactGithubSourcedText` is the canonical multi-secret scrubber**
  (`apps/web-platform/lib/safety/redaction-allowlist.ts:145`). The extraction must
  route the tails through it (NOT just the substrate's installation-token-only
  `redactToken`). The backslash-then-pipe escape ORDER in `formatTailForIssue`
  is load-bearing (js/incomplete-sanitization) — preserve byte-for-byte.

## Implementation Phases

### Phase 0 — Preconditions (verify before editing)

- [x] Confirm PR #4975 is merged and the fallback exists: `gh pr view 4975 --json state` → MERGED; `grep -n "ensureContentGeneratorAuditIssue" apps/web-platform/server/inngest/functions/cron-content-generator.ts` → present.
- [x] Confirm all 8 producers are structurally uniform (verify-output → sentry-heartbeat → `return { ok: heartbeatOk }`): already enumerated in `cron-producer-output-wiring.test.ts:22-40`.
- [x] Confirm each producer's `titlePrefix` against its prompt block (the table above): `grep -nE "\[Scheduled\]" <producer>.ts` for each.
- [x] Confirm `redactGithubSourcedText` import path is `@/lib/safety/redaction-allowlist`.
- [x] Run baseline: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-content-generator.test.ts test/server/inngest/cron-shared.test.ts test/server/inngest/cron-producer-output-wiring.test.ts` → all green pre-change (capture counts).

### Phase 1 — RED: failing tests for the shared helper (`cq-write-failing-tests-before`)

- [x] In `apps/web-platform/test/server/inngest/cron-shared.test.ts`, add a
      `describe("ensureScheduledAuditIssue (shared fallback)")` block mirroring
      the existing `cron-content-generator.test.ts` behavioral suite (lines
      157-281): inject a fake octokit, assert:
  - creates exactly one labeled audit issue (`{ created: true }`) when none exists in the window;
  - title is `${titlePrefix} ${date}` with `date = runStartedAt.slice(0,10)`;
  - does NOT double-file when today's audit issue already exists (`{ created: false }`) — exercise BOTH an exact-title hit and a title-PREFIX hit (suffixed prompt issue suppresses the fallback);
  - the dedup GET is label-scoped (`labels: <label>`), `state: "all"`, explicitly `sort: "created", direction: "desc"`, `per_page: 10`;
  - the body scrubs secrets (feed a fixture tail containing a synthesized `sk-ant-…`-shape token per `cq-test-fixtures-synthesized-only`) and neutralizes markdown-breakout chars (backtick → `ʼ`, `|` → `\|`, CR/LF → space);
  - propagates a create failure to the caller (POST throws → helper rejects).
  - parameterization works: run the create/dedup assertions for ≥2 distinct `{ label, titlePrefix }` pairs (e.g. growth-audit + community-monitor) so a hardcoded-slug regression fails.
- [x] Confirm these FAIL (helper does not exist yet).

### Phase 2 — GREEN: extract the shared helper into `_cron-shared.ts`

- [x] Add to `_cron-shared.ts`:
  - `const DEFAULT_AUDIT_TAIL_CHARS = 500;` (rename of `AUDIT_TAIL_CHARS`; keep value).
  - `export function formatTailForIssue(tail: string | undefined): string` — moved VERBATIM from `cron-content-generator.ts:163-174` (the backslash→pipe→backtick escape chain, order preserved). Import `redactGithubSourcedText` at the top of `_cron-shared.ts`.
  - `export async function ensureScheduledAuditIssue(args: { label: string; titlePrefix: string; cronName: string; runStartedAt: string; spawnResult: Pick<SpawnResult, "exitCode" | "signal" | "abortedByTimeout" | "durationMs" | "stdoutTail" | "stderrTail">; installationToken?: string; octokit?: Octokit; }): Promise<{ created: boolean }>` — the body of `ensureContentGeneratorAuditIssue` (`cron-content-generator.ts:176-253`) with:
    - `SENTRY_MONITOR_SLUG` → `args.label` (used in dedup GET `labels:` AND create `labels: [label]`);
    - `[Scheduled] Content Generator -` → `args.titlePrefix` (the `title` becomes `\`${titlePrefix} ${date}\``);
    - `cron-content-generator` literal in the body prose + the `fn` table row → `args.cronName`;
    - keep `date = runStartedAt.slice(0, 10)`, the `octokit ?? new OctokitCtor({ auth: installationToken })` resolution, the `startsWith` dedup, and the self-diagnosing markdown table body.
  - `SpawnResult` type: import from `./_cron-claude-eval-substrate`. `Octokit` type: import from `@octokit/core` (mirror content-generator's imports). NOTE: `_cron-shared.ts` already imports `createProbeOctokit`; adding the `SpawnResult` + `Octokit` type imports is the only new import surface besides `redactGithubSourcedText`.
- [x] Run the Phase 1 tests → GREEN.

### Phase 3 — Re-wire content-generator (no behavior change)

- [x] In `cron-content-generator.ts`: DELETE `AUDIT_TAIL_CHARS`, `formatTailForIssue`, and `ensureContentGeneratorAuditIssue` (now in `_cron-shared.ts`).
- [x] Replace the `ensure-audit-issue` step body to call
      `ensureScheduledAuditIssue({ label: SENTRY_MONITOR_SLUG, titlePrefix: "[Scheduled] Content Generator -", cronName: "cron-content-generator", runStartedAt, spawnResult, installationToken })`.
- [x] **Compatibility shim decision:** `cron-content-generator.test.ts:25` imports
      `ensureContentGeneratorAuditIssue`. Choose ONE (record in spec):
  - (a) re-export a thin wrapper `export const ensureContentGeneratorAuditIssue = (args) => ensureScheduledAuditIssue({ ...args, label: SENTRY_MONITOR_SLUG, titlePrefix: "[Scheduled] Content Generator -", cronName: "cron-content-generator" })` so the existing test keeps passing unchanged; OR
  - (b) update `cron-content-generator.test.ts` to import + call `ensureScheduledAuditIssue` directly with the explicit params, and delete the content-generator-specific behavioral block (now covered by `cron-shared.test.ts`).
  - **Recommended: (b)** — avoids a vestigial wrapper; the behavioral coverage moves to `cron-shared.test.ts` (Phase 1) and the wiring coverage stays in `cron-producer-output-wiring.test.ts` (Phase 5). Keep content-generator's source-shape anchors that assert the `ensure-audit-issue` step + `!heartbeatOk` gate (those are wiring, not behavior).
- [x] Run `cron-content-generator.test.ts` → GREEN (adjust the import/assertions per the chosen option).

### Phase 4 — Wire the other 7 producers

For EACH of `cron-roadmap-review`, `cron-competitive-analysis`,
`cron-growth-audit`, `cron-growth-execution`, `cron-seo-aeo-audit`,
`cron-community-monitor`, `cron-campaign-calendar`:

- [x] Add `ensureScheduledAuditIssue` to the `_cron-shared` import.
- [x] Insert AFTER the `sentry-heartbeat` step and BEFORE the `finally` teardown
      (mirror `cron-content-generator.ts:358-393`):
      ```ts
      if (!heartbeatOk) {
        await step.run("ensure-audit-issue", async () => {
          try {
            await ensureScheduledAuditIssue({
              label: SENTRY_MONITOR_SLUG,
              titlePrefix: "<the producer's prefix from the table>",
              cronName: "<cron-name>",
              runStartedAt,
              spawnResult,
              installationToken,
            });
          } catch (err) {
            reportSilentFallback(err, {
              feature: "<cron-name>",
              op: "ensure-audit-issue-failed",
              message: "Handler-level fallback audit-issue create failed; run remains silent until watchdog threshold",
              extra: { fn: "<cron-name>", runStartedAt },
            });
          }
        });
      }
      ```
- [x] Confirm `installationToken` is in scope at the insertion point (all 7
      mint it as `step.run("mint-installation-token", …)` — verified). Confirm
      `reportSilentFallback` is already imported (all 7 import it — verified).
- [x] `titlePrefix` per the table above. Double-check each against the
      producer's prompt block (the `grep -nE "\[Scheduled\]"` from Phase 0).

### Phase 5 — Extend the un-wiring guard

- [x] In `cron-producer-output-wiring.test.ts`, inside the
      `it.each(WIRED_PRODUCERS)` block, add anchors asserting the fallback wiring
      is present in ALL 8:
  - `expect(src).toContain("ensureScheduledAuditIssue(")`;
  - `expect(src).toContain('"ensure-audit-issue"')`;
  - `expect(src).toContain("if (!heartbeatOk)")`;
  - `expect(src).toContain('op: "ensure-audit-issue-failed"')`.
- [x] Add a guard that the fallback is NOT present in the 3 `BEST_EFFORT_CRONS`
      (`expect(src).not.toContain("ensureScheduledAuditIssue")`) — they are not
      output-aware producers and must not adopt the fallback.

### Phase 6 — Full verification

- [x] `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/` (all inngest tests).
- [x] `cd apps/web-platform && npx tsc --noEmit` (extraction must not break types; `tsc` is the canonical enumerator for any missed consumer).
- [x] `grep -rn "ensureContentGeneratorAuditIssue" apps/web-platform/` → only the chosen shim/test references remain (zero if option (b)).
- [x] `grep -c 'op: "ensure-audit-issue-failed"' apps/web-platform/server/inngest/functions/cron-*.ts` summed across the 8 producers = 8.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1** — `_cron-shared.ts` exports `ensureScheduledAuditIssue` and `formatTailForIssue`; the helper accepts `{ label, titlePrefix, cronName }` and uses each (verified by the ≥2-pair parameterization test in `cron-shared.test.ts`).
- [x] **AC2** — the composed fallback title for content-generator is byte-identical to the pre-extraction string `[Scheduled] Content Generator - <date>` (a test asserts `title === \`[Scheduled] Content Generator - ${date}\`` given `titlePrefix = "[Scheduled] Content Generator -"`).
- [x] **AC3** — all 8 producers contain the `ensure-audit-issue` step gated on `if (!heartbeatOk)` with the `ensure-audit-issue-failed` Sentry fallback: `grep -c 'op: "ensure-audit-issue-failed"'` across the 8 `cron-*.ts` producers sums to 8 (verified by `cron-producer-output-wiring.test.ts`).
- [x] **AC4** — the 3 `BEST_EFFORT_CRONS` do NOT contain `ensureScheduledAuditIssue` (asserted in `cron-producer-output-wiring.test.ts`).
- [x] **AC5** — body-redaction is preserved: the helper routes tails through `redactGithubSourcedText` AND neutralizes backtick/pipe/CR-LF (test feeds a synthesized `sk-ant-`-shape token + a `|`/backtick payload and asserts neither survives in the issue body).
- [x] **AC6** — dedup is label-scoped + title-prefix, `state:all`, `sort:created/desc`, `per_page:10` (test asserts the exact GET params) and suppresses a same-day prompt-success issue (no double-file under `retries:1`).
- [x] **AC7** — `npx tsc --noEmit` clean; full `test/server/inngest/` suite green.
- [x] **AC8** — no turn-budget change in any producer (`--max-turns` unchanged); no prompt edit; no new runtime dependency (`cq-before-pushing-package-json-changes` — `package.json` untouched).
- [x] **AC9** — PR body uses `Closes #4978`.

### Post-merge (operator)

- [x] **AC10** — **Automation: deploy is automatic.** `web-platform-release.yml`
      path-filtered `on.push` restarts the container on merge to main touching
      `apps/web-platform/**`; the PR merge IS the deploy + function-sync
      remediation. No operator step. (Per the automation-feasibility gate: a cron
      handler change deploys via the existing release pipeline.)
- [ ] **AC11** — optional smoke (operator, automatable via `/soleur:trigger-cron`):
      fire one wired producer's manual-trigger from a worktree (e.g.
      `cron/seo-aeo-audit.manual-trigger`) AFTER deploy and confirm a
      `[Scheduled] SEO/AEO Audit - <date>` issue lands (success path) — the
      fallback path itself is exercised by the unit suite, not requiring a forced
      prod crash.

## Observability

```yaml
liveness_signal:
  what: each producer's per-function Sentry monitor (scheduled-<slug>) goes RED via resolveOutputAwareOk when no issue lands; the handler-level fallback then files a FAILED [Scheduled] … issue so cron-cloud-task-heartbeat stays green
  cadence: per cron fire (producer-specific: Tue/Thu, daily, weekly, monthly)
  alert_target: Sentry Crons monitor per slug + cron-cloud-task-heartbeat watchdog (maxGapDays per producer, cron-cloud-task-heartbeat.ts:70-74)
  configured_in: apps/web-platform/server/inngest/functions/_cron-shared.ts (postSentryHeartbeat + resolveOutputAwareOk) and each producer handler
error_reporting:
  destination: Sentry via reportSilentFallback / warnSilentFallback (cq-silent-fallback-must-mirror-to-sentry)
  fail_loud: true — a fallback create failure emits op:"ensure-audit-issue-failed"; the watchdog still catches the absence after maxGapDays (defense-in-depth)
failure_modes:
  - mode: producer terminates without its audit issue (mid-eval crash / API 500 / max-turns kill)
    detection: resolveOutputAwareOk finds no labeled issue in window → heartbeatOk=false
    alert_route: handler files FAILED [Scheduled] … issue (this PR) + scheduled-output-missing Sentry event; monitor RED
  - mode: fallback create itself fails (GitHub 5xx)
    detection: try/catch in the ensure-audit-issue step.run
    alert_route: reportSilentFallback op:"ensure-audit-issue-failed"; cron-cloud-task-heartbeat catches absence after maxGapDays
  - mode: verify-list THREW (transient GitHub 5xx) on a spawn-ok run
    detection: resolveOutputAwareOk returns spawnOk → fallback skipped
    alert_route: verify-output-failed Sentry event (already emitted); watchdog maxGapDays backstop
logs:
  where: Sentry (errors/warnings); GitHub issues (the audit-issue artifacts themselves); app stdout is NOT shipped to Better Stack (hence the redacted tail in the issue body)
  retention: Sentry default; GitHub issues indefinite
discoverability_test:
  command: cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-producer-output-wiring.test.ts test/server/inngest/cron-shared.test.ts
  expected_output: all green; 8 producers assert the ensure-audit-issue wiring, 3 best-effort crons assert its absence
```

## Open Code-Review Overlap

(Filled at Step 1.7.5 after the Files lists below are frozen — see check output appended during planning.)

## Files to Edit

- `apps/web-platform/server/inngest/functions/_cron-shared.ts` — add `ensureScheduledAuditIssue`, `formatTailForIssue`, `DEFAULT_AUDIT_TAIL_CHARS`; import `redactGithubSourcedText`, `SpawnResult` type, `Octokit` type.
- `apps/web-platform/server/inngest/functions/cron-content-generator.ts` — delete the now-extracted helpers; call `ensureScheduledAuditIssue`.
- `apps/web-platform/server/inngest/functions/cron-roadmap-review.ts` — add the `!heartbeatOk` fallback step.
- `apps/web-platform/server/inngest/functions/cron-competitive-analysis.ts` — add the fallback step.
- `apps/web-platform/server/inngest/functions/cron-growth-audit.ts` — add the fallback step.
- `apps/web-platform/server/inngest/functions/cron-growth-execution.ts` — add the fallback step.
- `apps/web-platform/server/inngest/functions/cron-seo-aeo-audit.ts` — add the fallback step.
- `apps/web-platform/server/inngest/functions/cron-community-monitor.ts` — add the fallback step.
- `apps/web-platform/server/inngest/functions/cron-campaign-calendar.ts` — add the fallback step.
- `apps/web-platform/test/server/inngest/cron-shared.test.ts` — behavioral tests for `ensureScheduledAuditIssue`.
- `apps/web-platform/test/server/inngest/cron-producer-output-wiring.test.ts` — extend `it.each(WIRED_PRODUCERS)` with the fallback-wiring anchors; add the best-effort negative anchor.
- `apps/web-platform/test/server/inngest/cron-content-generator.test.ts` — adjust import/assertions per the Phase 3 shim decision.

## Files to Create

(None — all edits are to existing files.)

## Non-Goals / Out of Scope

- No change to `resolveOutputAwareOk` / `verifyScheduledIssueCreated` semantics.
- No new producers; the 3 `BEST_EFFORT_CRONS` and `cron-strategy-review` stay excluded by design.
- No turn-budget or prompt changes.
- The two verify-throw coupling residuals are intentionally absorbed (documented; the watchdog `maxGapDays` is the backstop). Not deferred — they are an accepted design property carried over from PR #4975, not a new gap.

## Alternative Approaches Considered

| Approach | Verdict |
| --- | --- |
| Slug-derive `titlePrefix` from `label` | Rejected — title prefixes do NOT match the slug (8 distinct human-readable forms); deriving would break the dedup `startsWith`. |
| Keep per-producer copies of the helper (no extraction) | Rejected — issue #4978 mandates extraction; 7 copies of a security-sensitive redaction path is a maintenance + drift hazard. |
| Add the fallback inside `resolveOutputAwareOk` (one call site) | Rejected — `resolveOutputAwareOk` is read-only by contract (documented at `_cron-shared.ts:201-202`); mixing a write into the read-only resolver violates its invariant and couples the heartbeat to `installationToken`/`spawnResult` it doesn't currently take. Keep the fallback a separate gated `step.run` (Inngest replay isolation). |
