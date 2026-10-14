# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-08-16-fix-betterstack-ingest-quota-exhaustion-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- Scope check: clean — `git diff <base>..HEAD --name-only` lists only
  `knowledge-base/project/{plans,specs}/` paths. No product code touched during planning.
- Post-planning collision re-probe: plan frontmatter `closes: 7569`, already cleared at
  Step 0a.5 (OPEN, zero linked/merged/body/title/git-log hits). No newly-discovered target.

### Errors
None blocking. Four self-corrections during planning, each caught by measurement:

1. First draft repeated the issue's false premise that `betterstack-query.sh` "exits 0 on a
   failed curl". Measured: bad SQL -> 22, bad host -> 6, empty -> 0. Remedy for a
   non-existent mechanism; cut.
2. Called `vector.toml`'s `parse_err` arm "the single hole". The comment five lines above
   documents it as a deliberate #4773 decision keeping non-JSON crash/stack lines. A naive
   bound would have deleted crash capture.
3. IaC section claimed "no `.tf` change, nothing applies". Wrong twice: `server.tf:982`
   hashes `vector.toml`, and delivery runs through a gated `vector-redeliver`
   `workflow_dispatch`. Merging alone delivers to no host.
4. Named `filter`/`throttle` for a fan-out problem. A filter cannot merge events; a throttle
   would corrupt traces. `reduce` is the correct element.

### Decisions
- Reframe the issue: account-wide Better Stack ingest refusal (HTTP 402
  `{"error":"Quota exceeded"}`), not a registry-channel fault. ADR-184's shipper is
  exonerated — absent from the top-10 producers, its 5,000/day cap held.
- Fix the existing detector rather than build a second one.
  `scheduled-zot-restart-loop.yml` ran every 30 minutes throughout and filed nothing: its
  TRANSIENT arm is fail-open for exactly the total-outage shape. Reuse the four-outcome
  taxonomy already in `betterstack-assert-absence.sh`; do not mint a third vocabulary.
- The volume cut alone restores the free tier. Measured 1,269 B/row x 107,567 =
  3.81 GB/month against a 3 GB allowance; removing the chronic Inngest `ECONNREFUSED` loop
  (64% of all ingest, from the already-tracked down host #7462) lands at ~1.48 GB/month.
  The paid tier buys an overage valve and 30-day retention, not capacity.
- This is an integrity problem, not only a billing one. The canonical classifier's only
  exit-0 is satisfiable by any row containing `SOLEUR_PROBE_CANARY` on that host; the sole
  barrier is an undocumented `.toLowerCase()` written for origin comparison. A forged
  `SOLEUR_ZOT_DISK` row can also suppress the alarm outright.
- Repeat of a documented 2026-06-10 near-miss whose "no internal monitor watches quota"
  action item (#5134) was never closed.
- Hard deadline: 3-day `logs_retention` means the last surviving evidence ages out
  ~2026-08-17 19:07Z.

### Root cause (self-pulled by the parent session, pre-planning)
- `POST https://s2457081.eu-fsn-3.betterstackdata.com/` with the live token ->
  HTTP 402, body `{"error": "Quota exceeded"}`.
- Bare `--since 24h --limit 3` (no grep) returns 0 rows of any kind from any producer.
- Per-day: 2026-08-13 = 61,669; 2026-08-14 = 107,567; 08-15 and 08-16 = zero. The
  08-07..08-12 absence is 3-day retention, NOT an outage.
- Hourly on 08-14: flat ~5,500/h through 18:00, then 612 in the 19:00 hour, hard stop at
  19:06:58Z. A clean cliff with no ramp = quota ceiling, not a degrading producer.
- Destination and credentials healthy: source 2457081 alive, `ingesting_paused: false`,
  table unchanged; source token sha256 == `soleur/prd_terraform` == `soleur-registry/prd`
  (all `81dea0a1...`); `zot-registry.tf:125` URL == the API's `ingesting_host`.
  All four candidates in the issue body are therefore disproven.
- Top producers on 08-14 by `SYSLOG_IDENTIFIER`: `dba0075ad965` (= container
  `soleur-web-platform`) 80,320; empty-identifier 23,012; `web-git-data-probe` 2,259;
  `web-zot-consumer-probe` 1,167; rest < 400 each.

### Components Invoked
- Skills: `soleur:plan`, `soleur:deepen-plan`
- Agents: `repo-research-analyst`, `learnings-researcher`, `engineering:cto`,
  `operations:coo`, `observability-coverage-reviewer`, `architecture-strategist`,
  `security-sentinel`, `test-design-reviewer`, `code-simplicity-reviewer`,
  `user-impact-reviewer`
- Gates: `lint-infra-no-human-steps.py` (green), `lint-guard-contract.py` (green, 2 guards),
  deepen-plan halts 4.5-4.11 (all pass)
- Self-pulled telemetry: `betterstack-query.sh` via Doppler `prd_terraform`, Better Stack
  Telemetry management API, direct ingest probes, `gh` issue/PR/run APIs

## Work Phase
- Status: starting
- Blocking items to resolve at `/work` Phase 0 before code is written:
  F14, F15, F7, F4, F2, and the empty-batch gate.
