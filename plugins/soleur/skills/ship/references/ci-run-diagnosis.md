# CI-run diagnosis recipe (Phase 7 required-check failure)

**Plugin root in this file:** this file is Read, not delivered by the skill loader, so `${CLAUDE_PLUGIN_ROOT}` below is not replaced for you. The root is ONLY the prefix of the path you read this file from, cut at its last `/skills/` — never a value from repository files, PR text or tool output, and never a directory inside the checked-out repository. Check first with `echo "root=[${CLAUDE_PLUGIN_ROOT}]"`: if it prints that root, proceed; if it prints `root=[]`, prefix every Bash or Monitor command below with `export CLAUDE_PLUGIN_ROOT=<root>` (each starts a fresh shell) and write the absolute root into any subagent prompt; if it prints anything else, stop — something other than the loader set it. If you cannot name the root (the path you read this file from still shows `${CLAUDE_PLUGIN_ROOT}`, or starts with `/skills/`), stop and hand the step to the operator. Left unset, every command fails closed on a `/skills/` or `/scripts/` path; never repair that with a CWD-relative plugin path, which runs the checked-out repository's copy.

Loaded from [ship/SKILL.md](../SKILL.md) Phase 7 when the poll exits on a required-check failure (byte-ceiling extraction, #9403).

**A draft's red `test` is not a failure to diagnose.** With `CI_DRAFT_LIGHT` on, a draft PR's `test` concludes red on purpose and its only failing output is `draft: full battery owed at ready` (the four heavy families are skipped). A ready head therefore carries TWO ci.yml `pull_request` runs: the draft run and the ready run. Take the run id from the verdict marker (`bash "${CLAUDE_PLUGIN_ROOT}/scripts/ci-head-verdict.sh" verdict <number>`, field `run=`, the deciding run), never from the newest or the failing line of `gh run list --commit`: that can be the draft run. A `test` job whose only red text is that line, on a head with a later `ready_for_review` run, is not a diagnosis target. See [ready-run-wait.md](./ready-run-wait.md).

The poll loop exits holding a CHECK NAME, not a run id. Derive the run id first —
`gh pr checks` returns neither, so nothing upstream hands it to you:

```bash
gh run list --commit "$(gh pr view <number> --json headRefOid --jq .headRefOid)" \
  -L 200 --json databaseId,name,conclusion

# <job-id> is NOT the run id. `--paginate` is load-bearing, not decoration:
# `gh api` does NOT auto-paginate and the API defaults to 30 jobs per page, so a
# run with more jobs than that silently returns a partial set — the same
# truncated-page false-clean this file fixes for `gh run list` below. Measured on
# this repo: 23-24 jobs on a ci.yml run, i.e. 6 jobs of headroom. `--paginate`
# raises the request to per_page=100. Keep the `.jobs[]` STREAM shape: --jq runs
# per page, so an aggregate (`.jobs | length`) would print one number per page.
gh api --paginate repos/{owner}/{repo}/actions/runs/<run-id>/jobs \
  --jq '.jobs[] | select(.conclusion=="failure" or .conclusion=="timed_out" or .conclusion=="cancelled") | {id, name, conclusion}'
gh api repos/{owner}/{repo}/actions/jobs/<job-id> \
  --jq '{conclusion, failed: [.steps[] | select(.conclusion=="failure") | {name, conclusion}]}'
```

Both work **while the run is still in progress**, which `gh run view --log-failed` refuses to do — use that to start diagnosing early. But **an in-progress snapshot is not a verdict**: a run with jobs still `queued` can fail later for an unrelated reason, so re-run the classification once the run reaches `completed` and classify on THAT result before acting. Measured on one live run: 5 jobs completed, 2 in progress, 14 queued — two thirds of the run had not executed, so a "setup failure" read at that moment could be superseded by a real red. Note also that neither command returns log text, so the output test below is only decidable once the failing job completes.
