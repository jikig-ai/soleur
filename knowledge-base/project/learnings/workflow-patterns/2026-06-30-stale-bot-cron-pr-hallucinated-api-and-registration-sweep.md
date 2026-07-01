# Learning: a stale bot-generated cron PR ships against a hallucinated substrate API and skips half its registration locations

## Problem

Reviving an 8-day-old bot-generated PR (#5631, `feat/cron-architecture-diagram-sync`,
authored by `app/soleur-ai`) surfaced three independent failure layers that a
"resolve the conflict and merge" reflex would have missed:

1. **It never compiled.** The codegen emitted seven literal `\!` (backslash-bang)
   sequences — `spawnCwd\!`, `\!spawnResult`, `installationToken\!` — which are
   invalid TypeScript. This was the real root cause of the original
   `web-platform-build` / `test` red, not the merge conflict.

2. **The handler was written against a hallucinated substrate API.** `tsc`
   reported wrong arg counts and wrong property names throughout:
   `deferIfTier2Cron(step, name)` (real API takes one options object),
   `mintInstallationToken({ minLifetimeMs })` (real key is `tokenMinLifetimeMs`,
   and it needs `repositories: [REPO_NAME]`), `spawnClaudeEval({ cwd })` (real key
   is `spawnCwd`, plus a required `buildSpawnEnv`), `resolveOutputAwareOk({
   spawnResult })` (real shape is `{ spawnOk, stderrTail, exitCode, stdoutTail }`).
   The fix was to rewrite the handler to mirror a known-good twin
   (`cron-seo-aeo-audit.ts`), not to patch errors one-by-one.

3. **The PR claimed "all four required locations" but ~8 are gated.** The body
   cited "handler, manifest, metadata, serve route per ADR-033." The mechanical
   CI gates require five MORE that the bot skipped:
   - `_cron-claude-eval-substrate.ts` `CRON_BASH_ALLOWLISTS` entry
     (`cron-containment-classify` gate — a substrate-contained cron MUST appear
     in exactly one of `CRON_BASH_ALLOWLISTS` or `TIER2_DEFERRED_CRONS`).
   - `test/server/inngest/function-registry-count.test.ts` route-count bump.
   - `infra/sentry/cron-monitors.tf` `sentry_cron_monitor` resource +
     `.github/workflows/apply-sentry-infra.yml` `-target=` line
     (`sentry-monitor-iac-parity` + `function-registry-count (c)/(f)`).
   - `cron-safe-commit-parity.test.ts` `MIGRATED_PROMPT` list + a
     `cron-shared.test.ts` acknowledgment (the `cron-tier2-parity` **sibling-set
     sweep** forces both test files into the diff whenever `cron-manifest.ts`
     changes — but the prompt-anchor invariant additionally requires the cron's
     prompt to carry `PERSISTENCE: Do NOT run git add`, which the bot omitted).

The reason all of this sat green-then-red: the PR was 8 days stale. Its last CI
run predated some of these gates and ran against an old `main`. Only
`gh pr update-branch` → **fresh** CI on current `main` exposed every layer at
once. The mechanical gates work; they simply had never run on a current base.

## Solution

When fixing a stale or bot-generated cron PR, do all three, in order:

1. **Rebase first, then read CI.** `update-branch` and let fresh CI enumerate
   the failures against current `main`. Never trust an old green.
2. **Verify substrate-API correctness against a known-good twin**, not against
   the PR's own prose. `tsc --noEmit` is the fast oracle; pick the structurally
   closest live cron (claude-eval + `safeCommitAndPr` ⇒ `cron-seo-aeo-audit.ts`)
   and align signature-for-signature.
3. **Run the full registration sweep**, not the PR's claimed subset. The
   authoritative list now lives in ADR-033 §"Registration checklist". Validate
   locally with the three drift guards before push:
   `bunx vitest run test/server/inngest/{function-registry-count,sentry-monitor-iac-parity,cron-containment-classify,cron-safe-commit-parity,cron-shared}.test.ts`.

## Compounding fix

Added a consolidated **Registration checklist** to ADR-033 so the "four
locations" undercount cannot recur — a future cron PR (bot or human) has one
authoritative enumeration of every gated location. The per-location CI gates
already exist; the gap was a single source of truth listing them.

## Related

- ADR-033 (inngest-cron) §"Registration checklist" — the canonical location list.
- `.github/enforcement-contracts.json` `cron-tier2-parity` — the sibling-set sweep.
- `2026-06-30-update-branch-drifts-lockfiles-and-npm11-pin.md` — the other stale-PR-drain hazard from the same session.
