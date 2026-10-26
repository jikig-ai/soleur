# Tasks: trim the Inngest host user_data by at least 500 B (#11080)

Plan: `knowledge-base/project/plans/2026-10-26-chore-trim-inngest-user-data-before-host-replace-plan.md`. Decisions: `decision-challenges.md` beside this file. Hard constraint for every task: nothing is replaced, dispatched or read on the Inngest host; the host replace, the resume and the flip are out of scope and each needs its own typed go. Run test suites one at a time with stdin from `/dev/null`.

## Phase 0: Preflight (no edits)

- [ ] 0.1 Rebase onto `origin/main` (never merge main in); re-run `bash apps/web-platform/infra/inngest-userdata-budget.sh --json` and record the baseline (280 B headroom expected)
- [ ] 0.2 Record the template's `ZIREF=` and `IREF=` lines and the `| grep -q` count (4) before editing
- [ ] 0.3 Re-grep the five Description strings and the four message tails across `*.test.*`, `scripts/` and `.github/` for pins added since the plan
- [ ] 0.4 Add the deferred `--min-headroom 300` floor as a new item on #11140 (a comment), before the PR is marked ready

## Phase 1: Red tests first

- [ ] 1.1 In `apps/web-platform/infra/inngest-carrier-vocabulary.test.sh` add `apps/web-platform/infra/cloud-init-inngest.yml` to `DELIVERY_FILES`
  - [ ] 1.1.1 Add the Guard 1 mutation rows (unmodified template, bare stem, STAGED re-add, quiesce-loop re-add after a compliant first member, brace form, snake and upper-case spellings, file removed)
  - [ ] 1.1.2 Add the must-PASS rows (stem in a whole-line comment stays GREEN; a code line with a trailing comment naming the stem is RED) (no new negative control; the existing `neg-*` controls stand)
  - [ ] 1.1.3 Replace the header's "NOT COVERED (1)" paragraph
  - [ ] 1.1.4 Run the suite: the real-tree row is RED with 6 stem hits (the failing test for change A)
- [ ] 1.2 Prepare the quiesce-battery adaptation in `apps/web-platform/infra/cloud-init-inngest-provision-unit.test.sh`: T4 on the flip timer; drop Q2 and Q3 and the `luks-cutover` fixture state; keep Q1, Q4, Q5 (flip flag only); re-point `Q_OPEN` and the G2-r14 mutation row; take row counts from an executed run (the header says 83, the suite reports 88)

## Phase 2: Template edits (`apps/web-platform/infra/cloud-init-inngest.yml`), measure after each step

- [ ] 2.1 A1: drop the three `inngest-luks-cutover.*` names from `STAGED=` (keep `cat-inngest-cutover-state.sh`); expected headroom 292 B
- [ ] 2.2 A2: quiesce block loops, stops and checks the flip timer and service only; delete the `frozen-active` busy line; drop the cutover timer from the service-status list; rewrite the comment above the block; expected 376 B
- [ ] 2.3 A3: delete the `/etc/default/inngest-luks-volumes` write and `grep -qx` lines and their comment; expected 428 B
- [ ] 2.4 B: shorten the five untested Descriptions (nftables, bs-token-restage, provision.timer, config-refresh.service, config-refresh.timer); leave the LUKS-open and provision.service Descriptions untouched; expected 528 B
- [ ] 2.5 C: cut the four logger message tails to marker + fields + `#7228`, moving the prose into whole-line `#` comments above each line with no `${` or `%{` in them; expected 800 B
- [ ] 2.6 Confirm the headroom is at least 780 B (`jq -e '.headroom >= 780'`); if short, re-measure after the rebase; blank-line removal (about 90 B) closes a shortfall of up to about 90 B only; if C had to be reverted the floor is not reachable here, so stop and re-ask the CTO (note P4)
- [ ] 2.7 Runbook sync: `knowledge-base/engineering/operations/runbooks/inngest-server.md` marker rows say what the removed tails said (add only if missing)

## Phase 3: Verification (one suite at a time)

- [ ] 3.1 Quick suites: `inngest-carrier-vocabulary`, `inngest-host`, `inngest-boot-emitter`, `cloud-init-inngest-bootstrap`, `inngest-redis-luks`, `inngest-redis-luks-loopback` (needs root and a loop device; record if unavailable), `journald-config`, `inngest-config-refresh`, `templatefile-bare-dollar-guard`, `credential-persist-home-guard`, `doppler-injection-bound`, `cloud-init-ghcr-seed-login`, `cloud-init-web-zot-seed`, `web-zot-consumer-probe`, `inngest-nic-wait`, `inngest-cutover-flip`, `inngest-server-flip-guard` (all `apps/web-platform/infra/*.test.sh`)
- [ ] 3.2 Slow suites in the background with a completion wait: `cloud-init-inngest-zot-pull-mutation.test.sh` (about 227 s), `cloud-init-inngest-provision-unit.test.sh` (about 4 min; prints `PROVISION_UNIT_SUITE_OK`)
- [ ] 3.3 Required-CI set: `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts`, `bun test plugins/soleur/test/terraform-target-parity.test.ts`, `bash .claude/hooks/grep-q-pipe-guard.test.sh`, `python3 scripts/lint-encryption-posture.py --repo-sweep`, `bash tests/scripts/test-argv-bearer-sweep.sh`, `bash .github/scripts/validate-infra-templates.sh apps/web-platform/infra`
- [ ] 3.4 Run the plan's AC1 to AC8 commands and record each result

## Phase 4: Ship (the merge needs the owner's typed go; no dispatch of anything)

- [ ] 4.1 PR body: baseline and per-step headroom, the CI log line of `inngest-userdata-budget`, the web-redeploy notice, the "PR-time plan shows the host as replaced, known drift" sentence, the Better Stack alert-definitions gap, `Closes #11080`, `Ref #11140`, `Ref #10390`, `Ref #10112`, `Ref #10975`
- [ ] 4.2 Pre-merge gate: parity green on the trial merge; no `ZIREF` or `IREF` line changed; headroom at least 780 B on the rebased branch; CI budget job green
- [ ] 4.3 After merge: read the push-apply run for the merge sha (success, no `hcloud_server.inngest` in plan or refresh, 0 changes) and the Better Stack no-new-boot check with the window starting before the merge; attach both to the PR; on any deviation file an `action-required` issue and stop
