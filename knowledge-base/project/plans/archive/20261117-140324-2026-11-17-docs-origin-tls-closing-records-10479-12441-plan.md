---
title: "docs: origin-TLS closing records for #10479 (CLO Q-1 addendum) and the #12441 analytics series"
date: 2026-11-17
slug: docs-origin-tls-closing-records-10479-12441
branch: feat-one-shot-origin-tls-records-10479-12441
issue: 10479
related: [12441, 10205, 10538, 12742, 12737]
type: docs
detail: minimal
lane: cross-domain
brand_survival_threshold: none
pr: 12843
# No `closes:` key: this PR closes nothing (Ref only; closingIssuesReferences must stay []).
---

# docs: origin-TLS closing records for #10479 and #12441

## Overview

A records-only change on epic #10205. It appends the CLO-owed closing addendum for the origin-TLS thread (#10479) to the counsel-review audit, adds Superseded markers to two auto-close predictions that proved false, and records the second Cloudflare analytics read of the /health series (#12441) with the CTO ruling on it in the strict-flip runbook. No code, infrastructure or published legal page changes.

## Enhancement Summary

**Deepened on:** 2026-11-17
**Sections enhanced:** 4 (Research Insights, Phase 3, Acceptance Criteria, Sharp Edges)
**Research agents used:** none newly spawned at deepen time. This is a proportional pass: the plan is records-only (MINIMAL), and plan time had already run learnings-researcher, CLO, CTO and code-simplicity-reviewer. Every halt gate (4.6, 4.8, 4.12) was run mechanically. 4.5, 4.55, 4.7, 4.9, 4.10, 4.11 and 4.13 do not trigger: there are no network-outage keywords in the plan's own scope, no infra, no code, no UI, no store, no guard and no new task. The quality checks were run live (below).

### Key Improvements
1. Re-verified the cause the markers cite, live, from PR #12737's GraphQL `userContentEdits`: the body edit that dropped `Closes` happened at 2026-11-16T12:59:10Z. Every earlier edit still had `Closes #10538`.
2. Issue (i) now carries the runbook's own full marker shape, including "emitted AFTER the response is written, inside try/catch", which the CTO summary left out. Labels and the milestone for both issues are verified to exist.
3. The removed-line and verbatim checks were changed from grep forms, which could pass on a broken diff, to forms that cannot (numstat deletions, span-removed equality, exact `str.count`).

### New Considerations Discovered
- The brief's "only surviving pre-flip comparison" is too broad: the committed 2026-11-11 evidence files still hold 126 pre-flip hourly rows. The record is bounded to say so (Research Reconciliation).
- The brief's 07:00Z "left the window" time and its "8 h before the flip" label do not match the wrapper's window arithmetic (`gql_window`). The CTO set the wording.

## Research Reconciliation — Brief vs. Codebase

| Brief claim | Reality (read 2026-11-17 in this worktree) | Plan response |
|---|---|---|
| The first reads sit "likely in the latency-candidates table" of `origin-tls-strict-flip.md` | They sit in `##### Addendum 2026-11-11: first sanctioned wrapper reads (Cloudflare analytics, Ref #12441)`, below the candidates table, as additions-only `Unverified:` lines with two tables | Add a sibling `##### Addendum 2026-11-16: ...` right after the 2026-11-11 addendum, before `#### What was NOT run before the flip`. The candidates table is not edited |
| Superseded markers "in the same file's convention" | `2026-11-counsel-review-10479.md` has no marker yet. The corpus uses a blockquote `> **Superseded <date> (#N):** ...` under the line (the A7 file line 11, `2026-10-counsel-review-6931.md`) and, inline, `[Superseded <date>, as to "...":]` (`2026-11-counsel-review-12011.md`) | Blockquote under body lines. Inline bracket inside the YAML string for Q-1 (a YAML flow list cannot hold a blockquote). See the CLO rows |
| Keep `LEGAL_DOC_SHAS` and the ledger lints green | `apps/web-platform/lib/legal/legal-doc-shas.ts` pins only `docs/legal/` pages and does not pin these files. `scripts/encryption-posture-ledger.json` cites the A7 file by path only (connection 6), so a no-rename edit cannot break it. `lint-legal-registers.sh` and `lint-encryption-posture.py` both exit 0 on the base | Run both lints and the doc-SHA check after the edit. No re-pin is expected |
| "the pre-flip hours have left the 216 h window since about 2026-11-17 07:00Z" | The 2026-11-11 read at 17:26Z returned 2026-11-02T17Z to 2026-11-11T16Z, so the window starts at the read hour minus 216 h. By that arithmetic the last pre-flip hour (2026-11-07T22Z) is outside the window for any read after about 2026-11-16T23:00Z | Use the wording in the CTO row (window arithmetic only) |
| 11-07 daily median from "8 h before the flip" | For a read just before 17:00Z the window holds 2026-11-07T16Z to 23Z, so the 8 rows probably include the 23Z hour that straddles the flip, which the 2026-11-11 recipe left out. The raw file is lost, so this cannot be checked | Record the figure as given and say plainly that it is not recorded whether the straddling hour is included |
| "These daily medians are therefore the only surviving pre-flip comparison" | The committed `evidence/2026-11-11-analytics-health-216h.json` and `-edge-errors-216h.json` still hold 126 pre-flip hourly rows (2026-11-02T17Z to 11-07T22Z) | Write it bounded: the 2026-11-16 daily medians are the only surviving pre-flip comparison *from the 2026-11-16 read*; the 2026-11-11 evidence file is the only surviving *hourly* pre-flip record. Say the same in the PR body |
| The 5xx histogram covers the same requests as the /health series | The 2026-11-11 addendum notes that `analytics-edge-errors` filters on the host `app.soleur.ai` (all paths) and `analytics-health` filters on the path `/health`. Different filters, different requests | Say so in the new addendum, as the 2026-11-11 addendum did |

## Research Insights

**Premise validation (2026-11-17).** #10479, #10538, #12441, #10205 and #12742 are all OPEN. PR #12737 merged 2026-11-16T13:10:30Z as `233c690996`; its `closingIssuesReferences` is `[]` and its body says `Ref #10479` / `Ref #10538`, which confirms that both auto-close predictions are false. Draft PR #12843 is OPEN with `closingIssuesReferences` = 0. CLO/CTO comment 6946870123 on #10479 (posted 2026-11-17T11:34:10Z) holds both 2026-11-16 rulings quoted in the brief. Collision pre-check for #10479 and #12441 found only this branch's own draft PR #12843, with no foreign runs.

**Property list.**
- P1: the counsel-review record shows Q-1 as discharged, with the evidence, and does not leave the 2026-11-19 hard stop looking open.
- P2: no live line in the legal records still says GitHub closed, or will close, #10479 or #10538 at the merge of #12737.
- P3: the runbook keeps the only surviving pre-flip comparison of the Cloudflare-side series, names its limits, and states the CTO's attribution status for each feature.
- P4: the next analytics read lands at a durable path.
- P5: every ruling is a row in `decision-challenges.md`.

**Cut list.** Re-saving an evidence JSON file is cut: the raw file is lost, and fabricating one would be a false record. No new lint or guard: the existing legal lints cover these files. No edits to `encryption-posture-ledger.json`: connection 7 already carries no exception (the CLO ruling).

**Conventions (from learnings).**
- `2026-09-15-my-legal-record-said-the-change-had-landed-inside-the-pr-that-lands-it.md` (#8207): no past tense ahead of the merge a claim depends on. Here the measured facts happened before this PR (#12737 merged, reads taken), so the past tense is true. Do not word anything as if #12843 has merged.
- `2026-10-04-a-supersede-note-must-enumerate-what-it-supersedes-and-what-stays-live.md`: quote the superseded phrase, say what stays live, date the reading, and never write "above". A blockquote directly under another blockquote trips MD028, so keep a blank non-quote line between them.
- `workflow-patterns/2026-10-27-legal-correction-notes-quote-the-phrase-they-remove.md`: a marker quotes the phrase, so a check for the phrase's absence must strip marker spans first. Check for the presence of the marker instead.
- `2026-09-03-four-ways-i-destroyed-evidence-in-the-pr-that-exists-to-preserve-it.md`: signed body bytes must survive. Check with `git diff` that no `-` lines appear outside the frontmatter `open_follow_ups` value and the new `addenda:` line.
- `2026-07-15-ad-hoc-verification-evidence-is-as-perishable-as-uncommitted-code.md`: this is the root of the lost raw file. P4 is the fix.
- Sharp-edges catalogue (targeted scan): a brief's "state plainly: X" is a claim to check (the row above); before extending a line, check what exact-matches it. `git grep -F` for the Q-1 text and the Artifact 5 cell text finds only the file itself, so no pin breaks.
- `2026-06-05-followthrough-pr-body-prose-closes-keyword-autocloses-tracker.md`: no close/fix/resolve keyword next to any `#N` anywhere in the PR body.

**Facts the CLO found at plan time (2026-11-17).** The body of PR #12737 said `Closes #10479` and `Closes #10538` when the review was written on 2026-11-15. It was changed to `Ref` at 2026-11-16T12:59:10Z (GraphQL `userContentEdits`), about 11 minutes before the 13:10:30Z merge. So the review's "This PR's body says `Closes #10538`" was true when it was written. Only the prediction that the issues would close at merge is false, and every marker gives this cause. The Q-1 measurement itself is #10479 comment 6917496007 (2026-11-16T13:16:31Z): ruleset v8, last_updated 13:12:15Z, 3 rules, `dcb85b75` strict and the only rule matching app.soleur.ai, no flexible rule, `--require-tls` 20/20. Comment 6946870123 holds the ruling. Cite both.

**Facts the CTO found at plan time (2026-11-17).** `cloudflare-readonly.sh` `gql_window` sets `end` to the current time rounded down to the hour, and `start = end - HOURS*3600`, over the half-open range `[start, end)`. In the committed file `evidence/2026-11-11-analytics-health-216h.json`, hourly p90 is 472 ms at 11-07T22Z, 450 ms at 23Z and 826 ms at 11-08T00Z. The lowest p90 after the flip is 778 ms. No open issue tracks `SOLEUR_HEALTH_TIMING` or a site-split (coloCode) host-filtered query (`gh issue list` searches, 2026-11-17).

**Deepen-time live verification (2026-11-17).**

```text
$ gh api graphql ... pullRequest(number:12737){userContentEdits{nodes{editedAt diff}}}
2026-11-16T12:59:10Z closes=false ref=true    <- the edit that dropped Closes
2026-11-16T10:26:22Z closes=true  ref=false
2026-11-15T23:02:19Z closes=true  ref=false   (and three earlier 11-15 edits, all closes=true)
$ gh pr view 12737 --json closingIssuesReferences,mergedAt,mergeCommit
closes=[]  2026-11-16T13:10:30Z  233c690996010931a31835b22b49cf43949b0fb3
$ gh api .../issues/comments/6917496007 --jq .created_at   -> 2026-11-16T13:16:31Z (Q-1 re-measure)
$ gh api .../issues/comments/6946870123 --jq .created_at   -> 2026-11-17T11:34:10Z (CLO + CTO rulings)
$ gh label list | grep -E '^(domain/engineering|observability)$'   -> both exist
$ gh api repos/jikig-ai/soleur/milestones --jq '.[].title' | grep Post-MVP   -> "Post-MVP / Later"
$ git ls-files | grep health-keyword-monitor-contract   -> apps/web-platform/test/server/health-keyword-monitor-contract.test.ts
$ grep -n legal/audits apps/web-platform/lib/legal/legal-doc-shas.ts   -> (no output: these files are not SHA-pinned)
```

Verify-the-negative pass: "no published legal surface is edited" is confirmed, because Files to Edit holds only `knowledge-base/` paths. "LEGAL_DOC_SHAS does not pin these files" is confirmed by the grep above. "The ledger cites the A7 file by path only" is confirmed: `scripts/encryption-posture-ledger.json` connection 6 holds the path string, and the A7 file is not renamed.

## Files to Edit

- `knowledge-base/legal/audits/2026-11-counsel-review-10479.md`: the frontmatter (`addenda:` key added, Q-1 string extended in place); appended marker brackets at about line 103 (an Artifact 5 table cell) and line 115 (a new sub-bullet under R1's "New:"); a blockquote under line 140 ("Q-1 to Q-6 ..."); a blockquote under line 143 ("GitHub will close ..."); and a new closing section with the verbatim addendum.
- `knowledge-base/legal/audits/2026-11-13-a7-leg2-owner-extension-inngest-sdk-url-poll.md`: one blockquote marker under the "Owner's words" bullet (line 65).
- `knowledge-base/engineering/operations/runbooks/origin-tls-strict-flip.md`: one new `##### Addendum 2026-11-16 ...` section inserted between the end of the 2026-11-11 addendum (the "Not separated by these reads" paragraph) and `#### What was NOT run before the flip`. No existing line is edited.
- `knowledge-base/project/specs/feat-one-shot-origin-tls-records-10479-12441/decision-challenges.md`: written at plan time, extended at work time with the two follow-up issue numbers.

## Files to Create

None in the repo tree. The work phase files two GitHub issues (see Phase 3).

## Implementation Phases

### Phase 1 — Part A: CLO closing addendum (due 2026-11-19)

All marker dates are **2026-11-17** (CLO Q3). The addendum heading keeps **2026-11-16** word for word. No signed body text is rewritten: every change appends.

1. **Frontmatter `addenda:`.** Add `addenda:` as the last frontmatter key, directly after `re_evaluation_triggers`, with this value exactly (CLO Q4):
   `addenda: ["2026-11-16 post-merge Q-1 discharge addendum, written 2026-11-17 (#10479, records PR #12843; Q-1 measured 2026-11-16 13:12-13:16Z, #10479 comment 6917496007; CLO ruling 2026-11-16, posted in #10479 comment 6946870123): discharges Q-1 and supersedes the auto-close prediction for #10479 and #10538 (both OPEN; #12737's body was edited to Ref before merge). See 'Addendum — 2026-11-16 (post-merge, Q-1)'"]`
2. **Q-1 in `open_follow_ups`.** Keep the Q-1 text exactly as it is. Before Q-1's closing `"`, append (CLO Q2):
   ` [Superseded 2026-11-17 (#10479), as to Q-1 being open: DISCHARGED by the 2026-11-16 13:12-13:16Z read, #10479 comment 6917496007; see 'Addendum — 2026-11-16 (post-merge, Q-1)' below.]`
   The appended text has no raw double quote. Parse the frontmatter afterwards (Phase 4).
3. **Body, under "Q-1 to Q-6, as listed in the frontmatter `open_follow_ups`."** Add an indented blockquote, `> **Superseded 2026-11-17 (#10479), as to Q-1:**`. It says that Q-1 is discharged (comments 6917496007 and 6946870123), and that Q-2 to Q-6 stay open. On Q-1's clause "Do this before #12742 dispatches anything", assert only what has evidence: "the CTO ruling of 2026-11-16 (#10479 comment 6946870123) records the #12742 replace as not yet requested". Do not claim that no dispatch has run.
4. **Line 143 (prediction a).** Under the bullet, add `> **Superseded 2026-11-17 (#10479), as to "GitHub will close #10479 and #10538 at merge ("Closes")":**`. Then say that PR #12737's body was changed to `Ref #10479` / `Ref #10538` at 2026-11-16T12:59:10Z, before the 13:10:30Z merge (233c690996), so GitHub closed neither issue. Both are OPEN (read 2026-11-17). With Q-1 recorded, #10479 counts as closed for the legal record, but its GitHub state is OPEN and the owner closes it. #10538 may close only as "not planned, superseded by #12742", never as "completed" (CLO 2026-11-16). Never write "#10479 closed". Keep a blank non-quote line between this blockquote and any neighbouring blockquote (MD028).
5. **Line ~103 (Artifact 5 table cell).** Append inside the Verdict cell, after "The issue named closes when this PR merges": `[Superseded 2026-11-17 (#10479), as to "The issue named closes when this PR merges":]`, followed by the same cause (body edited to `Ref #10538` at 2026-11-16T12:59:10Z; #10538 is OPEN; it may close only as not planned, superseded by #12742). Leave "This PR's body says `Closes #10538`" and "WRONG ROUTE. Correct per R1" as they are. Escape no `|`; the appended text must contain none.
6. **Line ~115 (R1 "New:").** Leave the text exactly as it is. Add a sub-bullet indented under the "New:" line: `[Superseded 2026-11-17 (#10479), as to "(#10538 closes on the merge of PR #12737)":]`, with the same cause and OPEN state.
7. **Closing section.** Append at end of file:
   - the heading `## Addendum — 2026-11-16 (post-merge, Q-1)`;
   - the first body line: `Written 2026-11-17; records the 2026-11-16 13:12-13:16Z measurement and the 2026-11-16 CLO ruling. The measurement is #10479 comment 6917496007 and the ruling is #10479 comment 6946870123.`;
   - then the owner's addendum paragraph **verbatim, byte for byte**, starting `**Addendum — 2026-11-16 (post-merge, Q-1).** Q-1 is discharged.` and ending `ledger connection 7 carries no exception.`

### Phase 2 — Part A(b): the A7 record

8. In `2026-11-13-a7-leg2-owner-extension-inngest-sdk-url-poll.md`, under the "Owner's words" bullet (line 65), add an indented blockquote: `> **Superseded 2026-11-17 (#10479), as to "(#10538 closes on the merge of PR #12737)":**`. It gives the same cause (#12737's body was edited to Ref at 2026-11-16T12:59:10Z, before the merge) and says that #10538 is OPEN (read 2026-11-17) and may close only as not planned, superseded by #12742. The route "the owner confirms in their own words on #12742" stays live. The bullet itself is not edited.

### Phase 3 — Part B: runbook addendum (#12441)

9. **File the two follow-up issues first**, so that the addendum can cite their numbers. Each uses `--milestone` from `knowledge-base/product/roadmap.md` (fallback "Post-MVP / Later"). Each references `Ref #12441` / `Ref #10479` / `Ref #10205`, with no closing keywords.
   - (i) `origin-tls: revive the SOLEUR_HEALTH_TIMING marker (trigger (2) of the 2026-11-08 marker ruling met)`. Labels `domain/engineering` and `observability`. The body quotes the runbook's shape sentence verbatim (the "If revived, the shape is: ..." line under "Marker ruling"): a `warn`-level line with fields `total_ms`, `supabase_ms`, `tls` and `protocol`, emitted AFTER the response is written, inside try/catch, only when `total_ms > 500` plus a 1-in-50 sample, at most 6 lines per minute, with the response body and status unchanged (`apps/web-platform/test/server/health-keyword-monitor-contract.test.ts`). The marker does not wait for (ii). (CTO 2026-11-17 Q1.) No priority label: priority is the owner's call.
   - Both issues: milestone `Post-MVP / Later` (verified to exist), and no `Closes`/`Fixes` keyword in the body.
   - (ii) `origin-tls: site-split (coloCode), host-filtered (app.soleur.ai) /health analytics query with an end-time offset in cloudflare-readonly.sh`. Label `domain/engineering`. The wrapper is a closed read-only subcommand set (ADR-289), so the issue names a new subcommand or a flag. It is not a manual GraphQL path. This confirms or rejects the provisional p90 attribution (CTO 2026-11-16).
10. **Insert `##### Addendum 2026-11-16: second wrapper reads and the CTO ruling (Cloudflare analytics, Ref #12441)`** at the position given in Files to Edit, mirroring the 2026-11-11 addendum's register (additions-only, `Unverified:` lines, every figure sampled, no cause claimed beyond the CTO ruling). Content:
    - **Opening.** Additions-only. The read supersedes nothing above, except that the p90 status line "**Status: unexplained.**" at the head of the p90 section is now read together with the CTO ruling below (the line itself stays as written).
    - **Source line.** `cloudflare-readonly.sh analytics-health 216` and `analytics-edge-errors 216`, read 2026-11-16 at about 17:00Z, from origin/main. Do not invent a SHA: if none was recorded, say "checkout SHA not recorded". Cloudflare-side origin response time for `/health`, sampled. The health read is path-filtered and not host-scoped; the edge read is host-filtered (`app.soleur.ai`, all paths). The two do not cover the same requests.
    - **Table 1: daily medians of hourly p50/p90 (ms).** One row per day, using the brief's values exactly: 11-07 233/468; 11-08 258/852 (max p90 1388); 11-09 279/859; 11-10 416/869; 11-11 545/883; 11-12 546/1378; 11-13 555/892; 11-14 572/1388; 11-15 556/902; 11-16 00-07Z p50 540-795, p90 846-1477; 11-16 08-15Z p50 206-273, p90 810-852. The 11-07 row's label, word for word (CTO Q2): "the 11-07 daily median, over the 8 hourly rows dated 2026-11-07 inside that read's window, recorded as given; the raw file is lost, so whether the straddling 23Z hour was among the 8 rows is not recorded, and the 2026-11-11 recipe excluded it." Never "8 h before the flip".
    - **Consistency note.** 11-08, 11-09 and 11-10 match the 2026-11-11 addendum's upper daily medians (258, 279, 416). Its 11-11 figure (548, 17 h) and this read's 545 (full day) differ by 3 ms. This is a description only.
    - **Table 2: 5xx histogram by day (sampled counts).** 11-07 503=1, 521=20; 11-08 520=17, 521=20; 11-11 500=46; 11-12 500=206; 11-16 503=2, 521=1. Totals: 500=252, 503=3, 520=17, 521=41. Days with no row are recorded as "no rows", never "no errors". No 525/526 rows, if that is so in the given data (the brief lists none). Record this as an absence in this read, not as evidence about the hop.
    - **Laptop corroboration.** `/health` x30 on 2026-11-16 at 16:55Z: p50 0.325 s, p90 0.484 s. On 2026-11-17 at 11:33Z: p50 0.247 s, p90 0.320 s. This is client-side, n=30, and a different measurement from the Cloudflare-side series.
    - **Limitation (plain).** The raw hourly file from this read was lost to a session-scratchpad wipe, so no evidence file exists for it. Under the wrapper's window (`end` = the current hour, `start = end - 216 h`), the last pre-flip hour 2026-11-07T22Z is outside the window for every read from 2026-11-16T23:00Z on, and the straddling 23Z hour is outside from 2026-11-17T00:00Z. The daily medians above are the only surviving pre-flip comparison from the 2026-11-16 read; the committed `evidence/2026-11-11-analytics-health-216h.json` and `evidence/2026-11-11-analytics-edge-errors-216h.json` are the only surviving hourly pre-flip record. Write "confirmed gone by 2026-11-17T07:00Z" **only** if an actual read at that time is recorded, and name its run time. Otherwise write "by the window arithmetic" alone (CTO Q2 correction 1).
    - **CTO ruling, 2026-11-16 (#10479 comment 6946870123).** Record it as `Ruled by CTO agent, 2026-11-16: ...` lines. The p90 step at the 11-08 strict flip (about 470 to about 850 ms) is "provisionally attributed" to the strict TLS origin hop; confirmation needs a site-split (coloCode), host-filtered (app.soleur.ai) query with an end-time offset (issue (ii)). The p50 rise from 11-10 to 11-16 08:00Z is "unexplained": it ended at the 08:55Z release, before the web-2 replaces at 11:51Z and 12:01Z, so the replace is ruled out, and the candidates are process state cleared by a restart, or Supabase latency (candidate 4 above). The 500s on 11-11 and 11-12 map to no known incident (unverified). Evidence bar: "attributed" needs a change point within ±1 h, a matching mechanism read, and no alternative event in the window; "noise" means the values stay within the pre-event hourly range; otherwise "unexplained".
    - **CTO ruling, 2026-11-17 (marker).** Trigger (2) of the 2026-11-08 marker ruling ("Cloudflare origin duration shows a step change aligned with the flip") was first met by the 2026-11-11 read and was not acted on then. Say so plainly, and do not give it today's date. The marker is revived as issue (i). No code goes into this PR.
    - **Durable-path note (one line).** Save every analytics read's line 2 to `knowledge-base/engineering/operations/runbooks/evidence/<UTC date>-analytics-<subcommand>-216h.json` (the path the 2026-11-09 median recipe already names) and commit it. Never save it to the session scratchpad.

### Phase 4 — Verify (all read-only)

11. `python3 -c` with `yaml.safe_load` on the counsel-review frontmatter: it parses, `addenda` is a one-item list, and `open_follow_ups` still has 6 items.
12. `git diff --numstat origin/main -- knowledge-base/legal/audits/2026-11-counsel-review-10479.md knowledge-base/legal/audits/2026-11-13-a7-leg2-owner-extension-inngest-sdk-url-poll.md knowledge-base/engineering/operations/runbooks/origin-tls-strict-flip.md`: the deletions column reads `2`, `0`, `0` (the counsel-review `open_follow_ups:` line and the Artifact 5 row are each replaced by one insertion). For each of the two, the new line with the inserted `[Superseded 2026-11-17 ...]` span removed equals the old line byte for byte. (Do not use `grep '^-[^-]'`: it cannot see removed bullet lines, which diff as `-- `.)
13. Verbatim check: save the brief's addendum paragraph to the scratchpad, then run `python3 -c 'import sys; t=open(sys.argv[1]).read(); p=open(sys.argv[2]).read().rstrip("\n"); assert t.count(p)==1' <counsel-review file> <paragraph file>`.
14. Run `bash scripts/lint-legal-registers.sh`, `python3 scripts/lint-encryption-posture.py`, `bash scripts/lint-legal-mirror-drift-baseline.sh --base origin/main`, `bash scripts/lint-legal-scope-block-placement.sh --base origin/main` and `bash apps/web-platform/scripts/check-tc-document-sha.sh`. All exit 0. `node_modules/.bin/markdownlint -c .markdownlint.json` on the three edited files passes. The base is clean for the counsel-review file at plan time. `knowledge-base/project/` is in `.markdownlintignore`, so the plan itself is not linted. `lint-infra-no-human-steps.py` fails on the base with 10 hits, all in other files and none in this change's files, so judge it by new hits only (MD028 in particular).
15. Before every push, run `bash plugins/soleur/skills/ship/scripts/prepush-secret-scan.sh`.

### Phase 5 — PR #12843 (no merge)

16. The PR body uses only `Ref #10479`, `Ref #12441` and `Ref #10205`, and cites the two new issues with `Ref`. No close/fix/resolve keyword sits next to any `#N`. After every body edit, `gh pr view 12843 --json closingIssuesReferences` must return `[]`. Never touch #12698.
17. Mark the PR ready when CI is green and review is done. **Do not arm or enqueue the merge.** Stop and ask the owner for a typed go that names PR #12843.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing on a user-facing surface. No published page, code path or infrastructure changes. The worst case is an internal legal record that misstates the origin-TLS closure, for example by claiming #10479 or #10538 closed. A later counsel review would then read a false record.
- **If this leaks, the user's data is exposed via:** no vector. The files are public-repo records that contain hostnames, rule refs, issue and comment IDs and aggregate latency figures, but no personal data or secrets. The prepush secret scan runs before every push.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** this is a records-only diff with no sensitive paths (it matches no `SENSITIVE_PATH_RE`) and no published legal surface. The claims that do reach users (Privacy Policy §11, DPD 8.1(c)) were attested in #12737 and were not edited here (CLO 2026-11-16: "no corrective PR is needed").

`threshold: none, reason: knowledge-base/ records only; no docs/legal page, code or infra is touched, and the user-facing TLS claim was attested and left unchanged by the CLO on 2026-11-16.`

## Observability

Skipped (plan Phase 2.9): this is a pure-docs plan with no Files-to-Edit under `apps/*/server|src|infra` or `plugins/*/scripts`, and it adds no infrastructure surface. The follow-up issues (i) and (ii) carry their own observability when they are planned.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Add an `addenda:` frontmatter key." [brief] | Phase 1 step 1 | mapped |
| 2 | "In `open_follow_ups`, mark Q-1 discharged, with a Superseded marker under it." [brief] | Phase 1 steps 2-3 | mapped |
| 3 | "Append this addendum verbatim" [brief] | Phase 1 step 7, Phase 4 step 13 | mapped |
| 4 | "Add Superseded markers, in the same file's convention, to two predictions that proved false" [brief] | Phase 1 step 4, Phase 2 step 8 (plus steps 5-6 per CLO Q1) | mapped |
| 5 | "If the LEGAL_DOC_SHAS or ledger lints pin these files, keep them green." [brief] | Phase 4 step 14 | mapped |
| 6 | "Find the runbook section where the earlier first-reads PR ... recorded the analytics first reads." [brief] | Research Reconciliation row 1; Phase 3 step 10 placement | mapped |
| 7 | "Record the following as measured values." [brief] | Phase 3 step 10 (Tables 1-2, laptop) | mapped |
| 8 | "State the limitation plainly." [brief] | Phase 3 step 10 (Limitation) | mapped |
| 9 | "Record the CTO ruling (soleur:engineering:cto agent, 2026-11-16)" [brief] | Phase 3 step 10 (CTO ruling) | mapped |
| 10 | "Add a one-line note that analytics reads must be saved to a durable path" [brief] | Phase 3 step 10 (Durable-path note) | mapped |
| 11 | "Do NOT arm or enqueue the merge" / "closingIssuesReferences must be []" / "Never touch #12698" [brief] | Phase 5 | mapped |
| 12 | "Persist every decision as a row of the `\| Item \| Class \| Ruling \|` table" [brief] | decision-challenges.md | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Markers on line ~103 and R1 "New:" (steps 5-6) | — | inferred — justification: they carry the same false premise as the two named lines. CLO ruling 2026-11-17 Q1 requires them |
| Follow-up issue (i), the marker revival | — | inferred — justification: CTO ruling 2026-11-17 Q1(A). Trigger (2) of a standing ruling has fired, and an untracked revival would be invisible (`wg-when-deferring-a-capability-create-a`) |
| Follow-up issue (ii), the site-split query | "as a later wrapper PR" | asked — tracking issue for the CTO-named follow-up |
| "Written 2026-11-17" first line of the addendum section | — | inferred — justification: CLO ruling 2026-11-17 Q3, no backdating. The verbatim paragraph is unchanged |

### Split Assessment

- Subsystems touched: 2 — `knowledge-base/legal/`, `knowledge-base/engineering/` (plus planning artifacts)
- Planned files: 4 | Estimated changed lines: about 60
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [x] AC1: The counsel-review frontmatter parses with `yaml.safe_load`. `addenda` is a one-item list whose value equals the Phase 1 step 1 string. `open_follow_ups` has 6 items, and item 0 begins with the original Q-1 text and contains `[Superseded 2026-11-17 (#10479), as to Q-1 being open: DISCHARGED`.
- [x] AC2: the Phase 4 step 13 python check passes (the verbatim paragraph occurs exactly once), and `## Addendum — 2026-11-16 (post-merge, Q-1)` is followed by the `Written 2026-11-17; ...` line.
- [x] AC3: `grep -c 'Superseded 2026-11-17 (#10479)'` returns `5` (the verbatim paragraph contains no such string; checked against the brief at plan time) in the counsel-review file (Q-1 string, body Q-1 blockquote, line-143 blockquote, line-103 cell, R1 sub-bullet) and `1` in the A7 file.
- [x] AC4: Signed-body preservation. `git diff --numstat origin/main` gives deletions `2` / `0` / `0` for counsel-review / A7 / runbook. Each replaced line, with the inserted `[Superseded 2026-11-17 ...]` span removed, equals the old line byte for byte.
- [x] AC5: No edited file states that #10479 or #10538 is closed. The new text says "OPEN" for both, with the read date 2026-11-17.
- [x] AC6: The runbook holds exactly one `##### Addendum 2026-11-16:` heading, placed after the 2026-11-11 addendum and before `#### What was NOT run before the flip`. It contains the 11 Table 1 rows (11-07 to 11-15, plus 11-16 00-07Z and 11-16 08-15Z), the 5xx totals `500=252, 503=3, 520=17, 521=41` (written as the table's `| Total | 252 | 3 | 17 | 41 |` row), both laptop samples, the limitation paragraph, both CTO rulings, the two follow-up issue numbers, and the durable-path line naming `runbooks/evidence/`.
- [x] AC7: The strings "8 h before the flip" and "confirmed gone by 2026-11-17T07:00Z" do not appear in the runbook, unless the work phase cites a recorded read run time for the latter.
- [x] AC8: `lint-legal-registers.sh`, `lint-encryption-posture.py`, `lint-legal-mirror-drift-baseline.sh --base origin/main`, `lint-legal-scope-block-placement.sh --base origin/main`, `check-tc-document-sha.sh` and markdownlint on the three files all exit 0. `git diff origin/main --stat` lists no file under `docs/legal/`, `plugins/soleur/docs/pages/legal/`, `apps/` or `scripts/`.
- [ ] AC9: `gh pr view 12843 --json closingIssuesReferences --jq '.closingIssuesReferences'` prints `[]`. The PR body has no close/fix/resolve keyword next to `#N`. The PR is not in the merge queue and auto-merge is not armed.
- [x] AC10: `decision-challenges.md` has its rulings rows: CLO 2026-11-16 x1; CTO 2026-11-16 x4; CLO 2026-11-17 x4 (marker scope, Q-1 format, marker date, `addenda:` value), plus x2 added at review (the `inngest-server.md` precondition, the addendum first line), so 6 in all; CTO 2026-11-17 x2 (marker revive, window arithmetic); plus the taste rows. The 'Marker revive trigger (2)' and 'p90 step' rows cite the issue numbers filed in Phase 3 step 9.

## Domain Review

**Domains relevant:** Legal, Engineering (both carried forward from the 2026-11-16 rulings and ruled again on 2026-11-17 for the new forks; no fresh sweep is needed for a records-only diff).

### Legal

**Status:** reviewed
**Assessment:** The CLO agent ruled on 2026-11-16 that the closing addendum is owed by 2026-11-19, and on 2026-11-17 on marker scope, format, date and the `addenda:` value (Q1-Q4, recorded in decision-challenges.md). The published wording is unchanged and correct.

### Engineering

**Status:** reviewed
**Assessment:** The CTO agent ruled on 2026-11-16 on the latency attribution and the evidence bar. On 2026-11-17 it ruled that marker trigger (2) has fired, so the marker is revived as an issue, and fixed the window-arithmetic and 11-07 wording.

Product/UX Gate: not applicable. No UI surface is touched.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, holds only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6. This one is filled (`none`, with a scope-out reason).
- Markers quote the phrase they supersede. A check that the old prediction is absent will match the markers themselves, so check for the presence of each marker (AC3) instead.
- The Q-1 bracket goes inside a YAML double-quoted flow-list string. A stray `"` or a `"` closed too early breaks the frontmatter for every consumer. AC1 parses it.
- The Artifact 5 bracket goes inside a table cell. A `|` in the appended text would split the row.
- Do not reconstruct a substitute for the lost raw file from the 2026-11-11 evidence (CTO Q2 rejected this). Record the brief's figures as given.
- The verbatim addendum says `origin-tls-probe --require-tls` "returned HTTP 200 over TLSv1.3". Leave it as it stands. The 20/20 count lives in comment 6917496007 and is cited on the `Written` line, not edited into the paragraph.
- The 5xx Table 2 must list every day from 11-07 to 11-16. Days with no row (11-09, 11-10, 11-13, 11-14, 11-15) read "no rows", so a reader cannot take a blank row as zero errors.
- `ship` Phase 5.5 may route a `knowledge-base/legal/` diff to a counsel-review gate. The CLO rulings of 2026-11-16 and 2026-11-17 are the attestation inputs, so cite them rather than re-spawning.
