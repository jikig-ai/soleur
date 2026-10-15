# Tasks — feat-bare-root-anchor-gate

Plan: `knowledge-base/project/plans/2026-10-15-chore-bare-root-cwd-session-gate-plan.md`
Issue: #10383

## Phase 1 — Detection helper + battery

- [x] 1.1 Create `.claude/hooks/bare-root-cwd-guard.sh` — config-FILE predicate
  (`-d .git && ! -L`, `git config --file .git/config --type=bool --get core.bare == true`,
  `--absolute-git-dir == $root/.git`), `unset GIT_*` location vars, `dir="${1:-$PWD}"`,
  prints `SOLEUR_BARE_ROOT_CWD source=session-start` + bounded `[bare-root-cwd]`
  redirect block on detection, silent + `exit 0` otherwise. No `set -e`.
- [x] 1.2 Create `.claude/hooks/bare-root-cwd-guard.test.sh` — fixtures via
  `plugins/soleur/test/lib/git-fixture-env.sh`: mk_bare_root fires;
  mk_true_bare / mk_plain / linked worktree of bare repo / masked-config clone /
  symlinked `.git` / non-repo all silent; `dir` arg honored; marker+block shape
  asserted; positive control per negative row; owning EXIT trap before
  `source test-helpers.sh`; `grep -c` comparisons not `! grep -q`.

## Phase 2 — Loader integration

- [x] 2.1 Edit `.claude/hooks/session-rules-loader.sh` — timeout-guarded child
  call beside `BARE_HEAL_OUT` (reuse the `command -v timeout` conditional-array
  pattern, `SOLEUR_BARE_CWD_TIMEOUT_S` env override), capture + bound + sanitize
  output, append to `OUT_BODY` after the heal marker; header job list gains
  item 11.
- [x] 2.2 Edit `.claude/hooks/session-rules-loader.test.sh` — bare-root
  envelope contains marker + redirect block and `loaded: N of M` with N>0;
  worktree envelope contains neither; helper-absent → valid envelope, no
  marker (fail-open row).
- [x] 2.3 Edit `.claude/hooks/README.md` — sibling subsection under
  "Bare-root HEAD self-heal" documenting the arm's contract.

## Phase 3 — Readiness marker + telemetry

- [x] 3.1 Edit `plugins/soleur/skills/git-worktree/scripts/git-repo-readiness-diag.sh`
  — READY arm echoes `SOLEUR_BARE_ROOT_CWD source=readiness-diag` when
  `bare_out==true && wt_out!=true` AND the config-FILE predicate holds
  (parity comment pointing at the hook copy).
- [x] 3.2 Create `plugins/soleur/test/git-repo-readiness-diag.test.sh` —
  bare-root → READY + marker; worktree → READY only; masked-config → READY
  without marker.
- [x] 3.3 Edit `apps/web-platform/server/git-lock-marker-telemetry.ts` —
  `SOLEUR_BARE_ROOT_CWD\b.*` in MARKER_RE + MIRRORED-NOT-PAGED comment block.
- [x] 3.4 Edit `apps/web-platform/test/git-lock-marker-telemetry.test.ts` —
  mirror row for the marker.
- [x] 3.5 Create `scripts/bare-root-cwd-guard-probe.sh` — builds a throwaway
  bare-root-shaped dir, runs the guard, prints the marker (<15s, no creds).

## Phase 4 — Decision record + deferred filings

- [x] 4.1 Amend `knowledge-base/engineering/architecture/decisions/ADR-099-git-surface-topology.md`
  — idiom rule (session-start bare-CWD detection + redirect; overlay is a
  maintained mirror) + Alternatives-considered row (deny/auto-create/
  plugin-arm/do-nothing).
- [ ] 4.2 File follow-up issue A — bare-root scratch cleanup
  (operator-authorized; stop anchored sessions; `diff HEAD` enumeration;
  preserve the mirror / `.mcp.json` / `plugins/` per ADR-179).
- [ ] 4.3 File follow-up issue B — plugin-level `""`-matcher arm
  (cross-repo) + audit sibling SessionStart scripts
  (`ensure-kb-index.sh`, `memory-backstop-resolve.sh`,
  `supabase-loopback-warn.sh`) for bare-root write behavior.
- [x] 4.4 Edit `plugins/soleur/commands/go.md` — one sentence in the Step 1
  bare-repo guard paragraph noting the earlier session-start layer (outside
  `eval-gate:block:go-routing`).
- [ ] 4.5 Run the new suites + `git-lock-marker-telemetry.test.ts` +
  `session-rules-loader.test.sh`; verify every plan AC.

## Acceptance cross-check

- [ ] 5.1 All `## Acceptance Criteria` items in the plan verified against
  the diff; `git grep -l SOLEUR_BARE_ROOT_CWD` covers helper, diag,
  MARKER_RE, both test files, probe.
