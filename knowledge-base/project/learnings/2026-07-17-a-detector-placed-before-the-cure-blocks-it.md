---
date: 2026-07-17
issue: 6589
pr: 6582
tags: [observability, terraform, ci, fail-closed, gate-design]
category: bug-fixes
---

# A detector placed before the cure blocks the cure

## The bug

#6589 makes `terraform destroy` reachable for `infra/sentry/**` (the apply used to be
`-target=`-scoped, so deleting a `.tf` block was a silent no-op and live monitors piled up
8 → 49). Alongside it, Phase 6 added **Class D orphan detection**: a live Sentry monitor
with no declaring `.tf` block. Class D was specified **fail-closed** — deliberately, because
every existing orphan class only `printf`s, so a printing-only Class D would be "a detector
wired to nothing".

Class D was implemented as `live AND not declared`. Against live state that set contains
exactly one member: `scheduled-ghcr-token-minter` — **the very orphan #6589 exists to
destroy**.

`apply-sentry-infra.yml` runs the audit **before** `terraform plan` (a deliberate ordering:
the 4-gate destination-controllability check must not be bypassable via `workflow_dispatch`).
So on the first apply after merge:

1. audit runs → Class D sees the undeclared live monitor → **exit 1**
2. the job fails → `terraform plan` never runs
3. the destroy never happens → **the monitor stays live and billing**

The detector blocks its own cure. The end state is byte-identical to #6074 — the incident
the whole PR exists to prevent — reached from the opposite direction, and now with a
red check to make it look like the system is working.

## The root cause is the DEFINITION, not the plumbing

Class D means *"Terraform can never reclaim this"*. `live AND not declared` is **not** that
set. A monitor **in state** with no `.tf` block is the opposite of unreclaimable: the next
full-root apply destroys it. That is the fix working.

The tell was in the error message the whole time:

> `ERROR: … (Class D). Terraform will never reclaim them — each bills $0.78/mo.`

That sentence is **false** for a monitor in state. The message was wrong *because the
definition was wrong*, and nobody noticed because the message was never evaluated against
the one case that mattered.

Correct: **`live AND undeclared AND not in state`**.

## Why it survived a careful implementation

The implementing agent mutation-tested 8 ways and every test was killed by ≥1 mutation. It
still shipped a deadlock, because **every mutation was of the code, and the defect was in
the specification**. Mutation testing proves your tests can detect changes to your
implementation. It cannot tell you the thing you implemented is the wrong thing.

The agent also ran an explicit blast-radius check and reported:

> "simulated against today's real state (49 declared == 49 live) → exits 0, zero markers.
> Merging this will not break the production workflow."

Live was **50**. The claim was confidently stated, specific, and wrong — and it was the
exact claim that would have caught the bug. One integer between "safe to merge" and
"wedges production".

**It was caught by running the real script against live state**, not by reading it:

```
$ bash apps/web-platform/scripts/sentry-monitors-audit.sh
=== AUDIT EXIT=1   <-- the apply job halts here, BEFORE terraform plan
SOLEUR_SENTRY_CLASS_D_ORPHAN: slug=scheduled-ghcr-token-minter …
```

## The generalisable rule

**When you add a fail-closed detector, find where it sits in the call graph relative to the
thing that fixes what it detects.** If the detector runs *before* the remediation, its
firing set must exclude everything the remediation is about to handle — otherwise the gate
is a deadlock, and it deadlocks hardest in exactly the state the feature was built for.

Ask three questions of any new fail-closed gate:

1. **What is in my firing set right now, live?** Not "what should be" — run it.
2. **Does anything downstream of this gate resolve a member of that set?** If yes, the
   member does not belong in the set.
3. **Is my error message true of every member?** A message that is false for one member is
   a definition bug wearing a copy-editing costume.

## The second-order bug: empty ≠ unknown

The first fix injected state via a bare env var, `SENTRY_STATE_SLUGS`. That **failed open**
on a real case: an **empty** state (Terraform tracks zero cron monitors → every live monitor
IS unreclaimable → must fail) is indistinguishable from **unset** (state never read → cannot
classify → must warn), because empty-string and unset are the same thing to
`[[ -n "${VAR:-}" ]]`.

So the strictest case silently took the most lenient branch.

Fixed with a **file path** (`SENTRY_STATE_SLUGS_FILE`): an empty *file* is unambiguously
"state is empty"; an absent *var* is "state unknown". A set-but-missing file is an error —
the caller believed it provided state, and degrading to the warn path would turn a broken
producer into a permanently green gate.

Found by testing my own fix rather than trusting it. The general shape: **when a variable
must express three states (known-nonempty / known-empty / unknown), a bare string can only
express two.** Reach for a file path, a sentinel, or a companion flag.

## What "wired to nothing" actually requires

The original instinct — Class D must exit non-zero or it is a detector wired to nothing —
was right, and is preserved. But "fail closed" is not a synonym for "fail always":

| state | verdict | why |
|---|---|---|
| unreclaimable orphan | **exit 1** | the thing Class D is for |
| pending destroy | exit 0 | the next apply reclaims it |
| empty state | **exit 1** | everything undeclared is unreclaimable |
| state unknown | exit 0 + `::warning::` | cannot classify → must not deadlock |
| state file set but missing | **exit 1** | no silent fallback |

The unknown branch is the subtle one. Failing there *feels* more rigorous and is actually
the deadlock: **a gate that cannot be correct should not be the one with teeth.** The
authoritative fail-closed run is the caller that can know — `apply-sentry-infra.yml`, which
inits Terraform first and injects the state half.

## See also

- `knowledge-base/project/learnings/best-practices/2026-06-14-short-circuit-guard-must-sit-after-the-recovery-it-gates.md`
  — the same shape one layer down: an early-return that amputates the recovery living
  inside the path it skips. This is that rule for *detectors* rather than *guards*, and
  the recovery is a whole downstream job rather than a function call.
- `knowledge-base/project/learnings/2026-07-15-narrowing-is-not-anchoring-and-a-documented-class-recurred-four-times-in-one-pr.md`
  — read-and-believed assertions; only mutation caught them. Here mutation was run and
  still missed it, because the defect was upstream of the code.
