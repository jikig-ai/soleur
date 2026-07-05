# Learning: a mid-pipeline ADR renumber must sweep the plan/tasks/AC — not just the ADR body

## Problem

`feat-design-taste-learning` (#5990, gstack Wave 3 FR7) ran the full `go → brainstorm → plan →
plan-review → work → review` pipeline in one long session. Two workflow gaps surfaced:

1. **ADR ordinal collision mid-pipeline.** The plan chose a *provisional* `ADR-087` (highest on
   `main` at plan time was 086). During the work phase's rebase onto `origin/main`, two sibling
   PRs had merged `ADR-087` (cosign-deploy-verify) and `ADR-088` (control-plane-token-minter).
   The ADR was correctly renumbered to **089** and that propagated to the ADR body, the seed
   `taste-profile.md`, and the helper header comment — but the **plan and tasks.md kept the stale
   `ADR-087`**, including **AC12** which literally asserted `` `ADR-087-*.md` exists `` — a
   verification criterion that now fails against the real `ADR-089-*.md`. Caught only at the
   review phase by `pattern-recognition-specialist`.

2. **Orphan test suite.** The shared helper was hoisted to `plugins/soleur/scripts/` (per an
   architecture-strategist "ownership inversion" finding), and its `taste-profile-update.test.sh`
   went with it. But `scripts/test-all.sh`'s bash-shard glob covered `plugins/soleur/test/` and
   `plugins/soleur/skills/*/test/` — **not** `plugins/soleur/scripts/`. The suite passed locally
   (run directly) but would **never gate in CI**. Caught at work Phase 7 by asking "is this test
   actually wired into a gate?" before trusting the green local run.

## Solution

1. **When a provisional ADR/PA/register ordinal is renumbered, grep the whole feature's artifact
   set for the old number and sweep every hit in the same edit cycle** — not just the ADR file.
   The renumber touches: the ADR filename + body, any seed/artifact that cites "See ADR-NNN",
   the helper/code comments, AND the **plan + tasks + every AC** that names the ordinal. AC12's
   `ADR-087-*.md exists` is the load-bearing case: an AC that names a file by ordinal becomes
   false the moment the ordinal moves. Cheapest gate: `grep -rn 'ADR-<old>' knowledge-base/project/{plans,specs}/feat-<slug>/`
   after any renumber.

2. **A hoisted/relocated `.test.sh` must be re-verified against `test-all.sh`'s glob before it
   counts as "gating."** When moving a test to a new directory, `grep -n '\.test\.sh' scripts/test-all.sh`
   and confirm the new path matches one of the loop globs; if not, add the directory glob in the
   same commit. A green *direct* run (`bash <test>`) is not evidence the suite gates in CI.

## Key Insight

A **long single-session pipeline** (plan → work spanning a rebase) is exactly when provisional
identifiers rot: sibling PRs merge *between* plan-time and work-time, so any plan-chosen ordinal,
line number, or count is a moving target. `/ship` re-verifies the next-free ADR ordinal, but that
only fixes the ADR *file* — the planning docs that cite it are a separate surface the re-verify
does not touch. Generalizes the existing "plan-quoted numbers are preconditions, not facts" rule
to **self-authored identifiers that a concurrent merge can invalidate.**

The orphan-suite gap generalizes: **relocating a file can silently move it out of a gate's
discovery glob.** Test discovery is glob-based and per-directory; hoisting a helper for good
architectural reasons (ownership inversion) can drop its test out of CI without any error.

## What went right (pipeline caught its own gaps)

Each stage caught the prior stage's misses: the work-phase rebase caught the ADR collision; work
Phase 7 caught the orphan suite; review's `pattern-recognition` caught the stale AC12; review's
`security-sentinel` confirmed the injection boundary airtight while `code-simplicity` + `user-impact`
converged on the validated-region ≠ consumed-region gap (consumers read the prose table, `--validate`
only certified the JSON block). The multi-stage gates are the value.

## Session Errors

- **ADR-087 → 089 renumber didn't reach plan/tasks/AC** — Recovery: `sed` sweep in the two files at review time. Prevention: grep the feature's `plans/`+`specs/` for the old ordinal immediately after any renumber (this learning).
- **Orphan test suite (`plugins/soleur/scripts/*.test.sh` outside the glob)** — Recovery: added the glob to `test-all.sh:195`. Prevention: re-check `test-all.sh` glob membership whenever a `.test.sh` is created or moved.
- **`validate_json` jq `.`-rebind** (`$str | contains(" " + .field + " ")` indexes the string) — Recovery: bind entry fields with `as` first. Prevention: one-off; note the jq-pipe-rebinds-dot gotcha.
- **Recency-only grep matched the word "confidence" in a helper comment** — Recovery: reworded the comment. Prevention: already covered by `2026-06-17-grep-assertion-over-script-body-false-matches-own-comments`.
- **Stale bare-repo premise (read #5989 as unbuilt)** — Recovery: `git fetch origin main` + re-grep `origin/main`. Prevention: already covered by the premise-validation rules.
- **`test-all.sh` timed out at 550s** (web-platform shard) — one-off; diff touches no web-platform source; CI runs the full suite.

## Tags
category: workflow-patterns
module: plan, work, review, architecture
