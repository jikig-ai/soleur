---
name: merge-pr
description: "This skill should be used when merging a feature branch to main with automatic conflict resolution and cleanup."
---

<!-- soleur-cloud-mode:start -->
**Cloud Mode (Devin):** before pipeline work run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cloud-detect.sh"`. If `CLAUDE_PLUGIN_ROOT` is unset (cloud exec shells do not export it), resolve the root by IDENTITY, never by script basename: for `d` in `"$HOME/.local/share/devin/cli/plugins/cache"` and `/opt/.devin/plugins`, skip unless `[ -d "$d" ]`, then `MANIFEST="$(find "$d" -path '*/.claude-plugin/plugin.json' -exec grep -l '"name"[[:space:]]*:[[:space:]]*"soleur"' {} + 2>/dev/null | head -1)"`, `ROOT="${MANIFEST%/.claude-plugin/plugin.json}"` — one resolution, two consumers: `$ROOT/scripts/cloud-detect.sh` and `$ROOT/scripts/precommit-guard.sh`. (Shape check, not authentication: a planted `{"name":"soleur"}` dir passes — ADR-179 A11.) `local` or `not-local:no-devin-env` proceeds normally; any other `not-local:<reason>` applies `<plugin-root>/devin/INSTRUCTIONS.md` §Cloud Mode: emit the `--banner`, fan out sequentially with `Reviewed-Coverage: sequential-fallback` disclosure (never claim an independent review ran), `message_user` ack before any secrets read or production mutation, and run `precommit-guard.sh` before any `git commit` — hooks do not fire in cloud.
<!-- soleur-cloud-mode:end -->

# merge-pr Skill

**Purpose:** Automate the merge pipeline for a single PR -- replacing the manual execution of `soleur:ship` Phases 3.5-8. Runs lights-out: merge main, resolve conflicts, push, create PR, wait for CI, merge, and cleanup.

**Relationship to soleur:ship:** Both skills are independent user-invoked entry points. `soleur:ship` handles artifact validation, compound, and documentation (Phases 0-3). This skill handles the merge-through-cleanup pipeline. They do NOT invoke each other.

**Arguments:** Optional branch name. If omitted, auto-detects from current branch.

## Phase 0: Context Detection

Detect the current environment and record the starting state for rollback. Run these commands separately and store the results:

1. Get current branch name:

```bash
git rev-parse --abbrev-ref HEAD

```

2. Get current commit SHA (this is the rollback point):

```bash
git rev-parse HEAD

```

3. Get current working directory path (worktree path):

```bash
pwd

```

4. Get the main repo root (first path from worktree list output):

```bash
git worktree list

```

Store these four values as BRANCH, STARTING_SHA, WORKTREE_PATH, and REPO_ROOT for use throughout the pipeline.

Load project conventions:

```bash
if [[ -f "CLAUDE.md" ]]; then
  cat CLAUDE.md
fi

```

If an argument was provided, verify that branch exists and check it out. Otherwise use the current branch.

Announce:

```text
merge-pr: Starting pipeline for branch: <branch-name>
Starting SHA: <starting-sha> (rollback point)

```

Replace `<branch-name>` with the actual branch name and `<starting-sha>` with the current HEAD SHA.

## Phase 1: Pre-condition Validation

Validate all pre-conditions before proceeding. On any failure, stop immediately and report.

### 1.1 Not on default branch

```bash
git rev-parse --abbrev-ref HEAD

```

If the branch is `main` or `master`, stop:

```text
STOPPED: Cannot run merge-pr on the default branch.
Switch to a feature branch or provide a branch name as argument.

```

### 1.2 Clean working tree

```bash
git status --porcelain

```

If output is non-empty, stop:

```text
STOPPED: Uncommitted changes detected. Commit changes before running merge-pr.

```

### 1.3 Compound has run

Extract the feature name from the branch (strip `feat-`, `feature/`, `fix-`, `fix/` prefix). Search for unarchived KB artifacts matching the feature name in:

- `knowledge-base/project/brainstorms/` (excluding `archive/` paths)
- `knowledge-base/project/plans/` (excluding `archive/` paths)
- `knowledge-base/project/specs/feat-<feature>/`

If any unarchived artifacts are found, stop:

```text
STOPPED: Unarchived KB artifacts found for this feature:
<list of files>

Use `skill: soleur:compound` to consolidate and archive these artifacts, then re-run `skill: soleur:merge-pr`.

```

If no unarchived artifacts exist (either compound already archived them, or no artifacts were created), proceed.

## Phase 2: Merge Main

Fetch the latest main and merge into the feature branch:

```bash
git fetch origin main
git merge origin/main

```

**If merge is clean (exit code 0):** Proceed to Phase 4 (skip Phase 3).

**If merge conflicts (exit code non-zero):** Proceed to Phase 3.

> **Note:** Version bumping is handled automatically by CI at merge time. This skill does not bump versions.

## Phase 3: Conflict Resolution

Identify conflicted files:

```bash
git diff --name-only --diff-filter=U

```

### 3.1 Route conflicts

For each conflicted file, apply the appropriate resolution strategy:

| File Pattern | Strategy |
|-------------|----------|
| `plugins/soleur/CHANGELOG.md` | Merge both sides -- see 3.2 |
| `plugins/soleur/README.md` | Accept feature branch component counts |
| Generated artifacts | See 3.2b. **The knowledge-base caches are untracked and cannot conflict — see the transition note** |
| Everything else | Claude-assisted resolution -- see 3.3 |

**Generated artifacts (3.2b).** A generated file has no authorial intent to preserve, so 3.3 does not apply to it: hand-picking hunks produces an artifact that matches neither side's source and that no generator would emit. Resolve by discarding both sides and regenerating from the merged source. The one known member is `knowledge-base/engineering/architecture/diagrams/model.likec4.json` → [regenerate-c4-model.sh](../../../../scripts/regenerate-c4-model.sh) (verify with [c4-model-freshness.test.sh](../../test/c4-model-freshness.test.sh), which is exactly the in-sync assertion). Every other generated artifact in this repo is an untracked cache and cannot reach a merge at all. Lockfiles follow the same shape with a pinned toolchain — see [drain-prs/SKILL.md](../drain-prs/SKILL.md) §6(a).

**In the Soleur repository the knowledge-base caches cannot conflict at all, because they are not committed** ([ADR-235](../../../../knowledge-base/engineering/architecture/decisions/ADR-235-generated-artifacts-caches-untracked-products-regenerated-on-conflict.md)). `knowledge-base/INDEX.md`, `kb-tags.txt`, `kb-categories.txt` and `knowledge-base/project/rule-metrics.json` are gitignored: each is a pure function of the tree (or, for the metrics aggregate, of gitignored local data), so it is regenerated on demand instead of merged. If one of them appears in a conflict list, something has force-added it — that is the bug, not the conflict.

This replaces a merge driver that #7935 registered for `INDEX.md` and #8377 retired along with `.gitattributes`, its SessionStart installer and the resolution playbook that used to sit here. The driver worked locally and was **structurally unable** to run server-side, which is where the cost actually landed: GitHub's merge cannot run a driver from `git config`, so every `gh pr update-branch`, every "Update branch" button and every strict-up-to-date auto-merge resolved the index with the default text merge. 71 of 102 first-parent `main` commits in the week before the change touched `INDEX.md`, so open PRs paid the conflict on nearly every advance — PRs #8319 / #8321 / #8347 took 7 / 11 / 3 forced resyncs. An untracked file removes the mechanism rather than automating its resolution.

**TRANSITION — a branch opened before #8377 merged hits this exactly once.** Such a branch still tracks the four files, `main` has deleted them, and the next sync is therefore a **modify/delete** conflict rather than a content one. It is resolved by untracking them on that branch, with no regeneration and no side-picking:

```bash
git rm --cached knowledge-base/INDEX.md knowledge-base/kb-tags.txt \
                knowledge-base/kb-categories.txt knowledge-base/project/rule-metrics.json
```

Then commit the merge as usual. Nothing on disk is lost — [ensure-kb-index.sh](../../../../scripts/ensure-kb-index.sh) regenerates the three index files on the next read, and [rule-prune.sh](../../../../scripts/rule-prune.sh) regenerates the aggregate before reading it. This is deliberately a documented one-liner rather than a sweep script: it runs once per affected branch, on a conflict whose owner is already resolving it, and a tool that force-pushes ~20 branches is a worse failure mode than ~20 blocking conflicts.

**The one generated artifact that IS still committed is `model.likec4.json`**, because the web-platform C4 viewer (`app/api/kb/c4/project/route.ts`) fetches the committed blob from GitHub on the request path with no build step, so it has to exist as a committed blob. It stays a member of 3.2b, and on the sync path it is resolved automatically: [resolve-regenerable-conflicts.sh](../../scripts/resolve-regenerable-conflicts.sh) completes the merge and re-runs [regenerate-c4-model.sh](../../../../scripts/regenerate-c4-model.sh) against the **merged** tree, which is the step that makes regeneration correct where side-picking is not. It is called by `sync-pr-behind.sh`, `pre-merge-rebase.sh` and ship Phase 7; resolving by hand is the same operation:

```bash
git merge origin/main            # leaves model.likec4.json conflicted
bash scripts/regenerate-c4-model.sh
git add knowledge-base/engineering/architecture/diagrams/model.likec4.json
git commit --no-edit
```

The regeneration script validates on diagnostics and element count and exits non-zero on a fault, so a broken `.c4` source surfaces instead of committing an empty model.

**For README.md (accept feature branch):**

```bash
git checkout --ours plugins/soleur/README.md
git add plugins/soleur/README.md

```

### 3.2 CHANGELOG merge

CHANGELOG requires special handling to preserve entries from both sides without truncation.

Read both sides using git stage numbers (NOT `git show HEAD:` which only gives one side):

```bash
ours=$(mktemp -t changelog-ours.XXXXXXXX.md); theirs=$(mktemp -t changelog-theirs.XXXXXXXX.md)
git show :2:plugins/soleur/CHANGELOG.md > "$ours"
git show :3:plugins/soleur/CHANGELOG.md > "$theirs"
echo "ours=$ours theirs=$theirs"  # echo the paths: the Read/Write steps below need them, and a separate tool call does not inherit these vars

```

- `:2:` is "ours" (feature branch)
- `:3:` is "theirs" (main)

Read both files. Reconstruct the complete CHANGELOG:

- Keep the file header (title, description, links)
- Merge version entries in descending version order
- If the feature branch has a draft entry, keep it
- All entries from main must be preserved

Write the complete reconstructed file. Then verify integrity:

```bash
wc -l plugins/soleur/CHANGELOG.md

```

The line count should be roughly the sum of unique lines from both sides. If the result is suspiciously short (less than 80% of the larger input file), something was truncated -- stop and report.

```bash
git add plugins/soleur/CHANGELOG.md

```

### 3.3 Claude-assisted resolution

For non-version-file conflicts, read the conflicted file and resolve based on intent:

1. Read the file with conflict markers
2. Understand what each side changed and why
3. Resolve the conflict preserving the intent of both changes
4. Write the resolved file

If resolution confidence is low (ambiguous intent, large conflict spanning many lines, or the changes are contradictory), abort the entire merge:

```bash
git merge --abort

```

Then stop:

```text
STOPPED: Could not confidently resolve conflict in: <file>
The merge has been aborted. Working tree is clean at the starting SHA.

Conflicted files:
<list>

Resolve manually, then re-run soleur:merge-pr.

```

### 3.4 Commit resolved conflicts

After all conflicts are resolved:

```bash
git commit -m "merge: resolve conflicts with origin/main"

```

Before Phase 4 pushes, run every suite that references a script your branch changes, derived as in `work/SKILL.md` ("derive the list from CONSUMERS, not memory"): a sibling's new test merges cleanly, so the conflict list misses it (#8474).

## Phase 4: Push and PR

Push the branch to remote:

```bash
git push -u origin <branch-name>

```

Replace `<branch-name>` with the actual branch name.

Check for an existing PR:

```bash
gh pr list --head <branch-name> --json number,state | jq '.[] | select(.state == "OPEN") | .number'

```

**If a PR exists:** Announce the PR number and proceed.

**If no PR exists:** Before creating, detect associated issue numbers from the branch name (e.g., `fix/123-desc`) and commit messages (`git log origin/main..HEAD --oneline`). Then create the PR:

```bash
gh pr create --title "<type>: <description>" --body "
## Summary
<bullet points summarizing changes>

Closes #ISSUE_NUMBER

## Test plan

- [ ] CI passes
- [ ] Manual verification of merge pipeline

Generated with [Claude Code](https://claude.com/claude-code)
"

```

If an issue number was detected, include the `Closes #N` line. If none, omit it. Derive the title from the branch name and changes. Use `feat:` for features, `fix:` for bug fixes.

Announce the PR URL.

## Phase 5: CI and Merge

### 5.1 Queue Auto-Merge

```bash
SS_LIB="${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/scripts/lib/session-state.sh"
if [[ -r "$SS_LIB" ]] && command -v flock >/dev/null 2>&1; then
  bash "$SS_LIB" with_lock merge-main 600 -- \
    gh pr merge <number> --squash --auto
  rc=$?
else
  # Degrade open, loudly — the lock is advisory (ADR-178 §5).
  echo "SOLEUR_SESSION_STATE_UNAVAILABLE path=$SS_LIB reason=running-unlocked"
  gh pr merge <number> --squash --auto
  rc=$?
fi
# rc=99 comes only from `with_lock` — but it means "the lock could not be
# TAKEN", which is broader than contention: `acquire_lock` also returns 99 when
# the lock FILE cannot be opened (EROFS/ENOSPC/EMFILE). The guard above removes
# the third cause (a missing flock(1)) by routing it to the degrade-open arm,
# because otherwise a host without util-linux reports ">600s contention" on an
# uncontended lock and exits 1 forever. Do not report 99 as contention without
# saying it may be an unopenable lock file.
if [[ "$rc" -eq 99 ]]; then
  echo "merge-main lock contended >600s — another session is queueing auto-merge. Retry shortly."
  exit 1
fi

```

The `with_lock <name> <timeout_s> -- <cmd>` wrapper serializes concurrent `merge --auto` queueings across parallel CC sessions; the lock releases on exit. **The `--` separator is required** to terminate positional args. Returns 99 on `>timeout_s` contention; check `$?` so the merge intent doesn't drop silently.

This queues the merge. GitHub waits for all branch protection requirements (CI checks, CLA) to pass, then merges automatically. Do NOT use `gh pr checks --watch` -- it exits immediately with "no checks reported" when CI hasn't registered yet.

**NEVER use `--delete-branch`.** The guardrails hook blocks it when any worktree exists. Branch cleanup is handled by `cleanup-merged` in Phase 6.

### 5.2 Poll for Merge

Use the **Monitor tool** with the same state-machine loop as `soleur:ship` Phase 7. The loop covers three structurally-unmergeable states in addition to the terminal MERGED/CLOSED exits: **required-check failure** (exit at first failing required check, name it on stdout — the Monitor tool streams stdout only), **BEHIND** (auto-sync main into the branch up to 6 attempts, then emit a structured warning at the inflection point), and **DIRTY** (server-side merge conflict — exit and surface). Max `MAX_POLL_MIN` iterations × 60s sleep = `MAX_POLL_MIN`-minute wall-clock cap. Do NOT use foreground `sleep` — Claude Code blocks `sleep` >= 2s in foreground Bash calls.

**Mirror invariant:** the block below is a derived mirror of `plugins/soleur/skills/ship/SKILL.md` Phase 7 (the canonical site). If you edit one, edit both — the canonical site carries the full prose rationale for fail-open required-check fetch, BEHIND budget, and DIRTY semantics. The `ship-phase-7-poll-fixtures.test.sh` fixture extracts and executes BOTH blocks: every scenario (clean merge, required-check failure, DIRTY, BEHIND saturation, and the BEHIND sync-arm rows — conflict, refused, in-progress, push failure, fetch failure, success) runs against this mirror too, and a parity token list pins the arm's spelling — so a behavioural fix applied to one block reddens the suite until it lands in the other. Cross-grep both blocks before pushing anyway; the real-git scenario runs on ship's block only.

```bash
# <!-- phase-7-poll-block:start --> mirror of ship/SKILL.md Phase 7
# BEHIND merge/push: plugins/soleur/scripts/sync-pr-behind.sh --step (edit it there).
PR="<number>"  # bare digits: a pasted `#8474` would print a false "pushed" downstream
[[ $PR =~ ^[0-9]+$ ]] || { echo "[ship.phase7.precondition] PR='$PR' is not a bare PR number — set PR to digits only (no #), then re-arm the poll"; exit 2; }
prev=""; i=0; behind_syncs=0; behind_pushes=0; MAX_BEHIND_SYNCS=6; behind_warned=0
fetch_failures=0  # fetch outages counted separately so behind_exhausted is truthful (#8339)
# Minutes to poll before giving up (one iteration = one `sleep 60`).
# DERIVED, not chosen: measured over the last 12 CI runs on main, a full
# run takes min 22 / median 32 / p90 43 / max 54 minutes, and `test-scripts`
# alone is a median 28. The previous budget was 15, i.e. BELOW the fastest
# run ever observed — so it could not succeed, and every ship run reported a
# spurious timeout on a PR that was merging fine. 60 covers the observed max
# with headroom. This is a BACKSTOP: the loop already exits early on MERGED,
# a failed required check, and DIRTY, so a longer budget costs nothing on
# the healthy paths. Re-derive it if CI wall-clock changes materially.
MAX_POLL_MIN=60
BRANCH=$(git rev-parse --abbrev-ref HEAD)
sync_ok=1
if [[ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" != true ]]; then
  echo "[ship.phase7.precondition] not inside a worktree — BEHIND auto-sync disabled; the poll heartbeats, sync by hand from a worktree"
  sync_ok=0
fi
# Bare ${CLAUDE_PLUGIN_ROOT} + plugin.json identity + --step probe + per-poll snapshot
# (see ship/SKILL.md Phase 7 for the rationale; ADR-179).
# Read once in a `set +u` subshell: a nounset host shell must not die on an unset root.
SYNC_ROOT="$(set +u; printf '%s' "${CLAUDE_PLUGIN_ROOT}")"
SYNC_SH="$SYNC_ROOT/scripts/sync-pr-behind.sh"; SYNC_SNAP=""
if [[ "$sync_ok" -eq 1 ]]; then
  why=""
  if [[ -z "$SYNC_ROOT" ]]; then why="CLAUDE_PLUGIN_ROOT is unset"
  elif ! grep -q '"name"[[:space:]]*:[[:space:]]*"soleur"' "$SYNC_ROOT/.claude-plugin/plugin.json" 2>/dev/null; then
    why="$SYNC_ROOT/.claude-plugin/plugin.json does not name soleur (ADR-179 identity check)"
  elif [[ ! -r "$SYNC_SH" ]]; then why="the script is missing"
  elif ! bash "$SYNC_SH" --help 2>/dev/null | grep -q -- '--step'; then why="its --help has no --step (an older copy)"
  elif ! { SYNC_SNAP="$(mktemp)" && trap 'rm -f "$SYNC_SNAP"' EXIT && cp "$SYNC_SH" "$SYNC_SNAP"; }; then why="the snapshot copy failed"
  fi
  if [[ -n "$why" ]]; then
    echo "[ship.phase7.precondition] sync-pr-behind.sh not usable at '$SYNC_SH': $why — BEHIND auto-sync disabled; export CLAUDE_PLUGIN_ROOT=<the installed soleur plugin root> (Devin/Codex: see that harness's INSTRUCTIONS.md), or sync by hand."
    sync_ok=0
  fi
fi
# REQUIRED_CHECKS is fetched once, fail-open: empty array → no-op scan
# (see ship/SKILL.md Phase 7 for the full rationale; do NOT harden).
mapfile -t REQUIRED_CHECKS < <(gh api 'repos/{owner}/{repo}/rules/branches/main' \
  --jq '[.[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context] | .[]' \
  2>/dev/null || true)
while true; do
  i=$((i+1))
  s=$(gh pr view "$PR" --json state,mergeStateStatus \
      --jq '"\(.state) \(.mergeStateStatus)"' 2>&1) \
    || s="fetch-error: $s"
  if [[ "$s" != "$prev" ]] || (( i % 3 == 1 )); then
    echo "$(date +%H:%M:%S) [${i}/${MAX_POLL_MIN}] PR $PR ${s}"
    prev="$s"
  fi
  echo "$s" | grep -qE "^(MERGED|CLOSED|fetch-error)" && break

  if (( ${#REQUIRED_CHECKS[@]} > 0 )); then
    mapfile -t failed_names < <(gh pr checks "$PR" --json name,bucket \
      --jq '.[] | select(.bucket == "fail") | .name' 2>/dev/null || true)
    if (( ${#failed_names[@]} > 0 )); then
      required_failed=""
      for n in "${failed_names[@]}"; do
        for r in "${REQUIRED_CHECKS[@]}"; do
          [[ "$n" == "$r" ]] && { required_failed="$n"; break 2; }
        done
      done
      if [[ -n "$required_failed" ]]; then
        echo "$(date +%H:%M:%S) [${i}/${MAX_POLL_MIN}] [ship.phase7.required_failed] check='${required_failed}' — exiting poll"
        break
      fi
    fi
  fi

  if [[ "$s" == *DIRTY* ]]; then
    mt_out=""; fetch_rc=0
    git fetch origin main >/dev/null 2>&1 || fetch_rc=$?
    if (( fetch_rc != 0 )); then
      # A fetch outage is not a conflict: report it and let the next tick retry.
      echo "$(date +%H:%M:%S) [${i}/${MAX_POLL_MIN}] [ship.phase7.sync_failed] kind=fetch rc=$fetch_rc — fetch origin main failed while classifying DIRTY — retrying next tick"
    elif mt_out="$(git merge-tree --write-tree origin/main HEAD 2>&1)"; then
      s="OPEN BEHIND"
    elif [[ "$sync_ok" -eq 1 && -f "$SYNC_ROOT/scripts/resolve-regenerable-conflicts.sh" ]] \
         && bash "$SYNC_ROOT/scripts/resolve-regenerable-conflicts.sh" origin/main; then
      # ADR-235: the resolver merged and regenerated model.likec4.json from the MERGED
      # sources and committed locally; it never pushes. Treat the state as BEHIND so the
      # push goes through the one implementation below: sync_step's merge is then a no-op
      # and HEAD is ahead of its upstream, so it pushes (or stops with kind=push).
      echo "$(date +%H:%M:%S) [${i}/${MAX_POLL_MIN}] [ship.phase7.dirty] regen resolved — merge committed locally; pushing via sync-pr-behind.sh"
      s="OPEN BEHIND"
    else
      echo "$(date +%H:%M:%S) [${i}/${MAX_POLL_MIN}] [ship.phase7.dirty] PR is DIRTY (merge conflict) — exiting poll"
      echo "Conflicted paths (merge-tree; no merge is in progress, so --diff-filter=U is empty):"
      printf '%s\n' "$mt_out" | grep '^CONFLICT ' || true
      echo "Resolve locally: git merge origin/main"
      break
    fi
  fi

  if [[ "$s" == "OPEN BEHIND" && "$sync_ok" -eq 1 && "$behind_syncs" -lt "$MAX_BEHIND_SYNCS" ]]; then
    behind_syncs=$((behind_syncs+1))
    echo "$(date +%H:%M:%S) [${i}/${MAX_POLL_MIN}] BEHIND detected — auto-sync attempt ${behind_syncs}/${MAX_BEHIND_SYNCS}"
    sync_rc=0; bash "$SYNC_SNAP" "$PR" --step || sync_rc=$?   # errexit-safe (#8339)
    case "$sync_rc" in
      0) echo "$(date +%H:%M:%S) [${i}/${MAX_POLL_MIN}] auto-sync ${behind_syncs}/${MAX_BEHIND_SYNCS} pushed"
         behind_pushes=$((behind_pushes+1))
         (( behind_pushes == 2 )) && echo "$(date +%H:%M:%S) [${i}/${MAX_POLL_MIN}] [ship.phase7.hatch_check] 2 BEHIND syncs pushed — read ${CLAUDE_PLUGIN_ROOT}/skills/ship/references/settle-then-admin-merge.md now; it classifies eligibility (else keep polling)"
         s=$(gh pr view "$PR" --json state,mergeStateStatus \
             --jq '"\(.state) \(.mergeStateStatus)"' 2>&1) \
           || s="fetch-error: $s"
         echo "$s" | grep -qE "^(MERGED|CLOSED|fetch-error)" && break ;;
      11) behind_syncs=$((behind_syncs-1))  # no-op: GitHub state lag, not a sync — budget and hatch untouched
          echo "$(date +%H:%M:%S) [${i}/${MAX_POLL_MIN}] [ship.phase7.sync_noop] main already merged and pushed; mergeStateStatus lags — not counted, polling on" ;;
      5) fetch_failures=$((fetch_failures+1))
         echo "$(date +%H:%M:%S) [${i}/${MAX_POLL_MIN}] [ship.phase7.sync_failed] kind=fetch — skipping this sync attempt" ;;
      *) echo "$(date +%H:%M:%S) [${i}/${MAX_POLL_MIN}] [ship.phase7.sync_failed] sync-pr-behind.sh exited $sync_rc (see its line above). Stopping the poll."
         break ;;
    esac
  elif [[ "$s" == "OPEN BEHIND" && "$sync_ok" -eq 0 ]]; then
    echo "$(date +%H:%M:%S) [${i}/${MAX_POLL_MIN}] [ship.phase7.behind_no_sync] PR $PR is BEHIND and auto-sync is disabled (precondition line above). From the PR worktree run:" 'bash "${CLAUDE_PLUGIN_ROOT}/scripts/sync-pr-behind.sh"' "$PR" "after export CLAUDE_PLUGIN_ROOT=<the installed soleur plugin root>; exit 8 after a kind=pushed line means the push landed. Then re-arm the poll. Stopping the poll."
    break
  elif [[ "$s" == "OPEN BEHIND" && "$sync_ok" -eq 1 && "$behind_syncs" -ge "$MAX_BEHIND_SYNCS" && "$behind_warned" -eq 0 ]]; then
    elapsed=$((i * 60))
    if (( fetch_failures == MAX_BEHIND_SYNCS )); then
      echo "$(date +%H:%M:%S) [${i}/${MAX_POLL_MIN}] [ship.phase7.behind_exhausted] BEHIND budget exhausted after ${MAX_BEHIND_SYNCS} auto-syncs in ${elapsed}s (fetch_failures=${fetch_failures}/${MAX_BEHIND_SYNCS}). Every attempt failed at git fetch — a network/credential outage, not main moving. Check connectivity and credentials, then re-arm the poll."
    else
      echo "$(date +%H:%M:%S) [${i}/${MAX_POLL_MIN}] [ship.phase7.behind_exhausted] BEHIND budget exhausted after ${MAX_BEHIND_SYNCS} auto-syncs in ${elapsed}s (fetch_failures=${fetch_failures}/${MAX_BEHIND_SYNCS}; attempts that failed at fetch never synced). origin/main is moving faster than this PR's CI cycle. Recommendation: for a zero-conflict-surface change, use the settle-then-admin-merge escape hatch (admin-merge-ready.sh <PR> <sha> must exit 0, then gh pr merge --squash --admin --match-head-commit <sha> — full procedure: ${CLAUDE_PLUGIN_ROOT}/skills/ship/references/settle-then-admin-merge.md); else merge during a quieter window."
    fi
    behind_warned=1
  fi

  if [ "$i" -ge "$MAX_POLL_MIN" ]; then
    echo "Merge poll timed out after ${MAX_POLL_MIN} minutes. Last state: $s"
    break
  fi
  sleep 60
done
# <!-- phase-7-poll-block:end -->

```

If the loop exits with state `CLOSED` (not `MERGED`), auto-merge was cancelled — check for CI failures:

```bash
gh pr checks --json name,state,description | jq '.[] | select(.state != "SUCCESS")'

```

Stop and report:

```text
STOPPED: CI check failed.

Failed checks:
<check name>: <description>

Starting SHA for rollback: <starting-sha>
To rollback: git reset --hard <starting-sha> && git push --force-with-lease origin <branch-name>

```

The state-machine details (`mergeStateStatus` enum coverage, fail-open required-check fetch, fixture at `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh`) are documented in `plugins/soleur/skills/ship/SKILL.md` Phase 7. When the poll prints `[ship.phase7.hatch_check]` (2 BEHIND syncs pushed) or `[ship.phase7.behind_exhausted]`, read [settle-then-admin-merge.md](../ship/references/settle-then-admin-merge.md) for the settle-then-admin-merge escape hatch (zero-conflict-surface changes only). Any `--admin` merge, whether through this hatch or authorized by the operator, requires `plugins/soleur/scripts/admin-merge-ready.sh <PR> <sha>` to exit 0 immediately before it and `--match-head-commit <sha>` on the merge; `gh pr checks --required` is not a substitute, because it cannot see a required check that has not been created yet (#8458, #8500). When the operator authorizes `--admin` on a BEHIND PR whose prior head was green, the surface classifier is waived but the gate is not: `--green-sha <prior-green-sha>` carries the certification to the new head only if it is GitHub's own verified merge of that sha and the base (see the reference's "was-green carryover" section); UNTRUSTED-CI and DIRTY still refuse. On `[ship.phase7.required_failed]` or `[ship.phase7.dirty]`, follow ship/SKILL.md Phase 7's handling for a poll that exits on a required-check failure or a DIRTY state (`gh pr checks <N>` to inspect; `git merge origin/main` to resolve locally). On a `[ship.phase7.sync_failed]` line ending `Stopping the poll.` (a `kind=fetch` one is informational — the poll continues), do the next action the `[pr-behind-sync] kind=…` line above it names (resolve and push, reconcile a concurrent push, or clear the worktree state), then re-invoke this §5.2 poll — a routine conflict is not an operator handoff. `[ship.phase7.sync_noop]` is GitHub state lag (uncounted; the poll continues); `[ship.phase7.behind_no_sync]` means auto-sync was disabled — run the printed command from the PR worktree, then re-arm the poll.

## Phase 6: Cleanup and Report

### 6.1 Navigate to repo root

The `cleanup-merged` script skips the current working directory's worktree. Navigate to the main repo root first:

Navigate to the main repository root directory (the parent of `.worktrees/`). Run `cd` to the repo root path, then verify with `pwd`.

### 6.2 Run cleanup

```bash
bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/git-worktree/scripts/worktree-manager.sh cleanup-merged

```

This reaps branches proven merged (an ancestor of main, or a merged same-repo PR whose head contains the branch tip — the path a squash-merged, auto-deleted branch takes), removes their worktrees, deletes the local branches, and pulls latest main. A `[gone]` branch with no merge evidence is kept and reported so the next worktree branches from the current state.

### 6.3 End-of-run report

Print a summary:

```text
merge-pr complete!

PR: #<number> (<URL>)
Merge SHA: <sha>
Cleanup: <worktrees cleaned or "no cleanup needed">

Rollback (if needed): git reset --hard <starting-sha>

```

Replace `<starting-sha>` with the SHA recorded at the start of the pipeline.

## Rollback

If the pipeline fails partway through and the branch has unwanted commits (e.g., merge commit), rollback to the starting state:

```bash
git reset --hard <starting-sha>
git push --force-with-lease origin <branch-name>

```

Replace `<starting-sha>` and `<branch-name>` with the actual values recorded at pipeline start.

The starting SHA is recorded in Phase 0 and printed in the end-of-run report.

## Important Rules

- **On any failure: stop and report.** Do not retry, do not guess, do not continue.
- **Never use `--delete-branch`** with `gh pr merge`. Use `cleanup-merged` for branch deletion.
- **Never commit on main.** All commits happen on the feature branch.
- **CHANGELOG integrity is critical.** Read both sides via `:2:` and `:3:` stage numbers. Verify line count after writing. Never truncate.
