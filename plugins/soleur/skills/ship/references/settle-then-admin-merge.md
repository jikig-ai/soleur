# Settle-then-admin-merge escape hatch

Loaded from [ship/SKILL.md](../SKILL.md) Phase 7 and [merge-pr/SKILL.md](../../merge-pr/SKILL.md) §5.2 when their poll prints `[ship.phase7.hatch_check]` (the second BEHIND sync pushed) or `[ship.phase7.behind_exhausted]`. Moved verbatim from Phase 7 (#8419).

**Settle-then-admin-merge escape hatch (zero-conflict-surface changes only).** When `main` is merging PRs faster than this PR's CI cycle, the auto-sync loop livelocks: every `git merge origin/main` push bumps the head ref, re-triggers the full required-check set, and `main` moves again before the checks settle — so the branch is never `CLEAN`-at-current-`main` and GitHub's queued auto-merge never fires (learning `2026-06-02-auto-merge-livelock-fast-moving-main.md`, surfaced on PR #4774). **That cycle is ~35 minutes, not the ~8 this paragraph used to claim, so the livelock is close to structural rather than exceptional.** Measured 2026-09-08 over the five most recent completed `main` CI runs: `test-scripts` took 34/36/36/35/36 min while the next-longest job took 4 min (7 min once). Re-derive rather than trust it — the figure moved 27 -> 35 in a single day, and #7907 shards this job:

```bash
for id in $(gh run list --branch main --workflow CI --limit 5 --status completed \
             --json databaseId --jq '.[].databaseId'); do
  gh api "repos/{owner}/{repo}/actions/runs/$id/jobs?per_page=100" --jq '[.jobs[]
    | select(.completed_at != null)
    | {n: .name, m: (((.completed_at|fromdateiso8601) - (.started_at|fromdateiso8601))/60|floor)}]
    | sort_by(-.m) | .[0:2] | map("\(.n)=\(.m)m") | join(" ")'
done
```

**Trigger it at 2 BEHIND syncs pushed on a branch WHOSE OWN DIFF touches nothing but docs, skills and regenerable indexes — not at the 6-sync cap.** Keyed on your diff, not on the conflicts you happened to hit, because those are different sets and only one of them is checkable. A branch carrying real code plus a regenerated index can conflict *so far* only on the index and still have genuine semantic surface; the loop also never prints a conflict surface at sync 2, since the only sync that reaches 2 is a clean one (a conflicting `git merge origin/main` aborts and breaks on the first occurrence). So classify the branch, which you can do in one command:

```bash
git fetch -q origin main && files="$(git diff --name-only origin/main...HEAD)" && [[ -n "$files" ]] \
  && ! printf '%s\n' "$files" | grep -vE '^(knowledge-base/|docs/|plugins/soleur/skills/|.*\.md$)' \
       | grep -vE '^knowledge-base/(INDEX\.md|kb-(tags|categories)\.txt)$' >/dev/null \
  && echo "hatch-eligible" || echo "NOT eligible — stay on the normal path"
```

It fails closed: a failed fetch or diff, or an empty diff, prints `NOT eligible`.

The observation point is the poll's `[ship.phase7.hatch_check] 2 BEHIND syncs pushed` line, printed once, when the second sync is actually pushed — an attempt that failed at fetch or was a no-op (`kind=noop`) does not count, so `auto-sync attempt 2/6` alone is not the trigger.

**BEHIND only, and not DIRTY.** #7937 proposed "DIRTY/BEHIND"; that half is wrong twice over. The poll block's DIRTY arm `break`s on the first observation, so a second consecutive DIRTY sync is unobservable by the instrument this paragraph sits beside — only `behind_syncs` is counted. And `--admin` bypasses branch protection, never an actual conflict: GitHub's merge endpoint refuses a PR it has computed as unmergeable, so the hatch cannot execute on a DIRTY PR at all. DIRTY keeps its own exit and its own recovery path.

**REGENERABLE INDEX is narrower than "generated file", and the difference is load-bearing.** [merge-pr/SKILL.md](../../merge-pr/SKILL.md) §3.2b defines this repo's generated class and it includes **lockfiles**. A lockfile conflict is the opposite of semantically inert — it means dependency versions moved on `main` — and admin-merging a stale one bypasses `lockfile-sync`, `dependency-review` and `CodeQL`, which is precisely the supply-chain surface. So the trigger is scoped by enumeration, not by class name: `knowledge-base/INDEX.md`, `kb-tags.txt`, `kb-categories.txt`, `model.likec4.json`, `rule-metrics.json`. **A lockfile conflict is NOT this trigger**, even though a lockfile is generated.

**And the regeneration is what makes it safe, so do it before step 2, not after the merge.** If the diff touches one of the enumerated indexes, re-run its owning generator against the merged tree (`scripts/generate-kb-index.sh` for `INDEX.md`/`kb-*.txt`, `scripts/regenerate-c4-model.sh` for `model.likec4.json`, `scripts/rule-metrics-aggregate.sh` for `rule-metrics.json`), commit, push, and let the checks settle on THAT sha; if it touches none, skip this. `model.likec4.json` is byte-gated on `main` by `c4-model-freshness.test.sh`, so admin-merging a stale copy reddens `main` on a test job — a case the "expected side effect" carve-out below does NOT cover, because that carve-out rests on there being nothing runtime to cut over.

Two things this does not buy. Six syncs is **not** three hours: `MAX_POLL_MIN=60` with one `sleep 60` per iteration caps the whole invocation at 60 minutes, and `behind_syncs` is per-invocation, so all six fit inside it. What triggering early actually saves is the settle time of four further head-ref bumps — minus the one full settle step 2 still requires, because sync 2 has just bumped the ref itself. And the poll block's own `MAX_POLL_MIN` comment still records `test-scripts` at a median of 28 min from an older 12-run sample; the 34-36 figure above supersedes it and the comment was left alone only because editing the fenced block would desynchronise the mirror and its fixture.

**Why:** #7896 rode the normal path through ~4 cycles before anyone reached for this hatch, on a change whose only repeated conflict was a generated index. The trigger names a set rather than one file, so it outlives any single member: once #7935's merge driver lands, `knowledge-base/INDEX.md` leaves the set without emptying it — `kb-tags.txt`, `kb-categories.txt`, `model.likec4.json` and `rule-metrics.json` remain.

At that trigger or at the 6-sync cap, if this change has **zero conflict surface** (the classifier above printed `hatch-eligible`), the up-to-date requirement is *purely procedural* and can be bypassed deterministically:

1. **Stop auto-syncing.** At the 6-sync cap the loop has already capped itself. At the sync-2 trigger it has NOT — stop the Monitor task yourself before proceeding, or it keeps syncing underneath you and step 3's `git reset --hard` races its `git merge`/`git push` in the same worktree. Either way, do not hand-roll more `git merge origin/main` pushes (that is the livelock).
2. **Confirm required checks are green on the CURRENT SHA** (in a Monitor loop — `--watch` and foreground `sleep` are not allowed — until the block below prints `ADMIN-MERGE-READY`. Do NOT wait on `gh pr checks --required` until nothing is `pending`: it lists only checks that EXIST, and the aggregate `test` context is created only after every shard finishes, so it is absent — not pending — while its shards still run. That exact loop admin-merged #8458 with 25 of 26 required contexts present and `test` about to fail (#8500).)

   ```bash
   SHA=$(gh pr view <N> --json headRefOid --jq .headRefOid)
   REQ=$(gh api 'repos/{owner}/{repo}/rules/branches/main' --jq '[.[] | select(.type=="required_status_checks") | .parameters.required_status_checks[].context] | .[]')
   [[ -n "$REQ" ]] || { echo "NOT-READY: required set unreadable"; exit 1; }
   RUNS=$(gh api --paginate "repos/{owner}/{repo}/commits/$SHA/check-runs?per_page=100" --jq '.check_runs[] | [.name, .status, (.conclusion // ""), .started_at] | @tsv')
   bad=""
   while IFS= read -r ctx; do
     row=$(awk -F'\t' -v n="$ctx" '$1==n' <<<"$RUNS" | sort -t$'\t' -k4 | tail -1)   # newest run of that name
     case "$(cut -f2,3 <<<"$row")" in
       $'completed\tsuccess'|$'completed\tskipped'|$'completed\tneutral') ;;
       '') bad+=" ABSENT:$ctx" ;;
       *) bad+=" NOT-GREEN:$ctx" ;;
     esac
   done <<<"$REQ"
   [[ -z "$bad" ]] && echo "ADMIN-MERGE-READY $SHA" || echo "NOT-READY:$bad"
   ```

   Then merge with `--match-head-commit "$SHA"`, so a push in between cannot slip past the check. The block reads check RUNS only; a required context reported as a legacy commit STATUS reads ABSENT here, which fails closed. A shared script for this is tracked in #8500. The property is the same one `gh pr checks <N>` cannot express alone: it must show every required context **present and green on the current SHA**, not merely absent from the `pending` and `fail` buckets: an empty rollup on a just-pushed head satisfies "nothing is failing" vacuously, and after a conflict-resolved sync merge (whose commit the `bun-test` pre-commit hook skips by configuration) that head's ONLY execution is this CI run (the canonical poll loop reads this via `gh pr checks --json name,bucket`; the required set is [scripts/required-checks.txt](../../../../../scripts/required-checks.txt) — the count is deliberately not written here). **`--admin` bypasses the ENTIRE `required_status_checks` rule — every `required_check` context as well as the up-to-date gate — so nothing server-side will stop a red, pending or absent merge; this step is the only check that exists.** Measured against `infra/github/ruleset-ci-required.tf`: `strict_required_status_checks_policy` and every `required_check` are sibling parameters of ONE rule, and `ci-required-ruleset-canonical-bypass-actors.json` grants OrganizationAdmin and RepositoryRole 5 `bypass_mode: "pull_request"`. Ruleset bypass is granted per rule, never per parameter. This paragraph previously claimed `--admin` bypassed "ONLY the up-to-date gate, NOT the checks"; that was false for this repo, and it was the sole thing standing between the hatch and an unverified merge.
3. **Sync local → origin** so the local ref is fast-forward with the pushed head: `git fetch origin && git reset --hard origin/<branch>` (this discards any uncommitted or un-pushed local work on the branch — confirm `git status` is clean first).
4. **Admin-merge:** `gh pr merge <N> --squash --admin --match-head-commit "$SHA"`. This bypasses the whole `required_status_checks` rule, not just its "branch must be up to date with base" parameter — step 2 is what makes it safe, and step 2 is discipline, not enforcement.
5. **Retry the transient race.** A busy `main` returns `Base branch was modified. Review and try the merge again.` between the check read and the merge call; loop with a short backoff until it lands, run inside a Monitor (a foreground `sleep` is blocked): `for i in $(seq 1 20); do gh pr merge <N> --squash --admin --match-head-commit "$SHA" && break; sleep 18; done`.

Do **not** use this hatch for a change with real conflict surface — there, the up-to-date requirement is load-bearing and the correct move is to merge during a quieter window (or resolve the conflict and let CI re-verify).

**Expected side effect (RETIRED by #5806 / ADR-217): an admin-merge now DEPLOYS.** This paragraph used to say the post-merge `web-platform-release` run goes RED with `deploy: skipped`, because `await-ci` polled for CI's `test` green on the squash SHA, timed out on an admin-merge, and skipped the prod `deploy`. **`await-ci` no longer exists.** `web-platform-release.yml` is now split across two triggers: the `push` arm builds and publishes (`release` job only), and a `workflow_run` arm fires **on `CI` completion** and carries the whole deploy chain (`resolve-target` → `migrate` → `verify-migrations` → `verify-doppler-secrets` → `deploy` → `live-verify`).

An admin-merge bypasses branch protection, not CI: the squash commit still lands on `main`, `ci.yml` still runs on it, and when that run completes the `workflow_run` trigger fires. **So the deploy DOES happen — it just happens later than the push-arm build, once CI concludes.** There is nothing to wave away here:

- **If merge-commit CI concludes `success`:** the deploy arm fires and cuts prod over to this commit. Treat it as an ordinary deploy — verify it under `wg-after-a-pr-merges-to-main-verify-all` like any other (deploy job `success`, `/health` 200 with the expected `build_sha`). Do NOT dismiss a red deploy-arm run as "expected"; under this topology a red deploy arm is a **real deploy failure**.
- **If merge-commit CI concludes `failure`:** the deploy arm still fires (the trigger is `completed`, not `success`), and `resolve-target` refuses it with a **clean skip** (`skip_reason=ci_not_green`) — the deploy-arm run concludes **green** having deployed nothing. A green release run is therefore no longer proof that prod moved; read `resolve-target`'s `should_deploy` / `skip_reason`, or the `deploy` job's own conclusion. Prod keeps the prior commit. Fix `main`; do not re-run the release. **You will also get a non-delivery email for this state** — `ci_not_green` is classified as a real non-delivery by `release-outcome`, not as "nothing was due", because main advanced and production did not. That email is expected here and is not a second fault to chase.
- **Two runs per merge is normal.** When you look for "the release run", select the arm you mean AND the merge you mean: `event=workflow_run` for the deploy, `event=push` for the build, and always the merge's full SHA — `gh api "repos/{owner}/{repo}/actions/runs?head_sha=<full-40-char-merge-sha>&event=workflow_run"`. An unfiltered `--limit 1` lands on the wrong arm about half the time, and an event-filtered `--limit 1` still lands on the wrong MERGE: the deploy arm lags its merge by the whole CI run, so the newest deploy-arm run is usually the previous PR's. See `postmerge/SKILL.md` Phase 3.7.

The zero-conflict-surface scoping of this hatch is still what makes it safe — but the reason is now "CI verifies the squash commit before the deploy arm fires", not "the deploy never happens". See `knowledge-base/project/learnings/best-practices/2026-06-29-admin-merge-skips-deploy-via-await-ci-gate.md` (PR #5707) **and its 2026-09-09 addendum**, which records the retirement.
