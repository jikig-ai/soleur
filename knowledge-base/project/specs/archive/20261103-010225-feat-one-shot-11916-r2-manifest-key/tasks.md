# Tasks — feat-one-shot-11916-r2-manifest-key

Plan: `knowledge-base/project/plans/2026-11-02-fix-cla-evidence-r2-versioned-manifest-key-plan.md`
Issue: #11916 — cla-evidence-timestamp same-month re-dispatch dies on R2 ObjectLockedByBucketPolicy.

## Phase 1 — Workflow fix

- [ ] 1.1 In `.github/workflows/cla-evidence-timestamp.yml` job `env:` block (next to `RUN_ID`), add `RUN_ATTEMPT: ${{ github.run_attempt }}`.
- [ ] 1.2 In step `Upload manifest + .tsr to R2`, change the two destination keys to `timestamps/${YYYY_MM}/manifest-${RUN_ID}-${RUN_ATTEMPT}.jsonl` and `timestamps/${YYYY_MM}/manifest-${RUN_ID}-${RUN_ATTEMPT}.tsr`; update the step's preceding comment to state the per-run-attempt versioned-key contract.
- [ ] 1.3 In step `Persist via PR-with-auto-merge to cla-signatures`, correct the stale comment claiming the R2 upload is "idempotent in practice (PUT overwrites)" — replace with the locked, never-overwrite contract (versioned keys make each PutObject write a never-before-written key). Do NOT change the git `cp`/`git add` filenames — the git paper-trail stays month-keyed.
- [ ] 1.4 AC checks: `grep -n 'manifest-\${RUN_ID}-\${RUN_ATTEMPT}'` returns 2 hits; `grep -nE 's3://.*(manifest\.jsonl|manifest\.tsr)'` returns 0 (destination-anchored: the plan's literal `s3 cp .*manifest\.` regex also matches the `out/manifest.jsonl` SOURCE operand and can never return 0 — destination is what WORM guards); `grep -n 'timestamps/\${YYYY_MM}/manifest'` still returns the persist-step lines; `actionlint` reports no NEW findings vs `origin/main` (the file carries 3 pre-existing shellcheck findings — SC2129 + 2×SC2016 — so AC7's literal exit-0 is unachievable on this file; verified identical on `actionlint /tmp/cet-main.yml`).

## Phase 2 — Runbook retrieval recipes

- [ ] 2.1 In `knowledge-base/engineering/operations/runbooks/cla-signature-evidence-retrieval.md` §6 step 4, replace the two fixed-name `s3 cp` fetches with a list-and-select-latest recipe: `aws s3api list-objects-v2 --bucket "$R2_CLA_EVIDENCE_BUCKET" --prefix "timestamps/$(date -u +%Y-%m)/" --output json`, pick the newest `manifest-*.jsonl` by `LastModified`, then fetch that object and the `.tsr` carrying the identical `<run_id>-<attempt>` suffix. Note the recipe is backward-compatible with legacy fixed `manifest.jsonl`/`manifest.tsr` names (they are oldest `LastModified` and resolve as the only objects present).
- [ ] 2.2 Same replacement in §7.7 (tombstone-presence check), plus the partial-pair caveat: a `.jsonl` whose same-suffix `.tsr` is absent marks an incomplete run — read the previous complete pair instead.
- [ ] 2.3 AC check: `grep -nE 'timestamps/.*/manifest\.(jsonl|tsr)' knowledge-base/engineering/operations/runbooks/cla-signature-evidence-retrieval.md` returns 0.

## Phase 3 — Legal disclosure reconciliation

- [ ] 3.1 In `docs/legal/data-protection-disclosure.md` §2.3(n), replace the fixed `timestamps/<yyyy-mm>/manifest.tsr` assertion with per-run versioned-key wording (e.g., "under a per-run key at `timestamps/<yyyy-mm>/`"). Keep the edit minimal — factual key-name correction only; no posture change.
- [ ] 3.2 Apply the identical wording change to `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` (mirror copy — must move in lockstep per the legal-mirror drift lint).
- [ ] 3.3 AC check: `grep -c 'manifest.tsr'` returns 0 in both copies; `bash scripts/lint-legal-mirror-drift-baseline.sh` (or its normalise diff) shows no new drift; `git diff --quiet origin/main...HEAD -- knowledge-base/legal/article-30-register.md` exits 0.

## Phase 4 — Post-merge verification (automated, `gh` CLI)

- [ ] 4.1 After merge: `gh workflow run cla-evidence-timestamp.yml -f manifest_yyyy_mm=2026-11`.
- [ ] 4.2 Wait for the run; `gh run view <id> --log` must show the upload writing `timestamps/2026-11/manifest-<run_id>-<attempt>.jsonl` + matching `.tsr`, conclusion `success` despite the pre-existing locked `manifest.jsonl`.
- [ ] 4.3 `gh issue close 11916` with the run URL noted (if `Closes #11916` in the PR body did not already close it).
