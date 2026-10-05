---
module: System
date: 2026-10-05
problem_type: workflow_issue
component: documentation
symptoms:
  - "A grep -c over `fallthrough_type = \"NoOne\"` returned 4; only 3 lines were rules and the fourth was a comment at issue-alerts.tf:241"
  - "An awk that tagged each match with the last `resource \"sentry_alert\"` header seen blamed that comment on auth_per_user_loop, which is ActiveMembers"
  - "The miscount was given to the operator as the reason for a change at the dispatch approval prompt, then copied into the plan, tasks, session state and a commit message"
root_cause: logic_error
resolution_type: documentation_update
severity: medium
tags: [premise-validation, grep-count, approval-prompt, review-panel, count-drift, c4]
synced_to: []
---

# Learning: a count I put in an approval prompt was a grep that had counted a comment

Issue #9312 / PR #9527: delete the hand-maintained "40 of the 43 `sentry_alert` rules ... three deliberately set NoOne" sentence (and three rule names) from the C4 `sentry -> founder` edge in `model.c4`, and re-render `model.likec4.json`.

## Problem

The change was dispatched on a false premise that I stated to the operator as fact at the approval prompt: "the number is already wrong: 39 of 43 with four NoOne rules, and `auth_per_user_loop` is unnamed". It was not wrong. `apps/web-platform/infra/sentry/issue-alerts.tf` has 43 `sentry_alert` resources and **three** rules that set `fallthrough_type = "NoOne"` (`git_data_boot_warning`, `byok_cap_exceeded`, `web_luks_boot_warning`), so the old text was accurate on `main`.

The "four" had two sources, both mine:

1. `grep -c 'fallthrough_type *= *"NoOne"'` counts every matching LINE, and a prose comment at line 241 (inside the block above `git_data_boot_warning`) quotes the same literal.
2. An `awk` that remembered the last `resource "sentry_alert"` name and printed it beside each match attributed that comment to `auth_per_user_loop`, because the comment sits after that resource's closing brace but before the next resource header. That produced a confident, named, wrong fourth rule.

The wrong premise then spread: plan Overview, Premise Validation, Cut List and Property List, `tasks.md`, `session-state.md`, and the message of the first commit. My correction round repeated it in the second commit message (it called `auth_per_user_loop` a frozen rule "whose NoOne is captured live state") while fixing a different overclaim ("the non-paging halves of a severity split", which is true for two of the three and false for `byok_cap_exceeded`, whose routing is an open decision).

Four independent seats found it: the security seat and the history seat each re-derived the rule list line by line, the quality seat found the plan's file-set and acceptance-criteria inaccuracies, and the fix-round verifier re-checked it. I confirmed by listing each match with its line number and enclosing resource, which is the second method I should have used before the prompt.

## Solution

- Corrected the plan, tasks and session state to three NoOne rules, and rewrote the deletion rationale to the one that is independent of the miscount: nothing verifies the count (`c4-count-parity.test.sh` has no row for it), every new alert rule needs a hand edit, and its text has been hand-edited across several PRs (31 of 33 at #8694, 36 of 38 in #9312, 40 of 43 now).
- Kept the diagram edit as made: it carries no number and no rule names, says "a few rules set fallthrough_type NoOne instead (issue-alerts.tf is the authoritative list)", and makes no claim about why a rule is NoOne.
- Put the correction in the pushed history as a new commit (the earlier commit messages cannot be amended after a push) and disclosed it to the operator in the final report, since the approval rested on the wrong figure.

## Key Insight

- **A number you are about to put in an approval prompt is a claim to re-derive with a second method, because the operator will decide on it.** A count taken by `grep -c` is a count of matching LINES, and a literal that a rule's own comment quotes matches twice. Re-derive by listing each match with its line, the enclosing block and whether the line is code or a comment, then count the list.
- **A per-block attribution in `awk`/`sed` has to reset at the block's closing delimiter, not only at the next header**, or trailing and leading comments between blocks are charged to the wrong resource.
- **The decision can survive a false premise and still need the correction disclosed.** Here the deletion stood on an independent rationale, so the work was right; the operator still approved it on a figure that was wrong, so the report names the error.
- Fix commits written to correct one overclaim are where the same class reappears: re-read every sentence the correction ADDS (including the commit message) against the artifact before pushing.

## Session Errors

1. **Miscounted NoOne rules (`grep -c` matched a comment; `awk` blamed `auth_per_user_loop`) and stated it to the operator as fact.** Recovery: seats and a per-line re-check found three rules; plan, tasks, session state corrected; disclosed in the final report. **Prevention:** before a count goes into an approval prompt, list every match with line, enclosing block and code-versus-comment, then count the list.
2. **The correction commit repeated the same error** (called `auth_per_user_loop` a frozen NoOne rule). Recovery: a new corrective commit and the corrected plan text (pushed messages are not amended). **Prevention:** re-derive each claim a correction adds, including commit-message prose, against the artifact it names.
3. **First rewrite generalized "non-paging halves of a severity split" over rules where it is false for one.** Recovery: read the comment above each NoOne rule before the panel, then removed the claim. **Prevention:** a general sentence replacing an enumeration must hold for every member of the enumeration; check each.
4. **A probe `cd`'d into a sibling worktree and silently moved the primary working directory.** Recovery: re-entered the primary checkout before running `worktree-manager.sh create`. **Prevention:** use `git -C <path>` or `(cd … && …)` in a subshell for read-only probes of other trees.
5. **A foreground `timeout 540` deploy-arm wait hit my own cap without a verdict** (the release arm needed a cold 10 minute rebuild). Recovery: re-ran under Monitor with output to a log file and an rc echo. **Prevention:** wait on `deploy-arm.sh find --wait` through Monitor, never a bounded foreground call.
6. **Plan-accuracy slips caught by the quality seat:** `session-state.md` missing from the file set, `c4-count-parity` and `render-c4-model` credited as evidence for an edge neither reads, a residual-grep AC whose pattern matched an unrelated shell comment. Recovery: fixed inline; only `c4-model-freshness` is evidence for the edit. **Prevention:** run each AC's literal command before ticking it and state which suite actually exercises the change.
7. **The `e2e` CI job hit the known flake #8785 twice on PR #9496 with different signatures** (`ERR_CONNECTION_REFUSED` after the dev server stopped answering, then Turbopack failing to resolve the Google font module). Recovery: red-on-main probe (green on main), occurrence comment on #8785, one `gh run rerun --failed` each. **Prevention:** none beyond the existing tracker.
8. **The BEHIND auto-sync restarted all required checks five times on a busy `main`.** Recovery: a poll variant that defers the sync until the current head's checks settle; recorded on the existing tracker #8683. **Prevention:** tracked on #8683.
9. **A `git log -S` pickaxe returned one commit, so a history claim could not rest on it.** Recovery: limited the plan's drift-history sentence to values I had measured. **Prevention:** a pickaxe string that changed spelling across versions finds only some of them; measure each version directly with `git show <sha>:<file>` before quoting a history.

## Cross-references

- `2026-08-17-i-corrected-a-fabricated-claim-by-grepping-its-phrasing-and-missed-a-site.md` (a sweep keyed on phrasing; here the miscount was keyed on a pattern)
- `2026-08-06-i-shipped-two-unmeasured-causal-claims-inside-the-lint-that-forbids-them.md` (claims a diff's prose adds need a falsifying command)
- Issues: #9312, #8683, #8785; PRs #9527, #9496.

## Tags

category: workflow-issues
module: System
