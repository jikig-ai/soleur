# Learning: the fix for a relay DoS made a latent close bug reachable, and the docs I wrote named routes that were not built

## Problem

PR #12462 (signed relay hello, pre-TLS peer allowlist, bounded deny reporting) added a 10 s hello deadline and a pre-hello byte guard that
`terminate()` an owner-side socket. A six-seat targeted fix round plus a verification seat then found, in the fix itself:

1. **A swallowed throw stranded the peer.** An owner-side terminate reads as close code 1006 on the sending host. The sender forwarded that code with
   `clientWs.close(1006, …)`, which `ws` rejects (`First argument must be a valid error code number`), and `safeClose` swallowed the throw. The
   socket was left in CLOSING and the browser never saw a 4014 or reconnected. The bug predated the PR (owner crash reached it) and the PR's own new
   terminate paths made it routine. Four seats found it independently, one reproduced it against `ws` 8.21.
2. **The guards switched off at the first message, refused or not.** The byte guard and the deadline were cleared on message *arrival*, and a
   refusal only called `close()`. A peer that ignored the close frame kept streaming: measured ~20 MiB in 1.5 s and 90 MiB in one frame while `ws`
   waited up to 30 s to close. The next implementation that satisfied the tests while violating the property was exactly the current one ("clear on
   first message instead of on accepted hello"), because every byte-guard test sent the flood as the *first* frame.
3. **My prose claimed things that were not true.** ADR-323 Decision 9 described a "kill switch" (`host_proxy_tls_enabled` false) and a "reviewed
   full-root run" as operable leak routes; neither is built (the flag is flipped by editing a default, the per-merge plan for it is a destroy the HALT
   refuses, containers read Doppler only at start). The ADR also called the key "existing debt under ADR-320 decision 3" (the resource was added after
   that ADR) and said the agent sandbox does not hide `/proc/<pid>/environ` (true only of the opt-in outer wrap; #9723 was closed and ADR-272 measured
   0 readable environs inside the inner sandbox). Four doc claims were falsified by `gh issue view` and one `grep` each.
4. **A latent flake in my own round-1 test.** `skew +31 s` built `floor(now)+31` and the verifier floors `now` to whole seconds, so a second tick
   between building and verifying turned a 31 s skew into 30 s (accepted): about a 5% failure rate under load.

## Solution

- `safeClose` terminates the socket when `close()` throws, and the sender maps any code `ws` cannot send (`isSendableCloseCode`: 1000–1014 except
  1004/1005/1006, or 3000–4999) to the retryable 4014. A pinned boundary table and a throwing-`close()` fake cover it.
- `refuse()` sends the uniform close frame and terminates 250 ms later; the linger value is exported and bounded in a test, and a call-form test
  asserts every owner-side refusal goes through it and that no bare `ws.close(` exists outside `safeClose`.
- `accepted` is set only after `proxy_ready` is on the wire; a refused peer's later socket error is not counted as a second refusal.
- Decision 9 now says "not built", with the real reasons; ADR-320 framing, the `/proc` bullet, the runbook query field (`message.reason`, flat),
  the replay window (~61 s) and the "every refusal closes with relay refused" sentence were corrected against the code.
- The skew case is `+33 s` with the exact boundary pinned elsewhere with an injected clock.

## Key Insight

- **When a PR adds a way to kill a connection, trace what the *other end* does with the resulting close code.** The terminate paths were tested from
  the owner side only; the defect was in the sender's forwarding of the code they produce. A fix that adds an abnormal-close path must add the test that
  the peer's handler survives an abnormal close.
- **A guard that disarms on "a message arrived" is not a guard on "an accepted message arrived".** Pin the *refusal* path with a peer that ignores
  the close frame (or pin the wiring by call form where the polite test client cannot tell graceful from terminate: N17 survived until the
  comment-stripped source assertion).
- **Prose I write about routes, issue states and exposure is a set of claims; run one command per sentence.** Three of the four false claims were
  inherited framing ("existing debt", "kill switch", "#9723 stays open") rather than measured state. The seats that found them each did one
  `gh issue view`, one `grep`, or one reading of a test file.
- **A test that builds a timestamp near a whole-second verifier boundary must stay clear of it by more than a second.**
- **CONCUR earned its place.** I drafted a rotation-route deferral with an attribution I had not verified and a mislabelled dependency issue; the
  simplicity seat checked the three premises with commands and the filing became a documentation fix plus a comment on the epic (net 0 issues).

## Session Errors

1. **Docs lint wording** (ADR-068 "operator apply") — Recovery: reworded to "local full-root run" — Prevention: run `lint-infra-no-human-steps.py --changed --base origin/main` before pushing any runbook or ADR edit.
2. **Secret scan NOT_RUN on a shallow clone** — Recovery: `git fetch --deepen=300 origin main` — Prevention: deepen before the first scan in a fresh worktree.
3. **Local full gate crashed the owner's browser** — Recovery: killed the tree, relied on CI (`ci-is-the-gate` in session-state) — Prevention: never start `test-all.sh` on a saturated machine; single test files only.
4. **Existing handshake test red after pre-TLS admission** (loopback not allowlisted) — Recovery: allowlist 127.0.0.1 in the case — Prevention: grep tests that open real sockets to the listener when the admission predicate changes.
5. **Test destroyed the client before the server counted `secureConnection`** — Recovery: wait on the server-side counter first — Prevention: assert on the server-side observable, not the client's.
6. **Padded frame double-counted by the guard and the verifier** — Recovery: `cutOff`/`handled` flags — Prevention: mutate each new guard in the commit that adds it.
7. **Boot test lacked a `loadProxyHelloKey` mock and asserted an async flush synchronously** — Recovery: mock the new boot dependency, `vi.waitFor` the flush — Prevention: grep the boot test's mocks whenever `index.ts` gains an import.
8. **Bundled 8-item residuals tracker DISSENTed** — Recovery: reshaped, then deferral dissolved into docs plus an epic comment — Prevention: run the CONCUR gate on the reshaped item before drafting more bodies.
9. **Unverified attribution and a mislabelled issue (#12167) in a draft filing** — Recovery: CONCUR seat checked the premises; filing dropped — Prevention: run `gh issue view <n>` for every issue a trigger names, and never attribute a finding to a seat from memory.
10. **False doc claims (kill switch, rotation route, ADR-320 debt, `/proc`)** — Recovery: rewrote Decision 9 and three bullets; sweep by claim — Prevention: for every causal sentence the diff adds, name and run the falsifying command before committing.
11. **Swallowed 1006 close left the browser socket open** — Recovery: `isSendableCloseCode` mapping plus `safeClose` terminate fallback — Prevention: test the peer's handling of an abnormal close for every new terminate path.
12. **Refusal path let a closing peer keep streaming** — Recovery: `refuse()` with a bounded linger — Prevention: pin refusal paths with a close-frame-ignoring peer or a call-form source assertion.
13. **`skew +31 s` test flaked** — Recovery: `+33 s` with the boundary pinned by injected clock — Prevention: never place a built timestamp within one second of a whole-second boundary.
14. **A behavioural test for the VITEST-only seam was impossible** (`createProxyServer` returns null with VITEST cleared) — Recovery: comment-stripped source anchor — Prevention: check which other seats a switch gates before designing a behavioural test around it.
15. **Parity-test regex and the T66m mutation sed were coupled to the jq line I restructured** — Recovery: updated both — Prevention: after editing a file other tests grep or mutate, run those suites and the mutation landing check in the same step.
16. **`Duplex` typing error (`tsc`) in a new test** — Recovery: typed the array as `Duplex[]` — Prevention: run `tsc --noEmit` after adding tests, not only vitest.
17. **Mutant N17 (graceful close on membership refusal) survived** — Recovery: call-form source assertion — Prevention: when a polite test client cannot tell graceful from terminate, pin the wiring by call form.
18. **Two Bash calls changed the lead's CWD** (`gh` from repo root; `cd ..` inside a compound command) — Recovery: re-cd with an absolute path — Prevention: use subshells `( cd dir && … )` or absolute paths.
19. **Seats left sandboxes behind** — Recovery: `soleur-sandbox.sh rm` per path (one refused: no ownership marker) — Prevention: brief seats to `rm` their sandbox as the last step and print the removal result.

## Tags
category: logic-errors
module: apps/web-platform/server/session-proxy
