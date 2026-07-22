---
title: "The jq argv ceiling, and shell tempfile-cleanup ownership"
status: accepted
date: 2026-07-20
issue: 6736
supersedes: null
---

# ADR-129: the jq argv ceiling, and shell tempfile-cleanup ownership

## Context

Two shell-level defect classes surfaced together while draining follow-ups from
PR #6726. They are recorded in one ADR because both are "a shell idiom that
works at today's corpus size and fails silently as the corpus grows", not
because they share an enforcement mechanism — they do not, and an earlier draft
of this ADR claimed they did. The argv rule is enforced by per-site tests; the
ownership rules are enforced by a lint.

### The argv ceiling

`scripts/domain-model-drift.sh` died with `Argument list too long` after its
accumulators outgrew a `jq --argjson` binding (#6720, following a live HTTP 500
in #5523).

The governing limit is **`MAX_ARG_STRLEN` = 131,072 bytes for a SINGLE argv
argument** — not `ARG_MAX`, which is 2,097,152 on the build host. Measured by
bisect during this work: 131,071 passes, 131,072 fails with `E2BIG`. A payload
at ~6% of `ARG_MAX` therefore still dies, which is why "it is nowhere near
`ARG_MAX`" is not a defence.

**Item count is not a proxy for argv bytes.** 1,200 minimal rows measure 75,782
bytes — under the ceiling, and so passing on unmodified code. Bytes per row is
the parameter. A fixture built by row count alone produces a vacuous test.

### Cleanup ownership

Bash allows exactly **one** EXIT trap per shell; a second registration silently
REPLACES the first rather than chaining. Two distinct defects followed from
that, both reproduced during this work:

- **Subshell-append.** `scripts/content-publisher.sh` appended to its
  `_TMPFILES` cleanup array from inside `make_tmp`, which all six call sites
  invoke as `f=$(make_tmp)`. Command substitution runs the function in a
  subshell, so the append mutated a copy; the parent array stayed empty and the
  trap expanded to `rm -f ""`, owning nothing.
- **Trap replacement.** `scripts/skill-freshness-aggregate.sh` registered a
  tmpdir trap, replaced it with an `$OUT.tmp` trap inside the write block, then
  cleared cleanup entirely with `trap - EXIT`. The success path leaked the
  tmpdir on every report write.

A correction to the originating issue's framing, worth recording because it
changes where the harm lands: content-publisher's six sites each `rm -f` their
own tempfile on every return path, so a run that COMPLETES never leaked. The
trap covers only the window between `mktemp` and that `rm -f`. It is aborts
inside that window — on a long-lived Inngest host, with no runner teardown since
#4483 retired the GitHub Actions workflow — that accumulated to #6713's 9,470
files / 1.9 GB.

## Decision

**1. A jq binding whose payload grows with a corpus MUST use `--rawfile` /
`--slurpfile`, never `--argjson`.** File I/O has no argv limit. Bounded
bindings — those whose size is pinned by a hard cap such as `--limit 100`, an
explicit `.[0:20]`, or a `group_by` collapse — are left alone and carry a
load-bearing comment naming what bounds them. Converting them would be churn.

Reference implementation: `scripts/domain-model-drift.sh`. Fixture-adequacy
self-check: `domain-model-drift.test.sh` T20, which asserts the fixture actually
exceeds `MAX_ARG_STRLEN` so the test cannot silently degrade to vacuous.

**2. Cleanup arrays are appended in the PARENT scope, never inside `$( )`.**
Allocate in the helper, register at the call site.

**3. One owning trap per script.** Extend a cleanup function; never register a
second `trap … EXIT`.

**4. `mktemp` without an owning trap is gated for NEW ALLOCATIONS only.** The
existing population — 102 tracked `*.sh` files at time of writing — is ACCEPTED
rather than fixed file-by-file. Most are short-lived CI scripts where the leak is
bounded by runner teardown.

Two scoping details, both corrections made after the rule fired on correct code:

- **A `trap … RETURN` counts as ownership, not only `trap … EXIT`.** Per-function
  cleanup is the right lifetime for a harness that allocates per test case, and
  is better scoped than a process-wide EXIT trap. An EXIT-only anchor flagged
  `inngest-inventory.test.sh`, which carries thirty correct RETURN traps.
- **The unit is the ADDED LINE, not the touched file.** File-level scoping meant
  that editing any of the accepted files demanded you also pay off its
  pre-existing debt — `inngest-doublefire-probe.test.sh` carries 13 untrapped
  allocations on `main` and was flagged merely because this PR appended a test to
  it. A gate that taxes incidental edits is a gate that gets switched off.

**Upgrade trigger for the accept.** Fix a class-b file when it (a) starts
running on a long-lived host rather than an ephemeral runner, (b) allocates
inside a loop, or (c) allocates more than a trivial amount of data. Criterion
(a) is what made content-publisher.sh urgent: it did not change, its execution
substrate did.

## Enforcement, stated honestly

`scripts/lint-trap-tempfile-ownership.py` implements rule (a) subshell-append
repo-wide and rule (c) mktemp-without-trap on changed files, with a mandatory
reason-carrying escape hatch (`# lint-trap-ownership: ok <reason>`; a bare
marker is itself an error). `lint-trap-tempfile-ownership.highwater` ratchets
the accepted population so it can only shrink.

**This gate is ADVISORY, not blocking.** It runs in `ci.yml`'s
`lint-bot-statuses` job, and that job appears in NEITHER
`scripts/required-checks.txt` NOR the Terraform branch ruleset — so a PR can
merge with it red. It is therefore **not** stronger enforcement than an
AGENTS.md rule, and this ADR does not claim it is. Promoting it means adding the
job to `required-checks.txt` and the ruleset together, which is a deliberate
follow-up with merge-queue blast radius, not a side effect of this PR (whose
declared IaC scope is None).

The argv rule has no lint at all. It is enforced per-site by fixtures asserting
their own adequacy against the named constant.

## Consequences

- A new script that allocates a tempfile without a trap is flagged before merge,
  which is what the accept in decision 4 is fenced by. Without rule (c) the
  accept would be a pile nobody guards.
- Conversions are byte-verified rather than argued: each carries a fixture
  asserting it exceeds `MAX_ARG_STRLEN`.
- Because enforcement is advisory, a determined merge can still land a
  violation. Accepted knowingly; the alternative changes required checks for
  every PR in the repo.
- `MAX_ARG_STRLEN` is a per-host kernel constant. It is written NAMED at every
  use so a host with a different value is a one-line change, not a hunt for
  `131072`.

## Alternatives Considered

**An AGENTS.md rule instead of a lint — declined on budget.** `B_ALWAYS` measures
22,900 bytes against a 23,000 cap per `lint-agents-rule-budget.py` (the linter is
authoritative; a `wc -c` reading of 22,973/27 is not the same measurement). A
~50–60 byte pointer could land, barely. Declined on margin rather than on
principle.

**Repo-wide shellcheck — declined.** There is no `.shellcheckrc` and no
shellcheck CI job, and shellcheck has no rule for either defect. It would be a
large adoption for zero coverage of the actual classes.

**Converting the bounded argv sites — declined as churn.** `learning-retrieval-
bench.sh` is pinned by a hardcoded 7-element array and an explicit `.[0:20]`
(4,156 B, 3% of ceiling); `skill-freshness-aggregate.sh` collapses to one row
per skill via `group_by`; `audit-bot-codeql-coverage.sh` is bounded by
`--limit 100` (19,186 B). Comments naming the bound are what a human needs at
the moment of editing; a harness would synthesize ~30× the real fixture to prove
a bound nobody proposed removing.

**Rule (b), "trap replacement by superset" — rejected as incoherent.** Such a
rule must model subshell scope and intentional handoff, and gets both wrong:
`provision-hetzner.sh` is safe ONLY because its second trap sits inside `( … )`,
and `vendor-pin-integrity.test.sh` uses `trap - EXIT` CORRECTLY — the very shape
the rule would condemn. One analyzer cannot hold two contradictory models of
scope, and a rule that fires on correct code is disabled within a week. Both
shapes are pinned as negative fixtures. The trap-replacement defect is guarded
behaviourally instead, by the affected script's own suite.

**A broader rule (a) — rejected after it fired on correct code.** The first
draft required only "appends to an array inside a `$()`-invoked function" and
flagged three correct sites: `local curl_args` / `env_args` arrays built and
consumed within the same function, with no trap anywhere. Requiring the array to
be referenced by an EXIT trap, and not `local`-shadowed, is what separates a
cleanup array from an argument builder. Both false-positive shapes are pinned as
negative fixtures.
