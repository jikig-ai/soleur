---
module: run-health emit
date: 2026-11-20
problem_type: workflow_issue
component: tooling
symptoms:
  - "run-health-emit.sh --status with no value hung until timeout rc 124 and printed nothing"
  - "--seal --import-tally stored an empty tally_show when pipeline-tally.sh was not on PATH"
  - "one-shot and test-fix-loop did not invoke run-health-emit.sh --seal, so the ledger never sealed"
  - "discover mktemp had no owning EXIT trap and lint-trap-tempfile-ownership raised class-b high-water above 36"
root_cause: missing_workflow_step
resolution_type: workflow_improvement
severity: medium
status: open
tags: [run-health, fail-open, seal, workflow]
---

# Troubleshooting: A run-health pointer is not a seal call

## Problem

The helper that writes `.soleur/runs/<run-id>/run_health.json` already existed, and the pipeline skills did not call it. A sentence that names `bash`, `run-health-emit.sh`, and `--seal` satisfied a careless grep while no ledger was sealed. Wiring the real call exposed two fail-open bugs: a missing flag value spun the argument loop, and tally import stored an empty string when the sibling script was not on `PATH`.

## Environment

- Module: plugins/soleur scripts and the one-shot / test-fix-loop skills
- Affected Component: `plugins/soleur/scripts/run-health-emit.sh` and `plugins/soleur/skills/one-shot/references/run-health-schema.md`
- Date: 2026-11-20
- Stage: post-implementation, issue #12573

## Symptoms

- `timeout 2` on `--status` with no value returned rc 124 and empty stderr.
- `PATH=/usr/bin:/bin` plus `--seal --import-tally` stored `tally_show=''`.
- The skill files had no `bash` invocation of the helper, so a run directory was never sealed.
- `scripts/lint-trap-tempfile-ownership` reported `run-health-emit.sh` discover `mktemp` with no owning trap. Class-b high-water went to 37, above the accepted 36.

## What Didn't Work

**Attempted Solution 1:** Treat the skill-file sentence that contains `bash`, `run-health-emit.sh`, and `--seal` as the producer call.

- **Why it failed:** The sentence is prose. Deleting the schema fences left that grep green. The call that must stay is the fenced seal line in `run-health-schema.md`.

**Attempted Solution 2:** Turn the helper into `set -euo pipefail` and exit 1 on a bad argument.

- **Why it failed:** The helper is specified fail-open. A missing value must print `run-health-emit:` on stderr and exit 0. `set -e` would also change the `shift` failure into an abort instead of the guarded exit.

**Attempted Solution 3:** Count `goto_count` from the planner sentence `verb=goto`.

- **Why it failed:** The shipped rule counts full lines whose stripped text is exactly `verb: goto` in the session-state file passed with `--session-state`. A prose `verb=goto` does not count.

## Session Errors

**1. The commit hook denied `cd && git commit` and `git -C "$WT"`.** The hook reads the command text. `$WT` is not expanded, so the path does not prove a worktree commit.

- **Recovery:** Commit with a literal `git -C /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-12573-run-health-emit`.
- **Prevention:** Pass a literal worktree path on the commit segment. The same class is already recorded in [git -C with a variable path](./workflow-patterns/2026-10-25-git-c-with-variable-path-is-denied-like-a-bare-commit.md).

**2. Git, tally, lint, and `wc -c` ran from the main checkout and read the wrong tree.** `pipeline-tally.sh show` hit the default-branch ledger. The first helper test saw a different 5-case file. `wc -c` of one-shot SKILL.md read 51995 there, while `git show HEAD:plugins/soleur/skills/one-shot/SKILL.md` in the worktree is 51594. The compound branch check in this same session printed `main` at `e3046c2be9`.

- **Recovery:** Re-run with `git -C` the worktree, or `cd` the worktree before the script. The worktree branch is `feat-one-shot-12573-run-health-emit` and HEAD is `b4b01737e2951e919ced8e4198527d8fc8583c84` before this learning.
- **Prevention:** Any command that reads branch, tally, or skill bytes names the worktree absolute path. A visible wrong branch name is the discoverability exit, so this learning is the record and no AGENTS.md line is added.

**3. `grok-pre-push-gate.sh` on `705ec1a1eb` failed trap ownership.** `run-health-emit.sh` discover `mktemp` had no owning trap. The long unaccounted tail was fail-fast after that lint.

- **Recovery:** Register the `EXIT` trap in the discover arm after `mktemp` succeeds. Commit `40cfd645ad`. A later gate on that commit passed. The accepted population stays 36.
- **Prevention:** The lint is the guard. Fail-open and exit 0 do not exempt a `mktemp` from an owning trap. Do not add `set -e`.

**4. Required `quality-guards` failed MD046 on `plugins/soleur/skills/test-fix-loop/SKILL.md`.** An older indented `git add` line sat beside new fenced blocks, so markdownlint's consistent style expected fences.

- **Recovery:** Put that one command in a fenced bash block. Commit `980ef4cb65`. Local markdownlint on that file exited 0.
- **Prevention:** Before pushing a markdown edit that introduces a fence, convert sibling indented code blocks in that same file. CI `quality-guards` is the corpus check.

**5. `technical-ruling-gate.sh --branch` exited 1 on ten unruled cells.**

- **Recovery:** Rewrite each cell to `Ruled by CTO agent, 2026-11-20:`. Re-run printed PASS. Commit `f7ad4090af`.
- **Prevention:** The gate is the guard. Do not spawn a second CTO when the re-run passes. The session-state `### Errors` line that still says the gate failed is stale. The addendum is the current record.

**6. `gh issue view --comments --json` rejected the combined flags.**

- **Recovery:** Read comments with `gh api`.
- **Prevention:** One-off. The error names the illegal combination. Do not retry the same flag pair.

**7. The planner Decisions bullet said `verb=goto`. The ruling that shipped counts full lines `verb: goto`.**

- **Recovery:** The addendum records the supersession. The unit test pins the line form.
- **Prevention:** Re-measure the shipped sentence against the test, not against the planner's earlier wording. A residual-zero grep for the old spelling does not prove the count is right.

**8. `grep -q budget-capped` on session-state exited 0.** The addendum contains the word. The run status was not `budget-capped`.

- **Recovery:** Read the status line. Do not halt and do not increment `fix_rounds` for that match.
- **Prevention:** Match a status field before treating a bare token in a spec as a halt marker.

**9. `### Decisions` still states the planner goto sentence after the ruling shipped.** The pipeline rule is to append an addendum, not to rewrite the old section.

- **Recovery:** The addendum dated 2026-11-20 is the source that ships.
- **Prevention:** A reader who stops at `### Decisions` inherits a false sentence. Read the latest addendum before quoting a session-state decision.

**10. A foreign `test-all.sh` in another worktree held the shared lock and surfaced `CAPACITY_CONTENDED`.**

- **Recovery:** Treat it as lock contention from a sibling worktree, not as a failure of this helper. Do not start a second affected battery for this HEAD.
- **Prevention:** Name the lock holder before classifying a contended battery as a product failure.

**11. A probe that mixed `--discover` with `rm -rf` of a temp dir was denied.** The worktree incident log records `guardrails-block-recursive-delete` at 2026-11-20T14:01:17Z.

- **Recovery:** The discover arm's own `EXIT` trap and success-path `rm` remove the temp dir. A later `--discover` printed `ok`.
- **Prevention:** Already hook-enforced. Do not put `rm -rf` in a probe command. Let the script own its temp dir.

## Solution

Keep the helper fail-open. Guard every value flag before `shift 2`. Put `pipeline-tally.sh`'s directory on `PATH` only for the tally capture. Seal from the schema fence, with `--session-state` bound on the previous line. Own the discover temp dir with an `EXIT` trap. Leave `plugins/soleur/skills/one-shot/SKILL.md` at 51594 bytes. The ceiling stays 52000. The skill file only points at the schema.

```bash
# Missing value: exit 0, do not spin, do not add set -e.
--status)
  [[ $# -ge 2 ]] || { echo "run-health-emit: --status requires a value" >&2; exit 0; }
  STATUS="$2"
  shift 2
  ;;
```

```bash
# Tally import. A PATH stub in front of this script's directory still wins.
_tally_dir="$(cd "$(dirname "$0")" && pwd)"
TALLY_SHOW="$(PATH="${PATH}:${_tally_dir}" pipeline-tally.sh show 2>/dev/null)" || TALLY_SHOW=""
```

```bash
# Discover arm, after mktemp succeeds. Recursive children do not inherit the trap.
d="$(mktemp -d -t runhealth-discover.XXXXXXXX)" || { echo "run-health-emit: mktemp failed" >&2; exit 0; }
trap 'rm -rf -- "${d:-/nonexistent}"' EXIT
```

```bash
# The producer call. A prose sentence that contains these tokens is not this line.
SESSION_STATE="knowledge-base/project/specs/<branch>/session-state.md"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/run-health-emit.sh" \
  --run-dir "$RUN_DIR" --status failed --seal \
  --session-state "$SESSION_STATE" --import-tally
```

`bash plugins/soleur/scripts/run-health-emit.test.sh` printed `passes=27 fails=0` after the helper, the pins, and the trap. `--discover` prints `ok` and leaves no `runhealth-discover.*` directory.

## Why This Works

1. The root cause is a missing call plus two loops that fail open into the wrong success. The skill pointer documented the obligation. The schema fence performs it. The test greps the fence, so deleting `--session-state "$SESSION_STATE"` goes red.
2. On bash 5.3, `shift 2` with one argument left returns 1 and does not consume the flag. The next iteration sees the same flag. The `$#` check exits 0 before that shift. The required stderr line is `run-health-emit: --status requires a value`.
3. Tally import was a bare `pipeline-tally.sh` lookup. Prefixing `PATH` with the helper's directory finds the sibling. The `||` keeps fail-open when show fails. A test PATH stub still precedes that directory, so a stub that prints `UNKNOWN` is what the empty-counter case asserts.
4. The trap runs on process death before the success-path `rm`. Explicit `exit 0` still exits 0. The lint's high-water check stays at the accepted population.

## Prevention

- Pin the seal invocation in the schema file, including `--session-state "$SESSION_STATE"` and `--import-tally`. Do not pin it by a prose sentence in one-shot SKILL.md.
- For a fail-open bash flag loop, test one value-flag with its argument omitted and assert exit 0 plus the exact stderr line. Do not add `set -e` to make `shift` abort.
- A new `mktemp` in a shell script needs an owning trap in that same arm even when the script exits 0 on every error path.
- When a markdown skill gains its first fence, convert older indented blocks in that file so MD046 consistent style stays fenced.
- Do not edit one-shot `description:` or `plugins/soleur/test/skill-body-budget.json` to make room. The pointer block is the whole one-shot edit this slice allows.
- Archive `knowledge-base/project/specs/<branch>/` and the plan in ship Phase 6.45, after step 2.5 has read `decision-challenges.md` from the live path. This plan has no deferral sentence of its own. Ship's live-path read is why compound does not archive first.

## Related Issues

- See also: [shift 2 with one argument left](./2026-09-03-the-deviation-ledger-was-an-hour-of-my-own-test-fixtures.md). That note's prevention is `shift 2 || shift`. This helper stays without `set -e`, so the guard is the `$#` check and exit 0.
- See also: [git -C with a variable path](./workflow-patterns/2026-10-25-git-c-with-variable-path-is-denied-like-a-bare-commit.md).
- See also: [archive before the live read](./2026-09-18-every-instrument-i-built-to-check-the-guards-needed-checking.md).
- Subject issue: #12573. Parent epic stays open.
