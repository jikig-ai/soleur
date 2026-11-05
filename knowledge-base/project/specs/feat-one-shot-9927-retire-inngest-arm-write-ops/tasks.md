# Tasks - retire the Inngest cutover write ops that need the arm-write token (Ref #9927 item 8)

Plan: `knowledge-base/project/plans/2026-11-05-chore-retire-inngest-arm-write-cutover-ops-plan.md`.
Hard limits: no revoke, scope-down or deletion of the arm-write token; `inngest-arm-write-token.tf` stays (comment-only edit); G2e pin untouched; no `inngest-host-replace` dispatch and no manual terraform apply; `Ref #9927`, never `Closes`.

## Phase 0 - Preconditions (read-only)

- 0.1 Re-read `INNGEST_CUTOVER_FLIP` and `INNGEST_LUKS_CUTOVER` on `soleur-inngest/prd`; record value and UTC time. STOP if either is not `done`.
- 0.2 `git fetch origin main`; check whether #12100 and #12064 merged; rebase and recompute counts if so.
- 0.3 Only if CI turns red on `cla-signed-author-gate.test.sh` T15: ship the ~4-line identity fix as its own PR first.
- 0.4 `wc -c` baseline of `apply-web-platform-infra.yml` (489,718).
- 0.5 Capture the real `doppler secrets --only-names --json` and absent-key `get` shapes (names only) as synthesized fixtures.

## Phase 1 - Failing tests first

- 1.1 Create `apps/web-platform/infra/inngest-host-replace-preflight.test.sh` (Guard 1 behavioural rows with stubbed `doppler`/`jq` under `env -i` and a symlink-farm PATH, fixed-string step-name match, `bash <tmpfile>` not `eval`; Guard 3 static pins incl. `plaintext_value` equals its own token's `.key` and by-reference project/config). RED.
- 1.2 Add the Guard 2 literal-set and absence block to `cutover-inngest-workflow.test.sh`. RED.
- 1.3 Register the new suite as `scripts/lint-orphan-test-suites.sh` and `scripts/lib/test-affected-paths.sh` require.

## Phase 2 - Terraform (file only)

- 2.1 Create `apps/web-platform/infra/inngest-flip-read-token.tf` (token `inngest-ci-flip-read`, `access = "read"`, by-reference project/config; repo secret `DOPPLER_TOKEN_INNGEST_FLIP_READ`; rotation comment with both `-target`s).
- 2.2 Add both `-target=` lines to the default per-merge allow-list in `apply-web-platform-infra.yml`, each beside its arm sibling (never between `doppler_secret.inngest_redis_luks_key` and `supabase_project.prd`); not the `inngest_host` job.
- 2.3 Comment-only updates in `inngest-arm-write-token.tf`: the `CONSUMERS` block, the file header, the "Human ack" paragraph and the environment-secret comment.
- 2.4 Recompute `TEST_FLOOR` in `terraform-target-parity.test.ts` only if a `test(` is added.

## Phase 3 - Preflight rewrite

- 3.1 Rewrite the step: leading xtrace refusal (exit 78); empty token exits 1; blind names-list (missing `doppler`/`jq`, rc != 0, empty output, invalid JSON, non-object or empty object) exits 1; key absent warns; present-and-get-fails exits 1; stderr discarded; remove `continue-on-error`; error text names the secret and the re-run-the-push-apply remedy.
- 3.2 Move the rationale prose to the runbook; dry-run `wc -c` first; stay at or below 489,718.
- 3.3 Zero `DOPPLER_TOKEN_INNGEST_ARM` references left in the workflow, comments included.

## Phase 4 and 5 - Retire arm, reflush, luks-cutover and prune tests (ONE commit)

- 4.1 `cutover-inngest.yml`: drop three options; narrow token ternary and export `if:` to `rollback`/`resume`; environment ternary to `rollback`/`resume`/`backup`; drop `FLUSH_LATCH_SINCE`; fix comments.
- 4.2 `scripts/cutover-inngest.sh`: delete the three arms; delete a helper or global only after per-name `git grep` shows no caller; keep `confirm_flip_state` and the resume/rollback helpers.
- 4.3 Reword live `op=arm` pointers in `execute)`, `rollback)` and `resume)`.
- 5.1 Prune `cutover-inngest-workflow.test.sh`; fix the arm-token wiring asserts; delete (not empty-pass) the non-vacuity asserts on emptied extractions; recount the shared-reader call sites.
- 5.2 Recompute `_EXACT_FLOOR` from the `STALE FLOOR` FATAL line.
- 5.3 `test-argv-bearer-sweep.sh`: remove the arm battery; recompute the HMAC-copy count only if needed.
- 5.4 Update `lint-shell-capture-exit.baseline.txt` and `fixture-relative-assert.baseline.txt`; re-derive `ci-pr-affected-audit.accept.tsv` anchors; content-anchor the `lint-hcloud-token-readonly-no-fallback.sh` citation.
- 5.5 Run the whole-tree ratchets (test-all legs, parity, file-size, c4-count-parity, `lint-infra-no-human-steps.py --changed`).

## Phase 6 - Docs and records

- 6.1 Runbooks: `inngest-server.md` (incl. a repair line for a dead or missing flip-read token), `inngest-luks-cutover-6894.md`, `infra-credential-tiers-8209.md`.
- 6.2 ADR-282 addendum (append-only).
- 6.3 C4: rewrite the `github -> hetzner` edge text, add ONE `github -> doppler` edge covering both CI credentials into `soleur-inngest/prd`, regenerate `model.likec4.json`, run the C4 tests.
- 6.4 PR body first lines (production-mutating merge; departures; no benefit until revoke); file the tracking issue for a replacement write-credential design with the F2 precondition and `Ref #9927`.

## Phase 7 - Post-merge (read-only)

- 7.1 Confirm the merge-commit push apply (`--event push --commit <sha>`, `conclusion=success`) created exactly the two resources; on a partial apply re-run it, never `-replace` the token.
- 7.2 Confirm the repo secret exists and the live token metadata is `inngest-ci-flip-read` / `read`.
