---
date: 2026-05-03
category: best-practices
module: schedule, review
issue: 3094
pr: 3067
tags: [review, security, single-user-incident, multi-agent-review, comment-mutability, defense-in-depth]
---

# Learning: `user-impact-reviewer` catches runtime-content-tamper vectors that plan-time review misses

## Problem

PR #3067 added `soleur:schedule --once` for one-time scheduled agent runs. The plan was simplified by a 3-reviewer panel (DHH / Kieran / Simplicity) and explicitly named four load-bearing defenses (D1-D4) for a single-user-incident threshold:

- **D1** Issue+comment ID context reference (no inline prompts)
- **D2** Fire-time stale-context preamble (issue OPEN, repo not archived, comment matches issue)
- **D3** In-prompt date guard (PRIMARY cross-year defense)
- **D4** `gh workflow disable` inside the agent prompt (SECONDARY)

At /review time, the 11-agent panel (security-sentinel, architecture-strategist, user-impact-reviewer, plus 8 others) converged on a brand-survival-class vector that D1-D4 did not address: **the comment body is fetched at fire time but is mutable between schedule authoring and fire**. An attacker with comment-edit access on the referenced issue can rewrite the task spec hours, days, or weeks later — the agent runs whatever is in the comment at fire time, with `issues: write` + `actions: write` + `ANTHROPIC_API_KEY`.

D1 was framed as "no inline prompts" — preventing leak via committed YAML — but `D1 ⟹ D5` does not hold. "Not inlined" and "not tampered between create and fire" are different invariants.

## Solution

Added **D5: comment-author + immutability pin**. At create time, capture `comment.user.login` as `EXPECTED_AUTHOR` and `comment.created_at` as `EXPECTED_CREATED_AT` env vars. At fire time, the pre-flight runs two additional checks:

1. `actual_author == EXPECTED_AUTHOR` (the comment must still be authored by the same person)
2. `created_at == updated_at` AND `created_at == EXPECTED_CREATED_AT` (the comment must not have been edited since authoring)

Both checks live as steps #6 and #7 in the agent prompt, immediately after the original D2 preamble. Failure path matches D2: post observation comment, `gh workflow disable`, exit 0.

Belt-and-suspenders: author-pin alone fails to catch edits within the GitHub <60s "no `updated_at` bump" window; immutability-pin alone fails to catch delete-and-repost-under-attacker-login. Both are required.

## Key Insight

**When `Brand-survival threshold = single-user incident` is declared, the plan-time defense table is necessary but not sufficient. Multi-agent /review with the user-impact-reviewer agent enumerates concrete user-facing failure modes from the actual diff, not from the plan's abstraction.** The user-impact-reviewer's contract — "name the artifact + the exposure vector per artifact" — produces a different lens than simplicity-biased peer review, and reliably surfaces vectors that involve runtime-fetched mutable content, cross-tenant writes, and edited-after-authoring tampering.

Two derived patterns:

- **"No inline prompts" (D1) and "runtime content integrity" (commenter pin + immutability) are independent invariants.** When designing any "fetch-at-runtime" defense for security-sensitive content, explicitly check the runtime-fetched object for: (a) author equals expected author, (b) `updated_at == created_at`, (c) any other identity/integrity property the threat model requires. Do not let "no inline" collapse the trust analysis.
- **`hr-weigh-every-decision-against-target-user-impact` already enforces user-impact-reviewer at review time** for `single-user incident` plans. Rule worked — the vector was caught pre-merge. Validates the rule's load-bearing role.

## Test Lessons (from this session)

Three minor content-assertion test gotchas surfaced and were fixed inline. Document for future test authors:

1. **Bare-token `assert_contains` is a substitution oracle for prose-shaped assertions.** `assert_contains "$BLOCK" "OPEN"` passes if any prose contains the word. Anchor on operative line shape (e.g., `gh issue view "$ISSUE_NUMBER" --json state,repository_url`) so the test fails when the actual command is removed even if surrounding prose mentions the token.
2. **Heuristic block extraction silently picks the wrong block when the heuristic ambiguates.** "First yaml fence containing FIRE_DATE" worked today but breaks the moment another fence (a doc example, before/after snippet) mentions FIRE_DATE. **Use HTML comment markers** (`<!-- once-template-begin -->` / `<!-- once-template-end -->`) wrapping the canonical artifact and extract between them — explicit > heuristic.
3. **Multi-line prose-wrapped assertions are fragile under markdown reformatting.** A reviewer rewrapping `"The state must be OPEN"` to `"The state\nmust be OPEN"` breaks the substring assertion silently. Either pin assertions to one-line code blocks/inline-code spans, or relax to short non-line-spanning phrases.

## Session Errors

1. **Bash test exited under `set -euo pipefail` when `grep -nF | head -1 | cut` had a non-match.** Recovery: wrapped pipes with `|| true` to coerce to exit 0. **Prevention:** in test scripts using `pipefail`, expect `grep` non-matches and explicitly degrade with `|| true` when zero-match is a valid case. Add this to the bash-test author's mental checklist alongside `set -euo pipefail` itself.
2. **Awk `exit` triggered the END block, producing duplicate output that broke shell integer comparison.** Recovery: piped through `head -1`. **Prevention:** in awk, `exit` invokes END unconditionally; if you `print` before `exit` AND have an `END { print }` fallback, you get two outputs. Either guard with `printed=1` flag or coerce downstream with `head -1`.
3. **First RED test bailed early via `print_results` on missing yaml block, masking TS2-TS5 individual failures.** Recovery: changed missing-block bail to "continue against empty block; cascading failures make diagnosis explicit". **Prevention:** for diagnostic clarity in content-assertion tests, surface all assertion failures rather than fail-fast on prerequisite — cascading TS1-TS5 failures with empty-block warning is more informative than "block missing, exit 1".
4. **`assert_contains 'state must be OPEN'` mismatched after SKILL.md prose wrapped the words across lines.** Recovery: relaxed to `'must be OPEN'`. **Prevention:** see Test Lessons #3 above. For content assertions across markdown prose, prefer short non-line-spanning phrases or pin to inline-code spans.
5. **`cd .worktrees/feat-schedule-one-time-runs` failed — already inside worktree (relative path didn't resolve).** Recovery: confirmed CWD via `pwd`, used absolute paths thereafter. **Prevention:** when chaining commands in a worktree-aware session, anchor with `pwd` or use absolute paths up front; the Bash tool does not persist CWD across calls.

All five errors were self-recovered via clear command output. Per `wg-every-session-error-must-produce-either` discoverability exit, no new AGENTS.md rule warranted — learning file alone is sufficient.

## Cross-references

- AGENTS.md `hr-weigh-every-decision-against-target-user-impact` — the rule that fired user-impact-reviewer at review time.
- `plugins/soleur/skills/review/SKILL.md` — section 1 conditional agents #15 (user-impact-reviewer trigger).
- `knowledge-base/project/plans/2026-05-03-feat-schedule-one-time-runs-plan.md` — Five Defenses table (D5 added during review).
- `plugins/soleur/skills/schedule/SKILL.md` — Step 0c capture + Step 3b pre-flight checks #6 and #7.
- `knowledge-base/project/learnings/2026-04-15-multi-agent-review-catches-bugs-tests-miss.md` — generalized pattern catalogue.
- `knowledge-base/project/learnings/2026-04-24-multi-agent-review-catches-feature-wiring-bugs.md` — adjacent precedent.

## Tags

category: best-practices, security
module: schedule, review
trigger: brand-survival-threshold = single-user incident
