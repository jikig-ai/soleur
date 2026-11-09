# Criterion (d): reader audit — 2026-11-09

test-affected-kb-consumers.test.sh: 31 passed, 0 failed of 31 (cases=31)
KB-mention census: baseline lists 340 known-gap rows (wc -l scripts/test-affected-kb-consumers.baseline.txt = 340); b1 asserts committed baseline == regenerated (no stale/missing).
edge:consumed datapoint: `apps/web-platform [repo-wide+component]` prints `sel=0 edge:consumed` on a README-only diff (--paths=README.md), i.e. a consumed edge does not spuriously select the suite.

Status: pass
