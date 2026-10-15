# Decision Challenges — feat-bare-root-anchor-gate

Headless pipeline channel (one-shot → plan → deepen-plan). No subagent
surface existed on this harness, so every technical ruling carries
`pending - assumed:` per the technical-ruling-delegation contract.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Gate placement: repo-level child arm inside `session-rules-loader.sh` (+ readiness-diag marker) vs. plugin `hooks.json` `""`-matcher arm vs. `worktree-manager.sh` emission | technical | pending - assumed: repo-level loader child arm + diag marker; the loader already reaches both measured misanchored harnesses via existing registrations; `worktree-manager.sh`/`cleanup-merged` at bare root is the *legitimate* case and must not be marked; plugin arm deferred to extension follow-up |
| Redirect vs. refuse vs. auto-worktree on detection | technical | pending - assumed: marker + injected redirect context (advisory); a hard PreToolUse deny is #3206's scope (adjacent, not folded in); auto-creating a worktree cannot `cd` the session and mutates branches unasked |
| Detection predicate: `git rev-parse --is-bare-repository` (issue's literal proposal) vs. config-FILE `core.bare` + gitdir identity | technical | pending - assumed: config-FILE conjunction per ADR-173 — `--is-bare-repository` reports `true` for a normal clone under a masked config and `false` inside a linked worktree; `bare-head-self-heal.sh:44-51` is the proven pattern |
| `.claude/.session-manifests/` writes at the bare root: keep or suppress | technical | pending - assumed: keep — the manifest is the durable forensic record of the misanchor (SOC 2 CC6.1); suppressing loses evidence of the measured condition |
| Marker payload: include absolute CWD path on the telemetry-mirrored line | technical | pending - assumed: `source=` only, no path — a mirrored path puts operator filesystem layout in Better Stack; the in-context block names the path (session-local) |
| Overlay/scratch cleanup (issue ask 4): this PR or deferred | operator (irreversible/production-mutating authorization) | deferred — follow-up issue filed; requires stopping live anchored sessions and preserves the maintained `sync_bare_files` mirror, so it cannot ride a code PR |
| Sequential review fallback (no Task/run_subagent on this harness) | mechanical | applied — plan-review lenses, domain sweep, and GDPR check executed inline; `Reviewed-Coverage: sequential-fallback` disclosed in the plan |
