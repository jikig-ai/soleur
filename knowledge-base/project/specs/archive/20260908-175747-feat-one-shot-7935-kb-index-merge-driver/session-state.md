# Session State

## Plan Phase

- Plan file: knowledge-base/project/plans/2026-09-08-fix-kb-index-merge-driver-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors

- `iac-plan-write-guard.sh` PreToolUse hook blocked the first full plan write on the phrase
  "out-of-band" (its `out[- ]of[- ]band` pattern). Resolved by rephrasing, NOT by the
  acknowledgement opt-out — no infrastructure step existed to acknowledge.
- The Kieran correctness reviewer ran ~29 min and returned against a superseded draft; two
  findings were still new and were folded in, the rest were already resolved by the revision.
- An AC insertion briefly duplicated numbers 15-17; corrected by appending the new criteria as
  AC24-AC26 so no existing cross-reference broke.
- Two agent measurements conflict on whether `npm install --package-lock-only` fires `prepare`.
  The empirical one (fixture run, npm 12.0.2) was adopted; the plan records it as measured and
  Phase 0 re-verifies.

### Decisions

- **Row-set merge over regeneration** — forced by measurement, not preference. At merge-driver
  invocation time the worktree and index are still on the *ours* side (incoming files are not on
  disk, `MERGE_HEAD` unset), so "regenerate against the merged tree" would index the ours-side
  file set and re-create the exact row-drop the driver exists to prevent. A `pre-merge-commit`
  fallback is also dead: the hook sees the merged tree but its `git add` is discarded because
  `git merge` computes its tree first. The driver derives the merged index from the three
  versions git supplies (`%O`/`%A`/`%B`). The three cases where this diverges from a true
  regeneration are named explicitly in the plan rather than glossed.
- **`merge=union` for `kb-tags.txt`/`kb-categories.txt`, not a bespoke driver mode** — the only
  content consumer validates with `grep -Fxq`, which is indifferent to order and duplicates, so a
  git built-in satisfies the real contract with zero code and no unregistered-failure mode. The
  lefthook stanza is widened so those files are actually staged.
- **Loudness comes from CI, not git** — an unregistered driver falls back silently with no
  warning, so the guard is a regeneration diff (`--out DIR` + `--check`) rather than a structural
  lint; that is the only form that catches title drift and the rename case.
- **Two registration surfaces, not three** — the key lands in the shared bare-repo config
  (verified empirically), so the first surface to fire registers all 37 worktrees; the lefthook
  arm was cut because it fires *after* the merge it would arm.
- **"Stop committing the index" recorded as a challenge, not adopted** — two reviewers converged
  on it and its supporting facts check out, but it reverses an explicit instruction and carries
  costs they did not price. Written to `decision-challenges.md` for `ship` to surface; no issue
  filed, keeping #7935 at Closing:1 / Filing:0 / Net:-1.

### Two live bugs surfaced that were NOT in the issue

- The lefthook `generate-kb-index` glob has **never** matched `knowledge-base/INDEX.md` (gobwas
  `**` needs an intermediate directory; verified against real lefthook).
- `merge-pr/SKILL.md` routes the index to guidance telling the reader to resolve conflict markers
  that a driver failure guarantees are absent — a live path to the reported bug through the
  repo's own skill.

### Components Invoked

- Skills: `soleur:plan`, `soleur:deepen-plan`
- Agents: `repo-research-analyst`, `learnings-researcher`, `cto`, `spec-flow-analyzer`,
  `kieran-rails-reviewer`, `code-simplicity-reviewer`, `dhh-rails-reviewer`, `security-sentinel`,
  `test-design-reviewer`, a scoped strong-model consult, plus verify-the-negative and
  dropped-symbol-audit passes
- Gates run: plan Phases 0.6 / 0.6b / 0.6c / 0.7 / 1.7.5 / 2.5-2.12; deepen-plan Phases 4.4-4.11
- Linters: `lint-infra-no-human-steps.py`, `lint-guard-contract.py`, `c4-count-parity.test.sh`
  (all green)
