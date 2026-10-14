---
title: An absence pin over HCL must compare the whole shape, not the kinds I was guarding
date: 2026-09-30
category: test-failures
module: apps/web-platform/infra/sentry
tags: [sentry, terraform, op-contract, mutation-testing, guard-contract]
issue: 9299
pr: 9302
---

# Learning: an absence pin over HCL must compare the whole shape

## Problem

PR #9302 split the Sentry rule `inngest-provision-failure` in two, so that the once-per-boot
`bootstrap_done_degraded` stage has its own throttle (#9299). The op-contract vitest was extended
to both rules, and its header claimed it pinned what must be ABSENT: "one extra AND-ed condition,
a second action filter, a disabled rule, a dropped action or a create-time environment".

My own 10-row mutation battery was fully green. The review's test-design seat then found **15
mutants that survived the unit test**. Two of them also survived every other gate in the repo:

- A second emitter of a paged stage elsewhere in `cloud-init-inngest.yml`, or a duplicate emit.
  Either shares the rule's throttle window, which is the #9299 bug itself.
- A dropped or reversed `depends_on`.

Every survivor sat on an axis my battery never edited. The absence checks had been written against
the kinds I was thinking of:

- **Row kinds:** only `tagged_event` rows were counted, so an extra `level` condition, a
  `first_seen_event` trigger, or a one-line action filter with a `webhook` all passed.
- **Comment forms:** `#` and `//` were stripped, but `/* */` and trailing comments were not.
- **Actions:** only the `email` action was counted.
- **Emitter region:** only the provision `write_files` block was scanned.
- **Top-level attributes:** a `count = 0`, a `locals` block swallowed by the resource slice, and a
  dropped `lifecycle` were never looked at.

The PR-time reference gate catches most of the `.tf` survivors in CI. It cannot see:

- fields the projection omits (`depends_on`, `lifecycle`);
- the emitter file.

The unit test is the only check that runs locally, so its header was claiming a property it did
not hold.

## Solution

Replace per-kind counts with whole-shape comparisons, derived from the block itself:

- `rowKinds(block)`: the sorted multiset of every `{ <kind> = {` row, compared with `toEqual`.
  An extra row of ANY kind reds.
- `topLevel(block)`: the sorted list of two-space-indented attributes and nested blocks. It is
  compared as a list, so a duplicate also reds, and `count`, `environment` and a missing
  `depends_on` or `lifecycle` all red.
- `/* */` is stripped from the `.tf` only. Applied to the YAML, it eats shell `/*` globs.
  Trigger and action regexes are anchored to a whole line.
- `tfBlockFor` ends at the block's own column-0 `}` rather than at the next `resource`.
- Emitter locality: each paged stage has exactly one `soleur-boot-emit <stage>` call site, and the
  file-wide literal count equals the provision-block count.

After the change, all 22 rows went RED as intended (the original 10 plus 12 new survivors), H2
stayed green, and restore was verified. The one mutant left, an emit wrapped in `if false`,
cannot be seen statically; the emitter suite's TD1 row catches it.

## Key Insight

A negative assertion quantifies over a set, and I had enumerated that set from my own guards. So
a battery that mutates the guarded kinds cannot find what the guards omit: it samples the same
set twice. The fix is not a longer list of forbidden kinds. Compare the observed shape to the
exact expected shape, so anything unlisted fails by construction.

For a once-only signal, a second emitter anywhere in the file is the throttle bug in a new place.
So the guard's region must be the whole file, not the block the emit happens to live in.

## Session Errors

1. **markdownlint MD038 on two code spans (plan phase).** Recovery: fixed before commit.
   **Prevention:** existing pre-commit lint; none needed.
2. **The planner's verify-agent prompt cited #7142, which was never cited (plan phase).**
   Recovery: dropped. **Prevention:** check `gh issue view N --json title` before putting any
   `#N` in an agent prompt.
3. **Mutation row M6 anchored on `frequency_minutes = 33`, which also occurs in the rule's
   comment.** Recovery: the harness's `count == 1` assert aborted the run, and the row was
   re-anchored on the indented code line (two spaces, `frequency_minutes = 33`, newline). **Prevention:** keep an
   exactly-once assert in every mutation replace, and anchor on the indented code line.
4. **The ADR-257 correction note was inserted mid-sentence, because the anchor ended partway
   through a line.** Recovery: caught on read-back and moved to the paragraph end.
   **Prevention:** anchor insertions on a paragraph boundary (a blank line, or the start of the next list item), never
   on a phrase, and read the changed region back.
5. **MD031: the new runbook code fence had no blank line after it.** Recovery: blank line added.
   **Prevention:** existing lint.
6. **The #9262 session-state commit was refused by `lint-infra-no-human-steps`.** The operator
   constraints line paired an actor with "terraform applies". Recovery: reworded as
   "this pipeline makes no production writes". **Prevention:** existing lint; state constraints
   as properties of the pipeline, not as actor imperatives.
7. **The stop hook fired three times while the report-only panel was running.** My closing text
   named fixes I would apply. Recovery: stated the hold with `<stop>BLOCKED: …</stop>`.
   **Prevention:** while blocked, report what is held and why, and do not narrate future actions.
8. **The self-run battery was green, and 15 survivors existed.** Recovery: shape pins as above.
   **Prevention:** for any HCL/YAML absence guard, pin the row-kind multiset and the top-level
   attribute list, and add one mutation row per axis (kind, comment form, meta-argument, sibling
   block, emitter region), not N rows on the guarded kinds. Routed to
   `plugins/soleur/skills/plan/references/plan-sharp-edges.md`.
9. **The first degraded-rule comment said the detail carries "only the two reasons".** The
   emitter also appends `attempt` and `iid`. Recovery: read `cloud-init-inngest.yml:1322` and
   corrected it at write time. **Prevention:** read the emitter line before describing its
   output.

## Related

- `2026-09-30-one-throttle-over-a-repeating-and-a-once-only-signal-silences-the-once-only-one.md`
  (the #9176 bug this PR fixes)
- `plugins/soleur/skills/work/SKILL.md`: "audit a self-run battery's AXES, not its count"

## Tags

category: test-failures
module: apps/web-platform/infra/sentry
