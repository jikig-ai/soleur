# Weakness Digest

_Read-only recurring-failure signal from learnings added in the last 7d (#6037).
Triage clusters into `/compound`; this file never edits the harness._

Learnings in window: 139

## Recurring failure patterns

_Clusters of learnings sharing >= 2 tags, ranked by size (>= 3 members)._

### mutation-testing + review — 9 learnings
- 2026-09-20-every-guard-pinned-the-artifact-and-none-pinned-the-wire.md
- 2026-09-20-the-ops-only-green-verdict-claimed-a-fact-the-gate-never-measured.md
- 2026-09-21-my-escrow-suite-stubbed-the-one-tool-that-would-have-refused-it.md
- 2026-09-23-my-guards-read-source-through-a-stripper-that-deleted-the-code.md
- 2026-09-24-every-refusal-i-added-had-a-one-keystroke-repair-that-reopened-it.md
- 2026-09-24-i-mirrored-the-applys-token-line-and-not-the-job-around-it.md
- 2026-09-24-the-guard-4781-asked-for-already-existed-and-its-reporting-was-the-defect.md
- 2026-09-24-the-reaper-assumed-every-run-it-cancelled-would-be-replaced.md
- 2026-09-25-a-no-raw-id-claim-tested-at-the-call-args-missed-three-sinks-on-the-same-event.md

### guards + mutation-testing — 7 learnings
- 2026-09-20-every-guard-pinned-the-artifact-and-none-pinned-the-wire.md
- 2026-09-23-a-hand-off-to-a-later-pass-is-a-silent-clean-hole-unless-it-is-accounted.md
- 2026-09-23-arming-an-advisory-gate-turns-its-soft-defaults-into-bypasses.md
- 2026-09-23-every-fix-i-shipped-to-close-a-defect-carried-the-same-defect.md
- 2026-09-23-my-verdict-rode-on-a-pipeline-status-and-my-test-deleted-the-option-that-inverts-it.md
- 2026-09-24-every-refusal-i-added-had-a-one-keystroke-repair-that-reopened-it.md
- 2026-09-24-the-reaper-assumed-every-run-it-cancelled-would-be-replaced.md

### guards + review — 5 learnings
- 2026-09-20-every-guard-pinned-the-artifact-and-none-pinned-the-wire.md
- 2026-09-21-every-gate-this-pr-added-failed-open-on-the-input-it-could-not-measure.md
- 2026-09-24-every-refusal-i-added-had-a-one-keystroke-repair-that-reopened-it.md
- 2026-09-24-routing-59-cron-monitors-every-guard-was-narrower-than-its-name.md
- 2026-09-24-the-reaper-assumed-every-run-it-cancelled-would-be-replaced.md

### doppler + terraform — 5 learnings
- 2026-09-23-every-fix-i-shipped-to-close-a-defect-carried-the-same-defect.md
- 2026-09-23-the-alert-i-was-told-paged-routed-to-nobody.md
- 2026-09-24-a-line-scanner-is-not-a-lexer-and-my-guard-fixture-hid-the-suite.md
- 2026-09-24-a-second-apply-workflow-could-perform-the-rotation-without-its-gate.md
- 2026-09-25-doppler-token-rotation-with-a-secret-consumer-and-revoke-first-removes-the-blanket-ack.md

### mutation-testing + sentry — 5 learnings
- 2026-09-21-curl-retry-flags-turn-a-throttled-emit-into-success-and-my-stubs-were-looser-than-the-code.md
- 2026-09-23-a-hand-off-to-a-later-pass-is-a-silent-clean-hole-unless-it-is-accounted.md
- 2026-09-24-sandboxing-a-render-child-with-bwrap-no-writable-host-bind.md
- 2026-09-24-the-guard-4781-asked-for-already-existed-and-its-reporting-was-the-defect.md
- 2026-09-25-a-no-raw-id-claim-tested-at-the-call-args-missed-three-sinks-on-the-same-event.md

### mutation-testing + vacuity — 4 learnings
- 2026-09-19-every-fix-for-a-silent-drop-was-itself-a-silent-drop.md
- 2026-09-20-every-guard-pinned-the-artifact-and-none-pinned-the-wire.md
- 2026-09-23-a-hand-off-to-a-later-pass-is-a-silent-clean-hole-unless-it-is-accounted.md
- 2026-09-23-every-fix-i-shipped-to-close-a-defect-carried-the-same-defect.md

### review + terraform — 4 learnings
- 2026-09-24-i-mirrored-the-applys-token-line-and-not-the-job-around-it.md
- 2026-09-24-routing-59-cron-monitors-every-guard-was-narrower-than-its-name.md
- 2026-09-21-pinning-ssh-host-keys-the-guards-pinned-presence-not-the-resolved-value.md
- 2026-09-24-a-second-apply-workflow-could-perform-the-rotation-without-its-gate.md

### github-actions + mutation-testing — 4 learnings
- 2026-09-23-every-fix-i-shipped-to-close-a-defect-carried-the-same-defect.md
- 2026-09-24-i-mirrored-the-applys-token-line-and-not-the-job-around-it.md
- 2026-09-24-i-parked-a-fix-for-a-cause-i-never-tested-and-my-stubs-could-not-see-the-device.md
- 2026-09-24-the-reaper-assumed-every-run-it-cancelled-would-be-replaced.md

### ci + mutation-testing — 4 learnings
- 2026-09-23-a-blocking-gate-over-shared-dev-must-say-who-owns-each-row.md
- 2026-09-23-arming-an-advisory-gate-turns-its-soft-defaults-into-bypasses.md
- 2026-09-24-the-reaper-assumed-every-run-it-cancelled-would-be-replaced.md
- 2026-09-25-my-ancestry-gate-was-sound-and-its-harness-and-its-recovery-text-were-not.md

### mutation-testing + review-panel — 3 learnings
- 2026-09-20-every-correction-i-shipped-needed-correcting.md
- 2026-09-24-the-least-certain-verdict-had-the-quietest-alert.md
- 2026-09-20-my-sink-control-was-a-denylist-over-a-string-the-model-writes.md

### github-actions + terraform — 3 learnings
- 2026-09-23-every-fix-i-shipped-to-close-a-defect-carried-the-same-defect.md
- 2026-09-24-i-mirrored-the-applys-token-line-and-not-the-job-around-it.md
- 2026-09-21-pinning-ssh-host-keys-the-guards-pinned-presence-not-the-resolved-value.md

### sentry + terraform — 3 learnings
- 2026-09-21-a-removed-vendor-api-is-a-migration-with-a-backlog-not-a-brownout-to-retry.md
- 2026-09-23-the-alert-i-was-told-paged-routed-to-nobody.md
- 2026-09-24-routing-59-cron-monitors-every-guard-was-narrower-than-its-name.md

### ci + ship — 3 learnings
- 2026-09-20-the-gate-that-caught-it-was-the-one-suite-i-had-no-reason-to-run.md
- 2026-09-23-a-green-deploy-arm-had-deployed-the-parent-commit.md
- kb-index-dirty-livelock-20260921.md

### guards + vacuity — 3 learnings
- 2026-09-20-every-guard-pinned-the-artifact-and-none-pinned-the-wire.md
- 2026-09-23-a-hand-off-to-a-later-pass-is-a-silent-clean-hole-unless-it-is-accounted.md
- 2026-09-23-every-fix-i-shipped-to-close-a-defect-carried-the-same-defect.md

### inngest + step-boundary — 3 learnings
- 2026-09-24-a-thrown-error-loses-its-status-at-the-inngest-step-boundary-so-return-the-verdict.md
- 2026-09-24-changing-a-step-return-shape-strands-in-flight-runs-and-a-boundary-redaction-blinds-the-detector.md
- 2026-09-25-onfailure-never-sees-a-cancel-and-a-mocked-column-hid-a-dead-read.md

### ci + review — 3 learnings
- 2026-09-24-a-pinned-binary-guard-proved-the-file-and-the-gate-resolved-the-name.md
- 2026-09-24-editing-an-already-applied-migration-during-review-breaks-the-dev-ledger.md
- 2026-09-24-the-reaper-assumed-every-run-it-cancelled-would-be-replaced.md

### pipefail + sigpipe — 3 learnings
- 2026-09-24-an-empty-api-search-is-not-evidence-of-absence-and-my-sanitiser-died-before-it-could-page.md
- 2026-09-23-my-sigpipe-regression-guard-pinned-the-file-size-not-the-cause.md
- 2026-09-25-the-flake-was-sigpipe-at-4kib-and-my-fix-leaked-a-pipe-status-through-a-bare-return.md

### bash + test-harness — 3 learnings
- 2026-09-24-the-verify-rows-i-called-host-health-were-the-verifiers-own.md
- 2026-09-22-exec-redirection-is-permanent-and-fd-inheritance-outlives-the-owner.md
- 2026-09-25-the-watchdog-fixing-the-spin-held-the-pipe-it-guarded.md

### mutation-testing + terraform — 3 learnings
- 2026-09-20-every-correction-i-shipped-needed-correcting.md
- 2026-09-23-every-fix-i-shipped-to-close-a-defect-carried-the-same-defect.md
- 2026-09-24-i-mirrored-the-applys-token-line-and-not-the-job-around-it.md

### ci-paths + mutation-testing — 3 learnings
- 2026-09-20-the-ops-only-green-verdict-claimed-a-fact-the-gate-never-measured.md
- 2026-09-23-a-mutation-anchor-can-match-inside-your-own-comment.md
- 2026-09-23-a-packed-string-searched-by-glob-is-a-quadratic-map.md

### guard-vacuity + review — 3 learnings
- 2026-09-22-the-admin-merge-gate-read-ready-from-an-empty-body.md
- 2026-09-23-my-guards-read-source-through-a-stripper-that-deleted-the-code.md
- 2026-09-24-a-second-apply-workflow-could-perform-the-rotation-without-its-gate.md

### review + sentry — 3 learnings
- 2026-09-24-routing-59-cron-monitors-every-guard-was-narrower-than-its-name.md
- 2026-09-24-the-guard-4781-asked-for-already-existed-and-its-reporting-was-the-defect.md
- 2026-09-25-a-no-raw-id-claim-tested-at-the-call-args-missed-three-sinks-on-the-same-event.md

### bash + mutation-testing — 3 learnings
- 2026-09-19-every-fix-for-a-silent-drop-was-itself-a-silent-drop.md
- 2026-09-23-a-packed-string-searched-by-glob-is-a-quadratic-map.md
- 2026-09-23-my-verdict-rode-on-a-pipeline-status-and-my-test-deleted-the-option-that-inverts-it.md

### github-actions + review — 3 learnings
- 2026-09-24-i-mirrored-the-applys-token-line-and-not-the-job-around-it.md
- 2026-09-24-the-reaper-assumed-every-run-it-cancelled-would-be-replaced.md
- 2026-09-21-pinning-ssh-host-keys-the-guards-pinned-presence-not-the-resolved-value.md

