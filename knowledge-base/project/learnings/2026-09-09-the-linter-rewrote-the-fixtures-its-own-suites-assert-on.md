---
date: 2026-09-09
issue: 7927
pr: 7955
category: test-failures
module: markdown-lint, ship-incident-pir-gate, check-sweep-completeness
tags: [fixtures, linting, pre-existing-failures, fail-open, merge-semantics, gh-api]
---

# Learning: the linter rewrote the fixtures its own suites assert on

## Problem

PR #7955 turned on a repo-wide markdownlint gate and swept 441 files to zero errors.
The sweep was verified with two per-file invariants (word sequence unchanged, heading
count unchanged) and every targeted gate was green locally. CI still found four real
failures, and two of them shared one root cause that neither invariant could see.

## The class: a checker must not rewrite its own subject

**A fixture is test INPUT, not documentation.** Linting one is a category error: the
linter rewrites the exact bytes a suite asserts on. Both instances were measured, and
they failed by different mechanisms:

- `plugins/soleur/test/fixtures/ship-incident-pir-gate/` feeds a paragraph/heading
  **boundary** classifier, so its blank lines ARE the input. MD012 added two, flipping
  mutation rows M5 and M9 from `want=no` to `got=yes`.
- `test/helpers/sample-content.md` is asserted on by substring. MD034's autolink
  rewrite turned `Link: https://…` into `Link: <https://…`.

The word-sequence and heading-count invariants were both satisfied in the first case
(blank lines merge no words and add no headings) and in the second the *tokens* were
preserved — the assertion broke on where a `<` landed. **An invariant chosen to protect
prose says nothing about a file whose whitespace and punctuation are semantic.**

**Fix the class, not the instances.** All 14 swept fixture files were restored to
`origin/main`'s bytes (verified: zero fixture `*.md` differ from main), and the six
corpora are excluded in `.markdownlintignore` with the measurement justifying each.
Documentation that happens to live under a fixture directory stays in scope
deliberately — `test/fixtures/orphan-proc-dangling/README.md` is why the `test` root
still appears in `EXPECTED_ROOTS`.

## A "known pre-existing failure" is a claim to re-measure, not a fact to inherit

I was briefed that `ship-incident-pir-gate-mutation.test.sh` "fails 2 of 25 on main
today, identical rows before and after this branch, tracked by #7801". The count
matched **exactly** — 2 of 25 — which is precisely what made the label credible.

It was false for this tree. My branch touched exactly the two fixtures the two failing
rows are named for.

**The discriminator takes 30 seconds and is not a count.** Install the base version of
the *specific inputs* and re-run:

```bash
for f in real-outage-after-heading-boundary real-outage-after-fenced-block-abutting-paragraph; do
  cp "$D/$f.md" "$SAVE/$f.md"; git show "origin/main:$D/$f.md" > "$D/$f.md"
done
bash scripts/ship-incident-pir-gate-mutation.test.sh   # 25/25 with main's fixtures
                                                       # 23/25 with the swept ones
```

Matching failure counts is the weakest possible evidence for "pre-existing", because a
regression that breaks N rows is indistinguishable from a known failure of N rows.
Swap the inputs, not the tally. Accepting the label would have shipped a real break
under cover of a known one.

## Three smaller findings with independent recurrence vectors

**A guard that fails closed can still be unpassable, and that is a defect.**
`gh pr diff --name-only` reads GitHub's diff endpoint, which caps at **300 files**
(HTTP 406). `check-sweep-completeness.sh` failed closed — correct — but no PR above
that cap could ever pass, and the author's only remedy was a smaller PR, which a
repo-wide sweep cannot be. Fail-closed is necessary, not sufficient: also ask whether
the measurement path can *succeed* for legitimate inputs. GitHub's own 406 body named
the fix (the paginated `pulls/N/files` API).

**`gh api` writes its JSON error body to STDOUT.** The first version of that fix was a
fail-OPEN for exactly this reason: on a 404 `gh api` prints
`{"message":"Not Found",…}` to stdout *and* exits non-zero, so `$(cmd || echo "")`
yields a NON-EMPTY string and the existing `[[ -z "$changed" ]]` test read that body as
a valid changeset — PR `99999999` reported "no violations" where the original correctly
failed closed. **Gate on exit status, never on output emptiness, for any command whose
failure mode is a structured error document.** Caught only by testing the direction that
must stay RED. Same shape as [[2026-09-07-my-instruments-reported-green-while-measuring-nothing]].

**A merge can produce a defect neither parent has.** Both sides of
`plugins/soleur/skills/work/SKILL.md` were individually MD007-clean; the merged file had
44 errors. Main had dedented a `**bold**` line to column 0 while leaving its continuation
lines at 3 spaces — that column-0 line terminates the enclosing list, re-parsing 44
following bullets as a new top-level list. Auto-merge produced it silently, with no
conflict markers. **Lint the merge RESULT, never just the two sides.**

## Process findings

**A CONFLICTING PR stops GitHub triggering every `pull_request` workflow.** #7955 sat
`DIRTY` for ~15 hours. Only `pull_request_target` (CLA) kept running, so the PR looked
quiet rather than broken and the new gate had **never once reported**. Before diagnosing
"why isn't CI running", run `gh pr view N --json mergeable,mergeStateStatus`, and compare
against another branch's PR to separate repo-wide from PR-specific.

**A byte budget sitting exactly on its ratchet turns any added comment into a CI
failure.** The AGENTS rule budget is at precisely 46000/46000 on main; a 41-byte
`<!-- markdownlint-disable-line MD038 -->` reddened `grok-fidelity` and two
`test-scripts` shards. I first misdiagnosed this as pre-existing by measuring **raw
bytes** instead of running the gate's own measure — the gate strips frontmatter, so
`wc -c` and the linter disagree in exactly the near-cap regime where the number decides.
**Run the gate; do not approximate it.** Resolved by rephrasing so no silencing comment
was needed (45999).

## Session Errors

1. **The sweep rewrote 14 test fixture files.** Recovery: restored all to `origin/main`
   bytes, excluded six corpora. Prevention: fixture corpora belong in
   `.markdownlintignore`; see the class section above.
2. **Nearly accepted a false "pre-existing failure" label.** Recovery: swapped in main's
   fixtures and re-ran (25/25 vs 23/25). Prevention: re-measure by swapping base inputs,
   never by matching failure counts.
3. **First fix for the 300-file cap was a fail-open.** Recovery: gated on exit status
   plus a body-shape backstop. Prevention: for any `gh api`/`curl` capture, test the
   failing direction explicitly.
4. **Misdiagnosed the rule-budget failure as pre-existing** by measuring raw bytes.
   Recovery: ran `lint-agents-rule-budget.py`. Prevention: run the gate, not a proxy.
5. **Overstated two claims about #7902 to the operator** ("solving the wrong problem",
   "ceiling already stale"). Recovery: corrected plainly; the branch had already caught
   the queue attribution and my figures were pre-shard. Prevention: verify a sibling
   branch's current state before characterising it.
6. **First sweep attempt corrupted 78 files** (MD018 `--fix` turned 106 prose `#5913`
   lines into H1s) and **passed its own verification**, because a word-sequence guard is
   structurally blind to an inserted space. Recovery: reset, not patched forward; added
   a heading-count guard. Prevention: pair every content invariant with a structural one.
7. **`M11b` bare-token grep matched the policy's own documentation** — the SUT's refusal
   message names `npm install`. Recovery: anchored on command position after stripping
   comments and string literals. Prevention: the documented body-grep false-positive
   class; strip strings, not just comments.
8. **Wrote `9633 tracked *.md` into a guard comment; the real count is 9660.** Recovery:
   measured and corrected in the same turn. Prevention: never round or recall a number
   that is about to be committed as a measurement.
9. **Included `git stash list` in a command that had no need for it**; the guardrail
   correctly blocked the whole call. Prevention: read your own command for incidental
   forbidden tokens before running it.
10. **A 128-line PR-body draft in the session scratchpad was swept from `/tmp`** between
    turns and had to be rewritten. Prevention: long-lived drafts belong in the worktree.
11. **Malformed `gh pr checks --json … --jq --arg …`** ("accepts at most 1 arg(s),
    received 4"). Recovery: piped through `jq` separately.
12. **Nested quoting in `python3 -c "…"` inside bash** produced a syntax error at a
    generated regex. Recovery: switched to a quoted heredoc (`<<'PYNET'`). Prevention:
    heredoc any embedded script carrying regex metacharacters.
13. **A `git commit && git push` exceeded the 120s tool timeout** and backgrounded; the
    commit never landed and its content had to be folded into a later one. Prevention:
    commit and push as separate calls when hooks are slow, and never start a second
    writer against the same index.

## Key Insight

The verification invariants were chosen for prose and applied to a corpus that included
**test input data**, where whitespace and punctuation are semantics rather than style.
A checker is only safe over a subject it does not rewrite — and when it does rewrite,
the invariant that protects the common case is exactly the one that will be silent on
the uncommon one.

Second, and more portable: **an inherited failure label is evidence about a different
tree.** The count matching is what makes it dangerous, not what makes it true.

Related: [[2026-09-08-every-guard-i-added-to-the-gate-could-not-fail]],
[[2026-09-08-six-instruments-were-broken-and-three-printed-a-verdict-anyway]],
[[2026-09-07-my-instruments-reported-green-while-measuring-nothing]],
[[2026-09-08-the-fix-i-shipped-to-prove-the-fix-contained-the-defect]].
