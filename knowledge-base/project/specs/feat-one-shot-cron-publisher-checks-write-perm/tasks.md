---
plan: knowledge-base/project/plans/2026-06-12-fix-cron-content-publisher-checks-write-perm-plan.md
lane: cross-domain
status: ready
---

# Tasks — fix: GitHub App `checks: write` for cron synthetic check-runs

Derived from `2026-06-12-fix-cron-content-publisher-checks-write-perm-plan.md`.
Root cause: `apps/web-platform/infra/github-app-manifest.json:21` declares `"checks": "read"`;
`POST /repos/{owner}/{repo}/check-runs` (`_cron-safe-commit.ts:683`) requires `checks: write`.
Two-plane fix: manifest code change (this PR) + live GitHub-UI re-acceptance (post-merge, Playwright MCP).

## Phase 0 — Preconditions (verify, do not edit)

- [ ] 0.1 Confirm `github-app-manifest.json:21` currently reads `"checks": "read"`.
- [ ] 0.2 Confirm parity-test value-assertion convention at `github-app-manifest-parity.test.ts:110-121`
      (`administration`/`issues` === `"write"`) and that `EXPECTED_PERMISSION_KEYS` already contains
      `"checks"` (line 64) — value-only change, no key-set edit.
- [ ] 0.3 Confirm drift-suppress mechanism: `cron-github-app-drift-guard.ts:70` (`SUPPRESS_FILE`),
      `:235-275` (ISO-8601 + 30-day cap), `:407` (global short-circuit before both diff sites).

## Phase 1 — Manifest fix (root cause)

- [ ] 1.1 Edit `apps/web-platform/infra/github-app-manifest.json`: `"checks": "read"` → `"checks": "write"`
      (keep alphabetical key order — sits between `administration` and `contents`).

## Phase 2 — Regression test (RED → GREEN)

- [ ] 2.1 In `apps/web-platform/test/github-app-manifest-parity.test.ts`, add a value-assertion test
      (next to the `issues === "write"` test at line 121):
      `test("default_permissions.checks === 'write' (synthetic check-run POST requires it)", …)`
      asserting `m.default_permissions?.checks` toBe `"write"`.
- [ ] 2.2 Confirm RED-before (test fails against unedited manifest) / GREEN-after (passes after 1.1):
      `cd apps/web-platform && ./node_modules/.bin/vitest run test/github-app-manifest-parity.test.ts`.

## Phase 3 — Drift-suppress sequencing file

- [ ] 3.1 Create `apps/web-platform/infra/MANIFEST_DRIFT_SUPPRESS_UNTIL` with a single strict ISO-8601
      UTC timestamp set at create-time to expected **deploy** time + ~24h (NOT merge — guard reads the
      container filesystem; window opens at deploy; ≤ 30-day cap). The literal in the plan is an example.
- [ ] 3.2 Do NOT reorder to "re-accept first" — the drift diff (`manifest-diff.ts:79-110`) fires
      `permission_drift` symmetrically; the suppress file is required regardless of order.

## Phase 4 — Pre-ship verification

- [ ] 4.1 Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [ ] 4.2 Full parity suite green (`vitest run test/github-app-manifest-parity.test.ts`); exact-key-set
      test (line 175) still passes with no `EXPECTED_PERMISSION_KEYS` edit.
- [ ] 4.3 PR body uses `Ref #<tracking-issue>` (NOT `Closes`) — fix completes only after post-merge
      re-acceptance (ops-remediation `Ref` rule, `wg-use-closes-n-in-pr-body-not-title-to`).

## Phase 5 — Post-merge live-grant (automated, in-session via Playwright MCP)

- [ ] 5.1 Widen the App's Checks permission to Read & write at
      `https://github.com/organizations/jikig-ai/settings/apps/soleur-ai/permissions`, save.
- [ ] 5.2 Accept the installation permission-update banner at
      `https://github.com/organizations/jikig-ai/settings/installations/122213433`
      ("Review request" → "Accept new permissions"). Per runbook github-app-provisioning.md Step 2.1.
- [ ] 5.3 HARD GATE: verify grant via
      `gh api /orgs/jikig-ai/installations --jq '.installations[] | select(.app_slug=="soleur-ai") | .permissions.checks'`
      returns `write`. Closure depends on THIS read, not Playwright's apparent success.
- [ ] 5.4 Trigger `cron/github-app-drift-guard.manual-trigger`; confirm green (no `installation_permission_drift`).
- [ ] 5.5 Delete `MANIFEST_DRIFT_SUPPRESS_UNTIL` (delete-commit) once 5.3 + 5.4 pass — a stale file
      blinds the guard globally; deletion is close-gating.
- [ ] 5.6 After next `cron-content-publisher` run (or `cron/content-publisher.manual-trigger`), confirm
      Sentry op `safe-commit-check-run-failed` no longer fires and check-runs post `completed/success`.
- [ ] 5.7 `gh issue close <N>` only after 5.3 + 5.4 + 5.5 all pass.
