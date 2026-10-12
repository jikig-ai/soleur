# Tasks — feat-one-shot-9963-syslog-systemd-journald-path (#9963)

Plan: `knowledge-base/project/plans/2026-10-12-chore-pin-syslog-systemd-journald-path-plan.md`

## Phase 1 — document the mechanism in vector.toml (AC1)

- [ ] 1.1 `apps/web-platform/infra/vector.toml` — rewrite the `[sources.inngest_journald]` header comment: journalctl is spawned with NO match args (`--follow --all --show-cursor --output=json`), matching is client-side `filter_matches`/`contains_match` = OR over all record fields; `include_units` merges into `include_matches._SYSTEMD_UNIT`; therefore the source admits `_SYSTEMD_UNIT=inngest-server.service` (any priority) OR `PRIORITY ∈ {0..4}` (any unit). Correct the false "INFO+DEBUG drop at source" claim (PRIORITY-6 inngest lines ship — OBSERVED, betterstack-logs-alerts.tf:492-496).
- [ ] 1.2 Same file, `[sources.system_journald]` header: `PRIORITY ∈ {0..2} AND NOT excluded unit` under the same evaluator; name the PRIORITY≤2 Source-1↔Source-2 double-admission (CRIT+ host rows ship twice).
- [ ] 1.3 Same file: document the `SYSLOG_IDENTIFIER=systemd` path explicitly (PID-1 `Failed to start`, PRIORITY 3, `UNIT=`/`JOB_RESULT=failed` → Source-1 PRIORITY arm → `pii_scrub_*` → `tag_journald` → `sinks.betterstack` → source 2457081); the `systemd`-never-in-Source-4 trap with the quota reason; cross-links #9963/#6551/#8875 and the `vector.tf:13` version pin. Update the stale `~1,240 rows/day` paragraph (:168-171) — the mechanism is no longer unexplained.

## Phase 2 — control emission (AC2)

- [ ] 2.1 `apps/web-platform/infra/inngest-bootstrap.sh` — inside the `PROBESCRIPTEOF` heredoc, next to the unconditional `SOLEUR_INNGEST_SERVER_PROBE` emit (~:1211), add `logger -t systemd -p err "SOLEUR_SYSTEMD_JOURNALD_CONTROL host=$(hostname -s) ts=$(date -u +%s) — rides the inngest_journald PRIORITY≤4 admission arm (#9963)"`. Unconditional; outside any credential-gated block (probe ExecStart is a plain script, not doppler-wrapped — preserves the R3-4.5d invariant).

## Phase 3 — consumer wiring (AC4, AC5)

- [ ] 3.1 `scripts/betterstack-assert-absence.sh` — add repeatable `--control-require <substring>` AND'd onto the control predicate inside `run_count` call for the control read (mirror `--absence-require` composition + SQL escaping); extend the usage text with the systemd-path recipe (`--control 'SOLEUR_SYSTEMD_JOURNALD_CONTROL' --control-require '"SYSLOG_IDENTIFIER":"systemd"'`).
- [ ] 3.2 `scripts/followthroughs/inngest-provision-rehearsal-capture.sh` — add `count_systemd_path_control` (two-stage grep: marker `SOLEUR_SYSTEMD_JOURNALD_CONTROL` AND `SYSLOG_IDENTIFIER.{0,8}systemd`, mirroring `count_inngest_failed`'s shape) + a `systemd_path_check` arm beside `inngest_failed_check`: zero → `want` (TRANSIENT), ≥1 → proceed.

## Phase 4 — pins and suites (AC3, AC6, AC8)

- [ ] 4.1 `apps/web-platform/infra/journald-config.test.sh` — emission-anchored arms (mirror R3-4.5): the emit line exists in inngest-bootstrap.sh's PROBESCRIPTEOF (anchor on the emission, not the bare token), carries `-t systemd` AND `-p err`, and `systemd` is absent from the Source-4 allowlist in vector.toml. No `<<< 'literal'` (bind feeds to variables); floors via `printf >&2` + `exit 1`, never the assert helpers they backstop.
- [ ] 4.2 `apps/web-platform/test/infra/vector-pii-scrub.test.sh` — documented PRIORITY-arm exemption registry entry for tag `systemd` (the literal `logger -t systemd` is derivable by AC3 but must NOT join EXPECTED-tags-as-allowlist) + Source-1 `include_matches.PRIORITY` drift pin (arm the control rides).
- [ ] 4.3 `scripts/betterstack-assert-absence.test.sh` — arms: field-scoped control satisfied → live; marker-only row → `unshipping`; flag absent → legacy behaviour; require AND'd into control predicate (asserted via stub SQL dispatch).
- [ ] 4.4 `scripts/followthroughs/inngest-provision-rehearsal-capture.test.sh` — fixtures: control present (marker+systemd tag) / absent / marker-on-doppler-tag contaminated (must NOT satisfy).
- [ ] 4.5 Exercise the Guard-Contract mutation matrix (each RED row verified to fire; must-PASS rows pass).

## Phase 5 — decision record (AC7)

- [ ] 5.1 ADR-286 (verify next-free ordinal at write/ship time; sweep `grep -rn 'ADR-<n>'` if renumbered) — `knowledge-base/engineering/architecture/decisions/ADR-286-<slug>.md`: OR-over-fields mechanism + path-scoped-control convention + #6551/#8875 deferral; status `adopting`.

## Phase 6 — verify (AC8, AC9)

- [ ] 6.1 `bash -n` on every edited `.sh`; run suites `scripts/betterstack-assert-absence`, `scripts/followthroughs/inngest-provision-rehearsal-capture`, `apps/web-platform/infra/journald-config`, `apps/web-platform/test/infra/vector-pii-scrub` — all green.
- [ ] 6.2 PR body records delivery staging: vector.toml → web-1 via `journald_persistent` replace on next apply; inngest host emits the control only after next `apply_target=inngest-host-replace` dispatch; interim `unshipping` on `soleur-inngest-prd` is correct. `Closes #9963`.
