---
title: "fix(followthrough): placement_decision probe reads CONTAINER_NAME + message_json (#12587)"
type: fix
date: 2026-11-11
slug: fix-placement-probe-field-isolation
branch: feat-one-shot-12587-probe-field-fix
issue: 12587
domain: engineering
priority: p3-low
brand_survival_threshold: none
lane: cross-domain
---

# fix(followthrough): placement_decision probe reads CONTAINER_NAME + message_json (#12587)

## Overview

The follow-through probe `scripts/followthroughs/placement-decision-forward-9137.sh`
verifies the AC12 soak for tracker #12587 (placement-aware execution, merged
2026-11-11 as `f94e57a8` / PR #12554) but can never exit 0, for two independent
field defects:

1. **Row isolation reads a field that does not carry the app name.** The probe
   selects `.SYSLOG_IDENTIFIER == "soleur-web-platform"`, but the app container
   is launched `docker run --name soleur-web-platform --log-driver journald`
   with no `--log-opt tag` (`apps/web-platform/infra/cloud-init.yml:811`), so
   journald `SYSLOG_IDENTIFIER` is the rotating container short ID
   (currently `e7b1da5ba07c` / `3bdb782cb4ab`). The stable field carrying the
   app name is `CONTAINER_NAME`.
2. **Payload extraction greps the wrong field.** The probe greps `.message`
   for `placement_decision`, but the structured placement payload lives in
   `.message_json` (the vector-parsed pino object: `.event`, `.decision`,
   `.host_ip`, `.class`); `.message` in these rows is an unrelated octokit
   deprecation line.

Live evidence (queried 2026-11-11 via `betterstack-query.sh --since 24h --grep
placement_decision --limit 5000`): 218 rows; 0 carry
`SYSLOG_IDENTIFIER == "soleur-web-platform"`; rows with
`CONTAINER_NAME == "soleur-web-platform"` show 11 `decision=forward
host_ip=10.0.1.11` and 94 `decision=execute host_ip=10.0.1.10` — the AC12 split
is already true in production, so the corrected probe exits 0 on its first run.

## Research Insights

### Premise Validation (Phase 0.6)

| Cited artifact | Verified | Note |
|---|---|---|
| #12587 | OPEN | carries `follow-through` label + directive `script=scripts/followthroughs/placement-decision-forward-9137.sh earliest=2026-11-12T12:43:15Z secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD` |
| PR #12554 / `f94e57a8` | MERGED 2026-11-11 | `feat(inngest): placement-aware execution` — the change under soak |
| `scripts/followthroughs/placement-decision-forward-9137.sh` | present, 100755 | defect lines confirmed: `:38-40` SYSLOG_IDENTIFIER select + `.message` grep; `:42-45` forward/execute arms |
| `apps/web-platform/infra/cloud-init.yml:811` | confirmed | `docker run -d --name soleur-web-platform --log-driver journald` — no `--log-opt tag` |
| `scripts/followthroughs/actions-queue-tail-8450.test.sh` | present | sibling fixture-test convention (stub on PATH/env, `expect <desc> <rc> <needle>`) |
| Open collision | PR #12650 is THIS branch's own draft WIP PR | not a foreign duplicate |

The live row counts above are operator-supplied evidence, re-verified by the
plan's own acceptance command before merge. No stale premises.

### Property List (Phase 0.6b)

- P1 — The probe admits only rows emitted by the `soleur-web-platform`
  container, excluding host-journald rows and the `SYSLOG_IDENTIFIER=doppler`
  webhook contamination class — the property the original `SYSLOG_IDENTIFIER`
  isolation was written for, retargeted at the field that carries the name for
  an untagged docker journald container.
- P2 — The probe reads the structured placement payload (`message_json.event ==
  "placement_decision"`, `.decision`, `.host_ip`), never the `.message` string.
- P3 — The exit contract is unchanged: 0 = split verified, 1 = still soaking,
  2 = TRANSIENT query-layer failure — and no partial arm ever produces exit 0.
- P4 — A fixture suite proves both arms, both missing-arm directions, the
  transient path, and contamination rejection against rows shaped like the real
  wire (double-encoded `raw` + `message_json` object).

### Cut List (Phase 0.6b)

| Cut mechanism | Property it would buy | What already covers it / why cut |
|---|---|---|
| Add `--log-opt tag=soleur-web-platform` to `cloud-init.yml`'s `docker run` | stable SYSLOG_IDENTIFIER | Container-launch change on a running host = redeploy/replace blast radius to fix a read-side bug; `CONTAINER_NAME` already carries the name with no deploy. Out of scope per the brief ("keep the probe's structure"). |
| Change `betterstack-query.sh` (server-side CONTAINER_NAME filter) | fewer rows over the wire | `--grep placement_decision` substring filter + post-decode field isolation already bound the read; the transport is shared by every probe and needs no change. |
| New tracker directive / secrets wiring | enrollment | Already staged in #12587's body (`secrets=BETTERSTACK_QUERY_*`); the `follow-through` label is applied. |
| Soak-window or threshold changes | — | The verification criterion in #12587 is unchanged; this is a read-side fix only. |

### Relevant files

- `scripts/followthroughs/placement-decision-forward-9137.sh` — the probe;
  `:26-29` header comment asserts SYSLOG_IDENTIFIER carries the app name
  (wrong for untagged docker journald); `:38-45` the defective jq + grep arms.
- `apps/web-platform/infra/cloud-init.yml:811` — the `docker run` proving
  `SYSLOG_IDENTIFIER` is the container short ID.
- `scripts/lib/web2-relay-rows.sh:92` — established precedent:
  `JSONExtractString(raw,'CONTAINER_NAME') = 'soleur-web-platform'` is how this
  repo isolates app-container rows.
- `scripts/image-cve-triage.sh:114` — precedent for `.raw | fromjson` →
  `.message_json | select(type == "object")` payload reads.
- `scripts/followthroughs/anthropic-admin-key-6297.test.sh` — fixture envelope
  convention (`{dt, raw:"<escaped JSON>"}`) + `env -i` hermetic probe runs.
- `scripts/suite-shard-legs.tsv` — shard registration; `lint-orphan-test-suites.sh`
  reds any tracked `*.test.sh` not registered (regen:
  `python3 scripts/regenerate-shard-manifest.py --incremental --write`).
- `scripts/followthrough-exec-bit.test.sh` — gates every
  `scripts/followthroughs/*.sh` (incl. `*.test.sh`) at index mode 100755.
- `scripts/lint-followthrough-varq-ban.sh` — probe lint the edit must keep
  passing (no `${VAR:?}`, no retired credential names, no unbounded `/events/`).
- `.github/workflows/scheduled-followthrough-sweeper.yml` +
  `scripts/sweep-followthroughs.sh` — the consumer of the exit contract
  (cron `0 18 * * *`; exit 0 closes the tracker, 1 keeps soaking, 2 retries).

### Institutional learnings applied

- `2026-07-18-betterstack-followthrough-probe-must-field-isolate-syslog-identifier.md`
  — field isolation exists because doppler-webhook rows (SYSLOG_IDENTIFIER=doppler)
  quote repo text verbatim; `CONTAINER_NAME` preserves that property since
  host-journald rows lack the field entirely. Also: fixture rows must model the
  real wire shape (double-encoded `raw`), or the suite passes a probe reality
  rejects — the #6475 failure mode this fixture avoids by construction.
- `2026-06-05-followthrough-pr-body-prose-closes-keyword-autocloses-tracker.md`
  — PR body uses `Ref #12587`, never `Closes #12587`; the sweeper owns closure.
- `2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md`
  — mutation matrix includes a starved-dispatch row and a second-member row.
- `2026-09-17-followthrough-directive-on-existing-issue-three-silent-traps.md`
  — the directive + label on #12587 were checked before assuming enrollment.

### Related issues

| Issue / PR | State | Relationship |
|---|---|---|
| #12587 | open | soak tracker this probe verifies; the sweeper closes it once the probe exits 0 after `earliest=2026-11-12T12:43:15Z` |
| PR #12554 (`f94e57a8`) | merged | placement-aware execution under soak; AC12 source |
| #9137 | referenced | parent placement-forwarding issue (epic #10390) |
| #8698 | open | object-shaped `message_json` decoder — same field family, orthogonal |
| PR #12650 | open draft | this branch's own WIP PR — the ship target |

## Problem Statement / Motivation

The probe's verdict gates an automated tracker close. Today it produces a
permanent exit-1: zero rows ever satisfy the isolation predicate, so the
sweeper will keep soaking #12587 indefinitely even though the production
evidence already meets the criterion. A soak probe that can never observe its
signal is a silently inert gate — the same dead-guard class the fixture test
exists to prevent from recurring.

**Reachability consequence (what each exit code triggers in the sweeper, per
`scripts/sweep-followthroughs.sh`):** exit 0 → sweeper posts a PASS and closes
#12587 (and never reopens a closure it justified); exit 1 → keeps soaking;
exit 2 → TRANSIENT, quiet retry next run. Making exit 0 reachable is the point
of this fix — and it is safe only because the criterion the unreachable verdict
was masking is the AC12 split itself, which the live 24h sample already
satisfies (11 `decision=forward host_ip=10.0.1.11` + 94 `decision=execute
host_ip=10.0.1.10`, all post-deploy). The directive's
`earliest=2026-11-12T12:43:15Z` gate still applies, so no close can fire before
the soak window regardless of when the probe first exits 0 (#11393 class —
checked: the evidence the close would act on is post-deploy, not pre-fix).

## Proposed Solution

Two surgical edits inside the probe's existing structure (exit codes, env
overrides `PLACEMENT_FT_QUERY` / `PLACEMENT_FT_WINDOW`, and the
`fwd > 0 && exe > 0` verdict are all preserved):

1. **Row isolation** — `select(.SYSLOG_IDENTIFIER == $id)` →
   `select(.CONTAINER_NAME == $id)`. The docker journald driver sets
   `CONTAINER_NAME` on container rows; host-journald rows (including the
   doppler webhook contaminant class) lack the field, so the exclusion the
   original comment intended is preserved.
2. **Payload extraction** — replace `.message | grep 'placement_decision'`
   with a `.message_json` parse emitting compact objects the existing grep
   arms keep consuming:

   ```jq
   .raw | fromjson | select(.CONTAINER_NAME == $id)
     | (.message_json // {}) | select(type == "object")
     | select(.event == "placement_decision")
     | {decision, host_ip}
   ```

   emitted with `jq -c`, so `grep '"forward"'` / `grep '"execute"'` and the
   `host_ip` predicates (`"host_ip":[[:space:]]*"10.0.1.10"`) match unchanged.
   `select(type == "object")` mirrors `image-cve-triage.sh:114` and makes a
   non-object `message_json` (string/absent) drop rather than error.
3. **Header comment** — rewrite the field rationale: for an untagged docker
   journald container `SYSLOG_IDENTIFIER` is the rotating container short ID
   and `CONTAINER_NAME` carries the app name; the doppler-exclusion intent and
   the "no exit 0 on partial success" contract are restated, not weakened.

## Files to Edit

- `scripts/followthroughs/placement-decision-forward-9137.sh` — header comment
  (`:26-29`) + the jq extraction (`:38-40`); grep arms (`:42-45`) unchanged.
- `scripts/suite-shard-legs.tsv` — register the new suite via
  `python3 scripts/regenerate-shard-manifest.py --incremental --write`
  (enforcement: `lint-orphan-test-suites.sh`).

## Files to Create

- `scripts/followthroughs/placement-decision-forward-9137.test.sh` — fixture
  suite, committed 100755 (enforcement: `followthrough-exec-bit.test.sh`),
  mirroring `actions-queue-tail-8450.test.sh` / `anthropic-admin-key-6297.test.sh`:
  `env -i` hermetic runs with `PLACEMENT_FT_QUERY` pointed at an executable
  fixture-printing stub; fixture rows carry the real wire shape
  (`{dt, raw:"<json-string>"}`, decoded raw holding `CONTAINER_NAME`,
  `SYSLOG_IDENTIFIER`, `message`, `message_json`).

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` searched for all four
file paths; zero hits.

## Technical Considerations

- `betterstack-query.sh` `raw` is double-encoded JSON; the `.raw | fromjson`
  decode stays, only the downstream predicates move.
- The fixture test needs no credentials and completes well under the 15 s
  preflight probe cap.
- `PLACEMENT_FT_QUERY` stub must be executable (the probe checks `[[ -x ]]`)
  and exit non-zero to model the TRANSIENT arm.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — the
  failure modes are an internal tracker left open (missed verification) or
  auto-closed on a false exit 0, both inside the ops sweeper.
- **If this leaks, the user's data / workflow / money is exposed via:** no
  exposure vector — the probe reads log rows and emits counts; it writes
  nothing to any user surface.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** internal verification tooling on an
  ops surface; the worst case is a wrong soak verdict on a tracker issue, not
  a user-visible defect or data exposure. No sensitive-path diff
  (`scripts/followthroughs/`, `scripts/suite-shard-legs.tsv` all miss the
  preflight `SENSITIVE_PATH_RE`).

## Observability

The observability layer for this change is the follow-through sweeper itself:
the probe is the signal, `scheduled-followthrough-sweeper.yml` is the cadence,
and tracker #12587 is the surface the verdict lands on.

```yaml
liveness_signal:
  what: "probe exit code per daily sweeper run (0 = split verified → tracker close; 1 = still soaking; 2 = TRANSIENT retry)"
  cadence: "daily, cron 0 18 * * *, once earliest=2026-11-12T12:43:15Z has passed"
  alert_target: "tracker #12587 (sweeper posts verdict comments there)"
  configured_in: ".github/workflows/scheduled-followthrough-sweeper.yml + scripts/sweep-followthroughs.sh"
error_reporting:
  destination: "tracker #12587 via sweeper comment; probe stdout/stderr in the Actions run log"
  fail_loud: "probe prints 'TRANSIENT: betterstack-query.sh exited …' on query-layer failure (exit 2); a non-executable probe is reported by sweep-followthroughs.sh"
failure_modes:
  - mode: "probe can never observe its signal (the field-isolation defect this plan fixes)"
    detection: "fixture suite reds on a wrong-field read before merge; post-merge the live verification command in the Acceptance Criteria proves exit 0"
    alert_route: "tracker #12587 stays open past the soak window — the sweeper run log is the surface"
  - mode: "Better Stack query layer down or credentials rotated"
    detection: "exit 2 TRANSIENT — sweeper retries next run, no false FAIL posted"
    alert_route: "sweeper run log; no page (transient by contract)"
logs:
  where: "scheduled-followthrough-sweeper.yml Actions run logs (probe stdout/stderr captured per run)"
  retention: "GitHub Actions default log retention"
discoverability_test:
  command: "bash scripts/followthroughs/placement-decision-forward-9137.test.sh"
  expected_output: "All fixtures passed."
```

## Guard Contract

The probe is an assertion-based check executed by the sweeper, and the new
fixture suite is the anti-vacuity control over it — the deliverable includes a
guard.

### Guard 1 — placement_decision split verdict only on container-emitted structured rows

**Property.** The probe exits 0 iff journald rows emitted by the
`soleur-web-platform` container carry `message_json` placement_decision events
showing BOTH `decision=forward` with `host_ip != 10.0.1.10` AND
`decision=execute` with `host_ip == 10.0.1.10`; contamination rows, wrong-field
rows, partial evidence, and an empty window never produce exit 0.

**Assembly.** Every row returned by `betterstack-query.sh --since <window>
--grep placement_decision --limit 5000` flows through the single chokepoint in
the probe: `.raw | fromjson` → `CONTAINER_NAME` select → `message_json`
object/event select → forward/execute arms → `fwd`/`exe` counters →
`(( fwd > 0 && exe > 0 ))`. The fixture stub replaces the transport via
`PLACEMENT_FT_QUERY`, so the suite exercises every row shape the chokepoint can
consume; the sweeper (`sweep-followthroughs.sh` exec of the probe path) is the
only production dispatch.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Probe reverts isolation to `SYSLOG_IDENTIFIER == $id` | RED — fixtures carry the name only in `CONTAINER_NAME`; the bare-SYSLOG_IDENTIFIER contaminant row asserts the old predicate admits what the new one must reject |
| 2 | Probe greps `.message` instead of parsing `.message_json` | RED — qualifying rows carry the event only in `message_json`; a row whose `.message` mentions `placement_decision` with no `message_json` asserts the old extraction admits what the new one must reject |
| 3 | Guard's own dispatch starved: fixture prints zero rows (or stub exits non-zero) | probe exits 1 (or 2) — a suite/probe reporting pass on empty input is vacuous |
| 4 | Second-member: only the execute arm present (forward arm missing) | exit 1 — a verdict that stops at the first compliant arm is the defect class |
| 5 | Contaminant row: `SYSLOG_IDENTIFIER=doppler`, no `CONTAINER_NAME`, qualifying `message_json` | row must not satisfy either arm |
| 6 | Must-PASS: both arms present interleaved with unrelated container rows | exit 0 — proves the guard does not reject everything |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Row isolation: `.raw \| fromjson \| select(.SYSLOG_IDENTIFIER == $id)` → `select(.CONTAINER_NAME == $id)`" | Files to Edit: probe jq extraction | mapped |
| 2 | "Payload: replace the `.message \| grep 'placement_decision'` extraction with a `.message_json` parse — `(.message_json // {}) \| select(.event == \"placement_decision\")`" | Files to Edit: probe jq extraction | mapped |
| 3 | "Update the header comment's field rationale … and keep the 'do not exit 0 on partial success' contract" | Files to Edit: probe header comment; AC-1 | mapped |
| 4 | "Add a fixture test scripts/followthroughs/placement-decision-forward-9137.test.sh matching sibling convention (see actions-queue-tail-8450.test.sh)" | Files to Create: fixture suite | mapped |
| 5 | "Verify: `doppler run -p soleur -c prd_terraform -- bash scripts/followthroughs/placement-decision-forward-9137.sh` exits 0 printing the 'split verified' line" | AC-4 | mapped |
| 6 | "PR body must use `Ref #12587`, never `Closes #12587` … semver:patch" | AC-5 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Probe jq + header edits | asks 1–3 | asked |
| Fixture test | ask 4 | asked |
| `suite-shard-legs.tsv` registration | — | inferred — justification: `lint-orphan-test-suites.sh` reds any tracked `*.test.sh` run by no runner; without registration the suite ships orphaned (an enforcement contract requires it) |
| 100755 index mode on the new test file | — | inferred — justification: `followthrough-exec-bit.test.sh` gates every `scripts/followthroughs/*.sh` at 100755 |

### Split Assessment

- Subsystems touched: 1 — `scripts/`
- Planned files: 3 | Estimated changed lines: ~160
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal ops tooling change on an
existing verification surface. The mechanical UI-surface override does not
fire (no `*.tsx`/`page.tsx`/`layout.tsx` in the file lists).

## Acceptance Criteria

- [ ] `placement-decision-forward-9137.sh` isolates rows on
      `CONTAINER_NAME == "soleur-web-platform"` and reads the placement payload
      from `message_json` (`event`/`decision`/`host_ip`); exit contract
      0/1/2 and the `fwd > 0 && exe > 0` no-partial-success verdict unchanged.
- [ ] Header comment states the real field rationale (untagged docker journald
      → `SYSLOG_IDENTIFIER` is the rotating short ID, `CONTAINER_NAME` carries
      the app name, doppler/host rows excluded) and the exit contract.
- [ ] `scripts/followthroughs/placement-decision-forward-9137.test.sh` exists,
      is committed 100755, is registered in `scripts/suite-shard-legs.tsv`, and
      passes locally covering: both arms → 0; each missing arm → 1; stub
      failure/non-executable → 2; doppler contaminant + bare-SYSLOG_IDENTIFIER
      rows satisfy neither arm.
- [ ] `doppler run -p soleur -c prd_terraform -- bash
      scripts/followthroughs/placement-decision-forward-9137.sh` exits 0
      printing the `placement_decision split verified` line.
- [ ] PR body carries `Ref #12587` (never `Closes #12587`) and a
      `## Changelog` section; label `semver:patch`.

## Test Scenarios

All scenarios are `integration` layer (the fixture suite runs the real probe
end-to-end against stub-transport input — the lowest layer exercising the full
jq pipeline and exit contract):

- Given fixtures with CONTAINER_NAME=soleur-web-platform rows carrying
  `message_json` forward-off-exec AND execute-on-exec events, when the probe
  runs, then it exits 0 printing `split verified`.
- Given only the execute arm, when the probe runs, then exit 1.
- Given only the forward arm, when the probe runs, then exit 1.
- Given a `decision=forward` row with `host_ip=10.0.1.10` (forward on exec),
  when the probe runs, then it does not satisfy the off-exec arm → exit 1.
- Given a doppler row (`SYSLOG_IDENTIFIER=doppler`, no `CONTAINER_NAME`)
  carrying a qualifying `message_json`, when the probe runs, then it
  contributes to neither arm.
- Given a host-journald row with `SYSLOG_IDENTIFIER=soleur-web-platform` and
  no `CONTAINER_NAME` carrying a qualifying `message_json`, when the probe
  runs, then it contributes to neither arm (pins the field swap).
- Given a CONTAINER_NAME row whose `.message` mentions `placement_decision`
  but whose `message_json.event` differs (or `message_json` absent), when the
  probe runs, then it contributes to neither arm (pins the payload source).
- Given the stub exits non-zero (or is non-executable), when the probe runs,
  then exit 2 TRANSIENT.
- Given an empty result set, when the probe runs, then exit 1.
- Property that must never break: no single arm, contaminant, or
  wrongly-shaped row can produce exit 0 — the close verdict requires both
  arms from container-emitted `message_json` events only.

## Non-Goals

- No `cloud-init.yml` / `docker run` changes (no `--log-opt tag` retrofit).
- No `betterstack-query.sh` transport changes.
- No tracker directive, label, or secrets changes — enrollment is already
  staged on #12587.
- No changes to the AC12 verification criterion itself.

## References

- Tracker: #12587 · Source PR: #12554 (`f94e57a8`) · Parent: #9137
- Sibling conventions: `scripts/followthroughs/actions-queue-tail-8450.test.sh`,
  `scripts/followthroughs/anthropic-admin-key-6297.test.sh`
- Field precedent: `scripts/lib/web2-relay-rows.sh:92`,
  `scripts/image-cve-triage.sh:114`
- Enforcement: `scripts/lint-orphan-test-suites.sh`,
  `scripts/followthrough-exec-bit.test.sh`,
  `scripts/lint-followthrough-varq-ban.sh`,
  `scripts/sweep-followthroughs.sh`,
  `.github/workflows/scheduled-followthrough-sweeper.yml`
- Convention doc: `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`

Note: no `spec.md` exists for this branch — `lane:` defaulted to `cross-domain`
(fail-closed).
