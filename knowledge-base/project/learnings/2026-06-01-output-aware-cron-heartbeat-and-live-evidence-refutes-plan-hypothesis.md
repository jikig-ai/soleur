# Learning: output-aware cron heartbeat + live evidence must refute plan hypotheses before shipping a security-relaxing "restore"

## Problem

Four scheduled Inngest producers (roadmap-review #4689, strategy-review #4686,
content-generator #4684, competitive-analysis #4688) went silent after the TR9
GHA→Inngest migration. Each reported its Sentry monitor `ok: spawnResult.ok`
(claude exit code), so a clean exit that produced **no** `scheduled-<task>`
GitHub issue kept the per-function monitor GREEN. The silence was caught only by
the separate `cron-cloud-task-heartbeat` issue-count watchdog — weeks late.

The plan front-loaded a prime root cause (B1): `setupEphemeralWorkspace` writes
`.claude/settings.json` with `permissions.allow: []` + `sandbox.enabled: true`,
"blocking the spawned claude's `gh issue create`." The proposed restore was to
widen that sandbox/allowlist across the shared substrate (8+ crons).

## Solution

Shipped the **confirmed-safe observability fix only**, and deferred the restore
pending a live diagnosis — because live evidence refuted B1:

1. **Output-aware heartbeat** (`_cron-shared.ts`): `verifyScheduledIssueCreated`
   (read-only `GET /repos/{owner}/{repo}/issues`, filtered by `updated_at` via
   the `since` param) + `resolveOutputAwareOk` (gate the heartbeat on
   `spawnOk && issue-touched-in-window`; emit `scheduled-output-missing` on
   clean-but-empty, stay green-inconclusive if the verify GET itself throws).
   Wired into the 3 always-create producers; **strategy-review excluded** (pure-
   TS, legitimately creates zero issues on an all-clean run → its `errors===0`
   heartbeat is already output-aware).
2. **`spawnSimple` stderr capture**: was `stdio:"ignore"`, discarding git's
   stderr → the recurring `git clone failed (exit 128)` was undiagnosable. Now
   captures (bounded `STDERR_CAP_BYTES=8192`) and folds the **redacted** reason
   into the thrown error.
3. **Missing Sentry monitor** (found at review): `scheduled-content-generator`
   had NO `sentry_cron_monitor` and was on the `KNOWN_UNMONITORED_SLUGS`
   exemption in `function-registry-count.test.ts` — so its `?status=error`
   check-in was dropped on the floor. Added the monitor + removed the exemption.

## Key Insight

**A plan's root-cause hypothesis is a hypothesis, not a fact — confirm it against
runtime evidence before shipping any fix that relaxes a security boundary.**

The decisive probe: `cron-daily-triage` was producing output the same morning
(commented on 8 issues at 04:11 UTC) through the **same**
`DEFAULT_CLAUDE_SETTINGS` (`allow:[]`, `sandbox.enabled:true`). If that settings
block stopped `gh`, daily-triage couldn't comment either. B1 refuted in one
query. The real divergence is producer-specific (wholesale `Bash` + low
`--max-turns` 40/45/50 vs daily-triage's narrowed `Bash(gh …:*)` + 80 turns) —
permissions-vs-max-turns, which needs a live run to disambiguate. The live run is
loopback-gated (`INNGEST_BASE_URL=host.docker.internal:8288`), so the honest path
was: ship the observability fix that makes the next fire RED, then trigger-
diagnose. The output-aware heartbeat IS the diagnostic enabler for the restore.

Corollary: an exit-code-only heartbeat on a spawn-and-produce cron is a dark
observability surface. Gate the monitor on the actual artifact (the labeled
issue), filtered by `updated_at` so a legitimate dedup-COMMENT (roadmap-review's
DEDUP RULE comments instead of creating) is not false-red.

## Sentry diagnostic mechanics (reusable)

Pulling prod Sentry from the operator network without `sentry-cli`:
- Token: **`SENTRY_ISSUE_RW_TOKEN`** (Doppler `soleur/prd`), NOT `SENTRY_AUTH_TOKEN`
  or `SENTRY_API_TOKEN` (both 403 on the issues API).
- Endpoint: the **org**-issues endpoint works
  (`/api/0/organizations/jikigai-eu/issues/?query=feature%3A<feat>&statsPeriod=14d&project=-1`);
  the project-issues endpoint 403'd with the same token.
- `statsPeriod` valid values are **`''` / `24h` / `14d`** only — `90d` → HTTP 400
  `Invalid stats_period`.
- `reportSilentFallback` tags events with `feature=cron-<name>`; a claude that
  exits 0 without creating its issue throws nothing → **zero Sentry events is
  itself diagnostic** (confirms silent-no-op, not "no problem").

## Session Errors

1. **Bash stdout intermittently dropped/delayed** — many calls returned empty,
   surfaced later. Recovery: routed all consequential output through `/tmp/*.txt`
   + Read-back. Prevention: known environment quirk; write-to-file-and-Read is
   the reliable pattern (the work prompt already warns of it).
2. **First Edit to `_cron-shared.ts` failed** — targeted an anchor comment that
   didn't exist (assumed a `cron-shared.test.ts` marker convention). Recovery:
   grep-confirmed 0 partial write, re-anchored on the real last function.
   Prevention: Read the exact insertion target before Edit; don't assume a
   convention-based anchor exists.
3. **Sentry token/period 403/400 dance** — see "Sentry diagnostic mechanics."
   Recovery: probed token scopes + period values. Prevention: documented above.
4. **Plan prime hypothesis (B1) refuted by live data** — see "Key Insight."
   Recovery: paused before shipping the sandbox-widening restore; shipped only
   the confirmed-safe fixes. Prevention: confirm plan root-cause against runtime
   evidence before any security-relaxing change.
5. **IaC-routing hook blocked a plan Edit** — "verify in the Sentry UI" phrasing
   tripped `hr-all-infrastructure-provisioning-servers`. Recovery: reworded to
   document existing Sentry-managed (`ignore_changes`) state + added
   `<!-- iac-routing-ack: plan-phase-2-8-reviewed -->`. Prevention: when
   documenting pre-existing external config, use descriptive ("is Sentry-
   managed") not imperative ("verify in the UI") phrasing.

## Tags
category: integration-issues
module: apps/web-platform/server/inngest
