# Tasks — fix: ship unpushed-commits gate (#3632)

Derived from `knowledge-base/project/plans/2026-05-12-fix-ship-unpushed-commits-gate-plan.md`.

## Phase A: Hook script + tests (RED → GREEN)

- [ ] A.1 **MANDATORY GATE — Empirical hook-input shape verification** (per learning `2026-05-10-empirical-hook-input-shape-prevents-silent-zero-emission.md`).
  - A.1.1 Write `/tmp/ship-gate-stub-capture.sh` that `cat > /tmp/ship-gate-input-sample.json` and exits 0.
  - A.1.2 Wire stub temporarily in `.claude/settings.json` under `hooks.PreToolUse` matcher `Bash`.
  - A.1.3 Run `claude -p 'echo hello'` child session — child loads settings, fires stub on its own Bash invocation, writes the sample.
  - A.1.4 Inspect `/tmp/ship-gate-input-sample.json` — confirm `.tool_input.command` (string), `.cwd` (string), `.tool_name == "Bash"`.
  - A.1.5 Record verified shape as date-stamped header comment in the new hook (template in plan Phase A.1).
  - A.1.6 Remove stub from settings.json; delete `/tmp/ship-gate-stub-*`.
  - **Gate:** If any field path differs from the sibling-hook contract, halt and surface — drift would invalidate all 5 sibling hooks.
- [ ] A.2 Write `.claude/hooks/ship-unpushed-commits-gate.test.sh` with stubs for T1-T14 (T1-T11 base + T12-T14 from deepen-plan).
  - Mirror the fixture pattern from `.claude/hooks/pre-merge-rebase.test.sh`.
  - Initial run: all tests FAIL (hook does not exist yet).
- [ ] A.3 Implement `.claude/hooks/ship-unpushed-commits-gate.sh`.
  - A.3.1 Header includes the empirically-verified hook-input shape from A.1.
  - A.3.2 `set -eo pipefail` (omit `-u`); source `lib/incidents.sh`.
  - A.3.3 Single `jq` fork via `@sh` to extract `.cwd` and `.tool_input.command` (mirrors `guardrails.sh:30`).
  - A.3.4 Apply chain-operator regex `(^|&&|\|\||;)\s*gh\s+pr\s+merge(\s|$)` — exit 0 if no match.
  - A.3.5 **Guard ordering (load-bearing per learning 2026-03-28):** (1) non-merge cmd → exit 0, (2) main/master → exit 0, (3) detached HEAD → exit 0, (4) no upstream tracking → exit 0, (5) not a work-tree → exit 0.
  - A.3.6 `git -C "$WORK_DIR" fetch origin "$CURRENT_BRANCH" >/dev/null 2>&1 || { echo "warn..." >&2; exit 0; }` — **redirect BOTH stdout AND stderr** per R5/T14.
  - A.3.7 `UNPUSHED=$(git -C "$WORK_DIR" rev-list "origin/${CURRENT_BRANCH}..HEAD" 2>/dev/null | wc -l | tr -d ' ')`.
  - A.3.8 If `UNPUSHED -gt 0`: capture 10-commit `COMMIT_LIST`, call `emit_incident wg-ship-push-before-merge deny "<≤50char prefix>" "$CMD"`, emit deny-JSON via `jq -n --arg ...`.
  - A.3.9 Else: exit 0 with `additionalContext` JSON confirming pass.
- [ ] A.4 `chmod 755 .claude/hooks/ship-unpushed-commits-gate.sh`.
- [ ] A.5 Run tests until GREEN. All T1-T14 PASS.

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
- [ ] F.2 `bash .claude/hooks/ship-unpushed-commits-gate.test.sh` final GREEN (T1-T14 all PASS).
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
