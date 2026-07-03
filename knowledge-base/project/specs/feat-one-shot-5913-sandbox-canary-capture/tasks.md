# Tasks — Wire creds-gated real `--capture` for the faithful sandbox canary (#5913)

Plan: `knowledge-base/project/plans/2026-07-03-feat-sandbox-canary-real-capture-plan.md`
Branch: `feat-one-shot-5913-sandbox-canary-capture` · Issue: #5913 · ADR-079 deferral B
lane: cross-domain (no spec.md — defaulted, TR2 fail-closed)

## Phase 0 — Preconditions
- [ ] 0.1 Confirm installed `@anthropic-ai/claude-agent-sdk@0.3.197`; grep `sdk.mjs` to re-confirm `bwrap` PATH auto-detection.
- [ ] 0.2 Confirm the `query()` option shape (`sandbox`/`model`/`maxTurns`/`permissionMode`/`canUseTool`) and the `"sandbox required but unavailable"` failure substring against the installed SDK (not memory).
- [ ] 0.3 Verify the current cheapest reliably-tool-calling model ID + per-token price against the `claude-api` reference (do NOT hardcode `claude-sonnet-5`).
- [ ] 0.4 Confirm GH-hosted `ubuntu-latest` can drive the SDK with `ANTHROPIC_API_KEY`, and that the guardrail-3 docker-bwrap userns pattern from `sandbox-canary-regression.test.sh` is reusable for the CI replay.

## Phase 1 — Pure LLM-free capture logic (RED → GREEN, vitest)
- [ ] 1.1 Write failing tests in `apps/web-platform/test/sandbox-canary.test.ts` for `parseShimSetupArgv`, `deterministicSiblingRoot`, input-sort normalization (byte-stability + no output-token reorder), `assessCaptureOutcome`.
- [ ] 1.2 Implement `parseShimSetupArgv(rawArgv)` — split at first `--`.
- [ ] 1.3 Implement `deterministicSiblingRoot()` — fixed **non-symlinked** root (realpath-normalized) + constant UUID own-workspace + fixed sorted sibling set; return `{ root, ownWorkspacePath, prepDirs }`.
- [ ] 1.4 Sort the sibling **input** list via existing `sortDenyPaths` before it feeds `buildAgentSandboxConfig`; do NOT sort emitted argv tokens (breaks `--tmpfs DIR` / `--bind SRC DEST` pairing).
- [ ] 1.5 Implement `assessCaptureOutcome({ captureFilePresent, setupArgv })` — require non-empty argv with a `--unshare-*` token; de-dupe multi-spawn (init probe vs. Bash-tool).
- [ ] 1.6 Keep green: `sandbox-canary.test.ts:150` lazy `await import()` + `:160` no-hand-authored-argv contract.

## Phase 2 — `--capture` / `--verify` runtime (side-effecting; CI-only)
- [ ] 2.1 Replace `runCapture` stub (`return 3`): guard on `SANDBOX_CANARY_CAPTURE=1` **and** `ANTHROPIC_API_KEY`; else `creds_absent` + reserved exit `4`, no write.
- [ ] 2.2 Build the bwrap PATH shim (temp `bin/`): record SETUP argv (pre-`--`) to `$CAPTURE_FILE`, exec the post-`--` no-op; handle multi-spawn.
- [ ] 2.3 Drive `query()` with the real `buildAgentSandboxConfig(ownWorkspacePath)`, cheapest tool-calling model, `maxTurns:1–2`, directive no-op Bash prompt, `canUseTool` force-allow.
- [ ] 2.4 Non-determinism bound: retry `N` (default 3) each under a per-attempt wall-clock timeout (ceiling `N×timeout`); break on valid capture; on failure emit `capture_no_bwrap` + exit `4` (non-fixture, no overwrite).
- [ ] 2.5 Write fixture `{status:"captured", sdkPackage, sdkVersion, bwrapSetupArgv, prepDirs}` (atomic); no prod-shaped path rewrite.
- [ ] 2.6 `finally`/`EXIT`-trap cleanup: remove shim `bin/`, hermetic root, capture file; never persist `ANTHROPIC_API_KEY` to a temp file.
- [ ] 2.7 Implement `--verify`: re-capture to temp, byte-diff committed, non-zero on drift with "commit the refreshed argv" message.

## Phase 3 — Commit the first real captured fixture (self-replay-green first)
- [ ] 3.1 In one CI run: `--capture` → replay the fresh argv against committed `infra/seccomp-bwrap.json`, assert PASS → only then commit (do not seed #5889's first soak deploy red).
- [ ] 3.2 Flip `apps/web-platform/infra/sandbox-canary-argv.json` `uncaptured → captured`; `sdkVersion:"0.3.197"`; update `_comment` to "real-captured".
- [ ] 3.3 Update `sandbox-canary-regression.test.sh` A5b assertion `uncaptured → captured`; keep it DISTINCT from `split-unshare-argv.json` (guardrail 1).

## Phase 4 — CI SDK-bump gate wiring (block on captured sandbox_broken; ack-fallback)
- [ ] 4.1 Add an always-run required check (step in `lockfile-sync` or a dedicated job) reusing `sdk-bump-sandbox-gate.sh` bump detection; consider extracting to `sandbox-canary-capture-gate.sh` (+ `.test.sh`) for testable shell.
- [ ] 4.2 Creds present + bump: `--capture` → docker-replay captured argv vs committed seccomp → parse verdict JSON; **block ONLY on captured `sandbox_broken`**; `--verify` drift also blocks.
- [ ] 4.3 Capture-mechanism failure (exit `4` / no bwrap / non-discriminating SKIP): fall back to requiring `sdk-bump-verified:` ack — do NOT hard-block.
- [ ] 4.4 Creds absent (fork PR): check passes; `sdk-bump-verified:` ack remains required (degrade to ack, never silent green).
- [ ] 4.5 Extend `sdk-bump-sandbox-gate.test.sh` (+ new gate `.test.sh`): bump∧creds→block on drift/sandbox_broken; capture-fail→ack-fallback; creds-absent→pass+ack; no-bump→pass.

## Phase 5 — ADR-079 amendment (in-scope)
- [ ] 5.1 Amend `ADR-079-…md` Deferral B: record it landed/wired (cite #5913 / this PR), the resolved non-determinism bound (retry-N + per-attempt timeout + reserved exit `4`), and the block-on-captured-`sandbox_broken` / ack-fallback semantic.
- [ ] 5.2 Keep status `adopting` (Deferral A / #5889 soak still open); reaffirm the BOTH-B-and-A flip-to-`accepted` criterion. No C4 change (verify against `model.c4`/`views.c4`/`spec.c4`).

## Phase 6 — Verify & ship
- [ ] 6.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [ ] 6.2 `./node_modules/.bin/vitest run test/sandbox-canary.test.ts` green; run the `test-scripts` shard (`sandbox-canary-regression.test.sh`, `sdk-bump-sandbox-gate.test.sh`).
- [ ] 6.3 Review-time: route `observability-coverage-reviewer` + `security-sentinel`; reviewers eyeball the argv fixture diff.
- [ ] 6.4 PR body: `Refs #5875, #5889, ADR-079`; do NOT `Closes #5889` (its soak is downstream). Note the per-SDK-bump-PR API cost.
