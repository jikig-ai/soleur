# Tasks: SOLEUR_HOST_KERNEL marker + stale-kernel alert (#12007)

Plan: `knowledge-base/project/plans/2026-11-08-feat-host-kernel-marker-stale-kernel-alert-plan.md`
Rulings: `knowledge-base/project/specs/feat-one-shot-12007-host-kernel-marker/decision-challenges.md`
Holds (never in this run, each needs an explicit per-command go-ahead): apply, host replace, arming a heartbeat, any host connection (#12386).

## Phase 0: Failing tests first

- 0.1 `host-state.test.sh`: add fixtures for web-1, web-2, inngest, registry kernel rows (synthesized kernels only)
  - 0.1.1 Guard 1 mutation rows 1-9, harness rows, must-PASS non-canonical rows
  - 0.1.2 Producer-contract rows (collector literal, SyslogIdentifier, allowlist entry, registry post call, registry id constant equality)
  - 0.1.3 Rewrite the canary-kernel assertions from `observed` to `stale`; raise `MIN_CASES`
  - 0.1.4 Add the new class to the SQL pins (`multiIf` tag, `OR`-clause count)
- 0.2 `deadman-heartbeat-feeder.test.sh`: rehearsal rows for the four targets (fresh beats, old withholds, empty withholds, cross-host does not feed, unreadable kernel withholds), window literal pin
  - 0.2.1 Rewrite the loop pin to "loop = TARGETS minus DEFERRED_TARGETS"
  - 0.2.2 Extend the wiring pin (`want_res` / `EXPECT_TARGETS`) with the four heartbeat `-target` lines
- 0.3 New `apps/web-platform/infra/host-kernel-marker.test.sh`: collector grammar, stubbed apt/uname/uptime, bad role exit 64, Guard 3 census (extends the existing host census), unit-to-allowlist join, byte-parity of baked copies, neither server in a per-merge `-target` list
- 0.4 Register the suite (`suite-durations.tsv`, `suite-shard-legs.tsv`, runner population); run `scripts/lint-orphan-test-suites.sh`

## Phase 1: Collector and units

- 1.1 `apps/web-platform/infra/host-kernel-marker.sh` (one line, explicit PATH, `LC_ALL=C`, role allowlist, `kernel=` followed by a space, `sec_updates` best effort, `host=` only for `--role registry`)
- 1.2 `host-kernel-marker.service` and `host-kernel-marker.timer` (plain names; `OnBootSec=2min`, 6-hourly `OnCalendar`, `Persistent=true`, `RandomizedDelaySec`)

## Phase 2: Vector allowlist

- 2.1 `vector.toml`: include entry plus the inngest-source exclude mirror (set-equal), quota note, no `systemd`
- 2.2 `journald-config.test.sh`, `vector-admission.test.sh`, `vector-pii-scrub.test.sh` (scrub fixture); grep for the derived-tag test the header calls AC3

## Phase 3: Delivery per host class (nothing applied)

- 3.1 Web: `server.tf` bake list, installers (web-1 and web-2 twin, sibling shape), `OPERATOR_APPLIED_EXCLUSIONS` entries, `.dockerignore`, `Dockerfile` COPY, `soleur-host-bootstrap.sh`, `cloud-init.yml`, parity tests (`W2_ALLOWED`), `fresh-boot-parity.test.sh`, user-data size test
- 3.2 Inngest: `inngest-bootstrap.sh` writes and enables its own unit pair; bootstrap image build carries the collector; byte-parity test; `inngest-userdata-budget.sh`
- 3.3 Registry: collector support only (`--role registry`, helper and feeder decode, the paused `host-kernel-registry` heartbeat). The registry emitter (`cloud-init-registry.yml`, the once-per-6h call in `zot-disk-heartbeat.sh`, `registry-userdata-budget.sh`) is a follow-up PR the owner approves before it merges, because its merge auto-fires `registry-host-replace-dispatch.yml` and replaces the production registry host (#12386). Registry stays `unknown` until then
- 3.4 Apply-path assertions: heartbeat `-target` lines in the main list; registry/inngest absent from per-merge targets; `cloud-init-registry.yml` unchanged against the merge base, so the dispatcher's render gate emits deliver=false

## Phase 4: Alert and runbooks

- 4.1 `scripts/deadman-heartbeat-feeder.sh`: four targets, window 129600, `$`-free predicates, `--selftest`
- 4.2 `uptime-alerts.tf`: four paused heartbeats; `heartbeat-manifest.ts` rows with `feeder: none` + tracking issue 12386
- 4.3 Workflow comment only (no loop change); `betterstack-log-query.md` section; arming runbook (two-stage order, pause before planned replace, expected-unknown note)

## Phase 5: Helper and skill text

- 5.1 `host-state.sh`: `kern` class (explicit `multiIf` arm), identity rules, `observed|stale|unknown`, newest-valid-row precedence, keep probe/NIC/ZOT clauses intact
- 5.2 `SKILL.md` Steps 3, 5, 6 and `component-map.md`
- 5.3 ADR-322 amendment (via `soleur:architecture`); `model.c4` edge clauses and provisioner count; C4 tests

## Phase 6: Ratchet sweep

- 6.1 kb-consumers baseline, guard-vacuity floor, probe-row census (no allowlist edit), public-claim guard, marker telemetry test, alert-structure test, heartbeat parity, c4 count parity, orphan lint
- 6.2 Diff sweep for kernel-shaped strings and host literals outside fixtures

## Phase 7: PR

- 7.1 PR body: `Closes #12007`, `Ref #12385`, `Ref #12386`, Holds block, Claude Code attribution line last
