# Tasks — fix: sandbox-canary capture projection — bridge-spawn placeholder + fixture refresh

Plan: `knowledge-base/project/plans/2026-10-06-fix-sandbox-canary-bridge-spawn-placeholder-plan.md`
Issues: #9614, #9618 | Branch: `feat-one-shot-9614-9618-canary-capture-fixture`

Note: this PR touches two capture inputs (`scripts/sandbox-canary.mjs`,
`infra/sandbox-canary-argv.json`) plus `server/agent-runner-sandbox-config.ts`,
so the `sandbox-canary-capture-gate` CI job WILL run on it. The gate passes
only if Phase 4's in-image re-capture + `--verify` land BEFORE merge — the
fixture refresh is a merge-blocker, not an optional step.

## Phase 1 — failing tests (cq-write-failing-tests-before)

- [ ] 1.1 `apps/web-platform/test/sandbox-canary.test.ts`: import
  `CANARY_BRIDGE_SPAWN_PLACEHOLDER`; add `describe("bridge-spawn placeholder
  (#9614/#9618)")` covering:
  - `<homedir>/.claude/bridge-spawn` (and a `/sub` subpath) maps to
    `${CANARY_BRIDGE_SPAWN}` when `bridgeSpawnRoot` is passed; prepDirs gains it;
  - `substituteCanonicalArgv` with `bridgeSpawn` round-trips; without it,
    `hasUnsubstitutedPlaceholder` is true;
  - WITHOUT the opt, `"--tmpfs", "/root/.claude/bridge-spawn"` still throws
    `/host_path/` (fail-loud regression pin);
  - `--tmpfs /root/.ssh` still throws `/host_path/` even WITH the opt (sibling
    HOME paths are not loosened);
  - committed-fixture census: add the placeholder to `known` and assert
    `--tmpfs ${CANARY_BRIDGE_SPAWN}` appears exactly once + prepDirs contains
    it (this row stays RED until Phase 4).
- [ ] 1.2 `cd apps/web-platform && npx vitest run test/sandbox-canary.test.ts`
  → new assertions RED.

## Phase 2 — projection + replay implementation

- [ ] 2.1 `apps/web-platform/scripts/sandbox-canary.mjs`:
  - `export const CANARY_BRIDGE_SPAWN_PLACEHOLDER = "${CANARY_BRIDGE_SPAWN}";`
    with a `#9614/#9618` comment (SDK-internal dir, `join(homedir(),
    ".claude", "bridge-spawn")`, no env override);
  - `normalizeCapturedArgv` gains `bridgeSpawnRoot` opt; `norm()` maps the dir
    + subpaths; `prepDirs` conditional push (mirror the c4Staging block);
  - `substituteCanonicalArgv` gains `bridgeSpawn` (undefined → leave token for
    `hasUnsubstitutedPlaceholder` to catch);
  - `runReplay`: `mkdtempSync(join(tmpdir(), "canary-replay-bridge-spawn-"))`,
    pass to BOTH substitution calls;
  - `doCapture`: compute `bridgeSpawnRoot` via `join(homedir(), ".claude",
    "bridge-spawn")` (raw homedir — match the SDK byte-for-byte, no realpath),
    return it, `runCapture` forwards it;
  - emitted fixture `_comment` gains `${CANARY_BRIDGE_SPAWN}`;
  - add `homedir` to the `node:os` import.
- [ ] 2.2 `cd apps/web-platform && npx vitest run test/sandbox-canary.test.ts`
  → unit assertions green; committed-fixture census row still RED (expected).

## Phase 3 — premise correction re-land (#9570 revert, commit `cdab1153`)

- [ ] 3.1 `apps/web-platform/server/agent-runner-sandbox-config.ts:313` —
  replace `// \`--ro-bind / /\` (whole FS readable) with Bash (kb-search greps),
  so the` with the two-line form `// \`--ro-bind / /\` (whole FS readable) with
  Bash retained as the` / `// deny+escalate tripwire (kb-search itself is
  Read/Grep/Glob-only, #9559), so the` (verbatim from the reverted diff).

## Phase 4 — in-image re-capture + verify (creds-gated; merge-blocker)

- [ ] 4.1 From the worktree root, run
  `ANTHROPIC_API_KEY="$(doppler secrets get ANTHROPIC_API_KEY --project soleur --config ci --plain)" SANDBOX_CANARY_MODE=capture bash apps/web-platform/scripts/sandbox-canary-verify-in-image.sh`
  → verdict `captured`, `sdkVersion` `0.3.284`, fixture written back through
  the `/out` mount. If creds are absent: scripted API stand-in via
  `ANTHROPIC_BASE_URL` (the #9614 measurement shape) — scaffold only if needed.
  If a DIFFERENT `host_path`/`unrecognized_option` token surfaces, iterate
  deliberately (named placeholder or justified drop — never weaken the guard).
- [ ] 4.2 Same env with `SANDBOX_CANARY_MODE=verify` →
  `{"verdict":"verify_ok","reason":"ok"}`.
- [ ] 4.3 Review the regenerated fixture diff — capture-emitted bytes only;
  hand-edits are the #4932 trap. `droppedForDeterminism` counts may differ —
  audit-only, not diffed by `--verify`.

## Phase 5 — ADR-079 amendment + full green

- [ ] 5.1 Append the dated 2026-10-06 amendment to
  `knowledge-base/engineering/architecture/decisions/ADR-079-faithful-sandbox-canary-and-profile-redeploy-verification.md`
  (text in plan Phase 5.1); status stays `adopting`.
- [ ] 5.2 `cd apps/web-platform && npx vitest run test/sandbox-canary.test.ts`
  → fully green including the committed-fixture census.
- [ ] 5.3 Gate self-proof: on the PR, `sandbox-canary-capture-gate` reaches
  `canary --verify OK` without an `sdk-bump-verified:` trailer.
