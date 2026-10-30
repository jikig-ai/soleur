# Phase 0 measurements: credential-broker mechanism spike (#9543, ADR-311)

Raw outcomes of `apps/web-platform/test/broker-mechanism-spike.test.ts`, run with `C4_BWRAP_REQUIRED=1` and `BROKER_SPIKE_OUT` set. This file records surface names and outcome words only. It holds no environment dump, no `/proc` content and no decoy value (a secret-pattern scan over the raw output returned 0 matches before it was quoted here).

## Conditions (what these results do and do not cover)

| Item | Value |
|---|---|
| Host | Linux 7.2.8 x86_64, a developer workstation. **Not** the production image: its seccomp and AppArmor profiles differ (the limit ADR-272 records for its own measurement). |
| Agent SDK | `@anthropic-ai/claude-agent-sdk` 0.3.284 (exact pin, asserted by the suite) |
| bubblewrap | 0.13.1, through the repo shim `infra/bwrap-shim/bwrap` (same shim the W1 runtime test uses) |
| curl / OpenSSL / Node | 8.23.0 / 3.6.5 / v26.12.1 |
| Chain | sandboxed `curl` -> SDK sandbox-runtime proxy -> the real, unmodified `infra/egress-forwarder.mjs` -> a **stub gateway** in the test file (loopback only, CONNECT and absolute-URI tunnelling to local echo targets) |
| Production config | `buildAgentSandboxConfig(own, { allowWebEgress: true })` with `allowManagedDomainsOnly: true` and the Phase-A deny census; arms vary only the fields named below |
| Stand-in model | Scripted Anthropic stand-in; no model, no real credential. All secrets are per-run decoys; a CI runner's ambient tokens are added to the declared secrets so the scan would fail if one were visible. |

Commit of the test at measurement time: `8f22c10b5d` plus the working tree of this branch. Outcomes are re-derived on every run; this table is the record of one run, not an expected value.

## Outcomes

Outcome vocabulary: `works`, `does-not-work`, `leaks`, `unmeasurable(reason)`; each outcome carries observed-event evidence in the raw JSON.

| Probe / arm | Outcome | Evidence in one line |
|---|---|---|
| control-no-mask (http) | `leaks` | Positive control: with no `mask` entry the decoy is plainly in the sandbox environment and the echo target receives the real value. The scan can find a secret. |
| **(c)** `tlsTerminate` via `options.sandbox.network` | `works` | The sandboxed client saw the issuer "sandbox-runtime ephemeral CA" for the HTTPS target, so TLS was terminated by the runtime. |
| **(c)** `tlsTerminate` via `options.settings.sandbox.network` | `does-not-work` | Issuer unchanged (the echo target's own certificate). Observable in the same harness that observed the arm above. |
| **(c)** `tlsTerminate` via `extraArgs --settings` (CLI control) | `unmeasurable` | Issuer unchanged, but the arm cannot distinguish "not forwarded to the CLI" from "not honored by it". |
| **(a)** `mask` + `injectHosts`, production config (`allowManagedDomainsOnly: true`), http | `does-not-work` | The sandbox saw only the sentinel; the echo target received the sentinel, not the real value, on the injectHosts host. |
| **(a)** same, https (no `tlsTerminate`) | `does-not-work` | CONNECT tunnel to the echo target; the target received the sentinel. |
| **(a)** `mask`, `allowManagedDomainsOnly: false`, http and https | `does-not-work` | Same as above; turning the managed-domains flag off did not change the result. |
| **(a)** `mask` under `tlsTerminate` via `options.sandbox`, http | `does-not-work` | Sentinel received. |
| **(a)** `mask` under `tlsTerminate` via `options.sandbox`, https (with and without the echo certificate trusted on the host side) | `unmeasurable` | The client completed a TLS handshake with the runtime CA but the HTTPS request never reached the echo target and no CONNECT reached the gateway; the cause of the failed upstream leg was not isolated. |
| **(a)** `mask` under `tlsTerminate` via `options.settings` / CLI control | `does-not-work` | Sentinel received (TLS was not terminated in these arms). |
| **(b)** request to a virtual host through the forwarder | `works` (reachability only) | A plain-HTTP request to a virtual host reached its destination through the forwarder and the gateway authenticated the forwarder-injected credential. The forwarder takes tenant and token from its own environment, not from the inbound credential. |
| **(b)** proxy-hop credential visible to the sandbox | no | The forwarder token and its Basic encoding were declared secrets; no surface showed them. |

Scoping arms: a request to a host outside `injectHosts` and a reflecting echo returned only the sentinel in every `mask` arm, so no real value left the host side and no real value was reflected back into the sandbox. These arms are vacuous for the mechanism itself, because substitution never happened (see the first rows): they establish what `mask` did **not** do on this carrier, not that its scoping is correct.

## What the results do not show

- That `mask` substitutes anywhere. On this carrier (env proxy URL, chained through the forwarder) it did not substitute in any arm that could be measured. Whether it substitutes when the sandbox runtime handles the request without an upstream proxy chain was not measured.
- Anything about the production image or the production gateway. The gateway here is a stub in the test file.
- Whether HTTPS masking works under TLS termination: the arm is `unmeasurable`.
- That (b) is an acceptable mechanism: it shows reachability and that the sandbox cannot read the proxy-hop credential. Any in-sandbox caller shares the agent's user and namespaces, so a bearer credential held there is not secret from the agent.

## Guard 1 mutation record

Mutants applied to `test/helpers/broker-spike-scan.ts` over a pristine backup, hermetic block only (restore verified with `diff`):

| Mutant | Result |
|---|---|
| M1 scan never reports a hit | 3 tests fail (killed) |
| M2 vacuity check removed | 2 tests fail (killed) |
| M3 scan stops at the first secret | **survived** the first fixture set (fixture gap: no test had two secrets visible on one surface); a case was added (`guard row 3c`) and the mutant is then killed (1 test fails) |
