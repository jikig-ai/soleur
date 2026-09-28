---
title: "A restored marker restored controls nobody measured"
date: 2026-09-27
category: security-issues
module: knowledge-base/legal
issues: ["#8754", "#8872"]
tags: [legal-records, append-only, restored-marker, overclaim]
---

# Learning: a restored marker restored controls nobody measured

## Problem

The #8754 post-replace check measured one thing: the Hetzner cloud firewall 11269127 was
`applied` on the new Inngest server 167651172. The restored markers I wrote first went further.
They said "all three controls are in force again" (runbook) and "in force again, alongside
host-local nftables and the `/v1/*` loopback gating" (ADR-030 ×2). The Art. 30 (e) marker said
"this clause again describes the host", and that clause includes the nftables scoping. The
determination's own L2 limb says nftables load was measured on the old host 167310350 only.
The replacement host was never measured for it. Two review seats, security and evidence-fidelity,
independently flagged the gap.

## Solution

Narrow every marker to the measured control:

- the cloud firewall is measured in force;
- nftables and the `/v1/*` loopback gating are "installed by design; load on 167651172 not
  separately measured".

The CLO's #8872 condition added the same qualifier to the PA-13 (g) TOM (11)(b) cell.

## Key Insight

A restoration marker is a claim about what a check MEASURED, not about the design the incident
temporarily broke. When the defect was one control missing, the natural sentence is "the controls
are back". But the check only re-measured the missing one. Every other control mentioned nearby
has its own measurement history, and on a replaced host that history is empty.

## Session Errors

1. **Restored markers overclaimed unmeasured controls.** Recovery: narrowed in a review commit.
   **Prevention:** for each marker, list the controls the verification actually measured and
   state every other control as "by design, not measured on <host>". The route-to-definition
   was not applied: `plugins/soleur/skills/review/SKILL.md` is at its byte ceiling
   (lint-skill-body-budget), so this learning is the record.
2. **In-cell breach-register inserts rewrote existing tokens** (`loopback` became `loopback.`).
   Recovery: an em-dash separator restores the original tokens. **Prevention:** on append-only
   records, run `git diff origin/main...HEAD --word-diff=porcelain -- knowledge-base/legal | grep -c '^-[^-]'`
   and expect 0 before pushing.
3. **The coverage wording asserted "whole window"** when five 12 h counts do not arithmetically
   span the 63 h read. Recovery: the verdict is attributed "as recorded with the read", with the
   tail rows cited. **Prevention:** before stating a coverage verdict, check that the window
   edges add up; if they don't, attribute the verdict to its source.
4. **`xxd` is not installed on this host.** Recovery: skipped the check. **Prevention:** use
   `od -c` or `tail -c1 | od -An -tx1`.
5. **A `grep -v` on a path also hid matching content lines**, because the breach-register row
   cites the determination's path. Recovery: grep per file. **Prevention:** filter by filename
   with `git grep -l` first, then grep each file.

## Tags

category: security-issues
module: knowledge-base/legal
