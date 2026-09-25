---
title: "feat(6178): pin three attributed soak groups into the soak probe's explained set"
date: 2026-09-25
slug: feat-inngest-soak-6178-explained-pins
branch: feat-one-shot-6178-soak-explained-pins
issue: 6178
closes: none
type: feat
priority: p1
domain: engineering
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
status: draft
lane: cross-domain
---

# feat(6178): pin three attributed soak groups into the soak probe's explained set

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-09-25. **Kept proportionate:** a data-pin change, not a 40-agent fan-out.

**Agents used:**

- `soleur:engineering:review:test-design-reviewer`, which built the planned change in a scratch copy and ran mutants;
- a `standard`-tier verify-the-negative sweep over 11 factual claims (all confirmed, with file:line);
- the plan-time learnings researcher, the advisor, and the DHH/Kieran/simplicity/CTO panel (§Plan Review Revisions).

**Mechanical halt gates, all passed:**

- 4.6 User-Brand Impact: present, `aggregate pattern`.
- 4.7 Observability: five fields present. The `grep` verb is allowlisted, the command has no shell-active bytes, and `expected_output` is a literal.
- 4.8: no PAT shapes.
- 4.9 and 4.10: not triggered.
- 4.11: `lint-guard-contract.py` is green, and the Assembly names the `EXPLAINED` chokepoint, not a member list.

**Key improvements:**

1. **Measured byte budget.** In the scratch build, C26q is **3881 of 4000 bytes**, so only 119 bytes of headroom. The new `why` strings were shortened, and the cap is now 110 bytes. E1 now also runs the suite on the tree merged with #8626, since a text-clean merge can still overflow. DC-2 (window-prefixing each why) is recommended against, because of the measured margin.
2. **Whole-line why assertions.** A mutant that truncated the new `why` text passed every prefix assertion. AC5 and C26 now use `grep -cxF` on the full line for the three new buckets.
3. **Two matrix rows added.** Row 10 (the why query loses `select(.explained)`) is caught only by C26c. Row 11 covers a truncated why.

**Verified facts:**

- The sweeper captures `2>&1` and republishes `tail -c 4000` (`sweep-followthroughs.sh`, `out=$(... 2>&1)` and `trimmed_out=`).
- The dry run logs `exit=$rc` and a 600-byte `DRY_RUN — output tail`, and skips every comment and close.
- The sweeper's checkout has no `ref:`, so `--ref <branch>` checks out this branch.
- `refs/remotes/pr8626` is #8626's current head (`847b7e9d9b`).

**PR:** #8835 (draft). **Tracker:** #6178, referenced as `Ref #6178` and never closed. Closing it
is an operator verb: the ADR-100 `adopting → accepted` flip, a fresh re-read, the snapshot release,
and then the close. **Production writes:** none. This PR changes probe data, the probe's output
format, tests and docs.

## Overview

The #6178 soak probe (`scripts/followthroughs/inngest-soak-6178.sh`) buckets cron runs by
`(functionID, 1200 s startedAt-bucket)`. Every group with more than one distinct run is a finding
unless it equals a pin in the `EXPLAINED` constant. A pin is an exact functionID, bucket, count and
sorted member run-id set. The sweeper's 2026-09-24T20:56Z reading was
`explained=2 UNEXPLAINED=3 … SOAK NOT CLEAN`. The three UNEXPLAINED groups are exactly the three
that #6178 comment 5829980093 attributes read-only: host run id == `routine_runs.run_id` == the
Better Stack events. None of them is a double-fire.

| Bucket (window) | Function | Count | Run ids (sorted) | Attribution |
|---|---|---|---|---|
| 1491540 (09-19 20:00–20:20Z) | `9a26ac57-…` cron-compound-promote | 2 | `01M2XM4813N3QE97TEZZVW9TT7`, `01M2XMEM8TZEDVAMRTZSCPWVVZ` | two manual triggers (20:01:07Z, 20:06:47Z, `trigger=manual-api`, both `trigger_source=manual`); the first failed, the second is the operator's retry |
| 1491719 (09-22 07:40–08:00Z) | `26e6836b-…` cron-ghcr-token-minter | 3 | `01M341XPCWG79VZZPDJQ9W64KG`, `01M341XQ4SX2KGWVF5J0XQ9PTG`, `01M341XQNXQDFJSNW1C5PDP4TH` | catch-up after a no-scheduler window: the private-NIC boot race during the dedicated-host replace (runs 35697187645 → 35697872056), resumed by `op=resume` run 35698687536 at 07:57:38Z; the missed 07:00, 07:20 and 07:40 ticks each fired once at 07:57:40–41Z; all `trigger_source=scheduled` |
| 1491858 (09-24 06:00–06:20Z) | `209d5706-…` cron-terraform-drift | 2 | `01M38ZZP4PKKDB2QJ3HB77JTEY`, `01M390P0W5ZT51H3VDD1M2CTYJ` | the scheduled 06:00Z tick plus a manual trigger at 06:12:11Z (`trigger_source=manual`; event `cron/terraform-drift.manual-trigger` `01M390P0FG4GT9J99GR09R77RB`, `trigger=manual-api`) |

This plan pins the three groups as three more exact pins, so the explained set becomes five groups
over four events. It also replaces the single `explained_why:` line with one attribution line per
explained bucket. The 09-17 text is then printed only when a 09-17 group is actually present.

## Research Reconciliation — brief vs. codebase

| Brief claim | Reality (verified 2026-09-25) | Plan response |
|---|---|---|
| The three groups and their triples | The 2026-09-24T20:56Z sweeper comment on #6178 lists exactly these three `UNEXPLAINED:` lines (same functionID, bucket and count). `date -u -d @$((b*1200))` puts each startedAt in the brief's bucket. Each id list is already in `LC_ALL=C` sort order, which is what jq `sort` yields for these ASCII ULIDs. | Pin the brief's values verbatim. |
| The three functionIDs are in the pinned population | Yes: `inngest-soak-6178.function-ids.txt` data lines 12 (`209d5706`), 1 (`26e6836b`) and 27 (`9a26ac57`). | No population change. |
| "the ADR-100 addendum/runbook references that say exactly two such groups are EXPLAINED" | The phrase is in the probe header (line 23). ADR-100's 2026-09-19 addendum says "pins the two groups above" and "the flip condition is 'the criterion holds outside that one bucket'". **No runbook** mentions the explained groups: `grep -niE "soak\|explained" knowledge-base/engineering/operations/runbooks/inngest-server.md` has no hit on this topic, and no other runbook cites the probe. | Edit the probe header and the 09-19 addendum. No runbook edit. |
| #8626 edits the probe "in hunks adjacent to EXPLAINED_WHY" | Verified with `gh pr diff 8626`. Probe: lines 8–9 (header), 166 (`SNAPSHOTS=`, plus a two-line comment above it), and 456/459 (the verdict printfs). Test: the C2 token loop (lines 283–285). ADR-100: an EOF append (`## Addendum — 2026-09-23 (#8532)`). | Stay clear of all of these. A trial `git merge-file` found that **changing line 165 (`EXPLAINED_WHY=`) conflicts** with #8626 (rc=1). Inserting pins directly after `EXPLAINED='[` (line 159) and editing lines 22–28, 154–158, 402 and 437 merges clean (rc=0). An EOF append to ADR-100 would also conflict, so the ADR note goes inside the 09-19 addendum. |

**Premise validation.** #6178 is OPEN with the `follow-through` label, and comment 5829980093 exists
with the attribution table above. #8626 is an OPEN draft whose merge-base with main carries the same
probe and test bytes as this branch's HEAD (`cmp` equal). #8835 is an OPEN draft. The probe on
`origin/main` holds exactly the two 09-17 pins. No premise is stale.

## Research Insights

**Files and anchors (content anchors, not line numbers, per `cq-cite-content-anchor-not-line-number`):**

- `scripts/followthroughs/inngest-soak-6178.sh`:
  - the header paragraph `WHAT IT MEASURES`, and the `SCOPE (op=verify P2-a)` accepted-residuals sentence about manual triggers;
  - the comment block above `EXPLAINED='[`;
  - the `EXPLAINED` constant;
  - the `EXPLAINED_WHY=` constant (**do not edit**: #8626 edits the next line);
  - `jqv split split` (the explained predicate);
  - the `[[ "$explained_n" -gt 0 ]] && printf 'explained_why: %s\n'` print.
- `scripts/followthroughs/inngest-soak-6178.test.sh`:
  - the header `FIXTURES ARE VENDOR-SHAPED` (it says "except the six explained run ids");
  - `EXPLAINED_MINTER` / `EXPLAINED_CREDIT` / `add_explained`;
  - C3's `explained_why:` assertion;
  - the P-D scratch-mutant pattern;
  - `FLOOR=117`.
- `scripts/sweep-followthroughs.sh` `trimmed_out=$(printf '%s' "$out" | tail -c 4000)` is the public comment's window. The sweeper keeps only the LAST 4000 bytes, so an overflow cuts the `reading:` summary line off the top.
- `scripts/guard-vacuity-floor.test.sh` slices the `FLOOR=` binding backward over contiguous assignments. The new `FLOOR=` must stay directly above its `if`.
- `scripts/test-all.sh` already runs the suite (`run_suite "scripts/inngest-soak-6178"`). It needs no change.

**Measured baselines (scratch copy of the suite, 2026-09-25):**

- The suite ran 117 passed and 0 failed in about 20 s.
- The C3 clean-arm output (the two 09-17 pins) is **2786 bytes**. Its longest lines are `explained_why` (387) and the provenance (485).
- C4 (NOT CLEAN arm, one extra group) is **2459 bytes**.
- The clean arm is the larger arm until there are 4 or more UNEXPLAINED groups. Estimate for five pins with three why lines of 120 bytes or less: about 3600 bytes. Adding the registry-growth `registry:` line (about 215 bytes) and the `(QUALIFIED: …)` clause brings it to about 3870, which is under the 4000-byte tail but with little headroom. So the per-pin `why` is capped by test, not by prose.

**Institutional learnings applied:**

- `2026-09-19-the-explained-pin-was-columns-not-members.md`: pin by member ids, never by columns. Every new pin carries its sorted ids, and the exact-set conjunct stays.
- `2026-08-13` (every guard satisfiable by a stub) and `2026-07-24` (count-vs-floor fixtures): each new case needs a must-FAIL twin (a mutated id) and a must-PASS non-canonical input (the new pins alone, without the 09-17 pins).
- `cq-test-fixtures-synthesized-only`: the production ULIDs are the pin itself, so a synthetic set cannot exercise it. This is the same carve-out the suite header already declares for the six 09-17 ids. Extend the carve-out to name all thirteen.

**Premise (Phase 0.6) and minimality (Phase 0.6b):**

- **Property list:**
  - P1: the sweeper reads SOAK CLEAN when the only multi-run groups are the five attributed ones.
  - P2: a group matching a pin's triple but not its member ids stays UNEXPLAINED.
  - P3: an unrelated group stays UNEXPLAINED.
  - P4: each printed justification is visibly bound to the group(s) it justifies, and none is printed for a group that is absent.
  - P5: the whole reading still fits the sweeper's 4000-byte tail.
- **Cut list:**
  - A per-pin `why` for the two 09-17 pins → P4 → already covered by `EXPLAINED_WHY`, which stays verbatim. Duplicating its 387 bytes would also break P5.
  - A new ADR-100 addendum at EOF → recording the change → covered by an in-place `[Updated 2026-09-25]` note in the 09-19 addendum. An EOF append would collide with #8626's addendum.
  - A runbook edit → no runbook states the explained set.

**Advisor consult (Step 4.5):**

- The advisor recommended validating the pin set once at startup, before any GET, and keeping the one legacy-bucket exception in a named constant. **Both were later overridden at plan review** (§Plan Review Revisions): a malformed pin fails safe to UNEXPLAINED, and the suite catches a missing `why`.
- Point the byte-budget test at the **largest realistic** output (five pins plus a grown registry), not at the plain clean case. **Applied** as C26q, plus C26f for the NOT CLEAN arm.

**Skipped research (proportionality):**

- The external-research, functional-overlap and community-discovery fan-outs were not run. This is a data pin on an existing in-repo probe: no new capability and no new stack.
- `soleur:engineering:research:repo-research-analyst` was not spawned. The planner read the two files, the ADR addendum, the sweeper tail and #8626's diff directly.
- `soleur:engineering:research:learnings-researcher` ran.

## Proposed Solution

### Probe (`scripts/followthroughs/inngest-soak-6178.sh`)

1. **Three new pins, inserted directly after the `EXPLAINED='[` line.** Each pin ends with `},`, and the two existing 09-17 pins stay byte-identical. Each new pin carries a `"why"` string. It must be ASCII only, **at most 110 bytes**, with no `'` (the constant is single-quoted) and no `\`. Order the pins by bucket (1491540, 1491719, 1491858). Shape:

   ```text
   {"functionID":"9a26ac57-a722-5c59-9f36-115675eecbad","bucket":1491540,"count":2,
    "ids":["01M2XM4813N3QE97TEZZVW9TT7","01M2XMEM8TZEDVAMRTZSCPWVVZ"],
    "why":"2026-09-19 20:01Z+20:06Z: two manual triggers (trigger_source=manual), an operator retry of a failed run"},
   ```

   The measured strings are 104 bytes for 1491540 and 108 and 91 bytes for the other two:
   - 1491719: `2026-09-22 catch-up: 07:00/07:20/07:40 ticks missed with no scheduler, each fired once at resume 35698687536`
   - 1491858: `2026-09-24 06:00Z scheduled tick plus a manual trigger at 06:12:11Z (trigger_source=manual)`

2. **The two 09-17 pins keep no `why`; their attribution stays `EXPLAINED_WHY`.** That line is not edited. The fallback is one rule in jq (step 4): an explained group whose pin has no `why` prints `EXPLAINED_WHY`. Add one comment line to the pin comment block saying so: only the 09-17 pins omit `why`, and every new pin must carry one. No named-bucket constant and no startup validation are added (cut at plan review, see §Plan Review Revisions). A malformed pin (count ≠ ids length, unsorted ids, a typo in an id) can never match, so it reads UNEXPLAINED. That is the safe direction, and the suite reds on it. A new pin missing its `why` would print the 09-17 text on the wrong bucket, and C26's per-bucket text assertions red on that.

3. **Split carries the matched pin's why.** In `jqv split split`, replace the `any(...)` with a select over the same four conjuncts. The predicate stays inline and appears once; it is not factored into a `def`:

   ```jq
   [ .[] | . as $g
     | ([ $ex[] | select(.functionID == $g.functionID and .bucket == $g.bucket and .count == $g.count and ((.ids | sort) == $g.ids)) ] | first) as $pin
     | . + { explained: ($pin != null), why: ($pin.why // "") } ]
   ```

   `[] | first` is `null`, and `null | .why` is `null`, so an unmatched group carries `why: ""` (checked with jq 1.8.2). The four-conjunct semantics are unchanged: same triple and a different member set stays UNEXPLAINED. `why` is additive and is never compared.

4. **One attribution line per explained bucket.** Replace the single `[[ "$explained_n" -gt 0 ]] && printf 'explained_why: %s\n' "$EXPLAINED_WHY"` with a loop.
   - Feed it:

     ```bash
     jqv why_rows why_rows -r --arg w "$EXPLAINED_WHY" '[.[] | select(.explained) | {bucket, why: (if .why == "" then $w else .why end)}] | unique_by(.bucket) | .[] | [.bucket, .why] | @tsv' <<<"$split"
     ```

   - Call `jqv` directly, never inside `$(…)`. The fallback happens in jq, so the TSV never carries an empty field.
   - `unique_by(.bucket)` collapses the two 09-17 groups onto one line. That is only correct while every pin in one bucket shares one `why`, which is true because only 1491374 holds two pins and both fall back. Say so in a one-line comment. It also sorts by bucket, so the lines print in bucket order.
   - Read with `while IFS=$'\t' read -r b w`. **The first statement of the loop body must be `[[ -n "$b" ]] || continue`**, as in `print_groups`. When nothing is explained, `<<<"$why_rows"` still feeds the loop one empty line. Without the skip, the `INT_RE` check turns every default-fixture reading (C0, C1, C11, C15 …) into rc 3 (Kieran P1, reproduced). Then re-validate `b` against `INT_RE` (a `cannot_establish "shape_failed site=why_bucket"` on failure, mirroring `print_groups`), and print `explained_why: bucket=<b> <w>`.

   The explained group lines themselves stay byte-identical. The output keeps its current order: explained lines, then the why lines, then the UNEXPLAINED lines.

5. **Header comment.** Rewrite the `WHAT IT MEASURES` sentence ("Exactly two such groups are EXPLAINED — …") to say that five groups over four attributed events are explained:
   - the 09-17 catch-up (two groups);
   - the 09-19 manual retry;
   - the 09-22 catch-up;
   - the 09-24 manual trigger.

   Each is pinned as an exact run-id set, with attributions on #6178 comments 5738682595 and 5829980093. Name the `explained_why: bucket=` keying. Also extend the `SCOPE` residual sentence about manual triggers: an attributed manual-trigger group is recorded as a pin, as two already are.

**Do not edit:**

- the `EXPLAINED_WHY=` / `SNAPSHOTS=` lines, which are adjacent to #8626;
- the verdict printfs, including their singular "outside the explained bucket" wording, which #8626 rewrites;
- the C2 token loop.

### Test (`scripts/followthroughs/inngest-soak-6178.test.sh`)

Add a C26 block after the C5 block, before `# ── C6 / C7`. Write it **first** and watch it red against the unmodified probe (§Implementation Phase 1). The new fixture constants sit beside `EXPLAINED_CREDIT`:

- `PROMOTE=9a26ac57-…`, `DRIFT=209d5706-…`, and `NOW_0925=1790337600` (2026-09-25T12:00:00Z: after SOAK_END, before SOAK_STALE 1791244800).
- `PIN_PROMOTE`, `PIN_MINTER2` and `PIN_DRIFT`: JSON run arrays holding the production ids with vendor-shaped startedAt values from comment 5829980093:
  - `2026-09-19T20:01:08.133Z` and `20:06:48.347Z`;
  - `2026-09-22T07:57:40.135Z`, `07:57:40.891Z` and `07:57:41.438Z`;
  - `2026-09-24T06:00:00.407Z` and `06:12:12.295Z`.
- `add_new_pins()`, which appends each array to `slice_of <fn>`.

The cases are listed in §Test Scenarios. Update C3's attribution assertion to `explained_why: bucket=1491374 2026-09-17T12:40–13:00Z catch-up`. Keep its exactly-once count on `op=resume run 35223389582`. Extend the header's production-id carve-out to thirteen ids. Re-measure the pass count and set `FLOOR` to it.

### ADR-100 (`knowledge-base/engineering/architecture/decisions/ADR-100-inngest-dedicated-single-host-singleton-control-plane.md`)

Make two in-place `[Updated 2026-09-25 …]` edits inside `## Addendum — 2026-09-19 (#6178) — the soak reading at day 3.5 …`. This follows the `[Updated YYYY-MM-DD — …]` precedent in ADR-033 and ADR-038.

1. After "the flip condition is "the criterion holds outside that one bucket"", add a bracketed note: the exception now spans four buckets (five groups), see the update at the end of this addendum.
2. Add one closing paragraph of about three sentences before `## Addendum — 2026-09-19 (#6488, #6617)`. It names the three groups (bucket, function, count) and their attribution: two are manual-trigger groups, which is the P2-c residual this addendum already names, and one is a catch-up with the same shape as 09-17. It cites #6178 comment 5829980093 as the full record, and states that nothing is flipped, released or closed.

Do **not** append at EOF, because #8626 appends its 2026-09-23 addendum there.

## Files to Edit

- `scripts/followthroughs/inngest-soak-6178.sh`
- `scripts/followthroughs/inngest-soak-6178.test.sh`
- `knowledge-base/engineering/architecture/decisions/ADR-100-inngest-dedicated-single-host-singleton-control-plane.md`

## Files to Create

None.

## Implementation Phases

1. **RED.**
   - Add the C26 block, the fixture constants and the C3 assertion change to the test.
   - Run `bash scripts/followthroughs/inngest-soak-6178.test.sh`.
   - Against the unmodified probe, C26 (explained=5), C26b, the per-bucket why assertions, C26q and C3's new assertion must fail. Quote that output in the PR body.
   - C26c and C26f already pass against the old probe, because it reads their groups UNEXPLAINED. They are regression guards, not RED targets.
2. **GREEN.** Apply probe steps 1–4 from §Proposed Solution and re-run to 0 failed.
3. **Byte budget.**
   - Confirm that the C26q and C26f outputs fit under `tail -c 4000` with their first line intact.
   - Record the measured byte counts in the PR body.
   - If they do not fit, shorten the new `why` strings. Do not touch `EXPLAINED_WHY` or the verdict lines.
4. **Floor.** Set `FLOOR=` to the measured pass count and re-run to confirm the floor passes.
5. **Docs.** Edit the probe header (step 5) and ADR-100 (two in-place notes).
6. **Merge-safety check against #8626.** Run `git fetch origin pull/8626/head:refs/remotes/pr8626`. Then, for each of the three files, run `git merge-file -p <ours> <merge-base version> <pr8626 version>` and require exit 0 with no `<<<<<<<` markers. If #8626 has moved, re-run against its current head.

## Guard Contract

### Guard 1 — the soak probe's explained split and its attribution lines

**Property.** A (functionID, bucket) group with more than one distinct run reads `explained` if and
only if its functionID, bucket, count **and** sorted member-id set all equal those of one pin in
`EXPLAINED`. Every bucket holding an explained group prints exactly one
`explained_why: bucket=<b>` line, carrying that bucket's own attribution. No `explained_why` line is
printed for a bucket that has no explained group. The whole reading fits the sweeper's 4000-byte
tail.

**Assembly.** There is one chokepoint: the `EXPLAINED` constant. Every pin reaches exactly two
consumers.

- (a) The select inside `jqv split split` is the only place `explained` and `why` are computed.
- (b) The why-row query and its print loop are the only place attribution text reaches stdout.
  `EXPLAINED_WHY` enters only through (b)'s empty-`why` fallback.

Downstream, the output window is the sweeper's `tail -c 4000` (`scripts/sweep-followthroughs.sh`,
`trimmed_out=`), which is why P5 belongs to this guard.

**Mutation matrix** (each row is proven by the suite case named; no hand-run is required):

| # | Mutation | Expected |
|---|---|---|
| 1 | delete any ONE of the three new pins | RED: C26 (that group reads UNEXPLAINED, `explained=4`) |
| 2 | drop the `(.ids \| sort) == $g.ids` conjunct (triple-only pin) | RED: C26c (the mutated-id group reads explained) and the existing C5f |
| 3 | drop the `.bucket` conjunct | RED: the existing C5d |
| 4 | restore the old unconditional `[[ "$explained_n" -gt 0 ]] && printf 'explained_why: %s\n' "$EXPLAINED_WHY"` | RED: C26b (the 09-17 text is printed with no 09-17 group) and C26's `bucket=` assertions |
| 5 | the why-row loop reads only the first row (`head -1`, `.[0]`): the *second member* row | RED: C26 (`bucket=1491540`/`1491719`/`1491858` lines missing) |
| 6 | the why-row query selects nothing (`select(.explained \| not)`): the loop's own dispatch goes empty | RED: C3 and C26 (no `explained_why:` line at all) |
| 7 | drop `why` from one new pin | RED: C26 (that bucket's line carries the 09-17 text instead of its own) |
| 8 | lengthen the three new `why` strings to 250 bytes | RED: C26q (`reading:` cut from the 4000-byte tail) |
| 9 | `unique_by(.bucket)` removed | RED: C26's exactly-once count on `bucket=1491374` (two 09-17 groups print it twice) |
| 10 | the why query drops `select(.explained)` | RED: C26c's `expect_absent "explained_why: bucket=1491719"` (the only case that catches it, so it must not be cut as redundant) |
| 11 | a new `why` truncated or edited (`.why[0:30]`) | RED: C26's whole-line `grep -cxF` assertions |

**Harness rows:**

- Must-PASS non-canonical input: C26b, the new pins alone without the 09-17 pins, reads SOAK CLEAN. A split that rejects everything reds here, as does one that needs the 09-17 pins present.
- Every C26 case runs through `run()`, so `assert_never_close_verb` applies to it.
- Floor: `FLOOR` is re-measured. Deleting any C26 assertion drops `passes` below it.

**Anchor.** The pinned ids and triples are copied from two records outside this commit:

- #6178 comment 5829980093, timestamped, alongside the prd `routine_runs` rows it cites;
- the sweeper's own 2026-09-24T20:56Z reading, which printed the three triples.

A diff that widens a pin, for example by adding an id or changing a count, must also contradict
those two records and the ADR-100 note in the same PR. The member-set conjunct means a pin can never
match more runs than it lists.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly, because the probe only posts a comment on #6178. The indirect failure is a false SOAK CLEAN. For example, a pin that matches a real double-fire, or an ids conjunct lost in a refactor. That would lead the operator to flip ADR-100 and release rollback snapshot `411798619` while two schedulers are live. Every user would then feel duplicated cron effects (double emails or Discord posts, double SLA filings), with the pre-cutover rollback path gone.
- **If this leaks, the user's [data / workflow / money] is exposed via:** the sweeper republishes the probe's output verbatim on a PUBLIC issue. The new output adds only probe-authored constants: the `why` strings, run ULIDs, GitHub run ids and bucket numbers. These are already public on #6178 comment 5829980093. No secret and no host-authored text is added. The xtrace refusal (rc 78) and AC-NOBODY stay as they are.
- **Brand-survival threshold:** `aggregate pattern`. A wrong verdict harms all users at once through duplicated cron side effects. The destructive verbs stay manual and are named, never executed, by the probe.

threshold: aggregate pattern, reason: the diff touches no user-data or auth surface; its only failure mode is a wrong soak verdict that gates operator-executed verbs.

## Observability

```yaml
liveness_signal:
  what: "the sweeper's daily comment on #6178, headed NOT YET / CANNOT ESTABLISH / ACTION REQUIRED, whose reading line carries explained=<n> UNEXPLAINED=<m>; after this PR the expected reading is explained=5 UNEXPLAINED=0 with four explained_why: bucket= lines"
  cadence: "daily (the scheduled-followthrough-sweeper cron, about 20:5x UTC observed) until the operator closes #6178; the probe refuses past 2026-10-06 (horizon_passed)"
  alert_target: "the operator via the #6178 issue comment (issue-author notification) and the sweeper workflow run log"
  configured_in: ".github/workflows/scheduled-followthrough-sweeper.yml plus the directive in the #6178 body (unchanged by this PR)"
error_reporting:
  destination: "the same #6178 comment; every existing reason= token is unchanged, and this PR adds no new refusal"
  fail_loud: "a malformed pin can never match, so its group reads UNEXPLAINED and the verdict SOAK NOT CLEAN (the safe direction); the probe still never exits 0 or 1"
failure_modes:
  - mode: "a pin edit breaks a pin (count != ids length, unsorted ids, an id typo, a missing why)"
    detection: "pre-merge: C26 reds (explained=4, or the bucket line carries the wrong text); post-merge: the group reads UNEXPLAINED on the #6178 comment (layer 6)"
    alert_route: "CI red before merge; ACTION REQUIRED SOAK NOT CLEAN on #6178 after"
  - mode: "a new multi-run group appears after merge (open-topped window: another manual trigger or catch-up)"
    detection: "UNEXPLAINED line plus SOAK NOT CLEAN on the next sweep (layer 6)"
    alert_route: "ACTION REQUIRED heading on #6178; attribute it the same read-only way before pinning"
  - mode: "output outgrows the sweeper's 4000-byte tail and the reading line is cut"
    detection: "pre-merge: C26q (clean arm) and C26f (NOT CLEAN arm); post-merge: a comment whose first folded line is not reading:"
    alert_route: "CI red before merge"
logs:
  where: "sweeper workflow run logs (Actions) and the #6178 issue comments"
  retention: "Actions 90 days; issue comments indefinitely"
discoverability_test:
  command: "grep -c 01M390P0W5ZT51H3VDD1M2CTYJ scripts/followthroughs/inngest-soak-6178.sh"
  expected_output: "1"
```

## Architecture Decision (ADR/C4)

### ADR

This amends ADR-100's **2026-09-19 addendum** in place. The recorded exception to Decision 7's
bucket criterion grows from one bucket (two groups) to four buckets (five groups), each an
operator-attributed, immutable, historical exception. This is an extension of an existing
addendum's exception set, not a new decision, so there is no new ADR ordinal. The edit ships in
this PR (two `[Updated 2026-09-25]` notes); it is not deferred. The status stays `adopting`.

### C4 views

No C4 impact. The planner read `model.c4` (865 lines, the Inngest Server container at `inngest =
container "Inngest Server"`, `inngestPostgres`, `inngestRedis`, Better Stack, GitHub), `views.c4`
(106 lines) and `spec.c4` (54 lines). This PR adds no external actor (the operator already reads
#6178), no external system (GitHub, the deploy webhook and Better Stack are already modeled), no
container or data store, and no access relationship. The probe's HTTP path and its readers are
unchanged, and only the constant data and the output lines change.
`bash plugins/soleur/test/c4-count-parity.test.sh` was run on 2026-09-25: `Failed: 0 / ALL TESTS
PASSED`.

### Sequencing

Nothing is soak-gated in this PR. The ADR flip remains the operator's first verb after a clean
reading.

## Acceptance Criteria

### Pre-merge

- [ ] **AC1 (RED first).** The C26 block and the C3 assertion change are committed or run *before* the probe edit. The Phase 1 run shows C26, C26b, C26q and the new C3 assertion failing against the unmodified probe. The output is quoted in the PR body.
- [ ] **AC2.** `bash scripts/followthroughs/inngest-soak-6178.test.sh` ends with `inngest-soak-6178: <N> passed, 0 failed` and exits 0, and `FLOOR=<N>` equals the measured count.
- [ ] **AC3 (pins exact).**
  - `EXPLAINED` holds exactly five pins.
  - The three new pins carry the brief's functionIDs, buckets (1491540, 1491719, 1491858), counts (2, 3, 2) and sorted ids verbatim. Check: `grep -c` of each of the seven new ULIDs in the probe returns `1`.
  - Each new `why` is ASCII, at most 110 bytes, and contains no `'` or `\`.
  - The two 09-17 pin lines are byte-identical to `origin/main`.
- [ ] **AC4 (exact-set semantics).** C26c (one id of the 1491719 pin mutated) prints `UNEXPLAINED: functionID=26e6836b-97ad-503f-8b08-490d8a2f4ce8 bucket=1491719 (2026-09-22T07:40:00Z–2026-09-22T08:00:00Z) count=3` and reads `SOAK NOT CLEAN`. The existing C5d/C5f stay green.
- [ ] **AC5 (keyed attribution).**
  - C26 prints exactly one `explained_why: bucket=<b>` (followed by a space) line for each of 1491374, 1491540, 1491719 and 1491858.
  - For 1491540, 1491719 and 1491858, the WHOLE line is asserted: `grep -cxF "explained_why: bucket=<b> <full why>"` returns 1. A prefix check misses a truncated or edited why (test-design review: a `.why[0:30]` mutant passed every prefix assertion).
  - For 1491374, the line starts `bucket=1491374 2026-09-17T12:40–13:00Z catch-up`.
  - `op=resume run 35223389582` appears exactly once.
  - C26b prints no `bucket=1491374` line and no `op=resume run 35223389582`.
- [ ] **AC6 (budget).** For C26q (five pins plus one registry-grown function, QUALIFIED, clean arm) and for C26f (five pins plus one UNEXPLAINED group, NOT CLEAN arm), the first line of `printf '%s' "$OUT" | tail -c 4000` starts with `reading:`. Both byte counts are recorded in the PR body.
- [ ] **AC7 (never 0/1).** Every new case runs through `run()`, so `assert_never_close_verb` applies. `grep -nE '^\s*exit (0|1)\b' scripts/followthroughs/inngest-soak-6178.sh` returns nothing.
- [ ] **AC8 (untouched lines).** `git diff origin/main -- scripts/followthroughs/inngest-soak-6178.sh` changes none of the `EXPLAINED_WHY=`, `SNAPSHOTS=` or verdict-printf lines, and `git diff origin/main -- scripts/followthroughs/inngest-soak-6178.test.sh` does not touch the C2 token loop. This is deterministic on this branch's diff.
- [ ] **AC9 (docs).**
  - The probe header no longer says "Exactly two such groups".
  - `grep -n "Updated 2026-09-25"` on the ADR-100 file hits twice, both inside the 2026-09-19 (#6178) addendum.
  - The last `## Addendum` heading of ADR-100 is unchanged by this PR.
- [ ] **AC10 (PR body).**
  - It uses `Ref #6178` and contains no `Closes`/`Fixes`/`Resolves #6178`.
  - It carries the web-1 quiesced-shape evidence as prose, not code: web-1's last `server_active=active` row is 2026-09-15 08:29Z, before SOAK_FROM (12:40Z), and all 242 later hourly `SOLEUR_INNGEST_SERVER_PROBE` rows read `server_active=inactive`, per #6178 comment 5829980093.
  - It links comment 5829980093 as the attribution record.

**Evidence, not gates.** These depend on state outside this diff (`cq-ac-must-not-depend-on-concurrent-sessions`). Record each in the PR body. A surprising result is a finding to report, never a reason to change the pins.

- [ ] **E1 (merge-safety with #8626).**
  - Phase 6's `git merge-file` against #8626's then-current head returns 0 with no conflict markers for all three files.
  - Build the merged tree (`git merge-tree --write-tree HEAD refs/remotes/pr8626`) and run the suite once in a scratch worktree of that tree. A text-clean merge can still break the byte budget or the C2 loop.
  - Record both results. On a conflict, note the hunk in the PR body; whichever PR lands second resolves it.
- [ ] **E2 (live pre-merge reading, read-only).**
  1. Run `gh workflow run scheduled-followthrough-sweeper.yml --ref feat-one-shot-6178-soak-explained-pins -f dry_run=true` and watch it to completion (per `hr-dispatch-async-must-arm-watch`). `dry_run` skips every comment and close in `scripts/sweep-followthroughs.sh`.
  2. Expect the run log's #6178 line to read `exit=5`, with a `DRY_RUN — output tail` containing `SOAK CLEAN` and `5 explained group(s), 0 UNEXPLAINED`.

  If a NEW UNEXPLAINED group appears instead (the window is open-topped), do not widen a pin. Record it as a new finding for read-only attribution.

### Post-merge (automatic, no operator step)

- [ ] **E3.** The next scheduled sweeper comment on #6178 reads `explained=5 UNEXPLAINED=0` and ends `ACTION REQUIRED: SOAK CLEAN …`, unless a new group has appeared since. The operator verbs it names (flip, re-read, snapshot release, close) stay on #6178. This PR does not execute them, and they are already enrolled in the probe's own output, so no new tracking issue is needed.

## Domain Review

**Domains relevant:** none

No cross-domain implications were detected. This is an infrastructure/tooling change to a
verification probe's data, output and tests, plus an ADR note. It has no user-facing surface, no
UI files, no regulated-data surface, no new infrastructure and no vendor.

## Test Scenarios

All new cases use `NOW=$NOW_0925`.

| Case | Fixture | Expect |
|---|---|---|
| C26 | default + `add_explained` + `add_new_pins` | rc 5; `explained=5 UNEXPLAINED=0`; the three new `explained: functionID=… bucket=… (<window>) count=…` lines with exact windows; exact whole-line `grep -cxF` == 1 for the three new why lines, plus the 1491374 prefix line (AC5); `op=resume run 35223389582` exactly once; no `UNEXPLAINED:`; last line `ACTION REQUIRED: SOAK CLEAN` with `5 explained group(s)` |
| C26b | default + `add_new_pins` only | rc 5 `SOAK CLEAN`; `explained=3`; absent `bucket=1491374`; absent `op=resume run 35223389582` |
| C26c | all five pins, but one id of the **1491719** minter pin with its last char flipped (still ULID-shaped, still unique). This function holds two pins. | rc 5 `SOAK NOT CLEAN`; the exact `UNEXPLAINED: functionID=$MINTER bucket=1491719 (…) count=3` line; absent `explained_why: bucket=1491719`; the 1491374 minter group is still explained |
| C26f | all five pins + OTHER ×2 at `2026-09-19T20:25:00Z` and `20:30:00Z` (bucket 1491541) | rc 5 `SOAK NOT CLEAN`; `explained=5 UNEXPLAINED=1`; `UNEXPLAINED: functionID=$OTHER bucket=1491541`; the first line of `tail -c 4000` starts `reading:` |
| C26q | C26 + `registry_fixture 71 "" '["b0000000-0000-4000-8000-000000000001"]'` | rc 5; `(QUALIFIED: 1 unmeasured`; the first line of `printf '%s' "$OUT" \| tail -c 4000` starts `reading:`. The failure message prints the size as `LC_ALL=C wc -c` plus the margin to 4000, never `${#OUT}`, which counts characters while the output holds multibyte `–`, `×` and `→`. |
| C3 (edit) | unchanged fixture | `explained_why: bucket=1491374 2026-09-17T12:40–13:00Z catch-up`; `op=resume run 35223389582` exactly once |

## Plan Review Revisions

The panel was DHH, Kieran, code-simplicity, plus CTO (devex lens), and before them the Step 4.5 advisor. Mechanical findings were applied:

- **Cut:** the startup pin validation, the `EXPLAINED_WHY_BUCKET` constant, the P-E mutants and their harness row, the hand-run mutation AC, the `pinmatch` def (the predicate appears once), and C26d/C26e/C26g/C26h. A malformed pin can never match, so it fails safe to UNEXPLAINED. A missing `why` is caught by C26's per-bucket text assertions (DHH P1, simplicity, CTO P2).
  - The advisor's "validate at startup" recommendation was weighed and **overridden** by the three-seat convergence. It guarded failure modes that already fail safe, in a probe that refuses from 2026-10-06.
- **Fixed:**
  - The why loop skips the empty line that `<<<` feeds when nothing is explained (Kieran P1, reproduced).
  - Per-bucket text assertions now bind each attribution to its bucket (Kieran P2).
  - The byte-budget check now also covers the NOT CLEAN arm (CTO P2).
  - AC8/AC11/AC13, which depend on state outside the diff, became evidence items E1–E3 (Kieran P3, standing check `cq-ac-must-not-depend-on-concurrent-sessions`).
  - The `'` sharp edge was corrected (Kieran P3).
  - The ADR closing paragraph was trimmed to three sentences.
- **Kept against a cut:** C26f (simplicity called it a duplicate of C4). The brief explicitly requires "a fourth unrelated group stays UNEXPLAINED", and cutting operator-requested scope is never mechanical. C26f now also carries the NOT CLEAN byte-budget check.
- **Taste, persisted to `decision-challenges.md`:** pluralising the verdict line's "outside the explained bucket" belongs to #8626's hunk, so it is noted for that PR, not done here. Prefixing each `why` with its exact window is left as optional, since each line already starts with its date.

## Dependencies & Risks

- **#8626 (draft) edits neighbouring lines.** Mitigation: the edit placement was proven clean by a trial `git merge-file` (§Research Reconciliation), and E1 re-checks it against #8626's current head. Whichever PR merges second re-runs the suite, and C26q/C26f then catch a combined output that outgrows 4000 bytes.
- **The window is open-topped.** A new manual trigger near a tick, or another catch-up, reads NOT CLEAN again. That is correct behaviour: it gets a new read-only attribution, never a speculative widening. E2 surfaces it pre-merge.
- **Horizon.** The probe refuses from 2026-10-06. The flip → re-read → release → close sequence has to happen before then. That is operator-side and outside this PR.

## Non-Goals

- Touching `SNAPSHOTS`, the verdict printfs or the C2 loop. #8626 owns those.
- Pluralising "outside the explained bucket" in the verdict lines. It sits on #8626's lines, the probe is deleted soon after the #6178 close, and the new `explained_why: bucket=` lines already name every bucket. This is wording only, not a capability, so it gets no tracking issue.
- Recording web-1's quiesced shape in code. It goes in the PR body as evidence, per the brief.
- Any production write, workflow change or directive change on #6178.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.
- **Do not edit the `EXPLAINED_WHY=` line.** It is adjacent to #8626's `SNAPSHOTS=` change, and a trial merge proved any edit there conflicts. It stays verbatim as the 1491374 attribution.
- **Insert the new pins directly after `EXPLAINED='[`,** each ending `},`. Appending after the last 09-17 pin would mean editing its closing `}` line to add a comma. That also merges clean today, but it is one line closer to #8626.
- `why` strings sit inside a single-quoted bash string. A `'` closes it, and the file then mis-parses (`probe_unparseable`, rc 3, or worse, a silently different constant). Keep the strings free of `'` and `\`.
- En-dashes cost 3 bytes against the 4000-byte tail, so keep the new `why` strings ASCII.
- The why loop needs `[[ -n "$b" ]] || continue` first. `<<<""` still yields one empty line.
- `unique_by(.bucket)` is correct only while all pins in one bucket share one attribution. Today only 1491374 has two pins, and both fall back. Say so in a code comment. (`unique_by(.why)` would give byte-identical output on today's data, because the four attributions differ, so no case distinguishes the two. Bucket is the key the output names.)
- The test harness's `run()` always pins the clock. New cases pass `NOW=$NOW_0925` explicitly, and none reads the wall clock.
- Run `npx markdownlint-cli2` on this plan and `tasks.md` before committing (lefthook lints both).

## Addendum — 2026-09-25 (work phase): E2 found the reading untakeable; slices re-dealt 5 → 7

E2 (sweeper dry run 36121535964 on this branch) returned `CANNOT ESTABLISH: reason=slice_unreadable
slice=1/5 http=500 cause=probe_fatal`. The host's own body, read directly three times, was
`FATAL empty/truncated runs response on page 8 after 1 retry (last_curl_exit=28, total_count=1023)`,
deterministic at ~34 s. The minter alone (713 runs, 8 pages, 19 s) and the other ten slice-1 ids
(310 runs, 4 s) each read HTTP 200. So `main`'s probe could no longer take the reading either,
independent of this PR. Scope grew by one constant: `SLICE_MAX` 11 → 8 (7 slices). The harness
now derives its loops from `SLICES=7`, its curl stub rejects > 8 ids, and a literal pin reds on
drift. The live read-only run of this branch at 7 slices returned rc=5 SOAK CLEAN, 2304 runs,
explained=5, UNEXPLAINED=0, s1=775. The population order is unchanged, and the dated measurement
in the population file is appended to, not edited.

