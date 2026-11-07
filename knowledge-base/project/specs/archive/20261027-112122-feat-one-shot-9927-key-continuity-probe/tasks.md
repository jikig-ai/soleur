# Tasks - Inngest on-host LUKS key-continuity probe (#9927 item 2)

Plan: `knowledge-base/project/plans/2026-10-26-feat-inngest-luks-key-continuity-probe-plan.md`
Branch: feat-one-shot-9927-key-continuity-probe. Draft PR: #11260. `Ref #9927` only (items 1, 3 to 8 remain open).
Standing constraints: no host replace, no Hetzner/Doppler/Supabase write, no bundle build or digest promotion (owner hold, D9), no `op=resume`, no #10382; no `user_data`, STAGED, `DEST_SPEC` or image-pin change; never `git add -A`; no git stash; commits end with the Co-Authored-By line; PR bodies end with the generated-with line; never print or paste a secret.

## Phase 0 - Setup

> **Superseded in part (D12, review D13 to D17):** tasks 1.3 (dead-man SQL structure), 3.2 and the dead-man residuals in 4.2 moved to the follow-up PR; 2.1's findmnt form is `${src##*$'\n'}`, not `tail -n1`; the review round added the `at=died` row, `--disable-locks` on every header read, an upstream-stage verdict check and a push-armed alert.

- 0.1 Re-run `bash apps/web-platform/infra/inngest-userdata-budget.sh` on the branch base; record headroom (expect 804 B) for the before/after check.
- 0.2 File the two follow-up issues from the plan (standalone keeper at the next replace, including the dead-man conversion trigger; owner-hold tracker for the bundle delivery with a due date and label `follow-through`); every body `Ref #9927`.
- 0.3 Re-run the workflow census (`git grep -l -E "apps/web-platform/infra/\*\*|betterstack-logs-alerts" -- .github/workflows`) and record it; confirm `apply-deploy-pipeline-fix.yml` paths and `server.tf` `triggers_replace` still hash the script.

## Phase 1 - Tests first (RED)

- 1.1 Create `apps/web-platform/infra/inngest-luks-key-probe.test.sh` (stubs for findmnt, cryptsetup with stdin drain, logger, phone-home, meminfo fixture; real-tool arm on a file-backed LUKS2 container, explicit skip marker if cryptsetup is absent). Cover plan Test Scenarios 1 to 6.
- 1.2 Write Guard 1, 2, 3 mutation rows and harness rows as failing cases before the function exists (Guard 1 row 2 and the disarm are tested outside the `||` context).
- 1.3 Create `apps/web-platform/test/infra/inngest-luks-key-probe-alert.test.sh` (paging SQL, dead-man SQL structure, parameters, `-target` parity), modelled on `inngest-luks-wrong-volume-alert.test.sh`.
- 1.4 Update `inngest-cutover-flip.test.sh` only where the seam-list derivation or counts demand it.

## Phase 2 - The probe (GREEN)

- 2.1 Add `luks_key_probe_tick` and helpers to `inngest-cutover-flip.sh`: subshell isolation (`trap - ERR EXIT; set +eEx; set +o pipefail`, every step tests its own rc), `timeout -k 5` on every external command, stamp (pending token first, skip if that write fails), key presence by `grep -q` and key via `sed | head | tr | cryptsetup --key-file -`, `--disable-locks`, `findmnt -T ... | tail -n1`, `luksDump` memory pre-check, `oom_score_adj=1000`, closed token vocabulary with `at=`, `fail_header` only when `luksUUID` and `isLuks` agree, dual emit.
- 2.2 Call it from the four terminal-noop arm tails only; add new seam names to the `for _seam in` list; fix the stale "sixteen names" comment; amend the header invariant; one `local x=` per line; no `GUARD_REV` bump.
- 2.3 Run the affected suites (flip, new probe suite, carrier-vocabulary, doppler-injection-bound, config-refresh, cutover-inngest-workflow, cutover-latch, vector-admission, journald-config) and `python3 scripts/lint-encryption-posture.py`.
- 2.4 Sandbox rehearsal under a transient unit with the flip service's properties against a loopback LUKS2 device where root exists, with the real `findmnt` and `cryptsetup status`; quote the output in the PR, or write `sandbox: unverified` in the runbook.

## Phase 3 - Alerts

- 3.1 Add the paging alert pair to `betterstack-logs-alerts.tf` (`token=fail_` only, `query_period` 10800) and its `-target` lines in `apply-web-platform-infra.yml`; check `workflow-file-size.test.ts`.
- 3.2 Dead-man: prove the API accepts a 30-day `query_period` (fallback 7 days, then the count-variable form); run the read-only substitution controls (live marker gives 0, empty marker gives 0, shortened window gives 1), record latency, confirm the phone-home row begins with the marker and lands in the same source. Only then add the dead-man pair and its `-target` lines; if this cannot run in the session, split it into its own PR.
- 3.3 Confirm the merge plan read shows only the alert creates plus the known standing drift.

## Phase 4 - Docs and architecture

- 4.1 ADR-282: update the Deferred row, narrow the "LUKS header corrupted" detection cell, add the short dated addendum; one-line pointer in ADR-135.
- 4.2 Runbook `inngest-luks-cutover-6894.md` section 5c "Key-continuity probe (#9927 item 2)": token table, claim limits, key-charset assumption, decision table for a page, dead-man residuals, no-SSH diagnosis path, pre-promotion checks, owner hold steps (bundle dispatch, promotion, first-row read from both channels, rollback by revert plus pre-built higher bundle, probe-carrying bundle before any replace), "no recovery if the header is lost" with the #9927 item 1 link. One cross-reference line in `inngest-config-refresh.md`.
- 4.3 C4: edit the `inngest -> betterstack` edge text and the `inngestRedis` description in `model.c4`; run the C4 suites and `plugins/soleur/test/c4-count-parity.test.sh`.

## Phase 5 - Registries and gates

- 5.1 Register the new suite (`suite-shard-legs.tsv`, `suite-durations.tsv` via `scripts/regenerate-shard-manifest.py --group infra --incremental --write`); verify whether `scripts/lib/test-affected-paths.sh`, `scripts/ci-pr-affected-audit.baseline.tsv` and `.claude/hooks/grep-q-pipe-guard.test.sh` need rows before editing.
- 5.2 Run `python3 scripts/lint-guard-contract.py`, `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`, `bash apps/web-platform/infra/inngest-userdata-budget.sh` (headroom unchanged), and the merge-base diff of `cloud-init-inngest.yml`, `infra-config-install.sh`, `inngest-config-refresh-set.txt` (must be empty).

## Phase 6 - Ship

- 6.1 Open for review with `soleur:engineering:review:user-impact-reviewer` and `soleur:engineering:review:observability-coverage-reviewer`; PR body `Ref #9927`, web-redeploy notice, apply expectation (alert creates from the infra apply; the deploy-pipeline-fix web-host push is expected), owner-hold summary.
- 6.2 Post-merge, automated: infra apply and deploy-pipeline-fix run conclusions (`files_written == files_total`), `git tag --contains <merge-sha> --list 'vinngest-v*'`, alert existence read. Owner holds (not done by this work): pre-promotion checks, bundle build, digest promotion, first `token=ok` row from both channels.
