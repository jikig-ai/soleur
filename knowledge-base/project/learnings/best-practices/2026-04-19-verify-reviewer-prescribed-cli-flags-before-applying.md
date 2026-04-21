---
name: Verify reviewer-prescribed CLI flags before applying as fixes
description: Multi-agent reviewers can prescribe CLI flags or subcommands that don't exist; verify via --help before committing to the fix. Generalizes the gh-jq rule.
type: best-practice
category: review
date: 2026-04-19
pr: 2647
issue: 2615
---

# Verify reviewer-prescribed CLI flags before applying as fixes

## Problem

During multi-agent review of PR #2647, two independent reviewers prescribed CLI
fixes that referenced flags or subcommands that do not exist on the installed
`gh` binary:

1. `code-quality-analyst` (P2-3) suggested replacing
   `gh issue create ... | grep -oE '[0-9]+$'`
   with `gh issue create ... --json number --jq .number`. The `--json` flag does
   not exist on `gh issue create` (only on `gh issue list`/`view`). Verified via
   `gh issue create --help` AFTER applying the edit.
2. `security-sentinel` (medium) suggested replacing
   `gh issue close 2615 --comment "$(cat /tmp/aeo-pass-comment.md)"`
   with `gh issue close 2615 --body-file /tmp/aeo-pass-comment.md`. The
   `--body-file` flag does not exist on `gh issue close` (only `--comment
   <string>`, `--reason`, and `--duplicate-of`). Verified via
   `gh issue close --help` AFTER applying the edit.

In both cases I applied the suggestion verbatim, committed it, and then caught
the mismatch on a follow-up sanity check. Each required a revert + rework into
a CLI-form that actually exists:

- For `gh issue create`: parse the URL output with `awk -F/ '{print $NF}'` plus
  numeric guard (the URL ends in `/issues/<number>`, so the last path component
  is always the issue number).
- For `gh issue close`: split into `gh issue comment <N> --body-file <path>`
  followed by `gh issue close <N> --reason completed`. Two commands, but no
  shell re-expansion of file content.

## Solution

When a review agent prescribes a specific CLI invocation as a fix, verify the
flag/subcommand exists BEFORE applying:

```bash
# Check the exact flag the reviewer named
gh <subcommand> --help | grep -E "(--<flag>|-<short>)"

# Or for general subcommand support
gh <command> --help | grep -A2 "USAGE"
```

If the flag/subcommand is absent, do not silently swap to a "similar" one —
either:

1. Fall back to a verified safer pattern (e.g., shape-validate the variable
   before interpolation, split the operation into two verified commands).
2. Use a different tool (e.g., `awk -F/` instead of a non-existent `--json`).
3. Push back on the reviewer in the disposition table: "Suggested flag does
   not exist; using <alternative> instead — same security/correctness
   property."

## Key Insight

**Review agents hallucinate CLI flags as confidently as documentation does.**
The agent's training data may be stale, internally inconsistent (e.g.,
generalizing from `gh issue list --json`), or simply wrong. The cost of
verification is one `--help` call — significantly less than the cost of a
revert + rework + commit history pollution.

This generalizes the existing review-skill Sharp Edge for `gh --jq --arg`
forwarding. The pattern is class-wide, not just `gh --jq`-specific:

> Whenever a reviewer prescribes `--<flag>` for `<command> <subcommand>`,
> verify the flag exists on that subcommand via `<command> <subcommand>
> --help` before applying.

It also dovetails with the existing plan-preflight learning
(`2026-04-17-plan-preflight-cli-form-verification.md`): preflight verifies
the CLI invocations the plan PRESCRIBES; this rule verifies the CLI
invocations the REVIEWER PRESCRIBES as fixes. Same root principle, different
trigger surface.

## Session Errors

- **`code-quality-analyst` P2-3 prescribed `gh issue create --json`** —
  Recovery: revert edit, switch to `awk -F/ '{print $NF}'` URL parse with
  numeric guard. Prevention: verify reviewer-prescribed flags via `--help`
  before applying.
- **`security-sentinel` prescribed `gh issue close --body-file`** —
  Recovery: revert edit, split into `gh issue comment --body-file` +
  `gh issue close --reason completed`. Prevention: same as above.
- **`sleep 5` in foreground Bash chained after `gh workflow run`** —
  Violated `hr-never-use-sleep-2-seconds-in-foreground`; not blocked by any
  hook (none exists). Recovery: tolerated; the workflow returned. Prevention:
  use `Bash` with `run_in_background: true` for delayed checks, or a hook
  that scans Bash inputs for `sleep <N>` with N≥2 (chained or bare).

## Prevention

1. **Update `plugins/soleur/skills/review/SKILL.md` Sharp Edges** to
   generalize the existing `gh --jq` rule into a class-wide rule covering any
   `<tool> <subcommand> --<flag>` prescription. (See route-to-definition
   below.)
2. **Optional hook idea** (not implementing yet — bounded surface, mostly
   advisory): a PreToolUse hook on Edit/Write that detects newly-introduced
   `--<flag>` patterns inside fenced bash blocks and emits a soft warning
   suggesting `--help` verification. Likely too noisy to ship; keep the rule
   prose-only for now and revisit if the failure recurs.

## Related

- `knowledge-base/project/learnings/2026-04-15-gh-jq-does-not-forward-arg-to-jq.md`
- `knowledge-base/project/learnings/best-practices/2026-04-17-plan-preflight-cli-form-verification.md`
- `cm-when-a-reviewer-prescribes-arg-for-jq-injection` (review skill Sharp
  Edges, line 580 of review SKILL.md as of 2026-04-19)
- AGENTS.md `cq-docs-cli-verification` (related but applies only to
  user-facing docs; this learning covers internal scripts derived from
  reviewer prescriptions)
