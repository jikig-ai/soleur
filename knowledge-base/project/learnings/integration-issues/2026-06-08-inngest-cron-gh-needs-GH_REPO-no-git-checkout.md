# Learning: a no-clone Inngest cron that runs `gh` must set `GH_REPO` (the /app container has no `.git`)

## Problem

`cron-follow-through-monitor` (Inngest, `0 9 * * 1-5`) posted a Sentry **error
check-in every weekday run** for ~2 weeks (since 2026-05-27). The symptom monitor
(`WEB-PLATFORM-2C` "Cron failure: scheduled-follow-through") gave no cause; the
root-cause event (`WEB-PLATFORM-W`, surfaced via `reportSilentFallback`) did:

```
Command failed: gh issue list --label follow-through --state open --json number,title,body --limit 100
failed to run git: fatal: not a git repository (or any of the parent directories): .git
```

`gh` was authenticated (the cron mints a GitHub App installation token into
`GH_TOKEN`) but could not resolve the *target repo*. `gh`'s repo precedence is
`--repo` flag > `GH_REPO` env > git-remote of CWD. The cron runs `gh` from the
prod Next.js container CWD `/app`, which is **not a git checkout** — and unlike
the audit/bug-fixer crons it never clones a repo (it only touches issues). With
no `--repo`, no `GH_REPO`, and no `.git`, `gh` fell through to git-remote
detection and failed.

Regressed when the cron migrated from a checked-out GitHub Actions workflow to
the Inngest `/app` container (TR9 PR-2). The workflow ran *inside* a repo
checkout where `gh` derived the repo from the git remote; the Inngest function
does not.

## Solution

Add `GH_REPO: \`${REPO_OWNER}/${REPO_NAME}\`` (→ `jikig-ai/soleur`, both already
exported from `_cron-shared`) to the cron's `buildSpawnEnv` allowlist. `gh`
honors `GH_REPO` as the default repo, so **one env field fixes every `gh`
invocation at once** — the Node-process `execFileSync` prefetch AND every
`gh issue view/edit/comment/close` the spawned claude agent runs (the agent's
gh subprocesses inherit the spawn env). No clone needed; the monitor only reads
and edits issues, never repo files.

Import `REPO_OWNER`/`REPO_NAME` from the **relative** `./_cron-shared` (the
substrate-import guard `test/server/cron-substrate-imports.test.ts:11` requires
the relative form and forbids local re-declaration). Keep the Layer-2 allowlist
comment in sync (it enumerates which vars reach the subprocess).

Precedent the fix mirrors: `scripts/sweep-followthroughs.test.sh:99` already
documents `GH_REPO` as load-bearing for the GitHub Actions sweeper's own `gh`
calls — same root cause, same fix, different runner.

## Key Insight

**The clone-vs-no-clone distinction decides whether an Inngest cron needs
`GH_REPO`.** The audit/content crons run the agent with `cwd: spawnCwd` where
`setupEphemeralWorkspace` cloned the repo (so `gh` resolves via the git remote);
the *monitor*-class crons (follow-through, daily-triage) skip the clone because
they only touch issues — so for them `GH_REPO` is the only repo-resolution path.
When migrating any `gh`-running automation from a checked-out CI runner to a
no-checkout container, set `GH_REPO` (or `--repo`) — authentication (`GH_TOKEN`)
is necessary but **not sufficient**; `gh` still needs to know *which* repo.

The defect was heartbeat-invisible because `postSentryHeartbeat({ ok: result.ok })`
keys on the eval's exit code, and the error went out via a *separate*
`reportSilentFallback` event — so diagnosing it meant pulling the
`reportSilentFallback` issue's latest event (not the cron-monitor check-in) to
read the child-process stderr. Diagnostic path: Sentry monitor red → find the
sibling `reportSilentFallback` error issue → read `entries[].exception.value`
for the wrapped child stderr.

## Session Errors

1. **Redundant tsc-completion Monitor timed out.** I armed a `Monitor` to watch
   for tsc completion while the same `tsc --noEmit` was already running inside a
   `run_in_background` Bash task that reports `tsc EXIT=$?` on completion.
   **Recovery:** the background task fired its own completion notification with
   `tsc EXIT=0`; the monitor timeout was harmless. **Prevention:** when a
   long command is already inside a `run_in_background` Bash task that prints its
   own exit marker, do NOT also arm a Monitor for the same condition — the task
   notification IS the signal (per the Monitor tool's own guidance: use Bash
   `run_in_background` for a single completion notification, Monitor only for
   per-occurrence streams).

## Tags
category: integration-issues
module: apps/web-platform/server/inngest/functions

## Related
- [[2026-06-02-inngest-dispatches-gha-for-credential-heavy-crons]] — the substrate-import gotcha (relative `./_cron-shared` only) and the GHA-vs-Inngest dispatch tradeoff for these same crons.
- PR #4733 — established follow-through-monitor + daily-triage as a sibling pair fixed together for the prior `gh auth login` (GH_TOKEN) class; this PR is the direct `GH_REPO` follow-up.
- #5010 (this fix). Sentry: WEB-PLATFORM-W (root cause) / WEB-PLATFORM-2C (symptom monitor).
