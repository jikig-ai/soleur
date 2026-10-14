# Tasks — feat-one-shot-6604-workspaces-plaintext-wipe

Plan: `knowledge-base/project/plans/2026-09-28-feat-workspaces-plaintext-volume-wipe-plan.md`
Issues: #6604 (step 7), #6588 (infra half). PR A uses `Ref #6604` / `Ref #6588` — never `Closes`
(the closures ride PR B, after the dispatch). ADR-119 `status:` must NOT change in PR A.

Decision record: `knowledge-base/project/specs/feat-one-shot-6604-workspaces-plaintext-wipe/decision-challenges.md`.

## Phase 1 — RED tests first (PR A)

- [x] 1.1 `apps/web-platform/infra/workspaces-luks-wipe.test.sh` on `workspaces-luks-harness.sh`:
      Guards 1, 2, 3 (stubbed rows), 5 as cases; `harness_floor` at the measured count. Harness
      requirements (plan Phase 1): `PATH` tripwires for `blkdiscard`/`dd`/`doppler`/`aws`,
      `systemd-run` pass-through stub, device-resolution seam (not env-settable), stub fidelity
      (`cryptsetup` stdin compare, per-path `luksUUID`, `blkid` TYPE/LABEL + rc 0/2/4/8, per-unit
      `systemctl show`, realistic `list-dependencies`, `cmp` stdout), `STUB_UNKNOWN_FLAG`, exact
      `reason=` per RED row, reason-slug census, instrument self-test H1.
- [ ] 1.2 `workspaces-luks-loopback.test.sh`: small loop device (multiple of 512, not of 4 MiB), real
      `mkfs.ext4 -L workspaces_plain`; zero + read-back GREEN; non-zero byte at fixed offsets RED;
      interrupted zero resumes (`arm=re_zero`); `blkdiscard` command line fails `EBUSY` on an
      open-LUKS and on a mounted loop device; capture real `list-dependencies` output.
      *(Written as Session W, LW1–LW7, `bash -n` clean; needs root + loop devices, so it runs in CI
      only — `infra-validation.yml` deploy-script-tests. Left unticked until CI shows it green.)*
- [x] 1.3 `workspaces-luks-cutover-workflow.test.sh`: job set `{preflight, cutover, wipe}`; `cutover`
      env expression byte-identical and first `environment:` line; `cutover` `if:` predicate;
      `CONFIRM_WIPE = wipe_plaintext && dry_run`; `wipe` unconditional environment; Guard 6 rows.
- [x] 1.4 New workflow test for `workspaces-plaintext-forget.yml`: Guard 4 rows (incl. presence proof,
      no state printed/stored, exact type/name selection, serial/lineage), concurrency literal,
      `infra-privileged`, constant pin, `TERRAFORM_VERSION`. Workflow behavior rows run `yq`-extracted
      step bodies against a `curl` stub.
- [x] 1.5 Tier census: `STATE_WRITE` widened to `state (rm|mv|push)`; `terraform-target-parity.test.ts`
      covers the forget workflow.

## Phase 2 — Script (PR A)

- [x] 2.1 `wipe_plaintext()` Stage 1 (W0–W2), Stage 2 arm table (`first_wipe`/`re_zero`/`detached`,
      explicit `blkid -p` rc map, `crypto_LUKS` refused on every arm), Stage 3 (W3–W12) per plan §A
      incl. W5 restorability (test-passphrase on the file + fresh `luksHeaderBackup` cmp, shred on
      every exit), W6 `ID_SERIAL`, W6b all `SysFSPath` units, W7 service/job, `result=begun` /
      `readback_start` rows, `systemd-run --scope` io.max cap; `emit_wipe()` single row format;
      heredoc `.env` inputs with duplicate-key refusal.
- [x] 2.2 Mode block after CLEAN_STRAY; never assigns `DRY_RUN`; never sets the cleanup globals.
- [x] 2.3 `cleanup()` `wipe_aborted` arm + `mode=wipe`; run-step `::error::` lists it.
- [x] 2.4 ROLLBACK refusal on `PLAINTEXT_WIPE_BEGUN`/`PLAINTEXT_WIPED` (explicit row + `trap - EXIT`);
      check `arm_dead_man` reachability, refuse there too or drop with a note.
- [x] 2.5 Header comment points at the mode.

## Phase 3 — Workflows (PR A)

- [x] 3.1 `workspaces-luks-cutover.yml`: inputs (env-only into `run:`); `dry_run` description;
      preflight order (exclusion → pin shape → token → presence proof → `api_state` → banner,
      `-w '%{http_code}'` status reads, escaped `.error.code` only).
- [x] 3.2 `cutover` wipe-rehearsal wiring (`${{ (inputs.wipe_plaintext && inputs.dry_run) && '1' || '0' }}`),
      job-level `if:`, `.env` re-validation before the heredoc.
- [x] 3.3 `wipe` job: loader, presence proof, re-GET, pause-is-real check (both workflows
      `disabled_manually`, no queued run), same-day verify run, labels-PUT probe — all before web-1;
      bridge (`unset HCLOUD_TOKEN`) + heredoc `.env` + run with `ServerAliveInterval`,
      `::stop-commands::`, `PIPESTATUS` rc, strict success-row regex tied to `api_state`;
      detach/poll/delete/404 with token via `--config -`; `timeout-minutes: 240`; summary.
- [x] 3.4 `workspaces-plaintext-forget.yml` per plan §C (constant pin; xtrace refusal; copied
      extract+init steps; presence proof + 404 + empty name + pause check; `state pull` piped only into
      a field-selecting `jq`; `state rm`; serial/lineage + list diff).
- [x] 3.5 `actionlint` both workflows; tier census; version parity.

## Phase 4 — Docs (PR A)

- [x] 4.1 Runbook step 7: commands, pause/un-pause, approval (and delegation limits), freeze, verdict
      table with irreversible?/re-dispatch-safe?/next-action columns (halt-and-escalate where no
      webhook verb exists); summary prints the anchor; Step 0 marked never-after-step-7.
- [x] 4.2 ADR-119 addendum (AP-009 superseded-copy basis, AP-001 deviation, two-PR ordering + TF
      measurements, pause-not-guard and #6919/T55, operand rule kept, duplicated delivery block).
- [x] 4.3 ADR-241 D2 one-line note.
- [x] 4.4 `model.c4` edges `github -> hetzner`, `hetzner -> cloudflare`; C4 syntax/render/count-parity tests.
- [x] 4.5 Destruction-record template (`status: template`, CLO field set).
- [x] 4.6 CODEOWNERS rows if required; a test that every `reason=`/`arm=` token in the plan's
      Observability section exists in `workspaces-cutover.sh`.
- [ ] 4.7 AC check: no `*.tf`, filter or `apply-web-platform-infra.yml` diff; web-platform plan counts
      equal `main`'s baseline.
      *(First half verified locally: the three-path diff is empty and ADR-119 `status:` is unchanged.
      The plan-count half is `infra-validation`'s web-platform plan in CI; left unticked until read.)*

## Phase 5 — Ship PR A, prepare PR B, stop (post-merge)

- [ ] 5.1 Merge PR A; wait for the release and push apply.
- [ ] 5.2 Draft PR B (server.tf narrowing + sentinel, forget-workflow deletion, ledger row).
- [ ] 5.3 Same-day `workspaces-luks-verify.yml` baseline.
- [ ] 5.4 Rehearsal dispatch (autonomous, read-only); watch it.
- [ ] 5.5 STOP: one operator go-ahead naming the full command set (plan Phase 5 step 5).

## Phase 6 — After the go-ahead

- [ ] 6.1 Pause both push-apply workflows; dispatch D; approval; watch.
- [ ] 6.2 Dispatch the forget workflow; watch.
- [ ] 6.3 Off-host verification (API 404, server volumes, verify run vs same-day baseline, Sentry,
      uptime, `scheduled-prod-version-drift.yml`, Better Stack rows for the dispatch).
- [ ] 6.4 Finish PR B (destruction record → ADR `accepted`, legal sweep CLO-attested, expenses,
      job-rationale runbook, C4 description, #6931 delete-protection comment); merge same day.
- [ ] 6.5 Re-enable both workflows; `manual-rerun` apply; drift green; `GET ?name=` → `[]`.
- [ ] 6.6 Evidence comments on #6604 / #6588; #6897 item 1 update; sweeper closes #6604.
