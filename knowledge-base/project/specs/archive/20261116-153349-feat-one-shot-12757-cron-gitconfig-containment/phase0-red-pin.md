# Phase 0 RED run — Guard 3 (the pin)

Run 2026-11-16 against the unchanged source (no Doppler), git 2.56.0:

```
cd apps/web-platform && ./node_modules/.bin/vitest run \
  test/server/inngest/cron-spawn-git-config-pin.test.ts \
  test/server/inngest/cron-claude-eval-substrate-exit.test.ts
```

Result: RC=1, 16 failed / 39 passed (55). A RED is an assertion failure; a row that fails because `CRON_GIT_CONFIG_PIN`,
`agentGitConfigReadable`, `xdgGitResidualPresent` or `withCronGitConfigPin` does not exist yet is "fails to load".

| Row | Pre-fix | Note |
|---|---|---|
| 0 constant | fails to load | `CRON_GIT_CONFIG_PIN` is undefined |
| sweep dispatch | pass | control |
| 2 HOME literals pinned | RED | 26 sites in 23 files, none pinned |
| 2 KNOWN_HOME_LITERALS identity | pass | control (map seeded from this sweep) |
| 4 git spawns pinned | RED | 9 of 16 call sites: compound-promote spawnGit, publisher/rule-prune/weekly spawnGit, vendor-drift spawnGit/spawnGitStdout, cidr clone + status, strategy-review clone |
| 4 KNOWN_GIT_SPAWNS identity | pass | control, 16 call sites in 15 {file, owner} pairs |
| 4c git-capable literals | RED | the 9 git sites above plus 4 bash `spawnScriptCapture`, cidr `bash`, follow-through `gh` x2 |
| 4c exclusions stale-check | pass | zero exclusions needed by the first sweep |
| 4c dynamic-command spawns | RED | spawnSimple and spawnClaudeEvalUnguarded envs unpinned |
| 4c no other literal command | pass | control |
| 4d GIT_CONFIG_* writes | pass | control (compound-promote spawnGitCapture only) |
| 4b no retyped path | pass | control |
| walk self-tests, binding-not-name (3 planted cases) | pass | controls on synthetic source |
| 5 precheck / control arm | pass | control |
| 5 pinned arm, 5 third arm (NOSYSTEM) | RED | the pin spreads as `{}` so the planted alias/identity is read |
| 5b XDG residual | pass | characterisation |
| 6 probes (3 rows) | fails to load | `TypeError: … is not a function` via `vi.importActual` |
| substrate-exit row 1 | RED | `GIT_CONFIG_GLOBAL` is `/tmp/evil` |
| substrate-exit row 3 (2 cases) | RED | `undefined` / `/tmp/evil` |
| substrate-exit row 6 wiring (2 rows + control) | RED | zero reports; probes never consulted |
