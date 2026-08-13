# ADR-187: A nested runner signals UNRESOLVED by exit-shape, and only from an observed rc

- **Status:** Accepted. True the moment the code merges — no soak window, no time-gated criterion.
- **Date:** 2026-08-13
- **Issue:** #7429. Sibling (same PR, different subject): #7402, #7523.
- **Relationship to ADR-177:** **extends** it. ADR-177 defines the taxonomy and the *top-level*
  exit contract, and explicitly delegated the wrapper-parity question to #7429. This ADR spends
  that delegation. It does not reverse anything in ADR-177; the re-affirmation that `3` stays
  top-level-only, and the correction of ADR-177's npm claim, are recorded in that file's
  2026-08-13 addendum rather than here.
- **Relationship to ADR-166:** **constrained by** it. ADR-166 forbids naming a cause the emitter
  did not measure. Decision 2 below is that constraint applied to exit codes: it is the whole
  reason decision 1 is safe.
- **Relationship to ADR-178:** **constrained by** it, in the negative. ADR-178 governs shared
  bash primitives; this ADR deliberately does NOT create one. See §"Why the classifier is
  inlined three times".

## Context

`scripts/test-all.sh` classifies a suite that died on a signal as `[KILLED]` — UNRESOLVED, not
failed — and exits `3`. That classification is only reachable when the process `run_suite` forks
is *itself* the one that dies. Shell wrappers between `run_suite` and the suite flatten the exit
status to a boolean before the runner can see its shape, so a suite starved by contention and a
suite with a real regression arrive at the operator identically.

That indistinguishability is the expensive failure, not the lost suite: it is what teaches an
operator to discount red. On 2026-08-13 six concurrent full-gate runs on one 16-core box drove
load to 43.8, and every suite they starved would have reported as a plain `[FAIL]`.

Two in-repo wrappers absorb the shape:

- `apps/web-platform/infra/run-registered-suites.sh` — returns a plain `1`;
- `.github/scripts/test/run-all.sh` — `if ! bash "$t"; then FAIL=1; fi` discards `$?` by construction.

A third wrapper (the webplat `npm run test:ci` registration) was recorded by ADR-177 as the most
consequential absorber. **That was measured wrong.** See the ADR-177 addendum: npm propagates
`137`/`143`/`130`, including through the full `bash → npm → sh → vitest → workers` chain under a
SIGKILL of the largest-RSS node. It is struck from the absorbing set.

## Decision

### 1. A nested runner that observed a signal-killed child, and no assertion failure, exits with that child's signal-shaped rc (`128+N`)

`run_suite` then classifies it `[KILLED]` with **no change to the classifier**. The nested runner
participates in the existing taxonomy rather than acquiring one of its own.

This is *within* ADR-177's declared semantics, not a lie about the wrapper. ADR-177's own
classification rule states that `$?` cannot distinguish a signal death from a deliberate one, and
the rendered `[KILLED]` line already says "exit $rc is also what a suite calling exit($rc)
reports". The marker has always meant **signal-shaped** — never "was killed by". A wrapper
re-emitting a shape it observed is therefore making exactly the claim the marker already encodes.

Precedence, where a run has both: a real assertion failure **dominates** a terminated suite. A run
carrying both a `[FAIL]` and a `[KILLED]` is a failing run, and reporting it as merely
"terminated" would hide the failure the operator can act on.

### 2. A nested runner may exit `128+N` only for an `N` it DIRECTLY OBSERVED in a child's `$?`

It must never synthesize a signal shape from an inference — a wall-clock guess, a log scrape, an
"it probably OOMed".

This single sentence is what keeps decision 1 honest. Without it, "exit the signal shape"
degrades into "fabricate a plausible one", and the marker stops meaning anything — which is the
exact defect ADR-177 exists to prevent, reintroduced one layer down.

It also decides a case that would otherwise look like an oversight. Where a wrapper genuinely
cannot recover a per-child rc — `xargs` absorbing a dead shim and returning its own `125`, with
no `.meta` written — **mimicry is unavailable by construction**, because there is no observed rc
to re-emit. The honest options there are a discriminator on the absorbing layer's own exit code
or a file-backed sideband; inventing a signal number is not among them.

## Consequences

### Why the classifier is inlined three times rather than shared

ADR-178 would ordinarily push a repeated primitive into `scripts/lib/`. It is **not** applicable
here, and the reason is measured rather than stylistic:
`apps/web-platform/infra/run-registered-suites.test.sh:586` sandboxes its subject with
`PRISTINE="$MUTDIR/pristine.sh"; cp "$SUT" "$PRISTINE"` — a **single-file** copy. A sourced lib
would be absent from that copy, the runner's degradation path would fire, and every `[KILLED]`
assertion in the mutation battery would silently exercise the fallback instead of the classifier.
That is ADR-177 §A3's constraint, and it binds this file.

Duplication under a pin is the lesser evil against a guard that certifies the wrong code path.
The pin is `scripts/suite-exit-class-parity.test.sh`.

**The pin could not be what was first specified, and the reason is worth recording.** The plan
called for a single assertion that the classifier is byte-identical across all three files. It is
not, and should not be: the infra runner's call site already counts every non-zero child, so it
needs a **boolean** "is this rc in the killed subset?", while the other two classify a bare rc and
need a **tri-state** `ok`/`killed`/`failed`. Forcing one shape on both call sites would add
adapter code at one of them — a third thing to drift. So the pin asserts byte-identity only where
the shape is genuinely shared (`test-all.sh` ↔ `run-all.sh`) and **behavioural** agreement across
all three over the rc domain. The behavioural arm is the load-bearing one: it catches a change to
one classifier's *logic* in a file whose body was never expected to match the others byte-for-byte
— which a byte comparison is structurally blind to.

**A measured aside the pin exists to keep true.** The `<= 192` bound present in the tri-state form
and absent from the boolean form produces no disagreement: for rc 193..255 the `kill -l` operand
is 65..127, and on this shell `kill -l 65` exits **1**, so the preceding failure branch already
rejects them. That also makes the `[[ -n "$name" ]]` guard unreachable-as-decider here — mutating
it out survives every ordinary row. It is still correct to keep, because POSIX does not require
that exit status; the pin therefore synthesizes a permissive shell (shadowing `kill` to return
0-with-empty) so the guard is on the decision path in at least one arm, with a fixture self-check
asserting the shadow actually took effect. Without that arm the guard is untested in both files
and could be deleted from either with every suite green.

> **Recorded because it was got wrong first.** An earlier revision of this decision asserted that
> `run-registered-suites.test.sh` does *not* sandbox via single-file `cp`, citing `:21` and `:614`
> (the `SUT=` indirection), and concluded §A3 does not bind — inverting the entire rationale while
> reaching the same conclusion. The original probe grepped `cp .*TARGET|SUT=|mktemp -d`, a pattern
> that cannot match `cp "$SUT"`. The grep manufactured the answer. A decision that lands correctly
> on a stated-wrong reason is worse than a wrong decision, because the next engineer will read the
> reason and act on it.

### `RED` is a superset, and `killed` is derived from it

In `run-registered-suites.sh` the parallel child already emits `RED` for *any* non-zero rc, so a
signal-killed child is **already counted**. A naive "killed branch" added beside it is dead code:
any precedence of `RED>0 → exit 1` fires in every case the killed branch would. `killed` is
therefore derived as a subset and `failed=$(( RED - killed ))`.

The count must be taken in the **parent**. The `.meta` read loop lives inside a function called
within a `{ … } 2>&1 | sed …` pipeline, and a pipeline is a subshell: any counter incremented
there evaporates at the closing brace.

### The summary line does not change

`=== registered infra suites: N passed, N failed, N unaccounted (of N) ===` has two byte-exact
consumers (`run-registered-suites.test.sh` T6v and
`plugins/soleur/test/main-health-monitor-workflow.test.sh:554,571`). Adding a fourth number breaks
both. The new precision rides on a **separate line gated on `killed > 0`**, mirroring
`scripts/test-all.sh`'s own breakdown-line precedent, so clean output stays byte-identical.

The `${RED} failed` label consequently becomes imprecise when a suite was terminated. Correcting
the label would break both pinned consumers, so the gated breakdown line carries the precision
instead and a comment at the emit site records why.

### What this widens for the operator

`.github/workflows/main-health-monitor.yml` told the operator that only "the six suites this
runner starts via `bun`/`node` directly" could surface a signal-shaped exit. After this ADR the
set grows by **109** — the 98 infra suites behind `run-registered-suites.sh` plus the 11 fixture
suites behind `.github/scripts/test/run-all.sh`. (Both figures are re-derived from the as-written
tree, not from the plan: the fixture count is 11 rather than the plan's 10 because this same
change adds the propagation guard as an 11th suite and raises that runner's `MIN_SUITES` floor to
match.) Left unedited, that guidance would under-state
the search space on exactly the issue an operator reads when a suite is terminated. It is updated
in the same change.

## Alternatives Considered

**Adopt `3` as a nested contract too.** Rejected, and recorded as a deliberate re-affirmation
rather than a silent non-change. A nested runner emitting `3` would be indistinguishable from a
suite that itself chose `exit 3` for unrelated reasons — reintroducing at the nested layer exactly
the deliberate-versus-signal ambiguity ADR-177's classification rule exists to resolve. Decision 1
is *why* no reversal is needed: a nested runner never needs `3`, because it emits `128+N`.

**Extract the classifier to `scripts/lib/suite-exit-class.sh`.** Rejected on the single-file-`cp`
measurement above, not on taste.

**Generalise the `.meta` sideband to `TEST_TIMING_LOG` across all three runners.** Deferred. The
`.meta` files already are a file-backed per-suite-rc sideband — shipped by PR #7423 as
"telemetry" — so this ADR recognises the channel already load-bearing in the
`run-registered-suites.sh` domain rather than inventing one. What remains unearned is promoting
an ad-hoc telemetry file to a cross-runner contract. **Re-evaluation trigger:** a second runner
needing to report a killed suite it cannot exit-encode — i.e. the moment `run-all.sh` or
`test-all.sh` acquires an absorbing layer of its own.
