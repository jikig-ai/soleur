# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-24-fix-c4-stale-banner-diagnostic-and-likec4-bwrap-sandbox-plan.md
- Status: recovered from partial-artifact (planning subagent terminated by API rate limit, HTTP 429, 2026-09-24 15:5x CEST; plan body incl. `## Acceptance Criteria` was on disk)
- Plan artifact: recovered (selector=branch)
- deepen-plan: DONE (2026-09-24). Next: `soleur:work` on the plan.

### Errors
- Planning subagent hit the account session limit (resets 16:40 Europe/Paris) before deepen-plan and before emitting its Session Summary.

### deepen-plan run
- Gates: 4.6 pass, 4.7 pass, 4.8 pass (no PAT), 4.9 copy-only exemption per `ui-surface-terms.md` §Excluded (explicit override in plan + decision-challenge 1), 4.10/4.5/4.55 not triggered, 4.11 `lint-guard-contract.py` green (5 guards). markdownlint clean.
- Seats added this round (panel architecture/Kieran/spec-flow not re-spawned): security-sentinel, test-design-reviewer, code-simplicity-reviewer, observability-coverage-reviewer, learnings-researcher, verify-the-negative (sonnet).
- Replica measurements (bookworm bwrap 0.8.0 + prod seccomp): `--size`, `--unshare-ipc/uts` OK; `--disable-userns` fails (RO /proc/sys); root tmpfs writable without `--remount-ro /`; child can plant a symlink in `/c4-out`.
- decision-challenges.md: added 5 (no-reason copy) and 6 (Concierge-edit reload deferred).

### Findings disposition (one line each; full table in the plan's "Review Findings Disposition")
- SF1/AR1 (P0) symlink/FIFO/oversize output read — ADOPTED (Guard 5, `readRenderOutput`).
- SF2 (P1) resource bounds — ADOPTED stderr cap, sized tmpfs, RO `/` + `/dev`, stat-before-read; prlimit/choom measure-then-adopt; REJECTED `RLIMIT_AS`, container `--pids-limit`.
- SF3 (P1) "will refresh" promise — ADOPTED (`RETRY_DIAGNOSTIC` on resync failure, `SUPERSEDED_LINE`); REJECTED client re-fetch.
- SF4 (P1) Concierge edit leaves banner — DEFERRED with follow-up issue (Phase 3 item 5).
- SF5/AR5 (P1) weak boot probe — ADOPTED (real fixture render via the one spawn site).
- SF6/AR7 (P1) vacuous isolation row — ADOPTED (H4 with positive controls).
- AR2 (P1) source pinning — ADOPTED.
- AR3 (P1) prod `/usr` pin — ADOPTED.
- AR4 (P1) probe after `listen` — ADOPTED.
- K1-K5 (P1) command param, one spawn site, fsMock, `views:{}` fixtures, real-bwrap file placement — ADOPTED.
- SEC1 (P1) `rm` while sandbox alive after timeout — ADOPTED (wait for `close`, Guard 5 row 5).
- TD1-TD4 (P1) rows that could not go red — ADOPTED (harness notes); TD4 moot after SIM3.
- OBS1-OBS3 (P1) info line not shipped, pino-mirror tag loss, layer citations — ADOPTED (Sentry info event, `err = null`, layers 3/5).
- SF7-SF11, AR6, AR8, K6-K10 (P2) — ADOPTED, except `--disable-userns` REJECTED (measured failure) and reason persistence across reload REJECTED.
- SEC2-SEC6 (P2) forgeable tag, fork/OOM/`/dev`, nested userns, fd scan, absolute bwrap — ADOPTED (status fd / choom / prlimit conditional on measurement).
- TD5-TD11 (P2) — ADOPTED.
- OBS4-OBS5 (P2) probe-absent detection, executable AC-P1 + `detail_class` — ADOPTED.
- SIM1 split pool — REJECTED; SIM2 merge Guard 4 — REJECTED; SIM3 cut module-load row — ADOPTED; SIM4 always two-arg `onSaved` — REJECTED; SIM5 census postmerge — REJECTED (CPO condition); SIM6 drop PROBE_STAGE boundary row — ADOPTED; SIM8 de-duplicate — ADOPTED.
- VN `"non_zero_exit"` literal in c4-writer-rerender.test.ts — ADOPTED (claim corrected).
- LRN kb-share lstat TOCTOU, single-fd, vitest leaks — ADOPTED.
