# Learning: a branch dispatch of the workflow you edited is skip-masked, and claude_args is tokenised like a shell

PR 12136 (closes #12102) moved the CI claude pins onto the Bun 1.4.4 pair. Four review rounds found problems that every local check had passed.

## Problem

1. **The "real verification" could not verify.** The plan named a `workflow_dispatch` of `test-pretooluse-hooks.yml` on the branch as the proof that the bumped `claude-code-action` works. The PR edits that workflow, so the action printed "Skipping action due to workflow validation … identical content to the version on the repository's default branch" and exited 0 before installing the CLI or running a single guard test. The step carries `continue-on-error: true`, so its `conclusion` was `success` and the run was green. `constitution.md` already says a modified consumer can never be exercised by branch dispatch.
2. **An unquoted allowlist is split at its spaces.** `claude_args` goes through shell tokenising. On v1.0.101 the parentheses of `--allowedTools ...,Bash(gh pr list:*)` were dropped, widening the rule to bare `Bash` in a job holding `ANTHROPIC_API_KEY` and `issues:write`. On v1.0.263 the parentheses survive but the three space-bearing rules are still split into junk tokens, so the digest would silently lose its reads. A CTO ruling that read the source concluded v1.0.263 was fine; only a seat that executed the tokeniser with the locked shell-quote versions found the remainder.
3. **A pinned-version rationale was asserted, not measured.** The ADR addendum said SDK 0.3.310 embeds a Bun below the fix. `strings` on the linux-x64 package shows 0.3.309 to 0.3.311 all read Bun 1.4.4 (0.3.293 reads 1.4.3), so that bump was pair alignment.

## Solution

- Verify a bumped action only by a dispatch on `main` after merge, and read the run log (not the step conclusion) for the skip line. Recorded as a post-merge acceptance criterion.
- Quote the `--allowedTools` value (`"Write,...,Bash(gh pr list:*),..."`); all nine rules survive on every release. `operator-digest-workflow.test.sh` pins the quoting on the comment-stripped code, anchored at both ends.
- Measure the embedded runtime with `strings <bin> | grep -oE 'Bun v[0-9]+\.[0-9]+\.[0-9]+'` (the `grep -m1 '^Bun v'` form returns a template line).
- A lockstep guard (`apps/web-platform/test/claude-pin-lockstep.test.ts`) now ties the six action carriers, the SHA-to-tag pairs, `CLI_VERSION`, the Dockerfile, package.json and the pen-cli lock together.

## Key Insight

A check that returns green is a claim about the question it was able to ask. A dispatch whose action skips itself, a prose reading of a tokeniser, and a package version used as a proxy for the runtime inside it each answered an easier question than the one being certified.

## Session Errors

1. **The plan named a branch dispatch as the real verification** — Recovery: read the run log, found the skip line, rewrote Phase 2.6 and added a post-merge criterion — **Prevention:** route a bullet to the plan skill's Sharp Edges (done); never tick a verification from a step `conclusion` when `continue-on-error` is set.
2. **ADR-191 addendum claimed 0.3.310 embeds a vulnerable Bun** — Recovery: `npm pack` plus `strings` on three versions, reworded — **Prevention:** run the falsifying command for every causal claim a diff adds before writing it.
3. **The CTO F7 parse claim was half right** — Recovery: security seat executed the tokeniser, allowlist quoted, F7 lead note added — **Prevention:** a source-read ruling carries "not executed" and the fix must not depend on it; execute the cheap probe.
4. **markdownlint "passed" by printing usage** — the path was in `.markdownlintignore`, so zero files matched and the CLI printed help at rc 0 — Recovery: negative control in-repo — **Prevention:** run every linter once against a known-bad file before reading its silence.
5. **Mutation M4 did not land** (a `#` sed delimiter inside a pattern containing `#`) — Recovery: the landing check caught it, re-ran with `|` — **Prevention:** keep the landing assertion on every mutation row.
6. **Expected-set comparison failed on hand ordering** — the first run of the discovery guard compared an unsorted list to a sorted walk — Recovery: compare sorted copies — **Prevention:** sort both sides of any set equality.
7. **The tracker probe scanned a capped list** (`-L 200` of 312 open issues) — caught by the security and code-quality seats — Recovery: read the issue by number — **Prevention:** a probe that must find its own tracker looks it up by number.
8. **I read the wrong clock** and reported a run as queued for 20 minutes when it was 6 — Recovery: compared `date -u` with `createdAt` — **Prevention:** compare UTC before reasoning about elapsed time.
9. **Hook rejections** (compound `cd && cat > && git commit`, `rm -rf` on a probe directory, a filing without a user-visible consequence) — Recovery: split commits into their own calls, `rm -f` plus `rmdir`, `meta/machinery` label — **Prevention:** none needed; the hooks did their job and their messages named the repair.

## Tags
category: integration-issues
module: ci-pins, claude-code-action, operator-digest
