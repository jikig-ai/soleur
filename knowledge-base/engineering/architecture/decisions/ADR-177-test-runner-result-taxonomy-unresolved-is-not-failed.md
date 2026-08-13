# ADR-177: A terminated suite is UNRESOLVED, not failed

- **Status:** Accepted. True the moment the code merges — no soak window, no time-gated criterion.
- **Date:** 2026-08-11
- **Issue:** #7424. Sibling (adjacent class, different subject): #7376.
- **Relationship to ADR-133:** **extends** it. ADR-133 documents the contention layer around
  `scripts/test-all.sh` and says nothing about what the runner's results MEAN, so a future
  engineer reading only the ADRs would find the taxonomy undocumented.
- **Relationship to ADR-166:** **constrained by** it. ADR-166 forbids naming a cause the
  emitter did not measure. That constraint is the reason this ADR stops at "signal-shaped"
  and never says "was killed by".

## Context

`scripts/test-all.sh` had exactly two result classes, `[ok]` and `[FAIL]`, and both
non-passing outcomes incremented one counter. A suite **terminated by a signal** therefore
rendered byte-identically to a suite that **failed an assertion**:

```
[FAIL] <suite-path> (<elapsed>ms)
```

Observed 2026-08-10 while shipping an unrelated PR. `tests/scripts/registry-gate-mutation-battery`
reported `[FAIL] … (560931ms)` on a run in which the battery **caught every mutation and left
no surviving mutant** — its own output shows every mutation through `E06` as `caught`, and the
block simply ends with bash's `Terminated                 "$@"` notice from the surviving
runner reporting its foreground child.

The suite file was byte-identical to `origin/main` and CI passed it on a clean runner, so it
was not a regression. But read from the runner's summary alone — which is how it is read — the
line says *the mutation battery guarding an irreversible destroy of production's sole image
store is failing*. That is the most alarming available reading, it was false, and the runner
supplied no way to reach the correct one.

The cost is not the lost run. It is that a terminated suite trains the reader to treat `[FAIL]`
on that suite as noise, so the next genuine failure is pre-discounted. On a gate authorizing an
irreversible destroy, that is the expensive direction to be wrong in.

### What was NOT determined, and why that matters here

**What sent the signal was never established.** A kernel/cgroup OOM kill, a wrapper wall-clock
timeout, and a stray signal from a concurrent session were not distinguished, and the
discriminators that would settle it (a kernel-log OOM line correlated to the pid at the kill
instant; the wrapper's own timeout diagnostic; the sender's audit record) were not captured and
are unavailable retrospectively.

This is load-bearing for the decision rather than a caveat on it. The defect being fixed is
*a reader reaching a confident conclusion the evidence does not support*. A fix that replaced
`[FAIL]` with an equally confident `[TIMEOUT]` would reintroduce the same defect one layer up.

**`$?` cannot distinguish a signal death from a deliberate one.** `bash -c 'exit 143'` yields
143, identical to a real SIGTERM. So even "this was signalled" is an inference, not a
measurement — which is why the rendered line reports the raw code as the measurement, `128+N`
as a *decode*, and states the ambiguity in its own text.

## Decision

**A suite whose exit status is signal-shaped with a decodable, non-empty signal name is an
UNRESOLVED result.** Concretely:

1. It gets **its own marker**, `[KILLED]`, distinct from `[ok]` and `[FAIL]` — both of which
   keep their exact current byte shape, because 11 learning files (21 occurrences) and four
   skills are anchored on `^\[FAIL\]`. Re-derive rather than trusting that count:
   `grep -rl '\[FAIL\]' knowledge-base/project/learnings/ | wc -l`. An earlier revision of
   this line said "roughly thirty", which reproduces at neither reading — the conclusion
   survives, the number did not.
2. It is **excluded from the failure count**. It counts as neither passed nor failed in
   `=== N/M suites passed ===`.
3. It is **named in the summary**, via a breakdown line emitted only when `killed > 0`.
4. It is surfaced as a **distinct non-zero exit code**, `3`.
5. **The runner never names what terminated it.** The register is "signal-shaped",
   "unresolved", "this runner did not measure what terminated it" — never "timed out", never
   "was killed by SIGTERM", never "OOM".

### Exit contract

```
0  every registered suite passed
1  >= 1 suite FAILED (an assertion verdict) — failure dominates when both are present
3  0 failures and >= 1 suite KILLED — UNRESOLVED, not measured, and NOT green
2  usage error (TEST_GROUP took an unsupported value) — predates this ADR
```

Exit `2` was unavailable for the new class because the runner already uses it for the
`TEST_GROUP` usage error.

### Classification rule

`rc` is `killed` iff **all three** hold: `rc > 128`, `rc <= 192`, and `kill -l $((rc - 128))`
returns a **non-empty** name. Each guard was measured on bash 5.3.9/Linux and two of the three
are individually necessary:

| Probe | Result | Consequence |
| --- | --- | --- |
| `kill -l 0` | `EXIT` (rc 0) | without `rc > 128`, rc=128 classifies `killed` with signal name "EXIT" |
| `kill -l 32`, `kill -l 33` | **rc 0, EMPTY output** (glibc-internal SIGCANCEL/SIGSETXID) | without the non-empty test, rc=160/161 render `= SIG` with a blank name |
| `kill -l 143` | `TERM` | `kill -l` **masks** values above 64, so it is not a validity oracle |

`kill -l` is therefore **not** a bounds check, and anyone "simplifying away the redundant
`> 128` test because `kill -l` already validates" breaks the classifier.

`<= 192` is retained as a legibility bound but is **NOT** load-bearing and no test pins it:
the call passes `kill -l $((rc - 128))`, so every rc in 193..255 yields an operand of 65..127,
which `kill -l` rejects — the non-empty guard already excludes that range. This is recorded so
a future reader does not go looking for the test that proves it.

A malformed `rc` (empty, whitespace, non-numeric) classifies **`failed`**, fail-closed. Without
that guard `(( rc == 0 ))` on `""` evaluates **true** and returns `ok` — the one class that
increments no counter and emits no warning.

An **unrecognized** class from the classifier is counted `failed` and warns. Without that
default arm it would increment neither counter, and `suites - failed - killed` would silently
count the suite as **passed**.

## Consequences

### `3` is a TOP-LEVEL contract only

A nested runner that returned `3` into `run_suite` classifies as a plain `FAIL`, because `3`
is not signal-shaped. Do **not** adopt exit 3 in a nested runner without revisiting this
decision. The classification suite pins this with an executed row.

### Wrapper absorption — the class is only visible when the process `run_suite` forks is the one that dies

> **SUPERSEDED IN PART — see the 2026-08-13 addendum (#7429), D1.** The `npm` row below is
> **false**: measured end-to-end, `npm` propagates `128+N` (rc 137 under a SIGKILL of the
> largest-RSS node in the real `test:ci` chain). The absorbing set is the **two shell wrappers**.
> The paragraphs below are left intact as the record of how the error survived; do not act on
> the `npm` claim or on the `exec node_modules/.bin/vitest run` remedy it motivates.

Three in-repo wrappers swallow the signal shape:

- `apps/web-platform/infra/run-registered-suites.sh` — returns a plain `1`;
- `.github/scripts/test/run-all.sh`;
- most consequentially, the **webplat** registration `env … bash -c 'cd apps/web-platform && npm run test:ci …'`, because `npm` does not propagate `128+N` for a signal-killed child.

So an OOM kill of the vitest/node process — the single most plausible instance of the class
this ADR is about — still surfaces as `[FAIL]`. This is a real limit, not a rounding error.
Parity is tracked as #7429. The deferral reason differs per wrapper, and an earlier revision
of this paragraph over-generalised it into a single coupling that does not exist:

- **Wrapper 1** (`run-registered-suites.sh`) is genuinely coupled to #7376, which owns that file.
- **Wrapper 3** (the webplat `npm run test:ci` registration) is coupled to nothing and is deferred
  for scope alone. `apps/web-platform/package.json` defines `"test:ci": "vitest run"` — a single
  command, no flags — so `exec node_modules/.bin/vitest run` would make the process `run_suite`
  waits on BE the vitest process, and a kernel OOM kill would render `[KILLED]`. The cost is that
  it bypasses the package's declared entry point, so it needs a drift pin asserting `test:ci`
  stays exactly `vitest run`. Since this is the wrapper named most consequential above, claiming
  it waits on #7376 asserts a dependency the evidence does not support.

Measured and worth recording: `env VAR=x bash -c '…'` **does** propagate, because `env` execs
rather than forks.

### The runner being killed is out of scope

If the signal reaches the whole process group, `test-all.sh` dies too and emits no marker at
all. This ADR covers only *suite died, runner survived* — which is what the incident showed.
The pre-existing discriminator (absence of the terminal marker) still covers the other case.

### The reader contract for `=== N/M suites passed ===` changes

`N < M` no longer implies at least one `[FAIL]`. The byte shape is preserved and the breakdown
line is gated on `killed > 0`, so clean output is byte-identical; but agent-facing docs that
inferred "failed" from "not passed" needed updating, and were.

### Agent-level readers had to change, because they terminate on parsed output

Two readers terminate on **parsed output rather than the exit code**, so the new class reaches
them even though the exit code is non-zero:

- `test-fix-loop` reads "zero failures → report success". A killed-only run parses zero
  failures. Untreated, an autonomous loop stages fixes and **reports success** on a run that
  measured nothing. Its iteration arithmetic is the sharper half: a suite that FAILED in
  iteration N and is KILLED in N+1 *lowers* the parsed count, reading as a fabricated
  improvement, and the rebound in N+2 reads as a **Regression** → `git reset --hard HEAD`,
  discarding real fixes on a signal artifact.
- `main-health-monitor.yml` builds both its failure flag and its issue **body** from one grep.
  A killed-only run would otherwise file an issue that names no suite at all.

## Alternatives Considered

| # | Alternative | Why rejected |
| --- | --- | --- |
| **A1** | Keep one bucket; only change the `[FAIL]` text for signal-shaped exits | Leaves the failure **count** wrong, so `N/M suites passed` still misreports and the exit code still says red for a result nobody measured. The count is what readers and monitors act on, so changing only the prose fixes the sentence and not the signal. |
| **A2** | Exit `1` for killed-only (no new exit code) | Free, but throws away the machine-readable half of the distinction — the conflation simply moves from the marker to the exit code. All consumers were measured binary zero/non-zero, so `3` is safe for every one; `scripts/zot-restart-loop-alarm.sh` is the in-repo precedent for a named multi-code contract. |
| **A3** | Put the classifier in `scripts/lib/suite-exit-class.sh` with its own auto-globbed unit suite | Measured fatal. `scripts/test-all-infra-coverage-notice.test.sh` builds its sandbox with `cp "$TARGET" "$out"` — a **single-file** copy. A sourced lib would be absent under test, the degradation path would fire, and every KILLED assertion would silently exercise the fallback instead of the classifier. Inlining also removes the degradation stub and a whole failure mode. |
| **A4** | A self-killing watchdog that aborts a suite at its declared budget (the issue's literal "fail with its own diagnostic") | Requires guessing the upstream killer's timing, which is precisely what was not measured, and trades a possibly-completing measurement for a guaranteed non-result. Adopted instead: **declare and report**, which delivers the attribution the item was asking for without self-inflicting the outcome. Recorded as a deliberate deviation from the issue's literal wording. |
| **A6** | Carry the class OUT-OF-BAND rather than on the exit code — a nested runner appends a `KILLED` row to `TEST_TIMING_LOG` (whose field 3 this change already widened) and `run_suite` classifies on `signal-shaped rc` ∪ `child declared killed` | Not adopted here, recorded because it is the one design that makes the taxonomy COMPOSITIONAL: that channel survives npm, `xargs` and `if ! bash`, so it resolves the top-level-only limit and wrapper absorption with one mechanism. Absence of the channel means "no killed", so it is fail-safe and byte-identical to today. The cost is real — three files must be taught to write it, and `TEST_TIMING_LOG` becomes a CONTRACT rather than ad-hoc telemetry; today nothing outside the runner parses it, which is precisely why widening field 3 was free. #7429 should spend that freedom deliberately rather than inherit it. |
| **A5** | Widen the existing `SIBLING_RUN_DETECTED` matcher to also cover directly-run suites | The two answer different questions — "is another full run in flight?" versus "is another suite in flight?" — and merging them would silently change what an existing `SIBLING_RUN_DETECTED` line means in every log and learning that cites one. A separate `SIBLING_SUITE_DETECTED` banner keeps both readable. |

## Addendum — 2026-08-11 (ADR-181): the exit contract gains a REFUSED class, and `2` widens

ADR-181 (relevance-gated suites) changes the contract this ADR defines. Recorded here because
`scripts/test-all.sh`'s `EXIT CONTRACT` block is cited as authoritative by
`plugins/soleur/scripts/grok-pre-push-gate.sh` and `plugins/soleur/skills/work/SKILL.md`, so a
contract change that lands only in the code leaves both pointing at a stale table. Nothing above
is edited — this appends.

```
4  REFUSED before anything ran — SOLEUR_SUBAGENT=1 without SOLEUR_ALLOW_FULL_GATE=1
2  ALSO: the relevance-predicate data file is missing (in addition to the TEST_GROUP usage error)
```

**Why `4` and not `3`.** They are opposite claims. `3` says a registered suite was terminated
and its coverage is therefore *unresolved* — the runner tried and could not measure. `4` says
nothing ran at all, deliberately, and nothing is unresolved: a spawned agent asked for the full
gate and was refused so it would not corrupt the lead's measurement. Collapsing them would make a
refusal indistinguishable from a killed suite for exactly the consumers this ADR exists to serve.

**Why the missing-data-file case reuses `2` rather than taking `5`.** Both `2` cases mean "this
runner cannot run" and neither is a verdict about a suite, which is the distinction this ADR's
taxonomy actually turns on. Every consumer is binary zero/non-zero, so a second usage-shaped code
would add a value nothing reads. The overload is documented rather than silent.

**Consumer impact: none beyond what this ADR already recorded.** Every consumer still blocks on
any non-zero. `grok-pre-push-gate.sh` reads `3` specifically; it does not read `4`, and a refusal
cannot reach it because the gate does not set `SOLEUR_SUBAGENT`.

## Addendum — 2026-08-13 (#7429): the npm absorption claim is falsified, and `3` stays top-level-only

Append-only. The body above is left byte-for-byte intact, including the paragraphs this
addendum corrects — a dated record is amended by appending, never by substitution, and the
superseded text is the evidence for how the error survived review.

### D1 — `npm` DOES propagate `128+N`. The wrapper-3 claim was wrong.

§"Wrapper absorption" names the **webplat** registration "most consequentially" absorbing,
"because `npm` does not propagate `128+N` for a signal-killed child", and concludes that an OOM
kill of the vitest/node process "still surfaces as `[FAIL]`". Re-measured 2026-08-13 on
npm 11.12.1 / node v22.22.2, against the **real** `test:ci` (`vitest run`), not a synthetic
`package.json`:

| shape | rc |
| --- | --- |
| `npm run test:ci` → SIGTERM to the spawned shell | 143 |
| `npm run test:ci` → SIGINT | 130 |
| `env VAR=x bash -c 'cd apps/web-platform && npm run test:ci …'` → SIGKILL | 137 |
| **the real OOM shape** — full `bash → npm → sh → vitest node → 15 workers` chain, `SIGKILL` to the largest-RSS node (268 MB, the process a kernel OOM killer selects) | **137** |

The last row is the one that matters: it is the exact scenario the body calls "the single most
plausible instance of the class this ADR is about", executed end-to-end rather than argued. npm
propagates the signal shape, so that case already renders `[KILLED]` and already exits 3.

**Consequences of the correction.**

- Wrapper 3 is struck. The absorbing set is **two** shell wrappers, not three.
- **The `exec node_modules/.bin/vitest run` remedy the body proposes is unnecessary**, and so is
  the drift pin it would have required (asserting `test:ci` stays exactly `vitest run`). Both are
  withdrawn. This matters beyond bookkeeping: the remedy bypassed the package's declared entry
  point, so the ADR was recommending a real cost to buy a property the toolchain already had.
- The body's measured note that `env … bash -c` propagates (because `env` execs rather than
  forks) is **re-confirmed** and stands.

**How the error survived.** The claim is plausible, it is the kind of thing npm has done in
older majors, and nothing in the original work executed it — the wrapper table was reasoned
about rather than driven. It then propagated into #7429's body as that issue's headline finding.
The re-probe cost under a minute. This is `cq-assert-anchor-not-bare-token`'s sibling for
claims: a wrapper's behaviour is a measurement, not a deduction from its category.

### D2 — `3` remains a TOP-LEVEL contract only (re-affirmed, not reversed)

§"`3` is a TOP-LEVEL contract only" was re-opened deliberately under #7429 and is **kept**. A
nested runner returning `3` into `run_suite` still classifies as a plain `FAIL`, because `3` is
not signal-shaped and `run_suite` classifies on shape. The nested runners therefore propagate
`128+N` — the shape — rather than adopting `3`.

Adopting `3` as a nested contract was rejected because it would make a nested runner's
"a suite under me was terminated" indistinguishable from a suite that itself chose `exit 3` for
unrelated reasons, re-introducing at the nested layer precisely the deliberate-vs-signal
ambiguity §"Classification rule" exists to resolve. ADR-187 records the resulting constraint:
classification is on **observed rc only**.

### D3 — the A6 status correction

The body's A6 deferral rested on a trigger that had **already fired** when it was written:
`xargs` *is* an absorbing layer, and `.meta` *is* the sideband. The tripwire now lives at the
shim (`xargs` reports **125** for a real signal versus **123** for a deliberate exit), which is
the only position where the two are distinguishable at all — at the fixture-suite position they
are byte-identical at every chokepoint (`rc=$?` 137, `xargs` 0). A canary placed there could
never have fired, which is the same vacuity class this ADR's taxonomy exists to expose.
