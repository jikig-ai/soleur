# Tasks — fix #9127: reaper archive persistence for tracked KB files

lane: procedural
Plan: `knowledge-base/project/plans/2026-09-28-fix-reaper-archive-tracked-kb-persistence-plan.md`

Locate all constructs by content anchor (`archive_kb_files`, `cleanup_merged_worktrees`,
`SOLEUR-GUARD-MAINRESET`, `sync_bare_files`, `ensure_worktree_identity`,
`_sanitize_marker_field`, `headless_or_stderr`), never by line number — the script is ~3.9k
lines and drifts.

## Phase 1 — Failing tests first (TDD per `cq-write-failing-tests-before`)

- [ ] 1.1 Create `plugins/soleur/skills/git-worktree/test/reap-archive-persistence.test.sh`
      following the sibling pattern (`mktemp` fixture repo, `cdx` containment guard,
      GIT_DIR tripwire, EXIT trap placed BEFORE any `source` of helpers per
      `lint-trap-tempfile-ownership` and the #8644 sharp edge).
- [ ] 1.2 Fixture A — non-bare clone on `main`, tracked spec dir for a merged branch:
      run `cleanup-merged`, then `git reset --hard HEAD`; assert live dir still tracked+on-disk,
      no archive copy exists, `SOLEUR_REAP_ARCHIVE_DEFERRED` was emitted, tree clean. Run the
      pair a second time (next-session arm).
- [ ] 1.3 Fixture B — clone on a feature branch, tracked spec dir for a merged OTHER branch:
      run `cleanup-merged`; assert a `chore(archive-kb)` commit exists on the feature branch,
      `git show --name-only` of it equals exactly the archive-move path set, and a pre-staged
      unrelated file is still staged-and-uncommitted (AC5 pin).
- [ ] 1.4 Fixture C — untracked spec dir: plain `mv` to `archive/` still occurs; no-clobber
      `[[ -e ]]` arm preserved.
- [ ] 1.5 Fixture D — bare repo with HEAD-tracked spec path (stale mirror): DEFERRED emitted,
      no disk churn of the mirror.
- [ ] 1.6 Fixture precondition asserts: the "tracked" fixture file IS `git ls-files`-tracked
      before the reap (vacuous-fixture fail-loud — guard matrix row 6).
- [ ] 1.7 Census assert: every `mv`/`git mv` of KB artifacts in `worktree-manager.sh` routes
      through the single persistence helper (assembly chokepoint — guard matrix row 5).
- [ ] 1.8 Register the suite: declared-edge array
      `AFFECTED_PLUGINS_SOLEUR_SKILLS_GIT_WORKTREE_TEST_REAP_ARCHIVE_PERSISTENCE_TEST_SH_PATHS`
      in `scripts/lib/test-affected-paths.sh` (subject: `worktree-manager.sh` + this plan +
      the test file + `test-affected-paths.sh` itself); row in
      `scripts/suite-shard-legs.tsv` (sibling git-worktree suites sit on legs 2 and 7).

## Phase 2 — Persistence helper + dispatch (contract before consumers)

- [ ] 2.1 Once-per-run committability probe before the reap loop in
      `cleanup_merged_worktrees`: `current_branch=$(git -C "$GIT_ROOT" rev-parse --abbrev-ref
      HEAD || true)`; committable iff `IS_BARE != true` AND branch ∉ {main, master, HEAD, empty}.
- [ ] 2.2 Single persistence helper (the chokepoint): given an artifact path — classify
      tracked (`git ls-files --error-unmatch` on a worktree; `git ls-tree HEAD` for bare), then
      `git mv` when tracked+committable, DEFERRED sentinel when tracked+not-committable, plain
      `mv` when untracked. Preserve the existing `[[ -e archive_path ]]` no-clobber guard.
- [ ] 2.3 Route the spec-dir block AND both `archive_kb_files` call sites (brainstorms, plans)
      through the helper — three sites, one rule.
- [ ] 2.4 Per-file tracked classification inside `archive_kb_files`'s glob loop — a batch can
      be mixed tracked/untracked.
- [ ] 2.5 After each reaped branch's moves on a committable checkout: `ensure_worktree_identity`,
      then pathspec-scoped `git commit -m "chore(archive-kb): persist reap archive for <slug>"
      -- <moved paths>` inside an `if …; then … else` rc capture (`set -e` discipline). Emit
      `SOLEUR_REAP_ARCHIVE_COMMITTED slug=<slug>` on success; on failure leave the staged
      payload and emit `SOLEUR_REAP_ARCHIVE_STAGED slug=<slug>` — never `LEFTHOOK=0`.
- [ ] 2.6 On the non-committable arm emit `SOLEUR_REAP_ARCHIVE_DEFERRED
      slug=<sanitized> reason=<main-checkout|detached|bare>` (sanitize via
      `_sanitize_marker_field`; stdout, not stderr — agent-visible convention).
- [ ] 2.7 MAINRESET block untouched: no dirty-check reclassification — no reap dirt is
      produced on main anymore (option (b) deliberately not implemented; plan §Why-not-b).

## Phase 3 — Dedup the three stranded spec dirs

- [ ] 3.1 `git mv` live-only files into each archive twin: `tasks.md` + `upstream-asks.md` →
      `specs/archive/20260917-155554-feat-devin-upstream-asks-posture/`;
      `decision-challenges.md` + `phase-0-measurement.md` →
      `specs/archive/20260909-173031-feat-one-shot-7946-7947-sentry-org-token-and-snapshot-redaction/`;
      `migration-checklist.md` → `specs/archive/20260915-173141-feat-pluggable-web-agent-engines/`.
- [ ] 3.2 `git rm -r` the three live dirs:
      `specs/feat-devin-upstream-asks-posture`,
      `specs/feat-one-shot-7946-7947-sentry-org-token-and-snapshot-redaction`,
      `specs/feat-pluggable-web-agent-engines`.
- [ ] 3.3 Verify: `comm -12` of live feat-* names vs stamp-stripped archive names excludes the
      three slugs; `git ls-files knowledge-base/project/specs/` shows each spec only under
      `archive/`; `diff -r` of each merged twin covers the union.

## Phase 4 — Docs, ADR, verification

- [ ] 4.1 `plugins/soleur/skills/git-worktree/SKILL.md`: document the commit-path-gated
      persistence rule + `SOLEUR_REAP_ARCHIVE_{COMMITTED,STAGED,DEFERRED}` markers in the
      reaper sections; body only, `description:` frontmatter untouched.
- [ ] 4.2 Author `knowledge-base/engineering/architecture/decisions/ADR-257-*.md`
      (provisional ordinal — re-verify next-free against `origin/main` at author time and let
      `soleur:ship`'s collision gate re-check; on renumber sweep this plan's ADR section +
      AC8 + this file).
- [ ] 4.3 Run `bash plugins/soleur/skills/git-worktree/test/reap-archive-persistence.test.sh`
      → 0 failed; run the four sibling git-worktree suites → 0 failed; run touched shards per
      `soleur:work`'s Touched-Shard Exit Gate.
- [ ] 4.4 Run `bash scripts/followthroughs/reaper-archive-stranded-spec-9113.sh` in this
      worktree → `twin count changed` / exit 0 once dedup is applied.
- [ ] 4.5 PR body: `Closes #9127` on its own line (the fix lands atomically with this PR — the
      post-merge follow-through probe is the verification, not the closure mechanism).
