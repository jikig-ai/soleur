---
title: Inngest cron functions invoke claude-code via child_process.spawn
status: active
date: 2026-05-18
---

# ADR-033: Inngest cron functions invoke claude-code via child_process.spawn

## Context

PR-F (#3940, MERGED 2026-05-17) shipped the Inngest substrate self-hosted on Hetzner as the durable trigger layer for server-side agents (see [ADR-030](./ADR-030-inngest-as-durable-trigger-layer.md)). The first registered function — `cfo-on-payment-failed.ts` — is event-triggered and invokes the Anthropic SDK directly via `runWithByokLease` inside `step.run`.

The TR9 slice (#3948) migrates ~11 recurring "agent-loop" cron workflows from `.github/workflows/scheduled-*.yml` (currently invoked by `anthropics/claude-code-action` on GitHub Actions runners) to Inngest cron functions running inside the long-lived Node worker on the Hetzner host. The substrate-gap question driving this ADR is: **how do Inngest cron functions invoke `claude-code`?**

The two execution models differ in posture:

- `claude-code-action` spawns a **fresh ephemeral runner** per invocation, with a pristine `~/.claude/`, a 60-min GitHub Actions timeout, and runtime-injected agent prompt text. State does not survive across runs.
- Inngest functions are **long-lived worker processes** with `step.run` memoization (each step re-emits its memoized result on replay). The worker process owns its filesystem state.

Without a deliberate choice, the next 11 migration PRs would each independently re-invent how to invoke the agent — guaranteeing drift on the failure-mode-prevention contract (idempotency, replay-safety, cost ceiling). The decision must be made BEFORE PR-1 (`scheduled-daily-triage` migration) lands code, so every subsequent migration cites a single accepted invariant set.

Operator confirmed the decision 2026-05-18 during brainstorm Phase 1.2; recorded as K9 in `knowledge-base/project/brainstorms/2026-05-18-tr9-agent-loop-crons-inngest-migration-brainstorm.md`. CTO assessment (h) and CPO sign-off both accepted the spawn-child path.

## Considered Options

- **Option A: `child_process.spawn('claude-code', [...args])` inside `step.run('claude-eval', ...)`.** Treats `claude-code` as an external binary executed per step. Stdout/stdin/exit-code captured deterministically so `step.run` memoizes correctly on replay. Agent prompt loaded from a co-located `*.prompt.md` file (or inline string). Operator `ANTHROPIC_API_KEY` passed via env. **Pros:** preserves existing claude-code-action agent prompts as-is (no rewrite); lower-risk port; per-step memoization comes for free if stdout capture is deterministic; the spawn boundary is a natural place to enforce a per-step timeout via `AbortSignal`. **Cons:** spawn surface is one more failure mode (binary missing, version drift, working-directory assumptions); requires `claude-code` CLI on the Hetzner worker image with a pinned version.

- **Option B: SDK rewrite — invoke `@anthropic-ai/sdk` directly inside Inngest functions.** Port each agent prompt + tool-use loop into TypeScript code running in-process. **Pros:** no subprocess surface; full control over conversation state; no binary version-pinning; tighter integration with Inngest's `AbortSignal` + step boundaries. **Cons:** re-implements claude-code's tool-use orchestration, MCP server connections, the agent loop, file-edit primitives, and prompt-caching logic; 11× the per-workflow port cost; loses the prompt-file portability that claude-code-action already provides; tool-use bugs ship per-workflow instead of being centralized in one well-tested binary.

- **Option C: Inngest "function-as-CI" — keep claude-code-action, just have Inngest dispatch a GitHub Actions workflow_dispatch.** Inngest function fires on schedule, calls the GitHub API to dispatch the same `claude-code-action`-based workflow that exists today. **Pros:** zero migration of the agent invocation itself; reuses existing battle-tested action. **Cons:** doesn't actually migrate cron off GitHub Actions — defeats the purpose of TR9 entirely (the rationale is replacing GitHub Actions' jitter + lack-of-replay/idempotency with Inngest's). The cron scheduling moves but the execution doesn't; the failure modes the migration is meant to fix (silent failure, replay safety, observability) remain.
  - **Scope note (2026-06-02, terraform-drift migration):** this Option-C rejection is specific to the **agent-loop** crons, whose whole point was to move `claude-code` execution off GHA. For a **credential-heavy infra cron** whose execution *must* stay in an ephemeral runner (e.g. `scheduled-terraform-drift`: terraform binary + R2/AWS/Doppler `prd_terraform` cloud-admin creds that must NOT be parked on the long-lived app host), Option C is the *correct* shape — only goal (a) "kill GHA scheduling jitter" applies; goal (b) "move execution in-process" is actively harmful. See `apps/web-platform/server/inngest/functions/cron-terraform-drift.ts`. Do not mis-cite this rejection as a blanket ban on Inngest→workflow_dispatch.
  - **Anti-circularity corollary (2026-08-03, #6808 — `workspaces-luks-verify`):** the scope note above says *when* Option C is the right shape. This corollary says when **even Option C is wrong**, and a native GHA `schedule:` is the only correct trigger. **A verifier must not be EXECUTED by the host it verifies.** Be precise about which half: since the #6178 dedicated-host cutover (ADR-100, which explicitly supersedes the #5450 same-host durable-backend framing) the Inngest *scheduler* runs on its own host (`hcloud_server.inngest`, 10.0.1.40), so scheduling is genuinely off web-1. *Execution* is not. Inngest sends every function step to the serve URL the app registers — `serveHost` = `https://app.soleur.ai` in `apps/web-platform/app/api/inngest/route.ts` — and `cloudflare_record.app` resolves that name to **web-1** only, with no failover to web-2 (serving-weight 0, ADR-143 D2). `[corrected 2026-09-28, #7230]` `workspaces-luks-verify` exists to detect that web-1's `/mnt/data` is no longer on the LUKS mapper — up to and including "web-1 is gone". Under Option C the `cron-*.ts` that issued the dispatch would run on the subject itself: if web-1 is down the callback never lands, the function never executes, no `workflow_dispatch` is issued, and the check reports nothing in exactly the failure it was built for — silence, read as health. That is not a jitter or an observability trade-off, it is a circular dependency between a monitor and its target, and no amount of retry or alerting inside the dispatcher can remove it. The test is mechanical: *if the thing being checked fails completely, can the trigger still fire?* Where the answer is no, the trigger must live outside the failure domain — a native `schedule:` (no dependency on web-1) or a third-party scheduler. Note this cuts the opposite way from goal (a): the native trigger accepts GHA scheduling jitter, and its own dropped-run mode is covered one layer further out by the `workspaces-luks-verify` Sentry Crons monitor, because a monitor that cannot report a missed run has the same defect one level up. Applies to any host-state verifier, not only this one. **This corollary is a consequence of a topology, not a law of nature: it binds only because Inngest function EXECUTION is pinned to web-1 by the registered serve URL (`serveHost` = `https://app.soleur.ai`) plus `cloudflare_record.app` resolving to web-1 only. `[corrected 2026-09-28, #7230]` Decoupling execution from web-1 is tracked at #7230 (the placement rule) and #9137 (placement-aware execution) — which functions spawn `claude-code` (I1) or operate on the sole-copy `/mnt/data` LUKS volume (ADR-119) is recorded per function in `apps/web-platform/server/inngest/execution-placement.ts`, and those host-bound functions are why the realistic outcome is a split rather than a move. If that split ever lands, re-derive this corollary against the then-current topology instead of assuming it still holds.**
  - **Addendum — 2026-09-24 (#8495):** a native `schedule:` alone measured one run per 2–7 h for the `*/15` Inngest watchdog, so watchers of the scheduling substrate are now dispatched by an in-process web-server clock with `schedule:` as the fallback, under an explicit eligibility rule — see [ADR-248](ADR-248-watchdog-dispatch-clock-runs-in-the-web-server.md).

## Decision

**Choose Option A.** Every Inngest cron function in `apps/web-platform/server/inngest/functions/cron-*.ts` invokes `claude-code` via `child_process.spawn` inside a `step.run('claude-eval', ...)` step.

The decision lands with PR-1 of #3948 (proof-of-pattern `scheduled-daily-triage` migration). This ADR may be superseded if a future operator decides the SDK-rewrite cost has dropped (e.g., after Anthropic ships a higher-level Node SDK matching claude-code's agent-loop primitives, or after 3+ workflows reveal spawn-boundary friction that the SDK avoids).

**Load-bearing invariants** (binding all 11 subsequent migrations):

- **I1.** `claude-code` is spawned INSIDE `step.run` (not at function entry). Step memoization is what protects against replay-cost runaway; spawning at entry escapes step memoization and triggers fresh Anthropic API calls on every replay.
- **I2.** Operator `ANTHROPIC_API_KEY` ONLY — never founder BYOK. Enforced via inverse-assertion in `apps/web-platform/test/server/byok-audit-writer-sweep.test.ts`: files matching `server/inngest/functions/cron-*.ts` MUST NOT import `runWithByokLease`. This is the "no-founder-context" boundary marker (see also I6).
- **I3.** `AbortSignal` aborts the spawned process at **60 minutes** (matches the old GitHub Actions `timeout-minutes: 60` ceiling and preserves the 0.75 min/turn peer-ratio floor for an 80-turn budget — see `2026-03-20-claude-code-action-max-turns-budget.md`). The `AbortSignal` is plumbed from Inngest's per-step timeout into the `child_process.spawn` options. Abort handler escalates with manual `process.kill(-child.pid, "SIGTERM")` then SIGKILL after 5 s on a `detached: true` process group so grandchildren (bash, gh) do not orphan. `[Refined 2026-05-18 post PR-1 plan review — 5-agent panel converged that the original 55-min figure under-fired the peer ratio; rollback-headroom rationale dropped since Inngest replays do not depend on spawn ceiling.]`
- **I4.** `claude` binary (npm package `@anthropic-ai/claude-code`) is **pinned via `apps/web-platform/package.json` dependency**. The existing deploy pipeline runs `npm install` on the Hetzner worker; the npm package's `postinstall` downloads the platform-native binary and exposes it at `node_modules/.bin/claude`. Inngest functions resolve the absolute path at module load via `createRequire(import.meta.url).resolve("@anthropic-ai/claude-code/package.json")`. The npm package installs the binary under the name `claude` (NOT `claude-code` — that is only the npm-registry package name). `[Refined 2026-05-18 post PR-1 plan review — original cloud-init pin was an extra IaC dance for no upside; the dep already ships via the same release artifact as the application code.]` `[Refined 2026-05-26 post TR9 PR-11 — I4 binary pin surface now includes Chromium, pinned transitively via @playwright/test devDep at docker build time (npx playwright@1.58.2 install --with-deps chromium). The @playwright/test package itself is a devDep omitted from the runner's npm ci --omit=dev; only the browser binary + system libs persist in the image. The Chromium revision is frozen in the image; drift between image-baked Chromium and any future @playwright/test bump is caught by the existing lockfile-sync CI gate.]`
- **I5.** Stdout/exit-code captured **deterministically** so `step.run` memoization fires reliably. Inngest's memoization is keyed on the serialized step result; if claude-code's stdout includes nondeterministic timestamps or progress chatter, memoization breaks and replays re-spawn the agent. PR-1 must verify deterministic capture via the FR10 integration test (second invocation in succession MUST NOT re-spawn).
- **I6.** Event payloads emitted by `cron-*` functions carry `actor: "platform"` tag. This is the boundary marker that lets platform-loop crons + per-founder runtime share one Inngest server; without it, `hr-gdpr-gate-on-regulated-data-surfaces` fires the moment PR-G (#3947) ships founder cohort exposure.
- **I7.** Cron containment is a **deny-by-default `PreToolUse` hook**, NOT the OS bash sandbox and NOT `--allowedTools`/`permissions.defaultMode`. `[Added 2026-06-08 — #5018/#5000/#5004.]` The substrate's `DEFAULT_CLAUDE_SETTINGS` sets `sandbox.enabled:false` (host-independence — immune to the recurring bwrap-userns drift #4928/#4932 that broke #5000/#5004) and registers `cron-bash-allowlist-hook.mjs` under a `*` catch-all matcher via `buildCronEvalSettings`. Phase-0 probes (committed AC0 evidence; re-verified on the prod-pinned CLI 2.1.79) proved that with the sandbox off, headless `claude --print` does **NOT** fail-close non-allowlisted commands via `--allowedTools` or any `defaultMode` (dontAsk/default/auto all fail-OPEN), and an unhooked tool class / a crashed hook **fails OPEN** — so the hook is the only fail-closed boundary. Load-bearing sub-invariants: (a) deny-by-default at the **tool-class** level (catch-all + explicit Read/Grep/Glob secret-path deny + Bash allowlist + Write/Edit self-protection) — `bypassPermissions` (the v1 P1-blocked exfil primitive) MUST NOT reappear; (b) **secret-out-of-context** is the real safety property — every env/secret-read path (env dump, `/proc`, `.git/config` where the clone URL embeds the token) is denied across Bash AND Read/Grep, so the allowed egress verbs (`gh issue create`, `git push`) can't leak a secret never read; (c) a **spawn-time self-test** (`runHookSelfTest`) asserts the hook denies a canonical exfil payload before any agent spawns — a failure aborts the cron (→ FAILED self-report) rather than running unprotected; (d) per-cron `--allowedTools` and `permissions.deny` are documented defense-in-depth, NOT relied upon. **Negative guarantee:** this containment governs the claude-code tool layer ONLY — it does NOT extend to Node-level `child_process.spawn("bash", …)` (cron-content-publisher / content-vendor-drift / rule-prune / weekly-analytics bypass it entirely). Those + the broad-bash crons (`TIER2_DEFERRED_CRONS`) are paused (D6) until restored under finite allowlists. `[Refined 2026-06-10 — #5046 PR-2/ADR-052.]` The Tier-2 boundary LANDED: the 4 spawn-bash crons are now contained by the DOCKER-USER container egress allowlist (ADR-052 — content-blind, off-allowlist-severing), and the hook's catch-all was relax-minimally opened to `Task`/`Agent`/`Skill` ONLY (every Bash/secret-read layer intact; gated by extended `runHookSelfTest` probes incl. a `*`-matcher registration check). That restored exactly the two crons whose sole denied construct was `Task` (cron-agent-native-audit, cron-legal-audit — issue-creator allowlists + a `contents:read`+`issues:write` token); the remaining nine stay deferred pending per-construct allowlist refinement (six PR-flow crons) or non-GitHub-egress coverage (bug-fixer, community-monitor, ux-audit). Only crons whose entire command surface is a finite allowlist (`CRON_BASH_ALLOWLISTS`) are restorable.

- **I8.** **Classify-fatal heartbeat + widened `routine_runs` failure contract.** `[Added 2026-06-29 — #5674.]` A claude-eval non-zero exit is NOT uniformly green and NOT uniformly red — it is **classified** from the captured stdout/stderr tail (`resolveBestEffortEvalOk` / `classifyEvalFatal` in `_cron-shared.ts`, single source of the fatal markers, shared with the credit-probe canary):
  - a **FATAL class** — credit exhausted (`/credit balance is too low/i`), auth/401 revoked (`invalid x-api-key` / `authentication_error`), spawn fault (`exitCode === -1` / `ENOENT`/`EACCES`), OR `abortedByTimeout` — MUST flip the Sentry monitor RED (`postSentryHeartbeat({ ok:false })`) and write a `routine_runs.failed` row carrying the redaction-scrubbed reason;
  - a **BENIGN** non-zero exit (`claude --print` hitting max-turns, clean no-artifact) MUST stay GREEN (liveness) but still record the reason via `warnSilentFallback` + a scrubbed `sentryExtra`.

  This **supersedes and reconciles** the 2026-06-01 decision (incident `5127648` / #4730 / PR #4727) that decoupled the heartbeat from `spawnResult.ok` — that fix correctly stopped benign max-turns false-pages; classify-fatal keeps that protection while restoring a red signal for the genuinely-fatal classes it over-suppressed (the 2026-06-29 credit-exhaustion incident: the whole fleet no-op'd with green monitors). The four masked best-effort crons (`cron-agent-native-audit`, `cron-legal-audit`, `cron-ux-audit`, `cron-bug-fixer`) route every non-zero exit through `resolveBestEffortEvalOk`; the eight output-aware producers keep `resolveOutputAwareOk` (output presence is their success contract) but now also emit a scrubbed `error_summary`.

  **Widened `routine_runs` contract:** for ANY `ROUTINE_METADATA` cron, a handler that **returns** `data.ok === false` (without throwing) is recorded `failed`. The run-log middleware (`middleware/run-log.ts`) gates ONLY the **thrown** path on the final-attempt retry window — a returned `ok:false` is *terminal* under `retries:1` (no retry) and is written immediately (gating it on the final attempt would drop the exact failure we record). The failure reason (scrubbed last-N stdout/stderr) reaches BOTH Sentry and `routine_runs.error_summary`. Every new tail sink (`formatTailForSentry`) routes through the canonical multi-secret scrubber (`redactGithubSourcedText`), not just `redactToken` — closing a pre-existing `sk-ant` Sentry leak in `resolveOutputAwareOk`.

  **No-balance-endpoint canary.** Anthropic exposes NO remaining-credit/prepaid-balance endpoint (verified live 2026-06-29 against the usage/cost API docs); the Admin Usage/Cost API reports *spend* only, under a separate `sk-ant-admin` key. So credit exhaustion is detected by an hourly 1-token canary (`cron-anthropic-credit-probe.ts`) on the operator `ANTHROPIC_API_KEY` (NOT a BYOK lease — I2), which pages on the classified credit-400 / auth-401 and **re-throws** transient/unclassified errors (429/500/529/network) so Inngest retries and the missed-checkin margin backstops (a 529 overloaded is not an empty wallet — false-paging it would itself be the alert-fatigue bug). Pre-exhaustion spend-vs-budget alerting via the Admin `cost_report` API is a deferred follow-up (`Ref #5674`) — it needs the new `sk-ant-admin` secret + an operator-set `ANTHROPIC_MONTHLY_BUDGET_USD` (no sensible default), so shipping it half-configured would false-alarm or never fire.

  **Alternatives considered (rejected):** (1) the prior *unconditional* "liveness, not success" green check-in — wrong because credit-exhaustion non-zero was indistinguishable from clean-no-artifact at the monitor level (the 2026-06-29 incident); (2) **flip-all non-zero → red** — rejected: reintroduces the #4730 daily false-page because `claude --print` exits non-zero on healthy max-turns runs, and pollutes `routine_runs` with false-`failed` rows; (3) the `in_progress → ok/error` two-phase check-in — not needed once classify-fatal distinguishes the classes at the source. Residual risk: **marker drift** — a new fatal mode whose tail matches no marker stays green; mitigated by keeping the marker set small/centralized/fixture-pinned and by the benign path still recording the reason in `routine_runs` (visible-but-not-paged, never invisible). Two further residuals, both accepted (review #5680): (a) **`abortedByTimeout` pages even on a *healthy* long run** — a cron that legitimately exhausts the 60-min budget (most plausibly `cron-bug-fixer`, the highest benign-non-zero-frequency cron) now flips RED rather than staying green-with-a-Sentry-error as before; this is **intended** — a budget overrun is a degraded outcome worth one page, and the alternative (a per-cron timeout exemption) reintroduces exactly the per-handler special-casing this design removed. If timeout-paging proves noisy in practice, raise the budget (I3) rather than re-exempting the class. (b) **The fatal-marker regexes match two distinct text sources** — the claude-CLI stdout/stderr tail (resolver) and the Anthropic HTTP JSON error body (canary) — coupling both detectors to one phrasing; robust today via case-insensitive substring and fixture-pinned, but a marker reword must be validated against both source shapes.

  **Amendment `[2026-06-29 — #5728]` — heartbeat-DELIVERY guarantee (the gap I8 left).**
  I8 reasoned about classifying a non-zero *exit* and **assumed the run reaches the
  `sentry-heartbeat` step**. #5728 surfaced the orthogonal case: the heartbeat is
  **never delivered** — the run is SIGKILLed mid-eval, a step *throws* before the
  heartbeat, or the single terminal POST is dropped (5xx/network/timeout) — so
  Sentry records a server-generated **`missed`** (not a client `?status=`).
  classify-fatal cannot color a check-in that never posts. Phase-0 evidence
  (`routine_runs` + Sentry checkins; Better Stack aged out) found the 2026-06-13→
  06-21 window was **SIGKILL-dominant** (zero `routine_runs` terminal rows while
  sibling crons logged normally) — whose remedy is the **graceful cron drain before
  container swap (ADR-078 / #5686)**, NOT a heartbeat-code change. The #5728 code fix
  closes the *delivery* gap for the throw/dropped-POST classes (defense-in-depth) via
  (i) a final-attempt-gated, memoization-safe terminal `?status=error` on the throw
  path (`finalizeOutputAwareHeartbeat`, adopted fleet-wide by the output-aware cohort),
  and (ii) a bounded retry (5xx/network/timeout; never 4xx) on the heartbeat POST.

  **The `in_progress → ok/error` two-phase check-in REMAINS REJECTED** (alternative
  (3) above) — single end-of-job POST stays the doctrine.
  **Recorded rejection COST (do not re-open the I8 debate):** without the
  run-correlation id an `in_progress` beacon would provide, a **late / retry-chain
  finish cannot reconcile to its scheduled period** — a standalone late `?status=ok`
  does NOT retroactively clear a `missed`. Therefore for the slow/late/killed class,
  **`checkin_margin_minutes` (sized against the worst-case retry-chain + shared
  `account` `limit:1` queue wall-clock, not single-run duration) and kill-prevention
  (ADR-078) are the ONLY levers** — Phase 1/2 delivery-hardening cannot close it.
  **Accepted residual:** a genuinely killed run reads `missed` until a late retry, and
  `missed` is an honest signal for a killed run. Runbook H11 carries the per-day
  H11a–d discrimination recipe. (For #5728 the verdict was kill-dominant with H1/H4
  only plausible on routine_runs-blind days, so the margin was left at 60 — no TF
  diff.)
  **Inngest-run-status vs. Sentry divergence (deliberate).** On a final-attempt
  genuine failure the output-aware cohort posts `?status=error` and **returns
  `{ok:false}` rather than throwing** (unlike the `cron-stale-deferred-scope-outs`
  precedent which rethrows). So the Inngest run is marked *succeeded* while the
  Sentry monitor is RED. This is intentional and preserves the pre-#5728 producer
  behavior: paging is driven by the Sentry check-in, and the failure is also
  recorded as a `routine_runs.failed` row (the I8 widened-contract: a returned
  `data.ok === false` is recorded `failed`) — so the failure is observable via two
  layers without relying on Inngest's native run status. If Inngest-level failure
  alerting is ever introduced, revisit this choice.

- **I9. Structured `--output-format json` for per-run cost capture.** `[Added 2026-07-09 — feat-anthropic-cost-attribution.]` `spawnClaudeEval` now requests `--output-format json` (injected at argv index, mirroring the `--strict-mcp-config` prepend, ONLY when the caller's `flags` do not already set `--output-format`) so the final `{"type":"result",…}` event carries the CLI's own authoritative `total_cost_usd` / `usage` / model (the model id is the KEY of `modelUsage`; Phase-0 live probe pinned the shape). A `SOLEUR_CLAUDE_COST` marker is emitted on EVERY child exit with a positive `capture_status` (`ok` | `no-result-event` | `parse-error` | `timeout`).

  **Reconciliation with I8 (the load-bearing constraint).** The credit/auth/spawn-fault classifier `classifyEvalFatal` substring-matches `stdoutTail + stderrTail`. Under the JSON format the CLI's stdout is a single result object, NOT free text, so the substrate **extracts the result event's human-readable `.result` text (which carries the API error message on an error run) back INTO `stdoutTail`** (via the pure `parseClaudeResultLine` helper) rather than letting raw JSON crowd the bounded tail. stderr is unchanged by `--output-format`, so an Anthropic API error still reaches `stderrTail` independently. I8 classification therefore survives: a credit-exhausted / auth-failed / spawn-fault run still classifies fatal, a benign max-turns run still classifies benign (unit-pinned; Phase-0 live confirmation cited in the plan's `## Research Insights`).

  **Reconciliation with I5 (deterministic capture).** `SpawnResult` gains optional `costUsd?` / `usage?` / `model?` (optional so inline-spawn sibling crons that build their own `SpawnResult` literals stay compiling). The FR10 memoized-step test stays green — the cost fields ride the same deterministically-captured exit path; a parse failure / old text format degrades the fields to `undefined` (fail-open), never a red run. Cost capture is wrapped and NEVER rethrows, so a logging failure cannot red a cron.

## Consequences

**Easier:**

- Migration cost per workflow drops to "translate the YAML to a 50-line TS file" — agent prompts move as-is from inline-YAML to `*.prompt.md` files co-located with the function.
- Replay safety is in scope of the existing Inngest contract — every cron-* function inherits the same `step.run` memoization story without per-function reasoning.
- The `AbortSignal` + 60-min ceiling gives a single consistent cost-runaway primitive across all 11 migrations (where GitHub Actions had 11 different `timeout-minutes` values to reason about).
- Single point of CLI upgrade across all 11 workflows (Hetzner cloud-init), instead of bumping `claude-code-action` version across 11 YAML files.
- Future workflow additions are mechanical: drop a new `cron-*.ts` file and a new `*.prompt.md`, register in `inngest.createFunction({cron: "..."}, ...)` — no GitHub Actions YAML at all.

**Harder:**

- Hetzner Inngest worker image must include `claude-code` with a pinned version (cloud-init or systemd unit). One more thing to keep in IaC drift-check.
- Spawn boundary introduces a `child_process` failure mode class (binary not found, working-directory assumptions, env-var inheritance gotchas). Per-function integration tests must exercise the spawn path.
- Stdout determinism is load-bearing for replay-cost safety; any future `claude-code` upgrade that adds nondeterministic stdout chatter silently breaks memoization. Mitigation: FR10 jitter-guard integration test catches it (second invocation MUST early-return without spawning).
- The 11 follow-up PRs all depend on the spawn primitive landing in PR-1. If PR-1's spawn primitive is wrong, fixing it requires a cross-cutting touchup of every migrated cron-* file (mitigated by per-workflow PR shape — the substrate primitive lives in a shared helper, not per-function code).

**[Refined 2026-05-19 post PR-2 plan review — account-scope concurrency keying]**

PR-2 (`cron-follow-through-monitor`) shares the `account`-scope `"cron-platform"` concurrency slot with PR-1 (`cron-daily-triage`). Decision: KEEP the global `"cron-platform"` key (vs per-function-class key like `"cron-platform-${fn.id}"`) at PR-2 scope. Rationale:

- Two cron-* functions today; schedule overlap impossible (PR-1 fires `0 4 * * *` daily, PR-2 fires `0 9 * * 1-5` weekdays).
- Manual-trigger latency upper bound under global keying = `max(MAX_TURN_DURATION_MS)` across all cron-* = 60 min (PR-1's daily-triage). Acceptable at PR-2 scale.
- Hetzner OOM protection that motivated the global slot at PR-1 remains correct: per-function-class keying would shift sizing budget from `max` to `Σ` and require Hetzner node up-sizing as the cron-* fan-out grows.

**Re-evaluation criterion:** if Monday drain time exceeds 4 hours OR any single function waits >120 minutes in the queue, split to dual pools. Switching to per-function-class keying (`{scope: "account", key: '"cron-platform-${fn.id}"', limit: 1}`) is mechanically simple (30-min find-and-replace) but requires concurrent Hetzner sizing review. `[Updated 2026-05-26 — original "past 3 functions" threshold replaced with empirical drain-time threshold; see Phase 2 refinement below.]`

**[Refined 2026-05-26 post TR9 Phase 2 plan review — schedule staggering + file prefix conventions]**

Phase 2 (#3948) migrates 21 additional functions to the single `cron-platform` pool (limit: 1), bringing the total to ~35 registered Inngest functions. The 5-agent plan review (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow-analyzer) converged: dual pools are premature optimization; schedule staggering solves the real problem (Monday collision) at zero prerequisite cost.

**Schedule staggering strategy:**

- Monday is the heaviest day: 6+ cron functions fire between 06:00-16:00 UTC.
- Stagger Monday-scheduled functions by ≥90 minutes so queue depth never exceeds 2.
- Applied stagger offsets (vs original schedules):
  - `cron-growth-audit`: 09:00→07:00 UTC
  - `cron-seo-aeo-audit`: 10:00→11:00 UTC
  - `cron-linkedin-token-check`: 09:00→11:00 UTC (runs in parallel with seo-aeo-audit since both are <5 min pure-TS)
- Synthetic Sentry monitor `cron-platform-monday-drain` expects heartbeat by 18:00 Monday — if queue hasn't drained, missed check-in fires alert.

**File prefix conventions for `server/inngest/functions/`:**

| Prefix | Schedule | Sentry cron monitor | Example |
|--------|----------|--------------------|---------|
| `cron-` | Recurring (Inngest `cron:` field) | Yes — a `sentry_cron_monitor` resource (declaring it applies it; full-root apply since #6589, no `-target=` line) | `cron-daily-triage.ts` |
| `oneshot-` | One-time fire, no recurring schedule | No — error alerting only via `reportSilentFallback` | `oneshot-gdpr-gate-50d-eval.ts` |
| `event-` | Triggered by `inngest.send()` (manual or cascade) | No — no recurring schedule to monitor | `event-ship-merge.ts` |
| `_` (underscore) | N/A — shared helper, not a function | N/A | `_cron-shared.ts` |

Oneshots and event-triggered functions do NOT get `sentry_cron_monitor` resources. Sentry cron monitors would permanently false-alert on missed check-ins for functions that have no recurring schedule.

### Registration checklist (a NEW `cron-*` claude-eval function)

``[Added 2026-06-30 — #5631. Revised 2026-07-17 — #6589: was eight; the `-target=` allow-list location is gone (full-root apply), leaving seven. Revised 2026-09-28 — #7230: row 8, the execution-placement manifest, makes it eight again.]`` Adding a recurring claude-eval cron touches **eight** gated locations, not the "four" (handler + manifest + metadata + serve route) often cited in PR bodies. Each location below has a CI gate that fails closed; a stale or bot-generated PR that ran before some gate existed will look green until rebased onto current `main`. Mirror the structurally-closest live cron (claude-eval + `safeCommitAndPr` ⇒ `cron-seo-aeo-audit.ts`) signature-for-signature rather than writing the handler from the substrate's prose.

| # | Location | What to add | Gate that catches an omission |
|---|----------|-------------|-------------------------------|
| 1 | `server/inngest/functions/cron-<name>.ts` | Handler using the REAL substrate API (`spawnClaudeEval({spawnCwd, buildSpawnEnv, …})`, `mintInstallationToken({tokenMinLifetimeMs, repositories})`, `resolveOutputAwareOk({spawnOk, …})`). Prompt MUST carry `PERSISTENCE: Do NOT run git add` for safe-commit crons. | `web-platform-build` (`tsc`) + `cron-safe-commit-parity` (prompt anchor) |
| 2 | `app/api/inngest/route.ts` | `import` + entry in the `functions: [...]` array | `function-registry-count (a)` count + `(e)` watchdog set |
| 3 | `server/inngest/cron-manifest.ts` | `EXPECTED_CRON_FUNCTIONS` entry | `cron-inngest-cron-watchdog` parity |
| 4 | `server/inngest/routine-metadata.ts` | `ROUTINE_METADATA` entry | routine-metadata parity test |
| 5 | `server/inngest/functions/_cron-claude-eval-substrate.ts` | `CRON_BASH_ALLOWLISTS` entry (or `TIER2_DEFERRED_CRONS` if deferred) — substrate-contained crons MUST be in exactly one | `cron-containment-classify` |
| 6 | `test/server/inngest/function-registry-count.test.ts` | Bump the `route.ts functions array` count | `function-registry-count (a)` |
| 7 | `infra/sentry/cron-monitors.tf` | `sentry_cron_monitor` resource for the slug (declaring it applies it — the full-root apply needs no workflow edit) | `sentry-monitor-iac-parity` + `function-registry-count (c)` |
| 8 | `server/inngest/execution-placement.ts` | `EXECUTION_PLACEMENT` row with the tightest class the function's markers imply (Guard 2 rejects a wrong `portable`) | `execution-placement.test.ts` Guard 1 |

Plus the `cron-tier2-parity` sibling-set sweep (`.github/enforcement-contracts.json`) forces `cron-safe-commit-parity.test.ts` (add to `MIGRATED_PROMPT` for safe-commit crons) and `cron-shared.test.ts` into the same diff whenever `cron-manifest.ts` changes. Validate locally before push: `bunx vitest run test/server/inngest/{function-registry-count,sentry-monitor-iac-parity,cron-containment-classify,cron-safe-commit-parity,cron-shared}.test.ts`.

## Cost Impacts

**None.** Inngest substrate is already in `knowledge-base/operations/expenses.md` (PR-F shipped self-hosted on existing Hetzner node; no new vendor, no billing-tier change). `claude-code` CLI install on Hetzner is free; binary pin is a config change, not a paid resource. Operator `ANTHROPIC_API_KEY` consumption stays in the same operator-Anthropic billing surface — the migration is a substrate swap (GitHub Actions runner → Hetzner node), not a budget increase.

If the Hetzner node ever needs to upsize for concurrency (e.g., multiple cron-* functions running simultaneously), that's an operations-side cost decision NOT bound by this ADR. The Inngest free-tier "5 concurrent steps" cap is irrelevant under self-hosted.

## NFR Impacts

This decision is the **architecture primitive** that enables NFR improvements in subsequent PR-1 acceptance criteria; the ADR itself does not tier-move any NFR at the register level. The downstream effects when the 11 migrations land:

- **Improves NFR-001 (Logging) / NFR-003 (Observability)** for migrated crons: GitHub Actions silent-failure traps (per `2026-05-18-vendor-cron-heartbeat-silent-fail-pattern.md`) are eliminated because Sentry check-in is at end-of-`step.run` (FR4 of PR-1 spec). Status improvement applies per-migrated-workflow, not at the substrate level.
- **Improves NFR-007 (Circuit Breaker / Cost Ceiling)** indirectly: the I3 `AbortSignal` at 55-min provides a deterministic cost ceiling that GitHub Actions' `timeout-minutes` could only approximate.
- **No impact on NFR-026 (Encryption In-Transit)** — `claude-code` invokes the Anthropic API over HTTPS regardless of host; substrate swap doesn't change transport.

NFR register entries are not updated as part of this ADR; PR-1 (and each subsequent migration PR) updates the per-workflow row when the migration lands.

## Principle Alignment

- **AP-008 (Doppler secrets): Aligned** — `ANTHROPIC_API_KEY` already in Doppler `prd` (PR-F runtime). The Hetzner worker reads from Doppler, not from a `.env` file. Cron-* functions inherit the operator key from the parent Node process env.
- **AP-001 (Terraform-only provisioning): Aligned** — `claude-code` binary pin lives in `apps/web-platform/infra/server.tf` (cloud-init or systemd unit), not a manual operator step.
- **`hr-dev-prd-distinct-supabase-projects`: Aligned** — `cron_run_ledger` ledger writes hit dev/prd-distinct Supabase projects per the parent project posture.
- **`hr-autonomous-loop-skill-api-budget-disclosure`: NO-OP at write time** — the rule targets founder-BYOK consumption unattended. These `cron-*` functions consume the OPERATOR key only (invariant I2). Guard clause: if any future cron-* function transitions to per-founder execution, this ADR MUST be superseded and the budget-disclosure rule re-evaluated before that transition merges.

## Diagram

```mermaid
C4Component
title Inngest cron function — claude-code spawn boundary (component view)

Container_Boundary(node, "Hetzner Node — long-lived Node process") {
  Component(inngest_worker, "Inngest worker", "@inngest v3", "Receives cron schedule, dispatches to function handler")
  Component(cron_fn, "cron-daily-triage.ts", "TypeScript", "Inngest function handler")
  Component(step_jitter, "step.run('jitter-guard')", "Inngest step", "Reads cron_run_ledger; early-returns if <80% interval elapsed")
  Component(step_eval, "step.run('claude-eval')", "Inngest step", "Spawns claude-code via child_process.spawn; captures stdout deterministically")
  Component(step_heartbeat, "step.run('sentry-heartbeat')", "Inngest step", "End-of-job POST to Sentry Crons monitor")
  Component(spawn, "claude-code CLI", "Pinned via cloud-init", "Executes agent prompt with operator ANTHROPIC_API_KEY")
}

ContainerDb(ledger, "cron_run_ledger", "Postgres / Supabase", "function_name, last_run_at, run_count")
System_Ext(anthropic, "Anthropic API", "Operator ANTHROPIC_API_KEY")
System_Ext(github, "GitHub API", "Label-mutator / issue-creator side effects")
System_Ext(sentry, "Sentry Crons", "Heartbeat check-in")

Rel(inngest_worker, cron_fn, "fires on schedule", "cron")
Rel(cron_fn, step_jitter, "step 1")
Rel(step_jitter, ledger, "read + UPSERT", "SQL")
Rel(cron_fn, step_eval, "step 2 (if not jitter-guarded)")
Rel(step_eval, spawn, "child_process.spawn", "stdio + 60-min AbortSignal")
Rel(spawn, anthropic, "tool-use loop", "HTTPS")
Rel(spawn, github, "label / comment writes", "HTTPS")
Rel(cron_fn, step_heartbeat, "step 3 (always)")
Rel(step_heartbeat, sentry, "POST status=ok|error", "HTTPS")
```

## Amendment — 2026-09-23 (#8611, ADR-243): one step, one request, is not one child

I1 and I5 assume the child lives inside **one** `step.run` request and that memoization is what stops a
re-spawn. That held only for steps shorter than the transport. The self-hosted server calls steps at the
Cloudflare-proxied serve URL, whose ~100 s origin timeout 524'd every long claude-eval step; the retry
re-invoked the step **before** anything was memoized, so a second child spawned beside the first (51%
of 30-day cron spend). Memoization protects a finished step, never a running one.

Now: every Claude spawn goes through `spawnClaudeEval`, which is single-flight per
`(cronName, runId)` — a re-invocation joins the live child, or within 15 minutes gets its settled
result — and each spawn carries a per-run `--max-budget-usd` and a 2/hour function throttle. Step
responses stream (`serve({ streaming: "force" })`) so the proxy no longer times out. See ADR-243.

## Amendment — 2026-09-28 (#7230): execution placement

The anti-circularity corollary named the wrong mechanism for why execution sits on web-1, and it
gave a hand count of claude-code spawners that no test kept true. Both are corrected in place. The
dedicated host's `--sdk-url` (`http://10.0.1.10:3000/api/inngest`) is only the registration poll
(#8611). Steps go to the serve URL the app registers, `serveHost` = `https://app.soleur.ai` in
`app/api/inngest/route.ts`, and `cloudflare_record.app` resolves that name to web-1 only. The hand
count is replaced by a per-function manifest.

### Decision

Keep execution on the one step-executing host, web-1. Record each function's host needs now, so a
later split is a data change instead of an audit.

| Option | Ruling | Why |
|---|---|---|
| **(c) keep execution on the one step-executing host (web-1)** | **Adopt now** | Existing mechanisms already deliver most of (a)'s benefits. Anti-circularity is served by the GHA-native schedule and the ADR-248 clock on both web hosts. Restart coupling is absorbed by Inngest retries plus the ADR-078 drain lease. A web-1 outage is a product outage that Better Stack already pages. It also needs no production write. |
| **Placement-aware execution at the ADR-143 Phase-3 flip** | **Designated target (#9137)** | `portable` functions run on any web host, `host-affine` functions stick to one host, and `volume-bound` functions stay on the sole-copy LUKS volume holder. Losing web-1 then no longer drops portable work, and the singleton control plane is untouched. |
| **(a) second SDK worker on the Inngest host** | **Fallback only (#9137)**, for a verifier that must survive the loss of *every* web host | It would put a Node worker and prd secrets on the deliberately minimal singleton control-plane host, turning ADR-100 SEC-H3's *indirect* exposure into direct secret read. It adds a second deploy target and version-skew surface, and a new app id means new function ids, with a double-fire-or-gap migration. |
| **(b) separate cron deployable** | **Reject** | It duplicates the build, deploy and version-drift pipelines for small functions. The importability boundary it offers is delivered inside one deployable by the client-free leaf pattern (`cron-manifest.ts`) plus the portable-boundary guard. |

**Constraint on the target.** A serve URL belongs to an app id, and it is last-writer-wins per app
id (ADR-100 Phase-0 spike finding 1). One app id therefore has one serve URL, and a single-app-id deployment
cannot send `host-affine` or `volume-bound` steps to a different host than `portable` ones.
Placement-aware execution needs one of two things: **per-class app ids**, which means new function
ids and the same migration cost charged against (a); or **an ingress layer that routes a step
request by its function id**, for example host affinity on `/api/inngest` keyed by the `fnId`
query parameter. Both costs sit in #9137 and neither is paid here.

**Re-open triggers** (also on #9137): (1) the ADR-143 Phase-3 flip is scheduled; (2) a new
host-state verifier appears that neither the GHA-native schedule nor the ADR-248 clock can serve;
(3) a measured incident in which losing web-1 dropped `portable` work with user impact.

### The placement rule

Every function served by `app/api/inngest/route.ts` has exactly one class in
`apps/web-platform/server/inngest/execution-placement.ts` (`EXECUTION_PLACEMENT`, keyed by the
Inngest function id; type `ExecutionPlacement`). An `onFailure` handler, which the SDK registers
as a separate `<id>-failure` function, inherits its parent's class and has no row of its own.

| Class | Meaning | Future host constraint |
|---|---|---|
| `portable` | No host-local dependency. It still needs prd secrets: host-free, not secret-free. | Any host holding the secrets. |
| `host-affine` | Needs exactly one host with the app image: a Claude spawn through `spawnClaudeEval` (its single-flight guard is process-local, ADR-243 §2), an ephemeral clone on `CRON_WORKSPACE_ROOT`, the ADR-078 deploy lease, or any child process. | Exactly one app host, sticky per run: every step and retry of a run must reach the same process, including within ADR-243's `SETTLED_TTL_MS` settled-result window. That host's `CRON_WORKSPACE_ROOT` must be the host-mounted `/mnt/data/workspaces`, so the deploy lease stays visible to `ci-deploy.sh`. |
| `volume-bound` | Touches user workspaces: reads `WORKSPACES_ROOT` or reaches `server/workspace.ts` / `server/workspace-resolver.ts`. | Only the host holding the ADR-119 sole-copy LUKS volume, `hcloud_volume.workspaces_luks` (web-1 today). Not merely a host with a `/mnt/data`: `hcloud_volume.workspaces` exists on every web host. |

- Ephemeral cron clones are `host-affine`, not `volume-bound`. They sit on `/mnt/data` for disk
  capacity, not for data.
- **`cron-workspace-gc` co-location constraint.** `cron-workspace-gc` is `volume-bound`, because it
  sweeps `/workspaces` directly. It is also the garbage collector for every `host-affine` clone
  root. Three single-host classes cannot say "the GC runs wherever `host-affine` producers run", so
  that is stated here: moving `host-affine` producers to a host without a GC there leaks clones
  until the volume fills (the 2026-06-02 ENOSPC freeze) and hides the deploy lease from
  `ci-deploy.sh`. A per-host GC is the likely shape (#9137).

### Enforcement

The rule is enforced by `apps/web-platform/test/server/inngest/execution-placement.test.ts`; read
the guards there rather than a copy here. That suite enforces only the `portable` boundary.
Over-pinning is safe and is not guarded, and the `host-affine`/`volume-bound` split is declared and
reviewed until a placement-aware registry consumes it (#9137).

The Guard 2 allowlist of shared exports a `portable` function may import is seeded from what the
code imports today, and adding to it is an architecture change, not a test fix.

Single-host execution itself is enforced in two halves. The serve URL half is Guard 4 of that suite
plus guard (g) of `test/server/inngest/function-registry-count.test.ts`. The DNS half is
`apps/web-platform/infra/lb-weight-gate.test.sh` Condition C, which holds `cloudflare_record.app`
to web-1. Condition C runs only on changes under `apps/web-platform/infra/**`, which is the only
place `cloudflare_record.app` can change.

**Known gaps** the guards cannot detect:

- process-local module state, for example a `globalThis` single-flight map;
- HTTP calls to a private IP or loopback address;
- a forbidden workflow named by template-literal assembly, such as `` `workspaces-luks-${x}.yml` ``;
- a dispatch by numeric workflow id, where no filename appears at all.

### The corollary, re-derived for today's topology

Restated: **a verifier whose own run is the only signal of total loss of its subject must not be
executed by that subject.** A GHA `schedule:` is best-effort, not reliable: #8495 measured one run
per 2–7 h for a `*/15` schedule. Where it is the only trigger, its dropped runs are a known gap.

| Verifier | Subject | Trigger | Survives total loss of its subject? |
|---|---|---|---|
| `workspaces-luks-verify` | web-1's `/mnt/data` on the LUKS mapper | GHA `schedule:` only | Yes, but only as often as GitHub starts the run (best-effort per #8495). Moving it onto the ADR-248 clock is evaluated in #9138. |
| `scheduled-inngest-health` | The Inngest scheduler and its web unit | ADR-248 clock on both web hosts, `schedule:` as fallback | Yes, while at least two web hosts are deployed (ADR-248 reversal trigger 3). |
| `scheduled-zot-restart-loop` | The zot registry host | ADR-248 clock on both web hosts, `schedule:` as fallback | Yes, while at least two web hosts are deployed (ADR-248 reversal trigger 3). |
| `scheduled-prod-version-drift` | The deployed web-platform image | GHA `schedule:` only | Yes, but only as often as GitHub starts the run (best-effort per #8495). |

**Sanctioned Inngest-scheduled watchers.** `cron-inngest-config-drift` (dispatches
`inngest-config-drift.yml`) and `cron-inngest-cron-watchdog` watch Inngest from inside Inngest.
That is legitimate, because their run is not the only signal of the substrate's total loss:
`scheduled-inngest-health` covers that from outside it. They watch partial failures (config drift,
de-planned crons) that leave the substrate able to run them.
