---
title: A plan can specify a mechanism the packaging boundary forbids
date: 2026-09-18
category: workflow-patterns
module: plan, plan-review, workflow-fidelity
issue: 8302
pr: 8301
tags: [plan-review, packaging-boundary, fail-open, guard-placement, prompt-text-vs-state]
---

# Learning: A plan can specify a mechanism the packaging boundary forbids

## Problem

A plan passed premise validation, the mechanism-minimality gate, a value
measurement, a C4 completeness enumeration and a Guard Contract — and still
specified three mechanisms that could not work. A six-agent review found them.
All three share a shape: **the plan reasoned about a file's location in the
repository, not about where the artifact executes.**

## Solution

### 1. Repo-root config is not plugin content

The plan had `plugins/soleur/lib/workflow-fidelity.ts` read
`.claude/phase-surface-map.json` at call time. Both files are in the repo, one
directory apart, and the read is trivially correct on the developer's machine.

But `.claude-plugin/marketplace.json` declares `source: "./plugins/soleur"`.
`.claude/` is **not inside the shipped tree**. On a customer install the read
misses, `mandatorySuccessors()` returns `[]`, and the function that renders
"invoke next: /review" silently emits nothing. That is ADR-151's
*appears enforced, is absent* — on someone else's machine, where no lint runs.

The repo had already solved this once and left the answer in a comment.
`apps/web-platform/server/phase-surface-map.ts` opens with: *"The `.claude/`
directory is NOT shipped into the web container … so the web SDK phase-surface
hook cannot read the canonical map at runtime — it imports this bundled `.ts`
const."* The bundled copy exists **because of this exact constraint**, and the
plan cited that file as a parity-test precedent without reading why it exists.

**Probe:** for any runtime read a plan adds, ask *what does the distributed
artifact contain?* — `jq -r '.plugins[].source' .claude-plugin/marketplace.json`,
then `ls <source>/<path>`. Repo-relative correctness is not shipped correctness.

### 2. A guard in the wrong CI shard is permanently fail-open

The plan's best idea was a byte ceiling anchored to the **merge base**, so a
diff could not raise a ceiling and satisfy it in one commit — the fix for a
budget constant that had been bumped 15 times, each "against a N/N zero-headroom
baseline".

It specified the assertion in `plugins/soleur/test/components.test.ts`. That
file runs in a CI job whose checkout declares **no `fetch-depth`**. At depth 1,
`origin/main` is not a fetched ref, so `git show origin/main:<file>` fails on
every run — and any working-tree fallback makes the guard fail-open forever,
degrading it to precisely the changelog it was written to prevent.

**A guard's placement is part of its contract.** "Which job runs this, and what
does that job's checkout provide?" belongs in the Guard Contract's *assembly*,
next to the chokepoint. Add a mutation row asserting the guard reddens under the
degraded environment (`fetch-depth: 1` → hard RED, never skip).

### 3. A function whose output is prompt text cannot carry semantic state

The plan declared three back-edges (`review→work`, `ship→work`, `work→plan`) and
asserted them through `mandatorySuccessors()`. The name reads like a transition
set. Its result is rendered as **"When standalone, invoke next: /X, /Y"**.

Putting `plan` into `work`'s successors would therefore instruct the model to
re-enter planning after every implementation run. *Permitted transition* and
*mandatory successor* are different concepts; a back-edge is legal-if-taken, not
a directive. They needed separate functions.

**Probe:** before adding a value to a collection, read what consumes it. A
collection rendered into a prompt is an instruction, not a data structure.

## Key Insight

**Each defect was invisible to the gate that should have caught it, because
every gate reasoned about the repository and all three failures live somewhere
else** — a customer's install, a CI job's checkout depth, a rendered prompt.

The Guard Contract asks for property, assembly and mutation matrix. All three
were written. What was missing from *assembly* in every case was the execution
environment: **which machine, which job, which consumer.** A chokepoint named
only by file path is under-specified.

Corollary on review economics: six reviewers produced findings that were
**convergent, not additive**. Four independently said cut the gate; three
independently said the extraction targets were core-path. Where both the
simplification panel and the correctness panel fire on one scope, the plan-review
rule "prefer delete over fix" was right — cutting the gate dissolved a hook, a
settings entry, a test file, an entire guard and four acceptance criteria, and
every defect in them went with it.

## Prevention

- For any runtime read a plan adds, resolve the **distributed** artifact's
  contents, not the repo's.
- Record a guard's **CI job and that job's checkout guarantees** in the Guard
  Contract's assembly, and add a mutation row for the degraded environment.
- Before writing to a collection, read its consumer; a collection rendered into
  a prompt is an instruction.
- When both review panels fire on one scope, cut before fixing.
- Anchor a claim on a cited precedent by reading **why the precedent exists**,
  not only its shape — the answer was in the first nine lines of the file the
  plan already cited.

## Session Errors

1. **Specified a plugin-code read of repo-root config** — *Recovery:* verified
   `marketplace.json` ships `./plugins/soleur` and that
   `plugins/soleur/.claude/` does not exist. — *Prevention:* resolve the
   distributed tree.
2. **Placed the merge-base guard in a shard without fetch depth** —
   *Recovery:* moved it to a job with `fetch-depth: 0`, base-missing as hard
   RED. — *Prevention:* job + checkout guarantees belong in assembly.
3. **Conflated permitted back-edges with mandatory successors** —
   *Recovery:* split `declaredTransitions()` from `mandatorySuccessors()`. —
   *Prevention:* read the consumer first.
4. **Cited `summary.events_total` in an AC** — the field does not exist among
   the aggregate's 21 keys. Invented, not measured. — *Prevention:* `jq keys`
   before naming a field.
5. **Wrote a byte-sum conservation check** that is content-blind and passes on
   equal-sized substituted text. — *Prevention:* exact diff, or nothing.
6. **Seeded ceilings at zero headroom** — the precise pattern the plan cited as
   the cause of 15 prior bumps. — *Prevention:* when citing a failure mode,
   check the new design does not reproduce it.
7. **Measured "conditional reference loads" twice with too-short capture
   windows** (reported 0 of 12 both times; the answer is 7 of 12). Third
   derivation was correct. Same class as the brainstorm's six measurement
   errors — see [[2026-09-18-re-verifying-a-stale-audit-and-six-measurement-errors-of-my-own]].

## Related

- `knowledge-base/project/learnings/2026-09-18-re-verifying-a-stale-audit-and-six-measurement-errors-of-my-own.md`
- ADR-070 (two-tier fail-open), ADR-086 (PostToolUse mandate), ADR-091
  (local-producer rule metrics), ADR-116 (advisory→blocking never promoted),
  ADR-131 (gate moratorium), ADR-151 (unconditional rule corpus)
- Plan: `knowledge-base/project/plans/2026-09-18-feat-workflow-fsm-remediation-plan.md`
  (`## Plan Review Revisions` R1–R11)
