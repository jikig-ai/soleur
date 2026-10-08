---
title: "fix: agent sandbox hardening — /proc mask realized, deny root follows the workspace resolver, support persona stops minting repo credentials"
type: fix
date: 2026-10-08
slug: fix-sandbox-hardening-cluster
branch: feat-one-shot-9723-9725-9558-sandbox-hardening
issue: 9723
closes: [9723, 9725, 9558]
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix: agent sandbox hardening cluster (#9723, #9725, #9558)

`lane: cross-domain` — no `spec.md` exists for this branch (the three issues arrived as a direct plan request, no brainstorm); the default is carried per the plan skill's lane rule. `requires_cpo_signoff: true` — `single-user incident` threshold (a cross-tenant credential leak through `/proc/<pid>/environ` is the named blast radius). CPO sign-off is required on the plan/PR; at review time `soleur:engineering:review:user-impact-reviewer` must be in the seat list.

## Overview

Three security-boundary defects on the hosted agent path, all surfaced by the PR #9709 review panel (MERGED — the constant parent-deny change) or the PR #9540 review, and all fixable without new infrastructure:

1. **#9723 (P1)** — the vendored CLI 2.1.284 builder's `enableWeakerNestedSandbox` handling appends `--bind /proc /proc` as the LAST setup token (position 118-119 of the committed `sandbox-canary-argv.json` fixture), re-mounting the container's real procfs over the `--tmpfs /proc` that the `denyRead` entry emits early (position 20). Later mounts win: inside the sandbox `/proc` shows every process in the container, including other tenants' concurrent CLI/bwrap children, and same-uid `/proc/<pid>/environ` exposes `GIT_INSTALLATION_TOKEN` and session env. The defect is already documented in-tree as the `KNOWN TAIL CAVEAT` comment in `agent-runner-sandbox-config.ts`.
2. **#9725 (P2)** — `buildAgentSandboxConfig` denies `WORKSPACES_ROOT` while `workspacePathForWorkspaceId` resolves under `WORKTREE_ROOT` (`/var/lib/soleur/worktrees`) once `GIT_DATA_STORE_ENABLED` flips (ADR-068 PR-C cutover). Post-flip, the only Bash-level cross-tenant guard masks an empty root and `--ro-bind / /` exposes every sibling workspace.
3. **#9558 (P2)** — a `persona:"support"` dispatch (read-only per ADR-113) still mints a GitHub App installation token, injects `GH_TOKEN`/`GIT_INSTALLATION_TOKEN`, writes `.soleur-askpass.sh` into the user's `.git/`, and opens `ENTITLED_EGRESS_DOMAINS` — none of it gated on `mode.sandboxWrite`/`mode.runRepoLifecycle`.

## Research Reconciliation — Issue claims vs. codebase

| Issue / brief claim | Reality (verified this session) | Plan response |
|---|---|---|
| #9723: "the argv ends with `--bind /proc /proc`" | Confirmed: `jq .bwrapSetupArgv[-12:]` on the committed fixture ends `--bind /proc /proc` (tokens 118-119 of 120); `--tmpfs /proc` sits at position 20 | Fix lands at the shim, not the builder. |
| #9723: "shim-level argv rewrite" is an option | The shim (`infra/bwrap-shim/bwrap`) scans only OUTER argv; `--args FD` carries the whole setup argv as a NUL pipe the shim refuses to read (consuming it would starve bwrap). The fixture's payload carries NO `--` — the command boundary lives in the OUTER argv (`bwrap --args N -- cmd`), proven by `runArgsFdTransportProbe` (`spawnSync("bwrap", ["--args","3","--","/usr/bin/true"])`) and `parseShimSetupArgv` | Insert `--tmpfs /proc` in the outer argv immediately before the first `--` — lands AFTER the expanded payload, hence after the tail bind. Verified live on bwrap 0.12.0 (this session): `bwrap --args 3 --tmpfs /proc -- sh -c …` yields empty `/proc`. VERSION DELTA: the deployed image pins Bookworm `bubblewrap` 0.8.0 (`Dockerfile:126`) — the ordering semantic is the documented one (bwrap(1): mount ops "applied in the order they are given") and the Phase-2 `proc_mask` probe is the in-image verification on the real version. Defensive arm for a future payload-carried `--` reads+rewrites the payload fd rather than failing soft. |
| #9723: fixture "must be regenerated via the capture gate" | The capture shim records the SDK-EMITTED argv (payload + outer split at first `--`); our shim's injection happens BELOW that seam, so the captured fixture is byte-identical. What actually breaks is the `fd_census` replay probe (`ls /proc/self/fd` inside the sandbox → `canary_infra_error` under a real tmpfs `/proc`) | No re-capture for #9723 itself; the probe suite is redesigned instead. The fixture DOES drift under #9725's dual-root deny (see below) — one re-capture task serves it. |
| #9725: "`getWorkspaceWorktreeRoot` returns `WORKTREE_ROOT` when enabled" | `workspace-resolver.ts:69-72` — flag-on → `process.env.WORKTREE_ROOT || "/var/lib/soleur/worktrees"` and flag-off → `getWorkspacesRoot()` (dedupes to the same root). `getWorkspaceWorktreeRoot` is currently PRIVATE (line 69); `isGitDataStoreEnabled` is exported (line 56) | Deny BOTH roots flag-independently (Option A), not only the resolver's effective root — see Proposed Solution for why. |
| #9725: "add this check to the git-data cutover gate (`infra/lb-weight-gate.sh` / `git-data-flag-precheck.sh` callers)" | Both exist. `apps/web-platform/infra/lb-weight-gate.sh` is the ADR-143 D3 anti-pooling gate (web-2 serving-weight top-guard + Conditions A/B; env-pure by design — "reads ONLY injected env"), and its Condition B already requires `GIT_DATA_STORE_ENABLED=="true"` — pooling cannot precede the flip, so the flip is the chokepoint. `git-data-flag-precheck.sh` (`:206-215` TOFU_ARM source-grep pattern) + `flip_preconditions` in `.github/workflows/git-data-cutover.yml:213-282` run AT the flip | The deny-roots check lands at the flip: a blocking `SANDBOX_DENY_ROOTS` arm in the flag precheck (flip mode) + a `GIT_DATA_DENY_FLOOR` deployed-image check in `flip_preconditions`. Adding an env predicate to `lb-weight-gate.sh` Condition B was evaluated and rejected — it would break the gate's env-pure contract for zero coverage gain (the flip already can't complete without the precheck). |
| #9558: mint at "`~:2290`", askpass at "`~:2584`" | Mint is `cc-dispatcher.ts:2340-2355` (`if (effectiveInstallationId !== null)`), egress derive `:2356-2363`, askpass write `:2656-2662`, env threading `:2876-2880`. Additionally the dispatch-time clone `ensureWorkspaceRepoCloned` at `:2249` is UNGATED for support (a host-side write from a touch-nothing persona) and `resolveEffectiveInstallationId` at `:1993` runs unconditionally | Gate the whole repo-credential surface under the mode predicate; the clone + install-resolution joins the gated set (same ADR-113 invariant as the already-gated `ensureWorkspaceDirExists` at `:2013` and the write-lease at `:2812`). |
| Implicit: "service tokens are fine for support" | `getUserServiceTokens` (`:1820`) is fetched for every dispatch and threaded into `buildAgentEnv` (`:2874`); a read-only kb-search-only support session has no Connected-Services need for them and sandboxed `env` can exfiltrate them | Fold-in candidate (marked `inferred` in Scope Check — one conditional, same predicate; reviewers may cut). |
| PR #9709 mechanism | `gh pr view 9709` → MERGED `fix(web-platform): constant parent denyRead on vendored deny-then-restore ordering (#5862)` | This plan is the follow-up the merged review panel filed. |

## Problem Statement / Motivation

The sandbox's tenant-isolation story currently holds in *configuration* but not in *the wire argv* (#9723), and holds only against the *pre-cutover* root (#9725). The support persona's "touch nothing" contract holds for the filesystem write-set but not for the *credential surface* (#9558). All three are silent, in-flight failures of the same class: the deployed boundary is weaker than the declared one. Brand-survival framing: one tenant's `GIT_INSTALLATION_TOKEN` readable from another tenant's `/proc` is a single-user incident with cross-tenant blast radius.

## Proposed Solution

### FR1 (#9723) — realize the `/proc` mask at the shim layer

`infra/bwrap-shim/bwrap` gains an argv-tail-mask arm in front of the existing exec:

- **Arm A (today's shape):** first literal `--` in `"$@"` → splice `--tmpfs /proc` immediately before it. Verified live: `bwrap --args <fd> --tmpfs /proc -- <cmd>` → in-sandbox `/proc` is an empty tmpfs.
- **Arm B (defensive):** no outer `--` but ≥1 `--args <fd>` → read each args fd's NUL-separated payload in order (`mapfile -d ''`), locate the first `--` inside any payload and splice before it (else append to the LAST payload); re-emit each consumed payload through a fresh pipe via `exec {fd}< <(printf '%s\0' …)` and substitute the new fd number into the outer argv. Unreadable/malformed payload → `fail` (65).
- **Arm C:** no `--`, no `--args` → insert before the first non-option/non-value token (the shim's existing arity walk already classifies values); a pure-options argv gets the token appended.
- Unresolvable shapes still fail closed (exit 65, `bwrap-shim:` marker) — never exec an unmasked spawn.

Rationale for the layer: the vendored builder owns the payload and cannot be patched without supply-chain infrastructure the repo lacks (ADR-075 alternative C); the config layer cannot beat a vendor-appended token; the shim is the last in-image chokepoint before the real binary.

### FR2 (#9725) — deny both tenant-workspace roots, flag-independently

- `workspace-resolver.ts`: export a `workspaceTenantDenyRoots()` helper returning the deduped set `{ getWorkspacesRoot(), process.env.WORKTREE_ROOT || WORKTREE_ROOT_DEFAULT }` — the raw worktree root unconditionally, NOT `getWorkspaceWorktreeRoot()`'s flag-collapsed form (the transition window where the cutover stage populates the worktree root while the flag is still off is exactly when staged tenant data needs masking).
- `agent-runner-sandbox-config.ts`: `denyRead = new Set([...workspaceTenantDenyRoots(), c4StagingRoot, "/proc", ...denyReadExtra])`. The catastrophic-misconfig throw checks `workspacePath` against BOTH roots; the `tenant-deny` log gains `worktreeRoot`, `gitDataStoreEnabled`, `worktreeRootExists` and a `workspaceUnderEffectiveRoot` field (strict-descendant of the resolver's effective root — the drift tripwire #9725 names). The prod `WORKSPACES_ROOT missing` Sentry arm extends to the effective root.
- The vendored builder skips non-existent deny landings, so flag-off argv is unchanged on hosts without the worktree dir — BUT the capture harness sets `WORKTREE_ROOT` to a fixed canary path (`/tmp/soleur-sandbox-canary-worktrees`) so the emitted argv deterministically carries both roots and the re-captured fixture pins their ordering.
- Cutover gate: `git-data-flag-precheck.sh` gains a `SANDBOX_DENY_ROOTS` arm (blocking `refuse` under `FLAG_MODE=flip`, informational otherwise) grepping the checkout's `agent-runner-sandbox-config.ts` for worktree-root coverage; `git-data-cutover.yml` `flip_preconditions` gains a `GIT_DATA_DENY_FLOOR` arm (same `ver_le` + `/health` semver pattern as `live_image_stale`) so a flip cannot run against an image predating the deny fix. Both arms' refusal messages name the remedy, never "flip anyway".

### FR3 (#9558) — persona-gate the repo-credential surface

In `cc-dispatcher.ts` `realSdkQueryFactory`, under the existing `mode` object:

- `resolveEffectiveInstallationId` (`:1993`), `ensureWorkspaceRepoCloned` + `consumeDispatchCloneOutcome` (`:2249-2284`), and the mint (`:2340-2355`) are gated by `mode.runRepoLifecycle` (clone/resolution are repo-lifecycle ops; the mint additionally requires `mode.sandboxWrite !== "none"` per the issue's predicate — `runRepoLifecycle` implies it today and the FR states both).
- `ghToken` stays `undefined` for support → askpass write (`:2657`), `GH_TOKEN`/`GIT_INSTALLATION_TOKEN` env injection (`:2876-2880`), and `allowGithubEgress` widening (`:369`) all collapse to off by construction — the issue's "both-or-nothing".
- The `githubEgress` log.info gains `persona` so a `persona="support" githubEgress=true` row is a pageable breach signal.
- `GH_NO_NETWORK_PROMPT_ADDENDUM` (`:2573`) now always fires for support — already truthful (no egress), no change.
- `serviceTokens` for support: recommended fold-in — `mode.sandboxWrite === "none" ? {} : await getUserServiceTokens(...)` (same-invariant, one conditional; flagged `inferred` — see Scope Check).

## Technical Considerations

### Attack Surface Enumeration (security-fix requirement)

Ways an in-sandbox process can reach another tenant's data/credentials today:

- `/proc/<pid>/environ`, `/proc/<pid>/cmdline` — **checked by FR1** (tmpfs mask lands last).
- Direct sibling-tree reads via `--ro-bind / /` — **checked by FR2** for the post-cutover root; already covered for `/workspaces`.
- `env`/`printenv` in sandboxed Bash — Anthropic creds already denied (W1, `credentials.envVars`); `GH_TOKEN`/`GIT_INSTALLATION_TOKEN`/service tokens remain reachable — **FR3 narrows the support-persona set**; command-center tokens intentionally stay (ADR-272 deferral to #9543 broker).
- Network egress exfil — `allowManagedDomainsOnly` + empty `allowedDomains`; **FR3 keeps support at the closed default**.
- Unsandboxed commands — `allowUnsandboxedCommands: false` already closed.
- `--args`/fd-injection argv smuggling — shim fd sweep + preserve-set already covers; FR1's Arm B reads payloads only into a rewritten pipe, never into the exec'd fd table unchecked.

Unchecked-but-safe: in-process MCP tools and hooks run outside bwrap with the parent env (recorded out-of-scope in ADR-272's spawn table — unchanged by this plan).

### Behavior-change disclosure

Under a real empty `/proc`, in-sandbox `ps`/`pgrep`/`top`/`lsof` and `/proc/self/*` reads fail. That is the ADR-075 deny intent being *realized*, not a regression — but it is user-visible on agent Bash commands that introspect processes. The plan's Observability + changelog carry it.

## User-Brand Impact

- **If this lands broken, the user experiences:** every hosted agent session failing to spawn (`bwrap-shim:` exit-65 → "sandbox required but unavailable"), or support chat dead-ending on repo-readiness errors if the gate over-fires.
- **If this leaks, the user's data/money is exposed via:** a prompt-injected (or merely concurrent) agent reading another tenant's `GIT_INSTALLATION_TOKEN`/`GH_TOKEN`/`ANTHROPIC_*` out of `/proc/<pid>/environ`, or a support session minting a repo-scoped write token and shipping it to github.com through widened egress.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** cross-tenant credential exposure harms a second user through the first user's session — the failure is not contained to the actor's account, which is precisely the `single-user incident` tier's lower bound; `aggregate pattern` would be for systemic multi-tenant sweeps.

## Observability

```yaml
liveness_signal:
  what: "Deploy-time sandbox canary replay verdict (sandbox-canary-verify-in-image.sh in web-platform-release.yml chain) + boot self-probe verifyAgentSandboxHardening (op=sandbox-hardening-selfprobe)"
  cadence: "per deploy + once per container boot"
  alert_target: "deploy blocks on non-pass canary verdict; Sentry warn on self-probe failure"
  configured_in: "apps/web-platform/server/agent-runner-sandbox-config.ts (verifyAgentSandboxHardening); apps/web-platform/scripts/sandbox-canary.mjs (runHardeningProbes)"
error_reporting:
  destination: "Sentry (feature=agent-sandbox / feature=cc-dispatcher); pino → Vector → Better Stack"
  fail_loud: "bwrap-shim: <reason> stderr + exit 65 → spawn failure → 'sandbox required but unavailable' surfaced in-chat and mirrored (op=sdk-startup); tenant-deny emit + reportSilentFallback for a missing deny root"
failure_modes:
  - mode: "SDK argv shape drift (no '--', no '--args', malformed payload)"
    detection: "shim exit 65 → canary verdict bwrap_shim_refused pre-deploy; in prod, sdk-startup Sentry events"
    alert_route: "deploy gate + Sentry feature=agent-sandbox"
  - mode: "fd_census redesign regression (probe bound wrong)"
    detection: "canary verdict fd_census_* / canary_infra_error blocks deploy"
    alert_route: "deploy gate (loud, safe direction)"
  - mode: "deny root missing in prod (vanished mount / flag-on without worktree dir)"
    detection: "reportSilentFallback 'WORKSPACES_ROOT missing' extended to the effective root + worktreeRootExists=false in per-dispatch tenant-deny emit"
    alert_route: "Sentry feature=agent-sandbox"
  - mode: "support-persona credential gate regresses (mint fires for support)"
    detection: "per-dispatch 'Concierge sandbox GitHub egress posture' log gains persona; query persona=support AND githubEgress=true; unit tests RED"
    alert_route: "Better Stack log query + CI"
logs:
  where: "pino stdout → Vector → Better Stack (feature=agent-sandbox, op=tenant-deny); Sentry warnSilentFallback/reportSilentFallback"
  retention: "Better Stack retention window (existing)"
discoverability_test:
  command: "bash apps/web-platform/infra/sandbox-hardening-contract.sh"
  expected_output: "sandbox-hardening-contract:ok"
```

The contract script (created in this PR) is a static source-level check that the three guards are present (shim tail-mask splice, worktree-root deny entry, `sandboxWrite !== "none"` mint gate) — it exists because the real observability signals (canary verdicts, per-dispatch emits) are not locally readable without credentials, per the established `escrow-split-contract:ok` precedent.

## Encryption Posture

Skipped — no new persistent store and no new cross-component/network connection. The plan *narrows* an existing egress allowlist for one persona; no TLS/cert-verification surface is added or relaxed.

## Guard Contract

### Guard 1 — realized /proc mask

**Property.** Every sandbox-building bwrap spawn through the PATH shim mounts an empty tmpfs at `/proc` AFTER any vendor-emitted `/proc` bind — i.e. the last procfs-touching setup token is ours.

**Assembly.** All bwrap invocations that reach `infra/bwrap-shim/bwrap` with a setup argv (argc>1, non-probe): the SDK's `--args`-transported spawn, the canary replay's argv-form spawn, any future caller. Chokepoint is the single `exec "$REAL" …` in the shim; there is no second bwrap caller in the image (capture uses a throwaway shim upstream of it).

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Shim execs `"$@"` verbatim (insertion removed) | RED — bwrap-shim.test.ts asserts `--tmpfs /proc` lands after `--args` payload tokens / before `--`; real-bwrap row asserts in-sandbox `/proc/self/environ` absent |
| 2 | Insertion moved AFTER the `--` boundary (lands in command argv) | RED — same position assertion; in-sandbox `/proc` stays populated |
| 3 | Payload-rewrite arm drops the mask when `--` lives inside `--args` payload | RED — fake-bwrap row asserting the rewritten payload contains the mask before its `--` |
| 4 | Second `--` earlier in argv (command tail `--` first) — splice must target the FIRST `--` | RED — row asserting insertion index |

### Guard 2 — dual-root deny

**Property.** `denyRead` covers every root that can hold tenant workspaces at any flag state.

**Assembly.** `workspaceTenantDenyRoots()` in workspace-resolver.ts is the single producer; `buildAgentSandboxConfig` is the single consumer; the cutover precheck is the structural tripwire.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Drop `WORKTREE_ROOT` from the deny set | RED — tenant-deny suite asserts both envs honored; flag-precheck `SANDBOX_DENY_ROOTS` arm refuses on flip |
| 2 | `GIT_DATA_STORE_ENABLED=true` + `WORKTREE_ROOT=/x` → workspace under `/x` — deny must include `/x` | RED — env-stubbed suite case |
| 3 | workspacePath equal/containing the worktree root | RED — catastrophic-guard throw extends to the second root |
| 4 | Guard's own enumeration weakened (deny list asserted as length only, members unchecked) | RED — membership assertions per root, not count |

### Guard 3 — support credential gate

**Property.** `persona:"support"` dispatches never mint an installation token, write an askpass helper, run a repo clone, resolve installations, or widen egress.

**Assembly.** `realSdkQueryFactory` is the sole dispatch path for the support persona (the legacy `startAgentSession` path carries no support persona — `resolveWorkspaceMode` is only consulted on the cc path).

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Mint gate removed (`effectiveInstallationId !== null` alone) | RED — support+connected-repo test asserts `generateInstallationToken` not called |
| 2 | Askpass write ungated | RED — `writeAskpassScriptTo` not called under support |
| 3 | `ensureWorkspaceRepoCloned` re-ungated for support | RED — support test asserts zero clone calls |
| 4 | Egress derived independently of token | RED — `buildAgentSandboxConfig` asserted `allowGithubEgress:false` under support |
| 5 | A second `sandboxWrite` value added that isn't `"none"`/`"workspace"` | RED — union exhaustiveness (`_exhaustive: never` rail exists in resolveWorkspaceMode; the gate predicate is `!== "none"`, stays correct for any non-none member) |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "#9723 — P1 security issue: vendored CLI appends `--bind /proc /proc` at argv tail under `enableWeakerNestedSandbox`, shadowing the earlier `--tmpfs /proc`" | FR1 + Guard 1 + Phases 1-2 | mapped |
| 2 | "#9725 — P2 security issue: `buildAgentSandboxConfig` denies `WORKSPACES_ROOT`, while `workspacePathForWorkspaceId` may resolve under `WORKTREE_ROOT` after ADR-068 cutover" | FR2 + Guard 2 + Phase 3 | mapped |
| 3 | "#9558 — P2 bug/security issue: support persona still mints GitHub installation credentials, writes `.soleur-askpass.sh`, and opens `ENTITLED_EGRESS_DOMAINS`" | FR3 + Guard 3 + Phase 4 | mapped |
| 4 | "the plan must be treated as still requiring validation before implementation" (carry-forward on shim approach) | Research Reconciliation row 2 — mechanism verified live on bwrap 0.12.0 this session; Arms B/C handle shape drift | mapped |
| 5 | "fixtures under `sandbox-canary-argv.json` must be regenerated via the capture gate" (#9723 issue body, conditional) | Phase 3 re-capture task (the #9725 dual-root deny is what actually drifts the fixture; #9723's shim injection is below the capture seam) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| FR1 shim argv rewrite | "Shim-level argv rewrite (the `infra/bwrap-shim` PATH shim already rewrites argv for #8752 fd hygiene)" | asked |
| FR1 Arm B payload rewrite | none — defensive arm for a shape the current SDK does not emit | inferred — justified: fail-closed on an undocumented shape would turn an SDK patch bump into a full agent outage; the rewrite arm is the same guarantee at lower blast radius |
| FR2 dual-root deny | "include BOTH roots in the deny set during the cutover window" | asked (strengthened to unconditional — the window cannot be bounded by the flag's own value) |
| FR2 cutover-gate check | "Add this check to the git-data cutover gate" | asked |
| FR3 mint/askpass/egress gate | "skip the mint, the askpass write, and the egress widening when `mode.sandboxWrite === "none"`" | asked |
| FR3 clone + install-resolution gating | "None are gated on `mode.runRepoLifecycle`/`persona`" (#9558 body) | inferred — the issue names the predicate; the clone at :2249 and install-resolution at :1993 are the same ADR-113 repo-lifecycle class (a host-side write / GitHub-API surface from the touch-nothing persona) — folding them in is the issue's own predicate applied to the two sites its enumeration missed |
| FR3 serviceTokens fold-in | none | inferred — a read-only kb-search persona has no Connected-Services need for service tokens in its Bash env; one conditional; reviewers may cut without touching FR3's asks |
| fd_census probe redesign | none | inferred — forced: the probe reads `/proc/self/fd` inside the sandbox and goes `canary_infra_error` under the realized mask; the plan cannot ship FR1 without it |
| Canary fixture re-capture | "must be regenerated via the capture gate" | asked (conditional — triggered by FR2's argv change, not FR1) |
| ADR-075/ADR-113 addenda + C4 disposition | "a plan that changes a trust boundary or ADR must decide amend/create/no-impact" | asked (pipeline rule) |

### Split Assessment

- Subsystems touched: 4 roots — `apps/web-platform/server/`, `apps/web-platform/infra/` + `apps/web-platform/scripts/`, `apps/web-platform/test/`, `.github/workflows/` + `knowledge-base/` (ADR addenda).
- Planned files: ~15 | Estimated changed lines: ~450
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: **single PR** — the three fixes share one verification surface (the shim + canary + dispatcher tests), are one security story at review, and the probe redesign is structurally coupled to FR1; files/lines stay well under the split thresholds. (FR-coupling note: splitting #9723 into its own PR was considered and rejected — the fd_census redesign it forces is wasted if #9725's re-capture lands separately.)

## Implementation Phases

Each phase is RED-first (failing test rows land before the behavior change), then the change, then GREEN.

### Phase 1 — shim tail-mask (#9723 core)

- 1.1 Extend `apps/web-platform/test/bwrap-shim.test.ts` with rows for Guard 1's matrix: insertion before first `--`; after-`--args`-payload ordering (fake-bwrap records `ARG`/`PAYLOAD` lines — assert the mask sits between the last setup token and `--`); Arm B payload-rewrite row (payload carrying its own `--`); Arm C positional-boundary row; fail-closed rows for malformed args fd.
- 1.2 Implement the three arms + fail-closed in `infra/bwrap-shim/bwrap`, keeping probe passthrough and the fd sweep unchanged. Header comment updated: the shim now rewrites argv (documents the new trust role).
- 1.3 `apps/web-platform/test/sandbox-isolation.test.ts` FR7 + `apps/web-platform/test/helpers/sandbox-isolation-fixtures.ts`: build the harness argv from the REAL captured shape — append the vendor tail `--bind /proc /proc` to the helper's emitted setup argv and run the spawn THROUGH the shim (`SOLEUR_BWRAP_REAL`/`SOLEUR_BWRAP_SECCOMP_BPF` env overrides, shim dir first on PATH for the spawned process only) so FR7 measures the deployed chain, not a paraphrase of it.
- 1.4 `apps/web-platform/test/sandbox-credential-deny-runtime.test.ts` (or a sibling `sandbox-proc-mask-runtime.test.ts`): two-arm behavior probe — CONTROL (shim bypassed) asserts `/proc/self/environ` exists; TREATMENT (shim on PATH) asserts `/proc` is empty. Pins the OUTCOME, claims no mechanism (per the #9601/PR #9599 sharp-edge: outcome, not mechanism).

### Phase 2 — canary probe redesign (coupled to Phase 1)

- 2.1 `apps/web-platform/scripts/sandbox-canary.mjs`: replace the `fd_census` probe's `ls /proc/self/fd | wc -l` with a procfs-free POSIX-sh fd enumeration (`eval` redirect-existence probe over fds 3..63, read- then write-mode) and re-derive `fdLimit` for the new enumerator (no `ls` transient dir fd). Add a fourth probe `proc_mask`: inside the replayed sandbox `test -e /proc/self/environ` MUST fail AND `ls /proc` MUST be empty — the deploy-time proof that the realized mask holds in the shipped image.
- 2.2 `apps/web-platform/scripts/sandbox-canary-regression.test.sh`: update D3's probe-payload assertion to the new enumerator's marker (drop the `/proc/self/fd` literal); add an assertion that `runHardeningProbes` includes `proc_mask`.
- 2.3 `apps/web-platform/test/sandbox-canary.test.ts`: unit rows for the new classifiers — empty-`/proc` treatment passes, populated-`/proc` control arm classifies `sandbox_broken` (`proc_mask_bypass`), unparseable/spawn errors keep `canary_infra_error`.

### Phase 3 — dual-root deny + cutover gate (#9725)

- 3.1 `workspace-resolver.ts`: export `workspaceTenantDenyRoots()` (deduped raw roots) — keep `getWorkspaceWorktreeRoot` private; the deny helper is the one exported surface.
- 3.2 `agent-runner-sandbox-config.ts`: deny set via the helper; extend the catastrophic-misconfig throw and `workspaceUnderDenyRoot`/missing-root Sentry arm to both roots + effective-root drift fields; update the module header (`KNOWN TAIL CAVEAT` → realized-by-shim note) and the `deniedCount` comment.
- 3.3 `apps/web-platform/test/agent-sandbox-tenant-deny.test.ts` (+ `agent-runner-sandbox-config.test.ts`): env-stubbed rows for Guard 2's matrix (WORKTREE_ROOT set/unset × flag on/off; workspace under each root; catastrophic shapes for both roots).
- 3.4 `git-data-flag-precheck.sh`: `SANDBOX_DENY_ROOTS` arm — `grep` the checkout's `agent-runner-sandbox-config.ts` for worktree-root coverage; `refuse` on `FLAG_MODE=flip`, informational line otherwise (TOFU_ARM pattern). Plus a `git-data-flag-precheck.test.sh` row.
- 3.5 `git-data-cutover.yml` `flip_preconditions`: `GIT_DATA_DENY_FLOOR` arm — `[[ -n "${GIT_DATA_DENY_FLOOR:-}" ]] || fail …` then `ver_le` against `/health` version; refusal message instructs setting the var to the first release carrying this PR (same posture as `GIT_DATA_EMITTER_FLOOR` — an operator-set vars value inside an already operator-gated dispatch workflow, not a new manual step).
- 3.6 Canary re-capture: set `WORKTREE_ROOT=/tmp/soleur-sandbox-canary-worktrees` in the capture harness env, run the creds-gated `--capture`/`--verify` path (`sdk-bump-sandbox-gate.sh` / capture workflow), commit the regenerated `sandbox-canary-argv.json` with both deny roots pinned.

### Phase 4 — support credential gate (#9558)

- 4.1 `apps/web-platform/test/cc-dispatcher-real-factory.test.ts`: support+connected-repo cases — `generateInstallationToken`, `writeAskpassScriptTo`, `ensureWorkspaceRepoCloned`, `resolveEffectiveInstallationId` NOT called; `buildAgentSandboxConfig` asserted `allowGithubEgress:false`; egress-posture log asserted to carry `persona`. Command-center regressions: mint/askpass/clone still fire (existing AC1/askpass rows remain green).
- 4.2 `cc-dispatcher.ts`: gate `resolveEffectiveInstallationId` (:1993), the `ensureWorkspaceRepoCloned`+`consumeDispatchCloneOutcome` block (:2249-2284), and the mint (:2340) under `mode.runRepoLifecycle` (mint additionally `mode.sandboxWrite !== "none"`); `ghToken` then stays `undefined` and askpass/env/egress collapse by construction; add `persona` to the egress-posture `log.info`; optional serviceTokens fold-in (`? {} :` on the Promise.all member) — flagged inferred.
- 4.3 Sweep for other support-visible token surfaces: confirm `buildAgentEnv`'s `gitInstallationToken`/askpass args are the only channel (they are — `:2876-2880` is the single threading point).

### Phase 5 — docs, ADR/C4, ship hygiene

- 5.1 ADR-075 addendum: deny-set is now dual-root (transition-window rationale) and the `/proc` deny is realized by shim tail-mask rather than the mid-argv tmpfs; record that the committed fixture now pins BOTH roots' ordering.
- 5.2 ADR-113 addendum: the persona-gated set gains clone, install-resolution, mint, askpass, egress (the credential surface joins the repo-lifecycle surface); record the serviceTokens decision either way.
- 5.3 ADR-272 one-line note: the `/proc` deny is now realized — the measured outcome's mechanism is no longer load-bearing on userns/ptrace luck.
- 5.4 C4: no model change — enumerated: no new actor, no new external system/vendor, no new container/datastore, no new relationship; the `support_persona` description ("read-only sandbox") becomes accurate. State the enumeration in the PR description.
- 5.5 `apps/web-platform/infra/sandbox-hardening-contract.sh` (new, ~30 lines): greps the three guard surfaces, prints `sandbox-hardening-contract:ok`.
- 5.6 Changelog entry; PR body `Closes #9723, #9725, #9558`.

## Architecture Decision (ADR/C4)

This plan amends two ADRs rather than writing a new one: the changes enforce boundaries the existing ADRs already declare — ADR-075 owns tenant read-isolation (deny set + /proc mask semantics change), ADR-113 owns the support-persona gated set (enumeration extended to the credential surface). ADR-272 gets a factual note only. **Detection triggers fired:** "reversal or extension of an existing ADR" (ADR-075's constant-deny set gains a member; its `/proc` intent gains a realization layer) and "trust-boundary semantic change" (the shim's role extends from fd-hygiene+seccomp injection to argv rewriting — recorded in both the shim header and the ADR-075 addendum). **C4 disposition: no model change**, with the completeness enumeration (no actor/system/container/relationship delta).

## Acceptance Criteria

- [ ] AC-1: `apps/web-platform/test/bwrap-shim.test.ts` contains rows asserting `--tmpfs /proc` is inserted before the first `--` and after `--args` payload expansion, including the payload-carried-`--` rewrite arm, and they pass.
- [ ] AC-2: `apps/web-platform/test/sandbox-isolation.test.ts` FR7 runs the vendor argv shape (tail `--bind /proc /proc` present) THROUGH the shim and asserts cross-tenant environ is unreadable; without the shim the same shape shows real procfs (control discrimination recorded in the test or its fixture helper).
- [ ] AC-3: `runHardeningProbes` includes a `proc_mask` probe; `sandbox-canary-regression.test.sh` no longer greps `/proc/self/fd` and asserts the new probe is wired; `apps/web-platform/test/sandbox-canary.test.ts` classifiers cover mask-present/mask-absent/unparseable.
- [ ] AC-4: `buildAgentSandboxConfig` deny set includes both `WORKSPACES_ROOT` and `WORKTREE_ROOT`-resolved roots under every flag/env combination in `agent-sandbox-tenant-deny.test.ts`; catastrophic-guard rows cover both roots.
- [ ] AC-5: `apps/web-platform/infra/sandbox-canary-argv.json` is regenerated through the capture path with `WORKTREE_ROOT` set in the capture env; the fixture pins both deny roots and still ends `--bind /proc /proc` (vendor tail unchanged — the mask is ours, below the capture seam).
- [ ] AC-6: `git-data-flag-precheck.sh` refuses `FLAG_MODE=flip` when the checked-out `agent-runner-sandbox-config.ts` lacks worktree-root deny coverage; `git-data-cutover.yml` flip requires `GIT_DATA_DENY_FLOOR` ≤ running image.
- [ ] AC-7: `cc-dispatcher-real-factory.test.ts` proves a support dispatch with a connected repo never calls `generateInstallationToken`, `writeAskpassScriptTo`, `ensureWorkspaceRepoCloned`, or `resolveEffectiveInstallationId`, and calls `buildAgentSandboxConfig` with `allowGithubEgress:false`; the egress-posture log carries `persona`.
- [ ] AC-8: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean; `bun test` shards covering the touched suites green (run via the repo's own runner wiring — `test-all.sh` selection — not a hand-enumerated list that can drift from the gate's set).
- [ ] AC-9: `npx markdownlint-cli2` clean on this plan + `tasks.md`.
- [ ] AC-10: `bash apps/web-platform/infra/sandbox-hardening-contract.sh` prints `sandbox-hardening-contract:ok` in the Check-10 sandbox shape (repo read-only, `PATH=/usr/local/bin:/usr/bin:/bin`, no credentials, <15s).

## Test Scenarios

- Given a bwrap argv `--args N -- cmd` where the payload ends `--bind /proc /proc`, when the shim execs, then the real binary receives `--tmpfs /proc` after the payload and before `--`, and in-sandbox `/proc` is empty.
- Given the payload carries its own `--`, when the shim execs, then the rewritten payload contains the mask before the boundary and the spawn succeeds.
- Given `GIT_DATA_STORE_ENABLED=true` + `WORKTREE_ROOT=/var/lib/soleur/worktrees`, when a sandbox config is built for `/var/lib/soleur/workspaces/<uuid>`, then `/var/lib/soleur/worktrees` is in `denyRead` and `workspaceUnderEffectiveRoot` is true in the emit.
- Given a support dispatch on a workspace with a connected repo, when the factory runs, then no token is minted, no askpass file is written, no clone runs, and `allowedDomains` is empty.
- Given a command-center dispatch (regression), when the factory runs with a connected repo, then mint/askpass/clone/egress behave exactly as today (existing rows stay green).
- Given the capture workflow runs with `WORKTREE_ROOT` set, then the fixture gains the second deny root and `--verify` byte-diffs clean on re-run.
- Given a mutated shim that drops the splice, then `bwrap-shim.test.ts` + the FR7/real-bwrap row go RED (guard mutation proof).

## Success Metrics

- Deploy canary `proc_mask` verdict `pass` on the first release carrying the shim change (the deploy is the proof).
- Zero `bwrap_shim_refused`/`fd_census_*`/`args_fd_*` canary verdicts across the deploys that follow.
- Per-dispatch `tenant-deny` emits carry `worktreeRoot` + `gitDataStoreEnabled` fields; zero `persona="support" githubEgress=true` rows in Better Stack.
- Cutover flip blocked (`SANDBOX_DENY_ROOTS` refuse) when staged against a pre-fix tree — demonstrated once in the precheck suite.

## Dependencies & Risks

- **In-sandbox `/proc` becomes genuinely empty** — agent Bash commands that introspect processes (`ps`, `/proc/self/fd` tricks) stop working. This is the ADR-075 intent realized; it is a deliberate behavior change disclosed in the changelog and user-impact section.
- **fd_census redesign** must keep discriminating fd leaks (the `leakFd` arm) without procfs; the bound re-derivation is the subtle part — Guard 1/2 mutation rows cover it.
- **Arm B payload rewrite** adds ~30 lines of fd juggling to a security boundary script; the alternative (fail-closed on a payload-carried `--`) was rejected: a shape drift would take down every agent session instead of just being handled. Precedent-diff gate note: the `exec {fd}< <(printf '%s\0' …)` re-emit pattern has NO in-repo precedent (grepped — `exec {…}< <(` appears nowhere under `apps/web-platform/infra`, `scripts/`, or `plugins/soleur`); pattern is novel, scrutinize at review.
- **bwrap version delta**: local verification ran on 0.12.0; the image pins Bookworm's 0.8.0. Ordering semantics are documented and version-stable, but the in-image `proc_mask` probe + `--verify` gate are what certify the real binary.
- **`GIT_DATA_DENY_FLOOR` is an operator-set repo variable** — consistent with `GIT_DATA_EMITTER_FLOOR`'s existing posture (the flip workflow is already typed-confirmation operator-gated); it is not a new manual step in a code path.
- **Open draft PR #9529** touches `agent-runner-sandbox-config.ts` + `cc-dispatcher.ts` (web-egress work) — file-level overlap only, no scope collision; rebase watch at work time.
- **Support persona loses repo minting** — intended; if support ever legitimately needs repo read access, that's a new ADR-113 decision, not a silent restore.

## References & Research

- Live verification (this session, host bwrap 0.12.0 — image pins Bookworm 0.8.0; the ordering semantic is bwrap(1)-documented and version-stable): `bwrap --args 3 --tmpfs /proc -- sh -c 'test -e /proc/self/environ …'` → `PROC_EMPTY` (mask lands after payload tail-bind); `bwrap --args 3 -- echo …` and payload-carried `--` both parse.
- Learnings applied: `security-issues/deny-then-restore-vendored-builder-argv-ordering-20261007.md` (re-derive vendor behavior at the pinned revision; ordering pins quantify over EVERY covering mount op — this plan's Guard 1 does position, not token-class), `security-issues/bwrap-shared-seccomp-filter-fd-hygiene-20261006.md` (arity-aware fd scan; `bwrap-shim:` stderr → `bwrap_shim_refused` never `canary_infra_error`; fd census carries a deliberately-leaked fd — the redesigned enumerator must keep that arm), `2026-10-06-i-claimed-a-mechanism-from-an-outcome...` (ACs assert observable outcomes, never mechanism).
- Fixture: `apps/web-platform/infra/sandbox-canary-argv.json` — `bwrapSetupArgv[118:120]` = `["/proc","/proc"]` tail of `--bind`; no `--` in payload.
- Sibling plan (merged PR #9599): `knowledge-base/project/plans/2026-10-06-feat-agent-security-hardening-slice-1-plan.md` — W1 credential deny, capture-gate conventions, ADR-272 residuals.
- ADRs: `knowledge-base/engineering/architecture/decisions/ADR-075-agent-sandbox-tenant-read-isolation.md` (constant parent deny + this plan's addendum target), `ADR-113-support-persona-scoped-concierge.md`, `ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md`, `ADR-272-agent-credential-isolation-via-sandbox-credentials-deny.md`, `ADR-079-faithful-sandbox-canary-and-profile-redeploy-verification.md`, `ADR-051-concierge-sandbox-github-egress-token-derived.md`.
- Sharp edges consulted: `plugins/soleur/skills/plan/references/plan-sharp-edges.md` — esp. the outcome-not-mechanism edge (#9601/PR #9599), the named-artifact/existence greps, exit-code probes, and the Check-10 probe-verb constraints.
- Issues: #9723, #9725, #9558 (this PR closes all three); provenance: PR #9709 review panel (MERGED), PR #9540 review.

## Review & Consult Provenance

Plan + deepen ran inline in this subagent (no Task/Spawn tool in this runtime — the multi-seat research fan-out is recorded as an environment limitation, not a skipped gate). Verified at write/deepen time: issue bodies fetched verbatim; every cited file/symbol re-grepped; the core mechanism (`--tmpfs` after `--args` payload beats the tail bind) measured live on host bwrap 0.12.0 and cross-checked against bwrap(1) docs; `lint-guard-contract.py` green on the Guard Contract; deepen halts 4.5 (network-outage — no trigger), 4.55 (downtime — code+workflow only, normal deploy path), 4.6 (User-Brand Impact — present, `single-user incident`), 4.7 (Observability — 5 fields, probe `bash` + committed script, no banned metacharacters), 4.8 (PAT scan — clean), 4.9 (UI wireframe — no UI surface), 4.10 (Encryption — no new store/connection), 4.11 (Guard Contract — lint green, assemblies structural), 4.12 (Scope Check — single unfenced section, all rows mapped/justified). One correction landed during deepen: `lb-weight-gate.sh` exists (the ADR-143 D3 pooling gate); the check lands at the flip precheck instead — see the reconciliation row.
