---
title: A correction PR carried its retired wording in its own commit body, and its replacement hedges still insinuated
date: 2026-09-23
category: workflow-patterns
module: competitive-intelligence
tags: [correction-pr, squash-merge, third-party-content, reconciliation, review]
pr: 8284
---

# Learning: a correction PR's own commit messages and replacement hedges are review surface

## Problem

PR 8284 landed a 2026-09-18 peer-plugin audit of mattpocock/skills five days late, after all five
bundles it recommended had shipped. The work was a reconciliation: correct every present-tense stale
claim and neutralise wording about a named third party's star count. Three defects survived the
implementation and were caught only by a five-agent review plus a CLO ruling:

1. **The replacement text overclaimed.** "Filed as five bundles and all shipped by 2026-09-22" was
   written in two places while the same PR's own status table recorded B5 as not applied and B9/B12
   as partial. A correction sentence summarising a table drifted from the table in the same commit.
2. **The neutralised hedges still insinuated.** Removing "implausible" and "laundered" left
   "unverified", "confirm against a second source", "unusually high for the repo's age" and "if it is
   real" — each of which only makes sense as doubt about a GitHub API count for one named person's
   repo, when the same file cites another competitor's API count as "verified". The fix was a
   non-accuracy reason to withhold citation (stars measure attention, not use) plus a "pair it with a
   usage signal" instruction instead of "verify it".
3. **The retired wording would have reached main through the squash.** The repo squashes with
   `squash_merge_commit_message: COMMIT_MESSAGES`, so the original branch commit's body ("flagged
   unverified rather than laundered as fact", "Soleur is ahead") would have become main's permanent
   commit message for the very PR removing that phrasing.

## Solution

- Every causal or summary sentence the correction ADDED was re-checked against the status table it
  summarises; "all shipped" became "all five closed (B5 not applied; B9/B12 in part; B4/B10 never
  filed)".
- The tone question was routed to the CLO agent (legal posture is the CLO's call, not the operator's),
  which returned paste-ready replacement text for all four passages.
- The branch was collapsed (`git reset --soft <merge-base>` + one commit with a neutral message)
  before merge, so the squash body carries nothing the PR retires.

## Key Insight

On a correction PR, three artifacts carry the claim being corrected, and the diff review sees only
one: the file (reviewed), the replacement sentences (reviewed only if someone checks them against the
PR's own evidence), and the commit messages (reviewed by nobody, and copied onto main by the squash
setting). Before merge, grep `git log origin/main..HEAD --format=%B` for the retired phrases the same
way the file was grepped.

## Session Errors

1. **Plan-artifact push rejected as non-fast-forward** (the branch was an unpushed rebase over the
   remote head). — Recovery: published with `--force-with-lease=<branch>:<old-sha>` at review time. —
   **Prevention:** after rebasing an existing PR branch locally, push the rebase before spawning the
   planning subagent, so its artifact commits fast-forward.
2. **Two research-subagent briefs carried factual errors** (bundle attribution, B4 status, skill count,
   rerun cost, a CI check, an Admin-key consumer, a credit regex). — Recovery: the planner re-derived
   every row with its own command. — **Prevention:** already covered — a subagent's count or status is
   a claim to re-derive (`2026-07-27-instrument-misreports-own-coverage-and-subagent-counts-are-claims.md`).
3. **Checkbox-ticking script asserted on `**AC6**` while the plan writes `**AC6.**`**, aborting after
   `tasks.md` was written but before the plan was, so the commit carried half the ticks. — Recovery: a
   follow-up regex `- \[ \] (\*\*AC%d[.*])` and a second commit. — **Prevention:** write the anchor
   check for every item before writing any file (validate-all-then-write), so a mismatch aborts with
   nothing written.
4. **Replacement wording introduced new defects** (items 1–2 above, plus an absolute local path carried
   over from the original commit). — Recovery: review fixes inline plus the CLO ruling. — **Prevention:**
   for every sentence a correction ADDS, name the table/row that supports it and read them side by side;
   extend the absence-grep list with each hedge a reviewer names.
5. **Retired wording in the branch commit body would squash onto main.** — Recovery: collapsed the branch
   to one neutral commit. — **Prevention:** on any PR whose purpose is removing wording, grep the branch's
   commit bodies for the retired phrases before merge.
6. **The Linear preflight regex `[A-Z]{2,}-[0-9]+` matched `ADR-236`.** — Recovery: judged not a Linear
   ID and skipped. — **Prevention:** one-off in effect; the preflight's own intent (Linear team keys such
   as `SOL-`) is clear enough for an agent to discriminate.
7. **`plugins/soleur/NOTICE` claimed nothing under `knowledge-base/` carries the attribution comment**,
   contradicted by a generated operator-bootstrap `bootstrap.sh` under `knowledge-base/project/specs/`.
   Pre-existing. — Recovery: narrowed the sentence to the Bundle 3 records it was about. — **Prevention:**
   a NOTICE sentence quantified over a directory is a claim to grep, like any other universal.

## Tags

category: workflow-patterns
module: competitive-intelligence
