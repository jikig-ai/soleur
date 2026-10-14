---
title: I hardened my verifier twice and its sample was still a sample
date: 2026-08-19
category: workflow-issues
module: apps/web-platform/infra
tags: [verification, rebase, mutation-testing, review, scope-out, guards]
related_issues: [7291, 7565, 7613]
related_prs: [7510, 7567]
related_learnings:
  - knowledge-base/project/learnings/2026-08-16-every-number-i-inherited-was-stale-and-the-panel-found-the-defect-class-inside-my-fix.md
  - knowledge-base/project/learnings/2026-08-11-the-pr-that-fixed-narrow-guards-shipped-three-narrow-guards.md
  - knowledge-base/project/learnings/2026-07-15-ad-hoc-verification-evidence-is-as-perishable-as-uncommitted-code.md
---

# Learning: I hardened my verifier twice and its sample was still a sample

## Problem

PR #7510 (closing #7291) was rebased onto #7567, which had merged into the exact function the
branch was rewriting. To prove the rebase reverted none of #7567's work, I built a checklist of
anchors and ran it against the composed tree.

**Version 1 asserted presence.** It printed `ok` for an anchor that existed once, while #7567 had
placed it at *two* sites and the rebase had dropped the mutation arm's copy. Presence cannot see a
halved population.

**Version 2 asserted exact occurrence counts,** positive-controlled against `origin/main` where
every count must hold. It reported 16/16 on both trees. It was still wrong: an entire 13-line floor
itemisation from #7567 had been deleted, and **none of its 16 anchors sat in that region.**

The falsifier that found it took one command:

```bash
git show 6b17eb2e0 -- "$F" | grep '^+' | grep -v '^+++' | sed 's/^+//' > /tmp/added
while IFS= read -r l; do
  [ -z "$l" ] && continue
  grep -qxF -- "$l" "$F" || echo "GONE: $l"
done < /tmp/added
```

37 lines absent; 13 of them the stanza. The suite was green throughout, and the surviving
itemisation chain read 44 → 46 → **48** → 49 with nothing explaining the middle step — four lines
under a comment instructing the next author to reconstruct the base from exactly those stanzas.

## Key Insight

**Correctness of a predicate and completeness over a population are different properties, and
fixing the first feels like fixing both.**

Version 1 → version 2 was a real improvement on a real axis: the predicate went from "≥1" to
"exactly N". That is the axis I had just been burned on, so it was the axis I fixed. The anchor
*set* — which regions of the artifact get any predicate at all — was never the thing under
consideration, and it stayed a sample of my own choosing across both versions.

The tell is that the instrument's output is **identical on a healthy tree and a damaged one**. A
16/16 that is also 16/16 on `origin/main` proves the anchors are well-formed; it says nothing about
coverage. Ask of any hand-built verifier: *which regions of the subject can change without any
assertion noticing?* If the answer is "I chose the anchors", the answer is "many".

For the specific case of a rebase over a sibling that touched the same code, the population is
enumerable and the check is mechanical: **every line the sibling added is either present at HEAD,
or accounted for as deliberately superseded.** Do not sample it. My 32 remaining absences after the
fix all classified as superseded-with-replacement — but I only knew that because I enumerated them.

## Solution

- Restored the deleted stanza and added two anchors *inside* the previously unsampled region,
  re-validated on both trees.
- Kept the enumerate-every-added-line falsifier as the primary check; the anchor list is now the
  cheap regression net, not the proof.

## Prevention

- After building any completeness verifier, run it against a tree you have **deliberately damaged
  in a region you did not anchor**. If it stays green, the anchors are a sample.
- For rebase composition specifically, enumerate the sibling's added lines and classify each
  survivor; a curated anchor list is a supplement.
- Positive-controlling against the source tree proves anchor well-formedness only. It cannot
  detect an unsampled region, because both trees have that region intact.

## Session Errors

1. **`pkill -f 'run-battery2.sh'` matched its own command line and killed the invoking shell**
   (exit 144). — Recovery: `plugins/soleur/scripts/lib/proc.sh kill_mine`, which resolves ownership
   through `/proc/<pid>/cwd` and refuses same-process-group matches. — **Prevention:** already
   documented and already tooled; the rule needs no change, I needed to reach for the tool first.

2. **Edited the suite while a mutation battery was running it.** Bash reads scripts by byte offset,
   so the in-flight row was executing bytes I had changed. — Recovery: killed the battery, discarded
   the run, separated the prose commit from the mutation work. — **Prevention:** commit before
   launching any run, and treat "my edit is unrelated to the running suite" as false by default.

3. **Did it again** — edited the file while a *control* run was reading it, hours later. — Recovery:
   killed and discarded that run too, re-ran clean on the committed bytes. — **Prevention:** this is
   the one recurring item with no mechanical guard; see Route-to-Definition below.

4. **Mutation row 1 was mis-designed.** It removed the CHMOD_RAN instrumentation, which trips an
   upstream guard and hard-exits *before* the verdict — red for a reason unrelated to the routing it
   is named for. — **Prevention:** for each row, name the branch it must reach and confirm the run
   got there, not merely that it went red.

5. **Mutation row 7 survived and I nearly recorded it as a pass.** It added a synthetic skip of cost
   2 against a ceiling of 2 without forcing the real skip, so `2 ≤ 2` held. — **Prevention:** a
   surviving mutant has exactly two readings — the fixtures do not exercise the property, or the
   mutant is equivalent. Label which. This was the first.

6. **The graft checklist was blind in the region that mattered.** — See Key Insight.

7. **The `/tmp` scratchpad was reaped mid-session,** taking `mutate.py`, the battery driver and the
   checklist. Run artifacts written to `/var/tmp` survived. — **Prevention:** tooling a later step
   depends on goes in `/var/tmp` or the repo, never the session scratchpad.

8. **The universal "EVERY ROUTE" survived at a third site** one commit after I retracted it at two.
   — **Prevention:** when retracting a claim, grep the OLD wording repo-wide and classify every
   survivor; a residual count over the NEW wording is structurally blind to the sites still carrying
   the old.

9. **I broke a claim in the commit that removed its subject.** The commit deleted the `pass; pass`
   dash counterweight, documented the deletion, and left a sentence ninety lines below asserting the
   counterweight "exists to keep it so". Found by a CONCUR gate, not by me. — **Prevention:** after
   deleting a mechanism, grep its name before committing.

10. **Proposed a scope-out bundle whose re-evaluation trigger was already satisfied** — "the next
    time anyone is in this file", while I was in it adding 500 lines. — **Prevention:** state the
    trigger, then ask whether it holds right now.

11. **Fixed one pre-existing item inline and proposed deferring three of the same class,** with no
    stated principle for where I stopped. — **Prevention:** if a stated rationale ("this makes the
    floor trustworthy") applies to other findings, it applies to them too, or the rationale is not
    the real reason.

12. **The re-scoped bundle's mechanism claim was false on three of six items.** — **Prevention:**
    a bundle's shared mechanism is a claim to verify per item, not a label to apply to the group.

13. **Used `stat -c %Y` on a directory to measure elapsed time.** The directory's mtime updates when
    files are created inside it, so the delta was 0 by construction. — one-off. — **Prevention:**
    measure against an independent clock reference.

14. **Assumed a missing symbol was a reverted `main` feature.** It was my own branch's deliberate
    removal. — one-off, and the check worked: `git log -S` before acting.

## Also worth recording

**Both CONCUR passes DISSENTed and both were right, including about my own inconsistency** (#11
above). The gate is worth the round-trip precisely because it adjudicates the disposition rather
than the code.

**But a gate's verdict and its prescribed fix are separate claims.** The first pass was right to
flip the filing and wrong about the fix: it prescribed changing an assertion literal to the shipped
template's stage name, which would have RED the suite — the capture carries the *driver's* value, so
the driver was the side that had to move. Verify a gate's prescription like any other.

**A convention finding needs a density check.** A panel recommended renumbering ADR-188 to 194 on
"highest + 1". The merged sequence has three gaps — 188, 189, 192 — and 189/192 are held by two
other in-flight branches. They are concurrent reservations, not holes; renumbering would *create*
the hole and place a 2026-08-12 decision above two later branches. The re-derive rule guards
collision, and there was none.

## Verified figures

Base floor on `origin/main`: 48. Shipped floor: 49 (net +1: +1 skip ceiling, +1 errexit-ordering
assertion, −1 for merging two bag-union assertions into one single-record conjunction). Control:
`49 passed, 0 failed, Skipped: 0 (49 assertions)`, rc 0. Skip path: `47 passed, 0 failed,
Skipped: 2 (49 assertions)`, rc 0, with the degraded-run NOTE. Identical under `CI=true` and
`SOLEUR_SUBAGENT=1`. Skip cost and ceiling both 2.
