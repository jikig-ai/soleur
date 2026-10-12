---
title: "A destructive single-use workflow needs content-level evidence, a gate after the evidence step, and credential parity before its first real dispatch"
date: 2026-10-12
category: workflow-patterns
tags: [destructive-operations, evidence-gates, approval-gates, credentials, retirement, web-2, luks]
issue: 9372
pr: 10083
branch: feat-one-shot-9372-web2-luks-cleanup-pr2
---

# Learning: what the web-2 rebirth did not have, and what the next volume-deleting workflow must

## Problem

The single-use web-2 rebirth workflow (#9372, run 2026-10-06 as runs 37508997529 and 37516716515) deleted a
Hetzner volume on the strength of an "emptiness" check. It worked: no loss was observed, web-2 was an unpooled standby at serving weight 0 with no routed data, and
the volume was re-born raw and formatted LUKS at first boot (graded by the #6931 PASS of 2026-10-10). But the
evidence step measured a coarse bound and called it emptiness, and two properties around it were missing. The
workflow is now deleted (ADR-263 addendum 2026-10-12), so the question #9642 asked (how strict the evidence must be)
was ruled moot and retrospective for this cleanup by the CTO agent on 2026-10-11. What survives is a requirement
list for any future workflow that deletes a volume on evidence.

## Solution / Key Insights

1. **Require content-level emptiness evidence, not a size bound.** The evidence step passed on the trailing
   7-day `filesystem_used_bytes` of `/mnt/data` staying at or under 1 GiB with a spread of at most 64 MiB. The
   observed level was 15,556,608 to 16,027,648 bytes over 169 hours, which is about what an ext4 volume's own
   metadata occupies, but it was never compared with an independent empty reference (a freshly formatted ext4
   volume of the same size): that reading is a hypothesis, not a measurement. A used-bytes figure cannot tell
   "empty" from "holds 15 MB of someone's files". Evidence that a volume is safe to delete must read what is on
   the device (a listing of the filesystem tree, an inode count against a fresh-format baseline, or an equivalent
   content read), or the workflow must carry a refusal that the number alone cannot override.
2. **Put a second gate after the evidence step.** The environment approval is a job-level gate: it comes before
   the evidence step. The numbers were readable in a plan-only run, but an apply dispatch's PASS flowed into the
   `delete-volume` step in the same approved job, so nobody read the numbers between the check and the delete.
   An approval that precedes the measurement approves the intent, not the measurement. For an irreversible step,
   split the job: the evidence step ends the first job and publishes its figures, and a second approved job (or a
   step gated on a fresh approval) performs the delete only after a person has read them.
3. **Check credential parity before the first real dispatch.** The read-only control that confirmed the Better
   Stack row paths ran under Doppler read credentials, while the workflow read the repository
   `BETTERSTACK_QUERY_*` secrets (recorded in the #9642 issue body). A control that passes under one credential
   set says nothing about a run under another. The first live plan-only run shows what an unexercised evidence
   step looks like: it read paths that no stored row carried and went RED `used_bytes_absent_or_host_dark` (run
   37463995633), and only a separate read-only control found the real row shape. Before a destructive workflow's
   first real dispatch, run its evidence step end to end under exactly the credentials the workflow will use and
   record the figures it prints.

## Prevention

- A plan for a workflow that deletes a volume names, in its acceptance criteria, the content read it uses as
  evidence, the point after which a person reads the figures before the delete, and the credential set under
  which the evidence step was exercised.
- A review of such a workflow rejects "bytes under a ceiling" as the only emptiness evidence, and rejects an
  approval gate that sits before the evidence step as the only human gate.
- Related: the 2026-08-17 learning on an empty read being three states, and the 2026-10-11 learning on a control
  that fails early; this note is about the delete step that consumed the evidence.

## Session Errors

None in the diff. One measured deviation from the plan: the incremental shard-manifest regeneration also added
floor rows for seven suites that main registers but its manifests lacked, and the infra runner derives its set from
committed files only, so the infra regeneration had to run after the first local commit.
