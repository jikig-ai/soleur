# Decision Challenges — feat-one-shot-retire-10865-window-probe

| Item | Class | Ruling |
|------|-------|--------|
| Sweeper workflow `pull-requests: read` — the in-file comment says "Retire this line with the probe," but surviving probes read `/pulls` and the mixed `issues` endpoint that silently filters PRs without the scope | technical | pending - assumed: keep the permission, rewrite the comment to attribute surviving consumers; removing it would 403 or silently filter the live probes' reads |
| ADR-276 — the RETIREMENT clause claimed the PR3a amendment names the script path; it does not (issue-number references only) | technical | pending - assumed: no edit; the amendments are dated historical narrative in an append-only record |
| Activation runbook — keep a historical mention vs excise the window subsection | technical | pending - assumed: keep, converted to past tense with a dated note naming this PR; the rules text is the certification record PR3b's entry conditions cite |
| `ci-oracle-lane.md` names #10865 as the evidence-attachment tracker for a future activation audit | technical | pending - assumed: leave; the reference is to the issue record (a closed tracker still accepts comments), not the script |
| Accept-row pruning — hand-delete the 12 probe-citing rows vs re-derive | technical | pending - assumed: re-derive via the ratchet's own `--print-baseline` stale-accept check (exit 2 census-degraded names them); the 12 are the floor, not the ceiling |
| `--rows` re-split shape after the 129-site deletion | technical | pending - assumed: three roughly-equal contiguous arms tiling `1..DECLARED_TOTAL`, identical in test-all.sh and ci-oracle-lane-suites.txt, verified by scripts-shard-totality.test.sh |
