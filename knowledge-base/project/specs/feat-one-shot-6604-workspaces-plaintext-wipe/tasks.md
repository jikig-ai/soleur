# Tasks — feat-one-shot-6604-workspaces-plaintext-wipe

Plan: `knowledge-base/project/plans/2026-09-28-feat-workspaces-plaintext-volume-wipe-plan.md`
Issues: #6604 (step 7), #6588 (infra half). PR A uses `Ref #6604` / `Ref #6588` — never `Closes`
(the closures ride PR B, after the dispatch). ADR-119 `status:` must NOT change in PR A.

Decision record: `knowledge-base/project/specs/feat-one-shot-6604-workspaces-plaintext-wipe/decision-challenges.md`.

## Phase 1 — RED tests first (PR A)

- [ ] 1.1 `apps/web-platform/infra/workspaces-luks-wipe.test.sh` on `workspaces-luks-harness.sh`:
      Guards 1, 2, 3 (stubbed rows), 5 as cases; real-flag stubs exit 64 on unknown flags;
      `harness_floor` at the measured count.
- [ ] 1.2 `workspaces-luks-loopback.test.sh`: small loop device, real `mkfs.ext4 -L workspaces_plain`;
      zero + read-back GREEN; non-zero byte after zeroing RED; interrupted zero resumes (re-zero arm).
- [ ] 1.3 `workspaces-luks-cutover-workflow.test.sh`: job set `{preflight, cutover, wipe}`; `cutover`
      env expression byte-identical and first `environment:` line; `cutover` `if:` predicate;
      `CONFIRM_WIPE = wipe_plaintext && dry_run`; `wipe` unconditional environment; Guard 6 rows.
- [ ] 1.4 New workflow test for `workspaces-plaintext-forget.yml`: Guard 4 rows, concurrency literal,
      `infra-privileged`, `TERRAFORM_VERSION`.
- [ ] 1.5 Tier census: `STATE_WRITE` widened to `state (rm|mv|push)`; `terraform-target-parity.test.ts`
      covers the forget workflow.

## Phase 2 — Script (PR A)

- [ ] 2.1 `wipe_plaintext()` Stage 1 (W0–W2), Stage 2 arm table (explicit `blkid -p` rc map),
      Stage 3 (W3–W12) per plan §A; `emit_wipe()` own marker; heredoc `.env` inputs.
- [ ] 2.2 Mode block after CLEAN_STRAY; never assigns `DRY_RUN`; never sets the cleanup globals.
- [ ] 2.3 `cleanup()` `wipe_aborted` arm + `mode=wipe`; run-step `::error::` lists it.
- [ ] 2.4 ROLLBACK refusal on `PLAINTEXT_WIPE_BEGUN`/`PLAINTEXT_WIPED` (explicit row + `trap - EXIT`);
      check `arm_dead_man` reachability, refuse there too or drop with a note.
- [ ] 2.5 Header comment points at the mode.

## Phase 3 — Workflows (PR A)

- [ ] 3.1 `workspaces-luks-cutover.yml`: inputs; `dry_run` description; preflight order (exclusion →
      pin shape → token → `api_state` → banner, `-w '%{http_code}'` status reads).
- [ ] 3.2 `cutover` wipe-rehearsal wiring and job-level `if:`.
- [ ] 3.3 `wipe` job: loader, re-GET, labels-PUT probe, bridge + heredoc `.env` + run with
      `ServerAliveInterval`, success-row parser tied to `api_state`, detach/poll/delete/404,
      `timeout-minutes: 240`, summary.
- [ ] 3.4 `workspaces-plaintext-forget.yml` per plan §C (copied extract+init steps; 404 + empty name;
      `state pull` identity; `state rm`; post-diff).
- [ ] 3.5 `actionlint` both workflows; tier census; version parity.

## Phase 4 — Docs (PR A)

- [ ] 4.1 Runbook step 7: commands, pause/un-pause, approval, freeze, verdict table with
      irreversible?/re-dispatch-safe?/next-action columns; summary prints the anchor.
- [ ] 4.2 ADR-119 addendum (AP-009 superseded-copy basis, AP-001 deviation, two-PR ordering + TF
      measurements, pause-not-guard and #6919/T55, operand rule kept, duplicated delivery block).
- [ ] 4.3 ADR-241 D2 one-line note.
- [ ] 4.4 `model.c4` edges `github -> hetzner`, `hetzner -> cloudflare`; C4 syntax/render/count-parity tests.
- [ ] 4.5 Destruction-record template (`status: template`, CLO field set).
- [ ] 4.6 `BASELINE_DECLARED_PROBES` bump with PLACEMENT/TRUTH/NO-SUBSTITUTE comment; CODEOWNERS if required.
- [ ] 4.7 AC check: no `*.tf`, filter or `apply-web-platform-infra.yml` diff; web-platform plan counts
      equal `main`'s baseline.

## Phase 5 — Ship PR A, prepare PR B, stop (post-merge)

- [ ] 5.1 Merge PR A; wait for the release and push apply.
- [ ] 5.2 Draft PR B (server.tf narrowing + sentinel, forget-workflow deletion, ledger row).
- [ ] 5.3 Same-day `workspaces-luks-verify.yml` baseline.
- [ ] 5.4 Rehearsal dispatch (autonomous, read-only); watch it.
- [ ] 5.5 STOP: one operator go-ahead naming the full command set (plan Phase 5 step 5).

## Phase 6 — After the go-ahead

- [ ] 6.1 Pause both push-apply workflows; dispatch D; approval; watch.
- [ ] 6.2 Dispatch the forget workflow; watch.
- [ ] 6.3 Off-host verification (API 404, server volumes, verify run, Sentry, uptime).
- [ ] 6.4 Finish PR B (destruction record → ADR `accepted`, legal sweep CLO-attested, expenses,
      job-rationale runbook, C4 description); merge same day.
- [ ] 6.5 Re-enable both workflows; `manual-rerun` apply; drift green; `GET ?name=` → `[]`.
- [ ] 6.6 Evidence comments on #6604 / #6588; #6897 item 1 update; sweeper closes #6604.
