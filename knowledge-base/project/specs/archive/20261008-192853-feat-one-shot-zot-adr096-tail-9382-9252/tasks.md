# Tasks: Zot / ADR-096 tail (plan: knowledge-base/project/plans/2026-10-08-chore-zot-adr096-tail-9382-9252-plan.md)

## Phase 1 — Class A pending/drift split (only code; stop rule: > 100 changed lines or > 4 files => revert and file an issue)

- 1.1 Write the test rows first in `apps/web-platform/scripts/sentry-monitors-audit.test.sh` (after T19m): pending-only, pending + drift + routed, commented-out key, typo'd label, unresolved placeholder, no-`SENTRY_TF_DIR` run, tab/space/trailing-comment map (must-PASS), stubbed-out partition (must go RED)
- 1.2 Add the map-key to slug awk pass inside the `tf_dir` coherence block of `apps/web-platform/scripts/sentry-monitors-audit.sh`
- 1.3 Partition `class_a_unrouted_labels` into pending and drift; set `class_a_count` to the drift count; guard the loop against an empty array under `set -u`
- 1.4 Report wording: "undeclared" counter plus a declared-pending line and bullets
- 1.5 Amend the Class A bullet and alternatives in `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md`
- 1.6 Run `bash apps/web-platform/scripts/sentry-monitors-audit.test.sh`, `bash tests/scripts/test-sentry-monitors-audit-class-d.sh`, `bash plugins/soleur/test/c4-count-parity.test.sh`
- 1.7 `git diff --shortstat origin/main`; apply the stop rule

## Phase 2 — Bundle #9252 with #9390 (comments only)

- 2.1 Comment on #9252 and #9390: shared registry-host replace, target zot v2.1.22, boot asset before merge, shared trigger
- 2.2 Comment on #9252: ubuntu:24.04 digest is a separate PR, not a registry render input

## Phase 3 — Record #9382

- 3.1 Comment on #9382 with run 37735265313 and the 8 add / 1 change / 8 destroy plan; leave open

## Report items (final operator report)

- R1 #9372 rebirth not run; web-2 replace 2026-10-07 observation; no docs PR
- R5 wipe dispatched 2026-10-08 (run 37801674740, actor deruelle); re-evaluation moot
- R6 #9291 open, unobjected
- Re-read `apply-web-platform-infra.yml` state (workflow 280110019)
