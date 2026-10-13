# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-16-fix-inert-monitor-invariant-registry-heartbeat-plan.md
- Status: complete

### Errors
- Two Write calls blocked by `iac-plan-write-guard.sh` on the phrase `out-of-band`, which the plan
  quoted only in order to delete. Diagnosed by running the hook against the content rather than
  guessing; resolved by removing the trigger phrase rather than using the `iac-routing-ack` bypass —
  the plan has zero operator steps, so it passes the gate honestly.
- No other errors. Planning only; nothing implemented.

### Decisions
- Do NOT unpause `soleur-registry-prd` first — build its feeder, then unpause. `ZOT_HEARTBEAT_URL`
  has zero consumers repo-wide (verified independently by the parent: 1 hit, its own `doppler_secret`
  definition at `zot-registry.tf:441`). The probe was never written, so #6537's premise "the probe
  shipped" is false. Unpausing today would page every 60s forever (#6210 is that exact incident).
  Issue ask #1 explicitly authorised this inversion.
- Corrected a second inherited premise: "the host can die silently" is FALSE — `zot-disk-heartbeat`
  already alarms host death in <=25 min via absence. The real gap is narrower: zot process dead,
  host alive, disk fine.
- Feeder pings the registry's own private IP (`10.0.1.30:5000/v2/`), never `localhost` — the repo
  documents that a localhost probe is structurally blind to #6400.
- Zero Terraform resource changes: `betteruptime_heartbeat.registry_prd` is an
  `OPERATOR_APPLIED_EXCLUSION` (`terraform-target-parity.test.ts:584`), so a `period` edit could
  never apply. Meets the existing 60/30 cadence with a systemd timer, mirroring `inngest_prd`.
- Cut ~50% of v1 across a 7-agent review panel; v1's own watchdog would itself have been an inert
  monitor — the exact class it existed to gate.

### Components Invoked
`soleur:plan` · `soleur:plan-review` · `soleur:deepen-plan` · `Explore` · `dhh-rails-reviewer` ·
`kieran-rails-reviewer` · `code-simplicity-reviewer` · `architecture-strategist` ·
`spec-flow-analyzer` · `engineering:cto` · `product:cpo`

### Carry-forward caveat for /work
Phase 4.2 dispatches a `registry-host-replace`; its "latency-only, no downtime" analysis depends on
the GHCR fallback still being warm. ADR-096 is status `Adopting` today, so it holds — but AC19
re-asserts this at run time and halts if Phase-5 has retired GHCR. `/work` must not assume it.

### Parent-verified
- Scope check: `git diff origin/main...HEAD --name-only` → only `knowledge-base/project/{plans,specs}/`.
  Base SHA `36837416c` matches the branch parent (no stale-ref false positive).
- Brief error corrected by the plan: `scripts/betterstack-query.sh` is a ClickHouse Logs reader and
  cannot read the uptime/heartbeats API. Correct surface is
  `https://uptime.betterstack.com/api/v2/heartbeats` with `BETTERSTACK_API_TOKEN`.
