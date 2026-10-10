# Tasks: fix(infra): zot shipper cap-exempts the real PatchBlobUpload error line (#9373)

Plan: knowledge-base/project/plans/2026-10-10-fix-zot-shipper-cap-exempt-patchblobupload-func-plan.md
Process: every Bash call chains `cd <worktree> &&`; no bare git stash; no process-kill by full command line; no writes to Claude Code memory.

## 1. Setup
- 1.1 Record the baseline from Better Stack: boot_id, zot_restarts, zot_image_digest, 7556 and 7341 verdict lines.
- 1.2 Record `registry-userdata-budget.sh --json` baseline (stored bytes).
- 1.3 Run `bash apps/web-platform/infra/zot-log-shipper.test.sh` (expect 174 passed) and confirm a single `is_cap_exempt` call site and a single `JQ_TICK`.

## 2. Tests first (RED)
- 2.1 zot-log-shipper.test.sh: retarget the T9 fixture to the real func-keyed shape; anchor on `removing .uploads/ files` + `PatchBlobUpload,goroutine`.
- 2.2 Raise the T19 `JQ_TICK` floor to `-ge 6`.
- 2.3 Add T21: S1 (EOF line survives flood), S2 (i/o timeout, v3 module path), S3 (sub-quota bound; other handlers capped), S4 (panic behind 17 lines), S6 (forged HTTP row), S7 (forged journald fragment), S8 (empty/absent func, no field shift).
- 2.4 tests/scripts/test-zot-log-channel-probe.sh: extend C15 (real func-keyed row counted, header-borne decoy not).
- 2.5 zot-fill-rate-7341.test.sh: one assertion for the func-keyed counter.
- 2.6 Run the suites; record the RED set.

## 3. Core implementation (GREEN)
- 3.1 cloud-init-registry.yml: widen `JQ_TICK` (+ `((($j.func?) // null) | s)`) and `read -r` (+ `zfunc`) in the same edit.
- 3.2 `is_cap_exempt`: `local func="$2"`, remove the message arm, add `*"(*RouteHandler).PatchBlobUpload") return 2`.
- 3.3 Call-site restructure (`_cx` handling; rc 2 -> `_exempt=1; _upload_only=1`).
- 3.4 Update the four stale comment blocks (no `${` or `%{`).
- 3.5 Counters: zot-log-channel-7440.sh, zot-fill-rate-7341.sh; comments in zot-upload-ceiling-7556.sh; runbook row.
- 3.6 Measure the render before/after; raise `REGISTRY_GZIP_BUDGET` to measured + ~500 B with a dated comment.
- 3.7 Run Guard Contract mutation rows 1-5 once by hand; each must go RED; record the output.

## 4. Verify and ship
- 4.1 `bash scripts/pre-push-ratchet-lane.sh` + targeted suites; disclose that typecheck, vitest and the broad battery rely on CI.
- 4.2 The 9353 probe exits 0.
- 4.3 CI green; run `registry-replace-preflight.sh` in the background under Monitor as the last gate; an unclean result means stop and report.
- 4.4 PR body: first-line replace disclosure, `Closes #9373`, measurements, mutation output; no `[ack-destroy]` anywhere (commits, PR body, title).
- 4.5 Merge via the merge queue to MERGED; arm a watch on the dispatcher and apply runs.

## 5. Post-merge telemetry (no SSH)
- 5.1 SOLEUR_ZOT_DISK query: new boot_id, zot_restarts=0, post_fail=0, digest unchanged.
- 5.2 7556 PASS (or a named TRANSIENT); 7341 not FAIL (TRANSIENT span<24h expected); report "7341 PASS: not yet observable" and "arm live: pending".
