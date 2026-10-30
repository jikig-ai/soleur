# Phase 0 measurements: credential-broker mechanism spike (#9543, ADR-311)

Raw outcomes of `apps/web-platform/test/broker-mechanism-spike.test.ts`, run with `C4_BWRAP_REQUIRED=1` and `BROKER_SPIKE_OUT` set. This file records surface names and outcome words only. It holds no environment dump, no `/proc` content and no decoy value (a secret-pattern scan over the raw output returned 0 matches before it was quoted here). It moves to `specs/archive/` with the feature; ADR-311 Decision 2 is the durable summary.

## Conditions (what these results do and do not cover)

| Item | Value |
|---|---|
| Host | Linux 7.2.8 x86_64, a developer workstation. **Not** the production image: its seccomp and AppArmor profiles differ (the limit ADR-272 records for its own measurement). |
| Agent SDK | `@anthropic-ai/claude-agent-sdk` 0.3.284 (exact pin, asserted by the suite) |
| bubblewrap | 0.13.1, through the repo shim `infra/bwrap-shim/bwrap` (same shim the W1 runtime test uses) |
| curl / OpenSSL / Node | 8.23.0 / 3.6.5 / v26.12.1 |
| Chain | sandboxed `curl` -> SDK sandbox-runtime proxy -> the real, unmodified `infra/egress-forwarder.mjs` -> a **stub gateway** in the test file (loopback only, CONNECT and absolute-URI tunnelling to local echo targets) |
| Config | `buildAgentSandboxConfig(own, { allowWebEgress: true })` with these fields varied per arm and nothing else: `allowManagedDomainsOnly` (the production value is `true`), `allowedDomains` (empty on the control, the three test hosts elsewhere), the `credentials.envVars` `mask` entry, and where `tlsTerminate` is set |
| Stand-in model | Scripted Anthropic stand-in; no model, no real credential. All secrets are per-run decoys; a CI runner's ambient tokens are added to the declared secrets so the run fails if one were visible. |

Measured against the test file carried by the same commit as this record (PR #11624 after its review fixes; the PR is still open, so no merge SHA exists yet). Outcomes are re-derived on every run; this table records one run, not an expected value.

## Outcomes

Outcome vocabulary: `works`, `does-not-work`, `leaks`, `unmeasurable(reason)`; each outcome carries observed-event evidence in the raw JSON. Every conclusion below was drawn only after the suite proved its premises: the sandbox bash completed, the sandbox env showed the secret variable (the decoy on the control, a non-real sentinel on a `mask` arm), and a request reached the destination.

| Probe / arm | Outcome | Evidence in one line |
|---|---|---|
| `control-no-mask:http` | `leaks` | Positive control: with no `mask` entry the decoy is plainly visible on the sandbox env surface and the destination receives the real value. The scan can find a secret. |
| **(c)** `c-tls-options.sandbox` (`tlsTerminate` via `options.sandbox.network`) | `works` | The sandboxed client saw the issuer "sandbox-runtime ephemeral CA" for the HTTPS target, so TLS was terminated by the runtime. |
| **(c)** `c-tls-options.settings` (`tlsTerminate` via `options.settings.sandbox.network`) | `does-not-work` | Issuer unchanged (the destination's own certificate), in the same harness that observed the arm above. |
| **(a)** `mask-managed-domains-on` and `mask-managed-domains-off`, http and https | `does-not-work` | The sandbox env held a sentinel; the destination received that sentinel, not the real value, on the injectHosts host. The managed-domains flag made no difference. The HTTPS arms here are not evidence by themselves: without `tlsTerminate` a CONNECT tunnel cannot be rewritten, so they show only that nothing substituted outside the tunnel. |
| **(a)** `mask-under-tls-options.sandbox:http` | `does-not-work` | Sentinel received. |
| **(a)** `mask-under-tls-options.sandbox:https` | `unmeasurable` | The client completed a TLS handshake with the runtime CA but the HTTPS request never reached the destination; the cause of the failed upstream leg was not isolated. |
| **(a)** `mask-under-tls-options.settings`, http and https | `does-not-work` | Sentinel received (TLS was not terminated in this arm). |
| **(b)** `b-virtual-host` | `works` (reachability only) | A request to a virtual host reached its destination over the ordinary egress path through the real forwarder and the stub gateway, which authenticated the forwarder-injected credential. The forwarder takes tenant and token from its own environment and requires a matching inbound token. The sandbox could not see the proxy-hop credential. |

Gateway attribution is per connection, not per request: in the recorded run 20 plain-HTTP requests reached the destination over 5 gateway absolute-URI connections, because the runtime multiplexes sequential plain-HTTP requests over one forwarder connection. A per-request statement about the gateway is therefore not available.

Scoping arms: a request to a host outside `injectHosts` and a reflecting destination returned only the sentinel in every `mask` arm. These arms establish what `mask` did **not** do on this carrier, not that its scoping is correct, because substitution never happened.

Two further arms were tried during development and dropped because they came back `unmeasurable` by construction: a control that sets `tlsTerminate` through the CLI `--settings` layer (it cannot tell "not forwarded to the CLI" from "not honored by it"), and a variant that trusts the destination's certificate on the host side of the proxy (same `unmeasurable` result as the arm without it).

## What the results do not show

- That `mask` substitutes anywhere. On this carrier (env proxy URL, chained through the forwarder) it did not, in any arm that could be measured. Whether it substitutes when the runtime handles a request without an upstream proxy chain was not measured.
- Anything about the production image or the production gateway.
- Whether HTTPS masking works under TLS termination: that arm is `unmeasurable`.
- That mechanism (b) is acceptable: it shows reachability and that the sandbox cannot read the proxy-hop credential. A push to the forge host is HTTPS and was not measured over (b). Any in-sandbox caller shares the agent's user and namespaces, so a bearer credential held there is not secret from the agent.

## Guard 1 evidence

The hermetic block and the real-sandbox suite were mutated over a pristine backup (restore verified with `diff`). Two rounds: the review panel's first-version survivors, then the fix-round seats' named gaps.

| Mutation | Result |
|---|---|
| Scan never reports a hit; vacuity check removed | killed |
| Scan stops at the first secret | first version survived (no fixture had two secrets on one surface); killed after adding that fixture |
| Arm dispatch loop emptied | first version survived; killed by the outcome floor |
| Secret variable not exported to the sandbox | first version survived; killed (the control no longer leaks, the env premise fails) |
| Env section blanked on mask arms | first version survived; killed (the floor requires a mask arm to reach a conclusion) |
| Echo header name misspelled in the harness | fix round: survived until the floor required the control's echo to record the real value; killed |
| `proc` and `cwdfiles` probe lines replaced by `true` | fix round: survived until the floor required both surfaces non-empty; killed |
| Sentinel tie on `does-not-work` removed | **survives**: in the recorded run the destination received the sentinel on every measured arm, so the tie never changes a verdict; it matters only when the header is absent or garbled |

Finding from that round: the `/proc/*/environ` glob was empty inside the sandbox on every arm, so the surface the scan named was never read. The probe now also reads `/proc/self/environ`, and the floor fails if either surface is empty.
