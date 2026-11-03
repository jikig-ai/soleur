# Tasks — feat-one-shot-12001-10033-suite-times

Plan: `knowledge-base/project/plans/2026-11-03-fix-ci-ratchet-suite-times-apply-redrive-plan.md`

## 1. Setup / Re-verify

- [ ] 1.1 `git fetch origin main` and confirm the worktree is current; note any sibling drain PRs (#11958/#11950/#11949/#11994/#10926/#10928) merged since 2026-11-03.
- [ ] 1.2 Run `python3 -I scripts/ci-pr-affected-replay.py audit --all-refs` and capture the boundary set; confirm the 8 anchors still match the plan's disposition table (re-derive any that moved).

## 2. Phase 1 — Ratchet repair (#12001)

- [ ] 2.1 Add `scripts/lib/bearer-curl.sh` and `.github/actions/dispatch-web-redeploy/track.sh` to `AFFECTED_PLUGINS_SOLEUR_PATHS` in `scripts/lib/test-affected-paths.sh` (append-only, per-line `why` comments).
- [ ] 2.2 Append the 6 anchor-keyed accept rows to `scripts/ci-pr-affected-audit.accept.tsv` (table in plan §Phase 1; reasons name the line kind).
- [ ] 2.3 Re-run `ratchet`; disposition any DRAIN-REVEAL residue the two new edges mint (repeat to fixpoint).
- [ ] 2.4 `python3 -I scripts/ci-pr-affected-replay.py ratchet --print-baseline > scripts/ci-pr-affected-audit.baseline.tsv`; verify C-locale order + final newline + `ratchet` prints `exit=0`.

## 3. Phase 2 — Top-15 suite-time report (epic #11556 Lever A2)

- [ ] 3.1 List last ≥4 green `merge_group` ci.yml runs; `gh run download <rid> -R jikig-ai/soleur -p 'suite-timings-scripts-*' -D <dir>` each.
- [ ] 3.2 Concatenate TSVs, drop `__run_boundary_*` rows, median per label, rank → top 15.
- [ ] 3.3 Per top-15 label: `suite-durations.tsv` price (flag `floor`), `suite-shard-legs.tsv` leg, cause-class evidence grep (sleep/flock/install/spawn-loop patterns).
- [ ] 3.4 Write `knowledge-base/engineering/audits/2026-11-0X-suite-time-top-15-report.md` (table + methods + outlier remedies + pre-staged next slice).
- [ ] 3.5 File the actionable outlier issues named by the report.

## 4. Phase 3 — Apply-delivery re-queue (#10033)

- [ ] 4.1 `scripts/apply-delivery-gap.sh`: emit `redrive_deploy_fix=true|false` to `$GITHUB_OUTPUT` after `reconcile_issue` (true iff deploy-fix rows exist AND all `evicted-before-start` AND `N_INFLIGHT == 0`); extend `self_test`.
- [ ] 4.2 `.github/workflows/apply-delivery-gap-follower.yml`: `follow` step `id:` + job `outputs:`; new `redrive` job (`needs`, `if:`, job-level `permissions: actions: write`, `gh workflow run … --ref main -f reason=…`); update header contract (no longer DETECTION ONLY).
- [ ] 4.3 `plugins/soleur/test/apply-delivery-gap-follower.test.sh`: add the 5 Guard-Contract rows (eligible/mid-run/in-flight/delivered/harness-shape).
- [ ] 4.4 Update `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-red-run.md` (redrive arm + storm re-eviction residual).
- [ ] 4.5 Author ADR-318 (provisional ordinal — verify next-free; sweep `grep -rn 'ADR-<old>' knowledge-base/project/{plans,specs}/feat-one-shot-12001-10033-suite-times/` on renumber).

## 5. Close-out

- [ ] 5.1 File deferral issues: `queue: max` re-evaluation; `infra`-key redrive extension.
- [ ] 5.2 PR body: `Closes #12001`, `Closes #10033`, `Ref #11556` (epic stays open).
- [ ] 5.3 Verify AC1-AC9 from the plan.
