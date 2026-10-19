# Decision Challenges — feat-bare-root-anchor-gate

Headless pipeline channel (one-shot → plan → deepen-plan). The plan-phase
subagent had no spawn surface, so technical rows were staged as
`pending - assumed:` and ruled in the main session by a batched
`soleur:engineering:cto` spawn on 2026-10-15 — all five confirmed.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Gate placement: repo-level child arm inside `session-rules-loader.sh` (+ readiness-diag marker) vs. plugin `hooks.json` `""`-matcher arm vs. `worktree-manager.sh` emission | technical | Ruled by CTO agent, 2026-10-15: repo-level loader child arm + readiness-diag marker — the loader is already registered in both measured harnesses (`.claude/settings.json` SessionStart + `.devin/config.json` `""` matcher) and the `BARE_HEAL_OUT` child-call pattern (`session-rules-loader.sh` › loader body) is the proven isolation contract; `worktree-manager.sh`/`cleanup-merged` at bare root is the legitimate population and must not emit; plugin `hooks.json` arm deferred to #10392 |
| Redirect vs. refuse vs. auto-worktree on detection | technical | Ruled by CTO agent, 2026-10-15: marker + injected redirect context (advisory) — SessionStart can only emit `additionalContext` and cannot refuse, so the refuse arm requires a PreToolUse hook, which is #3206's scope; auto-creating a worktree cannot `cd` the session and mints branches unasked |
| Detection predicate: `git rev-parse --is-bare-repository` (issue's literal proposal) vs. config-FILE `core.bare` + gitdir identity | technical | Ruled by CTO agent, 2026-10-15: config-FILE conjunction per ADR-173, verbatim reuse of `bare-head-self-heal.sh` › three-term predicate (`.git` real non-symlink dir + `core.bare=true` via `git config --file` + `--absolute-git-dir == $root/.git` identity) — `--is-bare-repository` reports `true` on a masked-config plain clone (false-positive redirect into a healthy session) and `false` inside linked worktrees |
| `.claude/.session-manifests/` writes at the bare root: keep or suppress | technical | Ruled by CTO agent, 2026-10-15: keep — the manifest write is the durable forensic record of the misanchor (SOC 2 CC6.1); suppressing discards evidence of the measured condition for ~100 bytes/file |
| Marker payload: include absolute CWD path on the telemetry-mirrored line | technical | Ruled by CTO agent, 2026-10-15: `source=` only on the mirrored line — least-data for a marker firing routinely on the operator's personal checkout path; the absolute CWD belongs in the session-local `[bare-root-cwd]` context block only |
| Overlay/scratch cleanup (issue ask 4): this PR or deferred | operator (irreversible) | deferred — follow-up issue #10391 filed; requires stopping live anchored sessions and preserves the maintained `sync_bare_files` mirror, so it cannot ride a code PR |
| Sequential review fallback (no Task/run_subagent on this harness) | technical | Ruled by CTO agent, 2026-10-15: applied — plan-review lenses, domain sweep, and GDPR check executed inline; `Reviewed-Coverage: sequential-fallback` disclosed in the plan |
