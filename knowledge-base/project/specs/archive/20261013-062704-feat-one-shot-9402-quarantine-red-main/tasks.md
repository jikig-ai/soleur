---
title: "chore(ci): quarantine checks red on main — tasks"
branch: feat-one-shot-9402-quarantine-red-main
plan: knowledge-base/project/plans/2026-10-01-chore-quarantine-red-main-checks-plan.md
lane: cross-domain
---

# Tasks — quarantine checks red on main, fix timing-flaky test, incremental shard regen

Derived from the finalized plan (post-review). Each task is ≤ 2 h.

## Phase 1 — red-on-main probe + suite (P1)

- [x] 1.1 Write `plugins/soleur/test/check-red-on-main.test.sh` FIRST
      (`cq-write-failing-tests-before`): gh PATH-stub in the
      `admin-merge-ready.test.sh` shape — canned JSON per endpoint,
      STUB-MISS on unexpected argv, real-flag whitelist only (`gh api`:
      `--jq`, `--paginate`, `-X`, `-f`, `-F`; `gh issue`: `--label`,
      `--state`, `--milestone`, `--json`, `--jq`, `-L`) — invented flags
      exit 64.
  - [x] 1.1.1 Rows: red-on-main, green-on-main, skipped-in-newest-run +
        failed-in-older-run (windowed evidence), no-evidence (rc 2),
        gh-error (rc 3, no quarantine), cancelled-classified-as-red.
  - [x] 1.1.2 `--report` rows: sentinel dedupe (existing sentinel → comment,
        not create), closes its own sentinel on green, never touches a
        non-sentinel issue, list-failure files nothing.
- [x] 1.2 Write `plugins/soleur/scripts/check-red-on-main.sh`:
      `<check-name> --run-id <id> [--report] [--repo o/r]`; resolve
      `.workflow_id` from the failing run; scan ≤ 5 completed main runs of
      that workflow; first run where an EXACT-named job (matrix suffix
      included) reached a real conclusion decides the verdict; exit
      0/1/2/3 = green/red/no-evidence/error; one
      `SOLEUR_RED_ON_MAIN verdict=…` marker per call; `--self-test` runs the
      classifier over fixture JSON with zero network and prints
      `SOLEUR_RED_ON_MAIN_SELFTEST ok`.
  - [x] 1.2.1 `--report`: label pre-create via `gh label create --force
        2>/dev/null || true`; file under milestone "Post-MVP / Later" with
        labels `ci/main-broken`, `meta/machinery`, `type/chore` (all verified
        to exist); sentinel `<!-- soleur:red-on-main check="<name>" -->`;
        oldest-first dedupe; list failure warns, never files; green verdict
        comments+closes only sentinel-owned issues for that check name.
  - [x] 1.2.2 `gh api` GET calls embed query in URL — never `-f` (flips to
        POST, 404s actions runs endpoints).

## Phase 2 — ship/monitor wiring (P1 consumers)

- [x] 2.1 Create
      `plugins/soleur/skills/ship/references/red-on-main-quarantine.md` —
      full disposition detail (advisory → report+continue; required →
      report+escalate, no rerun/no test-fix-loop; green/no-evidence/error →
      unchanged behavior).
- [x] 2.2 `plugins/soleur/skills/ship/SKILL.md` Phase 7 red-check arm: add a
      ≤ 300-byte pointer to the reference file, OUTSIDE the
      `phase-7-poll-block` markers (merge-pr mirror untouched). Budget:
      SKILL.md is at 273,665/274,000 B — 335 B headroom; compress adjacent
      prose if needed, never raise the ceiling.
- [x] 2.3 `plugins/soleur/scripts/monitor-pr-checks.sh`: on terminal-fail
      exit only, annotate ≤10 failing check names with the probe verdict;
      warn-and-continue on probe error (never block the monitor's exit).

## Phase 3 — deterministic ceiling trip (P2)

- [x] 3.1 `scripts/test-all-runtime-ceiling.test.sh`: `build_sandbox` gains a
      `sub_once` splice on `_elapsed_s=$(( "${EPOCHSECONDS:-0}" -
      _RUN_START_EPOCH ))` adding `$(cat "${SOLEUR_TC_BUMP_FILE:-/dev/null}"
      2>/dev/null || echo 0)`.
- [x] 3.2 New `bump.sh` fixture writing `120` to `${SOLEUR_TC_BUMP_FILE}`;
      convert trip arms to ceiling=60 (replaces `slow.sh`/`sleep` in trip
      arms); control arms (99999, `abc`, `07200`, CI-exempt) and the mutation
      battery anchors unchanged.
- [x] 3.3 Verify: `for i in 1 2 3 4 5; do bash
      scripts/test-all-runtime-ceiling.test.sh || break; done` — five
      consecutive greens.

## Phase 4 — incremental regen + ADR amendment (P3)

- [x] 4.1 `scripts/regenerate-shard-manifest.py` gains `--incremental`:
      incumbent rows pinned for still-registered labels; new labels →
      least-loaded leg by incumbent loads at floor weight; unregistered
      incumbent rows drop; refuses `--run/--runs/--timings-dir` combos;
      `--legs` K≠N committed-write refusal unchanged; empty incumbent → WARN
      + full-assignment fallback; durations table takes the parity delta (stale rows out,
      + new labels in at floor; retained rows byte-identical).
- [x] 4.2 `plugins/soleur/test/regenerate-shard-manifest.test.sh` arms:
      +1-row-only diff on suite add, unregistered-row drop, new label to
      least-loaded leg, empty-incumbent fallback, contradictory-flag refusal,
      incumbent leg > n is rejected.
- [x] 4.3 Runbook `ci-test-scripts-sharding.md`: prescribe `--incremental`
      for add/remove; full `--runs 5 --write` for balance corrections.
- [x] 4.4 ADR-240: amend `## Decision` + `## Alternatives Considered` with the
      incremental mode + the full-rebalance alternative's cost evidence
      (#9402's 10-suite rebalance).

## Phase 5 — pre-ship

- [x] 5.1 `python3 scripts/lint-guard-contract.py
      knowledge-base/project/plans/2026-10-01-chore-quarantine-red-main-checks-plan.md`
      stays green.
- [ ] 5.2 Semver label `semver:patch` on the PR; body carries
      `Closes #9402` + `## Changelog`.
- [x] 5.3 `git grep` check: Phase-7 probe pointer sits outside
      `phase-7-poll-block` markers.
