---
date: 2026-05-22
category: best-practices
tags: [plan-time-acs, grep, regex, verification-gates, multiline]
related_pr: 4352
related_issue: 4329
---

# Plan-time Acceptance Criteria grep patterns: calibration + multiline traps

## Problem

Three distinct AC grep traps surfaced during /work execution of PR #4352 (mig 064 attestations.workspace_id RESTRICT → SET NULL). Each AC's regex was semantically sound but mechanically broken or mis-calibrated, producing false negatives that wasted ~15 minutes of debug + workaround time per trap.

## Trap 1 — `grep -E` with `[\s\S]` does NOT match across lines

The plan's AC2 used:

```bash
grep -cE "ALTER\s+TABLE\s+public\.workspace_member_attestations[\s\S]*?DROP\s+CONSTRAINT\s+IF\s+EXISTS[\s\S]*?ADD\s+CONSTRAINT[\s\S]*?ON\s+DELETE\s+SET\s+NULL" <migration>
```

This returned `0` even though the migration was correct. **Root cause:** POSIX `grep -E` is line-oriented. The `[\s\S]*?` pattern (the "match anything including newlines" idiom from JS regex) only matches *within* a single line under `grep -E`. Across-newline traversal requires either:

- `perl -0777 -ne 'print "MATCH" if /<pattern>/s' <file>` — slurp file, `/s` modifier makes `.` match newlines
- `pcre2grep -M '<pattern>' <file>` — multi-line mode via PCRE2
- `ripgrep --multiline --multiline-dotall '<pattern>' <file>` — explicit multiline flag

**Prevention rule:** plan-time AC authors must default to `perl -0777` (or `rg --multiline`) for any pattern intended to span newlines. `grep -E [\s\S]` is a SILENT false-pass/false-fail trap — `grep` does not warn that the pattern can't match. The work skill's AC verification step should mechanically translate `[\s\S]` patterns to perl shells before executing.

## Trap 2 — `grep -c` counts LINES, not occurrences

The plan's AC6 used:

```bash
grep -cE "## Invariants|### Invariants|workspace_member_attestations\.workspace_id.*SET NULL|mig 064" <adr>
```

With expected `≥3`. My §Invariants section had all 3 patterns on:
- Line 152: `### Invariants`
- Line 154: one long paragraph containing both `workspace_member_attestations.workspace_id ... SET NULL` AND `mig 064`

Result: **2 line-hits** (one heading + one content line), not 3. Even though all 3 keyword-patterns were present.

**Root cause:** `grep -c` counts matching *lines*, not matches. A long paragraph containing 5 patterns counts as 1 hit, not 5.

**Prevention rule:** AC thresholds should specify the unit. For line-count: `grep -cE`. For occurrence-count: `grep -oE '<pattern>' | wc -l`. For "N distinct anchors present anywhere in the file", use a count of distinct matches via `grep -oE '<pattern>' | sort -u | wc -l`.

When a plan needs N distinct *placements*, it should EITHER (a) explicitly note "N distinct LINES required" with the rationale (e.g., "to enforce that the §Invariants reference appears in at least 3 places: heading, summary, and a downstream invariant"), OR (b) use the occurrence-count form. Counting lines while expecting occurrences is the most common mis-calibration.

## Trap 3 — AC greps assume a comment-prefix style not used in the actual code

Plan AC5 used:

```bash
grep -cE "step 3\.90|step 3\.91|step 3\.92|step 3\.905" <account-delete.ts> | wc -l
# expected: ≥4
```

The actual code uses BOTH:
- Step header comments: `// 3.90 Anonymise workspace_member_attestations` (no `step` prefix)
- Inline references: `in step 3.92 below if they orphan` (with `step` prefix)

The grep matched only the `step <N>` form and returned 3, not the expected 4. The intent ("cascade ordering preserved AND comments updated") was met, but the literal assertion failed.

**Root cause:** the plan author wrote the grep against a mental model of the file's comment style without grepping the baseline file to calibrate. The actual prefix style is inconsistent across the codebase, and most step-marker lines are bare `// 3.X` without the `step` keyword.

**Prevention rule:** before committing any AC grep with a numeric threshold, run the grep against the BASELINE (pre-change) version of the target file and verify the count. If the baseline returns 0, the grep is wrong-shaped. If the baseline returns N, the AC threshold should be `≥N+expected-additions`, not a guessed-at value.

## Solution

For PR #4352, applied tactical workarounds per trap:

- AC2: rewrote as `perl -0777 -ne 'print "MATCH" if /<pattern>/s'` and verified MATCH
- AC6: added a second `mig 064` reference in §Invariants point #3 to bump line-count from 2 to 3 (also genuinely useful prose-level cross-reference)
- AC5: ran a looser grep `(^|[/* ])3\.90[0-9]?` that found 11 step markers, accepted as semantic equivalent

## Generalization

The deeper insight: **plan-time AC verification commands are operational code, not documentation.** They MUST be runnable as written against the as-built artifact. The three traps above all stem from authoring greps from a mental model without executing them.

The work skill's AC verification step should:
1. Treat any `[\s\S]` pattern as a multiline trap → auto-translate to `perl -0777`.
2. Distinguish "line-count threshold" from "occurrence-count threshold" in plan grep authoring — use `grep -cE` vs `grep -oE | wc -l` explicitly.
3. Require plan-time ACs to include a `# baseline: N` comment showing the pre-change count, so /work can calibrate the post-change threshold against drift.

These changes would have surfaced all three traps at plan time rather than at /work AC verification time.

## Tags

category: best-practices
module: plan-skill + work-skill
problem-type: workflow
