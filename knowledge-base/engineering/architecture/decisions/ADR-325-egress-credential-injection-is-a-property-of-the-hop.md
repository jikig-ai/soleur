---
title: Egress credential injection is a property of the hop, decided apart from the isolation runtime
status: adopting
date: 2026-11-10
---

# ADR-325: Egress credential injection is a property of the hop, decided apart from the isolation runtime

## Context

Issue #12517 re-opened the agent runtime question: keep the bwrap sandbox and the egress gateway (ADR-278), or move agent sessions to a managed sandbox platform. The operator's deciding criterion is whether one mechanism covers every HTTPS-credentialed tool (`gh`, `git`, any HTTPS-API CLI) without per-tool code on our side. Today an agent in an entitled session cannot push: ADR-311 found that the SDK's credential `mask` mode does not substitute on our proxy carrier and ruled (Decision 4) that any network-layer credential path is rejected unless every vend is gated by an unconsumed ADR-309 approval row. The per-verb alternative (#12467) adds one gated tool at a time.

The brainstorm (`knowledge-base/project/brainstorms/2026-11-09-agent-runtime-sandbox-eval-brainstorm.md`) found that the criterion does not depend on the isolation substrate: session-to-tenant identity already exists at the hop (ADR-278 Decision 3), so injection can be specified against the hop and measured on today's runtime, and the work carries into the gVisor path (#9842).

## Considered Options

Ranked first on the operator's criterion, then on cost, residency and reversibility.

| Option | One mechanism, no per-tool code | Isolation | EU posture | Cost and effort |
|---|---|---|---|---|
| A. Keep bwrap, add a self-run injector on the hop | Yes if measured (measured by this ADR's spike: yes) | Unchanged | Unchanged | Lowest; no new vendor |
| C. gVisor per session (#9842) plus the same injector | Yes; A's hop interface carries into C (Decision 1) | Best self-run | Unchanged | High; 15 open spike issues (S0 #9859 to S13 #10536) |
| B. Cloudflare Sandbox (programmable outbound handler) | Yes per vendor documentation, untested by us | Firecracker microVM, per-sandbox CA | US importer, no stated hard EU guarantee | Additive spend plus loop and tool remoting and a legal rewrite |
| B'. Vercel Sandbox | Declarative injection; the programmable route forwards to our own proxy | Firecracker microVM, per-sandbox CA | DPA: primary processing in the US | As B |
| D. Kata plus OpenSandbox Credential Vault | Yes at README level | Hardware boundary | Unchanged | Needs a KVM node; does not run under gVisor |
| F. Daytona, E2B | Daytona: cloud only. E2B: host-keyed only | Mixed | US importers | Rejected in the brainstorm |
| E. Status quo plus per-verb tools (#12467) | No: #12188 added one gated write verb in 36 files (9 source), and #12465 a read tool in 42 (measured with `gh pr view --json files`) | Unchanged | Unchanged | Linear per verb |

A, B, C and D tie on the criterion and E fails it. The tiebreak goes to A: the runtime has no dedicated host (it shares web-1), there are no external hosted users, only GitHub demand is evidenced, and A's hop interface carries into C. What does not carry unchanged is listed in Decision 1. The rejected candidates and their reasons are listed in the brainstorm's "Rejected or set aside" table.

## Decision

1. **Injection is a property of the hop.** Credential injection is specified and built against the egress hop, apart from the isolation runtime. The independence claim covers the interface only: a CONNECT proxy with per-session authentication that the runtime's network path dials. The carrier (the SDK sandbox runtime chaining from the sandbox's network namespace to a container-loopback proxy) is tied to the runtime (ADR-278 measurement 1), and so are criteria 1, 5 and 6 of the measurement: they rest on bwrap's masked paths, `canUseTool`'s file-tool containment and the Read tool's own refusals. #9842 must re-measure the carrier and those three criteria.
2. **Approach A is measured first; the managed platform is the contingency.** A self-run, digest-pinned injector (iron-proxy v0.56.0) was measured with the production run tuple's flags on a GitHub-hosted runner (not on the production host) behind a per-session CONNECT router, with an approval hook calling the ADR-309 RPCs. The Cloudflare trial is a sibling PR under #9859 Arm D (brainstorm Decision 9); it keeps its own spec directory.
3. **The EU-only promise is negotiable for a clear gain, not a hard constraint** (brainstorm Decision 3, an operator ruling). "Clear gain" means any one flip fact below holds, the Cloudflare trial has passed, and the CLO's gates are met.
4. **CA scope** (brainstorm Decision 6): one ephemeral CA per session, name-constrained to the inject hosts, its key held outside the sandbox and deleted at session end. A DNS constraint on `github.com` also permits every subdomain (RFC 5280), so the effective scope is the four inject hosts plus `*.github.com`.
5. **Fold into #9842, do not replace it** (brainstorm Decision 9): S3 (#9845) is widened to generic per-host injection with approval attachment, and S0 Arm D (#9859) from paperwork to the Cloudflare trial.
6. **ADR-311.** Decision 4 is cited here, not restated: every vend is gated by an ADR-309 row. The measured hook satisfies it for writes and vends allowlisted reads without a row (brainstorm Decision 5). Decision 4 is therefore amended only by the merge-conditioned addendum on ADR-311 that records this measurement, worded "on merge of PR #12518". ADR-311 Decision 6 stays frozen as narrowed: no public or legal wording changes until a measured production control exists (brainstorm Decision 10).

**Flip facts** (when a managed platform becomes the primary path):

- **F1.** The self-run injector fails criterion 2 or 5 on our carrier.
- **F2.** The loop and tools prove remotable (S4 #9846 passes) and gVisor fails its file-I/O gate (S1a #9843).
- **F3.** The hosted-concurrency trigger (roadmap row 4.6, "5+ concurrent users") fires before #9842 Stage 1 is ready.
- **F4.** A cross-tenant isolation incident, or a vulnerability in bwrap or the SDK sandbox (ADR-315's first triggers).

**CLO gates**, quoted verbatim:

> "CLO gates for any managed platform: a signed DPA that names the product; an EEA contracting entity or a transfer mechanism covering that product; an acceptable sub-processor list; a transfer impact assessment and DPIA; a successor to the T-1 location gate with fresh operator acknowledgement; published documents changed before any tenant data moves."

The mapping from the T-1 location gate to #5274 is unverified: the compliance posture register carries it ("T-1 EU-location pin + CI gate | #5274"), and #5274's own body does not mention a location gate.

**Production gate.** DPIA trigger t3 (#9853) gates the first PR that puts TLS termination on a tenant-serving hop (#9845, #11637). The ePrivacy question on terminating tenant traffic is parked for outside counsel before that PR.

## Consequences

- **#11637 owns adoption.** The measured mechanism needs production changes this PR does not make (each measured with the change applied in the harness only): removing the inject hosts from `NO_PROXY` (production sends GitHub traffic direct today), an explicit `SandboxNetworkAccess` arm in `createCanUseTool` (#12585; production denies it as an unknown tool, entitled sessions included), a sanctioned `gh` placeholder token, `NODE_USE_ENV_PROXY=1` for Node fetch, a migration adding the vend tool name to `approval_request`'s `tool_name` CHECK, and a hook deadline or watchdog. #11637 is blocked by #12585. It also inherits these preconditions from the review of this PR (rulings R36 to R40 in the spec's decision record):
  - per-session installation tokens minted with `repositories` set to the session allowlist (`generateInstallationToken` already takes it), because GraphQL queries and mutations are not repository-scoped by the hook; GraphQL refused in production until then; a GraphQL mutation's approval card names the repository, resolved server-side, or the mutation is refused (R38);
  - the injector's request-body cap stated as a product limit: iron-proxy cuts bodies above `max_request_body_bytes` with no error, so the hook refuses at the cap, and pushes above it cannot be approved (R39, R40);
  - the `secrets` rules' method list generated from the policy, and the hook's SNI and tunnel checks kept (R36, R37);
  - action hashing through `server/approval/canonical.ts`, not the spike's recipe;
  - a git-visible pending-approval signal (git shows only a bare 403 for every refusal reason), and pending or refused vends shown to the owner, not only mirrored for operators;
  - `consumed` recorded as "approval spent", not "write delivered": an RPC abort after the server commits spends the approval with nothing sent (ADR-311 Decision 5);
  - correcting the `agent-env.ts` comment that the SDK's API path transits the proxy (ADR-278 addendum, 2026-11-10).
- **Forwarder-first ordering is the alternative #11637 must weigh.** In the measured ordering a dead injector stops only inject-host traffic; the CLI's own Messages API traffic goes direct under production `NO_PROXY` and kept streaming with the injector killed (CTO R17, R33; this reverses ADR-278 measurement 4 for SDK 0.3.311, recorded in an ADR-278 addendum). A forwarder-first chain would put the injector in front of everything.
- **Hook key custody is part of the blast radius.** One hook process holds the service-role and HMAC keys for every session, as the dispatcher does.
- **Tracer facts that bind any production design (CTO R24 to R27).** iron-proxy v0.56.0 terminates every tunnel, so selective termination needs a router (this router, forwarder-first, or an upstream passthrough). A frozen hook meets no iron-proxy deadline. The plain-HTTP, HTTPS and metrics listeners cannot be switched off and default to all interfaces. The hook channel is authenticated by mutual TLS. The spike adds the measured guard that every non-CONNECT request must arrive on a tunnel to its own host (R28).
- **Reads vend without a row**, so the confused-deputy residual is recorded, not removed: an agent can read any allowlisted repository over REST and git, and any repository the token reaches over GraphQL, without a human seeing each read (R38).
- **The results go stale at merge** until #11637 owns the job; the re-measure trigger is in the results note.
- #12467 (per-verb tools) closes on the merge of a GO, superseded by #11637 as the home of approval-gated writes. It reopens if #11637 is closed as not planned or drops the injector, if a re-run of the spike job under #11637 records NO-GO or fails criterion 2, 3 or 5, or if #11637 has no merged PR at the next `soleur:product-roadmap` review of Phase 4 (CTO R42).
- **Status.** This record stays `adopting` on merge, becomes `accepted` when #11637 ships the injector with the spike job green, and `superseded` if a #12467 reopen trigger fires or #9859 picks a managed platform (CTO R42).
- Nothing here offers credential injection to users, treats vendor documentation as a control, asserts that Cloudflare's DPA covers Sandbox or Containers, or claims EU placement for any managed platform.

## Cost Impacts

None from this ADR. The spike runs on GitHub-hosted runners with no secrets and no paid vendor. The Cloudflare trial (USD 50 over 14 days, synthetic data only; brainstorm Decision 8) is approved and lands, with its expense row, in the sibling PR.

## NFR Impacts

Assessed against the NFR register with `soleur:architecture assess` (affected: agent runtime, egress hop, approval store). No NFR changes status in this PR, which ships test-path code only.

- **NFR-024 Attack Prevention, NFR-038 Least Privilege Container Images (applied here to credential custody):** the measured design keeps the credential out of the sandbox and out of the agent's file tools (criterion 1) and scopes each session's CA (criterion 9). Adoption under #11637 would move these for the agent runtime.
- **NFR-026 Encryption In-Transit:** TLS is terminated at the injector for the four inject hosts only and re-established to GitHub with verification on; every other host stays tunnelled end to end (criterion 2). The termination is the DPIA t3 trigger above.
- **NFR-001 Logging, NFR-033 Unified Logging Format:** the hook emits `SOLEUR_EGRESS_VEND`, `SOLEUR_EGRESS_VEND_REFUSED` and `SOLEUR_EGRESS_CONNECT` with ids and classes only; no log carried a secret or a body (criterion 6). Mirroring refusals to Sentry is #11637's.
- **NFR-007 Circuit Breaker:** a dead or stalled hook fails closed within the client's bound, but a frozen hook has no iron-proxy deadline; a watchdog is a #11637 precondition (criterion 8).
- **NFR-034 Stable Dependency Versioning:** iron-proxy is pinned by digest; mirroring it into our registry and a bus-factor review are preconditions for adoption.

## Principle Alignment

- **AP-011 ADRs for architecture decisions:** aligned (this record).
- **AP-012 New vendor checklist:** aligned in scope. iron-proxy runs only in a test path here; the checklist applies before #11637 adopts it.
- **AP-020 Untrusted input at the agent boundary:** aligned. The hook decides on request bytes the agent controls, so it normalises the canonical path and refuses unparseable or ambiguous requests before matching or hashing.
- **AP-001, AP-008:** not applicable. No infrastructure or secret changes; every spike secret is a generated decoy.

## Diagram

The C4 model gains no element in this PR. An `egressInjector` container (the per-session injector and its approval hook, between the agent runtime and the egress forwarder) is a pending change assigned to #11637, added when the injector reaches a production topology.

## Measured outcome — injector

GO: on run [42823659776](https://github.com/jikig-ai/soleur/actions/runs/42823659776), the production run tuple, all nine criteria passed. Record: [injector-spike-results.md](../../../project/specs/feat-agent-runtime-sandbox-eval/injector-spike-results.md), raw JSON beside it.

- The real credential was not observable in the sandbox or by the agent's file tools (criterion 1).
- git, gh, curl and Node fetch reached GitHub with the real credential through the injector, and the open-web stream was untouched (criterion 2).
- Writes waited for an owner's approval and spent it once, bound to the exact request (criterion 3); allowlisted reads vended with no row (criterion 4).
- Sessions could not obtain each other's credential (criterion 5).
- ADR-278's controls did not regress, and no log carried a secret (criterion 6).
- A new GitHub verb took one policy data file (criterion 7).
- Failures were visible and closed (criterion 8).
- The CA scope held for OpenSSL, GnuTLS and Node clients (criterion 9).

Flip fact F1 does not hold. The measurement found and fixed two hook defects and a policy defect: the hook refused iron-proxy's origin-form request targets, it vended a request sent straight to one of iron-proxy's other listeners, and the canonical path dropped literal segments so two verbs could share an approval. The production changes #11637 needs are listed in the results note and above; the `SandboxNetworkAccess` denial is filed as #12585.
