---
module: web-platform
date: 2026-04-19
problem_type: integration_issue
component: vitest_integration_test
severity: medium
tags: [mu1, github-app, doppler, vitest, describe-skipif, integration-test]
symptoms:
  - "AC-2 (provisionWorkspaceWithRepo clones fixture) was deferred until a public fixture repo existed"
  - "Partial Doppler secret set could silently skip the test"
---

# Learning: MU1 AC-2 fixture-repo gate design (#2605)

## Problem

MU1 AC-2 asserts that signup-time `provisionWorkspaceWithRepo` clones the
user's connected GitHub repo. Prior to #2605 the test was a placeholder
comment because there was no public fixture repo + App install to clone
against. The gating design had to:

- Run only when both fixture env vars are present (AC-1 already gates on
  `MU1_INTEGRATION=1`; AC-2 is orthogonal — needs `soleur-ai` App creds +
  a public clone target).
- Fail loud if Doppler drifts to partial-set (exactly one of the two
  fixture vars present) — otherwise `describe.skipIf` masks the
  misconfig and the AC silently regresses.
- Defend against the value-shape traps that `Number.isInteger` alone
  misses (`Number("1e20")` and `Number("42.0")` both pass the coerced
  `isInteger` check but are not valid installation ids).
- Defend against argument-injection via `repoUrl` (git treats URLs
  starting with `-` as positional flags, e.g. `--upload-pack=<cmd>`).
- Detect fixture-repo drift (extra top-level entries) before the clone
  asserts `readdirSync` shape.

## Solution

Four orthogonal gates on top of a single `describe.skipIf` block:

1. **Partial-env canary** (module-collection time, not test time):

   ```ts
   const AC2_HAS_REPO_URL = !!process.env.MU1_FIXTURE_REPO_URL;
   const AC2_HAS_INSTALL_ID = !!process.env.MU1_FIXTURE_INSTALLATION_ID;
   if (AC2_HAS_REPO_URL !== AC2_HAS_INSTALL_ID) {
     throw new Error("MU1 AC-2 fixture env vars partially set — ...");
   }
   ```

   Throwing at module load means an operator who only set one of the two
   gets a hard failure at collection time, not a silent skip.

2. **Regex gate BEFORE `Number()` coercion:**

   ```ts
   const INSTALLATION_ID_RE = /^[1-9][0-9]{0,9}$/;
   expect(INSTALLATION_ID_RE.test(rawId.trim())).toBe(true);
   const installationId = Number(rawId);
   expect(installationId).toBeGreaterThan(0);
   ```

   Regex on the raw string (NOT on the coerced number) rejects `"1e20"`,
   `"42.0"`, `" 42"`, and scientific-notation forms that silently pass
   `Number.isInteger(Number("1e20"))`.

3. **URL-shape assertion (argument-injection defense):**

   ```ts
   expect(repoUrl.startsWith("https://github.com/")).toBe(true);
   ```

   Prevents a future Doppler entry like `--upload-pack=cmd https://...`
   from being treated as a positional flag when git parses it.

4. **Fixture-drift canary via exact `readdirSync` equality:**

   ```ts
   const OVERLAY_ENTRIES = new Set([".claude", "plugins"]);
   const fixtureEntries = readdirSync(ws)
     .filter((e) => !OVERLAY_ENTRIES.has(e))
     .sort();
   expect(fixtureEntries).toEqual([".git", "README.md", "knowledge-base"]);
   ```

   If `jikig-ai/mu1-fixture` ever grows a `package.json`, `Dockerfile`,
   or `.github/workflows/`, the test fails at the assertion line,
   naming the drifted set.

## Key Insight

**AC-2 test gates must fail loud on misconfig, not quietly skip.**
`describe.skipIf` is the right primitive for "optional integration test",
but it must be paired with a partial-env canary that throws at module
load — otherwise any env-copy bug produces a false green. Likewise, any
string-to-int coercion must regex-gate the raw string BEFORE `Number()`,
because `Number.isInteger` operates on the coerced float and accepts
scientific notation.

## Security Baseline Trade-off

The plan originally expected `repository_selection = "selected"` with
`mu1-fixture` as a narrow pinned repo (AC-B). In practice, the
`soleur-ai` App installation on `jikig-ai` is `repository_selection =
"all"` (id `122213433`) because production `provisionWorkspaceWithRepo`
uses the same App for other jikig-ai-owned repos — narrowing would
regress unrelated workflows.

Commit `68b6f33e` accepted this trade-off and updated the runbook's
Security Baseline to document:

- Installation id (verified via `gh api /orgs/jikig-ai/installations`)
- Expected `repository_selection: all`
- Dev-Doppler readers can mint tokens for the App; blast radius is
  bounded by the App's org-scope (just `jikig-ai`)
- Re-evaluate if dev-Doppler access widens beyond the founder team

## Prevention

- When wiring a gated integration test, always add a partial-env canary
  at module-collection time — `describe.skipIf` alone is a silent-skip
  hazard under Doppler/env drift.
- Regex-gate any env-derived int before `Number()` coercion.
- Assert URL shape on any env-derived repo URL passed to `git clone`.
- For fixture repos with frozen content, pin the top-level entry set
  with `toEqual([...])` (not `toContain`) so drift fails loud.
- When the Security Baseline of an App install differs from a plan's
  stated AC, update the runbook and commit the correction before
  wiring the test — so the AC-G post-ship check matches reality.

## Session Errors

None detected. Session was a clean resumption of a pre-committed
branch after a terminal crash.

## Components Invoked

- `soleur:go` → `soleur:work` → `soleur:ship` → `soleur:compound`
- `gh api`, `doppler run`, `vitest`, `markdownlint-cli2`

## Cross-References

- Plan: `knowledge-base/project/plans/2026-04-19-ops-mu1-fixture-repo-and-ac2-test-plan.md`
- Runbook: `knowledge-base/engineering/ops/runbooks/mu1-signup-workspace-verification.md`
- Test: `apps/web-platform/test/mu1-integration.test.ts`
- Issue: [#2605](https://github.com/jikig-ai/soleur/issues/2605)
- Related rule: `cq-destructive-prod-tests-allowlist` (shared `assertSyntheticEmail` helper)
