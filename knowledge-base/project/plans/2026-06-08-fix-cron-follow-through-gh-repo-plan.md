---
title: "fix(cron): scheduled-follow-through (+daily-triage) buildSpawnEnv missing GH_REPO"
type: fix
issue: 5010
branch: feat-one-shot-5010-followthrough-gh-repo
lane: cross-domain
date: 2026-06-08
brand_survival_threshold: aggregate pattern
---

# 🐛 fix(cron): `buildSpawnEnv` missing `GH_REPO` — `gh` fails in `/app` (no `.git`)

## Enhancement Summary

**Deepened on:** 2026-06-08
**Sections enhanced:** Acceptance Criteria (AC5 mirror target pinned), Sharp Edges (substrate-guard
path + symbol-redefine guard corrected), Research Insights (added).

### Key Improvements
1. **AC5 mirror target pinned** — verified daily-triage's existing test `"mints an installation token
   first … into the claude spawn"` (~L175) captures `spawnEnv = spawnSpy.mock.calls[0][2].env`; the
   `GH_REPO` assertion attaches there (single spawn, no gh-label/execFileSync → one assertion).
2. **Substrate-import guard path corrected** — actual guard is `test/server/cron-substrate-imports.test.ts:11`
   (`SHARED_IMPORT_RE`), NOT `test/server/inngest/…`. Added the `:66` symbol-redefine guard note:
   `REPO_OWNER`/`REPO_NAME` must be IMPORTED, never locally re-declared.
3. **No hidden env-shape landmine** — grepped both test files: no `Object.keys`/`toHaveLength`/`toEqual({…})`
   exact-key-count or allowlist-negative assertion on the spawn env → adding `GH_REPO` breaks nothing.

### New Considerations Discovered
- The `:66` substrate guard ("does not locally redefine extracted `_cron-shared` symbols") actively
  *requires* the import-not-redefine approach — it would FAIL a `const REPO_OWNER = "jikig-ai"` local copy.
  This reinforces the fix and removes the temptation to inline the constant.
- `GH_REPO` is a novel literal in this codebase (0 prior occurrences in `apps/web-platform/server|test`).
  The `gh` env-var contract is upstream-documented AND empirically verified live (`GH_REPO=cli/cli gh
  repo view` → `cli/cli` from an unrelated CWD). No in-repo precedent needed — it's a standard `gh` env var.

### Research Insights

**Best Practices:**
- `gh` resolves the target repo in this precedence: `--repo` flag > `GH_REPO` env > git-remote of CWD.
  Setting `GH_REPO` is the canonical clone-free way to pin a repo for a `gh` process that runs outside a
  checkout (the exact `/app`-container situation). Confirmed against `gh` 2.92.0.
- Mirror the existing `buildSpawnEnv` allowlist *comment* update with the code change — the comment is the
  human-readable Layer-2 contract; drift between comment and body is a documented reviewer trap.

**Edge Cases:**
- Token-scope edge: if the minted installation token lacks the target repo, `GH_REPO` is set but `gh`
  still 4xxs. Detection is already wired: follow-through's `validate-predicates` catch → `reportSilentFallback`
  → Sentry; daily-triage surfaces it as agent-level gh failure → monitor error check-in. No new handling needed.
- Replay-safety: `buildSpawnEnv` is pure (no `step.run`), called fresh per spawn — adding a static field is
  idempotent across Inngest replay by construction.

**References:**
- `gh help environment` (GH_REPO) — verified live, `gh` 2.92.0.
- Learning `knowledge-base/project/learnings/2026-06-02-inngest-dispatches-gha-for-credential-heavy-crons.md`
  (substrate-import gotcha #1: relative `./_cron-shared` only).
- Sibling-pair precedent: PR #4733 (`fix(inngest): follow-through-monitor & daily-triage crons mint
  GitHub App token …`) — established the two crons are fixed together for gh-auth-class defects.

## Overview

The Inngest cron `cron-follow-through-monitor` posts a Sentry **error check-in every
weekday run** (recurring since 2026-05-27; Sentry `WEB-PLATFORM-W`, symptom monitor
`WEB-PLATFORM-2C`). Root cause:

```
Command failed: gh issue list --label follow-through --state open --json number,title,body --limit 100
failed to run git: fatal: not a git repository (or any of the parent directories): .git
```

`buildSpawnEnv(installationToken)` in `cron-follow-through-monitor.ts` (lines 268-276)
sets `GH_TOKEN` but **not `GH_REPO`**. The function runs `gh` from the prod Next.js
container CWD `/app`, which is not a git checkout (unlike the audit/bug-fixer crons,
this monitor never clones a repo — it only touches issues). `gh` authenticates via the
token but cannot resolve the target repo, so it falls back to `git`-remote detection and
fails. This breaks **both** the Node-process `execFileSync` prefetch (L433) **and** every
in-agent `gh issue view/edit/comment/close` call (claude-eval spawn, L480).

Regressed when the cron migrated from a checked-out GitHub Actions workflow to the
Inngest `/app` container (TR9 PR-2). The workflow ran inside a repo checkout where `gh`
derived the repo from the git remote; the Inngest function does not.

**Fix:** add `GH_REPO: \`${REPO_OWNER}/${REPO_NAME}\`` (→ `jikig-ai/soleur`, both already
exported from `_cron-shared.ts`) to `buildSpawnEnv`. `gh` honors `GH_REPO` as the default
repo — no clone needed. Verified empirically (see Research Reconciliation R1).

**Scope decision — fold in `cron-daily-triage`:** `cron-daily-triage.ts` has the
**identical latent defect** (same `buildSpawnEnv` GH_TOKEN-only body, no clone, no `cwd`,
active `{ cron: "0 4 * * *" }`, own Sentry monitor `scheduled-daily-triage`). The two
crons were already fixed as a sibling pair for the *previous* gh-auth class in PR #4733
(`fix(inngest): follow-through-monitor & daily-triage crons mint GitHub App token…`).
`GH_REPO` is the direct sibling follow-up. No existing issue tracks the daily-triage gap.
Folding it in is one extra line + one mirrored test, closes the whole class in one PR,
and avoids a near-certain "why did you fix only one of the pair?" follow-up. See
`## Open Code-Review Overlap` and Research Reconciliation R5.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue #5010 / proposed fix) | Reality (verified) | Plan response |
| --- | --- | --- |
| R1: `gh` honors `GH_REPO` to set default repo | **Verified empirically**: `GH_REPO=cli/cli gh repo view --json nameWithOwner -q .nameWithOwner` returned `cli/cli` from an unrelated CWD (the soleur worktree), proving `GH_REPO` overrides repo resolution independent of CWD/git-remote. `gh` 2.92.0. Mechanism confirmed, not assumed. | Use `GH_REPO`; no fallback needed. |
| R2: `buildSpawnEnv` has 0 `GH_REPO` occurrences | Confirmed: `grep -c GH_REPO` = 0 in the file. Body sets only `PATH/HOME/NODE_ENV/ANTHROPIC_API_KEY/GH_TOKEN` (L269-275). | Add the field. |
| R3: `REPO_OWNER`/`REPO_NAME` "already exported from `_cron-shared`" | Exported at `_cron-shared.ts:10-11` (`"jikig-ai"`/`"soleur"`), **but NOT currently imported** into `cron-follow-through-monitor.ts` (import block L77-81 pulls only `mintInstallationToken`, `postSentryHeartbeat`, `HandlerArgs`). | Extend the `./_cron-shared` import to add `REPO_OWNER`, `REPO_NAME`. |
| R4: failure surface is `execFileSync` prefetch at "~line 433" | Confirmed at L433-438 (`["issue","list",...]`, `env: buildSpawnEnv(...)`). Also two `spawn` sites: ensure-labels L329, claude-eval L480 — all share `buildSpawnEnv`. | Single fix at `buildSpawnEnv` covers all three call sites. |
| R5: issue scoped to follow-through only | `cron-daily-triage.ts` has the identical defect (buildSpawnEnv L177-185, GH_TOKEN-only, 0 clone/cwd, in-agent `gh issue` spawn at L217, active cron, slug `scheduled-daily-triage`). Daily-triage has **no** Node-process `execFileSync` (in-agent `gh` only) so its failure is the agent silently failing every `gh` op rather than a hard error check-in — but the root cause and fix are identical. | **Fold in** (see Overview + Open Code-Review Overlap). |
| R6: "Add a source-regex test" | The existing test file already has a **behavioral** harness (T7, L250-290) that captures `execEnv`/`claudeEnv`/`ghEnv` and asserts `GH_TOKEN`. A behavioral `GH_REPO` assertion mirroring T7 is strictly stronger than a source-regex. | Add T8 mirroring T7 (assert `GH_REPO === "jikig-ai/soleur"` on all three env captures). Daily-triage: mirror its existing env-capture test if present, else add the equivalent. |

## User-Brand Impact

**If this lands broken, the user experiences:** follow-through issues (external
dependencies the founder is waiting on) never get their SLA tracked, auto-closed, or
`@`-mention escalated — they silently rot open. Daily triage labels never get applied, so
the issue backlog the founder relies on for prioritization goes stale. Both are
*operator-dogfood* surfaces (this is Soleur monitoring its own repo), not end-user-tenant
surfaces.

**If this leaks, the user's data/workflow/money is exposed via:** N/A — no data surface.
The change widens the spawn-env allowlist by exactly one non-secret constant
(`jikig-ai/soleur`, a public repo slug). The Layer-2 allowlist guarantee (only
`PATH/HOME/NODE_ENV/ANTHROPIC_API_KEY/GH_TOKEN/GH_REPO` reach the subprocess) is preserved;
`GH_REPO` is a public repo coordinate, not a credential.

**Brand-survival threshold:** aggregate pattern. (No single follow-through/triage miss is a
brand incident; the *sustained* monitor-red + stale-backlog pattern is the cost. This is
operator-internal automation, not a tenant data path → not `single-user incident`.)
`threshold: aggregate pattern, reason: operator-internal cron automation, no tenant data surface, allowlist widened by one public non-secret constant.`

## Acceptance Criteria

### Pre-merge (PR)

- [x] AC1: `buildSpawnEnv` in `cron-follow-through-monitor.ts` returns an env object whose
  `GH_REPO` equals `\`${REPO_OWNER}/${REPO_NAME}\`` (→ `jikig-ai/soleur`). Verify:
  `grep -nE 'GH_REPO:\s*\`\$\{REPO_OWNER\}/\$\{REPO_NAME\}\`' apps/web-platform/server/inngest/functions/cron-follow-through-monitor.ts` returns 1 line.
- [x] AC2: `cron-follow-through-monitor.ts` imports `REPO_OWNER, REPO_NAME` from `./_cron-shared`
  (relative form, per the substrate-import guard). Verify: the `from "./_cron-shared"` import
  block contains both symbols.
- [x] AC3: New behavioral test **T8** mirrors T7: drives the handler, captures the
  `execFileSync` env, the claude-eval spawn env, and the ensure-labels `gh` spawn env, and
  asserts each `.GH_REPO === "jikig-ai/soleur"`. Verify: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-follow-through-monitor.test.ts` passes.
- [ ] AC4 (fold-in): `cron-daily-triage.ts` `buildSpawnEnv` includes the same
  `GH_REPO: \`${REPO_OWNER}/${REPO_NAME}\`` and imports `REPO_OWNER, REPO_NAME` from
  `./_cron-shared`. Verify: `grep -c 'GH_REPO' apps/web-platform/server/inngest/functions/cron-daily-triage.ts` ≥ 1.
- [ ] AC5 (fold-in): a behavioral `GH_REPO` assertion is added to
  `test/server/inngest/cron-daily-triage.test.ts`. **Mirror target verified at plan time:** the
  existing test `"mints an installation token first and injects it as GH_TOKEN into the claude
  spawn"` (~L175) already captures `spawnEnv = spawnSpy.mock.calls[0][2].env` and asserts
  `spawnEnv.GH_TOKEN`. Add `expect(spawnEnv.GH_REPO).toBe("jikig-ai/soleur")` alongside it (daily-triage
  has a single claude `spawn`, no `gh` label spawn, no execFileSync — one assertion suffices). Verify
  the daily-triage suite passes.
- [x] AC6: full webplat suite green for both touched files (`cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/`). `tsc --noEmit` clean.

### Post-merge (operator/automated)

- [ ] AC7: the next weekday `0 9 * * 1-5` run of `scheduled-follow-through` posts a **healthy**
  check-in. **Automation:** verify via Sentry monitor API (read-only) — `scheduled-follow-through`
  monitor (`monitor.id 3f5e80d3-e527-442f-94c2-f3d4e65a6c61`) flips to OK and Sentry
  `WEB-PLATFORM-W` stops firing. Pull the monitor status yourself (`hr-no-dashboard-eyeball`);
  do not punt to dashboard-watching. The merge to `apps/web-platform/**` triggers
  `web-platform-release.yml` which restarts the container — no separate deploy step.
- [ ] AC8: the next `0 4 * * *` run of `scheduled-daily-triage` posts a healthy check-in
  (same read-only Sentry monitor verification).
- [ ] AC9: `gh issue close 5010` after AC7 confirms green. Use `Ref #5010` in the PR body
  (not `Closes`) only if AC7 cannot be verified pre-ready; otherwise `Closes #5010` is fine
  because the fix is verified by the test, not by a post-merge prod write. **Default: `Closes #5010`.**

## Implementation Phases

### Phase 0 — Preconditions (re-verify at /work time)

1. `grep -n 'REPO_OWNER\|REPO_NAME' apps/web-platform/server/inngest/functions/_cron-shared.ts`
   → confirm both still exported as `"jikig-ai"` / `"soleur"`.
2. Re-read the import block (L77-91) and `buildSpawnEnv` (L268-276) of
   `cron-follow-through-monitor.ts` and the equivalent in `cron-daily-triage.ts` (import block,
   `buildSpawnEnv` ~L177-185) — line numbers may drift.
3. Confirm both crons still have **zero** clone/`cwd:` (`grep -c 'clone\|cwd:' <file>` = 0). If a
   clone was added since plan-time, the `GH_REPO` fix is still correct but re-confirm the failure
   surface.

### Phase 1 — RED: failing tests first (`cq-write-failing-tests-before`)

1. Add **T8** to `cron-follow-through-monitor.test.ts`, modeled exactly on T7 (L250-290): capture
   `execEnv` (from `execFileSyncSpy.mock.calls[0][2].env`), `claudeEnv` (spawn call where `c[0] !== "gh"`),
   and each `ghEnv` (spawn calls where `c[0] === "gh"`); assert `.GH_REPO === "jikig-ai/soleur"` on all.
2. Add the mirrored `GH_REPO` assertion to `cron-daily-triage.test.ts` (find its GH_TOKEN env-capture
   test; add a sibling `GH_REPO` expectation, or a new env-capture test if absent).
3. Run both suites; confirm the new assertions FAIL (RED).

### Phase 2 — GREEN: the one-line fix per file

1. `cron-follow-through-monitor.ts`: extend the `./_cron-shared` import to add `REPO_OWNER, REPO_NAME`;
   add `GH_REPO: \`${REPO_OWNER}/${REPO_NAME}\`,` to the `buildSpawnEnv` return object. Update the
   allowlist comment (L257-259, L51-52) to list `GH_REPO` alongside the existing five vars (keep the
   Layer-2 allowlist documentation accurate).
2. `cron-daily-triage.ts`: same two edits (import + `GH_REPO` field + comment).
3. Run both suites → GREEN.

### Phase 3 — Full-suite + types

1. `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/` (covers both crons +
   substrate-import + registry-count guards).
2. `tsc --noEmit`.

## Files to Edit

- `apps/web-platform/server/inngest/functions/cron-follow-through-monitor.ts` — import +
  `buildSpawnEnv` `GH_REPO` field + allowlist comment.
- `apps/web-platform/server/inngest/functions/cron-daily-triage.ts` — same (fold-in).
- `apps/web-platform/test/server/inngest/cron-follow-through-monitor.test.ts` — T8 behavioral
  `GH_REPO` assertion.
- `apps/web-platform/test/server/inngest/cron-daily-triage.test.ts` — mirrored `GH_REPO` assertion.

## Files to Create

- None.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` body-grepped for both
`cron-follow-through-monitor` and `cron-daily-triage` → zero matches. No open scope-out
touches either file. (The daily-triage fold-in is a *new* scope decision driven by the
shared-root-cause + PR #4733 sibling-pair precedent, not a pre-existing tracked issue.)

## Domain Review

**Domains relevant:** Engineering (infra/observability cron). No Product/UX surface (no
user-facing pages or components — pure server-side cron env fix; the UI-surface glob scan
over Files-to-Edit matches nothing under `components/**`, `app/**/page.tsx`, `app/**/layout.tsx`).
No Legal/GDPR surface (no regulated-data path; widens spawn-env by one public repo slug —
not a credential, not PII). No Marketing/Finance/Growth implications.

No cross-domain implications detected beyond engineering — infrastructure/tooling fix.

## Infrastructure (IaC)

Skip — no new infrastructure. The Sentry monitor resources (`sentry_cron_monitor.scheduled_follow_through`
at `infra/sentry/cron-monitors.tf:172`; `scheduled_daily_triage` likewise) already exist; this PR
edits no `.tf`, adds no secret, vendor, or runtime process. The container restart that picks up the
fix is the existing `web-platform-release.yml` path-filtered `on.push` (a merge IS the deploy).

## Observability

```yaml
liveness_signal:
  what: existing postSentryHeartbeat({ ok: result.ok }) on the scheduled-follow-through
        monitor (slug; monitor.id 3f5e80d3-e527-442f-94c2-f3d4e65a6c61) AND the
        scheduled-daily-triage monitor.
  cadence: per cron run (follow-through 0 9 * * 1-5; daily-triage 0 4 * * *).
  alert_target: Sentry cron-monitor red on missed/error check-in (WEB-PLATFORM-2C symptom monitor).
  configured_in: cron-follow-through-monitor.ts (postSentryHeartbeat call) +
                 infra/sentry/cron-monitors.tf (monitor resources).
error_reporting:
  destination: reportSilentFallback → Sentry (already wired at validate-predicates catch, L448).
  fail_loud: yes — the validate-predicates failure already mirrors to Sentry; this fix makes the
             happy path stop hitting that catch.
failure_modes:
  - mode: gh cannot resolve repo (the bug being fixed)
    detection: Sentry error check-in on scheduled-follow-through; WEB-PLATFORM-W issue.
    alert_route: existing Sentry cron monitor → WEB-PLATFORM-2C.
  - mode: GH_REPO present but token lacks repo scope
    detection: gh 4xx in execFileSync/agent output → reportSilentFallback (follow-through) /
               agent-level gh failure (daily-triage).
    alert_route: Sentry reportSilentFallback (cron-validate-predicates) / monitor error check-in.
logs:
  where: Inngest run logs + Sentry breadcrumbs; stdout/stderr inherited by the spawned children.
  retention: Sentry default; Inngest run history.
discoverability_test:
  command: grep -l GH_REPO apps/web-platform/server/inngest/functions/cron-follow-through-monitor.ts
  expected_output: cron-follow-through-monitor.ts
  note: |
    Root-runnable local probe confirming the fix landed (GH_REPO present in the
    cron's buildSpawnEnv). Runtime confirmation is post-merge (AC7/AC8): the
    scheduled-follow-through / scheduled-daily-triage Sentry monitors flip from
    error to OK on the next weekday/daily cron run after the container restart —
    no pre-merge runtime endpoint exists (the cron only fires on schedule).
```

## Test Scenarios

- T8 (follow-through, new): `GH_REPO === "jikig-ai/soleur"` on execFileSync env + claude-eval spawn
  env + every ensure-labels `gh` spawn env. (Mirrors T7's three-env capture.)
- Daily-triage (new/mirrored): `GH_REPO === "jikig-ai/soleur"` on the agent `gh` spawn env.
- Regression: existing T1-T7 (follow-through) and the daily-triage suite still pass unchanged —
  the only env-object delta is the added `GH_REPO` key.
- Registry guards: `function-registry-count.test.ts` + `cron-substrate-imports.test.ts` unaffected
  (no new cron, relative `./_cron-shared` import preserved).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only TBD/placeholder, or omits the
  threshold will fail `deepen-plan` Phase 4.6. (Filled above — `aggregate pattern` with reason.)
- The substrate-import guard at `apps/web-platform/test/server/cron-substrate-imports.test.ts:11`
  (`SHARED_IMPORT_RE = /from\s+["']\.\/_cron-shared["']/`, verified at plan time) matches ONLY the
  relative form. Add `REPO_OWNER, REPO_NAME` to the **existing** relative `./_cron-shared` import — do
  NOT introduce an `@/server/inngest/functions/_cron-shared` alias import (it passes tsc + the fn's own
  tests but fails the substrate guard in the full webplat shard). The same test (`:66`, `"does not
  locally redefine extracted _cron-shared symbols"`) ALSO requires importing rather than re-declaring
  `REPO_OWNER`/`REPO_NAME` — so a local `const REPO_OWNER = ...` would fail; import them. See learning
  `2026-06-02-inngest-dispatches-gha-for-credential-heavy-crons.md` gotcha #1.
- Test runner is **vitest**, not bun. Invoke `./node_modules/.bin/vitest run <path>`; the package
  `test` script is `vitest`. Test files live under `test/**/*.test.ts` (node project glob in
  `vitest.config.ts:44`) — both touched test files already satisfy it.
- Keep the allowlist documentation comment (L257-259 + L51-52) in sync with the `buildSpawnEnv` body:
  when you add `GH_REPO` to the return object, list it in the "only X reach the subprocess" comment.
  An out-of-sync allowlist comment is a future-reviewer trap (the comment is the human-readable
  Layer-2 contract).
- Do NOT add `GH_REPO` to the spawn-env *override* test (T7's "minted token OVERRIDES ambient PAT")
  semantics — `GH_REPO` is a static constant, not env-derived; the override invariant is GH_TOKEN-only.
