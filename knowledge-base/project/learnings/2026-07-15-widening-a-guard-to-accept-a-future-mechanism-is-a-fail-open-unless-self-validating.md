---
title: "Widening a guard to accept a not-yet-existent mechanism is a fail-open unless the allowlist self-validates"
date: 2026-07-15
category: test-failures
module: infra-validation, ci-guards, cloud-init
issues: [6446, 6458, 6473]
pr: 6456
tags: [fail-open, drift-guard, allowlist, mutation-testing, required-checks, matrix-jobs, false-green]
---

# Learning: naming a mechanism is not evidence the mechanism runs

Sibling to [[2026-07-15-narrowing-is-not-anchoring-and-a-documented-class-recurred-four-times-in-one-pr]].
That one is about assertions that pass **because prose satisfies them**. This one is the
opposite failure of the same guard: an assertion that passes because it names a mechanism
that **does not exist yet**. Fixing the first defect is what created the second.

## Problem

A drift guard asserted that `.github/workflows/infra-validation.yml` still schema-checks
cloud-init. v1 pinned main's **implementation**:

```bash
grep -qF 'cloud-init schema -c /tmp/cloud-init.stripped.yml'
```

That is a temp-file path. Sibling PR #6458 replaces the step wholesale with a
render-then-validate script — so v1 would have turned #6458 **red for upgrading the very
property the guard protects**. Correct diagnosis. The fix was to widen to an alternation
accepting either mechanism:

```bash
grep -qE '^[[:space:]]*(cloud-init schema -c /tmp/cloud-init\.stripped\.yml|bash .*validate-infra-templates\.sh)'
```

**The second alternate names a script that does not exist on this branch.** It exists only
on #6458's branch. So that alternate could only ever *fail open*: replace the stripped step
with a call to the missing script and the guard goes **green while coverage is gone**.

The guard's own comment, two lines above, states the contract it just broke:

> A drift guard must fail on SILENT LOSS of coverage, never on a deliberate upgrade of it.

## Why the obvious escape hatch does not save it

The reflex rebuttal is *"`bash <missing-script>` exits 127, so CI catches it anyway."*
That is false **here**, and the reason is the whole point:

`bash <missing>` reds the `validate` job — a **matrix** job. Its check names are dynamic
(`validate (apps/web-platform/infra)`), so they **cannot be pinned as required contexts**.
A red matrix job blocks nobody. That is precisely the "red for days and nobody was blocked"
pathology (#6344 → #6446) this guard exists to backstop.

So the guard was blind in the exact failure mode it was written for, and the fallback that
would normally cover the blindness is the same fallback that was already known broken.

**Generalize:** "the runtime would fail anyway" is only a defense if the runtime failure
reaches something that *blocks*. Check whether the job you are relying on is a required
context before you lean on it. A guard for a non-required job that itself lives in a
non-required job protects nothing on its own (tracked: #6473).

## Key Insight

> **Naming a mechanism is not evidence the mechanism performs the check.**

An allowlist entry that matches a *string* asserts that someone wrote a line, not that the
line does anything. Where the entry names a script/command, make it **self-validating** —
conditional, so it costs nothing until the mechanism lands:

```bash
VALIDATE_TEMPLATES_SH="$SCRIPT_DIR/../../../.github/scripts/validate-infra-templates.sh"
if grep -qE '^[[:space:]]*bash [^-].*validate-infra-templates\.sh' "$INFRA_VALIDATION_WF"; then
  assert "validate-infra-templates.sh exists and actually runs cloud-init schema (#6458)" \
    "[[ -x '$VALIDATE_TEMPLATES_SH' ]] && grep -q 'cloud-init schema' '$VALIDATE_TEMPLATES_SH'"
fi
```

Two corollaries that each cost a review cycle here:

- **A text grep over a caller cannot verify the callee.** A workflow-text guard
  structurally cannot know whether a script it merely *calls* does the check. So the honest
  ceiling is an explicit **allowlist**, and the prose must say "allowlist". I wrote
  *"deliberately mechanism-agnostic"* — a false claim about a guard, in a PR about false
  claims about guards. The discipline was cited in the comment; it was not applied to the
  comment.
- **`bash .*` admits lint-only decoys.** `bash -n <script>` syntax-checks and validates
  nothing, and satisfied the alternate. `bash [^-].*` rejects a flag as the first token.

## The mutation matrix is the deliverable

Every claim below was **run**, not reasoned about. The two rows marked ← are the ones that
reading had approved:

| Mutation | Verdict |
|---|---|
| baseline | 69/69 PASS |
| delete the stripped line (coverage lost) | 68/69 FAIL |
| revert to raw `-c cloud-init.yml` | 67/69 FAIL (both halves) |
| comment the command out, prose intact | 68/69 FAIL |
| call a **missing** script | 69/70 FAIL ← was a false-GREEN |
| script exists but is a stub | 69/70 FAIL ← new coverage |
| `bash -n` lint-only decoy | 68/69 FAIL ← was a false-GREEN |
| #6458's real form (exists + schema-checks) | 70/70 PASS |
| guard deleted entirely | 67/67 (proves both asserts execute) |

The last row is the cheapest and most-skipped check: **delete the guard and confirm the
total moves.** If the suite reports the same count with the guard gone, it was pinning
nothing.

## Prevention

- When widening a guard to admit a future mechanism, ask: **does that mechanism exist in
  this repo right now?** If no, the alternate is currently a pure fail-open surface — it
  cannot green anything real, it can only excuse an absence. Either drop it (YAGNI) or make
  it self-validating. Never ship it bare.
- Mutate **toward** the thing you just widened for, not only away from it. The mutations
  that caught this were "call the script but don't create it" and "create it but make it a
  stub" — both *inside* the newly-admitted branch. Mutating the old branch (delete the
  stripped line) passed fine and proved nothing about the new one.
- Before relying on "CI would catch it," confirm the catching job is a **required context**.
  `gh api repos/:owner/:repo/rulesets` / `infra/github/ruleset-ci-required.tf`. Matrix jobs
  never are.
- Prose describing a guard is part of the guard. "Mechanism-agnostic", "any", "always" are
  claims — grep them against the code before writing them.

## Session Errors

- **The widened guard shipped a fail-open.** Recovery: `security-sentinel` mutation-proved
  it (swap stripped line → call to missing script → green). Prevention: self-validating
  allowlist entry; mutate toward the newly-admitted branch.
- **Prose over-claimed the code** ("mechanism-agnostic" for a two-item allowlist). Recovery:
  `code-quality-analyst` diffed prose vs. regex. Prevention: an allowlist is an allowlist;
  say so.
- **Minted a rotted citation mid-fix** ("See AC16" → AC16 is *Full suite green*). Recovery:
  self-caught before push. A second one ("AC7 leg" → the plan's unchecked `[PR-B]` AC7 for a
  different file) survived to review. Prevention: every `AC<N>` / `#<N>` pointer written into
  a doc gets grepped against its definition in the same edit.
- **Minted the 8th false comment** — the added `Install cloud-init` step said the raw-source
  step "was deleted" (the merge kept it), and self-refuted by pointing at "the comment on the
  `validate` job above", a job whose existence the sentence denied. Recovery:
  `code-quality-analyst`. Prevention: when a merge reverses a premise, grep the whole diff
  for prose asserting the old premise — the sibling comment 79 lines away was fixed in the
  same diff while this one was missed.
- **PR body draft minted two new auto-close adjacencies** (`fixed #6446`, `fixes #6446`,
  describing *other* PRs' work). Benign only because #6446 was already in the Closes list.
  Recovery: ran `auto-close-scan.sh` before pushing the body. Prevention: already documented
  — [[2026-06-29-auto-closes-meta-content-in-commit-body-trips-github-autoclose-on-hand-rolled-merge]].
  Reword to `fixed issue #N` to break the adjacency.
- **Cross-agent worktree contamination cost a cycle.** `security-sentinel` reported a
  clean-tree 68/69 while `test-design-reviewer` concurrently mutated the workflow. Recovery:
  `git diff HEAD -- <file>` against committed HEAD. Prevention: already documented in
  `review/SKILL.md` §Sharp Edges — synthesize against committed HEAD, never the live tree.
- **`run_in_background` + trailing `echo` reported "exit code 0" twice** for
  `bash scripts/test-all.sh > log 2>&1; rc=$?; echo "TESTALL_EXIT=$rc"`. That 0 is the
  *echo's* exit. Recovery: grepped the log for the real verdict. Prevention: already
  documented in `work/SKILL.md` §Test Continuously.
- **`cleanup-merged` hit `Permission denied`** removing an unrelated worktree's
  `supabase/snippets`. One-off; session-start hygiene, non-blocking.

## Related

- [[2026-07-15-narrowing-is-not-anchoring-and-a-documented-class-recurred-four-times-in-one-pr]] — the sibling failure of the same guard
- [[2026-07-15-guard-gate-and-probe-must-pin-the-thing-they-name]] — mutate the gate out and re-run; if green, it pins nothing
- [[2026-07-15-a-guard-that-never-ran-has-more-than-one-reason-and-indexof-block-scoping-swallows-siblings]] — a guard's silence has more than one cause
- #6473 — fail-closed required-check aggregator; the load-bearing fix for the matrix-job gap
