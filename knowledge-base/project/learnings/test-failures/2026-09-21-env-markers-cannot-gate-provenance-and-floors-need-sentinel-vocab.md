---
date: 2026-09-21
category: test-failures
module: apps/web-platform/infra
problem_type: logic_error
severity: high
pr: 8471
issues: [8372]
tags: [capability-gates, vacuity-floor, env-markers, test-seams, mutation-battery, sentinel-vocabulary]
---

# Learning: an env-var marker is a flag, not a credential — and a new floor's message is part of the oracle contract

Two independent mechanisms in the capability-gate PR (#8471 / #8372) produced the same
shape of lesson: a guard's *name* for what it checks and what it *actually* checks drifted
apart, and only a mutation pass that attacked the gate itself (not the SUT) caught it.

## Problem 1 — the static env marker was forgeable

The zot suite's S4 mutation battery spawns child runs with `CONFIG_JSON_OVERRIDE` and
`SOLEUR_ZOT_GUARD_NO_DIGEST=1` — both must be refused under CI or a bare `env:` line in
the workflow would green the suite on substituted bytes. The first implementation gated
the refusal on the absence of `SOLEUR_ZOT_S4_CHILD` — a static env flag the same `env:`
block can mint:

```yaml
env:
  CI: "1"
  SOLEUR_ZOT_S4_CHILD: "1"
  SOLEUR_ZOT_GUARD_NO_DIGEST: "1"
  CONFIG_JSON_OVERRIDE: path/to/substituted.json
```

Measured green: `rc=0`, 7/7 — acceptance never obtained, S4 battery skipped, three
independent review seats reproduced it. The guard's comment even named the adversary it
failed to stop.

**Fix.** `synth_case` mints a per-run nonce *file* inside its own mktemp dir and exports
the **path** as `SOLEUR_ZOT_S4_CHILD`. The child requires the path to sit inside a
`tmp.*`-named directory AND name a real file:

```bash
is_s4_child() {
  local v="${SOLEUR_ZOT_S4_CHILD:-}"
  [[ "$v" == "${TMPDIR:-/tmp}"/tmp.*/* && -f "$v" ]]
}
```

An `env:` block can mint any variable but cannot create a file; the `tmp.*` shape blocks
pointing at a pre-existing one (`/etc/passwd` — the naive `-f`-only check still accepts
it). Forging now takes a `run:` step planting a file — review-conspicuous, not silent.
Still not a trust boundary (workflow-edit authority already subsumes the suite), and the
comment says so honestly.

**Key insight:** when a gate checks "am I the suite's own child?", verify an artifact the
env cannot mint — a file inside a fresh mktemp dir — never the value of an env var alone.
`-f` alone is insufficient: `env:` can name files that already exist.

## Problem 2 — the floor's message is part of the mutant-oracle contract

Adding a conservation floor to the canary suite produced two meta-guard failures:

1. **Deferred-ledger growth (22/23).** A new floor-bearing file inside a deferred
   directory grew `guard-vacuity-floor`'s ledger 47→48. The ledger is shrink-only: the
   sanctioned move is a `PROMOTED_FILES` entry (per-file mutant pin), never a ratchet
   bump. ~11 prior promotions carry identical boilerplate.
2. **Mutant scored CONSTRUCTION, not FIRES.** `classify_mutant` maps `rc=2` to
   CONSTRUCTION unless the emitted message matches the sentinel vocabulary
   (`\[FATAL\]`, `FAIL(ED)?:`, `assertion floor`, `assertions ran`, `only [0-9]`, …).
   A bare `FATAL:` matches nothing — the floor tripped correctly (rc=2) and still scored
   as a construction failure. Rewording to `assertion floor/conservation — assertions
   ran=…` scored FIRES.

**Key insight:** the sentinel regex in `scripts/guard-vacuity-floor.test.sh` is a
cross-file vocabulary contract. Any new floor in a deferred directory needs (a) the
`PROMOTED_FILES` promotion and (b) a failure message containing a recognized sentinel
token — otherwise the meta-guard reads a working floor as unconstructible.

## Session Errors

- **rc read through a `| tail` pipeline** reported tail's exit, not the suite's —
  re-ran with output redirected to a file for an honest rc.
- **Bare `FATAL:` floor message** scored CONSTRUCTION instead of FIRES (Problem 2).
  Prevention: any new floor message must carry an oracle-sentinel token; check
  `classify_mutant`'s regex before choosing wording.
- **Deferred-ledger 47→48** on the new floor-bearing file. Prevention: a new floor in
  a deferred dir is a `PROMOTED_FILES` promotion, never `MAX_DEFERRED` — the ledger is
  shrink-only.
- **Stale `CONFLICTING` mergeable flag** while 3 commits behind main — clean rebase +
  `--force-with-lease`, verified by `merge_tree_rc=0`.
- **Nine `run_subagent` spawns failed** missing the required `title` field — retried.
- **`subagent_explore` has no exec/git tool** — design-pass agents reconstructed diffs
  by file comparison instead of `git diff`. Prevention: review-panel agents that must
  run git/suites spawn as `subagent_general` with explicit report-only instructions.
- **An edit dropped a comment line** — caught by re-reading the echoed snippet, restored.
- **First `is_s4_child` draft used `-f` only** — `/etc/passwd` would have satisfied it;
  self-caught and strengthened with the `tmp.*` shape (Problem 1).
- Forwarded: transient detached-HEAD subagent reading (verified false); exec cwd drift
  (explicit workdir re-runs); no Task tool in subagent context (sequential-fallback).

## Prevention

- Child/provenance markers: require a **file inside a fresh mktemp-shaped dir**, never a
  bare env value; state the residual trust boundary honestly in the comment.
- New assertion floors in deferred directories: `PROMOTED_FILES` + oracle-sentinel
  message, verified by running the meta-guard before commit.
- Report-only review agents that need `git`/suite execution: `subagent_general` with a
  report-only contract, not `subagent_explore`.
- Never read a suite's rc through a pipe tail — redirect to a file, capture `$?`.

## Tags
category: test-failures
module: apps/web-platform/infra
