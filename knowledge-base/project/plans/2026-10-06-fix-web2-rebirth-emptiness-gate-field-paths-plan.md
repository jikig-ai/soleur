---
title: "fix: point the web-2 rebirth emptiness gate at the field paths Better Stack actually stores"
date: 2026-10-06
slug: web2-rebirth-emptiness-gate-field-paths
branch: feat-one-shot-9372-emptiness-gate-field-paths
issue: 9372
type: fix
priority: p2
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix: point the web-2 rebirth emptiness gate at the field paths Better Stack actually stores

Ref #9372 (never `Closes`: the issue closes only after rebirth evidence lands). Draft PR: #9628. Code PR only.

## Overview

The single-use web-2 volume rebirth (#9372) refuses to delete the plaintext `/mnt/data` volume unless seven days of Better Stack
filesystem metrics prove it empty (`scripts/web2-rebirth-emptiness.sh`, step `Emptiness evidence` of
`.github/workflows/web2-luks-rebirth.yml`). The plan-only run of 2026-10-06
(<https://github.com/jikig-ai/soleur/actions/runs/37463995633>) went RED `reason=used_bytes_absent_or_host_dark`: the SQL filters on
`host_name`, `source_kind`, `metric.name`, `metric.value`, none of which exist in the stored `raw`. The gate failed closed as
designed, but could never PASS.

This plan establishes the root cause, fixes the QUERY paths (not the shipper), keeps every threshold, the verdict function and the
fail-closed semantics byte-identical, adds a test that cannot share the bug with the code, and replaces the script header's
"UNCONFIRMED" caveat with the confirmed paths. It does not dispatch, approve, apply, write Doppler, mint tokens, toggle a
workflow, or claim web-2 is LUKS-backed or reborn.

## Research Insights

### Premise Validation (Phase 0.6)

- `#9372` is OPEN. `#6944` (OPEN) recorded the same shape gap on 2026-07-25 and the runbook `betterstack-log-query.md`
  (§"Querying host CPU / memory / load") already documents the working paths (`tags.host`, top-level `name`, `gauge.value`,
  `source_kind` unset). The gate (2026-10-05) was written without consulting it. Premise holds: a gate-vs-reality defect, not a
  never-built feature.
- Cited files exist on `origin/main`: `scripts/web2-rebirth-emptiness.sh`, `scripts/web2-rebirth-emptiness.test.sh`,
  `scripts/web2-rebirth.test.sh`, `apps/web-platform/infra/vector.toml`.
- **Brief-vs-repo reconciliation.** The brief names `scripts/web2-rebirth.test.sh` (floor 123). That suite exercises the stateful
  steps against a fake Hetzner/Terraform world and only consumes `EMPTINESS=` as a string; it never evaluates the emptiness SQL.
  The SQL and verdict are tested by `scripts/web2-rebirth-emptiness.test.sh` (floor 29, suite `scripts/web2-rebirth-emptiness` in
  `scripts/test-all.sh`). Scenarios and fixtures change THERE; `web2-rebirth.test.sh` runs unchanged as a regression gate.
- ADR corpus: no ADR proposes a shipper fix for this. ADR-263 carries two "unverified until the first live query" sentences
  (the pass-condition prose and "Known limits") that this change must amend: stale-claim edits, not a decision change.
- Flow fact verified in the workflow: `environment: web-platform-infra-apply` is a JOB-level gate, so approval happens BEFORE the
  `Emptiness evidence` step runs. The header's "the owner reads the printed min/max before approving the dispatch" is therefore
  wrong for a dispatch; the min/max are readable only after approval (in the plan-only run, which writes nothing). The header,
  runbook and Observability claims are corrected accordingly (AC5).

### Root cause (measured 2026-10-06)

Reproduced with the production-pinned Vector 0.43.1 (`timberio/vector:0.43.1-alpine`, the version in `soleur-host-bootstrap.sh`):
the repo's own `[transforms.tag_metrics]`, fed by a `host_metrics` source and printed with `encoding.codec = "json"` (the sink's
codec), emits the BARE metric `{"name","namespace","tags":{...,"host","mountpoint"},"timestamp","kind","gauge":{"value"}}` with no
`source_kind`, `host_name`, `shipper` or `metric.*`. The transform is a silent no-op on metric events: VRL `remap` on a metric can
only write the metric's own fields (`name`, `namespace`, `timestamp`, `kind`, `tags`); an arbitrary top-level write errors at
runtime and, with the default `drop_on_error = false`, Vector forwards the event unmodified (the error is a debug-level event, so
nothing ever surfaced). This answers #6944's open question 1: not "deployed hosts predate it"; the transform can never take effect
on this source. Counter-experiment: a `metric_to_log` transform ahead of `tag_metrics` makes flattening work but MOVES the host from
`tags.host` to top-level `host` (breaking every documented runbook query) while keeping `name`, `gauge.value`, `tags.mountpoint`.

### Live positive control (read-only, 2026-10-06)

The proposed SQL run through `scripts/betterstack-query.sh` under `doppler run -p soleur -c prd_terraform` (credentials never
printed) returned exactly the two aggregate rows the verdict code consumes, with and without the added `HAVING` clause:

```text
{"metric_name":"filesystem_used_bytes","n":2019,"hours":169,"vmin":15556608,"vmax":16027648,"newest_age_s":98}
{"metric_name":"filesystem_total_bytes","n":2019,"hours":169,"vmin":20957446144,"vmax":20957446144,"newest_age_s":98}
```

These satisfy every threshold (169 >= 160 hours, age <= 1800, min > 0, max about 16 MB <= 1 GiB, spread 471040 <= 64 MiB, total
20.96e9 in [15e9, 21.5e9]). `n` 2019 over 7 days at a 300 s scrape is about 2016, so one series reports `/mnt/data`; and since the
hot window is about 40 minutes, more than 99% of those rows came through the `s3Cluster` archive arm, so the archive arm's `raw`
shape is exercised by the same control. Limits of this control: it ran under Doppler read credentials, while the workflow uses the
repo secrets `BETTERSTACK_QUERY_*`; only the first post-merge plan-only dispatch (needs the owner's explicit go-ahead; NOT done
here) proves those read the same table.

### Property List (Phase 0.6b)

1. The gate reads rows that are stored: on today's live data its SQL returns the two aggregate rows.
2. Zero rows, an absent path, or rows from another host, mountpoint, namespace, or a second device can never produce PASS: a named RED.
3. Every threshold, the verdict function and the `W2R_DETACHED` arm are unchanged.
4. The test cannot share the code's wrong assumption: the SQL's own JSON paths are resolved against a real-shape row.
5. The header states what is confirmed (with date and how) and what is not (the `dm-*` exclusion, post-LUKS behaviour).
6. A later shape change fails closed (already true via the zero-row RED) and the header names the coupling.

### Cut List (Phase 0.6b)

| Mechanism | Property | Why cut |
|---|---|---|
| Fix the shipper (`metric_to_log`, or remove the dead transform) in `vector.toml` | 1 | The query fix buys property 1 alone. The shipper fix edits `vector.toml` (also edited by the open draft PR `feat-open-web-egress`), reaches web-2 only through a host rebuild inside the rebirth window, moves `tags.host` to `host` (breaking documented queries) and enlarges rows against a quota this stream already nearly blew. It stays #6944's job. |
| Accept both shapes (`tags.host = X OR host_name = X`) | 6 | Widens the predicate on an irreversible-delete gate to pre-pay a change nobody proposed. |
| `vector.toml` shape-drift canary test | 6 | Two of seven reviewers cut it (speculative cross-file coupling; it detects one literal; it can be deleted by the PR it should stop; the gate already fails closed at run time). The header drift note carries the coupling. Surfaced to the owner (decision-challenges.md). |
| `tags.collector = 'filesystem'` predicate | 2 | The live control returned identical aggregates without it; `name` + `mountpoint` + host already pin the series, and each extra path is another field a shipper change can break. |
| Jq evaluator that aggregates rows and chains into the verdict; decoy fleet; harness-red stubs | 4 | It reimplements ClickHouse WHERE/GROUP BY in jq (it proves jq, not ClickHouse), needs `dt` series the fixture does not carry, and the existing 29 verdict arms already prove the aggregate-to-verdict chain. Replaced by the strict path-and-value check below. |
| clickhouse-local in CI | 4 | No binary available; the path check buys the paths without a new dependency. |
| Touch `web2-rebirth.test.sh` or its 123 floor | none | It never evaluates the SQL. |

### Institutional learnings applied

`2026-08-11-my-fixture-shared-the-bug-so-the-test-could-not-see-it.md` and
`2026-07-12-dry-run-fixture-must-derive-from-producer-source-not-fabricated-format.md` (the existing fixtures are aggregate rows the
code is already shaped to read, so no test could see a wrong SQL path; the new fixture is the producer's real raw row and the paths
come from the SQL text); `2026-07-18-betterstack-followthrough-probe-must-field-isolate-syslog-identifier.md` (field-isolate on
decoded paths); `2026-07-24-guest-luks-store-must-gate-consumer-on-mount-and-guard-suite-must-pin-fail-loud-semantics.md` (scope
greps to the SQL block, a mutation per rule); `2026-04-27-preflight-security-gates-skip-vs-fail-defaults.md` (empty result is never a
skip); `cq-test-fixtures-synthesized-only` (byte values invented; hostnames and device names are the repo's own identifiers).

## Research Reconciliation: Spec vs. Codebase

| Claim | Reality | Plan response |
|---|---|---|
| Brief: update `scripts/web2-rebirth.test.sh` (floor 123) | The SQL is tested by `scripts/web2-rebirth-emptiness.test.sh` (floor 29) | Change that suite; run the 123-floor suite unchanged |
| Header: paths "UNCONFIRMED ... no repo consumer reads these JSON paths" | The runbook (#6944) documents them | Header cites it and the 2026-10-06 live control |
| Header: "the owner reads the printed min/max before approving the dispatch" | Approval is a job-level gate, so it precedes the evidence step | Reword header, runbook, Observability |
| `vector.toml`: `tag_metrics` "flattens the metric event" | Measured no-op on metric events (Vector 0.43.1) | Not edited here; recorded in the runbook and on #6944 |
| ADR-263: JSON paths unverified until the first live query (two sentences) | Confirmed 2026-10-06; `dm-*` exclusion still unverified | Amend both |
| `model.c4` `hetzner -> betterstack`: host telemetry told apart by a per-host `host_name` discriminator | True for log rows; `host_metrics` rows carry `tags.host` and no `host_name` | One clause added to that edge description |

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` bodies checked against the file list; re-run at work time.)

## Files to Edit

- `scripts/web2-rebirth-emptiness.sh` (SQL paths, `HAVING`, header)
- `scripts/web2-rebirth-emptiness.test.sh` (real-shape rows, strict path-and-value check, mutations, tightened floor)
- `knowledge-base/engineering/operations/runbooks/web2-luks-rebirth-9372.md` (the "unconfirmed until the first live query" sentence; approval-before-evidence wording)
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` (one sentence: root cause replaces "tracked in #6944 separately"; the gate reads the native shape)
- `knowledge-base/engineering/architecture/decisions/ADR-263-guest-side-fresh-boot-luks-for-web-hosts.md` (both "unverified until the first live query" sentences)
- `knowledge-base/engineering/architecture/diagrams/model.c4` (one clause on the `hetzner -> betterstack` edge; re-run the C4 gates)

Not edited: `apps/web-platform/infra/vector.toml`, `scripts/web2-rebirth.test.sh`, the workflow, `scripts/lib/web2-luks-rows.sh`.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-9372-emptiness-gate-field-paths/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-9372-emptiness-gate-field-paths/decision-challenges.md`
- No fixture file on disk: the real-shape rows are inline synthesized `printf` literals in the test.

## The change

### SQL (scripts/web2-rebirth-emptiness.sh, `w2r_sql_emptiness`)

Only the paths change and one `HAVING` is added; the FROM (hot + archive arm), window, output aliases, FORMAT and every constant stay.

```sql
SELECT JSONExtractString(raw,'name') AS metric_name, count() AS n, countDistinct(toStartOfHour(dt)) AS hours,
       min(JSONExtractFloat(raw,'gauge','value')) AS vmin, max(JSONExtractFloat(raw,'gauge','value')) AS vmax,
       min(dateDiff('second', dt, now())) AS newest_age_s
FROM (SELECT dt, raw FROM remote($BS_TABLE) UNION ALL SELECT dt, raw FROM s3Cluster(primary, $BS_TABLE_S3) WHERE _row_type = 1)
WHERE dt > now() - INTERVAL 7 DAY
  AND JSONExtractString(raw,'tags','host') = 'soleur-web-2'
  AND JSONExtractString(raw,'namespace') = 'host'
  AND JSONExtractString(raw,'tags','mountpoint') = '/mnt/data'
  AND JSONExtractString(raw,'name') IN ('filesystem_used_bytes','filesystem_total_bytes')
GROUP BY metric_name
HAVING uniqExact(JSONExtractString(raw,'tags','device')) = 1
FORMAT JSONEachRow
```

- `host_name` -> `tags.host`; `source_kind = 'host_metrics'` -> `namespace = 'host'` (the replacement for the field that never
  exists); `metric.name` -> `name`; `metric.value` -> `gauge.value`.
- **`HAVING uniqExact(device) = 1` (new, from the architecture review).** The aggregate pools min, max, hours and newest age across
  every series matching host + mountpoint + name. A second device reporting `/mnt/data` (an unexcluded LUKS mapper, a bind mount) would
  let a live series mask a dark one and two half-covered series jointly satisfy 160 hours. With the clause a multi-device group
  disappears, so it reads as zero rows: RED `used_bytes_absent_or_host_dark`. SQL-only, fail-closed, verdict function untouched; the
  live control passes with it (one device, `/dev/sdb`). Cost accepted: a device rename inside the 7 days would be a false RED (safe).
- Fail-closed direction: every added predicate only REMOVES rows. An absent `gauge.value` reads as 0, so the existing `min > 0`
  rule still yields RED `used_bytes_zero_or_missing`. Zero rows stays RED. `w2r_emptiness_verdict` and `w2r_main` are NOT touched.
- Why `tags.host`: it is the machine's own hostname written by Vector's `host_metrics` source and equals `W2L_HOST_NAME`. Trust is
  unchanged: any holder of the shared ingest token can write `tags.host`, `namespace`, `mountpoint` or `host_name` alike; the extra
  predicates raise the accident bar, not the forgery bar. `$BS_TABLE` / `$BS_TABLE_S3` stay literal for the query script.
- **Header rewrite:** confirmed paths with the date and the evidence (the recorded control, the runbook section, the Vector 0.43.1
  reproduction); keep the "`dm-*` vs LUKS mapper device is unverified, so this evidence is NOT claimed to vanish after LUKS" caveat;
  correct "the owner reads min/max before approving" (approval precedes the step; the numbers are read from the plan-only run);
  state that RED `used_bytes_absent_or_host_dark` also covers a changed row shape (#6944: if the shipper starts flattening, `tags.host`
  moves to top-level `host`) and a multi-device group, and that the SQL and the test fixture must change together.

### Test (scripts/web2-rebirth-emptiness.test.sh)

The existing fixtures are AGGREGATE rows the verdict function is already shaped to read, so no test could notice a wrong raw path:
that blind spot is the defect. Added (about 60 lines, no SQL interpreter):

1. **Real-shape rows (synthesized values).** Inline literals shaped like the stored bare Vector metric:
   `{"name":"filesystem_used_bytes","namespace":"host","tags":{"collector":"filesystem","device":"/dev/sdb","filesystem":"ext4","host":"soleur-web-2","mountpoint":"/mnt/data"},"timestamp":"...","kind":"absolute","gauge":{"value":16000000}}`
   and the `filesystem_total_bytes` twin; a second used row with different values, extra tag keys and permuted key order (the
   non-canonical must-PASS input); a LEGACY flat row (`host_name`, `source_kind`, `metric.name`, `metric.value`, no `tags`/`gauge`);
   and an other-host decoy (`tags.host` `soleur-web-platform`).
2. **`w2r_sql_paths <sql-text>` (in-process, takes the SQL as an argument).** Extracts from the awk-scoped block between `^WHERE` and
   `^GROUP BY` (anchored: the FROM subquery also contains `WHERE _row_type = 1`) every conjunct, under a STRICT grammar: each line must
   be the `dt` window, `JSONExtractString(raw,'a'[,'b']) = '<lit>'`, or `... IN ('<lit>',...)`; any other shape (`OR`, `!=`, `LIKE`,
   two conjuncts on a line) makes it print `FAILED` and return non-zero. It also extracts every `JSONExtractFloat(raw,...)` path and
   the SELECT name path.
3. **Assertions.** (a) The extracted (path, value) set EQUALS the expected set exactly (host, namespace, mountpoint, name list), not a count;
   (b) the float paths are exactly two, both `gauge,value`; the SELECT name path equals the IN-predicate name path; (c) each conjunct,
   evaluated with `(try getpath($p) catch null)` coalesced to `""`, holds on the real used rows and the total row; the legacy row and
   the other-host decoy each violate at least one; (d) the float path resolves to a non-zero number on the real rows; (e) in-process
   negative controls: `w2r_sql_paths` on a SQL whose WHERE block is empty fails ("parsed 0"), and on the old legacy-path SQL string
   the real rows violate conjuncts; (f) every oracle failure path prints a line starting `FAILED` (the report loop treats other lines as
   informational, so a bare error would stay green) and each assertion increments `n`.
4. **Existing assertions kept and re-aimed.** The SQL-shape fragment loop covers what the oracle ignores (the UNION arms, `GROUP BY
   metric_name`, `INTERVAL 7 DAY`, `HAVING uniqExact`) and is updated to the new text. The mutations `host predicate removed` and
   `mountpoint predicate removed` are re-aimed at the new text; new mutations are listed in the Guard Contract. The `cmp -s` no-op guard
   stays, and a green BASELINE run is asserted before the mutation kill-counting (a red base would make every mutation look killed).
5. **Floor.** `ran` is currently a lower bound (`-ge 29`). Re-derive the count from a green run and set the floor to exactly that
   (tightening, not slack); transport and main-exit checks outside `battery()` stay outside `ran`.

Scope note put in the test header: the check certifies path resolution and predicate text, not ClickHouse semantics (the recorded live
control is the anchor for `JSONExtract*` behaviour) and not the time window or aggregation (the existing verdict arms cover those).

Regression gates run unchanged: `web2-rebirth.test.sh` (123), `test-destroy-guard-counter-web-platform.sh` (107),
`c4-model-freshness.test.sh`, `lint-encryption-posture.py --repo-sweep`.

## Guard Contract

### Guard 1 — web-2 emptiness evidence gate (`w2r_sql_emptiness` + `w2r_emptiness_verdict`) and its path check

**Property.** The gate prints PASS only when rows that exist in the stored Better Stack shape, from exactly one device of soleur-web-2's
`/mnt/data` filesystem metrics, satisfy coverage, freshness, zero floor, ceiling, spread and volume-size; zero rows, an absent path, or
rows from any other host, mountpoint, namespace, metric name or a second device yield a named RED and never PASS; and the test resolves
the SQL's own JSON paths against a real-shape row so a path that does not exist in stored rows turns the suite RED.

**Assembly.** Chokepoints: `w2r_sql_emptiness` is the only SQL (conjuncts: `tags.host`, `namespace`, `tags.mountpoint`, `name IN`;
SELECT paths: `name`, `gauge.value` twice; `HAVING` device count; hot arm and archive arm under the outer WHERE);
`w2r_emptiness_verdict` is the only judge; `w2r_main` the only caller (0 PASS, 1 RED, 2 transport); the workflow step `Emptiness
evidence` the only consumer, feeding `EMPTINESS` to `scripts/web2-rebirth.sh delete-volume`, which refuses unless it starts with
`PASS`. No other reader of these rows exists (`grep -rn "w2r_sql_emptiness\|web2-rebirth-emptiness"` hits the script, its test, the
workflow, and two workflow suites that shim it). The test side: `w2r_sql_paths` is the only extraction, invoked inside `battery()` so
every mutation copy runs it.

**Mutation matrix.** Edits that MUST drive the suite RED (sed on a copy of the script unless stated):

| # | Mutation | Row kind |
|---|---|---|
| 1 | host predicate path reverted to `JSONExtractString(raw,'host_name')` | design: stored rows have no such path |
| 2 | `gauge.value` reverted in the `vmin` aggregate only (first occurrence) | precondition holds, property fails |
| 3 | `gauge.value` reverted in the `vmax` aggregate only (second occurrence) | a vmax-only swap leaves vmin > 0 and passes the verdict, so only the exact-set check sees it |
| 4 | name path reverted in the SELECT only | exact-set / equal-name-path check |
| 5 | name path reverted in the `IN` predicate only | zero rows |
| 6 | host predicate deleted | second member after a compliant first: the other-host decoy now satisfies the remaining conjuncts |
| 7 | mountpoint predicate deleted | existing, re-aimed |
| 8 | `namespace` predicate deleted | exact-set check |
| 9 | `HAVING uniqExact(device)` deleted | fragment check; pooling hole reopened |
| 10 | archive arm deleted | existing |
| 11 | an unrecognized conjunct appended to the WHERE block (`OR 1 = 1`) | strict-grammar row: the extractor must FAIL, not skip it |
| 12 | the path check's own dispatch: `w2r_sql_paths` on a SQL with an empty WHERE block (in-process) | must report "parsed 0" and fail, never exit 0 |
| 13 | every existing verdict rule removed in turn (coverage, staleness, zero floor, spread, ceiling, volume-size, zero-row arm, judge-error arm, detached relaxation) | existing mutations, kept |

Harness rows (edits to the SUITE side that MUST drive it RED, plus must-PASS inputs): (a) the legacy-path SQL string fed to
`w2r_sql_paths` in-process: the real rows must violate conjuncts and the suite must report it; (b) must-PASS non-canonical: the second
real-shape row (different synthesized values, extra tag keys, permuted key order) satisfies every conjunct; (c) a decoy whose `tags` is a
scalar and one whose `gauge` is absent must not crash the evaluator (`try getpath`), the first violating the host conjunct and the
second failing the non-zero check.

**Anchor.** The fixture and the SQL are edited in one diff, so the suite alone proves consistency, not integrity. What OUTSIDE the
commit must also move for a weakening to pass: (i) the runbook `betterstack-log-query.md` §host_metrics, authored 2026-07-25 under
#6944 independently of this change, documents the same native paths; (ii) the live positive control recorded in the PR body
(2026-10-06, read-only), re-observed by the first post-merge plan-only dispatch, which needs the owner's explicit go-ahead and is NOT
done here; (iii) AC2 checks by diff that no threshold, the verdict function or the `W2R_DETACHED` arm changed.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "fix scripts/web2-rebirth-emptiness.sh so its Better Stack emptiness query reads the field paths that actually exist in the stored rows" [brief] | The change / SQL; Files to Edit entry 1 | mapped |
| 2 | "investigate it (e.g. the sink encoding or a later transform dropping fields) and decide whether to fix the query to the real paths (tags.host, gauge.value, name) or fix the shipper" [brief] | Research Insights: Root cause + Cut List row 1 | mapped |
| 3 | "Keep fail-closed semantics: zero rows stays a named RED, never a pass; keep every threshold" [brief] | AC1, AC2; Guard 1 | mapped |
| 4 | "Read the script header caveat about UNCONFIRMED paths and update it with the now-confirmed paths" [brief] | The change / Header rewrite; AC5 | mapped |
| 5 | "Update scripts/web2-rebirth.test.sh scenarios and fixtures (suite floor is 123 scenarios; raise the floor if scenarios are added)" [brief] | Files to Edit entry 2 (the emptiness suite) | descoped for web2-rebirth.test.sh — justification: that suite never evaluates the SQL (Premise Validation); the floor that moves is the emptiness suite's, 123 is verified unchanged |
| 6 | "add a regression fixture built from the REAL row shape (synthesized values only)" [brief] | Test items 1-3 | mapped |
| 7 | "run: bash scripts/web2-rebirth.test.sh; bash tests/scripts/test-destroy-guard-counter-web-platform.sh (floor 107); bash plugins/soleur/test/c4-model-freshness.test.sh; python3 scripts/lint-encryption-posture.py --repo-sweep" [brief] | Phase 4; AC6 | mapped |
| 8 | "this is a code PR only. Do NOT dispatch .github/workflows/web2-luks-rebirth.yml" [brief] | AC7, AC8; Sharp Edges | mapped |
| 9 | "this change needs a security-focused review before merge" [brief] | AC9 | mapped |
| 10 | "Use 'Ref #9372' in the PR body" [brief] | AC8 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| SQL path swap, `namespace` predicate | "reads the field paths that actually exist in the stored rows" | asked |
| Header rewrite | "update it with the now-confirmed paths" | asked |
| Real-shape fixture and strict path check | "add a regression fixture built from the REAL row shape" | asked |
| `HAVING uniqExact(device) = 1` | — | inferred — justification: the aggregate pools series, so a second device on `/mnt/data` could mask a dark plaintext device; it only removes rows (fail-closed) and keeps the verdict function untouched, serving "zero rows stays a named RED, never a pass" |
| Header/runbook correction of approval-before-evidence | "update it with the now-confirmed paths" | asked (the header must be truthful about what the printed numbers permit) |
| ADR-263 two sentences, runbook sentence, `model.c4` clause, `betterstack-log-query.md` sentence | — | inferred — justification: each states a claim this fix falsifies; leaving them is how this defect was missed in the first place |
| `#6944` root-cause comment | "Root cause of why the tag_metrics transform's flat fields ... are absent from raw is NOT yet established: investigate it" | asked |
| Tightened floor, green-baseline assertion | "raise the floor if scenarios are added" | asked |

### Split Assessment

- Subsystems touched: 3 — `scripts`, `knowledge-base`, (no `apps/` or `plugins/` file)
- Planned files: 8 | Estimated changed lines: about 150
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Architecture Decision (ADR/C4)

No new architectural decision (a query-path correction on an existing gate); the ADR-263 and `model.c4` edits correct stale claims.
C4 checked against all three of `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`: the Better Stack Logs
system, the Vector shipper and the GitHub Actions workflow are modeled; no actor, system, store or actor-to-surface relationship is
added and no derived count moves (confirmed by running `plugins/soleur/test/c4-model-freshness.test.sh` and the count-parity test
after the one-clause edge-description change).

## Encryption Posture

Skipped: no persistent store, no new connection, and no `.tf`, migration, cloud-init or compose file touched; the read uses the
already-declared Better Stack HTTPS channel through `scripts/betterstack-query.sh`. `lint-encryption-posture.py --repo-sweep` still
runs as a regression gate. Nothing here asserts web-2 is LUKS-backed or reborn.

## User-Brand Impact

**If this lands broken, the user experiences:** a rebirth that either can never start (gate stuck RED: delay only, nothing touched)
or, in the catastrophic direction, a false PASS that lets the workflow delete a web-2 volume holding workspace data, which a customer
would see as lost workspace files with no recovery path (the volume delete is irreversible).

**If this leaks, the user's workflow data is exposed via:** no new vector: the change reads existing metric rows through the existing
credentialed query script, adds no secret, prints no credential, and the test uses synthesized values only.

**Brand-survival threshold:** single-user incident

- CPO sign-off: `requires_cpo_signoff: true`. An advisory CPO pass during plan review returned "sign-off with conditions"
  (C1 sign-off recorded as a pre-work gate and not self-attributed; C2 the PR body must not imply the gate is proven before the first
  post-merge plan-only dispatch, and the PASS line's min/max stay visible; C3 keep the live control in the PR body and do not waive
  AC9; C4 the PR body states `tags.host` is no weaker than `host_name`). That advisory is NOT the owner's or CPO's sign-off: the
  sign-off remains a gate before `soleur:work` begins.
- Parent-plan CPO/CLO/CTO conditions carry forward unchanged (no threshold weakened, no data-protection surface, trust boundary unchanged).
- Review-time (REQUIRED, AC9): `soleur:engineering:review:security-sentinel` and `soleur:engineering:review:user-impact-reviewer`,
  asked: can any input produce PASS without the stored rows proving emptiness; does any predicate widen what matches; does the path
  check have a vacuous arm.
- Open owner decisions surfaced in `decision-challenges.md` (not decided here): the 1 GiB ceiling versus a measured 16 MB baseline;
  approval-before-evidence (an apply dispatch's PASS flows to the delete in the same approved job); the `heal:detach_done` premise; the
  time between the evidence read and the delete.

## Domain Review

**Domains relevant:** Engineering (infrastructure/tooling)

### Engineering

**Status:** reviewed (plan-review panel: DHH, Kieran, code-simplicity, architecture-strategist, spec-flow, CTO devex, CPO advisory)
**Assessment:** Bash/jq/SQL change on an existing CI gate plus docs; no product, marketing, legal, finance, sales or support surface.
Product/UX gate: NONE (no UI-surface file in either Files list).

## Observability

```yaml
liveness_signal:
  what: the gate prints exactly one verdict line (PASS ... or RED reason=...) and exits 0, 1 or 2; the workflow step copies the first line into the step output and the dispatch summary
  cadence: per dispatch of web2-luks-rebirth.yml (single-use); no schedule
  alert_target: the workflow run log and dispatch summary (GitHub Actions), read from the plan-only run (the environment approval precedes this step)
  configured_in: .github/workflows/web2-luks-rebirth.yml step "Emptiness evidence"
error_reporting:
  destination: stdout/stderr of the step; a transport failure is rc 2 with an explicit "read did not answer" line; a verdict is rc 0 or 1
  fail_loud: true
failure_modes:
  - mode: stored row shape changes (a shipper fix, #6944)
    detection: zero rows -> RED used_bytes_absent_or_host_dark (header names the coupling)
    alert_route: red workflow step before any write
  - mode: web-2 dark or the Better Stack read fails
    detection: RED stale or coverage_gap, or rc 2 (no verdict)
    alert_route: red workflow step
  - mode: a second device or another host's rows match
    detection: HAVING removes a multi-device group; the path check and mutations pin the predicates in CI
    alert_route: red workflow step; red CI suite on the PR
logs:
  where: GitHub Actions run log (verdict line) and the dispatch summary
  retention: GitHub Actions default retention
discoverability_test:
  command: bash scripts/web2-rebirth-emptiness.sh
  expected_output: PASS
  credentials_required: "BETTERSTACK_QUERY_HOST/USERNAME/PASSWORD (read-only ClickHouse connection, via doppler prd_terraform) - no unauthenticated probe verifies that the stored rows have the shape the SQL reads"
```

## Implementation Phases

Phase 1 (RED first, `cq-write-failing-tests-before`): in the emptiness test add the real-shape rows, `w2r_sql_paths`, the assertions,
the green-baseline check and the new mutations; run against the UNCHANGED SQL and record that the path assertions fail (the old paths
resolve to nothing on the real rows).
Phase 2 (GREEN): change only the paths and add the `HAVING` in `w2r_sql_emptiness`; rewrite the header. Re-run; set the exact floor.
Phase 3 (docs): the ADR-263 sentences, the runbook sentences, the `model.c4` clause, the `betterstack-log-query.md` sentence.
Phase 4 (regression gates, all green): `bash scripts/web2-rebirth-emptiness.test.sh`; `bash scripts/web2-rebirth.test.sh` (123);
`bash tests/scripts/test-destroy-guard-counter-web-platform.sh` (107); `bash plugins/soleur/test/c4-model-freshness.test.sh` and the
count-parity test; `python3 scripts/lint-encryption-posture.py --repo-sweep`; `python3 scripts/lint-guard-contract.py` on this plan;
`shellcheck` on the two scripts; markdownlint on edited docs.
Phase 5 (ship): PR body uses `Ref #9372`; carries the live positive control, the Vector reproduction summary, the measured baseline
(about 16 MB used of 20 GB), the `tags.host` trust note, and states that no dispatch, approval, Doppler write, token mint, workflow
toggle or Terraform apply happened. Post the root-cause comment on #6944 (answers its open question 1; does not close it) and a
comment on #9372 naming the first post-merge plan-only dispatch as the next owner-gated step (so it does not stall silently).

## Test Scenarios

- Real-shape web-2 used and total rows satisfy every extracted conjunct; legacy-flat and other-host rows violate at least one.
- Extracted (path, value) set equals the expected set; float paths are exactly two `gauge,value`; SELECT name path equals the IN name path.
- A scalar-`tags` row and an absent-`gauge` row do not crash the evaluator.
- Empty body -> RED `used_bytes_absent_or_host_dark`; HTML body -> RED `emptiness_body_unparseable`; transport failure -> rc 2.
- All 29 existing verdict arms unchanged and green; every constant unchanged.
- Mutations 1-13 each leave at least one red; a no-op sed is itself a failure; the base run is green first.

## Acceptance Criteria

- [ ] AC1: `w2r_sql_emptiness` reads `tags.host`, `namespace`, `tags.mountpoint`, `name`, `gauge.value` and carries `HAVING uniqExact(JSONExtractString(raw,'tags','device')) = 1`; none of `host_name`, `source_kind`, `'metric','name'`, `'metric','value'` remains in the SQL block (awk-scoped grep).
- [ ] AC2: the diff shows changes only in `w2r_sql_emptiness` and header comments of the script: every `W2R_*` constant, `w2r_emptiness_verdict`, `w2r_main` and the `W2R_DETACHED` arm are byte-identical.
- [ ] AC3: the emptiness suite has the real-shape rows, the strict `w2r_sql_paths`, the exact-set assertions, the in-process negative controls and mutations 1-13; the path assertions were observed RED against the unchanged SQL before the change (recorded in the PR body).
- [ ] AC4: the floor equals the re-derived count (greater than 29, stated as a tightened lower bound); every mutation reports at least 1 red after a green baseline.
- [ ] AC5: the header no longer says UNCONFIRMED for the JSON paths; it quotes the date and the control's `n`, hours, age, min and max, keeps the `dm-*` caveat, no longer says the owner reads min/max before approving, and states that RED `used_bytes_absent_or_host_dark` also covers a changed row shape or a multi-device group.
- [ ] AC6: `bash scripts/web2-rebirth.test.sh` (floor 123), `bash tests/scripts/test-destroy-guard-counter-web-platform.sh` (floor 107), `bash plugins/soleur/test/c4-model-freshness.test.sh`, the C4 count-parity test, `python3 scripts/lint-encryption-posture.py --repo-sweep` and `python3 scripts/lint-guard-contract.py` (this plan) all exit 0.
- [ ] AC7: `apps/web-platform/infra/vector.toml`, `scripts/web2-rebirth.test.sh`, the workflow and `scripts/lib/web2-luks-rows.sh` are byte-unchanged (`git diff --stat origin/main`).
- [ ] AC8: the PR body says `Ref #9372` (no `Closes`), carries the recorded live control and the C2/C4 CPO conditions, and states that no dispatch, environment approval, Doppler write, token mint, workflow pause/enable or Terraform apply was performed; it does not claim web-2 is LUKS-backed or reborn or the gate "proven".
- [ ] AC9: a security-focused review (security-sentinel + user-impact-reviewer) ran against the diff before merge and its findings are resolved.
- [ ] AC10: both ADR-263 sentences, the runbook sentences and the `model.c4` clause are amended; the #6944 root-cause comment and the #9372 next-step comment are posted.

## Sharp Edges and Risks

- The live control proves the SQL returns the right rows today; it does not prove web-2 is empty beyond the thresholds (about 16 MB used
  of 20 GB, flat). The ceiling (1 GiB) is about 60 times the measured baseline and a flat 100 to 900 MB of old user data would still
  pass the ceiling and the spread; the brief says keep every threshold, so it is unchanged and surfaced to the owner.
- Approval precedes evidence (job-level environment gate): an apply dispatch's PASS reaches the delete without a human reading the
  numbers first; the plan-only run is the only pre-delete read. Also unchanged and surfaced: evidence freshness vs the delete (the
  preplan and checks run between them) and the `heal:detach_done` premise.
- The path check certifies path resolution and predicate text only; do not extend it to emulate ClickHouse.
- A future shipper fix (#6944) changes the shape: the gate goes RED (named), not wrong; a drift guard was deliberately cut.
- Do not run the real `web2-luks-rebirth.yml` dispatch to "see it go green"; it needs a separate explicit owner go-ahead, as does the plan-only dispatch.
- Header text says "confirmed" only for what was measured; the `dm-*` and post-LUKS behaviour stay unconfirmed.
- A plan whose `## User-Brand Impact` section is empty or placeholder fails deepen-plan Phase 4.6; this one is filled.
- Fixtures stay synthesized: invented byte values and timestamps; hostnames and device names are the repo's own identifiers.
