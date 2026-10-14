---
date: 2026-08-06
issue: "#7332"
pr: 7336
category: test-failures
tags: [gates, fixture-space, json-contracts, toctou, observability]
---

# My gate would have fired on every input, and no unit test could see it

## The defect

The C4 producer's whole purpose is a **relationship-count gate**: a corpus of
component docs with no parseable dependencies renders elements, exits 0, validates
clean, and produces a diagram of disconnected boxes reported as success. The gate
catches that and reports `degraded`.

It shipped reading the wrong JSON key. likec4 exports `relations`; the code read
`model.relationships`, got `undefined`, and `Object.keys(undefined ?? {}).length`
resolved to **0 for every corpus**. So the gate fired on every input — including
the ones it was supposed to pass.

A gate that always fires is exactly as useless as one that never fires, and it is
*worse* than a missing gate, because the `degraded` verdict looks like the feature
working.

## Why 31 passing unit tests could not see it

`assessRender` — the gate itself — takes plain numbers:

```ts
assessRender({ diagnostics, elementCount: 3, relationshipCount: 0 })
```

Every test of it passed, and correctly. The bug was not in the gate; it was in the
**mapping from the artifact to the gate's inputs**, and no test touched that seam.
The fixture space had zero members for "a real `model.likec4.json`".

This is the fixture-space-cardinality class, in its least visible form: the missing
member was not an edge case of a property under test — it was an entire boundary
nothing quantified over. A mutation battery would not have found it either. Every
mutation of `assessRender` dies against the existing tests; the defect was upstream
of the mutated code.

## What actually caught it

Running the thing. One smoke invocation against a fixture corpus whose `.c4` file
visibly contained three edges, and the marker said `relationships=0`. The
contradiction between the artifact I could read and the number the program
reported is what surfaced it.

## The fix that generalises

Move the mapping into the library and pin it against a **real artifact**, not a
synthesized one:

```ts
export function countModelJson(json: string) { /* … model.relations … */ }
```

```ts
const realModel = readFileSync(".../model.likec4.json", "utf8");
expect(countModelJson(realModel).elements).toBeGreaterThan(0);
expect(countModelJson(realModel).relationships).toBeGreaterThan(0);
```

Deliberately **not** literal counts — those drift with every model edit and the
test becomes a chore. The claim under test is "both keys resolve", which a wrong
key cannot satisfy, and which survives any future model change.

## Rule

When a gate's inputs are **parsed out of an external tool's output**, the parse is
part of the gate. Unit-testing the decision function with hand-written numbers
tests the half that was never in doubt. Pin the field mapping against a real
artifact the repo already commits, and assert the shape resolves rather than the
values.

Corollary, and the cheaper habit: after wiring any gate, run it once against an
input you expect to **pass** and once against an input you expect to **fail**. A
gate observed in only one state is unverified in both. Here the same producer had
to show:

```
frontmatter corpus  → status=ok       relationships=3
prose corpus        → status=degraded relationships=0
```

## Two smaller findings from the same session

**A refuted hypothesis is a result — record it, do not "fix" it anyway.** I
suspected a `pipefail`/SIGPIPE fail-open in a pre-existing `printf … | grep -q`
and began patching it. Measured with a positive control (`yes | grep -q y` → 141,
proving the instrument works and `grep` was not the ugrep shim): the existing form
still returned 0, because `printf` is a bash **builtin** and bash does not
propagate SIGPIPE as 141 for builtins. The control is what made the measurement
trustworthy; without it, "rc=0" would have been indistinguishable from a broken
probe. Reverted — churn on an unproven premise is a cost with no benefit.

**A safety guard's own TOCTOU is worth more than a generic one.** CodeQL flagged
`existsSync(p) ? readFileSync(p) : null` (`js/file-system-race`) in the function
deciding whether a file was hand-edited. The generic finding is minor; here the
race window is precisely the state in which the producer overwrites an operator's
correction — the single outcome the guard exists to prevent. Fixed with a
single ENOENT-classifying read, and moved create-if-absent to `O_CREAT|O_EXCL`
(`wx`), which removes the window rather than narrowing it. Rate a race by what it
races **against**, not by the rule's default severity.

See also
[[2026-08-06-read-the-generated-artifact-not-the-generators-spec]].
