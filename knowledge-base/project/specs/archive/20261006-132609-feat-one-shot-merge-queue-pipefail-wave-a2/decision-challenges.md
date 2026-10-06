# Decision challenges: Wave A2 plan review (2026-10-06)

Persisted by plan-review (headless). Rendered into the PR body by ship. Neither item is auto-applied.

## 1. User-Challenge: split class W (50 hits, web-host deploy artefacts) out of this PR

- Operator direction: item A (all of apps/web-platform/infra, .github, lefthook.yml, the drain workflow) ships on this branch.
- Challenge (DHH P0, CTO P1; the plan's own Split Assessment also exceeded the file-count and root-count thresholds): class W auto-applies to prod web hosts on merge (apply-deploy-pipeline-fix, cron-egress re-provision), most of its sites have pipefail OFF so the benefit is latent, and #9529 shares seven of its files, so a conflict in the queue can eject the whole PR.
- Plan default: keep W in this PR, commits ordered J, C, CI, W, with a descope valve (ship the first three, move W to A2b).
- Decision needed from the operator if they prefer the split up front: make A2b the default.

## 2. Taste: open a dedicated tracker issue for the four replace-class rows (A3)

- CTO P1: rows citing the umbrella #9217 are invisible to roadmap queries.
- Plan default: no new issue (net-issue-flow gate); the rows name #9217.

## 3. Taste: trim ceremony

- DHH P1: drop the per-hit classification table, pin census, coordination comments and roadmap B-I list. Plan default: kept the table and census as reviewability aids; reduced comments to #9529 and #9571 and removed AC10 and the 20-run AC.
