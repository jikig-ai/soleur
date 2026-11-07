# Learning: a nine-seat review and a 16-mutant battery both missed three gaps that one fresh verifier found

## Problem

PR #12246 lets a brief's `ci-is-the-gate` constraint reach `soleur:ship` Phase 4, so `battery-owed.sh` skips the local battery (exit 42). The arm that decides this reads a free-text file and must still refuse when the diff touches the infra surface. It went through a nine-seat review, a CTO ruling, a simplicity pass, a four-seat fix-round and a 16-mutation battery (all mutants killed after two pinning rows were added). A single read-only verifier, given only the fix-round diff and three questions, then reproduced three more gaps at HEAD:

- **Submodule hidden by `ignore = all`.** A gitlink committed under `apps/web-platform/infra/` vanished from `git diff --name-only` when `.gitmodules` set `ignore = all` in the same commit, so the arm returned SKIPPABLE for an infra change.
- **Symlinked directory read as a token.** The symlink check compared the resolved directory with the repo top level, so an in-repo symlinked spec directory was read although the header said it is not.
- **Corrupt `MERGE_HEAD` read as "no merge".** `git rev-parse -q --verify MERGE_HEAD` exits 1 for garbage content, the same as for an absent file.

## Solution

- Pass `--ignore-submodules=none` to the three `git diff` path sources.
- Compare the physical (`pwd -P`) and logical spec directory; equality means no component is a symlink.
- Also test `-e "$(git rev-parse --absolute-git-dir)/MERGE_HEAD"`.
- One row per gap, each killed by reverting its fix (suite 221/221).
- The invisible-HTML-block gap (`<style>`, `<pre>`) was documented as accepted in the script header: the file is pipeline-written and the infra refusal still stands.

## Key Insight

The mutation battery measures whether the rows pin the code that exists. It cannot see a property the code never had, and the review seats had graded the same code with the same mental model as its author. Each gap above is a place where git's own view differs from the view the gate assumed (a config knob that hides paths, a symlink the resolver follows, a state file whose validity is not its existence). Before relying on a path-enumerating gate, ask what each git plumbing call hides by configuration, and run one fresh verifier over the final diff with questions rather than conclusions.

## Session Errors

1. **Merge-in-progress fixture created no conflict** (`plugins/soleur` did not exist on main, so the printf failed). Recovery: `mkdir -p` in the fixture. **Prevention:** assert the fixture's precondition (`git status` shows the state) before the row that depends on it.
2. **First sandbox battery had a red control** (sandbox was not a git repo and lacked `scripts/test-all.sh`). Recovery: `git init` plus the missing files, control 154/0. **Prevention:** the existing mutation-battery discipline (green unmutated control first) caught it; no new rule.
3. **Battery script crashed with `IndexError`** when a mutant failed with no FAIL line. Recovery: fixed the indexing. **Prevention:** one-off.
4. **Another review seat overwrote my shared-scratchpad `mut2.py`**, so a restarted battery ran the wrong script. Recovery: killed it, relaunched as `lead-r2-battery.py`. **Prevention:** the lead-unique scratchpad file-name rule already exists; it held once applied.
5. **Hooks blocked `rm -rf` on `.git`-bearing sandboxes and `pgrep -f`.** Recovery: did not route around; two `/var/tmp` sandboxes were left in place for the operator. **Prevention:** hooks worked as designed.
6. **`one-shot/SKILL.md` exceeded main by 4 bytes** after a rewording. Recovery: trimmed the phrase. **Prevention:** measure `wc -c` against the ceiling after every SKILL.md edit (already the practice).
7. **`shellcheck` SC2154 x19** persisted after a local directive. Recovery: one file-wide disable. **Prevention:** one-off.
8. **`fixture-relative-assert` ratchet moved by 3 sites.** Recovery: rewrote three `mktemp`-root writes to `( cd "$R" && ... )`. **Prevention:** covered by the existing work rule on repo-global ratchets that a file-selected suite set cannot see.
9. **Mutation survivors** (w3 NULs, then the allow-list `;` and `unset GIT_*` mutants). Recovery: added pinning rows. **Prevention:** the survivor-then-pin loop is the discipline working.
10. **Verification pass found three gaps after review closed** (above). Recovery: fixed and pinned. **Prevention:** run the fresh-verifier pass over the final diff for any gate that reads attacker-adjacent text; ask about what each git call hides.
11. **Production deploys rolled back (`canary_inngest_link_failed`) because of a half-finished Inngest key rotation** (host keys changed in phase 1, `apply2` never updated the web copy), so the canary's 401 was correct. Recovery: the operator approved and re-dispatched `converge both`; #12243 closed. **Prevention:** the rotate workflow's in-flight-release guard only runs at the start of phase 2. Recorded in the #12243 closing comment; no new issue (one data point, net-issue-flow).

## Tags

category: workflow-issues
module: ship/battery-owed
