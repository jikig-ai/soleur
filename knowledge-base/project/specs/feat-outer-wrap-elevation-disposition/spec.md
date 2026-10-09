---
title: Disposition — drop the arm-F elevation arm (#9873); executor proceeds unchanged (#9773)
status: decided (operator ratified 2026-10-09)
owner: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-10-09-outer-wrap-elevation-disposition-brainstorm.md
issues: [9873, 9773]
branch: feat-outer-wrap-elevation-disposition
pr: 9896
created: 2026-10-09
---

# Spec: Outer-wrap elevation arm disposition (Option 3)

## Decision

**Option 3 — drop the privileged elevation arm.** `AGENT_OUTER_WRAP` remains
flag-off on the shared prod container; the implicit-userns fallback continues to
serve hosts that permit it. `agent-outer-wrap.ts` (771 lines, tested, flag-gated)
is kept inert as design reference for the executor's host launcher — not deleted.
#9773 / epic #9842 proceed unchanged; no interim arm competes with Stage 0/1.

Operator ratified 2026-10-09 after unanimous CTO/CLO/CPO + prior-art analysis
(see brainstorm for the full option matrix).

## Why not the arms

- **Setuid bwrap (1a):** dead mechanism — upstream removed setuid at 0.12.0,
  deprecated it at 0.11.2 (CVE-2026-41163); works only on prod's pinned 0.8.0,
  untestable on dev's 0.12, dead on any upgrade. Any elevation arm also needs
  `CAP_SYS_ADMIN` in the container bounding set (3 `docker run` sites), which
  flips seccomp onto its permissive CAP_SYS_ADMIN shape for every process and
  weaponizes every setuid binary already in the image (`su`, `mount`, `newgrp`).
  An agent-reachable setuid bwrap is the primitive that unmasks the deny-mounts
  in force today — self-defeating.
- **Bespoke setuid launcher (1b):** parked behind a revisit trigger — executor
  Stage-1 GA slips ~8 weeks, or a realized sibling-filesystem incident. Closes
  only sibling-FS-presence; heap/proc/net/IPC residuals stay open either way.
- **Patch/fork (2):** forked security-critical binary for a transitional arm.

## Residual (accepted, documented)

Sibling filesystem *existence*/mount-table presence on the shared container
stays open until #9773 Stage 1. Sibling workspace *content* remains masked by
the #5862 deny-then-restore + realpath hook (the `denyRead` on `workspacesRoot`
stays load-bearing indefinitely under flag-off — see #9798 note). Exit
criterion: #9773 Stage 1 GA.

## Record actions (deliverables of this disposition)

- [x] R1 Close #9873 with the decision comment
- [x] R2 ADR-075 addendum (2026-10-09): file-cap arm reverted; arm dropped
- [x] R3 Flag the stale arm-F TOM bullet to PR #9832 (rewrite owed before merge)
- [x] R4 compliance-posture.md row — residual named, exit = #9773 Stage 1
- [x] R5 CLO ruling doc in knowledge-base/legal/audits/
- [x] R6 #9798 annotated: premise (post-promotion cleanup) void under flag-off;
      denyRead stays load-bearing
- [x] R7 No-claim discipline noted (Schedule-4 interim wording per executor
      Decision 9 already correct)
