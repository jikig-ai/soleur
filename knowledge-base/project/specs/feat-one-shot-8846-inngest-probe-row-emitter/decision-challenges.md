# Decision Challenges — feat-one-shot-8846-inngest-probe-row-emitter

## Taste: name the shared selector lib for the class, not for this marker (CTO devex, plan-review)

- **Operator direction (default kept):** fix the listed #8846 consumers with a shared selector for `SOLEUR_INNGEST_SERVER_PROBE`.
- **Challenge:** name the lib `scripts/lib/betterstack-emitter-row.sh`, with a generic `def bs_emitter_row($tag; $prefix)`, so that the next marker lands in the same lib instead of a second one.
- **Why not applied here:** the generic def does not fit the liveness rows, whose `.message` is a parsed object rather than a string. Generalising also widens a P1 false-alarm fix into a class refactor.
- **Where it goes:** #8875 (the class-wide "select Better Stack rows by emitter" guard) re-evaluates the naming when that guard is built.

## Scope note: 6894 gets the predicate but no fixture harness

- **Operator direction:** fix `inngest-luks-cutover-6894.sh` and add a fixture in "each consumer's suite".
- **Reality:** the script's header says it was retired on 2026-09-21 under #8296 and that nothing runs it. It has no suite. It is kept only because deleting it would edit a plugin baseline, which fires a plugin release.
- **Resolution:** the predicate is fixed, and the census asserts it. No new harness is built for dead code.
