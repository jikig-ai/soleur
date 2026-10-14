# feat-devin-plugin-parity — tasks

## Phase 1 — Manifest and wrappers
- [x] Add `skills: ["./skills", "./devin/skills"]` to `.devin-plugin/plugin.json`.
- [x] Create `devin/skills/{go,help,sync}/SKILL.md` wrappers linking to canonical commands.
- [x] Update `plugins/soleur/hooks/hooks.json` to run `devin-session-start.sh` on SessionStart.

## Phase 2 — Local-dev setup and project config
- [x] Create `.devin/config.json` registering SessionStart and PreToolUse hooks.
- [x] Create `scripts/setup-devin.sh` to install the local plugin and project config idempotently.
- [x] Add `.devin/*` with `!.devin/config.json` to `.gitignore`.

## Phase 3 — Tests
- [x] Create `plugins/soleur/test/devin-plugin.test.ts` mirroring `codex-plugin.test.ts`.
- [x] Create `plugins/soleur/test/devin-setup.test.ts` mirroring `codex-setup.test.ts`.

## Phase 4 — Verification
- [x] Run targeted harness tests (`devin-*`, `codex-*`, `grok-*`) — all pass.
- [x] Validate JSON and bash syntax.

## Phase 5 — Documentation
- [x] Update root `README.md` and `plugins/soleur/README.md` Devin sections to reference `scripts/setup-devin.sh`.

## Phase 6 — Ship
- [ ] Open PR, attach semver label, run `/ship` checks.
