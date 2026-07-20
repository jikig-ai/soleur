---
title: "A drift-guard test that extracts substrings to compare against an exact-equality production Set must mirror the checker's command boundaries AND match every emission shape"
date: 2026-07-07
category: best-practices
module: apps/web-platform/test, plugins/soleur/skills
tags: [drift-guard, test-authoring, regex-fidelity, exact-equality, safe-bash, coupling-test]
pr: 6152
issue: 6121
---

# Learning: drift-guard extraction fidelity vs. the exact-equality set it mirrors

## Problem

Slice C of the `${CLAUDE_PLUGIN_ROOT}` migration (#6121) added a coupling test
(`apps/web-platform/test/plugin-root-list-carveout-coupling.test.ts`) that walks
the SKILL.md tree, extracts every `worktree-manager.sh list|ls` emission via a
regex, and asserts each extracted string is an **exact member** of
`EXACT_LITERAL_SAFE_COMMANDS` (the safe-bash Stage-0 carve-out). It passed green
on the 4 real sites and looked sound. Post-implementation multi-agent review
found **two false-GREEN holes** in the extraction regex — both caught by
adversarial agents (test-design-reviewer, user-impact-reviewer), neither by the
green suite or tsc.

## Root cause

When a test extracts a **substring** of a candidate to compare against an
**exact-equality** production Set, the extraction must reproduce, byte-for-byte,
what the production checker treats as "the command." Two independent ways to get
it wrong:

1. **Boundary mismatch (verb-terminated capture).** The regex ended
   `(?:list|ls)\b`, stopping at the verb. safe-bash matches on the *whole trimmed
   segment* (`candidate.trim()`). So a drifted emission `… worktree-manager.sh
   list --json` extracted the bare `… list` prefix — which **IS** a Set member →
   GREEN — while the real command `… list --json` is a **non-member** the server
   would not auto-approve. The guard was blind to trailing-arg drift, the single
   most likely future drift (`--json`, `--porcelain`).

2. **Shape omission (over-anchored prefix).** The regex required a literal
   `bash ` prefix. But the producer legitimately emits the **no-`bash`/env-
   prefixed direct-exec** shape too (this very diff uses `SOLEUR_…= ${CLAUDE_PLUGIN_ROOT:-…}/…worktree-manager.sh feature` for the `feature`
   verb). A future no-`bash` `list` emission would never be **matched** →
   never checked → silently escapes the guard while falling out of the carve-out.

3. **Consequence overclaim (bonus).** The docstring/failure-message said drift is
   "DENIED on the autonomous server." Verifying `permission-callback.ts:189`: the
   autonomy toggle "bypasses ONLY the review-gate, NEVER the blocklist" — a
   non-carved (but non-blocked) command **auto-approves via the autonomous-bypass**
   post-consent; it is never a hard deny. The carve-out governs only the approval
   *prompt* (UX friction), not *which script executes* (that is the
   `${CLAUDE_PLUGIN_ROOT}` path migration). Claiming "server deny" misframes a
   UX-friction gap as a security exposure.

## Solution

Make the regex extract the **full command** (match every legitimate shape; let
the membership check — not the regex — decide conformance), then `.trim()` to
mirror `candidate.trim()`:

```js
// prefix OPTIONAL (matches bash-prefixed AND no-bash/env-prefixed shapes);
// trailing tail captured up to a command boundary so args make it a non-member.
const LIST_EMISSION =
  /(?:bash )?\$\{CLAUDE_PLUGIN_ROOT:-[^}]+\}\/skills\/git-worktree\/scripts\/worktree-manager\.sh (?:list|ls)\b[^\n`|;&)>]*/g;
// …
emissions.push(match[0].trim()); // mirror safe-bash candidate.trim()
```

Verified against 5 adversarial shapes: real bare-list → GREEN; `list --json`,
no-`bash`, wrong-anchor (`../../`) → all RED; benign trailing space → trimmed →
GREEN (no false-RED).

## Key Insight

**When a test extracts a substring to check against an exact-equality production
set, two properties are load-bearing and neither is provable by a green run:**
(a) the extraction must span the SAME boundaries the production check uses (full
command, not a salient prefix), and (b) it must match every SHAPE the producer
can legitimately emit (optional prefixes, env-prefixed forms) — an unmatched
shape is a silent escape, not a caught drift. Litmus: mentally mutate the
producer (add a flag, drop the `bash `, change the anchor) and confirm the test
goes RED for each. Also: don't let the docstring assert a failure *consequence*
you haven't traced in the actual gate code (verify the ordering, e.g.
`permission-callback.ts`), or the guard teaches the next reader a wrong threat model.

## Session Errors

1. **CWD-drift on verification greps.** AC1 completeness `git grep`s ran from the
   bare-repo root (the Bash tool does not persist CWD across calls), matching the
   *stale synced on-disk copies* at the bare root and returning a false "0
   migrated / empty residual" — even though the Edits (absolute worktree paths)
   had landed correctly in the worktree. Recovery: re-ran with `cd
   <worktree-abs> && …`. **Prevention:** already a documented recurring class
   (`hr-when-in-a-worktree-never-read-from-bare`); prefix every verification
   `git grep`/`grep`/`bun test` with an explicit `cd <worktree-abs> &&` in the
   same Bash call.
2. **Push rejected non-fast-forward after rebase.** Rebased onto origin/main
   after the draft-PR had already pushed the pre-rebase branch → divergence.
   Recovery: `git push --force-with-lease` on the own feature branch. One-off
   (standard post-rebase git); force-with-lease is the correct tool.
3. **Node `-e` syntax error** in the first adversarial regex check (`const
   dr(m)=>{…}` — invalid arrow-function declaration). Recovery: rewrote with a
   named `function`. One-off typo. **Prevention:** none warranted.
4. **test-all.sh exceeded the 2-min Bash foreground limit.** Re-ran with
   `run_in_background: true`. One-off (known: full-suite shards are long);
   background + rc-capture is the right pattern.
5. *(plan phase, forwarded)* Two IaC-routing hook false-positives on
   "operator-run" prose (resolved via the documented `<!-- iac-routing-ack -->`
   opt-out); one Edit `old_string` em-dash mismatch (re-read exact bytes). Both
   one-off applications of known classes.
