---
title: "fix: cross-workspace isolation canary probe fails on unresolved vitest/config import"
type: fix
date: 2026-10-09
slug: fix-workspace-isolation-vitest-config
branch: feat-one-shot-9860-deploy-canary-health-failed
issue: 9860
priority: normal
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# fix: cross-workspace isolation canary probe fails on unresolved vitest/config import

The report-only cross-workspace isolation deploy probe (#2640, shipped in PR
#9809) logs `op=workspace-isolation workspace_isolation_failed
reason=vitest_rc_1: test/vitest.canary.config.ts [UNRESOLVED_IMPORT] Could not
resolve 'vitest/config'` on every deploy — confirmed on the v0.334.1 deploy at
2026-10-09 ~19:31Z (issue #9860, latest comment). The defect is in the probe's
own wiring, not in workspace isolation: the suite never runs, so the soak
counter `consecutive_pass` can never move and the report-only → blocking-gate
promotion (follow-through `scripts/followthroughs/workspace-isolation-verdict-2640.sh`)
is silently stuck at zero.

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Proposed Fix

Remove the only unresolvable import from `test/vitest.canary.config.ts` and
export a plain object literal instead of `defineConfig(...)`. **Measured on
vitest 4.1.11 in this worktree:** with cwd in a directory containing only the
three-file payload and no `node_modules`, a plain-object config runs clean and
the suite file's own `import { describe, it, expect } from "vitest"` **does**
resolve — vitest's module runner maps the bare `vitest` specifier to the
running installation internally (verified: `Tests 1 passed`). So dropping
`defineConfig` alone is sufficient; no image change, no symlink, no NODE_PATH.

## Files to Edit

- `apps/web-platform/test/vitest.canary.config.ts` — delete
  `import { defineConfig } from "vitest/config"`; change
  `export default defineConfig({…})` to `export default {…}` (a plain object
  literal carrying identical keys); extend the header comment to record that
  the in-image run resolves no bare specifiers from the config file.
- `apps/web-platform/test/dockerfile-vitest-version-pin.test.ts` — add an `it`
  asserting the canary config carries **zero `import` statements** (the
  in-image run has no `node_modules/vitest` to resolve them; vitest-only
  specifiers inside *test* files resolve internally, config-file imports do
  not).
- `knowledge-base/engineering/operations/runbooks/workspace-isolation-canary-probe.md`
  — one paragraph under "Image strategy" recording the zero-import constraint
  and the pin that enforces it (design-note accuracy; this file is NOT in the
  sibling session's collision set — see below).

## Files to Create

- None.

## Collision Guard (sibling session #9884)

Worktree `.worktrees/feat-one-shot-9871-canary-failure-diagnostics` (draft PR
#9884) has committed diffs to `apps/web-platform/infra/ci-deploy.sh`,
`apps/web-platform/infra/ci-deploy.test.sh`,
`knowledge-base/engineering/operations/runbooks/canary-probe-set.md`, and
`plugins/soleur/test/preflight-discoverability-test.test.ts` (verified via
`git -C <worktree> diff origin/main --name-only` at plan time). **This plan
touches none of them** — the chosen fix needs no `ci-deploy.sh`/`ci-deploy.test.sh`
edit (argv unchanged) and no `canary-probe-set.md` verdict-table edit
(classification unchanged). The one runbook edit lands in
`workspace-isolation-canary-probe.md`, outside the sibling's set.

## Research Insights

**Premise Validation (Phase 0.6).** Checked: (a) issue #9860 state — `OPEN`,
title confirms the umbrella is the `sandbox_broken` faithful-canary verdict;
the vitest defect is a *reported sub-finding in its latest comment*, so the
issue is live premise. (b) All four code paths cited exist on `origin/main`
(`git show origin/main:<path>` OK for `test/vitest.canary.config.ts`,
`test/sandbox-isolation.test.ts`, `infra/ci-deploy.sh`,
`test/dockerfile-vitest-version-pin.test.ts`). (c) #2640 is CLOSED (the probe's
origin issue — `Ref` only); #9871 is CLOSED (the deploy blocker). (d) ADR
corpus grep on `vitest|canary|defineConfig` surfaced no decision rejecting a
plain-object config — ADR-079 governs the faithful-canary argv capture, which
this plan does not touch. (e) Mechanism claim verified empirically rather than
asserted: local repro of BOTH arms (failing `defineConfig` config and passing
plain-object config) ran under `env -i` with the worktree's vitest 4.1.11 —
same version the Dockerfile pins globally.

**Property List (Phase 0.6b).**

1. `vitest run --config test/vitest.canary.config.ts` inside the canary
   container executes the suite instead of dying at config load.
2. The defect class (config file carrying an import the in-image resolution
   context cannot satisfy) is caught at PR time, not by a per-deploy Sentry
   page.
3. `env -i` scrubbing, the exact pinned docker-exec argv (CWI-1), the vitest
   version pin, and the report-only semantics all stay byte-identical.

**Cut List (Phase 0.6b).** Mechanisms the ask floated and what cut them:

- `node_modules/vitest` symlink → global install baked into the Dockerfile —
  buys property 1, but property 1 is already bought by the 4-line config edit;
  image diff + new resolution edge is strictly more mechanism. **Cut.**
- `NODE_PATH` — does not affect ESM resolution AND `env -i` scrubs it; buys
  nothing. **Cut** (named in the ask as probably-broken; confirmed).
- Surgical `COPY` of `node_modules/vitest` — already rejected in
  `workspace-isolation-canary-probe.md` (~50+ transitive packages). **Cut.**
- Vendored `vitest` stub module — unnecessary; suite-side `vitest` imports
  resolve internally (measured). **Cut.**

**Key file/symbol map.**

- `apps/web-platform/infra/ci-deploy.sh` › `run_workspace_isolation_probe()` —
  docker-exec argv (`env -i` + `/usr/local/bin/vitest run --config …`), rc →
  verdict classification, `Tests [1-9]… passed` vacuous-green guard.
- `apps/web-platform/infra/ci-deploy.test.sh` › CWI-1 — pins the exact exec
  argv; **unchanged by this plan** (no diff → no collision).
- `apps/web-platform/test/dockerfile-vitest-version-pin.test.ts` — carries the
  vitest global-install pin AND the canary-config minimality `it`; the new
  assertion lands beside the latter.
- `apps/web-platform/test/sandbox-isolation.test.ts` — imports `vitest`
  (resolves internally — measured) and `@anthropic-ai/claude-agent-sdk`
  (production dependency, present in runner `/app/node_modules` via
  `npm ci --omit=dev` — resolved through vite-node's node-resolution walk from
  the importer — measured with a stub package).
- `apps/web-platform/test/helpers/sandbox-isolation-fixtures.ts` — node
  builtins only; no resolution risk.
- `apps/web-platform/.dockerignore` — the three `!test/…` exact-path bangs
  already re-include the whole payload; **no change needed**.
- `apps/web-platform/Dockerfile` — `npm install -g vitest@4.1.11
  --before=2026-08-19 --ignore-scripts` (cli-tools stage) + 3-file payload
  COPY (runner stage); **no change needed**.

**Institutional learnings applied.**

- `2026-10-09-docker-exec-inherits-the-canarys-prod-env-scrub-with-env-i.md` —
  the `env -i` scrub is load-bearing; this fix preserves it byte-for-byte.
- `2026-10-09-an-rc0-verdict-is-not-proof-the-suite-ran-vacuous-green.md` —
  the vacuous-green marker guard already in the probe stays as-is.
- `2026-09-13-the-gate-built-to-catch-docker-only-failures-never-ran-in-docker.md`
  / `2026-07-23-cross-root-import-passes-local-next-build-fails-docker-context.md`
  — this defect is the same class: green locally (repo has
  `node_modules/vitest`), red only in the pruned resolution context of the
  image. The new pin assertion is the PR-time mirror of the in-image
  constraint.
- `2026-05-04-in-isolation-probe-missed-user-shape-and-scope-out-exacerbation.md`
  — probe work on this surface reads small and pages per-deploy; the fix is
  deliberately minimal.

## Research Reconciliation — Spec vs. Codebase

| Spec/brief claim | Reality | Plan response |
|---|---|---|
| "the suite file itself may import `vitest` and fail" (the 5-line-vs-image-change fork) | Suite DOES `import { … } from "vitest"` but vitest 4.1.11 resolves the bare `vitest` specifier internally even with zero `node_modules` in scope — measured, not assumed | Option (a) alone is sufficient; no Dockerfile/symlink change |
| "`NODE_PATH` probably does not work for ESM" | Correct — and `env -i` scrubs it anyway | Cut |
| Root cause hypothesis (global install + no `/app/node_modules/vitest`) | Confirmed: `npm ci --omit=dev` in runner stage + `npm install -g vitest@4.1.11`; repro produced the exact failure locally | Proceed with config fix |

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly — the probe
  is report-only and tenant-facing isolation is unchanged. The real cost of
  *not* fixing it: every deploy emits a `workspace_isolation_failed` Sentry
  page that is pure noise, and the verdict ledger's `consecutive_pass` can
  never accumulate, so the blocking-gate promotion path is silently dead.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no
  new exposure — the `env -i` scrub (the actual credential-containment
  mechanism) is untouched.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the change is confined to a test
  config file and a unit test; it neither weakens sandboxing nor touches a
  credential path — the sensitive-path regex does not match
  `apps/web-platform/test/*` (preflight Check 6 SSOT verified).

## Observability

```yaml
liveness_signal:
  what: "Per-deploy `WORKSPACE_ISOLATION: verdict=…` journald line (logger -t
        ci-deploy) + durable verdict in
        /mnt/data/ci-deploy-workspace-isolation.json surfaced as
        `.workspace_isolation` on /hooks/deploy-status
        (cat-deploy-state.sh › workspace_isolation_json())"
  cadence: "once per deploy, inside the CANARY_HEALTHY window"
  alert_target: "Sentry op=workspace-isolation event on red verdicts only
                (workspace_isolation_sentry_event)"
  configured_in: "apps/web-platform/infra/ci-deploy.sh ›
                 run_workspace_isolation_probe() / write_workspace_isolation_state()"
error_reporting:
  destination: "Sentry web-platform (op=workspace-isolation) + journald
               ci-deploy unit + deploy stdout `Workspace isolation probe
               (non-blocking): …` echo"
  fail_loud: "workspace_isolation_failed / workspace_isolation_timeout emit a
             Sentry event; canary_infra_error records state without paging
             (dark-launch by design)"
failure_modes:
  - mode: "This defect class regresses — a future edit reintroduces an import
          the in-image context cannot resolve (layers: PR-time pin assertion in
          dockerfile-vitest-version-pin.test.ts → post-deploy
          `reason=vitest_rc_1: …[UNRESOLVED_IMPORT]` in journald + Sentry)"
    detection: "new zero-imports assertion REDs at PR time; post-deploy the
               red verdict + reason text reaches Sentry"
    alert_route: "Sentry page (existing route, unchanged)"
  - mode: "Genuine workspace-isolation break (the probe's actual job)"
    detection: "workspace_isolation_failed with a `FAIL <file>`/`AssertionError`
               reason; vacuous-green guard converts suspicious rc-0 to RED"
    alert_route: "Sentry page (existing)"
  - mode: "Probe hangs (bwrap deadlock in-image)"
    detection: "workspace_isolation_timeout via the host-side `timeout` cap"
    alert_route: "Sentry page (existing)"
logs:
  where: "journald `ci-deploy` unit (WORKSPACE_ISOLATION: line) on the deploy
         host; mirrored to Better Stack via the existing Vector ship"
  retention: "journald retention per journald-soleur.conf; verdict ledger is
             durable on /mnt/data"
discoverability_test:
  # Single-verb grep — Check 10's shell-active reject bans | ; & < > $ and
  # backticks anywhere in the string, so no alternation/sed/chaining. Asserts
  # the POST-FIX shape (`export default {`): prints 1 with rc 0 once the fix
  # lands, 0 (rc 1) while `export default defineConfig({…})` is still there —
  # verified on this worktree 2026-10-09.
  command: "grep -c 'export default {' apps/web-platform/test/vitest.canary.config.ts"
  expected_output: "1"
```

## Guard Contract

### Guard 1 — canary-config zero-imports assertion

**Property.** `test/vitest.canary.config.ts` contains no `import` statements,
so the in-image `vitest run --config` (which resolves no bare specifiers from
`/app/node_modules` — vitest is a global install there) can always load it.

**Assembly.** The single config file is the only artifact vitest's *config
loader* resolves from `/app/test/` in the runner image; the assertion
quantifies over the file's full non-comment code after the existing
comment-stripping in `dockerfile-vitest-version-pin.test.ts`. The chokepoint
is that file's import section — there is no second config the probe loads
(CWI-1 pins the argv to exactly this `--config`).

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Reintroduce `import { defineConfig } from "vitest/config"` | RED |
| 2 | Point the test's `read("test/vitest.canary.config.ts")` at a nonexistent path (guard's own dispatch: a read that throws before asserting would silently vacate a `not.toMatch`) — the assertion must error, not pass | RED |
| 3 | Add a second import of a *different* kind (`import path from "node:path"`) after a compliant file | RED |
| 4 | Suite-side (harness) mutation: weaken the regex to `'^import from '` (a shape real imports never take) | RED |
| 5 | Must-PASS input differing from canonical: the plain-object config with keys reordered (`test:` before `cacheDir:`) | PASS |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Fix the workspace-isolation canary probe defect reported in issue #9860's latest comment … `[UNRESOLVED_IMPORT] Could not resolve 'vitest/config'`" [brief] | Files-to-Edit `test/vitest.canary.config.ts` | mapped |
| 2 | "pick after checking vitest's config-load semantics … verify whether the SUITE file `test/sandbox-isolation.test.ts` itself imports `vitest` … resolve it in the plan, do not hand-wave" [brief] | Research Insights measurement + Research Reconciliation row | mapped |
| 3 | "the probe is report-only dark-launch (never blocking) — keep it that way; `env -i` scrubbing is load-bearing … do not weaken it" [brief] | Non-Goals + AC preserving argv/`env -i`/classification | mapped |
| 4 | "the exact docker exec argv is pinned by `ci-deploy.test.sh` (CWI-1) and vitest version pin by `dockerfile-vitest-version-pin.test.ts` — update those tests only if the chosen fix changes what they pin" [brief] | CWI-1 unchanged; new `it` added to the pin file (extension, not a re-pin) | mapped |
| 5 | "`.dockerignore` prunes `test/` and re-includes the probe payload — check it" [brief] | Checked: three exact-path bangs cover the whole payload; no edit needed | mapped |
| 6 | "Prefer fixes that do NOT touch those files; if the chosen fix must touch one, the plan must name the overlap" [brief] | Collision Guard section: zero overlap with the sibling's four files | mapped |
| 7 | "plans touching prod code MUST carry a `## Observability` block (5 fields incl. a `discoverability_test.command` that runs without SSH) and observability-layer citations per failure mode" [brief] | `## Observability` block above (command is `grep` — allowlisted, no ssh) | mapped |
| 8 | "PR body should use `Ref #9860` (NOT `Closes` …) and `Ref #2640`" [brief] | AC + tasks.md PR-body reminder | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Plain-object `export default` in `vitest.canary.config.ts` | "(a) drop `defineConfig` and `export default` a plain object literal in `test/vitest.canary.config.ts` (removes the import entirely — likely minimal)" | asked |
| Zero-imports `it` in `dockerfile-vitest-version-pin.test.ts` | "the defect class is caught at PR time" — implied by "update those tests only if the chosen fix changes what they pin" + "write tests first per TDD gate" | inferred — justification: the probe defect shipped green because no PR-time check mirrored the in-image resolution constraint; without the pin the fix is unenforced (Guard 1 exists for exactly this) |
| Runbook paragraph in `workspace-isolation-canary-probe.md` | — | inferred — justification: the design note records *why* the payload is 3 files with a standalone config; the zero-import constraint is a load-bearing part of that design and would otherwise live only in a test file |

### Split Assessment

- Subsystems touched: 1 — `apps/web-platform` (+ its runbook doc under
  `knowledge-base/engineering/operations/runbooks/`)
- Planned files: 3 | Estimated changed lines: ~35
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] `apps/web-platform/test/vitest.canary.config.ts` contains no `import`
      statements and `export default`s a plain object literal with the same
      keys (`cacheDir`, `test.environment`, `test.include`, `test.testTimeout`,
      `test.hookTimeout`)
- [ ] New assertion in `apps/web-platform/test/dockerfile-vitest-version-pin.test.ts`
      REDs when the config gains any `import` line; full file green
- [ ] `bash apps/web-platform/infra/ci-deploy.test.sh` — CWI arms unchanged and
      still green (no diff to `ci-deploy.sh`)
- [ ] In-image-equivalent repro: `env -i`-scrubbed vitest run against a temp
      dir holding only the 3 payload files collects and runs the suite
      (verified once at implementation time; recipe in Test Scenarios)
- [ ] Probe stays report-only: `run_workspace_isolation_probe` still
      `return 0`s; verdict vocabulary unchanged
- [ ] Zero overlap with sibling PR #9884's file set — verify against the
      merge-base (`git diff --name-only origin/main...HEAD` contains none of
      `apps/web-platform/infra/ci-deploy.sh`,
      `apps/web-platform/infra/ci-deploy.test.sh`,
      `knowledge-base/engineering/operations/runbooks/canary-probe-set.md`,
      `plugins/soleur/test/preflight-discoverability-test.test.ts`), NOT the
      moving tip
- [ ] PR body uses `Ref #9860` and `Ref #2640` — never `Closes` (the issue's
      `sandbox_broken` verdict is owned by the sibling pipeline)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change.
Semantic sweep against all 8 domain Assessment Questions: no UI surface (the
mechanical glob check against `test/vitest.canary.config.ts`,
`test/dockerfile-vitest-version-pin.test.ts`, and the runbook matches nothing
in `ui-surface-terms.md`), no regulated-data surface, no vendor/procurement
decision, no user-facing capability. Product tier: NONE (no files match the
mechanical escalation globs).

## Test Scenarios

- **unit (RED→GREEN, TDD):** Given the current config with
  `import { defineConfig } …`, when the new zero-imports `it` runs, then it
  FAILs; after the config edit it PASSes. Command:
  `npx vitest run test/dockerfile-vitest-version-pin.test.ts`
- **unit (existing pins):** Given the unchanged Dockerfile pin and minimality
  `it`, when the file runs, then both stay green (the plain-object literal
  still satisfies `include: ["test/sandbox-isolation.test.ts"]`).
- **integration (in-image equivalence, run once at work time):** Given a temp
  dir `T` with only `test/vitest.canary.config.ts`, `test/sandbox-isolation.test.ts`,
  `test/helpers/sandbox-isolation-fixtures.ts` and a `node_modules` containing
  only prod deps (or a stub for the SDK), when
  `env -i PATH=… HOME=/tmp CI=true <vitest-bin> run --config test/vitest.canary.config.ts`
  runs with cwd `T`, then vitest collects the suite and exits without
  `[UNRESOLVED_IMPORT]` — the exact failure the prod probe logged. (Measured
  at plan time with a stubbed SDK package: `Tests 1 passed`; the real suite
  will also exercise `SOLEUR_ISOLATION_TIERS=direct`.)
- **regression (report-only semantics):** Given a vitest failure post-fix,
  when `ci-deploy.test.sh` runs, then CWI-4's "a vitest FAIL still exits 0"
  arm stays green — unchanged code path.

## Alternative Approaches Considered

| Approach | Why not chosen |
|---|---|
| (b) Symlink `/app/node_modules/vitest` → `/usr/local/lib/node_modules/vitest` in the Dockerfile | Works, but adds an image diff + a second resolution surface to keep honest (symlink target drift vs. the `npm -g` pin) when a 4-line config edit removes the need entirely |
| (c) `NODE_PATH` | Does not affect ESM resolution; `env -i` scrubs it anyway — dead on both axes |
| Drop the config file, pass everything as CLI flags | Changes the CWI-1-pinned argv (and `cacheDir`/`testTimeout` flag coverage is thinner); a collision-adjacent diff for zero benefit |
| `import type { UserConfig }` + `satisfies` | `import type` is erased pre-resolution so it *would* work — but a zero-import file is simpler and the guard invariant is stricter |

## Non-Goals

- Promoting the probe to a blocking gate (soak-gated promotion lives in
  `scripts/followthroughs/workspace-isolation-verdict-2640.sh`; this fix
  unblocks the soak, does not flip it)
- The `sandbox_broken / bwrap_operation_not_permitted` faithful-canary
  verdict — owned by the sibling pipeline (#9884)
- The `wrong_elevation_userns` outer-wrap finding — expected per the #9874
  file-cap revert
- Any change to the docker-exec argv, `env -i` scrub, verdict vocabulary, or
  Sentry routing

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` bodies contain no
match for `apps/web-platform/test/vitest.canary.config.ts`,
`apps/web-platform/test/dockerfile-vitest-version-pin.test.ts`,
`apps/web-platform/test/sandbox-isolation.test.ts`, or
`apps/web-platform/Dockerfile`.

## References

- Issue: #9860 (latest comment — the `workspace_isolation_failed` report) —
  `Ref`, not `Closes`
- Origin issue: #2640 (`Ref`) — probe shipped in PR #9809
- Sibling: draft PR #9884 (branch `feat-one-shot-9871-canary-failure-diagnostics`)
- Runbook: `knowledge-base/engineering/operations/runbooks/workspace-isolation-canary-probe.md`
- Followthrough: `scripts/followthroughs/workspace-isolation-verdict-2640.sh`
- Learning: `knowledge-base/project/learnings/security-issues/2026-10-09-docker-exec-inherits-the-canarys-prod-env-scrub-with-env-i.md`
