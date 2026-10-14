# Tasks: Zot / ADR-096 wrap-up

Plan: knowledge-base/project/plans/2026-10-03-chore-zot-adr096-wrapup-delivery-resolver-alert-adr190-plan.md
Branch: feat-one-shot-zot-adr096-wrapup-9393-9390-9391-9392 (PR-1, draft #9451). PR-2 is a separate branch.

## PR-1: runbook decisions, resolver fix, ADR-190 (no `.github/workflows/` edit)

### 1. Evidence (optional, does not gate the fix)
- 1.1 Read Sentry issue 127244085 via `doppler run -p soleur -c prd -- scripts/sentry-issue.sh <id>`; take the 24h and 30d hourly buckets.
- 1.2 Compare with `ci-deploy` row times (`scripts/betterstack-query.sh --grep DEPLOY_SCRIPT_SHA`). Record counts only in the PR body.

### 2. Tests first (RED)
- 2.1 `apps/web-platform/infra/cron-egress-firewall.test.sh`: behavioral section extracting `enforcement_probe` from the resolver, `nft` PATH shim, rows: both present, jump absent, drop absent, both absent, unreadable (rc 1, empty), SIGPIPE reproducer (labelled inlined old-form control), noisy listing, extraction non-vacuity, exactly one call site, row floor, `PASS+FAIL==CASES`.
- 2.2 `cron-egress-nftables.test.sh`: a row proving no `nft ... | grep -q` pipeline remains in Phase 4.
- 2.3 Confirm RED against the unchanged files for the right reason; record in the PR body.

### 3. Implementation
- 3.1 `cron-egress-resolve.sh` self-heal: three-valued `enforcement_probe` as a bare statement, statuses initialised to 0, capture-then-match, retry once on unreadable, decision = jump absent OR `default drop` absent (the old check matched the LOG rule prefix), fields `host`, `jump_present`, `drop_present`, `log_present`, `rc_jump`, `rc_drop`, `read_failed`, `read_retried`, `docker_since`, `loader_since` (`timeout 2`, read BEFORE the post; post stays before the loader re-run and before `fail`; minimal fallback extra if `jq` fails), literal top-level `sentry_event "<msg>" "enforcement_missing" "$extra"`, message byte-identical.
- 3.2 `cron-egress-nftables.sh` Phase 4: capture-then-match, in its OWN commit with its own test row.
- 3.3 Keep `sentry-egress-ghcr-deny-alert-op-contract.test.ts` green (do not move message/op into variables).

### 4. Docs
- 4.1 `cron-egress-blocked.md`: rewrite both "Known residual" sections (pause as cause, closing event per host, silent signals, no SSH); decode table for the new fields; note on any registry render change during the pause.
- 4.2 ADR-096 residual bullets (#9393 rebirth-only decision; #9391 and #9390 as "see issue state"); ADR-169 one dated sentence (merge no longer delivers a registry change while paused). Runbook residuals keyed to observable state, "as of 2026-10-03", removal trigger #9393.
- 4.3 ADR-190: `status: accepted`, `## Status` opens with the scope caveat (deadline sub-mode only, a tripwire not proof), then the PASS verdict (run 2026-10-01T22:06:46Z); past-tense the soak sentence.

### 5. Baselines and lints
- 5.1 `preflight-discoverability-test.test.ts` `BASELINE_DECLARED_PROBES` +1 with dated comment (re-count with the test's own rule).
- 5.2 Run `fixture-relative-assert` and guard-vacuity runners; adjust baselines only if they move.
- 5.3 `python3 scripts/lint-guard-contract.py`, `python3 scripts/lint-infra-no-human-steps.py --changed`, `bash plugins/soleur/test/c4-count-parity.test.sh`.

### 6. Tracking (no files)
- 6.1 Comment on #9393 (decision, closing events, re-evaluation 2026-10-17), #9390 (held, trigger evaluation, recipe, re-evaluation 2026-10-17), #9392 (fix landed, exit criterion: 3+ events or 7 days after proven delivery), #9372 (image_tag must come from a post-PR-1 commit), #9348 hold list (the wipe procedure owns the re-pause).
- 6.2 `gh issue edit 9393 --add-blocked-by 9372`.
- 6.3 PR body: `Ref #9393`, `Ref #9392`, `Ref #9390`; first line answers "does merging this alone mutate production?".

## PR-2: Better Stack alert for ghcr_blocked=0 (branch feat-one-shot-9391-ghcr-blocked-alert; rebase after PR-1)

### 7. Live probe
- 7.1 Probe the final SQL (hot + archive, 14d, counts only): as written (about 1), arm R positive control, scoping-removed variant. Record counts in the ADR-218 amendment.

### 8. Guard first
- 8.1 `apps/web-platform/test/infra/ghcr-blocked-alert.test.sh` per Guard 1 (M1-M7, floor, emitter needles read from source, pin that the emitter writes ` zot_last_err=` after the head).
- 8.2 `betterstack-send-failed-alert-mutation.test.sh`: `values = [local.vector_prd_source_id]` count 9 to 10 (re-derive with grep -c on main).

### 9. Terraform and workflows
- 9.1 `betterstack-logs-alerts.tf` #9391 section (locals, exploration, alert) with paging 300/900/1800 and `incident_cause` saying 30 quiet minutes.
- 9.2 `apply-web-platform-infra.yml`: two `-target=` lines beside `bwrap_probe_rollback`.
- 9.3 `infra-validation.yml`: one step running the guard.

### 10. Docs
- 10.1 ADR-218 amendment (tenth alert).
- 10.2 `betterstack-log-query.md` standing-alarm row; `cron-egress-blocked.md` decode section (unknown does not alert; silence is not health; paused-apply caveat; a fresh host's first deploy row can read =0 once). ADR-096 #9391 bullet already written as "see issue state".
- 10.3 PR body `Ref #9391`; #9391 closes after the first apply creates the alert.

## Held: #9390 (do not implement now)
- Recipe and trigger are in the plan ("Held"). Trigger: pause lifted AND a registry render change due or standalone replace authorized AND `scripts/registry-replace-preflight.sh` clean.

## Non-code follow-ups (parent session)
- O1 PR #9450 merge confirm (Monitor) then `worktree-manager.sh cleanup-merged`.
- O2 approval request: lift the apply-workflow pause (re-run the two read-only checks first: registry render inputs unchanged since the pause; accumulated merges #9385, #9397, #9440; the wipe procedure owns the re-pause).
- O3 Sentry monitor mute-state read (documented path, no raw tokens).
- O4 #9291 surface only.
- O5 after O2: delivery evidence, then read events carrying `rc_jump` and record the D4 conclusion on #9392.
