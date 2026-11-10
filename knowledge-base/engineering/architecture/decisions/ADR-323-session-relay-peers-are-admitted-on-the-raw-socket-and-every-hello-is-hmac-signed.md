---
title: Session relay peers are admitted on the raw socket and every hello is HMAC-signed under a dedicated key
status: accepted
date: 2026-11-09
issue: 12289
related_adrs: [ADR-068, ADR-118, ADR-263, ADR-282, ADR-320, ADR-241]
---

# ADR-323: Session relay peers are admitted on the raw socket and every hello is HMAC-signed under a dedicated key

Refs: #12288, #12289, #12290, #12167, #8211. Related: ADR-068 (user-sticky routing, peer allowlist), ADR-118 (proxy cert SANs track the
roster; the hello key joined its count gate in the 2026-11-08 amendment), ADR-263 and ADR-282 (the LUKS no-ack set this PR deliberately
does not extend), ADR-320 and ADR-241 (Tier-A state readers). Plan:
`knowledge-base/project/plans/archive/20261109-130604-2026-11-09-feat-signed-relay-hello-pre-tls-allowlist-plan.md`.

## Status

Accepted 2026-11-09. In force at merge of the PR that closes #12288, #12289 and #12290. The deployed signed round trip between the two
web hosts is a separate precondition for serving external users from the second host; it is not a condition of this decision.

**Amended 2026-11-10** (#8211, PR #12536; CTO rulings of 2026-11-10, each cited inline where it applies): the verifier accepts one
verify-only slot, `PROXY_HELLO_HMAC_KEY_ACCEPT_ALSO`, absent by default, and each host logs a key fingerprint when its relay listener
starts. Decisions 2, 6 and 9 and the considered options gain marked additions; the 2026-11-09 text is unchanged, and the rotation
consequence is restated in `## Amendment — 2026-11-10 (#8211)` at the end. The amendment builds the verifier half of a rotation route
only: the leak route and the rotate mode are left to #12538 (signed relay probe: #12539), and no rotation phase can run until
it lands.

## Context

The owner host's relay listener (`session-proxy.ts`, port 8443 on the private net) attaches a token-less, pre-authenticated session for
whoever presents a valid `userId`/`workspaceId` pair: AP-2 membership (`verifyProxiedSessionMembership`) proves only that the pair is a
valid member pair, never that the caller may act as that user. Before this change the credential was therefore a valid user UUID plus a
reachable port. Three conditions of the owner's typed risk acceptance (on #8211) had to be closed before any external user is routed to
the second host:

1. **The peer allowlist ran after TLS and after the WebSocket upgrade.** ADR-068's 2026-07-02 amendment and the in-code comment said
   "before the handshake"; the code checked inside `wss.on("connection")`. Any private-net host could force a TLS handshake and a
   `reportSilentFallback` per connection (#12288).
2. **The hello was unsigned** (#12289). The TLS key is shared by both hosts, so it cannot be the signing key: a leaked TLS key must not
   forge hellos.
3. **A bad `SOLEUR_PROXY_PORT` threw out of `createProxyServer`** (`listen(NaN)` raises `ERR_SOCKET_BAD_PORT` synchronously into
   `index.ts`), a restart loop of the whole app for a relay-only fault (#12290).

## Considered Options

- **Accept-unsigned-and-log phase, then an enforce flip** (raised by the architecture reviewer). Removes the refusal window during the
  rolling deploy. Rejected by the CTO ruling of 2026-11-08: live users are 0, fail-closed is the safer default, and a dual-accept window
  keeps the takeover vector open for its whole length. Re-ask the CTO if `agent_sessions_live` is not 0 at release time.
- **`_PREVIOUS` dual-key verification.** The zero-downtime rotation pattern. Cut: rotation has no route in this PR; the new destroy-guard
  HALT blocks a replace instead.
- **`_PREVIOUS` two-phase stage-then-clear** (amendment, 2026-11-10). Rejected: every host both signs and verifies, so a host that
  signs the new key while its peer has not yet loaded it splits the hosts for the stagger. ADR-317 records the egress audit token's
  `_PREVIOUS` ordering as: "apply-A writes PREVIOUS=old AND CURRENT=new in one apply, the fleet redeploys (the app then accepts both),
  vector restarts on every host, and only then a clear apply `-replace`s PREVIOUS back to the empty default". That the ordering is
  lossless there because the token's sender (vector) and receiver (the app) are different services is this amendment's inference,
  not an ADR-317 statement. The slot is also not named `_PREVIOUS`: in P1 it holds the NEW key (CTO ruling of 2026-11-10 on the
  slot name).
- **Two accept slots** (amendment). Rejected: one accept-only slot covers every adjacent phase pair (see Decision 9).
- **An `accepted_also` counter on `relay_hello_window`** (amendment; CTO ruling of 2026-11-10). Cut: once the fingerprint rows show
  every host on current = new, no host signs the old key, so the counter adds nothing, and a new field is a parsing hazard on older
  images. The window grammar is unchanged.
- **A release-path shape check of the slot in `verify-required-secrets.sh`** (amendment; CTO ruling of 2026-11-10). Cut: it runs
  only on release restarts, so it cannot be the hard check, and a required entry would block every deploy. The hard checks are left
  to #12538's rotate mode (Decision 9, requirement (e)).
- **A Terraform `-replace` row for the key in `key-rotate.yml`** (amendment). Rejected: the hello key is minted by `random_bytes` in
  the web-platform root, the case ADR-320 decision 1 forbids for a production-access secret, so a `-replace` mints the new key into
  the same Tier-A-readable state, which ADR-320 says does not repair a leak. ADR-317's built `-replace` route is a different case: it
  resets `doppler_secret.egress_audit_ingest_token_previous`, which is fed by a sensitive variable, to its empty default, and
  Terraform mints nothing.
- **A new `ProxyState` value for "no hello key".** Cut: `error` already pages through `relay_listener_down`.
- **A hello-deadline timer** (slow-peer bound). First cut (the serve-gate probe holds an allowlisted, hello-less upgrade open for 700 ms
  to read `ok`), then REVERSED by the CTO ruling of 2026-11-09 (A2): a 10 s deadline sits far above the 700 ms probe hold and bounds an
  idle allowlisted peer. See Decision 1.
- **Edit `RELAY_PROBE_JS` so a pre-TLS reset reads `denied`.** Cut: it is a baked host script, so any byte changes the host-scripts
  coherence hash, for no gate benefit.
- **Extend the LUKS no-ack set (`luks_passphrase_addrs`) with the hello pair.** Cut: its HALT text, closed-sequence parity test, ADR-282
  wording and exact assertion floor are LUKS-specific.
- **A standalone key-presence preflight script.** Cut: `verify-doppler-secrets` already runs before `deploy`, and a merge to main is
  itself the release trigger, so a runbook step alone cannot gate it.

## Decision

1. **Pre-TLS admission (#12288).** A named listener `admitProxyPeer` is PREPENDED to the https server's raw `connection` event. A source
   whose normalized `remoteAddress` is absent or not in `SOLEUR_PROXY_PEER_ALLOWLIST` is destroyed before Node's TLS wrapper reads a
   byte. The in-`wss` re-check stays as defence in depth and shares the predicate. An admitted peer that produces no message
   within 10 s of admission (`HELLO_DEADLINE_MS`) is destroyed; the timer is cleared on the first message, and a test pins that the 700 ms
   probe hold is not cut.
2. **Bounded deny reporting.** Every refusal goes through one reporter (`proxy-deny-report.ts`): at most 5 Sentry events per reason per
   60 s window, an exact counter, one summary event for a window that suppressed anything, and one closed-grammar pino line
   `relay_hello_window accepted=<n> denied=<n> suppressed=<n>` per window with hello activity. That line is the only off-host positive
   signal for a signed round trip, because the serve-gate probe sends no hello. Extras are an enum, counts and the peer address; an
   unauthenticated reason never carries a hello-derived byte.
   *Amended 2026-11-10:* `createProxyServer` also emits one warn line per listener start (once per boot, because `index.ts` calls it
   once), right after the key check passes,
   `relay_hello_key_fp current=<8hex> accept_also=<8hex|none>`. Each value is the first 32 bits of HMAC-SHA256(key,
   `"soleur-relay-hello-key-fp-v1"`) from `helloKeyFingerprint`, never a raw-key prefix or a plain hash of the key; it is the only
   key-derived value that may reach a log. It proves the key state each host loaded, off-host and with no SSH, and NOT a serving
   relay: the bad-port, TLS-setup and listen-error exits after it can still stop the listener. The canary stops at `no_bind` first,
   so it prints none. The window line's grammar is unchanged.
3. **Signed hello (#12289).** `{type, userId, workspaceId, ts, nonce, mac}`; `mac` = HMAC-SHA256 under `PROXY_HELLO_HMAC_KEY` over
   `"soleur-proxy-hello-v1\n" + userId + "\n" + workspaceId + "\n" + ts + "\n" + nonce`. `ts` is Unix seconds as a decimal string,
   `nonce` 32 lowercase hex, `mac` 64 lowercase hex, both ids strict lowercase UUIDs. One shared module builds the canonical string for
   the sender and the verifier; a known-answer vector assembled by hand in the test pins it.
4. **Check order, fail-closed.** allowlist (pre-TLS) → pre-hello byte guard (a peer that sends more than 2048 bytes before its first message
   ARRIVES is terminated, so the bound is 2048 bytes plus the read chunk that completes the first frame; the server-wide `maxPayload`
   cannot be lowered because the same socket later carries relayed client frames) → 1 KiB cap on
   the raw Buffer length → text frame, plain object with exactly the six
   keys, shapes → MAC (`timingSafeEqual` on two 32-byte buffers) → ts within ±30 s → replay → AP-2 membership. The replay
   check-and-insert is synchronous and precedes the membership `await`. Every verifier refusal closes with the single reason
   `relay refused` and the owner terminates the socket 250 ms later, so a peer that ignores the close frame cannot keep streaming into it.
   The hello deadline and the byte guard drop the socket without a close frame (an abnormal close, 1006); a protocol error is terminated right
   after `ws` queues its own close frame (1002/1007/1009). The sending host maps a 1006 from the owner leg to the retryable 4014 so the
   browser reconnects.
5. **Replay cache.** 4096 live entries, per process. Each entry expires at `ts + 31 s` (derived from the hello's own `ts`, so the cache
   can neither outlive nor undercut the skew window; a receipt-based 60 s TTL expired exactly at the skew boundary). A full cache refuses
   with its own reason `full` and never evicts. The total replay window is about 61 s (`ts - 30` to `ts + 31`).
6. **Key handling.** `loadProxyHelloKey` accepts exactly 64 lowercase hex characters. It is called once at boot (`index.ts`, before any
   child can be spawned), the value is cached in module state, and the variable is deleted from `process.env` so a default or spread child
   environment cannot inherit it. It is in `sensitive-keys.ts`, absent from `agent-env.ts`, `ALLOWED_SERVICE_ENV_VARS` and `providers.ts`, pinned by an isolation test. With
   relay TLS enabled and the key absent or malformed, `createProxyServer` returns null, `proxy_state=error` and one constant-text
   `createProxyServer.no-hello-key` event; the check sits after the tls, bind and allowlist checks so `disabled`, `no_bind` and
   `no_allowlist` keep their meaning. Dev and CI without TLS stay `disabled` with no event.
   *Amended 2026-11-10:* the loader is `loadProxyHelloKeys()`, one cache over both `PROXY_HELLO_HMAC_KEY` and the verify-only slot
   `PROXY_HELLO_HMAC_KEY_ACCEPT_ALSO`; both are deleted from `process.env` on the first call whatever their values, and both names are in
   `sensitive-keys.ts` and pinned by the isolation test. The returned set is frozen and prints a placeholder under `JSON.stringify` and
   `util.inspect`. The slot is unset by default (silent); malformed reads as absent with one `loadProxyHelloKeys.accept-also-ignored`
   event; equal to the current key is kept with one warn-level `loadProxyHelloKeys.accept-also-equals-current` event; well-formed and
   distinct is kept with one warn-level `loadProxyHelloKeys.accept-also-active` event per boot (it sits outside Terraform, so a planted
   slot must not be silent). Each event text is a constant. The loader runs at every boot, so these events also fire when the canary
   boots (it gets the same `--env-file`); only the fingerprint line comes from the serving container. The slot alone never starts the
   listener: a missing current key still gives
   `createProxyServer.no-hello-key`. The sender signs with the current key only (`signProxyHello` takes one Buffer). The verifier
   computes both MACs and compares both with `timingSafeEqual` whenever the slot is set, refuses with `mac` only when neither matches,
   and applies the same skew, replay and AP-2 checks whichever key matched.
7. **Port parse and listen fence (#12290).** `resolveProxyPort` is a strict `^[0-9]{1,5}$` in 1..65535 parse evaluated at call time (the
   module-load constant is gone); `listen()` is wrapped, a throw closes the server and reports only the error code. The sender uses the
   same parser and never dials with an invalid port.
8. **Guard rails around the key.** A dedicated destroy-guard counter `relay_hello_key_changes` with its own non-ackable HALT on the
   per-merge path (a replace, update, delete, forget, state move off either address (`previous_address`), unreadable action list, or create of `random_bytes.proxy_hello_hmac` halts; a lone
   create of the secret is legal), and `PROXY_HELLO_HMAC_KEY` in the `REQUIRED` list of `verify-required-secrets.sh`, which the existing
   `verify-doppler-secrets` job runs before `deploy`. The gate is presence-only: it refuses an absent or empty key and does not check the
   shape; a present-but-malformed key is caught at startup by `createProxyServer.no-hello-key`, which leaves the app serving with the relay
   in `error`. The `migrate` job is not gated on `verify-doppler-secrets`, so on a release that carries a schema migration, a missing key
   blocks the deploy AFTER the migration has run, leaving the schema ahead of the serving image until the key exists.
9. **Leak response and kill switch: neither is built.** If the key leaks, the hellos it signs can be forged until it changes, and no
   reviewed, rehearsed route changes it. The per-merge HALT refuses a replace on purpose; the repo's workflows never set
   `host_proxy_tls_enabled` (`terraform-target-parity.test.ts` pins the workflow text, not a variable supplied from the secrets store), so
   flipping it is an edit of its `variables.tf` default, and the per-merge plan for that flip is a destroy of the pair, which the same
   HALT refuses. The containers read Doppler only at start, so any change also needs a rolling restart
   of both hosts, and while the relay is down users whose lease sits on the other host get 4014 and retry without limit (the app serves
   only the users routed to the local host). Restoring the previous Doppler value (the route for an out-of-band edit) re-installs a leaked
   key, so it is not a leak route. A rotation is therefore a separately reviewed change (dual-key `_PREVIOUS` verification, or minting the
   key outside Terraform per ADR-320 decision 2), not a runbook step; it is recorded on #8211 as an open item before external users are
   served from the second host.

   *Amended 2026-11-10 (#8211):* this block owns the rotation rationale; other files point here. The 2026-11-09 parenthetical above
   (`_PREVIOUS` or ADR-320 decision 2) is superseded by the accept-only slot and #12538 below.

   - **The slot.** One accept-only slot, `PROXY_HELLO_HMAC_KEY_ACCEPT_ALSO`, verify-only and dark by default (no new secret is minted).
     The sender never signs with it.
   - **Once #12538 provides the route, a routine rotation will be three phases** (CTO ruling of 2026-11-10 on the replace route), each
     one Doppler change plus one phase restart of every host in turn, because each host both signs and verifies: P1 sign old, slot
     holds new; P2 sign new, slot holds old; P3 sign new, slot unset. Two hosts in adjacent phases complete a signed round trip in both
     directions, and a skipped phase splits them in the predicted direction;
     `apps/web-platform/test/proxy-hello-rotation-phases.test.ts` is the executable statement of why.
   - **A phase restart is a container recreate through ci-deploy's `deploy` action**, which downloads Doppler `prd` into a fresh env
     file and starts a new container from it. A `docker restart`, a crash restart under `--restart unless-stopped`, a daemon restart or
     a reboot reuses the old container's env-file environment, so it does not advance the phase (which is also why a crash restart
     mid-rotation is safe). ci-deploy's `restart` action refuses the web-platform component. Because one image is pinned for the whole
     rotation (requirement (c)), #12538 must confirm that a same-tag redeploy recreates the container.
   - **A confirmed leak will be single-phase** under #12538, whatever the live session count (CTO ruling of 2026-11-10 on the leak
     path): the one-stagger 4014 split is accepted, because three phases would keep a leaked key accepted through two phase restarts
     plus the gate waits. #12538 is to declare the leak by a typed `leak` input in the owner's dispatch confirm; no such input exists
     until it lands. A leak rotation must, in one Doppler change, write a freshly minted current key distinct from both the old current
     value and the old slot value, and clear `PROXY_HELLO_HMAC_KEY_ACCEPT_ALSO`. It succeeds only when every roster host's
     current-boot fingerprint row shows the new `current=` and `accept_also=none`. Otherwise a leak during P1 or P2 leaves the slot's
     key accepted, and a slot planted by whoever holds the leaked key survives a rotation of the current key alone.
   - **A single-phase routine rotation** may be allowed by #12538 while `agent_sessions_live=0` on both hosts, with its check-then-act
     race named as an accepted residual (same ruling).
   - **Not executable until #12538.** `PROXY_HELLO_HMAC_KEY` is Terraform-managed (`doppler_secret.proxy_hello_hmac_key`, no
     `ignore_changes`), so any Doppler edit of it trips the `relay_hello_key_changes` HALT. No phase can run until #12538 moves the key
     out of Terraform (ADR-320 decision 2) and rotates it in the same act.
   - **Until #12538 lands there is no leak response and no kill switch.** Containment is the pre-TLS allowlist only: a forged hello also
     needs a roster-host source address. Restoring a previous Doppler value is still not a leak route. Retiring the relay stays a
     reviewed PR, never a normal-merge act.
   - **The signed relay probe is deferred** (#12539): a probe hello would raise `accepted` on every deploy and blur the "a real session
     ran" evidence; the fingerprint line is the smaller variant that ships here.

   **Phase-gate requirements for #12538** (normative; no line grammar is frozen by this amendment; CTO ruling of 2026-11-10 on the
   phase-gate contract):

   - (a) Every roster host shows a `relay_hello_key_fp` row from its **current boot**, and the host count equals the roster size.
     #12538 chooses the boot-identity field; a `boot=<nonce>` on the fingerprint line is preferred, shipped in an image release before
     the first rotation.
   - (b) A fingerprint row proves key state, not a serving relay, so a same-boot `relay_probe proxy_state=listening` row is also
     required.
   - (c) Before P1, every roster host shows a fingerprint row, which proves its image knows the slot. One image is pinned from P1
     through P3: no deploy of another image and no rollback mid-rotation. The slot must not be set while any container on an image
     older than this release can start (a rollback target, a held canary, the old container during a swap). An older image neither
     accepts the slot nor deletes it from `process.env`, and its `sensitive-keys.ts` does not list it for redaction. So a rollback
     mid-stagger splits the hosts (the rolled-back host refuses hellos signed with the slot's key), and any child process spawned with
     a default or spread environment inherits the key (agent subprocesses excepted: their environment is allowlist-built).
   - (d) #12538 freezes the line grammars when its parser lands.
   - (e) #12538's rotate mode must shape-check the slot before writing it, refuse a slot equal to the current key and a P2 slot not
     equal to the old current key, and run a per-host fingerprint check after the first host restarts, before the roll continues. The
     P1 to P2 gate must refuse while any host reads `accept_also=none`: a malformed slot reads as absent and leaves that host
     single-key. #12538 must also add a Better Stack alert on `accept_also!=none` outside a recorded rotation (a planted slot is
     otherwise only a warn-level Sentry event). The loader's Sentry events also fire on the canary boot, so a count of them is not a
     count of serving boots; only the fingerprint line comes from the serving container.
   - (f) #12538 must add a check that detects a hello-key split between hosts (for example, differing `current=` values across the
     current-boot fingerprint rows) and run it at every phase. No deploy gate detects one today: the serve-gate peer probe sends no
     signed hello.

## Consequences

- **Rolling deploy.** New sender → old receiver works: the pre-PR parser ignores extra hello keys (verified once against the real
  `origin/main` parser in a sandbox: a signed new-shape hello received `proxy_ready`). Old sender → new receiver is refused with reason
  `shape` for the stagger (a few minutes); users whose lease sits on the lagging host see close code 4014 and the generic reconnect
  loop. The release is named only after `agent_sessions_live=0` is read on both hosts. Rolling back to a pre-PR image re-opens unsigned
  hellos until the roll-forward.
- **`relay_peer_probe` shift.** A non-allowlisted source is now reset before `secureConnect`, so it reads `result=tls`; `denied` is
  unreachable from the probe on this image. This holds once both hosts run this image; during the roll an old-image peer still closes after the upgrade and reads `denied`. The grammar, the three `relay_*` alert queries and the serve gate (`result=ok`) are unchanged. The
  discriminator between a certificate fault and an allowlist deny is the receiver-side `peer` event. Node's TLS wrapper still raises one
  `tlsClientError` per destroyed connection (measured on Node 26; the admission test covers the CI Node); `secureConnection` stays 0.
- **The probe cannot see a broken verifier.** It sends no hello. The deployed signed round trip (a `relay_hello_window accepted>0` row on
  the owner host from a real proxied session) is the evidence needed before the second host serves external users.
- **Tier-A exposure, and ADR-320.** The key is minted by `random_bytes` in the web-platform Terraform root, so anyone with Tier-A state
  read (ADR-320, ADR-241) can forge hellos. This is NOT existing debt under ADR-320 decision 3: the resource was added by #12414 on
  2026-11-08, after ADR-320 (2026-11-04), and decision 1 forbids exactly this for a secret that grants production access; `PROXY_TLS_KEY`
  pre-dates the ADR. It is a departure from decision 1 that this PR introduces and records here, not a waiver; the move out of Terraform (decision 2) is the discharge, and ADR-320's own consequence
  applies: rotating a secret that sits in readable state does not repair the exposure, because the new value lands in the same state.
- **Agent sandbox and `/proc`.** `Bash` inside the inner sandbox cannot read the parent's `/proc/<pid>/environ`: the shim leaves an empty
  `/proc` (`agent-runner-sandbox-config.ts`, #10032; ADR-272 measured 0 readable environs on its measurement host, not the production image;
  `sandbox-isolation.test.ts` FR7/FR7b pin it; #9723 is closed). The opt-in outer wrap (`AGENT_OUTER_WRAP=1`, `agent-outer-wrap.ts`) still
  binds the full `/proc` and keeps its residual. The readers that DO inherit the server environment are
  the ones outside the sandbox (hooks, in-process MCP tools, `pdf-chapter-router`; ADR-272), which is why the key is deleted from
  `process.env` after the boot read: `/proc/self/environ` keeps the original block either way, so the deletion stops inheritance by
  children and nothing more.
- **Named residuals** (recorded here and on #8211 (comment of 2026-11-09), and the child-environment allowlist follow-up on #2614): the audience is not bound (a captured hello is replayable to a different roster host inside
  the replay window; a `v2` domain tag with the target host would bind it); the first frame is buffered up to the `ws` default
  `maxPayload`, but the pre-hello byte guard terminates a peer past 2048 bytes first; no `maxConnections` cap, because each proxied session holds one connection and a cap below the concurrent-session
  ceiling would refuse legitimate users; replaying a captured hello needs a compromised roster host; the per-process replay cache is
  cleared by a container restart for up to about 61 s, and a backward clock step can re-admit a purged nonce.
- **No rotation route.** After this change a replace of the key is an outage: the HALT blocks it on the per-merge path, `_PREVIOUS`
  dual-key verification is the future pattern (see Decision 9), and retiring the relay (`host_proxy_tls_enabled` false) needs a
  separately reviewed route and removing the `REQUIRED` entry in the same change.
- **Coupling.** A missing key blocks every deploy, hotfixes included, until it exists.
- **Clock assumption.** ±30 s needs NTP on both hosts; `reason=skew` is the symptom.

## Cost Impacts

None. No new vendor, host or recurring spend; one extra HMAC per relayed session setup.

## NFR Impacts

Security: closes the account-takeover vector on the relay port for a host that is merely on the private net. Availability: a missing key
stops only the relay; the app keeps serving. Observability: every refusal class carries a `reason` enum in a bounded Sentry event, and
`relay_hello_window` gives a per-minute accepted/denied/suppressed count.

## Principle Alignment

Fail-closed on every unsigned or invalid input; a dedicated secret per purpose; checks ordered cheapest-and-unauthenticated first; no
secret value, length or state in any event; every added guard has a mutation row in the commit that adds it.

## Diagram

No C4 change. The `coordinator` element description ("proxy over one-way-TLS private net") remains true and its comment already
describes the allowlist and the pinned certificate; `PROXY_HELLO_HMAC_KEY` reaches the container over the existing Doppler runtime
secrets edge; no actor, external system, container or access relationship is added. All three files under
`knowledge-base/engineering/architecture/diagrams/` (`model.c4`, `views.c4`, `spec.c4`) were read before concluding.

## Amendment — 2026-11-10 (#8211): the verifier accepts a verify-only slot; the rest of the rotation route is #12538

The 2026-11-09 Consequences bullet "No rotation route" stays as written, because it was true at acceptance. This amendment adds a
verify-only slot, `PROXY_HELLO_HMAC_KEY_ACCEPT_ALSO`, so the verifier half of a rotation route now exists, and that bullet's "future
pattern" is superseded by it (see Considered Options for why the two-phase pattern was rejected). Decision 9 (as amended) owns the
rotation rationale; other files point there.

Until #12538 lands, a replace of the key is still an outage and the HALT still blocks it on the per-merge path. A Terraform
`-replace` is not the route (Considered Options). Retiring the relay (`host_proxy_tls_enabled` false) still needs a separately
reviewed route and removing the `REQUIRED` entry in the same change. The slot itself stays optional and is not in
`verify-required-secrets.sh` (CTO ruling of 2026-11-10: a release-path check runs only on release restarts, so it cannot be the
hard check).

Named residuals added by this amendment:

- **Replay cache per phase.** Each rotation phase will recreate every container, so every host's in-process replay cache is cleared
  once per phase.
- **A planted slot is quiet.** A slot planted out of band causes no Terraform drift and no HALT, so its only signals are the per-boot
  `loadProxyHelloKeys.accept-also-active` event and `accept_also!=none` on the fingerprint line, until #12538 adds the alert.
- **`docker exec` inherits both key names.** The container starts with `--env-file`, the daemon keeps those values in the
  container's configuration and injects them into every `docker exec`, and the `process.env` deletion covers only the server process
  and its children. So every exec into the container runs with `PROXY_HELLO_HMAC_KEY` and, during P1 or P2,
  `PROXY_HELLO_HMAC_KEY_ACCEPT_ALSO` in its environment. ci-deploy strips env-file values from the exec output it logs today: the
  relay peer probe drops its stderr and logs only a closed result enum, and the canary diagnostics and the bwrap probe's error tail
  pass through `_cred_err_tail`, which replaces every env-file value of 12 or more characters. A future exec whose output skips that
  redaction would expose the keys.
- **No deploy gate detects a hello-key split between hosts.** The serve-gate peer probe sends no signed hello, so it cannot tell a
  split from a healthy pair; the symptom is a stream of `reason=mac` refusals on the owner host. Detection is a #12538 requirement
  (Decision 9, requirement (f)).
