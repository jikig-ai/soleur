---
title: Decision challenges for feat-one-shot-11294-11711-rotation-audit
branch: feat-one-shot-11294-11711-rotation-audit
created: 2026-11-04
---

# Decision Challenges

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Does `inngest-key-rotate.yml` `keys=both` cover the dedicated Inngest signing+event pair that the `inngest_host`/`inngest_host_replace` jobs printed (the "inngest-host pair needs its own rotation ruling" row of #11711)? | technical | Ruled by CTO agent, 2026-11-04: yes — `inngest-key-rotate.yml keys=both` is the complete merged route for the dedicated pair (apply1 `-replace`s `random_id.inngest_{signing,event}_key_dedicated`, apply2 propagates the derived app copies); the row resolves to "routed — owner-gated dispatch pending", not a new route - `scripts/inngest-key-rotate.sh` gate table, workflow `keys` choice, #11215 soak COMPLETED 2026-11-01T18:51Z |
| Do the retired `random_id.inngest_{signing,event}_key_prd` resources owe a rotation? | technical | Ruled by CTO agent, 2026-11-04: no — state-only since #10540, zero `.tf` references, `-replace` changes no live value; close-out is state removal under #11293 - `inngest.tf` retired-block comment + `grep -rn 'inngest_{signing,event}_key_prd'` returns comments/tests only |
| Are `random_password` resources exposed via the `[id=]` vector and do they need census rotation rows? | technical | Ruled by CTO agent, 2026-11-04: not exposed — the provider emits literal `[id=none]` on refresh lines and `result` is sensitive (prints `(sensitive value)`); census rows marked "not exposed — no rotation owed by this vector" - `test-tf-redact-random-ids.sh` fixture shape, `hashicorp/random` 3.9.0 lock pin |
| How do the 89 `drift-check (apps/web-platform/infra)` job-row census hits reconcile with the drift plan being captured in `$(...)` since file creation? | technical | Ruled by CTO agent, 2026-11-04: mechanism narrowed — plan-stream ruled out by a full git-history scan (`PLAN_OUTPUT=$(terraform plan …)` captured since creation commit `e997bc5185`; every `cat plan-output.txt` sits inside issue-body heredocs feeding `gh issue comment/create`; zero `terraform show\|state\|refresh\|output\|apply` to stdout in any revision); remaining attribution is census-column counting vs matrix-leg misattribution, which needs `census-11294.tsv` (operator scratch, uncommitted); bounded — every hit log is deleted |
| Brand-survival threshold `aggregate pattern` for this plan | taste | Ruled by CTO agent, 2026-11-04: aggregate pattern — shared-channel auth keys, not per-user records; the CLO already adjudicated the incident under Art. 4(12), no Art. 33/34 duties - `knowledge-base/legal/audits/2026-10-29-clo-determination-11294-random-id-log-exposure-art-4-12.md` |
| Census row count and shape (12 random_id + 10 random_password main root + 4 rehearsal + 1 rung2 = 27 rows) | technical | Ruled by CTO agent, 2026-11-04: 27 rows exact — 12 `random_id` + 10 `random_password` in `apps/web-platform/infra`, 2+2 in `inngest-provision-rehearsal`, 0+1 in `rung2-rehearsal`; three roots declare `random_` resources ("four roots" phrasing imprecise, count and split exact) - `find . -name '*.tf' -exec grep -Hn 'resource "random_'` enumeration |
