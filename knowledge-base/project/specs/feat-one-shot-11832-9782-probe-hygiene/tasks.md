---
branch: feat-one-shot-11832-9782-probe-hygiene
plan: knowledge-base/project/plans/2026-11-03-chore-followthrough-probe-hygiene-plan.md
issues: [11832, 9782]
---

# Tasks — follow-through probe hygiene (#11832 + #9782)

## Phase 1 — Retire inngest-trace-retention-5150 (#11832)

- [ ] 1.1 Delete `scripts/followthroughs/inngest-trace-retention-5150.sh` and `scripts/followthroughs/inngest-trace-retention-5150.test.sh` (`git rm`).
- [ ] 1.2 In `scripts/test-all.sh`, delete the `#5150` comment block + `run_suite "scripts/followthroughs/inngest-trace-retention-5150" …` line (block at ~:6016-6019).
- [ ] 1.3 In `scripts/lib/test-affected-paths.sh`, delete the `"scripts/followthroughs/inngest-trace-retention-5150.sh"` row inside `AFFECTED_SCRIPTS_BETTERSTACK_EMITTER_READ_PATHS` (~:3346).
- [ ] 1.4 In `scripts/lint-betterstack-emitter-read.sh`, delete the `ALLOW["scripts/followthroughs/inngest-trace-retention-5150.sh"]` rationale row (:158) — the STALE arm (:325-335) fails CI while it names a missing file.
- [ ] 1.5 Verify: `git grep -n 'inngest-trace-retention-5150' -- scripts/ plugins/` returns zero hits; `bash scripts/lint-betterstack-emitter-read.sh` exits 0.

## Phase 2 — Repair inngest-cli-apply-window-7463 (#9782)

- [ ] 2.1 In `scripts/followthroughs/inngest-cli-apply-window-7463.sh` (~:74-94): split the `gh api --paginate` capture from the `jq` parse (two-step, so transport failure is countable); guard the jq term as `[.[].jobs? // [] | .[] | select(.name | test("inngest.host.replace"; "i")) | .conclusion][]`; add `jobq_total`/`jobq_failed` counters (`var=$((var + 1))`, never `((var++))`); after the loop, exit 3 `CANNOT-ESTABLISH` when `jobq_total > 0 && jobq_failed == jobq_total`. Keep all existing exit semantics and the xtrace refusal.
- [ ] 2.2 Create `scripts/followthroughs/inngest-cli-apply-window-7463.test.sh` on the `git-data-boot-poll-8178.test.sh` donor shape: PATH-shimmed `gh` answering per-arm fixtures (`pr.json`, `runs.json`, `jobs-<id>.json`, `<name>.fail`), exit 64 on unwritten argv, instrument self-test, byte-identical `assert_fixture_dir`, `env -i` probe invocations. Arms: all-fail → rc 3; `.jobs`-absent/null payload → no jq crash, correct NOT-YET/FAIL; replace-success + post-dating green health → rc 0; replace failed/cancelled → rc 1; no post-merge dispatches → rc 2; health run pre-dating replace → no PASS; `.jobs: []` present-but-empty → GREEN (permitted member).
- [ ] 2.3 Honor convention-suite landmines: no `| grep -q` pipes, no `env -u`, no literal `<<-`, `\x24\x24` not `$$` in unquoted `<<PY`, six-assignment floor windows, mutate fragments byte-match via `grep -F`.
- [ ] 2.4 Register the suite: add `run_suite "scripts/followthroughs/inngest-cli-apply-window-7463" bash scripts/followthroughs/inngest-cli-apply-window-7463.test.sh` + convention comment in `scripts/test-all.sh`.

## Phase 3 — Regenerated registries & verification battery

- [ ] 3.1 Run `python3 scripts/regenerate-shard-manifest.py --incremental --write`; confirm `suite-durations.tsv` + `suite-shard-legs.tsv` drop the 5150 rows and gain a 7463 row.
- [ ] 3.2 Run `bash scripts/followthroughs/inngest-cli-apply-window-7463.test.sh`, `bash scripts/lint-orphan-test-suites.sh`, `bash scripts/lint-betterstack-emitter-read.sh` — all exit 0.
- [ ] 3.3 Run `bash plugins/soleur/test/fixture-relative-assert.test.sh`; if it reds on site-count drift, regenerate with `--write-baseline` and re-run.
- [ ] 3.4 `shellcheck -S warning` on every touched `.sh`; `bash -n` clean.
- [ ] 3.5 Grep-verify the plan's "already present"/count claims before committing (per the 2026-11-03 census learning).

## Phase 4 — Post-merge bookkeeping (agent-executable `gh` calls; ship or work may run)

- [ ] 4.1 Strip the `<!-- soleur:followthrough … -->` directive from #5150's body (`gh issue view 5150 --json body` → edit → `gh issue edit 5150 --body`).
- [ ] 4.2 Post a checklist-refresh comment (or body edit) on epic #10390 ticking confirmed-CLOSED rows: #8595, #8841, #9139, #8874, #8316, #9705, #8764, #10136 — plus #11832 and #9782 on closure.
