---
module: plugins/soleur/test + .github/workflows
date: 2026-09-14
problem_type: test_failure
component: testing_framework
symptoms:
  - "git-fixture-env-shell.test.sh fails 14/10 when invoked under a real git hook env (blocks commits staging plugins/soleur/test/)"
  - "Guard-2 recovery recipe prints `5` where its own prose promises only `0` or `1`"
  - "an env-var-gated replay arm can be silently skipped by the very ambient env it simulates"
root_cause: test_isolation
resolution_type: test_fix
severity: high
status: closed
tags: [git, environment-variables, test-isolation, hooks, grep, anchoring, operator-recovery, vacuous-test]
synced_to: [review]
---

# Troubleshooting: GIT_* Hook-Env Leak in a Shell Fixture Suite + Unanchored Recovery Grep

## Problem

Two sibling defects in operator/developer tooling, fixed in one PR (#8154, closing #8051 and #8053):

1. `plugins/soleur/test/git-fixture-env-shell.test.sh` failed under any real `git commit` hook environment — Git injects `GIT_DIR`, `GIT_INDEX_FILE`, `GIT_AUTHOR_*`, `GIT_COMMITTER_*`, `GIT_EDITOR`, `GIT_PREFIX`, `GIT_EXEC_PATH`, and more into hook processes, and every child of the suite inherited them. The ambient values were indistinguishable from leakage produced by the function under test, so commits staging files under `plugins/soleur/test/` were blocked.
2. The Guard-2 recovery recipe in `.github/workflows/apply-web-platform-infra.yml` told the operator to run `grep -c "probe_schema=$EXPECTED"` and promised the result would be `0` or `1`. Unanchored, the grep also matched comment lines repeating the token and printed `5` — an operator reading its own instructions could not tell which branch they were in.

## Environment

- Module: `plugins/soleur/test` (bash fixture suite) + `.github/workflows/apply-web-platform-infra.yml` (recovery message) + `scripts/cutover-inngest.sh` (sibling recipe)
- Affected component: git-fixture-env test harness; Guard-2 volume-recut recovery instructions
- Date: 2026-09-14

## Symptoms

- Suite reported `14 passed, 10 failed` when run inside a `git commit` hook; `25/0` clean.
- `grep -c "probe_schema=$EXPECTED"` printed `5` on a file containing one assignment and four comment mentions.
- A mutation check confirmed the new replay arm fails correctly when the scrub is deleted.

## What Didn't Work

**Attempted Solution 1 (pre-existing, #7976):** A five-name `env -u GIT_DIR -u GIT_INDEX_FILE …` chain.

- **Why it failed:** Git exposes far more than five `GIT_*` variables to hooks, and the set grows; any finite name list goes stale. Measured: a real hook env still broke the suite 14/10 after the five-name fix landed.

**Attempted Solution 2 (review round):** An environment-variable flag `_GFE_HOOK_ENV_REPLAY=1` to guard the inner replay arm.

- **Why it failed:** The flag lives in the same channel the arm exists to defend against. An externally supplied `_GFE_HOOK_ENV_REPLAY=1` selects the inner "already replayed" branch and the suite reports the arm green having replayed nothing — a silent vacuity vector.

## Session Errors

**Row 6d "non-comment" needle was too strict (`^[^#]*`)**

- **Recovery:** Changed to "first non-blank character is not `#`" (`^[[:space:]]*[^#[:space:]]`) — the message line legitimately contains `(#7695;` before the grep.
- **Prevention:** When asserting "not a comment," match the line's first token against the comment introducer; a `#` may legitimately appear later in content (issue refs, fragments).

**Row 6d needle over-escaped the trailing `$`**

- **Recovery:** Wrote the needle as the file's actual bytes `\$EXPECTED$` (backslash only before the first `$`).
- **Prevention:** Extract pin needles from the target file's real bytes (read it, copy the literal), not from remembered syntax.

**Coverage consult lead was a false positive (MIN_ASSERTIONS floor drift)**

- **Recovery:** Self-verified — deleting the replay arm drops the ledger to 24 < floor 25 → FATAL. Dropped the lead.
- **Prevention:** Consult output is a lead list, not a finding list; verify each against the code before implementing.

**Row 6e negative pin matched its own historical prose (`["']*`)**

- **Recovery:** Required a literal quote before `probe_schema=` (`["']probe_schema=`), so the deliberate `'grep -c probe_schema=3'` prose quote is not flagged while real unanchored reversions are.
- **Prevention:** A negative regression pin that greps for a forbidden pattern must distinguish prose *quoting* the forbidden form from the executable form — constrain on executable shape, not bare content.

**`TEST_GROUP=scripts bash scripts/test-all.sh` exited 4**

- **Recovery:** Read the refusal output — the contention guard measured sibling full-gate runs and recommended running touched suites; those were already green. rc=4 is a refusal, not a failure.
- **Prevention:** Distinguish the guard's structured refusal exit from test failure before investigating.

**Forwarded from planning phase:** #8051's premise was partially stale (#7976 landed a five-name fix one day after filing); #8053's file attribution was wrong (recovery message lives in the workflow, not the lib script).

- **Recovery:** Plan's Research Reconciliation re-targeted both before implementation.
- **Prevention:** Re-derive issue premises against current `main` at plan time — filed issues age.

**Ship-time advisor consult found the recipe's `git show` lacked its `:path` (post-review, post-QA)**

The Guard-2 recipe ran `git show $(…)` on the bare tag — dumping the commit, not the bootstrap script — so `^probe_schema=` could never match and the promised `1` was unreachable (always read as `0`, "don't replace"). QA's AC6 run had verified the *intended* `tag:path` form, not the recipe's verbatim bytes; nine review seats missed it because no pin covered the `git show` operand itself.

- **Recovery:** `git show "${TAG:?…}:apps/web-platform/infra/inngest-bootstrap.sh"`; `${EXPECTED:?}`/`${TAG:?}` make the prose's "an ERROR instead of a count" literally true; pins 6i (`git show .*:path`) and 6j (`:?` guards) added; Row 6g gained the `^[[:space:]]*` it claimed to pin.
- **Prevention:** A recovery recipe embedded in an error string must be *executed verbatim* against a real fixture (the pinned tag), not verified by paraphrase — and every operand of the recipe (`git show` spec, extraction pipeline, count) needs its own pin, not just the final grep.

## Solution

**#8051 — two-layer prefix scrub (name-prefix, not name-list):**

```bash
# Suite top, immediately after `export TMPDIR` — before repo discovery or any child:
for _v in ${!GIT_@}; do
  [[ "$_v" == "GIT_LOCATION_VARS" ]] && continue
  unset "$_v"
done
unset _v
```

- `${!GIT_@}` enumerates every variable with the `GIT_` prefix — robust against future Git env vars the way a name list is not.
- `GIT_LOCATION_VARS` is exempted (suite-owned state).
- A second, probe-local scrub runs before sourcing the fixture library so the probe reports builder state even if the suite-level scrub is reverted — verified by mutation: commenting out the ambient scrub makes the replay arm report `[FAIL]`, exit 1.

**Regression arm — argv-gated, not env-gated:**

```bash
if [[ "${1:-}" == "--hook-env-replay" ]]; then
  ok "inner replay run (the outer invocation supplied the hook env)"
```

The outer arm re-execs the suite with the ten hook-shaped variables injected. `GIT_EXEC_PATH` points at a deliberately nonexistent path under the trap-cleaned `_FIXTURE_ROOT`, so an unsanitized environment fails loudly. A scrub-residue self-check greps the suite for the `${!GIT_@}` idiom, catching a reversion to a finite name list.

**#8053 — anchored, right-bounded, failure-guarded recipe:**

```bash
# Extract EXPECTED and the pinned tag from anchored assignment lines only:
grep -m1 -o 'IREF=[^ ]*' ...   # anchor: ^[[:space:]]*IREF=
# Then — count only after the write succeeds, so an error can never read as 0:
git show <tag>:apps/web-platform/infra/inngest-bootstrap.sh > /tmp/ib-probe.sh &&
  grep -c "^probe_schema=$EXPECTED$" /tmp/ib-probe.sh
```

- `^…$` bounds restrict the count to the assignment line; comments can no longer inflate it.
- The `git show > file && grep` chain separates "could not extract/fetch" (error) from "schema absent" (a real `0`).
- The sibling recipe in `scripts/cutover-inngest.sh` got the same anchor — the fix closed the class, not the instance.
- Regression pins 6d–6h in `tests/scripts/test-inngest-volume-recut-gate.sh` cover: anchored non-comment grep present, no unanchored count surviving (quoted forms included), sibling anchored, `IREF=` anchoring, and the extraction-guard chain. Anti-vacuity floor raised 53 → 58.

## Why This Works

1. **Root cause of the env leak:** `GIT_*` is an open set. Any finite `env -u` list is a snapshot that goes stale; prefix enumeration (`${!GIT_@}` in bash, `!key.startsWith("GIT_")` in TS) is the only durable shape — the same conclusion the lefthook learning reached for `gitCleanEnv()`.
2. **Root cause of the vacuous arm:** a guard read from the ambient environment is controlled by the caller — including the hostile environment under simulation. Only caller-explicit channels (argv) or harness-written state can distinguish "replayed" from "injected".
3. **Root cause of the misleading count:** an unanchored substring grep treats comments as data. And an unguarded `git show | grep -c` collapses extraction failure into `0` — the operator reads "schema absent, do not replace" when the real answer was "could not measure". The `> file && grep` shape makes fail-loud the default.

## Prevention

- Any test spawning `git` (or asserting on git-produced state) in a hook-reachable context must scrub `GIT_*` **by prefix**, in the suite preamble AND locally at the probe — defense in depth survives a partial revert.
- A self-replay/regression arm must gate on argv (or state the harness itself writes), never on an environment variable.
- Operator-facing count recipes: anchor to the assignment line (`^k=v$`), extract referents from anchored lines only, and chain the count behind the extraction's success so `0` always means `0`.
- A negative regression pin must not match its own prose quoting the forbidden form — constrain on executable shape (a required quote immediately before the token, an actual line-start anchor).

## Related Issues

- [#8051](https://github.com/jikig-ai/soleur/issues/8051), [#8053](https://github.com/jikig-ai/soleur/issues/8053) — the two closed defects; PR [#8154](https://github.com/jikig-ai/soleur/pull/8154)
- [#7976](https://github.com/jikig-ai/soleur/issues/7976) — the insufficient five-name `env -u` fix this supersedes
- [#7835](https://github.com/jikig-ai/soleur/issues/7835) — census tracking the same `GIT_*` sweep across TS fixtures (`gitCleanEnv()`); this PR is the shell-fixture analog
- See also: [Lefthook GIT_* env var leak breaks tests](../workflow-issues/2026-04-03-lefthook-git-env-var-leak-breaks-tests.md) — same mechanism in the TS harness; its 2026-09-04 erratum is why this entry files at `severity: high` (env leaks are data-loss-capable, not test nuisances)
- See also: [Every fix reintroduced the class it was fixing](../2026-09-04-every-fix-reintroduced-the-class-it-was-fixing.md) — the anchor-assertion class this PR's pins were written to satisfy
