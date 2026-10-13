# Tasks: git-data first-boot bootstrap tolerates a late volume attachment

Plan: `knowledge-base/project/plans/2026-10-13-fix-git-data-bootstrap-volume-attach-race-plan.md`
Branch: feat-one-shot-git-data-bootstrap-attach-race (draft PR #10210). Issue context: #10138.
No task in this file dispatches a workflow, runs terraform apply, writes Doppler, or touches a host.

## Phase 0: RED tests first (git-data-bootstrap-store-verify.test.sh)

- [x] 0.1 Add extraction rows for the new `# ---- BEGIN/END attach-wait helper ----` sentinels (exactly one pair, helper syntactically valid, line floor) and prepend the extracted helper to the harness prelude
- [x] 0.2 Add a `sleep` stub (logs each call; on its Nth call creates the by-id link) and extend the `blockdev` stub with `--getsize64`
- [x] 0.3 Add `blockdev --getsize64 <origin>` to the origin-call allowlist as a pre-`--setro` identity probe (Guard 1 row 7)
- [x] 0.4 Rows: late link proceeds with the on-time verdict; link appears on 1st and last-before-bound sleep; link via symlink chain; bound 0 with link present (one probe, no sleep)
- [x] 0.5 Rows: never appears -> unchanged FATAL, no marker, stage=bootstrap emit, no setro/dmsetup/mount call, sleeps <= ceil(bound/10)
- [x] 0.6 Rows: invalid bound (`abc`, `-5`, empty) refused with its own FATAL before the first probe; empty plaintext id -> no wait
- [x] 0.7 Rows: add `luks-discover unit` sentinels + a second extraction; LUKS discovery wait (plaintext present first, LUKS device appears on pass 3) and its never-appears FATAL
- [x] 0.8 Mutation rows 1-10 (incl. probe-once-then-sleep) of Guard 1 (landed-check + instrument self-test each); harness rows (never-materialising stub paired with the late-link row)
- [x] 0.9 Confirm every new row is RED against the current script

## Phase 1: Bootstrap helper, call sites, seam strip

- [x] 1.1 `git-data-bootstrap.sh`: add `_gd_attach_wait` above section 1 (`${VAR-300}`, `^[0-9]{1,4}$` with `10#`, `&&`-chain predicates, direct call, re-resolve `_pt_dev`; validate bound, probe-once at 0, `udevadm settle --timeout=5 || true`, `sleep 5`, count 10 per pass, log start/resolution, return 1 after the bound)
- [x] 1.2 Plaintext site: wait on `realpath -e` + block-special + `getsize64 > 0`; unchanged FATAL after the bound; verification untouched
- [x] 1.3 LUKS site (section 1): predicate re-runs the glob + `cryptsetup isLuks` scan each pass; keep the `luksOpen --key-file -` line byte-identical (B19d)
- [x] 1.4 `cloud-init-git-data.yml`: add `-u GIT_DATA_ATTACH_WAIT_S` to the bootstrap `env -u` list, BEFORE `-u GIT_DATA_PLAINTEXT_DEV` (census C2 adjacency regex)
- [x] 1.5 `git-data-store-device-census.test.sh`: C2 row for the new seam and bump its floor; Guard 3 mutation rows
- [x] 1.6 Run the store-verify suite GREEN; set `MIN_ASSERTIONS` equal to the measured `passes + fails`

## Phase 2: First-boot LUKS wait in the template

- [x] 2.1 `cloud-init-git-data.yml` luks_open heredoc: 30 -> 300 counted iterations, `udevadm settle --timeout=2 || true` every 10th pass, keep `-b "$DEV"` + size > 0 predicate and the isLuks rc=4 FATAL
- [x] 2.2 `git-data-luks.test.sh` B18 (i): pin the new literal, add the settle-call row and Guard 2 mutation arms
- [x] 2.3 Re-run `git-data-runcmd-rehearsal.test.sh`, `git-data-template-strip.test.sh`, `git-data-render-strip-parity.test.sh`
- [x] 2.4 `bash apps/web-platform/infra/git-data-userdata-budget.sh --json` and `plugins/soleur/test/cloud-init-user-data-size.test.ts`; record headroom (pre-change 2,656 B)

## Phase 3: Rehearsal harness late attachment

- [x] 3.1 `rung2-rehearsal/variables.tf`: `rehearsal_attach_delay_s` (default 0, validated 0-240)
- [x] 3.2 `rung2-rehearsal/rehearsal.tf`: `terraform_data.rehearsal_attach_delay_luks` / `_pt` (no `count`; sleep = payload ? var : 0, delay in `environment`, `triggers_replace` = server id only); both attachments depend on them (LUKS floor(delay/2), plaintext full delay)
- [x] 3.3 `.github/workflows/git-data-rung2-rehearsal.yml`: single job-level `TF_VAR_rehearsal_attach_delay_s: "150"` line, no rationale prose (ADR-231 byte budget)
- [x] 3.4 `scripts/git-data-rung2-plan-shape.sh` host-only: admit an exact-match replace of the two delay addresses; `tests/scripts/test-git-data-rung2-plan-shape.sh` rows incl. glob-rejection, `[0]` rejection, fixtures from a real `terraform show -json`
- [x] 3.5 `git-data-rung2-rehearsal.test.sh`: rows for phase gating, default 0, triggers, both attachments depending on a delay resource (Guard 4)
- [x] 3.6 `terraform validate` and plan-only checks in the rehearsal root at delay 0 and 150; rely on `git-data-rung2-rehearsal.test.sh` step-bound pins (apply 15/25/15, capture 16 min) for +150 s

## Phase 4: Docs and ADR

- [x] 4.1 `git-data-luks-cutover-5274.md`: dated entry for run 38384137515 (measured timeline; inherited items labelled), recovery order, #10207 interaction
- [x] 4.2 `git-data-rung2-rehearsal.md`: the deliberate late attachment and what a PASS now implies (inference, not a measurement)
- [x] 4.3 `soleur:architecture`: amend ADR-239; confirm `bash plugins/soleur/test/c4-count-parity.test.sh` green (no C4 edit)

## Phase 5: Handoff (no dispatch)

- [ ] 5.1 Compute and record the new payload digest (`git_data_rung2_user_data_sha256 apps/web-platform/infra/cloud-init-git-data.yml`) in the PR body; state the gate reads HOLD until the evidence PR lands
- [x] 5.2 PR comment on #10207 about the `stale_boot_complete` wedge (no #10207 file edited)
- [x] 5.3 Run the full local suite list from the plan's Acceptance Criteria; lint (`scripts/lint-guard-contract.py`, markdownlint on touched docs)
- [ ] 5.4 PR body lists the rehearsal / replace / rotate commands as UNRUN and gated on a go-ahead that names each command

## Review-round amendment (2026-10-13)

Tasks 0.4-0.8 (bound 0, ceil(bound/10), invalid-bound rows, rows 1-10), 1.1 (seam, `settle --timeout=5`, `sleep 5`), 1.3 (the section-1 LUKS site), 1.4, 1.5, 3.4 (`[0]` rows beyond the kept refusals), 3.6 (the step-bound pins now sit in the restored job-budget arm) and the section-1 / seam / in-loop-settle parts of 2.1, 2.2 and 3.x were
implemented and then superseded by the CTO's review-round ruling (see `decision-challenges.md`): the
seam, the section-1 LUKS wait, the census change and the in-loop settles no longer exist; the heredoc
keeps one post-loop settle. The plan's amendment banner lists the shipped design.
