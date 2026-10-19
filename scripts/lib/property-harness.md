# Property-style testing for `.test.sh` suites

The repo's shell corpus is example-based: every case asserts one hand-picked
point of an input domain. `scripts/lib/property-harness.sh` adds the missing
oracle class — a **seeded generated-input loop** that hunts for counterexamples
across a domain the author enumerates, with a replay story for every failure it
finds. It is the shell-side sibling of `fast-check` (the `apps/web-platform`
devDependency used by `test/**/*.property.test.ts`); the decision to sanction
both is ADR-293.

Reference implementation: `scripts/lib/legal-normalise-property.test.sh`
(generated-input idempotence + residue-freedom over `legal-normalise.sh`'s
`collapse`).

## The pattern

```bash
#!/usr/bin/env bash
set -euo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$REPO_ROOT/scripts/lib/<sut>.sh"
. "$REPO_ROOT/scripts/lib/property-harness.sh"

prop_init "<suite-name>"

i=0
while (( i < PROP_RUNS_ACTIVE )); do
  prop_iter; i=$PROP_ITER
  input=$(gen_input)            # seeded by the harness stream
  assert_property "$input"      # see "property shapes" below
done

# Anti-vacuity floor: never print PROP_PASS unless the loop actually ran.
if (( PROP_ITER < PROP_RUNS_ACTIVE )); then
  echo "property loop ran $PROP_ITER of $PROP_RUNS_ACTIVE cases — refusing to report green" >&2
  exit 1
fi
prop_pass "<suite-name>" "$PROP_ITER"
```

## Generators: the token-alphabet rule

Write `gen_input` as composition over a **token alphabet**: a fixed list of
concrete inputs (members of each LHS form the SUT transforms, plus benign
noise), chosen per case with `prop_pick` / `prop_rand` and joined into the
shape the SUT consumes.

**The alphabet MUST enumerate every transform the SUT applies.** A generator
that only produces inputs from 3 of a SUT's 30 rewrite rules tests a tenth of
the oracle. Enumerate the SUT's transform set mechanically — for a `sed -E`
chain, extract every `s|LHS|...|` pattern from the SUT body and build one
concrete token per pattern; for a parser, one token per grammar production.
Then include adversarial free text: whitespace-only lines, leading/trailing
blank runs, partial-prefix tokens, and literals that resemble but do not match
the transforms (suffix anchoring is a common non-idempotence class).

```bash
ALPHABET=(
  "(privacy-policy.md)" "(/legal/privacy-policy/)"   # each LHS transform
  "[https://soleur.ai]" "plain free-text line"
  ""                                                  # blank-line member
)
line_for() { prop_pick "$1" "${ALPHABET[@]}"; }
```

## Property shapes for shell

Three oracle classes cover most pure shell transforms. In order of increasing
strength (per the Trail of Bits property catalog — *no crash* is a floor, not
a property):

1. **Invariant / output contract** — every generated input yields output
   satisfying a predicate (`out` contains no `LHS` residue, ends in a marker,
   is sorted, …). Cheapest to write; asserts the contract, not a full oracle.
2. **Idempotence** — `f(f(x)) == f(x)`. For normalisers, linters,
   canonicalisers. Compare byte-for-byte (`[[ "$out2" == "$out1" ]]`).
3. **Round-trip / inverse** — `decode(encode(x)) == x`. For framed or
   serialised formats; pair with a metameric check (parse(parse-fail junk)
   must throw) so the property is not tautological.

When two implementations exist (TS + SQL twin, canonical + mirror), an
**oracle** property — `f_sut(x) == f_reference(x)` — outranks all three.

## Reproducibility (`PROP_SEED`) and the run budget (`PROP_RUNS`)

- Every run prints `PROP_SEED=<n>` at `prop_init`. On failure the
  `PROP_FAIL <label> seed=<s> iter=<i>` line gives the replay command:
  `PROP_SEED=<s> bash <suite>.test.sh`.
- `PROP_RUNS=<n>` overrides the default 100-case budget. Keep the default at
  ~seconds of CI time; run `PROP_RUNS=1000` locally when hardening a fix.
- **Streams are bash-version-specific.** `$RANDOM`'s generator is
  implementation-defined; a seed replays on the same host/bash, not across
  architectures or bash majors. Never assert cross-host seed equality.

## Counterexample → permanent regression fixture

When a property finds a counterexample, it is a found defect in either the SUT
or the property — triage first, then preserve the case forever:

1. **Triage.** A red property means one of two things: the SUT violates its
   documented contract (a real bug — fix the SUT, never weaken the property),
   or the property over-claims (e.g., asserting trim-stability a normaliser
   never promised — rewrite the property, and shrink the failing input to its
   minimal form first so the rewrite is informed). ToB's catalog calls the
   second failure the *tautology/vacuity* anti-pattern; a property that can
   only pass teaches nothing.
2. **Preserve.** Whatever the verdict, the shrunk input becomes a permanent
   named case in the suite (or a sibling example suite), labelled
   `# regression fixture: PROP_SEED=<s> iter=<i>` — the seed/iter records
   provenance, the pinned case makes the finding deterministic on every host.
   For the vitest side the convention is identical (`// regression fixture:
   fast-check seed <seed> path <path>`); see `apps/web-platform/test/README.md`.
3. **Never** pin `PROP_SEED` or `fc.assert(..., {seed})` in committed code —
   that freezes the corpus to one stream and silently narrows coverage. The
   pinned *case*, not the stream, is the fixture.

## Placement rules — a suite that runs nowhere stays green forever

Put the suite where `scripts/test-all.sh`'s `SUITE_GLOBS` already reaches
(`scripts/test-all.sh` itself warns: an unregistered suite "runs in zero
runners and stays green forever"):

| Suite subject | Home | Why |
|---|---|---|
| `scripts/lib/<x>.sh` | `scripts/lib/<x>-property.test.sh` | glob-registered; `source` edge makes diffs to the SUT select it |
| `.claude/hooks/<x>.sh` | `.claude/hooks/<x>-property.test.sh` | hook corpus glob; hook suites also need the "Adding a hook test suite" checklist in `.claude/hooks/README.md` |
| `plugins/soleur/**` | `plugins/soleur/test/<x>-property.test.sh` | plugin glob |

Anywhere else needs an explicit `run_suite` line in `scripts/test-all.sh` —
and `lint-orphan-test-suites.sh` will census-flag it if forgotten. Prefer
placement over registration edits: presence is the registration.

## Anti-vacuity obligations (non-negotiable)

- **Run-count floor:** assert `PROP_ITER >= PROP_RUNS_ACTIVE` before
  `prop_pass` — a generator that produces zero cases must never read as green.
- **Instrument self-test:** drive `prop_fail` once in a captured subshell and
  assert the `PROP_FAIL` marker + non-zero rc — the suite must prove its own
  failure channel works before its green is trusted.
- **Negative property control:** at least one case (or a dedicated probe)
  where a deliberately-wrong oracle is asserted to *fail* — e.g., run
  `collapse` output through a checker requiring an LHS residue and assert the
  checker rejects it.
- **Determinism receipt:** the suite is the last line to print
  `PROP_PASS ... seed=<s>` — CI logs then carry the replay token for any red.
