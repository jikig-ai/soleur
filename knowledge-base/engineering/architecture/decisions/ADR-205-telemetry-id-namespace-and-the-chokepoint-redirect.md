# ADR-205: A section prefix is a claim to corpus membership, and test telemetry is redirected at the runner chokepoint

- **Status:** Accepted
- **Date:** 2026-09-07
- **Issues:** [#7849](https://github.com/jikig-ai/soleur/issues/7849),
  [#7853](https://github.com/jikig-ai/soleur/issues/7853),
  [#7854](https://github.com/jikig-ai/soleur/issues/7854)
- **Ordinal note:** `origin/main` topped out at ADR-202, but ADR-203 and ADR-204
  were already claimed by pushed branches. A `main`-only check would have
  collided; the probe quantified over every `origin/*` ref.

## Context

Two defects filed a day apart turned out to share one missing idea.

`scripts/rule-metrics-aggregate.sh` exits 5 when it finds an emitted `rule_id`
that is not tagged in `AGENTS.md`. It carried **nine** hand-maintained exemption
stanzas and still exited 5, naming 23 ids. Every one of the 23 was a hook or
gate emitting its own telemetry — `guardrails-block-commit-on-main`,
`post-dispatch-watch-gate`, `git-commit-secret-scan`. None had ever claimed to
be an AGENTS rule. The gate was asking "is this id in the corpus?" when the
question it needed was "does this id *claim* to be in the corpus?"

Separately, three test suites were writing fabricated rows into the operator's
live `.claude/.rule-incidents.jsonl` because they drove real emitters without
setting `INCIDENTS_REPO_ROOT`. This was the **third** occurrence: `d0d3b5d68`
sandboxed one suite, a later sweep sandboxed twelve more, and both missed
siblings. The recurring failure was not any individual miss but the repair
shape — a per-call-site sweep, applied three times, leaking three times.

## Decision

> **A section prefix (`hr`, `wg`, `cq`, `rf`, `pdr`, `cm`) is a CLAIM to
> membership in the AGENTS corpus. An identifier that carries one and is neither
> a current rule nor a deliberately retired one is an orphan; an identifier that
> carries none is hook telemetry and is outside the corpus by construction.**
>
> **Test telemetry is redirected at the RUNNER CHOKEPOINT — the code that runs
> before a runner runs a test — never at the call site, and never by teaching
> production code to detect tests.**

## Consequences

### The namespace rule replaces an enumeration with a predicate

Nine stanzas become one clause plus a retirement lookup. The gate went from
`rc=5` with 23 orphans to `rc=0` with none, while an injected section-prefixed
id that is not retired still exits 5.

Measured support: **0 of 105** AGENTS ids lack a section prefix, so the
predicate cannot exempt a live rule. That is what makes this a namespace rule
rather than a heuristic.

The rule has a **third** case that the first analysis missed, recorded here
because it is the interesting one. A section-prefixed id can be legitimately
absent from the corpus for two different reasons: **retired** (admitted, then
removed — `scripts/retired-rule-ids.txt` is the record) and **never admitted**
(`cq-pencil-collapse-auto-recover`, which is tier-gated out under
`cq-agents-md-tier-gate` and is live). The second case is currently handled by a
single exact exemption. The durable repair is to rename that emitter literal to
an unprefixed id — permitted, because `cq-rule-ids-are-immutable` binds
`AGENTS.md` `[id: …]` tags via `lint-rule-ids.py` and not hook-telemetry
literals — and it is tracked as a deferral.

### The chokepoint rule fixes the repair shape, not one leak

Five chokepoints carry the redirect: both `bunfig.toml` preloads, the vitest
`globalSetup`, the shell prelude in `test-helpers.sh`, and the
`_git_fixture_env` import (the real chokepoint for `python3 -m unittest`, which
loads no `conftest.py`). `scripts/test-all.sh` and
`.github/scripts/test/run-all.sh` carry it as a belt.

This reaches a **directly invoked** suite, which is the spelling all three
measured leaks occurred under, and it needs no branch in production hook code.

Two alternatives were considered and rejected. A tripwire inside `incidents.sh`
refusing to append when the process "looks like a test" puts test-awareness into
production code, where a false positive darkens real operator telemetry — the
one failure this system cannot tolerate, since the ledger is read as evidence. A
per-call-site sweep is the shape that already failed three times: partial
isolation greps identically to full isolation, so a static check for the
variable's name reports clean on a leaking suite.

### Fail-loud is chosen per-layer, not globally

The git tripwire ABORTS at these same five points; the telemetry redirect
EXPORTS. The asymmetry is deliberate. An inherited git-location environment is a
broken **entry point** that a person must fix, and naming it is the entire value.
An unset telemetry sink is the **default** everywhere outside a test — there is
no entry point to name, so there is nothing to fail loudly about, only a default
to set. Where a sandbox genuinely cannot be created, every layer aborts:
an unset `INCIDENTS_REPO_ROOT` is not a degraded sandbox, it is the operator's
real ledger, and an EMPTY value is indistinguishable from unset to
`_incidents_repo_root()` while still reading as "set" to a static check.

### One derivation, not two

`#7854` is the same idea in a third place. A hook decided whether it could find
a Claude process by walking `/proc`; its suite gated an end-to-end arm on its
**own** independent walk. Because the hook runs as a CHILD of the suite, the two
walks start one process apart and can always disagree by one hop — so under
lefthook's deeper tree the suite asserted an adoption that correctly never
happened, and failed the commit gate. The suite now asks the hook for its
verdict. Matching the traversal limit, which the issue proposed, would have left
the origins different and could not have fixed it.

**A fact needed by both a mechanism and its test is derived once, by the
mechanism, and read by the test.** Two independent derivations of one fact are
free to disagree, and the disagreement surfaces as a failure attributed to
whichever side is cheaper to blame.

## Verification

- Orphan gate: `rc=5`/23 → `rc=0`/0; injected non-retired prefixed id → `rc=5`.
- Ledger: `gdpr-gate-self-test.test.sh` 8 rows/run → **0**, suite still 13/13.
- Ancestry: RED at lefthook depth → GREEN; mutation battery `killed=12 survived=0`.
- Chokepoints: each of the five produces an absolute root on a bare invocation;
  the vitest arm verified to reach worker children under both `pool: "forks"` and
  `WEBPLAT_TEST_USE_THREADS=1`.
