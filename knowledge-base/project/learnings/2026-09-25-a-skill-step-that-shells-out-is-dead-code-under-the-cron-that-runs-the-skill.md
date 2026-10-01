---
title: "A skill step that shells out is dead code under the cron that runs the skill"
date: 2026-09-25
category: integration-issues
module: content-writer, cron-content-generator
issue: 8774
pr: 8801
tags: [skill-prose, cron-containment, bash-allowlist, heredoc, dry-run]
---

# A skill step that shells out is dead code under the cron that runs the skill

## Problem

#8774 added a deterministic jargon scan to the content-writer skill (Phase 2.4): write the draft to a temp file and run `blog-jargon-scan.sh` on it, in one fenced Bash block. The plan, the deepen pass and a five-seat plan review all accepted it.

The skill's largest producer is the weekly `cron-content-generator`, which runs content-writer headless under a deny-by-default Bash containment hook. `CRON_BASH_ALLOWLISTS["cron-content-generator"]` is `gh issue list/create` and `gh label list/create` only, and the hook also denies `$(...)` substitution and interpreters (`bash …`) regardless of the allowlist. So on the path that writes most blog posts, the new step could never run. The skill text handled `SCAN_RC` values only, so a refused call was an undefined outcome the model might retry against `--max-turns`.

The same block pasted the model-written draft into a quoted heredoc (`<<'DRAFT_EOF'`). Quoting stops `$(...)` and backticks from expanding, but a draft line equal to the terminator ends the heredoc, and the rest of the draft then runs as shell. The security seat reproduced it. The block also re-pasted the whole draft on every re-scan, up to about 77k output tokens in the worst case.

## Solution

- Draft handling: `mktemp -d` for a scratch dir, the **Write** tool writes the draft, and Bash only runs the scanner by path. That closes the injection and the token cost, and fixes go through **Edit**.
- An explicit "the Bash call is refused" row: print `blog-jargon-scan unavailable (denied)` and do not retry. On the cron, the Blog note's jargon limits now rest on the model alone. Changing the containment would be a security decision for its own PR (decision-challenges T-5).
- A contract test pins the scan invocation and the absence of a heredoc around the draft.

## Key Insight

A skill is not run in one environment. Before adding a shell step to a skill, find every caller that runs it under restrictions (`git grep '/soleur:<skill>' apps/web-platform/server/inngest/`) and read that caller's `CRON_BASH_ALLOWLISTS` entry and the containment hook's global denials. A step the runner refuses is dead code on that path, and a skill that does not name the refusal leaves the model to improvise.

Two review instruments found what reading did not:

- The **coverage consult** ("which defect class is absent?") found a regression in my own review fix: a one-line JSON-LD block set a skip flag and never cleared it, so the rest of the post went unscanned.
- A **constrained dry run** of the rewritten Phase 2.4 found eight sentences an agent could not follow. One was a cleanup step that deleted the only copy of the fixed draft. Ten review seats had read that prose.

## Session Errors

1. **Read from the main-repo plugin path while in a worktree.** Recovery: re-ran from the worktree. **Prevention:** always `cd` to the worktree path; never to `/data/.../soleur/plugins`.
2. **Misused `list_runs`, then backgrounded a whole `&&` chain, starting a duplicate #8779 battery.** Recovery: identified both runs by `/proc/<pid>/cwd` and killed the duplicate's process group. **Prevention:** `list_runs <pattern>` needs an argument. A trailing `&` applies to the entire `&&` list, so launch detached work as a single `setsid nohup bash -c '…' &` statement.
3. **CI red on `grep-q-pipe-guard` for `|| grep -q` on a herestring line (#8779).** Recovery: split into two `elif` arms. **Prevention:** the guard's pattern `\|[[:space:]]*grep…-q` also matches the second bar of `||`; tracked in #8807.
4. **PIR gate first ran against the PR body alone.** Recovery: added the plan path to the body. **Prevention:** put `Plan: <path>` in the PR body when it is first drafted.
5. **The planning subagent stalled mid-deepen with no Session Summary.** Recovery: a SendMessage resume. **Prevention:** resume rather than respawn (the review skill's existing guidance).
6. **Plan AC5 was truncated mid-command.** Recovery: completed at work time and noted in the AC. **Prevention:** lint the plan for an unbalanced backtick in any AC line before handing it to work.
7. **The contract test's `--audience` extractor prefix included the closing backtick, so it matched zero lines.** Recovery: dropped the backtick. **Prevention:** run each extractor against the real file before writing its assertions; RED-for-the-wrong-reason looks identical to RED.
8. **The detached gate worktree had no `node_modules`.** Recovery: killed the run and symlinked top-level `node_modules` from the feature worktree. **Prevention:** a raw `git worktree add` is not `worktree-manager.sh create`; link dependencies before running suites there.
9. **The gate sat queued for about 40 minutes; review fixes then made its SHA stale.** Recovery: killed it and let ship's battery-owed check decide on the final SHA. **Prevention:** do not launch the full affected gate before review on a contended box; the plugin suite plus targeted consumers covered the diff.
10. **Plan-level design flaw: a Bash step in a skill the contained cron runs.** Recovery: Write-then-scan-by-path plus a "denied" row. **Prevention:** the plan sharp-edge bullet this learning adds.
11. **Heredoc-terminator injection of model text.** Recovery: Write tool. **Prevention:** never place model-generated text inside a shell heredoc. Use the Write tool, which does no shell parsing.
12. **My JSON-LD-skip fix left the flag set on a one-line block.** Recovery: only set the flag when the opener line has no `</script>`, plus a fixture. **Prevention:** when replacing an `exit` with a state flag, fixture the single-line form of the delimited construct.
13. **Phase 2.4 prose deleted the fixed draft during cleanup.** Recovery: read `draft.md` back before removing the dir. **Prevention:** dry-run any rewritten skill phase (the QA skill's existing note).
14. **`___` placeholders tripped MD037, and a blockquote swallowed the next line.** Recovery: bracketed placeholders and a blank line after the quote. **Prevention:** run markdownlint after every prose edit to a knowledge-base doc.
15. **The #8548 handoff linked a branch path that breaks after merge and archival.** Recovery: edited the comment to a commit permalink. **Prevention:** link plan sections in issue comments by commit SHA, never by branch.
16. **A reviewer reported vision.md as unchanged (a stale read).** Recovery: verified at HEAD and dismissed it. **Prevention:** re-derive any "file not updated" finding with `git show HEAD:<path>` before acting on it.
