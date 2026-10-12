# Tasks: S7b producer-side join, Arm P (tracker #9217, Ref only)

Plan: knowledge-base/project/plans/2026-10-11-chore-grep-q-wave-b-s7b-producer-join-plan.md

## Phase 0 J0 (read-only; first commit is evidence.md)

- [x] 0.1 Re-run `ulimit -v 6000000; python3 -I knowledge-base/project/specs/feat-one-shot-grep-q-pipe-guard-s7b-producer-join/j0-derive.py` in a clean checkout; compare with `j0-plan-time-output.txt`; explain differences.
- [x] 0.2 Classify each Funnel A pair (stdin-reading command or not); give every `exempt` row a closed-vocabulary reason.
- [x] 0.3 Reach probe in a sandbox copy (marker line at the top of each stub, one run per owner suite under `timeout 300`): EXEC, TEXT, UNVERIFIED, BLOCKED (#9956). Never commit the markers.
- [x] 0.4 Read each EXEC stub by hand: drains in every arm, some arms, or never; record the consuming flag per verb from the non-test site.
- [x] 0.5 Record the count of suites needing an edit and how many are under `apps/web-platform/infra/` (no gate; the commit order makes a cut at ship time free).
- [x] 0.6 Write `evidence.md` with 0.1 to 0.5 and commit it before any owner suite is touched.

## Phase 1 Red first

- [x] 1.1 In the guard, add the derivation, the empty-table comparison and the control rows; run once from a clean checkout under `ulimit -v 6000000`; record each new row's first result in evidence.md.

## Phase 2 Stub edits (hand edits only)

- [x] 2.1 Commit A: owner suites outside `apps/web-platform/infra/` (`.github/scripts/test`, `plugins/soleur/test`, `scripts`, `tests`).
- [x] 2.2 Commit B: infra owner suites, and the sourced harness `workspaces-luks-harness.sh` if its `cryptsetup` stub needs the edit. Skip `cloud-init-inngest-bootstrap.test.sh` while #9956 leaves it red at base.
- [x] 2.3 Each edited stub: flag-keyed drain as its first statement (`timeout 2 cat`, capture only when the suite names a capture file, `[ ! -t 0 ]` kept, dash-safe in `#!/bin/sh` stubs); one wire assert per drained pair with the `${KNOB:-default}` form.
- [x] 2.4 `git diff --stat` on each owner suite: only the three kinds of edit, no reach-probe marker left behind.

## Phase 3 Guard

- [x] 3.1 `PRODUCER_JOIN` rows (`drains` with definition count and flag token, `exempt` with a closed-vocabulary reason) and the bash derivation `join_pairs` (tracked files only, whole-token owner match, four stub arms including the one-hop sourced file).
- [x] 3.2 Checks: missing row, stale row, positional first-statement pin per `drains` definition, recall rows (`luks-monitor.test.sh` with `cryptsetup` derives; the `ssh` stand-in is an `exempt variable-named-verb` row), candidate-row message, `PASS: grep-q-producer-join`, one `JOINED:` line per row.
- [x] 3.3 Fixtures indented or built with `printf` so no column-0 pin text appears; recompute `SWEEP_PROBE_CHECKS` with the header recipe.

## Phase 4 Dynamic control

- [x] 4.1 Sentinel hand-off writer, SIGPIPE ignored and default, bash pipeline, `sh` and bash stub interpreters, accepted spellings (shell-tagged) and non-reading spellings arrays shared with the Phase 3 detector.

## Phase 5 Wording

- [x] 5.1 Rewrite the guard header's producer-side paragraph (what is pinned, the stated limits, the authoritative derivation); list the follow-on slices; do not write that the series is finished.

## Phase 6 Evidence and ship

- [x] 6.1 Mutation rows M1 to M21 and harness rows H1 to H6, one at a time under `ulimit -v 6000000` on a scratch clone (`git add` any added file); rows that run an owner suite go through `scripts/soleur-sandbox.sh run-isolated`.
- [x] 6.2 Pair run of each edited suite at base and head; cheap lints (plan AC-9); `bash scripts/test-affected-kb-consumers.test.sh` once before the push.
- [x] 6.3 decision-challenges.md update; learning if a non-obvious finding occurs.
- [ ] 6.4 PR body per AC-11; `soleur:ship`; post-merge per AC-12 (tracker comment with J0 numbers and command, NOT-fixed list, next slice named; file the affected-edge follow-on).
