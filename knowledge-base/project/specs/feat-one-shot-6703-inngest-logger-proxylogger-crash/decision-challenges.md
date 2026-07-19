# Decision Challenges — feat-one-shot-6703-inngest-logger-proxylogger-crash

Persisted at plan time (headless / one-shot pipeline — no interactive gate available).
`/soleur:ship` should render these into the PR body and file an `action-required` issue.

---

## DC-1 — USER-CHALLENGE: the plan refuses the operator's prescribed fix

**Operator's stated direction (the default):** "The intended fix: wire the Inngest client's
`logger` option to the shared pino instance."

**What the plan does instead:** binds the ctx logger at an Inngest middleware boundary and
explicitly does **not** add a `logger:` option to `new Inngest({...})`.

**Why the challenge is raised:** the brief invited it — *"If the evidence does not actually
support 'unwired client logger causes this TypeError', say so plainly in the plan and
propose the fix the evidence DOES support."* Three measured findings:

1. `ProxyLogger.enabled` is a class instance field initialized to `false`
   (`node_modules/inngest/middleware/logger.js:29`). It is never `undefined` on a live
   instance, so the unwired logger cannot produce
   `Cannot read properties of undefined (reading 'enabled')`.
2. `node_modules/inngest/components/Inngest.js:673` wraps **any** provided logger in
   `ProxyLogger` unconditionally — so wiring pino would have been wrapped identically and
   thrown identically. The prescribed fix does not fix the reported crash.
3. Wiring the shared pino would **regress** INFO traversal: `infra/vector.toml:87-96` keeps
   non-JSON lines (`if parse_err != null { true }`), so `DefaultLogger`'s `console.info`
   text reaches Better Stack today, while pino INFO would become JSON `level: 30` and be
   dropped. The brief's framing ("INFO still won't reach Better Stack even after this
   change") is inverted — INFO reaches it now and would stop.

**Operator decision needed:** accept the substitution, or direct that the client `logger`
option be wired anyway for the observability reasons in #6703 item 2 (accepting the INFO
regression and the fleet-wide Sentry-breadcrumb volume increase).

**Status:** plan proceeds with the substitution. #6703 stays OPEN with a corrected premise.

---

## DC-2 — USER-CHALLENGE: the reported crash is already fixed

The brief describes the crash as live. It was fixed by PR #6705 (`6496e3398`, merged
2026-07-19 17:35 UTC) — 37 minutes after #6700 (`9eadb1cc5`, 16:58 UTC) first made the
benign terminal path reachable in production and exposed it. The failing run predates the
fix.

**Consequence:** this PR is not a crash fix. It is a hardening change that removes the bug
*class*. A legitimate alternative is **ship nothing and close out** — zero violations exist
in the codebase today. The plan argues for shipping because the ~20-line bind eliminates a
class that has already cost one production incident, at no runtime cost.

**Operator decision needed:** ship the hardening, or close as already-fixed.

---

## DC-3 — TASTE: plan scope reduction (partially applied)

The code-simplicity review recommended cutting the plan ~70% (625 → ~180 lines), reducing
13 ACs to 3, and collapsing Phase 0.

**Applied:** ACs cut 13 → 11 → then restructured to 11 focused ones with fragile shell
fixed; the vacuous runtime "characterization" test was cut; redundant test-invocation
phases (3.3/3.4) collapsed into the full-suite gate.

**Not applied:** the full 70% reduction and the 3-AC target. Rationale — the plan's length
is dominated by the *falsification* sections, which two of three reviewers explicitly
praised and which exist to stop the next agent re-deriving the same wrong fix. Cutting
those would re-open the trap. Recorded as taste, not silently discarded.

---

## DC-4 — DISSENT ON THE RECORD: ADR for the middleware layer

The architecture review held that binding at the Inngest middleware layer "would warrant an
ADR" as a new cross-boundary integration pattern.

**Plan's call:** no new ADR — `client.ts` already composes `sentryCorrelationMiddleware`
and `runLogMiddleware`, so this is a third instance of an established in-repo pattern.

**Recorded so a future reader can disagree on the record rather than discover the omission.**
