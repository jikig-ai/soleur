# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-09-feat-signed-relay-hello-pre-tls-allowlist-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- cto_spawns=1 (batched F1-F4 rulings by the planning subagent)

### Errors
None blocking. The planner grepped the sharp-edges catalogue instead of reading it whole, ran a scoped deepen pass, and used a provisional ADR-323 ordinal (ADR-322 was last on origin/main).

### Decisions
- Destroy guard: dedicated counter relay_hello_key_changes with its own non-ackable HALT (F1).
- Presence preflight: add PROXY_HELLO_HMAC_KEY to REQUIRED in verify-required-secrets.sh (F2).
- Pre-TLS allowlist via prependListener on the https server with socket.destroy(); ci-deploy.sh untouched (F3).
- Bounded reporting 5 events per 60 s per reason plus counter; replay entry expires at ts + 31 s; one shared canonical-string module (F4).
- All ten added guards get sandbox mutation rows in the commit that adds them.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan, soleur:engineering:cto, soleur:product:cpo, plan-review panel, security-sentinel, test-design-reviewer.

## Operator Constraints

- constraint: Merge, release dispatch, apply dispatch, Doppler writes, flip.sh and cf-lb-overlay dispatch are owner gated and never run by the agent.
- constraint: Run the CI equivalent local gates including each CI flag before every push.
- constraint: Mutate every added guard on a sandbox copy in the commit that adds it, control green first.
- constraint: Review panel includes security-sentinel and test-design-reviewer at minimum.
- constraint: Stop with the PR ready and end with a Paused sentence naming the merge for the owner.
- constraint: Do not start PR B.
- ci-is-the-gate: Rely on CI instead of the local affected battery, the machine is saturated and the browser crashed during a call.

## Fix-round 2 dedup ledger (targeted round over 260c7353b6..07b61dbd84; dedup: 43 raw -> 14 unique)

| raw finding | canonical defect key | reporting seat(s) | planned fix commit |
|---|---|---|---|
| owner-side terminate reads as close 1006; `safeClose` swallows the throw and the browser socket stays open (x4) | sender forwards an unsendable close code | code-quality, user-impact, security, architecture | fix round 2 (session-proxy.ts, `isSendableCloseCode`, `safeClose` terminate fallback) |
| first message disarms byte guard and deadline; a refused peer keeps streaming up to maxPayload while `ws` waits to close | refusal path leaves a closing socket readable | security, test-design | `refuse()` with 250 ms terminate linger |
| `ws.on("error")` mislabels post-ready protocol errors as hello `shape` (x4) | error listener not scoped to pre-accept | code-quality, user-impact, observability, architecture | `accepted` flag |
| `internal` catch discards the error class | silent fallback loses cause | observability, user-impact | `errName` in extra |
| ADR `/proc` sentence false for sandboxed Bash; #9723 closed | doc claim contradicted by ADR-272 | security, architecture | ADR-323 rewrite |
| ADR-320 "existing debt" framing false (resource added after the ADR) | doc claim | architecture | ADR-323 rewrite |
| Decision 9 / HALT / runbook name kill-switch and rotation routes that are not built | doc claim | architecture, security | Decision 9 "not built"; HALT line; runbook |
| runbook query field `message.extra.reason` does not exist (flat `message.reason`) | doc claim | observability, architecture | runbook |
| "every refusal closes with relay refused" false for deadline / byte guard / protocol error | doc claim | architecture | ADR, runbook, header comment |
| stale 60 s replay window, R4/R5/R9, F3 "no timer" | stale paraphrase | architecture | ADR-068, runbook, plan, decision-challenges |
| `previous_address` clause undocumented in HALT / ADR / rationale runbook | doc gap | architecture, code-quality | HALT text, ADR-323, ADR-118, rationale runbook |
| unpinned: deadline per-connection key, destroy vs end, cumulative count, constants, VITEST seam, ws options, flush and key-load order, exact extras (x8) | test gaps | test-design, observability, code-quality | new tests; mutation rows N1-N17 |
| T66h: key address with an unrelated `previous_address` has no fixture | test gap | test-design | T66h sub-case + membership mutation |
| presence-only gate lets a malformed key through (user-impact F3) | RULED F2 (CTO): presence only; startup guard catches shape | user-impact | no change |

Disposition notes: P6-4 (`if (cutOff) return;`) verified equivalent by four seats under the current `ws` config; the config is now pinned in source and tested. N6 (clear before set) and N14 (peer label after destroy) are equivalent mutants: a live 4-tuple cannot repeat, and `net.Socket` caches `_peername` on the allowlist read that precedes the destroy. Declined as pre-existing/out of scope: no timeout between the deadline clear and the AP-2 lookup (pre-existing AP-2 call); stale `ci-deploy.sh:451` comment and `lb-weight-gate` labels (editing a baked host script changes the coherence hash); stale `agent-outer-wrap.ts` residual comment (other subsystem, recorded in ADR-323). The key-rotation filing was DISSENTed by the CONCUR seat and is not filed; the open items are recorded in ADR-323 Decision 9 and commented on #8211 and #2614 (2026-11-09).

Verification pass (1 seat, a15bad39e4): no P1. Closed in the final fix commit: ADR claims that residuals were "recorded on #8211/#2614" (now posted), `host_proxy_tls_enabled` "only" overstatement, `/proc` bullet scoping (outer wrap keeps its residual), protocol-error close wording, reporter header (`errName`), `accepted` set after proxy_ready, a refused peer's later socket error not counted twice, close-handler timer identity check, pinned linger, close-code boundary table, no bare `ws.close(`, pending-lookup protocol error test. Mutation rows V1, V2, V4, V7, V9 killed; V10 (timer identity in the close handler) equivalent, a live 4-tuple cannot repeat.
