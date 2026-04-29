---
issue: 3033
type: bug
priority: p1
classification: ops-remediation
requires_cpo_signoff: false
deepened_on: 2026-04-29
---

## Enhancement Summary

**Deepened on:** 2026-04-29
**Sections enhanced:** 7 (Implementation Phase 2, Phase 3 fixture matrix, Acceptance Criteria, Risks, Sharp Edges, Files to Edit, new "Decode Pipeline & Strict-Mode Discipline" subsection)
**Research sources:** repo-research grep over `apps/web-platform/infra/`, learning-file scan in `knowledge-base/project/learnings/` (PR #3029 / #3010 plan precedent, 2026-04-27 SKIP-vs-FAIL semantics, 2026-04-28 anon-key log-injection guard, 2026-04-21 cloud-task-silence bash-strict-mode trap), live verification of `cloud-init.yml` package list (jq present), live `curl` against current prod login bundle, `gh issue view 3033`.

### Key Improvements

1. **`jq` availability resolved at deepen time, not work time** — `cloud-init.yml` line 7 ships `jq` in the host package list. Phase 2 now prescribes a `jq -er`-anchored decode pipeline outright (matching PR #3029 SKILL.md Step 5.4) instead of the conditional fallback the initial plan hedged on. This removes a work-phase decision branch.
2. **Bash strict-mode discipline pinned** per `2026-04-21-cloud-task-silence-watchdog-pattern.md` — the script keeps `set -uo pipefail` (NOT `-e`) because the chunk-traversal loop intentionally tolerates per-iteration failures (failed `curl`, `grep` rc=1 on no-match). Adding `-e` would abort the loop on any per-chunk fetch failure and revert the gate to the same brittle behavior the fix is closing. Made explicit in the new "Decode Pipeline & Strict-Mode Discipline" subsection so the work-phase agent doesn't auto-add `-e` "for safety."
3. **Reason-string contract decision made explicit** — initial plan added five new `canary_layer3_*` reason strings the script would emit to stderr, but mapped all of them to ci-deploy.sh's existing single `canary_layer3_jwt_claims` field. Decision: keep one ci-deploy.sh reason, route specifics through `journalctl` via the new `logger -t` pipe. Rationale: the deploy-status state file's `reason` field is consumed by `cat-deploy-state.sh` which has a string-shape contract with the GitHub Actions deploy-verification poller (`.github/workflows/reusable-release.yml` lines 277-303). Changing the contract has cross-repo blast radius; the journalctl side-channel is sufficient for human triage.
4. **`mktemp` cleanup hardened** — initial plan kept the trap on the two static tempfiles but the new traversal needs a tempdir (`/tmp/canary-l3-chunks.XXXXXX/`). Added explicit `mktemp -d` + `rm -rf` to the trap to defend against tmpdir leak across the 20-fetch loop.
5. **Test-runner port-collision defense pinned** — Phase 3 prescribes a deterministic ephemeral-port helper (`python3 -c 'import socket; s=socket.socket(); s.bind(("",0)); p=s.getsockname()[1]; s.close(); print(p)'`) AND a startup wait loop with a hard timeout. Ports get bound by the OS-allocator, NOT picked from a random range, so collision is impossible by construction.
6. **F12 (log-injection) test scenario tightened** — initial plan said "stderr output MUST NOT contain a literal newline-prefixed `::notice::` annotation". Refined: the test asserts `printf '%s' "$STDERR" | grep -c '^::notice::'` returns 0 — i.e., the C0 strip + U+2028/U+2029 strip removed the smuggled annotation BEFORE it could become a line on its own. This is the assertion shape from `2026-04-28-anon-key-test-fixture-leaked-into-prod-build.md` session error #6.
7. **CI-test discoverability gate added** — Phase 3 verification now requires grepping `.github/workflows/` for `canary-bundle-claim-check.test.sh` AFTER file creation. If no workflow runs the test, the work-phase MUST add the test step to the existing infra-test job (or file a follow-up issue with milestoned tracking). A new test file that no CI job runs is a silent rot vector — `wg-when-an-audit-identifies-pre-existing` applies here proactively.

### New Considerations Discovered

- The `/mnt/data/plugins/soleur` mount that already exists in `ci-deploy.sh` is **also empty** in production — no rsync, no `git clone`, no terraform provisioner populates it. The plan correctly drops the mount-extension framing, but this raises a separate concern outside scope: code in the running app references `/app/shared/plugins/soleur` (`workspace.ts:39`, `cc-dispatcher.ts:387`, `agent-runner.ts:542`), which will resolve to an empty directory at runtime. Whether that's fine (the symlink is best-effort, see `workspace.ts:381-384`) or a latent bug should be tracked in a separate issue, NOT folded into this fix. **Action item for work-phase:** file a follow-up issue noting the discovery; do not attempt to fix it here.
- The `terraform_data.deploy_pipeline_fix` resource's `triggers_replace` already includes `cat-deploy-state.sh` and `webhook.service` — adding `canary-bundle-claim-check.sh` to the join means terraform-drift weekly cron will tag the resource as drifted whenever ANY of the four files change. This is desired (each file change should re-apply on the existing server) but operator-visible. The PR body's terraform-plan output needs to call this out so the CI drift report doesn't generate a false "unexpected drift" ticket.
- The `<script src>` regex in the script must match BOTH self-closing (`<script src="..." />`) AND open/close (`<script src="..."></script>`) tag forms, AND `<link rel=preload href="..." as="script">` references. PR #3029's preflight Check 5 only matches the URL pattern (any `/_next/static/chunks/<...>.js`) without anchoring to the tag context — same approach used here. The grep is `-oE '/_next/static/chunks/[^"]+\.js'` (preserves the existing canary script's regex shape).
- Verified live against current prod (`curl -fsSL https://app.soleur.ai/login | grep -oE '/_next/static/chunks/[^"]+\.js' | sort -u`): 13 unique chunk references, all matching the cap-of-20 design. The `8237-323358398e5e7317.js` chunk contains exactly one `eyJ...` match (208 chars), decode passes canonical claims. The script change will pass on current prod immediately after deploy.

---

# fix(canary): Layer 3 claim-check mount path + dynamic chunk discovery

**Issue:** [#3033](https://github.com/jikig-ai/soleur/issues/3033)
**Branch:** `feat-one-shot-3033-canary-layer3`
**Worktree:** `.worktrees/feat-one-shot-3033-canary-layer3/`

## Overview

Two compounding regressions silently disabled Layer 3 of the canary probe set:

1. **Layer 3 has been skipped on every deploy since #3014.** `apps/web-platform/infra/ci-deploy.sh` invokes `canary-bundle-claim-check.sh` from `/app/shared/apps/web-platform/infra/...` but the canary container only mounts `/mnt/data/plugins/soleur:/app/shared/plugins/soleur:ro`. There is no `apps/...` mount, no terraform-pushed copy of the script, no Dockerfile `COPY`, and no rsync from the repo to `/mnt/data`. The `[[ -x "$CANARY_LAYER_3_SCRIPT" ]]` test silently fails on every iteration of the canary loop, so Layer 3 has never executed in production CI. PR #3014's whole purpose — catching the #3007 client-only regression class at canary time — has been unrealized for a week.
2. **The script's bundle-layout assumption is stale post-#3017.** `canary-bundle-claim-check.sh` hardcodes the login chunk path (`/_next/static/chunks/app/(auth)/login/page-*.js`) and greps for `eyJ...` in that single chunk. After #3017 ("browser-safe JWT decode + preflight Check 9 + Layer 2 promotion") rebundled the Supabase init out of the login chunk, the JWT now lives in a numeric shared chunk (`/_next/static/chunks/8237-*.js`). Even if the mount were fixed, the script would now report `no JWT found in login chunk` on every healthy deploy and false-fail the canary, blocking swap.

This is the second appearance of the same chunking-assumption-drift class in 24 hours. Preflight Check 5 had the identical failure mode — the fix landed in PR #3029 (#3010 plan) yesterday with a dynamic-discovery loop and a SKIP-vs-FAIL decision matrix. That precedent is the load-bearing reference for the script-side change here. The mount-side change is a parallel pattern to `terraform_data.deploy_pipeline_fix` in `server.tf` — `ci-deploy.sh` and `cat-deploy-state.sh` already ship to `/usr/local/bin/` via that resource; the canary script must join them.

## User-Brand Impact

**If this lands broken, the user experiences:** continued silent Layer 3 skipping, exactly today's state. The visible symptom is the absence of a symptom — every deploy reports green, while the post-#3007 regression class (broken inlined Supabase init, client-only validator throws) is once again undetected. The next #3007-class regression that ships to prod takes the dashboard out for an unknown wall-clock window — exactly the window #3014 was built to close.

**If this fix itself ships broken** (mount fix lands, script fix doesn't, or vice versa), the canary will start failing on healthy deploys and block production swap until rolled back. The blast radius is "release pipeline stuck, no production user impact" — the old container keeps serving, swap is gated correctly. The reverse failure (mount fix lands, script regresses to fail-open) would be a security-gate-disabled state and is the worse class.

**If this leaks, the user's data/workflow/money is exposed via:** N/A. Layer 3 is a probe; it does not handle user data, write to Supabase, or carry credentials. The script reads the public `/login` HTML and grep-decodes a public JWT from a public CDN-served chunk. There is no PII surface.

**Brand-survival threshold:** none. This is an ops-remediation of a probe surface. The probe failing closed (today's state — script not found, gate skipped) is the wrong default but is not a single-user incident. The probe failing open after the fix (script found, fail-open on a real bundle break) WOULD be a brand-survival concern — that risk is what the SKIP-vs-FAIL semantics enforce.

- `threshold: none, reason: This PR touches `apps/web-platform/infra/` (sensitive-path regex match) but only modifies a non-credential, non-data-handling probe script and its CI plumbing; the script reads public CDN URLs and decodes a public JWT, with no PII, secrets, payment, or user-owned-resource surface anywhere in the diff.`

## Research Reconciliation — Spec vs. Codebase

| Spec claim (issue #3033) | Reality (verified 2026-04-29 against current main + prod) | Plan response |
| --- | --- | --- |
| "the canary container only mounts `/mnt/data/plugins/soleur:/app/shared/plugins/soleur:ro` (lines 263, 378)" | Verified. `ci-deploy.sh` lines 263 and 378 are the only mount declarations in the canary and prod `docker run` blocks. No `apps/` mount exists. | Accept. The mount path is missing as described. |
| "There is no `-v /mnt/data/apps:/app/shared/apps:ro` mount" | Verified, AND `/mnt/data/apps/` is never populated by anything (cloud-init, server.tf, .github/workflows/) — it does not exist on the host. Mounting it would mount an empty path. The deeper truth: `/mnt/data/plugins/soleur/` is ALSO never populated by anything. The plugin mount has been an empty directory since the server was provisioned. | The fix cannot be "add an `apps/` mount" — that mounts an empty path. The fix must ship the script to `/usr/local/bin/` via `terraform_data.deploy_pipeline_fix`'s file provisioner (mirroring `ci-deploy.sh` / `cat-deploy-state.sh`), with the bound script path resolved on the HOST and passed in to the canary loop. The container does NOT need to invoke the script; the canary loop runs on the HOST and probes the container via `http://localhost:3001`. |
| Issue's "Proposed fix #1" — "add `-v /mnt/data/apps/web-platform/infra:/app/shared/apps/web-platform/infra:ro`" | Misframed: this mounts an empty directory. The script is not on the host today. | **Drop the docker `-v` mount approach.** Replace with the `terraform_data.deploy_pipeline_fix` file-provisioner pattern. `CANARY_LAYER_3_SCRIPT` default changes from `/app/shared/apps/web-platform/infra/canary-bundle-claim-check.sh` to `/usr/local/bin/canary-bundle-claim-check.sh`. ci-deploy.sh runs on the host, so the script needs to be on the host filesystem, not the container's. |
| "Today's prod login chunk … contains zero JWT and zero supabase URL" | Verified live on 2026-04-29 — `wc -c page-f2f3d55448d7908c.js` = 4762 bytes; `grep -c eyJ` = 0; `grep -c supabase` = 0. | Accept. |
| "The canonical anon JWT now lives in `/_next/static/chunks/8237-323358398e5e7317.js`" | Verified — the 8237 chunk contains exactly one `eyJ...` match (208 chars), decode passes `iss=supabase, role=anon, ref=ifsccnjhymdmidffkzhl` (canonical 20-char). | Accept. |
| Issue's "Proposed fix #2" — "broaden chunk discovery — fetch all chunks referenced from `/login` HTML and grep for `eyJ...` across all of them" | Aligns with PR #3029's preflight Check 5 fix. The same `<script src="/_next/static/chunks/...">` enumeration pattern applies. | Accept and import the load-bearing semantics from PR #3029. The script fix mirrors the SKILL.md change verbatim where applicable, scaled to the canary's localhost target instead of the public origin. |
| Issue's "Proposed fix #3" — "add a unit/integration test fixture with both layouts (pre-#3017 login-chunk-inlined, post-#3017 vendor-chunk-inlined)" | Achievable: `bash` test harness can serve fixtures over a local HTTP server (or use `file://` with a path-rewrite). The existing `ci-deploy.test.sh` mocks the script with a stub; this plan adds a separate, dedicated test file (`canary-bundle-claim-check.test.sh`) so unit-level fixture tests don't bloat the integration test. | Accept. New file: `apps/web-platform/infra/canary-bundle-claim-check.test.sh`. Two-layout fixture matrix (login-chunk-JWT, vendor-chunk-JWT) plus the same SKIP-vs-FAIL matrix from PR #3029 scaled to the script. |

## Hypotheses (initial diagnosis triage)

The two failure modes are independently reproducible and independently fixable. Both have already been verified against current main + prod (see Research Reconciliation). No alternative root-cause hypotheses survive — the diagnosis is the fix list below.

## Implementation Phases

### Phase 1 — Ship `canary-bundle-claim-check.sh` to the host (mount fix)

**Goal:** The script is present and executable at a stable host path. `[[ -x "$CANARY_LAYER_3_SCRIPT" ]]` returns true on every deploy. New servers provisioned from cloud-init pick it up automatically.

**Files to edit:**

- `apps/web-platform/infra/ci-deploy.sh` — change `CANARY_LAYER_3_SCRIPT` default from `/app/shared/apps/web-platform/infra/canary-bundle-claim-check.sh` to `/usr/local/bin/canary-bundle-claim-check.sh` (line 279). Update the inline comment on lines 329-332 to drop the "shipped via the read-only plugin mount" framing — the new framing is "shipped via terraform_data.deploy_pipeline_fix and cloud-init.write_files, mirroring ci-deploy.sh".
- `apps/web-platform/infra/server.tf` — extend `terraform_data.deploy_pipeline_fix`:
  - Add `file("${path.module}/canary-bundle-claim-check.sh")` to the `triggers_replace` `sha256(join(",", [...]))` list (line 216-221).
  - Add a `provisioner "file"` block uploading `canary-bundle-claim-check.sh` to `/usr/local/bin/canary-bundle-claim-check.sh` (mirror the existing block at lines 240-243 for `cat-deploy-state.sh`).
  - Add `chmod +x /usr/local/bin/canary-bundle-claim-check.sh` to the `provisioner "remote-exec"` inline list (line 250-268).
- `apps/web-platform/infra/cloud-init.yml` — extend `write_files`:
  - Add a new `path: /usr/local/bin/canary-bundle-claim-check.sh` entry (mirror the existing entries at lines 131-135 for `ci-deploy.sh` and 140-144 for `cat-deploy-state.sh`). Use the `${canary_bundle_claim_check_script_b64}` template variable.
- `apps/web-platform/infra/server.tf` (templatefile call, lines 29-41) — pass `canary_bundle_claim_check_script_b64 = base64encode(file("${path.module}/canary-bundle-claim-check.sh"))`.

**Files to create:** none in this phase. (The script already exists.)

**Verification (pre-merge):**

- `terraform -chdir=apps/web-platform/infra plan` shows `terraform_data.deploy_pipeline_fix` in `replace` (expected — `triggers_replace` hash changes when canary script content is added to the join). `terraform validate` passes.
- `bash -n apps/web-platform/infra/ci-deploy.sh` (syntax-only) passes.
- `bash -n apps/web-platform/infra/canary-bundle-claim-check.sh` passes (no script edits in this phase).
- `bash apps/web-platform/infra/ci-deploy.test.sh` — existing 66+ tests still green (no test-shape change in Phase 1; mock script path is still env-overridden).

**Verification (post-merge / operator-driven):**

- `terraform -chdir=apps/web-platform/infra apply` (per `hr-menu-option-ack-not-prod-write-auth` — show command, wait for go-ahead, then `-auto-approve`).
- After apply, `ssh deploy@<host> 'ls -la /usr/local/bin/canary-bundle-claim-check.sh'` shows mode `0755` and matches the source SHA256 (`sha256sum apps/web-platform/infra/canary-bundle-claim-check.sh`).
- `gh workflow run web-platform-release.yml --ref main` to force a deploy. CI logs include `Canary OK (health/login/dashboard probes passed)` AND no `[[ -x ]]`-skipped path. (Layer 3 still false-fails on the bundle-layout regression — Phase 2 fixes the script logic. The Phase 1 success criterion is "the gate fires"; Phase 2's is "the gate fires correctly.")

### Phase 2 — Dynamic chunk discovery in `canary-bundle-claim-check.sh` (script fix)

**Goal:** The script discovers the JWT-bearing chunk dynamically, identical in semantics to PR #3029's preflight Check 5 update. Pre-#3017 layouts (JWT in login chunk) and post-#3017 layouts (JWT in vendor chunk) both pass.

**Files to edit:**

- `apps/web-platform/infra/canary-bundle-claim-check.sh` — rewrite the chunk-discovery block (lines 35-50) to:
  1. Enumerate all `<script src="/_next/static/chunks/...js">` references from the fetched login HTML (cap at 20).
  2. For each candidate, fetch with `--max-time 5 --max-filesize 5242880` (timeout-bound; defends tmpfs).
  3. Defense-in-depth path validation: each candidate path must match `^/_next/static/chunks/[A-Za-z0-9_/().-]+\.js$` before string-interpolation into the curl URL (mirror SKILL.md Step 5.2 hardening).
  4. Track `jwt_chunk` (first candidate yielding an `eyJ...` match). The host-union tracking from preflight Check 5 is intentionally NOT mirrored — the canary's brief is JWT-claim canonicality, not host validation (preflight already enforces host).
  5. Use the redirected-stdin form (`< /tmp/canary-l3-candidates.txt`) for the `while read` loop, NOT a pipe (subshell variable scope trap — same precedent as SKILL.md Step 5.2 hardening note).
- `apps/web-platform/infra/canary-bundle-claim-check.sh` — preserve the existing claim-assertion block (lines 52-80): `iss == supabase`, `role == anon`, `ref` matches `^[a-z0-9]{20}$`, no placeholder prefix. No semantic change to claim validation.
- Replace the inline `grep -oE` + `cut -d. -f2` + `tr` + `base64 -d` chain with a `jq -er`-anchored decode pipeline. **Verified at deepen time (2026-04-29):** `cloud-init.yml` line 7 includes `jq` in the host package list — every canary host has `jq` installed at provision time. No conditional fallback needed.

**Decode Pipeline & Strict-Mode Discipline (load-bearing):**

The script keeps `set -uo pipefail` (NOT `set -euo pipefail`). This is INTENTIONAL — the chunk-traversal loop relies on per-iteration `curl` failures and `grep` rc=1 on no-match being non-fatal. Adding `-e` would abort the loop the first time a candidate chunk fails to fetch (bot-management 403, transient 5xx, prefetch chunk that was deleted) and revert the gate to the same brittle behavior the fix is closing. Per `knowledge-base/project/learnings/2026-04-21-cloud-task-silence-watchdog-pattern.md`, bash strict-mode aborts on any non-zero rc — for traversal-loop semantics, the correct posture is `set -uo pipefail` plus explicit per-statement rc-check at the decision points (host union accumulation, JWT match, claim assertion).

The decode pipeline (replaces lines 52-72 of current script):

```bash
# After jwt_chunk is confirmed non-empty post-traversal:
JWT=$(grep -oE 'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+' "$jwt_chunk" | head -1)
PAYLOAD=$(printf '%s' "$JWT" | cut -d. -f2)
PAD=$(( (4 - ${#PAYLOAD} % 4) % 4 ))
if [[ $PAD -gt 0 ]]; then PADDED="$PAYLOAD$(printf '=%.0s' $(seq 1 $PAD))"; else PADDED="$PAYLOAD"; fi
JSON=$(printf '%s' "$PADDED" | tr '_-' '/+' | base64 -d 2>/dev/null) || {
  echo "canary_layer3_jwt_decode_failed: base64 payload could not be decoded" >&2
  exit 1
}

# jq -er fails closed on missing/null claim. Mirrors preflight Check 5 Step 5.4.
iss=$(printf '%s' "$JSON" | jq -er '.iss // ""') || { echo "canary_layer3_jwt_decode_failed: payload not parseable as JSON (.iss)" >&2; exit 1; }
role=$(printf '%s' "$JSON" | jq -er '.role // ""') || { echo "canary_layer3_jwt_decode_failed: payload missing .role" >&2; exit 1; }
ref=$(printf '%s' "$JSON" | jq -er '.ref // ""')   || { echo "canary_layer3_jwt_decode_failed: payload missing .ref" >&2; exit 1; }

# Sanitize for log-injection defense — strip C0 controls, DEL, U+2028, U+2029
# before any echo back to stderr (mirrors 2026-04-28 anon-key learning #6).
sanitize() {
  printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177' | sed 's/\xe2\x80\xa8//g; s/\xe2\x80\xa9//g'
}
iss=$(sanitize "$iss"); role=$(sanitize "$role"); ref=$(sanitize "$ref")
```

The `LC_ALL=C tr -d '\000-\037\177'` form is byte-level (not locale-dependent) — required because `tr` in some locales does NOT strip C0 by default. The `sed` clauses match the UTF-8 byte sequences for U+2028 (`E2 80 A8`) and U+2029 (`E2 80 A9`) — the `tr` step does NOT cover these because they are 3-byte UTF-8 sequences, not single bytes in the C0 range.

**Tempfile/tempdir cleanup hardening:**

The current script's trap is `trap 'rm -f "$LOGIN_HTML" "$CHUNK_FILE"' EXIT` (two static tempfiles). The new traversal needs a tempdir for cached chunks:

```bash
LOGIN_HTML=$(mktemp /tmp/canary-l3-login.XXXXXX)
CHUNK_DIR=$(mktemp -d /tmp/canary-l3-chunks.XXXXXX)
CANDIDATES=$(mktemp /tmp/canary-l3-candidates.XXXXXX)
trap 'rm -f "$LOGIN_HTML" "$CANDIDATES"; rm -rf "$CHUNK_DIR"' EXIT
```

The `rm -rf "$CHUNK_DIR"` is load-bearing — without it, repeated canary failures across a deploy storm could leak ~100MB across the 20-fetch loop (`--max-filesize 5242880` × 20 = 100 MB worst-case).

**SKIP-vs-FAIL semantics (load-bearing):**

Per `knowledge-base/project/learnings/2026-04-27-preflight-security-gates-skip-vs-fail-defaults.md`, the canary's Layer 3 is an INVARIANT check — its job is to refuse swap unless the deployed bundle's inlined Supabase init has canonical claims. The script's exit codes encode the decision matrix:

| Login HTML fetch | Candidate enumeration | JWT discovery | Claim canonicality | Exit | CANARY_FAIL_REASON |
| --- | --- | --- | --- | --- | --- |
| Fails (curl rc≠0 or empty) | n/a | n/a | n/a | 1 | `canary_layer3_login_fetch_failed` |
| Succeeds, but zero `<script src>` matches | n/a | n/a | n/a | 1 | `canary_layer3_no_chunks` |
| Succeeds, ≥1 candidate, all 20 fetches return 0 JWT | exhausted | none | n/a | 1 | `canary_layer3_no_jwt` |
| Succeeds, JWT found, decode fails (jq parse / base64 invalid) | found | invalid | n/a | 1 | `canary_layer3_jwt_decode_failed` |
| Succeeds, JWT found, claims non-canonical (any of iss/role/ref/placeholder) | found | valid | non-canonical | 1 | `canary_layer3_jwt_claims` (preserved — matches existing test fixture) |
| Succeeds, JWT found, claims canonical | found | valid | canonical | 0 | n/a |

Note the canary's Layer 3 has NO SKIP outcome — every non-zero result is a hard FAIL that triggers rollback. This contrasts with preflight Check 5, which has SKIP outcomes (e.g., for "Supabase init not present in any chunk loaded by /login"). Rationale: the canary runs against a freshly-built container we are about to swap to prod; "I cannot determine the answer" must NOT proceed to swap. Same fail-closed posture as the existing script (line 14-16 of canary-bundle-claim-check.sh: "SKIP outcomes return non-zero — the canary treats absence as failure to avoid fail-open on a bundling change"). The fix preserves that posture and refines the granularity of the failure-reason strings so post-incident triage can distinguish "bundle structure changed again" from "real claim regression".

**ci-deploy.sh integration (reason-string contract preserved):** The existing `if [[ -x "$CANARY_LAYER_3_SCRIPT" ]]; then` gate (line 333-339) maps a non-zero script exit to `CANARY_FAIL_REASON="canary_layer3_jwt_claims"`. **Decision: do NOT change the ci-deploy.sh reason field.** The deploy-status state file's `reason` field is consumed by `cat-deploy-state.sh`, which has a string-shape contract with the GitHub Actions deploy-verification poller in `.github/workflows/reusable-release.yml` lines 277-303 (substring-match assertion logic). Changing the contract has cross-repo blast radius beyond this PR's scope.

Instead: the script writes specific reason strings to stderr (e.g., `canary_layer3_no_jwt`, `canary_layer3_no_chunks`, `canary_layer3_jwt_decode_failed`, `canary_layer3_jwt_claims`), and ci-deploy.sh captures that stderr via a journalctl side-channel:

```bash
# ci-deploy.sh lines 333-339 — replace existing block
if [[ -x "$CANARY_LAYER_3_SCRIPT" ]]; then
  "$CANARY_LAYER_3_SCRIPT" http://localhost:3001 2>&1 | logger -t "$LOG_TAG" -p user.warning
  if [[ "${PIPESTATUS[0]}" -ne 0 ]]; then
    CANARY_FAIL_REASON="canary_layer3_jwt_claims"  # umbrella reason (contract preserved)
    sleep 3
    continue
  fi
fi
```

The `${PIPESTATUS[0]}` is load-bearing — `| logger` always exits 0, so a naked `if !` would always pass through. Operator triage reads the specific failure reason via `journalctl -u webhook -t ci-deploy --since '5 min ago' | grep canary_layer3_`. The umbrella `canary_layer3_jwt_claims` reason in state file is sufficient for the deploy-status workflow gate; it doesn't need granularity (the workflow just needs "Layer 3 failed, rolled back").

**Files to edit (continued):**

- `apps/web-platform/infra/ci-deploy.sh` — change line 334 from `"$CANARY_LAYER_3_SCRIPT" http://localhost:3001 >/dev/null 2>&1` to `"$CANARY_LAYER_3_SCRIPT" http://localhost:3001 2>&1 | logger -t "$LOG_TAG" -p user.warning` (preserve the rc check via `${PIPESTATUS[0]}`). Keep Layer 3 fail mapping to `CANARY_FAIL_REASON="canary_layer3_jwt_claims"` (no contract break).

**Files to create:** none in this phase (script is rewritten in place).

**Verification (pre-merge):**

- `bash -n apps/web-platform/infra/canary-bundle-claim-check.sh` passes.
- `shellcheck apps/web-platform/infra/canary-bundle-claim-check.sh` passes (or documented exemption with `# shellcheck disable=SC...`).
- New test file (Phase 3) green.
- Existing `bash apps/web-platform/infra/ci-deploy.test.sh` green — including the `MOCK_LAYER3_FAIL=1` branch and the rollback assertion at line 1285 (CANARY_FAIL_REASON contract preserved).
- Live smoke test against current prod: `bash apps/web-platform/infra/canary-bundle-claim-check.sh https://app.soleur.ai` returns exit 0 (post-fix; today returns exit 1).

### Phase 3 — Regression test with two-layout fixture matrix

**Goal:** A self-contained `bash` test file that drives `canary-bundle-claim-check.sh` against served fixtures covering both pre-#3017 and post-#3017 bundle layouts, plus negative cases for each row of the SKIP-vs-FAIL matrix.

**Files to create:**

- `apps/web-platform/infra/canary-bundle-claim-check.test.sh` — new file. Pattern: mirror `ci-deploy.test.sh` style (bash + assert helpers). Uses `python3 -m http.server` on an OS-allocated ephemeral port to serve the fixture tree; the script-under-test is invoked with `http://localhost:<port>`. Port-collision defense (load-bearing — required for parallel CI):

```bash
# Get an OS-allocated free port (no race window vs. random-range picking)
PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("",0)); p=s.getsockname()[1]; s.close(); print(p)')
python3 -m http.server "$PORT" --directory "$FIXTURE_ROOT" >/dev/null 2>&1 &
HTTP_PID=$!
trap 'kill $HTTP_PID 2>/dev/null || true' EXIT

# Wait for server with hard timeout (avoid CI hang on Python startup failure)
for i in $(seq 1 20); do
  curl -fsS -m 1 "http://localhost:$PORT/" >/dev/null 2>&1 && break
  sleep 0.2
done
```

Fixture matrix:
  - **F1 — pre-#3017 (login-chunk-inlined):** `/login/index.html` references `<script src="/_next/static/chunks/app/(auth)/login/page-abc.js">`; `/page-abc.js` contains a canonical-claim JWT. Expect exit 0.
  - **F2 — post-#3017 (vendor-chunk-inlined, current prod):** `/login/index.html` references `<script src="/_next/static/chunks/app/(auth)/login/page-def.js">` AND `<script src="/_next/static/chunks/8237-xyz.js">`; the page chunk is empty; the 8237 chunk contains a canonical JWT. Expect exit 0.
  - **F3 — JWT in chunk #5 of 13 (mid-traversal):** post-#3017 layout but the JWT-bearing chunk appears 5th in the `<script>` enumeration. Expect exit 0 (verifies non-bail-early traversal works AND the iteration cap of 20 is generous).
  - **F4 — placeholder-ref leak:** post-#3017 layout, JWT decode yields `ref=test1234567890123456`. Expect exit 1 with stderr containing `placeholder prefix`.
  - **F5 — non-anon role:** JWT decodes to `role=service_role`. Expect exit 1 with stderr containing `expected "anon"`.
  - **F6 — non-supabase iss:** JWT decodes to `iss=evil`. Expect exit 1 with stderr containing `expected "supabase"`.
  - **F7 — short ref:** JWT decodes with `ref=abc123` (6 chars). Expect exit 1 with stderr containing `canonical 20-char shape`.
  - **F8 — login HTML 404:** server returns 404 for `/login`. Expect exit 1 with stderr containing the new `canary_layer3_login_fetch_failed`-class reason string.
  - **F9 — login HTML returns no chunk references:** HTML body is `<html><body>hi</body></html>`. Expect exit 1 with the new `canary_layer3_no_chunks` reason string.
  - **F10 — all chunks empty (no JWT anywhere):** all candidate chunks are empty files. Expect exit 1 with the new `canary_layer3_no_jwt` reason string.
  - **F11 — JWT decode failure (corrupt base64):** JWT regex matches `eyJ...` but the payload base64 is corrupt. Expect exit 1 (fail-closed per matrix row 4).
  - **F12 — log-injection guard:** crafted JWT with `\n::notice::PASS` in a claim string value (mirroring the 2026-04-28 anon-key learning's session error #6). Assertion shape: `printf '%s' "$STDERR" | grep -c '^::notice::'` returns 0 — i.e., the C0 strip + U+2028/U+2029 strip removed the smuggled annotation BEFORE it could become a line on its own. Also test U+2028 / U+2029 variants explicitly (they bypass naive `${var//$'\n'/}` because they are 3-byte UTF-8 sequences, not single-byte newlines).
  - **F13 — generous cap (21 candidates):** HTML references 21 chunks; the JWT-bearing one is at position 21. Expect exit 1 (cap is 20 by design — bumping the cap is a future change with explicit operator review). Document the rationale in the test header.
- The fixture corpus is generated by a `setup_fixture_<N>` helper inside the test file; no external golden-file directory.

**Files to edit:**

- `apps/web-platform/infra/ci-deploy.test.sh` — extend the existing `MOCK_LAYER3_FAIL` plumbing only if the new script's reason-string contract requires test-shape changes. Expected: no test-shape change because the integration test mocks the script entirely; the mock contract (exit 0 / exit 1) is unchanged.

**Verification:**

- `bash apps/web-platform/infra/canary-bundle-claim-check.test.sh` — all 13 fixtures green.
- `bash apps/web-platform/infra/ci-deploy.test.sh` — all existing 66+ tests still green.
- CI: the test file MUST be picked up by an existing workflow. Verify via `grep -rn 'canary-bundle-claim-check' .github/workflows/` AFTER the file is created. If no workflow runs the test, the work-phase MUST add it as a step to the existing `ci-deploy.test.sh`-running job (find via `grep -l 'ci-deploy.test.sh' .github/workflows/`). Discoverability is load-bearing — a new test file that no CI job runs is a silent rot vector. Per `wg-when-an-audit-identifies-pre-existing`, file a tracking issue if the work-phase determines test wiring requires a separate PR.

### Phase 4 — Post-merge verification

**Goal:** Layer 3 actually executes on a fresh deploy and reports `final_write_state 0 "ok"` after passing all canary probes including Layer 3.

**Operator-driven steps (per `hr-menu-option-ack-not-prod-write-auth` and `wg-after-a-pr-merges-to-main-verify-all`):**

1. After PR merge, terraform-apply (per Phase 1 verification) to push `canary-bundle-claim-check.sh` to `/usr/local/bin/`. Show command; wait for go-ahead; run with `-auto-approve`.
2. `gh workflow run web-platform-release.yml --ref main` (force a release).
3. Poll `gh run list --workflow web-platform-release.yml --limit 1` until conclusion is `success`.
4. SSH to host, `journalctl -u webhook -t ci-deploy --since '10 min ago' | grep -E '(canary_layer3|final_write_state|Canary OK)'`. Expect:
   - One line confirming Layer 3 invoked (the new `logger -t` redirect shows the script's stderr, OR the absence of any `canary_layer3_*` failure reason proves it executed and passed).
   - `final_write_state 0 "ok"` confirming the deploy completed.
5. `gh issue comment 3033 --body "Verified: Layer 3 executed in deploy run <run_id>; final_write_state 0 ok. Closing." && gh issue close 3033`.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `apps/web-platform/infra/ci-deploy.sh` `CANARY_LAYER_3_SCRIPT` default points to `/usr/local/bin/canary-bundle-claim-check.sh`.
- [ ] `apps/web-platform/infra/server.tf` `terraform_data.deploy_pipeline_fix` ships `canary-bundle-claim-check.sh` to `/usr/local/bin/canary-bundle-claim-check.sh` with `chmod +x` and is included in `triggers_replace`.
- [ ] `apps/web-platform/infra/cloud-init.yml` `write_files` includes a `/usr/local/bin/canary-bundle-claim-check.sh` entry rendered from `${canary_bundle_claim_check_script_b64}`; the templatefile() call in `server.tf` passes that variable.
- [ ] `apps/web-platform/infra/canary-bundle-claim-check.sh` enumerates all chunk references from `/login` HTML (cap 20), probes each for an `eyJ...` JWT, and validates claims on the first match. SKIP-vs-FAIL semantics match the matrix in Phase 2 (every non-zero exit is a hard fail; no SKIP outcome).
- [ ] Path-validation regex `^/_next/static/chunks/[A-Za-z0-9_/().-]+\.js$` is applied to each candidate before string-interpolation into the curl URL.
- [ ] `--max-time 5` and `--max-filesize 5242880` are pinned on every chunk fetch in the new traversal loop.
- [ ] `apps/web-platform/infra/ci-deploy.sh` Layer 3 invocation captures script stderr via `logger -t "$LOG_TAG" -p user.warning`, preserving rc via `${PIPESTATUS[0]}`. CANARY_FAIL_REASON contract preserved (still maps to `canary_layer3_jwt_claims` umbrella); specific reasons available in journalctl side-channel.
- [ ] Script keeps `set -uo pipefail` (NOT `-euo`) — work-phase must NOT add `-e`. Per Phase 2 "Decode Pipeline & Strict-Mode Discipline" subsection, the loop intentionally tolerates per-iteration failures.
- [ ] Decode pipeline uses `jq -er` (with explicit non-zero-rc fail-closed) on `iss`, `role`, `ref` extraction. Verified at deepen time: cloud-init.yml installs `jq` on every host.
- [ ] Tempfile cleanup uses `mktemp -d` for chunk cache + `rm -rf "$CHUNK_DIR"` in the EXIT trap.
- [ ] Log-injection guard applied to decoded claim values: `LC_ALL=C tr -d '\000-\037\177'` AND `sed` strip of UTF-8 byte sequences for U+2028 (`E2 80 A8`) and U+2029 (`E2 80 A9`) before any `echo` to stderr (mirrors the 2026-04-28 anon-key learning #6).
- [ ] `apps/web-platform/infra/canary-bundle-claim-check.test.sh` exists, contains 13 fixtures (F1–F13), all green locally.
- [ ] CI discoverability: after creating the test file, `grep -rn 'canary-bundle-claim-check' .github/workflows/` matches at least one workflow that runs the test (or the work-phase has filed a tracking issue per `wg-when-an-audit-identifies-pre-existing`).
- [ ] Test harness uses OS-allocated ephemeral port via the `python3 -c 'import socket; ...'` form (NOT a hardcoded port or random-range pick) and waits for the http server with a hard timeout (≤4 s) before invoking the script.
- [ ] `bash apps/web-platform/infra/ci-deploy.test.sh` green — `MOCK_LAYER3_FAIL` rollback fixture preserved.
- [ ] `bash apps/web-platform/infra/canary-bundle-claim-check.sh https://app.soleur.ai` returns exit 0 against current prod (live smoke).
- [ ] `terraform -chdir=apps/web-platform/infra plan` shows `terraform_data.deploy_pipeline_fix` in `replace`; `terraform validate` passes.
- [ ] PR body uses `Ref #3033` (NOT `Closes #3033`) — closure happens post-merge after the operator runs `terraform apply` and verifies Phase 4 succeeded. (Per the AGENTS.md sharp-edge for `ops-remediation` plans whose fix executes post-merge.)

### Post-merge (operator)

- [ ] `terraform apply` (per-command ack) pushes the canary script to `/usr/local/bin/canary-bundle-claim-check.sh` on the live host. Hash matches source.
- [ ] `gh workflow run web-platform-release.yml --ref main` triggers a deploy that completes with `success`.
- [ ] `journalctl -u webhook` for the deploy run shows Layer 3 executed (no `canary_layer3_*` failure-reason; deploy reaches `final_write_state 0 "ok"`).
- [ ] Issue #3033 closed with a deploy-run-id breadcrumb in a comment.

## Test Scenarios

(Detailed in Phase 3 fixture matrix F1–F13. Summarized as Acceptance Criteria above.)

## Risks

1. ~~**`jq` may not be installed on the canary host.**~~ **Resolved at deepen time:** `cloud-init.yml` line 7 ships `jq` in the host package list. Phase 2 uses `jq -er` outright with no conditional fallback.
2. **`terraform_data.deploy_pipeline_fix` `triggers_replace` already churns on every push of `ci-deploy.sh`** (it's the documented design). Adding `canary-bundle-claim-check.sh` to the join means the resource is also re-applied on canary-script-only changes — desired behavior, but operator-visible as another `replace` line in plan output. Document in the PR body.
3. **The `python3 -m http.server` test harness binds a random port that may collide with other test fixtures running in parallel.** Mitigation: pick a port via `python3 -c 'import socket; s=socket.socket(); s.bind(("",0)); print(s.getsockname()[1])'` AND wait for `curl -s -o /dev/null -w '%{http_code}' http://localhost:$port/health` to return 200 before running the script. (Standard `bash` test harness pattern — not novel.)
4. **The canary loop's `[[ -x "$CANARY_LAYER_3_SCRIPT" ]]` gate currently masks the mount-missing failure mode silently.** After this fix, if the script is removed from `/usr/local/bin/` (terraform drift, manual `rm`, etc.), Layer 3 will go back to silent-skip. Mitigation: track in the existing terraform-drift weekly cron output (already monitors `deploy_pipeline_fix`). Alternative considered: change the gate to `[[ -e "$CANARY_LAYER_3_SCRIPT" ]] || { echo "Layer 3 script missing"; exit 1; }` — REJECTED because it conflates "script genuinely missing" (configuration regression) with "first deploy after server reprovisioning" (legitimate transient). Track via terraform drift report, not gate enforcement.
5. **Bundle layout drifts again in a future Webpack/Next.js upgrade.** Mitigation: the dynamic-discovery loop is robust to where the JWT lives. The cap of 20 chunks is generous (current prod loads 13). If a future release exceeds 20 chunks at `/login`, F13 will catch it AND the canary will start failing — the operator review is the gate, not silent-skip.

6. **The `/mnt/data/plugins/soleur` mount that already exists in `ci-deploy.sh` is also empty in production.** Discovered during deepen-pass: no rsync, no `git clone`, no terraform provisioner populates `/mnt/data/plugins/soleur` either. Code in the running app references `/app/shared/plugins/soleur` (`workspace.ts:39`, `cc-dispatcher.ts:387`, `agent-runner.ts:542`) which resolves to an empty directory at runtime. Mitigation: out of scope for this PR — the work-phase MUST file a follow-up tracking issue with: (a) which call-sites are affected, (b) whether the empty-mount behavior is a latent bug or a best-effort no-op (`workspace.ts:381-384` warn-on-failure suggests the latter), (c) milestone for re-evaluation. Do NOT attempt to fold the fix into this PR.

7. **`terraform_data.deploy_pipeline_fix` weekly drift cron will tag the resource as drifted.** Adding `canary-bundle-claim-check.sh` to `triggers_replace` means the resource hash changes whenever ANY of the four files (`ci-deploy.sh`, `webhook.service`, `cat-deploy-state.sh`, `canary-bundle-claim-check.sh`) is edited. Mitigation: the PR body's terraform-plan output must call this out so the CI drift report's auto-filed ticket (per `scheduled-terraform-drift.yml`) can be acknowledged as expected, not unexpected.

## Sharp Edges

- Editing `terraform_data.deploy_pipeline_fix` in `server.tf` AND `cloud-init.yml`'s `write_files` AND the templatefile() call must stay in sync (per existing comments in server.tf line 204-208). The plan touches all three files; the work-skill must verify all three edits land in one commit. Mismatches show up as: new server provisioning loses the canary script (cloud-init missing) OR existing server doesn't pick up the change (terraform_data missing) OR terraform plan fails (templatefile arg missing).
- `bash apps/web-platform/infra/canary-bundle-claim-check.sh https://app.soleur.ai` is the load-bearing pre-merge live smoke. If it returns exit 1 against current prod after the script change, the script itself is the regression — DO NOT MERGE; investigate. The current prod is known-canonical (verified 2026-04-29); a script-change that fails there means the script is wrong, not the bundle.
- The `< /tmp/canary-l3-candidates.txt` redirect in the `while read` loop is load-bearing for variable scope. A pipe (`cat ... | while read`) scopes loop variables to a subshell and `jwt_chunk` will be empty at end-of-loop. (Same precedent as PR #3029 SKILL.md Step 5.2.)
- The `--max-filesize 5242880` (5 MB) cap on each chunk fetch is load-bearing. A misbehaving CDN response can fill `/tmp` (which is a 256MB tmpfs in the canary container, NOT on the host — but the script runs on the HOST where `/tmp` is real disk; still, 20 × unbounded fetches is a DoS surface).
- The `^/_next/static/chunks/[A-Za-z0-9_/().-]+\.js$` regex is load-bearing for command-injection defense even though the source HTML is served by our own CDN. The threat model is: a future upstream supply-chain compromise injects a chunk URL with `..`, `;`, backtick, or `$(...)` into the `/login` HTML; without the regex the curl URL becomes attacker-controlled.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is filled in.)
- `Closes #3033` MUST NOT appear in the PR body. Use `Ref #3033`. Issue closure happens after Phase 4 operator verification, NOT at merge — `Closes` would auto-close before the actual fix runs (per AGENTS.md `cq-`-class sharp edge for ops-remediation).
- The script's first line is `set -uo pipefail` — DO NOT change to `set -euo pipefail` "for safety". The traversal loop intentionally tolerates per-iteration `curl` and `grep` failures; `-e` would abort on the first per-chunk failure and revert the gate to the brittle behavior the fix is closing. Per `2026-04-21-cloud-task-silence-watchdog-pattern.md`. Decision points are guarded with explicit per-statement rc checks.
- The `${PIPESTATUS[0]}` form in `ci-deploy.sh` is load-bearing — `| logger` always exits 0, so a naked `if !` would always pass through silently. A future refactor that drops the pipe MUST also drop the `${PIPESTATUS[0]}` reference back to `$?`.
- `LC_ALL=C tr -d '\000-\037\177'` is byte-level, not locale-aware. `tr` without `LC_ALL=C` may NOT strip C0 in non-C locales — verified against `tr` in `coreutils 9.x` on Ubuntu 22.04. The `LC_ALL=C` prefix is load-bearing for the log-injection guard.
- `sed` clauses for U+2028 (`\xe2\x80\xa8`) and U+2029 (`\xe2\x80\xa9`) are required IN ADDITION TO `tr` because these are 3-byte UTF-8 sequences, not single bytes. A `tr` strip alone leaks them through the C0 gate.

## Domain Review

**Domains relevant:** none (infrastructure / probe surface, no user-facing or product implications)

This change touches the deploy pipeline and a probe script. There is no product surface, no user data, no copy, no marketing surface, no legal surface, no architectural pattern beyond the already-established `terraform_data.deploy_pipeline_fix` precedent. Skipping domain leader spawning per `pdr-do-not-route-on-trivial-messages-yes` — the domain signal IS the current task's topic (engineering/ops).

## Open Code-Review Overlap

One open code-review issue references `apps/web-platform/infra/server.tf` in its body, but the match is incidental:

- **#2197** — billing/SubscriptionStatus refactor; mentions `server.tf` as one of several files in a different context (subscription status type tracking). **Disposition: acknowledge.** No fold-in (different concern, different file region — `server.tf` is large and the canary-related edits are scoped to the `terraform_data.deploy_pipeline_fix` block at lines 209-269; #2197's concerns are unrelated).

No other matches across `ci-deploy.sh`, `cloud-init.yml`, `canary-bundle-claim-check.sh`, or `ci-deploy.test.sh`.

## Research Insights

**From PR #3029 (#3010 plan, merged 2026-04-29):**

- Dynamic chunk discovery via `<script src>` enumeration is the correct pattern for "find the chunk that holds X" against a Next.js bundle. Current prod loads 13 chunks; cap of 20 is generous.
- Subshell-variable-scope trap on `cat ... | while read` is a real pitfall — the redirected-stdin form (`< file`) preserves loop variables.
- `--max-filesize 5242880` and `--max-time` are required hardenings; unbounded fetches against attacker-controllable upstream is a DoS surface.
- Path-regex `^/_next/static/chunks/[A-Za-z0-9_/().-]+\.js$` is the canonical defense against command-injection via crafted chunk names — even when the upstream is our own CDN.

**From `knowledge-base/project/learnings/2026-04-27-preflight-security-gates-skip-vs-fail-defaults.md`:**

- SKIP semantics differ between informational and invariant gates. The canary's Layer 3 is an invariant gate; SKIP is wrong; every uncertain outcome should fail closed.

**From `knowledge-base/project/learnings/bug-fixes/2026-04-28-anon-key-test-fixture-leaked-into-prod-build.md` (session error #6):**

- `jq -r` does not escape control characters. A crafted JWT with `\n::notice::PASS` in a claim string value can smuggle a synthetic GitHub Actions annotation. Strip C0 controls (`\x00–\x1f`), DEL (`\x7f`), U+2028, U+2029 from claim values before any echo to stderr or stdout. Test fixture F12 enforces this.

**Live verification (2026-04-29):**

- `curl -fsSL https://app.soleur.ai/login | grep -oE '/_next/static/chunks/[^"]+\.js' | sort -u | wc -l` → 13.
- Login chunk `page-f2f3d55448d7908c.js` size = 4762 bytes, JWT count = 0.
- `8237-323358398e5e7317.js` contains exactly one `eyJ...` match (208 chars). Decode: `{iss:supabase, role:anon, ref:ifsccnjhymdmidffkzhl}` (canonical).
- `bash apps/web-platform/infra/canary-bundle-claim-check.sh https://app.soleur.ai` exits 1 with `no JWT found in login chunk` (current main behavior, confirms diagnosis).

## Files to Edit

- `apps/web-platform/infra/ci-deploy.sh` (Phases 1 + 2 — `CANARY_LAYER_3_SCRIPT` default + comment update + Layer 3 stderr capture).
- `apps/web-platform/infra/canary-bundle-claim-check.sh` (Phase 2 — dynamic chunk discovery, log-injection guard, refined exit-reason granularity).
- `apps/web-platform/infra/server.tf` (Phase 1 — `terraform_data.deploy_pipeline_fix` extension + templatefile arg).
- `apps/web-platform/infra/cloud-init.yml` (Phase 1 — `write_files` entry).
- `apps/web-platform/infra/ci-deploy.test.sh` (Phase 3 — only if reason-string contract changes propagate; expected: no edit).

## Files to Create

- `apps/web-platform/infra/canary-bundle-claim-check.test.sh` (Phase 3 — 13-fixture matrix).
