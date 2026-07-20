---
title: "Tasks — pin the CLAUDE_PLUGIN_ROOT server-export invariant fail-closed (ADR-093)"
issue: 6223
branch: feat-one-shot-6223-plugin-root-export-invariant
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-08-fix-claude-plugin-root-export-invariant-plan.md
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Tasks

Derived from the finalized (post-deepen) plan. Implement with `skill: soleur:work`.
**CPO sign-off required before /work begins** (single-user-incident threshold).

## Phase 0 — Preconditions
- [x] 0.1 Re-verify on fresh `origin/main`: `git grep -n "if (opts?.pluginPath)" apps/web-platform/server/agent-env.ts` still shows the fail-open no-op at ~:201 (the ADR-093 amendment's event-grep re-eval trigger fires if the injection changed).
- [x] 0.2 Confirm the double-sink premise: `assertTrustedPluginPath(args.pluginPath)` at `agent-runner-query-options.ts:197` (binding sink) is retained; the new guard is the env sink.
- [x] 0.3 Read the `stubProductionEnv()` / `vi.unstubAllEnvs()` harness in `apps/web-platform/test/plugin-path.test.ts:20-30` — copy it verbatim into `agent-env.test.ts`.

## Phase 1 — RED (tests first; `cq-write-failing-tests-before`)
- [x] 1.1 `apps/web-platform/test/agent-env.test.ts`: rewrite the *"omits CLAUDE_PLUGIN_ROOT when opts.pluginPath is absent or empty"* test (~:252) into the AC2 mutation-coverage set:
  - [x] 1.1.1 prod-sim empty/absent → throw matching `/CLAUDE_PLUGIN_ROOT export required/` (`{ pluginPath: "" }` + one absent case).
  - [x] 1.1.2 prod-sim non-empty-INVALID → throw matching `/plugin path/i` (`/workspaces/abc/plugins/soleur`, `/tmp/evil/plugins/soleur`, `plugins/soleur`, `/app/../workspaces/x/plugins/soleur`).
  - [x] 1.1.3 prod-sim valid `/app` → sets `env.CLAUDE_PLUGIN_ROOT = /app/shared/plugins/soleur`.
  - [x] 1.1.4 ambient-VITEST absent → still `not.toHaveProperty("CLAUDE_PLUGIN_ROOT")` (graceful test behavior).
- [x] 1.2 `apps/web-platform/test/agent-runner-query-options.test.ts`: AC3 integration pin — valid dispatch (`pluginPath: "/app/shared/plugins/soleur"`) → final returned `options.env.CLAUDE_PLUGIN_ROOT` equals it. Positive-only (the `:197` guard would mask a negative). Keep T4 drift snapshot green.
- [x] 1.3 AC4 re-throw check: decide test-vs-code-read. If test, assert a throw out of `buildAgentQueryOptions` is re-thrown (not swallowed) — cc path re-throws at `cc-dispatcher.ts:2767` → captured in `soleur-go-runner.ts` (`feature:"soleur-go-runner"`); legacy path captures at `agent-runner.ts:2730`.
- [x] 1.4 Run `./node_modules/.bin/vitest run test/agent-env.test.ts test/agent-runner-query-options.test.ts` — confirm new cases FAIL.

## Phase 2 — GREEN (harden the injection)
- [x] 2.1 `apps/web-platform/server/agent-env.ts`: add `import { assertTrustedPluginPath } from "./plugin-path";` (no cycle — plugin-path.ts imports only node:path).
- [x] 2.2 Replace the `:201` `if (opts?.pluginPath)` no-op with the fail-closed injection:
  - present → `env.CLAUDE_PLUGIN_ROOT = assertTrustedPluginPath(opts.pluginPath)` (validates `/app/`; returns value unchanged);
  - absent/empty in prod (`!(process.env.VITEST || process.env.NODE_ENV === "test")`) → `throw new Error("[plugin-path] CLAUDE_PLUGIN_ROOT export required for agent dispatch — pluginPath was empty/undefined")`;
  - absent/empty in test → omit (graceful).
- [x] 2.3 Add a one-line comment citing `plugin-path.ts` as the canonical VITEST/NODE_ENV=test bypass predicate (drift guard) AND note the double `assertTrustedPluginPath` call is deliberate (distinct sinks — see plan Alternatives). Update the `:192-200` doc comment: export is now a fail-closed dispatch precondition; drop the fictional "graceful CLI degradation" language.
- [x] 2.4 Run the two suites → GREEN. `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.

## Phase 3 — ADR amendment (in-scope deliverable)
- [x] 3.1 Amend `knowledge-base/engineering/architecture/decisions/ADR-093-sdk-plugin-source-is-platform-deployed-not-connected-repo.md`'s 2026-07-08 amendment: precise scope wording ("export invariant pinned (non-empty + `/app`-trusted at the buildAgentEnv injection site) + bash propagation gated in CI" — NOT blanket "invariant pinned"); note the shared `NODE_ENV=test` bypass (consumed, not hardened); note `assertTrustedPluginPath` is lexical, not mount-verifying.

## Phase 4 — Verify (ACs)
- [x] 4.1 AC1–AC5, AC7 green (behavioral mutation coverage + integration pin + re-throw + tsc + suites).
- [x] 4.2 AC6: `grep -n "plugin-root-propagation" .github/workflows/ci.yml` ≥1 (present/unmodified; re-fires on this agent-env.ts change per ci.yml:343).
- [x] 4.3 AC8: ADR amendment landed with precise scope.

## Phase 5 — Ship
- [x] 5.1 PR body uses `Ref #6223` (NOT `Closes` — `deferred-scope-out`); note ci.yml propagation probe re-fires on this PR.
- [ ] 5.2 Post-merge: `gh issue close 6223` after merge verification.
