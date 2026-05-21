---
title: tasks for feat-one-shot-fix-kb-drift-walker-doppler-sha
plan: knowledge-base/project/plans/2026-05-21-fix-kb-drift-walker-doppler-action-sha-plan.md
branch: feat-one-shot-fix-kb-drift-walker-doppler-sha
lane: single-domain
created: 2026-05-21
---

# Tasks — fix kb-drift-walker Doppler action SHA

Derived from `knowledge-base/project/plans/2026-05-21-fix-kb-drift-walker-doppler-action-sha-plan.md`.

## Phase 1 — Apply SHA correction

- [x] 1.1 Confirm CWD is the worktree (`pwd` ends in `.worktrees/feat-one-shot-fix-kb-drift-walker-doppler-sha`).
- [x] 1.2 Confirm branch is `feat-one-shot-fix-kb-drift-walker-doppler-sha` (not `main`).
- [x] 1.3 Read `.github/workflows/kb-drift-walker.yml` lines 40-45 to confirm line 43 still holds the bad SHA `517441f1eaf80f64b34d0e4dca44c0aacb13a3a3`.
- [x] 1.4 Edit `.github/workflows/kb-drift-walker.yml:43`: replace the bad SHA with `014df23b1329b615816a38eb5f473bb9000700b1`. Preserve the `dopplerhq/` lowercase prefix, indentation, and the `# v3` trailing comment.
- [x] 1.5 Verify diff shape: `git diff --stat .github/workflows/kb-drift-walker.yml` → expect `1 file changed, 1 insertion(+), 1 deletion(-)`.
- [x] 1.6 Verify bad SHA fully removed: `grep -rn "517441f1eaf80f64b34d0e4dca44c0aacb13a3a3" .github/` returns empty.
- [x] 1.7 Verify new line is verbatim with the length-pinned regex:

  ```bash
  grep -cE '^        uses: dopplerhq/cli-action@014df23b1329b615816a38eb5f473bb9000700b1 # v3$' \
    .github/workflows/kb-drift-walker.yml
  # expect: 1
  ```

- [x] 1.8 Verify the SHA is 40 characters (truncation guard):

  ```bash
  grep -oE 'dopplerhq/cli-action@[0-9a-f]+' .github/workflows/kb-drift-walker.yml \
    | awk -F@ '{print length($2)}'
  # expect: 40
  ```

- [x] 1.9 Best-effort `actionlint .github/workflows/kb-drift-walker.yml` if installed; skip otherwise (non-blocking). (actionlint not installed; skipped)

## Phase 2 — Commit, push, open PR

- [ ] 2.1 `git add .github/workflows/kb-drift-walker.yml`
- [ ] 2.2 `git commit -m "fix(ci): pin kb-drift-walker doppler action to canonical v3 SHA"`
- [ ] 2.3 `git push -u origin feat-one-shot-fix-kb-drift-walker-doppler-sha`
- [ ] 2.4 Open PR with title `fix(ci): pin kb-drift-walker doppler action to canonical v3 SHA`.
- [ ] 2.5 PR body MUST contain `Ref: Actions run 26209907780`.
- [ ] 2.6 PR body MUST contain a one-sentence statement that subsequent step failures (Doppler auth, signing key, ingest) are out of scope.
- [ ] 2.7 PR body MUST cite the canonical SHA source: `gh api repos/dopplerhq/cli-action/git/refs/tags/v3` → `014df23b1329b615816a38eb5f473bb9000700b1`.
- [ ] 2.8 Labels: `type/bug`, `domain/engineering`, `priority/p1-high`, `chore`, `semver:patch` (verify each exists with `gh label list --limit 200 | grep -E "^<label>\\b"` before adding).

## Phase 3 — Post-merge verification (automated via /soleur:ship)

- [ ] 3.1 Wait for PR merge to `main`.
- [ ] 3.2 Capture trigger timestamp: `TRIGGER_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)`.
- [ ] 3.3 `gh workflow run kb-drift-walker.yml --ref main` returns success (HTTP 204).
- [ ] 3.4 Poll for a run created at-or-after `TRIGGER_TS` (do NOT use `gh run list --limit 1`, which races with the `0 3 * * *` schedule):

  ```bash
  for i in 1 2 3 4 5 6; do
    RUN_ID=$(gh run list --workflow=kb-drift-walker.yml \
      --created ">=${TRIGGER_TS}" \
      --limit 1 \
      --json databaseId \
      --jq '.[0].databaseId // empty')
    [ -n "$RUN_ID" ] && break
    sleep 5
  done
  [ -n "$RUN_ID" ] || { echo "ERROR: no run created after $TRIGGER_TS"; exit 1; }
  ```

- [ ] 3.5 `gh run watch "$RUN_ID" --exit-status || true` (allow non-zero — we re-classify below).
- [ ] 3.6 Probe step conclusion: `gh run view "$RUN_ID" --json jobs --jq '.jobs[].steps[] | select(.name == "Install Doppler CLI") | {name, conclusion, started_at}'` → MUST show non-null `conclusion` AND non-null `started_at`.
- [ ] 3.7 Confirm the resolve-failure signature is absent: `gh run view "$RUN_ID" --log 2>&1 | grep -q "Unable to resolve action.*dopplerhq/cli-action"` MUST return non-zero (no match).
- [ ] 3.8 If steps 3.6/3.7 both pass: this PR's scope is satisfied. Any subsequent step failure observed in `$RUN_ID` MUST be filed as a separate issue, NOT folded back into this PR.

## Phase 4 — Cleanup

- [ ] 4.1 If a learning is warranted (e.g., "the bad SHA originated from PR #X"), file it under `knowledge-base/project/learnings/bug-fixes/<topic>.md` with today's date. If the origin is unclear from git blame, skip the learning — over-explanation of a typo is debt.
- [ ] 4.2 Archive plan and tasks if requested via `/soleur:archive-kb` (defer until next archive sweep).
