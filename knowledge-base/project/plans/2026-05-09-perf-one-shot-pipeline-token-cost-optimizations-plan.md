---
title: One-Shot Pipeline Token-Cost Optimizations (work + preflight + review)
type: refactor
date: 2026-05-09
branch: feat-one-shot-pipeline-token-cost-optimizations
classification: security-hygiene-class-refactor
requires_cpo_signoff: false
---

# One-Shot Pipeline Token-Cost Optimizations

Three minimal-surface, behavior-preserving edits to `work/`, `preflight/`, and
`review/` skill definitions that reduce token cost on the dependency-bump and
orphan-cleanup PR class without changing PASS/FAIL outcomes for any case where
the existing checks apply. Modeled directly on PR #3488 (merged 2026-05-09 as
8403414): a Dependabot dual-lockfile bump that exercised every skill in the
one-shot pipeline at full cost despite touching only `bun.lock`,
`package-lock.json`, and a small set of orphan deletions.

## User-Brand Impact

- **If this lands broken, the user experiences:** a one-shot pipeline that
  silently SKIPs a check that should have FAILed (e.g., a real CSP regression
  in a touched `.tsx` file slips past Check 2 because the new fast-path SKIP
  predicate is wrong), and a regression ships to prod without operator
  awareness.
- **If this leaks, the user's [data / workflow / money] is exposed via:** N/A —
  the change is to skill definition files (`plugins/soleur/skills/**/SKILL.md`,
  one new reference file). Skill definitions are authoring instructions
  consumed by Claude Code; they are not deployed to user-facing surfaces, do
  not handle credentials, and do not cross the sensitive-path regex defined in
  `plugins/soleur/skills/preflight/SKILL.md` Check 6 Step 6.1.
- **Brand-survival threshold:** `none` — the touched paths
  (`plugins/soleur/skills/{work,preflight,review}/SKILL.md` and a new
  `plugins/soleur/skills/work/references/work-lockfile-bumps.md`) do not match
  the canonical sensitive-path regex; no scope-out reason is required by the
  preflight Check 6 contract, but the indirect risk above (incorrect
  fast-path SKIP) is mitigated by the "no semantic change" acceptance
  criterion and the test-suite invariants.

## Overview

Three independent edits, one PR, one commit per change is acceptable:

| # | File | Edit | Goal |
|---|------|------|------|
| 1 | `plugins/soleur/skills/work/references/work-lockfile-bumps.md` (new) + `plugins/soleur/skills/work/SKILL.md` | Adapt 2026-05-09 lockfile learning into a reference; add a one-line bullet to Phase 2 step 4 ("Follow Existing Patterns") gated on diffs touching `bun.lock`. | First-attempt path for transitive bun bumps avoids the three-failed-attempts rediscovery cost paid in PR #3488. |
| 2 | `plugins/soleur/skills/preflight/SKILL.md` | Add Phase 0 diff classifier that runs `git diff --name-only origin/main...HEAD` ONCE and stores the result; rewrite each check's first step to re-use the cached path-set instead of re-running diff. Add explicit "fast-path SKIP" criteria per check. | For PR #3488-class diffs (lockfile + orphan deletions), 8 of 10 checks are guaranteed-SKIP given the diff signature. Net: 10 → 2 checks executed (Lockfile Consistency + Node-Only Encodings). |
| 3 | `plugins/soleur/skills/review/SKILL.md` | Extend the Change Classification Gate with two sub-classes: `deletion-dominated` (≥80% deletions across files AND lines) and `lockfile-only` (changed files match a lockfile glob plus optional knowledge-base/spec edits, zero source files). On match, spawn only `git-history-analyzer` + `security-sentinel`. | Skip `pattern-recognition-specialist` + `code-quality-analyst` for diffs whose information density does not justify them. |

Net effect on a PR #3488-class run of `/soleur:one-shot`: preflight runs ≈2/10
checks instead of 10/10; review runs 2 agents instead of 4 (or 8 — see
"Override-deep-review" below); work cites the surgical-edit reference instead
of triggering three failed `bun update` attempts mid-task. No behavior change
on any case where the check or agent applies.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (from ARGUMENTS) | Reality (from repo read) | Plan response |
|---|---|---|
| `preflight/SKILL.md` has 10 checks. | Read of `preflight/SKILL.md` shows checks numbered 1, 2, 3, 4, 5, 6, 7, 8, 9 (nine), plus the Not-Bare-Repo assertion (one). Total runnable units = 10 if Not-Bare-Repo counts. | Treat "10 checks" as nine numbered checks plus the Not-Bare-Repo assertion. Phase 0 classifier feeds path-set into all nine numbered checks; Not-Bare-Repo runs unconditionally. |
| `review/SKILL.md` has a "Change Classification Gate" extending "code vs non-code". | Confirmed at lines 63–100 of `review/SKILL.md`. The gate has a single binary judgment (source-code present or not) and an "override" via `deep review`/`full review`. | Extend with two sub-classes (`deletion-dominated`, `lockfile-only`); preserve override-deep-review precedence. Update the "Announce" line to enumerate four classes with the agent set per class. |
| `work/SKILL.md` Phase 2 step 4 is "Follow Existing Patterns". | Confirmed at lines 321–339 of `work/SKILL.md`. The step already contains ~15 grep/sweep precedent bullets. | Add ONE bullet, scoped to `bun.lock` diffs, linking to `work-lockfile-bumps.md`. Match the existing bullet style (`- **When [trigger], [action]. [Why]:** [pointer].`). |
| Source learning at `knowledge-base/project/learnings/2026-05-09-bun-lockfile-transitive-bump-requires-surgical-edit.md`. | Confirmed exists; ~80 lines including session-error narrative. | Adapt: keep surgical pattern + ban list + `bun install --frozen-lockfile` validation; drop session-error narrative; cap at 80 lines per acceptance criterion. |
| `bun test plugins/soleur/test/components.test.ts` baseline. | Verified locally on this branch: `1013 pass / 0 fail`. Skill-description CI gate (`SKILL_DESCRIPTION_WORD_BUDGET = 1800` tokenized as `desc.split(/\s+/).filter(Boolean).length`) is independent of body edits — this plan does not touch any `description:` frontmatter, so the gate is not at risk. | Acceptance criterion #5 verifies `bun test` still returns `1013 pass / 0 fail` after edits. |
| Acceptance criteria says "10 checks → 2 (lockfile + node-encodings)". | Lockfile = Check 3. Node-Only Encodings = Check 9. Both currently run unconditionally OR with non-path-pattern gates. Check 9 has `"Always runs (no path-pattern gate)"`; Check 3 path-gates on lockfile diff. | Phase 0 classifier emits a `lockfile-bump+orphan-deletion` shape that fast-path-SKIPs Checks 1, 2, 4, 5, 6, 7, 8, plus Not-Bare-Repo (always runs — count this as "executed" in the 2/10 figure if needed). Check 3 fires (lockfile in diff). Check 9 fires (always runs). Confirms the spec figure as "checks doing real work = 2". |

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` returned zero open
issues whose body references `plugins/soleur/skills/work/SKILL.md`,
`plugins/soleur/skills/preflight/SKILL.md`, or
`plugins/soleur/skills/review/SKILL.md`.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1.** `plugins/soleur/skills/work/references/work-lockfile-bumps.md`
  exists, is `≤80 lines`, and contains:
  - The surgical-edit pattern (`grep -n` to locate, replace version + integrity
    sha, validate with `bun install --frozen-lockfile`).
  - The ban list with explicit rejection of `bun update <pkg>` (elevates
    transitive to direct dep) AND bare `bun update` (bumps every direct
    caret-ranged dep).
  - A pointer line referencing the source learning at
    `knowledge-base/project/learnings/2026-05-09-bun-lockfile-transitive-bump-requires-surgical-edit.md`
    and PR #3488.
  - No "Session Errors" narrative (dropped per ARGUMENTS).
- [ ] **AC2.** `plugins/soleur/skills/work/SKILL.md` Phase 2 step 4 ("Follow
  Existing Patterns") contains exactly ONE new bullet linking to
  `references/work-lockfile-bumps.md`. The bullet is gated on `bun.lock` in the
  diff (e.g., "When the diff touches `bun.lock` AND the bump is intended to be
  transitive-only, …"). No other Phase 2 step 4 bullets are reordered or
  removed.
- [ ] **AC3.** `plugins/soleur/skills/preflight/SKILL.md` Phase 0 contains:
  - The existing branch-safety check (unchanged).
  - A new step that runs `git diff --name-only origin/main...HEAD` once and
    stores the result as a path-set variable (e.g., `DIFF_FILES`).
  - The path-set is referenced by Checks 1, 2, 3, 5, 6, 7, 8, 9 as their first
    step (Check 4 always runs and remains unchanged on its first step).
  - Each check's existing path-gate logic is preserved verbatim — the change
    is `git diff --name-only origin/main...HEAD` → `printf '%s\n' "$DIFF_FILES"`
    (or equivalent re-use form) at the call site.
  - Each check has an explicit "fast-path SKIP" criterion in prose (e.g.,
    Check 2: "If `DIFF_FILES` contains zero files matching `\.(tsx|css)$`,
    `middleware\.ts$`, `Dockerfile`, `\.tf$`, or `\.github/workflows/`, return
    SKIP without fetching production headers.").
- [ ] **AC4.** `plugins/soleur/skills/review/SKILL.md` Change Classification
  Gate enumerates four classes with an explicit agent set per class:
  1. **code (full)** — source-code files present → 8 agents (existing
     behavior).
  2. **non-code** — no source files, not `deletion-dominated` or
     `lockfile-only` → 4 agents (existing behavior).
  3. **deletion-dominated** — ≥80% of changed files are deletions AND ≥80% of
     diff lines are deletions → 2 agents (`git-history-analyzer` +
     `security-sentinel`).
  4. **lockfile-only** — every changed file matches the lockfile glob
     (`*/package-lock.json`, `*/bun.lock`, `*/yarn.lock`, `*/Cargo.lock`,
     `*/go.sum`, `*/Gemfile.lock`, `*/poetry.lock`, `*/uv.lock`) plus
     optional `knowledge-base/**` or `spec*.md` edits, with zero source
     files → 2 agents (`git-history-analyzer` + `security-sentinel`).
  Override (`deep review` / `full review` in `$ARGUMENTS` or PR body/title)
  still wins and spawns all 8 agents regardless of sub-class. Announce line
  uses the exact format `"Change classified as **<class>**. Spawning N/8 review
  agents. <skipped agents list, if any>"`.
- [ ] **AC5.** `bun test plugins/soleur/test/components.test.ts` returns
  `1013 pass / 0 fail` (unchanged from baseline). The skill-description word
  budget is not affected because no `description:` frontmatter is edited.
- [ ] **AC6.** `bash scripts/test-all.sh` passes from the worktree
  (`.worktrees/feat-one-shot-pipeline-token-cost-optimizations/`) per the bare
  repo guard in `scripts/test-all.sh`.
- [ ] **AC7.** No edits to `AGENTS.md`, `knowledge-base/project/constitution.md`,
  or any agent definition file (`agents/**/*.md`). Verify with
  `git diff --name-only origin/main...HEAD | grep -E '^(AGENTS\.md$|knowledge-base/project/constitution\.md$|agents/)'`
  returns empty.
- [ ] **AC8.** Behavior-preservation verification (manual but cheap):
  re-read each check's path-gate regex before and after the edit; confirm the
  set of paths matched is unchanged. The substitution is purely "replace
  `git diff` invocation with reference to cached `$DIFF_FILES`" — the predicate
  string itself is identical.

### Post-merge (operator)

- [ ] **AC9.** Run `/soleur:one-shot` against a future Dependabot or
  orphan-cleanup PR; confirm the plan's claimed savings (preflight 10 → 2
  checks, review 4 → 2 agents) materialize. If the savings are off by ≥1
  check or agent, the classifier predicates need a follow-up. (No tracking
  issue required pre-merge — the validation is empirical and a follow-up is
  cheap to file if needed.)

## Files to Create

- `plugins/soleur/skills/work/references/work-lockfile-bumps.md` (new, ≤80
  lines).

## Files to Edit

- `plugins/soleur/skills/work/SKILL.md` — Phase 2 step 4 only, one new bullet.
- `plugins/soleur/skills/preflight/SKILL.md` — Phase 0 (new classifier step),
  Check 1 Step 1.1, Check 2 Step 2.1, Check 3 Step 3.1, Check 5 path-gate,
  Check 6 Step 6.1, Check 7 path-gate, Check 8 Steps 8.1+8.2, Check 9 Step
  9.1. Each call-site swap is a 1–3 line edit; no semantic change.
- `plugins/soleur/skills/review/SKILL.md` — Change Classification Gate
  (lines 63–100), classification result announcement.

## Implementation Phases

### Phase 1 — Change 1: work reference + Phase 2 step 4 bullet

1. Create `plugins/soleur/skills/work/references/work-lockfile-bumps.md`
   adapted from the source learning. Keep:
   - Two-sentence problem framing (transitive bump in dual-lockfile dir; bun
     has no clean lockfile-only mode).
   - Surgical pattern (numbered list: locate entry via `grep -n`, replace
     version + sha, validate with `bun install --frozen-lockfile`).
   - Ban list as a fenced bash block: `# DO NOT: bun update <pkg>` (adds to
     package.json), `# DO NOT: bun update` bare (bumps 13+ direct caret deps).
   - Pointer line at end: "Source learning: 2026-05-09-bun-lockfile-…
     | Precedent: PR #3488".
   Drop:
   - Session-error narrative (4 numbered errors at the end of the source).
   - Discussion of the `cq-before-pushing-package-json-changes` rule
     interaction (mentioned in acceptance verification only, not authoring
     guidance).
   Verify length: `wc -l plugins/soleur/skills/work/references/work-lockfile-bumps.md`
   returns `≤80`.

2. Edit `plugins/soleur/skills/work/SKILL.md` Phase 2 step 4 ("Follow Existing
   Patterns"). Add ONE bullet, alphabetically/topically-adjacent to existing
   "Before writing a new format, date, or util helper" or "Before writing
   data-layer tests" bullets, in the form:

   > - **When the diff touches `bun.lock` AND the bump is intended to be
   >   transitive-only (e.g., a Dependabot security bump), use the
   >   surgical-lockfile-edit pattern in
   >   [`references/work-lockfile-bumps.md`](./references/work-lockfile-bumps.md)
   >   as the first attempt — never `bun update <pkg>` (elevates the target to
   >   a direct dep) or bare `bun update` (bumps every direct caret-ranged
   >   dep). Validate with `bun install --frozen-lockfile`. **Why:** PR #3488 —
   >   three failed bun invocations rediscovered the constraint at task time.

3. Verify the bullet is the only new content in step 4: `git diff
   plugins/soleur/skills/work/SKILL.md | grep '^+' | wc -l` ≤ 10 lines.

### Phase 2 — Change 2: preflight Phase 0 classifier + check fast-paths

1. Edit Phase 0 ("Context Detection"). After the branch-safety check and
   before "Phase 1: Run All Checks in Parallel", add:

   > **Step 0.1: Compute changed-file path-set (diff classifier).**
   >
   > Run once at the start of preflight; subsequent checks re-use the result
   > instead of re-running `git diff`. Skill convention forbids `$()` command
   > substitution — write the diff to a tmpfile so checks can `grep -E` the
   > predicate they care about.
   >
   > ```bash
   > git diff --name-only origin/main...HEAD > /tmp/preflight-diff-files.txt
   > ```
   >
   > If the command fails (e.g., offline, no remote), every path-gated check
   > falls back to its existing `git diff` form. Operators do not need to
   > handle this case — the absence of `/tmp/preflight-diff-files.txt` is the
   > signal.
   >
   > **Fast-path SKIP overview.** For diffs whose path-set matches one of the
   > recognized "guaranteed-SKIP" shapes, the relevant check returns SKIP at
   > Step <N>.1 without further work:
   >
   > | Check | Fast-path SKIP predicate (against `/tmp/preflight-diff-files.txt`) |
   > | --- | --- |
   > | 1 (Migrations) | Zero matches for `*/supabase/migrations/*\.sql`. |
   > | 2 (Sec headers) | Zero matches for `\.(tsx|css|html)$`, `middleware\.ts$`, `next\.config\.`, `\.tf$`, `Dockerfile`, `nginx`, `\.github/workflows/`. |
   > | 3 (Lockfiles) | Zero matches for `*/bun.lock`, `*/package-lock.json`, root `bun.lock`/`package-lock.json` — existing predicate, unchanged. |
   > | 5 (Bundle host) | Zero matches for the existing path-gate (Supabase client/validator paths, Dockerfile, reusable-release.yml, verify-required-secrets.sh) — existing predicate, unchanged. |
   > | 6 (Brand-survival) | Zero matches for the canonical sensitive-path regex — existing predicate, unchanged. |
   > | 7 (Canary) | `apps/web-platform/infra/ci-deploy.sh` not in path-set — existing predicate, unchanged. |
   > | 8 (SW cache bump) | No `fix(`/`fix:`/`hotfix` commit subject AND zero client-bundle surface matches — existing predicate, unchanged. |
   > | 9 (Node-only encodings) | Always runs (no fast-path SKIP). |
   > | 4 (Env isolation) | Always runs (no fast-path SKIP). |
   > | Not-Bare-Repo | Always runs. |
   >
   > For PR #3488-class diffs (lockfile bumps + orphan-cleanup deletions),
   > Checks 1, 2, 5, 6, 7, 8 fast-skip → Checks 3 (lockfile fires), 4 (env
   > isolation always), 9 (always), Not-Bare-Repo (always) execute. Of those
   > four, only Check 3 and Check 9 do "real work" against the diff; Check 4
   > and Not-Bare-Repo are constant-cost.

2. For each numbered Check that currently begins with `git diff --name-only
   origin/main...HEAD`, replace the call with `cat /tmp/preflight-diff-files.txt`
   (or `grep -E '<existing-pattern>' /tmp/preflight-diff-files.txt`). Preserve
   the existing path-pattern regex verbatim — the only diff is the diff source.

   Specifically:
   - Check 1 Step 1.1 — currently `git diff --name-only origin/main...HEAD --
     '*/supabase/migrations/*.sql'`. Replace with `grep -E
     '/supabase/migrations/[^/]+\.sql$' /tmp/preflight-diff-files.txt`.
   - Check 2 Step 2.1 — currently `git diff --name-only
     origin/main...HEAD`. Replace with `cat /tmp/preflight-diff-files.txt`
     (the subsequent grep against patterns is preserved).
   - Check 3 Step 3.1 — currently uses `git diff --name-status` (note:
     `--name-status`, not `--name-only`). **Do NOT swap this one** — the
     status letters (M/A/D) are load-bearing for Check 3's "added/deleted
     don't trigger sibling check" logic. Leave Check 3 unchanged.
   - Check 5 path-gate — currently `git diff --name-only
     origin/main...HEAD`. Replace with `cat /tmp/preflight-diff-files.txt`.
   - Check 6 Step 6.1 — currently `git diff --name-only origin/main...HEAD |
     grep -E "$SENSITIVE_PATH_RE"`. Replace with `grep -E
     "$SENSITIVE_PATH_RE" /tmp/preflight-diff-files.txt`.
   - Check 7 Step 7.1 — currently relies on path-gate text "only runs when
     `git diff --name-only origin/main...HEAD` contains
     `apps/web-platform/infra/ci-deploy.sh`". Update prose to reference the
     cached path-set; no executable change inside the steps themselves.
   - Check 8 Step 8.2 — currently `git diff --name-only
     origin/main...HEAD | grep -E '<surface>'`. Replace with `grep -E
     '<surface>' /tmp/preflight-diff-files.txt`.
   - Check 9 Step 9.1 — currently uses `git ls-files` (not `git diff`),
     because Check 9 scans the full client-bundle path universe, not the
     diff. Leave Check 9 unchanged.

3. Verify behavior preservation: for each modified Check, confirm the regex
   passed to `grep -E` is byte-equal to the regex previously consumed by `git
   diff` or the inline `grep`. The diff source is the only mutation.

### Phase 3 — Change 3: review classification sub-classes

1. In `plugins/soleur/skills/review/SKILL.md` "Change Classification Gate"
   (lines 63–100), expand step 3's binary judgment into four classes. Apply
   in this order (first-match wins; override always trumps):

   ```text
   Step 3 (revised):
     If $ARGUMENTS or PR body/title contains "deep review" / "full review":
       class = code-full-override (8 agents)
     Else if every changed file matches the lockfile glob OR
            (lockfile glob + optional knowledge-base/** or spec*.md edit)
            AND zero source-code extensions are present:
       class = lockfile-only (2 agents: git-history-analyzer + security-sentinel)
     Else if (deletions / total changed files) >= 0.80 AND
            (deleted lines / total diff lines) >= 0.80:
       class = deletion-dominated (2 agents: git-history-analyzer + security-sentinel)
     Else if any changed file has a source-code extension:
       class = code (8 agents) — existing behavior
     Else:
       class = non-code (4 agents) — existing behavior
   ```

2. Implement the metric computations as inline bash — the skill convention
   already has `head -n 200` and `git diff --name-only` patterns:

   ```bash
   git diff --name-only origin/main...HEAD > /tmp/review-changed.txt
   git diff --name-status origin/main...HEAD > /tmp/review-status.txt
   git diff --numstat origin/main...HEAD > /tmp/review-numstat.txt

   total_files=$(wc -l < /tmp/review-changed.txt)
   deleted_files=$(grep -cE '^D' /tmp/review-status.txt || true)
   added_lines=$(awk 'BEGIN{s=0} {if ($1 != "-") s += $1} END{print s}' /tmp/review-numstat.txt)
   deleted_lines=$(awk 'BEGIN{s=0} {if ($2 != "-") s += $2} END{print s}' /tmp/review-numstat.txt)
   total_lines=$((added_lines + deleted_lines))
   ```

   Then evaluate the predicates:

   ```bash
   LOCKFILE_RE='(^|/)(package-lock\.json|bun\.lock|yarn\.lock|Cargo\.lock|go\.sum|Gemfile\.lock|poetry\.lock|uv\.lock)$'
   ALLOWED_NONLOCK_RE='^(knowledge-base/|.*\.md$)'
   SOURCE_RE='\.(ts|tsx|js|jsx|rb|py|go|rs|swift|kt|java|c|cpp|cs|php|sh|bash|zsh|mjs|cjs)$'

   non_lock_files=$(grep -vE "$LOCKFILE_RE" /tmp/review-changed.txt || true)
   non_lock_non_doc=$(printf '%s\n' "$non_lock_files" | grep -vE "$ALLOWED_NONLOCK_RE" | grep -v '^$' || true)
   has_source=$(grep -E "$SOURCE_RE" /tmp/review-changed.txt | head -1 || true)
   ```

   - `lockfile-only` matches when `non_lock_non_doc` is empty AND `grep -E
     "$LOCKFILE_RE" /tmp/review-changed.txt` is non-empty AND `has_source` is
     empty.
   - `deletion-dominated` matches when `total_files > 0` AND `total_lines >
     0` AND `(deleted_files * 100 / total_files) >= 80` AND `(deleted_lines *
     100 / total_lines) >= 80`. (Use bash integer arithmetic — float not
     needed at 80% threshold.)

3. Update the spawn block. After the existing "If the PR contains source code
   files (or override detected), spawn all 8 agents:" section, insert two new
   sections (or merge into a single decision block). The cleanest form:

   ```markdown
   **If class is `lockfile-only` or `deletion-dominated` (and override not detected), spawn 2 agents:**

   1. Task git-history-analyzer(PR content)
   2. Task security-sentinel(PR content) — config/lockfile changes can introduce supply-chain or removal-related risk

   Skipped for lockfile-only / deletion-dominated PRs: pattern-recognition-specialist, code-quality-analyst, architecture-strategist, performance-oracle, data-integrity-guardian, agent-native-reviewer. Lockfile diffs and bulk deletions do not contain semantic patterns or quality regressions for the pattern/quality agents to find; architecture/perf/integrity/agent-native agents have no source code to analyze. Use `deep review` to force full pipeline.
   ```

4. Update the announce line to enumerate four classes:

   > "Change classified as **<class>**. Spawning N/8 review agents.
   > [If skipped agents: Skipped: <list> — not relevant to <class> changes.
   > Use 'deep review' to force full pipeline.]"

5. Conditional Agents block (`<conditional_agents>`) is unaffected — preserve
   the existing "The conditional agents block below … is **unaffected** by the
   classification gate." note. Confirm semgrep-sast still fires when source
   files are present (independent of the new sub-classes — `lockfile-only`
   and `deletion-dominated` typically have no source files, so semgrep-sast
   self-skips per its own gate at line 165).

### Phase 4 — Verification

1. From the worktree, run `bun test plugins/soleur/test/components.test.ts`.
   Expect `1013 pass / 0 fail`. If a description-budget test fails, no
   `description:` frontmatter was edited, so investigate as a regression
   (don't paper over).
2. From the worktree, run `bash scripts/test-all.sh`. Expect a passing run
   (the bare-repo guard inside the script will refuse to run from the bare
   root — operators MUST run from the worktree path).
3. Sanity-check the path-set caching in preflight: simulate a lockfile-only
   diff via `git diff --name-only origin/main...HEAD` and confirm Checks 1,
   2, 5, 6, 7, 8 fast-path SKIP.
4. Sanity-check the review classifier on a synthetic three-PR matrix
   (commit-author note: this is a manual spot check, not a test):
   - Lockfile-only PR (#3488 shape) → class=`lockfile-only`, 2 agents.
   - Pure-deletion PR (e.g., the `.plugin/` orphan deletion in #3488) →
     class=`deletion-dominated`, 2 agents.
   - Mixed lockfile + source PR → class=`code`, 8 agents.

## Test Scenarios

This is a workflow/skill-definition change, not a code change with runnable
behavior. The "tests" are the acceptance criteria invariants verified above
(`bun test`, `scripts/test-all.sh`, AC8 byte-equality of regex predicates) and
manual spot checks in Phase 4. No new RED-test infrastructure is required;
infrastructure-only changes are exempt from `cq-write-failing-tests-before`
per its own carve-out clause.

For Change 3 (review classifier), one cheap spot-check would be a small
shell-snippet that re-runs the classifier predicate against a fixture diff
output and asserts the chosen class. This is OPTIONAL — the AC8 byte-equality
check on path predicates is the load-bearing invariant; a fixture-driven
shell test is icing.

## Risks

1. **Fast-path SKIP predicate drift.** If the Check 2 fast-path SKIP regex
   diverges from Check 2's existing inner regex (the one that matches `.tsx`,
   `.css`, `middleware.ts`, etc. for "relevant" classification), a real CSP
   regression in a touched `.tsx` file could be skipped. Mitigation: AC8
   requires byte-equality of regexes before/after the edit. The Phase 2
   description above prescribes "preserve existing pattern verbatim — the
   only diff is the diff source".
2. **Cached path-set staleness within a single preflight run.** The
   classifier writes `/tmp/preflight-diff-files.txt` once at Phase 0; if
   anything between Phase 0 and a Check mutates the working tree (which would
   change the `origin/main...HEAD` diff), the cache is stale. Mitigation: no
   step between Phase 0 and Phase 1 mutates the tree; this is true today.
   Documented in Phase 0 prose.
3. **Review classifier false-positive on `lockfile-only`.** If a PR adds a
   knowledge-base markdown file alongside a lockfile bump, the
   `non_lock_non_doc` predicate must allow the markdown file. The plan's
   regex `ALLOWED_NONLOCK_RE='^(knowledge-base/|.*\.md$)'` includes
   markdown — verify on Phase 4 step 4 spot check.
4. **Review classifier false-negative on `deletion-dominated`.** A PR with a
   single small file deletion (1 file, 100% deleted) would score 100/100 on
   both predicates and class as `deletion-dominated`, dropping
   pattern-recognition. Mitigation: the spec (ARGUMENTS) explicitly
   prescribes 80%/80% as the threshold; for tiny PRs the savings are
   minimal anyway, and `git-history-analyzer` + `security-sentinel` are the
   most relevant agents for "what was this deleted thing?" review.
5. **Override-deep-review precedence regression.** The override check must
   fire before sub-class evaluation. Phase 3 step 1 prescribes this order
   explicitly. Verify by reading the final edit.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail
  `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `/work`.
  (Threshold here is `none`, valid; section is filled.)
- The path predicates for fast-path SKIP MUST be byte-equal to the existing
  inner predicates. Any "simplification" that drops an alternation member
  (e.g., dropping `nginx*` from Check 2's set because "no current diff
  matches nginx") is a silent fail-open. Re-read the existing pattern
  verbatim and copy it.
- The review classifier's `LOCKFILE_RE` must include every common lockfile
  shape from ARGUMENTS verbatim — adding a new lockfile shape later (e.g.,
  `flake.lock` for Nix) requires a follow-up edit. Not a current-PR concern,
  but worth a code comment in the gate.
- Check 3 (Lockfile Consistency) uses `git diff --name-status` (status
  letters) not `--name-only` — DO NOT swap Check 3 to use the cached
  `/tmp/preflight-diff-files.txt` (which contains only names). The plan
  preserves Check 3 verbatim for this reason; reviewer agents tempted to
  "unify" all checks against the same cache should reject that suggestion.
- Check 9 (Node-Only Encodings) uses `git ls-files` not `git diff` — it
  scans the full client-bundle path universe, not the diff. DO NOT swap it
  to use `/tmp/preflight-diff-files.txt` for the same reason.
- The `cat /tmp/preflight-diff-files.txt` substitution preserves the file
  ordering produced by `git diff --name-only` (which is alphabetic by
  pathspec). Subsequent `grep -E` predicates do not depend on order. If a
  future check adds an order-sensitive consumer (e.g., "first changed file"),
  the cache is still safe — `head -n 1` against the cache is identical to
  `head -n 1` against the live `git diff`.

## Domain Review

**Domains relevant:** Engineering only (CTO).

This is a token-cost optimization to skill-definition files. No product
surface (CPO), legal/privacy (CLO), marketing surface (CMO), finance (CFO),
sales (CRO), support (CCO), or operations (COO) implications. Per AGENTS.md
`hr-new-skills-agents-or-user-facing` rule (which mandates CPO+CMO for new
skills/agents/user-facing capabilities), this plan does not introduce a new
skill, agent, or user-facing capability — it modifies existing skill-internal
authoring instructions. CTO assessment: low blast-radius refactor; zero
semantic change to PASS/FAIL outcomes; mitigations in Risks section above
cover the silent-failure modes.

### Product/UX Gate

**Tier:** none — no user-facing surface touched. Skipped per Phase 2.5
contract for NONE-tier classification.

## Out of Scope

- Changing check semantics (e.g., raising/lowering thresholds, adding new
  banned tokens to Check 9, altering Check 5's eight-row decision matrix).
- Adding new review agents or skills.
- Editing `AGENTS.md`, `knowledge-base/project/constitution.md`, or any agent
  definition file under `agents/**/*.md`.
- A token-budget aggregator skill or rule-metrics work (separate effort,
  not blocked by or blocking this plan).
- Bun-version pinning for `bun install --frozen-lockfile` (the source
  learning notes the integrity sha is registry-driven; `bun install
  --frozen-lockfile` validates against the registry tarball, not against a
  bun-version pin).

## References

- Source learning:
  `knowledge-base/project/learnings/2026-05-09-bun-lockfile-transitive-bump-requires-surgical-edit.md`
- Precedent PR: #3488 (merged 2026-05-09 as 8403414) — Dependabot dual-
  lockfile bump that exercised the full one-shot pipeline at full cost.
- AGENTS.md `cq-before-pushing-package-json-changes` — dual-lockfile rule
  (note: triggers on `package.json` changes, not security-only transitive
  bumps; the new reference clarifies the gap for `bun.lock`).
- `plugins/soleur/skills/preflight/SKILL.md` Check 6 Step 6.1 — canonical
  sensitive-path regex (consulted to confirm this plan's paths do not match,
  hence `threshold: none` is valid without a scope-out reason).
- `plugins/soleur/skills/review/SKILL.md` lines 63–100 — existing Change
  Classification Gate.
- `plugins/soleur/skills/work/SKILL.md` Phase 2 step 4 (lines 321–339) —
  existing "Follow Existing Patterns" bullet style.
- `plugins/soleur/test/components.test.ts` — skill-description CI gate (1800
  word budget, tokenizer `desc.split(/\s+/).filter(Boolean).length`); not at
  risk for this plan.
- `scripts/test-all.sh` — bare-repo guard (must run from worktree).
