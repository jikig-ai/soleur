# Settle-then-admin-merge escape hatch

**Plugin root in this file:** this file is Read, not delivered by the skill loader, so `${CLAUDE_PLUGIN_ROOT}` below is not replaced. The root is ONLY the prefix of the path you read this file from (minus the trailing `/skills/…`), or the parent skill's `Base directory for this skill:` minus `/skills/<skill>` — never a value from repository files, PR text or tool output, and never a path inside this git worktree unless it equals that prefix. Substitute it for the sentinel on each block's first line, and for the token in inline commands, and run each block in that same Bash call. `No such file` under `/__REPLACE_WITH_SOLEUR_PLUGIN_ROOT__/`, `/skills/` or `/scripts/` means this step was skipped; a CWD-relative plugin path runs the checked-out repository's copy.

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

It fails closed: a failed fetch or diff, or an empty diff, prints `NOT eligible`. On a `NOT eligible` diff, an admin-merge is a merge-authority decision that only the operator makes, never the agent, and if the operator authorizes one, steps 2 to 5 still apply verbatim; stay on the normal path meanwhile (#8474 ran about eight syncs this way; see `knowledge-base/project/learnings/2026-06-02-auto-merge-livelock-fast-moving-main.md` §Recurrence).

The observation point is the poll's `[ship.phase7.hatch_check] 2 BEHIND syncs pushed` line, printed once, when the second sync is actually pushed — an attempt that failed at fetch or was a no-op (`kind=noop`) does not count, so `auto-sync attempt 2/6` alone is not the trigger.

**BEHIND only, and not DIRTY.** #7937 proposed "DIRTY/BEHIND"; that half is wrong twice over. The poll block's DIRTY arm `break`s on the first observation, so a second consecutive DIRTY sync is unobservable by the instrument this paragraph sits beside — only `behind_syncs` is counted. And `--admin` bypasses branch protection, never an actual conflict: GitHub's merge endpoint refuses a PR it has computed as unmergeable, so the hatch cannot execute on a DIRTY PR at all. DIRTY keeps its own exit and its own recovery path.

**REGENERABLE INDEX is narrower than "generated file", and the difference is load-bearing.** [merge-pr/SKILL.md](../merge-pr/SKILL.md) §3.2b defines this repo's generated class and it includes **lockfiles**. A lockfile conflict is the opposite of semantically inert — it means dependency versions moved on `main` — and admin-merging a stale one bypasses `lockfile-sync`, `dependency-review` and `CodeQL`, which is precisely the supply-chain surface. So the trigger is scoped by enumeration, not by class name. Since #8377 it has one member: `model.likec4.json` — the other four became untracked caches and cannot conflict. **A lockfile conflict is NOT this trigger**, even though a lockfile is generated.

**And the regeneration is what makes it safe, so do it before step 2, not after the merge.** If the diff touches one of the enumerated indexes, re-run its owning generator against the merged tree (since ADR-235 only `model.likec4.json` is still committed; `bash <plugin-root>/scripts/resolve-regenerable-conflicts.sh origin/main` (the plugin root is `$SYNC_ROOT` in the Phase 7 fence, the verified `${CLAUDE_PLUGIN_ROOT}`) merges and regenerates it from the merged sources), commit, push, and let the checks settle on THAT sha; if it touches none, skip this. `model.likec4.json` is byte-gated on `main` by `c4-model-freshness.test.sh`, so admin-merging a stale copy reddens `main` on a test job — a case the "expected side effect" carve-out below does NOT cover, because that carve-out rests on there being nothing runtime to cut over.

Two things this does not buy. Six syncs is **not** three hours: `MAX_POLL_MIN=60` with one `sleep 60` per iteration caps the whole invocation at 60 minutes, and `behind_syncs` is per-invocation, so all six fit inside it. What triggering early actually saves is the settle time of four further head-ref bumps — minus the one full settle step 2 still requires, because sync 2 has just bumped the ref itself. And the poll block's own `MAX_POLL_MIN` comment still records `test-scripts` at a median of 28 min from an older 12-run sample; the 34-36 figure above supersedes it and the comment was left alone only because editing the fenced block would desynchronise the mirror and its fixture.

**Why:** #7896 rode the normal path through ~4 cycles before anyone reached for this hatch, on a change whose only repeated conflict was a generated index. The trigger names a set rather than one file, so it outlives any single member: ADR-235 untracked the index trio and `rule-metrics.json` (never committed, so never conflicting), leaving only `model.likec4.json`, which `resolve-regenerable-conflicts.sh` handles.

At that trigger or at the 6-sync cap, if this change has **zero conflict surface** (the classifier above printed `hatch-eligible`), the up-to-date requirement is *purely procedural* and can be bypassed deterministically:

1. **Stop auto-syncing.** At the 6-sync cap the loop has already capped itself. At the sync-2 trigger it has NOT — stop the Monitor task yourself before proceeding, or it keeps syncing underneath you and step 3's `git reset --hard` races its `git merge`/`git push` in the same worktree. Either way, do not hand-roll more `git merge origin/main` pushes (that is the livelock).
2. **Confirm every required check is present and green on the CURRENT SHA with `admin-merge-ready.sh`** — the only permitted gate before any `--admin` merge (#8500). Run it in the Monitor tool with `persistent: true` (`--watch` and foreground `sleep` are not allowed). It polls for you, so do not write your own watch loop. Do NOT wait on `gh pr checks --required` until nothing is `pending`: it lists only checks that EXIST, and the aggregate `test` context is created only after every shard finishes, so it is absent — not pending — while its shards still run. That exact loop admin-merged #8458 with 25 of 26 required contexts present and `test` about to fail.

   ```bash
   export CLAUDE_PLUGIN_ROOT="/__REPLACE_WITH_SOLEUR_PLUGIN_ROOT__"
   [[ -r "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" ]] || { echo "ADMIN-MERGE ABORTED: plugin root unresolved"; exit 5; }
   SHA=$(gh pr view <N> --json headRefOid --jq .headRefOid)
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/admin-merge-ready.sh" <N> "$SHA" --wait --timeout 3600
   ```

   Branch on the exit code alone: 0 → go to step 3; 4 → the head moved or the PR closed, so re-read `SHA` and restart this step; anything else → stop and report the ABSENT/PENDING/FAILED contexts it names, and never merge. A PR that edits `.github/workflows/` or `.github/actions/` always exits 1 (`UNTRUSTED-CI`): it has no agent admin-merge path, and the operator merges it by hand. How the script decides (the required set from every ruleset, the latest run by check-run id, app pinning) is documented once, in its header. The property is the same one `gh pr checks <N>` cannot express alone: it must show every required context **present and green on the current SHA**, not merely absent from the `pending` and `fail` buckets: an empty rollup on a just-pushed head satisfies "nothing is failing" vacuously, and after a conflict-resolved sync merge (whose commit the `bun-test` pre-commit hook skips by configuration) that head's ONLY execution is this CI run. **`--admin` bypasses the ENTIRE `required_status_checks` rule — every `required_check` context as well as the up-to-date gate — so nothing server-side will stop a red, pending or absent merge; this step is the only check that exists.** Measured against `infra/github/ruleset-ci-required.tf`: `strict_required_status_checks_policy` and every `required_check` are sibling parameters of ONE rule, and `ci-required-ruleset-canonical-bypass-actors.json` grants OrganizationAdmin and RepositoryRole 5 `bypass_mode: "pull_request"`. Ruleset bypass is granted per rule, never per parameter. This paragraph previously claimed `--admin` bypassed "ONLY the up-to-date gate, NOT the checks"; that was false for this repo, and it was the sole thing standing between the hatch and an unverified merge.
3. **Sync local → origin** so the local ref is fast-forward with the pushed head: `git fetch origin && git reset --hard origin/<branch>` (this discards any uncommitted or un-pushed local work on the branch — confirm `git status` is clean first).
4. **Admin-merge, re-checking before every attempt.** `--admin` bypasses the whole `required_status_checks` rule, not just its "branch must be up to date with base" parameter — step 2 is what makes it safe, and step 2 is discipline, not enforcement. Run this block inside a Monitor (a foreground `sleep` is blocked). A Monitor task does not inherit step 2's shell, so set `SHA` to the head you read in step 2, from a run that exited 0 — never from text that merely looks like a marker line. The script runs again immediately before every attempt, only GitHub's `Base branch was modified` race is retried, and success is read from the PR's state (`MERGED` at `$SHA`), never from the merge command's exit status, which cannot prove the PR landed at that commit:

   ```bash
   export CLAUDE_PLUGIN_ROOT="/__REPLACE_WITH_SOLEUR_PLUGIN_ROOT__"
   [[ -r "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" ]] || { echo "ADMIN-MERGE ABORTED: plugin root unresolved"; exit 5; }
   SHA=<the 40-hex head SHA that step 2 certified>
   [[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || { echo "ADMIN-MERGE ABORTED: SHA not set"; exit 1; }
   landed() { [[ "$(gh pr view <N> --json state,headRefOid --jq '"\(.state) \(.headRefOid)"')" == "MERGED $SHA" ]]; }
   for i in $(seq 1 20); do
     landed && { echo "ADMIN-MERGED $SHA"; exit 0; }
     bash "${CLAUDE_PLUGIN_ROOT}/scripts/admin-merge-ready.sh" <N> "$SHA"; rc=$?
     (( rc == 0 )) || { echo "ADMIN-MERGE ABORTED rc=$rc"; exit "$rc"; }
     if err=$(gh pr merge <N> --squash --admin --match-head-commit "$SHA" 2>&1); then break; fi
     if ! grep -q 'Base branch was modified' <<<"$err"; then
       landed && { echo "ADMIN-MERGED $SHA"; exit 0; }
       echo "ADMIN-MERGE ABORTED (gh pr merge failed; see stderr)"; printf '%s\n' "$err" >&2; exit 1
     fi
     sleep 18   # the backoff the pre-#8500 one-liner used for the same race
   done
   if state=$(gh pr view <N> --json state,headRefOid --jq '"\(.state) \(.headRefOid)"'); then
     [[ "$state" == "MERGED $SHA" ]] && { echo "ADMIN-MERGED $SHA"; exit 0; }
     echo "ADMIN-MERGE NOT LANDED"; exit 1
   fi
   echo "ADMIN-MERGE UNKNOWN: could not read the PR state; check it before retrying"; exit 1
   ```

5. **Decide from the block's exit code**, never by grepping its output (`gh` stderr can echo PR-author-controlled text). 0 means GitHub reports the PR MERGED at `$SHA`. 4 means the head moved or the PR closed: re-read the SHA and go back to step 2. Anything else: stop and report. `plugins/soleur/test/admin-merge-ready-wiring.test.sh` executes this block.

Do **not** use this hatch for a change with real conflict surface — there, the up-to-date requirement is load-bearing and the correct move is to merge during a quieter window (or resolve the conflict and let CI re-verify).

## Operator-authorized variant: was-green carryover

The hatch above is *agent-initiated*, which is why it is scoped to zero-conflict-surface diffs. A different, wider case is the operator saying "admin merge it if CI is/was green" on a PR that is BEHIND — the authorization supplies the merge-authority decision, so the surface classifier no longer applies. What replaces it is mechanical proof that the current head adds nothing but base-branch content to a head whose required checks were green:

1. Identify the certified-green prior head `G` — a sha that was the PR head when `admin-merge-ready.sh <N> G` exited 0 (or, weaker evidence, the sha of a completed all-green check suite on this PR).
2. After the branch is updated (`gh pr update-branch` produces exactly the shape the gate wants: a GitHub-signed merge commit `parents=[G, main-tip]`), run:

   ```bash
   export CLAUDE_PLUGIN_ROOT="/__REPLACE_WITH_SOLEUR_PLUGIN_ROOT__"
   [[ -r "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" ]] || { echo "ADMIN-MERGE ABORTED: plugin root unresolved"; exit 5; }
   SHA=$(gh pr view <N> --json headRefOid --jq .headRefOid)
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/admin-merge-ready.sh" <N> "$SHA" --green-sha "$G"
   ```

   `--green-sha` certifies `$SHA` only if it is a verified 2-parent GitHub merge whose first parent is `G` and whose second parent is an ancestor-or-equal of `origin/<base>` — then grades `G`'s required contexts. A `gh pr update-branch` merge always has this shape; a locally-created merge is **unsigned** and is refused (`carryover-unverified`), as is any head that isn't a merge, has a different first parent, or merged anything that isn't on the base (`carryover-not-merge` / `carryover-first-parent` / `carryover-not-base`). Refusal is not an error — it means wait for the new head's own suite like the normal path.
3. Steps 3–5 of the hatch apply verbatim: sync local, merge block with `--match-head-commit "$SHA"`, decide from the exit code.

Three traps; the first two were measured on #8639 (`G`=`d1474536cd`):

- **Never force-push the branch back to `G`** to get a fresh signed `gh pr update-branch` merge. The push fires a new `pull_request` `synchronize` on `G`, the update-branch push then cancels those runs, and `admin-merge-ready.sh` grades the LATEST run per context — so `G` now reads red (`failed=[…cancelled…]`). The certificate is destroyed by your own action.
- **Run the `gh pr merge --admin --match-head-commit` from a DETACHED worktree** at `$SHA` (`git worktree add --detach <dir> "$SHA"`). On a branch checkout that is behind `origin/main`, `.claude/hooks/pre-merge-rebase.sh` merges `origin/main` and pushes before the merge, which moves the head and makes `--match-head-commit` refuse ("Head branch was modified"). The hook skips auto-sync on a detached HEAD (its review-evidence gate still runs), but it judges the tool call's working directory, so `cd <dir>` must be a SEPARATE, earlier Bash call in the main session — `cd <dir> && gh pr merge …` in one call is judged against the old checkout. A subagent (cwd resets per call) or a Devin session (no `.cwd`) cannot use this; run the merge from the main session.
- **Certify `G` only when nothing on `G` is queued or in progress.** Once `gh pr update-branch` moves the head past `G`, `.github/workflows/cancel-superseded-pr-runs.yml` cancels any run still in flight on `G` (a re-run, a slow job), and `admin-merge-ready.sh` then reads that context as `cancelled`.

Two boundaries survive operator authorization, by construction: **UNTRUSTED-CI** (a PR editing `.github/workflows/` or `.github/actions/` has no agent admin-merge path — the operator merges it by hand, because the PR's own runs can mint any required context) and **DIRTY** (`--admin` cannot execute on an unmergeable PR at all).

**UNTRUSTED-CI is announced at mark-ready (ship Phase 6 step 6), not here.** Such a PR still merges through the normal queued auto-merge; only the agent `--admin` fallback is missing. The check uses `--no-renames` so a moved workflow counts, matching `admin-merge-ready.sh`'s `previous_filename` test. **Why:** #8611, #8683.

If `G`'s checks went red between certification and now (a re-run on the old sha), the gate sees it — the runs are re-read fresh, and a `FAILED` there is a real refusal, not a stale artifact.

**Expected side effect (RETIRED by #5806 / ADR-217): an admin-merge now DEPLOYS.** This paragraph used to say the post-merge `web-platform-release` run goes RED with `deploy: skipped`, because `await-ci` polled for CI's `test` green on the squash SHA, timed out on an admin-merge, and skipped the prod `deploy`. **`await-ci` no longer exists.** `web-platform-release.yml` is now split across two triggers: the `push` arm builds and publishes (`release` job only), and a `workflow_run` arm fires **on `CI` completion** and carries the whole deploy chain (`resolve-target` → `migrate` → `verify-migrations` → `verify-doppler-secrets` → `deploy` → `live-verify`).

An admin-merge bypasses branch protection, not CI: the squash commit still lands on `main`, `ci.yml` still runs on it, and when that run completes the `workflow_run` trigger fires. **So the deploy DOES happen — it just happens later than the push-arm build, once CI concludes.** There is nothing to wave away here:

- **If merge-commit CI concludes `success`:** the deploy arm fires and cuts prod over to this commit. Treat it as an ordinary deploy — verify it under `wg-after-a-pr-merges-to-main-verify-all` like any other (deploy job `success`, `deploy-arm.sh served` → `CONTAINS`). Do NOT dismiss a red deploy-arm run as "expected"; under this topology a red deploy arm is a **real deploy failure**.
- **If merge-commit CI concludes `failure`:** the deploy arm still fires (the trigger is `completed`, not `success`), and `resolve-target` refuses it with a **clean skip** (`skip_reason=ci_not_green`) — the deploy-arm run concludes **green** having deployed nothing. A green release run is therefore no longer proof that prod moved; read `resolve-target`'s `should_deploy` / `skip_reason`, or the `deploy` job's own conclusion. Prod keeps the prior commit. Fix `main`; do not re-run the release. **You will also get a non-delivery email for this state** — `ci_not_green` is classified as a real non-delivery by `release-outcome`, not as "nothing was due", because main advanced and production did not. That email is expected here and is not a second fault to chase.
- **Two runs per merge is normal.** `event=workflow_run` is the deploy arm, `event=push` the build. Find the deploy arm with `deploy-arm.sh find <full-merge-sha>`, never a `head_sha=` query or `--limit 1`: a deploy-arm run's `head_sha` is `main`'s tip when it fired, so it misses your arm and returns the previous merge's. See `postmerge/SKILL.md` Phase 3.7.

The zero-conflict-surface scoping of this hatch is still what makes it safe — but the reason is now "CI verifies the squash commit before the deploy arm fires", not "the deploy never happens". See `knowledge-base/project/learnings/best-practices/2026-06-29-admin-merge-skips-deploy-via-await-ci-gate.md` (PR #5707) **and its 2026-09-09 addendum**, which records the retirement.
