# A wrong measurement propagated into three artifacts, and the fix for it reproduced its own defect

**Date:** 2026-08-06
**Issue:** #7299 · **PR:** #7300 · **Filed:** #7307 · **Corrected:** #7302, #7287, ADR-096, ADR-152

## Problem

`registry-userdata-budget.sh` measured the registry host's cloud-init by rendering
`templatefile(...)` **raw**, while `zot-registry.tf` renders
`base64gzip(replace(templatefile(...), local.registry_rationale_strip, ""))`. It therefore
measured **36,404 B** against Hetzner's 32,768 B cap — a payload no host is ever given. The real
stored artifact is **9,408 B, 23,360 B under cap**.

The script was fail-LOUD. It reported a breach that did not exist. That is supposed to be the safe
direction, and it still cost more than a quiet bug would have.

## The actual damage: one wrong number, three artifacts

The phantom did not stay in the script. Every artifact that cited it inherited it as fact:

| artifact | what it claimed | consequence |
|---|---|---|
| issue #7299 | "the registry host cannot be re-provisioned" | filed as a P1 outage; a full plan→work→review→ship cycle spent on a defect that did not exist |
| `ADR-096` apply-blocker list | byte cap is a hard blocker on `registry-host-replace` | the apply reads as more blocked than it is |
| `ADR-096` **rollback procedure**, constraint 2 | "the revert strands the registry for the same arithmetic reason" | **read mid-incident** by an operator deciding whether a revert exists |
| issue #7287 pre-flight checklist | "(c) is currently BREACHED and is a hard blocker" | gates the real apply |

The rollback entry is the sharp one. A wrong number in a rollback procedure is consumed at the
worst possible moment, by someone who has no time to re-derive it.

**The lesson is not "fail loud is bad."** It is that a fail-loud measurement is still a *claim*,
and claims propagate. The blast radius of a wrong measurement is the set of artifacts that cite
it, not the tool that produced it.

## Why it survived: the reasoning was sound and the conclusion was still wrong

`infra-validation.yml` said, in writing:

> "It cannot be a hard gate YET. The check is RED on `main` today (-2,032 B) … **#7280's
> `local.registry_rationale_strip` strips comments BEFORE render and brings it to ~9.4 kB.**"

The author knew the resolution and shipped the job `continue-on-error: true` pending #7280. #7280
merged 6h 22m *before* the script was added (verified: `d0295964f` 08:18 UTC, `6720f2ae0` 14:40
UTC). The strip went live. The reading never moved — because the script was written after the
strip existed and still did not apply it.

**A permanently-red advisory check is how that hid.** It trains every reader to skip it, so nobody
re-ran the reasoning when its own stated precondition was met. Shipping a knowingly-red gate needs
an enforced follow-through, not a comment promising one.

## Then the fix reproduced the defect it was fixing

This is the part worth keeping. The first version of the fix asserted the strip was **declared**
in `zot-registry.tf` and assumed it was **applied**. Deleting the `replace(...)` wrapper leaves the
local orphaned — terraform accepts that silently, `validate` stays green — and the gate reported
9,408 B and exit 0 on a tree storing 36,404 B.

`ADR-152` had already recorded that exact case, measured, with the rule spelled out:

> "Extraction also does not prove the strip is APPLIED… measured: unwiring the `replace()` and
> leaving the local orphaned kept the whole suite green while the render returned to 34,628 B.
> **Assert on the RENDER EXPRESSION, not on a string in a file.**"

The rule existed, in the ADR this PR cited for its own design precedent, and it was not applied.
Three independent review agents found it.

### The second fail-open: ceilings without floors

Every numeric assertion in the new suite bounded one side. A strip widened to `/(?m)^.*\n/` eats
the whole payload; `base64gzip("")` is 40 chars, so it reported **maximum headroom and exit 0**
while `#cloud-config` was gone and the host would boot dark (LUKS locked, zot never started).

Worse: the suite's own new assertions — `stripped < raw/2` and `headroom >= 20000` — are satisfied
*maximally* by the destroyed payload. The guard was most confident exactly when the payload was
most broken. The sibling TS test already carried `REGISTRY_GZIP_FLOOR = 4_000` for this; the new
suite copied the ceiling and dropped the floor.

## Key insights

1. **A fail-loud measurement is a claim, and claims propagate.** Before trusting a number in an
   ADR, runbook, or issue checklist, ask what produced it and whether that producer has been
   verified since. Sweep by CLAIM, not by file: this PR corrected #7299 and initially left the
   identical phantom in ADR-096 and #7287.

2. **"X is declared" and "X is used" are independent facts.** Any guard that reads a config value
   to decide something must also assert the value is wired in. Reading a declaration proves the
   author's intent, never the system's behaviour.

3. **Every numeric assertion on a measured quantity needs both bounds.** Ask: "what does drift
   toward *smaller and safer* look like, and would anything fire?" On a hard gate, the optimistic
   direction is the one that causes the outage.

4. **A green mutation battery measures the mutations you imagined.** Mine perturbed one axis (the
   config declaration) and reported all-caught. Review found two survivors on axes it never
   touched: understating `stored_bytes` 8× passed 9/9, and swapping `cap` 32768→65536 passed —
   the whole artifact defends one number and no check read it. Audit a battery's AXES, not its
   count.

5. **An assertion-count floor must be equality against a named constant.** `checks < 8` on a suite
   whose green run emits 9 cannot distinguish "all passed" from "one failure swallowed".

6. **Stating a cost/benefit call as a blocked dependency is the same trap.** I wrote "promotion is
   blocked on #6480". It is not — #6480 concerns a different job's cost. As written it tells the
   next reader to *wait* rather than re-derive, which is precisely how #7299's precondition went
   unre-examined.

7. **Explain a numeric delta by measuring its components, not by attributing it.** I blamed a
   ~300 B difference on `terraform console` `<<EOT` re-escaping. Console does not re-escape; the
   ~300 B *was* the UTF-8 byte delta (152 non-ASCII chars). I swapped a byte-accurate figure for a
   grapheme count, labelled it `B`, against a byte cap — an optimistic bias in a file whose own
   header forbids optimistic measurement.

## Session Errors

1. **Guard asserted the strip was declared, not applied (P1 fail-open).** Recovery: anchor on
   `user_data = base64gzip(replace(templatefile(` and exit 2 otherwise. **Prevention:** when a
   guard reads a value from config to make a decision, assert the value is also *referenced* by
   the thing being guarded. ADR-152 states this; consult the ADR you cite for precedent.

2. **Ceiling-only assertions (P1 fail-open).** Recovery: 4,000 B plausibility floor +
   `#cloud-config`-survives assertion. **Prevention:** for each numeric arm, name the mutation
   that makes the measured value *smaller* and confirm something fires.

3. **Mutation battery perturbed a single axis.** Recovery: review's test-design pass found two
   survivors. **Prevention:** before trusting a battery, list the axes it edits (inputs, dispatch,
   set cardinality, harness) and note which are untouched.

4. **False mechanism in a comment (`length()` / console re-escaping).** Recovery: measured
   `length()` 74152 vs dump 74454 vs file 74453 and rewrote the comment. **Prevention:** measure
   the components of a delta before naming its cause.

5. **"Blocked on #6480" — a cost/benefit call stated as a dependency.** Recovery: corrected the
   workflow comment and rewrote #7302. **Prevention:** before writing "blocked on #N", check
   whether #N's constraint actually applies to *this* surface.

6. **False provenance twice** — "#7283 moved a budget reading no main run re-evaluated" (the
   script did not exist before that commit) and "#7282 added the script" (an issue, not the PR).
   **Prevention:** `git cat-file -e <sha>^:<path>` before asserting a file existed at a commit;
   `gh issue view` vs `gh pr view` before attributing authorship.

7. **`checks < 8` floor was one short of the 9-check green run.** **Prevention:** equality against
   a named `EXPECTED_CHECKS`.

8. **Test 5 counted files, not assignments, and its `"$DIR"/*.tf` glob made `-r` inert.**
   **Prevention:** when a check's message says "assignments", count assignments.

9. **Plan swept by file, not by claim.** Seven sections still described the descoped Phase 3
   design, one directly contradicting AC9. **Prevention:** after descoping a phase, grep the plan
   for the phase's mechanism words, not just its heading.

10. **`pgrep -f 'test-all.sh'` matched my own shell** (its command line contains the pattern), so I
    chased and killed phantom "stray runs" that were my own check commands. **Prevention:** use
    the bracket trick `pgrep -f '[t]est-all\.sh'`. *This trap is already documented in the rule
    corpus for `pkill`, and it recurred anyway — the `pgrep` direction is the one that produces
    confident wrong diagnoses rather than an obvious self-kill.*

11. **Edited the tree under a running full suite**, truncating the log and forcing a kill+re-run.
    **Prevention:** the documented rule is confirm-clean-then-do-not-edit; a mid-run edit means
    killing the run, not reinterpreting its output. *Also already documented; also recurred.*

12. **Mutation-battery control was RED** because the sandbox was not a git repo (the suite's
    `git grep` decls arm needs one), which voids every result. Recovery: `git init` the sandbox.
    **Prevention:** run the unmutated control first and require GREEN before reading any mutant.

13. **Registered the new suite in the wrong job.** The registration gate requires
    `deploy-script-tests` specifically, because `run-registered-suites.sh` derives from it.
    Caught by the full suite. **Prevention:** the gate's own error message names the job.

14. **First full-suite run corrupted** (launched, then kept editing; log truncated under a live
    writer). Recovery: killed, re-ran clean. Same root as #11.

## Prevention

- When a gate reads config to decide something, assert the config is **wired in**, not just present.
- Bound measured quantities on **both** sides; the optimistic direction is the dangerous one.
- Treat a numeric claim in an ADR/runbook/checklist as owned by whatever produced it — and sweep
  by claim when that producer is found wrong.
- Audit a mutation battery's **axes**, not its pass count; run the control first.

## Related

- `ADR-152` — the strip mechanism, and the "assert on the render expression" rule this session
  failed to apply, now annotated with the byte-exact gap it closes.
- `ADR-096` — apply-blocker list and rollback procedure, both corrected here.
- `knowledge-base/project/learnings/2026-07-27-the-subshell-bug-i-was-fixing-bit-me-three-more-times.md`
  — same shape: the defect being fixed recurring inside its own fix.
- #7307 — `main-health-monitor` dark (timeout reports `cancelled`, not `failure`).

## Tags

category: integration-issues
module: apps/web-platform/infra
