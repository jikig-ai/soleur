---
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
parent_epic: "#3244"
parent_pr_merged: "#3940 (PR-F)"
parent_adr: "ADR-033 (active)"
issue: "#3948"
sibling_open: "#3947 (PR-G)"
classification: feat-runtime-cron-migration
type: feature
date: 2026-05-18
version: v2 (post-review)
---

# feat(runtime): PR-1 — migrate scheduled-daily-triage to Inngest cron function (TR9 proof-of-pattern)

## Overview

Migrate the `scheduled-daily-triage` GitHub Actions workflow to an Inngest cron function (`cron-daily-triage`) running inside the Hetzner Node worker that PR-F (#3940, MERGED 2026-05-17) provisioned. Operator-chosen target (CPO recommended `scheduled-strategy-review` for shell-only simplicity; operator overrode 2026-05-18 to pick the hardest of the 11 recurring candidates — proof on a write-class, daily-fire, claude-code-action workflow). PR-1 lands the load-bearing primitives that PR-2..N reuse:

1. `cron-*.ts` file naming convention + Inngest function registration shape with both cron AND event triggers (manual-retry path).
2. `child_process.spawn('claude-code', ...)` inside `step.run` with process-group SIGTERM→SIGKILL escalation at 60-min AbortSignal.
3. Sentry heartbeat at end-of-`step.run` (single end-of-job POST per today's `2026-05-18-vendor-cron-heartbeat-silent-fail-pattern.md`).
4. Inverse-assertion sentinel: `cron-*.ts` files MUST NOT import or call `runWithByokLease` (ADR-033 I2 boundary marker).
5. Global `account`-scoped concurrency `"cron-platform"` (single in-flight cron-* across the Hetzner node — prevents OOM under future cron-* fan-out).
6. `@anthropic-ai/claude-code` as `apps/web-platform/package.json` dependency (ships via existing deploy pipeline — no separate IaC dance).
7. Delete-GHA-YAML-same-commit hygiene (per `2026-05-16-migration-mandates-must-have-wired-call-sites-in-same-pr.md`).

### v1 → v2 changes (5-agent plan-review reconciliation)

5-agent panel (DHH, Kieran, Code Simplicity, Architecture Strategist, Spec Flow) fired because brand-survival threshold = `single-user incident`. v2 cuts converge across both simplification axis (DHH + Code Simplicity) AND correctness axis (Kieran + Architecture + Spec Flow):

- **CUT `cron_run_ledger` table + migration + RPC + jitter-guard step.** Inngest cron triggers fire at most once per scheduled time; `concurrency: [{scope: "fn", limit: 1}]` covers manual-retry overlap. Ledger solved a non-existent problem AND introduced a 24h operator-retry trap AND its plpgsql cast-to-boolean would throw at runtime. 4-of-5 converge.
- **INLINE prompt as TS template literal.** esbuild bundling excludes `.md` files; `readFileSync(PROMPT_PATH)` would throw at first fire. 3-of-5.
- **REPLACE bootstrap.sh + terraform_data dance with one `package.json` dep.** Existing deploy pipeline installs Node deps; claude-code's npm package ships via `node_modules/.bin/claude-code`. 2-of-5.
- **KEEP existing Sentry slug `scheduled-daily-triage`.** No rename, no destroy-create window. Function file name is `cron-daily-triage.ts` (convention); Sentry slug stays for continuity. 3-of-5.
- **CUT Phase 9 11-issue pre-filing.** Single umbrella checkbox list on #3948 body; defer child issues to migration-start time. 2-of-5.
- **FIX AbortSignal grandchild propagation** (Kieran P0-3): `detached: true` + manual SIGTERM-then-SIGKILL on process group.
- **RAISE AbortSignal to 60min** (Architecture F2): 55-min × 80-turn = 0.69 ratio below 0.75 peer floor; partial-run silent-failure shape.
- **ADD `account`-scope `"cron-platform"` concurrency** (Architecture F7): prevents Hetzner OOM under concurrent crons in PR-2..N era.
- **ADD event trigger alongside cron** (Spec-flow AC37): operator can `inngest send cron/daily-triage.manual-trigger` to retry after failure.

### Inputs

- **Brainstorm** — `knowledge-base/project/brainstorms/2026-05-18-tr9-agent-loop-crons-inngest-migration-brainstorm.md` (CPO + CLO + CTO triad signed off).
- **Spec** — `knowledge-base/project/specs/feat-agent-loop-crons-inngest-tr9/spec.md`. **Spec FR1-FR16 superseded by this plan where they diverge** — specifically: FR1/FR2/FR7/TR4/TR8 (the `cron_run_ledger` migration) are CUT per panel reconciliation. spec.md will be updated in lockstep with this plan in Phase 9.
- **ADR-033** — `knowledge-base/engineering/architecture/decisions/ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn.md` (active; I1-I6 bind PR-1 and all 10 subsequent migrations). **ADR-033 I3 amended in v2**: AbortSignal ceiling = 60 min (not 55); rollback headroom rationale dropped (Inngest replays don't depend on spawn ceiling).
- **Parent ADR-030** — Inngest substrate self-hosted on Hetzner.
- **Today's silent-fail learning** — `2026-05-18-vendor-cron-heartbeat-silent-fail-pattern.md`.
- **Peer-ratio learning** — `2026-03-20-claude-code-action-max-turns-budget.md` (0.75 min/turn floor for daily-triage class).

### Out of scope (deferred to follow-up issues)

- 10 remaining recurring cron migrations — tracked as a checkbox list on #3948 umbrella body. Child issues filed at migration-start time, NOT at PR-1 plan-time (DHH P0-3 / Code-Simplicity P1: speculative-stale).
- `scheduled-gdpr-gate-preflight-eval-50d.yml` one-shot conversion — 11th umbrella checkbox.
- Founder-visible digest of cron run outcomes (Spec-flow AC17). Today the operator IS the only founder; Sentry monitor + Inngest dashboard is sufficient observability. Re-evaluate post PR-G.
- Post-flight canary on label distribution (Spec-flow AC21). Defer; will land if model-drift becomes a real incident class.
- Runtime guard at `runWithByokLease` call-stack level (Architecture F9). Build-time sentinel + reviewer attention is sufficient at PR-1's 1-file blast radius.
- Versioned-symlink rollback in claude-code install (Architecture F10). N/A — install path simplified to package.json dep.
- AGENTS.md workflow gate for cron-migration merge-window (Architecture F11). Defer to PR-2+ once we have data on deploy-pipeline timing.
- AP-014 principles register entry (Architecture F12). Cheap; do in Phase 9 alongside the umbrella body update.
- `/soleur:migrate-cron-to-inngest` scaffolding skill (#3990 productize candidate). Re-evaluate after PR-1 + 2 follow-up migrations.
- Group-(a) CI workflows (~18) and group-(b) content workflows (~8) — explicitly NEVER in TR9 scope per PR-F K14.

## Research Reconciliation — Spec vs. Codebase

| Claim source | Spec | Codebase reality | Plan response (v2) |
|---|---|---|---|
| Sentry monitor name | Spec FR8 says `cron-daily-triage` monitor | Existing `sentry_cron_monitor.scheduled_daily_triage` at `cron-monitors.tf:94` | **KEEP existing slug.** No Terraform rename. Function file is `cron-daily-triage.ts` (convention); Sentry slug stays `scheduled-daily-triage` (continuity). Code-comment documents the mismatch. Phase 5 reduces to a `checkin_margin_minutes` adjustment only (180 → 30; Inngest has minimal jitter vs GHA). |
| Jitter-guard ledger | Spec FR1/FR2/FR7/TR4/TR8 prescribe `cron_run_ledger` table + `record_cron_run` RPC | Inngest cron triggers fire at most once per scheduled time. `concurrency: [{scope: "fn", limit: 1}]` covers manual-retry duplicates. The plpgsql cast chain would throw at runtime. Ledger blocks legitimate operator manual-retry for 24h. | **CUT entirely.** Spec FR1/FR2/FR7/TR4/TR8 are formally retracted in Phase 9 spec.md update. The "proof-of-pattern primitive" framing was wrong — Inngest's native cron + step.run memoization is the load-bearing primitive; the ledger duplicated it at lower fidelity. |
| `claude-code` on Hetzner | Spec TR2 says "claude-code CLI installed with pinned version" | No existing reference in `apps/web-platform/infra/` | **Install via `package.json` dep.** Add `"@anthropic-ai/claude-code": "<version>"` to `apps/web-platform/package.json`. Existing deploy pipeline runs `npm install` on Hetzner. Resolve at module load via `import.meta.resolve` or `node_modules/.bin/claude-code` (verify which works under esbuild bundling at Phase 0.2). No bootstrap.sh, no terraform_data, no cloud-init addendum. |
| Prompt file co-location | Spec FR3 says co-located `.prompt.md` | esbuild bundles `apps/web-platform/server/**` and does NOT copy non-imported asset files (`.md`). `readFileSync(PROMPT_PATH)` would throw at first fire on Hetzner. | **Inline as TS template literal.** Export `const DAILY_TRIAGE_PROMPT = String.raw\`...\`` from `cron-daily-triage.ts` itself OR from a sibling `cron-daily-triage.prompt.ts`. esbuild bundles TS imports correctly. |
| Inngest event-emit invariant `actor: "platform"` | Spec FR5 says event payloads carry `actor: "platform"` | `cron-daily-triage` emits zero events; vacuously satisfied. The inverse-assertion sentinel enforces I2 (no founder BYOK) which is the architectural boundary that matters at PR-1. | Code-comment documents the I6 invariant; future-facing sentinel deferred until first cron-* function actually emits (Code-Simplicity P1). |

## Open Code-Review Overlap

Ran `gh issue list --label code-review --state open --json number,title,body --limit 200` and grepped each open issue body for files PR-1 touches. Two issues overlap:

- **#3829 (CI gate: "new Sentry monitor type → sentry-scrub.ts must change").** **Disposition: Acknowledge.** PR-1 v2 no longer adds a new `sentry_cron_monitor` resource (Phase 5 reduced to `checkin_margin_minutes` adjustment). No new monitor type; no new monitor instance. #3829's re-evaluation criterion ("new monitor types") not triggered. AC8 below explicitly confirms no `Sentry.logger` / `sentry.logs` / `sentry_log_*` / `log-condition` patterns introduced.
- **#3828 (extract composite action for 9-workflow Sentry Crons fan-out).** **Disposition: Acknowledge.** PR-1 deletes `scheduled-daily-triage.yml` (auto-reducing fan-out by 1 — to 8). #3828's calculus shifts slightly; stays open as a separate refactor decision on the remaining 8 workflows.

## Files to Create

- `apps/web-platform/server/inngest/functions/cron-daily-triage.ts` — Inngest function registered with **both** cron `0 4 * * *` AND event `cron/daily-triage.manual-trigger` triggers; three sequenced `step.run` steps (claude-eval / sentry-heartbeat / ledger-write-stub). Prompt inlined as TS template literal at module top.
- `apps/web-platform/test/server/inngest/cron-daily-triage.test.ts` — Vitest suite covering the 5 cases listed under Phase 6.
- `apps/web-platform/test/server/cron-no-byok-lease-sweep.test.ts` — extracted inverse-assertion sentinel (Kieran P1-2). Imports `LEASE_CALL_RE`, `ALIAS_IMPORT_RE`, and new `BARE_IMPORT_RE` from the existing byok-audit-writer-sweep.test.ts.
- `knowledge-base/project/specs/feat-agent-loop-crons-inngest-tr9/tasks.md` — generated by Save Tasks step.

## Files to Edit

- `apps/web-platform/package.json` — add `"@anthropic-ai/claude-code": "<pinned-version>"` to `dependencies` (version determined at Phase 0.1 via `npm view @anthropic-ai/claude-code dist-tags.latest`).
- `apps/web-platform/app/api/inngest/route.ts` — `import { cronDailyTriage }` + append to `functions: [...]` array.
- `apps/web-platform/test/server/byok-audit-writer-sweep.test.ts` — `export { LEASE_CALL_RE, ALIAS_IMPORT_RE }`; add `export const BARE_IMPORT_RE = /import\s*\{[^}]*\brunWithByokLease\b[^}]*\}/` (catches bare named import, subsumes alias case but keep both for explicit named-failure messages).
- `apps/web-platform/infra/sentry/cron-monitors.tf` — adjust `checkin_margin_minutes` from 180 to 30 on the existing `sentry_cron_monitor.scheduled_daily_triage` resource (Inngest has minimal jitter vs GHA's ~60-min sub-hourly degradation). Resource id + `name` field UNCHANGED for continuity.
- `knowledge-base/project/specs/feat-agent-loop-crons-inngest-tr9/spec.md` — Phase 9 retract FR1/FR2/FR7/TR4/TR8 (ledger) with a `[Revised post plan-review 2026-05-18]` note pointing at this plan; update FR3 (prompt inlining); update FR8 (Sentry slug continuity); update FR-claude-code-install (package.json dep, not IaC).
- `knowledge-base/engineering/architecture/decisions/ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn.md` — amend I3 (60-min not 55); amend I4 (claude-code via package.json dep, not cloud-init pin) — these are not full superseding; mark as `[Refined 2026-05-18 post PR-1 plan review]` inline.
- `knowledge-base/engineering/architecture/principles-register.md` — add AP-014 "Platform-loop / per-founder cohabitation boundary" sourced to ADR-033 (Architecture F12; cheap and load-bearing for proof-of-pattern).
- `#3948` (GitHub issue body) — add `## Umbrella Children` section with 11 checkbox items (one per remaining workflow + 1 gdpr-gate-50d conversion). Each line cites the workflow + current schedule; full child issue is filed by the migrator at migration-start time.

## Files to Delete

- `.github/workflows/scheduled-daily-triage.yml` (same commit as `cron-daily-triage.ts`).
- `.github/workflows/scheduled-dogfood-once-3049.yml` (already fired 2026-05-04, #3049 closed).
- `.github/workflows/scheduled-dogfood-once-3049-v2.yml` (already fired 2026-05-04, #3049 closed).

## Implementation Phases

### Phase 0 — Preconditions

3 verifications; failures halt.

- **0.1 — Version pin.** `npm view @anthropic-ai/claude-code dist-tags.latest`. Record `<version>` for Phase 1.
- **0.2 — CLI form + import-resolution verification.** Run `npx -y @anthropic-ai/claude-code@<version> --help` and confirm flags `--model claude-sonnet-4-6`, `--max-turns 80`, `--allowedTools Bash,Read,Glob,Grep`, `--prompt "..."`. Then verify the binary is resolvable from a TS module under `apps/web-platform/server/`: write a 5-line throwaway script that does `import { spawn } from "node:child_process"; spawn("claude-code", ["--version"])` from `apps/web-platform/server/__probe.ts`, run `bun run --bun apps/web-platform/server/__probe.ts` after `bun add @anthropic-ai/claude-code@<version>`, confirm exit 0. Discard the probe.
- **0.3 — SIGTERM propagates to grandchildren under `detached: true`** (Kieran P0-3). `bash -c 'claude-code --prompt "Run: bash -c \"sleep 300\"" --max-turns 1 & PID=$!; sleep 2; kill -TERM -- -$PID; wait $PID; pgrep -P $PID || echo "no orphans"'`. Confirm zero orphan grandchildren within ~5s. If claude-code's SIGTERM handling is unclean, Phase 2 will need explicit SIGKILL escalation (we ship the escalation defensively regardless).

### Phase 1 — Add claude-code dependency

```bash
# In apps/web-platform/
bun add @anthropic-ai/claude-code@<version-from-0.1>
```

Commit `package.json` + `bun.lock` + (if relevant) `package-lock.json` regeneration in the same atomic change.

### Phase 2 — Inngest cron function: `cron-daily-triage.ts`

```typescript
// TR9 PR-1 (#3948) — proof-of-pattern Inngest cron function.
//
// ADR-033 invariants (binding all cron-*.ts files):
//   I1 — claude-code spawned INSIDE step.run (replay memoization)
//   I2 — Operator ANTHROPIC_API_KEY only; never founder BYOK.
//        Inverse-assertion sentinel at test/server/cron-no-byok-lease-sweep.test.ts.
//   I3 — AbortSignal aborts at 60min (matches old GHA timeout; preserves 0.75 peer ratio for 80-turn budget)
//   I4 — claude-code installed via apps/web-platform/package.json dep; resolved through node_modules
//   I5 — Deterministic stdout/exit-code capture: step.run returns {ok, exitCode, signal, abortedByTimeout, durationMs}
//   I6 — Event payloads emitted by cron-*.ts MUST carry actor: "platform" (forward-looking; this function emits none).
//
// NAME NOTE: Sentry monitor slug stays "scheduled-daily-triage" for historical
// check-in continuity (PR-F shipped it; rename would orphan history with no
// upside). Inngest function id is "cron-daily-triage" (convention).
//
// Source: extracted from .github/workflows/scheduled-daily-triage.yml (deleted in same commit).

import { spawn } from "node:child_process";
import { inngest } from "@/server/inngest/client";
import { reportSilentFallback } from "@/server/observability";

// Inlined verbatim from .github/workflows/scheduled-daily-triage.yml lines 86-141.
// Editing this prompt and the --allowedTools / --max-turns flags below MUST happen
// together — they form a single agent contract (a permissive tool list with a
// restrictive prompt is silent agent failure).
const DAILY_TRIAGE_PROMPT = String.raw`
You are an issue triage agent. Your job is to classify open GitHub issues
and apply labels. You must NOT write code, create PRs, or modify any files.

## Instructions

1. List open issues: ${"`"}gh issue list --state open --limit 200 --json number,title,labels --jq 'map(select((.labels | map(.name) | index("ux-audit") | not) and (.labels | map(.name) | any(startswith("agent:")) | not)))'${"`"}
   The --jq filter excludes agent-authored issues (stream tag
   "ux-audit" and any "agent:*" label).
2. Filter: skip any issue that already has a label starting with "priority/".
   These have already been triaged.
3. For each remaining issue:
   a. Read the full issue: ${"`"}gh issue view <number>${"`"}
   b. Classify it across 3 dimensions using the rubric below.
   c. Apply labels: ${"`"}gh issue edit <number> --add-label "priority/<p>","type/<t>","domain/<d>"${"`"}
   d. Add a comment explaining your reasoning, IDEMPOTENTLY (search-before-add):
      first run ${"`"}gh issue view <number> --json comments --jq '.comments[].body'${"`"} and skip
      this issue if any existing comment starts with "**Automated Triage**".
   e. Otherwise: ${"`"}gh issue comment <number> --body "**Automated Triage**\n..."${"`"}
4. After processing all issues, output a summary table.

[... rest of prompt verbatim — full text in same file ...]
`;

const CLAUDE_CODE_ARGS = [
  "--model", "claude-sonnet-4-6",
  "--max-turns", "80",
  "--allowedTools", "Bash,Read,Glob,Grep",
];

// 60min — matches old GHA timeout; preserves 0.75 min/turn peer ratio for 80-turn budget
// (Architecture-strategist F2: 55min was below the 0.75 floor → partial-run silent-failure).
const MAX_TURN_DURATION_MS = 60 * 60 * 1000;

interface SpawnResult {
  ok: boolean;
  exitCode: number | null;
  signal: NodeJS.Signals | null;
  abortedByTimeout: boolean;
  durationMs: number;
}

export async function cronDailyTriageHandler({ step, logger }: {
  step: { run<T>(name: string, cb: () => Promise<T>): Promise<T> };
  logger: { info: (...a: unknown[]) => void; warn: (...a: unknown[]) => void; error: (...a: unknown[]) => void };
}): Promise<{ exitCode: number | null; durationMs: number; abortedByTimeout: boolean }> {

  const result = await step.run("claude-eval", async (): Promise<SpawnResult> => {
    const ac = new AbortController();
    const timer = setTimeout(() => ac.abort(), MAX_TURN_DURATION_MS);
    const startedAt = Date.now();
    let abortedByTimeout = false;
    ac.signal.addEventListener("abort", () => { abortedByTimeout = true; }, { once: true });

    try {
      return await new Promise<SpawnResult>((res) => {
        const child = spawn(
          "claude-code",
          [...CLAUDE_CODE_ARGS, "--prompt", DAILY_TRIAGE_PROMPT],
          {
            detached: true,                     // Kieran P0-3: own process group so SIGTERM propagates
            stdio: ["ignore", "inherit", "inherit"],
            env: { ...process.env },            // inherits ANTHROPIC_API_KEY from Doppler (operator key only — I2)
          },
        );

        // Process-group SIGTERM-then-SIGKILL escalation. ac.signal abort sends SIGTERM
        // to the leader (-pid); if the process group is still alive after 5s, escalate.
        ac.signal.addEventListener("abort", () => {
          try {
            if (child.pid) process.kill(-child.pid, "SIGTERM");
            setTimeout(() => {
              try { if (child.pid && !child.killed) process.kill(-child.pid, "SIGKILL"); } catch {}
            }, 5000);
          } catch (err) {
            // Process group already gone — fine.
          }
        }, { once: true });

        child.on("exit", (exitCode, signal) => {
          res({
            ok: exitCode === 0,
            exitCode,
            signal,
            abortedByTimeout,
            durationMs: Date.now() - startedAt,
          });
        });
        child.on("error", (err) => {
          reportSilentFallback(err, {
            feature: "cron-claude-eval",
            op: "child_process.spawn",
            message: "claude-code spawn failed",
            extra: { fn: "cron-daily-triage" },
          });
          res({ ok: false, exitCode: -1, signal: null, abortedByTimeout, durationMs: Date.now() - startedAt });
        });
      });
    } finally {
      clearTimeout(timer);
    }
  });

  // Sentry heartbeat — single end-of-job POST per 2026-05-18-vendor-cron-heartbeat-silent-fail-pattern.md.
  // Sentry slug "scheduled-daily-triage" matches the existing monitor resource (continuity preserved).
  await step.run("sentry-heartbeat", async () => {
    const domain = process.env.SENTRY_INGEST_DOMAIN;
    const projectId = process.env.SENTRY_PROJECT_ID;
    const publicKey = process.env.SENTRY_PUBLIC_KEY;
    if (!domain || !projectId || !publicKey) return;  // dev/local: silent skip
    const status = result.ok ? "ok" : "error";
    const url = `https://${domain}/api/${projectId}/cron/scheduled-daily-triage/${publicKey}/?status=${status}`;
    try {
      await fetch(url, { method: "POST", signal: AbortSignal.timeout(10_000) });
    } catch (err) {
      reportSilentFallback(err as Error, {
        feature: "cron-sentry-heartbeat",
        op: "fetch",
        message: "Sentry Crons heartbeat POST failed",
        extra: { fn: "cron-daily-triage", status },
      });
    }
  });

  return { exitCode: result.exitCode, durationMs: result.durationMs, abortedByTimeout: result.abortedByTimeout };
}

// Registration: BOTH cron (scheduled) AND event (manual-retry) triggers.
// Operator manual retry: `inngest send cron/daily-triage.manual-trigger` (spec-flow AC37).
// account-scope concurrency: limit to 1 simultaneous cron-* invocation across the Hetzner node
// (Architecture F7: prevents OOM under cron-* fan-out in PR-2..N era).
export const cronDailyTriage = inngest.createFunction(
  {
    id: "cron-daily-triage",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "0 4 * * *" },
    { event: "cron/daily-triage.manual-trigger" },
  ],
  cronDailyTriageHandler as unknown as Parameters<typeof inngest.createFunction>[2],
);
```

### Phase 3 — Register function in route.ts

```typescript
import { cfoOnPaymentFailed } from "@/server/inngest/functions/cfo-on-payment-failed";
import { cronDailyTriage } from "@/server/inngest/functions/cron-daily-triage";

export const { GET, POST, PUT } = serve({
  client: inngest,
  functions: [cfoOnPaymentFailed, cronDailyTriage],
  signingKey: SIGNING_KEY ?? "build-phase-placeholder",
});
```

### Phase 4 — Sentinel sweep inverse-assertion (extracted, hardened)

**Step 4a — `byok-audit-writer-sweep.test.ts`:**

```typescript
// Export the regex constants for re-use by the inverse-assertion sentinel.
export const LEASE_CALL_RE = /\brunWithByokLease\s*\(/;
export const ALIAS_IMPORT_RE = /import\s*\{[^}]*\brunWithByokLease\s+as\s+\w+/;
// PR-1 (TR9) Architecture F6: catches bare named imports without immediate call site.
//   import { runWithByokLease } from "..."; const fn = runWithByokLease; fn(...);
// Subsumes ALIAS_IMPORT_RE structurally; keep both for explicit named-failure messages.
export const BARE_IMPORT_RE = /import\s*\{[^}]*\brunWithByokLease\b[^}]*\}/;
```

(Rest of file unchanged; existing tests still consume `LEASE_CALL_RE`/`ALIAS_IMPORT_RE` at module-local scope as before.)

**Step 4b — `cron-no-byok-lease-sweep.test.ts` (new file):**

```typescript
// ADR-033 I2 enforcement: cron-* Inngest functions consume OPERATOR ANTHROPIC_API_KEY
// only — never founder BYOK. This file is the inverse of byok-audit-writer-sweep.test.ts:
// that file requires runWithByokLease at BYOK-write paths; this file forbids it at
// cron-* paths. Two simple files, one invariant each (Kieran P1-2).
import { readFileSync } from "node:fs";
import { sync as globSync } from "fast-glob";
import { describe, expect, it } from "vitest";
import {
  LEASE_CALL_RE,
  ALIAS_IMPORT_RE,
  BARE_IMPORT_RE,
} from "./byok-audit-writer-sweep.test";

describe("cron-*.ts MUST NOT import or call runWithByokLease (ADR-033 I2)", () => {
  const cronFiles = globSync("server/inngest/functions/cron-*.ts", {
    ignore: ["**/*.test.ts", "**/*.d.ts"],
  });

  it("at least one cron-* function exists (sentinel sanity)", () => {
    expect(cronFiles.length).toBeGreaterThan(0);
  });

  for (const file of cronFiles) {
    it(`${file}: MUST NOT import or call runWithByokLease`, () => {
      const src = readFileSync(file, "utf8")
        .replace(/\/\*[\s\S]*?\*\//g, "")
        .replace(/\/\/.*$/gm, "");
      // expect.soft (vitest) reports which shape caught the violation.
      expect.soft(LEASE_CALL_RE.test(src), "direct call site").toBe(false);
      expect.soft(ALIAS_IMPORT_RE.test(src), "aliased import").toBe(false);
      expect.soft(BARE_IMPORT_RE.test(src), "bare named import").toBe(false);
    });
  }
});

describe("inverse sentinel — fixture proofs", () => {
  it("catches a direct call site", () => {
    const violating = `import { runWithByokLease } from "@/server/byok-lease";\nawait runWithByokLease(uid, async () => {});`;
    expect(LEASE_CALL_RE.test(violating)).toBe(true);
  });
  it("catches an aliased import", () => {
    const violating = `import { runWithByokLease as withByokSession } from "@/server/byok-lease";`;
    expect(ALIAS_IMPORT_RE.test(violating)).toBe(true);
  });
  it("catches a bare named import without immediate call (Architecture F6)", () => {
    const violating = `import { runWithByokLease } from "@/server/byok-lease";\nconst fn = runWithByokLease;\nfn(uid, async () => {});`;
    expect(BARE_IMPORT_RE.test(violating)).toBe(true);
  });
  it("passes a compliant cron-* file (operator-key only)", () => {
    const compliant = `import { spawn } from "node:child_process";\nspawn("claude-code", ["--prompt", "..."], { env: { ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY } });`;
    expect(LEASE_CALL_RE.test(compliant)).toBe(false);
    expect(ALIAS_IMPORT_RE.test(compliant)).toBe(false);
    expect(BARE_IMPORT_RE.test(compliant)).toBe(false);
  });
});
```

### Phase 5 — Sentry monitor margin adjustment

Edit `apps/web-platform/infra/sentry/cron-monitors.tf` line 94 (existing `scheduled_daily_triage` resource):

- `checkin_margin_minutes`: `180` → `30` (Inngest has minimal jitter vs GHA's degraded sub-hourly cadence).
- Resource id, `name`, and Sentry slug UNCHANGED. No destroy-create, no historical orphan.

`apply-sentry-infra.yml` auto-applies on merge — no manual operator step.

### Phase 6 — Tests

Create `apps/web-platform/test/server/inngest/cron-daily-triage.test.ts` following the `cfo-on-payment-failed.test.ts` pattern (mock `step`, mock `child_process.spawn`, mock fetch):

- **T1 — Happy path.** Mock spawn exits 0; mock Sentry fetch returns 200. Handler returns `{exitCode: 0, abortedByTimeout: false}`; Sentry POST called once with `?status=ok`.
- **T2 — Spawn error.** Mock spawn fires `child.on("error")` with `ENOENT`. `reportSilentFallback` called; Sentry POST called with `?status=error`.
- **T3 — AbortSignal at 60min.** `vi.useFakeTimers()`; mock spawn never exits; advance clock past 60min; assert `process.kill(-pid, "SIGTERM")` called; advance another 5s; assert `process.kill(-pid, "SIGKILL")` called; result.abortedByTimeout === true.
- **T4 — Sentry env vars missing.** Unset `SENTRY_INGEST_DOMAIN`; assert no fetch call; step still resolves (no throw).
- **T5 — Event-trigger manual-retry path.** Construct handler with the same args; assert it executes regardless of whether invocation came from cron or event.

(NOTE: ledger-related T2 / T6 from v1 are CUT — no ledger.)

### Phase 7 — GHA YAML deletions (same commit as Phase 2 file lands)

`git rm`:
- `.github/workflows/scheduled-daily-triage.yml`
- `.github/workflows/scheduled-dogfood-once-3049.yml`
- `.github/workflows/scheduled-dogfood-once-3049-v2.yml`

### Phase 8 — Umbrella body update + ADR amend + principles entry

**Step 8a — `gh issue edit 3948 --body-file -`** appending:

```markdown
## Umbrella Children (11 follow-up migrations)

PR-1 establishes the proof-of-pattern. Subsequent migrations file their own
issues at migration-start time so each carries fresh side-effect-class + CLO-bucket
context. Checkbox each on PR merge.

- [ ] scheduled-followthrough-sweeper (`0 18 * * *`, comment-writer, CLO bucket ii)
- [ ] scheduled-bug-fixer (`0 6 * * *`, pr-creator, bucket i)
- [ ] scheduled-strategy-review (`0 8 * * 1`, issue-creator shell-only, bucket i)
- [ ] scheduled-roadmap-review (`0 9 * * 1`, issue-creator + pr-creator, bucket i)
- [ ] scheduled-community-monitor (`0 8 * * *`, kb-writer + pr-creator, bucket ii)
- [ ] scheduled-ux-audit (`0 9 1 * *`, read-only artifact, bucket i)
- [ ] scheduled-legal-audit (`0 11 1 1,4,7,10 *`, issue-creator, bucket i)
- [ ] scheduled-competitive-analysis (`0 9 1 * *`, kb-writer + pr-creator + issue-creator, bucket i)
- [ ] scheduled-compound-promote (`0 0 * * 0`, pr-creator direct-ANTHROPIC_API_KEY, bucket i)
- [ ] scheduled-agent-native-audit (`0 9 15 * *`, issue-creator, bucket i)
- [ ] scheduled-follow-through (`0 9 * * 1-5`, comment-writer + label-mutator, bucket ii)
- [ ] scheduled-gdpr-gate-preflight-eval-50d (CONVERT to inngest.send-triggered one-shot)
```

**Step 8b — ADR-033 inline amendments:**

- I3: AbortSignal aborts at **60 min** (was 55 min; raised per Architecture-strategist F2 to preserve 0.75 peer ratio). Rollback-headroom rationale dropped — Inngest replays do not depend on spawn ceiling. `[Refined 2026-05-18 post PR-1 plan review]`.
- I4: claude-code installed as `apps/web-platform/package.json` dependency, NOT cloud-init. Ships via existing deploy pipeline; version pin lives in `package.json` + lockfile. `[Refined 2026-05-18 post PR-1 plan review]`.

**Step 8c — Principles register (`knowledge-base/engineering/architecture/principles-register.md`):**

Add row:

```markdown
| AP-014 | Platform-loop / per-founder cohabitation boundary | active | Source: ADR-033 I2, I6. Enforcement: build-time sentinel (cron-no-byok-lease-sweep.test.ts) + runtime code-comment. Related NFR: NFR-014 (security boundary). |
```

**Step 8d — `spec.md` retract block** at top of "Functional Requirements":

```markdown
**[Revised post plan-review 2026-05-18]** FR1, FR2, FR7, TR4, TR8 (cron_run_ledger
ledger primitive) are RETRACTED. 5-agent plan-review converged that Inngest's
native cron + step.run memoization is the load-bearing primitive; ledger
duplicated it at lower fidelity AND blocked legitimate operator manual-retry
for 24h AND its plpgsql cast chain would throw at runtime. See
knowledge-base/project/plans/2026-05-18-feat-pr-1-migrate-scheduled-daily-triage-to-inngest-cron-tr9-plan.md
§Research Reconciliation for the full rationale.
```

### Phase 9 — Pre-merge verification

- `bun run typecheck` — clean.
- `bun run test:ci` — all suites pass: new `cron-daily-triage.test.ts`, new `cron-no-byok-lease-sweep.test.ts`, existing PR-F suites.
- `terraform fmt -check` on `apps/web-platform/infra/sentry/`.
- Verify PR #3985 (existing draft) body uses `Refs #3948` (umbrella stays open), user-impact-reviewer sign-off carry-forward summarized.

### Phase 10 — Post-merge (automation)

- **Deploy pipeline** ships the new code + `@anthropic-ai/claude-code` via existing `npm install` step on Hetzner deploy. Inngest worker restarts → registers `cronDailyTriage` automatically. No SSH, no IaC dance.
- **Sentry IaC** auto-applies via `apply-sentry-infra.yml` (margin adjustment only).
- **Operator verification step (cheap, automatable):** within ~5 min of deploy, send `inngest send cron/daily-triage.manual-trigger` (event-trigger path added in Phase 2) to validate end-to-end before waiting for the next 04:00 UTC fire. Verifiable via Inngest dashboard + Sentry monitor heartbeat + `gh issue list --label "priority/p3-low"` showing newly-triaged issues.

## Acceptance Criteria

### Pre-merge (PR ready)

- **AC1.** `apps/web-platform/package.json` lists `@anthropic-ai/claude-code` at the version pin from Phase 0.1. `bun.lock` / `package-lock.json` updated.
- **AC2.** `cron-daily-triage.ts` exports `cronDailyTriage` registered with `concurrency: [{scope:"fn",limit:1}, {scope:"account",key:'"cron-platform"',limit:1}], retries: 1` AND `[{cron:"0 4 * * *"},{event:"cron/daily-triage.manual-trigger"}]` trigger array.
- **AC3.** claude-eval `step.run` spawns `claude-code` with `detached: true`; AbortSignal at 60 min; abort handler sends `process.kill(-child.pid, "SIGTERM")` then `SIGKILL` after 5s. Step returns `{ok, exitCode, signal, abortedByTimeout, durationMs}` (deterministic memoization shape).
- **AC4.** Sentry heartbeat fires single end-of-job POST to slug `scheduled-daily-triage` (continuity preserved) with `status=ok|error` based on `result.ok`. Skips silently if Sentry env vars missing.
- **AC5.** `cron-no-byok-lease-sweep.test.ts` exists at `apps/web-platform/test/server/`. Three regexes asserted (LEASE_CALL_RE, ALIAS_IMPORT_RE, BARE_IMPORT_RE — last is new per Architecture F6). Fixture proofs cover bare-import + alias + direct-call shapes. `byok-audit-writer-sweep.test.ts` exports the three constants.
- **AC6.** Vitest suite covers T1-T5 (Phase 6). T3 specifically asserts SIGKILL escalation after 5s on AbortSignal abort.
- **AC7.** `cron-monitors.tf` resource `scheduled_daily_triage` `checkin_margin_minutes` is 30. Resource id + name UNCHANGED. `terraform fmt -check` clean.
- **AC8.** No `Sentry.logger`, `sentry.logs`, `sentry_log_alert`, `sentry_log_monitor`, `log-condition` patterns introduced (acknowledges open #3829). Verifiable via `git diff main --name-only | xargs grep -lE 'sentry_log_(alert|monitor)|Sentry\.logger|sentry\.logs|log-condition' || echo "clean"`.
- **AC9.** GHA YAML deletions in same commit: `scheduled-daily-triage.yml`, `scheduled-dogfood-once-3049.yml`, `scheduled-dogfood-once-3049-v2.yml`.
- **AC10.** #3948 body updated with `## Umbrella Children` section (11 checkbox items, markdown shape). ADR-033 I3 + I4 annotated with `[Refined 2026-05-18]` blocks. AP-014 added to principles register. `spec.md` retract block prepended to FRs.
- **AC11.** PR #3985 body uses `Refs #3948` (NOT `Closes` — umbrella stays open). PR description carries the user-impact-reviewer threshold (`single-user incident`) + the three failure vectors enumerated.
- **AC12.** `bun run typecheck` clean; `bun run test:ci` passes.

### Post-merge (automation-driven)

- **AC13.** Deploy pipeline ships claude-code with `bun.lock`-pinned version; Hetzner Inngest worker restarts and registers `cronDailyTriage` (visible in `/api/inngest` PUT response or Inngest dev dashboard).
- **AC14.** Sentry monitor `scheduled-daily-triage` `checkin_margin_minutes` updated to 30 via `apply-sentry-infra.yml`.
- **AC15.** Manual-trigger verification: `inngest send cron/daily-triage.manual-trigger` within 5 min of deploy completion produces a Sentry `status=ok` heartbeat AND labels ≥1 open untriaged issue. This is the AC23-equivalent (Spec-flow's prompt-idempotency verification) — the inlined prompt enforces search-before-add (Step 3d of the prompt body); the manual trigger validates end-to-end before the next 04:00 fire.

## Domain Review

**Domains relevant:** Engineering (CTO), Legal (CLO), Product (CPO). Marketing/Sales/Finance/Support/Operations: not relevant.

### Engineering (CTO) — Status: reviewed (brainstorm carry-forward + plan-review reconciliation)

Substrate gap resolved via ADR-033 (`child_process.spawn`). v2 reconciles 4 P0s surfaced at plan-review: drops the ledger (production-bug + 24h-trap), fixes AbortSignal grandchild propagation, inlines prompt (esbuild bundle correctness), simplifies install to package.json dep. Substrate primitives binding PR-2..N: cron+event dual trigger, account-scoped concurrency, 60-min AbortSignal with SIGTERM→SIGKILL escalation, sentinel inverse-assertion (3 regexes).

### Product (CPO) — Status: reviewed (brainstorm carry-forward)

PR-1 ships BEFORE PR-G (#3947) per K15. #3948 reshapes to umbrella with checkbox children (not pre-filed issues — DHH P0-3 / Code-Simplicity P1). Operator override on PR-1 target validated by v2 cuts: the "harder target = full primitive stack in one review" framing holds AND the v2 plan is materially simpler than v1 (~700 → ~450 lines) without sacrificing primitive coverage.

### Legal (CLO) — Status: reviewed (brainstorm carry-forward)

Bucket (i) operator-PII only — daily-triage operates on operator's own repo backlog. No Article 30 amendment. `hr-autonomous-loop-skill-api-budget-disclosure` NO-OP for platform-loop crons (operator key only). No key rotation required at migration.

### Product/UX Gate — Tier: NONE

PR-1 is server-side. No new `components/**/*.tsx`, no `app/**/page.tsx`, no `app/**/layout.tsx`.

## User-Brand Impact

**Brand-survival threshold:** `single-user incident` (carry-forward from brainstorm Phase 0.1). `requires_cpo_signoff: true`.

**If this lands broken, the user experiences:**
- **Silent loop failure** — operator's daily-triage stops firing without notice. Mitigated by AC4 (Sentry heartbeat at end-of-`step.run` per today's silent-fail learning) + AC14 (margin of 30 min triggers missed-check-in alert) + AC15 (post-deploy event-triggered verification before first cron fire).
- **Wrong-actor action (forward-looking)** — future refactor accidentally couples a cron-* function to per-founder context. Mitigated by AC5 inverse-assertion sentinel (3 regexes catching direct/alias/bare-import shapes) + AP-014 principles register entry making the boundary discoverable.
- **Replay-cost runaway** — Inngest replays `step.run` containing claude-code spawn. Mitigated by AC3 deterministic capture (memoization fires on identical `{ok, exitCode, signal, abortedByTimeout, durationMs}` shape) + the prompt's idempotency directives (search-before-add for comments).

**If this leaks, the user's [credentials / agent reputation] is exposed via:**
- **Operator `ANTHROPIC_API_KEY`** — inherited from Doppler-injected env (no new secret); existing `pino` log scrubbing (PR-D #3883 + PR-E sentinel sweep) applies.
- **Cross-tenant agent action (forward-looking)** — AC5 sentinel + AP-014 register entry close the boundary.

**Plan-time gates:**
- `user-impact-reviewer` MUST sign off at PR review (single-user-incident threshold).
- preflight Check 6 fires on `apps/web-platform/server/inngest/functions/cron-*.ts`, `apps/web-platform/test/server/{byok-audit-writer-sweep,cron-no-byok-lease-sweep}.test.ts`, `apps/web-platform/infra/sentry/cron-monitors.tf`, `apps/web-platform/package.json`.

## Risks

1. **`claude-code` SIGTERM handling under `detached: true`.** Phase 0.3 explicitly tests grandchild orphan behavior. If non-clean, SIGKILL escalation at +5s is the safety net.
2. **Stdout determinism for step.run memoization.** Function captures only `{ok, exitCode, signal, abortedByTimeout, durationMs}` — not stdout — so memoization shape is deterministic. AC3 + T3 catch regressions.
3. **Inngest dual-trigger surface (cron + event) interaction.** Both triggers route to the same handler; `account`-scope concurrency `"cron-platform"` limits in-flight to 1 across both paths. If operator manually triggers during a scheduled fire, the event invocation queues until the cron completes (or fails fast on concurrency rejection — verify behavior at Phase 0.2 or T5).
4. **Deploy-pipeline timing race** (Architecture F11). If the deploy lands after 04:00 UTC, the next-day fire is the first real run. Mitigation: AC15 manual-trigger verification within 5 min of deploy catches this immediately.
5. **GHA YAML deletion + Inngest registration ordering.** Same-commit shape; Inngest registers on next Hetzner Node restart (triggered by the same deploy). If deploy fails, revert restores the YAML.
6. **claude-code grandchildren (bash, gh) under SIGKILL.** If grandchildren hold file locks or partial git state, SIGKILL may leave stale `.git/index.lock` or partial label/comment writes. Mitigation: agent prompt's idempotency directives (search-before-add) tolerate replay; bash/gh hold no persistent state per invocation.

## Test Strategy

- **Vitest unit:** `cron-daily-triage.test.ts` T1-T5; mocked spawn + fetch.
- **Source-grep CI:** `cron-no-byok-lease-sweep.test.ts` fires on every commit (extracted, hardened).
- **Terraform:** `terraform fmt -check` + `terraform validate` on `apps/web-platform/infra/sentry/`.
- **Manual verification post-deploy:** `inngest send` event-trigger validates the full path before relying on cron schedule.
- No TENANT_INTEGRATION_TEST gate; PR-1 has no live tenant data.

## References

- **Issue:** [#3948](https://github.com/jikig-ai/soleur/issues/3948) — TR9 umbrella (PR-1 implements proof-of-pattern; 11 children tracked via checkbox list on issue body).
- **Sibling open:** [#3947](https://github.com/jikig-ai/soleur/issues/3947) — PR-G. TR9 ships BEFORE per brainstorm K15.
- **Productize candidate:** [#3990](https://github.com/jikig-ai/soleur/issues/3990) — `/soleur:migrate-cron-to-inngest` skill.
- **Brainstorm:** `knowledge-base/project/brainstorms/2026-05-18-tr9-agent-loop-crons-inngest-migration-brainstorm.md`.
- **Spec:** `knowledge-base/project/specs/feat-agent-loop-crons-inngest-tr9/spec.md` (FR1/FR2/FR7/TR4/TR8 retracted in Phase 8d).
- **ADR-033** (binding invariants; amended in Phase 8b): `knowledge-base/engineering/architecture/decisions/ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn.md`.
- **ADR-030** (substrate parent): `knowledge-base/engineering/architecture/decisions/ADR-030-inngest-as-durable-trigger-layer.md`.
- **Predecessor PR (merged):** [#3940](https://github.com/jikig-ai/soleur/pull/3940) — PR-F.
- **Draft PR (this work):** [#3985](https://github.com/jikig-ai/soleur/pull/3985).
- **5-agent plan-review reconciliation:** session transcripts captured at the brainstorm timestamp; converging cuts documented in `## v1 → v2 changes` above.
- **AGENTS.md rules touched:** `hr-weigh-every-decision-against-target-user-impact`, `hr-write-boundary-sentinel-sweep-all-write-sites`, `hr-gdpr-gate-on-regulated-data-surfaces` (Phase 0.7 invocation), `cq-silent-fallback-must-mirror-to-sentry`, `cq-nextjs-route-files-http-only-exports`.
- **Learnings carried forward:**
  - `2026-05-18-vendor-cron-heartbeat-silent-fail-pattern.md` (end-of-job heartbeat shape).
  - `2026-05-18-brainstorm-verify-issue-body-enumerations-against-live-state.md` (today's compound).
  - `2026-05-16-migration-mandates-must-have-wired-call-sites-in-same-pr.md` (same-commit GHA deletion).
  - `2026-03-20-claude-code-action-max-turns-budget.md` (0.75 peer ratio — drove AbortSignal raise to 60min).
