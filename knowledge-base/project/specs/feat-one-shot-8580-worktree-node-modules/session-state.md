# Session State

## Plan Phase

- Plan file: knowledge-base/project/plans/2026-09-22-fix-worktree-node-modules-hook-fallback-plan.md
- Status: plan written; deepen-plan inline pass COMPLETE (Enhancement Summary +
  Deepen-Plan Revisions R1–R7 added; tasks.md carries the corrections).

## Work Phase

- Status: IMPLEMENTED (Tier B fan-out, three file-disjoint groups) — committed
  `9092b83e71`, pushed, PR #8581 marked ready.
- Product files touched: `scripts/markdown-lint.sh`, `scripts/test-all.sh`,
  `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`,
  `lefthook.yml`, `scripts/hooks/pre-push` + tests and docs (tasks.md has the
  checklist; all rows [x]).
- Verification before review: `markdown-lint.test.sh` 39/39,
  `worktree-manager-hook-deps.test.sh` 13/13, real-repo e2e sibling
  resolution proven (`1 file(s) clean`).

## Ship Phase (in progress)

- Review: complete — trailer `f924150e42` (degraded 9/10 agents,
  `performance-oracle` absent; threshold `none` → non-blocking). QA: skipped
  per skill (T-rows covered by mutation suite; no browser/API surface).
  Compound: learning written (`2026-09-22-verify-by-manifest-not-by-executing-the-candidate.md`).
- Preflight: all checks PASS or path-gated SKIP; advisor consult verdict
  "complete, no blockers". PR #8581 synced with `origin/main` (`8d5c10df2d`),
  `semver:patch` label set.
- CI on synced head: `test-bun` + `test-webplat (1/2)` = pre-existing #8586
  drift (`scheduled-actions-queue-health`). `test-scripts (1/3)` had ONE real
  regression from this branch: the new `apps/web-platform/node_modules`
  precondition `exit 2`d the coverage-notice suite's recorder-mode sandbox
  arms on dep-less shards (69 fails, locally invisible — this worktree HAS
  the install). Fixed by exempting `SANDBOX_RECORD` arms (they start no
  suite, resolve no binary — same justification as `_ENUMERATE`); verified
  127/127 with `node_modules` absent.
- Local full battery: 484/496 (7 failed, 5 relevance-skips). Failures:
  `fixture-env-adoption` was OURS (new suite counted in the unconverted
  ratchet — fixed via `git_fixture_env`, `a2cd6e9772`, 13/13 + 26/26 green);
  `fixture-relative-assert`, `sentry-monitors-audit`, `c4-count-parity` are
  the #8578/#8586 `scheduled-actions-queue-health` drift (pre-existing,
  tracked); `go-session-gates` H3 needs a claude-CLI headless harness
  (environmental, diff-independent); `plugins/soleur` is the group aggregate.
- Merge: required `test` aggregate is red on the pre-existing shard failures
  → blocked until #8588 (#8586 fix) lands on main, then sync + merge.

## Review Phase (complete)

- Classification: `code`, design-risk yes (new sibling-binary resolution
  mechanism). Design-validity pass: code-simplicity + architecture both
  returned DESIGN SOUND. Full panel returned; findings are being fixed
  inline — see the diff for: manifest-read candidate verification (no
  exec-before-verify), shared `engine_version_for` (nearest-scope-first on
  both arms), distinct-version lockfile pin (fail-closed on ambiguity),
  `--path-format=absolute` git-common-dir, GIT_* scrub, absolute `--prefix`
  recovery commands, `npx tsc`/`npx vitest` pinned to local `.bin`, T7/T8
  never-executed + symlink-escape rows.

### Errors

None

### Decisions

- Fix lives at the consumption point (`scripts/markdown-lint.sh`), not any
  creation path: bypassing creators (agent harness `.claude/worktrees/agent-*`,
  ship/review `git worktree add --detach` recipes, manual adds) are
  unenumerable, and the only hook point (`post-checkout` fires on `git worktree
  add`) lives in the untracked shared `.git/hooks/` — unshippable.
- Sibling resolution is pin-verified: CLI `--version` == package.json pin AND
  engine package version == package-lock.json pin, both read from the
  consuming worktree. Local present-but-wrong still dies (no silent detour);
  no `npx`/PATH/network fallback (#7927 preserved).
- #2398 (vitest) gets a fail-fast precondition in test-all.sh, NOT sibling
  execution: `vitest.config.ts` imports resolve relative to the config file's
  own directory, so a sibling binary cannot satisfy app deps.
- `install_deps()` gains a hook-required-binaries enumeration line so
  warn-and-continue failures become visible at create time.
- ADR-009 gets a consequence-note amendment (read-only cross-worktree dep
  reads); no C4 change (no modeled element covers dev-host dep resolution).
- Detail level: MORE (standard). `brand_survival_threshold: none` — dev
  tooling, no sensitive paths.
- No external research needed — repo-internal machinery; all facts measured
  against the live checkout on 2026-09-22.

### Components Invoked

- `soleur:plan` (inline in this harness — no Skill tool surface) — plan file,
  research, gates, tasks.md
- `soleur:deepen-plan` (inline — halt gates + verify-the-negative greps +
  precedent diffs) — produced Enhancement Summary + Revisions R1–R7

### Deepen-Plan Outcome (2026-09-22)

Seven revisions folded in (see plan "Deepen-Plan Revisions"): R1 post-checkout
correction, R2 `npx tsc` same-class surface, R3 M7a token constraint, R4
SIGPIPE-safe porcelain parse precedent, R5 committed-symlink test fixture fix +
T1b row, R6 nearest-scope-first engine probe, R7 bare-block no-filter rule.
tasks.md phases 1–3 updated to carry each constraint.
