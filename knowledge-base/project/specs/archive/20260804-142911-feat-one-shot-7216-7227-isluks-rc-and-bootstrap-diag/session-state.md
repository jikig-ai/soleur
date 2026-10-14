# Session State

## Plan Phase
- Plan file: `knowledge-base/project/plans/2026-08-03-fix-git-data-isluks-rc-and-bootstrap-diagnostic-plan.md`
- Status: complete

### Errors
- **Environment (non-blocking):** `/tmp` (tmpfs, 4 GB) hit 100% full mid-session. 2.6 GB belongs to a different, still-active Claude session's scratchpad (`ba79420a-…`), so it was left in place. One command lost its output to ENOSPC and was worked around.
- No planning errors. All halt gates passed, all citations resolved live, all 10 verify-the-negative claims confirmed.

### Decisions
- **#7216 fix shape corrected twice.** The issue's proposed `cmd; _rc=$?` aborts under the stage's `set -euo pipefail`; and the v1 draft's own `2>>` on the probe line forges `rc=1` **without running the command** (measured) — which on an unwritable `/run` would have taken the `1) luksFormat` arm and reformatted an already-encrypted store, i.e. v1's fix contained the bug it was closing. Final shape captures stderr via command substitution with a separately-tolerated append. Exit codes pinned against the target image's cryptsetup 2.7.0 (`1` / `4` / `127`).
- **#7227 item 1 → option 3** (bootstrap stage gets its own seeded scoped detail file), with an honest **two-clause** invariant: clause A (parent commands, key absent from env) is structural; clause B (doppler children, key present) is behavioural and is mechanized by a guard on `special = false`, no `set -x`, and `--key-file -`.
- **`bootstrap_err` deleted** rather than duplicated — `MSG` derives from `$STAGE`, which also fixes a latent live bug where a `gc_timer` failure emits "git-data bootstrap FAILED", removes the `_detail` name collision that defeats the widened guard, and recovers ~1.3 kB against 6,800 B of headroom.
- **The widened `R3(3b)` needed fixing before it could be trusted** — three reviewers independently found its guard search is file-global and name-keyed, so a naive widening would have shipped *weaker* than `main`.
- **Two scope items folded in** that neither issue named: the `sshd_config` stage (a fourth fatal site the widened guard surfaces) and `git-data-bootstrap.sh`'s `log()` writing stdout (without which the new detail file captures none of its 20 FATAL invariants).

### Components Invoked
`soleur:plan` · `soleur:plan-review` · `soleur:deepen-plan` · agents: `dhh-rails-reviewer`, `kieran-rails-reviewer`, `code-simplicity-reviewer`, `architecture-strategist`, `spec-flow-analyzer`, `cto`, `learnings-researcher`, `Explore` ×2 · `gh` CLI, `docker` (ubuntu:24.04 rc measurement), `lint-encryption-posture.py`, `git-data-userdata-budget.sh`, and the four git-data suites for baselines.
