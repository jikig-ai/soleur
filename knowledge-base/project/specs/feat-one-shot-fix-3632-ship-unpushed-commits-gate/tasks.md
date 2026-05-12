# Tasks — fix: ship unpushed-commits gate (#3632)

Derived from `knowledge-base/project/plans/2026-05-12-fix-ship-unpushed-commits-gate-plan.md`.

## Phase A: Hook script + tests (RED → GREEN)

- [ ] A.1 Write `.claude/hooks/ship-unpushed-commits-gate.test.sh` with stubs for T1-T11.
  - Mirror the fixture pattern from `.claude/hooks/pre-merge-rebase.test.sh`.
  - Initial run: all tests FAIL (hook does not exist yet).
- [ ] A.2 Implement `.claude/hooks/ship-unpushed-commits-gate.sh`.
  - A.2.1 Source `lib/incidents.sh`.
  - A.2.2 Read stdin via single `jq` fork: parse `.cwd` and `.tool_input.command`.
  - A.2.3 Apply chain-operator regex `(^|&&|\|\||;)\s*gh\s+pr\s+merge(\s|$)` — exit 0 if no match.
  - A.2.4 Resolve `WORK_DIR`; skip if not a work-tree, on main/master, on detached HEAD, no upstream tracking.
  - A.2.5 `git fetch origin "$BRANCH"`; fail-open with stderr warning on network error.
  - A.2.6 Count `git rev-list "origin/${BRANCH}..HEAD" | wc -l`.
  - A.2.7 If > 0: `emit_incident wg-ship-push-before-merge deny <reason> "$CMD"` + deny-JSON output with commit list.
  - A.2.8 Else: exit 0 with `additionalContext` confirming pass.
- [ ] A.3 `chmod 755` on the hook script.
- [ ] A.4 Run tests until GREEN. All T1-T11 PASS.

## Phase B: Wire hook in `.claude/settings.json`

- [ ] B.1 Insert hook entry into `hooks.PreToolUse` with `matcher: Bash`, ordered AFTER `pre-merge-rebase.sh`.
- [ ] B.2 Validate JSON: `jq . .claude/settings.json > /dev/null`.
- [ ] B.3 Smoke-test by running the hook against current state (0 unpushed → pass).

## Phase C: Document Phase 6.4 in `plugins/soleur/skills/ship/SKILL.md`

- [ ] C.1 Insert `## Phase 6.4: Unpushed-Commits Gate` between Phase 5.5 and Phase 6.
- [ ] C.2 Body names the hook by path, includes equivalent shell snippet for headless contexts, cites `[skill-enforced: ship Phase 6.4 + hook ship-unpushed-commits-gate.sh]`.
- [ ] C.3 Verify Phase anchors: `grep -n "^## Phase" plugins/soleur/skills/ship/SKILL.md` shows expected order.

## Phase D: Register rule in AGENTS.md + AGENTS.core.md

- [ ] D.1 Add `- [id: wg-ship-push-before-merge] → core` to `AGENTS.md` Workflow Gates section, after `wg-after-marking-a-pr-ready-run-gh-pr-merge`.
- [ ] D.2 Add the single-line rule body to `AGENTS.core.md` Workflow Gates cluster.
- [ ] D.3 Verify byte budget ≤ 600 via `awk '/wg-ship-push-before-merge/ {print length($0)}' AGENTS.core.md`.
- [ ] D.4 Verify rule-id uniqueness: `grep -c '\[id: wg-ship-push-before-merge\]'` returns 1 per file.

## Phase E: Capture learning

- [ ] E.1 Write `knowledge-base/project/learnings/<topic-named>-ship-unpushed-commits-fail-open-class.md` (let author pick the date prefix at write-time).
- [ ] E.2 Body: Problem (chain), Solution (3 layers), Key Insight (GitHub MERGED state hides local fail-open), Session Errors (TBD).

## Phase F: Cross-file verification

- [ ] F.1 `grep -rn 'wg-ship-push-before-merge' . --exclude-dir=.git` — only PR-touched files match.
- [ ] F.2 `bash .claude/hooks/ship-unpushed-commits-gate.test.sh` final GREEN.
- [ ] F.3 `bash .claude/hooks/pre-merge-rebase.test.sh` still GREEN (regression).

## Phase G: PR

- [ ] G.1 Open PR with `Closes #3632` in body (NOT title; NOT `Ref`).
- [ ] G.2 Apply labels: `priority/p2-medium`, `type/bug`, `domain/engineering`, `semver:patch`.
- [ ] G.3 Run full preflight + review before queue.

## Dependencies between phases

```
A (hook + tests, GREEN)
   └─→ B (wire in settings) — needs A to succeed; settings change goes live immediately
         └─→ C (SKILL.md Phase 6.4) — references the hook by name; should land same PR
               └─→ D (AGENTS.md + AGENTS.core.md) — references SKILL.md Phase 6.4 via [skill-enforced: ...]
                     └─→ E (learning) — references the implementation
                           └─→ F (cross-file grep verify)
                                 └─→ G (PR)
```

A → B is hard-ordered (wiring a non-existent hook breaks all Bash invocations). C → D is soft-ordered (rule body cites SKILL.md phase, but the cross-file consistency only matters at PR time). All phases land in a single PR.
