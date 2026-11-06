---
title: "fix(observability): egress-gw soak probe floors the recurrence check at the apply and stops gating on the anchor's resolve actor"
date: 2026-11-06
slug: egress-gw-probe-apply-floor-and-informational-resolver
branch: feat-one-shot-12189-egress-gw-probe-floor
issue: 12189
type: fix
lane: cross-domain
---

<!-- Spec lacks a lane: key (no spec.md for this branch); defaulted to cross-domain (fail-closed). -->

## Enhancement Summary

**Deepened on:** 2026-11-06
**Sections enhanced:** Phase 1 (harness and rewrite list), Phase 2 (validation of derived values), Observability, Risks
**Research agents used:** CTO (two consults, the second after a live measurement), learnings-researcher, an adversarial
ladder reviewer read against the probe source, code-simplicity-reviewer. Gates run: User-Brand Impact, Observability (block
declared, command verified to print the literal in 16 ms with no credential), PAT scan (none), Guard Contract lint (green),
Scope Check (one live section), technical-ruling gate (14 rows). UI, encryption, network-outage, downtime and task-design gates
do not fire (no UI file, no store or `.tf`, no new autonomous task).

### Key Improvements
1. The CTO's first soak origin (alert `updated_at`) was falsified by two live reads (vendor churn every ~5 min) and withdrawn
   before it reached the plan; the earliest pass stays about 16:16Z.
2. The adversarial pass found suite rows the first draft did not list (anchor-own-second recurrence, `DECLARED=0` absent-canary
   text rows, `rows_in_window=na` on PASS, `A_RES` default later than the floor, `PAGES=2` split shifting) and fail-open spots in
   derived jq values (empty `max`, leading-zero floor, unparseable `resolved_at` read as open); all are now plan steps.
3. Pin provenance recorded: the apply run window (12:14:26Z to 12:17:27Z) is why the 300 s slack exists.

### New Considerations Discovered
- A re-created canary, or any canary incident older than the bound, is exit 3 by design and needs a re-pin.
- The slack window `[12:11:03Z, 12:16:03Z)` holds no production incident today (measured), so the asymmetry costs nothing now.
- The walk's blind spot also covers an older incident that resolves after the floor, not only an open one.

## Overview

Tracker #12189 (Ref #12180; #12180 is closed and contextual; this change never closes either) is closed by the daily
follow-through sweeper running `scripts/followthroughs/egress-gw-probe-silent-12180.sh`. Measured live on 2026-11-06
(issue comment 6684919763), that probe cannot reach exit 0:

1. The recurrence check counts any production incident newer than the anchor's start. Incident 1048111600 (old alert
   shape, started 07:45:00Z, auto-resolved 12:10:00Z, before the apply) is counted forever.
2. The pass path requires `anchor_resolved_by=none`, but the anchor (1047829421) was resolved through the API
   (`resolved_by` "API"), so the pass is unreachable.
3. The runbook and ADR-218 still call `resolved_by` null on auto-resolve ASSUMED; it is now OBSERVED on 1048111600.

The fix pins the apply time as the floor, replaces the three age gates with one soak clock measured from that floor,
makes the anchor's resolve actor informational, requires rows on both roster hosts on the pass path, and corrects the two
documents. No Better Stack write, no canary delete (the canary deletion is a later, owner-gated PR).

## Research Reconciliation: Spec vs. Codebase

| Brief claim | Reality (checked) | Plan response |
|---|---|---|
| "the floor should be the canary alert's creation time" | Live canary alert `created_at` = 2026-11-06T12:16:03.768Z (key present, unchanged across two reads). But the exit-0 read happens AFTER the canary alert is deleted, when no alert exists to read. | CTO: pin the measured value as a literal `APPLY_FLOOR_EPOCH=1793967363` (12:16:03Z); the live `created_at` and the canary incident `started_at` become cross-checks. |
| "earliest read after about 16:17Z" | 12:16:03Z + 4 h = 16:16:03Z. | Kept (`decision-challenges.md` Notes). |
| "pass when ... rows are present on both hosts" | Today `rows_in_window` is read only when the production incident is open or a newer one exists, and is diagnostic. | The rows read moves onto the pass path and becomes verdict-bearing there (exit 3 unreadable, exit 5 a roster host at zero). |
| Tracker #12189 body, criterion 2: "resolved without a manual action" | Anchor was resolved through the API at 07:47:00.612Z. | Tracker body is not edited; a corrective comment is posted at ship (Phase 5). |
| Brief: "make the anchor's resolve actor informational" | The anchor-open state is still load-bearing: an open production incident of any age must block a pass. | Anchor-open generalizes to "any open exact-name production incident not counted as a recurrence" (CTO ruling b). |
| (found while planning) the soak origin could use alert `updated_at` | Two reads 10 min apart show `updated_at` bumping about every 5 minutes on every alert with no apply (no apply run after 12:14Z). | `updated_at` is dropped entirely; the CTO withdrew its first soak-origin ruling after this measurement. |

## Research Insights

**Premise Validation.** `gh issue view`: #12189 OPEN (follow-through, observability, p2); #12180 CLOSED (contextual);
#12190 (heartbeat poller) OPEN; #12242 (canary mirror issue) OPEN; PR #12186 MERGED 2026-11-06T12:14:24Z; PR #12244 is this
branch's draft PR (the only open change naming #12189). Collision pre-check: no other open PR names #12189. ADR corpus
check: ADR-218's 2026-11-05 amendment is the decision this probe verifies; nothing rejects a pinned floor. Live read-only
reads (readonly token via Doppler, key names and timestamps only): alert listing and incident list as in the CTO evidence
in `decision-challenges.md`.

**Property List** (what must be true after this change):
P1. Exit 0 is reachable when, and only when, the canary has fired, the production alert is live and `higher_than 0`, both
roster hosts have rows in the trailing 15 minutes, and no production incident started at or after the apply for 4 h.
P2. A production incident that started before the apply and has resolved never blocks a pass; one still open always does.
P3. The anchor's resolve actor never changes a verdict (it is printed, nothing more).
P4. Every unreadable or inconsistent input maps to exit 3 or 5, never 0; exit 1 stays unused.
P5. The runbook and ADR-218 state which vendor facts are OBSERVED, which are INFERRED, and which are not measured.

**Cut List** (mechanisms considered and removed before research):
- Reading the floor from `SOLEUR_FT_EARLIEST` -> buys no property (it is an operator date later than the apply; hides post-apply incidents).
- Reading alert `updated_at` as a reshape marker or soak origin -> falsified by measurement (vendor churn every ~5 min).
- A code-level hash of the production alert block beside the pin -> P1 is already covered by the live shape check plus a hand re-pin; documented as a Non-Goal.
- A new ADR or C4 change -> no new component or boundary (CTO).

**Relevant learnings** (`knowledge-base/project/learnings/`): the 2026-11-06 absence-alert learning (both vendor
behaviours unverified, so every ambiguity maps to exit 3); 2026-09-20 probe-clock learning (header claims about the
sweeper clock were backwards; the sweeper parses the issue body); 2026-10-22 (an `exit` inside `$( )` only exits the
subshell: the new rows read must be a function called in the main shell, not a command substitution that calls `verdict`);
2026-10-19 soak-probe gate controls (positive control per helper, exact MIN_ASSERTIONS floor, reorder mutants for exit
precedence); 2026-10-28 (a probe that can finally pass must be read against what each exit TRIGGERS: see the table below);
2026-09-11 (name the falsifying command for every causal sentence added to a runbook).

**Sweeper action per exit code** (`scripts/sweep-followthroughs.sh`, open tracker): 0 posts the PASS heading and CLOSES
the tracker; 2, 3 and 5 post a comment (NOT YET, CANNOT ESTABLISH, ACTION REQUIRED), leave it open; 78 is retried; a stray
1 would comment FAIL (and on a closed tracker would REOPEN it), which is why exit 1 is unused. Each probe run has a 300 s
cap (`FT_PROBE_TIMEOUT`); the pass-path warehouse read adds one `betterstack-query.sh` call, well inside it. The sweeper
trims the probe output to 4000 bytes and posts it publicly, so every new line stays numbers and fixed tokens only. Closure
needs the canary deleted first: with the canary declared or live, a held soak returns exit 5 "delete the canary" (the
owner-gated deletion PR), and the sweep after that deletion returns 0.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly; the probe is operator tooling. The failure that matters
is the tracker closing early over an unexamined recurrence (an egress-gateway silence nobody is paged for) or never
closing (the canary pair keeps filing P1 mirror issues and one email, about 96 "Still open" comments a day).
**If this leaks, the user's data is exposed via:** the sweeper posts stdout and stderr verbatim to a public issue; the
new fields are numbers and fixed tokens, incident objects stay projected to id, name and timestamps, and the credential
never leaves curl's stdin channel. No user data is read.
**Brand-survival threshold:** none
threshold: none, reason: the diff edits a follow-through probe, its suite and two operator documents; it reads no user data and writes nothing to production.

## Files to Edit

- `scripts/followthroughs/egress-gw-probe-silent-12180.sh` (the probe: header contract, pin, ladder, fields, rows on the pass path).
- `scripts/followthroughs/egress-gw-probe-silent-12180.test.sh` (the suite; re-pin `MIN_ASSERTIONS`).
- `knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md` (the field list near the probe command; the decision-table row that says ASSUMED; new rows for the new verdicts).
- `knowledge-base/engineering/architecture/decisions/ADR-218-native-better-stack-logs-alerts-are-terraform-managed-via-the-logtail-provider.md` (append a dated amendment; earlier text untouched).

Checked and NOT edited (verified by `git grep` for `resolved_by|anchor_resolved_by|egress-gw-probe-silent-12180|SOLEUR_EGRESS_GW_SILENT_SOAK|ASSUMED`):
`betterstack-log-query.md` (its probe bullet only names the script and `rows_in_window`; stays true),
`apps/web-platform/test/infra/egress-gw-alert.test.sh` (pins `PROD_NAME`, `CANARY_NAME`, `CANARY_RESOURCE`, `EMITTER_TAG` at column 0 once; none is touched),
`apps/web-platform/infra/betterstack-logs-alerts.tf` (comment points at the RETIREMENT line, still true),
`plugins/soleur/test/preflight-discoverability-test.test.ts` (counts plans declaring a credentialed probe; this plan declares none, so the baseline of 95 is unchanged),
`scripts/test-all.sh`, `scripts/suite-shard-legs.tsv`, `tests/scripts/test-argv-bearer-sweep.sh` (suite path and name unchanged).

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-12189-egress-gw-probe-floor/decision-challenges.md` (done at plan time).
- `knowledge-base/project/specs/feat-one-shot-12189-egress-gw-probe-floor/tasks.md`.

## Open Code-Review Overlap

None. (Two-stage `gh issue list --label code-review` plus `jq --arg` over the four edited paths returned no match.)

## Architecture Decision (ADR/C4)

### ADR
Amend ADR-218 by appending "Amendment 2026-11-06 (#12189, Ref #12180)": records the OBSERVED facts, the pinned floor and
the soak definition, the stated cost of the pin (a reshape of the production alert's evaluated query, `on_missing_data` or
`query_period` must re-pin it in the same PR), and that it supersedes (a) the ASSUMED wording and (b) the 2026-11-05
sentence "this change has not yet shown that an incident of this alert can recover on its own". No new ADR (CTO).
### C4 views
No C4 change. Checked against `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`: the external
systems (Better Stack, GitHub Actions sweeper, the Logs warehouse) and the probe-to-vendor edges are already modeled and
no actor, system, container or access relationship changes; no derived cardinality moves (alert count stays 20, canary
pair unchanged), so `plugins/soleur/test/c4-count-parity.test.sh` must stay green (run it in Phase 4).
### Sequencing
The amendment describes the target state now; it is not a follow-up issue.

## Observability

The change is itself an observability surface: the probe's verdict line is what the sweeper publishes on the tracker.
`scripts/followthroughs/` is outside the code-class paths plan Phase 2.9 scopes, but deepen-plan Phase 4.7 reads any
non-docs path, so the five-field block is declared. No credential-gated probe is declared (it would raise the repo-wide
credentialed-probe baseline for no benefit): the discoverability command runs the probe with no credential bound, which
exercises the verdict-line chokepoint and prints the line in well under a second.

```yaml
liveness_signal:
  what: one SOLEUR_EGRESS_GW_SILENT_SOAK verdict line per sweeper run, posted on tracker #12189 (verdict=, quiet_age_s=, rows_in_window=)
  cadence: daily (scheduled-followthrough-sweeper.yml), first run after the tracker's earliest=2026-11-07T00:00:00Z
  alert_target: the tracker issue comment (NOT YET, CANNOT ESTABLISH, ACTION REQUIRED headings) and the sweeper's red-run annotation
  configured_in: scripts/followthroughs/egress-gw-probe-silent-12180.sh and .github/workflows/scheduled-followthrough-sweeper.yml
error_reporting:
  destination: stderr TRANSIENT and ACTION REQUIRED lines in the same sweeper comment (observability layer 6)
  fail_loud: every unreadable or inconsistent input exits 3 with verdict=unknown; the EXIT trap remaps any stray exit 1 to 3
failure_modes:
  - mode: warehouse unreadable or credentials absent on the pass path
    detection: exit 3, rows_in_window=unknown, TRANSIENT line names the exit code and byte length only
    alert_route: sweeper comment CANNOT ESTABLISH
  - mode: a roster host has no rows in the trailing 15 minutes while the alert is green
    detection: exit 5, rows_in_window shows the zero host
    alert_route: sweeper comment ACTION REQUIRED
  - mode: the pin or a live cross-check disagrees (canary created_at, canary incident start, floor outside anchor..now)
    detection: exit 3 naming the disagreeing input
    alert_route: sweeper comment CANNOT ESTABLISH
logs:
  where: the sweeper job log and the tracker comment (last 4000 bytes of stdout and stderr)
  retention: GitHub Actions log retention; the tracker comment is permanent
discoverability_test:
  command: bash scripts/followthroughs/egress-gw-probe-silent-12180.sh 2>&1 | grep -o SOLEUR_EGRESS_GW_SILENT_SOAK | head -1
  expected_output: SOLEUR_EGRESS_GW_SILENT_SOAK
```

## Implementation Phases

Tests first (`cq-write-failing-tests-before`): Phase 1 rewrites the suite so it is RED against the current probe; Phase 2
turns it GREEN.

### Phase 1 — Suite (RED)
Edit `egress-gw-probe-silent-12180.test.sh`.
1.1 Harness: add `EGRESS_GW_SILENT_FLOOR_EPOCH` to `run_case`'s env and a `FLOOR_AGE` default in `reset_defaults` (floor =
`NOW - FLOOR_AGE`, 20000 by default; anchor start AND anchor resolve both earlier than the floor, so `A_RES` must be set
before the floor in the default, not `NOW - H4 - 3601`; canary incident start = floor minus 64 s). Keep `CANARY_ALERT_AGE`
an INDEPENDENT knob (the young-canary rows need 300 to 1201 s; the new check only requires `created_at >= floor - 300`, so
the old default of 100000 would now be exit 3 and must become a value at or after the floor minus slack). Open-incident rows
(`A_RES=open`) use `FLOOR_AGE=3000` by default so they stay inside `QUIET_STALE_S`; the stale rows set it past 15300. Default
`ROSTER_BQ` becomes both roster hosts with non-zero counts. The default compliant fixture is the real exit-0 shape: canary
alert deleted (`ALERT_LIVE=0`), canary incident listed, `DECLARED=0`, anchor resolved by an actor. Add a 1048111600-shaped
decoy (production name, started before the floor, resolved before the floor, `resolved_by` null) to `build_fixtures`, and
pin that the anchor still lands on page 2 of the `PAGES=2` split (`$d[:3]`), since the added decoy shifts it. Give every alert
fixture an `updated_at` of `NOW` (vendor churn) so a behavioral row proves it never changes a verdict.
1.2 Rewrite the rows that encode the old contract (list from the current suite, by line group): the age-boundary rows
(resolved 4 h minus 1 s / exactly / plus 1 s) become floor-age boundaries on non-collinear points; the "canary incident
younger than 4 h" row becomes the floor-age row; the open-anchor staleness and `SOLEUR_FT_EARLIEST` rows become
`quiet_since`-based and "EARLIEST is ignored" rows (a fresh and an ancient EARLIEST each leave the verdict unchanged);
the `actor -> 5` rows and the `resolved_by` key-missing `-> 3` row become "informational: PASS with the field printed
`actor` / `unknown`"; the row that asserts no warehouse read on a resolved incident flips (a pass now reads rows), as does
the PASS verdict-line row that pins `rows_in_window=na` and `anchor_resolved_by=none`. Also rewrite, found by reading the
suite: the "second production incident in the anchor's own second" row (now pre-floor, so it is not a recurrence: rewrite
as the slack-boundary pair); the `DECLARED=0` rows with canary alert AND incident absent that expect "DELETED or NEVER
CREATED" or "apply|create" text (that shape is now the retired exit 5; they need `DECLARED=1`); the rows that use
`STALE_S` or `CANARY_AGE` as a soak input; the rows at "resolved 10 s ago" and "resolved 7200 s ago" (they hinge on the
anchor's `resolved_at` and now hinge on `quiet_since`).
1.3 New rows (each with an exit and a field/message assertion): pre-floor resolved decoy never counts (PASS,
`newer_prod_incident=0`); recurrence at exactly floor minus 300 counts, at floor minus 301 does not (two non-collinear
fixtures); a second post-floor incident after a compliant pre-floor one counts; pre-floor OPEN non-anchor incident -> 2
inside `quiet_since + 15300`, 5 past it; a pre-floor incident resolved after the floor moves `quiet_since` (boundary pair);
rows on the pass path (one row per distinct code path; the unreadable-warehouse modes run as one loop over mock modes):
warehouse rc non-zero / non-row answer -> 3, credentials unbound -> 3, empty `EGRESS_GW_SILENT_ROSTER` -> 3, one roster
host at zero -> 5, an extra non-roster host cannot cover a missing roster host; floor checks: floor after now -> 3, floor
before the anchor's start -> 3, listed canary alert with `created_at` missing / unparseable / before floor minus slack -> 3
(one loop of three fixtures; these rows run only while the alert is listed, the post-deletion shape is the default fixture),
duplicate canary alerts -> 3, a listed canary incident before floor minus slack -> 3 and a second fixture with two canary
incidents where the earlier one predates the bound (still 3: a re-created canary needs a re-pin); an unparseable
`resolved_at` on any listed production incident -> 3 (never read as open); retired
canary (alert absent, incident absent, not declared) -> distinct 5 whose text is not "DELETED or NEVER CREATED", and the
declared variant keeps the old text; anchor single read vs list disagree on resolved state -> 3.
1.4 Pins and floor: the 12-field verdict-line order regex (the first ten unchanged, then `quiet_age_s`,
`pre_floor_open_prod_incident`) with anchored character classes so the two appended values can only be digits, `-1`, or a
fixed token (they are posted publicly); source pins: `APPLY_FLOOR_EPOCH=` is assigned once at column 0 as digits and the
RETIREMENT block lists `APPLY_FLOOR_EPOCH` (no source-grep pin for `SOLEUR_FT_EARLIEST` / `updated_at`: behavioral rows
only, per simplicity review); negative controls for any new helper; re-pin `MIN_ASSERTIONS` from a green run (never hand-edit; `grep -n '^MIN_ASSERTIONS='` after).
Exit: `bash scripts/followthroughs/egress-gw-probe-silent-12180.test.sh` fails against the unmodified probe on the new rows.

### Phase 2 — Probe (GREEN)
Edit `egress-gw-probe-silent-12180.sh` to the CTO ladder:
2.1 Constants next to `ANCHOR_ID`: `APPLY_FLOOR_EPOCH=1793967363` (column 0, digits, comment: 2026-11-06T12:16:03Z, apply run
42216140017, canary alert `created_at` 12:16:03.768Z, "re-pin by hand in the PR that changes the production alert's
evaluated query, `on_missing_data` or `query_period`"), `FLOOR="${EGRESS_GW_SILENT_FLOOR_EPOCH:-$APPLY_FLOOR_EPOCH}"`,
`SLACK_S=300`; `QUIET_STALE_S=15300` replaces `STALE_S`. Delete the `SOLEUR_FT_EARLIEST` parsing block.
2.2 Setup checks (all `unknown`, exit 3): `FLOOR` numeric, canonicalized with `FLOOR=$((10#$FLOOR))` and digit-capped (a
leading-zero value passes `^[0-9]+$` but breaks `--argjson`), and `anchor_start <= FLOOR <= NOW`; more than one canary alert;
a listed canary alert whose `created_at` is not an epoch or is earlier than `FLOOR - SLACK_S`; a listed canary incident
earlier than `FLOOR - SLACK_S`; the anchor's open/resolved state differing between the single read and the list.
2.3 After EVERY new `$( )` derived value (recurrence set, canary incident list, `quiet_since`, pre-floor open set, flags)
assert the shape (`=~ ^[0-9]+$`, or `0|1`) and call `unknown` otherwise; the existing `newer=` / `canary_inc=` jq calls are
unchecked today and a jq failure there reads as zero. In the projection, error when `resolved_at != null` and
`resolved_epoch == null` (an unparseable resolve must be exit 3, not "open"). `quiet_since` takes the max over
`select(.resolved_epoch != null)` with `// empty` (jq `max` of an empty list is null). Replace the `newer` filter: exact-name production incidents with `id != anchor` and `epoch >= FLOOR - SLACK_S` are the
recurrence set (`V_NEWER`). Compute `quiet_since = max(FLOOR, max resolved_epoch over listed exact-name production
incidents)`, `V_QUIET = NOW - quiet_since`, and the pre-floor open set (exact-name, unresolved, not in the recurrence set,
anchor included).
2.4 Verdict ladder in the CTO order (see `decision-challenges.md`): prod alert state 5; recurrence 5; canary branches
(paused 5, young live alert 2, blind 5, retired 5 with its distinct text, absent-and-declared keeps the old text); pre-floor
open 2 until `V_QUIET > QUIET_STALE_S` then 5; `V_QUIET < SOAK_S` -> 2; rows check; canary declared or live -> 5; pass.
Delete the `V_RBY == actor` exit 5, the `V_RBY != none` exit 3, the `V_AGE` gate and the canary-age gate. Keep `V_RBY`,
`V_AGE`, `V_PROD` as informational fields.
2.5 Rows (diagnostic trigger now also fires for a pre-floor open incident, not only `V_PROD == open` or a recurrence): refactor the warehouse read into a function `read_rows` (called from the main shell, never inside `$( )`, per the
2026-10-22 learning) that sets `V_ROWS` and `ROWS_OK` (1 only when every roster host has `n > 0`, computed in the same jq
that builds the field); it keeps running diagnostically for an open / recurrence verdict and is now also called before the
rows step; unknown on the pass path -> `unknown ... ; exit 3`, a zero roster host -> `action ...; verdict action_required 5`.
2.6 `emit_line` appends `quiet_age_s` and `pre_floor_open_prod_incident`; update the header's verdict-line, EXIT CONTRACT,
EARLIEST paragraph (now: the probe does not read it, and why), the soak-origin text, a "BLIND SPOT" note (the walk stops at the
anchor, so a production incident older than the anchor is invisible, whether it is open or resolves after the floor), rewrite the
step-5 and `na` sentences (rows are no longer diagnostic-only), a "PIN" note, and the RETIREMENT list (add the
pin and the ADR note as sites; the suite derives referrers from the header). Exit 1 stays absent.
Exit: the suite is green; `bash -n`; no `exit 1` in non-comment code.

### Phase 3 — Documents
3.1 Runbook `cron-egress-blocked.md`: update the field list beside the probe command (12 fields); rewrite the decision-table
row that says ASSUMED to state the OBSERVED facts and that `anchor_resolved_by` is informational; add rows for: pre-floor
open production incident; recurrence at or after the apply (exit 5, poller #12190); rows missing on a roster host at the
pass step; canary retired with its incident unreadable (close by hand citing the `canary=fired` comment; do not build the
poller). Wording per the ruling: OBSERVED 2026-11-06 `resolved_by` null on incident 1048111600 and "API" on 1047829421;
list what is NOT measured. Front-load the "do NOT close the canary's mirror issue" warning is unchanged.
3.2 ADR-218: append the dated amendment (see the ADR section above); do not edit earlier text. Run the ADR and markdown
lint the repo uses for the decisions directory.
3.3 Sweep: `git grep -nE 'ASSUMED|never observed|resolved by the alert|by the alert recovering' -- knowledge-base/engineering scripts/followthroughs`
returns only text that is still true.

### Phase 4 — Verify
4.1 The suite; `bash apps/web-platform/test/infra/egress-gw-alert.test.sh` (probe literals); `bash plugins/soleur/test/c4-count-parity.test.sh`;
`python3 scripts/lint-guard-contract.py <this plan>`; shellcheck if the repo wires it for
`scripts/followthroughs/`; `bash tests/scripts/test-argv-bearer-sweep.sh` (suite name unchanged).
4.2 Read-only live check (one run, readonly token via the runbook's `doppler run` form, no writes): before 16:16:03Z expect
`verdict=not_yet` with `quiet_age_s` below 14400 and `newer_prod_incident=0`; after it, with the canary still declared and
live, expect `verdict=action_required` whose message says to delete the canary (not exit 0). Record the verdict line in the PR.

### Phase 5 — Ship notes
PR body: `Ref #12189` and `Ref #12180` (never `Closes`). Post one corrective comment on #12189 (criterion 2 was written as
"resolved without a manual action"; the anchor was resolved through the API, and the probe now gates on the floor, not the
actor). No label change, no `earliest=` change.

## Guard Contract

### Guard 1 — The probe's exit-0 gate

**Property.** The probe exits 0 only if the canary incident exists, the production alert is listed once, unpaused and
`higher_than 0`, every roster host has rows in the trailing 15 minutes, no exact-name production incident is open or
started at or after the pinned floor minus slack, at least 4 h have passed since `quiet_since`, and the canary alert is
neither declared nor live.

**Assembly.** One chokepoint: `verdict()` (the only place a contract exit is chosen). The members that feed it: the setup
checks, the prod-alert `case`, the recurrence set, the canary branches, the pre-floor open set, the soak gate, the rows
step, the declared-or-live step; the inputs: `APPLY_FLOOR_EPOCH`/`FLOOR`, the incident list walk, the alert listing, the
`.tf` declaration scan, the warehouse read. Consumers of the exit: `sweep-followthroughs.sh` (0 closes), the runbook table.
The suite is the second chokepoint (a pass mis-graded GREEN there is the same defect).

**Mutation matrix.**

| # | Edit (design-derived) | Must go RED because |
|---|---|---|
| M1 | delete the recurrence filter's `epoch >= FLOOR - SLACK_S` lower bound (count every production incident again) | the pre-floor decoy row would read as a recurrence, or a post-floor row stops counting |
| M2 | move the rows step above the soak gate (reorder, not delete) | the not-yet-with-warehouse-down row would exit 3 instead of 2 |
| M3 | make `verdict pass 0` reachable with `ROWS_OK` unset (drop the rows step) | the one-roster-host-at-zero row would exit 0 |
| M4 | drop the second member: only the first post-floor incident is compared (stop at the first match) | the "second post-floor incident after a compliant pre-floor one" row would pass |
| M5 | change `verdict()` so it never prints (own dispatch: the guard reports nothing) | the verdict-line regex row and every `verdict_is` row would fail |
| M6 | treat an unparseable canary `created_at` as "skip the check" | the missing / unparseable `created_at` rows would exit 5 or 0 instead of 3 |
| M7 | re-introduce the `V_RBY != none` gate | the actor-resolved compliant fixture would no longer pass |
| M8 | compute `quiet_since` without the resolved_at term | the pre-floor-incident-resolved-after-floor boundary pair would diverge |
| M9 | pin moved later than the canary incident start plus slack | the floor-above-canary-incident row would not exit 3 |

**Harness rows.** RED: replace the incident list with `[]` for the compliant fixture (existing harness (a) row) and also
delete the warehouse mock's per-host rows for the compliant fixture: the verdict must change (3 for the former, 5 for the
latter). Must-PASS non-canonical: a fixture with different ids and timestamps, an anchor resolved by an actor, one extra
non-roster host in the rows, and the canary alert already deleted (incident still listed), all of which the contract
explicitly permits.

**Anchor.** The pin is a stored value compared with the thing it protects. A single commit could move the pin later and
hide an incident, so the live canary incident `started_at` (and the canary alert `created_at` while it exists) bound the pin
from above: `FLOOR <= canary_start + SLACK_S` is enforced at run time (exit 3), and M9 proves it. After the canary
incident disappears there is no outside anchor; the RETIREMENT list and the header say so, and the 4 h soak plus the live
shape check remain.

### Guard 2 — The suite's own count floor and anti-vacuity controls

**Property.** The suite cannot go green with rows silently not executing.

**Assembly.** `MIN_ASSERTIONS` (exact-equality floor on the line above its `if`), the instrument self-test, the negative
controls for each assertion helper, the derived-referrer anti-vacuity floor, and `guard-vacuity-floor.test.sh` that slices
the floor line into a mutant.

**Mutation matrix.**

| # | Edit | Must go RED because |
|---|---|---|
| G1 | comment out one Phase 1.3 block | the exact count no longer equals `MIN_ASSERTIONS` |
| G2 | make `run_case` stop recording a forbidden exit 1 | the negative control for `run_case` fails |
| G3 | make `expect_out` always pass | the negative control for `expect_out` fails |
| G4 | add a second `APPLY_FLOOR_EPOCH=` assignment to the SUT | the assigned-once pin fails |

**Harness rows.** RED: lower `MIN_ASSERTIONS` by one (the equality check fires). Must-PASS non-canonical: the suite run
from a different working directory (it resolves `HERE`, not the cwd).

**Anchor.** The floor value is re-derived from a green run, never hand-edited; the repo-wide ratchet
`scripts/guard-vacuity-floor.test.sh` reads the line from outside this file.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "the floor should be the canary alert's creation time (the apply), not the anchor start" | Phase 2.1, 2.3 (pinned `APPLY_FLOOR_EPOCH` = that creation time, cross-checked live) | mapped |
| 2 | "make the anchor's resolve actor informational" | Phase 2.4 (gates deleted, field kept) | mapped |
| 3 | "Pass when the canary has fired, prod_alert=ok, rows are present on both hosts, and no production incident started after the apply for at least 4 h" | Phase 2.4, 2.5 | mapped |
| 4 | "the runbook and ADR-218 still call resolved_by null on auto-resolve ASSUMED; it is now OBSERVED" | Phase 3.1, 3.2 | mapped |
| 5 | "any other doc that describes the probe's pass criteria or the resolved_by assumption (grep the repo for them)" | Files to Edit "Checked and NOT edited"; Phase 3.3 | mapped |
| 6 | "Rule the design change through the CTO agent first." | `decision-challenges.md` (two consults) | mapped |
| 7 | "No Better Stack writes, no canary delete." | Non-Goals; only read-only GETs in Phase 4.2 | mapped |
| 8 | "(c) keep the 10-field verdict line stable or version it; keep exit 1 unused" | Phase 2.6 (first ten fields unchanged, two appended) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| pinned literal instead of a live read | "what happens when that field is missing or unparseable (must fail closed to exit 3, never a pass)" | asked (the live field cannot exist at the exit-0 read; CTO) |
| rows step verdict-bearing on the pass path | "rows_in_window being unknown when the warehouse credentials are absent ... unknown must not pass" | asked |
| retired-canary distinct exit 5 | "must fail closed ... never a pass" | inferred — justification: the existing code already deadlocks if the vendor drops the canary incident with its alert; the CTO ruled the fail-closed exit is a distinct message, not a pass |
| anchor single-vs-list state agreement check | — | inferred — justification: CTO-flagged defect the fix must not leave behind (a disagreement would feed the new ladder an inconsistent anchor) |
| dropping `SOLEUR_FT_EARLIEST` from the stale logic | "versus the sweeper's SOLEUR_FT_EARLIEST" | asked (CTO ruling a) |
| corrective comment on #12189 | "recorded at https://github.com/jikig-ai/soleur/issues/12189#issuecomment-6684919763" | inferred — justification: criterion 2 in the tracker body is now false; one comment, no body edit |

### Split Assessment

- Subsystems touched: 3 — scripts/followthroughs, knowledge-base/engineering/operations, knowledge-base/engineering/architecture
- Planned files: 4 edited + 2 specs | Estimated changed lines: about 650 (suite rewrite dominates)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Two consults (`decision-challenges.md`). Design: pinned floor with live cross-checks, one soak clock, open
pre-floor incidents block, rows verdict-bearing on the pass path, anchor actor informational, ADR amendment not a new ADR,
no C4 change. Second consult withdrew the alert-`updated_at` soak origin after the measurement that it churns every ~5 min.
Product, Legal, Marketing, Finance, Operations, Sales, Support: no implications (internal operator probe, no user data).

## Non-Goals

- Deleting the canary pair or any Better Stack write (owner per-command go-ahead and the standalone ack-destroy line; a later PR; this probe's exit 5 is its signal).
- Changing the alert Terraform, the sweeper, the `earliest=` directive or the tracker's labels.
- A code-level detector that hashes the production alert's resource block beside the pin: documented here, in the probe header and in the ADR amendment instead of filed as an issue (`wg-when-deferring-a-capability-create-a`); the follow-up, if the owner wants it enforced, is a test that hashes the block next to the pin.
- A walk that reaches back past the anchor (the vendor status filter is unverified).
- The heartbeat poller (#12190) and the canary's mirror issue (#12242).

## Acceptance Criteria

- [ ] AC1: Against the compliant fixture (floor 20000 s ago, both hosts with rows, anchor resolved by an actor with `resolved_by` "API"-shaped value, a pre-floor resolved decoy, the canary alert absent and its incident listed, not declared) the probe exits 0 with `anchor_resolved_by=actor` printed. (suite)
- [ ] AC2: A production incident that started before the floor, is resolved, and has `resolved_by` null never sets `newer_prod_incident=1`; one started at floor minus 300 does; one at floor minus 301 does not. (suite, two non-collinear fixtures)
- [ ] AC3: An open exact-name production incident that started before the floor yields exit 2 inside `quiet_since + 15300` and exit 5 after. (suite)
- [ ] AC4: With the soak at 14399 s -> exit 2; 14400 s and 14401 s -> pass path (non-collinear fixtures). (suite)
- [ ] AC5: Warehouse failure / absent credentials / non-row answer / empty roster -> exit 3; a roster host at zero -> exit 5; an extra host never covers a missing roster host. (suite)
- [ ] AC6: A listed canary alert with a missing, unparseable or too-early `created_at`, duplicate canary alerts, a canary incident earlier than floor minus slack, a floor after now, a floor before the anchor's start, and an anchor open-state disagreement between the two reads each yield exit 3. (suite)
- [ ] AC7: Canary alert absent + incident absent + not declared -> exit 5 with text distinct from "DELETED or NEVER CREATED"; declared -> the old text. (suite)
- [ ] AC8: The verdict line has twelve fields in the pinned order; exit 1 is never produced (existing forbidden-exit-1 harness plus the source pin). (suite)
- [ ] AC9: The SUT code does not read `SOLEUR_FT_EARLIEST` or alert `updated_at`, and a fresh or ancient `SOLEUR_FT_EARLIEST` leaves the verdict unchanged. (suite)
- [ ] AC10: `bash scripts/followthroughs/egress-gw-probe-silent-12180.test.sh` is green with `MIN_ASSERTIONS` re-pinned from the green run; it fails against the unmodified probe (recorded in the Phase 1 commit message).
- [ ] AC11: The runbook and ADR-218 contain the OBSERVED wording for incidents 1048111600 (null) and 1047829421 ("API") and a list of what is NOT measured; `git grep -n 'ASSUMED'` over the runbook and the ADR's new amendment returns nothing that is still false; ADR-218's earlier text is byte-identical outside the appended amendment (`git diff` shows additions only in that file).
- [ ] AC12: `egress-gw-alert.test.sh`, `c4-count-parity.test.sh` and `test-argv-bearer-sweep.sh` pass unchanged.
- [ ] AC13: PR body uses `Ref #12189` and `Ref #12180` and no `Closes`; a corrective comment is posted on #12189.
- [ ] AC14: A read-only live run is recorded in the PR body: before 16:16:03Z `verdict=not_yet`; after it, `verdict=action_required` with the delete-the-canary message (the canary is still declared and live), never exit 0 while the canary exists.

## Test Scenarios

1. The compliant pass (AC1) with every field printed, no raw vendor text, no credential in output.
2. 1048111600-shaped decoy: pre-floor, resolved, null resolver -> ignored.
3. A real recurrence after the floor -> exit 5 and the rows read runs diagnostically.
4. Pre-floor open incident, stale and not stale.
5. The warehouse mock failing on the pass path versus failing on the open-incident path (diagnostic only there).
6. Post-deletion shape: canary alert absent, incident listed -> pass; incident dropped -> distinct exit 5.
7. SIGTERM, stray exit, xtrace refusal rows unchanged.

## Risks and Sharp Edges

- **The pin is a stored value.** A reshape of the production alert's evaluated query, `on_missing_data` or `query_period` that
  keeps `higher_than 0` is invisible to the shape check, and the apply history shows no run after 12:14Z as of this plan, so
  the floor equals the last known change. The pin must be re-pinned by hand in the PR that reshapes the alert (header, ADR
  amendment and RETIREMENT list say so).
- **Alert `updated_at` is vendor churn (about every 5 minutes), inferred not measured.** Never use it as a change marker; a
  suite row pins that the SUT does not read it.
- **The slack is asymmetric.** An old-shape incident that started in `[floor - 300, floor)` would count as a recurrence
  forever. Measured against the incident list read at 14:20Z on 2026-11-06: no production incident started in
  `[12:11:03Z, 12:16:03Z)` (1048111600 started 07:45Z and resolved 12:10:00Z), so the window is empty today.
- **Pin provenance.** Apply run 42216140017 ran 12:14:26Z to 12:17:27Z; the canary incident started 12:14:59Z, 64 s before
  the alert's `created_at` 12:16:03.768Z, so the production alert's shape change landed somewhere inside that run, possibly
  before 12:16:03Z. The pin may therefore be later than the true change by up to about 1.6 minutes; the 300 s slack covers
  it. The probe header must say so and cite the run window, not only the single timestamp.
- **A re-created canary needs a re-pin.** Any listed canary incident or alert older than the bound is exit 3, by design.
- **Canary incident survival after alert deletion is still unverified.** The pass depends on it; if the vendor drops it, the
  distinct exit 5 asks for a hand close citing the last `canary=fired` comment.
- **Recurrence is permanent by design.** One production incident at or after the floor keeps returning exit 5 daily until a
  human acts (poller #12190); nobody should "fix" this with a moving floor.
- **`exit` inside `$( )`.** The rows function and every new check must run in the main shell; capture the rc and re-raise.
- **Public output.** Stdout is posted to a public issue (4000 bytes kept). New fields are numbers and fixed tokens; do not
  print the floor's source text, host names outside the roster shape, or any vendor string.
- **A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail
  `deepen-plan` Phase 4.6.** It is filled above.
- **ADR amendment numbering.** ADR-218 is amended in place at its tail; no new ordinal is claimed, so no collision gate applies.
