---
title: "Wire creds-gated real --capture for the faithful sandbox canary (ADR-079 deferral B)"
issue: 5913
branch: feat-one-shot-5913-sandbox-canary-capture
type: feature
lane: cross-domain
brand_survival_threshold: aggregate pattern
adr: ADR-079
relates_to: [5875, 5889, 5849, 5873, 4932, 4941]
date: 2026-07-03
---

# Wire creds-gated real `--capture` for the faithful sandbox canary — #5913

## Overview

`apps/web-platform/scripts/sandbox-canary.mjs --capture` is currently a stub (`runCapture` returns `3`), and the prod replay fixture `apps/web-platform/infra/sandbox-canary-argv.json` ships as `{"status":"uncaptured"}`. This plan implements the real `--capture`: a **bwrap-intercepting PATH shim** + a **real `query()` drive** that feeds the SDK the real `buildAgentSandboxConfig()` object, snapshots the SDK's real bwrap **SETUP argv** to the committed fixture (deterministically normalized), and wires a **CI SDK-bump gate** that re-captures + byte-diffs (`--verify`) and replays the captured argv against the committed seccomp profile, blocking on a real `sandbox_broken`.

This is **ADR-079 deferral B** — the higher-fidelity half of #5875 item 3 that PR3 deferred to keep a paid, non-deterministic model turn off the merge-blocking path. It is a **hard prerequisite of #5889** (the dark-launch soak): the soak counter holds at `0` (`fixture_uncaptured`) until a real fixture lands. Completing this issue **and** #5889 flips ADR-079 `adopting → accepted`; this PR lands B only, so ADR-079 stays `adopting` and is **amended** (not flipped) here.

**Work target = #5913 only.** #5889 (soak) and the ADR flip-to-accepted are downstream and out of scope.

### Why this is viable (key precondition findings)

- **The SDK auto-detects `bwrap` via `PATH`.** `sdk.d.ts:5885` — `bwrapPath` overrides auto-detection but is "Only honored from admin-controlled managed settings," so a PATH shim is the correct (and only script-controllable) interception point. The whole `--capture` mechanism rests on this and it holds for the installed `@anthropic-ai/claude-agent-sdk@0.3.197`.
- **`ANTHROPIC_API_KEY` is a confirmed repo secret** (`gh secret list` → present since 2026-03-20; already consumed by `claude-code-review.yml`, `test-pretooluse-hooks.yml`, `fix-constraints-stage-a.yml`). Prerequisite 1 is satisfied — but **fork PRs receive no secrets**, so the gate must degrade (pass, fall back to the existing human ack) when the key is absent, never block on its absence.
- **`query()` options carry `sandbox`, `model`, `maxTurns`, `permissionMode`, `canUseTool`** (`sdk.d.ts:1612/1647/1673/1314/1791`), so a hermetic single-Bash-op drive with the real sandbox config attached is expressible.
- **The fixture is baked into the image** (`Dockerfile:154-155` COPYs both `sandbox-canary.mjs` and `sandbox-canary-argv.json`), and `ci-deploy.sh:445` replays it via `docker exec … --replay`. So committing a real captured fixture is what starts #5889's soak clock on the next image build.

## Research Reconciliation — Spec (issue) vs. Codebase

| Issue/ADR claim | Codebase reality | Plan response |
| --- | --- | --- |
| `--capture` "currently a stub (returns 3)" | Confirmed — `sandbox-canary.mjs:246` `return 3`; imports `buildAgentSandboxConfig` but `void`s it | Replace `runCapture` body with the real shim+drive; keep the lazy `await import()` (unit test `sandbox-canary.test.ts:150` asserts it) |
| Fixture stays `status:"uncaptured"` | Confirmed — `sandbox-canary-argv.json:3` | This PR flips it `uncaptured → captured` with a real, normalized argv (starts #5889 soak) |
| Confirm `ANTHROPIC_API_KEY` in CI | Present (repo secret); consumed by 3 workflows; **absent on fork PRs** | Gate self-skips (green) when absent; blocks only when present + real breakage |
| "Wire into the SDK-bump CI path" | `lockfile-sync` job runs `sdk-bump-sandbox-gate.sh` (parity + bump-detect + `sdk-bump-verified:` ack) | Add capture+verify+replay as an always-run required check that self-skips unless (bump detected ∧ creds present); block on drift or `sandbox_broken` |
| "assert the tool actually invoked bwrap" | The shim capture file is the in-surface probe | Retry-until-bwrap-observed; distinct non-fixture verdict `capture_no_bwrap` on N failures |
| `enumerateSiblingDenyPaths` returns readdir order | Confirmed — `agent-runner-sandbox-config.ts:98`; `sortDenyPaths` already exported for exactly this | Capture against a hermetic controlled `WORKSPACES_ROOT`; sort + prefix-normalize |

**Premise Validation note.** Checked: #5913 OPEN (not resolved); `sandbox-canary.mjs` is a real stub returning 3 (not "never built"); ADR-079 exists, status `Adopting`, with an explicit "Flip to `accepted` only when BOTH land" criterion; #5889 OPEN (dependent soak, has its own follow-through enrollment); #5875 CLOSED (parent umbrella — correctly not a work target). Mechanism check: the capture-in-CI / replay-at-deploy hybrid is exactly what ADR-079 **decided** (not a rejected alternative — the rejected alternative was a pure model-turn-at-deploy canary). No stale premise.

## User-Brand Impact

**If this lands broken, the user experiences:** a Concierge Bash sandbox that is silently down for **every tenant** after a future SDK bump (the #5873 incident shape) — because a wrong/false-green capture makes the deploy-time replay and the SDK-bump gate validate the wrong argv, so a profile-breaking bump ships green.

**If this leaks, the user's data is exposed via:** no direct data path — the capture drives a **synthetic** no-op Bash op against a hermetic throwaway workspace, with no operator/tenant data. The residual exposure vector is a **hostile committed fixture** (a hand-authored or corrupted `bwrapSetupArgv` that injects a command at replay) — mitigated by the existing fixture trust path (`buildBwrapInvocation` sanity filters + `--verify` byte-diff + image-bake), which this PR preserves and strengthens (the fixture is now SDK-captured, never hand-authored).

**Brand-survival threshold:** `aggregate pattern` — carried forward from ADR-079's CTO ruling (the failure mode is a fleet-wide sandbox outage detectable as an aggregate signal; the canary is still non-blocking dark-launch at this stage, so a single wrong capture does not immediately roll back). No per-PR CPO sign-off required; section present per Phase 2.6.

## Implementation Phases

### Phase 0 — Preconditions (verify before coding)
- Confirm installed SDK version `@anthropic-ai/claude-agent-sdk@0.3.197` (`package.json:24`) and that `bwrap` PATH auto-detection holds (grep `sdk.mjs`).
- Confirm the GH-hosted `ubuntu-latest`/`ubuntu-24.04` runner can build+drive the SDK with `ANTHROPIC_API_KEY` (the capture job).
- Decide the replay-in-CI surface: reuse the `sandbox-canary-regression.test.sh` docker-bwrap discrimination pattern (`--security-opt seccomp=<committed>`, userns via the guardrail-3 apparmor sysctl, self-validating SKIP).

### Phase 1 — Pure, LLM-free capture logic (RED → GREEN, vitest)
Extract and unit-test (in `sandbox-canary.test.ts`, no network/LLM) the deterministic pieces:
- `parseShimSetupArgv(rawArgv)` — split the shim's argv at the first `--`; the prefix is the SETUP argv (the shim execs the post-`--` no-op).
- `deterministicSiblingRoot()` → `{ root, ownWorkspacePath, prepDirs }` — a **fixed, non-symlinked** hermetic workspaces root (CTO §2: `realpathSync` in `enumerateSiblingDenyPaths` rewrites symlinked temp paths like `$RUNNER_TEMP`/macOS `/private/var`, drifting the byte-diff) with a **constant** UUID own-workspace and a **fixed, sorted** sibling set. Realpath-normalize the root before use.
- **Normalization happens at the INPUT, not the output** (CTO §2 correction): sort the enumerated sibling list feeding `buildAgentSandboxConfig` via the existing `sortDenyPaths`, so `enumerateSiblingDenyPaths`'s readdir order never perturbs the emitted argv. Do **NOT** post-hoc sort the emitted argv tokens — that would break `--tmpfs DIR` / `--bind SRC DEST` positional pairing.
- **Do NOT rewrite path values to look like prod** (CTO §2 + the #4932 trap): the committed argv legitimately carries the CI-runner absolute paths (own workspace via `--bind`, siblings via `--tmpfs`). The `sandbox_broken` verdict is a *syscall-level* EPERM (`unshare`/`mount`), independent of path values; at deploy the container's `prepDirs` `mkdirSync`s those exact paths before bwrap runs. Path values are load-bearing only for `--verify`'s CI-vs-CI self-consistency — hence the fixed root, not a prod-shaped rewrite.
- `assessCaptureOutcome({ captureFilePresent, setupArgv })` → `{ captured, reason }` — the retry-loop decision (LLM-free): a valid capture requires a non-empty setup argv containing a `--unshare-*` token; de-dupe if the SDK spawned bwrap more than once (init probe vs. the Bash-tool spawn) and select the split-unshare invocation.
Contract test: capture logic never hand-authors a `--unshare` literal (`sandbox-canary.test.ts:160` already guards this; keep it green).

### Phase 2 — `--capture` runtime orchestration (side-effecting; CI-only)
Replace `runCapture` (currently `return 3`):
1. Guard: require `SANDBOX_CANARY_CAPTURE=1` (existing) **and** `ANTHROPIC_API_KEY`; else `creds_absent` + a **reserved distinct non-fixture exit code** (CTO §1: `0`/`2`/`3` are taken by replay/env-error/stub — reserve `4` so CI distinguishes *capture broke* from *captured + profile EPERM'd*). No write.
2. Hermetic env: use `deterministicSiblingRoot()` (Phase 1) — a **fixed non-symlinked** root + constant UUID own-workspace + fixed sorted sibling set; `WORKSPACES_ROOT=$root`. Deterministic `enumerateSiblingDenyPaths`.
3. bwrap shim: write an executable to a temp `bin/`, prepend to `PATH`. The shim records everything before the first `--` (SETUP argv) as JSON to `$CAPTURE_FILE`, then `exec`s the post-`--` command so the Bash op succeeds and `query()` completes (real sandboxing unnecessary for argv capture — avoids needing userns in the capture job). Handle the multi-spawn case (init probe vs. Bash-tool spawn): capture the split-unshare invocation.
4. Drive: `await import()` the real `buildAgentSandboxConfig(ownWorkspacePath)` (keep lazy — unit test asserts it); `query({ prompt: <maximally directive single no-op Bash op>, options: { sandbox, model: <cheapest reliably-tool-calling model — verify the current model ID + per-token price against the claude-api reference at implementation time; do NOT hardcode from memory>, maxTurns: 1–2, permissionMode, cwd: ownWorkspacePath, allowedTools:["Bash"], canUseTool: <force-allow> } })`; iterate + discard messages until completion or the capture file appears.
5. Non-determinism bound (see dedicated section): retry up to `N` attempts, each under a **per-attempt wall-clock timeout** (total ceiling = `N × timeout`); break on capture; on `N` failures emit `capture_no_bwrap` + exit `4` (**non-fixture** — never overwrites the committed fixture).
6. Sort siblings **at input** (Phase 1 — NOT the output argv) + write `{status:"captured", sdkPackage, sdkVersion, bwrapSetupArgv, prepDirs}` to the fixture (atomic). No prod-shaped path rewrite (keep CI-runner paths; the EPERM verdict is path-value-independent).
7. Cleanup via `finally`/`EXIT` trap (learnings — `set -e` + failing subprocess skips scattered cleanup): remove the shim `bin/`, hermetic root, capture file; never persist `ANTHROPIC_API_KEY` to a temp file.
8. `--verify`: capture into a temp fixture, byte-diff against the committed one; non-zero on drift with a "commit the refreshed argv" message. (`--verify` is itself creds-gated — it re-captures.)

### Phase 3 — Commit the first real captured fixture (self-replay-green first)
CTO §4 (must-fix): in **one CI run**, `--capture` → **replay the freshly-captured argv against the committed `infra/seccomp-bwrap.json` and assert PASS** → only then commit. Do NOT bake a fixture that would emit `sandbox_broken` against the current (post-#5874, known-good-for-0.3.197) profile — that would seed #5889's very first soak deploy red. Flip `sandbox-canary-argv.json` `uncaptured → captured` (real argv + `sdkVersion:"0.3.197"`), update its `_comment` to "real-captured". Keep the regression fixture (`test-fixtures/sandbox-canary/split-unshare-argv.json`) DISTINCT (guardrail 1); update `sandbox-canary-regression.test.sh` A5b `uncaptured → captured`.

### Phase 4 — CI SDK-bump gate wiring (block on captured sandbox_broken; ack-fallback otherwise)
Add an **always-run required check** (new step in `lockfile-sync`, or a dedicated job) that detects the SDK bump (reuse `sdk-bump-sandbox-gate.sh`'s detection). CTO §3 (must-fix) — split the two outcomes:
- **When `ANTHROPIC_API_KEY` is present:** run `--capture`, then replay the captured argv against the **committed** `infra/seccomp-bwrap.json` via docker (guardrail-3 userns/apparmor pattern, self-validating SKIP), and parse the **verdict JSON** (not the exit code — `runReplay` always exits 0).
  - **Block the merge ONLY on a captured `sandbox_broken`** (deterministic, LLM-free once captured, scoped to SDK-bump PRs). Also run `--verify` and **block on drift** (forces committing the bump's refreshed argv).
  - **On capture-mechanism failure** (exit `4` / no bwrap after N / non-discriminating replay SKIP): do **NOT** hard-block — **fall back to requiring the `sdk-bump-verified:` ack** (a flaky/paid model turn must never block a merge — #4941 in CI form; fail-closed to a human, not red-on-flake).
- **When creds are absent** (fork PR): the check **passes** and the existing `sdk-bump-verified:` ack remains the guard — **degrade to the ack, never to silent green**.
- Scope: capture+replay runs only when a bump is detected (`package-lock.json` OR `agent-runner-sandbox-config.ts` OR `sandbox-canary.mjs` changed, per ADR-079's re-capture key set).
- **Known limitation (document, don't fix):** a creds-less SDK-bump PR cannot run `--verify`, so a stale baked fixture vs. the image's new SDK is caught only by the human ack — acceptable, the ack IS the attestation for creds-less bumps.

### Phase 5 — ADR-079 amendment (in-scope deliverable)
Amend `ADR-079-…md` "Deferred (tracked)" section: mark **Deferral B as landed/wired** (cite this PR/#5913), keep **status `adopting`** (Deferral A / #5889 soak still open), and reaffirm the flip-to-`accepted` criterion (BOTH B and A). No C4 change (see Architecture Decision section).

## Files to Edit
- `apps/web-platform/scripts/sandbox-canary.mjs` — real `runCapture` + `--verify`; export the new pure helpers.
- `apps/web-platform/test/sandbox-canary.test.ts` — unit tests for `parseShimSetupArgv` / `normalizeCapturedArgv` / `assessCaptureOutcome` (LLM-free).
- `apps/web-platform/infra/sandbox-canary-argv.json` — flip to real captured argv (Phase 3).
- `apps/web-platform/scripts/sandbox-canary-regression.test.sh` — A5b assertion `uncaptured → captured`.
- `.github/workflows/ci.yml` — capture/verify/replay gate wiring in `lockfile-sync` (or new job).
- `apps/web-platform/scripts/sdk-bump-sandbox-gate.sh` and/or `sdk-bump-sandbox-gate.test.sh` — if bump-detection is reused/exported for the capture gate.
- `knowledge-base/engineering/architecture/decisions/ADR-079-…md` — Deferral-B-landed amendment.

## Files to Create
- (maybe) `apps/web-platform/scripts/sandbox-canary-capture-gate.sh` + `.test.sh` — if the capture gate is cleaner as a dedicated script than inline ci.yml `run:` (keeps embedded shell testable — CTO/deepen to decide inline vs. extracted).

## Non-Determinism Bound (design)

The model turn is bounded so **the LLM is removed from the assertion path** (learning `2026-04-19-llm-sdk-security-tests-need-deterministic-invocation.md`): the model only decides *whether* the SDK builds+spawns bwrap, never *what* the fixture asserts (argv correctness is deterministic once captured, and `--verify`'s byte-diff is the assertion).

- **Retry/settle:** drive `query()` up to `N` attempts (default 3). After each, `assessCaptureOutcome` checks the shim capture file. Break on a valid capture.
- **Assert bwrap actually invoked:** a valid capture requires the shim wrote a non-empty SETUP argv containing a `--unshare-*` token; a completed turn with no bwrap invocation is NOT a capture. De-dupe multi-spawn (init probe vs. Bash-tool spawn).
- **Failure is loud, not silent:** after `N` attempts with no capture → verdict `capture_no_bwrap`, **reserved distinct exit code `4`** (CTO §1 — not `0`/`2`/`3`), **non-fixture**; never writes/overwrites the committed fixture with a guess. The gate reads exit `4` as *capture-mechanism broke → ack-fallback*, NOT *sandbox broken → block*.
- **Per-attempt wall-clock timeout + total ceiling:** `maxTurns` does NOT bound a network stall / `overloaded_error` backoff (CTO §1), so each attempt runs under an explicit wall-clock timeout; the worst case is bounded end-to-end at `N × timeout`. A hung turn times out and counts as a no-bwrap retry, never hangs CI.
- **Model / cost:** the turn's *output* is irrelevant (the shim execs a no-op; the SDK only needs to issue one Bash tool call). Pick the **cheapest model that reliably tool-calls** — verify the current model ID + per-token price against the `claude-api` reference **at implementation time**, do not hardcode `claude-sonnet-5` from memory. Small `maxTurns` (1–2) + `autoAllowBashIfSandboxed`. One cheap turn per SDK-bump PR (creds-gated), never on routine deploys; disclose the per-PR API cost.
- **Prompt:** a single maximally-directive no-op Bash directive (e.g. run `true` and stop) with `canUseTool` force-allowing Bash, minimizing the chance the model reasons instead of acting.

## Observability

```yaml
liveness_signal:
  what: capture verdict JSON on stdout (captured | capture_no_bwrap | creds_absent); --verify byte-diff result
  cadence: per SDK-bump CI run (capture gate); per deploy (replay, existing PR2)
  alert_target: CI job status (block on drift / sandbox_broken); Sentry event on faithful sandbox_broken (existing ci-deploy.sh path)
  configured_in: .github/workflows/ci.yml (capture gate); apps/web-platform/infra/ci-deploy.sh (replay)
error_reporting:
  destination: GH Actions ::error:: annotation (CI gate) + existing Sentry feature:"agent-sandbox" on deploy-time sandbox_broken
  fail_loud: true
failure_modes:
  - mode: model never invokes bwrap (non-determinism)
    detection: shim capture file absent after N retries → verdict capture_no_bwrap (in-surface probe from the capture process itself)
    alert_route: CI job non-zero + ::error:: (does NOT overwrite the committed fixture)
  - mode: captured argv drifts from committed on an SDK bump
    detection: --verify byte-diff non-zero
    alert_route: CI block + ::error:: "commit the refreshed argv"
  - mode: newly-bumped SDK's real argv EPERMs under committed seccomp (the #5873 shape)
    detection: docker replay bwrap stderr "Operation not permitted" → classifyReplayVerdict → sandbox_broken
    alert_route: CI block + ::error::
  - mode: creds absent (fork PR)
    detection: ANTHROPIC_API_KEY empty → verdict creds_absent
    alert_route: gate passes; falls back to sdk-bump-verified: human ack (no false block)
logs:
  where: GH Actions job logs (single-line verdict JSON, jq-parseable); Sentry (deploy-time)
  retention: GH Actions default; Sentry per project
discoverability_test:
  command: SANDBOX_CANARY_CAPTURE=1 node apps/web-platform/scripts/sandbox-canary.mjs --verify   # NO ssh
  expected_output: exit 0 + captured-argv match, or non-zero + drift/no-bwrap verdict on stdout
```

Affected-surface note (Phase 2.9.2): the agent sandbox is a blind execution surface; the capture verdict JSON is the **in-surface** probe emitted FROM the capture process, and its `reason` field discriminates the competing failure hypotheses (`capture_no_bwrap` vs. drift vs. `sandbox_broken` vs. `creds_absent`) in one event, not a single boolean.

## Architecture Decision (ADR/C4)

### ADR
Amend **ADR-079** (do NOT author a new one — this issue *is* deferral B of ADR-079). Mark Deferral B landed/wired, keep status `adopting`, reaffirm the BOTH-B-and-A flip criterion. In-scope task (Phase 5), not a follow-up issue.

### C4 views
**No C4 impact.** Enumerated against all three `.c4` files (`model.c4`, `views.c4`, `spec.c4`): (a) external human actors — none new (no correspondents/reviewers/recipients introduced; the capture drives a synthetic op); (b) external systems — the Anthropic LLM is already modeled (`model.c4:208` `anthropic`, edge `claude -> anthropic "LLM calls"` at `:281`); the CI capture reuses that same conceptual edge (CI drives the SDK which calls Anthropic) and CI is not a modeled actor; (c) containers/data-stores — the fixture JSON is a committed repo file, not a modeled data store; (d) access relationships — none change (no owner/tenancy/trust-boundary move). This is a CI test/capture harness, not a new system boundary. `deepen-plan` to re-confirm by reading the three files directly.

## Domain Review

**Domains relevant:** Engineering (CTO — ADR-079 is CTO-governed; the non-determinism bound and creds-gating are architecture rulings). Security is an *aspect* (sandbox/seccomp) but the change is a test/capture harness with no new data surface — covered at review by `security-sentinel` + `observability-coverage-reviewer` (blind-surface). No Product/UX (no files under `components/**`, `app/**/page.tsx`, `app/**/layout.tsx` — mechanical UI-surface override does NOT fire → Product NONE). No finance/legal/marketing/sales/support/ops implications.

### Engineering (CTO)
**Status:** reviewed (assessment spawned + folded into Non-Determinism Bound, Phase 3/4, and Sharp Edges).
**Assessment:** All five plan positions sound with refinements. Two **must-fix** before implementation: (§3) block the merge ONLY on a *captured* `sandbox_broken` verdict — fall back to the human `sdk-bump-verified:` ack on capture-mechanism failure or absent creds; never hard-block on a flaky/paid model turn (the #4941 false-rollback lesson in CI form). (§4) In the capture PR's CI, replay the freshly-captured fixture against the committed profile and assert PASS **before** committing it — do not seed #5889's first soak deploy red. Two **watch-items:** (§2) pin a **non-symlinked** hermetic root + constant uuid so `realpathSync` cannot drift the byte-diff, and sort the sibling **input** list (not the output argv tokens); (§5) reviewers must eyeball the argv fixture diff. Complexity MEDIUM (days); no new infra/secret. Route `observability-coverage-reviewer` + `security-sentinel` inline at review (existing agents — no capability gap).

## Acceptance Criteria

### Pre-merge (PR)
1. `runCapture` no longer returns the stub `3`; `SANDBOX_CANARY_CAPTURE=1 node sandbox-canary.mjs --verify` exits 0 against the committed fixture, and exits non-zero with a drift verdict when the fixture is mutated (test both directions).
2. `sandbox-canary-argv.json` has `status:"captured"`, a non-empty `bwrapSetupArgv` (first token a `--` option, no bare `--` separator, contains a `--unshare-*` token), and `sdkVersion:"0.3.197"`. `validateFixture` accepts it; `buildBwrapInvocation` builds `[...argv, "--", "true"]`.
3. Captured argv is **byte-reproducible**: two `--verify` runs in the same env produce identical bytes (sort + prefix-normalize verified by unit test on `normalizeCapturedArgv`).
4. `capture_no_bwrap` path: when the shim records no bwrap invocation, `--capture` exits non-zero **without** writing the fixture (unit-tested via `assessCaptureOutcome`; the committed fixture is unchanged on failure).
5. `sandbox-canary-regression.test.sh` A5b updated to assert the prod fixture is now `captured` and still DISTINCT from `split-unshare-argv.json`; the full `test-scripts` shard is green.
6. CI capture gate: on a simulated SDK bump with creds present, `--verify` drift **blocks**; a `sandbox_broken` replay **blocks**; with creds absent the gate **passes** and the `sdk-bump-verified:` ack remains required (verified via `sdk-bump-sandbox-gate.test.sh` + the new gate's test).
7. `sandbox-canary.test.ts` still asserts the lazy `await import()` and the no-hand-authored-argv contract (do not regress).
8. Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean; tests: `./node_modules/.bin/vitest run test/sandbox-canary.test.ts`.
9. ADR-079 amended (Deferral B landed, status still `adopting`).

### Post-merge (operator/automated)
- Next image build bakes the real fixture (`Dockerfile:154-155`); the deploy-time replay begins emitting real verdicts, starting #5889's soak clock. No separate operator action — the merge IS the remediation (container restart via `web-platform-release.yml`). #5889's existing follow-through enrollment closes the soak automatically.

## Test Scenarios
- Pure unit (vitest, LLM-free): argv split, normalization (sort + prefix rewrite) byte-stability, capture-outcome decision, empty/no-bwrap rejection.
- Gate shell test: bump-detected ∧ creds-present → verify/replay blocking; creds-absent → pass + ack fallback; no-bump → pass.
- Regression: `sandbox-canary-regression.test.sh` A-layer stays green with the prod fixture now `captured`.

## Risks & Sharp Edges
- **Determinism is the crux.** The captured argv embeds workspace paths; capture MUST run against a hermetic controlled `WORKSPACES_ROOT` (fixed sibling set) and normalize (sort + rewrite ephemeral root → `/workspaces`) or `--verify`'s byte-diff false-fails on every run. Unit-test `normalizeCapturedArgv` for idempotence and machine-independence.
- **Replay-in-CI faithfulness vs. bwrap version.** `sandbox-canary-regression.test.sh` found bwrap 0.11.x *combines* namespaces, so a *synthesized* argv could not reproduce the split-unshare EPERM. The **real captured** argv replayed under the committed profile is faithful by construction (it is the SDK's own invocation — the ADR-079 replay guarantee); keep the replay a self-validating SKIP where userns is unavailable, and **only block on a positive `sandbox_broken`**, never false-fail.
- **Do not overwrite the committed fixture on a failed capture** (the #4932 hand-authored-argv trap). Failure is a non-fixture exit.
- **`--verify` re-capture also needs creds** — so `--verify` in CI is itself creds-gated; the deterministic non-creds guard remains the `sdk-bump-verified:` ack + the structural regression proof.
- **Model choice / cost** — cheapest viable model for a trivial Bash op; bounded by small `maxTurns` + per-attempt timeout; disclose the per-SDK-bump-PR API cost (`hr-autonomous-loop-skill-api-budget-disclosure`).
- **`socat` is load-bearing in the bwrap argv** (`2026-04-19-socat-load-bearing-for-bwrap-sandbox.md`) — normalization must NOT strip socat/networking tokens from the captured SETUP argv; sort only the sibling-deny group and rewrite the root prefix, nothing else.
- **Replay needs the bwrap three-layer stack** (`bwrap-sandbox-three-layer-docker-fix-20260405.md`): docker replay must set seccomp (the committed profile under test) + AppArmor unconfined + rely on `enableWeakerNestedSandbox` (already in the config) + the userns sysctl (`kernel.apparmor_restrict_unprivileged_userns=0`, `2026-06-04-cron-silence-was-bwrap-userns-drift-not-turn-budget.md`). Reuse the exact guardrail-3 pattern from `sandbox-canary-regression.test.sh`; a partial stack silently fails, so a non-discriminating replay is a SKIP (never a false block).
- **Secret + temp-file hygiene** (`canary-crash-leaks-env-file-ci-deploy-20260406.md`): under `set -e`, a failing `docker run` exits before cleanup — use an `EXIT` trap to remove the shim `bin/`, the hermetic `WORKSPACES_ROOT`, and the capture file; never write `ANTHROPIC_API_KEY` into a temp file. Wrap any logging pipe with `set +o pipefail` (`2026-04-29-canary-layer3-mount-and-pipefail-traps.md`).
- **Dark-launch infra safety** (`2026-07-03-dark-launch-pr-must-exclude-operator-prerequisite-infra.md`): this PR's only infra-adjacent change is the fixture CONTENT (already COPYed by `Dockerfile:154-155`) — no new host/Doppler/operator prerequisite, so it is safe to apply on merge.
- **Verify the SDK drive signature empirically** (`2026-04-19-claude-agent-sdk-subprocess-exit-tag-via-stderr-substring.md`, `2026-05-18-claude-code-action-claude-args-vs-direct-cli-form-drift.md`): the capture drives `query()` directly (not the `claude` CLI), but Phase 0 must confirm the `query()` option shape + the `"sandbox required but unavailable"` failure substring against the installed SDK, not memory.
- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan` Phase 4.6 — this one is filled.

## Research Insights (institutional learnings)
- `best-practices/2026-04-19-llm-sdk-security-tests-need-deterministic-invocation.md` — **capture-once-then-replay is THE prescribed pattern** for LLM-mediated security gates; the model must not sit in the assertion path. Directly validates this plan's shape.
- `security-issues/2026-04-19-socat-load-bearing-for-bwrap-sandbox.md`, `security-issues/bwrap-sandbox-three-layer-docker-fix-20260405.md`, `2026-06-04-cron-silence-was-bwrap-userns-drift-not-turn-budget.md` — bwrap replay constraints (see Sharp Edges).
- `2026-05-16-repo-research-must-inventory-scheduled-ci-workflows-for-secret-sweeps.md` — fork PRs lack secrets; branch the gate on creds presence (this plan's Phase 4).
- `security-issues/canary-crash-leaks-env-file-ci-deploy-20260406.md`, `2026-04-29-canary-layer3-mount-and-pipefail-traps.md` — shell/secret hygiene for the gate + capture scripts.
- `2026-07-01-sandbox-observability-gate-signal-timing-and-affected-users-alert.md` — verify a phase-gate signal's actual timing; Sentry counts `user.id` not `extra` (relevant to the existing deploy-time event, unchanged here).

## Open Code-Review Overlap
Queried `gh issue list --label code-review --state open` against every Files-to-Edit path. **One nominal match, acknowledged (not folded in):**
- **#2965** (build-time critical-CSS extractor for Eleventy docs) names `ci.yml` — but its concern is the Eleventy docs build, an entirely different area of `ci.yml` than the `lockfile-sync` SDK-bump job this plan touches. **Disposition: acknowledge** — different concern, own cycle; this plan does not fix or interact with it.

No other edited path (`sandbox-canary.mjs`, `sandbox-canary.test.ts`, `sandbox-canary-argv.json`, `sandbox-canary-regression.test.sh`, `sdk-bump-sandbox-gate*`, `ADR-079`) has an open code-review overlap.

## Skill/AGENTS budget note
No `plugins/soleur/skills/*/SKILL.md` `description:` edit and no new AGENTS.md rule — Phase 1.8 / cq-skill-description-budget-headroom N/A.
