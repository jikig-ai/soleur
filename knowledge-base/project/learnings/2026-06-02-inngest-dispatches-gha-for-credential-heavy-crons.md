# Learning: Inngest-dispatches-GHA is the right shape for credential-heavy infra crons (and two test gotchas when adding a new cron)

## Problem

`scheduled-terraform-drift` was the last cron on a GitHub Actions `schedule:` trigger. GHA scheduled-dispatch jitter (observed up to 339 min late) had forced its Sentry monitor margin to 480 min just to suppress false "missed check-in" alarms (PR #4772). The goal: make Inngest the single scheduling substrate so the margin can tighten back to ~60 min — WITHOUT moving terraform execution (which needs the terraform binary + R2/AWS/Doppler `prd_terraform` cloud-admin credentials) onto the long-lived app server.

## Solution — the dispatch-hybrid

A new dispatch-only Inngest cron (`apps/web-platform/server/inngest/functions/cron-terraform-drift.ts`) fires on `{ cron: "0 6,18 * * *" }`, mints a short-lived GitHub App installation token (`mintInstallationToken`), and triggers the EXISTING GHA workflow via Octokit `POST /repos/{owner}/{repo}/actions/workflows/{workflow_id}/dispatches` (workflow_id = the workflow **filename** string, ref="main"). The GHA `schedule:` trigger is removed; `workflow_dispatch:` is kept. **terraform still runs in the ephemeral GHA runner** — the Inngest fn ONLY dispatches. The Sentry monitor margin drops 480→60.

## Key Insight

**Inngest-dispatches-GHA (the "Option C" dispatch-hybrid that ADR-033 REJECTED) is the CORRECT shape for a credential-heavy infra cron — the opposite of the agent-loop crons.** ADR-033 rejected dispatch-hybrid for the TR9 *agent-loop* crons because for those the whole point was to move `claude-code` execution off GHA (replay-safety / idempotency / observability). A credential-heavy infra cron is the inverse workload: goal (a) "kill GHA scheduling jitter" applies, but goal (b) "move execution in-process" is actively *harmful* (it would park cloud-admin creds on the app host). So dispatch-hybrid captures the only goal that applies while keeping execution where it safely belongs. Annotate the ADR's Option-C rejection with a scope-note so the next infra-cron author doesn't mis-cite it as a blanket ban.

**Liveness (Design A — no own Sentry monitor):** a dispatch-only cron does NOT need its own `SENTRY_MONITOR_SLUG`. Scheduler liveness is covered by `cron-inngest-cron-watchdog` + the parity-guarded `EXPECTED_CRON_FUNCTIONS` manifest; end-to-end liveness is covered by the downstream GHA monitor (no GHA heartbeat within the margin → red). A dispatcher-owned monitor would be *worse*: it could go green on a 2xx-no-run dispatch while the run silently never executed. The `function-registry-count.test.ts` guards (c)/(d)/(c2) skip slug-less files cleanly.

## Gotchas when adding a new `cron-*.ts` (each cost a red test)

1. **Import `_cron-shared` via the RELATIVE form `from "./_cron-shared"`, not the `@/server/inngest/functions/_cron-shared` alias.** `cron-substrate-imports.test.ts`'s `SHARED_IMPORT_RE = /from\s+["']\.\/_cron-shared["']/` matches only the relative form (every sibling cron uses it). The alias passes tsc + the function's own tests but fails the substrate guard in the full webplat shard.

2. **Registry count is a moving target — re-derive it at write-time.** `function-registry-count.test.ts` guard (a) asserts `routeEntries.length`. A sibling PR adding/removing an Inngest fn shifts the number between plan-write and /work. Re-run `grep -cE '^\s+\w+,$' app/api/inngest/route.ts` against the as-written file; do not trust the plan's literal.

3. **`JSON.stringify(new Error(msg))` is `"{}"` — a "token redacted out of the Error" test that serializes the call is VACUOUS.** `name`/`message`/`stack` are non-enumerable, so the token never appears in the serialized output whether or not redaction fired. Inspect the Error's `.message` directly (`errArg instanceof Error ? errArg.message : String(errArg)`) AND add a positive control asserting the redaction sentinel (`toContain("[REDACTED-INSTALLATION-TOKEN]")`) — proving redaction *actively fired*, not merely that the token is absent (an empty message also satisfies the negative). This applies to ANY test asserting a value was scrubbed from an Error handed to a reporter.

4. **Type vitest mock spies whose `.mock.calls[i]` you destructure.** `vi.fn(async () => ...)` infers an empty arg tuple `[]`, so `const [a, b] = spy.mock.calls[0]` fails tsc TS2493. Give the spy `(...args: unknown[])`.

## Session Errors

1. **`_cron-shared` alias import → substrate guard failure.** Recovery: relative `./_cron-shared`. Prevention: gotcha #1 above (guard-enforced convention).
2. **Vacuous redaction test (JSON.stringify(Error) drops .message).** Caught at multi-agent review (test-design-reviewer rec + my Error-serialization check). Recovery: inspect `.message` + positive control. Prevention: gotcha #3 above.
3. **tsc TS2493 on untyped mock spies.** Recovery: `(...args: unknown[])`. Prevention: gotcha #4 above.
4. **test-all.sh EXIT=1 masked as "exit code 0" by the background-wrapper notification** (91/92 suites). Recovery: grepped the `EXIT=` log marker (written via `echo "EXIT=$?" >> log`). Prevention: known tail-masking class (`2026-05-18-test-all-tail-masking`); always read the explicit `EXIT=` marker, never the wrapper's exit.
5. **signature-verify `importRoute()` timeouts (16s) in the 694-file single-process local shard.** Pass in isolation; CI shards webplat into 2 so won't hit it. Recovery: re-ran the failing files in isolation (CI-equivalent) to classify as resource-contention, not regression. Prevention: the documented doppler-env/contention caveat — re-run a failing webplat file in isolation before treating it as a regression.
6. **(forwarded)** Plan subagent Write blocked by worktree-boundary hook (main-repo path); corrected immediately. No impact.

Related: [[2026-05-19-inngest-substrate-five-bug-cascade]], [[2026-06-02-sentry-cron-margin-must-absorb-gha-dispatch-jitter]] (the predecessor PR #4772 this supersedes), [[2026-05-18-vendor-cron-heartbeat-silent-fail-pattern]].

## Tags
category: integration-issues
module: apps/web-platform/server/inngest
