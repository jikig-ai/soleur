---
title: Decision challenges for feat-one-shot-11294-11711-rotation-audit
branch: feat-one-shot-11294-11711-rotation-audit
created: 2026-11-04
---

# Decision Challenges

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Does `inngest-key-rotate.yml` `keys=both` cover the dedicated Inngest signing+event pair that the `inngest_host`/`inngest_host_replace` jobs printed (the "inngest-host pair needs its own rotation ruling" row of #11711)? | technical | pending - assumed: yes — ADR-307 records the route as the mechanism for exactly this pair (`apply1` `-replace`s `random_id.inngest_{signing,event}_key_dedicated`, `apply2` propagates to the app copies); the #11215 soak gate closed PASS 2026-11-01T18:51Z inside the 11-12 deadline; the ruling the issue wants resolves to "routed — owner-gated dispatch pending", not "needs a new route" |
| Do the retired `random_id.inngest_{signing,event}_key_prd` resources owe a rotation? | technical | pending - assumed: no — both are unreferenced state-only since #10540 (comment at `inngest.tf:47-51`); the printed values feed nothing live, so rotation changes nothing; removal from state is tracked in #11293 and is the close-out |
| Are `random_password` resources exposed via the `[id=]` vector and do they need census rotation rows? | technical | pending - assumed: not exposed — provider source sets `id = "none"` and `result` is sensitive (prints `(sensitive value)`); the 11 `random_password` rows across the roots get census rows marked "not exposed via this vector — no rotation owed by it" |
| How do the 89 `drift-check (apps/web-platform/infra)` job-row census hits reconcile with the drift plan being captured in `$(...)` since file creation? | technical | pending - assumed: the public sink was the `infra-drift` issue body/comment stream (218 comments redacted 2026-11-01), not step logs; the per-line attribution is unresolved until `census-11294.tsv` (operator scratch, sha256 `6ba16467…`) or a git-history scan of `scheduled-terraform-drift.yml` over 2026-07-31→10-29 settles it; bounded because every hit log is deleted |
| Brand-survival threshold `aggregate pattern` for this plan | taste | pending - assumed: aggregate pattern — shared-channel auth keys, not per-user records; the CLO already adjudicated the underlying incident under Art. 4(12) with breach-notification duties not engaged |
| Census row count and shape (12 random_id + 10 random_password main root + 4 rehearsal + 1 rung2 = 27 rows) | technical | pending - assumed: enumerated by `grep -rn 'resource "random_'` over all four Terraform roots on this branch at 2026-11-04 |
