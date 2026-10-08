# Tasks: argv-bearer sweep S2 (ops and runner scripts)

Plan: knowledge-base/project/plans/2026-10-08-fix-argv-bearer-sweep-s2-ops-runner-scripts-plan.md
Rules for every task: no credential value is printed, echoed or compared in the clear; no git stash; one push after the
committed-tree gates; baseline E regenerated only after the merge commit exists.

## Phase 0: Measure, then RED

- 0.1 Re-run the four census commands; record counts (cutover HMAC 19, baseline 32/65, x-api-key sites, `-hmac` set).
- 0.2 `docker run` the pinned `node:22-slim` digest: record openssl, python3, node, od, tr, base64 presence.
- 0.3 Better Stack credential shape count (value-free) or record "unmeasured".
- 0.4 Infra-suite partition: scratch copy of `cutover-inngest.sh` with all 19 HMAC sites converted, run the infra suite read-only, record red rows (expected: the two census rows).
- 0.5 Confirm `git status --short` is clean; nothing from the main checkout is staged.
- 0.6 Write the RED rows for every phase below and record the RED counts.

## Phase 1: Rule E `-u`/`--user` arm (commit 1)

- 1.1 Add `E_USER_FLAG`, `E_USER_ATTACHED`; set `f["user"]` in `_e_scan`; add the call-level, wrapper-site and second-credential reasons; keep the pinned finding grammar.
- 1.2 Add the fixtures and `e_row` rows (violation spellings, must-PASS spellings, out-of-scope, xfail proxy-user) and the mutation rows.
- 1.3 Swap the credential flag in `violation-ruled-bare-assignment-pin.sh` to `--oauth2-bearer`; re-run every row naming it.
- 1.4 Docstring edits (USER ARM, vocabulary gaps, `$CURL_BIN` bullet, heartbeat decision, R2 SigV4 census).
- 1.5 Expect exactly three new repo-wide offenders (betterstack-query.sh and two apps/cla-evidence files); confirm.

## Phase 2: cutover-inngest.sh and #8767 (commits 2 and 3)

- 2.1 `backup)` arm: guarded `::add-mask::` after the Doppler read, code-only error with a class hint, drop `cat /tmp/backup-action`.
- 2.2 Convert the HMAC sites outside the census range (17 expected) with the canonical snippet; comment the held-back sites; add the `_sig_curl` marker line (arms stay single-line).
- 2.3 Battery Stage S2-A rows (backup-arm extraction, oracle, parity, canary sweep). Run the infra suite read-only; floor 1069 unchanged.

## Phase 3: Better Stack reader (commit 4)

- 3.1 Deny-list guard (username no colon, both no `"`, `\`, control), marker, exit 2; `--config -` with `user = "..."`.
- 3.2 Battery Stage S2-B rows; run the three owning Better Stack suites.

## Phase 4: parity script and four probes (commit 3 continued)

- 4.1 Canonical snippet, `^[0-9a-f]{64}$` check, `_bearer_ok` on the Cloudflare Access values, `--disable --noproxy '*'`, stdin config, exit 2 on refusal.
- 4.2 Add the xtrace refusal to the three probes without it; drop their A/B/C and D baseline lines.
- 4.3 Update the two probe suites (remove the `openssl` stub, ensure `python3` resolves); add the `hmac-cf` shim profile and the four-probe manifest; rewrite the S2_OWNED row to assert empty with a positive control.

## Phase 5: sweeper hop (commit 5)

- 5.1 python3 `-I` execve launcher; keep validation order; rows for no `env` exec, no value in launcher argv, `=`/newline/100 KB round trip. Fall back to documenting if existing T8/G3 rows cannot hold.

## Phase 6: Anthropic key sites (commit 6)

- 6.1 `compound-promote.sh` and `learning-retrieval-bench.sh`: stdin config, key shape guard, refusal exit 1 (never `(API_ERROR)`); extend the mock curl to record argv and stdin; drop A/B/C and D baseline lines when the explicit-path run is clean.

## Phase 7: plugin scripts (commit 7)

- 7.1 `lib/hmac-sha1-b64.sh`; source it from `x-community.sh` and `x-setup.sh`.
- 7.2 `write-env` allow-list validation (bsky, discord, x); Discord argument handling with the four branches and exit 64; header and usage text.
- 7.3 Rows in `community-argv.test.sh` (oracle matrix, recording openssl shim, no-interpreter PATH run, hostile values, round trip, repair path).

## Phase 8: docs and tracking inputs (commit 8)

- 8.1 Create the five follow-up issues first.
- 8.2 Runbook row split, ADR-241 amendment, rotation tracking check (O13, #9294).

## Phase 9: verification and baseline-only commit (commit 9)

- 9.1 Merge `origin/main`; regenerate baseline E; edit the ceiling table; drop the converted A/B/C and D lines; assert totals = pre - 5 + 2.
- 9.2 Run the full gate list on the committed tree; one push.
- 9.3 Smoke on the branch (sweeper `dry_run`, one Better Stack reader workflow if one qualifies).

## Phase 10: PR and tracking

- 10.1 PR body per the plan (first line, Ref/Closes, no plan paths, no soak script names).
- 10.2 Comment on #9597 and #7898; confirm the five follow-up issues.
