---
module: plugins/soleur test harness (components.test.ts references-reachability census)
date: 2026-10-21
problem_type: logic_error
component: testing_framework
symptoms:
  - "the plan-prescribed negative control — remove the SKILL.md link on a scratch copy, expect the reachability census to red naming test-browser/references/feature-map.md — cannot red: the suite still reports the file linked"
  - "the census predicate is haystack.some(t => t.includes(f)) — basename substring over every other file in the skill dir — and `feature-map.md` survives in five docs/apps path mentions after both markdown links are removed"
  - "the same unfalsifiable control hit two executors — work ran it for tasks.md 3.2 and QA re-ran it — each had to derive the faithful mutation themselves"
root_cause: logic_error
resolution_type: workflow_improvement
severity: medium
rule_id: cq-assert-anchor-not-bare-token
related_issues: [10402]
related_prs: [10735]
tags: [negative-control, basename-substring, references-reachability, census, scratch-copy, producer-consumer-symmetry, byte-capped-edit]
synced_to: [plan]
---

# A "remove the link" negative control cannot red a census keyed on basename substring

## Problem

`components.test.ts`'s references-reachability census
(`describe("references/ files are reachable from their skill")`) decides
linked-ness by `haystack.some((t) => t.includes(f))` — the reference file's
**basename** as a substring of any other file in the skill directory, the
file itself excluded. A plan-prescribed negative control of the shape "on a
scratch copy, remove the markdown link and confirm the census reds naming
the file" is **structurally unable to red it** whenever the basename also
appears in the skill's prose — exactly the case for
`test-browser/references/feature-map.md`, whose basename occurs 7 times in
`test-browser/SKILL.md` (2 markdown links + 5 `docs/feature-map.md` /
`apps/web-platform/test/feature-map.md` path mentions). Removing both links
leaves 5 occurrences; `includes("feature-map.md")` stays true; the control
"passes" a suite that could not have failed.

The prescription came from the #10401 sibling learning
(`best-practices/2026-10-20-copied-template-links-and-coverage-negative-controls.md`),
which established the negative-control practice — correctly — for a basename
(`differential-migration-testing.md`) that occurred ONLY in the pointer
lines being removed. The technique silently breaks on the next basename that
is also a word the prose uses.

## What Didn't Work

**The control as prescribed (tasks.md 3.2):** "on a scratch copy with the
SKILL.md link removed, the reachability census reds naming
`test-browser/references/feature-map.md`." With the link deleted the census
still reports `linked: true` — not because the guard is broken but because
the mutation never touched what the predicate reads. Both `soleur:work`
(executing the task) and `soleur:qa` (re-verifying) hit the same wall.

**Reading the control's green as guard evidence:** a red-less control run is
indistinguishable from "the guard correctly reports linked" — the only thing
it certifies is that SOME basename occurrence survived, which is precisely
the failure the census exists to catch.

## Solution

Enumerate the predicate's input before mutating:

```bash
# What does the census actually read? every file in the skill dir except the
# reference itself. Enumerate the basename's sites first:
grep -rn "feature-map\.md" plugins/soleur/skills/test-browser/
# -> 7 hits: 2 link refs, 5 path prose. Removing "the link" addresses 2.

# Faithful control, option A — strip ALL basename occurrences on the scratch
# copy (comment them, rename the path mentions, or blank the file's prose),
# then assert the census reds NAMING the file.
#
# Faithful control, option B — assert the predicate directly: run the suite
# against a scratch skill dir whose haystack never contained the basename.
```

The general rule: **a negative control must remove what the guard's
predicate reads, not what the diff added.** For a substring census that is
EVERY occurrence of the keyed string; for a line-anchored parser it is the
one conforming line. `grep -rn '<basename>' <dir>` before prescribing the
mutation is the enumerate-then-decide step the prescription was missing.

Dual reading worth noting: the same bare-basename predicate means the census
never required a markdown link in the first place — a prose path mention
satisfies "reachable" by design (the guard documents intent as "named by
basename"). Teams that want link-required reachability need a different
predicate; the current one pins *mention*, which the convention doc's own
path citations will always satisfy.

## Why This Works

1. The control now targets the assertion's actual input domain. `includes(f)`
quantifies over every sibling file's full text, so the set of sites the
   mutation must touch = the grep hit set, not the link the diff happened
   to add.
2. It keeps the #10401 practice intact while fixing its blind spot: "delete
   the artifact/pointer, watch the suite red" is still the right shape — the
   refinement is WHAT counts as the artifact for a basename-keyed guard.
3. The litmus is the same one the review corpus already uses for
   guard-shaped diffs — name the input that satisfies the check while
   violating the property — applied one level up, to the control itself.

## Session Errors

1. **Plan prescribed an unfalsifiable negative control (tasks.md 3.2).**
   - **Recovery:** both executors derived the faithful form in-session —
     enumerate all basename occurrences, strip them all — and the real
     census red run was recorded in the work log before the task box ticked.
   - **Prevention:** routed to `plan-sharp-edges.md` — when prescribing a
     red-control for a substring-keyed census, `grep` the keyed string's
     full site list first and prescribe stripping every occurrence (or
     prescribe the predicate-level probe). The `hr-…` path-verification
     gates check that a prescribed command RUNS; they cannot check that the
     prescribed mutation reaches the guard's predicate — that check is the
     plan author's.
2. **§5b producer resolved only the canonical path (review P2).** The
   original "Map absent" arm keyed on `docs/feature-map.md` alone while all
   four consumers resolve a two-path set (convention + soleur's own
   `apps/web-platform/test/feature-map.md`); on soleur itself a "refresh"
   run would have found "no map" and WRITTEN a second map at the canonical
   path, forking the live one.
   - **Recovery:** code-quality-analyst + architecture-strategist flagged
     it; fixed inline in 9a944a4f22 ("No map at either path" / "Map present
     at either path").
   - **Prevention:** when a diff adds a PRODUCER for an artifact existing
     consumers resolve through a path SET, the producer must resolve the
     identical set — asymmetric resolution silently forks the artifact. The
     review seats caught this one; the checklist-shaped version lives in
     this learning's Related Issues (same "producer enumerates a different
     set than the consumer" shape as the sibling census guard).
3. **Step 8 summary template lacked the `Feature map` field §5b prescribed
   (review P3).**
   - **Recovery:** fixed inline in 9a944a4f22.
   - **Prevention:** a new instruction block whose Report line names a
     field must be checked against the template it feeds — instruction and
     template are two files' worth of one contract.
4. **Pages-router exclusion regex unanchored (review P3).**
   `_(app\|document\|error)\.` over-excluded segment-internal names
   (`my_app.page.tsx`).
   - **Recovery:** anchored to segment start in 9a944a4f22.
   - **Prevention:** an exclusion regex over path segments must anchor at a
     segment boundary — covered by existing review sharp-edges on unanchored
     matchers; noted for completeness.

## Convention Notes

**Byte-capped SKILL.md edits.** `qa/SKILL.md` sits under
`lint-skill-body-budget.py`'s ratchet, so the citation generalization was a
one-line in-place replacement (~+45 B), verified with a `wc -c` delta plus a
`--base origin/main` ratchet run — not an appended bullet. On a capped file
the edit pattern is replace-in-place and measure the delta, never append.
Already enforced by the ratchet; noted as technique.

## Related Issues

- `knowledge-base/project/learnings/best-practices/2026-10-20-copied-template-links-and-coverage-negative-controls.md`
  — the #10401 sibling that established the scratch-copy negative-control
  practice this learning refines (its basename occurred only in the removed
  pointers, so the caveat never surfaced there).
- `knowledge-base/project/learnings/2026-10-20-a-census-guard-under-counts-on-both-enumerators.md`
  — the OTHER census guard in this arc (`lint-feature-map-coverage.sh`);
  same family (a set-comparison instrument measured on the wrong
  enumerator), different mechanism.
- `knowledge-base/project/learnings/2026-09-07-my-instruments-reported-green-while-measuring-nothing.md`
  — instruments green while measuring nothing; this is the same defect on
  the control side rather than the sweep side.
- `knowledge-base/project/learnings/2026-07-21-the-guard-i-shipped-could-never-have-fired-and-my-fake-certified-it.md`
  — a fake/control certifying a guard it could not exercise.
- Issue #10402 / PR #10735 (this branch); arc parent #10397.
