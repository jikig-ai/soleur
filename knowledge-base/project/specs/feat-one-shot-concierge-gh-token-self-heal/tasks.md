---
feature: feat-one-shot-concierge-gh-token-self-heal
plan: knowledge-base/project/plans/2026-06-09-fix-concierge-sandbox-github-egress-gh-forbidden-plan.md
lane: cross-domain
status: pending
---

# Tasks — Concierge sandbox GitHub egress (gh `Post .../graphql: Forbidden`)

Note: no spec.md exists for this branch — `lane:` defaulted to `cross-domain`
(fail-closed). Diagnosis reframe: token plane already swept (mint consumes
`effectiveInstallationId`); the fix is the sandbox NETWORK plane
(`allowedDomains: []` denies `api.github.com` for in-sandbox `gh`).

## Phase 0 — Preconditions & probes

- [ ] 0.1 Re-grep installed `@anthropic-ai/claude-agent-sdk@0.2.85` for the two
      load-bearing semantics (`Cv8` else-branch reads flag-settings
      `allowedDomains`; `options.sandbox` rides `--settings`). Abort/re-derive
      if SDK bumped.
- [ ] 0.2 Best-effort local deny-shape probe (bwrap+socat+API key available
      only); SKIPPABLE. Pivot gate: if denied probe does not fail, STOP —
      re-diagnose per plan H-D (Sentry op:mint-gh-token +
      installation-self-heal queries) before any code.

## Phase 1 — Contract: buildAgentSandboxConfig egress option (RED→GREEN)

- [ ] 1.1 RED: egress-variant canonical-literal test + fail-closed default
      tests in `apps/web-platform/test/agent-runner-helpers.test.ts`.
- [ ] 1.2 GREEN: `GITHUB_EGRESS_DOMAINS = ["github.com", "api.github.com"]` +
      `opts?: { allowGithubEgress?: boolean }` in
      `apps/web-platform/server/agent-runner-sandbox-config.ts`.

## Phase 2 — Consumer: derive egress from ghToken (RED→GREEN)

- [ ] 2.1 RED: derivation tests (truthy → 2 hosts; absent → []; empty-string →
      []) in `apps/web-platform/test/agent-runner-query-options.test.ts`.
- [ ] 2.2 GREEN: `sandbox: buildAgentSandboxConfig(args.workspacePath,
      { allowGithubEgress: Boolean(args.ghToken) })` in
      `apps/web-platform/server/agent-runner-query-options.ts`.
- [ ] 2.3 Confirm legacy↔cc drift-guard tests stay green unchanged (legacy
      never passes ghToken → profile untouched).

## Phase 3 — Factory lockstep tests + observability (RED→GREEN)

- [ ] 3.1 RED: lockstep mismatch-case test (promotion → OWNER-install mint AND
      egress on, single test), fail-closed no-repo case, mint-throw case in
      `apps/web-platform/test/cc-dispatcher-real-factory.test.ts`.
- [ ] 3.2 GREEN: posture log `{ userId, githubEgress: Boolean(ghToken) }` in
      `apps/web-platform/server/cc-dispatcher.ts` after the mint block;
      boolean only, never the token.
- [ ] 3.3 Fix stale `CC_PATH_DISALLOWED_TOOLS` comment (~:1799) — Bash is
      sandbox-gated, not hard-blocked.
- [ ] 3.4 Sweep verify-unchanged suites:
      `test/cc-dispatcher-prefill-guard.test.ts:278,359`,
      `test/sandbox-isolation.test.ts:485`,
      `test/cc-dispatcher-real-factory.test.ts:341` — run, confirm green with
      NO edits.

## Phase 4 — Verification & ship gates

- [ ] 4.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [ ] 4.2 Targeted vitest then full suite via `./node_modules/.bin/vitest run`;
      `scripts/test-all.sh` green.
- [ ] 4.3 Record RED→GREEN evidence (new tests failing pre-change) in PR body.
- [ ] 4.4 AC5 invariance: diff shows no hunk in self-heal block /
      `findRepoOwnerInstallationForUser` / github-app.ts.
- [ ] 4.5 AC6: no `ghs_`/`gho_`/`ghp_` in new log payloads/fixture leakage
      into logs.
- [ ] 4.6 PR body: `Ref #5041` (NOT Closes); single-user-incident threshold →
      security-sentinel + user-impact-reviewer mandatory at review.
- [ ] 4.7 File deferral tracking issue: legacy leader path `buildGithubTools`
      consumes raw stored `installationId` (no self-heal) — separate surface.

## Post-merge (automated)

- [ ] 5.1 AC9: Playwright MCP against prod Concierge — `gh issue view 4826 -R
      jikig-ai/soleur` returns issue title, no Forbidden.
- [ ] 5.2 AC10: Sentry API query — zero new op:mint-gh-token failures
      post-deploy.
