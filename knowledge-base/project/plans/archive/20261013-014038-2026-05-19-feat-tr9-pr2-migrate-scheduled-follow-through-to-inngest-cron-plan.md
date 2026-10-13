---
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
parent_epic: "#3244"
parent_pr_merged: "#3985 (PR-1, scheduled-daily-triage)"
parent_adr: "ADR-033 (accepted)"
issue: "#4063"
umbrella_issue: "#3948"
sibling_open: "#3947 (PR-G)"
classification: feat-runtime-cron-migration
type: carry-forward
date: 2026-05-19
version: v2 (post-review)
---

# feat(runtime): TR9 PR-2 — migrate scheduled-follow-through to Inngest cron function

## Overview

Migrate `.github/workflows/scheduled-follow-through.yml` to an Inngest cron function `apps/web-platform/server/inngest/functions/cron-follow-through-monitor.ts`. Second migration under TR9 umbrella #3948, following PR-1 #3985 (`scheduled-daily-triage`, MERGED 2026-05-18) which established the substrate primitives in ADR-033. **PR-2 is a carry-forward**: ADR-033 invariants I1–I6 apply 1:1; this plan captures only the workflow-specific deltas and verifies them against the actual PR-1 implementation on main (not the PR-1 brainstorm doc — see Research Reconciliation).

Re-using PR-1's substrate verbatim means no fresh CPO/CLO/CTO triad spawn; carry-forward sign-off applies per Phase 0.5 step 4. The 4-agent plan-review panel (DHH, Kieran, Code Simplicity, Architecture-Strategist) ran post-draft and converged on the v1→v2 changes below.

### v1 → v2 changes (post plan-review)

**Convergent cuts (DHH + Code Simplicity):**

- **CUT 6 LARP ACs** that paraphrase phase mandates (per `2026-05-16-plan-time-ac-discipline-prod-synthetic-users-gdpr-gate-value.md`): old AC1, AC11, AC13, AC14, AC15, AC18.
- **CUT Risk #10** (write-learning-at-ship-time) — moved to `tasks.md` as a ship-time chore. A risk register entry that says "write documentation later" is noise.
- **TRIM Risk #8** to one-line deferral + issue link (#4068). Three-bullet re-evaluation criteria moved into the deferral issue body.
- **MERGE AC14a + AC14b into AC8** — both verified prompt-content directives via grep; one AC covers both with a single grep.
- **CONSOLIDATE 15-min AbortSignal rationale** to ONE surface (file header). Was repeated in 5 places: deltas table, Research Reconciliation, file header, AC10, Risk #4. Risk #4 reduced to one sentence.
- **CUT Phase 0.2** (Inngest accepts cron string) — phase itself said "no probe needed." A precondition with no check is a comment, not a phase.

**Kieran P0 mechanical fixes (ship-blockers):**

- **FIX AC8 grep robustness** — per-pattern `grep -cE` with `^+` line anchor + CIDR word boundaries (`\b127\.0\.0\.0/8\b`). Old form was vulnerable to substring drift (matched `110.0.0.0`), self-match against AC text, and `HTTPS` alternation matching any added line.
- **FIX AC12 SHA equality** — use `git log -1 --format=%H` + shell equality. Old `--name-only` multi-line output could not actually verify same-commit equality.
- **EXTEND atomicity declaration** to cover route.ts: Phases 1, 2, 5 land in a SINGLE commit (covered by Implementation Phases preamble + extended AC12). Old plan was silent on route.ts atomicity, which is the silent-loop-failure vector — without route.ts wired, Inngest worker has the file but isn't registered.

**Architecture-strategist P1 (substrate-calcification guards):**

- **FIX SSRF defense label** — triple → dual. In-prompt URL guard + spawn-env allowlist are load-bearing; Inngest `fn-concurrency=1` is blast-rate cap, NOT SSRF protection. PR-2 makes SSRF a NEW attack class (PR-1 had zero network verbs); marginal-widening framing was wrong.
- **DOCUMENT account-scope keying decision** — keep global `"cron-platform"` slot; document upper-bound manual-trigger latency = max(MAX_TURN_DURATION_MS) across all cron-* = currently 60min (PR-1's daily-triage). Re-evaluate if total cron-* grows past 3 functions.
- **ADD Phase 0.4 — Sentry weekday-cron parse verification** before merge. Verifies `getsentry/sentry` and `jianyuan/sentry` honor crontab DOW `1-5` correctly (weekend gap = expected silence, not false missed-checkin alert). Halts on failure.
- **ADD §Pattern Boundaries section** + in-file DO-NOT-COPY annotations for the 5 workflow-specific decisions (15-min budget, 30 turns, 3 idempotency guards, curl/dig allowlist, weekday cron). Prevents copy-paste contamination across PR-3..N.

**Architecture-strategist P2:**

- **ADD `silence-followthrough` opt-out label** — pre-@-mention check via `gh issue view --json labels`; skip @-mention (keep comment) if label present. Recoverability asymmetry: wrong auto-close is fixable; wrong @-mention isn't.
- **DEFER P99 per-turn wallclock attestation** — folded into Risk #4 re-evaluation criterion rather than a pre-merge AC. The total-wallclock evidence (mean 2m 45s, P95 3m 19s, ~5.5s/turn) is sufficient at PR-2 scale; P99 per-turn from Sentry traces becomes load-bearing only if a single-turn excursion exceeds the budget post-merge.

### Workflow-specific deltas vs PR-1

| Dimension | PR-1 (`cron-daily-triage`) | PR-2 (`cron-follow-through-monitor`) | Source of delta |
|---|---|---|---|
| Cron schedule | `0 4 * * *` daily | `0 9 * * 1-5` weekdays | GHA `.github/workflows/scheduled-follow-through.yml:16` |
| `MAX_TURN_DURATION_MS` | `60 * 60 * 1000` | `15 * 60 * 1000` | See file header rationale |
| `--max-turns` | `80` | `30` | GHA `--max-turns 30` (line 71) |
| `--allowedTools` | gh-CLI verbs only | gh-CLI + close + label-create + curl + dig | Predicate execution + state-machine close/label verbs |
| Side-effect class | Label-mutator + idempotent comment | Label-mutator + idempotent comment + **auto-close** + **@-mention** + **predicate execution (curl, dig)** | Workflow semantics |
| Idempotency guards | 1 | 3 (Verified-close; SLA-label; Maximum-polling) | Three state transitions to guard |
| Sentry monitor slug | `scheduled-daily-triage` (existing) | `scheduled-follow-through` (NEW resource) | No prior IaC resource |
| Inngest function id | `cron-daily-triage` | `cron-follow-through-monitor` | TR9 `cron-*` convention |
| Manual-trigger event | `cron/daily-triage.manual-trigger` | `cron/follow-through-monitor.manual-trigger` | Naming convention |
| Preflight GHA job | (none — PR-1 dropped) | DROP `preflight` job | PR-1 precedent |
| `@anthropic-ai/claude-code` dep | ADDED in PR-1 | Already in `package.json` | Carry-forward |

### Inputs

- **Spec** — `knowledge-base/project/specs/feat-cron-follow-through-monitor-tr9/spec.md`. TR5 RETRACTED (inherited stale primitive — see Research Reconciliation §1); TR6 corrected (sentinel test extension is automatic via glob); TR8 expanded (add NEW resource, not edit existing).
- **Brainstorm** — `knowledge-base/project/brainstorms/2026-05-19-tr9-pr2-scheduled-follow-through-inngest-brainstorm.md` (carry-forward triad sign-off inherited from PR-1).
- **PR-1 plan (template)** — `knowledge-base/project/plans/2026-05-18-feat-pr-1-migrate-scheduled-daily-triage-to-inngest-cron-tr9-plan.md`. Implementation phases mirror PR-1 with deltas threaded in.
- **PR-1 source-of-truth** — `apps/web-platform/server/inngest/functions/cron-daily-triage.ts` (372 lines); `apps/web-platform/test/server/inngest/cron-daily-triage.test.ts`; `apps/web-platform/test/server/cron-no-byok-lease-sweep.test.ts`; `apps/web-platform/test/server/byok-audit-writer-sweep.test.ts`.
- **ADR-033** — `knowledge-base/engineering/architecture/decisions/ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn.md` (status: accepted).
- **GHA workflow source** — `.github/workflows/scheduled-follow-through.yml` (145 lines; deleted in same commit).
- **Wallclock evidence** — `gh run list --workflow scheduled-follow-through.yml --limit 10`: mean ~2m 45s, P95 ~3m 19s, single failure (15s fast-failure 2026-05-11). At 30 turns, ~5.5s/turn average wallclock — well below abort budget per-turn.

### Out of scope (deferred)

- 9 remaining recurring cron migrations under #3948 umbrella; per-issue at migration-start time.
- `scheduled-followthrough-sweeper` reclassification — Phase 6 of this plan updates the umbrella checkbox; reclassification IS the deferral.
- `/soleur:migrate-cron-to-inngest` scaffolding skill (#3990 productize candidate). Re-evaluate after PR-2 merge.
- **Set.has() SSRF allowlist tightening** — deferred via #4068 (`deferred-scope-out`). See Risk #8.

## Research Reconciliation — Spec vs. Codebase

| Claim source | Spec / brainstorm | Codebase reality | Plan response |
|---|---|---|---|
| **`cron_run_ledger` jitter-guard** | Spec TR5 prescribes ledger + `<80%` early-return; brainstorm cites row name | **DOES NOT EXIST.** PR-1's plan-v2 reconciliation explicitly CUT the ledger (PR-1 plan line 71): "Inngest cron triggers fire at most once per scheduled time; `concurrency: [{scope:'fn',limit:1}]` covers manual-retry overlap. Ledger duplicated this at lower fidelity AND blocked operator manual-retry for 24h AND its plpgsql cast chain would throw at runtime. 4-of-5 panel converge." | **TR5 RETRACTED** in spec. No ledger work in PR-2. The brainstorm's "weekday-only + jitter-guard" concern dissolves entirely — the concern was real ONLY if the ledger existed. |
| **Sentinel test extension** | Spec TR6 originally prescribed manual file enumeration edit | `cron-no-byok-lease-sweep.test.ts:38-41` uses `globSync("server/inngest/functions/cron-*.ts")` — new files picked up automatically. `byok-audit-writer-sweep.test.ts` sweeps lease *callers*; PR-2 file is excluded by the sweepable filter (I2 enforcement). | **No edit required to either sentinel test.** AC5 verifies auto-extension. |
| **`Bash(curl:*)` allowlist precedent** | Brainstorm cites SSRF surface widening | `grep -rln "Bash(curl"` across the entire repo returns **zero hits**. PR-2 introduces a NEW allowlist shape — and a NEW attack class (PR-1 had no network verbs reachable from the agent's Bash). | **Document in file header** + §Pattern Boundaries + §Risks #1 (dual defense-in-depth: in-prompt URL guard load-bearing + spawn-env allowlist mechanical). Set.has() third-leg hardening deferred via #4068. |
| **All other claims** | (sentinel auto-extension, Sentry IaC add-not-edit, MAX_TURN_DURATION_MS rationale, drift-since-PR-1) | Verified at plan time; no drift since PR-1 merge | Subsumed by AC5, Phase 4, file header, AC10. |

## Open Code-Review Overlap

Ran `gh issue list --label code-review --state open --json number,title,body --limit 200` and grepped each body for `cron-daily-triage`, `cron-follow-through`, `apps/web-platform/server/inngest/functions/`, `cron_run_ledger`, `cron-no-byok-lease-sweep`, and `byok-audit-writer-sweep`. **Zero matches.** PR-2 has clean scope.

## Pattern Boundaries (PR-2-specific — DO NOT copy verbatim to PR-3..N)

This section enumerates decisions that bind PR-2 only. PR-3..N MUST re-derive each from their workflow-specific evidence; in-file header comments mirror this list in `cron-follow-through-monitor.ts` so the file is self-documenting against future copy-paste.

| Decision | PR-2 value | Bound by | PR-3..N must re-derive |
|---|---|---|---|
| `MAX_TURN_DURATION_MS` | `15 * 60 * 1000` | Predicate-bounded wallclock (curl/dig per turn), GHA `timeout-minutes: 15`, P95 wallclock 3m 19s evidence | Yes — each workflow's per-turn wallclock profile differs. PR-3 (`bug-fixer`) is LLM-bound, not predicate-bound; the 0.75 floor likely applies linearly there. |
| `--max-turns` | `30` | Typical follow-through corpus size (currently <10 active issues; 3× headroom) | Yes — each workflow's per-invocation work size differs. |
| 3 idempotency guards (A/B/C) | Verified-close + SLA-label + Maximum-polling | 3 state transitions specific to follow-through | Yes — re-count state transitions per workflow. PR-3 has 1; copying 3 guards is dead-code noise. |
| `Bash(curl:*),Bash(dig:*)` allowlist | Included | HTTP/DNS predicates in this workflow's YAML schema | **OMIT entirely** for any cron-* without documented predicate use. Re-introducing SSRF surface without benefit is a regression. |
| `cron: "0 9 * * 1-5"` | Weekday-only | Follow-through SLA semantic: business days only | Yes — most other cron-* are daily or weekly. Copying weekday-only would delay bug-fixer 72h every weekend. |

## Files to Create

- `apps/web-platform/server/inngest/functions/cron-follow-through-monitor.ts` — Inngest function; cron + manual-trigger event; three sequenced `step.run` (ensure-labels / claude-eval / sentry-heartbeat); inlined prompt as TS template literal; file header includes ADR-033 invariants verbatim + §Pattern Boundaries DO-NOT-COPY block.
- `apps/web-platform/test/server/inngest/cron-follow-through-monitor.test.ts` — Vitest suite, mirror of PR-1's `cron-daily-triage.test.ts`.
- `knowledge-base/project/specs/feat-cron-follow-through-monitor-tr9/tasks.md` — generated by Save Tasks step.

## Files to Edit

- `apps/web-platform/app/api/inngest/route.ts` — 2-line addition (import + array entry).
- `apps/web-platform/infra/sentry/cron-monitors.tf` — ADD new `sentry_cron_monitor.scheduled_follow_through` resource block (Phase 4).
- `#3948` (umbrella issue body) — check follow-through checkbox; reclassify sweeper.
- `knowledge-base/engineering/architecture/decisions/ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn.md` — amend with one-paragraph note on account-scope `"cron-platform"` global-slot decision (max manual-trigger latency = 60 min today; re-evaluate at 4+ cron-* functions). `[Refined 2026-05-19 post PR-2 plan review]`.

## Files to Delete

- `.github/workflows/scheduled-follow-through.yml` (same commit as Phases 1+2 land).

## Implementation Phases

**ATOMICITY (Kieran F3):** Phases **1, 2, 5 land in a SINGLE commit**. Phase 4 (Terraform resource) may land in the same commit or a follow-on — `apply-sentry-infra.yml` auto-applies only on merge to main, so monitor-creation ordering is decoupled from worker-code shipping. Phase 6 (umbrella body) is a post-merge GitHub API call, not a commit. AC12 verifies same-commit equality across the three load-bearing files.

### Phase 0 — Preconditions

Three verifications; failures halt.

- **0.1 — `claude` binary resolves under `createRequire`.** Three-line probe from worktree root:
  ```bash
  cd apps/web-platform && bun --print "const r = require('node:module').createRequire(import.meta.url); console.log(require('node:path').join(require('node:path').dirname(r.resolve('@anthropic-ai/claude-code/package.json')), '..', '..', '.bin', 'claude'))"
  ```
  Confirm path exists via `ls -la`. Discard.

- **0.3 — Sentry monitor resource conflict.** Read-only `terraform plan`:
  ```bash
  cd apps/web-platform/infra && \
    export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain) && \
    export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain) && \
    terraform init -input=false && \
    doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform plan -no-color | grep -c "scheduled_follow_through"
  ```
  Expected: 0 hits before this PR's apply.

- **0.4 — Sentry weekday-cron parse verification** (Arch F4). Confirm `getsentry/sentry` uses `croniter` (or equivalent crontab-respecting parser) AND `jianyuan/sentry` terraform provider passes the crontab through verbatim. Two `gh api` reads:
  ```bash
  gh api repos/getsentry/sentry/contents/src/sentry/monitors/utils.py 2>/dev/null | \
    jq -r .content | base64 -d | grep -E "croniter|next_schedule|MONITOR_SCHEDULE_TYPE_CRONTAB" | head -3
  gh api repos/jianyuan/terraform-provider-sentry/contents/internal/provider/resource_cron_monitor.go 2>/dev/null | \
    jq -r .content | base64 -d | grep -A3 "Crontab\|schedule"
  ```
  BOTH must produce non-empty output. If either fails, the plan must flip to a wider 7-day schedule with in-handler weekday-skip, OR raise `checkin_margin_minutes` past 72h (defeats purpose). Halt-on-failure.

### Phase 1 — Write `cron-follow-through-monitor.ts`

Mirror `cron-daily-triage.ts` 1:1 with workflow-specific deltas applied. File header includes:

```typescript
// TR9 PR-2 (#4063) — Inngest cron function for follow-through monitor.
//
// ADR-033 invariants (binding all cron-*.ts files):
//   I1–I6 verbatim — see ADR-033.
//
// NAME NOTE: Sentry slug "scheduled-follow-through" (this monitor is NEW;
// PR-1 set the precedent of slug naming for continuity). Inngest fn id
// "cron-follow-through-monitor" (TR9 convention).
//
// CLI form (per 2026-05-18-claude-code-action-claude-args-vs-direct-cli-form-drift):
// `claude` binary, `--print` required, prompt is positional, `--max-turns`
// is hidden-but-supported.
//
// MAX_TURN_DURATION_MS = 15 min — matches GHA `timeout-minutes: 15`. The
// peer-ratio floor (0.75 min/turn from 2026-03-20-claude-code-action-max-turns-budget.md)
// would prescribe 22.5 min for 30 turns IF the floor applied linearly. It
// does not here: predicate execution (curl, dig) dominates per-turn
// wallclock. Wallclock evidence at PR-2 plan time: mean 2m 45s, P95 3m 19s
// across last 10 GHA runs = ~5.5s/turn average — 4× headroom over 15 min
// budget. If P99 per-turn wallclock exceeds 30s post-merge, raise to 22.5 min
// (Risk #4 re-evaluation criterion).
//
// SSRF defense-in-depth (DUAL, not triple):
//   Layer 1 (load-bearing): in-prompt HTTPS-and-non-RFC1918 guard, copied
//     verbatim from .github/workflows/scheduled-follow-through.yml:96-101.
//   Layer 2 (mechanical): buildSpawnEnv() allowlist — only PATH, HOME,
//     NODE_ENV, ANTHROPIC_API_KEY, GH_TOKEN reach the subprocess.
// (Inngest fn-concurrency=1 is blast-rate cap, NOT SSRF defense.)
// Set.has() exact-match allowlist is the planned third-leg hardening,
// deferred via #4068 (deferred-scope-out).
//
// PR-2 SPECIFIC — DO NOT copy to PR-3..N without re-derivation
// (see plan §Pattern Boundaries):
//   MAX_TURN_DURATION_MS = 15min     ← bound by predicate wallclock
//   --max-turns 30                    ← bound by follow-through corpus size
//   Guards A/B/C                      ← bound by 3 state transitions
//   Bash(curl:*),Bash(dig:*)          ← OMIT if no network-verb need
//   cron: "0 9 * * 1-5"               ← bound by follow-through SLA semantic
//
// Account-scope concurrency key: "cron-platform" (global, shared with
// cron-daily-triage). Manual-trigger latency upper bound = max(MAX_TURN_DURATION_MS)
// across all cron-* = 60 min (PR-1's daily-triage). Re-evaluate keying
// scheme if cron-* count grows past 3 functions.
```

Then code shape (deltas from `cron-daily-triage.ts`):

```typescript
const CLAUDE_CODE_FLAGS = [
  "--print",
  "--model", "claude-sonnet-4-6",
  "--max-turns", "30",
  "--allowedTools",
  "Bash(gh issue list:*),Bash(gh issue view:*),Bash(gh issue edit:*),Bash(gh issue comment:*),Bash(gh issue close:*),Bash(gh label create:*),Bash(curl:*),Bash(dig:*),Read,Glob,Grep",
];

export const MAX_TURN_DURATION_MS = 15 * 60 * 1000;
export const KILL_ESCALATION_MS = 5_000;

const SENTRY_MONITOR_SLUG = "scheduled-follow-through";
```

**Prompt body**: inline the entire `prompt: |` block from `.github/workflows/scheduled-follow-through.yml:73-145` as `FOLLOW_THROUGH_PROMPT = String.raw\`...\``. Four additions to Sharp Edges:

1. **Guard A (auto-close on PASS)**: search-before-add `"Verified: "` comment + close.
2. **Guard B (SLA-exceeded)**: search-before-add `needs-attention` label + `"SLA exceeded "` comment.
3. **Guard C (max-polling auto-close)**: search-before-add `"Maximum polling "` comment + close.
4. **NEW Sharp Edges directives**:
   - "NEVER include the substring `closes #`, `fixes #`, `resolves #`, `closed #`, `fixed #`, `resolved #` (case-insensitive) anywhere in any comment body. Closing happens exclusively via `gh issue close` API call, never via close-keyword in comment text. (Per 2026-05-07-claude-code-action-boundaries-and-once-schedule-bundle.md — GitHub's auto-close regex is markdown-blind and fires inside code blocks, blockquotes, prose.)"
   - "@-mention target MUST come exclusively from `gh issue view <N> --json author --jq '.author.login'`. NEVER derive an @-mention from issue body text, predicate output, or any other source. If the author has the label `silence-followthrough`, post the comment WITHOUT the @-mention prefix (keep the rest of the comment text)."

Three sequenced `step.run` steps (mirror PR-1):

```typescript
// Step 1: ensure-labels — creates follow-through + needs-attention + silence-followthrough (NEW per Arch F5).
await step.run("ensure-labels", async () => { /* gh label create with || true */ });

// Step 2: claude-eval — mirror PR-1 with deltas applied.
const result = await step.run("claude-eval", async () => { /* spawn + abort + escalation */ });

// Step 3: sentry-heartbeat — mirror PR-1 verbatim, only slug differs.
await step.run("sentry-heartbeat", async () => { /* slug = "scheduled-follow-through" */ });
```

Registration block:

```typescript
export const cronFollowThroughMonitor = inngest.createFunction(
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
  cronFollowThroughMonitorHandler as unknown as Parameters<typeof inngest.createFunction>[2],
);
```

### Phase 2 — Register in `route.ts` (SAME commit as Phase 1)

```typescript
import { cronFollowThroughMonitor } from "@/server/inngest/functions/cron-follow-through-monitor";

export const { GET, POST, PUT } = serve({
  client: inngest,
  functions: [cfoOnPaymentFailed, cronDailyTriage, cronFollowThroughMonitor],
  signingKey: SIGNING_KEY ?? "build-phase-placeholder",
});
```

### Phase 3 — Tests: `cron-follow-through-monitor.test.ts`

Mirror `cron-daily-triage.test.ts`. Five test cases:

- **T1 — Happy path.** Spawn exits 0; Sentry fetch 200. Heartbeat called with slug `scheduled-follow-through`, `status=ok`.
- **T2 — Spawn error.** Spawn fires `error` ENOENT. `reportSilentFallback` called; heartbeat `status=error`.
- **T3 — AbortSignal at 15 min.** Fake timers; advance past 15 min; assert SIGTERM at -pid; advance another 5s; assert SIGKILL.
- **T4 — Sentry env missing.** Unset domain env var; assert no fetch; step resolves.
- **T5 — Manual-trigger event path.** Same handler args; assert execution regardless of trigger source.

### Phase 4 — Sentry monitor IaC

Add to `apps/web-platform/infra/sentry/cron-monitors.tf` (insert after `scheduled_daily_triage` resource at line 110):

```hcl
resource "sentry_cron_monitor" "scheduled_follow_through" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "scheduled-follow-through"
  schedule     = { crontab = "0 9 * * 1-5" }
  # TR9 PR-2 (#4063): new Inngest-fired monitor. 30-min margin per Inngest-fired
  # precedent (PR-1 line 105, PR-γ #4006). Weekday-only DOW range (1-5) is honored
  # by Sentry's croniter-backed missed-checkin algorithm (verified at Phase 0.4 of
  # the plan) — weekend gap is expected silence, not a false missed-checkin alert.
  checkin_margin_minutes  = 30
  max_runtime_minutes     = 15
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}
```

`apply-sentry-infra.yml` auto-applies on merge (scoped to `-target=sentry_cron_monitor.*`).

### Phase 5 — GHA YAML deletion (SAME commit as Phases 1+2)

```bash
git rm .github/workflows/scheduled-follow-through.yml
```

Singleton deletion (Kieran F8 confirmed no analogous one-shot strays).

### Phase 6 — Umbrella body update + sweeper reclassification

Post-merge: `gh issue edit 3948` two textual transformations (see brainstorm doc for the full strings).

### Phase 7 — Pre-merge verification

```bash
bun --cwd apps/web-platform run typecheck
bun --cwd apps/web-platform run test:ci
cd apps/web-platform/infra && terraform fmt -check && terraform validate
```

Test suite MUST show:
- `cron-follow-through-monitor.test.ts`: 5 cases passing.
- `cron-no-byok-lease-sweep.test.ts`: sweep enumerates **2** files (`cron-daily-triage.ts` + `cron-follow-through-monitor.ts`).

PR #4062 body uses `Closes #4063` + `Refs #3948` + `Refs #4068` (SSRF deferral).

### Phase 8 — Post-merge (automation)

- Deploy pipeline ships new code via existing `npm install` + Hetzner deploy. Inngest worker auto-registers `cronFollowThroughMonitor`.
- `apply-sentry-infra.yml` auto-applies new resource.
- **Operator verification (cheap, automatable):** `inngest send cron/follow-through-monitor.manual-trigger` within ~5 min of deploy. Verifiable via Inngest dashboard + Sentry monitor heartbeat + behavioral observation on any open follow-through issues.
- Phase 6 umbrella update via `gh issue edit`.

## Acceptance Criteria

### Pre-merge (PR ready)

- **AC2.** Inngest registration uses `id: "cron-follow-through-monitor"`, `concurrency: [{scope:"fn",limit:1}, {scope:"account",key:'"cron-platform"',limit:1}]`, `retries: 1`, `[{cron:"0 9 * * 1-5"},{event:"cron/follow-through-monitor.manual-trigger"}]`.
- **AC3.** `claude-eval` step.run spawns `claude` with `detached: true`; `MAX_TURN_DURATION_MS = 15 * 60 * 1000`; abort sends `process.kill(-pid, "SIGTERM")` then `SIGKILL` at 5s. Returns deterministic `{ok, exitCode, signal, abortedByTimeout, durationMs}`.
- **AC4.** Sentry heartbeat single POST to slug `scheduled-follow-through`; `?status=ok|error`. Env-component regex validation reused verbatim from PR-1. Silent skip on missing/malformed env.
- **AC5.** `cron-no-byok-lease-sweep.test.ts` sweep enumerates **2** files (`cron-daily-triage.ts` + `cron-follow-through-monitor.ts`) — both pass. No edits to either sentinel test file (glob auto-extension; CWD = `apps/web-platform/` per `vitest.config.ts` default root). Verified via test runner output.
- **AC6.** Vitest suite covers T1–T5. T3 asserts SIGKILL escalation after 5s at the **15-min** AbortSignal.
- **AC7.** `cron-monitors.tf` has new `sentry_cron_monitor.scheduled_follow_through` resource with `name = "scheduled-follow-through"`, `schedule = {crontab = "0 9 * * 1-5"}`, `checkin_margin_minutes = 30`, `max_runtime_minutes = 15`. `terraform fmt -check` + `terraform validate` clean.
- **AC8 — Prompt verbatim + Sharp Edges directives + per-pattern grep.** Prompt body inlined verbatim from `.github/workflows/scheduled-follow-through.yml:73-145`, with Guards A/B/C added. Sharp Edges section includes (i) close-keyword forbidden directive, (ii) @-mention from `gh issue view --json author` directive, (iii) `silence-followthrough` label opt-out directive. Verifiable via per-pattern grep on `+` added-lines only:
  ```bash
  diff=$(git diff main -- apps/web-platform/server/inngest/functions/cron-follow-through-monitor.ts | grep '^+' | grep -v '^+++')
  for pat in 'Only request HTTPS' '\b127\.0\.0\.0/8\b' '\b10\.0\.0\.0/8\b' '\b172\.16\.0\.0/12\b' '\b192\.168\.0\.0/16\b' '\b169\.254\.0\.0/16\b' 'NEVER include the substring' 'silence-followthrough' "author\.login"; do
    count=$(printf '%s\n' "$diff" | grep -cE "$pat") || true
    [ "$count" -ge 1 ] || { echo "AC8 FAIL: $pat"; exit 1; }
  done
  ```
- **AC9.** `--allowedTools` exactly: `Bash(gh issue list:*),Bash(gh issue view:*),Bash(gh issue edit:*),Bash(gh issue comment:*),Bash(gh issue close:*),Bash(gh label create:*),Bash(curl:*),Bash(dig:*),Read,Glob,Grep`.
- **AC10.** `--max-turns 30` and `MAX_TURN_DURATION_MS = 15 * 60 * 1000`. File header documents the 0.5 min/turn ratio rationale with predicate-bounded-wallclock + wallclock evidence (mean 2m 45s, P95 3m 19s).
- **AC12 — Atomicity of Phases 1+2+5 in a single commit.** Verifiable via SHA equality:
  ```bash
  add_fn=$(git log -1 --diff-filter=A --format=%H -- apps/web-platform/server/inngest/functions/cron-follow-through-monitor.ts)
  add_test=$(git log -1 --diff-filter=A --format=%H -- apps/web-platform/test/server/inngest/cron-follow-through-monitor.test.ts)
  mod_route=$(git log -1 --format=%H -- apps/web-platform/app/api/inngest/route.ts)
  del_yaml=$(git log -1 --diff-filter=D --format=%H -- .github/workflows/scheduled-follow-through.yml)
  [ "$add_fn" = "$mod_route" ] && [ "$add_fn" = "$del_yaml" ] || { echo "AC12 FAIL: $add_fn vs $mod_route vs $del_yaml"; exit 1; }
  echo "AC12 PASS: $add_fn"
  ```
  (Note: `add_test` may be in the same commit OR a follow-on since tests don't gate Inngest registration; equality not asserted.)
- **AC17 — Manual-trigger end-to-end verification.** Within 5 min of deploy completion: `inngest send cron/follow-through-monitor.manual-trigger` produces Sentry `status=ok` heartbeat AND processes any open follow-through issues per the prompt's state-transition rules.

### Post-merge (automation-driven)

- **AC16 — Sentry monitor active.** `apply-sentry-infra.yml` auto-applies the new resource. Verifiable via `gh api repos/jikig-ai/soleur/actions/runs --jq '.workflow_runs[] | select(.name=="Apply Sentry Infra") | {id, conclusion, head_sha}' | head -5` (NOT dashboard eyeball — `hr-no-dashboard-eyeball-pull-data-yourself`). The first run after PR-2 merge MUST have `conclusion: "success"` and `head_sha` matching the PR-2 merge commit.

## Domain Review

**Domains relevant:** Engineering (CTO), Legal (CLO), Product (CPO) — carry-forward from PR-1 + PR-2 brainstorm. Marketing/Sales/Finance/Support/Operations: not relevant.

### Engineering (CTO) — Status: reviewed (carry-forward + 4-agent plan-review)

ADR-033 invariants I1–I6 apply 1:1. No new substrate primitives. PR-2-specific architecture concerns (SSRF surface widening, account-scope keying decision, Sentry weekday-cron parse, substrate-calcification across PR-3..N) addressed via §Pattern Boundaries + Phase 0.4 + ADR-033 amendment.

### Product (CPO) — Status: reviewed (carry-forward)

Sequencing unchanged: TR9 PR-2 ships before PR-G #3947. Bucket ii confirmed. Sweeper reclassification is a positive scope reduction.

### Legal (CLO) — Status: reviewed (carry-forward)

Self-hosted Inngest avoids new sub-processor cycle. Article 30 record reused from PR-1 — same data classes. `hr-autonomous-loop-skill-api-budget-disclosure` NO-OP. No key rotation.

### Product/UX Gate — Tier: NONE

Server-side only. No new `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`.

## User-Brand Impact

**Brand-survival threshold:** `single-user incident` (carry-forward). `requires_cpo_signoff: true`.

**If this lands broken, the user experiences:**

- **Silent loop failure** — operator's follow-through monitor stops firing. Mitigated by AC4 (Sentry heartbeat) + AC16 (30-min margin triggers missed-check-in alert) + AC17 (post-deploy manual-trigger verification before first cron fire).
- **False-positive auto-close** — predicate returns 200 on a URL redirecting to an error page; agent auto-closes a real follow-through. **NEW vector unique to PR-2.** Mitigations: (a) the prompt's HTTP-200-equals-string-"200" check is stricter than 2xx; (b) Guard A's idempotency keeps the original close stable on replay; (c) operator can reopen. Re-evaluation criterion: if false-positive auto-close occurs ≥1 time in first 30 days post-merge, scope a follow-up to require `expected_substring` in YAML for http-200.
- **Wrong-actor action (forward-looking)** — AC5 sentinel + AP-014 register entry close the boundary (carry-forward).
- **Replay-cost runaway** — Mitigated by AC3 deterministic capture + Guards A/B/C idempotency.

**If this leaks, the user's [credentials / agent reputation] is exposed via:**

- **Operator `ANTHROPIC_API_KEY`** — Doppler-injected; no new secret; `pino` scrubbing applies.
- **SSRF via `Bash(curl:*)` jailbreak** — NEW attack class unique to PR-2 (PR-1 had zero network verbs reachable from agent's Bash). **Dual defense-in-depth (load-bearing):**
  1. **In-prompt HTTPS-and-non-RFC1918 guard** (AC8) — verbatim from GHA prompt.
  2. **`buildSpawnEnv()` allowlist** — only PATH, HOME, NODE_ENV, ANTHROPIC_API_KEY, GH_TOKEN reach the subprocess. `env | curl …` exfils nothing beyond the operator's GH token (operator's own repo scope).
  Inngest `fn-concurrency=1` is blast-rate cap, NOT SSRF defense. Set.has() exact-match allowlist is the planned third-leg hardening, deferred via **#4068** (Risk #8).

**Plan-time gates:**

- `user-impact-reviewer` MUST sign off at PR review.
- preflight Check 6 fires on `cron-*.ts`, `cron-*.test.ts`, `cron-monitors.tf`.

## Risks

1. **SSRF via curl/dig allowlist widening.** PR-2 introduces a NEW attack class (PR-1 had zero network verbs). Dual defense-in-depth: in-prompt URL guard (load-bearing per AC8) + spawn-env allowlist (mechanical). Inngest `fn-concurrency=1` is blast-rate cap, NOT SSRF defense (Arch F1). Third-leg hardening (Set.has()) deferred per Risk #8.
2. **False-positive auto-close on http-200 predicate.** Documented in User-Brand Impact + 30-day re-evaluation criterion.
3. **Guard A/B/C TOCTOU window.** ~50-500ms between `gh issue view` and subsequent `gh issue comment`/`gh issue close`. Inngest `fn`-scope concurrency=1 + `account`-scope concurrency=1 prevent two parallel invocations → serialization closes the window (Kieran F9 confirmed).
4. **15-min AbortSignal floor coherence.** 30 turns × 0.75 floor = 22.5 min would apply IF the floor were linear. Wallclock evidence (~5.5s/turn) gives 4× headroom. Re-evaluation criterion: if `abortedByTimeout: true` fires >1× in 30 days, OR if Sentry trace per-turn P99 exceeds 30s, raise budget to 22.5 min. File header documents the rationale (single surface; not repeated).
5. **Sentry monitor apply-ordering race.** If `apply-sentry-infra.yml` fires before Inngest worker registration, first scheduled fire arrives at a monitor whose `failure_issue_threshold = 1` files an issue on missed-checkin. Mitigation: AC17 manual-trigger verification within 5 min of deploy completion confirms registration BEFORE first scheduled fire.
6. **`scheduled-followthrough-sweeper` reclassification accuracy.** Criterion in umbrella body is explicit ("pure shell, no LLM call"); future LLM-introducing change must re-include sweeper in TR9 scope.
7. **Auto-close keyword markdown-blindness.** GitHub's auto-close regex `(close|fix|resolve)[sd]?\s+(#N|GH-N)` is markdown-blind. AC8 grep verifies the prompt's NEW Sharp Edges directive forbidding `closes #` / `fixes #` / `resolves #` substrings in any comment body. Closing happens exclusively via `gh issue close` API call.
8. **Set.has() SSRF allowlist deferred — tracked at #4068** (`deferred-scope-out`). Re-evaluation criteria live in the issue body.
9. **Account-scope `"cron-platform"` global slot — manual-trigger latency upper bound.** Two cron-* now share one slot; max manual-trigger queue latency = max(MAX_TURN_DURATION_MS) across all cron-* = 60 min today. Documented in ADR-033 amendment. Re-evaluate keying scheme (per-fn-class key) at 4+ cron-* functions.
10. **PR-2 substrate decisions calcifying across PR-3..N.** §Pattern Boundaries enumerates each workflow-specific decision with DO-NOT-COPY tags; in-file header annotations mirror the list so `cron-follow-through-monitor.ts` is self-documenting against future copy-paste.

## Test Strategy

- **Vitest unit:** `cron-follow-through-monitor.test.ts` T1–T5; mocked `spawn` + `fetch`.
- **Source-grep CI:** `cron-no-byok-lease-sweep.test.ts` glob enumerates both cron-* files (auto-extension; no edit needed).
- **Terraform:** `fmt -check` + `validate` on `apps/web-platform/infra/sentry/`.
- **Manual verification post-deploy:** `inngest send cron/follow-through-monitor.manual-trigger` (AC17).
- **No TENANT_INTEGRATION_TEST gate**; no live tenant data.
- **No prompt-level integration test**; claude-eval step is opaque to unit tests per ADR-033.

## References

- **Issue:** [#4063](https://github.com/jikig-ai/soleur/issues/4063) — child of umbrella #3948.
- **Umbrella:** [#3948](https://github.com/jikig-ai/soleur/issues/3948).
- **Predecessor PR (MERGED):** [#3985](https://github.com/jikig-ai/soleur/pull/3985) — PR-1.
- **This work (draft PR):** [#4062](https://github.com/jikig-ai/soleur/pull/4062).
- **SSRF deferral (filed at plan-review v2):** [#4068](https://github.com/jikig-ai/soleur/issues/4068).
- **PR-1 plan (template):** `knowledge-base/project/plans/2026-05-18-feat-pr-1-migrate-scheduled-daily-triage-to-inngest-cron-tr9-plan.md`.
- **Brainstorm:** `knowledge-base/project/brainstorms/2026-05-19-tr9-pr2-scheduled-follow-through-inngest-brainstorm.md`.
- **Spec:** `knowledge-base/project/specs/feat-cron-follow-through-monitor-tr9/spec.md`.
- **ADR-033** (binding invariants; amend with account-scope decision): `knowledge-base/engineering/architecture/decisions/ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn.md`.
- **ADR-030** (substrate parent): `knowledge-base/engineering/architecture/decisions/ADR-030-inngest-as-durable-trigger-layer.md`.
- **AGENTS.md rules touched:** `hr-weigh-every-decision-against-target-user-impact`, `hr-write-boundary-sentinel-sweep-all-write-sites`, `cq-silent-fallback-must-mirror-to-sentry`, `cq-nextjs-route-files-http-only-exports`, `hr-all-infrastructure-provisioning-servers`, `hr-no-dashboard-eyeball-pull-data-yourself`.
- **Learnings carried forward:**
  - `2026-05-18-vendor-cron-heartbeat-silent-fail-pattern.md`
  - `2026-05-16-migration-mandates-must-have-wired-call-sites-in-same-pr.md`
  - `2026-05-18-claude-code-action-claude-args-vs-direct-cli-form-drift.md`
  - `2026-05-18-brainstorm-verify-issue-body-enumerations-against-live-state.md`
  - `2026-05-07-claude-code-action-boundaries-and-once-schedule-bundle.md` (auto-close keyword markdown-blindness; AC8 + Risk #7)
  - `2026-03-20-open-redirect-allowlist-validation.md` (Set.has() third-leg hardening; deferred via #4068)
  - `2026-05-15-ci-sentinel-paren-safety-substring-match-against-canonical-prose.md` (AC8 grep robustness — word-boundary CIDR anchors)
  - `2026-05-15-plan-ac-verification-commands-awk-self-match-and-marker-conjunction.md` (AC8 `^+` anchor)
  - `2026-05-16-plan-time-ac-discipline-prod-synthetic-users-gdpr-gate-value.md` (LARP-AC cut criterion)
- **Wallclock evidence** (plan-time): mean ~2m 45s, P95 ~3m 19s, 1 fast-failure (2026-05-11).
- **Plan-review panel:** DHH (cuts), Kieran (P0 mechanical fixes), Code Simplicity (YAGNI cuts), Architecture-Strategist (substrate-calcification guards). All 4 reviews completed 2026-05-19.
