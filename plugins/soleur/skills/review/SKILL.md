---
name: review
description: "This skill should be used when performing exhaustive code reviews using multi-agent analysis, ultra-thinking, and worktrees."
---

# Review Command

<command_purpose> Perform exhaustive code reviews using multi-agent analysis, ultra-thinking, and Git worktrees for deep local inspection. </command_purpose>

## Introduction

<role>Senior Code Review Architect with expertise in security, performance, architecture, and quality assurance</role>

## Prerequisites

<requirements>
- Git repository with GitHub CLI (`gh`) installed and authenticated
- Clean main/master branch
- Proper permissions to create worktrees and access the repository
- For document reviews: Path to a markdown file or document
</requirements>

## Main Tasks

### 0. Setup

**Load project conventions:**

```bash
# Load project conventions
if [[ -f "CLAUDE.md" ]]; then
  cat CLAUDE.md
fi
```

Read `CLAUDE.md` if it exists - apply project conventions during review.

### 1. Determine Review Target & Setup (ALWAYS FIRST)

<review_target> #$ARGUMENTS </review_target>

<thinking>
First, I need to determine the review target type and set up the code for analysis.
</thinking>

#### Immediate Actions:

<task_list>

- [ ] Determine review type: PR number (numeric), GitHub URL, file path (.md), or empty (current branch)
- [ ] Check current git branch
- [ ] If ALREADY on the target branch (PR branch, requested branch name, or the branch already checked out for review) → proceed with analysis on current branch
- [ ] If DIFFERENT branch than the review target → offer to use worktree: "Use git-worktree skill for isolated Call `skill: git-worktree` with branch name
- [ ] Fetch PR metadata using `gh pr view --json` for title, body, files, linked issues
- [ ] Set up language-specific analysis tools
- [ ] Prepare security scanning environment
- [ ] Make sure we are on the branch we are reviewing. Use gh pr checkout to switch to the branch or manually checkout the branch.

Ensure that the code is ready for analysis (either in worktree or on current branch). ONLY then proceed to the next step.

</task_list>

#### Change Classification Gate

Before spawning review agents, classify the PR to avoid spawning agents whose expertise is irrelevant to the change.

1. Run `git diff --name-only origin/main...HEAD | head -n 200` to get the list of changed files.
2. Check for override: scan `$ARGUMENTS` for "deep review" or "full review". Also run `gh pr view --json body,title --jq '.body + " " + .title'` and check for the same phrases. If override detected, skip classification and spawn all 8 agents.
3. Apply a single judgment on the file list: **Does this PR contain source code files?** Source code includes: `.ts`, `.js`, `.jsx`, `.tsx`, `.rb`, `.py`, `.go`, `.rs`, `.swift`, `.kt`, `.java`, `.c`, `.cpp`, `.cs`, `.php`, `.sh`, `.bash`, `.zsh` — any file that contains executable logic. Non-code includes: `.md`, `.txt`, `.yml`, `.yaml`, `.toml`, `.json`, `.css`, `.html`, `.njk`, `.svg`, `.png`, `.jpg`, `.gif`, `.pen`, `LICENSE`, `CHANGELOG*`, `.github/**` workflow files, and plugin/agent/skill definition files (`plugins/**/*.md`, `agents/**/*.md`).
4. Announce the classification result before spawning agents.

#### Parallel Agents to review the PR:

<parallel_tasks>

**If the PR contains source code files (or override detected), spawn all 8 agents:**

1. Task git-history-analyzer(PR content)
2. Task pattern-recognition-specialist(PR content)
3. Task architecture-strategist(PR content)
4. Task security-sentinel(PR content)
5. Task performance-oracle(PR content)
6. Task data-integrity-guardian(PR content)
7. Task agent-native-reviewer(PR content) - Verify new features are agent-accessible
8. Task code-quality-analyst(PR content) - Detect code smells and produce refactoring roadmap

**If the PR contains NO source code files (non-code only), spawn 4 agents:**

1. Task git-history-analyzer(PR content)
2. Task pattern-recognition-specialist(PR content)
3. Task security-sentinel(PR content) - Still needed: config/CI can expose secrets, markdown can contain code examples
4. Task code-quality-analyst(PR content) - Still needed: docs/config quality matters

Skipped for non-code PRs: architecture-strategist, performance-oracle, data-integrity-guardian, agent-native-reviewer. These agents analyze source code structure, runtime performance, database integrity, and agent accessibility — none are relevant to documentation, configuration, or CI changes.

Announce: "Change classified as **[code/non-code]**. Spawning [N]/8 review agents. [If non-code: Skipped: architecture-strategist, performance-oracle, data-integrity-guardian, agent-native-reviewer — not relevant to non-code changes. Use 'deep review' to force full pipeline.]"

</parallel_tasks>

**Note:** The conditional agents block below (agents 9-14: Rails reviewers, migration experts, test-design-reviewer, semgrep) is **unaffected** by the classification gate. Both gates run independently — the classification controls only the always-on agents above.

#### Conditional Agents (Run if applicable):

<conditional_agents>

These agents are run ONLY when the PR matches specific criteria. Check the PR files list and project structure to determine if they apply:

**If project is a Rails app (Gemfile AND config/routes.rb exist at repo root):**

9. Task kieran-rails-reviewer(PR content) - Rails conventions and quality bar
10. Task dhh-rails-reviewer(PR title) - Rails philosophy and anti-patterns

**When to run Rails review agents:**

- Repository root contains both `Gemfile` and `config/routes.rb`
- PR modifies Ruby files (*.rb)
- PR title/body mentions: Rails, Ruby, controller, model, migration, ActiveRecord

**What these agents check:**

- `kieran-rails-reviewer`: Strict Rails conventions, naming clarity, controller complexity, Turbo patterns
- `dhh-rails-reviewer`: Rails philosophy adherence, JavaScript framework contamination, unnecessary abstraction

**If PR contains database migrations (db/migrate/*.rb files) or data backfills:**

11. Task data-migration-expert(PR content) - Validates ID mappings match production, checks for swapped values, verifies rollback safety
12. Task deployment-verification-agent(PR content) - Creates Go/No-Go deployment checklist with SQL verification queries

**When to run migration agents:**

- PR includes files matching `db/migrate/*.rb`
- PR modifies columns that store IDs, enums, or mappings
- PR includes data backfill scripts or rake tasks
- PR changes how data is read/written (e.g., changing from FK to string column)
- PR title/body mentions: migration, backfill, data transformation, ID mapping

**What these agents check:**

- `data-migration-expert`: Verifies hard-coded mappings match production reality (prevents swapped IDs), checks for orphaned associations, validates dual-write patterns
- `deployment-verification-agent`: Produces executable pre/post-deploy checklists with SQL queries, rollback procedures, and monitoring plans

**If PR contains test files:**

13. Task test-design-reviewer(PR content) - Score test quality against Farley's 8 properties

**When to run test review agent:**

- PR includes files matching `*_test.rb`, `*_spec.rb`
- PR includes files matching `test_*.py`, `*_test.py`
- PR includes files matching `*.test.ts`, `*.test.js`, `*.spec.ts`, `*.spec.js`
- PR includes files matching `*_test.go`
- PR includes files matching `*_test.swift`, `*Tests.swift`
- PR includes files in `__tests__/` or `spec/` or `test/` directories

**What this agent checks:**

- `test-design-reviewer`: Scores tests against Farley's 8 properties, produces a weighted Test Quality Score with letter grade and top 3 improvement recommendations

**If PR modifies source code files, semgrep-sast is a mandatory gate:**

14. Task semgrep-sast(PR content) - Deterministic SAST scanning for known vulnerability patterns

**When to run SAST agent:**

- PR modifies source code files (*.py,*.js, *.ts,*.rb, *.go,*.java, *.rs,*.swift, *.kt, etc.)
- Not needed for documentation-only or config-only changes

**Bootstrap (mandatory before spawning the agent):** Run [ensure-semgrep.sh](./scripts/ensure-semgrep.sh) from the repo root. The script checks PATH first, then auto-installs via brew → pipx → `pip --user` in that order. Exits 0 when semgrep is reachable. Exit 1 means an install was attempted and failed; exit 2 means no install path was available (no brew, pipx, or python3 with pip). On non-zero exit, print the script's stderr to the user and abort the review. Do NOT silently skip — the deterministic SAST pass is what catches CodeQL-equivalent patterns like `js/file-system-race` before push.

**Custom rules file:** [semgrep-custom-rules.yaml](./references/semgrep-custom-rules.yaml) ships alongside the public rule packs and covers CodeQL queries the public packs miss (e.g. the TOCTOU patterns that blocked PR #2463 in CI). The semgrep-sast agent loads it via `--config=plugins/soleur/skills/review/references/semgrep-custom-rules.yaml`. Extend it whenever a CodeQL finding in CI was not caught locally — the goal is no-surprises on CI.

**What this agent checks:**

- `semgrep-sast`: Known vulnerability signatures (CWE patterns), hardcoded secrets, insecure function calls, taint analysis. Complements security-sentinel's LLM-based architectural review with deterministic rule-based scanning.

</conditional_agents>

### 2. Rate Limit Fallback

<decision_gate>

After all parallel and conditional agents complete, check their outputs:

- **If ALL agents returned empty output or rate-limit errors** (e.g., "out of extra usage", "rate limit exceeded", zero findings across every agent): perform an inline review in the main context covering all four core dimensions — security, architecture, performance, and simplicity. This is expected fallback behavior during high-usage periods, not an error condition.
- **If ANY agent returned substantive output**: proceed normally with available results. No fallback needed — partial coverage from real agents is better than duplicating their work inline.

This is a binary gate: all-failed triggers the fallback; any-succeeded means continue.

</decision_gate>

### 4. Ultra-Thinking Deep Dive Phases

<ultrathink_instruction> For each phase below, spend maximum cognitive effort. Think step by step. Consider all angles. Question assumptions. And bring all reviews in a synthesis to the user.</ultrathink_instruction>

<deliverable>
Complete system context map with component interactions
</deliverable>

#### Phase 3: Stakeholder Perspective Analysis

<thinking_prompt> ULTRA-THINK: Put yourself in each stakeholder's shoes. What matters to them? What are their pain points? </thinking_prompt>

<stakeholder_perspectives>

1. **Developer Perspective** <questions>

   - How easy is this to understand and modify?
   - Are the APIs intuitive?
   - Is debugging straightforward?
   - Can I test this easily? </questions>

2. **Operations Perspective** <questions>

   - How do I deploy this safely?
   - What metrics and logs are available?
   - How do I troubleshoot issues?
   - What are the resource requirements? </questions>

3. **End User Perspective** <questions>

   - Is the feature intuitive?
   - Are error messages helpful?
   - Is performance acceptable?
   - Does it solve my problem? </questions>

4. **Security Team Perspective** <questions>

   - What's the attack surface?
   - Are there compliance requirements?
   - How is data protected?
   - What are the audit capabilities? </questions>

5. **Business Perspective** <questions>
   - What's the ROI?
   - Are there legal/compliance risks?
   - How does this affect time-to-market?
   - What's the total cost of ownership? </questions> </stakeholder_perspectives>

#### Phase 4: Scenario Exploration

<thinking_prompt> ULTRA-THINK: Explore edge cases and failure scenarios. What could go wrong? How does the system behave under stress? </thinking_prompt>

<scenario_checklist>

- [ ] **Happy Path**: Normal operation with valid inputs
- [ ] **Invalid Inputs**: Null, empty, malformed data
- [ ] **Boundary Conditions**: Min/max values, empty collections
- [ ] **Concurrent Access**: Race conditions, deadlocks
- [ ] **Scale Testing**: 10x, 100x, 1000x normal load
- [ ] **Network Issues**: Timeouts, partial failures
- [ ] **Resource Exhaustion**: Memory, disk, connections
- [ ] **Security Attacks**: Injection, overflow, DoS
- [ ] **Data Corruption**: Partial writes, inconsistency
- [ ] **Cascading Failures**: Downstream service issues </scenario_checklist>

### 6. Multi-Angle Review Perspectives

#### Technical Excellence Angle

- Code craftsmanship evaluation
- Engineering best practices
- Technical documentation quality
- Tooling and automation assessment

#### Business Value Angle

- Feature completeness validation
- Performance impact on users
- Cost-benefit analysis
- Time-to-market considerations

#### Risk Management Angle

- Security risk assessment
- Operational risk evaluation
- Compliance risk verification
- Technical debt accumulation

#### Team Dynamics Angle

- Code review etiquette
- Knowledge sharing effectiveness
- Collaboration patterns
- Mentoring opportunities

### 4. Simplification and Minimalism Review

Run the Task code-simplicity-reviewer() to see if we can simplify the code.

### 4.5. CLI-Verification Check (user-facing docs only)

When reviewing a PR that changes `*.njk`, `*.md`, `README`, or content under
`apps/**`, scan every fenced code block tagged `bash`, `sh`, `shell`, or
untagged-but-CLI-shaped. For each `<command> <subcommand>` pair:

1. If the tool is well-known (git, gh, npm, bun, curl, ollama, supabase,
   doppler, etc.), verify the subcommand exists. Cross-reference the tool's
   official docs via `WebFetch` or run `<tool> --help`. If unsure, flag as
   `cli-verification-unverified` and require an explicit annotation or
   citation before approving.
2. If the tool is project-local (`./scripts/*`,
   `plugins/soleur/skills/*/scripts/*`), verify the script exists at the
   path.
3. If the snippet names a model or registry tag (`<model>:<tag>`,
   `@<version>`), fetch the registry or cite the registry URL.

Flag any unverified CLI invocation as **P1 (docs-trust)** — NOT P3 polish. A
fabricated CLI command on a high-intent landing page breaks first-touch
trust (#1810/#2550).

### 5. Findings Synthesis and GitHub Issue Creation

<critical_requirement>
Each finding's default action is to FIX IT INLINE on the PR branch: make the edit,
commit with a message `review: <summary> (P<N>)`, and push. Apply to P1, P2, P3
equally.

Filing a GitHub issue instead of fixing is allowed ONLY when the finding meets
one of these four scope-out criteria:

  1. **cross-cutting-refactor** — fix requires touching **≥3 files** that are
     **materially unrelated to this PR's core change**, where **core change =
     files named in the PR's linked issue, OR files in the same top-level
     directory (e.g., `apps/web-platform/`, `plugins/soleur/`) as the primary
     changed file**. Bare multi-file fixes do NOT qualify; the unrelatedness
     must be concrete and defensible — count specific files or drop the
     scope-out.
  2. **contested-design** — multiple valid fix approaches AND the review
     **agent** (not the PR author) independently names ≥2 concrete approaches
     that trade off differently on durability, cost, or complexity AND
     recommends a design cycle outside this PR. Author-initiated
     contested-design claims ("I don't feel like implementing approach X
     here") do NOT qualify; the agent must independently surface the tradeoff.
  3. **architectural-pivot** — fix would change a pattern used across the
     codebase and deserves its own planning cycle.
  4. **pre-existing-unrelated** — finding existed on `main` before this PR and
     is not exacerbated by the PR's changes. (Does NOT block merge.) **Only
     reachable through the `pre-existing` branch of the provenance triage in
     Step 1 below — never applies to `pr-introduced` findings.**

When filing:

- The issue body MUST contain a `## Scope-Out Justification` section naming the
  specific criterion and a 1-3 sentence rationale.
- The issue MUST be created with `--label deferred-scope-out` and `--milestone`
  (per guardrails:require-milestone).
- The issue title MUST use a review-origin prefix (`review:`, `Code review #`,
  `Refactor:`, `arch:`, `compound:`, `follow-through:`).
- Use `gh issue create --body-file <path>` — never `--body "$VAR"` — so
  untrusted finding text (diffs, agent output) cannot shell-interpolate.

Everything else (magic numbers, duplicated helpers, small refactors, missing
tests for PR-introduced code, polish, naming, a11y on PR-introduced surfaces,
performance issues introduced by the PR) MUST be fixed inline.

**Second-reviewer confirmation gate:** Before creating a scope-out issue under
any criterion, invoke `code-simplicity-reviewer` via Task. The prompt MUST
include:

1. The finding (location, description).
2. The proposed fix.
3. The exact four scope-out criteria definitions from this section
   (cross-cutting-refactor ≥3 unrelated files, contested-design with
   independent agent-named tradeoffs, architectural-pivot, pre-existing-
   unrelated). Do not rely on the agent's prior knowledge of the criteria —
   pass the definitions literally.
4. The criterion being claimed and a 1-3-sentence rationale.
5. This instruction: "Default to rejecting the scope-out filing. Only co-sign
   when the claimed criterion is concretely and obviously correct against the
   four definitions above. Reply with a single line as the first line of your
   output: `CONCUR` (to co-sign the filing) or `DISSENT: <one-sentence
   reason>` (to flip to fix-inline). Everything after the first line is
   advisory context."

If the first line of the agent's reply begins with `DISSENT`, the disposition
flips to fix-inline — do not file the issue. If the first line is `CONCUR`,
proceed with filing. Any other first-line content is treated as `DISSENT`
(fail-safe toward fix-inline).

**Rationale:** One agent's "scope-out is fine here" can be wrong in the same
way a single test can miss a bug. Requiring a second, simplicity-biased agent
to co-sign blocks the most common regression pattern: an agent-author pair
rationalizing a filing that a fresh pair of eyes would reject. See
`knowledge-base/project/learnings/2026-04-15-multi-agent-review-catches-bugs-tests-miss.md`.

Filing without scope-out justification will be caught by /ship Phase 5.5 Review-
Findings Exit Gate and BLOCK merge. See rule rf-review-finding-default-fix-inline.
</critical_requirement>

#### Step 1: Synthesize All Findings

<thinking>
Consolidate all agent reports into a categorized list of findings.
Remove duplicates, prioritize by severity and impact.
</thinking>

<synthesis_tasks>

- [ ] Collect findings from all parallel agents
- [ ] Categorize by type: security, performance, architecture, quality, etc.
- [ ] Assign severity levels: CRITICAL (P1), IMPORTANT (P2), NICE-TO-HAVE (P3)
- [ ] Remove duplicate or overlapping findings
- [ ] Estimate effort for each finding (Small/Medium/Large)
- [ ] Tag each finding with **provenance**: `pr-introduced` or `pre-existing`.
      A finding is **pr-introduced** if the code the finding critiques was added
      or modified by this PR's diff (verify with `git log -L :<function>:<file>
      origin/main..HEAD` or `git diff origin/main...HEAD -- <file>`). A finding
      is **pre-existing** if the code existed on `main` before this PR and the
      PR neither changed nor moved it. Provenance-ambiguous findings (e.g., a
      helper the PR refactored but didn't introduce) default to
      **pr-introduced** — the PR touched it, the PR owns the fix.

**Disposition by provenance:**

- **pr-introduced:** MUST be fixed inline. No scope-out allowed regardless of
  criterion — the PR introduced the concern, the PR resolves it. If a fix is
  genuinely too large, reduce the PR (split or revert the offending commit)
  rather than filing a scope-out.
- **pre-existing:** Triage into exactly one of three buckets:
    1. **Fix inline** — small, load-bearing, cheap to include. Default for
       sub-20-line fixes on files the PR already touches.
    2. **File as scope-out** — legitimately needs its own cycle. MUST carry
       the `pre-existing-unrelated` criterion AND a re-evaluation deadline
       (a target phase milestone such as `Phase 4`, or a concrete trigger
       condition such as "revisit when syncWorkspace lands in #2244").
       Open-ended scope-outs with no deadline are NOT permitted — they become
       the backlog this rule exists to drain.
    3. **Close as wontfix** — polish-only, low-value noise, or concern already
       covered by existing code. Close immediately (do not file) with a
       1-sentence rationale in the summary report.

The `pr-introduced → fix inline` rule is the mechanical version of rule
`rf-review-finding-default-fix-inline`: it removes the judgment loophole ("is
this really cross-cutting?") for findings the PR itself introduced.

</synthesis_tasks>

**Coupling note:** Ship Phase 1.5, Phase 5.5, and pre-merge hook pre-merge:review-evidence-gate detect review evidence by searching for GitHub issues with the `code-review` label whose body contains `PR #<number>`. If the issue body template or label changes, update detection logic in `ship/SKILL.md` and `.claude/hooks/pre-merge-rebase.sh`. Phase 5.5 Review-Findings Exit Gate (new in #2374) additionally detects open review-origin issues cross-referencing the PR by body regex `(Ref|Closes|Fixes) #<N>\b` without `deferred-scope-out` label; filing without scope-out justification will block merge.

#### Step 2: Create GitHub Issues

<critical_instruction> Fix inline or, where a scope-out criterion applies, create a `deferred-scope-out` issue. Do NOT present findings for per-item user approval. </critical_instruction>

**Read `plugins/soleur/skills/review/references/review-todo-structure.md` now** for the complete GitHub issue creation flow: label prerequisite, issue body template, `--body-file` pattern, label/milestone selection, duplicate detection, error handling, and batch strategy.

#### Step 3: Summary Report

After creating all GitHub issues, present comprehensive summary:

````markdown
## Code Review Complete

**Review Target:** PR #XXXX - [PR Title] **Branch:** [branch-name]

### Findings Summary

- **Total Findings:** [X]
- **P1 CRITICAL:** [count] - BLOCKS MERGE
- **P2 IMPORTANT:** [count] - Should Fix
- **P3 NICE-TO-HAVE:** [count] - Enhancements
- **By provenance:** [pr-introduced count] pr-introduced, [pre-existing count] pre-existing
- **Pre-existing disposition:** [fix-inline count] fixed, [scope-out count] scoped-out, [wontfix count] wontfix

### Fixed Inline

**P1 - Critical (BLOCKS MERGE):**

- {description} — commit {sha}
- {description} — commit {sha}

**P2 - Important:**

- {description} — commit {sha}

**P3 - Nice-to-Have:**

- {description} — commit {sha}

### Filed as Deferred Scope-Out

**Scope-out criterion required per finding (cross-cutting-refactor | contested-design | architectural-pivot | pre-existing-unrelated):**

- #NNN - review: {description} — criterion: {name} — rationale: {1-3 sentences}
- #NNN - review: {description} — criterion: {name} — rationale: {1-3 sentences}

**Failed (if any):**

- {description} - Error: {error message}

### Review Agents Used

- security-sentinel
- performance-oracle
- architecture-strategist
- agent-native-reviewer
- [other agents]

### Next Steps

1. **Verify inline fixes landed**: Each finding above should have a commit on the PR branch.

   ```bash
   git log --oneline origin/main..HEAD | grep '^[a-f0-9]* review:'
   ```

2. **Inspect any scope-out issues**: Review findings filed as `deferred-scope-out` with justification.

   ```bash
   gh issue list --label deferred-scope-out --search "Ref #<PR_NUMBER>"
   ```

3. **Phase 5.5 gate self-check**: `/ship` will run the Review-Findings Exit Gate and block merge on any open review-origin issue cross-referencing the PR without the `deferred-scope-out` label. If the gate blocks, either fix inline and close the issue, or add the `deferred-scope-out` label + `## Scope-Out Justification`.
````

### Severity Breakdown:

**P1 (Critical - Blocks Merge):**

- Security vulnerabilities
- Data corruption risks
- Breaking changes
- Critical architectural issues

**P2 (Important - Should Fix):**

- Performance issues
- Significant architectural concerns
- Major code quality problems
- Reliability issues

**P3 (Nice-to-Have):**

- Minor improvements
- Code cleanup
- Optimization opportunities
- Documentation updates

### 6. Exit Gate

**Pipeline detection:** If the conversation contains `skill: soleur:work` output earlier (indicating review was invoked by work's Phase 4 chain) or `soleur:one-shot` output (indicating review was invoked by one-shot step 4), skip the exit gate. The calling pipeline handles compound, commit, and lifecycle progression. When review is invoked by work or one-shot, do not duplicate these steps.

**If invoked directly by the user** (no work or one-shot orchestrator in the conversation):

1. Run `skill: soleur:compound` to capture learnings from the review session.
   If compound finds nothing to capture, it will skip gracefully — do not block on this.
2. Commit any local artifacts. GitHub issues are already created remotely,
   but local files may have been modified (plan updates, todo resolutions).
   Run `git status --short`. If there are changes:

   ```bash
   git add <changed files>
   git commit -m "docs: review artifacts for feat-<name>"
   git push
   ```

   If there are no local changes, skip the commit (this is the expected case — review's
   primary output is GitHub issues, which are remote-only). If push fails (no network),
   warn and continue.
3. Display: "Review complete. All findings are tracked as GitHub issues.
   Run `/clear` then `/soleur:work` or `/soleur:ship` for maximum context headroom."

### 7. End-to-End Testing (Optional)

**Read `plugins/soleur/skills/review/references/review-e2e-testing.md` now** for project type detection, testing offers (Web/iOS/Hybrid), and subagent procedures for browser and Xcode testing.

### Defect Classes This Review Reliably Catches

Multi-agent parallel review has been shown to catch bugs in shipped, green-CI code across these classes (each a real P1 caught on PR #2347):

- **Shared mutable state across co-mounted instances** — module-level `let` bindings captured by a once-built object that multiple components import. Pattern-recognition and code-quality agents spot the closure capture in seconds; unit tests rarely co-mount instances.
- **Validator scope on sibling message fields** — new top-level fields added to a schema whose existing validator covers only one field. Security-sentinel asks "what if the client sends X?" for every permutation without waiting for the test author to imagine it.
- **DB partial-index predicate drift** — the application's query filter (`.is("archived_at", null)`) no longer matches the index's `WHERE` clause. Data-integrity-guardian reads both files and compares WHERE clauses symbolically; the bug stays silent until a user archives a row.

See `knowledge-base/project/learnings/2026-04-15-multi-agent-review-catches-bugs-tests-miss.md` for the full pattern catalogue.

### Sharp Edges: Review Agent Limitations

Review agent suggestions that modify workflow `if` conditions or event filters must be smoke tested against the full user journey (not just the reduced trigger case) before shipping -- agents optimize locally and can break flows they don't fully model.

When a reviewer prescribes `--arg` for jq injection defense in a `gh ... --jq` context, verify the CLI forwards jq flags before implementing. `gh --jq` accepts a single expression string and does NOT forward `--arg`, `--argjson`, or `--slurp` to the underlying jq binary — applying the fix produces `unknown arguments` at runtime. Fall back to shape-validating the shell variable (e.g., `[[ "$VAR" =~ ^[0-9]+$ ]]`) before interpolation, or pipe to a second-stage standalone `jq --arg`. See `knowledge-base/project/learnings/2026-04-15-gh-jq-does-not-forward-arg-to-jq.md`.

Parallel review batches can stall silently — spawning 12 review agents at once has been observed to produce completion notifications for only 6, with the remaining agents' transcripts frozen ~15s after spawn and no completion event emitted. When more than 30% of spawned agents stop producing output for >2 minutes after launch, proactively announce "N of M agents stalled" rather than silently waiting. Proceed with synthesis from the agents that returned — the Rate Limit Fallback gate already permits partial coverage. See `knowledge-base/project/learnings/2026-04-17-postgrest-aggregate-disabled-forces-rpc-option.md`.

Before reporting a broken link or missing file, reviewer agents MUST verify via Glob or Read. Unverified "broken link" claims waste reviewer-response cycles — the file may exist at the exact path. **Why:** PR #2226 pattern-recognition-specialist false-positive on a `runtime-errors/2026-02-13-...` learning file that did exist.

### Important: P1 Findings Block Merge

Any **P1 (CRITICAL)** findings must be addressed before merging the PR. Present these prominently and ensure they're resolved before accepting the PR.
