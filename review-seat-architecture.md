# Architecture Review — PR #11780 (feat-one-shot-11772-next-dev-server-crash)

**Seat:** `soleur:engineering:review:architecture-strategist`
**Scope:** `git diff origin/main...HEAD` — `isBenignClientAbort` (Error + `"aborted"` + `ECONNRESET`) → `warnSilentFallback`, no exit, both `uncaughtException` + `unhandledRejection`, dev+prod. First non-fatal class in the ADR-062 crash contract.
**Questions asked of this seat:** (1) is the process-boundary chokepoint the right layer; (2) does the exact-pair contract hold as an architectural invariant; (3) boundary/consumer implications of adding a non-fatal class.

## Verdict

**Approve.** The architecture is sound and the layer choice is forced, not merely preferred. No P1s. Two P2s are advisory — one coverage gap on the invariant's provenance, one unrecorded observability-volume decision — neither blocks merge.

## 1. Chokepoint layer — affirmed, and structurally forced

`installCrashHandlers` (`apps/web-platform/server/crash-handlers.ts:82`, registered once at `server/index.ts:83`, before `app.prepare()`) is the single process-level chokepoint for both event types, and it is the **only** layer that can see this signature: the upstream defect (vercel/next.js #49587) wipes the `IncomingMessage`'s `'error'` listeners, so request/middleware-level classification is structurally unreachable — the abort escapes to process level precisely because every lower layer was stripped. The rejected alternatives recorded in the ADR-062 addendum (patch `next/dist`, restructure `middleware.ts`, respawn wrapper) are each strictly worse on review surface or efficacy.

Guard-2's assembly claim (plan §"Guard Contract") verifies in the diff: **one predicate, one dispatch site, one assertion home** — `isBenignClientAbort` is the sole classifier, `crash-handlers.test.ts` the sole pin. That is the correct shape for an exemption to a fatal contract: nothing else can drift.

Ordering inside the listener is also correct: classification runs **before** `reportFatalAndExit`'s `handling` re-entrancy check, so a benign abort landing mid-fatal-flush warns rather than force-exiting — and conversely a real fatal during a benign warn is unaffected (the warn path is synchronous, no state touched).

## 2. Exact-pair contract as invariant — holds, conservative direction

`err instanceof Error && err.message === "aborted" && err.code === "ECONNRESET"` is the right invariant:

- **Benign-by-origin is sound.** The pair is minted by Node's inbound-socket layer (`connResetException` via `abortIncoming`) on an already-destroyed request. ADR-062's fatal premise — "process in undefined state after an uncaught throw" — does not apply: no userland frames unwind mid-mutation; the throw escapes through Next internals on a dead connection. The non-fatal class is scoped to a signature whose origin is provably outside app state.
- **Near-miss census holds.** Verified: `dsar-export.ts` (35 `throw new Error("aborted")` sites), `dsar-export-co-uploader.ts` (4) — none assigns `.code`; outbound ECONNRESET mints `"socket hang up"`; fetch `AbortError`/`SessionAbortError` carry different messages (`"This operation was aborted"`, `"Session aborted: <kind>"`) and no `ECONNRESET`. All stay fatal; all pinned by test arms (crash-handlers.test.ts:152-186).
- **Fail direction is correct.** A false negative (signature drift) reverts to fatal — the DoS returns but no masked fatal. A false positive requires a future producer minting the exact pair — the documented residual, correctly ruled acceptable since it degrades to a recoverable warn-level miss.

## 3. Boundary/consumer implications of the non-fatal class

- Uniform dev+prod application is **structural**, not conventional: one entry point, unconditional install — no env gate to forget.
- `warnSilentFallback` gives the non-fatal class the full observability contract (pino mirror + `captureException(level:"warning")` + redaction + pseudonymization) with zero new sink code; `cq-silent-fallback-must-mirror-to-sentry` satisfied by reuse.
- The ADR-062 addendum documents the carve-out in-place at the contract it amends — exactly where a future reader of the fatal contract will look.

## Findings

### P2 — advisory, non-blocking

**P2-1. Runtime-mint provenance is unpinned; Node-side drift silently reverts the class.**
The invariant keys on Node-internal minted text (`"aborted"`/`"ECONNRESET"` from `internal/errors`' `connResetException`). The tests pin a *synthetic* fixture (`connResetException()` helper, crash-handlers.test.ts:131-136); the live socket repro was ad-hoc (`.next/repro-client.mjs`, uncommitted). A Node semver bump changing the minted message produces zero test failures while the mitigation silently dies — the unauthenticated restart-DoS returns with no signal. #11783 tracks *next*-side drift (delivery path), not Node-side (signature mint). Mitigation: a ~30-line vitest that mints the real error — `http.createServer`, send a request, `socket.destroy()` mid-response, assert the error that reaches the 'error'/process layer has the exact pair — pinning the runtime side in CI, or at minimum an explicit Node-version-coupling sentence in the ADR addendum naming the mint site.

**P2-2. The non-fatal class is an unauthenticated, client-driven Sentry event generator; quota decision unrecorded.**
`warnSilentFallback` calls `Sentry.captureException` per occurrence (`observability.ts:321`). Inbound aborts are routine in prod and attacker-influencable (tab closes, preload cancellations, SSE disconnects per #56529; the ruling itself notes cloudflared propagates aborts — no origin shielding). The change converts a *restart*-DoS into an *event-volume*-DoS — a strictly better failure class (availability > quota), and the plan does name volume a user-impact vector (plan:377) with burst-readable monitoring (plan:398). But no sampling/threshold decision is recorded; it rides on the still-pending CPO sign-off (decision-challenges.md:19). Recommend confirming that sign-off explicitly covers quota/saturation shape, and noting the pino mirror is the durable full-fidelity signal if the Sentry arm ever needs shedding.

### P3 — follow-ups

**P3-1. Listener origin not propagated.** Both listeners emit identical `feature=crash-handlers, op=client-abort` (crash-handlers.ts:85-88, 95-98); the warn event cannot distinguish `uncaughtException`-origin from `unhandledRejection`-origin — a distinction the #11783 re-evaluation will want ("which listener still receives the pair on fixed upstream?"). `SilentFallbackOptions.tags` supports additive extension (decision-challenges.md:18): pass `tags: { kind }`.

**P3-2. Warn path fires during a fatal flush window.** A benign abort arriving while `handling === true` (fatal flush in flight) calls `captureException` against a `Sentry.close()`-disabled SDK — harmless (dropped event), but a `handling` early-return or one-line comment would pin intent.

**P3-3. Second abort classifier in the server tree — scope-comment for cohesion.**
`server/abort-classifier.ts` (`SessionAbortError`, `classifyAbortReason`) classifies session-domain abort *reasons* at request/agent level; `isBenignClientAbort` classifies socket-level abort *errors* at process boundary. No signature collision (`"Session aborted: <kind>"` ≠ `"aborted"`, no `.code`), but two abort classifiers invite a future mis-unification. A one-line cross-reference on each ("classifies X-layer aborts; see Y for Z-layer") pins the boundary.

## Compliance check

- All five settled rulings verified against the diff — **none contradicted**: exact-pair scope (crash-handlers.ts:74-80); prod-wide (index.ts:83 unconditional, single entry); `warnSilentFallback` sink (observability.ts:287-334 reused, no bespoke Sentry call); `team_names` deferral (no mock route added); defense-in-depth retention (ADR addendum records keep-not-revert).
- ADR-062 updated in-place with carve-out, trigger, rejected alternatives, and re-evaluation pointer — meets the "significant architectural decisions documented" bar; no new ADR needed for amending an existing contract.
- Co-landing the `next ~16.4.1` bump with the classifier is justified (the bump alone crashes e2e); Guard-1 floor rows (`assert-dependabot-drain.py` REQUIRED/FLOOR_ANCHORS/WATCHED + MIN_ROWS/RESOLVED 36) and the egress version pin (16.3→16.4) updated consistently.
- No new module-boundary violations: `crash-handlers.ts → observability.ts` adds no cycle (observability imports logger/pii-redact/postgres-errors/userid-pseudonymize only; observability is already in index.ts's graph via `reportSilentFallback`).
