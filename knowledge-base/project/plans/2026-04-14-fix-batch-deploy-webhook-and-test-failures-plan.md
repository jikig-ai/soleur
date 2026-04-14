# Fix: Batch — deploy webhook flake + web-platform test failures (#2185, #2145, #2131)

> Batch deliverable. Three related-but-distinct fixes shipped as one PR to keep main green and compress the deploy/verify cycle. Grouped by file proximity (all in `apps/web-platform/`) and because all three shape the "is the web-platform suite trustworthy" signal. Each bug gets its own commit within the branch so they remain independently revertable.

## Enhancement Summary

**Deepened on:** 2026-04-14
**Sections enhanced:** all three Parts, plus Alternatives and Domain Review
**Research inputs:** existing learnings (`2026-03-20-ci-deploy-reliability-and-mock-trace-testing`, `2026-03-21-async-webhook-deploy-cloudflare-timeout`, `2026-04-02-docker-image-accumulation-disk-full-deploy-failure`, `2026-04-13-vitest-mock-sharing-and-issue-batching`), `apps/web-platform/infra/server.tf` and `ci-deploy.test.sh`, adnanh/webhook docs (Hook-Definition.md), vitest `vi.doMock` + dynamic-import guidance.

### Key improvements discovered during deepening

1. **Terraform provisioning MUST extend the existing `terraform_data "deploy_pipeline_fix"` resource** — NOT add a new `terraform_data` block. Because `hcloud_server.web` has `lifecycle { ignore_changes = [user_data, ...] }` (server.tf:34–36), cloud-init changes do NOT re-apply to the existing server. The `deploy_pipeline_fix` resource's `triggers_replace` hash must include `cat-deploy-state.sh` AND the updated `hooks.json` content, and its remote-exec must write the new `hooks.json` file + restart webhook. If we skip this, the new hook is never created on the live server.
2. **`hooks.json` lives inside `cloud-init.yml` as a write_files block** (cloud-init.yml:96–128). Because cloud-init does not re-run on existing servers, the `deploy_pipeline_fix` remote-exec must write `/etc/webhook/hooks.json` directly with the new two-hook content AND `systemctl restart webhook`. Duplicating the JSON inside a Terraform heredoc is error-prone; recommended pattern: ship `hooks.json` as a standalone file in `apps/web-platform/infra/hooks.json`, then `cloud-init.yml` reads `${hooks_json_b64}` and `server.tf` provisions the file on change.
3. **Use `vi.doMock` + `await import()`** for #2145 — the existing passing tests in the file already use exactly this pattern (lines 96–115). `vi.doMock` is NOT hoisted (unlike `vi.mock`) and only mocks subsequent dynamic imports; the test at lines 30–43 already imports `provisionWorkspaceWithRepo` via `await import(...)` after `vi.doMock(...)`, so we just mirror that pattern.
4. **adnanh/webhook behavior confirmed (Hook-Definition docs):** with `include-command-output-in-response: false`, webhook returns `success-http-response-code` immediately on `exec.Cmd.Start()` — the HTTP response is independent of the script's exit code. This directly confirms #2185 root cause class. No way to change this behavior without a patched webhook binary, so client-side status polling is the right architecture.
5. **Existing `ci-deploy.test.sh` infrastructure is rich.** Mock scaffolding (`create_base_mocks`), run harnesses (`run_deploy`, `run_deploy_traced`), assertion helpers (`assert_exit`, `assert_exit_contains`), env-var-driven failure injection (`MOCK_DOCKER_PULL_FAIL`, `MOCK_DOCKER_RUN_FAIL_CANARY`, `MOCK_CURL_CANARY_FAIL`, `MOCK_DF_LOW`) already exist. The new `write_state` tests should extend this pattern, not rebuild it — add a `MOCK_FLOCK_CONTENDED=1` variant of `flock` mock for lock-contention coverage.
6. **`logger` is mocked in tests** (ci-deploy.test.sh:20–24) so `write_state` calls to `logger -t` work fine in CI test harness. `mktemp`, `mv`, `date`, `printf` are real — no extra mocking needed for state-file writes.
7. **`/var/lock` is already in `ReadWritePaths`** of webhook.service (cloud-init.yml:150 and webhook.service:17) so the state file location needs no systemd changes. Confirmed before relying on it.
8. **Concurrency group** `deploy-web-platform` (web-platform-release.yml:66–68) with `cancel-in-progress: false` serializes CI-side. Per `2026-03-20-ci-deploy-reliability-and-mock-trace-testing`, this was intentional — it prevents two workflows calling the webhook simultaneously. But it does not prevent a *prior* ci-deploy.sh from still running on the server when the NEXT job fires the webhook. The server-side `flock` lock is the second line of defense; this plan makes its failures visible.

### New considerations surfaced

- **State file race with concurrent readers.** If CI polls `/hooks/deploy-status` while ci-deploy.sh is mid-write via `mv tmp state`, readers either see the old file (pre-rename) or the new file (post-rename) — never a torn write, because `mv` within a filesystem is atomic. Good.
- **Tag selector consideration.** CI's status loop matches on `.tag == "v$VERSION"`. If an operator manually triggers a deploy between steps, the state file tag might belong to that manual deploy. Mitigation: CI loops until its specific `VERSION` tag appears OR fails after 120s. Acceptable — manual intervention during a CI deploy is already a coordination bug.
- **`-2 no_prior_deploy` on a reprovisioned server.** After a server recreate/rebuild, the state file is missing. First deploy through the new status step will get `-2` briefly before the first successful ci-deploy.sh writes state. That is handled (`-2 → continue polling`). No special case needed beyond the existing `-2` branch.
- **State file secrets hygiene.** Ensure `write_state` never interpolates env vars from `resolve_env_file` or Doppler output into the JSON. Only `COMPONENT`, `IMAGE`, `TAG`, `reason`, and timestamps — all public/non-sensitive values. Keep printf arguments positional; no `$(cat ...)` substitution.
- **Secondary failure during `write_state`.** If `mv` itself fails (disk full, /var/lock inode exhaustion), `write_state` exits non-zero and the outer `trap` fires. Add `set +e` around `write_state` calls or make the function always return 0 (trailing `:` or `|| true`). Without this, a disk-full scenario could turn a `insufficient_disk_space` reason into an `unhandled` trap. Small but worth handling — the `write_state` helper should end with `|| true`.

## Issues in scope

| # | Priority | Area | Closes |
|---|----------|------|--------|
| #2185 | bug + infra (no priority label) | `apps/web-platform/infra/` deploy pipeline | `Closes #2185` |
| #2145 | P3 low | `apps/web-platform/test/workspace-error-handling.test.ts` | `Closes #2145` |
| #2131 | P2 medium | 6 files under `apps/web-platform/test/` | `Closes #2131` |

## Sequencing

Do them in this order within the branch, each as its own commit:

1. **#2131** (6 pre-existing failing test files) — largest investigative surface, fix first so we know what "green suite" looks like before touching other tests.
2. **#2145** (workspace-error-handling git-clone timeout) — narrow fix; the green baseline from #2131 makes it trivial to verify no regression.
3. **#2185** (deploy webhook flake) — infrastructure change; independent of test work but benefits from a green suite to confirm the release path still works end-to-end.

Commit message pattern: `fix(<area>): <description> (#<number>)`.

---

## Part 1 — #2131: 6 pre-existing web-platform test failures (P2)

### Problem

Six test files in `apps/web-platform/test/` fail on `main`. They have been failing for multiple PRs, masking regressions in every new PR.

### Failing files (from issue body)

- `test/abort-all-sessions.test.ts`
- `test/agent-runner-cost.test.ts`
- `test/agent-runner-tools.test.ts`
- `test/canusertool-tiered-gating.test.ts`
- `test/session-resume-fallback.test.ts`
- `test/ws-deferred-creation.test.ts`

### Known context

`knowledge-base/project/learnings/2026-04-13-vitest-mock-sharing-and-issue-batching.md` is directly relevant: the agent-runner tests (`agent-runner-cost.test.ts`, `agent-runner-tools.test.ts`) already share helpers at `apps/web-platform/test/helpers/agent-runner-mocks.ts`. Failures in those two files are most likely mock-shape drift against `apps/web-platform/server/agent-runner.ts`.

The other four have their own mock graphs — no shared helper. Failures are likely Supabase query-builder chain drift (`.select().eq().eq().single()` vs current code), `ws-handler` signature changes, or `agent-runner` export renames.

### Investigation approach (per file)

Run **from `apps/web-platform/`** (vitest lives at `apps/web-platform/node_modules/vitest`, not root):

```bash
cd apps/web-platform && npm run test:ci -- test/abort-all-sessions.test.ts 2>&1 | tail -100
```

Repeat for each failing file. For each, classify:

- **Mock drift** — production code's dependency shape changed; test mock chain no longer matches. Fix: update mock chain to match current code.
- **API drift** — function signature or export name changed. Fix: import/call the current name.
- **Assertion drift** — expected value no longer matches current (correct) behavior. Fix: update expected value to the true current value. If production behavior is wrong, file a separate issue — do not weaken the assertion to hide a real bug.
- **Timing drift** — async race or missed `await`. Fix: add explicit awaits / `vi.waitFor`.

**Constraint.** Do not delete or `.skip` any test to make green. If a test exercises behavior that no longer exists, delete the whole test with a commit-body note explaining *why the behavior no longer exists*, cross-linking the PR/issue that removed it. If uncertain, leave failing and file a new tracking issue.

### Files likely to change

- `apps/web-platform/test/abort-all-sessions.test.ts`
- `apps/web-platform/test/agent-runner-cost.test.ts`
- `apps/web-platform/test/agent-runner-tools.test.ts`
- `apps/web-platform/test/canusertool-tiered-gating.test.ts`
- `apps/web-platform/test/session-resume-fallback.test.ts`
- `apps/web-platform/test/ws-deferred-creation.test.ts`
- `apps/web-platform/test/helpers/agent-runner-mocks.ts` — extend if shape changed

### Acceptance criteria

- [x] All 6 files pass: `cd apps/web-platform && npm run test:ci -- test/abort-all-sessions.test.ts test/agent-runner-cost.test.ts test/agent-runner-tools.test.ts test/canusertool-tiered-gating.test.ts test/session-resume-fallback.test.ts test/ws-deferred-creation.test.ts`
- [x] No test deleted or `.skip`'d without an explanatory note in the commit body
- [x] Each classification documented in the commit body

---

## Part 2 — #2145: `workspace-error-handling.test.ts` git clone timeout (P3)

### Problem

The `wraps git clone failure with stderr output` test in `apps/web-platform/test/workspace-error-handling.test.ts` (lines 45 to 58) times out at 5000 ms intermittently. The test calls `provisionWorkspaceWithRepo` against a nonexistent GitHub repo and asserts the error wrapping works (the expected rejection message matches `/Git clone failed/`).

### Root cause

`provisionWorkspaceWithRepo` in `apps/web-platform/server/workspace.ts` (lines 160 to 170) shells out to real `git clone` with a 120 000 ms timeout via `execFileSync`. The test does not stub that spawn. It relies on git failing fast when GitHub returns 404 for the nonexistent repo. Normally that finishes in under a second; on a slow network or DNS hiccup it exceeds 5 s and vitest kills the test.

The two other tests in the same file (the `cleans up credential helper even when clone fails` test, and the token-generation failure test at lines 30 to 43) already handle this correctly: they stub `execFileSync` via `vi.doMock("child_process", ...)`. Two more sentinel-file tests (lines 96 to 115 and 126 to 155) do the same. This one test is the odd one out.

### Fix

Stub `execFileSync` in the failing test via `vi.doMock("child_process", ...)` so it throws synchronously with a realistic `stderr` buffer, matching the pattern already used in `provisionWorkspaceWithRepo sentinel file` tests. The test becomes deterministic, fast (under 100 ms), and network-independent.

Pseudocode structure (abbreviated — full file will follow the pattern of lines 96 to 115):

```text
test("wraps git clone failure with stderr output", async () => {
  vi.doMock("../server/github-app", () => ({
    generateInstallationToken returns "ghs_faketoken123",
    randomCredentialPath returns a random /tmp path,
  }));

  vi.doMock("child_process", async () => {
    // Preserve actual module surface; override the sync spawner to throw.
    // Return an Error whose .stderr buffer contains:
    //   "fatal: repository 'https://github.com/nonexistent/fake-repo-xxx/' not found\n"
    // This matches what git actually prints, so the production error-wrapping
    // code path (workspace.ts:172) reads .stderr via (err as {stderr?: Buffer})?.stderr?.toString()
    // and produces the "Git clone failed: ..." message the test asserts.
  });

  const { provisionWorkspaceWithRepo } = await import("../server/workspace");
  const userId = randomUUID();

  await expect(
    provisionWorkspaceWithRepo(userId, "https://github.com/nonexistent/fake-repo-xxx", 12345),
  ).rejects.toThrow(/Git clone failed/);
});
```

The stubbed spawner only throws for git-clone invocations; later git config calls (user.name, user.email at workspace.ts:191 and 201) are unreached because the clone failure rejects the promise first.

### Why this is the right fix (not a timeout bump)

Bumping the vitest timeout to 30 s "fixes" the flake but makes every future regression where code hangs forever take 30 s to surface. And the test is not testing git — it is testing the error-wrapping behavior of `provisionWorkspaceWithRepo`. That behavior is fully covered by a stubbed spawner that throws with a realistic stderr shape; the production code at workspace.ts:172 just reads `.stderr?.toString()` and wraps the resulting string. Same input, same output.

### Files to change

- `apps/web-platform/test/workspace-error-handling.test.ts` — add the `child_process` stub to the `wraps git clone failure with stderr output` test

### Research insights (Part 2)

**vitest mock hoisting (from vitest.dev docs):**

- `vi.mock(...)` is hoisted; factory cannot reference test-local variables.
- `vi.doMock(...)` is NOT hoisted; can reference test-local variables, but only affects *subsequent dynamic imports*.
- The passing tests in `workspace-error-handling.test.ts` at lines 96–115 and 126–155 already use `vi.doMock("child_process", async () => ...)` followed by `await import("../server/workspace")` — that is exactly the pattern the failing test needs to adopt.
- Why this works: `vi.doMock` registers the mock; the dynamic `await import()` runs after registration, so the imported module resolves `child_process` through the mock.

**Edge cases worth covering (confirmed by reading existing file):**

- `vi.resetModules()` runs in `beforeEach` (line 18) — ensures each test gets fresh module graph. Good; no extra cleanup needed for the new mock.
- `vi.restoreAllMocks()` runs in `afterEach` (line 22) — also handles the new mock.
- The existing cleanup at lines 23–26 (`rmSync(TEST_WORKSPACES, ...)`) covers the case where clone creates a partial dir; the new stubbed spawner never creates the dir, so the cleanup is a no-op — harmless.

**What NOT to change:**

- Do NOT remove the `try { rmSync(...) } catch {}` in afterEach. Other tests in the file rely on it.
- Do NOT switch to `vi.mock` for this test — vi.mock would affect *all* tests in the file since it's file-scoped hoisted, breaking the 4 tests that want a different mock shape.

### Acceptance criteria

- [x] Test passes 10 consecutive runs: `cd apps/web-platform && for i in $(seq 1 10); do npm run test:ci -- test/workspace-error-handling.test.ts || break; done`
- [x] Test completes in under 500 ms (was timing out at 5000 ms)
- [x] Other tests in the file still pass unchanged
- [x] Test still asserts `/Git clone failed/` — behavior under test unchanged
- [x] The stubbed `execFileSync` returns an error whose `.stderr` is a `Buffer` (not a string) — matches the real shape and flows through `workspace.ts:172` correctly

---

## Part 3 — #2185: web-platform deploy webhook flake (same class as #1405)

### Problem

Release run `24401297396` (2026-04-14 13:20:37 UTC, PR #2181, v0.35.8):

- Deploy webhook returned HTTP 202
- Verify step polled `/health` for 300 s
- Uptime climbed from 951 s to 1255 s across 30 polls (+304 s) — container was **never restarted**
- Re-running the same deploy job immediately succeeded, with no code changes

### Why this is NOT a recurrence of #1405 root cause

#1405 was root-caused to disk exhaustion. Fix (PR #1406, committed): `docker image prune -af` plus a 5 GB pre-flight check in `ci-deploy.sh` (lines 113 to 118 and 123 to 124). Post-fix, disk exhaustion produces `exit 1` at the pre-flight guard — *not* a silent no-op. See `knowledge-base/project/learnings/integration-issues/2026-04-02-docker-image-accumulation-disk-full-deploy-failure.md`.

#2185 is the **same symptom class** (webhook 202 + no restart + re-run fixes it) with a **different underlying trigger**. This plan fixes the *symptom class* by making all silent ci-deploy.sh failures visible to CI — regardless of which specific trigger fires next time.

### Root cause (hypothesis)

The webhook is fire-and-forget async:

```jsonc
// apps/web-platform/infra/cloud-init.yml (lines 96 to 126)
{
  "id": "deploy",
  "execute-command": "/usr/local/bin/ci-deploy.sh",
  "include-command-output-in-response": false,
  "success-http-response-code": 202,
  ...
}
```

`adnanh/webhook` returns HTTP 202 immediately after validating the HMAC and starting `ci-deploy.sh` in the background. The 202 tells the CI caller **nothing** about whether the script ran to completion.

`ci-deploy.sh` acquires a `flock -n` lock (lines 108 to 110):

```bash
LOCK_FILE="${CI_DEPLOY_LOCK:-/var/lock/ci-deploy.lock}"
exec 200>"$LOCK_FILE"
flock -n 200 || { logger -t "$LOG_TAG" "REJECTED: another deploy in progress"; echo "Error: another deploy in progress" >&2; exit 1; }
```

Release timing on 2026-04-14:

- 13:02:44 UTC — release 24400449012 (succeeded)
- 13:20:37 UTC — release 24401297396 (**failed, this ticket**)

18 minutes is long for a healthy deploy, but plausible scenarios that silently consume the webhook ACK:

1. **Prior ci-deploy.sh stalled, still holding flock.** `docker pull` or `docker exec … bwrap` hangs, lock stays held, second invocation gets "another deploy in progress" and `exit 1`. Webhook already returned 202.
2. **Doppler transient failure** inside `resolve_env_file` (ci-deploy.sh:17 to 49). `exit 1`, no deploy, 202 already returned.
3. **Script start failed after webhook spawn.** `adnanh/webhook` in `-verbose` mode starts `ci-deploy.sh` and returns 202 based on a successful `Start()` in Go. If the process then dies (env file missing, permission denied), the 202 is already on the wire.
4. **Canary rollback exits 1** (ci-deploy.sh:163 to 211). The script correctly exits 1, but the webhook does not know.

The diagnosis cannot be confirmed from CI logs alone. The failed script's stderr went to journalctl on the server because `include-command-output-in-response` is false. Actual root cause must be read from `journalctl -u webhook` plus `logger -t ci-deploy` around 13:24:37 UTC on the server.

Per AGENTS.md, SSH is for infra provisioning only, not observability. Sentry does not instrument bash. Better Stack does not tail journalctl. **The lack of CI-visible state for ci-deploy.sh is itself the bug class** — that is what this plan fixes.

### Fix strategy (two layers)

**Layer 1 — synchronous status check.** Add a second webhook endpoint `/hooks/deploy-status` that returns the last `ci-deploy.sh` run's structured status (start_ts, end_ts, exit_code, component, image, tag, reason). CI polls `/hooks/deploy-status` after `/hooks/deploy` returns 202 to distinguish "accepted and still running" from "accepted but failed immediately" from "lock conflict". This matches the issue body: *"Consider adding a webhook response that indicates actual execution status (not just 'accepted')"*.

**Layer 2 — persist run state.** `ci-deploy.sh` writes JSON state at start and end to `/var/lock/ci-deploy.state` atomically via temp file + `mv`. The status endpoint just `cat`s that file.

### Concrete design

#### `ci-deploy.sh` changes

Add state-writing helpers and call them at each exit path:

```bash
# Added near top, before existing flock block
STATE_FILE="${CI_DEPLOY_STATE:-/var/lock/ci-deploy.state}"
START_TS=$(date +%s)

# write_state always returns 0 so a failure in state-writing (e.g. disk-full) does not
# convert an explicit failure reason into an "unhandled" trap on re-entry. Log to syslog
# if mktemp/mv themselves fail so the failure is still visible via journalctl.
write_state() {
  local exit_code="$1"
  local reason="${2:-}"
  local tmp
  tmp=$(mktemp "${STATE_FILE}.XXXXXX" 2>/dev/null) || {
    logger -t "$LOG_TAG" "write_state: mktemp failed for STATE_FILE=$STATE_FILE"
    return 0
  }
  printf '{"start_ts":%d,"end_ts":%d,"exit_code":%d,"component":"%s","image":"%s","tag":"%s","reason":"%s"}\n' \
    "$START_TS" "$(date +%s)" "$exit_code" "${COMPONENT:-}" "${IMAGE:-}" "${TAG:-}" "$reason" > "$tmp" 2>/dev/null || {
    logger -t "$LOG_TAG" "write_state: printf/redirect failed"
    rm -f "$tmp"
    return 0
  }
  mv "$tmp" "$STATE_FILE" 2>/dev/null || {
    logger -t "$LOG_TAG" "write_state: mv failed"
    rm -f "$tmp"
    return 0
  }
  return 0
}

# Initial write: "running"
write_state -1 "running"

# Trap captures any non-zero exit that did not call write_state explicitly.
# Use a sentinel file to check whether an explicit write_state already ran for this exit.
trap 'rc=$?; [ "$rc" -ne 0 ] && [ ! -f "${STATE_FILE}.final" ] && write_state "$rc" "unhandled"; rm -f "${STATE_FILE}.final"' EXIT

# When an explicit write_state fires at a known failure point, touch the sentinel so
# the EXIT trap does not overwrite with "unhandled". Example wrapper:
#
#   final_write_state() { write_state "$1" "$2"; touch "${STATE_FILE}.final"; }
#
# Use final_write_state at each explicit failure exit, write_state only for "running".
```

**Why the sentinel:** without it, the EXIT trap fires AFTER an explicit `write_state 1 "doppler_fetch_failed"` + `exit 1`, and overwrites the state file with `reason: "unhandled"`. The sentinel lets the trap know the failure was already reported.

Wire explicit reasons at each failure exit (keep existing `logger -t` and stderr lines, add `write_state`):

| Exit location | reason |
|---|---|
| Missing Doppler CLI (ci-deploy.sh:21) | `doppler_unavailable` |
| Missing DOPPLER_TOKEN (ci-deploy.sh:27) | `doppler_token_missing` |
| Doppler secrets download fail (ci-deploy.sh:40) | `doppler_fetch_failed` |
| Empty SSH_ORIGINAL_COMMAND (ci-deploy.sh:60) | `command_missing` |
| Wrong field count (ci-deploy.sh:67) | `command_malformed` |
| Unknown action (ci-deploy.sh:78) | `action_unknown` |
| Unknown component (ci-deploy.sh:85) | `component_unknown` |
| Wrong image (ci-deploy.sh:92) | `image_mismatch` |
| Bad tag format (ci-deploy.sh:99) | `tag_malformed` |
| `flock` contention (ci-deploy.sh:110) | `lock_contention` |
| Disk pre-flight (ci-deploy.sh:116) | `insufficient_disk_space` |
| Canary sandbox fail (ci-deploy.sh:167 to 172) | `canary_sandbox_failed` |
| Production container start fail (ci-deploy.sh:198 to 202) | `production_start_failed` |
| Canary health fail (ci-deploy.sh:204 to 211) | `canary_failed` |
| No handler for component (ci-deploy.sh:215 to 217) | `no_handler` |
| Successful deploy (ci-deploy.sh:196) | `ok` (with `exit_code=0`) |

Important details:

- For the `flock` failure path, keep the lock file (`/var/lock/ci-deploy.lock`) and the state file (`/var/lock/ci-deploy.state`) as **separate files**. The second invocation cannot acquire the lock but can still write state — that is correct behavior; the "winner" will overwrite it when it finishes.
- `mv tmp STATE_FILE` is atomic within a filesystem. Safe under concurrent writers; last writer wins. That is fine because CI polls for its own `tag` match — stale state for a different tag fails the `tag == $VERSION` check.

#### New script — `apps/web-platform/infra/cat-deploy-state.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

STATE_FILE="${CI_DEPLOY_STATE:-/var/lock/ci-deploy.state}"
if [[ ! -f "$STATE_FILE" ]]; then
  echo '{"exit_code":-2,"reason":"no_prior_deploy"}'
else
  cat "$STATE_FILE"
fi
```

10 lines. Reads once, prints JSON, exits. No side effects.

#### `cloud-init.yml` changes

1. **Add a write_files entry** for `cat-deploy-state.sh`, mirroring the `ci-deploy.sh` block at lines 83 to 89. Use `encoding: b64` with `${cat_deploy_state_script_b64}` from Terraform.
2. **Add a second hook** in `/etc/webhook/hooks.json` at lines 96 to 126:

```jsonc
[
  { "id": "deploy", "execute-command": "/usr/local/bin/ci-deploy.sh", /* ... existing ... */ },
  {
    "id": "deploy-status",
    "execute-command": "/usr/local/bin/cat-deploy-state.sh",
    "command-working-directory": "/",
    "include-command-output-in-response": true,
    "http-methods": ["POST"],
    "trigger-rule-mismatch-http-response-code": 403,
    "trigger-rule": {
      "match": {
        "type": "payload-hmac-sha256",
        "secret": "${webhook_deploy_secret}",
        "parameter": { "source": "header", "name": "X-Signature-256" }
      }
    }
  }
]
```

HMAC-signed POST (same scheme as `/hooks/deploy`) keeps the secret model identical. No new secret, no new authentication surface. `include-command-output-in-response: true` so CI reads the state JSON in the response body.

3. **webhook.service** (lines 130 to 152) already has `ReadWritePaths=/mnt/data /var/lock` — the state file lives in `/var/lock`, so no change needed to the unit file.

#### Terraform changes (updated after deepen-plan review)

**Critical finding from `server.tf` read:** `hcloud_server.web` has `lifecycle { ignore_changes = [user_data, ssh_keys, image] }` at lines 34–36. This means **cloud-init changes do NOT re-apply to the existing production server**. Any new file introduced via `write_files:` in `cloud-init.yml` reaches only freshly-provisioned servers.

The existing solution for this problem is `terraform_data "deploy_pipeline_fix"` at `server.tf:86–126`, which pushes `ci-deploy.sh` + `webhook.service` to the live server and restarts webhook via `provisioner "remote-exec"`. Its `triggers_replace` hash is `sha256(join(",", [file("ci-deploy.sh"), file("webhook.service")]))`.

**Approach:** Extend `deploy_pipeline_fix` rather than create a parallel resource. This keeps a single restart path for webhook-related config.

Concrete changes to `apps/web-platform/infra/server.tf`:

1. **Extract `hooks.json` to its own file** at `apps/web-platform/infra/hooks.json`. Today it lives inline in `cloud-init.yml` (lines 96–126). Extract so Terraform can file-provision it and so the hash trigger can detect changes.
2. **Update `cloud-init.yml`** to read the file via template interpolation: `${hooks_json_b64}` — add `hooks_json_b64 = base64encode(file("${path.module}/hooks.json"))` to the `templatefile(...)` inputs at `server.tf:20–28`, and change the `hooks.json` write_files block to `encoding: b64` + `content: ${hooks_json_b64}`. Cloud-init will template-substitute the secret `${webhook_deploy_secret}` at provision time; since we're moving the JSON out of cloud-init, the secret must be substituted some other way — specifically, the secret lives in the `hooks.json` source file as a placeholder `__WEBHOOK_DEPLOY_SECRET__` and the remote-exec provisioner uses `sed` to substitute it from `/etc/default/webhook-deploy` on the server. Alternative: keep the JSON template interpolation in Terraform using `templatefile` instead of reading the raw file. The latter is cleaner:

   ```hcl
   hooks_json_b64 = base64encode(templatefile("${path.module}/hooks.json.tmpl", {
     webhook_deploy_secret = var.webhook_deploy_secret
   }))
   ```

   Then `hooks.json.tmpl` contains literal `"secret": "${webhook_deploy_secret}"` that Terraform renders. The rendered JSON goes into `cloud-init.yml` for fresh provisions and into a file provisioner for existing servers.

3. **Extend `deploy_pipeline_fix`** (server.tf:86–126):
   - `triggers_replace` hash: add `file("${path.module}/cat-deploy-state.sh")` and the rendered hooks.json to the join:

     ```hcl
     triggers_replace = sha256(join(",", [
       file("${path.module}/ci-deploy.sh"),
       file("${path.module}/webhook.service"),
       file("${path.module}/cat-deploy-state.sh"),
       templatefile("${path.module}/hooks.json.tmpl", {
         webhook_deploy_secret = var.webhook_deploy_secret
       }),
     ]))
     ```

   - Add a `provisioner "file"` for `cat-deploy-state.sh` → `/usr/local/bin/cat-deploy-state.sh`.
   - Add a `provisioner "file"` for the rendered hooks.json → `/etc/webhook/hooks.json`.
     - If using `templatefile`, first render to a local temp file via `local_file` resource, then provision. Alternative: use `remote-exec` with a heredoc — but AGENTS.md warns against left-aligned heredocs in CI YAML; here it's Terraform HCL, so less risky, but still prefer the file approach.
   - Extend the existing `remote-exec` block:

     ```hcl
     inline = [
       "chmod +x /usr/local/bin/ci-deploy.sh",
       "chmod +x /usr/local/bin/cat-deploy-state.sh",
       "chown root:deploy /etc/webhook/hooks.json",
       "chmod 640 /etc/webhook/hooks.json",
       # ... existing idempotent DOPPLER_CONFIG_DIR append ...
       "systemctl daemon-reload",
       "systemctl restart webhook",
       # ... existing stale .env cleanup ...
     ]
     ```

   - Note: `webhook.service`'s `ReadOnlyPaths=/etc/webhook` (line 151 of cloud-init.yml and line 18 of webhook.service) means the webhook process CANNOT write to `/etc/webhook`, but the chown/chmod are done outside the systemd context by the `remote-exec` running as root. Good.

4. **NO new `terraform_data` resource.** The existing one already has SSH connection, triggers on hash, and webhook restart. Keep one restart path.

R2 backend is already configured per AGENTS.md — no change.

**Verification after Terraform apply:**

```bash
# From local workstation (requires Cloudflare service token in Doppler)
curl -sf -X POST \
  -H "X-Signature-256: sha256=$(printf '{}' | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //')" \
  -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" \
  -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
  -d '{}' \
  https://deploy.soleur.ai/hooks/deploy-status
# Expected first-call response (before any deploy): {"exit_code":-2,"reason":"no_prior_deploy"}
```

#### `.github/workflows/web-platform-release.yml` changes

Insert a new step between `Deploy via webhook` (lines 70 to 92) and `Verify deploy health and version` (lines 94 to 127):

```yaml
- name: Verify deploy script completion
  env:
    WEBHOOK_SECRET: ${{ secrets.WEBHOOK_DEPLOY_SECRET }}
    CF_ACCESS_CLIENT_ID: ${{ secrets.CF_ACCESS_CLIENT_ID }}
    CF_ACCESS_CLIENT_SECRET: ${{ secrets.CF_ACCESS_CLIENT_SECRET }}
    VERSION: ${{ needs.release.outputs.version }}
  run: |
    PAYLOAD='{"query":"status"}'
    SIGNATURE=$(printf '%s' "$PAYLOAD" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //')
    for i in $(seq 1 24); do
      BODY=$(curl -sf --max-time 10 \
        -X POST \
        -H "Content-Type: application/json" \
        -H "X-Signature-256: sha256=$SIGNATURE" \
        -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" \
        -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
        -d "$PAYLOAD" \
        "https://deploy.soleur.ai/hooks/deploy-status" || echo "")
      if [ -z "$BODY" ]; then
        echo "Attempt $i/24: status endpoint unreachable"
        sleep 5
        continue
      fi
      EXIT_CODE=$(echo "$BODY" | jq -r '.exit_code // -99')
      REASON=$(echo "$BODY" | jq -r '.reason // "unknown"')
      TAG=$(echo "$BODY" | jq -r '.tag // ""')
      case "$EXIT_CODE" in
        0)
          if [ "$TAG" = "v$VERSION" ]; then
            echo "ci-deploy.sh completed successfully for v$VERSION"
            exit 0
          fi
          echo "Attempt $i/24: last deploy was for $TAG (want v$VERSION)"
          ;;
        -1)
          echo "Attempt $i/24: ci-deploy.sh still running (reason=$REASON)"
          ;;
        -2)
          echo "Attempt $i/24: no prior deploy recorded"
          ;;
        *)
          echo "::error::ci-deploy.sh exited $EXIT_CODE (reason=$REASON, tag=$TAG)"
          echo "$BODY" | jq .
          exit 1
          ;;
      esac
      sleep 5
    done
    echo "::error::ci-deploy.sh did not report completion for v$VERSION within 120s"
    exit 1
```

YAML-indentation check (per AGENTS.md hard rule on heredocs): this step uses no heredocs and no multi-line CLI args that drop below the block's base indent. All shell is inside the `run: |` block at consistent indent.

The existing `Verify deploy health and version` step (lines 94 to 127) stays in place as a backstop — it verifies the **container** is actually healthy post-swap. The new step catches the "ci-deploy.sh exited 1 silently" class that is invisible to `/health`.

### Flow after fix

1. CI POSTs to `/hooks/deploy` → 202 "initiated"
2. CI loops on `/hooks/deploy-status` (up to 120 s):
   - `exit_code: -1, reason: running` → continue
   - `exit_code: 0, tag: v$VERSION` → done, proceed to health check
   - `exit_code: >=1` → fail fast with `::error::` annotation and the reason
   - `exit_code: -2` → state file missing, server never ran ci-deploy.sh at all; keep polling a few times then fail
3. If script completion confirmed, proceed to existing `/health` check (300 s of container health verification)
4. If script completion never confirmed in 120 s → fail with timeout

### Observability-first rationale (explicit)

Per AGENTS.md: "For production debugging, use observability tools — never SSH for logs." SSH is for infra provisioning only (Terraform). This fix creates a CI-visible observability channel for `ci-deploy.sh` that did not exist before — bringing bash deploy scripts up to the same standard as application-level Sentry and `/health` instrumentation.

### Files to change

- `apps/web-platform/infra/ci-deploy.sh` — add `write_state`, wire at each exit
- `apps/web-platform/infra/ci-deploy.test.sh` — add mock-trace tests for each `write_state` path, using the `$(export MOCK_X=1; run_deploy ...)` pattern documented in `knowledge-base/project/learnings/2026-03-20-ci-deploy-reliability-and-mock-trace-testing.md`. Concrete additions:
  - New helper: `assert_state_contains <description> <expected_reason> <expected_exit_code> [<cmd>]` — runs the deploy then `jq -r '.reason' "$STATE_FILE"` and `jq -r '.exit_code'` to validate.
  - Extend `create_base_mocks` with a configurable `flock` mock: when `MOCK_FLOCK_CONTENDED=1` is set, exit 1 (lock contended) instead of 0.
  - New test cases:
    - Happy path → `reason: "ok"`, `exit_code: 0`
    - `MOCK_DF_LOW=1` → `reason: "insufficient_disk_space"`, `exit_code: 1`
    - `MOCK_FLOCK_CONTENDED=1` → `reason: "lock_contention"`, `exit_code: 1`
    - `MOCK_DOCKER_PULL_FAIL=1` → `reason: "unhandled"` (or a more specific one if we add a handler around `docker pull`), `exit_code: 1`
    - `MOCK_DOCKER_RUN_FAIL_CANARY=1` → `reason: "canary_sandbox_failed"` (if health probe also fails) or `reason: "unhandled"`, `exit_code: 1`
    - `MOCK_CURL_CANARY_FAIL=1` → `reason: "canary_failed"`, `exit_code: 1`
  - Add a `reset_state()` helper that `rm -f "$STATE_FILE"` between tests — otherwise cross-test state leakage could mask bugs.
- `apps/web-platform/infra/cat-deploy-state.sh` — new (10 lines)
- `apps/web-platform/infra/cloud-init.yml` — add write_files entry for `cat-deploy-state.sh`, add second hook in `/etc/webhook/hooks.json`
- `apps/web-platform/infra/server.tf` (and/or `main.tf`) — add `base64encode(file(...))` local and the remote-exec block for `cat-deploy-state.sh`, mirroring the `disk-monitor.sh` pattern at `server.tf:23,43-68`
- `.github/workflows/web-platform-release.yml` — insert `Verify deploy script completion` step between existing `Deploy via webhook` and `Verify deploy health and version`

### Out of scope (explicit)

- **Root-causing the specific 2026-04-14 13:24 UTC failure.** This plan adds a detector so the next occurrence surfaces with an exact reason. Actually rooting out *this* cause requires journalctl diagnosis on the server (infra diagnosis). Not a blocker for this PR. The next failure will be self-diagnosing.
- **Auto-kill of stalled ci-deploy.sh processes.** If the root cause is `docker exec bwrap` hanging, this plan makes the stall visible but does not auto-kill. Follow-up (see Deferrals below).
- **Automatic retry of failed deploys.** Current workflow requires manual re-run. Auto-retry for `lock_contention` is tempting but can mask real outages. Keep manual; the new `::error::` annotation tells operators exactly *why* to re-run.

### Deferrals (follow-up issues)

1. **Auto-kill stalled ci-deploy.sh** — add a wrapper systemd unit `ci-deploy@.service` with `TimeoutSec=600` so any invocation that exceeds 10 minutes is SIGTERM'd. File as a new GitHub issue milestoned to "Post-MVP / Later" with re-evaluation trigger: "any deploy that exceeds 10 minutes in production".
2. **Push deploy state to Better Stack.** Currently the state is only polled on-demand. A push model (Doppler-authenticated Better Stack source) would catch deploys that fail out-of-band (e.g., manual curl from the server). File as follow-up; not needed for #2185 resolution.

Both deferrals get issues filed **as part of this PR's shipping checklist** per AGENTS.md: "When deferring a capability, create a GitHub issue … milestoned to the target phase".

### Acceptance criteria

- [x] `ci-deploy.sh` writes a JSON state record at start (`exit_code=-1, reason="running"`) and at every exit path (success and failure) with a specific reason
- [x] `cat-deploy-state.sh` reads the state file and returns it as JSON (or `{"exit_code":-2,"reason":"no_prior_deploy"}` if absent)
- [x] New hook `/hooks/deploy-status` is HMAC-authenticated with the same secret as `/hooks/deploy`, returns the state JSON in the HTTP body
- [x] `apps/web-platform/infra/ci-deploy.test.sh` covers: success, `insufficient_disk_space`, `lock_contention`, `doppler_fetch_failed`, `canary_failed`, `canary_sandbox_failed`. All tests pass locally.
- [ ] Terraform apply after merge provisions `cat-deploy-state.sh` to the server, webhook service reloads, `/hooks/deploy-status` responds 200 to a signed request
- [x] New CI step `Verify deploy script completion` emits a `::error::` annotation with the `reason` field when `exit_code >= 1`, and fails the job before the 300 s `/health` poll
- [x] Existing health-verify step remains unchanged as a backstop
- [x] No secrets leaked: state JSON contains no credentials; HMAC signature still required on the status endpoint
- [ ] Two follow-up issues filed (auto-kill stalled deploys; push-to-Better-Stack)

### Post-merge verification

Per AGENTS.md "After a PR merges to main, verify all release/deploy workflows succeed":

- [ ] Web Platform Release workflow for this PR succeeds end-to-end
- [ ] Signed POST to `https://deploy.soleur.ai/hooks/deploy-status` returns the most recent deploy's state with `exit_code == 0`
- [ ] Next release after merge uses the new `Verify deploy script completion` step and passes

---

## Test Scenarios (cross-cutting)

| # | Scenario | Expected | Part |
|---|----------|----------|------|
| 1 | `cd apps/web-platform && npm run test:ci` — full suite | All tests green | #2131, #2145 |
| 2 | Loop `npm run test:ci -- test/workspace-error-handling.test.ts` 10x | All 10 green, each under 1 s | #2145 |
| 3 | `bash apps/web-platform/infra/ci-deploy.test.sh` | All scenarios pass; state file written for each path | #2185 |
| 4 | Local: `MOCK_DOCKER_PULL_FAIL=1 run_deploy …` → read `$STATE_FILE` | `exit_code >= 1` with specific reason | #2185 |
| 5 | Signed POST to `/hooks/deploy-status` before any deploy → `{"exit_code":-2,"reason":"no_prior_deploy"}` | graceful first-call | #2185 |
| 6 | Force an intentional canary health fail in a staging/dry-run → state reflects `canary_failed`, CI `::error::` annotation present | full loop works end-to-end | #2185 |

## Implementation sequence (TDD gate per AGENTS.md)

Each part has its own TDD gate:

- **#2131** — run failing test, classify, write expected assertion, make green. Each file independent.
- **#2145** — write the stub for the sync spawner first; confirm it fails with the *current* code (sanity: the stub actually loads), then confirm it passes fast. Verify `/Git clone failed/` still asserted.
- **#2185** — start with failing mock-trace test in `ci-deploy.test.sh` asserting the state file contains `"reason":"lock_contention"` on `flock` failure. Implement `write_state`. Repeat for each reason. Then wire `cat-deploy-state.sh`, hook, Terraform, CI step. The `ci-deploy.test.sh` pattern lets us land the bash logic without needing a staging server.

## Shipping

Use `/ship` with label `fix` (patch bump). PR body:

```
Batch fix:
- Closes #2131
- Closes #2145
- Closes #2185

Also files follow-up issues:
- Auto-kill stalled ci-deploy.sh (Post-MVP / Later)
- Push deploy state to Better Stack (Post-MVP / Later)
```

Use `Closes` (not `Ref`) because each part fully addresses its issue.

## Browser task automation check

Scanned for "manual", "browser", or "user must" tasks. None present. No browser interactions. Terraform apply runs in CI on merge via the existing release workflow — no manual step.

---

## Domain Review

**Domains relevant:** Engineering (CTO)

All three are pure engineering/infra concerns with no product, marketing, sales, legal, finance, or customer-support implications. Skipping the full eight-domain sweep because:

- #2131 and #2145 are internal test hygiene (no user-facing surface, no copy, no flow, no storage change)
- #2185 is release infrastructure (no user-facing surface, no copy, no flow, no storage change)
- No new pages or components; no new services signed up; no new spend; no new legal commitments; no new data processed
- No brainstorm exists for this work (straight bug-batch), so no specialist carry-forward to honor

**Brainstorm-recommended specialists:** none (no brainstorm)

### Product/UX Gate

**Tier:** none
**Decision:** skipped — no user-facing surface

Mechanical escalation check (per skill instructions): no new files under `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`. Confirmed NONE tier.

### Engineering (CTO)

**Status:** reviewed (inline during plan drafting)
**Assessment:** Plan follows established patterns in `apps/web-platform/infra/`:

- Mock-trace bash testing pattern already documented at `knowledge-base/project/learnings/2026-03-20-ci-deploy-reliability-and-mock-trace-testing.md`
- Terraform `base64encode(file())` injection pattern already in `server.tf:23` for `disk-monitor.sh`
- Async webhook pattern already in `cloud-init.yml` — we add a second hook with identical auth
- R2 remote backend already configured (AGENTS.md compliance)

No new dependencies, no new services, no new secrets. The fix is additive: preserves the existing deploy flow, adds one detection layer.

The observability gap this fixes (silent `ci-deploy.sh` failures invisible to CI) is real and recurring — second time in about 2 months after #1405. Investing in permanent observability is correct per AGENTS.md "observability-first".

Anticipated reviewer pushback:

1. *"Just SSH in and read journalctl"* — rejected by AGENTS.md. SSH is for infra only; observability must be CI-visible.
2. *"Just add Sentry to bash scripts"* — rejected. Sentry has no bash target; would require a sidecar. A 10-line state file is strictly simpler.
3. *"Bump `/health` polling to 600 s"* — does not help when `ci-deploy.sh` never runs (state never changes, just times out slower).
4. *"Make the webhook synchronous"* — rejected. Would require the HTTPS connection to stay open 2 to 5 minutes through Cloudflare tunnel; CI request times out at 30 s (`--max-time 30`). Async + status-poll is the right pattern for long server tasks.

---

## Alternative Approaches Considered

| Alternative | Why rejected |
|---|---|
| **One PR per issue (three PRs)** | Triples release/deploy overhead for three small `apps/web-platform/` fixes. Also triples the risk of hitting #2185 itself during the deploy cycle. Batching is the documented pattern (learning 2026-04-13-vitest-mock-sharing-and-issue-batching). |
| **Bump vitest timeout for #2145** | Masks network flake. Every future regression where code hangs forever now takes 30 s to surface. Stub is the correct fix; the test is not testing git. |
| **Synchronous webhook** for #2185 | HTTPS connection held 2 to 5 min through Cloudflare tunnel; CI `--max-time 30` timeout. Flaky on network hiccups. Async + status-poll is the standard for long-running server tasks. |
| **Sentry-based bash instrumentation** | Bash has no Sentry runtime. Would need a sidecar daemon to tail logs. 10-line state file is strictly simpler and more reliable. |
| **Skip #2131 until someone "gets to it"** | Directly violates AGENTS.md: pre-existing failures without tracking issues normalize a red suite. The tracking issue exists (#2131); closing it now is the right move. |
| **Delete the 6 failing tests** | Rejected by #2131 issue ("fix or update tests to pass on current main"). Tests exist for a reason; we fix the mocks, not delete coverage. |

No plan-level deferrals beyond the two CI/observability follow-ups already listed under Part 3.

---

## Research sources and references

**Project learnings consulted:**

- `knowledge-base/project/learnings/2026-03-20-ci-deploy-reliability-and-mock-trace-testing.md` — mock-trace pattern via stdout markers (avoids PATH corruption); `$(export MOCK_X=1; run_deploy ...)` convention for env propagation.
- `knowledge-base/project/learnings/2026-03-21-async-webhook-deploy-cloudflare-timeout.md` — why sync webhook does not work (Cloudflare 120 s edge timeout); confirms async-with-status-poll as the only viable pattern behind Cloudflare Tunnel on non-Enterprise plans.
- `knowledge-base/project/learnings/integration-issues/2026-04-02-docker-image-accumulation-disk-full-deploy-failure.md` — #1405 root cause (disk full); confirms #2185 is a different root cause with the same symptom class.
- `knowledge-base/project/learnings/2026-04-13-vitest-mock-sharing-and-issue-batching.md` — batching N issues into 1 PR by file proximity; shared-helper pattern for agent-runner tests.
- `knowledge-base/project/learnings/integration-issues/2026-04-05-shell-mock-testing-and-disk-monitoring-provisioning.md` (referenced; validates mock-trace + terraform_data remote-exec pattern used here).

**adnanh/webhook docs:**

- [Hook-Definition](https://github.com/adnanh/webhook/blob/master/docs/Hook-Definition.md) — confirms `include-command-output-in-response: false` causes the webhook binary to return the success code immediately on `Start()`, regardless of script exit code. Behavior is by design, not configurable without a patched binary.
- [Issue #220](https://github.com/adnanh/webhook/issues/220) — community discussion confirming: sync mode returns HTTP 500 on non-zero exit; async mode always returns the `success-http-response-code` regardless.
- [Issue #245](https://github.com/adnanh/webhook/issues/245) — "Run command in background"; standard pattern is async + separate status polling.

**vitest docs:**

- [Vitest `vi` API](https://vitest.dev/api/vi) — `vi.doMock()` is not hoisted; only affects subsequent dynamic imports. Use with `await import(...)` (pattern already present in `workspace-error-handling.test.ts`).
- [Vitest mocking guide](https://vitest.dev/guide/mocking) — Node.js built-in modules (`child_process`) are mockable via `vi.doMock` factory returning `{ ...actual, execFileSync: vi.fn(...) }`.

**In-repo code read:**

- `apps/web-platform/server/workspace.ts:120-230` — `provisionWorkspaceWithRepo` implementation and the exact `execFileSync` call that the test needs to stub.
- `apps/web-platform/test/workspace-error-handling.test.ts:96-115` — passing test that demonstrates the `vi.doMock("child_process", ...)` + `await import("../server/workspace")` pattern.
- `apps/web-platform/infra/ci-deploy.sh:1-220` — full script, exit-path inventory.
- `apps/web-platform/infra/ci-deploy.test.sh:1-250` — test harness scaffolding, mock conventions, assertion helpers.
- `apps/web-platform/infra/cloud-init.yml:80-158` — write_files for `ci-deploy.sh`, `hooks.json`, `webhook.service`.
- `apps/web-platform/infra/server.tf:12-126` — `hcloud_server.web` `ignore_changes = [user_data]`, `terraform_data "deploy_pipeline_fix"` SSH-based re-provisioning pattern.
- `.github/workflows/web-platform-release.yml:58-127` — current deploy + verify steps.
