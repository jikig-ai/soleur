# Tasks — feat-one-shot-11796-ratchet-pairs

Plan: `knowledge-base/project/plans/2026-11-01-ci-affected-index-ratchet-pairs-repair-plan.md`
Issue: #11796 | PR: #11814

Live ratchet state (2026-11-01): `exit=1 reason=new-pair live=1518 baseline=1510` —
8 uncovered pairs (5 from #11713, 3 from #11688).

- [x] Step 0 — Re-run `python3 -I scripts/ci-pr-affected-replay.py ratchet --report /tmp/ratchet.txt`
       and `audit --all-refs` to re-enumerate every boundary line + anchor/ordinal at work time
       (main may have moved again; pairs beyond the 8 planned must be triaged the same way)
- [x] Step 1a — Extend `AFFECTED_PLUGINS_SOLEUR_TEST_NPM_PUBLISH_OIDC_TEST_SH_PATHS` (~:3359,
       sorted) with `knowledge-base/engineering/operations/runbooks/npm-publish-trusted-publisher.md`
       (`[[ -f ]]` assert at test :1107, rubric-c) and `packages/opencode-plugin/package.json`
       (jq real read, test :1103, rubric-b)
- [x] Step 1b — Add `AFFECTED_SCRIPTS_GIT_DATA_REPLICATION_SIGNAL_11704_PATHS` after the
       `..._GIT_DATA_REHEARSAL_EVIDENCE_8211_PATHS` block: `scripts/lib/betterstack-read-classify.sh`,
       `scripts/lib/betterstack-sources.sh`, `scripts/lib/test-affected-paths.sh` (THIS FILE)
- [x] Step 2 — Insert 7 anchor-keyed accept rows (sorted TSV position, never append):
       2× `scripts/betterstack-emitter-read` (anchor f35b5c5e8a3d/1, kind `data row not fed to a
       read loop`, cite FLOOR :335 + LIVE :347 + always-on `betterstack-emitter-read-live`),
       3× `scripts/git-data-replication-signal-11704 → scripts/betterstack-query.sh`
       (anchors 9b15ae82a00e/1, 3db9a5675390/1, 7feaf06e5ad1/1 — stub-shadowed fixture refs),
       2× `plugins/soleur/test/npm-publish-oidc.test.sh → package.json` (anchors
       243d3a657939/1, e6f0ead4b98e/1 — basename token; root package.json never opened)
- [x] Step 3 — Prune `scripts/test-affected-kb-consumers.baseline.txt:100` (npm runbook pair the
       declared edge vacates); run `bash scripts/test-affected-kb-consumers.test.sh` — restore the
       row if the suite still reports it live
- [x] Step 4 — `ratchet` → `SOLEUR_PR_AFFECTED_RATCHET exit=0`; `--print-baseline` diff ==
       baseline.tsv (adopt pruned file only if different); `lint-orphan-test-suites.sh` clean;
       `--print-selection` shows each new edge selecting its suite
- [ ] `Closes #11796` on PR body with per-pair provenance (#11713 vs #11688);
       review/qa/compound/ship per one-shot
