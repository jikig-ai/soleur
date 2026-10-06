# Tasks — fix: safe-bash git-branch tightening + kb-search support-persona path (#9555, #9559)

Plan: `knowledge-base/project/plans/2026-10-06-fix-safe-bash-git-branch-support-kb-search-plan.md`
Branch: `feat-one-shot-9555-9559-safe-bash-kb-search`

## Phase 1 — Fix A: `git branch` read-only arms (#9555), tests first

- [ ] 1.1 RED: add the deny battery to `apps/web-platform/test/safe-bash.test.ts`
  — new `describe` asserting `isBashCommandSafe(...) === false` for
  `git branch foo`, `git branch foo main`, `-d`, `-D`, `--delete`, `-m`,
  `-M`, `--move`, `-c`, `-C`, `-f`, `-q foo`, `-u`/`--set-upstream-to`,
  `--unset-upstream`, `--edit-description`, `git branch --list -d`,
  `git branch --list foo -D`, `git branch --list ../x`, and
  `git status && git branch -d x` (chain).
- [ ] 1.2 RED: add allow cases — `git branch`, `-a`, `-r`, `-v`, `-vv`,
  `-av`, `--list`, `--list feat`, `--show-current`, `--merged main`,
  `--contains HEAD~2`, `--no-merged main`, `--points-at HEAD`,
  `--sort=-committerdate`, `--ignore-case --list x`.
- [ ] 1.3 RED: add `git branch -d x` / `git branch feat-x` to the
  not-auto-approved (falls-through-to-review-gate) cases in
  `apps/web-platform/test/permission-callback-safe-bash.test.ts`; keep
  `"git branch"` in `SAFE_COMMANDS`.
- [ ] 1.4 GREEN: replace the `git branch` entry at
  `apps/web-platform/server/safe-bash.ts:131` with
  `GIT_BRANCH_READ_FLAG` + the two arms exactly as specified in the plan's
  Fix A block (closed flag set, `-q` excluded, args gated behind a list
  flag + `(?!-)` lookahead).
- [ ] 1.5 Verify: `cd apps/web-platform && ./node_modules/.bin/vitest run
  test/safe-bash.test.ts test/permission-callback-safe-bash.test.ts`
  green; mutation spot-check via `bun -e` import probe.

## Phase 2 — Fix B: kb-search support-persona tool path (#9559, option b)

- [ ] 2.1 `plugins/soleur/skills/kb-search/SKILL.md`: add the
  support-persona section at the top of `## Execution` (before Phase 0)
  per the plan's quoted block + phase-mapping table. Keep
  `<!-- stage-2-paraphrase-union-v1 -->` and the `SENSITIVE_QUERY_REGEX`
  literal byte-identical.
- [ ] 2.2 `apps/web-platform/server/support-directive.ts`: add one
  directive line — kb-search runs via Read/Grep/Glob only, no shell in
  this chat; correct the stale comments at :16-17 and :51-52.
- [ ] 2.3 `apps/web-platform/server/cc-dispatcher.ts`: correct the stale
  "kb-search shells out" comment (~:2879).
- [ ] 2.4 `apps/web-platform/test/support-directive.test.ts`: extend
  directive assertions to pin the tool-only sentence (regex
  `/Read.*Grep.*Glob|no shell/i`); rename the stale test title at :28
  (`"…KEEPS Bash (kb-search shells out)"` — premise falsified by #9559);
  existing assertions unchanged.
- [ ] 2.5 Verify: `cd apps/web-platform && ./node_modules/.bin/vitest run
  test/support-directive.test.ts` green; `bash
  plugins/soleur/test/kb-search-lockstep.test.sh` green.

## Phase 3 — Guard 2 drift test

- [ ] 3.1 Create `plugins/soleur/test/kb-search-support-path.test.sh`:
  assert (i) SKILL.md support-persona marker present, (ii) no
  ` ```bash ` fenced block inside the support section (anchor on the
  fenced form — prose legitimately names Bash), (iii) corpus files
  `plugins/soleur/knowledge-base/{INDEX.md,kb-tags.txt,kb-categories.txt}`
  exist non-empty. Owning EXIT trap BEFORE `source test-helpers.sh`;
  pass-count floor ≥3; negative rows carry positive controls.
- [ ] 3.2 Verify: `bash plugins/soleur/test/kb-search-support-path.test.sh`
  exits 0; confirm `scripts/test-all.sh` discovers it
  (`plugins/soleur/test/*.test.sh` glob, test-all.sh:97).

## Phase 4 — ADR-113 amendment + C4 model update

- [ ] 4.1 `knowledge-base/engineering/architecture/decisions/
  ADR-113-support-persona-scoped-concierge.md`: append amendment noting
  the 5(c) premise was falsified by #9559 — the allowlist never admitted
  kb-search's shell-outs; support path is Read/Grep/Glob-only.
- [ ] 4.2 `knowledge-base/engineering/architecture/diagrams/model.c4`:
  add `supportUser = actor "End User (Support Chat)"` `#external` + edge
  `supportUser -> platform.webapp` (app-help questions via support bubble).
- [ ] 4.3 `knowledge-base/engineering/architecture/diagrams/views.c4`:
  add `supportUser` to `view context` include list (both edge endpoints
  must be in-view — #7332 rule).
- [ ] 4.4 Verify: `cd apps/web-platform && ./node_modules/.bin/vitest run
  test/c4-code-syntax.test.ts test/c4-render.test.ts` green.

## Phase 5 — Final verification

- [ ] 5.1 Full file-scoped vitest set green (Phases 1.5 + 2.5 + 4.4 files).
- [ ] 5.2 `bun -e` probe: `isBashCommandSafe("git branch -d foo") ===
  false`, `("git branch --show-current") === true`,
  `("git branch foo") === false`, `("git status && git branch -d x")
  === false`.
- [ ] 5.3 `npx markdownlint-cli2` clean on every `*.md` touched.
- [ ] 5.4 `python3 scripts/lint-guard-contract.py` (if it takes the plans
  dir / diff scope — run its documented invocation) green.
- [ ] 5.5 PR body: `Closes #9555` + `Closes #9559`, `## Changelog`
  section, `semver:patch` label.
