# Decision challenges: argv-bearer sweep S4 (headless plan run, 2026-10-09)

Taste and user-challenge items from the planning pass. Each states the default the plan took and the alternative the lead may choose. None blocks the work phase except item 1's notice, which is the brief's own requirement.

## 1. The merge fires the production apply, the `deploy_pipeline_fix` replacement and the release deploy (user-challenge, notice required)

- Brief: "stop and get explicit operator notice before ship, and verify the apply outcome afterwards".
- Finding: `push-infra-config.sh` is hashed in `terraform_data.deploy_pipeline_fix.triggers_replace`, so the merge replaces that resource and runs the converted script as a provisioner; `apps/web-platform/**` fires the web release whose deploy job is itself converted; `apply-inngest-rls.yml` lists its own file and applies to the Inngest production database.
- Default taken: no kill-switch; the apply and the release run on the merge and are verified without SSH (a live first run of the most important converted script).
- Alternative: add `[skip-web-platform-apply]` and/or `[skip-deploy-fix-apply]` on their own lines in the merge commit body. Skips the apply (no live proof; drift reports until a sanctioned apply); does not deliver the files.

## 2. Single PR for S4 versus separating the infra-path commits (user-challenge)

- Brief: one slice per PR, S4 only.
- Default taken: one PR, commit layering isolates the two infra-path commits (6 and 7).
- Alternative: move commits 6 and 7 (every file the apply keys on) to a follow-on PR so the first PR fires only the web release and the RLS self-apply. Cost: S4 would span two PRs and the held-back S3 sites would wait.

## 3. Checkout-free production jobs gain a one-file sparse checkout (user-challenge)

- Finding: `web-platform-release` `deploy` and `release-outcome`, and `deploy-inngest-image` `deploy`, deliberately have no checkout (comments, ADR-072 and ADR-217); the library must come from the job's own checkout (ADR-280).
- Default taken: `actions/checkout` pinned, `persist-credentials: false`, `sparse-checkout: scripts/lib/bearer-curl.sh`, cone mode off, as the first step; a checkout outage now fails the deploy job at step 0 (loud, prod stays on the previous build), and a `release-outcome` checkout failure would suppress that job's operator email (its Sentry event is independent).
- Alternative: convert those five sites inline (S2 pattern, five more copies of the guard each with a parity row), keeping the checkout-free design.

## 4. Two sites take the inline wrapper instead of the library (taste)

- `workspaces-luks-cutover.yml`: its suite's census forbids any repo script executed in the token-holding step. `infra-config-verify.sh`: its suite pins a read-only command allowlist and builds a skeleton with no `scripts/lib`.
- Default taken: inline wrapper plus the canonical python3 snippet (parity audit grows from 17 to 19 copies).
- Alternative: library plus widening the census/sweep allowlists (a weaker pinned property in two security-relevant suites).

## 5. Honest-class pre-guards beyond the brief (taste, inferred scope)

- The brief names the inngest-health `probe` pre-guard. The same defect class exists at `webhook_liveness` (refusal would read as `listener_state=down`), `infra-config-verify.sh` (would print "listener DOWN") and `pre_frame` (`unreachable`). Default: guard all four. Alternative: guard only the probe and accept the false diagnostics.

## 6. `ci-deploy.sh` leaves the slice (informational)

- #9805 (`8729cc0dfa`) already moved its fan-out HMAC key to a python3 child; Rule E reads it clean. The tracker row is stale and is corrected on the tracker.

## 7. Items deliberately not taken (scope)

- #9757 item 1 (two held-back HMAC arms in `scripts/cutover-inngest.sh`): needs `cutover-inngest-workflow.test.sh` edited; that file and `cutover-inngest.sh` are in open draft #9877's diff, and the brief's S4 list does not name them. Stays on #9757.
- #9757 item 2 (heartbeat-URL path secrets), #9755, #9756, and the two agent-executed Markdown files teaching the argv HMAC form (plugin files would add a plugin release run): unchanged owners.
- Alternative: take the two cutover arms in S4 after #9877 merges; S4 already fires the apply, so the marginal exposure is nil.

## 8. Git push credential form (taste)

- `bump-inngest-bootstrap-pin.sh`: default is a per-command `GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY_0`/`GIT_CONFIG_VALUE_0` extra header (no userinfo in the URL), measured on the runner's git in Phase 0. Alternative: a `GIT_ASKPASS` helper script (a new file in the repo; reads the token from the environment).

## 9. Optional extra proofs that need the lead's go (taste)

- A throwaway `pull_request` job printing shape-guard pass/fail for GitHub-only secrets (Resend, Supabase): default not run; vendor formats plus the first live run decide.
- A read-only dispatch of `scheduled-inngest-health` on the branch before merge: default not dispatched (the probe can dispatch a restart if inngest is down); it is dispatched after merge.
