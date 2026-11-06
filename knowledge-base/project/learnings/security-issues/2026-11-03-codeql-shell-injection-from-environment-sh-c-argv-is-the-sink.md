---
title: "CodeQL js/shell-command-injection-from-environment: the sink is the `-c` argv element, not the spawn"
date: 2026-11-03
branch: feat-one-shot-codeql-shell-injection-batch
---

# The sink is `sh|bash|cmd.exe` argv elements when `-c` is present

`js/shell-command-injection-from-environment` (`ShellCommandInjectionFromEnvironmentCustomizations.qll` + `IndirectCommandArgument.qll`) sources are **absolute paths** (`__dirname`, `process.execPath`, `process.cwd()`, `path.resolve`/`realpathSync`/`mkdtempSync`-family outputs) and **file names**. Its sinks are nodes a shell interprets: `exec`/`execSync` arg0, and — via `IndirectCommandArgument` — **every element of the argv array** of a `sh|bash|cmd.exe` execution whose args contain `-c`. Plain `execFileSync`/`spawn` argv elements are NOT sinks, and an `env` option alone is not either — until one call site passes `cmd="bash"` + `"-c"`, at which point the shared wrapper's exec call becomes an indirect shell execution and EVERY absolute-path argv at every call site lights up (alert 279: one `resolveBin` `bash -c` produced six flows at `run()`'s `execFileSync`).

## Fixes that clear the flow (both measured)

1. **Script-file form** (PR #7566, alerts 213/214): write the inline script to a temp file, run `sh <file> <args>` — positional params carry the same values, and with no `-c` element nothing is shell-interpreted. `sh script arg1 arg2` maps `$1=arg1`, matching `sh -c 's' sh arg1`'s `$1=arg1`.
2. **Remove the shell entirely** (alerts 279): `command -v` + `readlink -f` == PATH walk + `statSync().isFile()` + `accessSync(X_OK)` + `realpathSync` — first PATH hit wins, absent → undefined. Empty PATH entries are skipped deliberately (`command -v` treats them as CWD; a `.` hit is never the installed launcher). `realpathSync` throw → return the candidate (the `|| r="$p"` arm).

Trap: `process.env.X = undefined` assigns the literal string `"undefined"` — guard PATH/env restore in tests.
