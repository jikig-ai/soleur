---
title: "Milestone Enforcement: Silent Workflow Edit Failures and Defense-in-Depth Patterns"
date: 2026-03-26
category: integration-issues
tags: [workflow-edits, pretooluse-hooks, grep-flag-interpretation, audit-surface-coverage, github-actions, milestone-enforcement]
module: hooks, github-actions, guardrails
---

# Learning: Milestone Enforcement Session -- Silent Edit Failures, Grep Flag Traps, and Audit Surface Miscounts

## Context

The feat-milestone-enforcement session implemented three-tier defense-in-depth for milestone assignment on all GitHub issue creation surfaces: PreToolUse hook guard (Guard 5 in guardrails.sh), prose rules (AGENTS.md and constitution.md), and code-level changes across 18 surfaces (scripts, workflows, skills). Three distinct errors occurred during implementation.

## Session Errors

### 1. GitHub Actions workflow edits silently blocked by security_reminder_hook.py

**Symptom:** All 10 workflow file edits via the Edit tool appeared to succeed -- no error was raised, and the tool returned normally. However, the `security_reminder_hook.py` PreToolUse hook on `.yml` files outputs a security warning that was interpreted as an edit rejection. The changes did not persist in the files. This was only discovered later when grep verification showed the expected `--milestone` flags were absent from all 10 workflow files.

**Impact:** Required re-applying all 10 workflow edits, doubling the work for that portion of the implementation.

**Root cause:** The PreToolUse hook for `.yml` files fires a security advisory on the first Edit attempt. The agent treated the advisory output as confirmation of success rather than verifying the file content changed.

**Prevention:** After editing any `.yml` file, immediately verify with grep that the change persisted. Do not trust the Edit tool's return status alone when PreToolUse hooks are active on the target file type. Example verification pattern:

```bash
grep '--milestone' .github/workflows/target-file.yml
```

### 2. Guard 5 grep flag interpretation -- `--milestone` parsed as grep flag

**Symptom:** The initial Guard 5 implementation in `guardrails.sh` used `grep -qE '--milestone'` to check whether `gh issue create` commands included the `--milestone` flag. The `grep` command interpreted `--milestone` as a command-line flag rather than a search pattern, causing the guard to malfunction silently.

**Impact:** Guard 5 did not correctly detect the presence or absence of `--milestone` in commands, rendering the hook ineffective until fixed.

**Root cause:** Strings beginning with dashes (`--`) are ambiguous to `grep` -- without explicit end-of-options signaling, they are parsed as flags rather than patterns.

**Fix:** Changed to `grep -qF -- '--milestone'`, where `--` signals end of options and `-F` treats the pattern as a fixed string rather than a regex.

**Prevention:** Always use `grep -qF --` when matching strings that start with dashes. The `--` (end-of-options) separator is mandatory for any grep pattern beginning with a hyphen.

### 3. Plan surface count off by 1 -- missed `scheduled-community-monitor.yml`

**Symptom:** The planning phase identified 17 surfaces requiring `--milestone` enforcement. During review, the security-sentinel agent caught that `scheduled-community-monitor.yml` (surface 18) was missing from the implementation -- it contained a `gh issue create` call without `--milestone` that the plan had not accounted for.

**Impact:** Without the review catch, one enforcement surface would have shipped without milestone assignment, leaving a gap in the defense-in-depth strategy.

**Root cause:** The planning agent's surface enumeration relied on a manual inventory rather than running the exhaustive grep query itself. The automated search would have found all 18 surfaces.

**Prevention:** When auditing all instances of a pattern across a codebase, run the search query directly (`grep -rn 'gh issue create' .github/ plugins/ scripts/`) rather than relying solely on a planning agent's count. Verify the implementation covers every match from the search results, not just the count from the plan.

## Key Insight

PreToolUse hooks that output warnings (like `security_reminder_hook.py` for `.yml` files) create a dangerous failure mode: the Edit tool may report success while the change silently fails to persist. This is distinct from a hard block (which raises an error) -- it is a soft block that appears to succeed. The only reliable defense is post-edit verification via grep or file read. This pattern applies to any file type that has a PreToolUse hook with advisory output.
