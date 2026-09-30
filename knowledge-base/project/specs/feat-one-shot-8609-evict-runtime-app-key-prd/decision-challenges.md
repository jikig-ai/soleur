# Decision challenges — feat-one-shot-8609-evict-runtime-app-key-prd

Decisions surfaced during headless planning that belong to the operator, not the pipeline.
Recorded per ADR-084. `ship` renders this into the PR body and files the `action-required` issue.

---

## DC-1 — Courtesy notice to the two third-party installers of the soleur-ai App

**Date:** 2026-09-30
**Classification:** Taste (product/trust decision; no legal duty)
**Status:** OPEN — decide after PR-B (the old key's `401` is proven)

### The question

The soleur-ai runtime key could mint write-capable tokens on two installations outside
`jikig-ai` while it sat in a branch-reachable Doppler config. The exposure is reachability-only;
there is no evidence of use, and the installers' own audit logs (which could show token use)
are not visible to us.

- **CLO:** no notification duty under GDPR Art. 33(2)/34 or contract on reachability alone.
  Record "no notification" as a controller decision. A voluntary notice is defensible because the
  third-party limb (K4) can never be measured. Wording must go through the CLO before sending.
- **CPO:** recommends sending a short notice after PR-B — the repository is public, so the ADR,
  plan and PR describe the exposure anyway, and a user finding it there without hearing from us
  costs more trust than a note. Say "no indication of misuse" unless logs were actually checked.

### Default if no decision is recorded

No notice is sent; the "no notification" controller decision is recorded in the #8609 exposure
assessment. Choosing to send it adds one CLO-reviewed message per installer after PR-B.
