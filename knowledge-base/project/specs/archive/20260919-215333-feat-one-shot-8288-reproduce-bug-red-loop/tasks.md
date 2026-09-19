# Tasks — feat-one-shot-8288-reproduce-bug-red-loop

Derived from `knowledge-base/project/plans/2026-09-19-feat-reproduce-bug-red-loop-tagged-instrumentation-bite-proof-plan.md`.
Phase numbering matches the plan's `## Implementation Phases`. Decision ids (D1–D10), guard ids (Guard 1–4) and revision ids (R1–R44) refer to that plan. **Read the plan's `## READ THIS FIRST` and `## Plan Review Revisions` before starting** — three structural reversals (R1 README/pointer written last; R2 default-mode self-cleanup on a failed bite; R11 zero test seams, fixture-owned stub `depcruise`) shape every task below.

> **Deepen-plan (R45–R72) applied 2026-09-19.** Read the plan's `## Deepen-Plan Reconciliation` and `## Precedent Diff` before starting. Paste-ready prose lives in `prose-drafts.md` beside this file. The load-bearing deltas: the stub `depcruise` branches on `--output-type` and probe presence (R45); the cleanup grep is `git grep -niE --untracked '\[DEBUG-[0-9a-f]{4}\]' -- . ':!knowledge-base/**/*.md'` (R47/R48); Guard 4's second predicate is call-form only (R49); `scripts/guard-vacuity-floor.test.sh` `PROMOTED_FILES` must list both skill-test suites (R50); the INT/TERM handler removes emitted artifacts (R51); `append_once` refuses symlinks (R52); `redact-engine.py` gates the Phase 8 comment (R56); no `--force` on `gh label create` (R65).

Constraints in force: no new skills; nothing named `wizard`; no `description:` frontmatter edits; `legacy-code-expert.md` is not edited; every sentinel in `constraint-scaffold` templates/dogfood untouched; all agent/skill references canonical (ADR-226); `MB` re-derived inline as `$(git merge-base origin/main HEAD)` in every command; do not close #8289 / #8290 / #8292.

## Phase 0: Preconditions and measurements (no product code)

- [x] 0.1 `cd /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-8288-reproduce-bug-red-loop && pwd && git merge-base origin/main HEAD`
- [x] 0.2 Re-fetch both peer files at `c55ee46073ed923f86ce59a5eb3b6d895095d1b7` via `gh api … --jq .content | base64 -d` into the scratchpad (source for imported paragraphs; corpus for AC2's shingle check)
- [x] 0.3 `grep -n 'reproduce-bug\|test-fix-loop\|legacy-code-expert' plugins/soleur/lib/workflow-fidelity.ts plugins/soleur/test/workflow-fidelity.test.ts .claude/workflow-transitions.json` → zero
- [x] 0.4 `time (cd apps/web-platform && bash scripts/constraint-gates.sh)`; record ×3 + one worktree pair for the PR body
- [x] 0.5 Re-run the one-hop bite measurement on a scratch fixture; copy the two `error <rule>: … <file>` lines verbatim for the stub outputs (S-real-minus-direct-transitive, S-direct-only, S-lines-rc0, S-bare-tokens)
- [x] 0.6 Baselines: `fixture-relative-assert.test.sh` + `fixture-dir-operand-assert.test.sh` green; `lint-trap-tempfile-ownership.py --check-highwater` exit 0; `bun test plugins/soleur/test/harness-parity-tree.test.ts` green; `bash scripts/guard-vacuity-floor.test.sh` green; `git ls-files -- . ':!knowledge-base' | wc -l` recorded; `parity.test.sh` prints `8 passed`; `wc -c plugins/soleur/skills/ship/SKILL.md` vs `skill-body-budget.json`
- [x] 0.7 `grep -n 'peer\|mattpocock\|8288' knowledge-base/product/roadmap.md` — decide the roadmap edit
- [x] 0.8 Re-derive the next free ADR ordinal across all `origin/*` refs (expected 230)

## Phase 1: RED — the suites before the guards

- [x] 1.1 Write `plugins/soleur/skills/constraint-scaffold/test/bite-proof.test.sh`
  - [x] 1.1.1 Fixture builder (Next.js-shaped `apps/web-platform`, `refs/remotes/origin/main`, `tsconfig.json` with `@/*`, `app/ components/ server/`; option to commit `CLAUDE.md` + `server/README.md`)
  - [x] 1.1.2 `make_stub_depcruise <dir> <clean-out> <clean-rc> <probe-out> <probe-rc> [<kill-pid-file>]` generating the three-branch stub from plan D6 (`baseline` → `[]`; `json` → `{"modules":[]}`; `err` → probe arm iff `components/__constraint_scaffold_bite_probe__/direct.tsx` exists in cwd, else clean arm; argv appended to `calls.log`; `exit 64` on unrecognised argv) + `dependency-cruiser/package.json` version `0.0.0-stub`; toolchain locate-or-install block placed AFTER the stub-driven segment (verbatim shape from `boundary.test.sh`, `EXIT INT TERM` trap)
  - [x] 1.1.3 Source pins: cleanup-list ↔ refuse-list; `trap '_wt_cleanup` line precedes `worktree add --detach` inside `with_detached_worktree`; rule-name ↔ template `name:`; `verdict_fail` stdout-before-`die`
  - [x] 1.1.4 Stub-driven (S-clean): C2 precondition 65; C3 pointer arms (a)/(b)/(c); C4 idempotency (README block + pointer, run twice); no-`@`; C-symlink (`CLAUDE.md -> elsewhere` → stdout warning, nothing written through the link, rc 0); C-tmpdir (`TMPDIR` inside the fixture → 69, no worktree); C6 commit + `--refresh-baseline` → rc 0, verdict, README/pointer byte-identical
  - [x] 1.1.5 Stub-driven (per-case stubs): S-direct-only → 72; S-lines-rc0 → 72; S-bare-tokens → 72; S-real-minus-direct-transitive → verdict rc 0; S-preprobe-violation → 74 naming the file; S-fail72 default → 72 + `git status --porcelain` empty + `scripts/`/`.github/workflows/` dirs gone; S-term → 143, `interrupted; removed:` line, one worktree, `git status --porcelain` empty, no mktemp dir
  - [x] 1.1.6 Real cases (behind the toolchain probe): C1 default full run (verdict `depcruise=` equals the real package version, never `0.0.0-stub`); C8 populated tree (harness d); C-e committed instructions files (harness e); C-warn (`severity: "warn"` copy of the config → 72); C-chmod (non-root: `chmod a-w .git` → 69, no mktemp dir)
  - [x] 1.1.7 Independent `cases`, conservation check, floors in the `[[ "$cases" -lt "$MIN" ]]` shape with `printf >&2; exit 1`; constants derived at commit time from `grep -c 'cases=\$((cases + 1))'` per segment and written into the comment beside them; trailer block copied verbatim from `boundary.test.sh` with `(N assertions)` suffix
- [x] 1.2 Write `plugins/soleur/test/debug-probe-residue.test.sh` (Guard 4): `$ROOT` (default own repo) and `MIN_POPULATION` (default 2 500) arguments; run from `git -C "$ROOT" rev-parse --show-toplevel`; predicate 1 `git grep -liE '\[DEBUG-[0-9a-f]{4}\]' -- . ':!knowledge-base/**/*.md'` (no `-I`); predicate 2 emit call-form only `(echo "|printf .|console\.(log|debug|warn|error)\(["'\`])SOLEUR_[A-Z_]*DEBUG` (must be 0 on today's tree — `permission-log.ts` reads the env flag, it does not emit); predicates first and findings printed before any floor; three-row `cases` counter + conservation + `MIN_CASES=3` + population floor, all direct
- [x] 1.3 Run both: every real and stub case RED against today's script; Guard 4 green on today's tree with rows 1/2/6/8 RED on synthesized repos; record in the PR body
- [x] 1.4 `bash scripts/lint-orphan-test-suites.sh` → `0 orphaned`

## Phase 2: GREEN — `constraint-scaffold.sh`

- [x] 2.1 Header exit matrix (+71/72/73/74, "no test seams" note), attribution comment (`# <!-- Inspired by mattpocock/skills/skills/in-progress/setup-ts-deep-modules/SKILL.md (MIT, Copyright (c) 2026 Matt Pocock). -->`), three-dirs precondition (65)
- [x] 2.2 `with_detached_worktree <ref> <fn>`: `WT="$(mktemp -d)"` on one line; refuse `TMPDIR` inside the repo (69); `trap '_wt_cleanup' EXIT` and `trap '_wt_cleanup; trap - EXIT; exit 143' INT TERM` BEFORE `worktree add`; `_wt_cleanup` in default mode also removes the six emitted artifacts + `rmdir`s the two dirs + prints `interrupted; removed: <list>`; cleared before return; refactor `capture_baseline_mergebase()` onto it (D6, R33, R51–R53, R59)
- [x] 2.3 `append_once <file> <marker> <content>` per plan D8 literal: `[[ -L ]]` refusal first, `grep -qF -- "$marker"` idempotency, `tail -c 1` newline guard, then append (R26, R52, R60); `emit_readme()` with inline `sed -e '1{/^<!-- Inspired by /d}' -e "s|__TARGET_DIR__|$TARGET_REL|g"`; `emit_pointer()` two arms (`$REPO_ROOT/CLAUDE.md` else `$REPO_ROOT/AGENTS.md`, created), informational prose, no `@`; failures after a successful bite are stdout warnings, not fatals (R55)
- [x] 2.4 `verdict_fail <code> <msg>`: stdout line, last 40 log lines on stdout, default-mode removal of `$CFG $RUNNER $WORKFLOW $FIXWORKFLOW_A $FIXWORKFLOW_B $BASELINE` + `rmdir` of the two dirs + `git worktree prune` note, then `die` (R2, R13, R54); the 65 precondition message also goes through the stdout path
- [x] 2.5 `prove_bite()` per D6 steps 1–7 (copy CFG/RUNNER/BASELINE + `node_modules` symlink; every runner call `rc=0; bash … >"$WT/bite-N.log" 2>&1 || rc=$?`; pass → 71/74 split; four-file inject; fail naming each rule on its own edge via `^\s*error <rule>: .*<file>` on the captured log; revert; pass → 73; ASCII verdict line with `depcruise=` read through the symlink chain)
- [x] 2.6 Wire both mode tails: refresh → `prove_bite; exit 0`; default → `prove_bite; emit_readme; emit_pointer; exit 0` (R1)
- [x] 2.7 Suite green; `bash -n` clean; execute Guard 1's 14 rows (1–12, 3b, 3c) and harness rows a–g, reverting each, recording each

## Phase 3: Templates, dogfood, parity

- [x] 3.1 Write `plugins/soleur/skills/constraint-scaffold/references/boundary-readme.template` (D8 content: boundary, two rule names, `import type`, how to run, three-dirs + `@/*` requirement, what the founder sees on a trip — red check + ADR-074 draft PR, install-time proof + re-prove via `--refresh-baseline`, agent-owns-recovery; attribution comment on line 1; no peer sentence)
- [x] 3.2 Place `apps/web-platform/server/README.md` = emitter transform; append the pointer line to repo-root `CLAUDE.md` (plain prose, `<!-- constraint-scaffold:pointer -->`, no `@`)
- [x] 3.3 `parity.test.sh`: rows 7–8 (`-s` pre-checks; row 7 `diff` + `grep -cF` pin of the strip expression in the script; row 8 marker `== 1`, path present, no `@apps/`); `boundary.test.sh`'s trailer block copied verbatim with `passes`/`fails` and `MIN_ROWS=10`; trailer `parity.test.sh: 10 passed, 0 failed (10 rows)`; execute Guard 2 rows 1–8 + harness
- [x] 3.4 `bash scripts/markdown-lint.sh` clean on the README; `bash .github/scripts/test/test-no-at-mention-credfile-footgun.sh` clean
- [x] 3.5 `scripts/guard-vacuity-floor.test.sh`: add `plugins/soleur/skills/constraint-scaffold/test/bite-proof\.test\.sh` and `…/parity\.test\.sh` to the `PROMOTED_FILES` regex (R50); `bash scripts/guard-vacuity-floor.test.sh` green with the deferred ledger unchanged

## Phase 4: Prose — `reproduce-bug`, `test-fix-loop`, `constraint-scaffold`, `ship`

- [x] 4.1 `plugins/soleur/skills/reproduce-bug/SKILL.md` per D1–D5
  - [x] 4.1.1 Attribution comment strictly between the frontmatter close and `<!-- soleur-cloud-mode:start -->` (R27)
  - [x] 4.1.2 Phase 1: replace the "Keep investigating…" sentence only
  - [x] 4.1.3 Phase 2 (new), from `prose-drafts.md` §(1): decision-first — Redact (extended: fixture-from-trace synthesized/redacted; Phase 8 body + `--cmd` through `redact-engine.py`); four checkboxes + hard gate; "cannot build a loop" stop with ordered defaults (instrumentation → non-shell environment access → agent-redacted captured artifact last, never attached, deleted after) and the Playwright-before-declaring rule; then `### Ways to construct one` (10 rungs; rung 5 Soleur clause; rung 10 → `soleur:agent-browser`, NOT peer prose); tighten; non-deterministic branch; nothing posted before Phase 8
  - [x] 4.1.4 Phase 3 (was 2): byte-preserved except the rung-4 sentence and the dev-server line (no `inform user`, no `bin/dev`); `redact-a11y-snapshot.py` reference verbatim
  - [x] 4.1.5 Phase 4 (new) reproduce + minimise; Phase 5 (new) hypotheses with Discriminator column, founder render "what else you'd see if this is it", in-turn decision (no question tool), headless audit line; Phase 6 (new) instrument: minimal marker form (spelling, `printf '[DEBUG-%04x]\n' $((RANDOM % 65536))`, decision rule, payload rule R58, D4 command with `--untracked`, cite ADR-230) + perf branch
  - [x] 4.1.6 Phase 7 seam verdict bullet incl. `gh label create "action-required" --description "Needs a human action" --color "B60205" 2>/dev/null || true` (no `--force`) + `--add-label` and the digest-scope sentence; Phase 8 single comment (body through `redact-engine.py`, exit 0 before posting) with items 6–8 and the post-Phase-9 `soleur:test-fix-loop --cmd '…' --max 5` hand-off; Phase 9 checklist (shape grep, harness deleted, no production payload in committed loop script/fixture, hypothesis stated, loop script committed)
- [x] 4.2 `plugins/soleur/skills/test-fix-loop/SKILL.md`: attribution comment (same placement); Phase 0 `--cmd` / `--max` form + hand-off sentence; §4 D4 command before the checkpoint commit and before the success-row `git add -A`; Recommendation routing to `soleur:engineering:review:legacy-code-expert`; Key Principles bullet citing ADR-230
- [x] 4.3 `plugins/soleur/skills/constraint-scaffold/SKILL.md` (attribution; `## Bite-proof (every run)`; emits table; usage; self-tests); `plugins/soleur/skills/ship/SKILL.md` one bullet under `## Phase 5: Final Checklist` with the D4 command
- [x] 4.4 `bun test plugins/soleur/test/harness-parity-tree.test.ts`, `components.test.ts`, `devin-cloud-mode.test.ts` green; `cd apps/web-platform && ./node_modules/.bin/vitest run test/git-lock-marker-telemetry.test.ts test/plugin-root-anchoring.test.ts` green
- [x] 4.5 Execute Guard 3 rows 1–5 on a scratch branch and Guard 4 rows 1–9 + harness; record

## Phase 5: Repo-global ratchets (BEFORE the review panel — operator-mandated; existing gates, run locally)

- [x] 5.1 `bash scripts/guard-vacuity-floor.test.sh` exit 0 (both skill-test suites promoted per 3.5; new floors in `FIRES_LIST`; ledger at `MAX_DEFERRED`)
- [x] 5.2 `python3 scripts/lint-trap-tempfile-ownership.py --changed` exit 0; `python3 scripts/lint-trap-tempfile-ownership.py --check-highwater` exit 0
- [x] 5.3 `python3 scripts/lint-rule-bodies.py --check --base "$(git merge-base origin/main HEAD)"` exit 0
- [x] 5.4 `bash plugins/soleur/test/fixture-relative-assert.test.sh` — if RED: `--write-baseline`, `diff` old vs new, only rows for the four edited files moved (else rebase first), commit the baseline **in the same commit** as the operand edits with the per-file delta; re-run green. Same for `fixture-dir-operand-assert.test.sh`
- [x] 5.5 `python3 scripts/lint-skill-body-budget.py --base "$(git merge-base origin/main HEAD)"` exit 0 (`ship` under 274 000)
- [x] 5.6 `bash scripts/lint-orphan-test-suites.sh` → `0 orphaned`; `bash plugins/soleur/skills/constraint-scaffold/test/boundary.test.sh` green
- [x] 5.7 First in-target proof: clean tree, `apps/web-platform/node_modules` installed → `bash plugins/soleur/skills/constraint-scaffold/scripts/constraint-scaffold.sh --refresh-baseline` prints the verdict line, exit 0, `git status --short` empty, `git worktree list` unchanged; paste the verdict line into the PR body

## Phase 6: ADRs, NOTICE, docs, evidence

- [x] 6.1 `soleur:architecture`: ADR-071 amendment `## Amendment 2026-09-19 (#8288) — …` with consequences (a)–(f) and the opt-out-flag rejected alternative; ADR-230 (provisional) with the single normative two-class table; sweep the ordinal into plan, `tasks.md`, both SKILL.md citations if it moved
- [x] 6.2 `plugins/soleur/NOTICE` › `mattpocock/skills`: `Used in:` + `Portions adopted:` paragraph; run `git diff "$(git merge-base origin/main HEAD)" | grep -n 'Matt Pocock\|mattpocock'` (nothing under `apps/web-platform/`); run the AC2 8-word shingle check over the emitted README against both peer blobs → 0
- [x] 6.3 `bash scripts/sync-readme-counts.sh` leaves no diff
- [x] 6.4 `knowledge-base/project/specs/feat-one-shot-8288-reproduce-bug-red-loop/decision-challenges.md` — already written by plan; append anything new from the work phase
- [ ] 6.5 PR body: one line per guard (`Guard N: k/k RED, h/h harness as specified`), ratchet trailers, RED-run evidence (1.3), bite cost (0.4), the 5.7 verdict line, the CMO changelog line for `soleur:feature-tweet`; `Closes #8288`; no `Closes` for #8289/#8290/#8292

## Phase 7: Acceptance

- [ ] 7.1 Walk AC1–AC23 with the exact commands in the plan; every "gate green" AC runs the gate's own invocation
- [x] 7.2 (filed during review, so SKILL.md could cite Deferral 3 by number: #8379 generator floor, #8380 CI-time bite, #8381 hosted HALT marker) Deferrals 1–3 filed with `deferred-scope-out` + re-evaluation criteria (3 = the mirrored-not-paged `SOLEUR_CONSTRAINT_SCAFFOLD_HALT` for the hosted surface); numbers on the `Filed:` line
