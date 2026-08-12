---
title: The full suite is the merge gate, not the implementation-exit gate
status: active
date: 2026-08-12
related_adrs: [ADR-133, ADR-177, ADR-181]
---

# ADR-183: The full suite is the merge gate, not the implementation-exit gate

## Context

`scripts/test-all.sh` ran twice per PR: once at the `/work` Phase 2 exit, and again at `/ship`
Phase 4 after review fixes. Measured on PRs #7344 / #7343:

| Signal | Measurement |
|---|---|
| Touched-file baseline on a 24-file diff | 224 assertions in ~90 s |
| Full run's infra runner alone | 573 s |
| Harness reaps of that run | 4 |
| Time serialised behind a sibling worktree holding the advisory lock | 2694 s |

The expensive thing is not running tests twice — it is running 460+ suites twice for a small diff.
Because `test-all.sh` takes a repo-wide advisory lock (ADR-133), the second run also doubles lock
contention across every concurrent worktree, so the cost is paid by sessions other than the one
running it.

**The issue that prompted this change (#7352) justified it on a false premise, and the correction
makes the change safer rather than weaker.** The issue argued the local runner had to move because
it *was* the merge gate. It never was. CI's required `test` context (ruleset 14145388) aggregates
three `test-all.sh` shards on the PR head and is what actually blocks merge. Reordering a *local*
checkpoint therefore cannot change what reaches `main` for anything that context covers.

## Decision

**The full `test-all.sh` battery runs once per PR, at `/ship` Phase 4. The `/work` Phase 2 exit runs
only the `TEST_GROUP` shards the diff touches.**

The shard is not a new mechanism: `TEST_GROUP` already exists and is already how CI shards. That
matters more than it sounds — a shard keeps the contention preamble
(`SIBLING_RUN_DETECTED` / `SIBLING_SUITE_DETECTED` / `LOW_TMP_HEADROOM`), the `EXIT CONTRACT`, the
terminal `=== N/M suites passed ===` marker, the rc file, and ADR-177's `rc=3` UNRESOLVED class. A
hand-derived command set (`vitest run --changed` plus a `git grep` per changed symbol) was specified
first and cut: it has none of those, and it has an **empty-derived-set** state that fails open.

### The two ceilings

1. **`/ship` Phase 4 stays `TEST_GROUP=all`.** This is the load-bearing constraint of the whole
   change. Sharding it for speed would silently delete the only gate the registered
   `apps/web-platform/infra/` suites have, because **no required status check runs that shard**.
   Pinned by `plugins/soleur/test/fullsuite-merge-gate.test.ts`, whose mutation is *sharding* the
   command, not deleting it — deletion is the easy mutation and the wrong threat.
2. **Projects with no CI-enforced full-suite gate keep the battery at implementation exit.** Four
   prescriptions in `work/SKILL.md` are project-agnostic and ship to self-hosted plugin users whose
   repos have neither ruleset 14145388 nor `scripts/test-all.sh`. For them the reordering would
   remove a gate and add none, so it does not apply. The detection ladder is a bounded local read
   that assumes no `gh` auth, no GitHub remote and no ruleset API, and **its default under
   uncertainty is the full battery** — the relaxation is the privileged branch and is never reached
   by assumption.

## Consequences

### What does not change

What reaches `main` is unchanged for every class the required `test` context covers. That context
runs the same three shards on the PR head regardless of anything either skill does locally.

### What this costs, stated plainly

The pre-review full run's unique value was cross-file breakage the touched-shard set cannot see:
orphan suites (a sibling file covering the same script, under a different name stem) and a suite
outside the diff's shards asserting on a literal the diff changed. That class now survives into
review, where it can add noise to the review agents' mutation work, and is caught at the merge gate
instead. Accepted: identical gates, better ordering.

### Why the pre-review gate was not dropped entirely

Three reasons, two of which fired while measuring this:

1. **A red baseline voids the review.** Several review agents mutate and re-run suites; a red tree
   going in makes every mutation row noise. On #7344 a whole battery had to be discarded.
2. **Attribution.** Review fixes introduce bugs — one did on #7344, a bare `sweep_orphan_leases`
   call aborting cleanup under `set -e`. A green checkpoint before review makes a post-review red
   unambiguously the review's fault.
3. **Fail-fast economics.** Spawning 8-10 agents against code that fails its own tests wastes the
   most expensive step in the pipeline.

### The loss of reap redundancy

With two full runs, a harness-reaped Phase 2 was recovered by Phase 4. With one, a reaped Phase 4
has no second chance, and "unresolved" under ship-time pressure resolves to "ship anyway" more often
than to a 45-minute re-run. Mitigated in prose rather than mechanism: ship Phase 4 states that a
reaped run is UNRESOLVED per ADR-177's three-way split and must be re-run, never shipped on.

### Revert tripwire

If this bites — if escapes start reaching the merge gate that the Phase 2 full run would have caught
— put the unconditional Phase 2 run back. One line, one place. A quantified tripwire (`N escapes in
M PRs`) was drafted and cut: an unspecified `N` with deferred counting is not falsifiability, and
automated escape-rate measurement needs cross-PR data that is its own work-stream.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| **Drop the pre-review gate entirely** | Voids review agents' mutation work against a red tree, destroys post-review attribution, and spends the most expensive pipeline step on code that fails its own tests. See the three reasons above. |
| **Derive a command set per diff** (`vitest run --changed` + `git grep -l '<symbol>'`) | Loses the contention banners, the `EXIT CONTRACT`, the terminal marker, the rc file and the `rc=3` class. `vitest run --changed` with zero matches exits 1, indistinguishable from a real red by exit code. Has an empty-derived-set state that fails open — the plan's own dogfood diff landed in exactly that state. |
| **Pin a `FULLSUITE_SHA` at Phase 4 and re-run on drift** | The Bash tool persists only CWD between calls, and Phase 4 to Phase 6.4 spans ~1000 prose lines and dozens of tool calls, so the variable cannot survive. Combined with a fail-closed-on-unset rule it would have failed on 100% of PRs and re-run the battery on every infra diff — reinstating the cost this ADR removes — while its own drafted mutation proof passed against the degenerate gate. |
| **Re-run the infra shard when the merging tree moves** | Protects one class CI already blocks (`terraform-target-parity.test.ts` in the `bun` shard feeds the required `test` context) and one that nothing blocks (R5 orphans — `lint-orphan-test-suites.sh` is advisory and does not scan `apps/web-platform/infra/` at all). Buys no property. |
| **Shard `/ship` Phase 4 too** | Ceiling 1. Deletes the only gate the registered infra suites have. Recorded here so a future optimiser finds the rejection instead of re-deriving the idea. |
| **Relax the four project-agnostic lines unconditionally** | Ceiling 2. Removes a gate and adds none for self-hosted users, during a live alpha measurement window. |

## The real infra gap is a ruleset gap

`apps/web-platform/infra/` is gated locally by exactly one `TEST_GROUP=all` run and by no required
status check: `infra-validation.yml`'s `infra-validate-required` job is absent from
`scripts/required-checks.txt` (verified: `grep -c` → 0). The correct fix is promoting it into that
file, `scripts/ci-required-ruleset-canonical-required-status-checks.json` and
`infra/github/ruleset-ci-required.tf` — already parity-guarded by
`plugins/soleur/test/required-checks-canonical-parity.test.sh` Test 1. That is a branch-protection
change and belongs in its own PR; folding it into a test-reordering diff would hide a merge-policy
change inside workflow prose. Tracked separately.

## References

- #7352 — the issue, including the operator decision of 2026-08-06
- PRs #7344 / #7343 — where the cost was measured
- ADR-133 — the advisory lock this change halves contention on
- ADR-177 — the UNRESOLVED (`rc=3`) taxonomy the reaped-run rule depends on
- ADR-181 — relevance-gated suites and counted declines, which reduces the cost of each run where
  this ADR reduces the number of runs
