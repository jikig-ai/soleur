# Session State

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-7697-10209-8163-contention-robustness/knowledge-base/project/plans/2026-10-13-fix-test-all-contention-robustness-plan.md
- Status: complete
- cto_spawns=1 (batched pre-work ruling, 2026-10-13 — all 5 pending rows ruled; Item D carries a Dissent recorded in decision-challenges.md)

### Errors
- `git commit` blocked twice by harness guard in subagent context; parent committed staged artifacts (609fab4362).
- No Task/Agent tool in subagent — research/review fan-outs performed inline; technical rulings persisted as `pending - assumed:` rows in decision-challenges.md.

### Decisions
- #7697: `timeout -k` outer bound in `_acquire_lock_impl` + report-only `<name>.holder` progress marker (ADR-133 honours: no abort-on-timeout, no stale-holder action).
- #10209: scrub inherited `TC_SIBLING_RUN_COUNT` + suite-pinned count mirroring `SANDBOX_SIBLINGS`; exempt-vs-assert pending CTO ruling.
- #8163: contention-aware ceiling — `[note]` instead of `[FAIL]` when siblings observed; uncontended still fails.
- Housekeeping: `archive-kb.sh one-shot-6752-7004-10167-tmp-gate-residuals` (dry-run then apply).

### Components Invoked
- `soleur:plan` (in-process), `soleur:deepen-plan` (in-process), empirical flock/timeout probes, `gh issue view`, `lint-guard-contract.py`

## Work Phase (2026-10-14)
- Commit: 742e3eb514 `fix(test-all): contention robustness` — 17 files, +840/-68.
- Execution: Tier C sequential (parallel fan-out would contaminate the contention measurements this batch fixes).
- Key implementation findings:
  - GNU `timeout` unblocks the child's signal mask, so wrapping `flock -w` RESTORES the inner expiry under a blocked SIGALRM (rc=1 at -w) — rc=124/LOCK_BOUND_FORCED is reserved for a flock that cannot return at all.
  - weight-drift C8 refusal chain confirmed live: sandbox diff walk degrades `index-missing` → `_aff_fallback` arms the full-gate conjunct → inherited count + re-armed stamp → rc=4.
  - `archive-kb.sh` slug run over-captures in-flight artifacts via its branch-diff axis — surgical `git mv` used for the leftover spec dir + plan (20261014-000000 prefix).
- Suite results (all green): session-state 44/44, test-contention 175/175, gitleaks-merge-commit 30/30, gitleaks-rules 45/45, weight-drift 52/52 (incl. under TC_SIBLING_RUN_COUNT=3), group-affected 54/54 (same), killed-classification 77/77, runtime-ceiling 23/23, affected 192/192, fanout-suite-scope 53/53, capacity-signal 80/80, orphan-process-reaper 148/148, orphan-mutation battery 610/610 (87s vs 240s ceiling), fixture-relative-assert 63/63 (baseline regenerated +2 sites), guard-vacuity-floor 23/23, lint-trap-tempfile-ownership 120/120, plan-gate-preamble 41/41.
- GDPR gate: skipped per rule — cumulative diff matches no canonical regulated-data path.
- Full gate run 1 (742e3eb): 620/626 — 3 failures, all attributed:
  - `lint-shell-capture-exit-live`: real defect — unguarded `$(grep …)` captures in the new test-contention lines → fixed in 82f019647a, verified isolated.
  - `go-session-gates` H3: environmental — box `claude` binary weekly-rate-limited (resets Oct 18); real-harness spawn returns the limit notice, not gate tokens. Documented `SOLEUR_GO_GATES_SKIP_H3=1` opt-out used for the rerun.
  - repo-boundary FATAL: self-inflicted — the 82f019647a commit moved HEAD inside the run's boundary window.
- Full gate run 2 (82f019647a + merge c77617d, quiesced tree, SOLEUR_GO_GATES_SKIP_H3=1): **623/626 passed, 0 failed, 0 killed (rc=0)**, ~3h50m; degraded to MODE=full by design (runner changed). `go-session-gates` 239/239 green under the opt-out.

## Review Phase (2026-10-14)
- Panel: class=code, tier=none (undeclared, no sensitive paths). 7 seats spawned: git-history, pattern, architecture, security, code-quality, test-design, structural-enumeration. Skipped per gates: data-integrity/agent-native/performance (no mapped path), semgrep (bash-only → shellcheck substitute), anti-slop (no web-app paths), gdpr (no regulated paths).
- Converged P2s fixed: missing `shift` in `stamp_lock_holder` (4 seats; stray name line verified live in the real gate's marker); `release_lock` rm-after-close ordering (architecture: successor's marker stranded for its whole hold → rm before close); unvalidated `timeout_s` in `$(( ))` (set -u abort path vs never-abort contract → digits-normalize); symlink-following `.holder` writes on the /tmp orphan fallback (security → mktemp+mv mint/stamp, `-f && ! -L` gate); stale `_tc_wait_heartbeat` docstring; miscited #8163 figure (241 s → recorded 429523ms/179s isolated).
- Test-design P2s fixed: SigBlk precondition asserted inside the wrapped script (T20); T23 now pins the `timeout(1) absent` degrade note; H8 anchors `stamp_lock_holder test-all`; new H2c arm proves a stamp advances `progress_epoch`; H2b shape pin (kv-only marker lines); fail-by-hang stubs carry an outer `timeout 60` (T20b, gitleaks T8).
- Cheap P3s folded in: `124|137` both map to LOCK_BOUND_FORCED; kv newline sanitization; lock-name charset validated before path use; lock-file type check (fifo would block in open() before the bound); shared-mode `-s` skips the mint (no single holder identity); `holder_progress_age=?` for non-positive epochs (bash<5); `_mut_sibling_count` deduped by worktree + distinguishes readable-empty (measured 0 → still asserts) from absent/unreadable (→ contended); group-affected dead `TC_SIBLING_RUN_COUNT_PID=$$` env dropped; `gl_probe` reuses `_GL_TIMEOUT_CMD`; ADR wording (blocked-mask = waiter's park vs holder's anon_pipe_read wedge; "recent GNU timeout"; degrade-arm residual named; "observe-only" label corrected).
- Structural-enumeration findings accepted as scope/report: other repo `flock -w` users (.claude/hooks, slot lock, tmpfs scripts) are outside the session-state chokepoint by design — the bound guards the named-lock class, not every flock; PATH-hijacked timeout and outer-SIGKILL residuals are inherent same-authority boundaries.
- Baseline drift (git-history P2): `ship-kb-archive-gate.*` landed on main post-merge-base (#10161) → merged `origin/main` (clean, merge-tree rc=0) and regenerated `fixture-relative-assert.baseline.txt` (478 rows, session-state 8 sites).
- Fix-round verification: session-state 44/44, test-contention 177/177, weight-drift 52/52 (+injected count), group-affected 54/54 (+injected count), gitleaks-merge-commit 30/30, gitleaks-rules 45/45, fixture-relative-assert 63/63, lint-shell-capture-exit 133/133 (0 new findings, 3 baselined pre-existing), shellcheck clean on edited files. `_mut_sibling_count` unit-driven: fake→1, readable-empty→0, absent/unreadable→unmeasurable.
- Environmental note: the mutation battery's unmutated CONTROL reddened during fix-round verification because a FOREIGN worktree's live `test-all --affected` ran on the box — the AC40 live-walk guard correctly refused non-victim processes (the #8163 class itself). Pre-existing control sensitivity, not the diff.
- tasks.md: all 20 boxes ticked.
