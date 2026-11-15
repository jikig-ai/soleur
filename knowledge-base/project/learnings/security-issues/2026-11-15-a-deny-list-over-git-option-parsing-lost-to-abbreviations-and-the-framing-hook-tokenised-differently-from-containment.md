---
title: A deny-list over git option parsing lost to abbreviations, and the framing hook tokenised differently from containment
date: 2026-11-15
category: security-issues
module: apps/web-platform/server/inngest (cron Claude eval substrate)
tags: [cron, containment, allowlist, git, posttooluse, untrusted-content, review]
pr: 12705
issues: [11076, 9601, 12753, 12754, 12757]
---

# Learning: a deny-list over git option parsing, and two parsers over one command

## Problem

PR #12705 added an opt-in PostToolUse(Bash) hook to the cron eval substrate. On a `gh` read it annotates the output as untrusted (ADR-287). Review found two defects.

1. **K1 — a pre-existing hole in the containment hook.** The cron allowlist admitted `git checkout` and `git switch` so the bug-fixer cron could create branches. The first fix was a deny-list: refuse `--`, path-looking arguments, and `-p`/`--patch`. It was defeated three ways:
   - git accepts any unambiguous long-option prefix (`--no-overl` means `--no-overlay`), so a list of exact flag spellings is never complete;
   - `--no-overlay` with a parent folder restores files without a `--` separator;
   - `?` and `[]` pathspec globs are not path-looking to a regex that looks for `/` or `.`.

   Also, bare `git checkout <name>` restores a *path* when no branch has that name. That makes a single argument ambiguous until runtime.
2. **K2 — two parsers over one command string.** Containment matches the whitespace-normalised join of the tokens. The framing hook checked raw token positions. A command with irregular whitespace was then admitted by one parser and classified differently by the other.

## Solution

- **K1' (CTO ruling): a positive grammar in place of the deny-list.** `gitVerbReason` admits only these forms:
  - `git checkout [-q|--quiet] -b <branch>`
  - `git switch [-q|--quiet] -c <branch>`
  - `git switch [-q|--quiet] <branch>`

  `<branch>` must pass `isBranchName`: it matches `^[A-Za-z0-9][A-Za-z0-9._/-]*$`, contains no `..`, `//` or `@{`, and does not end in `/`, `.` or `.lock`. Every other form is denied, including start points, `-B`/`-C`, and all of `git restore`. A refusal names the admitted forms.
- **K2: one normaliser, imported.** `normalizeSegmentWhitespace` is exported from `cron-bash-allowlist-hook.mjs`. The framing hook imports it, along with `splitSegments`, `tokenize` and `MAX_BASH_COMMAND_CHARS`, and matches on `normalize(tokens.join(" ")).split(" ")`. The two hooks now read one command one way.
- **Residual F1/F2, filed as #12757 (P1, already on main):** protect `$HOME/.gitconfig`, pin `GIT_CONFIG_GLOBAL`, and normalise the git subcommand token. The fix PR was not opened in this run because of the operator's one-PR limit.

## Key Insight

**Allowlist the grammar; never deny-list a parser you do not own.** git's option parser accepts prefixes, merges flags, and decides between branch and path at runtime. Any list of spellings is a claim about that parser, and the parser will outgrow it. State the few forms the caller needs, and refuse everything else.

**Two hooks that read the same command must share the code that reads it.** If they parse it separately, the gap between the two readings is exactly where a crafted command lives.

## Session Errors

1. **The plan's ruling gate rejected the mechanical-class rows** (forwarded). Recovery: moved them to a list; the gate passed with 27 rows. **Prevention:** none needed; the gate worked as designed.
2. **Two scripted plan edits failed on line-wrap and quoting** (forwarded). Recovery: re-ran and verified. **Prevention:** use the Edit tool for multi-line prose edits, not sed or python.
3. **Docs quotes came back paraphrased by a fetch agent** (forwarded). Recovery: flagged them and re-verified before writing ADR text. **Prevention:** never quote a fetch agent's output as verbatim; re-fetch the exact sentence.
4. **A python sort reordered the unrelated `repo-wide-suites.ts` registry.** Recovery: `git restore --source=HEAD`, then one inserted line. **Prevention:** insert a registry line at an anchor; never re-sort a file you are only appending to. Check `git diff --stat` before committing.
5. **I cited the wrong ADR precedent before verifying it.** Recovery: corrected it to `2026-07-04-testable-workflow-internal-logic-lib-plus-duplicate-plus-parity-guard.md`. **Prevention:** open the cited file and quote its line before citing it (the inherited-framing gate).
6. **The plan's Observability block used wrong layer numbers, and its YAML broke on unescaped quotes.** Recovery: cited layers 1–3 from the observability-coverage-reviewer list and re-parsed the YAML. **Prevention:** copy layer numbers from the reviewer's own list, and parse plan YAML (`python3 -c 'import yaml…'`) after editing it.
7. **The filing gate refused `gh issue create` three times:** no milestone, no filing exit, and a relative `--body-file`. Recovery: added the milestone, the `meta/machinery` label and an absolute path. **Prevention:** before the first filing in a session, build the command with all three parts.
8. **The K1 deny-list on git options was bypassable** (see Problem). Recovery: the CTO re-ruled it as the K1' positive grammar. **Prevention:** for any command allowlist over a third-party CLI, write admitted forms, never denied flags.
9. **A fix-round test-design seat's `cd` into its scratch copy failed, and its probe ran in the live worktree.** That switched the worktree to an orphan branch. The seat restored it with `reset --hard 08160a176a`, and I verified the tree was clean. **Prevention:** a seat brief makes the scratch `cd` its own checked command (`cd "$SBX" || exit 1`, then `git rev-parse --show-toplevel` must equal `$SBX`) before any git write. Routed to `risk-tier-and-fix-rounds.md`.
10. **Running `review-scan-gate.sh` through the plugin-root path resolved ROOT to the main checkout,** and the gate refused. The script derives `ROOT` from its own location (`$SCRIPT_DIR/../../../../..`), and the skill's documented path points into the main checkout. Recovery: ran the worktree copy. **Prevention:** filed as #12779. The script should take ROOT from `git rev-parse --show-toplevel` of the CWD, or the skill should name the worktree copy.
11. **A stale test row pinned a bug-fixer form the skill dropped in #831** (`git checkout -b <b> origin/main`). Recovery: flipped the row to deny under K1'. **Prevention:** none needed; K1' surfaced it.
12. **The CTO asked for the #12757 PR before #12705 ships,** which conflicts with the operator's one-PR-per-run limit. Recovery: #12705 proceeds on the ruling's own no-widening reasoning (decision-challenges V1/V2), and this is disclosed in the final output. **Prevention:** none needed; an operator constraint outranks a sequencing preference, and the disclosure is the control.
13. **I read the CI check set on a draft PR,** where `draft-light` skips every test leg. Recovery: mark the PR ready before reading test verdicts. **Prevention:** read `isDraft` before reading CI as a verdict. A skipped leg is not a passing one.

## Related

- ADR-287 and its 2026-11-12 addendum.
- `knowledge-base/project/learnings/2026-06-10-workflow-spawns-skip-posttooluse-and-skeptic-mutation-probes.md`
- `knowledge-base/project/learnings/workflow-patterns/2026-10-12-fix-rounds-catch-the-regressions-the-fix-introduced.md`
- `knowledge-base/project/learnings/2026-10-30-a-read-only-verifier-refused-the-store-its-producer-writes-and-its-census-was-a-lexer-arms-race.md` (also a lexer arms race, also ended by stating the contract)

## Tags

category: security-issues
module: cron-eval-substrate
