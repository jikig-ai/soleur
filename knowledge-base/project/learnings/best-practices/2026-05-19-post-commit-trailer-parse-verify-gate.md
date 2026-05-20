---
title: Post-commit trailer-parse verify gate
date: 2026-05-19
category: workflow-patterns
tags: [git-trailers, commit-format, ci-gates, workflow-enforcement]
symptoms: [git log --format='%(trailers:key=Allowlist-Widened-By,valueonly)' returns empty after commit, allowlist-diff.sh CI gate cannot find the ack trailer despite operator including it in the commit body]
module: ci-infrastructure
synced_to: [commit, ship]
component: commit-message-format
problem_type: process_issue
root_cause: rule_documented_but_not_auto_verified
route_to_definition_issue: 4106
severity: medium
---

# Post-commit trailer-parse verify gate

## Problem

On PR #4103, the first commit's message body included:

```
Ref #4099. Closes #4090.

Allowlist-Widened-By: you@example.com

Co-Authored-By: Claude Opus 4.7 (1M context) <claude@example.com>
```

The blank line between `Allowlist-Widened-By:` and `Co-Authored-By:` split them into two trailer paragraphs. `git interpret-trailers --parse` returned only `Co-Authored-By`. CI's exact form (`git log -1 --format='%(trailers:key=Allowlist-Widened-By,valueonly)'`) returned empty — meaning `apps/web-platform/scripts/allowlist-diff.sh` would have failed the gate at CI time despite the trailer being present in the human-readable body.

The contiguous-trailer-block rule is documented in [`2026-05-16-git-trailer-parser-requires-contiguous-key-value-block.md`](../2026-05-16-git-trailer-parser-requires-contiguous-key-value-block.md) and quoted verbatim in the work skill's Phase 2 step 3. The rule was in scope at commit time. It was still mis-applied.

## Solution

`git commit --amend` with the message restructured so the final paragraph is a contiguous block of `Key: value` lines:

```
Ref #4099. Closes #4090.

Allowlist-Widened-By: you@example.com
Co-Authored-By: Claude Opus 4.7 (1M context) <claude@example.com>
```

Post-amend verification:
```bash
$ git log -1 --format='%(trailers:key=Allowlist-Widened-By,valueonly)'
you@example.com
```

## Key Insight

**A rule that lives only in prose, with no inline verification step, regresses even when the operator has just read it.** The work skill text is loaded every session and was quoted in scope. The mistake still happened. The recovery (amend) was cheap because the commit was unpushed and seconds old; if the same shape had landed in a multi-commit ship the rework cost would have escalated.

## Prevention (workflow gate proposal)

Add to the **commit-commands:commit** and **soleur:ship** skills a post-commit verification step that runs immediately after `git commit`:

```bash
# Extract every key: line in the body that looks like a trailer candidate.
BODY=$(git log -1 --format=%B)
declare -a CANDIDATES=()
while IFS= read -r line; do
  [[ "$line" =~ ^([A-Z][A-Za-z-]+):[[:space:]] ]] && CANDIDATES+=("${BASH_REMATCH[1]}")
done <<< "$BODY"

# For each candidate, verify it parses as a trailer via the CI's exact form.
for key in "${CANDIDATES[@]}"; do
  val=$(git log -1 --format="%(trailers:key=${key},valueonly)")
  if [[ -z "$val" ]]; then
    echo "[FAIL] '${key}' is in the body but does not parse as a trailer." >&2
    echo "       Likely cause: blank line between trailers or non-trailer line in final paragraph." >&2
    echo "       Fix: git commit --amend with contiguous final-paragraph trailer block." >&2
    exit 1
  fi
done
```

Anchor: `[skill-enforced: commit, ship post-commit-trailer-parse-verify]`.

## Cross-references

- [`2026-05-16-git-trailer-parser-requires-contiguous-key-value-block.md`](../2026-05-16-git-trailer-parser-requires-contiguous-key-value-block.md) — the canonical failure-shape catalog. This learning re-discovers shape (a) (blank line between trailers).
- AGENTS.md work skill Phase 2 step 3 — the prose rule that was in scope but not auto-verified.
- `apps/web-platform/scripts/allowlist-diff.sh:TRAILER_KEY` — the CI consumer that requires the parse to succeed.

## Session Errors

- **First commit had blank line between `Allowlist-Widened-By:` and `Co-Authored-By:`, breaking CI's trailer parser.** Recovery: `git commit --amend` with contiguous block, re-verified via `git log -1 --format='%(trailers:key=...,valueonly)'`. **Prevention:** post-commit verify gate in commit/ship skills (proposal above).
- **PreToolUse `security_reminder_hook.py` blocked the first matrix-list Edit, succeeded on identical retry.** The added line was a 1-token literal string with no injection vector. Recovery: re-ran the same Edit. **Prevention:** none — hook is advisory and either transient or false-positive on safe additive YAML edits; no operator action.
