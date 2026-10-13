---
title: "fix: close out #10094 — slot-trigger + worktree-lease nightly legs verified green post-#10001"
date: 2026-10-13
slug: fix-slot-trigger-lease-nightly-legs-closeout
branch: feat-one-shot-10094-slot-trigger-lease-legs
issue: 10094
closes: 10094
type: fix
priority: p2-medium
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

# fix: close out #10094 — slot-trigger + worktree-lease nightly legs verified green post-#10001

## Overview

Issue #10094 tracks two red legs of the nightly `scheduled-integration-suites.yml`
job observed in dispatch run 38130672233 (2026-10-11T10:05Z, `main` @ `31ada28352`):
the `slot-trigger` leg (`test/conversation-archive-release-slot.integration.test.ts`,
`expected 'cap_hit' to be 'ok'`) and the `worktree-lease` leg
(`test/worktree-write-lease.integration.test.ts` AC2(c)/(e)/(f), `acquire(HOST_B)`
returning `undefined`).

Both legs have been green on every run since PR #10001 merged
(`5b2ccc1456`, 2026-10-11T15:08Z — five hours after the observed failure). The root
cause was test-constant drift, not dev-substrate drift: migration 133 raised the
slot/lease liveness thresholds 120 s → 240 s, but the two dormant env-gated suites
still aged their fixtures to 200 s / 121 s — inside the live 240 s threshold, so the
lazy sweep correctly refused to reap and the lease correctly refused takeover. The
remaining work is evidence-based tracker closeout, not code.

## Research Insights

### Premise Validation (Phase 0.6)

- `#10094` — OPEN, labels `ci/integration-suites`, `domain/engineering`,
  `meta/machinery`, `priority/p2-medium`; filed manually by `deruelle`
  2026-10-12T08:26Z. Not closed by any PR reference.
- `#9993` (standing tracker) — OPEN; must stay open. `#9994` — CLOSED (landed via
  #10090, merged 2026-10-12T13:08Z). `#9995` (MU1 401) — OPEN, separate leg.
  `#5372` — CLOSED (the cited dev-drift-class precedent).
- Cited artifacts all exist on `origin/main`:
  `apps/web-platform/test/conversation-archive-release-slot.integration.test.ts`,
  `apps/web-platform/test/worktree-write-lease.integration.test.ts`,
  migrations `029`, `036`, `037`, `093`, `115`, `116`, `128`, `133`,
  workflow `.github/workflows/scheduled-integration-suites.yml` (legs at :217 and :262).
- **Premise partially stale:** the issue hypothesizes possible dev function-body
  drift ("read the applied function body on dev (`pg_proc.prosrc`) and diff").
  Post-#10001 run evidence shows both legs green on four consecutive runs, so the
  legs are healthy on the *applied* dev substrate; a `pg_proc` probe is retained as
  an optional corroborating step, not a blocking one.
- Mechanism-vs-ADR corpus check: this plan proposes no mechanism (no guard, no
  threshold change, no workflow change); nothing to check against ADR corpus.

### Property List (Phase 0.6b)

Restated from the issue's asks:

1. The `slot-trigger` nightly leg must be green on the nightly lane.
2. The `worktree-lease` nightly leg must be green on the nightly lane.
3. The lazy-sweep / lease-takeover predicate on dev must be verified (issue's
   own probe guidance).
4. `#9993` remains the standing tracker — not closed by this work.

### Cut List (Phase 0.6b)

- *Code change to the STALE constants* — buys no property; #10001 deliberately
  keeps `STALE_SLOT_AGE_S`/`STALE_LEASE_AGE_S` as literals "so a future threshold
  bump re-reddens the leg — the alarm working." Deriving them would defeat a
  designed fail-loud alarm.
- *Dev function-body rewrite / drift repair* — buys property 3 only if drift
  exists; green legs bound the live threshold to the (60 s, 300 s) band already,
  and the optional `pg_proc` probe settles exactness without a write.
- *Workflow/auto-close automation for per-leg issues* — buys no property: per-leg
  issues are human-filed (`deruelle` authored #10094); the automation contract is
  one umbrella issue plus whole-run auto-close, which is behaving as designed.

### Findings

- **Root cause (established from run SHA + diffs, not inferred):** run 38130672233
  checked out `31ada28352` (pre-#10001). At that SHA the slot test called
  `backdateSlotHeartbeat(stuckConv, 200)` and the lease tests called
  `ageHeartbeat(121)` — both assuming the pre-mig-133 120 s threshold. Dev had
  mig 133's 240 s bodies applied since 2026-07-18 (`45e7aa1d4a`). 200 < 240 →
  `cap_hit`; 121 < 240 → zero rows → `undefined`. The passing controls (60 s fresh
  heartbeat → `cap_hit`; AC2(a)/(b)/(d)) are consistent with a correct 240 s
  substrate.
- **Fix already on main:** PR #10001 (`5b2ccc1456`, merged 2026-10-11T15:08Z)
  raised both stale ages to 300 s (= 240 s + 60 s clock-skew margin, named
  constants) and updated comments/copy. Its own commit message documents the same
  diagnosis.
- **Green-run evidence (queried via `gh api .../jobs` step conclusions):**
  run 38152254226 (dispatch, 10-11T15:40Z), 38164703648 (dispatch, 10-11T18:39Z),
  38233564364 (dispatch, 10-12T10:00Z), and 38248356757 (**schedule**, 10-12T12:19Z)
  all show `Run WORKTREE_LEASE_INTEGRATION_TEST suites` = `success` and
  `Run SLOT_TRIGGER_INTEGRATION_TEST suites` = `success`.
- **Remaining red legs are out of scope and tracked:** `SUPABASE_DEV_INTEGRATION`
  / `BYOK` (deleteUser-cascade class, fix landed via #10090 after the last checked
  run), `MU1` (#9995), raw-deleteUser carriers (#10096), plus umbrella #9993.
- **Institutional learnings applied:**
  `learnings/workflow-issues/2026-10-11-a-threshold-sweep-fixed-the-token-it-grepped-and-carried-a-dead-premise-into-the-copy.md`
  (the #10001 session's own record — confirms diagnosis class);
  `learnings/best-practices/2026-10-10-env-gated-suite-dormancy-is-a-conjunction-not-a-wiring-check.md`
  (dormancy is a conjunction; `scripts/lint-integration-env-gates.sh` is the
  durability half);
  `2026-05-15-one-shot-plan-subagent-cwd-divergence.md` (resolve paths from
  `git rev-parse --show-toplevel`).
- **No external research needed (Phase 1.6):** internal CI tracker closeout with
  complete local evidence; external docs add nothing.
- **Community/functional discovery (Phases 1.5/1.5b):** no uncovered stacks
  (TypeScript/bash, covered); no community artifact plausibly overlaps
  evidence-based issue closeout — skipped (no Task/Agent tool in this harness;
  assessed inline).

### Gate Decisions

- **Phase 1.4 network-outage checklist:** no trigger pattern in the feature
  description — skipped.
- **Phase 1.8 skill-description budget:** no `SKILL.md` `description:` edit is a
  candidate — skipped.
- **Phase 2.7 GDPR:** no regulated-data surface; none of the (a)–(d) extended
  triggers — skipped.
- **Phase 2.8 IaC routing:** no new infrastructure — skipped.
- **Phase 2.9 Observability:** `Files to Edit`/`Files to Create` are empty (no
  code-class file, no new infra surface) — detection does not fire. The plan's
  *subject* is itself observability (the nightly leg signal), but no block is
  required.
- **Phase 2.10 ADR/C4:** no architectural decision — a tracker-hygiene closeout
  reverses nothing and creates no boundary. Skipped.
- **Phase 2.11 Encryption Posture:** no persistent store or new connection —
  skipped.
- **Phase 2.12 Guard Contract:** the deliverable contains no guard — skipped.
- **Phase 2.13 Founder check:** headless/pipeline context — skipped.

## Root Cause

At failing-run SHA `31ada28352` (run 38130672233):

| Leg | Test expectation | Fixture age | Live dev threshold (mig 133) | Result |
|---|---|---|---|---|
| slot-trigger | `stale-heartbeat slot reaped → 'ok'` | `backdateSlotHeartbeat(…, 200)` | 240 s | `cap_hit` (200 < 240, not reaped) |
| worktree-lease AC2(c)/(e)/(f) | `acquire(HOST_B) after expiry → gen=2` | `ageHeartbeat(121)` | 240 s | zero rows → `undefined` |

The issue's own "Suites never exercised this path on dev before" framing is
correct in the small: the dormant env-gated suites first ran nightly on 2026-10-11
and immediately hit the constant drift. The "function body drift vs main"
hypothesis is bounded by the green legs — dev's threshold is in the (60 s, 300 s)
band, consistent with mig 133's 240 s and inconsistent with a stale 120 s body
(a 120 s body would still reap 300 s-aged fixtures, so green alone does not prove
exactness — the optional Phase-1 probe below settles it; it is corroboration, not
a gate).

## Implementation Phases

### Phase 1 — Final verification (work time, ~5 min)

1. Re-pull the then-latest run and confirm the two legs on a **`schedule`-event**
   run post-#10001 (the nightly lane the issue tracks):

   ```bash
   gh run list --workflow=scheduled-integration-suites.yml --limit 5 \
     --json databaseId,conclusion,createdAt,event,headSha
   gh api repos/jikig-ai/soleur/actions/runs/<latest-schedule-run>/jobs \
     -q '.jobs[0].steps[] | select(.name | test("SLOT_TRIGGER|WORKTREE_LEASE")) | "\(.conclusion)\t\(.name)"'
   ```

   Both lines must read `success`. (Already true for schedule-run 38248356757;
   re-verify at work time because newer runs land daily.)
2. **Optional corroborating probe (non-blocking; skip if no `doppler` dev access
   in the work environment):** confirm the applied dev function bodies carry the
   mig-133 literal. Note the `doppler run` quoting — `$VAR` must expand in the
   *inner* shell:

   ```bash
   doppler run -p soleur -c dev -- bash -c \
     'psql "${DATABASE_URL_POOLER:-$DATABASE_URL}" --no-psqlrc -tAq -c "select proname, position('"'"'240 seconds'"'"' in prosrc) > 0 as has_240s from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = '"'"'public'"'"' and proname in ('"'"'acquire_conversation_slot'"'"','"'"'acquire_worktree_lease'"'"')"'
   ```

   Expected: two rows, both `has_240s = t`.
3. **Honest-exit gate:** if any `schedule`-event run post-#10001 shows either leg
   red, do NOT close #10094 — post the run link + failing step on the issue and
   stop (the plan's premise is then stale; re-diagnosis needed).

### Phase 2 — #10094 closeout

1. Comment on #10094 with the root-cause table above, the run-SHA explanation
   (failing run predated the #10001 merge), and the green-run evidence list.
2. `gh issue close 10094 --comment "<close note referencing the evidence comment>"`.

### Phase 3 — Tracker hygiene (fold-ins + umbrella note)

1. Comment on #9993: the slot-trigger and worktree-lease legs verified green
   under #10094's scope (root cause: test-constant drift, fixed by #10001);
   tracker stays open for the remaining legs.
2. Close folded-in scope-outs with evidence comments:
   - `gh issue close 3373 --comment "<evidence: Run SLOT_TRIGGER_INTEGRATION_TEST
     suites step exists at scheduled-integration-suites.yml:262 and is green on
     nightly run 38248356757>"` — its re-evaluation criterion ("a separate effort
     wires nightly Doppler integration tests") is met.
   - `gh issue close 3221 --comment "<evidence: scheduled-integration-suites.yml
     runs the env-gated legs nightly; dormancy is guarded by
     scripts/lint-integration-env-gates.sh>"` — its re-evaluation criterion
     ("integration-test runner pattern established for the repo") is met. Both
     carry `do-not-autoclose`, so closure is a deliberate evidence-based act, not
     automation fallout.

## Files to Edit

None — tracker-hygiene change; no code edits.

## Files to Create

None (pipeline planning artifacts only, which are not plan-file entries).

## Non-Goals

- Do NOT close #9993 — it is the standing tracker (issue's own instruction).
- Do NOT change `STALE_SLOT_AGE_S` / `STALE_LEASE_AGE_S` — the literal constants
  are a deliberate fail-loud alarm designed in #10001.
- Do NOT chase the remaining red legs: `SUPABASE_DEV_INTEGRATION`/`BYOK`
  (deleteUser class → #9993/#10090), `MU1` → #9995, raw-deleteUser carriers →
  #10096, tmp-leak → #10017, deferred → #7004.
- No new CI automation — the umbrella-issue + whole-run auto-close contract is
  behaving as designed; per-leg issues are human-managed.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — worst
  case an internal tracker shows a stale open/closed issue state.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no
  exposure vector — GitHub issue metadata only; no user data touched.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** internal CI issue-tracker closeout —
  no user-facing artifact, no regulated data, no production mutation, so no tier
  above `none` is reachable.

## Open Code-Review Overlap

Two open `code-review` scope-outs touch the probed paths; both are **folded in**
(their re-evaluation criteria are verifiably met — see Phase 3):

- #3373 (`SLOT_TRIGGER_INTEGRATION_TEST not wired into nightly CI`) — **fold in**:
  satisfied by the `Run SLOT_TRIGGER_INTEGRATION_TEST suites` step
  (`.github/workflows/scheduled-integration-suites.yml:262`), green on nightly run
  38248356757.
- #3221 (`nightly cron for env-gated integration tests`) — **fold in**: satisfied
  by the same workflow's env-gated legs plus the dormancy guard
  `scripts/lint-integration-env-gates.sh`.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal CI issue-tracker closeout.
(Product/UX gate mechanical override: `Files to Create`/`Files to Edit` are
empty — no UI-surface path; tier NONE.)

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "slot-trigger leg — `test/conversation-archive-release-slot.integration.test.ts`: `expected 'cap_hit' to be 'ok'` at line ~351. The 200s-old stale-heartbeat slot was NOT reaped" [issue #10094] | Phase 1 verification + Phase 2 closeout | mapped |
| 2 | "worktree-lease leg — `test/worktree-write-lease.integration.test.ts` AC2(c)/(e)/(f): `acquire(HOST_B)` returned `undefined`" [issue #10094] | Phase 1 verification + Phase 2 closeout | mapped |
| 3 | "first probe: read the applied function body on dev (`pg_proc.prosrc`) and diff against main's latest migration version" [issue #10094] | Phase 1 step 2 (optional probe) | mapped |
| 4 | "Do NOT close #9993; it is the standing tracker." [issue #10094] | Non-Goals + AC3 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Phase 1 verification steps | asks 1–2 quotes above | asked |
| Phase 1 `pg_proc` probe | ask 3 quote above | asked |
| Phase 2 close #10094 with evidence | — | inferred — justification: the issue is a bug tracker entry; a verified-green pair of legs leaves an open issue asserting red legs, which is stale tracking data — closing with evidence is the resolution the issue exists for |
| Phase 3 comment on #9993 | — | inferred — justification: keeps the standing tracker accurate per the issue's own tracker-hygiene concern without closing it (ask 4) |
| Phase 3 close #3373 + #3221 | — | inferred — justification: plan Phase 1.7.5 fold-in contract; both scope-outs' re-evaluation criteria are verifiably met by the workflow step + lint sentinel |

### Split Assessment

- Subsystems touched: 0 (GitHub issue tracker only; no repo code paths)
- Planned files: 0 | Estimated changed lines: 0
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1: The then-latest `schedule`-event run of `scheduled-integration-suites.yml`
  on `main` post-#10001 shows `Run WORKTREE_LEASE_INTEGRATION_TEST suites` =
  `success` AND `Run SLOT_TRIGGER_INTEGRATION_TEST suites` = `success`, verified
  via `gh api repos/jikig-ai/soleur/actions/runs/<run>/jobs -q '.jobs[0].steps[]
  | select(.name | test("SLOT_TRIGGER|WORKTREE_LEASE")) | "\(.conclusion)\t\(.name)"'`.
  (Run 38248356757 already satisfies this; re-verified at work time.)
- [ ] AC2: `gh issue view 10094 --json state` returns `CLOSED`, and the issue
  carries a comment naming the root cause (test-constant drift vs mig-133's 240 s
  contract), PR #10001, and the green-run evidence.
- [ ] AC3: `gh issue view 9993 --json state` returns `OPEN`, and it carries a
  comment noting the two legs verified green under #10094's scope.
- [ ] AC4: `gh issue view 3373 --json state` and `gh issue view 3221 --json state`
  each return `CLOSED`, each with an evidence comment citing the satisfying
  mechanism (workflow step line; `scripts/lint-integration-env-gates.sh`).
- [ ] AC5: No code changes — `git diff --quiet origin/main...HEAD -- apps/
  plugins/ .github/ scripts/` exits 0 (docs/planning artifacts only; three-dot
  form diffs the merge-base, not the moving tip).

## Test Scenarios

- **integration:** Given post-#10001 `main`, when
  `gh run list --workflow=scheduled-integration-suites.yml --limit 5 --json
  databaseId,conclusion,event` is run and the latest `schedule` run's job steps
  are queried, then both `SLOT_TRIGGER` and `WORKTREE_LEASE` step conclusions
  read `success`.
- **integration:** Given #10094 is open with stale-leg claims, when the Phase-1
  re-verification returns two `success` lines and the closeout comment + `gh
  issue close 10094` run, then `gh issue view 10094 --json state` returns
  `CLOSED` and the last comment cites #10001 + the schedule-run id.
- **integration (honest exit):** Given a `schedule`-event run post-#10001 where
  either leg reads `failure`, when Phase 1 executes, then the pipeline does NOT
  close #10094 and instead comments the run link + failing step name on it.

## Context

- Failing run: [38130672233](https://github.com/jikig-ai/soleur/actions/runs/38130672233)
  (workflow_dispatch, `main` @ `31ada28352`, 2026-10-11T10:05Z)
- Green schedule run: [38248356757](https://github.com/jikig-ai/soleur/actions/runs/38248356757)
  (2026-10-12T12:19Z) — both legs `success`; job still red via sibling legs
- Fix PR: #10001 (`5b2ccc1456`, merged 2026-10-11T15:08Z) —
  `test(integration): realign dormant env-gated suites to mig-133's 240s
  liveness contract`; touched both test files plus related copy
- Threshold migration: `apps/web-platform/supabase/migrations/133_heartbeat_threshold_backoff.sql`
  (`45e7aa1d4a`, 2026-07-18) — lazy sweep + lease takeover 120 s → 240 s
- Standing tracker: #9993 (stays open); siblings: #9994 (closed via #10090),
  #9995 (MU1, open), #10096, #10017, #7004
- Related learning: `knowledge-base/project/learnings/workflow-issues/2026-10-11-a-threshold-sweep-fixed-the-token-it-grepped-and-carried-a-dead-premise-into-the-copy.md`

## Notes

- `lane:` set to `cross-domain` — no `spec.md` exists for this branch, so the
  fail-closed default applied (TR2). No `spec.md` will be authored: this is a
  tracker-hygiene plan, not a feature spec.
- Plan-review agent fan-out could not run in this harness (no Task/Agent tool —
  Devin CLI subagent). The plan was self-reviewed against the sharp-edges
  catalogue; every prescribed read-only command was executed once at plan time.
- Advisor consult (Phase 4.5) skipped: the plan is trivially mechanical
  (verify + issue closeout, zero code edits).
