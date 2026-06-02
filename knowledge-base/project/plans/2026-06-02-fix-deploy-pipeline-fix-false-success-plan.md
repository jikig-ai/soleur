---
title: "fix(infra): deploy-pipeline-fix false-success — assert files landed, break the chicken-and-egg freeze"
date: 2026-06-02
type: fix
issue: "#4804"
branch: feat-one-shot-4804-deploy-pipeline-fix-false-success
lane: cross-domain
status: planned
brand_survival_threshold: none
emoji: 🐛
---

# 🐛 fix(infra): deploy-pipeline-fix false-success — assert files landed on the host

> Spec lacks valid `lane:` (no spec.md for this branch) — defaulted to `cross-domain` (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-06-02
**Sections enhanced:** Acceptance Criteria (AC5, AC11), Phase 2, Risks/Sharp Edges, Network-Outage finding
**Research passes:** verify-the-negative (4.45), precedent-diff (4.4), network-outage gate (4.5), halt gates (4.6/4.7/4.8 all PASS)

### Key Improvements

1. **`files_total` must be emitted into the state JSON (NEW Phase 2 step).** Verified that
   `infra-config-apply.sh` computes `TOTAL_COUNT=${#FILE_MAP[@]}` (line 62) but does **NOT** emit
   it into the state JSON (only `files_written` + `files_failed` at line 133). The CI step
   therefore cannot assert `files_written == TOTAL` without either hardcoding `8` (which silently
   drifts when FILE_MAP grows — the exact bug class that caused the freeze) or adding the field.
   Phase 2 now adds a `"files_total":%d` field; AC5 asserts `files_written == files_total &&
   files_failed == 0`, self-contained and drift-proof.
2. **`files_written + files_failed == files_total` is an invariant** after the Phase 2 change:
   every FILE_MAP entry hits exactly one of three `continue`/increment arms (written, failed-base64,
   failed-visudo) plus the new failed-missing_env arm. Verified loop structure at lines 66-116.
3. **AC11 trigger is definitive, not hedged.** Verified the `apply-deploy-pipeline-fix.yml`
   `paths:` filter (lines 48-49) includes `infra-config-apply.sh` AND `push-infra-config.sh`.
   Since this PR edits `infra-config-apply.sh`, the merge **will** trigger the auto-apply. (The
   workflow file `apply-deploy-pipeline-fix.yml` itself is NOT in its own `paths:` filter — so a
   workflow-only edit would not self-trigger, but that's moot here.)
4. **Network-Outage gate (4.5): L3 firewall NOT applicable to this resource.** Verified
   `terraform_data.deploy_pipeline_fix` uses **`provisioner "local-exec"` only** (server.tf:332) —
   the SSH `connection`/`file`/`remote-exec` provisioners were removed in #3756. So the
   implicit-SSH-dependency trigger does NOT fire; the firewall/connection-reset keywords in
   Hypotheses are correctly classified as **ruled-out** (the failure is an application-layer
   `exit 1`, not connectivity). Telemetry emitted for the keyword match.

### New Considerations Discovered

- The `push-infra-config.sh`-cannot-read-async-exit claim is **confirmed** by code: webhook
  `success-http-response-code: 202` (hooks.json.tmpl:34) + async `systemd-run --on-active=3s`
  self-restart (infra-config-apply.sh:155). The assertion must live in CI, not the provisioner.
- `cat-infra-config-state.sh` echoes the state file verbatim, so any field added to the state
  JSON (e.g., `files_total`) is automatically exposed at `/hooks/infra-config-status` — no change
  to the reporter script needed.

## Overview

`terraform_data.deploy_pipeline_fix` reports **success on every merge**, but a subset of the
host scripts it is responsible for pushing (`cat-deploy-state.sh`, `ci-deploy-wrapper.sh`,
`canary-bundle-claim-check.sh`, `hooks.json`, sudoers) have **not changed on the prod host
since 2026-05-21** — a silent false-success. The most recent symptom: the `journald_storage`
field added to `cat-deploy-state.sh` in #4800 (closing #4792) is NOT live on
`/hooks/deploy-status` (returns `null`), despite the merge running deploy-pipeline-fix and
terraform reporting `Apply complete! Resources: 1 added, 0 changed, 1 destroyed`.

This plan makes the CI apply **fail loud** when files do not land, and breaks the
self-perpetuating freeze so future file additions deploy reliably. It is a **pure code/config
change** against an already-provisioned surface — no new infrastructure, no new vendor, no new
secret.

### The three independent defects (all required for the false-success)

1. **Trigger-and-forget at the `local-exec` boundary.** `push-infra-config.sh` checks only
   `HTTP_CODE == 202` and exits 0. The `/hooks/infra-config` webhook returns 202
   **synchronously** (`success-http-response-code: 202` in `hooks.json.tmpl:34`) the moment the
   hook *triggers* — `infra-config-apply.sh` then runs asynchronously and self-restarts the
   webhook binary via `systemd-run --on-active=3s`. So the 202 says "I started the script",
   never "the script wrote the files". `local-exec` exits 0 → terraform reports success
   regardless of the script's eventual internal exit code or `files_failed` count.

2. **The CI verify step is too weak AND has a silent escape hatch.** `apply-deploy-pipeline-fix.yml`
   *does* (since #4556) poll `/hooks/infra-config-status` and assert `exit_code == 0`
   (lines 209-265). But:
   - It asserts only `exit_code`, **not** `files_failed == 0 && files_written == TOTAL`.
   - On HTTP 404 it prints a warning and **passes** ("host may predate this feature" — line 244-245,
     256-257). A host whose stale `hooks.json` lacks the `infra-config-status` hook returns 404 →
     CI is green while nothing landed. This is the exact failure surface for the 2026-05-21 freeze.
   - It never verifies the **deployed file SHAs match HEAD** — the canonical provisioner-layer
     invariant (per learning `2026-04-29-deploy-pipeline-fix-postapply-verification-cf-access.md`).

3. **Chicken-and-egg freeze in the upfront validation.** `infra-config-apply.sh:52-60` does an
   **all-or-nothing** upfront `exit 1` if ANY expected env var is empty:
   ```sh
   for entry in "${FILE_MAP[@]}"; do
     IFS='|' read -r env_var _ _ _ <<< "$entry"
     if [[ -z "${!env_var:-}" ]]; then
       exit 1     # <-- aborts the ENTIRE write; NO files land, including the new hooks.json
     fi
   done
   ```
   When a new file is added to `FILE_MAP` + `hooks.json.tmpl` env-passing + `push-infra-config.sh`
   payload **atomically** (exactly what #4556 did — it added `CAT_INFRA_CONFIG_STATE_SH_B64` to
   all three, commit `0e3a8818`, 2026-05-27), the **host's stale `hooks.json`** does not pass the
   new lowercase payload key → the new uppercase env var is empty on the host → the upfront
   validation `exit 1`s → **nothing is written, including the new `hooks.json` that would teach
   the host to pass the new var**. The freeze is self-perpetuating: the only file that can fix the
   env-mapping (`hooks.json`) is gated behind the very validation it would satisfy.

   The write loop (lines 70-116) ALREADY has per-file failure accounting (`FAIL_COUNT`,
   `FILES_JSON`, `continue`). Only the **upfront** validation is all-or-nothing. The fix is to
   delete the upfront `exit 1` and let the existing per-file loop record a `missing_env` failure
   for the one absent file while still writing the other seven — crucially writing the new
   `hooks.json`, which re-aligns the env-mapping so the next apply is clean.

4. **(Compounding) The handler test never runs in CI.** `infra-config-apply.test.sh` exists but
   is **not registered** in `infra-validation.yml` (verified: `grep -c` returns 0). The
   per-file-vs-all-or-nothing behavior was never guarded.

### Why "delete the upfront validation" is safe

The write loop already handles every file independently and records `status` + `reason` per file.
A missing env var currently can't reach the loop (the upfront gate kills it first); after the
fix it reaches the loop and is recorded as a `failed` file with `reason: missing_env`, exactly
like `base64_decode` and `visudo_validation_failed` already are. `exit_code` becomes 1 (because
`FAIL_COUNT > 0`), which the **strengthened** CI verify step (Defect 2 fix) catches and fails on
— so we trade a *silent* freeze for a *loud* partial-failure that still self-heals the hooks.json
mapping. No file is written with bad content; the only behavior change is "write the 7 good files
instead of writing 0".

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Codebase reality | Plan response |
|---|---|---|
| "`infra-config-apply.sh` runs an upfront all-or-nothing validation that `exit 1`s, no files land" | **Confirmed** — `infra-config-apply.sh:52-60`. | Delete the upfront loop; rely on existing per-file accounting (Phase 2). |
| "Suggested fix 3: replace all-or-nothing with per-file failure accounting" | The **write loop already has** per-file accounting (`FAIL_COUNT`/`FILES_JSON`/`continue`, lines 81-116). Only the upfront gate is all-or-nothing. | Smaller fix than the issue implies: just remove the upfront gate + add a `missing_env` arm to the loop (Phase 2). |
| "Suggested fix 1: read the webhook output and fail local-exec on non-zero internal exit / `files_failed > 0`. The state file already records `files_written`/`files_failed`, queryable via `/hooks/infra-config-status`" | **Partially already built** — `apply-deploy-pipeline-fix.yml:209-265` polls `infra-config-status` and asserts `exit_code==0`. Gaps: doesn't assert `files_failed==0 && files_written==TOTAL`; 404 silently passes; no SHA-match check. | Strengthen the existing verify step rather than add a new one (Phase 3). `push-infra-config.sh` itself can't read the async result (202 is trigger-and-forget); the assertion must live in the CI workflow that can poll the status endpoint after the script finishes. |
| "The DPF drift-gate's 'verifies server-side hashes' claim does not appear to cover these files" | The `infra-config-status` state file **does** carry per-file `sha256` (written at `infra-config-apply.sh:111-114`); the CI step just doesn't compare them to HEAD. | Add a SHA-match assertion against the repo files (Phase 3, optional-strengthening). |
| "hooks.json keys are lowercase, FILE_MAP keys uppercase — hooks.json env-var mapping is load-bearing" | **Confirmed** — `hooks.json.tmpl:39-46` maps `cat_deploy_state_sh_b64` → `CAT_DEPLOY_STATE_SH_B64` etc. Current **repo** mapping is consistent; the drift is on the **host** (stale hooks.json). | The Phase 2 fix lets the new hooks.json land even when one new var is missing, self-healing the host mapping. No repo mapping change needed. |
| "Files frozen since 2026-05-21; #4556 (the verify step) landed 2026-05-27" | **Confirmed** dates. The freeze predates the verify step, so the verify step never had a chance to catch the *original* freeze — and its 404-tolerance means it still wouldn't, because the host lacks the status endpoint. | The Phase 3 fix removes the unconditional 404-pass; first clean apply will surface and self-heal. |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing directly — this is an
operator/CI deploy-reliability fix. The downstream risk it *removes*: silent non-deployment of
host-side deploy and observability scripts (e.g., the 900s `ci-deploy-wrapper.sh` wall-clock cap,
the canary claim-check, the journald-storage no-SSH surface), which can let a broken or stale
host script run unnoticed during a real production deploy.

**If this leaks, the user's data/workflow/money is exposed via:** N/A — no PII, no auth, no
billing, no regulated-data surface. The change touches a bash handler, a Terraform-invoked push
script, and a CI workflow.

**Brand-survival threshold:** none.

> `threshold: none, reason: this is an internal CI/host-script deploy-reliability fix with no
> user-facing surface, no PII, and no regulated-data path; a single failure is an operator-visible
> CI red, not a user incident.`

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Upfront gate removed.** `infra-config-apply.sh` no longer contains the upfront
  `for entry in "${FILE_MAP[@]}"` validation loop that `exit 1`s on the first missing env var.
  Verify: `grep -c 'required env var $env_var is missing or empty' apps/web-platform/infra/infra-config-apply.sh`
  returns `0` for the upfront-loop form (the per-file `missing_env` reason string is distinct).
- [ ] **AC2 — Per-file missing-env accounting.** The write loop records a `failed` file with
  `reason:"missing_env"` when `${!env_var:-}` is empty, `continue`s to the next file, and
  increments `FAIL_COUNT`. Verify via test (AC4): a payload missing exactly one var writes the
  other 7 files and the state JSON shows `files_written:7, files_failed:1` with that file's
  `status:"failed", reason:"missing_env"`.
- [ ] **AC3 — `exit_code` reflects partial failure.** With one missing var, the script exits `1`
  and the state file's `exit_code` is `1` (existing `FAIL_COUNT>0 ⇒ EXIT_CODE=1` logic at
  lines 122-125 is unchanged). Verify via test (AC4).
- [ ] **AC4 — Handler test extended + registered in CI.** `infra-config-apply.test.sh` gains a
  case asserting AC2/AC3 (one-var-missing → 7 written, 1 failed `missing_env`, exit 1, other
  files' content correct), and `infra-validation.yml` registers
  `bash apps/web-platform/infra/infra-config-apply.test.sh` as a step (it is currently absent —
  `grep -c infra-config-apply.test.sh .github/workflows/infra-validation.yml` returns 0 today,
  must return ≥1 after). Verify: run `bash apps/web-platform/infra/infra-config-apply.test.sh`
  locally → all cases pass.
- [ ] **AC5 — CI verify step asserts the full landed-files invariant.** Two parts:
  - **AC5a (handler):** `infra-config-apply.sh` emits a `"files_total":%d` field (value
    `TOTAL_COUNT`) into the state JSON in BOTH the success path (line 133) and the EXIT-trap
    "unhandled" path (line 48, value 0 or TOTAL — see Phase 2). Today only `files_written` +
    `files_failed` are emitted; `TOTAL_COUNT` is computed (line 62) but never written. Verify:
    `grep -c 'files_total' apps/web-platform/infra/infra-config-apply.sh` ≥ 1, and the handler
    test asserts the field appears in the state JSON.
  - **AC5b (CI):** The "Verify infra-config apply succeeded" step asserts `files_failed == 0` AND
    `files_written == files_total` (both parsed from the `infra-config-status` JSON via `jq`), not
    just `exit_code == 0`. Verify: the step extracts `.files_failed`, `.files_written`,
    `.files_total` and fails (`exit 1`) when `files_failed != 0` OR `files_written != files_total`.
    Do NOT hardcode `8` — derive the total from the JSON so the gate survives future FILE_MAP
    additions (the exact drift class that caused this bug).
- [ ] **AC6 — 404 no longer silently passes after first apply.** The unconditional
  "tolerate 404 — host may predate this feature" branch is replaced with a bounded one-time
  tolerance: a 404 is tolerated **only** when a documented first-bootstrap marker applies
  (e.g., `workflow_dispatch` with an explicit `reason`, or an env/input flag), and otherwise a
  persistent 404 across all retries **fails** the step. Verify: read the step; the
  `push`-triggered path does not have an unconditional `break`/pass on 404.
- [ ] **AC7 — `actionlint` clean.** `actionlint .github/workflows/apply-deploy-pipeline-fix.yml`
  passes; embedded `run:` snippets validated via `bash -c` extraction (do NOT use `bash -n` on
  the `.yml`).
- [ ] **AC8 — No behavior change to the happy path.** When all 8 env vars are present, the
  handler still writes all 8 files, `files_written==8, files_failed==0, exit_code==0`, and the
  CI verify step passes. Verify via existing/extended handler test + reading the verify step's
  all-present branch.
- [ ] **AC9 — `terraform fmt -check` + validate clean** for `apps/web-platform/infra/` (only if
  `server.tf` is touched; this plan does NOT plan to touch `server.tf`, so this is a no-op guard).
- [ ] **AC10 — Issue linkage.** PR body uses `Ref #4804` (NOT `Closes #4804`) — see Post-merge
  note: the real-world fix (host re-alignment) completes only after the **post-merge auto-apply**
  re-runs and self-heals; closing at merge would be a false-resolved state. Issue is closed in
  the post-merge step after `/hooks/deploy-status` confirms `journald_storage.persistent`.

### Post-merge (operator/automated)

- [ ] **AC11 — Auto-apply runs and self-heals.** Merging this PR triggers
  `apply-deploy-pipeline-fix.yml` on push to main: **verified** the `paths:` filter (lines 48-49)
  includes `apps/web-platform/infra/infra-config-apply.sh`, which this PR edits, so the trigger is
  definitive. The apply pushes the corrected handler + the current `hooks.json` to the host (the
  new hooks.json lands even if one env var were missing, self-healing the env-mapping).
  **Automation:** fully automated via the existing `on: push` workflow — no operator SSH, no
  manual terraform.
- [ ] **AC12 — Verification via no-SSH surface.** After the auto-apply, the strengthened verify
  step asserts `files_written == TOTAL && files_failed == 0`. Then confirm the original symptom
  is cleared: `GET /hooks/deploy-status` returns `.journald_storage.persistent == true` (the
  #4792/#4800 no-SSH surface that currently returns `null`). **Automation:** add this assertion
  as a final step in `apply-deploy-pipeline-fix.yml` (HMAC + CF-Access headers, same auth shape
  as the existing "Verify webhook is alive" step) — the workflow already has the Doppler secrets
  and curl pattern. No operator dashboard-watching.
- [ ] **AC13 — Close #4804.** A post-apply step (or `/soleur:ship` post-merge) runs
  `gh issue close 4804 --reason completed` only after AC12's `journald_storage.persistent == true`
  assertion holds. **Automation:** `gh` CLI in the workflow's success path (mirror the existing
  "Auto-close any open drift issues" step at lines 267-281).

## Implementation Phases

> **Phase order is load-bearing.** Phase 2 (handler contract change) must precede Phase 3 (CI
> consumer that asserts `files_failed`/`files_written`) so the contract exists before the consumer
> asserts on it. Atomic-merge ≠ atomic-per-phase TDD.

### Phase 0 — Preconditions (verify, no writes)

- [ ] Re-read `infra-config-apply.sh` lines 52-60 (upfront gate) and 70-116 (per-file loop) to
  confirm the loop already supports `continue` + `FAIL_COUNT` + `FILES_JSON` accounting.
- [ ] Confirm the state-file JSON shape carries `files_written`, `files_failed`, and per-file
  `sha256`/`status`/`reason` (lines 133-134, 85, 97, 114). The CI assertion (Phase 3) depends on
  these exact keys.
- [ ] Confirm `TOTAL = ${#FILE_MAP[@]}` value (currently **8** entries — `infra-config-apply.sh:23-32`).
  The CI step must derive TOTAL from the JSON, not hardcode 8, OR hardcode 8 with a comment + an
  AC that fails if `FILE_MAP` length changes. **Decision:** read `files_written`/`files_failed`
  from JSON and additionally assert `files_written + files_failed == files_total` if the script
  emits a total; otherwise assert `files_failed == 0` (the load-bearing invariant) + `exit_code == 0`.
- [ ] `grep -c infra-config-apply.test.sh .github/workflows/infra-validation.yml` → confirm `0`
  (test currently unregistered).

### Phase 1 — RED: failing tests first (cq-write-failing-tests-before)

- [ ] Add a case to `infra-config-apply.test.sh`: invoke the handler with all env vars set
  EXCEPT one (e.g., unset `CAT_INFRA_CONFIG_STATE_SH_B64`), assert:
  - exit code 1,
  - 7 destination files written with correct decoded content,
  - state JSON `files_written == 7`, `files_failed == 1`, `files_total == 8`,
  - the missing file's entry has `status:"failed", reason:"missing_env"`.
  This test RED-fails against the current upfront-gate behavior (current behavior: 0 files
  written, exit 1, no per-file JSON for the others).
- [ ] (Optional) add a case asserting the happy path is unchanged (all 8 → exit 0, 8 written).

### Phase 2 — GREEN: handler contract change (Defects 3 + the safe-removal)

Files: `apps/web-platform/infra/infra-config-apply.sh`

- [ ] Delete the upfront validation loop (lines 52-60).
- [ ] In the write loop, before the `base64 -d` step, add a missing-env arm:
  ```sh
  if [[ -z "${!env_var:-}" ]]; then
    logger -t "$LOG_TAG" "FAILED: $dest_path reason=missing_env"
    [[ -n "$FILES_JSON" ]] && FILES_JSON+=","
    FILES_JSON+="{\"file\":\"$dest_path\",\"sha256\":\"\",\"status\":\"failed\",\"reason\":\"missing_env\"}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    continue
  fi
  ```
  (placed at the top of the loop body, before `mktemp`, so no temp file is created for the
  missing file).
- [ ] Confirm `EXIT_CODE=1` when `FAIL_COUNT>0` (existing lines 122-125, unchanged).
- [ ] **Emit `files_total` into the state JSON.** Add `"files_total":%d` to the success-path
  `printf` (line 133) with value `$TOTAL_COUNT`, and add it to the EXIT-trap "unhandled" `printf`
  (line 48) with value `0` (the trap fires before any count is known; `files_written==0` +
  `files_total==0` is a consistent "nothing happened" sentinel — or use `$TOTAL_COUNT` if it is
  in scope at trap time; verify scope and pick the consistent form). `cat-infra-config-state.sh`
  echoes the state file verbatim, so the field is automatically exposed at
  `/hooks/infra-config-status` with no reporter change. This makes AC5b's
  `files_written == files_total` check self-contained.
- [ ] Run the handler test → all cases (RED from Phase 1 + existing) pass, and the state JSON in
  every case carries `files_total`.

### Phase 3 — GREEN: CI verify-step strengthening (Defects 1 + 2)

Files: `.github/workflows/apply-deploy-pipeline-fix.yml`

- [ ] In the "Verify infra-config apply succeeded" step, after parsing the JSON, extract
  `.files_failed`, `.files_written`, `.files_total` (and `.exit_code`) via `jq`. Fail the step
  when `files_failed != 0` OR `files_written != files_total`. (Keep the `exit_code` check as a
  belt-and-suspenders.) Derive total from `.files_total` — never hardcode `8`.
- [ ] Replace the unconditional 404-tolerance (`break` + "Tolerating missing endpoint" pass) with
  a bounded one: tolerate 404 ONLY on an explicit first-bootstrap signal (e.g.,
  `github.event_name == 'workflow_dispatch'` with a `reason` input, OR a dedicated boolean input
  `allow_missing_status_endpoint`); otherwise a persistent 404 fails the step. Route the untrusted
  input through an `env:` var per the workflow's injection-prevention convention (header comment
  lines 30-33).
- [ ] Add a final post-apply assertion step (or extend "Verify webhook is alive"): `GET
  /hooks/deploy-status` with HMAC + CF-Access headers and assert
  `.journald_storage.persistent == true` via `jq -e`. This is the AC12 no-SSH verification of the
  original symptom. Gate on `if: success()` so it runs only after the apply + landed-files
  assertions pass.
- [ ] Add the issue-close step (AC13): `gh issue close 4804 --reason completed` in a
  `if: success()` step after the `journald_storage` assertion. (Or document that `/soleur:ship`
  post-merge handles it — choose the workflow-embedded form per the automation-feasibility gate.)
- [ ] `actionlint .github/workflows/apply-deploy-pipeline-fix.yml` clean; validate embedded shell
  via `bash -c '<extracted snippet>'`.

### Phase 4 — Register the handler test in CI (Defect 4)

Files: `.github/workflows/infra-validation.yml`

- [ ] Add a step `run: bash apps/web-platform/infra/infra-config-apply.test.sh` alongside the
  existing per-script test steps (e.g., near `ci-deploy.test.sh` at line 133). Match the existing
  step naming/indentation.
- [ ] (Consider also registering the other unregistered infra `.test.sh` files —
  `cat-deploy-state.test.sh`, `cat-infra-config-state.test.sh`, `infra-config-apply.test.sh` — but
  scope to `infra-config-apply.test.sh` for this PR unless trivial; note the others as a follow-up
  if deferred.)

### Phase 5 — Capture learning

- [ ] Write `knowledge-base/project/learnings/bug-fixes/<topic>.md` (date picked at write-time)
  documenting: the 202-trigger-and-forget vs script-completion distinction, the chicken-and-egg
  freeze when a new file is added to FILE_MAP + hooks.json env-passing atomically, and the
  "assert files_failed==0 && files landed, not just the proxy responded" verification principle.
  Cross-reference `2026-04-29-deploy-pipeline-fix-postapply-verification-cf-access.md` and
  `2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md`.

## Files to Edit

- `apps/web-platform/infra/infra-config-apply.sh` — remove upfront gate, add per-file `missing_env` arm (Phase 2).
- `apps/web-platform/infra/infra-config-apply.test.sh` — RED test for one-missing-var → 7 written/1 failed (Phase 1).
- `.github/workflows/apply-deploy-pipeline-fix.yml` — assert `files_failed==0 && files_written==TOTAL`; bound 404-tolerance; add `journald_storage.persistent` assertion + issue-close (Phase 3).
- `.github/workflows/infra-validation.yml` — register `infra-config-apply.test.sh` (Phase 4).

> **Not edited:** `push-infra-config.sh` — it runs in the `local-exec` provisioner and cannot read
> the async script's eventual exit (the 202 is trigger-and-forget by design). The landed-files
> assertion belongs in the CI workflow, which can poll `/hooks/infra-config-status` after the
> handler completes. Editing `push-infra-config.sh` to poll would duplicate the workflow's polling
> and couple terraform `apply` wall-clock to the host's async self-restart. (If a reviewer prefers
> the assertion at the provisioner layer, it can move — but the workflow is the lower-blast-radius
> home.)
>
> **Not edited:** `server.tf` — no change to the `triggers_replace` set or the provisioner.
> `hooks.json.tmpl` repo mapping is already correct; the host mapping self-heals via Phase 2.

## Files to Create

- `knowledge-base/project/learnings/bug-fixes/<topic>.md` (Phase 5).

## Open Code-Review Overlap

None. (No open `code-review`-labeled issues were checked against these paths during planning;
the planner should run the overlap grep at /work time if the backlog has grown. The four edited
files are infra/CI surfaces not typically in the review backlog.)

## Hypotheses

The issue names neither SSH/network keywords in a way that triggers the network-outage checklist
(the failure is an application-layer all-or-nothing `exit 1`, not a connectivity fault), but for
completeness the **ruled-out** hypotheses:

- ❌ **Firewall/admin-IP drift.** Not applicable — the push goes through the CF Tunnel webhook
  (`/hooks/infra-config`), not SSH; the webhook returned HTTP 202 (it was reachable). Per
  `hr-ssh-diagnosis-verify-firewall` this would be the first check IF the symptom were a connection
  reset; it is not — the connection succeeded and returned 202.
- ❌ **HMAC/CF-Access auth failure.** Ruled out — a 401/403 would have made `push-infra-config.sh`
  exit 1 (it checks `!= 202`). Evidence shows 202, so auth passed.
- ✅ **All-or-nothing `exit 1` on a missing host env var (chicken-and-egg).** Primary hypothesis,
  supported by: scripts frozen exactly at the last fully-successful apply (2026-05-21); files that
  update only via deploy-pipeline-fix all frozen; `ci-deploy.sh` fresher because
  `web-platform-release.yml` also writes it.
- ✅ **Trigger-and-forget 202 masks the async exit.** Supported by the 202 success-code in
  `hooks.json.tmpl:34` + the `systemd-run --on-active=3s` self-restart making the script
  asynchronous to the HTTP response.

### Network-Outage Deep-Dive (gate fired on keyword match; resolved NOT-APPLICABLE)

The deepen-plan Phase 4.5 network-outage gate fired because the Hypotheses section contains the
substrings `firewall` and `connection reset`. Layer-by-layer verification:

- **L3 firewall allow-list:** NOT APPLICABLE. `terraform_data.deploy_pipeline_fix` uses
  `provisioner "local-exec"` **only** (verified `server.tf:332`); the SSH
  `connection`/`file`/`remote-exec` provisioners were removed in #3756. There is no SSH
  apply-time dependency for this resource, so the implicit-SSH-dependency trigger
  (`provisioner "remote-exec"` / `connection { type = "ssh" }`) does NOT fire. Per
  `hr-ssh-diagnosis-verify-firewall`, no firewall/egress-IP check is required because no SSH
  handshake occurs.
- **L3 DNS/routing:** the push reaches the host via the CF Tunnel HTTPS endpoint
  (`deploy.soleur.ai/hooks/infra-config`); evidence shows HTTP **202** was returned, so DNS +
  routing + tunnel were healthy at the time of the freeze.
- **L7 TLS/proxy:** CF Access + HMAC both validated (a 401/403 would have made
  `push-infra-config.sh` exit 1; it saw 202). No proxy-layer fault.
- **L7 application:** **the actual fault** — the host script's internal all-or-nothing `exit 1`
  wrote nothing, masked by the trigger-and-forget 202. This is the plan's primary hypothesis.

Conclusion: the failure is purely application-layer; the network keywords are ruled-out, not
load-bearing. No firewall remediation is part of this plan.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/CI deploy-reliability change. No
user-facing surface, no product/UX, no legal/compliance, no pricing/marketing. Engineering-only.

## Infrastructure (IaC)

This plan introduces **no new infrastructure** — no new server, service, secret, vendor, DNS
record, or firewall rule. It edits an existing host-resident bash handler
(`infra-config-apply.sh`), the existing CI apply workflow, and the existing CI validation
workflow. The host script lands via the already-provisioned `terraform_data.deploy_pipeline_fix`
local-exec path; the **apply path is the existing `on: push` auto-apply** (`apply-deploy-pipeline-fix.yml`),
which fires when `infra-config-apply.sh` changes. No `terraform apply` operator step, no SSH, no
Doppler write. Per Phase 2.8: skip — pure config change against provisioned surface.

## Observability

```yaml
liveness_signal:
  what: "/hooks/infra-config-status returns files_written==TOTAL && files_failed==0 after each apply"
  cadence: "every merge to main touching the trigger files (on: push) + manual workflow_dispatch"
  alert_target: "apply-deploy-pipeline-fix.yml job failure (GitHub Actions) + infra-drift issue auto-file on next 12h drift cron"
  configured_in: ".github/workflows/apply-deploy-pipeline-fix.yml (Verify infra-config apply succeeded step)"
error_reporting:
  destination: "GitHub Actions step annotation (::error::) + job failure; host-side logger -t infra-config-apply to journald (queryable via /hooks/deploy-status journald tail)"
  fail_loud: true
failure_modes:
  - mode: "one env var missing on host (chicken-and-egg)"
    detection: "files_failed > 0 in /hooks/infra-config-status JSON; specific file shows reason:missing_env"
    alert_route: "apply workflow fails the Verify step (exit 1) → red CI"
  - mode: "host hooks.json predates infra-config-status endpoint (404)"
    detection: "persistent HTTP 404 across all retries on a push-triggered apply"
    alert_route: "Verify step fails (no longer silently tolerated except on explicit first-bootstrap signal)"
  - mode: "files land but journald_storage still null (cat-deploy-state stale)"
    detection: "GET /hooks/deploy-status .journald_storage.persistent != true"
    alert_route: "final post-apply assertion step fails the job"
logs:
  where: "host journald (logger -t infra-config-apply); GitHub Actions run logs + step summary"
  retention: "journald per journald-soleur.conf bounded persistent storage (#4792); Actions logs per GitHub default (90d)"
discoverability_test:
  command: "curl -s -H \"X-Signature-256: sha256=$(printf '' | openssl dgst -sha256 -hmac \"$WEBHOOK_DEPLOY_SECRET\" | sed 's/.*= //')\" -H \"CF-Access-Client-Id: $CF_ACCESS_ID\" -H \"CF-Access-Client-Secret: $CF_ACCESS_SECRET\" https://deploy.soleur.ai/hooks/infra-config-status | jq '.files_written, .files_failed'"
  expected_output: "files_written == 8 (current FILE_MAP length), files_failed == 0"
```

## Alternative Approaches Considered

| Approach | Why not chosen |
|---|---|
| Make `push-infra-config.sh` poll `/hooks/infra-config-status` and fail the provisioner | Couples terraform `apply` wall-clock to the host's async self-restart (3s + binary init); duplicates the workflow's existing polling; the provisioner runs in a `local-exec` that would need the CF-Access + HMAC secrets re-plumbed. The CI workflow already has the secrets and polling pattern. Kept as a reviewer-option in Files-to-Edit note. |
| Keep upfront validation but make it per-file (warn + continue instead of exit) | Functionally identical to deleting it (the write loop already does per-file accounting); the upfront loop becomes dead duplication. Simpler to delete. |
| Add a brand-new "verify files landed" CI step | #4556 already added one; strengthening the existing step avoids two polling steps racing the same async window. |
| Verify by SSH-ing the host and `sha256sum`-ing the files | Violates `hr-no-ssh-fallback-in-runbooks` / no-SSH design (#3756). The `/hooks/infra-config-status` JSON already carries per-file `sha256`; use the HTTPS surface. |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above: threshold `none`
  with a non-empty scope-out reason.)
- The CI Verify step must derive the total from the state JSON's `files_total` field (emitted by
  the handler per Phase 2), NOT from a hardcoded literal `8` that silently drifts when a future
  file is added to FILE_MAP — that drift is the exact bug class this PR fixes. Both
  `files_failed == 0` AND `files_written == files_total` are load-bearing; `files_failed == 0`
  alone would pass if a future file were silently dropped from the loop without being counted.
- When editing the 404-tolerance, the untrusted `reason` / input must route through an `env:` var
  before reaching `run:` (workflow injection-prevention convention, header lines 30-33).
- The new `missing_env` arm must be placed BEFORE `mktemp` in the loop body so no orphan temp file
  is created for the absent file (the EXIT trap cleans `TMPFILES`, but skipping mktemp is cleaner).
- Validate the workflow with `actionlint` (it is a workflow, has `on:`+`jobs:`), NOT against the
  composite-action schema; validate embedded `run:` shell via `bash -c` extraction, never
  `bash -n` on the `.yml`.
- PR body uses `Ref #4804`, not `Closes #4804` — the real fix completes post-merge (auto-apply
  self-heals the host); the issue is closed by the post-apply success step after
  `journald_storage.persistent == true` is confirmed.

## Test Strategy

- **Runner:** bash `.test.sh` sandbox convention (matches every sibling in
  `apps/web-platform/infra/*.test.sh`; verified `infra-config-apply.test.sh` exists with a tmpdir
  sandbox + mocked `visudo`/`systemctl`/`logger`). No new test framework.
- **New/extended cases:** one-var-missing → 7 written / 1 `missing_env` / exit 1; happy path
  unchanged (8/0/exit 0).
- **CI gate:** register the handler test in `infra-validation.yml` so the contract is guarded on
  every PR.
- **Workflow:** `actionlint` on `apply-deploy-pipeline-fix.yml`; `bash -c` on extracted `run:`
  snippets.
