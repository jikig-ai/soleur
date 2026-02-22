---
module: soleur
date: 2026-02-22
problem_type: developer_experience
component: skill-design
tags: [merge-pr, skill-design, git, conflict-resolution, version-bump, compound, overengineering]
severity: medium
---

# merge-pr Skill Design Lessons

Six distinct failure modes surfaced while designing and implementing the `/soleur:merge-pr`
skill. Each is documented with root cause, prevention strategy, and generalizable lesson.

---

## Issue 1: Wrong git command for CHANGELOG conflict resolution

### What happened

The initial plan specified `git show HEAD:<path>` to read CHANGELOG.md during a merge
conflict. This is incorrect. During an active merge conflict, `HEAD` is ours (pre-merge)
and does not include the incoming changes. Reading only `HEAD:` discards the other side.

### Root cause

Confusion between "what HEAD points to during a normal commit" vs. "what the index stages
hold during an active merge conflict." The index stages carry all three versions:

- Stage 1 (`:1:`): the merge base (common ancestor)
- Stage 2 (`:2:`): ours (HEAD)
- Stage 3 (`:3:`): theirs (incoming)

### Prevention

When writing instructions that involve reading file content during merge conflicts, always
specify the stage number explicitly:

```bash
git show :2:CHANGELOG.md   # ours
git show :3:CHANGELOG.md   # theirs
```

Add this note to any skill or plan that handles merge conflicts in version files or
structured documents. `git show HEAD:` is only correct outside of a conflict state.

### Test scenario

Given: A branch has `CHANGELOG.md` changes AND origin/main has `CHANGELOG.md` changes.
When: The branch runs `git merge origin/main` and a conflict occurs.
Then: `git show :2:CHANGELOG.md` and `git show :3:CHANGELOG.md` must both be used to
reconstruct the full file; `git show HEAD:CHANGELOG.md` only returns one side.

---

## Issue 2: Skill invoking another skill is an architecture violation

### What happened

The initial plan had `/ship` hand off to `/merge-pr` as a final step. This was flagged
during review as a constitution violation: skills are user-invoked entry points with no
inter-skill API.

### Root cause

Treating skills like functions. Skills look like functions (they have names, take
arguments) but the plugin loader has no mechanism for one skill to invoke another. There
is no runtime dispatch table.

### Prevention

When a skill needs behavior from another skill:

1. **Redirect the user** -- tell them to run the other skill directly.
2. **Duplicate inline** -- copy the essential logic if it is small.
3. **Extract to a shared script** -- move common behavior to a script both skills call.
4. **Route through an agent** -- agents CAN spawn other agents via Task tool; if
   orchestration is required, the right unit is an agent, not a skill.

When designing multi-step workflows, draw the invocation hierarchy before writing the
plan. If an arrow points from one skill to another, it is wrong.

See also: `knowledge-base/learnings/implementation-patterns/2026-02-18-skill-cannot-invoke-skill.md`

### Test scenario

Given: A skill plan shows "Skill A delegates to Skill B for step X."
Then: This is a design error. Rewrite so A informs the user to invoke B, or extract
the shared behavior to a script.

---

## Issue 3: Version bump ran unconditionally -- skipped when no plugin files changed

### What happened

The initial plan always ran the version bump gate, even when no files under
`plugins/soleur/` were modified. This produces spurious version bumps that increment the
version without any actual plugin change, polluting the version history.

### Root cause

The version bump check was placed at a fixed point in the workflow without a conditional.
The rule "bump if and only if plugin files changed" was in AGENTS.md but not reflected in
the skill plan's control flow.

### Prevention

In any skill or plan that includes a version bump step, wrap it with an explicit file-scope
guard:

```
If any file under plugins/soleur/ was modified → MINOR/PATCH/MAJOR bump.
If no files under plugins/soleur/ were modified → skip version bump entirely.
```

The gate reads: "Did I touch plugin files? Yes: bump. No: skip." This is binary with no
middle ground.

### Test scenario

Given: A workflow run that only modifies files under `knowledge-base/`.
When: The version bump gate is evaluated.
Then: No version bump occurs; `plugin.json`, `CHANGELOG.md`, `README.md` are unchanged.

Given: A workflow run that modifies files under `plugins/soleur/skills/`.
When: The version bump gate is evaluated.
Then: A version bump occurs across all three files.

---

## Issue 4: Compound placed after CI creates an infinite loop

### What happened

An early design had compound run after CI checks passed. This created a logical loop:
compound writes a commit -> CI triggers on that commit -> compound must run again before
that CI merge -> and so on. Compound was never a valid post-CI step.

### Root cause

Compound was treated as a "cleanup" action that could run at any point. It cannot,
because compound produces a commit. Any commit after CI has passed invalidates the CI
result and forces a re-run.

### Prevention

Compound is always a pre-condition of the commit, never a post-condition. The sequence
is fixed:

```
review -> compound -> commit -> push -> CI -> merge
```

Compound cannot appear after "push" in any workflow design. If a skill plan shows
compound after CI, reorder it before the commit step.

The constitution rule is: "Run code review and `/soleur:compound` before committing --
the commit is the gate."

### Test scenario

Given: A skill workflow with phases: implement, CI-wait, compound, commit.
Then: This ordering is wrong. Compound must move before commit (and before CI-wait).

---

## Issue 5: Plan review reduced complexity by 45% -- single-file-first rule

### What happened

Three parallel reviewers evaluated the merge-pr plan and independently identified
overengineering. The original plan included multiple scripts, sub-agents, and supporting
files. Reviewers converged on a single-SKILL.md-file implementation with no scripts, no
agents, and no sub-skills. This is the fourth confirmed case of plan review reducing scope
by 30-50%.

### Root cause

Without external review, scope naturally expands. The author is solving the problem as
they understand it in full generality. Reviewers apply the "v1 rule": what is the
minimum that works today?

### Prevention

Default starting point for any new skill: a single `SKILL.md` file. No scripts, no
agents, no sub-skills on the first pass. Only add supporting files when there is a
concrete reason (e.g., a bash script that is too long to inline, a reference table that
would bloat the skill description).

Before ANY plan with:
- New directories
- External scripts
- Sub-agents
- Multi-phase orchestration

Run `/soleur:plan_review` first. This step consistently reduces scope 30-90% and is now
confirmed across at least four features (fuzzy deduplication, runtime agent discovery,
brand marketing tools, merge-pr).

See also: `knowledge-base/learnings/2026-02-06-parallel-plan-review-catches-overengineering.md`

### Test scenario

Given: A new skill plan that includes `scripts/`, `agents/`, and a new sub-directory.
When: `/soleur:plan_review` is run on the plan.
Then: Reviewers should converge on whether each supporting file is justified. If all
three reviewers agree a file is unnecessary, remove it before implementing.

---

## Issue 6: Conflict markers committed to version-controlled files

### What happened

Root `README.md` had a `>>>>>>> origin/main` conflict marker that was committed and pushed.
This means a merge conflict was resolved by accepting the file as-is (with markers) rather
than resolving the conflict content.

### Root cause

Conflict markers look like regular text in a diff. A hasty `git add` after a conflict
accepts whatever is in the working tree, including unresolved markers. No pre-commit check
blocked it.

### Prevention

Add a pre-commit hook (or CI check) that rejects files containing git conflict markers:

```bash
# lefthook pre-commit
git diff --cached --name-only | xargs grep -lE '^(<<<<<<<|=======|>>>>>>>)' && \
  echo "ERROR: conflict markers in staged files" && exit 1 || true
```

Before any commit that follows a merge, grep staged files for conflict markers:

```bash
git diff --cached | grep -E '^(\+(<{7}|={7}|>{7}))' && echo "CONFLICT MARKERS PRESENT"
```

The `/review` and `/ship` skills should include a conflict-marker check as an explicit
validation gate before staging files.

### Test scenario

Given: A file in the working tree contains `>>>>>>> origin/main`.
When: The pre-commit hook runs.
Then: The commit is blocked with a clear error message identifying the file.

Given: The same file is staged with `git add`.
When: A CI lint check runs.
Then: The check fails and the PR cannot merge.

---

## Generalizable Best Practices

These patterns apply beyond the merge-pr skill to all skill and plan authoring:

**1. Git stage numbers are required for conflict-time reads.**
Never use `git show HEAD:` during a merge conflict. Always specify `:2:` (ours) or
`:3:` (theirs).

**2. Draw the invocation graph before writing the plan.**
If any edge points from one skill to another skill, the design is invalid before a line
of SKILL.md is written.

**3. Version bump gates are conditional, not unconditional.**
The check is "did plugin files change?" If no, skip entirely. Build the condition into
every plan that includes a version bump step.

**4. Compound is a pre-commit gate, not a post-CI step.**
The ordering `review -> compound -> commit` is immutable. No workflow design should place
compound after `git push`.

**5. Start with one file, add supporting files when justified.**
A skill is a single SKILL.md until complexity demands extraction. Plan review catches
premature file proliferation before implementation begins.

**6. Conflict markers are invisible to `git diff` scanning.**
Add a pre-commit hook that greps staged content for `<<<<<<<`, `=======`, `>>>>>>>`.
This is mechanical and should never require human review to catch.
