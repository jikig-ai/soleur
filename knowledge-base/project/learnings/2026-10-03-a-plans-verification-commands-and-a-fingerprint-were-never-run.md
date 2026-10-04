# Learning: an unparseable key hashes to the empty-input digest, and a plan's verification commands must be run before they ship

## Problem

Two instances of one shape on #8609 (runbook R0 and the R3 plan): an instrument answered without measuring.

1. R0's "stop if the `prd` and `prd_terraform` fingerprints are equal" check was run with an `openssl pkey ... | openssl dgst -sha256 -binary | base64` pipeline. `prd_terraform`'s `GITHUB_APP_PRIVATE_KEY` had already been replaced by a non-key sentinel (#8209 O13), so `openssl` failed and the pipeline hashed empty input. The result, `47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=`, is a well-formed 44-character value that is simply different from the real key's, so it read as "two distinct keys". The conclusion (not equal) was right; the reasoning was not.
2. The R3 plan's Phase 0 and Phase 3 commands were written but not executed. Review found: `gh run list --status in_progress --status queued` keeps only the last value; `mergeCommit` is null until an `--auto` merge lands, so Phase 3.1 fed an empty SHA to the run filter; the "discoverability probe" already printed `success` before the change; and a bare `grep source=tier_b` also matches the echoed script source, which is why the old bootstrap verifier could never fail.

## Solution

- Compare fingerprints only after proving each input parses as a key, and treat `47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=` as "not a key". Routed into the runbook R0 row.
- Run every command in a plan's verification section once against live read-only data before committing the plan; anchor log matches on the rendered line (`##[notice]...`), guard empty SHAs, and call `gh` once per `--status`. Routed into `plan-sharp-edges.md`.

## Key Insight

A pipeline whose first stage can fail still prints a value from its last stage, and the value for "nothing" looks like a result. Before reading any measurement, ask what it prints for empty input, and run it on a case whose answer you already know.

## Session Errors

1. **Fingerprint "differs" read from the SHA-256 of empty input** — Recovery: re-scanned all Doppler configs and mapped the App page rows to holders — Prevention: runbook R0 now names the empty-input digest.
2. **Plan verification commands unexecuted (four defects)** — Recovery: five-seat review, fixed in `c7d6a82e27`, commands re-run live — Prevention: `plan-sharp-edges.md` bullet.
3. **Doppler scan used `.slug` instead of `.id` and printed nothing** — Recovery: inspected the JSON shape and re-ran — Prevention: print the field names of an unfamiliar CLI's JSON before iterating on one.
4. **`$TMPDIR` unset; a heredoc wrote to `/c8609.md` and was refused** — Recovery: used the session scratchpad — Prevention: use the scratchpad path, never `$TMPDIR`, in this environment.
5. **Playwright MCP died repeatedly on a stale Chrome `Singleton*` lock** — Recovery: removed the locks of dead pids and issued calls in quick succession — Prevention: host-local, none beyond the existing config note.
6. **Guard hooks refused `gh issue create` (missing label) and a process-pattern kill/list spelling, and refused this very learning's first shell write because its text named that spelling** — Recovery: added `--label meta/machinery`, used the file tools — Prevention: the hooks worked as designed.
7. **`operator-ack-guard` AC15 failed in the affected gate** — Recovery: reproduced on a clean `origin/main` checkout, traced to an `awk | grep -q` SIGPIPE under `pipefail`, filed #9460 — Prevention: tracked in #9460.

## Tags
category: workflow-issues
module: infra-credentials
