---
lane: cross-domain
brand_survival_threshold: single-user incident
parent_epic: "#3244"
parent_pr_merged: "#3985 (PR-1, scheduled-daily-triage)"
umbrella_issue: "#3948"
status: brainstorm-complete
created: 2026-05-19
type: carry-forward
---

# feat: TR9 PR-2 — `scheduled-follow-through` → Inngest cron

## Problem Statement

`scheduled-follow-through.yml` is the second of 10 group-(c) agent-loop crons enumerated by umbrella issue #3948. PR-1 (#3985, MERGED 2026-05-18) shipped the full TR9 substrate stack (ADR-033, `cron_run_ledger`, Sentry heartbeat, `actor: "platform"` invariant, no-byok-lease sentinel test, delete-GHA-YAML-same-commit) on `scheduled-daily-triage`. PR-2 reuses that substrate 1:1 to migrate `scheduled-follow-through`, retiring the GHA cron in the same commit.

`scheduled-follow-through.yml` runs `0 9 * * 1-5` (weekdays 09:00 UTC). It uses `anthropics/claude-code-action@v1.0.101` to: (a) list open issues labeled `follow-through`, (b) parse a YAML predicate block from each issue body (`manual`, `http-200`, `dns-txt`, `dns-a`), (c) run the predicate (curl, dig), (d) auto-close on PASS / add `needs-attention` + @-mention on SLA-exceeded / auto-close after 30-business-day max. The migration must preserve all four predicate behaviors and the comment-on-state-transition-only contract.

## Goals

- **G1.** Replace `.github/workflows/scheduled-follow-through.yml` with `apps/web-platform/server/inngest/functions/cron-follow-through-monitor.ts`, deleted-and-added in the same commit (I-13 hygiene from PR-1).
- **G2.** Reuse PR-1's ADR-033 substrate invariants I1–I6 verbatim. No new substrate primitives.
- **G3.** Preserve current behavior 1:1: weekday-09:00 schedule, 4 predicate types, business-day SLA math, 30-business-day max polling, auto-close + @-mention semantics, idempotent state-transition-only commenting.
- **G4.** Extend `cron-no-byok-lease-sweep.test.ts` and `byok-audit-writer-sweep.test.ts` to include the new file in the cron-* import-sentinel allowlist.
- **G5.** Reclassify `scheduled-followthrough-sweeper.yml` as group (a)/(b) infra-cron at PR-2 merge — update umbrella #3948 body to drop it from the migration checkbox list.

## Non-Goals

- **NG1.** No fresh CPO/CLO/CTO triad spawn. Carry-forward from PR-1 sign-off per Phase 0.5 step 4 (`in-flight feature refresh`).
- **NG2.** No new substrate primitives. ADR-033 is `accepted` and applies 1:1; any divergence escalates to triad re-spawn per the brainstorm's re-evaluation criteria.
- **NG3.** No port of the LLM logic to deterministic TypeScript. The LLM is the load-bearing decision layer (which predicate, which SLA bracket, which action) and porting it to TS would re-implement the entire prompt as code — strictly out of scope for a substrate migration.
- **NG4.** No change to the existing GHA preflight (`./.github/actions/anthropic-preflight`) for OTHER workflows. PR-2 only retires the preflight call for `scheduled-follow-through` (Doppler ANTHROPIC_API_KEY at spawn replaces it for THIS function); other GHA workflows that still use claude-code-action keep their preflight until they migrate.
- **NG5.** No migration of the other 9 group-(c) children. Each ships per-issue per K8.

## Functional Requirements

### FR1: Cron schedule preserved

Inngest function MUST fire on `cron: "0 9 * * 1-5"` (weekdays 09:00 UTC). Verify Inngest cron parser accepts the DOW range syntax at plan time. Manual-trigger event MUST also be registered: `{event: "cron/follow-through-monitor.manual-trigger"}` (per Spec-flow AC37 carry-forward from PR-1).

### FR2: Predicate execution preserved (4 types)

Agent prompt MUST preserve the 4 predicate types from the GHA prompt verbatim:
- `manual` — no automated check, SLA tracking only.
- `http-200` — `curl -s -o /dev/null -w "%{http_code}" "<url>"`, pass if "200", HTTPS-only, MUST refuse `localhost`, `127.0.0.0/8`, `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `169.254.0.0/16`.
- `dns-txt` — `dig +short TXT "<domain>"`, pass if contains `expected`.
- `dns-a` — `dig +short A "<domain>"`, pass if contains `expected` IP.

The HTTPS-and-non-RFC1918 guard is the load-bearing SSRF prevention. If the operator widens `--allowedTools` to include `curl`, this prompt-level guard MUST be preserved verbatim.

### FR3: State-transition-only commenting

Agent MUST NOT comment on issues that have not changed state. The 4 commentable transitions are:
1. PREDICATE PASSES — close + "Verified: …. Auto-closing."
2. SLA EXCEEDED FIRST TIME — add `needs-attention` label + @-mention author.
3. MAX POLLING EXCEEDED (30 business days) — add `needs-attention` + close + "Maximum polling period reached…".
4. WITHIN SLA, NO STATE CHANGE — do NOTHING. No comment.

### FR4: Idempotency guards (three guards, all required)

To survive Inngest replay without double-comment-and-close:
- **Guard A:** Before adding "Verified: …" comment + closing, `gh issue view --json comments --jq` for any existing comment starting with `"Verified: "`. Skip if present.
- **Guard B:** Before adding "SLA exceeded …" comment + `needs-attention` label, check (a) `gh issue view --json labels` for prior `needs-attention` label, (b) `gh issue view --json comments` for prior `"SLA exceeded "` comment. Skip if either present.
- **Guard C:** Before adding "Maximum polling …" comment + closing, check for prior `"Maximum polling "` comment. Skip if present.

### FR5: Business-day SLA math preserved

Agent prompt MUST compute SLA elapsed in BUSINESS DAYS (Mon-Fri, skip weekends) since `issue.createdAt`. Default `sla_business_days: 5` when YAML omits it. Hard cap: 30 business days = auto-close.

### FR6: Label setup preserved

Function MUST ensure `follow-through` and `needs-attention` labels exist on each invocation (per GHA `Ensure labels exist` step). Inside the Inngest fn this becomes a `step.run("ensure-labels", ...)` that exec's `gh label create … || true` — runs before the `claude-eval` step.

### FR7: GHA YAML deleted in same commit

`.github/workflows/scheduled-follow-through.yml` MUST be deleted in the same commit that adds `cron-follow-through-monitor.ts`. Per I-13 hygiene (carry-forward from PR-1).

## Technical Requirements

### TR1: ADR-033 invariants I1–I6 apply 1:1

- I1 — claude binary spawned INSIDE `step.run("claude-eval", ...)`.
- I2 — Operator `ANTHROPIC_API_KEY` only; never founder BYOK. Sentinel enforced by `cron-no-byok-lease-sweep.test.ts` (extend import allowlist to include this file).
- I3 — AbortSignal aborts at `MAX_TURN_DURATION_MS = 15 * 60 * 1000` (15 min — matches GHA `timeout-minutes: 15`). SIGTERM→SIGKILL escalation at `KILL_ESCALATION_MS = 5_000`.
- I4 — claude binary via `@anthropic-ai/claude-code` npm dep; lazy `resolveClaudeBin()` via `createRequire`.
- I5 — `step.run` returns deterministic `{ok, exitCode, signal, abortedByTimeout, durationMs}`. stdout NOT captured.
- I6 — Event payloads (the manual-trigger event has none from this fn; no-op) carry `actor: "platform"`.

### TR2: `--allowedTools` allowlist (workflow-specific widening)

```
Bash(gh issue list:*),Bash(gh issue view:*),Bash(gh issue edit:*),
Bash(gh issue comment:*),Bash(gh issue close:*),Bash(gh label create:*),
Bash(curl:*),Bash(dig:*),
Read,Glob,Grep
```

`curl` and `dig` are predicate execution; `gh issue close` and `gh label create` are state-machine verbs missing from PR-1's allowlist. SSRF prevention rests on the FR2 in-prompt HTTPS-and-non-RFC1918 guard.

### TR3: Sentry monitor slug = `scheduled-follow-through`

Continuity preserved (per PR-1's `SENTRY_MONITOR_SLUG = "scheduled-daily-triage"` precedent — slug carries forward from GHA monitor, function id follows TR9 `cron-*` convention). Heartbeat fired once at end-of-`step.run("sentry-heartbeat")` with `?status=ok|error`. Env-component regex validation (`SENTRY_DOMAIN_RE`, etc.) reused verbatim.

### TR4: Inngest function id = `cron-follow-through-monitor`

```ts
inngest.createFunction(
  {
    id: "cron-follow-through-monitor",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "0 9 * * 1-5" },
    { event: "cron/follow-through-monitor.manual-trigger" },
  ],
  cronFollowThroughMonitorHandler,
);
```

### TR5: [RETRACTED post-plan-review carry-forward] `cron_run_ledger` jitter-guard

**[Revised 2026-05-19 — see plan]** PR-1's 5-agent plan-review CUT the `cron_run_ledger` primitive entirely (4-of-5 panel converge: Inngest's native cron + `concurrency:[{scope:"fn",limit:1}]` + `step.run` memoization are the load-bearing primitive; the ledger duplicated it at lower fidelity, blocked legitimate operator manual-retry for 24h, AND its plpgsql cast chain would throw at runtime). PR-2 inherits PR-1's no-ledger architecture. No ledger row, no jitter-guard, no migration. The brainstorm's reference to `cron_run_ledger` was authored before PR-1's plan-v2 reconciliation was fully internalized; treat this TR as historical context only.

### TR6: Tests

- **New:** `apps/web-platform/test/server/inngest/cron-follow-through-monitor.test.ts` — mirror `cron-daily-triage.test.ts` structure (handler invocation, abort path, sentry heartbeat success/failure, env-malformed skip, manual-trigger event path).
- **No edit required:** `apps/web-platform/test/server/cron-no-byok-lease-sweep.test.ts` uses `globSync("server/inngest/functions/cron-*.ts")` (file already on disk at lines 39-41) — the new `cron-follow-through-monitor.ts` is picked up automatically. Verification AC: the sentinel sweep iterates over both `cron-daily-triage.ts` AND `cron-follow-through-monitor.ts` after PR-2 lands.
- **No edit required:** `apps/web-platform/test/server/byok-audit-writer-sweep.test.ts` — the 4 regex constants (`LEASE_CALL_RE`, `ALIAS_IMPORT_RE`, `BARE_IMPORT_RE`, `DYNAMIC_IMPORT_RE`) are already exported from PR-1; no further changes needed for PR-2.
- **No prompt-level integration test** required (PR-1 didn't ship one; the claude-eval step is opaque to unit tests by design per ADR-033).

### TR7: Inngest registration

`apps/web-platform/app/api/inngest/route.ts` MUST be updated to include `cronFollowThroughMonitor` in the `functions` array (mirror PR-1's `cronDailyTriage` addition).

### TR8: Sentry monitor IaC

`apps/web-platform/infra/sentry/cron-monitors.tf` currently has NO resource for `scheduled-follow-through` (line 94 is `scheduled_daily_triage` only). PR-2 MUST ADD a new `sentry_cron_monitor.scheduled_follow_through` resource mirroring the daily-triage shape with: `name = "scheduled-follow-through"`, `schedule = "0 9 * * 1-5"`, `time_zone = "UTC"`, `checkin_margin_minutes = 30`, `max_runtime_minutes = 20` (15-min AbortSignal + 5-min margin). `apply-sentry-infra.yml` auto-applies the new resource on merge — no manual operator step.

### TR9: Umbrella checkbox update

At PR-2 merge, update issue #3948 body to:
- Check the `scheduled-follow-through` checkbox.
- Add a strike-through note next to `scheduled-followthrough-sweeper`: "RECLASSIFIED group (a)/(b) infra-cron — stays on GHA, drops from TR9 scope (see PR-2)."
