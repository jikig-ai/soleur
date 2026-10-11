# Tasks — feat-one-shot-9962-envfile-storm-class (#9962)

## Phase 1 — unit edits
- [x] 1.1 `inngest-cutover-flip.service` — [Unit] `ConditionPathExists=/etc/default/inngest-server` + SKIP-VS-FAIL comment
- [x] 1.2 `inngest-cutover-flip.timer` — same condition (activation-evaluated)
- [x] 1.3 `inngest-bootstrap.sh` — heartbeat.service + heartbeat.timer conditions
- [x] 1.4 `inngest-bootstrap.sh` — inngest-server.service + vector.service conditions
- [x] 1.5 `cloud-init-inngest.yml` — soleur-inngest-provision.service condition on /etc/default/inngest-doppler
- [x] 1.6 `inngest-redis.service` — deliberately-loud comment

## Phase 2 — needle
- [x] 2.1 capture.sh: `Failed to start inngest-luks` → `Failed to start inngest`; UNIT arm `inngest-luks` → `[="]UNIT.{0,12}inngest`; rename count_/check_ functions + strings
- [x] 2.2 capture.test.sh: fixtures for `inngest-cutover-flip.service` + `inngest-server.service` forbidden rows; FP control row still green

## Phase 3 — suite rows
- [x] 3.1 inngest.test.sh: per-unit condition-set asserts (service [Unit] conditions ≡ [Service] EnvironmentFile paths; timer mirrors)
- [x] 3.2 mutation check: drop one condition → RED

## Phase 4 — verify
- [x] 4.1 bash -n on edited files; covering suites green

## Live notes

- Carrier guard (GuardA, deploy-script-tests 4/4) is EXPECTED-RED on this PR: the
  edited units are baked carriers; green returns when the vinngest-v1.1.51 tag +
  pin bump lands (same drift window #9944 rode). Sequence: merge carrier edits →
  mint tag → bump-workflow pin PR.
- Scope beyond the issue's three named units: inngest-heartbeat (60s timer),
  vector (RestartSec=10), inngest-server (RestartSec=5) share the identical
  class — conditioned per the write-boundary sweep; inngest-redis deliberately
  left loud per the issue's calibration note.
