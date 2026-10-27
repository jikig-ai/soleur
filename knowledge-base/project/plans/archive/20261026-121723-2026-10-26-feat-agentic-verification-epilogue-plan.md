---
title: "feat: agentic-verification arc epilogue — issue close-out + distribution scheduling"
type: feat
date: 2026-10-26
slug: feat-agentic-verification-epilogue
branch: feat-one-shot-10902-agentic-verification-epilogue
issue: 10902
closes: 10902
priority: p2
domain: marketing
brand_survival_threshold: none
lane: cross-domain
---

# feat: agentic-verification arc epilogue — issue close-out + distribution scheduling

## Overview

The agentic-verification content arc's seven blog posts are all merged and live
(five-spoke squash commit `5a284d137b`, 2026-10-25; hub published 2026-10-24;
dated→canonical 301 pairs verified at `apps/web-platform/infra/seo-bulk-redirects.tf:96-104`).
What remains is the epilogue: the issue ledger does not yet reflect shipped
reality (synthesis brief #10902 OPEN while its deliverable is published), two
stale-premise decision-challenges (#11078, #11003) sit on the action-required
backlog, an open scope challenge (#10736) needs a roster-free verification
comment, and six promotion-ready distribution drafts sit at `status: draft`
with empty `publish_date` — waiting for the daily `cron-content-publisher` to
assign them filename-ordered Tue/Thu slots that do **not** match the slots the
content PRs intended. This plan verifies the shipped state once more at work
time, pins all six drafts to deterministic dates, and performs the four issue
operations.

Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed).

## Research Insights

### Premise Validation (plan Phase 0.6)

Every cited artifact was verified against live state on 2026-10-26:

- **#10902 is the arc's synthesis content brief, not the epic.** Its body reads
  "Content brief — arc-level synthesis from the epic-close CMO assessment of
  #10397"; the parent epic is **#10397** (verified `CLOSED`). The directive's
  "close the epic" maps to #10902 — the brief whose deliverable (the hub post)
  is published. State: OPEN, labels `content`, `priority/p1-high`,
  `domain/marketing`.
- **All five child content briefs CLOSED** (verified `gh issue view` on
  2026-10-26): #10636, #10694, #10730, #10737, #10739.
- **Hub post is published and links all seven spokes.** Distribution file
  `2026-10-23-agentic-verification-arc.md` is `status: published`,
  `publish_date: 2026-10-24`. `plugins/soleur/docs/blog/2026-10-23-agentic-verification-checklist-shipped.md`
  links `map-that-cant-drift`, `map-that-only-records-what-the-agent-saw`,
  `property-test-cannot-fail-teaches-nothing`, `first-property-test-found-real-bug`,
  `test-the-migration-not-just-the-schema`, `flaky-test-passed-on-retry-quarantine`,
  `audited-102-guardrails-four-portable`.
- **#11078's recorded default is half-stale.** The blog post shipped with the
  default date (`plugins/soleur/docs/blog/2026-10-29-property-test-cannot-fail-teaches-nothing.md`,
  `date: 2026-10-29`; redirect pair present) — the *post-date* half of the
  default held. The *distribution* half did not: the draft
  `2026-10-29-property-test-cannot-fail-teaches-nothing.md` carries
  `status: draft`, `publish_date:` empty, and the 2026-10-29 distribution slot
  is occupied by `2026-10-27-audited-102-guardrails-four-portable.md`
  (`status: scheduled`, `publish_date: 2026-10-29`).
- **#11003 (sibling, not cited by the directive — inferred finding).** The
  guardrails spoke's own decision-challenge recorded "2026-10-27 stands"; the
  shipped distribution slot is 2026-10-29. Same stale-premise class as #11078.
- **#10736 verified roster-free.** Zero matches for `ux-audit`,
  `reproduce-bug`, `consumer` in both the spoke post
  (`plugins/soleur/docs/blog/2026-11-12-map-that-only-records-what-the-agent-saw.md`)
  and its distribution draft. The prior CTO ruling is on record at
  `knowledge-base/project/specs/archive/20261025-214638-feat-one-shot-10902-arc-spokes/decision-challenges.md`
  (row: "confirm the consumer-count-free default", Ruled by CTO agent,
  2026-10-25).
- **All six target drafts pass the readiness gate.** Channels
  `x, bluesky, discord, linkedin-personal` declared; zero Liquid markers; all
  four mapped sections (`## X/Twitter Thread`, `## Bluesky`, `## Discord`,
  `## LinkedIn Personal`) carry substantive content (spot-read 2026-11-05
  file; all six have populated section bodies).
- **The only other `status: draft` in the corpus cannot interleave.**
  `2026-04-24-service-automation-hn-show.md` has `channels:` empty → fails
  `isReadyDraft` (`content-promotion.ts:181-187`) → never promoted; it appears
  in campaign-calendar's "Stale Draft — needs approval" table instead.
- **Squash commit `5a284d137b` verified on origin/main** — PR #11108, merged
  2026-10-25; PR #11067 (PBT spoke) merged 2026-10-25T16:29Z.

### Mechanism (verified at source, plan Phase 0.6 + 1.7)

- `apps/web-platform/server/inngest/functions/content-promotion.ts`:
  `HORIZON_DAYS=28`, `PROMOTION_WEEKDAYS=[2,4]` (Tue/Thu), `planPromotions`
  assigns ready drafts in **filename-ascending** order to the next free
  Tue/Thu slots; `applyPromotion` flips `status: draft`→`scheduled` and
  rewrites `publish_date:` **unconditionally** (a draft with a pre-set date
  still gets re-slotted).
- `apps/web-platform/server/inngest/functions/cron-content-publisher.ts:281-292`:
  the `occupied` double-book set is the `publish_date` of **every** file
  regardless of status. Occupied near-horizon: **2026-10-27** (opencode,
  scheduled), **2026-10-29** (guardrails, scheduled), **2026-11-04**
  (six-questions, draft — PR #11158 flips it to `scheduled` keeping the date).
- `scripts/content-publisher.sh:861-896`: the daily publisher posts any file
  with `status: scheduled` + `publish_date == today` — **no weekday
  restriction**; a scheduled file whose `publish_date < today` is flipped to
  `status: stale` (warning + stale event), so a pinned date must not slip
  into the past before the run.
- The cron's promotion writes land via a **bot-PR** (`safeCommitAndPr` +
  synthetic checks), not a direct main push — operator-visible but racy
  against hand-pinning.
- `campaign-calendar.md` is **auto-generated** from distribution frontmatter
  by `cron-campaign-calendar`; it must not be hand-edited for status flips.

### Slot simulation (the load-bearing finding)

Free Tue/Thu slots from today (2026-10-26): `11-03, 11-05, 11-10, 11-12, 11-17,
11-19, 11-24…` (10-27, 10-29, 11-04 occupied). If all six drafts stay
`status: draft`, the cron assigns by filename order:

| Draft (filename order) | Auto-slot | Intended (filename/blog) date |
|---|---|---|
| 2026-10-29-property-test | 2026-11-03 | 2026-10-29 (occupied) |
| 2026-11-03-first-property-test | 2026-11-05 | 2026-11-03 |
| 2026-11-05-map-that-cant-drift | 2026-11-10 | 2026-11-05 |
| 2026-11-10-migration | 2026-11-12 | 2026-11-10 |
| 2026-11-12-map-only-records | 2026-11-17 | 2026-11-12 |
| 2026-11-17-flaky | 2026-11-19 | 2026-11-17 |

Every spoke lands one slot late — and if PR #11158 has not merged,
`2026-11-04-six-questions` (still `status: draft`) interleaves third in
filename order and has its hand-set `publish_date: 2026-11-04` **overwritten**
by `applyPromotion`. Pinning all six explicitly is the only deterministic
outcome; it is also the "flip to scheduled with publish_date" arm the
directive names.

### Property List (plan Phase 0.6b)

- P1 — the issue ledger reflects shipped reality: closed issues carry evidence
  comments, open ones carry the findings an operator needs.
- P2 — all six ready drafts hold deterministic, non-colliding publish dates
  before the next daily cron run.
- P3 — no published post or shipped doc is falsified by the open #10736 scope
  decision.
- P4 — zero file or slot conflict with open PR #11158
  (`2026-11-04-six-questions-before-recurring-job.md` +
  `2026-11-04-before-your-ai-team-takes-a-recurring-job.md` are untouched).

### Cut List (plan Phase 0.6b)

- **Hand-editing `campaign-calendar.md`** — cut; it is auto-generated from
  frontmatter by `cron-campaign-calendar` (property P2 is already bought by
  the frontmatter edit; the learnings file warns a regen before a rebase
  silently drops rebased content).
- **Touching `2026-11-04-six-questions-*`** — cut; PR #11158 owns that file
  and its slot (explicit directive: "avoid file or slot conflicts with it").
- **A re-slot helper/script or new scheduling mechanism** — cut;
  `publish_date` + `status` frontmatter plus the existing publisher already
  buy property P2 (no new machinery per 0.6b).
- **Closing #10736** — cut; the citation-scope decision is `operator (scope)`
  class. The plan supplies the roster-free finding only.
- **Renaming the property-test blog post/date** — cut; the post is live under
  its shipped 10-29 URL pair and the recorded default for the *post* held;
  only the distribution slot was displaced.

### Institutional learnings applied

- `knowledge-base/project/learnings/workflow-patterns/2026-10-25-rebase-continue-editor-hang-orphan-hooks.md`
  — `GIT_EDITOR=true git rebase --continue`; kill orphan `git commit`
  children, not just the rebase; `LEFTHOOK=0` for rebase replay (verified
  knob, not `LEFTHOOK_EXCLUDE`); complete the conflict resolution commit
  once before interrupting; regen generated calendars after the last
  rebase, not before.
- Sibling-spec decision-challenge conventions
  (`specs/archive/20261025-214638-feat-one-shot-10902-arc-spokes/` and
  `20261025-150240-feat-one-shot-10904-pbt-methodology/`): headless runs
  record operator-schedule defaults in `decision-challenges.md` rather than
  asking; technical rulings without an Agent tool are
  `pending - assumed: <default>`; absent agent-spawn capability is itself a
  recorded technical row.
- `distribution-content-format.test.ts` gates scheduled/draft files against
  the publisher's parse contract — flipping `status: draft`→`scheduled`
  brings these files under that CI guard, so run it locally.

### Research reconciliation — spec vs codebase

| Spec/directive claim | Verified reality | Plan response |
|---|---|---|
| "epic #10902" | #10902 is the synthesis content brief; parent epic #10397 CLOSED | Verify children + close #10902 per directive intent |
| "the 2026-10-29 slot was occupied by the guardrails spoke post" | Confirmed — distribution slot only; the *blog post* shipped with `date: 2026-10-29` | Resolve #11078 on the distribution half; post-date default held |
| "six distribution drafts sit at status:draft" | Confirmed — all six ready-gate-clean; a seventh file (`2026-04-24-*`) is draft but gate-excluded | Pin the six; leave the seventh alone |

## Problem Statement / Motivation

The arc's content work shipped in three PRs but its bookkeeping and scheduling
did not finish: the synthesis brief is still open, two decision-challenges
record defaults contradicted by what shipped, an open scope challenge needs one
verified fact to be resolvable, and six promotion-ready drafts will be
auto-slotted by tomorrow's cron run onto dates that contradict the slot
decisions recorded in the arc-spokes spec — unless they are pinned first.

## Proposed Solution

Four small phases — verification, six frontmatter pins, four issue operations,
artifacts. No code, no new mechanism, no content authoring.

### Implementation Phases

#### Phase 1 — Re-verify shipped state (read-only)

- Re-run `gh issue view` on #10397, #10902, #10636, #10694, #10730, #10737,
  #10739 — all CLOSED except #10902 (the one this plan closes). Abort #10902's
  close-out if any child reopened.
- Re-grep the hub post for the seven spoke slugs (abort on any missing link).
- Re-run the occupied-set enumeration:
  `grep -H "^publish_date:" knowledge-base/marketing/distribution-content/*.md`
  — confirm 10-28, 11-03, 11-05, 11-10, 11-12, 11-17 are still free before
  pinning; if any was taken since plan time, pick the next free day and update
  the decision-challenges row in the same commit.

#### Phase 2 — Pin the six distribution drafts

Six targeted frontmatter edits (two lines each, matching the corpus'
unquoted-date convention):

| File | `status:` | `publish_date:` |
|---|---|---|
| `2026-10-29-property-test-cannot-fail-teaches-nothing.md` | scheduled | **2026-10-28** |
| `2026-11-03-first-property-test-found-real-bug.md` | scheduled | 2026-11-03 |
| `2026-11-05-map-that-cant-drift.md` | scheduled | 2026-11-05 |
| `2026-11-10-test-the-migration-not-just-the-schema.md` | scheduled | 2026-11-10 |
| `2026-11-12-map-that-only-records-what-the-agent-saw.md` | scheduled | 2026-11-12 |
| `2026-11-17-flaky-test-passed-on-retry-quarantine.md` | scheduled | 2026-11-17 |

- If the cron's bot-PR already promoted a file before this lands, the edit
  still applies — `publish_date:` is rewritten to the pinned value regardless
  of prior value; do not accept the cron's assignment over the pin.
- Do **not** touch `2026-11-04-six-questions-before-recurring-job.md` or any
  other file (P4).
- Validation: `bash scripts/lint-distribution-content.sh <file>` per edited
  file + `bun test plugins/soleur/test/distribution-content-format.test.ts`.

#### Phase 3 — Issue operations

- **#10902 → close with completion comment** citing: children #10636 #10694
  #10730 #10737 #10739 + epic #10397 CLOSED; hub published 2026-10-24
  (`status: published`); all seven spoke links verified in the hub body;
  squash `5a284d137b`.
- **#11078 → comment + close.** Comment covers: post-date default held
  (`date: 2026-10-29` shipped, redirect pair live); distribution premise
  falsified (10-29 occupied by the guardrails spoke's scheduled slot);
  resolution = explicit pin `publish_date: 2026-10-28`; reversal = reopen and
  edit the date before the next publisher run.
- **#11003 → comment + close** (inferred sibling): recorded default 2026-10-27
  superseded by shipped reality (`publish_date: 2026-10-29` scheduled); no
  action needed.
- **#10736 → comment only, leave OPEN.** The comment supplies the verified
  fact: the map-that-only-records post and draft are consumer-roster-free
  (zero `ux-audit`/`reproduce-bug`/consumer references) per the CTO ruling
  recorded 2026-10-25 in the arc-spokes spec; no post or doc change is
  required by either resolution. The keep-vs-revert decision stays the
  operator's.

#### Phase 4 — Artifacts & close-out

- `decision-challenges.md` + `tasks.md` in
  `knowledge-base/project/specs/feat-one-shot-10902-agentic-verification-epilogue/`
  (written by the planning phase; work phase keeps the property-test date row
  accurate if the pin moves).
- Rebase hygiene if needed: `GIT_EDITOR=true`, `LEFTHOOK=0` for replay,
  enumerate `pgrep -a git` before retrying a stalled continue (learning
  2026-10-25).

## Files to Edit

- `knowledge-base/marketing/distribution-content/2026-10-29-property-test-cannot-fail-teaches-nothing.md` — `status: draft`→`scheduled`, `publish_date: 2026-10-28`
- `knowledge-base/marketing/distribution-content/2026-11-03-first-property-test-found-real-bug.md` — `status: draft`→`scheduled`, `publish_date: 2026-11-03`
- `knowledge-base/marketing/distribution-content/2026-11-05-map-that-cant-drift.md` — `status: draft`→`scheduled`, `publish_date: 2026-11-05`
- `knowledge-base/marketing/distribution-content/2026-11-10-test-the-migration-not-just-the-schema.md` — `status: draft`→`scheduled`, `publish_date: 2026-11-10`
- `knowledge-base/marketing/distribution-content/2026-11-12-map-that-only-records-what-the-agent-saw.md` — `status: draft`→`scheduled`, `publish_date: 2026-11-12`
- `knowledge-base/marketing/distribution-content/2026-11-17-flaky-test-passed-on-retry-quarantine.md` — `status: draft`→`scheduled`, `publish_date: 2026-11-17`

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-10902-agentic-verification-epilogue/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-10902-agentic-verification-epilogue/decision-challenges.md`

## Technical Considerations

- **`applyPromotion` is unconditional on `publish_date`** — a `status: draft`
  file with a hand-set date still gets re-slotted. Only `status: scheduled`
  protects a pin; that is why every pin includes the status flip.
- **Race with the daily cron.** The cron runs daily; whichever lands first
  wins the occupied set. All pins are written in this PR so the outcome is
  deterministic at merge rather than corpus-order-dependent.
- **Race with PR #11158.** If the cron's bot-PR runs while
  `2026-11-04-six-questions` is still `status: draft`, it will be promoted to
  a computed slot and its `publish_date: 2026-11-04` overwritten — mitigated
  by merging PR #11158 (which flips it to `scheduled`) before the next cron
  run; noted for the operator, not fixed here (out of scope).
- **Wednesday pins are legal.** The publisher has no weekday gate
  (`scripts/content-publisher.sh:884-896`); only auto-promotion constrains to
  Tue/Thu. PR #11158's Wed 11-04 pin is precedent. `2026-10-28` is the closest
  free day to the superseded 10-29 default.
- **Stale-flip hazard.** If the work runs after a pinned date passes, the
  publisher flips the file to `status: stale` at its next run — Phase 1's
  occupied-set re-check exists for exactly this slip.
- **No NFR/ADR impact** — no architectural decision, no new substrate, no
  store, no guard, no UI surface; every gate (2.7 GDPR, 2.8 IaC, 2.9
  observability, 2.10 ADR, 2.11 encryption, 2.12 guard-contract) scoped out:
  the diff is six two-line frontmatter edits in
  `knowledge-base/marketing/distribution-content/` plus `gh` issue ops.

## User-Brand Impact

- **If this lands broken, the user experiences:** a Soleur social post (X
  thread, Bluesky, LinkedIn Personal, Discord) shipping on the wrong day —
  or a stale flip that silently un-schedules it — on the public brand
  channels.
- **If this leaks, the user's [data / workflow / money] is exposed via:**
  no private data is touched; the only public vector is a social post going
  out at an unintended time (correctable by deletion/repost).
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the blast radius is six lines of
  frontmatter and issue comments; the worst live outcome is a mistimed social
  post on owned channels, which is correctable and touches no user data,
  money, or production surface.

## Open Code-Review Overlap

Checked `gh issue list --label code-review --state open` (2026-10-26) against
every planned file path — **no open scope-out touches the six edited files.**
Two issues matched the *directory/calendar* strings only:

- #10240 "review: campaign calendar refresh on PR 10140" — **acknowledge**:
  concerns calendar refresh mechanics, not these drafts; calendar is left to
  the cron.
- #3649 "marketing: PR-A2 #3603 content brief — schedule for PR-C merge" —
  **acknowledge**: a stale 2026-era scope-out unrelated to this arc.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Epic #10902 — verify every child brief is closed and its synthesis post is the published hub; close the epic with a completion comment if so." | Phase 1 re-verify + Phase 3 #10902 close; AC1 | mapped |
| 2 | "#11078 — OPEN decision-challenge on the 2026-10-29 publish date for the prior PBT-methodology spoke's distribution draft … resolve it — the content-promotion cron will auto-slot, or operator may want explicit re-slotting." | Phase 2 property-test pin + Phase 3 #11078 comment+close; AC2 | mapped |
| 3 | "#10736 (citation-scope question on the feature-map post) is OPEN — check whether its resolution requires any post or doc change." | Phase 3 #10736 evidence comment; AC3 | mapped |
| 4 | "Six distribution drafts sit at status:draft (5 new arc spokes + the prior property-test post): confirm the content-promotion Inngest cron promotes them to free Tue/Thu slots, or flip to scheduled with publish_date if immediate release is wanted." | Phase 2 six pins (the flip arm — auto-slot verified but produces wrong slots); AC5, AC8 | mapped |
| 5 | "aware but out of scope; avoid file or slot conflicts with it" [re: PR 11158] | P4 guard — the two 11-04 files excluded from every phase; AC6 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Phase 1 verification pass | "verify every child brief is closed and its synthesis post is the published hub" | asked |
| Phase 2 six frontmatter pins | "flip to scheduled with publish_date if immediate release is wanted" | asked |
| Phase 3 #10902 close | "close the epic with a completion comment if so" | asked |
| Phase 3 #11078 comment+close | "resolve it" | asked |
| Phase 3 #10736 comment | "check whether its resolution requires any post or doc change" | asked |
| Phase 3 #11003 comment+close | — | inferred — justification: identical stale-premise class as asked item #11078 (recorded default 10-27 falsified by shipped 10-29); leaving it open rots the action-required backlog the sweeper exists to prevent |
| `decision-challenges.md` + `tasks.md` artifacts | — | inferred — justification: pipeline contract requires the `| Item \| Class \| Ruling \|` table persisted under `specs/<branch>/` and the skill requires tasks.md |
| Property-test pin date 2026-10-28 | "or flip to scheduled with publish_date if immediate release is wanted" | asked — the *date choice itself* is a recorded operator(schedule) default, filed as a decision-challenges row |

### Split Assessment

- Subsystems touched: 1 — `knowledge-base` (issue ops are not file changes)
- Planned files: 8 (6 distribution edits + tasks.md + decision-challenges.md) | Estimated changed lines: ~80
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1 — `gh issue view 10902 --json state` → `CLOSED`, and its newest
  comment names: the five closed child briefs (#10636 #10694 #10730 #10737
  #10739), closed epic #10397, the hub post published 2026-10-24, and the
  verified seven spoke links.
- [ ] AC2 — `gh issue view 11078 --json state` → `CLOSED`; its closing comment
  records that the post shipped with `date: 2026-10-29`, that the distribution
  slot was occupied by the guardrails spoke's scheduled 10-29, and that the
  draft's slot resolved to the explicit pin `2026-10-28`.
- [ ] AC3 — `gh issue view 10736` stays `OPEN` and carries a new comment
  documenting the roster-free verification (zero `ux-audit` /
  `reproduce-bug` / `consumer` matches in the spoke post + draft) citing the
  2026-10-25 CTO ruling.
- [ ] AC4 — `gh issue view 11003 --json state` → `CLOSED`; comment records the
  shipped slot (scheduled 2026-10-29) superseding the recorded 2026-10-27
  default.
- [ ] AC5 — All six files carry `status: scheduled` and the pinned
  `publish_date:` values from the Phase 2 table (unquoted, corpus
  convention); `bash scripts/lint-distribution-content.sh` exits 0 for each;
  `bun test plugins/soleur/test/distribution-content-format.test.ts` is green.
- [ ] AC6 — `git diff --quiet origin/main...HEAD --`
  `knowledge-base/marketing/distribution-content/2026-11-04-six-questions-before-recurring-job.md`,
  `plugins/soleur/docs/blog/2026-11-04-before-your-ai-team-takes-a-recurring-job.md`,
  `knowledge-base/marketing/campaign-calendar.md` → clean (merge-base form —
  a sibling merge touching those paths must not red it).
- [x] AC7 — Each pinned `publish_date` appears exactly once across
  `knowledge-base/marketing/distribution-content/` (pre-existing published-corpus
  duplicate dates — 2026-03-21, 2026-04-21, 2026-06-15 — are historical and
  excepted; re-run the per-date count check after edits: six pins, one each).
- [ ] AC8 —
  `knowledge-base/project/specs/feat-one-shot-10902-agentic-verification-epilogue/{tasks.md,decision-challenges.md}`
  committed; the property-test row's ruling names the shipped date.
- [ ] AC9 — If the work executes after 2026-10-28, the property-test pin is
  moved to the next free day (occupied-set re-check) and the
  decision-challenges row updated in the same commit.

## Domain Review

**Domains relevant:** marketing

### Marketing

**Status:** reviewed (inline self-assessment — no agent-spawn capability in
this subagent context; recorded as a decision-challenges row, matching the
sibling-spec convention)

**Assessment:** Scheduling mechanics only — no copy is authored or edited, so
no brand-voice surface exists for CMO review. The content itself passed the
content PRs' own reviews. The marketing-relevant judgment (slot dates) is
`operator (schedule)` class and is filed as a decision-challenge, not silently
taken.

No Product/UX Gate subsection — no file in `## Files to Edit`/`Create`
matches the UI-surface term list; tier is NONE.

## Test Scenarios

All scenarios are verification-level (integration — live `gh` + filesystem
assertions); there is no unit-test surface in a frontmatter-only diff.

- Given all five child briefs CLOSED at verify time, when the close-out runs,
  then #10902 closes with the evidence comment; given any child reopened,
  then the close-out aborts and the plan's AC1 fails loudly.
- Given the six pinned dates re-checked free at work time, when the edits
  land, then each file's `status`/`publish_date` lines equal the Phase 2
  table and the occupied-set grep shows each date exactly once.
- Given a pinned date that slips into the past before the cron run, when the
  publisher next executes, then the file flips `scheduled`→`stale` — covered
  by AC9's date re-check before commit.
- **Verification commands:**
  - `for i in 10397 10636 10694 10730 10737 10739; do gh issue view $i --json state --jq .state; done` → all `CLOSED`
  - `grep -c 'blog/' plugins/soleur/docs/blog/2026-10-23-agentic-verification-checklist-shipped.md` ≥ 7
  - `for d in 2026-10-28 2026-11-03 2026-11-05 2026-11-10 2026-11-12 2026-11-17; do grep -h '^publish_date:' knowledge-base/marketing/distribution-content/*.md | grep -c "publish_date: $d\$"; done` → six lines of `1` (no double-booked slot; a whole-corpus `uniq -d` is both vacuous under `-H` and false-positive on pre-existing published dupes)
  - `bash scripts/lint-distribution-content.sh knowledge-base/marketing/distribution-content/<file>` ×6 → exit 0
  - `bun test plugins/soleur/test/distribution-content-format.test.ts` → pass

## Success Metrics

- #10902, #11078, #11003 closed with evidence-bearing comments; #10736 open
  with the roster-free finding attached.
- On each pinned date the daily publisher posts the draft to its four
  channels and flips it `scheduled`→`published` with no manual step.
- No arc spoke's distribution date deviates from the slot decisions recorded
  in the arc-spokes spec.

## Dependencies & Risks

- **Cron race:** if `cron-content-publisher`'s bot-PR lands before this PR
  merges, a file may already be `status: scheduled` with a computed date —
  the pin edit still applies (targeted line rewrite). Risk: the operator
  sees a transient cron-PR; mitigation is this PR's earlier merge.
- **PR #11158 interaction:** unmerged, `six-questions` stays a ready draft
  and the cron will re-slot it (overwriting `publish_date: 2026-11-04`).
  Not ours to fix; flagged for the operator — merge order should put #11158
  ahead of the next cron run.
- **Date slip:** if execution is delayed past 2026-10-28 the property-test
  pin stales — AC9 covers re-picking.
- **#10902 re-close premise:** if a child brief reopened between plan and
  work, Phase 1 aborts rather than closing on stale evidence.

## References & Research

- Promotion mechanics: `apps/web-platform/server/inngest/functions/content-promotion.ts`
  (`planPromotions` :236, `applyPromotion` :271, `isReadyDraft` :181,
  `HORIZON_DAYS` :26, `PROMOTION_WEEKDAYS` :29);
  `apps/web-platform/server/inngest/functions/cron-content-publisher.ts`
  (occupied-set :281-292, bot-PR write path);
  `scripts/content-publisher.sh:861-896` (publish/stale conditions).
- Redirect pairs: `apps/web-platform/infra/seo-bulk-redirects.tf:96-104`.
- Prior rulings: `knowledge-base/project/specs/archive/20261025-214638-feat-one-shot-10902-arc-spokes/decision-challenges.md`
  (consumer-roster-free CTO ruling, slot defaults, narrative ordering);
  `knowledge-base/project/specs/archive/20261025-150240-feat-one-shot-10904-pbt-methodology/decision-challenges.md`
  (the 10-29 default #11078 challenges).
- Learning: `knowledge-base/project/learnings/workflow-patterns/2026-10-25-rebase-continue-editor-hang-orphan-hooks.md`.
- Related PRs: #11108 (five spokes, merged), #11067 (PBT spoke, merged),
  #11158 (six-questions schedule — boundary file, do not touch).
- Related issues: #10902 (closes), #11078, #11003, #10736, #10397,
  #10636 #10694 #10730 #10737 #10739.

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Leave all six at `status: draft`; let the cron auto-slot | Rejected — filename-order slotting lands every spoke one slot late (property-test eats 11-03) and re-slots six-questions if #11158 is unmerged; wrong vs recorded slot defaults |
| Pin property-test to 2026-11-19 (next free Tue/Thu) | Rejected as default — keeps the weekday convention but pushes the arc's most time-pegged spoke ~3.5 weeks past its live post; recorded as the fallback in the decision-challenge |
| Hand-edit `campaign-calendar.md` rows to `scheduled` | Rejected — the file is auto-generated by `cron-campaign-calendar`; hand edits drift |
| Close #10736 alongside the finding comment | Rejected — the keep/revert scope decision is `operator (scope)`; out of mandate |

## Enhancement Summary

**Deepened on:** 2026-10-26 (inline — no agent-spawn capability in this
subagent context; the fan-out phases 2–5 were covered by the verified source
reads in `## Research Insights` and the carried-forward CTO ruling of
2026-10-25 recorded in `decision-challenges.md`).

### Key Improvements

- Slot simulation against `content-promotion.ts` proved the cron's
  filename-ordered auto-slot lands every arc spoke one slot late and would
  overwrite `six-questions`' hand-set date if PR #11158 lags — the basis for
  the pin-all-six design.
- Premise validation caught two stale premises: #10902 is the synthesis
  brief (parent epic #10397 already CLOSED), and #11078's recorded default
  split into a post-date half (held) and a distribution-slot half
  (falsified by the guardrails spoke's scheduled 10-29).
- Sharp-edges pass applied: AC6 rewritten to merge-base diff form
  (`origin/main...HEAD`); every prescribed verification command executed at
  plan time (`lint-distribution-content.sh` ×6 exit 0;
  `distribution-content-format.test.ts` 48/48 pass); `decision-challenges.md`
  re-formed to satisfy `technical-ruling-gate.sh` (the `pending - assumed`
  row replaced by the carried-forward `Ruled by CTO agent, 2026-10-25:` cell);
  markdownlint clean on all three artifacts.
- Gate verdicts (deepen-plan 4.5–4.13): Scope Check 1 unfenced section,
  no `unmapped`, no `BLOCKED`, `Recommendation:` present — pass;
  User-Brand Impact present with threshold `none` + decision sentence — pass;
  Observability/Encryption/Guard-Contract/Task-Design/UI-wireframe/
  PAT/network-outage/downtime gates — not triggered (frontmatter-only diff,
  no code/infra/UI/guard surface).
