---
title: "fix(security): pin the CLAUDE_PLUGIN_ROOT server-export invariant fail-closed at the injection site (ADR-093)"
date: 2026-07-08
type: fix
status: draft
issue: 6223
branch: feat-one-shot-6223-plugin-root-export-invariant
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
labels: [type/security, domain/engineering, deferred-scope-out]
---

# 🐛 fix(security): pin the `CLAUDE_PLUGIN_ROOT` server-export invariant fail-closed (ADR-093)

> Spec lacks a `spec.md` for this branch — `lane:` defaulted to `cross-domain` (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-07-08 · **Review agents:** architecture-strategist, security-sentinel, spec-flow-analyzer, code-simplicity-reviewer, verify-the-negative + scoped fable advisor. All 6 factual claims (sole caller, both factories `getPluginPath()`, `assertTrustedPluginPath` prod-throw, no import cycle, CI propagation gate, anti-pin test) CONFIRMED against source.

**Key improvements applied:**
1. **Closed an AC mutation hole (spec-flow):** the original AC3 let a fail-OPEN mutant (bare `if` assignment + throw only in `else`) pass, because the positive case ran under ambient VITEST where `assertTrustedPluginPath` is a no-op. AC3 now adds prod-simulated **non-empty-invalid** throw cases (`/workspaces`, `/tmp`, relative, traversal), a prod-simulated positive, and message assertions.
2. **Dropped the isolated `plugin-path.test.ts` guard tests (simplicity + spec-flow + architecture):** the original plan's isolated `assertTrustedPluginPath("")`/`undefined` cases are unreachable (empty is falsy → hits the throw branch before the guard; `undefined` → non-greppable `TypeError` + a type-lie), and workspace/relative/traversal are **already** covered at `plugin-path.test.ts:43-48`. Edit set: 5 files → 4 (AC numbers renumbered; the current AC4 is the new re-throw check).
3. **Corrected the Observability capture-layer citation (architecture P1, `hr-observability-layer-citation`):** the cc-path throw is NOT caught by the sandbox-class-only catch at `cc-dispatcher.ts:2709` — it is re-thrown at `:2767` and captured upstream in `soleur-go-runner.ts` (`feature:"soleur-go-runner"`); the legacy factory captures in its own catch (`agent-runner.ts:2730`).
4. **Reframed as zero-incremental-outage-risk regression pin (architecture + security P2):** the new throw is unreachable via the current prod path (`:197` throws first for the same value), so production outage risk is **zero** — it fires only post-decoupling or via a hypothetical future direct `buildAgentEnv` caller.
5. **Scoped AC9 precisely (architecture P2):** "export invariant pinned (non-empty + `/app`-trusted at injection) + propagation gated in CI," not a blanket "invariant pinned" — the ~28 shell sites are only transitively covered.

**New considerations:** the double `assertTrustedPluginPath` call per dispatch (`:197` binding sink + injection env sink) is **deliberate — distinct sinks**; the shared `NODE_ENV=test` bypass is a guard-family-wide kill-switch this change consumes (does not harden); `assertTrustedPluginPath` is lexical, not mount-verifying — assumptions carried into the ADR amendment.

## Overview

ADR-093 mandates that deployed skills shell out via `bash ${CLAUDE_PLUGIN_ROOT:-<git-root fallback>}/…`.
That `:-` fallback is fail-**safe only under one invariant**: the server exports a **non-empty,
`/app/`-prefixed `CLAUDE_PLUGIN_ROOT`** into the Concierge autonomous-bypass agent bash env. If the
server ever left it unset, the fallback would resolve the connected repo's **untrusted committed**
script copy, and the in-script `[[ -r "$SENTINEL" ]]` guard catches an *absent/unreadable* path but
**not** a *readable-but-untrusted* one — re-opening exactly the hole ADR-093 closes (silent secret
leak through a neutered `redact-sentinel.sh`; `INNGEST_MANUAL_TRIGGER_SECRET` exfiltration via a
redirected `trigger.sh`).

The ADR-093 2026-07-08 amendment recorded this as an **ADR-093-wide, currently-unpinned invariant** and
deferred the hardening to its own cycle (issue #6223). `user-impact-reviewer` rated it **P1**;
`security-sentinel` **P3** ("governed by the ADR-093 SDK-export invariant"); the **CTO** adjudicated
**defer, not block**.

**This plan pins that invariant fail-closed at the exact env-injection site, and removes the silent
no-op that currently encodes the hazard as intended behavior.** Pure server-side hardening: no schema,
no migration, no UI, no infra.

### Root cause: the injection is fail-OPEN and the hazard is pinned as "correct"

Trace (all verified on this branch):

- Both real-SDK factories (`cc-dispatcher.ts`, `agent-runner.ts startAgentSession`) route through the
  **shared** `buildAgentQueryOptions` — the **sole** caller of `buildAgentEnv` — and both always compute
  `pluginPath = getPluginPath()` (never empty in prod; defaults to `/app/shared/plugins/soleur`).
- `buildAgentQueryOptions` **already** calls `assertTrustedPluginPath(args.pluginPath)`
  (`agent-runner-query-options.ts:197`) — which **already throws in prod** for empty / relative /
  non-`/app/` input (`path.isAbsolute("")` is false; `undefined` throws in `path.resolve`). That guard
  protects the SDK `plugins:[{path}]` binding sink (in-process `hooks.json` execution). So the input is
  **incidentally** fail-closed today.
- **But the env export is fail-OPEN and unpinned.** `buildAgentEnv` **independently** injects the var
  via a silent `if (opts?.pluginPath) { env.CLAUDE_PLUGIN_ROOT = opts.pluginPath }` (`agent-env.ts:201`)
  — a no-op when falsy — and its unit test *"omits `CLAUDE_PLUGIN_ROOT` when `opts.pluginPath` is absent
  or empty"* (`agent-env.test.ts:252`) **pins the fail-open omission as intended behavior**. A future
  refactor that decouples input-validation (`:197`) from output-injection (`:201`) — the ADR amendment's
  own event-grep re-eval trigger — would pass `assertTrustedPluginPath` yet ship an env with **no**
  `CLAUDE_PLUGIN_ROOT`, and the shell fallback would silently resolve the untrusted copy.

The `buildAgentEnv` "graceful CLI degradation" rationale is **fictional**: `buildAgentEnv` is server-only
with exactly one caller; the CLI/worktree surface runs the plugin **directly**, never through this
function. The `if`-no-op is dead tolerance whose only exerciser is the anti-pin test.

Per the origin learning (`2026-07-06-connected-repo-shadows-deployed-plugin-via-workspace-relative-path.md`):
the real fail-closed guarantee is an upstream **throw**, not a runtime "if unset" branch. So the fix is
**not** a second, redundant output guard at the chokepoint (which would be dead code and invite a
"consolidate" review finding) — it is to make the **injection itself** fail-closed and flip the anti-pin
test. Enforcement then travels **with** the value-injection point, covering any future `buildAgentEnv`
caller/factory that bypasses `buildAgentQueryOptions`.

### Scope boundary: this pins the Node-side export, not the bash propagation

The end-to-end guarantee is two links: (1) the server **exports** a trusted `CLAUDE_PLUGIN_ROOT`
(this plan), and (2) the SDK **propagates** `options.env` into the bwrap-sandboxed bash. Link (2) is
**already pinned** by the in-image gate `apps/web-platform/scripts/plugin-root-propagation-verify-in-image.sh`
(runs in `.github/workflows/ci.yml`, F2/AC7a). This plan pins only link (1) — the previously-unpinned
one — and cites (2) rather than re-implementing it.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue #6223 / ADR-093 amendment) | Reality (verified) | Plan response |
|---|---|---|
| `agent-env.ts` injects `CLAUDE_PLUGIN_ROOT` ~lines 196–202 | Confirmed: `agent-env.ts:201-202`, silent `if (opts?.pluginPath)` no-op | **This** is the fail-open injection to harden |
| existing `assertTrustedPluginPath()` loaded-gun guard | `plugin-path.ts:68`; called at `agent-runner-query-options.ts:197`; tests at `plugin-path.test.ts:32+` | **Reuse it** at the injection site — no new guard function |
| assertion site ~`agent-env.ts` 110–202 | Correct file; the fix is at the `:201` injection, not a separate chokepoint assertion | Harden `buildAgentEnv`'s injection to fail-closed |
| "startup/dispatch assertion" (issue's proposed shape) | A boot check can't observe a **per-dispatch** env drop; the injection site is the precise per-dispatch boundary | Injection-site fail-closed throw (test-tolerant), not a boot assertion |
| the invariant is "currently unpinned by any test or AC" | Confirmed — and worse, `agent-env.test.ts:252` pins the **hazard** as intended | Flip that test; add prod-simulated throw pins |
| bash propagation invariant | Already pinned by `plugin-root-propagation-verify-in-image.sh` in CI | Cite as downstream link; out of scope to re-pin |
| #6154 (residual family migrations) | OPEN, distinct scope | Out of scope |

## User-Brand Impact

- **If this lands broken, the user experiences:** a false-positive throw would in principle fire on a
  Concierge web dispatch → the chat surface returns a dispatch error, **no agent run starts**. But the
  **incremental production outage risk is zero**: the sole caller always passes `getPluginPath()` (never
  empty in prod), and `assertTrustedPluginPath(args.pluginPath)` at `agent-runner-query-options.ts:197`
  **already throws first** for any empty/untrusted value — so the new `buildAgentEnv` throw is
  unreachable through the current dispatch path. It fires only post-decoupling (`:197` removed) or via a
  hypothetical future direct `buildAgentEnv` caller. The guard is test-tolerant.
- **If this leaks (the invariant this plan pins):** the user's **secrets** are exposed via a neutered
  `redact-sentinel.sh` (legal-generate / incident) writing un-redacted content, and
  `INNGEST_MANUAL_TRIGGER_SECRET` is exfiltrable via a redirected `trigger.sh` POST — a single Concierge
  session suffices.
- **Brand-survival threshold:** `single-user incident`.

> **CPO sign-off required at plan time before `/work` begins.** CTO adjudicated the defer at issue-filing
> time; CPO ack is the single product-owner sign-off on this technical approach. `user-impact-reviewer`
> runs at review time.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (fail-closed injection)** — `buildAgentEnv` (`apps/web-platform/server/agent-env.ts`) replaces
      the silent `if (opts?.pluginPath) { env.CLAUDE_PLUGIN_ROOT = opts.pluginPath }` no-op with a
      fail-closed injection:
      - `opts.pluginPath` present → `env.CLAUDE_PLUGIN_ROOT = assertTrustedPluginPath(opts.pluginPath)`
        (validates `/app/`-prefix; returns the value unchanged, then sets);
      - absent/empty **in a production env** (`!(process.env.VITEST || NODE_ENV === "test")`) → **throw**
        a distinct, greppable error `[plugin-path] CLAUDE_PLUGIN_ROOT export required for agent dispatch — pluginPath was empty/undefined`;
      - absent/empty **in test** → graceful omit (preserve fixture ergonomics for the many
        no-`pluginPath` unit tests).
      **Acceptance is behavioral, not structural:** the AC3 prod-simulated cases (below) are RED before
      Phase 2 and GREEN after. (A `grep` for `assertTrustedPluginPath` in `agent-env.ts` is an optional
      smoke check, NOT the gate — it cannot distinguish fail-closed from fail-open.)
- [ ] **AC2 (mutation coverage — closes the fail-OPEN hole)** — the `agent-env.test.ts` test
      *"omits CLAUDE_PLUGIN_ROOT when opts.pluginPath is absent or empty"* is rewritten so a fail-OPEN
      implementation (bare `if` assignment that sets an **unvalidated** path) CANNOT pass. Using the
      `stubProductionEnv()` / `vi.unstubAllEnvs()` harness from `plugin-path.test.ts`:
      - **prod-sim, empty/absent → throw** matching `/CLAUDE_PLUGIN_ROOT export required/`: cases
        `{ pluginPath: "" }` and `{}`/no-opts (one absent case suffices — both drive the same
        `opts?.pluginPath === undefined` branch).
      - **prod-sim, non-empty-INVALID → throw** matching `/plugin path/i` (proves the SET branch routes
        through `assertTrustedPluginPath`, not a bare assignment): `"/workspaces/abc/plugins/soleur"`,
        `"/tmp/evil/plugins/soleur"`, `"plugins/soleur"` (relative), `"/app/../workspaces/x/plugins/soleur"`
        (traversal).
      - **prod-sim, valid `/app` → sets** `/app/shared/plugins/soleur` (proves the value survives
        validation in prod — not only in the ambient-VITEST no-op path).
      - **ambient-VITEST, absent → still omits** (`not.toHaveProperty("CLAUDE_PLUGIN_ROOT")`) — graceful
        test behavior preserved.
- [ ] **AC3 (dispatch integration pin)** — an `agent-runner-query-options.test.ts` case asserts that for a
      valid dispatch (`pluginPath: "/app/shared/plugins/soleur"`) the **final returned**
      `options.env.CLAUDE_PLUGIN_ROOT` equals that value (assert the returned object — catches any
      downstream drop/allowlist-filter after `buildAgentEnv` returns). **Positive-only by design:** a
      negative integration case cannot isolate the `buildAgentEnv` guard, because
      `assertTrustedPluginPath(args.pluginPath)` at `:197` throws first — the guard-specific negatives
      live in AC2 (unit). The T4 shared-shape drift snapshot still passes.
- [ ] **AC4 (re-throw surfaced, not swallowed)** — a test (or an explicit code-read note in the PR) confirms
      that a throw out of `buildAgentQueryOptions` is **re-thrown** by BOTH factory catches — not
      swallowed: `cc-dispatcher.ts` re-throws at `:2767` (the `:2709` catch handles only sandbox-class
      startup errors) → captured upstream in `soleur-go-runner.ts` (`feature:"soleur-go-runner"`); the
      legacy `agent-runner.ts` factory captures in its own catch (`:2730`). This pins the Observability
      claim (§Observability) that the fail-closed dispatch is Sentry-visible, not a silent crash.
- [ ] **AC5 (test-tolerance preserved)** — under the default VITEST env, existing `buildAgentEnv` /
      `buildAgentQueryOptions` tests that pass mkdtemp / no-`pluginPath` fixtures stay green (the guard is
      a no-op in test mode).
- [ ] **AC6 (downstream link intact + re-fires)** — `apps/web-platform/scripts/plugin-root-propagation-verify-in-image.sh`
      and its `.github/workflows/ci.yml` invocation are **present and unmodified**; because this PR edits
      `agent-env.ts` (a declared propagation-input at `ci.yml:343`), the in-image propagation probe
      **re-fires on this PR** (link 2 actively re-verified, not merely cited). Verify:
      `grep -n "plugin-root-propagation" .github/workflows/ci.yml` returns ≥1.
- [ ] **AC7 (typecheck + suites)** — `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes
      (also proves the new `assertTrustedPluginPath` import in `agent-env.ts` creates no cycle);
      `./node_modules/.bin/vitest run test/agent-env.test.ts test/agent-runner-query-options.test.ts`
      green.
- [ ] **AC8 (ADR)** — `ADR-093-…md`'s 2026-07-08 amendment is updated from "unpinned, holds by
      construction" → precisely **"export invariant pinned (non-empty + `/app`-trusted at the
      `buildAgentEnv` injection site) + bash propagation gated in CI"** (NOT a blanket "invariant pinned"
      — the ~28 shell sites are only transitively covered). It also records: the guard shares (does not
      independently harden) the guard-family `NODE_ENV=test` bypass; and `assertTrustedPluginPath` is
      lexical, not mount-verifying (a `/app/<attacker-writable>` path would pass — controlling
      `args.pluginPath` requires a code change).

### Post-merge (operator)

- [ ] **AC9** — `Ref #6223` in the PR body (not `Closes` — `deferred-scope-out` item). Close via
      `gh issue close 6223` after merge verification. *Automation: `gh` CLI.*

## Implementation Phases

### Phase 1 — RED: pin the fail-closed invariant with tests first
`cq-write-failing-tests-before`. (No `plugin-path.test.ts` edit — its existing loaded-gun describe at
`:32-60` already covers relative/workspace/traversal for `assertTrustedPluginPath`; do not duplicate.)
- `agent-env.test.ts`: rewrite the "omits when absent/empty" test per AC2 — reuse the `stubProductionEnv()`
  / `vi.unstubAllEnvs()` harness copied from `plugin-path.test.ts`. Add the prod-sim empty/absent→throw
  (`/CLAUDE_PLUGIN_ROOT export required/`), prod-sim non-empty-invalid→throw (`/plugin path/i`), prod-sim
  valid-`/app`→sets, and the retained ambient-VITEST absent→omits cases.
- `agent-runner-query-options.test.ts`: add the AC3 integration pin on the final `options.env`
  (positive-only — see AC3 rationale).
- (AC4) Decide test-vs-code-read for the re-throw check; if a test, add it near the factory dispatch
  tests asserting the throw propagates (not swallowed).
- Run both suites; confirm the new cases **fail** (injection not yet hardened).

### Phase 2 — GREEN: harden the injection
- `agent-env.ts`: `import { assertTrustedPluginPath } from "./plugin-path";` then replace the `:201`
  no-op with the AC1 fail-closed injection (present → `assertTrustedPluginPath`-validate + set;
  absent-in-prod → throw the distinct message; absent-in-test → omit). Add a one-line comment citing
  `plugin-path.ts` as the canonical `VITEST`/`NODE_ENV=test` bypass predicate so the two copies cannot
  silently drift. Update the doc comment at `:192-200` to state the export is now a fail-closed dispatch
  precondition (drop the "graceful CLI degradation" language — it was fictional for this server-only
  function) AND note the double `assertTrustedPluginPath` call is deliberate (see Alternatives).
- Run both suites → GREEN. `tsc --noEmit`.

### Phase 3 — ADR amendment (in-scope deliverable, NOT a follow-up)
- Amend `ADR-093-…md`'s 2026-07-08 amendment per AC8: precise scope ("export invariant pinned … +
  propagation gated in CI"), the shared `NODE_ENV=test` bypass note, and the lexical-not-mount-verifying
  assumption carried forward. No new ADR — this hardens Accepted ADR-093.

## Architecture Decision (ADR/C4)

Detection fires: this **extends** the ADR-093 amendment's "currently unpinned" status → "pinned." The
ADR update is an **in-scope deliverable** (Phase 3), never deferred.

### ADR
Amend **ADR-093** (no new ADR): the 2026-07-08 amendment moves to "**pinned + verified** — the
`CLAUDE_PLUGIN_ROOT` server export is a fail-closed precondition enforced at the `buildAgentEnv`
injection site (reusing `assertTrustedPluginPath`), regression-pinned by `agent-env.test.ts` +
`plugin-path.test.ts`."

### C4 views
**No C4 impact — enumeration checked against all three `.c4` files.** Read
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`:
- **External human actor:** none new — the threat actor is the already-modeled untrusted
  **`connectedRepoPlugin`** ("Connected-Repo Plugin Copy" system, `model.c4:268`, UNTRUSTED boundary per
  ADR-093/ADR-074).
- **External system / vendor:** none new.
- **Container / data-store:** none new — no secret store, table, or bucket touched.
- **Actor↔surface access relationship:** none changed — the `claude -> skillloader` edge
  (`model.c4:316`, "Loads plugin from the PLATFORM-DEPLOYED root (getPluginPath())…, never the
  connected-repo workspace copy (ADR-093)") already models the boundary this fail-closed injection
  **strengthens**; no element description is falsified. No `views.c4 include` change needed.

### Sequencing
Not applicable — true at merge; the ADR amendment ships in the same PR.

## Observability

```yaml
liveness_signal:
  what: "Sentry issue captured when buildAgentEnv throws (dispatch fails closed); complemented by the existing plugin-root-propagation-verify-in-image.sh CI gate + verifyPluginMountOnce() boot probe"
  cadence: "per-dispatch (injection throw) / per-CI-run (propagation gate) / per-boot (mount probe)"
  alert_target: "Sentry web-platform issue → operator"
  configured_in: "apps/web-platform/server/agent-env.ts (injection throw) + apps/web-platform/scripts/plugin-root-propagation-verify-in-image.sh (CI, .github/workflows/ci.yml)"

error_reporting:
  destination: "Sentry web-platform via SENTRY_DSN. A throw out of buildAgentQueryOptions is RE-THROWN by both factory catches (it is NOT the sandbox-class error the cc-dispatcher.ts:2709 catch handles — that block re-throws at :2767) and captured upstream: cc path in soleur-go-runner.ts (feature:'soleur-go-runner'); legacy path in agent-runner.ts's own catch (:2730)"
  fail_loud: "the agent run never starts; a Sentry issue carrying the '[plugin-path] CLAUDE_PLUGIN_ROOT export required' message (or assertTrustedPluginPath's '[plugin-path] Refusing untrusted') appears — not a silent degraded run. NOTE: today this Sentry-visible fail-closed behavior is provided by the :197 guard; the buildAgentEnv throw is the post-decoupling regression pin whose throw rides the SAME re-throw path"

failure_modes:
  - mode: "server dispatch env would carry an empty/absent/untrusted CLAUDE_PLUGIN_ROOT (the exploit precondition) after a :197<->:201 decoupling"
    detection: "buildAgentEnv throws at the injection site (host-side Node dispatch process — trusted + Sentry-reachable, BEFORE the bwrap shell-out); re-thrown by both factory catches to the upstream captureException sites above (AC4 pins the re-throw)"
    alert_route: "Sentry web-platform → operator"

logs:
  where: "Sentry breadcrumbs + docker logs of the web-platform container"
  retention: "Sentry default (~90d); container logs ephemeral"

discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/agent-env.test.ts"
  expected_output: "the prod-simulated empty/absent-throw + non-empty-invalid-throw + valid-/app-set + ambient-VITEST-omit cases are all green — proving the fail-closed injection routes through assertTrustedPluginPath (fail-open mutant fails)"
```

**Affected-surface note (Phase 2.9.2):** the throw fires in the **host-side Node dispatch process**
(trusted, Sentry-inspectable) **before** any bwrap-sandbox shell-out — by design it catches the failure
on the inspectable side (the exploit itself would occur *inside* the blind sandbox bash). This is the
last trusted point upstream of the sandbox; no in-sandbox probe is required, and the downstream bash
propagation is separately gated in CI.

## Domain Review

**Domains relevant:** Engineering (security)

### Engineering / Security

**Status:** reviewed (CTO carry-forward from issue #6223 filing)
**Assessment:** CTO adjudicated the residual **defer, not block** and recorded it as an ADR-093-wide
amendment; `security-sentinel` P3 (governed by the SDK-export invariant), `user-impact-reviewer` P1.
This plan implements the CTO-endorsed hardening at the injection site with no new attack surface, no
dependency, no infra, and it removes an anti-pin test. At `single-user incident` threshold, deepen-plan's
security-sentinel + architecture-strategist run for substance-level review (the exit gate recommends
ultrathink/deepen-plan, invoked next).

### Product/UX Gate

Not applicable — mechanical UI-surface scan of `## Files to Edit` matches **no** UI path
(`components/**`, `app/**/page.tsx`, `app/**/layout.tsx`, `.css`, …). All edits are `server/*.ts`,
`test/*.ts`, and one ADR `.md`. **Product = NONE.**

## GDPR / Compliance Gate

Trigger (b) fires (brand-survival `single-user incident` declared), so the gate was **assessed**. The
diff touches **no** regulated-data surface: no schema, migration, `.sql`, auth flow, or API route; it
processes/stores/moves **no** personal data — it is a server-side env-injection **assertion**. No Art. 9,
no lawful-basis, no Art. 30 trigger. **Advisory: no Critical findings; no `compliance-posture.md` write.**
The hardening *reduces* leak risk for the secret-redaction path.

## Infrastructure (IaC)

None — no server, service, cron, secret, DNS, cert, or firewall rule introduced. Pure code change
against an already-provisioned surface (`apps/web-platform/server/`). Phase 2.8 skipped.

## Files to Edit

- `apps/web-platform/server/agent-env.ts` — replace the silent `if (opts?.pluginPath)` no-op with the
  fail-closed injection (reuse `assertTrustedPluginPath`); add the import; update the doc comment.
- `apps/web-platform/test/agent-env.test.ts` — rewrite the "omits when absent/empty" test into the AC2
  mutation-coverage set (prod-sim empty/absent-throw + non-empty-invalid-throw + valid-`/app`-set +
  ambient-VITEST-omit).
- `apps/web-platform/test/agent-runner-query-options.test.ts` — AC3 integration pin on the final
  `options.env.CLAUDE_PLUGIN_ROOT` (+ optional AC4 re-throw test).
- *(NOT edited: `apps/web-platform/test/plugin-path.test.ts` — its existing loaded-gun describe at `:32-60`
  already covers relative/workspace/traversal for `assertTrustedPluginPath`; dropped per review to avoid
  unreachable-input duplication.)*
- `knowledge-base/engineering/architecture/decisions/ADR-093-sdk-plugin-source-is-platform-deployed-not-connected-repo.md`
  — amend the 2026-07-08 amendment to "pinned."

## Files to Create

None.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` bodies reference none of `agent-env.ts`,
`agent-runner-query-options.ts`, or `plugin-path.ts`.

## Alternatives Considered

| Alternative | Rejected because |
|---|---|
| **Keep `buildAgentEnv` graceful + add a separate `assertPluginRootExported(env)` guard at the `buildAgentQueryOptions` chokepoint** (plan v1) | Redundant with the input guard, asserts an intermediate object, leaves the anti-pin test + fail-open `if` in place, and ships a two-guard design review will ask to consolidate. Scoped-advisor (fable) + origin learning both flagged the runtime output branch as dead code. |
| **Boot/startup-only assertion** | Cannot observe a **per-dispatch** env drop — the precise site of the exploit precondition is the injection, not boot. `getPluginPath()` + `verifyPluginMountOnce()` already cover the boot surface. |
| **Rely on the existing `assertTrustedPluginPath(args.pluginPath)` at :197 alone** | It validates the **input** arg for the `plugins:[]` binding sink; it does **not** enforce the **env-export** injection, which `buildAgentEnv` decides independently. The two are coupled only incidentally today — this plan makes the export enforcement explicit and co-located with the injection. |
| **Collapse the two `assertTrustedPluginPath` calls into one (`:197` only, or injection-only)** | NOT a duplication to remove — the two calls guard **distinct sinks**: `:197` protects the SDK `plugins:[{path}]` binding (in-process `hooks.json` execution, `agent-runner-query-options.ts:255`); the injection-site call protects the exported bash `CLAUDE_PLUGIN_ROOT`. Removing either re-opens its sink. The doc comment in `agent-env.ts` and this row mark the double-call **deliberate** so `/simplify` or a reviewer does not collapse it. |
| **Make `buildAgentEnv.pluginPath` a required TS param (interface change)** | Larger blast radius (every mkdtemp/no-pluginPath test call site becomes a type error); the runtime test-tolerant throw achieves the same fail-closed guarantee with a smaller diff and preserves fixture ergonomics. |
| **Runtime "if `CLAUDE_PLUGIN_ROOT` unset then …" branch in the deployed shell scripts** | The ADR establishes the shell layer *cannot* distinguish trusted-local-unset (CLI/worktree) from untrusted-server-unset. The distinction lives at the platform/SDK layer — hence this injection-site guard. |
| **Collapse the two `assertTrustedPluginPath` calls into one** (`:197` + the new injection call) | REJECTED — they guard **distinct sinks**: `:197` protects the SDK `plugins:[{path}]` binding (in-process `hooks.json` execution, `agent-runner-query-options.ts:255`); the injection call protects the exported `CLAUDE_PLUGIN_ROOT` bash-env sink. Collapsing either reopens one sink. The double call is **deliberate**; a code comment + this row prevent `/simplify` or a reviewer from consolidating it. |

## Non-Goals

- The #6154 residual **family migrations** — distinct, tracked separately.
- Re-pinning the bash-propagation link (already gated by `plugin-root-propagation-verify-in-image.sh`).
- Any change to `buildAgentSandboxConfig` / the ADR-079 bwrap canary fixture (untouched → canary-neutral).
- Changing the input guard at `agent-runner-query-options.ts:197` (it stays — protects the `plugins:[]`
  binding sink).

## Sharp Edges

- The `## User-Brand Impact` section must stay filled (no `TBD`/placeholder) or `deepen-plan` Phase 4.6
  halts.
- **Test-tolerance is load-bearing:** the injection throw MUST honor the VITEST/NODE_ENV=test bypass, or
  the many `buildAgentEnv` unit tests that pass no `pluginPath` would break. Reuse the exact
  `stubProductionEnv()` / `vi.unstubAllEnvs()` harness already in `plugin-path.test.ts`.
- **Mutation-test the gate** (learning `2026-07-05-…invariant-PR`): assert the injection actually THROWS
  on empty/absent in prod-sim — a first-cut guard that fails **open** would pass a naive "it exists"
  check while enforcing nothing.
- **Do not** claim the *end-to-end* invariant is pinned by this Node-side change alone — the bash
  propagation is a separate, already-gated link (AC7). State the scope boundary in the ADR amendment.
- If any AC greps a `${CLAUDE_PLUGIN_ROOT:-…}` needle, use `grep -F` — BRE `$`/`{`/`}` silently return 0
  (learning `2026-07-08-adr093-anchored-literal-migration-needs-parity-test-and-grep-F.md`).
- **Re-verify on fresh `origin/main`** before `/work` (learning `2026-07-05-stale-branch-…`): the
  amendment's event-grep trigger fires if `agent-env.ts`'s injection changed under you.

## Related

- ADR-093 (Accepted) + its 2026-07-08 amendment (origin).
- Issue #6223 (this plan) · #6154 (distinct residual family migrations) · #6156 PR (surfaced the P1).
- Learnings: `knowledge-base/project/learnings/bug-fixes/2026-07-06-connected-repo-shadows-deployed-plugin-via-workspace-relative-path.md`,
  `knowledge-base/project/learnings/best-practices/2026-07-08-adr093-anchored-literal-migration-needs-parity-test-and-grep-F.md`,
  `knowledge-base/project/learnings/2026-04-27-preflight-security-gates-skip-vs-fail-defaults.md`,
  `knowledge-base/project/learnings/2026-03-20-middleware-error-handling-fail-open-vs-closed.md`,
  `knowledge-base/project/learnings/workflow-patterns/2026-07-05-stale-branch-can-silently-revert-a-just-merged-invariant-pr.md`.
