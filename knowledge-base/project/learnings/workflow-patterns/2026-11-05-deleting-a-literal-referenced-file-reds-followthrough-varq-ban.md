---
title: "Deleting a file that a followthrough probe literals reds lint-followthrough-varq-ban — run the linter before pushing a deletion"
date: 2026-11-05
category: workflow-patterns
related: [10861, 10865, 12127]
---

The PR5z strict-zero slice deleted `scripts/ci-pr-affected-audit.baseline.tsv` (in scope per spec) but
the #10865 observation probe `scripts/followthroughs/ratchet-observation-window-10865.sh` still carried
`BASELINE="scripts/ci-pr-affected-audit.baseline.tsv"` as a bare literal. `lint-followthrough-varq-ban`
rule 3 requires every repo-relative literal in `scripts/followthroughs/*.sh` to resolve in the checkout —
three shards went red at once: `followthrough-varq-ban-live` plus `zot-log-channel-probe` and
`betterstack-roundtrip-latency`, whose suites assert the real linter stays green.

Fix was one line: `# repo-path: runtime` on the BASELINE assignment — the probe resolves the path via the
Contents API at remote refs (`gh api repos/.../contents/$BASELINE?ref=<sha>`) and already handles
absence-at-tip as the designed end state, so the literal is honestly runtime-scoped, never a checkout
read. The annotation is per-line; a file-scoped skip does not exist by design.

Rule: any plan that deletes a tracked file must grep `scripts/followthroughs/` for the path AND run
`bash scripts/lint-followthrough-varq-ban.sh` locally before push — the linter runs in seconds and would
have caught this pre-CI instead of costing a full battery cycle plus a post-ready fix commit.
"Verify-only" in a spec for sibling probes means run their gate, not read them by eye.
