---
title: "deploy-pipeline-fix false-success: 202 trigger-and-forget + chicken-and-egg env-var freeze"
date: 2026-06-02
category: bug-fixes
tags: [infra, ci, deploy-pipeline-fix, webhook, false-success, async, verification]
issue: "#4804"
---

# deploy-pipeline-fix reported success while host scripts froze for 12 days

## Symptom

`terraform_data.deploy_pipeline_fix` reported `Apply complete! Resources: 1 added,
0 changed, 1 destroyed` on every merge, yet a subset of the host scripts it pushes
(`cat-deploy-state.sh`, `ci-deploy-wrapper.sh`, `canary-bundle-claim-check.sh`,
`hooks.json`, sudoers) had **not changed on the prod host since 2026-05-21**. Concretely,
the `journald_storage` field added to `cat-deploy-state.sh` in #4800 (closing #4792)
returned `null` on `/hooks/deploy-status` — green CI, stale host.

## Three independent defects, all required for the false-success

1. **Trigger-and-forget at the `local-exec` boundary.** `push-infra-config.sh` checks only
   `HTTP_CODE == 202`. The `/hooks/infra-config` webhook returns 202 **synchronously**
   (`success-http-response-code: 202`) the moment the hook *triggers* — the handler then
   runs asynchronously and self-restarts the webhook binary via
   `systemd-run --on-active=3s`. So the 202 means "I started the script", never "the script
   wrote the files". `local-exec` exits 0 → terraform reports success regardless of the
   handler's eventual exit code or `files_failed` count. **The proxy responding is NOT the
   work succeeding.**

2. **The CI verify step was too weak AND had a silent escape hatch.** The post-#4556 verify
   step asserted only `exit_code == 0`, not `files_failed == 0 && files_written == total`.
   Worse, on HTTP 404 it printed a warning and **passed** ("host may predate this feature").
   A host whose stale `hooks.json` lacks the `infra-config-status` hook returns 404 → green
   CI while nothing landed — the exact freeze surface.

3. **Chicken-and-egg freeze in the upfront validation.** `infra-config-apply.sh` did an
   **all-or-nothing** upfront `exit 1` if ANY expected env var was empty. When a new file is
   added to `FILE_MAP` + `hooks.json` env-passing + `push-infra-config.sh` payload
   **atomically** (exactly what #4556 did, adding `CAT_INFRA_CONFIG_STATE_SH_B64`), the
   **host's stale `hooks.json`** doesn't pass the new lowercase payload key → the new
   uppercase env var is empty on the host → the upfront validation `exit 1`s → **nothing is
   written, including the new `hooks.json` that would teach the host to pass the new var.**
   Self-perpetuating: the only file that can fix the env-mapping is gated behind the very
   validation it would satisfy.

## Fix

- **Delete the upfront all-or-nothing gate.** The write loop already had per-file accounting
  (`FAIL_COUNT`/`FILES_JSON`/`continue`); only the upfront gate was all-or-nothing. Replace it
  with a per-file `missing_env` arm so the 7 good files (crucially the new `hooks.json`) land
  while the absent one is recorded as `status:"failed", reason:"missing_env"` and surfaces a
  loud `exit_code=1`. Trades a *silent freeze* for a *loud partial-failure that self-heals the
  hooks.json mapping on the next apply*.
- **Emit `files_total` into the state JSON.** `TOTAL_COUNT` was computed but never emitted, so
  CI couldn't assert `files_written == total` without hardcoding `8` — the exact drift class
  that caused the bug. Emitting the field makes the gate self-contained and FILE_MAP-growth-proof.
- **Strengthen the CI verify step** to assert `exit_code==0 AND files_failed==0 AND
  files_written==files_total` (total from JSON, never hardcoded), and **bound the 404
  tolerance** to a `workflow_dispatch` first-bootstrap escape hatch — a persistent 404 on a
  routine `push` apply now fails loud.
- **Stand up the no-SSH symptom assertion**: a final step asserts `/hooks/deploy-status`
  reports `journald_storage.persistent == true`, and auto-closes #4804 once verified.
- **Register `infra-config-apply.test.sh` in CI** — it existed but was never wired into
  `infra-validation.yml`, so the contract was unguarded.

## The principle

When a deploy crosses an **async trigger-and-forget boundary** (HTTP 202, fire-and-forget
queue, `systemd-run`-scheduled work), the synchronous response code is a *liveness* signal,
not a *completion* signal. Verification must poll the work's own state record and assert the
**landed-artifact invariant** (`files_failed==0 && files_written==files_total`), not just that
the proxy answered. And a verification step that **tolerates a missing status endpoint** is
not a verification step — it is a silent pass. Bound every "tolerate the absence" branch to an
explicit, documented first-bootstrap signal.

A second, subtler lesson: when a single change **atomically** adds a payload field across
producer + transport + consumer (here: `push-infra-config.sh` + `hooks.json` + `FILE_MAP`), the
rollout is only atomic in the *repo*. On a host that updates the transport config (`hooks.json`)
**through** the same pipeline, an all-or-nothing gate makes the new field's own delivery
mechanism depend on the field already being deliverable. Prefer per-item accounting so the
self-healing config can always land.

## Review-surfaced design lesson: scope value-assertions to their close-out

The first cut of the fix added a **standing** `journald_storage.persistent == true`
assertion that hard-failed on *every* future deploy-pipeline-fix apply. Multi-agent
review (architecture-strategist) flagged this as over-coupling: a generic
deploy-reliability workflow should not permanently gate on one downstream feature's
field *value*. A deliberate future journald change would false-red an unrelated
merge with a misleading "#4792/#4800 has not landed" message.

The generalizable rule: **a workflow's standing gate should assert its own generic
contract** (here, `files_written == files_total && files_failed == 0` — which already
proves the file landed), **and a one-time symptom/value check should be scoped to the
thing it closes out** (gated on the issue still being OPEN, so it auto-disables once
resolved). Distinguish "did the artifact deploy?" (standing, generic) from "does this
specific field have this specific value?" (close-out, point-in-time).

## Cross-references

- [[2026-04-29-deploy-pipeline-fix-postapply-verification-cf-access]] — the post-apply
  verification + CF-Access auth shape this strengthens.
- [[2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature]] — the auto-apply-on-merge
  workflow that this verify gate lives in.
