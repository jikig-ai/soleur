---
title: "fix: Inngest cutover / heartbeat / observability cleanup bundle (#6551–#6556)"
date: 2026-07-17
type: fix
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issues: [6552, 6553, 6555, 6556, 6551]
closes: [6552, 6553, 6555, 6556]
investigates: [6551]
unblocks: inngest-base-url-repoint (still-open; NOT closed by this PR)
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Phase 2.8 reviewed: this bundle provisions NO new infra (no server/secret/vendor/DNS/TF
resource/variable/root). All `systemctl`/ExecStart mentions in this plan DESCRIBE the EXISTING
on-host systemd FSM (the cutover-flip oneshot's controlled start, unit ExecStart render sites) —
not new manual operator provisioning. Changes are image-baked (inngest-bootstrap.sh + cloud-init
write_files + sudoers + workflow YAML + tests) and take effect on the dark host's next scheduled
force-replace/re-provision; no `terraform apply` is triggered. See the ## Infrastructure (IaC)
section for the apply path. -->

# 🐛 Inngest cutover / heartbeat / observability cleanup bundle

One cleanup PR that lands four descoped follow-ups (#6552, #6553, #6555, #6556) surfaced by the
#6536 Inngest-heartbeat fix, plus a **no-SSH investigation** of #6551. All five live in the
Inngest cutover / heartbeat / observability subsystem on the **dark, pre-cutover dedicated Inngest
host**, share files (`cutover-inngest.yml`, `inngest-bootstrap.sh`, `inngest-server-flip-guard.sh`,
`vector.toml`, `vector-pii-scrub.test.sh`), and together gate the still-open
**inngest-base-url-repoint** cutover work.

**Scope discipline:** #6552/#6553/#6555/#6556 are closed by this PR. #6551 is an investigation —
closed ONLY if a probe resolves to a definite defect with a shipped fix; otherwise it stays OPEN
with the measured conclusion recorded (it did NOT resolve — see Research Reconciliation).
inngest-base-url-repoint is an **unblocked-by dependency note**, not in scope.

## Enhancement Summary (deepen-plan)

**Deepened:** 2026-07-17. **Method:** 6-agent plan-review panel (DHH, Kieran, code-simplicity,
architecture-strategist, spec-flow-analyzer, cto — single-user-incident threshold) applied inline,
plus deepen-plan hard gates + realism sweeps.

### Key improvements folded in (mechanical, auto-applied)
1. **#6552 delete made UNCONDITIONAL** (spec-flow + architecture + Kieran converged) — the case-arm
   placement missed `aborted`/partial-arm/re-dispatch states where `op=arm`'s G4 URL persists.
2. **#6555 corrected to 6 sites incl. 2 STANDALONE unit files** (`inngest-cutover-flip.service:19`,
   `inngest-redis.service:23`) the first draft mislocated; + fail-closed non-empty check, dead-
   substitution cleanup, preserve-branch precondition, scoped-token backstop, "forward-guard" reframe.
3. **#6556 P2 alarm unit reshaped** — renamed `inngest-heartbeat-failure-log.service` (not `-alarm@`,
   which means "pages a human" here), non-templated, bootstrap heredoc, **bare `logger` with NO
   `doppler run` wrapper** (would hardcode `--project soleur`).
4. **#6553 hardened** — four prose sites (not three), cite the flushed-RESUME start (`:240`), add an
   FSM↔guard lockstep CI drift-guard + ADR class-invariant, fix ADR heading (`## Considered Options`).
5. **#6551 instrument spec corrected** — Source-section hash, NOT whole-file (the `@@HOST_NAME@@` sed
   makes a whole-file hash mismatch forever); stays gated + #6551 OPEN.

### Gates verified
User-Brand Impact (single-user incident) · Observability (5 fields, no-SSH discoverability) ·
no PAT-shaped vars · no UI surface (no `.pen` needed) · Downtime/Cutover NOT triggered (dark
non-serving host, no DB migration, no `hcloud_server` replace in this PR) · precedent-diff done
(`cron-egress-alarm@` → reshaped) · negative claims verified (tag reuse, redaction).

### Surfaced (operator visibility) → `decision-challenges.md`
Panel User-Challenges to the operator's stated direction (bundle-into-one-PR; CTO #6555 approach)
and Taste splits (#6551 instrument ship/drop; #6556 P1 minimal shape) — recorded, NOT silently
applied; `ship` renders them into the PR body + files an `action-required` issue.

## Overview

| # | P | Fix | Primary file |
|---|---|---|---|
| 6552 | P2 | `op=rollback` must DELETE `INNGEST_HEARTBEAT_URL` (inverse of `op=arm` G4) so a rolled-back dark host stops being a second pusher on the shared Better Stack monitor | `cutover-inngest.yml` |
| 6553 | P3→(likely higher) | Widen the flip-guard CODE allowlist `{armed,flipping,done}` → `{armed,flipping,flushed,done}`; amend ADR-100 | `inngest-server-flip-guard.sh` + ADR-100 |
| 6555 | P2 | Land `DOPPLER_PROJECT` in `/etc/default/inngest-server` at cloud-init so units drop `--project`; delete the ci-deploy + sudoers threading | `cloud-init-inngest.yml`, `inngest-bootstrap.sh`, both sudoers copies, `ci-deploy.sh` |
| 6556 | P2 | Part 1: extend the CI tag-drift guard beyond `infra/*.sh` (units, containers) + add the explicit-exclusion half. Part 2: add `OnFailure=` to `inngest-heartbeat.service`, honestly scoped | `vector-pii-scrub.test.sh`, `inngest-bootstrap.sh` |
| 6551 | P2 | INVESTIGATION only — run the 3 no-SSH probes, record findings, **leave OPEN** (recommended: ship a read-only `vector_config_*` probe instrument, gated on reviewer confirm) | `cat-deploy-state.sh` (recommended, gated) |

**Why one PR:** shared files + one common re-eval dependency (all gate inngest-base-url-repoint) +
they were carved out of #6536 together. Merging them separately would produce redundant CI churn on
the same test/vector surfaces and repeated review of the same subsystem.

## User-Brand Impact

- **If this lands broken, the user experiences:** the eventual dedicated-host cutover fails or
  silently regresses cron reliability — e.g. a widened guard that wrongly allows a start could
  double-fire prod crons (duplicate reminders/emails to the founder's users), or a botched
  rollback delete could leave the monitor false-green while co-located crons are actually down.
  Immediate blast radius is LOW today (the host is dark, no live traffic), but the failure class is
  single-user-incident when the cutover runs.
- **If this leaks, the user's data/workflow is exposed via:** no new data surface. The OnFailure
  log and the `vector_config_*` instrument carry no PII (a config hash + a unit-failure
  marker); `cat-deploy-state.sh` already redacts signing keys + heartbeat bearer URLs (#5159). No
  regulated-data field is added or shipped.
- **Brand-survival threshold:** single-user incident. Rationale: #6552 (monitor false-green masking
  a real co-located outage) and #6553 (a guard that on a strict reading blocks the cutover's own
  controlled start) are single-user-incident-class *when the cutover runs*; this subsystem already
  burned 3 days + a host replacement in #6536. CPO sign-off required; `user-impact-reviewer` runs
  at review time.

## Research Reconciliation — Spec vs. Codebase (measured, not paraphrased)

| Claim (issue body) | Reality (measured) | Plan response |
|---|---|---|
| #6552: `op=arm` writes `INNGEST_HEARTBEAT_URL` at G4 (~:760); `op=rollback` never deletes it | CONFIRMED. `op=arm` G4 writes it at `cutover-inngest.yml:760`; `op=rollback` (`:1095-1118`) writes `INNGEST_CUTOVER_FLIP=rollback` only — no `INNGEST_HEARTBEAT_URL` delete | Add the delete to `op=rollback` (inverse of G4) |
| #6553: guard allowlist `armed\|flipping\|done`; ADR-100 FSM is `armed→flipping→flushed→done`; `flushed` missing | CONFIRMED at `inngest-server-flip-guard.sh:40`. **Stronger finding:** the flip oneshot sets `flushed` (`inngest-cutover-flip.sh:188`) then runs `start_server` = `systemctl start inngest-server` (`:100,:189`) **while flag=`flushed`**, and `is_prod=true` during cutover → on a strict reading the ExecStartPre guard blocks the FSM's OWN controlled start, not just a restart-window edge | Widen the guard; treat as **possibly higher than P3** (see below) |
| #6553: ADR-100 deliberately excludes `flushed` | **REFUTED.** ADR-100:189 lists `{armed, flipping, done}` and NOWHERE justifies excluding `flushed`; its own FSM ordering (`:163,:172`) starts the server at `flushed`. A subagent paraphrase asserted "intentionally excluded" — not in the ADR text | Widen + amend ADR-100:189 (the omission is an oversight contradicted by ADR-100's own ordering) |
| #6555: `:47 export DOPPLER_PROJECT="${DOPPLER_PROJECT:-soleur}"`; units read env via `EnvironmentFile=`; CTO fix writes it into `/etc/default/inngest-server` and drops `--project` | CONFIRMED + refined: on the **dedicated host** the env-file is pre-created at `cloud-init-inngest.yml:324` (bootstrap hits the "preserve" branch and SKIPS the `:339` heredoc), so the fix must patch `cloud-init-inngest.yml:324` (dedicated) AND `inngest-bootstrap.sh:339` (web-host). Doppler CLI reads `DOPPLER_PROJECT` from env (precedent `cloud-init-registry.yml:734,741`); routing is also backstopped by a soleur-inngest-scoped `DOPPLER_TOKEN` (cloud-init-inngest.yml:384). The sudoers `env_keep` for `DOPPLER_PROJECT` is a **deliberate forward-guard** (ci-deploy.sh:2779-2784, H4 — "if a ci-deploy path is ever added to the DEDICATED host"), safe to delete today (ci-deploy is web-host-only) but NOT "dead weight". **2 of 6 `--project` sites are in STANDALONE unit files** (`inngest-cutover-flip.service:19`, `inngest-redis.service:23`) the first draft mislocated | CTO fix; enumerate all 6 `--project` sites (incl. 2 unit files) + dead-substitution cleanup + fail-closed check + both sudoers copies + ci-deploy + tests |
| #6556 P1: test derives EXPECTED_TAGS from `logger -t` + `SyslogIdentifier=` but scans only `infra/*.sh`, no exclusion half | CONFIRMED. `vector-pii-scrub.test.sh` AC3/AC3b scan `infra/*.sh` only; hardcodes `SYSTEMD_UNIT_IDENTIFIERS="webhook"`; no exclusion-with-reason list. Gaps: units with no `SyslogIdentifier=` (silent basename tags `sh`, `doppler`, `disk-monitor.sh`, `resource-monitor.sh`, `inngest-nftables.sh`, `zot-liveness-heartbeat.sh`), plus `luks-monitor.service` (only coincidentally covered via its `.sh`) | Extend coverage + add exclusion half (derive, don't hardcode) |
| #6556 P2: `inngest-heartbeat.service` has no `OnFailure=` | CONFIRMED (heredoc `inngest-bootstrap.sh:236-283`, no `OnFailure=`). Precedent exists: `cron-egress-alarm@%n.service` (`cron-egress-firewall.service:8`) | Add `OnFailure=` templated alarm unit; reuse `inngest-heartbeat` tag |
| #6551 probe 3: "surface a hash via `cat-deploy-state.sh`" | **INFEASIBLE as written** — `cat-deploy-state.sh` surfaces vector.service *status* + *journal tail* (`:417-418`) but NEVER reads/hashes `/etc/vector/vector.toml` | Probe 3 needs a new field; recommend adding a read-only `vector_config_*` (gated); #6551 stays OPEN |

### #6551 — the three no-SSH probes, run and dispositioned (#6536-compliant)

The measured live row: `PRIORITY=3 SYSLOG_IDENTIFIER=systemd _SYSTEMD_UNIT=init.scope UNIT=inngest-heartbeat.service host_name=soleur-inngest-prd`. `vector.toml`'s own Source 4 header (`:127-131`) already flags this as unexplained ("a live row carries SYSLOG_IDENTIFIER=systemd, which NO source here admits; tracked separately").

- **Probe 1 — do `include_units`/`exclude_units` match PID-1's `UNIT=` or only `_SYSTEMD_UNIT=`?**
  RESOLVED (Vector journald semantics): they match `_SYSTEMD_UNIT` (the cgroup unit), NOT the
  `UNIT=` field systemd sets when logging *about* a unit. The row's `_SYSTEMD_UNIT=init.scope` →
  Source 1 `include_units=["inngest-server.service"]` does not match; Source 2
  `exclude_units=[…]` does not exclude `init.scope` (so it passes the exclude filter). Probe 1 does
  **not** open an admit path — it is consistent with the "NO source admits it" table.
- **Probe 2 — is `include_matches.PRIORITY` applied on Source 2, or silently ignored (the #4267
  bogus-`include_priorities` class)?** RESOLVED (repo read): the repo uses the CORRECT
  `include_matches.PRIORITY = ["0","1","2"]` form (valid current Vector syntax, `sd_journal_add_match`),
  NOT a deprecated/typo'd key. Under the repo config, Source 2 reads only PRIORITY 0-2 from the
  journal; a PRIORITY-3 row is never read → cannot ship. Probe 2 does not explain the row **under
  the repo config**.
- **Probe 3 — diff running vs repo vs image via a hash from `cat-deploy-state.sh`.** INFEASIBLE:
  the script has no field that reads/hashes the running `/etc/vector/vector.toml`.
- **Disposition (per `2026-07-16-refuting-a-hypothesis-by-reasoning-while-its-discriminator-is-invisible.md`):**
  under the repo config, NO source admits the row (matches the table). The row shipping therefore
  proves the **running config differs from the repo config** in a way that admits PRIORITY-3 /
  `init.scope` — but the deciding datum (the running `/etc/vector/vector.toml` on the deny-all-public
  dark host) is **invisible off-box**. The honest disposition is **UNKNOWN root cause; #6551 stays
  OPEN**. We do NOT mark any hypothesis CONFIRMED/REFUTED beyond what repo/docs evidence supports,
  and we do NOT force a speculative fix.
- **Recommended (GATED on plan-review/CPO confirm) — ship the probe instrument ALONE, CORRECTLY
  SPECCED:** add a read-only `vector_config_*` field to `cat-deploy-state.sh` (precedent:
  `seccomp_profile_host_sha256`, cat-deploy-state.sh:314-334, per Kieran). **A naive
  `sha256sum /etc/vector/vector.toml` is WRONG and can NEVER match (CTO §1):** `inngest-bootstrap.sh:~708`
  runs `sed 's|@@HOST_NAME@@|soleur-inngest-prd|g'` over the installed file (vector.toml:380,395
  sentinels), so a whole-file hash ≠ the repo hash on every healthy host forever, AND worse it
  conflates the *expected* host_name render with the *actual* source-filter drift the mystery is
  about. Spec it to hash **only the canonical Source-definition section** (the `[sources.*]` stanzas,
  which the `@@HOST_NAME@@` substitution never touches) — that section IS the exact discriminator for
  whether the running config admits the PRIORITY-3/`init.scope` row — OR hash the repo file AFTER the
  same `@@HOST_NAME@@` render, and ship the field WITH its documented comparison procedure (against
  which ref, post-which substitution). Read-only, no-behavior-change, near-zero blast radius
  (architecture affirmed (e): this is "the right call"). **#6551 remains OPEN** (the instrument
  enables the future determination; it is not the root-cause fix; CTO §5 — it is also latent until
  the next dedicated-host bake, so it collects nothing until then). **Panel split → decision-challenge:**
  DHH argued to drop it from this cleanup bundle (scope-creep on an investigation-only issue);
  architecture affirmed it as sound and low-risk. Default: keep gated + corrected spec; if CPO/deepen
  prefer strict "no code for #6551", drop it and the #6551 issue update points to the corrected spec
  as the documented next step. M1 (spec-flow): the eventual inngest-base-url-repoint cutover runbook
  should gate on a running-vs-repo Source-section hash match — the cutover's own go/no-go gates ride
  this same Vector→Better Stack journald channel, so a drifted shipper is not proven to faithfully
  ship the `flag:done`/`rolled-back` lines those gates read.

## Implementation Phases

> **Phase order is load-bearing (contract-before-consumer):** for #6555, the env-file writes
> (`cloud-init-inngest.yml` + `inngest-bootstrap.sh` heredoc) MUST land in the same commit as the
> `--project` removals — an ExecStart that drops `--project` before `DOPPLER_PROJECT` is in the
> env-file would resolve the wrong project at runtime.

### Phase 0 — Preconditions (grep-verify, no code)
- Confirm the 6 `--project` render sites: `inngest-bootstrap.sh:283,523,585,737` (heredocs) +
  `inngest-cutover-flip.service:19` + `inngest-redis.service:23` (STANDALONE unit files). Confirm
  `inngest-redis-bootstrap.sh` has NO `--project` (only `${DOPPLER_PROJECT:-soleur}` at :82). Confirm
  all six read `EnvironmentFile=/etc/default/inngest-server`, and the scoped `DOPPLER_TOKEN` backstop
  (cloud-init-inngest.yml:384).
- Confirm both sudoers copies (`deploy-inngest-bootstrap.sudoers:27`, `cloud-init.yml:83`) and the
  AC5 content-only byte-parity assertion (`cloud-init-inngest-bootstrap.test.sh:143-179`).
- Locate the flip-guard test file and the heartbeat unit test (grep `GUARD_FLIP_FLAG`,
  `inngest-heartbeat` in `apps/web-platform/{test,infra}/*.test.sh` + `inngest.test.sh`).
- Enumerate `.service` + cloud-init `write_files` units for the #6556 P1 guard extension (see the
  gap table in Test Scenarios).

### Phase 1 — #6553 flip-guard widen (+ ADR-100 amend + FSM↔guard drift guard) [do first]
1. `inngest-server-flip-guard.sh:40` — `armed | flipping | flushed | done) flag_ok=true`.
2. Update the **FOUR** prose sites (Kieran P2-1) that name the allowlist to `{armed,flipping,flushed,done}`:
   comment `:12`, comment `:15-16` (`armed/flipping/done`), error `:44` (logger), error `:45` (stderr).
3. ADR-100:189 — amend the allowlist to `{armed, flipping, flushed, done}` and add one sentence:
   *the FSM's forward path starts the server at `flushed` (`:163,:172`; the flushed-RESUME arm at
   `inngest-cutover-flip.sh:240` also calls `start_server` while flag=`flushed`), and DBSIZE==0 is
   asserted (`inngest-cutover-flip.sh:178`) before `flushed` is set, so a start at `flushed` cannot
   double-fire against a dirty Redis — the guard must allow it.* Retarget the alternatives note to
   ADR-100's actual heading **`## Considered Options` (`:63`)** / the Decision 6a-6b prose (Kieran
   P2-3 — there is NO `## Alternatives Considered` heading). (ADR Gate deliverable.)
4. **FSM↔guard lockstep drift guard (architecture P2-5, CTO §3):** ADR-100 records the class rule —
   *the guard allowlist MUST equal the set of FSM states in which `start_server` is invoked.* Add a
   CI assertion (reuse the flip-guard test surface Phase 0 locates) that FAILS if the FSM `flag_set`s
   a state preceding a `start_server` call that the guard allowlist omits — so the next FSM state
   addition cannot silently re-introduce the self-block this issue fixes. This is the structural fix;
   AC2's grep-for-stale-string is only a point-in-time check.

### Phase 2 — #6552 rollback deletes INNGEST_HEARTBEAT_URL
1. `cutover-inngest.yml` `op=rollback` block — add an idempotent `doppler secrets delete
   INNGEST_HEARTBEAT_URL -p soleur-inngest -c prd` (inverse of G4 `:760`) via the
   `DOPPLER_TOKEN_INNGEST_ARM` token, no value echoed, absent-is-OK.
   **PLACEMENT IS LOAD-BEARING (plan-review P1, spec-flow H1/H2 + architecture P1-2): the delete
   MUST be UNCONDITIONAL — in the Half-B region that runs for EVERY entry state (after `esac`,
   ≥:1120), NOT inside the `armed|flipping|flushed|done)` reverse-flip case arm (which ends `;;` at
   :1114).** `op=arm` writes the URL at G4 (:760) BEFORE the FSM runs, so it is present in EVERY
   post-arm state — including `aborted`, the partial-arm case (G4 wrote the URL, then G5 `armed`
   failed → flag is a pre-arm value → the `*)` no-op arm), and the idempotent re-dispatch path
   (`rollback|rolled-back)` :1115, reached when a first dispatch times out at the 600s confirm and
   exits 1 BEFORE any delete). Nesting the delete in the forward-state arm strands the URL on all
   three → the exact two-pusher bug #6552 exists to close persists silently. Mirror the code's own
   stated principle at :1084 ("G1' decides ONLY whether to WRITE the reverse flip — it must NOT gate
   Half (B)") — the delete belongs with the unconditional web re-enable, idempotent + absent-OK.
   After delete, on any subsequent dark render the absent URL classifies as `url_present=no` (skip,
   exit 0) — one unambiguous pusher (co-located) per monitor (inngest-host.tf:137-171).
   Ordering note (architecture (c), affirmed): keep the delete AFTER the `rolled-back` confirm on
   the forward-state path so a `done`-state rollback does not blank the monitor while the dedicated
   scheduler is still live — but the delete itself is unconditional across states.

### Phase 3 — #6556 Part 2 OnFailure (event-driven; no quota decision)
Plan-review revised the unit shape on three converging findings — do NOT mirror `cron-egress-alarm@`
verbatim:
1. `inngest-bootstrap.sh` heartbeat `[Unit]` heredoc (`:236-241`) — add
   `OnFailure=inngest-heartbeat-failure-log.service`.
2. New **non-templated** oneshot `inngest-heartbeat-failure-log.service`, rendered as a **bootstrap
   heredoc** in `inngest-bootstrap.sh` (NOT a standalone tracked file):
   - **Name:** `-failure-log`, NOT `-alarm@` (CTO §2): in this repo `*-alarm@.service` means "pages a
     human" — `cron-egress-alarm.sh` genuinely emails (Resend) + Sentries. This unit is deliberately
     push-less; the `-alarm` name would train a future maintainer to assume paging it does not do.
   - **Non-templated** (code-simplicity B2): the `@`/`%i` template in `cron-egress-alarm@` is earned
     by TWO consumers needing `%i`; this has ONE consumer, so the failed-unit name is a constant.
   - **Bare `logger`, NO `doppler run` wrapper** (architecture P2-3): `cron-egress-alarm@`'s ExecStart
     wraps in `doppler run --project soleur …`; this unit only emits an ERR marker and needs no
     secrets — a `doppler run` wrapper would hardcode `--project soleur` (WRONG on the soleur-inngest
     host) and re-introduce the exact project-resolution surface #6555 removes. ExecStart is a direct
     `logger -t inngest-heartbeat -p err '<fixed message>'`.
   - `SyslogIdentifier=inngest-heartbeat` (reuse the existing Source 4 tag → queryable, **no new
     allowlist entry, no fresh quota decision**; `vector.toml:124`).
   - Header comment stating: **queryable, not alarming** on the dark host (deliberately no monitor
     push — one-pusher-per-monitor); the LIVE co-located pusher's real alarm is the Better Stack
     heartbeat *monitor* (missing pings). **Post-cutover semantics (CTO §2):** the unit is
     image-baked + permanent; after cutover the dedicated host BECOMES the live pusher, and
     queryable-only remains correct then (the Better Stack monitor's missing-pings alarm covers the
     now-live host; the log line stays the diagnostic) — so a future engineer must NOT "complete" it
     by adding a push.
   This makes the failure systemd currently emits as the un-shippable `SYSLOG_IDENTIFIER=systemd`
   "Failed to start" line (the #6551 row) shippable via the `inngest-heartbeat` channel instead.

### Phase 4 — #6556 Part 1 CI tag-drift guard extension
1. `vector-pii-scrub.test.sh` AC3/AC3b — extend the derivation to also enumerate: (a) `.service`
   files under `infra/`, (b) rendered unit heredocs inside `.sh`, (c) cloud-init `write_files` unit
   bodies. For each unit compute its **effective** `SYSLOG_IDENTIFIER` = its `SyslogIdentifier=` if
   present, else its ExecStart basename. Require each derived tag/identifier to be EITHER in the
   `vector.toml` Source 4 allowlist OR in a NEW documented **exclusion list with a reason**. Derive
   `webhook` from `webhook.service`'s basename (stop hardcoding it); keep a hardcoded set ONLY for
   identifiers no source line can yield. Failure message stays directional ("reconcile in the
   direction the emitter dictates" — remove the emitter or add the entry/exclusion; do NOT delete
   the emitter to silence). New OnFailure unit from Phase 3 must pass (reuses `inngest-heartbeat`).
2. Per-unit include/exclude triage (candidates — the *decision* per unit is #6556 substance and a
   quota decision; deepen-plan/CPO confirm): `sh`, `doppler` basenames → EXCLUDE (shared /
   non-diagnostic, or already covered by Source 1 `include_units` / Source 2 `exclude_units`);
   `disk-monitor.sh`, `resource-monitor.sh`, `inngest-nftables.sh`, `zot-liveness-heartbeat.sh` →
   EXCLUDE with reason (own Sentry/heartbeat path, or not on the inngest host). Adding any to the
   Source 4 allowlist is a fresh quota decision (Source 4 ~20% under 25k/day, vector.toml:120-138).

### Phase 5 — #6555 DOPPLER_PROJECT env-file (highest blast radius; atomic commit)
> **Safety backstop (architecture P2-1):** the dedicated host also carries a **soleur-inngest-scoped
> `DOPPLER_TOKEN`** in `/etc/default/inngest-server` (cloud-init-inngest.yml:384) — a scoped Doppler
> service token resolves the project even with no `--project` and no `DOPPLER_PROJECT`, so dropping
> `--project` is safe in principle. The env-file `DOPPLER_PROJECT` is belt; the scoped token is
> braces.

1. `cloud-init-inngest.yml:324` — add `DOPPLER_PROJECT=soleur-inngest` to the pre-create printf.
2. `inngest-bootstrap.sh:339-343` heredoc — add `DOPPLER_PROJECT=$DOPPLER_PROJECT` (web-host path).
3. Remove `--project …` from **all SIX** ExecStart/ExecStartPre sites; keep `--config prd`. The six
   (architecture P1-1 / Kieran P1-2 — TWO live in STANDALONE unit files the first draft mislocated):
   `inngest-bootstrap.sh:283` (heartbeat `${DOPPLER_PROJECT}`), `:523` (server `@@DOPPLER_PROJECT@@`),
   `:585` (server ExecStartPre flip-guard `${DOPPLER_PROJECT}`), `:737` (vector `@@DOPPLER_PROJECT@@`),
   **`inngest-cutover-flip.service:19`** (`@@DOPPLER_PROJECT@@`, standalone file), and
   **`inngest-redis.service:23`** (`@@DOPPLER_PROJECT@@`, standalone file). NOTE `inngest-redis-bootstrap.sh`
   contains NO `--project` (it only sets `redis_doppler_project="${DOPPLER_PROJECT:-soleur}"`); the
   first draft mis-attributed the redis site there. Preserve ALL `$DOPPLER_PROJECT` shell-var GATING
   logic (`:47` default, `:216/:391/:585` gates, DEDICATED_FLIP) — it drives *which arms render*, not
   the `--project` flag. All six units read `EnvironmentFile=/etc/default/inngest-server` (verified:
   `inngest-redis.service:18`, `inngest-cutover-flip.service:15`, + the three bootstrap heredocs).
3b. **Dead-substitution cleanup (architecture P2-4):** after `--project` removal the
   `@@DOPPLER_PROJECT@@` substitutions at `inngest-bootstrap.sh:592` (server), `:761` (vector), `:404`
   (flip render), and `inngest-redis-bootstrap.sh:84` become no-ops — remove them so a lingering
   `@@DOPPLER_PROJECT@@` mechanism cannot hide a re-introduction.
3c. **Fail-closed check (architecture P2-1 / spec-flow M2):** the fix creates TWO independent
   `DOPPLER_PROJECT` sources that must stay in lockstep — the render-time `env DOPPLER_PROJECT=`
   (cloud-init-inngest.yml:396, drives arm rendering, preserved) and the new runtime env-file line
   (`:324`). Add a bootstrap fail-closed check: `DOPPLER_PROJECT` present + non-empty in
   `/etc/default/inngest-server` before any unit start, since the `:47` default silently falls back
   to `soleur` (the wrong project). AC6 asserts non-empty presence, not mere presence.
4. Delete `DOPPLER_PROJECT` from env_keep in BOTH sudoers copies identically
   (`deploy-inngest-bootstrap.sudoers:27` + `cloud-init.yml:83` — AC5 byte-parity), and from
   `--preserve-env` at `ci-deploy.sh:2785` (+ update the `:2777-2784` comment). **Framing (Kieran
   P2-2): this is NOT "dead weight" — `ci-deploy.sh:2779-2784` documents it as a deliberate
   forward-guard (H4: "if a ci-deploy path is ever added to the DEDICATED host…"). Deletion is safe
   today (ci-deploy is web-host-only, `:47` default `soleur` is correct there) but frame it as
   removing a documented forward-guard, superseded by the env-file mechanism.**
5. Update pinning tests: `inngest.test.sh:130,134` (heartbeat), `:402` (server), `:593`
   (redis.service), a likely cutover-flip assertion, plus cutover-inngest-workflow.test.sh,
   cloud-init-inngest-bootstrap.test.sh.
6. **Preserve-branch precondition (architecture P2-2):** `inngest-bootstrap.sh:321` preserves an
   existing `/etc/default/inngest-server` with a valid `DOPPLER_TOKEN=dp.` and SKIPS the `:339`
   heredoc — so an in-place re-bootstrap over a pre-change env-file never adds the new line. The new
   line lands ONLY via a fresh-disk force-replace (cloud-init:324). Record as an explicit ordering
   precondition: no in-place re-bootstrap before the first force-replace.
7. **Residual honesty + SOLEUR-DEBT (CTO §4):** the render-time `:47` default trap is NOT removed by
   this fix (it still keys arm rendering off cloud-init's inline `env DOPPLER_PROJECT=`); its detector
   is `cat-deploy-state.sh`'s `HEARTBEAT_DARK_ARM` field (#6536). Add a one-line `SOLEUR-DEBT:` marker
   at `:47` pointing at that detector so the residual dual-sourcing is discoverable. Considered
   alternative (rejected — DHH/code-simplicity challenged it, CTO+architecture endorsed the CTO fix
   as the better long-term call because it eliminates the byte-parity sudoers tax + 6-site `--project`
   drift; recorded as a User-Challenge in decision-challenges.md): fail-closed the `:47` default only,
   leaving the threading.

### Phase 6 — #6551 investigation write-up (+ recommended gated instrument)
1. Record the probe findings (above) in the PR body and update issue #6551; leave it OPEN.
2. RECOMMENDED (gated): add read-only `vector_config_*` to `cat-deploy-state.sh`.

## Infrastructure (IaC)

### Terraform changes
None. No new TF resource, variable, root, server, secret, vendor, or DNS record. All changes are to
**image-baked artifacts** (systemd units rendered by `inngest-bootstrap.sh`, `cloud-init*.yml`
write_files, sudoers, workflow YAML, tests).

### Apply path
(b) cloud-init + idempotent bootstrap re-bake. The dedicated host is **dark/pre-cutover**. Changes
to `inngest-bootstrap.sh` / `cloud-init-inngest.yml` are baked into the
`soleur-inngest-bootstrap` OCI image and take effect on the next **dedicated-host force-replace /
re-provision** (part of the eventual cutover, or a dark-host re-provision) — no `terraform apply`
is triggered by this PR. `cutover-inngest.yml` (#6552) is a workflow change, live on merge to
default branch for the next `op=rollback` dispatch. Expected downtime/blast-radius: **zero live
impact** (dark host); the fixes are latent-until-provision and gate the eventual cutover.

### Distinctness / drift safeguards
`dev != prd`: N/A (infra host, not Supabase). The `$DOPPLER_PROJECT` gating that keeps the dedicated
(`soleur-inngest`) vs co-located (`soleur`) arms distinct is explicitly preserved. Sudoers
byte-parity is enforced by `cloud-init-inngest-bootstrap.test.sh` AC5.

### Vendor-tier reality check
Better Stack Logs Source 4 (source 2457081) is ~20% under 25k rows/day (vector.toml:120-138,
#5110). The #6556 P2 OnFailure is **event-driven** (fires only on failure), NOT timer-driven, and
reuses the `inngest-heartbeat` tag → no new allowlist entry and no fresh timer-driven quota
decision. Any #6556 P1 identifier promoted from exclusion → allowlist IS a fresh quota decision and
must be justified against the headroom.

## Observability

```yaml
liveness_signal:
  what: inngest-heartbeat.timer active-state + dark-arm render + (recommended) vector_config_* (Source-section hash)
  cadence: 60s timer; deploy-status read on demand (no ssh)
  alert_target: Better Stack heartbeat monitor (LIVE host) via missing pings; dark host is queryable-only
  configured_in: inngest-bootstrap.sh (units), cat-deploy-state.sh (no-ssh read surface)
error_reporting:
  destination: Better Stack Logs source 2457081 via Vector Source 4 (tag=inngest-heartbeat); systemd journal
  fail_loud: OnFailure alarm unit emits an ERR-priority inngest-heartbeat line on unit failure (was the un-shippable systemd "Failed to start" row)
failure_modes:
  - mode: rollback leaves INNGEST_HEARTBEAT_URL (two pushers)
    detection: cat-deploy-state.sh inngest_heartbeat_dark_arm + Better Stack monitor push-source count
    alert_route: op=rollback delete makes url absent -> dark arm url_present=no; one pusher restored
  - mode: heartbeat unit enters failed state (doppler/curl error, or #4116 empty-URL class)
    detection: OnFailure alarm -> logger -t inngest-heartbeat -p err -> Better Stack Logs (queryable); LIVE host also alarms via the monitor
    alert_route: Better Stack heartbeat monitor (live host); Logs query (dark host)
  - mode: running vector.toml drifts from repo (the #6551 mystery admit path)
    detection: (recommended, gated) vector_config_* Source-section hash in cat-deploy-state.sh vs repo Source-section hash
    alert_route: no-ssh deploy-status read post dedicated-host bake; #6551 stays open until read
  - mode: a new logger -t tag / unit SyslogIdentifier is invisible off-box (rides-the-shipper doctrine breach)
    detection: vector-pii-scrub.test.sh AC3/AC3b extended guard (CI, static)
    alert_route: CI fail -> add to allowlist or documented exclusion (fail-closed)
logs:
  where: Better Stack Logs source 2457081 (EU eu-fsn-3); host systemd journal (persistent, #4792)
  retention: Better Stack plan retention; journal bounded on-disk
discoverability_test:
  command: "curl -s <deploy.soleur.ai/hooks/deploy-status via CF Access> | jq '.services.inngest_heartbeat_dark_arm, .services.inngest_heartbeat_timer' (NO ssh)"
  expected_output: "dark host: inngest_heartbeat_dark_arm=\"rendered\", inngest_heartbeat_timer=\"active\""
```

Affected-surface note (blind execution surface — the deny-all-public dark host): every failure mode
above has an **in-surface** probe (OnFailure alarm line from the unit itself; dark-arm render read;
recommended config-hash) reachable via `cat-deploy-state.sh` over `/hooks/deploy-status`, never SSH
(`hr-no-ssh-fallback-in-runbooks`). The `vector_config_*` instrument is the discriminating
field for the host-config-vs-repo-vs-image hypothesis split (#6551).

## Architecture Decision (ADR/C4)

### ADR
Amend **ADR-100** (single amendment covering the bundle's ADR-touching changes) via
`/soleur:architecture`:
- **Guard allowlist (#6553):** `:189` `{armed, flipping, done}` → `{armed, flipping, flushed, done}`,
  with the one-sentence rationale (FSM starts at `flushed`; DBSIZE==0 asserted before `flushed`).
  This corrects an ADR-vs-code inconsistency (the allowlist omitted the very state the FSM starts
  at). Add the widen to `## Alternatives Considered` (the rejected alternative — "document why
  `flushed` is excluded" — is refuted because the FSM's own ordering starts at `flushed`).
- **Rollback URL delete (#6552):** extend Decision 6b (the `op=rollback` reverse write) to note the
  inverse-of-G4 `INNGEST_HEARTBEAT_URL` delete that restores one-pusher-per-monitor.
- **DOPPLER_PROJECT threading (#6555):** note the shift from `--project` flag + sudoers/ci-deploy
  threading to the `/etc/default/inngest-server` EnvironmentFile mechanism.

No NEW ADR ordinal is minted (all changes amend ADR-100). If deepen-plan decides the #6553 change
warrants its own record, the ordinal is provisional (ship re-verifies).

### C4 views
**No C4 impact** — verified by reading all three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`), not a keyword
grep. Enumerated against the change: external systems — `betterstack` (system, model.c4:266) and
`doppler` (model.c4:238) are already modeled; container — `inngest` (dedicated host, model.c4:188)
is modeled; access relationships — `inngest → betterstack` (Vector→Logs + heartbeat, model.c4:403),
`betterstack → hetzner` (uptime probe, :408), `doppler → inngest` (scoped `soleur-inngest` project,
:413) are all present. This bundle adds no external actor, no external system, no container, and no
access relationship — it changes internal on-host mechanisms (guard allowlist, secret-threading,
unit OnFailure, a CI test, a rollback step). Nothing a future engineer reading the C4 would be
misled about.

### Sequencing
All decisions are true at merge (no soak-gated status flip). ADR-100 amendment ships in this PR.

## Domain Review

**Domains relevant:** Engineering (infra + observability). Product/UX: NONE (no UI-surface file in
Files to Edit — infra/workflow/test only; mechanical UI-surface scan is clean). Legal/GDPR: not a
regulated-data change (no schema/auth/API-route/`.sql`; no new PII field shipped — OnFailure marker
+ config hash carry none). Finance/Sales/Marketing/Support/Product: none.

Engineering assessment (CTO lens, carried into deepen-plan): the bundle is coherent — shared files,
one re-eval dependency. Highest-risk item is #6555 (6 unit renders + sudoers byte-parity mirror +
ci-deploy + ~10 test sites + cloud-init immutable-redeploy). #6553 carries a correctness upgrade
(possible normal-path block, not P3). #6551 is correctly investigation-only. `single-user incident`
threshold → deepen-plan (data-integrity + security-sentinel + architecture-strategist) and
`user-impact-reviewer` at review, per the plan-review-catches-different-classes learning.

## Acceptance Criteria

### Pre-merge (PR)
1. `inngest-server-flip-guard.sh:40` case is `armed | flipping | flushed | done`; a guard run with
   `GUARD_FLIP_FLAG=flushed` + a prod-marker `GUARD_POSTGRES_URI` exits **0** (ALLOW). All **FOUR**
   prose/error sites (`:12`, `:15-16`, `:44`, `:45`) read `{armed,flipping,flushed,done}`.
2. ADR-100:189 reads `{armed, flipping, flushed, done}` with the FSM-start rationale (citing
   `:163/:172/:240`); a grep for the exact stale string `{armed, flipping, done}` in ADR-100 returns 0.
2b. **FSM↔guard lockstep drift guard:** a CI test FAILS when the FSM `flag_set`s a pre-`start_server`
    state absent from the guard allowlist (asserts allowlist ⊇ {states the FSM starts the server at}).
3. `cutover-inngest.yml` `op=rollback` deletes `INNGEST_HEARTBEAT_URL` from `soleur-inngest/prd`
   **UNCONDITIONALLY** — in the Half-B region after `esac` (≥:1119/1120), so it runs for EVERY entry
   state (`armed`/`flipping`/`flushed`/`done`/`aborted`/`unset` + the `rolled-back` re-dispatch +
   partial-arm). A workflow test asserts the delete is OUTSIDE the `armed|flipping|flushed|done)`
   case arm and runs on an `aborted`-state rollback fixture. Idempotent, no value echoed; `op=arm`
   unchanged.
4. `inngest-heartbeat.service` renders `OnFailure=inngest-heartbeat-failure-log.service`; the
   non-templated `inngest-heartbeat-failure-log.service` sets `SyslogIdentifier=inngest-heartbeat`
   (no new Source 4 entry) and its ExecStart is a **bare `logger` with NO `doppler run` wrapper**
   (grep for `doppler` / `--project` in the unit returns 0). A test asserts all three.
5. `vector-pii-scrub.test.sh` AC3/AC3b enumerate `.service` + `.sh`-heredoc + cloud-init units and
   FAIL unless each explicit `logger -t`/`SyslogIdentifier=` declaration is in the Source 4 allowlist
   OR the new documented exclusion list. Coverage extends beyond `infra/*.sh`; the exclusion half is
   added; `SYSTEMD_UNIT_IDENTIFIERS` retained only for identifiers no source line yields (webhook).
   The new `inngest-heartbeat-failure-log` unit passes (reuses `inngest-heartbeat`). Guard passes on
   the current tree, fails on a synthesized un-declared tag. (Minimal-shape vs basename-derivation is
   a surfaced taste decision — see decision-challenges.md.)
6. #6555: `DOPPLER_PROJECT` is present + **non-empty** in `/etc/default/inngest-server` on BOTH render
   paths (`cloud-init-inngest.yml:324` + `inngest-bootstrap.sh:339`), and the bootstrap fail-closes
   if it is missing/empty before unit start; NO unit ExecStart/ExecStartPre in ANY of the six sites
   (incl. `inngest-cutover-flip.service`, `inngest-redis.service`) contains `--project` (grep returns
   0); no residual `@@DOPPLER_PROJECT@@` substitution remains; `DOPPLER_PROJECT` absent from both
   sudoers `env_keep` + `ci-deploy.sh --preserve-env`; AC5 byte-parity passes. All `$DOPPLER_PROJECT`
   render-gating logic intact.
7. `apps/web-platform` typecheck/tests: `cd apps/web-platform && ./node_modules/.bin/vitest run`
   (relevant suites) + the infra `*.test.sh` shell suites pass. (Verify the exact runner via
   `package.json` at /work — do not assume.)
8. `## Open Code-Review Overlap: None` holds (61 open code-review issues checked; none touch these
   files).

### Post-merge (investigation / operator — NONE required)
9. #6551 stays OPEN; issue updated with the measured probe findings + the CORRECTED
   `vector_config_*` (Source-section hash, not whole-file) next step. `Ref #6551` in the PR body
   (NOT `Closes`). **Latency honesty (CTO §5):** the image-baked changes (and the instrument's
   payoff) are LATENT until the next dedicated-host force-replace, which is operator/cutover-gated —
   there is NO verified standing "scheduled" re-provision; do NOT claim one. #6551 cannot progress
   before that bake. `Automation: not applicable` for merge (no live host to touch, no vendor console).
10. PR body: `Closes #6552`, `Closes #6553`, `Closes #6555`, `Closes #6556`; `Ref #6551`; a note
    that **inngest-base-url-repoint** remains OPEN and is now unblocked by this cleanup.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (61 open) cross-referenced against every file
in Files to Edit — no match.

## Files to Edit
- `.github/workflows/cutover-inngest.yml` — #6552 rollback delete
- `apps/web-platform/infra/inngest-server-flip-guard.sh` — #6553 widen + prose
- `knowledge-base/engineering/architecture/decisions/ADR-100-inngest-dedicated-single-host-singleton-control-plane.md` — #6553/#6552/#6555 amendment
- `apps/web-platform/infra/inngest-bootstrap.sh` — #6555 (env-file heredoc :339 + 4 `--project` sites :283/:523/:585/:737 + dead-subst :592/:761/:404 + fail-closed check + `:47` SOLEUR-DEBT), #6556 P2 (OnFailure line + `inngest-heartbeat-failure-log.service` heredoc render)
- `apps/web-platform/infra/inngest-cutover-flip.service` — #6555 `--project @@DOPPLER_PROJECT@@` removal (:19) **[standalone unit file — architecture P1-1/Kieran P1-2]**
- `apps/web-platform/infra/inngest-redis.service` — #6555 `--project @@DOPPLER_PROJECT@@` removal (:23) **[standalone unit file]**
- `apps/web-platform/infra/inngest-redis-bootstrap.sh` — #6555 dead-substitution cleanup only (:84); NO `--project` lives here
- `apps/web-platform/infra/cloud-init-inngest.yml` — #6555 env-file pre-create (:324)
- `apps/web-platform/infra/cloud-init.yml` — #6555 sudoers inline copy (byte-parity :83)
- `apps/web-platform/infra/deploy-inngest-bootstrap.sudoers` — #6555 env_keep delete (:27)
- `apps/web-platform/infra/ci-deploy.sh` — #6555 `--preserve-env` (:2785) + forward-guard comment (:2777-2784)
- `apps/web-platform/test/infra/vector-pii-scrub.test.sh` — #6556 P1 guard extension
- `apps/web-platform/infra/cat-deploy-state.sh` — #6551 `vector_config_*` Source-section hash (RECOMMENDED, gated; precedent seccomp_profile_host_sha256:314-334)
- Tests: `inngest.test.sh` (:130/:134/:402/:593 + cutover-flip), `cutover-inngest-workflow.test.sh`, `cloud-init-inngest-bootstrap.test.sh`, flip-guard test (drift-guard AC), heartbeat unit test

## Files to Create
- None. The #6556 P2 OnFailure unit is rendered as a **bootstrap heredoc** in `inngest-bootstrap.sh`
  (non-templated `inngest-heartbeat-failure-log.service`), NOT a standalone tracked file — every
  other inngest unit is a bootstrap heredoc, avoiding a new file + server.tf delivery entry + its own
  pinning test (code-simplicity B3). If /work finds a heredoc unworkable, a standalone file is the
  fallback (but still non-templated, bare-logger, renamed).

## Test Scenarios

**#6556 P1 gap table (from enumeration — each identifier must end in allowlist OR documented exclusion):**

| Effective identifier | Source | Current coverage | Proposed disposition |
|---|---|---|---|
| every `logger -t` tag (14) + `luks-monitor` | `logger -t` / `SyslogIdentifier=` | allowlist ✓ | keep (allowlist) |
| `inngest-heartbeat` (new OnFailure unit) | `SyslogIdentifier=` | allowlist ✓ | keep (allowlist, reused) |
| `webhook` | webhook.service basename | hardcoded in test | DERIVE from unit basename |
| `sh` | cron-egress-{firewall,resolve}, container-restart-monitor, cron-egress-alarm@, soleur-host vector | none | EXCLUDE (shared basename; not diagnostic) |
| `doppler` | inngest-cutover-flip.service, inngest-redis.service | none | EXCLUDE (covered by Source 1/2 unit filters or non-diagnostic) |
| `disk-monitor.sh`, `resource-monitor.sh` | cloud-init.yml monitor units | none | EXCLUDE (own Sentry path) — confirm at deepen |
| `inngest-nftables.sh` | cloud-init-inngest.yml | none | EXCLUDE (firewall unit; not a log channel) — confirm |
| `zot-liveness-heartbeat.sh` | cloud-init-registry.yml | none | EXCLUDE (registry host, not inngest) — confirm |

**Flip-guard (#6553):** `flushed`+prod→ALLOW (new); `armed`/`flipping`/`done`+prod→ALLOW (regression);
`unset`/`rollback`/`rolled-back`/`aborted`+prod→BLOCK; any flag + non-prod URI→ALLOW.

**Rollback (#6552):** `op=rollback` deletes the URL; delete is idempotent (absent→no error); no
value echoed; runs after the `rolled-back` confirm.

## Sharp Edges
- `## User-Brand Impact` is filled (threshold `single-user incident`) — deepen-plan Phase 4.6 will
  halt on an empty/placeholder section; it is complete here.
- **#6553 is likely higher than P3.** The flip oneshot starts the server AT `flushed`
  (`inngest-cutover-flip.sh:189`, flag_set is synchronous `:86`), so a strict reading says the
  current guard blocks the FSM's own controlled start — a normal-path cutover blocker, not a
  restart-window edge. But this has NEVER run in production (host dark) and the flip tests mock
  `systemctl` (`CUTOVER_SYSTEMCTL_CMD`), so the real ExecStartPre guard is never exercised during a
  flip test — the live discriminator (Doppler read-after-write timing during a real cutover) is
  invisible. Per `2026-07-16-refuting-a-hypothesis-...`, do NOT ship a claim that "the cutover is
  broken" as fact; ship the widen (correct under both readings) and record the observation.
- **#6555 blast radius:** 6 `--project` sites + both sudoers copies (byte-parity, AC5) + ci-deploy
  + cloud-init (immutable-redeploy) + ~10 test sites. The env-file writes MUST land atomically with
  the `--project` removals. The `:47` render-time default trap is NOT fixed by this (still keyed off
  cloud-init's inline env); its detector is `cat-deploy-state.sh` `HEARTBEAT_DARK_ARM`.
- **#6553 do NOT "reconcile" by editing the comment.** The fix is a CODE change (widen the case) —
  the comments/error strings then update to match the NEW code; do not merely edit prose while
  leaving the case unchanged.
- **#6551 stays OPEN.** The probes did not resolve to a repo-config defect; the deciding datum is
  the invisible running config. The recommended `vector_config_*` instrument (Source-section hash —
  NOT whole-file, which the `@@HOST_NAME@@` sed at inngest-bootstrap.sh:708 makes mismatch forever)
  is gated on reviewer confirm and does NOT close #6551.
- **#6552 delete is UNCONDITIONAL.** THREE reviewers (spec-flow H1/H2, architecture P1-2, Kieran P1-1)
  converged: `op=arm` writes the URL at G4 (:760) before the FSM, so it is present in `aborted`,
  partial-arm, and re-dispatch states that the forward-state case arm skips. Place the delete after
  `esac` (≥:1119), not in the `armed|flipping|flushed|done)` arm.
- **#6555 touches TWO standalone unit files** (`inngest-cutover-flip.service:19`, `inngest-redis.service:23`)
  in addition to the four bootstrap heredocs — the first draft mislocated them (architecture P1-1,
  Kieran P1-2). `inngest-redis-bootstrap.sh` has NO `--project`. Dropping `--project` is safe because
  the scoped `DOPPLER_TOKEN` (cloud-init-inngest.yml:384) resolves the project even absent the flag;
  but add a fail-closed non-empty check + the dead-`@@DOPPLER_PROJECT@@`-substitution cleanup.
- **#6556 P2 alarm unit: rename + de-wrapper.** Do NOT mirror `cron-egress-alarm@` verbatim — that
  name means "pages a human" here (it emails+Sentries), it wraps in `doppler run --project soleur`
  (wrong on soleur-inngest), and its `@` template is earned by two consumers. Use a non-templated
  `inngest-heartbeat-failure-log.service` with a bare `logger` ExecStart.

## Plan-Review Consolidation (6-agent panel, single-user-incident threshold)

- **Mechanical (auto-applied above):** #6552 unconditional delete (spec-flow/arch/Kieran); #6555 two
  standalone unit files + fail-closed + dead-subst + preserve precondition + "forward-guard" reframe
  (arch/Kieran); #6556 P2 rename + non-template + heredoc + bare-logger (cto/arch/simplicity); #6553
  four prose sites + `:240` cite + FSM↔guard drift guard + `## Considered Options` heading (Kieran/arch/cto);
  #6551 instrument spec correction (cto); latent-until-reprovision honesty (cto).
- **Affirmed sound (all reviewers):** #6553 widen is correct + does not weaken the guard (DBSIZE==0
  asserted before `flushed`); #6552 delete-after-`rolled-back`-confirm ordering; ADR-100 amendment
  adequate; #6551 leave-OPEN-with-gated-instrument (architecture (e): "the right call").
- **Surfaced to `decision-challenges.md` (Taste / User-Challenge — operator's stated direction is the
  default, not silently changed):** (1) DHH: split the bundle (operator directed ONE PR); (2) DHH +
  code-simplicity: swap #6555 to the fail-closed-only alternative / defer the `--project` migration —
  CTO + architecture ENDORSE the delete-the-threading approach as the better long-term call, panel
  split; (3) code-simplicity A1: minimize the #6556 P1 guard (explicit declarations only, drop
  basename-derivation) — tension with #6556's own "SYSTEMD_UNIT_IDENTIFIERS only for identifiers no
  source line can yield" wording; (4) DHH: drop the #6551 instrument from this bundle vs architecture's
  affirmation — kept gated + corrected-spec pending CPO/deepen.
