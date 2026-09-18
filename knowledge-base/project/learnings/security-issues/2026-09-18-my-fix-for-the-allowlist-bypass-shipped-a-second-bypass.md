---
module: System
date: 2026-09-18
problem_type: security_issue
component: tooling
symptoms:
  - "cron-compound-promote filters proposal diff paths on lines starting with '+++ b/'"
  - "git apply strips one leading path component by default, so '+++ x/…' and '+++ w/…' write files the filter never saw"
  - "the proposed --numstat fix reports only the rename DESTINATION, so a rename of AGENTS.rules.md into an allowlisted path passes the allowlist and deletes the protected file"
root_cause: missing_validation
resolution_type: workflow_improvement
severity: high
tags: [allowlist, git-apply, guard-design, diff-shapes, plan-review, security]
issue: '#8274'
synced_to: [plan]
---

# Learning: my fix for the allowlist bypass shipped a second bypass

## Problem

`cron-compound-promote` applies an LLM-authored unified diff after checking it against
`TARGET_ALLOW_RE` (two permitted paths: `AGENTS.rules.md` and
`plugins/soleur/skills/<name>/SKILL.md`). #8274 reported the check as vacuous:

```ts
const diffPaths = cluster.proposed_diff_unified
  .split("\n")
  .filter((l) => l.startsWith("+++ b/"))
  .map((l) => l.replace("+++ b/", ""));
const badPath = diffPaths.find((p) => !TARGET_ALLOW_RE.test(p));
```

`git apply` with no `-p` strips **one** leading component, not specifically `b/`. Measured in a
throwaway repo: a patch headed `+++ x/target.txt` rewrote `target.txt`, and `+++ w/evil.yml`
created `evil.yml`. Neither line starts with `+++ b/`, so `diffPaths` is empty, `badPath` is
`undefined`, and the allowlist passes.

## The mistake

I planned the obvious fix: derive the paths from git itself via `git apply --numstat -z`, then
check every path git reports. That is the right *direction* and the wrong *mechanism*.

Kieran's plan-review challenged it, and the measurement settles it:

```
$ cat rename.patch
rename from AGENTS.rules.md
rename to plugins/soleur/skills/x/STOLEN.md

$ git apply --numstat -z rename.patch
0  0  plugins/soleur/skills/x/STOLEN.md      # ← destination ONLY

$ git apply --summary rename.patch
 rename AGENTS.rules.md => plugins/soleur/skills/x/STOLEN.md (100%)

$ git apply rename.patch && ls AGENTS.rules.md
ls: cannot access 'AGENTS.rules.md': No such file or directory
```

The derived path set is `["plugins/soleur/skills/x/STOLEN.md"]` — **fully allowlisted** — while the
apply **deletes the hard-rule corpus**. My fix would have closed the reported shape and left a
strictly worse one open, inside the PR whose stated purpose was closing the bypass.

## Key insight

**A guard that derives its protected set from a tool's own reporting is only as complete as the set
of input SHAPES that tool reports fully. Enumerate every shape the tool accepts — create, delete,
rename, copy, mode change — not just the shape the bug report happened to show.**

A fix verified only against the reported shape reproduces the defect class one shape over, and it
does so with *more* credibility than the original bug, because "we derive from git itself" sounds
like it closed the whole class. The tell is that `--numstat` answers "how many lines changed where",
which is a **statistics** question; the guard is asking an **authority** question ("what will this
write or destroy"). Those have different answers for renames, and only the second one is the
property.

## Solution

Derive from `git apply --summary` **plus** `--numstat -z`, and allowlist rename/copy **source**
paths as well as destinations. Refuse when the derived set is empty (a header-less diff currently
passes vacuously). The guard's mutation matrix gains a rename row and a copy row, each measured
rather than imagined, plus a must-PASS control so the guard cannot satisfy itself by refusing
everything.

## Prevention

- When writing a guard over a tool's output, list the tool's input shapes first and put one
  mutation-matrix row per shape. If a shape has no row, the guard has no claim about it.
- Prefer the tool's **authority** output (what it will do) over its **statistics** output (what
  changed, and by how much). `--summary` describes the operation; `--numstat` describes the deltas.
- A security fix's test battery must include the shape the *fix* introduces, not only the shape the
  *report* described.

## Session Errors

- **Two subagent claims would have shipped defects had they not been re-derived.** One reported
  `git apply` "defaults to -p0" (it strips one component — measured, and the whole fix depends on
  it). Another called adding the new marker to `MARKER_RE` "non-optional"; `MARKER_RE`
  (`git-lock-marker-telemetry.ts`) gates *plugin/CLI stdout* markers, a different surface from a
  server-side container emit. — **Prevention:** a constraint carries a **scope**, and the scope is
  the part that gets dropped in restatement. Before adopting a cited constraint, read the file that
  defines it and confirm the surface matches.
- **I grepped a consumer and nearly concluded a capability was absent.** `grep 'compound'
  manual-trigger-allowlist.ts` returns nothing, so the cron looked un-triggerable. The allowlist is
  **derived** (`EXPECTED_CRON_FUNCTIONS.map(manualTriggerEventFor)`), and the cron is in that
  manifest — it has been manually triggerable all along. That single fact collapsed a planned
  week-long soak into a minutes-long probe. — **Prevention:** grep the **authority** (the file that
  defines the set), not a file that consumes it; a derived list never contains its own members.
- **I wrote a false mitigation into the plan's risk table.** "PII pre-pass covers pattern content" —
  `PII_REGEX` runs inside `collect-corpus` and filters the proposer's **prompt input**, never any
  write path. I also cited `.gitleaks.toml:333` as the `private-key` allowlist; that is a different
  rule, and **two** rules carry the learnings path. — **Prevention:** a mitigation naming a
  mechanism must cite the line where that mechanism runs, and confirm it runs on the side of the
  data flow the risk is about.
- **The guard-contract lint silently scored my mutation matrices as 0 rows.** It counts markdown
  **table** rows in the span after `**Mutation matrix**`; numbered lists count for nothing, and the
  failure reads as "you wrote no matrix" rather than "wrong format." — **Prevention:** read
  `scripts/lint-guard-contract.py`'s `TABLE_ROW_RE` before authoring a Guard Contract.
- **The issue-filing gate cannot read `/tmp`,** and it also refuses a body file created in the
  *same* command as the `gh issue create` call. — **Prevention:** write the body to a
  repo-relative path in its own step, then file.
- **The gitleaks pre-commit hook failed** (`mise ERROR No version is set for shim: gitleaks`) and
  blocked the commit. Resolved with `mise use -g gitleaks@8.24.2` (already installed) rather than
  bypassing a secret-scanning hook. — **Prevention:** a missing tool shim is an environment fix,
  never a reason to reach for `--no-verify`.

## Related

- `knowledge-base/project/learnings/2026-09-18-the-loop-was-not-failing-it-was-succeeding-at-nothing-and-said-ok.md`
- `knowledge-base/project/plans/2026-09-18-feat-wikiskill-pattern-wiki-phase-1-plan.md` (Guard 2)
- #8274 (closed by that plan), #8281 (parent), #8293 (deferred pattern layer)
