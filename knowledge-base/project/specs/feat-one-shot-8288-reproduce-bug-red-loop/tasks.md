# Tasks — feat-one-shot-8288-reproduce-bug-red-loop

Derived from `knowledge-base/project/plans/2026-09-19-feat-reproduce-bug-red-loop-tagged-instrumentation-bite-proof-plan.md`.
Phase numbering matches the plan's `## Implementation Phases`. Decision ids (D1–D10), guard ids (Guard 1–4) and revision ids (R1–R44) refer to that plan. **Read the plan's `## READ THIS FIRST` and `## Plan Review Revisions` before starting** — three structural reversals (R1 README/pointer written last; R2 default-mode self-cleanup on a failed bite; R11 zero test seams, fixture-owned stub `depcruise`) shape every task below.

Constraints in force: no new skills; nothing named `wizard`; no `description:` frontmatter edits; `legacy-code-expert.md` is not edited; every sentinel in `constraint-scaffold` templates/dogfood untouched; all agent/skill references canonical (ADR-226); `MB` re-derived inline as `$(git merge-base origin/main HEAD)` in every command; do not close #8289 / #8290 / #8292.

## Phase 0: Preconditions and measurements (no product code)

- [ ] 0.1 `cd /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-8288-reproduce-bug-red-loop && pwd && git merge-base origin/main HEAD`
- [ ] 0.2 Re-fetch both peer files at `c55ee46073ed923f86ce59a5eb3b6d895095d1b7` via `gh api … --jq .content | base64 -d` into the scratchpad (source for imported paragraphs; corpus for AC2's shingle check)
- [ ] 0.3 `grep -n 'reproduce-bug\|test-fix-loop\|legacy-code-expert' plugins/soleur/lib/workflow-fidelity.ts plugins/soleur/test/workflow-fidelity.test.ts .claude/workflow-transitions.json` → zero
- [ ] 0.4 `time (cd apps/web-platform && bash scripts/constraint-gates.sh)`; record ×3 + one worktree pair for the PR body
- [ ] 0.5 Re-run the one-hop bite measurement on a scratch fixture; copy the two `error <rule>: … <file>` lines verbatim for the stub outputs (S-real-minus-direct-transitive, S-direct-only, S-lines-rc0, S-bare-tokens)
- [ ] 0.6 Baselines: `fixture-relative-assert.test.sh` + `fixture-dir-operand-assert.test.sh` green; `lint-trap-tempfile-ownership.py --check-highwater` exit 0; `bun test plugins/soleur/test/harness-parity-tree.test.ts` green; `bash scripts/guard-vacuity-floor.test.sh` green; `git ls-files -- . ':!knowledge-base' | wc -l` recorded; `parity.test.sh` prints `8 passed`; `wc -c plugins/soleur/skills/ship/SKILL.md` vs `skill-body-budget.json`
- [ ] 0.7 `grep -n 'peer\|mattpocock\|8288' knowledge-base/product/roadmap.md` — decide the roadmap edit
- [ ] 0.8 Re-derive the next free ADR ordinal across all `origin/*` refs (expected 230)

## Phase 1: RED — the suites before the guards

- [ ] 1.1 Write `plugins/soleur/skills/constraint-scaffold/test/bite-proof.test.sh`
  - [ ] 1.1.1 Fixture builder (Next.js-shaped `apps/web-platform`, `refs/remotes/origin/main`, `tsconfig.json` with `@/*`, `app/ components/ server/`; option to commit `CLAUDE.md` + `server/README.md`)
  - [ ] 1.1.2 `make_stub_depcruise <dir> <stdout-file> <rc> [<kill-pid-file>]` + `dependency-cruiser/package.json` version; toolchain locate-or-install block (verbatim shape from `boundary.test.sh`, `EXIT INT TERM` trap)
  - [ ] 1.1.3 Toolchain-free cases: C2 precondition 65; C3 pointer arms (a)/(b)/(c); C4 idempotency (README block + pointer); no-`@`; cleanup-list ↔ refuse-list pin; `trap`-before-`worktree add` shape pin; rule-name ↔ template `name:` pin
  - [ ] 1.1.4 Stub cases: S-direct-only → 72; S-lines-rc0 → 72; S-bare-tokens → 72; S-real-minus-direct-transitive → verdict rc 0; S-preprobe-violation → 74; S-fail72 default mode → 72 + `git status --porcelain` empty; S-term → exit 143, clean `git worktree list`, no leftover mktemp dir; C6 commit + `--refresh-baseline` → rc 0, README/pointer untouched
  - [ ] 1.1.5 Real cases (behind the toolchain probe): C1 default full run; C8 populated tree (Guard 1 harness d); C-e committed instructions files (harness e)
  - [ ] 1.1.6 Independent `cases`, conservation check, `TOOLCHAIN_FREE_MIN_ASSERTIONS=22`, `MIN_ASSERTIONS=31` in the `[[ "$cases" -lt "$MIN" ]]` shape, each `printf >&2; exit 1`; comment that counts move with the cases in the same commit
- [ ] 1.2 Write `plugins/soleur/test/debug-probe-residue.test.sh` (Guard 4): `$ROOT` argument (default own repo), two predicates (`\[DEBUG-[0-9a-f]{4}\]` case-insensitive with `-I`; `SOLEUR_[A-Z_]*DEBUG`), population floor 2 500 reported directly
- [ ] 1.3 Run both: every real and stub case RED against today's script; Guard 4 green on today's tree with rows 1/2/6/8 RED on synthesized repos; record in the PR body
- [ ] 1.4 `bash scripts/lint-orphan-test-suites.sh` → `0 orphaned`

## Phase 2: GREEN — `constraint-scaffold.sh`

- [ ] 2.1 Header exit matrix (+71/72/73/74, "no test seams" note), attribution comment (`# <!-- Inspired by mattpocock/skills/skills/in-progress/setup-ts-deep-modules/SKILL.md (MIT, Copyright (c) 2026 Matt Pocock). -->`), three-dirs precondition (65)
- [ ] 2.2 `with_detached_worktree <ref> <fn>` (mktemp -d; `EXIT` trap + `INT TERM` trap exiting 143, installed before `worktree add`; cleared before return); refactor `capture_baseline_mergebase()` onto it (D6, R33)
- [ ] 2.3 `append_once <file> <marker> <content>` with trailing-newline guard (R26); `emit_readme()` with inline `sed -e '1{/^<!-- Inspired by /d}' -e "s|__TARGET_DIR__|$TARGET_REL|g"`; `emit_pointer()` two arms (`$REPO_ROOT/CLAUDE.md` else `$REPO_ROOT/AGENTS.md`, created), plain prose, no `@`
- [ ] 2.4 `verdict_fail <code> <msg>`: stdout line, last 40 log lines on stdout, default-mode removal of `$CFG $RUNNER $WORKFLOW $FIXWORKFLOW_A $FIXWORKFLOW_B $BASELINE`, then `die` (R2, R13)
- [ ] 2.5 `prove_bite()` per D6 steps 1–7 (copy CFG/RUNNER/BASELINE + `node_modules` symlink; pass → 71/74 split; four-file inject; fail naming each rule on its own edge via `^\s*error <rule>: .*<file>` on the captured `2>&1` log; revert; pass → 73; ASCII verdict line with `depcruise=`)
- [ ] 2.6 Wire both mode tails: refresh → `prove_bite; exit 0`; default → `prove_bite; emit_readme; emit_pointer; exit 0` (R1)
- [ ] 2.7 Suite green; `bash -n` clean; execute Guard 1 rows 1–12 (incl. 3b/3c) and harness rows a–e, reverting each, recording each

## Phase 3: Templates, dogfood, parity

- [ ] 3.1 Write `plugins/soleur/skills/constraint-scaffold/references/boundary-readme.template` (D8 content: boundary, two rule names, `import type`, how to run, three-dirs + `@/*` requirement, what the founder sees on a trip — red check + ADR-074 draft PR, install-time proof + re-prove via `--refresh-baseline`, agent-owns-recovery; attribution comment on line 1; no peer sentence)
- [ ] 3.2 Place `apps/web-platform/server/README.md` = emitter transform; append the pointer line to repo-root `CLAUDE.md` (plain prose, `<!-- constraint-scaffold:pointer -->`, no `@`)
- [ ] 3.3 `parity.test.sh`: rows 7–8 (`-s` pre-checks; row 7 `diff` + `grep -cF` pin of the strip expression in the script; row 8 marker `== 1`, path present, no `@apps/`); independent `cases`, conservation, `MIN_ROWS=10` floor in the recognised shape; trailer `10 passed, 0 failed`; execute Guard 2 rows 1–8 + harness
- [ ] 3.4 `bash scripts/markdown-lint.sh` clean on the README; `bash .github/scripts/test/test-no-at-mention-credfile-footgun.sh` clean

## Phase 4: Prose — `reproduce-bug`, `test-fix-loop`, `constraint-scaffold`, `ship`

- [ ] 4.1 `plugins/soleur/skills/reproduce-bug/SKILL.md` per D1–D5
  - [ ] 4.1.1 Attribution comment strictly between the frontmatter close and `<!-- soleur-cloud-mode:start -->` (R27)
  - [ ] 4.1.2 Phase 1: replace the "Keep investigating…" sentence only
  - [ ] 4.1.3 Phase 2 (new): decision-first — Redact; four checkboxes + hard gate; "cannot build a loop" stop with ordered defaults (instrumentation → environment access → captured artifact last) and the Playwright-before-declaring rule; then `### Ways to construct one` (10 rungs; rung 5 Soleur clause; rung 10 → `soleur:agent-browser`); tighten; non-deterministic branch; nothing posted before Phase 8
  - [ ] 4.1.4 Phase 3 (was 2): byte-preserved except the rung-4 sentence and the dev-server line (no `inform user`, no `bin/dev`); `redact-a11y-snapshot.py` reference verbatim
  - [ ] 4.1.5 Phase 4 (new) reproduce + minimise; Phase 5 (new) hypotheses with Discriminator column, founder render "what else you'd see if this is it", in-turn decision (no question tool), headless audit line; Phase 6 (new) instrument: minimal marker form (spelling, `printf '[DEBUG-%04x]\n' $((RANDOM % 65536))`, decision rule, D4 command, cite ADR-230) + perf branch
  - [ ] 4.1.6 Phase 7 seam verdict bullet incl. `gh label create action-required … --force` + `--add-label` and the digest-scope sentence; Phase 8 single comment with items 6–8 and the post-Phase-9 `soleur:test-fix-loop --cmd '…' --max 5` hand-off; Phase 9 checklist (shape grep, harness deleted, hypothesis stated, loop script committed)
- [ ] 4.2 `plugins/soleur/skills/test-fix-loop/SKILL.md`: attribution comment (same placement); Phase 0 `--cmd` / `--max` form + hand-off sentence; §4 D4 command before the checkpoint commit and before the success-row `git add -A`; Recommendation routing to `soleur:engineering:review:legacy-code-expert`; Key Principles bullet citing ADR-230
- [ ] 4.3 `plugins/soleur/skills/constraint-scaffold/SKILL.md` (attribution; `## Bite-proof (every run)`; emits table; usage; self-tests); `plugins/soleur/skills/ship/SKILL.md` one pre-PR checklist bullet with the D4 command
- [ ] 4.4 `bun test plugins/soleur/test/harness-parity-tree.test.ts`, `components.test.ts`, `devin-cloud-mode.test.ts` green; `cd apps/web-platform && ./node_modules/.bin/vitest run test/git-lock-marker-telemetry.test.ts test/plugin-root-anchoring.test.ts` green
- [ ] 4.5 Execute Guard 3 rows 1–5 on a scratch branch and Guard 4 rows 1–9 + harness; record

## Phase 5: Repo-global ratchets (BEFORE the review panel — operator-mandated; existing gates, run locally)

- [ ] 5.1 `bash scripts/guard-vacuity-floor.test.sh` exit 0 (new floors in the derived population)
- [ ] 5.2 `python3 scripts/lint-trap-tempfile-ownership.py --changed` exit 0; `python3 scripts/lint-trap-tempfile-ownership.py --check-highwater` exit 0
- [ ] 5.3 `python3 scripts/lint-rule-bodies.py --check --base "$(git merge-base origin/main HEAD)"` exit 0
- [ ] 5.4 `bash plugins/soleur/test/fixture-relative-assert.test.sh` — if RED: `--write-baseline`, `diff` old vs new, only rows for the four edited files moved (else rebase first), commit the baseline **in the same commit** as the operand edits with the per-file delta; re-run green. Same for `fixture-dir-operand-assert.test.sh`
- [ ] 5.5 `python3 scripts/lint-skill-body-budget.py --base "$(git merge-base origin/main HEAD)"` exit 0 (`ship` under 274 000)
- [ ] 5.6 `bash scripts/lint-orphan-test-suites.sh` → `0 orphaned`; `bash plugins/soleur/skills/constraint-scaffold/test/boundary.test.sh` green
- [ ] 5.7 First in-target proof: clean tree, `apps/web-platform/node_modules` installed → `bash plugins/soleur/skills/constraint-scaffold/scripts/constraint-scaffold.sh --refresh-baseline` prints the verdict line, exit 0, `git status --short` empty, `git worktree list` unchanged; paste the verdict line into the PR body

## Phase 6: ADRs, NOTICE, docs, evidence

- [ ] 6.1 `soleur:architecture`: ADR-071 amendment `## Amendment 2026-09-19 (#8288) — …` with consequences (a)–(f) and the opt-out-flag rejected alternative; ADR-230 (provisional) with the single normative two-class table; sweep the ordinal into plan, `tasks.md`, both SKILL.md citations if it moved
- [ ] 6.2 `plugins/soleur/NOTICE` › `mattpocock/skills`: `Used in:` + `Portions adopted:` paragraph; run `git diff "$(git merge-base origin/main HEAD)" | grep -n 'Matt Pocock\|mattpocock'` (nothing under `apps/web-platform/`); run the AC2 8-word shingle check over the emitted README against both peer blobs → 0
- [ ] 6.3 `bash scripts/sync-readme-counts.sh` leaves no diff
- [ ] 6.4 `knowledge-base/project/specs/feat-one-shot-8288-reproduce-bug-red-loop/decision-challenges.md` — already written by plan; append anything new from the work phase
- [ ] 6.5 PR body: one line per guard (`Guard N: k/k RED, h/h harness as specified`), ratchet trailers, RED-run evidence (1.3), bite cost (0.4), the 5.7 verdict line, the CMO changelog line for `soleur:feature-tweet`; `Closes #8288`; no `Closes` for #8289/#8290/#8292

## Phase 7: Acceptance

- [ ] 7.1 Walk AC1–AC23 with the exact commands in the plan; every "gate green" AC runs the gate's own invocation
- [ ] 7.2 Deferrals 1–2 filed at ship with `deferred-scope-out` + re-evaluation criteria; numbers on the `Filed:` line
