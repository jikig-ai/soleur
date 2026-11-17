---
date: 2026-11-07
category: workflow-patterns
---
# A `--rows` re-split stales every literal range in the corpus — grep the OLD range, not just the suite

Retiring the observation-window section moved the replay suite's `DECLARED_TOTAL` 602→473 and re-split its three registered arms `1-193/194-386/387-602` → `1-158/159-316/317-473`. The footprint census enumerated the suite file, both registration sites, the edge arrays, and the accept rows — but missed `scripts/ci-oracle-lane.test.sh:1220`, whose G4 argv-drift fixture does `sed 's|--rows 1-193|--rows 1-195|'` against the manifest. After the re-split the sed substituted nothing, the drifted manifest came back byte-identical, and the `MEMBER-ARGV-DRIFT` row would have gone red on the suite's next run — a vacuous-fixture failure invisible to `bash -n` and to the re-split's own tiling guard.

The cheap gate for the next re-split: `rg -n 'rows <old-range>' scripts/ .github/ plugins/` for each retiring range literal — the sed anchor lives in a consumer the author list never names. Two runbook tables carried the same stale figures (twice over: 582/578 vs 602, then 602 vs 473), which shows literal ranges in docs rot the same way. Review caught all three; CI would have caught the test one red.
