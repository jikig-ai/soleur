---
title: "feat: egress credential broker (Phase B of open-web egress — credentialed sessions without secret exposure)"
date: 2026-10-30
slug: egress-credential-broker
branch: feat-one-shot-9543-egress-credential-broker
issue: 9543
closes: []
type: feat
priority: p3-low
domain: engineering
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
---

# feat: egress credential broker — measurement spike, ADR and sequenced follow-ups (Ref #9543)

## Enhancement Summary

**Deepened on:** 2026-10-30. **Passes:** plan-review panel (DHH, Kieran, code-simplicity), sharp-edges verification, deepen-plan halts 4.6-4.13 (all pass or skip with stated reason), verify-the-negative sweep, security review (security-sentinel), post-planning collision re-probe (clean), live verification of cited issues, labels, milestone and ADR ordinal.

**Key improvements:** harness topology made implementable (non-loopback hostname, stub CONNECT gateway, `NO_PROXY`, `allowManagedDomainsOnly` arm, plain-HTTP arm, two `tlsTerminate` settings paths); Guard 1 contradiction between "fail on any visible secret" and a legal `leaks` outcome removed; harness hygiene and scoping arms added from the security review; ADR ordinal moved from the claimed ADR-310 to ADR-311; F4 gains a blocked-by edge.

**New considerations:** a `works` outcome for network-layer injection is an approval-gate bypass by construction; the ADR must not generalize a stub-gateway measurement to production.

## Overview

Phase A of open-web egress (ADR-278) gives entitled hosted agent sessions uncredentialed open egress and, in exchange, denies every credential to the sandbox, so those sessions cannot push to a repository, call `gh`, or use a connected provider in-sandbox. Issue #9543 asks for the broker that restores that without placing a reusable secret in the sandbox.

The CTO ruling (2026-10-30, recorded in `decision-challenges.md`) found that none of the three candidate mechanisms can be built safely on current evidence, so this PR delivers the part that is measurable and defers the part that is not:

1. A real-sandbox measurement spike against the pinned SDK 0.3.284 (three probes, mutation-checked) that decides between the SDK `mask` mode and a bespoke mediating endpoint.
2. One new ADR recording the measured results, the mechanism choice and the sequencing, cross-referencing ADR-278 Decision 5 and the ADR-272 `mask` deferral.
3. Four tracked follow-up issues, including the two prerequisites the ruling identified (approval gate and grants in the cc path, a push tool in the cc path).

No production runtime code, feature flag, toggle copy or legal text changes. The PR references the issue as `Ref #9543` and does not close it.

## Research Reconciliation — Spec vs. Codebase

| Issue / brief claim | Reality on main | Plan response |
|---|---|---|
| Broker is a "credential-vending localhost endpoint" that slots into the forwarder shape | ADR-278 measurement 1: the sandboxed child's localhost is not the container loopback; the forwarder is only reachable through the sandbox proxy chain, and `apps/web-platform/infra/egress-forwarder.mjs` is a raw header rewriter (lines 33-80) that checks `Proxy-Authorization` against `WORKSPACE:TOKEN` and pipes to the gateway; it parses no absolute-URI request and takes its workspace and token from the environment. The issue never says how the sandboxed caller authenticates | Probe (b) of the spike measures reachability and caller authentication; no endpoint is built |
| "Reuses ... entitlement flag" | There is no Flagsmith flag for web egress; the gate is the per-workspace column `workspaces.web_egress` (migration 158, `server/resolve-web-egress.ts`) | Nothing consumed in this PR; recorded in the ADR |
| "Audit every vend via emitWorkspaceActionContext" | The helper writes a log line only and its `WorkspaceAction` union has no vend action (`server/workspace-action-audit.ts:13-22`) | Durable vend audit is specified in the ADR for the broker follow-up |
| "Blocked by #9534 Phase A" | Phase A is on main (ADR-278, forwarder, gateway) | Satisfied |
| (Brief) "unblocked by #4672 slice 1" | Slice 1 merged 2026-10-30 (ADR-309), dark; the grants object exists only in the legacy runner (`server/agent-runner.ts:1204`) | Entitled sessions run in the cc dispatcher, which has neither the grants nor `github_push_branch` (`buildGithubTools` has one caller, `agent-runner.ts:1764`); the wiring becomes follow-up F1/F2 |
| ADR-272 cites `mask` as the in-SDK candidate for slice 2 | SDK 0.3.284 typings document `credentials.envVars` `mask` with `injectHosts`; HTTPS header injection needs the experimental `network.tlsTerminate`, honored only from user, managed or CLI settings | Probes (a) and (c) |
| ADR-272 as the source of the web-egress `envVars` deny census | The census is ADR-278 Decision 5; ADR-272 is the Anthropic-auth baseline | Cross-referenced correctly in the new ADR |

## Research Insights

**Premise Validation.** Checked 2026-10-30: #9543 is open with no linked or body-referencing PR (`linked:issue`, `in:body` merged and open, `in:title`, `git log --grep` all clean except the cited predecessor PRs for the earlier quick-win slice); epic #9601 open; the follow-up gate issue for egress-audit enablement is untouched by this plan. Stale premise found and corrected during the CTO ruling: option C ("route push through the gated server-side tool") does not work for entitled sessions today (see the reconciliation table). No open issue was found for the cc approval wiring or a cc push tool by the queries `ExecutionGrants`, `cc-dispatcher approval`, `github_push_branch` and `approval queue`; the follow-up filing step re-searches before creating them. ADR corpus grep for the mechanism: ADR-272 explicitly deferred `mask` to this issue (not rejected); ADR-278 rejected nothing relevant.

**Property List.** P1: no reusable secret is readable inside an entitled sandbox after this PR (unchanged). P2: the choice of broker mechanism rests on a measurement taken in the production topology, not on documentation. P3: a vend, when it exists, cannot bypass the approval queue. P4: the outcome of each probe distinguishes "works", "does not work", "leaks" and "could not be measured". P5: no public claim runs ahead of the measured control.

**Cut List.** Bespoke vending endpoint: buys per-request scoping, unproven reachability and caller authentication, so deferred to F3. New push tool in the cc platform server: buys "entitled sessions can push", needs the approval gate in that path first, so F2 blocked by F1. Durable vend audit and a new `WorkspaceAction`: nothing vends in this PR, so F3. Toggle copy and legal edits: would claim an unmeasured control, so deferred to flag-on. C4 model edit: no component is added, so none. Feature flag: no runtime surface to gate, so none. Already on main and covering a property: `github_push_branch` (approval-gated server-side push) covers P1 for legacy-runner sessions only.

**Files and conventions found** (all under `apps/web-platform/`): `server/egress-forwarder.ts` (`spawnEgressForwarder`, registry keyed by conversation, token-file deletion is revocation), `infra/egress-forwarder.mjs` (the spawned script), `server/agent-env.ts` (`buildAgentEnv`, `egressProxy` carrier), `server/agent-runner-sandbox-config.ts` (`buildAgentSandboxConfig`, `WEB_EGRESS_ENV_DENY_CENSUS`), `server/cc-dispatcher.ts:3116-3150` (forwarder spawn), `test/sandbox-credential-deny-runtime.test.ts` (the real-bwrap pattern this spike copies), `test/helpers/anthropic-stub.ts`, `test/helpers/hermetic-cli-env.ts`, `infra/bwrap-shim/bwrap`. Runner is vitest; tests are flat under `test/`.

**SDK semantics, verbatim** (`apps/web-platform/node_modules/@anthropic-ai/claude-agent-sdk/sdk.d.ts`, pinned 0.3.284). Lines 8584-8586, `tlsTerminate`: "[EXPERIMENTAL] Enable in-process TLS termination so the per-request filter can see HTTPS request bodies ... Only honored from user, managed/policy, or CLI (`--settings`) settings — project settings (.claude/settings.json and .claude/settings.local.json) are ignored." Line 8656, `credentials.envVars`: "`deny` unsets the variable for sandboxed commands; `mask` substitutes a sentinel inside the sandbox and injects the real value at the proxy." Line 8684, `injectHosts`: "If unset, defaults to `network.allowedDomains` — the credential is injected at every reachable host. Each entry must be reachable via `network.allowedDomains` (sandbox-runtime validates this)." Option fields: `sandbox?: SandboxSettings` at line 2181 and `settings?: string | Settings` at line 2199 (the flag-settings layer).

**Institutional learnings applied.** A token file's name is the credential and `denyRead` masks only sandboxed Bash, so probes scan Glob and Grep output too (`2026-10-19-mounting-a-credential-dir-had-three-gaps-the-mount-flag-fix-did-not-see.md`). Egress tests are open-world, mutation-checked censuses, not spelling checks (`2026-09-29-a-source-census-that-checks-the-arguments-name-not-its-binding-and-a-closed-file-list-both-let-guarded-egress-through.md`). Loopback-peer reachability must be probed from the real topology (`2026-07-23-readyz-loopback-peer-gate-unreachable-across-bridge-published-port.md`). No claim ahead of a measured control (`security-issues/2026-09-27-a-restored-marker-restored-controls-nobody-measured.md`). Audit tenant comes from the credential binding, not the request (`2026-06-02-server-audit-must-read-rpc-body-and-ssr-identity-needs-css-placement.md`).

## Open Code-Review Overlap

Open scope-outs naming files this plan touches: none for `agent-runner-sandbox-config`, `egress-forwarder`, `web-egress` or the ADR files. Four mention `cc-dispatcher.ts` (#4254, #3820, #3243, #3242). **Acknowledge:** this plan does not edit `cc-dispatcher.ts` (no runtime change); #3243 (decompose the dispatcher) is relevant context for follow-up F1/F2, which will edit it, and is cross-linked from them.

## Technical Rulings (CTO, 2026-10-30)

Persisted in full, with the operator-class rows and the plan-review challenges, in `knowledge-base/project/specs/feat-one-shot-9543-egress-credential-broker/decision-challenges.md` (gate-checked).

## Implementation Phases

### Phase 1 — Spike harness and probes (test-first)

Write `apps/web-platform/test/helpers/broker-spike-scan.ts` (pure functions, unit-tested first) and `apps/web-platform/test/broker-mechanism-spike.test.ts` before any measurement is recorded. The test copies the structure of `test/sandbox-credential-deny-runtime.test.ts`: real SDK `query`, real `buildAgentSandboxConfig`, real bubblewrap through the repo shim, scripted API stand-in, decoy credentials, `SANDBOX_OK` skip locally and fail where `C4_BWRAP_REQUIRED` is set, and the same Haiku 4.5 model pin (`claude-haiku-4-5-20251001`) and carve-out comment that file carries; `plugins/soleur/test/model-launch-review.test.ts` names that one file explicitly, so this PR extends its "THIRD SDK-path file" assertion to the new file, otherwise the pin would silently miss the 5.5 cutover. The echo target and the CONNECT-tunnel stub gateway are small local functions inside the test file, not shared helpers.

**Pure functions (always run, hermetic, no sandbox).** `scanSandboxSurfaces(observations, declaredSecrets)` returns every surface on which any declared secret appears (environment, readable `/proc/*/environ`, working-directory files, Glob and Grep output); `classifyOutcome({ observedEvents, scan, expected })` returns one outcome and **requires an `evidence` field** naming the observed events, so "works with no observed request" is unrepresentable. The RED rows of the Guard Contract run here against synthetic observations.

**Topology the real-sandbox probes use.** Sandboxed `curl` to a **non-loopback test hostname** (for example `echo.spike.test`, reaching the echo target through the proxy chain, as the stub gateway accepts only the test hostnames), because the hermetic test helper sets `NO_PROXY=127.0.0.1,localhost` (`hermetic-cli-env.ts:34`), `buildAgentEnv` sets a platform-host `NO_PROXY` when `egressProxy` is present (`agent-env.ts:303`), and an in-sandbox loopback dial reaches the sandbox's own empty loopback (ADR-278 measurement 1). The hostname is in `network.allowedDomains` and in `injectHosts`. The chain is sandbox runtime proxy, then the real unmodified `infra/egress-forwarder.mjs`, then a **stub gateway that performs CONNECT tunnelling to the echo target**, so the carrier is the production one. The production config sets `allowManagedDomainsOnly: true`; whether `options.sandbox` counts as managed is unknown, so it is a named input flipped in its own arm and any silent ignoring of `allowedDomains` is recorded, not assumed away.

**Harness hygiene (security review, 2026-10-30).** The sandboxed child gets an explicit allowlisted environment built from `test/helpers/hermetic-cli-env.ts` with `ANTHROPIC_BASE_URL` pointed at the stub, never an inherited `process.env`; the suite never reads a real ambient credential (an explicit child env plus per-run decoys are what the scan covers). The stub gateway binds `127.0.0.1` on ephemeral ports only, refuses any CONNECT target other than the test hostnames on the echo ports, and the suite asserts that the echo targets and the gateway bind `127.0.0.1`. The ephemeral CA and its key live under a `mkdtemp` directory with mode 0700 outside every sandbox mount, are deleted in `afterAll`, and are never added to any trust store (the sandboxed `curl` uses `-k`; no `NODE_EXTRA_CA_CERTS` or `SSL_CERT_FILE` is set). The private key file is deleted as soon as the echo target has read it; because the sandbox runs as the same uid, the 0700 mode is hygiene, not a boundary.

**Order and probes.**

1. **Probe (c) — `tlsTerminate` reachability (run first; it decides whether the HTTPS arms are meaningful).** The app passes only `sandbox: buildAgentSandboxConfig(...)` with `settingSources: []` and never `settings:`; the typings say `tlsTerminate` is honored only from user, managed or CLI (`--settings`) settings. Two arms: `options.sandbox.network.tlsTerminate` and `options.settings.sandbox.network.tlsTerminate`. Oracle: a certificate issued by the sandbox runtime CA on the echo connection. [Updated after review: a third arm through the CLI `--settings` layer was tried and dropped — it cannot tell "not forwarded to the CLI" from "not honored", so it could only ever be `unmeasurable`. Harness faults are excluded instead by the suite's premise checks: the arm that does terminate TLS in the same harness shows the harness can observe it.]
2. **Probe (a) — `mask` on our carrier.** Entry `credentials.envVars: [{ name: SPIKE_TOKEN, mode: "mask", injectHosts: [<test hostname>] }]` in a test-local copy of the production config. Arms are protocol (plain `http://` and `https://`) by `tlsTerminate` (per probe c) by `allowManagedDomainsOnly`. The plain-HTTP arm is the only way to separate "`mask` works" from "TLS termination is missing". Positive control: the entry removed, so the decoy must be visible in the sandbox (proves the scan can find it). Treatment passes only if the echo target received the real value and the open-world scan finds only the sentinel. Scoping arms: a request to a host not in `injectHosts` must not receive the value; a reflecting echo must not return the real value to the sandbox; a redirect or Host/SNI mismatch must not receive it. A `works` outcome means the mechanism substitutes, not that it is acceptable: network-layer injection fires on any sandbox request to `injectHosts` (for example a `git push` to the forge host), so it bypasses the approval gate by construction unless gated (see the ADR constraint in Phase 2).
3. **Probe (b) — can a request addressed to a virtual host reach the forwarder, and what identifies it.** Recorded facts: whether the request arrives at all; that the forwarder's tenant is its constructor environment (workspace and token), not something derived from the inbound credential; whether the sandbox can read or derive the proxy-hop credential (scan as above); and what the forwarder, which only rewrites and pipes the proxy request head, can serve without TLS termination. This is a design-validity check that sizes follow-up F3, not a three-way measurement: if the request is unreachable, mechanism (B) is dead and no authentication analysis follows.

**Outcome vocabulary.** Each probe records exactly one of `works`, `does-not-work`, `leaks`, `unmeasurable(reason)`, each with `evidence`. A treatment-arm `leaks` is a recorded finding and does not fail the run; the suite fails only when the control arm does not leak (the scan cannot find a secret) or when a probe observed nothing. `unmeasurable` forces the ADR to state the mechanism as undecided and never defaults to a claim. If probes (a) and (c) both come back `unmeasurable`, ADR-311 decides nothing and this PR delivers only the harness, the ADR statement of that fact and the tracked follow-ups.

### Phase 2 — Record the results

Write `knowledge-base/project/specs/feat-one-shot-9543-egress-credential-broker/phase-0-measurements.md` (host, SDK version, bwrap version, command lines, raw outcomes with evidence) and `knowledge-base/engineering/architecture/decisions/ADR-311-credential-broker-mechanism-measured-before-built.md` (provisional ordinal: ADR-309 is the highest on `origin/main`, and ADR-310 is claimed by an open PR for npm publishing, so the next free ordinal across `origin/main`, every remote branch and open-PR file lists was ADR-311 at plan time; re-probe at the last rebase). The ADR links to the measurements file, states the mechanism choice only to the extent Phase 1 measured it, lists open items (can an approved row be consumed outside the tool-call path; TLS termination trust) and a re-measure trigger (any change to the pinned SDK version or to the sandbox flags), and carries the supersession links in `related_adrs`. Add a one-line dated addendum pointer to ADR-272 and ADR-278 (the repo's "Amended by" convention; no rewrite of their decisions), worded neutrally ("see ADR-311").

ADR and evidence constraints from the security review: (1) the ADR states "measured on host X, SDK 0.3.284, stub gateway" and forbids generalizing any arm to the production image; (2) it says "resolves the ADR-272 `mask` deferral" only for outcomes that are not `unmeasurable`, otherwise "leaves it open"; (3) it does not use the words "safe", "secure" or "no secret reaches"; (4) it records that any mechanism injecting a credential at the network layer or through a mediating endpoint is rejected unless every vend is gated by an unconsumed action-bound approval row, and that a `works` outcome does not equal acceptable; (5) the measurements file records surface names and decoy hashes only, never raw environment or `/proc` content, and a secret-pattern scan runs over it before commit; (6) the suite emits a visible CI warning annotation for any `leaks` or `unmeasurable` outcome so a green run is not read as a pass.

### Phase 3 — Follow-ups and tracking

File four issues (milestone `Phase 4: Validate + Scale`, label `domain/engineering`, each with a re-evaluation criterion and a link to the epic and to #9543): F1 wire the ADR-309 approval gate and `ExecutionGrants` into the cc dispatcher (prerequisite, independent of egress); F2 register `github_push_branch` in the cc `soleur_platform` server (blocked by F1); F3 implement the broker mechanism chosen by the spike for in-sandbox `git` and `gh`, with durable audit (blocked by the spike result and F1); F4 BYOK provider credentials for entitled sessions (blocked by F3 and F1; no credential enters an entitled sandbox, and `WEB_EGRESS_ENV_DENY_CENSUS` stays unchanged, before then). F2's acceptance includes a test that its handler fails closed when `ExecutionGrants` or the approval gate is absent, and F1 includes a sweep of every gated-tier tool registered in the cc path, because a GitHub blocked-by edge is advisory only. Set the blocked-by edges with `gh issue edit --add-blocked-by` (flag precedent: `plugins/soleur/skills/plan/SKILL.md` deferral-tracking item) and verify each with `gh issue view <N> --json blockedBy`. Comment on #9543 with the split. The PR body uses `Ref #9543`. F1 and F2 are the quickest route to "entitled sessions can push" and are independent of the broker; they may proceed in parallel with the spike's follow-up.

### Phase 4 — Verification

Run the new suite on this host and in CI with `C4_BWRAP_REQUIRED=1`; run the existing `sandbox-credential-deny-*` and `web-egress*` suites unchanged; run `plugins/soleur/test/c4-count-parity.test.sh` and `bun test plugins/soleur/test/model-launch-review.test.ts` (its extended assertion covers the new SDK-path test file); check whether `scripts/lib/test-affected-paths.sh` needs the new file registered and add it if so; after merge run `soleur:postmerge` and confirm the follow-up issues, the ADR and the addenda are on main.

## Files to Create

- `apps/web-platform/test/broker-mechanism-spike.test.ts` — real bubblewrap probes plus the hermetic scan/classify unit block (~280 lines)
- `apps/web-platform/test/helpers/broker-spike-scan.ts` — pure `scanSandboxSurfaces` and `classifyOutcome` (~80 lines)
- `knowledge-base/engineering/architecture/decisions/ADR-311-credential-broker-mechanism-measured-before-built.md` (~100 lines)
- `knowledge-base/project/specs/feat-one-shot-9543-egress-credential-broker/phase-0-measurements.md` (~80 lines, raw outcomes the ADR links to)
- `knowledge-base/project/specs/feat-one-shot-9543-egress-credential-broker/decision-challenges.md` (exists)
- `knowledge-base/project/specs/feat-one-shot-9543-egress-credential-broker/tasks.md`, `session-state.md` (pipeline records, not deliverables)

## Files to Edit

- `knowledge-base/engineering/architecture/decisions/ADR-272-agent-credential-isolation-via-sandbox-credentials-deny.md` — one-line dated addendum pointer
- `knowledge-base/engineering/architecture/decisions/ADR-278-opt-in-open-web-egress-via-dedicated-connect-gateway.md` — one-line dated addendum pointer
- `plugins/soleur/test/model-launch-review.test.ts` — extend the SDK-path-file model-pin assertion to `broker-mechanism-spike.test.ts`
- `scripts/lib/test-affected-paths.sh` — only if Phase 4 shows the new test needs registering

No `.c4`, workflow, infrastructure, migration, server, component or legal file is edited.

## Architecture Decision (ADR/C4)

### ADR

New ADR-311 (ordinal provisional; the ship ordinal gate re-verifies against `origin/main`): "Credential broker mechanism is measured before it is built". Decision: no credential-bearing surface ships for entitled sessions until the mechanism (SDK `mask`, a mediating endpoint, or a gated tool) is measured in the production topology and the approval gate exists in the path that runs those sessions. It records the three probe outcomes. Amends ADR-278 Decision 5 (names the path to restoring credentialed push) and resolves the ADR-272 `mask` deferral by measurement. Authored in this PR as a deliverable, not a follow-up.

### C4 views

No C4 impact, with the enumeration checked against all three files (`model.c4`, `views.c4`, `spec.c4`): external human actors — none added (the founder and agent runtime are modeled); external systems — none added (`publicInternet` and GitHub already modeled; the test echo target is a local fixture, not a system); containers and data stores — none touched (`platform.webapp.egressForwarder` and `platform.infra.egressGw` exist in `model.c4` at the forwarder and gateway elements); actor-to-surface access relationships — none changed (edges `claude -> egressForwarder`, `egressForwarder -> egressGw`, `egressGw -> publicInternet` unchanged). The pre-existing `views.c4` GAP comment about the egress path not rendering is not made worse or better here. If the spike selects a mediating endpoint, the C4 broker element is added by follow-up F3, which owns that component. Verified by a green `plugins/soleur/test/c4-count-parity.test.sh` (Phase 4).

### Sequencing

The ADR describes the target state as `adopting`; the broker itself lands in F3 after F1.

## Guard Contract

### Guard 1 — broker-mechanism measurement suite

**Property.** The harness can find a secret where one is visible and can tell a probe that observed something from one that observed nothing, so every recorded outcome is backed by observed evidence from the pinned SDK in the production sandbox topology.

**Assembly.** Every surface the sandbox can read, enumerated open-world and flowing through one chokepoint, the pure `scanSandboxSurfaces` function that all three probes call: the sandbox environment, every readable `/proc/*/environ`, files in the working directory, the reflected response body, curl output, and a catch-all over the whole tool result in the live suite, plus Glob and Grep output in the hermetic block (the live stand-in issues one Bash call and never exercises Glob or Grep, and the token-directory mount is not part of this spike's topology); every declared secret (the scan quantifies over all of them, not the first); and every probe's dispatch count (scripted Bash calls and inbound requests logged by the echo target or forwarder). The outcome type requires an `evidence` field, so a conclusion without an observed event cannot be constructed.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove the `mask` entry (control arm): the decoy becomes visible in the sandbox environment | RED if the scan misses it; the suite requires the control arm to leak |
| 2 | Script the stand-in to issue zero Bash calls, point the echo capture at an empty log, or report `works` with no observed inbound request | RED ("0 observed" and an evidence-free conclusion are failures, not passes) |
| 3 | Add a second declared secret left unmasked after a compliant first, and place a value in a working-directory file reachable only through Glob or Grep | RED (synthetic observations to `scanSandboxSurfaces`; every declared secret and the Glob/Grep surface are in the census) |

**Harness rows.** H1 (suite edit, must be RED): empty the arm dispatch loop, or stop exporting the secret variable to the sandbox, or blank the env section on mask arms; the outcome floor and the env premise redden each (re-driven by mutation, `phase-0-measurements.md`). H2 (must-PASS, differs from the canonical): randomize the secret variable name, the decoy value and the test hostnames per run; the suite still passes, so it is not keyed to canonical names.

**Anchor.** Outcomes are measured live on each run, so there is no stored expected value that a diff could weaken. The measurements file and the ADR record what was observed on one host; the ADR names the re-measure trigger (a change to the pinned SDK version or to the sandbox flags), which is reviewed in the lockfile and sandbox-config diff and is not enforced by CI.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing visible. No runtime code, copy, flag or migration is touched; a defect here shows up as a red CI job on one integration test or as an ADR that records an outcome the suite does not reproduce.
- **If this leaks, the user's workflow is exposed via:** no credential is handled by this change. The only exposure vector is a mis-recorded measurement that later lets a broker ship on a false "no secret reaches the sandbox" premise; the live-measured outcomes, the open-world scan and the mutation matrix exist to prevent that.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** none, because the PR adds no runtime path and the follow-up that does (F3) is planned at `single-user incident` with CPO sign-off. threshold: none, reason: the diff adds a test, documentation and issue tracking only and changes no code that handles a credential or reaches a user.

## Domain Review

**Domains relevant:** Engineering, Legal (considered)

### Engineering

**Status:** reviewed
**Assessment:** CTO ruled the mechanism fork, scope, approval binding, audit, spike scope, ADR shape and public-claims posture, then re-ruled after the cc-path correction (decision-challenges.md). Spike-only with no new credential-bearing surface.

### Legal

**Status:** reviewed (by ruling, no separate CLO spawn)
**Assessment:** The CTO's Item 7 rules no edits to the toggle copy, privacy policy, data-protection disclosure, Art. 30 register or DPA item 18 in this PR, because nothing ships and the Phase-A statement stays true. The CLO is engaged by follow-up F3 at flag-on. No regulated-data surface is touched (no schema, auth flow, API route or `.sql`), so the GDPR gate does not fire.

### Product/UX

None: no file matching the UI-surface term list is created or edited.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "a credential broker so web-entitled hosted agent sessions can use credentials WITHOUT exposing raw secrets to the sandbox" [issue #9543] | Phase 1 probes a-c, Phase 2 ADR, F3 | descoped — justification: CTO ruling 2026-10-30 Items 1-2 — no credential-bearing surface ships before the mechanism is measured and the cc approval gate exists; recorded as an operator (scope) row |
| 2 | "No reusable secrets readable inside the sandbox (Phase A invariant preserved)" [issue #9543] | Guard 1 open-world scan; no runtime change | mapped |
| 3 | "Per-request/per-host scoping; audit every vend" [issue #9543] | ADR-311 (audit design), F3 | descoped — justification: nothing vends in this PR (CTO Item 4) |
| 4 | "Revocation bound to session lifetime" [issue #9543] | Probe (b) tenant-from-registry check, F3 | descoped — justification: measured only; implementation follows the mechanism choice |
| 5 | "Reuses: forwarder shape, `emitWorkspaceActionContext` audit, entitlement flag" [issue #9543] | Probe (b) uses the unmodified forwarder | descoped — justification: audit and entitlement reuse belong to F3 (CTO Item 4) |
| 6 | "Updates toggle copy + legal docs whose promises are Phase-A-scoped" [issue #9543] | Technical Rulings Item 7 | descoped — justification: no claim ahead of a measured control (CTO Item 7) |
| 7 | "Take one PR per issue, each through merge and deploy verification" [brief] | This PR, Phase 4 | mapped |
| 8 | "ship the broker dark/flag-off and hand over the flag step as a single typed-yes command" [brief] | No flag is created | descoped — justification: no runtime surface exists to gate; the flag step arrives with F3 |
| 9 | "the flag and #11237 steps stay with you" [brief] | Acceptance criteria (no flag, issue untouched) | mapped |
| 10 | "no public security claim ahead of a measured control" [brief] | Technical Rulings Item 7, AC | mapped |
| 11 | "CTO rules technical forks (never ask the operator a technical question)" [brief] | Technical Rulings, decision-challenges.md | mapped |
| 12 | "run soleur:postmerge deploy verification and report evidence from the observability layer" [brief] | Phase 4 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `broker-mechanism-spike.test.ts` and `helpers/broker-spike-scan.ts` | "no public security claim ahead of a measured control" (ask 10) | asked |
| ADR-311 | "a credential broker so web-entitled hosted agent sessions can use credentials WITHOUT exposing raw secrets to the sandbox" (ask 1) | asked |
| `phase-0-measurements.md` | "no public security claim ahead of a measured control" (ask 10) | asked |
| `model-launch-review.test.ts` extension | — | inferred — justification: the test names the one existing SDK-path file, so a second real-`query()` test would escape the Haiku 4.5 cutover assertion |
| ADR-272 and ADR-278 addenda | — | inferred — justification: the superseded ADRs would otherwise keep reading as the current plan (ADR cross-reference contract) |
| Follow-up issues F1-F4 and the comment on #9543 | "Take one PR per issue" (ask 7) | asked |
| `decision-challenges.md` | "CTO rules technical forks" (ask 11) | asked |
| Guard 1 | — | inferred — justification: a measurement suite that cannot be driven red is vacuous (Phase 2.12 contract) |

### Split Assessment

- Subsystems touched: 2 — `apps/web-platform`, `knowledge-base`
- Planned files: 9 | Estimated changed lines: ~570
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

<!-- founder-stated check: see plan-founder-check.md -->

- [x] `apps/web-platform/test/broker-mechanism-spike.test.ts` runs probes (c), (a), (b) in that order against the real SDK and real bubblewrap; each records one of `works`, `does-not-work`, `leaks`, `unmeasurable(reason)` with `evidence`. Verify: `cd apps/web-platform && C4_BWRAP_REQUIRED=1 npx vitest run test/broker-mechanism-spike.test.ts` exits 0 on a sandbox-capable host.
- [x] The hermetic block of the same file (and `helpers/broker-spike-scan.ts`) demonstrates Guard 1 rows 2-3 with synthetic inputs; row 1 is the real-sandbox control arm, H1 is demonstrated live by the outcome floor and the env premise, and H2 holds by per-run randomization. Verify: `npx vitest run test/broker-mechanism-spike.test.ts -t guard --reporter=verbose | grep -c '✓'` prints at least 5.
- [x] The suite skips with a stated reason locally when the sandbox is unusable and fails where `C4_BWRAP_REQUIRED` is set (same convention as `sandbox-credential-deny-runtime.test.ts`).
- [x] `phase-0-measurements.md` records host, SDK version, bwrap version, commands and raw outcomes with evidence for each probe and arm.
- [x] ADR-311 exists with the next free ordinal verified across `origin/main` and every remote branch (`for r in $(git for-each-ref --format='%(refname)' refs/remotes/origin); do git ls-tree --name-only $r knowledge-base/engineering/architecture/decisions/; done | grep -oE 'ADR-3[0-9]{2}' | sort -u`) and open-PR file lists, states only what Phase 1 measured, names the re-measure trigger, and cross-references ADR-278 Decision 5 and the ADR-272 `mask` deferral. ADR-272 and ADR-278 each gain one addendum line and no decision text changes. Verify: `git diff --numstat origin/main...HEAD -- <each adr>` prints `2 0 <path>` (tab-separated) for both files (a blank line and the pointer line added, none removed).
- [x] Four follow-up issues F1-F4 exist with milestone `Phase 4: Validate + Scale`, a re-evaluation criterion, blocked-by edges (F2 by F1; F3 by F1 and the spike; F4 by F3 and F1), and links to the epic and #9543. Verify: `gh issue view <N> --json state,milestone,blockedBy` for each; #9543 carries a comment describing the split.
- [x] The diff is confined to the Files lists. Verify: `git diff --name-only origin/main...HEAD` shows only the Files to Create/Edit, the plan file, the pipeline records (`tasks.md`, `session-state.md`, `decision-challenges.md`) and the compound/ship learning file under `knowledge-base/project/learnings/`; nothing under `apps/web-platform/server/`, `components/`, `app/`, `supabase/`, `infra/` or `docs/legal/`.
- [x] No feature flag is created or changed, and the egress-audit enablement issue is not touched.
- [ ] `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch` exits 0; the PR body states `Ref #9543` and renders the operator rows from `decision-challenges.md`.
- [x] `plugins/soleur/test/c4-count-parity.test.sh`, `bun test plugins/soleur/test/model-launch-review.test.ts` (with its assertion extended to the new file), `bun test plugins/soleur/test/components.test.ts` and the existing `sandbox-credential-deny-*` and `web-egress*` suites pass.

## Test Scenarios

- Given the production sandbox config with a `mask` entry, when a sandboxed command sends the masked variable to the TLS echo target through the env-proxy carrier, then the echo target receives the real value and the sandbox shows only the sentinel (integration, probe a).
- Given the same config with the `mask` entry removed, when the same scan runs, then the decoy is found in the sandbox environment (integration, positive control).
- Given the real forwarder and a stub gateway, when a sandboxed request names a virtual host, then the forwarder log records the inbound credential and conversation-keyed tenant and the sandbox cannot read or derive the credential (integration, probe b).
- Given the headless settings path, when `network.tlsTerminate` is set, then the echo connection shows (or does not show) a runtime-CA certificate and the outcome is recorded (integration, probe c).
- Given a probe that observes nothing, when the suite finishes, then it fails with a vacuity message and a conclusion without `evidence` is rejected (unit, mutation row 2; the live-suite analogue is the outcome floor and the env premise).
- Given synthetic observations with a second unmasked secret and a value reachable only through Glob/Grep, when `scanSandboxSurfaces` runs, then both are reported (unit, mutation row 3).
- Regression: the existing `sandbox-credential-deny-runtime.test.ts` and `web-egress.test.ts` pass unchanged (unit/integration).
- Deterministic post-merge checks: `gh issue view <F1..F4> --json state,milestone` returns OPEN with the milestone; `git cat-file -e origin/main:knowledge-base/engineering/architecture/decisions/ADR-311-credential-broker-mechanism-measured-before-built.md` exits 0.

## Telemetry Impact

No file under `apps/*/server`, `apps/*/src`, `apps/*/infra` or `plugins/*/scripts` is edited and no infrastructure surface is introduced, so the production observability schema (plan Phase 2.9 trigger set, deepen-plan Phase 4.7) does not apply to this PR; the broker follow-up (F3) must declare it, including an in-sandbox probe for the blind execution surface. Post-merge verification reports the CI run, the release workflow and the postmerge skill output; there is no production signal to query because no production behavior changes.

## Dependencies & Risks

- **Environment risk.** The probes need bubblewrap, `socat`, `curl` and `openssl` (for the ephemeral CA) and a kernel that permits unprivileged user namespaces; `allowManagedDomainsOnly` in the production config may cause `allowedDomains` from `options.sandbox` to be ignored, which is a recorded input to probe (a), not a failure. Mitigation: the suite skips locally with a reason and fails in CI where `C4_BWRAP_REQUIRED` is set; `unmeasurable(reason)` is a valid outcome.
- **Topology risk.** The CI runner is not the production image (its seccomp and AppArmor profiles differ), as ADR-272 records for its own measurement. Mitigation: the ADR states the host the outcomes were measured on and what is not covered; the production-image repeat is named as an open item.
- **Scope risk.** The deliverable is narrower than the issue as written. Mitigation: the narrowing is a recorded operator (scope) row, the PR uses `Ref`, and the work moves to tracked follow-ups with blocked-by edges.
- **Shared-file risk.** `scripts/lib/test-affected-paths.sh` (a conditional edit) is touched by four unrelated open PRs; re-run the overlap preflight with `--files` before editing it.
- **Ordinal risk.** A sibling PR can claim ADR-311 first. Mitigation: the ship ordinal gate re-verifies after every sync.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only filler text, or omits the threshold will fail `deepen-plan` Phase 4.6. This one declares `none` with the sensitive-path scope-out bullet; keep it if the Files lists grow.
- The spike must never be turned into a code path: any server, component or infra file in the diff contradicts the CTO ruling and Acceptance Criteria 7.
- Do not describe probe results in the ADR, in comments or in the PR body more strongly than the recorded outcome vocabulary allows; `unmeasurable` is not a pass.
