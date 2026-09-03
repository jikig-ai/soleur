---
title: "Tasks — inngest-cutover-flip Doppler seam guard (#7761)"
branch: feat-one-shot-7761-cutover-flip-seam-guard
plan: knowledge-base/project/plans/2026-09-03-fix-cutover-flip-doppler-seam-guard-plan.md
issue: 7761
lane: cross-domain
---

# Tasks

Derived from the finalized plan. Read the plan's `## Guard Contract` and `## Alternatives
Considered` before starting — several obvious implementations were tried and rejected for reasons
that are not obvious from the code.

## Phase 0 — Preconditions (measure, do not assume)

- [ ] 0.1 `doppler secrets --only-names -p soleur-inngest -c prd` — confirm no seam name has appeared.
- [ ] 0.2 `doppler secrets get INNGEST_CUTOVER_FLIP -p soleur-inngest -c prd --plain` — record the FSM
      state; confirm the flip timer is live via `scripts/betterstack-query.sh` on the marker stream.
- [ ] 0.3 Confirm withholding the `DOPPLER_PROJECT` / `DOPPLER_CONFIG` / `DOPPLER_ENVIRONMENT`
      **secrets** breaks nothing. Do not inherit the earlier draft's citations — for this host the env
      file is pre-created by `cloud-init-inngest.yml` (`inngest-bootstrap.sh:793-800`), and it carries
      no `DOPPLER_CONFIG` and no `DOPPLER_ENVIRONMENT`. What makes it safe: `--config prd` is on the
      command line and the secret-write child passes `--project`/`--config` explicitly at `:86-87`.
- [ ] 0.4 Record the per-fire Doppler fetch behaviour under `PrivateTmp=true` on a 30-second cadence.
      `PrivateTmp` itself is not optional — `inngest.test.sh:200,232` require it, spelled `true`.
- [ ] 0.5 Run both cutover suites green; record the floors (measured at plan time: 102 and 45, both at
      zero headroom).

## Phase 1 — Failing tests first

- [ ] 1.1 Write Guard 1's eight mutation rows and two harness rows as executable cases.
- [ ] 1.2 Write Guard 2's seven mutation rows and three harness rows, including the `\n`-escaped
      `.tf`-heredoc must-RED fixture.
- [ ] 1.3 Confirm every row is RED before any implementation lands.

## Phase 2 — The in-script argv gate

- [ ] 2.1 Insert the gate after `readonly SERVER_UNIT` (`:61`) and before `STATE_FILE` (`:62`).
- [ ] 2.2 Gate on `[[ ${1:-} == --fixture-seams ]]`. Do not introduce an env-var marker.
- [ ] 2.3 Unset all fifteen seam names when the flag is absent; count what was unset. Do **not** unset
      `INNGEST_CUTOVER_FLIP` or `INNGEST_REDIS_PASSWORD`.
- [ ] 2.4 Emit a raw `logger -t inngest-cutover-flip "SOLEUR_INNGEST_CUTOVER_SEAM_REFUSED …"` when a
      seam was present and the flag absent. Not `emit_state` — it truncates the state slot that
      carries the legacy latch record.
- [ ] 2.5 Use `n=$((n+1))`, no trailing `[[ … ]] && …`. The block runs ~460 lines before the ERR trap
      at `:523`; a stray non-zero is a silent death.
- [ ] 2.6 Do not touch `PATH`, `BASH_ENV`, `IFS` or `LD_PRELOAD`.
- [ ] 2.7 Add no `start_server` site; insert no `flag_set` between `:496` and `:497`.

## Phase 3 — Harness

- [ ] 3.1 Append `--fixture-seams` at `inngest-cutover-flip.test.sh:159`, `:293`, `:334` and
      `inngest-cutover-latch.test.sh:176`. All four; `:293` and `:334` are separate re-execs.
- [ ] 3.2 Add refusal cases that assert a canary file is **absent**. Introduce no `PATH` shadowing.
- [ ] 3.3 Refusal cases run with the flag absent so they drive only the `noop-unset` arm.
- [ ] 3.4 Clean `/var/lock/inngest-cutover-flip.state` in `setup_case`/`teardown_case`.
- [ ] 3.5 Raise `MIN_ASSERTIONS` and `LATCH_MIN_ASSERTIONS` by exactly the number added.

## Phase 4 — Bound the injection at the unit

- [ ] 4.1 Add `--only-secrets INNGEST_CUTOVER_FLIP`, `--only-secrets INNGEST_REDIS_PASSWORD` and
      `--no-exit-on-missing-only-secrets`, all **after** `--config prd` and before the `--`.
- [ ] 4.2 Comment the `--no-exit-on-missing-only-secrets` line naming `noop-unset` as its reason.
- [ ] 4.3 Do **not** add `--no-fallback`.
- [ ] 4.4 Build Guard 2, lifting `enumerate_units()` and helpers from
      `credential-persist-home-guard.test.sh:571-605` (copy, do not source — ADR-177 §A3), with the
      ack-list/floor discipline from `inngest.test.sh:1617-1730`.
- [ ] 4.5 Register the new suite in `.github/workflows/infra-validation.yml`.

## Phase 5 — Systemd sandboxing

- [ ] 5.1 Add `NoNewPrivileges=yes`, `ProtectSystem=strict`, `PrivateTmp=true`. No `ProtectHome`.
- [ ] 5.2 Use `StateDirectory=inngest-cutover` plus `ReadWritePaths=/var/lock /mnt/data`. Do not name
      the lazily-created subdirectories, with or without a `-` prefix.
- [ ] 5.3 `systemd-analyze verify` the unit.

## Phase 6 — Record

- [ ] 6.1 Amend ADR-100 with the untrusted-name-space decision and the per-host-indirect-name limit.
- [ ] 6.2 Correct `model.c4:578`'s edge description; run the two C4 tests.

## Phase 7 — Full battery

- [ ] 7.1 Run the whole infra suite set, not the touched shards.

## Phase 8 — Rollout

- [ ] 8.1 Push the `vinngest-vX.Y.Z` tag; confirm the image build.
- [ ] 8.2 Bump both digest pins together (`cloud-init-inngest.yml:677`, `:721`).
- [ ] 8.3 Dispatch `apply_target=inngest-host`.
- [ ] 8.4 Commit `scripts/followthroughs/inngest-cutover-flip-rollout-7761.sh` and run it.
- [ ] 8.5 Close #7761 once 8.4 passes. The PR body carries `Ref #7761`, not `Closes`.

## Follow-ups to file

- [ ] F1 The four sibling units, with authored per-unit lists. Sequence `git-data-gc` first.
- [ ] F2 The brand-survival threshold ladder inversion.
- [ ] F3 Roadmap milestone drift: #7761 and #7695 sit in *Post-MVP / Later* while #6178 is *Phase 4*.
