# Tasks — Wire creds-gated real `--capture` for the faithful sandbox canary (#5913)

Plan: `knowledge-base/project/plans/2026-07-03-feat-sandbox-canary-real-capture-plan.md`
Branch: `feat-one-shot-5913-sandbox-canary-capture` · Issue: #5913 · ADR-079 deferral B
lane: cross-domain (no spec.md — defaulted, TR2 fail-closed)

## Phase 0 — Preconditions
- [x] 0.1 Confirm installed `@anthropic-ai/claude-agent-sdk@0.3.197`; grep `sdk.mjs` to re-confirm `bwrap` PATH auto-detection.
- [x] 0.2 Confirm the `query()` option shape (`sandbox`/`model`/`maxTurns`/`permissionMode`/`canUseTool`) and the `"sandbox required but unavailable"` failure substring against the installed SDK (not memory).
- [x] 0.3 Verify the current cheapest reliably-tool-calling model ID + per-token price against the `claude-api` reference (do NOT hardcode `claude-sonnet-5`).
- [x] 0.4 Empirically observe the SDK's bwrap spawn count per turn AND whether the SETUP argv carries any `--setenv` of a secret (secret-forwarding → Phase-0 BLOCKER).
- [x] 0.5 Confirm the guardrail-3 docker-bwrap userns replay (`sandbox-canary-regression.test.sh` layer B) reliably discriminates on `ubuntu-latest`. If not, CI docker-replay is best-effort SKIP and `--verify` drift is the always-on block — decide blocking-when-runs vs. drop at Phase 0, don't build speculatively.

## Phase 1 — Pure LLM-free capture logic (RED → GREEN, vitest)
- [x] 1.1 Write failing tests in `apps/web-platform/test/sandbox-canary.test.ts` for `parseShimSetupArgv`, `computeCanaryPaths` (stable path set), `assessCaptureOutcome`, and the secret-scrub predicate.
- [x] 1.2 Implement `parseShimSetupArgv(rawArgv)` — split at first `--`.
- [x] 1.3 Implement `computeCanaryPaths()` (PURE, IO-free) — fixed **non-symlinked** realpath-normalized root + constant-UUID own workspace + **empty** sibling set; return `{ root, ownWorkspacePath, prepDirs }`. FS creation lives in Phase 2, not here.
- [x] 1.4 Zero-sibling determinism: capture root has NO siblings → `enumerateSiblingDenyPaths → ["/proc"]` → argv byte-deterministic by construction. Do NOT add `normalizeCapturedArgv` (dropped) and do NOT sort emitted argv tokens.
- [x] 1.5 Implement `assessCaptureOutcome({ captureFilePresent, setupArgv })` — reuse `validateFixture`'s array/non-empty/all-strings checks + add the single `--unshare-*` predicate; when multiple bwrap spawns recorded, select the `--unshare-user` one.
- [x] 1.6 Implement the secret-scrub predicate — reject if any token contains the key value or a `--setenv <NAME>` with NAME matching `/KEY|TOKEN|SECRET|PASSWORD/i`.
- [x] 1.7 Keep green: `sandbox-canary.test.ts:150` lazy `await import()` + `:160` no-hand-authored-argv contract.

## Phase 2 — `--capture` / `--verify` runtime (side-effecting; CI-only)
- [x] 2.1 Replace `runCapture` stub (`return 3`): guard on `SANDBOX_CANARY_CAPTURE=1` **and** `ANTHROPIC_API_KEY`; else `creds_absent` + reserved exit `4`, no write.
- [x] 2.2 `mkdir` the `computeCanaryPaths()` zero-sibling root + own workspace; `WORKSPACES_ROOT=$root`.
- [x] 2.3 Build the bwrap PATH shim in a `mktemp -d` (0700) `bin/`, **prepended FIRST on PATH**: record SETUP argv (pre-`--`) to `$CAPTURE_FILE`, record **only argv (never process.env)**, then **`exit 0`** — do NOT exec the model command tail.
- [x] 2.4 Drive `query()` with the real `buildAgentSandboxConfig(ownWorkspacePath)`, cheapest tool-calling model, `maxTurns:1–2`, directive no-op Bash prompt, `canUseTool` force-allow.
- [x] 2.5 Non-determinism bound: retry `N` (default 3) each under a per-attempt wall-clock timeout (ceiling `N×timeout`); break on valid capture; on failure emit `capture_no_bwrap:<:timeout|:query_threw|:no_tool_call>` + exit `4` (non-fixture, no overwrite).
- [x] 2.6 Secret-scrub before write (reject → exit `4`, no write). Then write fixture `{status:"captured", sdkPackage, sdkVersion, bwrapSetupArgv, prepDirs}` (atomic); no path normalization.
- [x] 2.7 Route EVERY failure (incl. top-level catch for query()/import throw — currently `sandbox-canary.mjs:274-277` exits 2 with no verdict) through `emitVerdict({verdict:"canary_infra_error", reason:"capture_error:<class>"})`. `finally`/`EXIT`-trap cleanup: shim `bin/`, hermetic root, capture file. Key env-only, never a temp file, NO `set -x`.
- [x] 2.8 Implement `--verify` (one routine parameterized by output target): re-capture to temp, byte-diff committed, non-zero on drift with "commit the refreshed argv" message.

## Phase 3 — Commit the first real captured fixture (self-replay-green first)
- [x] 3.1 In one CI run: `--capture` → replay the fresh argv against committed `infra/seccomp-bwrap.json`, assert PASS → only then commit (do not seed #5889's first soak deploy red).
- [x] 3.2 Flip `apps/web-platform/infra/sandbox-canary-argv.json` `uncaptured → captured`; `sdkVersion:"0.3.197"`; update `_comment` to "real-captured".
- [x] 3.3 Update `sandbox-canary-regression.test.sh` A5b assertion `uncaptured → captured`; keep it DISTINCT from `split-unshare-argv.json` (guardrail 1).

## Phase 4 — CI SDK-bump gate wiring (block on captured sandbox_broken; ack-fallback)
- [x] 4.1 **Extend `sdk-bump-sandbox-gate.sh`** (NOT a new gate script) reusing its bump detection. Keep the deterministic gate (parity+bump+ack) and the capture gate as **two independent required checks** so a soft-degraded capture never removes the ack requirement.
- [x] 4.2 Add `apps/web-platform/infra/sandbox-canary-argv.json` to the re-capture/verify trigger set (a fixture-only edit must force `--verify`/ack — command-injection sink via `ci-deploy.sh:445`).
- [x] 4.3 Creds present + bump: `--capture` → (if Phase-0 confirmed discrimination) docker-replay captured argv vs committed seccomp → parse verdict JSON; **block ONLY on captured `sandbox_broken`**; `--verify` drift also blocks (always-on).
- [x] 4.4 Map EVERY non-`sandbox_broken` non-zero (exit `4`, exit `2`/no-verdict, non-discriminating SKIP) → **ack-fallback** (never hard-block, never silent-green) + emit `::warning::` with the verdict reason at the checks summary.
- [x] 4.5 Creds absent (fork PR): capture check passes; ack check remains required; ensure `sdk-bump-verified:` ack is maintainer/write-access-gated (a fork author cannot self-satisfy it).
- [x] 4.6 Extend `sdk-bump-sandbox-gate.test.sh`: bump∧creds→block on drift/sandbox_broken; capture-fail/throw→ack-fallback+warning; fixture-only-edit→verify/ack; creds-absent→pass+ack; no-bump→pass.

## Phase 5 — ADR-079 amendment (in-scope)
- [x] 5.1 Amend `ADR-079-…md` Deferral B: record it landed/wired (cite #5913 / this PR), the resolved non-determinism bound (retry-N + per-attempt timeout + reserved exit `4`), and the block-on-captured-`sandbox_broken` / ack-fallback semantic.
- [x] 5.2 Keep status `adopting` (Deferral A / #5889 soak still open); reaffirm the BOTH-B-and-A flip-to-`accepted` criterion. No C4 change (verify against `model.c4`/`views.c4`/`spec.c4`).

## Phase 6 — Verify & ship
- [x] 6.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [x] 6.2 `./node_modules/.bin/vitest run test/sandbox-canary.test.ts` green; run the `test-scripts` shard (`sandbox-canary-regression.test.sh`, `sdk-bump-sandbox-gate.test.sh`).
- [x] 6.3 Review-time: route `observability-coverage-reviewer` + `security-sentinel`; reviewers eyeball the argv fixture diff.
- [x] 6.4 PR body: `Refs #5875, #5889, ADR-079`; do NOT `Closes #5889` (its soak is downstream). Note the per-SDK-bump-PR API cost.
