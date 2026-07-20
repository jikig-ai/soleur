---
title: "Cron-liveness cohort audit — asserted vs consumed artifact"
date: 2026-07-20
type: audit
issue: 6737
adr: ADR-126
status: complete
last_updated: 2026-07-20
---

# Cron-liveness cohort audit (#6737)

ADR-126 closed the blind spot for one cron and recorded the cohort implication as out of scope:
it "deliberately does not widen to the cohort; **#6737 audits** each producer's asserted-vs-consumed
artifact against this decision." This is that audit. **It is audit-only — no handler is edited here.**

Every citation below is a **content anchor** (`cq-cite-content-anchor-not-line-number`): a literal
string present in the named file, not a line number that drifts on the next edit.

---

## Headline finding

**On the axis ADR-126 defines, the answer is not "N of 8 need no change" — it is 0 of 8.**
All eight `MIGRATED_PROMPT` crons gate their Sentry check-in colour on the same issue-based
predicate (`resolveOutputAwareOk`), and **seven of the eight discard `safeCommitAndPr`'s return
value entirely**. Only `cron-community-monitor` assigns it — anchor
`const commitResult = await step.run("safe-commit-pr"` — which is the ADR-126 fix itself. The other
seven share the anchor `await step.run("safe-commit-pr", async () =>` with no binding, so a
`{status:"failed"}` or `{status:"no-changes"}` is structurally unreadable by the handler that
produced it.

**But the more useful finding is the one that survives correction.** Measured from outside the
handlers, **8 of the 9 committed-file producers have not landed their artifact on the default branch
within a threshold derived from their own schedule**, and the single exception is
`cron-roadmap-review` — the producer the issue does not enumerate at all.

```
PRODUCER                         CADENCE        CLASS AGE     THRESHOLD VERDICT
cron-seo-aeo-audit               0 11 * * 1     B     54      22d       STALE
cron-content-generator           0 10 * * 2,4   A     40      9d        STALE
cron-growth-execution            0 10 1,15 * *  B     109     46d       STALE
cron-campaign-calendar           0 16 * * 1     A     55      15d       STALE
cron-growth-audit                0 7 * * 1      A     55      15d       STALE
cron-community-monitor           0 8 * * *      A     42      3d        STALE
cron-competitive-analysis        0 9 1 * *      B     89      75d       STALE
cron-architecture-diagram-sync   0 2 * * 0      B     NEVER   22d       STALE
cron-roadmap-review              0 9 * * 1      B     13      22d       PASS
```

Reproduce with `bash scripts/cron-artifact-age.sh --all`. No SSH, no credential, no dashboard.

> **Reading the AGE column.** The script floors to elapsed 24-hour periods from the commit
> timestamp, so it reads **up to one lower** than the calendar-day differences used in the tables
> below (e.g. 54 elapsed vs 55 calendar days for `cron-seo-aeo-audit`). The distinction is immaterial
> to every verdict here — no producer is within a day of its threshold — but it is stated so the two
> sets of numbers are not read as a contradiction.

---

## Correction to this plan's own R22c — the confounder is 5 days, not a season

The plan's retraction table states that `TIER2_DEFERRED_CRONS` "held **6** of the 8 until emptied in
commit `5ea440f4c` on 2026-06-13", and that "every R22(a) date falls in or before that window."
Verified against the diffs, **both halves need correcting, and the correction cuts against the
retraction**:

| Claim | Verified reality |
|---|---|
| "held 6 of the 8" | **7 of the 8.** At `d79e60209` the set held `campaign-calendar`, `community-monitor`, `competitive-analysis`, `content-generator`, `growth-audit`, `growth-execution`, `seo-aeo-audit`. Only `cron-architecture-diagram-sync` was never deferred. |
| "held … until emptied 2026-06-13" | The set was **introduced** at `a48c57e8d` on **2026-06-08** and emptied at `5ea440f4c` on **2026-06-13**. The defer window is **5 days wide**, not open-ended. |
| "every R22(a) date falls in or before that window" | Literally true, but it does not carry the inference drawn from it. Dates **before 2026-06-08 predate the defer entirely** — they cannot be confounded by a mechanism that did not yet exist. |

So the defer explains **at most 5 days** of any producer's darkness. The subtraction, per producer:

| Producer | Dark span to 2026-07-20 | Explained by the Tier-2 defer | **Unexplained** |
|---|---|---|---|
| `cron-growth-execution` | 110d | 5d | **105d** |
| `cron-competitive-analysis` | 90d | 5d | **85d** |
| `cron-campaign-calendar` | 56d | 5d | **51d** |
| `cron-growth-audit` | 56d | 5d | **51d** |
| `cron-seo-aeo-audit` | 55d | 5d | **50d** |
| `cron-community-monitor` | 42d | 5d | **37d** |
| `cron-content-generator` | 41d | 4d | **37d** |
| `cron-architecture-diagram-sync` | never produced | 0d (never deferred) | **entire lifetime** |
| `cron-roadmap-review` | 14d | 0d (never deferred) | within threshold |

**The retraction was right to demand the subtraction and wrong about its size.** R22's underlying
finding survives it almost intact. During the defer window `deferIfTier2Cron` did post `ok:true`
after skipping the spawn — anchor `await postSentryHeartbeat({ ok: true, sentryMonitorSlug` inside
`deferIfTier2Cron` — so those 5 days are genuinely uninterpretable. The remaining 37–105 days are not.

---

## Cadence discipline

Every age above is stated against its producer's **own** schedule, because a fixed observation
window is not evidence about a cron it does not contain a fire of. `cron-competitive-analysis` runs
`0 9 1 * *` — **monthly**. A 12-day window contains **zero** of its fires, so "nothing in 12 days"
says nothing whatsoever about it. This is why `scripts/cron-artifact-age.sh` derives each threshold
from the cron's own interval and never from a shared constant, and why the cadence column is printed
on every row of its output.

---

## Per-handler rows

`CONSUMED` is what the operator actually reads. `ASSERTED` is what the check-in colour is currently
gated on. The gap between those two columns is the entire defect ADR-126 names.

### Class A — deterministic (a healthy run always writes)

| # | Cron | Cadence | Content anchor (handler) | Operator CONSUMES | Check-in ASSERTS | Return value |
|---|---|---|---|---|---|---|
| 1 | `cron-community-monitor` | `0 8 * * *` daily | `export const COMMUNITY_DIGEST_DIR = "knowledge-base/support/community/";` | committed `<date>-digest.md` | **artifact** (ADR-126 fix applied) | **consumed** — `const commitResult = await step.run("safe-commit-pr"` |
| 2 | `cron-campaign-calendar` | `0 16 * * 1` weekly | `const CAMPAIGN_CALENDAR_ALLOWED_PATHS = [` | `campaign-calendar.md`, `content-strategy.md` | labelled **GitHub issue** | discarded |
| 3 | `cron-growth-audit` | `0 7 * * 1` weekly | `const GROWTH_AUDIT_ALLOWED_PATHS = [` | dated files under `audits/soleur-ai/` | labelled **GitHub issue** | discarded |
| 4 | `cron-content-generator` | `0 10 * * 2,4` 2×/wk | `const CONTENT_GENERATOR_ALLOWED_PATHS = [` | a new article under `docs/blog/` | labelled **GitHub issue** | discarded |

### Class B — change-conditional (a run may legitimately produce no diff)

| # | Cron | Cadence | Content anchor (handler) | Operator CONSUMES | Check-in ASSERTS | Return value |
|---|---|---|---|---|---|---|
| 5 | `cron-seo-aeo-audit` | `0 11 * * 1` weekly | `const SEO_AEO_ALLOWED_PATHS = ["plugins/soleur/docs/"] as const;` | refreshed docs pages | labelled **GitHub issue** | discarded |
| 6 | `cron-growth-execution` | `0 10 1,15 * *` 2×/mo | `const GROWTH_EXECUTION_ALLOWED_PATHS = [` | keyword-optimized pages | labelled **GitHub issue** | discarded |
| 7 | `cron-competitive-analysis` | `0 9 1 * *` monthly | `export const COMPETITIVE_ANALYSIS_ALLOWED_PATHS = [` | `competitive-intelligence.md` + 4 siblings | labelled **GitHub issue** | discarded |
| 8 | `cron-architecture-diagram-sync` | `0 2 * * 0` weekly | `commitMessage: "docs(arch): weekly architecture diagram sync",` | `.c4` files under `diagrams/` | labelled **GitHub issue** | discarded |

All seven discarding handlers share the gate anchor `if (heartbeatOk && !spawnResult.abortedByTimeout) {`
immediately above `await step.run("safe-commit-pr", async () =>`.

**A naive "must commit every run" rule would false-RED all four Class B rows** — which is why the
detector's remedy is a *threshold*, not a per-run assertion. The mechanism is identical across both
classes; only the number of intervals before a verdict differs.

---

## The two independent freshness producers

Column **(a)** is cron self-authorship: the last commit on `origin/main` whose message matches the
cron's own `commitMessage:` literal. Column **(b)** is the artifact's `last_updated` frontmatter —
written by whoever last refreshed the artifact, by any path. These are genuinely independent: (a) is
a property of the *producer*, (b) is a property of the *artifact*.

| Cron | (a) self-authored | (b) frontmatter `last_updated` | Agree? |
|---|---|---|---|
| `cron-campaign-calendar` | 2026-05-25 (56d) | `campaign-calendar.md` 2026-05-25 (56d) | **agree** |
| `cron-growth-audit` | 2026-05-25 (56d) | latest dated audit 2026-05-25 (56d) | **agree** |
| `cron-community-monitor` | 2026-06-08 (42d) | latest dated digest 2026-06-08 (42d) | **agree** |
| `cron-roadmap-review` | 2026-07-06 (14d) | `roadmap.md` 2026-07-06 (14d) | **agree** |
| `cron-content-generator` | 2026-06-09 (41d) | `seo-refresh-queue.md` 2026-06-08 (42d) | **agree** |
| `cron-competitive-analysis` | 2026-04-21 (90d) | `competitive-intelligence.md` **2026-07-04 (16d)** | **DISAGREE — 74 days apart** |
| `cron-growth-execution` | 2026-04-01 (110d) | `seo-refresh-queue.md` 2026-06-08 (42d) | **DISAGREE — 68 days apart** |
| `cron-seo-aeo-audit` | 2026-05-26 (55d) | *artifact has no frontmatter* (Eleventy docs pages) | **not comparable** |
| `cron-architecture-diagram-sync` | **NEVER** | *artifact has no frontmatter* (`.c4` sources) | **not comparable** |

### Rows where the two producers disagree — named, as required

1. **`cron-competitive-analysis` — 90d self-authored vs 16d frontmatter.** The artifact **is** fresh.
   `competitive-intelligence.md` carries `last_updated: 2026-07-04`, and its last commit is a human
   PR, not the cron. The cron has been dark for three monthly fires while its artifact stayed
   current **via another path**. A single-producer staleness check reading only (b) would have called
   this healthy; one reading only (a) would have called the artifact stale when it is not. **Both
   readings are wrong alone.** This row alone justifies carrying two columns.

2. **`cron-growth-execution` — 110d self-authored vs 42d frontmatter.** Same shape, weaker: the
   artifact was last refreshed by `cron-content-generator`'s 2026-06-09 run, not by
   `growth-execution`, which has not landed anything since 2026-04-01.

3. **`cron-seo-aeo-audit` and `cron-architecture-diagram-sync` — not comparable, and that is itself a
   finding.** Neither artifact carries `last_updated` frontmatter, so producer (b) does not exist for
   them. **They have exactly one freshness producer, and it is the one the handler cannot see.**
   Their `plugins/soleur/docs/` and `diagrams/` paths were touched 3 and 1 days ago respectively — by
   humans. Any path-mtime probe would report both as fresh while
   `cron-architecture-diagram-sync` has *never once* landed an artifact.

**The general lesson:** cron self-authorship and artifact currency are different questions, and on 2
of 9 rows they differ by more than two months. Any staleness claim that cites one producer is
unfalsifiable by construction.

---

## The four gaps the issue does not enumerate

### 1. `cron-roadmap-review` is a 9th site, reachable by no handler-local remedy

The issue scopes the cohort to the 8 `MIGRATED_PROMPT` files enumerated in
`cron-safe-commit-parity.test.ts`. `cron-roadmap-review` commits to
`knowledge-base/product/roadmap.md` on a weekly `0 9 * * 1` schedule and has the identical
consumed-artifact exposure — but it is **outside** `MIGRATED_PROMPT`, classified in the parity test's
`EXEMPT` map with the anchor `"cron-roadmap-review.ts": "hook-guarded Tier-1 self-commit"`. It does
not call `safeCommitAndPr` at all, so **every remedy phrased in terms of that helper's return value
structurally cannot reach it**.

It is also, at 14 days, the **only producer currently passing**. A cohort remedy scoped to
`MIGRATED_PROMPT` would have fixed the eight that are dark by a mechanism that excludes the one that
works — and would never have discovered that inversion, because it would never have measured it.
`scripts/cron-artifact-age.sh` enumerates **producers**, not handler shapes, and so covers 9/9.

### 2. Opened but never merged — PR #5026

`cron-seo-aeo-audit` opened PR **#5026** ("fix(seo): weekly SEO/AEO audit fixes 2026-06-08", head
`ci/seo-aeo-audit-2026-06-08-113158`). Verified live: **state `CLOSED`, `mergedAt: null`**. It was
never merged.

This is a GREEN-with-no-artifact path that ADR-126 does not enumerate and that **three** plausible
checks all miss: the issue-based predicate (the issue landed), a return-value read
(`safeCommitAndPr` genuinely committed and opened a PR — it returned success), and a naive `paths`
check (the paths were real). The commit happened; it happened on a branch that never landed. **Only
a default-branch check catches it**, which is why the detector measures `origin/main` and not the
handler's own report of what it pushed.

Note the class interaction: #5026 is a **Class B** instance, and the change-conditional producers are
exactly the ones where a missing artifact is hardest to distinguish from a legitimate no-op.

### 3. Propagation, not blindness — and the healthy neighbour that masks it

The intelligence arrived; the crons that *walk* it are dark. `competitive-intelligence.md` is 16 days
fresh while the four downstream producers that consume it have not landed anything in 50–105 days.

This is made materially harder to see by a **healthy neighbour**: `knowledge-base/marketing/` shows
commits 4 days old, which look like the marketing crons working. They are not.
Those commits are `cron-content-publisher`'s — anchor `ci: promote review-ready drafts + update
content distribution status` — a cron that is **not in this cohort** and never stopped. The
distribution arm is healthy and is publishing an increasingly stale queue; the *generation* arm is
dark. **Uniform silence would have been noticed sooner.** A partially-healthy subsystem is more
dangerous than a wholly dead one, because every coarse freshness probe reads the living half.

Consequences already accrued and **not** recoverable by fixing the crons: `content-strategy.md` has
missed 6 weekly cycles, `campaign-calendar.md` is 56 days stale, and article output is zero for 35
days. Indexation age is monotonic — those are permanently lost indexable assets, not deferred ones.

### 4. The corrected marker reality — the delta is monitor COLOUR, not silence

An earlier draft of this work asserted that seven of the eight crons "emit nothing at all" on a
failed persistence, and proposed adding handler-side `emitCronPersistResult` calls. **That is
falsified by the code, and acting on it would have made things worse.**

`safeCommitAndPr`'s failure path already calls `reportSilentFallback`, already comments
*"PR withheld: safe-commit failed at stage …"* onto the operator's issue, and already calls
`emitCronPersistResult`. Critically, **that emitter is invoked from inside the shared helper on all
three status paths, with zero handler-side call sites.** Adding a handler-side call would
**double-emit** and would make any emitter-count guard vacuous.

So the real delta is narrower and more precise than "the cohort is silent": the markers fire, the
issue gets its comment — **but the Sentry monitor still shows GREEN**, because the colour is gated on
the issue predicate rather than on the artifact. The operator-facing defect is a **wrong colour on a
monitor**, not an absence of telemetry. That is a much smaller claim, and it is the true one.

> **Do not add handler-side `emitCronPersistResult`.** Recorded here because the correction is the
> kind that quietly reverts.

---

## What this audit does NOT do

- **No handler is edited.** ADR-126 scoped #6737 to an audit and explicitly declined the cohort
  decision. Widening needs its own ADR or an ADR-126 amendment, because it carries an accepted
  negative — a trailing persistence throw posts RED where it was GREEN (#5728) — that must be
  recorded before being applied to seven more handlers.
- **No new `action-required` issue is filed.** #4375 (*"competitive-analysis … has not fired in 36
  days"*) has been open with that label since 2026-05-24, in a queue 28 items deep whose oldest entry
  is from 2026-03-12. This exact finding was already escalated through this exact channel and
  broadened while the issue sat. Filing a 29th is an append, not an escalation. The right action is
  to **reconcile with #4375** now that a defer-corrected diagnosis exists.

## Deferred, and why each needs its own ADR

Handler-local `livenessOk`; Class A ports; the `retryEligible` sweep; and the `inngest -> kb` C4
edge. Tracked separately.

One ordering constraint is load-bearing enough to restate here: **`retryEligible: false` must land
BEFORE return-value consumption, never beside it.** Per the anchor
`const failed = threw && !heartbeatOk && retryEligible !== false;`, lowering `heartbeatOk` on a run
that *also* throws returns `{retry:true}` — Inngest replays the function and **re-spawns the Claude
agent**, costing API spend and risking duplicate artifacts. Omitting the flag is inert; passing
`false` suppresses the retry. It is a **prerequisite**, not a peer.
