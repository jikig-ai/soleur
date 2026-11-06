---
title: A record PR for a destroy needs its claim limit before the first sentence is written
date: 2026-10-27
category: workflow-issues
tags: [records, claim-limit, sweep, markers, legal, git-data, retention]
---

# Learning: a record PR for a destroy needs its claim limit before the first sentence

## Problem

PR #11284 (issue #11195) recorded that the retired plaintext git-data volume (id 106867358) was deleted at the provider API. The only thing measured was "device deleted at the provider API" (404 by id, absent by name). Review found the first drafts claiming more than that, in four ways:

1. The runbook said no snapshot or backup of the volume "existed or was created". Nothing measured that.
2. A billing clause ("billing ends with the deletion") rested on no invoice or API read.
3. Present-tense statements elsewhere ("currently unencrypted", host-loss paths still naming the volume) were falsified by the destroy. A sweep keyed on the claim's phrasing missed them, because they sit in other sections and files.
4. A `Superseded` marker was written in a form the target file does not use. The runbook uses blockquote markers with bold only through the colon.

## Solution

- Take the claim limit from the legal ruling BEFORE drafting. Here the limit was "device deleted at the provider API"; any positive claim of emptiness, "never held user data", "no snapshot existed" or provider retention is a P1. Put the limit in the review brief so every seat greps for it.
- Replace an absence claim with an explicit non-measurement: "Provider-side snapshots or copies are not measured here either."
- Sweep by the SUBJECT (the volume name, id and resource), repo-wide, and decide every hit. Do not sweep by the phrase you corrected.
- Read the target file's existing markers and copy their form (blockquote, bold range, placement) instead of inventing one.
- Run gate batteries from a script that pins and prints `pwd`, branch and HEAD. A background run from an unpinned cwd printed `blockquote markers: 0` and measured the wrong tree.
- Keep scratch and logs small and under `/var/tmp`. EDQUOT on `/tmp/claude-1000` killed Bash twice and one push in this session.

## Key Insight

For a record of an irreversible action, the claim limit is the specification and the prose is a projection of it. Measure what the action's read-back proves, state only that, and sweep the whole repo by subject for every sentence the action falsified.

## Session Errors

1. **Runbook claimed "no snapshot or backup existed"** — Recovery: replaced with the non-measurement sentence after two seats converged on it — **Prevention:** put the CLO claim limit in the review brief and grep for absence phrasing ("never", "no snapshot", "no personal data") in every added line.
2. **Correction sweep keyed on phrasing missed present-tense twins** — Recovery: subject-keyed grep found the host-loss pointers and the ledger phrase — **Prevention:** grep the resource name and id repo-wide and read every hit; a residual-zero count of the old phrase proves nothing.
3. **Marker added in a form the file does not use** — Recovery: rewritten to the file's blockquote form — **Prevention:** read two existing markers in the target file before adding one.
4. **Unmeasured billing clause** — Recovery: softened to "no further volume charge is expected (not measured against an invoice)" — **Prevention:** a provider-side effect with no read-back behind it gets "expected" or "not measured", never a plain assertion.
5. **Background gate run measured an unpinned cwd** — Recovery: re-ran from `gates3.sh`, which prints `pwd/branch/HEAD` — **Prevention:** wrap multi-gate batteries in a script that pins and prints its tree.
6. **EDQUOT on the scratch dir broke Bash and a push** — Recovery: user freed space, then pushed — **Prevention:** logs under `/var/tmp`; do not delete the user's files to make room without telling them.
7. **Plan-sharp-edges catalogue read only in part** — Recovery: disclosed in the plan — **Prevention:** none beyond the disclosure (one-off).
