---
category: workflow-patterns
issue: 10112
date: 2026-11-06
---

# A remediation runbook must order its check before the destructive arm — and a reviewed-patch recipe must enumerate every pin it red-lines

Two independent review-seat findings on PR #12218 (issue #10112 residuals), both in *documentation*, both the same shape: a procedure written for execution under pressure was internally complete but under-enumerated or mis-ordered.

## Finding 1 — `terraform state rm` before the existence check orphans the object it checks for

The stranded-state section instructed `terraform state rm hcloud_volume.rehearsal_inngest …` first, then the Hetzner-API check, and called the two arms "equivalent". If the volume still exists API-side, `state rm` removes the only thing `terraform destroy` reads — the object strands outside the managed delete path, manufacturing exactly the orphan the post-teardown assertion exists to catch. **Rule: in any "X still exists? → arm A, X gone → arm B" remediation, the existence check is the first step and the arm-selection is explicit — never "do B, then check".**

## Finding 2 — the pin list for a reviewed allowlist window named the obvious pins and missed two

The blank-`prd` DR procedure told the window PR to update `_D6_HEAD`, the D6-case literal, and UNP5/UNP5b — but the widen also reds T1.16i (driven config table) and T1.16k (glob-agreement grep). Under incident pressure an unexplained red with no pointer reads as a suite defect, not an incomplete change. **Rule: when a documented patch touches a guarded literal, enumerate every assertion that reads that literal — `git grep -n '<literal>' <suite-files>` — and name them all; "fail closed" is not a substitute for "named".**

## Finding 3 — a fix sweep keyed on the corrected string misses the sites that carried the old claim differently

The 2026-10-24→2026-10-26 date correction fixed 4 sites and missed a 5th because that line phrased the date differently ("late-October host-replace prework (2026-10-24)"). Same class as PROPAGATED: grep the claim's *shape*, not just the exact string, before declaring the sweep done.
