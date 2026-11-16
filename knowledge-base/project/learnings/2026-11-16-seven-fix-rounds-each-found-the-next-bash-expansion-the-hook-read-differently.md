---
title: Seven fix rounds each found the next bash expansion the cron hook read differently
date: 2026-11-16
category: security-issues
module: apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs
tags: [cron, containment, pretooluse-hook, bash-expansion, git-pathspec, fix-rounds]
issues: ["#12757", "#12806", "#9601"]
---

# Learning: close a shell-expansion class, do not deny-list its spellings

## Problem

PR #12806 (#12757) hardened the cron containment PreToolUse hook. The hook reads the raw command text and runs
token rules on it (`git add .`, `commit -a`, worktree paths, the gh filing gate). Bash then expands that text before
git or gh sees it. Every place where the hook and bash disagree is a way to re-spell a refused command.

The first fix round denied one expanding form, a brace list matched by a regex. Each security seat after that found
the next disagreement, each measured with real bash and real git:

| Round | Form that got past | Effect (measured) |
|---|---|---|
| 1 | `{,~/.config/git}` | worktree planted at `~/.config/git` |
| 2 | `{~/.config/git,HEAD@\{0\}}` (escaped brace), `\' {-a,-m} \'` (escaped quote read as a quoted span) | worktree plant; working `git commit -a` |
| 3 | `$'\'' $(cmd) #'` (ANSI-C quoting), `$'-A'` | command substitution on both git-carrying crons; blanket stage (also on `main`) |
| 4 | `$[GIT_CONFIG_GLOBAL=0]` (arithmetic), `{-a,-m{}}` (nested) | config pin reset, fsmonitor code execution (also on `main`) |
| 5 | `git add -?` with a planted `-A` file, `--pathspec-from-file` | whole-tree stage |
| 6 | `git add ~+` (`$PWD`), `git commit -m x .` | whole-tree stage / commit (both on `main`) |
| 7 | `-Sc .` (optional attached value) | pathspec skipped by the option parser |

## Solution

Stop listing forms; refuse each class outright in `dangerousMetacharReason`, where quoting is tracked once:

- any backslash outside single quotes (then `stripQuoted` tracks quotes the way bash does);
- `$'…'` and `$"…"`;
- any `$` not followed by whitespace;
- any unquoted `{`, glob character (`*`, `?`, `[`, extglob) or word-start `~`.

For git's own argument parsing (not the shell): any unambiguous long-option prefix counts (`--al` is `--all`),
`--pathspec-from-file` is a whole-tree stage, a `git commit` pathspec records working-tree content and ignores the
index (so `git commit -m x .` is `commit -a`), and `-S`/`-u` own the rest of a short-option cluster.

Two over-denies came with the class rule and were fixed in the same rounds: quoted Next.js `[id]` route paths (the glob
check moved from the unquoted-token level to the metachar scan), and unquoted `-f labels[]=…` test rows (the hook's own
deny messages already prescribe the quoted form; one message that did not was corrected).

## Key Insight

A gate that judges text another interpreter will expand has to model that interpreter's whole expansion list, or
refuse everything it does not model. Write the list down before the first fix (bash manual "Shell Expansions" plus
"Quoting": brace, tilde, parameter, command, arithmetic, process substitution, word splitting, pathname, quote
removal) and close each class in one place. The round-4 seat that was briefed to sweep the list systematically, not to
find "one more instance", found the last two shell classes in one pass; the four seats before it each found one.

## Session Errors

1. **Deepen-plan security-sentinel stopped by model safeguards before reporting** (forwarded). — Recovery: AC12 kept a
   security seat on the real diff. — Prevention: none needed; the review round is the backstop.
2. **Plan design had a vacuous NBSP-before-git test** (forwarded; `splitSegments` trims U+00A0). — Recovery: fixed in
   plan review. — Prevention: plan review already catches it.
3. **Census missed two token-bearing `runProc("git")` calls** (forwarded). — Recovery: added in the sharp-edges pass.
   — Prevention: the AST census now fails on them.
4. **decision-challenges.md had four failing rows** (forwarded). — Recovery: fixed, gate PASS. — Prevention: gate
   already enforces.
5. **Scan gate ran the main checkout's script and scanned main.** — Recovery: re-ran the worktree copy. — Prevention:
   invoke gate scripts by worktree-relative path from the worktree root.
6. **Seven consecutive fix rounds, each closing one bash-expansion instance.** — Recovery: closed every class outright
   (table above). — Prevention: plan-sharp-edges bullet (routed in this PR): enumerate the interpreter's expansion list
   before the first fix, and brief the first fix-round seat for a systematic sweep.
7. **New deny rules pre-empted existing test rows** (`$HOME` and `~` worktree rows, six unquoted gh `labels[]` rows,
   the punctuation anti-vacuity row). — Recovery: moved each row to the rule that now fires first, or to the quoted
   spelling. — Prevention: run the whole hook suite after every new metachar class (done each round).
8. **`gh issue create` blocked twice by the filing gate** (variable/`$()` body path; missing `Mandated-By:` line). —
   Recovery: literal absolute `--body-file` and a `Mandated-By:` line. — Prevention: gate message already states both.
9. **Affected gate killed by the host's low-memory reaper.** — Recovery: CI as the gate, scoped suites locally. —
   Prevention: one-off host condition.
10. **ADR-033 double blank line failed CI `quality-guards` markdown-lint.** — Recovery: removed it. — Prevention: lint
    every changed tracked `*.md` with `markdownlint-cli2` before push.
11. **A backgrounded Bash poll loop was blocked by the `background-poll-prefer-monitor` hook.** — Recovery: Monitor
    tool. — Prevention: already hook-enforced.
12. **Token-level `[` check over-denied quoted Next.js route paths** (round 5). — Recovery: moved to the unquoted
    metachar scan. — Prevention: test a quoted dynamic-route path whenever a pathspec rule changes (row added).
13. **Commit option parser misread `-Sc` as `-S` plus a value-taking `-c`** (round 7, P3). — Recovery: `-S`/`-u` stop
    the cluster scan. — Prevention: test rows for optional-attached-value options.

## Tags

category: security-issues
module: cron-bash-allowlist-hook
