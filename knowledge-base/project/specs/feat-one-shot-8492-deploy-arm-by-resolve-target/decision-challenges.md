# Decision challenges — feat-one-shot-8492-deploy-arm-by-resolve-target

## DC-1 (User-Challenge, source: plan Step 4.5 advisor consult)

- **Operator's stated direction:** identify the deploy arm by reading the SHA from the `resolve-target` job log (`depth=1 origin <sha>`, `gh api --allow-escape-sequences`), as #8492 specifies.
- **Challenge:** also add `run-name: deploy ${{ github.event.workflow_run.head_sha }}` (with a push/dispatch fallback) to `.github/workflows/web-platform-release.yml`. The deployed SHA would then appear as `display_title` in the runs list, so one list call could replace a job-log read per candidate. Log parsing would stay as the fallback for runs created before the change.
- **Why it was not applied:** it widens scope into the deploy workflow itself, which the #8492 brief did not name, and it changes a file that `workflow-run-deploy-invariants.test.sh` and the ship pipeline-gate watch cover. The script's log-read design works without it, and the change can be added later without reworking the script (it would just become a cheaper candidate-SHA source).
- **Default (operator direction kept):** log-based identification only. Decide whether to file the `run-name` improvement as a follow-up.

## DC-2 (User-Challenge, source: plan-review — dhh-rails-reviewer, code-simplicity-reviewer)

- **Operator's stated direction:** "Keep `head_sha=` only as a first guess confirmed through resolve-target."
- **Challenge:** drop the `head_sha=` first-guess source entirely. Every run it returns is also in the `created>=` window query, so it only adds a call plus de-duplication.
- **Why it was not applied:** the operator asked for it explicitly. The revised plan makes it a real fast path: when the merge's CI `run_attempt` is 1, the script stops at the first readable exact arm from the first guess (4 API calls on an unbusy `main`).
- **Default:** keep it as the fast path.

## DC-3 (User-Challenge, source: plan-review — cto devex lens)

- **Operator's stated direction:** key on the `depth=1 origin <sha>` line in the resolve-target log.
- **Challenge:** move `web-platform-release.yml`'s `echo "resolving deploy target for $WR_HEAD_SHA"` above the `clean_skip` calls and key on that workflow-owned line, so a bump of `actions/checkout` cannot change the format the script depends on.
- **Why it was not applied:** it edits the deploy workflow, which is out of the brief's scope. The plan instead falls back to that line when present and adds a static test row pinning the resolve-target checkout `ref:`. A format change fails safe (`REASON=unresolved`, never a false green).
- **Default:** no workflow edit. Consider it together with DC-1 as one follow-up.
