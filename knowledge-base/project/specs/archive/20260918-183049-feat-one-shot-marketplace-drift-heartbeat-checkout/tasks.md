# Tasks: fix scheduled-marketplace-drift heartbeat local-action resolution

Plan: `knowledge-base/project/plans/2026-09-18-fix-marketplace-drift-heartbeat-local-action-resolution-plan.md`
(AC numbers below refer to that plan's `## Acceptance Criteria`).

## Phase 0: Probes (scratchpad only)

- [x] 0.1 Re-run the yaml-parsed `uses:` census over `.github/workflows/`; confirm the single RED is `scheduled-marketplace-drift.yml:drift-check` (baseline for 1.2)
- [x] 0.2 Acquire actionlint per `ci.yml`'s pinned + sha-verified install step into the scratchpad; run `-shellcheck= -pyflakes=` on the final workflow file; record the +1 `[action]` delta for the PR body and for a comment on #7042
- [x] 0.3 Gate 0: `GET /api/0/organizations/jikigai-eu/monitors/scheduled-marketplace-drift/` → 200 with `config.schedule == "37 6 * * *"`; then `checkins/?per_page=5` → `[]`; record both timestamps for the PIR
- [x] 0.4 Confirm `drift-check` inherits workflow-level `contents: read` (no job-level override) so a 403/404 on `$/` resolution is diagnosed as a token cause, not syntax

## Phase 1: Guard, RED first

- [x] 1.1 Write `scripts/lint-workflow-local-action-checkout.test.sh` from the Guard Contract
  - [x] 1.1.1 RED rows 1–12 (row 4 = synthesized production shape in a matrix job; row 8 = dispatch sub-cases each asserting rc 2 + named file/floor; row 9 = copy live tree, DELETE the checkout from `scheduled-domain-model-drift.yml:drift-check`, re-parse to prove placement, expect RED by name with finding count = unmutated + 1; row 10 commented-out checkout; row 11 `.yaml`; row 12 nested `./` in a composite)
  - [x] 1.1.2 Must-PASS rows (a)–(i) (b carries `with:`; h = unconditional + conditional checkout; i = filler tree alone is clean)
  - [x] 1.1.3 Harness rows: pass/fail canary; sibling tail verbatim (`verdict_ok`, literal `FAIL_FLOOR_MIN=<n>` = assertions executed on a green run, directly above the `-lt` test, FATAL `exit 2`)
  - [x] 1.1.4 Build `$TMP/filler` once; `reset()` = `rm -rf "$TMP/wf"; cp -r "$TMP/filler" "$TMP/wf"` (runtime band ~1.5 s)
  - [x] 1.1.5 Run: every case fails because the SUT does not exist
- [x] 1.2 Write `scripts/lint-workflow-local-action-checkout.py` (header: WHY, THE RULE, `$/…@` reject, named non-properties, `MIN_SAME_REPO_STEPS=30`, DIRECTION OF ERROR, measured sentence, posture, `Usage:`/`Exit:` lines; exit 0/1/2; `::error file=` findings; `run-body-syntax` walk; second surface over `.github/actions/*/action.yml`); unit suite green; live scan → exactly one finding (the marketplace-drift job)
- [x] 1.3 Register unit + `-live` pair in `scripts/test-all.sh` beside `lint-workflow-issue-write-scope` with the "both halves are required" comment; `bash scripts/lint-orphan-test-suites.sh` and `bash scripts/guard-vacuity-floor.test.sh` pass

## Phase 2: The fix

- [x] 2.1 `.github/workflows/scheduled-marketplace-drift.yml`: `uses: $/.github/actions/sentry-heartbeat`; rewrite the two comment blocks to present-tense facts + `Set up job` dependency + no-token-on-disk property + posture + `SOLEUR-DEBT:` marker naming the four `./`-anchored consumer censuses + rhysd/actionlint#711 citation; `permissions:` byte-identical (AC1, AC2, AC3)
- [x] 2.2 `.github/actions/sentry-heartbeat/action.yml`: add the `-w '\nsentry-heartbeat: http_code=%{http_code}\n'` line to the curl; header paragraph on `$/` for checkout-free jobs (described in words — must not contain the literal `http_code=%{http_code}`); nothing else changes (AC8)
- [x] 2.3 Live lint → 0 findings, OK line by shape (AC4); unit suite green (AC6); AC5 RED proof against the merge-base file; AC7 registration greps

## Phase 3: Pre-merge verification from the branch

- [x] 3.0 (work-time deviation) First dispatch, run 35360150848: `$/` resolved, `Set up job` failed extracting the archive on the committed dangling symlink `test/fixtures/orphan-proc-dangling/4242/cwd`; removed both dangling links (no runtime consumer; AC30b synthesizes them), README amended, re-dispatched as run 35361236920 — see the plan's 2026-09-18 addendum

- [x] 3.1 Push; `gh workflow run scheduled-marketplace-drift.yml --ref feat-one-shot-marketplace-drift-heartbeat-checkout`; bounded poll with the Monitor tool
- [x] 3.2 Read the `drift-check` job log: 0 `Can't find 'action.yml'` lines; `sentry-heartbeat: http_code=2xx` (primary arm); `outcome=success`. Setup-failure arm: `startup_failure` / `Set up job` failure / HTTP 422 → fallback trigger after 0.4 rules out a token cause (AC9)
- [x] 3.3 Read back via `doppler run -p soleur -c prd --only-secrets SENTRY_IAC_AUTH_TOKEN -- sh -c 'curl … $SENTRY_IAC_AUTH_TOKEN …/checkins/?per_page=5' | jq .`; require a row with `dateCreated` after the dispatch and the computed status; capture `id`, `status`, `environment`, `dateCreated` (AC10)
- [x] 3.4 (not needed — the `$/` form resolved on run 35361236920; fallback arm unused) Only if `$/` failed to resolve: pin `jikig-ai/soleur/.github/actions/sentry-heartbeat@<40-hex main sha>`, push, repeat 3.1–3.3, file the `$/`-migration tracking issue, note the arm in the PR body
- [x] 3.5 Note the armed-monitor side effects: merge the same day or expect (and let auto-close) a Sentry missed-check-in issue against `main`'s still-dark copy; an `error` first check-in opens a Sentry issue immediately — diagnose the unrelated failure and name the status in the PR body

## Phase 4: PIR amendment (after 3.3 has a timestamp)

- [x] 4.1 Frontmatter: ISO `recovery_at` with `# measured: Sentry cron monitor check-in id <id> via GET …/checkins/` on the value line; extended `incident_window` (keep the PIR's own `#7473` token); `status: resolved  # amended 2026-09-18 …`
- [x] 4.2 `> **AMENDED 2026-09-18` banner under the frontmatter: claimed vs measured (36/36 resolution errors, 33/36 green, `[]` until the branch dispatch), mechanism, why the repair's verification could not see it, dark-window arithmetic, fix + guard; state that the `recovery_at` row is a branch-dispatch check-in and the `main` row is AC16 in the PR body
- [x] 4.3 `## What would have caught it`: add the second gap, now closed by the lint
- [x] 4.4 `## Related`: PR #8313, the 2026-09-18 devin-docs-drift repair, the PR #8311 learning path, #8282; Action Items sentence = `*No action items — incident fully resolved by PR #8313 (2026-09-18; the source PR #7504 did not recover the monitor — see the AMENDED banner); no residual work.*`; `ship-pir-action-items-gate.sh <pir>` → pass (AC12)
- [x] 4.5 `python3 scripts/lint-infra-no-human-steps.py <pir>` → OK (courtesy check); AC11 greps; the PIR carries row values + run URL only, never the Doppler token-scope map

## Phase 5: Ship-time artifacts

- [x] 5.1 PR body: "Why `$/` and not a checkout" option table; AC9 run URL + arm; AC10 row; actionlint delta; #7520/#7524/#8282 untouched; the `-w` User-Challenge from `decision-challenges.md` (AC13)
- [x] 5.2 Post the actionlint +1 as a comment on #7042
- [x] 5.3 `/compound`: learning only if novel — the two residue points, citing the existing learnings and the PR #8311 path in prose
- [x] 5.4 Diff-scope check (AC14); local greens (AC15)

## Phase 6: Post-merge (pipeline-executed, no operator step)

- [x] 6.1 Reuse the run `/ship`'s modified-workflow validation dispatched on `main` (dispatch only if none); 0 `Can't find` lines; `http_code=2xx` (primary arm)
- [x] 6.2 `checkins/` read (`--only-secrets SENTRY_IAC_AUTH_TOKEN`) with the run's `createdAt`: ≥ 1 row after it. DONE cites the row, never the conclusion (AC16). No skill reads this block — the runner executes it by hand; the durable guard afterwards is the monitor's missed-check-in issue

## Evidence (closed 2026-09-20)

PR #8313 merged 2026-09-19T03:37:18Z as `a50cf9ad2382b7a3960b4571c8b0704b97d0b6df` (tag
`web-v0.279.5`); production `/health` reports that `build_sha` with `supabase: connected`.

- **5.1** — PR body carries the option table, the AC9/AC10 rows, the actionlint delta, the
  `#7520/#7524/#8282 untouched` statement and the `-w` User-Challenge.
- **5.2** — measured +1 (170 → 171 over `.github/workflows/*.yml`, CI's pinned actionlint 1.7.7,
  merge commit vs its first parent; the one new line is the `$/` *ref is missing* `[action]`
  finding). Posted: <https://github.com/jikig-ai/soleur/issues/7042#issuecomment-5739062992>.
- **5.3** — `2026-09-18-a-pir-recovery-written-as-an-expectation-and-an-alarm-that-was-never-armed.md`.
- **5.4** — diff scope re-derived 2026-09-20 from the merge itself
  (`git diff --name-only a50cf9ad2^1 a50cf9ad2`): 19 files, all inside the planned surfaces —
  the workflow + composite, the parity test, the two new `scripts/` guards plus `test-all.sh`
  and `marketplace-drift-check.test.sh`, the PIR/learning/runbook/plan/spec docs, and the
  dangling-fixture removal with its README. CI verified that exact tree. The local battery was
  deliberately **not** run (operator decision): only the untouched `infra` group differs locally.
- **6.1 (resolution, primary arm)** — `workflow_dispatch` run 35419097145 on `main`: `drift-check`
  log has **0** `Can't find` lines and no checkout step, `Set up job` resolved
  `jikig-ai/soleur@a50cf9ad2…` through `$/`, and the step printed `sentry-heartbeat: http_code=202`.
- **6.2 (resolution)** — check-in `357ad056-ccfa-4b6c-8c0c-8b4bb2dde5f0` (`ok`, `production`) at
  2026-09-19T03:44:21Z, after that run's `createdAt` 03:37:59Z.
- **6.2 (liveness — the claim a dispatch cannot make)** — two `schedule`-event runs have since
  delivered: run 35440135873 → check-in `b86e28dd-f6b0-4293-a90f-cb720d894b52` (2026-09-19T11:27:55Z)
  and run 35508695589 → `3e307148-2590-4ecb-88fb-7138dc4d2c5b` (2026-09-20T11:46:41Z), the latter
  re-read from `drift-check` as `http_code=202` with 0 `Can't find` lines. The learning file
  separates these two proofs; this row is the scheduled one.

The two scheduled ticks fired 4h49m and 5h08m after the `37 6 * * *` cron, with
`created_at == run_started_at` on both runs — GitHub's delivery of the `schedule` event lagged,
no runner queueing involved. Both clear `checkin_margin: 360`, the later one by ~52 minutes.
See the PIR addendum for what that headroom implies.
