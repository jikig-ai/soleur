# Learning: the green sandbox probes and the empty log query were each measuring something else

## Problem

Diagnosing #10032 (agent sandbox shim H6) produced four readings that looked like "prod is fine / fix is simple" and were not.

1. `sdk_noproc rc=0` looked like proof that a procfs-free argv works on the real host. It passes because the probe argv carries `--bind / /`, which brings in the host `/proc`: the very exposure the mask exists to remove.
2. `SANDBOX_PROBE_OK ... rc=0` (the simple probe) is green in the same deploys as `SANDBOX_CANARY_FAIL` (the faithful canary on the SDK's real argv). A green probe says nothing about the SDK argv.
3. The CPO assessed that "a failed canary leaves production on the last good image". One Better Stack query refuted it: `SANDBOX_CANARY_FAIL ... (report-only canary, never gated)`. Production runs the failing image.
4. A Better Stack grep for the symptom (`Can't mount proc`, `sandbox required but unavailable`) returned rows, but only webhook events whose payload echoed the text of the issue filed about the symptom. A self-filed issue pollutes its own telemetry query.

## Solution

- Name the population a probe's pass is about before citing it: ask what the argv mounts, not what its exit code says.
- Read a gate's blocking posture from its own emitted marker (`never gated`, `NON-BLOCKING dark-launch`) before reasoning about what a failure does to the deploy.
- When a leader claims a deploy-path behavior, run the one query that would falsify it (see the brainstorm skill's leader infra-claim cross-check).
- Filter telemetry hits by host or source (`host_name`) so that issue-text echoes from webhook ingestion cannot read as production evidence, and say so when the clean result is "no production-container rows", not "no rows".

## Key Insight

A pass is a claim about the thing it ran. When two probes disagree, the lighter one is not corroboration; and a query's silence only counts after it excludes the issue's own echo.

## Tags
category: workflow-patterns
module: agent-sandbox, canary, brainstorm
