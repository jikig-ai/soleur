---
title: The credential-broker mechanism is measured before it is built
status: adopting
date: 2026-10-30
supersedes: none
issue: 9543
related: [9543, 9601, 4672, 9534, 11635, 11636, 11637, 11638]
related_adrs: [ADR-272, ADR-278, ADR-305, ADR-309]
tags: [egress, sandbox, credentials, security, agent-runtime, approval]
brand_survival_threshold: single-user incident
---

# ADR-311: The credential-broker mechanism is measured before it is built

## Status

Adopting, 2026-10-30. Describes the target state: no credential-bearing surface ships for web-egress-entitled sessions until the mechanism is measured and the approval gate exists in the path that runs those sessions. This ADR ships a measurement and a constraint. It ships no broker. Narrows the route ADR-278 Decision 5 names back to credentialed push (it is now the cc approval wiring #11635 then the push tool #11636, as well as the broker #11637) and records the outcome of the ADR-272 `mask` deferral where it could be measured.

## Context

ADR-278 Decision 5 denies every credential to the sandbox of an entitled session, so those sessions cannot `git push`, call `gh`, or use a connected provider in-sandbox. Issue #9543 asks for a broker that restores that without placing a reusable secret in the sandbox. ADR-272 deferred the SDK's `credentials` `mask` mode to this issue as the in-SDK candidate. Three mechanisms were on the table:

- **A** the SDK `mask` mode: the sandbox sees a sentinel and the host proxy swaps it for the real value on egress to `injectHosts` (HTTPS needs the experimental `network.tlsTerminate`).
- **B** a bespoke endpoint on the forwarder that mediates the credential use.
- **C** the existing approval-gated server-side tool `github_push_branch`.

Two facts on `main` shaped the decision. First, entitled sessions run in the cc dispatcher (forwarder spawn in `server/cc-dispatcher.ts`), while `buildGithubTools` (which registers `github_push_branch`) and the ADR-309 `ExecutionGrants` object are wired only in the legacy runner (`server/agent-runner.ts`), and the legacy runner never has web egress. Option C is therefore a build in the cc path, not a confirmation. Second, ADR-278 measurement 1 showed the sandboxed child's localhost is not the container loopback, and nothing established how a sandboxed caller would authenticate to a bespoke endpoint without holding a reusable secret.

## Decision

1. **No credential-bearing surface ships for entitled sessions before the mechanism is measured in the production topology.** This change adds no tool, no endpoint, no flag, no copy and no legal text. Entitled sessions keep "cannot push", so the Phase-A statement in the toggle copy stays true.
2. **The mechanism is chosen only from measured outcomes.** The spike (`apps/web-platform/test/broker-mechanism-spike.test.ts`, raw record in `knowledge-base/project/specs/feat-one-shot-9543-egress-credential-broker/phase-0-measurements.md`) measured, on one host with the pinned SDK 0.3.284 and a stub gateway:
   - **(c)** `tlsTerminate` is honored when set through `options.sandbox.network` (the sandboxed client saw the sandbox-runtime CA) and not when set through `options.settings`; a CLI `--settings` control arm was tried and dropped because it could not tell "not forwarded to the CLI" from "not honored by it".
   - **(a)** `mask` with `injectHosts` did **not** substitute on the env-proxy carrier in any arm that could be measured (managed-domains flag on and off, plain HTTP, HTTPS without termination): the sandbox saw the sentinel and the destination received the sentinel. The HTTPS arm under `tlsTerminate` is `unmeasurable`: the handshake completed with the runtime CA but the request never reached the destination.
   - **(b)** a request to a virtual host reached its destination over the ordinary egress path (through the real forwarder and a gateway that authenticated the forwarder-injected credential; the virtual host is an allowed hostname, not a broker endpoint), and the sandbox could not read the proxy-hop credential. The forwarder takes tenant and token from its own environment and requires a matching inbound token. Gateway attribution is per connection, not per request: the runtime multiplexes sequential plain-HTTP requests over one forwarder connection.
3. **What is decided and what is left open.** Mechanism A is not usable on the current carrier as measured; whether it substitutes when the runtime handles a request without an upstream proxy chain was not measured, and the HTTPS-under-termination arm is open. The ADR-272 `mask` deferral is therefore resolved for the carrier and arms measured, and left open for the rest. Mechanism B is reachable over plain HTTP, but a push to the forge host is HTTPS, so neither A nor B has been shown for the real use case; and a bearer credential held by any in-sandbox caller is not secret from the agent, which shares its user and namespaces; the identity signals B can rely on are network position (the per-conversation forwarder) and the approval gate, not a secret. Mechanism C needs the approval gate and grants in the cc path first.
4. **Approval is part of any credential path.** Any mechanism that injects a credential at the network layer, or mediates its use through an endpoint, is rejected unless every vend is gated by an unconsumed action-bound ADR-309 approval row (repo, ref, commit), because a request from a sandboxed `git` is not a tool call and so, by inference from ADR-305 Decision 1 (`canUseTool` is the only approver of gated tools), never reaches `canUseTool`; no probe here exercises `canUseTool`. A `works` outcome in the spike means the mechanism substitutes; it does not mean the mechanism is acceptable. This needs three additions ADR-309 does not have: a `credential-vend` tool name in `APPROVAL_REQUIRED_TOOLS`, a proposal path that creates the pending row, and a non-tool consumer (ADR-309 rejects server-side execution of an approved payload as Option E). With the `approval-queue` flag off there are no durable rows, so a vend must be denied. The mechanical guard that exists today is the boot-time throw in `server/cc-dispatcher.ts` when `CC_MCP_ALLOWLIST` holds an approval-required tool; #11636 and #11637 must not weaken it except as the output of #11635. Network-layer injection fires on any sandbox request to `injectHosts` (for example a push to the forge host), so it bypasses the gated tier by construction unless it is gated.
5. **Vend audit is durable when a vend exists.** `emitWorkspaceActionContext` writes a log line only and has no vend action. The broker follow-up records the approval row plus a new `credential-vend` action line, mirrors every refusal to Sentry, and derives the tenant from the registry binding for the conversation, never from a value the sandbox controls.
6. **Public claims follow the measurement.** The toggle copy, privacy policy, data-protection disclosure, Article 30 register and DPA item 18 do not change until a broker is live and measured; they may then say only what was measured.

## Limits of the measurement

Measured on a developer workstation, not the production image (its seccomp and AppArmor profiles differ), against a stub gateway, with decoy credentials and a scripted model. No arm may be generalized to production. The re-measure trigger is any change to the pinned SDK version or to the sandbox flags in `buildAgentSandboxConfig`; the suite asserts the exact SDK pin, so a bump fails it and forces a re-measure decision; the re-run itself is not automated. The raw outcomes are in `phase-0-measurements.md`, which moves to `specs/archive/` with the feature; Decision 2 above is the durable summary.

## Open items

- Can an approved ADR-309 row be consumed by a non-tool caller (a broker verifying and consuming the row server-side)? Owned by the broker follow-up.
- Why the HTTPS request does not reach the destination under `tlsTerminate`, and whether trusting the destination's certificate on the host side changes it. Not isolated here.
- Whether `mask` substitutes when the sandbox runtime serves the request without an upstream proxy chain.
- Repeat the measurement under the production run tuple (the docker suite pattern used for ADR-272).

## Alternatives considered

| Alternative | Why not now |
|---|---|
| Build a vending endpoint now (B) | No verified caller-authentication path from inside the sandbox; a secret held in the sandbox contradicts the requirement. |
| Register `github_push_branch` in the cc path now (C) | Needs the approval gate and grants in that path first; adding a gated tool there without them would bypass or invent a second gate. Tracked as follow-ups F1 and F2. |
| Adopt `mask` and rely on the SDK (A) | Did not substitute on the measured carrier (env proxy URL, chained through the forwarder); other carriers are unmeasured. |
| Edit the toggle copy and legal text to say credentials are brokered | Would claim a control that does not exist. |

## C4

No component is added, changed or removed, so no `.c4` file changes. The existing elements and edges (`platform.webapp.egressForwarder`, `platform.infra.egressGw`, and the `claude -> egressForwarder -> egressGw -> publicInternet` edges) already model the carrier the spike used.

## Consequences

- Entitled sessions remain unable to push in-sandbox; the quickest route to a push capability is the cc approval gate (F1) then a cc push tool (F2), which do not depend on the broker (#11635, #11636).
- The broker implementation (#11637, F3) starts from these measurements and from Decision 4; BYOK provider credentials for entitled sessions (#11638, F4) wait for #11637 and #11635.
- The measurement suite stays in the repository as the harness a future SDK bump can re-run.
