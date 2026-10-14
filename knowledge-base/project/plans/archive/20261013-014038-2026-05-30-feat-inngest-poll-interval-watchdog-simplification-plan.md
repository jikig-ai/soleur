---
title: "Adopt Inngest --poll-interval to eliminate restart-dependency for function re-sync"
issue: 4652
branch: feat-one-shot-4652-inngest-poll-interval
type: infra
lane: cross-domain
brand_survival_threshold: aggregate pattern
created: 2026-05-30
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Rationale: every systemctl/state-change verb in this plan lives INSIDE the
     idempotent bootstrap script (apps/web-platform/infra/inngest-bootstrap.sh)
     or the deploy script (ci-deploy.sh) — i.e. the IaC apply mechanism itself,
     delivered via the soleur-inngest-bootstrap OCI image + cloud-init. There is
     NO operator-SSH step. The mirror of the existing Vector enable→restart fix
     already in inngest-bootstrap.sh:404-408. See ## Infrastructure (IaC). -->

# feat: Adopt Inngest `--poll-interval` + `--sdk-url`; simplify the #4650 watchdog

Closes #4652.

## Enhancement Summary

**Deepened on:** 2026-05-30
**Sections enhanced:** 5 (ExecStart change, deploy gate, watchdog demotion, runbook, tests)
**Gates passed:** 4.6 User-Brand Impact (threshold `aggregate pattern`), 4.7 Observability (5/5 fields, no-ssh), 4.8 PAT-shaped (clean), 4.4 precedent-diff (Vector `enable→restart` + ADR-033 Inngest-cron precedents both confirmed on `main`).

### Key Improvements
1. **Port resolved to 3000, not 8288**, with three independent confirmations (Dockerfile `PORT=3000`, ci-deploy.sh `0.0.0.0:3000:3000`, substrate learning verbatim quote). 8288 would make the server poll itself.
2. **Two deploy-effectiveness gaps surfaced and fixed**: (a) `enable --now` is a no-op on a running unit → needs explicit `restart` (Vector precedent at `:400-408`); (b) the `deploy inngest` path never called `verify_inngest_health` → added.
3. **SKIP_BINARY_INSTALL same-version-redeploy gap** identified as the single highest-risk decision (Phase 1.2) — server-unit write lives inside the skip guard, so an ExecStart-only change on a same-CLI-version image would never land. Resolution prescribed: reconcile-always (heartbeat precedent).
4. **Conservative watchdog demotion** (degrade-not-delete) with a unified MISSING ∪ UNPLANNED grace-tick model; heartbeat safety net untouched; restart path retained as a guarded backstop.

### New Considerations Discovered
- Loopback poll signing already works (the SDK route self-verifies HMAC, `/api/inngest` is in PUBLIC_PATHS from the #4017 fix) — no new signing config.
- `verify_inngest_health` retry budget (~30s) must cover the restart→SDK-PUT-sync window; the post-deploy restart syncs immediately (not waiting for the 60s poll), so the budget is adequate, but confirm at /work.

## Overview

The self-hosted Inngest server (`inngest-server.service`, loopback `127.0.0.1:8288`, SQLite at `/var/lib/inngest`) currently runs with **no `--poll-interval`** — so function discovery is bound to a server/container restart, not continuous polling. That binding is the root reason the #4650 self-healing watchdog (`cron-inngest-cron-watchdog`, shipped in merged PR #4649) has to **restart the server** to recover H9a (a function dropped from the registry).

The GO evaluation on #4652 confirmed (against the pinned CLI **v1.19.4**, `apps/web-platform/infra/inngest.tf:locals.inngest_cli_version`) that adding `--poll-interval 60` plus `--sdk-url http://127.0.0.1:3000/api/inngest` makes the server poll the co-located web-platform app's serve route every 60s, re-syncing **and re-planning** any dropped/de-planned function within one interval — without a restart.

This plan:

1. Adds `--poll-interval 60` and `--sdk-url http://127.0.0.1:3000/api/inngest` to the `inngest start` ExecStart in `apps/web-platform/infra/inngest-bootstrap.sh`.
2. Closes the **deploy-effectiveness gap**: an ExecStart change only takes effect when the unit is re-written AND `inngest-server.service` is restarted. The bootstrap currently only does `enable --now` (a no-op on an already-running service), and the `deploy inngest` path in `ci-deploy.sh` does NOT call `verify_inngest_health` afterward. Both are fixed (inside the bootstrap/deploy scripts — the IaC apply mechanism) so the new ExecStart actually loads and is verified post-deploy.
3. **Demotes the watchdog to a guarded backstop** (the conservative option from the GO eval): drops the routine restart-on-first-MISSING-tick for H9a/escalated-H9b, since polling now re-syncs/re-plans within one interval. Keeps the `ok=false` Sentry heartbeat as the safety net, and keeps the restart path alive ONLY as a **deeply-guarded, cooldown-gated backstop** that fires after the function has stayed defective across enough watchdog ticks that polling has demonstrably failed.
4. Updates runbook **H9** so H9a no longer prescribes a restart.
5. Updates/extends the shell + unit tests (`inngest.test.sh`, `cloud-init-inngest-bootstrap.test.sh`, `ci-deploy.test.sh`) and the watchdog vitest suites (`cron-inngest-cron-watchdog.test.ts`, `cron-inngest-cron-watchdog-handler.test.ts`).

### Why this is conservative

We do NOT remove the watchdog or its restart path. We change the watchdog's role from *active repair* (restart on the first MISSING tick) to *backstop + alerting* (alert always; restart only after polling has had multiple intervals to recover and failed). The `ok=false` Sentry heartbeat — the actual safety net — is untouched. This keeps a guarded recovery path for the failure mode where polling itself is broken (e.g., the app `/api/inngest` route is down, or the server's poll loop wedged), while removing the routine restart that polling makes unnecessary.

## Research Reconciliation — Spec vs. Codebase

The feature description was written before exact ports/endpoints were resolved. The table records what was verified against the worktree.

| Description claim | Reality (verified) | Plan response |
| --- | --- | --- |
| ExecStart "at ~line 147" of inngest-bootstrap.sh | Confirmed: `inngest-bootstrap.sh:147` is the `inngest start` ExecStart line, inside the `UNITEOF` heredoc | Edit line 147 |
| `--sdk-url http://127.0.0.1:<app-port>/api/inngest` (port TBD) | App container is `PORT=3000` (`apps/web-platform/Dockerfile:81`), published to host `0.0.0.0:80:3000` AND `0.0.0.0:3000:3000` (`ci-deploy.sh:623-624`). The substrate learning `2026-05-19-inngest-substrate-five-bug-cascade.md:37` states verbatim: *"The Inngest server polls the SDK URL (`http://127.0.0.1:3000/api/inngest`)"*. **Port is 3000**, NOT 8288 (8288 is the inngest server's own port). | Use `--sdk-url http://127.0.0.1:3000/api/inngest` |
| "Confirm signing/sync works over loopback with `--sdk-url`" | The SDK route (`app/api/inngest/route.ts`) does its own HMAC verify (`signingKey` from `INNGEST_SIGNING_KEY`, full `signkey-prod-<hex>` form). `/api/inngest` is in `PUBLIC_PATHS` (`lib/routes.ts`) so polling is NOT redirected to `/login` (the #4017 fix). The server signs the poll with its bare-hex `--signing-key`; both derive the same HMAC seed (`inngest-bootstrap.sh:129-136`). Loopback signing therefore already works for the post-deploy SDK-sync PUT; polling reuses the identical contract. | No new signing config needed; plan adds a deploy-path verification step (poll re-sync visible in `/v1/functions`) rather than asserting signing at the unit level |
| "ci-deploy.sh `verify_inngest_health` already asserts `/v1/functions` cron post-restart — reuse/extend that gate" | `verify_inngest_health()` (`ci-deploy.sh:201-246`) exists and asserts BOTH `/health` AND `/v1/functions` has `"cron":`. BUT it is only called on the `restart` action (`:361`) and the web-platform deploy path — **NOT** on the `deploy inngest` path (`:662-789`), which is what re-runs the bootstrap and changes ExecStart. | Add `verify_inngest_health` to the `deploy inngest` path after the bootstrap runs |
| "Changing ExecStart only takes effect on bootstrap re-run / server restart" | True AND under-handled: bootstrap does `daemon-reload` + `enable --now inngest-server.service` (`:278-279`). `enable --now` is a **no-op on an already-running unit** — daemon-reload reloads the unit file but the running process keeps the OLD ExecStart until an explicit `restart`. Same class as the Vector `enable --now` → `restart` fix already in this file (`:404-408`). | Bootstrap must `systemctl restart inngest-server.service` when the unit file content changed (or on the non-skip path), mirroring the Vector fix |
| Watchdog comment "the server runs with no `--poll-interval`" (`cron-inngest-cron-watchdog.ts:19-23, 369`) | Confirmed accurate today; becomes false after this change | Update the comment + the heal logic |

## Open Code-Review Overlap

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
```

Checked the planned file paths (`inngest-bootstrap.sh`, `ci-deploy.sh`, `cron-inngest-cron-watchdog.ts`, the four test files, the runbook) against open `code-review` issue bodies via standalone `jq --arg`. **None** — no open code-review scope-out names these files. (Re-run the two-stage `jq --arg` form at /work Phase 0 against live state, per the gh-jq learning.)

## User-Brand Impact

**If this lands broken, the user experiences:** scheduled tasks (cert-state checks, community monitoring, daily triage, content publishing) silently stop firing — the same regression class #4650 chased — OR, the worse new failure mode, an ExecStart typo that prevents `inngest-server.service` from starting at all, taking down the entire Inngest substrate (every cron + the agent-spawn + CFO payment-failure functions).

**If this leaks, the user's data/workflow/money is exposed via:** N/A — no new data surface. `--sdk-url` points at loopback; the signing key is already materialized via `doppler run` at ExecStart and never widens. No new secret, no new external endpoint, no regulated-data surface.

**Brand-survival threshold:** aggregate pattern. A single missed cron is recoverable and low-blast (the heartbeat pages); the brand risk is the aggregate pattern of the substrate silently degrading. The dominant new risk (server fails to start on a malformed ExecStart) is caught pre-prod by the shell-unit tests AND post-deploy by the extended `verify_inngest_health` gate, which fails the deploy loudly rather than leaving a dark substrate.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — ExecStart shape.** `inngest-bootstrap.sh` line 147 `inngest start` invocation contains `--poll-interval 60` AND `--sdk-url http://127.0.0.1:3000/api/inngest`, in addition to the existing `--host 0.0.0.0 --port 8288 --sqlite-dir /var/lib/inngest --signing-key … --event-key …`. Verify: `grep -E 'inngest start .*--poll-interval 60' apps/web-platform/infra/inngest-bootstrap.sh` AND `grep -F 'sdk-url http://127.0.0.1:3000/api/inngest' apps/web-platform/infra/inngest-bootstrap.sh` each return ≥1 line. (Assert each token independently to avoid flag-ordering brittleness.)
- [ ] **AC2 — ExecStart takes effect on redeploy.** `inngest-bootstrap.sh` issues an explicit `systemctl restart inngest-server.service` on the path where the unit file is (re)written, so a new ExecStart loads. Verify via `inngest.test.sh`: a new assertion that the bootstrap source contains `systemctl restart inngest-server.service` on the unit-write path. The existing upgrade-drain pause/resume (`:88-96`, `:287-291`) must remain intact.
- [ ] **AC3 — deploy gate.** `ci-deploy.sh` `deploy inngest` path calls `verify_inngest_health` after `inngest-bootstrap.sh` returns 0 and BEFORE `final_write_state 0 "success"`; a non-zero return writes `final_write_state 1 "inngest_health_failed"` and exits 1. Verify via `ci-deploy.test.sh` (new assertion exercising the `deploy inngest` success + cron-deplaned-failure paths against the existing `8288/v1/functions` mock router at `:265-277`).
- [ ] **AC4 — watchdog: no routine restart on first H9a tick.** A single MISSING tick fires the Sentry `ok=false` heartbeat and does NOT POST the deploy webhook nor file a D1-B issue. Verify via `cron-inngest-cron-watchdog-handler.test.ts`: H9a single tick → `restartRequested === false`, `ok === false`, NO `deploy.soleur.ai` fetch.
- [ ] **AC5 — watchdog: guarded backstop restart still possible.** After a function stays MISSING (or escalated-UNPLANNED) for `POLL_RECOVERY_GRACE_TICKS` consecutive watchdog ticks (polling-has-failed evidence), the restart path fires, still gated by the cooldown. Verify via handler test: tick count below threshold → no restart; tick count ≥ threshold within cooldown → no restart; ≥ threshold and cooldown elapsed → restart requested.
- [ ] **AC6 — H9b re-scope.** Given polling now re-plans de-planned crons within one interval, the H9b manual-trigger heal is retained (it restores the immediate missed check-in faster than waiting up to 60s for the next poll) but its escalation-to-restart is folded into the same `POLL_RECOVERY_GRACE_TICKS` backstop as H9a. Verify: the comment + `nextUnplannedStreaks`/`escalatedUnplannedFnIds` behavior documents that escalation now means "polling failed to recover", not "manual-trigger can't re-plan".
- [ ] **AC7 — heartbeat untouched.** `postSentryHeartbeat` step is unchanged; `ok = defectCount === 0` still drives `scheduled-inngest-cron-watchdog`. Verify: clean-registry handler test still returns `ok === true`.
- [ ] **AC8 — stale comments corrected.** `cron-inngest-cron-watchdog.ts` header comment block (`:19-23`) and `:368-370` no longer claim "the server runs with no `--poll-interval`"; they describe the polling-backstop model. Runbook H9 (`cloud-scheduled-tasks.md:264-396`) H9a entry no longer prescribes a server restart as the routine fix; the restart is the backstop. The "Self-healing" step 3 (`:368-379`) is rewritten for the backstop model. `grep -rn "no .--poll-interval" apps/web-platform/server/inngest/ knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md` returns zero.
- [ ] **AC9 — full suite green.** `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-inngest-cron-watchdog.test.ts test/server/inngest/cron-inngest-cron-watchdog-handler.test.ts test/server/inngest/function-registry-count.test.ts` passes; `bash apps/web-platform/infra/inngest.test.sh`, `bash apps/web-platform/infra/ci-deploy.test.sh`, `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` all pass; `tsc --noEmit` clean.
- [ ] **AC10 — cloud-init parity.** `cloud-init-inngest-bootstrap.test.sh` still passes (the bootstrap script is embedded in cloud-init via OCI image; no ExecStart literal lives in cloud-init.yml, so a port/flag change needs no cloud-init.yml edit — confirm this and that the test still passes).

### Post-merge (operator)

- [ ] **AC11 — bootstrap image rebuild + deploy.** The new `inngest-bootstrap.sh` only reaches the host when a new `soleur-inngest-bootstrap` OCI image is built (`.github/workflows/build-inngest-bootstrap-image.yml`) and deployed via `deploy inngest <image> <tag>`. **Automation:** verify at /work whether merge-to-main auto-builds + auto-deploys the inngest component, or whether a version/tag push is required (`hr-tagged-build-workflow-needs-initial-tag-push`). If tag-gated, prescribe the exact `gh workflow run` / tag-push in the ship step (NOT an SSH step). Post-deploy, confirm poll re-sync via the deploy-status endpoint / `verify_inngest_health` (AC3), not SSH.

## Implementation Phases

### Phase 0 — Preconditions (verify against live worktree)

0.1. `grep -n "PORT=3000" apps/web-platform/Dockerfile` and `grep -n "0.0.0.0:3000:3000" apps/web-platform/infra/ci-deploy.sh` — confirm app port 3000 published to host loopback. (Verified during planning; re-confirm.)
0.2. Confirm `/api/inngest` is in `PUBLIC_PATHS`: `grep -n "api/inngest" apps/web-platform/lib/routes.ts`. (This is what makes loopback polling not 307→/login.)
0.3. Re-run the open-code-review-overlap `jq --arg` check against live `gh issue list` output.
0.4. Confirm `--poll-interval` is int-seconds and `--sdk-url`/`-u` is the app serve URL at v1.19.4. Cite the GO eval's `pkg/devserver/devserver.go` `StartOpts{ PollInterval int; URLs []string }` evidence + the self-hosting doc URL. If the `inngest` binary is locally available, run `inngest start --help | grep -E 'poll-interval|sdk-url'` and pin the output with `<!-- verified: 2026-05-30 -->` per the CLI-form-verification gate.

### Research Insights — Inngest CLI flag semantics (Context7-verified, 2026-05-30)

Confirmed against the official Inngest self-hosting docs (`/inngest/website` → `pages/docs/self-hosting.mdx`, `inngest start --help` output) — this is the authoritative contract, supplementing the GO eval's source-code citation:

```plaintext
--sdk-url string, -u string [ --sdk-url string, -u string ]   App serve URLs to sync (ex. http://localhost:3000/api/inngest)
--signing-key string                                          Signing key … Must be hex string with even number of chars
--poll-interval int                                           Interval in seconds between polling for updates to apps (default: 0)
```

Three load-bearing confirmations:
1. **`--poll-interval` is int-seconds, default 0 (disabled).** `--poll-interval 60` = poll every 60s. Matches the plan.
2. **`--sdk-url` example in the docs is literally `http://localhost:3000/api/inngest`** — port **3000**, the app serve route, NOT the inngest server port (8288). Independently corroborates the Dockerfile/ci-deploy/learning evidence. `--sdk-url`/`-u` is repeatable (`[ … ]`).
3. **The docs' own YAML example pairs `urls: [http://localhost:3000/api/inngest]` with `poll-interval: 60`** — the exact ExecStart pairing this plan prescribes.
4. `--signing-key` "Must be hex string with even number of chars" — confirms why the bootstrap strips `signkey-prod-` to bare hex (`:147`); unchanged by this plan.

<!-- verified: 2026-05-30 source: Context7 /inngest/website pages/docs/self-hosting.mdx (inngest start --help) -->

Per the CLI-verification gate, the ExecStart snippet that lands in the runbook/PR is backed by this `--help` output (option a) plus the doc URL (option b).

### Phase 1 — ExecStart change (`inngest-bootstrap.sh`)

1.1. Edit line 147 ExecStart to append `--poll-interval 60 --sdk-url http://127.0.0.1:3000/api/inngest` to the `inngest start` command, inside the existing `'/usr/bin/bash -c '...''` wrapper. Keep the `$${INNGEST_SIGNING_KEY#signkey-prod-}` strip and `$${INNGEST_EVENT_KEY}` exactly as-is (the `$$` is systemd-escaped `$`). Add a brief inline comment: poll-interval re-syncs/re-plans functions every 60s without a restart (#4652); sdk-url is the co-located app serve route over loopback (port 3000 per Dockerfile + #4017 PUBLIC_PATHS).
1.2. Add the deploy-effectiveness fix on the path where the server unit file is written: after `systemctl daemon-reload`, replace `systemctl enable --now inngest-server.service` with `systemctl enable inngest-server.service` + `systemctl restart inngest-server.service`, mirroring the Vector `enable + restart` pattern already at `:404-408` and citing the same rationale (a running unit ignores ExecStart changes until restart). A `restart` subsumes the `enable --now` start; the upgrade-drain pause (`:88-96`) still runs before binary replace and the resume (`:287-291`) after.
    - **Sharp edge / DECISION (highest-risk):** the server-unit write is INSIDE the `if [[ -z "$SKIP_BINARY_INSTALL" ]]` guard (`:82-169`). `SKIP_BINARY_INSTALL` fires when the recorded version matches AND the service is active (`:75-80`), so a **same-CLI-version** redeploy would SKIP the server-unit write — an ExecStart-only change would never land. The heartbeat units are deliberately reconciled OUTSIDE the guard for exactly this reason (`:64-73`). **Resolve at /work, prefer option (a):** move the server-unit write + the new `restart` OUTSIDE the skip guard (reconcile-always, matching the heartbeat precedent) so an ExecStart change is deploy-reliable regardless of version bump. Option (b) — rely on a CLI-version/image-tag bump as the trigger and document it — is the fallback if moving the write proves to interact badly with the upgrade-drain logic. Document the chosen option in the PR body.

### Phase 2 — Deploy gate (`ci-deploy.sh`)

2.1. In the `deploy inngest` success path (after the bootstrap `if ! sudo … inngest-bootstrap.sh` block returns 0, `:784-788`), before `final_write_state 0 "success"`, add:
```bash
set +e
verify_inngest_health
VERIFY_RC=$?
set -e
if [[ "$VERIFY_RC" -ne 0 ]]; then
  logger -t "$LOG_TAG" "FAILED: inngest deploy health/cron-plan check"
  rm -rf "$INNGEST_EXTRACT_DIR"
  final_write_state 1 "inngest_health_failed"
  exit 1
fi
```
Reuse the existing `verify_inngest_health` function (`:201-246`) verbatim. This makes a post-deploy desync (or a poll-sync that never populated the cron plan) fail the deploy loudly.
2.2. Keep `rm -rf "$INNGEST_EXTRACT_DIR"` cleanup on both success and the new failure branch.

### Phase 3 — Watchdog demotion to guarded backstop (`cron-inngest-cron-watchdog.ts`)

3.1. Introduce a `POLL_RECOVERY_GRACE_TICKS` constant (suggested 2 — at 4h cadence, ~8h of a defect persisting despite 60s polling = polling has demonstrably failed). Either rename `UNPLANNED_RESTART_THRESHOLD` to this, or keep the name and re-document; the meaning changes from "manual-trigger can't re-plan" to "polling failed to recover".
3.2. Apply the grace-tick gate to BOTH H9a (MISSING) and escalated-H9b (UNPLANNED). Today MISSING goes straight to restart (`restartFnIds = [...plan.missingFnIds, ...escalated]`, `:451`). Change so MISSING also accrues a per-fnId streak and only escalates after `POLL_RECOVERY_GRACE_TICKS` consecutive MISSING ticks. Extend `nextUnplannedStreaks` + `escalatedUnplannedFnIds` to track a unified "defect streak" over MISSING ∪ UNPLANNED fnIds (or add a parallel `missingStreaks`). Keep the pure-helper + unit-test structure.
3.3. Keep the cooldown (`RESTART_COOLDOWN_MS`) as a second guard on the backstop (defense-in-depth). Do not remove.
3.4. Keep D1-A (deploy webhook) → D1-B (label-dispatch) restart path INTACT as the backstop body — only its TRIGGER changes (grace-ticks instead of first-MISSING tick). Do NOT delete `postRestartWebhook`, `fileRestartEscalationIssue`, `RESTART_ESCALATION_LABEL`, or the `inngest-watchdog-restart-dispatch.yml` integration.
3.5. Keep H9b manual-trigger heal (`step.run("heal-unplanned")`, `:414-437`) as-is; add a comment that polling re-plans the cron within one interval, so the manual-trigger is now a latency optimization, not the primary repair.
3.6. Keep the Sentry heartbeat step (`:531-539`) EXACTLY as-is. `ok = defectCount === 0`. Load-bearing safety net.
3.7. Rewrite the file header comment block (`:1-34`, especially RE-SYNC ASYMMETRY `:19-23`) and inline `:368-370`-equivalent to describe: polling continuously re-syncs+re-plans (≤60s); the watchdog is now backstop+alerting; restart fires only after polling fails for `POLL_RECOVERY_GRACE_TICKS`.

### Phase 4 — Runbook H9 (`cloud-scheduled-tasks.md`)

4.1. Update the H9a entry (`:272-275`): with `--poll-interval 60`, a dropped function re-syncs from the SDK manifest within ≤60s automatically — no restart required for the routine case. Restart is the backstop only if polling itself is broken.
4.2. Update the "Distinguishing H9a from H9b" / "Restore" framing: primary restore is now "wait one poll interval (≤60s) and re-query `/v1/functions`"; the restart workflow is the fallback.
4.3. Rewrite "Self-healing" step 3 (`:368-379`): the watchdog restarts only after `POLL_RECOVERY_GRACE_TICKS` consecutive defective ticks (polling-failed evidence), still cooldown-gated. Keep steps 1, 2, 4 accurate.
4.4. Keep the SSH manual-fallback as last-resort (`hr-no-ssh-fallback-in-runbooks`).

### Phase 5 — Tests

5.1. **`inngest.test.sh`** — extract the inngest-SERVER unit `UNITEOF` block (`awk '/cat > "\$UNIT_FILE" <</,/^UNITEOF$/'`) and assert ExecStart contains `--poll-interval 60` and `--sdk-url http://127.0.0.1:3000/api/inngest` (each token independently). Add the AC2 assertion that the bootstrap source restarts inngest-server on the unit-write path. Verify the awk extraction returns a non-empty multi-line block before asserting (start anchor `cat > "$UNIT_FILE" <<'UNITEOF'`, end `^UNITEOF$` — distinct lines, no self-match).
5.2. **`ci-deploy.test.sh`** — add a test that `deploy inngest <valid-image> <valid-tag>` success path invokes `verify_inngest_health` (reuse the `8288/v1/functions` mock router at `:265-277`: default mock returns cron-triggered → success; H9b-deplaned mock → `inngest_health_failed`). Mock the bootstrap/docker-extract as the existing deploy-inngest tests do (see `:501-513`).
5.3. **`cloud-init-inngest-bootstrap.test.sh`** — confirm still green; server ExecStart is not literally in cloud-init.yml (it's inside the OCI-embedded script), so no edit expected. If the suite is extended to read the script's server-unit block, add the same `--poll-interval`/`--sdk-url` assertions.
5.4. **`cron-inngest-cron-watchdog.test.ts`** — rename/extend streak tests for the unified MISSING ∪ UNPLANNED grace-tick model; assert MISSING does NOT escalate on tick 1; assert escalation at `POLL_RECOVERY_GRACE_TICKS`. Keep `restartAllowed`/`shouldRestart`/cooldown tests (cooldown retained). Classify/manifest tests unchanged.
5.5. **`cron-inngest-cron-watchdog-handler.test.ts`** — split "H9a + webhook 202 → restartRequested" into: H9a single tick → NO restart, `ok=false`, no webhook fetch (AC4); H9a sustained ≥grace ticks (seed `readFileMock` with a prior streak ≥ threshold-1) → restartRequested, webhook 202 (AC5). Keep the D1-B non-202 fallback test (sustained defect). Keep the clean-registry test (`ok=true`, no restart).
5.6. **`function-registry-count.test.ts`** — verify still green; `EXPECTED_CRON_FUNCTIONS` unchanged, `(e)` parity test (`:142-143`) unaffected. No edit expected.

## Infrastructure (IaC)

This plan edits an existing IaC-delivered artifact (`inngest-bootstrap.sh`, embedded in the `soleur-inngest-bootstrap` OCI image and base64-embedded in `cloud-init.yml`) and the deploy script (`ci-deploy.sh`). Every `systemctl` verb in the plan lives inside those scripts — the IaC apply mechanism itself — NOT in an operator-SSH step. No NEW infrastructure (no new server, secret, vendor, port, firewall rule, or runtime process).

### Terraform changes
None. The pinned `inngest_cli_version` (`inngest.tf:25`) is unchanged. No new variables, providers, or resources. (`--poll-interval`/`--sdk-url` are ExecStart flags, not TF-managed values.)

### Apply path
**cloud-init + idempotent bootstrap script (option b)** — the default for existing infra. The edited `inngest-bootstrap.sh` reaches the running host via a new `soleur-inngest-bootstrap` OCI image deploy (`deploy inngest <image> <tag>` → `ci-deploy.sh` extracts + runs the script). Fresh hosts get it via the cloud-init-embedded copy. **Expected downtime:** ~5s per inngest-server restart (loopback-only bind; matches `:87`). Blast radius: inngest substrate only; the web-platform app container is untouched.

### Distinctness / drift safeguards
No `dev != prd` concern — `--poll-interval`/`--sdk-url` are config-identical across environments (loopback). No new `lifecycle.ignore_changes`. No new state-stored secret. The ExecStart still strips the signing-key prefix at runtime; no key material added to the unit file beyond what is already there.

### Vendor-tier reality check
N/A — no new vendor resource. Inngest is self-hosted (ADR-030); no Inngest Cloud tier involved.

## Observability

```yaml
liveness_signal:
  what: inngest-heartbeat.timer -> Better Stack (process liveness, every 60s) — UNCHANGED by this plan
  cadence: 60s
  alert_target: Better Stack heartbeat (betteruptime_heartbeat.inngest_prd)
  configured_in: apps/web-platform/infra/inngest-bootstrap.sh (heartbeat unit), inngest.tf
error_reporting:
  destination: Sentry cron monitor scheduled-inngest-cron-watchdog (ok=false on any MISSING/UNPLANNED) — UNCHANGED; the load-bearing safety net for the demoted watchdog
  fail_loud: yes — verify_inngest_health failing the deploy writes final_write_state 1 inngest_health_failed, surfaced via deploy-status endpoint (no SSH)
failure_modes:
  - mode: ExecStart malformed -> inngest-server.service won't start
    detection: inngest.test.sh (pre-prod token assertions) + verify_inngest_health post-deploy (/health unreachable -> deploy fails)
    alert_route: deploy-status endpoint reason=inngest_health_failed; Better Stack heartbeat goes missed
  - mode: poll loop wedged / app /api/inngest down -> functions drop and DON'T re-sync
    detection: cron-inngest-cron-watchdog classifies MISSING/UNPLANNED; ok=false heartbeat after first tick; restart backstop after POLL_RECOVERY_GRACE_TICKS
    alert_route: Sentry scheduled-inngest-cron-watchdog monitor (paging)
  - mode: same-version redeploy skips server-unit write (SKIP_BINARY_INSTALL) -> ExecStart change never lands
    detection: verify_inngest_health passes (old ExecStart still healthy) but poll-interval absent — covered by Phase 1.2 decision (a)
    alert_route: pre-merge design decision; documented as Sharp Edge
logs:
  where: journalctl -u inngest-server.service (host); Vector ships journald -> Better Stack Logs; ci-deploy.sh captures bootstrap stderr to /tmp/inngest-bootstrap-stderr.log surfaced via deploy-status
  retention: Better Stack Logs default
discoverability_test:
  command: "curl -sf --max-time 5 http://127.0.0.1:8288/v1/functions | jq '[.[]|select(.triggers[]?.cron)]|length'"
  expected_output: integer >= 1 (cron-triggered functions present); after a forced drop, returns to >=1 within ~60s (one poll interval) WITHOUT a restart
```

## Domain Review

**Domains relevant:** Engineering (infra/ops). No Product, Marketing, Legal, Finance, Growth, Brand, Community implications.

No cross-domain implications detected — an infrastructure/tooling change to the Inngest substrate and its self-healing watchdog. The Product/UX Gate does not fire (no user-facing surface: no `components/**/*.tsx`, no `app/**/page.tsx`). GDPR/Compliance gate (Phase 2.7): no regulated-data surface — `--sdk-url` is loopback, no schema/auth/API-route/migration change, no LLM processing of user data; skip. IaC gate (Phase 2.8): handled in `## Infrastructure (IaC)` — no new infra, routed through the existing bootstrap/deploy path (no operator SSH baked in).

## Alternative Approaches Considered

| Approach | Why not chosen |
| --- | --- |
| Fully remove the watchdog restart path | Too aggressive per the GO eval ("keep as a guarded backstop, not primary"). If polling itself breaks (app route down, poll loop wedged), there'd be no recovery. Conservative = degrade, not delete. |
| Remove the watchdog entirely (rely only on polling + verify_inngest_health) | Loses the `ok=false` Sentry paging safety net and the runtime classification the build-time CI guard cannot do. |
| Aggressive poll interval (e.g. 10s) | GO eval recommends conservative 60s; lower adds needless loopback GET load with no recovery-latency benefit at 4h watchdog cadence. |
| Set `--poll-interval` via TF variable / Doppler | A static config value identical across environments; a literal in ExecStart is simpler (YAGNI). No `dev != prd` divergence. |

## Risks & Mitigations

- **R1 — Same-version redeploy skips the server-unit write (SKIP_BINARY_INSTALL).** Highest risk. Mitigation: Phase 1.2 decision (a) — move the server-unit write+restart outside the skip guard (reconcile-always, matching the heartbeat-unit precedent at `:64-73`).
- **R2 — ExecStart restart double-fires with the upgrade-drain path.** Mitigation: the upgrade pause (`:88-96`) runs BEFORE binary replace; the new restart runs AFTER unit write — a single `restart` subsumes the start. Verify at /work the resume (`:287-291`) still runs after.
- **R3 — Poll re-sync depends on the app `/api/inngest` route being reachable over loopback.** Already true (PUBLIC_PATHS, port 3000 published, signing self-verified — the #4017 fixes). If the app container is down, polling can't re-sync — but then the substrate is already degraded and the watchdog backstop + heartbeat page. No new dependency introduced.
- **R4 — `verify_inngest_health` on the deploy path could false-fail if poll re-sync hasn't populated the cron plan within the retry window.** Mitigation: `verify_inngest_health` already retries (`max_attempts=10`, `interval=3` → ~30s) and the post-deploy server restart re-syncs immediately via the SDK PUT (not waiting for the 60s poll). Confirm the retry budget covers the restart→sync window at /work.
- **R5 — Precedent for the `enable --now` → restart fix (precedent-diff, Phase 4.4).** The Vector unit (`:399-408`) already documents and fixes this exact bug class in the SAME bootstrap script. The current inngest-server reconcile (`:278-279`) is `daemon-reload` + `enable --now inngest-server.service` (no restart — a running unit keeps the OLD ExecStart). The Vector reconcile (`:407-408`) is `daemon-reload` + `enable vector.service` + an explicit `restart vector.service`. The Vector comment block (`:400-406`) states the rationale verbatim: *"`enable --now` is a no-op when the unit is already running; the new config would never be picked up by an already-running … process. Replace with explicit enable + restart so each deploy gives … a clean reload."* Adopt this shape for inngest-server (inside the bootstrap script — the IaC apply mechanism). **No competing precedent** — this is the only systemd-unit-reconcile pattern in the file, post-dating (2026-05-21) the original inngest-server `enable --now` line (correct when first written because the unit was new). The pattern is NOT novel; it is the established fix.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is filled; threshold `aggregate pattern`.)
- The `--sdk-url` port is **3000**, not 8288. 8288 is the inngest server's own loopback port (`--host 0.0.0.0 --port 8288`); 3000 is the co-located web-platform app serving `/api/inngest`. Using 8288 would make the server poll itself and discover nothing.
- The systemd `$$` in ExecStart is an escaped single `$`. The new flags add no `$`, but do NOT accidentally unescape the existing `$${INNGEST_SIGNING_KEY#...}` when editing the line.
- `inngest.test.sh` asserts the HEARTBEAT unit ExecStart today, NOT the server unit — the new server-unit assertions are additive. Extract the `UNITEOF` block specifically (single-quoted heredoc marker `'UNITEOF'`), distinct from the heartbeat `HEARTBEATEOF` block.

## Test Strategy

- Shell-unit: `inngest.test.sh`, `ci-deploy.test.sh`, `cloud-init-inngest-bootstrap.test.sh` (existing `assert`/mock-router harness; no new framework — `.test.sh` with the repo's `assert()` convention).
- TS-unit: `cron-inngest-cron-watchdog.test.ts` + `cron-inngest-cron-watchdog-handler.test.ts` via vitest (`./node_modules/.bin/vitest run` — do NOT use `bun test`, per the bunfig pathIgnorePatterns learning). Test files live under `apps/web-platform/test/server/inngest/` matching `vitest.config.ts` `include: test/**/*.test.ts`.
- No browser/e2e (no UI surface).
