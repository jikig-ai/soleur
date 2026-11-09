---
title: "Agent runtime sandbox evaluation, injector first: decision record and measured injector spike"
type: feat
date: 2026-11-09
slug: feat-agent-runtime-sandbox-eval-injector-first
branch: feat-agent-runtime-sandbox-eval
issue: 12517
closes: 12517
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Agent runtime sandbox evaluation, injector first

## Overview

This plan turns the 2026-11-09 brainstorm into a decision record and one measurement. The decision is that egress credential injection is decided at the egress hop's interface (a CONNECT proxy with per-session authentication), apart from the isolation runtime (bwrap today, the gVisor epic #9842 tomorrow). The measurement is a go/no-go on a self-run TLS-terminating injector (iron-proxy) for GitHub hosts, run in a hermetic suite on the production run tuple, against criteria fixed before the run: the brainstorm's seven, split and extended to nine (criteria 1–9 below; the mapping is in the spec edit). The Cloudflare Sandbox trial, the measured contingency, ships as a sibling PR under widened #9859 (Arm D) on this same spec (CTO ruling F-d). No credential-bearing surface reaches any tenant: the injector, its CA, its policy and its approval hook live under a test path only.

PR #12518 delivers: ADR-324 (provisional ordinal), the injector spike suite and its raw results, a results note with a verdict, the dependent-issue edits, and (only on GO) a merge-conditioned addendum to ADR-311.

## Problem Statement

Web-egress-entitled hosted sessions hold no credential (ADR-278 Decision 5), so in-sandbox `git push`, `gh` and connected providers do not work. The route in progress is one approval-gated server-side tool per verb. Measured from git: the first gated write tool in the cc path (PR #12188, `github_push_branch`) touched 36 files, 9 of them source; the six read tools (PR #12465) touched 42 files, 12 of them source. Egress-side injection would cover every HTTPS-credentialed tool with one mechanism, but nothing on our hop terminates TLS (squid is CONNECT-only), the only in-SDK candidate did not substitute on our carrier (ADR-311 Decision 2), production lists `github.com,*.github.com` in `NO_PROXY` so GitHub traffic does not reach the proxy at all today (`server/agent-env.ts` `buildAgentEnv`), and no vendor comparison backed the 2026-11-09 ruling to keep our own sandbox.

## Research Insights

**Premise Validation (2026-11-09).** Every cited issue is open: #12517, #12467, #11637, #11638, #9842, #9845, #9846, #9843, #9853, #9854, #9852, #9859, #9866, #5274; PR #9832 (the #9842 spec) is open and unmerged; PR #12518 is this branch's draft. ADR-075, -272, -278, -309, -311 and -315 exist on main. The collision pre-check found no open PR naming #12517 other than #12518; its foreign-process hits were unrelated `test-all.sh` runs in other worktrees. ADR-323 was claimed on main the same day; ADR-324 is free across every `origin/*` ref (probed 2026-11-09). Stale premises: the "41 / 14 files" baseline (replaced by measured 36 / 42) and "flag off denies everywhere" (true only in the cc dispatcher).

**Property List.**

- P1 A decision of record says injection is a hop decision separate from the runtime, with ranked options, flip facts and CLO gates.
- P2 Each go/no-go criterion has a measured verdict on the production run tuple.
- P3 A managed-platform contingency is measured within USD 50 and 14 days and torn down (sibling PR).
- P4 Dependent work (#12467, #11637, #9845, #9859) reflects the result.
- P5 No tenant-serving path gains TLS termination or a credential.

**Cut List.**

- Stub approval store → P2 → cut; the real `consume_approval` already exists and is the thing in question (CTO F-a).
- Hourly usage-pull job with auto-teardown → P3 → cut; a configuration bound on instance count and type caps worst-case spend.
- Production `credential-vend` migration, Vector allowlist and alert for the vend markers, Sentry mirror → P2 → cut from this PR; the throwaway-stack CHECK widening and in-suite marker assertions measure the property; the production versions are #11637's.
- Changes to `egress-forwarder.mjs` or `agent-env.ts` → P2 → cut; the injector chains in front of the unchanged forwarder, and the `NO_PROXY` change is measured as arm B and labelled #11637's (CTO R11), so no tenant path is touched (P5).
- A second hand-written injector arm → P2 → cut (CTO F-b).
- Criterion 0 (upstream chaining) as a criterion id → P2 → cut; the tracer answers it and criterion 2 re-proves it (CTO R14).
- A separate CA-minting script → P2 → inlined as a suite function (only the suite calls it).
- Harness self-check mutation rows (decoy constancy, stale-JSON nonce) → P2 → cut; a fresh CI runner has neither, and the results note cites run URL and SHA.

**Repository facts used.** `apps/web-platform/test/broker-mechanism-spike.test.ts` (ADR-311 harness; real-sandbox block gated by `SANDBOX_OK`, decoy secrets, stub gateway, spawns the real forwarder); its record is archived at `knowledge-base/project/specs/archive/20261030-160202-feat-one-shot-9543-egress-credential-broker/phase-0-measurements.md`. `apps/web-platform/infra/sandbox-masked-proc-docker.test.sh` (production-run-tuple suite; drives the real SDK in wrapped-command arms). `infra/lib/docker-run-tuple.py` (tuple parser). `infra/egress-forwarder.mjs` (inbound 407 on bad token, injects `workspace:token`, raw `client.pipe(gw)`); `server/egress-forwarder.ts` `spawnEgressForwarder` (all tenant processes uid 1001), spawned from `server/cc-dispatcher.ts` only when web egress is entitled. `server/agent-env.ts` `buildAgentEnv` sets the proxy env and `NO_PROXY` (includes `github.com,*.github.com`). `server/agent-runner-sandbox-config.ts` `buildAgentSandboxConfig` (credential-deny census; `allowAllUnixSockets: true`; per-session peer-socket and sibling-transcript masks). `infra/egress-gateway-squid.conf` (CONNECT-only, 443-only, deny list, `soleur_json` log with no body). `supabase/migrations/180_approval_request.sql`: `create_approval_request` (7 args, service_role only, returns the existing live row for the same hash, TTL minimum 60 s, 5 pending rows per conversation then `AP429`), `decide_approval(uuid, text)` (`'approve'`/`'deny'`, granted to `authenticated`), `consume_approval(p_id, p_hash, p_conversation)` (service_role only, single-use), `get_approval_status(id)`; closed `tool_name` CHECK of eight names; `expires_at` immutable by trigger. `server/approval/service.ts` (create-then-consume order). `server/approval/flag.ts` `isApprovalQueueEnabled`. `apps/web-platform/scripts/supabase-local.sh` (stack bound to host 127.0.0.1, used by `rls-authz-fuzz.yml`). Suite registration: `.github/scripts/test/test-infra-suite-registration.sh` (a `PRIVILEGED_WHY` suite must be a `sudo bash` step of `deploy-script-tests-fixed`; a suite under `apps/web-platform/test/infra/` needs a `bash` call in some workflow, Arm 3b). `infra-validation.yml` has `pull_request` and `workflow_dispatch` triggers and a `push` trigger covering `apps/*/infra/**` and `apps/web-platform/test/infra/**`; its `detect-changes` exposes `directories`, `plan_directories` and `pr_duplicate` only. vitest's unit project includes `test/**/*.test.ts` and may import `.mjs` under other paths (precedent `test/sdk-bash-probe-parity.test.ts`). `graphql` is not a dependency; `@grpc/grpc-js` is transitive at 1.14.6; `tsx` is a devDependency.

**External facts (retrieved 2026-11-09; agent-sourced, re-verify before citing in the ADR).** iron-proxy: Apache-2.0, v0.56.0 (2026-11-04), one CA per process, header placeholder replacement by default, gRPC `transform.v1.TransformService` with method, url, headers, body, host and remote_addr, CONTINUE/REJECT, no per-call deadline in `internal/transform/grpc/grpc.go`, `upstream_response_header_timeout` 30 s, audit line per request, bodies only via `body_capture`; image published under `:latest` (pin a digest); one dominant maintainer; upstream-proxy chaining unverified. Name constraints: enforced by OpenSSL, Go `crypto/x509` and BoringSSL; known defects in Mbed TLS, GnuTLS (CVE-2026-3833, case-sensitive matching), pyca and s2n-tls. CA env: `GIT_SSL_CAINFO`, `SSL_CERT_FILE`, `CURL_CA_BUNDLE` replace; `NODE_EXTRA_CA_CERTS` appends and is read at start; Bun support reported inconsistently; the `claude` CLI logs "CA certs: Appended extra certificates from NODE_EXTRA_CA_CERTS". git smart HTTP: upload-pack = read, receive-pack = write (classify by service name). GraphQL: classify the operation selected by `operationName`; reject batched arrays. Cloudflare Sandbox SDK 1.0: `interceptOutboundHttps`; Workers Paid USD 5/month required; no hard spend cap; Terraform manages Workers scripts and Durable Object bindings, not Containers.

**Institutional learnings applied.** `2026-11-09-a-deciding-criterion-belongs-to-one-component-find-it-before-comparing-bundles.md` (decide on the hop; one POST can be a read or a write). `2026-10-30-a-nonempty-check-was-satisfied-by-the-error-message-it-should-have-caught.md` (verdicts need positive observation; run instrument-breaking mutants first). `2026-11-09-cloud-gh-auth-loss-was-the-design-and-the-fix-is-server-side-reads.md` (do not re-add credentials to the sandbox). `2026-10-12-egress-gateway-single-shot-tcp-probe-raced-squid-bind.md`. `best-practices/2026-10-05-docker-interbridge-reply-path-ct-state-new.md`. `2026-09-29-a-source-census-that-checks-the-arguments-name-not-its-binding-and-a-closed-file-list-both-let-guarded-egress-through.md`. `security-issues/bwrap-masked-proc-drop-not-cover-shim-20261011.md`. `security-issues/2026-10-08-file-tool-tier-outside-bwrap-isolation-boundary-is-the-cli-process.md` (file tools run outside bwrap). `2026-04-06-node-slim-missing-ca-certificates.md`.

**Functional overlap.** No community skill or agent covers a credential-injecting egress proxy; nothing installed.

## Research Reconciliation — Spec vs. Codebase

| Spec / brainstorm claim | Reality (measured or read) | Plan response |
|---|---|---|
| "A gated write tool touches about 41 files, a read tool about 14" | Unsourced. PR #12188 = 36 files (9 src, 17 test, 10 kb); PR #12465 (six read tools) = 42 files (12 src). `git show --name-only d6f590a14f` / `d999eb6383` | Criterion 7 compares source to source: the overlay's data file against #12188's 9 source files, stating what the overlay leaves out (tests, approval-card text) |
| TR1 "only a placeholder is present" | Production git authenticates with Basic `x-access-token` via `GIT_ASKPASS`; a placeholder inside base64 cannot be substituted literally | The injector replaces the whole `Authorization` header (CTO R8); the sandbox holds no token-shaped value for git; spec TR1 is edited |
| TR2 reads are "GET/HEAD on a per-workspace path allowlist" | git reads are `POST git-upload-pack`; GraphQL queries are POSTs; a push starts with a ref-advertisement GET | Reads are classified by protocol (below); spec TR2 is edited |
| TR2 "flag off, every vend is denied" | Flag-off deny holds only in the cc dispatcher today | The hook denies every vend when its flag input is off, reads included (CTO R2) |
| TR5 "default-deny egress and the existing allowlists" | Gateway is CONNECT-only, 443-only, deny-list over public 443; default deny lives at session entitlement | Criterion 6 measures the deny list, 407, non-443 and no-route-when-unentitled through the full chain |
| TR8 "every vend emits a monitored marker; refusals mirrored to Sentry" | No vend marker exists; nothing ships to a host | In-suite `SOLEUR_EGRESS_VEND*` markers asserted per arm; monitoring and the Sentry mirror are #11637's |
| TR2 "consumes exactly one ADR-309 row" | Closed `tool_name` enum; service_role-only RPCs; create-then-consume by row id | The throwaway stack's CHECK is widened inline (CTO R5); the hook follows `service.ts`'s order (CTO R16) |
| "On the production run tuple" | The ADR-311 spike ran on a workstation | The suite derives the tuple with `docker-run-tuple.py` and runs the real SDK/SRT sandbox |
| GitHub traffic reaches the proxy | `NO_PROXY` lists `github.com,*.github.com` | Arm A measures today's env; arm B removes the inject hosts from `NO_PROXY`, labelled a production change for #11637 (CTO R11) |
| iron-proxy can scope a CA per tenant | One `tls` block per process | One injector process per session (CTO F-c) |
| The trial produces session-hours and concurrency | A synthetic trial measures unit cost only (COO) | Demand-side telemetry filed as a separate issue |

## Proposed Solution

### Decision record (ADR-324)

ADR-324, "Egress credential injection is a property of the hop, decided apart from the isolation runtime", status `adopting`, written now (CTO F-e). Its claim of substrate independence covers the interface only: a CONNECT proxy with per-session authentication that the runtime's network path dials. The carrier (the SDK sandbox runtime chaining from the sandbox's network namespace to a container-loopback proxy) is tied to the runtime (ADR-278 measurement 1) and is the part #9842 must re-measure. It records the options ranked on the operator's criterion, the tiebreak, brainstorm Decisions 3, 6 and 9, the flip facts F1–F4, and the CLO gates verbatim:

> "CLO gates for any managed platform: a signed DPA that names the product; an EEA contracting entity or a transfer mechanism covering that product; an acceptable sub-processor list; a transfer impact assessment and DPIA; a successor to the T-1 location gate with fresh operator acknowledgement; published documents changed before any tenant data moves."

Beside the gates it notes that the T-1 to #5274 mapping is unverified. It cites ADR-311 Decision 4 for approval-on-every-vend rather than restating it, states that ADR-311 Decision 6 stays frozen as narrowed, names DPIA trigger t3 / #9853 as the production gate, lists the parked ePrivacy question, records the forwarder-first ordering as the alternative #11637 must weigh (a dead injector also stops `claude` streaming; CTO R17), names the hook's key custody (service-role and HMAC keys in one dispatcher-like process) as part of the blast radius, and states that the results go stale at merge until #11637 owns the job. It cites code by function name, and does not claim credential injection is offered, treat vendor documentation as a control, assert Cloudflare's DPA covers Sandbox or Containers, or claim EU placement. Its C4 section names an `egressInjector` container as a pending change assigned to #11637. It amends ADR-311 Decision 4 only through a measured hook (GO) in merge-conditioned wording ("on merge of PR #12518"); on NO-GO it adds a see-also to ADR-311 so its Consequences line about #11637 does not go stale. `## Measured outcome — injector` is appended after the run; `## Measured outcome — Cloudflare trial` is appended by the sibling PR.

### Injector spike

Topology, inside one CI job on the production run tuple:

```text
sandbox (SDK/SRT bwrap, app image, uid 1001)     injector process (per session, outside bwrap, uid 1001)
  git / gh / curl / node / claude  -- CONNECT -->  iron-proxy (digest-pinned), per-session Proxy-Authorization
  holds no credential; CA cert only                 per-session CA key + real decoy token (masked paths, fd)
                                                     |                                   |
                                                     | gRPC over per-session socket      | CONNECT (workspace:token)
                                                     v                                   v
                                         approval hook (one process, host network,   egress-forwarder.mjs (real, unchanged)
                                         stands in for the dispatcher: service-role     |
                                         + HMAC keys; one socket per conversation)       v
                                                     |                                squid gateway (real conf, unchanged)
                                                     v                                   |
                                         local Supabase stack (real RPCs, loopback)      v
                                                                                     stub destinations (TLS, test root):
                                                                                     github.com, api.github.com,
                                                                                     uploads.github.com, codeload.github.com
                                                                                     (git http-backend + REST/GraphQL stub,
                                                                                      records the Authorization class received)
                                                                                     + stub Anthropic SSE (tunneled, not terminated)
```

Rulings that shape it (CTO, binding, 2026-11-09; full text in `decision-challenges.md`):

- **F-a** the real RPCs on the throwaway stack started by `supabase-local.sh`; if the stack cannot run, criterion 3 is `unmeasurable`, never measured against a stub.
- **F-b** iron-proxy, digest-pinned, is the only arm; a failure configuration cannot fix stops the run and goes to the CTO.
- **F-c** one injector process per session beside the forwarder, outside bwrap, CONNECT-chained to the unchanged forwarder and squid. The decoy credential and CA key reach it through a file descriptor or a file under a path the sandbox config masks for every session; never env or argv.
- **F-f** hermetic stub destinations; upstream verification stays on against a test root.
- **F-g / R22** an on-demand recorded run in a dedicated job (`pull_request` and `workflow_dispatch`, `if: github.event_name != 'push'`), job-level concurrency group `sandbox-eval-${{ github.event.pull_request.number }}` with `cancel-in-progress: false`; the suite never skips itself.
- **R9** one approval-hook process holds the service-role and HMAC keys (as the dispatcher does in production). Each session reaches it through its own unix socket in a per-session directory masked for every session (the #10445 peer-socket pattern), the hook binds each socket to one conversation id and accepts only a per-session nonce held by that session's injector, and a probe proves sandboxed Bash cannot `connect()` the socket.
- **R10** every secret (decoy token, CA key, hook socket, nonce) is out of env and argv and under masked paths; CLI-tier probes (below) prove the same-uid file tools cannot read them.
- **R11** arm A runs with the exact `buildAgentEnv` output and records where GitHub traffic goes; arm B removes the four inject hosts from `NO_PROXY`, labelled a production change owned by #11637. Both run through the real SDK/SRT sandbox (`sdk-bash-probe.mjs` pattern).
- **R20** the injector requires a per-session `Proxy-Authorization` on CONNECT; a CONNECT without it from container loopback gets 407.
- **R21** the hook runs in the runner host's network namespace (`--network host` if containerised) so `127.0.0.1` is the loopback `supabase-local.sh` binds. Before using the service-role key, the hook refuses unless the URL host is a loopback literal and the key and URL match `supabase status`.

Policy data (`policy.yaml`) is the per-host classifier and the only place a verb is declared. The base policy is closed for writes (CTO R13):

- Inject hosts: `github.com`, `api.github.com`, `uploads.github.com`, `codeload.github.com`. Every other host is tunneled without termination.
- Reads vend without a row, on the per-workspace repository allowlist: REST `GET`/`HEAD` on allowlisted paths; git `GET info/refs?service=git-upload-pack` and `POST git-upload-pack`; GraphQL documents whose selected operation (by `operationName`, parsed with the `graphql` package) is a `query`.
- The push ref advertisement (`GET info/refs?service=git-receive-pack`) vends without a row on the same allowlist: it mutates nothing and carries no ref updates to hash (CTO R1).
- Listed writes need a row: `POST git-receive-pack`; the REST write verbs and GraphQL mutation fields named in `policy.yaml`. An unlisted write, and any unparseable, batched (array) or multi-operation body without a resolvable `operationName`, is refused as `not-allowlisted` with no row.
- Each write rule names the canonical-action fields hashed into `action_sha256` (HMAC-SHA-256 with a spike-only key), always including host and repository path: REST = method, host, path, sha256 of body; GraphQL = host, operation name, operation type, sha256 of normalized document and variables; git push = host, repository path, and the ref-update commands from the receive-pack pkt-lines (old sha, new sha, ref). Host case, the repository path's `.git` suffix and percent-encoding are normalized first (CTO R6). `canonical_action` stores the same fields readably, so the results note records what an approval card could show.

The classifier and hash recipe are pure functions in `policy.mjs` over a normalized request struct `{method, host, path, query, headers, body}` with no top-level server or network imports, so #11637 can port them into `server/` unchanged.

Credential carriage (CTO R8): on the four inject hosts the injector replaces the whole `Authorization` header with the real one (HTTP Basic `x-access-token:<token>` for git smart HTTP, `token <t>` for the REST and GraphQL APIs) and ignores whatever the client sent; it never substitutes text inside a header. The sandbox therefore holds no token-shaped value for git. Every criterion 2 client runs under the production web-egress credential-deny list derived from `buildAgentSandboxConfig`'s census (never hand-copied). `gh` refuses to call the API without some token, so the suite records which harmless value `gh` can be given under that list; if the only route is exempting a name from it, the results note labels that a production change owned by #11637.

The approval hook (`approval-hook.mjs`, importing `policy.mjs`) implements iron-proxy's `TransformService`. Its decision order:

1. Flag input off: REJECT every vend, reads included, and create no row (CTO R2).
2. Unparseable, unclassifiable or unlisted write: REJECT `not-allowlisted`, no row.
3. Allowlisted read or push advertisement: CONTINUE.
4. Read outside the allowlist: REJECT `not-allowlisted`, no row.
5. Listed write: compute the hash; call `create_approval_request`, which returns the existing live row for this hash or inserts a pending one; if the row is `approved`, call `consume_approval(id, hash, conversation)` and CONTINUE on success; otherwise REJECT with a body naming the pending approval (`pending`), and report `rejected` or `expired` by checking `get_approval_status` for the ids it previously returned for this hash (the hook remembers them).

Timeouts, together: the hook bounds its own work at 5 s; iron-proxy's 30 s upstream header timeout bounds a slow destination; clients must exit within 10 s of a refusal or a dead hook. Each is shorter than the layer above it, so a stall is reported by the innermost layer that can see it. The hook emits `SOLEUR_EGRESS_VEND` (fields: `session`, `host`, `method`, `class`, `rule`, `approval_id` or `read-allowlist`) and `SOLEUR_EGRESS_VEND_REFUSED` (fields: `session`, `host`, `method`, `class`, `reason` in `flag-off | not-allowlisted | pending | rejected | expired | hook-timeout`). A request whose hash differs from an approved row simply finds no approved row, so the binding is proven by the stub's record, not by a reason code; cross-tenant isolation is likewise proven at the stub. When the hook is dead or frozen it cannot emit anything; the suite then reads iron-proxy's own audit line for the failed gRPC call. Nothing logs a body, a header value or a token.

The per-session CA is minted by a suite function: an ephemeral EC root with critical `nameConstraints` permitting the four inject hosts, `pathlen:0`, 24-hour validity, SAN-bearing leaves. The sandbox receives the certificate only, through `SSL_CERT_FILE` (gh, curl), `GIT_SSL_CAINFO` (git) and `NODE_EXTRA_CA_CERTS` (Node, Bun, `claude`), on a bundle that is the system bundle plus the session CA (the first two replace rather than append). The key never enters the sandbox and is deleted at session end.

### What the suite measures (criteria fixed before the run)

Each criterion yields `pass | fail | unmeasurable` with a positive observation required for any verdict. Every arm uses a fresh conversation (the 5-pending cap, CTO R16). Writes in criterion 2 run with the flag input on and a pre-approved row seeded per arm, so criterion 2 measures transport, not gating.

| # | Criterion | Probe |
|---|---|---|
| 1 | Real credential not observable in the sandbox or by the same-uid file tools | Sandbox side: scan of env, workspace and `$HOME` files and the process list through `scanSandboxSurfaces` (`test/helpers/broker-spike-scan.ts`, run with `tsx`); the scan must find a planted control string to count as live. CLI-tier side (CTO R10): the stub Anthropic server returns scripted `Read` and `WebFetch` tool calls for the decoy-token file, the CA key, the hook socket, the nonce and `/proc/<injector pid>/{environ,cmdline}`; each must be refused. Positive control: the harness, as the same uid outside the sandbox, reads `/proc/<injector pid>/environ` successfully first. Sandboxed Bash `connect()` on the hook socket fails (CTO R9) |
| 2 | `git` clone, fetch, push; `gh` REST and GraphQL; Node `fetch`; `curl`; `claude` CLI streaming, all through the injector with the injected CA, on the production run tuple | Arm A (`buildAgentEnv` as is) records where each client's GitHub traffic goes. Arm B (inject hosts removed from `NO_PROXY`, labelled #11637's change): each command runs inside the sandbox; the destination stub records the real decoy token class for inject hosts; the stub Anthropic SSE (non-inject host) streams 50 events untouched (the client sees the stub's own certificate) |
| 3 | A listed write with no approved row is denied and creates a pending row; with one it is consumed exactly once; flag off denies | Git push, full lifecycle (CTO R16): no row (REJECT `pending`, one pending row); retry before decision (still one row); owner `deny` via `decide_approval` with a JWT from the local stack's auth (REJECT `rejected`, then a new pending row on re-request); a row with `p_ttl_seconds=60` polled up to 70 s (REJECT `expired`); `approve` then retry (vend, `consumed`); retry again (REJECT, new pending row). After an allowlisted advertisement GET, a `POST git-receive-pack` with no row is refused and the stub records no real token (CTO R1). REST POST and GraphQL mutation: no row, approved-and-consumed, binding. **Binding** (CPO C4): a row approved for request X does not authorize request Y that differs in body, path, repository, ref or operation; the stub records no real token for Y. Flag input off: REJECT `flag-off`, no row. Recorded only (CTO R15): for `git`, `gh` and `claude`, whether the pending-approval message reached the agent |
| 4 | Allowlisted read vends without a row | REST GET on an allowlisted path, git clone, GraphQL query: vend, zero rows; GET on a non-allowlisted path: REJECT; the same allowlisted reads with the flag input off: REJECT |
| 5 | Session A cannot obtain session B's credential | Two sessions, workspaces, CAs, decoy tokens, hook sockets and nonces. From A: a request carrying B's token as an `Authorization` value; a request with B's proxy credential; a CONNECT to B's injector port (407 without B's per-session credential, CTO R20); A's CA presented to B's injector; A's nonce on B's hook socket. The stub never records B's token from A |
| 6 | ADR-278 controls do not regress; no request body logged | Through the full chain: deny-CIDR, localhost, link-local and port-80 targets refused; forwarder 407 on a bad token; an unentitled session has no route. A grep of every log (injector audit, hook output, squid `soleur_json`) for the decoy token and a planted body canary finds nothing |
| 7 | One new GitHub verb touches policy data only | A second pass applies the committed overlay `policy.add-verb.yaml` (create issue, `POST /repos/{o}/{r}/issues`) with the hook and `policy.mjs` unchanged (sha256 asserted equal across passes). Control: the same request is refused `not-allowlisted` in the first pass. Pass = in the second pass it is gated, consumed once and vended. The results note compares one data file with #12188's 9 source files, names what the overlay leaves out (tests, approval-card text), and states the claim's limit (CTO R4): REST verbs that fit the generic recipe only |
| 8 | Failure is visible and closed, not a hang or a leak | Hook alive but stalled past its deadline: `git`, `gh`, `curl` exit non-zero within 10 s, `hook-timeout` is emitted, the stub records no real token. Hook killed: the same exit bound and no real token at the stub, with iron-proxy's audit line naming the failed call. Injector killed: clients exit non-zero within 10 s, and the effect on `claude` streaming is recorded (CTO R17) |
| 9 | CA scope (spec TR3) | Two sessions have distinct CAs. A session-CA leaf for a non-inject name is rejected by every client; the TLS library each client links is recorded first. For a client linking GnuTLS, a mixed-case inject name is also tried and must be accepted (DNS names ignore case; a rejection is recorded as that client's defect, not a constraint failure). Session A's CA is not trusted in session B. The CA key file is absent after session end. Control: the same clients accept a session-CA leaf for an inject host |

Verdict, computed by the suite:

- **GO**: criteria 1–9 pass.
- **NO-GO**: every criterion has a measured verdict and at least one fails. A failure of criterion 2 or 5 means flip fact F1 holds; the managed-platform path still needs the Cloudflare trial and the CLO gates, so ADR-324 records "F1 holds; flip awaits the trial". Any other failure is an injector design defect, and the CTO rules whether to fix and re-run or resume #12467. NO-GO exits 0 only when the outcome floor holds (CTO R3).
- **INCONCLUSIVE**: any criterion is `unmeasurable` for a harness reason (the Supabase stack cannot run, a dependency is missing). The suite exits non-zero; each unmeasurable criterion carries its own harness reason in the raw JSON so the CTO re-rules on a named defect. A measured failure of criterion 2 or 5 is still recorded as F1 evidence even when the overall verdict is INCONCLUSIVE.

## Technical Approach

### Implementation Phases

#### Phase 0 — Hold the dependent work

- `gh issue edit 12517 --milestone "Phase 4: Validate + Scale"` (CPO C1); `gh issue edit 12467 --add-blocked-by 12517`; `gh issue edit 11637 --add-blocked-by 12517`; a comment on #12467 recording the pause with a review date of 2026-11-30, after which it resumes if the spike has not reported (CPO C3).
- The 2026-11-30 reminder (CTO R18) is armed through `POST /api/internal/schedule-reminder` as an issue comment on #12467, the way `scripts/arm-checkpoint.sh` does; it writes to production, so it waits on the operator's typed go (see `## Operator Holds`). The resume step removes the #12467 blocked-by-#12517 edge.

#### Phase 0.5 — Tracer: prove the injector's assumptions before anything else is built

Plain local docker, one stub host, a throwaway hook that logs what it receives. Each answer is recorded in `iron-proxy-image.provenance.md`.

1. **Upstream chaining:** iron-proxy CONNECTs to an upstream proxy with `workspace:token` proxy authorization.
2. **Selective termination:** a non-inject host is tunneled, not terminated.
3. **Hook body access:** the hook receives the full buffered body of a gzip-encoded and a chunked `POST git-receive-pack` (decoded or not; this decides whether the pure parser must handle chunking), and a REJECT can carry a body the client shows.
4. **Upstream trust:** a test upstream root is configurable without disabling upstream verification.
5. **Whole-header replacement (CTO R8):** on an inject host the injector can replace the entire `Authorization` header, through configuration first, then through the hook. Neither working is a mechanism failure under F-b; it is never a quiet fallback to a Bearer header.
6. **Dead hook:** with the hook unreachable or frozen, iron-proxy blocks the request (fail closed) rather than passing it; the bound on how long it waits is recorded.
7. **Inbound auth (CTO R20):** iron-proxy can require a per-session `Proxy-Authorization` on CONNECT.

Plus the binding mechanism: the CLI process's `HTTPS_PROXY` (set server-side, per session) is the SDK sandbox proxy's only upstream, and the sandbox's localhost is not the container loopback (ADR-278 measurement 1); the tracer records the actual mechanism and criterion 5 probes it.

Any "no" on 1–7 that configuration cannot fix stops the run and goes to the CTO (F-b) before Phase 1. Success: seven recorded answers and the binding mechanism.

#### Phase 1 — Hermetic tests, then the harness

- Write the Guard Contract matrices (below) before code; each row is run once by hand against the finished suite and its result recorded in the results note.
- `apps/web-platform/test/egress-injector-policy.test.ts`: hermetic tests over `policy.mjs` (cq-write-failing-tests-before): every policy row; GraphQL single query, single mutation, multi-operation with and without `operationName`, batched array, unparseable body; receive-pack pkt-lines with one and two ref updates (and chunked bodies only if tracer item 3 says the hook sees them raw); each single hashed-field change produces a different hash; repository spelling variants hash equal and a fork hashes differently (CTO R6). They fail before `policy.mjs` exists.
- Add `graphql` and `@grpc/grpc-js` (at the locked 1.14.6) as exactly pinned devDependencies of `apps/web-platform`, updating `package.json` and `package-lock.json` together (CTO R23, `cq-before-pushing-package-json-changes`).
- Pin iron-proxy by image digest; write `iron-proxy-image.provenance.md` (licence, release tag, digest, retrieval date, tracer answers, commit cadence, contributor count, hook proto revision, whether it builds from source). Mirroring the image into our registry and a bus-factor review are preconditions for #11637's production adoption, not spike criteria.
- `stub-github/server.mjs`: TLS server for the four hosts on the test upstream root; REST and GraphQL stub; `git http-backend` behind CGI on a synthetic repository created in the suite (no real repository content, CLO); records method, path and the `Authorization` class received (`real-decoy | other | none`) per request.
- `injector-spike-docker.test.sh` under `apps/web-platform/test/infra/egress-injector-spike/` (CTO R12; no `PRIVILEGED_WHY` entry): derives the run tuple, starts the gateway from the real `egress-gateway-squid.conf`, starts the local Supabase stack, seeds two synthetic workspaces and owners, widens the `tool_name` CHECK inline with `psql` only after the loopback-and-`supabase status` guard (CTO R5, R21) and records the exact change for #11637, starts the hook, spawns per session the real forwarder and the injector, runs the probes through the real SDK/SRT sandbox, writes raw JSON (`INJECTOR_SPIKE_OUT`) carrying the run's verdict, and fails the run if any criterion has no verdict. A missing tool or daemon is FAIL, never SKIP.
- `print-verdict.sh` beside it: prints `verdict=<GO|NO-GO|INCONCLUSIVE>` from the committed results JSON and exits 1 on any other value.
- `.github/workflows/infra-validation.yml`: new job `egress-injector-spike` (CTO R22: `pull_request` and `workflow_dispatch` only, `if: github.event_name != 'push'`, its own path check on the spike directories, `timeout-minutes: 30`, job-level concurrency `sandbox-eval-<pr>` with `cancel-in-progress: false`, plain `bash` invocation, raw JSON uploaded as an artifact). No new trigger is added to the workflow.
- Success: the tracer answers hold, the hermetic tests are green, and the suite reaches a verdict.

#### Phase 2 — Run and record

- Read the job's run on the PR; use `gh workflow run infra-validation.yml --ref feat-agent-runtime-sandbox-eval` only for a re-run (the workflow exists on the default branch, so a branch dispatch runs the branch's job).
- Write `knowledge-base/project/specs/feat-agent-runtime-sandbox-eval/injector-spike-results.md` and commit `injector-spike-results.json` beside it. The note opens with three plain sentences: what was tested, the verdict, what happens next. Then: machine class and date, SDK pin, image digests, run URL, commit SHA, each criterion's verdict and raw outcome, each claim labelled `measured | read from file | unverified` (TR9), the re-measure trigger (a change to the SDK pin, the sandbox flags in `buildAgentSandboxConfig`, the iron-proxy digest or `egress-gateway-squid.conf`; no bot bumps the digest, so a bump is a manual PR that re-runs the job), the guard-matrix by-hand results, and the verdict.
- Record what `canonical_action` shows for each write class, the per-client pending-approval message (CTO R15), the arm A `NO_PROXY` finding, the `gh` carriage finding, and the confused-deputy residual (reads plus open-web egress).

#### Phase 3 — Decision record and dispositions

- Write ADR-324 (above) and append `## Measured outcome — injector`.
- On GO only: append the merge-conditioned ADR-311 addendum (a hook satisfying Decision 4 was measured: exactly-once consumption on the real RPC, flag-off deny, pending-row creation, request binding; the three ADR-309 additions are #11637's scope). On NO-GO: add the ADR-311 see-also.
- Issue edits (D4):
  - #9845 (S3): append a linked section on generic per-host injection with approval attachment, leaving its Anthropic-key hypothesis unchanged (CTO R19).
  - #9859 (S0): widen Arm D from paperwork to the Cloudflare trial, carrying the Phase 4 requirements below, and name the sibling PR as delivery and #9859 as owner of the trial's evaluation.
  - #11637 (comment, made on merge): on GO, add as its acceptance criteria that the founder can read every approval card (CPO), that `git`, `gh` and `claude` each show a pending approval to the agent, that it owns re-running the spike job and refreshing the results JSON, and that the image mirror and bus-factor review precede adoption.
  - File "Demand-side session telemetry (session-hours, peak concurrency, session-length distribution) from our own runtime records", milestone Phase 4, so the managed break-even has inputs (COO).
- Dispositions take effect on merge, never before. `soleur:ship` derives the PR body's issue lines from `jq -r .verdict` of the committed results JSON, so a NO-GO cannot close #12467 by hand error:
  - GO: `Closes #12517`, `Closes #12467` (superseded, linking the results); on merge, the #11637 comment above.
  - NO-GO: `Closes #12517`, `Ref #12467`; on merge, a comment on #12467 that it resumes, `gh issue edit 12467 --remove-blocked-by 12517`, and `gh issue edit 11637 --add-blocked-by 9859` so #11637 stays blocked on the trial.
  - INCONCLUSIVE: the PR is not marked ready; `Ref #12517` only; the CTO rules on the harness defect and the run repeats.
- Handoff for the next `soleur:product-roadmap` workshop run (this plan never edits `roadmap.md`): row 4.6 should also cite #9842; #12517 and the demand-telemetry issue have no roadmap row; Current State (dated 2026-08-11) is stale.

#### Phase 4 — Sibling PR (out of this PR): Cloudflare trial under #9859 Arm D

This is the content posted to #9859 in Phase 3; that PR gets its own plan.

- Starts in parallel with this PR, regardless of its verdict (brainstorm Decision 2), on the day the operator authorizes the account change; the 14-day window runs from the first deploy.
- Measures the brainstorm's "Cloudflare trial must measure" list plus, where they apply, criteria 1, 2, 3 (a synchronous call from the outbound handler to an approval store, and the hold limit), 5 and 9 on the managed platform.
- A new Terraform root (R2 backend) for the Worker and its Durable Object namespace, `wrangler deploy` as a `local-exec` with a destroy-time `wrangler delete` (precedent `infra/rung2-rehearsal/rehearsal.tf`); the existing company account; a token scoped to Workers and Containers only; no route to production zones, Pages or R2 (CLO, CPO C5).
- Spend: pinned instance type and `max_instances` so that the worst case (instances x hourly vCPU, memory and disk rate x 336 h, plus Workers and Durable Object requests, duration and storage at a stated ceiling, plus USD 5) is at most USD 50; low `sleepAfter`; a billing notification as backstop only.
- Must not: clone a real repository, use real credentials, expose a public route, enable Logpush or external sinks, write operator email or IP anywhere, receive tenant traffic (CLO).
- Results in `cf-trial-results.md` in this spec directory; `## Measured outcome — Cloudflare trial` appended to ADR-324 (whichever PR merges second rebases and keeps both sections); expense-ledger row in `knowledge-base/operations/expenses.md` opened `approved-not-billing`, `active` on the operator's go, `retired` at teardown with the measured total.
- `Operator-authorizes:` the Workers Paid subscription change, after `GET /accounts/{id}/subscriptions` shows whether the account already has it.

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| Stub approval store implementing the consume contract | A stub satisfies the conversation and hash binding by construction (CTO F-a) |
| A second, hand-written Node TLS injector arm | New crypto code to own; doubles scope (CTO F-b) |
| One shared injector container on the gateway bridge | Holds every session's CA key and credential in one process (CTO F-c) |
| Per-session hook processes | Each would hold the service-role and HMAC keys; one dispatcher-like process with per-session sockets matches production custody (CTO R9) |
| Real GitHub with a test repository and an App installation token | A real credential leaves the suite (CTO F-f) |
| Required CI lane, or the shared `deploy-script-tests-fixed` job | Nothing serves tenants; the shared job's 15-minute cap cannot hold the stack (CTO F-g, R12) |
| Cloudflare trial in this PR | Ties this merge to a 14-day window, a spend hold and a teardown (CTO F-d) |
| Change `egress-forwarder.mjs` to route inject hosts to the injector (forwarder first) | Would put TLS termination on a tenant-serving hop and fire DPIA trigger t3 (CLO); recorded in ADR-324 as #11637's alternative (CTO R17) |
| A hand-written GraphQL operation classifier | Gets fragments, multiple operations and `operationName` wrong, and a wrong answer lets a write through (CTO R23) |

Rejected vendors and set-aside candidates are in the brainstorm's table and carried into ADR-324 unchanged.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly in this PR, because no tenant path changes; the risk is a wrong GO that sends #11637 to build a tenant-facing injector on a mechanism that leaks or misgates.
- **If this leaks, the user's data and workflow are exposed via:** each pair below, all measured by the suite before any tenant path exists.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one founder's GitHub token attached to a request they did not approve, or to another tenant's request, is a single-user breach of the core trust promise, so the threshold is not `aggregate pattern`.

Artifact and vector pairs (for `soleur:engineering:review:user-impact-reviewer`):

- Egress hop: a tenant credential attached to a request the founder did not approve (criterion 3).
- Egress hop: a tenant credential attached to another tenant's request (criterion 5).
- Sandbox and same-uid file tools: the real credential, CA key, hook socket or nonce readable from inside bwrap or by the CLI-process `Read`/`WebFetch` tools (criterion 1).
- Approval hook: a sandboxed process connecting to the hook socket and consuming approvals directly (criterion 1, CTO R9).
- Approval hook custody: the service-role and HMAC keys in one process, recorded in ADR-324 as blast radius for #11637.
- Managed platform (sibling PR): a third party holding decrypted tenant traffic and credentials.
- Approval card: an approval consumed by a different mutation than the one approved (criterion 3 binding).
- Approval card: an approval the founder cannot read and approves blind (results note records `canonical_action` per class; on GO a #11637 criterion).
- Classifier: a GraphQL mutation or a git push classified as a read and vended without approval (Guard 2, hermetic tests).
- Approved reads: a read token plus open-web egress moving private repository content to a third party with no write approved (recorded residual).
- Our own logs: tokens or bodies in the injector audit log, hook output or squid log; a session CA key outliving its session (criteria 6 and 9).
- Session: injector or hook down or slow, and `git`, `gh` or `claude` streaming hangs or silently proceeds with the credential (criterion 8).
- Trial data not really synthetic: a decoy copied from real data (fixtures generated per run, `cq-test-fixtures-synthesized-only`).

CPO sign-off (2026-11-09): approved with conditions C1 (milestone move and blocked-by edges: Phase 0), C2 (these failure modes: this section), C3 (pause review date with an owner: Phase 0 and `## Operator Holds`), C4 (approval binds to the request: criterion 3), C5 (trial isolated from production: Phase 4). `soleur:engineering:review:user-impact-reviewer` runs at review.

## Observability

```yaml
liveness_signal:
  what: the egress-injector-spike CI job writes injector-spike-results.json with a top-level verdict field on every run
  cadence: per dispatch and per pull request push that changes the spike directories
  alert_target: the pull request's check status (a missing verdict or INCONCLUSIVE fails the job)
  configured_in: .github/workflows/infra-validation.yml job egress-injector-spike
error_reporting:
  destination: the suite's stdout markers and the uploaded raw JSON (nothing leaves the suite; the production Sentry mirror is #11637's)
  fail_loud: SOLEUR_EGRESS_VEND_REFUSED reason=<reason> on stdout for every refusal, and a non-zero suite exit when any criterion lacks a verdict or the verdict is INCONCLUSIVE
failure_modes:
  - mode: a criterion silently has no verdict (probe never ran)
    detection: outcome floor in injector-spike-docker.test.sh fails the job
    alert_route: pull request check status
  - mode: the suite skips because docker, bwrap or the Supabase stack is missing
    detection: the suite treats a missing dependency as FAIL, never SKIP
    alert_route: pull request check status
  - mode: approval hook stalls or dies and the injector holds or passes the request
    detection: criterion 8 probes, SOLEUR_EGRESS_VEND_REFUSED reason=hook-timeout, iron-proxy's audit line, and the stub's token record
    alert_route: pull request check status
  - mode: a secret reaches a log or a same-uid reader
    detection: criterion 6 log grep and criterion 1 CLI-tier probes
    alert_route: pull request check status
logs:
  where: the CI job log plus the uploaded raw JSON artifact; the committed injector-spike-results.json
  retention: CI artifacts 90 days; the committed JSON for the life of the repository
discoverability_test:
  command: bash apps/web-platform/test/infra/egress-injector-spike/print-verdict.sh
  expected_output: verdict=
```

The probe prints `verdict=GO`, `verdict=NO-GO` or `verdict=INCONCLUSIVE` and exits 1 on a missing or unknown verdict; it confirms a verdict was recorded, not which one. In-surface probe (Phase 2.9.2): every detection is emitted from inside the suite's sandbox, injector, hook or stub; the marker fields (`class`, `rule`, `reason`) discriminate classifier error, missing row, pending, rejected, expired, flag and timeout in one event.

## Encryption Posture

Skipped: this PR introduces no persistent store and no production cross-component connection. Every TLS connection in it (sandbox to injector, injector to stubs) exists only inside the CI suite, with certificate verification on in both directions. The tenant-path posture is #11637's deliverable.

## Infrastructure (IaC)

This PR provisions nothing: no Terraform, cloud-init, compose or host change, and no change to `egress-forwarder.mjs`, `egress-gateway-squid.conf` or `agent-env.ts`. The sibling Cloudflare trial PR's apply path is in Phase 4 (new Terraform root, `local-exec` wrangler with destroy-time delete, scoped token), per `hr-all-infrastructure-provisioning-servers`.

## Task Design

Not triggered: no new workflow file and no new trigger (the new job joins `infra-validation.yml` on its existing `pull_request` and `workflow_dispatch` triggers), and the 2026-11-30 reminder reuses the existing schedule-reminder endpoint rather than creating a task surface.

## Architecture Decision (ADR/C4)

### ADR

Create ADR-324 (provisional; free across all `origin/*` refs on 2026-11-09) via `soleur:architecture`: "Egress credential injection is a property of the hop, decided apart from the isolation runtime". Conditional: the ADR-311 addendum on GO, or its see-also on NO-GO (Phase 3). If the ordinal collides, renumber and sweep this plan, `tasks.md`, the results note and every AC with `grep -rn 'ADR-324' knowledge-base/project/{plans,specs}/` in the same edit.

### C4 views

No `.c4` change in this PR. Checked against all three model files: external actors (the founder as approver is the existing user actor; no new human actor); external systems (`github` and `cloudflare` exist in `model.c4`); containers (`platform.webapp.egressForwarder` and `platform.infra.egressGw` exist and are unchanged; `publicInternet` exists); access relationships (none change; the `claude -> egressForwarder -> egressGw -> publicInternet` edges model the carrier the suite reuses). The injector is test-only here; ADR-324's C4 section names `egressInjector` as a pending container assigned to #11637. Known gap carried forward, not widened: the egress elements are in no view. Gate: `plugins/soleur/test/c4-count-parity.test.sh`, `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts` stay green.

### Sequencing

ADR-324 is `adopting` now and describes the target state; the measured outcome is appended in this PR and the Cloudflare outcome in the sibling PR.

## Guard Contract

### Guard 1 — Credential non-observability probe

**Property.** No byte sequence equal to a session's real decoy credential, CA key, hook nonce or hook socket is readable or connectable from inside that session's sandbox or by its same-uid file tools.

**Assembly.** Two chokepoints. Inside bwrap: the scan in arm `c1` of `injector-spike-docker.test.sh`, computed from `scanSandboxSurfaces`'s return, never from probe exit codes. Outside bwrap: the CLI-tier arm, whose verdict is computed from the stub Anthropic server's record of each scripted `Read`/`WebFetch` tool result. Every surface flows through one of the two; the positive control (same-uid harness reads `/proc/<injector pid>/environ`) proves the outside chokepoint can see.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Pass the decoy credential to the injector through its environment instead of an fd | RED: the CLI-tier `Read` of `/proc/<pid>/environ` returns it unless masked |
| 2 | The in-sandbox scanner returns zero surfaces (dispatch emptied) | RED: the planted control string is not found |
| 3 | Write the decoy into a second file after a first clean file | RED: every file is scanned, not the first |
| 4 | Move the CA key file out of the masked directory | RED: the CLI-tier `Read` returns it |
| 5 | Harness: the positive control reads a path that does not exist | RED: the control must read real bytes before denials count |
| 6 | Must-PASS: decoy only in the injector's fd, every secret under masked paths | PASS |

### Guard 2 — Vend gating

**Property.** A request to an inject host receives the real credential only if the policy classifies it as an allowlisted read, or one approved row whose hash equals this request's canonical action is consumed for it.

**Assembly.** `approval-hook.mjs`'s single `decide(request, session)` function, called by the gRPC handler for every request iron-proxy forwards for the four inject hosts; the classifier and hash recipe are the pure functions in `policy.mjs` under test in `egress-injector-policy.test.ts`. Second chokepoint: iron-proxy's header-replacement transform must fire only after the hook returns CONTINUE; the suite asserts the ordering with a write the hook REJECTs, checking the stub recorded no request or no real token.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Classifier labels `POST git-receive-pack` as a read | RED (hermetic test and criterion 3) |
| 2 | `decide` returns CONTINUE before calling `consume_approval` (dispatch skipped) | RED: criterion 3 finds the row still `approved`, not `consumed` |
| 3 | GraphQL body with a `query` first and a `mutation` second, selected by `operationName` | RED unless classified as a write |
| 4 | Hash omits the body digest, so two REST POSTs with different bodies share a hash | RED: binding arm of criterion 3 |
| 5 | Push hash omits the repository path, so a row for repo X authorizes the same update on a fork | RED: binding arm and hermetic fork test |
| 6 | The push ref advertisement GET is made to require a row | RED: an approved push fails at the POST |
| 7 | An unlisted REST write defaults to "needs a row" instead of `not-allowlisted` | RED: criterion 7's first-pass control |
| 8 | Reorder iron-proxy transforms so header replacement runs before the gRPC hook | RED: the REJECT arm sees the real token at the stub |
| 9 | Harness: the flag-off arm reads the flag from the same input as flag-on | RED: the suite asserts the two arms received different flag inputs |
| 10 | Must-PASS: a GraphQL `query` with variables and an `operationName` | PASS, vended without a row |

### Guard 3 — Outcome floor and never-skip

**Property.** The suite exits zero only when every criterion 1–9 has a measured verdict (`pass` or `fail`) backed by a positive observation; any `unmeasurable` criterion makes the verdict INCONCLUSIVE and the exit non-zero.

**Assembly.** The final outcome-floor block of `injector-spike-docker.test.sh`, which reads the raw JSON the arms wrote; every arm writes through one `record_verdict` function, and the floor counts distinct criterion ids, not lines.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the arm for criterion 5 | RED: the floor finds 8 of 9 ids |
| 2 | `record_verdict` writes nothing (dispatch emptied) | RED: zero ids |
| 3 | Criterion 4 recorded twice and criterion 6 never | RED: the floor counts distinct ids |
| 4 | Make docker unavailable | RED (FAIL), never SKIP |
| 5 | All criteria `unmeasurable` with recorded reasons | RED: INCONCLUSIVE, exit non-zero |
| 6 | Must-PASS: every criterion measured, criterion 4 `fail` | PASS (exit 0), verdict NO-GO |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "agent runtime sandbox evaluation (injector-first)" [brief] | Whole plan; ADR-324 + injector spike | mapped |
| 2 | "Brainstorm complete with 11 key decisions, plan next." [brief] | Proposed Solution carries Decisions 1–11; Phase 3 | mapped |
| 3 | "A decision record states that injection is a substrate-independent hop gated by ADR-309 approvals, lists the options ranked on the operator's criterion, and carries the flip facts and the CLO gates for a managed platform." [doc spec FR1] | ADR-324, Phase 3 | mapped |
| 4 | "A results note records pass or fail for each of the seven criteria in the brainstorm's \"Spike go/no-go criteria\", with raw outcomes, on the production run tuple." [doc spec FR2] | Phases 1–2, injector-spike-results.md (criteria 1–9 cover the seven; mapping in the spec edit) | mapped |
| 5 | "A results note records each item in the brainstorm's \"Cloudflare trial must measure\" list, the amount spent, and confirmation that the trial resources were torn down." [doc spec FR3] | — | descoped — justification: CTO ruling F-d moves the trial to a sibling PR under widened #9859 Arm D on this spec; Phase 4 records its requirements |
| 6 | "On a spike pass, #12467 is closed as superseded and #11637 proceeds from the measured mechanism. On a fail, #12467 resumes and the flip facts are evaluated." [doc spec FR4] | Phase 3 dispositions | mapped |
| 7 | "S3 (#9845) is widened to generic per-host injection with approval attachment, and S0 Arm D (#9859) is widened from paperwork to the Cloudflare trial." [doc spec FR5] | Phase 3 issue edits (S3 as a linked section, CTO R19) | mapped |
| 8 | TR1–TR9 [doc spec] | TR1 criterion 1; TR2 criteria 3–4; TR3 criterion 9; TR4 criterion 5; TR5 criterion 6; TR6 Legal review; TR7 Phase 4; TR8 markers; TR9 results note | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| ADR-324 | asks 3 | asked |
| `injector-spike-docker.test.sh`, stub, hook, `policy.mjs`, policy data, config, probe | asks 4, 8 | asked |
| `print-verdict.sh` | — | inferred — justification: the discoverability probe cannot contain a pipe and must fail on a missing verdict (preflight Check 10) |
| `iron-proxy-image.provenance.md` | — | inferred — justification: a digest-pinned third-party image without a provenance record breaks the `egress-gw-image.provenance.md` convention (CTO) |
| `egress-injector-policy.test.ts` | — | inferred — justification: `cq-write-failing-tests-before`; the classifier is the property Guard 2 protects |
| `package.json` and `package-lock.json` edits | — | inferred — justification: CTO R23; a real GraphQL parser and the gRPC library the hook needs |
| `infra-validation.yml` job | — | inferred — justification: CTO F-g, R12, R22 |
| injector-spike-results.md and .json | asks 4 | asked |
| ADR-311 addendum (GO) or see-also (NO-GO) | "It amends ADR-311 Decision 4 only if the spike measures a hook that satisfies it." | asked |
| Issue edits on #12467, #11637, #9845, #9859, #12517 | asks 6, 7 | asked |
| Milestone move and blocked-by edges | — | inferred — justification: CPO condition C1 |
| 2026-11-30 reminder | — | inferred — justification: CPO C3, CTO R18 |
| Demand-side telemetry follow-up issue | — | inferred — justification: COO; `wg-when-deferring-a-capability-create-a` |
| Phase 4 sibling-PR record | asks 5 | asked (descoped from this PR, recorded) |

### Split Assessment

- Subsystems touched: 3 — `apps/web-platform`, `knowledge-base`, `.github`
- Planned files: 18 | Estimated changed lines: about 2,100 (suite about 800, stub about 300, hook and policy about 400, hermetic tests about 250, ADR about 200, results and provenance about 150)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split — already applied: the Cloudflare trial is the sibling PR (CTO F-d). The rest is one measurement harness plus the decision record it feeds; splitting the ADR from the spike would merge a decision record whose measured-outcome section is empty, so this PR stays whole.

## Files to Create

- `knowledge-base/engineering/architecture/decisions/ADR-324-egress-credential-injection-is-a-property-of-the-hop.md`
- `apps/web-platform/test/infra/egress-injector-spike/injector-spike-docker.test.sh`
- `apps/web-platform/test/infra/egress-injector-spike/print-verdict.sh`
- `apps/web-platform/test/infra/egress-injector-spike/iron-proxy-image.provenance.md`
- `apps/web-platform/test/infra/egress-injector-spike/iron-proxy.config.tmpl.yaml`
- `apps/web-platform/test/infra/egress-injector-spike/policy.yaml`
- `apps/web-platform/test/infra/egress-injector-spike/policy.add-verb.yaml`
- `apps/web-platform/test/infra/egress-injector-spike/policy.mjs`
- `apps/web-platform/test/infra/egress-injector-spike/approval-hook.mjs`
- `apps/web-platform/test/infra/egress-injector-spike/stub-github/server.mjs`
- `apps/web-platform/test/infra/egress-injector-spike/probes/sandbox-probe.sh`
- `apps/web-platform/test/egress-injector-policy.test.ts`
- `knowledge-base/project/specs/feat-agent-runtime-sandbox-eval/injector-spike-results.md`
- `knowledge-base/project/specs/feat-agent-runtime-sandbox-eval/injector-spike-results.json`

## Files to Edit

- `.github/workflows/infra-validation.yml` — new `egress-injector-spike` job (CTO R22)
- `apps/web-platform/package.json` and `apps/web-platform/package-lock.json` — exactly pinned devDependencies `graphql` and `@grpc/grpc-js@1.14.6`
- `knowledge-base/engineering/architecture/decisions/ADR-311-credential-broker-mechanism-measured-before-built.md` — merge-conditioned addendum on GO, or see-also on NO-GO
- `knowledge-base/project/specs/feat-agent-runtime-sandbox-eval/spec.md` — FR3 moves to the sibling PR; FR2 maps the brainstorm's seven criteria to criteria 1–9 (criterion 8 fail-closed and 9 CA scope added, 3 extended with binding); TR1 reads "the sandbox holds no credential; the injector replaces the whole `Authorization` header"; TR2 lists protocol-classified reads (upload-pack POST, GraphQL query POST, push ref advertisement); the file-count baseline 36 / 42; the verdict set GO / NO-GO / INCONCLUSIVE
- `apps/web-platform/test/helpers/broker-spike-scan.ts` — only if a new surface needs a parameter; otherwise unchanged

## Open Code-Review Overlap

Two open code-review issues touch `.github/workflows/infra-validation.yml`: #8735 (notify-main-failure misses cancelled jobs), #7942 (two mutation batteries run in no gate).

- #8735 — Acknowledge: a different concern (main-branch failure email); the new job never runs on push to main.
- #7942 — Acknowledge: concerns `plugins/soleur/test/*.mutation.sh`; this plan's mutation rows run by hand against its own suite.

## Operator Holds

- Hold: Operator-authorizes: arm one issue-comment reminder on #12467 for 2026-11-30 through `POST /api/internal/schedule-reminder` (a production write), so the paused per-verb work resumes on that date if the spike has not reported.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] ADR-324 exists with status `adopting`, the interface-scoped independence claim, the ranked options, flip facts F1–F4, the CLO gates quoted verbatim, the T-1 mapping marked unverified, the hook key custody and forwarder-first alternative, `egressInjector` named as pending in its C4 section, and a `## Measured outcome — injector` section citing `injector-spike-results.md`.
- [ ] `injector-spike-results.md` opens with three plain sentences and records a verdict (`pass | fail | unmeasurable`) and raw outcome for criteria 1–9, the run URL, commit SHA, image digests, SDK pin, machine class, date, each claim's label, the re-measure trigger, the guard-matrix by-hand results, and GO or NO-GO (an INCONCLUSIVE run is not shipped).
- [ ] `bash apps/web-platform/test/infra/egress-injector-spike/print-verdict.sh` prints `verdict=GO` or `verdict=NO-GO` and exits 0.
- [ ] Criterion 7's comparison names one data file against #12188's 9 source files and what the overlay leaves out.
- [ ] #12517 is in milestone "Phase 4: Validate + Scale"; #12467 and #11637 are blocked by #12517; #9845 carries the linked section and #9859 the widened Arm D, both linking the spec; #12467 carries the pause comment; the demand-side telemetry issue exists.
- [ ] On GO only, the ADR-311 addendum exists and is worded "on merge of PR #12518"; on NO-GO, the ADR-311 see-also exists.
- [ ] `git diff --name-only origin/main...HEAD` contains none of `apps/web-platform/infra/egress-forwarder.mjs`, `apps/web-platform/infra/egress-gateway-squid.conf`, `apps/web-platform/server/agent-env.ts`, any path under `apps/web-platform/supabase/migrations/` or `apps/web-platform/server/`, or any `.tf` file (CLO: DPIA trigger t3 does not fire on this PR).
- [ ] The committed results JSON and note contain no string matching a GitHub token format (`gh[pousr]_` prefix); only generated decoys appear, none in a real token format.
- [ ] NFR register assessment run (`soleur:architecture assess`) and recorded in the ADR.
- [ ] `egress-injector-policy.test.ts` green in the `webplat` shard; the `egress-injector-spike` job green on the PR; `.github/scripts/test/test-infra-suite-registration.sh` green.
- [ ] `python3 scripts/lint-guard-contract.py` passes on this plan; the C4 tests listed above are green; `technical-ruling-gate.sh --branch` passes.

### Post-merge (on merge, by `soleur:ship`)

- [ ] The issue lines in the merged PR body match the committed verdict (GO: `Closes #12517`, `Closes #12467`; NO-GO: `Closes #12517`, `Ref #12467`).
- [ ] GO: the #11637 comment with its added acceptance criteria exists. NO-GO: #12467 carries the resume comment and no longer has the #12517 blocked-by edge, and #11637 is blocked by #9859.

## Test Scenarios

- Hermetic: every policy row; GraphQL single query, single mutation, multi-operation with and without `operationName`, batched array, unparseable body; receive-pack pkt-lines with one and two ref updates; hash differs for each single-field change; repository spelling variants hash equal; a fork hashes differently.
- Suite: criteria 1–9 as tabled; each Guard mutation row run once by hand and recorded in the results note with the run URL that reddened.

## Domain Review

**Domains relevant:** Engineering, Legal, Operations, Product

### Engineering

**Status:** reviewed
**Assessment:** CTO rulings F-a to F-g and R1 to R23 are binding (`decision-challenges.md`). Risks: the hash recipe is new and lives in policy data; the per-session injector and the hook put secrets in the same-uid app tier, so masked paths and the CLI-tier probes are load-bearing; reads vend without a row, so the confused-deputy residual is recorded, not removed; production `NO_PROXY` keeps GitHub traffic off the proxy, so adoption needs an `agent-env.ts` change (#11637). The Cloudflare trial needs a Terraform root with `local-exec` wrangler.

### Legal

**Status:** reviewed
**Assessment:** DPIA trigger t3 does not fire on this PR: the injector, CA and config live only under test paths and no production config references them; #9853's re-screen blocks the first PR that puts TLS termination on a tenant-serving hop (#9845 / #11637), and the ePrivacy question goes to outside counsel before that PR. The suite makes no Sentry call; the results JSON holds decoys only; nothing is appended to the DPIA memo. The Cloudflare trial (sibling PR) adds no Art. 28 role, sub-processor, Article 30 or published-document change if no personal data is processed; it uses the existing company account; its result satisfies no CLO gate.

### Operations

**Status:** reviewed
**Assessment:** Spend control for the trial is the configuration bound, not a billing alert; the expense-ledger row and teardown cancellation belong to the sibling PR. Demand-side telemetry cannot come from a synthetic trial and is filed separately.

### Product/UX Gate

Not applicable: tier NONE, no UI surface in Files to Create or Edit. CPO plan-time sign-off: approved with conditions C1–C5 (see User-Brand Impact).

**GDPR gate (Phase 2.7):** 0 regulated paths matched; no Critical. Advisory: Cloudflare's existing DPA row covers CDN and R2, not a Containers role (acceptable for a synthetic-only trial; a CLO gate before any tenant use); t3 fires only for a tenant-path merge; injector logs must exclude bodies and header values (criterion 6).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `soleur:work`.
- `NODE_EXTRA_CA_CERTS` is read at process start, and Bun's support is reported inconsistently; criterion 2 must observe the pinned `claude` binary loading the CA (its debug line), not assume it.
- `SSL_CERT_FILE` and `GIT_SSL_CAINFO` replace the system bundle, so the sandbox's bundle must contain the system roots plus the session CA, or the non-inject SSE probe breaks for the wrong reason.
- iron-proxy's gRPC call has no deadline in source; tracer item 6 and criterion 8 are what prove a dead or slow hook fails closed.
- `docker run -d` returns before squid binds; poll with a deadline (2026-10-12 learning).
- The Docker inter-bridge reply path needs its own `established,related` accept (2026-10-05 learning); a generic RFC1918 drop eats replies on 172.17.0.0/16.
- A "not observable" verdict needs a positive observation (2026-10-30 learning): `/proc` is not mounted in bwrap, so a read error there is not evidence; the CLI-tier positive control is.
- Keep the model out of the assertion path: sandbox probes are direct invocations through the sandbox wrapper, and CLI-tier probes are scripted tool calls from the stub Anthropic server, never natural-language prompts.
- Turn git's tracing off with `unset GIT_TRACE GIT_CURL_VERBOSE`, never `=0`: `GIT_CURL_VERBOSE` is presence-checked, and `=0` would print credential-bearing headers into the logs criterion 6 scans.
- Merging this PR mutates no production surface: it adds a CI job, devDependencies and test-path files only, and no apply or deploy workflow's `paths:` matches them (the `push` trigger of `infra-validation.yml` matches `apps/web-platform/test/infra/**`, and the new job's `if:` excludes push). The PR body's first line says so.
- New `SOLEUR_EGRESS_VEND*` markers live in test-path code; before the first push, `git grep -n 'SOLEUR_EGRESS_VEND'` and run any marker-vocabulary census the full battery carries.
- The expiry arm waits at least 60 s (`p_ttl_seconds` minimum; `expires_at` is immutable); budget it inside the job's 30-minute timeout.
- Run `npx markdownlint-cli2` on this plan and `tasks.md` before committing them.
