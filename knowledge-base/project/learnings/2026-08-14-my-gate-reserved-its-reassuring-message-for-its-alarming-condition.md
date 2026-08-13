---
title: My gate reserved its reassuring message for its alarming condition
date: 2026-08-14
category: logic-errors
module: infra/apply-web-platform-infra
issue: 7542
pr: 7543
tags: [terraform, plan-gates, test-fixtures, mutation-testing, guard-erosion]
---

# Learning: a gate whose success branch the real producer cannot reach

## Problem

`tests/scripts/lib/vector-redeliver-gate.sh` shipped (59a55911c) with a documented
promise in its own header: the no-op message must never be the one printed for the
alarming condition, because with an exact-equality allow-set, "zero entries" is *also*
what a broken allow-set looks like.

It then did exactly that. The gate keyed "already delivered → NO-OP success" on
`journald_entries == 0`.

Terraform does not emit that shape. It emits `["no-op"]` **rows** for
targeted-but-unchanged resources — measured on this repo's own captured plan,
`tests/scripts/fixtures/tfplan-web-platform-real-baseline.json`: 73 `resource_changes`,
**all** `["no-op"]`. So:

- a re-dispatch after a successful delivery — the most routine dispatch this arm has, and
  one the plan's own F12 names as legitimate — scored `entries=1 delivered=0` and hit
  `ABORT — a lone delete/forget, an update-in-place, or duplicate entries all land here`,
  sending the operator to hunt a destroy that does not exist;
- and `entries == 0` could then only mean the address was **absent** — the alarming case.
  The reassuring sentence was left serving nothing else.

The suite was green: 19 assertions, mutation-proved. Its `M4` fixture used an **empty
plan** (`[]`), not a no-op row at the allowed address. Those are different documents, and
only one of them is a thing terraform produces.

## Root cause

**The fixture modelled the absence of a change, not the representation of an unchanged
resource.** Every other row in the matrix described a *change* — a delivery, a delete, an
out-of-scope update — so the fixture builder was exercised only on shapes where something
happens. The steady state, which is what a re-dispatch actually meets, was never built.

A synthesized fixture is a claim about what the producer emits. Nothing checks that claim.
The suite proves the gate decides correctly *about the documents the suite writes*.

## Solution

Two counters, each converting a comment into an assertion:

- `journald_noop` — entries at the allowed address whose actions are exactly `["no-op"]`.
  Gives already-delivered its own SUCCESS branch, distinct from both absence and
  destruction.
- `journald_family` — the allow-set address with an **optional** `for_each`/`count`
  subscript. The only counter that can still see the resource after an un-indexed →
  indexed move, which is the hazard the header predicted and could not detect.

Ordering matters as much as the counters: the stale-allow-set refusal is named **before**
the generic out-of-scope one, because a moved resource is also out-of-scope by
construction — and that message sends the operator after closure drift that does not exist.

`journald_family` is keyed on `.address` with an anchored regex, **not** `.type`+`.name`.
The first cut used type+name; the shared fixture builder (`gate-suite-harness.sh
rc_entry`) emits only `address` and `type`, so that counter read 0 on every fixture in the
repo — structurally dead under test, which is the vacuity the Guard Contract exists to
forbid. Caught only because a mutation that should have reddened the suite did not.

## Key insights

**1. A synthesized fixture is an unverified claim about the producer.** When a fixture
stands in for a real tool's output, at least one row must model the shape that tool emits
in the *steady state*, not only in the state where something happens. "Nothing to do" and
"no document" are different documents.

**2. Check which branch your reassuring message is reachable from.** If a gate has a
benign-sounding outcome and an alarming one, enumerate the plans that reach each. A
message that is only reachable from the alarming condition is worse than no message.

**3. Adding an Nth instance to a file already covered by a membership assertion silently
weakens that assertion.** `check-cloudflare-token-drift.test.sh` pinned the
`cf-tunnel-ssh-bridge` caller set by sorted **file list** + **total count**. While
`apply-web-platform-infra.yml` had one call site, removing it dropped the file from the
list and membership caught the swap. Giving that workflow a *second* call site meant the
file stays listed, a donor holds the total constant, and both halves go quiet. The
mutation battery's M4 arm went from caught to **SURVIVED** — "the gate is protected by
nothing." Fix: pin the per-file *distribution*, which subsumes membership and cardinality.
Nothing in a diff that adds a call site looks like a guard change.

**4. "Which suites consume the files I changed" is not the same question as "which suites
consume what I added."** After a targeted-consumer sweep came back green, CI failed four
suites. Three of them consume the *class* of thing added — a new bridge caller, a new
`apply_target` option — not any file in the diff. No grep on changed filenames finds those.
For a change that adds a *member to an enumerated set*, the full suite is the only reliable
sweep.

**5. A file-wide `perl s///` in a 5,700-line multi-job workflow is not a mutation of your
job.** Without `/g` it rewrites the first match, which in a file of near-identical jobs is
somebody else's. Twice in this session that produced a confident, wrong conclusion that a
suite had a hole. Scope every workflow mutation to the job's line range and assert the
mutation landed *inside it* — a `cmp` that merely proves the file changed proves nothing
about where.

## Prevention

- When a gate's fixture stands in for a real producer, add one row built from the
  producer's steady-state output. Where a real captured artifact exists in-repo
  (`tests/scripts/fixtures/tfplan-*-real-baseline.json`), read its action distribution
  before writing the matrix.
- Before shipping a guard, ask which plan reaches each success branch. If a branch is
  unreachable, it is not a branch — it is a comment.
- When adding an instance to a set an existing assertion enumerates, run that assertion's
  mutation battery. A membership assertion over files silently degrades when a file gains
  a second instance.
- Scope workflow mutations to the job under test and verify the mutation landed there.

## Session Errors

1. **Gate no-op inversion shipped in Phases 1–2.** The subject of this learning.
   *Recovery:* two counters + branch reorder, mutation-proved (5 mutations red).
   *Prevention:* fixture must model the producer's steady state — see Key Insight 1.

2. **File-wide mutation landed in the wrong job, twice in one session.** Produced two
   false "the suite has a hole" conclusions during mutation testing.
   *Recovery:* re-ran every mutation scoped to the job's line range; all reddened.
   *Prevention:* Key Insight 5 — scope and verify placement, never just that the file changed.

3. **Blinded an existing guard by adding a second bridge call site.**
   *Recovery:* pinned the per-file distribution; retargeted the battery's M4 arm.
   *Prevention:* Key Insight 3.

4. **Concluded the full local suite was unnecessary from a targeted-consumer sweep.** CI
   then failed four suites.
   *Prevention:* Key Insight 4.

5. **Asserted `timeout-minutes: 15` bounds a concurrency-group hold.** It does not — the
   timeout starts when the job begins executing, and a run held in `waiting` for a
   deployment approval already holds its group.
   *Prevention:* for any claim of the form "X bounds Y", name the moment X starts.

6. **Two unverified factual claims in the runbook** — "web-1 is the sole tunnel connector"
   (false: multiple connector replicas; the *ingress service* is what pins web-1) and
   `triggers_replace` hashing only `vector.toml` (it also hashes `journald-soleur.conf`).
   *Recovery:* both corrected against `tunnel.tf` / `server.tf`.
   *Prevention:* an operator-facing runbook claim about topology needs the file:line that
   states it, in the same pass that writes the sentence.

7. **Apostrophe inside a single-quoted jq program** (`repo's`) terminated the bash string →
   exit 127. *Recovery:* reworded; the block now carries a no-apostrophes note.
   *Prevention:* a jq program embedded in a single-quoted bash string is apostrophe-hostile
   in its COMMENTS as well as its code — the file already carried a `''`-escaped instance;
   read the neighbouring escaping before adding prose to such a block. *(one-off)*

8. **Escalated a design decision the rules already answered.** Asked the operator to choose
   on `environment:` when `hr-menu-option-ack-not-prod-write-auth` plus the live branch-pin
   evidence settled it. The operator's correction: *"not sure what design trade off I need
   to choose from and why I have to be involved… you should figure it out yourself based on
   our Soleur rules."*
   *Prevention:* before surfacing a choice, check whether a hard rule decides it. Soleur
   operators are non-technical; a genuine choice is one the rules leave open.

9. **A counter keyed on a field the shared fixture builder never emits** (`.name`), making
   it structurally dead under test. *Recovery:* re-keyed on `.address`.
   *Prevention:* before keying a counter on a plan-JSON field, grep the shared fixture
   builder for that field — a predicate the builder never emits reads 0 forever and its
   matrix row proves nothing. *(one-off)*

10. **Ran a sandboxing mutation battery while editing the tree**, tripping its
    tree-cleanliness self-check. *Recovery:* re-ran on a clean tree.
    *Prevention:* a suite that sandboxes copies of its SUT will assert the worktree did
    not move under it; run it when no edits are in flight, and read a tree-cleanliness
    failure as a scheduling fault rather than a code failure. *(one-off)*

11. **`git stash list` (read-only) blocked by the never-stash-in-worktrees hook.** The hook
    matches the subcommand family, not the mutating subset.
    *Prevention:* reach for `git worktree list` / `git status` rather than any `git stash`
    subcommand inside a worktree, even a read-only one. *(one-off; the hook failing
    closed on a read-only verb is the safe direction)*

12. **A blanket `git add -A` staged a REJECTED rule-metrics aggregate.** The aggregator's
    orphan gate exits *after* writing, so a failed run leaves a partial file in the tree. My
    guarded invocation reverted it correctly; a later bare diagnostic re-run did not, and the
    consolidation `git add -A` picked it up. *Recovery:* `git restore --staged` + `git
    checkout --`. *Prevention:* the revert belongs on EVERY invocation of a writer whose
    failure path still writes — including throwaway diagnostic ones — not only the scripted
    call that carries the guard. (Blocked by pre-existing #6531; hook faults by #7275.)
    *(one-off)*

## Related

- `tests/scripts/lib/vector-redeliver-gate.sh` — the gate; its header carries the
  four-then-six-counter reasoning
- `tests/scripts/test-vector-redeliver-gate.sh` — M13/M14/M14c are the regression pins
- `tests/scripts/test-vector-redeliver-wiring.sh` — the axis-D suite
- `scripts/check-cloudflare-token-drift.test.sh` — W7 per-file distribution
- `knowledge-base/project/plans/2026-08-13-infra-vector-redeliver-apply-target-plan.md`
