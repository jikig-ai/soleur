# Learning: a new Inngest cron must update FIVE parallel registries in lockstep

## Problem

Adding `cron-kb-template-health.ts` (a new hourly Inngest cron) tripped three
registry-integrity invariants in `function-registry-count.test.ts` on the first
test run. A new server-side cron is not "done" when the handler compiles — it is
done when every parallel registry that tracks crons agrees.

## Solution

When adding a new Inngest cron function, update ALL of these in the SAME PR
(the `function-registry-count.test.ts` guards are the forcing function — they
fail until each is consistent):

1. **`apps/web-platform/app/api/inngest/route.ts`** — import the function +
   add it to the served-functions array.
2. **`apps/web-platform/server/inngest/cron-manifest.ts`** — add the slug to
   `EXPECTED_CRON_FUNCTIONS` (this also auto-extends the manual-trigger
   allowlist; no separate edit needed).
3. **`apps/web-platform/test/server/inngest/function-registry-count.test.ts`**
   — bump the expected route count by 1.
4. **`apps/web-platform/infra/sentry/cron-monitors.tf`** — add a
   `sentry_cron_monitor` resource whose **name slugifies to exactly the
   handler's `SENTRY_MONITOR_SLUG` constant** (a mismatch silently never
   creates the monitor → the dead-probe alarm never fires).
5. **`.github/workflows/apply-sentry-infra.yml`** — add the matching
   `-target=sentry_cron_monitor.<name>` line so the monitor is applied on
   merge.

The slug must be byte-identical across handler `SENTRY_MONITOR_SLUG` → `.tf`
`name` → `.tf` resource address → workflow `-target` suffix. The count test's
own guards machine-enforce the slug↔tf↔workflow lockstep.

## Key Insight

The repo has 39+ Inngest crons vs 4 legacy GitHub-Actions scheduled workflows
(`git ls-files | grep -c "server/inngest/functions/cron-"`). **When an issue
prescribes a literal mechanism (`.github/workflows/*.yml` cron) but the codebase
has an overwhelming established pattern + a direct structural sibling
(`cron-github-app-drift-guard.ts`), follow the established architecture (ADR-030),
not the issue's literal mechanism** — the issue is authoritative for intent
(detect kb-template drift proactively), never for the substrate. Reusing the
Inngest path also reuses `createProbeOctokit()` (installation-token auth, no PAT),
`assertNoLeak`, the Sentry mirror, and the inngest-heartbeat substrate — a
GH-Actions cron would re-implement JWT minting in inline shell (a known
silent-failure-trap class).

## A sixth lockstep dimension: containment class (#5072)

Beyond the five registries above, a new cron must ALSO land in exactly one
**containment class**, enforced by `cron-containment-classify.test.ts` (same
directory, same source-scan idiom). The three classes are observable from
source: **substrate-contained** (the cron *calls* `spawnClaudeEval()` — must be
in `CRON_BASH_ALLOWLISTS` XOR `TIER2_DEFERRED_CRONS`), **direct-spawn** (a real
`spawn(` not via the wrapper — must be enumerated in the test's
`KNOWN_DIRECT_SPAWN_CRONS` grandfather set, or moved to an ephemeral GHA runner
per #5073), and **pure-TS** (no spawn — must carry no containment entry).
Detection is by **call site**, not import: `cron-daily-triage` imports substrate
*helpers* (`resolveClaudeBin`, `KILL_ESCALATION_MS`) yet spawns claude on its own
path, so it is direct-spawn, not substrate-contained — an import-based regex
mis-classifies it. The gate fails closed on any new uncontained spawn surface and
emits the class + the literal map line to add.

## Session Errors

- **Planning subagent could not spawn nested Task subagents** (plan/review
  fan-out agents unavailable to an agent that is itself a subagent). Recovery:
  the subagent compensated by doing the research/premise-validation/precedent-diff
  inline. Prevention: this is a harness constraint (nested-agent Task restriction),
  not a fix-in-repo item — expect plan/deepen fan-out to degrade to inline
  research when planning runs inside a one-shot subagent; the plan quality was
  unaffected (the decisive precedent-diff finding was reached inline).

## Tags
category: integration-issues
module: apps/web-platform/server/inngest
