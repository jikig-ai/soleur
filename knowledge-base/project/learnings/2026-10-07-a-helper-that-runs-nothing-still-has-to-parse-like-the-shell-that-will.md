---
title: "A helper that runs nothing still has to parse like the shell that will"
date: 2026-10-07
category: workflow-patterns
module: preflight
tags: [preflight, founder-check, static-parse, mutation-testing, legal-wording, ratchet, ADR-274]
---

# Learning: a helper that runs nothing still has to parse like the shell that will

## Problem

PR #9637 (issue #9578) added preflight Check 13: a founder-stated acceptance check that is frozen in git, run separately in the Check 10 bwrap sandbox, and judged by `founder-check.py`, a decision helper that executes nothing itself. Three review rounds (12 seats, 4 verification seats, 3 CLO wording checks) kept finding the same shape:

- The helper's static screen read the command one way and bash read it another. The security seat's differential between `shlex` and bash tokenisation (`fe234ddc6d`) found forms the screen passed and the shell would have expanded.
- Every wording change to a founder-facing string broke exact-string tests in several files, because the strings lived in tests, references and the ADR as separate copies. Three CLO rounds meant three sweeps.
- Mutation rows that "survived" were sometimes crashes or edits that never landed, so a crash read as a kill and a no-op as a survivor.
- The suite-integrity floors (tests, assertions, manifest lines) were hand-edited and went stale after each fix round.

## Solution

- Screen with the same grammar the shell uses. The helper keeps an allowlist (git subcommands, interpreters) and rejects bare forms it cannot prove it parses identically, and a differential test drives `shlex` and bash over one corpus.
- Keep every founder-facing sentence in one `WORDING` map in `founder-check.py`. The references and ADR cite the constant, and the exact-string tests read it. The legal constraint (no "verified", "proven" or "safe" in a founder-facing string) is then one assertion over the map rather than a sweep.
- Run the mutation battery in a sandbox from `scripts/soleur-sandbox.sh`: control first and green, assert each mutation landed, and treat a crash as neither a kill nor a survivor.
- Regenerate the integrity floors from the measured run (`448792fd50`, `3f7315f085`) rather than editing numbers.
- Record what is only a declaration (`--no-pr`, `--mode interactive` are unauthenticated) in ADR-274 as a limit, not as a control.

## Key Insight

A decision helper that never executes the command is still a security boundary, because its verdict stands in for execution. Its parser must be pinned against the real executor by a differential test, not by a list of known-bad inputs. The same reasoning applies to wording and counts: a value that exists in N copies is an N-site sweep; make it one definition and assert from it.

## Session Errors

1. **A review seat left HEAD detached in the sibling worktree (plan A).** Recovery: `git switch feat-homepage-demo-9577`. **Prevention:** report-only seats already forbid checkout; a seat prompt that needs another ref should use `git show <sha>:<path>`.
2. **`cat > "$TMPDIR/msg.txt"` failed on an unset variable.** Recovery: `mktemp`. **Prevention:** use the session scratchpad or `mktemp`, never an unchecked env var.
3. **First mutation batch had a crashing row and a not-landed row.** Recovery: redone with a landing assertion. **Prevention:** already stated in the review skill (control first, confirm landed, a crash is not a kill); no new rule.
4. **`$?` read after a pipe returned `tail`'s status.** Recovery: read the checker's own output. **Prevention:** assert on the checker's output or use `PIPESTATUS`.
5. **`work/SKILL.md` was 247 bytes over its ceiling after a routed pitfall bullet.** Recovery: reverted the bullet and corrected the learning. **Prevention:** `lint-skill-body-budget` caught it; check headroom before routing into a lifecycle skill.
6. **`lint-window-closure-assertion` failed on `fanoutSection` (plan A).** Recovery: added the `// window-assembly:` declaration. **Prevention:** covered by that lint.
7. **`cancel-superseded` failed.** Judged unrelated and non-required. **Prevention:** none; flake.
8. **A merge-queue run dequeued PR #9631 on the known flaky e2e (#9666).** Recovery: re-armed once. **Prevention:** tracked in #9666.
9. **The acceptance-check fork stalled on a dead monitor with 8 unpushed commits and an uncommitted edit.** Recovery: resumed with an explicit push instruction. **Prevention:** a fork brief should name "commit and push before any wait" as a step.

## Tags

category: workflow-patterns
module: preflight
