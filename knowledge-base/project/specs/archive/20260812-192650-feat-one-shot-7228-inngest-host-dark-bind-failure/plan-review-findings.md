# Plan review — consolidated findings (2026-08-11)

Panel: dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer,
architecture-strategist, spec-flow-analyzer, cpo (escalated to 5+1 by
`brand_survival_threshold: single-user incident`).

**Verdict: the plan requires substantial revision before `/work`.** Its central premise is
refuted by the source, and three of its phases are net-negative as written. The
`## Research Insights` section is NOT part of the problem — every reviewer independently
affirmed it. The defects are concentrated in the phases, the ACs, and one inherited premise.

---

## P0-1 — The "dual-pusher heartbeat" premise is FALSE (unanimous)

Asserted in the Overview, Phase 1.1, and the Domain Review. Refuted by:

- `inngest.tf:302` — exactly ONE `betteruptime_heartbeat "inngest_prd"`.
- `inngest-host.tf:380` — `# NO new betteruptime_heartbeat here: the plan REUSES the existing`.
- `inngest-host.tf:152-163` — `INNGEST_HEARTBEAT_URL` is deliberately NOT provisioned to the
  dedicated host while dark, *precisely to prevent masking*.
- `inngest-host.tf:170` — `# The monitor stayed green throughout only because the co-located
  host is the sole pusher` — the code states the opposite of the plan.
- `inngest-bootstrap.sh:277` — the `@@DARK_ARM@@` skip is already implemented, tagged `#6617b`.

Provenance: inherited from a CTO domain assessment and propagated without a source check.

### The `paused` alternative was also checked and REFUTED

`inngest.tf:323` sets `paused = true` with `ignore_changes = [paused]`, which suggested an
inert monitor. But `plugins/soleur/lib/heartbeat-manifest.ts` records, self-pulled from
`/api/v2/heartbeats`: *"Source says paused=true; LIVE is paused=false / up."* The monitor was
armed and green.

### Corrected mechanism

**No monitor anywhere asserts that :8288 is bound.** The pusher is
`exec /usr/bin/curl -gfsS --max-time 10 "$INNGEST_HEARTBEAT_URL"` — a host-liveness ping. It
never touches :8288 on either host. One correctly-armed monitor stayed green for 12 days
because it measures "a timer fired", not "the scheduler serves".

**Consequence:** Phase 1.1 as written is not a fix. Splitting the monitor mints a SECOND
meaningless green — the `#7228` title ("health probe certified a different server") reproduced
a third time. The push must be gated on a listener check, or the monitor is decoration.

---

## P0-2 — A consumer-side probe already exists and would detect this on merge

`inngest-registry-probe.sh` runs on the WEB host, reaches `10.0.1.40:8288` over the private
net, and already returns the exact diagnosis — it has been returning it for 12 days. Nobody
put a monitor on it.

The house pattern for wrapping it was written for a byte-identical incident:
`web-zot-consumer-probe.sh` + `.timer` (#6438 §1) — web host probes peer host every 60s, 200
pings a dedicated heartbeat, everything else suppresses so absence alarms. Its header cites
#6400, "a silent-for-14-days degradation where every health signal stayed green".

**This is strictly better than instrumenting the dark host:** it has no dependency on the
broken host's bootstrap having run, and — decisively — it needs **no host replace**, so it
ships detection the day it merges.

---

## P0-3 — Phase 1 has no delivery path; nothing in the plan owns the replace

`cloud-init-inngest.yml` and `inngest-bootstrap.sh` reach 10.0.1.40 ONLY via
`apply_target=inngest-host-replace`. No phase, AC, or Non-Goal assigns firing it. Phases
1.2/1.3/1.4 and all of Phase 2 can merge, go green, close three issues, and the host stays
exactly as dark as today. AC13 asserts only that Terraform applied the delta — and a heartbeat
placed in `inngest-host.tf` is outside the per-merge apply by that file's own design
(`inngest-host.tf:20-23`), so AC13 is unachievable as written.

---

## P0-4 — Parking the FSM makes the replaced host permanently unverifiable

`inngest-server-flip-guard.sh:44-46` allows `{armed, flipping, flushed, done}`. `rollback` and
`rolled-back` are outside it, so `ExecStartPre` refuses EVERY prod-URI start. After a replace
the host ships markers that all report `listener=no` forever, by design.

Every hypothesis in `## Hypotheses` says "verdict deferred to the first instrumented boot" —
but that boot can never attempt a bind. **The root cause stays UNKNOWN after the replace**,
and the plan does not say so.

Resolution the panel converged on: a **guard-permitted diagnostic boot** against a non-prod
`INNGEST_POSTGRES_URI`, so `is_prod=false` takes the guard's ALLOW arm and the host can
actually try to bind and emit a discriminating `net-health` row — with zero double-scheduler
risk. Nothing in the plan provides this.

### Related: `op=rollback` likely cannot reach `rolled-back`

`scripts/cutover-inngest.sh:1492-1505` writes `INNGEST_CUTOVER_FLIP=rollback`, then blocks on
`confirm_flip_state`, which greps Better Stack for `"flag":"rolled-back"` (600s timeout). That
transition is performed by the ON-HOST FSM and confirmed via the ON-HOST shipper — and the
host ships zero rows. Predicted: the flag rests at `rollback`, the run exits 1. The brake (the
flag write) still lands; only the terminal confirmation fails.

---

## P0-5 — Phase 2.1 makes the FLUSHALL hazard WORSE

`emit_state()` (`inngest-cutover-flip.sh:143`) writes the state slot on EVERY branch including
terminal no-ops; the `rolled-back` arm stamps `{"flag":"rolled-back"}`. `flip_already_done()`
returns true only for exactly `"done"`.

Moving that slot onto the durable volume **persists the erasure** across a replace. A later
`op=arm` then finds `flip_already_done() == false` → `run_preflush_flip` → `FLUSHALL` against
the preserved prod AOF volume.

Phase 2.1 converts a latch that fails **safe by amnesia** into one that fails **unsafe by
false memory**. The latch must be **monotonic** ("has `done` EVER been recorded"), not
last-write-wins.

Compounding, all unlisted in `## Files to Edit`:
- `cat-inngest-cutover-state.sh:15` hardcodes `/var/lock/...` — the no-SSH operator read path
  would report a false "no state".
- `inngest-cutover-flip.sh:143` writes best-effort (`2>/dev/null || true`) — relocating onto an
  unwritable path silently disarms the guard (`cq-silent-fallback-must-mirror-to-sentry`).
- `inngest-cutover-flip.service` has no `RequiresMountsFor=/mnt/data`; the 30s timer can fire
  before the mount on any reboot.
- `cloud-init-inngest.yml:182` mounts with `|| true` — a failed mount leaves a latch that
  *looks* durable on the ephemeral root disk.

### And the Risks-table mitigation is mechanically wrong

"the FSM is parked at `rolled-back` so the guard refuses a prod start" — the guard is an
`ExecStartPre` on `inngest-server.service`. `FLUSHALL` runs from a separate oneshot that never
consults it. **The guard cannot prevent a flush.**

---

## P0-6 — Phase 2.4 silently breaks the guard and its lockstep test

Stamping `done` with an instance id changes the flag VALUE. Two consumers read it, neither in
`## Files to Edit`:
- `inngest-server-flip-guard.sh:44-46` — exact `case` match. `done@i-1234` falls through → the
  guard blocks a legitimately-completed host on every reboot.
- `inngest-server-flip-guard.test.sh:83-134` — derives start-states by parsing `flag_set`
  literals with a hard-coded `EXPECTED_START_SITES=2`. Phase 2.3 also trips this deliberate
  re-review latch.

If the id goes in a separate key instead, the guard stays instance-blind and still ALLOWs a
foreign-instance `done` — the double-scheduler hazard. Either way **AC8 is true of the FSM but
not of the guard**, and the guard is what decides whether a second prod scheduler starts.
Violates `hr-type-widening-cross-consumer-grep`.

---

## P1 — Duplication and scope

- **Phase 1.2 duplicates an existing probe.** `inngest-server-probe.timer` / `.sh` already ship
  hourly on this host with `http_code` against `127.0.0.1:8288/health`, `server_active`,
  `vector_active`, `redis_active`, `uptime_s`, `boot_id`, `image_ref`, plus a Vector-independent
  phone-home fallback. Real delta: 4 fields. Also `inngest-heartbeat.timer` exists with an
  `OnFailure=` loud channel, a rate-limited dark arm, and `cat-deploy-state.sh` surfacing.
- **The 60–300s cadence reverses a recorded decision.** The existing probe is hourly because
  "at 60s this marker alone would cost ~1,440 rows/day against the ~25k/day quota — the very
  cost #6617b is removing". `vector.toml` calls any new timer-driven tag "a fresh quota
  decision"; the plan adds a tag and skips the decision.
- **Phase 4 rides an unrelated subsystem.** The entropy bound touches the container-registry
  userdata budget. It is here because it was on an abandoned branch. Cut to its own PR.
- **Pin-freshness monitoring** builds a monitor whose only remediation (the bump) the same
  document defers. Cut to the bump window.
- **ADR-179 costs more than the sentence is worth.** The rule is a correction to ADR-100's
  Decision 6a, which this plan already amends in place. Folding it there deletes the ordinal
  archaeology, AC9, the collision risk row, and the merge-time re-derivation.

---

## P1 — Acceptance criteria (roughly 2:1 padded, several unsatisfiable)

- **AC1** — ownership is not a Terraform property (the URL→host binding is out-of-band by
  design). A naive count is wrong by 7: nine `betteruptime_heartbeat` resources repo-wide. Name
  resource addresses.
- **AC2** — structurally unsatisfiable. `inngest-bootstrap.sh` IS the shared renderer for both
  hosts; any grep for the dedicated heartbeat in "web-host code paths" hits it. "field-isolated"
  is a Better Stack query concept with no meaning applied to `grep`.
- **AC3** — category error: a `.timer` contains `OnUnitActiveSec`/`Unit`, not health fields.
- **AC4** — proves nothing if the unit ships via `templatefile()`; assert over RENDERED userdata.
- **AC9** — absence-grep self-matches: an honest ADR explaining why it omits `supersedes:` will
  contain the string. Needs a frontmatter-scoped assertion.
- **AC12** — vacuous. Suite registration is DERIVED from `infra-validation.yml`
  (`run-registered-suites.sh:27,128`), which is absent from `## Files to Edit`. Every new suite
  never executes, silently defeating the RED phase.
- **AC13** — passes on a paused monitor with a stale Doppler URL.
- **Phase 1.5 has no AC at all** — the most load-bearing phase, and the only one that would
  prove the channel works.

---

## P1 — Terraform mechanics for the heartbeat change

- `doppler_secret.inngest_heartbeat_url_prd` carries `lifecycle { ignore_changes = [value] }`.
  Repointing the value plans NO change and applies nothing, while AC1/AC13 still pass. A new
  monitor needs a NEW `doppler_secret` resource, not a value edit.
- A recreated heartbeat is born `paused = true`, discarding the operator's live unpause that
  `ignore_changes = [paused]` exists to protect.
- Arming must follow the `web-probe.tf:39-40` / ADR-117 precedent (PATCH `paused=false` only
  after a real measured beat), not a UI step — which would be an undeferred operator step.
- `scripts/cutover-inngest.sh` is unlisted but `op=arm` (`:998`/`:1079`) copies the SHARED
  monitor's URL to the dedicated host, and `op=rollback` (`:1533`) unconditionally DELETES it.
- `outputs.tf:26` consumes `betteruptime_heartbeat.inngest_prd.url` and would break at plan time.
- A new `.tf` resource needs a `-target=` line in `apply-web-platform-infra.yml` (unlisted).

---

## P1 — CPO: CHANGES-REQUESTED

1. **Price the restoration deferral.** Repointing `INNGEST_BASE_URL` is 3 hardcoded sites
   (`cloud-init.yml` + 2 in `ci-deploy.sh`), ships via normal ci-deploy with no window, and does
   NOT create the double-scheduler — it points the app at the host that is already the sole live
   scheduler, removing the split-brain. Either take it as an interim restore or record why not,
   with the user cost. "Per the operator decision" is not a rationale at this threshold.
2. **Answer recoverability.** The plan contains zero occurrences of `replay`, `backfill`, or
   `dead-letter`. What happens to 12 days of failed dispatches is not deferred — it is
   unconsidered. This is the single most user-relevant fact about the incident.
3. **Correct the blast radius.** #7228 measured the failure as fleet-wide, not inbound-email —
   `engineering.pr_review_pending` among them. Conversely the 53 crons were unaffected (#7230),
   because execution is still pinned to web-1. The honest statement is both broader and narrower.
4. **Assert the heartbeat is ARMED, not merely declared** — add
   `plugins/soleur/lib/heartbeat-manifest.ts` to Files to Edit with a `feeder` row. #6537 is the
   precedent where a probe "claimed to have shipped and left the monitor inert for 9 days".

Also: both Non-Goals say "Tracked as a follow-up issue" with no number
(`wg-when-deferring-a-capability-create-a`), and the replace dispatch is an unowned operator
step (`wg-block-pr-ready-on-undeferred-operator-steps`).

---

## What every reviewer said to KEEP

The retention-vs-boot-age reasoning that reframes the defect; refusing to name a root cause
where the discriminator was destroyed; running the flip guard against live values and scoping
its verdict to *now*; enumerating every write site of the token file; the field-isolation-on-
`host` discipline; Phase 1.3 (per-boot token re-stage) and Phase 1.4 (loud emitter), both real
`cq-silent-fallback-must-mirror-to-sentry` violations; and deferring the CLI bump on the
shared-Postgres goose-migration coupling.

---

## Converged shape for the revision

1. **Consumer-side probe** on the web host wrapping `inngest-registry-probe.sh`, cloned from
   `web-zot-consumer-probe.{sh,timer}`, pinging its own NEW heartbeat, armed on the ADR-117
   measured-beat pattern. Detects the outage on merge, no host replace.
2. **Gate the existing dedicated pusher on a listener check** (~5 lines in the existing
   heredoc) so a green beat means something. Decide and state its disposition during the
   deferral window (unfed vs permanently red).
3. **Extend the existing `inngest-server-probe.sh`** with the 4 missing fields. Delete the new
   timer/service/SYSLOG_IDENTIFIER/vector allowlist edit.
4. **Keep 1.3 + 1.4** (token re-stage, loud emitter) — cheap, correct, demoted to
   defense-in-depth.
5. **Monotonic latch** + `RequiresMountsFor=` + fatal write + sweep `cat-inngest-cutover-state.sh`.
6. **Merge 2.3/2.4** into one instance-scoped, probe-derived `done`, with the guard and its
   lockstep test in Files to Edit.
7. **Fold the rule into the ADR-100 amendment**; drop ADR-179.
8. **Add a diagnostic-boot path** (non-prod backend) so the replaced host can be verified.
9. **Own the replace** and the two deferrals as numbered issues.
10. **Cut Phase 4 entirely** to its own PRs.
11. **Price the restoration deferral and answer recoverability** per CPO.
