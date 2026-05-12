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

1. Run `git diff --name-only origin/main...HEAD | head -n 200` to get the list of changed files. Also capture status letters and line counts. Use `git rev-parse --git-dir` to resolve a writable tmp path that works in both regular checkouts and worktrees: in a worktree `.git` is a file (gitdir pointer), not a directory, so `> .git/review-*.txt` fails with `Not a directory (os error 20)`. The resolver returns the worktree's actual gitdir (e.g., `<bare>/worktrees/<name>/`):

   ```bash
   REVIEW_TMP="$(git rev-parse --git-dir)"
   git diff --name-only origin/main...HEAD > "$REVIEW_TMP/review-changed.txt"
   git diff --name-status origin/main...HEAD > "$REVIEW_TMP/review-status.txt"
   git diff --numstat origin/main...HEAD > "$REVIEW_TMP/review-numstat.txt"
   ```

   All downstream `cat .git/review-*.txt` references in the predicates below must use `"$REVIEW_TMP/review-*.txt"` instead. The pre-existing `.git/...` literals work in non-worktree checkouts but silently break in worktrees (where every PR review increasingly happens by default).

2. Check for override: scan `$ARGUMENTS` for "deep review" or "full review". Also run `gh pr view --json body,title --jq '.body + " " + .title'` and check for the same phrases. If override detected, skip classification and spawn all 8 agents.
3. Apply the four-class decision tree below in order; **first match wins** (override always trumps):

   ```text
   If $ARGUMENTS or PR body/title contains "deep review" / "full review":
     class = code (full override) → 8 agents
   Else if every changed file matches the lockfile glob OR
          (lockfile glob + optional knowledge-base/** or *.md edit)
          AND zero source-code extensions are present:
     class = lockfile-only → 2 agents (git-history-analyzer + security-sentinel)
   Else if total_files > 0 AND total_lines > 0 AND
          (deleted_files * 100 / total_files) >= 80 AND
          (deleted_lines * 100 / total_lines) >= 80 AND
          zero source-code extensions are present in the diff:
     class = deletion-dominated → 2 agents (git-history-analyzer + security-sentinel)
   Else if any changed file has a source-code extension:
     class = code → 8 agents
   Else:
     class = non-code → 4 agents
   ```

   The "zero source-code extensions" guard on `deletion-dominated` closes a piggyback class: a 1000-line cleanup PR that adds a 50-line `.ts` file would otherwise route to 2 agents and bypass pattern-recognition / code-quality / architecture / data-integrity / performance / agent-native review on the new source file. Mirroring `lockfile-only`'s `$has_source` empty requirement keeps the savings on legitimate orphan-cleanup PRs while routing any deletion-dominated PR with new source code through the full 8-agent path.

   Source-code extensions: `.ts`, `.tsx`, `.js`, `.jsx`, `.rb`, `.py`, `.go`, `.rs`, `.swift`, `.kt`, `.java`, `.c`, `.cpp`, `.cs`, `.php`, `.sh`, `.bash`, `.zsh`, `.mjs`, `.cjs` — any file containing executable logic. Non-code: `.md`, `.txt`, `.yml`, `.yaml`, `.toml`, `.json`, `.css`, `.html`, `.njk`, `.svg`, `.png`, `.jpg`, `.gif`, `.pen`, `LICENSE`, `CHANGELOG*`, `.github/**` workflow files, and plugin/agent/skill definition files (`plugins/**/*.md`, `agents/**/*.md`).

   Compute the predicates inline (`set -uo pipefail` — drop the `e` so legitimately-empty greps don't abort):

   ```bash
   total_files=$(wc -l < "$REVIEW_TMP/review-changed.txt")
   deleted_files=$(grep -cE '^D' "$REVIEW_TMP/review-status.txt" || true)
   added_lines=$(awk 'BEGIN{s=0} {if ($1 != "-") s += $1} END{print s}' "$REVIEW_TMP/review-numstat.txt")
   deleted_lines=$(awk 'BEGIN{s=0} {if ($2 != "-") s += $2} END{print s}' "$REVIEW_TMP/review-numstat.txt")
   total_lines=$((added_lines + deleted_lines))

   LOCKFILE_RE='(^|/)(package-lock\.json|bun\.lock|yarn\.lock|Cargo\.lock|go\.sum|Gemfile\.lock|poetry\.lock|uv\.lock)$'
   ALLOWED_NONLOCK_RE='^(knowledge-base/|.*\.md$)'
   SOURCE_RE='\.(ts|tsx|js|jsx|rb|py|go|rs|swift|kt|java|c|cpp|cs|php|sh|bash|zsh|mjs|cjs)$'

   non_lock_files=$(grep -vE "$LOCKFILE_RE" "$REVIEW_TMP/review-changed.txt" || true)
   non_lock_non_doc=$(printf '%s\n' "$non_lock_files" | grep -vE "$ALLOWED_NONLOCK_RE" | grep -v '^$' || true)
   has_source=$(grep -E "$SOURCE_RE" "$REVIEW_TMP/review-changed.txt" | head -1 || true)
   any_lockfile=$(grep -E "$LOCKFILE_RE" "$REVIEW_TMP/review-changed.txt" | head -1 || true)
   ```

   - `lockfile-only` matches when `$non_lock_non_doc` is empty AND `$any_lockfile` is non-empty AND `$has_source` is empty.
   - `deletion-dominated` matches when `total_files > 0` AND `total_lines > 0` AND `(deleted_files * 100 / total_files) >= 80` AND `(deleted_lines * 100 / total_lines) >= 80` AND `$has_source` is empty. Bash arithmetic evaluates left-to-right; multiply-first avoids the integer-truncation-to-zero trap. Note: `git diff --name-only` does not distinguish added/deleted paths, so `$has_source` may match a path that is itself a deletion — this is intentionally conservative (we want zero source-file activity in either direction) and prevents a piggyback attack where a backdoor `.ts` file rides along on a bulk-deletion cleanup PR.

4. Announce the classification result before spawning agents.

#### Parallel Agents to review the PR:

<parallel_tasks>

**If override is detected (`deep review` / `full review`), spawn all 8 agents regardless of class:**

1. Task git-history-analyzer(PR content)
2. Task pattern-recognition-specialist(PR content)
3. Task architecture-strategist(PR content)
4. Task security-sentinel(PR content)
5. Task performance-oracle(PR content)
6. Task data-integrity-guardian(PR content)
7. Task agent-native-reviewer(PR content) - Verify new features are agent-accessible
8. Task code-quality-analyst(PR content) - Detect code smells and produce refactoring roadmap

**Else if class is `code` (any source-code extension and not `deletion-dominated`/`lockfile-only`), spawn all 8 agents (existing behavior).**

**Else if class is `non-code` (no source files, not `lockfile-only` or `deletion-dominated`), spawn 4 agents:**

1. Task git-history-analyzer(PR content)
2. Task pattern-recognition-specialist(PR content)
3. Task security-sentinel(PR content) - Still needed: config/CI can expose secrets, markdown can contain code examples
4. Task code-quality-analyst(PR content) - Still needed: docs/config quality matters

Skipped for non-code PRs: architecture-strategist, performance-oracle, data-integrity-guardian, agent-native-reviewer. These agents analyze source code structure, runtime performance, database integrity, and agent accessibility — none are relevant to documentation, configuration, or CI changes.

**Else if class is `lockfile-only` or `deletion-dominated` (and override not detected), spawn 2 agents:**

1. Task git-history-analyzer(PR content) - Verify deletion/bump rationale matches cited PRs and issues
2. Task security-sentinel(PR content) - Lockfile bumps and bulk deletions can introduce supply-chain or removal-related risk

Skipped for `lockfile-only` / `deletion-dominated` PRs: pattern-recognition-specialist, code-quality-analyst, architecture-strategist, performance-oracle, data-integrity-guardian, agent-native-reviewer. Lockfile diffs and bulk deletions do not contain semantic patterns or quality regressions for the pattern/quality agents to find; architecture/perf/integrity/agent-native agents have no source code to analyze. Use `deep review` to force full pipeline.

Announce: "Change classified as **[code/non-code/deletion-dominated/lockfile-only]**. Spawning [N]/8 review agents. [If skipped agents: Skipped: <list> — not relevant to <class> changes. Use 'deep review' to force full pipeline.]"

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

**If the plan declares Brand-survival threshold as `single-user incident`:**

15. Task user-impact-reviewer(PR content + plan path) - Enumerate every user-facing failure mode implied by the diff and verify the plan's `## User-Brand Impact` section mitigates or scope-outs each

**When to run user-impact-reviewer:**

- The plan file referenced from the PR body contains literal text `Brand-survival threshold: single-user incident`
- The PR body itself contains a `## User-Brand Impact` section with that threshold label
- Either signal alone is sufficient to fire the agent — both signals fire it once (no duplicate invocation)

**What this agent checks:**

- `user-impact-reviewer`: Enumerates concrete user-facing artifacts exposed by the change (`user.email`, `workspace.name`, `api_key.token`, `conversation.id`, `message.body`, `billing.amount`, `oauth.installation_id`, etc.) AND a concrete exposure vector per artifact (cross-tenant read, RLS bypass, credential leak in logs, data loss on rollback, double-charge on retry, silent drop on degraded fallback). Rejects generic boilerplate (e.g., "users experience a bug", "error state", `TBD`/`TODO` placeholders). Coexists with security-sentinel — security-sentinel handles OWASP/CWE scanning across all PRs; user-impact-reviewer handles user-facing-outcome enumeration when the plan declares the brand-survival threshold as `single-user incident`.

**If the diff matches `hr-gdpr-gate-on-regulated-data-surfaces`:**

16. Skill gdpr-gate(diff + plan path) — Audit regulated-data design at review time, in addition to plan-phase and work-phase invocations. Self-invokes the same skill so reviewers see findings in PR review context.

**When to run gdpr-gate at review time:**

- `git diff main...HEAD --name-only | grep -E "$CANONICAL_REGEX"` returns at least one match (mirrored regex source: `plugins/soleur/skills/gdpr-gate/SKILL.md` §"Path globs (canonical)").

**What this agent checks:**

- `gdpr-gate`: Deterministic Art. 9 / RoPA / lawful-basis pattern checks. Output is advisory-only; Critical findings (Art. 9) escalate to operator-acknowledged write to `compliance-posture.md` Active Items + GitHub issue with label `compliance/critical`.

#### Boundary disambiguation — gdpr-gate vs. data-integrity-guardian vs. security-sentinel {#boundaries}

Use `gdpr-gate` for deterministic Art. 9 / RoPA / lawful-basis pattern checks; use `data-integrity-guardian` for migration safety and judgment-based PII review; use `security-sentinel` for OWASP/CWE security-of-processing flaws. The three reviewers complement each other and may all fire on the same PR — gdpr-gate scans for regulatory-design gaps, data-integrity-guardian scans for ID-mapping and value-swap migration risks, security-sentinel scans for OWASP/CWE vulnerabilities. This is the **canonical disambiguation prose**; sibling agent files reference back here as the single source of truth.

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

### 4.6. Build-step Gate Claim Verification

When a review agent claims that a build-step CI gate (e.g., post-Eleventy
`grep -rEn ... _site/`, post-Webpack chunk regex, post-`tsc` output scan)
will fail on rendered output, **rebuild the artifact directory BEFORE
running the gate locally**. Never run the gate against an existing
`_site/`, `dist/`, `build/`, or `.next/` from a prior session — those
predate the source change under review and return false-pass (zero
matches) even when the rendered output post-rebuild contains the flagged
strings.

The verification command order is non-negotiable:

```bash
<rebuild command> && <literal CI gate command>
```

Examples:
- Eleventy: `npx @11ty/eleventy --quiet && grep -rEn '<regex>' _site/`
- Next.js: `bun run build && grep -rEn '<regex>' .next/`

If the rebuild step is unfamiliar, read the corresponding `.github/workflows/`
job to find the exact build command the gate runs against — match it, do
not invent one. A stale-artifact false-pass is the most common dismissal
class for build-output gates (PR #3296 → #3347 hotfix). Treat any agent
finding of the form "rendered/built artifact X contains Y" as a
fresh-build-required claim by default.

### 5. Findings Synthesis and GitHub Issue Creation

<critical_requirement>
Each finding's default action is to FIX IT INLINE on the PR branch: make the edit,
commit with a message `review: <summary> (P<N>)`, and push. Apply to P1, P2, P3
equally.

**Cost-of-filing gate (apply BEFORE the four scope-out criteria below):** If the
fix is ≤30 lines of code AND touches ≤2 files AND no reviewer agent independently
dissents on technical grounds (e.g., contested-design with named alternatives),
fix inline. The bookkeeping cost of `gh issue create + scope-out justification +
future triage + closure + follow-up PR` averages ~30 minutes of cumulative
human attention; a ≤30-line code edit averages ~5 minutes. Filing the issue is
NET-NEGATIVE work for the team. This gate is load-bearing: a PR that opens
more issues than it closes is a workflow failure, not a normal review outcome.

The gate fails (fix-inline is required) when:
  - Fix is ≤30 lines AND ≤2 files, regardless of "feels like a follow-up" framing.
  - The only objection to fixing inline is bookkeeping/scope discipline (vs. a
    concrete technical contest the agent named).
  - The finding is `pr-introduced` (per Step 1 provenance triage) — these always
    fix inline.

The gate may pass (proceed to evaluate the four scope-out criteria) when:
  - Fix is >30 lines OR touches >2 files, AND
  - The fix demonstrably matches at least one of the four criteria below.

Filing a GitHub issue instead of fixing is allowed ONLY when both the cost-of-
filing gate above AND one of these four scope-out criteria are satisfied:

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
     Step 1 below — never applies to `pr-introduced` findings. Mirroring an
     existing brittle pattern "for symmetry" is exacerbation, not preservation:
     if `git diff origin/main...HEAD -- <file> | grep '^+' | grep <pattern>`
     returns ≥1 line, the criterion fails — fix inline. See
     `knowledge-base/project/learnings/2026-05-04-in-isolation-probe-missed-user-shape-and-scope-out-exacerbation.md`.**

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

**Write-time self-check:** Before invoking `gh issue create --label
deferred-scope-out`, scroll up in the conversation and confirm the most
recent `code-simplicity-reviewer` Task reply begins with `CONCUR` for THIS
finding. If no such Task exists in this conversation, or the reply begins
with anything other than `CONCUR`, STOP — invoke the agent first. Filing
first and co-signing second is a protocol violation even when the agent
eventually returns CONCUR; the gate exists for the DISSENT case, and
filing-first leaves a publicly-visible issue that has to be closed if the
agent dissents. See learning
`knowledge-base/project/learnings/best-practices/2026-05-05-extracted-bash-functions-need-self-contained-state.md`
Pattern 3.

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

**Pipeline detection (run BEFORE writing the summary):** Scan the conversation for `skill: soleur:work` or `skill: soleur:one-shot` output. If either is present, you are in **pipeline mode** — the calling orchestrator owns the lifecycle and is waiting on you to return so it can run step 5 / Phase 4. Emit the **compact progress marker** below instead of the verbose summary, then return immediately. Do NOT use the heading `## Code Review Complete`, do NOT include a `### Next Steps` section, and do NOT write a wrap-up sentence — those framings cause one-shot to mistake the summary for a turn boundary and stop mid-pipeline.

**Pre-emission cost-of-filing pass (run BEFORE the marker):** Build the
candidate "Filed as scope-out" list from your synthesis. For each candidate,
re-apply the cost-of-filing gate from §5:

  - Is the fix ≤30 lines AND ≤2 files? → Remove from the scope-out list; fix
    inline and add to "Fixed inline" instead.
  - Is the only objection bookkeeping ("feels like a follow-up", "not core to
    this PR") rather than a concrete technical contest? → Remove; fix inline.
  - Did `code-simplicity-reviewer` actually CONCUR on this specific item (not
    just on the batch)? Required even in pipeline mode. → If no CONCUR, fix
    inline.

Only items that survive ALL three checks appear in "Filed as scope-out". This
loop prevents the failure mode where pipeline mode rationalizes filing
≤30-line cleanup items because the marker template makes filing look like a
first-class option. **Target: the marker frequently shows "Filed as scope-out:
0".** A PR that nets +N issues from review is a workflow failure.

**Compact progress marker (pipeline mode):**

```markdown
## Review Phase Complete

- **Findings:** N total — N1 P1 / N2 P2 / N3 P3
- **Fixed inline:** N (commits: <sha>, <sha>, …)
- **Filed as scope-out:** N (#NNN, #NNN — criteria listed below)
- **Agents run:** <comma-separated list>

[Optional 1-line table of scope-out issues with criteria, if any.]
```

**Self-audit:** if the "Filed as scope-out" count exceeds 1 on a PR <500
lines, re-run the cost-of-filing pass above with a stricter posture before
emitting. The target is fewer-issues-opened than issues-closed, measured
across the team's PR throughput.

After emitting the marker, the calling skill's continuation gate takes over — control returns to one-shot step 5 / work Phase 4 in the SAME response.

**Direct invocation summary (interactive mode only — no `soleur:work` or `soleur:one-shot` in conversation):** Use the verbose summary template below.

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

**Pipeline detection:** If the conversation contains `skill: soleur:work` output earlier (indicating review was invoked by work's Phase 4 chain) or `soleur:one-shot` output (indicating review was invoked by one-shot step 4), skip the exit gate. The calling pipeline handles compound, commit, and lifecycle progression. When review is invoked by work or one-shot, do not duplicate these steps **and do not output the verbose `## Code Review Complete` block from Step 3** — the compact `## Review Phase Complete` marker (Step 3, pipeline mode) is the only output and the orchestrator's continuation gate handles progression. The verbose summary's `### Next Steps` block is the failure mode that causes orchestrators to mistake the report for a turn-ending deliverable.

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
- **Feature-wiring composition bugs** — module A is correct in isolation, module B is correct in isolation, but A+B together violate a constraint that lives in module C (downstream consumer, scheduler, taxonomy). Examples: `leaderId: "system"` reusing an internal taxonomy value whose UI semantics collide with router output; a `registry.reap()` method with no scheduler outside tests (tsc is silent on "never called in prod"); a nullable callback parameter the caller contract forbids but the implementer maps to a value that breaks invariants. Review prompts must enumerate the downstream consumer / scheduler / invariant explicitly for agents to reach it. See `knowledge-base/project/learnings/best-practices/2026-04-24-multi-agent-review-catches-feature-wiring-bugs.md`.
- **Runtime-content tamper between authoring and execution** — when a workflow fetches content (issue comment, file at remote URL, external service response) at fire/run time and acts on it, the gap between fetch-time integrity and execution-time mutability is a single-user-incident-class vector. "No inline prompts" prevents leak-via-committed-YAML; it does NOT prevent attacker-edits-the-source-between-create-and-fire. `user-impact-reviewer`'s "name artifact + name vector" mandate reliably surfaces this where simplicity-biased peer review at plan time does not. PR #3067 added D5 (commenter-author-pin + immutability-pin) after the 11-agent review caught the gap that 3-reviewer plan-time review missed. See `knowledge-base/project/learnings/2026-05-03-user-impact-reviewer-catches-runtime-content-tamper-vectors.md`.
- **Cross-stream format-contract drift in telemetry joins** — when a feature joins two telemetry streams (a producer and a consumer that look up by name), test fixtures that use a simplified shared format on both sides hide bugs where the producers actually emit different shapes (namespaced `"plugin:name"` vs bare `"name"`, dotted IDs vs slashed IDs, hashed keys vs raw keys). Review agents and unit tests both miss this because each side's tests look internally consistent. The defect surfaces only via a derived-metric counter (orphan rate, miss rate, fall-through rate) whose surprising value points back at the contract. PR #3124 surfaced a `soleur:plan` (hook) vs `plan` (inventory) mismatch only after the orphan-skill counter — added as polish — reported a non-zero count in production data. See `knowledge-base/project/learnings/2026-05-04-telemetry-join-format-mismatch-caught-by-orphan-counter.md`. Reviewer takeaway: when a PR adds a join across two streams, ask whether at least one fixture per side uses each producer's actual emission format, not a normalized placeholder.
- **Handshake schema drift between producer (skill) and consumer (file)** — when a skill instructs an operator to write a row/entry to a knowledge-base file, the producer's instruction template and the consumer's documented schema can drift in the same PR. Same column count + different semantics = silent table-corruption when followed verbatim. `data-integrity-guardian` catches this by reading both sides and comparing column-by-column. Reviewer takeaway: when a PR adds an instruction "write a row to file Y" alongside a schema documented in Y, grep Y's schema and assert the producer's row template matches column-by-column. Prefer reference-and-defer (instruction says "use the schema in Y") over embed-and-pray. PR #3501 shipped `gdpr-gate` with this exact drift; data-integrity-guardian flagged it as P1 pre-merge. See `knowledge-base/project/learnings/2026-05-10-handshake-schema-drift-and-stale-precondition-budgets.md`.
- **Replicated literals across ≥2 source files without parity test** — canonical regexes, schema strings, taxonomy IDs replicated across SKILL.md prose, hook scripts, test files, and config globs drift independently. Three reviewers in PR #3501 independently flagged a path-regex stored in 4 places. Reviewer takeaway: when a PR adds the same literal across ≥2 source files, expect a parity test (`expect(scriptContent.match(/^FOO='([^']+)'/)![1]).toBe(SOURCE_LITERAL)`). If absent, file as P2 inline-fix. Same learning file as above.
- **Self-claimed cross-artifact contract drift** — when a code/config file carries a comment, README line, or docstring claiming fidelity to another artifact (e.g., `globals.css: "Token names mirror brand-guide.md exactly"`, `schema.sql: "matches the TypeScript types in lib/types.ts"`), edits to either side can silently break the contract. Pattern-recognition, architecture, and code-quality reviewers approve the diff in isolation because each reads only the LOCAL file. Only an agent that reads BOTH files surfaces the contradiction. Reviewer takeaway: when the PR touches a file containing a "mirrors X" / "matches X" / "kept in sync with X" / "tracks X" self-claim comment, include in the review prompt: *"Read the named artifact X and verify the claim still holds post-diff."* Cheapest gate: `git diff origin/main...HEAD --name-only | xargs rg -l "(mirror|matches|kept in sync|tracks|reflects) (the )?(knowledge-base/|docs/|spec/)"` — every hit demands cross-artifact verification. PR #3556 (font normalization) shipped with the dashboard typography diverging from brand-guide.md; only git-history-analyzer caught it pre-merge. PR #3596 (Anthropic DPA row) confirmed an **implicit sub-pattern**: the grep above returns zero hits (no self-claim comment exists), but `compliance-posture.md`'s vendor-row framing still contradicted `docs/legal/gdpr-policy.md`'s public disclosure for the same vendor — only security-sentinel caught it. **Domain-specific gate:** for any diff under `knowledge-base/legal/`, the review prompt MUST instruct an agent to read `docs/legal/{gdpr,privacy}-policy.md` for the vendor name(s) in the diff and verify the diff's framing of vendor role / data flow / transfer mechanism agrees with the public disclosure. See `knowledge-base/project/learnings/2026-05-11-multi-agent-review-catches-cross-artifact-contract-drift.md`.
- **Vendor-pipeline trust-contract gaps (auto-PR-of-untrusted-bytes / tautological integrity / exit-code-as-result)** — when a PR establishes a new vendored-content pipeline (pinned upstream blob SHAs + scheduled drift workflow + integrity gate + severity classifier), four trust-model classes compose badly across the pipeline's boundary contracts: (1) auto-PR routing across security-relevant drift classes converts a detection signal into a write primitive (compromised upstream → bot-authored PR → review fatigue); (2) self-consistency integrity check (working-tree hash + frontmatter SHA both PR-author-mutable) is tautological — ask "what other thing must move to bypass this?"; (3) classifier that emits ONE exit-code result silently under-labels co-occurring categories (e.g., security + license drift in one upstream commit); (4) inline-Python/awk parsers with non-greedy or fragile tokenization can no-op silently when YAML formatting drifts. `user-impact-reviewer` names the adversary model; `data-integrity-guardian` runs the regex against the real input and produces the falsifying case. PR #3521 shipped all four; multi-agent review caught them pre-merge. Reviewer takeaway: for PRs establishing trust contracts, require (a) integrity check has at least one cross-domain anchor (CI-side `gh api` upstream verification, signed-commit, CODEOWNERS), (b) classifier emits multi-category stdout AND exit code, (c) auto-PR routing restricted to lowest-risk class only, (d) post-condition assertions on regex/awk substitutions (`subn` count == expected). See `knowledge-base/project/learnings/2026-05-11-multi-agent-review-vendor-pipeline-trust-model.md`.
- **Single-literal gate over a multi-member union/enum** — when a TypeScript predicate gates behavior on `X === <literal>` (or `!isFoo`, `status === "completed"`) and `X` is a union/enum with ≥ 3 members, the gate is correct only by coincidence unless every union member has been classified include/exclude in the originating FR. `user-impact-reviewer` and `pattern-recognition-specialist` reliably catch this **only when the review-spawn prompt explicitly enumerates the union members** — without the prompt, agents echo the plan's single-value framing as a false-pass. Reviewer takeaway: the review-spawn prompt MUST enumerate the union members literally — without that, agents echo the plan's single-value framing as a false-pass. Concretely: when reviewing a gate conditioned on `X === <literal>` where `X` is a TypeScript union/enum, grep the type's declaration (`rg "type X =" <module>` or `grep -nE "X = .*\|"`) and pass the resulting member list verbatim into the spawn prompt, then ask "is the gate correct for each value?" Single-literal gates against multi-member unions are a known defect class. **Why:** PR #3653 — plan §FR2 conditioned on `!isStreamingAssistant`; /work bound the gate to `streamState === "streaming"` while `StreamState = "idle" | "streaming" | "stopping"` (`ws-client.ts:47`). `"stopping"` is a distinct in-flight substate that mid-aborts traverse; a Stop click could have flashed the marker during that window. Caught only because the spawn prompt explicitly named the 3-value enum. See `knowledge-base/project/learnings/2026-05-12-plan-precondition-and-3-value-enum-gate-drift.md`.

See `knowledge-base/project/learnings/2026-04-15-multi-agent-review-catches-bugs-tests-miss.md` for the full pattern catalogue.

### Sharp Edges: Review Agent Limitations

Review agent suggestions that modify workflow `if` conditions or event filters must be smoke tested against the full user journey (not just the reduced trigger case) before shipping -- agents optimize locally and can break flows they don't fully model.

When a reviewer prescribes `--arg` for jq injection defense in a `gh ... --jq` context, verify the CLI forwards jq flags before implementing. `gh --jq` accepts a single expression string and does NOT forward `--arg`, `--argjson`, or `--slurp` to the underlying jq binary — applying the fix produces `unknown arguments` at runtime. Fall back to shape-validating the shell variable (e.g., `[[ "$VAR" =~ ^[0-9]+$ ]]`) before interpolation, or pipe to a second-stage standalone `jq --arg`. See `knowledge-base/project/learnings/2026-04-15-gh-jq-does-not-forward-arg-to-jq.md`.

Generalizing the rule above: whenever a review agent prescribes a CLI flag or subcommand as a fix (e.g., `gh issue create --json number`, `gh issue close --body-file`, `<tool> <subcommand> --<flag>`), verify the flag exists on that exact subcommand via `<tool> <subcommand> --help` BEFORE applying. Agents hallucinate flags by generalizing from sibling subcommands (`gh issue list` has `--json`, `gh issue create` does not). Cost of verification: one `--help` call. Cost of applying a non-existent flag: revert + rework + commit pollution. If the prescribed flag is absent, fall back to a verified pattern (split into two verified commands, parse output with `awk -F/`, etc.) and note the substitution in the disposition table. See `knowledge-base/project/learnings/best-practices/2026-04-19-verify-reviewer-prescribed-cli-flags-before-applying.md`.

When a single agent rates a finding P1/HIGH but no orthogonal agent independently surfaces the same harm, downgrade to advisory or skip. Single-agent HIGH against two-or-more silent or contradicting agents is the modal false-positive pattern. Cross-reconcile triad before applying: a **semantic-quality** agent (code-quality, pattern-recognition), an **orthogonal runtime** agent (performance-oracle for cache/sweep/eviction; data-integrity-guardian for type widening; security-sentinel for trust-surface claims), and **git-history-analyzer** for documented-intent context. Two-of-three concur on "non-issue" → skip with a one-line disposition. The HIGH rating is a hypothesis, not a verdict, and applying a "fix" for a non-issue often re-introduces the complexity the PR was designed to eliminate. See `knowledge-base/project/learnings/2026-05-12-multi-agent-review-cross-reconcile-catches-false-positive-high-findings.md` (PR #3670 — code-quality flagged a sweep-cutoff change as HIGH "doubles Sentry events"; performance-oracle + git-history-analyzer + dedup-trace independently falsified the claim; the proposed `staleTtlMs` parameter would have re-introduced the per-cache asymmetry the F3 extraction was designed to eliminate).

Parallel review batches can stall silently — spawning 12 review agents at once has been observed to produce completion notifications for only 6, with the remaining agents' transcripts frozen ~15s after spawn and no completion event emitted. When more than 30% of spawned agents stop producing output for >2 minutes after launch, proactively announce "N of M agents stalled" rather than silently waiting. Proceed with synthesis from the agents that returned — the Rate Limit Fallback gate already permits partial coverage. See `knowledge-base/project/learnings/2026-04-17-postgrest-aggregate-disabled-forces-rpc-option.md`.

When `code-simplifier` returns DISSENT on a bundled scope-out filing, do NOT argue back — read the dissent for the specific finding it cites, flip ONLY that finding inline, and re-run the CONCUR gate on the residual bundle. The gate exists precisely to catch bundling pathology where a single criterion (cross-cutting-refactor, contested-design) gets satisfied by the bundle as a whole while individual items inside it cross the ≤30-line/≤2-file cost-of-filing threshold. Filing the entire bundle inline (out of frustration with the dissent) is also wrong — the residual findings may legitimately scope out. Per-finding triage, not per-bundle. See `knowledge-base/project/learnings/2026-05-11-scope-out-bundling-hides-cheap-inline-fixes.md`.

Before reporting a broken link or missing file, reviewer agents MUST verify via Glob or Read. Unverified "broken link" claims waste reviewer-response cycles — the file may exist at the exact path. **Why:** PR #2226 pattern-recognition-specialist false-positive on a `runtime-errors/2026-02-13-...` learning file that did exist.

When a PR matches ALL of (a) plan reviewed by ≥3 agents at plan time, (b) implementation is verbatim plan execution (no scope creep), (c) diff is dominated by markdown/skill-prose with optional bash marker tests, and (d) no production code paths touched, operator MAY apply a focused 3-agent slice (`pattern-recognition-specialist`, `security-sentinel`, `code-simplicity-reviewer`) instead of the prescribed 8 with explicit deviation rationale in the classification announcement. The 4-class decision tree treats any source extension as `code`, but verbatim prose-plan PRs land in a sub-class where post-implementation review is mostly confirmation — design churn was absorbed at plan time. When in doubt, run the full 8. See `knowledge-base/project/learnings/2026-05-12-post-impl-review-value-asymmetry-for-verbatim-prose-plan-prs.md`.

When reviewing a Nunjucks/Eleventy page that pairs a visible HTML answer with a `FAPage`/`FAQPage` JSON-LD `acceptedAnswer.text`, compare the two surfaces character-for-character per Question. Google's FAQ rich-result parity check compares codepoints — flag (a) `{{ ... }}` interpolation in HTML paired with a hardcoded value in JSON-LD, and (b) HTML entities (`&rsquo;`, `&amp;`, etc.) in one surface and ASCII or `\uXXXX` in the other. See `knowledge-base/project/learnings/2026-04-18-faq-html-jsonld-parity.md`.

When flagging a skill description word-budget overrun, the tokenizer MUST match the CI gate. `plugins/soleur/test/components.test.ts` uses `desc.split(/\s+/).filter(Boolean).length` against the YAML value only (1800-word skill budget); the `grep -h 'description:' | wc -w` pattern in AGENTS.md belongs to the agent 2500-word budget and includes YAML framing, inflating counts by ~5 words per skill. Run `bun test plugins/soleur/test/components.test.ts` before reporting — if it passes, the budget is satisfied. See `knowledge-base/project/learnings/2026-04-19-skill-description-word-budget-tokenizer.md`.

When a review agent reports branch-scope regressions (claims the PR reverts merged commits, touches files outside the PR's linked issue/directory, or shows a file list materially larger than expected), verify with `git diff origin/main...HEAD --name-only` (three-dot) before accepting. Two-dot variants like `git diff main..HEAD` show commits on `main` since the fork point (NOT commits on HEAD) and produce wildly different file lists when the branch is behind main — a common agent failure mode that surfaces as a false-positive P0. See `knowledge-base/project/learnings/2026-04-22-markdown-table-parser-papercuts-and-review-diff-direction.md`.

When a review agent recommends ADDING a field, header, or schema element to a security-relevant surface (wire schema, redaction filter, log scrubber, error envelope), grep the diff scope for `// See #N` provenance comments referencing prior REMOVALS of the same artifact BEFORE applying the fix. A `Pn` rating reflects local severity; it does not auto-override deliberate cross-cutting decisions encoded in code comments. If a prior PR removed the field as a security/privacy mitigation, flip disposition to `contested-design` scope-out with the prior issue # named in the filing — code-simplicity-reviewer reliably co-signs when the threat-model context is surfaced. See `knowledge-base/project/learnings/2026-05-05-agent-native-recommendation-vs-prior-security-removal.md`.

ADRs documenting an *already-chosen-and-shipping* architecture fail `architectural-pivot` — the criterion requires the *fix itself* to change a cross-codebase pattern, and an ADR for the path you're already shipping is documentation work, not pattern-changing work. Inline-absorb ADRs of this shape (~1 markdown file under `knowledge-base/engineering/architecture/decisions/`) rather than scoping them out. Symmetric rule: when `code-simplicity-reviewer` DISSENTs by naming a *different* criterion that fits, re-file under that criterion (fresh concur cycle) rather than absorbing inline — the dissent is on the label, not on the underlying deferral. See `knowledge-base/project/learnings/2026-05-06-scope-out-criterion-misclassification-adr-not-architectural-pivot.md`.

When a reviewer prescribes ADDING a defensive wrapper (try/catch around an SDK call, a typeof guard, a validation step, a retry envelope) citing a single in-tree precedent, grep the same file/module for ≥3 sibling unwrapped invocations of the same primitive BEFORE applying. If precedent is consistent and the new code mirrors it, the wrapper recommendation is precedent-contradicting — reject with a one-line disposition citing the unwrapped sites. The cited precedent may be helper-internal (boot-path safety) and not generalize to call-site code. Cost of verification: one grep. Cost of applying a precedent-contradicting wrapper: a commit that future reviewers will roll back when they apply the same heuristic. See `knowledge-base/project/learnings/2026-05-05-phase-1-instrumentation-when-prior-fix-visibly-missed.md` (#3287 review's false-positive P1 on a `Sentry.addBreadcrumb` call that mirrored 5 in-file precedents).

When a PR introduces a shell wrapper (`with_lock`, `with_lease`, `flock --`, etc.) around a command intercepted by a PreToolUse hook, MUST verify the hook's command-detection regex matches the wrapped form before approving. Cheapest gate: extract the literal `matcher` regex from each `.claude/hooks/*.sh` for the wrapped command, then `echo "$WRAPPED_FORM" | grep -qE "$REGEX" || echo BYPASS`. Hooks anchored to `^|&&|\|\||;` (start-of-line / chain operators) silently bypass when the wrapped form puts the command after a `--` separator inside another argv. The bypass is INVISIBLE in normal review flow because the hook still runs (it just exits 0 without firing) and the wrapped command executes normally. **Why:** PR #3689 — `bash session-state.sh with_lock merge-main 600 -- gh pr merge --squash --auto` silently bypassed `pre-merge-rebase.sh`'s review-evidence gate AND auto-sync, caught only by 11-agent post-implementation review. See `knowledge-base/project/learnings/2026-05-12-cross-session-lock-lease-bash-primitives.md` (SE1).

### Important: P1 Findings Block Merge

Any **P1 (CRITICAL)** findings must be addressed before merging the PR. Present these prominently and ensure they're resolved before accepting the PR.
