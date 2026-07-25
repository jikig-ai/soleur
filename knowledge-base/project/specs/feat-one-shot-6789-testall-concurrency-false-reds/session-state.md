# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-22-fix-testall-worktree-contention-plan.md
- Status: complete
- Scope verified: `git diff origin/main...HEAD --name-only` returned only `knowledge-base/project/{plans,specs}/` paths — planning subagent stayed within its plan-only mandate.

### Errors
- **Flawed self-probe (caught and corrected in-session).** The initial `flock` liveness probe used `flock -w 1 -x -c true "$LOCK"`, which is malformed — `-c` consumed `true`, leaving `$LOCK` a stray argument, so it failed for usage reasons and reported `BLOCKED` in both arms. A second attempt chased a real but irrelevant confound (a child `sleep` inheriting fd 9). Only a third attempt with a known-free-lock positive control produced the correct result. Recorded as a Sharp Edge in the plan.
- **No `Task` tool in the planning subagent's context**, so the plan skill's parallel research fan-out (Phase 1) and the Phase 5 review panel could not be spawned. Research was performed directly instead (measurement-heavy rather than agent-heavy). `/soleur:plan-review` has NOT run against this plan — carried forward as a known gap; the one-shot pipeline's Step 4 `/soleur:review` still applies to the implementation.
- No other errors. No gate halted.

### Decisions
- **Re-derived the cause from measurement, not from the record.** H1 (semgrep bootstrap) and H2 (`.scan-meta.json`) were refuted by mechanical reachability plus `git log -S`; H3 (resource oversubscription) is confirmed material but not the sole cause; H4 (fixed-path tempfile) is honestly left UNKNOWN because the discriminating datum has not been captured. Phase 1's probe therefore ships alone, ahead of every fix, to capture it.
- **Both halves of the documented cause were refuted.** `.scan-meta.json` was PID-scoped in its original commit (`5da50856d`, #3524) and never changed — the `work/SKILL.md` attribution was wrong when written, not stale-after-a-fix. The semgrep bootstrap is unreachable from `test-all.sh` (zero suites under the runner's globs invoke it).
- **Actual contended resource: the shared 4 GiB `/tmp` tmpfs at 86 % occupancy**, RAM-backed, on a box with ~6 GiB available and swap exhausted. Both implicated suites already document their contention mode in-repo as a timeout (#4096, #3817/#4128), never a path collision.
- **Reuse `session-state.sh` rather than hand-roll a lock.** The precedent diff found it already supplies git-common-dir anchoring, bounded `flock`, a kill switch, a double-source guard, and fail-open behaviour — deleting an entire lock implementation from scope.
- **The lock is advisory: timeout ⇒ proceed with a banner, never abort.** No failure mode of the change can prevent a test run; worst case degrades to today's behaviour plus attribution.
- **Age-reap rather than trap-delete `.scan-meta.json`** — it is GDPR Art. 32 evidence with a documented post-exit consumer, so the obvious "add the missing cleanup trap" would have silently broken the override mechanism.
- **Occupancy is dominated by three entries (3.1 GiB) versus 4,294 small ones (160 MB)** — the intuitive many-small-files fix would have recovered 4.5 % of the problem.
- **Ratchet, not sweep,** on the tempfile-ownership debt (ADR-129 documents why paying off all ~100 accepted files is how a gate gets switched off).

### Components Invoked
- `Skill: soleur:plan`
- `Skill: soleur:deepen-plan`
- deepen-plan gates run inline: 4.4 (precedent-diff), 4.5 (network-outage — false-positive trigger, disposition recorded), 4.55 (downtime/cutover), 4.6 (user-brand impact), 4.7 (observability), 4.8 (PAT-shaped), 4.9 (UI wireframe) — no halt fired
- `gh` (issue/PR state + code-review overlap), `git log -S` / `git grep`, `bun test`, `flock`/`fuser` probes, `df`/`du`/`free`, `lint-trap-tempfile-ownership.py --census`
