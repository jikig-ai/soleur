---
date: 2026-05-10
category: best-practices
module: skill-design, plan-precondition-gates, multi-agent-review
tags:
  - handshake-protocol
  - schema-drift
  - single-source-of-truth
  - precondition-staleness
  - parity-tests
  - multi-agent-review
pr: 3501
issue: 3502
---

# Handshake schema drift and stale precondition budgets in long-lived plans

## Problem

PR #3501 shipped the `gdpr-gate` skill — a code-level GDPR/CCPA/HIPAA pre-generation advisory gate whose Critical-finding escalation flow instructs the operator to write a row to `knowledge-base/legal/compliance-posture.md` Active Items. Two unrelated-looking failures surfaced during the work-and-review pipeline; both share a single root cause: **producer and consumer of a contract were drafted independently and drifted before the first invocation.**

### Failure 1 — handshake schema drift between producer and consumer

`plugins/soleur/skills/gdpr-gate/SKILL.md` §"Critical-finding escalation flow" told the operator to append:

```text
| <date> | <check_id> | #<issue> | <one-line summary> | <owner> |
```

`knowledge-base/legal/compliance-posture.md` documented the canonical Active Items table as:

```text
| Item | Issue | Status | Deadline | Notes |
```

Same column count, **completely different semantics**. An operator following the gate's exact instructions would write `<date>` into the `Item` column, `<check_id>` into `Issue`, `#<issue>` into `Status`, etc. — corrupting the table the `clo` agent reads.

Both files were authored in the same PR. Neither author ran the produced row through the consumer parser. `tsc --noEmit`, `bun test`, and `lefthook` were all silent on this — the contract is markdown prose, not a typed interface.

Caught only by `data-integrity-guardian` during multi-agent review.

### Failure 2 — stale plan-time precondition measurements

The plan was authored 2026-05-10 with this precondition assertion:

> "Cumulative ~1614 words; ~186 words headroom; gate description targets ≤30 words. **No sibling-skill description trim required.**"

At `/soleur:work` start (same day), the cumulative count was **1785 words / 15 word headroom**. The plan's gate description (29 words) would have pushed `bun test plugins/soleur/test/components.test.ts` over the 1800-word cap. The plan's Phase 1 §Precondition step said "halt and file a chore PR per `2026-04-21-skill-description-budget-at-cap-requires-plan-time-surgery.md`" if `<30 words headroom`. Reality already dictated halt-or-trim before /work began.

Mitigation: trimmed the gate description to 14 words inline, fitting in 1799/1800 budget. AC1's "≤30 words" cap still satisfied; AC21's "no sibling trim required" still satisfied at the diff level.

Root cause: between plan authoring and /work invocation, parallel branches landed in `main` adding new skills. The plan's word-headroom measurement is a falsifiable claim about a moving target.

## Root cause

Both failures share the structural pattern: **the plan-or-skill author measured a value at authoring time, treated the measurement as a stable property of the system, and downstream readers consumed the assertion as ground truth.**

- Failure 1: SKILL.md and compliance-posture.md were two views of one contract. The author of SKILL.md never re-read the consumer's documented schema.
- Failure 2: Plan word-budget headroom was measured at plan time. Between plan-time and /work-time (hours apart), other PRs landed and changed the denominator.

The class of bug: **point-in-time facts asserted as invariants in long-lived documents.**

## Solution

Three structural fixes, each addressing the class:

### 1. Handshake parity test for producer/consumer schemas

When skill `X` instructs an operator to write to file `Y` in some schema `Z`, the schema must be referenced from one place. Either:

- **Embed-and-validate:** `X` literally embeds `Z`, AND a test reads both `X` and `Y` and asserts byte-equality of the schema literal (the "single source of truth + parity test" pattern shipped in this PR for the canonical regex).
- **Reference-and-defer:** `X` says "write a row matching the schema documented in `Y` §header", AND `Y`'s header documents the schema explicitly enough to be the single source.

Picked **reference-and-defer** for this PR (commit `a0d0b015`): `compliance-posture.md` Active Items header comment IS the schema; `SKILL.md` now says "the canonical schema is" and embeds the canonical 5-column form, derived from `compliance-posture.md`.

### 2. Re-measure plan preconditions at /work start

Plans that quote stale point-in-time numbers (`bun test … reports X`, `wc -c < AGENTS.md = N`, "cumulative ~Y words; ~Z headroom") MUST be re-measured at /work Phase 1 §Preconditions before any implementation step depends on the assertion. Prefer measuring the claim's invariant (e.g., "≥30 words headroom") over the literal number.

The plan for #3501 already had Phase 1 §Preconditions step 2 doing this — and the re-measurement caught the discrepancy. The fix here is **don't trust the plan's quoted number; re-run the test.** Any plan that quotes "current = X" is signalling a precondition to verify, not an established fact.

### 3. Single-source-of-truth parity test for replicated literals

Three reviewers in this PR flagged that the canonical path-regex existed in 4 places (SKILL.md prose, hook script, test file, lefthook globs). No CI test verified parity. The parity test added in commit `a0d0b015`:

```typescript
test("hook script CANONICAL_REGEX matches the test's literal", () => {
  const hookContent = readFileSync(HOOK_SH, "utf8");
  const m = hookContent.match(/^CANONICAL_REGEX='([^']+)'/m);
  expect(m![1]).toBe(CANONICAL_REGEX_SOURCE);
});

test("SKILL.md documents the same regex literal", () => {
  expect(skillContent).toContain(CANONICAL_REGEX_SOURCE);
});
```

Generalizes: when a constant must be replicated for performance/distribution reasons, ship a parity test that reads each location and asserts byte-equality against the canonical declaration.

## Prevention

- **Add to `/soleur:plan` Phase 2 (planning):** when defining a multi-step handshake (skill instructs operator to write to file Y in schema Z), grep file Y for an existing schema BEFORE writing the producer's instructions. Adopt reference-and-defer or embed-and-validate; never let producer and consumer drift.
- **Add to `/soleur:work` Phase 0.5 / Phase 1 §Preconditions:** re-measure any plan-quoted number (word counts, byte counts, `git ls-files | wc -l`) before depending on it. Treat plan-quoted numbers as preconditions to verify, not facts.
- **Add to `/soleur:review` skill:** when a PR adds replicated literals (regex, canonical paths, schema strings) across ≥2 source files, expect a parity test. If absent, file as a P2 inline-fix.

## Session Errors

- **Plan precondition staleness — word budget** — Recovery: trimmed gate description from 29 → 14 words inline; AC1 ≤30 cap still satisfied. Prevention: re-measure plan-quoted numbers at /work start; treat them as preconditions to verify.
- **Schema contract drift between SKILL.md and compliance-posture.md** — Recovery: P1 fix in commit `a0d0b015` re-aligning to canonical 5-col schema. Prevention: when a skill produces rows for a target file, grep the target's header for an existing schema before drafting the producer's row template.
- **Canonical regex stored in 4 places, no parity test** — Recovery: parity test added in commit `a0d0b015`. Prevention: ship a parity test alongside replicated literals; review skill should expect one.
- **AGENTS.md rule body 642 bytes over ~600 cap** — Recovery: trimmed to 559 bytes. Prevention: measure rule byte length at authoring time, not at lefthook time. (`cq-agents-md-why-single-line` enforces; the gap is at authoring.)
- **Worktree `.git` is a file** — Recovery: used `/tmp/review-*.txt` instead of `.git/review-changed.txt`. Prevention: review/SKILL.md classification scripts use `/tmp/` not `.git/`. Discoverability exit applies (clear ENOENT).
- **Bash CWD reset to bare repo root** — Recovery: absolute paths to worktree on every Bash call. Prevention: existing rule `wg-at-session-start-run-bash-plugins-soleur` covers; reinforced by Bash tool's CWD non-persistence (already documented).

## Cross-references

- Plan: `knowledge-base/project/plans/2026-05-10-feat-gdpr-gate-skill-plan.md`
- Spec: `knowledge-base/project/specs/feat-compliance-skills-eval/spec.md`
- ADR: `knowledge-base/engineering/architecture/decisions/ADR-026-pii-gate-as-plan-work-phase-skill-with-diff-hook.md`
- Review fix commit: `a0d0b015`
- Related learnings:
  - `2026-04-21-skill-description-budget-at-cap-requires-plan-time-surgery.md` — the chore-PR fallback when plan-time word measurements are stale.
  - `2026-04-15-multi-agent-review-catches-bugs-tests-miss.md` — handshake schema drift caught by `data-integrity-guardian` is canonical for this catalogue.
  - `2026-05-09-llm-authored-plans-cite-fabricated-and-retired-rule-ids.md` — same class (plan-time fact assertion that drifts).
