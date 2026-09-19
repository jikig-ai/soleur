# Tasks — make `git_data_rung2_rehearsal_gate` load-bearing (#8010)

Derived from [the plan](../../plans/2026-09-19-fix-git-data-rung2-gate-load-bearing-plan.md) after plan review. Phase order is load-bearing: the tests are written RED before the gate, and the gate's contract lands before its consumers are re-pointed.

## Phase 1 — RED: the gate's refuse paths

- [ ] 1.1 Gate suite (`tests/scripts/test-git-data-birth-readiness-gate.sh`): `export SOLEUR_TEST_MODE=1 SOLEUR_RUNG2_RUN_FETCH="$TMP/api-fetch.sh" SOLEUR_RUNG2_RETRY_SLEEP=0` at suite top (export, not a prefix — `mutate_r2`/`mutate_g` run in child shells).
- [ ] 1.2 Add the `$TMP/api/<path-suffix>` stub store and `api-fetch.sh` (body file + `.status` file; a distinct "no entry" shape for transport failure; prints body then status, no headers).
- [ ] 1.3 Add `_stub_run <id> key=value…` (`head_sha`, `conclusion`, `status`, `path`, `event`, `head_branch`, `created_at`, `http`, `artifacts`), defaulting artifacts to one `git-data-rung2-boot-evidence` entry.
- [ ] 1.4 Seed the existing arms: run id `1` (what `ok.env` names) and `17250000001`, plus `_G_URL`/`_G_URL2`, each with `head_sha` = the matching fixture's pre-evidence commit so the archive re-hashes to `R2_SHA`.
- [ ] 1.5 Extend `_r2_evidence_write` with `$6=sentry_verdict` (default `CLEAN`) and `$7=ack`.
- [ ] 1.6 Write the S-table rows S1–S12 (Sentry verdict + ack grammar).
- [ ] 1.7 Write the R-table rows R1–R13 (fetch failures, rate limit, anonymous retry, id parsing, field checks).
- [ ] 1.8 Write A1–A5 (artifacts discriminator, including the dry-run shape and the age branch).
- [ ] 1.9 Write H1–H6 (head_sha reachability, hash mismatch, the root-dir fixture, the ABORT token, the order pin).
- [ ] 1.10 Write T1 (`TOOLING_MISSING` before any stub call) and E1/E2 (the `::error::` emitter under `GITHUB_ACTIONS`).
- [ ] 1.11 Write the Guard Contract mutation and harness rows for Guards 1–3, including Guard 1 row 12 (the seam double gate, proven with a marker file and an unroutable host — never a live call).
- [ ] 1.12 Raise `_FLOOR=150` by hand to the new total and itemise it in a `RAISED 150 -> N (#8010), ITEMISED:` block.
- [ ] 1.13 Capture suite (`tests/scripts/test-git-data-rung2-evidence-capture.sh`): give the producer/consumer arm (`gate_out="$(git_data_rung2_rehearsal_gate …`) the exported seam and a stub whose `head_sha` is the fixture's own commit — it calls the real gate today and would otherwise go red and lose offline operation.
- [ ] 1.14 Write C1–C6 (host/run coupling, the 24 h liveness argv, ARTIFACT 4's liveness line, the resolved `--end`, `NOT_RUN`) and raise `_FLOOR=107` with its itemised block.
- [ ] 1.15 `apps/web-platform/infra/git-data-rung2-rehearsal.test.sh`: one arm asserting exactly one `ACK REQUIRED` / `ACK NOT REQUIRED` line.
- [ ] 1.16 Run all three suites plus `plugins/soleur/test/terraform-target-parity.test.ts` and the `fixture-relative-assert` baseline; commit RED and record the count.

## Phase 2 — GREEN: the gate

- [ ] 2.1 `_git_data_rung2_fetch` — curl with `--disable --noproxy '*' -sS --max-time 20 -w '\n%{http_code}'`, a bash-array auth header, 2 attempts on 5xx/transport, `SOLEUR_RUNG2_RETRY_SLEEP`, fast-fail on rc 6/7, one anonymous retry on a non-rate-limit 401/403, stderr to a temp file.
- [ ] 2.2 `_git_data_rung2_check_run` — `jq` field checks (`.id|tostring`, `.path`, `.event`, `.head_branch`, `.status`, `.conclusion`, `.head_sha`) with their tokens; rate limiting read from status + body.
- [ ] 2.3 `_git_data_rung2_hash_at_sha` — `cat-file -e`, then `git archive <sha>:<repo-rel-dir>` (or `<sha>:` at the repo root) with attributes disabled into a `mktemp -d` removed inline on every return path; `RUN_HASH_MISMATCH` / `RUN_HASH_UNCOMPUTABLE`.
- [ ] 2.4 `_git_data_rung2_check_artifacts` — exact name match, `expired` allowed, the 90-day age branch.
- [ ] 2.5 Wire steps A–E into `git_data_rung2_rehearsal_gate` after Guard 4, in the pinned order; add the two cardinality loops and the verdict `case`; add the run-id parser shared by Guard 1 and the ack check.
- [ ] 2.6 Add the `::error::` emitter for could-not-measure tokens under `GITHUB_ACTIONS`; extend the RELEASED line.
- [ ] 2.7 Update the Guard 4 header residual paragraph and add the runbook pointer to the `STALE EVIDENCE` message.
- [ ] 2.8 Re-run the suites to green; `shellcheck`.

## Phase 3 — GREEN: capture, workflow, probe, docs

- [ ] 3.1 Capture: the `--host-name`/`--evidence-url` suffix refusal (exit 64).
- [ ] 3.2 Capture: `--stats-period 24h` at the `--liveness` call site (no helper); keep the fatal read run-pinned.
- [ ] 3.3 Capture: the never-consulted branches write `NOT_RUN`.
- [ ] 3.4 Capture: ARTIFACT 4 gains the liveness query line, the HOLD sentence and the pre-reset scope note.
- [ ] 3.5 Capture: the reset arm records its resolved `--end` instead of the literal `<now>`.
- [ ] 3.6 Workflow: the single post-reset `ACK REQUIRED` / `ACK NOT REQUIRED` line, CR/LF-stripped; the reordered evidence-landing block (ack before `git add`); the wait-for-`success` sentence. Keep the pinned PASS/FAIL/WRAPPER headings.
- [ ] 3.7 Probe: one sentence in `git-data-reboot-evidence-landed-8210.sh`'s TRANSIENT message naming a `RUN_*`/`SENTRY_*` instrument failure.
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
