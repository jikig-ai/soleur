---
title: "Self-healing content promotion + starvation alert + loud Sentry heartbeat"
type: fix
date: 2026-07-05
lane: cross-domain
brand_survival_threshold: aggregate pattern
status: draft
closes:
  - 2756
  - 4861
branch: feat-one-shot-content-publisher-starvation-alert
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# 🐛 Fix: Social content silently stopped auto-posting for ~3 weeks — self-heal + make the silence loud

## Enhancement Summary

**Deepened on:** 2026-07-05
**Review agents:** architecture-strategist, code-simplicity-reviewer, silent-failure-hunter, spec-flow-analyzer, observability-coverage-reviewer + verify-the-negative / precedent greps. All deepen-plan gates passed (User-Brand Impact, Observability 5-field, PAT-shape, UI-wireframe; network-outage/downtime not triggered).

### Key improvements applied
1. **Starvation now fires on an empty/NaN published baseline** (silent-failure F1 / spec-flow P2) — the naive `daysSincePublish >= N` silently skipped the exact cold/all-draft drought this plan targets (`NaN >= 10` is `false`). Predicate rewritten to treat undefined/non-finite `daysSincePublish` (with 0 scheduled) as starved.
2. **Phase 4 (credential-skip) deferred with corrected root cause** (silent-failure F2 / simplicity S2) — the original all-channels-skipped premise was dead-on-arrival: skip paths `return 0` are scored as `file_successes++` and the file flips to `published` while posted nowhere. Re-scoped to a sentinel-return follow-up issue; symptom already covered by the starvation alert.
3. **Per-draft `draft-gate-failed` signal** (spec-flow P0) — closes the malformed-draft dead-end where a gate-failing draft was invisible whenever ≥1 other draft was schedulable.
4. **starvation-check failure-isolated** (architecture A-P1b / silent-failure F3) — an Octokit issue-create throw must never flip the heartbeat to `ok:false` (false cron-DOWN); wrapped + `reportSilentFallback`.
5. **Replay-safety justification corrected** (architecture A-P1a) — memoized `setup-workspace` + `finally` teardown means a retry has NO workspace; the real invariant is atomic single-step commit + fresh-daily-clone + fail-loud.
6. **Step order pinned** — `promote-drafts` before `pre-check-stale-content` (metric correctness), `starvation-check` after `safe-commit-pr` (post-publish state).
7. **#4861 verification command corrected** (observability O-P1) — uses `SENTRY_IAC_AUTH_TOKEN` + `de.sentry.io` (the RO issues token lacks monitor scope), citing `cloud-scheduled-tasks.md:650`.
8. **Simplifications** — cut `BACKLOG_THRESHOLD`; single corpus scan shared between promote + starvation; `occupied` widened to any dated file (parked double-book fix); starvation auto-close on recovery.

### New considerations discovered
- The publisher already skips empty mapped sections at post-time, so an all-empty-section file posts nothing yet still flips to `published` — the readiness gate (≥1 non-empty section) is load-bearing to avoid scheduling silent-nothing files.
- "Schedule the 18-draft backlog on run-1" is not literally achievable (2 slots/week); backlog reaches steady-state ~8-10 pending, which IS the intended cadence buffer — reframed from "drain" to "posting resumes."

## Overview

Social distribution silently stopped on **2026-06-15**. The daily Inngest cron
`cron-content-publisher` (14:00 UTC) has completed **green every day since** — it
is not down, it simply has nothing to post: of 43 files in
`knowledge-base/marketing/distribution-content/`, **0 are `status: scheduled`**
(20 published, 18 draft, 4 stale, 1 parked). Every file generated from 2026-06-16
onward is `status: draft` with `publish_date: ""`. The `draft → scheduled`
promotion is a manual CMO/operator step (documented in `content-strategy.md`,
enforced nowhere in code) that stalled (open issue **#2756**).

Nothing alerted because a run with **nothing scheduled is a SUCCESS** — the
publisher posts an `ok` Sentry heartbeat on no-changes runs, so the monitor stays
green. There is no "0 content published for N days" (starvation) signal, so
**absence of posting looks identical to a healthy day**. A parallel gap (#4861)
is that the raw Sentry cron heartbeat *itself* fails silently when its env is
unset/malformed (`postSentryHeartbeat` logs at `info`/`warn` and returns — pages
nowhere).

This plan ships three things, plus one bounded secondary fix:

1. **Automated `draft → scheduled` promotion** (folded into the existing
   publisher cron): every daily run assigns review-ready drafts to upcoming
   Tue/Thu slots and flips `draft → scheduled`, so the schedule self-heals and
   posting resumes without hand-editing frontmatter. Resolves the manual gap
   behind **#2756**.
2. **Content-starvation alert**: after promotion, if the schedule is *still*
   empty and the last post is older than N days, fire a loud
   `reportSilentFallback` (Sentry) **and** a dedup `action-required` GitHub issue.
   Absence of posting stops looking like a healthy day.
3. **Make the Sentry heartbeat's silent-skip loud** (`postSentryHeartbeat`):
   route the unset/malformed-env branches through `warnSilentFallback` (which
   uses `SENTRY_DSN` — a *different*, populated var — via the SDK, not the raw
   ingest URL), so a blank/broken heartbeat env can never again be a silent
   `logger.info`. Verify check-ins actually land for `scheduled-content-publisher`
   and resolve **#4861**.
4. **Secondary**: `content-publisher.sh` per-channel credential skips `return 0`
   (silent success). When *every* declared channel for a file is credential-
   skipped, the file is neither published nor failed → stays `scheduled` and
   silently re-attempts forever. Surface it (dedup `action-required` issue).

**Architecture choice (default):** fold promotion + starvation into the existing
`cron-content-publisher` rather than add a new Inngest cron. The publisher already
clones the repo, scans the content dir, and commits via `safeCommitAndPr` daily;
promotion assigns *future* Tue/Thu `publish_date`s and the same run publishes any
that land on today. This adds **zero** new cron-registration surface (no
`cron-manifest.ts` entry, no new `sentry_cron_monitor`, no parity-test churn) —
the single largest simplicity win over a standalone `cron-content-promote`. The
standalone-cron alternative is named in *Alternatives Considered*.

## Premise Validation (Phase 0.6)

Checked every referenced artifact against live repo + prod state:

- **#2756 OPEN** (`gh issue view 2756`) — "follow-through: flip service-automation
  distribution-content status draft→scheduled". Premise HOLDS. This plan resolves
  the underlying manual gap.
- **#4861 OPEN** (`type/bug`, `bot-fix/attempted`) — "cron Sentry heartbeats not
  landing (scheduled-content-publisher monitor absent, siblings lastCheckIn=null)".
  Premise **PARTIALLY STALE** — see Research Reconciliation. The monitor resource
  now EXISTS (`cron-monitors.tf:752`, added in the 2026-06-11 backfill block), and
  the 3 heartbeat vars are present+valid in Doppler `prd` (verified below). The
  remaining live risk is a container-env-injection mismatch (Doppler-correct ≠
  container-has-it) — verify end-to-end, don't assume blank.
- **`cron-content-publisher.ts` / `scripts/content-publisher.sh`** — exist, read in
  full. Confirmed: publisher is daily `{ cron: "0 14 * * *" }` (`:400`), posts only
  `status: scheduled` + `publish_date == today`; per-channel skips `return 0`.
- **`scheduled_content_publisher` sentry_cron_monitor** — EXISTS `cron-monitors.tf:752`
  (`checkin_margin 30`, `max_runtime 15`). Deliverable 3 is verify-only, **no `.tf`
  edit**.
- **Doppler `prd` + `prd_terraform` heartbeat env** (read-only, format-validated at
  plan time, values NOT printed): `SENTRY_INGEST_DOMAIN` present len=37
  `SENTRY_DOMAIN_RE`✓; `SENTRY_PROJECT_ID` present len=16 `SENTRY_PROJECT_RE`✓;
  `SENTRY_PUBLIC_KEY` present len=32 `SENTRY_PUBLIC_KEY_RE`✓; `SENTRY_DSN` present.
  → **The "blank in prod" hypothesis is stale at the Doppler layer.** The durable
  code fix (loud silent-skip) stands regardless of current value state.
- **Tue/Thu cadence** — encoded in code at `cron-content-generator.ts:467`
  (`{ cron: "0 10 * * 2,4" }`) and `routine-metadata.ts:55`; the *slot-assignment*
  logic is prose-only in `content-strategy.md:309-321`. This plan adds the first
  code that computes "next available Tue/Thu slot."
- **No rejected-alternative ADR** — grepped
  `knowledge-base/engineering/architecture/decisions/` for content-promotion /
  starvation / auto-schedule mechanisms; none rejects the folded-cron approach.

## Research Reconciliation — Spec vs. Codebase

| Diagnosis claim | Reality (verified) | Plan response |
|---|---|---|
| "Sentry cron monitor `scheduled-content-publisher` absent" (#4861) | Monitor resource EXISTS `cron-monitors.tf:752` (2026-06-11 backfill) | No `.tf` edit; verify check-ins land, then close #4861 |
| "verify SENTRY_* are set in prod, not blank as in `.env.example`" | Present + regex-valid in Doppler `prd`/`prd_terraform` (len 37/16/32) | Reframe: Doppler is correct → verify the *container* env / that check-ins land (learning `sentry-dsn-missing-from-container-env-20260405`) |
| "publisher only posts `status: scheduled` + `publish_date == today`" | Confirmed `content-publisher.sh:800,812`; TS pre-check mirrors | Promotion assigns future Tue/Thu dates so the daily publisher picks them up |
| "18-draft backlog, all `draft` with empty `publish_date`" | Confirmed by scan; 1 file is `parked` (must NOT auto-schedule); 4 `stale` | Readiness gate = `draft` + channels + liquid-clean; excludes `parked`/`stale`; `parked` is the operator's per-draft hold lever |
| "draft→scheduled promotion is a manual step" | No code auto-promotes anywhere (grep clean); only the publisher mutates `scheduled→published/stale` | New `content-promotion.ts` lib is the first promotion code |

## User-Brand Impact

**If this lands broken, the user experiences:** either (a) the schedule stays
empty and the multi-week content drought silently continues (promotion no-ops),
or (b) an unreviewed/off-brand draft is auto-posted to public channels
(Discord/X/LinkedIn/Bluesky) under the Soleur brand.

**If this leaks, the user's data/workflow/money is exposed via:** N/A — no user
PII, auth, payments, or regulated data touched. Operator-owned marketing content
and cron-internal Octokit token only.

**Brand-survival threshold:** aggregate pattern. The harm is a *pattern* — a
cadence of missed or off-brand posts — not a single-user security/data incident.
Blast radius is bounded by the readiness gate (liquid-clean + channels present +
mapped sections non-empty), Tue/Thu spacing, the rolling horizon cap, and the
`status: parked` per-draft hold. The **auto-post-unreviewed-drafts** decision is a
genuine brand call routed to the CMO in Domain Review and recorded as a decision-
challenge for plan-review (the alternative: require an explicit `ready: true`
flag, or open a draft PR the operator merges).

_No sensitive-path files touched (no schema/auth/API-route/`.sql`), so no
`threshold: none` scope-out bullet and no CPO sign-off frontmatter required._

## Implementation Phases

### Phase 1 — Promotion library (pure, unit-tested first)

**Create `apps/web-platform/server/inngest/functions/content-promotion.ts`** —
pure functions, no I/O, fully unit-testable (write failing tests first,
`cq-write-failing-tests-before`):

- `parseContentFrontmatter(raw: string): { status?, publishDate?, channels: string[] }`
  — reuse the publisher's awk-equivalent semantics; robust against titles
  containing `:` (only read `status`/`publish_date`/`channels` lines, never split
  the whole block on `:` — learning `2026-04-28-awk-field-split-on-colon...`).
- `isReadyDraft(parsed, body): boolean` — `status === "draft"` AND `channels`
  non-empty AND body passes the Liquid-marker check (reuse the publisher's
  `validate_no_liquid_markers` contract / `scripts/lint-distribution-content.sh`
  exit-0 semantics) AND **at least one** declared channel has a non-empty mapped
  body section. Excludes `parked`/`stale`/`published`. **Mapped-section rationale
  (simplicity review S4):** the publisher already skips an empty mapped section at
  *post* time (`content-publisher.sh` `post_*` `return 0` with a "No X content
  found" warning, e.g. `:603,:699`), so a draft whose declared channels are *all*
  empty would post nothing yet still flip to `published` (see Phase 4 note / F2) —
  scheduling it is the silent-nothing trap. Requiring ≥1 non-empty section is the
  minimal load-bearing form (NOT "every" — a file may legitimately declare a
  channel whose section is still a stub while another is ready). The linter check
  is genuinely separate (`lint-distribution-content.sh` validates Liquid markers
  only, not section presence).
- `nextTueThuSlots(from: Date, occupied: Set<string>, horizonDays: number): string[]`
  — enumerate `YYYY-MM-DD` for weekday ∈ {Tue=2, Thu=4} from `from` **inclusive**
  through `from + horizonDays`, skipping any date in `occupied`. Deterministic,
  UTC-based (use `getUTCDay`).
- `planPromotions({ files, today, occupied, horizonDays }): { path, publishDate }[]`
  — take ready drafts in **deterministic order** (filename asc), assign each to
  the next free Tue/Thu slot; stop when slots within the horizon are exhausted.
  `occupied` = `publish_date` of every file with `status ∈ {scheduled, published,
  stale}` (never double-book, never reuse a burned date).
- `applyPromotion(raw: string, publishDate: string): string` — **targeted line
  replacement only**, NOT a gray-matter round-trip (learning
  `2026-05-25-tr9-pr6-gray-matter-yaml11-date-coercion-trap`): replace
  `^publish_date:.*$` → `publish_date: <YYYY-MM-DD>` (**unquoted**, matching the
  corpus convention `publish_date: 2026-05-14`) and `^status: draft$` →
  `status: scheduled`, preserving every other byte. **Idempotent**: a file already
  `scheduled` is a no-op (load-bearing for Inngest replay safety, learning
  `2026-06-14-inngest-...-consolidate-write-and-commit`).

Constants (tunable at deepen-plan): `HORIZON_DAYS = 28`, weekdays `[2, 4]`.

**Backlog-drain semantics (deepen-plan clarification).** With `HORIZON_DAYS = 28`
there are only ~8 Tue/Thu slots, so **run-1 schedules ~8 of the 18 drafts, not all
18** (verified: from 2026-07-05, the next-28-day Tue/Thu slots are
`2026-07-07, -09, -14, -16, -21, -23, -28, -30`). This is intentional — dumping 18
posts onto sequential dates would violate the documented 2-posts/week cadence. The
remaining 10 drain onto subsequent daily runs as the rolling window advances
(`occupied` grows as earlier promotions publish, freeing new horizon slots). This
satisfies the deliverable's "posting resumes" intent (the drought ends on run-1)
while honoring cadence. If the CMO instead wants the *entire* backlog assigned in
one pass (spanning ~9 weeks), drop the horizon cap — named in *Alternatives
Considered* as the CMO's call.

### Phase 2 — Wire promotion + starvation into the publisher

**Edit `apps/web-platform/server/inngest/functions/cron-content-publisher.ts`:**

**Step ordering (pinned — architecture review A-P2):** insert `promote-drafts`
**immediately after `setup-workspace`, BEFORE the existing `pre-check-stale-content`
step** — that step computes `HandlerResult.published = preCheck.scheduledToday`
(`:224,:357`), so it must see post-promotion disk state or a promoted-onto-today
draft undercounts. Promotion only assigns *future/today* dates, never past, so it
can never manufacture a stale entry — moving it earlier is safe. Insert
`starvation-check` **after `safe-commit-pr`** (post-publish disk state) so
`latestPublishedDate` reflects any same-run publish and the signal is deterministic.
Final order: `run-started-at → mint-token → setup-workspace → promote-drafts →
pre-check-stale-content → run-publisher-script → safe-commit-pr → starvation-check
→ sentry-heartbeat`.

- **`promote-drafts` `step.run`**: `readdir` the cloned content dir, parse
  frontmatter, `planPromotions(...)`, and `writeFile(applyPromotion(raw, date))` on
  disk in the ephemeral clone for each planned file. **Also compute and return the
  post-promotion scalars** the starvation-check needs, so the corpus is scanned +
  parsed **once** per run, not twice (simplicity review S3): return `{ promoted:
  [{file, publishDate}], latestPublishedDate, daysSincePublish, scheduledWithinHorizon,
  draftBacklog, gateFailedDrafts: string[] }` — all memoizable scalars (no
  filesystem-memoization trap). The existing `safe-commit-pr` step already stages
  `${CONTENT_DIR_REL}/` and commits both promotions and publish flips in one PR;
  **update the commit message** to name both mutations (e.g. `"ci: promote
  review-ready drafts + update content distribution status"`, A-P2c). A throw here
  (planPromotions / writeFile) propagates to the handler top-level catch →
  `reportSilentFallback` + `ok:false` heartbeat — **this is correct**: a promotion
  *persistence* failure IS a liveness failure and SHOULD red the cron (F5). Do NOT
  wrap it in a swallow "for symmetry" with starvation-check below.
- **Per-draft gate-failed signal (spec-flow P0 — closes the malformed-draft dead
  end):** during the scan, any file that is `status: draft` + non-empty `channels`
  but **fails** the readiness gate (Liquid markers, or no declared channel has a
  non-empty mapped section) is collected into `gateFailedDrafts`. This is
  **independent of `scheduledWithinHorizon`** — otherwise a malformed draft is
  invisible the instant one *other* draft is schedulable (re-instantiating the
  original silent-gap bug at per-draft granularity). Emit one **debounced**
  `warnSilentFallback` (`op: "draft-gate-failed"`, `extra: { files: gateFailedDrafts }`)
  when the list is non-empty; optionally roll into the starvation dedup issue body.
- **`starvation-check` `step.run`** (consumes `promote-drafts` return — no second
  scan). **Failure-isolated (architecture A-P1b / silent-failure F3 / observability
  P2):** wrap the whole body (`reportSilentFallback` + `ensureDedupIssue` Octokit
  call + recovery-close) in its own `try/catch`; on failure emit
  `reportSilentFallback(op:"starvation-check-failed")` and **return normally**. An
  Octokit hiccup must NEVER propagate to the handler top-level catch (which posts
  `ok:false` — a false cron-DOWN, the exact liveness/content conflation this plan
  forbids). Add an AC asserting a thrown Octokit error does not flip the heartbeat.
  - **Starvation predicate (silent-failure F1 / spec-flow P2 — the load-bearing
    fix):** `latestPublishedDate` can be **absent** (zero `published` files — the
    exact cold/all-draft state this plan targets) or **unparseable**. `NaN >= 10`
    is `false`, so a naive `daysSincePublish >= STARVATION_DAYS` **silently never
    fires on the worst drought.** Define instead:
    `starved = scheduledWithinHorizon === 0 && (latestPublishedDate === undefined
    || !Number.isFinite(daysSincePublish) || daysSincePublish >= STARVATION_DAYS)`.
    An unparseable `publish_date` on a `published` file is itself surfaced via
    `reportSilentFallback` (do not let it collapse to a false-negative). Precedent
    NaN guard: `verifyScheduledIssueCreated` throws on a NaN bound
    (`_cron-shared.ts:669-675`).
  - **Scan-failure vs empty (silent-failure F4):** the counts come from
    `promote-drafts`; if that step's scan threw, it fails loud (top-level catch),
    so starvation-check is only reached on a *successful* scan — do NOT re-derive
    counts from a swallow-all catch that would mask "scan threw" as "0 scheduled."
  - On `starved`: `reportSilentFallback(new Error("content starvation: 0 scheduled, N days since last post"), { feature: "cron-content-publisher", op: "content-starvation", tags: { starvation: "true" }, extra: { daysSincePublish, draftBacklog, latestPublishedDate } })` — loud, queryable Sentry issue via `SENTRY_DSN` — **plus** a dedup `action-required` GitHub issue.
  - **Dedup-issue helper (verified precedent):** `ensureScheduledAuditIssue`
    (`_cron-shared.ts:1160`, used by `cron-campaign-calendar.ts:387`) is
    **spawn-result-shaped** (claude-eval `SpawnResult`, date-suffixed title) — NOT a
    drop-in. Add a small sibling `ensureDedupIssue(client, { title, body, labels })`
    reusing its dedup mechanism **verbatim**: `GET /repos/{owner}/{repo}/issues` with
    `labels`, `sort: "created", direction: "desc", per_page: 10`, exact-title match
    before create (`_cron-shared.ts:1210-1219`). Title **stable across runs** (no
    date suffix — starvation is a standing condition) so a persisting drought files
    one issue, not one per day.
  - **Auto-close on recovery (spec-flow P1):** when `scheduledWithinHorizon > 0`
    (drought cleared), close any open starvation `action-required` issue
    (`PATCH /repos/{owner}/{repo}/issues/{n}` `state:closed` with a recovery comment)
    — otherwise the operator sees a stale alert with no code to resolve it. This
    close path is also inside the failure-isolated try/catch.
- Extend `HandlerResult` with `promoted?: number`, `starved?: boolean`. The
  `sentry-heartbeat` step stays `ok: true` — starvation is a **content** signal,
  not a cron-liveness signal (learning
  `2026-06-01-best-effort-cron-monitor-liveness-not-success`); the two must not be
  conflated.

**`occupied` set (spec-flow P2 — double-book fix):** `occupied` = `publish_date`
of **every file that carries a non-empty `publish_date`, regardless of status**
(scheduled/published/stale/parked/any). Scoping it to `{scheduled,published,stale}`
would let a `parked` file holding a future Tue/Thu date collide with a
freshly-assigned draft on the same day. `parked`/`stale`/`published` are still
excluded from *promotion* (only `status: draft` is promotable); they are included
only in the date-collision guard.

Constants: `STARVATION_DAYS = 10`. **`BACKLOG_THRESHOLD` cut** (simplicity review
S1 / spec-flow): the non-paging backlog-warn only fired when `scheduledWithinHorizon
=== 0 && draftBacklog >= 10 && daysSincePublish < 10` — a speculative "stuck
unready" hint the drought alert + the new per-draft `draft-gate-failed` signal both
supersede. Dropped.

### Phase 3 — Make the Sentry heartbeat silent-skip loud (#4861)

**Edit `apps/web-platform/server/inngest/functions/_cron-shared.ts`
`postSentryHeartbeat` (:294-308):**

- Unset-env branch (`!domain || !projectId || !publicKey`, currently
  `logger.info` + `return`) and malformed-env branch (currently `logger.warn` +
  `return`): replace the silent return with a **debounced** `warnSilentFallback`
  (routes via `SENTRY_DSN` / the `@sentry/nextjs` SDK — which is populated and is
  a *different* var from the three ingest vars, so it lands even when they are
  blank). Distinct ops: `op: "heartbeat-env-unset"` / `op: "heartbeat-env-malformed"`,
  `feature: "cron-sentry-heartbeat"`, `tags: { cron: cronName }`. Keep the early
  `return` (do not attempt the POST) — the change is *observability*, not control
  flow. `cq-silent-fallback-must-mirror-to-sentry`.
- **Debounce is load-bearing**: ~45 crons share this env; per-cron per-fire emit
  is noise. **Decision (deepen-plan, verified):** use `mirrorWarnWithDebounce`
  (`observability.ts:544-552`, 5-min TTL) keyed on `(op, cronName)`. Confirmed it is
  a pure in-process `tryClaim` guard that delegates to `warnSilentFallback` →
  `@sentry/nextjs` SDK (`SENTRY_DSN`, set via `sentry.server.config.ts:20`) — **no
  dependency on the 3 ingest vars and no raw-ingest-URL construction**, so the loud
  path lands even when the ingest vars are blank (silent-failure review confirmed
  CLEAN). Residual: in a total-blank env (ingest vars AND `SENTRY_DSN` unset) only
  the pino `logger.warn` → stdout survives — still strictly louder than today's
  `logger.info`; `SENTRY_DSN` is verified present in `prd`.

**No `.tf` change** — `scheduled_content_publisher` monitor already exists.

### Phase 4 — Secondary: DEFERRED to a follow-up issue (root cause re-scoped)

**Deferred out of this PR** (simplicity review S2 + silent-failure review F2). The
plan's original framing was **wrong** and would have shipped a dead no-op:

- Premise was "all-channels-skipped leaves `file_successes==0 && file_failures==0`
  → stays `scheduled`." **False.** In `content-publisher.sh` every credential/skip
  path `return 0` (Discord `:305`, X `:418`, LinkedIn `:596`, Bluesky `:687`), and
  the caller scores `return 0` as **success** → `file_successes++`
  (`:861/:873/:882/:889/:896`). With `file_successes > 0` the file is flipped to
  `status: published` (`:905`) — **marked published while posted nowhere.** The
  proposed `successes==0 && failures==0` branch is therefore essentially
  unreachable for a credential skip.
- **The real silent-success** is skip-scored-as-publish → `published`. Fixing it
  correctly requires the skip paths to return a **distinct sentinel** (not `0`) and
  the caller to count skips separately from real successes before deciding
  published/stuck — a bounded but genuinely orthogonal bash change in a different
  file/language from this PR's TS core.
- **Coverage in the interim:** the starvation alert (Phase 2) already catches the
  *symptom* — a file stuck un-posted keeps `daysSincePublish` climbing until the
  drought fires. So deferring loses no observability of the outcome.

**Action:** file a follow-up issue "content-publisher.sh: credential-skip `return 0`
is scored as a publish (file flipped to `published` while posted nowhere)" with the
sentinel-return re-scope and the `:861-905` citations, labeled `type/bug`,
`domain/marketing`. Re-eval criterion: fold into the next `content-publisher.sh`
change or when a real credential-skip-masks-publish incident is observed.

### Phase 5 — Document the automation

**Edit `knowledge-base/marketing/content-strategy.md`** "Publishing Cadence"
(:307-321) + "Overdue handling": replace the prose implying `draft → scheduled`
is a manual CMO step with the automated behavior (daily promotion onto Tue/Thu,
readiness gate, `status: parked` as the hold lever, starvation alert as the
backstop). Keeps the doc from lying about the system.

## Files to Edit
- `apps/web-platform/server/inngest/functions/cron-content-publisher.ts` — promote + starvation steps (new step order), result shape, commit-message update
- `apps/web-platform/server/inngest/functions/_cron-shared.ts` — loud heartbeat silent-skip + new `ensureDedupIssue` sibling helper
- `knowledge-base/marketing/content-strategy.md` — document automated promotion
- `apps/web-platform/test/server/inngest/cron-shared.test.ts` — heartbeat loud-skip assertions (if the suite exists; else new)

_(`scripts/content-publisher.sh` removed from scope — Phase 4 deferred to a follow-up issue, see Phase 4.)_

## Files to Create
- `apps/web-platform/server/inngest/functions/content-promotion.ts` — pure promotion lib
- `apps/web-platform/test/server/inngest/content-promotion.test.ts` — slot math, readiness gate, idempotent mutation, gray-matter-safe date write
- `apps/web-platform/test/server/inngest/content-starvation.test.ts` — starvation trigger + dedup-issue + heartbeat-stays-ok

**Explicitly NOT touched** (no new cron): `cron-manifest.ts`,
`sentry-monitor-iac-parity.test.ts`, `function-registry-count.test.ts`,
`cron-monitors.tf`. Folding into the existing publisher avoids all of them.

## Observability

```yaml
liveness_signal:
  what: existing scheduled_content_publisher Sentry cron monitor (end-of-run ok heartbeat)
  cadence: daily 14:00 UTC
  alert_target: Sentry Crons — missed check-in opens an issue (failure_issue_threshold=1)
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf:752 (UNCHANGED — verify-only)
error_reporting:
  destination: Sentry via reportSilentFallback / warnSilentFallback (SENTRY_DSN SDK path) + dedup action-required GitHub issue
  fail_loud: true
failure_modes:
  - mode: content starvation (0 scheduled after promotion, N days since last post, INCLUDING no-published-baseline)
    detection: starvation-check step (failure-isolated) -> reportSilentFallback op=content-starvation (tag starvation=true) + dedup action-required issue; auto-closes on recovery
    alert_route: app SENTRY_DSN SDK capture + Layer 1 Inngest sentry-correlation middleware (auto-tags run_id) + GitHub action-required (operator-digest harvests it)
  - mode: ready-ish draft fails the readiness gate (Liquid markers / no non-empty mapped section)
    detection: promote-drafts collects gateFailedDrafts -> debounced warnSilentFallback op=draft-gate-failed (independent of scheduledWithinHorizon)
    alert_route: app SENTRY_DSN SDK capture (Layer 1 middleware)
  - mode: promotion write/commit fails
    detection: throw -> handler top-level catch -> reportSilentFallback + ok=false heartbeat (persistence failure legitimately reds the cron)
    alert_route: app SENTRY_DSN SDK + Layer 1 middleware + Sentry Crons missed/error + open PR
  - mode: starvation issue-create (Octokit) fails
    detection: inside starvation-check try/catch -> reportSilentFallback op=starvation-check-failed; returns normally (never flips heartbeat)
    alert_route: app SENTRY_DSN SDK capture (Layer 1 middleware)
  - mode: Sentry heartbeat env unset/malformed (silent no-op today)
    detection: postSentryHeartbeat -> mirrorWarnWithDebounce/warnSilentFallback op=heartbeat-env-unset|heartbeat-env-malformed
    alert_route: app SENTRY_DSN SDK capture (independent of the unset ingest vars; Layer 1 middleware)
logs:
  where: pino -> container stdout -> Better Stack; Sentry (SENTRY_DSN SDK) for the mirrored branches
  retention: per existing Better Stack + Sentry retention (unchanged)
discoverability_test:
  command: gh issue list --label action-required --search "Content starvation in:title" --state open
  expected_output: exactly one open starvation issue iff schedule empty > N days (auto-closed on recovery), zero otherwise. Verifiable via gh only, no remote-shell access. (Dropped the earlier "Sentry issue search" clause — scripts/sentry-issue.sh is id-based, not a tag-query CLI, so that half was a dashboard-eyeball in disguise per hr-no-dashboard-eyeball-pull-data-yourself.)
```

## Infrastructure (IaC)

No new infrastructure. The `scheduled_content_publisher` `sentry_cron_monitor`
already exists (`cron-monitors.tf:752`); no new secret (the 3 heartbeat vars +
`SENTRY_DSN` are present in Doppler `prd`); no new cron/vendor/DNS/cert/firewall.
Deliverable-3 verification is **read-only** (`doppler secrets get` presence check,
already run; Sentry monitors-API `lastCheckIn` read post-deploy) — **no Doppler
writes, no `terraform apply`** (the values are already present + valid; nothing to
mutate). The post-deploy check command (observability review O-P1 — the runbook's
live-verified form, NOT the wrong `SENTRY_ISSUE_RO_TOKEN` which lacks monitor
scope):

```bash
# cite: knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md:650
doppler run -p soleur -c prd_terraform -- curl -s \
  -H "Authorization: Bearer $SENTRY_IAC_AUTH_TOKEN" \
  "https://de.sentry.io/api/0/organizations/$SENTRY_ORG/monitors/scheduled-content-publisher/checkins/?per_page=1" \
  | jq '.[0].status, .[0].dateCreated'
```

Note the **regional host** `de.sentry.io` (bare `sentry.io` silently 401s,
`cloud-scheduled-tasks.md:568`) and the **disjoint-scope token** `SENTRY_IAC_AUTH_TOKEN`
(the issues/events RO token cannot read monitors, `:653`). If the check finds
`lastCheckIn` still null, the follow-up is a container-env-injection fix (confirm
which Doppler config the prod container mounts), filed as its own issue — not baked
here.

## Architecture Decision (ADR/C4)

**No new ADR required.** This extends an existing cron (`cron-content-publisher`)
with a promotion step, a content-signal alert, and a loud heartbeat branch. It
introduces no new ownership/tenancy boundary, no new substrate, no
resolver/trust-boundary change, and reverses no existing ADR (ADR-030 Inngest
substrate is honored — this is one more pure-TS Inngest cron behavior).

**C4 completeness (read all three `.c4` files):**
`model.c4` / `views.c4` / `spec.c4` reviewed. External actors/systems for this
feature — **Discord** (`model.c4:226`, `engine -> discord "Notifications"
{ Webhook }` :269) and the trigger/cron layer (`model.c4:174`, ADR-030) — are
already modeled. X/Twitter, LinkedIn, Bluesky are the publisher's existing egress
(the publisher container already posts to them today; this plan changes *what*
gets scheduled, not *which* systems are reached), and **Sentry**/**GitHub** are
already in the external-systems set (`views.c4:14`). No new external human actor
(the CMO/operator is an existing modeled actor), no new external system, no new
container, no changed access relationship. **No C4 edit** — the actors/systems
checked (Discord, X, LinkedIn, Bluesky, Sentry, GitHub, cron layer, operator) are
all already modeled.

## Domain Review

**Domains relevant:** Marketing (CMO)

### Marketing (CMO)
**Status:** to be assessed at plan-review (CMO panel is relevance-gated in).
**Assessment (planner framing):** This automates the content-cadence machinery the
CMO owns (`content-strategy.md` `owner: CMO`). The load-bearing decision for the
CMO: **auto-promoting unreviewed drafts to public channels.** Default = automated
readiness gate (liquid-clean + channels + mapped sections), `status: parked` as
the per-draft hold. Alternative = explicit `ready: true` gate or draft-PR-with-
operator-merge. Recorded as a decision-challenge (headless) for plan-review.

### Product/UX Gate
**Not applicable — NONE.** No `components/**`, `app/**/page.tsx`, or `app/**/layout.tsx`
in Files to Create/Edit; no user-facing UI surface. Server cron + bash + docs only.

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open`; no open scope-out names
any of my target files (`cron-content-publisher.ts`, `_cron-shared.ts`,
`observability.ts`, `content-publisher.sh`). Adjacent Sentry-monitor issues —
**#3828** (extract composite action for Crons check-in fan-out), **#3829** (CI gate
new-monitor→sentry-scrub), **#3740** (post-merge smoke workflow) — touch the Sentry
*monitor/workflow* surface, not this diff. **Disposition: Acknowledge** — different
concern (heartbeat *fan-out/CI*, not the heartbeat *silent-skip* behavior); leave
open.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `content-promotion.ts` unit tests pass: `nextTueThuSlots` returns only Tue/Thu UTC dates, skips `occupied`, respects horizon; `planPromotions` assigns deterministically and never double-books; `applyPromotion` flips `status: draft`→`scheduled` + writes **unquoted** `publish_date`, preserves all other lines, and is a **no-op on an already-`scheduled` file** (idempotency).
- [ ] Readiness gate excludes `parked` and `stale`: a `parked` fixture is never promoted. `occupied` includes a `parked` file's future `publish_date` (no double-book onto a parked date).
- [ ] Readiness gate: a `draft` with `channels` but all-empty mapped sections is NOT promoted (would post nothing) AND appears in `gateFailedDrafts`.
- [ ] **Per-draft gate-failed signal (spec-flow P0):** with ≥1 schedulable draft AND ≥1 gate-failing draft, a `warnSilentFallback` `op=draft-gate-failed` fires listing the failing file — even though `scheduledWithinHorizon > 0`.
- [ ] **Starvation predicate (silent-failure F1):** with 0 scheduled AND **zero `published` files** (undefined `latestPublishedDate`), starvation FIRES (not silently skipped by `NaN >= N`). Same for an unparseable `publish_date` (surfaced via `reportSilentFallback`).
- [ ] Starvation test: on `starved`, emits `reportSilentFallback op=content-starvation` AND creates exactly one dedup `action-required` issue (second run does not duplicate, stable title); the `sentry-heartbeat` step still posts `ok: true`.
- [ ] **Starvation auto-close (spec-flow P1):** once `scheduledWithinHorizon > 0`, an open starvation issue is closed with a recovery comment.
- [ ] **Starvation failure-isolation (architecture A-P1b / silent-failure F3):** a thrown Octokit error inside `starvation-check` is caught → `reportSilentFallback op=starvation-check-failed`, and the heartbeat still posts `ok: true` (does NOT flip to `ok:false`).
- [ ] `postSentryHeartbeat` test: with any of the 3 ingest vars unset OR malformed, a `warnSilentFallback` fires (asserted via the SDK/`SENTRY_DSN` path) with the right `op`; the POST is NOT attempted. `mirrorWarnWithDebounce` bounds repeat emits.
- [ ] Applying `planPromotions` against the **current 18-draft backlog** fixture schedules the horizon's ~8 Tue/Thu slots on run-1 (NOT all 18 — see backlog-drain semantics), flipping those `draft→scheduled`, and a simulated rolling window promotes the remainder on later runs with no permanent skip.
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean; `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/content-promotion.test.ts test/server/inngest/content-starvation.test.ts test/server/inngest/cron-shared.test.ts` green.
- [ ] `content-strategy.md` no longer describes `draft→scheduled` as a manual step.
- [ ] Follow-up issue filed for the deferred `content-publisher.sh` credential-skip-scored-as-publish bug (Phase 4).
- [ ] PR body uses `Closes #2756` (manual gap resolved by the promotion code) and `Ref #4861` (closed post-verification — see below).

### Post-merge (operator / automated)
- [ ] **Verify heartbeats land** (automatable, no remote shell) — run the O-P1 command from `## Infrastructure`: `doppler run -p soleur -c prd_terraform -- curl -s -H "Authorization: Bearer $SENTRY_IAC_AUTH_TOKEN" "https://de.sentry.io/api/0/organizations/$SENTRY_ORG/monitors/scheduled-content-publisher/checkins/?per_page=1" | jq '.[0].status,.[0].dateCreated'` (correct token + regional host; NOT `SENTRY_ISSUE_RO_TOKEN`). **Recent check-in present** → env reaches the container → `gh issue close 4861` with the evidence. **Absent/null** → file a follow-up issue for the container-env-injection mismatch (Doppler-correct ≠ container-has-it, learning `sentry-dsn-missing-from-container-env`) and keep #4861 open. Force a fresh check-in via `/soleur:trigger-cron` (`cron/content-publisher.manual-trigger`) then re-read.
- [ ] Confirm the first post-deploy run promoted ≥1 draft and (if a Tue/Thu slot == deploy day) published it — observe via the run's `routine_runs` row + the committed PR.

## Test Scenarios
1. **Backlog cold-start** — 18 drafts, 0 scheduled: run-1 promotes ~8 (horizon Tue/Thu slots); subsequent daily runs top up as the window rolls; no double-booking; no permanent per-draft skip.
2. **Today is a Tue/Thu, empty schedule** — a ready draft is promoted onto *today* and published same-run; `HandlerResult.published` reflects it (promote runs before pre-check).
3. **Parked hold** — a `parked` file is never promoted AND its future date is not double-booked.
4. **Genuine drought, no baseline** — all drafts fail the gate AND zero published files exist: starvation FIRES (baseline-undefined branch), heartbeat stays `ok`.
5. **Mixed drought** — ≥1 ready + ≥1 gate-failing draft: ready one promotes, gate-failing one raises `draft-gate-failed`, no starvation.
6. **Idempotent replay** — re-running promotion on an already-scheduled corpus mutates nothing and commits nothing.
7. **Heartbeat env blanked** — unset one ingest var: `warnSilentFallback` fires via `SENTRY_DSN`; heartbeat POST skipped; debounced across crons.
8. **Recovery** — drought fires an issue; next run promotes a slot → issue auto-closes.
9. **Octokit failure** — issue-create throws → caught, `reportSilentFallback`, heartbeat stays `ok:true`.

## Sharp Edges
- **gray-matter date coercion** — writing `publish_date` via `matter.stringify` would round-trip the whole block and can coerce/reorder; the plan mandates *targeted line replacement* writing an **unquoted** date to match the corpus (`publish_date: 2026-05-14`). The TS reader (`coerceFrontmatterDate`, publisher :180) already handles Date coercion on read.
- **Inngest replay-safety — corrected invariant (architecture review A-P1a).** The naive "on-disk writes are re-derivable so a cross-attempt replay is safe" claim is WRONG: on a function retry (`retries: 1`), `setup-workspace` is memoized so `mkdtemp + git clone` does NOT re-run, and the prior attempt's `finally` already `rm -rf`'d the workspace — so the disk is gone and a re-executing step hits ENOENT. The real safety property is: **the commit is atomic inside the single `safe-commit-pr` step; uncommitted promotions are discarded with the torn-down workspace; and idempotency holds across the NEXT daily fresh clone, not across an in-run replay.** `retries: 1` is effectively non-recovering for any post-`setup-workspace` failure — it fails loud via the top-level catch (`ok:false` heartbeat), which is acceptable. This plan deliberately inherits the publisher's existing write-step/commit-step split (vs `cron-compound-promote.ts:502-666` which consolidates write+commit into one `step.run`); that inheritance is why it works. Do NOT lean on replay recovery in the design.
- **Debounce does not depend on the ingest vars (VERIFIED)** — `mirrorWarnWithDebounce` (`observability.ts:544-552`) is a pure in-process `tryClaim` + `warnSilentFallback` → `@sentry/nextjs` SDK (`SENTRY_DSN`), no raw-ingest-URL construction. The loud heartbeat-skip lands even when the 3 ingest vars are blank. (Silent-failure review confirmed CLEAN.)
- **starvation-check is failure-isolated; promotion is NOT (asymmetry — silent-failure F5)** — a starvation issue-create (Octokit) failure must be caught + `reportSilentFallback` + return normally (never flip the heartbeat `ok:false`, which would false-page cron-DOWN). But a `promote-drafts` write/commit failure SHOULD propagate to the top-level catch and red the cron (it IS a persistence/liveness failure). Do NOT wrap promotion in a swallow "for symmetry."
- **Starvation must fire on an empty published baseline (silent-failure F1)** — `NaN >= N` is `false`, so a naive `daysSincePublish >= STARVATION_DAYS` silently skips the worst drought (zero published files). The predicate must treat undefined/non-finite `daysSincePublish` (with 0 scheduled) as starved.
- **Doppler-correct ≠ container-has-it** (learning `sentry-dsn-missing-from-container-env`) — the plan verifies check-ins *land*, not just that Doppler `prd` holds the vars. A green Doppler read is necessary, not sufficient, to close #4861.
- **`Ref #4861` not `Closes #4861`** — #4861's closure depends on the post-deploy `lastCheckIn` verification; auto-closing at merge would false-resolve it before the check runs.
- **A plan whose `## User-Brand Impact` is empty/TODO fails deepen-plan Phase 4.6** — it is filled above (threshold: aggregate pattern).
- **vitest, not `bun test`; in-package `tsc`, not `npm run -w`** — `apps/web-platform` runs vitest (`test/**/*.test.ts`) and has no root `workspaces` field; commands pinned in AC.
- **Readiness gate is automated, not human review** — the default auto-posts drafts that pass mechanical checks. This is the CMO decision-challenge; the `status: parked` lever is the escape hatch pending that call.

## Alternatives Considered
| Alternative | Why not (default = fold into publisher) |
|---|---|
| Standalone `cron-content-promote.ts` (mirror `cron-compound-promote`) | Adds a new cron: `cron-manifest.ts` entry + new `sentry_cron_monitor` + parity-test churn + registration. The publisher already clones+commits daily; folding is strictly less surface. Revisit only if promotion cadence must diverge from the daily publisher. |
| Draft PR the operator merges (`mergeMode: "none"`, `prDraft: true`) | Reintroduces a manual step (operator merges) — contradicts "non-technical operator, no manual step." Named as the CMO's review-gate alternative. |
| Explicit `ready: true` frontmatter gate | Still a manual per-file edit (the exact stall behind #2756). Kept as the CMO alternative if auto-posting unreviewed drafts is rejected. |
| New Sentry issue-alert rule in `issue-alerts.tf` for starvation | `reportSilentFallback` already creates a queryable Sentry issue; the `action-required` GitHub issue is the operator-facing surface (`operator-digest` harvests issues, not PR bodies). Avoids an auto-applied `.tf` change. |
| Re-provision the 3 Sentry vars in Doppler | They are already present + valid in `prd` (verified). Re-writing would be a no-op prod write with zero evidence it's needed. |

**Deferrals to track:** (1) Phase 4 — `content-publisher.sh` credential-skip
scored-as-publish (root cause re-scoped per silent-failure F2) — file the follow-up
issue as a pre-merge AC. (2) If the post-deploy `lastCheckIn` read is null, file the
container-env-injection issue and keep #4861 open. (3) CMO decision-challenge:
auto-promote unreviewed drafts vs an explicit review gate (persisted to
`decision-challenges.md` for headless plan-review).
