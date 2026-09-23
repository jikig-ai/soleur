# Every guard I wrote defended a worktree the render never needed

**Issue:** Ref #8542 · **Branch:** `feat-regenerable-manifest` · **Date:** 2026-09-23

## Problem

`resolve-regenerable-conflicts.sh` completes an unattended merge whose only conflict is the
generated `model.likec4.json`, by regenerating it. The first design started the merge, removed
the conflicted artifact, then ran the renderer **inside the worktree**, in the middle of the merge.

The 11-seat review panel's findings reduced to one root cause: every state the worktree can hold
during a render is one the resolver has to defend. Findings included:

- **Data loss.** The artifact was removed before the render. An interrupt, or a trap that
  resumed execution, left it deleted. With two members, the second one's file went too.
- **Execution of repo content.** likec4 walks the whole diagrams directory. It loads
  `likec4.config.{js,mjs,ts}` as code, reads `.likec4rc`, and follows symlinks out of the repo.
- **The worktree changing mid-render.** An edit, a staged file, or HEAD moving during a
  minutes-long `npx` render would be folded into the merge commit.
- **The unwind itself.** A stray unwind path and a check nicknamed "P5" existed only to
  undo work the render had half-done.

Each finding got a guard, and each guard was a new surface for the next round of review.

## Solution

The CTO re-ruled: render from git objects before touching the worktree.

1. Run `git merge-tree --write-tree -z --name-only BASE HEAD`, parsed NUL-framed. Accept only
   `CONFLICT (contents)` on regenerable paths.
2. Copy the source files through an allowlist, not a blocklist. Only tracked mode-100644/100755
   `*.c4|*.likec4|*.like-c4` blobs are copied from the **merged tree** with
   `git cat-file blob`, into a private 0700 staging dir under
   `${XDG_CACHE_HOME:-~/.cache}/soleur`. A symlink, gitlink, likec4 config, or `..` path is
   **refused**, not skipped: rendering without it would not be the repo's model.
3. Render in the background with `wait`, so a signal is handled immediately.
4. Only then touch the worktree:
   - re-check HEAD, re-check the tree is clean under `-uall`, and check that no added path
     would overwrite an existing file;
   - run `git merge --no-ff --no-commit`, copy the rendered bytes, `git add`;
   - check that the staged blob equals the rendered bytes and that the index equals the merged
     tree plus the regenerated paths;
   - commit, then assert the result: the commit's tree matches the pre-commit write-tree,
     `HEAD^1` is HEAD and `HEAD^2` is BASE. Otherwise `reset --keep` and refuse.

The data-loss, config-execution and npx vectors are now closed **by construction**. The P5
check, the stray unwind and the remove-before-render all went away. The mutation battery made
every remaining guard fail its tests when removed, except three documented equivalent mutants.

Late in the session, the fixture-scan ratchet (P1b) flagged the resolver's staging writes as
"not provably absolute". It was right. A **relative `XDG_CACHE_HOME`**, which the XDG spec says
is invalid, would have put the staging directory relative to the resolver's working directory,
which is the root of the repo being merged. The resolver now ignores a relative value and
asserts the staging parent and the artifact write are absolute. A row goes red without the fix.

## Key Insight

**When a helper must act on a live, operator-owned working tree, first ask whether the work
can happen somewhere the operator does not own.** Git already stores the merged content as
objects (`merge-tree --write-tree`, `cat-file blob`). Rendering from those objects in private
staging needs only a handful of invariants at the point where the result is written back.
Rendering in place needs one guard per worktree state. The guard count was the signal: once a
design's review findings are mostly "what if the tree is in state X during step Y", the fix is
to remove step Y from the tree, not to add guard X.

Second insight: **a ratchet written for test fixtures found a production bug.** Treat a
fixture-scan hit in a production script as a finding to investigate before quieting it. Here
the "appeasement" guard was the fix.

## Session Errors

1. **Lefthook bun-test battery queued ~20 min on the first commit.** Recovery: killed my own
   lefthook tree and re-committed with `LEFTHOOK_EXCLUDE=bun-test`.
   **Prevention:** already sanctioned; check for surviving hook processes before retrying
   (work SKILL two-writers rule).
2. **Committed while the fixture-relative-assert ratchet was red.** The commands were chained
   with `;`, which hid its status. Recovery: follow-up commit.
   **Prevention:** chain gate commands with `&&` or record `RC=$?` right after each one
   (work SKILL "wrapper that reports a gate").
3. **Three mutants survived: `CLAUDE_PLUGIN_ROOT` was preferred over the sibling.** Recovery:
   added a sibling-order row.
   **Prevention:** a resolution order needs a row where both candidates exist and differ.
4. **The old suite's row 3 flaked, rc=1 with no output, ~4 in 150 runs under load.** Not
   reproduced; that design was replaced.
   **Prevention:** none needed. The rewrite removed the in-tree render window.
5. **The INT/TERM trap resumed execution.** With two members, it deleted a file.
   Recovery: `exit` in the handler; later superseded by the rewrite.
   **Prevention:** a signal trap must terminate; drive SIGTERM mid-operation in a row.
6. **Write tool refused on stale file state.** Recovery: read the file first.
   **Prevention:** hr-always-read-a-file-before-editing-it.
7. **`ROOT_SRC` was lost because `plugin_root` ran as `x=$(fn)`.** Recovery: the function sets
   globals.
   **Prevention:** existing work SKILL bullet ("`x=$(fn)` silently loses every effect except
   stdout").
8. **The gitlink fixture was dropped by `git add -A`.** Recovery: `mkdir sub` plus
   `update-index --cacheinfo`.
   **Prevention:** assert the fixture's tree entry exists before the row reads it.
9. **A `git stash list` probe was blocked by a hook, which blocked the whole call.**
   Recovery: re-ran without it.
   **Prevention:** keep probes that hooks forbid out of compound calls.
10. **The issue-filing gate blocked #8623.** Two checks tripped: the named-surface
    User-Impact regex, and ≤100 lines counting as fix-inline. Recovery:
    `Mandated-By: wg-when-an-audit-identifies-pre-existing`.
    **Prevention:** a defect in another subsystem is filed with `Mandated-By` from the start.
11. **The hook's `grep` under `set -eo pipefail` aborted the deny path.** Recovery:
    `|| REGEN_WHY=""`.
    **Prevention:** in an errexit hook, every capture that may legitimately match nothing gets
    an `||` default.
12. **The initial push was rejected after a plan-commit rebase.** Recovery:
    `--force-with-lease=<branch>:<sha>`.
    **Prevention:** always lease against the observed remote SHA.
13. **Local test-all shards were refused (rc=4, sibling runs).** Recovery: CI plus targeted
    ratchets.
    **Prevention:** #8322 (affected suites plus ratchets as the local default).
14. **Review agents hit the session limit.** Recovery: resumed on request.
    **Prevention:** none; environmental.
15. **The git-objects rewrite was committed without the repo-global ratchets.** Measured
    after the fact:
    - the fixture-relative-assert baseline rose (resolver `.sh` 0→5, its test 11→16);
    - P1a rose 9→12;
    - the trap lint flagged T3b.

    Recovery: guarded the sites. The production guard exposed the relative-`XDG_CACHE_HOME`
    defect.
    **Prevention:** the work SKILL rule "a file-selected suite set cannot see a repo-global
    ratchet" already covers this, and #8322 would make it mechanical. Evidence was added there.
16. **`pgrep -f` was blocked because it matches its own command line.** Recovery: skipped the
    probe.
    **Prevention:** hook-enforced; use `proc.sh` `list_runs`.
17. **A mutation `sed` used `|` as its delimiter against a `||` pattern, so it did not apply.**
    Caught because the grep showed the line unchanged; re-driven with Python and confirmed red.
    **Prevention:** existing review SKILL bullet ("assert the mutation LANDED").
18. **Design error: rendering inside the worktree mid-merge.** Recovery: the CTO re-ruling above.
    **Prevention:** the Key Insight above, routed to the architecture skill's regeneration
    guidance.
19. **Latent defect: a relative `XDG_CACHE_HOME` placed staging relative to the repo.**
    Recovery: ignored per the XDG spec and asserted absolute, with a row that goes red without
    the fix.
    **Prevention:** see the second Key Insight.

20. **CI failed `fixture-env-adoption` (unconverted suites 24, ceiling 23).** The new
    `render-c4-model.test.sh` writes fixture repos with `git` without the shared fixture env.
    The ratchet selection in #15 did not include this gate, because the gate references no
    changed file. Recovery: `git_fixture_env "$SANDBOX"` in the suite.
    **Prevention:** before pushing, a new `plugins/soleur/test/*.sh` that runs `git` must source
    `lib/git-fixture-env.sh`. Add `fixture-env-adoption.test.sh` to the repo-global ratchet set
    alongside fixture-relative-assert, P1a and the trap lint (evidence added to #8322).

21. **CI failed the commit-hook rows, which passed locally.** `scripts/test-all.sh` sets
    `core.hooksPath` through inherited `GIT_CONFIG_*` for the whole run, and environment config
    outranks a fixture repo's own `.git/hooks`. So under CI the hooks never ran: the
    hook-rewrite rows exited 0, and the signal-during-commit row passed without testing
    anything. Recovery: the suite takes `git_fixture_env` (its prefix sweep drops the setting),
    plus a control row asserting that a fixture pre-commit hook actually runs. Reproduced red
    locally by exporting the same `GIT_CONFIG_*` values.
    **Prevention:** any suite whose rows depend on a fixture's hooks must take the fixture env
    and carry a "hooks run" control row. A standalone local run does not reproduce the CI
    environment, so test locally under the `GIT_CONFIG_*` values `test-all.sh` exports.
22. **The poll's BEHIND auto-sync merged and pushed while I had an uncommitted edit.** The
    merge did not touch the edited file, so nothing was lost. Recovery: stopped the Monitor,
    verified there was no MERGE_HEAD and only the intended diff, re-ran the suites, committed.
    **Prevention:** stop the Phase 7 poll before editing the PR worktree, and re-arm it after
    the push. The poll is a second writer on the same index.

## Related

- ADR-235 (amendment 2026-09-23): the git-objects design and its residuals.
- ADR-179 (amendment A17): the plugin-root anchor for this payload.
- #8623: the web-platform `c4-render.ts` loads a tenant likec4 config. Same vector, different
  trust boundary.
- `2026-09-19-a-generated-artifact-in-my-diff-made-every-landing-on-main-a-conflict.md`

## Tags

category: design-patterns
module: plugins/soleur/scripts/resolve-regenerable-conflicts.sh
