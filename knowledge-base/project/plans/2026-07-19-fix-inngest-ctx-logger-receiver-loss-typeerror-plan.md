# fix: eliminate Inngest ctx-logger receiver loss by binding at the middleware boundary

---
type: bug-fix
lane: cross-domain
date: 2026-07-19
branch: feat-one-shot-6703-inngest-logger-proxylogger-crash
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
refs: ["#6703", "#6657", "#6698", "#6705", "#6700"]
---

> **Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed).** No spec
> directory exists under `knowledge-base/project/specs/` for this branch, so there is no
> `lane:` to carry forward.

## Overview

**The prescribed root cause is falsified by the evidence, and the prescribed fix would
not have fixed the crash. The crash itself is already fixed on `main`.**

This plan does not implement "wire the Inngest client's `logger` option to the shared
pino instance." It implements the fix the evidence *does* support: **make receiver loss
impossible** by binding the ctx logger once, at the Inngest middleware boundary, so every
handler receives a logger whose methods carry no `this` dependency.

```ts
// server/inngest/middleware/bound-logger.ts (new, ~20 lines)
transformInput({ ctx }) {
  const raw = ctx.logger;
  return { ctx: { logger: new Proxy(raw, {
    get(target, prop, receiver) {
      const v = Reflect.get(target, prop, receiver);
      // Bind every function-valued property to its owner, so detaching it
      // (`const f = logger.info`) can never lose the receiver.
      return typeof v === "function" ? v.bind(target) : v;
    },
  }) } };
}
```

Every function-valued property comes out pre-bound, so `const log = logger.info; log(x)` —
and every other detachment shape — becomes safe rather than merely detectable. Applied once
in `client.ts` alongside the two existing middlewares, it covers all 60+ Inngest functions.

> ‼️ **Why a binding Proxy and not three arrow closures.** The obvious implementation —
> `{ info: (...a) => raw.info(...a), warn: …, error: … }` — **trades one crash for
> another.** `ProxyLogger`'s own constructor returns a Proxy whose `get` trap forwards any
> *unknown* property to the underlying user logger (`middleware/logger.js:32-35`), so the
> real ctx logger also carries `debug` (`logger.js:49-52`) plus pino passthroughs (`child`,
> `trace`, `fatal`, `level`). A three-method plain object silently **drops all of them**,
> and any caller reaching for one gets `TypeError: logger.debug is not a function`. The
> binding Proxy preserves the entire passthrough surface *and* makes every method
> detachment-safe, at the same ~5 lines. Caught by the deepen-plan SDK verification pass.

> **This is a revision.** The first draft of this plan proposed a *compile-time detector*
> (adding `this` parameters to `HandlerArgs["logger"]`). Three independent plan reviews
> converged against it, and two measured findings killed it:
>
> 1. **It has holes.** Measured against the pinned `tsc`: the type guard catches
>    extract-then-call but **silently misses** `p.catch(logger.error)`,
>    `setTimeout(logger.info, 0)`, `forEach(logger.info)`, and any assignment to a plain
>    function type — all of which crash identically at runtime.
> 2. **It guards a type the compiler never checks against reality.** **65 files** under
>    `server/inngest/functions/` register via
>    `handler as unknown as Parameters<typeof inngest.createFunction>[2]`. `HandlerArgs` is
>    a hand-written shim that is *never* type-checked against the SDK's real ctx, so
>    narrowing it constrains how handler bodies use the shim — not what inngest passes.
>
> A detector with holes, guarding a severed type, loses to a ~20-line bind that eliminates
> the class outright. See *Alternatives Considered*.

The full falsification is in **Research Reconciliation** below. The short version:

| Prescribed claim | Verified reality |
| --- | --- |
| Unwired client `logger` causes `TypeError: …reading 'enabled'` | **False.** `ProxyLogger.enabled` is an instance field initialized to `false` (`middleware/logger.js:29`) — never `undefined` on a live instance. |
| Wiring `logger` to pino fixes it | **False.** `components/Inngest.js:673` does `new ProxyLogger(providedLogger)` **unconditionally**. A wired pino is wrapped identically; a detached reference still throws. |
| The crash is live | **False.** PR #6705 (`6496e3398`, merged 2026-07-19 17:35 UTC) already fixed it. The failing run predates that merge. |

---

## Hypotheses

The reported marker is:

```
detail="reissue body failed after retries; steady state restored: Cannot read properties of undefined (reading 'enabled')"
errorName=TypeError
errorDetail="Cannot read properties of undefined (reading 'enabled')"
```

| # | Hypothesis | Verdict | Evidence |
| --- | --- | --- | --- |
| H1 | Unwired client logger → `DefaultLogger` in `ProxyLogger` → `this.enabled` undefined | **REFUTED** | `enabled = false` is a class instance field (`middleware/logger.js:29`). A constructed `ProxyLogger` always has it defined. `!this.enabled` on a live instance evaluates `!false` — no throw. |
| H2 | A **detached method reference** loses the receiver → `this` is `undefined` in strict-mode class code → `this.enabled` throws | **CONFIRMED** | This is the only expression in the entire `inngest` package that reads `.enabled` (`grep -rn "\.enabled" node_modules/inngest` → 6 hits, all `middleware/logger.js`). The message shape (`Cannot read properties of **undefined**`) requires `this === undefined`, which only a detached call produces. Confirmed by the in-repo fix + its comment at `cron-gh-pages-cert-reissue.ts:1492-1508`. |
| H3 | Some other `.enabled` in the codebase | **REFUTED** | `grep -rn "\.enabled\b" apps/web-platform/server apps/web-platform/app` → all hits are unrelated (`config.enabled`, `flag.enabled`, `autoMerge.enabled`, `args.enabled`, `kbChat?.enabled`) and none are on the cert-reissue execution path. |
| H4 | The failure originated in `onFailure` or the retry path | **REFUTED** | The `onFailure` handler *receives* the body's error and threads `error.message` into its detail string (`:1703`). The TypeError is the **body's** error, not `onFailure`'s. |

### Marker-shape discrepancy (flagged, not load-bearing)

The report gives `phase=terminal`. The detail string
`"reissue body failed after retries; steady state restored: …"` is emitted at
`cron-gh-pages-cert-reissue.ts:1703` with **`phase: "onfailure-restore"`**, not
`terminal`. Either two rows were conflated when pulling from Better Stack, or the phase
was paraphrased. This does not change the diagnosis — the `error.message` carried into
`onFailure` is the body's TypeError either way — but a plan that silently "corrected" the
operator's telemetry would be hiding a real read discrepancy, so it is recorded here.

### Why the bug fired when it did

1. **#6700** (`9eadb1cc5`, 16:58 UTC) added the step markers and the `probe_only_complete`
   outcome. That made `probe_only_complete` the **first benign terminal to actually
   execute in production** — previously the only reachable benign outcomes were `issued`
   (never achieved; the cert was wedged) and `not_stuck`.
2. The benign branch of `emitTerminal` was the only code path holding a detached
   `logger.info` reference. Every prior live fire ended non-benign and took the
   `reportSilentFallback` branch, which never touches the ctx logger.
3. The extracted reference threw, the throw escaped `emitTerminal` → the handler →
   exhausted `retries: 1` → fired `onFailure`. **A successful probe reported itself as a
   failure.**
4. **#6705** (`6496e3398`, 17:35 UTC, MERGED) replaced the extraction with direct method
   calls (`:1509-1515`) and added a `ProxyLoggerLike` test fake.

---

## Research Reconciliation — Spec vs. Codebase

| Claim (from the task brief / #6703 item 2) | Codebase reality | Plan response |
| --- | --- | --- |
| "`client.ts` constructs `new Inngest({...})` with **no** `logger` option" | **TRUE.** `apps/web-platform/server/inngest/client.ts:60-75` — no `logger` key. | Accepted as fact; but see next row for why it is not the cause. |
| "so inngest falls back to `DefaultLogger` wrapped in `ProxyLogger`" | **TRUE** — `components/Inngest.js:147` (`logger = new DefaultLogger()`) + `:673` (`new ProxyLogger(providedLogger)`). | Accepted. |
| "`enabled` only flips true inside `beforeExecution()`" | **TRUE** — `Inngest.js:680-682`. | Accepted; relevant to the *observability* class, not the crash. |
| "→ therefore the TypeError" | **FALSE — non sequitur.** `enabled` being `false` is not `enabled` being *undefined*. The gate returns early; it does not throw. | **Root cause re-derived** as receiver loss (H2). |
| "The intended fix: wire the client's `logger` to shared pino" | **Would not fix the crash.** `Inngest.js:673` wraps *any* provided logger in `ProxyLogger`. `this.enabled` on a detached reference throws identically with pino wired. | **Fix replaced** with a compile-time receiver guard. |
| "Vector drops pino INFO via `level_int >= 40`, so INFO still won't reach Better Stack" | **Partially inverted.** `vector.toml:87-96`: `parsed, parse_err = parse_json(.message); if parse_err != null { true }` — **non-JSON lines are KEPT.** `DefaultLogger` emits `console.info(payload, msg)` → `util.inspect` text → **not JSON → currently KEPT.** Wiring pino turns INFO into JSON `level: 30` → **DROPPED.** | Recorded as a **regression risk of the prescribed fix**, and a further reason not to do it here. |
| "`cert-reissue-marker.ts` routes around this defect; do not delete/refactor" | **TRUE** and reaffirmed. `cert-reissue-marker.ts:52` is a dedicated module-scope pino at WARN with **no `logMethod` hook**, deliberately (`:40-44`). | **Untouched by this PR.** See Out of Scope. |
| "Write a failing test first" | The routine already has a `ProxyLoggerLike` regression test for `emitTerminal` (`test/server/inngest/cron-gh-pages-cert-reissue.test.ts:1344`, added by #6705). | RED phase targets the **unguarded residual** (the type contract), not the already-guarded site. |
| "`onFailure` and its retry path are prime suspects" | **Refuted** (H4). `onFailure` is the *reporter*, not the source. | Recorded. |

### Alternatives Considered

| Option | Mechanism | Coverage | Cost | Verdict |
| --- | --- | --- | --- | --- |
| **A** — `this` parameters on `HandlerArgs["logger"]` | Compile-time **detector** | Partial (see table below); guards a type severed from reality by 65 casts | ~4 lines, but narrows a type consumed by 68 modules | **Rejected.** Holes + severed type. |
| **B** — bind at a per-handler adapter | Runtime **elimination** | Complete | Would need a wrapper at 65 registration sites | **Rejected.** Same effect as C at far higher cost. |
| **C** — bind via Inngest middleware `transformInput` | Runtime **elimination** | **Complete** — all shapes, all 60+ functions | ~20 lines, 1 new file + 1 line in `client.ts` | **CHOSEN.** |
| **D** — ESLint `no-restricted-syntax` | Lint **detector** | Broad but name-based/brittle; still only detects | New rule + config | Rejected as primary; noted as a possible later complement. |

**Why C over A** — measured coverage of the rejected detector, compiled against
`apps/web-platform/node_modules/.bin/tsc --strict --target ES2022`. `TS2684` = caught.
**Option C makes every row safe**, including all the ESCAPES:

| # | Shape | Result |
| --- | --- | --- |
| S1 | `const s = logger.info; s("x")` — **the #6705 shape** | **CAUGHT** (`TS2684`) |
| S2 | `const s = cond ? logger.warn : logger.info; s("x")` | **CAUGHT** (`TS2684`) |
| S3 | `const { info } = logger; info("x")` — destructure then call | **CAUGHT** (`TS2684`) |
| S4 | `const h = { fn: logger.info }; h.fn("x")` | **CAUGHT** (`TS2684`) |
| S5 | `[logger.info].forEach((f) => f("x"))` — arrow **wrapper** | **CAUGHT** (`TS2684`) |
| S6 | `emit(logger.info)` — passed to a `(...a: unknown[]) => void` parameter | **ESCAPES** |
| S7 | `const g: (...a: unknown[]) => void = logger.info; g("x")` | **ESCAPES** |
| S8 | `p.catch(logger.error)` / `forEach(logger.info)` / `setTimeout(logger.info, 0)` — passed **directly** | **ESCAPES** |

The rule for Option A: the `this` requirement survives **inference** (S1–S5) and is erased
by **widening to a plain function type** (S6–S8), because a function type with no `this`
parameter is assignable to one that declares it (bivariance; `strictFunctionTypes` does not
change this).

> ‼️ S5 vs S8 look alike and behave oppositely under Option A. `[logger.info].forEach((f)
> => f("x"))` is caught (the array element type retains `this`; the error lands on the
> inner `f("x")`); `forEach(logger.info)` is **not** (the callback parameter type erases
> it). That two visually-near-identical shapes diverge is itself an argument against
> shipping A as the guard — a reviewer cannot eyeball which side of the line a call sits on.
>
> **Under Option C, every row above is safe** and the distinction stops mattering.

Note that S8 (`p.catch(logger.error)`, `setTimeout(logger.info, 0)`) is arguably the *more*
idiomatic next occurrence in async cron code than S1 — so the detector missed the likelier
future bug while catching only the one that already happened.

### The actual residual risk (what this PR fixes)

`apps/web-platform/server/inngest/functions/_cron-shared.ts:183-187` declares:

```ts
logger: {
  info: (...a: unknown[]) => void;
  warn: (...a: unknown[]) => void;
  error: (...a: unknown[]) => void;
};
```

These are **standalone function-typed properties with no `this` requirement**. TypeScript
therefore accepts `const log = logger.info` at every one of the 60+ Inngest function
handlers — while the runtime value is a `ProxyLogger` whose methods dereference
`this.enabled`. **The type system cannot currently catch the receiver loss.** #6705 fixed
one call site and guarded it with one test fake; nothing prevents the next occurrence in
any other routine.

Verified today: `grep -rnE "(const|let|var)\s+\w+\s*=\s*\w*[Ll]ogger\.(info|warn|error|debug)\s*[;,)]"`
over `server/` and `app/` returns **zero** current extraction sites, and the bare-callback
form (`(logger.info)`) also returns zero. So the fix is a pure guard with no existing
violations to remediate — which is exactly why it is cheap to land now.

---

## User-Brand Impact

**If this lands broken, the user experiences:** a cron-wide outage. **Revised on review** —
an earlier draft called this "a type-only annotation with zero runtime emission" whose
worst case was "a `tsc --noEmit` failure that blocks CI." That described the rejected
Option A. What ships is runtime code on the hot path of all 65 Inngest functions: a `get`
trap that fires on *every property access of every logger call*. A throw in that trap, or
in `transformInput`, reds every cron on the surface — the marketing-site TLS renewal, the
weekly analytics fan-out, the payment-failure handlers. That is why three separate throw
paths (frozen logger, nested-trap `Reflect.get`, `new Proxy(undefined)`) are each guarded
and each pinned by a mutation-tested case: the blast radius of a mistake here is strictly
larger than the bug being fixed.

The failure mode of *not* landing it is the one already observed: a cron routine's
terminal-logging path throws, the routine reports a successful remediation as
`reissue_incomplete_restore_ok`, and the operator is paged for a success (or, worse, reads
a real success as a failure and re-fires a remediation that consumes a Let's Encrypt
validation attempt).

**If this leaks, the user's data / workflow / money is exposed via:** no exposure vector.
The facade forwards to the caller's logger and adds no field, no network call, and no
persisted data. It emits exactly one line of its own, on the fail-open branch, carrying a
fixed message and `typeof raw` — no logger contents, no event payload, no user data.

**Brand-survival threshold:** `aggregate pattern`

Rationale for not selecting `single-user incident`: this PR cannot itself expose or
corrupt any single user's data. The *routine* it protects does guard the public
marketing-site TLS path, but the blast radius of this specific diff is confined to
compile-time type checking.

---

## Open Code-Review Overlap

Query run at plan time:

```bash
ISSUES_JSON=$(mktemp -t open-review-issues.XXXXXXXX.json)
gh issue list --label code-review --state open --json number,title,body --limit 200 > "$ISSUES_JSON"
```

Then, per planned file path:

```bash
jq -r --arg path "apps/web-platform/server/inngest/functions/_cron-shared.ts" '
  .[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"
' "$ISSUES_JSON"
```

**Result: None.** No open `code-review` issue names `_cron-shared.ts`,
`cron-gh-pages-cert-reissue.ts`, `client.ts`, or `cert-reissue-marker.ts`.

**Disposition:** n/a — nothing to fold in, acknowledge, or defer.

Related-but-not-overlapping: **#6703** stays open (two of its three items are
deliberately out of scope; item 2's premise is corrected by this PR — see Phase 4).

---

## Domain Review

**Domains relevant:** Engineering (CTO)

Assessed all 8 domains semantically. Marketing, Sales, Finance, Legal, Product, Support,
Operations: **not relevant** — this is a compile-time type annotation on internal cron
infrastructure with no user-facing surface, no pricing/billing touch, no regulated data,
and no operational runbook change.

**Mechanical UI-surface override:** did **not** fire. `## Files to Edit` contains no path
matching `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`, or any other
UI-surface glob. Product/UX Gate correctly skipped (tier NONE).

### Engineering (CTO)

**Status:** reviewed
**Assessment:** The cross-cutting concern is that `HandlerArgs` is consumed by 60+ Inngest
handlers. Narrowing a type used that widely is a `hr-type-widening-cross-consumer-grep`
adjacent operation in reverse — a *narrowing*, which can break existing consumers. The
mitigation is mechanical and complete: `tsc --noEmit` over `apps/web-platform` compiles
every consumer, and the plan gates on a clean run. The pre-verified zero-extraction-sites
grep predicts a clean pass; any surprise failure is a genuine latent bug the guard exists
to surface, and must be fixed inline rather than by relaxing the type.

Second concern: adding `this` parameters must not break the **test fakes**, which pass
object literals (`{ info: vi.fn(), ... }`) as `HandlerArgs["logger"]`. Object-literal
methods satisfy a `this`-parameterized signature via TypeScript's bivariance on method
declarations, but this MUST be verified empirically in Phase 1, not assumed — it is the
single most likely way this change fails, and it would fail loudly at `tsc`, not silently.

---

## Observability

```yaml
liveness_signal:
  what: "cert-reissue terminal markers (SOLEUR_CERT_REISSUE, phase=terminal) continue to
         appear for benign outcomes, proving emitTerminal's logger path does not throw"
  cadence: "per manual fire of cron/gh-pages-cert-reissue.manual-trigger"
  alert_target: "Sentry issue-alert on tag feature=cron-gh-pages-cert-reissue (existing)"
  configured_in: "apps/web-platform/infra/sentry/ (existing alert, unchanged by this PR)"

error_reporting:
  destination: "Sentry via reportSilentFallback (non-benign) + Better Stack via
                cert-reissue-marker pino WARN (all phases)"
  fail_loud: true

failure_modes:
  - mode: "A future detached ctx-logger reference is introduced in any Inngest handler"
    detection: "NOT DETECTED — and deliberately so. The bind makes the shape HARMLESS
                rather than observable. There is nothing to alert on because there is no
                longer a failure. CAVEAT: this honesty holds only while the bind is
                actually applied, which is exactly what the fail-open mode below covers."
    alert_route: "n/a — failure mode removed, not monitored"
  - mode: "applyBoundLogger fails open (ctx.logger absent or non-object) — all 65
           functions silently revert to unbound loggers and the receiver-loss TypeError
           class returns fleet-wide. Reachable by an SDK bump OR by a refactor that reads
           ctx.logger from onFunctionRun instead of transformInput; tsc catches neither."
    detection: "Layer 2 — module-scope pino ERROR via warnSilentFallback → Sentry
                captureException, tag feature=inngest-bound-logger, op=transformInput.
                Deduped to one report per process (the container restarts each deploy, so
                it re-arms). Deliberately NOT the ctx logger: that is the path found
                missing, so the mirror must be disjoint from it."
    alert_route: "Sentry issue alert on tag feature:inngest-bound-logger"
  - mode: "Middleware ordering disturbs sentry-correlation scope tagging or run-log's
           {ok, errorSummary} projection (would surface as silent data loss in
           public.routine_runs, NOT as an error)"
    detection: "Existing sentry-correlation + run-log vitest suites, required to pass
                UNMODIFIED (AC6, enforced by an empty `git diff --name-only` over those
                suite paths). This is the highest-value assertion in the PR."
    alert_route: "CI test job on the PR (blocks merge)"
  - mode: "The bind defeats ProxyLogger's `enabled` gate, multiplying ctx-log volume
           across 60+ crons on every replay pass"
    detection: "T6 / AC5 — with enabled === false, a bound call must deliver ZERO calls to
                the underlying logger. Asserted, not assumed."
    alert_route: "CI test job on the PR (blocks merge)"
  - mode: "A handler reaches for a logger method the facade does not forward
           (debug / child / flush)"
    detection: "tsc --noEmit — HandlerArgs declares exactly info/warn/error and all 65
                handlers are typed against it"
    alert_route: "CI typecheck job (blocks merge)"

logs:
  where: "One conditional emission only: the fail-open branch of applyBoundLogger, via
          warnSilentFallback (module-scope pino ERROR → Sentry), deduped once per process.
          Zero emission on the healthy path — the facade forwards to the caller's logger
          and adds no line of its own."
  retention: "Sentry issue retention (existing); no new persisted data"

discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run
            test/server/inngest/bound-logger-middleware.test.ts"
  expected_output: "20 passed — including the hook-wiring case that drives
                    init().onFunctionRun().transformInput() and the hostile-shape cases
                    (frozen logger, nested-trap throw, cross-instance mis-bind)"
```

**Corrected on review.** An earlier draft of this block declared
`logs.where: "no new log emission — this PR adds zero runtime code"` and a
`tsc --noEmit` discoverability test. Both described **Option A, the rejected type-level
detector**. What ships is a runtime `InngestMiddleware` executing a `Proxy` get trap on
every property access of every logger call across 65 functions — a typecheck cannot
exercise that. The block above describes the shipped design.

**No SSH anywhere in the verification path.** The entire acceptance surface is a local
typecheck plus a vitest run.

### Affected-surface note (§2.9.2)

The Inngest cron worker is a blind execution surface, and this PR adds runtime code to it.
The healthy path is deliberately silent — a facade that logged about logging would
multiply volume across 65 crons for no signal. The one branch that *would* otherwise be
invisible, the fail-open, is covered by a Layer 2 emission (`warnSilentFallback` →
Sentry, `feature=inngest-bound-logger`) that is disjoint from the `ctx.logger` path it
reports as missing. The pre-existing in-surface probe (`cert-reissue-marker.ts` WARN
markers, reaching Better Stack) remains the runtime discriminator and is untouched.

### Soak follow-through enrollment (§2.9.1)

**Not applicable.** No acceptance criterion is time-gated; every AC resolves at CI time.
`#6657` remains follow-through-enrolled via
`scripts/followthroughs/gh-pages-cert-reissue-6657.sh` and is **not** touched by this PR.

---

## Architecture Decision (ADR/C4)

**No new ADR; no C4 change.**

**Detection result:** this PR makes no data-model ownership/tenancy move, introduces no
substrate or integration pattern, changes no resolver/dispatch/trust boundary, and
reverses no existing ADR. It narrows one internal TypeScript interface. A future engineer
reading ADR-125 + the C4 model would not be misled about the system after this ships.

**C4 completeness check (per the §2.10 mandate — enumeration, not a keyword grep).** Read
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`. Enumerated
for this change:

- **External human actors:** none added or changed. This PR has no human-facing surface.
- **External systems / vendors:** none added. The systems this routine touches are all
  already modeled — `github` (`model.c4:230`), `cloudflare` (`:234`), `letsencrypt`
  (`:269`), `publicResolvers` (`:278`), `betterstack` (`:283`), `sentry` (`:290`).
- **Containers / data stores:** none added. `inngest` (Inngest Server, `:188`) and
  `inngestRedis` (`:196`) already exist; this PR adds no container and no store.
- **Actor↔surface access relationships:** none changed. No sharing, ownership, or
  permission edge is added, removed, or re-pointed.

Because every element the change touches is already modeled and no element description is
falsified by it, **"no C4 impact" is supported by the enumeration above**, not asserted
bare.

**On the middleware choice specifically.** A plan-review agent argued that binding at the
Inngest middleware layer "would warrant an ADR" as a new cross-boundary integration
pattern. Judgment: **no new ADR.** `client.ts` already composes two middlewares
(`sentryCorrelationMiddleware`, `runLogMiddleware`); this is a third instance of an
established in-repo pattern, not a new one. Recording the dissent here rather than
silently discarding it, so a future reader can disagree with the call on the record.

**ADR-125 relationship:** ADR-125 (`status: accepted`, 2026-07-18) governs the
cert-reissue routine. It declares no numbered invariants and says nothing about the
Inngest ctx logger, ProxyLogger, pino, or Vector — so this PR neither amends nor
contradicts it. No amendment needed.

---

## Implementation Phases

### Phase 0 — Preconditions (verify, do not assume)

0.1. Confirm the fix for the reported crash is on `main` and this worktree is rebased on
     it:

```bash
git log --oneline -1 6496e3398          # 6705: emitTerminal must call the logger method
git branch --contains 6496e3398 | grep -qw main && echo "ON MAIN"
git merge-base --is-ancestor 6496e3398 HEAD && echo "IN BRANCH"
```

0.2. Re-confirm the vendored mechanism against the **pinned** version (do not trust this
     plan's quotes — re-read):

```bash
grep -n "version" apps/web-platform/node_modules/inngest/package.json | head -2   # expect 3.54.2
sed -n '27,40p'  apps/web-platform/node_modules/inngest/middleware/logger.js      # enabled = false instance field
sed -n '670,676p' apps/web-platform/node_modules/inngest/components/Inngest.js    # new ProxyLogger(providedLogger)
```

If `inngest` is not 3.54.2, **stop** and re-derive — every claim in this plan is pinned to
that version.

0.3. Re-confirm zero existing extraction sites (the guard must land green, not red, on
     production code):

```bash
grep -rnE "(const|let|var)\s+\w+\s*=\s*\w*[Ll]ogger\.(info|warn|error|debug)\s*[;,)]" \
  apps/web-platform/server apps/web-platform/app
grep -rnE "\(\s*\w*[Ll]ogger\.(info|warn|error|debug)\s*\)" apps/web-platform/server
```

Both must return zero. **If either returns a hit, that is a live latent crash** — fix it
in this PR and record it as an additional finding.

0.4. Confirm the typecheck command and that it covers `test/`:

```bash
grep -n '"include"' apps/web-platform/tsconfig.json   # expect **/*.ts, exclude only node_modules
cd apps/web-platform && ./node_modules/.bin/tsc --noEmit && echo "BASELINE CLEAN"
```

> **Note the runner forms** (both are repo sharp edges): typecheck is
> `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — **never**
> `npm run -w apps/web-platform typecheck` (the repo root declares no `workspaces`).
> Tests are **vitest**, not `bun test`:
> `cd apps/web-platform && ./node_modules/.bin/vitest run <path>`.

### Phase 1 — RED: a test that actually fails today

Create `apps/web-platform/test/server/inngest/bound-logger-middleware.test.ts`.

The RED assertion is a **runtime** one, and it genuinely fails before the fix — unlike the
`@ts-expect-error` the first draft proposed, which would have been an unused directive both
before and after (three reviewers independently flagged that as vacuous).

1. Build a `ProxyLoggerLike` **class** fake mirroring inngest's real shape — `enabled` as an
   initialized instance field, each method opening `if (!this.enabled) return;`. It MUST be
   a class: an object literal has no `this` dependency and cannot reproduce receiver loss.

2. **RED** — detaching from the RAW ctx logger throws today:

   ```ts
   const raw = new ProxyLoggerLike(); raw.enable();
   const detached = raw.info;
   expect(() => detached("x")).toThrow(
     /Cannot read properties of undefined \(reading 'enabled'\)/,
   );
   ```

3. **RED → GREEN** — the same detachment through the middleware-bound logger must NOT
   throw, and must still reach the underlying logger:

   ```ts
   const bound = applyBoundLogger(raw);        // the middleware's transformInput output
   const detachedBound = bound.info;
   expect(() => detachedBound("x")).not.toThrow();   // FAILS today (no middleware exists)
   expect(raw.received).toContainEqual(["x"]);       // still delivered, not swallowed
   ```

   Run it and **record the failure output** — this is the real RED evidence.

3b. **Anti-vacuity control** (per
   `knowledge-base/project/learnings/2026-07-19-a-self-graded-mutation-battery-went-vacuous-twice-in-one-pr-and-the-two-producer-count-that-fixed-it.md`):
   the battery must fail when the **observer is removed**, not only when an arm is
   perturbed. Add an explicit mutation check to the PR body: delete the `bind` (return `v`
   raw from the trap) and confirm the suite goes RED. A suite that stays green with the
   bind deleted is measuring nothing.

3c. **Fail-open case:** `applyBoundLogger(undefined)` and `applyBoundLogger(null)` must
   **not throw** and must leave ctx untouched (the middleware returns `undefined`). This is
   the guard that prevents `new Proxy(undefined, …)` from redding every cron.

3d. **Surface-preservation case:** a logger carrying `debug` / `child` / a non-function
   `level` must still expose all of them through the facade — `bound.debug` is a function,
   `bound.level` is the passthrough value, and a detached `const d = bound.debug; d("x")`
   does not throw. This is the regression the three-arrow-closure design would have shipped.

4. Cover all detachment shapes the detector would have missed, so the elimination claim is
   asserted rather than asserted-about:

   ```ts
   for (const call of [
     () => { const f = bound.info; f("a"); },
     () => { const { warn } = bound; warn("b"); },
     () => [1].forEach(bound.info as (v: number) => void),
     () => setTimeout(bound.error, 0),
     () => Promise.reject(new Error("z")).catch(bound.error),
   ]) expect(call).not.toThrow();
   ```

5. **Gate-preservation test** — binding must NOT defeat `ProxyLogger`'s `enabled` gate
   (that gate is load-bearing: it prevents duplicate logging across Inngest's replay
   passes). With `enabled === false`, a bound call must be a silent no-op, not a passthrough:

   ```ts
   const off = new ProxyLoggerLike();            // enabled === false
   applyBoundLogger(off).info("x");
   expect(off.received).toHaveLength(0);
   ```

### Phase 2 — GREEN: bind the ctx logger at the middleware boundary

Create `apps/web-platform/server/inngest/middleware/bound-logger.ts`, mirroring the
structure of the existing `run-log.ts` (`new InngestMiddleware({ name, init() { return {
onFunctionRun() { return { transformInput({ ctx }) { … } } } } } })`).

```ts
export const boundLoggerMiddleware = new InngestMiddleware({
  name: "bound-ctx-logger",
  init() {
    return {
      onFunctionRun() {
        return {
          // ‼️ Read ctx.logger HERE, not in onFunctionRun — see the precedent trap below.
          transformInput({ ctx }) {
            const raw = ctx.logger;
            // ‼️ FAIL OPEN. `new Proxy(undefined, …)` THROWS — and a throw here
            // would red EVERY cron on the surface. If the logger is missing or
            // not an object, return undefined: the waterfall passes `prev`
            // through unchanged and the run proceeds with the original ctx.
            // Sanctioned observability-of-observability exemption to
            // `cq-silent-fallback-must-mirror-to-sentry`, same rationale as
            // `cert-reissue-marker.ts`: a logging failure must NEVER red a cron,
            // and mirroring it would re-enter the path that is already broken.
            if (!raw || typeof raw !== "object") return;
            return {
              ctx: {
                logger: new Proxy(raw, {
                  get(target, prop, receiver) {
                    const v = Reflect.get(target, prop, receiver);
                    return typeof v === "function" ? v.bind(target) : v;
                  },
                }),
              },
            };
          },
        };
      },
    };
  },
});
```

**Fail-open vs fail-loud (a real tension, resolved deliberately).** A deepen-plan learnings
pass raised that `runLogMiddleware` classifies a non-throwing run as
`status='completed'`, so a silently-unbound logger would look like success
(`knowledge-base/project/learnings/integration-issues/2026-06-29-cron-health-run-log-green-masks-claude-eval-failure.md`).
That argues for failing loud. **We fail open anyway**, because the alternative is worse: a
throw in `transformInput` reds *every cron on the surface* over a logging concern. The
in-repo precedent is explicit — `cert-reissue-marker.ts:34-37` documents the same call as a
sanctioned exemption. The residual risk is bounded: the guard can only fire if Inngest stops
supplying `ctx.logger`, which would be an SDK-breaking change caught by the Phase 1 tests
and by `tsc` at the next bump.

**Why `v.bind(target)` and not `v.bind(receiver)`:** `receiver` is our outer Proxy, so
binding to it would re-enter this trap on every internal `this.*` access inside
`ProxyLogger` — including `this.enabled` and `this.logger`. Binding to `target` hands the
method the receiver it actually expects. Non-function values (e.g. `level`) pass through
untouched.

Register it in `apps/web-platform/server/inngest/client.ts`:

```ts
middleware: [sentryCorrelationMiddleware, runLogMiddleware, boundLoggerMiddleware],
```

**Ordering rationale (load-bearing — state it in a comment).** `boundLoggerMiddleware` goes
**last** so it wraps the ctx logger the earlier middlewares have already finished
composing. Verify empirically in Phase 3 that the ordering does not disturb
`sentry-correlation`'s scope tagging or `run-log`'s `transformOutput` projection; if it
does, move it and record why.

**Do NOT add a `logger:` option to `new Inngest({...})`.** That is the falsified fix, and
it would additionally regress INFO traversal through Vector (see Research Reconciliation).

**Note on `_cron-shared.ts`:** `HandlerArgs["logger"]` needs **no change**. The bound facade
satisfies the existing `(...a: unknown[]) => void` property shape exactly. Leaving that type
untouched is a deliberate simplification over the rejected Option A, which would have
narrowed a type consumed by 68 modules to no runtime benefit.


### Precedent diff (deepen-plan Phase 4.4)

Two in-repo middlewares establish the canonical shape. The new one MUST match it.

| Aspect | `sentry-correlation.ts` | `run-log.ts` | `bound-logger.ts` (new) |
| --- | --- | --- | --- |
| Constructor | `new InngestMiddleware({ name, init() {...} })` | same | **same** |
| Nesting | `init()` → `onFunctionRun({ctx, fn})` → `{ transformInput, beforeExecution, transformOutput }` | `init()` → `onFunctionRun({ctx, fn})` → `{ transformInput, transformOutput }` | `init()` → `onFunctionRun()` → `{ transformInput }` |
| Scoping | all functions | `if (!(fnId in ROUTINE_METADATA)) return {};` | **all functions** (the bind must be universal — scoping it would leave the un-scoped majority exposed) |
| `transformInput` returns | nothing (side-effect only) | nothing (captures `attempt`/`maxAttempts`) | **`{ ctx: { logger } }`** — the first in-repo middleware to return a ctx patch |

> ‼️ **Precedent-derived trap — do NOT read `ctx.logger` in `onFunctionRun`.** `run-log.ts`
> documents this explicitly: *"attempt / maxAttempts are NOT on onFunctionRun's ctx — that
> ctx is Inngest's InitialRunInfo (`{ event, runId }` only; 'does not necessarily contain
> all the data'). The retry-attempt fields live on BaseContext, which is only handed to
> transformInput."* The same applies to `logger`. Capturing it in `onFunctionRun` would
> silently yield `undefined`, and the facade would forward to nothing — a **silent
> log-loss across all 60+ crons**, with no error to detect it. The Phase 2 snippet reads
> `ctx.logger` inside `transformInput` for exactly this reason.
>
> **Novelty callout:** returning a `ctx` patch from `transformInput` is **not** an existing
> in-repo pattern — both current middlewares return void. The pattern is borrowed from
> Inngest's own built-in logger middleware (`components/Inngest.js:673-676`), which is the
> right precedent, but reviewers should scrutinize it as new-to-this-repo.

### Phase 3 — Verify the fleet-wide blast radius

The brief correctly insists the blast radius is every cron, not one routine. Under Option C
that is now genuinely true — the middleware runs on every function — so the verification
must be fleet-level.

3.1. Typecheck:

```bash
cd apps/web-platform && ./node_modules/.bin/tsc --noEmit
```

3.2. Enumerate the surface the middleware now covers, so the claim is named, not implied:

```bash
grep -rl "inngest.createFunction" apps/web-platform/server/inngest/functions/ | wc -l
```

Record the count in the PR body as the number of functions whose ctx logger is now bound.

3.3. **Middleware-interaction assertions** (the real fleet-wide risk — not the type):

- `./node_modules/.bin/vitest run test/server/inngest/` — all Inngest routines.
- Confirm `sentryCorrelationMiddleware` still tags scope: the existing
  sentry-correlation tests must pass unmodified.
- Confirm `runLogMiddleware` still projects `{ ok, errorSummary }`: the existing run-log
  tests must pass unmodified. **This is the highest-value assertion in the phase** — it is
  the one place a middleware-ordering mistake would surface as silent data loss in
  `public.routine_runs` rather than as a test failure in the new file.

3.4. Full-suite exit gate (catches orphan suites asserting on client/middleware shape):

```bash
cd apps/web-platform && ./node_modules/.bin/vitest run
```

### Phase 4 — Correct the record on #6703 item 2 (do NOT close)

`#6703` item 2 currently asserts the causal chain this plan falsifies. Leaving it
unamended means the next agent re-derives the same wrong fix.

Post a **comment** on #6703 (never an edit that closes it) recording:

- `ProxyLogger.enabled` is an instance field; the TypeError was receiver loss, fixed by #6705.
- Wiring the client `logger` would not have fixed it (`Inngest.js:673` wraps unconditionally).
- The observability rationale for item 2 **survives** on its own merits (the `enabled`
  gate genuinely swallows ctx logs on discovery/memoization passes) — but with a
  correction: wiring pino would make INFO ctx-logs **stop** reaching Better Stack
  (`vector.toml` keeps non-JSON, drops JSON `level: 30`), and would route fleet-wide WARN+
  through the shared pino `logMethod` Sentry-breadcrumb hook that `cert-reissue-marker.ts`
  was deliberately built to avoid.

**Issue hygiene (hard requirement):** the PR body uses `Ref #6703` and `Ref #6657` in
prose. **No `Closes`/`Fixes`/`Resolves` for either.** #6703 keeps two live out-of-scope
items; #6657 is follow-through-enrolled via
`scripts/followthroughs/gh-pages-cert-reissue-6657.sh` and closes only when the sweeper
confirms the cert reached `issued`/`approved`.

---

## Acceptance Criteria

Thirteen ACs in the first draft were cut to seven on review — the removed ones were
grep-for-the-thing-you-just-wrote, prose assertions with no command, or fragile shell
(`grep -c … → 0` exits 1 under `set -e`; `.comments[-1]` breaks on any later comment).

### Pre-merge (PR)

- **AC1 — the middleware exists and binds every function-valued property.**
  `server/inngest/middleware/bound-logger.ts` exports `boundLoggerMiddleware` and returns a
  `Proxy` whose `get` trap binds function values to `target`. Verify:
  `grep -c 'bind(target)' apps/web-platform/server/inngest/middleware/bound-logger.ts` → `>= 1`
  (currently `2` — the call plus the comment explaining `target` over `receiver`; a
  body-grep sees comments, so an exact count here would be pinning prose, per
  `cq-assert-anchor-not-bare-token`).
  (A three-arrow-closure implementation fails this AC by design — it drops
  `debug`/`child`/`level`.) **Behaviour, not shape, is the real gate:** AC4's suite asserts
  it, and the AC3b mutation control proves the suite would catch its removal.
- **AC1b — the fail-open guard exists AND reports.** Verify the guard admits both
  wrappable shapes and rejects nothing else:
  `grep -cE 'typeof raw !== "object" && typeof raw !== "function"' apps/web-platform/server/inngest/middleware/bound-logger.ts`
  → `1`. Without the guard, `new Proxy(undefined, …)` throws and reds every cron. **Revised
  on review:** the original AC rejected `typeof raw === "function"`, which would have failed
  open against a perfectly wrappable callable logger (debug/npmlog/roarr shape). It must
  also MIRROR — see AC1d.
- **AC1d — the fail-open is reported, not silent.** The guard calls `warnSilentFallback`
  (module-scope pino → Sentry, `feature: "inngest-bound-logger"`), deduped once per process,
  inside a `try/catch` so a reporting failure cannot red a cron. **Why this was added:**
  fail-open and fail-silent are separable and only the first is forced. Unreported, this
  branch silently reverts all 65 functions to unbound loggers with no signal on any
  observability layer — a fleet-wide regression shaped exactly like health. The
  `cert-reissue-marker.ts` exemption does NOT cover it: that one is scoped to a `catch`
  around an emit that already failed, where the mirror re-enters the broken path; here
  nothing has been attempted and the mirror target is disjoint from `ctx.logger`.
- **AC1e — hostile logger shapes cannot throw.** The `get` trap must survive three shapes
  that each reintroduce the crash class, all verified live against a real Proxy before being
  fixed:
  1. **Frozen logger.** For an own non-writable + non-configurable data property, `[[Get]]`
     requires the trap to return the target's exact value; a bound copy throws. That check
     runs *after* the trap returns, so a `try/catch` inside it does **not** contain the
     throw — it must be avoided via `Reflect.getOwnPropertyDescriptor`, not caught. Such a
     property stays unbound: not throwing is the guarantee, binding is unavailable at any
     price.
  2. **`Reflect.get` throwing through the nested trap.** The real target is itself a Proxy
     whose trap ends `Reflect.get(target.logger, …)`; a `child()` returning `undefined`
     makes any unknown-prop read throw `Reflect.get called on non-object`. Fail open to
     `undefined`.
  3. **Cross-instance mis-binding.** Bound methods are memoised two levels deep, keyed on
     the **target first**. Class methods live on the shared prototype, so a single-level
     cache hands the second logger a method bound to the first instance — silently routing
     one cron's logs into another's. Verified to return the wrong receiver.
  Also pins bound-method identity stability (`logger.info === logger.info`), without which
  `emitter.off(logger.info)` can never match and handler-set dedupe double-registers.
- **AC1f — the hook wiring is exercised end-to-end.** A test drives
  `boundLoggerMiddleware.init().onFunctionRun().transformInput({ ctx })` and asserts the
  returned ctx patch carries a bound facade. Every other assertion calls `applyBoundLogger`
  directly, so without this a wiring regression — notably reading `ctx.logger` in
  `onFunctionRun`, where it is `undefined` — would silently unbind all 65 functions with no
  red test.
- **AC1c — `ctx.logger` is read in `transformInput`, never `onFunctionRun`.** Verify the
  `onFunctionRun` signature takes no destructured `ctx`:
  `grep -cE 'onFunctionRun\(\)' apps/web-platform/server/inngest/middleware/bound-logger.ts` → `1`.
- **AC2 — it is registered on the client.** Verify:
  `grep -q "boundLoggerMiddleware" apps/web-platform/server/inngest/client.ts && echo BOUND`
  → prints `BOUND`, and the `middleware: [...]` array contains it.
- **AC3 — RED was real.** The PR body quotes the Phase-1 test output *before* Phase 2,
  showing `detachedBound("x")` throwing
  `Cannot read properties of undefined (reading 'enabled')`. A guard that never failed
  proves nothing — this AC exists because the first draft's proposed guard was vacuous and
  three reviewers caught it.
- **AC3b — the battery is not vacuous.** The PR body records the mutation control: with
  `v.bind(target)` replaced by `v`, the suite goes **RED**. A suite that stays green with the
  bind removed is measuring nothing (the failure mode recorded in the 2026-07-19
  self-graded-battery learning).
- **AC3c — fail-open verified.** `applyBoundLogger(undefined)` and `applyBoundLogger(null)`
  do not throw and leave ctx untouched.
- **AC3d — passthrough surface preserved.** A logger carrying `debug` and a non-function
  `level` exposes both through the facade, and a detached `const d = bound.debug; d("x")`
  does not throw.
- **AC4 — every detachment shape is safe.** `./node_modules/.bin/vitest run test/server/inngest/bound-logger-middleware.test.ts`
  passes, including the five-shape loop (extract, destructure, `forEach`, `setTimeout`,
  `.catch`) and the `enabled === false` gate-preservation case.
- **AC5 — the `enabled` gate still works.** Binding must not turn Inngest's replay-pass
  suppression into a passthrough. Asserted by the Phase-1 gate-preservation test; called
  out separately because it is the one way this change could *add* log volume fleet-wide.
- **AC6 — no middleware-interaction regression.** `cd apps/web-platform && ./node_modules/.bin/vitest run`
  (full suite) passes, with the existing `sentry-correlation` and `run-log` suites
  **unmodified**. Verify no edits leaked:
  `git diff --name-only $(git merge-base origin/main HEAD) -- 'apps/web-platform/test/server/inngest/*sentry*' 'apps/web-platform/test/server/inngest/*run-log*'`
  → empty.
- **AC7 — typecheck clean.** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0.
- **AC8 — the falsified fix is NOT implemented, and the marker is untouched.** Verify:
  `git diff --name-only $(git merge-base origin/main HEAD) -- apps/web-platform/server/cert-reissue-marker.ts`
  → empty, **and** `apps/web-platform/server/inngest/client.ts` gains no `logger:` option
  (the only change to that file is adding `boundLoggerMiddleware` to the `middleware` array).
  Both are explicit constraints from the brief; the merge-base (not `origin/main`) is used
  so a later unrelated merge to main cannot red a clean PR.
- **AC9 — issue hygiene.** The PR body contains `Ref #6703` and `Ref #6657` and **no**
  closing keyword for either. Verify (note `|| true` — `grep -c` exits 1 on zero matches):
  `gh pr view <N> --json body -q .body | grep -ciE "(clos(e[sd]?)|fix(e[sd])?|resolve[sd]?):?\s+#(6703|6657)" || true`
  → `0`. #6703 and #6657 both still `OPEN` after merge.
- **AC10 — no overclaim.** The PR body states explicitly that (a) the client `logger`
  option is deliberately NOT wired, (b) the `ProxyLogger.enabled` gate still suppresses ctx
  logs on discovery/memoization passes, so this does **not** fix the observability class,
  and (c) #6703 item 2 remains open with a corrected premise. Verified by reviewer reading
  — there is no mechanical check for "did not overclaim," and inventing a grep for it would
  be theatre.
- **AC11 — the record is corrected.** A comment on #6703 records the falsification.
  Verify across *all* comments, not the last:
  `gh issue view 6703 --json comments -q '.comments[].body' | grep -c "ProxyLogger" || true`
  → `>= 1`.

### Post-merge (operator)

**None.** Every acceptance criterion resolves at CI time. This PR ships no infrastructure,
no migration, no secret. The `web-platform-release.yml` pipeline restarts the container on
merge to `main` for `apps/web-platform/**` changes automatically, so the middleware takes
effect without an operator step.

## Files to Edit

| Path | Change |
| --- | --- |
| `apps/web-platform/server/inngest/client.ts` | Add `boundLoggerMiddleware` to the `middleware` array (last). **No `logger:` option.** |

## Files to Create

| Path | Purpose |
| --- | --- |
| `apps/web-platform/server/inngest/middleware/bound-logger.ts` | The `transformInput` bind that eliminates receiver loss fleet-wide. |
| `apps/web-platform/test/server/inngest/bound-logger-middleware.test.ts` | RED→GREEN detachment tests + the `enabled`-gate preservation test. |

## Files explicitly NOT edited

| Path | Why |
| --- | --- |
| `apps/web-platform/server/inngest/functions/_cron-shared.ts` | `HandlerArgs["logger"]` needs no change — the bound facade satisfies the existing shape. Narrowing a type used by 68 modules was the rejected Option A. |
| `apps/web-platform/server/cert-reissue-marker.ts` | Load-bearing WARN marker independently reaching Better Stack today (AC8). |
| `apps/web-platform/server/inngest/functions/cron-gh-pages-cert-reissue.ts` | **Deviation, comment-only.** No logic change; its `ProxyLoggerLike` regression test stays as the site-level belt. A review pass flagged that the `‼️ CALL THE METHOD, DO NOT EXTRACT IT` block reads as *false* once the middleware ships — a future reader would conclude the middleware doesn't work and either delete the guard or distrust the fix. Added a `#6703 UPDATE` note marking it defence-in-depth and stating why it still holds (the middleware fails open; a frozen logger keeps unbound methods). Recorded here rather than silently widening scope. |
| `apps/web-platform/infra/vector.toml` | No filter change needed or proposed. |

## Test Scenarios

| # | Scenario | Expectation |
| --- | --- | --- |
| T1 | `const f = raw.info; f("x")` on the **raw** ProxyLogger-like | Throws `Cannot read properties of undefined (reading 'enabled')`. **This is the RED.** |
| T2 | `const f = bound.info; f("x")` through the middleware | Does not throw; the call reaches the underlying logger. |
| T3 | `const { warn } = bound; warn("x")` | Does not throw. |
| T4 | `[1].forEach(bound.info)` — the shape Option A missed | Does not throw. |
| T5 | `setTimeout(bound.error, 0)` / `p.catch(bound.error)` — also missed by Option A | Does not throw. |
| T6 | `enabled === false`, then `bound.info("x")` | **Silent no-op.** The replay-suppression gate is preserved, not defeated. |
| T7 | Existing `sentry-correlation` + `run-log` suites | Pass unmodified — middleware ordering did not disturb scope tagging or the `routine_runs` projection. |
| T8 | #6705's `emitTerminal` regression block | Still green (belt-and-braces at the site level). |

## Risks & Mitigations

| # | Risk | Mitigation |
| --- | --- | --- |
| **R1** | **Middleware ordering breaks `sentry-correlation` scope tagging or `run-log`'s `{ ok, errorSummary }` projection.** This is now the top risk — it is the one failure mode that would surface as *silent data loss* in `public.routine_runs` rather than a red test. | `boundLoggerMiddleware` is registered **last**, so it wraps an already-composed ctx. AC6 requires the existing sentry-correlation and run-log suites to pass **unmodified** (verified by a `git diff --name-only` that must come back empty — a suite edited to make it pass is the failure this guards). If ordering does disturb them, move the registration and record why in a comment. |
| **R2** | **The bind defeats `ProxyLogger`'s `enabled` gate**, turning replay-pass suppression into a passthrough and multiplying log volume fleet-wide across 60+ crons. | The facade forwards to `raw.info(...)` with the correct receiver, so the gate applies exactly as before. Asserted explicitly by T6 / AC5 (`enabled === false` → zero delivered calls), not assumed. |
| **R3** | ~~The facade drops methods handlers might use (`debug`, `child`, `flush`).~~ **RESOLVED by design change.** | The original three-arrow-closure design **would** have dropped them — `ProxyLogger`'s constructor Proxy forwards unknown props to the underlying logger (`middleware/logger.js:32-35`), so the real ctx logger carries `debug` (`logger.js:49-52`) plus pino passthroughs. The binding-Proxy design preserves the entire surface. Asserted by AC3d. |
| **R4** | ~~Inngest's own internals call `logger.enable()` / `flush()` / `logger.error(error)` on the ctx logger — does replacing it break them?~~ **RESOLVED at plan time.** | **Verified against the pinned SDK.** `Inngest.js:673-687` declares `const logger = new ProxyLogger(providedLogger)` and calls `enable()`, `error()`, `flush()` on that **closure const** — `ctx` is read only at `:661-666` for `runId`/`eventName` metadata, never for the logger. The facade is invisible to them, and because it forwards to the same instance, `enable()` still flips the gate our calls observe. Also verified: the built-in logger middleware is **prepended** (`Inngest.js:162`, `[...builtInMiddleware, ...middleware]`), so ours runs after and sees the real `ProxyLogger`; and `transformInput` ctx merging is a shallow spread in array order, last-write-wins (`execution/v1.js:1087-1099`), so returning `{ ctx: { logger } }` clobbers nothing else — `run-log.ts` returns `undefined` and `sentry-correlation.ts` never touches `logger`. |
| **R4b** | `ctx.logger` is absent/non-object at `transformInput` → `new Proxy(undefined, …)` throws → **every cron on the surface reds** over a logging concern. | The fail-open guard (AC1b) returns `undefined`, and the waterfall passes `prev` through unchanged. Deliberately chosen over fail-loud despite the run-log `completed`-masking trade-off; rationale and precedent recorded in Phase 2. |
| **R5** | This plan misread the vendor. | Phase 0.2 re-reads the pinned `inngest@3.54.2` files before any edit; every claim cites a named path. If the version differs, halt. |
| **R6** | Someone reads this PR as "the observability class is fixed." | AC10 forbids that claim in the PR body; Phase 4 records the corrected premise on #6703, which stays open. |

## Out of Scope (tracked, NOT implemented here)

| Item | Tracker | Note |
| --- | --- | --- |
| PreToolUse hook blocking `gh issue close` on unverified follow-through issues | #6703 item 1 | Remains deferred. |
| Wiring the Inngest client `logger` to shared pino | #6703 item 2 | **Premise corrected by this PR** (Phase 4), item stays open. Not implemented — it does not fix the crash and regresses INFO traversal. |
| Broadening `EXPECTED_TOGGLE_RECORDS` to a type-aware assertion | #6703 item 3 | Remains deferred. |
| Intermittent soleur.ai apex 404 | #6728 | Separate tracker. |
| v2 self-heal auto-invoke + drift/apply freeze-lock | #6677, ADR-125 | Deferred by CTO ruling 2026-07-18. |

---

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/
  placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** Filled
  above with a concrete artifact, a concrete (nil) exposure vector, and an explicit
  threshold.
- **`enabled` being `false` is not `enabled` being `undefined`.** This whole plan exists
  because a plausible-reading causal chain ("`ProxyLogger.info` starts with
  `if (!this.enabled)`, and `enabled` only flips true in `beforeExecution()` — therefore
  the TypeError") is a **non sequitur** that survived into an issue body and a task brief.
  The gate returning early and the gate throwing are different facts. When a hypothesis
  names a specific expression, read the expression's *declaration* (is the field
  initialized?) before accepting it.
- **Wiring a `logger` option to an SDK does not bypass the SDK's wrapper.** `Inngest.js:673`
  wraps whatever you pass. Before adopting "configure X instead of Y" as a fix, grep the
  vendor for the construction site and confirm the configured value actually reaches the
  failing expression unwrapped.
- **Vector's filter keeps non-JSON lines.** `vector.toml:87-96` returns `true` when
  `parse_json` errors. So `console.*` output (unstructured) traverses while pino INFO
  (JSON `level: 30`) is dropped. Any claim of the form "X won't reach Better Stack because
  of the `level_int >= 40` filter" must first establish that X *is* JSON.
- **Typecheck is `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`**, never
  `npm run -w apps/web-platform typecheck` (repo root declares no `workspaces`). Tests are
  **vitest**, never `bun test` (`bunfig.toml` blocks discovery).
- **Arrow closures are the cheapest way to kill a receiver-loss class.** Before reaching
  for a type-level detector, ask whether a ~20-line bind at an existing boundary makes the
  bug impossible. Detection has holes and needs maintenance; elimination has neither. This
  plan's first draft got that backwards and three reviewers had to say so.
- **A hand-written ctx shim is not checked against the SDK.** 65 files register handlers via
  `as unknown as Parameters<typeof inngest.createFunction>[2]`. Any guarantee expressed as a
  constraint on `HandlerArgs` is a *convention*, not a contract — the compiler never
  compares it to what inngest actually passes. Worth a `SOLEUR-DEBT:` marker; out of scope
  here.
- **(Rejected-option knowledge, kept because it is easy to re-derive wrongly.) `TS2684`
  fires at the CALL SITE, not at the extraction.** `const f = obj.method` is
  always legal even with a `this` parameter; only `f(...)` is the error. Any
  `@ts-expect-error` guarding receiver loss MUST sit on the invocation line — on the
  extraction it is an unused directive that fails `tsc` permanently. Verified by compiling
  a fixture, not by reasoning; the first draft of this plan got it wrong.
- **(Rejected-option knowledge.) A `this`-parameter guard depends on `strict: true`** and
  is erased by widening to a plain function type — so `p.catch(logger.error)` and
  `setTimeout(logger.info, 0)` pass it silently while crashing identically at runtime. If
  anyone revisits the detector approach, that is the boundary to measure first.
- **A test fake that is an object literal cannot reproduce a receiver-loss bug.**
  Object-literal methods have no `this` dependency, so an extracted reference works fine
  against the fake and throws only in production. #6705 got this right with a
  `ProxyLoggerLike` **class**; T3 preserves that shape deliberately.
- **The crash being already-fixed is not a reason to ship nothing, nor a reason to ship
  the prescribed fix anyway.** The honest residual is the unguarded type contract. Do not
  let "there must be something to fix here" pull the prescribed `client.ts` edit back into
  scope.
