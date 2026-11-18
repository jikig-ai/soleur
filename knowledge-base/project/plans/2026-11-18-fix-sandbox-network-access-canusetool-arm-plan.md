---
title: "fix: explicit SandboxNetworkAccess arm in createCanUseTool (entitled egress through the gateway, deliberate deny otherwise)"
type: fix
date: 2026-11-18
slug: fix-sandbox-network-access-canusetool-arm
branch: feat-one-shot-12585-sandbox-network-access
issue: 12585
closes: 12585
priority: p2
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# fix: explicit SandboxNetworkAccess arm in createCanUseTool

## Enhancement Summary

**Deepened on:** 2026-11-18
**Inputs:**
- Plan review: DHH, Kieran, code-simplicity, architecture-strategist, spec-flow-analyzer, CTO (devex) and CPO.
- Deepen pass: security-sentinel, observability-coverage-reviewer, user-impact-reviewer, test-design-reviewer, a verify-the-negative sweep (13 current-code claims, all confirmed) and learnings-researcher.
- Strong-model advisor consult.

The CTO ruled every contested technical item: T1-T20 and D1-D7 in `decision-challenges.md`. Halts 4.6, 4.7, 4.8, 4.10, 4.11 and 4.12 pass. Halts 4.5, 4.55, 4.9 and 4.13 do not apply. This pass did not run the full every-agent fan-out of deepen-plan Phase 5. It ran a focused set chosen for this plan's risk surface.

### Key Improvements

1. **Phase 1a is a hard go/no-go before any arm code.**
   - It runs a child harness under `unshare -rnm` with routable decoys.
   - It has a positive control and records the SDK's actual input shape and version.
   - A failed step 0 turns the required lane red.
2. **The whole decision order lives in one pure function.** The ctx carries only `isLive`. NO_PROXY is pinned against a literal written out in the test. Hosts are matched strictly: hex and zone IDs, canonical IPv6, ASCII checked before lowercasing, and any port, `@` or `/` is denied.
3. **Revocation.**
   - Toggle-off tears down that host's forwarders immediately.
   - A next-dispatch re-resolve covers the other host (#12903).
   - A pre-decided deny-all (`gateway-unverified`) applies if the SDK caches or retries directly.
4. **Observability.**
   - Pino logs every deny; Sentry gets one capture per Query.
   - A Better Stack alert fires on granted-but-degraded sessions (merging creates two Better Stack resources).
   - The gateway decision log is named as the allow-path signal.

### New Considerations Discovered

- The SDK types have no `SandboxNetworkAccess` literal, so the request name and the `{ host }` shape are pinned only at runtime.
- The gateway does not deny the hosts' own public IPs. This predates the PR and is tracked in #12904.
- Production kernel-level restriction of the CLI to the forwarder is deferred to #12902.
- With web access on, commands still cannot reach NO_PROXY hosts: the user's own Supabase and Stripe, and `github.com` when no GitHub token was minted.

## Overview

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

The Agent SDK asks `canUseTool` for permission whenever a sandboxed command opens a connection to a host outside the sandbox `network.allowedDomains` set. The request is named `SandboxNetworkAccess` and carries `{ host }`. The production callback (`createCanUseTool`, `apps/web-platform/server/permission-callback.ts`) has no branch for it, so it lands on the closing "Deny-by-default: block unrecognized tools" branch.

Two consequences, both measured by the egress injector spike (PR #12518): (1) workspaces with Agent web access turned on (#9534) cannot reach the open web from any command the agent runs, silently; (2) the no-egress guarantee for every other workspace rests on that accidental branch, with no production signal, because `logPermissionDecision` returns early unless `SOLEUR_DEBUG_PERMISSION_LAYER=1`.

This plan adds a deliberate first branch for the request, keyed on the session's *live* egress forwarder, mirrors every denial to Sentry, re-measures ADR-278 measurements 3 and 4 on the shipped SDK pin, and corrects ADR-051, ADR-272 and ADR-278.

## Research Insights

**Premise Validation (Phase 0.6).** #12585 is open, no closing PR. The only collision hit (PR #12897) is this branch's own draft PR. PR #12518 (spike) merged 2026-11-11. #11637 (credential broker) is open and blocked by #12585 (ADR-311 Consequences, ADR-325 Consequences). **Stale premise:** the brief says "re-run measurements 3 and 4 on SDK 0.3.311"; the pin moved to `0.3.321` (`apps/web-platform/package.json` `"@anthropic-ai/claude-agent-sdk": "0.3.321"`, PR #12553 merged 2026-11-11). The CTO ruled (F7) to measure on 0.3.321, the version production runs. The spike driver's comment "#11637 owns the change" is stale: #12585 owns it.

**Property List (Phase 0.6b).**
- P1 A sandboxed connection request in a session with no live web-egress forwarder is refused by a branch whose only job is that request.
- P2 In a session whose forwarder is live, a request for a host that would bypass the proxy (NO_PROXY-matched, loopback, malformed) is refused; any other host is allowed and leaves only through the forwarder and the gateway.
- P3 After the forwarder is torn down (toggle off, crash), later requests are refused.
- P4 Every refusal is visible in Sentry and Better Stack in production, without the debug flag, and without the raw hostname.
- P5 The tests fail if the request regresses to the unknown-tool branch, and they exercise the real SDK on the shipped pin.
- P6 The architecture records stop claiming that `allowedDomains: []` closes sandboxed egress.

**Cut List (Phase 0.6b).** None of the asked mechanisms is redundant. The brief's "pin against the real SDK via the spike driver" is kept AND supplemented by a hermetic vitest, because the spike is not a required lane (cut nothing; the vitest buys P5 in a required lane). No new ADR: ADR-278 already owns the boundary (F8).

**Relevant code (content anchors).**
- `server/permission-callback.ts`: `createCanUseTool` returned callback; first branch today is `if (isFileTool(toolName))`; closing branch `// Deny-by-default: block unrecognized tools` with `logPermissionDecision("canUseTool-deny-default", ...)` and message `"Tool not permitted in this environment"`. Allow branches that could shadow a late arm: `if (isSafeTool(toolName))`, the plugin-MCP `pluginToolPrefix` allow. Sentry precedent: `createGitCarrierDenyReporter` (`server/git-carrier-guard.ts`), the safe-bash near-miss `WeakMap` budget.
- `server/permission-log.ts`: `PermissionLayer` union (16 members); early return on `SOLEUR_DEBUG_PERMISSION_LAYER !== "1"`.
- `server/agent-env.ts`: `if (opts?.egressProxy)` block builds `HTTP(S)_PROXY` and the inline `noProxy` literal; its comment "Measured caveat (spec TR7): the SDK's API path still transits the proxy" (ADR-278 measurement 4, contradicted on 0.3.311).
- `server/cc-dispatcher.ts`: `let webEgress` assigned only after `spawnEgressForwarder` succeeds (`if (webEgressEntitled && mode.runRepoLifecycle)`); `canUseTool: createCanUseTool({` built later with `webEgress` in scope; warm-path revocation `if (!entitled) teardownEgressForwarder(conversationId);`.
- `server/agent-runner.ts`: the legacy-runner `createCanUseTool(` call site (never egress). The full production-side census (plan-review, architecture): `server/cc-dispatcher.ts`, `server/agent-runner.ts`, and the dev probes `scripts/dev-probe-approval-gate.ts` and `scripts/dev-probe-destroy-ask.ts` (both pass no field, so `not-entitled`); `server/agent-runner-query-options.ts`'s boot probe uses an allow-all stub and never spawns a CLI. About 24 test files also call it and are unaffected because the field is optional. A census test over `createCanUseTool(` sites in `server/` and `scripts/` asserts only `cc-dispatcher.ts` passes the field.
- `server/egress-forwarder.ts`: `egressForwarders` registry; `hasEgressForwarder` is a "Test/QA hook"; exit handler identity check `egressForwarders.get(conversationId)?.proc === proc`; `teardownEgressForwarder`.
- `server/agent-runner-sandbox-config.ts`: `allowedDomains: opts?.allowGithubEgress ? [...ENTITLED_EGRESS_DOMAINS] : []`, `allowManagedDomainsOnly: true`; docstring "the sandbox proxy denies all other hosts either way" (false).
- `infra/egress-forwarder.mjs`: method-agnostic pipe to squid; squid (`egress-gateway-squid.conf`) is CONNECT-only, `SSL_ports 443`, deny-CIDR set.
- Spike: `test/infra/egress-injector-spike/probes/sdk-egress-driver.mts` (inline `noProxyMatches`, inline `SandboxNetworkAccess` arm, `permissionCalls`, `networkDecisions`, `networkAllowAll` control; calls `main()` at import); `.github/workflows/egress-injector-spike.yml` runs on `pull_request` when `server/agent-env.ts`, the spike dir and other listed paths change; mounts the working tree at `/app`.
- Real-SDK harness: `test/sandbox-wrapped-command-runtime.test.ts` (real `query()`, `buildAgentSandboxConfig`, `infra/bwrap-shim`, `test/helpers/anthropic-stub.ts`, `test/helpers/hermetic-cli-env.ts`, `skipIf(!SANDBOX_OK)` plus a throw under `C4_BWRAP_REQUIRED`); CI webplat shards install bwrap+socat and set `C4_BWRAP_REQUIRED: "1"` (`ci.yml`, step "Run webplat tests (vitest --shard)").
- Tests: `test/canusertool-decisions.test.ts` (`buildContext`, `assertDeny` checks only behavior + non-empty message; "Unknown non-mcp tool → deny-by-default"); `vi.mock("../server/permission-log")` precedent in `permission-callback-destroy-ask.test.ts`.

**Institutional learnings applied.**
- `knowledge-base/project/learnings/2026-10-11-a-mocked-sdk-could-not-see-the-permission-callback-never-ran.md`: only a real-SDK probe proves a gate fires; mocks cannot.
- `knowledge-base/project/learnings/2026-04-15-sdk-v0.2.80-zoderror-allow-shape.md`: every allow echoes `updatedInput` (use the existing `allow(toolInput)` helper).
- `knowledge-base/project/learnings/2026-03-16-agent-sdk-spike-validation.md`: `settingSources: []`, no bare `allowedTools` entry for a tool under test, or the probe proves nothing.
- `knowledge-base/project/learnings/2026-11-09-an-egress-injector-plan-must-read-the-env-the-rpc-and-the-auth-scheme-before-the-topology.md`: read the env builder for every host; `github.com,*.github.com` are in NO_PROXY.
- `knowledge-base/project/learnings/bug-fixes/2026-06-10-sandbox-network-plane-not-token-plane-error-shape-triage.md`: states "allowedDomains: [] closes egress"; gets a dated correction line.
- `knowledge-base/project/learnings/2026-05-13-mirror-with-debounce-vs-report-silent-fallback-for-high-cardinality-surfaces.md`: `mirrorWithDebounce` is a poor fit; enum-bounded per-session dedup instead.

**External research.** Skipped: security-sensitive, but the authority is the pinned SDK's measured behavior, not documentation; the plan measures it directly (F7).

**Rulings.** Every fork is recorded in `knowledge-base/project/specs/feat-one-shot-12585-sandbox-network-access/decision-challenges.md` (CTO F1-F11, CLO, CPO sign-off).

## Research Reconciliation — Spec vs. Codebase

| Brief / issue claim | Reality | Plan response |
|---|---|---|
| Re-run ADR-278 measurements 3 and 4 on SDK 0.3.311 | Pin is 0.3.321 | Measure on 0.3.321 (CTO F7) |
| "Pin against the real SDK — the spike driver records permissionCalls and networkDecisions" | Driver re-implements the arm inline and cannot be imported; spike is not a required lane | Driver calls the production predicate; a new required-lane real-SDK vitest carries the pin |
| Entitled session = "open-web egress entitlement" | Grant can be on while the forwarder failed to spawn (no `HTTPS_PROXY`) | Key on the live forwarder handle plus a call-time liveness check (F1, F10) |
| Driver comment "#11637 owns the change" | #12585 owns it; #11637 is blocked by #12585 | Comment updated |
| `agent-runner-sandbox-config.ts` docstring "the sandbox proxy denies all other hosts either way" | The SDK asks `canUseTool` and the answer decides | Docstring corrected |

## Problem Statement

A security property ("no outbound network for a workspace without web access") is held by a catch-all branch nobody wrote for it. A future edit that allows unknown tools in a narrow case, or a `SAFE_TOOLS` addition, would silently open direct egress from the app host for every workspace, because the spike's control showed an allowed request in an unentitled session reaches the open web through the SDK's own proxy on the app tier's direct route. Meanwhile the feature owners opted into does not work.

## Proposed Solution

One deliberate branch, first in the callback, with this decision order (CTO F10):

| Order | Condition | Behavior | Reason tag | Message to the model |
|---|---|---|---|---|
| 1 | `ctx.sandboxNetworkEgress` absent | deny | `not-entitled` | "Network access from sandboxed commands is not available in this session." |
| 2 | `isLive()` false or throws | deny | `egress-not-running` | same as row 1 |
| 3 | input not exactly `{ host: string }` (unexpected key set), host empty, not `net.isIP` and not LDH, or last label matches the WHATWG ends-in-a-number shape `^(0[xX][0-9a-fA-F]*|[0-9]+)$`, or contains a `%` zone ID (security deepen pass) | deny | `malformed-host` | "Commands can't connect to this host from this session." |
| 4 | loopback or unspecified IP literal (127/8, ::1, ::, 0/8, IPv4-mapped forms) | deny | `loopback-literal` | same as row 3 |
| 5 | `noProxyMatches(host, WEB_EGRESS_NO_PROXY)` | deny | `no-proxy-match` | same as row 3 (one shared host-deny message, CTO T3) |
| 6 | otherwise | allow (`allow(toolInput)`) | `gateway` | (none) |
| 6' | conditional, only if Phase 1a fails (fail-closed fallback): replaces row 6 for entitled sessions | deny | `gateway-unverified` | same as row 1 |

The whole order lives in the pure `decideSandboxNetworkAccess(input, egress: { live: boolean } | undefined, noProxy = WEB_EGRESS_NO_PROXY)`; the callback evaluates `isLive()` inside try/catch (a throw counts as not-live, CTO T4) and passes the boolean, so the spike driver (which passes `live: true`) pins the same order (CTO T2). The SDK types `input` only as `Record<string, unknown>` and has no `SandboxNetworkAccess` literal, so the tool name and `{ host }` shape are pinned at runtime only: the runtime test asserts the exact recorded key set (plan-review, Kieran).

Every deny is mirrored to Sentry and pino (warning) with no raw host. The allow is logged only through `logPermissionDecision`; the gateway logs every CONNECT it sees.

**Fail-closed fallback (CTO blocking concern 1; CLO ruling).** If the runtime test (Phase 1) or the spike run shows any allowed host's connection not arriving at the forwarder on 0.3.321 (direct route, direct retry after refusal), or a direct retry after refusal, or a per-host cached allow (arms B, E, F), row 6 does NOT ship: row 6' (deny-all with reason `gateway-unverified` for entitled sessions) is the design, a follow-up issue is filed, and the CLO DPIA t4 re-screen fires. No Query-abort or `onRevoke` machinery is built in this PR (CTO T12, overruling the F10 abort contingency): the exit handler and `teardownEgressForwarder` both drop the registry entry, so the per-call `isLive` covers revocation whenever the SDK re-asks, and if the SDK caches, only deny-all is safe.

### Attack Surface Enumeration

| Path from sandboxed code to the network | Checked by this fix? | Disposition |
|---|---|---|
| HTTPS CONNECT via the SDK in-netns HTTP proxy, host outside `allowedDomains` | Yes (arm) | Rows 1-6 |
| Plain HTTP via the same proxy | Yes (same `SandboxNetworkAccess` request); after allow it transits forwarder, squid refuses non-443 | Runtime test asserts it reaches the forwarder, never direct; spike criterion 6 measures squid's port-80 refusal |
| SOCKS / raw TCP via the SDK sandbox proxy (e.g. `ssh`, `curl --socks5-hostname`) | Measured, not assumed | Runtime test arm; a direct arrival triggers the fail-closed fallback |
| Hosts IN `allowedDomains` (GitHub set when a token is minted) | No: the SDK never asks; also in NO_PROXY, so they go direct | Pre-existing, owned by #11637 (F9); ADR-278 addendum and C4 prose must not claim the arm covers all sandboxed egress |
| In-process WebFetch | No: not sandboxed; honors process-env `HTTPS_PROXY` | Unchanged (ADR-278 Decision 6) |
| CLI's own API / telemetry traffic | No | Measurement 4 re-run; recorded in the ADR-278 addendum |
| Subagent Bash | Yes: same callback, same arm | Test |
| Support persona | Yes: arm runs before the support branches; support Bash is already denied | Test |
| Legacy domain-leader runner (`agent-runner.ts`) | Yes: never passes the field, so `not-entitled` | Test |
| Toggle-off or forwarder crash mid-session | Yes: call-time `isLive()` keyed on the session's token | Unit test plus runtime re-ask arm |

## Technical Approach

### Implementation Phases

Write the failing tests first in each phase (`cq-write-failing-tests-before`).

**Phase 1 — Measure first (hard go/no-go gate; decides whether row 6 ships).** Phase 1a runs before ANY Phase 2-5 code is written: the same suite drives arms B, D, E (sub-case) and F with a test-local `canUseTool` tap that allows `SandboxNetworkAccess`, the way the spike driver's `networkAllowAll` does, so the SDK's routing after an allow is measured independent of the arm. Only if B, E and F pass does work continue; otherwise the fail-closed fallback is the design and Phases 2-5 build the deny-all arm. Phase 1b, after Phase 3, swaps the tap for the production `createCanUseTool` and adds arms A and C. Create `apps/web-platform/test/sandbox-network-access-runtime.test.ts`, modeled on `sandbox-wrapped-command-runtime.test.ts` (same bwrap/socat probe, same throw under `C4_BWRAP_REQUIRED`, `startAnthropicStub`, `pointCliAtStub`/`scrubAmbientCliEnv`). Each arm drives one scripted sandboxed `curl` through the real `query()` with the production `buildAgentSandboxConfig`, `buildAgentEnv` (`egressProxy` pointing at the real `infra/egress-forwarder.mjs`, its `EGRESS_GW_HOST/PORT` pointed at a local recording "gateway" that logs request lines and the injected `Proxy-Authorization`, then answers 403), and the production `createCanUseTool` (minimal deps, as in `canusertool-decisions.test.ts`), with `permissionMode: "default"`, `settingSources: []`, no bare `allowedTools` entry for Bash. A tap around the callback records `(toolName, input, result)`. Harness topology (CTO T7): the vitest worker cannot sit inside a namespace, so the test spawns a child harness script (new `test/helpers/netns-egress-harness.mts`) under `unshare -rnm` (user + network + mount namespaces). The child hosts `query()`, the tap, the Anthropic stub, the production forwarder (started through `spawnEgressForwarder`), the recording gateway and the decoys, brings `lo` up, adds the aliases `10.0.0.1/32` and `10.0.0.2/32` on `lo`, and reports one JSON record per arm back to vitest on stdout. Decoy listeners bind `10.0.0.1:443`, `:80`, `:22` and `127.0.0.2:<p>`; a direct (off-forwarder) route to an IP-literal target lands on a recording decoy, and there is no resolver in the namespace, so a direct route to a DNS name fails closed. **Step 0 (required, before any arm):** inside the namespace, create the aliases and run the existing bwrap/apply-seccomp probe (nested user namespace). `ci.yml` relaxes `apparmor_restrict_unprivileged_userns` only best-effort (`|| true`) and the bwrap suite has hit `HELPER_EPERM` before, so this is measured, not assumed. Under `C4_BWRAP_REQUIRED=1` a step-0 failure throws and the lane goes red, as the existing suite does; `UNVERIFIED:nested-userns` applies only to local runs without the flag, and arm B never runs outside the namespace (CTO D4, amending T7). The Docker egress-injector spike stays the routing gate either way (F7). The child runs with the repo's `node_modules/.bin/tsx`, which resolves the tsconfig `@/*` paths; step 0 also asserts the child imports `permission-callback.ts` and `egress-forwarder.ts`, and the arm E/F teardown and `isLive` preconditions run in the child against its own registry (CTO D6). Any decoy hit, or a connection arriving at the recording gateway without the session `Proxy-Authorization`, fails the suite on its own, whatever the arm returned (CTO, advisor-consult ruling). Arms:
  - Control (permanent, CTO T9/T16): the allow-all tap with no egress env must hit the `10.0.0.1:443` decoy, or the suite fails; without it, arm A's silence cannot tell a closed path from a blind sensor.
  - A unentitled: `curl https://example.test/`, `curl https://10.0.0.1/` and `curl https://127.0.0.2:<p>/` => the tap shows a `SandboxNetworkAccess` call answered with reason `not-entitled`; nothing at the gateway or the decoy.
  - B entitled, open-web shape: `example.test`, `10.0.0.1` over HTTPS, plain HTTP to `example.test`, and a SOCKS/raw-TCP attempt to `example.test:22` => reason `gateway` (allow) and each connection arrives at the recording gateway as `CONNECT <host>:<port>` (or absolute-URI request) carrying the session's `workspaceId:token`; decoy listeners untouched. This is ADR-278 measurement 3 on 0.3.321.
  - C entitled, proxy-bypass shapes: `x.supabase.co`, `localhost`, `127.0.0.2`, `2130706433`, `[::1]` => explicit-arm deny with reasons `no-proxy-match` / `loopback-literal` / `malformed-host`; no CONNECT anywhere, decoy untouched.
  - D measurement 4 analog (CTO T8): a hosts file bind-mounted in the mount namespace maps `api.anthropic.com` (a production NO_PROXY entry) to `10.0.0.2`, where the stub listens, and the CLI is pointed at it by that name; the CLI's Messages API traffic must reach the stub directly and never appear at the recording gateway. (With the stub on `127.0.0.1`, every stack skips the proxy for loopback and D would prove nothing.) Without the mount namespace, D moves to the spike under the step-0 fallback and is recorded `UNVERIFIED` in the required lane.
  - E dead forwarder: forwarder process killed before the turn, and the test awaits the forwarder's `exit` event and asserts `isEgressForwarderLive(...) === false` as a precondition (otherwise the main case silently becomes the sub-case); allowed host => no connection at the decoy (no direct retry). The arm itself returns `egress-not-running` here; to measure SRT's retry behavior independent of the arm, a sub-case pins `isLive` true with the forwarder port closed.
  - E and F each send a second request to the same host after the gateway's 403, covering a direct retry and a per-host cached allow. Arm E (main case and sub-case) targets `10.0.0.1`, not a DNS name: with no resolver, a direct retry to a name fails closed and could never reach a decoy (test-design deepen pass).
  - Arm F synchronizes through a barrier file, not a sleep: the compound command waits (bounded) for a file the harness writes after `teardownEgressForwarder` returns.
  - Arm B adds `169.254.169.254` and a hosts-file name resolving to it: the arm allows them, and the recording gateway (and, in the spike, squid's `to_linklocal` and deny-CIDR) must refuse them with no upstream dial, showing the boundary acts on resolved IPs, not name strings (security deepen pass). Arm C adds `0:0::1`, `LOCALHOST.` and `0x7f000001` and asserts no decoy connection.
  - The positive control covers every decoy the silence checks rely on (`10.0.0.1:443`, `:80`, `:22`, `127.0.0.2:<p>`), not just one.
  - Every arm asserts the tap recorded at least one `SandboxNetworkAccess` call, so a degraded sandbox cannot pass green (learning 2026-06-04-cron-silence-was-bwrap-userns-drift-not-turn-budget); the step-0 bwrap probe includes `--proc /proc`, matching the production builder.
  - The recording gateway and forwarder readiness are polled with a deadline (30 s, 1 s interval), never a single connect (learning 2026-10-12-egress-gateway-single-shot-tcp-probe-raced-squid-bind).
  - Every runtime arm sets an explicit per-test timeout (vitest's default is far below a scripted turn; the existing real-SDK suite uses 240 s), and the file carries its `pyramid-justified:` comment.
  - `test/helpers/anthropic-stub.ts` gains a `host` parameter (arm D binds `10.0.0.2`) and a scripted tool sequence (arm G needs a `Task` call before the `Bash` call); it is added to Files to Edit.
  - F re-ask: allow host H, then tear the forwarder down via the production `teardownEgressForwarder`, request H again => the callback is called a second time and returns `egress-not-running`.
  - G subagent (Phase 1b, CTO T11): a scripted `Task` subagent runs the same `curl`; the tap records `SandboxNetworkAccess` with `agentID` set and the same not-entitled / gateway outcomes.
  - `MEASURED_ON_SDK = "0.3.321"` is asserted against the installed `@anthropic-ai/claude-agent-sdk` version; its failure message says to re-run arms B, D, E, F and update the ADR-278 addendum (CTO T16). When no `SandboxNetworkAccess` call is recorded, the failure prints the tool names that were recorded.
  - Floor: every arm ran to its last assertion (a skipped or filtered arm cannot pass vacuously), as in the existing suite's floor test.
  - Go/no-go: if B, E or F fails on 0.3.321 in Phase 1a, the fail-closed fallback above is the design from that point (no allow branch is written), with its follow-up issue and the CLO's DPIA t4 re-screen.

**Phase 2 — Pure decision module.** Create `apps/web-platform/server/sandbox-network-access.ts`, import-free except `node:net` (no pino, Sentry or `@/` aliases: `agent-env.ts` imports it, and the spike driver already imports `/app/server/agent-env.ts`, so the module must not pull in the logger or an import cycle; a one-line unit test asserts its import set): `SANDBOX_NETWORK_ACCESS_TOOL = "SandboxNetworkAccess"`; `WEB_EGRESS_NO_PROXY` (the current literal, byte-identical); `normalizeHost`; `noProxyMatches`; `decideSandboxNetworkAccess(input: unknown, egress: { live: boolean } | undefined, noProxy: string = WEB_EGRESS_NO_PROXY): { behavior: "allow" | "deny"; reason: SandboxNetworkReason; matchedEntry?: string }` (full F10 order inside; no `hostClass`, CTO T3). Unit tests in `apps/web-platform/test/sandbox-network-access.test.ts`, including an enumerated (not randomly generated; if fast-check is used, pin the seed) property sweep asserting no NO_PROXY or loopback spelling is ever allowed.

Normalization order (security deepen pass, consistent with CTO F3's over-deny): (1) require a primitive `string` (an array or `String` object denies `malformed-host`); (2) check the RAW value against `^[A-Za-z0-9.\-\[\]:]+$` BEFORE any lowercasing, because `"\u212A".toLowerCase() === "k"` (Kelvin sign) would otherwise turn non-ASCII into ASCII; IDN must arrive as punycode; (3) strip at most one trailing dot; (4) strip IPv6 brackets and rewrite an IPv6 literal to canonical form with `new URL("http://[" + h + "]").hostname` before the loopback check, so `0:0:0:0:0:0:0:1`, `::0001`, `::ffff:7f00:1`, `::127.0.0.1` and `64:ff9b::7f00:1` all classify as loopback; (5) lowercase; (6) deny `malformed-host` on any `:` that is not part of a valid IPv6 literal (so `[::1]:443` and `host:443` both deny) and on any `@`, `/` or whitespace; no port is ever stripped (CTO D7, overruling F3's port strip). Phase 1a records the raw input key set and host format the SDK actually sends as a go/no-go observation; if 0.3.321 sends `host:port` for an ordinary allowed request, the F3 strip returns with exact-match tests per observed shape. Sweep cases beyond the earlier set: `0x7f000001`, `0x7F.0.0.0x1`, `0177.0.0.01`, `127.1`, `::1%lo`, `fe80::1%eth0`, `[::ffff:127.0.0.1]`, `0:0::1`, `LOCALHOST.`, `localhost..`, `.supabase.co`, Kelvin-sign and fullwidth-dot (`x\uFF0Esupabase\uFF0Eco`) hosts, `user@127.0.0.1`, `localhost:80`, `[::1]:443`, and an `xn--` punycode spelling of a NO_PROXY suffix (allowed: it is a different host). The input-shape cases (`{host, port}`, extra keys, non-string `host`) must deny without throwing. The bypass-shape ACs drive `createCanUseTool` with the raw SDK `toolInput`, not the pure function with a pre-parsed host (learning 2026-11-10-the-hook-judged-a-cleaned-path...: test the entry point the transport calls).

**Phase 3 — The arm.** In `server/permission-callback.ts`: add `sandboxNetworkEgress?: { isLive: () => boolean }` and `webEgressGranted?: boolean` (Sentry tag only) to `CanUseToolContext` (the arm imports `WEB_EGRESS_NO_PROXY`; CTO T1, T13) (optional, documented as derived from the live forwarder handle); add the branch as the first decision branch of the returned callback, right after the existing `const subagentCtx = ...` line (whose `options.agentID` the Sentry `subagent` field needs) and before `if (isFileTool(toolName))`, matching `toolName === SANDBOX_NETWORK_ACCESS_TOOL` exactly, never falling through; evaluate `isLive()` inside try/catch per request; return `allow(toolInput)` or `{ behavior: "deny", message }` with the static per-reason messages. Add `"canUseTool-sandbox-network"` to `PermissionLayer` in `server/permission-log.ts`. Tests in `apps/web-platform/test/permission-callback-sandbox-network.test.ts` (mock `../server/permission-log` and `../server/observability` as the destroy-ask suite does).

**Phase 4 — Sentry mirroring.** Inside `createCanUseTool`, a reporter in the closure state of each `createCanUseTool` instance (so dedup lifetime is per Query, CTO T20; like `createGitCarrierDenyReporter`) keyed on `(reason, matchedEntry)` calls `warnSilentFallback(null, { feature: "cc-permissions", op: "sandbox-network-denied", tags: { reason, granted: "true" | "false" }, extra: { reason, granted, matchedEntry, subagent: Boolean(options.agentID) }, message: "sandboxed network request denied" })`. `granted` comes from the grant boolean `webEgressEntitled`, passed in the ctx for observability only and never read by the decision (CTO T13): a granted session whose forwarder failed to spawn reports `not-entitled` with `granted: "true"`, which must stand out from the normal not-granted volume. No `host`, no `toolInput`, no `userId` in any field (CLO ruling 3). Every deny occurrence also logs one pino `logger.warn` line (reason, granted, matchedEntry, subagent; never the raw host) OUTSIDE the dedup; only the Sentry mirror is deduplicated (CTO D3, learning 2026-05-29-mirror-warn-debounce-gates-both-pino-and-sentry). Tests assert N pino lines and 1 Sentry capture for N identical denies, and that two `createCanUseTool` instances each report once. The model-facing deny message is keyed on (reason, granted), static and host-free; the CPO writes the granted-but-degraded wording (CTO D2b).

**Phase 4b — Alert on granted-but-degraded denies (CTO D2a, overruling F5's no-alert).** Add a Better Stack logs alert in `apps/web-platform/infra/betterstack-logs-alerts.tf` following that file's seven-step recipe: a `locals` SQL predicate over the pino warn line for `sandbox-network-denied` with `granted` true (normal count about zero), a `logtail_exploration` on `local.vector_prd_source_id` with a `host_name`-agnostic predicate (both web hosts carry the signal), a `logtail_exploration_alert` copying the existing paging semantics, two `-target=` lines in `apply-web-platform-infra.yml`'s main plan allowlist, a row in `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`, the exploration-count bump in `test/infra/betterstack-send-failed-alert-mutation.test.sh`, and the alert's drift-guard step in `.github/workflows/infra-validation.yml`. Recipe step 1 asks for a live positive control; before deploy no event exists, so the predicate is validated against a synthesized fixture row in the drift guard, and the live positive control runs post-merge (AC15). **Merging this PR mutates production:** the merge-triggered `apply-web-platform-infra.yml` run creates exactly these two Better Stack resources (the normal ship path, in scope per the brief); no other infra resource changes.

**Phase 5 — Wiring.** `server/egress-forwarder.ts`: export `isEgressForwarderLive(conversationId, token)` (`egressForwarders.get(conversationId)?.token === token`). `server/agent-env.ts`: import `WEB_EGRESS_NO_PROXY` and use it for `NO_PROXY`/`no_proxy`; correct the measurement-4 comment to the Phase 1 result. `server/cc-dispatcher.ts`: pass `sandboxNetworkEgress: webEgress ? { isLive: () => isEgressForwarderLive(args.conversationId, webEgress.token) } : undefined` (capture `webEgress` in a `const` so the closure cannot see a later reassignment). Leave `server/agent-runner.ts` without the field. Also pass `webEgressGranted: webEgressEntitled` (observability only, feeds the `granted` tag; CTO T13). NO_PROXY pin (CTO T1): `buildAgentEnv({egressProxy}).NO_PROXY` equals today's literal written out in the test, so drift in either the constant or agent-env reds. Real-factory test (CTO T10, in the `cc-dispatcher-real-factory` style): grant on and forwarder spawn ok, the captured `createCanUseTool` args carry `sandboxNetworkEgress`, `isLive()` is true, and it is false after `teardownEgressForwarder(conversationId)`.

**Phase 5b — Immediate toggle-off teardown (CTO D1).** `server/egress-forwarder.ts`: add `teardownEgressForwardersForWorkspace(workspaceId)` over the registry entries' existing `workspaceId` field. `app/api/workspace/web-egress/route.ts`: call it right after `setWebEgress(false)` succeeds. A route test asserts a live forwarder for that workspace is gone and the next `SandboxNetworkAccess` is denied `egress-not-running`. The forwarder on the OTHER web host (LB `session_affinity = "none"`, `infra/cloudflare-lb.tf`) is revoked only by the T18 next-dispatch re-resolve; that cross-host window is tracked in #12903.

**Phase 6 — Spike driver and workflow.** `sdk-egress-driver.mts`: delete the local `noProxyMatches`; in the `SandboxNetworkAccess` branch call `decideSandboxNetworkAccess(input, entitled ? { noProxy: String(env.NO_PROXY ?? "") } : undefined)`, keep `spec.networkAllowAll`, record `{ host, decision, reason }` in `networkDecisions`; update the comments to cite #12585 and the production module. `.github/workflows/egress-injector-spike.yml`: add `apps/web-platform/server/sandbox-network-access.ts` to `on.pull_request.paths`. The consumer of that list is GitHub's own path filter on this workflow's trigger (`on:` / `pull_request:` / `paths:`, next to the comment naming the paths the suite and probes open), evaluated against the PR's changed files; without the entry, a change to the module the driver now imports would not re-run the spike. Record the raw host in `networkDecisions.host` (unchanged), and the normalized host and `reason` in separate new fields; update the `lib/arms.sh` criterion (the verdict computed from `ndec, edec = ...`) so its required denied set `{"127.0.0.1","localhost"}` accepts the `loopback-literal` reason and its "NO_PROXY rule denies" wording names the reasons (CTO T15).

**Phase 7 — Records.** ADR-051 and ADR-272: dated addenda (2026-11-18) correcting "allowedDomains: [] closes sandboxed egress": the empty allowlist makes the SDK ask `canUseTool` for every host, and the explicit arm's deny closes it. ADR-278: addendum covering the arm as boundary mechanics, the 0.3.321 results of measurements 3 and 4 (vitest + spike run URL), the residual windows (revocation takes effect at the next warm dispatch's async `resolveWebEgressStrict` re-resolve, so a long autonomous turn keeps egress until then (CTO T18); GitHub hosts in `allowedDomains` never reach the arm, #11637), the gateway residual that the deny-CIDR list does not cover the web hosts' own public IPs (tracked in #12904, CTO D5), and a sentence that it replaces the 2026-11-10 addendum's "which #11637 owns" assignment. ADR-325: one dated note that the `SandboxNetworkAccess` arm, the `agent-env.ts` comment fix and the 0.3.321 re-measure it assigns to #11637 are delivered by #12585 (CTO T14, amending F8). `server/agent-runner-sandbox-config.ts` docstring. `knowledge-base/engineering/architecture/diagrams/model.c4` edge `platform.engine.claude -> platform.webapp.egressForwarder`: name the canUseTool `SandboxNetworkAccess` gate. Learning `2026-06-10-sandbox-network-plane-not-token-plane-error-shape-triage.md`: one dated correction line.

**Phase 8 — Verification.** Full webplat vitest; C4 tests (`test/c4-code-syntax.test.ts`, `test/c4-render.test.ts`, `plugins/soleur/test/c4-count-parity.test.sh`); `tsc`; confirm the egress-injector spike run on the PR head SHA is green (all nine criteria), cite its URL in ADR-278. Post-merge (self-pulled, no production mutation): query Sentry for `op:sandbox-network-denied` and Better Stack for the pino warn line after deploy, confirming the event shape carries no host.

## Files to Create

- `apps/web-platform/server/sandbox-network-access.ts`
- `apps/web-platform/test/sandbox-network-access.test.ts`
- `apps/web-platform/test/permission-callback-sandbox-network.test.ts`
- `apps/web-platform/test/sandbox-network-access-runtime.test.ts`
- `apps/web-platform/test/helpers/netns-egress-harness.mts` (child harness run under `unshare -rnm`, CTO T7)
- a `cc-dispatcher` real-factory test for the `sandboxNetworkEgress` wiring (CTO T10), next to the existing `cc-dispatcher-real-factory` suite

## Files to Edit

- `apps/web-platform/server/permission-callback.ts`
- `apps/web-platform/server/permission-log.ts`
- `apps/web-platform/server/egress-forwarder.ts`
- `apps/web-platform/server/agent-env.ts`
- `apps/web-platform/server/cc-dispatcher.ts`
- `apps/web-platform/server/agent-runner-sandbox-config.ts` (docstring only)
- `apps/web-platform/test/infra/egress-injector-spike/probes/sdk-egress-driver.mts`
- `.github/workflows/egress-injector-spike.yml` (paths list only)
- `knowledge-base/engineering/architecture/decisions/ADR-051-concierge-sandbox-github-egress-token-derived.md`
- `knowledge-base/engineering/architecture/decisions/ADR-272-agent-credential-isolation-via-sandbox-credentials-deny.md`
- `knowledge-base/engineering/architecture/decisions/ADR-278-opt-in-open-web-egress-via-dedicated-connect-gateway.md`
- `knowledge-base/engineering/architecture/decisions/ADR-325-egress-credential-injection-is-a-property-of-the-hop.md` (dated note, CTO T14)
- `apps/web-platform/test/infra/egress-injector-spike/lib/arms.sh` (criterion text, CTO T15)
- `apps/web-platform/test/helpers/anthropic-stub.ts` (`host` parameter and scripted tool sequence for arms D and G)
- `apps/web-platform/app/api/workspace/web-egress/route.ts` (immediate teardown on toggle-off, CTO D1)
- `apps/web-platform/infra/betterstack-logs-alerts.tf`, `.github/workflows/apply-web-platform-infra.yml` (two `-target=` lines), `.github/workflows/infra-validation.yml`, `apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh`, `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` (granted-but-degraded alert, CTO D2)
- `knowledge-base/engineering/architecture/diagrams/model.c4` (one edge description)
- `knowledge-base/project/learnings/bug-fixes/2026-06-10-sandbox-network-plane-not-token-plane-error-shape-triage.md` (one correction line)

## Open Code-Review Overlap

- #3243 (decompose `cc-dispatcher.ts`): **Acknowledge** — a structural refactor; this PR adds one ctx field at the existing `createCanUseTool({` call and does not move code.
- #3242 (tool_use WS event lacks raw name field): **Acknowledge** — WS payload shape, unrelated to the permission arm.

## Alternative Approaches Considered

| Alternative | Why rejected |
|---|---|
| Key on the grant boolean `webEgressEntitled` | A grant with a failed forwarder has no `HTTPS_PROXY`; an allow goes direct (CTO F1) |
| Static entitlement captured at cold dispatch | Keeps allowing after toggle-off (CTO F10) |
| Place the arm just before deny-default | Later allow branches could shadow it (CTO F4) |
| Allow every IP literal outside NO_PROXY | Trusts unmeasured SDK loopback handling (CTO F3) |
| Arm-side private-CIDR list | Duplicates `infra/egress-deny-cidrs.txt`; would drift (CTO F3) |
| Measure on 0.3.311 | Not the shipped pin (CTO F7) |
| New ADR | Corrects mechanics of ADR-278's recorded decision (CTO F8) |
| Remove inject hosts from NO_PROXY here | #11637's measured change (CTO F9) |
| Raw host in Sentry | Agent-controlled, may identify a customer (CTO F5, CLO ruling 3) |
| Point the sandbox at the forwarder with `network.httpProxyPort` / `socksProxyPort` (present in the 0.3.321 `SandboxNetworkConfigSchema`) so routing is set by config | ADR-278 Decision 1: the `httpProxyPort` chain is credential-less and cannot satisfy the forwarder's inbound `workspaceId:token` auth, and the Phase-0 spike measured that under `httpProxyPort` the runtime proxy forwards without its domain filter. The env-proxy carrier stays; Phase 1a re-measures it on 0.3.321 as a go/no-go |
| Kernel-level egress restriction of the CLI process to the forwarder only (netns or uid rule) in production | The CLI's own control-plane traffic (measurement 4) and the server share the container network; a per-process egress rule is a topology change beyond this fix. The runtime test applies the restriction in CI instead (Phase 1 namespace), and the spike verifies the production image. Deferred: #12902 |

One item is deferred: production kernel-level restriction of the CLI to the forwarder, tracked in #12902 (CTO ruling). Conditional issues: the fail-closed fallback and any `UNVERIFIED:<capability>` each file an issue when they fire.

## User-Brand Impact

- **If this lands broken, the user experiences:** toward deny, owners with Agent web access on keep seeing agents fail to fetch packages or docs from commands (today's state); toward allow, a workspace that never opted in has an agent command reach the internet.
- **If this leaks, the user's data is exposed via:** a sandboxed command in a workspace without web access (or with web access revoked or its forwarder down) sending repository contents or tokens to an arbitrary host straight from the app host, bypassing the gateway and the Scope Grants audit; or an entitled session reaching container-loopback services or platform hosts directly through a NO_PROXY or loopback spelling the arm failed to match.
- **Product consequence, stated (CPO and architecture plan-review):** with web access on, commands still cannot reach any NO_PROXY host: the user's own Supabase projects (`*.supabase.co`, `*.supabase.in`), `api.stripe.com`, `*.sentry.io`, `*.datadoghq.com`, the Anthropic hosts, and `*.github.com` hosts other than the allowlisted `github.com`/`api.github.com` (codeload, gist, uploads). This is a known over-deny, not a regression (entitled sessions reach nothing from commands today); changing NO_PROXY membership is #11637's (CTO F9). A command reaching the workspace's own in-sandbox dev server (`curl localhost:3000`) is expected unaffected because curl skips the proxy for `localhost` and the connection stays on the sandbox loopback; the runtime test covers it in arm C or records `UNVERIFIED:in-sandbox-loopback`.
- **Revocation window, stated (CTO D1):** turning web access off stops the workspace's forwarders on the host that served the toggle immediately; a session on the other web host keeps egress until its next dispatch re-resolves the grant (#12903).
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one workspace's unconsented exfiltration is a breach on its own, so this is not an aggregate pattern.

CPO sign-off at plan time: **SIGN-OFF WITH CONDITIONS** (2026-11-18), conditions mapped to AC6-AC10. `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Observability

```yaml
liveness_signal:
  what: Sentry warning events tagged feature=cc-permissions op=sandbox-network-denied (one per Query per reason/matchedEntry; tags reason and granted), plus the same pino warn line in Better Stack
  cadence: pino line on every denied SandboxNetworkAccess request; Sentry event once per Query per (reason, matchedEntry) (CTO D3)
  alert_target: Better Stack logs alert on sandbox-network-denied with granted true (CTO D2, overruling F5); other reasons read on demand
  configured_in: apps/web-platform/server/permission-callback.ts (sandbox-network deny reporter inside createCanUseTool)
error_reporting:
  destination: Sentry project for apps/web-platform (SENTRY_DSN), via warnSilentFallback in server/observability.ts
  fail_loud: pino warn line "sandboxed network request denied" with feature=cc-permissions op=sandbox-network-denied reason=<reason>
failure_modes:
  - mode: entitled session's allowed traffic stops reaching the gateway (forwarder dead or torn down)
    detection: arm returns egress-not-running and emits op=sandbox-network-denied reason=egress-not-running; forwarder exit already reports via feature=egress-forwarder
    alert_route: pino -> Sentry (warnSilentFallback -> logger.warn + captureMessage level warning), Sentry issue stream
  - mode: regression routes SandboxNetworkAccess back to the unknown-tool branch
    detection: permission-callback-sandbox-network.test.ts and sandbox-network-access-runtime.test.ts fail in the required webplat lane (they assert layer canUseTool-sandbox-network and the reason, not just a deny)
    alert_route: workflow run log, required webplat lane (CI failure on the PR)
  - mode: SDK upgrade changes the request name or input shape
    detection: runtime test arm A/B fails (no SandboxNetworkAccess call recorded) in the required lane; the egress-injector spike re-runs on package.json changes
    alert_route: workflow run log, required webplat lane (CI failure on the dependency-bump PR)
  - mode: allowed host leaves without transiting the forwarder (direct route)
    detection: runtime test decoy listener on 127.0.0.2 and the recording gateway (in-surface: the connection itself) discriminate direct vs chained vs refused in one run
    alert_route: workflow run log, required webplat lane; triggers the fail-closed fallback
  - mode: allowed host never appears at the gateway in production (allow decided, CONNECT absent)
    detection: the allow path has no app-side production signal (logPermissionDecision is log.debug and Vector keeps only pino level 40 and up, app_container_warn_filter in infra/vector.toml); the gateway's own soleur_json decision log (egress-gateway-squid.conf) shipped by the egress_gw_journald source is the allow signal
    alert_route: Better Stack, read on demand with doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 24h --grep soleur-egress-gw, decoding .raw|fromjson|.message|fromjson|{decision,status,workspace}
logs:
  where: Better Stack (pino warn from the web app), Sentry events
  retention: Better Stack source retention; Sentry org event retention
discoverability_test:
  command: curl -s -H "Authorization: Bearer ${SENTRY_ISSUE_RO_TOKEN}" "https://jikigai-eu.sentry.io/api/0/organizations/jikigai-eu/events/?field=count()&project=4511404943671376&query=op:sandbox-network-denied&statsPeriod=24h"
  expected_output: "count()"
  credentials_required: "SENTRY_ISSUE_RO_TOKEN (event:read, org:read; from Doppler soleur/prd, run as doppler run -p soleur -c prd -- <command>) — Sentry event counts have no unauthenticated read path. This is a reachability probe: a zero count also prints count(), so it proves the token, endpoint and project pin, not that the op emits. The wiring probe that does not need credentials is grep -c 'op: \"sandbox-network-denied\"' apps/web-platform/server/permission-callback.ts, expected 1, run in CI."
```

## Encryption Posture

No new persistent store: the Phase 4b alert is a saved query over the existing Better Stack source `local.vector_prd_source_id` (deepen-plan Phase 4.10 fired on the `betterstack-logs-alerts.tf` path). The one connection this PR newly opens to sandboxed commands already exists for in-process WebFetch (ADR-278):

```yaml
at_rest: []  # no store introduced; the alert reads an existing log sink
in_transit:
  - connection: sandboxed command (via the SDK sandbox proxy) -> per-session egress forwarder (127.0.0.1) -> squid gateway (soleur-egress0, 172.31.100.2:8443) -> upstream host:443
    enforced_at: apps/web-platform/infra/egress-gateway-squid.conf (acl SSL_ports port 443; anything that is not an authenticated CONNECT to :443 is denied) and apps/web-platform/infra/egress-forwarder.mjs (GW_HOST / net.connect to the gateway)
    tls: end-to-end TLS (1.2+, negotiated by the command) inside an HTTP CONNECT tunnel; the proxy hops themselves (loopback, then the host-local Docker bridge) are plaintext HTTP carrying Proxy-Authorization
    cert_verification: on (the command's own TLS client verifies the upstream certificate; the gateway never terminates TLS)
    does_not_defend: a command that disables verification (curl -k) against a hostile upstream; a host-local process able to sniff the loopback or soleur-egress0 bridge reading the session's proxy credential; DNS-level redirection of an allowed name to a hostile origin
    disclosed_as: not-publicly-claimed
```

## Architecture Decision (ADR/C4)

### ADR

No new ADR (CTO F8). Amend ADR-278 (addendum 2026-11-18: the `SandboxNetworkAccess` arm is part of the boundary mechanics; measurements 3 and 4 re-run on 0.3.321 with the vitest and spike run URL; revocation and GitHub-host residuals). Add dated correction addenda to ADR-051 and ADR-272.

### C4 views

Read all three of `model.c4`, `views.c4`, `spec.c4`. Actors and systems checked: the agent runtime (`platform.engine.claude`), the per-dispatch forwarder (`platform.webapp.egressForwarder`), the egress gateway (`platform.infra.egressGw`), `publicInternet`, `anthropic`, the hosted user actors. All are modeled. No element, relationship or view inclusion changes. One description changes: the edge `platform.engine.claude -> platform.webapp.egressForwarder` gains the clause that each sandboxed CONNECT is admitted by canUseTool's `SandboxNetworkAccess` arm (live-forwarder sessions only; NO_PROXY, loopback and malformed hosts refused) and that hosts in `allowedDomains` do not take this edge. No counts move; `c4-count-parity.test.sh` must stay green.

### Sequencing

All records ship in this PR.

## Guard Contract

### Guard 1 — explicit SandboxNetworkAccess arm

**Property.** No `SandboxNetworkAccess` request is allowed unless the session's own forwarder is live at the moment of the request and the host is neither malformed, loopback, nor NO_PROXY-matched; every such request is decided by the dedicated branch.

**Assembly.** The single chokepoint is the first branch of the callback returned by `createCanUseTool`. Both construction sites feed it: `server/cc-dispatcher.ts` (passes `sandboxNetworkEgress` only from a live `webEgress`) and `server/agent-runner.ts` (never passes it). The decision logic is `decideSandboxNetworkAccess` in `server/sandbox-network-access.ts`, also consumed by the spike driver.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the arm (request falls to deny-default) | RED: unit and runtime tests assert layer `canUseTool-sandbox-network` and reason `not-entitled` |
| 2 | Move the arm below `isSafeTool` and add `SandboxNetworkAccess` to the safe set | RED: placement test (arm decides before any other branch for that name) |
| 3 | Key the cc-dispatcher field on `webEgressEntitled` instead of `webEgress` | RED: dispatcher test with grant true and spawn failure expects `not-entitled` |
| 4 | Drop the `isLive()` call (or cache it at construction) | RED: revocation unit test and runtime arm F |
| 5 | Make `isLive` key on `conversationId` only | RED: re-spawn-under-same-conversation test expects `egress-not-running` for the old token |
| 6 | Remove apex matching for `*.x` entries, or the trailing-dot strip | RED: property sweep (`supabase.co`, `x.supabase.co.`) |
| 7 | Second member: a host whose first spelling is denied and a second spelling (`X.SUPABASE.CO`, `[::1]:443`, `0x7f.1`) passes | RED: property sweep iterates every generated spelling, not the first |
| 8 | Allow path drops `updatedInput` | RED: allow-shape assertion |

**Harness rows:** mutate the runtime suite's tap to record nothing (every arm must then fail its "call recorded" assertion, and the floor test reds); a must-PASS input that is not canonical: an uppercase open-web host with a trailing dot (`EXAMPLE.TEST.`) must still be allowed in an entitled live session.

### Guard 2 — no direct route for allowed hosts (runtime)

**Property.** Every connection the arm allows, over any transport the SDK sandbox proxy offers, arrives at the forwarder carrying the session credential and never at a direct listener.

**Assembly.** `test/sandbox-network-access-runtime.test.ts` arms B, D, E: the recording gateway behind the real `infra/egress-forwarder.mjs` and the decoy listeners on 127.0.0.2 are the two observation points; transports enumerated: HTTPS CONNECT, plain HTTP, SOCKS/raw TCP.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove `HTTPS_PROXY` from the built env in the test (simulated degraded session with a forced allow) | RED: decoy or direct target receives the connection; arm B fails |
| 2 | Point the recording gateway's assertion at zero expected connections (dispatch vacuity) | RED: floor requires at least one recorded CONNECT per allowed transport |
| 3 | Second transport: HTTPS chains correctly but the SOCKS case is skipped | RED: per-transport floor lists every transport |

**Harness rows:** a suite edit that binds the decoy on a port the requests never target must red the "decoy reachable" canary (the suite proves its decoy can receive a direct connection before trusting its silence); must-PASS: a plain-HTTP request to an allowed host is accepted as chained when it arrives at the gateway as an absolute-URI request rather than a CONNECT.

### Guard 3 — single NO_PROXY source

**Property.** The NO_PROXY set the arm denies is byte-identical to the NO_PROXY the session's CLI env carries, and both equal today's literal.

**Assembly.** `WEB_EGRESS_NO_PROXY` in `server/sandbox-network-access.ts`, imported by `buildAgentEnv` (`server/agent-env.ts`) and by the arm (the default `noProxy` argument of `decideSandboxNetworkAccess`); the ctx carries no copy (CTO T1). The spike driver passes `env.NO_PROXY`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Re-inline a literal in `agent-env.ts` with one host removed | RED: `buildAgentEnv(...).NO_PROXY` vs the written-out literal |
| 2 | Edit the constant (add or drop a host) | RED: the same written-out-literal test |
| 3 | agent-env appends an extra host after the constant | RED: equality is on the full string, not a prefix |
| 4 | Add an import (pino, `@/`) to `sandbox-network-access.ts` | RED: import-set unit test (CTO T17) |

**Harness rows:** the expected side is a string literal written in the test file, never an import of the constant (CTO T1: comparing the constant with itself is circular).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "Add an explicit `SandboxNetworkAccess` arm to createCanUseTool, placed before the unknown-tool branch." [brief] | Phase 3, `permission-callback.ts` | mapped |
| 2 | "Unentitled session: deny on that explicit arm (the no-egress guarantee must live on this explicit branch, NOT on the unknown-tool branch)." [brief] | Proposed Solution rows 1-2, AC1 | mapped |
| 3 | "Entitled session (open-web egress entitlement): deny a host the session's NO_PROXY matches (exact, `*.suffix` or `.suffix`) and allow any other host" [brief] | Rows 3-6, Phase 2, AC2-AC3 | mapped |
| 4 | "Tests: an entitled session's request is allowed; an unentitled session's is denied by the explicit arm (assert the arm/reason, not just the deny" [brief] | Phase 3 tests, AC1-AC3 | mapped |
| 5 | "NO_PROXY-matched host in an entitled session is denied." [brief] | AC3, runtime arm C | mapped |
| 6 | "Pin against the real SDK where feasible — the spike driver ... records permissionCalls and networkDecisions." [brief] | Phase 1, Phase 6, AC5, AC21 | mapped |
| 7 | "Mirror a denial from that arm to Sentry (cq-silent-fallback-must-mirror-to-sentry)" [brief] | Phase 4, AC11 | mapped |
| 8 | "Correct ADR-051 and ADR-272 where they say `allowedDomains: []` closes sandboxed egress" [brief] | Phase 7, AC13 | mapped |
| 9 | "Re-running ADR-278 measurements 3 and 4 on SDK 0.3.311 ... do it if measurable locally, else record UNVERIFIED:<capability> and file an issue." [brief] | Phase 1 arms B/D on 0.3.321 (pin moved; CTO F7), ADR-278 addendum, AC5 | mapped |
| 10 | "Verification: Sentry / Better Stack (scripts/betterstack-query.sh) self-pulled; any hosted-session check uses a synthetic principal only" [brief] | Phase 8, AC15 | mapped |
| 11 | "Production dispatch ... needs the operator's explicit go-ahead: stop and name it as one plain ACTION." [brief] | decision-challenges operator row; AC15 | mapped |
| 12 | "Use `Closes #12585` in the PR body." [brief] | AC16 | mapped |
| 13 | "Pin it with a test against the real SDK." [issue #12585] | Phase 1 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| `server/sandbox-network-access.ts` | asks 3, 6 | asked |
| `test/sandbox-network-access.test.ts` | asks 3-5 | asked |
| `test/permission-callback-sandbox-network.test.ts` | asks 1, 2, 4, 7 | asked |
| `test/sandbox-network-access-runtime.test.ts` | asks 6, 9, 13 | asked |
| `server/permission-callback.ts` | asks 1, 2, 7 | asked |
| `server/permission-log.ts` | — | inferred — justification: the arm needs its own layer so tests can assert "the arm, not the unknown-tool branch" (ask 4) |
| `server/egress-forwarder.ts` (`isEgressForwarderLive`) | — | inferred — justification: CPO sign-off condition (c)2 and CTO F10; without it toggle-off would not revoke the allow |
| `server/agent-env.ts` | ask 3 ("the session's NO_PROXY") | asked |
| `server/cc-dispatcher.ts` | ask 3 ("Entitled session") | asked |
| `server/agent-runner-sandbox-config.ts` docstring | — | inferred — justification: repeats the false `allowedDomains` claim ask 8 corrects |
| `sdk-egress-driver.mts` | ask 6 | asked |
| `egress-injector-spike.yml` paths | — | inferred — justification: without the path the spike would not re-run when the module the driver imports changes (ask 6 pin rots) |
| ADR-051, ADR-272 | ask 8 | asked |
| ADR-278 | ask 9 | asked |
| `model.c4` edge | — | inferred — justification: plan Phase 2.10 C4 correctness; the edge describes the behavior this PR makes true |
| learning correction line | — | inferred — justification: the same false claim as ask 8 in a file planners read |
| Fail-closed fallback | — | inferred — justification: CTO blocking concern 1 and CLO ruling 2 (safety contract for the allow) |

### Split Assessment

- Subsystems touched: 3 — `apps/web-platform/server`, `apps/web-platform/test`, `knowledge-base/engineering/architecture` (plus one workflow paths line)
- Planned files: 17 | Estimated changed lines: ~650 (runtime test ~300)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1 Unentitled (no `sandboxNetworkEgress`): `SandboxNetworkAccess` is denied with layer `canUseTool-sandbox-network`, reason `not-entitled`, the not-entitled message; a test asserts the layer and the message is NOT `"Tool not permitted in this environment"`, for the cc ctx, the legacy-runner ctx, the support persona and a subagent call (`options.agentID` set). (`server/permission-callback.ts` first branch) AC1 asserts the `canUseTool-sandbox-network` layer on the allow path, the deny path and the support persona, which also proves placement ahead of the safe-set and MCP-prefix branches (CTO T5, replacing AC4).
- [ ] AC2 Entitled and live: a non-NO_PROXY DNS host and a non-loopback IP literal are allowed via `allow(toolInput)` (`updatedInput` echoed). (`server/sandbox-network-access.ts` `decideSandboxNetworkAccess`)
- [ ] AC3 Entitled and live: every NO_PROXY entry (exact, `*.x` including apex, `.x`), loopback literals in every form, and malformed hosts are denied with reasons `no-proxy-match` / `loopback-literal` / `malformed-host`; the property sweep covers case, trailing dot, brackets, ports, numeric shorthands and IPv4-mapped spellings.
- [ ] AC5 Real SDK on the shipped pin (0.3.321): `sandbox-network-access-runtime.test.ts` arms A-F (and arm G in Phase 1b) pass in the required webplat lane with `C4_BWRAP_REQUIRED=1`; the floor test proves every arm ran. Measurements 3 and 4 results are recorded in the ADR-278 addendum; any unmeasurable capability is recorded `UNVERIFIED:<capability>` with a filed issue.
- [ ] AC6 (CPO c1, HTTPS-only) Plain HTTP and SOCKS/raw-TCP attempts to an allowed host arrive at the forwarder (gateway enforces 443) or do not leave; none reaches a direct listener (runtime arm B). The spike run on the PR head shows squid's port-80 refusal still passes (criterion 6).
- [ ] AC7 (CPO c2, revocation) After `teardownEgressForwarder` (or a forwarder exit) the next request is denied `egress-not-running` (unit test plus runtime arm F); a re-spawn under the same `conversationId` with a new token does not re-arm the old ctx.
- [ ] AC8 (CPO c3, audit) Every allowed connection in the runtime test arrives at the recording gateway with the session `workspaceId:token` (the credential the audit attributes on).
- [ ] AC9 (CPO c4) AC1 holds.
- [ ] AC10 (CPO c5, same source) `buildAgentEnv({egressProxy}).NO_PROXY` equals today's literal written out in the test, and `agent-env.ts` and the arm both read `WEB_EGRESS_NO_PROXY` (CTO T1); `sandbox-network-access.ts` imports only `node:net` (CTO T17).
- [ ] AC11 Every deny calls `warnSilentFallback` with `feature: "cc-permissions"`, `op: "sandbox-network-denied"`, `tags.reason`; dedup per Query (each `createCanUseTool` instance) on `(reason, matchedEntry)` (two identical denies emit once, a different reason emits again).
- [ ] AC12 (CLO 3) For a deny of a distinctive host (`leak-canary-<random>.example`), a test serializes every sink the event and the decision touch and asserts the host string appears in none: every `warnSilentFallback` argument (message, tags, extra), every pino logger call including `logPermissionDecision` with `SOLEUR_DEBUG_PERMISSION_LAYER=1` (its `reason` argument), the deny `message` returned to the model, and the output of `scrubSentryBreadcrumb`/the `beforeSend` scrub in `server/sentry-scrub.ts` applied to the captured event. The guarantee lives at the call site (no host is passed into any field); the scrub run is a second check, not the mechanism.
- [ ] AC13 ADR-051 and ADR-272 carry dated addenda correcting the `allowedDomains: []` claim; ADR-278 carries the addendum (arm as boundary mechanics, 0.3.321 measurements, revocation window, GitHub-host residual); `agent-env.ts` measurement-4 comment and `agent-runner-sandbox-config.ts` docstring corrected; `model.c4` edge prose updated and C4 tests green.
- [ ] AC14 The egress-injector spike workflow runs on this PR's head SHA and all nine criteria pass; its run URL is cited in the ADR-278 addendum. If allowed traffic is observed off the forwarder (here or in AC5/AC6), the fail-closed fallback ships instead of row 6 and a follow-up issue is filed.
- [ ] AC15 Post-merge verification is self-pulled from Sentry and Better Stack (no production mutation). A zero count is not evidence: the no-host check runs only on a fetched event JSON; if no `sandbox-network-denied` event exists in the window, record `UNVERIFIED:prod-deny-event-shape` with an issue rather than passing on absence. A hosted entitled-session check is named as one plain ACTION for the operator's go-ahead; without it, `UNVERIFIED:hosted-entitled-sandboxed-egress` is recorded with an issue.
- [ ] AC16 PR body contains `Closes #12585`.
- [ ] AC17 (CTO T10) The cc-dispatcher real-factory test passes: with the grant on and the forwarder spawned, `sandboxNetworkEgress` reaches `createCanUseTool`, `isLive()` is true, and false after `teardownEgressForwarder`.
- [ ] AC18 (CTO T18, CPO c2) A warm dispatch whose `resolveWebEgressStrict` returns a definitive false tears the forwarder down, and the next `SandboxNetworkAccess` is denied `egress-not-running` (the test awaits the re-resolve promise); the within-turn window is stated in the ADR-278 addendum.
- [ ] AC19 (CTO T19) An entitled session with no GitHub token: `github.com` is denied `no-proxy-match` (current behavior pinned, not changed).
- [ ] AC20 (CTO T20) Dedup is per Query: two `createCanUseTool` instances each report the same deny once.
- [ ] AC21 (CTO T7, T9, T16) Runtime-test preconditions: step 0 (nested userns + aliases) ran or its failure is recorded `UNVERIFIED:nested-userns` with an issue; the permanent allow-all control hit the decoy; `MEASURED_ON_SDK` equals the installed SDK version; any decoy hit or a gateway connection without the session `Proxy-Authorization` fails the suite.
- [ ] AC22 (conditional, CTO T12) Only if Phase 1a fails: the arm denies every entitled request with reason `gateway-unverified` and the row-1 message, a follow-up issue is filed, and the CLO DPIA t4 re-screen runs before merge.
- [ ] AC23 (user-impact deepen pass) In-sandbox loopback: in arm C, a listener started inside the sandbox on `127.0.0.1:<p>` is reached by `curl http://localhost:<p>/` in an entitled session (curl honours NO_PROXY), and the tap shows whether the SDK asks `SandboxNetworkAccess` for it; the observed behavior is recorded in the ADR-278 addendum, or `UNVERIFIED:in-sandbox-loopback` with an issue.
- [ ] AC24 (CTO D1) Toggle-off: after `setWebEgress(false)` the route tears down this host's live forwarders for the workspace, and the next `SandboxNetworkAccess` is denied `egress-not-running` (route test).
- [ ] AC25 (CTO D2) The Better Stack alert on granted-but-degraded denies exists in Terraform with its drift guard green; the PR body's first line states that merging creates exactly these two Better Stack resources; the model-facing message is keyed on (reason, granted) with no host.
- [ ] AC26 (CTO D3) N identical denies produce N pino warn lines and 1 Sentry capture.
- [ ] AC27 (CTO D7) A host carrying a port, `@`, `/` or whitespace (outside a valid IPv6 literal) is denied `malformed-host`; Phase 1a records the observed SDK host format.

## Domain Review

**Domains relevant:** Engineering, Product, Legal

### Engineering

**Status:** reviewed
**Assessment:** CTO ruled F1-F11 (see decision-challenges.md): live-handle keying, call-time liveness by token identity, first-branch placement, over-deny matching, enum-bounded Sentry dedup with no raw host, measure on 0.3.321 with a required-lane real-SDK test plus the spike run as a merge precondition, no new ADR, fail-closed fallback if allowed traffic is ever off the forwarder.

### Legal

**Status:** reviewed
**Assessment:** CLO: no legal document, DPIA or Art. 30 change, provided allowed hosts leave only through the forwarder and gateway (else DPIA t4 re-screen before merge); Sentry field set acceptable with no raw hostname by any channel (AC12); the past silent failure is not a breach.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** soleur:product:cpo
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings

No UI file changes. The deny messages are model-relayed product copy: CPO required state-accurate, jargon-free text; CTO F11 confirmed no technical objection. CPO plan-time sign-off granted with conditions, mapped to AC6-AC10.

## Test Scenarios

- unit: Given no `sandboxNetworkEgress`, when `SandboxNetworkAccess {host:"example.test"}` arrives, then deny, layer `canUseTool-sandbox-network`, reason `not-entitled`.
- unit: Given a live egress, when host is `example.test` / `EXAMPLE.TEST.` / `93.184.216.34`, then allow with `updatedInput`.
- unit (property): Given a live egress, for every generated spelling of each NO_PROXY entry and each loopback form, then deny with the expected reason; never allow.
- unit: Given `isLive` false or throwing, then deny `egress-not-running` (liveness evaluated before host checks).
- unit: Given a support persona or `options.agentID`, then the same arm decides; no support-escalation record is written.
- unit: Given a NO_PROXY deny of a canary host, then no sink argument contains the host.
- integration: Given cc-dispatcher with grant true and forwarder spawn failure, then the ctx has no `sandboxNetworkEgress`.
- integration (real SDK, bwrap): runtime arms A-F as in Phase 1; `pyramid-justified: the property is the SDK's own routing of a sandboxed connection after the callback answers, which no mock can observe`.
- regression: Unknown non-SandboxNetworkAccess tool still reaches deny-default with its existing message.

## Dependencies & Risks

- The SDK's routing after an allow is the load-bearing unknown (direct route, retry-direct, per-host caching). Phase 1 measures it before the allow ships; the fallback is decided in advance.
- The spike workflow depends on Docker, a local Supabase stack and image pulls; a harness failure reads INCONCLUSIVE, not a pass, and blocks merge per AC14 until re-run green.
- Runtime test duration: each arm is one scripted turn (~10-30 s); `startAnthropicStub(command)` fixes one command per stub, so each arm gets its own stub and runs ONE scripted turn whose single compound command makes every connection attempt for that arm; arm F's request, teardown and re-request live in one command, with the test firing `teardownEgressForwarder` while the command sleeps. The forwarder is started through the production `spawnEgressForwarder` (with `EGRESS_TOKEN_DIR` and `EGRESS_GW_HOST/PORT` set) so teardown has a registry entry to remove. Phase 1a records the measured wallclock and sets per-arm timeouts from it.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `soleur:work`.
- Do not use `hasEgressForwarder` in production code; it is a test hook (CTO F10). Use the new token-identity export.
- Do not add `SandboxNetworkAccess` to any `allowedTools` list: a bare entry auto-approves before `canUseTool` runs (`CLAUDE_SDK_CAN_USE_TOOL_SHADOWED`, measured 2026-11-10).
- Capture `webEgress` in a `const` before building the `isLive` closure in cc-dispatcher. Today `webEgress` is not reassigned after its try block, so this guards against a future edit rather than a current bug. Liveness also covers forwarder crashes: the exit handler deletes the registry entry (`egressForwarders.get(conversationId)?.proc === proc`), so `isEgressForwarderLive` turns false without `teardownEgressForwarder`.
- The spike driver calls `main()` at import: import the production module into the driver, never the reverse.
- GitHub hosts: `github.com` and `api.github.com` are in `ENTITLED_EGRESS_DOMAINS` (`server/agent-runner-sandbox-config.ts`), only when the dispatch minted a GitHub token (`allowGithubEgress`); then the SDK never asks the arm for them and `git clone https://github.com/...` keeps working on the SDK's own allowed path. With no GitHub installation or a failed mint, `github.com` is not in `allowedDomains`, matches NO_PROXY, and is denied `no-proxy-match` even for public repos (plan-review, CPO); a unit case pins that for an entitled session with no GitHub token. Other `*.github.com` subdomains (for example `codeload.github.com`) match NO_PROXY and are denied `no-proxy-match`, which is today's effective behavior too. That is a stated consequence of CTO F9 (NO_PROXY membership is #11637's), not a side effect to fix here.
- `warnSilentFallback` takes an optional `message`; pass the explicit literal `"sandboxed network request denied"` so a Better Stack or Sentry search keyed on it does not depend on the helper's default.

## References

- Issue #12585; spike PR #12518; #11637; #9534; ADR-051, ADR-272, ADR-278, ADR-311, ADR-325.
- `knowledge-base/project/specs/archive/20261110-211546-feat-agent-runtime-sandbox-eval/injector-spike-results.md` and its `decision-challenges.md` (R34, R35).
- `knowledge-base/legal/audits/2026-10-05-dpia-screening-agent-web-egress.md`.
