---
type: fix
classification: production-bug
brand_survival_threshold: none
lane: single-domain
status: draft
created: 2026-06-01
sentry_id: 512e253141294ac1a808b2ef03a21289
fn_id: soleur-runtime-cron-follow-through-monitor
---

# fix: cron-follow-through-monitor — replace unauthenticated `gh` CLI shell-out with GitHub App installation token 🐛

## Overview

The Inngest cron `cron-follow-through-monitor` (fnId `soleur-runtime-cron-follow-through-monitor`) throws on **every** scheduled run (`0 9 * * 1-5`, i.e. 09:00 UTC weekdays). The `validate-predicates` `step.run` shells out to the `gh` CLI via `execFileSync` to list open `follow-through` issues:

```ts
// apps/web-platform/server/inngest/functions/cron-follow-through-monitor.ts:409-414
const stdout = execFileSync(
  "gh",
  ["issue", "list", "--label", "follow-through", "--state", "open",
   "--json", "number,title,body", "--limit", "100"],
  { env: buildSpawnEnv(), timeout: 30_000 },
).toString("utf-8");
```

Inside the production Next.js container `gh` is **unauthenticated** — there is no `gh auth login`, and `buildSpawnEnv()` populates `GH_TOKEN` from `process.env.GH_TOKEN ?? process.env.GITHUB_TOKEN`, both of which are empty in prod. `gh` exits non-zero with:

```
Error: Command failed: gh issue list --label follow-through --state open --json number,title,body --limit 100
To get started with GitHub CLI, please run:  gh auth login
Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
```

This is wrapped by `reportSilentFallback` (handled=yes / Sentry-mirrored) at the `try/catch` around the step — but the function still produces zero useful work every run and floods Sentry with a daily error (ID `512e253141294ac1a808b2ef03a21289`, release `web-platform@0.102.0+14c06d9f`).

**Root cause:** the function never mints a GitHub credential. It inherits the substrate shape from before the GitHub-App-token pattern was applied to it. Per hard rule `hr-github-app-auth-not-pat`, production code must authenticate via the GitHub App installation token (Octokit), **not** the `gh` CLI relying on an ambient PAT/`gh auth login`.

**Fix:** mint a GitHub App installation token (via the existing `mintInstallationToken` helper in `_cron-shared.ts`) in a new first `step.run`, and inject it as `GH_TOKEN` into BOTH (a) the server-side `execFileSync("gh", …)` env in `validate-predicates`, and (b) the agent-spawn env in `claude-eval` (the agent itself runs `gh issue view/edit/comment/close`). This mirrors the established precedent in `cron-bug-fixer.ts` exactly. No `gh auth login`, no PAT, no new infrastructure.

The existing `reportSilentFallback` observability stays in place — the catch block remains the failure surface; with a valid token the happy path now succeeds.

## Research Reconciliation — Spec vs. Codebase

No spec exists for this branch. All claims below verified against `origin`-tracked code on 2026-06-01.

| Claim (from task description) | Reality (verified) | Plan response |
| --- | --- | --- |
| Function shells out to `gh issue list` | Confirmed at `cron-follow-through-monitor.ts:409-414` (server-side `execFileSync`) AND in the agent prompt (`FOLLOW_THROUGH_PROMPT` lines 108, 137, 140, 157, 160-161). The **server-side** `execFileSync` is what throws the cited Sentry error first. | Fix both surfaces by threading a minted token into both env builders. |
| A GitHub App / Octokit auth path is "already used elsewhere in the server runtime" | Confirmed: `_cron-shared.ts` exports `mintInstallationToken({ tokenMinLifetimeMs })` (line 31) → `createProbeOctokit()` → installation discovery → `generateInstallationToken(installation.id)`. **22+ cron functions already use it** (`cron-bug-fixer`, `cron-community-monitor`, `cron-roadmap-review`, etc.). | Reuse `mintInstallationToken` verbatim. No new helper. |
| Failure must stay observable (handled=yes / Sentry-mirrored) | Confirmed: the `validate-predicates` catch calls `reportSilentFallback(...)` (line 424); `ensure-labels` and `claude-eval` also report via `reportSilentFallback`. | Keep all three `reportSilentFallback` sites unchanged. |
| Only one server-side `gh` shell-out in this flow | Confirmed: `_predicate-validator.ts` has NO `gh`/`spawn`/`execFileSync` (it parses HTML-comment YAML). The only server-side `gh` is the `execFileSync` in the handler. | Single server-side fix site. |

## Open Code-Review Overlap

**Files to Edit:** `apps/web-platform/server/inngest/functions/cron-follow-through-monitor.ts`, `apps/web-platform/test/server/inngest/cron-follow-through-monitor.test.ts`

Ran `gh issue list --label code-review --state open` (via the standard two-stage `--json` + standalone `jq --arg` pattern) against both paths: **None**. No open code-review scope-outs name these files.

## Blast-Radius Note — `cron-daily-triage` has the identical bug

`grep -n "GH_TOKEN: process.env.GH_TOKEN" apps/web-platform/server/inngest/functions/` returns exactly **two** hits:

1. `cron-follow-through-monitor.ts:260` (this fix)
2. `cron-daily-triage.ts:168` (**same root cause**)

`cron-daily-triage` has the identical `buildSpawnEnv()` reading `process.env.GH_TOKEN ?? process.env.GITHUB_TOKEN`, and its agent prompt also runs `gh issue list` (line 64). It is **also broken in production** — but it differs in failure shape: daily-triage has NO server-side `execFileSync` (it only spawns the agent), so the `gh` failures occur *inside* the agent (agent exits non-zero) rather than throwing the exact server-side `Command failed` Sentry error this plan targets.

**Disposition: Acknowledge + fold-in (recommended).** The Sentry error in scope is follow-through's server-side `execFileSync`. However, daily-triage shares the root cause and the identical fix shape (mint token → inject as `GH_TOKEN`). Folding both into one PR is the net-positive path (one review, one deploy, closes the whole class). The plan's phases are written so daily-triage is a trivial mechanical mirror (Phase 3). If the operator prefers to keep the PR scoped to the Sentry-cited function only, daily-triage MUST get a same-session follow-up issue (`fix: cron-daily-triage unauthenticated gh CLI — same root cause as #<this PR>`) so it is not invisible. **Default per `wg-defer-only-after-inline-triage`: fold in.**

## User-Brand Impact

**If this lands broken, the user experiences:** follow-through GitHub issues (external-dependency verification trackers) silently stop being monitored — SLA-exceeded issues never get the `needs-attention` label or `@author` ping, and passed predicates never auto-close. This is an internal operator-facing automation; non-technical Soleur end-users are not directly exposed. Currently it is *already* broken (the bug this plan fixes).

**If this leaks, the user's data / workflow / money is exposed via:** N/A — the fix narrows exposure. The minted installation token is short-lived (≤60 min, scoped to the App installation) and replaces any ambient long-lived `GH_TOKEN`/PAT inherited from the parent env (the `hr-github-app-auth-not-pat` rationale). The token is injected only as `GH_TOKEN` into the `gh`/agent subprocess env (already allowlisted); it is never logged. The `redactToken` helper is available if the token must appear near any logged URL (not needed here — no clone URL is built).

**Brand-survival threshold:** none — internal operator automation, no end-user data surface, and the fix strictly reduces credential exposure.

`threshold: none, reason: internal operator cron automation with no end-user-facing surface; fix reduces credential blast radius by replacing ambient PAT with a short-lived installation token.`

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Token minted via GitHub App, not gh CLI.** `cron-follow-through-monitor.ts` imports `mintInstallationToken` from `./_cron-shared` and calls it inside a `step.run("mint-installation-token", …)` that runs BEFORE `validate-predicates`. Verify: `grep -n "mintInstallationToken" apps/web-platform/server/inngest/functions/cron-follow-through-monitor.ts` returns the import + the call site.
- [ ] **AC2 — Server-side `gh issue list` uses the minted token.** The `execFileSync("gh", …)` in `validate-predicates` is passed `buildSpawnEnv(installationToken)` (the token-parameterized form), NOT the zero-arg `buildSpawnEnv()`. Verify: `grep -n "buildSpawnEnv()" apps/web-platform/server/inngest/functions/cron-follow-through-monitor.ts` returns **zero** hits after the fix (all call sites take the token argument).
- [ ] **AC3 — Agent spawn uses the minted token.** `buildSpawnEnv(installationToken)` is passed to the `claude-eval` `spawn(...)` env. Verify: the `spawn(claudeBin, …, { env: buildSpawnEnv(<token-var>) })` call passes the token variable.
- [ ] **AC4 — `buildSpawnEnv` no longer reads `process.env.GH_TOKEN`.** `grep -n "GH_TOKEN: process.env.GH_TOKEN" apps/web-platform/server/inngest/functions/cron-follow-through-monitor.ts` returns **zero** hits; the function instead returns `GH_TOKEN: installationToken` (mirroring `cron-bug-fixer.ts:193`).
- [ ] **AC5 — `ensure-labels` step also uses the minted token.** The `ensure-labels` step's `gh label create` subprocess (line 305-328) receives `buildSpawnEnv(installationToken)` so label creation is authenticated too. (This step currently uses `buildSpawnEnv()` and would have the same auth failure once labels need creating.)
- [ ] **AC6 — Observability preserved.** All three `reportSilentFallback` call sites (`cron-ensure-labels`, `cron-validate-predicates`, `cron-claude-eval`) remain present and unchanged in semantics. Verify: `grep -c "reportSilentFallback" apps/web-platform/server/inngest/functions/cron-follow-through-monitor.ts` ≥ 3.
- [ ] **AC7 — Tests updated and pass.** `cron-follow-through-monitor.test.ts` mocks `mintInstallationToken` (via mocking its underlying deps `createProbeOctokit` + `generateInstallationToken`, OR by mocking `@/server/inngest/functions/_cron-shared` — match whichever the repo's existing tests use; bug-fixer mocks the underlying deps) and asserts: (a) the mint step ran before validate-predicates; (b) the `execFileSync` `gh issue list` call receives an env carrying the mocked token; (c) the `spawn` claude-eval env carries the mocked token. Verify: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-follow-through-monitor.test.ts` passes.
- [ ] **AC8 — No-BYOK gate still passes.** `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/cron-no-byok-lease-sweep.test.ts` passes (the minted installation token is NOT a BYOK lease; bug-fixer already proves this shape is compliant).
- [ ] **AC9 — Typecheck clean.** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` reports no new errors.
- [ ] **AC10 (if daily-triage folded in) — daily-triage mirrors the fix.** `cron-daily-triage.ts` mints + injects the token identically; `grep -n "GH_TOKEN: process.env.GH_TOKEN" apps/web-platform/server/inngest/functions/` returns **zero** hits repo-wide; daily-triage tests updated and pass. If NOT folded in, AC10 is replaced by: a follow-up issue exists (`gh issue view <N>`) titled for the daily-triage same-root-cause fix.

### Post-merge (operator)

- [ ] **AC11 — Container restart applies the fix.** `web-platform-release.yml` path-filtered `on.push` restarts the Docker container on merge to `main` touching `apps/web-platform/**` — the merge IS the remediation (no separate operator restart per `hr-monitor-not-run-in-background-for-polling` automation gate). No manual step.
- [ ] **AC12 — Next scheduled run is clean.** After the next `0 9 * * 1-5` fire (or a manual trigger `inngest send cron/follow-through-monitor.manual-trigger`), confirm via the Inngest run log / Sentry that the `validate-predicates` step no longer throws the `gh auth login` error. Verify via Sentry API (read-only) that no new event with the `gh auth login` signature lands for `soleur-runtime-cron-follow-through-monitor` after the deploy SHA. **Automation:** Sentry issue-events query by `fnId` + release SHA — deterministic verdict (zero new events = pass), per `hr-no-dashboard-eyeball-pull-data-yourself`.

## Implementation Phases

> NEVER CODE during planning. The phases below are the work-time blueprint. The contract-changing edit (token mint + `buildSpawnEnv` signature) comes BEFORE the consumer edits (per `2026-05-10-plan-phase-order-load-bearing`).

### Phase 0 — Preconditions (verify before editing)

1. Read `apps/web-platform/server/inngest/functions/cron-bug-fixer.ts` lines 50-79, 179-195, 626-635 — the canonical mint + `buildSpawnEnv(token)` pattern.
2. Read `_cron-shared.ts:31-42` — confirm `mintInstallationToken({ tokenMinLifetimeMs }): Promise<string>` signature.
3. Confirm `TOKEN_MIN_LIFETIME_MS` precedent: `cron-community-monitor.ts:75` and `cron-roadmap-review.ts:71` both use `50*60*1000 + 10*60*1000` (60 min). Adopt the same constant — the cron agent runs ≤15 min (`MAX_TURN_DURATION_MS`), so a 60-min min-lifetime token has ≥45 min headroom.
4. Read the test file `cron-follow-through-monitor.test.ts` (full) and `cron-bug-fixer.test.ts:60-70,142-166` to mirror the mock shape for `createProbeOctokit` + `generateInstallationToken` (the deps `mintInstallationToken` calls).

### Phase 1 — Write failing tests first (cq-write-failing-tests-before)

In `cron-follow-through-monitor.test.ts`:
- Add module mocks for `@/server/github/probe-octokit` (`createProbeOctokit`) and `@/server/github-app` (`generateInstallationToken`), mirroring `cron-bug-fixer.test.ts:60-70`. `generateInstallationTokenSpy.mockResolvedValue("ghs_TESTTOKEN_REDACT_ME")`.
- Add tests asserting: (a) a `mint-installation-token` step runs first; (b) the `execFileSync` `gh issue list` call's `env` argument carries `GH_TOKEN === "ghs_TESTTOKEN_REDACT_ME"`; (c) the claude-eval `spawn` `env` carries the same token; (d) `ensure-labels` `gh label create` spawn env carries the token.
- Run RED: confirm these fail against current code.

### Phase 2 — Fix `cron-follow-through-monitor.ts` (contract-changing edit first)

1. Add import: `mintInstallationToken` from `./_cron-shared` (extend the existing import block — currently imports `postSentryHeartbeat`, `type HandlerArgs`).
2. Add constant `const TOKEN_MIN_LIFETIME_MS = 50 * 60 * 1000 + 10 * 60 * 1000;` with the 60-min/15-min-agent rationale comment.
3. Change `buildSpawnEnv()` → `buildSpawnEnv(installationToken: string)` returning `GH_TOKEN: installationToken` (drop the `process.env.GH_TOKEN ?? process.env.GITHUB_TOKEN` read; update the comment to cite `hr-github-app-auth-not-pat` and the dropped-ambient-PAT rationale, mirroring `cron-bug-fixer.ts:179-186`).
4. Add a first `step.run("mint-installation-token", () => mintInstallationToken({ tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS }))` at the top of `cronFollowThroughMonitorHandler`, BEFORE `ensure-labels`. (Mint in its own step so the token is memoized across Inngest replay and not re-minted per step.)
5. Thread `installationToken` into all three `buildSpawnEnv(...)` call sites: `ensure-labels` (`const ghEnv = buildSpawnEnv(installationToken)`), `validate-predicates` (`execFileSync(..., { env: buildSpawnEnv(installationToken), … })`), `claude-eval` (`spawn(..., { env: buildSpawnEnv(installationToken) })`).
6. Run GREEN: Phase 1 tests pass.

### Phase 3 — (Conditional, recommended) Mirror in `cron-daily-triage.ts`

Apply the identical transform to `cron-daily-triage.ts` (mint step + `buildSpawnEnv(token)` + `GH_TOKEN: installationToken`). Update `cron-daily-triage.test.ts` to match. If the operator scopes daily-triage out, file the follow-up issue instead (see Open Code-Review Overlap / Blast-Radius Note) — do NOT leave it silent.

### Phase 4 — Verify

Run AC7-AC9 (and AC10 if folded). Confirm `grep -n "GH_TOKEN: process.env.GH_TOKEN" apps/web-platform/server/inngest/functions/` returns zero hits across the fixed files.

## Risks & Mitigations

- **R1 — Token min-lifetime too short for the 15-min agent run.** Mitigated: 60-min min-lifetime token (precedent: community-monitor/roadmap-review) gives ≥45 min headroom over the `MAX_TURN_DURATION_MS = 15min` agent budget. `generateInstallationToken`'s `minRemainingMs` guarantees the cached token has ≥60 min left or it re-mints (`github-app.ts:481`).
- **R2 — Mint step adds a GitHub App API round-trip per run.** Acceptable: 5 weekday runs/day; `generateInstallationToken` caches the token across invocations within its lifetime (`github-app.ts:480-481`). Same cost profile as 22+ peer crons already in production.
- **R3 — Installation token scope.** The App installation token already grants `issues:write` + `pull_requests:write` (proven by `cron-bug-fixer.ts` running `gh issue view/edit/comment/close` and `gh pr create` against the same token). No new permission needed; this is the identical credential.
- **R4 — `mintInstallationToken` throws (App private key missing/invalid in prod).** Then the new mint step throws and Inngest's `retries: 1` retries; on persistent failure the step error surfaces (Inngest run marked failed + the function's existing Sentry instrumentation). This is the correct loud-failure behavior — a missing App key is a real prod misconfiguration, not something to swallow. Precedent: bug-fixer's mint step has the same failure semantics.
- **R5 — `buildSpawnEnv` signature change is a breaking contract within the file.** Mitigated by phase ordering: the signature change + all three call-site updates land in the same edit (Phase 2). `tsc --noEmit` (AC9) catches any missed call site.

## Observability

```yaml
liveness_signal:
  what: "Sentry cron monitor check-in (postSentryHeartbeat) at end of every run"
  cadence: "0 9 * * 1-5 (weekday 09:00 UTC) + manual-trigger event"
  alert_target: "Sentry cron monitor slug 'scheduled-follow-through' (apps/web-platform/infra/sentry/cron-monitors.tf)"
  configured_in: "cron-follow-through-monitor.ts:523-530 (sentry-heartbeat step)"
error_reporting:
  destination: "Sentry via reportSilentFallback (cron-validate-predicates, cron-ensure-labels, cron-claude-eval, cron-claude-eval spawn-error)"
  fail_loud: "yes — handled=yes Sentry events; mint-step failure surfaces as Inngest run failure (R4)"
failure_modes:
  - mode: "gh CLI unauthenticated (THIS BUG)"
    detection: "Sentry event with 'gh auth login' signature on fnId soleur-runtime-cron-follow-through-monitor"
    alert_route: "Sentry issue alert (existing); fixed by this PR — should drop to zero post-deploy"
  - mode: "GitHub App key missing/invalid in prod"
    detection: "mint-installation-token step throws → Inngest run failure + Sentry"
    alert_route: "Sentry + Inngest failed-run surface"
  - mode: "predicate validation fails (DNS/HTTP)"
    detection: "reportSilentFallback in validate-predicates catch; agent proceeds SLA-only"
    alert_route: "Sentry (handled)"
logs:
  where: "logger.info/warn structured logs (Inngest run logs); Sentry for errors"
  retention: "per Sentry/Inngest platform defaults"
discoverability_test:
  command: "After deploy, query Sentry issue-events for fnId=soleur-runtime-cron-follow-through-monitor with release>deploy-SHA; OR manually trigger: inngest send cron/follow-through-monitor.manual-trigger and read the Inngest run log"
  expected_output: "validate-predicates step succeeds (no 'gh auth login' error); summary table emitted; sentry-heartbeat check-in OK"
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — this is an infrastructure/runtime auth fix on an internal operator cron. No user-facing UI, no schema, no regulated data, no new infrastructure (reuses the existing GitHub App installation-token path). Product/UX gate: NONE. GDPR gate (Phase 2.7): skipped — no regulated-data surface; the fix narrows credential exposure. IaC gate (Phase 2.8): skipped — no new server/secret/vendor/cron; the cron already exists and the GitHub App credential is already provisioned.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is filled; threshold = none with a non-empty reason.)
- **`buildSpawnEnv()` zero-arg form must be fully eliminated.** There are THREE call sites (`ensure-labels`, `validate-predicates`, `claude-eval`) — missing any one leaves an unauthenticated subprocess that fails at runtime but passes `tsc` only if the old zero-arg signature is also kept. The fix MUST change the signature (so `tsc` flags every un-migrated caller) — do not add an overload.
- **Do not log the token.** `buildSpawnEnv` injects it only as an env var; no clone URL is built here (unlike bug-fixer), so `redactToken`/`buildAuthenticatedCloneUrl` are not needed. If a future edit logs subprocess env, redact `GH_TOKEN`.
- **daily-triage's failure shape differs.** Its `gh` calls fail *inside* the agent (no server-side `execFileSync`), so it does NOT throw the exact Sentry signature this plan targets — but it is the same root cause and the same fix. Don't assume "no Sentry error = not broken."

## Alternative Approaches Considered

| Approach | Why not |
| --- | --- |
| Run `gh auth login` / set `GH_TOKEN` env in the container | Violates `hr-github-app-auth-not-pat` (PAT in prod). Long-lived credential, no rotation, larger blast radius. |
| Replace the `gh issue list` `execFileSync` with a direct Octokit `issues.listForRepo` call | Cleaner for the server-side step in isolation, BUT the AGENT still runs `gh issue view/edit/comment/close` in-prompt and needs `GH_TOKEN` regardless. Minting the token covers both surfaces with one change; rewriting only the server-side call would leave the agent's `gh` calls still broken. The mint-and-inject approach is strictly necessary and is the established peer pattern. (A follow-up could migrate the server-side list to Octokit for type-safety, but that's out of scope for the prod-fix.) |
| Mint the token inside `validate-predicates` (not a separate step) | Inngest replay would re-mint per retry and the agent step wouldn't share it cleanly. A dedicated first `step.run` memoizes the token across replay — peer-cron precedent (bug-fixer, community-monitor). |
