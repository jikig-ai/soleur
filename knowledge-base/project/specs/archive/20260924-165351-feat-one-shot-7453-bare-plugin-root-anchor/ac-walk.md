# AC walk — #7453 (recorded 2026-09-24)

| AC | Result | Evidence |
| --- | --- | --- |
| AC1 | MET | `git grep -l -F -e 'CLAUDE_PLUGIN_ROOT:' -e 'CLAUDE_PLUGIN_ROOT-' -- 'plugins/soleur/**/*.md' \| wc -l` = 0; Pattern C grep = 0; `bash scripts/plugin-root-anchor-debt.sh` → `anchor-debt-files=0` (positive control on origin/main: 31). |
| AC2 | MET | Remaining non-md `:-` lines: `hooks/devin-session-start.sh:48` (emptiness test), `operator-bootstrap/template.sh:78` (`:-/nonexistent`), `redact-sentinel.test.sh` (FORBIDDEN needle + 2 comments), `go-session-gates.test.sh` (H1 + 2 comments). All Non-Goals. `concurrent-ship`/`lease-protects-active` now assemble the form from pieces, so they no longer appear. |
| AC3 | MET (deviation) | `bun test plugins/soleur/test/preflight-discoverability-test.test.ts` 123/0. Measured: under Check 10's `set -uo pipefail` an unset token aborts with `CLAUDE_PLUGIN_ROOT: unbound variable` (rc 127), not the plan's `FAIL: Check 10 parser missing at /skills/`; both rows are pinned (unset → unbound; set-but-empty → parser-missing), plus the twin control. |
| AC3b | MET | 69 distinct `${CLAUDE_PLUGIN_ROOT}/<path>` operands in skills markdown; 0 missing, 0 starting with `plugins/`. |
| AC4 | MET (deviation) | `phase1-red-run.txt`: W1 31, W1b 31, W2 2 files / 3 lines, W4a 2, W4b 9, W4c 1, W4d set mismatch. W4c's predicate was refined to fences that USE the token (most fences in these docs never touch the root), so it read 1 (SETUP.md:101), not the plan's 2. Green after migration: 46/46. |
| AC5 | MET | Identity pin passes; `git diff origin/main -U0 -- apps/web-platform/server/safe-bash.ts \| grep -E '^[-+]' \| grep -E 'RegExp\|DENYLIST *=\|String\.raw'` empty; only other non-comment change is `export` on `TRAILING_SAFE_REDIRECT`. `safe-bash` + coupling: 114/0. |
| AC6 | MET | Data-row diff: 38 `<` lines, all containing `CLAUDE_PLUGIN_ROOT:`, 0 `>` lines; 131 → 93 rows; `RATCHET_MIN_ROWS` 85. |
| AC7 | MET (scoped) | Guard 4 (a)–(d) green. The plan's literal pointer grep over-matches: its first needle `plugins/soleur/skills/brainstorm/references/` also hits pointers to NON-qualifying brainstorm references (`brainstorm-domain-config.md`, `ui-surface-terms.md`) — the #8729 class. Guard 4(b), which matches exactly the five docs, is the check. The `./plugins/soleur` added-line grep is empty over markdown; the two `.sh` hits are the lease test's decoy comment and its twin control's pre-migration form. |
| AC7b | MET | `admin-merge-ready-wiring.test.sh` 35/35: M12 positive, M13 unreplaced sentinel → exit 5 with empty ledgers, M14 twin decoy ran. Mutation (drop presence line) reds M13. The presence check reads `.claude-plugin/plugin.json`, not the gate script: naming the gate there satisfied the lint's "gate before merge" rule after the real gate was deleted (W6/W11 went green wrongly). |
| AC7c | MET | `concurrent-ship.test.sh` 30/0 (T1d mutation-checked); `schedule-skill-once.test.sh` and `lint-scheduled-show-full-output.sh` rc 0. |
| AC8 | MET | Derived sweep: 68 files (26 token-mentioning + 50 naming a migrated doc + the listed set + `tests/commands/test-sync-*.sh`), 62 result rows (7 webplat files as one vitest run, 250 tests), all rc 0, every log carrying a pass summary. `battery-tag-authorship` closure 1095 members = Phase 0. |
| AC9 | MET | ADR-179 `## Amendment — 2026-09-24 (#7453)` with A18–A20 and the Tier-1 table; `amended_by` entry; the Consequences deferral bullet carries a superseded note (append-only, not rewritten). ADR-093's "Amended by" line names the whole skills surface. |
| AC10 | MET | `git grep -n -e '#7453' -e '~105'` over server/test/scripts: remaining hits describe the completed migration, plus `run-template-gate.ts`'s unrelated "~105". |
| AC11 | MET | `c4-count-parity.test.sh`, `c4-code-syntax.test.ts`, `c4-render.test.ts` in the sweep, all green. |
| AC12 | MET | Captures below. |
| AC13 | PENDING | PR body, at ship. |

## AC12 captures (verbatim)

Setup: `cp -r plugins/soleur $T/soleur-plugin`; `$T/cwd` is a git repo holding canary copies of
`plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` (appends `CANARY-RAN` to a ledger)
and `plugins/soleur/skills/ship/references/settle-then-admin-merge.md` (first line
`# CANARY-CWD-COPY-OF-SETTLE-DOC`). Run from `$T/cwd` with
`env -u CLAUDE_PLUGIN_ROOT claude -p --plugin-dir "$T/soleur-plugin"` (Claude Code 2.1.281).

Prompt 1 (git-worktree `list`):

```text
COMMAND: bash "/var/tmp/ac12.DXMKhp/soleur-plugin/skills/git-worktree/scripts/worktree-manager.sh" list
EXIT: 0

I added `; echo "EXIT=$?"` to the end of that command to record the exit code. The script found no worktrees.
```

Canary ledger after prompt 1: empty.

Prompt 2 (ship's pointer to `settle-then-admin-merge.md`):

```text
PATH: /var/tmp/ac12.DXMKhp/soleur-plugin/skills/ship/references/settle-then-admin-merge.md
FIRST-LINE: # Settle-then-admin-merge escape hatch
NOTICE: **Plugin root in this file:** this file is Read, not delivered by the skill loader, so `${CLAUDE_PLUGIN_ROOT}` below is not replaced.
```

The path is under the relocated plugin and the first line is the real doc's, not the canary's.
