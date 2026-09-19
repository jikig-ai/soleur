# Tasks — make `git_data_rung2_rehearsal_gate` load-bearing (#8010)

Derived from [the plan](../../plans/2026-09-19-fix-git-data-rung2-gate-load-bearing-plan.md) after plan review. Phase order is load-bearing: the tests are written RED before the gate, and the gate's contract lands before its consumers are re-pointed.

## Phase 1 — RED: the gate's refuse paths

- [ ] 1.1 Gate suite (`tests/scripts/test-git-data-birth-readiness-gate.sh`): `export SOLEUR_TEST_MODE=1 SOLEUR_RUNG2_RUN_FETCH="$TMP/api-fetch.sh" SOLEUR_RUNG2_RETRY_SLEEP=0` at suite top (export, not a prefix — `mutate_r2`/`mutate_g` run in child shells).
- [ ] 1.2 Add the `$TMP/api/<path-suffix>` stub store and `api-fetch.sh` (body file + `.status` file; a distinct "no entry" shape for transport failure; prints body then status, no headers). Store lives under `$TMP` so `git_fixture_env` fences it; call `assert_fixture_dir` on it.
- [ ] 1.2b Give `mutate_r2`/`mutate_g` a 4th `needle` argument (they assert rc only today, so every HOLD→HOLD token-swap row would pass vacuously) and anchor each `sed` to the target function's line range.
- [ ] 1.2c Add `mutate_suite <label> <sed> <expect-fails>` — harness row (a) of all four guards mutates the SUITE, and no helper does that today.
- [ ] 1.3 Add `_stub_run <id> key=value…` (`head_sha`, `conclusion`, `status`, `path`, `event`, `head_branch`, `created_at`, `http`, `artifacts`), defaulting artifacts to one `git-data-rung2-boot-evidence` entry.
- [ ] 1.4 Seed the existing arms: derive the id list by grepping the suite for `actions/runs/[0-9]+` — it is `1`, `2`, `17250000001`, `17253046871`, `_G_URL`, `_G_URL2` — each with `head_sha` = the matching fixture's pre-evidence commit so the archive re-hashes to `R2_SHA`. A missed id turns a green arm red on merge.
- [ ] 1.5 Extend `_r2_evidence_write` with `$6=sentry_verdict` (default `CLEAN`) and `$7=ack`.
- [ ] 1.6 Write the S-table rows S1–S12 (Sentry verdict + ack grammar).
- [ ] 1.7 Write the R-table rows R1–R13 (fetch failures, rate limit, anonymous retry, id parsing, field checks).
- [ ] 1.8 Write A1–A5 (artifacts discriminator, including the dry-run shape and the age branch).
- [ ] 1.9 Write H1–H6 (head_sha reachability, hash mismatch, the root-dir fixture, the ABORT token, the order pin).
- [ ] 1.10 Write T1 (`TOOLING_MISSING` before any stub call) and E1/E2 (the `::error::` emitter under `GITHUB_ACTIONS`).
- [ ] 1.11 Write the Guard Contract mutation and harness rows for Guards 1–3. Guard 1 row 12 proves the seam double gate with a marker file and a seeded-but-must-not-be-read entry — **no URL-host override** (that would be a second seam outside the `SOLEUR_TEST_MODE` gate) and never a live call; pair it and T1 with positive controls so neither is a pure negative that also passes for the wrong reason.
- [ ] 1.11b Add the fixture work the new arms need: a sub-floor historical module commit (H5), a `PATH` symlink farm dropping only `jq` with explicit save/restore (T1), `date -u -d '<n> days ago'` for the artifact-age arms, and a **subdirectory-shaped** cloud-init fixture so Guard 2 row 5's `<sha>:<repo-rel-dir>` branch actually executes.
- [ ] 1.11c Add the source-grep arm over the gate library (`--disable`, `--noproxy '*'`, the `https://` literal present; `-k`/`--insecure`/`-v`/`-D -` absent) — under the seam the real fetch never runs, so this is the only mechanism that can assert the flag set. Add the `set -x` caller arm for NFR3.
- [ ] 1.12 Add per-family row-count pins (`_expect_rows S 12`, …) so a mis-parsed table reds at its own name, then raise `_FLOOR=150` by hand to the **measured** total (baseline: 150 passed / 0 failed / floor 150 — zero slack) and itemise it in a `RAISED 150 -> N (#8010), ITEMISED:` block.
- [ ] 1.13 Capture suite (`tests/scripts/test-git-data-rung2-evidence-capture.sh`): give the producer/consumer arm (`gate_out="$(git_data_rung2_rehearsal_gate …`) the seam **as a per-command prefix on that invocation only** — do NOT export it suite-wide there; that file's per-command prefix is deliberate (the CWE-427 double gate is the property under test at its own arms). Stub `head_sha` = the fixture's own commit; `$FIX` is repo-root-shaped so this also exercises the `<sha>:` form.
- [ ] 1.14 Write C1–C6 (host/run coupling, the 24 h liveness argv, ARTIFACT 4's liveness line, the resolved `--end`, `NOT_RUN`) and raise `_FLOOR=107` with its itemised block.
- [ ] 1.15 `apps/web-platform/infra/git-data-rung2-rehearsal.test.sh`: one arm asserting exactly one `ACK REQUIRED` / `ACK NOT REQUIRED` line.
- [ ] 1.16 Run all three suites plus `plugins/soleur/test/terraform-target-parity.test.ts` and the `fixture-relative-assert` baseline; commit RED and record the count.

## Phase 2 — GREEN: the gate

- [ ] 2.1 `_git_data_rung2_fetch` — curl with `--disable --noproxy '*' -sS --max-time 20 -w $'\n%{http_code}'` split via `tail -n1` / `sed '$d'` (the `scripts/sentry-issue.sh` sibling form), a bash-array auth header, xtrace saved-and-cleared then restored, stderr to a `umask 077` `mktemp` removed on every return, 2 attempts on 5xx/transport via `SOLEUR_RUNG2_RETRY_SLEEP`, fast-fail on rc 6/7, one anonymous retry on a non-rate-limit 401/403 (and a following 404 is `RUN_UNRESOLVABLE`, not `RUN_NOT_FOUND`). Emit `SEAM ACTIVE — <path>` on every verdict line when the seam is honoured.
- [ ] 2.2 `_git_data_rung2_check_run` — `jq` field checks (`.id|tostring`, `.path`, `.event`, `.head_branch`, `.status`, `.conclusion`, `.head_sha`) with their tokens; rate limiting read from status + body.
- [ ] 2.3 `_git_data_rung2_hash_at_sha` — `cat-file -e`, then `git archive <sha>:<repo-rel-dir>` (or `<sha>:` at the repo root) with attributes disabled, `tar -x --no-same-owner --no-same-permissions`, an `lstat` sweep refusing symlink/hardlink entries, then the shared hash function. The `mktemp -d` is **left to the runner** with a `# lint-trap-ownership: ok <reason>` annotation — no `EXIT` trap (ADR-129) and no variable-rooted `rm -rf` (the precedent rejected it as an operand the P1b guard cannot prove safe). `RUN_HASH_MISMATCH` / `RUN_HASH_UNCOMPUTABLE`.
- [ ] 2.3b Raise `scripts/lint-trap-tempfile-ownership.highwater` by one with a written reason (new entrant: the gate library calls `mktemp` zero times today) and confirm `--check-highwater` passes.
- [ ] 2.4 `_git_data_rung2_check_artifacts` — exact name match, `expired` allowed, the 90-day age branch.
- [ ] 2.5 Wire steps A–E into `git_data_rung2_rehearsal_gate` after Guard 4, in the pinned order; add the two cardinality loops and the verdict `case`; add the run-id parser shared by Guard 1 and the ack check.
- [ ] 2.6 Add the `::error::` emitter for could-not-measure tokens under `GITHUB_ACTIONS` (precedent: `tests/scripts/lib/preapply-entrypoint-gate.sh`'s `_err()` — emitting from a sourced library is the dominant pattern here), the evidence-value sanitizer every printed interpolation runs through, and the extended RELEASED line.
- [ ] 2.7 Update the Guard 4 header residual paragraph and add the runbook pointer to the `STALE EVIDENCE` message.
- [ ] 2.8 Re-run the suites to green; `shellcheck`.

## Phase 3 — GREEN: capture, workflow, probe, docs

- [ ] 3.1 Capture: the `--host-name`/`--evidence-url` suffix refusal (exit 64).
- [ ] 3.2 Capture: `--stats-period 24h` at the `--liveness` call site (no helper); keep the fatal read run-pinned.
- [ ] 3.3 Capture: the never-consulted branches write `NOT_RUN`.
- [ ] 3.4 Capture: ARTIFACT 4 gains the liveness query line, the HOLD sentence and the pre-reset scope note.
- [ ] 3.5 Capture: the reset arm records its resolved `--end` instead of the literal `<now>`.
- [ ] 3.6 Workflow: the single post-reset `ACK REQUIRED` / `ACK NOT REQUIRED` line, CR/LF-stripped; the reordered evidence-landing block (ack before `git add`); the wait-for-`success` sentence. Keep the pinned PASS/FAIL/WRAPPER headings.
- [ ] 3.7 Probe: split `exit 3` (CANNOT ESTABLISH — the sweeper already renders it, measured) out of `exit 2` on the could-not-measure token set, print the gate's full token line rather than `head -1`, and reword the TRANSIENT message. One probe-suite arm per rc.
- [ ] 3.8 Runbooks: the token→remedy table, `--ref main`, `After a PASS` updates, `RUN_NOT_COMPLETED` in the misleading-things list, the two-PR payload sequence; `git-data-birth.md`'s Sentry sentence and replace-route fallback.
- [ ] 3.9 ADR-149 `### Disposition — #8010 (2026-09-19)` including the residuals, the anonymous-CI statement, the ack tripwire and the attestation alternative in Future Considerations.
- [ ] 3.10 `model.c4` `gitDataStore` sentence; run `plugins/soleur/test/c4-count-parity.test.sh` and the C4 render/freshness tests.
- [ ] 3.11 `actionlint` on the rehearsal workflow; `bash -n` on the extracted `run:` snippet.

## Phase 4 — Live verification and sequencing

- [ ] 4.1 Real gate vs run 34768256297's recorded evidence at `15fd63aff…`, with and without an ack; paste both lines.
- [ ] 4.2 Real gate vs PR #8393's exact bytes in a scratch checkout of `d64430c26`, with and without the ack; paste both lines.
- [ ] 4.3 Real gate vs a hand-written file naming dry run 33886787297 → `HOLD [RUN_NO_EVIDENCE_ARTIFACT]`; paste it.
- [ ] 4.4 Sync `main`; if #8393 has merged, append the ack line in its own evidence-only commit (this PR touches no hash-bound file, so both Guard 4 arms pass). If not, note in #8393 that it must carry the ack.
- [ ] 4.5 File the blocker issue (`actions: read` + `GH_TOKEN` at four call sites, the tri-state call-site conversion with its parity-test regex, the freshness-step reorder), milestone `Phase 4: Validate + Scale`, linked from roadmap L27 and #8361, marked blocking the L27 dispatch; cite it from every `RUN_RATE_LIMITED` message.
- [ ] 4.6 `gh issue edit 8010 --milestone "Phase 4: Validate + Scale"`.
- [ ] 4.7 Full battery (`scripts/test-all.sh` shards touched by the diff) and the AC sweep.
