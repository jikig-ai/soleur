---
date: 2026-07-30
category: workflow-patterns
module: knowledge-base/operations, knowledge-base/finance
problem_type: logic_error
issue: 7086
tags: [universal-negative, sibling-mechanism, shape-vs-truth-acs, correction-pr, telemetry-markers]
---

# One blocked mechanism is not a blocked capability — and shape-ACs cannot catch a false claim

## Problem

PR #7086 existed to fix two expense rows that described mechanisms which no longer
existed. It shipped a **new** false claim into the same financial records, and every
local signal went green over it.

The rows asserted, in bold:

> **No fleet-wide figure exists and none is derivable from a source this repo can read.**

That is a **universal negative over a set of mechanisms**. It was written from evidence
about exactly one of them.

## Root cause — the sibling-mechanism trap

Research found `cron-anthropic-cost-report` and its `SOLEUR_CLAUDE_COST_DAILY` marker,
and correctly established that it is blocked: the Anthropic Admin Cost & Usage API
requires a team organization, this org is an individual account, so `ANTHROPIC_ADMIN_KEY`
is un-mintable (#6297) and the cron self-reports `key-missing` indefinitely.

All true. The error was the next sentence, which generalized from that one mechanism to
the capability.

`apps/web-platform/server/claude-cost-marker.ts` defines **two** markers, 47 lines apart:

| Line | Marker | Scope | Needs admin key? |
|---|---|---|---|
| 70 | `SOLEUR_CLAUDE_COST` | **per-run**, emitted by `_cron-claude-eval-substrate.ts:1027` on every child exit with `cost_usd` + `source: cron:<name>` | **No** |
| 117 | `SOLEUR_CLAUDE_COST_DAILY` | org-total, Admin API | Yes — blocked |

The per-run marker had been live since 2026-07-09 (ADR-108), and its ClickHouse query was
already committed in `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`.
ADR-108 §Context even records **~$430/mo** on the shared key — a fleet-scale figure the new
row asserted did not exist, ~29× the `$15.00` it carried forward.

**Why finding one made me stop looking:** a near-identical name is the highest-risk shape.
`FOO` and `FOO_DAILY` read as *the same thing at two cadences*, so locating either feels
like locating the mechanism. It is precisely when the names are similar that enumeration
matters most.

## Key insight

> When research finds one mechanism for capability X blocked, that is evidence about **that
> mechanism**, not about **X**. "No source can do X" is a universal negative over a SET and
> requires enumerating the set.

Before writing any *not obtainable / not derivable / no way to* claim:

```bash
# grep the DEFINING file for siblings — not the codebase for the name you already have
grep -n "SOLEUR_CLAUDE_COST" apps/web-platform/server/claude-cost-marker.ts
```

Two occurrences with different suffixes is the tell. This is the same family as the
documented *"a claim quantified over a set sampled once"* class
(`2026-07-17-every-hole-was-a-claim-quantified-over-a-set-sampled-once.md`) — here the set
is mechanisms rather than fixtures.

## The second insight — shape-ACs cannot catch a false claim

Everything passed:

- **10 acceptance criteria** — all green
- **`scripts/test-all.sh`** — rc=0, 235/235 suites
- **`expenses-verify-by-check.sh`** — 26 markers, 0 anomalies
- **A premise-validation table** with live `gh`/`git` evidence per row

Every AC tested the new prose's **shape**: grep counts, marker presence, file-path
boundaries, "0 hits for the old filename". Not one tested whether the new prose was
**true**. A correction PR can satisfy an entire shape-AC suite while asserting a falsehood,
because the ACs are checking that the *old* claim is gone — never that the *new* one is
supported.

**Rule:** a PR that replaces a claim needs at least one AC of the form *"every factual
claim the diff ADDS traces to a named line in a cited source"*. Absence-assertions
(`grep -c '<old>' == 0`) are necessary and never sufficient.

## Solution

An 8-agent review panel caught it; four agents converged independently. The fix:

1. Corrected the claim — the fleet **is** metered per-cron; only the **org-total** is blocked.
2. **Split the row** rather than book a known-wrong number:
   - `Anthropic API (cron-ux-audit)` stays in Product COGS at its narrow `15.00`
   - `Anthropic API (claude-eval cron fleet)` is a new **R&D** row booking `UNMEASURED`
3. Repointed the `verify_by` source from an Anthropic Console eyeball to the Better Stack
   query — the original violated `hr-no-dashboard-eyeball-pull-data-yourself`, which the
   very runbook being edited enforces in its opening paragraph.

### Why UNMEASURED beats a known-wrong number

`plugins/soleur/skills/operator-digest/SKILL.md` **reads `expenses.md`** and sums the
Recurring table's Amount for `active` rows into the founder's weekly digest. A wrong amount
propagates to a founder-facing artifact.

Status `unmetered` keeps the row out of that `active`-only allowlist. The digest then
**under-reports rather than mis-reports**, and every containing subtotal is printed as a
floor (`>=`).

> When a figure is genuinely unobtainable, an absent number with a floor-marked subtotal
> beats a known-wrong number sitting in a summed column. The prose caveat does not travel
> with the number; the number is what gets summed.

This also falsified the plan's `brand_survival_threshold: none`, whose stated reason was
"no user-facing surface". Raised to `single-user incident`.

## Prevention

- **Before any "not obtainable" claim:** grep the defining file for sibling mechanisms.
  Suffix-variant names (`_DAILY`, `_V2`, `_LEGACY`) are the highest-risk shape.
- **On a correction PR:** add an AC asserting every ADDED factual claim traces to a cited
  source line. Absence-greps alone will pass over a falsehood.
- **Before widening a row's scope in a ledger:** check whether the amount was measured at
  the old scope. Scope and amount must describe the same thing, or the row lies by
  construction.
- **Before declaring a records-only change low-risk:** grep for consumers
  (`git grep -l '<file>' plugins/ scripts/ apps/`). `expenses.md` looked internal and feeds
  a founder-facing digest.

## Session Errors

**Killed a sibling session's test run with `pkill -f`** — `pkill -f "bash scripts/test-all.sh"`
matched the identical process in another worktree, terminating a parallel session's suite
4,274 lines in. Recovery: the other session relaunched itself; its infra/terraform results
had already completed and survived. **Prevention:** the repo documents the *self*-match
variant of this trap; the **cross-session** variant is new. Kill by PID from the process
listing (`kill 424879`), or scope by `readlink /proc/<pid>/cwd` first. In a repo whose
documented workflow is parallel worktrees, `pkill -f` on a shared script name is never
correctly scoped.

**Misread `pgrep` self-match as liveness, twice** — `pgrep -f "scripts/test-all.sh"` matches
the shell running the `pgrep` itself, so the pattern always finds ≥1 process. Read as "my
run is alive" while it had been dead for hours. **Prevention:** never conclude liveness from
a bare `pgrep -f`; resolve each PID's `/proc/<pid>/cwd` and match the worktree.

**Trusted a background-task "exit code 0" three times** — the notification reports the
*wrapper's* exit, not the command's. Once it reported success while the suite had been dead
~3 hours with no `rc` file. **Prevention:** the rc **file** plus the runner's terminal marker
(`=== N/M suites passed ===`) are the only evidence. A documented class; this session is a
strong recurrence data point.

**A full-suite run died silently when `/tmp` was purged mid-run** — `/tmp` went 93% → 3%
during execution; sub-suites that hardcode `/tmp` lost their scratch, the run stopped, no
`rc` was ever written. **Prevention:** `export TMPDIR=/var/tmp` protects the runner's own
scratch but not sub-suites; treat a stalled log plus an absent `rc` as death, not slowness.

**Wrote a count from a raw file grep** — "21 Inngest crons" came from `grep -rl | wc -l`,
which counted a shared module, an event handler, two one-shots, a comment-only match and a
workspace-helper-only importer. Actual: **15**. **Prevention:** already documented
("counts written into the artifact must be derived from the as-written file"); recurrence
here was writing a count that *sounded* derived because a command produced it. The command
must count the thing the sentence names.

**Left stale references inside files I had edited** — `cost-model.md:167` and the runbook's
`:57` procedure still named the row I renamed, one of them eight lines from an edit I made.
**Prevention:** the documented fix is to sweep by **claim**, not by file; on a rename,
`git grep` the OLD identifier and classify every survivor before committing.

**Authored AC1 too broadly** (one-off) — asserted zero `scheduled-ux-audit.yml` hits across
all of `knowledge-base/`, which returns ~40 historical artifacts. Narrowed at /work with the
rationale recorded rather than silently. Correct handling of an authoring miss.

**`brand_survival_threshold: none` on a factual error** (one-off) — claimed "no user-facing
surface" without grepping for consumers. Caught by `user-impact-reviewer`.

## Related

- ADR-108 — Anthropic cost-attribution markers (the mechanism this learning missed)
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` — the committed query
- `2026-07-17-every-hole-was-a-claim-quantified-over-a-set-sampled-once.md` — same family
- `2026-07-20-i-swept-by-file-when-the-unit-of-truth-was-the-claim.md` — the sweep-by-claim rule
- #6297 (org-total, blocked), #5692 (pre-exhaustion alert)
