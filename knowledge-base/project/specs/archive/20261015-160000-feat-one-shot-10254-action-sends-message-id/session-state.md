
### Ship-phase position (near-final)
- HEAD d21066c62e (history rewritten to soleur-ai[bot] for cla-check; tc-document-sha literal updated). PR #10385 READY, 0 failing checks, merge-queue armed. Poll `gh pr view 10385 --json state` → MERGED, then verify release workflows (`gh run list --limit 5`), postmerge checks, worktree cleanup, emit DONE + resume prompt.

### Ledger-parity incident (resolved)
- `tenant-integration` + `tenant-integration-required` RED on dev-ledger-parity: migration 162's file was applied to dev by the FIRST push's CI (blob 1885e4f4); the review-fix comment made the tree body differ (526e945f). A ledgered filename is immutable (#8521/#8583).
- Fix: restored the applied body verbatim (delta was 4 comment lines only — semantics identical, dev schema already matches intent). New head after rewrite+fix; monitor 6e95c5 polling to MERGED.
- QA disposition: Test Scenarios all TENANT_INTEGRATION-gated → verified by the CI tenant-integration job + post-merge scheduled suites.
