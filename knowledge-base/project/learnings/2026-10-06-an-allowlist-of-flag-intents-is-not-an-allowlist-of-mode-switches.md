---
title: "An allowlist of flag intents is not an allowlist of mode switches — `git branch -v <name>` auto-approved a create through a 'read-only' gate, and the fix's own regex went exponential"
date: 2026-10-06
category: security-issues
tags: [safe-bash, allowlist, git-branch, mode-selection, regex, redos, review-panel, fix-round, kb-search]
issue: 9555
pr: 9570
branch: feat-one-shot-9555-9559-safe-bash-kb-search
---

# Learning: an allowlist of flag intents is not an allowlist of mode switches

## Problem

PR #9570 closed #9555 — `git branch` write forms auto-approving as read-only
through the safe-bash allowlist. The plan, the interface-contract, the
implementation, and the test battery all encoded the same invariant:

> every member of `GIT_BRANCH_READ_FLAG` is "list-mode", so any flag +
> a positional arg is a pattern/filter, never a create.

**That premise was asserted, never measured.** Seven of ten review seats
independently verified against real git 2.55 that only a subset forces list
mode: `--list`, `--show-current`, `--contains`/`--no-contains`,
`--merged`/`--no-merged`, `--points-at` (and `-a`/`-r`, which *fatal* on a
positional). The display modifiers — `-v`, `--verbose`, `--sort=`,
`--format=`, `--abbrev`, `--column`, `--no-column`, `--color`, `--no-color`,
`--ignore-case` — do **not** switch modes, so `git branch -v <name>`
**created** a branch while auto-approved. The exact confused-deputy class the
PR existed to close, re-shipped on the same hot path.

The review round then produced its own defect: the forcing-bundle class
`-[arv]*[ar][arv]*` (bundle containing ≥1 `a`/`r`) gives every `a`/`r` position
its own pivot parse. Nested in the `(…)*` token loop with a failing tail,
parses multiplied across tokens into ~2^m paths — **>10 s at ~110 chars**,
effectively a permanent synchronous hang of `canUseTool` at the 4096-char cap.
The performance fix-round seat caught it; `-(?=[arv]*[ar])[arv]+` (one
lookahead, maximal munch) is the same language with a single parse (0.1 ms at
200 tokens).

## Solution

Split the flag set by **verified git semantics**, not intent:

```ts
// list-FORCING: each member switches git branch to list mode or fatals
// on a positional — verified on git 2.55, not inferred from the flag's name
const GIT_BRANCH_LIST_FORCE = String.raw`(?:--list|--show-current|--all|--remotes|--contains|--no-contains|--merged|--no-merged|--points-at|-(?=[arv]*[ar])[arv]+)`;
const GIT_BRANCH_READ_FLAG = String.raw`(?:${GIT_BRANCH_LIST_FORCE}|-[v]+|--verbose|--sort=${PATH_TOKEN}|--format=${PATH_TOKEN}|--abbrev(?:=\d+)?|--column|--no-column|--color(?:=${PATH_TOKEN})?|--no-color|--ignore-case)`;
// Arm 2: a forcing flag must appear in the leading flag run (lookahead)
// before any positional arg is admitted.
new RegExp(String.raw`^git\s+branch(?=\s+(?:${GIT_BRANCH_READ_FLAG}\s+)*?${GIT_BRANCH_LIST_FORCE}(?=\s|$))\s+${GIT_BRANCH_READ_FLAG}(?:\s+(?:${GIT_BRANCH_READ_FLAG}|(?!-)${PATH_TOKEN}))*\s*$`),
```

The deny battery now pins every modifier+positional create (17 rows) plus the
auto-negation lookalikes (`--no-list`, `--no-all` — parse-options negations
that read read-only but create), and a 200-token timing pin guards the
multi-parse shape.

## Key Insight

**An allowlist classified by what a flag *looks like* is not an allowlist of
what it *does*.** `git branch` has a mode-selection rule — listing happens iff
`--list` is given, a filter flag consumed the arg, or there are no positional
args — and the regex's job is to encode THAT rule, not the author's taxonomy
of "read-only flags". The sentinel for every future allowlist arm: **probe the
tool's mode-selection semantics per admitted token against the real binary;
never classify by flag intent.** The same defect family nearly slipped the fix
itself: the plan's `decision-challenges.md` recorded "each member is provably
list-mode read-only" — a proof that never ran.

Second-order: **any alternation that can match one token more than one way,
nested in a repetition, is a silent ReDoS.** A "bundle containing ≥1 of set X"
written `-[set]*[x][set]*` multi-parses; write it `-(?=[set]*x)[set]+` and the
parse is single. The file's own #4868 comment documented the lesson; the fix
re-learned it one level inside the flag grammar.

## Session Errors

1. **Plan/contract/test triad encoded an unmeasured git-semantics premise**
   (the modifier-flag create launder). Caught by 7 review seats empirically.
   **Prevention:** for any allowlist over an external tool's flags, run the
   real binary per admitted flag in a scratch repo before writing the
   contract — the `decision-challenges` "provably X" claim must cite the probe
   that proved it.
2. **Arm-2 rewrite dropped the per-token `\s+` separator** — tokens could
   concatenate (`--listfeat`). Caught by a live probe before commit.
   **Prevention:** when reshaping a `(...)*` token loop, probe the new regex
   against the known-case matrix before committing — never review-by-reading
   a regex you just rewrote.
3. **Fix introduced a multi-parse ReDoS** (`-[arv]*[ar][arv]*`). **Prevention:**
   every new alternation member inside a repeated token gets the question
   "how many parses does one token have?" — >1 is the #4868 shape; a timing
   pin now guards this instance.
4. **`git add -A` swept a review seat's scratch file (`redos-bench.mjs`) into
   the commit.** **Prevention:** stage by explicit path, or sweep the worktree
   for seat artifacts before `git add -A` — the review panel's scratch work is
   not diff content.
5. **`index($0,m)==1` marker anchoring broke extraction** — the marker leads
   with `**`, so the anchored form returned empty. **Prevention:** verify the
   anchor against the actual first bytes of the marker line, not the marker
   string.
6. **Fresh-eyes verifier seat killed by rate limits ×3** — verification ran
   inline, disclosed. **Prevention:** when a delegated seat dies on quota,
   disclose the fallback in the fix-round attestation rather than claiming an
   independent pass ran.
7. **`gh issue create` refused twice by the filing gate** — the `Mandated-By:`
   line must sit on its own line with a real rule id. **Prevention:** read the
   refusal text fully — the accepted exits are enumerated in it.
8. **`sed` for the stale C4 header count missed on first try** (dash-count in
   the pattern). **Prevention:** trivial; verify the match before declaring.

## Related

- #9555 (the incident this closed), #9559 (support kb-search false handoff),
  #9600 (sibling `--ext-diff`/`diff.external` hole filed during review —
  pre-existing, out of scope).
- `knowledge-base/project/learnings/2026-09-24-every-refusal-i-added-had-a-one-keystroke-repair-…` — the `-q` exclusion already applied the create-by-modifier lesson this PR had to re-learn for display flags.
- ADR-267 fix-round mechanics — the targeted round caught a P1 the full panel
  missed in the *fix*, which is the property it exists for.

## Tags

safe-bash, allowlist, git-branch, mode-selection, regex, redos, review-panel, fix-round, kb-search
