# Tasks: egress credential broker, measurement spike and ADR (Ref #9543)

Plan: `knowledge-base/project/plans/2026-10-30-feat-egress-credential-broker-plan.md`
Branch: `feat-one-shot-9543-egress-credential-broker` | Draft PR: #11624

## Phase 1: Spike harness and probes (test-first)

- 1.1 Write `apps/web-platform/test/helpers/broker-spike-scan.ts` with `scanSandboxSurfaces(observations, declaredSecrets)` and `classifyOutcome({ probe, observedEvents, scan, substitutionObserved, evidence? })`; `evidence` is a required field of the outcome type.
  - 1.1.1 Write the hermetic unit block first (RED): second unmasked secret, value reachable only through Glob/Grep, zero observed events, conclusion without evidence, randomized names (H2), probe command replaced by `true` (H1).
  - 1.1.2 Make it GREEN.
- 1.2 Write `apps/web-platform/test/broker-mechanism-spike.test.ts` following `test/sandbox-credential-deny-runtime.test.ts` (real SDK `query`, real `buildAgentSandboxConfig`, bubblewrap shim, scripted stub, `SANDBOX_OK` skip, `C4_BWRAP_REQUIRED` fail, same Haiku 4.5 model pin and carve-out comment).
  - 1.2.1 Inline helpers: TLS echo target with ephemeral CA (openssl), plain-HTTP echo, CONNECT-tunnel stub gateway.
  - 1.2.1a Harness hygiene: explicit allowlisted child env via `hermetic-cli-env.ts`; ambient CI token names in `declaredSecrets`; stub gateway on 127.0.0.1 ephemeral ports refusing any CONNECT but the echo host:port; CA and key under `mkdtemp` 0700, removed in `afterAll`, trusted only via `curl --cacert`.
  - 1.2.2 Topology: non-loopback test hostname via curl `--resolve`/`--connect-to`; clear or override `NO_PROXY`; real unmodified `infra/egress-forwarder.mjs`; hostname in `allowedDomains` and `injectHosts`.
  - 1.2.3 Probe (c) first: `options.sandbox.network.tlsTerminate` and `options.settings.sandbox.network.tlsTerminate` arms; oracle is a runtime-CA certificate (the CLI `--settings` control and the upstream-trusted variant were dropped: `unmeasurable` by construction).
  - 1.2.4 Probe (a): protocol (http, https) by `tlsTerminate` by `allowManagedDomainsOnly` arms, plus the control arm with the `mask` entry removed.
  - 1.2.4a Probe (a) scoping arms: host outside `injectHosts`, reflecting echo, redirect or Host/SNI mismatch.
  - 1.2.5 Probe (b): reachability of a virtual-host request at the forwarder, how the forwarder identifies the session, whether the sandbox can read or derive the proxy-hop credential.
  - 1.2.6 Record outcomes (`works`, `does-not-work`, `leaks`, `unmeasurable(reason)`) with evidence; a treatment-arm `leaks` is recorded, not failed.
- 1.3 Run the suite on this host with `C4_BWRAP_REQUIRED=1`; capture raw output.

## Phase 2: Record the results

- 2.1 Write `knowledge-base/project/specs/feat-one-shot-9543-egress-credential-broker/phase-0-measurements.md` (host, SDK and bwrap versions, commands, raw outcomes with evidence).
- 2.2 Re-probe the next free ADR ordinal across `origin/main`, remote branches and open-PR files (ADR-310 is claimed), then write `ADR-311-credential-broker-mechanism-measured-before-built.md` (states only what was measured; open items; re-measure trigger; `related_adrs` for ADR-278 Decision 5 and the ADR-272 `mask` deferral).
- 2.2a ADR constraints: measured-on-host wording, no generalizing to production, "resolves" only for non-`unmeasurable` outcomes, no "safe"/"secure"/"no secret reaches", network-layer injection rejected unless gated by an unconsumed action-bound approval row; measurements file holds names and decoy hashes only, secret-pattern scan before commit; CI warning annotation for `leaks`/`unmeasurable`.
- 2.3 Add a one-line neutral dated addendum pointer to ADR-272 and ADR-278 (no decision text changes).

## Phase 3: Follow-ups and tracking

- 3.1 File F1 (approval gate and `ExecutionGrants` in the cc dispatcher), F2 (register `github_push_branch` in the cc platform server), F3 (broker mechanism per spike result, with durable vend audit), F4 (BYOK for entitled sessions): milestone `Phase 4: Validate + Scale`, label `domain/engineering`, re-evaluation criterion each, links to the epic and #9543.
- 3.2 Set blocked-by edges (F2 by F1; F3 by F1 and the spike; F4 by F3 and F1) and verify with `gh issue view <N> --json blockedBy`.
- 3.3 Comment on #9543 describing the split; the PR body uses `Ref #9543`.

## Phase 4: Verification

- 4.1 Existing `sandbox-credential-deny-*` and `web-egress*` suites, `c4-count-parity.test.sh`, `components.test.ts` pass unchanged; `model-launch-review.test.ts` passes with its extended assertion.
- 4.2 Extend the SDK-path-file assertion in `plugins/soleur/test/model-launch-review.test.ts` to the new test; check whether `scripts/lib/test-affected-paths.sh` needs the new test registered; add it if so.
- 4.3 `technical-ruling-gate.sh --branch` exits 0; `git diff --name-only origin/main...HEAD` is confined to the plan's Files lists.
- 4.4 After merge: `soleur:postmerge`; confirm F1-F4, ADR-311 and the addenda are on main.

## Filed follow-ups

- F1 #11635 (cc approval gate and grants), F2 #11636 (cc push tool, blocked by F1), F3 #11637 (broker mechanism, blocked by F1), F4 #11638 (BYOK, blocked by F3 and F1); comment posted on #9543.

## Operator holds (not performed here)

- Creating or flipping any feature flag, and any production enablement.
- The egress-audit enablement gates tracked on #11237.
- Legal wording sign-off at flag-on.
