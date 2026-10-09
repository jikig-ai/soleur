# Decision challenges — feat-one-shot-9252-zot-pin-bump-ghcr-deny

Appended by the plan phase (headless). `ship` renders these into the PR body and files the action-required issue.

## 2026-10-08 D1 — merge-time contact with web-1 / web-2 versus "do not touch the web-1 or git-data hosts" (taste)

- **Operator's stated direction (default):** edit the hosts-file deny at every byte-identical site, including copy B (`server.tf` locals) and keep the bump's comment claim in `ci-deploy.sh` current; and "do not touch the web-1 or git-data hosts".
- **Conflict found:** both files feed `triggers_replace` of SSH `terraform_data` resources (`zot_consumer_probe_install` on web-1, `deploy_pipeline_fix` and `deploy_pipeline_fix_web2` on web-1/web-2). `apply-web-platform-infra.yml` and `apply-deploy-pipeline-fix.yml` read `active` since 2026-10-08T19:07Z, so a merge fires both push applies, which would re-run those provisioners over SSH.
- **Plan's default:** keep the operator's constraint. One branch commit message carries `[skip-web-platform-apply]` and `[skip-deploy-fix-apply]` each on its own line, so neither push apply runs for this merge. The registry replace is a different workflow and is unaffected. Running-host delivery of copy B waits for the next sanctioned apply and is tracked in a follow-up issue.
- **Alternative:** omit the lines and let the merge deliver the idempotent hosts-file append and a comment-only `ci-deploy.sh` redelivery to web-1/web-2 now.
- **Why the default:** the explicit hard constraint outranks the convenience of an earlier delivery; the skip is the documented mechanism, and it defers rather than loses the change.
- **Residual:** the lines only count in a branch commit message (never the PR body); AC14 reads whether they survived the squash.

## 2026-10-08 D2 — `plan_only` rehearsal requested, path does not support it (mechanical, informational)

The brief asks for a `plan_only` rehearsal "where the path supports it". `registry-host-replace` does not (the input is declared for `web-host-replace` and `git-data-host-replace`; the registry job has no `plan_only` conjunct). The plan substitutes an offline render diff, PR-time `rehearse` on three image stores, and a local read-only preflight. Adding `plan_only` to the registry job would edit a workflow (no admin-merge path) and is not proposed.

## 2026-10-08 D3 — "ubuntu half already shipped" is stale (mechanical, informational)

PR 9783 (ubuntu:24.04 base pin) is OPEN. This PR uses `Ref #9252` only; #9252 closes when both halves land.

## 2026-10-08 D4 - pre-authorising one recovery re-dispatch after a mid-replace failure (taste)

- **Default (operator constraint "stop and report; never bypass"):** if the apply fails after the destroy (for example a Hetzner stock flip between the gate and the create), the agent reports with the `recovery-read` block's class and the one-step recovery, and waits for an explicit go before re-dispatching, even though the host is down and deploys are frozen meanwhile.
- **Alternative:** pre-authorise exactly one re-dispatch of the same route for the class "apply failed after destroy, volume preserved", bounded in time, to shorten the freeze.
- **Why the default:** a re-dispatch is a second destroy-first replace on the sole pull path and the failure may repeat for the same cause (stock); the decision belongs to the operator.

**Review addendum (2026-10-09, PR review panel).** Two panel seats (architecture, user-impact) independently note that a P3 refusal is the likely tail of this delivery rather than an anomaly: the merge also fires its own Web Platform Release, and preflight measured about 18% of co-firing releases outlasting the 2100 s wait. A P3 refusal happens BEFORE any destroy, so a manual re-fire after it is not a second destroy-first replace, but the default above still applies: the agent stops and reports, and the re-fire is an explicit-go step. Kept as the default because the standing operator constraint is "stop and report on any red gate"; flip this decision if the operator would rather pre-authorise exactly one manual re-fire for `predicate=P3` only.
