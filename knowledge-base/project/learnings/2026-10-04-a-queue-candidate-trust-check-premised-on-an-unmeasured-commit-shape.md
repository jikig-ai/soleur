---
title: A queue-candidate trust check premised on an unmeasured commit shape, and a dequeue detector that ran only on the tick that could not see it
date: 2026-10-04
category: integration-issues
module: merge-queue
tags: [merge-queue, github-rulesets, squash, ci-gates, review-process]
issue: 9454
---

# A queue-candidate trust check premised on an unmeasured commit shape

## Problem

Adopting the GitHub merge queue (PR for #9454) shipped through plan, deepen-plan and implementation with a
hardened CLA synthetic that required "the PR head must be a parent of the `merge_group` candidate". The plan,
the deepen pass and the author's mutation battery all agreed. It could never pass: with `merge_method = SQUASH`
the candidate is a single-parent squash commit whose parent is the previous candidate. The real shape was
already in the repo's own history (the first adoption, #5800: candidate `6f0e5d87a9` for `pr-5798` had one
parent, and the PR head was not a parent). A fixture modelled a MERGE-method candidate, so every test was green
over a check that would have failed every queue entry and recreated the 2026-06-30 deadlock through a different
producer.

## Solution

Design-pass review (architecture seat) read the first adoption's real queue commits and found it. The check was
removed (a push to a queued PR dequeues it, so the head cannot change between the real checks and the candidate;
`head_ref` shape and `base_ref` stay validated). A single-parent squash-shaped fixture now PASSES.

Second instance, same root: dequeue detection was first built as a marker written only on a BEHIND tick, so a
PR that reads CLEAN or BLOCKED while queued was never marked and a dequeue timed out silently after 90 minutes.
The fix reads GraphQL's `REMOVED_FROM_MERGE_QUEUE_EVENT` (verified by introspection) and checks every fifth tick.

## Key Insight

When a gate's logic is premised on the SHAPE of an object a third party constructs (a queue candidate commit,
a vendor payload, a generated ref), the fixture is the claim nobody checks. Before writing the check, read one
REAL instance from history (`git cat-file -p <sha>` on a real queue commit) and put that shape in a fixture.
A hand-built fixture that models the author's mental model passes by construction.

## Session Errors

1. **Unsatisfiable parent check shipped through plan, deepen and a green battery.** — Recovery: architecture
   design-pass seat measured real queue history; check removed. — **Prevention:** a check keyed on a
   third-party-constructed object's shape needs a fixture copied from a real instance, named in the plan
   ("measured on <sha>"); review's design-validity pass runs BEFORE the panel for exactly this.
2. **A review seat's `gh pr merge --help` fired `pre-merge-rebase.sh`, which merged `origin/main` into the
   branch and pushed.** — Recovery: kept (a plain main sync). — **Prevention:** the hook now skips help forms;
   spawn briefs for review seats forbid `gh pr merge` in any form.
3. **ADR ordinal 269 collided with a new ADR-269 on `main` between plan time and ship.** — Recovery:
   renumbered to 270 and swept references scoped to the diff's own lines. — **Prevention:** re-probe the next
   free ordinal across every `origin/*` ref immediately before ship (already in `ship` via
   `check-adr-ordinals.sh`).
4. **The affected gate caught an unowned `mktemp` (`lint-trap-tempfile-ownership`) that fix agents' own lint
   runs missed.** — Recovery: same-line annotation with the bounded-leak reason. — **Prevention:** fix briefs
   for guard-shaped diffs name the repo-global ratchets (`lint-trap-tempfile-ownership`, `lint-diagnosis-claims`,
   the two fixture-dir ratchets) so each agent runs them, not only the lead's gate.
5. **Fix-round diffs introduced defects in their own area (monitor false verdict on a failed read, hook stderr
   merged into a verdict, a re-armed PR reported dequeued twice).** — Recovery: a targeted fix round plus one
   verification pass found and closed each. — **Prevention:** none new; this is the documented reason fix
   rounds exist.
