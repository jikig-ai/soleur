# Tasks: grep -q pass 2 for the NIC guard and the egress-enforce probe

Plan: `knowledge-base/project/plans/2026-10-07-fix-grep-q-pass2-nic-guard-egress-probe-plan.md`
Series: Ref #9217 (tracker), #7005, #6601, #7376, #7797, #9482, #9638, #9639. Never `Closes`.

## Phase 0 — Characterization rows (green before AND after the conversion)

- 0.1 Read the control line first: run both suites on the unconverted scripts and record totals (56 and 154).
- 0.2 `cron-egress-enforce-probe.test.sh`: add stub knobs (`STUB_PS_NAMES`, `STUB_NFT_OUT`, both emitted with `printf '%s\n'`; `\$` escapes inside the double-quoted `mk_stub` bodies).
- 0.3 Add rows P2-2 (near-miss names), P2-3 (non-canonical must-pass), P2-4 (jump absent), P2-6 (no bare count on stdout); in the P2-4 `docker exec` check use `grep -c "^docker.exec"` (TAB-separated log).
- 0.4 `web-private-nic-guard.test.sh`: add section with W-1 (`-w` near-miss), W-2 (`-F` lookalike), W-4 (IMDS near-miss, `imds_nets=1`), W-5 (address appears on the second call; call-counting `ip` stub, exact count 3, counter file created before `run_guard`), W-6 (`-z "$OUT"` in the healthy and the absent-start runs).
- 0.5 No new row may contain a pipe-fed early-exit grep (the `apps/web-platform/*.test.sh` row has zero slack).
- 0.6 Run both suites against the UNCONVERTED scripts: all rows green. Record totals.
- 0.7 Raise both `MIN_CASES` literals (`:288` and `:553`) to the new exact totals, in place, on the line above the `if`.
- 0.8 Run `bash scripts/guard-vacuity-floor.test.sh` and `bash .claude/hooks/grep-q-pipe-guard.test.sh` before the first commit.

## Phase 1 — The six conversions

- 1.1 `web-private-nic-guard.sh` lines 55, 61, 78, 80: `grep -q...` to `grep -c... >/dev/null`.
- 1.2 `cron-egress-enforce-probe.sh` lines 86, 100: same form.
- 1.3 Add one short comment per script above the first converted site (no literal pipe-into-`grep -q` text).
- 1.4 Re-run the exit-status equivalence table (bash and dash, 8 inputs x 2 patterns); keep the output for the PR body.
- 1.5 Do not touch any `curl`, `emit_fail`, xtrace, `INGEST_URL_PINNED` or Sentry transport line.

## Phase 2 — Ledger

- 2.1 `.claude/hooks/grep-q-pipe-guard.test.sh`: delete rows at `:463-464` and the comment block at `:458-462`.
- 2.2 `GATED_PROD_ROWS=8` to `6` (`:898`).
- 2.3 Narrow any header or Wave A2 sentence that names these files or counts rows.

## Phase 3 — Verification (record in the PR body)

- 3.1 Both extended suites, the hook suite, the vacuity suite, `private-nic-guard.test.sh`, `betterstack-send-failed-alert-mutation.test.sh`.
- 3.2 Lints by their own invocation: credential-refusal `--changed --base origin/main`, `lint-shell-capture-exit.py`, repo-wide run.
- 3.3 Hand-applied mutants on scratch copies after reading the control line: G1-1..G1-3, H1-1, G2-1..G2-9, H2-1.
- 3.4 Discoverability command prints `0`.
- 3.5 `bash scripts/test-all.sh --affected` if the host allows; otherwise the PR body states verbatim: "Local `--affected` was skipped on this contended host; CI is the gate."
- 3.6 Add nothing to `plugins/soleur/skills/work/SKILL.md` (60 bytes of headroom).

## Phase 4 — Ship tail

- 4.1 One learning under `knowledge-base/project/learnings/test-failures/` (characterization rows; no `pipefail` so no live misread).
- 4.2 Evidence comment on #9217: commands and numbers, NOT-fixed list, corrected Class W premise, terminal-state statement, #9529 `MIN_CASES` sequencing note.
- 4.3 PR body: first line says whether merging alone mutates production; `Ref` lines only; NOT-fixed list; equivalence table; site 4 labelled an equivalent mutant.
- 4.4 Labels `semver:patch`, `app:web-platform`, `type/chore`, `domain/engineering`; no `[skip-deploy-fix-apply]`, `[skip-web-platform-apply]`, `[ack-destroy]` in any commit message.
- 4.5 Ship tail in order: `Filed:` line, Merge Danger (`Undo:`, `Blast Radius:`), Pipeline Tally, Changelog, Model Dissents, then `soleur:postmerge`.
- 4.6 Post-merge: apply run's SSH-stage notification step skipped and `private_nic_guard_install` replaced; heartbeat `soleur-web-nic-guard-web-1` up.
