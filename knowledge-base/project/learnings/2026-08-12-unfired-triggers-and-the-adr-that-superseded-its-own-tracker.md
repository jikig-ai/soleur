# Learning: when a tracker's triggers have NOT fired, check whether the ADR that shipped with it already superseded the tracker's framing

## Problem

Entry was `/soleur:go 7454`. Issue #7454 is a consolidated `deferred-scope-out` tracker holding three
post-MVP follow-ups from the 2026-08-11 test-pipeline post-mortem, each with an explicit
"Re-evaluate when:" trigger.

The default routing for a bare `#N` issue is brainstorm — which would have created a worktree and
spawned a domain-leader fan-out across all three items. Two of the three were deferred on **verified
structural defects** (the issue says so explicitly, and one is marked "should not be attempted
again"), so that fan-out would have spent a parallel round re-deriving conclusions the post-mortem
had already recorded with evidence.

But "nothing to do here" was also wrong.

## Solution

**Step 1 — verify every trigger before routing.** Four `gh`/`git` calls, well under a minute:

| Item | Trigger | Verified state | Fired? |
|---|---|---|---|
| 1. Bounded parallelism | #7376 closes, OR the new bytes probe identifies the mechanism | #7376 **OPEN**, no closing PR, its follow-through sweeper's `earliest` was still a day away. Probe landed but had identified nothing | NO |
| 2. Session "already green" memo | An input model that can see untracked producer/consumer pairs like `_site/` | Unchanged since the parent PR merged ~19 h earlier | NO |
| 3. Multi-run advisory-lock experiment | Can run without a one-full-gate budget cap | Operator budget call; not sanctioned | NO |

The verification also surfaced a gate the tracker never mentions: **#7432**, a second open issue
recording the item-1 work as "deadlocked today" with two hypotheses still UNKNOWN. A tracker's own
list of blockers is not exhaustive.

**Step 2 — read the ADR that shipped alongside the tracker.** ADR-133's 2026-08-11 addendum contained
a section titled *"The sharper finding: the lock is not currently serialising anything"* — a run had
waited the full 900 s `TC_LOCK_TIMEOUT` and then proceeded while three sibling runs executed
concurrently. Charging 15 minutes per session, delivering zero isolation.

That finding was tracked in **no issue**. And the ADR explicitly reframed the tracker's own item 3:

> It is not "mutex versus admission control"; it is **why a mutex that proceeds on timeout is being
> relied on as a mutex**.

#7454 item 3 still carried the superseded framing. The tracker and the ADR shipped in the same PR,
and the ADR was the one that had moved.

**Outcome:** neither "route as asked" nor "close as not actionable" — scope the untracked finding
(new issue #7484, instrumentation only), leave all three deferrals intact, and comment the trigger
verification back onto #7454 so the next session inherits data rather than re-deriving it.

## Key Insight

**A tracker records what was true when it was written; the ADR that shipped with it can already have
superseded its framing.** When a deferred tracker's triggers have not fired, that is a reason to stop
re-deriving its items — not a reason to stop looking. Read the ADR/post-mortem the tracker cites: a
same-PR addendum is the single likeliest place for a finding that no issue tracks, because the
addendum is written *after* the issue body and nothing round-trips back.

**Corollary — an existence claim and a statistical claim have different evidence bars, and conflating
them freezes actionable work.** #7454 item 3 gates the lock work behind a heavy multi-run bar (≥3
single-runner runs, ≥2 at N=2, an adversarial run). That bar correctly guards a *statistical* claim
about replacing a mutex. The addendum's finding — waited the full timeout and proceeded while three
siblings ran — is an *existence* claim, settled at n=1. The heavy bar had been silently inherited by
a finding it was never written for, freezing work that needed no such evidence.

This is the complement of
[2026-06-10-model-economics-brainstorm-dormant-triggers-and-pricing-source.md](2026-06-10-model-economics-brainstorm-dormant-triggers-and-pricing-source.md),
which covers a trigger that *fired* while nothing was watching. Together: **always verify the trigger
state, in both directions, before letting a deferral bound the work.**

## Secondary findings

**A timeout constant is a claim about the critical section it must outlast.** `TC_LOCK_TIMEOUT=900`
guards a section of ~2,700 s uncontended / 5,787 s measured contended, so the mutex cannot serialise
by construction — and the effect is self-reinforcing, since every waiter that times out and proceeds
lengthens the holder's run. One `git log -S` showed the value entered with **no recorded derivation**,
and it is documented nowhere operator-facing. Cheap check, load-bearing result.

**Reduce a leader's proposed mechanism to its limit case before adopting it.** The CTO's option
"short-circuit acquisition when a sibling is detected" collapses to *never lock when locking would
matter* — i.e. deleting the lock. The salvageable version keys on holder **age**, which `tc_preamble`
already computes at `test-all.sh:626` but does not pass to `tc_acquire` seven lines later at `:633`.
The gap was plumbing, not physics.

**The corpus can already hold the decisive counter-evidence.** The learnings sweep surfaced
`2026-03-20-docker-healthcheck-start-period-for-slow-init.md` — three successive timeout raises
against a variable duration that never converged — which is precisely the "just raise the timeout"
option. Sweeping learnings *before* proposing approaches, not after, is what made that land as a
constraint rather than a regret.

**A forced framing should be recorded honestly, not rubber-stamped.** Policy forces
`brand_survival_threshold: single-user incident` on every brainstorm. The CPO's assessment was that
it is a poor fit for internal-only dev tooling nobody outside the build loop can reach, and said so.
Recording the dissent keeps the threshold meaningful for the blocks that genuinely qualify; silently
stamping it is how an always-on gate degrades into noise.

## Session Errors

1. **`git show main:<path>ADR-133*.md` returned nothing, silently.** `git show` does not expand globs
   in pathspecs — it resolved a literal missing path, and my `2>/dev/null` swallowed the error, so the
   read looked like "the ADR has no addendum." **Recovery:** `git ls-tree --name-only <ref> <dir>` to
   resolve the exact filename, then re-read. **Prevention:** resolve exact paths with `git ls-tree`
   before `git show <ref>:<path>`, and do not `2>/dev/null` a read whose *emptiness* you intend to
   treat as evidence. This one was nearly fatal to the session: the entire finding this brainstorm
   scoped lives in that addendum, and the first read said it wasn't there. Same class as the
   "empty query is not evidence of absence" rule in `go.md`'s Sharp Edges, applied to `git show`.

2. **`gh issue create --body-file <scratchpad path>` failed with `No such file or directory`.** The
   session scratchpad directory did not exist yet. **Recovery:** `mkdir -p`, then the Write tool
   (which creates parents). **Prevention:** use the Write tool for scratchpad files rather than a
   heredoc to an unverified path. One-off; no recurrence vector beyond the first scratchpad write of
   a session.

3. **Roadmap drift detected but not fixed in-session** (`STALE_STATUS|phase 4|roadmap=81o/200c|milestone=87o/209c`).
   **Recovery:** none attempted. **Prevention:** the reconcile script's own guidance routes this to
   the roadmap-review cron (which opens a reviewed PR), so a hand-edit here would have contradicted
   the canonical module. Recorded rather than silently skipped. Not caused by this session.

## Triage

| Item | Recurring? | Disposition |
|---|---|---|
| `git show` glob pathspec returning a silent empty | **recurring** — agents write `git show <ref>:<glob>` routinely, and the failure is silent | file-tracked → routed as a single bullet to brainstorm SKILL.md Phase 1.0.5 (domain-scoped; rule budget is in WARN so AGENTS.rules.md is out) |
| Unverified tracker triggers bounding a brainstorm | **recurring** | routed to brainstorm SKILL.md (same bullet) |
| Scratchpad dir missing on first write | one-off | noted only |
| Roadmap phase-4 drift | recurring, but pre-existing and owned by the roadmap-review cron | no action here |

## Tags

category: workflow-patterns
module: brainstorm, go, test-harness
