# perf(kb): qpdf concurrency gate + container tmpfs /tmp

**Branch:** `feat-one-shot-pdf-concurrency-tmpfs`
**Worktree:** `.worktrees/feat-one-shot-pdf-concurrency-tmpfs/`
**Closes:** #2472, #2473
**Ref:** PR #2457 (prior-art merged 2026-04-17), plan `knowledge-base/project/plans/2026-04-17-perf-pdf-linearization-on-upload-plan.md`

## Enhancement Summary

**Deepened on:** 2026-04-18
**Sections enhanced:** Research Reconciliation, Files to Edit, Phase 3 (tmpfs flag set), Phase 6 (post-merge), Risks, Sharp Edges, Domain Review
**Validation performed this pass:**

- Live Docker 29.4.0 verification of `--tmpfs /tmp:…` flag syntax, including size enforcement and noexec default.
- Live git credential-helper invocation test proved Docker's `--tmpfs` default `noexec` silently breaks `credential.helper=!/tmp/git-cred-<uuid>` (used by `workspace.ts`, `session-sync.ts`, `push-branch.ts`).
- Repo-wide audit of in-container `/tmp` consumers: only two (`pdf-linearize.ts` mkdtemp — no exec needed; `randomCredentialPath()` — DOES need exec).
- Learnings cross-referenced: `2026-04-12-buildtree-bounded-concurrency-emfile.md` (inline `mapWithConcurrency` precedent — validates no-external-dep choice), `2026-03-28-tmpfs-guard-cron-defense-in-depth.md` (tmpfs-size-cap precedent — validates `size=256m`), `2026-04-07-code-review-batch-ws-validation-error-logging-concurrency-comments.md` (inline concurrency comments with callsite-local rationale).

### Key Improvements

1. **tmpfs flag set corrected:** `rw,nosuid,nodev,size=256m`. **DO NOT include `noexec`** — Docker sets `noexec` in the default flag set and breaks git's credential helper (`credential.helper=!…` invokes the helper as an executable, git does not prefix with `sh`). Verified with a live docker test below.
2. **In-container /tmp consumer map** added — documents that only the PDF linearize path and git credential helper write to `/tmp` inside the container, and what each needs from the mount options.
3. **Semaphore implementation pattern** aligned with repo precedent (`mapWithConcurrency` worker-pool in `server/kb-reader.ts`) — inline, no external dep, well-understood in the codebase.
4. **Release-on-error invariants** expanded: every error branch inside the gated block is enumerated, with an explicit test per branch (Tests 2–4).
5. **Post-merge verification sharpened** — exact `docker inspect` output format + specific Sentry query to confirm no tmpfs-full failures.

### New Considerations Discovered

- **Plan-breaking: `noexec` tmpfs default in Docker breaks git credential helpers.** Caught live at deepen-pass time, corrected here before implementation. Without this catch, the `/tmp` mount change would silently break every `cloneRepo` / `syncSession` / `pushBranch` call path the day it lands.
- **Dockerfile change NOT required.** The Dockerfile writable layer was the old `/tmp` backing; switching to tmpfs happens at `docker run` time. This means no image rebuild — the flag change flows through `ci-deploy.sh` on the next webhook deploy.

## Overview

Drain the two `deferred-scope-out` issues filed against PR #2457 in one PR. Both tighten the PDF linearization path introduced by #2457:

1. **#2472 (app)** — Cap concurrent `qpdf --linearize` subprocesses per replica. Today `linearizePdf()` spawns a new qpdf for every KB upload with no gate. Peak RAM and `/tmp` disk scale linearly with concurrent uploads. Fix: add an in-module async semaphore around `runQpdf()` with a small pool (default 2, env-overridable).
2. **#2473 (infra)** — Mount `/tmp` as tmpfs (size-capped) on the web-platform container. Today `/tmp` sits on overlayfs — each ~20 MB tempfile pair triggers COW write-amplification and layer bloat under sustained load. Fix: add `--tmpfs /tmp:rw,nosuid,nodev,size=256m` to both `docker run` invocations (ci-deploy.sh canary + production swap) and to cloud-init.yml's bootstrap `docker run`. **Intentionally omits `noexec`** — see Research Reconciliation row 5; git credential helpers under `/tmp` must remain executable.

The two changes are packaged together because they both harden the PDF linearization path and both live in the same conceptual surface (write-path tempfile lifecycle × subprocess pressure). Shipping separately would force two review cycles on the same mental model.

## Research Reconciliation — Spec vs. Codebase

| Claim (from issues) | Reality (codebase) | Plan response |
|---|---|---|
| "Add a `p-queue`-style concurrency gate" (#2472) | No `p-limit`/`p-queue` dep in `apps/web-platform/package.json`. Only consumer is `runQpdf()`. | Implement a ~15-line async semaphore inline in `server/pdf-linearize.ts`. Avoid adding a dependency for one call site (constitution: minimal deps). |
| "Add `tmpfs: /tmp` to docker compose" (#2473) | **No docker-compose in this app.** Production deploys via `docker run` inside `apps/web-platform/infra/ci-deploy.sh` (canary on :3001 then prod on :80/:3000). Fresh-server bootstrap is a second `docker run` in `apps/web-platform/infra/cloud-init.yml` write_files. | Fix lives in `ci-deploy.sh` (2 `docker run` blocks) and `cloud-init.yml` (1 `docker run` block). Three insertion points, not one. |
| "PR #2457 writes ~20 MB per upload to /tmp" | Confirmed: `linearizePdf()` calls `mkdtemp(tmpdir(), "pdf-linearize-")` then writes `in.pdf` + reads `out.pdf`. `os.tmpdir()` honours `TMPDIR` env (already allowlisted into the qpdf subprocess env). | tmpfs mount at `/tmp` is transparent to the Node code — no app-side change needed to benefit. |
| "scope-out: `cross-cutting-refactor`" (#2473) | The change is localised to 3 docker-run lines + their test assertions. Not cross-cutting. | Ship inline. The scope-out was accurate *at the time* of PR #2457 review (mixing app + infra is correct to avoid); one week later, a dedicated PR that packages only these two follow-ups IS the right home. |
| "tmpfs flags should include `noexec` for hardening" (common default) | `workspace.ts:144`, `session-sync.ts:75`, `push-branch.ts:116` call `randomCredentialPath()` → writes `#!/bin/sh` credential helper to `/tmp/git-cred-<uuid>`, invoked via `git -c credential.helper=!…`. Live-tested with Docker 29.4.0: Docker's `--tmpfs /tmp:size=…` applies `noexec` by default, and the `!` prefix makes git invoke the helper as an executable (not via `sh -c`). Result: `/tmp/git-cred-test get: line 0: /tmp/git-cred-test: Permission denied`. | **Drop `noexec`** from the flag set. Use `rw,nosuid,nodev,size=256m` — no `noexec`, no `exec` (exec is the non-noexec default for ext4/overlay writeable layer today, so we preserve current behavior). `nosuid,nodev` retain meaningful hardening without breaking git auth. |

## Open Code-Review Overlap

Ran the overlap check (`gh issue list --label code-review --state open` filtered for paths in scope — `server/pdf-linearize.ts`, `Dockerfile`, `infra/**`, `ci-deploy.sh`):

- **#2472** — this PR closes it. ✓
- **#2473** — this PR closes it. ✓

No other open code-review issue touches these files. The two open review issues in the repo (#2507, #2508) are unrelated (Plausible PII).

## In-Container /tmp Consumer Map

Grep of `server/**/*.ts` (excluding tests) for `/tmp`, `os.tmpdir`, `mkdtemp`:

| Consumer | File:line | Pattern | tmpfs compatibility |
|---|---|---|---|
| PDF linearize tempdir | `server/pdf-linearize.ts:36` | `mkdtemp(join(tmpdir(), "pdf-linearize-"))` → writes `in.pdf` + reads `out.pdf` | Read/write only. No exec needed. `size=256m` cap is the active concern. |
| Git credential helper | `server/github-app.ts:471` (callers: `workspace.ts`, `session-sync.ts`, `push-branch.ts`) | `/tmp/git-cred-<uuid>` written as shell script, invoked via `git -c credential.helper=!…` | **Requires exec.** Forces the tmpfs flag set to omit `noexec`. Files are ≤1 KB each with sub-second lifetime — negligible impact on size budget. |

Doppler CLI does NOT run inside the container (host-side only — see `webhook.service`); `DOPPLER_CONFIG_DIR=/tmp/.doppler` is in the **host** env, unaffected by container tmpfs.

Next.js runtime under `NODE_ENV=production` does not write to `/tmp` at page-serve time (cache lives under `.next/cache` on the image). No additional consumers.

## Files to Edit

- `apps/web-platform/server/pdf-linearize.ts` — add `acquire()`/`release()` semaphore around `runQpdf()`; expose pool size via `PDF_LINEARIZE_CONCURRENCY` env (default 2). Pattern aligns with `mapWithConcurrency` worker-pool already in `server/kb-reader.ts` (see learning `2026-04-12-buildtree-bounded-concurrency-emfile.md`).
- `apps/web-platform/test/pdf-linearize.test.ts` — add tests: (a) third concurrent call waits until one of the first two settles; (b) release happens on success, non-zero exit, timeout, and spawn_error (regression-proofing against a leak on any error branch); (c) env-override dynamic-import test for `PDF_LINEARIZE_CONCURRENCY=1`.
- `apps/web-platform/infra/ci-deploy.sh` — add `--tmpfs /tmp:rw,nosuid,nodev,size=256m` to both `docker run` blocks (canary @ line ~251 and production swap @ line ~296). Add a 1-line comment above each `--tmpfs` insertion: `# noexec deliberately omitted — randomCredentialPath() writes executable helpers to /tmp (see workspace.ts / session-sync.ts / push-branch.ts).` Keep other flags untouched. Use symbol anchors (function names), not line numbers, per AGENTS.md `cq-code-comments-symbol-anchors-not-line-numbers`.
- `apps/web-platform/infra/cloud-init.yml` — add the same `--tmpfs` flag (and same 1-line comment) to the bootstrap `docker run` block (@ line ~255, `soleur-web-platform`).
- `apps/web-platform/infra/ci-deploy.test.sh` — add an assertion under the existing `apparmor-trace` runner (or a new `tmpfs-trace` mode) that every production `docker run` line contains `--tmpfs /tmp:*size=256m` AND does NOT contain `noexec` on the tmpfs argument. Same pattern as the existing `apparmor=soleur-bwrap` assertion at line ~805. The "no noexec" assertion locks the plan-breaking regression class from Research Reconciliation row 5.

## Files to Create

None. All changes land in existing files.

## Implementation Phases

### Phase 1 — Concurrency gate in `pdf-linearize.ts` (closes #2472)

**Design:** in-module FIFO async semaphore. No external dep. Exposed pool size via env var for ops control.

```ts
// Near top of server/pdf-linearize.ts, after TIMEOUT_MS.

// Pool size: env-driven, clamped to [1, 16]. Default 2 matches the
// observation in PR #2457 plan: two concurrent 20MB uploads is the
// accepted-risk baseline; anything beyond should queue rather than
// fan out.
const POOL_SIZE = (() => {
  const raw = Number(process.env.PDF_LINEARIZE_CONCURRENCY);
  if (!Number.isFinite(raw) || raw < 1) return 2;
  return Math.min(Math.floor(raw), 16);
})();

let inFlight = 0;
const waiters: Array<() => void> = [];

function acquire(): Promise<void> {
  if (inFlight < POOL_SIZE) {
    inFlight++;
    return Promise.resolve();
  }
  return new Promise<void>((resolve) => {
    waiters.push(() => {
      inFlight++;
      resolve();
    });
  });
}

function release(): void {
  inFlight--;
  const next = waiters.shift();
  if (next) next();
}
```

**Wrap `runQpdf` (not `linearizePdf`)** — acquire the slot only for the subprocess section, not for `isSignedPdf` (sync) or `mkdtemp`/`writeFile` (cheap). That narrows the critical section to the one thing we're protecting: concurrent qpdf subprocesses. `skip_signed` returns early without touching the gate.

Critical edit shape inside `linearizePdf()`:

```ts
await acquire();
try {
  await writeFile(inPath, input);
  const run = await runQpdf(inPath, outPath);
  // ... existing body unchanged
} finally {
  release();
  // existing rm(dir, { recursive: true, force: true }) moves out of the
  // outer finally into a sibling try/finally so release() fires before
  // the rm.
}
```

**Release discipline:** every exit path from inside the `acquire()` block must release — success, non_zero_exit, timeout, spawn_error, empty output, writeFile throw. The `try { ... } finally { release(); }` shape covers all of them. Do NOT put `acquire()` outside the existing `try { ... } finally { rm(dir) }` — that would leak the slot if mkdtemp succeeded but writeFile threw.

**Sharp edges (for implementer):**

- Place `acquire()` AFTER `mkdtemp` and signed-skip (two fast paths return without touching the gate).
- `runQpdf` itself returns settled results — no unhandled rejection path exists today; verify `runQpdf(...)` is awaited (it is, line 45).
- Fake-timer test for timeout must still work — the semaphore does not introduce a new real timer.

### Phase 2 — Tests for the gate (RED before Phase 1 code lands)

Add to `apps/web-platform/test/pdf-linearize.test.ts`:

**Test 1: third concurrent call queues until first releases.** Spawn three `linearizePdf()` promises simultaneously against a `holdOpen: true` fakeChild. Assert `mockSpawn` was called exactly twice (POOL_SIZE=2 default). Emit close on the first fake child. Assert `mockSpawn` reaches 3. Emit close on the remaining two. Await all three; assert all resolve `ok: true`.

```ts
it("caps concurrent qpdf subprocesses to POOL_SIZE (2)", async () => {
  vi.useFakeTimers();
  const children: Array<ReturnType<typeof fakeChild>> = [];
  mockSpawn.mockImplementation(() => {
    const c = fakeChild({ holdOpen: true });
    children.push(c);
    return c;
  });
  mockReadFile.mockResolvedValue(Buffer.from("%PDF-out"));

  const p1 = linearizePdf(Buffer.from("%PDF-1"));
  const p2 = linearizePdf(Buffer.from("%PDF-2"));
  const p3 = linearizePdf(Buffer.from("%PDF-3"));

  // Give microtasks time to reach the acquire() point.
  await vi.advanceTimersByTimeAsync(0);
  expect(mockSpawn).toHaveBeenCalledTimes(2);   // p3 is queued

  // Release the first slot by emitting close on child[0].
  children[0].emit("close", 0, null);
  await vi.advanceTimersByTimeAsync(0);
  expect(mockSpawn).toHaveBeenCalledTimes(3);   // p3 enters the gate

  children[1].emit("close", 0, null);
  children[2].emit("close", 0, null);
  const results = await Promise.all([p1, p2, p3]);
  vi.useRealTimers();
  expect(results.every((r) => r.ok)).toBe(true);
});
```

**Test 2: slot releases on timeout.** Start POOL_SIZE inputs with `holdOpen: true`, advance timers past `TIMEOUT_MS`, then start one more `linearizePdf()` and assert it gets past the gate (mockSpawn called POOL_SIZE+1 times).

**Test 3: slot releases on spawn_error.** Start two `linearizePdf()` calls where the first spawns with a synthetic `ENOENT`. Second must enter the gate.

**Test 4: slot releases on non_zero_exit.** Similar shape — exit code 3 on child 1, child 2 must enter the gate.

**Pool-size env override** — set `process.env.PDF_LINEARIZE_CONCURRENCY = "1"` in a separate `describe` block that does `vi.resetModules()` before `await import("../server/pdf-linearize")`. Assert that two concurrent calls serialize. **Note:** This test requires dynamic import because POOL_SIZE is captured at module load; prior tests use the top-level static import.

**Critical invariant (asserted by Test 2–4):** every error branch releases. This is the regression that would be easy to introduce during later edits (e.g. an `early return` inside the semaphore-guarded block without `release()`).

### Phase 3 — tmpfs /tmp on docker run (closes #2473)

Edit `apps/web-platform/infra/ci-deploy.sh`:

At line ~251 (canary `docker run`), insert as a new line between `--security-opt seccomp=...` and `--env-file "$ENV_FILE"`:

```bash
      --tmpfs /tmp:rw,nosuid,nodev,size=256m \
```

At line ~296 (production swap `docker run`), insert the same line in the same relative position.

Edit `apps/web-platform/infra/cloud-init.yml` — find the `docker run` block (line ~255 per grep) for `soleur-web-platform` and add the same `--tmpfs` flag. **Verify by grep:** `grep -n "docker run" cloud-init.yml` returns exactly the expected line count before and after the edit.

**Flag anatomy (for review):**

- `rw` — writable (Docker default, listed explicitly for grep-stable assertions and so that the flag string is copy-obvious in code review).
- `nosuid` — a setuid binary written to `/tmp` by a compromised process would not gain elevated privileges. Zero cost for our workload (nothing setuids there).
- `nodev` — no device nodes creatable in `/tmp`. Defense in depth against rare container escapes via `/tmp/devfile`.
- `size=256m` — ceiling. Peak expected usage: POOL_SIZE (2) × (input 20 MB + output 20 MB) = 80 MB, plus transient `/tmp/git-cred-<uuid>` files (≤1 KB each, lifetime sub-second). 256 MB leaves 3× headroom. If a burst ever fills it, qpdf returns `non_zero_exit`/`io_error` cleanly — the silent-fallback path in `kb-upload-payload.ts` already handles this (unmodified bytes are stored; Sentry mirrors via `warnSilentFallback`).
- **`noexec` DELIBERATELY NOT SET** — see Research Reconciliation row 5. Docker's `--tmpfs` applies `noexec` by default; the flag string passed via `--tmpfs /tmp:<opts>` replaces the default set entirely. Omitting `noexec` from `<opts>` restores exec and keeps `randomCredentialPath()` functional. Document this inline in `ci-deploy.sh` with a 1-line comment anchor (`# noexec deliberately omitted — git credential helper in /tmp/git-cred-*`).

**Live verification performed at plan time (Docker 29.4.0):**

```text
$ docker run --rm --tmpfs /tmp:rw,nosuid,nodev,size=16m alpine:latest \
    sh -c 'mount | grep " /tmp "'
tmpfs on /tmp type tmpfs (rw,nosuid,nodev,relatime,size=16384k,inode64)

$ docker run --rm --tmpfs /tmp:rw,nosuid,nodev,size=16m alpine:latest sh -c '
    cat >/tmp/helper << EOF
    #!/bin/sh
    echo username=x
    echo password=y
    EOF
    chmod 700 /tmp/helper
    echo -e "protocol=https\nhost=example.com\n" |
      git -c "credential.helper=!/tmp/helper" credential fill'
protocol=https
host=example.com
username=x
password=y

$ docker run --rm --tmpfs /tmp:rw,nosuid,nodev,size=16m alpine:latest \
    sh -c 'dd if=/dev/zero of=/tmp/test bs=1M count=64 2>&1 | tail -2'
16+0 records in
16+0 records out       # cap enforced at 16 MB
```

**Why not `/var/tmp` or a bind mount:** `os.tmpdir()` returns `/tmp` by default inside the container (no `TMPDIR` in the env-file). Mounting `/tmp` as tmpfs is the zero-code-change path. Overriding `TMPDIR=/app/tmp` would require an app change and offers no benefit over the tmpfs approach.

### Phase 4 — Test assertion for tmpfs flag

Add to `apps/web-platform/infra/ci-deploy.test.sh`, mirroring the `apparmor=soleur-bwrap` assertion pattern at line ~805–850:

```bash
echo "--- tmpfs /tmp on docker run ---"

assert_tmpfs_flag() {
  local description="$1"
  local target_tag="$2"
  (
    export MOCK_DOCKER_MODE="apparmor-trace"  # emits DOCKER_RUN_ARGS lines
    # ... set up TMPDIR, PATH, create mocks ...
    run_deploy_web_platform "$target_tag" > "$output_file" 2>&1
  )
  local run_lines
  run_lines=$(grep "^DOCKER_RUN_ARGS:" "$output_file" || true)
  # Positive: the flag is present AND size-capped at 256m.
  if ! grep -qE -- "--tmpfs /tmp:[^ ]*size=256m" <<< "$run_lines"; then
    echo "  FAIL: $description (missing --tmpfs /tmp:…size=256m)"
    echo "  docker run lines:"
    echo "$run_lines" | sed 's/^/    /'
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
    return
  fi
  # Negative: the tmpfs argument must NOT contain noexec (would break
  # /tmp/git-cred-<uuid> credential helpers — see workspace.ts:144).
  if grep -qE -- "--tmpfs /tmp:[^ ]*noexec" <<< "$run_lines"; then
    echo "  FAIL: $description (tmpfs has noexec — breaks git credential helper)"
    echo "  docker run lines:"
    echo "$run_lines" | sed 's/^/    /'
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  fi
  TOTAL=$((TOTAL + 1))
}

assert_tmpfs_flag "web-platform: docker run has --tmpfs /tmp:size=256m without noexec" "v1.0.0"
```

**Why two assertions:**

- **Positive (`size=256m`):** a future edit might drop `size=` and rely on the Docker default (50% of host RAM), violating the "size-capped" intent of #2473. Regex locks the cap.
- **Negative (no `noexec`):** Docker's default flag set includes `noexec`, but the `--tmpfs …:<opts>` form replaces the entire default set. A future well-meaning edit that adds `noexec` for "hardening" silently breaks git auth across `workspace.ts`, `session-sync.ts`, and `push-branch.ts`. The Research Reconciliation table documents why; this assertion enforces it.

### Phase 5 — Verify & ship

1. Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/pdf-linearize.test.ts` — all tests pass (existing 10 + new 4–5).
2. Run `bash apps/web-platform/infra/ci-deploy.test.sh` — all pass including the new tmpfs assertion.
3. Run `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
4. `doppler run -p soleur -c dev -- ./scripts/dev.sh 3100` smoke-test: upload a real PDF via the KB uploader, confirm in logs that linearization runs and completes. (Concurrency gate is inert for a single upload; the test is that the refactor didn't break the happy path.)
5. `/ship` with `type/chore` + `domain/engineering` labels. PR body MUST include `Closes #2472` and `Closes #2473` (separate lines).

### Phase 6 — Post-merge verification (operator)

- After merge, the existing `deploy_pipeline_fix` terraform_data triggers on `ci-deploy.sh` hash change — `terraform apply` pushes the new ci-deploy.sh to the live server. cloud-init.yml change only affects **future** fresh provisions (existing server has `ignore_changes = [user_data]` per server.tf line 45).
- SSH read-only check (per AGENTS.md `cq-for-production-debugging-use` — infrastructure verification is the sanctioned SSH use): `docker inspect soleur-web-platform --format '{{json .HostConfig.Tmpfs}}'` must return a value matching `{"/tmp":"rw,nosuid,nodev,size=256m"}` (no `noexec`). Also run `docker exec soleur-web-platform mount | grep " /tmp "` — output should include `size=262144k` (256 MiB in kbytes) and must NOT include `noexec`. If either check fails, the deploy did not re-create the container — trigger a redeploy via the webhook.
- **Spot-test git credential helper path still works post-tmpfs** (blast-radius check for the noexec regression class): trigger any feature that calls `cloneRepo` (e.g., open a workspace for a new repo via the UI) and confirm no `Permission denied` in Sentry within the hour. Alternative smoke-test (run on the Hetzner host):

  ```bash
  docker exec soleur-web-platform sh -c '
    printf "%s\n%s\n" "#!/bin/sh" "echo smoke-ok" > /tmp/smoke.sh
    chmod 700 /tmp/smoke.sh
    /tmp/smoke.sh
    rm -f /tmp/smoke.sh
  '
  # expected output: smoke-ok
  ```

- Sentry check 24 h post-deploy: confirm no spike in `pdf linearization failed` with `reason=io_error` (would indicate tmpfs cap is too small in practice).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `linearizePdf()` acquires a semaphore slot around `runQpdf()` only (not around `isSignedPdf` or `mkdtemp`).
- [ ] Semaphore default is 2; env `PDF_LINEARIZE_CONCURRENCY` overrides, clamped to `[1, 16]`.
- [ ] Slot is released on every exit path: success, non_zero_exit, timeout, spawn_error, empty output, writeFile throw.
- [ ] New test: third concurrent call waits until one of the first two settles.
- [ ] New tests (×3): release happens on timeout, spawn_error, non_zero_exit — verified by assertions that a follow-up 3rd call gets past the gate after the blocking call fails.
- [ ] New test: `PDF_LINEARIZE_CONCURRENCY=1` via dynamic import serializes two concurrent calls.
- [ ] `ci-deploy.sh` canary `docker run` includes `--tmpfs /tmp:rw,nosuid,nodev,size=256m`.
- [ ] `ci-deploy.sh` production `docker run` includes the same flag.
- [ ] `cloud-init.yml` bootstrap `docker run` includes the same flag.
- [ ] `ci-deploy.test.sh` asserts (a) `--tmpfs /tmp:…size=256m` is present AND (b) the tmpfs argument does NOT contain `noexec` on every production `docker run`.
- [ ] Inline comment above each new `--tmpfs` line in `ci-deploy.sh` and `cloud-init.yml` explains why `noexec` is deliberately omitted (anchor: `workspace.ts:144`, i.e. use the symbol name, not the line number, per `cq-code-comments-symbol-anchors-not-line-numbers`).
- [ ] All existing `pdf-linearize.test.ts` tests still pass (10 baseline tests).
- [ ] `tsc --noEmit` clean; lefthook pre-commit clean.
- [ ] PR body contains `Closes #2472` and `Closes #2473` on separate lines.

### Post-merge (operator)

- [ ] `terraform apply` pushes the updated `ci-deploy.sh` (existing `deploy_pipeline_fix` triggers on file hash).
- [ ] One webhook-driven redeploy recreates the production container with the new flags.
- [ ] `docker inspect soleur-web-platform --format '{{json .HostConfig.Tmpfs}}'` shows `/tmp` tmpfs with `size=256m`.
- [ ] 24 h post-deploy: no spike in Sentry `pdf linearization failed` with `reason=io_error` (if spike, reassess `size=256m`).

## Test Scenarios

Scripted tests cover all the Pre-merge items above. Manual smoke path (Phase 5 step 4) verifies the happy path end-to-end.

## Risks & Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Semaphore leaks a slot on a code path not exercised by tests (e.g. future edit adds an `if (...) return` inside the gate without `release()`) | Replicas eventually stop linearizing — queue grows unbounded; uploads time out at route `maxDuration=30`. | Wrap the gated block in `try { ... } finally { release(); }` (single exit). Comment above the `finally` anchoring why. |
| `POOL_SIZE=2` too low under spiky load | Uploads queue up to 20 s before qpdf starts (TIMEOUT_MS is *per subprocess*, not per queue wait). Route hits 30 s maxDuration. | Env override (`PDF_LINEARIZE_CONCURRENCY=4` bumps the pool). Watch Sentry for `pdf linearization failed` with no subprocess reason — indicates wait-time dominance. |
| tmpfs `size=256m` too small under burst | qpdf exits non-zero with `ENOSPC` writing `out.pdf`. | The silent-fallback path already handles this: `kb-upload-payload.ts` returns the unmodified buffer, `warnSilentFallback` mirrors to Sentry. No data loss. |
| Container restart loses `/tmp` | None — `/tmp` is ephemeral by design. No code in the app depends on `/tmp` persistence. | N/A (intended behavior). |
| Doppler CLI caches under `/tmp/.doppler` (ci-deploy.sh comment near `DOPPLER_CONFIG_DIR`) | Confusion — this is the **webhook** process on the **host**, not inside the container. The `/tmp/.doppler` path is `/tmp` on the VM, not the container's `/tmp`. | Document in the commit message. The host `/tmp` is unaffected by container tmpfs. |
| **Future well-meaning edit adds `noexec` to the tmpfs arg "for hardening"** | Silent breakage of `cloneRepo` / `syncSession` / `pushBranch` — every GitHub authenticated op fails with `Permission denied` on the credential helper. | Test in `ci-deploy.test.sh` actively asserts the *absence* of `noexec` on the tmpfs argument. Inline comment above the `--tmpfs` line explains why. Research Reconciliation row 5 documents the live-tested evidence. |
| tmpfs occupies RAM (Hetzner CCX host has fixed RAM) | 256 MiB ceiling could pressure other workloads if repeatedly filled. | tmpfs usage is tracked by kernel the same as any cached file — unused tmpfs pages can be evicted; actively written pages count against `MemAvailable`. At sustained saturation the server's existing disk-monitor.sh would NOT catch this (it monitors disk, not RAM). Follow-up: if prod traffic shows sustained tmpfs saturation, add a RAM-watch to `disk-monitor.sh`. Out of scope for this PR. |

## Non-Goals

- Cross-replica rate limiting (the issue explicitly notes single-replica scope). Redis/Upstash coordination is out of scope; single replica today.
- Replacing qpdf with `pdfcpu` or in-process PDF optimization. PR #2457 settled on qpdf; this plan does not relitigate.
- Dynamic `POOL_SIZE` based on replica memory. Flat default + env override is enough for current scale.
- Observability for queue depth. If queue dominates upload latency (Risk #2), a future follow-up adds a Sentry gauge; not needed now.

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| Add `p-limit` dependency | New dep for one call site. Inline semaphore is ~15 lines and test-verified. |
| Concurrency gate at route layer (not inside `linearizePdf`) | Gate-at-source is module-local and reusable if another consumer calls `linearizePdf` later (none today, but the interface is public). Also easier to test (all existing mocks apply). |
| Cross-replica Redis semaphore | Over-engineering. Single replica today; spec says so (#2472 re-eval criteria). |
| Override `TMPDIR=/app/tmpfs` via env + bind-mount | Requires app-side env plumbing. Mounting `/tmp` tmpfs is zero-code-change and gets other `/tmp`-writers (Doppler, Next cache) for free. |
| Use `--read-only` container with multiple tmpfs mounts | Far larger blast radius; Next.js build emits `.next/cache` at runtime in some configs. Out of scope for this PR. |

## Domain Review

**Domains relevant:** Engineering (CTO)

### Engineering (CTO)

**Status:** reviewed (inline assessment, deepen-pass-validated)
**Assessment:** Both changes align with the existing pattern — ci-deploy.sh is the canonical docker-run site, terraform_data.deploy_pipeline_fix already auto-rolls changes to prod on file-hash change, and the semaphore is an idiomatic Node pattern matching the module-local style of the rest of `server/*.ts` (precedent: `mapWithConcurrency` in `server/kb-reader.ts` per learning 2026-04-12).

**Deepen-pass cross-check (infra compatibility):** live-tested Docker 29.4.0 tmpfs flag interaction with all existing in-container `/tmp` consumers (`pdf-linearize.ts`, `randomCredentialPath()`). Identified and corrected a plan-breaking regression class (Docker default `noexec` vs. git credential helpers) before it reached implementation. Test assertion added to prevent re-introduction.

No architectural decisions needed. Content generation N/A. No Product/UX implications (no user-facing surface). No CMO content-opportunity signal. No COO expense signal (no new service signups, Hetzner server already provisioned — tmpfs uses existing RAM budget, not new capacity).

No other domain leaders in scope for this plan.

## Sharp Edges (implementer-facing)

- **DO NOT add `noexec` to the tmpfs flag set** — Docker applies `noexec` by default, but passing `--tmpfs /tmp:<opts>` replaces the default set entirely. The plan's flag set `rw,nosuid,nodev,size=256m` deliberately omits `noexec` because `server/github-app.ts:randomCredentialPath()` writes `#!/bin/sh …` credential helpers to `/tmp/git-cred-<uuid>` and git invokes them as executables. Verified live with Docker 29.4.0 at plan time — adding `noexec` produces `git-cred-<uuid>: Permission denied` and breaks every GitHub auth path. The ci-deploy.test.sh assertion actively enforces the absence of `noexec`.
- **Semaphore release discipline** — the single most likely regression. Test 2–4 lock it; review should verify every `return`/`throw` path inside the gated block flows through the `finally`.
- **Dynamic import for env-override test** — the default POOL_SIZE test must NOT share module state with the override test. Use `vi.resetModules()` + `await import(...)` inside the dedicated `describe` block. Otherwise the first test's POOL_SIZE=2 capture persists into the second.
- **Three `docker run` sites, not two** — ci-deploy.sh has canary AND production swap, cloud-init.yml has the bootstrap. Miss one and fresh-provisioned servers silently lose the tmpfs (ignore_changes=[user_data] means cloud-init change doesn't re-apply to the existing server, but IS the source of truth for future replacement).
- **tmpfs flag position matters for grep** — put it immediately after the `--security-opt seccomp=...` line in both ci-deploy.sh sites so the test regex sees a consistent prefix.
- **Do NOT bump version files** (AGENTS.md `wg-never-bump-version-files-in-feature`).
- **Pin exact docker run tmpfs value in the test** — use a grep for `--tmpfs /tmp:[^ ]*size=256m`, not `--tmpfs /tmp` alone. A future edit dropping `size=` silently widens the cap to 50% of host RAM (Docker default) — the test must fail in that case.
- **Inline comments use symbol anchors, not line numbers** (AGENTS.md `cq-code-comments-symbol-anchors-not-line-numbers`). Reference `randomCredentialPath()` / `workspace.ts` / `session-sync.ts` / `push-branch.ts` by name in the `ci-deploy.sh` noexec-omission comment.
- **`acquire()` placement inside linearizePdf** — acquire AFTER `isSignedPdf` short-circuit and AFTER `mkdtemp` (they're fast and release-free). Wrap ONLY the `writeFile` + `runQpdf` + `readFile` triplet. If you gate the whole function, signed-PDF skips incur an unnecessary wait.
- **Semaphore env read at module load** — `POOL_SIZE` is captured at first module evaluation, not re-read per call. Documented so that ops edits to `PDF_LINEARIZE_CONCURRENCY` require a container restart (webhook redeploy), which is the intended ops path.

## PR-body template (for /ship)

```text
## Summary

Drains two scope-outs filed against PR #2457.

- **#2472 (app)** — Adds an async semaphore (default pool size 2, env-overridable via `PDF_LINEARIZE_CONCURRENCY`) around the qpdf subprocess inside `linearizePdf()`. Caps concurrent qpdf invocations per replica.
- **#2473 (infra)** — Mounts `/tmp` as tmpfs (`rw,nosuid,nodev,size=256m`) in all three `docker run` sites (ci-deploy.sh canary + prod, cloud-init.yml bootstrap). `noexec` is deliberately omitted so git credential helpers under `/tmp/git-cred-*` remain executable.

Both harden the PR #2457 PDF linearization path on the same mental model (/tmp pressure × qpdf subprocess fan-out), so they ship together.

Closes #2472
Closes #2473

## Test plan

- [ ] `vitest run test/pdf-linearize.test.ts` (pool size, release on every error branch, env override)
- [ ] `bash apps/web-platform/infra/ci-deploy.test.sh` (tmpfs flag assertion on canary + prod docker run)
- [ ] `tsc --noEmit` clean
- [ ] Post-merge: `terraform apply` + one webhook redeploy, then `docker inspect soleur-web-platform --format '{{json .HostConfig.Tmpfs}}'` confirms `/tmp` tmpfs at 256m
```
