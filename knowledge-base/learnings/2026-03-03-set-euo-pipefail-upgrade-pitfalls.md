# Learning: set -euo pipefail upgrade pitfalls in dispatch scripts

## Problem

During the standardize-shebang session, `worktree-manager.sh` was upgraded from bare `set -e` to `set -euo pipefail`. The deepen-plan audit had reviewed the script and reported zero incompatibilities. Two bugs were introduced silently:

### Trap 1: Bare positional args abort under nounset

The `main()` dispatch function used bare `$2` and `$3` to forward optional arguments to subcommands:

```bash
create)
  create_worktree "$2" "$3"
  ;;
```

Under `set -u` (nounset), referencing `$2` or `$3` when only one argument was passed aborts the script immediately with `unbound variable`. Callers that invoked `worktree-manager.sh cleanup-merged` (no second arg) would silently fail at the dispatch level.

### Trap 2: grep-in-pipeline exits 1 under pipefail when no match

The `cleanup_merged_worktrees()` function used:

```bash
gone_branches=$(git for-each-ref ... | grep '\[gone\]' | cut -d' ' -f1)
```

Under `set -o pipefail`, if `grep` finds no matches it exits with code 1. Because this is inside a command substitution assigned to a variable, the non-zero exit from `grep` propagates through the substitution and aborts the script before `gone_branches` is even checked. The script would fail every time there were no gone branches -- exactly the clean-state case used in CI.

## Solution

### Fix 1: Guard optional positional args with `${N:-}`

Replace bare references with default-empty expansion:

```bash
create)
  create_worktree "${2:-}" "${3:-}"
  ;;
feature|feat)
  create_for_feature "${2:-}" "${3:-}"
  ;;
```

`${2:-}` expands to the empty string if `$2` is unset, satisfying nounset without changing behavior (the called function already validates its own args).

### Fix 2: Append `|| true` to grep pipelines

```bash
gone_branches=$(git for-each-ref --format='%(refname:short) %(upstream:track)' refs/heads 2>/dev/null | grep '\[gone\]' | cut -d' ' -f1 || true)
```

`|| true` ensures the pipeline always exits 0, regardless of whether grep finds any matches. The subsequent `if [[ -z "$gone_branches" ]]; then` block handles the empty case correctly.

## Key Insight

`set -euo pipefail` introduces three independent failure modes, each requiring its own audit:

| Flag | Risk | Pattern to check |
|------|------|-----------------|
| `-e` (errexit) | Any command exits non-zero | Commands whose failure is intentional (e.g., `grep`, `git diff`) must use `|| true` or `if !` |
| `-u` (nounset) | Any unset variable is referenced | Bare `$N` for optional positional args in dispatch functions; `${N:-}` or `[[ $# -ge N ]]` guards required |
| `-o pipefail` | First non-zero exit in a pipeline propagates | `grep \| cut` and similar pipelines that legitimately return non-zero on no-match must use `|| true` |

Static code review often catches `-e` risks (commands known to fail) but misses `-u` risks in dispatch tables (the positional args look fine when the script is invoked with all args) and `-o pipefail` risks in command substitutions (the pipeline looks correct until the no-match case is tested).

**Audit checklist for `set -euo pipefail` upgrades:**

1. Search for all `$[0-9]` bare references -- add `${N:-}` or `${N:-default}` for optional args
2. Search for all pipeline-in-command-substitution patterns (`$(... | grep ...)`) -- add `|| true` if the pipeline may legitimately return non-zero
3. Test the script with *fewer* args than each dispatch branch accepts
4. Test the script in the case where each pipeline has zero matches

## Session Errors

1. **Deepen-plan audit false negative** -- The audit subagent reviewed the script and declared zero incompatibilities. It missed both traps above because it analyzed the happy path (all args provided, grep finds matches) rather than boundary cases. Audit prompts for strict-mode upgrades should explicitly instruct the subagent to enumerate all optional-arg dispatch paths and all grep/pipeline patterns.
2. **No test run before declaring done** -- The script changes were committed without running `worktree-manager.sh cleanup-merged` in a clean environment (no gone branches). The grep trap would have surfaced immediately.

## Tags
category: runtime-errors
module: plugins/soleur/skills/git-worktree
