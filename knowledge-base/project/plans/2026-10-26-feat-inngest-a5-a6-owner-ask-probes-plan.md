---
title: "feat: owner-ask probe for the Inngest TLS arc acts A5 and A6"
date: 2026-10-26
slug: inngest-a5-a6-owner-ask-probes
branch: feat-inngest-a5-a6-owner-ask-scheduler
issue: 11207
lane: single-domain
type: feat
---

# feat: owner-ask probe for A5 and A6

## Overview

The Inngest link TLS flip (act A3) ran on 2026-10-26 and the 48-hour soak (A4) is tracked by #11215. Two owner-human acts follow: A5 (the `INNGEST_SIGNING_KEY` rotation) and A6 (the "no known access" record). No agent runs either, and no delegation covers them. This plan adds one notify-only probe on the existing follow-through sweeper. Once a day it tells the owner, in plain words, what the next open act is, and it warns when the CLO bridge date (2026-11-12) is at risk because the rotation apply route (#10540) has no date. It never closes a tracker and never performs an act.

## Research Insights

**Premise validation (checked 2026-10-26).** #10136 open (epic, carries the done-anchors). #11207 open. #11215 open (soak tracker, `earliest=2026-10-28T13:56:10Z`). #10540 open, labels `priority/p2-medium` and `deferred-scope-out`, no date, no milestone. #10542 closed. #10543 open. The runbook states A5 is not dispatchable by an agent until #10540 lands (`inngest-server.md`, "Key rotation order (A5)", step 5). Held: nothing cited is stale.

**Property list.**
- P1: when A5 becomes askable the owner is told, in plain words naming the act, on every sweep until A5 is recorded.
- P2: from 2026-11-09, if #10540 is not closed COMPLETED and A5 is not recorded, the owner is told the bridge date is at risk, with the two ways out. This holds whatever state the soak tracker is in.
- P3: A6 is asked only after A5 is recorded.
- P4: the probe never exits 0 or 1 and never performs an act.
- P5: the reminder does not depend on the Inngest host, which A5 restarts.

**Cut list.** (a) A new scheduler or Inngest one-shot reminder: P5 rules it out and the sweeper already runs daily on GitHub Actions. (b) A hand-filed `action-required` issue per act: no date logic, no re-ask. (c) An `.acknowledged` file as the done record: it is a repo commit that sets a measured floor for the 7922 probe, not a completion record. (d) Probe preconditions for the nftables re-read and the Hetzner member list: the probe cannot read them, so the ask text names them as owner and CLO acts. (e) A second A6 probe and tracker, the 2026-11-30 A6 dead-man, parsing the sweeper's PASS comment, and a `followthrough-convention.md` listing: removed after plan review (see Review Disposition).

**Ruled by CTO agent, 2026-10-26.** Fork 1: a notify-only probe on the existing sweeper rather than hand-filed issues or an Inngest reminder. Fork 2 and its amendment after plan review: one probe and one tracker; both done-anchors live on the epic #10136 as trusted comments, because the tracker number is unknown when the probe is written. Fork 3: exit 5 with a 2026-11-09 dead-man date while #10540 is open; done is a trusted-comment anchor, not the `.acknowledged` file. Conditions: the A6 ask text states the 2026-12-10 lapse date and the days left; the A5 ask text names #10543.

**Review Disposition (plan-review, 2026-10-26).** Applied as mechanical: epic-anchored done markers (no tracker-number guess); "soak passed" is #11215 closed with `stateReason` COMPLETED (a PASS-comment parse is forgeable on a public repo and has no owner exit); "route landed" is #10540 closed COMPLETED; the bridge-risk row is evaluated before the soak rows; honest re-ask wording; verifiable acceptance commands; tracker-number acceptance criterion; trimmed mutation tables; no convention-doc edit. Applied by CTO ruling: single probe and tracker.

**Conventions applied.** Exit vocabulary `2` NOT YET, `3` CANNOT ESTABLISH, `5` ACTION REQUIRED, never `0` or `1` (`followthrough-convention.md`). Precedent `scripts/followthroughs/ccla-representative-icla-7922.sh`. Anchors are read through `scripts/lib/trusted-verdict.sh`, whose marker family is `^(RESULT|S[0-9]+-[A-Z][A-Z0-9_-]*):`. On an open tracker the sweeper comments at every exit 5 sweep and keeps it open; the ask therefore repeats daily until the anchor is posted. The sweeper republishes probe output in a public issue comment, so every output line is authored plain words with no key material, no host id and no CLO-internal detail.

## Scope Check

| Ask (verbatim from the owner) | Mapped to |
|---|---|
| "shall we plan a scheduler for A5 and A6" | the probe, its tracker, the two anchors |
| "yes to all" (create the soak tracker, plan the asks, look at #10540) | soak tracker #11215 (done), this plan, the 2026-11-09 #10540 dead-man |

Inferred items: the 2026-11-09 date (CLO bridge date 2026-11-12 minus three days, ruled by the CTO) and the runbook row edits (the runbook must name the tracker and the anchors it relies on). No other inferred item.

## Files to Create

- `scripts/followthroughs/inngest-a5-a6-owner-ask-10136.sh`
- `scripts/followthroughs/inngest-a5-a6-owner-ask-10136.test.sh`

## Files to Edit

- `scripts/test-all.sh` (one `run_suite` line)
- `knowledge-base/engineering/operations/runbooks/inngest-server.md` (A5 and A6 rows: name the tracker and the two anchor lines)

## Implementation Phases

### Phase 1 — failing suite first

Write `inngest-a5-a6-owner-ask-10136.test.sh` with a stubbed `gh` and a stubbed `trusted-verdict` view; one case per decision row below, plus the guard cases. The suite must fail before the probe exists.

### Phase 2 — the probe

No `secrets=` beyond `GH_TOKEN`. Decision order, first match wins. Any `gh` read failure, at any point, is exit 3 and never 5 (an unreadable state must not ask the owner to act on a guess).

1. Trusted `S6-A6-DONE: <UTC ISO>` on #10136 → exit 2, "A5 and A6 are recorded; close this tracker and remove its label."
2. No trusted `S5-A5-DONE:` anchor, today on or after 2026-11-09, and #10540 not closed COMPLETED → exit 5, bridge-risk ask: the key rotation has no dated apply route, the CLO bridge ends 2026-11-12 (extendable once to 2026-12-10), and the two ways out: schedule #10540, or run the manual Key rotation procedure with the owner's go. After 2026-11-12 the text says the bridge date has passed.
3. Trusted `S5-A5-DONE:` anchor present → exit 5, A6 ask: write the no-known-access record under `knowledge-base/legal/audits/`, link it from #10382 and #10136, the CLO attests it separately; the record needs the measured nftables re-read and the Hetzner member list; the Inngest row lapses 2026-12-10 and the text prints the days left.
4. #11215 open → exit 2, "waiting on the soak".
5. #11215 closed with `stateReason` other than COMPLETED → exit 3, "soak closed without a completed result; reopen it or post the soak result on #10136".
6. #10540 not closed COMPLETED (before 2026-11-09) → exit 2, "A5 is blocked on #10540".
7. Otherwise → exit 5, A5 ask: "This replaces the scheduler's signing key on both the Inngest host and the web app, then restarts the server and redeploys web." Names #10543 (fixed, or a quiesced window plus a replay check; the probe reads #10543's state and prints which applies) and the line the owner posts when done (`S5-A5-DONE: <UTC ISO>` on #10136).

### Phase 3 — tracker and wiring

File one tracker (`follow-through`, `action-required`, `meta/machinery`, milestone "Post-MVP / Later") whose body carries the directive with `earliest=2026-10-28T13:56:10Z` and `secrets=GH_TOKEN`. Add the `run_suite` line. Update the A5 and A6 runbook rows. List the retirement sites in the probe header (the suite, the `test-all.sh` line, the runbook rows, and any fixture baseline row, enumerated with `git grep` of the stem at retirement).

## Acceptance Criteria

- [ ] The suite drives every decision row with a stubbed `gh` and asserts the exit code and one literal output string per row.
- [ ] The suite asserts the probe never exits 0 or 1 on any input, including malformed `gh` output.
- [ ] A `gh` failure on any read yields exit 3 (suite case per read: #11215, #10540, #10543, the anchors).
- [ ] The suite asserts no output line contains a login, a host id, a key name or the text "CLO-internal".
- [ ] `grep -c 'inngest-a5-a6-owner-ask-10136.test.sh' scripts/test-all.sh` prints 1, and `bash scripts/followthroughs/inngest-a5-a6-owner-ask-10136.test.sh` exits 0.
- [ ] After merge, `gh issue view <tracker> --comments` shows the sweep comment after 2026-10-28T13:56:10Z; the expected heading is NOT YET while #11215 is open (the tracker number is recorded in the PR body once filed).
- [ ] The runbook A5 and A6 rows name the tracker number and both anchor lines.

## Guard Contract

### Guard 1 — the owner-ask probe

**Property.** The probe asks the owner to act only in the states the decision table names, and in every unreadable state it says it cannot establish instead of asking.

**Assembly.** The decision table in `inngest-a5-a6-owner-ask-10136.sh` is the single chokepoint. Its inputs are four reads: #11215 state, #10540 state, #10543 state, and the trusted anchors on #10136. The sweeper's exit-code mapping in `scripts/sweep-followthroughs.sh` is the consumer.

**Mutation matrix.**

| # | Mutation | Must go RED because |
|---|---|---|
| 1 | Accept an anchor from an author without write permission | the untrusted-author fixture expects row 4, not row 3 |
| 2 | Accept an anchor inside a code fence | the fenced-anchor fixture expects row 4, not row 3 |
| 3 | Remove the date comparison so row 2 always fires | the row-6 case dated before 2026-11-09 expects exit 2 |
| 4 | Let a `gh` failure fall through to row 7 | the per-read failure cases expect exit 3 |
| 5 | Evaluate the soak rows before row 2 | the case with #11215 open and the date past 2026-11-09 expects exit 5 |

**Harness rows.** Edit the suite so its `gh` stub reports every issue open: the "ready" case (row 7) must go RED. A must-PASS input that is not the canonical: an anchor with trailing text after the ISO time still counts, and #10540 closed COMPLETED with a different closing comment still reaches row 7.

**Anchor.** Done is a comment by an author with write permission, resolved through `trusted-verdict.sh`; a probe-edited constant cannot move it.

## User-Brand Impact

**If this lands broken, the user experiences:** a missed or premature reminder to the owner; no end-user surface changes.
**If this leaks, the user's data is exposed via:** a public issue comment, if the probe printed a secret or CLO-internal text; the suite greps for that.
**Brand-survival threshold:** none. `threshold: none, reason: notify-only script under scripts/followthroughs/ that reads GitHub issue state and performs no production act.`

## Domain Review

**Domains relevant:** none

No cross-domain implications beyond the CTO ruling recorded above; the A6 ask text names the CLO's separate attestation without changing it.

## Observability

```yaml
liveness_signal:
  what: the sweeper's daily comment on the tracker
  cadence: daily
  alert_target: GitHub issue comment, notifies the issue author
  configured_in: .github/workflows/scheduled-followthrough-sweeper.yml
error_reporting:
  destination: the sweeper's CANNOT ESTABLISH comment heading
  fail_loud: exit 3 with the reason on every unreadable state
failure_modes:
  - mode: sweeper does not run
    detection: cloud-task-silence monitor on the sweeper workflow
    alert_route: cloud-task-silence label issue
  - mode: probe reads the wrong state
    detection: suite rows plus the first-sweep acceptance criterion
    alert_route: PR review
logs:
  where: sweeper run log and the tracker comment
  retention: GitHub Actions default
discoverability_test:
  command: bash scripts/followthroughs/inngest-a5-a6-owner-ask-10136.test.sh
  expected_output: 0 failed
```

## Sharp Edges

- The anchor lines are `S5-A5-DONE:` and `S6-A6-DONE:` on #10136; the `trusted-verdict.sh` marker family requires the `S<digits>-<CAPS>:` shape, so a lower-case or differently shaped line is dropped silently.
- Sweeper comments are public; do not add a Hetzner server id, host IP or key name to any probe line.
- The dates 2026-11-09, 2026-11-12 and 2026-12-10 are constants in the probe header, derived from the CLO bridge dates; if the bridge is extended or lapses, edit them there.
- The ask repeats on every sweep while an anchor is missing; that is the sweeper's exit-5 behaviour, not a bug.
