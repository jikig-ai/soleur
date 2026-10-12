---
title: "chore(infra): pin the unexplained SYSLOG_IDENTIFIER=systemd journald shipping path to Better Stack"
date: 2026-10-12
slug: chore-pin-syslog-systemd-journald-path
branch: feat-one-shot-9963-syslog-systemd-journald-path
issue: 9963
closes: 9963
type: chore
domain: engineering
priority: p3-low
brand_survival_threshold: none
lane: cross-domain
---

# Plan: pin the SYSLOG_IDENTIFIER=systemd journald shipping path to Better Stack (#9963)

## Overview

Issue #9963 asks three things of the `SYSLOG_IDENTIFIER=systemd` journald rows
(the `Failed to start <unit>` class) that demonstrably shipped to Better Stack
source `soleur-inngest-vector-prd` during the #9939 storm (~1,240 rows/day)
while no `vector.toml` source appeared to admit them: (1) identify what actually
ships them, (2) document it in `vector.toml`, (3) add a positive-control row
type so the absence assertions that now depend on those rows cannot report a
vacuous clean if the delivery path dies.

**The mechanism is now identified** (see Research Insights): it is not a rogue
shipper and not `journalctl` match semantics. Vector 0.43.1's `journald` source
spawns `journalctl --follow --all --show-cursor --output=json` with **no match
arguments**, streams the entire journal, and filters each decoded record
client-side. Its `contains_match` is an **OR over all record fields**: a record
is admitted if ANY of its fields has a value in that field's match set.
`include_units` is merged into `include_matches._SYSTEMD_UNIT`, so Source 1
(`inngest_journald`) admits a record iff
`_SYSTEMD_UNIT=inngest-server.service` **OR** `PRIORITY ∈ {0,1,2,3,4}` — every
host row at PRIORITY ≤ 4 from any unit, plus every inngest-server row at any
priority. A PID-1 `Failed to start` row (PRIORITY 3, `UNIT=`,
`JOB_RESULT=failed`) is admitted by that PRIORITY arm and flows
`pii_scrub_* → tag_journald → sinks.betterstack` to Logs source 2457081.

This plan documents the real semantics in `vector.toml`, adds the
`SOLEUR_SYSTEMD_JOURNALD_CONTROL` row (hourly, `logger -t systemd -p err`, from
`inngest-server-probe.sh`), wires both named consumers to it, and pins the
whole chain in the existing drift-guard test suites.

*Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed).*

## Research Insights

### Premise Validation (Phase 0.6)

Every cited artifact was verified against the worktree before any design work:

| Cited artifact | Verified | Note |
|---|---|---|
| `apps/web-platform/infra/vector.toml:155-158` documents `SYSLOG_IDENTIFIER=systemd` unexplained delivery | ✓ present | comment at :169-171 on this branch, "via a mechanism this file does not explain (a live row carries SYSLOG_IDENTIFIER=systemd, which NO source here admits; tracked separately)" |
| `scripts/followthroughs/inngest-provision-rehearsal-capture.sh` `luks_failed_check` (added #9944) | ✓ present | now `inngest_failed_check`/`count_inngest_failed` (:299-329), widened to `(inngest|vector|soleur-inngest)` by #9962; header comment still says the delivery path "is documented unexplained" |
| `scripts/betterstack-assert-absence.sh` | ✓ present | already has `--absence-require` (added during the #9939 work, per its session-state.md) but **no `--control-require`** — the control read is marker-substring only |
| #9939 | CLOSED | source incident |
| PR #9944 | MERGED | the ConditionPathExists fix |
| #6551 / #8875 / #8698 / #6944 | all OPEN | sibling scope discrimination below |

No stale premises. One nuance sharper than the issue states: the OR semantics
is already *depended on* — `vector-pii-scrub.test.sh`'s #7898 Source-2 pin
asserts `include_matches.PRIORITY = ["0","1","2"]` precisely because host-script
`logger -p user.crit` refusal rows ship "from ANY unit" through that arm, and
`betterstack-logs-alerts.tf:492-496` records OBSERVED PRIORITY-6 inngest lines
shipping ("the source's `include_units` admits the unit independently of the
PRIORITY match (Vector appears to OR the two; the same mechanism is the suspect
in #6551)"). "Unexplained" applies to `vector.toml`'s prose, not to reality.

### The mechanism, evidence-level

Read at `https://raw.githubusercontent.com/vectordotdev/vector/v0.43.1/src/sources/journald.rs`
(Vector pin: `vector.tf:13` `vector_version = "0.43.1"`):

- `Journalctl::make_command` builds `journalctl --follow --all --show-cursor
  --output=json [--directory|--namespace|--boot|--since|--after-cursor]
  [extra_args]` — **no match arguments are ever passed**. The whole journal is
  streamed to the Vector process.
- `merge_units(matches, units)` inserts `include_units` values into
  `include_matches` under key `_SYSTEMD_UNIT` (`HashMap<String, HashSet<String>>`).
- `contains_match(record, matches)` = `record.iter().any(|(field, value)|
  matches.get(field).map(|set| set.contains(value)).unwrap_or(false))` —
  **a record is admitted when ANY of its fields carries a matched value**.
- `filter_matches` drops a record iff `!contains_match(record, includes) ||
  contains_match(record, excludes)`.

Derived consequences (each cited to a source block):

1. `inngest_journald` (vector.toml:51-56): `_SYSTEMD_UNIT=inngest-server.service
   OR PRIORITY ∈ {0..4}` → ships every host journald row at PRIORITY ≤ 4
   **regardless of unit or SYSLOG_IDENTIFIER**, plus all inngest-server rows at
   every priority. The header comment "INFO+DEBUG (5,6,7) drop at source" is
   false for the unit's own rows (OBSERVED live lines at PRIORITY 6).
2. `system_journald` (:61-66): `PRIORITY ∈ {0,1,2} AND NOT(_SYSTEMD_UNIT ∈
   {inngest-server.service, vector.service})` → overlaps Source 1 on
   PRIORITY ≤ 2 — every CRIT+ host row ships **twice** (once per source's
   journalctl stream).
3. `host_scripts_journald` (:186+): single-field match `SYSLOG_IDENTIFIER ∈
   {tags}` — behaves exactly as its comment intends.
4. `app_container_journald` / `egress_gw_journald`: single-field
   `CONTAINER_NAME` matches — as intended.
5. `SYSLOG_IDENTIFIER=systemd` rows (`Failed to start`, PRIORITY 3): admitted
   by Source 1's PRIORITY arm. Sink: `sinks.betterstack` (:606-620) generic
   HTTP → `s2457081.eu-fsn-3.betterstackdata.com`. Journald fields
   (`SYSLOG_IDENTIFIER`, `UNIT`, `JOB_RESULT`, `PRIORITY`) pass through the
   three `pii_scrub_*` transforms and `tag_journald` unmodified into `raw`.
6. A Source-4 tag row at PRIORITY ≤ 4 (e.g. `ci-deploy` at `user.warning` = 4)
   is admitted by **both** Source 1 and Source 4 → duplicate rows. Already
   observable in principle; documenting, not newly caused.

### Property List (Phase 0.6b)

- P1 — The delivery path for `SYSLOG_IDENTIFIER=systemd` journald rows is
  written down in `vector.toml` where a config reader sees it, with the real
  admission semantics (OR-over-fields, client-side filtering), the named
  admission arm, the sink, and the cross-issue references.
- P2 — A positive-control row transits the SAME admission arm carrying the SAME
  discriminator field (`SYSLOG_IDENTIFIER=systemd`), on a bounded cadence,
  host-scoped, so "zero matching rows" can never be read as clean on a dead
  path.
- P3 — Both named consumers bind the control: `betterstack-assert-absence.sh`
  (control read) and `inngest_failed_check` in the rehearsal capture (its
  "zero Failed-to-start rows" PASS).
- P4 — The pins anchoring emit/tag/priority/never-in-Source-4 cannot be
  silently removed (emission-anchored, not token-anchored), and contaminated
  marker-carrying rows (webhook/issue-body quotes, the measured false-match
  class) cannot satisfy the control.

### Cut List (Phase 0.6b)

| Cut mechanism | Property it would buy | What already covers it / why cut |
|---|---|---|
| Re-architect Source 1/2 to journalctl-style AND semantics (e.g. remap/filter transforms) | "sources mean what their comments say" | Tracked by #6551 (the bug) and #8875 (emitter selection); changes delivery + requires quota re-measure + dedupe handling. Out of #9963 scope — the issue asks to *pin* the path, not fix the semantics. Documented as an explicit boundary. |
| Dedicated `soleur-systemd-journald-control.{service,timer}` | periodic control emission | `inngest-server-probe.timer` already provides hourly cadence (`OnUnitActiveSec=1h`, `OnBootSec=90s`), an unconditional emit, and a non-doppler-wrapped ExecStart. A second unit buys no property. |
| Add `"systemd"` to Source 4 `include_matches.SYSLOG_IDENTIFIER` | "ship systemd rows deliberately" | Ships ALL PID-1 chatter incl. every PRIORITY-6 `Started/Stopped` line — quota blow (the trap the Source-4 comment already names for a PRIORITY widen). The control only needs to prove the *admission arm + discriminator* transit, which `-t systemd -p err` does with ~24 rows/day. |
| New Better Stack alert on the control row | "control silence pages" | The control's consumers ARE the alerting surface (`unshipping`/`TRANSIENT`). A separate alert would page on the interim not-yet-deployed window (delivery staging below). Cut. |
| `betterstack-query.sh` changes | — | Not needed; all queries are raw SQL via the existing transport. |

### Relevant files

- `apps/web-platform/infra/vector.toml` — the documentation target; Sources 1/2
  comments currently assert AND semantics that do not exist.
- `apps/web-platform/infra/inngest-bootstrap.sh` — `inngest-server-probe.sh`
  heredoc (`PROBESCRIPTEOF`, emit at :1211; unit block :1238-1286) is the
  control emit site; `logger -t` usage precedent at :299, :482, :1462.
- `scripts/betterstack-assert-absence.sh` — `--absence-require` shape at :78-86,
  :155-163 to mirror for `--control-require`; control read at :224-231.
- `scripts/followthroughs/inngest-provision-rehearsal-capture.sh` —
  `count_inngest_failed`/`inngest_failed_check` :299-329; `HOST_ROWS` fetch
  :218-223 (`position(raw,'"host":"<name>"')`).
- `apps/web-platform/infra/journald-config.test.sh` — R3-4.5 canary lockstep
  precedent (:491-534).
- `apps/web-platform/test/infra/vector-pii-scrub.test.sh` — AC3 `logger -t`
  tag-set derivation (:422-529): a literal `logger -t systemd` is pulled into
  EXPECTED_TAGS → requires a documented exemption entry (new registry), plus a
  `systemd`-never-in-Source-4 pin. #7898 Source-2 drift pin :667-684 shows the
  shape to mirror for a Source-1 arm pin.
- `apps/web-platform/infra/betterstack-logs-alerts.tf:492-496` — records the
  OBSERVED OR behaviour; keep consistent with the new vector.toml prose.
- `apps/web-platform/infra/server.tf:1321-1440` — `terraform_data.journald_persistent`
  delivery for web-1 (hash over journald-soleur.conf + vector.toml).
- `apps/web-platform/infra/inngest-host.tf` + `server.tf:1066` — dedicated
  inngest host takes bootstrap/vector.toml changes only via
  `apply_target=inngest-host-replace`.

### Institutional learnings applied

- `2026-07-18-betterstack-followthrough-probe-must-field-isolate-syslog-identifier.md`
  — control/needle reads must field-isolate `"SYSLOG_IDENTIFIER":"systemd"`,
  never bare-substring (doppler-tagged webhook rows quote repo text verbatim).
- `2026-07-18-web-1-…-vector-toml-has-no-running-host-delivery.md` — file-only
  changes do not reach a running host; delivery staging is a plan item.
- ADR-192 (`an-empty-warehouse-read-is-three-states`) — the control is a new
  `marker`-mode producer heartbeat; I-2 (no marker predicate satisfiable by
  attacker-influenced rows) is what makes `--control-require` load-bearing.
- `2026-06-10-betterstack-quota-diagnosis` — every shipped row spends quota;
  the control is bounded at ~24-48 rows/day.
- `2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md`
  — mutation matrix written from the design, includes dispatch-kill,
  second-member, and must-PASS/must-RED harness rows.

### Related issues (scope discrimination)

| Issue | State | Relationship |
|---|---|---|
| #9963 | open | this plan |
| #6551 | open, bug p2 | SAME root mechanism (OR-over-fields admits a row no source "admits"). This plan documents the mechanism and scopes the fix to documentation + control for the systemd-tag path; the semantic fix itself stays with #6551. Do NOT close on this PR — verify separately. |
| #8875 | open | emitter-based reader selection. The new control row carries `SYSLOG_IDENTIFIER=systemd` with a distinct marker; documented as an exempt control class for that migration. Stays open. |
| #8698 | open | object-shaped message decoder — orthogonal. Stays open. |
| #6944 | open | host_metrics native-shape tagging — orthogonal (`tag_metrics` path, untouched). Stays open. |
| #9939 / PR #9944 | closed/merged | source incident + the check that now depends on this path. |

## Research Reconciliation — Spec vs. Codebase

The issue is the spec here; its claims reconcile as follows:

| Issue claim | Codebase reality | Plan response |
|---|---|---|
| "`Failed to start` journald rows carry `SYSLOG_IDENTIFIER=systemd`, which no Vector source admits (Source 1 include_units allowlist, Source 2 PRIORITY 0-2 drops the err-level row, Source 4 exact-tag allowlist lacks `systemd`)" | True under the journalctl-AND mental model; **false under the actual evaluator** — Vector's `contains_match` is OR-over-fields, so Source 1's `include_matches.PRIORITY = ["0".."4"]` arm admits the PRIORITY-3 rows regardless of unit or identifier | Document the real semantics in vector.toml (AC1); the "unexplained" framing is resolved, not re-litigated |
| "a mechanism this file does not explain" | The mechanism is the file's own `include_matches.PRIORITY` — present since Source 1 was written, silently OR'd | Rewrite the comments; record in ADR-286 |
| "two evidence surfaces now depend on that unexplained delivery" | Verified: `inngest_failed_check` counts the rows; `betterstack-assert-absence.sh` is the named probe — but its `--control` proves sink liveness, not systemd-path transit | The field-scoped control (`--control-require`) + the capture's control-count arm |

## Problem Statement / Motivation

Two verification surfaces depend on a delivery path `vector.toml` claims does
not exist:

1. `inngest_failed_check` counts `Failed to start (inngest|vector|soleur-inngest)`
   rows as violations — if delivery silently stops, every run reports
   `zero 'Failed to start' journal rows` **vacuously green**.
2. `betterstack-assert-absence.sh --absence 'Failed to start inngest-luks'` —
   its `--control` proves the *sink* is alive, not that *systemd-tagged* rows
   transit (a `SOLEUR_PROBE_CANARY` row rides Source 4, a different arm on a
   different host's probe).

Meanwhile `vector.toml`'s Source 1/2 comments assert AND-style filtering
("INFO+DEBUG drop at source"; Source 2 "drops the err-level row") that Vector
does not implement — the next engineer reading the file will again fail to
explain the storm rows.

## Proposed Solution

1. **Document the real semantics in `vector.toml`** (the "pin" the issue asks
   for): rewrite the Source 1/2 header comments to state the OR-over-record-
   fields admission, the client-side filtering (`journalctl` is spawned with no
   match args — verified against `src/sources/journald.rs` @ v0.43.1), the
   PRIORITY≤4 arm that carries `SYSLOG_IDENTIFIER=systemd` rows, the PRIORITY≤2
   Source-1↔Source-2 double-admission, and the `systemd`-never-in-Source-4
   trap. Cross-link #9963/#6551/#8875.
2. **Emit `SOLEUR_SYSTEMD_JOURNALD_CONTROL`** once per
   `inngest-server-probe.timer` fire (hourly) inside the probe script heredoc
   in `inngest-bootstrap.sh`, placed **immediately after** the unconditional
   `SOLEUR_INNGEST_SERVER_PROBE` emit (:1211, "NO `if` may precede this line"
   — the control emit must be equally unconditional):
   `/usr/bin/logger -t systemd -p err "SOLEUR_SYSTEMD_JOURNALD_CONTROL ts=$(date -u +%s) — rides the inngest_journald PRIORITY≤4 admission arm (#9963)"`.
   Journald stamps `host` itself; the marker + ts suffice. The spoofed tag is
   deliberate and load-bearing: consumers discriminate real failure rows by
   `"SYSLOG_IDENTIFIER":"systemd"`, so the control must prove THAT field shape
   transits (a different tag would prove a different arm). `_COMM=logger`,
   `_TRANSPORT=syslog`, and the marker keep it trivially distinguishable from
   PID-1 rows. Precedent shape: `/usr/bin/logger -t <tag> -p err` is exactly
   the `inngest-heartbeat-failure-log.service` emit (inngest-bootstrap.sh:482).
3. **`--control-require` on `betterstack-assert-absence.sh`** — repeatable,
   AND'd onto the control predicate, byte-mirroring `--absence-require`. The
   systemd-path recipe becomes `--control 'SOLEUR_SYSTEMD_JOURNALD_CONTROL'
   --control-require-field 'SYSLOG_IDENTIFIER=systemd'`: a doppler-tagged webhook
   row quoting the marker text (the measured contamination class) cannot
   satisfy it, and neither can a future transform that drops the field.
4. **Rehearsal-capture control arm** — count `HOST_ROWS` rows carrying the
   marker AND `SYSLOG_IDENTIFIER.{0,8}systemd` (same two-stage grep shape as
   `count_inngest_failed`); zero → `want` (TRANSIENT, keep polling) instead of
   a `ok "zero 'Failed to start' journal rows"` on an unproven channel.
5. **Pins** — `journald-config.test.sh` emission-anchored arms (emit exists,
   `-t systemd`, `-p err`, inside PROBESCRIPTEOF, never-doppler-gated);
   `vector-pii-scrub.test.sh` documented PRIORITY-arm exemption registry entry
   for tag `systemd` (the literal `logger -t systemd` is derivable by AC3 but
   must NOT enter the Source-4 allowlist) + a `systemd`-absent-from-allowlist
   pin + a Source-1 PRIORITY-arm drift pin (the arm the control rides).
6. **Decision record** — new ADR (provisional ADR-286): the OR-over-fields
   semantics as recorded architecture, the path-scoped-control convention
   (bind an admission arm + a discriminator field, not a source name), and the
   explicit deferral of semantic re-architecture to #6551/#8875.

## Files to Edit

- `apps/web-platform/infra/vector.toml` — Source 1/2 header comment rewrite
  (OR semantics, admission arms, duplicates, never-Source-4 trap, refs).
- `apps/web-platform/infra/inngest-bootstrap.sh` — control emit inside the
  `PROBESCRIPTEOF` heredoc (~:1211) + comment naming the arm and #9963.
- `apps/web-platform/infra/journald-config.test.sh` — new arms pinning the
  control emit/tag/priority/placement and `systemd`-not-in-Source-4.
- `apps/web-platform/test/infra/vector-pii-scrub.test.sh` — PRIORITY-arm
  exemption registry + `systemd` entry + Source-1 PRIORITY-arm drift pin.
- `.github/workflows/workspaces-luks-verify.yml` — comment correction at :491:
  "SYSLOG_IDENTIFIER=systemd, which Vector does not ship" is false under the
  actual semantics (PRIORITY≤4 systemd rows ship via Source 1's arm); point at
  the pinned mechanism.
- `scripts/betterstack-assert-absence.sh` — `--control-require` flag (usage,
  parse, predicate composition), recipe note in the usage text.
- `scripts/betterstack-assert-absence.test.sh` — arms for `--control-require`
  (field-scoped control satisfied / marker-only unsatisfied / flag absent).
- `scripts/followthroughs/inngest-provision-rehearsal-capture.sh` —
  `systemd_path_control` count + arm beside `inngest_failed_check`.
- `scripts/followthroughs/inngest-provision-rehearsal-capture.test.sh` —
  fixtures: control present / absent / marker-on-doppler-tag contaminated.

## Files to Create

- `knowledge-base/engineering/architecture/decisions/ADR-286-<slug>.md` —
  provisional ordinal (next free after ADR-285 at plan time; re-verify at ship).

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` bodies contain none of
the eight file paths above (checked 2026-10-12).

## Technical Considerations

- **Marker contamination (ADR-192 I-2).** The literal marker string will exist
  in this repo's scripts/tests/issues, and inngest ships webhook-payload rows
  quoting repo text under `SYSLOG_IDENTIFIER=doppler`. A marker-substring
  control read is forgeable by that class — measured: issue #9939's own title
  produced 10 false matches. Field-scoping the control
  (`"SYSLOG_IDENTIFIER":"systemd"`) is the anti-contamination discriminator,
  not decoration.
- **Quota.** ~24 rows/day on the inngest host (+ ~24/day on each web host that
  renders the probe) — inside the ~20% headroom under 25k/day the Source-4
  comment documents.
- **Duplicates.** This plan documents but does not fix the PRIORITY≤2
  Source-1↔Source-2 and PRIORITY≤4 Source-1↔Source-4 double-admission; counted
  in the quota arithmetic only (~small). Fix belongs to #6551.
- **Deploy staging.** `vector.toml` comment changes move the
  `journald_persistent` hash → web-1 gets a real re-delivery + `vector
  validate` + reload on the next apply (this is also the exercised reload the
  #7539 paragraph exists for — do NOT delete that paragraph). The control emit
  inside `inngest-server-probe.sh` reaches the dedicated host only via
  `apply_target=inngest-host-replace`; until then systemd-path absence reads on
  `soleur-inngest-prd` report `unshipping` — the correct conservative outcome.
- **Alert hygiene.** Verified `betterstack-logs-alerts.tf`: no alert selects
  `SYSLOG_IDENTIFIER='systemd'` or counts PRIORITY=3 rows generically; the
  control cannot page a real-failure alert (its text carries no
  `Failed to start` and no unit name).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — the
  blast radius is an operator verification surface reporting a misleading
  verdict on internal telemetry (a vacuous absence read as clean, or a
  false `unshipping` training operators to ignore the check).
- **If this leaks, the user's [data / workflow / money] is exposed via:** no
  user-data path — control rows are synthetic ops telemetry (host, timestamp,
  marker) with no payload; the pii_scrub chain already guards the sink.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** infra-internal observability
  machinery; the worst outcome is a wrong verdict in an operator-facing
  assertion, not a user-facing defect or data exposure.

*Scope-out override:* `threshold: none, reason: the diff is confined to
observability plumbing (vector config comments, a logger emit, read-side
assertion scripts and their tests) — no user-facing surface, no user data, no
credential flow is modified; the doppler credential is only referenced by the
existing ExecStart the emit is placed beside.`

## Observability

The deliverable IS an observability control; the section describes its own
liveness chain.

```yaml
liveness_signal:
  what: SOLEUR_SYSTEMD_JOURNALD_CONTROL journald rows (marker + SYSLOG_IDENTIFIER=systemd + PRIORITY=3) transiting journald → Vector Source 1 PRIORITY arm → sinks.betterstack
  cadence: hourly (inngest-server-probe.timer OnUnitActiveSec=1h, OnBootSec=90s)
  alert_target: consumers fail closed — betterstack-assert-absence.sh exits 2 (unshipping); inngest-provision-rehearsal-capture.sh reports TRANSIENT rather than a green zero-count
  configured_in: apps/web-platform/infra/inngest-bootstrap.sh (PROBESCRIPTEOF emit); consumption in scripts/betterstack-assert-absence.sh + scripts/followthroughs/inngest-provision-rehearsal-capture.sh

error_reporting:
  destination: Better Stack Logs source 2457081 (the channel under test); verdicts surface in the calling runbook/workflow output
  fail_loud: SOLEUR_ABSENCE_ASSERT outcome=unshipping / outcome=unknown verdict lines; capture TRANSIENT sentinel INNGEST_PROVISION_CAPTURE_VERDICT=2

failure_modes:
  - mode: control emit removed/renamed or its tag/priority drifts
    detection: journald-config.test.sh emission-anchored pins go RED at CI; live windows report unshipping
    alert_route: PR check failure / assertion verdict in the consuming probe
  - mode: Source 1 PRIORITY arm narrowed below PRIORITY 3 (or Vector match semantics change on a version bump)
    detection: Source-1 drift pin in vector-pii-scrub.test.sh RED at CI; live control rows stop → unshipping
    alert_route: PR check failure / unshipping verdict
  - mode: "systemd" added to a Source-4-style exact-tag allowlist (the tempting fix)
    detection: explicit never-add pin + AC3 exemption-registry disjointness RED
    alert_route: PR check failure
  - mode: marker-quoting contamination (doppler/webhook rows embedding the marker text)
    detection: control reads require '"SYSLOG_IDENTIFIER":"systemd"'; contaminated rows cannot satisfy
    alert_route: not applicable — rejected by construction
  - mode: dedicated host not yet re-provisioned after merge (delivery staging gap)
    detection: control rows absent on soleur-inngest-prd until inngest-host-replace → unshipping
    alert_route: documented interim state; correct conservative verdict

logs:
  where: journald (source) → Better Stack Logs source 2457081, raw JSON rows
  retention: Better Stack source retention (existing)

discoverability_test:
  command: grep -l SOLEUR_SYSTEMD_JOURNALD_CONTROL apps/web-platform/infra/inngest-bootstrap.sh
  expected_output: apps/web-platform/infra/inngest-bootstrap.sh
```

## Infrastructure (IaC)

### Terraform changes

None — no new resources, providers, or variables. The delivery rides two
existing IaC paths:

- `apps/web-platform/infra/server.tf` `terraform_data.journald_persistent`
  (:1321-1365) hashes `journald-soleur.conf` + `vector.toml`; the comment edit
  moves the hash → a `terraform_data` replace is planned on the next
  `apply-web-platform-infra` run → `file()` staging +
  remote-exec re-render/validate/reload on web-1 (:1399-1436). This is the
  sanctioned vector.toml delivery path for web-1 — no operator step.
- `apps/web-platform/infra/inngest-bootstrap.sh` + `vector.toml` reach the
  dedicated inngest host only through `apply_target=inngest-host-replace`
  (server.tf:1066 comment; inngest-host.tf user_data ForceNew) — the next
  dispatched maintenance replace, NOT merge-apply. No new provisioner is
  introduced for this chore (P3): until then systemd-scoped absence reads on
  `soleur-inngest-prd` correctly report `unshipping`.

### Apply path

(b) existing dispatch paths only: merge-apply for web-1 (automatic via the
hash-triggered `terraform_data` replace); `inngest-host-replace` maintenance
dispatch for the dedicated host (operator-scheduled, out of this PR's trigger).
Expected blast radius: one `vector.service` reload on web-1; the inngest host
sees the emit at its next replace (same blast radius as every bootstrap
change — a planned host recreation).

### Host fan-out

`terraform_data.journald_persistent` remote-exec targets web-1 only (its own
comment at inngest-bootstrap.sh:1959 notes it does not target the inngest
host). `inngest-server-probe.timer` renders on the dedicated inngest host and
on any web host running the shared renderer's probe unit — the control emit
follows the probe, so coverage is per-probe-host by construction.

### Distinctness / drift safeguards

No dev/prd divergence vector (Vector runs on prd hosts only). No
`ignore_changes` interaction: web-1's user_data is ignored by design, which is
exactly why `journald_persistent` exists — documented in-file.

### Vendor-tier reality check

~24-48 added rows/day total vs the ~20% headroom under Better Stack's
25k/day row budget the Source-4 comment records. No new vendor surface.

## Guard Contract

### Guard 1 — systemd-path positive-control pipeline

**Property.** A row carrying marker + `SYSLOG_IDENTIFIER=systemd` + PRIORITY 3
transits the `inngest_journald` PRIORITY≤4 admission arm into `sinks.betterstack`
on a bounded cadence, so the discriminated delivery path is provably alive
independent of real unit failures.

**Assembly.** The single emission chokepoint is the `PROBESCRIPTEOF` heredoc in
`apps/web-platform/infra/inngest-bootstrap.sh` (the only place
`SOLEUR_SYSTEMD_JOURNALD_CONTROL` may be emitted); the admission chokepoint is
the `[sources.inngest_journald]` block in `vector.toml` (its
`include_matches.PRIORITY` set is the arm the control rides); the derivation
chokepoint is the AC3 `logger -t` tag-set census in
`vector-pii-scrub.test.sh` (every literal `logger -t` in infra is enumerated —
a new tag must either join the allowlist or the exemption registry); the
never-add chokepoint is the Source-4 `include_matches.SYSLOG_IDENTIFIER` list.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the `logger -t systemd -p err` emit line from the heredoc | RED — the emission-anchored pin (emit exists, not bare token) fails; live windows go `unshipping` |
| 2 | Change `-p err` to `-p notice` (PRIORITY 3→5) | RED — the priority pin fails AND the row leaves the admission arm (PRIORITY 5 ∉ {0..4}) → live `unshipping` |
| 3 | Change `-t systemd` to `-t soleur-sys-path` | RED — the tag pin fails AND `--control-require-field 'SYSLOG_IDENTIFIER=systemd'` can never be satisfied → `unshipping` |
| 4 | Add `"systemd"` to the Source-4 `include_matches.SYSLOG_IDENTIFIER` allowlist | RED — the explicit never-add pin + the exemption-registry disjointness arm both fire |
| 5 | Narrow Source 1 `include_matches.PRIORITY` to `["0","1","2"]` | RED — the Source-1 arm drift pin fails; the PRIORITY-3 control leaves the arm → live `unshipping` |
| 6 | Add a SECOND literal `logger -t newtag` inside the probe script without an allowlist or exemption entry | RED — AC3's derivation census finds a tag with no disposition (second member after a compliant first) |
| 7 | Harness: feed a doppler-tagged row quoting `SOLEUR_SYSTEMD_JOURNALD_CONTROL` verbatim (webhook contamination shape) | must-RED — the systemd-field-scoped control read must reject it; if marker-substring alone satisfies, the harness is vacuous |
| 8 | Harness: feed a row with the marker, systemd identifier, and DIFFERENT message text/host | must-PASS — field-scoped, not payload-scoped; certifies the read is not glued to a canonical row |

**Anchor.** The control's presence in Better Stack is out-of-repo evidence no
single commit can fabricate; the pins live in registered suites with their own
vacuity floors, so weakening requires editing emitter + pin + floor in one
reviewed diff.

### Guard 2 — consumers cannot verdict on an unproven systemd path

**Property.** No absence or zero-count verdict on `SYSLOG_IDENTIFIER=systemd`
journald rows reports `clean`/`ok` when the discriminated path is not proven by
a field-scoped control row in the read window.

**Assembly.** `betterstack-assert-absence.sh`: the `run_count` control read
(:224-231), the new `--control-require` composition, and the
`unshipping`/`unknown` verdict arms. `inngest-provision-rehearsal-capture.sh`:
`count_inngest_failed` (:299-321) + `inngest_failed_check` (:323-329) + the new
control-count arm and the `want`/`viol`/`ok` verdict helpers.
Documented-recipe surface: the script's usage text and this plan's recipe.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Parse `--control-require` but never AND it into the control predicate | RED — a test arm feeding marker-only rows must report `unshipping`; silent no-op flag is the defect |
| 2 | Reorder the capture's verdict so the failed-count arm prints `ok` before the control-count arm evaluates | RED — a `want`/`TRANSIENT` on a dark path must dominate `ok`; verdict-order pin |
| 3 | Let the control predicate accept a marker-only row (drop the require from the documented recipe AND the composition) | RED — contaminated-row harness arm |
| 4 | `betterstack-assert-absence.sh` exits 0 when control_rows = 0 | RED — the unshipping dispatch itself is pinned (a "0 checked → clean" shape is the vacuity class) |
| 5 | Count control rows marker-substring-only in the capture (no systemd-identifier second stage) | RED — a doppler-tagged fixture row carrying the marker must not satisfy the count |
| 6 | must-PASS: control row whose message field differs from the canonical string but carries marker + systemd identifier | must-PASS — proves the binding is to the discriminator, not a golden row |

**Anchor.** The verdict vocabulary (`clean`/`unshipping`/`unknown`,
`ok`/`want`/`viol`) is the externally observable contract; the test stubs
dispatch on SQL shape, so predicate weakening is visible to the harness, not
just to code review.

## Architecture Decision (ADR/C4)

### ADR

Create **ADR-286** (provisional — re-verify next-free at ship): "Vector
journald `include_*`/`exclude_*` semantics are OR-over-record-fields —
delivery-path documentation and path-scoped positive controls". Records: the
`filter_matches`/`contains_match` mechanism with the version pin; why the
systemd-tag path is admitted-by-design rather than a rogue shipper; the
control convention (bind an admission arm + discriminator field);
deferral of semantic re-architecture to #6551/#8875.

### C4 views

No `.c4` edit — enumeration per the completeness mandate: (a) external human
actors — none added (control rows are machine-emitted); (b) external
systems/vendors — Better Stack is already the modeled external system
(`model.c4:458 betterstack = system "Better Stack"`); (c)
containers/data-stores — the `inngest -> betterstack` and
`hetzner -> betterstack` "Ships journald + host_metrics via Vector" edges
(model.c4:735-736) already model this exact edge and already name host_metrics
caveats; (d) access relationships — unchanged (the control rides the existing
edge). A row-level control convention is below container granularity.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "identify what actually ships `SYSLOG_IDENTIFIER=systemd` rows from the host to Better Stack (journald Vector source default tagging? host_metrics? an unnamed journalctl shipper?)" | Research Insights §mechanism (identified: Source-1 PRIORITY≤4 arm under Vector's OR-over-fields `contains_match`; sink `sinks.betterstack`→2457081) + vector.toml doc rewrite + ADR-286 | mapped |
| 2 | "document it in vector.toml" | Files-to-Edit: `apps/web-platform/infra/vector.toml` (Source 1/2 comment rewrite) | mapped |
| 3 | "add a positive control row type so the absence assertions can't go vacuous if the path dies" | `SOLEUR_SYSTEMD_JOURNALD_CONTROL` emit (inngest-bootstrap.sh) + `--control-require` (betterstack-assert-absence.sh) + capture control arm + test pins | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| vector.toml Source 1/2 comment rewrite | "document it in vector.toml" | asked |
| `SOLEUR_SYSTEMD_JOURNALD_CONTROL` emit in `inngest-server-probe.sh` | "add a positive control row type" | asked |
| `--control-require` on betterstack-assert-absence.sh | "so the absence assertions can't go vacuous if the path dies" | inferred — justification: a marker-substring control is satisfiable by measured webhook/issue-body contamination (10 false matches on #9939's title); the field-scoped require is the only form that binds the systemd path specifically (ADR-192 I-2) |
| capture `systemd_path_control` arm | "counts `Failed to start inngest-luks` rows as a violation — if delivery silently stops, it reports … vacuously" | asked (consumer #1 named in the issue) |
| journald-config/vector-pii-scrub test pins | "pin the unexplained … path" | inferred — justification: "pin" is the title's word; a doc-only pin rots on the next edit — the drift-guard suites are the repo's enforcement convention (R3-4.5 precedent) |
| ADR-286 | — | inferred — justification: Phase-2.10 gate; the OR-semantics discovery contradicts what a reader of vector.toml would believe and three open issues hinge on it; recorded architecture must not lag the finding |

### Split Assessment

- Subsystems touched: 4 — `apps/web-platform`, `scripts`, `knowledge-base`, `.github`
- Planned files: 10 | Estimated changed lines: ~460
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR (root-count threshold met only because `.github/workflows/workspaces-luks-verify.yml` is a one-line comment correction riding the same doc sweep — splitting it would isolate nothing behavioral; no functional surface is touched outside `apps/web-platform` and `scripts`)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/observability
machinery change. Mechanical UI-surface scan: no Files-to-Create/Edit path
matches the ui-surface term list or `components/**` / `app/**/page|layout.tsx`
globs → Product/UX Gate not triggered.

## Acceptance Criteria

- [x] **AC1** `vector.toml` Source 1 and Source 2 header comments state the
  actual admission semantics — OR-over-record-fields client-side filtering
  with the `journald` source spawning `journalctl` unfiltered, verified against
  Vector `0.43.1` `src/sources/journald.rs` (`merge_units`, `contains_match`,
  `filter_matches`) — and name the `SYSLOG_IDENTIFIER=systemd` path (Source-1
  `include_matches.PRIORITY` arm → `sinks.betterstack` → source 2457081). The
  stale claims ("INFO+DEBUG … drop at source"; the implied Source-2 err-drop)
  are corrected; the #6551/#8875 links are present.
- [x] **AC2** `inngest-server-probe.sh` (inside the `PROBESCRIPTEOF` heredoc in
  `inngest-bootstrap.sh`) emits
  `logger -t systemd -p err "SOLEUR_SYSTEMD_JOURNALD_CONTROL …"` once per probe
  run (hourly), unconditionally and outside any credential-gated block.
- [x] **AC3** `systemd` is added to NO `include_matches.SYSLOG_IDENTIFIER`
  allowlist anywhere in `vector.toml`; a pin asserts it and fails on violation.
- [x] **AC4** `betterstack-assert-absence.sh` accepts repeatable
  `--control-require <substring>` AND'd onto the control predicate; its usage
  text documents the systemd-path recipe
  (`--control 'SOLEUR_SYSTEMD_JOURNALD_CONTROL' --control-require-field 'SYSLOG_IDENTIFIER=systemd'`).
- [x] **AC5** The rehearsal capture's `inngest_failed_check` neighbour arm
  reports `want`/TRANSIENT (never `ok`) when the row set lacks a marker +
  `SYSLOG_IDENTIFIER=systemd` control row, and a doppler-tagged row quoting the
  marker does not satisfy the count.
- [x] **AC6** The Guard-Contract mutation rows are exercised: each RED row
  (emit deleted, `-p` drift, `-t` drift, `systemd`-in-allowlist, PRIORITY-arm
  narrowed, second unregistered tag, contaminated-marker, no-require) produces
  a test failure; each must-PASS row passes.
- [x] **AC7** ADR-286 (or the ship-time next-free ordinal) exists in
  `knowledge-base/engineering/architecture/decisions/` recording the
  OR-over-fields mechanism, the control convention, and the #6551/#8875
  deferral; status `adopting`.
- [x] **AC8** `bash -n` passes on every edited `.sh`; suites
  `scripts/betterstack-assert-absence`,
  `scripts/followthroughs/inngest-provision-rehearsal-capture`,
  `apps/web-platform/infra/journald-config`,
  `apps/web-platform/test/infra/vector-pii-scrub` are green; no `<<< 'literal'`
  here-strings added to any `.test.sh`.
- [x] **AC9** The PR body and/or plan record the delivery staging explicitly:
  vector.toml reaches web-1 via `journald_persistent` on next apply; the
  inngest host emits the control only after the next
  `apply_target=inngest-host-replace` dispatch; interim `unshipping` on
  `soleur-inngest-prd` is the correct conservative verdict.

## Test Scenarios

- Given a row at PRIORITY 3 with `SYSLOG_IDENTIFIER=systemd`, when Vector's
  `contains_match` evaluates it against Source 1, then it is admitted by the
  PRIORITY arm (documented mechanism — pinned by the comment + arm drift pin).
  *(unit — comment/pin fidelity)*
- Given the control emit in the probe script, when journald-config.test.sh
  runs, then it asserts the emit line, `-t systemd`, `-p err`, and placement
  inside PROBESCRIPTEOF. *(unit)*
- Given a doppler-tagged raw row quoting `SOLEUR_SYSTEMD_JOURNALD_CONTROL`,
  when the control count evaluates it, then it is rejected by the
  systemd-identifier second stage. *(unit — regression for the #9939-title
  contamination class)*
- Given `--control-require` absent vs present, when the control read composes,
  then absent preserves legacy behaviour and present ANDs every require term.
  *(unit)*
- Given `control_rows=0` under a stubbed transport, when
  betterstack-assert-absence runs, then outcome is `unshipping`, exit 2.
  *(unit — existing arm kept green)*
- Given HOST_ROWS with control absent vs present, when the capture runs
  `inngest_failed_check` mode, then absent → `want`/TRANSIENT, present → the
  failed-count verdict applies normally. *(unit)*
- Given a `logger -t newtag` added to the probe script with no allowlist or
  exemption entry, when the AC3 census runs, then the tag-set mismatch fails.
  *(unit — second-member row)*
- Integration (live, post-replace): on `soleur-inngest-prd`,
  `betterstack-assert-absence.sh --host soleur-inngest-prd --absence 'Failed to start inngest-luks' --absence-require '"SYSLOG_IDENTIFIER":"systemd"' --absence-require '"host":"soleur-inngest"' --control 'SOLEUR_SYSTEMD_JOURNALD_CONTROL' --control-require-field 'SYSLOG_IDENTIFIER=systemd' --since 6h`
  exits 0 (`clean`) with `control_rows>=1`. *(integration — requires the
  inngest-host-replace staging; interim verdict is `unshipping`)*

## Non-Goals

- Re-architecting Vector source admission to journalctl-AND semantics (#6551).
- Migrating readers to emitter-based selection (#8875).
- The object-shaped message decoder (#8698) and host_metrics tagging (#6944).
- Deduplicating PRIORITY-overlapping sources (documented, not fixed).
- Any new Better Stack alert on the control row (cut — consumers are the
  alerting surface).

## Working Constraints (carried from the queue)

- `<<< 'literal'` here-strings are **banned inside `*.test.sh`** while the
  guard-vacuity-floor `heredoc_lines_of` phantom-opener defect is unfixed —
  bind feeds to variables first (e.g. `feed='…'; printf '%s' "$feed" | grep`).
- Floors never route through the assertion helpers they backstop (the
  pass/fail counters; use `printf >&2` + `exit 1` directly).
- Merge conflicts are resolved by merging `origin/main`, never by rebasing.

## Deepen Pass — 2026-10-12

**Mode disclosure:** this harness exposes no Task/Agent spawn, so the
deepen-plan fan-outs (per-section research agents, learnings sub-agents,
review panel) could not be spawned. All gate checks, the verify-the-negative
sweep, and the precedent diff ran in-process against the repo. The residual —
no independent adversarial seats — is recorded in
`specs/<branch>/decision-challenges.md`; `soleur:plan-review` may be re-run on
this file if the pipeline wants a panel pass.

**Gate results:**

| Gate | Verdict | Note |
|---|---|---|
| 4.5 network-outage | skip | zero trigger-pattern matches in plan body; the plan drives no new `terraform apply` SSH-provisioned resource (delivery rides the existing `journald_persistent` path) |
| 4.55 downtime & cutover | pass | the plan introduces NO replace/reboot — `inngest-host-replace` is the standing scheduled path every bootstrap change already rides; the web-1 `vector.service` reload is a telemetry-shipper restart, not a user-serving surface |
| 4.6 user-brand impact | pass | section present; `threshold: none` + required scope-out bullet (diff touches `apps/*/infra/`, a sensitive-path regex match) |
| 4.7 observability | pass | all five fields populated; `discoverability_test.command` = `grep -l …` (allowlisted verb, sub-second, literal `expected_output` path string) |
| 4.8 PAT-shaped variables | pass | zero matches |
| 4.9 UI wireframe | skip | no UI-surface file in either Files list |
| 4.10 encryption posture | pass | no new persistent store or cross-component connection — the control rides the existing journald→Better Stack edge (model.c4:735-736); Files match no `.tf`/`.sql`/cloud-init/compose pattern |
| 4.11 guard contract | pass | `lint-guard-contract.py` green (2 entries); assemblies name chokepoints (PROBESCRIPTEOF emission site, the Source-1 block admission arm, the AC3 derivation census, the Source-4 allowlist), not member lists |
| 4.12 scope check | pass | 3 asks all `mapped`; 2 `inferred` provenance rows carry non-boilerplate justifications; `Recommendation:` present |

**Verify-the-negative sweep (4.45):**

| Negative claim in plan | Verification | Result |
|---|---|---|
| `systemd` is not in the Source-4 allowlist | read of `vector.toml:188-350` | confirms |
| probe emit is not credential-gated | `PROBEUNITEOF` — `ExecStart=/usr/local/bin/inngest-server-probe.sh`, `-`-prefixed EnvironmentFiles, no `doppler run` wrapper; emit at :1211 is behind bounded calls and commented "unconditional" | confirms |
| no Better Stack alert can be paged by the control row | `grep SYSLOG_IDENTIFIER` in `betterstack-logs-alerts.tf` — only `luks-monitor`/`ci-deploy`/`egress-gw-probe` selects; the one PRIORITY predicate is `='2'`; control is PRIORITY 3 with no `Failed to start` text | confirms |
| marker-contaminating rows exist today (the forgery class the `--control-require` defeats) | capture.sh:296-297 documents 10 measured false matches on #9939's title under `ident=doppler` | confirms — the require is load-bearing |
| journald itself cannot rate-drop the control | `journald-soleur.conf` sets only storage caps (no `RateLimit*` keys); defaults are ~1000 msg/30s per service — one extra line/hour is unreachable | confirms |
| systemd-emitted `Failed to start` rows are PRIORITY 3 | measured storm rows carry PRIORITY err + `UNIT=`/`JOB_RESULT=failed` (capture.sh:296) — consistent with Source-1's `["0".."4"]` arm | confirms |

**Precedent diff (4.4):** the emit shape `/usr/bin/logger -t <tag> -p err "…"`
is the established idiom — `inngest-heartbeat-failure-log.service`'s
`ExecStart` (inngest-bootstrap.sh:482) and the probe's own emit (:1211) use it
byte-for-byte. The only novel element is the `systemd` tag value (deliberate,
documented); no new pattern is introduced. Scheduled-work check: no new
recurring job — the control rides the existing `inngest-server-probe.timer`.

**Folded in from the sweep:** two stale "does not ship" consumer claims were
found and added to the doc-correction scope — `inngest-bootstrap.sh:465`
("un-shippable SYSLOG_IDENTIFIER=systemd 'Failed to start' row", written when
the path was believed absent; the #9939 storm proves otherwise) and
`.github/workflows/workspaces-luks-verify.yml:491` ("which Vector does not
ship"). The `inngest-heartbeat-failure-log.service` unit stays — its tagged
re-emit is belt-and-braces, not redundancy worth a removal decision in this PR.

## References

- Issue: #9963; surfaced by the #9939 review panel. Related: #6551, #8875,
  #8698, #6944, #9939, PR #9944, #7898.
- Vector journald source (pinned version): `src/sources/journald.rs` @
  `v0.43.1` — `Journalctl::make_command` (no match args), `merge_units`,
  `filter_matches`, `contains_match` (`record.iter().any`).
- `betterstack-logs-alerts.tf:492-496` (observed OR behaviour record),
  `vector.tf:13` (version pin), `server.tf:1321-1436` (web-1 delivery),
  `inngest-host.tf` + `server.tf:1066` (replace-only delivery),
  `inngest-bootstrap.sh:548-560,1211-1300` (probe unit/script),
  `journald-config.test.sh:491-534` (R3-4.5 lockstep precedent),
  `vector-pii-scrub.test.sh:422-529,667-684` (AC3 census + #7898 arm pin).
- ADR-192 (marker vs any-row controls; I-2 anti-forgery), ADR-159 (delivery is
  not activation), learnings `2026-07-18-betterstack-followthrough-probe-*`,
  `2026-07-18-web-1-…-vector-toml-has-no-running-host-delivery`.
