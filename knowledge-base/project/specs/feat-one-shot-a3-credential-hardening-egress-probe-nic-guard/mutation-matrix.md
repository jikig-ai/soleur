# Guard Contract matrix — one-time results (scratch copies, restore verified byte-identical)

Control (unmutated, both suites): 0 failures. Each mutation was applied to a scratch copy of the script, the owning suite run, the file restored from a pristine copy and compared.

| Row | Mutation | Result |
|---|---|---|
| G1.1 | delete the xtrace `case` block (NIC guard) | RED, 13 failing rows |
| G1.1c | delete the `case` block (cron probe) | RED, 9 |
| G1.2 | `*x*)` becomes `*y*)` | RED, 13 |
| G1.3 | `exit 78` becomes `exit 0` | RED, 4 |
| G1.4 | cron probe: refusal moved BELOW `trap emit_fail EXIT` (reorder) | RED, 3 (call log non-empty) |
| G1.5 | refusal made conditional on the token | RED, 1 (X1b only, as designed) |
| G2.1 | drop `--disable` from `post()` | RED, 1 (X2, 4 bad calls) |
| G2.2 | `--disable` not first | RED, 1 |
| G2.3 | drop `--noproxy` from the second heartbeat curl | RED, 1 |
| G2.4 | third heartbeat call site added | RED, 1 |
| G3.1 | equality becomes `[ -n "$INGEST_URL" ]` | RED, 16 |
| G3.2 | substring glob | RED, 12 |
| G3.3 | scheme-anchored prefix glob | RED, 6 |
| G3.4 | literal env-reachable (`${INGEST_URL_PINNED:-...}`) | RED, 4 |
| G3.5 | one-character edit of the literal | RED, 29 |
| G3.6 | extra `elif` posting when host merely contains the domain | first placement SURVIVED: it sat after the existing `unpinned_url` branch, so it is unreachable (equivalent mutant). Re-placed before that branch: RED, 12 |

Not run (as the plan states): G1.6 (`set -x` appended, caught by the repo-wide lint Rule B) and G1.7 (a credential command above the refusal, lint Rule A prologue) are lint-owned; the lint is green on the final tree and its own suite covers those rules.
