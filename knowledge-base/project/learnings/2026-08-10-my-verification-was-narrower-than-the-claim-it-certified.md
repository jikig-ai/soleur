---
title: "Every verification I wrote this session was narrower than the claim it certified"
date: 2026-08-10
module: plugins/soleur/skills/compound
problem_type: best_practice
component: tooling
severity: high
tags: [verification-scope, negative-space-assertions, grep-anchoring, set-e, fixture-space, review-panel]
related_files: plugins/soleur/test/generate-kb-index.test.sh, knowledge-base/engineering/architecture/decisions/ADR-173-kb-index-exclusion-supersedes-per-feature-archival.md
---

# Every verification I wrote this session was narrower than the claim it certified

Four independent defects in one PR, all green, all reducing to one sentence:
**the check's scope was smaller than the property it was taken to establish.**
None was caught by the implementation, three were caught by a review panel, one
by a deterministic lint *after* ten review agents had passed over it.

## The four

### 1. A literal-phrase grep certified a claim about meaning

Three files asserted *"INDEX.md lists every non-archived KB file"*. I amended
them and verified with:

```bash
grep -rn "lists every non-archived KB file" plugins/ .openhands/
```

Zero hits, declared done. That grep cannot see the same claim written as
"excludes `**/archive/`", or "lists all KB files", and it never looks in
`knowledge-base/`. Two more sites were live — and the one that mattered was the
learning file that the file I *had* fixed **cites as its source**. So the
derived prose was corrected and the cited authority left asserting the opposite.

The property was semantic; the check was lexical, over two of three roots.

### 2. A negative-space assertion with no existence precondition

```bash
assert_not_indexed "$kb" "specs/feat-x/session-state.md" "…dropped"
```

`grep -qF "]($rel)"` returns nothing when the row is correctly absent — and
also when the fixture was never created. Deleting all five drop-side fixtures
left the suite **byte-identical green**; deleting a single keep-side fixture
reddened. The suite was asymmetric on the exact axis it existed to test.

No mutation of the implementation can reach this. It is a fixture-space defect,
so a green mutation battery says nothing about it.

### 3. A fail-closed guard that could not run

```bash
allowed=$(sed -n '…' "$GEN_SCRIPT" | grep -oE "…")
if [[ -z "$allowed" ]]; then
  echo "  FAIL: could not extract the allowlist (extraction is broken, not the prose)"
```

The `if` exists so a broken extraction is *legible*. `grep` exits 1 on no
match, and the file runs under `set -euo pipefail`, so the suite dies at the
assignment and the branch never executes. The guard against silent failure
failed silently — in the commit that added it.

### 4. An absolute count asserted from inside the corpus it counts

ADR-173 stated `7,481 → 6,199` while `INDEX.md` in the same commit said
`6,200`. Both were measured correctly. The ADR is a file in the tree being
counted, so writing the number changed it. An absolute post-count in that
position can never be self-consistent.

## Key insight

Before trusting a check, state the property in one sentence and the check's
scope in another, then ask whether the second covers the first.

| Property | Scope that actually got checked |
|---|---|
| "no document overstates what INDEX.md contains" | one phrasing, two of three roots |
| "this file is correctly excluded" | "no row exists" — true also when no file exists |
| "extraction failure is reported" | reachable only when extraction succeeds |
| "the index shrank to N" | N measured before the measuring artifact joined the corpus |

Three practical rules fall out:

- **Sweeping a claim is not grepping a phrase.** Enumerate the paraphrases, sweep every root, classify every hit. A phrase-anchored sweep is a sample, and the site it misses is disproportionately the one that matters — here, the cited source.
- **Every negative assertion needs a positive precondition.** "X is absent from the output" is only meaningful once "X is present in the input" is asserted.
- **A fail-closed branch under `set -e` must be shown reachable.** Mutate the thing it guards and confirm it *reports* rather than aborts.

## What actually caught these

Not the implementation. Not `tsc`-equivalent gates. Not a green 57-assertion
suite, and not a 15-mutation battery that I wrote.

Three came from a ten-agent review panel, and the strongest signal was
**convergence** — three agents independently found the same depth/scope
mismatch, which is what made it decisive rather than arguable. A single agent's
P1 stayed a hypothesis until verified: one panel finding ("archival *has* a
recorded purpose") was partially refuted on checking, because it collapsed *why
the script exists* with *why the practice exists* — the cited commit explains
the script extraction, and the practice predates it by four weeks.

The fourth came from `lint-shell-capture-exit`, a deterministic grep-based
lint, **after** all ten agents had read the file. Worth remembering when
weighing a panel against a cheap mechanical gate: they catch different classes,
and the lint is far cheaper.

## Session Errors

- **Declared my own running suite dead on a pattern that could not see it.** `pgrep -f 'test-all\.sh'` and `pgrep -f 'test-all'` gave opposite answers, and my probe command matched its own `/proc/*/cmdline` to invent a third process. **Prevention:** resolve ownership via `/proc/<pid>/cwd` and exclude the probe itself; never conclude from one pattern.
- **Read a stale exit gate.** I launched the full suite, then committed a fix, then read the run — which was measuring a tree that no longer existed. **Prevention:** confirm the tree is clean at launch and do not edit under a running gate; if an edit cannot wait, kill the run rather than reinterpreting it.
- **A copied test suite produced a red control** because it sources `test-helpers.sh` relative to its own location. Caught by requiring a green unmutated control. **Prevention:** a red baseline voids every battery row — always run the control first.
- **Ran the pipeline phases in the plan's stated order once and had to deviate.** The plan numbered "regenerate INDEX.md" before "write the ADR"; regenerating first would have omitted the ADR's own row from the index it describes. **Prevention:** when a plan phase produces an artifact that a later phase indexes, order by dependency, not by number.
- **Two hooks fired on documentation of their own trigger tokens** — the IaC routing gate blocked a plan that quoted `doppler secrets set` inside a "gates I scanned for" list, and a security hook flagged `eval` in a scratchpad harness. Both were rephrased rather than opted out of. **Prevention:** worth a hook refinement — a bullet asserting a *negative* finding about a token is not a use of it.

## See also

- [[2026-08-10-pipe-buf-atomicity-does-not-apply-to-the-file-i-was-redirecting-into]] — the fifth defect from the same PR, same root: a safety claim whose scope did not cover the code.
- [[2026-07-16-a-mutation-battery-only-covers-what-you-mutate]] — the fixture-space half of #2.
- [[2026-07-30-a-known-gap-of-seven-was-a-predicate-and-my-battery-mutated-one-axis]] — batteries that measure one axis.
