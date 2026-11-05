---
title: "fix: invert the egress-gateway probe-silence alert metric to a missing-host count and add a canary"
type: fix
date: 2026-11-05
slug: fix-egress-gw-probe-silent-invert-metric
branch: feat-one-shot-12180-egress-gw-probe-silent-invert-metric
issue: 12180
closes: none (PR body carries `Ref #12180` only; the incident mirror closes #12180 when the vendor incident resolves)
domain: engineering
priority: p1-high
brand_survival_threshold: aggregate pattern
lane: cross-domain
---

# fix: invert the egress-gateway probe-silence alert metric to a missing-host count and add a canary

`lane:` defaulted to `cross-domain` (TR2 fail-closed): no `spec.md` exists for this one-shot branch.

## Enhancement Summary

**Deepened on:** 2026-11-05
**Sections enhanced:** Proposed Solution (probe fields, Post-apply decision table), Apply path, Observability, ADR text, Guard 2, ACs
**Agents used:** soleur:engineering:cto (five rulings, before drafting), plan-review panel (DHH, Kieran, code-simplicity), then architecture-strategist, observability-coverage-reviewer, terraform-architect, framework-docs-researcher, learnings-researcher

### Key Improvements

1. A Post-apply decision table covers every evaluator shape (zero-fill, empty window, error-reads-0, canary never created, incident not clearing); "revert" was removed as a response because it restores the shape that misfired.
2. The probe gained the discriminating fields `rows_in_window` and `canary_alert_live`, exits 5 early on a blind canary, and has an explicit exit path when the poller (#12190) replaces it.
3. The Apply path now states the unverified ForceNew question, the `[ack-destroy]` consequence and the alert-id check that stops a replacement from confounding the soak.
4. The Observability block cites layers per failure mode and names the one mode no layer covers.
5. Gate results: 4.6, 4.7, 4.8, 4.11, 4.12 pass; 4.9 and 4.13 do not apply; 4.10 (Encryption Posture) was deliberately skipped: the `.tf` trigger regex matches but the plan adds no persistent store and no cross-component connection (the plan/SKILL skip clause).

### New Considerations Discovered

- The Better Stack docs describe the incidents API on a v3 host while both repo scripts use v2; the probe's first step is one read-only GET against each.
- The canary shares the production query shape, so it cannot distinguish an empty evaluator window; the plan claims only non-zero delivery on an empty count.
- Tracker #12189 and the deferred poller #12190 are filed; the PR links both with `Ref`.

## Overview

The Better Stack Logs alert `soleur-egress-gw-probe-silent-prd` opened incident 1047829421 at
2026-11-05T17:15:00Z while both web hosts were shipping their `egress-gw-probe` rows. An earlier incident from
the same alert (1031046761, open since 2026-10-12) was resolved with owner authorization on the diagnosis "stale
incident, data returned". The fresh incident shows that diagnosis was incomplete: a new false positive opened on a
healthy fleet.

The binding CTO ruling (already made; not re-asked) keeps the same two Terraform resources and changes what they
measure:

1. The query returns the **number of roster hosts that did not emit**, floored at 0 (healthy 0, one dark host 1,
   fully dark 2), and the alert fires on `higher_than 0`. A zero-filled or missing evaluator step now reads
   healthy instead of paging.
2. `on_missing_data = "treat_as_zero"` stays (a fully dark window must remain detectable).
3. A throwaway **canary** alert pair runs the identical query against an identifier no host emits, so it must
   read 2 and fire. If it never fires, the evaluator is blind for this query shape and the production alert
   cannot be trusted.
4. The feeder-fed heartbeat poller (the #11653 pattern, `scripts/deadman-heartbeat-feeder.sh`) is **not built
   here**; it is the declared fallback if the canary stays silent or the incident does not clear.

**Epistemic status, stated in the PR body and the runbooks as required.** The read-only SQL proof (healthy gives
0, web-2 only gives 1, a nonexistent identifier gives 2) proves the **query**. It does not prove **Better Stack's
evaluator**. The zero-fill mechanism (a missing evaluator step is read as 0) is an **inference**: the vendor does
not expose the evaluated value over its read-only API (ADR-218 labels the related hot-window rule INFERRED too).
The canary exists precisely because the mechanism is unproven.

## Research Insights

### Premise Validation (Phase 0.6)

- `gh issue view 12180`: OPEN, the mirror-filed `[ci/betterstack-incident]` issue (labels `priority/p1-high`,
  `action-required`, `ci/betterstack-incident`), incident id marker 1047829421. The mirror
  (`scripts/betterstack-incident-mirror.sh`) closes it when the incident leaves the vendor open list, so the PR
  must say `Ref #12180`, never `Closes`.
- Collision pre-check hit: PR #12186 names #12180. It is this branch's own draft PR (headRefName equals the
  branch). Foreign `test-all.sh` processes belong to two unrelated worktrees. No live duplicate.
- Cited paths all exist on this branch: `egress_gw_probe_silent_sql` (line 1444), both resources (1525, 1546),
  G2 block of `egress-gw-alert.test.sh` (188-235), `-target` lines (apply workflow 667-668), runbook sections
  (`cron-egress-blocked.md` 913, `betterstack-log-query.md` 321).
- **Stale in the brief (reconciled below):** `betterstack-alert-structure.test.sh` is under
  `apps/web-platform/infra/`, not `test/infra/`; it holds census **floors** (minimums), so it very likely needs no
  edit. The `inngest-cutover-flip-silent-alert.test.sh` guard does not pin the egress sibling; only its header
  prose names it.
- The last per-merge apply (run 42072857138, push at 2026-11-05T17:15:38Z) finished `0 added, 0 changed,
  0 destroyed`, so the alert was not touched by an apply when incident 1047829421 opened. An apply-triggered
  re-create is not the cause.
- ADR corpus check (Phase 0.6 item 4): ADR-218 (Terraform-managed Logs alerts; its 2026-10-12 amendment set the
  `count(DISTINCT host_name)` + `lower_than length(var.web_hosts)` shape this plan inverts) and the
  dead-man post-mortem (`deadman-logs-alerts-blind-to-their-own-row-postmortem.md`) are the standing context. No
  ADR rejects an inverted metric or a positive-control canary. ADR-218 gets an amendment (below).
- Apply workflow is `active` (not `disabled_manually`); the last five runs succeeded, so a merge touching
  `apps/web-platform/infra/**` auto-applies.

### Property List and Cut List (Phase 0.6b)

Properties (each an observable outcome):

- P1. A healthy fleet (both roster hosts emitting) never opens an incident.
- P2. A dead, dark or Vector-dropped host still opens one within the existing 900 s window.
- P3. A fully dark window (no rows at all) still opens one.
- P4. The evaluator's ability to deliver a non-zero value for this exact query shape is observed, not assumed.
- P5. The currently open incident 1047829421 clears, and stays clear for at least 4 hours.
- P6. Every claim about the evaluator is labeled inference until P4/P5 are observed.
- P7. The throwaway canary can be removed later without leaving a dangling `-target`, census floor or runbook claim.

Mechanisms named in the ask and what already covers them:

| Mechanism | Property bought | Existing coverage on `origin/main` | Verdict |
|---|---|---|---|
| Invert metric + `higher_than 0` | P1, P2, P3 | none (current shape is `lower_than`) | keep |
| Keep `treat_as_zero` | P3 | already present | keep unchanged |
| Canary alert pair | P4 | none; the read-only SQL proof covers only the query | keep |
| Cron poller | P2/P3 if the evaluator is blind | `scripts/deadman-heartbeat-feeder.sh` pattern exists | **cut from this PR** (fallback only, per the ruling) |
| Manual incident resolve | P5 | none, and it is a Better Stack write | **cut** (needs the user's per-command go-ahead; not planned) |

Cut List: poller build (fallback only); hand-resolving incident 1047829421 (production write beyond the
per-merge apply); re-arming the paused `inngest_cutover_flip_silent` with the inverted shape (needs measured
evidence first; see Decision Classes).

### Institutional learnings applied

- `deadman-logs-alerts-blind-to-their-own-row-postmortem.md`: an alert accepted without proving its evaluator can
  see the row read `Current value: 0` for 33 nights; the vendor value is unobservable via the read-only API. This
  is why the canary is a hard requirement, not a nicety.
- `2026-11-02-three-hand-copied-lists-and-an-alert-claim-that-outran-its-emitter.md`: adding a resource of a class
  moves exact counts in several hand-copied places; grep a sibling resource name at plan time (done below) and
  verify every universal sentence in alert comments against the emitter.
- `test-failures/2026-10-31-a-guard-floor-constant-is-two-write-sites-not-one.md`: `PRESENCE_ROWS` has two write
  sites (the declaration and the `mutate_floor_red` sed anchor). Re-run the battery after changing it.
- `2026-07-24-count-vs-floor-guard-single-value-fixtures-cannot-discriminate-operator.md`: probe fixtures must sit
  off collinear points (window exactly 4 h, 4 h minus 1 s, 4 h plus 1 s).
- `2026-06-17-terraform-target-parity-test-guards-only-terraform-data-subset.md`: the parity test does not cover
  `logtail_*`; `egress-gw-alert.test.sh` and the structure suite (rows 21-22) are the only `-target` enforcement.
- ADR-231 / `workflow-file-size.test.ts`: `apply-web-platform-infra.yml` is 489,718 bytes against a 490,000-byte
  gate. Two `-target` lines add about 160 bytes and fit; no comment prose may be added to that file.

### CTO rulings obtained during planning (this session)

Ruled by CTO agent, 2026-11-05 (recorded in `decision-challenges.md`): F1 canary `email = true`; F2 derive the
canary SQL with `replace()`; F3 interpolated `greatest(toInt64(roster) - toInt64(count(DISTINCT host_name)), 0)`;
F4 soak probe reads the Better Stack incidents API, one tracker, exit 5 "delete the canary" until the canary is
gone; F5 canary silent 20 minutes after apply completion means the evaluator is blind for this shape, leave the
production alert armed and build the poller. Named residual from the CTO: with `treat_as_zero` kept, an evaluator
error or timeout reads 0, so the inverted alert goes quiet where the old metric would have fired; the canary
proves only the empty-count path, not the error path.

## Research Reconciliation: Brief vs. Codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| Update pinned test `betterstack-alert-structure.test.sh` | It is `apps/web-platform/infra/betterstack-alert-structure.test.sh`. Census floors (`CENSUS_FLOOR_ALERTS=18`, `..._EXPLORATIONS=18`, `GUARD_CENSUS_FLOOR=17`) are minimums, not exact counts; adding a pair keeps them green. Rows 9-10 require one alert per exploration with identical resource names; rows 21-22 require a `-target` per logtail resource. | Run it; edit only if a row reds. Name the canary pair `egress_gw_probe_silent_canary` for both resources. |
| Update `inngest-cutover-flip-silent-alert.test.sh` | It does not pin the egress sibling. Header lines 35-37 say the sibling "shows the same stuck-at-0". It does pin `PAUSED PENDING #11869` and `# Paused pending #11869`. | Comment-only reword of those header lines; do not touch the pinned strings. |
| `infra-validation.yml` ~line 995 | Lines ~990-994 are the comment above the step; the step name is pinned by mutation rows in `egress-gw-alert.test.sh` | Reword the comment only; keep the step name byte-identical |
| Add canary `-target` lines | One `-target` list, all inside the `apply:` job; 282 bytes of headroom to the 490,000-byte gate | Add exactly two lines, no prose |
| (unstated) exact-count suites | `logs-alert-query-period-ceiling.test.sh` has `EXPECT_BLOCKS=18` and `MIN_PASSES=116` compared with `!=`; `betterstack-send-failed-alert-mutation.test.sh` asserts `count == 18` for `values = [local.vector_prd_source_id]` | Both move +1 with the canary and -1 when it is deleted; listed in Files to Edit and in the follow-up RETIREMENT list |
| (unstated) post-deploy soaks | `scripts/followthroughs/post-deploy-incident-soak.sh` fails on ANY new incident or `ci/` issue in its window | The canary's incident and mirror issue would fail any such soak enrolled while it is live; documented in Risks (none are enrolled today, checked with `gh`) |

## Open Code-Review Overlap

None for the alert, test, workflow, runbook and TF files. Acknowledged, different concerns, left open:
#8735 and #7942 (touch `infra-validation.yml` / `scripts/test-all.sh`: unrelated job-cancel and `*.mutation.sh`
gating), #11312, #10464, #10463, #10462, #8435 (touch other probes under `scripts/followthroughs/`).

## Problem Statement

Observed facts (read-only): the production alert's incident 1047829421 is open while both hosts ship probe rows;
a prior incident from the same alert stayed open for 24 days with data present. The sibling
`inngest_cutover_flip_silent` showed the same "stuck at `Current value: 0`" and was paused (#11869). The common
shape is a `lower_than N` silence alert over `treat_as_zero`: any evaluator step that reads 0 pages it, and the
alert cannot distinguish "no rows" from "evaluator produced no value".

Inference (not measured): the evaluator zero-fills a step it cannot evaluate and then compares 0 against the
threshold. Under `lower_than 2` that reads as a false page; under the inverted `higher_than 0` shape the same
zero reads healthy.

## Proposed Solution

### Production SQL (the `egress_gw_probe_silent_sql` local, heredoc kept)

```sql
SELECT toDateTime({{end_time}}) AS time, greatest(toInt64(${length(var.web_hosts)}) - toInt64(count(DISTINCT JSONExtractString(raw, 'host_name'))), 0) AS value
FROM {{source}}
WHERE dt BETWEEN {{start_time}} AND {{end_time}}
  AND JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'egress-gw-probe'
```

- Whole-window scalar, no `GROUP BY`: an aggregate without `GROUP BY` always returns one row, so a fully dark
  window returns the roster size (2) rather than "no data".
- `toInt64` on both operands: ClickHouse `count()` is unsigned and an unsigned subtraction wraps on a surplus of
  emitting hosts; the floor needs a signed operand.
- The roster size is interpolated from `var.web_hosts` (one source of truth with the former
  `lower_than length(var.web_hosts)`), not a literal 2.
- Accepted pre-existing residual (CTO F3, named in the alert comment): the metric compares a distinct-host COUNT
  to the roster size, not set identity, so an extra or renamed emitter could mask a dead host.

### Production alert

`operator = "higher_than"`, `value = 0`, everything else unchanged (`check_period 300`, `query_period 900`,
`confirmation_period 0`, `recovery_period 900`, `treat_as_zero`, `paused = false`, email only). `incident_cause`
is reworded to say the value is the number of roster hosts that did not emit, and the comment above the alert
states: the evaluator mechanism is an inference; the residual that an evaluator error reads 0; a green alert is
not evidence of health until the canary has fired.

### Canary pair (throwaway, reversible by deleting the two resources)

```hcl
egress_gw_probe_silent_canary_sql = replace(local.egress_gw_probe_silent_sql, "'egress-gw-probe'", "'egress-gw-probe-canary-absent'")
```

Placed after the `egress_gw_probe_fail_sql` local so the existing anchors in the mutation battery do not drift.
Resources `logtail_exploration.egress_gw_probe_silent_canary` and
`logtail_exploration_alert.egress_gw_probe_silent_canary`, Better Stack name
`soleur-egress-gw-probe-silent-canary-prd`, `higher_than 0`, same windows and `treat_as_zero`, `paused = false`,
`email = true` (the tested sibling shape; CTO F1), `push`/`call`/`sms`/`critical_alert` false, the same free/paid
`escalation_target` ternary, `metadata.runbook` the existing egress runbook URL. `incident_cause` begins with
`THROWAWAY CANARY (#12180)` and says it is expected to fire and is not an outage.

Expected behavior: the canary reads 2 and opens one incident that never recovers (the query is constant). That
incident is mirrored as a P1 `action-required` issue by `betterstack-incident-mirror.sh`. Both are expected and
last until the follow-up deletes the pair (incidents close minutes after their alert is deleted, observed in
#11631).

### Soak verification probe (new; CTO F4)

`scripts/followthroughs/egress-gw-probe-silent-12180.sh` is enrolled on one tracker issue. It reads the Better
Stack incidents API (the `send-failed-alert-probe-8097.sh` pagination and projection pattern), the Telemetry alert
listing (does the canary alert exist live) and, for the discriminating field, `scripts/betterstack-query.sh`. The
credentials `BETTERSTACK_API_TOKEN` and the three `BETTERSTACK_QUERY_*` names are already bound in the
sweeper. **Pre-step (UNVERIFIED host):** Better Stack's current public docs describe the incidents API at
`https://incidents.betterstack.com/api/v3/incidents` (fields `name`, `cause`, `started_at`, `resolved_at`, `status`;
newest first; `pagination.next`), while both repo scripts call `https://uptime.betterstack.com/api/v2/incidents`.
Before writing the probe, make one authenticated read-only GET against each host and use the one that answers (v2 if
it still serves, since two working scripts depend on it); record the choice in the probe header. Also unconfirmed:
whether Logs-alert incidents appear in that list without a filter (the mirror issue for #12180 shows they do on the
host the mirror reads).

| Verdict | Exit | Condition |
|---|---|---|
| `pass` | 0 | incident 1047829421 resolved at least 4 h ago, no later incident named `soleur-egress-gw-probe-silent-prd`, a canary incident exists, AND the canary resources are no longer declared in the checkout's `betterstack-logs-alerts.tf` |
| `not_yet` | 2 | incident 1047829421 still open (and no condition below holds) or resolved less than 4 h ago |
| `unknown` | 3 | any read failure, unparseable payload or truncated page |
| `action_required` | 5 | any of: `canary=absent` with `canary_alert_live=1` (evaluator blind for this shape: poller #12190, production alert stays armed); `canary=absent` with `canary_alert_live=0` (the apply never created it: fix the apply, not an evaluator finding); a production incident that started after 1047829421 resolved (recurrence); incident 1047829421 still open more than 4 h after `earliest` (poller or a pause; the tracker is then closed in favor of #12190 with its label removed, so it has no dead end); or all verification held but the canary is still declared (delete it). These do not wait for the 4-hour window: the sweeper runs from `earliest`, which is apply completion plus 30 minutes |
| xtrace refusal | 78 | #7797 |

Incidents are matched on `.attributes.name ==` the exact alert name for both the production and the canary alert
(the 8097 probe's `name or cause-prefix` match would count a canary cause as a production recurrence). The probe reads
`BETTERSTACK_API_TOKEN` (bound in the sweeper); the post-merge run maps `BETTERSTACK_API_TOKEN_READONLY` (Doppler
`prd_terraform`) into that name for one invocation, never on argv.

The verdict line carries one field per condition so a caller can read any of them regardless of the overall
verdict: `SOLEUR_EGRESS_GW_SILENT_SOAK verdict=<v> prod_incident=<open|resolved|unknown> resolved_age_s=<n>
newer_prod_incident=<0|1> canary=<fired|absent|unknown> canary_alert_live=<1|0|unknown> canary_declared=<0|1>
rows_in_window=<host:n,...>`. `rows_in_window` is read only when a production incident is open or newer: per-host
counts (never row content) of `egress-gw-probe` rows over that incident's `started_at` to `resolved_at` (or now),
the one field that separates an evaluator fault (rows present on both hosts) from an emitter or ingest fault (a
host with none). The `canary=` field is what the post-merge step reads at apply completion plus 25 minutes
(AC12). On any read failure the probe prints the HTTP status and the byte length only, never a response body.

Sweeper action per code: 0 closes the tracker (so it must be unreachable while the canary is declared); 2, 3 and
78 are transient and retried next sweep; 5 comments `ACTION REQUIRED` and leaves it open; 1 is never used (the
sweeper reads it as FAIL and may reopen a human-closed tracker). Output is projected to
`{id,name,started_at,resolved_at}` (public-comment discipline).

### Post-apply decision table

| Observation | Reading | Response |
|---|---|---|
| canary incident exists, 1047829421 resolves within the soak | evaluator delivers a non-zero value for an empty count; the inverted shape works | delete the canary (AC14); soak completes |
| `canary=absent`, `canary_alert_live=1` after 25 minutes | evaluator reads 0 for this query shape | poller #12190; production alert stays armed; a green alert is not evidence of health |
| `canary=absent`, `canary_alert_live=0` | the apply did not create it (alert-count cap refusal or a failed create) | hotfix PR; not an evaluator finding |
| 1047829421 still open, `rows_in_window` shows rows on both hosts | empty-window read or vendor never auto-resolving (the 24-day incident 1031046761 precedent) | poller #12190, or a pause; a manual resolve is a Better Stack write needing the user's per-command go-ahead; never a revert (a revert restores the shape that misfired) |
| 1047829421 still open, a host has no rows | real silence | the existing runbook ladder (host repair); the alert is right |
| new production incident while 1047829421 is already open | cannot be observed: Better Stack keeps one open incident per alert, so AC12b is read from the open incident's state, not from a second incident | as the rows above |
| evaluator error or timeout reads 0 | false silence; undetectable by this alert | accepted residual of the CTO ruling; the sibling detectors cover only a fleet-wide dead resolver timer and a failing probe (a Vector or journal break on one host has no independent detector); #12190 is the tracked mitigation |

## Implementation Phases

### Phase 1 - Tests first (`cq-write-failing-tests-before`)

1.1 Edit the G2 block of `apps/web-platform/test/infra/egress-gw-alert.test.sh` to the new canon (flattened
heredoc equality, `higher_than`/`0`, `treat_as_zero`, unpaused, email, own exploration, both `-target` lines) and
add a **G2b** block for the canary (see Guard Contract). Run it: RED against the unchanged `.tf`. Specifics the
review found in the existing file: (a) the byte-exact canon is a double-quoted `[ "$X" = "SELECT ..." ]` string, so a
literal `${length(var.web_hosts)}` raises "bad substitution" and kills the suite; write the canon with `\${` or from
single-quoted segments. (b) `sql_local` only extracts `<<[-]SQL` heredocs and returns empty for the canary's
`replace()` local, so pin that line with an anchored whole-line `grep -cE` count of exactly 1 and compare it whole.
(c) The existing mutation rows for the silent alert break on the new SQL and are REWRITTEN, not kept: the
`count(DISTINCT ...)) AS value` anchor, the `value = length(var.web_hosts)` anchor, and the flip to `higher_than`
(now a no-op). (d) The header prose ("All six resources"), the opener loop, the resource-header loop and the
"no mute knob in any resource block" negative row (six blocks) all gain the canary blocks. (e) Add an exact-count
row for resources named `egress_gw_probe_silent*` (4), because the structure suite's rows 1-4 are floors and rows
9-10 pass for a second canary that has its own exploration.
1.2 Write the probe suite `scripts/followthroughs/egress-gw-probe-silent-12180.test.sh` (PATH-shimmed `curl`/`gh`
fixtures, synthesized responses only) before the probe: RED with the probe absent.

### Phase 2 - Production change

2.1 `betterstack-logs-alerts.tf`: new SQL, alert operator/value/comment/`incident_cause`, canary local and the two
canary resources, comment refresh of the flip-silent block (lines mentioning `egress_gw_probe_silent`), the
header comment of the egress section ("pages when the emitting-host count drops below the roster" becomes the
missing-count wording).
2.2 `apply-web-platform-infra.yml`: two `-target` lines after the `egress_gw_probe_fail` pair, nothing else. Check
`wc -c` stays at or below 490,000.
2.3 Re-prove the **final** SQL text read-only (CTO-independent AC): with the Doppler `prd_terraform` read
credentials, run `scripts/betterstack-query.sh` in raw-SQL mode substituting `{{source}}` with
`remote($BS_TABLE)`, `{{start_time}}` with `now() - INTERVAL 15 MINUTE` and `{{end_time}}` with `now()`. Three
cases: unchanged text (expect 0), an added `AND JSONExtractString(raw,'host_name') = 'soleur-web-2'` conjunct
(expect 1), and the canary identifier (expect 2). Record counts only in the PR body. If the credentials are
unavailable in the session, say so in the PR body instead of asserting the proof.
2.4 Read-only vendor count (names and counts only, never payloads): list the live Logs alerts through the
Telemetry API to confirm the free-tier cap (undocumented; at least 17 observed, 18 TF-managed plus one hand-made
today) can take one more. Pre-decided fallback if the post-merge apply is refused on count: remove the canary
pair in a hotfix PR and proceed straight to the poller (the refusal fails the whole push apply, so it surfaces on
this merge).

### Phase 3 - Dependent exact counts

3.1 `logs-alert-query-period-ceiling.test.sh`: `EXPECT_BLOCKS` 18 to 19 and re-derive `MIN_PASSES` by running it.
3.2 `betterstack-send-failed-alert-mutation.test.sh`: `count == 18` to `19` and the comment's list of explorations.
3.3 Run `betterstack-alert-structure.test.sh`; edit only if a row reds. Expected: green with no edit.
3.4 `egress-gw-alert.test.sh`: re-derive `PRESENCE_ROWS` and `MUT_ROWS` after the rows are final (both write
sites of each constant), and refresh its header prose.
3.5 `inngest-cutover-flip-silent-alert.test.sh` header lines 35-37 comment reword. Pinned strings untouched.

### Phase 4 - Probe, registration, docs

4.1 Write the probe (green the Phase 1.2 suite). Register the suite like `send-failed-alert-probe-8097`:
`scripts/test-all.sh` (`run_suite`), `scripts/suite-shard-legs.tsv`, `scripts/lib/test-affected-paths.sh`, and
whatever `scripts/lint-betterstack-emitter-read.sh` requires for a probe that reads the `.tf`; run that lint and
the registration gates to find the full set.
4.2 `infra-validation.yml` comment above the egress step (step name unchanged).
4.3 Runbooks: `cron-egress-blocked.md` section `#### soleur-egress-gw-probe-silent-prd` (rename the heading
suffix, new metric, canary section, inference label, evaluator-error residual, interpretation of canary
silence); `betterstack-log-query.md` bullet (~321-331: replace the "lower_than ... may stay open ... resolve
manually" sentences, which no longer describe this alert, with the inverted-shape and canary text; fix the
flip-silent bullet's "same stuck-at-0 shows on egress_gw_probe_silent" sentence, ~line 359). No guard pins those
sentences (checked with `git grep`), but the `.tf` comment at the flip-silent block says the two bullets and the
comment are edited together. Triage order in the rewritten `cron-egress-blocked.md` section stays no-SSH: the canary
and incident reads (probe verdict line, `betterstack-query.sh`) come first, then Sentry, and any host-timer repair is
named by its webhook verb, never by a `systemctl` login.
4.4 ADR-218 amendment (below).
4.5 Tracker issue #12189 (filed during planning, milestone Post-MVP / Later, labels type/chore, domain/engineering,
priority/p2-medium, observability; open, no directive yet): at ship add the `follow-through` label and the column-0
directive (see Acceptance Criteria). The PR body links it with `Ref #12189`, never `Closes`.

### Phase 5 - Verify

Run, in this order: `egress-gw-alert.test.sh`, `betterstack-alert-structure.test.sh --presence-only`,
`logs-alert-query-period-ceiling.test.sh`, `betterstack-send-failed-alert-mutation.test.sh`,
`inngest-cutover-flip-silent-alert.test.sh`, the probe suite, `plugins/soleur/test/c4-count-parity.test.sh`,
`bun test plugins/soleur/test/workflow-file-size.test.ts`, `python3 scripts/lint-guard-contract.py`, then
`scripts/lint-orphan-test-suites.sh` (the new probe suite must be reported registered, not orphaned), the repo's
affected-tests runner, a scratch-worktree dry run of the Rollback recipe, and `technical-ruling-gate.sh --branch`
(ship skill `scripts/`) on `decision-challenges.md`.

## Files to Edit

- `apps/web-platform/infra/betterstack-logs-alerts.tf` (SQL local, silent alert, canary local + pair, comments)
- `.github/workflows/apply-web-platform-infra.yml` (two `-target` lines)
- `.github/workflows/infra-validation.yml` (comment above the egress step only)
- `apps/web-platform/test/infra/egress-gw-alert.test.sh` (G2 rewrite, G2b canary, mutation rows, row constants)
- `apps/web-platform/test/infra/inngest-cutover-flip-silent-alert.test.sh` (header comment only)
- `apps/web-platform/infra/betterstack-alert-structure.test.sh` (run; edit only on red)
- `apps/web-platform/test/infra/logs-alert-query-period-ceiling.test.sh` (`EXPECT_BLOCKS`, `MIN_PASSES`)
- `apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh` (`18` to `19` and comment)
- `knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md`
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`
- `knowledge-base/engineering/architecture/decisions/ADR-218-native-better-stack-logs-alerts-are-terraform-managed-via-the-logtail-provider.md` (amendment)
- `plugins/soleur/test/preflight-discoverability-test.test.ts` (`BASELINE_DECLARED_PROBES` 94 to 95 with the
  PLACEMENT/TRUTH/NO-SUBSTITUTE comment: this plan declares `credentials_required`)
- `scripts/test-all.sh`, `scripts/suite-shard-legs.tsv`, `scripts/lib/test-affected-paths.sh`,
  `scripts/lint-betterstack-emitter-read.sh` (registration, mirroring the 8097 probe; each entry must name the
  consumer that reads it for this diff shape, and an entry nothing consults is dropped, not kept)

## Files to Create

- `scripts/followthroughs/egress-gw-probe-silent-12180.sh`
- `scripts/followthroughs/egress-gw-probe-silent-12180.test.sh`
- `knowledge-base/project/specs/feat-one-shot-12180-egress-gw-probe-silent-invert-metric/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-12180-egress-gw-probe-silent-invert-metric/decision-challenges.md`

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-218 (do not create a new ADR): append `## Amendment - 2026-11-05 (#12180): absence alerts on a
multiplexed source report a missing-host count; a positive-control canary accompanies any new evaluator shape`,
scoped to sub-900 s host-roster absence alerts. Format of the 2026-10-31 dead-man amendment: a Preserved list and a
Superseded-by-name list. Preserved: the 2026-10-12 rule to count emitting HOSTS, never rows. Superseded: only its
comparator (`lower_than length(var.web_hosts)`) and what replaces it. It must also state the inversion of ADR-197's
"a zero from a log surface is not evidence of absence" and the 2026-10-31 "never reads a zero as healthy" posture:
this alert reads a zero as healthy, the accepted failure direction moves from false page to false silence, and the
canary plus the sibling detectors are the compensating controls. Further contents: the evidence (incident 1047829421, the 24-day stale incident, the paused flip-silent sibling) and the
explicit INFERRED label on the zero-fill mechanism; the canary and its decision rule (the Post-apply decision table above); the evaluator-error residual; the alert count
(19 Terraform-managed once applied, 18 after the canary is deleted) with the live count read in Phase 2.4; the
Alternatives Considered row for the feeder-fed heartbeat poller (rejected as the first move, kept as fallback) and
for dropping `treat_as_zero` (rejected by the CTO: a fully dark window must stay detectable). Appended, not edited.

### C4 views

No C4 element change. Checked against all three model files (`model.c4` 274,732 B, `views.c4`, `spec.c4`):
(a) external human actors: none added (the founder wake path from `betterstack` is already modeled); (b)
external systems: Better Stack (`betterstack`, `model.c4` ~514) and its edges to github (incident mirror, ADR-298)
already exist; no new vendor; (c) containers/data stores: none; (d) actor-surface access relationships: unchanged.
The derived-cardinality gate is verified by running `plugins/soleur/test/c4-count-parity.test.sh` (Phase 5), not by
reasoning.

### Sequencing

The ADR amendment lands in this PR and describes the target state; the canary-removal note is "adopting" until the
tracker closes.

## Infrastructure (IaC)

### Terraform changes

`apps/web-platform/infra/betterstack-logs-alerts.tf` only: the logtail provider is already pinned
(`BetterStackHQ/logtail`, lock 11.2.0). No new variable, secret, provider or root. The two new resources use the
same `team_name = "Your team"`, `local.vector_prd_source_id` and escalation ternary as their siblings.

### Apply path

Per-merge push apply (`apply-web-platform-infra.yml`, active). The change is update-in-place for the two existing
resources and create for the pair. Expected plan: `2 added, 1 or 2 changed, 0 destroyed`. **RESOLVED at work time (2026-11-06):** the provider source at the pinned tag v11.2.0 carries `ForceNew` exactly once across
`resource_exploration.go`, `resource_exploration_alert.go` and `alert_shared.go`: on the alert's `exploration_id`. So a
`sql_query` change on `logtail_exploration` and an `operator`/`value` change on the alert are UPDATE-IN-PLACE (a read-only
plan could not be taken: the R2 backend needs Terraform >= 1.10 and this host has 1.9.8). Previously unverified: whether a
`sql_query` change on `logtail_exploration` (and `operator`/`value` on the alert) is update-in-place or ForceNew;
the pinned provider binary (11.2.0) only carries generic `ForceNew`/`RequiresReplace` strings and the repo records
no per-attribute result. The precedent that changed the same fields is #10133 (commit dff05deff5): cite its apply
output, or take a read-only plan from a session with backend access, before merge and record the counts here.
Two consequences if the exploration is replaced: (1) the push apply's destroy-guard counts it (`resource_deletes`)
and demands `[ack-destroy]` on its own line in the merge commit, so a plan showing a destroy needs that line or the
merge is refused; (2) `exploration_id` parents the alert, so the alert is replaced too, and deleting the old alert
closes incident 1047829421 for a reason unrelated to the evaluator, which confounds the 4-hour soak (P5). The
postmerge step therefore reads the alert id before and after (Telemetry alert listing, names and ids only) and the
soak counts the resolution only if the id is unchanged; on a replacement the 4-hour clock restarts from the new
alert's first healthy evaluation. No downtime.

### Host fan-out

Not applicable: no `terraform_data` SSH provisioner is touched.

### Distinctness / drift safeguards

The structure suite forbids `lifecycle`, `count`, `for_each` in alert and exploration blocks, so "reversible" means
deleting the two resources in a follow-up PR; the reconciler's `logs_alert` arm (`logs-alert-absent` /
`logs-alert-paused`) automatically covers the new alert once it exists live.

### Vendor-tier reality check

Free-tier alert-count cap is undocumented (at least 17 observed live). Phase 2.4 reads the live count read-only;
fallback pre-decided above.

## Observability

```yaml
liveness_signal:
  what: the production alert value (missing roster hosts, 0 when healthy) and the canary incident, both read through the Better Stack incidents API by the soak probe
  cadence: alert checked every 300 s over a 900 s window; probe run once by the postmerge step at apply completion plus 25 minutes, then by the daily 18:00 UTC follow-through sweeper from earliest (apply completion plus 30 minutes)
  alert_target: team email plus a mirrored GitHub issue (ci/betterstack-incident, action-required, priority/p1-high)
  configured_in: apps/web-platform/infra/betterstack-logs-alerts.tf (egress_gw_probe_silent, egress_gw_probe_silent_canary)

error_reporting:
  destination: Better Stack incident, mirrored by scripts/betterstack-incident-mirror.sh into a GitHub issue; the sweeper comments on the tracker
  fail_loud: incident_cause text naming the missing-host count and the runbook anchor; probe stdout verdict line

failure_modes:
  - mode: one roster host stops emitting (timer, Vector allowlist, journal)
    detection: layer 3 (vector, host journald to Better Stack): production alert value 1 for a full window
    alert_route: email plus the mirrored issue; the soak probe's rows_in_window field names the silent host
  - mode: both hosts dark or the source dead
    detection: layer 3 (vector): production alert value 2 (the aggregate always returns a row)
    alert_route: email plus the mirrored issue
  - mode: evaluator reads 0 regardless of data (blind for this query shape) while the canary alert exists live
    detection: layer 6 (workflow run log of the sweeper and the postmerge probe run): canary=absent with canary_alert_live=1, 25 minutes after apply completion
    alert_route: tracker comment (exit 5) and the postmerge report; response is the poller (#12190), production alert stays armed
  - mode: canary alert never created (apply refused on the free-tier alert cap, or the create failed)
    detection: layer 6 (workflow run log of the apply, and the probe's canary_alert_live=0)
    alert_route: apply run failure; response is a hotfix PR removing the canary and then the poller, not a blindness finding
  - mode: production incident on a healthy fleet, or incident 1047829421 not clearing (empty-window read, vendor never auto-resolving, or real silence)
    detection: layer 6 (probe verdict line) with the discriminating field rows_in_window=<host:n,...> over that incident's started_at to resolved_at (rows present on both hosts means evaluator fault; absent means emitter or ingest fault)
    alert_route: tracker comment (exit 5); response is the poller (#12190) or a pause, each needing the user's per-command go-ahead for any Better Stack write
  - mode: evaluator error or timeout reads 0 under treat_as_zero (false silence)
    detection: no layer covers this; accepted residual of the CTO ruling, the failure direction moved from false page to false silence
    alert_route: not alerted; the sibling detectors (Sentry cron check-in without a host dimension, op egress_gw_probe_fail on result=fail rows) cover only a fleet-wide dead timer and a failing probe, and #12190 is the tracked mitigation

logs:
  where: Better Stack Logs source 2457081 (rows tagged egress-gw-probe, one per 5 minutes per host); incident history via the uptime API
  retention: hot window about one hour, then the archive (measured in the dead-man post-mortem)

discoverability_test:
  command: bash scripts/followthroughs/egress-gw-probe-silent-12180.sh
  expected_output: SOLEUR_EGRESS_GW_SILENT_SOAK verdict=
  credentials_required: BETTERSTACK_API_TOKEN, BETTERSTACK_QUERY_HOST, BETTERSTACK_QUERY_USERNAME and BETTERSTACK_QUERY_PASSWORD (read scope, from Doppler soleur/prd_terraform) - the incident list and the alert listing are not exposed by any unauthenticated endpoint, so no anonymous probe verifies the same property; the probe is a single short read sequence and fits the 15 s cap if the waiver is ever dropped
```

## Guard Contract

### Guard 1 - egress-gw-alert drift guard (inverted metric plus canary)

**Property.** The production silence alert pages if and only if at least one roster host is missing, and the canary
is a faithful, always-firing positive control of the same query shape.

**Assembly.** Everything the property quantifies over, read through one chokepoint (`sql_local` / `res_block` over
`betterstack-logs-alerts.tf`, `APPLY_JOB` over the workflow): (1) the flattened production heredoc compared whole
to a pinned canon containing the literal `${length(var.web_hosts)}`; (2) the production alert block (operator,
value, `treat_as_zero`, paused, email, exploration binding); (3) the canary local line, exploration block and
alert block; (4) all four `-target` lines in the `apply:` job; (5) the sibling exact-count suites
(`EXPECT_BLOCKS`, `count == 18`) that must move with the canary; (6) the guard's own dispatch (`PRESENCE_ROWS`,
`MUT_ROWS`). The canary SQL is derived, so it has exactly one producer; the guard asserts the derivation line
appears exactly once, that the replacement identifier is not any `logger -t` tag in `cron-egress-resolve.sh`, and
that canary and production differ.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | production operator reverted to `lower_than` | RED (fragment: `higher_than`) |
| 2 | production `value` raised from `0` to `1` (one missing host no longer pages) | RED |
| 3 | any edit to the production SQL canon: the `greatest(... , 0)` floor dropped, the `toInt64` casts removed, or the roster interpolation replaced by a literal `2` (one byte-exact comparison covers all three) | RED (byte-exact canon) |
| 4 | `DISTINCT` regresses to `count(*)` (host-mask defect) | RED (existing row kept) |
| 5 | production `on_missing_data` changed from `treat_as_zero` | RED |
| 6 | canary derivation line deleted (resource points at the production local) | RED |
| 7 | canary `replace()` target no longer matches (silent no-op, canary equals production) | RED |
| 8 | canary identifier set to the real tag `egress-gw-probe` | RED (anti-collision row) |
| 9 | canary alert `paused = true` or operator `lower_than` | RED |
| 10 | either canary `-target` line removed from the workflow's allowlist | RED |
| 11 | `PRESENCE_ROWS` bumped one past the real count | RED (floor row, dispatch) |
| 12 | the guard's own `run:` line removed from `infra-validation.yml` | RED (existing row kept) |
| 13 | a SECOND canary-like resource pair added after the compliant first (`..._canary2`) | RED (the guard's exact count of `egress_gw_probe_silent*` resources, plus `EXPECT_BLOCKS` in the ceiling suite) |

**Harness rows.** (a) Suite edit that must RED: drop the canon comparison line for the production heredoc from a
scratch copy of the suite and require the dispatch floor to fail (assertion count below the floor). (b) Must-PASS
non-canonical input: whitespace reflow of the production heredoc (still equal after flattening) and a
comment-only edit to the `.tf` stay green, so a guard that rejects everything cannot pass.

**Anchor.** The pinned canon, the `18` and `19` counts and the floors are stored in the same diff as what they
protect, so a deliberate in-diff edit passes: the suite proves consistency, not integrity. The external anchor is
review plus the live check: the canary incident observed in the vendor API 20 minutes after apply (the soak probe)
and the reconciler's `logs-alert-absent` arm.

### Guard 2 - soak probe verdict suite

**Property.** The probe returns PASS only when incident 1047829421 was resolved at least 4 hours ago, no newer
production incident exists, a canary incident exists, and the canary is no longer declared; it never exits 1 and
never reports PASS on an unanswered read.

**Assembly.** The incident list (paged, newest first, stopping at the anchor), the single-incident read, the `.tf`
read, the clock, and every exit path of the script (a `trap`-remapped status included). One chokepoint: a single
`verdict()` function that prints the marker line and sets the exit code, so no path can exit without a verdict.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | resolved_at exactly 4 h minus 1 s ago | RED if the probe exits 0 (must be `not_yet`) |
| 2 | incident list truncated (next page present, anchor not reached) | RED if the probe exits 0 (must be `unknown`) |
| 3 | no canary incident in an otherwise healthy fixture | RED if the probe exits 0 (must be `action_required`) |
| 4 | canary still declared in the fixture `.tf` with every other condition true | RED if exit is 0 (must be 5) |
| 5 | a SECOND production incident started after resolved_at while the first is compliant | RED if exit is 0 |
| 6 | the probe exits 1 on any fixture | RED (exit-1-never row) |
| 7 | curl returns HTTP 500 or empty body | RED if exit is 0 (must be 3) |
| 8 | tracing enabled with a bearer set | exit 78 |
| 9 | an API failure whose body contains a bearer-shaped string or credential name | the output carries the HTTP status and byte length only (no body, no echoed credential) |
| 10 | canary absent while the canary alert is also absent from the live listing | `canary_alert_live=0`, not the blind-evaluator verdict |
| 11 | production incident open with one roster host missing from `rows_in_window` | the field names that host; verdict stays `action_required` |

**Harness rows.** (a) Suite edit that must RED: replace the shimmed incident payload with `[]` for every case; the
healthy case must change verdict. (b) Must-PASS non-canonical: a healthy fixture whose incident ids and timestamps
differ from the canonical, and one with resolved_at exactly 4 h plus 1 s ago.

**Anchor.** Fixtures are synthesized (`cq-test-fixtures-synthesized-only`); the live anchor is the tracker's first
sweeper comment (run with `dry_run=true` before enrolling, per the follow-through convention).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly on the product surface. The egress gateway's
  allow/deny verification could go dark on a host while the alert reads green, so a mis-ACL'd or absent gateway
  would not page the owner; or a false page keeps an `action-required` P1 issue open on a healthy fleet.
- **If this leaks, the user's [workflow] is exposed via:** no data path changes. The only new text is a Better
  Stack alert definition and a probe that prints incident id, name and timestamps; no credential or workspace data
  reaches an issue comment.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** an undetected gateway-verification gap would widen the window for an
  agent-session egress problem, but this alert is one of several detectors (Sentry `egress_gw_probe_fail`, the deny
  spike alert, the resolver's own check-in) and it protects an internal control, not a single user's data; so
  not `single-user incident`.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "Invert the metric to the count of missing probe hosts, floored at 0" [brief] | Proposed Solution (production SQL), Phase 2.1 | mapped |
| 2 | "set the alert to `higher_than 0`" [brief] | Production alert, Phase 2.1 | mapped |
| 3 | "Do NOT drop `on_missing_data = treat_as_zero`" [brief] | Production alert, Guard 1 `treat_as_zero` row | mapped |
| 4 | "keep the same Terraform resources" [brief] | Proposed Solution (resources unchanged) | mapped |
| 5 | "Add a reversible throwaway canary alert pair that must fire on a synthetic silence" [brief] | Canary pair, Phase 2.1, Guard 1 canary rows | mapped |
| 6 | "say so in the PR and runbook" (the zero-fill mechanism is an inference) [brief] | Overview epistemic status, Phase 4.3, AC8, PR-body AC | mapped |
| 7 | "the pinned tests ... egress-gw-alert.test.sh (G2 block), inngest-cutover-flip-silent-alert.test.sh, betterstack-alert-structure.test.sh" [brief] | Phase 1.1, 3.3, 3.4, 3.5 | mapped |
| 8 | ".github/workflows/infra-validation.yml (~line 995); .github/workflows/apply-web-platform-infra.yml (`-target` lines for the canary)" [brief] | Phase 2.2, 4.2 | mapped |
| 9 | "runbooks ... cron-egress-blocked.md ... and betterstack-log-query.md" [brief] | Phase 4.3 | mapped |
| 10 | "Post-merge verification ...: the canary fires; incident 1047829421 auto-resolves; it stays resolved for at least 4 hours" [brief] | Soak probe, Observability, post-merge AC | mapped |
| 11 | "If it does not, fall back to the cron poller." [brief] | Guard 2 / probe verdict table (fallback is named, not built) | mapped |
| 12 | "A follow-up PR deletes the canary (file it as a tracked follow-up, not a net-new unlinked issue)" [brief] | Phase 4.5 tracker issue; RETIREMENT list in the probe header | mapped |
| 13 | "use `Ref #12180`, never `Closes`" [brief] | frontmatter, PR-body AC | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| `betterstack-logs-alerts.tf` SQL, alert, canary | "keep the same Terraform resources" / "Add a reversible throwaway canary alert pair" | asked |
| `apply-web-platform-infra.yml` two `-target` lines | "`-target` lines for the canary" | asked |
| `infra-validation.yml` comment | "(~line 995)" | asked |
| `egress-gw-alert.test.sh` rewrite + G2b | "the pinned tests ... (G2 block ~lines 188-233)" | asked |
| `inngest-cutover-flip-silent-alert.test.sh` comment | "inngest-cutover-flip-silent-alert.test.sh" | asked |
| `betterstack-alert-structure.test.sh` run | "betterstack-alert-structure.test.sh" | asked |
| the two runbooks | "runbooks knowledge-base/.../cron-egress-blocked.md ... betterstack-log-query.md" | asked |
| `logs-alert-query-period-ceiling.test.sh` and `betterstack-send-failed-alert-mutation.test.sh` count bumps | — | inferred - justification: both compare an exact alert/exploration count with `!=`/`==`; the canary pair turns them red, and the drift pin rots otherwise |
| ADR-218 amendment | — | inferred - justification: the amendment supersedes the 2026-10-12 standing rule (`lower_than length(var.web_hosts)` on a multiplexed source), and an unamended ADR would tell the next author to write the shape that misfired; kept to about 15 lines (new rule, INFERRED label, canary decision rule, evaluator-error residual) |
| `BASELINE_DECLARED_PROBES` 94 to 95 | — | inferred - justification: forced by the probe's `credentials_required` declaration; the preflight ratchet goes red without it |
| soak probe, its suite and registrations | "it stays resolved for at least 4 hours" | asked (the mechanism is inferred: ship's soak-enrollment gate blocks PR-ready on a prose-only soak criterion) |
| tracker issue | "file it as a tracked follow-up" | asked |
| `decision-challenges.md`, `tasks.md` | — | inferred - justification: pipeline contract artifacts required by the technical-ruling gate and the plan skill |
| flip-silent TF comment refresh | — | inferred - justification: two comments assert the sibling's stuck-at-0 as current fact and would be false after this change (minimal truth fix; no pinned string touched) |

### Split Assessment

- Subsystems touched: 4 - `apps/web-platform`, `.github`, `scripts`, `knowledge-base`
- Planned files: 22 | Estimated changed lines: about 700 (the test rewrite and the new probe suite dominate)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR - the four roots are one atomic behavioral change. The proposed seam (PR-1 TF, tests
  and runbooks; PR-2 probe and registrations) was rejected: PR-1 alone would ship the new alert shape with its
  soak criterion only in prose, which ship's enrollment gate blocks, and the verification is the point of the
  change. The knowledge-base edits are the same change's documentation.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1. The production heredoc flattens to exactly the SQL in Proposed Solution; `egress-gw-alert.test.sh`
  pins it whole. Read-only proof recorded as counts in the PR body: 0 (healthy), 1 (web-2 only), 2 (canary
  identifier) for the **final** text, or an explicit "credentials unavailable" statement.
- [ ] AC2. Production alert: `operator = "higher_than"`, `value = 0`, `on_missing_data = "treat_as_zero"`,
  `paused = false`, `email = true`; `incident_cause` and the comment describe the missing-count semantics.
- [ ] AC3. Canary resources exist with identical names `egress_gw_probe_silent_canary`, the derived `replace()`
  SQL, `higher_than 0`, same windows, `treat_as_zero`, `paused = false`, `email = true`; `git grep -F
  "egress-gw-probe-canary-absent"` returns hits only in the `.tf`, the guard, the probe, runbooks and this plan's
  spec, never in an emitter.
- [ ] AC4. `apply-web-platform-infra.yml` has the two canary `-target` lines inside `apply:` and
  `wc -c` is at most 490,000; no prose added to that file.
- [ ] AC5. These pass: `egress-gw-alert.test.sh` (with `PRESENCE_ROWS`/`MUT_ROWS` re-derived at both write sites),
  `betterstack-alert-structure.test.sh`, `logs-alert-query-period-ceiling.test.sh` (`EXPECT_BLOCKS=19`),
  `betterstack-send-failed-alert-mutation.test.sh` (`== 19`), `inngest-cutover-flip-silent-alert.test.sh`, the
  probe suite, `c4-count-parity.test.sh`, `workflow-file-size.test.ts`, `python3 scripts/lint-guard-contract.py`
  (reports this plan's two guards).
- [ ] AC6. The probe and its suite are registered like the 8097 probe, and the probe header has a `RETIREMENT:`
  line listing every site to touch when the canary is deleted: the two resources, both `-target` lines (kept one
  apply; the structure suite's rows 21-22 tolerate a bare `-target` for a deleted address only when the address is listed in `INTENDED_DESTROYS` of `tests/scripts/test-infra-privileged-tier-census.sh`, so the deletion PR adds the two logtail addresses there and a later PR removes them with the targets, the #11653 then #11785 sequence; the deletion plan shows `2 destroyed` (alert first) and needs a standalone `[ack-destroy]` line in the merge commit; rows 21-22 and the census must be re-run to confirm they accept a `logtail_*` row, which is unverified today), `EXPECT_BLOCKS` 19 to 18, `MIN_PASSES`,
  `count == 19` to `18`, the guard's G2b block and rows, the runbook canary section, the ADR note.
- [ ] AC7. ADR-218 amendment appended, with the live alert count and the INFERRED label.
- [ ] AC8. Both runbooks and the `.tf` comment state: the evaluator zero-fill is an inference; the query is proven
  and the evaluator is not; a green production alert is not evidence of health until the canary has fired;
  evaluator errors read 0.
- [ ] AC9. PR body: `Ref #12180` (no `Closes`), the inference disclosure, the proof counts, the expected plan
  (`2 added, 1-2 changed, 0 destroyed`), and `## Changelog`.
- [ ] AC10. Tracker issue #12189 carries the `follow-through` label and an unfenced column-0 directive
  `<!-- soleur:followthrough script=scripts/followthroughs/egress-gw-probe-silent-12180.sh earliest=<apply
  completion + 30 minutes, ISO-8601 Z>
  secrets=BETTERSTACK_API_TOKEN,BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->`; the sweeper is dry-run once
  (`dry_run=true`) and its `exit=` line read.

### Post-merge (verified by the probe and `soleur:postmerge`; no manual step)

- [ ] AC11. The per-merge apply succeeds and its plan matches the expected counts.
- [ ] AC12. A canary incident exists within 20 minutes of apply completion. The executor is whoever merges (the
  session that owns the merge-to-deploy verification; `soleur:postmerge` itself is not changed by this PR), who runs the
  probe once at apply completion plus 25 minutes with read credentials from Doppler (`prd_terraform`) and reads the `canary=` field of its verdict line (the probe prints one field per condition,
  so no special mode exists). `canary=absent` with `canary_alert_live=1` means the evaluator is blind for this shape: leave the production
  alert armed, build the poller (#12190 holds the deferral; start it at once), and do not treat a green production
  alert as healthy.
  The tracker's sweeper probe (earliest at apply completion plus 30 minutes, daily 18:00 UTC sweep) is the backstop.
- [ ] AC12b. A production incident that stays open (1047829421) or a newer one while both hosts show rows in the
  window (`rows_in_window`) disproves the inverted shape just as an absent canary does: the evaluator may be
  scanning an empty window, in which case production and canary both read 2 (the canary shares the production
  query shape and cannot tell a genuinely silent fleet from an empty window, so what it proves is non-zero delivery
  on an empty count, not general evaluator health). Response per the Post-apply decision table: the poller or a
  pause, a Better Stack write only with the user's per-command go-ahead, never a revert.
- [ ] AC13. Incident 1047829421 reaches resolved without a manual action and stays resolved for at least 4 hours
  with no newer `soleur-egress-gw-probe-silent-prd` incident. If not: fall back to the poller; hand-resolving the
  incident needs the user's explicit per-command go-ahead and is not part of this plan.
- [ ] AC14. The canary is deleted by a follow-up PR as soon as AC12 holds (a canary incident is observed), not
  after the 4 hours: the 4-hour soak concerns only the production incident, and the canary's never-recovering
  incident, P1 mirror issue and email should not outlive its job. The probe then exits 0 once AC13 also holds
  and the sweeper closes the tracker; before that it reports `action_required: delete the canary`.

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed
**Assessment:** The CTO ruled the design before planning (binding) and ruled five implementation forks during
planning (F1-F5, recorded). No product, marketing, legal, finance, sales, support or operations surface changes;
no user-facing UI path matches the UI-surface term list, so no Product/UX gate. GDPR gate: no regulated-data
surface (no schema, auth flow, API route or personal data); skipped. Encryption posture: no persistent store or
new cross-component connection; skipped. Task-design gate: no new autonomous-task surface (the probe runs under
the existing sweeper).

## Test Scenarios

- Healthy fleet fixture (both hosts present) evaluates the production predicate to 0 in the guard's canon check.
- One host absent evaluates to 1; no host evaluates to 2; surplus hosts floor at 0 (the `toInt64` case).
- Canary derivation: the canary heredoc equals the production heredoc with exactly one substring swapped.
- Probe: the eight verdict fixtures in Guard 2, window boundaries at 4 h minus 1 s, exactly 4 h, 4 h plus 1 s.
- Registration: the suite appears in `test-all.sh`, the shard TSV and the affected-paths map (registration gates).

## Rollback

Reverting this PR restores the `lower_than` shape and removes the canary from the `.tf`. A canary that already
exists live is then orphaned unless its two `-target` lines stay in the apply workflow for one apply (a bare
`-target` on an address with no configuration plans its DELETE) and the destroy-guard receives `[ack-destroy]` in
the merge commit. The same recipe is the deletion PR's, so it lives in the probe's `RETIREMENT:` header and the
runbook canary section. The recipe is executed once in a scratch detached worktree (`git revert --no-commit`, then
the exact-count suites and the structure suite) in Phase 5, because it is otherwise first run during an incident.

## Risks and Sharp Edges

- A user-brand section lacking its threshold fails `deepen-plan`; this one declares `aggregate pattern`.
- **Evaluator-blind inversion.** If the evaluator reads 0 for every step, the inverted alert never fires. That is
  the case the canary detects; it is not covered by anything else until the poller exists.
- **The canary shares the production query shape (`dt BETWEEN`, whole-window scalar), the shape of the two
  alerts known to read 0.** Alerts known to evaluate (`monitor_send_failed`, `egress_gw_deny_spike`) use
  `{{time}}`, `time BETWEEN` and `GROUP BY time`. A proven-shape canary would prove the evaluator works in general
  and say nothing about this shape, so the canary deliberately stays on the production shape; AC12b covers the
  empty-window case it cannot see.
- **Evaluator errors read 0** under `treat_as_zero` (CTO residual, named in the comment, runbooks and ADR).
- **Noise while the canary lives:** one email, one P1 `action-required` mirror issue, and a constant-fail input to
  any `post-deploy-incident-soak` enrolled meanwhile (none are enrolled; check with `gh issue list --label
  follow-through` before merge), and the `soleur:postmerge` alert-channel sweep (Phase 3.9) will list the canary's
  `ci/betterstack-incident` issue and open incident as rows; that phase is advisory and never blocks, and the
  report names those rows as the expected canary. The canary is deleted as soon as AC12 holds (see AC14), not after the 4 hours.
- **Count suites flip twice:** +1 here, -1 at deletion. The probe's `RETIREMENT:` line is the single list.
- **Apply byte budget:** 282 bytes of headroom; do not add any comment to the workflow file.
- **Free-tier cap:** an apply refusal on alert count fails the whole push apply; the fallback is pre-decided.
- **Heredoc interpolation:** the production SQL now contains `${length(var.web_hosts)}`; the guard's awk extraction
  reads raw text, so the canon literal contains `${`. A hand-run of the query must substitute the number first.
- The canary string `egress-gw-probe-canary-absent` must never become a real `logger -t` tag.
