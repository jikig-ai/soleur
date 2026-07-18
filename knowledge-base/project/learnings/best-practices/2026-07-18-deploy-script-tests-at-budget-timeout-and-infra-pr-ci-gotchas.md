# deploy-script-tests at-budget timeout diagnosis + three infra-PR CI gotchas (#6649/PR #6650)

## Problem

Resuming PR #6650 (the #6649 LUKS header-escrow wiring), the full CI suite surfaced three
independent failures the local touched-file loop never sees, plus a diagnostic trap on a
CANCELLED (not FAILED) required check.

## 1. `deploy-script-tests` cancels mid-suite — a pre-existing at-budget timeout, not your diff

`deploy-script-tests` (in `.github/workflows/infra-validation.yml`) CANCELLED twice on the branch,
both times with GitHub's `##[error]The operation was canceled.` landing at **step 61**
(`scan-workflow-mutation.test.sh`, which took only ~8s). The instinct is to blame step 61 (it was
spewing `printf: write error: Broken pipe` — but that meta-test *intentionally* arms SIGPIPE; the
spew is by-design).

**The cancel location is a red herring.** The job has `timeout-minutes: 8` (480s), and the
`Run ci-deploy.sh tests` step **alone measures ~407s** — real `sleep`s from #6525's transient-retry
backoff (`"2 4"` = 6s) + lease/lock/drain timing + #6475's soak path. That consumes ~85% of the
budget, leaving ~73s for the other 70 steps. The wall-clock simply runs out **wherever execution
happens to be** — step 61 in this case. The job is at-budget on `main` itself, so it flakily times
out on any slightly-slow runner, for *every* infra PR.

**Diagnostic that works:** per-step DURATIONS, not the cancel location:
```bash
gh api repos/<owner>/<repo>/actions/jobs/<job_id> \
  --jq '.steps[] | select(.started_at and .completed_at)
        | [((.completed_at|fromdate)-(.started_at|fromdate)), .number, .name] | @tsv' \
  | sort -rn | head
```
The single 407s step is obvious; everything else is ≤8s.

**Attribution (don't blame your own added step):** a step your branch ADDED that runs *after* the
cancel point cannot be the cause. Confirm with:
```bash
base=$(git merge-base origin/main HEAD)
git diff "$base"...HEAD          -- .github/workflows/infra-validation.yml | grep -E '^\+.*- name:'  # what you added
git diff "$base"..origin/main    -- .github/workflows/infra-validation.yml | grep -E '^\+.*- name:'  # what main added since branch
```
If both are empty/after-the-cancel, the budget was already blown on `main` — a re-run won't help
(it cancelled again, deterministically).

**Fix:** bumped `timeout-minutes: 8 → 12` (honest interim — root cause understood, not a hidden
hang) and filed #6665 to broaden the existing `MOCK_SLEEP_NOOP` gate (`ci-deploy.test.sh:673`) so
the timing-non-fidelity tests stop paying real wall-clock, returning the budget to a tight 8. The
architecture review preferred a step-level `timeout-minutes` on the long-pole step over inflating
the whole job ceiling — worth considering when #6665 lands.

## 2. A no-default TF root variable breaks the existing `terraform test` file

Adding `var.cf_api_token_r2` (no default, `sensitive`) to `variables.tf` turned
`validate (apps/web-platform/infra)` RED with:
```
Error: No value for required variable … variable "cf_api_token_r2" … has no set value.
```
`terraform test` requires **every** root variable to be resolvable. The fix is a synthetic dummy in
the tftest's `variables {}` block, mirroring the sibling `cf_api_token*` stubs:
```hcl
# apps/web-platform/infra/tests/web-hosts-eu-pin.tftest.hcl  (variables { … } block)
cf_api_token_r2 = "0123456789012345678901234567890123456789"
```
Keep alphabetical order + `=`-column alignment (`terraform fmt -check` gates it). This is invisible
to `terraform validate`; only `terraform test` (run by the `validate` CI job) catches it.

## 3. Plan mechanism prose trips `lint-infra-no-human-steps.py`

The `lint-bot-statuses` job runs `scripts/lint-infra-no-human-steps.py` over `knowledge-base/project/plans/`
(+ specs, runbooks, ADRs). Deferred-orchestrator / mechanism prose that co-occurs an actor +
terraform/SSH/reboot imperative (premise-validation tables, apply-path bullets, impl-phase blocks)
is flagged as a "prescribed human-run infra step". Wrap each such block in the sanctioned region
(HTML-comment form required), matching the sibling #6604 plan idiom:
```
<!-- lint-infra-ignore start: <why this is mechanism/deferred-orchestrator prose, not a runtime step> -->
… table / bullets / phase block …
<!-- lint-infra-ignore end -->
```
Keep the regions minimal — do NOT swallow sections that should stay linted (User-Brand Impact,
Observability, etc.). Verify locally: `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`.

## Key insight

The full-suite exit gate exists precisely for failures the touched-file loop cannot see: an
existing `terraform test` broken by a new root var, an existing lint scanning your new plan prose,
and a shared job whose budget your PR merely tips over. And on a **CANCELLED** (vs FAILED) required
check, the cancel *location* is not the cause — the slowest *step* is; read per-step durations, and
attribute against the merge-base diff before touching anything.

## Session Errors

- **`validate` RED — no-default TF var absent from the tftest variables block.** Recovery: added a
  synthetic dummy. Prevention: when adding a no-default root var, grep `infra/tests/*.tftest.hcl`
  for the sibling `variables {}` block and stub it in the same commit (this learning).
- **`lint-bot-statuses` RED — plan mechanism prose tripped `lint-infra-no-human-steps.py`.**
  Recovery: `lint-infra-ignore` region wraps. Prevention: run the linter locally on new infra-plan
  prose; wrap mechanism blocks (this learning).
- **`deploy-script-tests` CANCELLED ×2 — pre-existing at-budget timeout.** Recovery: timeout 8→12 +
  #6665. Prevention: per-step-duration diagnostic + merge-base attribution (this learning); the real
  fix is #6665.
- **The branch's OWN SIGPIPE `grep -q` learning was applied to the test but NOT the production
  script.** Recovery: review converted `printf … | grep -Eq` → `grep -Eq … <<<"$var"` in
  `workspaces-cutover.sh`. Prevention: when a session captures an anti-pattern learning, `git grep`
  the anti-pattern across ALL sites in the SAME PR (test AND production), not just the file that
  first surfaced it — "learning captured" ≠ "learning swept".
- **Foreground `sleep` + `run_in_background` CI-poll both blocked by harness gates.** Recovery: used
  the Monitor tool for CI waits. One-off — the rules (`hr-monitor-not-run-in-background-for-polling`)
  were followed once recognized; no change needed.
- **Playwright MCP disconnected mid-session.** One-off (environment). Noted because the post-merge
  R2-cred mint (a Cloudflare dashboard step) will need Playwright in a session where it is connected.

## Tags
category: best-practices
module: apps/web-platform/infra
