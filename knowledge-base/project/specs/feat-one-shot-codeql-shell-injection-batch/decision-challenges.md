# Decision Challenges — feat-one-shot-codeql-shell-injection-batch

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Fix vs leave-open for the two test-file alerts (302/303) | operator (scope) | Ruled by operator $ARGUMENTS, 2026-11-03: fix when a shape-preserving remediation exists; the temp-file `sh <file> <argv>` pattern (precedent PR #7566, alerts 213/214) is exactly that — fix, don't flag as false positive. |
| `resolveBin` remediation shape for alert 279 | technical | pending - assumed: pure-Node PATH walk + realpathSync replaces the `bash -c` command-v/readlink script; it preserves `command -v` semantics (X_OK, first-hit, absent→undefined) and kills all six indirect-command flows at `run()`'s execFileSync — alternatives (PATH allowlist, codeql[] suppression) were cut in plan Phase 0.6b. |
| Whether `have()`'s `execFileSync("command", ["-v", bin], {shell:"/bin/bash"})` needs treatment | technical | pending - assumed: no — it is not a flagged site (implicit env, no env-derived argv element), and editing it would be scope creep beyond the three alerts. |
| Empty-PATH-entry handling in the new `resolveBin` | technical | pending - assumed: skip empty entries rather than resolve them cwd-relative; a `.` hit is never the installed launcher this function exists to find, and a skip cannot return a wrong binary. |
