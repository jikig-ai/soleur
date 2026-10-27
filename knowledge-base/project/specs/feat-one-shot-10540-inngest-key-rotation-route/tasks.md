# Tasks: Inngest key rotation apply route (#10540)

Plan: `knowledge-base/project/plans/2026-10-27-feat-inngest-key-rotation-apply-route-plan.md`

The change delivers the route only. No task dispatches `rotate` or `converge`, applies anything to production, reads a secret value, or posts `S5-A5-DONE`.

## Phase 0: Verify before building (read-only)

- [ ] 0.1 On a throwaway Terraform root confirm a `-replace` plan of a `random_id` plus `doppler_secret` pair prints `hex` and `id`; record the sentinel strings the suite will use.
- [ ] 0.2 Read `.github/actions/infra-credentials/action.yml`: exported names (`DOPPLER_TOKEN_TF`, `HCLOUD_TOKEN`, `TF_STATE_AWS_*`) and whether `TF_VAR_inngest_link_tls` is exported with `doppler run -c prd_terraform --name-transformer tf-var`.
- [ ] 0.3 Check whether `scripts/inngest-link-flip.sh` helpers (idle guard, bearer-curl) are sourceable; else duplicate and pin parity.
- [ ] 0.4 Read `scripts/betterstack-query.sh`, `scripts/lib/betterstack-read-classify.sh` and `tests/scripts/test-infra-privileged-tier-census.sh` (Guards 1/2/4) for what a new Tier-B workflow must carry.
- [ ] 0.5 Read all three C4 files before the C4 edit.
- [ ] 0.6 Verify whether `inngest-link-flip.sh flip` can start from a flag at `1`.
- [ ] 0.7 Read the rehearsal runbook's reboot leg and `inngest-bootstrap.sh` for LUKS-reopen evidence and a Doppler fallback cache on the dedicated unit.
- [ ] 0.8 Confirm provider `-replace` order for `doppler_secret` and that `-replace` with `ignore_changes=[value]` creates with the new value.

## Phase 1: Terraform derivation (RED first)

- [ ] 1.1 `inngest.test.sh`, `inngest-host.test.sh`: app value expressions equal the dedicated expressions; dedicated pair has no `lifecycle`; `ignore_changes=[value]` kept on the app pair (RED on unedited `inngest.tf`).
- [ ] 1.2 `terraform-target-parity.test.ts`: closure gains the `random_id.*_dedicated` edge with no `hcloud_*` member; `inngest_host` shape gate still refuses `random_id` touches; add the new workflow to the file list beside `WEB_PLATFORM_WORKFLOW` / `DEPLOY_PIPELINE_FIX_WORKFLOW`; update the exclusion comment on the dedicated pair.
- [ ] 1.3 Edit `inngest.tf`: two value expressions, SHARED-CHANNEL CONTRACT comment, closing NOTE, retired-resource comment on the `_prd` `random_id`s (tracked #11293).

## Phase 2: Script (`scripts/inngest-key-rotate.sh`), test-first against stubs

- [ ] 2.0 First, the `--print-contract` mode (prints `inngest-key-rotate verdict-tokens` plus the fixed token list; offline, no credentials, under 15 seconds): it is the plan's `discoverability_test.command` for preflight Check 10.
- [ ] 2.1 Refusal ladder (confirm format, `run_attempt`, `quiet_window`, link flag `1`, soak #11215, in-flight runs, server name + IP, pre-reboot SERVING for `rotate`); `plan` reports booleans only.
- [ ] 2.2 `kr_tf` wrapper (streams to a file, `TF_LOG` unset, never printed or uploaded), `kr_scrub` for short error bodies, Gate A and Gate B built from one table, exact addresses/actions/count.
- [ ] 2.3 Value-silent compare (hash on the pipe, booleans only).
- [ ] 2.4 Reboot function: one POST latch, Hetzner action poll, 10-minute new-`boot_id` wait, 15-minute SERVING + `tls-health` read via `inngest-host-state.sh` / `betterstack-query.sh`.
- [ ] 2.5 Redeploy driver via `track.sh`; converge derivation from the newest non-plan run that reached apply1; Hetzner action-list check; stop sentences with the exact converge command; issue filing; `S5-A5-DONE` line and evidence block printed only.
- [ ] 2.6 BUDGET TABLE (apply1, reboot POST + 10-minute new-boot wait + 15-minute read, apply2, redeploy bounded by the 4800-second pipeline ceiling). The guard takes the read-only Hetzner key; only the reboot step receives the write key.

## Phase 3: Workflow and static suite

- [ ] 3.1 `.github/workflows/inngest-key-rotate.yml`: dispatch-only, `run-name` with mode and keys, workflow group `inngest-key-rotate`, jobs `guard`, `apply1`, `reboot`, `apply2`, `redeploy` with per-job credential binding and `needs`/`if` graph.
- [ ] 3.2 `apps/web-platform/infra/inngest-key-rotate-workflow.test.sh`: parsed-YAML posture, the four Guard Contract mutation batteries and harness rows, sentinel test, no `restart-inngest-server.yml` reference, reboot step `env -i` + one POST.

## Phase 4: Link-flip guard

- [ ] 4.1 `flip_apply_flag off` check (any non-plan run, `--limit 200`), `confirm_off_after_rotation` input in `inngest-link-flip.yml`, rows in `inngest-link-flip-workflow.test.sh`; `flip` refusal after a rotation if 0.6 shows it can start from `1`.

## Phase 5: Registrations and records

- [ ] 5.1 `infra-credential-tiers-8209.md` rows; census; `tests/scripts/trio-baseline.tsv`; `web-hosts-fanout-parity.test.sh` operand; `infra-validation.yml` paths.
- [ ] 5.2 ADR-304 (via `soleur:architecture`; re-verify the ordinal against `origin/main`); ADR-100 §4 amendment; ADR-294 one-line pointer.
- [ ] 5.3 `model.c4` `github -> hetzner` edge text; run the C4 validation tests and `c4-count-parity.test.sh`.
- [ ] 5.4 Runbook rewrite (A5 row, order step 3, Key rotation, Rollback step 3, evidence wording, between-phases note, follow-ups table); owner-ask probe text and its suite.

## Phase 6: Local verification only

- [ ] 6.1 Run every touched suite, `terraform fmt -check` and `validate`, `lint-infra-no-human-steps.py`, `workflow-file-size`; confirm no dispatch of `rotate` or `converge` anywhere.
- [ ] 6.2 PR body: `Ref #10205`, `Closes #10540` only if AC1-AC8 hold and #11292/#11293 exist; arm merge with `gh pr merge --squash --auto`; never push to a queued PR.

## Post-merge (read-only)

- [ ] 7.1 One `mode=plan` dispatch; `verdict=plan_ok`; no key-shaped string in the log.
