## Follow-Through Item

Verify Sentry monitors received first check-in (sentinel: scheduled-realtime-probe)

**Source PR:** #9999
**Created by:** /ship Phase 7 Step 3.5
**Created:** 2026-05-22

## Verification

<!-- soleur:followthrough
  script=scripts/followthroughs/test-fixture-9999.sh
  earliest=2026-05-22T18:00:00Z
-->

Canonical convention: `knowledge-base/engineering/ops/runbooks/followthrough-convention.md`.
The directive is parsed daily by `.github/workflows/scheduled-followthrough-sweeper.yml`
via `scripts/sweep-followthroughs.sh` — exit 0 PASS / exit 1 FAIL / other TRANSIENT.

## Status

Awaiting verification. The follow-through sweeper will check this issue once `earliest` is reached.
