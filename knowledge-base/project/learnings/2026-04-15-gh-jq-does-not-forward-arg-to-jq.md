---
title: "`gh --jq` does not forward `--arg` to jq; use shell interpolation with digits-only validation"
date: 2026-04-15
category: build-errors
module: ship-gate-detection
tags: [gh-cli, jq, shell-injection, security-review]
related:
  - pr: 2375
  - issue: 2374
---

# Learning: `gh --jq` does not forward `--arg` to jq

## Problem

In PR #2375, the ship Phase 5.5 Review-Findings Exit Gate needs to detect open review-origin issues cross-referencing the current PR via a jq regex:

```bash
PR_NUMBER=$(gh pr view --json number --jq .number)
gh issue list --state open --json number,title,body \
  --jq '[.[] | select((.body // "") | test("(^|\\s)(Ref|Closes|Fixes) #'"$PR_NUMBER"'(\\s|$|[^0-9])"))]'
```

`security-sentinel` flagged this as shell/jq injection: if `$PR_NUMBER` contains regex metacharacters or shell quotes, the regex widens silently or jq parses attacker syntax. The agent prescribed the canonical jq defense — pass the value as a jq variable:

```bash
--jq --arg pr "$PR_NUMBER" '... test("... #" + $pr + "...")'
```

Applied the fix. Runtime failed with:

```text
unknown arguments ["pr" "2375" "[.[]\n  ...\n]"]
```

## Root Cause

`gh issue list --jq <EXPR>` accepts a **single positional expression string**. It does not forward `--arg`, `--argjson`, `--slurp`, or any other jq flags to the underlying jq binary. The CLI treats everything after `--jq` up to the next gh flag as a single expression.

When you write `--jq --arg pr "$PR_NUMBER" '...expr...'`, gh sees:

- `--jq` (flag)
- `--arg` (becomes the value of `--jq`)
- `pr 2375 ...expr...` (unknown positional args)

This is the opposite of standalone `jq`, where `--arg pr "$PR_NUMBER" '<expr>'` is the idiomatic safe-injection pattern.

## Solution

For `gh ... --jq`, the only available defense is **validating the shell variable before interpolation**. Use a digits-only (or appropriate-shape) check:

```bash
PR_NUMBER=$(gh pr view --json number --jq .number)
[[ "$PR_NUMBER" =~ ^[0-9]+$ ]] || { echo "Error: PR_NUMBER is not a positive integer: $PR_NUMBER"; exit 1; }
gh issue list ... --jq '...test("... #'"$PR_NUMBER"'...")...'
```

Digits-only validation blocks both regex-metachar widening (`.`, `(`, `|` cannot appear) and shell/jq-quote injection (`'` cannot appear). After validation, shell interpolation is safe.

If you need `--arg` safety (e.g., the value is arbitrary user input), switch to two-stage piping:

```bash
gh issue list ... --json number,title,body \
  | jq --arg pr "$PR_NUMBER" '[.[] | select(... | test("... #" + $pr + "..."))]'
```

The two-stage form costs one extra subprocess and a JSON round-trip but restores `--arg` availability.

## Key Insight

Security review recommendations that assume standalone-jq semantics may not apply to `gh --jq`. When a reviewer prescribes `--arg`, always verify the target CLI forwards jq flags before implementing the fix. Most `gh` subcommands that expose `--jq` use it for output filtering, not parameterized queries.

## Prevention

- When implementing a reviewer-suggested `--arg` fix in a `gh ... --jq` context, smoke-test the command with a sample value **before** committing. Runtime failure ("unknown arguments") is the only signal — no lint catches it.
- If you cannot use `--arg`, fall back to shape-validation (`[[ =~ ]]`) on the shell variable, and document the constraint inline near the interpolation so future editors don't remove it.

## Session Errors (from this compound run)

1. **`gh label list` default pagination returns 30 labels** — Resolved with `--limit 500`. **Prevention:** when verifying label existence, always pass `--limit 500` or query by name.
2. **Pipeline `grep -oE '/issues/[0-9]+'` over `gh issue create` output returned empty** — The URL output has no `/issues/` prefix in the chain I used. **Prevention:** use `| grep -oE '[0-9]+$'` directly on the URL tail.
3. **GitHub search index eventual-consistency lag (~15s)** — Phase 3.1 gate-detection queries returned inverted counts immediately after label mutations. Required `sleep 15` between mutation and re-query. **Prevention:** document the lag in any gate-validation procedure that toggles labels and expects immediate query-result changes.
4. **`gh --jq --arg` invalid syntax** — See root-cause section above. **Prevention:** the Sharp Edge note routed to `review/SKILL.md` in this compound run.
5. **Plan success-criterion grep omitted markdown bold markers** — `grep -c 'Default action (...):  Apply ...'` returned 0 because the plan text included `**...:**`. **Prevention:** when plans include literal text with markdown emphasis, success-criterion greps must escape/match the emphasis.
6. **Over-aggressive `sed -i 's/- \[ \]/- [x]/g'` on tasks.md** — checked off items that hadn't actually run (Phases 3.3 and 5). Caught and reverted in-turn. **Prevention:** self-discipline; no rule needed.

## References

- PR #2375 commits `02b915c8` (initial gate), `227121b6` (broken --arg fix), `60a66b2b` (correct revert)
- Related rule: `rf-review-finding-default-fix-inline` in AGENTS.md
- jq manual: `--arg name value` passes pre-defined jq variable bindings — works for `jq` binary, not for `gh --jq` wrapper
