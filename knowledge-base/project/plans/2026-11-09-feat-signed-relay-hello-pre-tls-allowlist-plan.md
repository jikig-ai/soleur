---
title: "feat: signed relay hello, pre-TLS peer allowlist and bounded deny reporting (PR A of #8211 / #12167)"
date: 2026-11-09
slug: signed-relay-hello-pre-tls-allowlist
branch: feat-one-shot-12288-12289-12290-signed-relay-hello
issue: 12289
closes: [12288, 12289, 12290]
refs: [12167, 8211]
type: feat
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# feat: signed relay hello, pre-TLS peer allowlist and bounded deny reporting

## Enhancement Summary

**Deepened on:** 2026-11-09
**Agents used:** soleur:engineering:cto (F1-F4), soleur:product:cpo (F5), plan-review panel (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow), deepen-plan security-sentinel and test-design-reviewer. Deterministic checks run inline: User-Brand / Observability / PAT / Guard-Contract / Scope-Check halts, ADR ordinal against freshly fetched `origin/main` (ADR-322 is the last, so ADR-323 holds), every cited rule id present in AGENTS.md, `betterstack-query.sh` exists, `ws` default `maxPayload` read from `node_modules` (104857600), Node `tls.Server` `'connection'` semantics read from the v22.23.4 docs via Context7.

### Key improvements
1. Replay-cache expiry is derived from the hello's own `ts` (`ts + SKEW_S + 1`), not receipt time: a receipt-based 60 s TTL expired exactly at the skew boundary.
2. Unauthenticated-input hardening added to the verifier: byte-length cap on the Buffer before string conversion, text-frame only, exactly six own keys on a plain object, `ts` regex without leading-zero aliases, a distinct `full` reason so a full cache is never mistaken for a replay.
3. A positive off-host signal (`relay_hello_window accepted/denied/suppressed` line) so a signed round trip is provable, which the serve-gate probe cannot do.
4. Every Guard Contract floor is now derivable (one `_report` per row id) and the rows that could not go RED were replaced by behavioural ones (`timingSafeEqual` spy, closed-server spy, future-dated `ts` replay).

### New considerations discovered
- `ws` buffers the whole first frame up to 100 MiB before any application check; the relay and the public server share that default (parity, named residual). A small `maxConnections` was NOT adopted: every proxied session holds one connection, so a cap sized below the concurrent-session ceiling would refuse legitimate users (recorded as a taste item and in the residuals issue).
- Rolling back to a pre-PR image re-opens unsigned hellos (runbook line).
- `/proc/<pid>/environ` keeps the original environment block, so deleting the key from `process.env` would not help; whether the agent sandbox can read the parent's environ is verified read-only at work time and recorded as a residual if not provable.

## Overview

Application change that closes the three owner-conditioned items blocking any external user from being routed to the second web host (the owner's typed risk acceptance on #8211, condition list in issues #12288, #12289, #12290):

1. **#12288** — admit a peer on the raw TCP `remoteAddress` before the TLS handshake starts, and bound deny reporting (fixed Sentry events per window plus a counter) instead of one `reportSilentFallback` per connection.
2. **#12289** — a fail-closed HMAC-SHA256 signed hello `{type,userId,workspaceId,ts,nonce,mac}` keyed with `PROXY_HELLO_HMAC_KEY`, a secret separate from the TLS key. The key already exists in Doppler `prd` (A-0, PR #12414, merged 2026-11-08); nothing reads it yet. This PR makes the first read, so it also lands the sensitive-key entry, the agent-env isolation test, the destroy-guard no-ack rotation counter and the release-time presence gate.
3. **#12290** — a strict `SOLEUR_PROXY_PORT` parse and a guarded `listen()` so a bad port value is mirrored to Sentry, the relay reports `proxy_state=error`, and the app keeps serving 80/443/3000.

Already ruled (CTO, 2026-11-08, on #12289; not re-litigated here): fail-closed on every unsigned or invalid hello; MAC over `"soleur-proxy-hello-v1\n"+userId+"\n"+workspaceId+"\n"+ts+"\n"+nonce`; +-30 s skew; 60 s / 4096-entry replay cache; check order allowlist (pre-TLS) -> 1 KiB cap -> UUID shape -> MAC (constant time) -> ts -> replay -> AP-2 membership; no new `ProxyState` value; key absent -> `recordProxyNotStarted("error")` + Sentry with the app still serving; startup guard `createProxyServer.no-hello-key`; dev/CI without the key means relay off, never fail-closed.

New forks met while planning were ruled by the CTO agent (and the CPO for sign-off) and are recorded in `knowledge-base/project/specs/feat-one-shot-12288-12289-12290-signed-relay-hello/decision-challenges.md` (F1-F5). Their effect on this plan: dedicated destroy-guard counter (F1), presence gate inside the existing `verify-doppler-secrets` release job (F2), `prependListener` pre-TLS mechanism with `ci-deploy.sh` untouched (F3), reporter and wire parameters (F4).

**Out of scope (PR B and the owner-gated acts):** the web-2 serve flip, mTLS or per-host keys, `_PREVIOUS` dual-key verification, `normalizeProxyPem`/`normalizeGitDataKey` unification, deploy-token rotation #12330, #11694, PR #11676, #11669, #10476.

## Research Reconciliation — Spec vs. Codebase

| Brief / issue claim | Reality (checked on this branch) | Plan response |
|---|---|---|
| #12288: "the allowlist is checked on the TCP remoteAddress after the handshake" | True, and worse: `session-proxy.ts` checks inside `wss.on("connection")`, i.e. after TLS **and** the WebSocket upgrade. The in-code comment ("BEFORE the handshake") and the ADR-068 2026-07-02 amendment ("BEFORE the handshake") describe the intent, not the code. | Phase 2 moves the check to the TCP `connection` event; ADR-068 amendment corrects the record. |
| Brief: "keep the relay_peer_probe contract valid" | `ci-deploy.sh` `RELAY_PROBE_JS` maps "reset before `secureConnect`" to `result=tls` and "101 then close frame" to `result=denied`. After a pre-TLS destroy a non-allowlisted source reads `tls`; `denied` becomes unreachable. The grammar, the 3 `relay_*` alert queries (`refused|timeout|tls|denied` fire, `ok`/`skipped` never) and the serve gate (`result=ok`) stay valid. | F3: do **not** edit `ci-deploy.sh` (a baked host script; any byte changes the host-scripts coherence hash). Document the `denied`-reads-`tls` shift in the runbook. |
| Brief: probe sends no hello and decides `ok` after 700 ms | Yes (`setTimeout(verdict,700)`). The owner must not close an allowlisted, hello-less connection within ~700 ms or healthy peers read `denied` and the serve gate refuses. | F3: no hello-deadline timer in this PR; a source comment pins the constraint; a test holds a hello-less allowlisted connection open >1 s. |
| A-0 comment precondition 2: "names-only prd presence read before the A release dispatch" (script + runbook) | `web-platform-release.yml` already has `verify-doppler-secrets` (runs `apps/web-platform/scripts/verify-required-secrets.sh` under `doppler run -c prd`, `deploy` `needs:` it). And a merge to main is itself the release trigger (push -> CI -> `workflow_run`). | F2: add the key to `REQUIRED` there (plus a value-silent shape check). No new script, no new CI secret. |
| A-0 comment precondition 4: "add to the destroy guard's no-ack rotation set" | The only no-ack set is `luks_passphrase_addrs` (six LUKS addresses; HALT text, closed-sequence structural test in `terraform-target-parity.test.ts`, ADR-282 and the exact floor 121 are LUKS-worded). | F1: dedicated counter `relay_hello_key_changes` + its own non-ackable HALT; both addresses are `[0]`-indexed so the match goes through `luks_passphrase_base`. |
| ADR-118 amendment (2026-11-08): "A new ADR waits for the handshake itself" | No ADR for the signed hello exists. Next free ordinal on `origin/main` is ADR-323 (provisional). | Phase 8 authors ADR-323 and amends ADR-068 and ADR-118. |
| Brief: "bad SOLEUR_PROXY_PORT" | `PROXY_LISTEN_PORT = Number(process.env.SOLEUR_PROXY_PORT \|\| 8443)` at module load; `Number("0x20fb")`, `Number("1e3")`, `Number(" 8443 ")` all parse; `listen(NaN \| 70000)` throws `ERR_SOCKET_BAD_PORT` synchronously out of `createProxyServer` into `index.ts` (restart-loops the whole app). The sender dials `wss://host:NaN`. Prod pins the value to the literal 8443 in `ci-deploy.sh`, so the fault is dormant today. | Phase 5: strict `^[0-9]{1,5}$` + 1..65535 parse at call time, try/catch around `listen()`, sender uses the same parser. |
| Issue #12289: "owner rejects a hello with a bad or missing MAC" | Existing test fixtures use non-UUID ids (`user-42`, `ws-9`) and the old hello shape. | Phase 4 rewrites those fixtures with synthesized UUIDs. |
| CPO read: "client reconnects and is re-routed" during the stagger | Wrong for a user whose lease sits on the host being upgraded: routing is by lease holder, so a reconnect proxies to the same owner and is refused again until the sender is upgraded (close code 4014 `ROUTING_UNAVAILABLE`, no client handling beyond the generic reconnect loop). Live users today: 0. | Named in User-Brand Impact and in the rollout runbook; the release stays gated on `agent_sessions_live=0` on both hosts. |

## Research Insights

**Premise validation (Phase 0.6).** #12288/#12289/#12290 open, no closing PR; PR #12414 (A-0) MERGED 2026-11-08T23:17Z; PR #12462 is this branch's draft (the only collision hit for all three issues); epic #12167 open. All cited paths exist on `origin/main`: `session-proxy.ts`, `proxy-tls.ts`, `proxy-listener-status.ts`, `sensitive-keys.ts`, `agent-env.ts`, `tests/scripts/lib/destroy-guard-filter-web-platform.jq`, `proxy-hello-hmac.tf`, `scripts/key-rotate.sh` `kk_copy_state`. ADR corpus check (mechanism nouns `hello`, `HMAC`, `peer allowlist`, `rotation set`): ADR-068 (peer allowlist, mTLS rejected as dominated), ADR-118 (key joins the count gate, defers the guard), ADR-282 (LUKS protection set; not extended). No ADR rejects the chosen mechanisms. Names-only prd presence of the key was verified in A-0 (not re-read here: reading Doppler is not needed to plan, and the release gate re-checks it at deploy time).

**Property List (Phase 0.6b).**
- P1. A private-net host that is not an allowlisted peer costs no TLS handshake and cannot flood Sentry.
- P2. A relayed session attaches only for a hello with a valid MAC under a key distinct from the TLS key, a timestamp inside +-30 s, and a nonce not seen in about 61 s; every other hello is refused before the membership lookup.
- P3. A bad `SOLEUR_PROXY_PORT` or a missing/invalid hello key stops only the relay, is reported, and the app keeps serving.
- P4. The hello key never reaches an agent env, a log line or a Sentry event.
- P5. A routine merge apply (or an `[ack-destroy]`) cannot replace, update, forget or re-mint the key.
- P6. A release cannot deploy while the key is absent or empty in prd (presence-only gate; a present-but-malformed value is caught at app startup, which leaves the relay in `error` with the app serving).
- P7. The `relay_probe` / `relay_peer_probe` grammars and the three `relay_*` alert queries stay valid.

**Cut List.**
| Mechanism | Property it would buy | Verdict |
|---|---|---|
| Accept-unsigned-and-log phase then enforce flip (architecture reviewer) | smoother mixed-version window | CUT by CTO ruling: N=0 live users; re-ask the CTO if `agent_sessions_live` is not 0 at release time |
| `_PREVIOUS` dual-key verification | zero-downtime rotation | CUT: rotation has no route; the new HALT blocks rotation instead |
| New `ProxyState` value for "no hello key" | distinct alert | CUT by ruling: reuse `error` (the `relay_listener_down` alert already covers it) |
| Hello deadline timer | slow-peer DoS bound | CUT (F3): conflicts with the probe's 700 ms `ok`; recorded as a named residual |
| Edit `RELAY_PROBE_JS` so a pre-TLS reset reads `denied` | keep `denied` meaningful | CUT (F3): changes a baked host script and the coherence hash for no gate benefit |
| Standalone preflight script + runbook step | key presence | CUT (F2): the existing `verify-doppler-secrets` job already gates `deploy` |
| Reuse `luks_passphrase_addrs` | no-ack rotation | CUT (F1): wrong word, wrong text, wrong floor |

**Institutional learnings applied.** `2026-05-29-warn-level-debounce-for-recovered-fallback-sentry-floods` (flood-bounded Sentry arm, full-fidelity pino); `2026-09-14-my-proxy-allowlisted-the-messages-it-relayed-and-relayed-them-verbatim` (a relay must validate what it forwards); `2026-10-09-a-revert-recipe-dry-run-must-run-every-gate-and-no-openssl-flag-reads-an-hmac-key-from-stdin` (never put an HMAC key on argv; tests derive MACs in-process); plan-sharp-edges entries on RNG alphabets in negative-substring assertions (hex ids), validator grandfathering (UUID shape vs existing fixtures), CI-gate ACs running the gate's own invocation, and `-target` allow-list work lists derived by `git grep`.

**Spike (done during planning, repeat as a test).** `/var/tmp/relay-spike/spike.mjs` on Node 26.13 and on Node 22 (the production image is `node:22-slim`, 22.23.4): `httpsServer.prependListener("connection", s => s.destroy())` -> client `ECONNRESET`, `secureConnection` 0, no uncaught exception, exactly one `tlsClientError` (Node's wrapper). Phase 2's real-socket test is the standing guard on whichever Node CI uses.

## Open Code-Review Overlap

None. (Queried open `code-review` issues against every planned file path: `session-proxy.ts`, `proxy-tls.ts`, `proxy-listener-status.ts`, `sensitive-keys.ts`, the destroy-guard `.jq`, `apply-web-platform-infra.yml`, `web-platform-release.yml`, `verify-required-secrets.sh`, `betterstack-log-query.md` - zero hits.)

## User-Brand Impact

- **If this lands broken, the user experiences:** a relayed session that never attaches: the client sees close code 4014 (`ROUTING_UNAVAILABLE`) and the generic reconnect loop. Affected users are exactly those whose worktree lease sits on the *other* host: during the rolling-deploy stagger (a few minutes, old sender -> new receiver is refused) and, if the relay is stopped by a missing/invalid key or a bad port, for as long as it stays stopped ("serves locally only" holds only for users routed `local`). No data loss, no wrong-tenant attach. A broken verifier that rejects valid hellos is the same symptom; the serve gate (`relay_peer_probe result=ok`) cannot see it because the probe sends no hello (see Risks R2).
- **If this leaks, the user's workspace and session are exposed via:** the owner host's `attachProxiedSession`, a token-less act-as-user session. Before this PR a valid user UUID plus a reachable port 8443 is the whole credential (`verifyProxiedSessionMembership` returns true whenever `workspaceId === userId`). After it the credential is a MAC under `PROXY_HELLO_HMAC_KEY`; exposure vectors are the key itself (Doppler `prd` readers, Tier-A Terraform state readers (ADR-320), container env, logs, Sentry, agent env) and replay of a captured hello inside the 60 s window by a compromised roster host.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one account takeover or one user's workspace opened to another is brand-ending for a product whose pitch is the user's own repo and agent; `aggregate pattern` would understate a single forged hello. CPO signed off at plan time (F5) on the conditions that rejection precedes the membership lookup and the replay window (60 s total) is stated as a plan decision.
- Close reasons never reveal which check failed: every post-upgrade refusal uses the single reason string `relay refused`.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "peer allowlist check on the TCP remoteAddress BEFORE the TLS handshake" [brief] | Phase 2 | mapped |
| 2 | "BOUNDED deny reporting (fixed number of Sentry events per window + a counter)" [brief] | Phase 1 | mapped |
| 3 | "Keep the relay_probe / relay_peer_probe log contracts and the 3 Better Stack relay_* alert queries ... valid" [brief] | Phase 2 (tests pin), Phase 8 (runbook), no edit to `ci-deploy.sh` / `betterstack-logs-alerts.tf` | mapped |
| 4 | "HMAC hello as above" [brief] | Phases 3-4 | mapped |
| 5 | "Add PROXY_HELLO_HMAC_KEY to sensitive-keys.ts ... keep it OUT of agent-env.ts and ALLOWED_SERVICE_ENV_VARS, with a test" [brief] | Phase 3 | mapped |
| 6 | "Add random_bytes.proxy_hello_hmac / doppler_secret.proxy_hello_hmac_key to the destroy guard's no-ack rotation set ... with its tests" [brief] | Phase 6 (F1 shape) | mapped |
| 7 | "Names-only prd presence preflight before the release dispatch ... decide where it belongs" [brief] | Phase 7 (F2) | mapped |
| 8 | "wrap listen() so a bad SOLEUR_PROXY_PORT is Sentry-mirrored and the relay reports proxy_state=error" [brief / issue #12290] | Phase 5 | mapped |
| 9 | "Add a runbook note" (rolling deploy) [brief] | Phase 8 | mapped |
| 10 | "Startup guard: ... report createProxyServer.no-hello-key to Sentry and stop the relay" [brief] | Phase 4 | mapped |
| 11 | "mutate EVERY added guard on a sandbox copy in the commit that adds it" [brief] | Guard Contract + every phase | mapped |
| 12 | "pre-push gate list derived from the CI steps INCLUDING each CI flag" [brief] | Pre-push gate list | mapped |
| 13 | "ADR/C4/runbook/KB updates where relevant (check ADR-068, ADR-118, runbooks mentioning the relay hello)" [brief] | Phase 8 | mapped |
| 14 | "Review panel includes security-sentinel and test-design-reviewer at minimum" [brief] | Review plan | mapped |
| 15 | "Do NOT plan PR B items" [brief] | Out of scope list | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Bounded reporter leaf module | "BOUNDED deny reporting (fixed number of Sentry events per window + a counter)" | asked |
| Shared canonical MAC module used by sender and verifier | "HMAC-SHA256 over ..." | asked (single source avoids sender/verifier drift; F4) |
| Sender-side signing in `proxyClientToOwner` | "new sender to old receiver works" | asked |
| Strict port parse also applied on the sender | "a bad SOLEUR_PROXY_PORT" | inferred — justification: the same env var feeds the dial URL (`wss://host:NaN`) and an uncaught rejection from `proxyClientToOwner` is the same failure class; ~6 lines |
| `relay_hello_window accepted=<n> denied=<n> suppressed=<n>` warn line per window | "new sender to old receiver works" (needs a positive, off-host signal to be provable) | inferred — justification: the serve-gate probe sends no hello, so only an accepted-hello count can prove a deployed signed round trip (CPO condition; PR B precondition); counts only, same timer as the reporter |
| Runbook section "Signed hello rollout (#12289)" in `betterstack-log-query.md` | "Add a runbook note" | asked |
| Tracking issue for the F3 residuals | "wg-defer-only-after-inline-triage" (AGENTS.md deferral rule) | inferred — justification: a deferral without a tracking issue is invisible |
| `proxy-hello-key` isolation test file | "keep it OUT of agent-env.ts and ALLOWED_SERVICE_ENV_VARS, with a test" | asked |

### Split Assessment

- Subsystems touched: 5 — `apps/web-platform/server`, `apps/web-platform/scripts`, `.github/workflows`, `tests/scripts` (+ `plugins/soleur/test`), `knowledge-base`
- Planned files: ~22 | Estimated changed lines: ~1400 (about half tests)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines — exceeded on roots and lines
- Recommendation: single PR — the three issues are one owner condition set ("must ship before any external user is routed"), the key's first read and its guards must land together (`sensitive-keys.ts` "in the same PR as the first read"; the rotation HALT "because after A a replace is an outage"), and commits are ordered so Phases 6-7 (guard rails) can be reviewed independently of Phases 1-5 (relay code).

## Downtime & Cutover

- **Operation and surface.** The rolling container swap (web-1 first, web-2 after the fan-out) changes the relay hello shape. Affected surface: relayed (proxied) sessions only. Local sessions, 80/443/3000 and every non-relay path are untouched on both hosts.
- **Zero-downtime path evaluated.** An accept-unsigned-and-log phase followed by an enforce flip (architecture reviewer) would remove the refusal window; the CTO ruled it out (2026-11-08, N=0 live users, fail-closed is the safer default) and a dual-accept window would leave the takeover vector open for its whole length. New sender -> old receiver already works (the old parser ignores extra keys; verified once against the real pre-PR parser in Phase 4).
- **Residual accepted.** Old sender -> new receiver is refused for the stagger (a few minutes). Bounded: it only affects users whose lease sits on the lagging host (live users: 0 today); named in User-Brand Impact; the release is owner-named only after `agent_sessions_live=0` is read on both hosts. If `agent_sessions_live` is not 0 at release time the CTO is re-asked (ruling on #12289 point 5). Rollback to a pre-PR image re-opens unsigned hellos until the roll-forward; the runbook says so.
- **Per-stage verification.** After web-1: `relay_probe proxy_state=listening` (read-only query) and no `createProxyServer.no-hello-key` issue; after web-2: both hosts listening and, once a real proxied session exists, `relay_hello_window accepted>0`.

## Architecture Decision (ADR/C4)

### ADR
- **Create ADR-323** (provisional ordinal; `bash scripts/check-adr-ordinals.sh` re-verifies at ship) via `soleur:architecture`: *Session relay peer admission happens on the raw socket and every hello is HMAC-signed under a dedicated key.* Records: the check order, fail-closed semantics, the wire format, replay bounds (60 s total window), the bounded reporter, the dedicated no-ack counter (F1), the release-time presence gate (F2), the pre-TLS mechanism and the `denied`-reads-`tls` consequence (F3), the Tier-A state exposure (the key is minted by `random_bytes` in the web-platform root, so anyone with Tier-A state read can forge hellos; accepted debt as for `PROXY_TLS_KEY`, cite ADR-320 and ADR-241), and the named residuals (idle allowlisted peers, `ws` default `maxPayload` buffering of the first frame, a captured hello replayable to a different host inside 60 s because the MAC does not bind the target host).
- **Amend ADR-068** (2026-07-02 amendment (a) says "BEFORE the handshake"): dated amendment stating that until this PR the check ran after TLS and upgrade, and now runs on the TCP `connection` event; the hello is signed.
- **Amend ADR-118** (2026-11-08 paragraph): the key is now in a no-ack counter, so the "setting the flag false plans six destroys under `[ack-destroy]`" route is closed on the per-merge path (the HALT is not ackable); retiring the relay needs a separately reviewed route; also `verify-required-secrets.sh` must drop the entry in the same change that turns `host_proxy_tls_enabled` off.

### C4 views
Read all three of `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` at work time before concluding. Planned conclusion, to be confirmed by that read: **no C4 impact, no `.c4` edit** (a comment-only edit would answer no ask and risk the freshness gate; the `coordinator` comment already describes the allowlist and `PROXY_TLS_CERT`). Actors/systems/relationships checked and found already modeled: external human actors (none added; the roster hosts are the same web-1/web-2 nodes), external systems (Doppler delivers `PROXY_HELLO_HMAC_KEY` over the existing `doppler -> engine "Runtime secrets"` edge; Sentry and Better Stack edges unchanged), containers/data stores (none new), actor-to-surface access relationships (unchanged: the relay is host-to-host). The coordinator's rendered description ("proxy over one-way-TLS private net") stays true. Derived counts embedded in edge prose are untouched (no `.c4` file changes), so `c4-count-parity` needs no run; if the read finds a falsified element description, the `.c4` edit and the C4 test suites become in-scope.

### Sequencing
Authored now describing the target state; status `accepted` (the decision is in force at merge). The deployed signed-hello round trip between the two hosts is the PR B serve-flip precondition (CPO), not an ADR gate.

## Domain Review

**Domains relevant:** Engineering, Product (sign-off only), Operations (rollout runbook)

### Engineering
**Status:** reviewed
**Assessment:** CTO agent ruled F1-F4 (decision-challenges.md). The 2026-11-08 ruling on #12289 stands. Evidence-based amendments recorded: dedicated counter instead of a LUKS-set edit; presence gate in the existing release job; no `ci-deploy.sh` edit; reject-when-full replay cache.

### Product
**Status:** reviewed (sign-off only; no UI, no user-visible copy)
**Assessment:** CPO signed off for `single-user incident` (F5). Conditions carried into the plan: reject before membership lookup; 60 s replay window stated; refusal wording uniform; the stagger and stopped-relay symptoms named in User-Brand Impact. No Product/UX gate: the mechanical UI-surface override finds no `components/**`, `app/**/page.tsx` or `layout.tsx` path in the file lists.

### Operations
**Status:** reviewed by plan
**Assessment:** the rollout is a runbook note plus owner-gated acts (below). Legal: no new processing activity and no new regulated-data surface (ids already cross this link today; Sentry extras carry enums and counts only, never ids or hello fields), so `soleur:gdpr-gate` does not fire; CLO not consulted.

## Owner-Gated Acts (named by the owner; never agent steps)

The merge, the release (`web-platform-release.yml` fires from the merge; a dispatch is the same gate), any apply dispatch, any Doppler write, `flip.sh`, and `cf-lb-overlay` dispatches are performed only on the owner's named command, in the owner's own session, after `agent_sessions_live=0` is read on both hosts (two reporter rows per host at least 90 s apart, newest under 2 minutes old). Agents prepare, read and wait. The plan's phases contain none of these as steps.

## Implementation Phases

Conventions for every phase: **tests first** — write the test, run it against the unmodified tree, capture the RED output to `/var/tmp/relay-a-red-<phase>.log`, then implement to GREEN; **mutate every guard the phase adds** on a sandbox copy in the same commit (`SBX=$(bash scripts/soleur-sandbox.sh new relay-a-<phase> --link-node-modules)`; run the control (unmutated) suite green first in the sandbox; apply the mutant by a scripted edit; **assert the mutation landed** (`grep -c`/`diff` against the live file must show the edit) before trusting a RED; run via `bash scripts/soleur-sandbox.sh run-isolated "$SBX" -- <cmd>`; `bash scripts/soleur-sandbox.sh rm "$SBX"` after). Any "equivalent mutant" claim carries the enumerated input shapes beside it (the Guard Contract rows below name them). No secrets on command lines or in output; synthesize keys at test time with `crypto.randomBytes(32).toString("hex")` (`cq-test-fixtures-synthesized-only`); scratch and logs under `/var/tmp`; never `git stash`.

### Phase 0 — Baseline and spike (no commit)
- 0.1 Control run, record counts: `cd apps/web-platform && npx vitest run test/session-proxy.test.ts test/proxy-tls.test.ts test/proxy-listener-status.test.ts test/ws-handler-proxied-attach.test.ts test/server-index-boot-pin-line.test.ts`; `bash tests/scripts/test-destroy-guard-counter-web-platform.sh` (expect 121 assertions, floor 121); `bun test plugins/soleur/test/terraform-target-parity.test.ts`.
- 0.2 Re-run `/var/tmp/relay-spike/spike.mjs` under Node 22 to confirm the pre-TLS destroy shape before writing Phase 2.

### Phase 1 — Bounded deny reporter (`server/proxy-deny-report.ts`, leaf) — commit 1
Tests first (`test/proxy-deny-report.test.ts`, fake timers): per reason, the first 5 denies in a 60 s tumbling window call `reportSilentFallback`; denies 6..N only increment the counter; when a window that had suppressions ends (unref'd timer) exactly one summary event carries `{reason, denied, suppressed}`; `recordAccepted()` increments an accepted counter; when a window ends with accepted+denied above zero, exactly one closed-grammar warn pino line `relay_hello_window accepted=<n> denied=<n> suppressed=<n>` is emitted (counts only; it starts with `relay_hello_window`, so it matches none of the `relay_probe proxy_state=` / `relay_peer_probe peer=` alert filters) - this is the positive off-host signal for a signed round trip that the serve-gate probe cannot give (it sends no hello); a second reason has its own bucket; pino lines are bounded the same way; extras contain only enums, counts and (for `peer`) the peer address; hello fields never appear. Implement `createDenyReporter({maxEvents=5, windowMs=60_000, report=reportSilentFallback, now})` and a module default plus `__resetDenyReporterForTests`. Reason enum: `peer | size | shape | mac | skew | replay | full | membership | no_key`. Injectable: `createDenyReporter({ now, setTimer })` so reporter tests control time; real-socket tests call `__resetDenyReporterForTests()` in `beforeEach` (the module singleton must not leak between cases) and never use fake timers; the window starts at the first event of that reason. Unauthenticated reasons (`peer|size|shape|mac|skew|replay|full|no_key`) carry only the enum (plus `peer` for the peer deny); a behavioural `it.each` floods EACH reason through the real handlers and asserts at most 5 reports each and no hello-derived byte in any report (replaces a source scan).

### Phase 2 — #12288 pre-TLS admission — commit 2
Tests first (`test/session-proxy-admission.test.ts`, real sockets, synthesized self-signed cert as in `proxy-listener-status.test.ts`): (a) allowlisted loopback peer completes TLS and the upgrade; (b) a non-allowlisted peer (allowlist set to a different IP) gets `ECONNRESET`, the https server's `secureConnection` count is 0 and no HTTP upgrade bytes are read; (c) a REAL unconnected `net.Socket` whose `remoteAddress` is overridden to `undefined` via `Object.defineProperty`, emitted through `server.emit("connection", sock)`, is destroyed (deny, never allow) - a plain object would throw inside Node's TLS wrapper listener, which still runs after the destroy; (d) IPv4-mapped (`::ffff:10.0.1.9`) matches a plain-IPv4 allowlist; (e) a flood of 200 denied connects produces exactly 5 reporter calls for `peer` and a counter of 200; (f) an allowlisted peer that sends no hello is NOT closed within 1.2 s (pins the 700 ms `ok` probe contract); (g) `relay_probe` lines still match the closed grammar and `proxy_state` stays `listening`. Cost control (test-design): the self-signed cert is generated ONCE per file in `beforeAll` through a shared `test/helpers/proxy-test-tls.ts` (the existing suite spawns `openssl` in every `beforeEach`), and the 200-connect flood runs over loopback with raw `net.connect` (no TLS client), so it stays well under a second. Implement `httpsServer.prependListener("connection", function admitProxyPeer(...) {...})` (named, so a structural row can assert `server.listeners("connection")[0].name === "admitProxyPeer"`) using `normalizeProxyPeerAddress` + `peerAllowlist`; keep the in-`wss` check as defence in depth (same predicate, shared function); deny -> `socket.destroy()` + `denyReporter.record("peer", {peer})`. Add the source comment tying the no-deadline decision to the probe.

### Phase 3 — Hello protocol module and key isolation — commit 3
Tests first: `test/proxy-hello.test.ts` (pure, injected `now`; skew and replay-expiry rows live HERE, not in the real-socket files, so no fake timers and no clock seam on `createProxyServer`): known-answer vector computed in the test by hand-assembling `"soleur-proxy-hello-v1\n"+userId+"\n"+workspaceId+"\n"+ts+"\n"+nonce` and `createHmac("sha256", Buffer.from(keyHex,"hex"))` (independent of the module's builder); sign/verify round trip; every shape rule (strict lowercase UUID pair, `ts` `^[1-9][0-9]{9}$` (no leading-zero aliases of one instant; valid until 2286), nonce `^[0-9a-f]{32}$`, mac `^[0-9a-f]{64}$`, exactly the six keys, `type === "proxy_hello"`); size cap on the raw frame's Buffer byte length (1024) checked before any string conversion or `JSON.parse`; text frames only (`isBinary === false`); the parsed value must be a non-null, non-array plain object with exactly the six own keys; skew boundaries (+-30 s accepted, 31 s rejected; future and past); replay cache semantics (insert only after MAC and ts pass; each entry expires at `ts + SKEW_S + 1` seconds, i.e. exactly when that hello can no longer pass the skew check, NOT 60 s after receipt - a hello with `ts = T+30` accepted at T stays skew-valid until T+60, so a receipt-based 60 s TTL would purge it at the boundary; `ts` is compared against `Math.floor(now/1000)`; purge then test full; reject when full of unexpired entries, never evict). Boundary rows: replay at `ts+SKEW_S` refused, at `ts+SKEW_S+1` the skew check (not the cache) refuses it, a fresh nonce is accepted once expired entries are purged. `test/proxy-hello-key-isolation.test.ts`: `PROXY_HELLO_HMAC_KEY` is in `SENSITIVE_KEY_NAMES`/`SENSITIVE_LOWER`/`REDACT_PATHS` (also redacted by the Sentry scrubber on an `extra` object), absent from `ALLOWED_SERVICE_ENV_VARS`, absent from `buildAgentEnv()` output when set in `process.env`, and the string appears in no `server/agent-env.ts`/`providers.ts` source line. Read-only check recorded in the ADR-323 consequences: whether the agent sandbox can read the parent's `/proc/<pid>/environ` (`git grep -n "unshare-pid\|--proc" apps/web-platform/server/agent-runner-sandbox-config.ts`); if not provable, it goes in the residuals issue (deleting the key from `process.env` would not help, the original environment block stays in `/proc`). `proxy-tls.test.ts`: `loadProxyHelloKey()` returns a 32-byte Buffer only for `^[0-9a-f]{64}$`, `null` for absent, empty, 63/65 chars, uppercase, whitespace-padded, and reports state `absent | invalid | ok`. Implement `server/proxy-hello.ts` (leaf: constants, `buildHelloMacInput`, `signProxyHello`, `verifyProxyHello`, `createReplayCache`; `timingSafeEqual` on equal-length buffers after the shape gate; a test mocks `node:crypto` with a pass-through spy on `timingSafeEqual` and asserts it was called with two 32-byte Buffers for both a valid and an invalid MAC), `loadProxyHelloKey` in `proxy-tls.ts` (read per call from `process.env`, not cached, not deleted), and the `sensitive-keys.ts` entry with a comment (same pattern as `PROXY_TLS_KEY`).

### Phase 4 — Wire the verifier and the sender — commit 4
Tests first (`test/session-proxy-hello.test.ts`, real sockets + injected `onProxiedSession`; `verifyProxiedSessionMembership` mocked with a spy): valid signed hello -> `proxy_ready` then `onProxiedSession`; each of {missing mac, bad mac, wrong key, tampered userId, tampered workspaceId, swapped ids, old-shape hello without ts/nonce/mac, extra key, oversized frame (valid hello padded with whitespace to 2 KiB), non-UUID ids, skew +31 s, replayed nonce, cache full} -> close `ROUTING_UNAVAILABLE` reason `relay refused`, **membership spy never called**, `onProxiedSession` never called, bounded report with the right reason; AP-2 deny after a valid MAC still refuses (existing behaviour) via the bounded reporter; key absent/invalid with TLS+bind+allowlist set -> `createProxyServer` returns null, `getProxyStatus().state === "error"`, one `createProxyServer.no-hello-key` event, the host's app untouched; TLS absent (dev/CI) -> `disabled`, no Sentry; empty `SOLEUR_PROXY_BIND` (canary) -> still `no_bind`; allowlist unset -> still `no_allowlist`. The `no-hello-key` error text is a constant carrying no value, length or state. A full cache refuses with reason `full` (its own bounded event) so a mass reconnect after an owner restart is distinguishable from a replay. Phase 4 rows are an `it.each` with one distinct name per rejection class. Sender (`session-proxy.test.ts` rewritten fixtures with synthesized UUIDs): `owner.on("open")` sends a hello whose MAC verifies under the same key; key absent/invalid or non-canonical ids -> client closed `ROUTING_UNAVAILABLE`, `dial` never called, bounded `proxyClientToOwner.no-hello-key`; two sends differ in nonce. Rolling-deploy case in the suite: an old-shape hello (no ts/nonce/mac) refused by the new verifier with reason `shape`. Existing `proxy-listener-status.test.ts` cases that expect `listening` get the key stubbed in `beforeEach`; the key check sits **after** the tls/bind/allowlist checks so the `no_bind`/`no_allowlist`/`error` assertions keep their meaning. The replay check-and-insert runs synchronously **before** the `await verifyProxiedSessionMembership(...)` (the handler is an async `ws.once("message")`), and a concurrency row sends two hellos with the same nonce in the same tick and expects exactly one `proxy_ready`. The AP-2 deny keeps its `userId`/`workspaceId` extras (the pair is MAC-authenticated at that point; the unauthenticated classes never carry ids); grep the existing tests for the `ap2-deny` extras at work time. Rolling-deploy evidence for "new sender -> old receiver": the CHARACTERISATION is a one-time verification, not a committed test — in a sandbox, extract the pre-PR `createProxyServer` with `git show origin/main:apps/web-platform/server/session-proxy.ts`, drive it with a real new-shape hello, and record the observed `proxy_ready` in the ADR-323 consequences and the phase commit message (a committed stub parser would test only itself). Implement in `session-proxy.ts` per the check order allowlist -> cap -> shape (UUID, nonce, mac, ts digits) -> MAC -> ts -> replay -> AP-2; the sender signs with `signProxyHello` using the shared module.

### Phase 5 — #12290 port parse and guarded listen — commit 5
Tests first (extend `proxy-listener-status.test.ts`): `resolveProxyPort` accepts `"8443"`, `""`/unset (default 8443), `"1"`, `"65535"`; rejects `"abc"`, `"0"`, `"65536"`, `"-1"`, `"8443.5"`, `"0x20fb"`, `"1e3"`, `" 8443"`, `"8443 "`, `"99999999999"`; `params.port` of `NaN`, `-1`, `70000`, `1.5` makes `createProxyServer` return null without throwing, `getProxyStatus().state === "error"`, one `createProxyServer.bad-port` (or `listen-throw`) event with only the error code; the host keeps listening on the other servers (assert `index.ts` boot path: `createProxyServer` returns null and boot continues — extend `server-index-boot-pin-line.test.ts` only if its pin lines move); `port: 0` (ephemeral) stays valid via the param seam. A thrown `listen()` (seam: `vi.spyOn(Server.prototype, "listen")` with `Server` from `node:net`, since `createProxyServer` builds the https server internally; a second spy on `close`) is caught: `close` is called once, `recordProxyNotStarted("error")`, reported, `null`. Sender: invalid port -> bounded `proxyClientToOwner.bad-port` + client closed `ROUTING_UNAVAILABLE`, no `new WebSocket`. Implement; delete the `PROXY_LISTEN_PORT` module-load constant (no importer outside `session-proxy.ts`, verified by `git grep`) and call `resolveProxyPort()` at both use sites, so a `NaN` can never re-enter as a default.

### Phase 6 — Destroy-guard no-ack counter (F1) — commit 6
Files derived by `git grep -n "luks_passphrase_rotations\|luks_passphrase_addrs" -- . ':!knowledge-base/project'` at work time (not from this list alone). Tests first in `tests/scripts/test-destroy-guard-counter-web-platform.sh` with new fixtures `tests/scripts/fixtures/tfplan-proxy-hello-*.json` (built from the existing rotation fixtures' shapes, addresses `random_bytes.proxy_hello_hmac[0]` / `doppler_secret.proxy_hello_hmac_key[0]`): replace halts (2 counted), `[ack-destroy]` cannot bypass, forget halts, CREATE of `random_bytes` halts, lone CREATE of the secret reads 0, no-op reads 0 (the per-merge shape after A-0), update-only on the secret halts, indexed and module-prefixed forms count, near-name decoys (`tls_private_key.proxy_server`, `doppler_secret.proxy_tls_key`, `doppler_secret.proxy_tls_cert`, `random_bytes.other`) read 0, undecidable `actions: []` at the pair counts, per-address removal mutants, normalization-removal mutant, create-list removal mutant, executed-HALT segment of the real workflow step. Implement `relay_hello_key_addrs`, `relay_hello_key_create_halt_addrs` and `relay_hello_key_changes` in the `.jq` (through `luks_passphrase_base`), the `apply` job read + numeric validation + non-ackable HALT (before the `destroy_count` sum, `exit 1`, `[skip-web-platform-apply]` UNWEDGE text, remediation text that names a relay outage and the `_PREVIOUS` pattern, no LUKS wording) in `.github/workflows/apply-web-platform-infra.yml`, and extend `plugins/soleur/test/terraform-target-parity.test.ts` in lock-step (COUNTERS / READS / the closed-sequence allow-list, a structural pin for the new HALT, and a job-reach row: the pair is `-target`ed by `apply` and by no other job or workflow, mirroring the #9377 web-pair rows). The new HALT block carries its own diagnostic `grep -F -e random_bytes.proxy_hello_hmac -e doppler_secret.proxy_hello_hmac_key -e 'Plan:' tfplan.txt >&2 || true`; the LUKS block's `grep` line and the parity test's `GREP_RE {6}` stay untouched. Update the `.jq` comment that says `luks_passphrase_base` is "Used ONLY by luks_passphrase_rotations" (keep the helper's name: `test-destroy-guard-counter-web-platform.sh` seds the LUKS text), update the `.jq` header counter list, and update `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md`. Rows (ids fixed here; EACH id is exactly one `_report` call, with sub-cases aggregated into one detail string as T64e/T64h already do, so the floor is derivable): T66a replace halts (2 counted); T66b `[ack-destroy]` cannot bypass; T66c forget halts; T66d CREATE of `random_bytes` halts; T66e lone CREATE of the secret reads 0; T66f no-op pair reads 0; T66g update-only on the secret halts; T66h indexed and module-prefixed forms counted; T66i decoy neighbours read 0; T66j undecidable `actions: []` counts; T66k mutant: remove `random_bytes` address; T66l mutant: remove `doppler_secret` address; T66m mutant: drop normalization; T66n mutant: remove `random_bytes` from the create-halt list; T66o executed-HALT segment of the real workflow step. Exact floor: see Acceptance Criteria.

### Phase 7 — Release-time presence gate (F2) — commit 7
Tests first (new `apps/web-platform/scripts/verify-required-secrets.test.sh` — that glob is auto-registered by `scripts/test-all.sh`, so no `ci.yml` edit; patterned on `service-role-allowlist-gate.test.sh`). Every row runs the script under `env -i` with an explicit synthesized environment; V1 must also supply valid synthesized `NEXT_PUBLIC_SUPABASE_URL` / `NEXT_PUBLIC_SUPABASE_ANON_KEY` / `GITHUB_CLIENT_ID` values because the script shape-checks them. Rows (ids fixed): V1 all required present incl. the key -> pass; V2 key missing -> fail naming only the key name; V3 key empty -> fail; V4 a synthesized sentinel value never appears in stdout/stderr; V5 xtrace refusal (rc 78) still holds; V6 suite-level mutant: removing the `REQUIRED` entry is caught by V2. Implement: add `PROXY_HELLO_HMAC_KEY` to `REQUIRED` with a comment (#12289; remove together with `host_proxy_tls_enabled`). Presence only, as ruled in F2 (the 64-hex shape is checked by the app startup guard; the Terraform-minted value cannot be malformed without an owner write). No workflow edit (`verify-doppler-secrets` already runs the script and gates `deploy`). Add one parity-test row in `plugins/soleur/test/terraform-target-parity.test.ts`: `REQUIRED` lists `PROXY_HELLO_HMAC_KEY` iff `host_proxy_tls_enabled` defaults true in `variables.tf`. Coupling accepted by the CTO: a missing key blocks every deploy, including hotfixes, until it exists.

### Phase 8 — Records and runbooks — commit 8
- ADR-323 (new), ADR-068 and ADR-118 amendments. C4: read all three `.c4` files and record the enumerated "no C4 impact" conclusion in the ADR (no `.c4` edit; see Architecture Decision).
- A new section "Signed hello rollout (#12289)" inside `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` (the relay runbook; no new file): the check order and wire format summary; the rolling-deploy note (new sender -> old receiver works because extra hello fields are ignored; old sender -> new receiver is refused for the stagger, a few minutes; users on the lagging host see 4014 and the generic reconnect loop; live users are 0; the release is named by the owner only after `agent_sessions_live=0` is read on both hosts, and the merge is the release trigger); the `agent_sessions_live` read; what a refused hello looks like in Sentry (`createProxyServer.*` ops with `reason`) and Better Stack; the key-absent symptom (`proxy_state=error`, `relay_listener_down` after ~5 minutes) and its first-host catch; the no-rotation rule (after A a replace is an outage; the HALT blocks it; `_PREVIOUS` is the future pattern); `denied` now reads `tls` (the discriminator between a cert fault and an allowlist deny is the receiver-side bounded `peer` Sentry event); the clock assumption (+-30 s needs NTP on both hosts; what `reason=skew` means); the `relay_hello_window accepted=<n> denied=<n> suppressed=<n>` line and how to read it (an `accepted>0` row on the owner host is the positive round-trip signal); the per-process replay cache is cleared by a container restart for up to 60 s; rolling back to a pre-PR image re-opens unsigned hellos until the roll-forward.
- Update the `denied` definition in the same runbook's peer-line bullet.
- Tracking issue (one `gh issue create`, label per repo convention, milestone from `knowledge-base/product/roadmap.md`) for the named residuals: idle/slow allowlisted peers, first-frame buffering up to the `ws` default `maxPayload`, a captured hello replayable to a different roster host inside 60 s (MAC does not bind the target host), the deployed signed-hello round-trip evidence needed before the serve flip (PR B), the response procedure for a leaked hello key (no rotation route exists: HALT blocks replace, `_PREVIOUS` is cut), and the owner/route for retiring the relay (`host_proxy_tls_enabled` false is closed on the per-merge path).

## Files to Edit
- `apps/web-platform/server/session-proxy.ts` — pre-TLS admission, hello verify, sender signing, port parse, listen guard, key guard.
- `apps/web-platform/server/proxy-tls.ts` — `loadProxyHelloKey`.
- `apps/web-platform/server/sensitive-keys.ts` — `PROXY_HELLO_HMAC_KEY`.
- `apps/web-platform/test/session-proxy.test.ts`, `proxy-tls.test.ts`, `proxy-listener-status.test.ts` (key stub, port cases), possibly `ws-handler-proxied-attach.test.ts` and `server-index-boot-pin-line.test.ts` if fixtures or pin lines move.
- `apps/web-platform/scripts/verify-required-secrets.sh`
- `tests/scripts/lib/destroy-guard-filter-web-platform.jq`, `tests/scripts/test-destroy-guard-counter-web-platform.sh` (rows + floor + header comment)
- `.github/workflows/apply-web-platform-infra.yml` (read, validation, new HALT with its own diagnostic grep; the LUKS HALT is untouched)
- `plugins/soleur/test/terraform-target-parity.test.ts`
- `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md`, `betterstack-log-query.md` (includes the new rollout section)
- `knowledge-base/engineering/architecture/decisions/ADR-068-...md`, `ADR-118-...md`

## Files to Create
- `apps/web-platform/server/proxy-deny-report.ts`, `apps/web-platform/server/proxy-hello.ts`
- `apps/web-platform/test/helpers/proxy-test-tls.ts` (cert generated once per file)
- `apps/web-platform/test/proxy-deny-report.test.ts`, `proxy-hello.test.ts`, `proxy-hello-key-isolation.test.ts`, `session-proxy-admission.test.ts`, `session-proxy-hello.test.ts`
- `apps/web-platform/scripts/verify-required-secrets.test.sh`
- `tests/scripts/fixtures/tfplan-proxy-hello-*.json` (names per the row list in Phase 6)
- `knowledge-base/engineering/architecture/decisions/ADR-323-<slug>.md` (provisional ordinal)

Files deliberately NOT touched: `apps/web-platform/infra/ci-deploy.sh` (F3), `apps/web-platform/infra/betterstack-logs-alerts.tf`, `apps/web-platform/infra/proxy-hello-hmac.tf` (a comment edit there would pull in the Encryption Posture gate and the terraform-target-parity header pins), `server/agent-env.ts`, `server/providers.ts`, `.github/workflows/web-platform-release.yml`.

## Observability

```yaml
liveness_signal:
  what: "relay_probe proxy_state=<listening|disabled|no_bind|no_allowlist|error> addr=<ip|none> port=<n> workspaces_populated=<0|1> (warn-level pino line, one per minute per host; grammar unchanged). A missing/invalid hello key or a bad port reads proxy_state=error."
  cadence: "60s per host"
  alert_target: "relay_listener_down (4+ non-listening rows in 300s), relay_probe_silent (host silent 10 min), relay_peer_probe_failed (first deploy-time refused|timeout|tls|denied) -> team email"
  configured_in: "apps/web-platform/infra/betterstack-logs-alerts.tf (unchanged); apps/web-platform/server/proxy-listener-status.ts (unchanged)"
error_reporting:
  destination: "Sentry via reportSilentFallback, feature control_plane_route; ops createProxyServer.no-hello-key, createProxyServer.bad-port, createProxyServer.listen-throw, proxyClientToOwner.no-hello-key, proxyClientToOwner.bad-port, plus bounded deny ops createProxyServer.peer-deny / hello-deny with a reason enum"
  fail_loud: "startup guards stop only the relay and set proxy_state=error; denies are bounded to 5 events per reason per 60 s with a counter and one summary event per suppressed window, so a flood cannot hide the signal or drown the project"
failure_modes:
  - mode: "hello key absent or not 64 lowercase hex while relay TLS is enabled"
    detection: "createProxyServer.no-hello-key Sentry event from the app container on the first host that starts (the deploy still completes because the app serves; nothing halts the fan-out to the second host automatically) + relay_probe proxy_state=error; release blocked earlier by verify-required-secrets.sh in the verify-doppler-secrets job"
    alert_route: "release job fails loudly; relay_listener_down email after ~5 minutes if it ships anyway"
  - mode: "non-allowlisted private-net source connecting"
    detection: "bounded createProxyServer.peer-deny events (reason peer) with a per-window counter in the summary event"
    alert_route: "Sentry issue; no page"
  - mode: "forged, unsigned, stale or replayed hello from an allowlisted peer"
    detection: "bounded hello-deny events with reason size|shape|mac|skew|replay; close reason is uniform so the peer learns nothing"
    alert_route: "Sentry issue; a sustained reason=mac stream after a deploy means a key split between hosts"
  - mode: "bad SOLEUR_PROXY_PORT"
    detection: "createProxyServer.bad-port / listen-throw event + proxy_state=error"
    alert_route: "relay_listener_down"
  - mode: "valid hellos rejected (verifier bug) while the serve-gate probe stays ok"
    detection: "the probe sends no hello, so it cannot see this; the relay_hello_window accepted/denied counts per minute and reason=mac/shape bounded events from a real proxied session are the signal"
    alert_route: "Sentry issue; PR B's deployed round-trip check owns the positive proof"
logs:
  where: "app container pino (Better Stack) for relay_probe; Sentry for the events above"
  retention: "Better Stack tier retention; Sentry project retention"
discoverability_test:
  command: "bash scripts/betterstack-query.sh --since 10m --grep 'relay_probe proxy_state='"
  expected_output: "proxy_state=listening"
  credentials_required: "Better Stack read credentials from Doppler prd_terraform — a deployed host's log row has no unauthenticated substitute"
```

Affected-surface note (blind execution surface): the verifier runs inside the owner's app container, which is not directly inspectable; every rejection class emits an in-process event carrying the discriminating `reason` enum, so one event separates "key split" (mac), "clock skew" (skew), "old sender" (shape) and "capture/replay" (replay).

## Guard Contract

### Guard 1 — Pre-TLS peer admission

**Property.** No TLS handshake starts for a TCP connection whose normalized `remoteAddress` is absent or not in `SOLEUR_PROXY_PEER_ALLOWLIST`.

**Assembly.** The chokepoint is the https server's raw `connection` event (every accepted TCP stream passes it exactly once before Node's TLS wrapper reads a byte); the listener is registered with `prependListener` on the same server object that `proxy-listener-status.ts` records. Second line: the `wss.on("connection")` re-check shares the predicate. Both read the predicate from one function; there is no other accept path (no second listener, no `noServer` upgrade route).

**Mutation matrix.**

| # | Mutation | Must go RED because |
|---|----------|---------------------|
| 1 | remove `socket.destroy()` (log only) | denied peer completes TLS: `secureConnection` count 1 |
| 2 | invert the predicate (deny allowlisted) | allowlisted peer test (a) fails |
| 3 | treat `undefined` remoteAddress as allowed | fake-socket row (c) is not destroyed |
| 4 | drop `normalizeProxyPeerAddress` | IPv4-mapped row (d) denied |
| 5 | register after the TLS listener (append, not prepend) | EQUIVALENT in observable terms — enumerated input shapes: allowlisted peer, non-allowlisted peer, `undefined` remoteAddress, IPv4-mapped, burst of 200: in all five the destroy runs in the same tick before any ClientHello read, so `secureConnection`, client events and `tlsClientError` counts are identical; pinned structurally by `server.listeners("connection")[0].name === "admitProxyPeer"` (RED if appended) |
| 6 | remove the in-`wss` re-check | EQUIVALENT — enumerated shapes: `remoteAddress` is fixed at accept and `server.emit("connection", fake)` passes the pre-TLS listener first, so no input reaches `wss` with a denied peer; kept as defence in depth |

**Harness rows.** Edit the suite so the denied-peer connect uses the allowlisted address -> row (b) must go RED (the suite can see a no-op test). Must-PASS non-canonical input: an allowlisted peer connecting via the IPv4-mapped spelling, and a second allowlisted peer from the CSV's trailing-space entry.

**Anchor.** The allowlist value comes from the container env set by the owner-class Doppler write (`SOLEUR_PROXY_PEER_ALLOWLIST`) and the roster in Terraform state; `lb-weight-gate.sh` already parses the same string with the same parser. A weakening needs a Doppler write the owner names.

### Guard 2 — Bounded deny reporter

**Property.** For any number of denies in a window, at most 5 Sentry events per reason are emitted, the counter is exact, and a suppressed window yields exactly one summary event.

**Assembly.** Every deny site routes through the one `record(reason, extra)` function: pre-TLS peer deny, in-`wss` peer re-check, every hello rejection class, AP-2 deny, key/port guards on the sender. Chokepoint: no production call site calls `reportSilentFallback` for a per-connection deny directly; proven behaviourally by the per-reason flood `it.each` through the real handlers (at most 5 reports per reason), not by a source scan.

**Mutation matrix.**

| # | Mutation | Must go RED because |
|---|----------|---------------------|
| 1 | remove the cap (always report) | flood row: 200 denies produce 200 reports |
| 2 | cap off by one (6) | exact-5 assertion |
| 3 | window never rolls | after 61 s the next deny must report again |
| 4 | one global bucket instead of per-reason | second reason after the first reason's cap is starved (second member after a compliant first) |
| 5 | counter increments only when reporting | counter equals denied total (200), not 5 |
| 6 | summary omits `suppressed` | summary-shape row |
| 7 | one reason's handler bypasses the reporter (direct `reportSilentFallback`) | that reason's flood row sees more than 5 reports |

**Harness rows.** Edit the suite to assert 6 reports for a 6-deny burst -> must go RED against the correct implementation; must-PASS: a burst of exactly 5 (no summary emitted) and a burst of 5 followed by a quiet window.

**Anchor.** The cap and window are constants in the module; a weakening is a code diff reviewed in the PR; the source-scan row pins that no deny site bypasses the reporter.

### Guard 3 — Signed-hello verification (MAC, shape, size, order)

**Property.** `onProxiedSession` and the AP-2 membership lookup run only for a hello that passed size, shape and constant-time MAC checks under the loaded key.

**Assembly.** The single verifier function `verifyProxyHello` (called from the one owner message handler), the single canonical-string builder shared with the sender, and the single key loader. Check order is enforced by call sequence in one function; the membership spy proves no earlier reject reaches it.

**Mutation matrix.**

| # | Mutation | Must go RED because |
|---|----------|---------------------|
| 1 | skip the MAC compare (return ok after shape) | bad-mac / wrong-key / tampered-id rows attach a session |
| 2 | swap `userId` and `workspaceId` in the builder | known-answer vector (computed independently in the test) fails |
| 3 | drop the domain prefix | known-answer vector fails |
| 4 | drop the size cap | the whitespace-padded 2 KiB otherwise-valid hello is accepted |
| 5 | accept a case-insensitive UUID | uppercase-id row |
| 6 | run membership before MAC | membership spy called on a bad-MAC hello |
| 7 | compare with `===`/`Buffer.compare` instead of `timingSafeEqual` | the `node:crypto` pass-through spy is never called (outcomes are identical for equal / one-byte-different MACs, so the spy, not the verdict, is what goes RED; wrong-length and empty MACs are shape-gated before the compare) |
| 8 | accept an extra key in the hello | extra-key row (strict six-key shape) |
| 9 | accept a text-or-binary frame / accept a non-plain-object (array, null) | binary-frame and array-JSON rows |

**Harness rows.** Edit the suite's sign helper to use a different key than the server's -> the valid-hello row must go RED; must-PASS non-canonical: a second valid UUID pair, `ts` at -29 s and +29 s, a hello signed under a freshly generated second key with that key loaded on both sides.

**Anchor.** The key's integrity is anchored outside the commit: Doppler `prd` (owner-written, A-0) and the release-time presence/shape gate; the known-answer vector is computed by hand-assembling the spec string, not from the module under test.

### Guard 4 — Timestamp skew

**Property.** A hello whose `ts` differs from the owner's clock by more than 30 s in either direction is refused.

**Assembly.** The single comparison in `verifyProxyHello`, fed by one injected clock; seconds only (the unit is part of the wire format).

**Mutation matrix.**

| # | Mutation | Must go RED because |
|---|----------|---------------------|
| 1 | remove the skew check | +31 s and -31 s rows |
| 2 | drop `Math.abs` (past-only) | future-skew row |
| 3 | boundary `<` vs `<=` flipped | exactly +-30 s row (accepted) and 31 s (refused) |
| 4 | treat `ts` as milliseconds | every valid hello refused (round-trip row) |

**Harness rows.** Edit the suite's fake clock to a fixed value ignoring `advance` -> replay-window row must go RED; must-PASS: ts at -30 s and +30 s.

**Anchor.** The constants are code; the clock is injected only in tests (production passes `Date.now`).

### Guard 5 — Replay cache

**Property.** A nonce that passed MAC and skew is refused for 60 s, the cache never exceeds 4096 live entries, and forged hellos can neither fill it nor evict a live entry.

**Assembly.** The one `createReplayCache` instance per server, the insert call site (after MAC and ts only), the purge-then-full-test sequence.

**Mutation matrix.**

| # | Mutation | Must go RED because |
|---|----------|---------------------|
| 1 | no replay check | same hello twice is accepted twice |
| 2 | insert before MAC verification | 5000 bad-MAC hellos then a valid one: the valid one refused |
| 3 | evict-oldest when full | 4097th valid hello accepted and the first becomes replayable |
| 4 | no purge of expired entries | after 61 s a fresh nonce is refused because the cache looks full |
| 5 | expiry shortened to 30 s from `ts` | a future-dated `ts = T+30` hello accepted at T and replayed at T+35 is accepted (a replay at +45 s would be refused by the skew check anyway, so it cannot discriminate) |
| 6 | key by `userId` instead of nonce | two valid hellos from one user (different nonces) wrongly refused |
| 7 | insert into the cache after the `await` on membership | same-tick duplicate-nonce row: both hellos get `proxy_ready` |
| 8 | receipt-based TTL (60 s from insertion) | boundary row: a `ts = T+30` hello accepted at T replays successfully at T+60 |

**Harness rows.** Edit the suite to skip advancing the clock past the TTL -> the purge row must go RED; must-PASS: a nonce reused after 61 s (accepted again, it is a new valid hello), 4096 distinct live nonces all accepted.

**Anchor.** Bounds are constants asserted by the tests (expiry is derived from `ts`, so the cache cannot outlive or undercut the skew window); fail-closed when full is the property, so a weakening changes an asserted test row.

### Guard 6 — Hello key startup guard (owner) and sender refusal

**Property.** With relay TLS enabled and a bind and allowlist present, an absent or non-64-lowercase-hex key yields no listener, `proxy_state=error` and one `createProxyServer.no-hello-key` event; without TLS the relay is `disabled` with no event; the sender with such a key never dials.

**Assembly.** `loadProxyHelloKey` (the only reader of the env name), the owner check placed after tls/bind/allowlist, the sender's pre-dial check.

**Mutation matrix.**

| # | Mutation | Must go RED because |
|---|----------|---------------------|
| 1 | skip the key check (listen anyway) | server returned non-null / state `listening` |
| 2 | accept 63 hex | 63-char row |
| 3 | accept uppercase hex | uppercase row |
| 4 | record `disabled` instead of `error` | state assertion |
| 5 | move the check before the bind check | canary row: empty bind must still read `no_bind` |
| 6 | sender dials with an unsigned hello when the key is absent | `dial` spy called |
| 7 | fail closed when TLS is absent (dev) | dev row: `disabled`, no Sentry |

**Harness rows.** Edit the suite to stub the key as valid in the "absent" row -> must go RED; must-PASS: a 64-hex key with `0-9a-f` only, a different random valid key per run.

**Anchor.** The release-time gate (Guard 10) is the out-of-commit anchor for presence and shape in prd.

### Guard 7 — Strict port parse and guarded listen (#12290)

**Property.** No value of `SOLEUR_PROXY_PORT` or `params.port` can make `createProxyServer` throw; an invalid one yields `null`, `proxy_state=error` and a Sentry event.

**Assembly.** `resolveProxyPort` (env path) and the try/catch around `httpsServer.listen` (any synchronous throw, including from a validated-looking port); the sender's use of the same parser.

**Mutation matrix.**

| # | Mutation | Must go RED because |
|---|----------|---------------------|
| 1 | remove the try/catch around `listen` | stubbed throwing `listen` escapes |
| 2 | remove the parse (use `Number(...)`) | `"0x20fb"`, `"1e3"`, `" 8443"` rows |
| 3 | accept port 0 from the env path | `"0"` row |
| 4 | skip `recordProxyNotStarted("error")` in the catch | state stays `disabled`/`listening` |
| 5 | catch but do not close the server | the `close` spy was not called once |
| 6 | sender dials with an invalid port | `new WebSocket` spy called |

**Harness rows.** Edit the suite's throwing-listen stub to not throw -> row 1 must go RED; must-PASS: `"65535"`, `"1"`, unset, `params.port: 0`.

**Anchor.** Production pins the literal `-e SOLEUR_PROXY_PORT=8443` (`lib/docker-run-tuple.py` `RELAY_PROD_ENV`, tested by `docker-run-tuple.test.sh`); a drift there is a separate existing gate.

### Guard 8 — Hello-key destroy-guard counter and HALT (F1)

**Property.** A planned update, delete, forget, unreadable action list, or create-of-`random_bytes` at the hello key pair reaches a non-ackable HALT on the per-merge apply path.

**Assembly.** The two addresses (through `luks_passphrase_base`, so `[0]` and module-prefixed spellings count), the create-halt subset, the counter in the `.jq`, the workflow read/validation/HALT in the `apply` job only, and the parity test's closed sequence + job-reach scan over every workflow file.

**Mutation matrix.**

| # | Mutation | Must go RED because |
|---|----------|---------------------|
| 1 | remove `random_bytes.proxy_hello_hmac` from the address list | its per-address removal row |
| 2 | remove `doppler_secret.proxy_hello_hmac_key` | its per-address removal row |
| 3 | drop `luks_passphrase_base` (exact-address match) | indexed-form row (`[0]`) |
| 4 | drop the `update` verb | update-only row |
| 5 | add the `doppler_secret` to the create-halt list | lone-secret-create-legal row |
| 6 | remove `random_bytes` from the create-halt list | create-halts row |
| 7 | delete the workflow `exit 1` / add an ack bypass | parity structural pin and executed-HALT row |
| 8 | drop the counter from the numeric validation line | parity test numericOk |
| 9 | add the pair to a second job's `-target` list | job-reach row |

**Harness rows.** Edit the suite so the create fixture's action becomes `["no-op"]` -> the must-HALT predicate must NOT hold (the row can fail); must-PASS: the no-op per-merge shape, a lone secret create, a decoy neighbour update.

**Anchor.** The merge-base check: the HALT's address list is read by the parity test from the `.jq` itself (one source), and the workflow text is pinned structurally; an edit that weakens both must also rewrite the parity test, which a reviewer sees in the same diff — this proves consistency, not integrity, so CODEOWNERS on `tests/scripts/lib/` and `.github/workflows/apply-web-platform-infra.yml` is the outside-the-commit anchor (confirm the rows exist; the destroy-guard convention note in the `.jq` header requires them).

### Guard 9 — Key isolation (sensitive-keys, agent env)

**Property.** `PROXY_HELLO_HMAC_KEY` is scrubbed from logs and Sentry and never forwarded to an agent subprocess or accepted as a service token name.

**Assembly.** `SENSITIVE_KEY_NAMES` (-> `SENSITIVE_LOWER`, `REDACT_PATHS`), `AGENT_ENV_ALLOWLIST` + `buildAgentEnv`, `ALLOWED_SERVICE_ENV_VARS` (derived from `PROVIDER_CONFIG`), and the sandbox deny census that derives from the latter.

**Mutation matrix.**

| # | Mutation | Must go RED because |
|---|----------|---------------------|
| 1 | remove the entry from `SENSITIVE_KEY_NAMES` | scrubber/redact-path row |
| 2 | add the name to `AGENT_ENV_ALLOWLIST` | `buildAgentEnv` output row |
| 3 | add a `PROVIDER_CONFIG` entry whose `envVar` is the name | `ALLOWED_SERVICE_ENV_VARS` row |
| 4 | add a source mention in `agent-env.ts` | source-scan row |

**Harness rows.** Edit the suite to set the env var to an empty string -> the "absent from agent env" row must still hold and the "present in process.env" precondition row must go RED (the test proves the var was really set); must-PASS: `PROXY_TLS_CERT` (public) is not redacted.

**Anchor.** The test reads the live module exports, so a weakening needs a source edit the test sees; no stored hash.

### Guard 10 — Release-time presence gate (F2)

**Property.** `verify-doppler-secrets` fails (and `deploy` is skipped) when `PROXY_HELLO_HMAC_KEY` is absent or empty in prd, without printing the value.

**Assembly.** `REQUIRED` array entry in `verify-required-secrets.sh`, the job that runs it, and `deploy`'s `needs:` (unchanged; asserted by reading the workflow in the parity row), plus the flag-coupling row (`REQUIRED` lists the key iff `host_proxy_tls_enabled` defaults true).

**Mutation matrix.**

| # | Mutation | Must go RED because |
|---|----------|---------------------|
| 1 | remove the `REQUIRED` entry | missing-key row V2 |
| 2 | make an empty value pass | empty row V3 |
| 3 | print the value on success or failure | sentinel-leak row V4 |
| 4 | drop the xtrace refusal | rc-78 row V5 |
| 5 | flip `host_proxy_tls_enabled` default to false with the entry kept | flag-coupling parity row |

**Harness rows.** Edit the suite to export the key in the "missing" row's env -> V2 must go RED if the test does not control the env; must-PASS: a valid 64-hex synthesized key plus all other required vars (V1).

**Anchor.** The Doppler prd value itself (owner-written, minted by Terraform) is what is checked at release time; the script is anchored by the job's `needs:` chain and the parity row that reads the workflow.

## Pre-push Gate List (derived from `.github/workflows/ci.yml` run steps, with each CI flag)

Re-derive at push time with `awk '/^  [a-z0-9_-]+:$/{job=$1} /^      - name:/{n=$0} /^        run: /{print job" | "substr(n,15)" | "substr($0,14,200)}' .github/workflows/ci.yml` and add any new step that scans a file class this diff touches. For this diff (`.ts`, `.sh`, `.jq`, `.yml`, `.md`, ADR; no `.c4`, no `.tf`):

1. `cd apps/web-platform && npm run lint` and `node scripts/eslint-vacuity-floor.mjs` (job `lint-webplat`).
2. `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (job `test-webplat`).
3. Targeted then full web-platform tests: `npx vitest run <the new and edited test files>`, then `bash scripts/test-all.sh webplat`.
4. `bash scripts/test-all.sh scripts` (destroy-guard suite, the new `verify-required-secrets.test.sh`) and `bash scripts/test-all.sh bun` (`terraform-target-parity.test.ts`).
5. `bash scripts/lint-orphan-test-suites.sh` (every tracked `*.test.sh` registered).
6. `python3 scripts/lint-trap-tempfile-ownership.py` **and** `python3 scripts/lint-trap-tempfile-ownership.py --check-highwater`.
7. `python3 scripts/lint-shell-trace-credential-refusal.py --changed --base origin/main` (new/edited shell that handles a credential).
8. `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` (the plan, the runbook and the ADR must pass).
9. `bash scripts/check-adr-ordinals.sh` (ordinal + content completeness).
10. `python3 scripts/lint-credential-path-literals.py`.
11. `python3 scripts/lint-guard-contract.py` over this plan file.
12. `actionlint` on `.github/workflows/apply-web-platform-infra.yml` (pinned version as in the `lint-bot-statuses` job) when installed.
Not applicable (no `.tf` touched): `lint-encryption-posture.py --repo-sweep`, terraform fmt/validate.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] RED evidence exists for every phase: `/var/tmp/relay-a-red-<phase>.log` captured before the implementation commit; the commit message of each phase states the failing-before / passing-after counts.
- [ ] A non-allowlisted source never completes a TLS handshake (`secureConnection` 0) and an allowlisted source reads `relay_peer_probe`-equivalent `ok` behaviour (TLS verified, upgrade held open >1 s without a hello).
- [ ] 200 denied connects -> exactly 5 Sentry reports for `peer` and a counter of 200; one summary event.
- [ ] Every rejection class (size, shape, mac, skew, replay, membership) refuses with close reason `relay refused`; `verifyProxiedSessionMembership` is never called for any class before `membership`.
- [ ] Known-answer vector passes (spec string assembled by hand in the test); sender and verifier share one canonical-string module.
- [ ] Key absent/invalid with TLS+bind+allowlist set -> `createProxyServer` null, `proxy_state=error`, one `createProxyServer.no-hello-key`; dev/CI without TLS -> `disabled`, no Sentry; empty bind -> `no_bind`; empty allowlist -> `no_allowlist`.
- [ ] Every port shape in Phase 5 behaves as listed; `createProxyServer` never throws for any `port`/`SOLEUR_PROXY_PORT`.
- [ ] `PROXY_HELLO_HMAC_KEY` is in `sensitive-keys.ts`, absent from `agent-env.ts`, `ALLOWED_SERVICE_ENV_VARS` and `providers.ts`; isolation test green.
- [ ] Destroy-guard suite: **exact floor 136 = 121 + 15 new `_report` rows** (ids T66a-T66o, enumerated in Phase 6: one `_report` call per id); a green run must print exactly 136 assertions before the floor is set; if it does not, the id list or the `_report` count is wrong - fix that, never the number; the header comment's tally is extended in the same edit. LUKS rows and the `{6}` GREP regex are untouched.
- [ ] `verify-required-secrets.test.sh`: **exact floor 6** (ids V1-V6, Phase 7), one `_report`-equivalent per id; a mutant of each of Guard 10's rows 1-5 is run in the sandbox.
- [ ] Every guard in the Guard Contract was mutated on a sandbox copy in its own phase commit with control green first, the mutation-landed assertion, and the enumerated shapes beside every "equivalent mutant" claim (Guards 1 and 3); results recorded in the commit messages.
- [ ] All Pre-push gate commands above exit 0 with their CI flags (including `--check-highwater`).
- [ ] ADR-323 created, ADR-068 and ADR-118 amended, C4 comment edit made after reading all three `.c4` files, runbooks updated, tracking issue filed for the F3 residuals.
- [ ] Review panel run before merge readiness: `security-sentinel`, `test-design-reviewer` (minimum), plus `architecture-strategist`, `code-simplicity-reviewer`, `observability-coverage-reviewer`, `user-impact-reviewer` (single-user-incident), `semgrep-sast` per the review skill.
- [ ] PR body (written by ship): `Closes #12288`, `Closes #12289`, `Closes #12290`, `Ref #12167`, `Ref #8211`.

### Post-merge
- [ ] **Owner-named (never agent steps):** the merge and the release, only after `agent_sessions_live=0` is read on both hosts; the release's `verify-doppler-secrets` job must go green.
- [ ] **Agent-runnable reads after the stagger** (read-only via `scripts/betterstack-query.sh`): `relay_probe proxy_state=listening` on both hosts, paired with a positive control (rows present for each host) and the Sentry query for `createProxyServer.no-hello-key` returning no issue in the window.
- [ ] **Agent-runnable read, PR B precondition:** a `relay_hello_window accepted>0` row on the owner host from a real proxied session (the deployed signed round trip), tracked in the residuals issue.

## Test Scenarios
- Real-socket admission: allowed / denied / undefined-address / IPv4-mapped / 200-burst / hello-less hold-open >1.2 s.
- Hello matrix: valid, each tamper, each shape violation, oversize, skew edges, replay, cache-full, forged-flood-then-valid.
- Rolling deploy: old-shape hello refused by the new verifier (committed); new-shape hello accepted by the REAL pre-PR parser (one-time sandbox verification recorded in the commit message and ADR-323, not a committed test).
- Key and port guards: every listed value, dev/canary/no-allowlist precedence.
- Destroy guard: the 14 rows; HALT executed against the real workflow step segment.
- Release gate: key present/missing/empty/malformed, value never printed.

## Risks and Sharp Edges
- **R1. `tlsClientError` still fires once per denied connection** (measured in the spike with the prepended listener: Node's TLS wrapper is still constructed around the destroyed socket). Harmless; a test pins `secureConnection === 0`, not `tlsClientError === 0`. A front `net.Server` would remove it at the cost of changing the listening-server object three tests read (rejected, F3).
- **R2. The serve-gate probe cannot see a broken verifier.** `relay_peer_probe` sends no hello. Positive proof of a signed round trip is a PR B precondition (tracked in the residuals issue); PR A's tests plus the bounded `reason` events are the only evidence until then.
- **R3. Coupling.** Adding the key to `REQUIRED` blocks every deploy while the key is absent; removing the relay (`host_proxy_tls_enabled` false) now needs the entry removed in the same change, and the new HALT blocks the per-merge route for that flip (ADR-118 amendment states it).
- **R4. Residuals accepted (F3/F4):** idle allowlisted peers; first-frame buffering up to `ws`'s default `maxPayload` (1 KiB is a length check on the first frame, not a socket bound; the server-wide limit cannot drop because the same socket then carries relayed client frames); a captured hello replayable to a different roster host within 60 s (the MAC does not bind the target host; needs a compromised roster host).
- **R10. No `maxConnections` cap (taste, recorded):** a small cap would also limit legitimate proxied sessions (one connection each) and needs the fleet's concurrent-session ceiling; not adopted here, listed in the residuals issue. The allowlist is a source-address check, not a credential: container egress or agent-run code on an allowlisted host presents that host's IP, which is why the MAC is the real gate and the pre-auth work is bounded (byte cap, text frame, six-key shape, bounded reporting).
- **R5. Key read per call from `process.env`, not deleted** (parity with `PROXY_TLS_KEY`): a child process spawned with an inherited env would see it; agent subprocess envs are allowlisted (`buildAgentEnv`), and Guard 9 pins that. Any new `spawn` without an explicit env in `apps/web-platform/server/` is out of scope but would reopen it.
- **R9. Replay cache is per process and clock-bound:** a container restart clears it for up to 60 s (a hello captured before the restart stays skew-valid), and a backward NTP step could re-admit a purged nonce; accepted, same trust model as R4.
- **R6. Sender/verifier drift** is closed by one shared canonical-string module plus the independent known-answer vector; do not add a second builder.
- **R7. `## User-Brand Impact` must stay filled** (a missing or empty section or threshold fails `deepen-plan` Phase 4.6); this plan's section names the artifact, the vector and the threshold.
- **R8. Test hygiene:** hex ids/nonces/macs make negative-substring assertions fragile (alphabet `[0-9a-f]`); assert on structured fields, not on substrings of generated values.
