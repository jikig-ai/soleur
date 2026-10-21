# Tasks — feat-one-shot-10643-tf-plan-504-retry

Derived from `knowledge-base/project/plans/2026-10-20-fix-apply-web-platform-infra-cf-504-retry-plan.md` (post-review). Closes #10643.

## Phase 1: Setup & provider retry knobs

- [x] 1.1 In `apps/web-platform/infra/main.tf`, add `retries = 6`, `min_backoff = 15`, `max_backoff = 120` to each of the six `provider "cloudflare"` blocks (default :150, `zone_settings` :158, `rulesets` :189, `bot_management` :201, `r2` :211, `pages` :222), each carrying a comment citing #10643, the ~7.75-min/request backoff math, and the v5-era `max_retries` rename warning.
- [x] 1.2 In `apps/cla-evidence/infra/main.tf`, add the same trio + comment to the single `provider "cloudflare"` block (:25).
- [x] 1.3 Verify `terraform fmt -check` clean on both files; re-run the scratch-dir `terraform providers schema -json` probe on `cloudflare/cloudflare = 4.52.7` and confirm `retries`, `min_backoff`, `max_backoff` keys are present.

## Phase 2: Drift guards

- [x] 2.1 Create `apps/web-platform/infra/cloudflare-provider-retry.test.sh`: enumerate every `provider "cloudflare"` block in `apps/web-platform/infra/main.tf` (fail if the census finds zero) and assert each block contains all three attributes with values above the v4 defaults (3/1s/30s). Auto-registered by the `run-registered-suites.sh` glob.
- [x] 2.2 Extend `apps/cla-evidence/infra/main.test.sh` with the same presence/value assertions for its provider block.
- [x] 2.3 Drive the new suite RED against each Guard Contract mutation row (drop one attribute from one block; add an unknobbed seventh alias; zero the block census; mutate the suite's expected-name constant to `max_retries`) and confirm the reorder/respacing row stays PASS — before commit.

## Phase 3: Runbook & verification

- [x] 3.1 Add one line to `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-red-run.md`: provider calls now retry 5xx up to ~8 min/request; a plan red on `HTTP 504` post-change means the degradation outlasted that budget — re-running the workflow is the documented remedy.
- [x] 3.2 Run the verification bundle: `bash apps/web-platform/infra/cloudflare-provider-retry.test.sh` green; `bash apps/cla-evidence/infra/main.test.sh` green; `git grep -cE 'retries[[:space:]]*='` across both `main.tf` files = 7.
- [x] 3.3 Confirm `.github/workflows/apply-web-platform-infra.yml` is unmodified and no `-target` list changed (`terraform-target-parity.test.ts` unaffected).
