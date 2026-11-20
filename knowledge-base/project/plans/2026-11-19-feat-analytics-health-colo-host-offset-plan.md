---
title: "origin-tls: site-split (coloCode), host-filtered (app.soleur.ai) /health analytics query with an end-time offset in cloudflare-readonly.sh"
date: 2026-11-19
slug: feat-analytics-health-colo-host-offset
branch: feat-one-shot-12846-health-colo-split
issue: 12846
closes: []
type: feat
priority: p3-low
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
lane: cross-domain
---

# origin-tls: per-colo, host-scoped /health analytics read with an end-time offset

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-11-19. **Passes:** plan-review panel (DHH, Kieran, code-simplicity, CTO devex), an advisor consult, the sharp-edges catalogue pass, security-sentinel, test-design-reviewer, observability-coverage-reviewer, and a verify-the-negative / stale-reference self-audit; forks ruled by the CTO agent (rows T1-T6 and D1-D5 in `decision-challenges.md`) and the CLO agent (C1-C6).

### Key improvements

1. Splice route (CTO D1): `zone` and `window_end` are spliced inside `project()` after its unchanged jq line, so no second jq call site is added. A second `res=` line would have moved the jq census from 9 to 10 and made the `edit_once` anchors of W1.1, W6.19 and W6.21 match twice (verified).
2. Falsification recipe made testable (CTO D2, D3): a null-colo rule (`inconclusive: invalid-colo` only when a null-colo row qualifies), a committed pure-jq suite `health-colo-falsification.test.sh` with about 20 boundary cases, a recipe extracted from one marker pair in the runbook, and seven recipe mutation rows.
3. Guard 3 for CLO condition 1(e) output shapes, plus grammar rows for `""`, `1000` and a 20-digit offset, and a fail-closed offset bound (`[ 99999999999999999999 -gt 527 ]` is rc 2, which a `-gt` refusal skips) (CTO D4).
4. Security hardening (CTO D5): `END_OFFSET=0` unconditional (an inherited `a[$(cmd)]` runs `cmd` in arithmetic; reproduced), canary rows, and a handoff loop that re-checks wrapper drift before each read, validates its inputs by shape, writes evidence once under noclobber and runs every jq under `env -i`. The loop was run against a stub `doppler`: keep, truncated split, noclobber and refusal paths behave as written.
5. Corrections: the observability block now states the hosted-image path truthfully (the plugin ships in the web-platform image; a hosted run stops at `guard_source` exit 64 or `no-credential` exit 10); stale W1.6 and "invalid rows" references fixed; G1.Q1/G1.A12o named; `sub_config_entrypoint` line corrected to L423.

### New considerations discovered

- The four suite floors conflict with PR #12876 by construction; the new recipe suite is a separate file partly so it adds no fifth.
- Whether a runbook-only diff selects the new suite is unverified until `test-all.sh --print-selection` is run in the work phase.

## Overview

Add one read-only analytics read to the closed subcommand set of `plugins/soleur/scripts/cloudflare-readonly.sh` (ADR-289) that scopes Cloudflare's `/health` origin-response-time series to the host `app.soleur.ai`, splits it by Cloudflare colo (`coloCode`), and can end its window before the current hour, so the pre-flip baseline of the 2026-11-08 strict TLS flip stays reachable. The zone the read targets must follow the 2026-11-18 Cloudflare account and zone move (#12931).

## Research Insights

### Premise Validation (Phase 0.6)

- #12846 is OPEN (p3-low, type/chore, domain/engineering). Its only open PR is this branch's own draft #12959; the collision pre-check also listed three `test-all.sh` processes owned by the sibling worktree `feat-one-shot-12742-public-sdk-url-poll` (a test run, not a duplicate of this work).
- #12931 is OPEN; its migration PR #12932 is a draft that touches only knowledge-base files today. #12931's own checklist names `plugins/soleur/scripts/cloudflare-readonly.sh` as a Doppler `CF_ZONE_ID` consumer that breaks until Doppler is updated, and forbids dispatching `apply-web-platform-infra.yml` until it lands.
- The wrapper already has `analytics-health <hours>` (F) and `analytics-edge-errors <hours>` (G), shipped by PR #12515 (#12441). F is path-filtered (`clientRequestPath:"/health"`) only; G is host-filtered (`clientRequestHTTPHost:"app.soleur.ai"`). Neither groups by colo; both end at the current hour (`gql_window`). The issue's description of the gap holds on `origin/main`.
- The wrapper holds no zone literal: every read takes `CF_ZONE_ID` from the Doppler `prd_terraform` environment. Neither zone id appears in the wrapper or its suite (the old prefix appears only in `plugins/soleur/agents/engineering/infra/infra-security.md` and a tfplan fixture).
- Class R read, this session (Records line in `## Class R Checks` below): `analytics-health 216` against the configured zone returned `ok` with 199 contiguous hourly rows, 2026-11-10T10Z to 2026-11-18T16Z, and none after. So the configured zone is still the OLD zone, it still answers analytics in status `moved`, and traffic after the ~16:24Z move is on the NEW zone. The kept line 2 is `knowledge-base/engineering/operations/runbooks/evidence/2026-11-19-analytics-health-216h.json` (moved there from the spec directory in this PR) (the work phase moves it to `runbooks/evidence/`, per the runbook rule "never leave a read in a session scratchpad").
- Not checked: whether `CF_API_TOKEN_ANALYTICS_READ` can read the new zone. Class R reaches Cloudflare only through the wrapper with Doppler's `CF_ZONE_ID`, so a probe of the new zone is not a Class R act. "I did not check" it.

### Property List and Cut List (Phase 0.6b)

Properties the ask needs:

1. P1. A sanctioned read returns `/health` origin response time for requests to the host `app.soleur.ai` only.
2. P2. The same read splits each hour by Cloudflare colo, so a step confined to some colos can be told apart from a step at every colo.
3. P3. The read's window can end before the current hour, so the 2026-11-07T23:43Z flip and the hours before it stay reachable after they leave the last-216-hours window.
4. P4. The read stays inside the wrapper's closed set and Class R contract (ADR-289; fixed compiled-in query; no caller text in the query; `Unverified:` records).
5. P5. The zone the read describes is the zone in config, never a hard-coded id, and each saved result says which zone it read.
6. P6. One sanctioned read is committed as an evidence file and the runbook records the evidence-bar verdict.

Mechanisms the ask names, and what already covers them:

| Mechanism | Property | Already on `origin/main`? |
|---|---|---|
| host filter `clientRequestHTTPHost` | P1 | Yes as a filter spelling, in `GQL_EDGE_TPL` (accepted live on 2026-11-11); not on the health query. Reused, not re-researched. |
| `coloCode` group-by | P2 | No. New. Documented dimension. |
| end-time offset | P3 | No. `gql_window` always ends at `floor(now)`. New argument; the window arithmetic is reused. |
| closed-set subcommand or flag | P4 | The dispatcher, `need_hours`, `cf_graphql`, `guard_gql`, `project` all exist and are reused unchanged. |
| zone from config | P5 | Yes: `load_credential zone` already reads and validates `CF_ZONE_ID`. Nothing new except printing it. |
| evidence file + runbook verdict | P6 | The Handoff step 2 loop in `origin-tls-strict-flip.md` already writes evidence files; the H loop is modelled on it (same keep-only-ok shape) with H/O, the zone and truncation keep rules added. |

Cut List:

- A second Doppler variable for an analytics-only zone (`CF_ANALYTICS_ZONE_ID`) -> P5 -> already covered by `CF_ZONE_ID`; the flip window is entirely on the zone Doppler names today.
- A compiled-in old or new zone id -> P5 -> forbidden by the brief and covered by `CF_ZONE_ID`.
- A `settings`-node limits query -> no property needs it (the dataset's limits are learned from the first read's success or bounded `api-error`).
- An aggregate all-colo series in the same request -> P1 is already met by F's path series plus the host filter on the new read; a second aliased node would change `guard_gql`'s shape for no listed property.

### Value-proposition measurement (Phase 0.6c)

Not a cost or performance justification; skipped.

### Relevant files (repo research)

- `plugins/soleur/scripts/cloudflare-readonly.sh`: `SUBCOMMANDS` (L171), `MAX_HOURS=216` (L178), templates `GQL_HEALTH_TPL`/`GQL_EDGE_TPL` (L193-194), `JQ_DEFS` (L215-226), `cf_graphql` (L312), `guard_gql` (L369), `gql_fill` (L382), `gql_window` (L391), `need_hours` (L408), `sub_analytics_health` (L447), arg handling (L466-478), dispatcher (L481-489). Header: subcommand list (L8-17), token binding (L30-31), POST exception (L42-49), Records keys (L95-98), F/G records (L121-126), next-action table (L127-137).
- `plugins/soleur/test/cloudflare-readonly.test.sh` (2198 lines): sandbox rewrites `^CURL=/usr/bin/curl$` (`make_sandbox` L188-199); stub logs argv/stdin/env and refuses unknown flags (L128-186); inline fixtures (`ok_body` L291, `gql_wrap` L302); `check_wire` closed argv `EXP_POST` (L563-634); POST stdin is exactly three lines (L700-707); `SUBS`/`ANSUBS` literals (L116-118); parity length 6 (L436-440); dispatcher arm count 7 (L447); "exactly two `cf_graphql` callers" (L380); one `cf_graphql` per analytics body (L528); `MAX_HOURS` <= health row limit (L552); `QLIMIT` = edge limit (L553); grammar rows (L744-776); refuse floor 119 (L851); "all 6 subcommands" floor 90 (L1085); analytics projections (L1290-1496); templates/clock (L1588-1745, `FAKE_T=1794000123` L1599, `make_variant fakeclock` L1702); `PROJ_FLOOR=172` (L1757); mutation floor 196 (L2186); assertion floor 1965 (L2194). The suite strips comments before source rows (L316).
- `plugins/soleur/test/components.test.ts`: section 9 pins `CF_SIX` (L926), "its six subcommands" count 6 (L941-942), sd9 wording (L787-803, L896-903, L1074), `1 to MAX_HOURS` wording (L979-990), item count (L871-878).
- `plugins/soleur/skills/brainstorm-techniques/references/standing-delegation.md` section 9: item 2 (L439), Boundary (L445), Credentials (L447).
- `knowledge-base/engineering/architecture/decisions/ADR-289-standing-delegation-and-production-envelope.md`: addenda (last `## Addendum 2026-11-09 (Ref #12441, #10479, #10205)` L441), `related:` L7.
- `knowledge-base/engineering/operations/runbooks/origin-tls-strict-flip.md`: Handoff loop (L276-297), next-action table (L299-311), CTO rulings incl. the evidence bar (L399-405), "Save every analytics read" (L409).
- `scripts/suite-durations.tsv:204` (`cloudflare-readonly.test.sh` 155229 ms), `scripts/suite-shard-legs.tsv:206`, `scripts/lib/test-affected-paths.sh:590-591`; CI runs the suite through `scripts/test-all.sh` (`ci.yml` `bash scripts/test-all.sh scripts`).
- `plugins/soleur/agents/engineering/cto.md:84` names the wrapper; checked for a subcommand count in the work phase.

### Sibling work on the same files

- PR #12876 (branch `feat-one-shot-12742-public-sdk-url-poll`, live) edits the wrapper's header B block (L99-115), the END of `JQ_DEFS` (adds `def hn` and `def hostlit` after `def verstr`, L226) and `sub_config_entrypoint` (L423), plus 46 suite lines. This plan keeps every wrapper hunk at least three unchanged lines away from those, places any new jq def right after `def idv:` (L217), and verifies with `git merge-tree` against that branch before pushing (learning 2026-11-15: a matching value is not a clean hunk).
- PR #12896 (`feat-one-shot-12712`) edits `standing-delegation.md` at L161 and L396 only; section 9 (L432+) is untouched there.

### Institutional learnings applied

- `2026-11-04-a-read-only-wrapper-leaked-through-its-helper-children-and-its-own-scoping-clause.md`: exact-argv equality, every child under `env -i`, verdicts from wrapper-established counts, one mutation row and an executed-group floor per test group.
- `2026-11-10-a-fix-rounds-new-gates-and-rows-repeated-the-class-they-closed.md`: no conditional row inside an unconditional floor; re-read boundary fixtures when a refusal rule changes.
- `2026-03-25-bash-integer-validation-for-date-parameters.md`: GNU `date -d` accepts natural language; validate the offset as digits before any arithmetic.
- `2026-03-09-shell-api-wrapper-hardening-patterns.md`: never do bash arithmetic on vendor floats (durations stay in jq).
- `2026-09-21-curl-retry-flags-turn-a-throttled-emit-into-success-and-my-stubs-were-looser-than-the-code.md`: the curl stub must stay exactly as strict as the code (the closed `EXP_POST` vector is reused, not loosened).
- `2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md`: the new arm, its template and its offset argument each get their own mutation row.
- `2026-11-16-seven-fix-rounds-each-found-the-next-bash-expansion-the-hook-read-differently.md`: keep the new template free of `$`, backticks and `$(`.
- `2026-11-17-a-comment-id-cited-for-a-ruling-held-only-half-of-it.md`: cite the coloCode/host/offset shape to PR #12843's `decision-challenges.md`, and #10479 comment 6946870123 only for the p90/p50 rulings it holds.
- `2026-06-30-recurring-missing-data-signal-can-be-a-query-assumption-bug.md` and `2026-11-10-a-failover-premise-must-be-checked-against-the-serving-topology.md`: an empty series after the move is a zone question first; the zone the read used is printed, never inferred.
- `2026-11-15-byte-identical-row-is-not-a-clean-hunk-and-push-runs-carry-no-timings.md`: measure merge conflicts with `git merge-tree`; new suite cases move the `suite-durations.tsv` row; never write "fix" beside an issue number in prose.

### Cloudflare GraphQL fact sheet (public docs, read 2026-11-19; no authenticated call outside the wrapper)

- `coloCode` is a documented dimension of `httpRequestsAdaptiveGroups` (sample value `"LHR"`, "per data center") and is also usable as a filter: <https://developers.cloudflare.com/analytics/graphql-api/migration-guides/graphql-api-analytics/> and <https://developers.cloudflare.com/analytics/graphql-api/migration-guides/zone-analytics-colos/>. The docs do not define it as "the edge colo that served the request"; the plan says "Cloudflare colo" and claims no more.
- `clientRequestHTTPHost` and `requestSource:"eyeball"` are documented filters (<https://developers.cloudflare.com/analytics/graphql-api/tutorials/end-customer-analytics/>). `clientRequestPath` as a filter is not in the docs but was accepted live by F on 2026-11-11.
- `originResponseDurationMs` avg and P50/P90 quantile names: NOT in the docs; accepted live by F on 2026-11-11 and 2026-11-16.
- Retention: "Adaptive datasets, such as `httpRequestsAdaptiveGroups` ... retain at least 31 days of data on every plan" (<https://developers.cloudflare.com/analytics/graphql-api/limits/>). Free vs Pro `maxDuration`/`notOlderThan` for this dataset: NOT documented. The docs conflict on whether Free-plan zones reach the GraphQL Analytics API at all (settings page: "ALL plans for the essential datasets"; Prometheus page: "Zones on Cloudflare's Free plan do not have access"). So reads of the NEW (Free) zone are UNVERIFIED until a sanctioned read runs against it.
- The only page-size example is `maxPageSize: 10000`.
- Zone status: a Free-plan zone in Moved status is deleted 7 days after entering it; paid plans "may not correspond"; deleted zones are purged 7 days later (<https://developers.cloudflare.com/dns/zone-setups/reference/domain-status/>). The OLD zone was Pro and entered `moved` on 2026-11-18, so it may be deleted from about 2026-11-25. Its analytics are then unreachable, and the 2026-11-07 hours also age past the 31-day floor about 2026-12-08.
- Token reach: zone-scoped tokens are granted per zone resource; whether the existing analytics token reaches the new zone id is NOT documented and NOT checked.

### Functional overlap (Phase 1.5b)

`soleur:engineering:discovery:functional-discovery`: no community skill or agent queries zone HTTP analytics by host and colo (closest: `workers-observability`, `cloudflare/skills`, neither overlaps). Nothing installed. Community discovery (Phase 1.5) skipped: the change is bash only, no uncovered stack.

### Research decision (Phase 1.6)

External API, so external docs were read (fact sheet above). Strong local patterns exist for everything else.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue, brief or ruling) | Reality | Plan response |
|---|---|---|
| "`analytics-health` is path-filtered (`/health`), not host-scoped, not split by colo, always ends at the current hour" (issue) | Holds on `origin/main` (`GQL_HEALTH_TPL` L193, `gql_window` L391-405). | Build the gap as a new subcommand; F is not changed. |
| "Results ... saved to `evidence/<UTC date>-analytics-<subcommand>-216h.json`" (issue) | Existing files are named `<date>-<subcommand>-216h.json` (no doubled `analytics-`), and with an offset `216h` alone does not identify a read. | CTO F12: `<UTC date>-analytics-health-colo-<H>h-off<O>h.json`. |
| "any zone/account id the query uses must be the current one or read from config" (brief) | The wrapper reads `CF_ZONE_ID` from Doppler and holds no zone literal. Doppler still names the OLD zone; the whole flip window (2026-11-07/08) is on the OLD zone. | Read from config only (CTO F4) and print the zone in the projection. The evidence read targets the old zone and must run before #12931 changes Doppler and before the old zone can be deleted. |
| "whether the Free plan's analytics dataset/retention supports the coloCode group-by" (brief) | Docs: `coloCode` is documented; retention is "at least 31 days on every plan"; Free-plan GraphQL access is contradictory in the docs. | The #12846 read does not need the Free zone (the flip is on the Pro zone). A read of the new zone is UNVERIFIED and recorded as such; a 403 or `api-error` there is a recorded result, never a token swap. |
| CTO R2: host-level "supported" needs that "change-history shows no other event in the window" | `change-history` is bounded to the last 7 days (`since=7 days ago` in `sub_change_history`) and its token is under the dev config, so it cannot cover 2026-11-07. The runbook already records origin-side events inside +-1 h of the flip: the release deploy 23:47-23:50Z, the 00:14-00:15Z restart pair, Doppler `prd_terraform` writes 22:54:34Z, 23:41:47Z and 00:13:25Z. Per-colo shape cannot separate them from the flip (all act on the origin side). | Re-ruled by CTO T2: R2 is replaced by a falsification rule with outcomes `not supported` or `inconclusive` only; "supported" is removed; the "other event" window is `[2026-11-07T22:43Z, 2026-11-08T00:43Z]`; the alternative-event check uses the runbook's records plus `git log origin/main`, never `change-history`. |
| CTO F7: colo codes `\A[A-Z]{3,4}\z` | CLO condition 1(e): `coloCode` is printed only as three capital ASCII letters; a non-matching value is never printed | Narrowed to `\A[A-Z]{3}\z`; a non-match projects `null` (CTO reconciliation (b): 1(e) names only `null` or `bad-response`, so a third marker would reopen the legal condition). The row keeps its count and timings. |
| CTO F3: hours 1..216, offset 0..528, and hours+offset <= 744 | 216 + 528 = 744, so the sum check could never fire once both bounds hold (a dead check no mutation can drive RED); and the window start `floor(now) - 744 h` can sit up to 59 minutes past the documented `now - 31 d` floor | CTO reconciliation (a), T5, T6: `MAX_OFFSET=527`, no sum check in code, the span (at most 743) pinned by the `components.test.ts` section 9 pin and the edge grammar rows; the CLO amended its committed text to 527/743. |
| Runbook Step C shape included `requestSource: "eyeball"` | Neither shipped query uses it. | CTO F5: left out on purpose; the runbook addendum says so. |

## Problem Statement

The CTO agent's 2026-11-16 ruling "provisionally attributed" the /health p90 step at the 2026-11-07T23:43Z strict TLS flip (daily median hourly p90 about 470 ms to about 850 ms) to the strict origin hop, and set an evidence bar for "attributed": a change point within +-1 h, a matching mechanism read, and no alternative event in the window. The only sanctioned reader (`analytics-health`) cannot test that bar: it mixes all hosts that serve `/health`, cannot separate a per-colo effect from an origin-side effect, and its window always ends at the current hour, so the pre-flip hours left it on 2026-11-16. Since 2026-11-18 there is a second clock: the zone that holds every flip-window hour is in status `moved` and may be deleted from about 2026-11-25.

## Proposed Solution

A seventh subcommand, `analytics-health-colo <hours> <end-offset-hours>` (Records key `Cloudflare analytics-health-colo (H) #12846`), that sends one more fixed, compiled-in, read-only GraphQL query through the existing single POST chokepoint:

```text
query{viewer{zones(filter:{zoneTag:"@ZONE@"}){httpRequestsAdaptiveGroups(limit:10000,filter:{datetime_geq:"@START@",datetime_lt:"@END@",clientRequestHTTPHost:"app.soleur.ai",clientRequestPath:"/health"},orderBy:[datetimeHour_ASC]){count dimensions{datetimeHour coloCode} avg{originResponseDurationMs} quantiles{originResponseDurationMsP50 originResponseDurationMsP90}}}}}
```

(The compiled-in constant is the JSON-escaped one-line form, `GQL_COLO_TPL`, in the same style as `GQL_HEALTH_TPL`; no `$`, backtick or `$(` in it.)

- Window: complete UTC hours `[E - H h, E)`, where `E = floor(now to the hour) - O h`. `H` is 1..216 (`MAX_HOURS`, unchanged), `O` is 0..527 (`MAX_OFFSET`, CTO T6), so `H + O <= 743` holds by construction and every accepted window starts inside the documented 31-day floor (at 744 the start `floor(now) - 744 h` could reach up to 59 minutes past `now - 31 d`); anything else exits 64 with nothing sent, before any credential is read (CTO F2, F3, T6). Only the two computed stamps enter the query; neither caller integer does.
- Zone: `CF_ZONE_ID` from the environment, validated as today, printed in the projection as `zone` (CTO F4).
- Token: `CF_API_TOKEN_ANALYTICS_READ`, no fallback (the existing binding).
- Projection (one JSON line, CTO F8 as revised by T5): `{zone, window_end, subcommand, window_hours, rows, truncated, note, series:[{hour, colo, count, avg_ms, p50_ms, p90_ms}]}`. `zone` and `window_end` are spliced in front by bash outside jq, inside `project()` after its jq line (CTO T1 as narrowed by D1, see edit 9); the rest is the jq projection. `series` is sorted on the cleaned `[hour, colo]`; `colo` goes through a new `colo` jq def (`\A[A-Z]{3}\z`, else `null`; CTO F7 as reconciled with CLO condition 1(e)); `hour` is accepted only in the `YYYY-MM-DDTHH:00:00Z` shape (CLO 1(e)); `truncated` is true at the 10000-row cap (CTO F6); `note` states that counts are sampled estimates and the scope is the host `app.soleur.ai` and the path `/health` (no `requestSource` filter). No `window_start` or `end_offset_hours` (CTO T5: derivable from `window_end`, `window_hours` and the evidence filename).
- Records: always an `Unverified:` line, like F and G, never `Checked:`.

`analytics-health` and `analytics-edge-errors` keep their grammar, query and output byte for byte. The one shared helper that changes is `gql_window`, which subtracts `END_OFFSET * 3600` from the end; `END_OFFSET` stays `0` on every other arm, which the existing fake-clock rows for F and G keep pinning.

## Technical Approach

Line numbers in this plan are a snapshot of `origin/main` at `1887d54afb` (2026-11-19) and only help reading; PR #12876 shifts the suite. The work phase locates every row, mutation and line by its quoted label or content, never by number.

### Wrapper edits (`plugins/soleur/scripts/cloudflare-readonly.sh`)

Each edit names its anchor. Every hunk stays at least three unchanged lines away from PR #12876's hunks (header B block, `def verstr` and the lines after it, `sub_config_entrypoint`).

1. Header line 2-3 ("six READ-ONLY ... two fixed read-only GraphQL analytics reads"): seven reads, three analytics reads.
2. Header subcommand list (after the `analytics-edge-errors <hours>` line): add `analytics-health-colo <hours> <end-offset-hours>  H. /health origin response time per hour and colo, host app.soleur.ai   POST /graphql, one fixed query (#12846)`; `--list` prints "the seven names"; the argument sentence names the second argument, its grammar and the `H + O <= 743` bound (by construction).
3. Token binding paragraph (`analytics-health, analytics-edge-errors -> CF_API_TOKEN_ANALYTICS_READ`): add `analytics-health-colo`.
4. READ-ONLY POST EXCEPTION paragraph: "Exactly three fixed queries" (`GQL_HEALTH_TPL`, `GQL_EDGE_TPL`, `GQL_COLO_TPL`); the window sentence states `[E - hours, E)` with `E` the current hour minus the offset; the Unverified sentence adds "the `coloCode` dimension, the host and path filters together on this node, and the 10000 row cap".
5. Records keys line: add `` `Cloudflare analytics-health-colo (H) #12846` `` (L97-98; three unchanged lines remain before #12876's first changed line).
6. Records mapping: an `H analytics-health-colo` paragraph after the `G` paragraph (L124-126): figures `zone`, the window, `rows`, `truncated` and the per-hour per-colo series; ALWAYS `Unverified:`; `rows: 0` is never "no data problem" (a wrong zone or filter returns nothing too); a `zone` that is not the zone the record claims makes the read `other: wrong-zone` for that record.
7. Globals: `SUBCOMMANDS` gains `analytics-health-colo`; new `MAX_OFFSET=527` (no trailing comment) and `END_OFFSET=0` next to `MAX_HOURS`, both assigned unconditionally at global scope like `HOURS=0` (never `${END_OFFSET:-0}` or `: "${END_OFFSET:=0}"`: `gql_window` evaluates `END_OFFSET` in arithmetic, and bash arithmetic on an inherited value such as `a[$(cmd)]` runs `cmd`; CTO D5); no span constant and no sum check (`MAX_HOURS + MAX_OFFSET` is 743, so the span holds by construction; a sum check could never fire and no mutation could drive it RED; CTO reconciliation (a) as revised by T5: the span is pinned by the `components.test.ts` "at most 743" pin and the edge grammar rows, with no separate suite sum row); `GQL_COLO_TPL` directly after `GQL_EDGE_TPL`; the row-limit comment names the third cap.
8. `JQ_DEFS`: one new line directly after `def idv:` - `def colo: if type == "string" and test("\\A[A-Z]{3}\\z") then . else null end;`. The on-the-hour test is written inline in edit 12's guard condition (CTO T5: one use, no def).
9. The splice goes through `project()` (CTO D1, narrowing T1's "`project()` byte-identical" to "its `res=` jq line byte-identical"). `project` takes an optional second argument, a JSON member prefix; its `res=` line and `bad_jq` line stay byte-identical, and after the `bad_jq` line it gains:

   ```bash
     if [ -n "${2:-}" ]; then
       case "$res" in *$'\n'*) bad_shape ;; '{"'*'}') : ;; *) bad_shape ;; esac
       res="{$2,${res#\{}"
     fi
   ```

   The colo arm calls `project '<H program>' "$(printf '"zone":"%s","window_end":"%s"' "$CF_ZONE_ID" "$WIN_END")"`. F and G call `project` with one argument, so their output cannot change; `emit_ok` stays byte-identical (one caller). No second jq call site is added, so the census "jq and date are used in exactly 9 places (jq four times, date five times)" and the literals of W1.1, W1.6, W6.19 and W6.21 (each `edit_once`, exactly one match) stay as they are. `$CF_ZONE_ID` sits on a line with no `/usr/bin/jq`, so "no token, zone or account variable on any jq/date line" holds, and no `--arg` is added. Both spliced values already passed `ID_RE` and `STAMP_RE`, so they need no escaping, and no other environment value is printed (CLO ruling 3). A `res` that holds a newline or does not have the `{"...}` shape is `bad_shape` (CTO D5(3)). New PINNED whole lines: the `case "$res" in ...` line, the `res="{$2,${res#\{}"` line and the colo arm's `project ... "$(printf ...)"` line. New source row: "exactly one `project` call passes a second argument (the analytics-health-colo arm)". (Zone printed in full per CLO ruling 3; owner-review item 4 may switch it to a fingerprint, which changes only the spliced value.)
10. `gql_window`: keep the line `end=$((10#$t - 10#$t % 3600))` (two-space indent) byte-identical (mutation G1.H4 at suite L2141 searches for that literal) and add the next line `end=$((end - END_OFFSET * 3600))` (same indent); the F/G path change is purely additive (`END_OFFSET` is 0 there).
11. New `need_colo_args "$@"`, written with `if` (never a second `case "$SUB"`): arity exactly 3 (its own fixed usage message naming `analytics-health-colo <hours> <end-offset-hours>`), then `need_hours "$1" "$2"` (the one source of the hours grammar, bound and messages), then the offset by `^(0|[1-9][0-9]{0,2})$` FIRST and only then the bound, written fail-closed as `[ "$3" -le "$MAX_OFFSET" ] || die 64 ...` (never `-gt`: `[ 99999999999999999999 -gt 527 ]` returns rc 2, so a `-gt` refusal is skipped, and `$((x*3600))` wraps negative; CTO D4), each refusal its own fixed, value-free message at exit 64; no `[[ ... -gt ... ]]` or `(( ))` ever touches a raw argument (both evaluate it as arithmetic); sets `END_OFFSET` (`need_hours` sets `HOURS`). `MAX_OFFSET=527` carries no trailing comment, so the `components.test.ts` pin can mirror the `^MAX_HOURS=(\d+)$` form.
12. New `sub_analytics_health_colo`: `gql_window`; `body=$(gql_fill "$GQL_COLO_TPL")`; `cf_graphql "$body"`; `guard_gql` with the F condition, its hour test tightened inline to `test("\\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:00:00Z\\z")` (CLO 1(e)), plus `(.dimensions.coloCode == null or (.dimensions.coloCode | type) == "string")` (a non-matching string or null projects as `null`; the raw value is never printed; a number fails the guard); `QLIMIT=10000`; the H projection through `project` with the edit 9 prefix argument.
13. Argument handling: the first `case "${1:-}"` adds `analytics-health-colo` to the analytics alternation.
14. Dispatcher: `analytics-health-colo) need_colo_args "$@"; TOKVAR=CF_API_TOKEN_ANALYTICS_READ; load_credential zone; sub_analytics_health_colo ;;` before the `*)` arm.
15. The "What to do next" table gains nothing new (the H outcomes are F's), but its heading line says it covers F, G and H; it stays in step with the runbook table.

### Suite edits (`plugins/soleur/test/cloudflare-readonly.test.sh`), written first (RED)

- A new array `COLOSUBS=(analytics-health-colo)` joins `ALLSUBS`; `ANSUBS` stays the two one-argument reads, because every `ANSUBS` loop runs `"$an" <hours>` with one argument and expects the one-argument arity message (grammar rows near `MSG_ARITY_AN`, token rows, the fake-clock `run "$an" "$h"` loops). The new read gets dedicated loops for those groups.
- Per-subcommand `case` helpers each gain the new arm with its two-argument vector: `sargs`, `tok_of`, `tokvar_of`, `url_of`, `ok_body`, `check_wire` (the POST vector), `status_cells` (`w400=api-error`), and `tpl_of`.
- Census rows that move, each restated EXACTLY (never "at least"): the parity rows "SUBCOMMANDS array / dispatcher case labels / --list output ... length 6" -> 7 and "array equals the six expected names"; "census: dispatcher arm terminators == 7 (six arms plus the refusing default)" -> 8 (seven arms); "source: exactly two cf_graphql callers" -> three; "source: the two body assignments and the two cf_graphql calls are the exact lines" gains the colo body line; "source: body is assigned in exactly three places" -> four; "source: every constant whose name holds TPL is one of the two query templates" -> three; "source: anchor - exactly two query template constants" -> three; "source: each analytics subcommand body holds exactly one cf_graphql call" gains `sub_analytics_health_colo` (`1/1/1`); "the analytics token is bound only by the two analytics arms" `2/2` -> `3/3`; the template-content rows that grep `^GQL_(HEALTH|EDGE)_TPL=` widen to `^GQL_(HEALTH|EDGE|COLO)_TPL=` (else the new template escapes the template-content checks) and their ASC/DESC tally moves from `1/1` to `2/1`; the suite-side `^TPL_(HEALTH|EDGE)='` count row widens to three; in `components.test.ts` the `arrNames.length` 6 row -> 7. The one-POST-site / one-GET-site census stays `1/1`, and the jq/date census stays at 9 (CTO D1).
- Mutation rows whose expected-failing substring quotes a renamed row label are updated in the same commit: G1.A8 (the dispatcher-arm-count label), G1.A9, G1.A9b and W6.9 (the cf_graphql-caller label), and any other `mutate` line found by `grep -n 'mutate' <suite> | grep -F '<old label>'` for each renamed label. No mutation row's SEARCH literal is on a line this PR rewrites: W1.6, G1.H4, G1.H4b, W6.19 and W6.21 keep their literals, which stay present exactly once (`edit_once` fails on zero or two matches, so the colo arm must not add a second line containing `jq -c --argjson limit` or `--argjson limit "$LIMIT"`; see edit 9).
- QLIMIT tie (L553) is rewritten per function: the `QLIMIT=` line inside `sub_analytics_edge_errors` equals `GQL_EDGE_TPL`'s `limit:` and the one inside `sub_analytics_health_colo` equals `GQL_COLO_TPL`'s (today's `tail -n 1` form would pick the colo arm's 10000 and fail loudly against the edge template's 1000, so the row has to be rewritten either way). Mutation rows G1.Q1 (expected label "QLIMIT's value equals the edge query's limit") and G1.A12o quote that row's label or its `QLIMIT=1000\n` (two-space indent) literal; G1.Q1's expected label is updated to the rewritten edge row's label in the same commit, and a twin G1.Q1c (`QLIMIT=10000\n` (two-space indent) -> `QLIMIT=9999\n` (two-space indent)) expects the colo row's label. The `QLIMIT=1000\n` (two-space indent) literal does not match the new `QLIMIT=10000\n` (two-space indent) line (the newline follows a fifth digit), so both rows still match once.
- Template block: `TPL_COLO` duplicated from the wrapper; `tpl_of` gains the arm; `check_body` takes the offset (F and G call sites pass `0`) and checks the masked body equals `TPL_COLO` and the two stamps equal `floor(FAKE_T) - O h - H h` and `floor(FAKE_T) - O h` under `make_variant fakeclock`, for (H, O) in {(1,0), (24,0), (216,0), (1,527), (216,527), (100,250), (216,250)}; the F and G fake-clock rows stay with `O = 0`.
- Grammar rows (each: exit 64, the exact fixed message, zero curl calls, and the same with no token set, so 64 wins over 10): missing offset; a fourth argument; offset `""` (catches a `${3:-0}` default), `-1`, `01`, `+5`, `1e3`, a trailing space after `5`, `528`, `1000` (the regex refusal, told apart from the bound refusal by its message), a 20-digit `99999999999999999999` (the regex message; catches a regex widened to `[0-9]+`, which bash arithmetic would wrap past `<= 527`), a non-ASCII digit; `H=0, O=0`; `H=217, O=0`; `H=217, O=526` (sum 743 but H over); `H=1, O=528` (O over, sum within 743); `H=216, O=527` accepted (sum exactly 743). No separate `MAX_HOURS + MAX_OFFSET` source row (CTO T5). Two canary rows (CTO D5(2)): the environment `END_OFFSET='a[$(touch canary)]'` on the F and H arms (no canary file, F's stamps unchanged), and the same string as `$3` (exit 64, no canary file).
- Status cells: the new arm through all 15 outcomes, floor `all 7 subcommands x 15 outcomes` `>= 105` (L1085).
- Projection rows: valid colos sorted by `[hour, colo]` when the fixture is out of order; `"lhr"`, `"LH1"`, `"LHRX"`, `""` and `null` each project `null` (a numeric `coloCode` fails the guard and is a `shape_bad` row, `bad-response (shape)`), `series` is sorted on the CLEANED `colo` value (the sort runs after `colo`, so a rejected raw code never decides the order), and a canary non-matching value (for example `"QQ9CANARY"`) appears nowhere in stdout or stderr (CTO reconciliation (b)); an hour `2026-11-07T23:30:00Z` (not on the hour) is `bad-response (shape)`; `zone` equals the alternate zone id the run used; the spliced `window_end` and `window_hours` rows run inside the `make_variant fakeclock` block with O > 0 and compare to arithmetic on `FAKE_T`, never to the suite's own `date` (CTO D4; this also covers Guard 1 mutation 2); one hour holds `"AMS"` and `"lhr"`, so the raw sort and the cleaned sort differ; a `make_variant` row whose colo projection emits two values is `bad-response (shape)` (the D1 case line); `truncated` false at 9999 rows and true at 10000; a shape-bad body (missing `dimensions`, a non-RFC hour, a negative count, a duration above `1e7`) is `bad-response (shape)`; a GraphQL `errors` array is `api-error` with the bounded message rules unchanged; `zones: []` is `no-zone-access`; the redaction and leak rows cover the new arm.
- Floors: `PROJ_FLOOR`, the refuse floor (119), the mutation floor (196) and the assertion floor (1965) are raised to the exact new counts observed after GREEN (each row stays an exact-count statement, per its own comment). These lines are a KNOWN conflict with PR #12876, which rewrites the same floors (`PROJ_FLOOR` 172 -> 181, assertion floor 1965 -> 1993, and the mutation floor): no hunk placement avoids it. The PR body records this PR's per-floor delta; whichever PR merges second rebases, re-runs the full suite (about 155 s) and pins base plus both deltas from that run, never by adding the two deltas by hand.
- Guards that this change must keep intact: "no token, zone or account variable on any jq/date line", "no jq --arg / --args / --rawfile / --slurpfile / --jsonargs", the jq call-form census, and the mutation rows W1.6, W6.19, W6.21, G1.H4 and G1.H4b, and W1.1, whose search literals all stay present exactly once (`project()`'s `res=` line and the `end=` line are untouched). The PINNED whole-line block gains the three edit 9 lines. New projection and mutation rows are inserted away from #12876's suite inserts (about L1182, L1233, L2066): after the existing analytics projection block and at the end of the mutation list. Census and label strings are built from the expected-name arrays (`${#ALLSUBS[@]}`, `${#ANSUBS[@]}` + `${#COLOSUBS[@]}`) instead of literal 6/7/2/3, and the mutation rows G1.A8/A9/A9b/W6.9 search for labels built from the same variables (CTO T4).

### The falsification-recipe suite (new, CTO D3)

- `plugins/soleur/test/health-colo-falsification.test.sh`, pure jq, no network, no subprocess fan-out (under a second). It extracts the recipe from the one marker pair in `origin-tls-strict-flip.md` (asserting exactly one pair) and runs it with `/usr/bin/env -i /usr/bin/jq -r -f`.
- One synthetic fixture `plugins/soleur/test/fixtures/health-colo-falsification/base.json` in the evidence-file shape (synthetic zone id, not `5af02a2f`; `cq-test-fixtures-synthesized-only`). Each case is a named one-line jq patch on the base, inside the test.
- About 20 cases, each asserting the full output line: the three T2 classes, and both sides of each boundary: (i) a change point at 23Z with the 23Z p90 above the baseline max; (ii) exactly 24 after-hours only if 23Z were counted, so the colo is not judged; (iii) 5 versus 6 qualifying hours in cp+1..cp+24; (iv) a dip at cp+24 (breaks the run) versus cp+25 (does not); (v) missing rows inside the window (stepping is by clock hour, never by row position); (vi) count 9 versus 10, and p90 equal to the baseline max (not an exceedance); (vii) a non-sustained exceedance at 01Z followed by a sustained run from 06Z; (viii) the second `not supported` path (a non-positive judged colo with a sustained run starting at 01Z or later); (ix) `colo: null` rows all under count 10 (judging runs, counts printed) versus one at count 10 (`inconclusive: invalid-colo`).
- A row asserts that the addendum's outputs block equals the test's case-name and expected-line list, in order, so the runbook copy cannot drift from what was pre-registered.
- Seven recipe mutation rows at plan time (thirteen after the review rulings, see AC14) in the `edit_once` style, each of which must turn at least one case RED: 23Z counted as baseline; cp..cp+23; `>= 5`; stepping by row position; first exceedance only; drop the second `not supported` path; drop the D2 null rule. Plus an executed-row floor.
- CI: registered by `SUITE_GLOBS` `'plugins/soleur/test/*.test.sh'` (`scripts/test-all.sh`). `scripts/lib/test-affected-paths.sh` gains `AFFECTED_PLUGINS_SOLEUR_TEST_HEALTH_COLO_FALSIFICATION_TEST_SH_PATHS` naming the runbook (a real read), the fixture dir, the test and the file itself, in the existing `# THIS FILE` style. Unverified whether a runbook-only diff selects the suite without it: the work phase confirms with `bash scripts/test-all.sh --print-selection` on a staged runbook-only edit.

### Doc parity and decision records

- `standing-delegation.md` section 9 item 2, Boundary and Credentials: apply the CLO text from `knowledge-base/project/specs/feat-one-shot-12846-health-colo-split/clo-ruling-text.md` verbatim (see Domain Review, Legal). The pinned invocation `doppler run -p soleur -c prd_terraform -- plugins/soleur/scripts/cloudflare-readonly.sh <subcommand>` is unchanged.
- `plugins/soleur/test/components.test.ts`: `CF_SIX` -> `CF_SUBCOMMANDS` (seven names, count derived from its length, CTO T4); "its six subcommands" slice -> "its seven subcommands", count 7 (L941-942 and the self-test at L1115); the sd9 list pin at L787; the pinned `the two analytics subcommands each send one POST` (REQUIRED item 2 and the `sd9` row) -> `the three analytics subcommands each send one POST`; `VENDOR_SENTENCE` -> the CLO's Boundary text (section A); a new pin that item 2 states the wrapper's `MAX_OFFSET` and `MAX_HOURS + MAX_OFFSET` (`from 0 to ${MAX_OFFSET}` and `at most ${MAX_HOURS + MAX_OFFSET}`, so 527 and 743), mirroring the `MAX_HOURS` pin at L979-990; the five-token set and the `TOKVAR=` census stay at five; every other pin re-run unchanged. CLO caveats: do not backtick `CF_ZONE_ID` in the Credentials clause; the item 2 clause must contain none of `permits`, `except`, `unless`, `but`.
- ADR-289: `## Addendum 2026-11-19 (Ref #12846)` with the CLO paragraph, conditioned on the merge; `related:` gains 12846.
- `plugins/soleur/agents/engineering/cto.md:84`: read; edit only if it states a subcommand count.
- Runbook `origin-tls-strict-flip.md`: a new additions-only `##### Addendum 2026-11-19: the per-colo host-scoped read and its pre-registered test (Ref #12846)` placed after the 2026-11-16 addendum's last paragraph and before `#### What was NOT run before the flip`. It holds: the subcommand and what it does and does not cover (no `requestSource` filter, on purpose, per CTO F5); the pre-registered window (R1) and the falsification rule (R2 as replaced by CTO T2), verbatim from `decision-challenges.md`, stated BEFORE any H data is read, with the four terms T2 defines; the R2 jq recipe itself, as the ONE fenced block between `<!-- health-colo-r2-recipe:start -->` and `<!-- health-colo-r2-recipe:end -->` (input = one kept evidence file, output = one line `not supported` or `inconclusive: <reason>` with `null_colo_rows=<n> null_colo_qualifying=<m>`, plus the per-colo table), with its `inconclusive:` reasons as a closed, listed set that includes `invalid-colo`; the null-colo rule (CTO D2): `colo: null` rows are never judged, and any null-colo row with `count >= 10` makes the verdict `inconclusive: invalid-colo`; and the recorded outputs, as the block between `<!-- health-colo-r2-outputs:start -->` and `<!-- health-colo-r2-outputs:end -->` (one `<case name>: <expected line>` per case, in the test's order), recorded before any real H data exists and checked by the new suite below; the "other event" list for `[2026-11-07T22:43Z, 2026-11-08T00:43Z]` by pointer to this runbook's own records (the release deploy 23:47-23:50Z, the 00:14-00:15Z restart pair, the Doppler writes 22:54:34Z, 23:41:47Z, 00:13:25Z) plus `git log origin/main` for releases in that span, and that `change-history` cannot reach 2026-11-07; the statement that "supported" is not a reachable outcome (an origin-side release deploy shares the flip's hour), so the label stays "provisionally attributed" unless the outcome is "not supported"; the deadline (old zone deletion from about 2026-11-25; Doppler `CF_ZONE_ID` change by #12931); the ready-to-paste handoff loop for H (below); and the Class R line for this session's `analytics-health 216` read, with its evidence file moved to `knowledge-base/engineering/operations/runbooks/evidence/2026-11-19-analytics-health-216h.json` (`git mv` from the spec dir).

Handoff loop for the post-merge H read (the runbook copy is the one that runs):

```bash
d=knowledge-base/engineering/operations/runbooks/evidence; mkdir -p "$d"; sub=analytics-health-colo; fetched=yes
git fetch -q origin main || fetched=no
keep='.window_end == $e and .window_hours == $h and .zone == "5af02a2f394e9ba6e0ea23c381a26b67" and .rows > 0 and .truncated == false'
diag='"zone=\(.zone | tostring) rows=\(.rows) truncated=\(.truncated) window_end=\(.window_end) window_hours=\(.window_hours)"'
nulls='"null_colo_rows=\([.series[] | select(.colo == null)] | length) null_colo_qualifying=\([.series[] | select(.colo == null and .count >= 10)] | length)"'
h_read() { # $1 = H, $2 = window end E (YYYY-MM-DDTHH:00:00Z). 0 kept | 2 truncated only | 1 not kept
  [ "$fetched" != no ] || { echo "other: fetch-failed (git fetch origin main failed; nothing was read)"; return 1; }
  git diff --quiet origin/main -- plugins/soleur/scripts/cloudflare-readonly.sh || { echo "other: wrapper-drift"; return 1; }
  local H="$1" Es="$2" E now O err out rc line1 j f
  [[ "$Es" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:00:00Z$ ]] || { echo "refused: E is not an on-the-hour UTC stamp"; return 1; }
  E=$(date -u -d "$Es" +%s) || { echo "refused: date could not read E=$Es"; return 1; }
  now=$(date -u +%s); O=$(( (now - now % 3600 - E) / 3600 ))
  [[ "$O" =~ ^[0-9]+$ ]] || { echo "refused: H=$H O=$O is not a whole number of hours (E in the future?)"; return 1; }
  err=$(mktemp); out=$(doppler run -p soleur -c prd_terraform -- plugins/soleur/scripts/cloudflare-readonly.sh "$sub" "$H" "$O" 2>"$err"); rc=$?
  line1=$(printf '%s\n' "$out" | sed -n 1p); j=$(printf '%s\n' "$out" | sed -n 2p); f="$d/$sub-${H}h-end$(date -u -d "$Es" +%Y%m%dT%HZ).json"
  if [ "$rc" -eq 0 ] && [ "$line1" = "cloudflare-readonly: $sub ok" ] && printf '%s\n' "$j" | /usr/bin/env -i /usr/bin/jq -e --arg e "$Es" --argjson h "$H" "$keep" >/dev/null 2>&1; then
    rm -f "$err"
    if [ -L "$d" ] || [ -L "$f" ]; then echo "refused: $f or its directory is a symlink"; return 1; fi
    ( set -C; printf '%s\n' "$j" > "$f" ) || { echo "refused: $f already exists"; return 1; }
    echo "kept $f, read at $(date -u +%FT%TZ), $(printf '%s\n' "$j" | /usr/bin/env -i /usr/bin/jq -r "$nulls")"; return 0
  fi
  echo "$sub H=$H E=$Es: not kept, rc=$rc, stdout line 1: ${line1:-none}, stderr line 1: $(sed -n 1p "$err"), line 2: $(printf '%s\n' "$j" | /usr/bin/env -i /usr/bin/jq -r "$diag" 2>/dev/null || echo 'not JSON')"; rm -f "$err"
  if [ "$rc" -eq 0 ] && printf '%s\n' "$j" | /usr/bin/env -i /usr/bin/jq -e '.truncated == true' >/dev/null 2>&1; then return 2; fi
  return 1
}
h_read 216 2026-11-12T12:00:00Z; r=$?
if [ "$r" -eq 2 ]; then
  h_read 108 2026-11-12T12:00:00Z; r1=$?; h_read 108 2026-11-08T00:00:00Z; r2=$?
  q1=-; q2=-; q3=-; q4=-
  if [ "$r1" -eq 2 ]; then h_read 54 2026-11-12T12:00:00Z; q1=$?; h_read 54 2026-11-10T06:00:00Z; q2=$?; fi
  if [ "$r2" -eq 2 ]; then h_read 54 2026-11-08T00:00:00Z; q3=$?; h_read 54 2026-11-05T18:00:00Z; q4=$?; fi
  echo "split reads: H=108 $r1 $r2, H=54 $q1 $q2 $q3 $q4 (0 kept; 1 not kept: record that line; 2 truncated at H=54: record other: truncated; - not needed)"
fi
h_read 216 2026-11-18T17:00:00Z   # archival capture of the old zone's last full week; never a verdict input
```

Keep rules (CTO T3): rc 0, line 1 exactly `cloudflare-readonly: analytics-health-colo ok`, `.window_end == E`, `.window_hours == H`, `.zone` exactly `5af02a2f394e9ba6e0ea23c381a26b67` (the old zone named in #12931, compared in full so no prefix can collide; a read of any other zone is not the flip-window record; CTO Q7), `.rows > 0`, `.truncated == false`. A truncated main read falls back to two H=108 reads split exactly at 2026-11-08T00Z (a half that truncates again is split once more, at its midpoint, into two H=54 reads; the loop runs those itself). The `.window_end` check also makes a read whose offset was computed in a different hour from the wrapper's own clock fail closed; re-run it. The archival capture (H=216 ending 2026-11-18T17:00Z) is never a verdict input and has no fallback: if it is not kept, its not-kept line goes into the capture comment and nothing is re-read. The loop needs GNU `date` (`-d`), as the wrapper does. Hardening (CTO D5): the fetch and wrapper-drift checks run before every read and never `exit` (a pasted interactive shell would close), and a failed `git fetch` refuses the read rather than skipping the drift check; `E` and `O` are checked by shape, and the offset's range is left to the wrapper's own bound, which refuses with exit 64 and sends nothing (CTO Q9, D5 amended); evidence files are named by the read's window end, so a re-run in a later hour or on a later day refuses rather than writing a second file; the evidence write is one noclobber write, so an existing file or a dangling symlink refuses it; every jq in the loop runs under `env -i`, so a planted `~/.jq` cannot redefine a builtin. The kept line prints `null_colo_rows=<n> null_colo_qualifying=<m>` (CTO D2); a not-kept line prints the full zone id (it is public, and a wrong zone can share any prefix), `rows`, `truncated`, `window_end` and `window_hours`. The arithmetic, the keep predicate (old zone kept; new zone and `rows: 0` refused), the refusals and `bash -n` were run on 2026-11-19 against a stub `doppler` and synthetic line-2 values; the real `doppler run` line is first exercised by the post-merge read.

## Implementation Phases

### Phase 0 — Baseline (no repository change)

- 0.1 `git fetch origin main feat-one-shot-12742-public-sdk-url-poll feat-one-shot-12712`; record the merge-base.
- 0.2 Run `bash plugins/soleur/test/cloudflare-readonly.test.sh` and `bun test plugins/soleur/test/components.test.ts` on the untouched branch; record pass counts and the suite's wall time (about 155 s per `scripts/suite-durations.tsv:204`).
- 0.3 `bash plugins/soleur/test/c4-count-parity.test.sh` green on the baseline.

### Phase 1 — Tests first (RED)

- 1.1 The suite edits above, all of them, before any wrapper edit; run the suite and confirm the new rows fail for the right reason (unknown subcommand, missing template, parity 6 vs 7).
- 1.2 The `components.test.ts` edits; confirm they fail against the unchanged section 9.

### Phase 2 — Wrapper (GREEN)

- 2.1 Wrapper edits 1-15 above. Run the suite to green, then raise the four floors to the exact observed counts and re-run.
- 2.2 Run the full mutation battery (the suite's own mutation group) and confirm every new mutation row in the Guard Contract below is caught.

### Phase 3 — Doc parity and decision records

- 3.1 Apply the CLO text to section 9; `bun test plugins/soleur/test/components.test.ts` green.
- 3.2 ADR-289 addendum and `related:`.
- 3.3 `cto.md:84` check.

### Phase 4 — Runbook addendum and the moved evidence file

- 4.1 `git mv knowledge-base/project/specs/feat-one-shot-12846-health-colo-split/2026-11-19-analytics-health-216h.json knowledge-base/engineering/operations/runbooks/evidence/2026-11-19-analytics-health-216h.json`.
- 4.2 Write `health-colo-falsification.test.sh`, its base fixture and the `test-affected-paths.sh` entry first, and confirm RED (no marker pair yet).
- 4.3 The runbook addendum above (additions-only; rows named by anchor text, never by line number), with the recipe and outputs blocks; the new suite goes GREEN and each of its seven mutation rows is caught.

### Phase 5 — Verify

- 5.1 Full cloudflare suite, `health-colo-falsification.test.sh`, `components.test.ts`, `c4-count-parity.test.sh`, markdown lint on the touched docs, `bash scripts/test-all.sh --affected`.
- 5.2 Merge-conflict check against the sibling (pre-push, not an acceptance criterion): `git merge-tree --write-tree origin/feat-one-shot-12742-public-sdk-url-poll HEAD` reports no conflict in `cloudflare-readonly.sh`, and in its test none outside the four floor lines (which conflict by construction, see Suite edits); the same against `origin/feat-one-shot-12712` for `standing-delegation.md`. A conflict elsewhere means moving the hunk, never editing the sibling's branch. If #12876 merges first, rebase, re-run, re-pin the floors.
- 5.3 `scripts/suite-durations.tsv` row 204 is not hand-edited (it is measured on merge_group runs); note the expected growth in the PR body.

### Phase 6 — PR and the #12931 sequencing comment

- 6.1 Push; update draft PR #12959 body: `Ref #12846`, `Ref #12441`, `Ref #10479` (never `Closes`, and no "fix" next to an issue number); confirm `closingIssuesReferences` is `[]`. Lead with the deadline. List the six CLO owner-review items from `clo-ruling-text.md` section E: (1) Class R Cloudflare reads widen from six to seven and the `cf_graphql` caller census from two to three; (2) a second caller integer, the end offset (0-527, span at most 743), reaching back just under 31 days, inside the documented retention; (3) the new `coloCode` breakdown and host filter, with the no-suppression determination scoped to `/health`; (4) the full zone id printed and committed to a public repository (the owner can require a short fingerprint instead); (5) a public per-colo, per-hour evidence JSON produced by a post-merge Class R run under a new dated filename; (6) the analytics token's scope on the current zone is unverified since the #12931 move.
- 6.2 One comment on #12931: the #12846 read must run against the old zone before Doppler `CF_ZONE_ID` changes, and the old zone may be deleted from about 2026-11-25; after the change, `CF_API_TOKEN_ANALYTICS_READ` reaching the new zone is unverified (a credential question for the owner, listed in #12931's token re-mint item).
- 6.3 Standing limits for this PR and session: no production apply, no workflow dispatch (including `apply-web-platform-infra.yml`), no credential or Doppler change. The PR is code and docs only.

### Post-merge follow-up (closes #12846; not this PR)

In the session that lands this PR, as a post-landing step (CTO T3; Class R, no typed go needed), from a fresh `origin/main` checkout where `git diff origin/main -- plugins/soleur/scripts/cloudflare-readonly.sh` is empty: run the handoff loop above and push the kept evidence files alone on a branch at once (the verdict comes later and has no deadline; the capture does). Hard date: 2026-11-24 (the old zone may be deleted from about 2026-11-25; paid-plan timing is undocumented). Then, in the PR that carries `Closes #12846`: run the pre-registered R2 recipe on the main capture and write the runbook addendum with its one-line outcome (`not supported` or `inconclusive: <reason>`) as an `Unverified:` record. If the old zone is gone or Doppler `CF_ZONE_ID` already names the new zone before the capture, record `Unverified: Cloudflare analytics-health-colo (H) #12846, other: no-zone-access` (or `other: wrong-zone`); the label stays "provisionally attributed" with the 2026-11-11 evidence file as the only pre-flip record.

## Files to Edit

- `plugins/soleur/scripts/cloudflare-readonly.sh`
- `plugins/soleur/test/cloudflare-readonly.test.sh`
- `plugins/soleur/test/components.test.ts`
- `plugins/soleur/skills/brainstorm-techniques/references/standing-delegation.md` (section 9 only)
- `knowledge-base/engineering/architecture/decisions/ADR-289-standing-delegation-and-production-envelope.md`
- `knowledge-base/engineering/operations/runbooks/origin-tls-strict-flip.md` (additions-only addendum)
- `plugins/soleur/agents/engineering/cto.md` (only if L84 states a count)
- `scripts/lib/test-affected-paths.sh` (one new `AFFECTED_..._PATHS` array, CTO D3)

## Files to Create

- `plugins/soleur/test/health-colo-falsification.test.sh` (CTO D3)
- `plugins/soleur/test/fixtures/health-colo-falsification/base.json` (synthetic)
- `knowledge-base/engineering/operations/runbooks/evidence/2026-11-19-analytics-health-216h.json` (moved by `git mv` from this branch's spec dir; the bytes are the wrapper's stdout line 2 of this session's Class R read)

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open`, 2026-11-19: no open issue body names any file above.)

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-289 with `## Addendum 2026-11-19 (Ref #12846)`, conditioned on the merge, carrying the CLO paragraph; `related:` gains 12846. Ruled by CTO agent, 2026-11-19 (F11): no new ADR. Decision in one line: the Class R Cloudflare reads widen from six to seven; the seventh is a third fixed read-only POST through the same single POST site, with a second caller integer that only moves the window end.

### C4 views

No C4 change. Checked against all three of `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` in the work phase (read in full, not grepped): (a) external human actors: none added (the owner and agent sessions are the existing operator); (b) external systems: Cloudflare is already modelled, and the GraphQL Analytics API is an endpoint of that system; agent-read edges to Cloudflare, Sentry and Better Stack are omitted by deliberate choice (ADR-289 2026-11-03 and 2026-11-04 addenda), and this change keeps that; (c) containers and data stores: none touched (the evidence file is a repository document); (d) actor-to-surface access relationships: none change. The 2026-11-18 account move is #12931's C4 question, not this plan's. `bash plugins/soleur/test/c4-count-parity.test.sh` is run green in Phase 0.3 and Phase 5.1.

### Sequencing

The addendum is written now and conditioned on the merge; nothing is deferred to a follow-up issue.

## Observability

```yaml
liveness_signal:
  what: the first stdout line of each wrapper run, `cloudflare-readonly: analytics-health-colo ok` or `cloudflare-readonly: analytics-health-colo unverified - <reason>`, plus the exit code (0, 10, 11, 14, 64, 78)
  cadence: per run (an on-demand reader; no daemon, no schedule)
  alert_target: the invoking agent or owner session reads the line in-session; nothing pages, by design (observability layer 7, cli-stdout-artifact)
  configured_in: plugins/soleur/scripts/cloudflare-readonly.sh (output contract in the header)

error_reporting:
  destination: stdout and stderr of the wrapper to the invoking session (layer 7 cli-stdout-artifact); no Sentry DSN. The script does ship in the hosted image (apps/web-platform/Dockerfile vendors plugins/soleur to /opt/soleur/plugin, and web-platform-release.yml triggers on plugins/soleur/** minus docs/ and test/), but a hosted run stops before any request: `guard_source` refuses with exit 64 unless DOPPLER_PROJECT=soleur and DOPPLER_CONFIG=prd_terraform, and `load_credential` exits 10 (`no-credential`) when CF_API_TOKEN_ANALYTICS_READ is absent; both lines are fixed and value-free, and both go to the caller's stdout
  fail_loud: a non-zero exit with a fixed value-free line (`no-credential`, `token-invalid`, `token-lacks-scope`, `no-zone-access`, `api-error`, `bad-response (shape)`, `upstream-error`) and, for api-error only, the bounded `graphql:` message

failure_modes:
  - mode: the old zone has been deleted, or Doppler CF_ZONE_ID already names the new zone that the token cannot read
    detection: exit 14 `unverified - no-zone-access` or exit 11 `unverified - token-lacks-scope` on the run, plus the printed `zone` field on any ok run (layer 7 cli-stdout-artifact)
    alert_route: the invoking session records the Unverified line; never answered by a token swap or a hand-written query
  - mode: the window is older than the dataset keeps, or wider than the plan allows
    detection: a GraphQL `errors` array gives exit 14 `unverified - api-error (graphql: <bounded message>)` (layer 7 cli-stdout-artifact)
    alert_route: the invoking session narrows H or records the result; not a wrapper fix PR unless the field names are at fault
  - mode: coloCode or the combined host and path filter is wrong for this node
    detection: exit 14 `api-error (graphql: unknown field ...)` or `bad-response (shape)` (layer 7 cli-stdout-artifact)
    alert_route: a wrapper fix PR, at most one for this query (CTO Q8; the cap of two belonged to F and G, #12441)
  - mode: result cut at the 10000-row cap
    detection: `truncated: true` in the projection (layer 7 cli-stdout-artifact)
    alert_route: the reader re-runs with a smaller H; a truncated read is never a verdict input
  - mode: a colo code the dataset spells differently (lowercase, digits, longer)
    detection: `colo: null` rows in the projection (layer 7 cli-stdout-artifact)
    alert_route: the reader records them as `colo: null` rows (their count is printed on the handoff loop's kept line); a repeat is a wrapper fix PR under the same cap
  - mode: bad arguments or tracing (hours outside 1-216, offset outside 0-527, wrong arity, shell tracing with a live credential)
    detection: exit 64 with a distinct fixed message per cause, or exit 78 for tracing, before any request (layer 7 cli-stdout-artifact)
    alert_route: the invoking session re-runs correctly; nothing is recorded for a usage error
  - mode: silently misleading figure (sampled counts, few requests per colo-hour)
    detection: the fixed `note` field and the pre-registered count >= 10 rule in the runbook addendum (layer 7 cli-stdout-artifact)
    alert_route: the reader applies the R2 rule; an unqualified colo-hour never enters the change-point test
  - mode: Cloudflare outage or rate limit
    detection: 429 or 5xx gives exit 14 `unverified - upstream-error` (layer 7 cli-stdout-artifact)
    alert_route: one re-run after a pause; the newest line governs

logs:
  where: none persisted by the wrapper; the durable artifacts are the committed evidence JSON under knowledge-base/engineering/operations/runbooks/evidence/ and the Unverified Records line in the runbook addendum
  retention: git history

discoverability_test:
  command: bash plugins/soleur/scripts/cloudflare-readonly.sh --list
  expected_output: analytics-health-colo
```

## Guard Contract

### Guard 1 — The new read sends only a compiled-in query with wrapper-computed stamps

**Property.** Every request `analytics-health-colo` can make is one POST to `https://api.cloudflare.com/client/v4/graphql` whose body equals `GQL_COLO_TPL` with only the validated zone id and two stamps substituted, the stamps being `[E - H h, E)` with `E = floor(now) - O h`, and neither caller integer appearing in the body.

**Assembly.** The single POST call site in `cf_graphql` (pinned whole-line), the `cf_graphql` callers (exactly three after this change: one per analytics arm), the `body=$(gql_fill ...)` assignments (exactly one per arm), the three `*TPL*` constants and the suite's duplicated template block (`TPL_HEALTH`, `TPL_EDGE`, `TPL_COLO`), `gql_window` (the one place `END_OFFSET` is applied), `gql_fill`, the dispatcher arm, and `check_body`'s masked-body equality under the fake clock. The chokepoint is `cf_graphql`; the arms are its members and are counted, not listed.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Interpolate the raw offset argument `$3` into `GQL_COLO_TPL` or into `body` | RED (masked body equals `TPL_COLO`; hostile-integer rows) |
| 2 | Apply the offset to the start only (end stays `floor(now)`) | RED (fake-clock body `datetime_lt` rows and the spliced `window_end` rows for O > 0) |
| 4 | Dispatch: remove the new arm so the dispatcher census reports 7 terminators | RED (arm census 8; parity 7; the guard's own dispatch cannot report "0 checked") |
| 5 | Add a fourth `cf_graphql` caller after the three compliant ones (a copy of the colo arm) | RED (caller census exactly 3) |
| 6 | Change `limit:10000` in `GQL_COLO_TPL` without changing its `QLIMIT` | RED (the per-function QLIMIT tie) |
| 7 | Reorder: compute `WIN_START` from `floor(now) - H h` before subtracting the offset (start and end no longer `H` apart) | RED (the fake-clock body rows check both stamps against `FAKE_T`) |
| 8 | Harness row: make `check_body` compare against `TPL_HEALTH` for every arm | RED (the colo arm's masked body differs; a control fixture feeds a health body to the colo check and expects a failure) |
| 9b | Put `CF_ZONE_ID` (or the splice values) on the `project()` jq line or pass them with `--arg` instead of the bash splice | RED (the "no token, zone or account variable on any jq/date line" and "no jq --arg" source rows) |
| 9 | Harness row: make the fake clock ignore the variant (real clock used) | RED (the fake-clock control that checks the stamp equals the `FAKE_T`-derived value, not merely a valid stamp) |
| D1.M1 | Drop the prefix argument from the colo arm's `project` call | RED (AC5 `zone`/`window_end` rows) |
| D1.M2 | Delete the `res="{$2,${res#\{}"` line | RED (the same rows and the PINNED block) |
| D1.M3 | Give the `analytics-health` arm the same prefix | RED (F's projection rows and the one-caller row) |
| D1.M4 | Change the case line's `*$'\n'*) bad_shape` arm to `*$'\n'*) : ;;` | RED (the two-value `make_variant` row) |
| D5.M1 | `END_OFFSET=0` -> `: "${END_OFFSET:=0}"` | RED (the environment canary rows) |

Must-PASS inputs that are not the canonical: (H, O) = (1, 0), (216, 0), (1, 527), (216, 527), (100, 250); an alternate zone id; an alternate valid token.

**Anchor.** The template and its suite duplicate live in two files of the same PR, so one commit can move both; the outside anchors are the `components.test.ts` pins against section 9's text (a separate review surface the owner reads on the draft PR), the CLO ruling text committed in the spec dir, and the run-only-from-`origin/main` rule.

### Guard 2 — The two caller integers are refused before any credential or request

**Property.** For `analytics-health-colo`, any argument vector other than exactly two whole numbers with `1 <= H <= 216` and `0 <= O <= 527` (so `H + O <= 743` by construction) exits 64 with a fixed value-free message, reads no credential and makes no curl call.

**Assembly.** The first `case "${1:-}"` alternation, `need_colo_args` (arity, two regexes, two bounds), the dispatcher's order (`need_colo_args` before `load_credential`), `MAX_HOURS`/`MAX_OFFSET`, the suite's grammar rows, and the `components.test.ts` pins tying section 9's numbers (`1 to 216`, `0 to 527`, `at most 743`) to those constants.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Raise `MAX_OFFSET` to 528 (the span would reach 744, past the 31-day floor) | RED (the `components.test.ts` pins of section 9's `0 to 527` and `at most 743`, and the `H=1, O=528` refusal row) |
| 2 | Accept a leading zero (`^[0-9]{1,3}$`) | RED (`01` row) |
| 3 | Move `need_colo_args` after `load_credential` | RED (bad offset with no token must exit 64, not 10) |
| 4 | Dispatch: the arm calls `need_hours "$@"` instead (arity 2) | RED (every valid three-argument row exits 64) |
| 5 | Validate the offset, then validate a second, extra argument loosely (accept a fourth argument after a valid third) | RED (fourth-argument row) |
| 7 | Echo the offending value in the refusal message | RED (value-free message rows: the exact fixed string) |
| 8 | Harness row: a grammar row that only checks `rc != 0` | RED (each row asserts the exact message and `ncalls == 0`; a control injects a refusal with a curl call and expects the row to fail) |
| 9 | Widen the offset regex to `^(0\|[1-9][0-9]*)$` | RED (the `1000` and 20-digit rows assert the regex message; the bound would refuse `1000` with a different message) |
| 10 | Write the bound as `[ "$3" -gt "$MAX_OFFSET" ] && die 64 ...` together with mutation 9 | RED (the 20-digit row: `-gt` is rc 2 and the refusal is skipped) |

Must-PASS inputs that are not the canonical: `H=216, O=527` (the span exactly 743), `H=1, O=0`, `H=1, O=527`.

**Anchor.** `components.test.ts` compares section 9's stated bounds with the wrapper's own constants, so a bound cannot move in the code alone; the owner reviews section 9 on the draft PR.

### Guard 3 — A Cloudflare value reaches output only in its checked shape (CLO condition 1(e))

**Property.** In the H projection, `colo` is either three capital ASCII letters or `null`, `hour` is only `YYYY-MM-DDTHH:00:00Z`, a raw non-matching colo value appears nowhere in stdout or stderr, and `series` is ordered on the cleaned values.

**Assembly.** The `colo` jq def (after `def idv:`), the guard condition's inline on-the-hour test and `coloCode` type clause in `sub_analytics_health_colo`, the projection's `| colo` and its sort, and the suite's projection rows (the `"lhr"`/`"LH1"`/`"LHRX"`/`""`/`null` rows, the `QQ9CANARY` row, the `23:30:00Z` row, and the hour holding `"AMS"` and `"lhr"`).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop `\| colo` in the projection (raw `coloCode` printed) | RED (the `null` rows and the canary row) |
| 2 | Replace the inline on-the-hour test with `rfc` | RED (the `2026-11-07T23:30:00Z` row expects `bad-response (shape)`) |
| 3 | Drop the `coloCode` type clause from the guard | RED (the numeric `coloCode` row expects `bad-response (shape)`) |
| 4 | Sort on the raw `coloCode` before `colo` runs | RED (the `"AMS"`/`"lhr"` hour: the raw sort puts AMS first, the cleaned sort puts `null` first) |
| 5 | Widen the `colo` def to `\A[A-Z]{3,4}\z` | RED (the `"LHRX"` row) |

Must-PASS inputs that are not the canonical: an hour with several valid colos out of order; a body with only `null` colos.

**Anchor.** CLO condition 1(e) in `clo-ruling-text.md` and section 9 item 2's text (pinned by `components.test.ts`), reviewed by the owner on the draft PR.

## User-Brand Impact

- **If this lands broken, the user experiences:** no end-user surface changes. The owner and agent sessions get a failed or misleading per-colo read (a wrong window, a wrong zone, mis-sorted colos), which could keep or wrongly lift the "provisionally attributed" label on the strict TLS hop and steer a production decision about the Cloudflare-to-origin TLS mode that serves every `app.soleur.ai` user.
- **If this leaks, the user's data is exposed via:** the committed evidence JSON in a PUBLIC repository (per-hour, per-colo sampled request counts and origin timings for `app.soleur.ai/health`; no IP, user agent, URL query, referrer or per-visitor field is selected), and the analytics token if the stdin-only credential path regressed (pinned by the existing leak rows, extended to the new arm).
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** an internal operator read of aggregate infrastructure timings; no user data is selected and no user-facing path changes, so one bad read is an operator error, not a user incident. `threshold: none, reason: the diff touches no sensitive path (no apps/*/server, infra, auth, Doppler-script or credential-workflow file); it adds one read-only aggregate query to an operator-only wrapper.`

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Add a read-only subcommand, or a flag on `analytics-health`, to the wrapper's closed subcommand set (ADR-289)" [issue #12846] | Wrapper edits 7, 11-14; CTO F1 | mapped |
| 2 | "It must not be a manual GraphQL path." [issue #12846] | `GQL_COLO_TPL` compiled in; Guard 1 | mapped |
| 3 | "filter on the host `app.soleur.ai` as well as the path `/health`" [issue #12846] | `GQL_COLO_TPL` filter; CTO F5 | mapped |
| 4 | "group by `coloCode` (site split)" [issue #12846] | `GQL_COLO_TPL` dimensions; `colo` def; CTO F7 | mapped |
| 5 | "take an end-time offset, so a window that ends before now can be read and a pre-flip baseline stays reachable" [issue #12846] | `need_colo_args`, `gql_window`; Guard 2; CTO F2, F3 | mapped |
| 6 | "Its results stay `Unverified:` records, like the existing analytics reads" [issue #12846] | Header Records mapping H; runbook addendum | mapped |
| 7 | "are saved to `knowledge-base/engineering/operations/runbooks/evidence/<UTC date>-analytics-<subcommand>-216h.json` and committed" [issue #12846] | Handoff loop; CTO F12 filename | mapped (filename refined by CTO F12) |
| 8 | "The subcommand or flag is merged with its suite." [issue #12846] | Phases 1-6 | mapped |
| 9 | "One sanctioned read is committed as an evidence file, and the runbook records whether the p90 step meets the evidence bar" [issue #12846] | Post-merge follow-up (closes #12846); R1, R2 pre-registered in this PR's runbook addendum | descoped — justification: section 9 item 2 allows the read only from a checkout matching `origin/main`, so it cannot run before this PR merges (CTO F9); this PR uses `Ref #12846` and the issue stays open for it |
| 10 | "any zone/account id the query uses must be the current one or read from config — check against #12931 before hard-coding" [brief] | `CF_ZONE_ID` only; `zone` printed; CTO F4; Research Reconciliation | mapped |
| 11 | "no production apply, workflow dispatch, or credential change without the owner's typed go; do not dispatch apply-web-platform-infra.yml before #12931 lands" [brief] | Phase 6.3 | mapped |
| 12 | "whether the Free plan's analytics dataset/retention supports the coloCode group-by; verify against Cloudflare GraphQL docs" [brief] | Research Insights fact sheet; Research Reconciliation | mapped |
| 13 | "Keep your edits away from those hunks to minimise merge conflict; do not edit or comment on that PR." [brief] | Technical Approach hunk rule; Phase 5.2 merge-tree | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `plugins/soleur/scripts/cloudflare-readonly.sh` | asks 1-5, 10 | asked |
| `plugins/soleur/test/cloudflare-readonly.test.sh` | "merged with its suite" (ask 8) | asked |
| `plugins/soleur/test/components.test.ts` | — | inferred — justification: the doc-parity pins fail when the subcommand count and the argument bounds change (`CF_SIX`, "its six subcommands"); without the edit the suite is RED |
| `standing-delegation.md` section 9 | — | inferred — justification: section 9 item 2 is the Class R contract that names every subcommand and its argument grammar; a read outside its text is not Class R (CLO ruling) |
| ADR-289 addendum | — | inferred — justification: plan Phase 2.10 (the closed-set membership is an ADR-289 decision; CTO F11) |
| Runbook addendum (pre-registered R1/R2, handoff loop, deadline) | "the runbook records whether the p90 step meets the evidence bar" (ask 9) | asked (the verdict itself is the follow-up's; pre-registration must precede the read, CTO R2) |
| Moved evidence file `2026-11-19-analytics-health-216h.json` | "are saved to ... evidence/ ... and committed" (ask 7) | asked (the runbook's "never leave a read in a session scratchpad" rule applies to this session's read) |
| `cto.md:84` check | — | inferred — justification: the only other prose that names the wrapper; edited only if it states a count |
| `health-colo-falsification.test.sh`, its fixture, the `test-affected-paths.sh` entry | "the runbook records whether the p90 step meets the evidence bar" (ask 9) | inferred — justification: the pre-registered recipe decides that record once, on data that cannot be re-read after the old zone is deleted; CTO D3 requires a committed test so the rule and its recorded outputs cannot drift |
| #12931 sequencing comment | "check against #12931" (ask 10) | asked |

### Split Assessment

- Subsystems touched: 2 — `plugins/soleur`, `knowledge-base`
- Planned files: 11 | Estimated changed lines: about 700 (wrapper about 70, suite about 320, falsification suite and fixture about 160, components about 30, test-affected-paths about 8, docs about 110)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Class R Checks

Unverified: Cloudflare analytics-health (F) #12441 (premise read for #12846): cloudflare-readonly.sh via doppler prd_terraform, ok, 199 contiguous hourly rows 2026-11-10T10Z to 2026-11-18T16Z and no rows after (the configured zone is the old zone; its traffic ends at the 2026-11-18 move), 2026-11-19T10:03:19Z
Unverified: whether CF_API_TOKEN_ANALYTICS_READ can read the new zone, other: not-class-r (the wrapper reads only Doppler's CF_ZONE_ID, which names the old zone), 2026-11-19T10:03Z

## Acceptance Criteria

### Pre-merge (this PR)

- [ ] AC1 `bash plugins/soleur/scripts/cloudflare-readonly.sh --list` prints seven lines, one of them exactly `analytics-health-colo`, exit 0, no curl call (suite parity rows).
- [ ] AC2 Under the suite's fake clock, `analytics-health-colo H O` sends exactly one POST whose masked body equals `TPL_COLO` and whose stamps are `floor(FAKE_T) - (O + H) h` and `floor(FAKE_T) - O h`, for every (H, O) in the Guard 1 must-PASS list (`check_body` rows).
- [ ] AC3 Every refused argument vector in the grammar rows exits 64 with its exact fixed message and zero curl calls, with and without a token set (Guard 2).
- [ ] AC4 `analytics-health` and `analytics-edge-errors` bodies, windows and projections are unchanged: under the fake clock their masked bodies still equal `TPL_HEALTH`/`TPL_EDGE` with stamps `floor(FAKE_T) - H h` and `floor(FAKE_T)`, and their projection rows pass. In `git diff -U0 origin/main...HEAD -- plugins/soleur/test/cloudflare-readonly.test.sh`, the only changed lines that mention `analytics-health` or `analytics-edge-errors` are the `check_body` call sites gaining the `0` offset argument, the per-function QLIMIT tie, the census rows listed under Suite edits, and the helper `case` arms.
- [ ] AC4b The source rows "no token, zone or account variable on any jq/date line" and "no jq --arg / --args / --rawfile / --slurpfile / --jsonargs", and the mutation rows G1.H4, W6.19 and W6.21, are byte-identical to `origin/main` (`git diff origin/main -- plugins/soleur/test/cloudflare-readonly.test.sh` shows no change on those lines); none of these literals change, and neither does W1.6's (`project()`'s `res=` line is untouched).
- [ ] AC5 The H output line 2 begins `{"zone":"<CF_ZONE_ID>","window_end":"<stamp>",` and then carries `subcommand`, `window_hours`, `rows`, `truncated`, `note` and a `series` sorted on the cleaned `[hour, colo]`; it carries no `window_start` or `end_offset_hours`; a non-matching colo projects `null` and its raw value appears nowhere in stdout or stderr (projection rows); F's and G's line 2 are unchanged (AC4).
- [ ] AC6 Every mutation row of Guards 1, 2 and 3 is caught (the suite's own "every mutation row ran and was caught" row). Each of the four floors rises from its `origin/main` value by exactly the number of rows of its kind this PR adds; the PR body lists each floor's baseline, delta and new value, and a reviewer checks the delta against the count of added rows in the diff.
- [ ] AC7 `bun test plugins/soleur/test/components.test.ts` is green with the seven-name and the `MAX_OFFSET` / `MAX_HOURS + MAX_OFFSET` pins; section 9 carries the CLO text verbatim from `clo-ruling-text.md`.
- [ ] AC8 ADR-289 has `## Addendum 2026-11-19 (Ref #12846)` and `related:` contains 12846; `bash plugins/soleur/test/c4-count-parity.test.sh` is green.
- [ ] AC9 The runbook addendum contains R1 and R2 verbatim (each matched by `grep -F` on its first sentence from `decision-challenges.md`), the alternative-event list for the window by pointer to the runbook's existing records, the deadline line, and the evidence file `knowledge-base/engineering/operations/runbooks/evidence/2026-11-19-analytics-health-216h.json` exists and parses with `jq -e .`; no `analytics-health-colo` figure appears anywhere in the runbook (the only H data is post-merge).
- [ ] AC10 Every wrapper hunk in `git diff -U0 origin/main...HEAD -- plugins/soleur/scripts/cloudflare-readonly.sh` (three dots: measured against the merge base, so a sibling PR that lands first does not show reversed) starts and ends at least three unchanged lines away from these content anchors of the merge-base wrapper (`git show $(git merge-base origin/main HEAD):plugins/soleur/scripts/cloudflare-readonly.sh`): the header line containing `with a non-null ssl) and per rule ref`, the line `def verstr:`, and the line `sub_config_entrypoint() {`. (The sibling-branch `git merge-tree` run in Phase 5.2 is a pre-push check, not an acceptance criterion, because its result depends on another session's branch.)
- [ ] AC11 The PR body has `Ref #12846` (no `Closes`), `closingIssuesReferences` is `[]`, and the body leads with the deadline and lists the CLO owner-review items; the #12931 sequencing comment is posted.
- [ ] AC12 No workflow was dispatched by this PR's sessions: `gh run list --workflow apply-web-platform-infra.yml --event workflow_dispatch --created ">=2026-11-19" --json databaseId --jq length` prints `0` at ship time (a dispatch by anyone else is recorded, not ignored); the diff touches no `.github/`, `apps/*/infra/` or Doppler file (`git diff --name-only origin/main...HEAD` holds none).

- [ ] AC14 `bash plugins/soleur/test/health-colo-falsification.test.sh` is green: the runbook holds exactly one recipe marker pair, every case's full output line matches, the outputs block equals the test's case list in order, and each recipe mutation row is caught (seven at plan time, thirteen after the review rulings Q1-Q2 and the input checks); `bash scripts/test-all.sh --print-selection` on a runbook-only change selects it.
- [ ] AC15 The handoff loop in the runbook is byte-identical to the plan's block, and `bash -n` passes on it.

### Post-merge (the follow-up PR that closes #12846)

- [ ] AC13a Right after merge, the follow-through tracker for `scripts/followthroughs/health-colo-capture-12846.sh` is filed (label `follow-through`, `Ref #12846`, an unfenced column-0 `soleur:followthrough` directive with `secrets=GH_TOKEN`), and one sweeper run log shows the probe's `exit=` line (added in review, fix round 1).
- [ ] AC13 By 2026-11-24, in the landing session, the handoff loop has kept and pushed `evidence/<UTC date>-analytics-health-colo-216h-off<O>h.json` (or the two H=108 split files) passing every T3 keep rule, including `.zone` starting `5af02a2f` (or the old zone's fingerprint, if the owner chose one under owner-review item 4), plus the archival capture ending 2026-11-18T17:00Z; then the PR that closes #12846 records the pre-registered T2 recipe's one-line outcome (`not supported` or `inconclusive: <reason>`) as an `Unverified:` line, or records why the capture could not run.
  - Amended in review, 2026-11-19/20 (CTO Q5-Q7, Q10; `decision-challenges.md`): kept files are named `evidence/analytics-health-colo-<H>h-end<YYYYMMDDTHHZ>.json` by window end; `.zone` must equal the full old zone id `5af02a2f394e9ba6e0ea23c381a26b67`; the recipe runs behind the runbook's preflight and sha256 check; and the capture is recorded by an `S1-HEALTHCOLO-CAPTURED:` comment on #12846, which closes the follow-through tracker.

## Test Scenarios

- Given a fake clock at `FAKE_T` and `analytics-health-colo 216 250`, when the run completes, then the body's `datetime_lt` is `floor(FAKE_T) - 250 h` and `datetime_geq` is 216 h earlier, and the body otherwise equals `TPL_COLO`.
- Given `analytics-health-colo 216 529` with no token set, then exit 64, the fixed offset-range message, and no curl call.
- Given `analytics-health-colo 216 527`, then the request is sent (span exactly 743); given `analytics-health-colo 216 528`, exit 64 and no curl call.
- Given a 200 body whose groups carry `coloCode` values `"LHR"`, `"lhr"`, `null`, then the series shows `"LHR"`, `null`, `null`, sorted by hour then colo, and `lhr` appears nowhere in stdout or stderr.
- Given 10000 groups, then `truncated` is true; given 9999, false.
- Given `zones: []`, then `unverified - no-zone-access`, exit 14.
- Given the F arm under the same fake clock after this change, then its stamps are still `floor(FAKE_T) - H h` and `floor(FAKE_T)`.
- Given a mutant that interpolates `$3` into the body, then the masked-body row is RED.
- Given `analytics-health-colo 216 99999999999999999999`, then exit 64 with the regex message (not the bound message) and no curl call.
- Given the environment `END_OFFSET='a[$(touch canary)]'` and `analytics-health 24`, then no canary file exists and F's stamps are unchanged.
- Given an evidence fixture with one `colo: null` row at count 10, then the recipe prints `inconclusive: invalid-colo` with `null_colo_qualifying=1`.

## Domain Review

**Domains relevant:** Engineering, Legal

### Engineering

**Status:** reviewed
**Assessment:** CTO agent rulings of 2026-11-19 (rows F1-F12, R1, R2, T1-T6 and the reconciliations in `decision-challenges.md`; T1-T6 came from plan review): a seventh subcommand, integer offset with 0..527 (T6) and a 743-hour span cap, zone from the environment and printed, host and path filters without `requestSource`, 10000-row cap with `truncated`, the `colo` def placed away from the sibling hunk, a fixed projection, the done-when split with a post-merge follow-up that closes #12846, no fixed-date floor, an ADR-289 addendum and no C4 change, a filename carrying H and O, a fixed target window ending 2026-11-12T12:00Z, and a pre-registered per-colo change-point rule. Risks raised: the old-zone deletion deadline, small per-colo counts, the `cf_graphql` caller census must be updated exactly, section 9 must name both integers, and token reach to the new zone is unverified.

### Legal

**Status:** reviewed
**Assessment:** CLO agent rulings of 2026-11-19 (rows in `decision-challenges.md`; replacement text committed verbatim in `knowledge-base/project/specs/feat-one-shot-12846-health-colo-split/clo-ruling-text.md`, sections A-E, which the work phase applies and does not re-word). (1) `analytics-health-colo` stays Class R under every 2026-11-09 condition plus six new ones: both integers digits-only with no sign or leading zero, checked before the credential and before any request (hours 1-216, offset 0-527, sum at most 743, as amended by the CLO for CTO T6); only wrapper-computed stamps enter the query; the selection is exactly `datetimeHour`, `coloCode`, `count` and avg/p50/p90 `originResponseDurationMs`, with no client-side dimension; same POST chokepoint and token, token set stays five; `coloCode` printed only as three capital letters and hour stamps only as `YYYY-MM-DDTHH:00:00Z`; the first live read is after the merge. (2) `coloCode` per hour on `app.soleur.ai/health` is not personal data and needs no minimum-count suppression (Art. 4(1), Recital 26); ePrivacy Art. 5(3) not engaged; no new processor or transfer; scoped to this host and path only (any other path or host re-runs the GDPR gate and starts from k >= 10 suppression); the evidence file holds the projection only, never joined with log rows, under a new dated filename that overwrites no cited file. (3) Printing the zone id is permitted (a resource identifier, not a credential), only as the validated environment value, with no other environment value printed; committing the full id to this PUBLIC repository is an owner-review item (alternative: a short fingerprint). (4) Section 9 Boundary, item 2 and Credentials text, and the ADR-289 `## Addendum 2026-11-19 (Ref #12846)`, as committed. (5) Six owner-review items for the draft PR (listed in Phase 6.1). This plan's GDPR gate (Phase 2.7) is discharged by this ruling: the canonical regex surfaces are not touched, and the one trigger that fires, (d) a new artifact distribution surface (the plugin update and the public evidence file), is the surface the CLO ruled on.

Product/UX, Marketing, Finance, Operations, Sales and Support: no implication (no user-facing surface, no spend, no new vendor, no new credential). The mechanical UI-surface override did not fire (no `components/`, `app/` or page path in the file lists), so there is no Product/UX Gate and no wireframe.

## Non-Goals and Deferrals

- No read of the new (Free) zone in this PR, and no new or re-minted token: the flip is on the old zone; a new-zone analytics token is part of #12931's token re-mint item, a credential change that is the owner's.
- No `requestSource` filter and no all-colo aggregate series (CTO F5, F8).
- No change to `analytics-health` or `analytics-edge-errors`.
- The evidence read, the evidence file for H and the verdict are the post-merge follow-up of #12846 itself (the issue stays open), not a new issue.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `soleur:work`.
- The deadline is real and external: the old zone may be deleted from about 2026-11-25, and #12931 will change Doppler `CF_ZONE_ID`. A read after either one describes a different zone or none; the printed `zone` field is how a reader tells.
- Never answer a `no-zone-access` or `token-lacks-scope` on the new zone with another token or a hand-written query: both leave Class R.
- The handoff computes O in one hour and the wrapper computes its own clock a moment later; across an hour boundary the window shifts by one hour. The loop's `.window_end` check makes that fail closed; re-run it.
- Do not write "fix" next to an issue number in the PR body or commit messages (auto-close).
- `supported` is not a reachable outcome of the H read (CTO T2): an origin-side release deploy shares the flip's hour. Do not let a later session re-introduce it by reading the per-colo shape as separating the deploy from the flip.
- The splice (edit 9, inside `project()` after `bad_jq`) is the one place the zone reaches output; a later edit that moves it into jq argv, or adds a second jq call site for it, reopens the census question CTO T1 and D1 closed.
- The offset bound must stay fail-closed (`-le ... ||`): an integer test on a non-integer or overflowing value is rc 2, which a `-gt ... &&` form reads as "in range".
