---
date: 2026-05-11
issues: [3533]
prs: [3534]
tags: [tdd, exit-gates, dogfooding, skill-prose-lint]
category: best-practices
---

# Test-all.sh exit gate self-validated on the PR that created it

## Problem

PR #3534 added a `bash scripts/test-all.sh` exit-gate to `soleur:work` Phase 2 (issue #3533) so that orphan test suites (untouched siblings of the PR's touched test files) cannot bypass the inner-loop TDD checks. The risk being mitigated: PR #3512 had passed touched-file tests but failed CI when `scripts/test-all.sh` discovered an untouched orphan whose fixture broke under a tightened predicate.

## Solution

When the new step 9 was added, I dogfooded it before commit per the plan's Phase 3 step 1. `bash scripts/test-all.sh` ran 26 suites and reported 1 failure:

```
plugins/soleur/test/components.test.ts:
  (fail) No backtick file references in skills > skills/work/SKILL.md uses markdown links, not backticks
  Received: [ "`scripts/rule-metrics-aggregate.test.sh`" ]
```

The new step-9 prose I had just written contained `` `scripts/rule-metrics-aggregate.test.sh` `` — and that backtick form trips the lint at `plugins/soleur/test/components.test.ts:227-230`:

```ts
const backtickRefs = body.match(/`(?:references|assets|scripts)\/[^`]+`/g);
expect(backtickRefs).toBeNull();
```

The lint is in `components.test.ts` (a touched-file test for this PR's edits) — but it would have passed if I had only run `bun test plugins/soleur/test/components.test.ts` against the unmodified `work/SKILL.md`. The failure surfaced because the full-suite gate re-ran components.test.ts against the *current* working tree, which now included my prose addition.

Recovery: reworded to `e.g., an untouched `tests/scripts/test-rule-metrics-aggregate.sh` alongside the touched `rule-metrics-aggregate.test.sh``. The `tests/scripts/...` form is fine (doesn't match the regex anchor); the `rule-metrics-aggregate.test.sh` form is fine (no leading `scripts/`).

## Key Insight

The gate caught its own creating PR. The hypothetical defect class the gate exists to prevent — "touched-file tests pass but the full suite catches an orphan break" — is exactly what fired on the very commit adding the gate. That is the strongest possible validation of the gate's value.

Secondary lesson: when adding prose to `plugins/soleur/skills/**/SKILL.md`, the components.test.ts lint forbids `` `(references|assets|scripts)/<file>` `` backtick patterns. Either use a markdown link (`[file](./scripts/file.sh)`) or use the bare filename without the leading dir prefix.

## Prevention

Already enforced — no new rule needed. The components.test.ts lint catches `` `scripts/<file>` `` patterns at the touched-file boundary. The new work Phase 2 step 9 catches orphan-suite regressions across all SKILL.md edits.

## Session Errors

- **`scripts/<file>` backtick reference in SKILL.md prose** — Recovery: reworded prose to bare filename. Prevention: already enforced by `plugins/soleur/test/components.test.ts` backtick-references lint; the new test-all.sh exit gate caught it pre-commit.
- **Bash `&&` short-circuit on `grep -c 0` verification chain** — Recovery: rewrote with per-line `$(...)` substitution. Prevention: when chaining grep-count verifications, use `|| true` or per-line `$(...)` for any grep that can legitimately return zero.
