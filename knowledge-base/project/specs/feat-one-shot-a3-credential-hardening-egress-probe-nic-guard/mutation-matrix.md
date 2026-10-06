# Guard Contract matrix — results on the final tree (scratch copies, restore verified byte-identical)

Control (unmutated, both suites, in a sandbox with `apps/web-platform/Dockerfile` present): 0 failures. A first run of the probe rows
against a sandbox missing that file had a RED control and was discarded as void. Each mutation was applied to a scratch copy, the owning
suite run, the file restored and compared.

| Row | Mutation | Result (failing rows) |
|---|---|---|
| G1.1 | delete the xtrace `case` block (NIC guard) | RED, 13 |
| G1.1c | delete it (cron probe) | RED, 9 |
| G1.2 | `*x*)` becomes `*y*)` | RED, 13 |
| G1.3 | `exit 78` becomes `exit 0` | RED, 4 |
| G1.4 | cron probe: refusal moved BELOW `trap emit_fail EXIT` | RED, 6 |
| G1.5 | refusal conditional on the token | RED, 1 (X1b only, as designed) |
| G2.1 | `post()` drops `--disable` | RED, 2 |
| G2.2 | `--disable` not first | RED, 2 |
| G2.3 | `beat()` drops `--noproxy` | RED, 2 |
| G2.4 | third heartbeat call site | RED, 2 |
| G2.6 | `post()` adds `-k` | RED, 2 (golden-argv allowlist; a flag deny-list survived this) |
| G2.7 | `post()` adds `--location-trusted` | RED, 2 |
| G2.8 | `beat()` adds `--proxy` | RED, 2 |
| G2.9 | heartbeat also receives the stdin bearer | RED, 3 |
| G2.10 | POST carries no auth | RED, 4 |
| G2.11 | bearer back on argv | RED, 4 |
| G2.12 | extra sender with stdin bearer in the unpinned branch | RED, 18 |
| G2.13 | bare curl in the unpinned branch | RED, 9 |
| G3.1 | equality becomes `[ -n "$INGEST_URL" ]` | RED, 34 |
| G3.2 | substring glob | RED, 25 |
| G3.3 | scheme-anchored prefix glob | RED, 17 |
| G3.3b | prefix match on the full literal | RED, 9 |
| G3.3c | case-folded compare | RED, 5 |
| G3.4 | literal env-reachable (`${INGEST_URL_PINNED:-...}`) | RED, 5 |
| G3.5 | one-character edit of the literal | RED, 33 |
| G3.6 | extra `elif` posting on host-contains, placed BEFORE the unpinned branch | RED, 26 (placed after it, it is unreachable and survives: an equivalent mutant) |
| G4.1 | token-shape guard removed | RED, 2 |
| G4.2 | heartbeat not withheld when refused | RED, 9 |
| S1 | probe suite: stub call logger neutered | RED, 1 (instrument control P-X1c) |

Not run here: appending `set -x` after the refusal and a credential command above it are owned by the repo-wide lint (Rules A and B), green on
the final tree. Anti-vacuity: both suites now carry a call-site `CASES` counter, a `MIN_CASES` floor and a PASS+FAIL==CASES conservation check
reported by `printf` + `exit 1`; `scripts/guard-vacuity-floor.test.sh` constructs and fires both (the suites are promoted there, ledger unchanged).
