---
title: "A `grep -q` inside a pipefail pipeline made the trigger silently miss the bug class it was built for"
date: 2026-10-01
category: engineering
tags: [bash, pipefail, grep-q, code-review, hooks, env-scrub, ratchet-lane, issue-9400]
---

# Learning: a `grep -q` inside a pipefail pipeline silently inverts

## Problem

Issue #9400 asked for a fast pre-push lane that runs only the ratchets a diff can
trip, evaluated on the *merged* branch+`origin/main` tree. The first design-pass
review round of PR #9409 produced a cluster of defects whose common theme is
**a fail-safe that quietly fails open** — each one looked correct in isolation
and each one would have silently degraded the gate at exactly the moment it
mattered:

1. `printf '%s\n' "$diff" | grep '^+' | grep -v '^+++' | grep -qF 'knowledge-base/'`
   under `set -o pipefail`: `grep -q` exits on first match, SIGPIPE kills the
   upstream greps, the pipeline returns **141** — read as *no match*. The F2
   trigger (`kb-consumers`) would have nondeterministically missed on exactly
   the large diffs it exists to catch. Two review seats flagged it independently;
   the repo's own suite header already stated the rule ("never `producer |
   grep -q` under pipefail — grep a FILE instead") and I wrote the violation
   anyway.
2. `trap cleanup EXIT INT TERM HUP` runs the handler and then **resumes**
   dispatch on INT/TERM/HUP — cleanup deletes `$PARENT` and every subsequent
   member log write fails into a deleted directory, cascading false-REDs.
3. `_reason="$(conditional_reason)"` runs the function in a capture subshell —
   an internal `assert_fixture_dir` FATAL exits the subshell with rc 2, which the
   `if` reads as "no trigger" → benign SKIP. An infra abort laundered into a
   skip.
4. `grep -qF 'knowledge-base/'` on *every* branch-touched file (the pre-review
   shape) fired on ~73% of commits — the 4–11 min conditional member would have
   run on nearly every push, collapsing the lane's 1–2 min cost contract.

## Solution

The fixes that generalize:

- **Filter diffs to a file, then grep the file.** `git diff -U0 … > f; grep '^+' f | grep -v '^+++' > g; grep -qF needle g` — `grep -q` against a file operand has no upstream to SIGPIPE.
- **Signal traps exit, they don't just clean up.** `trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM; trap cleanup EXIT` — cleanup runs once via EXIT.
- **Distinguish subshell rc 1 from rc 2** when a capture-subshell function can FATAL: `_out="$(fn)" || _rc=$?; (( _rc == 2 )) && abort …` — never let a guard exit read as a false return.
- **Restated literal sets are drift liabilities.** `KB_CONSUMERS_INPUTS` and the
  deps-group list both restate system-owned enumerations — pinned by parity arms
  that read the system's own source (`AFFECTED_…_PATHS` array, TEST_GROUP enum).
  Where a registry exists (`--enumerate-commands`), consult it at runtime rather
  than mirroring it.
- **env -i is the honest boundary for hook-executed dispatch.** Ambient
  `GIT_SSH_COMMAND`/`GIT_CONFIG_*`/`BASH_ENV`/`LD_*` are exec vectors,
  `GH_TOKEN`/`_TOKEN`/`_SECRET` leak credentials into member environments, and
  runner-control vars (`TEST_GROUP`, `SCRIPTS_SHARD`, `SOLEUR_SUBAGENT`,
  `SOLEUR_TEST_FORCE_ALL`) corrupt nested `test-all.sh` probes — `TEST_GROUP`
  env *overrides* the positional group arg, silently enumerating the wrong group.
- **The lane's own dogfood caught two real merged-tree defects on its first
  green-seeking run:** a `retain_log` `cp` whose destination chained to a
  command substitution the operand scanner couldn't prove absolute, and a
  `skill-body-budget` ceiling trip that exists only in the branch+main merge
  (main had extended `ship/SKILL.md` since the fork) — the exact F1-class
  "red only post-merge" shape the lane exists to catch.

## Session Errors

1. **Wrote a `producer | grep -q` under pipefail** despite the constraint being
   documented in the suite's own header.
   **Prevention:** when a diff filter must feed a `-q` probe, write the filtered
   stream to a file and grep the file — the corpus rule now has a second witness.
2. **Test-needle concatenation:** asserted `verdict=SKIP reason=not-a-suite` on
   receipt lines that interleave `seconds=0` between the two fields.
   **Prevention:** assert member lines as separate `has` calls per field, or pin
   the exact format with `seconds=` included.
3. **`[a-z, ]` sed class dropped `scripts-heavy` and `infra` from the TEST_GROUP
   enum extraction** (hyphen absent), then a trailing-space artifact produced an
   empty expected entry — two iterations to extract a comma list correctly.
   **Prevention:** extract enum lists with a permissive capture then split on
   `,` and ` ` with empties filtered.
4. **Todo-write consolidation triggered a false "removed items" warning.**
   **Prevention:** one-off; cosmetic, no action.
5. **`ps | grep` self-match hook rejection** when probing for running test-all
   processes.
   **Prevention:** the hook message itself names the fix — use argv-slot awk or
   `pgrep` without `-f`.

## Prevention

- Lane suite pins every fixed defect: removal-side trigger arm (4h), DECLINED
  parse arm, lib-registered dispatch arm, enumerate-degrade receipt arm,
  unknown-tier arm, budget-abort arm, arm-13a member-verdict tightening, plus
  `KB_CONSUMERS_INPUTS`/TEST_GROUP parity arms (arm 21).
- The `grep -q`-under-pipefail hazard is now documented twice (suite header +
  this learning); a corpus lint for the shape is worth filing if it recurs a
  third time.
- See PR #9409 / plan `knowledge-base/project/plans/2026-10-01-chore-affected-ratchets-pre-push-lane-plan.md`.
