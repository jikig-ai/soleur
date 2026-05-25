---
title: "TR9 PR-6 — Migrate scheduled-strategy-review to Inngest cron"
date: 2026-05-25
type: feat
status: ready-for-work
branch: feat-one-shot-inngest-strategy-review-3948
issue: 4416
umbrella: 3948
lane: single-domain
brand_survival_threshold: none
requires_cpo_signoff: false
predecessors:
  - 3985 # PR-1 daily-triage (substrate proof-of-pattern)
  - 4062 # PR-2 follow-through (closest reference; also shell-only)
  - 4227 # PR-3 oauth-probe
  - 4303 # PR-4 drift-guard
  - 4377 # PR-5 bug-fixer (most recent; ephemeral workspace + GH App token)
---

# TR9 PR-6 — Migrate `scheduled-strategy-review` to Inngest cron

## Enhancement Summary

**Deepened on:** 2026-05-25 (deepen-plan pass 1)
**Sections enhanced:** Overview, Goals, Files to Create/Edit, Implementation Phase 1, Implementation Phase 3 (CRITICAL fix), Risks
**Halt gates passed:** 4.6 (User-Brand Impact threshold=none + reason), 4.7 (Observability 5-field schema), 4.8 (no PAT-shaped variables)

### Key Improvements — load-bearing corrections from deepen-pass

1. **`gh` CLI is NOT in the Hetzner Dockerfile** — verified by reading `apps/web-platform/Dockerfile:57-59` (apt-get installs only `ca-certificates git bubblewrap socat qpdf`). The original v1 design "spawn `/bin/bash scripts/strategy-review-check.sh`" would have failed at spawn time because the script depends on `gh` for ALL operations (label create, issue list, issue create). **CORRECTION: port the script's logic to TS using `@octokit/core`** — aligns with PR-5 precedent (35 octokit invocations, zero `gh` CLI spawns) and avoids a Dockerfile change. The shell-only framing in the umbrella refers to **side-effect class** (issue-creator, no agent decision-making), not to "must remain bash." See Files to Edit + Phase 1 below.

2. **`apply-sentry-infra.yml` `-target=` list MUST be extended** — verified by reading `.github/workflows/apply-sentry-infra.yml:160-179` which enumerates 11 explicit `-target=sentry_cron_monitor.<name>` entries. **The new resource `scheduled_strategy_review` MUST be added as a 12th `-target` line**, otherwise the auto-apply workflow processes the new resource only by accident (any sibling drift would re-target everything, but a clean push touching only the new resource would NOT apply it). v1 plan missed this.

3. **Alphabetical insertion slot in `route.ts`** — verified: `cronStrategyReview` goes BETWEEN `cronOauthProbe` (line 49) and `githubOnEvent` (line 50). Pinned in Phase 2 below.

4. **TF resource alphabetical slot in `cron-monitors.tf`** — verified: NOT after `scheduled_bug_fixer` (v1 was wrong); should land alphabetically AFTER `scheduled_skill_freshness` and BEFORE `scheduled_terraform_drift`, OR appended at file end since the existing file is NOT strictly alpha-ordered (terraform_drift is at line 48, bug_fixer at 107). Match the file's pragma — appended new resources go at the end after `scheduled_gh_pages_cert_state` (line 216).

5. **`bash` IS present in `node:22-slim`** — Debian Bookworm provides bash by default. No Dockerfile change needed for that. (Only relevant if a future plan reverts to script spawn.)

6. **First TR9 child with no claude-eval AND no bash spawn** — pattern is even simpler than v1 envisioned: pure Octokit + node:fs reads of the cloned workspace. See learning capture in Phase 5.

### New Considerations Discovered

- `gh` CLI dependency is the lurking blocker — anytime a future TR9 child wants to spawn an existing bash script that uses `gh`, the same blocker applies. Either install `gh` once in the Dockerfile (single Dockerfile edit, all-future TR9 PRs benefit) OR convert each script to Octokit-TS. PR-6 chooses the latter for minimal blast radius; the Dockerfile route is filed as scope-out follow-up consideration.
- The script's `--milestone "Post-MVP / Later"` requires the milestone exists; if renamed/deleted, the script's `gh issue create` exits non-zero (script's `errors=$((errors+1))` + final exit 1). TS port replicates this via `octokit.request("POST /repos/{owner}/{repo}/issues", { milestone: <number> })` — the TS port MUST first resolve the milestone title → milestone number via `GET /repos/{owner}/{repo}/milestones?state=open`. Document as Sharp Edge.
- The script reads YAML frontmatter via `sed` — TS port uses `gray-matter` (already in `apps/web-platform/package.json` per `kb-doc-shell.tsx` precedent). Verify presence in Phase 0.
- The TS port eliminates `MAX_RUN_DURATION_MS` AbortController complexity (no spawn), but still needs a Sentry heartbeat at end-of-step.run (single-step pattern preserved) AND a Promise-level overall timeout via `AbortSignal.timeout()` on the outer step.run callback for runaway-eval safety.

## Overview

Migrate `.github/workflows/scheduled-strategy-review.yml` (weekly `0 8 * * 1`, 5-min budget, issue-creator shell-only side-effect class, CLO bucket i — operator-only) to an Inngest cron function as the next child of umbrella #3948 (TR9 group-(c) agent-loop crons).

This is the **simplest migration** in the TR9 umbrella to date: the GHA workflow runs a pure bash script (`scripts/strategy-review-check.sh`, 164 lines — YAML frontmatter parse + date math + `gh issue create`) with no `claude-code-action` invocation. **Deepen-pass correction:** the v1 plan envisioned spawning the bash script directly; the `gh` CLI is NOT in the Hetzner Dockerfile, so the script cannot run as-is. The function instead **ports the script's logic to TypeScript using `@octokit/core`** (PR-5 precedent — Octokit is the canonical TR9 GH client) — no claude-eval, no `--allowedTools`, no SSRF surface, no auto-merge gate, no `RESEND_API_KEY`, no bash spawn, no Dockerfile change.

Closest precedent: **PR-5 #4377** (`scheduled-bug-fixer`) — adopt its Octokit-based GH operations + ephemeral workspace clone pattern (the function needs FRESH `knowledge-base/` markdown from main; Hetzner has no checked-out repo at runtime). Minus PR-5's claude-eval spawn, plugin symlink, and auto-merge gate. Secondary precedent: **PR-2 #4062** (`scheduled-follow-through`) — same end-of-step.run Sentry heartbeat pattern.

Closes #4416.

## Research Reconciliation — Umbrella body vs codebase reality

The umbrella body lists `cron_run_ledger` as a binding substrate primitive. **No such table or migration exists in the codebase** (`grep -rn 'cron_run_ledger' apps/web-platform/ supabase/migrations/` returns nothing; latest migration is `066_audit_byok_use_art17_carveout.sql`). PR-1 through PR-5 all shipped without it; the inverse-assertion sweep is **`test/server/cron-no-byok-lease-sweep.test.ts`** (which globs `cron-*.ts` and auto-extends to this file). The "jitter-guard" role is served structurally by Inngest's `{ scope: "fn", limit: 1 }` + `{ scope: "account", key: '"cron-platform"', limit: 1 }` concurrency keys plus the per-function single-cron-trigger.

| Spec/umbrella claim                                 | Codebase reality                                                                 | Plan response                                                            |
| --------------------------------------------------- | -------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| `cron_run_ledger` table for jitter-guard            | Does NOT exist; no migration creates it                                          | Do NOT introduce it; rely on Inngest fn-concurrency=1 + cron-platform account-key (PR-1..PR-5 precedent) |
| All cron-* MUST not import `runWithByokLease`       | Enforced by `test/server/cron-no-byok-lease-sweep.test.ts` (globs `cron-*.ts`)   | New file is auto-swept by the existing glob — no test change required   |
| `actor: "platform"` event-payload invariant         | This handler emits NO events (downstream of any per-tenant workflow)             | I6 structurally satisfied; manual-trigger event from operator carries no payload |
| GHA-era Sentry monitor `scheduled-strategy-review`  | NO monitor exists (`grep scheduled_strategy_review cron-monitors.tf` → 0 hits)  | NEW resource (no continuity rename — same as PR-5 bug-fixer pattern)    |

## User-Brand Impact

**If this lands broken, the user experiences:** the operator (Jean) does not receive weekly strategy-doc review reminders → strategy docs go stale → product/marketing/sales decisions reference outdated artifacts. No customer-facing surface; no founder-facing surface. Operator-only.

**If this leaks, the user's [data / workflow / money] is exposed via:** N/A — the function reads operator-owned `knowledge-base/{product,marketing,sales}/` markdown and creates issues in `jikig-ai/soleur`. No founder data, no user data, no payment data.

**Brand-survival threshold:** none — operator-only ops workflow, no customer-facing surface.

**Reason:** the function reads operator-owned knowledge-base markdown and writes issues in the operator's own repo. No founder/customer data touches any code path.

## Goals

1. Inngest function `cron-strategy-review` fires weekly at `0 8 * * 1` UTC and produces the same effect as the current GHA workflow (issues created/skipped/up-to-date per strategy doc's `review_cadence`).
2. GHA workflow `.github/workflows/scheduled-strategy-review.yml` DELETED in the same commit.
3. New Sentry cron monitor `scheduled_strategy_review` in `apps/web-platform/infra/sentry/cron-monitors.tf` AND added as a 12th `-target=` entry in `.github/workflows/apply-sentry-infra.yml` (so the auto-apply workflow actually creates it on push to main).
4. The function **ports the bash script's logic to TS using `@octokit/core` + `gray-matter`** (NO bash spawn — `gh` CLI is absent from the Hetzner Dockerfile per deepen-pass verification). Ephemeral `git clone --depth=1` workspace is still used to read fresh `knowledge-base/{product,marketing,sales/battlecards}/*.md` files via `node:fs/promises`.
5. Operator can manual-trigger via Inngest event `cron/strategy-review.manual-trigger` with optional `{actor: "platform", data: {date_override: "YYYY-MM-DD"}}` payload.
6. `bun test apps/web-platform/test/server/cron-no-byok-lease-sweep.test.ts` passes (auto-extends to the new file via `cron-*.ts` glob).
7. The bash script `scripts/strategy-review-check.sh` is left intact (still callable from operator command line for ad-hoc local runs) — but the workflow file that fires it is deleted. This preserves operator-local hand-testing without runtime dependency.

## Non-Goals

- ~~Porting `strategy-review-check.sh` logic to TypeScript inline~~ — **REVERSED at deepen-pass**: the TS port IS the design now because `gh` CLI is missing from the Hetzner runtime. The bash script stays on disk for operator-local hand-testing but is no longer the cron's runtime contract.
- Installing `gh` CLI in `apps/web-platform/Dockerfile` (would unblock the v1 bash-spawn design but adds dep + apt-source + maintenance surface for one-off use case; deferred to follow-up if a future TR9 child needs `gh`).
- Introducing `cron_run_ledger` Supabase table (not in codebase; not adopted by PR-1..PR-5).
- Email notification on failure via Resend (Sentry heartbeat + `reportSilentFallback` cover the observability surface; matches PR-2/PR-5 — Resend was decorative on the GHA side).
- Tightening the strategy-review logic, adding new strategy-doc scopes, or fixing #-tracked bugs in the bash itself. **Scope is strictly substrate migration.** Bug-for-bug parity with the script (same skip patterns, same dedup behavior, same cadence map).
- Adding a plugin symlink (PR-5 needs it because claude resolves plugins from cwd; PR-6 spawns no claude).
- Migrating other TR9 children (strict K8 per-workflow scope).

## Files to Create

- `apps/web-platform/server/inngest/functions/cron-strategy-review.ts` — new Inngest function (~280-320 lines: helper TS port of the bash script's logic + Octokit calls + ephemeral workspace + Sentry heartbeat. Larger than v1's 250 estimate because the script logic is now inline; smaller than PR-5's 1226 because no claude-eval/auto-merge-gate/Resend/plugin-symlink).

## Files to Edit

- `apps/web-platform/app/api/inngest/route.ts` — add `import { cronStrategyReview } from "@/server/inngest/functions/cron-strategy-review";` AFTER the `cronOauthProbe` import line (verified: alphabetical slot). Add `cronStrategyReview,` to the `functions: [...]` array on a NEW line BETWEEN `cronOauthProbe,` (line 49) and `githubOnEvent,` (line 50) — verified via `grep -nE '^\s*cron' apps/web-platform/app/api/inngest/route.ts`.
- `apps/web-platform/infra/sentry/cron-monitors.tf` — add `sentry_cron_monitor.scheduled_strategy_review` resource. **Appended at file end** (after `scheduled_gh_pages_cert_state` at line 216) — the file's existing order is NOT strict alphabetical (terraform_drift at 48, bug_fixer at 107, daily_triage at 119), so appending matches the file's append-on-PR pragma. NEW resource — no GHA-era predecessor (`grep scheduled_strategy_review cron-monitors.tf` → 0 hits, confirmed at deepen-pass).
- **[deepen-pass addition]** `.github/workflows/apply-sentry-infra.yml` — add `-target=sentry_cron_monitor.scheduled_strategy_review \` as a 12th line in the `terraform plan` step's `-target=` list (verified at lines 169-178 of the workflow). Without this edit, the resource will land in TF state only after a sibling-resource drift forces a full re-target — the auto-apply workflow does NOT pick up new untargeted resources.
- `.github/workflows/scheduled-strategy-review.yml` — **DELETE** in the same commit per TR9 I-13 hygiene.
- `knowledge-base/project/learnings/2026-05-25-tr9-pr6-strategy-review-no-bash-spawn-octokit-port-pattern.md` — capture the deepen-pass correction (bash spawn blocked by missing `gh` CLI in runtime container; pattern: convert script to Octokit-TS rather than install gh in Dockerfile).

## Files to NOT edit (explicit non-scope)

- `scripts/strategy-review-check.sh` — Keep intact for operator-local hand-testing. No longer the cron's runtime contract; semantic-parity with the script is the TS port's contract (Sharp Edge: script-vs-TS-port drift on cadence map, skip patterns, dedup behavior).
- `apps/web-platform/Dockerfile` — Do NOT add `gh` CLI install. Defer to follow-up if a future TR9 child also needs it.
- `test/server/cron-no-byok-lease-sweep.test.ts` — Auto-extends via `cron-*.ts` glob; no edit required.
- `test/server/byok-audit-writer-sweep.test.ts` — N/A (BYOK boundary; cron-*.ts never opens a BYOK lease).
- All previously-migrated `cron-*.ts` files — independent migrations per K8.

## Implementation Phases

### Phase 0 — Preflight verification

Before authoring code, confirm the following (Bash, no edits):

1. `ls apps/web-platform/server/inngest/functions/cron-bug-fixer.ts` returns the reference file (1226 lines).
2. `gh issue view 3948 --json title,state` returns `OPEN` and umbrella title.
3. `gh issue view 4416` returns the freshly-filed child issue (this PR's `Closes` target).
4. `git ls-files | grep -E "scripts/strategy-review-check.sh|.github/workflows/scheduled-strategy-review.yml"` returns BOTH files (confirms the migration source is present in the worktree).
5. `grep -rn cron_run_ledger apps/web-platform/ supabase/migrations/` returns ZERO hits (confirms reconciliation row above).
6. `grep -n "cronFollowThroughMonitor\|cronBugFixer\|cronDailyTriage\|cronOauthProbe" apps/web-platform/app/api/inngest/route.ts` returns the 4 existing cron registrations (confirms registry edit shape AND alphabetical insertion slot for `cronStrategyReview`).
7. `awk '/^name:/ { print; exit }' .github/workflows/scheduled-strategy-review.yml` returns `name: Strategy Review` (confirms exact wording for note in PR body).
8. **[deepen-pass addition]** `grep -E '"gray-matter"' apps/web-platform/package.json` returns `"gray-matter": "^4.0.3",` (confirms YAML-frontmatter parser is available; deepen-pass verified).
9. **[deepen-pass addition]** `grep -nE 'gh|github-cli' apps/web-platform/Dockerfile` returns ZERO hits (confirms `gh` CLI is NOT installed; reason TS port is required, not bash spawn).
10. **[deepen-pass addition]** `grep -cE '^\s*-target=sentry_cron_monitor' .github/workflows/apply-sentry-infra.yml` returns `11` (current target count; will become `12` after Phase 3 edit).
11. **[deepen-pass addition]** `grep -nE 'milestone' scripts/strategy-review-check.sh` returns `150:    --milestone "Post-MVP / Later"; then` — TS port must resolve title→number via `GET /repos/{owner}/{repo}/milestones?state=open`.

### Phase 1 — Author `cron-strategy-review.ts` (TS port, no bash spawn)

**Deepen-pass design change:** the v1 plan envisioned `spawn("/bin/bash", ["scripts/strategy-review-check.sh"], ...)` inside `step.run`. Verified at deepen-pass: `gh` CLI is NOT in the Hetzner Dockerfile (`apps/web-platform/Dockerfile:57-59` installs only `ca-certificates git bubblewrap socat qpdf`), so the script's `gh label create` / `gh issue list` / `gh issue create` calls would all fail at spawn time. **Port the script to TypeScript** using `@octokit/core` + `gray-matter`:

**Structure (target ~280-320 lines):**

```typescript
// TR9 PR-6 (closes #4416) — Migrated from the GHA scheduled-strategy-review
// workflow (deleted in the same PR per TR9 I-13 hygiene). Pure TS port —
// scripts/strategy-review-check.sh remains on disk for operator-local
// hand-testing but is NOT the runtime contract (gh CLI absent from
// Hetzner Dockerfile per deepen-pass verification).
//
// ADR-033 invariants (binding all cron-*.ts files):
//   I1 — Octokit + node:fs reads called INSIDE step.run (Inngest replay
//        memoization). No child_process spawn (PR-6 is the first TR9 child
//        with no spawn at all — pure TS).
//   I2 — Operator-owned data only; never founder BYOK. Structurally
//        satisfied — no SDK call. Auto-asserted by
//        test/server/cron-no-byok-lease-sweep.test.ts via cron-*.ts glob.
//   I3 — Outer step.run carries no AbortSignal (no long-lived spawn);
//        per-Octokit-request 30s timeout via the default Octokit retry.
//        Outer wall-clock safety: Inngest function timeout (default 30s
//        per step, configurable) — we set explicit retries=1 + timeout
//        guard via Promise.race in the scan-and-create step.
//   I4 — N/A (no binary resolution; pure Node.js).
//   I5 — Deterministic step.run return shape per step: see handler.
//   I6 — Event payloads emitted by this handler MUST carry actor: "platform".
//        (This handler emits none.)
//
// NAME NOTE: Sentry monitor slug "scheduled-strategy-review" is NEW — the
// GHA predecessor had NO Sentry check-in. Resource added in same commit
// AND added to apply-sentry-infra.yml -target= allow-list (12 entries).
//
// PURE-TS PATTERN — PR-6 is the first TR9 child with ZERO spawn (no
// claude-eval, no bash script). All GH ops via Octokit; file reads via
// node:fs/promises against the cloned workspace. See learning
// 2026-05-25-tr9-pr6-strategy-review-no-bash-spawn-octokit-port-pattern.md.

import { spawn } from "node:child_process";
import { readFile, readdir, mkdtemp, rm, stat } from "node:fs/promises";
import { existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import matter from "gray-matter";
import type { Octokit } from "@octokit/core";
import { inngest } from "@/server/inngest/client";
import { createProbeOctokit } from "@/server/github/probe-octokit";
import { generateInstallationToken } from "@/server/github-app";
import { reportSilentFallback } from "@/server/observability";

const SENTRY_MONITOR_SLUG = "scheduled-strategy-review";
const SENTRY_HEARTBEAT_TIMEOUT_MS = 10_000;
const REPO_OWNER = "jikig-ai";
const REPO_NAME = "soleur";

// 10 min outer wall-clock budget. GHA's timeout-minutes was 5; 10 doubles
// it for safety against transient GitHub API retries. Past runs complete
// in <30s (≤20 strategy docs scanned, ≤5 issues created). Enforced via
// Promise.race wrapping the strategy-review step.run callback.
export const MAX_RUN_DURATION_MS = 10 * 60 * 1000;

// Installation-token lifetime floor: 10-min outer budget + 5-min headroom.
const TOKEN_MIN_LIFETIME_MS = 15 * 60 * 1000;

const SENTRY_DOMAIN_RE = /^[a-z0-9.-]+\.sentry\.io$/i;
const SENTRY_PROJECT_RE = /^\d+$/;
const SENTRY_PUBLIC_KEY_RE = /^[a-f0-9]{32}$/;

interface HandlerArgs {
  event?: { data?: { date_override?: unknown } };
  step: { run<T>(name: string, cb: () => Promise<T>): Promise<T> };
  logger: { info: (...a: unknown[]) => void; warn: (...a: unknown[]) => void; error: (...a: unknown[]) => void };
}

// ----- helpers (mint token, clone repo, TS port of strategy-review-check.sh, teardown, heartbeat) -----

async function mintInstallationToken(): Promise<string> {
  const octokit = await createProbeOctokit();
  const { data: installation } = await octokit.request(
    "GET /repos/{owner}/{repo}/installation",
    { owner: REPO_OWNER, repo: REPO_NAME },
  );
  return generateInstallationToken(installation.id, {
    minRemainingMs: TOKEN_MIN_LIFETIME_MS,
  });
}

function buildAuthenticatedCloneUrl(token: string): string {
  return `https://x-access-token:${token}@github.com/${REPO_OWNER}/${REPO_NAME}.git`;
}

function redactToken(s: string, token: string): string {
  if (!token) return s;
  return s.replaceAll(token, "[REDACTED-INSTALLATION-TOKEN]");
}

// `git clone --depth=1` into an ephemeral workspace. No plugin symlink
// (PR-6 spawns no claude). No env-injection needed (Octokit handles GH
// auth directly via the per-step octokit instance). Returns the cloned
// repo path used as the file-system root for collectStrategyFiles.
async function setupEphemeralWorkspace(token: string): Promise<{
  ephemeralRoot: string;
  repoRoot: string;
}> {
  const ephemeralRoot = await mkdtemp(join(tmpdir(), "soleur-cron-strategy-review-"));
  const repoRoot = join(ephemeralRoot, "repo");
  const cloneUrl = buildAuthenticatedCloneUrl(token);
  const cloneResult = await new Promise<{ exitCode: number | null }>((resolve) => {
    const child = spawn("git", ["clone", "--depth=1", cloneUrl, repoRoot], {
      stdio: "ignore",
    });
    child.on("exit", (exitCode) => resolve({ exitCode }));
    child.on("error", () => resolve({ exitCode: -1 }));
  });
  if (cloneResult.exitCode !== 0) {
    // DO NOT include cloneUrl — contains the token.
    throw new Error(
      `git clone failed (exit ${cloneResult.exitCode}) for ${REPO_OWNER}/${REPO_NAME}`,
    );
  }
  // Sentinel: at least one of the three strategy-doc directories must exist
  // post-clone. If all three are missing, knowledge-base/ was reorganized
  // and this cron's source-of-truth has drifted.
  const dirHits = await Promise.all(
    STRATEGY_DIRS.map(async (rel) => existsSync(join(repoRoot, rel))),
  );
  if (!dirHits.some(Boolean)) {
    throw new Error(
      `Sentinel: none of [${STRATEGY_DIRS.join(", ")}] exist after clone — knowledge-base/ may have been reorganized`,
    );
  }
  return { ephemeralRoot, repoRoot };
}

async function teardownEphemeralWorkspace(ephemeralRoot: string | null): Promise<void> {
  if (!ephemeralRoot) return;
  try {
    await rm(ephemeralRoot, { recursive: true, force: true });
  } catch (err) {
    reportSilentFallback(err, {
      feature: "cron-strategy-review",
      op: "teardown-ephemeral-workspace",
      message: "Failed to remove ephemeral workspace",
      extra: { fn: "cron-strategy-review", ephemeralRoot },
    });
  }
}

// ----- TS port of scripts/strategy-review-check.sh logic -----
//
// Faithful port preserves the script's contract:
//   - Scan knowledge-base/{product,marketing,sales/battlecards}/*.md (maxdepth 1).
//   - Parse YAML frontmatter for `review_cadence` (weekly|monthly|quarterly|biannual|annual)
//     + `last_reviewed` (YYYY-MM-DD or missing → immediately stale).
//   - Skip docs not due within 7 days.
//   - Dedup via gh issue list --label scheduled-strategy-review against title
//     "Strategy Review: {scope}/{slug}".
//   - Create issue with milestone "Post-MVP / Later" (resolve title→number first).
//   - Return counts: created / skipped / up_to_date / errors. Errors>0 → ok=false.

const REVIEW_LABEL = "scheduled-strategy-review";
const ISSUE_MILESTONE_TITLE = "Post-MVP / Later";
const STRATEGY_DIRS = ["knowledge-base/product", "knowledge-base/marketing", "knowledge-base/sales/battlecards"] as const;
const CADENCE_DAYS: Record<string, number> = {
  weekly: 7, monthly: 30, quarterly: 90, biannual: 180, annual: 365,
};

interface ReviewResult {
  created: number;
  skipped: number;
  upToDate: number;
  errors: number;
}

async function ensureReviewLabel(octokit: Octokit): Promise<void> {
  try {
    await octokit.request("POST /repos/{owner}/{repo}/labels", {
      owner: REPO_OWNER, repo: REPO_NAME,
      name: REVIEW_LABEL,
      description: "Strategy document review is overdue",
      color: "0E8A16",
    });
  } catch (err) {
    // 422 already-exists is the idempotent path; swallow.
    const status = (err as { status?: number }).status;
    if (status !== 422) {
      reportSilentFallback(err, {
        feature: "cron-strategy-review",
        op: "ensure-label",
        message: "Failed to create scheduled-strategy-review label",
        extra: { fn: "cron-strategy-review", status },
      });
    }
  }
}

async function resolveMilestoneNumber(octokit: Octokit): Promise<number | undefined> {
  // Script uses --milestone "Post-MVP / Later" (title); Octokit REST requires
  // the integer number. Resolve title→number; on miss, log + create issue
  // without milestone (script's || true fallback).
  try {
    const resp = (await octokit.request(
      "GET /repos/{owner}/{repo}/milestones",
      { owner: REPO_OWNER, repo: REPO_NAME, state: "open", per_page: 100 },
    )) as { data: Array<{ number: number; title: string }> };
    return resp.data.find((m) => m.title === ISSUE_MILESTONE_TITLE)?.number;
  } catch (err) {
    reportSilentFallback(err, {
      feature: "cron-strategy-review",
      op: "resolve-milestone",
      message: `Failed to resolve milestone "${ISSUE_MILESTONE_TITLE}"`,
      extra: { fn: "cron-strategy-review" },
    });
    return undefined;
  }
}

async function listExistingReviewIssueTitles(octokit: Octokit): Promise<Set<string>> {
  // Script: gh issue list --label LABEL --state open --json title --jq '.[].title'
  // Pagination: per_page=100; the corpus is tiny (~5-20 open per fire), but
  // guard against future growth by paginating until empty.
  const titles = new Set<string>();
  let page = 1;
  while (true) {
    const resp = (await octokit.request("GET /repos/{owner}/{repo}/issues", {
      owner: REPO_OWNER, repo: REPO_NAME,
      state: "open", labels: REVIEW_LABEL,
      per_page: 100, page,
    })) as { data: Array<{ title: string }> };
    if (resp.data.length === 0) break;
    for (const issue of resp.data) titles.add(issue.title);
    if (resp.data.length < 100) break;
    page++;
  }
  return titles;
}

async function collectStrategyFiles(repoRoot: string): Promise<string[]> {
  // Script: find <dir> -maxdepth 1 -name '*.md' -type f
  const files: string[] = [];
  for (const rel of STRATEGY_DIRS) {
    const abs = join(repoRoot, rel);
    let entries: string[] = [];
    try { entries = await readdir(abs); } catch { continue; }
    for (const name of entries) {
      if (!name.endsWith(".md")) continue;
      const fullPath = join(abs, name);
      try {
        const s = await stat(fullPath);
        if (s.isFile()) files.push(fullPath);
      } catch { /* skip */ }
    }
  }
  return files;
}

function parseISODate(s: string): number | null {
  // Script: date -d "$last_reviewed" +%s — accepts YYYY-MM-DD plus other forms.
  // Restrict TS port to strict YYYY-MM-DD per the date_override regex; if a
  // doc uses non-strict date, treat as malformed (script's "invalid
  // last_reviewed" branch). Use Date.parse for the strict shape since YYYY-
  // MM-DD parses unambiguously as UTC midnight.
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) return null;
  const t = Date.parse(`${s}T00:00:00Z`);
  return Number.isNaN(t) ? null : t;
}

async function runStrategyReview(args: {
  octokit: Octokit;
  repoRoot: string;
  todayISO: string;
  logger: HandlerArgs["logger"];
}): Promise<ReviewResult> {
  const { octokit, repoRoot, todayISO, logger } = args;
  const result: ReviewResult = { created: 0, skipped: 0, upToDate: 0, errors: 0 };

  const todayEpochMs = parseISODate(todayISO);
  if (todayEpochMs === null) {
    throw new Error(`Invalid today date: ${todayISO}`);
  }

  await ensureReviewLabel(octokit);
  const milestoneNumber = await resolveMilestoneNumber(octokit);
  const existingTitles = await listExistingReviewIssueTitles(octokit);
  const files = await collectStrategyFiles(repoRoot);
  if (files.length === 0) {
    logger.info({ fn: "cron-strategy-review" }, "No strategy documents found");
    return result;
  }

  for (const filePath of files) {
    let raw: string;
    try { raw = await readFile(filePath, "utf-8"); } catch (err) {
      reportSilentFallback(err, { feature: "cron-strategy-review", op: "read-file", message: `Failed to read ${filePath}`, extra: { fn: "cron-strategy-review", filePath } });
      result.errors++;
      continue;
    }
    const parsed = matter(raw);
    const cadence = parsed.data.review_cadence as string | undefined;
    if (!cadence) continue; // no cadence → not a tracked strategy doc

    const cadenceDays = CADENCE_DAYS[cadence];
    if (!cadenceDays) {
      logger.warn({ fn: "cron-strategy-review", filePath, cadence }, "Skipping: unknown review_cadence");
      result.errors++;
      continue;
    }

    const lastReviewed = parsed.data.last_reviewed as string | undefined;
    let daysUntil: number;
    if (!lastReviewed) {
      daysUntil = -1;
    } else {
      const lastEpochMs = parseISODate(String(lastReviewed));
      if (lastEpochMs === null) {
        logger.warn({ fn: "cron-strategy-review", filePath, lastReviewed }, "Skipping: invalid last_reviewed");
        result.errors++;
        continue;
      }
      const nextDueEpochMs = lastEpochMs + cadenceDays * 86400 * 1000;
      daysUntil = Math.floor((nextDueEpochMs - todayEpochMs) / (86400 * 1000));
    }

    if (daysUntil > 7) { result.upToDate++; continue; }

    // Script: slug=${file#knowledge-base/}; slug=${slug%.md}
    const slug = filePath.substring(filePath.indexOf("knowledge-base/") + "knowledge-base/".length).replace(/\.md$/, "");
    const expectedTitle = `Strategy Review: ${slug}`;

    if (existingTitles.has(expectedTitle)) {
      logger.info({ fn: "cron-strategy-review", slug }, "Skipping: open issue already exists");
      result.skipped++;
      continue;
    }

    const owner = parsed.data.owner as string | undefined;
    const reviewDue = lastReviewed
      ? new Date(parseISODate(lastReviewed)! + cadenceDays * 86400 * 1000).toISOString().slice(0, 10)
      : "immediately (no last_reviewed set)";

    const repoUrl = `https://github.com/${REPO_OWNER}/${REPO_NAME}`;
    const fileRel = filePath.substring(filePath.indexOf("knowledge-base/"));
    const fileLink = `${repoUrl}/blob/main/${fileRel}`;
    const body = `## Strategy Review Due: ${slug}\n\n**Review due:** ${reviewDue}\n**Last reviewed:** ${lastReviewed ?? "never"}\n**Cadence:** ${cadence}\n**Owner:** ${owner ?? "unassigned"}\n**Source:** [${fileRel}](${fileLink})\n\nWhen complete:\n- [ ] Review the document for accuracy and relevance\n- [ ] Update \`last_reviewed\` to today's date in the YAML frontmatter\n- [ ] Update \`last_updated\` if content was changed\n- [ ] Check \`depends_on\` documents for upstream changes since last review\n- [ ] Close this issue\n\n_Auto-created by the [scheduled-strategy-review Inngest function](${repoUrl}/blob/main/apps/web-platform/server/inngest/functions/cron-strategy-review.ts)._`;

    try {
      await octokit.request("POST /repos/{owner}/{repo}/issues", {
        owner: REPO_OWNER, repo: REPO_NAME,
        title: expectedTitle,
        body,
        labels: [REVIEW_LABEL],
        ...(milestoneNumber !== undefined ? { milestone: milestoneNumber } : {}),
      });
      logger.info({ fn: "cron-strategy-review", title: expectedTitle }, "Created issue");
      result.created++;
    } catch (err) {
      reportSilentFallback(err, { feature: "cron-strategy-review", op: "create-issue", message: `Failed to create issue for ${slug}`, extra: { fn: "cron-strategy-review", slug, title: expectedTitle } });
      result.errors++;
    }
  }

  return result;
}

async function postSentryHeartbeat(args: {
  ok: boolean;
  logger: HandlerArgs["logger"];
}): Promise<void> {
  // [verbatim from cron-bug-fixer.ts:postSentryHeartbeat — single end-of-step
  // POST per 2026-05-18-vendor-cron-heartbeat-silent-fail-pattern.md]
}

// ----- handler -----

export async function cronStrategyReviewHandler({
  event,
  step,
  logger,
}: HandlerArgs): Promise<{ ok: boolean; created: number; skipped: number; upToDate: number; errors: number }> {
  // 1. Parse date_override (manual-trigger event); validate YYYY-MM-DD shape.
  let dateOverride: string | undefined;
  const raw = event?.data?.date_override;
  if (raw !== undefined && raw !== null) {
    if (typeof raw !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(raw)) {
      reportSilentFallback(
        new Error(`Invalid event.data.date_override: ${JSON.stringify(raw)}`),
        {
          feature: "cron-strategy-review",
          op: "parse-event-data",
          message: "date_override must be YYYY-MM-DD",
          extra: { fn: "cron-strategy-review", rawOverride: String(raw) },
        },
      );
      await step.run("sentry-heartbeat", () => postSentryHeartbeat({ ok: false, logger }));
      return { ok: false, created: 0, skipped: 0, upToDate: 0, errors: 1 };
    }
    dateOverride = raw;
  }
  const todayISO = dateOverride ?? new Date().toISOString().slice(0, 10);

  // 2. Mint installation token (memoized across replays).
  const installationToken = await step.run("mint-installation-token", () => mintInstallationToken());

  // 3. Setup ephemeral workspace (clone --depth=1, sentinel-check KB dirs).
  let ephemeralRoot: string | null = null;
  let repoRoot: string | null = null;
  try {
    const ws = await step.run("setup-workspace", () => setupEphemeralWorkspace(installationToken));
    ephemeralRoot = ws.ephemeralRoot;
    repoRoot = ws.repoRoot;
  } catch (err) {
    const e = err as Error;
    reportSilentFallback(new Error(redactToken(e.message ?? "", installationToken)), {
      feature: "cron-strategy-review",
      op: "setup-ephemeral-workspace",
      message: "Failed to scaffold ephemeral cron workspace",
      extra: { fn: "cron-strategy-review" },
    });
    await step.run("sentry-heartbeat", () => postSentryHeartbeat({ ok: false, logger }));
    return { ok: false, created: 0, skipped: 0, upToDate: 0, errors: 1 };
  }

  // 4. Run TS port of strategy-review-check.sh (Octokit + node:fs), heartbeat.
  //    try/finally guarantees teardown.
  try {
    const result = await step.run("strategy-review-check", async (): Promise<ReviewResult & { ok: boolean }> => {
      // Construct a per-step Octokit instance authenticated with the freshly-
      // minted installation token. NOT createProbeOctokit (which uses JWT) —
      // we need installation-scoped requests for issues:write.
      const { Octokit: OctokitCtor } = await import("@octokit/core");
      const octokit = new OctokitCtor({ auth: installationToken }) as unknown as Octokit;

      // Outer wall-clock guard via Promise.race against MAX_RUN_DURATION_MS.
      const timeoutMs = MAX_RUN_DURATION_MS;
      const reviewPromise = runStrategyReview({ octokit, repoRoot: repoRoot!, todayISO, logger });
      const timeoutPromise = new Promise<never>((_, reject) =>
        setTimeout(() => reject(new Error(`strategy-review timed out after ${timeoutMs}ms`)), timeoutMs),
      );
      const review = await Promise.race([reviewPromise, timeoutPromise]);
      logger.info({ fn: "cron-strategy-review", ...review }, "strategy-review complete");
      return { ...review, ok: review.errors === 0 };
    });

    await step.run("sentry-heartbeat", () => postSentryHeartbeat({ ok: result.ok, logger }));
    return result;
  } finally {
    await teardownEphemeralWorkspace(ephemeralRoot).catch((err) =>
      reportSilentFallback(err, {
        feature: "cron-strategy-review",
        op: "teardown-ephemeral-workspace-finally",
        message: "teardownEphemeralWorkspace threw in finally block",
        extra: { fn: "cron-strategy-review", ephemeralRoot },
      }),
    );
  }
}

// ----- registration -----

export const cronStrategyReview = inngest.createFunction(
  {
    id: "cron-strategy-review",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [{ cron: "0 8 * * 1" }, { event: "cron/strategy-review.manual-trigger" }],
  cronStrategyReviewHandler as unknown as Parameters<typeof inngest.createFunction>[2],
);
```

**Key simplifications vs PR-5 `cron-bug-fixer.ts`:**

- No `resolveClaudeBin` / no `CLAUDE_CODE_FLAGS` / no claude-eval prompt / no AbortController for spawn / no SIGTERM→SIGKILL escalation / no stdout-stderr redact pipe (no child process at all). 
- No plugin symlink in `setupEphemeralWorkspace` (no claude → no plugin resolution).
- No `precreateLabels` step — `ensureReviewLabel` inside `runStrategyReview` handles the single label idempotently (same `gh label create … || true` semantic).
- No PR-detection / auto-merge-gate / notify-ops-email steps.
- 10-min outer wall-clock budget enforced via `Promise.race` (vs PR-5's per-spawn AbortController + 50-min budget for claude-eval).

**Borrowed verbatim from PR-5:**

- `mintInstallationToken` shape and `TOKEN_MIN_LIFETIME_MS` floor (smaller value, same semantics).
- `buildAuthenticatedCloneUrl` + `redactToken` (defense-in-depth — `runStrategyReview` doesn't log GH_TOKEN but the helpers are cheap insurance against future regressions).
- `setupEphemeralWorkspace` minus the plugin symlink + with KB-dir sentinel instead of script-file sentinel.
- `postSentryHeartbeat` single-step pattern (verbatim).
- `teardownEphemeralWorkspace` finally-block discipline (verbatim).

**New TS-port helpers (no PR-5 precedent — PR-6 contribution):**

- `ensureReviewLabel`, `resolveMilestoneNumber`, `listExistingReviewIssueTitles`, `collectStrategyFiles`, `parseISODate`, `runStrategyReview` — port the bash script's logic 1:1, preserving the script's exit-code semantics via `result.errors === 0 ⇒ ok: true`. Bug-for-bug parity is the contract.

### Phase 2 — Register in `/api/inngest/route.ts`

Add the import (alphabetical) between `cronOauthProbe` and `cronStrategyReview` is the natural slot — but alphabetical order with the existing list places `cronStrategyReview` AFTER `cronOauthProbe` and BEFORE `githubOnEvent` in the registry:

```typescript
import { cronStrategyReview } from "@/server/inngest/functions/cron-strategy-review";
```

And add `cronStrategyReview` to the `functions: [...]` array in alphabetical position.

### Phase 3 — Add Sentry cron monitor resource

**Deepen-pass correction:** v1 plan said "auto-creates on push to main" but the auto-apply workflow uses an EXPLICIT `-target=` allow-list (verified at `.github/workflows/apply-sentry-infra.yml:168-179`). The new resource MUST be added to that list as a 12th `-target=` line, otherwise it's silently ignored.

**Edit 3.1 — `apps/web-platform/infra/sentry/cron-monitors.tf`** — append at file end (after `scheduled_gh_pages_cert_state` at line 216; the file's existing order is NOT strictly alphabetical so append-on-PR is the established pragma):

```hcl
# TR9 PR-6 (closes #4416): Inngest-fired via
# `apps/web-platform/server/inngest/functions/cron-strategy-review.ts`. NEW
# monitor — no GHA-era predecessor (the workflow ran on GHA's runner pool
# with no Sentry check-in). The GHA scheduled-strategy-review workflow was
# deleted in the same commit per TR9 I-13 hygiene.
resource "sentry_cron_monitor" "scheduled_strategy_review" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-strategy-review"
  schedule                = { crontab = "0 8 * * 1" }
  checkin_margin_minutes  = 30
  max_runtime_minutes     = 10
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}
```

`max_runtime_minutes = 10` matches `MAX_RUN_DURATION_MS` in the TS file.

**Edit 3.2 — `.github/workflows/apply-sentry-infra.yml`** — add `scheduled_strategy_review` to the `terraform plan` step's `-target=` list (verified at lines 168-179: currently 11 entries; the v1 plan and the cron-monitors.tf file header both mistakenly imply the workflow uses a wildcard, but it does NOT). Insert AFTER `scheduled_follow_through`:

```yaml
            -target=sentry_cron_monitor.scheduled_follow_through \
            -target=sentry_cron_monitor.scheduled_strategy_review \
```

Without this edit, the new resource is created in TF state only when a sibling drift forces a full re-target — operationally invisible until then. **Sharp edge:** the v1 design's "auto-apply works without operator action" claim was wrong; deepen-pass corrected.

(Sibling-scope observation, NOT scope-creep for this PR: `scheduled_bug_fixer` is similarly absent from the `-target=` list — PR-5 has the same gap. File as separate follow-up tracking issue; do NOT fix here.)

After both edits, `cd apps/web-platform/infra/sentry && terraform init -input=false && terraform validate` exits 0 (validate doesn't care about the workflow file).

### Phase 4 — DELETE `.github/workflows/scheduled-strategy-review.yml`

In the SAME commit the Inngest function lands, `git rm .github/workflows/scheduled-strategy-review.yml`. The `scripts/strategy-review-check.sh` file STAYS — preserved for operator-local hand-testing (`bash scripts/strategy-review-check.sh` runs in the operator's terminal where `gh` IS installed). It is NO LONGER the cron's runtime contract; the TS port in `cron-strategy-review.ts` is.

### Phase 5 — Write capture learning

`knowledge-base/project/learnings/2026-05-25-tr9-pr6-strategy-review-no-bash-spawn-octokit-port-pattern.md`:

Topic: "When a TR9 cron migration's source is a pure bash script that depends on the `gh` CLI, AND the Hetzner runtime Dockerfile does NOT install `gh`, the migration MUST port the script's logic to TS using `@octokit/core` rather than `child_process.spawn` the script. Installing `gh` in the Dockerfile is a wider-blast-radius change (apt-source addition, ongoing version-pin maintenance) than the per-cron TS port for a one-off use case. Deferred-scope-out: install `gh` once if a second TR9 child needs it. Pattern: PR-6 is the first TR9 child with ZERO spawn — pure Octokit + node:fs reads of the cloned workspace. The script remains on disk for operator-local hand-testing where `gh` IS available. Verify the runtime container's CLI inventory at deepen-plan time (`grep -E 'gh|cli' apps/web-platform/Dockerfile`); v1 plans that assume vendor CLIs are present ship to /work and fail at spawn time."

Also document the apply-sentry-infra.yml `-target=` list gotcha: "The auto-apply workflow uses an EXPLICIT `-target=` allow-list (not a wildcard). New `sentry_cron_monitor` resources MUST be added to the list as a same-commit edit, otherwise they're silently ignored on push to main. Verify at deepen-plan time: `grep -cE '^\s*-target=sentry_cron_monitor' .github/workflows/apply-sentry-infra.yml` — count returns the current entries, add 1 per new resource."

### Phase 6 — Test

```bash
cd apps/web-platform
bun test test/server/cron-no-byok-lease-sweep.test.ts
# Expect: cron-strategy-review.ts auto-included in glob; passes (no runWithByokLease import).

bun run typecheck   # tsc --noEmit; route.ts import resolves; Octokit request signatures type-check.

# Sentry TF validate (no apply — apply happens on push to main per Phase 3 above):
cd apps/web-platform/infra/sentry
terraform init -input=false
terraform validate

# Workflow lint (deepen-pass addition — confirm -target= list addition didn't break YAML):
cd $(git rev-parse --show-toplevel)
actionlint .github/workflows/apply-sentry-infra.yml || true   # warn-only; many sibling lints are pre-existing

# Bug-for-bug parity hand-test (AC11):
# 1. Run bash script locally with date_override:
bash scripts/strategy-review-check.sh
# 2. Compare to TS port output via a one-shot Node REPL:
#    (full test harness is post-merge; pre-merge spot-check via reading the TS-port logic against the bash control-flow).
```

### Phase 7 — Post-merge verification (automated)

`/soleur:ship` already runs `gh workflow run apply-sentry-infra.yml` on PR merge (handles Phase 3 auto-apply). Post-merge automation:

1. `gh run list --workflow=apply-sentry-infra.yml --limit=1` confirms TF auto-apply ran on the merge SHA.
2. **Operator automation feasibility:** the next scheduled fire is the following Monday 08:00 UTC; verify-on-deploy is moot because Inngest can be hand-fired immediately via `inngest send cron/strategy-review.manual-trigger '{"actor":"platform"}'`. Post-merge ship step fires this and confirms the function landed in the registry.
3. `gh api -X POST /repos/jikig-ai/soleur/dispatches` is NOT needed — `gh workflow run` is the canonical dispatch.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** — `apps/web-platform/server/inngest/functions/cron-strategy-review.ts` exists; structure matches Phase 1 outline (handler exports `cronStrategyReview`, single-step Sentry heartbeat, Promise.race outer-budget guard, NO `child_process.spawn` other than the `git clone` in setupEphemeralWorkspace).
- [ ] **AC2** — `grep -E "^\s*(runWithByokLease|resolveKeyOwnerThenLease)\s*\(" apps/web-platform/server/inngest/functions/cron-strategy-review.ts` returns ZERO matches.
- [ ] **AC3** — `grep -E "import.*byok-lease" apps/web-platform/server/inngest/functions/cron-strategy-review.ts` returns ZERO matches.
- [ ] **AC3b** — **[deepen-pass addition]** `grep -cE 'spawn\("/bin/bash"|spawn\("bash"' apps/web-platform/server/inngest/functions/cron-strategy-review.ts` returns ZERO (no bash spawn; pure TS port). The ONLY allowed `spawn(` call is `spawn("git", ["clone", …])` in `setupEphemeralWorkspace` — assert `grep -cE 'spawn\(' apps/web-platform/server/inngest/functions/cron-strategy-review.ts` returns exactly `1`.
- [ ] **AC3c** — **[deepen-pass addition]** `grep -E '@octokit/core|gray-matter' apps/web-platform/server/inngest/functions/cron-strategy-review.ts` returns matches for BOTH (Octokit for GH API; gray-matter for YAML frontmatter parsing). `grep -E '"gray-matter"' apps/web-platform/package.json` confirms the dep is present (Phase 0 precondition).
- [ ] **AC4** — `cd apps/web-platform && bun test test/server/cron-no-byok-lease-sweep.test.ts` passes; output includes `cron-strategy-review.ts` in the `for (const file of cronFiles)` enumeration (the inverse-assertion fixture-proof tests + 6 cron-* file tests, now 7).
- [ ] **AC5** — `apps/web-platform/app/api/inngest/route.ts` contains both: `import { cronStrategyReview } from "@/server/inngest/functions/cron-strategy-review";` AND `cronStrategyReview,` inside the `functions: [...]` array between `cronOauthProbe,` and `githubOnEvent,` (alphabetical slot). `cd apps/web-platform && bun run typecheck` succeeds.
- [ ] **AC6** — `apps/web-platform/infra/sentry/cron-monitors.tf` contains a `resource "sentry_cron_monitor" "scheduled_strategy_review"` block with `name = "scheduled-strategy-review"`, `schedule = { crontab = "0 8 * * 1" }`, `max_runtime_minutes = 10`. `cd apps/web-platform/infra/sentry && terraform init -input=false && terraform validate` exits 0.
- [ ] **AC6b** — **[deepen-pass addition — CRITICAL]** `.github/workflows/apply-sentry-infra.yml` contains a `-target=sentry_cron_monitor.scheduled_strategy_review \` line in the `terraform plan` step. `grep -cE '^\s*-target=sentry_cron_monitor' .github/workflows/apply-sentry-infra.yml` returns `12` (up from `11`). Without this edit, the Sentry resource will NOT auto-apply on push to main — operationally silent failure mode.
- [ ] **AC7** — `.github/workflows/scheduled-strategy-review.yml` is DELETED. Verify atomic landing: `BASE=$(git merge-base HEAD origin/main); for sha in $(git rev-list ${BASE}..HEAD); do git show --name-status ${sha} | head -20; done` shows ALL FIVE paths landing in ONE commit: (1) NEW `apps/web-platform/server/inngest/functions/cron-strategy-review.ts`, (2) MODIFIED `apps/web-platform/app/api/inngest/route.ts`, (3) MODIFIED `apps/web-platform/infra/sentry/cron-monitors.tf`, (4) MODIFIED `.github/workflows/apply-sentry-infra.yml`, (5) DELETED `.github/workflows/scheduled-strategy-review.yml`. (PLUS the learning file in any commit on the branch.)
- [ ] **AC8** — Capture learning file exists at `knowledge-base/project/learnings/2026-05-25-tr9-pr6-strategy-review-no-bash-spawn-octokit-port-pattern.md` documenting BOTH (a) the bash-spawn-blocked-by-missing-gh pattern, AND (b) the apply-sentry-infra.yml `-target=` allow-list gotcha.
- [ ] **AC9** — PR body uses `Closes #4416` (the per-migration child issue) — NOT `Closes #3948` (the umbrella stays open until the umbrella's last child merges).
- [ ] **AC10** — `scripts/strategy-review-check.sh` is UNCHANGED (`git diff $(git merge-base HEAD origin/main) HEAD -- scripts/strategy-review-check.sh` is empty). Script remains on disk for operator-local hand-testing.
- [ ] **AC11** — **[deepen-pass addition — TS-port bug-for-bug parity smoke test]** Hand-run the TS port locally against a stub `knowledge-base/` tree with one overdue doc; assert the same issue title is generated as `bash scripts/strategy-review-check.sh DATE_OVERRIDE=YYYY-MM-DD`. Both should produce `"Strategy Review: <scope>/<slug>"` with identical body content (modulo the cron-strategy-review.ts vs scheduled-strategy-review.yml URL in the auto-creator footer).
- [ ] **AC12** — **[deepen-pass addition]** Dockerfile UNCHANGED (`git diff $(git merge-base HEAD origin/main) HEAD -- apps/web-platform/Dockerfile` is empty). `gh` CLI is NOT being installed.

### Post-merge (operator — but automated where possible)

- [ ] **AC13** — `gh run list --workflow=apply-sentry-infra.yml --limit=1 --json status,conclusion,headSha` confirms the post-merge Terraform apply completed `conclusion: success` on the merge SHA AND the apply log contains `+ create` for `sentry_cron_monitor.scheduled_strategy_review` (verifies the `-target=` allow-list edit took effect). Automation: `/soleur:ship`'s built-in `gh workflow run` triggers it; ship verification step polls until conclusion lands.
- [ ] **AC14** — Operator fires `inngest send cron/strategy-review.manual-trigger '{"actor":"platform"}'` (via `inngest-cli` on the Hetzner host); the function appears in `inngest list functions` and produces a successful run in the Inngest dashboard within 90s (the TS port's git clone + KB read takes ~5-10s; should be well under). Automation: deferred to `/soleur:ship` Phase 7 manual-trigger check (existing pattern for PR-1..PR-5).
- [ ] **AC15** — Sentry monitor `scheduled-strategy-review` appears at https://sentry.io with state `active` and a fresh `ok` check-in from AC14's manual trigger. Automation: defer to operator visual verify per `/soleur:postmerge`'s standing checklist (PR-1..PR-5 precedent accepts dashboard-eyeball as the recovery-confirmation step).
- [ ] **AC16** — Umbrella #3948 body checklist updated to mark `scheduled-strategy-review` line as done with PR-6 link. Automation: `/soleur:ship` updates the umbrella body automatically (existing PR-1..PR-5 precedent).
- [ ] **AC17** — Issue #4416 closed automatically via `Closes #4416` in PR body at merge.

## Open Code-Review Overlap

`gh issue list --label code-review --state open --json number,title,body --limit 200` — scanned for paths touching `apps/web-platform/server/inngest/functions/`, `apps/web-platform/app/api/inngest/route.ts`, `apps/web-platform/infra/sentry/cron-monitors.tf`, `scripts/strategy-review-check.sh`, `.github/workflows/scheduled-strategy-review.yml`. **None.**

## Domain Review

**Domains relevant:** CTO (cron substrate / infrastructure). CPO not relevant (no user-facing surface). CLO not relevant beyond bucket-(i) carry-forward (operator-only data flow).

### CTO

**Status:** carry-forward from PR-5 multi-agent review (which approved the ephemeral-workspace + GH App token pattern).
**Assessment:** PR-6 is a strict subset of PR-5's surface (drops claude-eval + plugin symlink + auto-merge + Resend; keeps ephemeral workspace + token + Sentry heartbeat). No new architectural primitives are introduced. The simplification surface is the absence of components, not the addition of new ones. ADR-033 invariants I1/I3/I5/I6 carry over verbatim; I2 is structurally satisfied (no SDK call); I4 is reshaped (bash binary, not claude binary — `/bin/bash` POSIX path).

No fresh agent invocations needed beyond the carry-forward.

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/sentry/cron-monitors.tf` — add `sentry_cron_monitor.scheduled_strategy_review` resource. NO new provider, NO new variable, NO new sensitive value. Reuses `var.sentry_org` + `data.sentry_project.web_platform.slug`.

### Apply path

- (c) **Auto-apply on push to main** via `.github/workflows/apply-sentry-infra.yml` (existing — added at PR-1 #3985 for sibling resources). The workflow is scoped to `-target=sentry_cron_monitor.*` per `cron-monitors.tf` line 13. Zero operator action.

### Distinctness / drift safeguards

- Sentry org/project are shared dev↔prd here (single Sentry project for web-platform per `hr-dev-prd-distinct-supabase-projects` does NOT apply to Sentry — Sentry is one project that ingests from both envs distinguished by `environment` tag). No drift hazard.

### Vendor-tier reality check

- Sentry crons monitors are unlimited on the team plan (current Soleur tier). No tier-gating needed.

## Observability

```yaml
liveness_signal:
  what: Sentry cron monitor "scheduled-strategy-review" check-in
  cadence: weekly (Mon 08:00 UTC)
  alert_target: Sentry → ops@jikigai.com via Sentry alert rule (existing for cron-monitor failures, applies to all sentry_cron_monitor resources)
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf (new resource scheduled_strategy_review) + apps/web-platform/server/inngest/functions/cron-strategy-review.ts (postSentryHeartbeat end-of-step.run POST)
error_reporting:
  destination: Sentry (via reportSilentFallback at every failure path — clone failure, spawn failure, abort-by-timeout, heartbeat-post failure, teardown failure, event-data-parse failure)
  fail_loud: true (reportSilentFallback mirrors to Sentry with feature/op/message/extra tagging per cq-silent-fallback-must-mirror-to-sentry)
failure_modes:
  - mode: "git clone --depth=1 fails (network, auth, repo deletion)"
    detection: spawn exitCode !== 0 in setupEphemeralWorkspace
    alert_route: reportSilentFallback → Sentry (feature=cron-strategy-review, op=setup-ephemeral-workspace) + step.run error + Sentry heartbeat status=error
  - mode: "bash script exits non-zero (gh API rate limit, malformed YAML in strategy doc, gh issue create failure)"
    detection: SpawnResult.ok === false in cronStrategyReviewHandler
    alert_route: Sentry heartbeat POST with status=error; stdout/stderr lines stream to logger.error (centralized via Inngest logs)
  - mode: "AbortController fires at MAX_RUN_DURATION_MS (10 min)"
    detection: SpawnResult.abortedByTimeout === true
    alert_route: reportSilentFallback (feature=cron-strategy-review, op=spawn-timeout) + Sentry heartbeat status=error
  - mode: "Installation token mint failure (GH App revoked, network)"
    detection: mintInstallationToken throws inside step.run
    alert_route: step.run replays once (retries: 1); on second failure, Sentry monitor opens issue via failure_issue_threshold=1 (no check-in lands)
  - mode: "Sentry heartbeat POST fails"
    detection: fetch error inside postSentryHeartbeat
    alert_route: reportSilentFallback (feature=cron-sentry-heartbeat) — monitor will open issue via missed check-in regardless
  - mode: "Teardown fails (stranded /tmp dir)"
    detection: rm() throws inside teardownEphemeralWorkspace
    alert_route: reportSilentFallback (feature=cron-strategy-review, op=teardown-ephemeral-workspace) — non-fatal, function still returns
logs:
  where: Inngest function logs (stdout/stderr from spawn streamed via redactToken pipe through logger.info/logger.error); Sentry events for reportSilentFallback paths
  retention: Inngest default (90 days for paid tier; check Doppler-pinned plan); Sentry default (90 days for events on team plan)
discoverability_test:
  command: 'inngest send cron/strategy-review.manual-trigger ''{"actor":"platform","data":{"date_override":"2026-05-25"}}'' && sleep 30 && curl -fsS -H "Authorization: Bearer $INNGEST_SIGNING_KEY" "https://app.inngest.com/v1/runs?function_id=cron-strategy-review&limit=1" | jq -r ''.data[0].status'''
  expected_output: '"Completed" (status from Inngest API for the most recent run of cron-strategy-review). Probe is host-agnostic — runs from any environment with $INNGEST_SIGNING_KEY in env. No remote-shell dependency.'
```

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| `git clone --depth=1` fails on Hetzner (DNS, network, GH App token expired) | Low | Medium (cron silently skipped one week) | `reportSilentFallback` → Sentry; missed Sentry check-in opens issue at `failure_issue_threshold=1` |
| TS port misses an edge case the bash script handled (e.g., date-format laxity — `date -d` accepts more shapes than `parseISODate`'s strict YYYY-MM-DD regex) | Medium | Low (strategy doc with non-strict date silently skipped + errors+=1) | AC11 bug-for-bug parity smoke test catches majority; the strict regex is intentional (rejects ambiguous shapes the bash form happened to accept by coercion); document in Sharp Edges |
| Concurrent manual-trigger fires while scheduled cron fires | Very low | Very low | `concurrency: [{ scope: "fn", limit: 1 }, { scope: "account", key: '"cron-platform"', limit: 1 }]` serializes both paths |
| Inngest replay re-executes `runStrategyReview` after partial completion (e.g., created 3 of 5 issues then crashed) | Low | Low (dedup via `listExistingReviewIssueTitles` is idempotent) | The dedup pulls the freshly-created issues into the existingTitles Set; replay finds the partially-created issues already exist and skips. Worst case: a few extra `gh issue list` page reads. |
| GH App token expires mid-execution (token has ≥15 min lifetime when minted; outer budget is 10 min) | Very low | Low | `TOKEN_MIN_LIFETIME_MS = 15 min`; mint floor exceeds outer budget by 5 min |
| `runStrategyReview` Octokit `POST /issues` rate-limited (max 5-10 issues per fire, well under 5000/h limit) | Very low | Low | `errors++` per failed create; `result.errors > 0` triggers Sentry status=error |
| **[deepen-pass]** `gray-matter` parses a frontmatter shape the bash `sed` form didn't recognize (e.g., quoted keys, nested objects) | Low | Medium (could create unexpected issues for non-strategy docs) | The `if (!cadence) continue;` guard prevents the function from acting on docs without `review_cadence`; gray-matter's parsed.data is a typed object so unexpected shapes coerce safely |
| **[deepen-pass]** Milestone "Post-MVP / Later" renamed/deleted in repo settings | Low | Low (issue created without milestone — script's `\|\| true` fallback) | `resolveMilestoneNumber` logs failure to Sentry and returns undefined; issue creation proceeds without milestone (matches script behavior) |
| **[deepen-pass]** apply-sentry-infra.yml `-target=` allow-list omission (the bug this PR's AC6b explicitly catches) | Medium without AC6b | Operationally silent — resource exists in TF but never applied | AC6b is the binding check; without it, the resource lands only via sibling-drift cascade. Sharp Edge documented for next TR9 child author. |
| Plugin-symlink hazard (PR-5 specific) | N/A | N/A | Not applicable — PR-6 spawns no claude, so no symlink is created. |

## Pattern Boundaries (PR-6 specific — DO NOT carry to PR-7..N without re-derivation)

- `MAX_RUN_DURATION_MS = 10 min` ← bound by ~5-10s typical TS-port run + 60× headroom for Octokit retries (PR-5 was 50 min for claude-eval)
- `TOKEN_MIN_LIFETIME_MS = 15 min` ← bound by `MAX_RUN_DURATION_MS + 5 min slack`
- No plugin symlink ← bound by "this cron spawns no claude / no plugin"
- No `--allowedTools` ← bound by "no claude-eval"
- No stdout-redact pipe ← bound by "no spawned child with GH_TOKEN in env" (Octokit-internal auth never leaks tokens to a log)
- `cron: "0 8 * * 1"` ← bound by the weekly-strategy-review SLA semantic (Monday morning = start of work week)
- 5-step pipeline (mint-token → setup-workspace → strategy-review-check (TS port inside step.run) → sentry-heartbeat + finally:teardown) ← bound by no-spawn pattern; PR-5's 9-step pipeline is for claude-eval crons

When the next group-(c) migration considers reusing this shape, **re-derive every boundary**:

- `scheduled-roadmap-review` (next likely child) ALSO has `bash scripts/roadmap-review-check.sh` — if that script also uses `gh`, the TS-port pattern applies. **Audit at plan time:** `grep -nE '\bgh ' scripts/roadmap-review-check.sh` to confirm.
- `scheduled-community-monitor` (kb-writer + pr-creator, bucket ii) likely needs PR-5's claude-eval shape AND ephemeral workspace AND plugin symlink — TS port would be inappropriate.
- The **deepen-pass discovery** ("gh CLI missing from Dockerfile") is a one-time cost: once any future TR9 child decides to install `gh` in the Dockerfile (single apt-source addition), PR-6's TS port becomes net-negative-LoC vs spawning the original script. Track via scope-out follow-up if a 2nd cron needs `gh`.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Filled above with `none` threshold + operator-only justification.
- The PR MUST land the GHA-YAML delete + new TS file + sentry TF resource + apply-sentry-infra.yml `-target=` addition in a SINGLE commit (per umbrella I-13 hygiene). `git log --oneline -- <yaml> <ts>` is a UNION filter (sharp edge from `2026-05-11-plan-review-caught-git-log-union-trap-and-cross-module-field-assumption`); use `git rev-list <base>..HEAD -- <paths>` + per-commit `git show --name-status` to assert atomic landing in AC7.
- Sentry monitor name `scheduled-strategy-review` is NEW (no GHA-era predecessor). Do NOT confuse with the PR-5 rename-hazard pattern (PR-1..PR-4 preserved historical slugs because the GHA-era workflows had Sentry check-ins; PR-5 and PR-6 are NEW slugs because the GHA workflows had no Sentry monitor).
- **[deepen-pass]** **The TS port and the bash script can drift** — script stays on disk for operator-local hand-testing; TS port is the runtime. Bug-for-bug parity is a CONTRACT (AC11). If a future operator updates the script (e.g., adds a new strategy directory, changes the dedup label), the TS port MUST be updated in the same commit. Suggested: add a comment at the top of `scripts/strategy-review-check.sh` reading "If you edit this file, also update `apps/web-platform/server/inngest/functions/cron-strategy-review.ts`" — out of scope for THIS PR but worth filing as a `scope-out` follow-up.
- **[deepen-pass]** **The `parseISODate` regex is STRICTER than bash `date -d`** — bash's `date -d "Mon May 25 2026"` parses; `parseISODate("Mon May 25 2026")` returns null and the doc is silently skipped with `errors++`. This is intentional (rejects ambiguous shapes) but is a divergence from the script's behavior. AC11's parity test should pin this divergence with a fixture: a strategy doc with `last_reviewed: "2026/05/25"` (slash form) — bash accepts (returns epoch), TS port rejects (treats as invalid). Document the divergence in the function header.
- **[deepen-pass]** **`apply-sentry-infra.yml` `-target=` list is NOT a wildcard** — every new `sentry_cron_monitor` resource MUST add itself to the list as a same-commit edit (AC6b enforces). Sibling-omission analysis: `scheduled_bug_fixer` is currently missing from the list (PR-5 had the same gap); file follow-up tracking issue post-merge if not already filed.
- ⚠️ The TS port's `octokit.request("POST /repos/{owner}/{repo}/issues")` may fail with HTTP 422 if the milestone "Post-MVP / Later" has been renamed/deleted. `resolveMilestoneNumber` falls back to `undefined` (issue created without milestone), matching the script's `|| true` semantics. If milestone failures become noisy post-merge, file a follow-up issue.
- The TS port reads `knowledge-base/{product,marketing,sales/battlecards}/` — if a future KB reorganization moves strategy docs (e.g., to `knowledge-base/strategy/`), the cron silently scans no files. Mitigation in design: the `setupEphemeralWorkspace` sentinel asserts AT LEAST ONE of the three directories exists post-clone (throws otherwise → Sentry status=error). Sharp edge: if ANY ONE directory exists but is empty of strategy docs, the function reports `created=0, errors=0` (ok). KB reorg that empties all three triggers the sentinel; KB reorg that keeps one as legacy dir but empties strategy content silently passes.
- **[deepen-pass]** The script's exit code is no longer the cron's contract (TS port replaces it). The contract is now `result.errors === 0 ⇒ ok: true`. Document this divergence in the function header for future maintainers.
- **[deepen-pass]** **Sibling-PR drift:** `scheduled_bug_fixer` is also missing from `apply-sentry-infra.yml`'s `-target=` list — verified at deepen-pass. PR-5 has the same operational silence as PR-6's v1 design would have had. NOT a scope-creep concern for this PR but worth filing as a follow-up `chore` tracking issue: "Add scheduled_bug_fixer to apply-sentry-infra.yml -target= list (TR9 PR-5 follow-up)".

## Test Strategy

- `apps/web-platform/test/server/cron-no-byok-lease-sweep.test.ts` — auto-extends to `cron-strategy-review.ts` via existing glob `server/inngest/functions/cron-*.ts`. No edit required. Validates: no `runWithByokLease` direct call, no aliased import, no bare named import, no dynamic import bypass.
- TypeScript compile via `bun run typecheck` validates the `inngest.createFunction` signature, handler args type, Octokit request types, and import resolution in `route.ts`.
- Terraform validate (`terraform init -input=false && terraform validate`) confirms the new `sentry_cron_monitor` resource block parses against the `jianyuan/sentry` provider schema.
- **[deepen-pass addition]** Workflow lint via `actionlint .github/workflows/apply-sentry-infra.yml` confirms the `-target=` list edit doesn't break YAML.
- **[deepen-pass addition]** Bug-for-bug parity hand-test (AC11): run `bash scripts/strategy-review-check.sh` locally with `DATE_OVERRIDE=2026-06-01` against the current `knowledge-base/` AND a Node.js REPL invocation of `runStrategyReview()` with a stub Octokit (record-replay or in-process mock). Compare the two outputs (issue titles, body content, counts) — they MUST match modulo the footer URL.
- Live smoke-test post-merge (AC14): `inngest send cron/strategy-review.manual-trigger '{"actor":"platform"}'` from the Hetzner inngest-cli host → confirm a successful run in the Inngest dashboard within 90s + Sentry heartbeat lands + (if any docs are due) 1-N new GitHub issues appear with label `scheduled-strategy-review`.

## Rollback

If the new function misbehaves in production (e.g., creates duplicate issues, fails repeatedly):

1. Disable the cron schedule by amending `cron-strategy-review.ts` triggers to `[{ event: "cron/strategy-review.manual-trigger" }]` only (remove the `{ cron: "0 8 * * 1" }` entry); deploy.
2. Re-introduce `.github/workflows/scheduled-strategy-review.yml` from git history (`git show <pre-merge-sha>:.github/workflows/scheduled-strategy-review.yml`). The script `scripts/strategy-review-check.sh` is intact (it never moved); GHA workflow can resume firing the script directly.
3. Remove the `sentry_cron_monitor.scheduled_strategy_review` resource from TF AND remove its `-target=` line from `apply-sentry-infra.yml` (the inverse of Phase 3 edits).
4. Delete the cron function file `cron-strategy-review.ts` and remove its registration from `route.ts`.

No data is mutated by the cron beyond GitHub issue creation (which is independently reversible via `gh issue close --reason "not planned"`). The migration is reversible without data-loss risk.

**[deepen-pass observation]** Reversing the TS port back to bash-spawn would require installing `gh` in the Dockerfile (the original v1 design's hidden dependency). If a rollback is needed, the simpler revert is to re-enable the GHA workflow (which already has `gh` in its runner image) rather than rewire the cron substrate.

## PR Body Template

```
TR9 PR-6 — migrate scheduled-strategy-review to Inngest cron.

Closes #4416. (Umbrella #3948 child; update umbrella checklist on merge.)

## Summary
- Adds `cron-strategy-review.ts` Inngest function (~300 LoC). Pure TS port of the
  bash script — Octokit + node:fs + gray-matter. NO claude-eval, NO bash spawn.
- DELETES `.github/workflows/scheduled-strategy-review.yml` (TR9 I-13 hygiene).
  `scripts/strategy-review-check.sh` stays on disk for operator-local hand-testing.
- Adds `sentry_cron_monitor.scheduled_strategy_review` resource (NEW, no GHA-era
  predecessor) AND adds it to the apply-sentry-infra.yml `-target=` list (was 11,
  now 12 entries).
- Reuses PR-5 ephemeral-workspace + GH App installation token + Sentry heartbeat
  pattern; drops plugin symlink, claude-eval spawn, auto-merge gate, Resend.

## Pattern note (deepen-plan correction)
First TR9 child with ZERO spawn other than `git clone`. Deepen-plan caught that
`gh` CLI is NOT installed in the Hetzner Dockerfile, so v1 plan's bash-spawn
design would have failed at runtime. Ported the script's logic to TS via
@octokit/core + gray-matter. See learning 2026-05-25-tr9-pr6-strategy-review-no-bash-spawn-octokit-port-pattern.md.

## Test plan
- [ ] bun test test/server/cron-no-byok-lease-sweep.test.ts (auto-extends to new cron-*.ts)
- [ ] bun run typecheck
- [ ] terraform validate apps/web-platform/infra/sentry
- [ ] Hand-test: TS port output matches `bash scripts/strategy-review-check.sh` for the same date_override (bug-for-bug parity)
- [ ] Post-merge: `gh run list --workflow=apply-sentry-infra.yml --limit=1` confirms apply created `sentry_cron_monitor.scheduled_strategy_review`
- [ ] Post-merge: `inngest send cron/strategy-review.manual-trigger '{"actor":"platform"}'` → Inngest dashboard shows successful run within 90s

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```
